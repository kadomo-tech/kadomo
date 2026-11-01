#!/usr/bin/env python3
"""Draws the built-in themes' wallpapers from their palettes.

Each theme gets three soft-glow images in themes/<name>/backgrounds/, small
PNGs that macOS scales to the screen (smooth gradients scale well). Run it
again after changing a theme's colors:

    python3 tools/make-backgrounds.py [theme...]

Standard library only; the palette comes from lib/palette.awk.
"""
import math
import os
import struct
import subprocess
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 480, 300


def palette(theme):
    out = subprocess.run(["awk", "-f", os.path.join(ROOT, "lib", "palette.awk"),
                          os.path.join(ROOT, "themes", theme, "colors.toml")],
                         check=True, capture_output=True, text=True).stdout
    return dict(line.split("\t", 1) for line in out.splitlines() if "\t" in line)


def rgb(hex_color):
    h = hex_color.lstrip("#")[:6]
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def gradient_colors(p):
    spec = p.get("hyprland_active_border", "")
    colors = []
    for token in spec.split():
        t = token.lower()
        if t.startswith("rgba(") or t.startswith("rgb("):
            colors.append(rgb(t[t.index("(") + 1:t.index("(") + 7]))
    return colors or [rgb(p["accent"]), rgb(p["blue"])]


def png(path, pixels):
    raw = b"".join(b"\x00" + bytes(row) for row in pixels)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def draw(base, glows):
    """base color with radial glows: (cx, cy, radius, color, strength), in 0-1 units."""
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            r, g, b = base
            u, v = x / W, y / H
            for cx, cy, radius, color, strength in glows:
                d = math.hypot((u - cx) * W / H, v - cy) / radius
                t = strength * math.exp(-d * d * 2.2)
                r, g, b = r + (color[0] - r) * t, g + (color[1] - g) * t, b + (color[2] - b) * t
            # A little noise keeps the gradient from banding once it is scaled up.
            n = ((x * 7919 + y * 104729) % 17 - 8) * 0.25
            row += [max(0, min(255, int(c + n + 0.5))) for c in (r, g, b)]
        rows.append(row)
    return rows


def make(theme):
    p = palette(theme)
    bg, dark = rgb(p["background"]), rgb(p["darker_background"])
    grad = gradient_colors(p)
    first, last = grad[0], grad[-1]
    accent, blue, magenta = rgb(p["accent"]), rgb(p["blue"]), rgb(p["magenta"])
    light = p.get("mode") == "light"
    s = 0.35 if light else 0.55
    out = os.path.join(ROOT, "themes", theme, "backgrounds")
    os.makedirs(out, exist_ok=True)
    images = {
        "0-glow.png": draw(bg, [(0.15, 0.1, 0.8, first, s), (0.9, 0.95, 0.8, last, s)]),
        "1-horizon.png": draw(dark, [(0.5, 1.15, 0.9, accent, s + 0.1), (0.5, 1.4, 0.6, magenta, s * 0.6)]),
        "2-drift.png": draw(bg, [(0.8, 0.2, 0.6, blue, s * 0.8), (0.25, 0.75, 0.7, last, s * 0.7), (0.6, 0.6, 0.4, first, s * 0.5)]),
    }
    for name, pixels in images.items():
        png(os.path.join(out, name), pixels)
        print(f"themes/{theme}/backgrounds/{name}")


if __name__ == "__main__":
    # tmac2k ships its own neon wallpapers; only the generated ones are redrawn.
    themes = sys.argv[1:] or sorted(d for d in os.listdir(os.path.join(ROOT, "themes"))
                                    if d != "tmac2k" and os.path.isfile(os.path.join(ROOT, "themes", d, "colors.toml")))
    for theme in themes:
        make(theme)
