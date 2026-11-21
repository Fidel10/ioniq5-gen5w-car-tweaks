#!/bin/sh
# SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
# SPDX-License-Identifier: AGPL-3.0-only
# Instala a nova pagina WiFi + daemon a partir da pen.
# Correr NO CARRO: Tweaks -> Scripts -> Refresh -> install-wifi-ui
#
# Mantem boot_off=0 (WiFi ligado) para poderes verificar a pagina.
# Para o OFF por defeito, correr depois: finalize-boot-off
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
UI="$HERE/wifi-ui"
OUT="$HERE/results/install-wifi-ui.txt"
mkdir -p "$HERE/results" 2>/dev/null
exec >"$OUT" 2>&1

echo "=== date ==="
date 2>/dev/null
echo "here=$HERE"

[ -f "$UI/WifiPage.qml" ] || { echo "FALTA $UI/WifiPage.qml"; exit 1; }
[ -f "$UI/wifi_daemon" ] || { echo "FALTA $UI/wifi_daemon"; exit 1; }

CFG=/rw_data/wifi/config.conf
Q=/app/share/AppHomeScreen/qml_eco3.0/HomeScreen/WifiPage.qml
QBAK=/rw_data/wifi/WifiPage.before-ui2.qml
DBAK=/rw_data/wifi/wifi_daemon.before-ui2

echo "=== 1/4 manter WiFi ligado (boot_off=0) ==="
cp -f "$CFG" "$CFG.before-ui2" 2>/dev/null
if grep -q "^boot_off=" "$CFG"; then
    sed -i "s/^boot_off=.*/boot_off=0/" "$CFG"
elif grep -q "^wlan_on=" "$CFG"; then
    sed -i "/^wlan_on=/a boot_off=0" "$CFG"
else
    printf "boot_off=0\n" >> "$CFG"
fi
sync
grep -E "^(boot_off|wlan_on|mode|ssid|static_ip)=" "$CFG" 2>/dev/null

echo "=== 2/4 instalar QML ==="
mount -o remount,rw / 2>/dev/null || true
[ -f "$Q" ] && cp -f "$Q" "$QBAK" 2>/dev/null
cp -f "$UI/WifiPage.qml" "$Q"
chmod 644 "$Q" 2>/dev/null
rm -rf /root/.cache/AppHomeScreen /root/.cache/qmlcache /tmp/qmlcache /tmp/qt-qml-cache 2>/dev/null
sync
mount -o remount,ro / 2>/dev/null || true
md5sum "$Q" 2>/dev/null

echo "=== 3/4 reiniciar AppHomeScreen ==="
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
    echo "UI_OK"
else
    echo "UI_FAIL -> rollback"
    if [ -f "$QBAK" ]; then
        mount -o remount,rw / 2>/dev/null || true
        cp -f "$QBAK" "$Q"
        sync
        mount -o remount,ro / 2>/dev/null || true
        rm -rf /root/.cache/AppHomeScreen /root/.cache/qmlcache /tmp/qmlcache /tmp/qt-qml-cache 2>/dev/null
        restart_ui
        sleep 3
        pidof AppHomeScreen >/dev/null 2>&1 && echo "UI_RESTORED" || echo "UI_REBOOT_NEEDED"
    fi
fi

echo "=== 4/4 trocar daemon (WiFi reinicia; o script pode cair aqui) ==="
if [ -f /rw_data/wifi/wifi_daemon ]; then
    cp -f /rw_data/wifi/wifi_daemon "$DBAK" 2>/dev/null
fi
cp -f "$UI/wifi_daemon" /rw_data/wifi/wifi_daemon
chmod 755 /rw_data/wifi/wifi_daemon 2>/dev/null
chown 0:0 /rw_data/wifi/wifi_daemon 2>/dev/null
sync
ls -l /rw_data/wifi/wifi_daemon 2>/dev/null
echo "restart agendado em 2 s"
if command -v nohup >/dev/null 2>&1; then
    nohup sh -c 'sleep 2; systemctl restart wifi-daemon.service' >/dev/null 2>&1 &
else
    ( sleep 2; systemctl restart wifi-daemon.service ) >/dev/null 2>&1 &
fi
echo "=== done (o log fica em store/results/install-wifi-ui.txt) ==="
