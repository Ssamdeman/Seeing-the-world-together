#!/usr/bin/env bash
set -euo pipefail

IFACE="wlan0"
AP_CON="Frame-Setup"
AP_SSID="Frame-Setup"
AP_PASS="frame-Says-Iloveyou"
STATE_DIR="/run/frame-wifi"
FAIL_FILE="$STATE_DIR/fail_count"
RETRY_FILE="$STATE_DIR/retry_count"
SCANS_FILE="$STATE_DIR/networks.json"
STATUS_FILE="$STATE_DIR/status.json"

mkdir -p "$STATE_DIR"
chmod 755 "$STATE_DIR"

write_status() {
  local mode="$1"
  local msg="${2:-}"
  printf '{"mode":"%s","ssid":"%s","password":"%s","url":"http://10.42.0.1","message":"%s"}\n' \
    "$mode" "$AP_SSID" "$AP_PASS" "$msg" > "$STATUS_FILE.tmp"
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
}

ensure_ap_profile() {
  if ! nmcli -t -f NAME connection show | grep -Fxq "$AP_CON"; then
    nmcli connection add type wifi ifname "$IFACE" con-name "$AP_CON" \
      autoconnect no ssid "$AP_SSID" \
      802-11-wireless.mode ap 802-11-wireless.band bg \
      ipv4.method shared ipv4.addresses 10.42.0.1/24 \
      wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn wifi-sec.pairwise ccmp \
      wifi-sec.wps-method disabled wifi-sec.psk "$AP_PASS" >/dev/null
  else
    nmcli connection modify "$AP_CON" \
      ssid "$AP_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn \
      wifi-sec.pairwise ccmp wifi-sec.wps-method disabled wifi-sec.psk "$AP_PASS" >/dev/null
  fi
}

scan_networks() {
  nmcli device wifi rescan ifname "$IFACE" >/dev/null 2>&1 || true
  sleep 2
  python3 -c '
import subprocess, json
out = subprocess.check_output(
    ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list", "ifname", "wlan0"],
    text=True, stderr=subprocess.DEVNULL
)
seen = {}
for line in out.splitlines():
    parts = line.split(":")
    if len(parts) < 3:
        continue
    ssid = parts[0].strip()
    if not ssid or ssid == "Frame-Setup":
        continue
    sig = int(parts[1]) if parts[1].isdigit() else 0
    sec = parts[2].strip() or "OPEN"
    if ssid not in seen or sig > seen[ssid]["signal"]:
        seen[ssid] = {"ssid": ssid, "signal": sig, "security": sec}
ranked = sorted(seen.values(), key=lambda x: x["signal"], reverse=True)
print(json.dumps(ranked))
' > "$SCANS_FILE.tmp" 2>/dev/null || echo "[]" > "$SCANS_FILE.tmp"
  mv "$SCANS_FILE.tmp" "$SCANS_FILE"
}

start_setup_mode() {
  scan_networks
  ensure_ap_profile
  nmcli connection up "$AP_CON" >/dev/null
  echo 0 > "$RETRY_FILE"
  write_status "setup" "Connect to Wi-Fi $AP_SSID and open http://10.42.0.1"
}

ACTIVE_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev {print $1; exit}')

# Case 1: Already in Frame-Setup AP mode
if [ "$ACTIVE_CON" = "$AP_CON" ]; then
  write_status "setup" "Connect to Wi-Fi $AP_SSID and open http://10.42.0.1"
  CLIENTS=$(iw dev "$IFACE" station dump 2>/dev/null | grep -c "^Station " || true)
  if [ "$CLIENTS" -gt 0 ]; then
    echo 0 > "$RETRY_FILE"
    exit 0
  fi

  RETRIES=$(cat "$RETRY_FILE" 2>/dev/null || echo 0)
  RETRIES=$((RETRIES + 1))
  if [ "$RETRIES" -lt 5 ]; then
    echo "$RETRIES" > "$RETRY_FILE"
    exit 0
  fi

  # 5 minutes elapsed with no phone connected: retry saved Wi-Fi
  echo 0 > "$RETRY_FILE"
  nmcli connection down "$AP_CON" >/dev/null 2>&1 || true
  nmcli device connect "$IFACE" >/dev/null 2>&1 || true
  sleep 8

  NEW_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev {print $1; exit}')
  if [ -n "$NEW_CON" ] && [ "$NEW_CON" != "$AP_CON" ]; then
    echo 0 > "$FAIL_FILE"
    write_status "connected" ""
  else
    ensure_ap_profile
    nmcli connection up "$AP_CON" >/dev/null 2>&1 || true
    write_status "setup" "Connect to Wi-Fi $AP_SSID and open http://10.42.0.1"
  fi
  exit 0
fi

# Case 2: Normal client Wi-Fi connected
if [ -n "$ACTIVE_CON" ]; then
  echo 0 > "$FAIL_FILE"
  echo 0 > "$RETRY_FILE"
  write_status "connected" ""
  exit 0
fi

# Case 3: Disconnected — increment consecutive failure count
FAILS=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)
FAILS=$((FAILS + 1))
echo "$FAILS" > "$FAIL_FILE"
write_status "disconnected" ""

if [ "$FAILS" -ge 4 ]; then
  start_setup_mode
fi
