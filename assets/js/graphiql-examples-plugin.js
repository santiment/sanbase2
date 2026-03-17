/**
 * GraphiQL "Example Queries" plugin.
 * Shows a permanent, non-clearable list of curated example queries
 * that help developers discover the Santiment API.
 */
import React, { useCallback } from "react";
import { useGraphiQL } from "@graphiql/react";
import examples from "./graphiql-examples.js";

// --- Icon: a book/guide icon ---
var BookIcon = function () {
  return React.createElement(
    "svg",
    {
      height: "1em",
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      strokeWidth: 1.5,
      xmlns: "http://www.w3.org/2000/svg",
    },
    React.createElement("path", {
      d: "M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20",
      strokeLinecap: "round",
      strokeLinejoin: "round",
    }),
    React.createElement("path", {
      d: "M8 7h6",
      strokeLinecap: "round",
    })
  );
};

// --- Styles ---
var styles = {
  container: {
    padding: "12px",
    fontFamily: "system-ui, -apple-system, sans-serif",
    fontSize: "13px",
    height: "100%",
    overflowY: "auto",
  },
  heading: {
    fontSize: "13px",
    fontWeight: 600,
    margin: "0 0 4px 0",
    color: "hsl(var(--color-neutral-60))",
    textTransform: "uppercase",
    letterSpacing: "0.5px",
  },
  subtitle: {
    fontSize: "12px",
    color: "hsl(var(--color-neutral-50))",
    margin: "0 0 12px 0",
  },
  item: {
    padding: "8px 10px",
    marginBottom: "4px",
    borderRadius: "4px",
    cursor: "pointer",
    border: "1px solid transparent",
    transition: "background 0.15s, border-color 0.15s",
  },
  itemName: {
    fontWeight: 500,
    marginBottom: "2px",
  },
  itemDesc: {
    fontSize: "11px",
    color: "hsl(var(--color-neutral-50))",
    lineHeight: 1.3,
  },
};

// --- Plugin content component ---
function ExamplesContent() {
  var editors = useGraphiQL(function (state) {
    return { queryEditor: state.queryEditor, variableEditor: state.variableEditor };
  });

  var handleClick = useCallback(
    function (example) {
      if (editors.queryEditor) {
        editors.queryEditor.setValue(example.query);
      }
      if (editors.variableEditor) {
        editors.variableEditor.setValue(example.variables || "");
      }
    },
    [editors]
  );

  return React.createElement(
    "div",
    { style: styles.container },
    React.createElement("p", { style: styles.heading }, "Example Queries"),
    React.createElement(
      "p",
      { style: styles.subtitle },
      "Click to load into the editor"
    ),
    examples.map(function (example, i) {
      return React.createElement(
        "div",
        {
          key: i,
          style: styles.item,
          className: "graphiql-example-item",
          onClick: function () {
            handleClick(example);
          },
        },
        React.createElement("div", { style: styles.itemName }, example.name),
        example.description &&
          React.createElement(
            "div",
            { style: styles.itemDesc },
            example.description
          )
      );
    })
  );
}

// --- Plugin factory ---
export function examplesPlugin() {
  return {
    title: "Example Queries",
    icon: BookIcon,
    content: ExamplesContent,
  };
}
