#!/bin/sh
# SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Read-only snapshot of processes, CPU, memory, services and QML/UI runtime.
# Nothing is killed, restarted or modified. Run on the head unit as root.
#
# CPU is measured from /proc/<pid>/stat deltas over two 2-second windows, so
# the report shows what is consuming CPU now, not the lifetime average that
# ps %CPU reports. HZ is taken from getconf when available (100 otherwise).
#
# Usage:
#   sh system-inventory.sh                 # print to stdout
#   sh system-inventory.sh --out FILE      # truncate FILE (mode 0600)
#
# The report includes process command lines and paths: keep it local.

set -u

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
        if [ -L "$2" ]; then
            echo "refusing to write through a symlink: $2" >&2
            exit 2
        fi
        umask 077
        exec 3>&2
        exec >"$2" 2>&1
        chmod 600 "$2" 2>/dev/null || true
        mode=$(stat -c %a "$2" 2>/dev/null || echo '?')
        [ "$mode" = "600" ] ||
            printf 'WARNING: report mode is %s, expected 600\n' "$mode" >&3
        ;;
    *)
        echo "unknown argument: $1" >&2
        echo "usage: $0 [--out FILE]" >&2
        exit 2
        ;;
esac

section() { printf '\n=== %s ===\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# One line per process: "pid utime+stime" (jiffies).
cpu_sample() {
    awk '
        {
            f = FILENAME
            sub(/^\/proc\//, "", f)
            sub(/\/stat$/, "", f)
            line = $0
            sub(/^.*\) /, "", line)
            n = split(line, a, " ")
            if (n >= 13) print f, a[12] + a[13]
        }
    ' /proc/[0-9]*/stat 2>/dev/null
}

cpu_window() { # snapshot1, snapshot2, label
    s1=$1
    s2=$2
    label=$3
    printf -- '-- window %s\n' "$label"
    printf '%-8s %-7s %-10s %s\n' 'jiffies' '%CPU' 'PID' 'command'
    {
        printf '%s\n' "$s1"
        echo '=='
        printf '%s\n' "$s2"
    } | awk -v hz="$HZ" -v iv=2 '
        $0 == "==" { second = 1; next }
        NF == 2 {
            if (second) b[$1] = $2
            else a[$1] = $2
        }
        END {
            for (p in b)
                if (p in a) {
                    d = b[p] - a[p]
                    if (d > 0) print d, p, int(d * 100 / (hz * iv))
                }
        }
    ' | sort -rn | head -15 | while read -r d p pct; do
        cmd=$( { tr '\0' ' ' < "/proc/$p/cmdline"; } 2>/dev/null )
        cmd=${cmd% }
        [ -n "$cmd" ] || cmd=$( { tr '\n' ' ' < "/proc/$p/comm"; } 2>/dev/null )
        cmd=$(printf '%s' "$cmd" | cut -c1-200)
        printf '%-8s %-7s %-10s %s\n' "$d" "$pct" "$p" "$cmd"
    done
}

rss_top() { # top RSS in KiB from /proc
    for d in /proc/[0-9]*; do
        pid=${d#/proc/}
        [ -r "$d/status" ] || continue
        rss=$(awk '/^VmRSS:/{print $2}' "$d/status" 2>/dev/null)
        [ -n "${rss:-}" ] || continue
        cmd=$( { tr '\0' ' ' <"$d/cmdline"; } 2>/dev/null )
        cmd=${cmd% }
        [ -n "$cmd" ] || cmd=$( { tr '\n' ' ' <"$d/comm"; } 2>/dev/null )
        cmd=$(printf '%s' "$cmd" | cut -c1-200)
        printf '%s\t%s\t%s\n' "$rss" "$pid" "$cmd"
    done | sort -rn | head -15
}

systemctl_run() {
    if have timeout; then
        timeout 10 systemctl "$@" 2>/dev/null
    else
        systemctl "$@" 2>/dev/null
    fi
}

HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
case "$HZ" in
    ''|*[!0-9]*) HZ=100 ;;
    0) HZ=100 ;;
esac

printf 'Read-only system snapshot\n'
printf 'Generated: %s\n' "$(date 2>/dev/null || echo unknown)"
printf 'Nothing is killed, restarted or modified.\n'
printf 'Report contains command lines and paths; keep it local.\n'
printf 'CPU_HZ=%s\n' "$HZ"

section "System"
uname -a 2>/dev/null || echo 'uname unavailable'
uptime 2>/dev/null || echo 'uptime unavailable'
printf 'loadavg: '; cat /proc/loadavg 2>/dev/null || echo unknown
printf 'cpus: '; getconf _NPROCESSORS_ONLN 2>/dev/null || \
    grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo unknown

section "Memory"
free -m 2>/dev/null || echo 'free unavailable'
grep -E '^(MemTotal|MemFree|MemAvailable|Cached|Buffers|SwapTotal|SwapFree|Dirty):' \
    /proc/meminfo 2>/dev/null

section "Pressure (PSI, if available)"
for f in /proc/pressure/cpu /proc/pressure/io /proc/pressure/memory; do
    if [ -r "$f" ]; then
        printf -- '-- %s\n' "$f"
        cat "$f" 2>/dev/null
    fi
done

section "CPU frequency (kHz) and governor"
for c in /sys/devices/system/cpu/cpu*/cpufreq; do
    [ -d "$c" ] || continue
    printf '%s gov=%s cur_khz=%s max_khz=%s\n' "${c%/cpufreq}" \
        "$(cat "$c/scaling_governor" 2>/dev/null)" \
        "$(cat "$c/scaling_cur_freq" 2>/dev/null)" \
        "$(cat "$c/cpuinfo_max_freq" 2>/dev/null)"
done | head -12

section "Thermal zones (temp_mC = millidegrees Celsius)"
for z in /sys/class/thermal/thermal_zone*; do
    [ -r "$z/temp" ] || continue
    printf '%s type=%s temp_mC=%s\n' "${z##*/}" \
        "$(cat "$z/type" 2>/dev/null)" "$(cat "$z/temp" 2>/dev/null)"
done | head -20

section "CPU windows (deltas from /proc, two 2 s windows)"
if ! have sleep; then
    echo 'sleep unavailable; CPU windows skipped'
else
    S1=$(cpu_sample)
    sleep 2
    S2=$(cpu_sample)
    sleep 2
    S3=$(cpu_sample)
    if [ -z "$S1" ] || [ -z "$S2" ]; then
        echo '/proc/<pid>/stat unreadable; CPU windows unavailable'
    else
        cpu_window "$S1" "$S2" "1 (2 s)"
        cpu_window "$S2" "$S3" "2 (2 s)"
    fi
fi

section "Top memory (RSS KiB, PID, command)"
rss_top

section "UI/QML processes"
if have ps; then
    ps w 2>/dev/null |
        grep -iE 'apphomescreen|qhmi|qml|qt |qtweb|weston|wayland|compositor' |
        grep -v grep | head -25
else
    echo 'ps unavailable'
fi

section "QML caches (size in KiB)"
for d in /root/.cache/AppHomeScreen /root/.cache/qmlcache \
         /tmp/qmlcache /tmp/qt-qml-cache /var/cache/qmlcache; do
    [ -e "$d" ] || continue
    du -skx "$d" 2>/dev/null
done
find /root /tmp -xdev -maxdepth 4 -type f -name '*.qmlc' -print 2>/dev/null | wc -l \
    | awk '{print "qmlc files:", $1}'

section "Services (running)"
if have systemctl; then
    systemctl_run list-units --type=service --state=running --no-pager | head -60
else
    echo 'systemctl unavailable'
fi

section "Failed units"
if have systemctl; then
    systemctl_run --failed --no-pager | head -30
else
    echo 'systemctl unavailable'
fi

section "UI-related units and restart counters"
if have systemctl; then
    systemctl_run list-units --all --plain --no-pager |
        grep -iE 'home|qml|qt|compositor|weston|wayland' | head -30
    units=$(systemctl_run list-units --type=service --all --no-legend \
            --plain --no-pager | awk '{print $1}' | grep -iE 'home|qml|qt')
    [ -n "$units" ] || units=$(systemctl_run list-units --type=service \
            --all --no-legend --no-pager |
            awk '{print ($1 == "\342\227\217") ? $2 : $1}' |
            grep -iE 'home|qml|qt')
    for u in $units; do
        systemctl_run show "$u" \
            -p Id,NRestarts,ExecMainStartTimestamp,MemoryCurrent,CPUUsageNSec
    done
else
    echo 'systemctl unavailable'
fi

section "Recent kernel messages"
if have dmesg && dmesg >/dev/null 2>&1; then
    dmesg 2>/dev/null | tail -25
else
    echo 'dmesg unavailable (missing or restricted)'
fi

section "How to read this"
cat <<'EOF'
Look for:
  - a process with a high %CPU/jiffies delta in both windows: steady hog;
    a spike in only one window is triggered work (scan, dump, QML rebuild);
  - AppHomeScreen/qml processes with high RSS or a rising NRestarts
    (crashes/restarts make the UI feel slow);
  - low MemAvailable and high PSI memory/io: the UI competes for memory or
    waits on the eMMC;
  - thermal throttling (temp_mC near the trip point) and a low cur_khz;
  - stale/large QML caches: after changing a page the first paint rebuilds
    them; a cache left by an old install can slow startup.

%CPU here is the delta over a 2 s window (one core = 100, multi-threaded
processes can exceed 100). It is not the lifetime average shown by ps.
A child that starts and exits between two samples can be missed.
If HZ is not 100, the jiffies column is exact and %CPU is approximate.

Nothing here changes the car. Use the windows to decide, then test one
change at a time (QML cache clear, daemon polling interval, page timers).
EOF
