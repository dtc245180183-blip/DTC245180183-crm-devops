# Hướng Dẫn Truy Vấn Log Bằng LogQL (Loki)

Tài liệu tổng hợp các truy vấn LogQL chuẩn hóa trên hệ thống giám sát tập trung Grafana Loki của dự án CRM.

## 1. Cấu Trúc Nhãn (Labels) Trong Loki
Promtail được cấu hình thu thập log từ Docker Engine và gắn nhãn theo các quy tắc sau:
- `job`: Định danh loại dịch vụ giám sát:
  - `nginx`: Máy chủ Web / Reverse Proxy Nginx.
  - `webapp`: Ứng dụng Web CRM (Node.js/Express).
  - `postgres`: Hệ quản trị CSDL PostgreSQL.
  - `other`: Các dịch vụ phụ trợ khác.
- `container`: Tên container Docker (`crm-nginx-1`, `crm-web-1`, `crm-db-1`, ...).
- `compose_service`: Tên dịch vụ trong `docker-compose.yml` (`nginx`, `web`, `db`, ...).
- `status`: Mã phản hồi HTTP (được trích xuất từ access log của Nginx thông qua pipeline stage regex, tránh high-cardinality cho IP).

---

## 2. Danh Mục 5 Truy Vấn LogQL Chuẩn Đã Kiểm Chứng Thực Tế

### Truy Vấn Q1: Lọc lỗi máy chủ HTTP 5xx từ Nginx
- **Mục đích**: Phát hiện các lỗi nghiêm trọng phía máy chủ web (500 Internal Server Error, 502 Bad Gateway, 504 Gateway Timeout).
- **Cú pháp LogQL**:
  ```logql
  {job="nginx"} |~ "\" 5[0-9]{2} "
  ```
- **Cú pháp thay thế dựa trên nhãn parsed**:
  ```logql
  {job="nginx", status=~"5.."}
  ```
- **Dữ liệu thực tế ghi nhận**:
  ```text
  172.23.0.1 - - [20/Oct/2026:06:22:48 +0000] "GET / HTTP/1.1" 502 150 "-" "curl/8.18.0" "-" rt=22.514
  ```

---

### Truy Vấn Q2: Lọc các dòng log chứa lỗi hoặc ngoại lệ từ ứng dụng Web CRM
- **Mục đích**: Phát hiện các exception, lỗi ứng dụng, thất bại xác thực hoặc kết nối trong ứng dụng Node.js.
- **Cú pháp LogQL**:
  ```logql
  {job="webapp"} |~ "(?i)(error|exception|failed)"
  ```
- **Dữ liệu thực tế ghi nhận**:
  ```text
  LOGIN_FAILED ip=172.23.0.1 user=admin reason=wrong_password
  ```

---

### Truy Vấn Q3: Lọc sự kiện đăng nhập thất bại (LOGIN_FAILED)
- **Mục đích**: Giám sát an ninh, phát hiện hành vi nhập sai mật khẩu hoặc tấn công dò mật khẩu.
- **Cú pháp LogQL**:
  ```logql
  {job="webapp"} |= "LOGIN_FAILED"
  ```
- **Trích xuất trường bằng LogQL Pattern**:
  ```logql
  {job="webapp"} |= "LOGIN_FAILED" | pattern "LOGIN_FAILED ip=<src_ip> user=<target_user> reason=<fail_reason>"
  ```
- **Dữ liệu thực tế ghi nhận**:
  ```text
  LOGIN_FAILED ip=172.23.0.1 user=admin reason=wrong_password
  ```

---

### Truy Vấn Q4: Đếm tổng số lần đăng nhập thất bại theo thời gian (Metric Query Alert Rule 1)
- **Mục đích**: Chuyển đổi log streams thành time-series metrics để vẽ biểu đồ và kích hoạt cảnh báo khi số lần vi phạm vượt ngưỡng (> 3 trong 1 phút).
- **Cú pháp LogQL**:
  ```logql
  sum(count_over_time({job="webapp"} |= "LOGIN_FAILED" [1m]))
  ```
- **Dữ liệu thực tế ghi nhận**:
  Trong đợt mô phỏng tấn công, giá trị đạt `4` trong 1 phút (kích hoạt cảnh báo mức `critical`).

---

### Truy Vấn Q5: Đếm số yêu cầu đăng nhập bị Nginx từ chối với mã 429 (Metric Query Alert Rule 2)
- **Mục đích**: Giám sát hiệu quả của cơ chế Rate Limiting tại Nginx và phát hiện các đợt tấn công tần suất cao đang bị chặn ở tầng biên (> 5 trong 1 phút).
- **Cú pháp LogQL**:
  ```logql
  sum(count_over_time({job="nginx", status="429"} [1m]))
  ```
- **Dữ liệu thực tế ghi nhận**:
  Trong đợt mô phỏng tấn công, giá trị đạt `16` trong 1 phút (kích hoạt cảnh báo mức `warning`).

---

## 3. Cách Sử Dụng Trên Giao Diện Grafana Explore
1. Truy cập `https://localhost/grafana/explore`.
2. Chọn nguồn dữ liệu **Loki**.
3. Dán một trong các câu truy vấn trên vào khung soạn thảo LogQL.
4. Chọn khoảng thời gian khảo sát (ví dụ: `Last 15 minutes` hoặc `Last 1 hour`).
5. Bấm **Run query** để xem log stream hoặc biểu đồ tần suất.
