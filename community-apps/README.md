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
  <app-id>/
    README.md              # Omaxian port notes + install
    omaxian.deps.json      # Debian apt (+ optional apt_build / manual)
    install.sh             # user-local install for this host
    .omaxian-upstream-commit
    … upstream / patched sources …
```

### `omaxian.deps.json`

Same idea as community plugins: declare Debian packages the installer (or a
human) should install. Extra keys used by apps:

- `apt` — runtime packages
- `apt_build` — packages needed only to compile from this tree
- `manual` — human follow-ups (models, agents, bar widget link)

## Catalog

| Directory | App | Upstream | Status |
| --------- | --- | -------- | ------ |
| [`omarchy-meeting-recorder`](omarchy-meeting-recorder/) | Meeting Recorder (GTK4) | [jankeesvw/omarchy-meeting-recorder](https://github.com/jankeesvw/omarchy-meeting-recorder) `v1.8.0` | Ported |
| [`monologue`](monologue/) | Monologue (Qt Quick webcam recorder) | [omacom/monologue](https://github.com/omacom/monologue) `0.3.1` | Ported |
| [`signed`](signed/) | Signed (Qt Quick PDF signer) | [omacom/signed](https://github.com/omacom/signed) `0.3.1` | Ported |
| [`disktree`](disktree/) | disktree (GPUI disk treemap) | [tobi/disktree](https://github.com/tobi/disktree) `0.11.0` | Ported |

## Install

Each app ships its own `install.sh`. Example:

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
5. Add a catalog row above. Do not wire into `setup` / `install` / `deploy`.

## See also

- [`community-plugins/README.md`](../community-plugins/README.md) — bar/panel ports
- [`docs/omaxian/install-scripts.md`](../docs/omaxian/install-scripts.md) — desktop install flow
