/**
 * Shared theme detection for Santiment GraphiQL.
 *
 * GraphiQL puts graphiql-dark / graphiql-light on .graphiql-container, NOT on <body>.
 * When theme is "system" neither class is present — fall back to the media query.
 */
export function isEffectivelyDark() {
  const container = document.querySelector(".graphiql-container");
  if (container) {
    if (container.classList.contains("graphiql-dark")) return true;
    if (container.classList.contains("graphiql-light")) return false;
  }
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}
