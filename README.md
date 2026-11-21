# IONIQ 5 Gen5W — car-specific WiFi, battery, climate and Home Assistant tweaks

A **curated, car-specific derivative** of
[SCOURGE](https://github.com/nickles-lee/hkg_SCOURGE): it documents and
shares the work done on one 2021 IONIQ 5 Gen5W head unit (European `260128`
firmware, `5w.master.fumo.75`). It is not a fork of the upstream history and
not a replacement for it.

> **Origin — start here.** Everything below builds on
> **[nickles-lee/hkg_SCOURGE](https://github.com/nickles-lee/hkg_SCOURGE)**:
> the packages, build system, payloads and runbooks come from there. Read
> the upstream README, `docs/06-run-stuff.md` and `docs/07-packages.md`
> before using anything in this repository. This repository only adds the
> car-specific WiFi, battery, climate and Home Assistant work on top; see
> [`NOTICE`](NOTICE) for the full attribution and [`FORK.md`](FORK.md) if
> you want to publish your own derivative.

This is **not** a jailbreak guide, **not** a firmware image, and **not** a
copy of the OEM rootfs. It contains documentation, first-party reference
code, scripts and Home Assistant examples. Read
[`NOTICE`](NOTICE) and the upstream project first.

> **Status honesty.** Every item below is marked as car-validated,
> offline-validated or WIP. The owner's car is a single vehicle; your
> firmware, trim, APs and network will differ.
>
> **Security.** Do not post secrets, logs or personal data in issues. Report
> security problems privately as described in [`SECURITY.md`](SECURITY.md).

---

## What this repository is

- **Documentation** of the problems, diagnosis and fixes:
  - [WiFi: WPA2/WPA3 handshake failure, static IP, single-owner daemon,
    UI, fast reconnect](docs/01-wifi.md)
  - [Battery page, I-CAN signals, gauge, charging, V2L and limitations](docs/02-battery.md)
  - [Charge Port button → Home Assistant webhook → smart plug](docs/03-home-assistant.md)
  - [Interior/exterior temperature tile](docs/04-climate.md)
  - [Sensor/state catalogue and what is not available](docs/05-sensors.md)
  - [Android Auto findings: no AA stack in this firmware](docs/06-aa.md)
  - [Install, backup and rollback notes](docs/07-install.md)
  - [Prior art: review of a related Gen5W VM research repository](docs/08-prior-art.md)
- **Reference code** (first-party files, sanitised):
  - `reference/qml/` — `WifiPage.qml`, `BatteryPage.qml`, `ClimateTile.qml`,
    `TweaksPage.qml`
  - `reference/daemon/` — `wifi_daemon.c`, `battery_daemon.c`
  - `reference/systemd/` — service units
- **Scripts and examples**:
  - `scripts/install-wifi-ui.sh`, `scripts/wifi-always-on.sh`
  - `scripts/install-wifi-page.sh`, `scripts/install-battery-page.sh`
  - `scripts/add-climate-tile.py`
  - `scripts/install-door-hook.sh`
  - `scripts/home-assistant/charge-door.yaml`
  - `scripts/config/wifi.txt.sample`

Everything is **sanitised**: owner SSIDs, PSKs, LAN IPs, MACs, webhook IDs, HA
tokens and entity IDs are placeholders. Replace them with your own values.
The only literal credentials are the upstream product default account
(`car`/`electric`), which is a documented factory default, not a secret —
change it on your unit. The code is a reference to drop into the upstream
package layout; it is not a standalone build.

---

## Status matrix

| Area | State | Notes |
|---|---|---|
| WiFi UI (tabs, scan, Ping, Log) | **Car-validated** | New page installed; tabs visible; Ping/Log/Redes working |
| WiFi daemon (single owner, static IP, boot_off=0) | **Car-validated** | `wpa_state=COMPLETED`, internet, SSH; no ConnMan WiFi |
| WiFi fast reconnect + BSSID pin | **Car-validated** | retry 15 s, boot grace 20 s, `scan_ssid=1`, pin to the stronger AP |
| Scan with BSSID/freq + IP presets | **Car-validated / one path WIP** | `/scan` tested; join-with-IP not exercised end-to-end on a second SSID |
| Battery page + gauge + instant power | **Car-validated** | negative regen, peak/regen, capacity, charge/V2L, conditioning/winter |
| Battery daemon + charge-door hook | **Car-validated** | `/chargedoor` tests, hook fired, HA webhooks triggered |
| Charge Port → HA → plug | **Car-validated** | webhook + automation + physical plug confirmed |
| Climate tile (INT/EXT) | **Car-validated (visual)** | driver set temp + exterior; no measured cabin sensor |
| Sensor catalogue | **Car-observed / derived** | names/IDs from the owner's firmware; not every bit layout validated |
| Android Auto wireless | **Blocked** | this firmware has no AA projection stack; see docs/06 |

---

## The short version of what was needed

1. **Root and own the head unit** with the upstream SCOURGE tooling. All
   work was done on the owner's car, parked, with backups and rollback.
2. **WiFi**: the OEM ConnMan/supplicant stack fought our link. The car must
   own `wlan0` (`connmanctl disable wifi`, stop the OEM supervisor, run our
   own `wpa_supplicant -O`), use a **WPA2-PSK** SSID (a WPA2/WPA3 mixed SSID
   stalled in `4WAY_HANDSHAKE`), and apply a **static IPv4 address** because
   there is no DHCP client in the payload. Boot starts with the radio on
   (`boot_off=0`), the watchdog retries every 15 s, and the driver is pinned
   to the AP with the best signal at the parking spot.
3. **Battery**: one of the head unit's CAN interfaces (`can0`/`can1`,
   depending on enumeration; this car used `can1`) is I-CAN. `0x2FC` gives
   SoC and the
   **minimum** cell temperature; `0x326` gives cable/charging state. The
   useful heater number is `pwrInstantHeat + pwrInstantBattery` (kW), not
   `heatBatteryPercent`. A new page adds a signed drive/regen gauge,
   charging/target/time, capacity, low-SOC, V2L and conditioning/winter.
4. **Home Assistant**: the Charge Port tile calls
   `/chargedoor/toggle`; the battery daemon confirms the command in
   `door_finish()` and POSTs to two HA webhooks. HA turns a smart plug on/off.
   The car stores only webhook URLs (no HA token), and the webhooks are
   protected by their unguessable IDs.
5. **Climate tile**: `INT` is the driver's set temperature
   (`appClimateModel.levelDriver`), `EXT` is the ambient temperature
   (`ambienTemp`). The car does not expose a measured cabin temperature.
6. **AA**: the installed firmware has AirPlay/CarPlay projection only; the
   `CAndroidAuto` gate found in another firmware is not present here.
   Wireless AA would need an AA-capable projection stack first. The radio
   hardware does support AP+STA (BCM4359, `wl apsta=1`).

---

## Quick start

1. Read [`docs/07-install.md`](docs/07-install.md).
2. Start from a rooted head unit with the upstream SCOURGE packages.
3. Replace every placeholder (`<YOUR_SSID>`, `192.168.1.x`, `<HA_IP>`,
   `switch.your_plug`, webhook IDs, BSSIDs).
4. Build and install the daemon/UI with your own tooling, keeping backups.
5. Test one change at a time; keep a USB pen with rollback scripts.

---

## Attribution and licence

This work is based on **SCOURGE** by
[nickles-lee](https://github.com/nickles-lee/hkg_SCOURGE) and the SCOURGE
contributors. The upstream project, its packages, runbooks and tests made
this possible. See [`NOTICE`](NOTICE) and [`FORK.md`](FORK.md).

The AA/VM research of
[NecktiedHummingbird/ioniq-5-Reverse-Engineering](https://github.com/NecktiedHummingbird/ioniq-5-Reverse-Engineering)
was used as prior art; see [`docs/08-prior-art.md`](docs/08-prior-art.md).

Licensed under **AGPL-3.0-only**; see [`LICENSE`](LICENSE). The `LICENSE`
file keeps the upstream "or any later version" preamble; [`NOTICE`](NOTICE)
explains why this derivative is distributed under version 3 only.

No firmware images, OEM binaries, OEM-derived dumps, personal data or
secrets are included. The upstream product default account is not treated
as a secret; change it on your unit.
