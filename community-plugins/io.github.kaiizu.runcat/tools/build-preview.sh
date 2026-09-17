#!/usr/bin/env bash
# Build preview.png and docs/demo.gif from the plugin's own sprite frames, the
# bar theme colors, and the bar's font, so the previews match what the widget
# draws — just larger, and crisp instead of screengrabbed.
#
# The size/fontRatio screenshot in the README (docs/in-bar.png) is a real
# capture of the running bar, not generated here.
#
# Requires: rsvg-convert, ImageMagick (magick), fontconfig.
# Usage: tools/build-preview.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FONT="$(fc-match -f '%{file}' monospace)"
BG="#2d353b"       # bar background   (Everforest dark)
FG="#d3c6aa"       # bar foreground / sprite tint
MUTED="#9da9a0"    # muted label color

CATBOX=96                                    # sprite box in the big preview
BAR_H=$((CATBOX * 26 / 22))                  # bar cross-axis (26px at size 22)
SIDE=$((CATBOX * 5 / 22))                    # WidgetButton horizontalMargin
GAP=$((CATBOX * 3 / 22))                     # Style.space(3) cat <-> number
TEXT_PT=$((CATBOX * 45 / 100))               # fontRatio 0.45
SMALL=64                                     # pose row sprite box
PAD=14

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p docs

tint() { # <height> <svg> <out>
  rsvg-convert -h "$1" "$2" -o "$TMP/raw.png"
  magick "$TMP/raw.png" -fill "$FG" -colorize 100 "$3"
}

for i in 0 1 2 3 4; do
  tint "$CATBOX" "assets/active/$i.svg" "$TMP/run-$i.png"
  tint "$SMALL"  "assets/active/$i.svg" "$TMP/pose-$i.png"
done
tint "$CATBOX" "assets/idle/0.svg" "$TMP/idle.png"
tint "$SMALL"  "assets/idle/0.svg" "$TMP/pose-idle.png"

magick -background none -fill "$FG" -font "$FONT" -pointsize "$TEXT_PT" \
  label:'7%' "$TMP/text.png"
TEXT_W="$(magick identify -format '%w' "$TMP/text.png")"
TEXT_H="$(magick identify -format '%h' "$TMP/text.png")"

STRIP_W=$((SIDE + CATBOX + GAP + TEXT_W + SIDE))
CAT_Y=$(((BAR_H - CATBOX) / 2))
TEXT_Y=$(((BAR_H - TEXT_H) / 2))

# Background plus the percentage; the cat is composited per frame on top of
# this so a frame never inherits the previous cat.
magick -size "${STRIP_W}x${BAR_H}" "xc:$BG" \
  "$TMP/text.png" -geometry "+$((SIDE + CATBOX + GAP))+${TEXT_Y}" -composite \
  "$TMP/frame-bg.png"

# One static strip (frame 0) for the preview card.
magick "$TMP/frame-bg.png" \
  "$TMP/run-0.png" -geometry "+${SIDE}+${CAT_Y}" -composite "$TMP/strip-base.png"

# --- docs/demo.gif: one full cycle at 7% CPU, ~197ms a frame ---------------
for i in 0 1 2 3 4; do
  magick "$TMP/frame-bg.png" \
    "$TMP/run-$i.png" -geometry "+${SIDE}+${CAT_Y}" -composite "$TMP/frame-$i.png"
done
magick -delay 20 -loop 0 "$TMP"/frame-*.png -colors 64 -layers Optimize \
  -define gif:dispose=background docs/demo.gif

# --- preview.png: the widget, then every pose ------------------------------
POSES_W=$((PAD * 2 + 6 * SMALL + 5 * (SMALL / 4)))
POSES_H=$((SMALL + PAD))
W=$((STRIP_W + PAD * 2 > POSES_W ? STRIP_W + PAD * 2 : POSES_W))
H=$((BAR_H + 2 * PAD + POSES_H))

magick -size "${W}x${H}" "xc:$BG" "$TMP/card.png"

x=$(((W - STRIP_W) / 2))
magick "$TMP/card.png" "$TMP/strip-base.png" -geometry "+${x}+${PAD}" -composite \
  "$TMP/card-step.png"

x=$(((W - (6 * SMALL + 5 * (SMALL / 4))) / 2))
y=$((BAR_H + 2 * PAD))
magick "$TMP/card-step.png" \
  "$TMP/pose-0.png" -geometry "+${x}+${y}" -composite \
  "$TMP/pose-1.png" -geometry "+$((x + (SMALL + SMALL / 4)))+${y}" -composite \
  "$TMP/pose-2.png" -geometry "+$((x + 2 * (SMALL + SMALL / 4)))+${y}" -composite \
  "$TMP/pose-3.png" -geometry "+$((x + 3 * (SMALL + SMALL / 4)))+${y}" -composite \
  "$TMP/pose-4.png" -geometry "+$((x + 4 * (SMALL + SMALL / 4)))+${y}" -composite \
  "$TMP/pose-idle.png" -geometry "+$((x + 5 * (SMALL + SMALL / 4)))+${y}" -composite \
  preview.png

magick identify preview.png docs/demo.gif
