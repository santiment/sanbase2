import { describe, it, expect, vi } from "vitest";
import { createAutocompleteData, CACHE_KEY } from "./graphiql-autocomplete-data.js";
import { createRequest } from "./graphiql-fetcher.js";

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
    if (query.indexOf("SanAutocompleteLists") !== -1) return Promise.resolve(LISTS);
    if (query.indexOf("SanAutocompleteSlugs") !== -1) {
      return Promise.resolve({ getMetric: { metadata: { availableSlugs: ["bitcoin"] } } });
    }
    if (query.indexOf("SanAutocompleteMeta") !== -1) {
      return Promise.resolve({ getMetric: { metadata: { humanReadableName: variables.metric.toUpperCase() } } });
    }
    return Promise.reject(new Error("unexpected"));
  });
}

describe("autocomplete data", function () {
  it("loads lists once, sorted and cleaned, and caches them in storage", async function () {
    var request = fakeRequest();
    var storage = memoryStorage();
    var data = createAutocompleteData({ request: request, storage: storage, now: function () { return 1000; } });
    var lists = await data.getLists();
    await data.getLists();
    expect(request).toHaveBeenCalledTimes(1);
    expect(lists.metrics).toEqual(["dev_activity", "price_usd"]);
    expect(lists.projects).toEqual([{ slug: "bitcoin", name: "Bitcoin", ticker: "BTC" }]);
    var cached = JSON.parse(storage.getItem(CACHE_KEY));
    expect(cached.projects).toEqual([["bitcoin", "Bitcoin", "BTC"]]);
  });

  it("uses the storage cache on the next page load without a request", async function () {
    var storage = memoryStorage();
    await createAutocompleteData({ request: fakeRequest(), storage: storage, now: function () { return 1000; } }).getLists();
    var request = fakeRequest();
    var data = createAutocompleteData({ request: request, storage: storage, now: function () { return 2000; } });
    var lists = await data.getLists();
    expect(request).not.toHaveBeenCalled();
    expect(lists.metrics).toEqual(["dev_activity", "price_usd"]);
  });

  it("answers from a stale cache and refreshes in the background", async function () {
    var storage = memoryStorage();
    await createAutocompleteData({ request: fakeRequest(), storage: storage, now: function () { return 0; } }).getLists();
    var request = fakeRequest();
    var data = createAutocompleteData({ request: request, storage: storage, now: function () { return 25 * 3600 * 1000; } });
    var lists = await data.getLists();
    expect(lists.metrics.length).toBe(2);
    expect(request).toHaveBeenCalledTimes(1);
  });

  it("retries after a failure", async function () {
    var fail = true;
    var request = vi.fn(function () {
      return fail ? Promise.reject(new Error("down")) : Promise.resolve(LISTS);
    });
    var data = createAutocompleteData({ request: request, storage: null });
    await expect(data.getLists()).rejects.toThrow("down");
    fail = false;
    expect((await data.getLists()).metrics.length).toBe(2);
  });

  it("memoizes per-metric lookups in memory only", async function () {
    var request = fakeRequest();
    var storage = memoryStorage();
    var data = createAutocompleteData({ request: request, storage: storage });
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
    var data = createAutocompleteData({ request: fakeRequest(), storage: storage });
    expect((await data.getLists()).metrics.length).toBe(2);
  });
});

describe("createRequest", function () {
  function response(status, text) {
    return Promise.resolve({ status: status, statusText: "", text: function () { return Promise.resolve(text); } });
  }

  it("sends the query with editor headers and resolves to data", async function () {
    var fetchImpl = vi.fn(function () { return response(200, '{"data":{"a":1}}'); });
    var request = createRequest({ endpoint: "/graphql", fetchImpl: fetchImpl, getHeaders: function () { return '{"Authorization":"Apikey k"}'; } });
    expect(await request("{ a }", { x: 1 })).toEqual({ a: 1 });
    var init = fetchImpl.mock.calls[0][1];
    expect(init.headers.Authorization).toBe("Apikey k");
    expect(JSON.parse(init.body)).toEqual({ query: "{ a }", variables: { x: 1 } });
    await request("query Named { a }");
    expect(JSON.parse(fetchImpl.mock.calls[1][1].body).operationName).toBe("Named");
  });

  it("rejects on errors without data and on non-JSON responses", async function () {
    var request = createRequest({ endpoint: "/graphql", fetchImpl: function () { return response(200, '{"errors":[{"message":"nope"}]}'); } });
    await expect(request("{ a }")).rejects.toThrow("nope");
    var html = createRequest({ endpoint: "/graphql", fetchImpl: function () { return response(502, "<h1>Bad Gateway</h1>"); } });
    await expect(html("{ a }")).rejects.toThrow("HTTP 502");
  });

  it("resolves partial data", async function () {
    var request = createRequest({ endpoint: "/graphql", fetchImpl: function () { return response(200, '{"data":{"a":null,"b":1},"errors":[{"message":"a failed"}]}'); } });
    expect(await request("{ a b }")).toEqual({ a: null, b: 1 });
  });
});
