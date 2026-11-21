#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATUS_FILE = "/run/frame-wifi/status.json"

HTML = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Photo Frame Display</title>
<style>
  html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #000; font-family: system-ui, sans-serif; }
  iframe { border: 0; width: 100%; height: 100%; display: block; }
  #setup {
    position: fixed; inset: 0; background: #0b0b0d; color: #f4f4f5;
    display: flex; align-items: center; justify-content: center; text-align: center;
    opacity: 0; pointer-events: none; transition: opacity 0.4s ease; z-index: 10;
  }
  #setup.active { opacity: 1; pointer-events: auto; }
  .box { max-width: 560px; padding: 36px; border: 1px solid #27272a; border-radius: 16px; background: #141417; }
  h1 { margin: 0 0 12px; font-size: 2rem; font-weight: 600; }
  p { margin: 10px 0; font-size: 1.2rem; color: #a1a1aa; line-height: 1.5; }
  .cred { margin: 22px 0; padding: 18px; border-radius: 12px; background: #1f1f23; font-size: 1.35rem; color: #fff; }
  .cred div { margin: 6px 0; }
  span.val { font-family: monospace; color: #60a5fa; font-weight: 700; }
  #err { margin-top: 14px; color: #fca5a5; font-size: 1.05rem; min-height: 1.4em; }
</style>
</head>
<body>
  <iframe id="frame" src="http://127.0.0.1:9090"></iframe>
  <div id="setup">
    <div class="box">
      <h1>Wi-Fi Setup Mode</h1>
      <p>The frame could not reach saved Wi-Fi. Connect your phone to finish setup:</p>
      <div class="cred">
        <div>1. Join Wi-Fi: <span class="val" id="ssid">Frame-Setup</span></div>
        <div>2. Password: <span class="val" id="pass">frame1234</span></div>
        <div>3. Open: <span class="val" id="url">http://10.42.0.1</span></div>
      </div>
      <p>Your photos will resume automatically once connected.</p>
      <div id="err"></div>
    </div>
  </div>
<script>
async function poll() {
  try {
    const res = await fetch('/status', { cache: 'no-store' });
    const data = await res.json();
    const overlay = document.getElementById('setup');
    if (data.mode === 'setup') {
      document.getElementById('ssid').textContent = data.ssid || 'Frame-Setup';
      document.getElementById('pass').textContent = data.password || 'frame1234';
      document.getElementById('url').textContent = data.url || 'http://10.42.0.1';
      const msg = data.message || '';
      document.getElementById('err').textContent = msg.includes('Could not connect') ? msg : '';
      overlay.classList.add('active');
    } else {
      overlay.classList.remove('active');
    }
  } catch (e) {}
}
poll();
setInterval(poll, 3000);
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_GET(self):
        if self.path == "/status":
            try:
                with open(STATUS_FILE, "rb") as f:
                    body = f.read()
            except Exception:
                body = b'{"mode":"connected"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        body = HTML.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 9091), Handler).serve_forever()
