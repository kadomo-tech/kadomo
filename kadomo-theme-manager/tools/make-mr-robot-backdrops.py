#!/usr/bin/env python3
"""Draws the Mr. Robot theme's wallpapers into themes/mr-robot/backgrounds/.

- 0-wall: the posters' slate wall, a mottled plaster texture lit softly from
  above and falling off to black at the edges.
- 1-glow: Elliot's desktop, near black with a teal glow rising from the
  bottom left.
- 2-hexdump: a dim teal hex dump filling the screen, one run of it lit
  bright cyan. Decode the bright bytes.

The wall and the glow are smooth, so they are small and macOS scales them up;
the hex dump is full 4K so its digits stay crisp. Run it again after changing
the colors below:

    python3 tools/make-mr-robot-backdrops.py

Standard library only.
"""
import math
import os
import random
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "themes", "mr-robot", "backgrounds")


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def png(name, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(k, d):
        return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)

    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))
    print(f"themes/mr-robot/backgrounds/{name}")


def clamp(v):
    return 0 if v < 0 else 255 if v > 255 else int(v + 0.5)


def value_noise(w, h, cells_x, seed):
    """Smooth random field in -1..1, bilinear between random grid points."""
    rnd = random.Random(seed)
    cells_y = max(1, round(cells_x * h / w))
    grid = [[rnd.uniform(-1, 1) for _ in range(cells_x + 2)] for _ in range(cells_y + 2)]
    field = []
    for y in range(h):
        gy = y * cells_y / h
        j, fy = int(gy), gy - int(gy)
        fy = fy * fy * (3 - 2 * fy)
        a, b = grid[j], grid[j + 1]
        row = []
        for x in range(w):
            gx = x * cells_x / w
            i, fx = int(gx), gx - int(gx)
            fx = fx * fx * (3 - 2 * fx)
            top = a[i] + (a[i + 1] - a[i]) * fx
            bot = b[i] + (b[i + 1] - b[i]) * fx
            row.append(top + (bot - top) * fy)
        field.append(row)
    return field


def wall():
    w, h = 1920, 1080
    lit, dark = rgb("#1f3c41"), rgb("#070c0e")
    coarse = value_noise(w, h, 12, 1)
    fine = value_noise(w, h, 90, 2)
    grain = random.Random(3)
    rows = []
    for y in range(h):
        v = y / h
        row = bytearray()
        for x in range(w):
            u = x / w
            # A soft light above the middle, like a lamp behind the subject.
            d = math.hypot((u - 0.5) * 1.5, (v - 0.32) * 1.1)
            t = math.exp(-d * d * 3.2)
            t *= 1 + 0.10 * coarse[y][x] + 0.06 * fine[y][x]
            t = max(0.0, min(1.0, t))
            n = grain.randint(-2, 2)
            row += bytes(clamp(dk + (lt - dk) * t + n) for lt, dk in zip(lit, dark))
        rows.append(row)
    png("0-wall.png", w, h, rows)


def glow():
    w, h = 960, 540
    base, teal, deep = rgb("#070b0d"), rgb("#3a9e9e"), rgb("#1b3a44")
    rows = []
    for y in range(h):
        v = y / h
        row = bytearray()
        for x in range(w):
            u = x / w
            r, g, b = base
            for cx, cy, rad, col, s in ((0.05, 1.1, 0.9, teal, 0.55), (0.35, 0.9, 1.1, deep, 0.5)):
                d = math.hypot((u - cx) * w / h, v - cy) / rad
                k = s * math.exp(-d * d * 2.2)
                r, g, b = r + (col[0] - r) * k, g + (col[1] - g) * k, b + (col[2] - b) * k
            n = ((x * 7919 + y * 104729) % 17 - 8) * 0.25
            row += bytes(clamp(c + n) for c in (r, g, b))
        rows.append(row)
    png("1-glow.png", w, h, rows)


# 5x7 glyphs for the hex digits, one string per row, "#" lit.
FONT = {
    "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
    "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    "3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
    "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
    "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
    "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
    "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
    "a": [".....", ".....", ".###.", "....#", ".####", "#...#", ".####"],
    "b": ["#....", "#....", "####.", "#...#", "#...#", "#...#", "####."],
    "c": [".....", ".....", ".###.", "#....", "#....", "#...#", ".###."],
    "d": ["....#", "....#", ".####", "#...#", "#...#", "#...#", ".####"],
    "e": [".....", ".....", ".###.", "#...#", "#####", "#....", ".###."],
    "f": ["..##.", ".#..#", ".#...", "###..", ".#...", ".#...", ".#..."],
}


def hexdump():
    w, h = 3840, 2160
    scale, cw, ch = 4, 24, 40           # glyph pixel size, cell width and height
    cols, lines = w // cw, h // ch
    bg = rgb("#0a0e11")
    dim, offset_col, bright = rgb("#1f4648"), rgb("#16292d"), rgb("#7fd0cc")
    secret = b"hello friend"
    rnd = random.Random(1337)
    secret_line = lines * 3 // 5

    # Each line: an 8-digit offset, then 16 bytes in two groups of 8, as hexdump -C.
    text = []                            # per line: list of (char, color) per column
    for n in range(lines):
        cells = [(c, offset_col) for c in f"{n * 16:08x}"] + [(" ", None)] * 2
        data = bytearray(rnd.randrange(256) for _ in range(16))
        lit = set()
        if n == secret_line:
            data[2:2 + len(secret)] = secret
            lit = set(range(2, 2 + len(secret)))
        for i, byte in enumerate(data):
            col = bright if i in lit else dim
            cells += [(c, col) for c in f"{byte:02x}"] + [(" ", None)]
            if i == 7:
                cells.append((" ", None))
        # Repeat the line's bytes across the screen so the dump fills the width.
        while len(cells) < cols:
            byte = rnd.randrange(256)
            cells += [(c, dim) for c in f"{byte:02x}"] + [(" ", None)]
        text.append(cells[:cols])

    # Darken toward the edges, separably so it stays cheap.
    fx = [0.35 + 0.65 * math.sin(math.pi * x / w) ** 0.6 for x in range(w)]
    fy = [0.35 + 0.65 * math.sin(math.pi * y / h) ** 0.6 for y in range(h)]
    pad_y = (ch - 7 * scale) // 2
    rows = []
    for y in range(h):
        line, yy = divmod(y, ch)
        gy = (yy - pad_y) // scale if pad_y <= yy < pad_y + 7 * scale else -1
        row = bytearray(bg * w)
        if line < lines and gy >= 0:
            for c, (ch_, col) in enumerate(text[line]):
                if col is None:
                    continue
                bits = FONT[ch_][gy]
                x0 = c * cw + (cw - 5 * scale) // 2
                for gx, bit in enumerate(bits):
                    if bit == "#":
                        for x in range(x0 + gx * scale, x0 + (gx + 1) * scale):
                            k = fx[x] * fy[y] if col is not bright else 1.0
                            row[x * 3:x * 3 + 3] = bytes(clamp(b + (c_ - b) * k) for b, c_ in zip(bg, col))
        rows.append(row)
    png("2-hexdump.png", w, h, rows)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    wall()
    glow()
    hexdump()
