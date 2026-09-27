# Calculator (Omaxian port)

A quick calculator for the Omaxian shell. Press a key, type a calculation, and
the result appears next to it as you type. `Enter` copies the result to the
clipboard and closes.

Port of [canclini/omarchy-calculator](https://github.com/canclini/omarchy-calculator)
(upstream commit `0bfb983`).

Plugin id: `io.github.canclini.calculator` (unchanged). Optional — not installed
by `./deploy.sh`. See [`../README.md`](../README.md) for the catalog install
pattern.

![The calculator showing (1250 + 8,1%) × 12 = 16215](preview.png)

## Omaxian deltas

| Upstream (Omarchy / Hyprland) | This port |
| ----------------------------- | --------- |
| Full-screen layer-shell overlay | `Ui/CenteredModal` (T1; no picom black-out) |
| Wayland clipboard CLI | `xclip` (fallback `xsel`) |
| Hyprland bind / `bindings.lua` | i3 bind example below |
| `omarchy plugin add` / bar move CLI | Local rsync install; Settings → Plugins for enablement |

`CalcModel.js`, `BarWidget.qml`, and the evaluator tests are unchanged.

## Requirements

Omaxian with third-party shell plugins enabled, and `xclip` (or `xsel`) for
copying the result. `xclip` is in the recommended / `setup.sh` set.

```bash
sudo apt install xclip
```

## Install

From the Omaxian repo root:

```bash
PLUGIN=community-plugins/io.github.canclini.calculator
ID=$(jq -r .id "$PLUGIN/manifest.json")

omarchy-plugin-check "$PLUGIN"
omarchy-plugin-validate "$PLUGIN"

mkdir -p ~/.config/omarchy/plugins
rsync -a --delete -- "$PLUGIN/" "$HOME/.config/omarchy/plugins/$ID/"

omarchy-shell shell rescanPlugins
omarchy-plugin-enable "$ID"
```

A calculator icon appears in the center of the bar; click it to open. Move the
widget in Settings → Bar, or with the shell’s bar layout tools.

### Update

```bash
omarchy-plugin-update "$ID" --from "$PLUGIN"
```

### Remove

```bash
omarchy-plugin-remove io.github.canclini.calculator
```

Then delete any i3 keybinding or menu line you added.

## Open it from the keyboard

The plugin does not bind a key on its own. i3 example (put in
`~/.config/i3/config.d/` or similar, then `i3-msg reload`):

```
bindsym $mod+Mod1+c exec --no-startup-id omarchy-shell shell toggle io.github.canclini.calculator
```

To also find it in the Omarchy menu, add this line to
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"calculator": {"icon":"󰃬","label":"Calculator","action":"omarchy-shell shell summon io.github.canclini.calculator {}"},
```

## Features

- **Live result:** shown next to the expression while you type; `Enter` copies it and closes.
- **Editing:** move with the arrow keys, `Home` and `End`, select with `Shift`, paste with `Ctrl+V`.
- **Parentheses:** select part of the expression and type `(` to wrap it; deleting a parenthesis also deletes its partner.
- **Percent like a desk calculator:** `200*15%` is `30`, `80+10%` is `88`, `80-25%` is `60`.
- **Functions:** powers `2^10`, roots `sqrt(144)` or `√16`, `round(3,14159; 2)`, `floor`, `ceil`, and `pi`.
- **Local notation:** decimal comma `0,5`, thousands separator `1'000`, and `×` `÷` `−`.
- **Proper signs:** type `3*2` or `3x2` and the field shows `3×2`; `-` becomes `−` and `**` becomes `^`. The result stays plain.
- **Safe:** a small parser evaluates the input; nothing reaches `eval()` or a shell.

![Four calculations: 80 − 25% = 60, sqrt(144) + 2^10 = 1036, 1'299,90 × 3 = 3899.7, round(2pi; 4) = 6.2832](examples.png)

| Type this | Get this |
|---|---|
| `(1+2)*3` | `9` |
| `17%5` | `2` (a `%` followed by a number is the remainder) |
| `2^3^2`, `-2^2` | `512`, `-4` |
| `2√9`, `2pi`, `2(3+4)` | `6`, `6.28318530717959`, `14` |
| `round(2.5)`, `round(1.005; 2)` | `3`, `1.01` |

Separate function arguments with `;` or with `, ` and a space, since `3,14` is a
decimal number. Results always use a decimal point so they paste anywhere.

| Key | Action |
|---|---|
| `Enter` | Copy the result and close |
| `Escape` | Clear the field, press again to close |

## Development

```bash
node test/calc-model.test.js
omarchy-plugin-check .
omarchy-plugin-validate .
```

After QML edits: `./deploy.sh` is not involved (this tree is outside `omaxian/`).
Re-rsync into `~/.config/omarchy/plugins/…`, then **log out / log in** — do not
run `omarchy-restart-shell` from an agent session.

Licensed under the [MIT License](LICENSE).
