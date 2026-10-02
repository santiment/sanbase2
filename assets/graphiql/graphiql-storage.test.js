import { describe, it, expect, vi, afterEach } from "vitest";
import { localStorageBackend, memoryBackend } from "./graphiql-storage.js";
import { fakeLocalStorage } from "./graphiql-test-support.js";

// Every backend must behave the same; run the contract against each.
var backends = {
  localStorage: function () { return localStorageBackend(fakeLocalStorage()); },
  memory: memoryBackend,
};

Object.keys(backends).forEach(function (name) {
  describe(name + " backend", function () {
    it("stores, returns copies of, and removes JSON values", async function () {
      var b = backends[name]();
      var value = { entries: [{ a: 1 }] };
      expect(await b.get("k")).toBeNull();
      await b.set("k", value);
      var read = await b.get("k");
      expect(read).toEqual(value);
      expect(read).not.toBe(value);
      await b.remove("k");
      expect(await b.get("k")).toBeNull();
    });

    it("returns an unsubscribe function from onChange", function () {
      var off = backends[name]().onChange("k", function () {});
      expect(typeof off).toBe("function");
      off();
    });
  });
});

describe("localStorage backend", function () {
  it("rejects writes the browser refuses (quota)", async function () {
    var ls = fakeLocalStorage();
    ls.failures = Infinity;
    await expect(localStorageBackend(ls).set("k", { a: 1 })).rejects.toThrow();
  });

  it("reads unparsable or unavailable storage as null", async function () {
    var ls = fakeLocalStorage();
    ls.data.k = "{not json";
    expect(await localStorageBackend(ls).get("k")).toBeNull();
    expect(await localStorageBackend(null).get("k")).toBeNull();
    await expect(localStorageBackend(null).set("k", 1)).rejects.toThrow();
  });
});

describe("localStorage backend onChange (other browser tabs)", function () {
  afterEach(function () { vi.unstubAllGlobals(); });

  function storageEvent(key, newValue) {
    return Object.assign(new Event("storage"), { key: key, newValue: newValue });
  }

  it("delivers parsed values for its key only, null on clear(), nothing after unsubscribe", function () {
    var win = new EventTarget();
    vi.stubGlobal("window", win);
    var seen = [];
    var off = localStorageBackend(fakeLocalStorage()).onChange("k", function (v) { seen.push(v); });
    win.dispatchEvent(storageEvent("k", JSON.stringify({ a: 1 })));
    win.dispatchEvent(storageEvent("other", JSON.stringify({ b: 2 })));
    win.dispatchEvent(storageEvent(null, null)); // localStorage.clear() in another tab
    win.dispatchEvent(storageEvent("k", "{corrupt"));
    off();
    win.dispatchEvent(storageEvent("k", JSON.stringify({ c: 3 })));
    expect(seen).toEqual([{ a: 1 }, null, null]);
  });
});
