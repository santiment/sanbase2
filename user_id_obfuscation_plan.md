# User ID Obfuscation: Migration Plan

## Problem

User IDs are currently sequential auto-incrementing integers (`bigint`).
Public GraphQL accepts and returns integer user IDs in multiple places, which
makes user enumeration practical (`id=1,2,3...`) and leaks user cardinality.

## Goals

1. Stop practical user enumeration as early as possible.
2. Preserve internal DB model (`users.id bigint` + existing FK graph).
3. Migrate clients without a hard outage.
4. Remove integer user IDs from the public API surface after deprecation.

## Non-Goals

- Do **not** change `users.id` primary key type.
- Do **not** migrate 48 FK columns to UUID.
- Do **not** change internal joins/jobs to use UUID.

---

## Design Decision: UUID `public_id` Column

Add `users.public_id` (`uuid`) and treat it as the only external user identifier.

- Internal storage/joins: `users.id` (integer) remains canonical.
- External API: use `public_id` (UUID string).
- API boundary resolves `public_id -> id` once, then uses integer IDs internally.

### Why UUID over alternatives

| Approach | Rejected because |
|---|---|
| **Sqids/Hashids** | Not cryptographically secure. Sqids FAQ itself warns against using it for user IDs. Determined attacker can reverse-engineer the alphabet. |
| **Feistel Cipher** | Good security but requires PostgreSQL triggers, adds operational complexity. Less standard than UUIDs. |
| **Optimus** | No Elixir library. Output is still an integer (looks guessable even if it isn't). |
| **Relay Node IDs** | Base64(`User:123`) is trivially decoded. Security through obscurity only. |
| **Change PK to UUID** | Would require migrating all 48 FK columns across the database. Massive blast radius, high risk. |

**UUID column wins because:**
- True non-enumerability (128-bit random space)
- Zero changes to foreign keys — internal joins stay on integer PK (fast)
- Standard approach used by Shopify, Buildkite, GitHub
- Built-in Ecto support (`Ecto.UUID`)
- UUIDv7 (time-ordered) for better index locality. Note: v7 embeds a
  millisecond timestamp, which leaks approximate user creation time — acceptable
  tradeoff since `inserted_at` is already exposed on the user type.
- Reversible — if something goes wrong, drop the column

### External API Contract (final)

- Canonical external field: `publicId`.
- Integer `id` on `:public_user` and `:user` is deprecated, then removed.
- We **do not** rename `publicId` back to `id` later (avoids a second client migration).

---

## Why Foreign Keys Don't Need to Change

This is the key insight that makes the entire migration feasible:

```
                    API BOUNDARY
                        |
  [Browser/Svelte]  <-- | -->  [GraphQL Resolvers]  -->  [Ecto/DB]
                        |
  sees: public_id       |      translates:               uses: integer id
  (UUID string)         |      public_id -> id           (bigint PK/FK)
```

Foreign keys across all 48 tables reference `users.id` (the integer PK). The new
`users.public_id` column is **not referenced by any FK**. It's a lookup column
with a unique index, used only for API-boundary translation.

The translation happens once per request in the resolver:

```elixir
# Incoming: public_id (UUID)  ->  Lookup: users WHERE public_id = ?  ->  Get: integer id
# From here on, everything is integer-based internally
```

No other table needs a new column. No FK migrations. No reindexing.

---

## Scope Inventory (Must Be Covered)

The migration must cover all public GraphQL entry points that currently accept
or expose integer user IDs. Verified against the codebase on 2026-03-13.

### User type fields exposing integer IDs

| Type | Field | File | Line |
|---|---|---|---|
| `:public_user` | `field(:id, non_null(:id))` | `user_types.ex` | 61 |
| `:user` | `field(:id, non_null(:id))` | `user_types.ex` | 175 |
| `:user_follower` | `field(:user_id, non_null(:id))` | `user_types.ex` | 502 |
| `:user_follower` | `field(:follower_id, non_null(:id))` | `user_types.ex` | 503 |
| `:user_trigger` | `field(:user_id, :integer)` | `user_trigger_types.ex` | 10 |
| `:upvote` | `field(:user_id, :integer)` | `timeline_event_types.ex` | 57 |

### Query/mutation args accepting integer user IDs

| Endpoint | Arg | File |
|---|---|---|
| `follow` | `user_id: non_null(:id)` | `user_queries.ex` |
| `unfollow` | `user_id: non_null(:id)` | `user_queries.ex` |
| `following_toggle_notification` | `user_id: non_null(:id)` | `user_queries.ex` |
| `mute_user_notifications` | `user_id: non_null(:id)` | `app_notification_queries.ex` |
| `unmute_user_notifications` | `user_id: non_null(:id)` | `app_notification_queries.ex` |
| `all_insights_for_user` | `user_id: non_null(:integer)` | `insight_queries.ex` |
| `all_insights_user_voted` | `user_id: non_null(:integer)` | `insight_queries.ex` |
| `public_triggers_for_user` | `user_id: non_null(:id)` | `user_trigger_queries.ex` |
| `get_user_queries` | `user_id: :integer` (optional) | `queries_queries.ex` |
| `get_user_dashboards` | `user_id: :integer` (optional) | `queries_queries.ex` |
| `chart_configurations` | `user_id: :integer` (optional) | `chart_configuration_queries.ex` |
| `table_configurations` | `user_id: :integer` (optional) | `table_configuration_queries.ex` |

### Authenticated mutations with integer user IDs

| Endpoint | Arg | File |
|---|---|---|
| `generate_linked_user_token` | `secondary_user_id: non_null(:integer)` | `linked_user_queries.ex` |
| `remove_primary_user` | `primary_user_id: non_null(:id)` | `linked_user_queries.ex` |
| `remove_secondary_user` | `secondary_user_id: non_null(:id)` | `linked_user_queries.ex` |

### Admin/internal endpoints (BasicAuth-protected, lower priority)

| Endpoint | Arg/Field | File |
|---|---|---|
| `get_events_for_users` | `users: non_null(list_of(:id))` | `intercom_queries.ex` |
| `:user_attribute` | `field(:user_id, :id)` | `intercom_types.ex` |
| `:user_event` | `field(:user_id, :id)` | `intercom_types.ex` |
| `:api_metric_distribution_per_user` | `field(:user_id, :id)` | `intercom_types.ex` |

### Verified clean (no changes needed)

These types properly use nested `:public_user` objects instead of raw integer IDs:
`:post`, `:comment`, `:user_list`, `:dashboard`, `:sql_query`,
`:chart_configuration`, `:table_configuration`, `:timeline_event`.

---

## Phase 0: Immediate Risk Reduction (same release window)

Apply before full client migration is complete.

1. Add rate limits for `getUser` and other public user-scoped queries.
2. Add telemetry counters for every integer-id argument/field usage.
3. Add structured deprecation logs (operation name + client metadata).
4. Restrict high-risk selectors:
   - `getUser(selector: {id})`: deprecate immediately; optionally block for
     anonymous users first.
   - Reassess `selector.email` exposure (keep only if explicitly required;
     otherwise auth-gate or remove).

**Success criteria:**
- Integer-id traffic is measured for every relevant operation.
- Anonymous high-rate enumeration attempts are throttled.

---

## Phase 1: Database Migration (safe, race-free)

### Step 1.1: Add column with default for concurrent safety

A single migration that adds the column AND sets the DB default, so any user
created during backfill automatically gets a `public_id`:

```elixir
defmodule Sanbase.Repo.Migrations.AddPublicIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :public_id, :uuid, null: true, default: fragment("gen_random_uuid()")
    end
  end
end
```

### Step 1.2: Backfill existing rows

Run idempotent batch backfill (mix task or Oban worker). Safe to re-run — only
touches rows where `public_id IS NULL`:

```elixir
import Ecto.Query

from(u in "users", where: is_nil(u.public_id), select: u.id)
|> Sanbase.Repo.all()
|> Enum.chunk_every(1000)
|> Enum.each(fn ids ->
  Sanbase.Repo.query!(
    "UPDATE users SET public_id = gen_random_uuid() WHERE id = ANY($1) AND public_id IS NULL",
    [ids]
  )
end)
```

### Step 1.3: Enforce uniqueness and non-null

Separate migrations after backfill is confirmed complete. Create the unique
index concurrently to avoid locking the table:

```elixir
defmodule Sanbase.Repo.Migrations.AddPublicIdUniqueIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create unique_index(:users, [:public_id], concurrently: true)
  end
end
```

Then enforce NOT NULL (after verifying zero NULLs remain):

```elixir
defmodule Sanbase.Repo.Migrations.EnforcePublicIdNotNull do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :public_id, :uuid, null: false, default: fragment("gen_random_uuid()")
    end
  end
end
```

### Step 1.4: Update Ecto schema and add lookup functions

In `lib/sanbase/accounts/user.ex`, add the field to the schema:

```elixir
schema "users" do
  # existing fields...
  field :public_id, Ecto.UUID  # new — DB default handles generation
end
```

Add lookup function following the existing `by_id/2` pattern:

```elixir
def by_public_id(public_id, opts \\ []) do
  preloads = Keyword.get(opts, :preload, @preloads)

  result =
    from(u in __MODULE__, where: u.public_id == ^public_id, preload: ^preloads)
    |> Repo.one()

  case result do
    nil -> {:error, "User with public_id '#{public_id}' not found"}
    user -> {:ok, user}
  end
end
```

Extend `by_selector/2` with a new clause:

```elixir
def by_selector(%{public_id: public_id}, opts), do: by_public_id(public_id, opts)
# Keep existing clauses for id, email, username, twitter_id
```

---

## Phase 2: Dual-Read API Migration (backward compatible)

### Step 2.1: Expose `publicId` on user types

In `lib/sanbase_web/graphql/schema/types/user_types.ex`:

```elixir
# In :public_user object
field :public_id, non_null(:string)
field :id, non_null(:id), deprecate: "Use publicId instead"

# In :user object
field :public_id, non_null(:string)
field :id, non_null(:id), deprecate: "Use publicId instead"
```

At this point, API responses include both `id` (integer, deprecated) and
`publicId` (UUID).

### Step 2.2: Update `user_selector_input_object`

```elixir
input_object :user_selector_input_object do
  field(:id, :id)              # existing — keep temporarily, deprecated
  field(:public_id, :string)   # new
  field(:email, :string)       # existing
  field(:username, :string)    # existing
end
```

### Step 2.3: Add parallel UUID arguments to mutations

For every endpoint listed in the Scope Inventory, add a parallel `_public_id`
argument. Example pattern for `follow`:

```elixir
# Before
field :follow, :user do
  arg(:user_id, non_null(:id))
  middleware(JWTAuth)
  resolve(&UserFollowerResolver.follow/3)
end

# After
field :follow, :user do
  arg(:user_id, :id)              # now optional, deprecated
  arg(:user_public_id, :string)   # new, also optional
  middleware(JWTAuth)
  resolve(&UserFollowerResolver.follow/3)
end
```

Apply the same pattern to all endpoints in the inventory: `unfollow`,
`following_toggle_notification`, `mute_user_notifications`,
`unmute_user_notifications`, `all_insights_for_user`, `all_insights_user_voted`,
`public_triggers_for_user`, `get_user_queries`, `get_user_dashboards`,
`chart_configurations`, `table_configurations`, `generate_linked_user_token`,
`remove_primary_user`, `remove_secondary_user`.

Shared resolver helper to resolve either ID type:

```elixir
defp resolve_user_id(%{user_id: id}) when not is_nil(id) do
  Logger.warning("Deprecated: integer user_id argument used",
    field: "user_id", value: id)
  {:ok, Sanbase.Math.to_integer(id)}
end

defp resolve_user_id(%{user_public_id: public_id}) when not is_nil(public_id) do
  case User.by_public_id(public_id) do
    {:ok, user} -> {:ok, user.id}
    error -> error
  end
end

defp resolve_user_id(_), do: {:error, "Provide either user_id or user_public_id"}
```

### Step 2.4: Migrate type fields that expose integer user IDs

**`:user_follower`** — add UUID fields, deprecate integer fields:

```elixir
object :user_follower do
  field(:user_id, non_null(:id), deprecate: "Use userPublicId")
  field(:follower_id, non_null(:id), deprecate: "Use followerPublicId")
  field(:user_public_id, :string)       # resolved from user relation
  field(:follower_public_id, :string)   # resolved from user relation
  field(:is_notification_disabled, :boolean)
  field(:user, :public_user)
end
```

**`:user_trigger`** — replace `user_id` with `user_public_id`:

```elixir
object :user_trigger do
  field(:user_id, :integer, deprecate: "Use userPublicId")
  field(:user_public_id, :string)  # resolved from :user relation
  field(:user, :public_user)       # already exists
  field(:trigger, :trigger)
  # ...
end
```

**`:upvote`** — replace `user_id` with `user_public_id`:

```elixir
object :upvote do
  field(:user_id, :integer, deprecate: "Use userPublicId")
  field(:user_public_id, :string)  # resolve from user lookup
end
```

### Step 2.5: Deprecation instrumentation

Instrument all deprecated integer paths (not just `getUser(selector.id)`).
Track by operation name and client metadata. This telemetry drives the
Phase 3 deprecation deadline.

**Success criteria:**
- FE and known API consumers can operate using only `publicId` / `..._public_id`.
- Integer-id usage trend is near zero and observable via telemetry.

---

## Phase 3: Frontend and Consumer Cutover

Frontend changes (Svelte + external consumers):

1. Request `publicId` on all user payloads; stop using `id`.
2. Use `publicId` (or `userPublicId`) in all mutation/query arguments.
3. Remove dependency on integer user IDs in app state, cache, local storage.
4. Update URL routing (e.g. `/profile/123` -> `/profile/<uuid>`). Keep integer
   routes resolving during transition.
5. Update any hardcoded user IDs (admin accounts, test fixtures).

Operationally:

- Announce deprecation date.
- Keep a hard deadline (e.g. 60-90 days) based on telemetry.
- JWT `sub` claim continues storing integer ID — it's opaque to the client.

---

## Phase 4: Security Cutover and Cleanup

After deprecation window and telemetry confirmation:

1. Remove integer `id` field from `:public_user` and `:user` types.
2. Remove `selector.id` from `user_selector_input_object`.
3. Remove all deprecated integer user-id args listed in Scope Inventory.
4. Remove `user_id` from `:user_trigger`, `:upvote`, `:user_follower` types.
5. Remove dual-resolution helpers and deprecation logging.
6. Migrate admin/internal endpoints (intercom types) — lower priority, can be
   done in a follow-up.
7. Keep internal DB integer IDs unchanged.

**Success criteria:**
- No public GraphQL path accepts integer user IDs.
- No public GraphQL user object exposes integer user IDs.

---

## What Does NOT Change (Out of Scope)

| Component | Why it stays |
|---|---|
| **Database primary key (`users.id`)** | Changing PK type on a table with 48 FK references is extremely high risk. Integer PKs are faster for joins. |
| **All `user_id` FK columns** (48 tables) | FKs reference the integer PK internally. UUID is only for the API boundary. |
| **JWT `sub` claim** | Opaque to the client. Guardian resolves it server-side. |
| **Internal Ecto queries** | All `Repo.get(User, id)`, `where: u.id == ^user_id` continue using integers. |
| **Oban jobs, Kafka messages** | Server-to-server, never exposed to end users. |
| **DB indexes on FK columns** | Continue working on integers. No reindexing needed. |
| **Dataloader `:users_by_id`** | Internal batching mechanism, keyed by integer ID. No change needed. |

---

## Testing Plan

### Migration tests

- Backfill idempotency: re-running only touches `NULL` rows.
- Concurrent user creation during backfill receives `public_id` via DB default.
- Unique index rejects duplicate UUIDs.
- NOT NULL constraint holds after enforcement.

### GraphQL tests

- `getUser(selector: {publicId: "..."})` returns the correct user.
- All dual-arg endpoints accept the UUID path and reject when both old/new args
  are provided simultaneously.
- Deprecated integer paths still work during Phase 2-3 and emit telemetry.
- Post-cleanup (Phase 4): integer paths return clear errors.
- `:user_trigger`, `:upvote`, `:user_follower` types return `userPublicId`.

### Regression tests

- Existing auth/JWT/internal flows continue using integer IDs.
- Access-control behavior for user-scoped queries remains unchanged.
- Dataloader batch loading still works on integer IDs.
- `follow`/`unfollow` mutations work with both ID formats during transition.

---

## Observability

- **Telemetry counters:** per-operation calls using legacy integer args.
- **Structured logs:** operation name + client metadata on deprecated paths.
- **Metrics:** errors by selector type (`id` / `public_id` / `email` / `username`).
- **Alerts:** alert if legacy usage increases after FE cutover.
- **Rollback path:** The dual-ID support in Phase 2 is itself the rollback
  mechanism. If Phase 4 cleanup causes issues, revert the cleanup commit to
  re-enable integer paths — no DB rollback needed.

---

## Performance Notes

- **UUID index**: One additional B-tree index on `users.public_id` (~16 bytes per
  row). Negligible for typical user counts (< 10M).
- **Extra lookup**: One unique-index lookup (`SELECT id FROM users WHERE public_id = ?`)
  per incoming request using `public_id`. Effectively O(1). Can be cached in
  ETS/Cachex for hot paths if needed.
- **No JOIN impact**: All joins continue using integer PKs.

---

## Timeline

| Phase | Duration | Dependencies |
|---|---|---|
| **Phase 0**: Rate limits + telemetry | 1-2 days | None |
| **Phase 1**: DB migration + backfill | 1 sprint | None (parallel with Phase 0) |
| **Phase 2**: Dual-ID API support | 1 sprint | Phase 1 |
| **Phase 3**: Frontend cutover | 1-3 sprints | Phase 2, FE team availability |
| **Phase 4**: Cleanup | 1 sprint | 60-90 day deprecation window after Phase 3 |

Security impact starts in **Phase 0** (rate-limits + visibility) and materially
improves in **Phase 2/3** as integer paths are drained, with full closure in
**Phase 4**.

---

## References

- [Buildkite: Goodbye Integers, Hello UUIDv7](https://buildkite.com/resources/blog/goodbye-integers-hello-uuids/)
- [Shopify Global IDs](https://shopify.dev/docs/api/usage/gids)
- [Stripe ID Design](https://gist.github.com/fnky/76f533366f75cf75802c8052b577e2a5)
- [Lessons Learned Converting IDs to UUIDs](https://www.codewithjason.com/lessons-learned-converting-database-ids-uuids/)
- [OWASP IDOR Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Insecure_Direct_Object_Reference_Prevention_Cheat_Sheet.html)
- [Sqids FAQ (why not for user IDs)](https://sqids.org/faq)
- [Feistel Cipher for Elixir](https://elixirforum.com/t/feistelcipher-ashfeistelcipher-encrypted-integer-ids-using-feistel-cipher/72880)
