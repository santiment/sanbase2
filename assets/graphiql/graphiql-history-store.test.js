import { describe, it, expect, beforeEach } from "vitest";
import { createHistoryStore, STORAGE_KEY } from "./graphiql-history-store.js";

function memoryStorage(initial) {
  var data = Object.assign({}, initial || {});
  return {
    data: data,
    getItem: function (k) { return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null; },
    setItem: function (k, v) { data[k] = String(v); },
    removeItem: function (k) { delete data[k]; },
  };
}

function clock(start) {
  var t = start || 1000000;
  var fn = function () { return t; };
  fn.advance = function (ms) { t += ms; };
  return fn;
}

var Q = '{ getMetric(metric: "dev_activity") { timeseriesDataJson(selector: {organization: "ethereum"}) } }';

describe("history store", function () {
  var storage, now, store;

  beforeEach(function () {
    storage = memoryStorage();
    now = clock();
    store = createHistoryStore({ storage: storage, now: now });
  });

  function run(params, outcome, durationMs) {
    var token = store.startRun(params);
    now.advance(durationMs || 100);
    store.finishRun(token, outcome || { status: "success", error: null });
    now.advance(1000);
    return token;
  }

  it("records one entry per execution with status and duration", function () {
    run({ query: Q }, { status: "success", error: null }, 250);
    var entries = store.getSnapshot().entries;
    expect(entries.length).toBe(1);
    expect(entries[0].lastStatus).toBe("success");
    expect(entries[0].lastDurationMs).toBe(250);
    expect(entries[0].runCount).toBe(1);
    expect(entries[0].title).toBe("getMetric(dev_activity)");
  });

  it("does not create a new entry when the same query is executed again", function () {
    run({ query: Q });
    run({ query: Q.replace(/ /g, "  ") }); // reformatted, same query
    run({ query: Q }, { status: "error", error: "boom" }, 50);
    var entries = store.getSnapshot().entries;
    expect(entries.length).toBe(1);
    expect(entries[0].runCount).toBe(3);
    expect(entries[0].lastStatus).toBe("error");
    expect(entries[0].lastError).toBe("boom");
    expect(entries[0].runs.map(function (r) { return r.status; })).toEqual(["error", "success", "success"]);
  });

  it("treats different variables as different entries, ignoring key order", function () {
    run({ query: Q, variables: { a: 1, b: 2 } });
    run({ query: Q, variables: { b: 2, a: 1 } });
    run({ query: Q, variables: { a: 2 } });
    expect(store.getSnapshot().entries.length).toBe(2);
  });

  it("moves a re-run entry to the top", function () {
    run({ query: "{ a }" });
    run({ query: "{ b }" });
    run({ query: "{ a }" });
    expect(store.getSnapshot().entries.map(function (e) { return e.query; })).toEqual(["{ a }", "{ b }"]);
  });

  it("does not record anything from edits (only startRun records)", function () {
    // Regression: the stock plugin saved "e", "et", "eth", ... while a query ran.
    var token = store.startRun({ query: Q });
    now.advance(5000);
    store.finishRun(token, { status: "success", error: null });
    expect(store.getSnapshot().entries.length).toBe(1);
  });

  it("tracks in-flight runs in memory only", function () {
    var token = store.startRun({ query: Q });
    var id = token.id;
    expect(store.getSnapshot().running[id]).toBe(1);
    expect(storage.getItem(STORAGE_KEY)).not.toContain("running");
    store.finishRun(token, { status: "success", error: null });
    expect(store.getSnapshot().running[id]).toBeUndefined();
  });

  it("ignores empty and oversized queries", function () {
    expect(store.startRun({ query: "" })).toBeNull();
    expect(store.startRun({ query: "   " })).toBeNull();
    expect(store.startRun({ query: "{ a }" + " ".repeat(100001) })).toBeNull();
    expect(store.getSnapshot().entries.length).toBe(0);
  });

  it("never stores headers", function () {
    run({ query: Q, headers: { Authorization: "Apikey secret" } });
    expect(storage.getItem(STORAGE_KEY)).not.toContain("secret");
  });

  it("caps the run log", function () {
    store = createHistoryStore({ storage: storage, now: now, maxRuns: 3 });
    for (var i = 0; i < 5; i++) run({ query: Q });
    var entry = store.getSnapshot().entries[0];
    expect(entry.runs.length).toBe(3);
    expect(entry.runCount).toBe(5);
  });

  it("prunes oldest non-favorites but keeps favorites", function () {
    store = createHistoryStore({ storage: storage, now: now, maxEntries: 2 });
    run({ query: "{ a }" });
    store.toggleFavorite(store.getSnapshot().entries[0].id);
    run({ query: "{ b }" });
    run({ query: "{ c }" });
    run({ query: "{ d }" });
    var queries = store.getSnapshot().entries.map(function (e) { return e.query; }).sort();
    expect(queries).toEqual(["{ a }", "{ c }", "{ d }"]);
  });

  it("clear keeps favorites", function () {
    run({ query: "{ a }" });
    run({ query: "{ b }" });
    var b = store.getSnapshot().entries[0];
    store.toggleFavorite(b.id);
    store.clear();
    var entries = store.getSnapshot().entries;
    expect(entries.length).toBe(1);
    expect(entries[0].query).toBe("{ b }");
  });

  it("renames and removes entries", function () {
    run({ query: "{ a }" });
    var id = store.getSnapshot().entries[0].id;
    store.rename(id, "  My query  ");
    expect(store.getSnapshot().entries[0].label).toBe("My query");
    store.rename(id, "   ");
    expect(store.getSnapshot().entries[0].label).toBeNull();
    store.remove(id);
    expect(store.getSnapshot().entries.length).toBe(0);
  });

  it("finishing a run for a deleted entry is a no-op", function () {
    var token = store.startRun({ query: Q });
    store.remove(token.id);
    store.finishRun(token, { status: "success", error: null });
    expect(store.getSnapshot().entries.length).toBe(0);
    expect(store.getSnapshot().running[token.id]).toBeUndefined();
  });

  it("persists across store instances", function () {
    run({ query: Q });
    var again = createHistoryStore({ storage: storage, now: now });
    expect(again.getSnapshot().entries.length).toBe(1);
    expect(again.getSnapshot().entries[0].runCount).toBe(1);
  });

  it("does not overwrite entries written by another browser tab", function () {
    var other = createHistoryStore({ storage: storage, now: now });
    run({ query: "{ a }" });
    var t = other.startRun({ query: "{ b }" });
    other.finishRun(t, { status: "success", error: null });
    store.reload();
    expect(store.getSnapshot().entries.length).toBe(2);
  });

  it("notifies subscribers and returns a stable snapshot between changes", function () {
    var calls = 0;
    var unsubscribe = store.subscribe(function () { calls++; });
    var before = store.getSnapshot();
    expect(store.getSnapshot()).toBe(before);
    run({ query: Q });
    expect(calls).toBeGreaterThan(0);
    expect(store.getSnapshot()).not.toBe(before);
    unsubscribe();
  });

  it("works without storage", function () {
    store = createHistoryStore({ storage: null, now: now });
    run({ query: Q });
    run({ query: Q });
    expect(store.getSnapshot().entries.length).toBe(1);
    expect(store.getSnapshot().entries[0].runCount).toBe(2);
  });

  it("survives a quota error by dropping older entries", function () {
    var failNext = false;
    var s = memoryStorage();
    var setItem = s.setItem;
    s.setItem = function (k, v) {
      if (failNext) { failNext = false; throw new Error("QuotaExceededError"); }
      setItem(k, v);
    };
    store = createHistoryStore({ storage: s, now: now });
    run({ query: "{ a }" });
    run({ query: "{ b }" });
    failNext = true;
    run({ query: "{ c }" });
    expect(store.getSnapshot().entries.length).toBeGreaterThan(0);
  });
});

describe("legacy migration", function () {
  it("imports stock GraphiQL history and favorites once, deduplicated", function () {
    var storage = memoryStorage({
      "graphiql:queries": JSON.stringify({
        queries: [
          { query: "{ old }" },
          { query: "{ a }", variables: '{"x": 1}' },
          { query: "{  a  }", variables: '{"x":1}' }, // keystroke-style duplicate
        ],
      }),
      "graphiql:favorites": JSON.stringify({
        favorites: [{ query: "{ fav }", label: "SQL", favorite: true }],
      }),
    });
    var store = createHistoryStore({ storage: storage, now: clock() });
    var entries = store.getSnapshot().entries;
    expect(entries.map(function (e) { return e.query; })).toEqual(["{  a  }", "{ old }", "{ fav }"]);
    var fav = entries.find(function (e) { return e.favorite; });
    expect(fav.label).toBe("SQL");
    expect(fav.runCount).toBe(0);

    // Removing everything does not re-import.
    entries.forEach(function (e) { store.remove(e.id); });
    var again = createHistoryStore({ storage: storage, now: clock() });
    expect(again.getSnapshot().entries.length).toBe(0);
  });

  it("starts empty when there is nothing to migrate", function () {
    var store = createHistoryStore({ storage: memoryStorage(), now: clock() });
    expect(store.getSnapshot().entries).toEqual([]);
  });
});
