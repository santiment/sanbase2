/**
 * Chart modal overlay for GraphiQL.
 * Shows an interactive timeseries chart over the response data.
 *
 * Theme is handled via CSS custom properties (--san-*) defined in graphiql.css,
 * so it follows GraphiQL's light/dark toggle automatically.
 */
import React, { useEffect, useRef, useState, useCallback } from "react";
import { useGraphiQL } from "@graphiql/react";
import { extractTimeseries, renderChart } from "./graphiql-chart.js";

// ─── Chart Modal ────────────────────────────────────────────────

function ChartModal({ onClose }) {
  const containerRef = useRef(null);
  const cleanupRef = useRef(null);

  const responseEditor = useGraphiQL(function (state) {
    return state.responseEditor;
  });

  // Track editor content so series recompute when the response changes,
  // not just when the editor instance is created.
  const [responseText, setResponseText] = useState(function () {
    return responseEditor ? responseEditor.getValue() : "";
  });

  useEffect(function () {
    if (!responseEditor) return;
    setResponseText(responseEditor.getValue());
    const disposable = responseEditor.onDidChangeModelContent(function () {
      setResponseText(responseEditor.getValue());
    });
    return function () { disposable.dispose(); };
  }, [responseEditor]);

  const series = React.useMemo(
    function () {
      if (!responseText) return [];
      return extractTimeseries(responseText);
    },
    [responseText]
  );

  useEffect(
    function () {
      if (!containerRef.current || series.length === 0) return;

      function doRender() {
        if (cleanupRef.current) cleanupRef.current();
        var style = getComputedStyle(containerRef.current);
        var chartColors = {
          bg: style.getPropertyValue("--san-bg-panel").trim() || "#ffffff",
          text: style.getPropertyValue("--san-text").trim() || "#333333",
          grid: style.getPropertyValue("--san-chart-grid").trim() || "rgba(0,0,0,0.06)",
        };
        cleanupRef.current = renderChart(containerRef.current, series, chartColors);
      }

      doRender();

      // Re-render chart when theme toggles (class change on .graphiql-container)
      var themeTarget = document.querySelector(".graphiql-container");
      var observer = themeTarget
        ? new MutationObserver(function () { doRender(); })
        : null;
      if (observer) {
        observer.observe(themeTarget, { attributes: true, attributeFilter: ["class"] });
      }

      return function () {
        if (observer) observer.disconnect();
        if (cleanupRef.current) {
          cleanupRef.current();
          cleanupRef.current = null;
        }
      };
    },
    [series]
  );

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
      className: "san-chart-overlay",
      onClick: function (e) {
        if (e.target === e.currentTarget) onClose();
      },
    },
    React.createElement(
      "div",
      { className: "san-chart-modal" },
      // Header
      React.createElement(
        "div",
        { className: "san-chart-header" },
        React.createElement(
          "span",
          { className: "san-chart-title" },
          series.length > 0
            ? series.map(function (s) { return s.label; }).join(", ")
            : "Chart"
        ),
        React.createElement(
          "button",
          {
            className: "san-chart-close-btn",
            onClick: onClose,
            type: "button",
            "aria-label": "Close chart",
          },
          "\u2715"
        )
      ),
      // Chart container or empty state
      series.length === 0
        ? React.createElement(
            "div",
            { className: "san-chart-empty" },
            "No timeseries data found in the response. Run a query with timeseriesData or timeseriesDataJson first."
          )
        : React.createElement("div", {
            ref: containerRef,
            className: "san-chart-container",
          })
    )
  );
}

// ─── Chart Button (placed in toolbar area) ──────────────────────

var ChartIcon = React.createElement(
  "svg",
  {
    width: 16,
    height: 16,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 2,
    strokeLinecap: "round",
    strokeLinejoin: "round",
  },
  React.createElement("polyline", { points: "22 12 18 12 15 21 9 3 6 12 2 12" })
);

export function ChartButton() {
  const [open, setOpen] = useState(false);

  const toggle = useCallback(function () {
    setOpen(function (v) { return !v; });
  }, []);

  const close = useCallback(function () {
    setOpen(false);
  }, []);

  return React.createElement(
    React.Fragment,
    null,
    React.createElement(
      "button",
      {
        className: "graphiql-toolbar-button",
        title: "Show Chart",
        onClick: toggle,
        type: "button",
        style: {
          display: "inline-flex",
          alignItems: "center",
          justifyContent: "center",
        },
      },
      ChartIcon
    ),
    open && React.createElement(ChartModal, { onClose: close })
  );
}
