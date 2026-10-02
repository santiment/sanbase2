/**
 * Data for metric/slug/version autocomplete.
 *
 * - Metric names and projects are loaded on first use (not on page load),
 *   cached through the storage backend (graphiql-storage.js) for 24h and
 *   refreshed in the background once stale, so suggestions show instantly
 *   on later visits.
 * - Per-metric data (available slugs, metadata) is fetched on demand and kept
 *   in memory for the page session only.
 * - After a failed request the same lookup is not retried for 30s, so a
 *   broken API does not get a request per keystroke.
 *
 * `request(query, variables)` must resolve to the `data` of a GraphQL
 * response and reject on errors. No React/Monaco imports, so it can be
 * unit-tested in node.
 */
import { packProjects, unpackProjects } from "./graphiql-autocomplete-utils.js";
import { memoryBackend } from "./graphiql-storage.js";

export var CACHE_KEY = "san-graphiql-autocomplete-v1";
var TTL_MS = 24 * 60 * 60 * 1000;
var RETRY_AFTER_MS = 30 * 1000;

var LISTS_QUERY = "{ getAvailableMetrics allProjects { slug name ticker } }";
var METRIC_SLUGS_QUERY =
  "query($metric: String!) { getMetric(metric: $metric) { metadata { availableSlugs } } }";
var METRIC_META_QUERY =
  "query($metric: String!) { getMetric(metric: $metric) { metadata { " +
  "humanReadableName defaultAggregation minInterval " +
  "availableVersions { versionNum versionName description } } } }";

// options: { request, storage (backend, default in-memory), now }
export function createAutocompleteData(options) {
  var request = options.request;
  var storage = options.storage || memoryBackend();
  var now = options.now || Date.now;

  // Memoize a promise-returning lookup by key. A rejection is kept for
  // RETRY_AFTER_MS and then dropped, so the next call retries.
  function memo(fn) {
    var cache = new Map();
    return function (key) {
      var hit = cache.get(key);
      if (hit && !(hit.failedAt !== null && now() - hit.failedAt > RETRY_AFTER_MS)) return hit.promise;
      var entry = { promise: fn(key), failedAt: null };
      entry.promise.catch(function () { entry.failedAt = now(); });
      cache.set(key, entry);
      return entry.promise;
    };
  }

  var lists = null; // { metrics, projects, fetchedAt }
  var fetchLists = memo(function () {
    return request(LISTS_QUERY, null).then(function (data) {
      var packed = packProjects(data.allProjects || []);
      var value = {
        metrics: (data.getAvailableMetrics || []).filter(Boolean).sort(),
        projects: unpackProjects(packed),
        fetchedAt: now(),
      };
      lists = value;
      storage.set(CACHE_KEY, { fetchedAt: value.fetchedAt, metrics: value.metrics, projects: packed })
        .catch(function () {}); // not cached: fetched again next page load
      return value;
    });
  });

  // Read the cache once per page load.
  var cacheRead = null;
  function readCache() {
    if (!cacheRead) {
      cacheRead = storage.get(CACHE_KEY).then(function (data) {
        if (lists || !data || !Array.isArray(data.metrics) || !Array.isArray(data.projects)) return;
        lists = {
          metrics: data.metrics.filter(function (m) { return typeof m === "string"; }),
          projects: unpackProjects(data.projects),
          fetchedAt: data.fetchedAt || 0,
        };
      }).catch(function () {}); // unreadable or corrupt cache: a miss, fetched again
    }
    return cacheRead;
  }

  // A fresh memo key per refresh, so a stale cache refreshes once per
  // TTL_MS instead of on every call, and failures back off.
  function listsKey() {
    return lists ? "refresh-" + lists.fetchedAt : "initial";
  }

  function getLists() {
    return readCache().then(function () {
      if (!lists) return fetchLists(listsKey());
      if (now() - lists.fetchedAt > TTL_MS) {
        // Stale: answer from cache now, refresh for next time.
        fetchLists(listsKey()).catch(function () {});
      }
      return lists;
    });
  }

  function metadataOf(data, metric) {
    var meta = data.getMetric && data.getMetric.metadata;
    if (!meta) throw new Error("no metadata for " + metric);
    return meta;
  }

  var getMetricSlugs = memo(function (metric) {
    return request(METRIC_SLUGS_QUERY, { metric: metric }).then(function (data) {
      return new Set(metadataOf(data, metric).availableSlugs || []);
    });
  });

  var getMetricMeta = memo(function (metric) {
    return request(METRIC_META_QUERY, { metric: metric }).then(function (data) {
      return metadataOf(data, metric);
    });
  });

  return {
    getLists: getLists,
    getMetricSlugs: getMetricSlugs,
    getMetricMeta: getMetricMeta,
  };
}
