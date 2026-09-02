# Reporting Issues and Submitting PRs

Read this when the user wants to report a bug, suggest a feature, or
contribute a fix.

Omaxian lives at https://github.com/aozora/omaxian. Upstream Omarchy lives at
https://github.com/omacom/omarchy.

Route requests to the right place:

- **Bugs in this X11 / i3 / Debian port** (bar, dock, Settings, i3 binds,
  `omarchy-*` wrappers, picom, dunst, apt widgets, …) → Omaxian
- **Bugs in upstream Omarchy itself** (a behavior that is wrong on Arch +
  Hyprland too) → Omarchy, not here
- Do **not** file Hyprland-only missing features as Omarchy bugs when this
  port documented them as skipped (see the Omaxian README and
  `docs/omarchy-port/deltas.md` in the git checkout)

## Filing a good bug report (Omaxian)

Gather:

```bash
omarchy-shell shell ping
# log
tail -n 200 ~/.local/state/omarchy/shell.log
# capture the problem — see capture.md
~/.config/i3/scripts/i3_screenshot --now
```

Include: OS (`devuan` / `debian`, version), i3 and Quickshell versions,
what happened, what was expected, steps to reproduce, and the log / screenshot.

File with `gh` when available:

```bash
gh issue create --repo aozora/omaxian --title "..." --body "..."
```

`gh` cannot attach media. Save a screenshot and give the user the path to
drag into the web form.

Wait for the user to agree before filing. Never file unprompted.

## Submitting a PR

Never develop against `~/.local/share/omarchy` in place. Clone the checkout:

```bash
gh repo fork aozora/omaxian --clone
cd omaxian
```

Follow the repository `AGENTS.md` for style and commit conventions. Edit
`omaxian/`, not `omarchy-quattro/`. Keep commits atomic. A PR that fixes a
visual problem should include before/after captures (see [`capture.md`](capture.md)).
