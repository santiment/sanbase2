/**
 * Santiment GraphiQL — entry point.
 * Bundled with esbuild into a single file served at /assets/graphiql.js
 */

// --- Monaco Web Workers ---
// Must be defined before Monaco loads. Workers are built as separate esbuild entry points.
globalThis.MonacoEnvironment = {
  getWorkerUrl(_workerId, label) {
    if (label === "json") return "/assets/graphiql-json.worker.js";
    if (label === "graphql") return "/assets/graphiql-graphql.worker.js";
    return "/assets/graphiql-editor.worker.js";
  },
};

import React, { useEffect, useRef } from "react";
import { createRoot } from "react-dom/client";
import { GraphiQL } from "graphiql";
import { useMonaco } from "@graphiql/react";
import { explorerPlugin } from "@graphiql/plugin-explorer";
import { examplesPlugin } from "./graphiql-examples-plugin.js";
import { historyPlugin } from "./graphiql-history-plugin.js";
import { createHistoryStore, withHistory } from "./graphiql-history-store.js";
import { createFetcher } from "./graphiql-fetcher.js";
import { localStorageBackend } from "./graphiql-storage.js";
import { ChartButton } from "./graphiql-chart-modal.js";
import { TableButton } from "./graphiql-table-modal.js";
import { SanTabNames } from "./graphiql-tab-names.js";
import { SanAutocomplete } from "./graphiql-autocomplete.js";
import { isEffectivelyDark } from "./graphiql-theme.js";

// CSS: base GraphiQL styles, explorer plugin styles, then our customizations
import "graphiql/style.css";
import "@graphiql/plugin-explorer/style.css";
import "./graphiql.css";

// --- Custom Monaco light theme ---
// Registered via the public useMonaco() hook from @graphiql/react.
// Rendered as an invisible child component inside <GraphiQL>.
const LIGHT_THEME_RULES = [
  { token: "keyword.gql",                    foreground: "1565c0" },  // blue — query/mutation/fragment
  { token: "type.identifier.gql",            foreground: "b71c1c" },  // deep red — type/field names
  { token: "argument.identifier.gql",        foreground: "6a1b9a" },  // purple — argument names
  { token: "key.identifier.gql",             foreground: "6a1b9a" },  // purple — argument names
  { token: "string.gql",                     foreground: "2e7d32" },  // green — string values
  { token: "string.invalid.gql",             foreground: "2e7d32" },
  { token: "number.gql",                     foreground: "e65100" },  // orange — numbers
  { token: "number.float.gql",               foreground: "e65100" },
  { token: "comment.gql",                    foreground: "757575" },  // grey — comments
  { token: "delimiter.gql",                  foreground: "37474f" },  // dark grey — braces
  { token: "delimiter.curly.gql",            foreground: "37474f" },
  { token: "delimiter.parenthesis.gql",      foreground: "37474f" },
  { token: "delimiter.square.gql",           foreground: "37474f" },
];

const LIGHT_THEME_COLORS = {
  "editor.background": "#ffffff00",
  "scrollbar.shadow": "#ffffff00",
};

const LIGHT_THEME_DATA = { base: "vs", inherit: true, rules: LIGHT_THEME_RULES, colors: LIGHT_THEME_COLORS };

function SantimentTheme() {
  const monaco = useMonaco(function (state) { return state.monaco; });
  const registered = useRef(false);

  useEffect(function () {
    if (!monaco || registered.current) return;
    registered.current = true;

    monaco.editor.defineTheme("santiment-light", LIGHT_THEME_DATA);
    monaco.editor.defineTheme("graphiql-LIGHT", LIGHT_THEME_DATA);

    // Only force the custom light theme when the effective theme is light.
    // When dark, let GraphiQL's built-in dark theme remain active.
    if (!isEffectivelyDark()) {
      monaco.editor.setTheme("graphiql-LIGHT");
    }
  }, [monaco]);

  return null;
}

// --- URL Parameter Handling ---
// Supports ?query=...&variables=... for sharing queries.
// Headers are NEVER read from or synced to the URL — use the headers editor panel instead.
// This prevents credentials from leaking into browser history, server logs, and referrer headers.
const urlParams = new URLSearchParams(window.location.search);
const initialQuery = urlParams.get("query") || "";
const initialVariables = urlParams.get("variables") || "";

function syncUrlParam(key, value, isEmpty) {
  const params = new URLSearchParams(window.location.search);
  if (value && !(isEmpty && isEmpty(value))) {
    params.set(key, value);
  } else {
    params.delete(key);
  }
  history.replaceState(null, null, "?" + params.toString());
}

function onEditQuery(query) {
  syncUrlParam("query", query);
}

function onEditVariables(variables) {
  syncUrlParam("variables", variables, function(v) {
    return v.trim() === "" || v.trim() === "{}";
  });
}

// --- Storage ---
// Where history and the autocomplete cache are kept. To use another browser
// storage, swap this line for another backend (see graphiql-storage.js).
const storage = localStorageBackend();

// --- HTTP Fetcher ---
// Cancellable (Stop aborts the request), turns non-JSON error pages into
// readable errors, and records executions in the query history.
const historyStore = createHistoryStore({
  storage: storage,
  onError: function(e) {
    console.error("[graphiql-history] failed to save history", e);
  },
});

const graphqlEndpoint = window.location.origin + "/graphql";

const fetcher = withHistory(
  createFetcher({ endpoint: graphqlEndpoint }),
  historyStore,
  function(e) {
    console.error("[graphiql-history] failed to record run", e);
  }
);

const graphiqlRoot = document.getElementById("graphiql");
if (!graphiqlRoot) {
  throw new Error("GraphiQL mount point #graphiql not found");
}

// --- Plugins ---
const explorer = explorerPlugin();
const examples = examplesPlugin();

// GraphiQL mounts the stock HistoryStore only when the plugins array contains
// the HISTORY_PLUGIN object itself (identity check in GraphiQL.js). Passing our
// own plugin object keeps the stock per-keystroke recording switched off.
const sanHistory = historyPlugin(historyStore);

// --- Render ---
const root = createRoot(graphiqlRoot);
root.render(
  React.createElement(
    GraphiQL,
    {
      fetcher: fetcher,
      plugins: [explorer, examples, sanHistory],
      initialQuery: initialQuery || undefined,
      initialVariables: initialVariables || undefined,
      shouldPersistHeaders: false,
      defaultEditorToolsVisibility: true,
      onEditQuery: onEditQuery,
      onEditVariables: onEditVariables,
    },
    // Custom Monaco theme — must be inside GraphiQL to access useMonaco hook
    React.createElement(SantimentTheme),
    // Tab names keyed by tab id ("Query N", double-click or F2 to rename)
    React.createElement(SanTabNames),
    // Suggestions inside metric/slug/version strings
    React.createElement(SanAutocomplete, { endpoint: graphqlEndpoint, storage: storage }),
    // Toolbar: render prop receives default buttons, we append the chart and table buttons
    React.createElement(
      GraphiQL.Toolbar,
      null,
      function (props) {
        return React.createElement(
          React.Fragment,
          null,
          props.prettify,
          props.merge,
          props.copy,
          React.createElement(ChartButton),
          React.createElement(TableButton)
        );
      }
    )
  )
);
