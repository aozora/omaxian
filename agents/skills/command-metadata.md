# Command Metadata

Read this before adding or changing commands in `omaxian/.local/share/omarchy/bin/`.

Omaxian has no `omarchy` group dispatcher. Each file is invoked by its filename
(`omarchy-theme-set`, `omarchy-restart-shell`). Metadata comments near the top
of the file still document the command for humans and for anything that scans
them the same way upstream `bin/omarchy` does.

Supported metadata keys:

- `# omarchy:group=...` - logical group (theme, plugin, network, system, …)
- `# omarchy:name=...` - short name when it differs from the filename tail
- `# omarchy:summary=...` - short help text
- `# omarchy:args=...` - usage arguments
- `# omarchy:examples=...` - examples separated with ` | `
- `# omarchy:alias=...` / `# omarchy:aliases=...` - alternate names users already type
- `# omarchy:hidden=true` - hide from listings / treat as internal
- `# omarchy:requires-sudo=true` - mark commands that require sudo

Only use `omarchy:examples` where there are args that need explaining.

Prefer explicit metadata for user-facing commands. Keep the filename as
`omarchy-<group>-<action>` unless there is a deliberate compatibility name.

Examples in metadata may show the upstream `omarchy <group> <action>` form for
readers coming from Omarchy; the working invocation in this port is always the
binary on `PATH`.

Example:

```bash
# omarchy:summary=Apply an Omarchy theme (X11 / i3 / picom / dunst / GTK / Quickshell port)
# omarchy:args=<theme-name>
# omarchy:examples=omarchy-theme-list | omarchy-theme-set "Tokyo Night"
```

New commands belong in `omaxian/.local/share/omarchy/bin/` so `install.sh` and
`deploy.sh` ship them. Do not add commands under `omarchy-quattro/bin/`.
