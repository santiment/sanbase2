# Security Remediation Plan — Sanbase2

Source: security review on branch `security-review` (2026-06-10). Threat model: external/anonymous and low-privilege authenticated users compromising the system.

Each item has: severity, confidence, exact location, why it matters, and concrete fix steps. Work top-to-bottom. Items are independent unless noted. After each fix, run `mix compile` and the relevant tests before moving on.

Legend — Severity: Critical > High > Medium > Low. Confidence: high / medium (how sure the finding is real).

---

## P0 — Fix first (externally reachable, confirmed)

### SEC-1 — `<iframe src>` sanitizer bypass (stored content-injection / XSS)
- **Severity:** High (Critical if frontend renders the field as HTML) — **Confidence:** high
- **File:** `lib/sanbase/utils/html_subset_scrubber.ex:58`
- **Problem:** `iframe` is allowlisted with `Meta.allow_tag_with_these_attributes("iframe", ["src"])`, which does **not** scheme-check the URL. Every other URL tag in the file uses the scheme-checked macro. This scrubber backs the `:sanitized_html_subset_string` scalar used by `Post.text`, `Post.short_desc`, `Post.pulse_text`, `Comment.content` — all public, externally-created content. An attacker can store `<iframe src="javascript:...">`, `<iframe src="data:text/html,...">`, or `<iframe src="https://evil">` and it survives sanitization.
- **Fix (preferred):** Remove the iframe allowlist line entirely. There is no legitimate need for user-submitted iframes.
  ```elixir
  # DELETE line 58:
  Meta.allow_tag_with_these_attributes("iframe", ["src"])
  ```
- **Fix (if iframes must stay, e.g. embeds):** Scheme-restrict and ideally host-restrict:
  ```elixir
  Meta.allow_tag_with_uri_attributes("iframe", ["src"], ["http", "https"])
  ```
  Note: even http/https iframes allow arbitrary external embedding (phishing/clickjacking). Prefer removal; if embeds are a product feature, allowlist specific hosts at the application layer.
- **Test:** Add a scrubber test asserting `<iframe src="javascript:alert(1)">` and `<iframe src="data:...">` are stripped. Check `test/` for existing scrubber/insight sanitization tests and extend them.

### SEC-2 — Presigned S3 URL IDOR (cross-user object read)
- **Severity:** High — **Confidence:** high
- **Files:** `lib/sanbase/presigned_s3_url/presigned_s3_url.ex:49-63`, `lib/sanbase_web/graphql/resolvers/presigned_s3_url_resolver.ex:4-11`, schema `lib/sanbase_web/graphql/schema/queries/presigned_s3_url_queries.ex`
- **Problem:** `getPresignedS3Url(object:)` takes a fully attacker-controlled key. On a DB miss it signs a GET URL for **any** key in the shared `api-users-datasets` bucket — no per-user prefix / ownership check. Any authenticated (even free) user can read another user's dataset object if they know/guess the key.
- **Fix:** Enforce a per-user key prefix in `get_presigned_s3_url/2` before signing. First confirm the real key naming convention used when objects are written to this bucket (grep for where objects are uploaded / how keys are generated — search `api-users-datasets`, `generate_presigned_url`, dataset export code). Then:
  ```elixir
  def get_presigned_s3_url(user_id, object) do
    if allowed_object?(user_id, object) do
      # ... existing body ...
    else
      {:error, "You are not allowed to access this object."}
    end
  end

  # Adjust the prefix to match the ACTUAL key convention used on write.
  defp allowed_object?(user_id, object) when is_binary(object) do
    String.starts_with?(object, "#{user_id}/") or
      String.starts_with?(object, "users/#{user_id}/")
  end
  defp allowed_object?(_user_id, _object), do: false
  ```
- **Important:** Do not guess the prefix — verify it against the write path first. If keys are not user-scoped today, the real fix is an ownership table / explicit allowlist. Coordinate before changing.
- **Test:** Assert a user requesting an object outside their prefix gets an error and no `generate_presigned_url` call happens.

### SEC-3 — Public-dashboard cache poisoning
- **Severity:** High — **Confidence:** high
- **Files:** `lib/sanbase/dashboards/dashboard/dashboard.ex:181-189` (`get_for_cache_update`), resolver `lib/sanbase_web/graphql/resolvers/queries_resolver.ex:335-357` (`cache_dashboard_query_execution`), schema field `storeDashboardQueryExecution` in `lib/sanbase_web/graphql/schema/queries/queries_queries.ex:398-408`
- **Problem:** The mutation stores a **client-supplied** `compressed_query_execution_result` as the cached panel result. `get_for_cache_update` authorizes with `d.user_id == ^querying_user_id or d.is_public == true`, so any authenticated user can overwrite the cached results of any public dashboard (IDs are enumerable). Viewers then see attacker-controlled data.
- **Fix:** Restrict storing a client-supplied result to the dashboard **owner**. The "anyone can refresh a public dashboard" intent should mean "trigger a server-side recompute", not "upload arbitrary bytes". Change the store path to use an ownership-scoped query (mirror `get_for_mutation`, which is `d.user_id == ^querying_user_id` only):
  - In the cache-store code path, replace the `get_for_cache_update` lookup with the owner-only `get_for_mutation` query (or add an `only_owner: true` option).
  - Keep `get_for_cache_update` (public-allowed) only for read/recompute paths that do **not** accept client-supplied result bytes.
- **Caution:** Trace all callers of `get_for_cache_update` first (`grep -rn get_for_cache_update lib/`) so you don't break the legitimate recompute flow. There may be a separate code path that recomputes server-side for public dashboards — that one is fine.
- **Test:** Assert a non-owner calling `storeDashboardQueryExecution` on a public dashboard they don't own is rejected.

### SEC-4 — Unauthenticated ClickHouse schema disclosure
- **Severity:** Medium — **Confidence:** high
- **File:** `lib/sanbase_web/graphql/schema/queries/queries_queries.ex:247-253` (`get_clickhouse_database_metadata`)
- **Problem:** Field has `meta(access: :free)` and no `middleware(UserAuth)` (neighbors have it). Anonymous users get full `system.tables`/`system.columns`/`system.functions` listings for the prod DB.
- **Fix:** Add the auth middleware to match sibling fields:
  ```elixir
  field :get_clickhouse_database_metadata, :clickhouse_database_metadata do
    meta(access: :free)
    arg(:functions_filter, :clickhouse_metadata_function_filter_enum)
    middleware(SanbaseWeb.Graphql.Middlewares.UserAuth)   # ADD (use same alias other fields use)
    cache_resolve(&QueriesResolver.get_clickhouse_database_metadata/3)
  end
  ```
  Check the top of the file for the existing `UserAuth` alias/import and use that exact form.
- **Test:** Assert an unauthenticated query returns an auth error.

---

## P1 — Config-dependent (real, require missing/weak env var)

### SEC-5 — Stripe webhook forgeable when `STRIPE_WEBHOOK_SECRET` unset
- **Severity:** High if misconfigured — **Confidence:** high
- **Files:** `config/stripe_config.exs:10`, `lib/sanbase_web/plug/verify_stripe_webhook.ex:34-44`
- **Problem:** Secret defaults to `""`. `construct_event(body, sig, "")` lets an attacker forge events (e.g. grant themselves a paid subscription) in any env where the var is unset. Also `[signature] = get_req_header(...)` crashes on missing header.
- **Fix:**
  1. Remove the empty default in `config/stripe_config.exs`:
     ```elixir
     webhook_secret: {:system, "STRIPE_WEBHOOK_SECRET"}   # no "" default
     ```
  2. Guard in the plug before verifying:
     ```elixir
     defp do_verify(conn, body) do
       secret = webhook_secret()

       with [signature] <- get_req_header(conn, "stripe-signature"),
            true <- is_binary(secret) and byte_size(secret) > 0,
            {:ok, %Stripe.Event{}} <-
              Sanbase.StripeApi.Webhook.construct_event(body, signature, secret) do
         assign(conn, :stripe_event, Jason.decode!(body))
       else
         _ -> halt_and_log_error(conn, "invalid or unverifiable stripe webhook")
       end
     end
     ```
  3. Confirm prod/stage actually set `STRIPE_WEBHOOK_SECRET`.
- **Test:** existing config `config/test.exs:151` already sets a test secret — keep tests green.

### SEC-6 — SSRF via `confirmation_endpoint` in metric-registry sync
- **Severity:** Medium (gated by sync secret) — **Confidence:** high
- **File:** `lib/sanbase/metric/registry/sync.ex:167-172`
- **Problem:** `Req.post(confirmation_endpoint, ...)` with no host/scheme validation. If the sync secret leaks, SSRF to internal services / `169.254.169.254`.
- **Fix:** Validate the host against the known backend URL before posting. The legitimate endpoint is generated by `get_confirmation_endpoint/1` and is self-referential; reject anything whose host isn't the configured `BACKEND_URL` host.
  ```elixir
  defp send_sync_completed_confirmation(url, actual_changes) do
    if allowed_confirmation_url?(url) do
      Req.post(url, json: %{actual_changes: actual_changes})
    else
      {:error, "confirmation_endpoint host not allowed"}
    end
  end
  ```
  Implement `allowed_confirmation_url?/1` by parsing `URI.parse(url)` and comparing host (and scheme == "https") to the configured backend host.

### SEC-7 — Admin email-auth bypass if `DEPLOYMENT_ENVIRONMENT` unset
- **Severity:** Medium (config hardening) — **Confidence:** medium
- **Files:** `config/config.exs:72` (`deployment_env` defaults to `"dev"`), `lib/sanbase_web/plug/admin_email_auth_plug.ex` (treats dev as token bypass — confirm exact logic)
- **Problem:** A prod admin pod that doesn't set `DEPLOYMENT_ENVIRONMENT=prod` would accept email-only admin login.
- **Fix:** Don't default to a privileged-bypass value. Either remove the default (fail closed) or make the bypass require an explicit `:dev`/`:test` AND non-prod container check. Verify deploy manifests set `DEPLOYMENT_ENVIRONMENT`. Lowest-risk code change: in the plug, require `Mix.env() in [:dev, :test]` (compile-time) in addition to the runtime env check, so a missing runtime var can't enable the bypass in a prod build.

---

## P2 — Lower severity / defense-in-depth

### SEC-8 — User profile fields unsanitized / no URL scheme allowlist
- **Severity:** Medium (frontend-dependent) — **Confidence:** high
- **Files:** `lib/sanbase/accounts/user.ex:184` (`description` cast, no sanitization), `lib/sanbase/utils/validation.ex:99-126` (`valid_url?` accepts `javascript:`/`data:`)
- **Fix A — URL scheme allowlist** in `valid_url?`:
  ```elixir
  cond do
    is_nil(uri.scheme) or is_nil(uri.host) ->
      {:error, "`#{url}` is missing a scheme (e.g. https) or host"}
    uri.scheme not in ["http", "https"] ->
      {:error, "`#{url}` must use http or https"}
    true -> :ok
  end
  ```
  This protects `avatar_url` and `website_url` (`user.ex:197-198`).
- **Fix B — sanitize `description`:** strip tags on write in the changeset, e.g. `update_change(changeset, :description, &HtmlSanitizeEx.strip_tags/1)`, or change the GraphQL field type to `:sanitized_string_no_tags`.

### SEC-9 — Admin LiveViews don't re-check admin-panel role on WS (re)mount
- **Severity:** Low (mitigated by `AdminPodOnly` pod isolation) — **Confidence:** high
- **File:** `lib/sanbase_web/router.ex:177-277` (live routes using only `:ensure_authenticated`, and bare `live/` routes with no `on_mount`)
- **Fix:** Add a role-checking `on_mount` (mirror the existing `:ensure_user_has_metric_registry_role` pattern, but for "Admin Panel" role) to those `live_session` blocks, and wrap the bare `live/` routes (notifications/broadcast, promo_trials, user_roles, ses_events, etc.) in a `live_session` with `[:ensure_authenticated, :extract_and_assign_current_user_roles, :ensure_user_has_admin_panel_role]`. Implement `on_mount(:ensure_user_has_admin_panel_role, ...)` in `lib/sanbase_web/admin_user_auth.ex` analogous to the metric-registry one (check `String.starts_with?(&1, "Admin Panel")`).

### SEC-10 — CSRF disabled across admin scope
- **Severity:** Low (amplifier; pod-isolated) — **Confidence:** high
- **File:** `lib/sanbase_web/plug/admin_pod_only.ex:17`
- **Fix:** Ideally don't blanket-skip CSRF. If the admin uses standard Phoenix forms, remove `put_private(:plug_skip_csrf_protection, true)` and rely on `:protect_from_forgery` in the `:browser` pipeline. If something specific needs it, scope the skip to those exact routes. Lower priority — document the decision if intentionally kept.

### SEC-11 — Comment content unsanitized into email template vars
- **Severity:** Low — **Confidence:** high
- **File:** `lib/sanbase/comments/notification.ex` (lines ~287,307,327,347 pass raw `comment.content` as `comment_text`)
- **Fix:** `HtmlSanitizeEx.strip_tags(comment.content)` before putting it in the Mailjet variables map.

### SEC-12 — Non-constant-time secret comparisons
- **Severity:** Low — **Confidence:** high
- **Files:** `lib/sanbase_web/plug/telegram_match_plug.ex:16` (`===`), `lib/sanbase/accounts/user/user_email.ex:105,116` (`==` on email tokens)
- **Fix:** Use `Plug.Crypto.secure_compare/2` for both. For telegram, also remove the `"some_random_string"` default in `config/notifications_config.exs` and require the env var.

### SEC-13 — `getClickhouseQueryExecutionStats` IDOR
- **Severity:** Low (UUIDv4 keyed) — **Confidence:** high
- **Files:** `lib/sanbase/queries/query/query_execution.ex:208` (`get_execution_stats/1`), resolver `lib/sanbase_web/graphql/resolvers/queries_resolver.ex:467-481`
- **Fix:** Add a `user_id` filter. There's already a `get_query_execution_by_clickhouse_query_id/2` that takes `user_id` — follow that pattern: make `get_execution_stats/2` accept `user_id` and add `where: qe.user_id == ^user_id`. Pass `user.id` from the resolver.

### SEC-14 — `update_terms_and_conditions` uses omnibus changeset
- **Severity:** Low (defense-in-depth; Absinthe strips undeclared args today) — **Confidence:** high
- **Files:** `lib/sanbase_web/graphql/resolvers/user/user_resolver.ex:371-394`, `lib/sanbase/accounts/user.ex:154-210`
- **Fix:** Add a narrow `User.terms_changeset/2` that only casts `:privacy_policy_accepted` and `:marketing_accepted`, and use it in the resolver instead of `User.changeset/2`.

### SEC-15 — `san_lang` uses `String.to_atom` on function name
- **Severity:** Low (guarded by compile-time allowlist) — **Confidence:** high
- **File:** `lib/sanbase/san_lang/interpreter.ex:100`
- **Fix:** Change `String.to_atom(function_name)` to `String.to_existing_atom(function_name)`. The `when function_name in @supported_functions` guard guarantees the atom already exists, so this is a safe net with no behavior change for valid input.

### SEC-16 — Unauthenticated reference-data GET routes (recon)
- **Severity:** Low — **Confidence:** high
- **File:** `lib/sanbase_web/router.ex:377-391` (`api_metric_name_mapping`, `projects_data`, `projects_twitter_handles`, `clickhouse_metrics_metadata`, `ecosystems_data`, `ecosystem_github_organization_mapping`, `cryptocompare_asset_mapping`)
- **Fix:** Optional. Add an IP allowlist plug or a shared secret if these are only consumed internally (they expose internal metric/table names). Confirm no external consumer depends on them before locking down.

---

## Do NOT act on these (verified false positives / non-issues)

- **`REPLACED_BLOCKQUOTE` sentinel** (`sanitized_string.ex:28-31`): not a bypass — the substitution runs after scrubbing and content after the sentinel is still scrubbed. Cosmetic only.
- **Hardcoded `"secret_only_on_prod"` registry secrets** (`config/config.exs:329-330`): not prod-exploitable. `runtime.exs:177-180` overrides inside `if config_env() == :prod`, and `valid_secret?` fails closed (constant-time, binary-guarded) when the env secret is nil. Dev/test placeholders only.
- **`sanitized_string` `serialize(nil) -> {:ok, nil}`** (`sanitized_string.ex:20,34`): at most a data-integrity quirk, likely dead (Absinthe short-circuits nil). Not security. (Optional tidy: return bare `nil`.)

## Verified clean (no action)

ClickHouse user-SQL uses parameterized named params (no string interpolation) on a read-only role; `san_lang` is a closed allowlist DSL (no `Code.eval`); GraphQL ownership checks present on watchlists/queries/triggers/subscriptions; image upload extension allowlist + `Path.basename`; outbound webhook SSRF guard (`valid_public_url?` blocks private/link-local/metadata ranges); SES SNS URL validation; `binary_to_term` only on server-written data via `non_executable_binary_to_term([:safe])`; repo-reader git calls use argv (no shell). No SQL injection or RCE path found.

---

## Suggested execution order for the follow-up model

1. SEC-1 (delete iframe line) — trivial, high impact.
2. SEC-4 (add middleware) — trivial.
3. SEC-15, SEC-12, SEC-13, SEC-14 — small, mechanical, low-risk.
4. SEC-8 (URL scheme allowlist + description sanitize).
5. SEC-5 (Stripe guard) — verify test config stays green.
6. SEC-2 (presigned prefix) — **requires verifying key convention first; don't guess.**
7. SEC-3 (dashboard cache owner-only) — **trace `get_for_cache_update` callers first.**
8. SEC-6, SEC-7, SEC-9, SEC-10, SEC-11, SEC-16 — remaining hardening.

For each change: edit, `mix compile`, run nearest tests (`mix test <path>`), keep commits small and one-finding-per-commit. SEC-2 and SEC-3 need a human/owner sanity check before merging because they touch product behavior.
