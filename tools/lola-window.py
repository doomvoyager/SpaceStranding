#!/usr/bin/env python3
"""Fetch a window of NASA's LOLA south-pole elevation model and bake it for the game.

The ground is the real south pole as of 2026-09-14 (see docs/07-Decisions). NASA's
Planetary Geodynamics lab publishes the LOLA polar DEMs as public-domain GeoTIFFs:

    20m   LDEM_80S_20MPP_ADJ.TIF   80-90 S, 20 m/px, 30400 px, 2.7 GB
    10m   LDEM_83S_10MPP_ADJ.TIF   83-90 S, 10 m/px, 30400 px, 5.1 GB
    5m    ldem_87s_5mpp.tif        87-90 S,  5 m/px, 40000 px, 3.5 GB

Nobody downloads those. They are tiled BigTIFFs and the server takes byte ranges,
so a window is a handful of tile-sized requests: 25.6 km at 20 m is 16 MB.

**The tiles are decoded here, not by tifffile.** They are ADOBE_DEFLATE with the
TIFF floating-point predictor, which tifffile refuses without the imagecodecs
package - a 30 MB binary wheel for fifteen lines of numpy. After inflating, each
row holds the four byte planes of its floats most-significant first,
horizontally differenced; a wrapping cumulative sum undoes the differencing and
a transpose gathers the planes back into big-endian floats. Checked against the
tile at the pole: heights of -1.2 to +1.6 km, no NaN, 4 m between rows.

**Projection.** Polar stereographic on the pole, metres, +x toward 90 E and +y
toward 0 E; pixel (0, 0) is the top-left corner at (-half, +half). Shackleton's
rim runs through the pole and its floor is 4 km down, which is how the axes were
checked.

The height bake is written with the EXR writer in bake-terrain.py, in raw
metres: `ProceduralTerrain` remaps a map by its own min and max, so set
`height_span` to the relief this prints. `detect_3d/compress_to=0` still has to
be written into the .import by hand, or Godot re-imports the heights as lossy
the first time a material touches them - see docs/02-Systems/Terrain.md.

Usage, from the repo root:

    python3 tools/lola-window.py --product 20m --center 2000 -3000 --size 25600 \\
        --preview previews/2026-09-14/lola-overview
    python3 tools/lola-window.py --product 5m --center 0 0 --size 4100 --resample 1025 \\
        --out game/assets/terrain/lola_pole_4100.exr --preview previews/2026-09-14/lola-pole
    python3 tools/lola-window.py --product 5m --center 0 0 --size 24585 --smooth 2.5 \\
        --raw game/assets/terrain/lola_pole_24k.hf --preview previews/2026-09-15/lola-24k
"""

import argparse
import importlib.util
import io
import pathlib
import sys
import time
import urllib.request
import zlib

import numpy as np

REPO = pathlib.Path(__file__).resolve().parent.parent
MOON_RADIUS = 1_737_400.0

PRODUCTS = {
    "20m": ("https://pgda.gsfc.nasa.gov/data/LOLA_20mpp/LDEM_80S_20MPP_ADJ.TIF", 2696082051),
    "10m": ("https://pgda.gsfc.nasa.gov/data/LOLA_20mpp/LDEM_83S_10MPP_ADJ.TIF", 5116709568),
    "5m": ("https://pgda.gsfc.nasa.gov/data/LOLA_5mpp/87S/ldem_87s_5mpp.tif", 3465285714),
}

CHUNK = 1 << 20


class RangeFile(io.RawIOBase):
    """A read-only file over an HTTP URL, fetched a megabyte at a time by Range."""

    def __init__(self, url, size):
        self.url, self.size, self.pos, self.cache, self.fetched = url, size, 0, {}, 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def seek(self, off, whence=0):
        self.pos = {0: off, 1: self.pos + off, 2: self.size + off}[whence]
        return self.pos

    def tell(self):
        return self.pos

    def _chunk(self, i):
        if i not in self.cache:
            start = i * CHUNK
            end = min(start + CHUNK, self.size) - 1
            req = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{end}"})
            self.cache[i] = urllib.request.urlopen(req, timeout=120).read()
            self.fetched += len(self.cache[i])
        return self.cache[i]

    def read(self, n=-1):
        if n < 0:
            n = self.size - self.pos
        out = bytearray()
        while n > 0 and self.pos < self.size:
            i, off = divmod(self.pos, CHUNK)
            piece = self._chunk(i)[off:off + n]
            out += piece
            self.pos += len(piece)
            n -= len(piece)
        return bytes(out)

    def readinto(self, b):
        data = self.read(len(b))
        b[:len(data)] = data
        return len(data)


def decode_tile(data, width, height):
    """One DEFLATE + floating-point-predictor tile to (height, width) float32."""
    raw = zlib.decompress(data)
    rows = np.frombuffer(raw, np.uint8).reshape(height, width * 4)
    rows = np.cumsum(rows, axis=1, dtype=np.uint8)  # undo the differencing, mod 256
    planes = rows.reshape(height, 4, width)  # byte planes, most significant first
    be = np.ascontiguousarray(planes.transpose(0, 2, 1))
    return be.view(">f4").reshape(height, width).astype(np.float32)


class Product:
    def __init__(self, key):
        import tifffile
        url, size = PRODUCTS[key]
        self.key = key
        self.fh = RangeFile(url, size)
        self.page = tifffile.TiffFile(self.fh).pages[0]
        p = self.page
        self.scale = float(p.tags["ModelPixelScaleTag"].value[0])
        tie = p.tags["ModelTiepointTag"].value
        self.x0, self.y0 = float(tie[3]), float(tie[4])
        self.tw, self.th = p.tilewidth, p.tilelength
        self.tiles_across = (p.imagewidth + self.tw - 1) // self.tw

    def window(self, cx, cy, size_m):
        """A square window centred at projected (cx, cy) metres, north up."""
        n = int(round(size_m / self.scale))
        col0 = int(round((cx - size_m / 2 - self.x0) / self.scale))
        row0 = int(round((self.y0 - (cy + size_m / 2)) / self.scale))
        out = np.full((n, n), np.nan, np.float32)
        for tr in range(row0 // self.th, (row0 + n - 1) // self.th + 1):
            for tc in range(col0 // self.tw, (col0 + n - 1) // self.tw + 1):
                idx = tr * self.tiles_across + tc
                self.fh.seek(self.page.dataoffsets[idx])
                tile = decode_tile(self.fh.read(self.page.databytecounts[idx]), self.tw, self.th)
                r_off, c_off = tr * self.th - row0, tc * self.tw - col0
                rs, re_ = max(0, r_off), min(n, r_off + self.th)
                cs, ce = max(0, c_off), min(n, c_off + self.tw)
                out[rs:re_, cs:ce] = tile[rs - r_off:re_ - r_off, cs - c_off:ce - c_off]
        return out


def project(lat_deg, lon_deg):
    """Polar stereographic metres for a south-polar latitude and east longitude."""
    rho = 2.0 * MOON_RADIUS * np.tan(np.radians(90.0 + lat_deg) / 2.0)
    return rho * np.sin(np.radians(lon_deg)), rho * np.cos(np.radians(lon_deg))


def resample(z, n):
    """Bilinear resample of a square array to n x n, corners kept on corners."""
    src = z.shape[0]
    f = np.linspace(0.0, src - 1, n)
    i0 = np.clip(np.floor(f).astype(int), 0, src - 2)
    t = (f - i0)[:, None]
    rows = z[i0] * (1 - t) + z[i0 + 1] * t  # (n, src)
    t = (f - i0)[None, :]
    return (rows[:, i0] * (1 - t) + rows[:, i0 + 1] * t).astype(np.float32)


def smooth(z, sigma):
    """Separable Gaussian blur, sigma in samples, edges held.

    The 5 m product carries about 0.54 m of per-sample speckle - a 6 degree
    tilt per sample - which is invisible where the sun hits the ground
    squarely and comes out as bright lines on every face the sun grazes,
    measured 2026-09-15 (docs/02-Systems/Terrain.md, "Striations"). A sigma of
    one sample takes it down about threefold and leaves anything wider than
    ~20 m alone, and still draws most of the lines; 2.5 - what the world
    uses - takes most of the lines and the steepest faces with them (p99
    slope 36.1 to 34.2 degrees). The detail layer will put controlled
    roughness back.
    """
    if sigma <= 0.0:
        return z
    radius = int(np.ceil(3.0 * sigma))
    x = np.arange(-radius, radius + 1, dtype=np.float64)
    k = np.exp(-0.5 * (x / sigma) ** 2)
    k /= k.sum()
    pad = np.pad(z.astype(np.float64), radius, mode="edge")
    rows = np.apply_along_axis(lambda r: np.convolve(r, k, mode="valid"), 1, pad)
    out = np.apply_along_axis(lambda c: np.convolve(c, k, mode="valid"), 0, rows)
    return out.astype(np.float32)


def slopes(z, spacing):
    gy, gx = np.gradient(z, spacing)
    return np.degrees(np.arctan(np.hypot(gx, gy))), gx, gy


def report(z, spacing, label, threshold):
    v = z[~np.isnan(z)]
    print(f"{label}: {z.shape[1]} x {z.shape[0]} px at {spacing:g} m = "
          f"{z.shape[1] * spacing / 1000:.2f} km, {int(np.isnan(z).sum())} nodata")
    print(f"  elevation {v.min():.0f} .. {v.max():.0f} m, relief {v.max() - v.min():.0f} m")
    s, _, _ = slopes(z, spacing)
    sv = s[~np.isnan(s)]
    print("  slope: median %.1f  p90 %.1f  p99 %.1f  max %.1f deg"
          % tuple(np.percentile(sv, [50, 90, 99, 100])))
    print("  share <= 15 deg %.1f%%   <= %g deg %.1f%%   > 35 deg %.1f%%"
          % ((sv <= 15).mean() * 100, threshold, (sv <= threshold).mean() * 100,
             (sv > 35).mean() * 100))
    return s


def previews(z, spacing, prefix, sun_elevation_deg, threshold):
    """A hillshade under the game's sun, a drivability mask and a height ramp."""
    from PIL import Image
    s, gx, gy = slopes(z, spacing)
    e = np.radians(sun_elevation_deg)
    light = np.array([0.0, np.cos(e), np.sin(e)])  # toward the sun: from +y, low
    nrm = np.dstack([-gx, gy, np.ones_like(z)]).astype(np.float64)
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    lit = np.clip(nrm @ light, 0.0, 1.0)
    hill = np.clip(0.15 + 0.85 * lit, 0.0, 1.0)
    Image.fromarray((np.nan_to_num(hill) * 255).astype(np.uint8)).save(f"{prefix}-hill.png")
    mask = np.zeros(z.shape + (3,), np.uint8)
    mask[..., 1] = (s <= threshold) * 180
    mask[..., 0] = (s > threshold) * 200
    mask[np.isnan(s)] = 40
    Image.fromarray(mask).save(f"{prefix}-slope.png")
    lo, hi = np.nanmin(z), np.nanmax(z)
    ramp = np.nan_to_num((z - lo) / max(hi - lo, 1e-6))
    Image.fromarray((ramp * 255).astype(np.uint8)).save(f"{prefix}-height.png")
    print(f"  previews: {prefix}-hill.png, -slope.png, -height.png")


RAW_MAGIC = b"SSHF"


def write_raw(path, z, spacing):
    """The heightfield as the game reads it: a 32-byte header, then float32 rows.

    Not an EXR, because Godot's importer expands one float channel to three -
    a 4917 px window would become 290 MB of texture - and because a texture is
    the wrong shape for a heightfield the whole world has to be able to query.
    `StreamedTerrain` reads this with FileAccess in one call. Little-endian
    float32, north up: row 0 is the northern edge, column 0 the western.

        0   "SSHF"        4 bytes
        4   width         u32, samples per row
        8   height        u32, rows
        12  spacing       f32, metres between samples
        16  lowest        f32, metres
        20  highest       f32, metres
        24  reserved      8 bytes, zero
        32  samples       width * height * float32, row-major
    """
    z = np.ascontiguousarray(z, dtype="<f4")
    with open(path, "wb") as f:
        f.write(RAW_MAGIC)
        f.write(np.array([z.shape[1], z.shape[0]], "<u4").tobytes())
        f.write(np.array([spacing, float(z.min()), float(z.max())], "<f4").tobytes())
        f.write(bytes(8))
        f.write(z.tobytes())


def exr_writer():
    spec = importlib.util.spec_from_file_location("bake_terrain", REPO / "tools" / "bake-terrain.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.write_exr_gray


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--product", choices=PRODUCTS, default="20m")
    ap.add_argument("--center", nargs=2, type=float, metavar=("X", "Y"),
                    help="window centre in projected metres from the pole")
    ap.add_argument("--latlon", nargs=2, type=float, metavar=("LAT", "LON"),
                    help="window centre as south-polar latitude and east longitude")
    ap.add_argument("--size", type=float, default=25600.0, help="window side in metres")
    ap.add_argument("--smooth", type=float, default=0.0,
                    help="Gaussian sigma in samples applied after the fetch; 1.0 takes the 5 m product's speckle down")
    ap.add_argument("--resample", type=int, default=0,
                    help="resample the window to this many pixels a side (1025 for 4 m over 4100 m)")
    ap.add_argument("--out", help="EXR to write, in raw metres")
    ap.add_argument("--raw", help="heightfield file to write for StreamedTerrain (see write_raw)")
    ap.add_argument("--preview", help="prefix for the three preview PNGs")
    ap.add_argument("--sun", type=float, default=5.5, help="sun elevation for the hillshade")
    ap.add_argument("--threshold", type=float, default=25.0, help="the rover's slope limit, degrees")
    args = ap.parse_args()

    if args.latlon:
        cx, cy = project(*args.latlon)
        print(f"{args.latlon[0]} S {args.latlon[1]} E is ({cx:.0f}, {cy:.0f}) m from the pole")
    else:
        cx, cy = args.center if args.center else (0.0, 0.0)

    t = time.time()
    prod = Product(args.product)
    z = prod.window(cx, cy, args.size)
    print(f"fetched {prod.fh.fetched / 1e6:.1f} MB in {time.time() - t:.1f} s")
    if np.isnan(z).any():
        sys.exit("the window has nodata in it; move it or pick a coarser product")
    report(z, prod.scale, f"{args.product} window at ({cx:.0f}, {cy:.0f})", args.threshold)

    spacing = prod.scale
    if args.smooth > 0.0:
        t = time.time()
        z = smooth(z, args.smooth)
        print(f"smoothed with sigma {args.smooth:g} samples in {time.time() - t:.1f} s")
        report(z, spacing, "smoothed", args.threshold)
    if args.resample:
        z = resample(z, args.resample)
        spacing = args.size / (args.resample - 1)
        report(z, spacing, f"resampled to {args.resample}", args.threshold)

    if args.preview:
        previews(z, spacing, args.preview, args.sun, args.threshold)

    if args.raw:
        write_raw(args.raw, z, spacing)
        print(f"wrote {args.raw}: {z.shape[1]} x {z.shape[0]} at {spacing:g} m, "
              f"{(z.shape[1] - 1) * spacing:g} m across, {pathlib.Path(args.raw).stat().st_size / 1e6:.1f} MB")

    if args.out:
        exr_writer()(args.out, z)
        lo, hi = float(z.min()), float(z.max())
        print(f"wrote {args.out}: {z.shape[1]} px over {args.size:g} m")
        print(f"  terrain settings: size = {args.size:g}, height_span = {hi - lo:.1f}, "
              f"resolution = {args.size / (z.shape[1] - 1):.3g}")


if __name__ == "__main__":
    main()
