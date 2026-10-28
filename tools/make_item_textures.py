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
    "k": (0, 0, 0, 255),          # the event horizon
    "v": (88, 40, 150, 255),      # dark violet
    "m": (63, 224, 90, 255),      # mothership green
    "M": (24, 120, 44, 255),      # dark green
    "h": (34, 40, 54, 255),       # hull
    "e": (226, 58, 40, 255),      # the downfall's red lights
    "E": (120, 22, 16, 255),      # dark red
    "u": (77, 124, 255, 255),     # the planet killer's blue
    "U": (175, 205, 255, 255),    # its pale blue
    "n": (24, 40, 110, 255),      # its deep blue
    "q": (190, 120, 255, 255),    # the crystal bloom's violet
    "Q": (238, 214, 255, 255),    # its pale facets
    "x": (96, 44, 168, 255),      # its deep violet
    "z": (255, 120, 210, 255),    # its rose
    "Z": (110, 220, 255, 255),    # its ice blue
    "s": (210, 162, 87, 255),     # the sinkhole's dust
    "S": (236, 214, 170, 255),    # its pale dust
    "t": (92, 150, 52, 255),      # grass
    "T": (60, 104, 34, 255),      # dark grass
    "j": (118, 82, 52, 255),      # dirt
    "J": (78, 54, 36, 255),       # dark dirt
    "l": (112, 112, 112, 255),    # stone
    "L": (70, 70, 74, 255),       # dark stone
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

BLACKHOLE_ICON = [         # a black hole edge-on: the disk across its middle, its far side bent up over the top and under
    "................",
    "................",
    ".....vppppv.....",
    "....pOyyyyOp....",
    "...pOkkkkkkOp...",
    "..vOkkkkkkkkOv..",
    "..pykkkkkkkkyp..",
    ".OOyWkkkkkkWyOO.",
    "oOWWWWWWWWWWWWOo",
    ".oOyyWWWWWWyyOo.",
    "..pOkkkkkkkkOp..",
    "...pOkkkkkkOp...",
    "....pOyyyyOp....",
    ".....vppppv.....",
    "................",
    "................",
]

def meteor_icon():
    """A burning rock coming down from the top right: a flame trail behind it, its leading edge white-hot."""
    from PIL import ImageDraw
    im = Image.new("RGBA", (16, 16), K["."])
    d = ImageDraw.Draw(im)
    cx, cy, r = 5.5, 10.0, 4.0
    for w, c in ((3.6, "r"), (2.6, "o"), (1.6, "O"), (0.7, "y")):      # the trail, widest and reddest outside
        d.polygon([(cx - w * 0.7, cy - w * 0.7), (cx + w * 0.7, cy + w * 0.7), (15.5, 0.5)], fill=K[c])
    d.ellipse([cx - r - 0.5, cy - r - 0.5, cx + r + 0.5, cy + r + 0.5], fill=K["d"])
    d.ellipse([cx - r + 0.5, cy - r + 0.5, cx + r - 0.5, cy + r - 0.5], fill=K["g"])
    d.ellipse([cx - 2.0, cy - 2.6, cx + 0.6, cy - 0.4], fill=K["G"])     # a lighter face
    d.arc([cx - r - 0.5, cy - r - 0.5, cx + r + 0.5, cy + r + 0.5], 100, 190, fill=K["O"])  # the leading edge, glowing
    d.arc([cx - r + 0.5, cy - r + 0.5, cx + r - 0.5, cy + r - 0.5], 115, 175, fill=K["y"])
    return im



def mothership_icon():
    """The ship from below and a little behind: a long slab of dark metal across the top, its edge catching the light,
    a deck stepped down under it with a green seam along it and the eye in it, and its green beam coming down from the
    eye onto the ground."""
    from PIL import ImageDraw
    im = Image.new("RGBA", (16, 16), K["."])
    d = ImageDraw.Draw(im)
    d.rectangle([0, 1, 15, 5], fill=K["G"])                       # the slab, its lit edge
    d.rectangle([1, 2, 14, 5], fill=K["h"])
    d.line([(1, 1), (14, 1)], fill=K["w"])
    d.rectangle([3, 5, 12, 6], fill=K["g"])                       # the deck stepped down under it
    d.line([(2, 4), (13, 4)], fill=K["M"])                        # a seam of light along it
    d.point((1, 3), fill=K["m"]); d.point((14, 3), fill=K["m"])  # running lights
    d.rectangle([7, 7, 8, 13], fill=K["m"])                       # the beam, white down its middle
    d.line([(8, 7), (8, 13)], fill=K["W"])
    d.rectangle([6, 6, 9, 6], fill=K["m"])                        # the eye
    d.point((7, 6), fill=K["W"]); d.point((8, 6), fill=K["W"])
    d.line([(4, 14), (11, 14)], fill=K["o"])                      # where it touches down, the ground molten
    d.line([(5, 13), (10, 13)], fill=K["O"])
    d.line([(7, 13), (8, 14)], fill=K["W"]); d.point((7, 14), fill=K["y"]); d.point((8, 13), fill=K["W"])
    d.point((3, 12), fill=K["o"]); d.point((12, 12), fill=K["o"])
    return im


DOWNFALL_ICON = [          # the mothership coming down stern first, burning, smoke streaming up off it; the black hole
    ".............gG.",    # tearing out of its stern
    "...........gGg..",
    "..........gGg.gG",
    ".........gGg.gG.",
    "........dddgdGg.",
    "......ddGGGdGdd.",
    ".....dhhhhOyGhd.",
    "....dhhhhhhOhhd.",
    "...dhhEehhhhhd..",
    "..dhhEEhhhhhd...",
    ".vphhhhhhhdd....",
    "vpkpphhhdd......",
    "pkkkpdd.........",
    "pkkkp...........",
    "vpkpv...........",
    ".vpv............",
]

def planetkiller_icon():
    """Two towers either side, their beams arcing up and over onto a white star high up, and one beam from it down
    onto the ground, white down its middle, the ground molten where it lands."""
    from PIL import ImageDraw
    im = Image.new("RGBA", (16, 16), K["."])
    d = ImageDraw.Draw(im)
    for x0, x1 in ((0, 2), (13, 15)):                             # the towers, dark, their crowns lit
        d.polygon([(x0, 14), (x1, 14), ((x0 + x1) // 2 + (1 if x0 else 0), 7)], fill=K["G"])
        d.line([((x0 + x1) // 2 + (1 if x0 else 0), 13), ((x0 + x1) // 2 + (1 if x0 else 0), 9)], fill=K["u"])
        d.point(((x0 + x1) // 2 + (1 if x0 else 0), 6), fill=K["U"])
    for pts in (((1, 6), (2, 3), (4, 1), (6, 2)), ((14, 6), (13, 3), (11, 1), (9, 2))):   # their beams, arcing over
        d.line(pts, fill=K["u"])
    d.rectangle([7, 4, 8, 13], fill=K["W"])                       # the one beam, white-hot in its blue sheath
    d.line([(6, 5), (6, 13)], fill=K["u"]); d.line([(9, 5), (9, 13)], fill=K["u"])
    d.rectangle([6, 2, 9, 3], fill=K["U"])                        # the star where they meet
    d.point((7, 1), fill=K["U"]); d.point((8, 1), fill=K["U"])
    d.rectangle([7, 2, 8, 3], fill=K["W"])
    d.line([(3, 14), (12, 14)], fill=K["o"])                      # where it lands, the ground molten
    d.line([(5, 13), (10, 13)], fill=K["O"])
    d.line([(6, 14), (9, 14)], fill=K["y"]); d.line([(7, 13), (8, 13)], fill=K["W"])
    d.line([(0, 15), (15, 15)], fill=K["n"]); d.point((2, 15), fill=K["E"]); d.point((13, 15), fill=K["E"])
    return im


CRYSTALBLOOM_ICON = [     # a cluster of crystal spires bursting up out of cracked ground, the tallest violet, a rose one leaning
    ".......Q........",    # left, an ice one right, a glint over them
    "......QqQ.......",
    "......qQx.......",
    "..z...qQx...W...",
    ".zQz..qQx..ZW...",
    ".zQx..qQx..ZQZ..",
    "..zQx.qQx.ZQx...",
    "..zQx.qQxZQx....",
    "...zQxqQxQx.....",
    "...zQxqQxQx.....",
    "....zxqQxx......",
    "...ddzqQxdd.....",
    "..dgdQdgddQdd...",
    ".dgdqgdggdqgdd..",
    "dgggdggdgggdggd.",
    "................",
]

SINKHOLE_ICON = [        # the land caving in: a dark pit, its walls in strata, a slab tipping into it, dust over it
    "......S..S......",
    "....SsSsSsS.....",
    "...sSs.s.sSs....",
    "....s.....s.....",
    "................",
    "tTtTtt.....ttTtt",
    "jjJjjtT...Ttjjjj",
    "jJjjl.tt..jl.jJj",
    "llLl..jjt.Lll.lL",
    "lLl...Jj...lLl.l",
    "Ll.....l....Lll.",
    "lL..........lLL.",
    "L.....dd.....Ll.",
    "l....dkkd.....L.",
    "L...dkkkkd....L.",
    "...dkkkkkkd.....",
]

GRIDS = {"sinkhole_icon": SINKHOLE_ICON, "remote": REMOTE, "plasma_icon": PLASMA_ICON, "godly_icon": GODLY_ICON, "blackhole_icon": BLACKHOLE_ICON,
         "downfall_icon": DOWNFALL_ICON, "crystalbloom_icon": CRYSTALBLOOM_ICON}
DRAWN = {"laser_designator": designator, "meteor_icon": meteor_icon, "mothership_icon": mothership_icon,
         "planetkiller_icon": planetkiller_icon}

names = ("laser_designator", "remote", "plasma_icon", "godly_icon", "blackhole_icon", "meteor_icon", "mothership_icon", "downfall_icon",
         "planetkiller_icon", "crystalbloom_icon", "sinkhole_icon")
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
        im = DRAWN[name]()
    im.save(OUT / f"{name}.png")
    sheet.paste(im, (i * 20, 0))
big = Image.new("RGBA", (sheet.width * 20, 16 * 20), (30, 34, 40, 255))
big.alpha_composite(sheet.resize((sheet.width * 20, 16 * 20), Image.NEAREST))
big.convert("RGB").save(OUT.parent.parent.parent.parent.parent / "docs" / "item-textures-preview.png")
print("wrote", *(p.name for p in OUT.glob("*.png")))
