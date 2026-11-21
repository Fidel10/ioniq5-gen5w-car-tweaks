# Charge Port button → Home Assistant webhook → smart plug

Status: **car-validated** on the owner's car: the webhook fired, the Home
Assistant automation ran and the physical smart plug switched on/off in
response (confirmed by the owner at the socket).

## Goal

When the driver presses the **Charge Port** tile on the head unit (the one
that opens/closes the charge door), Home Assistant should turn a smart plug
on or off. The plug powers the charging socket, so the sequence is:
open the door with the button → the socket is already live when the cable is
plugged in.

## Why not use the door state passively

The battery daemon can decode `0x3AA` when it is visible, but the head unit
sleeps when the car is off and the frame is not always on the same bus.
Using the **button command** is deterministic: the head unit is awake, the
user initiated the action, and the daemon knows when the micom accepted the
command.

The hook lives in the daemon's `door_finish()`: it fires only after a
successful **commanded** open/close, not on a manual door movement and not
when the command is blocked (cable, cooldown, busy, failure).

## Flow

1. The tile `ChargeDoorTile` calls
   `POST http://127.0.0.1:8088/chargedoor/toggle`.
2. The daemon computes the target (open/close), checks the block reasons,
   sends the micom CAN frames (`0x4A2`) and tracks the result.
3. On success, `door_finish()` writes `door_hook_fire(target)`.
4. The hook reads `/rw_data/battery/door_hook.conf` (root-only, mode 600):
   ```ini
   open_url=http://<HA_IP>:8123/api/webhook/<OPEN_WEBHOOK_ID>
   close_url=http://<HA_IP>:8123/api/webhook/<CLOSE_WEBHOOK_ID>
   ```
5. A detached child makes a small HTTP POST (2 s timeouts) with
   `{"state":"open"}` or `{"state":"closed"}`. A slow/unreachable HA never
   blocks the CAN loop.
6. Home Assistant runs two webhook automations that call
   `switch.turn_on` / `switch.turn_off` on the plug entity.

The car stores **only webhook URLs** — no Home Assistant token. The webhook
IDs are the secret; anyone who knows them can trigger the automation.

## Home Assistant automations

Use the tested legacy keys (`trigger`/`action`) or let the current HA editor
rewrite them. Replace `switch.your_plug` and **both** webhook IDs with your
own long random values (HA generates them for you when you create a webhook
automation; do not keep predictable IDs like `charge_door_open`). The `id:`
fields below are HA automation IDs, not secrets — only `webhook_id` is the
secret.

```yaml
- id: charge_door_open
  alias: Car - charge door opens -> plug on
  trigger:
    - platform: webhook
      webhook_id: <OPEN_WEBHOOK_ID>
      allowed_methods: [POST]
  action:
    - service: switch.turn_on
      target:
        entity_id: switch.your_plug
  mode: single

- id: charge_door_close
  alias: Car - charge door closes -> plug off
  trigger:
    - platform: webhook
      webhook_id: <CLOSE_WEBHOOK_ID>
      allowed_methods: [POST]
  action:
    - service: switch.turn_off
      target:
        entity_id: switch.your_plug
  mode: single
```

The full example is in `scripts/home-assistant/charge-door.yaml`.

If the plug does not respond, remember that the HA entity state and the
physical relay can disagree: during setup on a SONOFF **POWR320D** the
entity changed in HA before the physical relay was reachable. The webhook
path was already correct; check the device/integration if the state toggles
but the relay does not.

## Network requirements

- The car must be on the same VLAN as HA, or route to it. In the reference
  setup the car and HA shared one IoT VLAN; the car could ping HA and open
  TCP 8123.
- The car's WiFi must be **on** at that moment. `boot_off=0` keeps it on
  across boots. If your automation must work with WiFi off, use a physical
  sensor instead; LTE + a public HTTPS endpoint would need a TLS client,
  which this small C hook does not implement.
- The hook supports **http:// + IPv4 literal only** (no TLS, no hostname)
  because the daemon is a static binary and avoids NSS/glibc surprises. If
  HA is only HTTPS (e.g. Nabu Casa), use a different client or a physical
  sensor.
- Use the HA local IP, not `homeassistant.local` (mDNS) for this hook.

## Testing

Server side (with an HA long-lived token, only for verification):

```sh
curl -s -H "Authorization: Bearer <TOKEN>" \
  http://<HA_IP>:8123/api/states/switch.your_plug
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"state":"open"}' http://<HA_IP>:8123/api/webhook/<OPEN_WEBHOOK_ID>
```

Then check the relay and the entity state. Car side:

```sh
# after pressing the tile, look for the hook line:
grep 'door hook' /rw_data/battery/daemon.log
```

Expected (the path/ID is redacted in the log):

```
door hook open -> http://<HA_IP>:8123/...
```

The daemon log therefore does not contain the webhook secret.

If the log shows the hook but HA does not fire, check the URL/IP, TCP 8123
from the car, and that the automation is enabled. If the log has no hook,
the door command did not succeed or the config is empty.

## Security notes

- Do not put a long-lived HA token in the car or in this repository. If you
  create one for setup, revoke it afterwards.
- Treat webhook IDs as secrets; do not publish them.
- Keep `door_hook.conf` mode 600.
- The car daemon binds its HTTP API to `127.0.0.1`; do not expose it to the
  LAN: it also has preheat/door/join write endpoints.
- A webhook can turn the plug on/off; scope the automation to that plug
  only.

## Close behaviour

The reference config sends both open and close webhooks. If you want the
plug to stay on until you turn it off manually, leave `close_url=` empty (or
remove the close automation). The owner chose to test both directions; the
close hook can surprise you if you close the door while charging.

## Alternative: physical door sensor

If the trigger must work when the head unit is asleep or WiFi is off, a
Zigbee/Thread magnetic contact sensor on the charge door is more reliable.
The HA automation becomes `binary_sensor.charge_door` → `switch.turn_on`.
The car-button hook is convenient but depends on the head unit being awake
and networked.
