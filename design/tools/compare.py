"""Puts an app screen beside the north star, for design/compare/.

    python3 design/tools/compare.py <app-screen.png> <north-star side: left|right> <out.png>

Needs Pillow. The north star image holds two phone screens; `left` is its pitch screen and
`right` is its question screen.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
NORTH_STAR = ROOT / "design/references/00-north-star.jpg"
# Crop boxes of the two phone screens inside the north star image (736x981).
SCREENS = {"left": (44, 270, 352, 925), "right": (398, 245, 705, 900)}


def main(app_path: str, side: str, out_path: str) -> None:
    app = Image.open(app_path).convert("RGB")
    height = 1400
    app = app.resize((round(app.width * height / app.height), height), Image.LANCZOS)
    ref = Image.open(NORTH_STAR).convert("RGB").crop(SCREENS[side])
    ref = ref.resize((round(ref.width * height / ref.height), height), Image.LANCZOS)

    gap, margin, caption = 48, 48, 56
    canvas = Image.new("RGB", (margin * 2 + ref.width + gap + app.width, margin * 2 + height + caption), (232, 232, 236))
    canvas.paste(ref, (margin, margin + caption))
    canvas.paste(app, (margin + ref.width + gap, margin + caption))
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, margin), "North star (reference)", fill=(90, 90, 100))
    draw.text((margin + ref.width + gap, margin), "Screenshot Brain (app render)", fill=(90, 90, 100))
    canvas.save(out_path)


if __name__ == "__main__":
    main(*sys.argv[1:4])
