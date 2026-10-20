# Báo Cáo Xử Lý Sự Cố An Toàn Thông Tin: Tấn Công Dò Mật Khẩu (Brute Force Attack) Vào Trang Đăng Nhập CRM

- **Mã sự cố**: `INC-2026-10-20-001`
- **Mức độ nghiêm trọng**: `CRITICAL` (Nghiêm trọng)
- **Hệ thống bị ảnh hưởng**: Ứng dụng Web CRM (`https://localhost/auth/login`)
- **Thời gian phát hiện**: `2026-10-20T07:24:10Z`
- **Trạng thái**: Đã điều tra nguyên nhân, truy vết đầy đủ và hoàn tất gia cố (Mitigated & Hardened)

---

## 1. Mô Tả Sự Cố (Incident Description)
Vào lúc 07:24:06Z ngày 20/10/2026, hệ thống ghi nhận một đợt tấn công dò mật khẩu tự động (Dictionary / Brute Force Attack) nhắm vào tài khoản quản trị `admin` tại endpoint `/auth/login`. Kẻ tấn công gửi liên tiếp 20 yêu cầu xác thực sai mật khẩu trong khoảng thời gian ~11 giây với nhiều mật khẩu phổ biến từ danh từ điển (`password123`, `admin123`, `12345678`, `qwerty2026`, v.v.).

---

## 2. Phát Hiện Sự Cố (Detection & Alerting)

### 2.1. Cấu hình Alert Rules Đôi (Dual Alerting Architecture)
Nhằm phát hiện toàn diện cả hành vi tấn công chạm tới ứng dụng và các nỗ lực bị chặn ở tầng biên (edge), hệ thống giám sát được cấu hình 2 Alert Rules tự động trong Grafana Alerting:

#### Quy tắc 1: CRM - Brute force login
- **Nguồn dữ liệu**: Grafana Loki (truy vấn metric từ log ứng dụng):
  ```logql
  sum(count_over_time({job="webapp"} |= "LOGIN_FAILED" [1m]))
  ```
- **Điều kiện kích hoạt**: Số lần `LOGIN_FAILED` trong 1 phút > 3 (`$B > 3`).
- **Thời gian duy trì (for)**: `0s` (kích hoạt ngay lập tức).
- **Mức độ (Severity)**: `critical`.

#### Quy tắc 2: CRM - Login bị giới hạn (429)
- **Nguồn dữ liệu**: Grafana Loki (truy vấn access log Nginx):
  ```logql
  sum(count_over_time({job="nginx", status="429"} [1m]))
  ```
- **Điều kiện kích hoạt**: Số yêu cầu nhận mã HTTP 429 tại Nginx trong 1 phút > 5 (`$B > 5`).
- **Thời gian duy trì (for)**: `0s` (kích hoạt ngay lập tức).
- **Mức độ (Severity)**: `warning`.

### 2.2. Quá trình kích hoạt cảnh báo thực tế (lần chạy ở Bước 5, cấu hình ban đầu 5r/m, burst 3)

> Số liệu ở mục 2.2 và mục 3 thu từ lần chạy đầu tiên ở Bước 5 với cấu hình giới hạn ban đầu (5 yêu cầu/phút, burst 3). Cấu hình cuối cùng (10 yêu cầu/phút, burst 5) được kiểm chứng lại ở mục 2.3.

1. **Trước tấn công (07:23:00Z)**:
   - Số lượng `LOGIN_FAILED` và `status="429"` trong 1 phút: `0`.
   - Trạng thái Alertmanager: `0` alert firing (Normal).
2. **Trong tấn công (07:24:06Z - 07:24:17Z)**:
   - 4 yêu cầu đầu tiên đi qua Nginx tới ứng dụng: Web CRM ghi nhận 4 log `LOGIN_FAILED`, vượt ngưỡng > 3. Quy tắc `CRM - Brute force login` chuyển sang trạng thái **`Firing`** (Critical) lúc `07:24:10Z`.
   - 16 yêu cầu tiếp theo bị Nginx chặn và trả về HTTP 429: Access log Nginx ghi nhận 16 dòng mã 429, vượt ngưỡng > 5. Quy tắc `CRM - Login bi gioi han (429)` chuyển sang trạng thái **`Firing`** (Warning) lúc `07:24:20Z`.
3. **Tiếp nhận thông báo (Contact Point `alert-sink`)**:
   - Grafana gửi Webhook POST tới dịch vụ `http://alert-sink:5001/`.
   - Log ghi nhận tại container `crm-alert-sink-1`:
     ```text
     [2026-10-20T07:24:15.096618+00:00] [ALERT-SINK] status=firing alert=[FIRING:1] CRM - Brute force login Security (critical) payload={... "values": {"B": 4, "C": 1} ...}
     [2026-10-20T07:24:25.036823+00:00] [ALERT-SINK] status=firing alert=[FIRING:1] CRM - Login bi gioi han (429) Security (warning) payload={... "values": {"B": 16, "C": 1} ...}
     ```
4. **Hồi phục tự động (Resolved)**:
   - Sau khi đợt tấn công chấm dứt và cửa sổ trượt 1 phút kết thúc, cả 2 quy tắc tự động gửi webhook `[RESOLVED]` lúc `07:25:15Z` và `07:25:25Z`. Grafana trở lại trạng thái `Normal`.


### 2.3. Kiểm chứng lại với cấu hình cuối (10r/m, burst 5) – 20/10/2026

- **Thời điểm**: tấn công từ 10:47:46Z đến 10:47:59Z. Kịch bản gửi 20 yêu cầu đăng nhập sai tới `https://localhost/auth/login`, cách nhau 0,5 giây, sau khi chờ 90 giây để bộ đếm `limit_req` sạch.
- **Kết quả đo**: **8 phản hồi 401** (lọt tới ứng dụng), **12 phản hồi 429** (bị Nginx chặn), 0 mã khác.
- **Đối chiếu chéo**: log ứng dụng có 8 dòng `LOGIN_FAILED`, log Nginx có 12 dòng 429, Loki đếm 8 `LOGIN_FAILED` trong 3 phút; ba nguồn khớp số đo.
- **Giải thích**: `rate=10r/m burst=5 nodelay` cho 6 yêu cầu lọt ngay (1 + burst 5), sau đó cứ 6 giây nạp lại 1 yêu cầu. Cuộc tấn công kéo dài 13 giây nên lọt thêm 2 yêu cầu, tổng cộng 8. Cấu hình ban đầu (5r/m, burst 3) chỉ cho 4 lượt. Số 401 có thể dao động 7–8 giữa các lần chạy.
- **Cảnh báo**: cả hai rule đều bắn và gửi webhook tới `alert-sink`. Script chụp trạng thái rule sau 75 giây nên khi đó rule đã quay về Normal; bằng chứng bắn cảnh báo là các dòng webhook sau (đã lược bỏ phần payload):

    [2026-10-20T10:48:05.371469+00:00] [ALERT-SINK] status=firing alert=[FIRING:1] CRM - Login bi gioi han (429) Security (warning)
    [2026-10-20T10:48:05.475909+00:00] [ALERT-SINK] status=firing alert=[FIRING:1] CRM - Brute force login Security (critical)
    [2026-10-20T10:49:05.040936+00:00] [ALERT-SINK] status=resolved alert=[RESOLVED] CRM - Login bi gioi han (429) Security (warning)
    [2026-10-20T10:49:05.053425+00:00] [ALERT-SINK] status=resolved alert=[RESOLVED] CRM - Brute force login Security (critical)

---

## 3. Truy Vết Sự Cố Bằng LogQL (Forensic Investigation)

### 3.1. Truy vấn log ứng dụng Web CRM
```logql
{job="webapp"} |= "LOGIN_FAILED"
```
- Số lần thử sai: 4 lần ghi nhận tại ứng dụng Node.js (lần chạy Bước 5); 8 lần ở lần kiểm chứng cuối (mục 2.3).
- Tài khoản mục tiêu: `admin`
- Lý do thất bại: `reason=wrong_password`
- IP nguồn: `172.23.0.1`

### 3.2. Truy vấn access log Nginx
```logql
{job="nginx"} |= "POST /auth/login"
```
- 4 yêu cầu đầu tiên trả về HTTP 401 (`rt=0.080s` - `0.110s`). Ở lần kiểm chứng cuối: 8 yêu cầu trả về 401.
- 16 yêu cầu tiếp theo trả về HTTP 429 (`rt=0.000s`), bị chặn hoàn toàn tại Nginx. Ở lần kiểm chứng cuối: 12 yêu cầu trả về 429.

---

## 4. Xử Lý & Gia Cố Hệ Thống (Mitigation & Hardening)

### 4.1. Cấu hình Rate Limiting tại Nginx
Trong `nginx/nginx.conf`:
```nginx
    # Rate limit chỉ áp dụng cho POST /auth/login
    map $request_method $login_limit_key {
        POST $binary_remote_addr;
        default "";
    }

    # Giới hạn 10 req/min, burst 5 req, trả về HTTP 429
    limit_req_zone $login_limit_key zone=login_limit:10m rate=10r/m;
    limit_req_status 429;

    server {
        ...
        location = /auth/login {
            limit_req zone=login_limit burst=5 nodelay;
            proxy_pass http://web:3000;
            ...
        }
    }
```

### 4.2. Hạn Chế Kỹ Thuật Thực Tế (Docker Desktop WSL2 SNAT)
> **Hạn chế trung thực trên Docker Desktop / WSL2**:
> - Trên môi trường Docker Desktop cho Windows (chạy trên nhân WSL2), toàn bộ lưu lượng mạng từ Windows Host đi qua cổng được publish (80/443) vào container đều chịu cơ chế **Source NAT (SNAT)**.
> - Do đó, mọi client kết nối từ bên ngoài đều có cùng một địa chỉ IP nguồn là `172.23.0.1` (IP gateway của mạng Docker bridge).
> - Điều này dẫn tới việc biến khóa `$binary_remote_addr` trong Nginx xem tất cả người dùng như một client duy nhất. Giới hạn `rate=10r/m burst=5` trở thành giới hạn **TOÀN CỤC (GLOBAL)**.
> - **Ảnh hưởng**: Kẻ tấn công thực hiện brute force có thể làm người dùng hợp lệ tạm thời nhận mã 429 nếu cố đăng nhập cùng thời điểm.
> - **Giải pháp trên môi trường Production**:
>   1. Sử dụng module `ngx_http_realip_module` với cấu hình `set_real_ip_from` tin cậy từ Reverse Proxy/Load Balancer lớp trước và trích xuất client IP thật từ `X-Forwarded-For`.
>   2. Triển khai cơ chế khóa tài khoản hoặc giới hạn tần suất theo danh tính (Account-based throttling) tại tầng ứng dụng (ví dụ khóa tài khoản `admin` tạm thời sau 5 lần nhập sai liên tiếp bất kể IP).

---

## 5. Bài Học Kinh Nghiệm & Khuyến Nghị Dài Hạn
1. **Phòng thủ đa tầng (Defense-in-Depth)**: Kết hợp chặn sớm ở reverse proxy (Nginx 429) và theo dõi log ứng dụng (Node.js 401).
2. **Khả năng quan sát kép**: Bố trí cảnh báo cho cả lỗi đăng nhập (401) và số lượng yêu cầu bị chặn (429) giúp quản trị viên nắm được cả mức độ tấn công lẫn hiệu quả của biện pháp phòng thủ.
