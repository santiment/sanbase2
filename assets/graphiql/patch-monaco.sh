#!/bin/sh
# Patch monaco-graphql to use a slim Monaco build instead of the full editor.
#
# monaco-graphql/esm/monaco-editor.js re-exports from edcore.main.js which
# imports editor.all.js (all 55+ contrib modules). We replace it with
# editor.api.js (core only) + the minimum contribs GraphiQL needs.
#
# Run automatically via npm postinstall, or manually after npm install.

SHIM="node_modules/monaco-graphql/esm/monaco-editor.js"

if [ ! -f "$SHIM" ]; then
  echo "patch-monaco: $SHIM not found, skipping"
  exit 0
fi

cat > "$SHIM" << 'EOF'
// Patched by scripts/patch-monaco.sh — slim build for GraphiQL
import 'monaco-editor/esm/vs/basic-languages/graphql/graphql.contribution.js';
import 'monaco-editor/esm/vs/language/json/monaco.contribution.js';

// Core editor
import 'monaco-editor/esm/vs/editor/browser/coreCommands.js';
import 'monaco-editor/esm/vs/editor/browser/widget/codeEditor/codeEditorWidget.js';

// Minimum contribs for GraphiQL:
import 'monaco-editor/esm/vs/editor/contrib/suggest/browser/suggestController.js';
import 'monaco-editor/esm/vs/editor/contrib/hover/browser/hoverContribution.js';
import 'monaco-editor/esm/vs/editor/contrib/find/browser/findController.js';
import 'monaco-editor/esm/vs/editor/contrib/contextmenu/browser/contextmenu.js';
import 'monaco-editor/esm/vs/editor/contrib/bracketMatching/browser/bracketMatching.js';

// Codicon styles
import 'monaco-editor/esm/vs/base/browser/ui/codicons/codiconStyles.js';

export * from 'monaco-editor/esm/vs/editor/editor.api.js';
EOF

echo "patch-monaco: patched $SHIM (slim build)"
