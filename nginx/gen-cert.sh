#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/certs"
mkdir -p "${CERTS_DIR}"

LAN_IP="$1"
SAN="DNS:localhost,IP:127.0.0.1"

if [ -n "${LAN_IP}" ]; then
  SAN="${SAN},IP:${LAN_IP}"
  echo "[Certificate] Adding LAN IP to Subject Alternative Name: ${LAN_IP}"
fi

echo "[Certificate] Generating self-signed SSL certificate for CRM Nginx..."
echo "[Certificate] SAN: ${SAN}"

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout "${CERTS_DIR}/server.key" \
  -out "${CERTS_DIR}/server.crt" \
  -subj "/C=VN/ST=ThaiNguyen/L=ThaiNguyen/O=ICTU/OU=KTPM-K23B/CN=localhost" \
  -addext "subjectAltName=${SAN}"

# Thiết lập phân quyền an toàn
chmod 644 "${CERTS_DIR}/server.key"
chmod 644 "${CERTS_DIR}/server.crt"

echo "[Certificate] Certificate generated successfully:"
echo " - Private Key: ${CERTS_DIR}/server.key"
echo " - Certificate: ${CERTS_DIR}/server.crt"
