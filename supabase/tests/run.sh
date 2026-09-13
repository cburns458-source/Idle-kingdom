#!/usr/bin/env bash
#
# Applies the Bazaar migration to a scratch database and checks what it does.
#
# Not part of `npm test` or the Dart suites, because neither of those has a
# Postgres to talk to. Run it by hand when the exchange's SQL changes:
#
#   supabase/tests/run.sh
#
# Needs a local Postgres and a superuser to reach it with. Set PSQL to override
# how it connects, e.g. PSQL='psql -d postgres' when you are already a superuser.
set -euo pipefail

cd "$(dirname "$0")/../.."

PSQL=${PSQL:-"sudo -n -u postgres psql"}
DB=${DB:-bazaar_test}

run() { $PSQL -q -d "$DB" -v ON_ERROR_STOP=1 "$@"; }

$PSQL -q -c "drop database if exists $DB;" -c "create database $DB;"

run -f supabase/tests/00_project_stand_in.sql
run -f supabase/migrations/005_play_session.sql
run -f supabase/migrations/024_bazaar_market.sql

echo
echo "=== what the exchange does ==="
run -f supabase/tests/bazaar_market_test.sql

echo
echo "=== what a signed-in client may not do ==="
run -f supabase/tests/bazaar_permissions_test.sql

echo
echo "=== a placement still lands with a play session claimed ==="
run -c "set request.jwt.claims = '{\"role\":\"service_role\"}';" \
    -f supabase/tests/bazaar_play_session_test.sql

echo
echo "All Bazaar SQL checks passed."
