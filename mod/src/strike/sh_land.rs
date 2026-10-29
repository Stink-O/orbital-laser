//! The sinkhole's land as it really is: the blocks round the top of every column of the pit, read from the world
//! (`world.read-columns`, columns.rs) as it starts, worked out a few thousand columns a tick into what the pass draws each
//! falling slab with (its ground's height, the blocks on top, under them and deeper, the snow on it, the trunk and the
//! leaves of a tree standing on it), and each column's top, which the dig clears up to (nothing is left hanging over the
//! pit, however high the mountain it cut through).
//!
//! What the pass reads (render.set-data, shaders/sinkhole.wgsl's sh_col and sh_mat): from SH_MAT the materials, two words
//! each (`mat_words`); from SH_GRID a square of SH_GW by SH_GW columns round the target (x then z, from the target's less
//! SH_G), three words a column (`ColInfo::words`). Keep the two in step.
use super::sinkhole::ShGeo;
use std::rc::Rc;

/// The square of columns round the target the land is read over: SH_G either side (the rim at its widest, and more).
pub(super) const SH_G: i32 = 134;
pub(super) const SH_GW: usize = (2 * SH_G + 1) as usize;
/// Where the materials and the columns are in the pass's data.
pub(super) const SH_MAT: usize = 7936;
pub(super) const SH_GRID: usize = 8192;
/// How deep under each column's top it is read, and how high (just the top's own air).
pub(super) const READ_BELOW: u32 = 24;
pub(super) const READ_ABOVE: u32 = 1;
/// The rows of the square asked about in a query (six queries for all of it, a tick each), and the columns worked out
/// a tick.
pub(super) const READ_ROWS: usize = 45;
pub(super) const PER_TICK: usize = 3000;

/// What a block is to a slab: nothing (air, and what is too thin to show: grass, flowers, torches, fences), the snow
/// lying on the ground, leaves, a trunk, or the ground.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(super) enum Class {
    Air,
    Snow,
    Leaves,
    Log,
    Ground,
    /// Water over the ground: a slab carries the bed under it (the water is not drawn falling), and no crack runs
    /// over it.
    Water,
}

/// The materials: top colour, side colour (sRGB: the game's own textures' averages), how much each block varies, its
/// kind (0 plain, 1 leaves, 2 a log, 3 water, 4 grassy: its sides the second colour with a fringe of the first along the
/// top) and its tint (TINT_GRASS or TINT_FOLIAGE: its first colour, grey, tinted by the column's biome as the game tints
/// it; spruce and birch leaves have their fixed tints in).
pub(super) const TINT_GRASS: u8 = 1 << 3;
pub(super) const TINT_FOLIAGE: u8 = 2 << 3;
pub(super) const MATS: [([u8; 3], [u8; 3], f32, u8); 63] = [
    ([122, 112, 100], [122, 112, 100], 0.18, 0),             // 0 anything else
    ([147, 147, 147], [134, 96, 67], 0.14, 4 | TINT_GRASS),  // 1 grass block
    ([134, 96, 67], [134, 96, 67], 0.18, 0),                 // 2 dirt
    ([119, 85, 59], [119, 85, 59], 0.22, 0),                 // 3 coarse dirt
    ([91, 63, 24], [134, 96, 67], 0.16, 4),                  // 4 podzol
    ([144, 103, 76], [144, 103, 76], 0.18, 0),               // 5 rooted dirt
    ([60, 57, 60], [60, 57, 60], 0.12, 0),                   // 6 mud
    ([148, 121, 65], [134, 96, 67], 0.07, 4),                // 7 dirt path
    ([90, 50, 22], [134, 96, 67], 0.16, 4),                  // 8 farmland
    ([111, 98, 101], [134, 96, 67], 0.07, 4),                // 9 mycelium
    ([249, 254, 254], [240, 247, 249], 0.02, 0),             // 10 snow
    ([145, 183, 253], [145, 183, 253], 0.05, 0),             // 11 ice
    ([125, 125, 125], [125, 125, 125], 0.09, 0),             // 12 stone
    ([127, 127, 127], [127, 127, 127], 0.23, 0),             // 13 cobblestone
    ([136, 136, 136], [136, 136, 136], 0.12, 0),             // 14 andesite
    ([188, 188, 188], [188, 188, 188], 0.18, 0),             // 15 diorite
    ([149, 103, 85], [149, 103, 85], 0.18, 0),               // 16 granite
    ([108, 109, 102], [108, 109, 102], 0.19, 0),             // 17 tuff
    ([80, 80, 82], [80, 80, 82], 0.26, 0),                   // 18 deepslate
    ([223, 224, 220], [223, 224, 220], 0.09, 0),             // 19 calcite
    ([131, 127, 126], [131, 127, 126], 0.13, 0),             // 20 gravel
    ([219, 207, 163], [219, 207, 163], 0.05, 0),             // 21 sand
    ([190, 102, 33], [190, 102, 33], 0.06, 0),               // 22 red sand
    ([160, 166, 179], [160, 166, 179], 0.04, 0),             // 23 clay
    ([152, 94, 67], [152, 94, 67], 0.05, 0),                 // 24 terracotta
    ([46, 84, 182], [46, 84, 182], 0.1, 3),                  // 25 water
    ([216, 104, 26], [216, 104, 26], 0.19, 0),               // 26 lava
    ([89, 109, 45], [89, 109, 45], 0.15, 0),                 // 27 moss
    ([151, 121, 73], [109, 85, 50], 0.24, 2),                // 28 oak log
    ([108, 80, 46], [58, 37, 16], 0.2, 2),                   // 29 spruce log
    ([193, 179, 135], [216, 215, 210], 0.25, 2),             // 30 birch log
    ([67, 45, 22], [60, 46, 26], 0.18, 2),                   // 31 dark oak log
    ([149, 109, 70], [85, 67, 25], 0.19, 2),                 // 32 other logs (jungle's)
    ([144, 144, 144], [144, 144, 144], 0.22, 1 | TINT_FOLIAGE), // 33 oak leaves
    ([48, 76, 48], [48, 76, 48], 0.27, 1),                   // 34 spruce leaves (#619961)
    ([65, 85, 43], [65, 85, 43], 0.16, 1),                   // 35 birch leaves (#80a755)
    ([150, 150, 148], [150, 150, 148], 0.18, 1 | TINT_FOLIAGE), // 36 other tinted leaves
    ([229, 172, 194], [229, 172, 194], 0.17, 1),             // 37 cherry leaves
    ([162, 130, 78], [162, 130, 78], 0.19, 0),               // 38 oak planks
    ([114, 84, 48], [114, 84, 48], 0.16, 0),                 // 39 dark planks
    ([122, 121, 122], [122, 121, 122], 0.15, 0),             // 40 stone bricks
    ([150, 97, 83], [150, 97, 83], 0.19, 0),                 // 41 bricks
    ([175, 213, 219], [175, 213, 219], 0.12, 0),             // 42 glass
    ([166, 136, 38], [166, 136, 38], 0.18, 0),               // 43 hay
    ([85, 85, 85], [85, 85, 85], 0.4, 0),                    // 44 bedrock
    ([42, 35, 40], [42, 35, 40], 0.3, 0),                    // 45 blackstone
    ([73, 72, 77], [73, 72, 77], 0.22, 0),                   // 46 basalt
    ([97, 38, 38], [97, 38, 38], 0.24, 0),                   // 47 netherrack
    ([15, 10, 24], [15, 10, 24], 0.3, 0),                    // 48 obsidian
    ([216, 203, 155], [216, 203, 155], 0.08, 0),             // 49 sandstone
    ([186, 99, 29], [186, 99, 29], 0.12, 0),                 // 50 red sandstone
    ([142, 106, 79], [142, 106, 79], 0.09, 0),               // 51 packed mud
    ([158, 158, 158], [158, 158, 158], 0.11, 0),             // 52 smooth stone
    ([110, 118, 94], [110, 118, 94], 0.21, 0),               // 53 mossy cobblestone
    ([233, 236, 236], [233, 236, 236], 0.05, 0),             // 54 wool, concrete and the like
    ([90, 114, 44], [90, 114, 44], 0.21, 1),                 // 55 azalea leaves
    ([188, 86, 23], [188, 86, 23], 0.24, 1),                 // 56 orange poplar leaves
    ([153, 44, 39], [153, 44, 39], 0.26, 1),                 // 57 red poplar leaves
    ([214, 133, 40], [214, 133, 40], 0.23, 1),               // 58 yellow poplar leaves
    ([116, 121, 114], [116, 121, 114], 0.26, 1),             // 59 pale oak leaves
    ([136, 122, 110], [79, 60, 42], 0.2, 2),                 // 60 poplar log
    ([198, 189, 187], [87, 77, 75], 0.25, 2),                // 61 pale oak log
    ([185, 141, 137], [54, 33, 44], 0.24, 2),                // 62 cherry log
];

/// A block's material and class, by its name (`minecraft:snow`).
pub(super) fn material(name: &str) -> (u8, Class) {
    use Class::*;
    let n = name.strip_prefix("minecraft:").unwrap_or(name);
    let has = |s: &str| n.contains(s);
    let ends = |s: &str| n.ends_with(s);
    match n {
        "air" | "cave_air" | "void_air" => return (0, Air),
        "snow" => return (10, Snow),
        "grass_block" => return (1, Ground),
        "dirt" => return (2, Ground),
        "coarse_dirt" => return (3, Ground),
        "podzol" => return (4, Ground),
        "rooted_dirt" => return (5, Ground),
        "mud" => return (6, Ground),
        "dirt_path" => return (7, Ground),
        "farmland" => return (8, Ground),
        "mycelium" => return (9, Ground),
        "snow_block" | "powder_snow" => return (10, Ground),
        "stone" | "infested_stone" => return (12, Ground),
        "andesite" | "polished_andesite" => return (14, Ground),
        "diorite" | "polished_diorite" => return (15, Ground),
        "granite" | "polished_granite" => return (16, Ground),
        "tuff" => return (17, Ground),
        "calcite" | "dripstone_block" => return (19, Ground),
        "gravel" => return (20, Ground),
        "sand" | "suspicious_sand" => return (21, Ground),
        "red_sand" => return (22, Ground),
        "clay" => return (23, Ground),
        "water" | "bubble_column" => return (25, Water),
        "lava" | "magma_block" => return (26, Ground),
        "moss_block" => return (27, Ground),
        "oak_log" | "oak_wood" => return (28, Log),
        "spruce_log" | "spruce_wood" => return (29, Log),
        "birch_log" | "birch_wood" => return (30, Log),
        "dark_oak_log" | "dark_oak_wood" => return (31, Log),
        "oak_leaves" => return (33, Leaves),
        "spruce_leaves" => return (34, Leaves),
        "birch_leaves" => return (35, Leaves),
        "cherry_leaves" => return (37, Leaves),
        "orange_poplar_leaves" => return (56, Leaves),
        "red_poplar_leaves" => return (57, Leaves),
        "yellow_poplar_leaves" => return (58, Leaves),
        "pale_oak_leaves" => return (59, Leaves),
        "poplar_log" | "poplar_wood" => return (60, Log),
        "pale_oak_log" | "pale_oak_wood" => return (61, Log),
        "cherry_log" | "cherry_wood" => return (62, Log),
        "azalea_leaves" | "flowering_azalea_leaves" => return (55, Leaves),
        "hay_block" => return (43, Ground),
        "bedrock" => return (44, Ground),
        "obsidian" | "crying_obsidian" => return (48, Ground),
        "smooth_stone" => return (52, Ground),
        "mossy_cobblestone" => return (53, Ground),
        "packed_mud" | "mud_bricks" => return (51, Ground),
        _ => {}
    }
    // (what is too thin or small to show on a slab: plants, crops, carpets, torches, fences, doors, signs and the like)
    const THIN: [&str; 40] = [
        "grass", "fern", "flower", "tulip", "orchid", "allium", "bluet", "daisy", "poppy", "dandelion", "cornflower",
        "lily", "rose", "peony", "lilac", "bush", "sapling", "mushroom", "petals", "litter", "vine", "lichen", "carpet",
        "torch", "lantern", "fence", "door", "sign", "rail", "button", "plate", "pane", "bars", "ladder", "wheat",
        "carrots", "potatoes", "beetroots", "sugar_cane", "kelp",
    ];
    if has("leaves") {
        return (36, Leaves);
    }
    if ends("_log") || ends("_wood") || ends("_stem") || ends("_hyphae") {
        return (32, Log);
    }
    if !n.ends_with("_block") && (THIN.iter().any(|t| has(t)) || n == "seagrass" || n == "tall_seagrass" || ends("_bed") || n == "bell") {
        return (0, Air);
    }
    let m = if has("ice") {
        11
    } else if has("deepslate") {
        18
    } else if has("blackstone") {
        45
    } else if has("basalt") {
        46
    } else if has("netherrack") || has("nylium") {
        47
    } else if has("red_sandstone") {
        50
    } else if has("sandstone") {
        49
    } else if has("terracotta") {
        24
    } else if has("cobblestone") {
        13
    } else if has("stone_brick") || has("stone_stairs") || has("stone_slab") {
        40
    } else if has("brick") {
        41
    } else if has("glass") {
        42
    } else if has("spruce") || has("dark_oak") || has("mangrove") {
        39
    } else if has("planks") || has("oak") || has("birch") || has("jungle") || has("acacia") || has("bamboo") || has("cherry") {
        38
    } else if has("ore") || has("stone") {
        12
    } else if has("wool") || has("concrete") || has("quartz") {
        54
    } else if has("dirt") || has("mud") {
        2
    } else if has("moss") {
        27
    } else if has("snow") {
        10
    } else {
        0
    };
    (m, Ground)
}

/// The materials as the pass reads them: two words each, the top colour and kind, the side colour and how much each
/// block varies.
pub(super) fn mat_words() -> Vec<u32> {
    let mut w = Vec::with_capacity(MATS.len() * 2);
    for (top, side, var, kind) in MATS {
        w.push(u32::from(top[0]) | u32::from(top[1]) << 8 | u32::from(top[2]) << 16 | u32::from(kind) << 24);
        w.push(u32::from(side[0]) | u32::from(side[1]) << 8 | u32::from(side[2]) << 16 | ((var * 255.0) as u32) << 24);
    }
    w
}

/// A colour (0xRRGGBB) in 16 bits, 5-6-5 (0 kept 0: not known).
pub(super) fn rgb565(c: u32) -> u32 {
    if c == 0 {
        return 0;
    }
    let (r, g, b) = ((c >> 16) & 255, (c >> 8) & 255, c & 255);
    ((r >> 3) << 11 | (g >> 2) << 5 | (b >> 3)).max(1)
}
/// And back (for the tests).
#[cfg(test)]
pub(super) fn rgb888(c: u32) -> u32 {
    if c == 0 {
        return 0;
    }
    let (r, g, b) = ((c >> 11) & 31, (c >> 5) & 63, c & 31);
    (r << 3 | r >> 2) << 16 | (g << 2 | g >> 4) << 8 | (b << 3 | b >> 2)
}

/// A column as a slab carries it: its ground's top (one above its highest ground block, from the target's ground), the
/// ground block's material, the one under it and the one deeper; snow lying on it; the trunk standing on it (its
/// material and its top, over the ground block) and the leaves over it (their material, lowest and highest).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct ColInfo {
    pub h: i32,
    pub top: u8,
    pub under: u8,
    pub deep: u8,
    pub snow: bool,
    pub log: u8,
    pub log_top: u8,
    pub leaf: u8,
    pub leaf_lo: u8,
    pub leaf_hi: u8,
    pub wet: bool,
    /// The biome's grass and foliage tints there (0xRRGGBB; 0 not known).
    pub grass: u32,
    pub foliage: u32,
}
impl ColInfo {
    /// Its two words for the pass, it being slab `slab`'s (none: no slab's): see shaders/sinkhole.wgsl's sh_col.
    pub fn words(&self, slab: Option<usize>) -> [u32; 3] {
        let h = (self.h.clamp(-256, 255) + 256) as u32;
        let s = slab.map_or(0, |k| (k as u32 + 1).min(511));
        let a = h | u32::from(self.top & 63) << 9 | u32::from(self.under & 63) << 15 | s << 21 | u32::from(self.snow) << 30 | 1 << 31;
        let b = u32::from(self.deep & 63)
            | u32::from(self.log & 63) << 6
            | u32::from(self.log_top.min(15)) << 12
            | u32::from(self.leaf & 63) << 16
            | u32::from(self.leaf_lo.min(15)) << 22
            | u32::from(self.leaf_hi.min(15)) << 26
            | u32::from(self.wet) << 30;
        [a, b, rgb565(self.grass) | rgb565(self.foliage) << 16]
    }
    /// The words back (the pass's reading of them, for the tests): the column and its slab.
    #[cfg(test)]
    pub fn from_words(w: [u32; 3]) -> Option<(ColInfo, Option<usize>)> {
        if w[0] >> 31 == 0 {
            return None;
        }
        let (a, b) = (w[0], w[1]);
        let s = (a >> 21) & 511;
        let c = ColInfo {
            h: (a & 511) as i32 - 256,
            top: ((a >> 9) & 63) as u8,
            under: ((a >> 15) & 63) as u8,
            snow: (a >> 30) & 1 == 1,
            deep: (b & 63) as u8,
            log: ((b >> 6) & 63) as u8,
            log_top: ((b >> 12) & 15) as u8,
            leaf: ((b >> 16) & 63) as u8,
            leaf_lo: ((b >> 22) & 15) as u8,
            leaf_hi: ((b >> 26) & 15) as u8,
            wet: (b >> 30) & 1 == 1,
            grass: rgb888(w[2] & 0xffff),
            foliage: rgb888(w[2] >> 16),
        };
        Some((c, (s > 0).then(|| s as usize - 1)))
    }
    /// The highest block of it a slab draws (from the target's ground): its ground, its trunk or its leaves.
    pub fn highest(&self) -> i32 {
        let g = self.h - 1;
        let mut top = g;
        if self.log > 0 {
            top = top.max(g + i32::from(self.log_top));
        }
        if self.leaf > 0 {
            top = top.max(g + i32::from(self.leaf_hi));
        }
        top
    }
}

/// A column worked out from its blocks (`stack`, bottom first, its top `base`: one above its highest block that is not
/// air; `below` of them under it), each block's material and class given by `mats`, `gy` the target's ground: none for
/// one with nothing in it.
pub(super) fn col_info(stack: &[u16], base: i32, below: i32, mats: &[(u8, Class)], gy: i32) -> Option<ColInfo> {
    let y0 = base - below;
    let mut c = ColInfo::default();
    let (mut leaf_lo, mut leaf_hi, mut log_hi) = (i32::MAX, i32::MIN, i32::MIN);
    let mut snow = false;
    let mut ground = None;
    for i in (0..stack.len()).rev() {
        let (m, class) = mats.get(stack[i] as usize).copied().unwrap_or((0, Class::Ground));
        let y = y0 + i as i32;
        match class {
            Class::Air => {}
            Class::Snow => snow = true,
            Class::Water => c.wet = true,
            Class::Leaves => {
                c.leaf = m;
                leaf_lo = leaf_lo.min(y);
                leaf_hi = leaf_hi.max(y);
            }
            Class::Log => {
                c.log = m;
                log_hi = log_hi.max(y);
            }
            Class::Ground => {
                ground = Some(i);
                break;
            }
        }
    }
    // (a tree too tall for what was read: its ground taken as the lowest block of it)
    let gi = match ground {
        Some(i) => i,
        None => {
            if c.log == 0 && c.leaf == 0 {
                return None;
            }
            0
        }
    };
    let gyb = y0 + gi as i32;
    let mat = |i: usize| mats.get(stack[i] as usize).filter(|m| m.1 == Class::Ground).map_or(0, |m| m.0);
    c.top = if ground.is_some() { mat(gi) } else { c.log.max(c.leaf) };
    c.under = if gi >= 1 { mat(gi - 1) } else { c.top };
    c.deep = if gi >= 4 { mat(gi - 4) } else { c.under };
    if c.under == 0 {
        c.under = c.top;
    }
    if c.deep == 0 {
        c.deep = c.under;
    }
    c.h = gyb + 1 - gy;
    // (snow lying on the ground block; snow on leaves alone is left to them)
    c.snow = snow && stack.get(gi + 1).is_some_and(|&b| mats.get(b as usize).is_some_and(|m| m.1 == Class::Snow));
    if c.log > 0 {
        c.log_top = (log_hi - gyb).clamp(1, 15) as u8;
    }
    if c.leaf > 0 {
        c.leaf_lo = (leaf_lo - gyb).clamp(1, 15) as u8;
        c.leaf_hi = (leaf_hi - gyb).clamp(1, 15) as u8;
    }
    Some(c)
}

/// The land worked out so far: the pass's words for the square of columns, each column's top (the dig clears up to it:
/// i32::MIN where it is not known) and each slab's bounds (the columns it covers, lowest first, and the heights its
/// ground and what stands on it reach, from the target's ground).
pub(super) struct Land {
    pub words: Vec<u32>,
    pub top: Vec<i32>,
    pub bounds: Vec<[i32; 6]>,
    pub lowest: Vec<i32>,
    /// The columns the world could not read (their chunks not loaded yet: asked again), and how many of each slab's.
    pub missing: Vec<(i32, i32)>,
    pub missing_n: Vec<u32>,
    /// How far the middle's slabs went down before they fall (the give and the sag; none with the terrain off).
    pub give: i32,
}
impl Land {
    pub fn new(slabs: usize, give: i32) -> Self {
        Land {
            words: vec![0; SH_GW * SH_GW * 3],
            top: vec![i32::MIN; SH_GW * SH_GW],
            bounds: vec![[i32::MAX, i32::MAX, i32::MIN, i32::MIN, i32::MAX, i32::MIN]; slabs],
            lowest: vec![i32::MAX; slabs],
            missing: Vec::new(),
            missing_n: vec![0; slabs],
            give,
        }
    }
    /// Column (x, z)'s index in the square round the target (bx, bz), if it is in it.
    pub fn index(bx: i32, bz: i32, x: i32, z: i32) -> Option<usize> {
        let (i, k) = (x - bx + SH_G, z - bz + SH_G);
        (i >= 0 && k >= 0 && (i as usize) < SH_GW && (k as usize) < SH_GW).then(|| k as usize * SH_GW + i as usize)
    }
    /// Column (x, z)'s top, if it was read.
    pub fn top_at(&self, bx: i32, bz: i32, x: i32, z: i32) -> Option<i32> {
        Land::index(bx, bz, x, z).map(|i| self.top[i]).filter(|t| *t != i32::MIN)
    }
    /// Column (x, z)'s ground (one above its highest ground block), if it was read.
    pub fn ground_at(&self, bx: i32, bz: i32, x: i32, z: i32, gy: i32) -> Option<i32> {
        let i = Land::index(bx, bz, x, z)?;
        let a = self.words[3 * i];
        (a >> 31 == 1).then(|| (a & 511) as i32 - 256 + gy)
    }
    /// Column (x, z), worked out: kept, and counted into its slab's bounds.
    pub fn put(&mut self, bx: i32, bz: i32, x: i32, z: i32, top: i32, c: Option<ColInfo>, slab: Option<usize>) {
        let Some(i) = Land::index(bx, bz, x, z) else { return };
        self.top[i] = top;
        let Some(c) = c else { return };
        let w = c.words(slab);
        self.words[3 * i..3 * i + 3].copy_from_slice(&w);
        if let Some(k) = slab {
            let (ci, ck) = ((i % SH_GW) as i32, (i / SH_GW) as i32);
            let b = &mut self.bounds[k];
            b[0] = b[0].min(ci);
            b[1] = b[1].min(ck);
            b[2] = b[2].max(ci);
            b[3] = b[3].max(ck);
            b[5] = b[5].max(c.highest() + 1);
            self.lowest[k] = self.lowest[k].min(c.h);
        }
    }
}

/// The columns of the square the land is read over, in rows z0..z1 of it: those inside the rim, and a little past it.
pub(super) fn read_columns(g: &ShGeo, bx: i32, bz: i32, k0: usize, k1: usize) -> Vec<(i32, i32)> {
    const IN2: f64 = (super::sinkhole::SH_R * 0.84) * (super::sinkhole::SH_R * 0.84);
    const OUT2: f64 = (super::sinkhole::SH_R * 1.16 + 1.0) * (super::sinkhole::SH_R * 1.16 + 1.0);
    let mut out = Vec::new();
    for k in k0..k1.min(SH_GW) {
        let z = bz - SH_G + k as i32;
        let dz = f64::from(z - bz);
        for i in 0..SH_GW {
            let x = bx - SH_G + i as i32;
            let dx = f64::from(x - bx);
            let r2 = dx * dx + dz * dz;
            // (well inside the narrowest the rim gets, or past the widest: no need to work out the rim there)
            if r2 > OUT2 {
                continue;
            }
            if r2 > IN2 && r2.sqrt() > g.rim(dz.atan2(dx)) + 1.0 {
                continue;
            }
            out.push((x, z));
        }
    }
    out
}

/// Answer `a`'s columns from `start` on, up to PER_TICK of them, worked out into `land`; where it got to.
/// `retry`: the answer to asking again for columns missing before.
#[allow(clippy::too_many_arguments)]
pub(super) fn work(land: &mut Land, g: &ShGeo, a: &crate::columns::Answer, mats: &[(u8, Class)], bx: i32, gy: i32, bz: i32, start: usize, retry: bool) -> usize {
    let end = (start + PER_TICK).min(a.columns.len());
    for i in start..end {
        let (x, z) = a.columns[i];
        let (dx, dz) = (f64::from(x - bx), f64::from(z - bz));
        let slab = g.slab_at(dx, dz);
        let Some((base, stack)) = a.column(i) else {
            // (not loaded yet: asked again)
            land.missing.push((x, z));
            if let Some(k) = slab
                && !retry
            {
                land.missing_n[k] += 1;
            }
            continue;
        };
        if let Some(k) = slab
            && retry
        {
            land.missing_n[k] = land.missing_n[k].saturating_sub(1);
        }
        let mut c = col_info(stack, base, a.below, mats, gy);
        if let Some(cc) = c.as_mut() {
            (cc.grass, cc.foliage) = a.tints(i);
        }
        // (the middle went down with the give and the sag, seven blocks, before any of it falls)
        if let (Some(cc), Some(k)) = (c.as_mut(), slab)
            && g.slabs[k].ring == 0
        {
            cc.h -= land.give;
        }
        land.put(bx, bz, x, z, base, c, slab);
    }
    end
}

/// The shared land a strike's stages fill and read.
pub(super) type Shared = Rc<std::cell::RefCell<Land>>;

#[cfg(test)]
mod tests {
    use super::*;

    fn mats(names: &[&str]) -> Vec<(u8, Class)> {
        names.iter().map(|n| material(n)).collect()
    }

    #[test]
    fn materials_by_name() {
        assert_eq!(material("minecraft:snow"), (10, Class::Snow));
        assert_eq!(material("minecraft:short_grass").1, Class::Air);
        assert_eq!(material("minecraft:poppy").1, Class::Air);
        assert_eq!(material("minecraft:oak_fence").1, Class::Air);
        assert_eq!(material("minecraft:jungle_leaves"), (36, Class::Leaves));
        assert_eq!(material("minecraft:stripped_spruce_log"), (32, Class::Log));
        assert_eq!(material("minecraft:cobblestone_stairs"), (13, Class::Ground));
        assert_eq!(material("minecraft:iron_ore"), (12, Class::Ground));
        assert_eq!(material("minecraft:grass_block"), (1, Class::Ground));
        assert_eq!(material("minecraft:moss_carpet").1, Class::Air);
        assert_eq!(material("minecraft:packed_ice").0, 11);
        assert_eq!(material("minecraft:water").1, Class::Water);
        assert!(MATS.len() <= 64 && SH_MAT + MATS.len() * 2 <= SH_GRID);
        assert_eq!(material("minecraft:red_poplar_leaves"), (57, Class::Leaves));
        assert_eq!(rgb888(rgb565(0xDF6827)) >> 19, 0xDF6827 >> 19);
        // (snow white, stone grey, leaves green, logs brown)
        assert!(MATS[10].0.iter().all(|c| *c > 230));
        assert!(MATS[34].0[1] > MATS[34].0[0] && MATS[34].0[1] > MATS[34].0[2] && MATS[33].3 & TINT_FOLIAGE != 0);
        assert!(MATS[28].1[0] > MATS[28].1[2]);
    }

    #[test]
    fn a_column_round_trips() {
        // snow on a grass block over dirt over stone, a spruce standing on it: its trunk 6 up, leaves from 3 to 9 up
        let names = ["minecraft:air", "minecraft:stone", "minecraft:dirt", "minecraft:grass_block", "minecraft:snow", "minecraft:spruce_log", "minecraft:spruce_leaves"];
        let m = mats(&names);
        let mut stack = vec![1u16; 25];
        // (bottom first: y = base - 24 + i; the ground block at i 12)
        stack[10] = 2;
        stack[11] = 2;
        stack[12] = 3;
        stack[13] = 4;
        for i in 13..=18 {
            stack[i] = 5;
        }
        for i in 15..=21 {
            if i > 18 {
                stack[i] = 6;
            }
        }
        stack[22] = 0;
        stack[23] = 0;
        stack[24] = 0;
        let base = 100;
        let c = col_info(&stack, base, 24, &m, 64).unwrap();
        let gyb = base - 24 + 12;
        assert_eq!(c.h, gyb + 1 - 64);
        assert_eq!((c.top, c.under, c.deep), (1, 2, 12));
        assert_eq!(c.log, 29);
        assert_eq!(c.log_top, 6);
        assert_eq!((c.leaf, c.leaf_lo, c.leaf_hi), (34, 7, 9));
        // (the snow under the trunk does not count as lying on it: the trunk is there)
        assert!(!c.snow);
        let (back, slab) = ColInfo::from_words(c.words(Some(77))).unwrap();
        assert_eq!(back, c);
        assert_eq!(slab, Some(77));
        // snow lying on bare ground
        let mut s2 = vec![1u16; 25];
        s2[20] = 3;
        s2[21] = 4;
        for v in s2.iter_mut().skip(22) {
            *v = 0;
        }
        let c2 = col_info(&s2, 70, 24, &m, 64).unwrap();
        assert!(c2.snow && c2.log == 0 && c2.leaf == 0);
        assert_eq!(c2.h, 70 - 24 + 20 + 1 - 64);
        assert_eq!(ColInfo::from_words(c2.words(None)).unwrap(), (c2, None));
        // a column with nothing in it
        assert_eq!(col_info(&[0; 25], 70, 24, &m, 64), None);
        // under water: the bed, and wet
        let wm = mats(&["minecraft:air", "minecraft:sand", "minecraft:water"]);
        let mut s3 = vec![1u16; 25];
        for v in s3.iter_mut().skip(18) {
            *v = 2;
        }
        s3[24] = 0;
        let c3 = col_info(&s3, 70, 24, &wm, 64).unwrap();
        assert!(c3.wet && c3.top == 21);
        assert_eq!(c3.h, 70 - 24 + 17 + 1 - 64);
        assert_eq!(ColInfo::from_words(c3.words(Some(3))).unwrap(), (c3, Some(3)));
    }
}
