/**
 * Pure helpers for the custom History plugin.
 * Kept free of GraphiQL/React imports so they can be unit-tested in node.
 */
import { parse, stripIgnoredCharacters, visit, Kind } from "graphql";

// JSON with object keys sorted at every level, so {a,b} and {b,a} compare
// equal. No variables, null and {} are all "" (GraphiQL sends {} or
// undefined depending on whether the variables editor holds "{}" or nothing).
export function canonicalJson(value) {
  if (value === undefined || value === null) return "";
  if (typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 0) return "";
  return JSON.stringify(sortKeys(value));
}

function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === "object") {
    var out = {};
    Object.keys(value).sort().forEach(function (k) {
      out[k] = sortKeys(value[k]);
    });
    return out;
  }
  return value;
}

// Whitespace/comment-insensitive form of a query. Falls back to collapsing
// whitespace when the query does not parse (it can still be executed).
function normalizeQuery(query) {
  var q = query || "";
  try {
    return stripIgnoredCharacters(q);
  } catch (e) {
    return q.replace(/\s+/g, " ").trim();
  }
}

// 53-bit string hash (cyrb53), as 14 hex chars.
export function hashString(str) {
  var h1 = 0xdeadbeef;
  var h2 = 0x41c6ce57;
  for (var i = 0; i < str.length; i++) {
    var ch = str.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(16).padStart(14, "0");
}

// Identity of a history entry: re-running the same query with the same
// variables (ignoring formatting and key order) maps onto the same entry.
// Hashed so entries don't store a second copy of the query.
export function entryKey(query, variables, operationName) {
  return hashString([normalizeQuery(query), canonicalJson(variables), operationName || ""].join("\u0000"));
}

// "Is this fetcher call a user execution?" Introspection calls the same
// fetcher with operationName "IntrospectionQuery" and without documentAST in
// the options; executions always pass documentAST (possibly undefined).
// Fails open: if GraphiQL changes its signature, introspection would show up
// in history rather than history silently stopping.
export function isIntrospectionCall(params, opts) {
  var hasDocumentAST = !!opts && Object.prototype.hasOwnProperty.call(opts, "documentAST");
  return !!params && params.operationName === "IntrospectionQuery" && !hasDocumentAST;
}

// Classify a GraphQL response:
//   success - no errors
//   partial - errors alongside non-null data
//   error   - errors and no data
export function classifyResult(result) {
  if (!result || typeof result !== "object") {
    return { status: "error", error: "Empty response" };
  }
  var errors = Array.isArray(result.errors) ? result.errors : [];
  if (errors.length === 0) return { status: "success", error: null };

  var first = errors[0];
  var message = (first && first.message) || "Unknown error";
  if (errors.length > 1) message += " (+" + (errors.length - 1) + " more)";
  message = truncate(message, 300);

  var hasData = result.data && typeof result.data === "object" &&
    Object.keys(result.data).some(function (k) { return result.data[k] !== null; });
  return { status: hasData ? "partial" : "error", error: message };
}

export function truncate(s, n) {
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

// Short human title for a query: the operation name if set, otherwise the
// top-level fields, e.g. "v1: getMetric(dev_activity), v2: getMetric(dev_activity)".
// The first string argument is shown because it is usually the most
// distinguishing one (metric, slug, ...).
export function summarizeQuery(query, operationName) {
  if (operationName) return operationName;
  var doc;
  try {
    doc = parse(query || "");
  } catch (e) {
    return fallbackSummary(query);
  }

  var op = doc.definitions.find(function (d) { return d.kind === Kind.OPERATION_DEFINITION; });
  if (!op) return fallbackSummary(query);
  if (op.name) return op.name.value;

  var parts = op.selectionSet.selections
    .filter(function (s) { return s.kind === Kind.FIELD; })
    .map(function (field) {
      var name = field.alias ? field.alias.value + ": " + field.name.value : field.name.value;
      var strArg = (field.arguments || []).find(function (a) { return a.value.kind === Kind.STRING; });
      return strArg ? name + "(" + strArg.value.value + ")" : name;
    });

  var prefix = op.operation === "query" ? "" : op.operation + " ";
  return parts.length ? prefix + parts.join(", ") : fallbackSummary(query);
}

function fallbackSummary(query) {
  return truncate((query || "").replace(/\s+/g, " ").trim(), 80) || "(empty)";
}

export function formatDuration(ms) {
  if (typeof ms !== "number" || !isFinite(ms)) return "";
  if (ms < 1000) return Math.round(ms) + " ms";
  if (ms < 60000) return (ms / 1000).toFixed(ms < 10000 ? 2 : 1) + " s";
  var m = Math.floor(ms / 60000);
  var s = Math.round((ms % 60000) / 1000);
  return m + "m " + s + "s";
}

export function formatRelativeTime(timestamp, now) {
  var diff = Math.max(0, (now || Date.now()) - timestamp);
  var sec = Math.floor(diff / 1000);
  if (sec < 45) return "just now";
  var min = Math.floor(sec / 60);
  if (min < 60) return Math.max(1, min) + "m ago";
  var h = Math.floor(min / 60);
  if (h < 24) return h + "h ago";
  var d = Math.floor(h / 24);
  if (d < 7) return d + "d ago";
  return new Date(timestamp).toLocaleDateString();
}

// Free-text filter over label, title and query text. All whitespace-separated
// terms must match (case-insensitive).
export function matchesSearch(entry, search) {
  var terms = (search || "").toLowerCase().split(/\s+/).filter(Boolean);
  if (terms.length === 0) return true;
  var hay = [entry.label, entry.title, entry.operationName, entry.query, entry.variables]
    .filter(Boolean).join("\n").toLowerCase();
  return terms.every(function (t) { return hay.indexOf(t) !== -1; });
}

// Cancelled runs are left out: their duration is time-until-Stop.
export function durationStats(runs) {
  var ds = (runs || [])
    .filter(function (r) { return r.status !== "cancelled"; })
    .map(function (r) { return r.durationMs; })
    .filter(function (d) { return typeof d === "number"; });
  if (ds.length === 0) return null;
  var sum = ds.reduce(function (a, b) { return a + b; }, 0);
  return { min: Math.min.apply(null, ds), max: Math.max.apply(null, ds), avg: sum / ds.length };
}

// Short description of what a query asks for, shown under each history
// title: targets (values inside `selector: {...}` plus `slug`/`slugs`
// arguments), metric versions and from → to ranges, each deduplicated across
// aliases and joined with " · ". E.g. for two aliased getMetric calls:
//   "ethereum · original:v1, modern:v1 · utc_now-3000d → utc_now"
var TARGET_ARGS = { slug: true, slugs: true };

function stringArg(field, name) {
  var arg = (field.arguments || []).find(function (a) { return a.name.value === name; });
  return arg && arg.value.kind === Kind.STRING ? arg.value.value : null;
}

export function queryDetails(query) {
  var doc;
  try {
    doc = parse(query || "");
  } catch (e) {
    return "";
  }
  var targets = [];
  var versions = [];
  var ranges = [];
  function add(list, value) {
    if (value && list.indexOf(value) === -1) list.push(value);
  }

  visit(doc, {
    Field: function (field) {
      add(versions, stringArg(field, "version"));
      var from = stringArg(field, "from");
      var to = stringArg(field, "to");
      if (from || to) add(ranges, (from || "") + " \u2192 " + (to || ""));
    },
    enter: function (node, _key, parent, _path, ancestors) {
      if (node.kind !== Kind.STRING && node.kind !== Kind.ENUM) return;
      // `ancestors` excludes the direct parent (an Argument / ObjectField / list).
      var named = ancestors.concat([parent]).filter(function (a) {
        return a && (a.kind === Kind.ARGUMENT || a.kind === Kind.OBJECT_FIELD);
      });
      var inSelector = named.some(function (a) {
        return a.kind === Kind.ARGUMENT && a.name.value === "selector";
      });
      var nearest = named[named.length - 1];
      if (inSelector || (nearest && TARGET_ARGS[nearest.name.value])) add(targets, node.value);
    },
  });

  return [targets, versions, ranges]
    .filter(function (list) { return list.length; })
    .map(function (list) { return list.join(", "); })
    .join(" \u00b7 ");
}

// "recent": last run first. "runs": most executed first, ties by recency.
export function sortHistory(entries, mode) {
  var byRecent = function (a, b) { return (b.lastRunAt || 0) - (a.lastRunAt || 0); };
  var cmp = mode === "runs"
    ? function (a, b) { return (b.runCount || 0) - (a.runCount || 0) || byRecent(a, b); }
    : byRecent;
  return entries.slice().sort(cmp);
}
