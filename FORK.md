Publishing: standalone repository
=================================

This work is published as a **standalone repository**, not as a fork. It is a
selective, car-specific derivative of SCOURGE: documentation plus first-party
reference code, not a copy of the upstream packages.

Why standalone:

- The curated tree is not a branch of upstream. A fork would carry the whole
  upstream history and branches, which suggests all of it is part of this
  work.
- The published tree contains only the sanitised material, so the boundary is
  easy to review.
- Attribution is explicit in `README.md` and `NOTICE`, with links to upstream,
  and the licence stays AGPL-3.0-only.

Suggested repository description:

    Car-specific SCOURGE tweaks for a 2021 IONIQ 5 Gen5W: WiFi UI/daemon,
    battery page and gauge, climate tile, Home Assistant charge-door hook.
    Built on nickles-lee/hkg_SCOURGE (AGPL-3.0-only).

Fork alternative
----------------

If you want the "forked from" badge or to open pull requests against upstream,
fork the upstream and publish a curated **orphan branch** containing only the
material in this directory. Never push the owner's dirty working branch.

Commands (replace `<you>` and the repository names):

    gh repo fork nickles-lee/hkg_SCOURGE --clone=false
    git clone https://github.com/<you>/hkg_SCOURGE.git
    cd hkg_SCOURGE
    git checkout --orphan car-tweaks
    git rm -rf .
    cp -a /path/to/hkg_SCOURGE-car-tweaks/. .
    git add .
    git status                 # review: no secrets, no OEM material
    git commit -m "Car-specific WiFi, battery, climate and Home Assistant tweaks"
    git push -u origin car-tweaks

A normal branch is a bad idea: the owner's local tree is based on a diverged
branch with uncommitted changes, so it would expose unrelated work and a noisy
diff.

Checklist before pushing
------------------------
- [ ] No firmware images, OEM binaries, OEM QML dumps or diagnostics.
- [ ] No owner SSIDs, PSKs, IPs, MACs, VINs, tokens, webhook IDs or account data.
- [ ] Placeholders replaced in scripts and docs where needed.
- [ ] LICENSE and NOTICE kept.
- [ ] The code still builds against the upstream packages you document.
- [ ] If an AI agent created the commit on your behalf, the project's
      second-opinion rule applies: have a distinct reviewer check the diff
      and record `Second-Opinion: <agent/model> — PASS` in the commit
      message. Do not land a FAIL-reviewed change.
- [ ] Review the repository visibility before publishing.

## No-key upload (GitHub web)

If GitHub asks for 2FA/sudo when adding a deploy key, you can publish without
a key:

1. Create an empty repository in the browser (no README, no .gitignore).
2. Download a zip/tarball of this directory (for example from the GitHub
   archive of a prepared branch, or `git archive`).
3. Extract it locally.
4. In the empty repo: **Add file -> Upload files**.
5. Open the extracted folder and drag its **contents** (not the parent folder)
   into the upload area. Keep the directory structure (`docs/`, `reference/`,
   `scripts/`).
6. Commit on `main`.

The commit author is your GitHub account; no SSH key or PAT is needed. The
web upload is a human-reviewed commit, so the project's second-opinion rule
for unattended AI commits does not apply. If you later want the prepared git
history instead, add the deploy key and push the prepared `main` branch.
