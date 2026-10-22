#!/usr/bin/env python3
"""Generate the logo files in docs/branding/ (pure vector, no fonts needed: the lettering is drawn as strokes).

    python3 tools/make_branding.py          # writes the SVGs; PNGs too if ImageMagick (magick) is installed

The wordmark is ORBITAL LASER with the O replaced by a targeting reticle that the beam drops into.
"""
import shutil, subprocess
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "docs" / "branding"
OUT.mkdir(parents=True, exist_ok=True)

BEAM, RING = "#29A3FF", "#FF8800"          # beam blue, crater orange
STROKE, H, GAP, SPACE = 11, 100, 36, 84    # stroke width, cap height, letter gap, word gap

# monoline capitals on a 100-unit cap height: (path, advance width)
G = {
    "R": ("M0 100V0H33A25 25 0 0 1 33 50H0M31 50L58 100", 58),
    "B": ("M0 0V100H32A27 27 0 0 0 32 46H0M32 46A23 23 0 0 0 32 0H0", 56),
    "I": ("M0 0V100", 0),
    "T": ("M0 0H60M30 0V100", 60),
    "A": ("M0 100L31 0L62 100M12 66H50", 62),
    "L": ("M0 0V100H48", 48),
    "S": ("M52 16C46 5 38 0 27 0C12 0 3 9 3 22C3 35 14 41 27 47C41 54 53 61 53 77C53 91 42 100 27 100C14 100 5 94 1 83", 54),
    "E": ("M52 0H0V100H52M0 50H44", 52),
}


def reticle(x, ink):
    """The O: an orange ring with inner ticks, and the beam coming down into its centre."""
    cx, cy = x + 50, 50
    return (f'<g transform="translate({x} 0) translate(50 50) scale(1.16) translate(-50 -50)">'
            f'<defs><linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{BEAM}" stop-opacity="0"/><stop offset="0.45" stop-color="{BEAM}" stop-opacity="1"/></linearGradient>'
            f'<linearGradient id="fadew" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="#FFFFFF" stop-opacity="0"/><stop offset="0.45" stop-color="#FFFFFF" stop-opacity="1"/></linearGradient></defs>'
            f'<circle cx="50" cy="50" r="44" fill="none" stroke="{RING}" stroke-width="{STROKE}"/>'
            f'<path d="M15 50H29M71 50H85M50 71V85" fill="none" stroke="{RING}" stroke-width="{STROKE - 3}"/>'
            f'<rect x="43" y="-110" width="14" height="160" fill="url(#fade)"/>'
            f'<rect x="47" y="-110" width="6" height="160" fill="url(#fadew)"/>'
            f'<circle cx="50" cy="50" r="9" fill="#FFFFFF" stroke="{BEAM}" stroke-width="4"/></g>')


def wordmark(ink):
    parts, x = [], 0
    layout = [("O", None), ("R",), ("B",), ("I",), ("T",), ("A",), ("L",), ("SP",), ("L",), ("A",), ("S",), ("E",), ("R",)]
    glyphs = []
    for item in layout:
        k = item[0]
        if k == "SP":
            x += SPACE - GAP
            continue
        if k == "O":
            glyphs.append(reticle(x, ink)); x += 100 + GAP
            continue
        d, w = G[k]
        glyphs.append(f'<path transform="translate({x} 0)" d="{d}"/>'); x += w + GAP
    width = x - GAP
    body = (f'<g fill="none" stroke="{ink}" stroke-width="{STROKE}" stroke-linejoin="miter" stroke-linecap="butt">'
            + "".join(g for g in glyphs if g.startswith("<path")) + "</g>"
            + "".join(g for g in glyphs if g.startswith("<g")))
    return body, width


def logo(name, plate, ink):
    body, w = wordmark(ink)
    pad_x, top, bottom = 112, 190, 90
    W, Hh = w + pad_x * 2, top + H + bottom
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {Hh}" width="{W}" height="{Hh}">'
           f'<title>Orbital Laser</title>'
           f'<rect width="{W}" height="{Hh}" rx="{Hh * 0.26:.0f}" fill="{plate}"/>'
           f'<g transform="translate({pad_x} {top})">{body}</g></svg>')
    (OUT / name).write_text(svg)


def icon(name, plate):
    s = 1024
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s} {s}" width="{s}" height="{s}">'
           f'<title>Orbital Laser</title><rect width="{s}" height="{s}" rx="230" fill="{plate}"/>'
           f'<g transform="translate(212 218) scale(6)">{reticle(0, "#FFFFFF")}</g></svg>')
    (OUT / name).write_text(svg)


def social_preview(tagline="A terrestrial orbital laser strike for Horizon"):
    """1280x640 social preview, laid out like Portalcraft's: grey ground, the wordmark 1025 px wide centred at
    y = 262, a one-line tagline in Barlow Medium 40 px centred at y = 479, and a 14 px blue/orange bar on the bottom edge."""
    import tempfile
    from PIL import Image, ImageDraw, ImageFont
    body, w = wordmark("#222428")
    pad = 60
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-{pad} -190 {w + pad * 2} 380" '
           f'width="{(w + pad * 2) * 3}" height="1140"><g>{body}</g></svg>')
    with tempfile.TemporaryDirectory() as t:
        src, png = Path(t, "w.svg"), Path(t, "w.png")
        src.write_text(svg)
        subprocess.run(["magick", "-background", "none", "-density", "288", str(src), str(png)], check=True)
        mark = Image.open(png).convert("RGBA")
    # crop to the visible ink (ignoring the faint top of the beam's fade), then fit to 1025 px wide
    alpha = mark.split()[3].point(lambda v: 255 if v > 90 else 0)
    mark = mark.crop(alpha.getbbox())
    mark = mark.resize((1025, round(mark.height * 1025 / mark.width)), Image.LANCZOS)
    bg = Image.new("RGBA", (1280, 640), "#E9EAEC")
    bg.alpha_composite(mark, ((1280 - mark.width) // 2, round(262 - mark.height / 2)))
    d = ImageDraw.Draw(bg)
    font_file = Path(__file__).resolve().parent / "fonts" / "Barlow-Medium.ttf"
    font = ImageFont.truetype(str(font_file), 40)
    box = d.textbbox((0, 0), tagline, font=font)
    d.text(((1280 - (box[2] - box[0])) / 2 - box[0], 479 - (box[1] + box[3]) / 2), tagline, font=font, fill="#222428")
    d.rectangle([0, 626, 639, 639], fill="#1F7AD6")
    d.rectangle([640, 626, 1279, 639], fill="#E8820C")
    bg.convert("RGB").save(OUT / "social-preview.png", optimize=True)


logo("orbital-laser-logo-light.svg", "#FFFFFF", "#303133")
logo("orbital-laser-logo-dark.svg", "#1F2328", "#E8EAED")
icon("orbital-laser-icon.svg", "#1F2328")

if shutil.which("magick"):
    subprocess.run(["magick", "-background", "none", "-density", "192", str(OUT / "orbital-laser-icon.svg"),
                    "-resize", "1024x1024", str(OUT / "orbital-laser-icon.png")], check=True)
if shutil.which("magick"):
    try:
        social_preview()
    except ImportError:
        print("Pillow missing: skipped social-preview.png")
print("wrote", *sorted(p.name for p in OUT.iterdir()))
