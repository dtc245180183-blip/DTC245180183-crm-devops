# Báo Cáo Tóm Tắt Quét Lỗ Hổng An Ninh (Security Scan Summary)

- **Thời gian quét**: 2026-10-20 (khoảng 10:54Z)
- **Công cụ**: Trivy `aquasec/trivy:0.60.0` (cố định tag), tùy chọn `--severity HIGH,CRITICAL --scanners vuln` (tính cả lỗ hổng chưa có bản vá), và `npm audit --omit=dev`
- **Phạm vi**: 12/12 image trong `docker compose config --images`
- **Lệnh tương đương cho từng image**: `docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.60.0 image --severity HIGH,CRITICAL --scanners vuln <image>`

---

## 1. Kết quả quét từng image

| Image | CRITICAL | HIGH | Gói chính (rút gọn) | Mức tiếp cận từ bên ngoài |
|---|---|---|---|---|
| `crm-web` (tự build) | 4 | 49 | brace-expansion, cross-spawn, glob, http-cache-semantics, ip-address, libcrypto3 | Qua Nginx, có xác thực |
| `crm-alert-sink` (tự build) | 3 | 25 | libcrypto3, libssl3, musl, musl-utils, setuptools, sqlite-libs | Nội bộ (monitoring) |
| `nginxinc/nginx-unprivileged:1.27.4-alpine` | 2 | 53 | c-ares, curl, libcrypto3, libcurl, libexpat, libpng | **Publish cổng 80/443** |
| `postgres:16.8-alpine` | 7 | 85 | libcrypto3, libssl3, libxml2, libxslt, musl, musl-utils | Nội bộ (backend, internal) |
| `grafana/grafana:11.5.2` | 9 | 133 | jsonparser, kin-openapi, go-jose, golang-jwt, tempo | Qua Nginx `/grafana/`, có xác thực |
| `dpage/pgadmin4:9.1` | 6 | 143 | Authlib, Brotli, Mako, PyJWT, azure-core, cryptography | Qua Nginx `/pgadmin/`, có xác thực |
| `prom/prometheus:v3.2.1` | 4 | 104 | docker/docker, golang-jwt, otel/sdk, x/crypto, x/net, x/oauth2 | Nội bộ (monitoring) |
| `grafana/loki:3.4.2` | 2 | 55 | jsonparser, golang-jwt, prometheus, otel/sdk, x/crypto | Nội bộ (monitoring) |
| `grafana/promtail:3.4.2` | 2 | 58 | docker/docker, golang-jwt, prometheus, x/crypto, x/net | Nội bộ (monitoring) |
| `gcr.io/cadvisor/cadvisor:v0.49.2` | 4 | 63 | docker/docker, runc, selinux, logrus, x/crypto, x/net | Nội bộ (monitoring) |
| `nginx/nginx-prometheus-exporter:1.4.1` | 1 | 45 | x/crypto, x/net, x/oauth2, x/text, stdlib | Nội bộ (monitoring) |
| `prometheuscommunity/postgres-exporter:v0.16.0` | 1 | 47 | x/crypto, x/net, x/oauth2, x/text, stdlib | Nội bộ (backend, monitoring) |
| **Tổng cộng** | **45** | **860** | (một lỗ hổng có thể xuất hiện ở nhiều image) | |

## 2. Kết quả `npm audit --omit=dev` (mã nguồn web)

- 3 lỗ hổng: **1 critical, 2 high**, cùng gốc từ gói `tar <= 7.5.20`, kéo theo `@mapbox/node-pre-gyp <= 1.0.11` và `bcrypt 5.0.1 – 5.1.1`.
- Cách sửa do npm đề xuất: nâng lên `bcrypt@6.0.0` (thay đổi lớn, chưa áp dụng trong phạm vi bài này để tránh rủi ro làm hỏng ứng dụng đang chạy ổn).
- Đã kiểm tra bằng `grep`: mã nguồn ứng dụng (`web/src`) không import trực tiếp gói `tar`.

---

## 3. Đánh giá và nhận định

1. **Hệ thống chưa đạt mức "không có lỗ hổng HIGH/CRITICAL"**. Số lượng cao một phần vì các image được cố định ở tag cũ so với thời điểm quét, và Trivy tính cả gói hệ điều hành lẫn thư viện Go biên dịch tĩnh. Có lỗ hổng chưa có bản vá, và nhiều lỗ hổng chỉ khai thác được trong điều kiện cụ thể; số lượng không đồng nghĩa với việc khai thác được.
2. **Biện pháp bù đắp đang áp dụng** (đã kiểm chứng bằng `docker inspect`): chỉ Nginx publish cổng 80/443; mạng `backend` là `internal`; `no-new-privileges` trên 12/12 container; `cap_drop: ALL` trên 11/12 (trừ `pgadmin`); `read_only` trên 7 service; phần lớn chạy non-root (ngoại lệ `cadvisor`, `promtail`).
3. **Nhóm ưu tiên cập nhật** vì tiếp cận được từ bên ngoài: `nginx-unprivileged`, `crm-web`, `grafana`, `pgadmin`.
4. Với `crm-web`: lỗ hổng `tar` nằm trong chuỗi phụ thuộc cài đặt của `bcrypt@5`; ứng dụng không gọi `tar` khi chạy, container chạy non-root với hệ tệp chỉ đọc. Đây là phân tích rủi ro, không phải cam kết không thể khai thác.

## 4. Hướng khắc phục (chưa thực hiện trong phạm vi bài)

- Cập nhật tag các image lên bản vá mới nhất, kiểm thử lại, rồi quét lại.
- Nâng `bcrypt` lên 6.x (hoặc dùng `bcryptjs`), build lại image `crm-web`.
- Tự động hóa quét Trivy trong quy trình CI và đặt ngưỡng chặn với lỗ hổng CRITICAL có bản vá.
