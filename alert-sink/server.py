import sys
import json
import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

class AlertHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health' or self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        try:
            payload = json.loads(body.decode('utf-8'))
            alert_name = payload.get('title') or payload.get('alerts', [{}])[0].get('labels', {}).get('alertname', 'Unknown')
            status = payload.get('status', 'unknown')
            log_entry = f"[{now}] [ALERT-SINK] status={status} alert={alert_name} payload={json.dumps(payload, ensure_ascii=False)}"
        except Exception:
            log_entry = f"[{now}] [ALERT-SINK] raw_body={body.decode('utf-8', errors='ignore')}"

        # In ra stdout để Promtail thu thập đưa về Loki
        print(log_entry, flush=True)

        # Ghi ra tệp /tmp/alerts.log
        try:
            with open("/tmp/alerts.log", "a", encoding="utf-8") as f:
                f.write(log_entry + "\n")
        except Exception as e:
            print(f"[ALERT-SINK] Error writing /tmp/alerts.log: {e}", flush=True)

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"status":"received"}')

    def log_message(self, format, *args):
        # Tắt bớt log truy cập HTTP mặc định để log alert rõ ràng
        pass

def run(port=5001):
    server_address = ('0.0.0.0', port)
    httpd = HTTPServer(server_address, AlertHandler)
    print(f"[ALERT-SINK] Webhook listener running on port {port}...", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()

if __name__ == '__main__':
    run()
