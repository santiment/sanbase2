/**
 * Query history store for GraphiQL, persisted in localStorage.
 *
 * Replaces the stock @graphiql/plugin-history recording, which saved an entry
 * on every keystroke while a query was in flight (its effect depends on
 * [isFetching, activeTab]). Here entries are recorded from the fetcher, which
 * GraphiQL calls exactly once per execution.
 *
 * - Re-running the same query + variables (ignoring formatting) updates the
 *   existing entry and moves it to the top instead of adding a new one.
 * - Each entry keeps its last run status, duration and error, plus a short
 *   log of recent runs.
 * - Headers are never stored: they usually carry API keys.
 * - Every mutation re-reads storage first, so several browser tabs do not
 *   overwrite each other's history.
 *
 * No React/GraphiQL imports, so it can be unit-tested in node.
 */
import { entryKey, summarizeQuery } from "./graphiql-history-utils.js";

export var STORAGE_KEY = "san-graphiql-history";
var VERSION = 1;
var MAX_QUERY_SIZE = 100000; // same limit as the stock history

// Stock @graphiql/toolkit keys, imported once so existing favorites survive.
var LEGACY_QUERIES_KEY = "graphiql:queries";
var LEGACY_FAVORITES_KEY = "graphiql:favorites";

function defaultStorage() {
  try {
    return typeof localStorage !== "undefined" ? localStorage : null;
  } catch (e) {
    return null; // access can throw when site data is blocked
  }
}

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
  if (!variables) return null;
  if (typeof variables !== "string") return variables;
  try {
    return JSON.parse(variables);
  } catch (e) {
    return variables; // keep invalid JSON as-is; still part of the identity
  }
}

function readJson(storage, key) {
  try {
    var raw = storage.getItem(key);
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    return null;
  }
}

export function createHistoryStore(options) {
  var opts = options || {};
  var storage = opts.storage !== undefined ? opts.storage : defaultStorage();
  var key = opts.key || STORAGE_KEY;
  var maxEntries = opts.maxEntries || 100;
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

  function load() {
    if (!storage) return entries;
    var data = readJson(storage, key);
    if (data && Array.isArray(data.entries)) return data.entries;
    if (data === null) return migrateLegacy();
    return [];
  }

  function save(list) {
    var pruned = prune(list);
    if (!storage) return pruned;
    try {
      storage.setItem(key, JSON.stringify({ version: VERSION, entries: pruned }));
    } catch (e) {
      // Quota exceeded: keep favorites and the newer half of the rest.
      var favs = pruned.filter(function (x) { return x.favorite; });
      var rest = pruned.filter(function (x) { return !x.favorite; });
      pruned = sortEntries(favs.concat(rest.slice(0, Math.floor(rest.length / 2))));
      try {
        storage.setItem(key, JSON.stringify({ version: VERSION, entries: pruned }));
      } catch (e2) {
        // Give up persisting; history still works for this page session.
      }
    }
    return pruned;
  }

  // Drop the oldest non-favorites beyond maxEntries. Favorites never expire.
  function prune(list) {
    var kept = 0;
    return list.filter(function (x) {
      if (x.favorite) return true;
      kept++;
      return kept <= maxEntries;
    });
  }

  function sortEntries(list) {
    return list.slice().sort(function (a, b) { return (b.lastRunAt || 0) - (a.lastRunAt || 0); });
  }

  function mutate(fn) {
    var list = load().slice();
    var result = fn(list);
    entries = save(sortEntries(list));
    emit();
    return result;
  }

  function migrateLegacy() {
    var legacyQueries = readJson(storage, LEGACY_QUERIES_KEY);
    var legacyFavorites = readJson(storage, LEGACY_FAVORITES_KEY);
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

    list = sortEntries(list);
    // Always write (even an empty list) so migration runs only once.
    return save(list);
  }

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
      createdAt: at,
      lastRunAt: at,
      runCount: 0,
      lastStatus: null,
      lastDurationMs: null,
      lastError: null,
      runs: [],
    };
  }

  function update(id, fn) {
    return mutate(function (list) {
      var idx = list.findIndex(function (x) { return x.id === id; });
      if (idx === -1) return false;
      list[idx] = fn(Object.assign({}, list[idx]));
      return true;
    });
  }

  entries = sortEntries(load());
  snapshot = { entries: entries, running: running };

  return {
    getSnapshot: function () { return snapshot; },

    subscribe: function (listener) {
      listeners.add(listener);
      return function () { listeners.delete(listener); };
    },

    // Re-read storage (e.g. after another browser tab changed it).
    reload: function () {
      entries = sortEntries(load());
      emit();
    },

    storageKey: key,

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
        var existing = list.find(function (x) { return x.key === k; });
        if (existing) {
          var idx = list.indexOf(existing);
          // Keep the latest formatting of the query text.
          list[idx] = Object.assign({}, existing, {
            query: query,
            variables: variablesToString(variables),
            title: summarizeQuery(query, operationName),
            lastRunAt: startedAt,
          });
          return existing.id;
        }
        var entry = newEntry(k, query, variablesToString(variables), operationName, startedAt);
        list.push(entry);
        return entry.id;
      });

      running = Object.assign({}, running);
      running[id] = (running[id] || 0) + 1;
      emit();
      return { id: id, startedAt: startedAt };
    },

    // outcome: { status: "success" | "partial" | "error", error: string|null }
    finishRun: function (token, outcome) {
      if (!token) return;
      var finishedAt = now();
      var durationMs = finishedAt - token.startedAt;

      running = Object.assign({}, running);
      if (running[token.id] > 1) running[token.id]--;
      else delete running[token.id];

      var updated = update(token.id, function (entry) {
        var run = { at: token.startedAt, durationMs: durationMs, status: outcome.status };
        if (outcome.error) run.error = outcome.error;
        entry.runs = [run].concat(entry.runs || []).slice(0, maxRuns);
        entry.runCount = (entry.runCount || 0) + 1;
        entry.lastStatus = outcome.status;
        entry.lastDurationMs = durationMs;
        entry.lastError = outcome.error || null;
        return entry;
      });
      // Entry was deleted mid-run: still clear the running marker.
      if (!updated) emit();
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
