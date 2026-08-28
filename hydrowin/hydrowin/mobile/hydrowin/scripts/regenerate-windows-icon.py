"""Regenerate windows/runner/resources/app_icon.ico from branding logo."""

from __future__ import annotations

import io
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "branding" / "hydrowin_logo.png"
OUT = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
SIZES = (16, 32, 48, 64, 128, 256)


def fit_logo(size: int, logo: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    scaled = logo.copy()
    scaled.thumbnail((size, size), Image.Resampling.LANCZOS)
    x = (size - scaled.width) // 2
    y = (size - scaled.height) // 2
    canvas.paste(scaled, (x, y), scaled)
    return canvas


def write_multi_png_ico(path: Path, images: list[Image.Image]) -> None:
    pngs = []
    for image in images:
        buf = io.BytesIO()
        image.save(buf, format="PNG")
        pngs.append(buf.getvalue())

    offset = 6 + 16 * len(pngs)
    header = struct.pack("<HHH", 0, 1, len(pngs))
    entries = bytearray()
    data = bytearray()
    for image, png in zip(images, pngs, strict=True):
        width = 0 if image.width >= 256 else image.width
        height = 0 if image.height >= 256 else image.height
        entries.extend(
            struct.pack(
                "<BBBBHHII",
                width,
                height,
                0,
                0,
                1,
                32,
                len(png),
                offset,
            )
        )
        data.extend(png)
        offset += len(png)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + bytes(entries) + data)


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"Logo not found: {SRC}")

    logo = Image.open(SRC).convert("RGBA")
    images = [fit_logo(size, logo) for size in SIZES]
    write_multi_png_ico(OUT, images)
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes, {len(SIZES)} sizes)")


if __name__ == "__main__":
    main()
