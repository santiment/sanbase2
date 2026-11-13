#!/usr/bin/env bash
# Rebuild the Phoenix static assets (Tailwind CSS + esbuild JS) into priv/static/assets.
#
# On macOS the downloaded tailwind/esbuild binaries can end up with an invalid
# code signature, and the kernel then SIGKILLs them (`mix tailwind default exited
# with 137`). This script ad-hoc re-signs any such binary before building.
#
# Usage: bin/build_assets.sh [--minify]
#   --minify   build with `mix assets.deploy` (minified + digested) instead of `mix assets.build`

set -euo pipefail

minify=false
for arg in "$@"; do
  case "$arg" in
    --minify) minify=true ;;
    -h | --help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

cd "$(dirname "$0")/.."

echo "==> Installing tailwind/esbuild binaries (if missing)"
mix assets.setup

if [[ -f assets/package.json && ! -d assets/node_modules ]]; then
  echo "==> Installing npm dependencies"
  npm install --prefix assets
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "==> Checking code signatures of asset binaries"
  shopt -s nullglob
  for bin in _build/tailwind-* _build/esbuild-*; do
    [[ -f "$bin" && -x "$bin" ]] || continue

    if codesign --verify "$bin" >/dev/null 2>&1; then
      echo "    ok        $bin"
    else
      xattr -d com.apple.quarantine "$bin" 2>/dev/null || true
      codesign --force --sign - "$bin"
      echo "    re-signed $bin"
    fi
  done
  shopt -u nullglob
fi

if $minify; then
  echo "==> Building minified assets (mix assets.deploy)"
  mix assets.deploy
else
  echo "==> Building assets (mix assets.build)"
  mix assets.build
fi

for f in priv/static/assets/app.css priv/static/assets/app.js; do
  if [[ ! -s "$f" ]]; then
    echo "ERROR: expected $f to be built, but it is missing or empty" >&2
    exit 1
  fi
done

echo "==> Done"
ls -lh priv/static/assets/app.css priv/static/assets/app.js
