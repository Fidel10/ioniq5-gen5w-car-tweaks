# Security policy

This repository is a personal, car-specific derivative of SCOURGE. It ships
documentation, first-party reference code and scripts; there are no releases
and no supported version branches. Only the current `main` is maintained.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Use GitHub's private vulnerability reporting:

**Security → Report a vulnerability**

That form is private between you and the maintainer; no email address is
needed. If the button is not available, open a minimal public issue asking
for a private channel, without details of the vulnerability.

Useful reports include: the affected file/line or script, the impact, the
steps to reproduce (on your own hardware or a copy), and any suggested fix.

## Scope

In scope:

- the reference code in `reference/` (WiFi/battery daemons, QML pages);
- the scripts in `scripts/` and the Home Assistant examples;
- documentation that could lead to an unsafe or insecure setup
  (for example webhook handling, default accounts, LAN exposure).

Out of scope:

- the OEM firmware, head unit, apps or services themselves;
- vulnerabilities in upstream SCOURGE or third-party packages — report those
  upstream;
- anything requiring access to a vehicle you do not own, or work performed
  while driving.

## What to expect

This is a best-effort, single-maintainer project: no SLA and no bounty. I
will acknowledge a report when I can, discuss a fix and credit you in the
commit or release notes unless you prefer otherwise.

## Please do not include

Real SSIDs, PSKs, LAN addresses, MACs, webhook IDs, Home Assistant tokens,
VINs or logs from a vehicle you do not own. Redact them before reporting.
