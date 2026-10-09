# Security

This plugin copies passwords and two-factor codes. You are right to be careful
about what you install for that. This document states plainly what the plugin
can and cannot do, and how to check every claim yourself. Nothing here asks you
to take our word for it.

This is the Omaxian (X11) port of josh2c/omarchy-protonpass. The threat model
matches upstream; clipboard tooling is `xclip` / `xsel` instead of the Wayland
clipboard CLI.

## Security at a glance

- **It makes no network connections of its own.** Only Proton's official
  `pass-cli` talks to Proton's servers. The plugin never opens a socket, never
  calls out, never "phones home."
- **It never sees your Proton password.** Signing in opens Proton's own
  `pass-cli` in a terminal. Your password and any 2FA go straight to Proton; the
  plugin only checks afterward that a session exists.
- **It never shows or stores a secret.** Field values go from `pass-cli` straight
  to your clipboard. They never appear in the panel, never touch a log, never
  land in a file.
- **The only things it writes to disk** are a list of recently used item IDs (no
  names, no secrets) and a one-way hash of the last value it copied (used to
  auto-clear the clipboard safely). Both are yours-only files, and the recents
  list is deleted the moment you turn the setting off.

## Verify it yourself

The entire runtime is four files (one Bash helper, two QML files, one small
JavaScript file). Run these from the plugin directory:

```sh
# No network code. This returns nothing at all.
grep -rnE 'curl|wget|http|nc |socket|XMLHttpRequest' *.qml Keybinds.js omarchy-protonpass

# Secrets are never revealed: the only hits for --show-secrets are this
# document and the test that FORBIDS it.
grep -rn 'show-secrets' .

# Every secret clipboard write goes through clipboard_copy (xclip/xsel).
# There is no --sensitive on X11; auto-clear is the history mitigation.
grep -nE 'clipboard_copy|xclip|xsel|have_clipboard' omarchy-protonpass

# Sign-in is delegated to the official CLI in a terminal.
grep -n 'pass-cli login' Panel.qml

# No arbitrary-code constructs in the helper or the keybind parser.
grep -nE 'eval|sh -c|`' omarchy-protonpass Keybinds.js
```

And the strongest check is mechanical: `tests/security-test.sh` runs offline
with no Proton account. It statically forbids `--show-secrets`, `eval`, `sh -c`,
exported secret variables, and secret-shaped UI properties, and it dynamically
plants a marker "secret," runs a real copy, and scans process arguments, the
environment, and every file the run touched to prove the marker never escaped.
You can run it yourself: `bash tests/security-test.sh`.

## Scope and limits

**Assets.** Your field values (passwords, usernames, TOTP codes); your Proton
session; the clipboard; and the availability of the Omarchy shell process the
panel runs inside.

**Adversaries.** A local unprivileged process on your machine reading arguments,
environment, or files. An editor of a vault you have accepted a share of, who
authors the item metadata this plugin reads. Anyone who can read your clipboard
history.

**Explicitly out of scope.** A compromised Proton account or `pass-cli` binary;
a compromised Omarchy shell; a privileged local attacker who can read another
process's memory; and physical access to an unlocked session.

**How the helper and the CLI are found.** The panel runs the helper from the
plugin directory, and the helper runs `pass-cli` by name, resolved through your
`PATH`. `OMARCHY_PROTONPASS_HELPER` overrides which helper the panel runs (tests
use it). Anything that can set a variable in the shell's environment, or plant a
`pass-cli` earlier in your `PATH`, can choose the code behind this plugin.

**Shared vaults.** Item titles and vault names are treated as untrusted input:
length, vault count, item count, response size, and indexing time are bounded,
and control / bidi characters are stripped before display.

## How copying a secret actually works

1. You pick an item and an action. The panel sends the helper only an **opaque
   item ID** and a **field name** (`username` / `password` / `totp`), never a
   value.
2. The helper asks `pass-cli` for that one field. The value arrives on a pipe and
   lives in a single shell variable that is never exported and is erased right
   after use.
3. The value is piped to `xclip` (or `xsel`). X11 has no clipboard "sensitive"
   flag, so Omarchy clipboard history — if you use one — may see the value. The
   configured auto-clear shortens that window; clear manually with
   `Ctrl+Shift+X` when you are done.
4. After the configured delay, the clipboard is cleared, but **only if it still
   holds exactly the value we put there.** If you copied something else in the
   meantime, your newer content is left untouched.

The value never crosses into the panel/UI layer. The panel only ever handles
non-secret metadata: item titles, vault names, and which field you asked for.

## What it deliberately never does

- Never runs with, stores, or transmits your Proton password; sign-in and unlock
  happen only in the official CLI, in a terminal you control.
- Never uses `pass-cli --show-secrets`.
- Never displays a password, TOTP code, or username on screen.
- Never writes a secret value to any file, log, notification, or command line.
- Never bundles, patches, or installs Proton software.

## Honest limits

- **Anything already running as your user.** A program under your account can
  already read your `pass-cli` session, process memory, and live clipboard.
- **The clipboard while a value is live.** On X11, any same-user client can read
  the selection while a value sits there. There is no `--sensitive` equivalent;
  auto-clear and a short clear delay are the mitigations.
- **The one-way hash at rest.** A SHA-256 of the last copied value lives in a
  user-only runtime file so auto-clear can compare safely. A low-entropy value
  (e.g. a 6-digit TOTP) can be guessed offline from that hash. The file is
  deleted when the clipboard is cleared.
- **Offline access.** Listing and copying require a network connection every
  time.

## Reporting a vulnerability

If you find a security issue, please report it privately: open a GitHub security
advisory on the upstream repository, or email the maintainer at the address in
the commit history, rather than filing a public issue.
