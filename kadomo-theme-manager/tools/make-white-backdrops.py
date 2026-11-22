#!/usr/bin/env python3
"""Draws the White theme's wallpapers into themes/white/backgrounds/.

They borrow from Dieter Rams's Braun designs: flat off-white, black shapes,
and one orange signal.

- 0-radio: a radio face, a speaker grille of dots on the left, a tuning scale
  with an orange needle, three push buttons, and a big black dial.
- 1-meters: a pair of level meters, black segments rising to pale gray ones
  with an orange peak, beside a calendar of black dots ending in orange.
- 2-plain: a plain off-white field, a shade grayer at the bottom.

All three are flat, so they are drawn at 1920x1080 and macOS scales them up.
Run it again after changing the colors below:

    python3 tools/make-white-backdrops.py

Standard library only.
"""
import math
import os
import random
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "themes", "white", "backgrounds")
W, H = 1920, 1080


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


PAPER = rgb("#f2f2ef")
WHITE = rgb("#fafaf8")
GRAY = rgb("#dddcd7")
PALE = rgb("#c9d1d7")
INK = rgb("#1c1c1c")
ORANGE = rgb("#c8401a")


class Canvas:
    def __init__(self, fill):
        self.px = [[list(fill(x, y)) for x in range(W)] for y in range(H)]

    def blend(self, x, y, c, a):
        if 0 <= x < W and 0 <= y < H and a > 0:
            p = self.px[y]
            p[x] = [p[x][i] + (c[i] - p[x][i]) * min(a, 1.0) for i in range(3)]

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1)):
            for x in range(int(x0), int(x1)):
                self.blend(x, y, c, 1.0)

    def circle(self, cx, cy, r, c):
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                self.blend(x, y, c, r + 0.5 - math.hypot(x - cx, y - cy))

    def segment(self, x0, y0, x1, y1, width, c):
        """A straight line of the given width, antialiased."""
        lx, ly = x1 - x0, y1 - y0
        ln = math.hypot(lx, ly)
        pad = width + 1
        for y in range(int(min(y0, y1) - pad), int(max(y0, y1) + pad) + 1):
            for x in range(int(min(x0, x1) - pad), int(max(x0, x1) + pad) + 1):
                t = max(0.0, min(1.0, ((x - x0) * lx + (y - y0) * ly) / (ln * ln)))
                d = math.hypot(x - (x0 + t * lx), y - (y0 + t * ly))
                self.blend(x, y, c, width / 2 + 0.5 - d)

    def save(self, name, seed):
        # A faint grain, so the flat fields don't band on a big display.
        rnd = random.Random(seed)
        noise = [rnd.uniform(-1.0, 1.0) for _ in range(W * 7 + 13)]
        raw = bytearray()
        for y, row in enumerate(self.px):
            raw.append(0)
            for x, c in enumerate(row):
                n = noise[(x * 7 + y * 13) % len(noise)]
                raw += bytes(clamp(v + n) for v in c)

        def chunk(k, d):
            return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)

        with open(os.path.join(OUT, name), "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n")
            f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)))
            f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
            f.write(chunk(b"IEND", b""))
        print(f"themes/white/backgrounds/{name}")


def clamp(v):
    return 0 if v < 0 else 255 if v > 255 else int(v + 0.5)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def paper(x, y):
    return mix(WHITE, PAPER, y / H)


def radio():
    cv = Canvas(paper)
    # The speaker grille: a field of small dots.
    for row in range(30):
        for col in range(46):
            cv.circle(250 + col * 14, 300 + row * 14, 3.2, INK)
    # The tuning scale: a black bar with fine white ticks and an orange needle.
    sx0, sy0, sx1, sy1 = 1110, 340, 1610, 420
    cv.rect(sx0, sy0, sx1, sy1, INK)
    for i in range(61):
        x = sx0 + 25 + i * 7.5
        top = sy0 + (20 if i % 5 == 0 else 32)
        cv.segment(x, top, x, sy1 - 18, 1.6, WHITE)
    cv.rect(1404, sy0 + 10, 1408, sy1 - 10, ORANGE)
    # Three push buttons.
    for i in range(3):
        x = 1110 + i * 52
        cv.rect(x, 650, x + 34, 684, INK)
    # The dial, its white indicator pointing straight up.
    dx, dy, dr = 1460, 680, 150
    cv.circle(dx, dy, dr, INK)
    cv.segment(dx, dy - dr + 14, dx, dy - dr + 64, 4.0, WHITE)
    # A hairline across the bottom, as on the front panel.
    cv.segment(160, 900, 1760, 900, 1.2, GRAY)
    cv.save("0-radio.png", 1)


def meters():
    cv = Canvas(paper)
    # Two level meters: 22 segments each, black, then an orange peak, then pale.
    for m, level in enumerate((15, 12)):
        x0 = 420 + m * 120
        for i in range(22):
            y = 820 - i * 22
            c = INK if i < level else ORANGE if i == level else PALE
            cv.rect(x0, y, x0 + 52, y + 12, c)
        cv.circle(x0 + 26, 300, 4, INK)
    # A month of dots: seven columns, the last two (the weekend) in orange.
    gx, gy, step, r = 1120, 420, 66, 22
    for day in range(30):
        row, col = divmod(day + 2, 7)
        cv.circle(gx + col * step, gy + row * step, r, ORANGE if col >= 5 else INK)
    cv.segment(160, 900, 1760, 900, 1.2, GRAY)
    cv.save("1-meters.png", 2)


def plain():
    cv = Canvas(lambda x, y: mix(PAPER, GRAY, 0.5 * (y / H) ** 2))
    cv.save("2-plain.png", 3)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        os.remove(os.path.join(OUT, old))
    radio()
    meters()
    plain()
