"""Renders the app icon (light, dark and tinted) into the asset catalog.

    python3 design/tools/app_icon.py

The same recipe as the app's light: a closed shape filled with one gradient (interpolated in
OKLab), blurred hard along one direction so it reads as a long exposure, with faint grain. The
mark on top is the app's: the four corners of a screenshot's frame. Needs Pillow and NumPy.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "App/Resources/Assets.xcassets/AppIcon.appiconset"
SIZE = 1024
SCALE = 2  # supersample, then downscale


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def to_oklab(rgb):
    r, g, b = srgb_to_linear(rgb)
    l = np.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = np.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = np.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return np.array([
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    ])


def from_oklab(lab):
    L, a, b = lab
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return linear_to_srgb(np.stack([r, g, bb]))


def hex_rgb(value):
    return np.array([(value >> 16) & 255, (value >> 8) & 255, value & 255]) / 255


# The north star's two-tone smear: a deep indigo body with a warm salmon leading edge.
STOPS = [0x24206F, 0x4A3BB8, 0xC34FA0, 0xF57E74, 0xFFB07A]


def gradient_field(size, start, end):
    """OKLab gradient along start -> end, as an RGB float image."""
    labs = np.stack([to_oklab(hex_rgb(c)) for c in STOPS])
    ys, xs = np.mgrid[0:size, 0:size] / size
    axis = np.array(end) - np.array(start)
    t = ((xs - start[0]) * axis[0] + (ys - start[1]) * axis[1]) / (axis @ axis)
    t = np.clip(t, 0, 1) * (len(STOPS) - 1)
    index = np.minimum(t.astype(int), len(STOPS) - 2)
    frac = (t - index)[..., None]
    lab = labs[index] * (1 - frac) + labs[index + 1] * frac
    return from_oklab(np.moveaxis(lab, -1, 0)).transpose(1, 2, 0)


def catmull_rom(points, steps=24):
    """A smooth closed curve through the points."""
    pts = np.array(points)
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        for t in np.linspace(0, 1, steps, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return [tuple(p) for p in out]


def directional_blur(image, angle_deg, radius, stretch):
    """Rotate, squash along the motion, blur, unsquash, rotate back: blur that's longer one way."""
    w, h = image.size
    rotated = image.rotate(angle_deg, resample=Image.BICUBIC, expand=True)
    rw, rh = rotated.size
    squashed = rotated.resize((max(1, int(rw / stretch)), rh), Image.LANCZOS)
    blurred = squashed.filter(ImageFilter.GaussianBlur(radius))
    unsquashed = blurred.resize((rw, rh), Image.LANCZOS)
    back = unsquashed.rotate(-angle_deg, resample=Image.BICUBIC, expand=False)
    left, top = (back.width - w) // 2, (back.height - h) // 2
    return back.crop((left, top, left + w, top + h))


def render(dark=False, tinted=False):
    s = SIZE * SCALE
    top = hex_rgb(0x0B0B0D if dark else 0xF4F3F7)
    bottom = hex_rgb(0x111016 if dark else 0xE9E7F2)
    ys = np.linspace(0, 1, s)[:, None, None]
    ground = top * (1 - ys) + bottom * ys
    ground = np.broadcast_to(ground, (s, s, 3)).copy()

    # The smear: a long diagonal sweep from upper right to lower left.
    shape_points = [(1.08, 0.10), (0.78, 0.06), (0.52, 0.18), (0.30, 0.42), (0.06, 0.78), (-0.04, 0.98),
                    (0.12, 0.96), (0.34, 0.70), (0.56, 0.50), (0.80, 0.42), (1.08, 0.40)]
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).polygon([(x * s, y * s) for x, y in catmull_rom(shape_points)], fill=255)
    fill = gradient_field(s, (0.95, 0.10), (0.05, 0.92))

    color = Image.fromarray((fill * 255).astype(np.uint8))
    premult = Image.composite(color, Image.new("RGB", (s, s), (0, 0, 0)), mask)
    soft_mask = directional_blur(mask, -38, s * 0.035, 2.4)
    soft_color = directional_blur(premult, -38, s * 0.035, 2.4)

    alpha = np.asarray(soft_mask, dtype=np.float64)[..., None] / 255
    rgb = np.asarray(soft_color, dtype=np.float64) / 255 / np.maximum(alpha, 1e-4)
    rgb = np.clip(rgb, 0, 1)
    strength = 0.95 if dark else 0.88
    image = ground * (1 - alpha * strength) + rgb * alpha * strength

    if tinted:
        luminance = image @ np.array([0.2126, 0.7152, 0.0722])
        image = np.repeat(luminance[..., None], 3, axis=2)

    # Faint grain, enough to kill banding.
    rng = np.random.default_rng(7)
    image = np.clip(image + rng.normal(0, 0.012, image.shape), 0, 1)
    icon = Image.fromarray((image * 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS)

    # The mark: four corners of a screenshot's frame, centred, thin and round-capped.
    draw = ImageDraw.Draw(icon)
    ink = (243, 243, 246) if dark else (22, 22, 26)
    half_w, half_h, arm, width = 150, 230, 78, 22
    cx, cy = SIZE / 2, SIZE / 2
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = cx + sx * half_w, cy + sy * half_h
            draw.line([(x, y - sy * arm), (x, y), (x - sx * arm, y)], fill=ink, width=width, joint="curve")
            for px, py in ((x, y - sy * arm), (x - sx * arm, y)):
                draw.ellipse([px - width / 2, py - width / 2, px + width / 2, py + width / 2], fill=ink)
    return icon


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    render().save(OUT / "AppIcon.png")
    render(dark=True).save(OUT / "AppIcon-dark.png")
    render(tinted=True).convert("L").save(OUT / "AppIcon-tinted.png")
    (OUT / "Contents.json").write_text("""{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "AppIcon-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "AppIcon-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""")


if __name__ == "__main__":
    main()
