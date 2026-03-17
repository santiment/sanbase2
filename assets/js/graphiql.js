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

import React from "react";
import { createRoot } from "react-dom/client";
import { GraphiQL } from "graphiql";
import { explorerPlugin } from "@graphiql/plugin-explorer";
import { examplesPlugin } from "./graphiql-examples-plugin.js";

// CSS: base GraphiQL styles, explorer plugin styles, then our customizations
import "graphiql/style.css";
import "@graphiql/plugin-explorer/style.css";
import "../css/graphiql.css";

// --- Register custom Monaco light theme after GraphiQL initializes Monaco ---
// GraphiQL lazily loads Monaco then defines "graphiql-LIGHT" and "graphiql-DARK".
// We poll for globalThis.__MONACO (set by @graphiql/react's monaco store)
// and then define our custom theme on top.
// Shared theme definition — used for both "santiment-light" and "graphiql-LIGHT"
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

function registerSantimentTheme() {
  const m = globalThis.__MONACO;
  if (!m) {
    setTimeout(registerSantimentTheme, 200);
    return;
  }

  const themeData = { base: "vs", inherit: true, rules: LIGHT_THEME_RULES, colors: LIGHT_THEME_COLORS };
  m.editor.defineTheme("santiment-light", themeData);
  // Override the graphiql-LIGHT theme that GraphiQL uses internally
  m.editor.defineTheme("graphiql-LIGHT", themeData);

  // Re-apply if currently in light mode
  if (!document.body.classList.contains("graphiql-dark")) {
    m.editor.setTheme("graphiql-LIGHT");
  }
}

registerSantimentTheme();

// --- URL Parameter Handling ---
// Preserves the existing URL format: ?query=...&variables=...
// This ensures all existing shared links continue to work.
// NOTE: Headers are intentionally NOT synced to URL to avoid leaking
// credentials (tokens, API keys) into browser history, referrer headers, and logs.
const urlParams = new URLSearchParams(window.location.search);
const initialQuery = urlParams.get("query") || "";
const initialVariables = urlParams.get("variables") || "";
const initialHeaders = urlParams.get("headers") || "";

// Strip headers from URL after reading — prevents credential persistence in browser history
if (initialHeaders) {
  urlParams.delete("headers");
  const qs = urlParams.toString();
  history.replaceState(null, null, qs ? "?" + qs : window.location.pathname);
}

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
  const headers = {
    "Accept": "application/json",
    "Content-Type": "application/json",
  };

  // Merge headers from the headers editor
  if (fetcherOpts && fetcherOpts.headers) {
    try {
      const editorHeaders = typeof fetcherOpts.headers === "string"
        ? JSON.parse(fetcherOpts.headers)
        : fetcherOpts.headers;
      Object.assign(headers, editorHeaders);
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
  React.createElement(GraphiQL, {
    fetcher: fetcher,
    plugins: [explorer, examples],
    initialQuery: initialQuery || undefined,
    initialVariables: initialVariables || undefined,
    initialHeaders: initialHeaders || undefined,
    shouldPersistHeaders: true,
    defaultEditorToolsVisibility: true,
    onEditQuery: onEditQuery,
    onEditVariables: onEditVariables,
  })
);
