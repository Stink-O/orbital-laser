#!/usr/bin/env python3
"""For looking at the Hurricane's textured blocks offscreen: a stand-in for the game's block sprite arrays, made from
the player's own prepared resources (nothing of the game goes into the repository), and the sprites of every block as
the fork's atlas.block-sprites would describe them, near enough, for the tests' fake atlas (mod/src/sdk.rs).

    python3 tools/hu_atlas.py OUT_DIR     # writes OUT_DIR/atlas.raw (tools/preview's PREVIEW_ATLAS) and
                                          # OUT_DIR/atlas.txt (the mod tests' HU_ATLAS_JSON)

atlas.raw: `w h layers levels` as four little-endian u32, then each mip level's layers in turn, RGBA8 (the textures'
first frames, gamma-encoded as the game's). atlas.txt: a line a block, `name|down|up|north|south|west|east`, each side
its faces `layer,cutout,tint,u0,v0,duu,duv,dvu,dvv` joined by `;` (tint `-`, `grass`, `foliage`, or `#RRGGBB`).
"""
import struct, sys
from pathlib import Path
from PIL import Image
import hu_blocks as H

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
layers, index = [], {}


def layer(texture):
    t = texture.split(":", 1)[-1]
    if t in index:
        return index[t]
    p = H.A / "textures" / (t + ".png")
    if not p.exists():
        return None
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    if h > w:
        im = im.crop((0, 0, w, w))
    index[t] = len(layers)
    layers.append(im.resize((16, 16), Image.NEAREST))
    return index[t]


# (each side's axes and how a plain model's texture runs across them: docs/mods.md "Block textures in a post pass")
UVS = {"down": (0, 1, 1, 0, 0, -1), "up": (0, 0, 1, 0, 0, 1), "north": (1, 1, -1, 0, 0, -1), "south": (0, 1, 1, 0, 0, -1),
       "west": (0, 1, 1, 0, 0, -1), "east": (1, 1, -1, 0, 0, -1)}
lines = []
for n in sorted({s[0] for s in H.facts["states"]}):
    b = H.bare(n)
    m = H.model_of(n)
    if not m:
        continue
    tex, elems = H.resolve(m)
    sides = []
    for side in ("down", "up", "north", "south", "west", "east"):
        faces = []
        for e in elems:
            d = e.get("faces", {}).get(side)
            if not d:
                continue
            # (whole faces on the side's plane only, as the game's own answer has them first)
            fr, to = e.get("from", [0, 0, 0]), e.get("to", [16, 16, 16])
            if side in ("down", "up") and (fr[0] > 0 or to[0] < 16 or fr[2] > 0 or to[2] < 16) or side not in ("down", "up") and (fr[1] > 0 or to[1] < 16):
                continue
            ly = layer(H.ref(tex, d.get("texture")) or "")
            if ly is None:
                continue
            tint = "-"
            if "tintindex" in d:
                tint = "grass" if b in H.GRASS else "#619961" if b == "spruce_leaves" else "#80a755" if b == "birch_leaves" else "foliage"
            cut = "1" if b.endswith("_leaves") or "glass" in b else "0"
            faces.append(f"{ly},{cut},{tint}," + ",".join(str(v) for v in UVS[side]))
        sides.append(";".join(faces))
    lines.append(n + "|" + "|".join(sides))
(OUT / "atlas.txt").write_text("\n".join(lines) + "\n")
levels = 5
with open(OUT / "atlas.raw", "wb") as f:
    f.write(struct.pack("<4I", 16, 16, len(layers), levels))
    for lv in range(levels):
        s = 16 >> lv
        for im in layers:
            f.write((im if s == 16 else im.resize((s, s), Image.BOX)).tobytes())
print(f"{len(layers)} textures, {len(lines)} blocks -> {OUT}")
