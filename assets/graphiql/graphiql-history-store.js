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
 * - History stays within a size budget (default 1MB of serialized JSON, well
 *   under browser storage quotas) and at most 100 entries: the entries run
 *   longest ago are evicted first. Favorites are never evicted, the most
 *   recently run entry is always kept, and so is an entry the user just
 *   un-favorited or renamed. Runs whose query + variables exceed 100KB are
 *   not recorded.
 * - Headers are never stored: they usually carry API keys.
 * - Memory is the source of truth: changes show immediately and are
 *   persisted in order through a swappable storage backend (see
 *   graphiql-storage.js). A save from another browser tab is merged in:
 *   its list wins, except for entries this tab added since it last synced
 *   (kept) and runs this tab has that the other lacks (combined).
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
var MAX_ENTRY_SIZE = 100000; // query + variables; the stock history limited the query alone
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
  // Before the `imported` flag, entries imported from the stock history were
  // the only ones saved without any run.
  var unflagged = entry.imported === undefined && !entry.runCount && !(entry.runs && entry.runs.length);
  if (!stale && !oldKey && !unflagged) return entry;
  var copy = Object.assign({}, entry);
  DROPPED_FIELDS.forEach(function (f) { delete copy[f]; });
  if (unflagged) copy.imported = true;
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
//   onError        - called with unexpected persistence errors
//   maxEntries, maxBytes, maxRuns, now - limits and clock (tests)
export function createHistoryStore(options) {
  var opts = options || {};
  var storage = opts.storage || memoryBackend();
  var legacyStorage = opts.legacyStorage !== undefined ? opts.legacyStorage : defaultStorage();
  var onError = opts.onError || function () {};
  var maxEntries = opts.maxEntries || 100;
  var maxBytes = opts.maxBytes || 1000000; // characters of serialized JSON
  var maxRuns = opts.maxRuns || 20;
  var now = opts.now || Date.now;

  var entries = [];
  var running = {}; // entry id -> number of in-flight runs (memory only)
  var listeners = new Set();
  var snapshot = { entries: entries, running: running };

  function emit() {
    snapshot = { entries: entries, running: running };
    listeners.forEach(function (l) { l(); });
  }

  function size(entry) {
    return JSON.stringify(entry).length;
  }

  // Least recently run first out. `list` is sorted newest first. Keeps
  // favorites and `keepId` (an entry the user is acting on), then the other
  // entries from the newest while they fit the count and size budget. The
  // newest is always kept (counted only if it fits, so a large newest entry
  // cannot evict everything older); any other entry too big for the space
  // left is dropped on its own.
  function evict(list, keepId) {
    function pinned(x) { return x.favorite || x.id === keepId; }
    var used = list.reduce(function (sum, x) { return pinned(x) ? sum + size(x) : sum; }, 0);
    var kept = 0;
    return list.filter(function (x) {
      if (pinned(x)) return true;
      var s = size(x);
      if (kept === 0) {
        kept++;
        if (used + s <= maxBytes) used += s;
        return true;
      }
      if (kept >= maxEntries || used + s > maxBytes) return false;
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

  // Set when not even the smallest list could be written (storage blocked,
  // or the origin's quota used up by other data). While set, each change
  // makes a single attempt instead of running the eviction loop again.
  var blocked = false;

  // Write `list`; if the backend refuses (quota), evict one more entry at a
  // time until it fits. The evicted entries are then dropped from memory
  // too, so the next save starts from what fits instead of repeating the
  // loop. If nothing fits, history keeps working in memory.
  function write(list) {
    function attempt(candidate) {
      return storage.set(STORAGE_KEY, { entries: candidate }).then(function () {
        blocked = false;
        markSynced(candidate);
        if (candidate.length < list.length) forget(list, candidate);
      }, function () {
        if (blocked || !evictable(candidate)) {
          blocked = true;
          return undefined;
        }
        return attempt(dropOldest(candidate));
      });
    }
    return attempt(list);
  }

  // Remove from memory the entries of `list` that did not fit in `kept`,
  // unless they changed since (e.g. were re-run while saving).
  function forget(list, kept) {
    var dropped = new Set(list.filter(function (e) { return kept.indexOf(e) === -1; }));
    entries = entries.filter(function (e) { return !dropped.has(e); });
    emit();
  }

  // Ids of the entries this tab last loaded, wrote or adopted: an entry
  // missing from another tab's save was deleted there if it is in this set,
  // and is new in this tab otherwise.
  var synced = new Set();
  function markSynced(list) {
    synced = new Set(list.map(function (e) { return e.id; }));
  }

  // Same entry in both tabs: the other tab's version (its label/favorite are
  // the latest edit) plus this tab's runs and timestamps. Symmetric, so two
  // tabs agree after one exchange instead of saving back and forth.
  function combine(l, r) {
    var ats = new Set((r.runs || []).map(function (x) { return x.at; }));
    var extraRuns = (l.runs || []).filter(function (x) { return !ats.has(x.at); });
    var runCount = Math.max(l.runCount || 0, r.runCount || 0);
    var lastRunAt = Math.max(l.lastRunAt || 0, r.lastRunAt || 0);
    if (!extraRuns.length && runCount === (r.runCount || 0) && lastRunAt === (r.lastRunAt || 0)) return r;
    return Object.assign({}, r, {
      runCount: runCount,
      lastRunAt: lastRunAt,
      runs: (r.runs || []).concat(extraRuns)
        .sort(function (a, b) { return b.at - a.at; })
        .slice(0, maxRuns),
    });
  }

  // Merge another tab's saved list with this tab's entries.
  function mergeRemote(remote) {
    var local = new Map(entries.map(function (e) { return [e.id, e]; }));
    var remoteIds = new Set();
    var keptLocal = false;
    var merged = remote.map(function (r) {
      remoteIds.add(r.id);
      var l = local.get(r.id);
      var c = l ? combine(l, r) : r;
      if (c !== r) keptLocal = true;
      return c;
    });
    entries.forEach(function (e) {
      if (!remoteIds.has(e.id) && !synced.has(e.id)) {
        merged.push(e);
        keptLocal = true;
      }
    });
    return { list: merged, keptLocal: keptLocal };
  }

  // Saves are chained so they reach the backend in order, start only after
  // the initial load, and always write the latest list (several changes in
  // a row become one write). A failed save never blocks later ones.
  var saveQueued = false;
  var saving; // set once `ready` exists

  function persist() {
    if (saveQueued) return saving;
    saveQueued = true;
    saving = saving.then(function () {
      saveQueued = false;
      return write(entries);
    }).catch(onError);
    return saving;
  }

  function normalize(list) {
    return evict(mergeDuplicates(sortHistory(list, "recent"), maxRuns));
  }

  function mutate(fn, keepId) {
    var list = entries.slice();
    var result = fn(list);
    entries = evict(sortHistory(list, "recent"), keepId);
    emit();
    persist();
    return result;
  }

  // Stored entries, upgraded; malformed ones are skipped instead of failing
  // the whole load.
  function fromStored(data) {
    if (!data || !Array.isArray(data.entries)) return null;
    var out = [];
    data.entries.forEach(function (e) {
      if (!e || typeof e !== "object" || typeof e.query !== "string" || !e.id) return;
      try {
        out.push(upgradeEntry(e));
      } catch (err) {
        onError(err);
      }
    });
    return out;
  }

  function migrateLegacy() {
    var legacyQueries = readJson(legacyStorage, LEGACY_QUERIES_KEY);
    var legacyFavorites = readJson(legacyStorage, LEGACY_FAVORITES_KEY);
    // Stock stores are ordered oldest first.
    var items = []
      .concat((legacyFavorites && legacyFavorites.favorites) || [])
      .concat((legacyQueries && legacyQueries.queries) || [])
      .reverse();

    // Duplicates (same key) are merged by normalize().
    var t = now();
    return items.filter(function (item) {
      return item && typeof item.query === "string" && item.query;
    }).map(function (item, i) {
      var k = entryKey(item.query, variablesToObject(item.variables), item.operationName);
      var entry = newEntry(k, item.query, variablesToString(item.variables), item.operationName, t - i);
      entry.favorite = !!item.favorite;
      entry.label = item.label || null;
      entry.imported = true; // no real run time or runs
      return entry;
    });
  }

  // Initial load. Runs recorded before it finishes are merged in (they are
  // the newest). The result is written back when it differs from what was
  // stored: first use (legacy import), upgraded, skipped or merged entries.
  var loaded = false;
  var remoteBeforeLoad; // another tab's save that arrived during the load
  var ready = storage.get(STORAGE_KEY)
    .catch(function () { return null; })
    .then(function (data) {
      loaded = true;
      if (remoteBeforeLoad !== undefined) data = remoteBeforeLoad;
      var stored = fromStored(data);
      var hadLocal = entries.length > 0;
      var upgraded = stored && (stored.length !== data.entries.length ||
        stored.some(function (e, i) { return e !== data.entries[i]; }));
      entries = normalize(entries.concat(stored || migrateLegacy()));
      markSynced(stored || []);
      emit();
      var changed = stored ? hadLocal || upgraded || entries.length !== stored.length : entries.length > 0;
      if (changed) persist();
    });
  saving = ready.catch(onError);

  // Another browser tab saved history: merge it in, and save the result if
  // this tab contributed entries the other tab did not have.
  storage.onChange(STORAGE_KEY, function (data) {
    if (!loaded) {
      remoteBeforeLoad = data;
      return;
    }
    var remote = fromStored(data) || [];
    var result = mergeRemote(remote);
    entries = normalize(result.list);
    markSynced(remote);
    emit();
    if (result.keptLocal) persist();
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
      imported: false,
    };
  }

  function update(id, fn, keepId) {
    mutate(function (list) {
      var idx = list.findIndex(function (x) { return x.id === id; });
      if (idx !== -1) list[idx] = fn(Object.assign({}, list[idx]));
    }, keepId);
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
      if (!query || !query.trim()) return null;
      var variables = params.variables;
      if (query.length + variablesToString(variables).length > MAX_ENTRY_SIZE) return null;
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

    // Both keep the entry even if it would now be evicted: un-favoriting an
    // old entry must not make it disappear under the user's cursor.
    toggleFavorite: function (id) {
      update(id, function (entry) {
        entry.favorite = !entry.favorite;
        return entry;
      }, id);
    },

    rename: function (id, label) {
      var trimmed = (label || "").trim();
      update(id, function (entry) {
        entry.label = trimmed || null;
        return entry;
      }, id);
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
            finish({ status: "error", error: "No response" }); // no-op after next()
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
