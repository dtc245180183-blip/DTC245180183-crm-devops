#!/usr/bin/env bash
set -e

# Đọc user và password exporter từ biến môi trường container db
EXPORTER_USER="${POSTGRES_EXPORTER_USER:-exporter}"
EXPORTER_PASSWORD="${POSTGRES_EXPORTER_PASSWORD}"

if [ -z "$EXPORTER_PASSWORD" ]; then
  echo "[10-exporter.sh] WARNING: POSTGRES_EXPORTER_PASSWORD is empty. Skipping exporter role configuration."
  exit 0
fi

# Dùng psql với tham số hóa an toàn (-v + :'biến'), không để lộ password trong process list hay script
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v exp_user="$EXPORTER_USER" \
  -v exp_pass="$EXPORTER_PASSWORD" <<'EOSQL'
SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'exp_user')
  THEN format('ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE;', :'exp_user', :'exp_pass')
  ELSE format('CREATE ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE;', :'exp_user', :'exp_pass')
END \gexec

SELECT format('GRANT pg_monitor TO %I;', :'exp_user') \gexec
EOSQL

echo "[10-exporter.sh] Configured role $EXPORTER_USER with pg_monitor privileges successfully."
