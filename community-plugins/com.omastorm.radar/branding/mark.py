#!/usr/bin/env python3
"""The omastorm mark as a miniature of the app view.

Thin range rings with a dashed outer ring, the site crosshair, and a squall
line running SW to NE drawn in the Glyphs density treatment (22 / 44 / 78 /
100 %) with the app's reflectivity palette.  31x31 grid, site at the center.

    python3 branding/mark.py     # writes branding/mark/ exports and branding/mark.png
"""
import math, os, subprocess

N = 31
C = 15
RING, DASH, CROSS, FRAME, L1, L2, L3, L4 = range(8)

# sampled from the running app (warm dark theme)
APP = dict(bg="#2d2626", fg="#e7d6d3", coral="#f18b6d",
           teal="#50b393", green="#82c269", yellow="#eac75f", orange="#e79e4b", red="#e07048", crimson="#d34b62")

PAL = {
    "app":        {"bg": APP["bg"], RING: (APP["fg"], .5), DASH: (APP["fg"], .5), CROSS: (APP["fg"], .95), FRAME: (APP["fg"], .35),
                   L1: (APP["teal"], 1), L2: (APP["green"], 1), L3: (APP["yellow"], 1), L4: (APP["red"], 1)},
    "app-light":  {"bg": "#f3ede9", RING: ("#2d2626", .5), DASH: ("#2d2626", .5), CROSS: ("#2d2626", .95), FRAME: ("#2d2626", .35),
                   L1: (APP["teal"], 1), L2: (APP["green"], 1), L3: (APP["orange"], 1), L4: (APP["crimson"], 1)},
    "mono-dark":  {"bg": "#1a1b26", RING: ("#f3efe4", .5), DASH: ("#f3efe4", .5), CROSS: ("#f3efe4", .95), FRAME: ("#f3efe4", .35),
                   L1: ("#f3efe4", .35), L2: ("#f3efe4", .55), L3: ("#f3efe4", .8), L4: ("#f3efe4", 1)},
    "mono-light": {"bg": "#f2f0e9", RING: ("#1c1c22", .5), DASH: ("#1c1c22", .5), CROSS: ("#1c1c22", .95), FRAME: ("#1c1c22", .35),
                   L1: ("#1c1c22", .35), L2: ("#1c1c22", .55), L3: ("#1c1c22", .8), L4: ("#1c1c22", 1)},
    "accent":     {"bg": APP["bg"], RING: (APP["fg"], .5), DASH: (APP["fg"], .5), CROSS: (APP["fg"], .95), FRAME: (APP["fg"], .35),
                   L1: (APP["coral"], .35), L2: (APP["coral"], .55), L3: (APP["coral"], .8), L4: (APP["coral"], 1)},
}

def ring(g, r, role=RING, dashed=False, width=1):
    for y in range(N):
        for x in range(N):
            if abs(math.hypot(x - C, y - C) - r) < width / 2:
                if dashed:
                    a = math.atan2(y - C, x - C)
                    if int((a + math.pi) / (2 * math.pi) * 24) % 2: continue
                g.setdefault((x, y), role)

def crosshair(g, arm=2):
    for i in range(-arm, arm + 1):
        g[(C + i, C)] = CROSS
        g[(C, C + i)] = CROSS

def frame(g):
    for i in range(N):
        for c in ((i, 0), (i, N - 1), (0, i), (N - 1, i)):
            g[c] = FRAME
    for c in ((0, 0), (N - 1, 0), (0, N - 1), (N - 1, N - 1)):
        del g[c]

def squall(g, cx, cy, a, b, angle_deg=-45, bow=0.0, taper=0.0):
    """SW->NE line in Glyphs density: 100 / 78 / 44 / 22 % from core to fringe.
    taper > 0 makes the SW end fatter and the NE end thinner."""
    t = math.radians(angle_deg)
    for y in range(N):
        for x in range(N):
            dx, dy = x - cx, y - cy
            u = dx * math.cos(t) + dy * math.sin(t)
            v = -dx * math.sin(t) + dy * math.cos(t) - bow * a * (u / a) ** 2
            bb = b * (1 - taper * (u / a))
            d = math.hypot(u / a, v / bb)
            if d < 0.32:
                g[(x, y)] = L4
            elif d < 0.55 and (x + 2 * y) % 4 != 0:
                g[(x, y)] = L3
            elif d < 0.8 and (x + y) % 2 == 0:
                g[(x, y)] = L2
            elif d < 1.05 and (x + y) % 2 == 0 and x % 2 == 0:
                g[(x, y)] = L1

def scope(radii=((6, 1), (11, 1)), dashed=False):
    g = {}
    for r, w in radii: ring(g, r, width=w)
    if dashed: ring(g, 14, DASH, dashed=True)
    return g

def framed(radii, **storm):
    g = scope(radii)
    squall(g, **storm)
    crosshair(g)
    frame(g)
    return g

def ref():        # variant 2 from the last sheet
    return framed(((6, 1), (11, 1)), cx=18, cy=12, a=13, b=3.2)

def v_a():        # tapered line: a big cell at the SW end thinning to the NE; heavy outer ring
    return framed(((6, 1), (11.5, 2)), cx=18, cy=12, a=12, b=3.6, taper=0.55)

def v_b():        # bow echo, convex to the SE; heavy inner ring
    return framed(((6, 2), (11, 1)), cx=18, cy=12, a=12, b=3.4, bow=0.28)

def v_c():        # compact cell, less slash; heavy outer ring
    return framed(((5.5, 1), (11.5, 2)), cx=18, cy=12, a=9, b=4.4, taper=0.3)

def v_d():        # tapered and bowed; three rings, outer heavy
    return framed(((4.5, 1), (8.5, 1), (12.5, 2)), cx=18, cy=12, a=12, b=3.4, bow=0.2, taper=0.5)

CONCEPTS = [
    ("2", "omastorm-mark", "The mark", ref),
]

# ------------------------------------------------------------- 16 px grid
# For 16, 32, 48, 64 px, where the 31 grid would scale unevenly.  Same
# construction on a 16 grid: frame, one ring, the line, a 2 px site.
def mark16():
    global N, C
    N0, C0 = N, C
    N, C = 16, 7.5
    try:
        g = {}
        ring(g, 5, width=1)
        t = math.radians(-45)
        for y in range(16):
            for x in range(16):
                dx, dy = x - 9.5, y - 5.5
                u = dx * math.cos(t) + dy * math.sin(t)
                v = -dx * math.sin(t) + dy * math.cos(t)
                d = math.hypot(u / 5.5, v / 1.6)
                if d < 0.5: g[(x, y)] = L4
                elif d < 0.85: g[(x, y)] = L3
                elif d < 1.2 and (x + y) % 2 == 0: g[(x, y)] = L2
        for c in ((7, 7), (8, 7), (7, 8), (8, 8)):
            g[c] = CROSS
        frame(g)
        return g
    finally:
        N, C = N0, C0

def rects(g, pal):
    out = []
    for (x, y), role in sorted(g.items()):
        color, a = PAL[pal][role]
        op = "" if a >= 1 else f' fill-opacity="{a:.2f}"'
        out.append(f'<rect x="{x}" y="{y}" width="1" height="1" fill="{color}"{op}/>')
    return "".join(out)

def icon_svg(g, pal, size=256, n=N, bg=True):
    b = f'<rect width="{n}" height="{n}" fill="{PAL[pal]["bg"]}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {n} {n}" width="{size}" height="{size}" shape-rendering="crispEdges">'
            f'{b}{rects(g, pal)}</svg>')

def place(g, pal, x, y, size, bg=True, n=N):
    s = size / n
    b = f'<rect width="{n}" height="{n}" fill="{PAL[pal]["bg"]}"/>' if bg else ""
    return f'<g transform="translate({x},{y}) scale({s:.4f})">{b}{rects(g, pal)}</g>'

FONT = "JetBrainsMono Nerd Font, monospace"

def sheet(out_dir):
    g, g16 = ref(), mark16()
    W, H = 1200, 420
    p = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" shape-rendering="crispEdges">',
         f'<rect width="{W}" height="{H}" fill="#221c1c"/>',
         f'<text x="40" y="52" font-family="{FONT}" font-size="24" fill="#e7d6d3" letter-spacing="3">OMASTORM MARK</text>',
         f'<text x="40" y="80" font-family="{FONT}" font-size="14" fill="#a08f8b">31 px grid for 128 px and up · 16 px grid for 64 / 48 / 32 / 16 · app colors, light, one color, accent</text>']
    y0 = 110
    p.append(place(g, "app", 40, y0, 248))
    p.append(place(g, "app-light", 304, y0, 120))
    p.append(place(g, "accent", 304, y0 + 128, 120))
    p.append(place(g, "mono-dark", 440, y0, 120))
    p.append(place(g, "mono-light", 440, y0 + 128, 120))
    p.append(f'<rect x="576" y="{y0}" width="220" height="120" fill="{APP["bg"]}"/>')
    p.append(f'<rect x="576" y="{y0+128}" width="220" height="120" fill="#f3ede9"/>')
    for pal, yy in (("app", y0 + 28), ("app-light", y0 + 156)):
        x = 592
        for sz in (64, 48, 32, 16):
            p.append(place(g16, pal, x, yy + (64 - sz), sz, bg=False, n=16))
            x += sz + 12
    p.append(f'<rect x="812" y="{y0}" width="348" height="248" fill="{APP["bg"]}"/>')
    p.append(place(g16, "app", 832, y0 + 28, 16, bg=False, n=16))
    p.append(f'<text x="860" y="{y0+41}" font-family="{FONT}" font-size="14" font-weight="bold" fill="#e7d6d3" letter-spacing="3">OMASTORM</text>')
    p.append(place(g16, "app", 832, y0 + 80, 32, bg=False, n=16))
    p.append(f'<text x="876" y="{y0+104}" font-family="{FONT}" font-size="22" font-weight="bold" fill="#e7d6d3" letter-spacing="4">OMASTORM</text>')
    p.append(place(g, "app", 832, y0 + 140, 62, bg=False))
    p.append(f'<text x="906" y="{y0+180}" font-family="{FONT}" font-size="32" font-weight="bold" fill="#e7d6d3" letter-spacing="5">OMASTORM</text>')
    p.append(place(g16, "mono-dark", 832, y0 + 222, 16, bg=False, n=16))
    p.append(f'<text x="860" y="{y0+235}" font-family="{FONT}" font-size="13" fill="#a08f8b" letter-spacing="2">one color, theme foreground</text>')
    p.append("</svg>")
    # exports
    for pal in PAL:
        open(os.path.join(out_dir, f"omastorm-mark-{pal}.svg"), "w").write(icon_svg(g, pal))
        open(os.path.join(out_dir, f"omastorm-mark-16-{pal}.svg"), "w").write(icon_svg(g16, pal, n=16))
    open(os.path.join(out_dir, "omastorm-mark-mono.svg"), "w").write(icon_svg(g, "mono-dark", bg=False))
    open(os.path.join(out_dir, "omastorm-mark-16-mono.svg"), "w").write(icon_svg(g16, "mono-dark", n=16, bg=False))
    for pal in ("app", "mono-dark", "mono-light"):
        for sz in (512, 256, 128):
            subprocess.run(["rsvg-convert", "-w", str(sz), "-h", str(sz), "-o", os.path.join(out_dir, f"omastorm-mark-{pal}-{sz}.png"),
                            os.path.join(out_dir, f"omastorm-mark-{pal}.svg")], check=True)
        for sz in (64, 48, 32, 16):
            subprocess.run(["rsvg-convert", "-w", str(sz), "-h", str(sz), "-o", os.path.join(out_dir, f"omastorm-mark-{pal}-{sz}.png"),
                            os.path.join(out_dir, f"omastorm-mark-16-{pal}.svg")], check=True)
    return "\n".join(p)

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "mark"); os.makedirs(out, exist_ok=True)
    for f in os.listdir(out): os.remove(os.path.join(out, f))
    sheet_path = os.path.join(out, "sheet.svg")
    open(sheet_path, "w").write(sheet(out))
    subprocess.run(["rsvg-convert", "-o", os.path.join(here, "mark.png"), sheet_path], check=True)
    print("wrote", os.path.join(here, "mark.png"))
