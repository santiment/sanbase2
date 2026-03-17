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

// CSS: base GraphiQL styles, explorer plugin styles, then our customizations
import "graphiql/style.css";
import "@graphiql/plugin-explorer/style.css";
import "../css/graphiql.css";

// --- Register custom Monaco light theme after GraphiQL initializes Monaco ---
// GraphiQL lazily loads Monaco then defines "graphiql-LIGHT" and "graphiql-DARK".
// We poll for globalThis.__MONACO (set by @graphiql/react's monaco store)
// and then define our custom theme on top.
function registerSantimentTheme() {
  var m = globalThis.__MONACO;
  if (!m) {
    setTimeout(registerSantimentTheme, 200);
    return;
  }

  m.editor.defineTheme("santiment-light", {
    base: "vs",
    inherit: true,
    rules: [
      // GraphQL tokens (suffixed .gql by monaco-graphql)
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
    ],
    colors: {
      "editor.background": "#ffffff00",
      "scrollbar.shadow": "#ffffff00",
    },
  });

  // Also override the graphiql-LIGHT theme that GraphiQL uses
  m.editor.defineTheme("graphiql-LIGHT", {
    base: "vs",
    inherit: true,
    rules: [
      { token: "keyword.gql",                    foreground: "1565c0" },
      { token: "type.identifier.gql",            foreground: "b71c1c" },
      { token: "argument.identifier.gql",        foreground: "6a1b9a" },
      { token: "key.identifier.gql",             foreground: "6a1b9a" },
      { token: "string.gql",                     foreground: "2e7d32" },
      { token: "string.invalid.gql",             foreground: "2e7d32" },
      { token: "number.gql",                     foreground: "e65100" },
      { token: "number.float.gql",               foreground: "e65100" },
      { token: "comment.gql",                    foreground: "757575" },
      { token: "delimiter.gql",                  foreground: "37474f" },
      { token: "delimiter.curly.gql",            foreground: "37474f" },
      { token: "delimiter.parenthesis.gql",      foreground: "37474f" },
      { token: "delimiter.square.gql",           foreground: "37474f" },
    ],
    colors: {
      "editor.background": "#ffffff00",
      "scrollbar.shadow": "#ffffff00",
    },
  });

  // Re-apply if currently in light mode
  if (!document.body.classList.contains("graphiql-dark")) {
    m.editor.setTheme("graphiql-LIGHT");
  }
}

registerSantimentTheme();

// --- URL Parameter Handling ---
// Preserves the existing URL format: ?query=...&variables=...&headers=...
// This ensures all existing shared links continue to work.
const urlParams = new URLSearchParams(window.location.search);
const initialQuery = urlParams.get("query") || "";
const initialVariables = urlParams.get("variables") || "";
const initialHeaders = urlParams.get("headers") || "";

function onEditQuery(query) {
  const params = new URLSearchParams(window.location.search);
  if (query) {
    params.set("query", query);
  } else {
    params.delete("query");
  }
  history.replaceState(null, null, "?" + params.toString());
}

function onEditVariables(variables) {
  const params = new URLSearchParams(window.location.search);
  if (variables && variables.trim() !== "" && variables.trim() !== "{}") {
    params.set("variables", variables);
  } else {
    params.delete("variables");
  }
  history.replaceState(null, null, "?" + params.toString());
}

function onEditHeaders(headers) {
  const params = new URLSearchParams(window.location.search);
  if (headers && headers.trim() !== "" && headers.trim() !== "{}") {
    params.set("headers", headers);
  } else {
    params.delete("headers");
  }
  history.replaceState(null, null, "?" + params.toString());
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

const tabObserver = new MutationObserver(renameUntitledTabs);
tabObserver.observe(graphiqlRoot, { childList: true, subtree: true, characterData: true });

// --- Plugins ---
const explorer = explorerPlugin();

// --- Render ---
const root = createRoot(document.getElementById("graphiql"));
root.render(
  React.createElement(GraphiQL, {
    fetcher: fetcher,
    plugins: [explorer],
    initialQuery: initialQuery || undefined,
    initialVariables: initialVariables || undefined,
    initialHeaders: initialHeaders || undefined,
    shouldPersistHeaders: true,
    defaultEditorToolsVisibility: true,
    onEditQuery: onEditQuery,
    onEditVariables: onEditVariables,
    onEditHeaders: onEditHeaders,
  })
);
