#!/bin/bash
#
# Build the chart explorer and deploy it to Cloudflare Pages.
#
# Served from https://84beings.com/explore/, so --base-href must stay
# /explore/ — lib/astro/swe_web.dart resolves the wasm glue against
# document.baseURI and would look in the wrong place without it.

set -euo pipefail

cd "$(dirname "$0")/.."

WRANGLER_VERSION=4.115.0

if [ -n "$(git status --porcelain)" ]; then
  echo "warning: working tree is dirty — deploying uncommitted changes" >&2
fi
echo "==> deploying $(git rev-parse --short HEAD) on $(git branch --show-current)"

flutter build web --release --base-href=/explore/

# The Swiss Ephemeris web glue ships as a swisseph_rs package asset. If it is
# missing, the build resolved against the wrong swisseph_rs (or a stale
# vendored copy in web/) and the engine will fail to boot in the browser.
# Catch that here rather than after it is live.
GLUE=build/web/assets/packages/swisseph_rs/wasm/swisseph_ffi.js
if [ ! -f "$GLUE" ]; then
  echo "error: $GLUE missing — refusing to deploy a build with no engine" >&2
  exit 1
fi

npx --yes "wrangler@${WRANGLER_VERSION}" pages deploy build/web \
  --project-name 84beings-explore
