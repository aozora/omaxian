#!/usr/bin/env python3
"""Build a compact icon-name → best-path map for AppLibrary.

Emits one JSON object on stdout. Scoring matches AppLibrary.iconPathScore:
SVG / scalable beat sized PNGs; among PNGs prefer the largest NxN dir.
Running the merge here keeps ~10^5 find paths off Quickshell's UI thread.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def score(path: str) -> int:
  lower = path.lower()
  if lower.endswith(".svg"):
    return 10000
  if "/scalable/" in path:
    return 9999
  for part in path.split("/"):
    if "x" in part and part[0].isdigit():
      left, _, right = part.partition("x")
      if left.isdigit() and right.isdigit():
        return int(left)
  return 1


def consider(index: dict[str, tuple[int, str]], path: str) -> None:
  name = Path(path).stem
  if not name:
    return
  s = score(path)
  prev = index.get(name)
  if prev is None or s > prev[0]:
    index[name] = (s, path)


def iter_icon_files(roots: list[Path]):
  for root in roots:
    if not root.is_dir():
      continue
    for dirpath, _dirnames, filenames in os.walk(root):
      for name in filenames:
        if not (name.endswith(".svg") or name.endswith(".png")):
          continue
        full = os.path.join(dirpath, name)
        parts = Path(os.path.relpath(full, root)).parts
        if "apps" in parts or "devices" in parts:
          yield full


def main() -> int:
  roots: list[Path] = [
    Path.home() / ".icons",
    Path.home() / ".local/share/icons",
  ]
  for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
    if d:
      roots.append(Path(d) / "icons")

  index: dict[str, tuple[int, str]] = {}
  for path in iter_icon_files(roots):
    consider(index, path)

  pixmaps = Path("/usr/share/pixmaps")
  if pixmaps.is_dir():
    for entry in pixmaps.iterdir():
      if entry.is_file() and entry.suffix.lower() in (".svg", ".png"):
        consider(index, str(entry))

  out = {name: path for name, (_s, path) in index.items()}
  json.dump(out, sys.stdout, separators=(",", ":"))
  sys.stdout.write("\n")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
