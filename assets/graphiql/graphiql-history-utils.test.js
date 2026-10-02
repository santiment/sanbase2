import { describe, it, expect } from "vitest";
import {
  canonicalJson,
  hashString,
  entryKey,
  isIntrospectionCall,
  classifyResult,
  summarizeQuery,
  formatDuration,
  formatRelativeTime,
  matchesSearch,
  durationStats,
  queryDetails,
  sortHistory,
} from "./graphiql-history-utils.js";

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

  it("treats {} variables like no variables", function () {
    // GraphiQL sends {} for an editor holding "{}" and undefined for an empty one.
    expect(entryKey("{ a }", {})).toBe(entryKey("{ a }", undefined));
    expect(entryKey("{ a }", null)).toBe(entryKey("{ a }"));
    expect(entryKey("{ a }", { x: 1 })).not.toBe(entryKey("{ a }"));
  });

  it("is a short hash, not a copy of the query", function () {
    var long = "{ " + "a ".repeat(5000) + "}";
    expect(entryKey(long).length).toBe(14);
    expect(hashString("x")).toBe(hashString("x"));
    expect(hashString("x")).not.toBe(hashString("y"));
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
    expect(durationStats([{ durationMs: 100 }, { durationMs: 300 }])).toEqual({ min: 100, max: 300, avg: 200 });
    expect(durationStats([])).toBeNull();
  });
});

describe("queryDetails", function () {
  function metric(alias, version, selector, from) {
    return alias + ': getMetric(metric: "dev_activity", version: "' + version + '") {' +
      ' timeseriesDataJson(from: "' + (from || "utc_now-3000d") + '", to: "utc_now", selector: ' + selector +
      ', interval: "toStartOfMonth") } ';
  }

  it("shows targets, versions and range, deduplicated across aliases", function () {
    var q = "{ " + metric("v1", "original:v1", '{organization: "ethereum"}') +
      metric("v2", "modern:v1", '{organization: "ethereum"}') + "}";
    expect(queryDetails(q)).toBe("ethereum \u00b7 original:v1, modern:v1 \u00b7 utc_now-3000d \u2192 utc_now");
  });

  it("lists every selector field and distinct ranges", function () {
    var q = "{ " + metric("a", "1.0", '{address: "0xabc", infrastructure: ETH}') +
      metric("b", "1.0", '{slugs: ["bitcoin", "ethereum"]}', "utc_now-7d") + "}";
    expect(queryDetails(q)).toBe(
      "0xabc, ETH, bitcoin, ethereum \u00b7 1.0 \u00b7 utc_now-3000d \u2192 utc_now, utc_now-7d \u2192 utc_now"
    );
  });

  it("includes slug arguments outside selectors and skips missing parts", function () {
    expect(queryDetails('{ projectBySlug(slug: "santiment") { name } }')).toBe("santiment");
    expect(queryDetails('{ getMetric(metric: "nvt") { timeseriesDataJson(from: "utc_now-1d", slug: "bitcoin") } }'))
      .toBe("bitcoin \u00b7 utc_now-1d \u2192 ");
    expect(queryDetails("{ allProjects(page: 1) { slug } }")).toBe("");
  });

  it("returns empty for unparsable queries", function () {
    expect(queryDetails("{ broken")).toBe("");
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
});
