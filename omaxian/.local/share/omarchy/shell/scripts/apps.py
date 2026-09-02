#!/usr/bin/env python3
"""List / filter / launch .desktop applications for the eww launcher."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

CACHE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "eww-apps-cache-v2.json"
CACHE_TTL_SEC = 60
LIMIT_DEFAULT = 80
ICON_PX = 48
FALLBACK_ICON = "application-x-executable"

APP_DIRS = [
	Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "applications",
	Path("/usr/share/applications"),
	Path("/usr/local/share/applications"),
	Path("/var/lib/flatpak/exports/share/applications"),
	Path.home() / ".local/share/flatpak/exports/share/applications",
]

_icon_theme = None


def _get_icon_theme():
	global _icon_theme
	if _icon_theme is not None:
		return _icon_theme
	try:
		import gi

		gi.require_version("Gtk", "3.0")
		from gi.repository import Gtk

		_icon_theme = Gtk.IconTheme.get_default()
	except Exception:
		_icon_theme = False
	return _icon_theme


def resolve_icon(icon: str) -> str:
	"""Return an absolute image path for the launcher, or empty string.

	SVG paths are returned as-is: this box was initially missing the Qt6
	`libqsvg.so` imageformats plugin (`qt6-svg-dev`/`libqt6svg6` alone don't
	include it), which made QtQuick.Image unable to decode .svg at all — a
	real problem since most installed icon themes here (Papirus) are
	SVG-only. Installing `qt6-svg-plugins` fixed it at the source (verified
	live: a plain `Image { source: "...svg" }` reports `Image.Ready`, not
	`Image.Error`), so the earlier workaround here (rasterizing every SVG to
	a cached PNG via `resvg`/`convert`) is no longer needed.
	"""
	if not icon:
		icon = FALLBACK_ICON

	# Absolute / relative file path from Icon=
	p = Path(icon)
	if p.is_file():
		return str(p.resolve())
	if icon.startswith("/") and Path(icon + ".png").is_file():
		return icon + ".png"
	if icon.startswith("/") and Path(icon + ".svg").is_file():
		return icon + ".svg"

	name = Path(icon).stem if "/" in icon or icon.endswith((".png", ".svg", ".xpm")) else icon

	theme = _get_icon_theme()
	if theme:
		info = theme.lookup_icon(name, ICON_PX, 0)
		if info and info.get_filename():
			return info.get_filename()
		if name != FALLBACK_ICON:
			info = theme.lookup_icon(FALLBACK_ICON, ICON_PX, 0)
			if info and info.get_filename():
				return info.get_filename()

	# Manual search in common theme dirs (no gi).
	home = Path.home()
	candidates = [
		home / ".icons",
		home / ".local/share/icons",
		Path("/usr/share/icons"),
		Path("/usr/share/pixmaps"),
	]
	for base in candidates:
		if not base.is_dir():
			continue
		for pattern in (
			f"**/{ICON_PX}x{ICON_PX}/**/{name}.png",
			f"**/{ICON_PX}x{ICON_PX}/**/{name}.svg",
			f"**/scalable/**/{name}.svg",
			f"**/{name}.png",
			f"**/{name}.svg",
			f"{name}.png",
			f"{name}.svg",
			f"{name}.xpm",
		):
			hits = list(base.glob(pattern))
			if hits:
				return str(hits[0])
	return ""


def _parse_desktop(path: Path) -> dict | None:
	try:
		text = path.read_text(encoding="utf-8", errors="replace")
	except OSError:
		return None

	# Only the main Desktop Entry group
	if "[Desktop Entry]" not in text:
		return None
	section = text.split("[Desktop Entry]", 1)[1].split("\n[", 1)[0]

	vals: dict[str, str] = {}
	for line in section.splitlines():
		line = line.strip()
		if not line or line.startswith("#") or "=" not in line:
			continue
		key, value = line.split("=", 1)
		# Prefer unlocalized keys; keep first Name= etc.
		if "[" in key:  # Name[it]=…
			continue
		if key not in vals:
			vals[key] = value

	if vals.get("Type", "Application") != "Application":
		return None
	if vals.get("NoDisplay", "").lower() == "true":
		return None
	if vals.get("Hidden", "").lower() == "true":
		return None
	if "Exec" not in vals:
		return None

	# Skip entries that only show on other DEs when OnlyShowIn is set and
	# does not include a generic session we care about. Keep permissive.
	only = vals.get("OnlyShowIn", "")
	if only and "i3" not in only and "X-Generic" not in only:
		# Still allow common DEs so apps are not hidden on bare i3
		pass

	desktop_id = path.name  # includes .desktop
	name = vals.get("Name") or path.stem
	comment = vals.get("Comment") or vals.get("GenericName") or ""
	icon_name = vals.get("Icon") or FALLBACK_ICON
	icon_path = resolve_icon(icon_name)

	return {
		"id": desktop_id,
		"name": name,
		"comment": comment,
		"icon": icon_name,
		"icon_path": icon_path,
		"exec": vals["Exec"],
	}


def scan_apps() -> list[dict]:
	seen: set[str] = set()
	apps: list[dict] = []
	for directory in APP_DIRS:
		if not directory.is_dir():
			continue
		for path in sorted(directory.glob("*.desktop")):
			# Later dirs win only if id not seen — prefer user local first
			app = _parse_desktop(path)
			if not app:
				continue
			if app["id"] in seen:
				continue
			seen.add(app["id"])
			apps.append(app)
	apps.sort(key=lambda a: a["name"].casefold())
	return apps


def load_apps(force: bool = False) -> list[dict]:
	import time

	if not force and CACHE.is_file():
		age = time.time() - CACHE.stat().st_mtime
		if age < CACHE_TTL_SEC:
			try:
				return json.loads(CACHE.read_text(encoding="utf-8"))
			except (OSError, json.JSONDecodeError):
				pass
	apps = scan_apps()
	try:
		CACHE.write_text(json.dumps(apps, ensure_ascii=False), encoding="utf-8")
	except OSError:
		pass
	return apps


def score(app: dict, query: str) -> int:
	if not query:
		return 1
	q = query.casefold()
	name = app["name"].casefold()
	if name == q:
		return 100
	if name.startswith(q):
		return 80
	if q in name:
		return 50
	tokens = re.split(r"\s+", q)
	if tokens and all(t in name for t in tokens if t):
		return 40
	return 0


def search(query: str, limit: int = LIMIT_DEFAULT) -> list[dict]:
	apps = load_apps()
	query = (query or "").strip()
	if not query:
		return apps[:limit]
	ranked: list[tuple[int, dict]] = []
	for app in apps:
		s = score(app, query)
		if s > 0:
			ranked.append((s, app))
	ranked.sort(key=lambda x: (-x[0], x[1]["name"].casefold()))
	return [a for _, a in ranked[:limit]]


def launch(desktop_id: str) -> None:
	desktop_id = desktop_id.strip()
	if not desktop_id:
		return
	if not desktop_id.endswith(".desktop"):
		desktop_id = f"{desktop_id}.desktop"
	app_id = desktop_id.removesuffix(".desktop")

	# Prefer gtk-launch
	try:
		subprocess.Popen(
			["gtk-launch", app_id],
			stdout=subprocess.DEVNULL,
			stderr=subprocess.DEVNULL,
			start_new_session=True,
		)
		return
	except OSError:
		pass

	apps = load_apps()
	app = next((a for a in apps if a["id"] == desktop_id), None)
	if not app:
		return
	cmd = re.sub(r"\s*%[fFuUdDnNickvm]", "", app["exec"]).strip()
	if not cmd:
		return
	subprocess.Popen(
		cmd,
		shell=True,
		stdout=subprocess.DEVNULL,
		stderr=subprocess.DEVNULL,
		start_new_session=True,
	)


def main() -> None:
	if len(sys.argv) < 2:
		print("usage: apps.py list|search [query]|launch <id>|refresh", file=sys.stderr)
		sys.exit(1)
	cmd = sys.argv[1]
	if cmd == "list":
		print(json.dumps(load_apps(), ensure_ascii=False))
	elif cmd == "refresh":
		print(json.dumps(load_apps(force=True), ensure_ascii=False))
	elif cmd == "search":
		query = sys.argv[2] if len(sys.argv) > 2 else ""
		limit = int(sys.argv[3]) if len(sys.argv) > 3 else LIMIT_DEFAULT
		# Slim payload for eww `for`
		out = [
			{
				"id": a["id"],
				"name": a["name"],
				"comment": a["comment"],
				"icon": a.get("icon") or FALLBACK_ICON,
				"icon_path": a.get("icon_path") or "",
			}
			for a in search(query, limit=limit)
		]
		print(json.dumps(out, ensure_ascii=False))
	elif cmd == "launch":
		if len(sys.argv) < 3:
			sys.exit(1)
		launch(sys.argv[2])
	elif cmd == "launch-first":
		query = sys.argv[2] if len(sys.argv) > 2 else ""
		hits = search(query, limit=1)
		if hits:
			launch(hits[0]["id"])
	else:
		print(f"unknown command: {cmd}", file=sys.stderr)
		sys.exit(1)


if __name__ == "__main__":
	main()
