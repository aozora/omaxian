# Reporting a Crash Upstream

Read this only after concluding that a crash is genuinely Omaxian's or
Omarchy's to fix.

## Whose bug is it?

Be strict. Omaxian is a configuration layer over Devuan/Debian + i3 +
Quickshell. A crash inside a third-party application — a file manager, a
browser, a GNOME or Qt library — is almost always an upstream bug in **that**
project.

Omaxian's sphere of control is roughly:

- the `omarchy-*` commands in this port
- the Quickshell shell and its plugins as shipped here
- the i3, picom, dunst, and terminal configuration it ships
- its themes and templates
- `setup.sh` / `install.sh` / `deploy.sh`

Omarchy's sphere (file there, not here) is the same pieces **as they exist on
Arch + Hyprland**, when the bug is not caused by this port's X11/Debian
changes.

A crash in a program Omaxian merely installs via apt is **not** an Omaxian bug
unless this port's own packaging or configuration is implicated.

If it is not Omaxian's and not Omarchy's, say so and stop. Suggesting the right
upstream project is useful; filing there yourself is not part of this.

## Three conditions, all required

1. **It is a verified bug** in Omaxian's or Omarchy's sphere, established on
   evidence.
2. **The user has explicitly agreed.** Show them the exact title and body you
   propose, and wait for a yes. Never file unprompted.
3. **The machine can file it** — `gh auth status` must succeed. If `gh` is
   missing or unauthenticated, do not install or authenticate it. Say so, and
   hand the user the finished text to submit themselves.

## Search before filing

```bash
# Omaxian (X11 / i3 / Debian port)
gh search issues --repo aozora/omaxian "<program> crash"
gh issue list --repo aozora/omaxian --state all --search "<signal> <program>"

# Upstream Omarchy (only if it would also fail on Arch + Hyprland)
gh search issues --repo omacom/omarchy "<program> crash"
```

Search on the crashing program, the signal, and distinctive symbols from the
backtrace. Include **closed** issues. `gh search issues` accepts only `open` or
`closed` for `--state`; leaving it off searches both.

## Adding to an existing report

```bash
gh issue view <number> --repo aozora/omaxian --comments
```

Confirm it is genuinely the same failure. If it is, comment only when you have
something the thread does not already contain.

```bash
gh issue comment <number> --repo aozora/omaxian --body "..."
```

A comment that only says the bug happens to you too is noise.

## Filing a new issue

```bash
gh issue create --repo aozora/omaxian --title "..." --body "..."
```

Include what happened, what was expected, steps to reproduce, OS details, and
`~/.local/state/omarchy/shell.log` when the shell is involved. There is no
`omarchy debug` in this port.

`gh` cannot attach media. If a screenshot would help, save one and give the user
the path to drag into the web form.

## Signing

End the issue or comment with a line naming the model and agent harness that
produced it, so a human reader knows it was machine-authored:

> Filed by \<model name\> via \<agent harness\>.

Use your actual model and harness names. If you are not certain of them, say so
plainly rather than inventing a version string.
