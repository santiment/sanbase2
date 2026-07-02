/**
 * Pure helpers for the custom History plugin.
 * Kept free of GraphiQL/React imports so they can be unit-tested in node.
 */

// Mirrors the built-in Clear semantics (@graphiql/toolkit deleteHistory):
// favorites survive a Clear, everything else goes.
export function itemsToClear(items) {
  return items.filter(function (item) {
    return !item.favorite;
  });
}
