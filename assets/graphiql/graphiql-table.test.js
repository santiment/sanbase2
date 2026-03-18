import { describe, it, expect } from "vitest";
import { extractTables, sortRows, toCSV } from "./graphiql-table.js";

// ─── extractTables ───────────────────────────────────────────────

describe("extractTables", function () {
  it("returns empty array for invalid JSON", function () {
    expect(extractTables("not json")).toEqual([]);
  });

  it("returns empty array for empty response", function () {
    expect(extractTables(JSON.stringify({ data: {} }))).toEqual([]);
  });

  it("returns empty array when no data key", function () {
    expect(extractTables(JSON.stringify({ errors: [] }))).toEqual([]);
  });

  // ─── Array of objects ──────────────────────────────────────

  it("extracts a simple array of objects", function () {
    var response = {
      data: {
        allProjects: [
          { slug: "bitcoin", name: "Bitcoin", ticker: "BTC" },
          { slug: "ethereum", name: "Ethereum", ticker: "ETH" },
        ],
      },
    };
    var result = extractTables(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].label).toBe("allProjects");
    expect(result[0].columns).toEqual(["slug", "name", "ticker"]);
    expect(result[0].rows).toHaveLength(2);
    expect(result[0].rows[0].slug).toBe("bitcoin");
  });

  // ─── Timeseries data ──────────────────────────────────────

  it("extracts timeseries {datetime, value} as table", function () {
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
    var result = extractTables(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].columns).toContain("datetime");
    expect(result[0].columns).toContain("value");
    expect(result[0].rows).toHaveLength(2);
  });

  // ─── {datetime, balance} ───────────────────────────────────

  it("extracts {datetime, balance} data as table", function () {
    var response = {
      data: {
        historicalBalance: [
          { datetime: "2024-01-01T00:00:00Z", balance: 0.01 },
          { datetime: "2024-01-02T00:00:00Z", balance: 0.02 },
        ],
      },
    };
    var result = extractTables(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].columns).toContain("balance");
    expect(result[0].rows[0].balance).toBe(0.01);
  });

  // ─── Nested objects are flattened ──────────────────────────

  it("flattens nested objects with dot notation", function () {
    var response = {
      data: {
        items: [
          { name: "test", metadata: { type: "A", count: 5 } },
          { name: "test2", metadata: { type: "B", count: 10 } },
        ],
      },
    };
    var result = extractTables(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].columns).toContain("metadata.type");
    expect(result[0].columns).toContain("metadata.count");
    expect(result[0].rows[0]["metadata.type"]).toBe("A");
  });

  // ─── Arrays within objects are JSON-stringified ────────────

  it("stringifies array fields in objects", function () {
    var response = {
      data: {
        items: [
          { slug: "bitcoin", tags: ["crypto", "btc"] },
        ],
      },
    };
    var result = extractTables(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].columns).toContain("tags");
    expect(result[0].rows[0].tags).toBe('["crypto","btc"]');
  });

  // ─── JSON-encoded [[datetime, value], ...] ─────────────────

  it("extracts JSON-encoded pair arrays as table", function () {
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
    var result = extractTables(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].columns).toEqual(["datetime", "value"]);
    expect(result[0].rows).toHaveLength(2);
    expect(result[0].rows[0].datetime).toBe("2024-01-01T00:00:00Z");
    expect(result[0].rows[0].value).toBe(100);
  });

  // ─── JSON-encoded per-slug data ────────────────────────────

  it("extracts JSON-encoded per-slug map as table with slug column", function () {
    var inner = JSON.stringify({
      bitcoin: [
        ["2024-01-01T00:00:00Z", 42000],
      ],
      ethereum: [
        ["2024-01-01T00:00:00Z", 2200],
      ],
    });
    var response = {
      data: {
        getMetric: {
          timeseriesDataPerSlugJson: inner,
        },
      },
    };
    var result = extractTables(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].columns).toEqual(["slug", "datetime", "value"]);
    expect(result[0].rows).toHaveLength(2);
  });

  // ─── Multiple datasets found ───────────────────────────────

  it("extracts multiple datasets from aliased queries", function () {
    var response = {
      data: {
        projects: [
          { slug: "bitcoin", name: "Bitcoin" },
        ],
        metrics: [
          { metric: "daa", dataType: "TIMESERIES" },
        ],
      },
    };
    var result = extractTables(JSON.stringify(response));
    expect(result).toHaveLength(2);
    var labels = result.map(function (d) { return d.label; });
    expect(labels).toContain("projects");
    expect(labels).toContain("metrics");
  });

  // ─── Null values handled ───────────────────────────────────

  it("handles null values in objects", function () {
    var response = {
      data: {
        items: [
          { slug: "bitcoin", description: null, value: 100 },
          { slug: "ethereum", description: "ETH", value: 200 },
        ],
      },
    };
    var result = extractTables(JSON.stringify(response));
    expect(result).toHaveLength(1);
    expect(result[0].rows[0].description).toBeNull();
  });
});

// ─── sortRows ────────────────────────────────────────────────────

describe("sortRows", function () {
  var rows = [
    { name: "charlie", value: 30 },
    { name: "alice", value: 10 },
    { name: "bob", value: 20 },
  ];

  it("sorts by string column ascending", function () {
    var sorted = sortRows(rows, "name", "asc");
    expect(sorted.map(function (r) { return r.name; })).toEqual(["alice", "bob", "charlie"]);
  });

  it("sorts by string column descending", function () {
    var sorted = sortRows(rows, "name", "desc");
    expect(sorted.map(function (r) { return r.name; })).toEqual(["charlie", "bob", "alice"]);
  });

  it("sorts by numeric column ascending", function () {
    var sorted = sortRows(rows, "value", "asc");
    expect(sorted.map(function (r) { return r.value; })).toEqual([10, 20, 30]);
  });

  it("sorts by numeric column descending", function () {
    var sorted = sortRows(rows, "value", "desc");
    expect(sorted.map(function (r) { return r.value; })).toEqual([30, 20, 10]);
  });

  it("does not mutate original array", function () {
    var original = rows.slice();
    sortRows(rows, "value", "asc");
    expect(rows).toEqual(original);
  });

  it("sorts nulls to end", function () {
    var withNulls = [
      { v: 2 },
      { v: null },
      { v: 1 },
    ];
    var sorted = sortRows(withNulls, "v", "asc");
    expect(sorted[0].v).toBe(1);
    expect(sorted[1].v).toBe(2);
    expect(sorted[2].v).toBeNull();
  });

  it("compares numeric strings as numbers", function () {
    var numStrings = [
      { v: "100" },
      { v: "20" },
      { v: "3" },
    ];
    var sorted = sortRows(numStrings, "v", "asc");
    expect(sorted.map(function (r) { return r.v; })).toEqual(["3", "20", "100"]);
  });
});

// ─── toCSV ───────────────────────────────────────────────────────

describe("toCSV", function () {
  it("generates CSV with header row", function () {
    var columns = ["name", "value"];
    var rows = [{ name: "alice", value: 10 }];
    var csv = toCSV(columns, rows);
    var lines = csv.split("\n");
    expect(lines[0]).toBe("name,value");
    expect(lines[1]).toBe("alice,10");
  });

  it("escapes commas in values", function () {
    var columns = ["name"];
    var rows = [{ name: "hello, world" }];
    var csv = toCSV(columns, rows);
    expect(csv.split("\n")[1]).toBe('"hello, world"');
  });

  it("escapes double quotes in values", function () {
    var columns = ["name"];
    var rows = [{ name: 'say "hello"' }];
    var csv = toCSV(columns, rows);
    expect(csv.split("\n")[1]).toBe('"say ""hello"""');
  });

  it("escapes newlines in values", function () {
    var columns = ["text"];
    var rows = [{ text: "line1\nline2" }];
    var csv = toCSV(columns, rows);
    // The value contains a literal newline, so split("\n") will break it up.
    // Instead, check the full CSV after the header line.
    var headerEnd = csv.indexOf("\n");
    var dataLine = csv.slice(headerEnd + 1);
    expect(dataLine).toBe('"line1\nline2"');
  });

  it("handles null/undefined values as empty string", function () {
    var columns = ["a", "b"];
    var rows = [{ a: null, b: undefined }];
    var csv = toCSV(columns, rows);
    expect(csv.split("\n")[1]).toBe(",");
  });

  it("handles empty rows", function () {
    var columns = ["a", "b"];
    var rows = [];
    var csv = toCSV(columns, rows);
    expect(csv).toBe("a,b");
  });
});
