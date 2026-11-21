# Prior art: review of ioniq-5-Reverse-Engineering

Repository:
[NecktiedHummingbird/ioniq-5-Reverse-Engineering](https://github.com/NecktiedHummingbird/ioniq-5-Reverse-Engineering)

This is a review of what that project added to the work documented here.
No code was copied; the public snapshot has no explicit licence file, so
treat it as reference documentation only.

## What it is

- Research notes and tooling for a 2021 UK IONIQ 5 Gen5W head unit, aimed
  at running the **authentic vendor firmware unmodified in QEMU**.
- It uses the official EU `260128` package as a local analysis input and
  reaches an authentic Home screen in the VM. Navigation/compositing,
  audio, persistence and the full micom/CAN contract are still open.
- A large security register (kernel, ConnMan, oFono, Broadcom BSA, AppFUMO,
  SMACK, AppLauncher), plus a public sanitised snapshot. The 1.6 TB working
  tree, raw diagnostic exports and OEM binaries are not published.

## Useful confirmations

- The installed/owner's unit evidence and the `260128` target match the
  same firmware family used here.
- The AU manual lists **Android Auto/CarPlay as USB-cable** functions;
  wireless support is undocumented. That agrees with the finding in
  `docs/06-aa.md`: the installed tree has no AA projection stack.
- `vbtd` is Broadcom BSA. Their SDP work is a **security audit** of the SDP
  parser (CVE-2017-0785/13255/13256), not an SDP record/profile dump: no
  SPP record, no RFCOMM channel, no `InterfaceName`.
- ConnMan CVE findings (DHCPv6 DOMAIN_LIST, DHCPv4 underflow) reinforce the
  decision here to avoid ConnMan for the car's WiFi/DHCP. The design uses a
  single-owner supplicant and a static address.
- The serial-console note (root getty on `ttyS2`, gated by a temp file;
  `secure_console=1` removes the tty) is consistent with the warning here
  never to write `secure_console=0` on this platform.
- The AppHomeScreen show-gate analysis and the QEMU/IVI-window-manager work
  are useful if you ever want an offline UI testbed. They are not a
  packaged, standalone VM.

## What it does not add

- No new CAN IDs, DBC, bit layouts, battery/12 V/SOH decodes or vehicle
  signal contract; their own handover says the data-bearing micom/CAN
  contract is still being reconstructed.
- No working Android Auto stack for this firmware.
- No SPP/AA transport.
- No ready-to-use offline QML test harness (the published VM scripts are
  historical and refer to the private 1.6 TB work tree).

## Thanks

The VM, AppHomeScreen, micom and security research in that project is
substantial and helped frame the AA and platform conclusions here. It is
credited as prior art; this repository does not redistribute its files.
