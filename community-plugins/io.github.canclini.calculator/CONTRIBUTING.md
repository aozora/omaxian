# Contributing

This directory is an **Omaxian port** of
[canclini/omarchy-calculator](https://github.com/canclini/omarchy-calculator).
Evaluator / feature fixes that apply upstream belong in that repository first;
bring them here with a sync note in the port README.

## Project boundary

The plugin is one overlay: an expression goes in, a number goes to the clipboard.
It does not bind keys, edit user configuration, or install anything outside its
plugin folder.

A few things are fixed for this port:

- Overlay chrome uses `Ui/CenteredModal` (not layer-shell). Do not reintroduce
  `Quickshell.Wayland` / `WlrLayershell`.
- The only external clipboard command is `xclip` (fallback `xsel`), with the
  result passed as a separate bash argument — never interpolated into a shell
  string built from user input.
- No network access, no `eval()`.
- The plugin id `io.github.canclini.calculator` stays as upstream’s marketplace id.

## Checks

```bash
node test/calc-model.test.js
omarchy-plugin-check .
omarchy-plugin-validate .
```

`CalcModel.js` is a QML `.pragma library` module: keep it to ES5 (no arrow
functions, `let`, `BigInt`, lookbehind). The test strips the pragma line and
runs under node.
