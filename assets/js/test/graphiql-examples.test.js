import { describe, it, expect } from "vitest";
import sections from "../graphiql-examples.js";

describe("graphiql-examples", function () {
  it("exports an array of sections", function () {
    expect(Array.isArray(sections)).toBe(true);
    expect(sections.length).toBeGreaterThan(0);
  });

  it("every section has a title and items array", function () {
    sections.forEach(function (section, i) {
      expect(section.title, "section " + i + " missing title").toBeTruthy();
      expect(Array.isArray(section.items), "section " + i + " items not array").toBe(true);
      expect(section.items.length, "section " + i + " has no items").toBeGreaterThan(0);
    });
  });

  it("every example has a name and a non-empty query", function () {
    sections.forEach(function (section) {
      section.items.forEach(function (example) {
        expect(example.name, "missing name in " + section.title).toBeTruthy();
        expect(typeof example.query).toBe("string");
        expect(example.query.trim().length).toBeGreaterThan(0);
      });
    });
  });

  it("no example has a Raw SQL query", function () {
    sections.forEach(function (section) {
      expect(section.title.toLowerCase()).not.toContain("raw sql");
      section.items.forEach(function (example) {
        expect(example.name.toLowerCase()).not.toContain("raw sql");
      });
    });
  });

  it("Discovery section comes first", function () {
    expect(sections[0].title).toBe("Discovery");
  });

  it("queries are valid GraphQL (start with { or query/mutation keyword)", function () {
    sections.forEach(function (section) {
      section.items.forEach(function (example) {
        var trimmed = example.query.trim();
        var startsCorrectly =
          trimmed.startsWith("{") ||
          trimmed.startsWith("query") ||
          trimmed.startsWith("mutation") ||
          trimmed.startsWith("subscription");
        expect(startsCorrectly, "bad query start in: " + example.name).toBe(true);
      });
    });
  });

  it("variables, if present, are valid JSON", function () {
    sections.forEach(function (section) {
      section.items.forEach(function (example) {
        if (example.variables) {
          expect(function () {
            JSON.parse(example.variables);
          }, "invalid variables JSON in: " + example.name).not.toThrow();
        }
      });
    });
  });
});
