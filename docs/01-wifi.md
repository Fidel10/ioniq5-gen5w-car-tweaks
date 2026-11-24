# WiFi: WPA2/WPA3 handshake, static IP, single-owner daemon and fast reconnect

Status: **car-validated** on a 2021 IONIQ 5 Gen5W (EU `260128`,
`5w.master.fumo.75`), except the join-with-IP path: `/scan` is
car-validated, but joining a new network with a new IP/subnet has not been
exercised end-to-end on a second SSID (WIP). All IPs/SSIDs below are
examples; replace them.

## Symptoms

- The car associated to the home SSID but never obtained an address.
- `wpa_cli status` stayed in `wpa_state=4WAY_HANDSHAKE` (or repeatedly
  `SCANNING`) while the AP showed the client as connected.
- The OEM WiFi stack (ConnMan + `supplicantmanager`) fought our link:
  disconnects, power-save latency, routes rewritten, and unreliable SSH.
- After a reboot the radio was sometimes off and needed a manual toggle.
- When it did connect, it could take a minute or more, especially when
  coming home with a weak signal.

## Root causes

1. **Mixed WPA2/WPA3 (SAE) security.** The main SSID was configured as
   WPA2/WPA3 mixed with PMF. The head unit's supplicant stalled in the
   4-way handshake. A pure **WPA2-PSK/AES** SSID on an isolated IoT VLAN
   (a placeholder `<IOT_SSID>`, not the mixed main SSID) connected
   immediately. Confirm the SSID settings in the controller: `versionPsk`
   (2 = WPA2, 4 = SAE/mixed) and `pmfMode`.
2. **Two managers.** The OEM ConnMan and its supervisor wanted to own
   `wlan0`; our daemon also wanted it. The fix is single ownership, not
   more retries: disable ConnMan WiFi, stop the OEM supervisor, run our
   own `wpa_supplicant -O`, and apply addressing ourselves.
3. **No DHCP client in the payload.** The head unit has no `udhcpc` /
   `dhcpcd`. The daemon must apply a **static IPv4 address, mask and
   gateway**. Joining a new network therefore needs the subnet too.
4. **No default route.** If the interface already had an address but no
   default route, only the local subnet worked (`ping gateway` OK,
   everything else failed). The watchdog must ensure the route, not only
   the address.
5. **Two APs, one SSID.** The scan list has one row per **BSSID**, not per
   SSID. Marking rows by SSID makes both APs look "connected". The car is
   associated to exactly one BSSID. Pin the BSSID with the best signal at
   the parking spot if the controller's AP lock is not enough.
6. **Signal.** A parked car at -79 dBm will always associate more slowly
   than one at -60 dBm. Rain and AP placement matter. No software trick
   fixes weak RF.

## What the working design does

### Single owner

- `connmanctl disable wifi`
- stop `supplicantmanager.service` and `supplicantmanager.path`
- run `wpa_supplicant` with our control socket (`-O`) and no ConnMan DBus
- keep power save off (`iw dev wlan0 set power_save off`)
- re-add the firewall rules for SSH, the daemon HTTP port and ICMP on
  every watchdog cycle (OEM rules do not survive reboots)
- cap `daemon.log`, `wpa_supplicant.log` and `ssh.log` at **1 MiB** each,
  truncating in place (the systemd unit, wpa_supplicant and dropbear keep
  their descriptors open; a rename would leak the space on the 1.2 GB
  `/rw_data` partition)

Reference: `reference/daemon/wifi_daemon.c`, service unit in
`reference/systemd/wifi-daemon.service`.

### Addressing

- `static_ip`, `static_mask`, `static_gw` live in the daemon config
  (`/rw_data/wifi/config.conf`).
- The daemon applies them after association; there is no DHCP.
- The route is `default via <static_gw> dev wlan0`.
- If the interface has a stale or wrong address, flush it before applying
  the configured one. Do not skip the route when an address already exists.

### Boot and reconnect

- `boot_off=0`, `wlan_on=1`, `mode=client`: the radio starts on and the
  client mode is applied at boot.
- Watchdog re-apply: **15 s** instead of 65 s when not associated.
- Supplicant boot grace: **20 s** (the OEM stack had 90 s; that was a
  minute of unnecessary waiting on this unit).
- `scan_ssid=1` is set for every network; harmless for visible SSIDs and
  required for hidden ones.
- Optional BSSID pin: `client_bssid=<AP BSSID>` in the config. This avoids
  scanning the weaker AP and roaming. Clear it when the car moves or when
  joining another network (the join endpoint clears it).
- Power save stays off; it adds 0.5–2.5 s to every packet on this radio.

### UI

`reference/qml/WifiPage.qml` is a full replacement page:

- Tabs: **WiFi | Redes | Ping | SSH | Log**
- WiFi: compact summary (on/off, SSID, signal + bar, SSH/port), connect /
  disconnect / band buttons.
- Redes: scan with SSID, security, dBm, percentage, frequency and BSSID
  suffix; only the **current BSSID** is marked "ligado"; tap a network to
  open the password dialog with an on-screen keyboard.
- Join dialog: **LAN 1.x**, **IoT 2.x**, **Atual** presets. The selected
  address/gateway is sent to `/client/join` and applied by the daemon; the
  BSSID pin is cleared for the new network. The page preselects the 2.x
  preset for the SSID set in the optional `iotSsid` property; leave it empty
  to always start on 1.x. **WIP:** `/scan` is car-validated; the
  join-with-IP path was not exercised end-to-end on a second SSID.
- Ping: several targets (internet, router, second subnet), raw output.
- Log: full-width console with Daemon/WPA/SSH sources.
- SSH: switch, port, command, USB key import.

The page is installed under
`/app/share/AppHomeScreen/qml_eco3.0/HomeScreen/WifiPage.qml` and needs the
upstream `WifiButton`/`WifiSwitch`/`QText` components. The OEM `Advanced.qml`
only needs the page instance; do not redistribute the OEM file.

### Daemon API

- `GET /status` — connection, IP, signal, SSH, scan/join state.
- `GET /scan` — networks with `ssid`, `bssid`, `freq`, `signal`, `security`.
- `POST /wlan?on=0|1` — radio.
- `POST /client/connect`, `/client/disconnect`.
- `POST /client/band?value=2.4|5` — band preference (BSSID placeholders in
  the reference code; set your own AP BSSIDs).
- `POST /client/join?ssid=…&psk=…[&ip=…&gw=…&mask=…]` — join and apply the
  static profile.
- `GET /ping?host=…` — 2-packet ping from the car.
- `GET /logs?source=daemon|wpa|ssh` — live console.

## Diagnosing

On the car (SSH):

```sh
wpa_cli -p /var/run/wpa_supplicant -i wlan0 status
wpa_cli -p /var/run/wpa_supplicant -i wlan0 signal
wpa_cli -p /var/run/wpa_supplicant -i wlan0 scan_results
ip -4 addr show wlan0
ip route
ping -c2 <gateway>
ping -c2 1.1.1.1
ping -c2 google.com
tail -40 /rw_data/wifi/daemon.log
```

The cap truncates the file in place, so `tail` right after a cap can
temporarily show nothing; retry once the daemon logs again.

On a host (SSH tunnel to the car's localhost API):

```sh
ssh -N -L 18090:127.0.0.1:8090 car@<CAR_IP>
curl http://127.0.0.1:18090/status
curl http://127.0.0.1:18090/scan
```

Notes:

- `iw dev wlan0 link` can print `Not connected` on this driver/firmware even
  while `wpa_cli` reports `COMPLETED` and traffic flows. Trust `wpa_cli`,
  `ip` and real pings.
- `signal` is RSSI in dBm (negative; -79 is weak, -60 is good). The scan
  list may show a few dBm better than the live link.
- If the gateway pings but nothing outside does: missing default route or
  DNS. If `1.1.1.1` works but names do not: DNS. If the second subnet does
  not work: inter-VLAN routing/firewall.

## Tuning at home

- Prefer the AP with the best RSSI at the parking spot; pin its BSSID.
- Keep the controller's AP lock and the BSSID pin consistent.
- Use 2.4 GHz for range; 5 GHz only if the signal is good.
- If both APs are around -80 dBm, a mesh node or AP closer to the car is the
  real fix.
- Keep `boot_off=0` so the car reconnects in the background while it is on.

## Install and rollback

The upstream package (or a pen payload) builds the daemon and copies the
page. Keep backups:

- `/rw_data/wifi/wifi_daemon.before-*`
- `/rw_data/wifi/WifiPage.before-*`
- `/rw_data/wifi/config.conf.before-*`

A daemon restart drops WiFi for a few seconds and cuts SSH; use a local
watchdog that restores the previous daemon if `wpa_state` is not
`COMPLETED` with an IP after ~50 s. The page update only restarts
AppHomeScreen and does not drop WiFi.

Do not expose the daemon's write endpoints (preheat, door, join) to the LAN;
it binds to `127.0.0.1` for a reason.
