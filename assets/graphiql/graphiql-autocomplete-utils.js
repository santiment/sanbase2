/**
 * Pure helpers for metric/slug/version autocomplete (graphiql-autocomplete.js).
 * No Monaco/GraphiQL imports, so they can be unit-tested in node.
 *
 * Context detection uses a small tolerant tokenizer instead of the GraphQL
 * parser: while typing, the query is usually not valid GraphQL, but we still
 * need to know which argument the cursor is in and which metric the
 * enclosing getMetric(...) asks for.
 */

// Argument / input field names that get suggestions, by kind. Matching by
// name (not by schema field) covers getMetric(metric:), selector: {slug:},
// slugs: [...] and the rest of the API without a hand-kept field list.
var KEY_KINDS = {
  metric: "metric",
  metrics: "metric",
  slug: "slug",
  slugs: "slug",
  version: "version",
};

var MAX_RESULTS = 100;

function isNameStart(c) {
  return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c === "_";
}

function isNameChar(c) {
  return isNameStart(c) || (c >= "0" && c <= "9");
}

/**
 * If `offset` is inside a string value, describe it:
 *   {
 *     kind: "metric" | "slug" | "version" | null,
 *     key, inList,
 *     prefix,          // string contents before the cursor
 *     start, end,      // offsets of the string contents (end excludes the closing quote)
 *     closed,          // whether the string has a closing quote on this line
 *     metric,          // metric of the enclosing getMetric(...), if any
 *   }
 * Returns null when the cursor is not inside a (single-line) string.
 */
export function getStringContext(text, offset) {
  var frames = []; // { type: "(" | "{" | "[", field, key, args, selectionOf }
  var tokens = []; // significant tokens: { t: "name" | "punct" | "string" | "other", v }
  var lastCall = null; // { field, args } of the most recently closed "(...)"
  var snapshot = null;
  var i = 0;
  var n = text.length;

  function prev(k) { return tokens[tokens.length - k]; }
  function top() { return frames[frames.length - 1]; }

  // Key that a value at this position belongs to: `key: <value>` or a list
  // element `key: [..., <value>]`.
  function currentKey() {
    var p = prev(1);
    if (p && p.t === "punct" && p.v === ":") {
      var name = prev(2);
      return name && name.t === "name" ? { key: name.v, inList: false } : null;
    }
    var f = top();
    if (f && f.type === "[") return { key: f.key, inList: true };
    return null;
  }

  while (i < n) {
    var c = text[i];

    if (c === " " || c === "\t" || c === "\n" || c === "\r" || c === "," || c === "﻿") {
      i++;
      continue;
    }

    if (c === "#") {
      while (i < n && text[i] !== "\n") i++;
      continue;
    }

    if (c === '"') {
      if (text.substr(i, 3) === '"""') {
        // Block string (descriptions): skip, never completed.
        var close = text.indexOf('"""', i + 3);
        i = close === -1 ? n : close + 3;
        tokens.push({ t: "string", v: null });
        continue;
      }
      var start = i + 1;
      var j = start;
      while (j < n && text[j] !== '"' && text[j] !== "\n") {
        j += text[j] === "\\" ? 2 : 1;
      }
      var closed = j < n && text[j] === '"';
      var keyInfo = currentKey();
      var value = text.slice(start, Math.min(j, n));

      if (!snapshot && offset >= start && offset <= j) {
        snapshot = {
          key: keyInfo ? keyInfo.key : null,
          inList: keyInfo ? keyInfo.inList : false,
          prefix: text.slice(start, offset),
          start: start,
          end: Math.min(j, n),
          closed: closed,
          frames: frames.slice(),
        };
      }

      var f = top();
      if (keyInfo && !keyInfo.inList && f && f.args) f.args[keyInfo.key] = value;
      tokens.push({ t: "string", v: value });
      i = closed ? j + 1 : j;
      continue;
    }

    if (isNameStart(c)) {
      var s = i;
      while (i < n && isNameChar(text[i])) i++;
      tokens.push({ t: "name", v: text.slice(s, i) });
      continue;
    }

    if (c === "(" || c === "{" || c === "[") {
      var p1 = prev(1);
      var frame = { type: c, field: null, key: null, args: null, selectionOf: null };
      if (c === "(") {
        frame.field = p1 && p1.t === "name" ? p1.v : null;
        frame.args = {};
      } else {
        var k = currentKey();
        if (k) {
          // Object or list value: `selector: {` / `slugs: [`
          frame.key = k.key;
          if (c === "{") frame.args = {};
        } else if (c === "{") {
          // Selection set: belongs to the call just closed, or to a bare field.
          if (p1 && p1.t === "punct" && p1.v === ")" && lastCall) frame.selectionOf = lastCall;
          else if (p1 && p1.t === "name") frame.selectionOf = { field: p1.v, args: {} };
        }
      }
      frames.push(frame);
      tokens.push({ t: "punct", v: c });
      i++;
      continue;
    }

    if (c === ")" || c === "}" || c === "]") {
      var closing = frames.pop();
      if (c === ")" && closing && closing.type === "(") {
        lastCall = { field: closing.field, args: closing.args };
      }
      tokens.push({ t: "punct", v: c });
      i++;
      continue;
    }

    if (c === ":" || c === "=" || c === "!" || c === "$" || c === "@" || c === "|" || c === "&") {
      tokens.push({ t: "punct", v: c });
      i++;
      continue;
    }

    // Numbers, spreads, anything else: one opaque token.
    var s2 = i;
    while (i < n && !/[\s,"#(){}[\]:=!$@|&]/.test(text[i])) i++;
    if (i === s2) i++;
    tokens.push({ t: "other", v: text.slice(s2, i) });
  }

  if (!snapshot) return null;

  // Innermost enclosing getMetric(...): its own args when the cursor is in
  // them, or the args of the call a selection set belongs to. Frames are
  // shared objects, so args written after the cursor are visible here too
  // (e.g. version: "|" before metric: "x").
  var metric = null;
  for (var fi = snapshot.frames.length - 1; fi >= 0 && metric === null; fi--) {
    var fr = snapshot.frames[fi];
    if (fr.type === "(" && fr.field === "getMetric") metric = fr.args.metric || null;
    else if (fr.selectionOf && fr.selectionOf.field === "getMetric") metric = fr.selectionOf.args.metric || null;
  }

  var kind = snapshot.key ? KEY_KINDS[snapshot.key] || null : null;
  // Versions only make sense directly in getMetric(...) with a known metric.
  if (kind === "version") {
    var own = snapshot.frames[snapshot.frames.length - 1];
    if (!own || own.type !== "(" || own.field !== "getMetric" || !metric) kind = null;
  }

  return {
    kind: kind,
    key: snapshot.key,
    inList: snapshot.inList,
    prefix: snapshot.prefix,
    start: snapshot.start,
    end: snapshot.end,
    closed: snapshot.closed,
    metric: metric,
  };
}

function byLengthThenAlpha(a, b) {
  return a.length - b.length || (a < b ? -1 : a > b ? 1 : 0);
}

// Metric names: exact, prefix, start of an "_"-separated segment, substring.
export function rankMetrics(metrics, query, limit) {
  var q = (query || "").toLowerCase();
  var max = limit || MAX_RESULTS;
  if (!q) return metrics.slice().sort().slice(0, max);

  var scored = [];
  metrics.forEach(function (m) {
    var lower = m.toLowerCase();
    var tier;
    if (lower === q) tier = 0;
    else if (lower.indexOf(q) === 0) tier = 1;
    else if (lower.indexOf("_" + q) !== -1) tier = 2;
    else if (lower.indexOf(q) !== -1) tier = 3;
    else return;
    scored.push({ m: m, tier: tier });
  });
  scored.sort(function (a, b) { return a.tier - b.tier || byLengthThenAlpha(a.m, b.m); });
  return scored.slice(0, max).map(function (x) { return x.m; });
}

/**
 * projects: [{ slug, name, ticker }]. Matches slug, name and ticker, so
 * "ETH" finds ethereum. `preferred` (a Set of slugs, e.g. the slugs the
 * enclosing metric is available for) ranks first within each tier, and on
 * an empty query only preferred slugs are listed when there are any.
 * Returns [{ project, preferred }].
 */
export function rankSlugs(projects, query, preferred, limit) {
  var q = (query || "").toLowerCase();
  var max = limit || MAX_RESULTS;
  var pref = preferred || null;
  var scored = [];

  projects.forEach(function (p) {
    var slug = p.slug.toLowerCase();
    var name = (p.name || "").toLowerCase();
    var ticker = (p.ticker || "").toLowerCase();
    var isPref = !!pref && pref.has(p.slug);
    var tier;
    if (!q) tier = 0;
    else if (slug === q) tier = 0;
    else if (ticker === q) tier = 1;
    else if (slug.indexOf(q) === 0) tier = 2;
    else if (name.indexOf(q) === 0) tier = 3;
    else if (ticker.indexOf(q) === 0) tier = 4;
    else if (slug.indexOf("-" + q) !== -1 || name.indexOf(" " + q) !== -1) tier = 5;
    else if (slug.indexOf(q) !== -1 || name.indexOf(q) !== -1 || ticker.indexOf(q) !== -1) tier = 6;
    else return;
    scored.push({ project: p, preferred: isPref, tier: tier });
  });

  if (!q && pref && pref.size > 0) {
    scored = scored.filter(function (x) { return x.preferred; });
  }

  scored.sort(function (a, b) {
    return a.tier - b.tier ||
      (a.preferred === b.preferred ? 0 : a.preferred ? -1 : 1) ||
      byLengthThenAlpha(a.project.slug, b.project.slug);
  });
  return scored.slice(0, max).map(function (x) { return { project: x.project, preferred: x.preferred }; });
}

// versions: [{ versionNum, versionName, description }] from metadata.
// Suggests the name when there is one (both are accepted by getMetric).
export function rankVersions(versions, query) {
  var q = (query || "").toLowerCase();
  var out = [];
  (versions || []).forEach(function (v) {
    var name = v.versionName || v.versionNum;
    if (!name) return;
    var hay = (name + " " + (v.versionNum || "")).toLowerCase();
    if (q && hay.indexOf(q) === -1) return;
    out.push({ value: name, versionNum: v.versionNum, description: v.description || null });
  });
  return out;
}

// Compact cache format: projects as [slug, name, ticker] tuples.
export function packProjects(projects) {
  return projects
    .filter(function (p) { return p && p.slug; })
    .map(function (p) { return [p.slug, p.name || "", p.ticker || ""]; });
}

export function unpackProjects(rows) {
  return (rows || []).map(function (r) { return { slug: r[0], name: r[1], ticker: r[2] }; });
}

// Markdown shown in the suggestion details panel for a metric. The human
// readable name is set as the item detail (panel header), so not repeated.
export function metricDocumentation(meta) {
  if (!meta) return "";
  var lines = [];
  var facts = [];
  if (meta.defaultAggregation) facts.push("aggregation `" + meta.defaultAggregation + "`");
  if (meta.minInterval) facts.push("min interval `" + meta.minInterval + "`");
  if (facts.length) lines.push(facts.join(" · "));
  var versions = (meta.availableVersions || [])
    .map(function (v) { return v.versionName || v.versionNum; })
    .filter(Boolean);
  if (versions.length > 1) lines.push("versions: " + versions.map(function (v) { return "`" + v + "`"; }).join(", "));
  return lines.join("\n\n");
}
