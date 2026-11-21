#!/bin/sh
# SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
# SPDX-License-Identifier: AGPL-3.0-only
# Instala o battery_daemon com o hook de porta para o Home Assistant.
# Uso: ./install-door-hook.sh <open_url> [close_url]
#   open_url  ex.: http://<HA_IP>:8123/api/webhook/<OPEN_WEBHOOK_ID>
#   close_url opcional (ex.: mesmo webhook ou outro)
# O binario tem de ser construido com o hook de porta; passa o caminho em
# HOOK_BIN=... (por defeito: ./battery_daemon_hook ao lado deste script).
set -eu
OPEN_URL=${1:?open_url obrigatorio}
CLOSE_URL=${2:-}
CAR=${CAR:-car@192.168.1.228}
PORT=${PORT:-2222}
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOOK_BIN=${HOOK_BIN:-"$DIR/battery_daemon_hook"}
SSH="ssh -p $PORT -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new"

if [ ! -f "$HOOK_BIN" ]; then
    echo "falta $HOOK_BIN: constroi o battery_daemon com o hook de porta" >&2
    echo "(ver docs/07-install.md) e passa HOOK_BIN=/caminho/para/binario" >&2
    exit 2
fi

case "$OPEN_URL" in
    http://*) ;;
    *) echo "open_url tem de ser http://<ipv4>:<porta>/..." >&2; exit 2 ;;
esac

echo "== enviar daemon =="
$SSH "$CAR" 'cat > /tmp/battery_daemon.new' < "$HOOK_BIN"

echo "== instalar e configurar =="
$SSH "$CAR" "
set -e
B=/rw_data/battery/battery_daemon
[ -f \"\$B\" ] && cp -f \"\$B\" /rw_data/battery/battery_daemon.before-doorhook || true
cp -f /tmp/battery_daemon.new \"\$B\"
chmod 755 \"\$B\"
chown 0:0 \"\$B\" 2>/dev/null || true
cat > /rw_data/battery/door_hook.conf <<'EOF'
# Home Assistant webhooks fired by the Charge Port button.
# Only http://IPv4 is supported (no TLS).
open_url=$OPEN_URL
close_url=$CLOSE_URL
EOF
chmod 600 /rw_data/battery/door_hook.conf
sync
systemctl restart battery-daemon.service 2>/dev/null || true
sleep 2
pgrep -af battery_daemon | head -2
tail -4 /rw_data/battery/daemon.log 2>/dev/null || true
"
echo "== fim =="
