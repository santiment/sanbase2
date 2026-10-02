/**
 * Data for metric/slug/version autocomplete.
 *
 * - Metric names and projects are loaded on first use (not on page load),
 *   cached in localStorage for 24h and refreshed in the background once
 *   stale, so suggestions show instantly on later visits.
 * - Per-metric data (available slugs, metadata) is fetched on demand and kept
 *   in memory for the page session only.
 * - Failed requests are not cached, so the next suggestion retries.
 *
 * `request(query, variables)` must resolve to the `data` of a GraphQL
 * response and reject on errors. No React/Monaco imports, so it can be
 * unit-tested in node.
 */
import { packProjects, unpackProjects } from "./graphiql-autocomplete-utils.js";

export var CACHE_KEY = "san-graphiql-autocomplete-v1";
var TTL_MS = 24 * 60 * 60 * 1000;

var LISTS_QUERY =
  "query SanAutocompleteLists { getAvailableMetrics allProjects { slug name ticker } }";
var METRIC_SLUGS_QUERY =
  "query SanAutocompleteSlugs($metric: String!) { getMetric(metric: $metric) { metadata { availableSlugs } } }";
var METRIC_META_QUERY =
  "query SanAutocompleteMeta($metric: String!) { getMetric(metric: $metric) { metadata { " +
  "humanReadableName defaultAggregation minInterval " +
  "availableVersions { versionNum versionName description } } } }";

function defaultStorage() {
  try {
    return typeof localStorage !== "undefined" ? localStorage : null;
  } catch (e) {
    return null;
  }
}

// Memoize a promise-returning function by key; rejected results are dropped.
function memo(fn) {
  var cache = new Map();
  return function (key) {
    if (!cache.has(key)) {
      var p = fn(key);
      cache.set(key, p);
      p.catch(function () { cache.delete(key); });
    }
    return cache.get(key);
  };
}

export function createAutocompleteData(options) {
  var request = options.request;
  var storage = options.storage !== undefined ? options.storage : defaultStorage();
  var now = options.now || Date.now;
  var ttl = options.ttlMs || TTL_MS;

  var lists = null; // { metrics, projects, fetchedAt }
  var inflight = null;

  function readCache() {
    if (!storage) return null;
    try {
      var data = JSON.parse(storage.getItem(CACHE_KEY) || "null");
      if (!data || !Array.isArray(data.metrics) || !Array.isArray(data.projects)) return null;
      return { metrics: data.metrics, projects: unpackProjects(data.projects), fetchedAt: data.fetchedAt || 0 };
    } catch (e) {
      return null;
    }
  }

  function writeCache(value) {
    if (!storage) return;
    try {
      storage.setItem(CACHE_KEY, JSON.stringify({
        fetchedAt: value.fetchedAt,
        metrics: value.metrics,
        projects: packProjects(value.projects),
      }));
    } catch (e) {
      // Quota or blocked storage: keep the in-memory copy only.
    }
  }

  function fetchLists() {
    if (inflight) return inflight;
    inflight = request(LISTS_QUERY, null)
      .then(function (data) {
        var value = {
          metrics: (data.getAvailableMetrics || []).filter(Boolean).sort(),
          projects: (data.allProjects || []).filter(function (p) { return p && p.slug; }),
          fetchedAt: now(),
        };
        lists = value;
        writeCache(value);
        return value;
      })
      .finally(function () { inflight = null; });
    return inflight;
  }

  function getLists() {
    if (!lists) lists = readCache();
    if (lists) {
      if (now() - lists.fetchedAt > ttl) {
        // Stale: answer from cache now, refresh for next time.
        fetchLists().catch(function () {});
      }
      return Promise.resolve(lists);
    }
    return fetchLists();
  }

  var getMetricSlugs = memo(function (metric) {
    return request(METRIC_SLUGS_QUERY, { metric: metric }).then(function (data) {
      var meta = data.getMetric && data.getMetric.metadata;
      return new Set((meta && meta.availableSlugs) || []);
    });
  });

  var getMetricMeta = memo(function (metric) {
    return request(METRIC_META_QUERY, { metric: metric }).then(function (data) {
      return (data.getMetric && data.getMetric.metadata) || null;
    });
  });

  return {
    getLists: getLists,
    getMetricSlugs: getMetricSlugs,
    getMetricMeta: getMetricMeta,
    // Drop cached lists (e.g. to pick up a newly added metric).
    refresh: function () {
      lists = null;
      return fetchLists();
    },
  };
}
