#!/usr/bin/env python3
"""Write mod/src/strike/hu_blocks.rs: every block of the game, by name, with what the Hurricane does to it and the
colours its faces show as it flies (the averages of the game's own textures: the top, the sides and the bottom, as the
block's model puts them on), and how the game tints it. Worked out from the prepared resources of the player's own
Minecraft (horizon-prepare's output: nothing of the game is in this repository but these numbers, as with sh_land.rs's
MATS).

    python3 tools/hu_blocks.py [RESOURCES]    # RESOURCES: .../.local/horizon-client/26.3 (default: $HORIZON_RESOURCES,
                                              # else the Horizon install in ~/Downloads)

What the wind does (`class`): 0 air; 1 water, lava and what grows in water (left alone); 2 the natural ground (dug where
the wind tears the ground up); 3 logs, wood and stems (trees torn up whole); 4 leaves and the like (mushroom caps); 5
plants and what lies on the ground (stripped: grass, flowers, saplings, crops, cane, cactus, bamboo, vines, moss carpets,
mushrooms, snow layers, berry bushes, pumpkins, melons, cocoa, bee nests); 6 light things people put up (fences, gates,
carpets, signs, banners, torches, lanterns, rails, pots, candles: torn away); 7 everything else (buildings: left
standing). Tint: 0 none, 1 the biome's grass, 2 its foliage.
"""
import json, os, sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "mod" / "src" / "strike" / "hu_blocks.rs"
RES = Path(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("HORIZON_RESOURCES", str(Path.home() / "Downloads/horizon-linux-x86_64/.local/horizon-client/26.3")))
A = RES / "assets" / "minecraft"

tags = {k: json.loads(v)["values"] for k, v in json.loads((RES / "block-tags.json").read_text()).items()}


def tag(name, seen=None):
    out = set()
    for v in tags.get(name, []):
        v = v if isinstance(v, str) else v.get("id")
        out |= tag(v[1:]) if v.startswith("#") else {v}
    return out


def bare(n):
    return n.split(":", 1)[-1]


facts = json.loads((RES / "facts.json").read_text())
names = sorted({s[0] for s in facts["states"]})

# ---- what the wind does to each ----------------------------------------------------------------------------------------
FLUID = {"water", "lava", "bubble_column", "seagrass", "tall_seagrass", "kelp", "kelp_plant", "sea_pickle"}
LOGS = {bare(n) for n in tag("minecraft:logs")} | {"mushroom_stem", "bamboo_block", "stripped_bamboo_block"}
LEAVES = {bare(n) for n in tag("minecraft:leaves")} | {"brown_mushroom_block", "red_mushroom_block"}
PLANTS = {bare(n) for t in ("replaceable_by_mushrooms", "replaceable_by_trees", "flowers", "small_flowers", "saplings", "crops",
                             "cave_vines", "corals", "replaceable") for n in tag("minecraft:" + t)}
PLANTS |= {"sugar_cane", "cactus", "cactus_flower", "bamboo", "bamboo_sapling", "sweet_berry_bush", "pumpkin", "melon",
           "cocoa", "bee_nest", "moss_carpet", "pale_moss_carpet", "pink_petals", "wildflowers", "lily_pad", "big_dripleaf",
           "big_dripleaf_stem", "small_dripleaf", "spore_blossom", "mangrove_propagule", "azalea", "flowering_azalea",
           "hanging_roots", "pale_hanging_moss", "snow", "dead_bush", "attached_melon_stem", "attached_pumpkin_stem",
           "melon_stem", "pumpkin_stem", "brown_mushroom", "red_mushroom", "leaf_litter", "firefly_bush", "bush",
           "short_dry_grass", "tall_dry_grass", "glow_lichen", "vine", "twisting_vines", "twisting_vines_plant",
           "weeping_vines", "weeping_vines_plant", "crimson_fungus", "warped_fungus", "crimson_roots", "warped_roots",
           "nether_sprouts", "torchflower_crop", "pitcher_crop", "pitcher_plant", "shelf_mushroom", "red_shrub",
           "golden_dandelion", "resin_clump"}
LIGHT = {bare(n) for t in ("fences", "fence_gates", "wool_carpets", "banners", "all_signs", "rails", "buttons", "pressure_plates",
                            "candles", "flower_pots", "beds") for n in tag("minecraft:" + t)}
LIGHT |= {"torch", "wall_torch", "soul_torch", "soul_wall_torch", "redstone_torch", "redstone_wall_torch", "copper_torch",
          "copper_wall_torch", "lantern", "soul_lantern", "copper_lantern", "scaffolding", "ladder", "lever", "tripwire",
          "tripwire_hook", "string", "cobweb", "flower_pot", "decorated_pot", "hay_block", "target", "bell"}
GROUND = {bare(n) for t in ("dirt", "sand", "base_stone_overworld", "terracotta", "snow", "ice", "mineable/shovel") for n in tag("minecraft:" + t)}
GROUND |= {"gravel", "clay", "snow_block", "powder_snow", "mud", "moss_block", "pale_moss_block", "bedrock", "sandstone",
           "red_sandstone", "mycelium", "podzol", "grass_block", "dirt_path", "farmland", "rooted_dirt", "coarse_dirt",
           "calcite", "dripstone_block", "tuff", "deepslate", "stone", "granite", "diorite", "andesite", "obsidian",
           "magma_block", "packed_ice", "blue_ice", "ice", "soul_sand", "soul_soil", "netherrack", "basalt", "blackstone",
           "end_stone", "amethyst_block", "smooth_basalt", "suspicious_sand", "suspicious_gravel", "packed_mud"}
GROUND |= {bare(n) for n in names if bare(n).endswith("_ore")}


def klass(n):
    b = bare(n)
    if b.endswith("air"):
        return 0
    if b in FLUID:
        return 1
    if b in LOGS:
        return 3
    if b in LEAVES:
        return 4
    if b in PLANTS or b.startswith("potted_"):
        return 6 if b.startswith("potted_") else 5
    if b in LIGHT:
        return 6
    # (stairs, slabs and walls of ground blocks are buildings, as are the blocks themselves once cut)
    if b in GROUND and not any(s in b for s in ("_slab", "_stairs", "_wall", "polished", "brick", "chiseled", "cut_", "smooth_stone")):
        return 2
    return 7


# ---- the colours of its faces --------------------------------------------------------------------------------------------
def load(path):
    p = A / "models" / (path.split(":", 1)[-1] + ".json")
    return json.loads(p.read_text()) if p.exists() else None


def model_of(name):
    p = A / "blockstates" / (bare(name) + ".json")
    if not p.exists():
        return None
    bs = json.loads(p.read_text())
    if "variants" in bs:
        v = bs["variants"]
        key = next((k for k in ("", "axis=y", "half=lower", "type=bottom") if k in v), None)
        if key is None:
            # (a state that faces up and is not lit or waterlogged, if there is one)
            key = next((k for k in v if "facing=up" in k), None) or next(iter(v))
        m = v[key]
    elif "multipart" in bs:
        m = bs["multipart"][0]["apply"]
    else:
        return None
    if isinstance(m, list):
        m = m[0]
    return m.get("model")


def resolve(model):
    """The textures, merged down the parents, and the first elements found."""
    tex, elems, seen = {}, None, 0
    while model and seen < 12:
        seen += 1
        j = load(model)
        if j is None:
            break
        for k, v in j.get("textures", {}).items():
            tex.setdefault(k, v)
        if elems is None and "elements" in j:
            elems = j["elements"]
        model = j.get("parent")
    return tex, elems or []


def ref(tex, v):
    for _ in range(8):
        if isinstance(v, dict):
            v = v.get("sprite") or v.get("texture")
        if v and v.startswith("#"):
            v = tex.get(v[1:])
        else:
            break
    return v


CACHE = {}


def avg(texture):
    if not texture:
        return None
    t = texture.split(":", 1)[-1]
    if t in CACHE:
        return CACHE[t]
    p = A / "textures" / (t + ".png")
    if not p.exists():
        CACHE[t] = None
        return None
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    if h > w:
        im = im.crop((0, 0, w, w))
    raw = im.tobytes()
    px = [raw[i:i + 4] for i in range(0, len(raw), 4) if raw[i + 3] > 127]
    if not px:
        CACHE[t] = None
        return None
    c = tuple(round(sum(q[i] for q in px) / len(px)) for i in range(3))
    CACHE[t] = c
    return c


def faces(name):
    """(top, side, bottom) colours, and whether the faces are tinted."""
    m = model_of(name)
    if not m:
        return None
    tex, elems = resolve(m)
    got, tinted = {}, False
    for e in elems:
        for f, d in e.get("faces", {}).items():
            if f not in got:
                c = avg(ref(tex, d.get("texture")))
                if c:
                    got[f] = c
            tinted |= "tintindex" in d
    fallback = None
    for k in ("all", "side", "texture", "cross", "plant", "particle", "end", "top"):
        fallback = fallback or avg(ref(tex, tex.get(k)))
    up = got.get("up") or got.get("north") or fallback
    side = got.get("north") or got.get("east") or got.get("up") or fallback
    down = got.get("down") or up
    if not (up and side and down):
        return None
    return up, side, down, tinted


GRASS = {"grass_block", "short_grass", "tall_grass", "fern", "large_fern", "potted_fern", "sugar_cane", "bush"}
FOLIAGE = {"vine", "oak_leaves", "jungle_leaves", "acacia_leaves", "dark_oak_leaves", "mangrove_leaves"}
FIXED = {"spruce_leaves": (0x61, 0x99, 0x61), "birch_leaves": (0x80, 0xA7, 0x55), "lily_pad": (0x20, 0x80, 0x30)}

rows, missing = [], []
for n in names:
    b = bare(n)
    k = klass(n)
    if k == 0:
        continue
    f = faces(n)
    if f is None:
        missing.append(n)
        continue
    up, side, down, tinted = f
    tint = 0
    if tinted and b in GRASS:
        tint = 1
    elif tinted and (b in FOLIAGE or b.endswith("_leaves") and b not in FIXED and "poplar" not in b and "cherry" not in b and "azalea" not in b and "pale" not in b):
        tint = 2
    if b in FIXED:
        mul = lambda c: tuple(round(c[i] * FIXED[b][i] / 255) for i in range(3))
        up, side, down = mul(up), mul(side), mul(down)
    # (grass: its sides dirt with the green over it, as near enough the dirt)
    rows.append((n, up, side, down, k, tint))

with open(OUT, "w") as o:
    o.write("// @generated by tools/hu_blocks.py from the prepared resources of the player's own Minecraft: do not edit.\n")
    o.write("//! Every block of the game by name: what the Hurricane does to it (`class`: 1 left alone (water), 2 the natural\n")
    o.write("//! ground, 3 logs, 4 leaves, 5 plants and what lies on the ground, 6 light things people put up, 7 buildings) and\n")
    o.write("//! the colours its faces show (sRGB, the averages of the game's textures as the block's model puts them on: top,\n")
    o.write("//! sides, bottom) and its tint (0 none, 1 the biome's grass, 2 its foliage; the colours then grey, tinted as the\n")
    o.write("//! game tints them). Sorted by name, for `hu_block`'s binary search.\n")
    o.write("pub(super) struct HuBlock {\n    pub name: &'static str,\n    pub top: [u8; 3],\n    pub side: [u8; 3],\n    pub bottom: [u8; 3],\n    pub class: u8,\n    pub tint: u8,\n}\n")
    o.write(f"pub(super) const HU_BLOCKS: [HuBlock; {len(rows)}] = [\n")
    for n, up, side, down, k, tint in rows:
        c = lambda v: f"[{v[0]}, {v[1]}, {v[2]}]"
        o.write(f"    HuBlock {{ name: {json.dumps(n)}, top: {c(up)}, side: {c(side)}, bottom: {c(down)}, class: {k}, tint: {tint} }},\n")
    o.write("];\n")
print(f"wrote {OUT.relative_to(ROOT)}: {len(rows)} blocks; no faces found for {len(missing)}: {' '.join(bare(m) for m in missing)}")
from collections import Counter
print("by class:", dict(sorted(Counter(r[4] for r in rows).items())))
