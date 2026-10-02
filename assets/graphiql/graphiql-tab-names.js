/**
 * Tab naming: untitled tabs get "Query N", double-click a tab to rename it.
 *
 * Rendered as an invisible child of <GraphiQL> so it can read the tab list
 * from GraphiQL state. GraphiQL recomputes tab.title from the query on every
 * edit, so names cannot live in its state; instead each tab button gets a
 * data-san-name attribute that CSS shows in place of GraphiQL's own text
 * (graphiql.css). React's text node is never touched, so GraphiQL can keep
 * re-rendering the tab bar normally.
 */
import { useEffect, useLayoutEffect, useRef } from "react";
import { useGraphiQL } from "@graphiql/react";
import {
  UNTITLED,
  emptyTabNames,
  isValidTabNames,
  migrateLegacyTabNames,
  resolveTabNames,
  setCustomTabName,
} from "./graphiql-tab-names-utils.js";

var STORAGE_KEY = "san-graphiql-tab-names-v2";
var LEGACY_NAMES_KEY = "san-graphiql-tab-names";
var LEGACY_COUNTER_KEY = "san-graphiql-tab-counter";
var MAX_APPLY_RETRIES = 10;

function readJson(key) {
  try {
    var raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    return null;
  }
}

function save(state) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch (e) {
    // Names still work for this page session.
  }
}

function load(tabs) {
  var state = readJson(STORAGE_KEY);
  if (isValidTabNames(state)) return state;
  var legacy = readJson(LEGACY_NAMES_KEY);
  if (legacy && typeof legacy === "object") {
    var counter = parseInt(readJson(LEGACY_COUNTER_KEY), 10);
    return migrateLegacyTabNames(legacy, counter, tabs);
  }
  return emptyTabNames();
}

function tabButtons() {
  var root = document.getElementById("graphiql");
  return root ? Array.from(root.querySelectorAll(".graphiql-session-header .graphiql-tab-button")) : [];
}

// Floating input over the tab button, appended to <body> so the tab's
// React-managed children are left alone.
function openRenameInput(btn, initial, onCommit) {
  if (document.querySelector(".san-tab-rename")) return;
  var rect = btn.getBoundingClientRect();
  var style = getComputedStyle(btn);
  var input = document.createElement("input");
  input.type = "text";
  input.className = "san-tab-rename";
  input.value = initial;
  input.setAttribute("aria-label", "Tab name");
  input.placeholder = "Default name";
  input.style.left = rect.left + "px";
  input.style.top = rect.top + "px";
  input.style.width = Math.max(rect.width, 80) + "px";
  input.style.height = rect.height + "px";
  input.style.font = style.font;
  document.body.appendChild(input);
  input.focus();
  input.select();

  var finished = false;
  function finish(commit) {
    if (finished) return;
    finished = true;
    window.removeEventListener("resize", cancel);
    if (commit) onCommit(input.value);
    input.remove();
    btn.focus();
  }
  function cancel() { finish(false); }

  input.addEventListener("blur", function () { finish(true); });
  input.addEventListener("keydown", function (e) {
    if (e.key === "Enter") { e.preventDefault(); finish(true); }
    if (e.key === "Escape") { e.preventDefault(); finish(false); }
  });
  window.addEventListener("resize", cancel);
}

export function SanTabNames() {
  var tabs = useGraphiQL(function (state) { return state.tabs; });
  var tabsRef = useRef(tabs);
  var stateRef = useRef(null);
  var namesRef = useRef({});
  var retryRef = useRef(0);

  tabsRef.current = tabs;
  if (stateRef.current === null) stateRef.current = load(tabs);

  function apply() {
    var current = tabsRef.current;
    var buttons = tabButtons();
    // Buttons and tabs are rendered in the same order. If the DOM is not in
    // sync yet, try again on the next frame instead of mislabeling tabs.
    if (buttons.length !== current.length) {
      if (retryRef.current++ < MAX_APPLY_RETRIES) requestAnimationFrame(apply);
      return;
    }
    retryRef.current = 0;
    buttons.forEach(function (btn, i) {
      var id = current[i].id;
      var name = namesRef.current[id];
      btn.dataset.sanTabId = id;
      if (name) {
        btn.dataset.sanName = name;
        btn.setAttribute("aria-label", name);
      } else {
        delete btn.dataset.sanName;
        btn.removeAttribute("aria-label");
      }
    });
  }

  function refresh() {
    var resolved = resolveTabNames(tabsRef.current, stateRef.current);
    stateRef.current = resolved.state;
    namesRef.current = resolved.names;
    if (resolved.changed) save(resolved.state);
    apply();
  }

  // Layout effect: label tabs before paint, so "<untitled>" never flashes.
  useLayoutEffect(refresh, [tabs]);

  useEffect(function () {
    var root = document.getElementById("graphiql");
    if (!root) return undefined;

    function onDblClick(e) {
      var btn = e.target.closest(".graphiql-tab-button");
      if (!btn || !btn.dataset.sanTabId) return;
      e.preventDefault();
      e.stopPropagation();
      var id = btn.dataset.sanTabId;
      var tab = tabsRef.current.find(function (t) { return t.id === id; });
      var initial = namesRef.current[id] || (tab && tab.title !== UNTITLED ? tab.title : "");
      openRenameInput(btn, initial, function (value) {
        stateRef.current = setCustomTabName(stateRef.current, id, value);
        refresh();
        save(stateRef.current);
      });
    }

    root.addEventListener("dblclick", onDblClick);
    return function () { root.removeEventListener("dblclick", onDblClick); };
  }, []);

  return null;
}
