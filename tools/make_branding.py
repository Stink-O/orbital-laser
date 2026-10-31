#!/usr/bin/env python3
"""Make the branding in docs/branding/ from its two traced logos.

    python3 tools/make_branding.py          # needs ImageMagick (magick) and Pillow

The sources are orbital-laser-logo-light.svg (the wordmark: ORBITAL LASER, its O a targeting reticle, the beam
striking just past it) and orbital-laser-icon.svg (the reticle alone, the beam dropping into it), both in dark ink
for light backgrounds. From them: their dark-background versions (the ink turned light; the beam and the burst as
they are), the icon as a PNG, and social-preview.png (GitHub's 1280 x 640 card: the wordmark over a strike).
"""
import subprocess, tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "branding"
INK = ("#0C1729", "#0D1B2D")     # the traced ink's fills (the wordmark's, the icon's)
LIGHT = "#E9EDF2"
FONT = Path(__file__).resolve().parent / "fonts" / "Barlow-Medium.ttf"


def dark(src, dst):
    svg = (OUT / src).read_text()
    for ink in INK:
        svg = svg.replace(f'fill="{ink}"', f'fill="{LIGHT}"')
    (OUT / dst).write_text(svg)


def raster(svg, width):
    with tempfile.TemporaryDirectory() as t:
        png = Path(t, "out.png")
        subprocess.run(["magick", "-background", "none", "-density", "288", str(OUT / svg), "-resize", f"{width}x", str(png)], check=True)
        return Image.open(png).convert("RGBA")


def social_preview():
    W, H = 1280, 640
    # a strike on the right of the card (its ship and beam clear of the words), fading into the dark on the left
    # (a taller crop of the Payload's column than docs/32, so its foot and the land under it fit the card)
    shot = Image.open(ROOT / "docs" / "branding" / "payload-card.jpg").convert("RGB")
    shot = shot.resize((round(shot.width * H / shot.height), H), Image.LANCZOS)
    card = Image.new("RGBA", (W, H), (7, 10, 17, 255))
    card.paste(shot, (W - shot.width + 200, 0))
    shade = Image.new("RGBA", (W, H))
    px = shade.load()
    for x in range(W):
        a = round(255 * min(1.0, max(0.0, (760 - x) / 380)) ** 0.8)
        for y in range(H):
            px[x, y] = (7, 10, 17, min(a + round(60 * (y / H) ** 3), 255))
    card.alpha_composite(shade)
    # the wordmark and what it is
    logo = raster("orbital-laser-logo-dark.svg", 560)
    card.alpha_composite(logo, (72, 140))
    d = ImageDraw.Draw(card)
    d.text((80, 140 + logo.height + 34), "Orbital strikes for Horizon,", font=ImageFont.truetype(str(FONT), 32), fill="#C4CBD4")
    d.text((80, 140 + logo.height + 76), "the Rust rewrite of Minecraft Java", font=ImageFont.truetype(str(FONT), 32), fill="#C4CBD4")
    names = ImageFont.truetype(str(FONT), 19)
    d.text((80, 140 + logo.height + 136), "PLASMA · GODLY · BLACK HOLE · METEOR STORM · MOTHERSHIP", font=names, fill="#FF9A2E")
    d.text((80, 140 + logo.height + 166), "DOWNFALL · PLANET KILLER · CRYSTAL BLOOM · SINKHOLE · PAYLOAD", font=names, fill="#FF9A2E")
    d.text((80, 140 + logo.height + 196), "NUKE", font=names, fill="#FF9A2E")
    card.convert("RGB").save(OUT / "social-preview.png", optimize=True)


dark("orbital-laser-logo-light.svg", "orbital-laser-logo-dark.svg")
dark("orbital-laser-icon.svg", "orbital-laser-icon-dark.svg")
raster("orbital-laser-icon.svg", 1024).save(OUT / "orbital-laser-icon.png")
social_preview()
print("wrote", *sorted(p.name for p in OUT.iterdir()))
