#!/usr/bin/env bash
set -euo pipefail

IFACE="wlan0"
AP_CON="Frame-Setup"
AP_SSID="Frame-Setup"
AP_PASS="frame-says-I-love-you"
PORTAL_SVC="wifi-portal.service"
STATE_DIR="/run/frame-wifi"
LOG_DIR="/mnt/frame/logs/wifi"
LOG_FILE="$LOG_DIR/wifi.log"
FAIL_FILE="$STATE_DIR/fail_count"
RETRY_FILE="$STATE_DIR/retry_count"
SCANS_FILE="$STATE_DIR/networks.json"
STATUS_FILE="$STATE_DIR/status.json"

mkdir -p "$STATE_DIR"
chmod 755 "$STATE_DIR"

log_event() {
  local level="$1"
  local msg="$2"
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

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
      802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 6 \
      ipv4.method shared ipv4.addresses 10.42.0.1/24 \
      wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp \
      wifi-sec.pmf disable wifi-sec.wps-method disabled wifi-sec.psk "$AP_PASS" >/dev/null
  else
    nmcli connection modify "$AP_CON" \
      ssid "$AP_SSID" 802-11-wireless.band bg 802-11-wireless.channel 6 \
      wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn \
      wifi-sec.pairwise ccmp wifi-sec.group ccmp wifi-sec.pmf disable \
      wifi-sec.wps-method disabled wifi-sec.psk "$AP_PASS" >/dev/null
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
  for _ in $(seq 1 15); do ip -4 addr show "$IFACE" | grep -q "10.42.0.1" && break; sleep 0.5; done
  systemctl restart "$PORTAL_SVC"
  echo 0 > "$RETRY_FILE"
  write_status "setup" "Connect to Wi-Fi $AP_SSID and open http://10.42.0.1"
  log_event "ERROR" "Wi-Fi failed 4 consecutive checks; entered Frame-Setup AP mode (10.42.0.1)"
}

ACTIVE_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev {print $1; exit}')
PREV_FAILS=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)

# Case 1: Already in Frame-Setup AP mode
if [ "$ACTIVE_CON" = "$AP_CON" ]; then
  write_status "setup" "Connect to Wi-Fi $AP_SSID and open http://10.42.0.1"
  systemctl is-active --quiet "$PORTAL_SVC" || systemctl start "$PORTAL_SVC"
  CLIENTS=$(iw dev "$IFACE" station dump 2>/dev/null | grep -c "^Station " || true)
  if [ "$CLIENTS" -gt 0 ]; then
    echo 0 > "$RETRY_FILE"
    exit 0
  fi

  RETRIES=$(cat "$RETRY_FILE" 2>/dev/null || echo 0)
  RETRIES=$((RETRIES + 1))
  if [ "$RETRIES" -lt 15 ]; then
    echo "$RETRIES" > "$RETRY_FILE"
    exit 0
  fi

  # 15 minutes elapsed with no client connected: retry saved Wi-Fi
  echo 0 > "$RETRY_FILE"
  systemctl stop "$PORTAL_SVC" >/dev/null 2>&1 || true
  nmcli connection down "$AP_CON" >/dev/null 2>&1 || true
  nmcli device connect "$IFACE" >/dev/null 2>&1 || true
  sleep 8

  NEW_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev {print $1; exit}')
  if [ -n "$NEW_CON" ] && [ "$NEW_CON" != "$AP_CON" ]; then
    echo 0 > "$FAIL_FILE"
    write_status "connected" ""
    log_event "INFO" "Auto-retry succeeded; reconnected to $NEW_CON"
  else
    ensure_ap_profile
    nmcli connection up "$AP_CON" >/dev/null 2>&1 || true
    for _ in $(seq 1 15); do ip -4 addr show "$IFACE" | grep -q "10.42.0.1" && break; sleep 0.5; done
    systemctl restart "$PORTAL_SVC" >/dev/null 2>&1 || true
    write_status "setup" "Connect to Wi-Fi $AP_SSID and open http://10.42.0.1"
    log_event "WARN" "15-minute auto-retry failed; returned to Frame-Setup AP mode"
  fi
  exit 0
fi

# Case 2: Normal client Wi-Fi connected
if [ -n "$ACTIVE_CON" ]; then
  systemctl stop "$PORTAL_SVC" >/dev/null 2>&1 || true
  if [ "$PREV_FAILS" -gt 0 ]; then
    log_event "INFO" "Wi-Fi recovered on $ACTIVE_CON after $PREV_FAILS failed check(s)"
  fi
  echo 0 > "$FAIL_FILE"
  echo 0 > "$RETRY_FILE"
  write_status "connected" ""
  exit 0
fi

# Case 3: Disconnected — increment consecutive failure count
systemctl stop "$PORTAL_SVC" >/dev/null 2>&1 || true
FAILS=$((PREV_FAILS + 1))
echo "$FAILS" > "$FAIL_FILE"
write_status "disconnected" ""

if [ "$FAILS" -lt 4 ]; then
  log_event "WARN" "Wi-Fi disconnected (check $FAILS/4)"
else
  start_setup_mode
fi
