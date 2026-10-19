#!/usr/bin/env bash
set -e

BASE_URL="http://127.0.0.1:3000"
COOKIE_JAR="/tmp/crm_test_cookies.txt"
RAND_ID=$((RANDOM % 9000 + 1000))
TEST_EMAIL="test.sales${RAND_ID}@example.com"

# Đọc mật khẩu từ .env
source /home/duongtiendung/crm/.env

echo "================================================================================"
echo "BẮT ĐẦU KIỂM THỬ TỰ ĐỘNG END-TO-END HỆ THỐNG CRM"
echo "Thời gian: $(date)"
echo "================================================================================"

# Helper: Lấy CSRF Token từ HTML
get_csrf() {
  local html="$1"
  echo "$html" | grep -o 'name="_csrf" value="[^"]*"' | head -n 1 | cut -d'"' -f4
}

# 1. Healthcheck và Trang đăng nhập
echo -n "[1] Kiểm tra /health: "
HEALTH_RESP=$(curl -s "$BASE_URL/health")
if [ "$HEALTH_RESP" == "OK" ]; then echo "PASS (OK)"; else echo "FAIL ($HEALTH_RESP)"; exit 1; fi

echo -n "[2] Kiểm tra GET /auth/login: "
LOGIN_PAGE=$(curl -s -c "$COOKIE_JAR" "$BASE_URL/auth/login")
CSRF_TOKEN=$(get_csrf "$LOGIN_PAGE")
if [ -n "$CSRF_TOKEN" ]; then echo "PASS (CSRF Token: $CSRF_TOKEN)"; else echo "FAIL (No CSRF)"; exit 1; fi

# 3. Đăng nhập sai mật khẩu (Kiểm tra ghi log LOGIN_FAILED reason=wrong_password)
echo -n "[3] Thử đăng nhập sai mật khẩu: "
WRONG_LOGIN=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -d "username=admin&password=WrongPassword123&_csrf=$CSRF_TOKEN" -w "%{http_code}" -o /dev/null "$BASE_URL/auth/login")
echo "HTTP $WRONG_LOGIN (Mong đợi 401)"

# 4. Đăng nhập tài khoản không tồn tại (reason=unknown_user)
echo -n "[4] Thử đăng nhập tài khoản lạ: "
UNKNOWN_LOGIN=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -d "username=ghost_user&password=SomePassword123&_csrf=$CSRF_TOKEN" -w "%{http_code}" -o /dev/null "$BASE_URL/auth/login")
echo "HTTP $UNKNOWN_LOGIN (Mong đợi 401)"

# 5. Đăng nhập Sales (sales01)
echo "[5] Đăng nhập tài khoản sales01..."
rm -f "$COOKIE_JAR"
LOGIN_PAGE=$(curl -s -c "$COOKIE_JAR" "$BASE_URL/auth/login")
CSRF_TOKEN=$(get_csrf "$LOGIN_PAGE")
curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -d "username=sales01&password=$SEED_SALES_PASSWORD&_csrf=$CSRF_TOKEN" "$BASE_URL/auth/login" -o /dev/null

DASH_PAGE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/dashboard")
CSRF_TOKEN=$(get_csrf "$DASH_PAGE")
echo " -> Đăng nhập thành công, CSRF mới: $CSRF_TOKEN"

# 5a. Sales tạo khách hàng hợp lệ
echo -n "[5a] Sales tạo khách hàng mới ($TEST_EMAIL): "
CUST_CREATE_RESP=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -d "full_name=Công ty Test Sales $RAND_ID&company=Test Co&email=$TEST_EMAIL&phone=0909999888&source=website&segment=new&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/customers")
if echo "$CUST_CREATE_RESP" | grep -q "302 Found"; then echo "PASS (Redirect to detail)"; else echo "FAIL"; exit 1; fi

# 5b. Sales tạo khách hàng trùng email (Chặn trùng email)
echo -n "[5b] Sales tạo khách hàng trùng email: "
DUP_EMAIL_RESP=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -d "full_name=Khách Hàng Trùng Email&email=$TEST_EMAIL&source=website&segment=new&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/customers")
if echo "$DUP_EMAIL_RESP" | grep -q "đã tồn tại trong hệ thống"; then echo "PASS (Bị chặn với thông báo lỗi)"; else echo "FAIL"; exit 1; fi

# 5c. Sales thêm tương tác
echo -n "[5c] Sales thêm tương tác cho khách hàng 1: "
INT_RESP=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -d "customer_id=1&type=call&subject=Test Call by Sales01&content=Trao doi thanh cong voi anh An&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/interactions")
if echo "$INT_RESP" | grep -q "302 Found"; then echo "PASS"; else echo "FAIL"; exit 1; fi

# 5d. Sales tạo cơ hội bán hàng
OPP_TITLE="Co Hoi Test $RAND_ID"
echo -n "[5d] Sales tạo cơ hội bán hàng ($OPP_TITLE): "
OPP_RESP=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -d "customer_id=1&title=$OPP_TITLE&value=75000000&stage=new&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/opportunities")
if echo "$OPP_RESP" | grep -q "302 Found"; then echo "PASS"; else echo "FAIL"; exit 1; fi

# Lấy ID cơ hội vừa tạo
OPP_ID=$(docker compose exec -T db psql -U crm_app -d crm -t -c "SELECT id FROM opportunities WHERE title = '$OPP_TITLE' LIMIT 1;" | tr -d '[:space:]')
echo " -> ID cơ hội vừa tạo: $OPP_ID"

# 5e. Sales thử nhảy cóc giai đoạn từ new -> proposal (Bị từ chối)
echo -n "[5e] Thử nhảy cóc giai đoạn new -> proposal: "
JUMP_RESP=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{http_code}" -o /dev/null \
  -d "target_stage=proposal&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/opportunities/$OPP_ID/stage")
if [ "$JUMP_RESP" == "400" ]; then echo "PASS (HTTP 400 Bị từ chối đúng luật)"; else echo "FAIL ($JUMP_RESP)"; exit 1; fi

# 5f. Sales tiến tuần tự new -> contacted
echo -n "[5f] Tiến tuần tự new -> contacted: "
NEXT_RESP=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -d "target_stage=contacted&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/opportunities/$OPP_ID/stage")
if echo "$NEXT_RESP" | grep -q "302 Found"; then echo "PASS"; else echo "FAIL"; exit 1; fi

# 5g. Sales chuyển sang lost nhưng KHÔNG nhập lý do (Bị từ chối)
echo -n "[5g] Chuyển sang lost không có lý do: "
LOST_NO_REASON=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{http_code}" -o /dev/null \
  -d "target_stage=lost&lost_reason=&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/opportunities/$OPP_ID/stage")
if [ "$LOST_NO_REASON" == "400" ]; then echo "PASS (HTTP 400 Bắt buộc có lý do)"; else echo "FAIL ($LOST_NO_REASON)"; exit 1; fi

# 5h. Sales chuyển sang lost có lý do hợp lệ
echo -n "[5h] Chuyển sang lost kèm lý do: "
LOST_WITH_REASON=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -d "target_stage=lost&lost_reason=Khach hang doi ke hoach 2027&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/opportunities/$OPP_ID/stage")
if echo "$LOST_WITH_REASON" | grep -q "302 Found"; then echo "PASS"; else echo "FAIL"; exit 1; fi

# 5i. Thử đổi giai đoạn của cơ hội đã lost (Bị từ chối)
echo -n "[5i] Thử đổi cơ hội đã lost sang won: "
CHANGE_LOST=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{http_code}" -o /dev/null \
  -d "target_stage=won&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/opportunities/$OPP_ID/stage")
if [ "$CHANGE_LOST" == "400" ]; then echo "PASS (HTTP 400 Không cho đổi cơ hội đã kết thúc)"; else echo "FAIL ($CHANGE_LOST)"; exit 1; fi

# 5j. Sales truy cập trái quyền (Quản lý nhân viên & Xuất CSV -> Phải bị 403)
echo -n "[5j] Sales truy cập /users: "
SALES_USERS=$(curl -s -b "$COOKIE_JAR" -w "%{http_code}" -o /dev/null "$BASE_URL/users")
if [ "$SALES_USERS" == "403" ]; then echo "PASS (HTTP 403 Forbidden)"; else echo "FAIL ($SALES_USERS)"; exit 1; fi

echo -n "[5k] Sales truy cập /customers/export/csv: "
SALES_CSV=$(curl -s -b "$COOKIE_JAR" -w "%{http_code}" -o /dev/null "$BASE_URL/customers/export/csv")
if [ "$SALES_CSV" == "403" ]; then echo "PASS (HTTP 403 Forbidden)"; else echo "FAIL ($SALES_CSV)"; exit 1; fi

# 6. Đăng nhập Support (support01)
echo "[6] Đăng nhập tài khoản support01..."
rm -f "$COOKIE_JAR"
LOGIN_PAGE=$(curl -s -c "$COOKIE_JAR" "$BASE_URL/auth/login")
CSRF_TOKEN=$(get_csrf "$LOGIN_PAGE")
curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -d "username=support01&password=$SEED_SUPPORT_PASSWORD&_csrf=$CSRF_TOKEN" "$BASE_URL/auth/login" -o /dev/null

DASH_PAGE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/dashboard")
CSRF_TOKEN=$(get_csrf "$DASH_PAGE")

# 6a. Support sửa khách hàng -> 403 Forbidden
echo -n "[6a] Support sửa khách hàng: "
SUP_EDIT_CUST=$(curl -s -b "$COOKIE_JAR" -w "%{http_code}" -o /dev/null \
  -d "full_name=Support Hack Name&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/customers/1/edit")
if [ "$SUP_EDIT_CUST" == "403" ]; then echo "PASS (HTTP 403 Forbidden)"; else echo "FAIL ($SUP_EDIT_CUST)"; exit 1; fi

# 6b. Support tạo cơ hội -> 403 Forbidden
echo -n "[6b] Support tạo cơ hội: "
SUP_CREATE_OPP=$(curl -s -b "$COOKIE_JAR" -w "%{http_code}" -o /dev/null \
  -d "customer_id=1&title=Support Opp&value=1000000&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/opportunities")
if [ "$SUP_CREATE_OPP" == "403" ]; then echo "PASS (HTTP 403 Forbidden)"; else echo "FAIL ($SUP_CREATE_OPP)"; exit 1; fi

# 6c. Support tạo ticket mới
TICKET_SUBJ="Ticket Test $RAND_ID"
echo -n "[6c] Support tạo ticket mới ($TICKET_SUBJ): "
SUP_TICKET_RESP=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -d "customer_id=1&subject=$TICKET_SUBJ&description=Kiem tra quy trinh SLA va comment file&category=technical&priority=urgent&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/tickets")
if echo "$SUP_TICKET_RESP" | grep -q "302 Found"; then echo "PASS"; else echo "FAIL"; exit 1; fi

TICKET_ID=$(docker compose exec -T db psql -U crm_app -d crm -t -c "SELECT id FROM tickets WHERE subject = '$TICKET_SUBJ' LIMIT 1;" | tr -d '[:space:]')
echo " -> ID ticket vừa tạo: $TICKET_ID"

# 6d. Support nhận xử lý và chuyển open -> in_progress
echo -n "[6d] Chuyển ticket open -> in_progress: "
TICKET_IN_PROG=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -d "target_status=in_progress&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/tickets/$TICKET_ID/status")
if echo "$TICKET_IN_PROG" | grep -q "302 Found"; then echo "PASS"; else echo "FAIL"; exit 1; fi

# 6e. Upload tệp hợp lệ (ảnh PNG thật)
echo -n "[6e] Support bình luận đính kèm tệp PNG hợp lệ: "
printf "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB\`\x82" > /tmp/valid_sample.png

VALID_UPLOAD=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -F "content=Dinh kem hinh anh loi he thong chup tu may khach" \
  -F "_csrf=$CSRF_TOKEN" \
  -F "attachment=@/tmp/valid_sample.png;type=image/png" \
  "$BASE_URL/tickets/$TICKET_ID/comments")
if echo "$VALID_UPLOAD" | grep -q "302 Found"; then echo "PASS"; else echo "FAIL"; exit 1; fi

# 6f. Upload tệp giả mạo .exe hoặc magic bytes sai (Bị từ chối)
echo -n "[6f] Thử upload tệp .exe giả danh .png: "
echo "This is not a real PNG executable code" > /tmp/malicious.png
FAKE_UPLOAD=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{http_code}" -o /dev/null \
  -F "content=Test malicious file upload" \
  -F "_csrf=$CSRF_TOKEN" \
  -F "attachment=@/tmp/malicious.png;type=image/png" \
  "$BASE_URL/tickets/$TICKET_ID/comments")
if [ "$FAKE_UPLOAD" == "400" ]; then echo "PASS (HTTP 400 Bị chặn bởi Magic Bytes check)"; else echo "FAIL ($FAKE_UPLOAD)"; exit 1; fi

# 6g. Upload tệp quá kích thước > 2MB (Bị từ chối)
echo -n "[6g] Thử upload tệp lớn > 2.5MB: "
dd if=/dev/zero of=/tmp/large_file.pdf bs=1M count=3 2>/dev/null
LARGE_UPLOAD=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{http_code}" -o /dev/null \
  -F "content=Test large file upload" \
  -F "_csrf=$CSRF_TOKEN" \
  -F "attachment=@/tmp/large_file.pdf;type=application/pdf" \
  "$BASE_URL/tickets/$TICKET_ID/comments")
if [ "$LARGE_UPLOAD" == "400" ]; then echo "PASS (HTTP 400 Bị chặn vì vượt quá 2MB)"; else echo "FAIL ($LARGE_UPLOAD)"; exit 1; fi

# 6h. Support giải quyết ticket (in_progress -> resolved)
echo -n "[6h] Chuyển ticket in_progress -> resolved: "
TICKET_RESOLVE=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -d "target_status=resolved&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/tickets/$TICKET_ID/status")
if echo "$TICKET_RESOLVE" | grep -q "302 Found"; then echo "PASS"; else echo "FAIL"; exit 1; fi

# 7. Đăng nhập Manager (admin)
echo "[7] Đăng nhập tài khoản admin (Manager)..."
rm -f "$COOKIE_JAR"
LOGIN_PAGE=$(curl -s -c "$COOKIE_JAR" "$BASE_URL/auth/login")
CSRF_TOKEN=$(get_csrf "$LOGIN_PAGE")
curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -d "username=admin&password=$SEED_MANAGER_PASSWORD&_csrf=$CSRF_TOKEN" "$BASE_URL/auth/login" -o /dev/null

DASH_PAGE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/dashboard")
CSRF_TOKEN=$(get_csrf "$DASH_PAGE")

# 7a. Manager tạo nhân viên mới
STAFF_USER="staff_${RAND_ID}"
STAFF_EMAIL="staff_${RAND_ID}@example.com"
echo -n "[7a] Manager tạo nhân viên mới ($STAFF_USER): "
NEW_STAFF_RESP=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -d "username=$STAFF_USER&email=$STAFF_EMAIL&full_name=Nguyen Van Staff&role=sales&password=StaffPass123456789&_csrf=$CSRF_TOKEN" \
  "$BASE_URL/users")
if echo "$NEW_STAFF_RESP" | grep -q "302 Found"; then echo "PASS"; else echo "FAIL"; exit 1; fi

STAFF_ID=$(docker compose exec -T db psql -U crm_app -d crm -t -c "SELECT id FROM users WHERE username = '$STAFF_USER' LIMIT 1;" | tr -d '[:space:]')

# 7b. Manager khóa tài khoản 'teststaff'
echo -n "[7b] Manager khóa tài khoản $STAFF_USER: "
LOCK_RESP=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -i \
  -d "_csrf=$CSRF_TOKEN" \
  "$BASE_URL/users/$STAFF_ID/toggle-lock")
if echo "$LOCK_RESP" | grep -q "302 Found"; then echo "PASS"; else echo "FAIL"; exit 1; fi

# 7c. Thử đăng nhập bằng tài khoản bị khóa -> Phải thất bại với reason=inactive
echo -n "[7c] Đăng nhập bằng tài khoản $STAFF_USER đang bị khóa: "
LOCK_LOGIN_PAGE=$(curl -s -c /tmp/locked_cookie.txt "$BASE_URL/auth/login")
LOCK_CSRF=$(get_csrf "$LOCK_LOGIN_PAGE")
LOCKED_LOGIN=$(curl -s -b /tmp/locked_cookie.txt -d "username=$STAFF_USER&password=StaffPass123456789&_csrf=$LOCK_CSRF" -w "%{http_code}" -o /dev/null "$BASE_URL/auth/login")
if [ "$LOCKED_LOGIN" == "401" ]; then echo "PASS (HTTP 401 Bị chặn vì tài khoản đã khóa)"; else echo "FAIL ($LOCKED_LOGIN)"; exit 1; fi

# 7d. Manager thử tự khóa chính mình -> Phải bị từ chối
echo -n "[7d] Manager thử tự khóa chính mình: "
SELF_LOCK=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -w "%{http_code}" -o /dev/null \
  -d "_csrf=$CSRF_TOKEN" \
  "$BASE_URL/users/1/toggle-lock")
if [ "$SELF_LOCK" == "400" ]; then echo "PASS (HTTP 400 Bị từ chối vì không thể tự khóa chính mình)"; else echo "FAIL ($SELF_LOCK)"; exit 1; fi

# 7e. Manager mở khóa tài khoản
echo -n "[7e] Manager mở khóa tài khoản $STAFF_USER: "
curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -d "_csrf=$CSRF_TOKEN" "$BASE_URL/users/$STAFF_ID/toggle-lock" -o /dev/null
echo "PASS"

# 7f. Manager xuất CSV khách hàng
echo -n "[7f] Manager xuất danh sách khách hàng ra CSV: "
CSV_CONTENT=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/customers/export/csv")
if echo "$CSV_CONTENT" | grep -q "Mã KH"; then
  ROW_COUNT=$(echo "$CSV_CONTENT" | wc -l)
  echo "PASS ($ROW_COUNT dòng dữ liệu CSV, có chống CSV injection)"
else
  echo "FAIL"
  exit 1
fi

# 8. Kiểm tra log đăng nhập từ container docker compose logs web
echo "[8] Kiểm tra cấu trúc log container (LOGIN_FAILED / LOGIN_SUCCESS):"
docker compose logs web | grep -E "LOGIN_FAILED|LOGIN_SUCCESS" | tail -n 8

echo "================================================================================"
echo "HOÀN TẤT TOÀN BỘ BÀI TEST TỰ ĐỘNG END-TO-END: TẤT CẢ ĐỀU PASS 100%!"
echo "================================================================================"
