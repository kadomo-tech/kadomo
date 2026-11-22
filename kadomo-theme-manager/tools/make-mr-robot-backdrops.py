#!/usr/bin/env python3
"""Draws the Mr. Robot theme's wallpapers into themes/mr-robot/backgrounds/.

- 0-wall: the posters' slate wall, a mottled plaster texture lit softly from
  above and falling off to black at the edges.
- 1-glow: Elliot's desktop, near black with a teal glow rising from the
  bottom left.
- 2-hexdump: a dim teal hex dump filling the screen, one run of it lit
  bright cyan. Decode the bright bytes.
- 3-prompt: a root shell in the bottom left corner of a dark screen, the
  path in the prompt's blue and a teal cursor waiting.
- 4-scanlines: an old CRT, teal phosphor glowing through soft scanlines,
  with the refresh bar rolling past.
- 5-glitch: the slate wall again, torn by a few bands of shifted, teal and
  red split signal.
- 6-packets: a dim network of nodes, one route across it lit cyan from end
  to end.

The wall, the glow, the scanlines and the glitch are smooth, so they are
small and macOS scales them up; the hex dump, the prompt and the packets are
full 4K so their text and lines stay crisp. Run it again after changing
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


def slate(w, h, seeds=(1, 2, 3)):
    """The posters' wall as rows of float RGB, grain included."""
    lit, dark = rgb("#1f3c41"), rgb("#070c0e")
    coarse = value_noise(w, h, 12, seeds[0])
    fine = value_noise(w, h, 90, seeds[1])
    grain = random.Random(seeds[2])
    rows = []
    for y in range(h):
        v = y / h
        row = []
        for x in range(w):
            u = x / w
            # A soft light above the middle, like a lamp behind the subject.
            d = math.hypot((u - 0.5) * 1.5, (v - 0.32) * 1.1)
            t = math.exp(-d * d * 3.2)
            t *= 1 + 0.10 * coarse[y][x] + 0.06 * fine[y][x]
            t = max(0.0, min(1.0, t))
            n = grain.randint(-2, 2)
            row.append(tuple(dk + (lt - dk) * t + n for lt, dk in zip(lit, dark)))
        rows.append(row)
    return rows


def wall():
    w, h = 1920, 1080
    rows = [bytearray(clamp(c) for px in row for c in px) for row in slate(w, h)]
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
    # The rest of the lower case and the shell's punctuation, for the prompt.
    "g": [".....", ".....", ".####", "#...#", ".####", "....#", ".###."],
    "h": ["#....", "#....", "####.", "#...#", "#...#", "#...#", "#...#"],
    "i": ["..#..", ".....", ".##..", "..#..", "..#..", "..#..", ".###."],
    "j": ["...#.", ".....", "..##.", "...#.", "...#.", "#..#.", ".##.."],
    "k": ["#....", "#....", "#..#.", "#.#..", "##...", "#.#..", "#..#."],
    "l": [".##..", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "m": [".....", ".....", "##.#.", "#.#.#", "#.#.#", "#.#.#", "#.#.#"],
    "n": [".....", ".....", "####.", "#...#", "#...#", "#...#", "#...#"],
    "o": [".....", ".....", ".###.", "#...#", "#...#", "#...#", ".###."],
    "p": [".....", ".....", "####.", "#...#", "####.", "#....", "#...."],
    "q": [".....", ".....", ".####", "#...#", ".####", "....#", "....#"],
    "r": [".....", ".....", "#.##.", "##..#", "#....", "#....", "#...."],
    "s": [".....", ".....", ".####", "#....", ".###.", "....#", "####."],
    "t": [".#...", ".#...", "###..", ".#...", ".#...", ".#..#", "..##."],
    "u": [".....", ".....", "#...#", "#...#", "#...#", "#..##", ".##.#"],
    "v": [".....", ".....", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "w": [".....", ".....", "#...#", "#...#", "#.#.#", "#.#.#", ".#.#."],
    "x": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
    "y": [".....", ".....", "#...#", "#...#", ".####", "....#", ".###."],
    "z": [".....", ".....", "#####", "...#.", "..#..", ".#...", "#####"],
    " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
    "@": [".###.", "#...#", "#.###", "#.#.#", "#.###", "#....", ".###."],
    ":": [".....", "..#..", "..#..", ".....", "..#..", "..#..", "....."],
    "~": [".....", ".....", ".#...", "#.#.#", "...#.", ".....", "....."],
    "#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
    ".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
    "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
    "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
    "_": [".....", ".....", ".....", ".....", ".....", ".....", "#####"],
    '"': [".#.#.", ".#.#.", ".....", ".....", ".....", ".....", "....."],
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


class Canvas:
    """A 4K frame to draw text, lines and dots on, alpha blended."""

    def __init__(self, w, h, rows):
        self.w, self.h = w, h
        self.buf = bytearray(b"".join(rows))

    def blend(self, x, y, col, a):
        if a <= 0 or not (0 <= x < self.w and 0 <= y < self.h):
            return
        a = min(a, 1.0)
        i = (y * self.w + x) * 3
        b = self.buf
        b[i], b[i + 1], b[i + 2] = (clamp(b[i + k] + (col[k] - b[i + k]) * a) for k in range(3))

    def text(self, x, y, s, col, scale, a=1.0):
        """Draws s with its top left at x, y, one 6x10 cell of glyph pixels per character."""
        for n, c in enumerate(s):
            for gy, bits in enumerate(FONT[c]):
                for gx, bit in enumerate(bits):
                    if bit == "#":
                        x0, y0 = x + (n * 6 + gx) * scale, y + gy * scale
                        for yy in range(y0, y0 + scale):
                            for xx in range(x0, x0 + scale):
                                self.blend(xx, yy, col, a)

    def line(self, x0, y0, x1, y1, col, r, a=1.0, glow=False):
        """A segment r pixels in radius, antialiased, or a soft glow of radius r."""
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy) or 1.0
        reach = 2.5 * r if glow else r + 1
        steep = abs(dy) > abs(dx)
        if steep:   # walk along y and sweep across x
            x0, y0, x1, y1, dx, dy = y0, x0, y1, x1, dy, dx
        if x0 > x1:
            x0, y0, x1, y1, dx, dy = x1, y1, x0, y0, -dx, -dy
        span = reach * length / max(abs(dx), 1e-9)
        for i in range(int(x0 - reach), int(x1 + reach) + 2):
            t = (i - x0) / dx if dx else 0.0
            yc = y0 + dy * max(0.0, min(1.0, t))
            for j in range(int(yc - span) - 1, int(yc + span) + 2):
                # Distance from the pixel to the segment.
                u = max(0.0, min(1.0, ((i - x0) * dx + (j - y0) * dy) / (length * length)))
                d = math.hypot(i - (x0 + u * dx), j - (y0 + u * dy))
                k = math.exp(-(d / r) ** 2) if glow else max(0.0, min(1.0, r + 0.5 - d))
                if steep:
                    self.blend(j, i, col, a * k)
                else:
                    self.blend(i, j, col, a * k)

    def dot(self, cx, cy, r, col, a=1.0, glow=False):
        reach = 2.5 * r if glow else r + 1
        for y in range(int(cy - reach), int(cy + reach) + 2):
            for x in range(int(cx - reach), int(cx + reach) + 2):
                d = math.hypot(x - cx, y - cy)
                k = math.exp(-(d / r) ** 2) if glow else max(0.0, min(1.0, r + 0.5 - d))
                self.blend(x, y, col, a * k)

    def save(self, name):
        row = self.w * 3
        png(name, self.w, self.h, [self.buf[y * row:(y + 1) * row] for y in range(self.h)])


def field(w, h, f, shade):
    """Rows of a w x h frame shaded at 1/f the size and blown up, for smooth backgrounds
    under crisp drawing. shade(u, v) gives the color at that point of the frame."""
    sw, sh = w // f, h // f
    rows = []
    for y in range(sh):
        row = b"".join(bytes(clamp(c) for c in shade((x + 0.5) / sw, (y + 0.5) / sh)) * f for x in range(sw))
        rows += [row] * f
    return rows


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def prompt():
    w, h = 3840, 2160
    base, teal = rgb("#080c0e"), rgb("#16343a")

    def shade(u, v):
        # The faintest teal light from the bottom left, where the shell is.
        d = math.hypot((u - 0.1) * w / h, v - 0.95)
        return mix(base, teal, 0.6 * math.exp(-d * d * 1.6))

    cv = Canvas(w, h, field(w, h, 4, shade))
    host, path, cmd, out = rgb("#8a999c"), rgb("#5a7fd6"), rgb("#d0d8d7"), rgb("#55707a")
    ps1 = [("root@fsociety", host), (":", cmd), ("~", path), ("# ", cmd)]
    session = [
        ("whoami", ["root"]),
        ("ls -a", [".  ..  .bash_history  fsociety00.dat  readme.txt"]),
        ("cat readme.txt", ["leave me here"]),
        ("shred -u .bash_history", []),
        ('echo "hello friend"', ["hello friend"]),
        (None, []),
    ]
    scale, lh = 5, 64                    # glyph pixel size and line height
    lines = sum(1 + len(o) for _, o in session)
    x0, y = 220, h - 260 - lines * lh
    for command, output in session:
        x = x0
        for s, col in ps1:
            cv.text(x, y, s, col, scale, 0.75)
            x += len(s) * 6 * scale
        if command is None:              # the cursor, waiting
            for yy in range(y - scale, y + 8 * scale):
                for xx in range(x, x + 5 * scale):
                    cv.blend(xx, yy, rgb("#3a9e9e"), 0.9)
        else:
            cv.text(x, y, command, cmd, scale, 0.75)
        y += lh
        for o in output:
            cv.text(x0, y, o, out, scale, 0.8)
            y += lh
    cv.save("3-prompt.png")


def scanlines():
    w, h = 1920, 1080
    base, phosphor, hot = rgb("#060a0c"), rgb("#2a7f80"), rgb("#7fd0cc")
    rnd = random.Random(7)
    rows = []
    for y in range(h):
        v = y / h
        flicker = 1 + rnd.uniform(-0.03, 0.03)
        # Soft scanlines, a sine across four rows so scaling doesn't alias them.
        line = 0.74 + 0.26 * math.cos(2 * math.pi * y / 4)
        bar = 0.10 * math.exp(-((v - 0.68) / 0.035) ** 2)
        row = bytearray()
        for x in range(w):
            u = x / w
            d = math.hypot((u - 0.5) * 1.6, v - 0.45)
            t = 0.55 * math.exp(-d * d * 4.5) + bar
            # The tube's rounded corners falling off to black.
            edge = (1 - (2 * u - 1) ** 10) * (1 - (2 * v - 1) ** 10)
            t *= max(0.0, edge) * line * flicker
            r, g, b = mix(base, phosphor, min(t, 1.0))
            r, g, b = mix((r, g, b), hot, max(0.0, t - 0.45) * 0.6)
            n = ((x * 7919 + y * 104729) % 17 - 8) * 0.25
            row += bytes(clamp(c + n) for c in (r, g, b))
        rows.append(row)
    png("4-scanlines.png", w, h, rows)


def glitch():
    w, h = 1920, 1080
    src = slate(w, h, (11, 12, 13))
    out = [list(row) for row in src]
    teal, red, hot = rgb("#3a9e9e"), rgb("#c8484c"), rgb("#7fd0cc")
    rnd = random.Random(404)

    # A cluster of tears a little below the middle, and a few strays.
    bands = [(rnd.gauss(0.6, 0.07), rnd.choice((3, 6, 12, 24, 40, 70))) for _ in range(11)]
    bands += [(rnd.uniform(0.1, 0.9), rnd.choice((2, 4, 8))) for _ in range(4)]
    for centre, height in bands:
        y0 = int(centre * h)
        y1 = min(h, y0 + height)
        shift = rnd.randint(-160, 160)
        split = rnd.randint(3, 8)
        x0 = rnd.choice((0, rnd.randint(0, w // 2)))
        x1 = rnd.choice((w, rnd.randint(x0 + w // 4, w)))
        lift, tint = rnd.uniform(1.0, 1.3), rnd.uniform(0.08, 0.3)
        from_ = rnd.choice((0, 0, 37, -53))
        for y in range(max(0, y0), y1):
            row = src[(y + from_) % h]
            for x in range(x0, x1):
                out[y][x] = mix(tuple(c * lift for c in row[(x - shift) % w]), teal, tint)

        # The red and teal halves of the signal pulled apart: the tear's ghost
        # shows red below and right of it, teal above and left.
        def fringe(ys, xs, col, a):
            for y in ys:
                if 0 <= y < h:
                    for x in xs:
                        if 0 <= x < w:
                            out[y][x] = mix(out[y][x], col, a)

        if height >= 6:
            fringe(range(y1, y1 + split), range(x0 + split, x1 + split), red, 0.22)
            fringe(range(y0 + split, y1), range(x1, x1 + split), red, 0.22)
            fringe(range(y0 - split, y0), range(x0 - split, x1 - split), hot, 0.16)
            fringe(range(y0, y1 - split), range(x0 - split, x0), hot, 0.16)

    # Runs of dead pixels in the thick of it.
    for _ in range(12):
        y = int(rnd.gauss(0.6, 0.05) * h) % h
        x = rnd.randrange(w)
        col = rnd.choice((teal, red, hot))
        for xx in range(x, min(w, x + rnd.randint(20, 200))):
            for yy in range(y, min(h, y + rnd.choice((2, 3, 4)))):
                out[yy][xx] = mix(out[yy][xx], col, 0.5)

    rows = [bytearray(clamp(c) for px in row for c in px) for row in out]
    png("5-glitch.png", w, h, rows)


def packets():
    w, h = 3840, 2160
    base, deep = rgb("#070b0d"), rgb("#10232a")

    def shade(u, v):
        d = math.hypot((u - 0.5) * w / h, v - 0.5)
        return mix(base, deep, 0.7 * math.exp(-d * d * 1.2))

    cv = Canvas(w, h, field(w, h, 4, shade))
    edge, node, bright, label = rgb("#1a3a3e"), rgb("#2c5c60"), rgb("#7fd0cc"), rgb("#3a6e72")
    rnd = random.Random(2600)

    # Nodes on a jittered grid with holes in it.
    cols, lines = 18, 10
    nodes = []
    for j in range(lines):
        for i in range(cols):
            if rnd.random() < 0.3:
                continue
            nodes.append(((i + 0.5 + rnd.uniform(-0.35, 0.35)) * w / cols,
                          (j + 0.5 + rnd.uniform(-0.35, 0.35)) * h / lines))

    # Each node linked to its nearest few.
    links = set()
    for a, (ax, ay) in enumerate(nodes):
        near = sorted(range(len(nodes)), key=lambda b: math.hypot(nodes[b][0] - ax, nodes[b][1] - ay))
        for b in near[1:1 + rnd.choice((2, 3, 3))]:
            if math.hypot(nodes[b][0] - ax, nodes[b][1] - ay) < 2.2 * w / cols:
                links.add((min(a, b), max(a, b)))

    def fade(x, y):
        return (0.3 + 0.7 * math.sin(math.pi * x / w) ** 0.6) * (0.3 + 0.7 * math.sin(math.pi * y / h) ** 0.6)

    for a, b in links:
        (ax, ay), (bx, by) = nodes[a], nodes[b]
        cv.line(ax, ay, bx, by, edge, 1.2, fade((ax + bx) / 2, (ay + by) / 2))
    for x, y in nodes:
        cv.dot(x, y, 5, node, fade(x, y))

    # The route: the shortest way from the far left to the far right.
    graph = {n: [] for n in range(len(nodes))}
    for a, b in links:
        d = math.hypot(nodes[a][0] - nodes[b][0], nodes[a][1] - nodes[b][1])
        graph[a].append((b, d))
        graph[b].append((a, d))
    left = min(range(len(nodes)), key=lambda n: nodes[n][0] + abs(nodes[n][1] - h * 0.6))
    right = max(range(len(nodes)), key=lambda n: nodes[n][0] - abs(nodes[n][1] - h * 0.4))
    dist, prev, todo = {left: 0.0}, {}, {left}
    while todo:
        a = min(todo, key=dist.get)
        todo.discard(a)
        for b, d in graph[a]:
            if dist[a] + d < dist.get(b, math.inf):
                dist[b], prev[b] = dist[a] + d, a
                todo.add(b)
    route = [right]
    while route[-1] != left and route[-1] in prev:
        route.append(prev[route[-1]])
    route.reverse()

    for a, b in zip(route, route[1:]):
        cv.line(*nodes[a], *nodes[b], bright, 10, 0.18, glow=True)
    for a, b in zip(route, route[1:]):
        cv.line(*nodes[a], *nodes[b], bright, 1.6, 0.9)
    for n in route:
        cv.dot(*nodes[n], 14, bright, 0.25, glow=True)
        cv.dot(*nodes[n], 7, bright)

    # Addresses above either end, kept clear of the route and the screen's edges.
    for n, addr in ((left, "10.0.0.7"), (route[-1], "192.251.68.254")):
        x, y = nodes[n]
        x = max(40, min(w - 40 - len(addr) * 24, x - len(addr) * 12))
        cv.text(int(x), int(y) - 70, addr, label, 4)
    cv.save("6-packets.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    wall()
    glow()
    hexdump()
    prompt()
    scanlines()
    glitch()
    packets()
