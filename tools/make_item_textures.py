#!/usr/bin/env python3
"""Draw the 16x16 item textures (and a preview sheet): the designator, the remote, and one icon per laser for the
remote's menu.

    python3 tools/make_item_textures.py
"""
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "orbital-laser-mod" / "assets" / "orbital" / "textures" / "item"
OUT.mkdir(parents=True, exist_ok=True)

K = {  # palette
    ".": (0, 0, 0, 0),
    "d": (24, 27, 33, 255),       # outline
    "g": (52, 58, 68, 255),       # dark body
    "G": (88, 97, 112, 255),      # light body
    "w": (170, 180, 196, 255),    # highlight
    "o": (255, 136, 0, 255),      # orange ring
    "O": (255, 190, 80, 255),     # orange light
    "b": (41, 163, 255, 255),     # beam blue
    "B": (150, 215, 255, 255),    # blue light
    "W": (255, 255, 255, 255),
    "r": (226, 52, 52, 255),
    "p": (160, 90, 255, 255),     # void violet
    "y": (255, 212, 90, 255),     # godly gold
    "c": (70, 230, 255, 255),     # screen cyan
}

def designator():
    """A spyglass-like tube on the diagonal: eyepiece bottom-left, a glowing blue lens top-right, two orange bands."""
    import math
    from PIL import ImageDraw
    im = Image.new("RGBA", (16, 16), K["."])
    d = ImageDraw.Draw(im)
    ax, ay, bx, by = 2.5, 13.5, 10.0, 6.0            # tube axis
    ux, uy = (bx - ax), (by - ay)
    ln = math.hypot(ux, uy)
    ux, uy = ux / ln, uy / ln
    nx, ny = -uy, ux                                    # normal

    def quad(t0, t1, w, color):
        pts = [(ax + ux * ln * t0 + nx * w, ay + uy * ln * t0 + ny * w), (ax + ux * ln * t1 + nx * w, ay + uy * ln * t1 + ny * w),
               (ax + ux * ln * t1 - nx * w, ay + uy * ln * t1 - ny * w), (ax + ux * ln * t0 - nx * w, ay + uy * ln * t0 - ny * w)]
        d.polygon(pts, fill=K[color])

    quad(-0.08, 1.0, 2.9, "d")        # outline
    quad(0.0, 0.98, 2.0, "g")         # body
    quad(0.0, 0.98, 0.9, "G")         # lighter core strip
    # highlight along the upper-left edge
    d.line([(ax + nx * 1.7, ay + ny * 1.7), (ax + ux * ln * 0.95 + nx * 1.7, ay + uy * ln * 0.95 + ny * 1.7)], fill=K["w"])
    quad(0.34, 0.41, 2.05, "o")       # two thin orange bands
    quad(0.64, 0.71, 2.05, "o")
    quad(-0.08, 0.06, 2.3, "d")       # eyepiece cap
    # the lens: a glowing blue blob with a white heart
    cx, cy = 11.8, 4.3
    d.ellipse([cx - 2.8, cy - 2.8, cx + 2.8, cy + 2.8], fill=K["d"])
    d.ellipse([cx - 2.0, cy - 2.0, cx + 2.0, cy + 2.0], fill=K["b"])
    d.ellipse([cx - 1.1, cy - 1.1, cx + 1.1, cy + 1.1], fill=K["B"])
    d.point((int(cx), int(cy)), fill=K["W"])
    return im


REMOTE = [
    "................",
    "......ddd.......",
    ".....dyyd.......",
    "...ddddyddddd...",
    "..dGGGGGGGGGGd..",
    "..dGcccccccGGd..",
    "..dGcccWcccGGd..",
    "..dGGGGGGGGGGd..",
    "..dGbbbGGyyyGd..",
    "..dGbBbGGyOyGd..",
    "..dGbbbGGyyyGd..",
    "..dGGGGGGGGGGd..",
    "..dGGGrrrGGGGd..",
    "..dGGGGGGGGGGd..",
    "...ddddddddddd..",
    "................",
]

PLASMA_ICON = [            # a beam coming down through forked lightning, splashing on the ground
    "......bBWBb.....",
    "......bBWBb.....",
    ".....b.BWB.b....",
    "....b..BWB..b...",
    "...b...BWB...b..",
    "....b..BWB..b...",
    ".....b.BWB.b....",
    "......bBWBb.....",
    "......bBWBb.....",
    "......bBWBb.....",
    ".....bBBWBBb....",
    "....bBBWWWBBb...",
    "..bbBWWWWWWWBbb.",
    ".bBBWWWWWWWWWBBb",
    "..ddddddddddddd.",
    "................",
]

GODLY_ICON = [             # a halo with a pillar of light through it
    "................",
    "....yyyyyyyy....",
    "..yy........yy..",
    ".y....WWWW....y.",
    "..yy..WWWW..yy..",
    "....yyWWWWyy....",
    "......WWWW......",
    "....O.WWWW.O....",
    "...O..WWWW..O...",
    "......WWWW......",
    "..O...WWWW...O..",
    "......WWWW......",
    ".....yWWWWy.....",
    "...yyyWWWWyyy...",
    ".yyyyyyyyyyyyyy.",
    "................",
]

GRIDS = {"remote": REMOTE, "plasma_icon": PLASMA_ICON, "godly_icon": GODLY_ICON}

names = ("laser_designator", "remote", "plasma_icon", "godly_icon")
sheet = Image.new("RGBA", (20 * len(names) - 4, 16), (0, 0, 0, 0))
for i, name in enumerate(names):
    if name in GRIDS:
        grid = GRIDS[name]
        assert len(grid) == 16 and all(len(r) == 16 for r in grid), name
        im = Image.new("RGBA", (16, 16))
        for y, row in enumerate(grid):
            for x, ch in enumerate(row):
                im.putpixel((x, y), K[ch])
    else:
        im = designator()
    im.save(OUT / f"{name}.png")
    sheet.paste(im, (i * 20, 0))
big = Image.new("RGBA", (sheet.width * 20, 16 * 20), (30, 34, 40, 255))
big.alpha_composite(sheet.resize((sheet.width * 20, 16 * 20), Image.NEAREST))
big.convert("RGB").save(OUT.parent.parent.parent.parent.parent / "docs" / "item-textures-preview.png")
print("wrote", *(p.name for p in OUT.glob("*.png")))
