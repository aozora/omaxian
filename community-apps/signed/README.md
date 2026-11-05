# Signed (Omaxian port)

Qt Quick PDF signer. Open a PDF, place a signature, text, or a date, and save
a copy. An optional self-signed seal shows later edits.

Port of [omacom/signed](https://github.com/omacom/signed) 0.3.1
(upstream commit `7d6a7cf`, pinned in `.omaxian-upstream-commit`). Full upstream
docs: [`README.upstream.md`](README.upstream.md).

This is a **standalone app**, not a Quickshell plugin. It lives under
`community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| `omarchy pkg add` / `makepkg` (`bin/install`) | Debian `install.sh` → `~/.local`. Arch script kept as `bin/install.arch` |
| Runtime dep `qt6-wayland` | Not installed. The binary is a `QGuiApplication` and uses XCB |
| Corner radius from `hyprctl` | Unchanged; already gated on `HYPRLAND_INSTANCE_SIGNATURE` (square corners on i3) |
| `noto-fonts`, `poppler-qt6`, `qpdf`, `nss` | `fonts-noto-core`, `libpoppler-qt6-3t64`, `libqpdf30`, `libnss3` |
| File chooser via xdg-desktop-portal | Same, with `xdg-desktop-portal-gtk` |
| Theme accent from `colors.toml` | Unchanged |

Placed text is still measured in Noto Sans and embedded in the PDF. The
desktop entry advertises `application/pdf` and is not set as the default viewer.

## Requirements

Runtime (also in `omaxian.deps.json`):

- Qt 6 Quick and Quick Controls, `qt6-qpa-plugins`, `qt6-image-formats-plugins`
- `libpoppler-qt6-3t64`, `libqpdf30`, `libnss3`
- `fonts-noto-core` (the "Noto Sans" family the stamper measures)
- `xdg-desktop-portal` and `xdg-desktop-portal-gtk`

Build: `qmake6`, `qt6-base-dev`, `qt6-declarative-dev`, `libpoppler-qt6-dev`,
`libqpdf-dev`.

## Install

```bash
community-apps/signed/install.sh
```

`install.sh` refuses to apt-install Qt when the `qmake6` candidate's major.minor
does not match the already-installed `libqt6core6t64`.

| Path | Role |
| ---- | ---- |
| `~/.local/bin/signed` | app |
| `~/.local/share/applications/signed.desktop` | launcher (`Exec` is the full path) |
| `~/.local/share/icons/hicolor/scalable/apps/signed.svg` | icon |

Open **Signed** from the launcher, or `signed open file.pdf`.

## Smoke check

1. `signed open some.pdf` shows the pages.
2. Place text and a signature image, then save a `-signed.pdf`. The original file is unchanged.
3. Switch theme (`omarchy-theme-set …`). The accent should follow. Corners stay square on i3.

## Uninstall

```bash
rm -f ~/.local/bin/signed
rm -f ~/.local/share/applications/signed.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/signed.svg
```

Signatures in `~/.local/share/signed/` and certificates next to them are left alone.

## License

MIT (upstream).
