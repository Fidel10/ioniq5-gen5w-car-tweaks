# Interior/exterior temperature tile

Status: **car-validated visually** on the owner's car; a background-fill
fix is prepared and pending visual validation (see
`docs/07-install.md`). The tile is a first-party QML component; the OEM
home-screen file is only patched, not redistributed.

## What it shows

`reference/qml/ClimateTile.qml` — a 306×249 tile in the home grid:

- **INT** — the driver's **set** temperature from the climate screen
  (`appClimateModel.levelDriver`). It is not a measured cabin temperature.
- **EXT** — the factory ambient temperature (`appClimateModel.ambienTemp`).
- Unit follows `appClimateModel.tempUnit` (C/F); values update live through
  QML bindings, no polling.
- Title `Clima`, subtitle `interior · exterior`.

The car does not expose a measured cabin temperature to QML. If a value is
missing/off, the tile shows `--`.

## Why not the real cabin temperature

`appClimateModel` exposes set points and climate state (`levelDriver`,
`levelPassenger`, `levelRear`, `valueTempRear`, `ambienTemp`, blower,
defog, seats, etc.), not a cabin air-temperature sensor. The `INT` label is
therefore the driver's set temperature, which is what the climate screen
shows. Do not present it as a measurement.

## Adding it to the home screen

The tile is placed in the next free slot after the existing custom tiles
(Charge Port = slot 1, Battery = slot 2, Climate = slot 3) on whichever page
has room.

`scripts/add-climate-tile.py` patches your own installed
`QHMI_HomeScreenMain_Advanced.qml`:

```sh
python3 scripts/add-climate-tile.py /path/to/QHMI_HomeScreenMain_Advanced.qml
```

It inserts a `ClimateTile { ... }` block after each `PreHeatTile` block, with
the correct `menuPage`/page index for pages 0, 1 and 2, and writes a
`.before-climate-tile` backup. The script is idempotent and refuses to run
if it cannot find the anchors.

The component goes in:

```
/app/share/AppHomeScreen/qml_eco3.0/component/ClimateTile.qml
```

The OEM Advanced file is not included in this repository. Keep your own
backups; on this car a bad Advanced/QML edit can blank the home screen.
Restarting AppHomeScreen does not drop WiFi/SSH, but a QML error can require
a restore from the backup or a head-unit reboot.

## Layout notes

- The tile uses the stock `Q_ThemeImage` background (`home_bg_icon_n`).
- The two values are two columns; the divider is a thin rectangle.
- No click action; it is a read-only tile.
- It can be removed at any time by deleting the three `ClimateTile` blocks
  and the component; keep the `.before-climate-tile` backup.

## Limitations

- If `levelDriver` is 0/off, `INT` shows `--`.
- Exterior temperature may be stale or unavailable when the climate module
  is asleep.
- The tile is car-validated only on the owner's firmware; the property names
  come from the factory QML and may differ on other builds.
