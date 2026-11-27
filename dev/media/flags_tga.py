"""Writes Media/Flags/<locale>.tga: the flag of each language the addon ships.

The sources are flagcdn.com's PNGs 160 wide (https://flagcdn.com/w160/<cc>.png,
public domain, Media/Flags/README.md), downloaded into a folder of their own.
Each flag keeps its own aspect: scaled to 32 high by area averaging and
centred on a 64 x 32 canvas, the rest transparent. Written as an uncompressed
32-bit TGA with alpha (image type 2, 8 alpha bits, bottom-left origin), the
format of Media/wheel.tga. Only the standard library: the PNG decoder reads
the non-interlaced 8-bit-or-less palette, grey and 8-bit RGB(A) files flagcdn
serves. Usage, from the repo root:
python3 -I dev/media/flags_tga.py <png folder> [out folder, default Media/Flags]
"""
import os
import struct
import sys
import zlib

WIDTH, HEIGHT = 64, 32
# locale code: the country code of its flag
FLAGS = {"enUS": "us", "deDE": "de", "esES": "es", "esMX": "mx", "frFR": "fr", "itIT": "it",
         "koKR": "kr", "ptBR": "br", "ruRU": "ru", "zhCN": "cn", "zhTW": "tw"}


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path):
    """Answers width, height and rows of (r, g, b, a) tuples."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(path + ": not a PNG")
    pos, idat, palette, trns = 8, b"", None, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    if interlace or (colour in (2, 4, 6) and depth != 8) or depth > 8:
        raise ValueError(path + ": an unsupported PNG layout")
    raw = zlib.decompress(idat)
    stride = (width * channels * depth + 7) // 8
    step = max(1, channels * depth // 8)
    rows, previous, pos = [], bytearray(stride), 0
    for _ in range(height):
        kind, line = raw[pos], bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            a = line[i - step] if i >= step else 0
            b = previous[i]
            c = previous[i - step] if i >= step else 0
            line[i] = (line[i] + (0, a, b, (a + b) // 2, paeth(a, b, c))[kind]) & 0xFF
        previous = line
        if depth < 8:
            per = 8 // depth
            values = [(line[x // per] >> (8 - depth * (x % per + 1))) & ((1 << depth) - 1) for x in range(width)]
        else:
            values = [tuple(line[x * channels:(x + 1) * channels]) for x in range(width)]
        out = []
        for v in values:
            if colour == 3:
                index = v if depth < 8 else v[0]
                alpha = trns[index] if index < len(trns) else 255
                out.append(palette[index] + (alpha,))
            elif colour == 0:
                g = v if depth < 8 else v[0]
                g = g * 255 // ((1 << depth) - 1)
                out.append((g, g, g, 255))
            elif colour == 4:
                out.append((v[0], v[0], v[0], v[1]))
            elif colour == 2:
                out.append(v + (255,))
            else:
                out.append(v)
        rows.append(out)
    return width, height, rows


def scale(width, height, rows, new_width, new_height):
    """Area averaging, alpha-weighted: each target pixel the mean of the source it covers."""
    fx, fy = width / new_width, height / new_height
    out = []
    for ty in range(new_height):
        y0, y1 = ty * fy, (ty + 1) * fy
        line = []
        for tx in range(new_width):
            x0, x1 = tx * fx, (tx + 1) * fx
            r = g = b = a = area = 0.0
            for sy in range(int(y0), min(height, int(-(-y1 // 1)))):
                wy = min(y1, sy + 1) - max(y0, sy)
                for sx in range(int(x0), min(width, int(-(-x1 // 1)))):
                    w = wy * (min(x1, sx + 1) - max(x0, sx))
                    pr, pg, pb, pa = rows[sy][sx]
                    r, g, b, a, area = r + pr * pa * w, g + pg * pa * w, b + pb * pa * w, a + pa * w, area + w
            if a == 0:
                line.append((0, 0, 0, 0))
            else:
                line.append((round(r / a), round(g / a), round(b / a), round(a / area)))
        out.append(line)
    return out


def write_tga(path, pixels):
    """pixels: WIDTH x HEIGHT rows, top first; written bottom row first."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, WIDTH, HEIGHT, 32, 8)
    body = bytearray()
    for row in reversed(pixels):
        for r, g, b, a in row:
            body += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(header + bytes(body))


def main(source, out):
    os.makedirs(out, exist_ok=True)
    for locale, country in sorted(FLAGS.items()):
        width, height, rows = read_png(os.path.join(source, country + ".png"))
        flag_width = min(WIDTH, round(HEIGHT * width / height))
        flag = scale(width, height, rows, flag_width, HEIGHT)
        left = (WIDTH - flag_width) // 2
        canvas = [[(0, 0, 0, 0)] * left + line + [(0, 0, 0, 0)] * (WIDTH - left - flag_width) for line in flag]
        write_tga(os.path.join(out, locale + ".tga"), canvas)
        print(locale, country, "%dx%d -> %dx%d on %dx%d" % (width, height, flag_width, HEIGHT, WIDTH, HEIGHT))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else os.path.join("Media", "Flags"))
