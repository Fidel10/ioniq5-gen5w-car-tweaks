#!/bin/sh
# SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
# SPDX-License-Identifier: AGPL-3.0-only
# Instala a nova pagina Battery (monitorizacao) no carro, com rollback.
#   ./install-battery-page.sh [car@192.168.1.228] [porta]
set -eu
CAR=${1:-car@192.168.1.228}
PORT=${2:-2222}
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SSH="ssh -p $PORT -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new"

echo "== enviar =="
SRC="$DIR/BatteryPage.qml"
[ -f "$SRC" ] || SRC="$DIR/../reference/qml/BatteryPage.qml"
$SSH "$CAR" 'cat > /tmp/BatteryPage.qml' < "$SRC"

echo "== instalar =="
$SSH "$CAR" '
set -e
Q=/app/share/AppHomeScreen/qml_eco3.0/HomeScreen/BatteryPage.qml
B=/rw_data/tweaks/BatteryPage.before-gauge.qml
mkdir -p /rw_data/tweaks 2>/dev/null || true
mount -o remount,rw / 2>/dev/null || true
if [ -f "$Q" ]; then cp -f "$Q" "$B"; fi
cp -f /tmp/BatteryPage.qml "$Q"
chmod 644 "$Q"
rm -rf /root/.cache/AppHomeScreen /root/.cache/qmlcache /tmp/qmlcache /tmp/qt-qml-cache 2>/dev/null
sync
mount -o remount,ro / 2>/dev/null || true
md5sum "$Q"
'

echo "== reiniciar AppHomeScreen =="
$SSH "$CAR" '
launcher_pid=""
for p in /proc/[0-9]*; do
    [ -r "$p/comm" ] || continue
    if [ "$(cat "$p/comm" 2>/dev/null)" = "AppLauncher" ]; then
        launcher_pid="${p#/proc/}"; break
    fi
done
if [ -n "$launcher_pid" ] && [ -r "/proc/$launcher_pid/environ" ]; then
    for var in DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR WAYLAND_DISPLAY QT_QPA_PLATFORM; do
        val=$(tr "\0" "\n" < "/proc/$launcher_pid/environ" 2>/dev/null | grep "^$var=" | head -n 1 | cut -d= -f2-)
        [ -n "$val" ] && export "$var=$val"
    done
fi
restart_ui() {
    if command -v dbus-send >/dev/null 2>&1; then
        dbus-send --session --type=method_call --dest=com.lge.avn.applauncher /Request \
            com.lge.avn.applauncher.request.terminate int32:11 >/dev/null 2>&1 || true
        sleep 2
        for i in 1 2 3; do
            dbus-send --session --type=method_call --dest=com.lge.avn.applauncher /Request \
                com.lge.avn.applauncher.request.launch int32:11 \
                string:AppHomeScreen string:/app/bin/AppHomeScreen >/dev/null 2>&1 && break
            sleep 2
        done
    fi
}
restart_ui
sleep 3
if pidof AppHomeScreen >/dev/null 2>&1; then
    echo UI_OK
else
    echo UI_FAIL_ROLLBACK
    Q=/app/share/AppHomeScreen/qml_eco3.0/HomeScreen/BatteryPage.qml
    B=/rw_data/tweaks/BatteryPage.before-gauge.qml
    if [ -f "$B" ]; then
        mount -o remount,rw / 2>/dev/null || true
        cp -f "$B" "$Q"
        sync
        mount -o remount,ro / 2>/dev/null || true
        rm -rf /root/.cache/AppHomeScreen /root/.cache/qmlcache /tmp/qmlcache /tmp/qt-qml-cache 2>/dev/null
        restart_ui
        sleep 3
        pidof AppHomeScreen >/dev/null 2>&1 && echo UI_RESTORED || echo UI_REBOOT_NEEDED
    else
        echo NO_BACKUP
    fi
fi
'
echo "== fim =="
