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

# --source-maps forces dart2js to emit .map files even in release; without it
# Sentry has nothing to symbolicate against and every minified error reads
# "Field '' has not been initialized". The maps are uploaded to Sentry below
# and stripped before deploy, so they never reach the CDN.
flutter build web --release --base-href=/explore/ --source-maps

# Flutter emits a NOTICES file (third-party licenses) with no extension.
# Cloudflare WAF challenges extensionless requests, producing a 403 that
# surfaces as an uncaught error in Sentry. The app has no license page,
# so the file is unnecessary.
mv build/web/assets/NOTICES /tmp/flutter-notices-$$

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

# Upload dart2js source maps to Sentry so minified stack traces symbolicate.
# `inject` writes matching Debug IDs into the JS and its map, which bind the
# two together — no release string has to line up. Skipped when
# SENTRY_AUTH_TOKEN is unset, so a plain deploy still works without it.
# Load Sentry upload creds (SENTRY_AUTH_TOKEN/ORG/PROJECT) if present. The file
# `export`s them so the sentry-cli child process inherits the auth token — a
# bare (unexported) assignment satisfies the `-n` guard below but leaves
# sentry-cli unauthenticated.
[ -f .sentry-env ] && source .sentry-env
# Refuse to ship a prod build with no source-map upload. `inject` lives inside
# this guard, so a tokenless deploy ships JS with NO debug id — every crash from
# it is permanently un-symbolicatable, and the old code only warned then deployed
# anyway (root cause of a minified prod crash we couldn't read). Fail loud
# instead. Escape hatch for a deliberate non-Sentry deploy: ALLOW_NO_SENTRY=1.
if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  if [ "${ALLOW_NO_SENTRY:-}" = "1" ]; then
    echo "warning: SENTRY_AUTH_TOKEN unset, ALLOW_NO_SENTRY=1 — deploying with UNsymbolicatable stacks" >&2
  else
    echo "error: SENTRY_AUTH_TOKEN unset — refusing to deploy a build whose crashes" >&2
    echo "       can't be symbolicated. Set up .sentry-env, or pass ALLOW_NO_SENTRY=1." >&2
    exit 1
  fi
else
  echo "==> uploading source maps to Sentry"
  npx --yes @sentry/cli sourcemaps inject build/web
  npx --yes @sentry/cli sourcemaps upload \
    --org "${SENTRY_ORG:?set SENTRY_ORG for source map upload}" \
    --project "${SENTRY_PROJECT:?set SENTRY_PROJECT for source map upload}" \
    build/web
fi

# Don't publish Dart source to the CDN; Sentry already has the maps. The Debug
# IDs injected above live in the .js files, not the maps, so they survive this.
find build/web -name '*.map' -delete

npx --yes wrangler pages deploy build/web \
  --project-name 84beings-explore
