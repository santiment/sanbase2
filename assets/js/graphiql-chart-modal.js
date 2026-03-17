/**
 * Chart modal overlay for GraphiQL.
 * Shows an interactive timeseries chart over the response data.
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

  const isDark =
    document.body.classList.contains("graphiql-dark") ||
    (window.matchMedia &&
      window.matchMedia("(prefers-color-scheme: dark)").matches &&
      !document.body.classList.contains("graphiql-light"));

  const series = React.useMemo(
    function () {
      if (!responseEditor) return [];
      const text = responseEditor.getValue();
      return extractTimeseries(text);
    },
    [responseEditor]
  );

  useEffect(
    function () {
      if (!containerRef.current || series.length === 0) return;
      // Clean up previous chart
      if (cleanupRef.current) cleanupRef.current();
      cleanupRef.current = renderChart(containerRef.current, series, isDark);
      return function () {
        if (cleanupRef.current) {
          cleanupRef.current();
          cleanupRef.current = null;
        }
      };
    },
    [series, isDark]
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
      style: {
        position: "fixed",
        inset: 0,
        zIndex: 10000,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "rgba(0,0,0,0.5)",
        backdropFilter: "blur(2px)",
      },
      onClick: function (e) {
        if (e.target === e.currentTarget) onClose();
      },
    },
    React.createElement(
      "div",
      {
        style: {
          width: "90vw",
          height: "75vh",
          maxWidth: 1400,
          maxHeight: 900,
          background: isDark ? "#1e1e1e" : "#ffffff",
          borderRadius: 8,
          overflow: "hidden",
          display: "flex",
          flexDirection: "column",
          boxShadow: "0 20px 60px rgba(0,0,0,0.3)",
        },
      },
      // Header
      React.createElement(
        "div",
        {
          style: {
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            padding: "10px 16px",
            borderBottom: "1px solid " + (isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.1)"),
          },
        },
        React.createElement(
          "span",
          {
            style: {
              fontWeight: 600,
              fontSize: 14,
              color: isDark ? "#d4d4d4" : "#333",
              fontFamily: "system-ui, -apple-system, sans-serif",
            },
          },
          series.length > 0
            ? series.map(function (s) { return s.label; }).join(", ")
            : "Chart"
        ),
        React.createElement(
          "button",
          {
            onClick: onClose,
            style: {
              background: "none",
              border: "none",
              cursor: "pointer",
              fontSize: 18,
              color: isDark ? "#999" : "#666",
              padding: "4px 8px",
              lineHeight: 1,
            },
          },
          "\u2715"
        )
      ),
      // Chart container or empty state
      series.length === 0
        ? React.createElement(
            "div",
            {
              style: {
                flex: 1,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: isDark ? "#666" : "#999",
                fontSize: 14,
                fontFamily: "system-ui, -apple-system, sans-serif",
              },
            },
            "No timeseries data found in the response. Run a query with timeseriesData or timeseriesDataJson first."
          )
        : React.createElement("div", {
            ref: containerRef,
            style: { flex: 1 },
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
