#!/bin/bash
set -e

# Script khởi tạo người dùng ứng dụng crm_app với quyền tối thiểu
# Chạy trong /docker-entrypoint-initdb.d/ trước khi thực thi init.sql

APP_USER="${DB_USER:-crm_app}"
APP_PASS="${DB_PASSWORD}"

if [ -z "$APP_PASS" ]; then
    echo "[FATAL] DB_PASSWORD không được để trống khi khởi tạo crm_app." >&2
    exit 1
fi

echo "[DB-INIT] Đang tạo người dùng ứng dụng '$APP_USER'..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$APP_USER') THEN
            CREATE ROLE "$APP_USER" WITH LOGIN PASSWORD '$APP_PASS' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
        ELSE
            ALTER ROLE "$APP_USER" WITH LOGIN PASSWORD '$APP_PASS' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
        END IF;
    END
    \$\$;
EOSQL

echo "[DB-INIT] Tạo người dùng '$APP_USER' thành công với quyền NOSUPERUSER."
