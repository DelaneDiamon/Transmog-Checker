"""Writes Media/funnel.tga: the funnel glyph of the appearance browser's filter button.

Slice E (E2) reshaped the design mock's funnel (addon-settings.html, path
M1 2h12L8.3 7.6V12L5.7 13V7.6Z) to read as a funnel at 20 units: a wide
rim, a short cone and a clear square stem, centred in a viewBox of 0 0 14
14, fill #ffd100, black stroke 0.8 with round joins. Drawn at 64 x 64 as an uncompressed 32-bit TGA with alpha (image type
2, 8 alpha bits, bottom-left origin), the format of Media/wheel.tga. Edges
are antialiased by 8 x 8 samples per pixel. Usage, from the repo root:
python3 dev/media/funnel_tga.py [out]
"""
import math
import struct
import sys

SIZE, SAMPLES, VIEW = 64, 8, 14.0
# the rim (y 1.6 to 3.4), the cone down to the stem (y 7.8), the stem (x 5.5 to 8.5)
POINTS = [(0.9, 1.6), (13.1, 1.6), (13.1, 3.4), (8.5, 7.8), (8.5, 12.6), (5.5, 12.6), (5.5, 7.8), (0.9, 3.4)]
FILL, STROKE, HALF_STROKE = (0xFF, 0xD1, 0x00), (0, 0, 0), 0.4


def inside(x, y):
    hit = False
    for i in range(len(POINTS)):
        (x1, y1), (x2, y2) = POINTS[i], POINTS[(i + 1) % len(POINTS)]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def edge_distance(x, y):
    best = float("inf")
    for i in range(len(POINTS)):
        (x1, y1), (x2, y2) = POINTS[i], POINTS[(i + 1) % len(POINTS)]
        dx, dy = x2 - x1, y2 - y1
        t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(x - (x1 + t * dx), y - (y1 + t * dy)))
    return best


def pixel(px, py):
    """Premultiplied colour sums over the samples of pixel (px, py), y down."""
    r = g = b = a = 0.0
    for sy in range(SAMPLES):
        for sx in range(SAMPLES):
            x = (px + (sx + 0.5) / SAMPLES) * VIEW / SIZE
            y = (py + (sy + 0.5) / SAMPLES) * VIEW / SIZE
            # the stroke is painted over the fill; a distance within half its
            # width of an edge or corner gives the round joins
            if edge_distance(x, y) <= HALF_STROKE:
                colour = STROKE
            elif inside(x, y):
                colour = FILL
            else:
                continue
            r, g, b, a = r + colour[0], g + colour[1], b + colour[2], a + 1
    n = SAMPLES * SAMPLES
    if a == 0:
        return 0, 0, 0, 0
    return round(r / a), round(g / a), round(b / a), round(255 * a / n)


def main(out):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    rows = []
    for py in range(SIZE - 1, -1, -1):  # bottom-left origin: the last row first
        row = bytearray()
        for px in range(SIZE):
            r, g, b, a = pixel(px, py)
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    with open(out, "wb") as f:
        f.write(header + b"".join(rows))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Media/funnel.tga")
