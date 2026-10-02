/**
 * Santiment History plugin for GraphiQL.
 *
 * Replaces the stock HISTORY_PLUGIN entirely (passing a different plugin
 * object keeps GraphiQL from mounting the stock HistoryStore, which recorded
 * an entry per keystroke while a query was running). Entries are recorded by
 * the fetcher wrapper in graphiql.js via graphiql-history-store.js.
 *
 * Features: search, favorites pinned on top, last-run status and duration,
 * run count, inline rename, per-entry run log, Clear with confirmation.
 */
import React, { useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import {
  Dialog,
  pick,
  useGraphiQL,
  HistoryIcon,
  StarIcon,
  StarFilledIcon,
  PenIcon,
  TrashIcon,
  ChevronDownIcon,
  MagnifyingGlassIcon,
} from "@graphiql/react";
import {
  matchesSearch,
  formatDuration,
  formatRelativeTime,
  durationStats,
  queryDetails,
  sortHistory,
} from "./graphiql-history-utils.js";
import { defaultStorage, readRaw, writeRaw } from "./graphiql-storage.js";
import { loadIntoEditors } from "./graphiql-editors.js";

var h = React.createElement;

// Sort choice is a per-browser convenience.
var SORT_STORAGE_KEY = "san-graphiql-history-sort";
var SORT_OPTIONS = [
  { id: "recent", label: "Recent", title: "Most recently run first" },
  { id: "runs", label: "Most run", title: "Most executed first" },
];

function readSortMode() {
  var v = readRaw(defaultStorage(), SORT_STORAGE_KEY);
  return SORT_OPTIONS.some(function (o) { return o.id === v; }) ? v : "recent";
}

var STATUS_LABELS = {
  success: "Succeeded",
  partial: "Partial data with errors",
  error: "Failed",
  cancelled: "Cancelled",
  running: "Running",
};

// Re-render periodically so "2m ago" stays fresh.
function useNow(intervalMs) {
  var _now = useState(Date.now());
  var setNow = _now[1];
  useEffect(function () {
    var t = setInterval(function () { setNow(Date.now()); }, intervalMs);
    return function () { clearInterval(t); };
  }, [intervalMs]);
  return _now[0];
}

function StatusDot(props) {
  var status = props.running ? "running" : props.status || "none";
  var label = STATUS_LABELS[status] || "Not run yet";
  return h("span", {
    className: "san-hist-status san-hist-status--" + status,
    role: "img",
    "aria-label": label,
    title: label,
  });
}

function RenameInput(props) {
  var ref = useRef(null);
  var done = useRef(false);

  useEffect(function () {
    if (ref.current) {
      ref.current.focus();
      ref.current.select();
    }
  }, []);

  function finish(commit) {
    if (done.current) return;
    done.current = true;
    if (commit) props.onCommit(ref.current.value);
    else props.onCancel();
  }

  return h("input", {
    ref: ref,
    type: "text",
    className: "san-hist-rename",
    defaultValue: props.initial,
    placeholder: props.placeholder,
    "aria-label": "History entry name",
    onBlur: function () { finish(true); },
    onKeyDown: function (e) {
      if (e.key === "Enter") { e.preventDefault(); finish(true); }
      if (e.key === "Escape") { e.preventDefault(); finish(false); }
    },
  });
}

function RunLog(props) {
  var entry = props.entry;
  var runs = entry.runs || [];
  var lastError = runs.length ? runs[0].error : null;
  var stats = durationStats(runs);
  // Over all runs (stats leave out cancelled ones), so no bar exceeds 100%.
  var maxMs = Math.max.apply(null, runs.map(function (r) { return r.durationMs || 0; }).concat([0]));

  return h(
    "div",
    { className: "san-hist-details" },
    lastError && h("div", { className: "san-hist-error", title: lastError }, lastError),
    stats &&
      h(
        "div",
        { className: "san-hist-stats" },
        h("span", null, "avg ", h("b", null, formatDuration(stats.avg))),
        h("span", null, "min ", h("b", null, formatDuration(stats.min))),
        h("span", null, "max ", h("b", null, formatDuration(stats.max)))
      ),
    runs.length > 1 &&
      h(
        "div",
        { className: "san-hist-bars", "aria-hidden": "true" },
        // Oldest on the left, newest on the right.
        runs.slice().reverse().map(function (run, i) {
          var pct = maxMs > 0 ? Math.max(8, Math.round((run.durationMs / maxMs) * 100)) : 8;
          return h("span", {
            key: i,
            className: "san-hist-bar san-hist-bar--" + run.status,
            style: { height: pct + "%" },
            title: formatDuration(run.durationMs) + " · " + (STATUS_LABELS[run.status] || run.status),
          });
        })
      ),
    runs.length > 0
      ? h(
          "ol",
          { className: "san-hist-runs" },
          runs.map(function (run, i) {
            return h(
              "li",
              { key: i, title: run.error || "" },
              h(StatusDot, { status: run.status }),
              h("span", { className: "san-hist-run-time" }, new Date(run.at).toLocaleString()),
              h("span", { className: "san-hist-run-dur" }, formatDuration(run.durationMs))
            );
          })
        )
      : h("div", { className: "san-hist-empty-runs" }, "No recorded runs (imported from the previous history)."),
    entry.variables &&
      h("pre", { className: "san-hist-vars", title: "Variables" }, entry.variables)
  );
}

function ActionButton(props) {
  return h(
    "button",
    Object.assign({
      type: "button",
      className: "san-hist-action" + (props.className ? " " + props.className : ""),
      "aria-label": props.label,
      title: props.title || props.label,
      onClick: props.onClick,
    }, props.extra),
    h(props.icon, { "aria-hidden": "true" })
  );
}

function HistoryRow(props) {
  var entry = props.entry;
  var last = entry.runs && entry.runs[0];
  var title = entry.label || entry.title;
  var neverRun = !entry.runCount && !props.running;
  // Imported entries have no real timestamp, so do not show a fake "just now".
  var meta = [neverRun ? "imported" : formatRelativeTime(entry.lastRunAt, props.now)];
  if (props.running) meta.push("running\u2026");
  else if (last && last.status === "cancelled") meta.push("cancelled");
  else if (last) meta.push(formatDuration(last.durationMs));
  if (entry.runCount > 0) meta.push(entry.runCount === 1 ? "1 run" : entry.runCount + " runs");

  var dot = h(StatusDot, { status: last && last.status, running: props.running });
  var favLabel = entry.favorite ? "Remove favorite" : "Add favorite";

  return h(
    "li",
    { className: "san-hist-item" + (props.expanded ? " is-expanded" : "") },
    h(
      "div",
      { className: "san-hist-row" },
      props.editing
        ? h(
            "div",
            { className: "san-hist-main" },
            dot,
            h(RenameInput, {
              initial: entry.label || "",
              placeholder: entry.title,
              onCommit: props.onRename,
              onCancel: props.onCancelRename,
            })
          )
        : h(
            "button",
            {
              type: "button",
              className: "san-hist-main",
              title: entry.query,
              "aria-label": "Load query: " + title,
              onClick: props.onLoad,
            },
            dot,
            h(
              "span",
              { className: "san-hist-text" },
              h("span", { className: "san-hist-title" }, title),
              props.details &&
                h("span", { className: "san-hist-subtitle", title: props.details }, props.details),
              h("span", { className: "san-hist-meta" }, meta.join(" \u00b7 "))
            )
          ),
      h(
        "div",
        { className: "san-hist-actions" + (entry.favorite ? " has-favorite" : "") },
        h(ActionButton, {
          className: "san-hist-fav",
          label: favLabel,
          icon: entry.favorite ? StarFilledIcon : StarIcon,
          onClick: props.onToggleFavorite,
        }),
        h(ActionButton, { label: "Rename", icon: PenIcon, onClick: props.onStartRename }),
        h(ActionButton, { label: "Delete from history", title: "Delete", icon: TrashIcon, onClick: props.onDelete }),
        h(ActionButton, {
          className: "san-hist-expand",
          label: props.expanded ? "Hide run details" : "Show run details",
          title: "Run details",
          icon: ChevronDownIcon,
          onClick: props.onToggleExpand,
          extra: { "aria-expanded": String(!!props.expanded) },
        })
      )
    ),
    props.expanded && h(RunLog, { entry: entry })
  );
}

function ClearDialog(props) {
  return h(
    Dialog,
    { open: props.open, onOpenChange: props.onOpenChange },
    h(
      "div",
      { className: "graphiql-dialog-header" },
      h(Dialog.Title, { className: "graphiql-dialog-title" }, "Clear history?")
    ),
    h(
      Dialog.Description,
      { className: "san-confirm-body" },
      "This removes all non-favorite queries from your history. " +
        "Favorites are kept. This cannot be undone."
    ),
    h(
      "div",
      { className: "san-confirm-footer" },
      h(
        "button",
        {
          type: "button",
          className: "san-confirm-cancel-btn",
          onClick: function () { props.onOpenChange(false); },
        },
        "Cancel"
      ),
      h(
        "button",
        { type: "button", className: "san-confirm-danger-btn", onClick: props.onConfirm },
        "Clear history"
      )
    )
  );
}

function makeHistoryContent(store) {
  return function SanHistory() {
    var state = useSyncExternalStore(store.subscribe, store.getSnapshot);
    var editors = useGraphiQL(pick("queryEditor", "variableEditor"));
    var now = useNow(30000);

    var _search = useState("");
    var search = _search[0];
    var setSearch = _search[1];

    var _open = useState(false);
    var open = _open[0];
    var setOpen = _open[1];

    var _sort = useState(readSortMode);
    var sortMode = _sort[0];
    var setSortMode = _sort[1];

    var _expanded = useState(null);
    var expandedId = _expanded[0];
    var setExpandedId = _expanded[1];

    var _editing = useState(null);
    var editingId = _editing[0];
    var setEditingId = _editing[1];

    var visible = sortHistory(
      state.entries.filter(function (e) { return matchesSearch(e, search); }),
      sortMode
    );
    var favorites = visible.filter(function (e) { return e.favorite; });
    var recent = visible.filter(function (e) { return !e.favorite; });
    var clearable = state.entries.some(function (e) { return !e.favorite; });
    // Parsed once per distinct query; entries are rebuilt on every store
    // change, so cache by query text and keep only live queries.
    var detailsCache = useRef(new Map());
    var details = useMemo(function () {
      var prev = detailsCache.current;
      var next = new Map();
      state.entries.forEach(function (e) {
        next.set(e.query, prev.has(e.query) ? prev.get(e.query) : queryDetails(e.query));
      });
      detailsCache.current = next;
      return next;
    }, [state.entries]);

    function renderRow(entry) {
      return h(HistoryRow, {
        key: entry.id,
        entry: entry,
        details: details.get(entry.query),
        now: now,
        running: !!state.running[entry.id],
        expanded: expandedId === entry.id,
        editing: editingId === entry.id,
        onLoad: function () { loadIntoEditors(editors, entry.query, entry.variables); },
        onToggleFavorite: function () { store.toggleFavorite(entry.id); },
        onStartRename: function () { setEditingId(entry.id); },
        onRename: function (label) { store.rename(entry.id, label); setEditingId(null); },
        onCancelRename: function () { setEditingId(null); },
        onDelete: function () { store.remove(entry.id); },
        onToggleExpand: function () {
          setExpandedId(expandedId === entry.id ? null : entry.id);
        },
      });
    }

    function section(id, label, list) {
      if (list.length === 0) return null;
      return h(
        "section",
        { className: "san-hist-section", "aria-labelledby": id },
        h("h3", { id: id, className: "san-hist-section-title" }, label, h("span", null, list.length)),
        h("ul", { className: "san-hist-list" }, list.map(renderRow))
      );
    }

    var body;
    if (state.entries.length === 0) {
      body = h(
        "div",
        { className: "san-hist-empty" },
        "Run a query and it will show up here, with its status and duration."
      );
    } else if (visible.length === 0) {
      body = h("div", { className: "san-hist-empty" }, "No history matches “" + search + "”.");
    } else {
      body = h(
        React.Fragment,
        null,
        section("san-hist-favorites", "Favorites", favorites),
        section("san-hist-recent", sortMode === "runs" ? "Most run" : "Recent", recent)
      );
    }

    return h(
      "div",
      { className: "san-history" },
      h(
        "div",
        { className: "san-history-header" },
        "History",
        h(
          "button",
          {
            type: "button",
            className: "san-history-clear-btn",
            disabled: !clearable,
            onClick: function () { setOpen(true); },
          },
          "Clear"
        )
      ),
      state.entries.length > 0 &&
        h(
          "div",
          { className: "san-hist-toolbar" },
          h(
            "label",
            { className: "san-hist-search" },
            h(MagnifyingGlassIcon, { "aria-hidden": "true" }),
            h("input", {
              type: "search",
              value: search,
              placeholder: "Search history",
              "aria-label": "Search history",
              onChange: function (e) { setSearch(e.target.value); },
            })
          ),
          h(
            "div",
            { className: "san-hist-sort", role: "group", "aria-label": "Sort history" },
            SORT_OPTIONS.map(function (opt) {
              return h(
                "button",
                {
                  key: opt.id,
                  type: "button",
                  className: "san-hist-sort-btn" + (sortMode === opt.id ? " is-active" : ""),
                  "aria-pressed": String(sortMode === opt.id),
                  title: opt.title,
                  onClick: function () {
                    setSortMode(opt.id);
                    writeRaw(defaultStorage(), SORT_STORAGE_KEY, opt.id);
                  },
                },
                opt.label
              );
            })
          )
        ),
      body,
      h(ClearDialog, {
        open: open,
        onOpenChange: setOpen,
        onConfirm: function () { store.clear(); setOpen(false); },
      })
    );
  };
}

export function historyPlugin(store) {
  return {
    title: "History",
    icon: HistoryIcon,
    content: makeHistoryContent(store),
  };
}
