import { describe, it, expect } from "vitest";
import {
  getStringContext,
  rankMetrics,
  rankSlugs,
  rankVersions,
  packProjects,
  unpackProjects,
  metricDocumentation,
} from "./graphiql-autocomplete-utils.js";

// "|" marks the cursor
function ctxAt(textWithCursor) {
  var offset = textWithCursor.indexOf("|");
  var text = textWithCursor.slice(0, offset) + textWithCursor.slice(offset + 1);
  return getStringContext(text, offset);
}

describe("getStringContext", function () {
  it("detects getMetric(metric:)", function () {
    var c = ctxAt('{ getMetric(metric: "dev_|") { x } }');
    expect(c.kind).toBe("metric");
    expect(c.prefix).toBe("dev_");
    expect(c.closed).toBe(true);
  });

  it("gives the range of the whole string contents", function () {
    var text = '{ getMetric(metric: "dev_activity") { x } }';
    var offset = text.indexOf("activity");
    var c = getStringContext(text, offset);
    expect(text.slice(c.start, c.end)).toBe("dev_activity");
    expect(c.prefix).toBe("dev_");
  });

  it("detects slugs inside selector objects, with the enclosing metric", function () {
    var c = ctxAt(
      '{\n  v1: getMetric(metric: "dev_activity", version: "original:v1") {\n' +
      '    timeseriesDataJson(from: "utc_now-30d", selector: {slug: "eth|"}) \n  }\n}'
    );
    expect(c.kind).toBe("slug");
    expect(c.prefix).toBe("eth");
    expect(c.metric).toBe("dev_activity");
  });

  it("picks the metric of the right aliased getMetric", function () {
    var c = ctxAt(
      '{ v1: getMetric(metric: "price_usd") { timeseriesDataJson(selector: {slug: "bitcoin"}) }\n' +
      '  v2: getMetric(metric: "daily_active_addresses") { timeseriesDataJson(selector: {slug: "|"}) } }'
    );
    expect(c.metric).toBe("daily_active_addresses");
  });

  it("detects list elements", function () {
    var c = ctxAt('{ getMetric(metric: "price_usd") { timeseriesPerSlugDataJson(selector: {slugs: ["bitcoin", "eth|"]}) } }');
    expect(c.kind).toBe("slug");
    expect(c.metric).toBe("price_usd");
    var m = ctxAt('{ getAvailableSlugs(metrics: ["|"]) }');
    expect(m.kind).toBe("metric");
  });

  it("detects version only inside getMetric with a known metric", function () {
    expect(ctxAt('{ getMetric(metric: "dev_activity", version: "|") { x } }').kind).toBe("version");
    // metric written after the version still counts
    var c = ctxAt('{ getMetric(version: "mod|", metric: "dev_activity") { x } }');
    expect(c.kind).toBe("version");
    expect(c.metric).toBe("dev_activity");
    expect(ctxAt('{ getMetric(version: "|") { x } }').kind).toBeNull();
    expect(ctxAt('{ other(version: "|") }').kind).toBeNull();
  });

  it("handles unterminated strings while typing", function () {
    var c = ctxAt('{ getMetric(metric: "dev|\n');
    expect(c.kind).toBe("metric");
    expect(c.closed).toBe(false);
    expect(c.prefix).toBe("dev");
  });

  it("ignores other strings, comments, block strings and positions outside strings", function () {
    expect(ctxAt('{ getMetric(metric: "x") { timeseriesDataJson(from: "utc_|") } }').kind).toBeNull();
    expect(ctxAt('# metric: "dev|"\n{ a }')).toBeNull();
    expect(ctxAt('"""\nmetric: "|"\n"""\n{ a }')).toBeNull();
    expect(ctxAt('{ getMetric(metric: |"x") }')).toBeNull();
    expect(ctxAt('{ getMetric(metric: "x")| }')).toBeNull();
  });

  it("handles escaped quotes", function () {
    var c = ctxAt('{ a(q: "say \\"hi\\"") getMetric(metric: "d|") }');
    expect(c.kind).toBe("metric");
    expect(c.prefix).toBe("d");
  });

  it("does not suggest project slugs for watchlist / non-crypto asset slugs", function () {
    expect(ctxAt('{ watchlistBySlug(slug: "my-|") { id } }').kind).toBeNull();
    expect(ctxAt('{ nonCryptoAssetBySlug(slug: "|") { name } }').kind).toBeNull();
    expect(ctxAt('{ projectBySlug(slug: "|") { name } }').kind).toBe("slug");
  });

  it("supports variables-free bare field selection sets", function () {
    var c = ctxAt('{ getMetric(metric: "nvt") { metadata { availableSlugs } timeseriesDataJson(slug: "|") } }');
    expect(c.kind).toBe("slug");
    expect(c.metric).toBe("nvt");
  });
});

describe("rankMetrics", function () {
  // Sorted, as the data module provides them.
  var metrics = ["active_addresses_24h", "daily_active_addresses", "dev_activity", "dev_activity_1d", "github_activity", "price_usd"];

  it("ranks exact, prefix, segment, substring", function () {
    expect(rankMetrics(metrics, "dev_activity")).toEqual(["dev_activity", "dev_activity_1d"]);
    expect(rankMetrics(metrics, "active")).toEqual(["active_addresses_24h", "daily_active_addresses"]);
    expect(rankMetrics(metrics, "activity")).toEqual(["dev_activity", "dev_activity_1d", "github_activity"]);
  });

  it("is case-insensitive and lists everything on an empty query", function () {
    expect(rankMetrics(metrics, "PRICE")).toEqual(["price_usd"]);
    expect(rankMetrics(metrics, "").length).toBe(metrics.length);
  });
});

describe("rankSlugs", function () {
  var projects = unpackProjects([
    ["ethereum-classic", "Ethereum Classic", "ETC"],
    ["ethereum", "Ethereum", "ETH"],
    ["ethena", "Ethena", "ENA"],
    ["bitcoin", "Bitcoin", "BTC"],
    ["wrapped-bitcoin", "Wrapped Bitcoin", "WBTC"],
  ]);
  var slugs = function (r) { return r.map(function (x) { return x.project.slug; }); };

  it("matches slug, name and ticker", function () {
    expect(slugs(rankSlugs(projects, "eth"))[0]).toBe("ethereum");
    expect(slugs(rankSlugs(projects, "BTC"))).toEqual(["bitcoin", "wrapped-bitcoin"]);
    expect(slugs(rankSlugs(projects, "classic"))).toEqual(["ethereum-classic"]);
  });

  it("puts slugs available for the metric first within a tier", function () {
    var r = rankSlugs(projects, "ethe", new Set(["ethena"]));
    expect(slugs(r)).toEqual(["ethena", "ethereum", "ethereum-classic"]);
    expect(r[0].preferred).toBe(true);
    // an exact ticker match still wins
    expect(slugs(rankSlugs(projects, "eth", new Set(["ethena"])))[0]).toBe("ethereum");
  });

  it("on an empty query lists only available slugs when known", function () {
    expect(slugs(rankSlugs(projects, "", new Set(["bitcoin"])))).toEqual(["bitcoin"]);
    expect(rankSlugs(projects, "").length).toBe(5);
    expect(rankSlugs(projects, "", new Set()).length).toBe(5);
  });
});

describe("rankVersions", function () {
  var versions = [
    { versionNum: "1.0", versionName: "original:v1", description: "Old" },
    { versionNum: "2.0", versionName: "modern:v1", description: null },
    { versionNum: "2.1", versionName: null },
  ];

  it("prefers names and filters by name or number", function () {
    expect(rankVersions(versions, "").map(function (v) { return v.value; })).toEqual(["original:v1", "modern:v1", "2.1"]);
    expect(rankVersions(versions, "mod").map(function (v) { return v.value; })).toEqual(["modern:v1"]);
    expect(rankVersions(versions, "2.").map(function (v) { return v.value; })).toEqual(["modern:v1", "2.1"]);
    expect(rankVersions(null, "")).toEqual([]);
  });
});

describe("pack/unpack projects", function () {
  it("round-trips", function () {
    var p = [{ slug: "bitcoin", name: "Bitcoin", ticker: "BTC" }, { slug: "x", name: null, ticker: undefined }, null];
    expect(unpackProjects(packProjects(p))).toEqual([
      { slug: "bitcoin", name: "Bitcoin", ticker: "BTC", lower: ["bitcoin", "bitcoin", "btc"] },
      { slug: "x", name: "", ticker: "", lower: ["x", "", ""] },
    ]);
  });
});

describe("metricDocumentation", function () {
  it("summarizes metadata", function () {
    var doc = metricDocumentation({
      humanReadableName: "Development Activity",
      defaultAggregation: "SUM",
      minInterval: "1d",
      availableVersions: [{ versionNum: "1.0", versionName: "original:v1" }, { versionNum: "2.0", versionName: "modern:v1" }],
    });
    expect(doc).not.toContain("Development Activity");
    expect(doc).toContain("`SUM`");
    expect(doc).toContain("`modern:v1`");
    expect(metricDocumentation(null)).toBe("");
  });
});
