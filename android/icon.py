#!/usr/bin/env python3
"""Bakes the Android launcher icon out of assets/icon/.

The icon is a sheep mid-hop in front of the dusk: a crescent moon, a few stars
and the hill it jumps over, in the game's palette (gfx.lua). It is kept as two
40px pictures, so the adaptive icon gets its two layers:

- assets/icon/background.png, the dusk sky and the hill, opaque;
- assets/icon/foreground.png, the sheep, on clear.

Every size here is a whole-number scale of those (a 40px drawing resampled to
fit a box comes out as a smear), centred, with the background scaled up past
the edges and cropped rather than left short of them.

Two sets are written into a love-android checkout's res/ directory:

- drawable-*dpi/love.png, the square legacy icon (48dp), which is what the
  manifest's @drawable/love names and what launchers before Android 8 use;
- drawable-*dpi/love_bg.png and love_fg.png plus drawable-anydpi-v26/love.xml,
  the adaptive icon (108dp, the sheep kept inside the 66dp the launcher
  promises not to mask), which every launcher since then prefers.

Standard library only (zlib), so the workflow needs nothing installed. Taken
from underroot.

    python3 android/icon.py <love-android>/app/src/main/res
"""

import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON = os.path.join(ROOT, "assets", "icon")

# (density, legacy px, adaptive layer px)
DENSITIES = [
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
]

# Share of the 108dp adaptive square the foreground may stand in: 66 / 108.
SAFE = 66 / 108


def read_png(path):
    """An 8-bit RGBA or RGB, non-interlaced PNG -> (w, h, [[(r, g, b, a)]])."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("icon.py: %s is not a PNG" % path)
    pos, idat, head = 8, b"", None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            head = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    w, h, depth, ctype, _, _, interlace = head
    if depth != 8 or ctype not in (2, 6) or interlace:
        sys.exit("icon.py: %s must be 8-bit RGB(A), not interlaced" % path)
    bpp = 4 if ctype == 6 else 3
    raw, stride = zlib.decompress(idat), w * bpp
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(h):
        kind, line = raw[pos], bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([tuple(line[x * bpp:x * bpp + bpp]) + ((255,) if bpp == 3 else ()) for x in range(w)])
        prev = line
    return w, h, rows


def png(path, size, pixels):
    """pixels(x, y) -> (r, g, b, a). Writes an 8-bit RGBA PNG."""
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter: none
        for x in range(size):
            raw.extend(pixels(x, y))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def layers():
    bw, bh, bg = read_png(os.path.join(ICON, "background.png"))
    fw, fh, fg = read_png(os.path.join(ICON, "foreground.png"))
    if (bw, bh) != (fw, fh) or bw != bh:
        sys.exit("icon.py: the two layers must be the same square size")
    return bw, bg, fg


def bbox(side, fg):
    xs = [x for y in range(side) for x in range(side) if fg[y][x][3]]
    ys = [y for y in range(side) for x in range(side) if fg[y][x][3]]
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def sampler(side, layer, scale, size, anchor=None):
    """layer drawn at a whole scale, centred in size (or with box centred)."""
    if anchor:
        x0, y0, x1, y1 = anchor
        ox = (size - (x1 - x0) * scale) // 2 - x0 * scale
        oy = (size - (y1 - y0) * scale) // 2 - y0 * scale
    else:
        ox = oy = (size - side * scale) // 2

    def pixel(x, y):
        gx, gy = (x - ox) // scale, (y - oy) // scale
        if 0 <= gx < side and 0 <= gy < side:
            return layer[gy][gx]
        return (0, 0, 0, 0)

    return pixel


def over(top, bottom):
    def pixel(x, y):
        t = top(x, y)
        return t if t[3] else bottom(x, y)

    return pixel


def cover(side, size):
    """Smallest whole scale that leaves no edge of the square uncovered."""
    return -(-size // side)


def fit(extent, size):
    return max(1, size // extent)


def icon(size, side, bg, fg, fill=1.0, box=None):
    """The whole icon in a size x size square: background covering it, the
    foreground at the largest whole scale whose box fits fill of it."""
    box = box or (0, 0, side, side)
    extent = max(box[2] - box[0], box[3] - box[1])
    front = sampler(side, fg, fit(extent, int(size * fill)), size, box)
    return over(front, sampler(side, bg, cover(side, size), size))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    res = sys.argv[1]
    side, bg, fg = layers()
    box = bbox(side, fg)
    extent = max(box[2] - box[0], box[3] - box[1])

    for density, size, layer in DENSITIES:
        folder = os.path.join(res, "drawable-" + density)
        png(os.path.join(folder, "love.png"), size, icon(size, side, bg, fg))
        png(os.path.join(folder, "love_bg.png"), layer, sampler(side, bg, cover(side, layer), layer))
        png(os.path.join(folder, "love_fg.png"), layer,
            sampler(side, fg, fit(extent, int(layer * SAFE)), layer, box))

    adaptive = os.path.join(res, "drawable-anydpi-v26")
    os.makedirs(adaptive, exist_ok=True)
    with open(os.path.join(adaptive, "love.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/love_bg" />\n'
            '    <foreground android:drawable="@drawable/love_fg" />\n'
            '</adaptive-icon>\n'
        )


if __name__ == "__main__":
    main()
