#!/usr/bin/env python3
"""Draws the Solaris theme's CDE-style backdrops.

CDE desktops showed a palette color with a small pattern tiled over it, not a
photo. This draws two, raised bricks lit from the top left like CDE's 3D
controls and a flat CDE mauve, into themes/solaris/backgrounds/ and, after its
own two, themes/synthwave/backgrounds/. They are full 4K,
since a crisp pattern blurs when macOS scales a small image up. Run it again
after changing the colors below:

    python3 tools/make-cde-backdrops.py

Standard library only.
"""
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 3840, 2160
# Where they go: theme, and the number each file name starts with there.
OUT = [("solaris", 3), ("synthwave", 2)]


def rgb(h):
    h = h.lstrip("#")
    return bytes(int(h[i:i + 2], 16) for i in (0, 2, 4))


def png(path, rows):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(k, d):
        return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


# Brick colors: the theme's plum shades, with its background as the mortar.
face, light, shadow, mortar = rgb("#3a2c4d"), rgb("#4e3d66"), rgb("#2a1f38"), rgb("#1b1226")
BW, BH, BEV, GAP = 96, 48, 4, 4


def brick_row(y):
    course, yy = divmod(y, BH)
    off = (BW // 2) * (course % 2)
    row = bytearray()
    for x in range(W):
        xx = (x + off) % BW
        if xx >= BW - GAP or yy >= BH - GAP:
            c = mortar
        elif xx < BEV or yy < BEV:
            c = shadow if (BW - GAP - xx) + (BH - GAP - yy) < 0 else light
        elif xx >= BW - GAP - BEV or yy >= BH - GAP - BEV:
            c = shadow
        else:
            c = face
        row += c
    return bytes(row)


cache = {}
rows = []
for y in range(H):
    key = (y // BH % 2, y % BH)
    if key not in cache:
        cache[key] = brick_row(y)
    rows.append(cache[key])
flat = rgb("#4a3a5e") * W
for theme, n in OUT:
    for name, image in ((f"{n}-cde-bricks.png", rows), (f"{n + 1}-cde-mauve.png", [flat] * H)):
        png(os.path.join(ROOT, "themes", theme, "backgrounds", name), image)
        print(f"themes/{theme}/backgrounds/{name}")
