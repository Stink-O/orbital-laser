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


def social_preview(tagline="An orbital laser strike for Horizon"):
    """1280x640 social preview, drawn for this project: the name on the left, and on the right the strike itself,
    a beam coming down into a crater with shockwave rings on the ground and a couple of forked bolts. Flat, dark and simple."""
    import math, random, tempfile
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
    S = 2                                   # draw at 2x, then downsample for clean edges
    W, H = 1280 * S, 640 * S
    rnd = random.Random(7)
    cx, impact = 925 * S, 438 * S           # the beam's x and where it lands

    def layer():
        return Image.new("RGBA", (W, H), (0, 0, 0, 0))

    def glow(img, radius):
        return img.filter(ImageFilter.GaussianBlur(radius * S))

    # ground: deep blue-black, a faint pool of light where the beam lands
    bg = Image.new("RGBA", (W, H), "#0D1117")
    pool = layer()
    pd = ImageDraw.Draw(pool)
    for i in range(14, 0, -1):
        k = i / 14
        pd.ellipse([cx - 520 * S * k, impact - 110 * S * k, cx + 520 * S * k, impact + 110 * S * k], fill=(255, 136, 0, int(9 * (1 - k) + 2)))
    bg.alpha_composite(glow(pool, 20))

    # shockwave rings lying on the ground, in perspective
    rings = layer()
    rd = ImageDraw.Draw(rings)
    for rx, a, wd in ((150, 255, 5), (290, 190, 4), (440, 120, 3), (600, 62, 3)):
        rd.ellipse([cx - rx * S, impact - rx * 0.2 * S, cx + rx * S, impact + rx * 0.2 * S], outline=(255, 136, 0, a), width=wd * S)
    bg.alpha_composite(glow(rings, 7))
    bg.alpha_composite(rings)

    # the crater: a dark hole with a glowing rim, and the molten light inside it
    cr = layer()
    cd = ImageDraw.Draw(cr)
    cd.ellipse([cx - 74 * S, impact - 15 * S, cx + 74 * S, impact + 15 * S], fill="#05070A", outline=(255, 160, 40, 255), width=4 * S)
    bg.alpha_composite(glow(cr, 5))
    bg.alpha_composite(cr)
    lava = layer()
    ld = ImageDraw.Draw(lava)
    ld.ellipse([cx - 52 * S, impact - 8 * S, cx + 52 * S, impact + 8 * S], fill=(255, 190, 90, 255))
    bg.alpha_composite(glow(lava, 6))

    # the beam: blue glow, blue body, white core, fading in from the top edge
    def beam_layer(width, color, blur):
        L = layer()
        d = ImageDraw.Draw(L)
        d.rectangle([cx - width * S / 2, 0, cx + width * S / 2, impact], fill=color)
        L = glow(L, blur) if blur else L
        fade = Image.linear_gradient("L").resize((W, H)).point(lambda v: min(255, int(v * 4.2)))   # 0 at the top, opaque by ~25% down
        r, g, b_, al = L.split()
        al = Image.composite(al, Image.new("L", (W, H), 0), Image.new("L", (W, H), 255))
        mask = Image.fromarray(__import__("numpy").minimum(al, fade))
        L.putalpha(mask)
        return L
    bg.alpha_composite(beam_layer(120, (41, 163, 255, 120), 26))
    bg.alpha_composite(beam_layer(34, (41, 163, 255, 255), 2))
    bg.alpha_composite(beam_layer(12, (255, 255, 255, 255), 0))

    # the flash where it lands
    fl = layer()
    fd = ImageDraw.Draw(fl)
    for i in range(10, 0, -1):
        k = i / 10
        fd.ellipse([cx - 120 * S * k, impact - 42 * S * k, cx + 120 * S * k, impact + 42 * S * k], fill=(255, 255, 255, int(40 * (1 - k) + 18)))
    bg.alpha_composite(glow(fl, 10))
    # impact flare: a hot white-orange bloom that swallows the beam's base, with a darker crater mouth under it
    fz = layer()
    zd = ImageDraw.Draw(fz)
    for i in range(14, 0, -1):
        k = i / 14
        zd.ellipse([cx - 95 * S * k, impact - 34 * S * k, cx + 95 * S * k, impact + 34 * S * k],
                   fill=(255, int(150 + 105 * (1 - k)), int(40 + 190 * (1 - k) ** 2), int(255 * (1 - k) ** 0.8 + 20)))
    bg.alpha_composite(glow(fz, 4))
    bg.alpha_composite(fz)
    up = layer()
    ImageDraw.Draw(up).ellipse([cx - 16 * S, impact - 120 * S, cx + 16 * S, impact - 6 * S], fill=(255, 255, 255, 235))
    bg.alpha_composite(glow(up, 5))

    # forked bolts, jagged and rooted on the beam
    def bolt(x0, y0, x1, y1, amp, steps=9):
        pts = [(x0, y0)]
        for i in range(1, steps):
            t = i / steps
            nx, ny = -(y1 - y0), (x1 - x0)
            n = math.hypot(nx, ny) or 1
            j = rnd.uniform(-amp, amp) * math.sin(math.pi * t)
            pts.append((x0 + (x1 - x0) * t + nx / n * j, y0 + (y1 - y0) * t + ny / n * j))
        pts.append((x1, y1))
        return pts
    lt = layer()
    ld2 = ImageDraw.Draw(lt)
    specs = [((cx + 6 * S, 190 * S), (cx + 215 * S, 150 * S)), ((cx - 6 * S, 270 * S), (cx - 190 * S, 318 * S)),
             ((cx + 6 * S, 330 * S), (cx + 150 * S, 372 * S))]
    for (x0, y0), (x1, y1) in specs:
        main = bolt(x0, y0, x1, y1, 22 * S)
        ld2.line(main, fill=(235, 246, 255, 255), width=3 * S, joint="curve")
        mx, my = main[len(main) // 2]
        fork = bolt(mx, my, mx + (x1 - x0) * 0.35, my + (y1 - y0) * 0.9 + 34 * S, 14 * S, 6)
        ld2.line(fork, fill=(235, 246, 255, 230), width=2 * S, joint="curve")
    bg.alpha_composite(glow(lt, 5))
    bg.alpha_composite(lt)

    # a few sparks
    sp = layer()
    sd = ImageDraw.Draw(sp)
    for _ in range(26):
        x = cx + rnd.gauss(0, 95 * S)
        y = rnd.uniform(120 * S, impact - 12 * S)
        r = rnd.uniform(1.5, 3.2) * S
        sd.ellipse([x - r, y - r, x + r, y + r], fill=(255, 214, 150, rnd.randint(150, 255)))
    bg.alpha_composite(sp)

    # the name, stacked and left-aligned: the O is a small reticle
    ink = "#E8EAED"
    scale = 0.86
    def line_svg(word, ring_first):
        x, parts = 0, []
        for k, ch in enumerate(word):
            if ch == "O":
                parts.append(f'<g transform="translate({x} 0)"><circle cx="50" cy="50" r="44" fill="none" stroke="{RING}" stroke-width="{STROKE}"/>'
                             f'<path d="M15 50H29M71 50H85M50 15V29M50 71V85" fill="none" stroke="{RING}" stroke-width="{STROKE - 3}"/>'
                             f'<circle cx="50" cy="50" r="8" fill="{BEAM}"/></g>')
                x += 100 + GAP
            else:
                d, w = G[ch]
                parts.append(f'<path transform="translate({x} 0)" d="{d}" fill="none" stroke="{ink}" stroke-width="{STROKE}" stroke-linejoin="miter" stroke-linecap="butt"/>')
                x += w + GAP
        return "".join(parts), x - GAP
    def place(word, top, left=96):
        body, w = line_svg(word, True)
        pad = 12
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-{pad} -{pad} {w + 2 * pad} {100 + 2 * pad}" '
               f'width="{round((w + 2 * pad) * scale * S)}" height="{round((100 + 2 * pad) * scale * S)}">{body}</svg>')
        with tempfile.TemporaryDirectory() as t:
            src, png = Path(t, "w.svg"), Path(t, "w.png")
            src.write_text(svg)
            subprocess.run(["magick", "-background", "none", "-density", "96", str(src), str(png)], check=True)
            im = Image.open(png).convert("RGBA")
        bg.alpha_composite(im, (round((left - pad * scale) * S), round((top - pad * scale) * S)))
    place("ORBITAL", 168)
    place("LASER", 168 + 100 * scale + 52)
    d = ImageDraw.Draw(bg)
    font = ImageFont.truetype(str(Path(__file__).resolve().parent / "fonts" / "Barlow-Medium.ttf"), 34 * S)
    d.text((96 * S, 440 * S), tagline, font=font, fill="#9AA4AF")

    bg.resize((1280, 640), Image.LANCZOS).convert("RGB").save(OUT / "social-preview.png", optimize=True)


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
