/**
 * Pure helpers for tab naming (graphiql-tab-names.js).
 *
 * Names are keyed by GraphiQL's tab id, which is stable across reorder,
 * close and reload (GraphiQL persists tabs with their ids). The previous
 * implementation keyed by position, so closing or dragging a tab moved
 * names onto the wrong tabs.
 *
 * State shape: { counter, auto: { id: "Query 3" }, custom: { id: "My name" } }
 * (versioned through the storage key).
 *   auto   - "Query N" given to a tab while it has no operation name
 *   custom - name set by double-clicking the tab; wins over everything
 */
export var UNTITLED = "<untitled>";
var AUTO_NAME = /^Query \d+$/;

export function emptyTabNames() {
  return { counter: 0, auto: {}, custom: {} };
}

export function isValidTabNames(state) {
  return !!state && typeof state.counter === "number" &&
    !!state.auto && typeof state.auto === "object" &&
    !!state.custom && typeof state.custom === "object";
}

// Old format: { "tab-0": "Query 1", "tab-1": "My name" } keyed by position,
// plus a separate counter. Mapped onto the current tabs by position, once.
export function migrateLegacyTabNames(legacyNames, legacyCounter, tabs) {
  var state = emptyTabNames();
  state.counter = Number.isFinite(legacyCounter) ? legacyCounter : 0;
  Object.keys(legacyNames || {}).forEach(function (key) {
    var m = /^tab-(\d+)$/.exec(key);
    var tab = m && tabs[Number(m[1])];
    var name = legacyNames[key];
    if (!tab || typeof name !== "string" || !name.trim()) return;
    if (AUTO_NAME.test(name)) state.auto[tab.id] = name;
    else state.custom[tab.id] = name;
  });
  return state;
}

// Returns { state, names, changed }. names maps tab id to the name to show,
// or null to keep GraphiQL's own title (the operation name).
export function resolveTabNames(tabs, state) {
  var next = { counter: state.counter, auto: {}, custom: {} };
  var names = {};

  tabs.forEach(function (tab) {
    var custom = state.custom[tab.id];
    if (custom) next.custom[tab.id] = custom;
    // Keep an auto name even while the tab has an operation name, so it comes
    // back if the operation name is removed again.
    var auto = state.auto[tab.id];
    if (!auto && !custom && tab.title === UNTITLED) {
      next.counter++;
      auto = "Query " + next.counter;
    }
    if (auto) next.auto[tab.id] = auto;

    if (custom) names[tab.id] = custom;
    else if (tab.title === UNTITLED) names[tab.id] = auto;
    else names[tab.id] = null;
  });

  return { state: next, names: names, changed: !sameState(state, next) };
}

// Empty name removes the custom name, falling back to the default.
export function setCustomTabName(state, id, name) {
  var custom = Object.assign({}, state.custom);
  var trimmed = (name || "").trim();
  if (trimmed) custom[id] = trimmed;
  else delete custom[id];
  return Object.assign({}, state, { custom: custom });
}

function sameMap(a, b) {
  var ka = Object.keys(a);
  return ka.length === Object.keys(b).length && ka.every(function (k) { return a[k] === b[k]; });
}

function sameState(a, b) {
  return a.counter === b.counter && sameMap(a.auto, b.auto) && sameMap(a.custom, b.custom);
}
