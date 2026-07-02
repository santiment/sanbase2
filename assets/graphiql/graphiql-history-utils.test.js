import { describe, it, expect } from "vitest";
import { itemsToClear } from "./graphiql-history-utils.js";

describe("itemsToClear", function () {
  it("keeps favorites", function () {
    var items = [
      { query: "{ a }", favorite: true },
      { query: "{ b }" },
      { query: "{ c }", favorite: false },
    ];
    var result = itemsToClear(items);
    expect(result.length).toBe(2);
    result.forEach(function (item) {
      expect(item.favorite).toBeFalsy();
    });
  });

  it("returns all items when none are favorites", function () {
    var items = [{ query: "{ a }" }, { query: "{ b }" }];
    expect(itemsToClear(items)).toEqual(items);
  });

  it("returns empty for empty input", function () {
    expect(itemsToClear([])).toEqual([]);
  });

  it("returns empty when everything is a favorite", function () {
    var items = [{ query: "{ a }", favorite: true }];
    expect(itemsToClear(items)).toEqual([]);
  });
});
