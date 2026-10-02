import { describe, it, expect, beforeEach } from "vitest";
import { createHistoryStore, STORAGE_KEY } from "./graphiql-history-store.js";
import { localStorageBackend, memoryBackend } from "./graphiql-storage.js";

// Fake Web Storage (what localStorageBackend wraps).
function memoryStorage(initial) {
  var data = Object.assign({}, initial || {});
  return {
    data: data,
    failures: 0, // next N setItem calls throw like a full quota
    getItem: function (k) { return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null; },
    setItem: function (k, v) {
      if (this.failures > 0) { this.failures--; throw new Error("QuotaExceededError"); }
      data[k] = String(v);
    },
    removeItem: function (k) { delete data[k]; },
  };
}

// Two "browser tabs" on one store: a write notifies the other tabs only,
// like the localStorage `storage` event.
function sharedBackend() {
  var inner = memoryBackend();
  var subs = [];
  return function tab() {
    var view = {
      get: inner.get,
      remove: inner.remove,
      set: function (key, value) {
        return inner.set(key, value).then(function () {
          subs.forEach(function (s) {
            if (s.view !== view && s.key === key) s.fn(JSON.parse(JSON.stringify(value)));
          });
        });
      },
      onChange: function (key, fn) {
        subs.push({ view: view, key: key, fn: fn });
        return function () {};
      },
    };
    return view;
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
  var ls, now, store;

  function open(extra) {
    return createHistoryStore(Object.assign({ storage: localStorageBackend(ls), legacyStorage: ls, now: now }, extra));
  }

  function stored() {
    return JSON.parse(ls.getItem(STORAGE_KEY));
  }

  beforeEach(async function () {
    ls = memoryStorage();
    now = clock();
    store = open();
    await store.ready;
  });

  function run(params, outcome, durationMs) {
    var token = store.startRun(params);
    now.advance(durationMs || 100);
    store.finishRun(token, outcome || { status: "success", error: null });
    now.advance(1000);
    return token;
  }

  var queries = function () { return store.getSnapshot().entries.map(function (e) { return e.query; }); };

  it("records one entry per execution with status and duration", function () {
    run({ query: Q }, { status: "success", error: null }, 250);
    var entries = store.getSnapshot().entries;
    expect(entries.length).toBe(1);
    expect(entries[0].runs[0].status).toBe("success");
    expect(entries[0].runs[0].durationMs).toBe(250);
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
    expect(entries[0].runs[0].error).toBe("boom");
    expect(entries[0].runs.map(function (r) { return r.status; })).toEqual(["error", "success", "success"]);
  });

  it("treats different variables as different entries, ignoring key order", function () {
    run({ query: Q, variables: { a: 1, b: 2 } });
    run({ query: Q, variables: { b: 2, a: 1 } });
    run({ query: Q, variables: { a: 2 } });
    expect(store.getSnapshot().entries.length).toBe(2);
  });

  it("does not duplicate an entry run with {} and then with empty variables", function () {
    run({ query: Q, variables: {} });
    run({ query: Q });
    expect(store.getSnapshot().entries.length).toBe(1);
    expect(store.getSnapshot().entries[0].variables).toBe("");
  });

  it("moves a re-run entry to the top", function () {
    run({ query: "{ a }" });
    run({ query: "{ b }" });
    run({ query: "{ a }" });
    expect(queries()).toEqual(["{ a }", "{ b }"]);
  });

  it("tracks in-flight runs in memory only", async function () {
    var token = store.startRun({ query: Q });
    expect(store.getSnapshot().running[token.id]).toBe(1);
    await store.flush();
    expect(ls.getItem(STORAGE_KEY)).not.toContain("running");
    store.finishRun(token, { status: "success", error: null });
    expect(store.getSnapshot().running[token.id]).toBeUndefined();
  });

  it("ignores empty and oversized queries", function () {
    expect(store.startRun({ query: "" })).toBeNull();
    expect(store.startRun({ query: "   " })).toBeNull();
    expect(store.startRun({ query: "{ a }" + " ".repeat(100001) })).toBeNull();
    expect(store.getSnapshot().entries.length).toBe(0);
  });

  it("never stores headers", async function () {
    run({ query: Q, headers: { Authorization: "Apikey secret" } });
    await store.flush();
    expect(ls.getItem(STORAGE_KEY)).not.toContain("secret");
  });

  it("caps the run log", function () {
    store = open({ maxRuns: 3 });
    for (var i = 0; i < 5; i++) run({ query: Q });
    var entry = store.getSnapshot().entries[0];
    expect(entry.runs.length).toBe(3);
    expect(entry.runCount).toBe(5);
  });

  it("keeps at most maxEntries non-favorites, plus all favorites", function () {
    store = open({ maxEntries: 2 });
    run({ query: "{ a }" });
    store.toggleFavorite(store.getSnapshot().entries[0].id);
    ["{ b }", "{ c }", "{ d }"].forEach(function (q) { run({ query: q }); });
    expect(queries().sort()).toEqual(["{ a }", "{ c }", "{ d }"]);
  });

  it("evicts the least recently run entries to stay within the size budget", async function () {
    store = open({ maxBytes: 1500 });
    var big = function (name) { return "{ " + name + "(x: \"" + "y".repeat(300) + "\") }"; };
    run({ query: big("fav") });
    store.toggleFavorite(store.getSnapshot().entries[0].id);
    ["a", "b", "c", "d", "e"].forEach(function (n) { run({ query: big(n) }); });
    run({ query: big("a") }); // re-running "a" makes it the most recently used
    var names = store.getSnapshot().entries.map(function (e) { return /^\{ (\w+)\(/.exec(e.query)[1]; });
    expect(names[0]).toBe("a");
    expect(names).toContain("fav"); // favorites are never evicted
    expect(names).not.toContain("b"); // least recently run goes first
    await store.flush();
    expect(ls.getItem(STORAGE_KEY).length).toBeLessThanOrEqual(1500 + 600); // budget + the kept newest
  });

  it("always keeps the newest entry even if it alone exceeds the budget", function () {
    store = open({ maxBytes: 10 });
    run({ query: "{ a }" });
    run({ query: "{ b }" });
    expect(queries()).toEqual(["{ b }"]);
  });

  it("clear keeps favorites", function () {
    run({ query: "{ a }" });
    run({ query: "{ b }" });
    store.toggleFavorite(store.getSnapshot().entries[0].id);
    store.clear();
    expect(queries()).toEqual(["{ b }"]);
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

  it("persists across store instances (page reloads)", async function () {
    run({ query: Q });
    await store.flush();
    var again = open();
    await again.ready;
    expect(again.getSnapshot().entries.length).toBe(1);
    expect(again.getSnapshot().entries[0].runCount).toBe(1);
  });

  it("keeps runs recorded before the stored history finished loading", async function () {
    run({ query: "{ old }" });
    await store.flush();
    var again = open();
    var token = again.startRun({ query: "{ old }" }); // before `ready`
    again.finishRun(token, { status: "success", error: null });
    await again.ready;
    expect(again.getSnapshot().entries.length).toBe(1);
    expect(again.getSnapshot().entries[0].runCount).toBe(2);
  });

  it("adopts history saved by another browser tab", async function () {
    var tab = sharedBackend();
    var a = createHistoryStore({ storage: tab(), legacyStorage: null, now: now });
    var b = createHistoryStore({ storage: tab(), legacyStorage: null, now: now });
    await Promise.all([a.ready, b.ready]);
    var token = a.startRun({ query: "{ x }" });
    a.finishRun(token, { status: "success", error: null });
    await a.flush();
    expect(b.getSnapshot().entries.map(function (e) { return e.query; })).toEqual(["{ x }"]);
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

  it("emits once per startRun and once per finishRun", function () {
    var calls = 0;
    store.subscribe(function () { calls++; });
    var token = store.startRun({ query: Q });
    expect(calls).toBe(1);
    store.finishRun(token, { status: "success", error: null });
    expect(calls).toBe(2);
  });

  it("works with the default in-memory backend", async function () {
    store = createHistoryStore({ legacyStorage: null, now: now });
    await store.ready;
    run({ query: Q });
    run({ query: Q });
    expect(store.getSnapshot().entries[0].runCount).toBe(2);
  });

  describe("when the backend refuses writes", function () {
    it("evicts the oldest until the write fits, keeping the newest", async function () {
      ["{ a }", "{ b }", "{ c }"].forEach(function (q) { run({ query: q }); });
      await store.flush();
      ls.failures = 1;
      run({ query: "{ d }" });
      await store.flush();
      expect(queries()[0]).toBe("{ d }");
      expect(stored().entries[0].query).toBe("{ d }");
    });

    it("keeps the only non-favorite when favorites fill the quota", async function () {
      run({ query: "{ fav }" });
      store.toggleFavorite(store.getSnapshot().entries[0].id);
      await store.flush();
      ls.failures = 1;
      run({ query: "{ new }" });
      await store.flush();
      expect(queries()).toContain("{ new }");
    });

    it("keeps everything in memory when no write succeeds", async function () {
      run({ query: "{ a }" });
      await store.flush();
      ls.failures = Infinity;
      run({ query: "{ b }" });
      await store.flush();
      expect(queries()).toEqual(["{ b }", "{ a }"]);
      expect(store.getSnapshot().entries[0].runs.length).toBe(1);
    });

    it("saves again once writes work (e.g. after Clear frees space)", async function () {
      ["{ a }", "{ b }", "{ c }"].forEach(function (q) { run({ query: q }); });
      await store.flush();
      ls.failures = Infinity;
      run({ query: "{ d }" });
      await store.flush();
      ls.failures = 0;
      store.clear();
      await store.flush();
      var reloaded = open();
      await reloaded.ready;
      expect(reloaded.getSnapshot().entries).toEqual([]);
    });
  });

  describe("upgrading history saved by earlier versions", function () {
    async function seed(entries) {
      ls.setItem(STORAGE_KEY, JSON.stringify({ entries: entries }));
      store = open();
      await store.ready;
    }

    it("matches entries saved with full (unhashed) keys", async function () {
      await seed([{ id: "x", key: "{a}\u0000\u0000", query: "{ a }", variables: "", title: "a", lastRunAt: 1, runCount: 3, runs: [] }]);
      run({ query: "{ a }" });
      expect(store.getSnapshot().entries.length).toBe(1);
      expect(store.getSnapshot().entries[0].runCount).toBe(4);
    });

    it("upgrades a 14-character key instead of mistaking it for a hash", async function () {
      // "{getFoo{id}}" + two NULs is 14 chars, the length of a hashed key.
      await seed([{ id: "x", key: "{getFoo{id}}\u0000\u0000", query: "{ getFoo { id } }", variables: "",
        title: "getFoo", lastRunAt: 1, runCount: 2, runs: [] }]);
      run({ query: "{ getFoo { id } }" });
      expect(store.getSnapshot().entries.length).toBe(1);
      expect(store.getSnapshot().entries[0].runCount).toBe(3);
    });

    it("matches entries recorded with {} variables", async function () {
      // Older versions keyed {} as "{}" but stored the variables as "".
      await seed([{ id: "x", key: "{a}\u0000{}\u0000", query: "{ a }", variables: "", title: "a", lastRunAt: 1, runCount: 2, runs: [] }]);
      run({ query: "{ a }", variables: {} });
      expect(store.getSnapshot().entries.length).toBe(1);
      expect(store.getSnapshot().entries[0].runCount).toBe(3);
    });

    it("merges entries that now share a key", async function () {
      await seed([
        { id: "new", key: "{a}\u0000{}\u0000", query: "{ a }", variables: "", title: "a", lastRunAt: 20,
          runCount: 2, runs: [{ at: 20, durationMs: 1, status: "success" }] },
        { id: "old", key: "{a}\u0000\u0000", query: "{ a }", variables: "", title: "a", lastRunAt: 10,
          runCount: 1, favorite: true, label: "Mine", runs: [{ at: 10, durationMs: 2, status: "error" }] },
      ]);
      var entries = store.getSnapshot().entries;
      expect(entries.length).toBe(1);
      expect(entries[0].id).toBe("new");
      expect(entries[0].runCount).toBe(3);
      expect(entries[0].favorite).toBe(true);
      expect(entries[0].label).toBe("Mine");
      expect(entries[0].runs.map(function (r) { return r.at; })).toEqual([20, 10]);
    });

    it("drops fields that were duplicated from the last run, and saves the upgrade", async function () {
      await seed([{ id: "x", key: "abc", query: "{ a }", variables: "", title: "a", lastRunAt: 1,
        runCount: 1, runs: [], lastStatus: "success", lastDurationMs: 5, lastError: null, createdAt: 1 }]);
      await store.flush();
      var saved = stored().entries[0];
      ["lastStatus", "lastDurationMs", "lastError", "createdAt"].forEach(function (f) {
        expect(f in saved).toBe(false);
      });
    });
  });
});

describe("legacy migration", function () {
  it("imports stock GraphiQL history and favorites once, deduplicated", async function () {
    var ls = memoryStorage({
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
    var open = function () {
      return createHistoryStore({ storage: localStorageBackend(ls), legacyStorage: ls, now: clock() });
    };
    var store = open();
    await store.ready;
    var entries = store.getSnapshot().entries;
    expect(entries.map(function (e) { return e.query; })).toEqual(["{  a  }", "{ old }", "{ fav }"]);
    var fav = entries.find(function (e) { return e.favorite; });
    expect(fav.label).toBe("SQL");
    expect(fav.runCount).toBe(0);

    // Removing everything does not re-import.
    entries.forEach(function (e) { store.remove(e.id); });
    await store.flush();
    var again = open();
    await again.ready;
    expect(again.getSnapshot().entries.length).toBe(0);
  });

  it("starts empty when there is nothing to migrate", async function () {
    var store = createHistoryStore({ storage: memoryBackend(), legacyStorage: memoryStorage(), now: clock() });
    await store.ready;
    expect(store.getSnapshot().entries).toEqual([]);
  });
});
