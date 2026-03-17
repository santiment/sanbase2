/**
 * Table modal overlay for GraphiQL.
 * Shows query response data as a sortable table with CSV/JSON export.
 *
 * Theme is handled entirely via CSS custom properties (--san-*) defined in
 * graphiql.css, so it follows GraphiQL's light/dark toggle automatically.
 */
import React, { useEffect, useState, useCallback, useMemo } from "react";
import { useGraphiQL } from "@graphiql/react";
import { extractTables, sortRows, toCSV, downloadFile } from "./graphiql-table.js";

// ─── Constants ───────────────────────────────────────────────────

var MAX_VISIBLE_ROWS = 500;
var SORT_ASC = "asc";
var SORT_DESC = "desc";

// ─── Table Modal ─────────────────────────────────────────────────

function TableModal(props) {
  var onClose = props.onClose;

  var responseEditor = useGraphiQL(function (state) {
    return state.responseEditor;
  });

  // Track editor content so datasets recompute when the response changes,
  // not just when the editor instance is created.
  var _responseText = useState(function () {
    return responseEditor ? responseEditor.getValue() : "";
  });
  var responseText = _responseText[0];
  var setResponseText = _responseText[1];

  useEffect(function () {
    if (!responseEditor) return;
    // Sync initial value in case editor was already populated before mount
    setResponseText(responseEditor.getValue());
    var disposable = responseEditor.onDidChangeModelContent(function () {
      setResponseText(responseEditor.getValue());
    });
    return function () { disposable.dispose(); };
  }, [responseEditor]);

  var datasets = useMemo(function () {
    if (!responseText) return [];
    return extractTables(responseText);
  }, [responseText]);

  var _activeTab = useState(0);
  var activeTab = _activeTab[0];
  var setActiveTab = _activeTab[1];

  var _sortCol = useState(null);
  var sortCol = _sortCol[0];
  var setSortCol = _sortCol[1];

  var _sortDir = useState(SORT_ASC);
  var sortDir = _sortDir[0];
  var setSortDir = _sortDir[1];

  // Reset sort when switching tabs
  var handleTabChange = useCallback(function (idx) {
    setActiveTab(idx);
    setSortCol(null);
    setSortDir(SORT_ASC);
  }, []);

  var currentDataset = datasets[activeTab] || null;

  var sortedRows = useMemo(function () {
    if (!currentDataset) return [];
    if (!sortCol) return currentDataset.rows;
    return sortRows(currentDataset.rows, sortCol, sortDir);
  }, [currentDataset, sortCol, sortDir]);

  var visibleRows = sortedRows.slice(0, MAX_VISIBLE_ROWS);
  var isTruncated = sortedRows.length > MAX_VISIBLE_ROWS;

  function handleSort(col) {
    if (sortCol === col) {
      setSortDir(sortDir === SORT_ASC ? SORT_DESC : SORT_ASC);
    } else {
      setSortCol(col);
      setSortDir(SORT_ASC);
    }
  }

  function handleExportCSV() {
    if (!currentDataset) return;
    var csv = toCSV(currentDataset.columns, sortedRows);
    var name = (currentDataset.label || "data").replace(/[^a-zA-Z0-9_-]/g, "_");
    downloadFile(csv, name + ".csv", "text/csv;charset=utf-8");
  }

  function handleExportJSON() {
    if (!currentDataset) return;
    var json = JSON.stringify(sortedRows, null, 2);
    var name = (currentDataset.label || "data").replace(/[^a-zA-Z0-9_-]/g, "_");
    downloadFile(json, name + ".json", "application/json");
  }

  // Close on Escape
  useEffect(function () {
    function handleKey(e) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", handleKey);
    return function () {
      document.removeEventListener("keydown", handleKey);
    };
  }, [onClose]);

  return React.createElement(
    "div",
    {
      className: "san-table-overlay",
      onClick: function (e) { if (e.target === e.currentTarget) onClose(); },
    },
    React.createElement(
      "div",
      { className: "san-table-modal" },
      // ─── Header bar ───
      React.createElement(
        "div",
        { className: "san-table-header" },
        // Left: dataset tabs
        React.createElement(
          "div",
          { className: "san-table-tabs" },
          datasets.length === 0
            ? React.createElement("span", {
                style: { fontWeight: 600, fontSize: 14, fontFamily: "system-ui, -apple-system, sans-serif" },
              }, "Table")
            : datasets.map(function (ds, i) {
                return React.createElement(
                  "button",
                  {
                    key: i,
                    className: "san-table-tab",
                    "data-active": String(i === activeTab),
                    onClick: function () { handleTabChange(i); },
                    type: "button",
                  },
                  ds.label + " (" + ds.rows.length + ")"
                );
              })
        ),
        // Right: export buttons + close
        React.createElement(
          "div",
          { className: "san-table-actions" },
          datasets.length > 0 && React.createElement(
            "button",
            { className: "san-table-export-btn", onClick: handleExportCSV, type: "button" },
            "\u2913 CSV"
          ),
          datasets.length > 0 && React.createElement(
            "button",
            { className: "san-table-export-btn", onClick: handleExportJSON, type: "button" },
            "\u2913 JSON"
          ),
          React.createElement(
            "button",
            { className: "san-table-close-btn", onClick: onClose, type: "button", "aria-label": "Close table" },
            "\u2715"
          )
        )
      ),
      // ─── Table body ───
      datasets.length === 0
        ? React.createElement(
            "div",
            { className: "san-table-empty" },
            "No tabular data found in the response. Run a query that returns a list of objects."
          )
        : currentDataset && React.createElement(
            "div",
            { className: "san-table-scroll" },
            React.createElement(
              "table",
              null,
              // Header
              React.createElement(
                "thead",
                null,
                React.createElement(
                  "tr",
                  null,
                  // Row number column
                  React.createElement("th", { className: "san-table-rownum" }, "#"),
                  currentDataset.columns.map(function (col) {
                    var isSorted = sortCol === col;
                    var arrow = isSorted ? (sortDir === SORT_ASC ? " \u25B2" : " \u25BC") : "";
                    return React.createElement(
                      "th",
                      {
                        key: col,
                        "data-sorted": String(isSorted),
                        onClick: function () { handleSort(col); },
                      },
                      col + arrow
                    );
                  })
                )
              ),
              // Body
              React.createElement(
                "tbody",
                null,
                visibleRows.map(function (row, rowIdx) {
                  return React.createElement(
                    "tr",
                    { key: rowIdx },
                    // Row number
                    React.createElement("td", { className: "san-table-rownum" }, rowIdx + 1),
                    currentDataset.columns.map(function (col) {
                      var val = row[col];
                      var display = val == null ? "" : String(val);
                      var truncated = display.length > 120 ? display.slice(0, 120) + "\u2026" : display;
                      return React.createElement(
                        "td",
                        {
                          key: col,
                          title: display.length > 120 ? display : undefined,
                        },
                        truncated
                      );
                    })
                  );
                }),
                isTruncated && React.createElement(
                  "tr",
                  null,
                  React.createElement(
                    "td",
                    {
                      className: "san-table-truncated",
                      colSpan: currentDataset.columns.length + 1,
                    },
                    "Showing " + MAX_VISIBLE_ROWS + " of " + sortedRows.length +
                    " rows. Export CSV/JSON to get all data."
                  )
                )
              )
            )
          )
    )
  );
}

// ─── Table Button (placed in toolbar) ────────────────────────────

var TableIcon = React.createElement(
  "svg",
  {
    width: 16, height: 16, viewBox: "0 0 24 24", fill: "none",
    stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round", strokeLinejoin: "round",
  },
  React.createElement("rect", { x: 3, y: 3, width: 18, height: 18, rx: 2 }),
  React.createElement("line", { x1: 3, y1: 9, x2: 21, y2: 9 }),
  React.createElement("line", { x1: 3, y1: 15, x2: 21, y2: 15 }),
  React.createElement("line", { x1: 9, y1: 3, x2: 9, y2: 21 }),
  React.createElement("line", { x1: 15, y1: 3, x2: 15, y2: 21 })
);

export function TableButton() {
  var _open = useState(false);
  var open = _open[0];
  var setOpen = _open[1];

  var toggle = useCallback(function () {
    setOpen(function (v) { return !v; });
  }, []);

  var close = useCallback(function () {
    setOpen(false);
  }, []);

  return React.createElement(
    React.Fragment,
    null,
    React.createElement(
      "button",
      {
        className: "graphiql-toolbar-button",
        title: "Show Table",
        onClick: toggle,
        type: "button",
        style: {
          display: "inline-flex", alignItems: "center", justifyContent: "center",
        },
      },
      TableIcon
    ),
    open && React.createElement(TableModal, { onClose: close })
  );
}
