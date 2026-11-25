#!/bin/sh
# SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
# SPDX-License-Identifier: AGPL-3.0-only
# Install (or roll back) the prepared ClimateTile/TweaksPage layout fixes.
# Run from the host; the script copies the QML over SSH and restarts
# AppHomeScreen through AppLauncher.
#
# Usage:
#   ./install-ui-fixes.sh [car@host] [port]
#   ./install-ui-fixes.sh --rollback [car@host] [port]
#   CAR=car@host PORT=2222 ./install-ui-fixes.sh
#
# The QML is prepared, not yet car-validated visually. Backups are
# /rw_data/tweaks/*.before-layoutfix.qml and are created only once, so the
# first run preserves the stock files. / is remounted read-write only for
# the copy; an EXIT/signal trap always tries to remount it read-only again.
# WiFi/SSH are not touched; only AppHomeScreen is restarted.
set -eu
MODE=install
if [ "${1:-}" = "--rollback" ]; then MODE=rollback; shift; fi
CAR=${1:-${CAR:-car@192.168.1.228}}
PORT=${2:-${PORT:-2222}}
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SSH="ssh -p $PORT -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new"

CLIMATE="$DIR/../reference/qml/ClimateTile.qml"
TWEAKS="$DIR/../reference/qml/TweaksPage.qml"

if [ "$MODE" = install ]; then
    [ -f "$CLIMATE" ] || { echo "missing $CLIMATE" >&2; exit 2; }
    [ -f "$TWEAKS" ] || { echo "missing $TWEAKS" >&2; exit 2; }
    echo "== enviar QML =="
    $SSH "$CAR" 'cat > /tmp/ClimateTile.new' < "$CLIMATE"
    $SSH "$CAR" 'cat > /tmp/TweaksPage.new' < "$TWEAKS"
fi

$SSH "$CAR" "sh -s $MODE" <<'REMOTE'
set -u
MODE=${1:-install}
QC=/app/share/AppHomeScreen/qml_eco3.0/component/ClimateTile.qml
QT=/app/share/AppHomeScreen/qml_eco3.0/HomeScreen/TweaksPage.qml
BC=/rw_data/tweaks/ClimateTile.before-layoutfix.qml
BT=/rw_data/tweaks/TweaksPage.before-layoutfix.qml
NEWC=/tmp/ClimateTile.new
NEWT=/tmp/TweaksPage.new
RW=0
RO_FAILED=0

cleanup() {
    if [ "$RW" = 1 ]; then
        if mount -o remount,ro / >/dev/null 2>&1; then
            RW=0
        else
            echo 'WARN: / may still be rw' >&2
        fi
    fi
}
trap cleanup 0
trap 'cleanup; exit 130' 1 2 15

remount_rw() {
    # Mark rw before the mount: a signal during the remount must still make
    # the exit trap try to remount read-only (harmless if it was already ro).
    RW=1
    mount -o remount,rw / >/dev/null 2>&1 || { echo REMOUNT_RW_FAILED; exit 3; }
}
remount_ro() {
    sync
    if mount -o remount,ro / >/dev/null 2>&1; then
        RW=0
        RO_FAILED=0
    else
        echo 'WARN: / may still be rw' >&2
        RO_FAILED=1
    fi
}
clear_cache() {
    rm -rf /root/.cache/AppHomeScreen /root/.cache/qmlcache \
           /tmp/qmlcache /tmp/qt-qml-cache /var/cache/qmlcache 2>/dev/null
}
restart_ui() {
    dbus-send --session --type=method_call --dest=com.lge.avn.applauncher /Request \
        com.lge.avn.applauncher.request.terminate int32:11 >/dev/null 2>&1 || true
    sleep 2
    for i in 1 2 3; do
        dbus-send --session --type=method_call --dest=com.lge.avn.applauncher /Request \
            com.lge.avn.applauncher.request.launch int32:11 \
            string:AppHomeScreen string:/app/bin/AppHomeScreen >/dev/null 2>&1 && break
        sleep 2
    done
}
# Return a PID only when the old PID is gone from the whole pidof list.
wait_new_pid() { # seconds, old_pid
    seconds=$1
    old=$2
    i=0
    while [ "$i" -lt "$seconds" ]; do
        pids=$(pidof AppHomeScreen 2>/dev/null) || pids=""
        if [ -n "$old" ]; then
            case " $pids " in
                *" $old "*) i=$((i + 1)); sleep 1; continue ;;
            esac
        fi
        for p in $pids; do
            if [ -n "$p" ]; then echo "$p"; return 0; fi
        done
        i=$((i + 1))
        sleep 1
    done
    return 1
}
restore_files() { # returns 1 if either restore did not verify
    rc=0
    cp -f "$BC" "$QC" 2>/dev/null || rc=1
    cmp -s "$BC" "$QC" 2>/dev/null || rc=1
    cp -f "$BT" "$QT" 2>/dev/null || rc=1
    cmp -s "$BT" "$QT" 2>/dev/null || rc=1
    return "$rc"
}

oldpid=$(pidof AppHomeScreen 2>/dev/null | awk '{print $1}')
# An empty oldpid is allowed: rollback must work when a bad QML keeps the
# UI down, and install can wait for the first PID to appear.

launcher_pid=""
for p in /proc/[0-9]*; do
    [ -r "$p/comm" ] || continue
    if [ "$(cat "$p/comm" 2>/dev/null)" = "AppLauncher" ]; then
        launcher_pid="${p#/proc/}"
        break
    fi
done
if [ -n "$launcher_pid" ] && [ -r "/proc/$launcher_pid/environ" ]; then
    for var in DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR WAYLAND_DISPLAY QT_QPA_PLATFORM; do
        val=$(tr '\0' '\n' < "/proc/$launcher_pid/environ" 2>/dev/null |
              grep "^$var=" | head -n 1 | cut -d= -f2-)
        [ -n "$val" ] && export "$var=$val"
    done
fi
have_dbus() {
    command -v dbus-send >/dev/null 2>&1 &&
        [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]
}

if [ "$MODE" = rollback ]; then
    [ -s "$BC" ] && [ -s "$BT" ] || { echo NO_BACKUP; exit 9; }
    remount_rw
    if ! restore_files; then
        echo ROLLBACK_COPY_FAILED
        clear_cache
        remount_ro
        exit 9
    fi
    clear_cache
    remount_ro
    if ! have_dbus; then
        echo ROLLBACK_FILES_RESTORED_NO_RESTART
        exit 13
    fi
    restart_ui
    rp=$(wait_new_pid 20 "$oldpid") || rp=""
    if [ -n "$rp" ] && [ "$RO_FAILED" = 0 ]; then
        echo "UI_ROLLBACK_OK pid=$rp"
        exit 0
    fi
    echo UI_ROLLBACK_INCOMPLETE
    exit 11
fi

# ---- install ---------------------------------------------------------
[ -f "$QC" ] && [ -f "$QT" ] || { echo TARGET_MISSING; exit 4; }
[ -s "$NEWC" ] && [ -s "$NEWT" ] || { echo PAYLOAD_MISSING; exit 4; }
have_dbus || { echo NO_DBUS_ENV; exit 8; }
mkdir -p /rw_data/tweaks || { echo BACKUP_DIR_FAILED; exit 5; }
remount_rw

# First run keeps the stock files; later runs must not overwrite them.
if [ ! -s "$BC" ]; then
    cp -f "$QC" "$BC" || { echo BACKUP_FAILED; remount_ro; exit 5; }
fi
if [ ! -s "$BT" ]; then
    cp -f "$QT" "$BT" || { echo BACKUP_FAILED; remount_ro; exit 5; }
fi

if ! cp -f "$NEWC" "$QC" || ! cp -f "$NEWT" "$QT" || ! chmod 644 "$QC" "$QT"; then
    echo INSTALL_FAILED
    if restore_files; then echo INSTALL_ROLLED_BACK; else echo INSTALL_ROLLBACK_INCOMPLETE; fi
    clear_cache
    remount_ro
    exit 6
fi
if ! cmp -s "$NEWC" "$QC" || ! cmp -s "$NEWT" "$QT"; then
    echo INSTALL_MISMATCH
    if restore_files; then echo INSTALL_ROLLED_BACK; else echo INSTALL_ROLLBACK_INCOMPLETE; fi
    clear_cache
    remount_ro
    exit 6
fi
clear_cache
remount_ro
md5sum "$QC" "$QT"

restart_ui
newpid=$(wait_new_pid 20 "$oldpid") || newpid=""
if [ -n "$newpid" ] && [ "$RO_FAILED" = 0 ]; then
    echo "UI_OK pid=$newpid"
    exit 0
fi
if [ -n "$newpid" ] && [ "$RO_FAILED" = 1 ]; then
    echo "UI_OK_BUT_ROOT_RW pid=$newpid"
    exit 12
fi

echo UI_RESTART_FAILED_ROLLBACK
remount_rw
if ! restore_files; then
    echo ROLLBACK_COPY_FAILED
    clear_cache
    remount_ro
    exit 9
fi
clear_cache
remount_ro
restart_ui
rp=$(wait_new_pid 20 "$oldpid") || rp=""
if [ -n "$rp" ] && [ "$RO_FAILED" = 0 ]; then
    echo "UI_ROLLBACK_OK pid=$rp"
    exit 10
fi
echo UI_ROLLBACK_INCOMPLETE
exit 11
REMOTE
echo "== fim ($MODE) =="
