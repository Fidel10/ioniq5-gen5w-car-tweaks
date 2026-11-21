# SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Add the Climate tile to the three page components of an installed
# QHMI_HomeScreenMain_Advanced.qml.  The OEM Advanced file is not
# redistributed here; point the script at your own copy (or at a copy pulled
# from the head unit).
#
# Usage:
#   python3 add-climate-tile.py /path/to/QHMI_HomeScreenMain_Advanced.qml
#
# The tile is placed in the next free slot after the pre-heat tile
# (firstEmptySlot(3)).  A backup is written next to the input file.

"""Insert the Climate tile into an installed Advanced.qml.

Usage:
  python3 add-climate-tile.py /path/to/QHMI_HomeScreenMain_Advanced.qml

The tile is inserted in the next free slot on pages 0-2 (using
firstEmptySlot(3)) and a .before-climate-tile backup is written next to the
input file. The OEM Advanced.qml is not redistributed here.
"""

import shutil
import sys
from pathlib import Path

MARKER = "ClimateTile"
BLOCK = """
                ClimateTile {{
                    id: climateTile{n}
                    property var slot: firstEmptySlot(3)
                    visible: slot !== null && slot.page === {page}
                    x: menuPage{sfx}.x + (slot !== null && slot.page === {page} ? (slot.index % k_nbrOfColumns) * k_itemWidth : 0)
                    y: menuPage{sfx}.y + (slot !== null && slot.page === {page} ? Math.floor(slot.index / k_nbrOfColumns) * k_itemHeight : 0)
                    width: k_itemWidth
                    height: k_itemHeight
                    z: 7
                }}"""


def add(path: Path) -> int:
    text = path.read_text()
    if MARKER in text:
        print("ClimateTile already present; nothing to do")
        return 0

    lines = text.split("\n")
    inserted = 0
    for n in (1, 2, 3):
        page = n - 1
        sfx = "" if n == 1 else str(n)
        start = next((i for i, line in enumerate(lines)
                      if f"id: preHeatTile{n}" in line), None)
        if start is None:
            print(f"warning: preHeatTile{n} not found")
            continue
        end = next((i for i in range(start, len(lines))
                    if lines[i] == "                }"), None)
        if end is None:
            print(f"warning: closing brace for preHeatTile{n} not found")
            continue
        lines[end + 1:end + 1] = BLOCK.format(n=n, page=page, sfx=sfx).split("\n")
        inserted += 1

    if not inserted:
        print("no PreHeatTile blocks found; refusing to write")
        return 1

    backup = path.with_suffix(path.suffix + ".before-climate-tile")
    shutil.copy2(path, backup)
    path.write_text("\n".join(lines))
    print(f"inserted {inserted} ClimateTile block(s); backup: {backup}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(add(Path(sys.argv[1])))
