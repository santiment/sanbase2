/**
 * Shared editor helpers for plugins (history, examples).
 */

// Put a query and its variables into the GraphiQL editors.
// `editors` is { queryEditor, variableEditor } from useGraphiQL.
export function loadIntoEditors(editors, query, variables) {
  if (editors.queryEditor) editors.queryEditor.setValue(query || "");
  if (editors.variableEditor) editors.variableEditor.setValue(variables || "");
}
