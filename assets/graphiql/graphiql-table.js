/**
 * GraphiQL Table Data Extraction & CSV Export.
 * Detects tabular data in GraphQL responses and provides utilities
 * for flattening, sorting, and exporting as CSV.
 */

// ─── Data extraction ────────────────────────────────────────────

/**
 * Walk a parsed GraphQL response and extract all table-renderable datasets.
 * Returns an array of { label, columns, rows } objects.
 *
 * A "dataset" is any array of objects with at least one row.
 * Nested objects are flattened with dot notation (e.g. "price.usd").
 */
export function extractTables(responseJson) {
  var datasets = [];
  try {
    var parsed = typeof responseJson === "string" ? JSON.parse(responseJson) : responseJson;
    if (parsed && parsed.data) {
      walkNode(parsed.data, [], datasets);
    }
  } catch (e) {
    // not valid JSON
  }
  return datasets;
}

function walkNode(node, path, datasets) {
  if (node === null || node === undefined) return;

  // JSON string that may contain data
  if (typeof node === "string") {
    tryParseJsonString(node, path, datasets);
    return;
  }

  // Array of objects → candidate table
  if (Array.isArray(node) && node.length > 0) {
    if (isObjectArray(node)) {
      var flat = flattenRows(node);
      if (flat.columns.length > 0) {
        datasets.push({
          label: pathToLabel(path),
          columns: flat.columns,
          rows: flat.rows,
        });
        return;
      }
    }
    // Array of primitives or mixed — skip, recurse into objects
    for (var i = 0; i < node.length; i++) {
      if (node[i] && typeof node[i] === "object" && !Array.isArray(node[i])) {
        walkNode(node[i], path, datasets);
      }
    }
    return;
  }

  // Object — recurse into each key
  if (typeof node === "object") {
    // Single object with scalar values → one-row table
    var keys = Object.keys(node);
    var hasChildArrays = keys.some(function (k) {
      return Array.isArray(node[k]) || (node[k] && typeof node[k] === "object" && !Array.isArray(node[k]) && hasNestedArray(node[k]));
    });

    for (var j = 0; j < keys.length; j++) {
      walkNode(node[keys[j]], path.concat(keys[j]), datasets);
    }

    // If no child arrays were found and this object has scalar fields, add as single-row table
    if (!hasChildArrays && datasets.length === 0 && path.length > 0) {
      var scalars = extractScalars(node);
      if (scalars.columns.length >= 2) {
        datasets.push({
          label: pathToLabel(path),
          columns: scalars.columns,
          rows: [scalars.row],
        });
      }
    }
  }
}

function tryParseJsonString(str, path, datasets) {
  var parsed;
  try {
    parsed = JSON.parse(str);
  } catch (e) {
    return;
  }

  // JSON-encoded array of arrays: [[datetime, value], ...]
  if (Array.isArray(parsed) && parsed.length > 0) {
    if (isArrayOfPairs(parsed)) {
      datasets.push({
        label: pathToLabel(path),
        columns: ["datetime", "value"],
        rows: parsed.map(function (p) { return { datetime: p[0], value: p[1] }; }),
      });
      return;
    }
    if (isObjectArray(parsed)) {
      var flat = flattenRows(parsed);
      if (flat.columns.length > 0) {
        datasets.push({
          label: pathToLabel(path),
          columns: flat.columns,
          rows: flat.rows,
        });
      }
      return;
    }
  }

  // JSON-encoded object: { slug: [[datetime, value], ...], ... } (per-slug data)
  if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
    var slugKeys = Object.keys(parsed);
    var allPairs = slugKeys.length > 0 && slugKeys.every(function (k) {
      return Array.isArray(parsed[k]) && parsed[k].length > 0 && isArrayOfPairs(parsed[k]);
    });
    if (allPairs) {
      var rows = [];
      for (var i = 0; i < slugKeys.length; i++) {
        var slug = slugKeys[i];
        for (var j = 0; j < parsed[slug].length; j++) {
          rows.push({ slug: slug, datetime: parsed[slug][j][0], value: parsed[slug][j][1] });
        }
      }
      datasets.push({
        label: pathToLabel(path),
        columns: ["slug", "datetime", "value"],
        rows: rows,
      });
    }
  }
}

// ─── Helpers ─────────────────────────────────────────────────────

function isObjectArray(arr) {
  var first = arr[0];
  return first !== null && typeof first === "object" && !Array.isArray(first);
}

function isArrayOfPairs(arr) {
  var first = arr[0];
  return Array.isArray(first) && first.length === 2 && typeof first[0] === "string";
}

function hasNestedArray(obj) {
  var keys = Object.keys(obj);
  for (var i = 0; i < keys.length; i++) {
    var v = obj[keys[i]];
    if (Array.isArray(v)) return true;
    if (v && typeof v === "object") {
      if (hasNestedArray(v)) return true;
    }
  }
  return false;
}

function extractScalars(obj) {
  var columns = [];
  var row = {};
  var keys = Object.keys(obj);
  for (var i = 0; i < keys.length; i++) {
    var v = obj[keys[i]];
    if (v === null || v === undefined || typeof v !== "object") {
      columns.push(keys[i]);
      row[keys[i]] = v;
    }
  }
  return { columns: columns, row: row };
}

/**
 * Flatten an array of (possibly nested) objects into flat rows.
 * Nested keys become "parent.child" columns.
 * Arrays/objects beyond one level of nesting are JSON-stringified.
 */
function flattenRows(rows) {
  // Collect all column names from first N rows to discover all keys
  var sampleSize = Math.min(rows.length, 50);
  var columnSet = {};
  var columnOrder = [];

  for (var i = 0; i < sampleSize; i++) {
    collectColumns(rows[i], "", columnSet, columnOrder);
  }

  // Build flat rows
  var flatRows = [];
  for (var j = 0; j < rows.length; j++) {
    var flat = {};
    flattenObject(rows[j], "", flat);
    flatRows.push(flat);
  }

  return { columns: columnOrder, rows: flatRows };
}

function collectColumns(obj, prefix, seen, order) {
  if (obj === null || obj === undefined) return;
  var keys = Object.keys(obj);
  for (var i = 0; i < keys.length; i++) {
    var key = prefix ? prefix + "." + keys[i] : keys[i];
    var val = obj[keys[i]];

    if (Array.isArray(val)) {
      // Store arrays as JSON strings in a single column
      if (!seen[key]) {
        seen[key] = true;
        order.push(key);
      }
    } else if (val !== null && typeof val === "object") {
      // Recurse one level into nested objects
      collectColumns(val, key, seen, order);
    } else {
      if (!seen[key]) {
        seen[key] = true;
        order.push(key);
      }
    }
  }
}

function flattenObject(obj, prefix, result) {
  if (obj === null || obj === undefined) return;
  var keys = Object.keys(obj);
  for (var i = 0; i < keys.length; i++) {
    var key = prefix ? prefix + "." + keys[i] : keys[i];
    var val = obj[keys[i]];

    if (Array.isArray(val)) {
      result[key] = JSON.stringify(val);
    } else if (val !== null && typeof val === "object") {
      flattenObject(val, key, result);
    } else {
      result[key] = val;
    }
  }
}

function pathToLabel(path) {
  var skip = new Set(["getMetric", "data"]);
  var parts = path.filter(function (p) { return !skip.has(p); });
  return parts.length > 0 ? parts.join(" \u2192 ") : "Results";
}

// ─── Sorting ─────────────────────────────────────────────────────

/**
 * Sort rows by a column. Returns a new array (does not mutate).
 * @param {object[]} rows
 * @param {string} column
 * @param {"asc"|"desc"} direction
 */
export function sortRows(rows, column, direction) {
  var mult = direction === "desc" ? -1 : 1;
  return rows.slice().sort(function (a, b) {
    var va = a[column];
    var vb = b[column];

    // nulls/undefined sort to end
    if (va == null && vb == null) return 0;
    if (va == null) return 1;
    if (vb == null) return -1;

    // Try numeric comparison
    var na = Number(va);
    var nb = Number(vb);
    if (!isNaN(na) && !isNaN(nb)) {
      return (na - nb) * mult;
    }

    // String comparison
    var sa = String(va);
    var sb = String(vb);
    if (sa < sb) return -1 * mult;
    if (sa > sb) return 1 * mult;
    return 0;
  });
}

// ─── CSV Export ──────────────────────────────────────────────────

/**
 * Convert columns + rows to a CSV string.
 */
export function toCSV(columns, rows) {
  var lines = [];
  lines.push(columns.map(csvEscape).join(","));
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var vals = columns.map(function (col) {
      var v = row[col];
      return v == null ? "" : csvEscape(String(v));
    });
    lines.push(vals.join(","));
  }
  return lines.join("\n");
}

function csvEscape(value) {
  if (value.indexOf(",") !== -1 || value.indexOf('"') !== -1 || value.indexOf("\n") !== -1) {
    return '"' + value.replace(/"/g, '""') + '"';
  }
  return value;
}

/**
 * Trigger a file download in the browser.
 */
export function downloadFile(content, filename, mimeType) {
  var blob = new Blob([content], { type: mimeType });
  var url = URL.createObjectURL(blob);
  var a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
