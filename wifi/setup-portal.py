#!/usr/bin/env python3
import html
import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

STATE_DIR = "/run/frame-wifi"
SCANS_FILE = os.path.join(STATE_DIR, "networks.json")
STATUS_FILE = os.path.join(STATE_DIR, "status.json")
FAIL_FILE = os.path.join(STATE_DIR, "fail_count")
AP_CON = "Frame-Setup"
TEST_CON = "Frame-Setup-Test"
AP_SSID = "Frame-Setup"
AP_PASS = "frame1234"
IFACE = "wlan0"


def read_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def write_status(mode, message=""):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = STATUS_FILE + ".tmp"
    data = {
        "mode": mode,
        "ssid": AP_SSID,
        "password": AP_PASS,
        "url": "http://10.42.0.1",
        "message": message,
    }
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp, STATUS_FILE)


def attempt_connect(ssid, password):
    time.sleep(1.5)
    write_status("connecting", f"Testing connection to {ssid}...")

    # Clean up only any stale test profile, never an existing saved profile
    subprocess.run(["nmcli", "connection", "delete", TEST_CON], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["nmcli", "connection", "down", AP_CON], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)

    cmd = ["nmcli", "device", "wifi", "connect", ssid, "ifname", IFACE, "name", TEST_CON]
    if password:
        cmd += ["password", password]

    res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if res.returncode == 0:
        # Verified working: replace any prior profile for this SSID, rename TEST_CON -> ssid
        if ssid != TEST_CON:
            subprocess.run(["nmcli", "connection", "delete", ssid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["nmcli", "connection", "modify", TEST_CON, "connection.id", ssid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["nmcli", "connection", "modify", ssid, "connection.autoconnect", "yes"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(FAIL_FILE, "w", encoding="utf-8") as f:
            f.write("0\n")
        write_status("connected", "")
        subprocess.Popen(["systemctl", "stop", "wifi-portal.service"])
        return

    # Failed: delete ONLY TEST_CON so pre-existing saved Wi-Fi remains untouched
    subprocess.run(["nmcli", "connection", "delete", TEST_CON], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["nmcli", "connection", "up", AP_CON], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    write_status("setup", f"Could not connect to {ssid}. Check password and try again.")


def render_page(error_msg=""):
    networks = read_json(SCANS_FILE, [])
    options = ['<option value="">-- Select nearby Wi-Fi --</option>']
    for net in networks:
        s = html.escape(net.get("ssid", ""))
        sig = net.get("signal", 0)
        if s:
            options.append(f'<option value="{s}">{s} ({sig}%)</option>')

    err_html = ""
    if error_msg:
        err_html = f'<div class="err">{html.escape(error_msg)}</div>'

    return f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Photo Frame Wi-Fi Setup</title>
<style>
  body {{ font-family: system-ui, sans-serif; background: #111; color: #f5f5f5; margin: 0; padding: 20px; }}
  .card {{ max-width: 420px; margin: 20px auto; background: #1e1e1e; padding: 22px; border-radius: 12px; }}
  h1 {{ font-size: 1.3rem; margin: 0 0 12px; }}
  p {{ color: #bbb; font-size: 0.92rem; line-height: 1.4; }}
  label {{ display: block; margin-top: 14px; font-size: 0.9rem; color: #ddd; }}
  select, input, button {{ width: 100%; box-sizing: border-box; margin-top: 6px; padding: 12px; border-radius: 8px; border: 1px solid #333; background: #2a2a2a; color: #fff; font-size: 1rem; }}
  button {{ background: #2563eb; border: none; font-weight: 600; margin-top: 20px; cursor: pointer; }}
  .err {{ background: #7f1d1d; color: #fecaca; padding: 12px; border-radius: 8px; margin-bottom: 14px; font-size: 0.92rem; }}
</style>
</head>
<body>
<div class="card">
  <h1>Photo Frame Wi-Fi Setup</h1>
  <p>Choose your home Wi-Fi network or type its exact name below.</p>
  {err_html}
  <form method="POST" action="/connect">
    <label>Nearby Networks</label>
    <select id="picker" onchange="document.getElementById('ssid').value=this.value">
      {''.join(options)}
    </select>
    <label>Wi-Fi Name (SSID)</label>
    <input id="ssid" name="ssid" required placeholder="Enter Wi-Fi name">
    <label>Wi-Fi Password</label>
    <input name="password" type="password" placeholder="Leave blank if open network">
    <button type="submit">Save &amp; Connect</button>
  </form>
</div>
</body>
</html>"""


class PortalHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_GET(self):
        status = read_json(STATUS_FILE, {})
        msg = status.get("message", "")
        err = msg if "Could not connect" in msg else ""
        body = render_page(err).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/connect":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        form = parse_qs(raw)
        ssid = form.get("ssid", [""])[0].strip()
        password = form.get("password", [""])[0]

        if not ssid:
            body = render_page("Please enter a Wi-Fi network name.").encode("utf-8")
            self.send_response(400)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        threading.Thread(target=attempt_connect, args=(ssid, password), daemon=True).start()

        resp = f"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Connecting...</title>
<style>body{{font-family:system-ui,sans-serif;background:#111;color:#f5f5f5;padding:30px;text-align:center;}}</style>
</head><body>
<h2>Connecting to {html.escape(ssid)}...</h2>
<p>Frame-Setup will turn off while the frame tests your Wi-Fi.</p>
<p>If it fails, reconnect to <b>Frame-Setup</b> and refresh <b>http://10.42.0.1</b>.</p>
</body></html>""".encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("10.42.0.1", 80), PortalHandler)
    server.serve_forever()
