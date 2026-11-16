# Community apps (optional)

Omaxian-compatible **standalone applications** ported from the Omarchy
ecosystem. These are not Quickshell shell plugins and are **not** installed by
`scripts/setup.sh`, `install.sh`, or `deploy.sh`.

| Kind | Tree | Hosted by |
| ---- | ---- | --------- |
| Shell plugins (bar / panels) | [`community-plugins/`](../community-plugins/) | `omarchy-shell` |
| Standalone apps (GTK, Qt, …) | `community-apps/` (this folder) | their own process + `.desktop` |

Keep this folder **outside** `omaxian/` so deploy never copies it into `$HOME`.
Do **not** seed these apps into stock `shell.json` or first-party
`shell/plugins/`.

## Layout

```text
community-apps/
  README.md
  lib/prebuilt.sh          # shared: deps lists + pinned-binary download
  lib/qmllint-qt68.sh      # QML check against Qt 6.8 (+ qmllint-ignore.txt)
  <app-id>/
    README.md              # Omaxian port notes + install
    omaxian.deps.json      # Debian apt (+ optional apt_build / manual)
    install.sh             # user-local install for this host
    .omaxian-upstream-commit
    .omaxian-prebuilt      # pinned pre-built binary (optional; see below)
    … upstream / patched sources …
```

### `omaxian.deps.json`

Same idea as community plugins: declare Debian packages the installer (or a
human) should install. Extra keys used by apps:

- `apt` — runtime packages. Everything the compiled binary links must be
  reachable from here: a downloaded binary gets **only** these (CI checks it).
- `apt_build` — packages needed only to compile from this tree
- `manual` — human follow-ups (models, agents, bar widget link)

`install.sh` reads both lists from this file (`app_deps_read` in
`lib/prebuilt.sh`), and so does the TUI. Do not repeat them in `install.sh`.

### Pre-built binaries (`.omaxian-prebuilt`)

By default `install.sh` downloads a pinned, sha256-checked binary and installs
only the `apt` packages. Everything else (`.desktop`, icons, fonts, Folio
plugins, i3 rules) still comes from this tree. It builds from source instead,
saying why, when:

- `--from-source` is passed (or the TUI's "Build everything from source")
- the app has no `.omaxian-prebuilt`, or the machine is not its `arch=`
  (x86_64 only for now)
- the system Qt is older than the binary's `qt=` (Qt apps are built against
  Qt 6.8 and run on 6.8 and newer)
- `<app>/` has local changes, or its tracked files differ from the source
  the binary was built from (`src=`, a hash of path, mode and blob id per
  file, so a shallow clone can check it too; files that only affect
  installing are ignored: `install.sh`, `*.md`, `omaxian.deps.json`,
  `.omaxian-prebuilt`)
- the download, checksum or unpack fails

Who builds them:

| App | Binary |
| --- | ------ |
| disktree | Upstream release, pinned by hand (Omaxian changes are packaging-only) |
| Every other app | `.github/workflows/community-apps.yml`: builds in `debian:trixie`, checks the binary on a clean trixie with only `apt` (libraries resolve; Qt apps also start headless with their QML loaded, which catches QML written for a newer Qt), publishes release `apps-<sha7>`, and opens a PR that rewrites `.omaxian-prebuilt` |

Until that PR lands for an app, its `install.sh` builds from source. Tag a
release only after it lands: `.github/workflows/release-pins.yml` fails a `v*`
tag whose pins are stale.
Plan and rationale:
[`docs/omaxian/plans/community-apps-prebuilts.md`](../docs/omaxian/plans/community-apps-prebuilts.md).

## Catalog

| Directory | App | Upstream | Status |
| --------- | --- | -------- | ------ |
| [`omarchy-meeting-recorder`](omarchy-meeting-recorder/) | Meeting Recorder (GTK4) | [jankeesvw/omarchy-meeting-recorder](https://github.com/jankeesvw/omarchy-meeting-recorder) `v1.8.0` | Ported |
| [`monologue`](monologue/) | Monologue (Qt Quick webcam recorder) | [omacom/monologue](https://github.com/omacom/monologue) `0.4.0` | Ported |
| [`signed`](signed/) | Signed (Qt Quick PDF signer) | [omacom/signed](https://github.com/omacom/signed) `0.3.2` | Ported |
| [`disktree`](disktree/) | disktree (GPUI disk treemap) | [tobi/disktree](https://github.com/tobi/disktree) `0.11.0` | Ported |
| [`plain`](plain/) | Plain (Qt Quick config/text editor) | [omacom/plain](https://github.com/omacom/plain) `0.3.3` | Ported |
| [`omacalc`](omacalc/) | Omacalc (Qt Quick calculator) | [omacom/omacalc](https://github.com/omacom/omacalc) `0.4.2` | Ported |
| [`omacut`](omacut/) | Omacut (Qt Quick video trimmer) | [omacom/omacut](https://github.com/omacom/omacut) `0.8.3` | Ported |
| [`omawrite`](omawrite/) | Omawrite (Qt Quick Markdown writer) | [omacom/omawrite](https://github.com/omacom/omawrite) `0.7.5` | Ported |
| [`folio`](folio/) | Folio (Qt Quick file manager) | [omacom/folio](https://github.com/omacom/folio) `61b7e20` | Ported |

**Not ported:** [omareel](https://github.com/omacom/omareel) — Hyprland plugin + `gpu-screen-recorder` / layer-shell capture; not viable on X11/i3.

## Install

During `./omaxian-install.sh`, accept the community-apps step and pick apps.
Outside the TUI:

```bash
./scripts/install-community-apps.sh --list
./scripts/install-community-apps.sh <dir>…
./scripts/install-community-apps.sh --from-source <dir>…   # never download
```

Or run one app’s installer directly (every `install.sh` takes
`--from-source` and `--skip-apt`):

```bash
./community-apps/omarchy-meeting-recorder/install.sh
```

Review the tree before running it; apps run unsandboxed as your user.

## Porting checklist

1. Prefer keeping the upstream app as a real standalone binary (do not rewrite
   it as a Quickshell plugin unless that is the product).
2. Replace Arch/Hyprland packaging with Debian user install + i3 glue.
3. Patch any `omarchy` group-dispatcher calls to `omarchy-*` binaries.
4. Pin upstream with `.omaxian-upstream-commit`; document deltas in `README.md`.
5. Source `lib/prebuilt.sh`, call `app_deps_read`, and use
   `prebuilt_fetch <name>` before building (see any existing `install.sh`).
   To have CI build it, add the dir to `CI_APPS` in
   `.github/scripts/prebuilt-plan.sh`.
6. Qt apps: run `lib/qmllint-qt68.sh <app>` (podman or docker) and make it
   pass. The binary targets Qt 6.8, and QML only fails when it loads: a
   property added after 6.8 builds fine, then the app will not start on
   Excalibur. Set such a property from JavaScript behind a same-line check,
   e.g. `Component.onCompleted: if (view.acceptedButtons !== undefined)
   view.acceptedButtons = Qt.NoButton`, and record the 6.8 fallback in the
   app's deltas table. `lib/qmllint-ignore.txt` is only for properties of the
   app's own C++ types, which qmllint cannot see. CI's verify step (headless
   start on Qt 6.8) is the final check.
7. Add a catalog row above. Do not wire into `setup` / `install` / `deploy`
   (the TUI / `scripts/install-community-apps.sh` discover dirs with
   `install.sh` automatically).

## See also

- [`community-plugins/README.md`](../community-plugins/README.md) — bar/panel ports
- [`docs/omaxian/install-scripts.md`](../docs/omaxian/install-scripts.md) — desktop install flow
