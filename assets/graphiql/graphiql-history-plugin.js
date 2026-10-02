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
  itemsToClear,
  matchesSearch,
  formatDuration,
  formatRelativeTime,
  durationStats,
  distinguishingHints,
  sortHistory,
  formatRunCount,
  SORT_MODES,
} from "./graphiql-history-utils.js";

var h = React.createElement;

var SORT_STORAGE_KEY = "san-graphiql-history-sort";

// Sort choice is a per-browser convenience; storage access can throw.
function readSortMode() {
  try {
    var v = localStorage.getItem(SORT_STORAGE_KEY);
    return SORT_MODES.indexOf(v) !== -1 ? v : "recent";
  } catch (e) {
    return "recent";
  }
}

function writeSortMode(mode) {
  try {
    localStorage.setItem(SORT_STORAGE_KEY, mode);
  } catch (e) {
    // ignore
  }
}

var STATUS_LABELS = {
  success: "Succeeded",
  partial: "Partial data with errors",
  error: "Failed",
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
  var stats = durationStats(runs);
  var maxMs = stats ? stats.max : 0;

  return h(
    "div",
    { className: "san-hist-details" },
    entry.lastError &&
      h("div", { className: "san-hist-error", title: entry.lastError }, entry.lastError),
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

function HistoryRow(props) {
  var entry = props.entry;
  var title = entry.label || entry.title;
  var neverRun = !entry.runCount && !props.running;
  // Imported entries have no real timestamp, so do not show a fake "just now".
  var meta = [neverRun ? "imported" : formatRelativeTime(entry.lastRunAt, props.now)];
  if (props.running) meta.push("running…");
  else if (entry.lastDurationMs != null) meta.push(formatDuration(entry.lastDurationMs));
  if (entry.runCount > 0) meta.push(formatRunCount(entry.runCount));

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
            h(StatusDot, { status: entry.lastStatus, running: props.running }),
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
            h(StatusDot, { status: entry.lastStatus, running: props.running }),
            h(
              "span",
              { className: "san-hist-text" },
              h("span", { className: "san-hist-title" }, title),
              props.hint &&
                h("span", { className: "san-hist-hint", title: props.hint }, props.hint),
              h("span", { className: "san-hist-meta" }, meta.join(" · "))
            )
          ),
      h(
        "div",
        { className: "san-hist-actions" + (entry.favorite ? " has-favorite" : "") },
        h(
          "button",
          {
            type: "button",
            className: "san-hist-action san-hist-fav",
            "aria-label": entry.favorite ? "Remove favorite" : "Add favorite",
            title: entry.favorite ? "Remove favorite" : "Add favorite",
            onClick: props.onToggleFavorite,
          },
          h(entry.favorite ? StarFilledIcon : StarIcon, { "aria-hidden": "true" })
        ),
        h(
          "button",
          {
            type: "button",
            className: "san-hist-action",
            "aria-label": "Rename",
            title: "Rename",
            onClick: props.onStartRename,
          },
          h(PenIcon, { "aria-hidden": "true" })
        ),
        h(
          "button",
          {
            type: "button",
            className: "san-hist-action",
            "aria-label": "Delete from history",
            title: "Delete",
            onClick: props.onDelete,
          },
          h(TrashIcon, { "aria-hidden": "true" })
        ),
        h(
          "button",
          {
            type: "button",
            className: "san-hist-action san-hist-expand",
            "aria-label": props.expanded ? "Hide run details" : "Show run details",
            "aria-expanded": String(!!props.expanded),
            title: "Run details",
            onClick: props.onToggleExpand,
          },
          h(ChevronDownIcon, { "aria-hidden": "true" })
        )
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
    var editors = useGraphiQL(function (s) {
      return { queryEditor: s.queryEditor, variableEditor: s.variableEditor };
    });
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

    // Pick up changes made in other browser tabs.
    useEffect(function () {
      function onStorage(e) {
        if (e.key === null || e.key === store.storageKey) store.reload();
      }
      window.addEventListener("storage", onStorage);
      return function () { window.removeEventListener("storage", onStorage); };
    }, []);

    function load(entry) {
      if (editors.queryEditor) editors.queryEditor.setValue(entry.query);
      if (editors.variableEditor) editors.variableEditor.setValue(entry.variables || "");
    }

    var visible = sortHistory(
      state.entries.filter(function (e) { return matchesSearch(e, search); }),
      sortMode
    );
    var favorites = visible.filter(function (e) { return e.favorite; });
    var recent = visible.filter(function (e) { return !e.favorite; });
    var clearable = itemsToClear(state.entries);
    var hints = useMemo(function () { return distinguishingHints(state.entries); }, [state.entries]);

    function renderRow(entry) {
      return h(HistoryRow, {
        key: entry.id,
        entry: entry,
        hint: hints[entry.id],
        now: now,
        running: !!state.running[entry.id],
        expanded: expandedId === entry.id,
        editing: editingId === entry.id,
        onLoad: function () { load(entry); },
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
            disabled: clearable.length === 0,
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
            [["recent", "Recent", "Most recently run first"], ["runs", "Most run", "Most executed first"]].map(function (opt) {
              return h(
                "button",
                {
                  key: opt[0],
                  type: "button",
                  className: "san-hist-sort-btn" + (sortMode === opt[0] ? " is-active" : ""),
                  "aria-pressed": String(sortMode === opt[0]),
                  title: opt[2],
                  onClick: function () { setSortMode(opt[0]); writeSortMode(opt[0]); },
                },
                opt[1]
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
