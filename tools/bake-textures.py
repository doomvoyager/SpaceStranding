#!/usr/bin/env python3
"""Bake the texture masters down to the sizes the game loads.

Masters live in `game/assets/textures/_source/`, which is gitignored and carries
a `.gdignore`, so Godot never imports them and git never stores them - the same
rule as the terrain masters. This writes the game-ready copies beside the
folder, keeping each master's name, format and channels; only the size changes.

`lens_dirt_2.png` arrived at 6016x4016 and 55 MB, with every speck of dust in its
alpha and the colour a near-flat brown-grey. At 3008x2008 it is 2.7 MB, and it is
drawn full-screen, so that is still sharper than a 1080p frame. See
docs/02-Systems/Lens.md.

Resampling is Lanczos, and Pillow premultiplies alpha while it does it, so the
colour of a fully transparent pixel cannot bleed into a speck's edge.

Dependencies: Pillow.

Usage, from the repo root:

    python tools/bake-textures.py
    python tools/bake-textures.py --only lens_dirt_2.png
"""

import argparse
import pathlib
import sys

from PIL import Image

REPO = pathlib.Path(__file__).resolve().parent.parent
SRC = REPO / "game" / "assets" / "textures" / "_source"
OUT = REPO / "game" / "assets" / "textures"

# Master file name -> width of the baked copy. Height follows the aspect.
BAKES = {
    "lens_dirt_2.png": 3008,
}


def bake(name: str, width: int) -> None:
    src = SRC / name
    dst = OUT / name
    Image.MAX_IMAGE_PIXELS = None
    with Image.open(src) as im:
        height = round(im.height * width / im.width)
        out = im.resize((width, height), Image.LANCZOS)
        out.save(dst, optimize=True)
        print(f"{name}: {im.width}x{im.height} {src.stat().st_size / 1e6:.1f} MB"
              f" -> {width}x{height} {dst.stat().st_size / 1e6:.1f} MB ({out.mode})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--only", help="bake just this master")
    args = parser.parse_args()
    names = [args.only] if args.only else list(BAKES)
    for name in names:
        if name not in BAKES:
            print(f"no bake size for {name}; add it to BAKES", file=sys.stderr)
            return 1
        if not (SRC / name).exists():
            print(f"missing master: {SRC / name}", file=sys.stderr)
            return 1
        bake(name, BAKES[name])
    return 0


if __name__ == "__main__":
    sys.exit(main())
