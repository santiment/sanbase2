# Load Testing

Local load testing for the Sanbase GraphQL API using [k6](https://k6.io/).

## Prerequisites

```bash
brew install k6
```

## Setup

All commands require the app's DB to be running.

```bash
# 1. Seed projects (contract addresses, github orgs)
mix load_test.seed_projects

# 2. Create users with API keys + Business Pro subscriptions (no rate limits)
mix load_test.setup --users 20 --no-rate-limits
```

## Run Tests

```bash
cd load_test

# Smoke test (2 VUs, 30s)
k6 run --env SCENARIO=smoke scripts/graphql_load_test.js

# Load test (20 VUs, 2min)
k6 run --env SCENARIO=load scripts/graphql_load_test.js

# Stress test (ramp to 50 VUs over 3min)
k6 run --env SCENARIO=stress scripts/graphql_load_test.js
```

Override the target URL:

```bash
k6 run --env SCENARIO=smoke --env BASE_URL=http://localhost:4000 scripts/graphql_load_test.js
```

## Cleanup

```bash
mix load_test.cleanup
```

Deletes all `*@sanload.test` users and removes the API keys JSON file.
Note: seeded projects are left in place (harmless in local dev).

## GraphQL Cache (Cachex) Benchmark

Standalone load test for `SanbaseWeb.Graphql.CachexProvider` — no DB, no app
boot; only `:cachex` is started. It asserts the invariants whose violation
caused the Cachex 4 OOM incident: bounded ETS growth under burst writes,
single-flight cache stampede protection, oversized-value rejection and TTL
sweeping. It also reports throughput, latency percentiles for mixed
read/write load, and memory footprint at controlled cache-hit ratios
(90% / 50% / 10%).

```bash
mix run --no-start load_test/scripts/cachex_provider_bench.exs

# Tunables
BENCH_DURATION_MS=10000 BENCH_WORKERS=64 BENCH_MAX_ENTRIES=100000 \
  mix run --no-start load_test/scripts/cachex_provider_bench.exs
```

## Cache Saturation E2E Test (k6)

End-to-end variant of the hit-ratio benchmark: fires real `getMetric`
timeseries queries with a controlled server-side cache hit ratio. "Pool"
requests repeat a fixed set of (metric, slug, window, interval) combinations
(cache hits after warmup); "fresh" requests use per-request-unique time
windows (guaranteed misses that keep inserting new cache entries). Latency is
reported separately per class (`pool_query_duration` vs
`fresh_query_duration`).

```bash
cd load_test

# The three canonical hit-ratio profiles
k6 run --env HIT_RATIO=0.9 scripts/cache_saturation_test.js
k6 run --env HIT_RATIO=0.5 scripts/cache_saturation_test.js
k6 run --env HIT_RATIO=0.1 scripts/cache_saturation_test.js

# More VUs / longer run, bigger hot pool
k6 run --env HIT_RATIO=0.5 --env SCENARIO=stress --env POOL_SIZE=2000 \
  scripts/cache_saturation_test.js
```

While it runs, watch the server-side cache from the server's IEx shell:

```elixir
SanbaseWeb.Graphql.Cache.count()  # entries
SanbaseWeb.Graphql.Cache.size()   # ETS megabytes
:erlang.memory(:total)            # whole-BEAM footprint
```
