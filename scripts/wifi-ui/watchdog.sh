#!/bin/sh
# SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
# SPDX-License-Identifier: AGPL-3.0-only
# Watchdog pos-instalacao: reinicia o daemon, espera COMPLETED+IP e, se
# falhar em ~50 s, repoe o daemon anterior (mantendo boot_off=0).
# Uso: watchdog.sh <pen-result> <bin> <backup-bin>
OUT=$1
BIN=$2
BAK=$3
LOG=/rw_data/wifi/alwayson-watch.log
{
    echo "=== $(date 2>/dev/null) ==="
    sleep 2
    systemctl restart wifi-daemon.service >/dev/null 2>&1 || true
    i=0
    while [ "$i" -lt 25 ]; do
        st=$(wpa_cli -p /var/run/wpa_supplicant -i wlan0 status 2>/dev/null)
        if echo "$st" | grep -q "wpa_state=COMPLETED" && ip -4 addr show wlan0 2>/dev/null | grep -q "inet "; then
            echo "CONNECTED after $((i * 2)) s"
            echo "CONNECTED" >> "$OUT" 2>/dev/null
            exit 0
        fi
        i=$((i + 1))
        sleep 2
    done
    echo "ROLLBACK: sem ligacao em 50 s; a repor daemon anterior"
    if [ -f "$BAK" ]; then
        cp -f "$BAK" "$BIN"
        chmod 755 "$BIN"
        sync
        systemctl restart wifi-daemon.service >/dev/null 2>&1 || true
        echo "ROLLED_BACK" >> "$OUT" 2>/dev/null
    else
        echo "NO_BACKUP" >> "$OUT" 2>/dev/null
    fi
} >> "$LOG" 2>&1
