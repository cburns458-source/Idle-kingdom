#!/usr/bin/env bash
# One-time copy of one player's profile + cloud save from live into Restoria test.
#
# Does not copy auth.users. Create the same email on the test project first,
# then pass that test user's UUID as TEST_USER_ID (it will differ from live).
#
# Required env (never commit these):
#   LIVE_SERVICE_ROLE_KEY  — live project service_role
#   TEST_SERVICE_ROLE_KEY  — Restoria test service_role
#   LIVE_USER_ID           — auth user id on live
#   TEST_USER_ID           — auth user id on test
#
# Optional:
#   LIVE_URL  default https://fxcovagwwbptqaavispl.supabase.co
#   TEST_URL  default https://xlbwmxxtzrqjujvgqcuf.supabase.co
set -euo pipefail

LIVE_URL="${LIVE_URL:-https://fxcovagwwbptqaavispl.supabase.co}"
TEST_URL="${TEST_URL:-https://xlbwmxxtzrqjujvgqcuf.supabase.co}"

for name in LIVE_SERVICE_ROLE_KEY TEST_SERVICE_ROLE_KEY LIVE_USER_ID TEST_USER_ID; do
  if [[ -z "${!name:-}" ]]; then
    echo "$name is unset." >&2
    exit 1
  fi
done

fetch_row() {
  local url="$1" key="$2" table="$3" user_id="$4"
  curl -sS \
    -H "apikey: ${key}" \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "${url}/rest/v1/${table}?user_id=eq.${user_id}&select=*"
}

upsert_row() {
  local url="$1" key="$2" table="$3" body="$4"
  curl -sS -X POST \
    -H "apikey: ${key}" \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates,return=minimal" \
    -d "${body}" \
    "${url}/rest/v1/${table}"
}

live_profile="$(fetch_row "$LIVE_URL" "$LIVE_SERVICE_ROLE_KEY" profiles "$LIVE_USER_ID")"
live_save="$(fetch_row "$LIVE_URL" "$LIVE_SERVICE_ROLE_KEY" player_saves "$LIVE_USER_ID")"

python3 - "$live_profile" "$live_save" "$TEST_USER_ID" <<'PY'
import json, sys

profile_rows = json.loads(sys.argv[1])
save_rows = json.loads(sys.argv[2])
test_user_id = sys.argv[3]

if not isinstance(profile_rows, list) or not profile_rows:
    print("No live profile for LIVE_USER_ID.", file=sys.stderr)
    sys.exit(1)
if not isinstance(save_rows, list) or not save_rows:
    print("No live player_saves row for LIVE_USER_ID.", file=sys.stderr)
    sys.exit(1)

profile = dict(profile_rows[0])
save = dict(save_rows[0])
profile["user_id"] = test_user_id
# Test project has its own guilds; a live guild_id would violate the FK.
profile["guild_id"] = None
save["user_id"] = test_user_id

with open("/tmp/copy-save-profile.json", "w", encoding="utf-8") as fh:
    json.dump(profile, fh)
with open("/tmp/copy-save-player.json", "w", encoding="utf-8") as fh:
    json.dump(save, fh)
print(f"Prepared profile {profile.get('username')!r} and save version {save.get('save_version')}.")
PY

upsert_row "$TEST_URL" "$TEST_SERVICE_ROLE_KEY" profiles "$(cat /tmp/copy-save-profile.json)"
upsert_row "$TEST_URL" "$TEST_SERVICE_ROLE_KEY" player_saves "$(cat /tmp/copy-save-player.json)"
rm -f /tmp/copy-save-profile.json /tmp/copy-save-player.json
echo "Copied live save for $LIVE_USER_ID onto test user $TEST_USER_ID."
