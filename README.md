# Hệ thống CRM Chăm sóc Khách hàng (Customer Relationship Management)

> **Môn học:** Triển khai và Quản trị Hệ thống Phần mềm  
> **Sinh viên thực hiện:** Dương Tiến Dũng  
> **Mã số sinh viên (MSSV):** DTC245180183  
> **Lớp:** KTPM K23B  
> **Email:** DTC245180183@ictu.edu.vn  
> **Repository GitHub:** `DTC245180183-crm-devops`

---

## 1. Giới thiệu Đề tài
Hệ thống **CRM Chăm sóc Khách hàng** cung cấp giải pháp chuyển đổi số toàn diện cho doanh nghiệp trong việc quản lý quan hệ khách hàng, tối ưu hóa quy trình bán hàng và chăm sóc sau bán hàng:
- **Hồ sơ khách hàng & Phân khúc**: Phân loại theo phân khúc (`new`, `regular`, `vip`, `inactive`) và nguồn tiếp cận (`website`, `referral`, `facebook`, `event`, `cold_call`, `other`).
- **Lịch sử tương tác (Timeline)**: Ghi nhận đa kênh các cuộc gọi, email, cuộc họp, ghi chú nội bộ và tin nhắn trao đổi.
- **Cơ hội bán hàng (Sales Pipeline Kanban)**: Quản lý các giai đoạn bán hàng theo chu trình chặt chẽ: `Mới tạo` $\rightarrow$ `Đã liên hệ` $\rightarrow$ `Đủ điều kiện` $\rightarrow$ `Gửi đề xuất` $\rightarrow$ `Thành công (Won)` / `Thất bại (Lost)`.
- **Phiếu hỗ trợ & khiếu nại (Support Tickets) có SLA**: Cam kết thời gian xử lý theo mức độ ưu tiên: Khẩn cấp (4 giờ), Cao (8 giờ), Trung bình (24 giờ), Thấp (72 giờ). Tự động cảnh báo nhãn "Quá hạn SLA". Hỗ trợ trao đổi bình luận và đính kèm tệp tài liệu an toàn.
- **Lịch nhắc việc (Tasks)**: Quản lý công việc cá nhân, lọc việc hôm nay và việc quá hạn, phân công công việc từ cấp quản lý.
- **Dashboard KPI**: Báo cáo tổng quan dành cho Quản lý (doanh thu chốt, tỷ lệ thắng deal, ticket quá hạn SLA, thời gian xử lý trung bình) và dashboard cá nhân cho nhân viên.

### Phân quyền người dùng theo vai trò (RBAC)
- **`sales` (Kinh doanh)**: Xem khách hàng; tạo/sửa thông tin khách hàng; ghi nhận tương tác; quản lý pipeline cơ hội; tạo ticket; quản lý nhắc việc cá nhân.
- **`support` (Chăm sóc khách hàng)**: Xem khách hàng (chỉ đọc hồ sơ); ghi nhận tương tác; tiếp nhận và đổi trạng thái ticket theo quy trình; đính kèm tệp; xem cơ hội; quản lý nhắc việc cá nhân.
- **`manager` (Quản lý)**: Toàn quyền quản trị; lưu trữ/khôi phục khách hàng; phân công ticket và nhắc việc; quản trị tài khoản nhân sự (tạo, sửa, khóa/mở khóa tài khoản – có cơ chế chống tự khóa chính mình); xem toàn bộ dashboard KPI; xuất dữ liệu khách hàng ra CSV có cơ chế chống CSV Injection.

---

## 2. Kiến trúc Hạ tầng Hệ thống
Hệ thống được đóng gói và vận hành đồng bộ bằng Docker Compose (`name: crm`):
- **Reverse Proxy**: Nginx Unprivileged (`nginxinc/nginx-unprivileged:1.27.4-alpine`) chạy non-root, lắng nghe cổng 80 (HTTP redirect 301 sang HTTPS) và cổng 443 (HTTPS với chứng chỉ số SSL tự ký và bộ Security Headers chuẩn OWASP).
- **Ứng dụng Web**: Node.js 20 LTS (`node:20.18.3-alpine`), Express, EJS Server-Side Rendering, CSS thuần (không framework nặng).
- **Cơ sở dữ liệu**: PostgreSQL 16 Alpine (`postgres:16.8-alpine`), lưu trữ dữ liệu bền vững qua Docker Named Volume `db_data`. Cổng CSDL được bảo vệ nội bộ, không mở ra ngoài host.
- **Công cụ Quản trị CSDL**: pgAdmin 4 v9.1 (`dpage/pgadmin4:9.1`), phục vụ trực tiếp qua đường dẫn con `https://localhost/pgadmin/`.
- **Hệ thống Giám sát Metrics (Prometheus + Grafana + Exporters)**:
  - **Prometheus** (`prom/prometheus:v3.2.1`): Thu thập và lưu trữ time-series metrics định kỳ 15s, retention 7 ngày qua volume `prometheus_data`.
  - **Grafana** (`grafana/grafana:11.5.2`): Trực quan hóa dashboard giám sát, phục vụ an toàn qua HTTPS đường dẫn con `https://localhost/grafana/` (có hỗ trợ WebSocket Upgrade cho Grafana Live).
  - **cAdvisor** (`gcr.io/cadvisor/cadvisor:v0.49.2`): Thu thập chỉ số tài nguyên container (CPU, RAM, Network I/O).
  - **Nginx Prometheus Exporter** (`nginx/nginx-prometheus-exporter:1.4.1`): Thu thập metrics máy chủ web từ endpoint nội bộ `http://nginx:8081/nginx_status`.
  - **PostgreSQL Exporter** (`prometheuscommunity/postgres-exporter:v0.16.0`): Thu thập số liệu hiệu năng DB qua tài khoản quyền tối thiểu `exporter` (role `pg_monitor`).

---

## 3. Hướng dẫn Cài đặt & Vận hành

### Yêu cầu tiên quyết
- Hệ điều hành: Windows 10/11 có WSL2 (Ubuntu) và Docker Desktop (kích hoạt WSL Integration).
- Dung lượng RAM cấp phát cho Docker $\ge$ 5 GB, ổ đĩa khả dụng $\ge$ 15 GB.

### Các bước khởi chạy hệ thống
1. **Clone mã nguồn dự án**:
   ```bash
   git clone https://github.com/DTC245180183/DTC245180183-crm-devops.git ~/crm
   cd ~/crm
   ```

2. **Cấu hình biến môi trường**:
   Sao chép tệp mẫu và chỉnh sửa các secret theo nhu cầu:
   ```bash
   cp .env.example .env
   ```
   *(Các mật khẩu mạnh ngẫu nhiên được lưu trữ bảo mật trong `.env` và được `.gitignore` bảo vệ tuyệt đối).*

3. **Sinh chứng chỉ SSL tự ký cho Nginx**:
   Chạy script tự động sinh khóa RSA 2048-bit và chứng chỉ x509 thời hạn 365 ngày kèm SAN `DNS:localhost,IP:127.0.0.1`:
   ```bash
   bash nginx/gen-cert.sh
   ```
   *(Tùy chọn: có thể truyền IP LAN máy host làm tham số: `bash nginx/gen-cert.sh 192.168.1.100`)*.

4. **Khởi động toàn bộ dịch vụ bằng Docker Compose**:
   ```bash
   docker compose up -d --build
   ```

5. **Xử lý tài khoản exporter khi volume CSDL đã tồn tại sẵn**:
   Trong trường hợp volume `db_data` đã được khởi tạo trước đó (tệp `init.sql` chỉ chạy lần đầu), chạy lệnh sau để bảo đảm tài khoản `exporter` được khởi tạo an toàn:
   ```bash
   source .env
   docker compose exec -T db psql -U crm_app -d crm -c "DO \$\$
   BEGIN
     IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'exporter') THEN
       CREATE USER exporter WITH PASSWORD '${POSTGRES_EXPORTER_PASSWORD}';
     ELSE
       ALTER USER exporter WITH PASSWORD '${POSTGRES_EXPORTER_PASSWORD}';
     END IF;
     GRANT pg_monitor TO exporter;
   END
   \$\$;"
   ```

---

## 4. Điểm Truy Cập và Danh Mục Dịch Vụ
Toàn bộ truy cập từ bên ngoài đều đi qua cổng bảo mật của Nginx (Reverse Proxy):

| Dịch vụ | Giao thức / Cổng | URL truy cập | Mô tả |
| :--- | :--- | :--- | :--- |
| **CRM Web Application** | HTTPS (443) | `https://localhost` | Hệ thống chính quản lý khách hàng |
| **pgAdmin 4 Web UI** | HTTPS (443) | `https://localhost/pgadmin/` | Quản trị CSDL PostgreSQL qua giao diện web |
| **Grafana Monitoring UI** | HTTPS (443) | `https://localhost/grafana/` | Bảng điều khiển giám sát hệ thống |
| **HTTP Redirect** | HTTP (80) | `http://localhost` | Tự động chuyển hướng 301 sang HTTPS |

> **Lưu ý về Chứng chỉ SSL tự ký:**  
> Khi truy cập từ trình duyệt Windows, trình duyệt sẽ hiển thị cảnh báo chứng chỉ tự ký (`NET::ERR_CERT_AUTHORITY_INVALID`). Nhấn **Nâng cao (Advanced)** $\rightarrow$ **Tiếp tục truy cập localhost (Proceed to localhost)** để vào hệ thống. Tuyệt đối không cài chứng chỉ vào Trusted Root Store của Windows khi chưa có yêu cầu.

### Hướng dẫn kiểm tra Prometheus Targets mà không mở cổng công khai
Theo chuẩn an toàn thông tin, cổng 9090 của Prometheus không được publish trực tiếp ra ngoài. Khi cần truy cập giao diện Targets để chụp ảnh minh chứng:
1. Tạo tệp `docker-compose.override.yml` (đã được cấu hình trong `.gitignore`, không commit vào Git):
   ```yaml
   services:
     prometheus:
       ports:
         - "127.0.0.1:9090:9090"
   ```
2. Cập nhật dịch vụ:
   ```bash
   docker compose up -d prometheus
   ```
3. Mở trình duyệt truy cập `http://localhost:9090/targets` để xem trạng thái tất cả các target (UP).
4. Sau khi chụp ảnh xong, xóa tệp override và gỡ cổng:
   ```bash
   rm -f docker-compose.override.yml
   docker compose up -d
   ```

---

## 5. Danh Mục Dashboard Giám Sát (Grafana Provisioning)
Các dashboard được tự động nạp từ thư mục `grafana/dashboards/` vào folder **"CRM Monitoring"**:
1. **CRM - Containers** (`crm-containers`):
   - Memory Usage (RAM) theo container (`container_memory_usage_bytes`).
   - CPU Usage Rate theo container (`rate(container_cpu_usage_seconds_total[1m]) * 100`).
   - Network I/O Receive & Transmit (`rate(container_network_receive_bytes_total[1m])`).
2. **CRM - Nginx** (`crm-nginx`):
   - Active Connections hiện thời (`nginx_connections_active`).
   - Tốc độ xử lý HTTP Request/s (`rate(nginx_http_requests_total[1m])`).
   - Tỷ lệ Connections Accepted vs Handled.
   - Trạng thái phân bổ kết nối (Reading / Writing / Waiting).
3. **CRM - PostgreSQL** (`crm-postgresql`):
   - Số kết nối Client đồng thời (`pg_stat_database_numbackends{datname="crm"}`).
   - Tốc độ giao dịch Commits/s và Rollbacks/s (`pg_stat_database_xact_commit`).
   - Tốc độ truy xuất Tuples Returned & Fetched (`pg_stat_database_tup_returned`).
   - Tỷ lệ Cache Hit Ratio (%) của hệ thống.
   - Dung lượng CSDL CRM (`pg_database_size_bytes{datname="crm"}`).

---

## 6. Danh Mục Tài Khoản Mẫu (Dữ liệu Seed)
Hệ thống tự động khởi tạo các tài khoản nhân sự mẫu với mật khẩu sinh ngẫu nhiên từ biến môi trường tương ứng:

| Tên đăng nhập | Vai trò (Role) | Mật khẩu truy cập | Ghi chú quyền hạn |
| :--- | :--- | :--- | :--- |
| **`admin`** | `manager` | *Xem tệp `.env` (`SEED_MANAGER_PASSWORD`)* | Quản lý toàn quyền hệ thống |
| **`sales01`** | `sales` | *Xem tệp `.env` (`SEED_SALES_PASSWORD`)* | Nhân viên kinh doanh 01 |
| **`sales02`** | `sales` | *Xem tệp `.env` (`SEED_SALES_PASSWORD`)* | Nhân viên kinh doanh 02 |
| **`support01`** | `support` | *Xem tệp `.env` (`SEED_SUPPORT_PASSWORD`)* | Nhân viên hỗ trợ CSKH 01 |
| **`support02`** | `support` | *Xem tệp `.env` (`SEED_SUPPORT_PASSWORD`)* | Nhân viên hỗ trợ CSKH 02 |
| **pgAdmin Admin** | `admin` | *Xem tệp `.env` (`PGADMIN_DEFAULT_PASSWORD`)* | Email: `admin@example.com` |
| **Grafana Admin** | `admin` | *Xem tệp `.env` (`GF_SECURITY_ADMIN_PASSWORD`)* | Quản trị bảng điều khiển giám sát |
| **Postgres Exporter** | `exporter` | *Xem tệp `.env` (`POSTGRES_EXPORTER_PASSWORD`)* | Quyền tối thiểu `pg_monitor` |

---

## 7. Lịch Sử Triển Khai (Quy chuẩn 3 Commit)
- **COMMIT 1**: `feat: Khởi tạo ứng dụng web CRM, CSDL PostgreSQL và Nginx Reverse Proxy với HTTPS`
- **COMMIT 2**: `feat: Tích hợp hệ thống giám sát Prometheus và Grafana cùng các Exporter`
- **COMMIT 3**: `feat: Thêm log tập trung Loki/Promtail và áp dụng các biện pháp hardening bảo mật`
