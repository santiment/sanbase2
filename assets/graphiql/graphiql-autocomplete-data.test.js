import { describe, it, expect, vi } from "vitest";
import { createAutocompleteData, CACHE_KEY } from "./graphiql-autocomplete-data.js";
import { createRequest } from "./graphiql-fetcher.js";
import { localStorageBackend } from "./graphiql-storage.js";

function memoryStorage() {
  var data = {};
  return {
    data: data,
    getItem: function (k) { return k in data ? data[k] : null; },
    setItem: function (k, v) { data[k] = String(v); },
    removeItem: function (k) { delete data[k]; },
  };
}

var LISTS = {
  getAvailableMetrics: ["price_usd", "dev_activity"],
  allProjects: [{ slug: "bitcoin", name: "Bitcoin", ticker: "BTC" }, { slug: null }],
};

function fakeRequest() {
  return vi.fn(function (query, variables) {
    if (query.indexOf("getAvailableMetrics") !== -1) return Promise.resolve(LISTS);
    if (query.indexOf("availableSlugs") !== -1) {
      return Promise.resolve({ getMetric: { metadata: { availableSlugs: ["bitcoin"] } } });
    }
    if (query.indexOf("humanReadableName") !== -1) {
      return Promise.resolve({ getMetric: { metadata: { humanReadableName: variables.metric.toUpperCase() } } });
    }
    return Promise.reject(new Error("unexpected"));
  });
}

describe("autocomplete data", function () {
  it("loads lists once, sorted and cleaned, and caches them in storage", async function () {
    var request = fakeRequest();
    var storage = memoryStorage();
    var data = createAutocompleteData({ request: request, storage: localStorageBackend(storage), now: function () { return 1000; } });
    var lists = await data.getLists();
    await data.getLists();
    expect(request).toHaveBeenCalledTimes(1);
    expect(lists.metrics).toEqual(["dev_activity", "price_usd"]);
    expect(lists.projects.map(function (p) { return p.slug; })).toEqual(["bitcoin"]);
    expect(lists.projects[0].lower).toEqual(["bitcoin", "bitcoin", "btc"]);
    var cached = JSON.parse(storage.getItem(CACHE_KEY));
    expect(cached.projects).toEqual([["bitcoin", "Bitcoin", "BTC"]]);
  });

  it("uses the storage cache on the next page load without a request", async function () {
    var storage = memoryStorage();
    await createAutocompleteData({ request: fakeRequest(), storage: localStorageBackend(storage), now: function () { return 1000; } }).getLists();
    var request = fakeRequest();
    var data = createAutocompleteData({ request: request, storage: localStorageBackend(storage), now: function () { return 2000; } });
    var lists = await data.getLists();
    expect(request).not.toHaveBeenCalled();
    expect(lists.metrics).toEqual(["dev_activity", "price_usd"]);
  });

  it("answers from a stale cache and refreshes in the background", async function () {
    var storage = memoryStorage();
    await createAutocompleteData({ request: fakeRequest(), storage: localStorageBackend(storage), now: function () { return 0; } }).getLists();
    var request = fakeRequest();
    var data = createAutocompleteData({ request: request, storage: localStorageBackend(storage), now: function () { return 25 * 3600 * 1000; } });
    var lists = await data.getLists();
    expect(lists.metrics.length).toBe(2);
    expect(request).toHaveBeenCalledTimes(1);
  });

  it("backs off for 30s after a failure, then retries", async function () {
    var fail = true;
    var t = 0;
    var request = vi.fn(function () {
      return fail ? Promise.reject(new Error("down")) : Promise.resolve(LISTS);
    });
    var data = createAutocompleteData({ request: request, storage: null, now: function () { return t; } });
    await expect(data.getLists()).rejects.toThrow("down");
    fail = false;
    t = 10 * 1000;
    await expect(data.getLists()).rejects.toThrow("down"); // still backing off
    expect(request).toHaveBeenCalledTimes(1);
    t = 31 * 1000;
    expect((await data.getLists()).metrics.length).toBe(2);
    expect(request).toHaveBeenCalledTimes(2);
  });

  it("refreshes a stale cache only once even when the refresh keeps failing", async function () {
    var storage = memoryStorage();
    await createAutocompleteData({ request: fakeRequest(), storage: localStorageBackend(storage), now: function () { return 0; } }).getLists();
    var request = vi.fn(function () { return Promise.reject(new Error("down")); });
    var t = 25 * 3600 * 1000;
    var data = createAutocompleteData({ request: request, storage: localStorageBackend(storage), now: function () { return t; } });
    for (var i = 0; i < 5; i++) expect((await data.getLists()).metrics.length).toBe(2);
    expect(request).toHaveBeenCalledTimes(1);
  });

  it("does not cache a lookup whose result has no metadata", async function () {
    var t = 0;
    var request = vi.fn(function () { return Promise.resolve({ getMetric: null }); });
    var data = createAutocompleteData({ request: request, storage: null, now: function () { return t; } });
    await expect(data.getMetricMeta("nope")).rejects.toThrow();
    t = 31 * 1000;
    await expect(data.getMetricMeta("nope")).rejects.toThrow();
    expect(request).toHaveBeenCalledTimes(2);
  });

  it("memoizes per-metric lookups in memory only", async function () {
    var request = fakeRequest();
    var storage = memoryStorage();
    var data = createAutocompleteData({ request: request, storage: localStorageBackend(storage) });
    var s1 = await data.getMetricSlugs("price_usd");
    await data.getMetricSlugs("price_usd");
    expect(s1.has("bitcoin")).toBe(true);
    expect((await data.getMetricMeta("nvt")).humanReadableName).toBe("NVT");
    expect(request).toHaveBeenCalledTimes(2);
    expect(Object.keys(storage.data)).toEqual([]);
  });

  it("works when storage throws", async function () {
    var storage = {
      getItem: function () { throw new Error("blocked"); },
      setItem: function () { throw new Error("blocked"); },
    };
    var data = createAutocompleteData({ request: fakeRequest(), storage: localStorageBackend(storage) });
    expect((await data.getLists()).metrics.length).toBe(2);
  });
});

describe("createRequest", function () {
  function response(status, text) {
    return Promise.resolve({ status: status, statusText: "", text: function () { return Promise.resolve(text); } });
  }

  it("sends the query with editor headers and resolves to data", async function () {
    var fetchImpl = vi.fn(function () { return response(200, '{"data":{"a":1}}'); });
    var request = createRequest({ endpoint: "/graphql", fetchImpl: fetchImpl, getHeaders: function () { return { Authorization: "Apikey k" }; } });
    expect(await request("{ a }", { x: 1 })).toEqual({ a: 1 });
    var init = fetchImpl.mock.calls[0][1];
    expect(init.headers.Authorization).toBe("Apikey k");
    expect(JSON.parse(init.body)).toEqual({ query: "{ a }", variables: { x: 1 } });
  });

  it("rejects on errors without data and on non-JSON responses", async function () {
    var request = createRequest({ endpoint: "/graphql", fetchImpl: function () { return response(200, '{"errors":[{"message":"nope"}]}'); } });
    await expect(request("{ a }")).rejects.toThrow("nope");
    var html = createRequest({ endpoint: "/graphql", fetchImpl: function () { return response(502, "<h1>Bad Gateway</h1>"); } });
    await expect(html("{ a }")).rejects.toThrow("HTTP 502");
  });

  it("rejects partial data, so a field error is never cached as an empty list", async function () {
    var request = createRequest({ endpoint: "/graphql", fetchImpl: function () { return response(200, '{"data":{"allProjects":null,"b":1},"errors":[{"message":"a failed"}]}'); } });
    await expect(request("{ a b }")).rejects.toThrow("a failed");
  });
});
