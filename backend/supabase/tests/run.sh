#!/usr/bin/env bash
# Applies every migration to a throwaway Postgres and runs the SQL checks.
# Usage: backend/supabase/tests/run.sh   (needs Docker, or set DATABASE_URL to an empty database)
set -euo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DATABASE_URL:-}" ]]; then
  name="blink-test-$$"
  docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=test -p 54329:5432 pgvector/pgvector:pg17 >/dev/null
  trap 'docker stop "$name" >/dev/null' EXIT
  DATABASE_URL="postgresql://postgres:test@localhost:54329/postgres"
  until psql "$DATABASE_URL" -qc 'select 1' >/dev/null 2>&1; do sleep 1; done
fi
run() { psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -f "$1"; }
run "$dir/tests/bootstrap.sql"
for f in "$dir"/migrations/*.sql; do run "$f"; done
run "$dir/tests/rls.sql"
