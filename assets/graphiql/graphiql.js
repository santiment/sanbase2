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
import { GraphiQL, HISTORY_PLUGIN } from "graphiql";
import { useMonaco } from "@graphiql/react";
import { explorerPlugin } from "@graphiql/plugin-explorer";
import { examplesPlugin } from "./graphiql-examples-plugin.js";
import { ChartButton } from "./graphiql-chart-modal.js";
import { TableButton } from "./graphiql-table-modal.js";
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

// --- HTTP Fetcher ---
const graphqlEndpoint = window.location.origin + "/graphql";

function fetcher(graphQLParams, fetcherOpts) {
  const headers = Object.create(null);
  headers["Accept"] = "application/json";
  headers["Content-Type"] = "application/json";

  // Merge headers from the headers editor
  if (fetcherOpts && fetcherOpts.headers) {
    try {
      const editorHeaders = typeof fetcherOpts.headers === "string"
        ? JSON.parse(fetcherOpts.headers)
        : fetcherOpts.headers;
      for (const key of Object.keys(editorHeaders)) {
        headers[key] = editorHeaders[key];
      }
    } catch (e) {
      // Invalid JSON in headers editor — ignore
    }
  }

  return fetch(graphqlEndpoint, {
    method: "POST",
    headers: headers,
    body: JSON.stringify(graphQLParams),
    credentials: "same-origin",
  }).then(function(response) {
    return response.json();
  }).catch(function(error) {
    return { errors: [{ message: error.message }] };
  });
}

// --- Tab naming: auto-name untitled tabs + double-click to rename ---
const tabNames = JSON.parse(localStorage.getItem("san-graphiql-tab-names") || "{}");
let tabCounter = parseInt(localStorage.getItem("san-graphiql-tab-counter") || "0", 10);

function saveTabNames() {
  localStorage.setItem("san-graphiql-tab-names", JSON.stringify(tabNames));
  localStorage.setItem("san-graphiql-tab-counter", String(tabCounter));
}

function getTabIndex(btn) {
  const allTabs = Array.from(document.querySelectorAll(".graphiql-tab-button"));
  return allTabs.indexOf(btn);
}

function renameUntitledTabs() {
  const tabs = document.querySelectorAll(".graphiql-tab-button");
  tabs.forEach(function(tab) {
    if (tab.dataset.sanRenamed) return;
    const idx = getTabIndex(tab);
    const key = "tab-" + idx;

    if (tabNames[key] && tab.textContent.trim() === "<untitled>") {
      tab.textContent = tabNames[key];
      tab.dataset.sanRenamed = "1";
    } else if (tab.textContent.trim() === "<untitled>") {
      tabCounter++;
      const name = "Query " + tabCounter;
      tab.textContent = name;
      tabNames[key] = name;
      tab.dataset.sanRenamed = "1";
      saveTabNames();
    }
  });
}

function startEditing(btn) {
  if (btn.querySelector("input")) return; // already editing

  const currentName = btn.textContent.trim();
  const input = document.createElement("input");
  input.type = "text";
  input.value = currentName;
  input.style.cssText =
    "all:unset; font:inherit; width:100%; min-width:50px; " +
    "border-bottom:1px solid var(--san-border); cursor:text; text-align:center;";

  btn.textContent = "";
  btn.appendChild(input);
  input.focus();
  input.select();

  function commit() {
    const newName = input.value.trim() || currentName;
    btn.textContent = newName;
    const idx = getTabIndex(btn);
    tabNames["tab-" + idx] = newName;
    saveTabNames();
  }

  input.addEventListener("blur", commit);
  input.addEventListener("keydown", function(e) {
    if (e.key === "Enter") { e.preventDefault(); input.blur(); }
    if (e.key === "Escape") { input.value = currentName; input.blur(); }
  });

  // Prevent the click from propagating to the tab button (which would switch tabs)
  input.addEventListener("mousedown", function(e) { e.stopPropagation(); });
  input.addEventListener("click", function(e) { e.stopPropagation(); });
}

// Attach double-click handler via event delegation
const graphiqlRoot = document.getElementById("graphiql");
if (!graphiqlRoot) {
  throw new Error("GraphiQL mount point #graphiql not found");
}
graphiqlRoot.addEventListener("dblclick", function(e) {
  const btn = e.target.closest(".graphiql-tab-button");
  if (btn) {
    e.preventDefault();
    e.stopPropagation();
    startEditing(btn);
  }
});

// Observe only the session header (tab bar) rather than the entire GraphiQL tree,
// to avoid firing renameUntitledTabs on every Monaco keystroke or result render.
const tabObserver = new MutationObserver(renameUntitledTabs);
function observeTabBar() {
  const header = graphiqlRoot.querySelector(".graphiql-session-header");
  if (header) {
    tabObserver.observe(header, { childList: true, subtree: true, characterData: true });
    // Handle tabs already rendered before observer connected
    renameUntitledTabs();
  } else {
    setTimeout(observeTabBar, 200);
  }
}
observeTabBar();

// --- Plugins ---
const explorer = explorerPlugin();
const examples = examplesPlugin();

// --- Render ---
const root = createRoot(document.getElementById("graphiql"));
root.render(
  React.createElement(
    GraphiQL,
    {
      fetcher: fetcher,
      plugins: [explorer, examples, HISTORY_PLUGIN],
      initialQuery: initialQuery || undefined,
      initialVariables: initialVariables || undefined,
      shouldPersistHeaders: false,
      defaultEditorToolsVisibility: true,
      onEditQuery: onEditQuery,
      onEditVariables: onEditVariables,
    },
    // Custom Monaco theme — must be inside GraphiQL to access useMonaco hook
    React.createElement(SantimentTheme),
    // Toolbar: render prop receives default buttons, we append the chart button
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
