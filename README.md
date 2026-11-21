# Seeing the World Together: Pi Photo Frame

Wall photo frame. Photos added to the iPhone album **"Maya_Sam_seeing_the_world_together"** → copied to **Immich on the Pi** → shown full-screen by **ImmichFrame**.

---

## Hardware
- Raspberry Pi 5 (8 GB) + CanaKit 45 W supply. **Use this supply only.** It gives the Pi 5V/5A, which the hard drive needs.
- 128 GB microSD: system only (Pi OS Lite 64-bit)
- Portable HDD: ext4, mounted at `/mnt/frame`, plugged into a **blue USB 3 port**
- Screen: HDMI port **next to the USB-C power port**. Test monitor now, InnoView 16" later.


## How it fits together
iPhone (Immich app) --Tailscale--> Immich (Docker, port 2283)
|
ImmichFrame (Docker, port 9090, Pi-only)
|
kiosk-wrapper.py (port 9091) <-- wifi-watchdog / setup-portal
|
kiosk.service: Cage + Chromium, full-screen --> screen
### Where things live
| What | Where |
|---|---|
| System + this repo | SD card, `~/frame` |
| Photos | `/mnt/frame/immich/library` |
| Database | `/mnt/frame/immich/postgres` |
| Database auto-backups (daily 2 AM, keeps 14) | `/mnt/frame/immich/library/backups` |
| Docker data | `/mnt/frame/docker` |
| Kiosk & Wi-Fi logs | `/mnt/frame/logs/{kiosk,wifi}` (symlinked at `~/frame/logs`) |
| Wi-Fi runtime state & AP scans | `/run/frame-wifi/` (`status.json`, `networks.json`) |
| Frame settings | `~/frame/immichframe/config/Settings.yml` |
| Passwords + API key | **Password manager only. Never in git.** |

## Access
- Everything goes through **Tailscale**. No router port forwarding.
- Immich (web + app): `http://100.78.211.78:2283`. Tailscale must be on.
- Slideshow: `http://localhost:9090` (via Wi-Fi status wrapper on `http://127.0.0.1:9091`). **Only the Pi itself** can open it.
- Wi-Fi setup portal (offline/AP fallback): join Wi-Fi `Frame-Setup` (`frame-says-I-love-you`) and open `http://10.42.0.1` (Tailscale/VPN must be off).
- SSH: `ssh admin@raspberrypi` (over Tailscale)


## Repo layout
```text
~/frame/
├── README.md, CHANGELOG.md
├── .gitignore                 keeps .env, *.key, and logs/ out of git
├── logs/                      symlink → /mnt/frame/logs (NOT in git)
├── immich/
│   ├── docker-compose.yml
│   ├── .env                   real settings + DB password (NOT in git)
│   └── .env.example           same, password blanked (in git)
├── immichframe/
│   ├── docker-compose.yml
│   └── config/
│       ├── Settings.yml       album ID, clock, notes, interval
│       └── api.key            Immich API key (NOT in git)
├── wifi/                      captive portal, watchdog, and kiosk gate
│   ├── kiosk-wrapper.py       → /usr/local/bin/kiosk-wrapper.py
│   ├── setup-portal.py        → /usr/local/bin/setup-portal.py
│   ├── wifi-watchdog.sh       → /usr/local/bin/wifi-watchdog.sh
│   └── systemd/
│       ├── kiosk-wrapper.service  → /etc/systemd/system/kiosk-wrapper.service
│       ├── wifi-portal.service    → /etc/systemd/system/wifi-portal.service
│       ├── wifi-watchdog.service  → /etc/systemd/system/wifi-watchdog.service
│       └── wifi-watchdog.timer    → /etc/systemd/system/wifi-watchdog.timer
└── system/                    copies of Pi config files
    ├── daemon.json            → /etc/docker/daemon.json
    ├── docker-override.conf   → /etc/systemd/system/docker.service.d/override.conf
    ├── fstab-line.txt         → add to /etc/fstab
    ├── kiosk.service          → /etc/systemd/system/kiosk.service
    ├── kiosk-refresh.service  → /etc/systemd/system/kiosk-refresh.service
    └── kiosk-refresh.timer    → /etc/systemd/system/kiosk-refresh.timer
```

## Everyday use
- **Add a photo:** put it in the iPhone album, then open the Immich app.
- **Add a note:** in Immich, open the photo → ⓘ → Add a description.
- **Move to a new Wi-Fi network:** plug in the frame; after 5 quick checks (~30s), it opens the `Frame-Setup` hotspot (`frame-says-I-love-you`). Join it on your phone (with Tailscale/VPN off), open `http://10.42.0.1`, pick your Wi-Fi, and enter the password. After a 40-second stability check, the slideshow starts automatically.
- ⚠️ **Never tap "Free up space" in the Immich app.** It deletes photos from iCloud.

## Handy commands
| Do | Command |
|---|---|
| Restart the screen | `sudo systemctl restart kiosk` |
| Screen service log | `journalctl -u kiosk -n 30` |
| Chromium browser log | `tail -n 30 ~/frame/logs/kiosk/chromium.log` |
| Wi-Fi watchdog & portal log | `tail -n 30 ~/frame/logs/wifi/wifi.log` |
| Check Wi-Fi portal status | `cat /run/frame-wifi/status.json` |
| Daily refresh timer | `systemctl list-timers kiosk-refresh.timer` |
| Immich status | `cd ~/frame/immich && docker compose ps` |
| ImmichFrame log | `cd ~/frame/immichframe && docker compose logs --tail 30` |

## Update routine (every time)
Update **Immich first, then ImmichFrame**. ImmichFrame has to work with whatever Immich version is running.
1. Read the release notes on GitHub. Look for breaking changes.
2. Back up the database: Immich web → Administration → Jobs → Create job → **Backup Database**.
3. **Immich:** in `immich/`, download that version's setup file:
   `wget -O docker-compose.yml https://github.com/immich-app/immich/releases/download/vX.Y.Z/docker-compose.yml`
   Then set `IMMICH_VERSION=vX.Y.Z` in **both** `.env` and `.env.example`.
4. **ImmichFrame:** change the `image:` version in `immichframe/docker-compose.yml`.
5. In each folder: `docker compose pull && docker compose up -d`
6. Check: the photos show on the screen, and the iPhone app connects.
7. Commit, and add a CHANGELOG entry.

**If it breaks:** go back to the old version in git, **and** restore the database backup from step 2.

## Rebuild from scratch (if the SD card dies)
Photos, database, logs, and Docker data are on the hard drive, so they survive.
1. Flash Pi OS Lite 64-bit with Raspberry Pi Imager (user `admin`, SSH key, Wi-Fi).
2. Update the system. Set SSH to key-only. Install git.
3. Install Tailscale with SSH on. In the Tailscale admin console, **disable key expiry** for the Pi.
4. Mount the drive: `sudo mkdir -p /mnt/frame`, add `system/fstab-line.txt` to `/etc/fstab`, `sudo mount -a`.
5. Install Docker. Copy `system/daemon.json` to `/etc/docker/`, and `system/docker-override.conf` to `/etc/systemd/system/docker.service.d/override.conf`. Then `sudo systemctl daemon-reload && sudo systemctl restart docker`.
6. `git clone` this repo to `~/frame` and link logs: `ln -sfn /mnt/frame/logs ~/frame/logs`.
7. Immich: `cp immich/.env.example immich/.env`, put the DB password back in, then `docker compose up -d` in `immich/`.
8. ImmichFrame: put the API key into `immichframe/config/api.key` (`chmod 600`), then `docker compose up -d` in `immichframe/`.
9. Wi-Fi portal & watchdog: copy `wifi/*.py` and `wifi/wifi-watchdog.sh` to `/usr/local/bin/` (`chmod +x`), copy `wifi/systemd/*` to `/etc/systemd/system/`, `sudo mkdir -p /mnt/frame/logs/wifi`, then `sudo systemctl daemon-reload && sudo systemctl enable --now kiosk-wrapper.service wifi-watchdog.timer`.
10. Screen: `sudo apt install -y cage chromium`, `sudo useradd -m -G video,render,input kiosk`, `sudo mkdir -p /mnt/frame/logs/kiosk && sudo chown -R kiosk:kiosk /mnt/frame/logs/kiosk`, copy `system/kiosk*` to `/etc/systemd/system/`, then `sudo systemctl daemon-reload && sudo systemctl enable --now kiosk kiosk-refresh.timer`.


## Known risks / to do
- [x] Tailscale: disable key expiry for the Pi.
- [x] Wi-Fi at the frame's new home: needs a setup mode, or her Wi-Fi added ahead of time.
- [x] Night mode: screen off/on schedule (configured via crontab: off 2  AM, on 5 AM PT).
- [ ] Immich update available (3.3.5 → 3.3.6)