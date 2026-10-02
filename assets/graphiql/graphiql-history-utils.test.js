import { describe, it, expect } from "vitest";
import {
  itemsToClear,
  canonicalJson,
  entryKey,
  isIntrospectionCall,
  classifyResult,
  summarizeQuery,
  formatDuration,
  formatRelativeTime,
  matchesSearch,
  durationStats,
  distinguishingHints,
  sortHistory,
  formatRunCount,
} from "./graphiql-history-utils.js";

describe("itemsToClear", function () {
  it("keeps favorites", function () {
    var items = [
      { query: "{ a }", favorite: true },
      { query: "{ b }" },
      { query: "{ c }", favorite: false },
    ];
    var result = itemsToClear(items);
    expect(result.length).toBe(2);
    result.forEach(function (item) {
      expect(item.favorite).toBeFalsy();
    });
  });

  it("returns all items when none are favorites", function () {
    var items = [{ query: "{ a }" }, { query: "{ b }" }];
    expect(itemsToClear(items)).toEqual(items);
  });

  it("returns empty for empty input", function () {
    expect(itemsToClear([])).toEqual([]);
  });

  it("returns empty when everything is a favorite", function () {
    var items = [{ query: "{ a }", favorite: true }];
    expect(itemsToClear(items)).toEqual([]);
  });
});

describe("entryKey", function () {
  it("ignores formatting and comments", function () {
    expect(entryKey("{ a { b } }")).toBe(entryKey("{\n  a {\n    b # note\n  }\n}"));
  });

  it("ignores variable key order", function () {
    expect(canonicalJson({ b: 1, a: { d: 1, c: 2 } })).toBe(canonicalJson({ a: { c: 2, d: 1 }, b: 1 }));
    expect(entryKey("{ a }", { x: 1, y: 2 })).toBe(entryKey("{ a }", { y: 2, x: 1 }));
  });

  it("distinguishes argument values", function () {
    expect(entryKey('{ a(s: "eth") }')).not.toBe(entryKey('{ a(s: "ethereum") }'));
  });

  it("handles unparsable queries", function () {
    expect(entryKey("{ a ")).toBe(entryKey("{   a   "));
  });
});

describe("isIntrospectionCall", function () {
  it("detects GraphiQL schema introspection", function () {
    expect(isIntrospectionCall({ query: "query IntrospectionQuery { __schema { types { name } } }", operationName: "IntrospectionQuery" }, {})).toBe(true);
    expect(isIntrospectionCall({ operationName: "IntrospectionQuery" }, { headers: {} })).toBe(true);
  });

  it("treats executions (which pass documentAST) as user runs", function () {
    expect(isIntrospectionCall({ query: "{ a }" }, { headers: {}, documentAST: undefined })).toBe(false);
    expect(isIntrospectionCall({ query: "{ a }", operationName: "IntrospectionQuery" }, { documentAST: {} })).toBe(false);
    expect(isIntrospectionCall({ query: "{ a }" }, {})).toBe(false);
  });
});

describe("classifyResult", function () {
  it("success without errors", function () {
    expect(classifyResult({ data: { a: 1 } })).toEqual({ status: "success", error: null });
  });

  it("partial when data and errors", function () {
    var r = classifyResult({ data: { a: 1, b: null }, errors: [{ message: "b failed" }] });
    expect(r.status).toBe("partial");
    expect(r.error).toBe("b failed");
  });

  it("error when only nulls and errors", function () {
    var r = classifyResult({ data: { a: null }, errors: [{ message: "x" }, { message: "y" }] });
    expect(r).toEqual({ status: "error", error: "x (+1 more)" });
  });

  it("error for network failures and empty responses", function () {
    expect(classifyResult({ errors: [{ message: "Failed to fetch" }] }).status).toBe("error");
    expect(classifyResult(null).status).toBe("error");
  });

  it("truncates long messages", function () {
    var r = classifyResult({ errors: [{ message: "x".repeat(1000) }] });
    expect(r.error.length).toBe(300);
  });
});

describe("summarizeQuery", function () {
  it("lists aliased root fields with their first string argument", function () {
    var q = '{ v1: getMetric(metric: "dev_activity", version: "original:v1") { x } v2: getMetric(metric: "dev_activity") { x } }';
    expect(summarizeQuery(q)).toBe("v1: getMetric(dev_activity), v2: getMetric(dev_activity)");
  });

  it("prefers the operation name", function () {
    expect(summarizeQuery("query Foo { a }")).toBe("Foo");
    expect(summarizeQuery("{ a }", "Bar")).toBe("Bar");
  });

  it("prefixes mutations", function () {
    expect(summarizeQuery("mutation { logout { success } }")).toBe("mutation logout");
  });

  it("falls back to the raw text", function () {
    expect(summarizeQuery("{ broken")).toBe("{ broken");
  });
});

describe("formatting", function () {
  it("formats durations", function () {
    expect(formatDuration(42.4)).toBe("42 ms");
    expect(formatDuration(1234)).toBe("1.23 s");
    expect(formatDuration(12345)).toBe("12.3 s");
    expect(formatDuration(72000)).toBe("1m 12s");
    expect(formatDuration(null)).toBe("");
  });

  it("formats relative time", function () {
    var now = 10 * 86400000;
    expect(formatRelativeTime(now - 5000, now)).toBe("just now");
    expect(formatRelativeTime(now - 5 * 60000, now)).toBe("5m ago");
    expect(formatRelativeTime(now - 3 * 3600000, now)).toBe("3h ago");
    expect(formatRelativeTime(now - 2 * 86400000, now)).toBe("2d ago");
  });
});

describe("matchesSearch", function () {
  var entry = { title: "getMetric(dev_activity)", label: "Dev", query: '{ getMetric(metric: "dev_activity") }' };

  it("matches all terms case-insensitively", function () {
    expect(matchesSearch(entry, "")).toBe(true);
    expect(matchesSearch(entry, "DEV getmetric")).toBe(true);
    expect(matchesSearch(entry, "dev price")).toBe(false);
  });
});

describe("durationStats", function () {
  it("computes min/max/avg", function () {
    expect(durationStats([{ durationMs: 100 }, { durationMs: 300 }])).toEqual({ min: 100, max: 300, avg: 200, count: 2 });
    expect(durationStats([])).toBeNull();
  });
});

describe("distinguishingHints", function () {
  function e(id, query, title) {
    return { id: id, query: query, title: title || "getMetric(dev_activity)" };
  }

  it("shows only the values that differ within a same-title group", function () {
    var q = function (org) {
      return '{ getMetric(metric: "dev_activity") { timeseriesDataJson(from: "utc_now-30d", selector: {organization: "' + org + '"}) } }';
    };
    var hints = distinguishingHints([e(1, q("ethereum")), e(2, q("bitcoin")), e(3, "{ other }", "other")]);
    expect(hints).toEqual({ 1: "ethereum", 2: "bitcoin" });
  });

  it("gives no hint for unique titles or identical literals", function () {
    expect(distinguishingHints([e(1, '{ a(x: "1") }', "a")])).toEqual({});
    expect(distinguishingHints([e(1, '{ a(x: "1") }'), e(2, '{ a(x: "1") { b } }')])).toEqual({});
  });

  it("groups by label when set", function () {
    var hints = distinguishingHints([
      { id: 1, query: '{ a(x: "1") }', title: "a", label: "Mine" },
      { id: 2, query: '{ a(x: "2") }', title: "a" },
    ]);
    expect(hints).toEqual({});
  });
});

describe("sortHistory", function () {
  var entries = [
    { id: "a", lastRunAt: 3, runCount: 1 },
    { id: "b", lastRunAt: 1, runCount: 5 },
    { id: "c", lastRunAt: 2, runCount: 5 },
    { id: "d", lastRunAt: 4 },
  ];
  var ids = function (list) { return list.map(function (e) { return e.id; }); };

  it("sorts by recency", function () {
    expect(ids(sortHistory(entries, "recent"))).toEqual(["d", "a", "c", "b"]);
  });

  it("sorts by run count, ties by recency", function () {
    expect(ids(sortHistory(entries, "runs"))).toEqual(["c", "b", "a", "d"]);
  });

  it("does not mutate the input", function () {
    sortHistory(entries, "runs");
    expect(ids(entries)).toEqual(["a", "b", "c", "d"]);
  });

  it("formats run counts", function () {
    expect(formatRunCount(1)).toBe("1 run");
    expect(formatRunCount(7)).toBe("7 runs");
  });
});
