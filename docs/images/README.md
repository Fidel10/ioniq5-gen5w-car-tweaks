# Screenshots

Captured on the owner's 2021 IONIQ 5 Gen5W with
`/usr/libexec/weston-screenshooter` (Weston 1.10, 1920x720), then:

- owner SSID, IP addresses, the SSH command, the timezone setting and the
  profile avatar blurred;
- downscaled to 1280x480 with LANCZOS;
- PNG metadata stripped (Pillow re-encode).

Published images: `wifi-page.png`, `battery-page.png`, `tweaks-page.png`,
`home-tiles.png`. The Tweaks and home screenshots were recaptured after the
layout fixes in `reference/qml/` were installed with
`scripts/install-ui-fixes.sh` and validated on the car (2026-11-25).

The renders include the OEM theme, icons and status bar. They are
documentation of this work only; the OEM artwork remains the property of its
owners and is not licensed by this repository. No OEM QML source, binary or
firmware is included.
