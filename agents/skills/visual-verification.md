# Visual Verification

Read this before finishing any change with a visual effect: Omaxian shell
styling and layout, panels, menus, notifications, i3 appearance, picom,
dunst, animations, and screenshot flows.

Visual changes must be verified in the running UI in addition to any smoke
commands. Creating an artifact is not sufficient: inspect it for clipping,
overlap, incorrect spacing, stale state, focus problems, and visual
regressions before finishing.

There is no `omarchy capture` / `omarchy screenshot` / `omarchy screenrecord`
in this port.

## Do not crash the session

**Never** run `omarchy-restart-shell`, stop/kill picom, or kill Quickshell
to “pick up” a QML edit for verification. Under glx picom that sequence has
frozen or torn down the whole X session (including when two restarts overlap).
Plugin hot-reload rebuilds the bar the same way — also forbidden on a live
desktop.

Safe apply path only:

1. Edit under `omaxian/`
2. User runs `./deploy.sh` (or agent copies with the deploy lock held and
   **without** stopping picom)
3. **Log out and back in** so QML loads fresh

If you cannot log out, leave the fix in the repo and say so. Do not gamble
on a live shell restart.

Take a full-screen screenshot without opening the editor:

```bash
~/.config/i3/scripts/i3_screenshot --now
```

Region and window:

```bash
~/.config/i3/scripts/i3_screenshot --area
~/.config/i3/scripts/i3_screenshot --win
```

`maim` writes PNG to the Pictures `Screenshots` directory and copies to the
clipboard via `xclip`. Super+Ctrl+C runs `--area` (region select).

Screen recording is **not ported**. Do not call `omarchy screenrecord`,
`wf-recorder`, or `wl-screenrec`. If a change is about timing or animation,
take before/after screenshots or record with a tool the user already has
(e.g. `ffmpeg -f x11grab`), and keep it short.

For interactive UI work, use `xdotool` to simulate keyboard input when
available (this is X11; `wtype` is Wayland). Example: wait briefly for
focus, then `xdotool key Right Return` to exercise keyboard selection.
Prefer this over manual-only verification when a UI returns a selected
value or changes a symlink/config.

If a launched UI would otherwise remain open, keep track of its PID and stop
it after the screenshot; avoid broad process kills unless checking with `ps`
first. Escape dismisses Omaxian panels; click-outside does not always close
a popup (see README).
