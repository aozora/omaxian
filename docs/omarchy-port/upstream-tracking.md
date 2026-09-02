# Keeping the port current with upstream Omarchy

How to absorb a new upstream Omarchy release into this port without losing the
X11/i3/Devuan adaptations.

This expands the four-line *"Upstream-tracking workflow"* in
[omarchy-migration.md](omarchy-migration.md) into a runbook, and is the plan the
`TODO.md` item *"plan instruction to semi-auto import changes/features from
upstream"* refers to.

---

## The model

Upstream is **not vendored in this git repo**. `setup.sh` / `install.sh` clone
`https://github.com/omacom/omarchy` into `omarchy-quattro/` at
`OMARCHY_UPSTREAM_REF` (default in both scripts). The directory is gitignored
(only `.gitkeep` is tracked). Never `git add` it. Treat it read-only — never
edit.

The clone is `--depth 1` and is **left as-is on later runs** if a `.git` is
already there. Changing the ref env var or the script default does nothing until
you wipe the checkout. That leftover `.git` is only the clone's own metadata so
the scripts can detect "already fetched"; it is not this project's history and
has no useful range to `git diff`.

| Tree | Relationship to upstream | On a bump |
|---|---|---|
| `omarchy-quattro/` | **Pinned clone**, gitignored. Source of truth for `themes/`, `default/`, and the `shell/` you re-mirror from. | Wipe the checkout, bump `OMARCHY_UPSTREAM_REF` in `setup.sh` **and** `install.sh`, re-run `install.sh`. |
| `omarchy-quattro/themes/`, `omarchy-quattro/default/` | Consumed **verbatim** — `install.sh` copies them straight to `~/.local/share/omarchy/`. Zero divergence. | Re-run `install.sh`. No code work. |
| `omaxian/.local/share/omarchy/shell/` | **Near file-for-file mirror** of `omarchy-quattro/shell/`. Every deviation is one row in [deltas.md](deltas.md). | Re-mirror, then re-apply every `deltas.md` row. |
| `omaxian/.local/share/omarchy/bin/` | **Hand-ported subset** — only the `omarchy-*` scripts a plugin or keybind actually calls, adapted per [omarchy-migration.md](omarchy-migration.md) §5. | Port new scripts on demand only. |
| `omaxian/.config/i3/`, `.xsessionrc`, picom, dunst, … | Port-authored; no upstream counterpart (upstream is Hyprland). | Unaffected by upstream bumps unless a keybind contract changes. |

**The invariant** (top of `deltas.md`): after a bump, every difference between
`omarchy-quattro/shell/` and `omaxian/.local/share/omarchy/shell/` must be either

1. a known mechanical transform — `T1` layer-shell→X11 window, `T2`
   `HyprlandFocusGrab`→X11 click-outside, `T3` `Quickshell.Hyprland`→`Quickshell.I3`,
   `drop-hyprctl`, `adapt-poll`, `pactl` (see migration §2a), **or**
2. a `Commons/`/`Style.qml` theming delta (migration §7), **or**
3. an explicit row in `deltas.md`.

Anything else is **drift** — fold it into upstream parity or delete it.

---

## Runbook for one upstream bump

Do this on a branch. One bump = one branch = pin commit + N port commits + a
`deltas.md` update + a smoke-test note. **Do not commit `omarchy-quattro/`.**

### 1. Snapshot the old checkout, then fetch the new one

`omarchy-quattro/` is not in this repo's git, so there is no
`git diff <prev-vendor>..<new-vendor> -- omarchy-quattro/` to lean on. Snapshot
first, then replace.

1. Record what you are leaving:
   - `omarchy-quattro/version`
   - `git -C omarchy-quattro describe --tags --always` (if `.git` exists)
   - the current `OMARCHY_UPSTREAM_REF` default in `setup.sh` / `install.sh`
2. Keep a copy of the trees you will review (the clone is shallow; once wiped,
   the old files are gone):

   ```
   cp -a omarchy-quattro/shell /tmp/omarchy-shell.prev
   cp -a omarchy-quattro/bin   /tmp/omarchy-bin.prev
   ```

3. Wipe the checkout. Keep the tracked placeholder:

   ```
   rm -rf omarchy-quattro
   git checkout -- omarchy-quattro/.gitkeep
   ```

   `install.sh` / `setup.sh` only clone when `omarchy-quattro/.git` is absent.
   Deleting files but leaving `.git` (or only bumping the ref) is a no-op.

4. Pin the new ref in **both** `setup.sh` and `install.sh` (`OMARCHY_UPSTREAM_REF`,
   currently `v4.0.2`). Then:

   ```
   OMARCHY_UPSTREAM_REF=<new-tag-or-sha> ./install.sh
   ```

   Confirm `omarchy-quattro/version` and
   `git -C omarchy-quattro describe --tags --always` match what you intended.

If you already wiped without a snapshot, use GitHub instead:

```
https://github.com/omacom/omarchy/compare/<old-ref>...<new-ref>
```

or `gh api repos/omacom/omarchy/compare/<old-ref>...<new-ref>`. That is the
changelog; the rest of the runbook is applying it to the port.

### 2. Read the upstream diff, bucket every change

```
diff -ruN /tmp/omarchy-shell.prev omarchy-quattro/shell
diff -ruN /tmp/omarchy-bin.prev   omarchy-quattro/bin
```

Also glance at `themes/` and `default/themed/*.tpl` (via GitHub compare, or a
third `diff -ruN` if you snapshotted those too). Sort each change into:

| Upstream area | Action |
|---|---|
| `themes/`, `default/themed/*.tpl` | Re-run `install.sh`. Done. (If a `.tpl` gained a token the X11 templaters in `omaxian/.config/omarchy/themed/` don't emit, add it there.) |
| `shell/Commons/`, `shell/Ui/`, `shell/services/` | Mostly **byte-identical mirrors** (see `deltas.md` — the `Commons/`,`Ui/` "everything not rowed" row). Overwrite the ported copies with the new upstream files, then re-apply only the handful of rows that touch this area: `Style.qml` `drop-hyprctl`, `Ui/PopupCard.qml` `T2`, `Ui/KeyboardPanel.qml` `T1`, `Ui/SpeedTestOverlay.qml`/`Ui/CenteredModal.qml`, `shell.qml` deltas **S1–S5**. |
| `shell/plugins/bar/`, `shell/plugins/panels/` | Apply the **per-file transform** named in `deltas.md`'s per-file map / migration §2b. Diff the old vs new upstream version of each file, replay those hunks onto the ported copy, then re-apply its delta. |
| `shell/plugins/<new-plugin>/` | Decide: port / skip / defer. **Record the decision as a new `deltas.md` row even if it's "not ported this pass"** — a silent omission is indistinguishable from drift next time. |
| `bin/<new or changed omarchy-*>` | Port **only if** a ported plugin or an i3 keybind calls it. Adaptation rules: migration §5 (`pacman`→`apt`, `hyprctl`→`i3-msg`/`xrandr`, `systemd*`→`sv`/`setsid`/`loginctl`, `wl-copy`→`xclip`, `grim`/`slurp`→`maim`/`slop`, `walker`/`wofi`→`rofi`, `systemd-cat`→`logger`). |
| `manual/`, `install/` (Arch installer) | Reference only. Not ported. `manual/07-hotkeys.md` is the source of truth if reconciling i3 keybinds. |

### 3. Re-mirror, file by file

For every `shell/` file:

- If `deltas.md` calls it **byte-identical / converged / verbatim** → just copy
  the new upstream file over the ported one in `omaxian/.local/share/omarchy/shell/`.
- If it has a delta row → apply the upstream hunks, then re-apply the delta.
  The row's *Notes* column usually says exactly what must never be re-added
  (e.g. *"never re-add the `Process`/fontconfig blocks"*, *"never re-add the
  `Wlr*` attached properties"*).

### 4. Update `deltas.md`

- Bump the dated section header / "as of" note (include the new
  `OMARCHY_UPSTREAM_REF` and `omarchy-quattro/version`).
- Add a row for every new divergence and every skipped upstream plugin.
- Mark rows that upstream changes made **converged** (delete the local
  divergence, reset to upstream).
- Delete rows for files that no longer exist upstream.

### 5. Rebuild and smoke-test

```
./install.sh && ./deploy.sh
omarchy-restart-shell
tail -f ~/.local/state/omarchy/shell.log     # watch for QML load errors
```

Then click through: every bar widget, each panel (audio / bluetooth / network /
weather / power / calendar), the launcher, the dock, a theme switch
(`omarchy-theme-set <name>`), and any popup with a keybind. Many `deltas.md`
rows record the original smoke check for that file — reuse them.

### 6. Quickshell version check

The port is pinned to a **locally built Quickshell 0.3.0** (no Devuan package —
see `docs/quickshell/README.md`). Before starting a bump, check whether the new
upstream `shell/` needs QS APIs the local build lacks:

- new `PanelWindow` / `PopupWindow` properties,
- `Quickshell.Services.Pipewire` (the local build ships it as a **type-only
  stub** — see the `Services/Audio.qml` delta row),
- anything under `Quickshell.Wayland` with no `Quickshell.I3` / X11 analogue.

If it does, that's a **separate dependency bump** (rebuild QS from a newer tag,
re-verify the X11 `XPanelWindow` strut behaviour) — do it first, on its own
branch.

---

## Making it semi-automatic (the open TODO)

Cheap wins, roughly in order of value:

1. **`bin/omarchy-port-diff`** — wrap
   `diff -ruN omarchy-quattro/shell omaxian/.local/share/omarchy/shell`,
   filter out every path that has a `deltas.md` row, and print only the
   **unclassified** hunks. That set should be empty after a clean bump; anything
   left is drift to triage. Run it in CI / a pre-commit check too.
2. **A "verbatim" assertion** — a script that, for every file `deltas.md` marks
   byte-identical, `cmp`s the ported copy against `omarchy-quattro/`. Fails loud
   if they've drifted. This is the single highest-leverage guard: it keeps the
   "mirror" honest between bumps.
3. **Machine-readable `deltas.md`** — a front-matter table or sidecar
   `deltas.toml` (`path`, `transform`, `status`, `smoke`) so `omarchy-port-diff`
   and the verbatim check read the same source the humans do.
4. **Single pin source** — `OMARCHY_UPSTREAM_REF` is duplicated in `setup.sh`
   and `install.sh`. One file (or one sourced snippet) would stop a bump from
   updating only one of them.

A true submodule/subtree (recorded SHA, `git range-diff`) would bring back
in-repo upstream diffs, at the cost of vendoring ~140 MB of themes. The current
gitignored clone is the deliberate trade-off; the snapshot in step 1 is how
review stays possible.

---

## Cadence

- Upstream Omarchy commits frequently. **Don't chase every commit** — track
  tagged releases / the `version` file changing (alpha → beta → stable of the
  quattro line are the real checkpoints).
- Batch a bump into one branch; land it only after the full smoke pass.
- If a bump is large, split by area: pin + fetch → `Commons`/`Ui` re-mirror →
  `plugins/panels` → `plugins/bar` → `bin` → `deltas.md` → smoke note, each its
  own commit, so a regression bisects cleanly.
