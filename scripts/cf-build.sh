#!/usr/bin/env bash
# Cloudflare Workers/Pages build: install Flutter and emit app_flutter/build/web.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.0}"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"
OUT="$ROOT/app_flutter/build/web"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter $FLUTTER_VERSION into $FLUTTER_HOME"
  rm -rf "$FLUTTER_HOME"
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  export PATH="$FLUTTER_HOME/bin:$PATH"
fi

flutter config --no-analytics
flutter precache --web
flutter --version

cd "$ROOT/app_flutter"
flutter pub get

if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  flutter build web --release --pwa-strategy=none \
    --dart-define="SUPABASE_URL=$SUPABASE_URL" \
    --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
else
  echo "SUPABASE_URL and SUPABASE_ANON_KEY are unset; building a local-only preview bundle." >&2
  flutter build web --release --pwa-strategy=none
fi

if [[ ! -f "$OUT/index.html" ]]; then
  echo "Flutter build finished but $OUT/index.html is missing." >&2
  ls -la "$ROOT/app_flutter/build" >&2 || true
  exit 1
fi

# `pwa-strategy=none` must not leave testers on the old caching worker. Put
# the unregistering script at the same URL the previous build registered.
cp "$ROOT/app_flutter/web/flutter_service_worker.js" "$OUT/flutter_service_worker.js"
cp "$ROOT/app_flutter/web/_headers" "$OUT/_headers"

echo "Web build ready at $OUT"
ls -la "$OUT"
