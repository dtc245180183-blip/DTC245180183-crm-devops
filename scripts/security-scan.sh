#!/bin/bash
set -e

# ==============================================================================
# KỊCH BẢN QUÉT LỖ HỔNG BẢO MẬT BẰNG TRIVY VÀ NPM AUDIT
# Dự án: CRM Bảo Mật
# Phiên bản Trivy: aquasec/trivy:0.60.0 (Cố định tag)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

EVIDENCE_FILE="$CRM_ROOT/evidence/buoc6-trivy.txt"
DOCS_DIR="$CRM_ROOT/docs/security-scan"
SUMMARY_FILE="$DOCS_DIR/summary.md"

mkdir -p "$CRM_ROOT/evidence" "$DOCS_DIR"

TRIVY_IMAGE="aquasec/trivy:0.60.0"

echo "==================================================================" | tee "$EVIDENCE_FILE"
echo "BẮT ĐẦU QUÉT LỖ HỔNG AN NINH HỆ THỐNG CRM" | tee -a "$EVIDENCE_FILE"
echo "Thời gian: $(date -u '+%Y-%m-%d %H:%M:%SZ')" | tee -a "$EVIDENCE_FILE"
echo "Công cụ: Trivy ($TRIVY_IMAGE) & npm audit" | tee -a "$EVIDENCE_FILE"
echo "==================================================================" | tee -a "$EVIDENCE_FILE"

# Danh sách image cần quét: image tự build và các image dịch vụ chính
IMAGES=(
    "crm-web"
    "crm-alert-sink"
    "postgres:16.8-alpine"
    "nginxinc/nginx-unprivileged:1.27.4-alpine"
    "grafana/grafana:11.5.2"
    "prom/prometheus:v3.2.1"
)

for IMG in "${IMAGES[@]}"; do
    echo "" | tee -a "$EVIDENCE_FILE"
    echo "------------------------------------------------------------------" | tee -a "$EVIDENCE_FILE"
    echo ">> QUÉT IMAGE: $IMG" | tee -a "$EVIDENCE_FILE"
    echo "------------------------------------------------------------------" | tee -a "$EVIDENCE_FILE"
    
    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$HOME/.cache/trivy:/root/.cache/" \
        "$TRIVY_IMAGE" image \
        --severity HIGH,CRITICAL \
        --scanners vuln \
        --format table \
        "$IMG" 2>&1 | tee -a "$EVIDENCE_FILE" || true
done

echo "" | tee -a "$EVIDENCE_FILE"
echo "------------------------------------------------------------------" | tee -a "$EVIDENCE_FILE"
echo ">> QUÉT PHỤ THUỘC ỨNG DỤNG WEB (npm audit --omit=dev)" | tee -a "$EVIDENCE_FILE"
echo "------------------------------------------------------------------" | tee -a "$EVIDENCE_FILE"

docker run --rm -v "$CRM_ROOT/web:/app" -w /app node:20.18.3-alpine npm audit --omit=dev 2>&1 | tee -a "$EVIDENCE_FILE" || true

echo "" | tee -a "$EVIDENCE_FILE"
echo "==================================================================" | tee -a "$EVIDENCE_FILE"
echo "HOÀN TẤT QUÉT BẢO MẬT. ĐÃ LƯU BẰNG CHỨNG VÀO $EVIDENCE_FILE" | tee -a "$EVIDENCE_FILE"
echo "==================================================================" | tee -a "$EVIDENCE_FILE"
