# Slow UI: measure first, then change one thing

Status: **script car-validated on one vehicle**; the numbers it produces are
a single snapshot, not a benchmark. Treat every cause below as a hypothesis
to confirm on your own car.

The head unit is a small x86-64 box running the OEM Qt/QML home screen next
to our daemons. "Sometimes slow" can be CPU contention, memory pressure,
eMMC/IO stalls, thermal throttling, QML cache rebuilds or an app restarting.
Guessing wastes time; take a snapshot first and compare.

## Snapshot

Run the read-only inventory on the car as root (`car` is uid 0 on
this firmware):

```sh
umask 077
ssh -p 2222 car@<CAR_IP> 'sh -s' < scripts/system-inventory.sh \
    > /tmp/system-report.txt
```

The redirect creates the local report; `umask 077` keeps it private. If
you run the script on the car instead, `--out FILE` creates mode 0600.

It never kills or restarts anything. It records:

| Section | What it tells you |
|---|---|
| System / Memory | load average, CPUs, available RAM, swap, dirty pages |
| Pressure (PSI) | whether tasks wait on CPU, IO or memory (if available) |
| CPU frequency / Thermal | governor, current/max frequency (kHz), zone temperatures (millidegrees C) |
| CPU windows | CPU time deltas over two 2 s windows, so it shows current load, not `ps` lifetime averages (one core = 100; can exceed 100 on multicore). Per-process CPU comes from `/proc/<pid>/stat` (the kernel's thread-group total); each window's busy/idle total comes from `/proc/stat`, so processes exiting between samples cannot skew it |
| Top memory | processes by RSS, with their command line |
| UI/QML processes | the home screen, Qt/QML helpers, compositor |
| QML caches | size and number of `*.qmlc` files |
| Services / Failed units | what is running and failing (if systemd is present) |
| UI-related units | `NRestarts`, start time, memory and CPU time (if available) |
| Kernel messages | recent errors, OOM, IO or thermal warnings (if `dmesg` is permitted) |

Take two snapshots: shortly after boot and after 10–15 minutes of normal
use. Compare them; a one-off spike during a scan or a QML rebuild is not the
same as a steady consumer.

## What to look for

- **One process high in both windows**: a steady hog (polling loop, busy
  wait, a daemon restarting in a loop).
- **A spike in one window only**: triggered work (Wi-Fi scan, log dump,
  QML cache rebuild, map/navigation update). A child that starts and exits
  between two samples can be missed; cross-check `dmesg` and the logs.
- **Falling `MemAvailable` with rising PSI memory/io**: memory pressure or
  eMMC stalls; check swap and `Dirty`.
- **High `NRestarts` on AppHomeScreen/QML units**: the UI is crashing and
  being restarted, which feels like lag.
- **Temperature near the trip point and low `scaling_cur_freq`**: thermal
  throttling; parking in the sun and the CPU governor matter more than code.
- **A large or stale QML cache**: the first paint after a page change
  rebuilds it; an old cache left by a previous install can slow startup.

## Levers worth testing (one at a time)

1. **QML cache.** The installers clear `/root/.cache/AppHomeScreen`,
   `/root/.cache/qmlcache` and `/tmp/qmlcache` before restarting the home
   screen. After editing a page, a clean cache costs one slow first paint
   and then settles; do not clear it on every boot.
2. **Daemon polling.** The WiFi main loop and the battery CAN loop wake at
   short intervals. If the snapshot shows our daemons near the top, measure
   their wake frequency before changing timeouts; correctness (door hook,
   reconnect) depends on them.
3. **Logs and eMMC writes.** Uncapped logs grow until `/rw_data` is full and
   keep the eMMC busy. The current daemons cap them at 1 MiB; see
   `docs/07-install.md`.
4. **Page timers.** A QML page that polls `/status` or redraws a clock every
   0.5-1.5 s keeps the UI process awake. Only reduce timers
   after confirming the process is a steady consumer.
5. **Restarts.** Fix crashes before micro-optimising; `NRestarts` and
   `dmesg` are the fastest signals.
6. **Thermal.** If the car is hot, the governor/frequency drop is expected.
   Shade and airflow beat software changes.

## Method

1. Baseline snapshot, car parked, same conditions.
2. Change **one** thing.
3. Repeat the snapshot after the same warm-up time.
4. Keep the change only if both CPU windows and the pressure lines improve;
   revert otherwise.

Keep the reports local: they contain command lines and paths.
