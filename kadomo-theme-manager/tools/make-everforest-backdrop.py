#!/usr/bin/env python3
"""Draws the Everforest theme's wallpaper into themes/everforest/backgrounds/.

Just one image: a plain #2c353a field, no gradient or texture. Run it again
if the color ever changes:

    python3 tools/make-everforest-backdrop.py

Standard library only.
"""
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "themes", "everforest", "backgrounds")
W, H = 1920, 1080
COLOR = (0x2c, 0x35, 0x3a)


def png(name, w, h, color):
    row = b"\x00" + bytes(color) * w
    raw = row * h

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))
    print(f"themes/everforest/backgrounds/{name}")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    png("0-plain.png", W, H, COLOR)
