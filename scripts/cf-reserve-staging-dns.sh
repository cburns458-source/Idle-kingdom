#!/usr/bin/env bash
# Reserve test.restoriaidle.com for the staging Worker without touching
# production records. Creates a proxied originless AAAA (100::), the same
# record type Cloudflare uses for Worker custom domains.
#
# Requires CLOUDFLARE_API_TOKEN with Zone DNS Edit on restoriaidle.com.
# Does not print the token.
set -euo pipefail

ZONE_ID="2965b4a468a4c56aafc36a25ce216671"
HOSTNAME="test.restoriaidle.com"
RECORD_TYPE="AAAA"
RECORD_CONTENT="100::"

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "CLOUDFLARE_API_TOKEN is unset." >&2
  exit 1
fi

auth_header() {
  printf 'Authorization: Bearer %s' "$CLOUDFLARE_API_TOKEN"
}

existing="$(
  curl -sS \
    -H "$(auth_header)" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${HOSTNAME}&type=${RECORD_TYPE}"
)"

python3 - "$existing" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
if not payload.get("success"):
    print("Failed to list DNS records:", payload.get("errors"), file=sys.stderr)
    sys.exit(1)
records = payload.get("result") or []
if records:
    record = records[0]
    print(
        f"Already present: {record.get('type')} {record.get('name')} "
        f"-> {record.get('content')} proxied={record.get('proxied')} "
        f"id={record.get('id')}"
    )
    sys.exit(0)
open("/tmp/cf-reserve-staging-dns.missing", "w").write("1")
PY

if [[ ! -f /tmp/cf-reserve-staging-dns.missing ]]; then
  exit 0
fi
rm -f /tmp/cf-reserve-staging-dns.missing

created="$(
  curl -sS -X POST \
    -H "$(auth_header)" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    --data "$(
      python3 - <<'PY'
import json
print(json.dumps({
    "type": "AAAA",
    "name": "test.restoriaidle.com",
    "content": "100::",
    "proxied": True,
    "comment": "Reserved for restoria-idlerpg-staging (do not point at production)",
}))
PY
    )"
)"

python3 - "$created" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
if not payload.get("success"):
    print("Failed to create DNS record:", payload.get("errors"), file=sys.stderr)
    sys.exit(1)
record = payload.get("result") or {}
print(
    f"Created: {record.get('type')} {record.get('name')} "
    f"-> {record.get('content')} proxied={record.get('proxied')} "
    f"id={record.get('id')}"
)
PY
