/**
 * Query history store for GraphiQL.
 *
 * Replaces the stock @graphiql/plugin-history recording, which saved an entry
 * on every keystroke while a query was in flight (its effect depends on
 * [isFetching, activeTab]). Here entries are recorded by wrapping the
 * fetcher (withHistory below), which GraphiQL calls exactly once per
 * execution.
 *
 * - Re-running the same query + variables (ignoring formatting) updates the
 *   existing entry and moves it to the top instead of adding a new one.
 * - Each entry keeps a short log of recent runs (newest first: status,
 *   duration, error) and a total run count.
 * - History stays within a size budget (default 1MB, localStorage allows
 *   ~5MB per origin) and at most 100 entries: the entries run longest ago are
 *   evicted first. Favorites are never evicted, and the most recently run
 *   entry is always kept.
 * - Headers are never stored: they usually carry API keys.
 * - Memory is the source of truth: changes show immediately and are
 *   persisted in order through a swappable storage backend (see
 *   graphiql-storage.js). Changes from another browser tab replace the
 *   in-memory list (last write wins).
 *
 * No React/GraphiQL imports, so it can be unit-tested in node.
 */
import {
  classifyResult,
  entryKey,
  isIntrospectionCall,
  summarizeQuery,
  sortHistory,
} from "./graphiql-history-utils.js";
import { defaultStorage, memoryBackend, readJson } from "./graphiql-storage.js";

export var STORAGE_KEY = "san-graphiql-history";
var MAX_QUERY_SIZE = 100000; // same limit as the stock history
var HASHED_KEY = /^[0-9a-f]{14}$/; // entryKey() output; normalized queries contain braces

// Stock @graphiql/toolkit keys, imported once so existing favorites survive.
var LEGACY_QUERIES_KEY = "graphiql:queries";
var LEGACY_FAVORITES_KEY = "graphiql:favorites";

function newId() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) return crypto.randomUUID();
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
}

function variablesToString(variables) {
  if (variables === undefined || variables === null) return "";
  if (typeof variables === "string") return variables.trim() === "{}" ? "" : variables;
  if (typeof variables === "object" && Object.keys(variables).length === 0) return "";
  return JSON.stringify(variables, null, 2);
}

function variablesToObject(variables) {
  if (!variables || typeof variables !== "string") return variables || null;
  try {
    return JSON.parse(variables);
  } catch (e) {
    return variables; // keep invalid JSON as-is; still part of the identity
  }
}

// Entries saved by earlier versions: the key was the full normalized query
// (and treated {} variables differently), and the last run was duplicated
// into lastStatus/lastDurationMs/lastError.
var DROPPED_FIELDS = ["lastStatus", "lastDurationMs", "lastError", "createdAt"];

function upgradeEntry(entry) {
  var stale = DROPPED_FIELDS.some(function (f) { return f in entry; });
  var oldKey = !HASHED_KEY.test(entry.key || "");
  if (!stale && !oldKey) return entry;
  var copy = Object.assign({}, entry);
  DROPPED_FIELDS.forEach(function (f) { delete copy[f]; });
  // Recomputed from the entry, not hashed from the old key, so it matches
  // what a re-run produces today.
  if (oldKey) copy.key = entryKey(entry.query, variablesToObject(entry.variables), entry.operationName);
  return copy;
}

// Entries that upgrading gave the same key are one query: merge them into
// the most recently run one. `list` is sorted newest first.
function mergeDuplicates(list, maxRuns) {
  var byKey = {};
  var out = [];
  list.forEach(function (e) {
    var kept = byKey[e.key];
    if (!kept) {
      byKey[e.key] = e;
      out.push(e);
      return;
    }
    var merged = Object.assign({}, kept, {
      favorite: kept.favorite || !!e.favorite,
      label: kept.label || e.label || null,
      runCount: (kept.runCount || 0) + (e.runCount || 0),
      runs: (kept.runs || []).concat(e.runs || [])
        .sort(function (a, b) { return b.at - a.at; })
        .slice(0, maxRuns),
    });
    out[out.indexOf(kept)] = merged;
    byKey[e.key] = merged;
  });
  return out;
}

// options:
//   storage        - storage backend (graphiql-storage.js); default in-memory
//   legacyStorage  - Web Storage holding the stock GraphiQL history to import
//                    once (default: localStorage)
//   maxEntries, maxBytes, maxRuns, now - limits and clock (tests)
export function createHistoryStore(options) {
  var opts = options || {};
  var storage = opts.storage || memoryBackend();
  var legacyStorage = opts.legacyStorage !== undefined ? opts.legacyStorage : defaultStorage();
  var maxEntries = opts.maxEntries || 100;
  var maxBytes = opts.maxBytes || 1000000; // characters of JSON, ~bytes as localStorage counts them
  var maxRuns = opts.maxRuns || 20;
  var now = opts.now || Date.now;

  var entries = [];
  var running = {}; // entry id -> number of in-flight runs (memory only)
  var listeners = new Set();
  var snapshot = { entries: entries, running: running };
  var saving = Promise.resolve();

  function emit() {
    snapshot = { entries: entries, running: running };
    listeners.forEach(function (l) { l(); });
  }

  function size(entry) {
    return JSON.stringify(entry).length;
  }

  // Least recently run first out. `list` is sorted newest first; keeps all
  // favorites, then non-favorites from the newest while they fit the count
  // and size budget. The newest non-favorite is always kept.
  function evict(list) {
    var used = list.reduce(function (sum, x) { return x.favorite ? sum + size(x) : sum; }, 0);
    var kept = 0;
    var full = false;
    return list.filter(function (x) {
      if (x.favorite) return true;
      if (full) return false;
      var s = size(x);
      if (kept > 0 && (kept >= maxEntries || used + s > maxBytes)) {
        full = true;
        return false;
      }
      kept++;
      used += s;
      return true;
    });
  }

  function dropOldest(list) {
    for (var i = list.length - 1; i >= 0; i--) {
      if (!list[i].favorite) return list.slice(0, i).concat(list.slice(i + 1));
    }
    return list;
  }

  function evictable(list) {
    return list.filter(function (x) { return !x.favorite; }).length > 1;
  }

  // Write `list`; if the backend refuses (e.g. other data on the origin
  // used up the quota), evict one more entry at a time until it fits. If
  // nothing fits, history keeps working in memory and the next change
  // retries.
  function write(list) {
    return storage.set(STORAGE_KEY, { entries: list }).catch(function (e) {
      if (!evictable(list)) return undefined;
      return write(dropOldest(list));
    });
  }

  // Saves are chained so they reach the backend in order.
  function persist() {
    var list = entries;
    saving = saving.then(function () { return write(list); });
    return saving;
  }

  function normalize(list) {
    return evict(mergeDuplicates(sortHistory(list, "recent"), maxRuns));
  }

  function mutate(fn) {
    var list = entries.slice();
    var result = fn(list);
    entries = evict(sortHistory(list, "recent"));
    emit();
    persist();
    return result;
  }

  function fromStored(data) {
    return data && Array.isArray(data.entries) ? data.entries.map(upgradeEntry) : null;
  }

  function migrateLegacy() {
    var legacyQueries = readJson(legacyStorage, LEGACY_QUERIES_KEY);
    var legacyFavorites = readJson(legacyStorage, LEGACY_FAVORITES_KEY);
    // Stock stores are ordered oldest first.
    var items = []
      .concat((legacyFavorites && legacyFavorites.favorites) || [])
      .concat((legacyQueries && legacyQueries.queries) || [])
      .reverse();

    var t = now();
    var byKey = {};
    var list = [];
    items.forEach(function (item, i) {
      if (!item || !item.query) return;
      var k = entryKey(item.query, variablesToObject(item.variables), item.operationName);
      var existing = byKey[k];
      if (existing) {
        existing.favorite = existing.favorite || !!item.favorite;
        existing.label = existing.label || item.label || null;
        return;
      }
      var entry = newEntry(k, item.query, variablesToString(item.variables), item.operationName, t - i);
      entry.favorite = !!item.favorite;
      entry.label = item.label || null;
      byKey[k] = entry;
      list.push(entry);
    });
    return list;
  }

  // Initial load. Runs recorded before it finishes are merged in (they are
  // the newest). The result is written back when it differs from what was
  // stored: first use (legacy import), upgraded or merged entries.
  var ready = storage.get(STORAGE_KEY)
    .catch(function () { return null; })
    .then(function (data) {
      var stored = fromStored(data);
      var hadLocal = entries.length > 0;
      var upgraded = stored && stored.some(function (e, i) { return e !== data.entries[i]; });
      entries = normalize(entries.concat(stored || migrateLegacy()));
      emit();
      if (!stored || hadLocal || upgraded || entries.length !== stored.length) persist();
    });

  // Another browser tab saved history: adopt its list.
  storage.onChange(STORAGE_KEY, function (data) {
    entries = normalize(fromStored(data) || []);
    emit();
  });

  function newEntry(k, query, variables, operationName, at) {
    return {
      id: newId(),
      key: k,
      query: query,
      variables: variables,
      operationName: operationName || null,
      title: summarizeQuery(query, operationName),
      label: null,
      favorite: false,
      lastRunAt: at,
      runCount: 0,
      runs: [],
    };
  }

  function update(id, fn) {
    mutate(function (list) {
      var idx = list.findIndex(function (x) { return x.id === id; });
      if (idx !== -1) list[idx] = fn(Object.assign({}, list[idx]));
    });
  }

  function setRunning(id, delta) {
    running = Object.assign({}, running);
    var n = (running[id] || 0) + delta;
    if (n > 0) running[id] = n;
    else delete running[id];
  }

  return {
    getSnapshot: function () { return snapshot; },

    subscribe: function (listener) {
      listeners.add(listener);
      return function () { listeners.delete(listener); };
    },

    // Resolves once stored history has been loaded.
    ready: ready,

    // Resolves once every change so far has been handed to the backend.
    flush: function () {
      return ready.then(function () { return saving; });
    },

    // Record the start of an execution. Returns a token for finishRun, or
    // null when the query is not recordable.
    startRun: function (params) {
      var query = params && params.query;
      if (!query || !query.trim() || query.length > MAX_QUERY_SIZE) return null;
      var variables = params.variables;
      var operationName = params.operationName || null;
      var k = entryKey(query, variablesToObject(variables), operationName);
      var startedAt = now();

      var id = mutate(function (list) {
        var idx = list.findIndex(function (x) { return x.key === k; });
        var entryId;
        if (idx !== -1) {
          // Keep the latest formatting of the query text.
          list[idx] = Object.assign({}, list[idx], {
            query: query,
            variables: variablesToString(variables),
            title: summarizeQuery(query, operationName),
            lastRunAt: startedAt,
          });
          entryId = list[idx].id;
        } else {
          var entry = newEntry(k, query, variablesToString(variables), operationName, startedAt);
          list.push(entry);
          entryId = entry.id;
        }
        setRunning(entryId, 1);
        return entryId;
      });
      return { id: id, startedAt: startedAt };
    },

    // outcome: { status: "success" | "partial" | "error" | "cancelled", error: string|null }
    finishRun: function (token, outcome) {
      if (!token) return;
      var durationMs = now() - token.startedAt;
      setRunning(token.id, -1);
      // A no-op when the entry was deleted mid-run; the emit still clears
      // the running marker.
      update(token.id, function (entry) {
        var run = { at: token.startedAt, durationMs: durationMs, status: outcome.status };
        if (outcome.error) run.error = outcome.error;
        entry.runs = [run].concat(entry.runs || []).slice(0, maxRuns);
        entry.runCount = (entry.runCount || 0) + 1;
        return entry;
      });
    },

    toggleFavorite: function (id) {
      update(id, function (entry) {
        entry.favorite = !entry.favorite;
        return entry;
      });
    },

    rename: function (id, label) {
      var trimmed = (label || "").trim();
      update(id, function (entry) {
        entry.label = trimmed || null;
        return entry;
      });
    },

    remove: function (id) {
      mutate(function (list) {
        var idx = list.findIndex(function (x) { return x.id === id; });
        if (idx !== -1) list.splice(idx, 1);
      });
    },

    // Remove everything except favorites.
    clear: function () {
      mutate(function (list) {
        var favs = list.filter(function (x) { return x.favorite; });
        list.length = 0;
        Array.prototype.push.apply(list, favs);
      });
    },
  };
}

// Wrap a GraphiQL Observable fetcher so each user execution is recorded in
// `store` with its outcome (cancelled when GraphiQL unsubscribes before a
// result). Schema introspection passes through unrecorded. History failures
// (e.g. storage errors) go to onError and never affect the execution.
export function withHistory(fetcher, store, onError) {
  var report = onError || function () {};

  return function (graphQLParams, fetcherOpts) {
    var observable = fetcher(graphQLParams, fetcherOpts);
    if (isIntrospectionCall(graphQLParams, fetcherOpts)) return observable;

    return {
      subscribe: function (observer) {
        var token = null;
        var finished = false;
        try {
          token = store.startRun(graphQLParams);
        } catch (e) {
          report(e);
        }

        function finish(outcome) {
          if (finished) return;
          finished = true;
          if (!token) return;
          try {
            store.finishRun(token, outcome);
          } catch (e) {
            report(e);
          }
        }

        var subscription = observable.subscribe({
          next: function (result) {
            finish(classifyResult(result));
            if (observer.next) observer.next(result);
          },
          error: function (error) {
            finish({ status: "error", error: (error && error.message) || String(error) });
            if (observer.error) observer.error(error);
          },
          complete: function () {
            if (observer.complete) observer.complete();
          },
        });

        return {
          unsubscribe: function () {
            finish({ status: "cancelled", error: null });
            subscription.unsubscribe();
          },
        };
      },
    };
  };
}
