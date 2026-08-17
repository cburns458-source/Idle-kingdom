#!/usr/bin/env bash
# Cloudflare Workers/Pages build: install Flutter and emit app_flutter/build/web.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.0}"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"
OUT="$ROOT/app_flutter/build/web"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "SUPABASE_URL and SUPABASE_ANON_KEY must be set as Cloudflare environment variables." >&2
  echo "Without them the built site cannot sign in against your project." >&2
  exit 1
fi

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
flutter build web --release \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"

if [[ ! -f "$OUT/index.html" ]]; then
  echo "Flutter build finished but $OUT/index.html is missing." >&2
  ls -la "$ROOT/app_flutter/build" >&2 || true
  exit 1
fi

echo "Web build ready at $OUT"
ls -la "$OUT"
