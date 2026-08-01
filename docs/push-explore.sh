#!/bin/bash
#
# Build the chart explorer and deploy it to Cloudflare Pages.
#
# Served from https://84beings.com/explore/, so --base-href must stay
# /explore/ — lib/astro/swe_web.dart resolves the wasm glue against
# document.baseURI and would look in the wrong place without it.

set -euo pipefail

cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain)" ]; then
  echo "warning: working tree is dirty — deploying uncommitted changes" >&2
fi
echo "==> deploying $(git rev-parse --short HEAD) on $(git branch --show-current)"

flutter build web --release --base-href=/explore/

# The Swiss Ephemeris web glue ships as a swisseph_rs package asset. If it is
# missing, the build resolved against the wrong swisseph_rs (or a stale
# vendored copy in web/) and the engine will fail to boot in the browser.
# Catch that here rather than after it is live.
#
# Both files matter: the .js is what initializeWasm loads, and it fetches the
# sibling .wasm at runtime. A build carrying only the glue passes a JS-only
# check and then dies on module instantiation in the browser.
WASM_DIR=build/web/assets/packages/swisseph_rs/wasm
for f in "$WASM_DIR/swisseph_ffi.js" "$WASM_DIR/swisseph_ffi.wasm"; do
  if [ ! -s "$f" ]; then
    echo "error: $f missing or empty — refusing to deploy a build with no engine" >&2
    exit 1
  fi
done

npx --yes wrangler pages deploy build/web \
  --project-name 84beings-explore
