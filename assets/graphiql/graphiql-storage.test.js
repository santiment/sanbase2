import { describe, it, expect } from "vitest";
import { localStorageBackend, memoryBackend } from "./graphiql-storage.js";

function fakeLocalStorage() {
  var data = {};
  return {
    data: data,
    full: false,
    getItem: function (k) { return k in data ? data[k] : null; },
    setItem: function (k, v) {
      if (this.full) throw new Error("QuotaExceededError");
      data[k] = String(v);
    },
    removeItem: function (k) { delete data[k]; },
  };
}

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
    ls.full = true;
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
