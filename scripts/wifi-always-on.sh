#!/bin/sh
# SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
# SPDX-License-Identifier: AGPL-3.0-only
# Liga o WiFi por defeito (boot_off=0, wlan_on=1), instala o daemon com
# retry de 15 s e scan_ssid, reinicia e valida. Se nao houver ligacao em
# ~50 s, repoe o daemon anterior automaticamente.
# Correr NO CARRO: Tweaks -> Scripts -> Refresh -> wifi-always-on
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
UI="$HERE/wifi-ui"
OUT="$HERE/results/wifi-always-on.txt"
mkdir -p "$HERE/results" 2>/dev/null
exec >"$OUT" 2>&1

echo "=== date ==="; date 2>/dev/null
[ -f "$UI/wifi_daemon" ] || { echo "FALTA $UI/wifi_daemon"; exit 1; }
[ -f "$UI/watchdog.sh" ] || { echo "FALTA $UI/watchdog.sh"; exit 1; }

CFG=/rw_data/wifi/config.conf
BIN=/rw_data/wifi/wifi_daemon
BAK=/rw_data/wifi/wifi_daemon.before-alwayson
[ -f "$CFG" ] || { echo "FALTA $CFG"; exit 1; }
[ -f "$BIN" ] && cp -f "$BIN" "$BAK"
cp -f "$CFG" "$CFG.before-alwayson" 2>/dev/null || true

set_key() {
    key=$1; val=$2
    if grep -q "^$key=" "$CFG"; then
        sed -i "s|^$key=.*|$key=$val|" "$CFG"
    else
        printf "%s=%s\n" "$key" "$val" >> "$CFG"
    fi
}

# WiFi sempre ligado (sem "off por defeito").
set_key boot_off 0
set_key wlan_on 1
set_key mode client
sync

echo "=== config ==="
grep -E "^(ssid|static_ip|static_gw|boot_off|wlan_on|mode|ssh|ssh_port)=" "$CFG" 2>/dev/null
echo "psk=***"

echo "=== instalar daemon ==="
cp -f "$UI/wifi_daemon" "$BIN"
chmod 755 "$BIN"
chown 0:0 "$BIN" 2>/dev/null || true
cp -f "$UI/watchdog.sh" /rw_data/wifi/alwayson-watch.sh
chmod 755 /rw_data/wifi/alwayson-watch.sh
sync

echo "=== agendar restart + verificacao ==="
nohup sh /rw_data/wifi/alwayson-watch.sh "$OUT" "$BIN" "$BAK" >/dev/null 2>&1 &
echo "watchdog iniciado; o WiFi vai reiniciar em 2 s"
echo "log: /rw_data/wifi/alwayson-watch.log"
echo "=== done ==="
