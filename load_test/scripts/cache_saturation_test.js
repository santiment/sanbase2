// Cache-saturation load test for the GraphQL API.
//
// Unlike graphql_load_test.js (which optimizes for realistic traffic mix),
// this script controls the CACHE HIT RATIO of the request stream so you can
// observe the memory/latency behavior of the Cachex-backed GraphQL cache
// under different hit profiles:
//
//   * "pool" requests draw from a fixed, deterministic pool of
//     (metric, slug, time-window, interval) combinations. The combination is
//     identical across VUs and iterations, so after first touch these are
//     server-side cache HITS.
//   * "fresh" requests shift the time window by a unique per-request number
//     of hours, producing a never-seen-before cache key — a guaranteed MISS
//     that also inserts a new cache entry (this is what saturates the cache).
//
// HIT_RATIO controls the pool/fresh split. Run the three canonical profiles:
//
//   k6 run --env HIT_RATIO=0.9 scripts/cache_saturation_test.js
//   k6 run --env HIT_RATIO=0.5 scripts/cache_saturation_test.js
//   k6 run --env HIT_RATIO=0.1 scripts/cache_saturation_test.js
//
// While it runs, watch the server-side cache from IEx:
//
//   SanbaseWeb.Graphql.Cache.count()  # entries
//   SanbaseWeb.Graphql.Cache.size()   # ETS megabytes
//   :erlang.memory(:total)            # whole-BEAM footprint
//
// Other tunables:
//   SCENARIO   - smoke | load | stress (default: load)
//   POOL_SIZE  - number of distinct hot combinations (default: 500)
//   BASE_URL   - target server (default: http://localhost:4000)

import http from "k6/http";
import { check, sleep } from "k6";
import { SharedArray } from "k6/data";
import { Rate, Trend, Counter } from "k6/metrics";

// Custom metrics — pool (mostly hits) and fresh (guaranteed misses) split
const errorRate = new Rate("graphql_errors");
const poolDuration = new Trend("pool_query_duration", true);
const freshDuration = new Trend("fresh_query_duration", true);
const poolCount = new Counter("pool_requests");
const freshCount = new Counter("fresh_requests");

const apikeys = new SharedArray("apikeys", function () {
  return JSON.parse(open("../data/apikeys.json"));
});

if (!Array.isArray(apikeys) || apikeys.length === 0) {
  throw new Error(
    "No API keys found in load_test/data/apikeys.json. Run `mix load_test.setup` first.",
  );
}

const BASE_URL = __ENV.BASE_URL || "http://localhost:4000";
const GRAPHQL_URL = `${BASE_URL}/graphql`;
const HIT_RATIO = parseFloat(__ENV.HIT_RATIO || "0.9");
const POOL_SIZE = parseInt(__ENV.POOL_SIZE || "500", 10);

if (!(HIT_RATIO >= 0 && HIT_RATIO <= 1)) {
  throw new Error(`Invalid HIT_RATIO="${__ENV.HIT_RATIO}". Use a number in [0, 1].`);
}

const scenarios = {
  smoke: { executor: "constant-vus", vus: 2, duration: "30s" },
  load: { executor: "constant-vus", vus: 20, duration: "2m" },
  stress: {
    executor: "ramping-vus",
    startVUs: 0,
    stages: [
      { duration: "30s", target: 10 },
      { duration: "1m", target: 50 },
      { duration: "1m", target: 50 },
      { duration: "30s", target: 0 },
    ],
  },
};

const selectedScenario = __ENV.SCENARIO || "load";
if (!Object.prototype.hasOwnProperty.call(scenarios, selectedScenario)) {
  throw new Error(
    `Invalid SCENARIO="${selectedScenario}". Valid values: ${Object.keys(scenarios).join(", ")}`,
  );
}

export const options = {
  scenarios: { default: scenarios[selectedScenario] },
  setupTimeout: "300s",
  thresholds: {
    http_req_duration: ["p(95)<5000"],
    graphql_errors: ["rate<0.1"],
  },
};

// --- Static data -------------------------------------------------------------

let SLUGS;
try {
  SLUGS = JSON.parse(open("../data/slugs.json"));
} catch (_e) {
  SLUGS = [
    "bitcoin", "ethereum", "solana", "cardano", "chainlink",
    "litecoin", "avalanche", "polkadot-new", "dogecoin", "tron",
    "xrp", "binance-coin", "monero", "stellar", "cosmos",
    "uniswap", "aave", "near-protocol", "aptos", "sui",
  ];
}

const METRICS = [
  "daily_active_addresses",
  "transaction_volume",
  "exchange_inflow",
  "exchange_outflow",
  "network_growth",
  "nvt",
  "mvrv_usd",
  "circulation",
  "age_consumed",
  "velocity",
  "mean_dollar_invested_age",
  "dev_activity_1d",
];

const DAY_RANGES = [7, 30, 90];
const INTERVALS = { 7: "1h", 30: "4h", 90: "1d" };

// --- Deterministic combination pool ------------------------------------------

// combo(i) is a pure function of i: every VU computes the same combination
// for the same index, which is what makes pool requests collide on the same
// server-side cache keys.
function combo(i) {
  const metric = METRICS[i % METRICS.length];
  const slug = SLUGS[Math.floor(i / METRICS.length) % SLUGS.length];
  const days = DAY_RANGES[i % DAY_RANGES.length];
  return { metric, slug, days };
}

// Midnight-aligned timestamps so the from/to strings are byte-identical for
// the whole run — the server buckets datetimes by TTL when building cache
// keys, and stable strings guarantee stable keys.
function poolQueryArgs(i) {
  const { metric, slug, days } = combo(i);
  const to = new Date(Date.now());
  to.setUTCHours(0, 0, 0, 0);
  const from = new Date(to.getTime() - days * 86400 * 1000);

  return {
    metric,
    slug,
    interval: INTERVALS[days],
    from: from.toISOString(),
    to: to.toISOString(),
  };
}

// Guaranteed-miss window: shift `to` back by a per-request-unique number of
// seconds. Steps are larger than the server's TTL bucket width (~10 min), so
// no two shifts can collapse into the same bucketed cache key. Shifts wrap
// after ~45k fresh requests per run; raise SHIFT_STEP_S coverage if you run
// longer scenarios.
const SHIFT_STEP_S = 700;
const YEAR_S = 365 * 86400;

function freshQueryArgs() {
  // Compact per-request-unique nonce (holds while a VU stays under 10k iters)
  const nonce = (__VU - 1) * 10_000 + __ITER;
  const shiftS = ((nonce * SHIFT_STEP_S) % YEAR_S) + 3600;
  const { metric, slug, days } = combo(nonce % POOL_SIZE);

  const to = new Date(Date.now() - shiftS * 1000);
  const from = new Date(to.getTime() - days * 86400 * 1000);

  return {
    metric,
    slug,
    interval: INTERVALS[days],
    from: from.toISOString(),
    to: to.toISOString(),
  };
}

function buildQuery({ metric, slug, from, to, interval }) {
  return `{
    getMetric(metric: "${metric}") {
      timeseriesData(
        selector: { slug: "${slug}" }
        from: "${from}"
        to: "${to}"
        interval: "${interval}"
      ) {
        datetime
        value
      }
    }
  }`;
}

// --- Main --------------------------------------------------------------------

export default function () {
  const apikey = apikeys[(__VU - 1) % apikeys.length];

  const isPool = Math.random() < HIT_RATIO;
  const args = isPool
    ? poolQueryArgs(Math.floor(Math.random() * POOL_SIZE))
    : freshQueryArgs();
  const query = buildQuery(args);

  const keyClass = isPool ? "pool" : "fresh";

  const res = http.post(GRAPHQL_URL, JSON.stringify({ query }), {
    headers: {
      "Content-Type": "application/json",
      Authorization: `Apikey ${apikey}`,
    },
    tags: { key_class: keyClass },
  });

  if (isPool) {
    poolCount.add(1);
    poolDuration.add(res.timings.duration);
  } else {
    freshCount.add(1);
    freshDuration.add(res.timings.duration);
  }

  const success = check(
    res,
    {
      "status is 200": (r) => r.status === 200,
      "no errors in body": (r) => {
        try {
          const body = JSON.parse(r.body);
          return !body.errors || body.errors.length === 0;
        } catch (_e) {
          return false;
        }
      },
    },
    { key_class: keyClass },
  );

  errorRate.add(!success);

  sleep(Math.random() * 0.2 + 0.05);
}
