#!/usr/bin/env python3
"""Emit JSON rows for the help widget from the *live* i3 keybindings.

Primary source: `i3-msg -t get_config` (what i3 actually loaded after includes).
Fallback: ~/.config/i3/config.d/02_keybindings.conf (+ modes), then the
repo checkout copy — so the sheet never silently shows a stale on-disk map
that i3 is not running.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

I3_DIR = Path(os.environ.get("I3_CONFIG_DIR", Path.home() / ".config/i3"))
# …/omaxian/.local/share/omarchy/shell/scripts → …/omaxian/.config/i3
REPO_I3 = Path(__file__).resolve().parents[5] / ".config/i3"

SECTION_ALIASES = {
	"GUI Apps": "Applications",
	"Applications": "Applications",
	"CLI apps / activity": "CLI & activity",
	"CLI Apps": "CLI & activity",
	"Menus / launchers": "Menus & launchers",
	"Fabric / Rofi Applets": "Menus & launchers",
	"System control panels (Quickshell)": "System panels",
	"Session": "Session",
	"Function keys": "Hardware keys",
	"Window management": "Window management",
	"i3 control": "i3 control",
	"Workspaces": "Workspaces",
	"Changing (named) workspaces/moving to workspaces": "Workspaces",
}

# Commands that are known no-ops / retired in this port — never list them even
# if a stale config still contains the bindsym.
DEAD_CMD_PATTERNS: list[re.Pattern[str]] = [
	re.compile(r"i3_fabric_"),
	re.compile(r"network_menu\b"),
	re.compile(r"rofi_bluetooth\b"),
	re.compile(r"rofi_powermenu\b"),
	re.compile(r"\brofi\b"),
	re.compile(r"i3_help\b"),
	re.compile(r"togglePanelAt\b"),  # no panel host for right 1..4 on this port
	re.compile(r"\$terminal --(float|full)\b"),  # old i3_term flags, gone
]


def live_config_text() -> str | None:
	"""Return i3's currently loaded config, or None if i3 isn't reachable."""
	try:
		proc = subprocess.run(
			["bash", "-c", "unset I3SOCK; exec i3-msg -t get_config"],
			capture_output=True,
			text=True,
			timeout=3,
			check=False,
		)
	except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
		return None
	if proc.returncode != 0 or not proc.stdout.strip():
		return None
	# get_config wraps the body in a JSON string.
	try:
		text = json.loads(proc.stdout)
	except json.JSONDecodeError:
		text = proc.stdout
	if not isinstance(text, str) or "bindsym" not in text:
		return None
	return text


def file_config_text() -> str:
	"""Concatenate the on-disk keybinding sources (fallback)."""
	chunks: list[str] = []
	for base in (I3_DIR, REPO_I3):
		paths = [
			base / "config.d" / "02_keybindings.conf",
			base / "config.d" / "04_modes.conf",
		]
		found = [p for p in paths if p.is_file()]
		if not found:
			continue
		for p in found:
			chunks.append(p.read_text(encoding="utf-8", errors="replace"))
		break
	if not chunks:
		raise SystemExit(
			f"keybindings not found under {I3_DIR} and i3-msg get_config failed"
		)
	return "\n".join(chunks)


def canonicalize_cmd(cmd: str) -> str:
	"""Map expanded `i3-msg get_config` commands back toward config variables.

	Live config substitutes `$qs`, `$terminal`, `$send-notify`, `$mode_gaps`,
	etc. Keep describe()/dead filters working on either form.
	"""
	home = str(Path.home())
	s = cmd
	# send-notify expands to a full dunstify exec
	s = re.sub(
		r",\s*exec\s+(?:--no-startup-id\s+)?"
		r"dunstify\s+-u\s+low\s+-h\s+string:x-dunst-stack-tag:i3config\s+'([^']*)'",
		r", $send-notify '\1'",
		s,
	)
	replacements = [
		(f"{home}/.config/i3/scripts/i3_quickshell_toggle", "$qs"),
		("~/.config/i3/scripts/i3_quickshell_toggle", "$qs"),
		(f"{home}/.config/i3/scripts/i3_term", "$terminal"),
		("~/.config/i3/scripts/i3_term", "$terminal"),
		(f"{home}/.config/i3/scripts/i3_music", "$music_player"),
		("~/.config/i3/scripts/i3_music", "$music_player"),
		(f"{home}/.config/i3/scripts/i3_colorpicker", "$color_picker"),
		("~/.config/i3/scripts/i3_colorpicker", "$color_picker"),
		(f"{home}/.config/i3/scripts/i3_brightness", "$brightness"),
		("~/.config/i3/scripts/i3_brightness", "$brightness"),
		(f"{home}/.config/i3/scripts/i3_volume", "$volume"),
		("~/.config/i3/scripts/i3_volume", "$volume"),
		(f"{home}/.config/i3/scripts", "$scripts"),
		("~/.config/i3/scripts", "$scripts"),
	]
	for path, var in replacements:
		s = s.replace(path, var)
	# mode "$mode_gaps" expands to the set string
	s = re.sub(r'mode "Gaps: \(o\)uter, \(i\)nner"', 'mode "$mode_gaps"', s)
	return s


def load_mod_vars(text: str) -> dict[str, str]:
	mods = {
		"$MOD": "Super",
		"$ALT": "Alt",
		"Mod4": "Super",
		"Mod1": "Alt",
		"Control": "Ctrl",
		"Ctrl": "Ctrl",
		"Shift": "Shift",
	}
	for line in text.splitlines():
		m = re.match(r"set\s+(\$MOD|\$ALT)\s+(\S+)", line.strip())
		if not m:
			continue
		var, val = m.group(1), m.group(2)
		pretty = {"Mod4": "Super", "Mod1": "Alt"}.get(val, val)
		mods[var] = pretty
		mods[val] = pretty
	return mods


def pretty_key(raw: str, mods: dict[str, str]) -> str:
	raw = re.sub(r"^--release\s+", "", raw.strip())
	raw = re.sub(r"^--whole-window\s+", "", raw)
	parts = raw.split("+")
	out: list[str] = []
	for p in parts:
		p = p.strip()
		if p in mods:
			out.append(mods[p])
		elif p.startswith("XF86"):
			out.append(p.replace("XF86", ""))
		elif len(p) == 1:
			out.append(p.upper())
		else:
			out.append(
				{
					"space": "Space",
					"Escape": "Esc",
					"Return": "Return",
					"Tab": "Tab",
					"Delete": "Delete",
					"minus": "-",
					"equal": "=",
					"plus": "+",
				}.get(p, p)
			)
	return " + ".join(out)


def is_dead_command(cmd: str) -> bool:
	core = canonicalize_cmd(cmd.strip())
	core = re.sub(r"^exec\s+(--no-startup-id\s+)?", "", core).strip()
	if len(core) >= 2 and core[0] == '"' and core[-1] == '"':
		core = core[1:-1]
	return any(p.search(core) for p in DEAD_CMD_PATTERNS)


def describe(cmd: str) -> str:
	cmd = canonicalize_cmd(cmd.strip())
	notify = re.search(r"\$send-notify\s+'([^']+)'", cmd)
	notify_msg = notify.group(1) if notify else None

	core = re.sub(r"\s*,\s*\$send-notify\s+'[^']*'\s*$", "", cmd).strip()
	core = re.sub(r"^exec\s+(--no-startup-id\s+)?", "", core).strip()
	# Only unwrap a surrounding quoted command — don't eat inner quotes
	# (e.g. mode "Resize").
	if len(core) >= 2 and core[0] == '"' and core[-1] == '"':
		core = core[1:-1]

	rules: list[tuple[re.Pattern[str], str]] = [
		(re.compile(r"^\$terminal$"), "Open terminal"),
		(re.compile(r"^\$terminal -e tmux$"), "Open terminal (tmux)"),
		(re.compile(r"^\$terminal -e btop$"), "Open btop"),
		(re.compile(r"^\$web_browser$|^brave$"), "Open web browser"),
		(re.compile(r"^\$file_manager$|^thunar$"), "Open file manager"),
		(re.compile(r"^\$text_editor$|sublime_text"), "Open text editor"),
		(re.compile(r"^\$music_player$"), "Open music player"),
		(re.compile(r"(?:\$qs|omarchy-shell -q)\s+launcher\b"), "Omarchy menu"),
		(re.compile(r"(?:\$qs|omarchy-shell -q)\s+runner\b"), "Run command"),
		(re.compile(r"(?:\$qs|omarchy-shell -q)\s+powermenu\b"), "Power menu"),
		(re.compile(r"(?:\$qs|omarchy-shell -q)\s+help\b"), "Keybindings help"),
		(re.compile(r"(?:\$qs|omarchy-shell -q)\s+calendar\b"), "Calendar"),
		(re.compile(r"(?:\$qs|omarchy-shell -q)\s+theme\b"), "Theme picker"),
		(re.compile(r"toggle local\.controlpanel\b"), "Control panel"),
		(re.compile(r"toggle omarchy\.audio\b"), "Audio panel"),
		(re.compile(r"toggle omarchy\.bluetooth\b"), "Bluetooth panel"),
		(re.compile(r"toggle omarchy\.network\b"), "Network panel"),
		(re.compile(r"toggle omarchy\.power\b"), "Power / battery panel"),
		(re.compile(r"toggle local\.monitor\b"), "Monitor panel"),
		(re.compile(r"i3_screenshot\b"), "Screenshot"),
		(re.compile(r"i3_lock\b"), "Lock screen"),
		(re.compile(r"^\$color_picker$"), "Colour picker"),
		(re.compile(r"workspace=__focused__.*kill"), "Close every window on workspace"),
		(re.compile(r"^\$brightness --inc$"), "Increase brightness"),
		(re.compile(r"^\$brightness --dec$"), "Decrease brightness"),
		(re.compile(r"brightnessctl set 100%"), "Brightness to max"),
		(re.compile(r"brightnessctl set 1% "), "Brightness to min"),
		(re.compile(r"brightnessctl set \+1%"), "Brightness up (fine)"),
		(re.compile(r"brightnessctl set 1%-"), "Brightness down (fine)"),
		(re.compile(r"^\$volume --inc$"), "Increase volume"),
		(re.compile(r"^\$volume --dec$"), "Decrease volume"),
		(re.compile(r"^\$volume --toggle$"), "Toggle mute"),
		(re.compile(r"^\$volume --toggle-mic$"), "Toggle mic mute"),
		(re.compile(r"set-sink-volume.*\+1%"), "Volume up (fine)"),
		(re.compile(r"set-sink-volume.*-1%"), "Volume down (fine)"),
		(re.compile(r"playerctl next|mpc next"), "Next track"),
		(re.compile(r"playerctl previous|mpc prev"), "Previous track"),
		(re.compile(r"playerctl play-pause|mpc toggle"), "Play / pause"),
		(re.compile(r"playerctl stop|mpc stop"), "Stop playback"),
		(re.compile(r"^kill$"), "Close window"),
		(re.compile(r"^split toggle$"), "Toggle split orientation"),
		(re.compile(r"^split horizontal$"), "Split horizontal"),
		(re.compile(r"^split vertical$"), "Split vertical"),
		(re.compile(r"^layout toggle tabbed split$"), "Toggle tabbed / split"),
		(re.compile(r"^layout toggle"), "Cycle layouts"),
		(re.compile(r"^fullscreen toggle$"), "Toggle fullscreen"),
		(re.compile(r"^floating toggle$"), "Toggle floating"),
		(re.compile(r"^border toggle$"), "Toggle borders"),
		(re.compile(r"^focus left$"), "Focus left"),
		(re.compile(r"^focus down$"), "Focus down"),
		(re.compile(r"^focus up$"), "Focus up"),
		(re.compile(r"^focus right$"), "Focus right"),
		(re.compile(r"^focus parent$"), "Focus parent container"),
		(re.compile(r"^focus child$"), "Focus child container"),
		(re.compile(r"^focus next$"), "Focus next window"),
		(re.compile(r"^focus prev$"), "Focus previous window"),
		(re.compile(r"^focus mode_toggle$"), "Toggle float / tile focus"),
		(re.compile(r"^focus output next$"), "Focus next monitor"),
		(re.compile(r"^focus output prev$"), "Focus previous monitor"),
		(re.compile(r"^move left$"), "Move window left"),
		(re.compile(r"^move down$"), "Move window down"),
		(re.compile(r"^move up$"), "Move window up"),
		(re.compile(r"^move right$"), "Move window right"),
		(re.compile(r"^move absolute position center$"), "Center floating window"),
		(re.compile(r"^move position mouse$"), "Move floating window to cursor"),
		(re.compile(r"^resize shrink width 2 "), "Shrink width (fine)"),
		(re.compile(r"^resize grow width 2 "), "Grow width (fine)"),
		(re.compile(r"^resize shrink width 20 "), "Shrink width (coarse)"),
		(re.compile(r"^resize grow width 20 "), "Grow width (coarse)"),
		(re.compile(r"^resize shrink height"), "Shrink height"),
		(re.compile(r"^resize grow height"), "Grow height"),
		(re.compile(r"^resize shrink width"), "Shrink width"),
		(re.compile(r"^resize grow width"), "Grow width"),
		(re.compile(r"^sticky toggle$"), "Toggle sticky"),
		(re.compile(r"^scratchpad show$"), "Show scratchpad"),
		(re.compile(r"^move scratchpad$"), "Move to scratchpad"),
		(re.compile(r'^mode "Resize"$'), "Enter resize mode"),
		(re.compile(r'^mode "\$mode_gaps"$'), "Enter gaps mode"),
		(re.compile(r"^mode "), "Enter i3 mode"),
		(re.compile(r"^restart"), "Restart i3"),
		(re.compile(r"^reload"), "Reload i3 config"),
		(re.compile(r"^exit$"), "Quit i3"),
		(re.compile(r"move container to workspace (next|prev)"), "Carry window to adjacent workspace"),
		(re.compile(r"workspace next$"), "Next workspace"),
		(re.compile(r"workspace prev$"), "Previous workspace"),
		(re.compile(r"^workspace back_and_forth$"), "Last-used workspace"),
	]
	for pat, desc in rules:
		if pat.search(core):
			return desc
	if notify_msg:
		return notify_msg
	return re.sub(r"^\S*/", "", core)[:80] or core[:80]


def section_from_comment(line: str) -> str | None:
	m = re.match(r"^##\s*--\s*(.+?)(?:\s*--+)?\s*$", line)
	if not m:
		return None
	title = m.group(1).strip(" -")
	if not title or title.lower().startswith("key bind"):
		return None
	if title.lower().startswith("variables"):
		return None
	if "kitty" in title.lower() or title.lower().startswith("terminal"):
		return "Applications"
	return SECTION_ALIASES.get(title, title)


def parse(text: str) -> list[dict]:
	mods = load_mod_vars(text)
	section = "General"
	rows: list[dict] = []
	pending_section: str | None = None
	ws_switch = False
	ws_move = False
	ws_move_nofollow = False
	in_mode_block = 0

	def flush_workspace_groups():
		nonlocal ws_switch, ws_move, ws_move_nofollow
		if ws_switch:
			rows.append(
				{
					"type": "bind",
					"keys": f"{mods['$MOD']} + 1..0",
					"action": "Switch to workspace 1..10",
					"text": "",
				}
			)
			ws_switch = False
		if ws_move:
			rows.append(
				{
					"type": "bind",
					"keys": f"{mods['$MOD']} + Shift + 1..0",
					"action": "Move window to workspace 1..10 (follow)",
					"text": "",
				}
			)
			ws_move = False
		if ws_move_nofollow:
			rows.append(
				{
					"type": "bind",
					"keys": f"{mods['$MOD']} + Shift + Alt + 1..4",
					"action": "Move window to workspace 1..4 (stay)",
					"text": "",
				}
			)
			ws_move_nofollow = False

	def ensure_section(name: str):
		nonlocal section
		flush_workspace_groups()
		if section == name:
			return
		section = name
		rows.append({"type": "header", "text": name, "keys": "", "action": ""})

	for raw in text.splitlines():
		stripped = raw.strip()
		if not stripped:
			continue

		# Skip binds that only apply inside a named mode block.
		if re.match(r"^mode\s+", stripped) and "{" in stripped:
			in_mode_block += 1
			continue
		if in_mode_block:
			if stripped == "}":
				in_mode_block -= 1
			continue

		if stripped.startswith("##"):
			sec = section_from_comment(stripped)
			if sec:
				pending_section = sec
			continue
		if stripped.startswith("#") or stripped.startswith("set "):
			continue

		m = re.match(
			r"^bindsym\s+(?:--release\s+)?(?:--whole-window\s+)?(.+?)\s+(.*)$",
			stripped,
		)
		if not m:
			continue

		keys_raw, cmd = m.group(1), m.group(2)
		if is_dead_command(cmd):
			continue

		if pending_section:
			ensure_section(pending_section)
			pending_section = None

		# Collapse workspace number spam into one row each.
		# Live get_config expands $wsN to "N" (or N).
		ws_tok = r'(?:\$ws\d+|"\d+"|\d+)'
		if re.search(rf"workspace number {ws_tok}\s*$", cmd) and "move container" not in cmd:
			if section != "Workspaces":
				ensure_section("Workspaces")
			ws_switch = True
			continue
		if re.search(
			rf"move container to workspace number {ws_tok};\s*workspace number",
			cmd,
		):
			if section != "Workspaces":
				ensure_section("Workspaces")
			ws_move = True
			continue
		if re.search(rf"^move container to workspace number {ws_tok}\s*$", cmd.strip()):
			if section != "Workspaces":
				ensure_section("Workspaces")
			ws_move_nofollow = True
			continue

		flush_workspace_groups()
		cmd_norm = canonicalize_cmd(cmd)
		if re.match(r"^(restart|reload|exit)\b", cmd_norm.strip().strip('"')):
			ensure_section("i3 control")
		elif re.search(r'\bmode "(Resize|\$mode_gaps)"', cmd_norm):
			ensure_section("Modes")

		rows.append(
			{
				"type": "bind",
				"keys": pretty_key(keys_raw, mods),
				"action": describe(cmd),
				"text": "",
			}
		)

	flush_workspace_groups()

	cleaned: list[dict] = []
	for i, row in enumerate(rows):
		if row["type"] == "header":
			ok = False
			for j in range(i + 1, len(rows)):
				if rows[j]["type"] == "header":
					break
				if rows[j]["type"] == "bind":
					ok = True
					break
			if ok:
				cleaned.append(row)
		else:
			cleaned.append(row)
	return cleaned


def main() -> None:
	text = live_config_text()
	source = "i3-msg get_config"
	if text is None:
		text = file_config_text()
		source = "on-disk fallback"
	rows = parse(text)
	# Optional debug for operators: HELP_BINDINGS_DEBUG=1
	if os.environ.get("HELP_BINDINGS_DEBUG"):
		sys.stderr.write(f"help-bindings: source={source} rows={len(rows)}\n")
	json.dump(rows, sys.stdout, ensure_ascii=False)
	sys.stdout.write("\n")


if __name__ == "__main__":
	main()
