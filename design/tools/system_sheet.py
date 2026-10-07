"""Stitches the design lab exports into design/system.png: light pages on top, dark below.

    python3 design/tools/system_sheet.py

Needs Pillow. Run after CI has exported design/lab/*.png.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / "design/lab"
PAGES = ["tokens", "light", "components", "surfaces"]
HEIGHT = 1300
GAP = 40


def main() -> None:
    rows = []
    for appearance in ("light", "dark"):
        images = []
        for page in PAGES:
            image = Image.open(LAB / f"{page}-{appearance}.png").convert("RGB")
            images.append(image.resize((round(image.width * HEIGHT / image.height), HEIGHT), Image.LANCZOS))
        rows.append(images)

    width = GAP + sum(image.width + GAP for image in rows[0])
    sheet = Image.new("RGB", (width, GAP + len(rows) * (HEIGHT + GAP)), (226, 226, 231))
    for row_index, images in enumerate(rows):
        x = GAP
        for image in images:
            sheet.paste(image, (x, GAP + row_index * (HEIGHT + GAP)))
            x += image.width + GAP
    sheet.save(ROOT / "design/system.png", optimize=True)


if __name__ == "__main__":
    main()
