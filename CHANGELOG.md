# Changelog

Newest on top. One entry per change: what, and why if it isn't obvious.

## 2026-11-21: Maintenance suite (M1-M3) and Immich v3 update
- Added `maintenance/frame-status` (`/usr/local/bin/frame-status`) for single-screen read-only health checks across systemd units, Docker stacks, Wayland `HDMI-A-1` state, Wi-Fi wrapper mode, thermals/disk, and latest DB backup
- Added `maintenance/deploy` (`/usr/local/bin/deploy`) for dry-run diffing and selective syncing/reloading from `~/frame` to live system paths and `kiosk` crontab
- Added `maintenance/safe-update` (`/usr/local/bin/safe-update`) for pre-update DB dumps + Git tags (`prep`), single-stack updates (`apply`), and tagged rollbacks (`rollback`), and verified with an Immich `v3` update

## 2026-11-21: Wi-Fi captive portal, watchdog recovery, and kiosk display gating
- Configured `Frame-Setup` AP mode (`10.42.0.1`) on 2.4 GHz Channel 6 with PMF disabled (`pmf disable`, `group ccmp`) and captive-portal probe redirects (`/hotspot-detect.html`, `/generate_204`, `/connecttest.txt`, `/ncsi.txt`) for seamless mobile setup
- Replaced the 4-minute startup wait with a 5-attempt rapid connection loop (`OnBootSec=5s`) in `wifi-watchdog.sh` that enters `Frame-Setup` AP mode immediately on failure and auto-retries saved Wi-Fi every 15 minutes when idle
- Updated `kiosk-wrapper.py` to block cached slides whenever offline (`disconnected` / `testing`), keep the setup overlay locked during credential checks, and display a 40-second connection stability countdown (`connected_wait`) before launching the slideshow
- Added `CONNECT_LOCK` concurrency protection and UUID-based duplicate profile cleanup in `setup-portal.py` so re-entered networks cleanly replace older NetworkManager profiles
- Consolidated event-only Wi-Fi and service logs under `/mnt/frame/logs/{wifi,kiosk}/` and symlinked `~/frame/logs` (ignored in `.gitignore`)

## 2026-11-18: Scheduled display power automation
- Configured `kiosk` user crontab (`UID 1001`, `WAYLAND_DISPLAY=wayland-0`) to power off `HDMI-A-1` at 2:00 AM and power it back on at 5:00 AM PST via `wlr-randr`

## 2026-11-17: Kiosk logging, healthcheck, daily refresh, and cursor fix
- Added Chromium logging (`--enable-logging --log-file=/mnt/frame/logs/kiosk/chromium.log --v=0`) and disabled background timer throttling in `kiosk.service` so browser/JS freezes can be diagnosed on the HDD without wearing out the SD card
- Added `kiosk-refresh.timer` and `kiosk-refresh.service` to restart `kiosk.service` daily at 4:00 AM, preventing multi-day Chromium renderer stalls
- Added a TCP healthcheck to `immichframe/docker-compose.yml` so container status reflects actual web UI availability
- Added `99-ignore-hdmi-cec.rules` (`udev`) to ignore HDMI-CEC virtual pointer devices (`vc4-hdmi-*`) in `libinput`, eliminating the persistent mouse cursor on the display

## 2026-11-17: Kiosk logging, healthcheck, and daily refresh
- Added Chromium logging (`--enable-logging --log-file=/mnt/frame/logs/kiosk/chromium.log --v=0`) and disabled background timer throttling in `kiosk.service` so browser/JS freezes can be diagnosed on the HDD without wearing out the SD card
- Added `kiosk-refresh.timer` and `kiosk-refresh.service` to restart `kiosk.service` daily at 4:00 AM, preventing multi-day Chromium renderer stalls
- Added a Docker `healthcheck` to `immichframe/docker-compose.yml` so container status reflects actual web UI availability

## 2026-11-09: Display working
- ImmichFrame v1.0.39.0 in Docker, on Immich's network (`immich_default`), reads the album with a read-only API key
- Slideshow port locked to the Pi only (`127.0.0.1:9090`). No other device can view it.
- `kiosk.service`: Cage + Chromium full-screen, runs as the `kiosk` user (no admin rights), restarts if it crashes
- The screen waits until Immich and ImmichFrame are both ready, so no error face at startup
- Docker waits for the hard drive (`RequiresMountsFor=/mnt/frame`), so it never writes to the SD card by mistake
- Reboot test passed: photos come back on their own
- Added crontab Night mode: screen off 11 PM, on 6 AM Pacific Time Zone.
- Tailscale key expiry disabled, iPhone VPN On Demand on, GitHub 2FA on
## 2026-11-03: Basic setup working
- Pi OS Lite 64-bit installed, Wi-Fi connected
- Tailscale installed (signed in with GitHub), Tailscale SSH on
- HDD formatted ext4, mounted at `/mnt/frame` with `nofail` (Pi still starts up if the drive is missing)
- Docker installed. Data stored on the HDD, logs capped at 3 × 10 MB
- Immich v3.3.5 installed. Storage template: YYYY/MM/DD
- iPhone Immich app: backs up one album only, sync albums on
- Test: a photo added on iPhone showed up in Immich ✅
