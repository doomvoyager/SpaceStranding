#!/usr/bin/env python3
"""Bake the authored terrain masters down to game-ready assets.

The masters in `game/assets/terrain/_source/` are Gaea-scale exports - 8193x8193
each, 420 MB together - and neither goes into the game or into git as delivered:

  * **Godot cannot import TIFF at all.** Not a settings problem, the format is
    simply unsupported, so the colour master has to be re-encoded no matter what.
  * **Godot expands the height master to 805 MB.** The single-channel ZIP EXR
    imports as a three-channel uncompressed float `CompressedTexture2D` - measured,
    not guessed. Roughly 3.7x the file on disk and all of it resident.

So this script runs once per re-export from Gaea and writes the two files the
game actually loads. See docs/02-Systems/Terrain.md.

**8193 is 8192+1**, which is the whole reason the decimation here is free: every
power-of-two stride lands exactly on source texels, so the height bake is a pure
subsample with no resampling error at all (verified zero at strides 4, 8 and 16).
The colour bake *is* resampled, because an albedo has no such alignment to keep.

Dependencies: numpy, Pillow, tifffile. The EXR read and write are implemented
here rather than pulled from OpenEXR, which is a heavyweight build dependency for
what amounts to zlib plus a byte shuffle.

Usage, from the repo root:

    python tools/bake-terrain.py
    python tools/bake-terrain.py --color-size 8192 --height-size 4097
"""

import argparse
import pathlib
import struct
import sys
import time
import zlib

import numpy as np

REPO = pathlib.Path(__file__).resolve().parent.parent
SRC = REPO / "game" / "assets" / "terrain" / "_source"
OUT = REPO / "game" / "assets" / "terrain"

# ZIP-compressed EXR always groups scanlines 16 at a time.
LINES_PER_BLOCK = 16


# --- EXR ----------------------------------------------------------------
#
# Only the one dialect the masters use: scanline, ZIP, single FLOAT channel.
# Anything else raises rather than guessing, because a silently misread
# heightfield is a terrain that looks plausible and is wrong.


def _read_header(f):
    magic = f.read(4)
    if magic != b"\x76\x2f\x31\x01":
        raise ValueError("not an EXR file")
    version = struct.unpack("<I", f.read(4))[0]
    if version & 0x200:
        raise ValueError("tiled EXR; only scanline is supported")
    attrs = {}
    while True:
        name = _read_cstr(f)
        if not name:
            break
        typ = _read_cstr(f)
        size = struct.unpack("<i", f.read(4))[0]
        attrs[name] = (typ, f.read(size))
    return attrs


def _read_cstr(f):
    out = bytearray()
    while True:
        c = f.read(1)
        if c in (b"\0", b""):
            return out.decode()
        out += c


def read_exr_gray(path):
    """Return an (H, W) float32 array from a single-channel ZIP scanline EXR."""
    with open(path, "rb") as f:
        attrs = _read_header(f)

        chan_blob = attrs["channels"][1]
        names, q = [], 0
        while chan_blob[q] != 0:
            e = chan_blob.index(b"\0", q)
            names.append(chan_blob[q:e].decode())
            q = e + 1
            if struct.unpack("<i", chan_blob[q : q + 4])[0] != 2:
                raise ValueError("channel is not FLOAT")
            q += 16
        if len(names) != 1:
            raise ValueError(f"expected one channel, found {names}")

        if attrs["compression"][1][0] != 3:
            raise ValueError("expected ZIP compression")

        x0, y0, x1, y1 = struct.unpack("<4i", attrs["dataWindow"][1])
        w, h = x1 - x0 + 1, y1 - y0 + 1

        nblocks = (h + LINES_PER_BLOCK - 1) // LINES_PER_BLOCK
        offsets = struct.unpack(f"<{nblocks}Q", f.read(8 * nblocks))

        out = np.empty((h, w), dtype=np.float32)
        for off in offsets:
            f.seek(off)
            y, size = struct.unpack("<ii", f.read(8))
            rows = _unzip_block(f.read(size))
            block = np.frombuffer(rows, dtype="<f4").reshape(-1, w)
            out[y - y0 : y - y0 + block.shape[0]] = block
        return out


def _unzip_block(payload):
    """Inflate, undo the delta predictor, then de-interleave the two halves."""
    raw = np.frombuffer(zlib.decompress(payload), dtype=np.uint8).astype(np.int64)
    acc = np.empty(len(raw), dtype=np.int64)
    acc[0] = raw[0]
    acc[1:] = raw[0] + np.cumsum(raw[1:] - 128)
    flat = (acc & 0xFF).astype(np.uint8)

    half = (len(flat) + 1) // 2
    out = np.empty(len(flat), dtype=np.uint8)
    out[0::2] = flat[:half]
    out[1::2] = flat[half:]
    return out.tobytes()


def write_exr_gray(path, data, channel="Y"):
    """Write an (H, W) float32 array as a single-channel ZIP scanline EXR."""
    data = np.ascontiguousarray(data, dtype="<f4")
    h, w = data.shape

    header = bytearray(b"\x76\x2f\x31\x01" + struct.pack("<I", 2))

    def attr(name, typ, blob):
        header.extend(name.encode() + b"\0" + typ.encode() + b"\0")
        header.extend(struct.pack("<i", len(blob)) + blob)

    # pLinear, reserved, xSampling, ySampling after the pixel type.
    attr("channels", "chlist", channel.encode() + b"\0" + struct.pack("<i", 2)
         + struct.pack("<BBBB", 0, 0, 0, 0) + struct.pack("<ii", 1, 1) + b"\0")
    attr("compression", "compression", bytes([3]))
    attr("dataWindow", "box2i", struct.pack("<4i", 0, 0, w - 1, h - 1))
    attr("displayWindow", "box2i", struct.pack("<4i", 0, 0, w - 1, h - 1))
    attr("lineOrder", "lineOrder", bytes([0]))
    attr("pixelAspectRatio", "float", struct.pack("<f", 1.0))
    attr("screenWindowCenter", "v2f", struct.pack("<ff", 0.0, 0.0))
    attr("screenWindowWidth", "float", struct.pack("<f", 1.0))
    header.append(0)

    nblocks = (h + LINES_PER_BLOCK - 1) // LINES_PER_BLOCK
    chunks = []
    for b in range(nblocks):
        y = b * LINES_PER_BLOCK
        chunks.append(struct.pack("<ii", y, 0)[:4] + _zip_block(
            data[y : y + LINES_PER_BLOCK].tobytes()))

    # The offset table sits between header and chunks, so its own size is known
    # before any chunk position can be resolved.
    pos = len(header) + 8 * nblocks
    offsets = []
    for c in chunks:
        offsets.append(pos)
        pos += len(c) + 4  # +4 for the size field written alongside each chunk

    with open(path, "wb") as f:
        f.write(header)
        f.write(struct.pack(f"<{nblocks}Q", *offsets))
        for c in chunks:
            f.write(c[:4])
            f.write(struct.pack("<i", len(c) - 4))
            f.write(c[4:])


def _zip_block(raw):
    """The exact inverse of _unzip_block: interleave, delta, deflate."""
    a = np.frombuffer(raw, dtype=np.uint8)
    half = (len(a) + 1) // 2
    tmp = np.empty(len(a), dtype=np.uint8)
    tmp[:half] = a[0::2]
    tmp[half:] = a[1::2]

    d = np.empty(len(tmp), dtype=np.uint8)
    d[0] = tmp[0]
    d[1:] = (tmp[1:].astype(np.int64) - tmp[:-1].astype(np.int64) + 384) & 0xFF
    return zlib.compress(d.tobytes(), 9)


# --- Bakes --------------------------------------------------------------


def bake_height(size):
    src = SRC / "world_01_height.exr"
    dst = OUT / f"world_01_height_{size}.exr"
    print(f"height: reading {src.name} ...", flush=True)
    t0 = time.time()
    full = read_exr_gray(src)
    print(f"  {full.shape[1]}x{full.shape[0]} in {time.time() - t0:.1f}s, "
          f"range {full.min():.4f}..{full.max():.4f}")

    n = full.shape[0]
    if (n - 1) % (size - 1) != 0:
        raise SystemExit(
            f"--height-size {size} does not divide the {n}x{n} master evenly. "
            f"Use one of {sorted(d + 1 for d in _divisors(n - 1) if d >= 16)}.")
    stride = (n - 1) // (size - 1)
    sub = np.ascontiguousarray(full[::stride, ::stride])
    print(f"  stride {stride} -> {sub.shape[1]}x{sub.shape[0]} (exact subsample)")

    write_exr_gray(dst, sub)

    # Round-trip, because a heightfield that is wrong by a little is a terrain
    # that looks fine and puts every placed object at the wrong altitude.
    back = read_exr_gray(dst)
    err = float(np.abs(back - sub).max())
    if err != 0.0:
        raise SystemExit(f"round-trip error {err} - refusing to ship this bake")
    print(f"  wrote {dst.name} ({dst.stat().st_size / 1e6:.1f} MB), "
          f"round-trip exact")
    return sub


def _divisors(n):
    return [d for d in range(1, n + 1) if n % d == 0]


def bake_color(size, quality):
    import tifffile
    from PIL import Image

    src = SRC / "world_01_color.tif"
    dst = OUT / f"world_01_color_{size}.webp"
    print(f"colour: reading {src.name} ...", flush=True)
    t0 = time.time()
    a = tifffile.TiffFile(src).pages[0].asarray()
    print(f"  {a.shape[1]}x{a.shape[0]} in {time.time() - t0:.1f}s")

    # Drop the duplicated +1 edge before resizing: 8192 is what actually tiles,
    # and keeping the odd column skews every texel by half its own width.
    img = Image.fromarray(a[: a.shape[0] - 1, : a.shape[1] - 1])
    img = img.resize((size, size), Image.LANCZOS)
    img.save(dst, "WEBP", quality=quality, method=6)
    print(f"  wrote {dst.name} ({dst.stat().st_size / 1e6:.1f} MB, q{quality})")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--height-size", type=int, default=2049,
                   help="side of the baked heightfield; must be 8192/N + 1 "
                        "(default: 2049, which is 2 m spacing over a 4096 m map)")
    p.add_argument("--color-size", type=int, default=4096,
                   help="side of the baked albedo (default: 4096)")
    p.add_argument("--color-quality", type=int, default=92,
                   help="WebP quality 1-100 (default: 92)")
    p.add_argument("--skip-height", action="store_true")
    p.add_argument("--skip-color", action="store_true")
    args = p.parse_args()

    if not SRC.is_dir():
        raise SystemExit(f"no masters at {SRC}")
    OUT.mkdir(parents=True, exist_ok=True)

    if not args.skip_height:
        bake_height(args.height_size)
    if not args.skip_color:
        bake_color(args.color_size, args.color_quality)
    print("done")


if __name__ == "__main__":
    sys.exit(main())
