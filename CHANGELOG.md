# Changelog

Newest on top. One entry per change: what, and why if it isn't obvious.

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
