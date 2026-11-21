#!/usr/bin/env python3
import json
import time
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
  #overlay {
    position: fixed; inset: 0; background: #0b0b0d; color: #f4f4f5;
    display: flex; align-items: center; justify-content: center; text-align: center;
    opacity: 1; pointer-events: auto; transition: opacity 0.4s ease; z-index: 10;
  }
  #overlay.hidden { opacity: 0; pointer-events: none; }
  .box { max-width: 580px; padding: 40px; border: 1px solid #27272a; border-radius: 18px; background: #141417; }
  h1 { margin: 0 0 12px; font-size: 2.1rem; font-weight: 600; }
  p { margin: 10px 0; font-size: 1.2rem; color: #a1a1aa; line-height: 1.5; }
  .cred { margin: 22px 0; padding: 18px; border-radius: 12px; background: #1f1f23; font-size: 1.35rem; color: #fff; }
  .cred div { margin: 6px 0; }
  span.val { font-family: monospace; color: #60a5fa; font-weight: 700; }
  .ok-badge { display: inline-block; padding: 8px 18px; border-radius: 999px; background: #14532d; color: #86efac; font-weight: 600; font-size: 1.1rem; margin-bottom: 14px; }
  .spinner { width: 42px; height: 42px; border: 4px solid #27272a; border-top-color: #60a5fa; border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto 18px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  #err { margin-top: 14px; color: #fca5a5; font-size: 1.05rem; min-height: 1.4em; }
  .hidden-panel { display: none; }
</style>
</head>
<body>
  <iframe id="frame" src="about:blank"></iframe>
  <div id="overlay">
    <div class="box" id="panel-connecting">
      <div class="spinner"></div>
      <h1 id="conn-title">Connecting to Wi-Fi...</h1>
      <p id="conn-msg">Checking saved network (Attempt 1/5)...</p>
    </div>

    <div class="box hidden-panel" id="panel-setup">
      <h1>Wi-Fi Setup Mode</h1>
      <p>No active Wi-Fi connection. Connect your phone to set up Wi-Fi:</p>
      <div class="cred">
        <div>1. Join Wi-Fi: <span class="val" id="ssid">Frame-Setup</span></div>
        <div>2. Password: <span class="val" id="pass">frame-says-I-love-you</span></div>
        <div>3. Open: <span class="val" id="url">http://10.42.0.1</span></div>
      </div>
      <p id="setup-sub">Your photos will start automatically once Wi-Fi is verified.</p>
      <div id="err"></div>
    </div>

    <div class="box hidden-panel" id="panel-connected">
      <div class="ok-badge">Connected</div>
      <h1 id="ok-title">Wi-Fi Connected!</h1>
      <p id="ok-msg">Verifying stable connection. Starting slideshow in 40 seconds...</p>
    </div>
  </div>
<script>
let frameLoaded = false;

function showPanel(name) {
  document.getElementById('panel-connecting').classList.toggle('hidden-panel', name !== 'connecting');
  document.getElementById('panel-setup').classList.toggle('hidden-panel', name !== 'setup');
  document.getElementById('panel-connected').classList.toggle('hidden-panel', name !== 'connected');
}

async function poll() {
  try {
    const res = await fetch('/status', { cache: 'no-store' });
    const data = await res.json();
    const overlay = document.getElementById('overlay');
    const iframe = document.getElementById('frame');
    const mode = data.mode || 'disconnected';

    if (mode === 'ready' || mode === 'connected') {
      if (!frameLoaded) {
        iframe.src = 'http://127.0.0.1:9090';
        frameLoaded = true;
      }
      overlay.classList.add('hidden');
      return;
    }

    // Any non-ready state immediately hides cached slides
    overlay.classList.remove('hidden');
    if (frameLoaded) {
      iframe.src = 'about:blank';
      frameLoaded = false;
    }

    if (mode === 'connected_wait') {
      showPanel('connected');
      const net = data.connected_ssid ? ` (${data.connected_ssid})` : '';
      document.getElementById('ok-title').textContent = `Connected${net}!`;
      const rem = typeof data.remaining === 'number' ? data.remaining : 40;
      document.getElementById('ok-msg').textContent = `Verifying stable connection. Starting slideshow in ${rem}s...`;
    } else if (mode === 'setup' || mode === 'testing') {
      showPanel('setup');
      document.getElementById('ssid').textContent = data.ssid || 'Frame-Setup';
      document.getElementById('pass').textContent = data.password || 'frame-says-I-love-you';
      document.getElementById('url').textContent = data.url || 'http://10.42.0.1';
      const msg = data.message || '';
      if (mode === 'testing') {
        document.getElementById('setup-sub').textContent = msg || 'Testing Wi-Fi credentials...';
        document.getElementById('err').textContent = '';
      } else {
        document.getElementById('setup-sub').textContent = 'Your photos will start automatically once Wi-Fi is verified.';
        document.getElementById('err').textContent = msg.includes('Could not connect') ? msg : '';
      }
    } else {
      showPanel('connecting');
      document.getElementById('conn-title').textContent = 'Connecting to Wi-Fi...';
      document.getElementById('conn-msg').textContent = data.message || 'Checking saved Wi-Fi connection...';
    }
  } catch (e) {}
}
poll();
setInterval(poll, 1500);
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
                    raw = json.loads(f.read().decode("utf-8"))
            except Exception:
                raw = {"mode": "disconnected", "message": "Starting network check..."}

            # Handle 40-second connected confirmation countdown dynamically
            if raw.get("mode") == "connected_wait":
                ready_at = float(raw.get("ready_at", 0))
                rem = int(round(ready_at - time.time()))
                if rem <= 0:
                    raw["mode"] = "ready"
                    raw["remaining"] = 0
                    try:
                        with open(STATUS_FILE + ".tmp", "w", encoding="utf-8") as wf:
                            json.dump(raw, wf)
                        import os
                        os.replace(STATUS_FILE + ".tmp", STATUS_FILE)
                    except Exception:
                        pass
                else:
                    raw["remaining"] = rem

            body = json.dumps(raw).encode("utf-8")
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
