/**
 * Autocomplete for metric, slug and version string values in the query
 * editor, e.g. getMetric(metric: "dev_|"), selector: {slug: "eth|"},
 * slugs: ["bitcoin", "|"], getMetric(metric: "x", version: "|").
 *
 * Registered as an extra Monaco completion provider for the "graphql"
 * language; Monaco merges it with monaco-graphql's schema suggestions.
 * Rendered as an invisible child of <GraphiQL> so it can reach the Monaco
 * instance and editors from GraphiQL state.
 *
 * Monaco does not open suggestions inside strings by default
 * (quickSuggestions.strings is off), and turning that on would ask every
 * provider in every string (from:, to:, interval:, ...), falling back to
 * word suggestions there. Instead the suggest widget is (re)opened here on
 * every edit inside one of the strings above. Re-triggering even while it is
 * open is deliberate: an edit during "Loading..." cancels the pending
 * request, and with quick suggestions off Monaco would not restart it.
 *
 * Monaco's word-based suggestions (words copied from the document) are
 * switched off. This is a page-wide Monaco setting, so it also applies to
 * the variables and headers editors. When a lookup fails or finds nothing,
 * a single explanatory row is shown instead.
 */
import { useEffect, useRef } from "react";
import { pick, tryParseJSONC, useGraphiQL, useMonaco } from "@graphiql/react";
import {
  getStringContext,
  rankMetrics,
  rankSlugs,
  rankVersions,
  metricDocumentation,
} from "./graphiql-autocomplete-utils.js";
import { createAutocompleteData } from "./graphiql-autocomplete-data.js";
import { createRequest } from "./graphiql-fetcher.js";

// Slug ranking prefers slugs the metric is available for, but that lookup
// must not hold up the list: after this long the plain ranking is shown and
// the next keystroke picks up the result.
var PREFERRED_WAIT_MS = 400;

// `promise`'s value, or null if it takes longer than `ms`.
function within(promise, ms) {
  var timer;
  var timeout = new Promise(function (resolve) { timer = setTimeout(function () { resolve(null); }, ms); });
  return Promise.race([promise, timeout]).finally(function () { clearTimeout(timer); });
}

function sortText(i) {
  return String(i).padStart(4, "0");
}

function warn(what, e) {
  console.warn("[graphiql-autocomplete] could not load " + what + ":", e && e.message ? e.message : e);
}

function createProvider(monaco, data) {
  var Kind = monaco.languages.CompletionItemKind;

  return {
    provideCompletionItems: function (model, position) {
      var ctx = getStringContext(model.getValue(), model.getOffsetAt(position));
      if (!ctx || !ctx.kind) return { suggestions: [] };

      var range = monaco.Range.fromPositions(model.getPositionAt(ctx.start), model.getPositionAt(ctx.end));
      var suffix = ctx.closed ? "" : '"';

      // filterText = what is typed, so Monaco keeps our ranking instead of
      // re-filtering; `incomplete` makes it ask again on the next keystroke.
      function item(value, i, extra) {
        return Object.assign({
          label: value,
          insertText: value + suffix,
          range: range,
          filterText: ctx.prefix,
          sortText: sortText(i),
        }, extra);
      }

      function done(suggestions) {
        return { suggestions: suggestions, incomplete: true };
      }

      // Single row explaining an empty list. Inserting it leaves the string as is.
      function notice(text) {
        var current = model.getValue().slice(ctx.start, ctx.end);
        return done([{
          label: text,
          insertText: current + suffix,
          range: range,
          filterText: ctx.prefix,
          kind: Kind.Issue,
          sortText: "9999",
        }]);
      }

      if (ctx.kind === "metric") {
        return data.getLists().then(function (lists) {
          var metrics = rankMetrics(lists.metrics, ctx.prefix);
          if (!metrics.length) return notice("No metric matches \u201c" + ctx.prefix + "\u201d");
          return done(metrics.map(function (m, i) {
            return item(m, i, { kind: Kind.Value, sanMetric: m });
          }));
        }, function (e) { warn("metrics", e); return notice("Could not load metrics: " + e.message); });
      }

      if (ctx.kind === "slug") {
        var preferred = ctx.metric
          ? within(
              data.getMetricSlugs(ctx.metric).catch(function (e) { warn("slugs for " + ctx.metric, e); return null; }),
              PREFERRED_WAIT_MS
            )
          : Promise.resolve(null);
        return Promise.all([data.getLists(), preferred]).then(function (res) {
          var lists = res[0];
          var available = res[1];
          var ranked = rankSlugs(lists.projects, ctx.prefix, available);
          if (!ranked.length) return notice("No project matches \u201c" + ctx.prefix + "\u201d");
          return done(ranked.map(function (r, i) {
            var p = r.project;
            var desc = [p.name, p.ticker].filter(Boolean).join(" · ");
            return item(p.slug, i, {
              label: { label: p.slug, description: desc },
              kind: r.preferred ? Kind.Value : Kind.Text,
              detail: available
                ? (r.preferred ? "available for " + ctx.metric : "not listed for " + ctx.metric)
                : desc,
            });
          }));
        }, function (e) { warn("projects", e); return notice("Could not load projects: " + e.message); });
      }

      if (ctx.kind === "version") {
        return data.getMetricMeta(ctx.metric).then(function (meta) {
          var all = (meta && meta.availableVersions) || [];
          var versions = rankVersions(all, ctx.prefix);
          if (!versions.length) {
            return notice(all.length
              ? "No version of " + ctx.metric + " matches \u201c" + ctx.prefix + "\u201d"
              : "No versions listed for " + ctx.metric);
          }
          return done(versions.map(function (v, i) {
            return item(v.value, i, {
              kind: Kind.EnumMember,
              detail: v.versionNum && v.versionNum !== v.value ? v.versionNum : undefined,
              documentation: v.description || undefined,
            });
          }));
        }, function (e) {
          warn("versions for " + ctx.metric, e);
          return notice("Could not load versions of " + ctx.metric + ": " + e.message);
        });
      }

      return { suggestions: [] };
    },

    // Metric details are fetched only for the highlighted suggestion.
    resolveCompletionItem: function (item) {
      if (!item.sanMetric) return item;
      return data.getMetricMeta(item.sanMetric).then(function (meta) {
        if (meta && meta.humanReadableName) item.detail = meta.humanReadableName;
        var doc = metricDocumentation(meta);
        if (doc) item.documentation = { value: doc };
        return item;
      }, function () { return item; });
    },
  };
}

export function SanAutocomplete(props) {
  var monaco = useMonaco(function (state) { return state.monaco; });
  var editors = useGraphiQL(pick("queryEditor", "headerEditor"));
  var headerEditorRef = useRef(null);
  var dataRef = useRef(null);
  headerEditorRef.current = editors.headerEditor;

  if (!dataRef.current) {
    dataRef.current = createAutocompleteData({
      storage: props.storage,
      // Sends the headers editor contents (e.g. an API key), parsed the way
      // GraphiQL parses them for queries. Headers are never stored; the
      // cached lists are whatever the first lookup returned.
      request: createRequest({
        endpoint: props.endpoint,
        getHeaders: function () {
          var editor = headerEditorRef.current;
          try {
            return editor ? tryParseJSONC(editor.getValue()) : null;
          } catch (e) {
            return null; // invalid headers: GraphiQL reports that on execution
          }
        },
      }),
    });
  }

  useEffect(function () {
    if (!monaco) return undefined;
    var disposable = monaco.languages.registerCompletionItemProvider(
      "graphql",
      createProvider(monaco, dataRef.current)
    );
    return function () { disposable.dispose(); };
  }, [monaco]);

  // Open the suggest widget while typing inside a metric/slug/version string.
  useEffect(function () {
    var editor = editors.queryEditor;
    if (!editor) return undefined;
    editor.updateOptions({ wordBasedSuggestions: "off" });
    var sub = editor.onDidChangeModelContent(function (e) {
      if (e.isFlush) return; // setValue (history, examples, tab switch)
      // One typed/deleted character, or '""' from auto-closing quotes.
      var text = e.changes.length === 1 ? e.changes[0].text : null;
      var typed = text !== null && (text.length <= 1 || text === '""') && !/\n/.test(text);
      if (!typed) return;
      var model = editor.getModel();
      var position = editor.getPosition();
      if (!model || !position) return;
      var ctx = getStringContext(model.getValue(), model.getOffsetAt(position));
      if (ctx && ctx.kind) editor.trigger("san-autocomplete", "editor.action.triggerSuggest", {});
    });
    return function () { sub.dispose(); };
  }, [editors.queryEditor]);

  return null;
}
