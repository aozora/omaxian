# Omamail (Omaxian port)

Email client for the Omaxian bar and shell. Port of
[huacnlee/omamail](https://github.com/huacnlee/omamail)
(upstream commit `2d5f2bd`, plugin version `0.10.8`).

Plugin id: `omamail` (unchanged). Optional — not installed by `./deploy.sh`.
See [`../README.md`](../README.md) for the catalog install pattern.

A native email and calendar app for Omarchy/Omaxian, with multiple accounts,
keyboard navigation, AI assistance and your desktop theme.

## Omaxian deltas

| Upstream (Omarchy) | This port |
| ------------------ | --------- |
| `Service.copyText` → Wayland clipboard CLI | Qt clipboard in `Service.copyText` |
| Wayland paste CLI then `xclip` for compose paste | `xclip` only |
| `default-mail.sh` → Hyprland `bindings.lua` + compositor reload | `~/.config/i3/config.d/99-omamail-default-mail.conf` + `i3-msg reload` |
| Hyprland bind example | i3 bind example below |
| Standalone Qt host under `app/` | Omitted; [`standalone/`](standalone/) runs the plugin UI in its own Quickshell window instead |
| `omarchy-mise-install` for `hey` | [hey-cli](https://github.com/basecamp/hey-cli) / setup-page install line |
| `omarchy plugin add` / `make install` | rsync into `~/.config/omarchy/plugins/`; later `omarchy-plugin-update --from` |

`FloatingWindow`, `KeyboardPanel`, `secret-tool`, `curl`, and `notify-send` work
as on Omarchy. File attach uses `omarchy-file-select` when present, otherwise
`zenity`. Agent instruction files (`.agents/`, `AGENTS.md`) and the upstream Qt host
(`app/`) are omitted from this tree.

---

<img width="800" alt="Omamail — reading mail with AI assistance" src="docs/images/full-mail.webp" />

## Features

- **Multiple mailboxes:** Gmail, Outlook, HEY, JMAP and IMAP/SMTP, including Fastmail, iCloud and self-hosted servers.
- **Mail and calendar:** read, search, compose, manage attachments and respond to meeting invitations. Available actions depend on your provider.
- **Keyboard navigation:** `j`/`k` to move, `r` to reply, `c` to compose, `/` to search and `?` for all shortcuts.
- **AI assistance:** ask about selected messages and review suggested drafts using your Omarchy AI setup (Claude, Codex, or OpenCode). Optional: suggest calendar events from mail (`suggestEvents` in Settings). See the [keyboard guide](docs/KEYS.md) for the AI dock shortcuts.
- **Desktop integration:** theme matching, unread counts, notifications, `mailto:` links, optional default mail client registration, and a compact layout for smaller windows.
- **Privacy controls:** credentials stored in the system keyring and remote images blocked until you choose to load them.

<img width="265" alt="Omamail calendar" src="docs/images/full-calendar.webp" /> <img width="265" alt="Writing a message" src="docs/images/full-compose.webp" /> <img width="265" alt="Compact message list" src="docs/images/mini-list.webp" />

## Install the plugin

From the Omaxian repo root:

```bash
PLUGIN=community-plugins/omamail
ID=$(jq -r .id "$PLUGIN/manifest.json")

omarchy-plugin-check "$PLUGIN"
omarchy-plugin-validate "$PLUGIN"

mkdir -p ~/.config/omarchy/plugins
rsync -a --delete -- "$PLUGIN/" "$HOME/.config/omarchy/plugins/$ID/"

omarchy-shell shell rescanPlugins
# rescan is async; omarchy-plugin-enable waits briefly for the id to appear
omarchy-plugin-enable "$ID"
"$HOME/.config/omarchy/plugins/$ID/scripts/register-mailto.sh" \
  "$HOME/.config/omarchy/plugins/$ID" --claim-default
```

### Update

When this port changes in the repo, refresh the installed tree (keeps accounts
and enablement):

```bash
omarchy-plugin-check "$PLUGIN"
omarchy-plugin-validate "$PLUGIN"
omarchy-plugin-update "$ID" --from "$PLUGIN"
```

Git installs: `omarchy-plugin-update omamail`. See
[`../README.md`](../README.md#update).

Open Omamail and explicitly install its backend when prompted. Loading the
plugin never downloads a binary. The installer uses the exact `backend-version`
release for Linux x86_64 or aarch64 and keeps it at `runtime/bin/omamail` inside
the plugin. See [backend installation and releases](docs/BACKEND-RUNTIME.md).

Then click the envelope in the bar. To open it from the keyboard, add an i3
bind (e.g. in `~/.config/i3/config.d/`):

```
bindsym $mod+Shift+g exec --no-startup-id omarchy-shell shell toggle omamail '{}'
```

Requires a running `omarchy-shell`, the Rust backend, `secret-tool`, `xdg-open`,
`python3`, `curl`, and `xclip` for keyring, desktop integration, and compose
paste. Attach picker: `zenity` (or `omarchy-file-select` if you have it).

```bash
sudo apt install libsecret-tools xdg-utils python3 curl xclip zenity
```

## Run as a standalone app

Omamail can also run as its own window, with no `omarchy-shell` and no bar
widget. It reuses the plugin UI unchanged, in plugin mode (not upstream's
`platform.standalone` mode), so credentials, notifications, clipboard and
attachments use the same scripts as the plugin.

```bash
community-plugins/omamail/standalone/install.sh --build-backend
omamail-app
```

- `install.sh` links `~/.local/share/omamail-app/` to this checkout (no copies)
  and the Omaxian shell's `Commons`/`Ui`, and puts `omamail-app` in
  `~/.local/bin`. `--build-backend` runs `cargo build --release` and installs
  the result (about 2 minutes); without it, use the in-app backend setup.
  `--claim-mailto` makes it the `mailto:` handler; `--uninstall` removes it.
- The window is **tiled** by default. `omamail-app --floating` (or
  `OMAMAIL_FLOATING=1`) floats it on open, or add an i3 rule such as
  `for_window [title="^Omamail$"] floating enable`.
- A second `omamail-app [mailto:… | --compose | --calendar]` hands the request
  to the running window and focuses it. Closing the window quits the app and its
  backend.
- Quickshell windows always report the X11 class `quickshell`, so the launcher
  sets `WM_CLASS` to `omamail`/`Omamail` once the window maps
  (`standalone/set-wm-class.py`). That is what lets the Omaxian dock and the
  `.desktop` entry (`StartupWMClass=Omamail`) recognise it as Omamail.
- Accounts, backend and cache are shared with the plugin install
  (`~/.config/omamail`, `~/.local/share/omamail`). Do not run both at once.
- Needs `quickshell`, the Omaxian shell files (`$OMARCHY_PATH/shell`),
  `libsecret-tools`, `python3` and `xclip`, plus `cargo` for `--build-backend`.

## Add your mailbox

Choose a provider in Settings. Gmail needs a Google OAuth client; Outlook needs
a Microsoft app registration. HEY uses the official
[HEY CLI](https://github.com/basecamp/hey-cli) (install via their docs or
`curl -fsSL https://hey.com/install-cli | bash` — Omaxian does not ship
`omarchy-mise-install`). JMAP and IMAP usually use an app password or API token.

See [mailbox setup](docs/MAILBOXES.md) for provider instructions and limitations,
including Microsoft 365 and Proton Mail Bridge.

Press `?` in Omamail for the shortcut sheet, or see the [keyboard guide](docs/KEYS.md).

## Help and contributing

- [Backend installation, updates and recovery](docs/BACKEND-RUNTIME.md)
- [Contributing](CONTRIBUTING.md)
- Upstream: [huacnlee/omamail](https://github.com/huacnlee/omamail)

Omamail is an independent project and is not affiliated with Google, Microsoft or 37signals. Gmail, Outlook and HEY belong to their respective trademark owners.

Licensed under the [MIT License](LICENSE).
