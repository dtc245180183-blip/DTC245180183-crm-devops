# Danh Mục Phiên Bản Thành Phần (Fixed Tags)

Tất cả các dịch vụ trong hệ thống CRM đều sử dụng Docker Image có tag phiên bản cố định (không sử dụng `:latest` hoặc tag nổi), đã được kiểm chứng bằng lệnh `docker pull` thực tế trên môi trường Docker Desktop / WSL2.

| STT | Thành phần / Dịch vụ | Docker Image & Tag | Phiên bản chi tiết | Mục đích sử dụng |
| :--- | :--- | :--- | :--- | :--- |
| 1 | CSDL PostgreSQL | `postgres:16.8-alpine` | PostgreSQL 16.8 on Alpine Linux | Lưu trữ CSDL quan hệ chính của CRM |
| 2 | Quản trị DB (pgAdmin) | `dpage/pgadmin4:9.1` | pgAdmin 4 v9.1 | Quản trị CSDL qua giao diện web |
| 3 | Ứng dụng Web CRM | `node:20.18.3-alpine` | Node.js 20.18.3 LTS on Alpine | Nền tảng thực thi ứng dụng Express & EJS |
| 4 | Web Server / Proxy | `nginxinc/nginx-unprivileged:1.27.4-alpine` | Nginx 1.27.4 (Non-root Unprivileged) | Reverse Proxy, SSL Termination, Security Headers |
| 5 | Prometheus | `prom/prometheus:v3.2.1` | Prometheus v3.2.1 | Thu thập và lưu trữ time-series metrics |
| 6 | Grafana | `grafana/grafana:11.5.2` | Grafana 11.5.2 | Trực quan hóa bảng điều khiển KPI & giám sát |
| 7 | cAdvisor | `gcr.io/cadvisor/cadvisor:v0.49.2` | cAdvisor v0.49.2 | Thu thập chỉ số tài nguyên container |
| 8 | Nginx Exporter | `nginx/nginx-prometheus-exporter:1.4.1` | Nginx Exporter v1.4.1 | Xuất chỉ số từ Nginx stub_status |
| 9 | Postgres Exporter | `prometheuscommunity/postgres-exporter:v0.16.0` | Postgres Exporter v0.16.0 | Xuất chỉ số CSDL PostgreSQL |
| 10 | Loki | `grafana/loki:3.4.2` | Grafana Loki v3.4.2 | Lưu trữ và xử lý log tập trung |
| 11 | Promtail | `grafana/promtail:3.4.2` | Promtail v3.4.2 | Thu thập log container chuyển tiếp về Loki |
| 12 | Alert Sink | `python:3.11.11-alpine` | Python 3.11 on Alpine Linux | Dịch vụ tiếp nhận Webhook cảnh báo an ninh |
| 13 | Trivy Scanner | `aquasec/trivy:0.60.0` | Trivy v0.60.0 | Quét lỗ hổng an toàn thông tin container |
