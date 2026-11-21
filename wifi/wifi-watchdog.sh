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
  local extra="${3:-}"
  if [ -n "$extra" ]; then
    printf '{"mode":"%s","ssid":"%s","password":"%s","url":"http://10.42.0.1","message":"%s",%s}\n' \
      "$mode" "$AP_SSID" "$AP_PASS" "$msg" "$extra" > "$STATUS_FILE.tmp"
  else
    printf '{"mode":"%s","ssid":"%s","password":"%s","url":"http://10.42.0.1","message":"%s"}\n' \
      "$mode" "$AP_SSID" "$AP_PASS" "$msg" > "$STATUS_FILE.tmp"
  fi
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
}

trigger_connected_wait() {
  local ssid="$1"
  local ready_at=$(( $(date +%s) + 40 ))
  write_status "connected_wait" "Connected to $ssid. Starting slideshow in 40 seconds..." \
    "\"connected_ssid\":\"$ssid\",\"ready_at\":$ready_at"
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
  log_event "ERROR" "Wi-Fi failed 5 connection attempts; entered Frame-Setup AP mode (10.42.0.1)"
}

ACTIVE_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev {print $1; exit}')
CUR_MODE=$(python3 -c 'import json; print(json.load(open("/run/frame-wifi/status.json")).get("mode",""))' 2>/dev/null || echo "")

# Do not interrupt an active portal password test
if [ "$CUR_MODE" = "testing" ]; then
  exit 0
fi

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
    trigger_connected_wait "$NEW_CON"
    log_event "INFO" "Auto-retry succeeded; reconnected to $NEW_CON (40s stability wait)"
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
  echo 0 > "$RETRY_FILE"
  if [ "$CUR_MODE" != "ready" ] && [ "$CUR_MODE" != "connected_wait" ] && [ "$CUR_MODE" != "connected" ]; then
    trigger_connected_wait "$ACTIVE_CON"
    log_event "INFO" "Wi-Fi connected to $ACTIVE_CON (40s stability wait)"
  fi
  exit 0
fi

# Case 3: Disconnected (at boot or runtime drop) — immediately hide slides and run 5 fast connection attempts
systemctl stop "$PORTAL_SVC" >/dev/null 2>&1 || true
log_event "WARN" "Wi-Fi disconnected; starting 5 quick connection attempts"

for ATTEMPT in 1 2 3 4 5; do
  write_status "disconnected" "Connecting to saved Wi-Fi (Attempt $ATTEMPT/5)..."
  nmcli device connect "$IFACE" >/dev/null 2>&1 || true
  sleep 6
  NEW_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev {print $1; exit}')
  if [ -n "$NEW_CON" ] && [ "$NEW_CON" != "$AP_CON" ]; then
    echo 0 > "$RETRY_FILE"
    trigger_connected_wait "$NEW_CON"
    log_event "INFO" "Wi-Fi connected on attempt $ATTEMPT/5 to $NEW_CON (40s stability wait)"
    exit 0
  fi
done

start_setup_mode
