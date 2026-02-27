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

# 2. Create users with API keys + Business Pro subscriptions
mix load_test.setup --users 20
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
