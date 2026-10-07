#!/usr/bin/env bash
# Bundle src/game rules into the game edge function.
#
# supabase/functions cannot import ../../../src/game at deploy time, so
# the deploy job copies the content database and emits one JS file that
# the function imports. Run this before `deno check` in that directory.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
shared="$root/supabase/functions/_shared"
mkdir -p "$shared"
cp "$root/content/data/game-database.json" "$shared/game-database.json"
deno bundle --no-lock --platform=deno --output="$shared/game_rules.js" "$root/src/game/server/prototype.ts"
echo "wrote $shared/game_rules.js and $shared/game-database.json"
