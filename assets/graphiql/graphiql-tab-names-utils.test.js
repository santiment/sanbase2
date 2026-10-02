import { describe, it, expect } from "vitest";
import {
  UNTITLED,
  emptyTabNames,
  isValidTabNames,
  migrateLegacyTabNames,
  resolveTabNames,
  setCustomTabName,
} from "./graphiql-tab-names-utils.js";

function tab(id, title) {
  return { id: id, title: title || UNTITLED };
}

describe("resolveTabNames", function () {
  it("gives untitled tabs Query N and keeps GraphiQL titles otherwise", function () {
    var r = resolveTabNames([tab("a"), tab("b", "MyOp"), tab("c")], emptyTabNames());
    expect(r.names).toEqual({ a: "Query 1", b: null, c: "Query 2" });
    expect(r.state.counter).toBe(2);
    expect(r.changed).toBe(true);
  });

  it("keeps names attached to ids when tabs are reordered", function () {
    var first = resolveTabNames([tab("a"), tab("b"), tab("c")], emptyTabNames());
    var r = resolveTabNames([tab("c"), tab("a"), tab("b")], first.state);
    expect(r.names).toEqual({ a: "Query 1", b: "Query 2", c: "Query 3" });
    expect(r.changed).toBe(false);
  });

  it("does not shift names when a tab is closed", function () {
    // Regression: index keys moved "Query 2" onto the third tab after closing the first.
    var first = resolveTabNames([tab("a"), tab("b"), tab("c")], emptyTabNames());
    var r = resolveTabNames([tab("b"), tab("c")], first.state);
    expect(r.names).toEqual({ b: "Query 2", c: "Query 3" });
    expect(r.state.auto).toEqual({ b: "Query 2", c: "Query 3" }); // closed tab pruned
  });

  it("never reuses numbers", function () {
    var s1 = resolveTabNames([tab("a"), tab("b")], emptyTabNames()).state;
    var r = resolveTabNames([tab("b"), tab("d")], s1);
    expect(r.names.d).toBe("Query 3");
  });

  it("custom names win, even over an operation name", function () {
    var s = setCustomTabName(emptyTabNames(), "a", "  Dev activity  ");
    var r = resolveTabNames([tab("a", "MyOp")], s);
    expect(r.names).toEqual({ a: "Dev activity" });
  });

  it("an empty custom name falls back to the default", function () {
    var s = resolveTabNames([tab("a")], emptyTabNames()).state;
    s = setCustomTabName(s, "a", "Mine");
    expect(resolveTabNames([tab("a")], s).names.a).toBe("Mine");
    s = setCustomTabName(s, "a", "  ");
    expect(resolveTabNames([tab("a")], s).names.a).toBe("Query 1");
  });

  it("restores the auto name when the operation name is removed", function () {
    var s = resolveTabNames([tab("a")], emptyTabNames()).state;
    var named = resolveTabNames([tab("a", "MyOp")], s);
    expect(named.names.a).toBeNull();
    expect(resolveTabNames([tab("a")], named.state).names.a).toBe("Query 1");
  });

  it("tabs that start with an operation name get no auto number", function () {
    var r = resolveTabNames([tab("a", "MyOp")], emptyTabNames());
    expect(r.state.counter).toBe(0);
    expect(r.changed).toBe(false);
  });
});

describe("migrateLegacyTabNames", function () {
  it("maps position keys onto current tab ids, splitting auto and custom names", function () {
    var s = migrateLegacyTabNames({ "tab-0": "Query 4", "tab-1": "Dev v1 vs v2", "tab-5": "gone" }, 7, [tab("a"), tab("b")]);
    expect(s.auto).toEqual({ a: "Query 4" });
    expect(s.custom).toEqual({ b: "Dev v1 vs v2" });
    expect(s.counter).toBe(7);
    expect(isValidTabNames(s)).toBe(true);
  });

  it("keeps the counter above migrated Query N names when the counter is missing", function () {
    var s = migrateLegacyTabNames({ "tab-0": "Query 1", "tab-3": "Query 6" }, NaN, [tab("a")]);
    expect(s.counter).toBe(6);
    var r = resolveTabNames([tab("a"), tab("b")], s);
    expect(r.names).toEqual({ a: "Query 1", b: "Query 7" });
  });

  it("tolerates junk", function () {
    var s = migrateLegacyTabNames({ x: "y", "tab-0": 5 }, NaN, [tab("a")]);
    expect(s).toEqual(emptyTabNames());
  });
});

describe("isValidTabNames", function () {
  it("rejects other shapes", function () {
    expect(isValidTabNames(null)).toBe(false);
    expect(isValidTabNames({ "tab-0": "Query 1" })).toBe(false);
    expect(isValidTabNames(emptyTabNames())).toBe(true);
  });
});
