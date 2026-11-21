#!/usr/bin/env python3
"""Draws the Milk theme's wallpapers into themes/milk/backgrounds/.

- 0-horizon: a milk-white sky over the curve of a pale lunar surface, its
  rim lit by a thin copper line.
- 1-hud: a ring display, fine sand circles and ticks off to the right, one
  copper arc of it lit.
- 2-plain: a plain milk field, warming to sand at the bottom.

All three are smooth, so they are drawn at 1920x1080 and macOS scales them
up. Run it again after changing the colors below:

    python3 tools/make-milk-backdrops.py

Standard library only.
"""
import math
import os
import random
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "themes", "milk", "backgrounds")
W, H = 1920, 1080


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


MILK = rgb("#f3ede2")
CREAM = rgb("#faf7f0")
SAND = rgb("#e0d6c4")
TAN = rgb("#c9a97c")
COPPER = rgb("#9c5523")


def png(name, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(k, d):
        return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)

    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))
    print(f"themes/milk/backgrounds/{name}")


def clamp(v):
    return 0 if v < 0 else 255 if v > 255 else int(v + 0.5)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def line(d, width):
    """Coverage of a line of the given width at distance d, antialiased."""
    return max(0.0, min(1.0, width / 2 + 0.5 - abs(d)))


def grain(seed):
    rnd = random.Random(seed)
    return [rnd.uniform(-1.2, 1.2) for _ in range(W * 7 + 13)]


def horizon():
    # The surface is a huge circle whose top rises above the bottom of the screen.
    cx, cy, r = W * 0.42, H + 2600, 2600 + H * 0.30
    noise = grain(1)
    rows = []
    for y in range(H):
        sky = mix(CREAM, MILK, y / H)
        row = bytearray()
        for x in range(W):
            d = math.hypot(x - cx, y - cy) - r
            if d < 0:
                # Below the rim: sand darkening to tan with depth, lit from the left.
                depth = min(1.0, -d / (H * 0.30))
                c = mix(SAND, TAN, 0.15 + 0.55 * depth)
                c = mix(c, CREAM, 0.25 * (1 - x / W) * (1 - depth))
            else:
                # A soft glow just above the rim.
                c = mix(sky, CREAM, 0.6 * math.exp(-d / 40))
            a = line(d, 2.0) * 0.85
            c = mix(c, COPPER, a)
            n = noise[(x * 7 + y * 13) % len(noise)]
            row += bytes(clamp(v + n) for v in c)
        rows.append(row)
    png("0-horizon.png", W, H, rows)


def hud():
    cx, cy = W * 0.68, H * 0.5
    rings = [(120, 1.5, SAND), (210, 1.2, TAN), (300, 2.0, SAND), (390, 1.0, TAN), (520, 1.0, SAND)]
    arc_r, arc_from, arc_to = 300, math.radians(-150), math.radians(-60)
    noise = grain(2)
    rows = []
    for y in range(H):
        row = bytearray()
        for x in range(W):
            dx, dy = x - cx, y - cy
            dist = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            # Background: milk, a touch brighter toward the center of the rings.
            c = mix(MILK, CREAM, 0.7 * math.exp(-(dist / 700) ** 2))
            for rr, wd, col in rings:
                a = line(dist - rr, wd)
                if a:
                    c = mix(c, col, a)
            # Ticks around the 390 ring: every 5 degrees short, every 30 long.
            if 384 <= dist <= 420:
                deg = (math.degrees(ang) + 360) % 360
                step = deg % 5
                near = min(step, 5 - step) * math.pi / 180 * dist
                long_tick = min(deg % 30, 30 - deg % 30) < 2.5
                if dist <= (420 if long_tick else 400):
                    c = mix(c, TAN, line(near, 1.2))
            # Crosshair through the center, fading out.
            for d in (dx, dy):
                a = line(d, 1.0) * max(0.0, 1 - dist / 560) * 0.6
                if a:
                    c = mix(c, TAN, a)
            # The lit copper arc.
            if arc_from <= ang <= arc_to:
                c = mix(c, COPPER, line(dist - arc_r, 4.0))
            # A small copper dot at the center.
            c = mix(c, COPPER, line(dist, 10.0))
            n = noise[(x * 7 + y * 13) % len(noise)]
            row += bytes(clamp(v + n) for v in c)
        rows.append(row)
    png("1-hud.png", W, H, rows)


def plain():
    noise = grain(3)
    rows = []
    for y in range(H):
        t = (y / H) ** 2
        c = mix(MILK, SAND, 0.6 * t)
        row = bytearray()
        for x in range(W):
            n = noise[(x * 7 + y * 13) % len(noise)]
            row += bytes(clamp(v + n) for v in c)
        rows.append(row)
    png("2-plain.png", W, H, rows)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    horizon()
    hud()
    plain()
