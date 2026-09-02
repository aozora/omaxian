# Acceptance Tests

Read this before looking for a graphical acceptance suite.

Omaxian does **not** ship `test/acceptance.d/`, `./test/all`, or an ISO
harness. Upstream Omarchy runs that suite in a disposable VM through the
sibling `omarchy-iso` repository against Arch + Hyprland. Those commands
(`omarchy-iso-test`, `omarchy-iso-make`, QMP, `wtype`) do not apply here.

Do not run graphical tests in the user's active session as if they were an
automated suite: they would open and close apps and rewrite desktop config
on the machine being used.

## What to run instead

On a deployed Omaxian session:

```bash
omarchy-shell shell ping                 # → ok
omarchy-shell shell listPlugins | jq length
pgrep -x quickshell                      # one process
omarchy-plugin-check /path/to/plugin     # community plugins only
```

Logs: `~/.local/state/omarchy/shell.log`. For live QML errors:

```bash
quickshell -n -p ~/.local/share/omarchy/shell
```

Exercise the changed UI in the running session and capture it per
[`visual-verification.md`](visual-verification.md). Restore any config you
temporarily changed.

If a future in-tree test directory is added, put CLI/shell tests next to
the code they cover and keep graphical checks out of `./test` runners that
developers would execute on their live desktop.
