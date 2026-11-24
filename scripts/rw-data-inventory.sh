#!/bin/sh
# SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Read-only inventory of /rw_data (or RW_DATA=<dir>) with delete candidates.
# Nothing is deleted or modified. Run on the head unit as root; permission
# errors are suppressed, so an unprivileged run under-reports.
#
# Usage:
#   sh rw-data-inventory.sh                 # print to stdout
#   sh rw-data-inventory.sh --out FILE      # truncate FILE (mode 0600)
#   RW_DATA=/tmp/fake sh rw-data-inventory.sh
#
# The report may contain private filenames, SSIDs and paths, so keep it on
# the car or a local disk. Sizes are KiB (du -sk); groups can overlap and
# totals are approximate.

set -u
ROOT=${RW_DATA:-/rw_data}
while [ "$ROOT" != "/" ] && [ "${ROOT%/}" != "$ROOT" ]; do
    ROOT=${ROOT%/}
done
if [ ! -d "$ROOT" ]; then
    echo "missing directory: $ROOT" >&2
    exit 2
fi

case "${1:-}" in
    "")
        if [ "$#" -ne 0 ]; then
            echo "usage: $0 [--out FILE]" >&2
            exit 2
        fi
        ;;
    --out)
        if [ "$#" -ne 2 ] || [ -z "$2" ]; then
            echo "usage: $0 [--out FILE]" >&2
            exit 2
        fi
        umask 077
        exec >"$2" 2>&1
        chmod 600 "$2" 2>/dev/null || true
        ;;
    *)
        echo "unknown argument: $1" >&2
        echo "usage: $0 [--out FILE]" >&2
        exit 2
        ;;
esac

section() { printf '\n=== %s ===\n' "$*"; }

# Read paths on stdin, print "KiB<TAB>path", skip vanished entries.
sizes() {
    while IFS= read -r p; do
        [ -e "$p" ] || [ -L "$p" ] || continue
        du -skx "$p" 2>/dev/null
    done
}

total_k() { awk '{s += $1} END {printf "%d", s + 0}'; }

list_total() { # label, then paths on stdin
    label=$1
    data=$(sizes)
    if [ -n "$data" ]; then
        printf '%s\n' "$data" | sort -rn | head -40
    fi
    printf -- '-- %s total: %s KiB\n' "$label" "$(printf '%s' "$data" | total_k)"
}

printf 'Read-only inventory of %s\n' "$ROOT"
printf 'Generated: %s\n' "$(date 2>/dev/null || echo unknown)"
printf 'Nothing is deleted or modified by this script.\n'

section "Filesystem"
df -Pk "$ROOT" 2>/dev/null || echo 'df unavailable'
df -Pi "$ROOT" 2>/dev/null || echo 'inode usage unavailable'

section "Top-level entries (KiB, largest first)"
for item in "$ROOT"/* "$ROOT"/.[!.]* "$ROOT"/..?*; do
    [ -e "$item" ] || [ -L "$item" ] || continue
    du -skx "$item" 2>/dev/null
done | sort -rn | head -40

section "Largest entries two levels down (KiB)"
du -skx "$ROOT"/*/* 2>/dev/null | sort -rn | head -30

section "Largest files over 10 MiB (KiB, top 30)"
find "$ROOT" -xdev -type f -size +10485760c -print 2>/dev/null |
    sizes | sort -rn | head -30

section "Logs (*.log, *.log.*)"
find "$ROOT" -xdev -type f \( -name '*.log' -o -name '*.log.*' \) \
    ! -name '*.before-*' -print 2>/dev/null | list_total 'logs'

section "Rollback copies (*.before-*): keep the newest of each"
find "$ROOT" -xdev -type f -name '*.before-*' \
    -print 2>/dev/null | list_total 'rollback copies'

section "Other leftovers (bak/orig/old/editor)"
find "$ROOT" -xdev -type f \( \
        -name '*.bak' -o -name '*.orig' -o -name '*.old' \
        -o -name '*~' -o -name '.#*' \) \
    ! -name '*.log.*' -print 2>/dev/null | list_total 'other leftovers'

section "Dumps and archives (completed exports)"
find "$ROOT" -xdev \
    \( -type d \( -name 'battery_logs_*' -o -name 'wifi_logs_*' \
                 -o -name 'tweaks_logs_*' \) -prune -print \) -o \
    \( -type f \( -name '*.tar.gz' -o -name '*.tgz' -o -name '*.zip' \) -print \) \
    2>/dev/null | list_total 'dumps'

section "Firmware/update payloads (keep unless you are sure they are stale)"
find "$ROOT" -xdev -type f \( \
        -name '*.img' -o -name '*.lz4' -o -name '*.dump' \) \
    -print 2>/dev/null | list_total 'payload files'

section "Core dumps"
find "$ROOT" -xdev -type f \( \
        -name 'core' -o -name 'core.*' -o -name '*.core' \) \
    -print 2>/dev/null | list_total 'cores'

section "QML/thumbnail caches (regenerated)"
find "$ROOT" -xdev -type d \( \
        -name 'qmlcache' -o -name 'thumbnails' -o -name '.thumbnails' \) \
    -prune -print 2>/dev/null | list_total 'caches'

section "Map / navigation data (informational; do not delete blindly)"
find "$ROOT" -xdev -maxdepth 4 -type d \( \
        -iname '*nav*' -o -iname '*map*' \) \
    -prune -print 2>/dev/null | sizes | sort -rn | head -20

section "Protected runtime data (keep)"
for p in "$ROOT/app_data" "$ROOT/wifi/config.conf" \
         "$ROOT/battery/door_hook.conf" "$ROOT/wifi/home/.ssh"; do
    [ -e "$p" ] || [ -L "$p" ] || continue
    du -skx "$p" 2>/dev/null
done
find "$ROOT" -xdev -maxdepth 4 -type f \( \
        -name 'authorized_keys' -o -name 'VBTConfig.json' \
        -o -name 'USBSerial.txt' -o -name 'status.json' \
        -o -name 'wifi_daemon' \
        -o -name 'battery_daemon' -o -name '*.qml' \) \
    -print 2>/dev/null | sizes | sort -rn | head -30

section "How to read this"
cat <<'EOF'
Safe candidates, after reviewing the list:
  - "Other leftovers" (bak/orig/old/editor files) and core dumps;
  - completed dumps/archives already copied to a pen;
  - QML/thumbnail caches - regenerated on restart;
  - oversized *.log files. A running writer holds the descriptor open, so
    `rm` frees nothing until it restarts; truncate in place instead
    (`: > /rw_data/wifi/daemon.log`). The current daemons cap at 1 MiB.

Rollback copies (*.before-*): these are your way back. Keep the newest
`wifi_daemon.before-*`, `battery_daemon.before-*`, `config.conf.before-*`,
`WifiPage.before-*.qml` and `BatteryPage.before-*.qml`. Only older
duplicates are candidates.

Firmware/update payloads (*.img/*.lz4/*.dump): keep unless you are certain
they are stale copies; they may be a staged update.

Think twice:
  - status.json and *.conf: small, needed for the next boot;
  - the only copy of a log you still need for diagnosis;
  - map/navigation data: deleting it can break navigation;
  - any other directory named "cache" (the section above lists only
    qmlcache/thumbnails).

Do not delete:
  - /rw_data/app_data (VBT/projection configuration, e.g. VBTConfig.json,
    USBSerial.txt);
  - wifi_daemon, battery_daemon, bin/ helpers, SSH keys/authorized_keys;
  - anything you cannot identify.

This script never deletes. Delete explicitly, one path at a time, with the
car parked, after copying anything you may need to a pen.
EOF
