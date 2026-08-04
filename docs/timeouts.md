# Request-path timeouts

Every timeout a user request can hit, outside in. A request dies at the first
layer whose budget it exhausts.

| # | Layer | Budget | Where | On timeout |
|---|-------|--------|-------|------------|
| 0 | Load balancer / ingress | **unverified** | infra, not this repo | 502/504; BEAM keeps computing |
| 1 | Cowboy `idle_timeout` | 120s web, 180s mcp | `config/runtime.exs` | connection closed; BEAM keeps computing |
| 2 | Absinthe document execution | none | — | no global cap |
| 3 | GraphQL cache lock wait | 102s, then fallback | `CachexProvider` | waiter recomputes without the lock; no error |
| 4 | Absinthe async middleware | 105s | `Helpers.Async` | `Task.await` exit → **500** |
| 5 | Absinthe batch middleware | 5s (library default) | unconfigured, `ico_resolver.ex` | `exit({:timeout, ..})` → **500** |
| 6 | Dataloader batches | 55s PG, 105s KV/CH | per-source `timeout:` | batch killed; fields → nil |
| 7 | `RehydratingCache.get/2` | 30s | `rehydrating_cache.ex` | `{:error, :timeout}` |
| 8 | Postgres | 30s, CoDel 5s/10s | `config/config.exs` | `DBConnection.ConnectionError` → **500** |
| 9 | ClickHouse (rw + per-plan ro) | 85s, CoDel 5s/20s | `config/config.exs` | rescued → `{:error, message}` |
| 10 | Generic ConCache locks | 102s, 120s alerts | `cache.ex`, `application.ex`, `alerts.ex` | `GenServer.call` exit → **500** |
| 11 | External HTTP in resolvers | 25–30s recv | `config/config.exs` | client error tuple |

Chain: `LB (>120s) > cowboy 120s > async 105s > cache lock 102s > CH 85s > PG 30s`.
MCP: `cowboy 180s > Anubis 150s > task work 120s`.

Cache-lock waits sit *above* the CH budget on purpose. Cowboy/async are
*containment* budgets (outer > inner). A lock wait is a wait on a *peer*: it
must exceed the peer's budget, or it gives up exactly when the holder is slow.

## Connection pools

- **`:timeout` is one absolute budget for pool wait + query.**
  `Holder.checkout/3` computes `now + :timeout` before contacting the pool and
  arms it as an `abs: true` deadline on handover. Queueing eats into the
  query's time, it does not add to it.
- **A queued client has no deadline.** `checkout_call/5`'s `receive` has no
  after-clause and the pool never expires queue entries. CoDel shedding is the
  only thing that releases a waiter.
- **`queue_target`/`queue_interval` are CoDel, not timeouts.** `queue_interval`
  is a sampling window (and the poll period); the pool tracks the *minimum*
  checkout delay in it and starts shedding only if even that minimum exceeded
  `queue_target` — a standing queue, not a burst. One fast checkout turns it
  back off. Shedding drops waiters past `2 * queue_target`, oldest first.
- **Reaction time**: 10s steady-state; a fully stalled pool needs two poll
  ticks (~40s CH / ~20s PG) since the first only records the baseline.
- **Ceiling on raising these**: at `queue_target` 5s a CH request can burn 40s
  of its 85s queueing, leaving 45s to run. Higher values hand out connections
  to clients that can no longer use them.
- **The deadline does not interrupt the driver.** `Ch.Connection.recv_all/3`
  re-applies `:timeout` to *every* `Mint.HTTP.recv`, so a dribbling response
  overshoots. That is why CH is 85s and not the full 102s of headroom.

## How timeouts surface

- **ClickHouse**: rescued in `Sanbase.ClickhouseRepo` → `{:error, "[log_id] msg"}`.
  `timeout_error?/1` matches four shapes — Mint's bare `"timeout"`,
  DBConnection's `"timed out because it queued and checked out"` and
  `"dropped from queue"`, ClickHouse's `(TIMEOUT_EXCEEDED)` — and returns a
  message telling the user to narrow the query. The match is word-bounded, so
  identifiers like `timeout_ms` do not count and `TIMEOUT_EXCEEDED` needs its
  own alternative. Errors can embed the user's SQL, so the echo after
  `"while processing query:"` is stripped first.
  Callers passing `propagate_error: true` (the SQL editor) still get the raw
  error.
- **Cache lock waits**: no user-facing error; the waiter recomputes. Replaces
  `"Obtaining cache lock failed because of timeout"` (8.8k Sentry events /
  157 users since Oct 2024, SANBASE-BACKEND-PROD-8).
- **Postgres**: still 500s.
- Dataloader timeouts sit on the **sources**, not the loader —
  `Dataloader.new(timeout:)` is never read; the run timeout is
  `max(source timeouts) + 1s`.
- Modules importing both `Helpers.Async` and `Absinthe.Resolution.Helpers`
  must `except: [async: 1, async: 2]` on the latter, or the call is ambiguous.

## Open items

1. **LB budget unverified.** Set ingress read/send timeouts ≥150s so cowboy is
   the outermost application-visible layer.
2. **Generic ConCache locks still 500 on timeout.** Porting `CachexProvider`'s
   recompute-instead-of-raise fallback to `Sanbase.Cache` would close this.
3. **KV source timeout is per batch.** `Task.async_stream` runs batches in
   waves, so a request with many CH batches can exceed the 106s loader budget
   and nil out the whole source. Not reachable at today's batch counts.
4. **The cache-lock fallback is best-effort for web callers.** 102s + a
   recompute cannot fit in async 105s. Correct for MCP/background callers;
   should only fire in anomalous states. If Sentry disagrees, make it
   budget-aware rather than lowering the wait.
5. **No per-document budget.** Many independent 85s fields can run for
   multiples of any single budget. Complexity limits are the lever, not
   timeouts.
6. **ClickHouse keeps running after we give up.** No `max_execution_time` is
   sent, so an abandoned query burns CPU to completion. Setting it ≈85 plus
   `cancel_http_readonly_queries_on_client_close` on the read-only pools would
   make the give-up mutual.
7. **`ConCacheProvider` has no callers** outside its own test. Its
   `acquire_lock_timeout` fix is inert; delete the module or wire it up.

## When touching these

- Keep the chain ordered, with margin for the response to travel out. The
  worst failure is an inner layer outliving the outer one.
- A DB layer's budget is `:timeout` (queue and query share it) — but leave
  slack, the deadline cannot interrupt a driver blocked in a socket read.
- Distinguish *containment* budgets (must exceed what they wrap) from *peer
  waits* (must exceed the peer's own budget).
