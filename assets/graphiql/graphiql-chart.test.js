import { describe, it, expect } from "vitest";
import { extractTimeseries } from "./graphiql-chart.js";

describe("extractTimeseries", function () {
  it("returns empty array for invalid JSON", function () {
    expect(extractTimeseries("not json")).toEqual([]);
  });

  it("returns empty array for empty response", function () {
    expect(extractTimeseries(JSON.stringify({ data: {} }))).toEqual([]);
  });

  it("returns empty array when no data key", function () {
    expect(extractTimeseries(JSON.stringify({ errors: [] }))).toEqual([]);
  });

  // ─── {datetime, value} format ──────────────────────────────

  it("extracts {datetime, value} timeseries", function () {
    var response = {
      data: {
        getMetric: {
          timeseriesData: [
            { datetime: "2024-01-01T00:00:00Z", value: 100 },
            { datetime: "2024-01-02T00:00:00Z", value: 200 },
          ],
        },
      },
    };
    var result = extractTimeseries(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].data).toHaveLength(2);
    expect(result[0].data[0].value).toBe(100);
    expect(result[0].data[1].value).toBe(200);
  });

  // ─── {datetime, balance} format ────────────────────────────

  it("extracts {datetime, balance} timeseries (historicalBalance)", function () {
    var response = {
      data: {
        historicalBalance: [
          { datetime: "2024-01-01T00:00:00Z", balance: 0.010201 },
          { datetime: "2024-01-02T00:00:00Z", balance: 0.010201 },
          { datetime: "2024-01-03T00:00:00Z", balance: 0.010201 },
        ],
      },
    };
    var result = extractTimeseries(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].data).toHaveLength(3);
    expect(result[0].data[0].value).toBeCloseTo(0.010201);
  });

  // ─── {datetime, price} or any numeric field ────────────────

  it("extracts {datetime, price} timeseries", function () {
    var response = {
      data: {
        historyPrice: [
          { datetime: "2024-01-01T00:00:00Z", price: 42000.5 },
          { datetime: "2024-01-02T00:00:00Z", price: 43000.0 },
        ],
      },
    };
    var result = extractTimeseries(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].data[0].value).toBeCloseTo(42000.5);
  });

  // ─── Multiple numeric fields ───────────────────────────────

  it("extracts multiple numeric fields as separate series", function () {
    var response = {
      data: {
        ohlc: [
          { datetime: "2024-01-01T00:00:00Z", open: 100, high: 110, low: 90, close: 105 },
          { datetime: "2024-01-02T00:00:00Z", open: 105, high: 115, low: 95, close: 110 },
        ],
      },
    };
    var result = extractTimeseries(JSON.stringify(response));
    expect(result).toHaveLength(4);
    var labels = result.map(function (s) { return s.label; });
    expect(labels).toContain("ohlc \u2192 open");
    expect(labels).toContain("ohlc \u2192 high");
    expect(labels).toContain("ohlc \u2192 low");
    expect(labels).toContain("ohlc \u2192 close");
  });

  // ─── JSON-encoded [[datetime, value], ...] ─────────────────

  it("extracts timeseriesDataJson (JSON string of pairs)", function () {
    var inner = JSON.stringify([
      ["2024-01-01T00:00:00Z", 100],
      ["2024-01-02T00:00:00Z", 200],
    ]);
    var response = {
      data: {
        getMetric: {
          timeseriesDataJson: inner,
        },
      },
    };
    var result = extractTimeseries(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].data).toHaveLength(2);
    expect(result[0].data[0].value).toBe(100);
  });

  // ─── JSON-encoded per-slug data ────────────────────────────

  it("extracts timeseriesDataPerSlugJson (JSON string of slug map)", function () {
    var inner = JSON.stringify({
      bitcoin: [
        ["2024-01-01T00:00:00Z", 42000],
        ["2024-01-02T00:00:00Z", 43000],
      ],
      ethereum: [
        ["2024-01-01T00:00:00Z", 2200],
        ["2024-01-02T00:00:00Z", 2300],
      ],
    });
    var response = {
      data: {
        getMetric: {
          timeseriesDataPerSlugJson: inner,
        },
      },
    };
    var result = extractTimeseries(JSON.stringify(response));
    expect(result).toHaveLength(2);
    var labels = result.map(function (s) { return s.label; });
    expect(labels).toContain("bitcoin");
    expect(labels).toContain("ethereum");
  });

  // ─── Per-slug array format ─────────────────────────────────

  it("extracts per-slug array format [{datetime, data: [{slug, value}]}]", function () {
    var response = {
      data: {
        getMetric: {
          timeseriesData: [
            {
              datetime: "2024-01-01T00:00:00Z",
              data: [
                { slug: "bitcoin", value: 42000 },
                { slug: "ethereum", value: 2200 },
              ],
            },
            {
              datetime: "2024-01-02T00:00:00Z",
              data: [
                { slug: "bitcoin", value: 43000 },
                { slug: "ethereum", value: 2300 },
              ],
            },
          ],
        },
      },
    };
    var result = extractTimeseries(JSON.stringify(response));
    expect(result).toHaveLength(2);
    var btc = result.find(function (s) { return s.label === "bitcoin"; });
    expect(btc.data).toHaveLength(2);
    expect(btc.data[0].value).toBe(42000);
  });

  // ─── Skips non-numeric fields ──────────────────────────────

  it("ignores non-numeric fields alongside datetime", function () {
    var response = {
      data: {
        items: [
          { datetime: "2024-01-01T00:00:00Z", name: "foo", value: 10 },
          { datetime: "2024-01-02T00:00:00Z", name: "bar", value: 20 },
        ],
      },
    };
    var result = extractTimeseries(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].data[0].value).toBe(10);
  });

  // ─── Filters NaN values ────────────────────────────────────

  it("filters out entries with NaN values", function () {
    var response = {
      data: {
        ts: [
          { datetime: "2024-01-01T00:00:00Z", value: 100 },
          { datetime: "2024-01-02T00:00:00Z", value: null },
          { datetime: "2024-01-03T00:00:00Z", value: 300 },
        ],
      },
    };
    var result = extractTimeseries(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].data).toHaveLength(2);
  });

  // ─── JSON-encoded {datetime, balance} ──────────────────────

  it("extracts JSON-encoded {datetime, balance} array", function () {
    var inner = JSON.stringify([
      { datetime: "2024-01-01T00:00:00Z", balance: 5.5 },
      { datetime: "2024-01-02T00:00:00Z", balance: 6.0 },
    ]);
    var response = {
      data: {
        result: inner,
      },
    };
    var result = extractTimeseries(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].data[0].value).toBeCloseTo(5.5);
  });
});
