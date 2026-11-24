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

# One line per process: "pid utime+stime" from /proc/PID/stat.
# The kernel reports thread-group totals there; /proc/PID/task/*/stat would be
# per-thread and non-monotonic when a worker exits inside a sampling window.
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

# Machine totals from /proc/stat, monotonic across process exits.
# Fields 2-9 are user..steal; guest/guest_nice (10-11) are already in
# user/nice and would inflate the total on a KVM host.
cpu_stat() {
    awk '/^cpu /{s = 0; for (i = 2; i <= 9 && i <= NF; i++) s += $i; print s, $5 + $6; exit}' \
        /proc/stat 2>/dev/null
}
cpu_ok() { case "$1$2" in ''|*[!0-9]*) return 1 ;; esac; }

cpu_window() { # snapshot1, snapshot2, total1, total2, idle1, idle2, label
    s1=$1
    s2=$2
    t1=$3
    t2=$4
    i1=$5
    i2=$6
    label=$7
    dt=$((t2 - t1))
    di=$((i2 - i1))
    [ "$di" -gt "$dt" ] && di=$dt
    [ "$di" -lt 0 ] && di=0
    busy=$((dt - di))
    printf -- '-- window %s\n' "$label"
    if [ "$dt" -gt 0 ]; then
        printf 'total: %s jiffies, busy %s (%s%% of %s CPUs, %s%% idle)\n' \
            "$dt" "$busy" "$((busy * 100 / dt))" "$CPUS" \
            "$((di * 100 / dt))"
    fi
    printf '%-8s %-7s %-10s %s\n' 'jiffies' '%CPU' 'PID' 'command'
    # Busybox awk on this firmware corrupts the heap with -v, so the delta
    # is computed here and the percentage in the shell below.
    {
        printf '%s\n' "$s1"
        echo '=='
        printf '%s\n' "$s2"
    } | awk '
        $0 == "==" { second = 1; next }
        NF == 2 {
            if (second) b[$1] = $2
            else a[$1] = $2
        }
        END {
            for (p in b)
                if (a[p] != "") {
                    d = b[p] - a[p]
                    if (d > 0) print d, p
                }
        }
    ' | sort -rn | head -15 | while read -r d p; do
        pct=$((d * 100 / (HZ * 2)))
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
CPUS=$(getconf _NPROCESSORS_ONLN 2>/dev/null ||
       grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
case "$CPUS" in
    ''|*[!0-9]*) CPUS=1 ;;
    0) CPUS=1 ;;
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
    S1=$(cpu_sample); C1=$(cpu_stat)
    sleep 2
    S2=$(cpu_sample); C2=$(cpu_stat)
    sleep 2
    S3=$(cpu_sample); C3=$(cpu_stat)
    T1=${C1% *}; I1=${C1#* }
    T2=${C2% *}; I2=${C2#* }
    T3=${C3% *}; I3=${C3#* }
    if [ -z "$S1" ] || [ -z "$S2" ] ||
       ! cpu_ok "$T1" "$I1" || ! cpu_ok "$T2" "$I2"; then
        echo '/proc data unreadable; CPU windows unavailable'
    else
        cpu_window "$S1" "$S2" "$T1" "$T2" "$I1" "$I2" "1 (2 s)"
        if [ -n "$S3" ] && cpu_ok "$T3" "$I3"; then
            cpu_window "$S2" "$S3" "$T2" "$T3" "$I2" "$I3" "2 (2 s)"
        else
            echo 'second window incomplete; skipped'
        fi
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
