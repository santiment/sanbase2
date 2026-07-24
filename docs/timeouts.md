# Request-path timeouts

Every timeout a user request can hit, ordered from the outside in. "Budget"
is how long that layer allows before it gives up; a request dies at the first
layer whose budget it exhausts.

| # | Layer | Budget | Where configured | What happens on timeout |
|---|-------|--------|------------------|-------------------------|
| 0 | Load balancer / ingress | **unverified** | infra, outside this repo | client gets 502/504; the BEAM keeps computing |
| 1 | Cowboy `idle_timeout` | 120s (web), 180s (mcp) | `config/runtime.exs` | connection closed; the BEAM keeps computing |
| 2 | Absinthe document execution | none | — | no global cap; a query runs as long as its slowest field |
| 3 | GraphQL cache lock wait | 102s, then **fallback** | `CachexProvider` `@lock_wait_timeout_ms` | waiter logs a warning and computes the value itself, without the lock — no user-facing error (should no longer trigger: the lock holder's work is bounded by the 100s CH budget) |
| 4 | Absinthe async middleware (`async/1` resolvers) | 105s | `Helpers.Async` `@async_timeout_ms` | `Task.await` exit → **500 internal error** (should no longer trigger: CH gives up first at 100s) |
| 5 | Dataloader batches | 35s (PG source), 105s (KV/CH source) | per-source `timeout:` in `sanbase_repo.ex` / `sanbase_dataloader.ex` | batch killed; dataloader-backed fields resolve to nil (`:return_nil_on_error`) (should no longer trigger: the wrapped queries give up first) |
| 6 | Postgres (`Sanbase.Repo`) | queue 5s/10s, query 30s | `config/config.exs` | `DBConnection.ConnectionError` raise |
| 7 | ClickHouse read-write (`ClickhouseRepo`) | queue 10s/30s, query 100s | `config/config.exs` | rescued → `{:error, message}` (see below) |
| 8 | ClickHouse read-only per-plan repos | queue 10s/30s, query 100s | `config/config.exs` | rescued → `{:error, message}` |
| 9 | Generic ConCache locks (`Sanbase.Cache`) | 102s (web), 120s (alerts) | `application.ex`, `alerts.ex` | `GenServer.call` exit → 500 |
| 10 | External HTTP inside resolvers (Tesla/Hackney, parity) | 25–30s recv | `config/config.exs` | client error tuple, resolver-specific |

Deploy-time only: `ConnectionDrainer` waits up to 30s for in-flight requests.

The web chain is ordered so every inner budget is smaller than the outer one
that contains it:

    LB (verify: must be > 120s) > cowboy 120s > async resolvers 105s
      > cache-lock wait 102s > CH query 100s > PG query 30s > external HTTP 30s

Note the cache-lock waits sit *above* the CH budget on purpose. Containment
budgets (cowboy, async) bound work they contain, so outer > inner. A lock
wait instead waits on a *peer's* work: it must exceed the peer's budget
(CH 100s), otherwise the waiter gives up precisely when the holder is slow —
and then recomputes a slow value with even less remaining budget.

MCP containers have their own chain (long-running AI tool calls):

    cowboy 180s > Anubis request_timeout 150s > task work 120s

## How timeouts surface to users

- **ClickHouse errors** are rescued in `Sanbase.ClickhouseRepo` and returned
  as `{:error, "[log_id] message"}`. Timeout-class errors (DBConnection queue
  drops, query timeouts, ClickHouse `TIMEOUT_EXCEEDED`/`Code: 159`) return a
  meaningful message telling the user the query ran too long and to request
  fewer fields/subqueries, narrow the time range or increase the interval —
  instead of the generic masked message. Everything is still logged in full
  under the `log_id`.
- **Cache lock waits** never produce a user-facing error anymore: after 102s
  the waiter computes the value itself (duplicate work, correct result). Since
  the wait outlasts the CH budget bounding any live holder, and leaked locks
  are released instantly by the monitor guard, this fallback should only fire
  in anomalous states. The old provider raised
  `"Obtaining cache lock failed because of timeout"` here — 8.8k Sentry
  events / 157 users since Oct 2024 (SANBASE-BACKEND-PROD-8).
- **Async resolvers** (`Helpers.Async.async/1`, 9 call sites) get 105s —
  more than the CH query budget — so a slow CH query surfaces its
  `{:error, timeout message}` instead of the Task exit becoming a 500.
- **Dataloader batches** get 105s (KV/CH source) and 35s (Ecto/PG source)
  for the same reason: the wrapped queries are allowed 100s/30s. The
  timeouts sit on the *sources* because Dataloader ignores the loader-level
  `Dataloader.new(timeout:)` option entirely — its run timeout is
  max(source timeouts) + 1s. The old loader-level 20s was a no-op: the
  effective budgets were the library defaults, 15s (Ecto) and 30s (KV),
  silently nil-ing out CH-backed fields while their queries kept running.
- **Postgres timeouts** still surface as 500s
  (`DBConnection.ConnectionError`).

## Remaining action items and rough edges

1. **Load balancer budget (#0) is unverified.** The whole chain assumes the
   LB allows more than cowboy's 120s. Verify the ingress read/send timeouts
   (nginx ingress: `proxy-read-timeout`/`proxy-send-timeout`, in seconds) and
   set them to ≥ 150s so cowboy — not the LB — is the outermost
   application-visible layer. Until verified, a >LB-budget request shows the
   user a 502/504 while the BEAM finishes work nobody receives.
2. **Generic ConCache locks (#9) still exit with a 500** when the wait
   timeout fires. Raising it to 102s (above the CH budget) means it no longer
   fires for a holder bounded by a single CH query, and ConCache's lock
   process monitors holders, so a brutally-killed holder releases its lock
   immediately — no leak. The remaining exposure is a holder that
   legitimately computes past 102s (e.g. several sequential CH queries under
   one lock): waiters then exit with a 500 instead of falling back to
   computing, the way CachexProvider does. Porting that fallback to
   `Sanbase.Cache` would remove this error class entirely.
3. **Absinthe has no per-document budget (#2).** A document with many
   independent 100s fields can, in principle, run for several multiples of
   any single budget across sequential resolution phases. Cowboy (120s) just
   closes the connection; the BEAM keeps computing. Complexity limits — not
   timeouts — are the lever if this becomes a problem in practice.

## History (fixed)

- **Old cache-lock behavior**: the previous provider waited ~52s
  (30 exponential-backoff attempts) and then raised. Two triggers: a lock
  holder legitimately computing longer than 52s (CH allows 100s), and leaked
  locks — a brutally-killed request (client disconnect) skipped `after`, and
  the old Unlocker janitor only released the lock after 60s, longer than any
  waiter's 52s budget, so every waiter on a leaked key errored. The new
  provider releases leaked locks instantly (monitor-based guard), lets
  waiters return as soon as the cached value lands, and falls back to
  computing after 60s instead of raising.
- **CH query 100s == cowboy 100s**: the connection could die at the exact
  moment the query finished. Web cowboy is now 120s.
- **Async middleware killed resolvers at 30s** while the CH work they wrap
  was allowed 100s — the Task exit became a 500 with no meaningful message.
  Now 105s via `Helpers.Async`.
- **Dataloader loader-level timeout was a no-op**: `Dataloader.new(timeout:)`
  is never read by `Dataloader.run/1` — it derives its timeout from the
  sources. The effective budgets were the library defaults (Ecto 15s, KV
  30s), both far below the queries they wrap (PG 30s, CH 100s): batches were
  killed (fields nil'd out) while their queries kept running server-side.
  Now 35s/105s, configured on the sources where the library actually reads
  them.
- **Cache-lock waits (60s) < CH budget (100s)**: waiters gave up on the lock
  exactly when the holder was slow, then recomputed the same slow value with
  only ~45s of async budget left — guaranteed dead work, killed at 105s.
  Both lock waits are now 102s, above the CH budget that bounds any live
  holder.
- **Per-plan CH repos queued 60s + 60s** before the 100s query even started —
  worst case ~220s, far beyond any outer layer. Under pool saturation users
  waited minutes and still got nothing. Now queue 10s/30s like the
  read-write repo: overload sheds fast, and queue drops return the
  user-facing timeout message.

## When touching any of these

Keep the chain ordered: every inner budget should be smaller than the outer
budget that contains it, with margin for the response to travel out. The
worst failure mode is an inner layer that outlives the outer one — work whose
result can never be delivered.
