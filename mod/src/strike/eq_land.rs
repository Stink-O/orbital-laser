//! The Earthquake's real land (terrain on). Three parts, one chain of stages a tick each (`eq_work`), every stage metered:
//!
//! - **The cut** (from `EQ_CRACK`, as the crack races out): every column the plates name as a fault's (`fault_at`) is
//!   opened from its floor to the top of the world, a chunk at a time as the crack reaches it (one edit a chunk, two when
//!   the crack crosses it twice), ahead of every other edit (`Blocks::urgent`). The solid columns beside the cut (its
//!   3x3 round each cut column) are lined in the same edit with the rock strata (`Strata`) from the cut's floor up to
//!   three under their ground (asked of the world, `world.surface-height`), and the water standing over them turned to
//!   rock too, so no cave, ore, water or lava shows in a wall and nothing pours into a fresh cut. The plates are worked
//!   out here, a chunk at a time from the middle out, by a quadtree on `where_at`'s distance to the nearest boundary: a
//!   block of columns far from every boundary is one plate's whole.
//! - **The land at rest** (behind the game's hold on the terrain, `render.hold-world`): every column of a disc that holds
//!   the plates and wherever they land read once (`world.read-columns`, `BELOW` under its ground, `ABOVE` from it up) and
//!   each chunk written once where its plate comes to rest. By destination (`Work::decide`): a moved plate whose column
//!   `c - offset` lies on it (and is not a cut column) is a candidate, raised by its rise; fixed land and a plate that does
//!   not move are their own. Higher ground wins. None: a gap. A gap along the main fault (`W_CANYON`, found from the main
//!   fault's cut columns out to `CANYON_REACH`) is open to a floor near `EQ_CUT_MAIN_Y` of blackstone, basalt and magma
//!   under two of lava; any other (`W_RUBBLE`) is filled with rubble to two to four under the lower side's land. A
//!   column with a lower neighbour (a face) is strata from below what shows up to three under its ground; at the foot of
//!   every step scree is heaped (`scree`). The walker's chunks (the land within `WALK_R` of where the player really
//!   stands as the chunks are listed: they walk the unmoved land there while the picture shows it moved, eq_ride.rs) go
//!   in last, from `EQ_RIDER_FROM`; each chunk's time is kept for the walk (`eq_chunk_due`).
//! - **Afterwards** (from rest): the lake rims the lining left breached and water standing over a drop set flowing, and
//!   rock let go from the cliffs' top edges as falling blocks; the mobs and items on each moved plate moved with it.
//!
//! Its memory: the disc's grids (some 6 MB at the default reach), the runs read (some 8 MB), an answer being taken in
//! (2 MB). All of it let go as the last chunk's edit is made. `eq_land_in` says when every edit made is in the world.
use super::earthquake::{EQ_CUT_HALF, EQ_PLATES, EQ_REST, EQ_STILL, EqPlates, eq_h, eq_vn};
use super::eq_trees::{EQ_SLAB_T, EQ_SLABS, EQ_TREE_LOGS, EQ_TREE_MOVE, EQ_TREE_REACH, EQ_TREES, EqSlab, EqTree, Kind, Look, eq_slabs_publish, eq_tree_at, eq_tree_edits, eq_tree_ways, eq_tree_when, eq_trees_publish, eq_trees_reset};
use super::{Act, Blocks, Plan};
use crate::ground::FxMap;
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::rc::Rc;

/// The hold on the terrain from here (just before the first edit at rest) until the land is swapped in at rest.
pub const EQ_HOLD_START: f32 = 9.6;
/// The chunks' edits at rest are due from EQ_LAND to EQ_LAND_END, the middle first; the rider's from EQ_RIDER_FROM to
/// EQ_RIDER_TO, when every plate is within a block of rest.
pub(super) const EQ_LAND: f32 = 10.0;
pub(super) const EQ_LAND_END: f32 = EQ_REST - 3.5;
pub(crate) const EQ_RIDER_FROM: f32 = EQ_REST - 1.6;
const EQ_RIDER_TO: f32 = EQ_REST - 0.5;
/// The land round where the player really stands as the chunks are listed that goes in last: room to walk there while
/// the plates move (eq_ride.rs hands them over before any of it goes in, or as soon as they reach land that has).
const WALK_R: f64 = 60.0;
/// Columns the world has not loaded by then are left alone.
const EQ_READ_BY: f32 = 9.0;
/// The longest the hold is kept, in the frames' own seconds (the game lets go by itself at 30: `gfx/hold.rs`'s MAX_HOLD).
pub const EQ_HOLD_MAX: f32 = 28.0;
/// Frames the warp stays on after the hold lets go: the game swaps the held land in on the frame after.
const EQ_SWAP_LAG: u8 = 1;
/// The read: under each column's ground and from it up (64 a column, the most the game reads in one query's room).
pub(super) const BELOW: u32 = 24;
pub(super) const ABOVE: u32 = 40;
const PER: usize = (BELOW + ABOVE) as usize;
/// Columns a part of the read at most (16,384 x 64 is the game's 1,048,576 blocks; half that: an answer is 160 bytes
/// a column in the mod's memory, FLIGHT of them and the one being taken in at once).
const PART: usize = 8_000;
/// Parts of the read asked and not taken in, at most: an answer waits in the mod's own memory.
const FLIGHT: usize = 2;
/// What a stage spends at most before what can wait waits (a tick's fuel is 50M; the edits made after the stages share
/// the tick); the cut may take more while it is behind the crack.
/// (The cut's work is counted at about what the game counts of it, measured with the fork's `mod_soak` and the trace:
/// its edits 1.0, its plates 0.9, its items 1.2 of the meter. Before that its edits were counted at half, and a stage
/// at 15M took up to 39M of the tick.)
const STAGE: u64 = 9_000_000;
const CUT_STAGE: u64 = 19_000_000;
/// What a stage of the rest's work may spend once the cut is made (the read, the passes and the chunks, nothing else of
/// the land's heavy then).
const REST_STAGE: u64 = 12_000_000;
/// What a stage of the passes over the grid may spend (the plates worked out late, which land lies where at rest, the
/// canyon, the gaps, the scree): played in the game a stage of them at REST_STAGE took 27.5M of a tick's 50M.
const PASS_STAGE: u64 = 9_500_000;
/// The most one chunk's plates and cut may cost (all 256 columns on a boundary): a chunk is begun only with this to spare.
const CUT_CHUNK: u64 = 7_000_000;
const HARD: u64 = 21_000_000;
/// Land that sinks this far or more has the land's biome put under it (`Work::biome_stage`), from this long in, this
/// many chunks a tick.
const BIOME_SINK: i32 = 8;
const BIOME_AT: f32 = EQ_STILL + 0.3;
const BIOME_CHUNKS: usize = 2;
/// The overworld's biomes of the land (the game's `#minecraft:is_overworld` less the caves': dripstone, lush, sulfur,
/// the deep dark). From the prepared resources' worldgen/biome_tags.json: to be read again for a new game version.
const BIOMES: [&str; 52] = [
    "mushroom_fields", "deep_frozen_ocean", "frozen_ocean", "deep_cold_ocean", "cold_ocean", "deep_ocean", "ocean", "deep_lukewarm_ocean",
    "lukewarm_ocean", "warm_ocean", "stony_shore", "swamp", "mangrove_swamp", "snowy_slopes", "snowy_plains", "snowy_beach",
    "windswept_gravelly_hills", "grove", "windswept_hills", "snowy_taiga", "windswept_forest", "taiga", "plains", "meadow", "beach", "forest",
    "old_growth_spruce_taiga", "flower_forest", "birch_forest", "dark_forest", "pale_garden", "savanna_plateau", "savanna", "jungle", "badlands",
    "desert", "wooded_badlands", "jagged_peaks", "stony_peaks", "frozen_river", "river", "ice_spikes", "dappled_forest", "old_growth_pine_taiga",
    "sunflower_plains", "old_growth_birch_forest", "sparse_jungle", "bamboo_jungle", "eroded_badlands", "windswept_savanna", "cherry_grove",
    "frozen_peaks",
];
/// A cut chunk is worked out no sooner than this before the crack reaches it.
const CUT_LOOK: f32 = 6.0;
/// A chunk the crack crosses twice this far apart in time gets two edits.
const CUT_SPLIT: f32 = 0.6;
/// The quadtree's slack: how far a point of a block may lie from its middle in `where_at`'s distance, per block of real
/// distance (the plates' points are pushed about by noise, which stretches distances).
const SLACK: f32 = 1.4;
#[cfg(test)]
thread_local! {
    static EVALS: Cell<u64> = const { Cell::new(0) };
    static SLACK_T: Cell<f32> = const { Cell::new(SLACK) };
}
fn slack() -> f32 {
    #[cfg(test)]
    return SLACK_T.with(Cell::get);
    #[cfg(not(test))]
    SLACK
}
fn counted_eval() {
    #[cfg(test)]
    EVALS.with(|e| e.set(e.get() + 1));
    crate::meter::spend(EVAL);
}
/// A chunk's edit at rest is made this long before it is due.
const LEAD: f32 = 0.35;
/// The most runs of the chunks' edits made and not yet in the world before more are made (some 4 MB of them).
const EQ_WAITING: u32 = 120_000;
/// A gap is the canyon out to this far from the main fault's cut.
const CANYON_REACH: u16 = 26;
/// Scree at the foot of a step at most this high.
const SCREE_MAX: i32 = 8;
/// The top of a gap's rubble (this deep) comes down after the swap with the scree, not in it.
const HIDE: i32 = 9;
/// Falling blocks from the cliffs' edges, places set flowing, lake rims breached.
const FALLS: usize = 75;
const FLOWS: usize = 150;
const BREACHES: usize = 40;
/// Water set flowing in at least this many places is heard pouring in.
const POUR_MIN: usize = 6;
/// What each piece of work costs (instructions, roughly: from the fork's `mod_soak`, the game's own count).
const TAKE_COL: u64 = 4_000;
const EVAL: u64 = 5_800;
const DECIDE_COL: u64 = 500;
const PASS_COL: u64 = 120;
const GAP_COL: u64 = 900;
const SCREE_COL: u64 = 300;
const CHUNK_COL: u64 = 2_500;
const STRATA_COL: u64 = 1_500;
/// A lined column of the cut, and each run of its lining (the strata's and the relief's work, `eq_land_costs`).
/// (Their mean: a tick of nothing but lined columns on high land costs half as much again, and a stage has taken
/// 27.5M of a tick in the game there. Counted at that, the cut falls up to 2 s behind the crack.)
const WALL_COL: u64 = 20_000;
const CUT_RUN: u64 = 2_100;
/// A column of the cut that is not lined (the canyon's, the lake's).
const CUT_COL: u64 = 2_200;
/// `crack_near`: one bending of a point (a quarter of `where_at`'s work and more).
const CRACK_NEAR: u64 = 1_800;
/// The trees that fall: a column looked at for a trunk, a trunk looked at for its tree (strike/eq_trees.rs's
/// `eq_tree_at`: some 7 x 7 columns' blocks, the plates round it), its edits made into the read.
const TREE_COL: u64 = 900;
const TREE_EVAL: u64 = 100_000;
const TREE_EDIT: u64 = 400_000;
const TREE_KIND: u64 = 250;
/// A cut column asked what it holds of the lake (`EqPlates::lake_at`: the bending, three times).
const LAKE_COL: u64 = 3_000;
/// A block of columns near the main fault's trench looked at for whether it is in it (the bending, some eight times).
const TRENCH_LOOK: u64 = 1_800;
/// A log alone in its column at rest, looked at for the way it lies (the four columns beside it).
const LYING_LOG: u64 = 1_500;
/// The trees that can fall looked for at most; the ones taken lie within this of the place most of them are round.
const EQ_TREE_CANDS: usize = 96;
/// Trunks looked at for a tree at most.
const EQ_TREE_LOOKS: usize = 300;
/// While the cut is being made the trees' disc of the read may take this much more of a stage, up to TREE_READ_TOP of
/// the tick's work in all.
const TREE_READ: u64 = 4_000_000;
const TREE_READ_TOP: u64 = 17_000_000;
const EQ_TREE_CLUSTER: f32 = 52.0;
/// A tree that can fall within this of the player is the place the falling trees are taken round.
const EQ_TREE_SEEN: f32 = 90.0;
const TREE_DECODE: u64 = 4_000;
/// How far past EQ_TREE_REACH a tree's finding looks at the land (its crown, where it lies, the room round it).
const TREE_ROOM: i32 = 24;
/// What a column at rest is (`Work::win`): a plate's index (the column comes from that plate), or:
const W_SELF: u8 = 200;
const W_GAP: u8 = 201;
/// In `Work::lakek`: a column beside the canyon, lined with rock over the lake's depth at rest.
const LINED: u8 = 0x80;
/// The tests leave out what lies this far over the lake's lava and under it: nothing of it is seen.
#[cfg(test)]
const LAKE_CLEAR: i32 = 1;
const W_CANYON: u8 = 202;
const W_RUBBLE: u8 = 203;
const W_LEAVE: u8 = 204;
const W_UNSET: u8 = 255;
/// A column's plate (`Work::plate`): a plate's index, or fixed land, or a cut column, or not worked out (outside).
const P_FIXED: u8 = 250;
const P_CUT: u8 = 251;
/// A column next to a boundary that is not cut: its plate worked out after the crack has passed (`Work::late_plates`).
const P_LATER: u8 = 252;
const P_UNSET: u8 = 255;
/// A column not read (not loaded), a height not known.
const NOT: i16 = i16::MIN;

const _: () = assert!(EQ_PLATES < W_SELF as usize);

// ---- the names of the blocks read, interned for the game's life (bounded by the game's blocks) -----------------------
#[derive(Default)]
struct Names {
    list: Vec<&'static str>,
    ids: HashMap<String, u16>,
    /// The upper half of a two-block plant or door, by its lower half's id.
    upper: HashMap<u16, u16>,
}
thread_local! {
    static NAMES: RefCell<Names> = RefCell::new(Names::default());
}
fn is_air(n: &str) -> bool {
    n == "minecraft:air" || n == "minecraft:cave_air" || n == "minecraft:void_air"
}
fn is_fluid(n: &str) -> bool {
    n.starts_with("minecraft:water") || n.starts_with("minecraft:lava")
}
/// Blocks two high whose upper half the read can't tell (it has no block states): written so where one stands on another.
fn two_high(n: &str) -> bool {
    n.ends_with("_door")
        || matches!(n, "minecraft:tall_grass" | "minecraft:large_fern" | "minecraft:sunflower" | "minecraft:lilac" | "minecraft:rose_bush" | "minecraft:peony" | "minecraft:tall_seagrass" | "minecraft:pitcher_plant")
}
/// What stands on the land rather than being it: the column's ground is the first block over the highest that is not.
fn stands(n: &str) -> bool {
    if is_air(n) || is_fluid(n) {
        return true;
    }
    let n = n.trim_start_matches("minecraft:");
    let n = n.split('[').next().unwrap_or(n);
    n.ends_with("_log")
        || n.ends_with("_wood")
        || n.ends_with("leaves")
        || n.ends_with("_stem")
        || n.ends_with("hyphae")
        || n.ends_with("_sapling")
        || n.ends_with("_flower")
        || n.ends_with("_tulip")
        || n.ends_with("_bush")
        || n.ends_with("_carpet")
        || n.ends_with("_petals")
        || n.ends_with("mushroom")
        || n.ends_with("torch")
        || n.contains("vine")
        || n.contains("bamboo")
        || matches!(
            n,
            "short_grass" | "tall_grass" | "fern" | "large_fern" | "dandelion" | "poppy" | "blue_orchid" | "allium" | "azure_bluet" | "oxeye_daisy" | "cornflower" | "lily_of_the_valley" | "sunflower" | "lilac" | "rose_bush" | "peony" | "dead_bush" | "sugar_cane" | "cactus" | "snow" | "seagrass" | "tall_seagrass" | "kelp" | "kelp_plant" | "lily_pad" | "leaf_litter" | "wildflowers" | "short_dry_grass" | "tall_dry_grass" | "pitcher_plant" | "torchflower" | "mangrove_roots" | "moss_carpet" | "glow_lichen" | "cocoa" | "bee_nest"
        )
}
impl Names {
    fn leak(&mut self, n: String) -> u16 {
        if let Some(&i) = self.ids.get(&n) {
            return i;
        }
        let i = self.list.len() as u16;
        self.list.push(Box::leak(n.clone().into_boxed_str()));
        self.ids.insert(n, i);
        i
    }
    /// A name read, as the id of what is written for it: air for every kind of air, leaves that never decay.
    fn id(&mut self, n: &str) -> u16 {
        if self.list.is_empty() {
            self.leak("minecraft:air".into());
        }
        if is_air(n) {
            return 0;
        }
        if let Some(&i) = self.ids.get(n) {
            return i;
        }
        if n.ends_with("_leaves") && !n.contains('[') {
            let i = self.leak(format!("{n}[persistent=true]"));
            // (the plain name found again without the format)
            self.ids.insert(n.to_string(), i);
            return i;
        }
        self.leak(n.to_string())
    }
    fn upper_of(&mut self, lower: u16) -> u16 {
        if let Some(&u) = self.upper.get(&lower) {
            return u;
        }
        let n = format!("{}[half=upper]", self.list[lower as usize]);
        let u = self.leak(n);
        self.upper.insert(lower, u);
        u
    }
}

// ---- the rock strata ---------------------------------------------------------------------------------------------------
/// A bed of the strata: its rock and the two it gives way to in patches, and how it weathers (-1 hard: it stands out of
/// a face as a ledge; 1 soft: it is recessed).
#[derive(Clone, Copy)]
struct Bed {
    rock: [&'static str; 3],
    hard: i8,
}
/// The marker beds, followed along a whole cliff and seen offset across each fault: a red-brown, a pale and a dark one.
const RED: Bed = Bed { rock: ["minecraft:terracotta", "minecraft:brown_terracotta", "minecraft:granite"], hard: -1 };
const PALE: Bed = Bed { rock: ["minecraft:calcite", "minecraft:diorite", "minecraft:calcite"], hard: -1 };
const DARK: Bed = Bed { rock: ["minecraft:smooth_basalt", "minecraft:blackstone", "minecraft:deepslate"], hard: 1 };
/// The ordinary beds, over the deepslate line and under it.
const BEDS: [Bed; 6] = [
    Bed { rock: ["minecraft:stone", "minecraft:andesite", "minecraft:stone"], hard: 0 },
    Bed { rock: ["minecraft:andesite", "minecraft:stone", "minecraft:diorite"], hard: 0 },
    Bed { rock: ["minecraft:tuff", "minecraft:stone", "minecraft:tuff"], hard: 1 },
    Bed { rock: ["minecraft:granite", "minecraft:stone", "minecraft:granite"], hard: -1 },
    Bed { rock: ["minecraft:stone", "minecraft:tuff", "minecraft:andesite"], hard: 0 },
    Bed { rock: ["minecraft:dripstone_block", "minecraft:tuff", "minecraft:granite"], hard: 1 },
];
const DEEP_BEDS: [Bed; 4] = [
    Bed { rock: ["minecraft:deepslate", "minecraft:cobbled_deepslate", "minecraft:deepslate"], hard: 0 },
    Bed { rock: ["minecraft:tuff", "minecraft:deepslate", "minecraft:tuff"], hard: 1 },
    Bed { rock: ["minecraft:deepslate", "minecraft:tuff", "minecraft:cobbled_deepslate"], hard: 0 },
    Bed { rock: ["minecraft:smooth_basalt", "minecraft:deepslate", "minecraft:smooth_basalt"], hard: -1 },
];
/// The markers' heights before the move (a few blocks of jitter each), their beds and thicknesses: spread over what
/// the cliffs show (the main fault's faces run from about -50 to the land, the steps' the top 30 or so).
const MARKERS: [(i32, Bed, i32); 7] = [(57, PALE, 2), (47, RED, 4), (31, DARK, 2), (16, PALE, 3), (-2, RED, 3), (-22, DARK, 2), (-40, PALE, 2)];

/// The strata every cut wall and every face at rest is lined with: beds by the block's own place in its plate (its
/// column x, z and its height before the move), so they rise with the plate and a wall lined as the crack passes is the
/// same rock as the cliff it becomes. The beds are layers continuous along a face: thick and thin, their heights
/// wandering over a hundred blocks and dipping gently one way, so a bed found in one column is at the same height or a
/// block off in the next. Within a bed its rock gives way to its two others in patches some seven blocks across.
struct Strata {
    seed: u32,
    beds: Vec<Bed>,
    /// Each height's bed (from STRATA_Y0) and the last height of that bed.
    bed_at: Vec<u16>,
    end_at: Vec<u16>,
    dip: [f32; 2],
    /// The main fault's way (the joints' frame).
    fdir: [f32; 2],
    /// What the meter counts for each run laid (the cut's linings are counted a wall at a time instead).
    per_run: Cell<u64>,
}
const STRATA_Y0: i32 = -160;
const STRATA_N: usize = 720;
impl Strata {
    fn new(seed: u32, fdir: [f32; 2]) -> Self {
        let mut beds: Vec<Bed> = Vec::new();
        let mut bed_at: Vec<u16> = Vec::with_capacity(STRATA_N);
        let markers: Vec<(i32, Bed, i32)> = MARKERS.iter().enumerate().map(|(i, &(y, b, t))| (y + (eq_h(seed, 0x5159, i as u32) % 5) as i32 - 2, b, t)).collect();
        let (mut k, mut last) = (0u32, usize::MAX);
        while bed_at.len() < STRATA_N {
            let y = STRATA_Y0 + bed_at.len() as i32;
            // (a marker starting at this height, or one already under way: laid whole)
            if let Some(&(_, b, t)) = markers.iter().find(|m| m.0 == y) {
                beds.push(b);
                for _ in 0..t {
                    bed_at.push((beds.len() - 1) as u16);
                }
                last = usize::MAX;
                continue;
            }
            let h = eq_h(seed, 0x5157 + k, 7);
            k += 1;
            let deep = y < -4;
            let pick = if deep { (h % DEEP_BEDS.len() as u32) as usize } else { (h % BEDS.len() as u32) as usize };
            if pick == last {
                continue;
            }
            last = pick;
            // (thin, middling and thick beds)
            let t = match (h >> 8) % 8 {
                0 | 1 => 1 + (h >> 12) % 2,
                2..=5 => 3 + (h >> 12) % 3,
                _ => 6 + (h >> 12) % 5,
            } as i32;
            // (never into a marker's height)
            let room = markers.iter().filter(|m| m.0 > y).map(|m| m.0 - y).min().unwrap_or(t);
            beds.push(if deep { DEEP_BEDS[pick] } else { BEDS[pick] });
            for _ in 0..t.min(room) {
                bed_at.push((beds.len() - 1) as u16);
            }
        }
        bed_at.truncate(STRATA_N);
        let mut end_at = vec![0u16; STRATA_N];
        let mut end = STRATA_N - 1;
        for i in (0..STRATA_N).rev() {
            if i + 1 < STRATA_N && bed_at[i + 1] != bed_at[i] {
                end = i;
            }
            end_at[i] = end as u16;
        }
        let a = f64::from(eq_h(seed, 0x5158, 1) % 6283) / 1000.0;
        Strata { seed, beds, bed_at, end_at, dip: [(a.cos() * 0.03) as f32, (a.sin() * 0.03) as f32], fdir, per_run: Cell::new(1_500) }
    }
    /// How far the beds are shifted at source column (sx, sz): a bed at height y there is the table's at y + this. Smooth
    /// and slow (about a block in seven at its steepest), so the beds read as layers along a face.
    fn shift(&self, sx: i32, sz: i32) -> i32 {
        let (fx, fz) = (sx as f32, sz as f32);
        let w = (eq_vn(self.seed, [fx / 120.0, fz / 120.0], 101) - 0.5) * 10.0 + (eq_vn(self.seed, [fx / 48.0, fz / 48.0], 102) - 0.5) * 3.0;
        (w + fx * self.dip[0] + fz * self.dip[1]).round() as i32
    }
    fn idx(k: i32) -> usize {
        (k - STRATA_Y0).clamp(0, STRATA_N as i32 - 1) as usize
    }
    /// The bed at table height k, and the last table height of it.
    fn bed(&self, k: i32) -> (usize, i32) {
        let i = Self::idx(k);
        let end = if k - STRATA_Y0 >= STRATA_N as i32 - 1 { i32::MAX / 2 } else if k < STRATA_Y0 { STRATA_Y0 } else { i32::from(self.end_at[i]) + STRATA_Y0 };
        (usize::from(self.bed_at[i]), end)
    }
    /// Bed b's rock at source column (sx, sz): its own, or one of its two others in patches (cells seven across, set
    /// differently for each bed).
    fn rock(&self, sx: i32, sz: i32, b: usize) -> &'static str {
        let hb = eq_h(self.seed, 0x5160, b as u32);
        let (cx, cz) = ((sx + (hb % 7) as i32).div_euclid(7), (sz + ((hb >> 4) % 7) as i32).div_euclid(7));
        let h = eq_h(self.seed ^ hb, (cx as u32).wrapping_mul(0x9e37_79b9) ^ (cz as u32).wrapping_mul(0x85eb_ca77), 0x5161) % 100;
        self.beds[b].rock[if h < 60 { 0 } else if h < 86 { 1 } else { 2 }]
    }
    /// The rock at table height k at source column (sx, sz).
    fn at(&self, sx: i32, sz: i32, k: i32) -> &'static str {
        self.rock(sx, sz, self.bed(k).0)
    }
    /// Blocks y0..=y1 of column (x, z) as strata, from source column (sx, sz), `k` the table's height at y = 0 (the
    /// source's shift less its rise): a run a bed.
    #[allow(clippy::too_many_arguments)]
    fn runs(&self, e: &mut Blocks, x: i32, z: i32, sx: i32, sz: i32, y0: i32, y1: i32, k: i32) {
        let (y0, y1) = (y0.max(-64), y1.min(319));
        let mut y = y0;
        while y <= y1 {
            let (b, end) = self.bed(y + k);
            let end = (end - k).min(y1);
            crate::meter::spend(self.per_run.get());
            e.run(x, z, y, end, self.rock(sx, sz, b));
            y = end + 1;
        }
    }
}

// ---- the faces' relief -------------------------------------------------------------------------------------------------
/// The relief of a face: the columns within RELIEF of a fault's cut are lined whole, and of those the nearest ones to the
/// cut are let go (air) where the face is set back: by up to DMAX blocks, from one function of where the face is (the cut
/// column it backs onto: `Wall::ax`, `az`) and the bed's height, so the same relief is cut as the crack passes and laid
/// at rest. Blocks let go along joints: the face's line jogs in and out in cells a dozen blocks along it and in smaller
/// ones, a few vertical joints opened as cracks two deep, hard beds standing out as ledges and soft ones recessed (never
/// more than two blocks over what is under them), and its top edge broken: notches let go down from the land in some
/// cells, a lip of rock in others. A face off the main fault is broken only in its top SIDE_RELIEF (the rest of it is
/// buried at rest), tapering down to its plain line, and lined with the strata only in its top SIDE_LINED.
const RELIEF: i32 = 5;
const DMAX: i32 = 4;
/// Off the main fault (the steps' faces, smaller): set back by up to DMAX_SIDE, lined RELIEF_SIDE deep, the column
/// behind the face lined only where the face in front of it is let go (`Strata::line`'s `only_open`).
const DMAX_SIDE: i32 = 1;
const RELIEF_SIDE: i32 = 2;
const SIDE_RELIEF: i32 = 20;
const SIDE_LINED: i32 = 36;
/// Off the main fault, how many blocks up the face each block of its set back eases in over.
const TAPER: i32 = 2;
/// A lined column's flags: on the main fault's face; kept whole (a trunk or a lake over it); its soil let go too.
const F_MAIN: u8 = 1;
const F_KEEP: u8 = 2;
const F_SOIL: u8 = 4;
/// The face's set back at its column (ax, az), less the beds': (its cells' and joints', where its notch starts down from
/// the lining's top (0 none), whether its top has a lip).
fn setback(st: &Strata, ax: i32, az: i32) -> (i32, i32, bool) {
    let (fx, fz) = (ax as f32, az as f32);
    let u = fx * st.fdir[0] + fz * st.fdir[1];
    let v = -fx * st.fdir[1] + fz * st.fdir[0];
    // (the big cells' edges wander a little; the small cells' sit on the big ones' frame)
    let uu = u + (eq_vn(st.seed, [v / 40.0, u / 40.0], 103) - 0.5) * 8.0;
    let (cu, cv) = ((uu / 13.0).floor() as i32, ((v + 5.0) / 13.0).floor() as i32);
    let hc = eq_h(st.seed, (cu as u32).wrapping_mul(0x9e37_79b9) ^ (cv as u32).wrapping_mul(0x85eb_ca77), 0x5162);
    let big = [0, 1, 1, 2, 2, 1, 0, 2][(hc % 8) as usize];
    let (fu, fv) = ((uu / 5.0 + 0.37 * cv as f32).floor() as i32, ((v + 1.0) / 5.0).floor() as i32);
    let hf = eq_h(st.seed, (fu as u32).wrapping_mul(0x9e37_79b9) ^ (fv as u32).wrapping_mul(0x85eb_ca77), 0x5163);
    let small = i32::from(hf % 3 == 0);
    // (a joint opened: a block-wide crack at the start of some big cells)
    let joint = if uu - cu as f32 * 13.0 < 1.0 && (hc >> 8) % 3 == 0 { 2 } else { 0 };
    let notch = if (hc >> 12) % 4 == 0 { 3 + ((hc >> 16) % 7) as i32 } else { 0 };
    let lip = notch == 0 && (hc >> 20) % 4 == 0;
    (big + small + joint, notch, lip)
}
/// How deep the face is let go at source height y in bed `hard` (the bed's weathering): the lined column k from the cut
/// is air when this is k or more.
/// Whether lined column `w` is lined only where the face in front of it is let go (behind a step's face).
fn only_open(w: &Wall) -> bool {
    w.k >= 2 && w.flags & F_MAIN == 0
}
#[allow(clippy::too_many_arguments)]
fn depth(base: i32, notch_from: i32, lip: bool, top: i32, from: i32, y: i32, hard: i8, dmax: i32) -> i32 {
    let mut d = base + i32::from(hard);
    if y >= notch_from {
        d += 2;
    }
    if lip && y >= top - 1 {
        d -= 1;
    }
    // (off the main fault: the face plain under its top SIDE_RELIEF, its relief easing in over it)
    if y < from + TAPER * dmax {
        d = d.min((y - from).max(0) / TAPER);
    }
    d.clamp(0, dmax)
}
impl Strata {
    /// Lined column (x, z) from source column (sx, sz) as wall `w`, risen `dy`: from its floor up to its lining's top,
    /// strata let go to air where its face is set back (`depth`), and its soil (to one over its ground) let go too where
    /// the face is set back there. The same blocks at the cut (dy 0) and at rest. Returns the column's ground after (one
    /// over its highest block left, before the rise) and whether its soil was let go.
    fn line(&self, e: &mut Blocks, x: i32, z: i32, sx: i32, sz: i32, w: &Wall, dy: i32) -> (i32, bool) {
        let k = i32::from(w.k);
        let (y0, top) = (i32::from(w.floor) + 1, i32::from(w.top));
        let sh = self.shift(sx, sz);
        let dmax = if w.flags & F_MAIN != 0 { DMAX } else { DMAX_SIDE };
        let keep = w.flags & F_KEEP != 0;
        let only_open = only_open(w);
        let (base, notch, lip) = if keep { (0, 0, false) } else { setback(self, sx + i32::from(w.ax), sz + i32::from(w.az)) };
        // (the steps' faces jog by half as much)
        let base = if w.flags & F_MAIN != 0 { base } else { base / 2 };
        let notch_from = if notch > 0 { top - notch } else { i32::MAX };
        // (behind a step's face: in view where the face in front is let go by its own cut column or the ones beside it)
        let (open_base, open_from) = if only_open && !keep {
            let (ax, az) = (sx + i32::from(w.ax), sz + i32::from(w.az));
            let (mut b, mut n) = (0, 0);
            for (dx, dz) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] {
                let (bb, nn, _) = setback(self, ax + dx, az + dz);
                b = b.max(bb / 2);
                n = n.max(nn);
            }
            (b, if n > 0 { top - n } else { i32::MAX })
        } else {
            (base, notch_from)
        };
        let from = if w.flags & F_MAIN != 0 { i32::MIN / 2 } else { top - SIDE_RELIEF };
        // (off the main fault, a column behind the face's plain line is never let go under `from`: lined from there)
        let mut y = if k >= 2 && w.flags & F_MAIN == 0 { y0.max(from) } else { y0 };
        let mut solid_top = y - 1;
        // (off the main fault, the cut's wall deeper than SIDE_LINED under its top is never seen once the gap's rubble is
        // in: plain rock there)
        if w.flags & F_MAIN == 0 && y < top - SIDE_LINED {
            let d = top - SIDE_LINED - 1;
            crate::meter::spend(2 * self.per_run.get());
            if y < 0 {
                put(e, x, z, y + dy, d.min(-1) + dy, "minecraft:deepslate");
            }
            put(e, x, z, y.max(0) + dy, d + dy, "minecraft:stone");
            solid_top = d;
            y = d + 1;
        }
        // (runs of the same block merged: a face let go whole is one run of air)
        let mut run: Option<(i32, i32, &'static str)> = None;
        let mut emit = |e: &mut Blocks, r: Option<(i32, i32, &'static str)>| {
            if let Some((a, b, n)) = r
                && a + dy <= 319
                && b + dy >= -64
            {
                crate::meter::spend(self.per_run.get());
                e.run(x, z, (a + dy).max(-64), (b + dy).min(319), n);
            }
        };
        while y <= top {
            let (b, end) = self.bed(y + sh);
            let mut end = (end - sh).min(top);
            // (a run breaks where the notch starts, at the lip, and through the taper's steps)
            if y < notch_from && end >= notch_from {
                end = notch_from - 1;
            }
            if lip && y < top - 1 && end >= top - 1 {
                end = top - 2;
            }
            if y < from {
                end = end.min(from - 1);
            } else if y < from + TAPER * dmax {
                end = end.min(from + TAPER * ((y - from) / TAPER) + TAPER - 1);
            }
            let d = if keep { 0 } else { depth(base, notch_from, lip, top, from, y, self.beds[b].hard, dmax) };
            // (behind a step's face: only where the face in front is let go; the rest left as it is, out of sight)
            if only_open && (keep || depth(open_base, open_from, false, top, from, y, self.beds[b].hard, dmax) < k - 1) {
                emit(e, run.take());
                solid_top = end;
                y = end + 1;
                continue;
            }
            let air = d >= k;
            let name = if air { "minecraft:air" } else { self.rock(sx, sz, b) };
            match run {
                Some((a, _, n)) if std::ptr::eq(n, name) => run = Some((a, end, n)),
                _ => {
                    emit(e, run.take());
                    run = Some((y, end, name));
                }
            }
            if !air {
                solid_top = end;
            }
            y = end + 1;
        }
        // (the soil and what grows on it: let go where the face is set back at the land's top)
        let soil = !keep && depth(base, notch_from, lip, top, from, top + 1, 0, dmax) >= k;
        if soil {
            let g = i32::from(w.ground);
            match run {
                Some((a, _, n)) if is_air(n) => run = Some((a, g + 1, n)),
                _ => {
                    emit(e, run.take());
                    run = Some((top + 1, g + 1, "minecraft:air"));
                }
            }
            emit(e, run);
            return (solid_top + 1, true);
        }
        emit(e, run);
        (i32::from(w.ground), false)
    }
}

// ---- what lib.rs asks of the land's work ------------------------------------------------------------------------------
#[derive(Default)]
struct Gate {
    on: bool,
    done: bool,
    made: u32,
    sent: Rc<Cell<u32>>,
    /// The runs of every edit made so far, summed up to each (to tell how many wait: `gate_waiting`).
    runs: Vec<u32>,
}
thread_local! {
    static GATE: RefCell<Gate> = RefCell::new(Gate::default());
    /// The most a stage of the land's work spent (the meter), for the tests.
    static PEAK: Cell<u64> = const { Cell::new(0) };
    /// Where the player's feet really are (x, z), as lib.rs last said (`eq_walker`): the walker's chunks are listed
    /// round it.
    static WALKER: Cell<Option<[f64; 2]>> = const { Cell::new(None) };
    /// Each chunk's edit at rest and when it is due (never in sooner), once listed (`eq_chunk_due`).
    static DUE: RefCell<FxMap<(i32, i32), f32>> = RefCell::new(FxMap::default());
}
/// Plate i's offset at rest.
fn offset_of(pl: &EqPlates, i: usize) -> [i32; 3] {
    pl.offset(i)
}
/// Where the player's feet really are (x, z), each tick of an Earthquake (none: no player).
pub fn eq_walker(at: Option<[f64; 2]>) {
    WALKER.with(|w| w.set(at));
}
/// When chunk (a, b)'s edit at rest is due (it never goes in sooner), if it has one and the chunks are listed.
pub fn eq_chunk_due(a: i32, b: i32) -> Option<f32> {
    DUE.with(|d| d.borrow().get(&(a, b)).copied())
}
/// Whether the land is all in the world: every chunk's edit made and gone in (true when there is no land work).
pub fn eq_land_in() -> bool {
    GATE.with(|g| {
        let g = g.borrow();
        !g.on || (g.done && g.sent.get() >= g.made)
    })
}
fn gate_reset(on: bool) {
    GATE.with(|g| *g.borrow_mut() = Gate { on, ..Default::default() });
    DUE.with(|d| *d.borrow_mut() = FxMap::default());
}
fn gate_made(q: &mut Plan, due: f32, e: Blocks) {
    GATE.with(|g| {
        let mut g = g.borrow_mut();
        g.made += 1;
        let n = g.runs.last().copied().unwrap_or(0) + e.runs.len() as u32;
        g.runs.push(n);
    });
    q.ev.push((due, Act::Blocks(Box::new(e))));
}
/// The runs of the edits made and not yet in the world (they go in in about the order they are made): what the mod
/// holds of them, 32 bytes a run.
fn gate_waiting() -> u32 {
    GATE.with(|g| {
        let g = g.borrow();
        let all = g.runs.last().copied().unwrap_or(0);
        let k = (g.sent.get() as usize).min(g.runs.len());
        all - if k == 0 { 0 } else { g.runs[k - 1] }
    })
}

/// What the frame does about the hold and the warp at strike second `t` (lib.rs's `frame`): `real`, the plates come to
/// rest on land really moved; `land_in`, all of it is in (`eq_land_in`); `held` the frames' seconds the hold has been on;
/// `prev`, the last frame's hold and frames since the hold let go. The hold from EQ_HOLD_START to rest, kept past it while
/// edits wait, never past EQ_HOLD_MAX; the warp from EQ_WARP_START to EQ_WARP_END, and while held, and for EQ_SWAP_LAG
/// frames from the one the hold lets go on (the game shows the held land on the frame after). Returns (hold, warp, the
/// frames since the hold let go, counting this one).
pub fn eq_frame(t: f32, real: bool, land_in: bool, held: f32, prev: (bool, u8)) -> (bool, bool, u8) {
    use super::earthquake::{EQ_WARP_END, EQ_WARP_START};
    let moving = (EQ_WARP_START..EQ_WARP_END).contains(&t);
    if !real {
        return (false, moving, 0);
    }
    let out_of_time = held >= EQ_HOLD_MAX;
    let hold = t >= EQ_HOLD_START && !out_of_time && !(t >= EQ_REST && land_in);
    let lag = if hold { 0 } else if prev.0 { 1 } else if prev.1 > 0 { prev.1.saturating_add(1) } else { 0 };
    // (the hold run out before rest, as on a server far behind: the real land shows at rest, so the warp goes too)
    if out_of_time && t < EQ_REST {
        return (false, false, lag);
    }
    let warp = (moving || hold || (lag > 0 && lag <= EQ_SWAP_LAG)) && t >= EQ_WARP_START;
    (hold, warp, lag)
}

// ---- the disc of columns ---------------------------------------------------------------------------------------------
/// A column lined as the cut passed (one within RELIEF of it): its lining from over `floor` up to `top`, its ground then
/// (`ground`, the soil between), and the lake over it turned to rock from `rim0` to `rim1` (none: `rim1 < rim0`); how
/// far it is from the cut (`k`, 1 beside it) and the cut column its face backs onto (`ax`, `az` from it); its ground
/// once its face is let go (`gnd`); `F_*`.
#[derive(Clone, Copy)]
struct Wall {
    top: i16,
    rim0: i16,
    rim1: i16,
    floor: i16,
    ground: i16,
    gnd: i16,
    k: u8,
    ax: i8,
    az: i8,
    flags: u8,
}
/// One column of a cut chunk's edit: a cut column or a lined one near it (`k` from it, its face's cut column `ax`, `az`
/// from it, on the main fault's face `main`), when the crack reaches it, its floor; `c` its cell in the disc, or `FAR`
/// for the main crack past the zone (worked out on its own, `Work::far_items`).
#[derive(Clone, Copy)]
struct Item {
    c: u32,
    x: i32,
    z: i32,
    at: f32,
    floor: i16,
    wall: bool,
    k: u8,
    ax: i8,
    az: i8,
    main: bool,
}
const FAR: u32 = u32::MAX;
/// Something done afterwards: a falling block let go from a cliff's edge, a place set flowing, a lake's rim breached.
struct After {
    falls: Vec<(i32, i32, i32, i8, i8, &'static str)>,
    flows: Vec<(i32, i32, i32)>,
    breaches: Vec<(i32, i32, i32, i32)>,
}
/// How far the rest's passes over the grid have got.
#[derive(Default)]
struct Passes {
    decided: usize,
    canyon: bool,
    gaps: usize,
    scree: usize,
    marked: usize,
}

/// The read's runs (a block's id << 8 | how many of it up the column), each column's together: kept in blocks of
/// RUNS_BLOCK that are never grown or moved. One list grown a run at a time doubles as it fills, the old and the new
/// held together as it does: tens of megabytes of the mod's 64 for a moment, on land with a lot to read.
#[derive(Default)]
struct Runs {
    blocks: Vec<Vec<u32>>,
}
const RUNS_BITS: u32 = 17;
const RUNS_BLOCK: usize = 1 << RUNS_BITS;
impl Runs {
    /// Where the next column's runs go (its slot): in a new block when the last has no room for `most` more.
    fn start(&mut self, most: usize) -> u32 {
        if self.blocks.last().is_none_or(|b| b.len() + most > RUNS_BLOCK) {
            self.blocks.push(Vec::with_capacity(RUNS_BLOCK.max(most)));
        }
        let b = self.blocks.len() - 1;
        ((b << RUNS_BITS) | self.blocks[b].len()) as u32
    }
    fn push(&mut self, r: u32) {
        if let Some(b) = self.blocks.last_mut() {
            b.push(r);
        }
    }
    /// The `n` runs from `slot`.
    fn of(&self, slot: u32, n: u8) -> &[u32] {
        let (b, o) = ((slot >> RUNS_BITS) as usize, slot as usize & (RUNS_BLOCK - 1));
        self.blocks.get(b).and_then(|v| v.get(o..o + usize::from(n))).unwrap_or(&[])
    }
}

struct Work {
    pl: EqPlates,
    np: usize,
    /// The disc's middle (the target block) and radius; the grid's corner and side.
    cx: i32,
    cz: i32,
    r: i32,
    x0: i32,
    z0: i32,
    w: i32,
    offs: Vec<[i32; 3]>,
    moved: Vec<bool>,
    strata: Strata,
    /// Where the player stood as it fired (x, z): the walker's chunks' middle when lib.rs has not said (`WALKER`).
    walk_at: Option<[f64; 2]>,
    plate: Vec<u8>,
    /// A cut column's kind (0 none, 1 a fault's, 2 the main fault's), its floor, when the crack reaches it.
    cutk: Vec<u8>,
    cutf: Vec<i16>,
    cat: Vec<f32>,
    walls: FxMap<u32, Wall>,
    // the cut
    cgrid: (i32, i32, i32),
    cdone: Vec<bool>,
    /// The disc's rows' half widths; each cut chunk's count of cut columns; the cells whose plates wait.
    halfw: Vec<i32>,
    ccount: Vec<u16>,
    later: Vec<u32>,
    later_done: usize,
    /// What the log has been told: the cut made, the read in.
    said: (bool, bool),
    /// The canyon's spread: each gap's distance from the main fault's cut, the gaps to spread from.
    cdist: Vec<u16>,
    cq: VecDeque<usize>,
    /// The cut's chunks and the soonest the crack can reach each, in that order.
    corder: Vec<(u32, f32)>,
    cnext: usize,
    cpend: Vec<u32>,
    surveys: VecDeque<(u32, Vec<Vec<Item>>)>,
    /// The main crack past the zone: its chunks in the crack's order (`crack_chunks`), how far it has got.
    far: Vec<(i32, i32, f32)>,
    far_next: usize,
    cut_built: bool,
    // the read
    base: Vec<i16>,
    /// How many of a column's blocks from its base reach up to its highest that is not air, and to its ground (one over
    /// its highest that does not stand on the land).
    hi: Vec<u8>,
    gnd: Vec<u8>,
    slot: Vec<u32>,
    nrun: Vec<u8>,
    rle: Runs,
    /// The read's parts: rows from and to, and whether it is those rows of the disc `tree_r` round the target (the
    /// trees') or of the rest.
    parts: Vec<(i32, i32, bool)>,
    /// How many of the parts, the first, are the trees' disc; its radius.
    tree_parts: usize,
    tree_r: i32,
    tags: Vec<u32>,
    asked: usize,
    taken: usize,
    taking: Option<(Rc<crate::columns::Answer>, usize)>,
    missing: Vec<(i32, i32)>,
    retry: Option<u32>,
    retry_since: f32,
    retry_at: f32,
    read_done: bool,
    // the rest
    win: Vec<u8>,
    /// The top at rest: land, its highest block that is the land (its ground less one); the canyon, its floor; rubble, its top.
    top: Vec<i16>,
    scree: Vec<u8>,
    pass: Passes,
    marks: Vec<bool>,
    chunks: Vec<(i32, i32, f32)>,
    next: usize,
    after: After,
    /// What comes down at the steps' feet after the swap: each chunk's edit, by how far along the main fault it lies.
    post: Vec<(f32, Blocks)>,
    /// What a stage may spend (`STAGE` while the cut is made, `REST_STAGE` after), and the most a chunk at rest has.
    cap: u64,
    chunk_cost: u64,
    sent: Rc<Cell<u32>>,
    /// The trees that fall (strike/eq_trees.rs), found once the read is in and the plates are known.
    trees: Trees,
    /// By a name's id: a log read with no block state (`lying_log`).
    plain_log: Vec<bool>,
    /// What each cut column holds of the lake (`EqPlates::lake_at`), told as the cut is found.
    lakek: Vec<u8>,
    /// The slabs of the low lip that come away (`find_slabs`), and whether lib.rs has been told of them.
    slabs: Vec<EqSlab>,
    /// The lake's level (`EqPlates::lake`, which works out every plate's offset: asked once, not a column).
    lake: Option<i32>,
    /// The next chunk of the grid looked at for the biome under it (`biome_stage`).
    biome_next: usize,
    slabs_said: bool,
}

/// The slabs of the low side's lip that come away (strike/eq_trees.rs's `EqSlab`): up to EQ_SLABS boxes of columns
/// inside the main fault's trench along the lake, on its low side, each two to seven columns in from the trench's edge
/// and long the fault's way, found from a guess (the fault's line unbent) by a probe across the trench and a check of
/// the box's corners and sides: every column of it, and the ring of columns round it, well inside the trench.
fn find_slabs(pl: &EqPlates) -> Vec<EqSlab> {
    let Some(lake) = pl.lake() else { return Vec::new() };
    let (f, end) = pl.fault();
    // (the way across the fault toward its line from the low side, as a world axis; the other axis runs along it)
    let n = [-f[1], f[0]];
    let (dir, e, a) = if n[0].abs() >= n[1].abs() {
        if n[0] > 0.0 { (0u8, [1, 0], [0, 1]) } else { (1, [-1, 0], [0, 1]) }
    } else if n[1] > 0.0 {
        (2, [0, 1], [1, 0])
    } else {
        (3, [0, -1], [1, 0])
    };
    let mut out: Vec<EqSlab> = Vec::new();
    // (which lurch each goes with: most with the climax)
    const KS: [usize; EQ_SLABS] = [4, 2, 4, 1, 4, 4, 3, 4, 2, 4];
    for i in 0..EQ_SLABS {
        crate::meter::spend(500_000);
        let h = eq_h(pl.seed, 700 + i as u32, 31);
        // (within about 70 of the target along the fault: where the trench is widest, and the copy the warp draws them
        // in stays small)
        let u = (i as f32 - 4.5) * (0.95 * end / EQ_SLABS as f32) + (h % 7) as f32 - 3.0;
        let deep = 4 + (h >> 4) % 3;
        let g = pl.unbent(u, -0.6 * super::earthquake::EQ_WIDE);
        // (across the trench through the guess: the columns from two inside its low edge, `deep` of them)
        let at = |k: i32, j: i32| [g[0] + k * e[0] + j * a[0], g[1] + k * e[1] + j * a[1]];
        let good = |c: [i32; 2], least: f32| pl.trench_probe(c[0], c[1]).is_some_and(|(pu, m, low)| low && m >= least && pu.abs() < end - 4.0);
        let run: Vec<i32> = (-18..=18).filter(|&k| pl.trench_probe(at(k, 0)[0], at(k, 0)[1]).is_some_and(|(_, m, low)| low && m >= 2.0 && m < 2.0 + deep as f32)).collect();
        let (Some(&k0), Some(&k1)) = (run.first(), run.last()) else { continue };
        // (grown from the middle of those, a row or a line of columns at a time, while the box and the ring of columns
        // round it stay inside the trench: the fault may run at any angle to the world's axes)
        let mut seen: HashMap<(i32, i32), bool> = HashMap::new();
        let mut ok = |k: i32, j: i32| *seen.entry((k, j)).or_insert_with(|| good(at(k, j), 0.8));
        let mut all = |ka: i32, kb: i32, ja: i32, jb: i32| (ka - 1..=kb + 1).all(|k| (ja - 1..=jb + 1).all(|j| ok(k, j)));
        let kc = (k0 + k1) / 2;
        let (mut ka, mut kb, mut ja, mut jb) = (kc, kc, 0, 0);
        if !all(ka, kb, ja, jb) {
            continue;
        }
        let (long, wide) = (8 + ((h >> 8) % 5) as i32, deep as i32 + 1);
        loop {
            let mut grew = false;
            if jb - ja + 1 < long && all(ka, kb, ja, jb + 1) {
                jb += 1;
                grew = true;
            }
            if jb - ja + 1 < long && all(ka, kb, ja - 1, jb) {
                ja -= 1;
                grew = true;
            }
            if kb - ka + 1 < wide && all(ka, kb + 1, ja, jb) {
                kb += 1;
                grew = true;
            }
            if kb - ka + 1 < wide && all(ka - 1, kb, ja, jb) {
                ka -= 1;
                grew = true;
            }
            if !grew {
                break;
            }
        }
        if jb - ja + 1 < 4 || kb - ka + 1 < 3 {
            continue;
        }
        let (c0, c1) = (at(ka, ja), at(kb, jb));
        let (lo, hi) = ([c0[0].min(c1[0]), c0[1].min(c1[1])], [c0[0].max(c1[0]), c0[1].max(c1[1])]);
        // (clear of the one before by a few columns)
        if out.iter().any(|s| lo[0] <= s.hi[0] + 3 && s.lo[0] <= hi[0] + 3 && lo[1] <= s.hi[1] + 3 && s.lo[1] <= hi[1] + 3) {
            continue;
        }
        let mid = [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2];
        let Some(plate) = pl.column(mid[0], mid[1]) else { continue };
        let t0 = pl.lurch(plate, KS[i]).t + 0.25 + 0.5 * ((h >> 12) & 255) as f32 / 255.0;
        // (how high it stands over the lava as it goes, how much room it has to the far side: it leans no further than
        // keeps its top short of that, and drops until all of it is under)
        let yb = lake + 2;
        let sunk = pl.disp(plate, t0 + 0.5 * EQ_SLAB_T)[1];
        let tall = ((pl.block[1] + 8 - yb) as f32 + sunk).max(6.0);
        let room = pl.trench_probe(mid[0], mid[1]).map_or(8.0, |(pu, m, _)| 2.0 * pl.main_half(pu) - m) + 19.0 * pl.share(plate, t0);
        let amax = ((room - 3.0) / tall).clamp(0.1, 0.96).asin().to_degrees().min(72.0);
        let fall = tall * amax.to_radians().cos() + (deep as f32 + 1.0) * amax.to_radians().sin() + 5.0;
        out.push(EqSlab { lo, hi, yb, dir, plate, t0, amax, fall });
    }
    out
}
/// How far the trees' finding has got: the rows of columns looked at for trunks, the trunks found (a hash to take them
/// in, their cell, their logs), how many looked at, the trees taken.
#[derive(Default)]
struct Trees {
    row: i32,
    /// The rows whose plates beside the cut are worked out.
    fix: i32,
    /// Where the trunks are looked at from, nearest first (the player), if so.
    from: Option<[f64; 2]>,
    started: bool,
    sites: Vec<(u32, u32, u8)>,
    sorted: bool,
    next: usize,
    /// The trees that can fall, each with its columns as they read once it has fallen; then the ones taken.
    cands: Vec<(EqTree, Vec<((i32, i32), (i32, Vec<u16>))>, u32)>,
    taken: Vec<EqTree>,
    done: bool,
}
/// The land as read, for the trees' finding: each column's blocks as they are looked at, kept.
struct Looker<'a> {
    wk: &'a Work,
    names: &'a [&'static str],
    /// What each id read is to a tree (`tree_kind` of its name).
    kinds: &'a [Kind],
    cols: FxMap<(i32, i32), Option<(i32, Vec<u16>)>>,
}
/// What a block's name is to a tree.
fn tree_kind(n: &str) -> Kind {
    if is_air(n) {
        return Kind::Air;
    }
    if is_fluid(n) {
        return Kind::Fluid;
    }
    let b = n.trim_start_matches("minecraft:");
    let b = b.split('[').next().unwrap_or(b);
    if b.ends_with("_log") || b.ends_with("_wood") {
        return Kind::Log;
    }
    if b.ends_with("leaves") {
        return Kind::Leaves;
    }
    if b == "vine" {
        return Kind::Vine;
    }
    if stands(n) && !b.contains("vine") && !matches!(b, "cocoa" | "bee_nest" | "mangrove_roots" | "glow_lichen") && !b.ends_with("_stem") && !b.ends_with("hyphae") && !b.contains("bamboo") {
        return Kind::Plant;
    }
    Kind::Other
}
impl Looker<'_> {
    fn col(&mut self, x: i32, z: i32) -> Option<&(i32, Vec<u16>)> {
        let wk = self.wk;
        self.cols
            .entry((x, z))
            .or_insert_with(|| {
                let c = wk.idx(x, z)?;
                if wk.base[c] == NOT {
                    return None;
                }
                crate::meter::spend(TREE_DECODE);
                Some((i32::from(wk.base[c]), wk.col_ids(c)))
            })
            .as_ref()
    }
    fn id_at(&mut self, b: [i32; 3]) -> Option<u16> {
        let (base, ids) = self.col(b[0], b[2])?;
        let k = b[1] - *base;
        (k >= 0 && (k as usize) < ids.len()).then(|| ids[k as usize])
    }
}
impl Look for Looker<'_> {
    fn kind(&mut self, x: i32, y: i32, z: i32) -> Kind {
        crate::meter::spend(TREE_KIND);
        match self.id_at([x, y, z]) {
            Some(id) => match self.kinds.get(usize::from(id)) {
                Some(&k) => k,
                None => tree_kind(self.names.get(usize::from(id)).copied().unwrap_or("minecraft:air")),
            },
            None => Kind::Other,
        }
    }
    fn ground(&mut self, x: i32, z: i32) -> Option<i32> {
        let c = self.wk.idx(x, z)?;
        (self.wk.base[c] != NOT).then(|| i32::from(self.wk.base[c]) + i32::from(self.wk.gnd[c].max(1)))
    }
    fn plate(&mut self, x: i32, z: i32) -> Option<usize> {
        let c = self.wk.idx(x, z)?;
        let p = usize::from(self.wk.plate[c]);
        (p < self.wk.np && self.wk.cutk[c] == 0 && self.wk.base[c] != NOT && !self.wk.walls.contains_key(&(c as u32))).then_some(p)
    }
}

impl Work {
    fn new(pl: EqPlates, me: Option<[f64; 3]>) -> Self {
        let np = EQ_PLATES;
        let offs: Vec<[i32; 3]> = (0..np).map(|i| offset_of(&pl, i)).collect();
        let moved: Vec<bool> = offs.iter().map(|o| *o != [0; 3]).collect();
        let maxh = offs.iter().map(|o| f64::from(o[0] * o[0] + o[2] * o[2]).sqrt()).fold(0.0, f64::max);
        let (mid, zr) = pl.zone();
        let (cx, cz) = (pl.block[0], pl.block[2]);
        // (everything that moves or is cut lies within the zone; where it lands within that and the largest offset)
        let r = (zr + f64::from(mid[0] as i32 - cx).hypot(f64::from(mid[1] as i32 - cz)) + maxh).ceil() as i32 + 3;
        let w = 2 * r + 1;
        let n = (w * w) as usize;
        // (first the disc round the target the trees that fall are looked for in, then the rest of the rows from the
        // target's out)
        let tree_r = (EQ_TREE_REACH as i32 + TREE_ROOM).min(r);
        let mut parts = Vec::new();
        let (mut from, mut cols) = (-tree_r, 0usize);
        for dz in -tree_r..=tree_r {
            let row = 2 * Self::half(tree_r, dz) as usize + 1;
            if cols + row > PART {
                parts.push((from, dz - 1, true));
                from = dz;
                cols = 0;
            }
            cols += row;
        }
        parts.push((from, tree_r, true));
        let tree_parts = parts.len();
        let (mut from, mut cols) = (-r, 0usize);
        for dz in -r..=r {
            let row = 2 * Self::half(r, dz) as usize + 1;
            if cols + row > PART {
                parts.push((from, dz - 1, false));
                from = dz;
                cols = 0;
            }
            cols += row;
        }
        parts.push((from, r, false));
        parts[tree_parts..].sort_by_key(|p| if p.0 <= 0 && p.1 >= 0 { 0 } else { p.0.abs().min(p.1.abs()) });
        let tags = parts.iter().map(|_| crate::columns::new_tag()).collect();
        let walk_at = me.map(|m| [m[0], m[2]]);
        let (x0, z0) = (cx - r, cz - r);
        let cgrid = (x0 >> 4, z0 >> 4, ((x0 + w - 1) >> 4) - (x0 >> 4) + 1);
        let seed = pl.seed;
        let mut wk = Work {
            pl,
            np,
            cx,
            cz,
            r,
            x0,
            z0,
            w,
            offs,
            moved,
            strata: Strata::new(seed, pl.fdir),
            walk_at,
            plate: vec![P_UNSET; n],
            cutk: vec![0; n],
            cutf: vec![NOT; n],
            cat: vec![0.0; n],
            walls: FxMap::default(),
            cgrid,
            cdone: vec![false; (cgrid.2 * cgrid.2) as usize],
            halfw: (-r..=r).map(|dz| Self::half(r, dz)).collect(),
            ccount: vec![0; (cgrid.2 * cgrid.2) as usize],
            later: Vec::new(),
            later_done: 0,
            said: (false, false),
            cdist: Vec::new(),
            cq: VecDeque::new(),
            corder: Vec::new(),
            cnext: 0,
            cpend: Vec::new(),
            surveys: VecDeque::new(),
            far: pl.crack_chunks(),
            far_next: 0,
            cut_built: false,
            base: vec![NOT; n],
            hi: vec![0; n],
            gnd: vec![0; n],
            slot: vec![u32::MAX; n],
            nrun: vec![0; n],
            rle: Runs::default(),
            parts,
            tree_parts,
            tree_r,
            tags,
            asked: 0,
            taken: 0,
            taking: None,
            missing: Vec::new(),
            retry: None,
            retry_since: 0.0,
            retry_at: 0.0,
            read_done: false,
            win: Vec::new(),
            top: Vec::new(),
            scree: Vec::new(),
            pass: Passes::default(),
            marks: Vec::new(),
            chunks: Vec::new(),
            next: 0,
            after: After { falls: Vec::new(), flows: Vec::new(), breaches: Vec::new() },
            post: Vec::new(),
            cap: STAGE,
            chunk_cost: 2_500_000,
            sent: Rc::new(Cell::new(0)),
            trees: Trees::default(),
            plain_log: Vec::new(),
            lakek: vec![0; n],
            slabs: Vec::new(),
            lake: pl.lake(),
            biome_next: 0,
            slabs_said: false,
        };
        // (the cut's chunks in the order the crack can first reach them or a chunk beside them: the soonest it can reach
        // a column of each, and a chunk's edit waits for every chunk round it to be worked out)
        let (a0, b0, cn) = cgrid;
        let mut order = Vec::new();
        let pad = slack() * 8.0 * std::f32::consts::SQRT_2 + 1.0;
        let mut soon = vec![f32::MAX; (cn * cn) as usize];
        for k in 0..cn * cn {
            let (a, b) = (a0 + k % cn, b0 + k / cn);
            if wk.chunk_dist(a, b) > f64::from(r) {
                wk.cdone[k as usize] = true;
                continue;
            }
            crate::meter::spend(CRACK_NEAR);
            soon[k as usize] = wk.pl.crack_soonest((a * 16 + 8 - wk.pl.block[0]) as f32, (b * 16 + 8 - wk.pl.block[2]) as f32, pad);
        }
        for k in 0..cn * cn {
            if soon[k as usize] == f32::MAX {
                continue;
            }
            let (i, j) = (k % cn, k / cn);
            let mut at = f32::MAX;
            for (u, v) in (-1..=1).flat_map(|dj| (-1..=1).map(move |di| (i + di, j + dj))) {
                if u >= 0 && v >= 0 && u < cn && v < cn {
                    at = at.min(soon[(v * cn + u) as usize]);
                }
            }
            order.push((k as u32, at));
        }
        order.sort_by(|a, b| a.1.total_cmp(&b.1));
        wk.corder = order;
        wk
    }
    /// A row's half width in the disc, `dz` from the middle.
    fn half(r: i32, dz: i32) -> i32 {
        f64::from(r * r - dz * dz).max(0.0).sqrt().floor() as i32
    }
    fn idx(&self, x: i32, z: i32) -> Option<usize> {
        let (i, k) = (x - self.x0, z - self.z0);
        (i >= 0 && k >= 0 && i < self.w && k < self.w).then(|| (k * self.w + i) as usize)
    }
    fn xz(&self, i: usize) -> (i32, i32) {
        (self.x0 + i as i32 % self.w, self.z0 + i as i32 / self.w)
    }
    fn in_disc_xz(&self, x: i32, z: i32) -> bool {
        let dz = z - self.cz;
        dz.abs() <= self.r && self.halfw[(dz + self.r) as usize] >= (x - self.cx).abs()
    }
    /// How far chunk (a, b)'s nearest column is from the target.
    fn chunk_dist(&self, a: i32, b: i32) -> f64 {
        let d = |c: i32, lo: i32| f64::from((lo - c).max(c - (lo + 15)).max(0));
        d(self.cx, a * 16).hypot(d(self.cz, b * 16))
    }
    fn part_columns(&self, p: usize) -> Vec<(i32, i32)> {
        let (a, b, trees) = self.parts[p];
        let mut out = Vec::with_capacity(PART);
        for dz in a..=b {
            let h = Self::half(self.r, dz);
            let at = |dx: i32| (self.cx + dx, self.cz + dz);
            // (the row's share of the trees' disc: none past it)
            let k = if dz.abs() <= self.tree_r { Self::half(self.tree_r, dz).min(h) } else { -1 };
            if trees {
                out.extend((-k..=k).map(at));
            } else if k < 0 {
                out.extend((-h..=h).map(at));
            } else {
                out.extend((-h..-k).map(at));
                out.extend((k + 1..=h).map(at));
            }
        }
        out
    }

    // ---- the cut ------------------------------------------------------------------------------------------------------
    /// The plates over the block of s x s columns from (x0, z0), and its cut columns: one look at its middle, and the
    /// four quarters looked at again where a boundary may pass through it.
    fn eval(&mut self, x0: i32, z0: i32, s: i32) {
        let (bx, bz) = (self.pl.block[0], self.pl.block[2]);
        if s == 1 {
            let Some(c) = self.idx(x0, z0).filter(|_| self.in_disc_xz(x0, z0)) else { return };
            // (whether it is cut, now; which plate it is on, once the crack has passed)
            counted_eval();
            if let Some(f) = self.pl.fault_at(x0, z0) {
                // (the main crack past the zone is cut on its own, `far_items`: here it is only kept out of the rest)
                self.plate[c] = P_CUT;
                self.cutk[c] = if f.crack { 3 } else if f.main { 2 } else { 1 };
                self.cutf[c] = f.floor.clamp(-63, 300) as i16;
                self.cat[c] = f.at;
                // (what it holds of the lake: asked only of a column that may)
                if !f.crack && self.pl.trench_near((x0 - bx) as f32 + 0.5, (z0 - bz) as f32 + 0.5, 12.0, 5.0) {
                    crate::meter::spend(LAKE_COL);
                    self.lakek[c] = self.pl.lake_at(x0, z0, f.main);
                }
                if !f.crack {
                    let (a0, b0, cn) = self.cgrid;
                    let k = ((z0 >> 4) - b0) * cn + ((x0 >> 4) - a0);
                    self.ccount[k as usize] = self.ccount[k as usize].saturating_add(1);
                }
            } else {
                self.plate[c] = P_LATER;
                self.later.push(c as u32);
            }
            let _ = (bx, bz);
            return;
        }
        // (a block wholly outside the disc: nothing)
        let fd = |c: i32, lo: i32| (lo - c).max(c - (lo + s - 1)).max(0);
        if f64::from(fd(self.cx, x0)).hypot(f64::from(fd(self.cz, z0))) > f64::from(self.r) {
            return;
        }
        counted_eval();
        let h = s as f32 * 0.5;
        let (mx, mz) = ((x0 - bx) as f32 + h, (z0 - bz) as f32 + h);
        let (p, e) = self.pl.where_at(mx, mz);
        // (the farthest column middle in the block is (h - 0.5) along each way from its middle)
        let pad = slack() * (h - 0.5) * std::f32::consts::SQRT_2 + 0.1;
        // (past the rim the main crack toward the player may pass through it too)
        let crack = p.is_none() && {
            crate::meter::spend(CRACK_NEAR);
            self.pl.crack_near(mx, mz, pad)
        };
        // (nor within the main fault's trench, wider than any other cut; a block wholly inside it is cut and lake
        // through and through)
        // (the main fault is a boundary: a block far from every boundary is far from its trench, and is not asked)
        let ht = (h - 0.5) * std::f32::consts::SQRT_2 + 0.1;
        let trench = e <= 2.0 * (super::earthquake::EQ_WIDE + pad + ht) + 4.0 && {
            crate::meter::spend(TRENCH_LOOK);
            self.pl.trench_near(mx, mz, pad, ht)
        };
        if trench
            && s <= 4
            && let Some(at) = self.pl.trench_inside(mx, mz, ht)
        {
            crate::meter::spend(60 * (s * s) as u64);
            let floor = super::earthquake::EQ_CUT_MAIN_Y as i16;
            for z in z0..z0 + s {
                for x in x0..x0 + s {
                    if self.in_disc_xz(x, z)
                        && let Some(c) = self.idx(x, z)
                    {
                        self.plate[c] = P_CUT;
                        self.cutk[c] = 2;
                        self.cutf[c] = floor;
                        self.cat[c] = at;
                        self.lakek[c] = 2;
                        let (a0, b0, cn) = self.cgrid;
                        let k = ((z >> 4) - b0) * cn + ((x >> 4) - a0);
                        self.ccount[k as usize] = self.ccount[k as usize].saturating_add(1);
                    }
                }
            }
            return;
        }
        if e > EQ_CUT_HALF + pad && !crack && !trench {
            let pv = p.map_or(P_FIXED, |i| i as u8);
            for z in z0..z0 + s {
                for x in x0..x0 + s {
                    if self.in_disc_xz(x, z)
                        && let Some(c) = self.idx(x, z)
                    {
                        self.plate[c] = pv;
                    }
                }
            }
            crate::meter::spend(80 * (s * s) as u64);
            return;
        }
        let q = s / 2;
        for (dx, dz) in [(0, 0), (q, 0), (0, q), (q, q)] {
            self.eval(x0 + dx, z0 + dz, q);
        }
    }
    /// Column c's wall: when the crack reaches the first cut column beside it and the lowest floor of those (none: no
    /// cut column within its 3x3).
    fn wall_of(&self, c: usize) -> Option<(f32, i16)> {
        if self.cutk[c] != 0 || self.plate[c] == P_UNSET {
            return None;
        }
        let (x, z) = self.xz(c);
        let mut out: Option<(f32, i16)> = None;
        for dz in -1..=1 {
            for dx in -1..=1 {
                if let Some(n) = self.idx(x + dx, z + dz).filter(|&n| matches!(self.cutk[n], 1 | 2)) {
                    out = Some(out.map_or((self.cat[n], self.cutf[n]), |(a, f)| (a.min(self.cat[n]), f.min(self.cutf[n]))));
                }
            }
        }
        out
    }
    /// Cut chunk k's columns: its cut columns and the columns within RELIEF of one (each with how far it is, the cut
    /// column its face backs onto, that column's crack time and floor; beside the cut, the soonest and the deepest of
    /// those round it), found by a distance pass over the chunk and RELIEF round it.
    fn cut_items(&self, k: u32) -> Vec<Item> {
        let (a0, b0, cn) = self.cgrid;
        let (i, j) = (k as i32 % cn, k as i32 / cn);
        let (a, b) = (a0 + i, b0 + j);
        let mut out = Vec::new();
        // (no cut column in it or round it: nothing)
        let near = (-1..=1).any(|dj| (-1..=1).any(|di| {
            let (u, v) = (i + di, j + dj);
            u >= 0 && v >= 0 && u < cn && v < cn && self.ccount[(v * cn + u) as usize] > 0
        }));
        crate::meter::spend(2_000);
        if !near {
            return out;
        }
        const W: i32 = 16 + 2 * RELIEF;
        // (each window row's nearest cut column within RELIEF of each of the chunk's x, any and the main fault's: its
        // signed dx, or none)
        let mut row = [[[i8::MAX; 16]; W as usize]; 2];
        let mut any = [false; 2];
        for r in 0..W as usize {
            let z = b * 16 - RELIEF + r as i32;
            let mut line = [0u8; W as usize];
            for (q, l) in line.iter_mut().enumerate() {
                *l = self.idx(a * 16 - RELIEF + q as i32, z).map_or(0, |c| if matches!(self.cutk[c], 1 | 2) { self.cutk[c] } else { 0 });
            }
            for (m, want) in [(0, 1u8), (1, 2u8)] {
                // (the nearest to the left and to the right of each, in two sweeps)
                let (mut left, mut right) = ([i32::MAX; W as usize], [i32::MAX; W as usize]);
                let mut last = i32::MIN / 2;
                for q in 0..W as usize {
                    if line[q] >= want {
                        last = q as i32;
                    }
                    left[q] = q as i32 - last;
                }
                last = i32::MAX / 2;
                for q in (0..W as usize).rev() {
                    if line[q] >= want {
                        last = q as i32;
                    }
                    right[q] = last - q as i32;
                }
                for ix in 0..16 {
                    let q = ix + RELIEF as usize;
                    let (l, rr) = (left[q], right[q]);
                    let d = if l <= rr { -l } else { rr };
                    if d.abs() <= RELIEF {
                        row[m][r][ix] = d as i8;
                        any[m] = true;
                    }
                }
            }
        }
        crate::meter::spend(u64::from(W as u32 * W as u32) * 30);
        for z in b * 16..b * 16 + 16 {
            for x in a * 16..a * 16 + 16 {
                let Some(c) = self.idx(x, z) else { continue };
                crate::meter::spend(4 * PASS_COL);
                if matches!(self.cutk[c], 1 | 2) {
                    out.push(Item { c: c as u32, x, z, at: self.cat[c], floor: self.cutf[c], wall: false, k: 0, ax: 0, az: 0, main: self.cutk[c] == 2 });
                    continue;
                }
                if self.cutk[c] != 0 || self.plate[c] == P_UNSET {
                    continue;
                }
                // (the nearest cut column, Chebyshev, the straighter of equals: the main fault's if one is within RELIEF,
                // so the faces by it are the main fault's whole, else any within RELIEF_SIDE)
                let (ix, iz) = (x - a * 16, z - b * 16);
                let near = |m: usize| {
                    let mut best: Option<(i32, i32, i32, i32)> = None;
                    for dz in -RELIEF..=RELIEF {
                        let dx = row[m][(iz + RELIEF + dz) as usize][ix as usize];
                        if dx == i8::MAX {
                            continue;
                        }
                        let dx = i32::from(dx);
                        let key = (dx.abs().max(dz.abs()), dx.abs() + dz.abs());
                        if best.is_none_or(|bb| key < (bb.0, bb.1)) {
                            best = Some((key.0, key.1, dx, dz));
                        }
                    }
                    best
                };
                crate::meter::spend(600);
                let best = if any[1] { near(1) } else { None }.or_else(|| near(0).filter(|b| b.0 <= RELIEF_SIDE));
                let Some((d, _, dx, dz)) = best else { continue };
                let n = self.idx(x + dx, z + dz).unwrap();
                let (mut at, mut floor) = (self.cat[n], self.cutf[n]);
                // (beside a cut: lined from the deepest floor round it, in place as soon as the first is opened)
                if let Some((a1, f1)) = self.wall_of(c) {
                    (at, floor) = (at.min(a1), floor.min(f1));
                }
                out.push(Item { c: c as u32, x, z, at, floor, wall: true, k: d as u8, ax: dx as i8, az: dz as i8, main: self.cutk[n] == 2 });
            }
        }
        out
    }
    /// Whether every chunk round cut chunk k is worked out (its walls may lie on a cut column across its edge).
    fn cut_ready(&self, k: u32) -> bool {
        let cn = self.cgrid.2;
        let (i, j) = (k as i32 % cn, k as i32 / cn);
        (-1..=1).all(|dj| (-1..=1).all(|di| {
            let (u, v) = (i + di, j + dj);
            u < 0 || v < 0 || u >= cn || v >= cn || self.cdone[(v * cn + u) as usize]
        }))
    }
    /// A wall's ground, as the world answered it, for its lining: one over its highest solid block, a lone tall column
    /// (a trunk) taken at its neighbours' height.
    /// Also whether it is such a trunk (its face is kept whole: the tree left standing on its ground).
    fn wall_ground(&self, x: i32, z: i32) -> Option<(i32, i32, bool)> {
        let g = crate::ground::at(x, z)?;
        let mut low = i32::MAX;
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            if self.idx(x + dx, z + dz).is_some_and(|n| self.cutk[n] == 0)
                && let Some(h) = crate::ground::at(x + dx, z + dz)
            {
                low = low.min(h);
            }
        }
        let wet = crate::ground::water(x, z).unwrap_or(0).max(0);
        let trunk = low < i32::MAX && g > low + 3;
        Some((if trunk { low + 3 } else { g }, wet, trunk))
    }
    /// Land that sinks comes to rest where the world may have a cave's biome (they lie under the land from some 20
    /// down), and its grass and leaves would take that biome's colours as it is swapped in. Under each chunk that sinks
    /// BIOME_SINK or more the land's own biome is put, from under the land now down to under where it comes to rest
    /// (`fillbiome`, the biome asked of the air over the land: a command a biome a chunk, only one of which does
    /// anything; nothing of it shows, the rock has no colours of a biome). A few chunks a tick, from BIOME_AT.
    fn biome_stage(&mut self, q: &mut Plan, now: f32) {
        let (a0, b0, cn) = self.cgrid;
        let (mut made, mut seen) = (0, 0);
        while self.biome_next < (cn * cn) as usize && made < BIOME_CHUNKS && seen < 40 {
            let k = self.biome_next as i32;
            self.biome_next += 1;
            seen += 1;
            crate::meter::spend(30_000);
            let (a, b) = (a0 + k % cn, b0 + k / cn);
            let (mut sink, mut lo, mut hi) = (0, f64::MAX, f64::MIN);
            for (dx, dz) in [(8, 8), (1, 1), (14, 1), (1, 14), (14, 14)] {
                let (x, z) = (a * 16 + dx, b * 16 + dz);
                if let Some(i) = self.pl.column(x, z) {
                    sink = sink.max(-self.offs[i][1]);
                }
                let Some(g) = crate::strike::eq_ground_height(f64::from(x) + 0.5, f64::from(z) + 0.5) else {
                    // (the land's heights never answered: left as it is)
                    self.biome_next = usize::MAX;
                    return;
                };
                (lo, hi) = (lo.min(g), hi.max(g));
            }
            if sink < BIOME_SINK {
                continue;
            }
            made += 1;
            crate::meter::spend(4_000 * BIOMES.len() as u64);
            let (x0, z0) = (a * 16, b * 16);
            let (y0, y1, py) = ((lo as i32 - sink - 24).max(-64), lo as i32 - 6, (hi as i32 + 10).min(319));
            for name in BIOMES {
                q.ev.push((now, Act::Cmd(format!("execute if biome {} {py} {} minecraft:{name} run fillbiome {x0} {y0} {z0} {} {y1} {} minecraft:{name}", x0 + 8, z0 + 8, x0 + 15, z0 + 15))));
            }
        }
    }
    /// A cut chunk's edits (one, or two when the crack crosses it twice), its walls' linings kept for the rest.
    fn cut_edits(&mut self, items: Vec<Item>) -> Vec<(f32, Blocks)> {
        let mut items = items;
        items.sort_by(|a, b| a.at.total_cmp(&b.at));
        // (split once, at the biggest gap in time, when the crack crosses it twice)
        let mut cut_at = items.len();
        if items.len() > 1 && items[items.len() - 1].at - items[0].at > CUT_SPLIT {
            let (mut gap, mut at) = (0.0f32, items.len());
            for k in 1..items.len() {
                let g = items[k].at - items[k - 1].at;
                if g > gap {
                    (gap, at) = (g, k);
                }
            }
            if gap > CUT_SPLIT * 0.5 {
                cut_at = at;
            }
        }
        let mut out = Vec::new();
        self.strata.per_run.set(CUT_RUN);
        for group in [&items[..cut_at], &items[cut_at..]] {
            if group.is_empty() {
                continue;
            }
            let due = group[group.len() / 2].at;
            let mut e = Blocks { urgent: true, sent: Some(self.sent.clone()), ..Default::default() };
            // (the crack past the zone: its walls beside one another, for a trunk's ground)
            let far_walls: HashMap<(i32, i32), ()> = group.iter().filter(|t| t.c == FAR && t.wall).map(|t| ((t.x, t.z), ())).collect();
            for it in group {
                let (x, z) = (it.x, it.z);
                let f = i32::from(it.floor);
                if !it.wall {
                    crate::meter::spend(CUT_COL);
                    // (past the zone, only where the world has the land loaded)
                    if it.c == FAR && crate::ground::at(x, z).is_none() {
                        continue;
                    }
                    put(&mut e, x, z, f, f, "minecraft:deepslate");
                    // (the lake in the main fault's trench: lava over a floor that draws nothing, so that when the
                    // plates part the warp has only the lava's own surface to stretch between them; a sill of rock
                    // where another cut opens into it or it ends, so none flows out)
                    let lake = if it.c == FAR { None } else { self.lake };
                    match lake.map(|l| (l, self.lakek.get(it.c as usize).copied().unwrap_or(0) & !LINED)) {
                        Some((l, 2)) if l - 3 > f => {
                            put(&mut e, x, z, f + 1, l - 3, "minecraft:air");
                            put(&mut e, x, z, l - 2, l - 2, "minecraft:barrier");
                            put(&mut e, x, z, l - 1, l, "minecraft:lava");
                            // (a slab of the lip: its land left standing over one block of air)
                            let top = if self.slabs.iter().any(|s| s.holds(x, z)) { l + 1 } else { 319 };
                            put(&mut e, x, z, l + 1, top, "minecraft:air");
                        }
                        Some((l, 1)) if l - 3 > f => {
                            put(&mut e, x, z, f + 1, l - 3, "minecraft:air");
                            put(&mut e, x, z, l - 2, l + 1, "minecraft:blackstone");
                            put(&mut e, x, z, l + 2, 319, "minecraft:air");
                        }
                        _ => put(&mut e, x, z, f + 1, 319, "minecraft:air"),
                    }
                    continue;
                }
                // (a wall of the main fault on a plate that does not rise: lined from a little under the lake only. What
                // lies under that is never seen, and the lining is most of the cut's work)
                let f = match self.lake {
                    Some(l) if it.main && it.c != FAR => {
                        crate::meter::spend(3_000);
                        if self.pl.column(x, z).is_none_or(|i| self.offs[i][1] <= 0) { f.max(l - 8) } else { f }
                    }
                    _ => f,
                };
                // (a column deep behind a face never let go far: left as it is, behind the lined ones)
                crate::meter::spend(WALL_COL);
                let ground = if it.c == FAR { Self::far_ground(x, z, &far_walls).map(|(g, w)| (g, w, true)) } else { self.wall_ground(x, z) };
                let Some((g, wet, trunk)) = ground else { continue };
                let top = g - 4;
                // (the lake over it, rock too: nothing pours into the cut)
                let (rim0, rim1) = if wet > 0 { (g, g + wet - 1) } else { (1, 0) };
                let keep = trunk || wet > 0 || it.c == FAR;
                let flags = if it.main { F_MAIN } else { 0 } | if keep { F_KEEP } else { 0 };
                let mut w = Wall { top: top as i16, rim0: rim0 as i16, rim1: rim1 as i16, floor: f as i16, ground: g as i16, gnd: g as i16, k: it.k.max(1), ax: it.ax, az: it.az, flags };
                if top > f {
                    let (gnd, soil) = self.strata.line(&mut e, x, z, x, z, &w, 0);
                    w.gnd = gnd as i16;
                    if soil {
                        w.flags |= F_SOIL;
                    }
                }
                if rim1 >= rim0 {
                    let k = self.strata.shift(x, z);
                    self.strata.runs(&mut e, x, z, x, z, rim0, rim1, k);
                }
                // (beside the lake: where the wall's face is let go the lava would run into it and down. A block that
                // draws nothing in the air there, over the lake's depth; the wall is lined again at rest, so none is
                // carried off with it)
                if it.c != FAR
                    && let Some(l) = self.lake
                    && [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|&(dx, dz)| self.idx(x + dx, z + dz).is_some_and(|n| self.lakek[n] & !LINED == 2))
                {
                    crate::meter::spend(400);
                    e.put(x, z, l - 2, l, "minecraft:barrier", Some("minecraft:air"), false);
                }
                if it.c != FAR {
                    self.walls.insert(it.c, w);
                }
            }
            if !e.runs.is_empty() {
                out.push((due, e));
            }
        }
        self.strata.per_run.set(1_500);
        out
    }
    /// A wall of the crack past the zone: its ground as `wall_ground` has it, among the walls beside it in its edit.
    fn far_ground(x: i32, z: i32, walls: &HashMap<(i32, i32), ()>) -> Option<(i32, i32)> {
        let g = crate::ground::at(x, z)?;
        let low = [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().filter(|(dx, dz)| walls.contains_key(&(x + dx, z + dz))).filter_map(|(dx, dz)| crate::ground::at(x + dx, z + dz)).min();
        let wet = crate::ground::water(x, z).unwrap_or(0).max(0);
        Some((low.map_or(g, |l| g.min(l + 3)), wet))
    }
    /// Chunk (a, b)'s columns of the main crack past the zone and their walls (the columns beside them that are no
    /// fault's), worked out from `fault_at` alone.
    fn far_items(&self, a: i32, b: i32) -> Vec<Item> {
        let (bx, bz) = (self.pl.block[0], self.pl.block[2]);
        // (the chunk and a column round it: which are the crack's)
        let mut crack: [Option<(f32, i16)>; 324] = [None; 324];
        let mut any = false;
        for j in 0..18 {
            for i in 0..18 {
                let (x, z) = (a * 16 - 1 + i, b * 16 - 1 + j);
                crate::meter::spend(CRACK_NEAR);
                if !self.pl.crack_near((x - bx) as f32 + 0.5, (z - bz) as f32 + 0.5, 0.0) {
                    continue;
                }
                counted_eval();
                counted_eval();
                if let Some(f) = self.pl.fault_at(x, z).filter(|f| f.crack) {
                    crack[(j * 18 + i) as usize] = Some((f.at, f.floor.clamp(-63, 300) as i16));
                    any = true;
                }
            }
        }
        let mut out = Vec::new();
        if !any {
            return out;
        }
        for j in 1..17 {
            for i in 1..17 {
                let (x, z) = (a * 16 - 1 + i, b * 16 - 1 + j);
                crate::meter::spend(4 * PASS_COL);
                if let Some((at, floor)) = crack[(j * 18 + i) as usize] {
                    out.push(Item { c: FAR, x, z, at, floor, wall: false, k: 0, ax: 0, az: 0, main: true });
                    continue;
                }
                let mut near: Option<(f32, i16)> = None;
                for dj in -1..=1 {
                    for di in -1..=1 {
                        if let Some((at, f)) = crack[((j + dj) * 18 + i + di) as usize] {
                            near = Some(near.map_or((at, f), |(a0, f0)| (a0.min(at), f0.min(f))));
                        }
                    }
                }
                // (a wall: beside the crack and no fault's own column)
                if let Some((at, floor)) = near {
                    counted_eval();
                    counted_eval();
                    if self.pl.fault_at(x, z).is_none() {
                        out.push(Item { c: FAR, x, z, at, floor, wall: true, k: 1, ax: 0, az: 0, main: true });
                    }
                }
            }
        }
        out
    }
    /// The cut's edits whose walls' ground is in, the soonest first, until the stage has spent `upto`.
    fn cut_surveyed(&mut self, q: &mut Plan, now: f32, upto: u64) {
        while let Some((tag, chunks)) = self.surveys.front_mut() {
            if !crate::ground::ready(*tag) {
                break;
            }
            let mut left = std::mem::take(chunks);
            while let Some(items) = left.pop() {
                if crate::meter::spent() + 1_000_000 >= upto {
                    left.push(items);
                    break;
                }
                for (due, e) in self.cut_edits(items) {
                    gate_made(q, due.max(now), e);
                }
            }
            if left.is_empty() {
                self.surveys.pop_front();
            } else {
                self.surveys.front_mut().unwrap().1 = left;
                break;
            }
        }
    }
    /// The chunks with every one round them worked out, the soonest first: their walls' ground asked, in one query.
    fn cut_ready_items(&mut self, q: &mut Plan, now: f32, upto: u64) {
        let mut cols = Vec::new();
        let mut batch = Vec::new();
        let mut keep = Vec::with_capacity(self.cpend.len());
        let pend = std::mem::take(&mut self.cpend);
        for (j, &k) in pend.iter().enumerate() {
            if crate::meter::spent() + 1_000_000 > upto.min(HARD) {
                keep.extend_from_slice(&pend[j..]);
                break;
            }
            if !self.cut_ready(k) {
                keep.push(k);
                continue;
            }
            let items = self.cut_items(k);
            if items.is_empty() {
                continue;
            }
            cols.extend(items.iter().filter(|t| t.wall).map(|t| self.xz(t.c as usize)));
            batch.push(items);
        }
        self.cpend = keep;
        if !batch.is_empty() {
            let tag = crate::ground::new_tag();
            crate::meter::spend(60 * cols.len() as u64);
            q.ev.push((now, Act::Survey { tag, columns: cols }));
            // (taken from the back: the soonest last)
            batch.reverse();
            self.surveys.push_back((tag, batch));
        }
    }
    /// The chunks the crack nears, the soonest first, worked out ahead at a steady pace (as far ahead as it gets): the
    /// zone's, and the main crack's past the zone, worked out on their own, a chunk's columns and walls asked for their
    /// ground together so none is cut where the world has not loaded the land.
    fn cut_ahead(&mut self, q: &mut Plan, now: f32) {
        loop {
            let g = self.corder.get(self.cnext).map(|c| c.1);
            let f = self.far.get(self.far_next).map(|c| c.2);
            let (at, far) = match (g, f) {
                (Some(g), Some(f)) => if f < g { (f, true) } else { (g, false) },
                (Some(g), None) => (g, false),
                (None, Some(f)) => (f, true),
                (None, None) => break,
            };
            if crate::meter::spent() >= CUT_STAGE || crate::meter::spent() + CUT_CHUNK > HARD || at > now + CUT_LOOK {
                break;
            }
            if far {
                let (a, b, _) = self.far[self.far_next];
                self.far_next += 1;
                let items = self.far_items(a, b);
                if !items.is_empty() {
                    let tag = crate::ground::new_tag();
                    crate::meter::spend(60 * items.len() as u64);
                    q.ev.push((now, Act::Survey { tag, columns: items.iter().map(|t| (t.x, t.z)).collect() }));
                    self.surveys.push_back((tag, vec![items]));
                }
                continue;
            }
            let k = self.corder[self.cnext].0;
            let (a0, b0, cn) = self.cgrid;
            let (a, b) = (a0 + k as i32 % cn, b0 + k as i32 / cn);
            self.eval(a * 16, b * 16, 16);
            self.cdone[k as usize] = true;
            self.cpend.push(k);
            self.cnext += 1;
        }
    }
    /// The cut's work this stage: chunks worked out as the crack nears them, their walls' ground asked, their edits made.
    fn cut_stage(&mut self, q: &mut Plan, now: f32) {
        // (what is nearest to being due first: the edits whose walls' ground is in, then the chunks ready for their
        // walls to be asked, then the plates worked out ahead; each with a share of the stage, and what is left after
        // to the first two again)
        for (edits, ready) in [(CUT_STAGE * 9 / 20, CUT_STAGE * 3 / 4), (CUT_STAGE, CUT_STAGE)] {
            self.cut_surveyed(q, now, edits);
            crate::trace("eq cut: edits made");
            self.cut_ready_items(q, now, ready);
            crate::trace("eq cut: items found");
            if ready < CUT_STAGE {
                self.cut_ahead(q, now);
                crate::trace("eq cut: plates ahead");
            }
        }
        #[cfg(test)]
        if std::env::var("EQ_CUTLOG").is_ok() {
            let next = self.corder.get(self.cnext).map_or(0.0, |c| c.1);
            let waiting: usize = self.surveys.iter().map(|s| s.1.iter().map(Vec::len).sum::<usize>()).sum();
            eprintln!("cut {now:.2}: chunk {}/{} next at {next:.2}, far {}/{}, pending {}, waiting items {waiting}, spent {:.1}M", self.cnext, self.corder.len(), self.far_next, self.far.len(), self.cpend.len(), crate::meter::spent() as f64 / 1e6);
        }
        if self.cnext == self.corder.len() && self.cpend.is_empty() && self.surveys.is_empty() && self.far_next == self.far.len() {
            self.cut_built = true;
            self.cat = Vec::new();
        }
    }

    // ---- the read -----------------------------------------------------------------------------------------------------
    /// Columns of an answer taken in, up to what the stage has left: whether it is all in.
    fn take_in(&mut self, a: &crate::columns::Answer, from: usize, upto: &mut usize) -> bool {
        // (the answer's names as the ids written for them, which are two high, which stand on the land)
        let (ids, flags): (Vec<u16>, Vec<(bool, bool)>) = NAMES.with(|n| {
            let mut n = n.borrow_mut();
            a.palette.iter().map(|p| (n.id(p), (two_high(p), stands(p)))).unzip()
        });
        crate::meter::spend(3_000 * a.palette.len() as u64);
        let mut i = from;
        while i < a.columns.len() {
            if crate::meter::spent() >= self.cap {
                *upto = i;
                return false;
            }
            crate::meter::spend(TAKE_COL);
            let (x, z) = a.columns[i];
            let Some(c) = self.idx(x, z) else {
                i += 1;
                continue;
            };
            let Some((top, blocks)) = a.column(i) else {
                self.missing.push((x, z));
                i += 1;
                continue;
            };
            let base = (top - a.below).clamp(-2048, 2047) as i16;
            self.base[c] = base;
            self.slot[c] = self.rle.start(PER);
            let (mut hi, mut gnd, mut n) = (0u8, 0u8, 0u8);
            let (mut cur, mut len) = (u16::MAX, 0u32);
            let mut lower = false;
            for (j, &b) in blocks.iter().take(PER).enumerate() {
                let mut id = ids.get(b as usize).copied().unwrap_or(0);
                let (double, stand) = flags.get(b as usize).copied().unwrap_or((false, true));
                if id != 0 {
                    hi = j as u8 + 1;
                }
                if !stand {
                    gnd = j as u8 + 1;
                }
                // (a two-high block on one of its own: the upper half)
                if double {
                    if lower && blocks[j - 1] == b {
                        id = NAMES.with(|n| n.borrow_mut().upper_of(id));
                        lower = false;
                    } else {
                        lower = true;
                    }
                } else {
                    lower = false;
                }
                if id == cur {
                    len += 1;
                } else {
                    if len > 0 {
                        self.rle.push(u32::from(cur) << 8 | len);
                        n += 1;
                    }
                    (cur, len) = (id, 1);
                }
            }
            if len > 0 {
                self.rle.push(u32::from(cur) << 8 | len);
                n += 1;
            }
            self.hi[c] = hi;
            self.gnd[c] = gnd;
            self.nrun[c] = n;
            i += 1;
        }
        *upto = i;
        true
    }
    fn read_stage(&mut self, q: &mut Plan, now: f32) -> bool {
        if self.asked < self.parts.len() && self.asked < self.taken + FLIGHT {
            let tag = self.tags[self.asked];
            crate::columns::by_ground(tag);
            let columns = self.part_columns(self.asked);
            crate::meter::spend(60 * columns.len() as u64);
            q.ev.push((now, Act::Read { tag, columns, below: BELOW, above: ABOVE }));
            self.asked += 1;
        }
        loop {
            if crate::meter::spent() >= self.cap {
                return false;
            }
            let (a, from) = match self.taking.take() {
                Some(t) => t,
                None => {
                    if self.taken < self.asked
                        && let Some(a) = crate::columns::take(self.tags[self.taken])
                    {
                        self.taken += 1;
                        (a, 0)
                    } else if let Some(tag) = self.retry
                        && let Some(a) = crate::columns::take(tag)
                    {
                        self.retry = None;
                        (a, 0)
                    } else {
                        break;
                    }
                }
            };
            let mut upto = from;
            if !self.take_in(&a, from, &mut upto) {
                self.taking = Some((a, upto));
                return false;
            }
        }
        // (the columns not loaded, asked again a part at a time until EQ_READ_BY; then left alone)
        if !self.read_done && self.taken == self.parts.len() && self.taking.is_none() {
            if let Some(tag) = self.retry
                && now > self.retry_since + 2.0
            {
                crate::columns::forget(tag);
                self.retry = None;
            }
            if self.missing.is_empty() && self.retry.is_none() {
                self.read_done = true;
            } else if now >= EQ_READ_BY {
                if !self.missing.is_empty() {
                    crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("earthquake: {} columns of the land never loaded; left alone", self.missing.len()));
                }
                if let Some(tag) = self.retry.take() {
                    crate::columns::forget(tag);
                }
                self.missing = Vec::new();
                self.read_done = true;
            } else if self.retry.is_none() && now >= self.retry_at && !self.missing.is_empty() {
                let n = self.missing.len().min(PART);
                let cols: Vec<(i32, i32)> = self.missing.drain(..n).collect();
                crate::meter::spend(60 * cols.len() as u64);
                let tag = crate::columns::new_tag();
                crate::columns::by_ground(tag);
                q.ev.push((now, Act::Read { tag, columns: cols, below: BELOW, above: ABOVE }));
                self.retry = Some(tag);
                self.retry_since = now;
                self.retry_at = now + 0.25;
            }
        }
        self.read_done
    }

    // ---- the land at rest ---------------------------------------------------------------------------------------------
    /// A source column's ground (one over its highest block that is the land): a wall lined over a lake, the lake's bed.
    fn src_ground(&self, s: usize) -> i32 {
        if let Some(w) = self.walls.get(&(s as u32)) {
            if w.rim1 >= w.rim0 {
                return i32::from(w.rim0);
            }
            // (its soil let go with its face: its ground as the relief left it, whenever it was read)
            if w.flags & F_SOIL != 0 {
                return i32::from(w.gnd);
            }
        }
        i32::from(self.base[s]) + i32::from(self.gnd[s].max(1))
    }
    /// A column's outcome at rest, and its ground there (one over its land; none for a gap).
    fn decide(&self, c: usize) -> (u8, i16) {
        let pc = self.plate[c];
        if pc == P_UNSET {
            return (W_UNSET, NOT);
        }
        let cut = self.cutk[c] != 0;
        // (not loaded: left alone, a cut column too, which may never have been cut)
        if self.base[c] == NOT {
            return (W_LEAVE, NOT);
        }
        let (x, z) = self.xz(c);
        // (each candidate: its ground at rest, its rise, its index for the tie, the outcome)
        let mut best: Option<(i32, i32, usize, u8)> = None;
        let beats = |a: (i32, i32, usize, u8), b: (i32, i32, usize, u8)| {
            if (a.0 - b.0).abs() > 2 {
                a.0 > b.0
            } else if a.1 != b.1 {
                a.1 > b.1
            } else {
                a.2 < b.2
            }
        };
        let mut take = |cand: (i32, i32, usize, u8)| {
            if best.is_none_or(|b| beats(cand, b)) {
                best = Some(cand);
            }
        };
        if !cut && (pc == P_FIXED || !self.moved[usize::from(pc)]) {
            take((self.src_ground(c), 0, usize::from(pc).min(self.np), W_SELF));
        }
        for i in 0..self.np {
            if !self.moved[i] {
                continue;
            }
            let o = self.offs[i];
            let Some(s) = self.idx(x - o[0], z - o[2]) else { continue };
            if usize::from(self.plate[s]) != i {
                continue;
            }
            if self.base[s] == NOT {
                return (W_LEAVE, NOT);
            }
            take((self.src_ground(s) + o[1], o[1], i, i as u8));
        }
        match best {
            Some(b) => (b.3, b.0.clamp(-64, 400) as i16),
            None => (W_GAP, NOT),
        }
    }
    /// The canyon along the main fault: the gaps out to CANYON_REACH from its cut columns, each with its floor (never into
    /// another fault's cut, which is not as deep).
    fn canyon_seed(&mut self, c: usize) {
        if self.cdist.is_empty() {
            self.cdist = vec![u16::MAX; self.win.len()];
            crate::meter::spend(self.win.len() as u64 * 4);
        }
        self.cdist[c] = 0;
        self.top[c] = self.canyon_floor(c);
        self.cq.push_back(c);
    }
    /// The canyon's spread, so much a stage: whether it is all found.
    fn canyon(&mut self) -> bool {
        while let Some(c) = self.cq.pop_front() {
            crate::meter::spend(GAP_COL);
            self.win[c] = W_CANYON;
            let (x, z) = self.xz(c);
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                if let Some(m) = self.idx(x + dx, z + dz)
                    && self.win[m] == W_GAP
                    && self.cutk[m] != 1
                    && self.cdist[m] == u16::MAX
                    && self.cdist[c] < CANYON_REACH
                {
                    self.cdist[m] = self.cdist[c] + 1;
                    self.top[m] = if self.cutk[m] == 2 { self.canyon_floor(m) } else { self.top[c] };
                    self.cq.push_back(m);
                } else if let Some(m) = self.idx(x + dx, z + dz)
                    && self.cdist[m] == u16::MAX
                {
                    // (beside the canyon and not of it, whatever it is: land, a wall let go, another fault's gap. It
                    // is lined with rock as deep as the lake, so the lava stays in the canyon: `chunk`)
                    self.lakek[m] |= LINED;
                }
            }
            if crate::meter::spent() >= self.cap {
                return false;
            }
        }
        self.cdist = Vec::new();
        true
    }
    /// A canyon column's floor (the lava lies in the two blocks over it): the lake's, or with no lake a little over the
    /// cut's floor.
    fn canyon_floor(&self, c: usize) -> i16 {
        match self.lake {
            Some(l) => (l - 2) as i16,
            None => self.cutf[c] + 3 + (eq_h(self.pl.seed, c as u32, 97) % 3) as i16,
        }
    }
    /// A rubble gap's top: two to four under the lower of the land beside it (the first land along each of the four
    /// ways), higher toward the higher side.
    fn rubble_top(&self, c: usize) -> i16 {
        let (x, z) = self.xz(c);
        let (mut low, mut high, mut nlow, mut nhigh) = (i32::MAX, i32::MIN, 99, 99);
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            for k in 1..=24 {
                let Some(m) = self.idx(x + dx * k, z + dz * k) else { break };
                crate::meter::spend(40);
                match self.win[m] {
                    W_GAP | W_RUBBLE | W_CANYON => continue,
                    w if w == W_SELF || usize::from(w) < self.np => {
                        let t = i32::from(self.top[m]);
                        if t < low {
                            (low, nlow) = (t, k);
                        }
                        if t > high {
                            (high, nhigh) = (t, k);
                        }
                    }
                    _ => {}
                }
                break;
            }
        }
        if low == i32::MAX {
            let own = if self.base[c] != NOT && self.cutk[c] == 0 { i32::from(self.base[c]) + BELOW as i32 - 4 } else { i32::from(self.cutf[c]) + 30 };
            return own as i16;
        }
        let toward = if nhigh < nlow { 2 } else if nhigh == nlow { 1 } else { 0 };
        let h = eq_h(self.pl.seed, c as u32, 98);
        (low - 4 + toward + (h % 2) as i32).min(high - 2) as i16
    }
    /// Scree heaped at the foot of each step down from column c: higher the taller the step, falling away from it.
    fn scree_from(&mut self, c: usize) {
        let t = i32::from(self.top[c]);
        let land = |w: u8, np: usize| w == W_SELF || usize::from(w) < np || w == W_RUBBLE;
        if !land(self.win[c], self.np) {
            return;
        }
        let (x, z) = self.xz(c);
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let Some(n) = self.idx(x + dx, z + dz) else { continue };
            if !land(self.win[n], self.np) {
                continue;
            }
            let tn = i32::from(self.top[n]);
            let step = t - tn;
            if step < 6 {
                continue;
            }
            let h = eq_h(self.pl.seed, c as u32 ^ (n as u32).rotate_left(16), 99);
            let h0 = (step / 3 + (h % 2) as i32).clamp(2, SCREE_MAX);
            for d in 1..=h0 {
                let Some(m) = self.idx(x + dx * d, z + dz * d) else { break };
                if !land(self.win[m], self.np) || i32::from(self.top[m]) > tn + 1 {
                    break;
                }
                let s = (h0 - d + 1) as u8;
                if s > self.scree[m] {
                    self.scree[m] = s;
                }
            }
        }
    }
    /// The log `name` at (sx, y, sz) of the land as read, alone in its column, named with the way it lies if it is one
    /// of a fallen tree's: three or more of the same log in a row along x or z at its height, each with no log over or
    /// under it, two or more of them on the land, and none of that log beside it across the row. None: it stands, or
    /// there is no telling (a mangrove's, a jungle tree's or an acacia's logs stand side by side on end, in the air).
    fn lying_log(&self, sx: i32, sz: i32, y: i32, name: &'static str, names: &[&'static str]) -> Option<&'static str> {
        let at = |x: i32, z: i32, yy: i32| self.idx(x, z).filter(|&n| self.base[n] != NOT).map(|n| self.src_block(n, yy, names));
        let log = |b: Option<&'static str>| b.is_some_and(|b| tree_kind(b) == Kind::Log);
        let lone = |x: i32, z: i32| at(x, z, y) == Some(name) && !log(at(x, z, y + 1)) && !log(at(x, z, y - 1));
        // (first what costs least: the same log beside it one way only)
        let beside = |dx: i32, dz: i32| at(sx + dx, sz + dz, y) == Some(name) || at(sx - dx, sz - dz, y) == Some(name);
        let (dx, dz, way) = match (beside(1, 0), beside(0, 1)) {
            (true, false) => (1, 0, "x"),
            (false, true) => (0, 1, "z"),
            _ => return None,
        };
        crate::meter::spend(3 * LYING_LOG);
        let on_land = |x: i32, z: i32| at(x, z, y - 1).is_some_and(|b| !stands(b));
        let (mut n, mut grounded) = (1, i32::from(on_land(sx, sz)));
        if !lone(sx, sz) {
            return None;
        }
        for sgn in [-1, 1] {
            for k in 1..=12 {
                let (x, z) = (sx + sgn * k * dx, sz + sgn * k * dz);
                if !lone(x, z) {
                    break;
                }
                // (none of it beside the row: two rows side by side are no fallen tree)
                if at(x + dz, z + dx, y) == Some(name) || at(x - dz, z - dx, y) == Some(name) {
                    return None;
                }
                n += 1;
                grounded += i32::from(on_land(x, z));
            }
        }
        if n < 3 || grounded < 2 {
            return None;
        }
        Some(NAMES.with(|m| {
            let mut m = m.borrow_mut();
            let i = m.id(&format!("{name}[axis={way}]"));
            m.list[usize::from(i)]
        }))
    }
    fn src_block(&self, s: usize, y: i32, names: &[&'static str]) -> &'static str {
        let mut at = i32::from(self.base[s]);
        for &r in self.rle.of(self.slot[s], self.nrun[s]) {
            let len = (r & 0xff) as i32;
            if y < at + len {
                return names.get((r >> 8) as usize).copied().unwrap_or("minecraft:air");
            }
            at += len;
        }
        "minecraft:air"
    }
    /// Column c's blocks as read, an id each from its base up.
    fn col_ids(&self, c: usize) -> Vec<u16> {
        let mut v = Vec::with_capacity(PER);
        for &r in self.rle.of(self.slot[c], self.nrun[c]) {
            v.extend(std::iter::repeat_n((r >> 8) as u16, (r & 0xff) as usize));
        }
        v
    }
    /// Column c's blocks read made `ids` (the trees that fall): its runs again, its highest block kept as high as what
    /// really stands there (what the land at rest clears over it).
    fn set_col(&mut self, c: usize, ids: &[u16]) {
        self.slot[c] = self.rle.start(ids.len());
        let (mut n, mut hi) = (0u8, 0u8);
        let mut k = 0;
        while k < ids.len() {
            let id = ids[k];
            let mut len = 1;
            while k + len < ids.len() && ids[k + len] == id && len < 255 {
                len += 1;
            }
            self.rle.push(u32::from(id) << 8 | len as u32);
            n += 1;
            if id != 0 {
                hi = (k + len) as u8;
            }
            k += len;
        }
        self.nrun[c] = n;
        self.hi[c] = self.hi[c].max(hi);
    }
    /// The trees that fall: the trunks within EQ_TREE_REACH of the target on plates that move EQ_TREE_MOVE or more
    /// (a log on the column's ground, EQ_TREE_LOGS of them), then each looked at in a seeded order (`eq_tree_at`), the
    /// ones that can fall kept, a block apart, at most EQ_TREE_CANDS, then those round one place taken (EQ_TREE_CLUSTER: the
    /// copy's cost goes with the circle round them), at most EQ_TREES, each given its time (`eq_tree_when`) and made into the
    /// read as if it had fallen (`eq_tree_edits`). Published for the warp once done. Whether it is done.
    fn tree_stage(&mut self, now: f32) -> bool {
        let reach = EQ_TREE_REACH as i32;
        if !self.trees.started {
            self.trees = Trees { row: -reach, fix: -(reach + TREE_ROOM), started: true, ..Default::default() };
        }
        // (the plates of the columns beside the cut, where the trees are looked for: the rest's are worked out later)
        let far = reach + TREE_ROOM;
        while self.trees.fix <= far {
            if crate::meter::spent() >= self.cap {
                return false;
            }
            let dz = self.trees.fix;
            self.trees.fix += 1;
            let h = f64::from(far * far - dz * dz).sqrt() as i32;
            crate::meter::spend(40 * (2 * h + 1) as u64);
            for dx in -h..=h {
                let (x, z) = (self.cx + dx, self.cz + dz);
                if let Some(c) = self.idx(x, z)
                    && self.plate[c] == P_LATER
                {
                    counted_eval();
                    self.plate[c] = self.pl.column(x, z).map_or(P_FIXED, |i| i as u8);
                }
            }
        }
        let big: Vec<bool> = self.offs.iter().map(|o| f64::from(o[0] * o[0] + o[1] * o[1] + o[2] * o[2]).sqrt() >= f64::from(EQ_TREE_MOVE)).collect();
        let names: Vec<&'static str> = NAMES.with(|n| n.borrow().list.clone());
        let kinds: Vec<Kind> = names.iter().map(|n| tree_kind(n)).collect();
        let logs: Vec<bool> = kinds.iter().map(|k| *k == Kind::Log).collect();
        crate::meter::spend(1_500 * names.len() as u64);
        while self.trees.row <= reach {
            if crate::meter::spent() >= self.cap {
                return false;
            }
            let dz = self.trees.row;
            self.trees.row += 1;
            let h = f64::from(reach * reach - dz * dz).sqrt() as i32;
            crate::meter::spend(TREE_COL * (2 * h + 1) as u64);
            for dx in -h..=h {
                let (x, z) = (self.cx + dx, self.cz + dz);
                let Some(c) = self.idx(x, z) else { continue };
                let p = usize::from(self.plate[c]);
                if p >= self.np || !big[p] || self.base[c] == NOT || self.cutk[c] != 0 {
                    continue;
                }
                // (the logs from the column's ground up)
                let g = usize::from(self.gnd[c].max(1));
                let (mut at, mut n) = (0usize, 0i32);
                for &r in self.rle.of(self.slot[c], self.nrun[c]) {
                    let len = (r & 0xff) as usize;
                    let end = at + len;
                    if end > g {
                        let log = logs.get((r >> 8) as usize).copied().unwrap_or(false);
                        if !log {
                            break;
                        }
                        n += (end - at.max(g)) as i32;
                    }
                    at = end;
                }
                if (EQ_TREE_LOGS.0..=EQ_TREE_LOGS.1).contains(&n) {
                    let hs = eq_h(self.pl.seed, (x as u32).wrapping_mul(0x9e37_79b9) ^ (z as u32).wrapping_mul(0x85eb_ca77), 410);
                    self.trees.sites.push((hs, c as u32, n as u8));
                }
            }
        }
        if !self.trees.sorted {
            crate::meter::spend(200 * self.trees.sites.len() as u64);
            // (in a seeded order; from the player out when they stand where trees are looked for, so the ones that
            // fall are the ones round them)
            match WALKER.with(Cell::get).or(self.walk_at).filter(|m| (m[0] - f64::from(self.cx)).hypot(m[1] - f64::from(self.cz)) <= f64::from(EQ_TREE_REACH + EQ_TREE_SEEN)) {
                Some(m) => {
                    self.trees.from = Some(m);
                    let (x0, z0, w) = (self.x0, self.z0, self.w);
                    self.trees.sites.sort_unstable_by_key(|&(hs, c, _)| {
                        let (x, z) = (x0 + (c as i32) % w, z0 + (c as i32) / w);
                        ((f64::from(x) + 0.5 - m[0]).hypot(f64::from(z) + 0.5 - m[1]) as u32 / 4, hs)
                    });
                }
                None => self.trees.sites.sort_unstable(),
            }
            self.trees.sorted = true;
        }
        while self.trees.next < self.trees.sites.len().min(EQ_TREE_LOOKS) && self.trees.cands.len() < EQ_TREE_CANDS {
            if crate::meter::spent() + TREE_EVAL + TREE_EDIT >= self.cap {
                return false;
            }
            // (round the player every one found is taken: no more looked for than fall)
            if let (Some(m), Some((first, _, _))) = (self.trees.from, self.trees.cands.first())
                && self.trees.cands.len() >= EQ_TREES
                && (f64::from(first.h[0]) + 0.5 - m[0]).hypot(f64::from(first.h[2]) + 0.5 - m[1]) <= f64::from(EQ_TREE_CLUSTER)
            {
                break;
            }
            let (hs, c, n) = self.trees.sites[self.trees.next];
            let c = c as usize;
            let (x, z) = self.xz(c);
            // (from the player out: past the reach of the ones taken, none is: those round the player when the nearest
            // that can fall is that near, else those round it)
            if let (Some(m), Some((first, _, _))) = (self.trees.from, self.trees.cands.first()) {
                let d = |x: i32, z: i32| (f64::from(x) + 0.5 - m[0]).hypot(f64::from(z) + 0.5 - m[1]);
                let d0 = d(first.h[0], first.h[2]);
                let far = if d0 <= f64::from(EQ_TREE_CLUSTER) { 0.0 } else { d0 };
                if d0 <= f64::from(EQ_TREE_SEEN) && d(x, z) > far + f64::from(EQ_TREE_CLUSTER) + 4.0 {
                    break;
                }
            }
            self.trees.next += 1;
            crate::meter::spend(TREE_EVAL);
            let p = usize::from(self.plate[c]);
            let g = i32::from(self.base[c]) + i32::from(self.gnd[c].max(1));
            let found = {
                let mut look = Looker { wk: self, names: &names, kinds: &kinds, cols: FxMap::default() };
                eq_tree_at(&mut look, [x, g, z], i32::from(n), p, eq_tree_ways(self.offs[p], hs)).and_then(|t| {
                    // (a block apart from every other, standing and lying)
                    let r = t.rect();
                    if self.trees.cands.iter().any(|(o, _, _)| {
                        let q = o.rect();
                        r[0] <= q[2] + 2 && q[0] <= r[2] + 2 && r[1] <= q[3] + 2 && q[1] <= r[3] + 2
                    }) {
                        super::eq_trees::why(11);
                        return None;
                    }
                    // (nor down on the player)
                    if let Some(m) = WALKER.with(Cell::get).or(self.walk_at)
                        && f64::from(r[0] - 2) <= m[0]
                        && m[0] <= f64::from(r[2] + 3)
                        && f64::from(r[1] - 2) <= m[1]
                        && m[1] <= f64::from(r[3] + 3)
                    {
                        super::eq_trees::why(11);
                        return None;
                    }
                    let Some(t0) = eq_tree_when(&self.pl, p, now, hs) else {
                        super::eq_trees::why(12);
                        return None;
                    };
                    let t = EqTree { t0, ..t };
                    crate::meter::spend(TREE_EDIT);
                    let edits = eq_tree_edits(&mut look, &t);
                    // (what goes where: the ids, a log laid along the way it lies)
                    let along = if t.e()[0] != 0 { "x" } else { "z" };
                    let mut put: Vec<([i32; 3], u16)> = Vec::with_capacity(edits.len());
                    for (to, from) in edits {
                        let id = match from {
                            None => 0,
                            Some(b) => {
                                let id = look.id_at(b).unwrap_or(0);
                                let name = names.get(usize::from(id)).copied().unwrap_or("minecraft:air");
                                if tree_kind(name) == Kind::Log {
                                    let plain = name.split('[').next().unwrap_or(name);
                                    NAMES.with(|m| m.borrow_mut().id(&format!("{plain}[axis={along}]")))
                                } else {
                                    id
                                }
                            }
                        };
                        put.push((to, id));
                    }
                    let mut cols: Vec<((i32, i32), (i32, Vec<u16>))> = Vec::new();
                    for (to, id) in put {
                        let k = match cols.iter().position(|(xz, _)| *xz == (to[0], to[2])) {
                            Some(k) => k,
                            None => {
                                let col = look.col(to[0], to[2])?.clone();
                                cols.push(((to[0], to[2]), col));
                                cols.len() - 1
                            }
                        };
                        let (base, ids) = &mut cols[k].1;
                        let j = to[1] - *base;
                        if j >= 0 && (j as usize) < ids.len() {
                            ids[j as usize] = id;
                        }
                    }
                    Some((t, cols, hs))
                })
            };
            if let Some(c) = found {
                self.trees.cands.push(c);
            }
        }
        // (those round one place: the copy the warp turns them in is the land within a circle round them all, and its
        // cost goes with that circle's area. The place with the most within EQ_TREE_CLUSTER of it, in the seeded order)
        let cands = std::mem::take(&mut self.trees.cands);
        crate::meter::spend(200 * (cands.len() * cands.len()) as u64);
        let at = |t: &EqTree| [f64::from(t.h[0]) + 0.5, f64::from(t.h[2]) + 0.5];
        let near = |a: [f64; 2], b: &EqTree| (a[0] - at(b)[0]).hypot(a[1] - at(b)[1]) <= f64::from(EQ_TREE_CLUSTER);
        let dense = (0..cands.len()).max_by_key(|&i| (cands.iter().filter(|(b, _, _)| near(at(&cands[i].0), b)).count(), usize::MAX - i)).map(|i| at(&cands[i].0));
        // (but those round the player when one that can fall stands within EQ_TREE_CLUSTER of them, on every side of
        // them; round the one nearest them if it is further off, within EQ_TREE_SEEN: the falls they are there to see)
        let me = WALKER.with(Cell::get).or(self.walk_at);
        let from_me = |t: &EqTree| me.map_or(f64::MAX, |m| (at(t)[0] - m[0]).hypot(at(t)[1] - m[1]));
        let seen = cands.iter().map(|(t, _, _)| *t).min_by(|a, b| from_me(a).total_cmp(&from_me(b))).filter(|t| from_me(t) <= f64::from(EQ_TREE_SEEN));
        let mid = match (seen, me) {
            (Some(t), Some(m)) if from_me(&t) <= f64::from(EQ_TREE_CLUSTER) => Some(m),
            (Some(t), _) => Some(at(&t)),
            _ => dense,
        };
        let found = cands.len();
        for (t, cols, hs) in cands {
            if self.trees.taken.len() >= EQ_TREES || !mid.is_some_and(|m| near(m, &t)) {
                continue;
            }
            // (its time again now it is taken: the looking took some ticks, and none starts to fall before it is known)
            let Some(t0) = eq_tree_when(&self.pl, t.plate, now, hs) else { continue };
            let t = EqTree { t0, ..t };
            self.trees.taken.push(t);
            for ((cx, cz), (_, ids)) in cols {
                if let Some(k) = self.idx(cx, cz) {
                    self.set_col(k, &ids);
                }
            }
        }
        let taken = std::mem::take(&mut self.trees.taken);
        for t in &taken {
            self.tree_log(t);
        }
        self.trees.taken = taken;
        eq_trees_publish(&self.trees.taken, [self.pl.block[0], self.pl.block[1] + 1, self.pl.block[2]]);
        crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("earthquake: {} trees fall (of {} trunks, {} looked at, {found} that could; why not {:?}) at {now:.2} s", self.trees.taken.len(), self.trees.sites.len(), self.trees.next, super::eq_trees::why_take()));
        self.trees.sites = Vec::new();
        self.trees.done = true;
        true
    }
    /// A tree that falls, logged with a place to see it from: across the way it falls, as far as its plate goes on with
    /// room to spare (halfway to its edge, 6 to 20 out), over the ground there (for pictures and checks).
    fn tree_log(&self, t: &EqTree) {
        let e = t.e();
        let side = [-e[1], e[0]];
        let mut best = (0, 1);
        for sgn in [1, -1] {
            let mut k = 0;
            while k < 34 {
                let (x, z) = (t.h[0] + sgn * side[0] * (k + 1), t.h[2] + sgn * side[1] * (k + 1));
                if self.idx(x, z).is_none_or(|c| usize::from(self.plate[c]) != t.plate || self.cutk[c] != 0) {
                    break;
                }
                k += 1;
            }
            if k > best.0 {
                best = (k, sgn);
            }
        }
        crate::meter::spend(40_000);
        let k = (best.0 / 2).clamp(6, 20);
        let (x, z) = (t.h[0] + best.1 * side[0] * k + 3 * e[0], t.h[2] + best.1 * side[1] * k + 3 * e[1]);
        let g = self.idx(x, z).filter(|&c| self.base[c] != NOT).map_or(t.h[1], |c| i32::from(self.base[c]) + i32::from(self.gnd[c].max(1)));
        crate::sdk::log::write(
            crate::sdk::log::Level::Info,
            &format!("earthquake: tree {} {} {} falls {} at {:.2} s, plate {}, top {}, seen from {x} {g} {z}", t.h[0], t.h[1], t.h[2], ["+x", "-x", "+z", "-z"][usize::from(t.dir & 3)], t.t0, t.plate, t.top),
        );
    }
    /// The lowest top at rest of column c's four neighbours, and which way it lies.
    fn exposed(&self, x: i32, z: i32) -> (i32, i8, i8) {
        let mut out = (i32::MAX, 0i8, 0i8);
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            if let Some(m) = self.idx(x + dx, z + dz)
                && self.top[m] != NOT
                && i32::from(self.top[m]) < out.0
            {
                out = (i32::from(self.top[m]), dx as i8, dz as i8);
            }
        }
        out
    }
    /// The chunk grid over the disc: its first chunk and how many a side.
    fn mark(&mut self, c: usize) {
        let (x, z) = self.xz(c);
        let (a, b, n) = self.cgrid;
        if self.marks.is_empty() {
            self.marks = vec![false; (n * n) as usize];
        }
        self.marks[((z >> 4) - b) as usize * n as usize + ((x >> 4) - a) as usize] = true;
    }
    /// The chunks with a column to change, each given its tick: the middle first; the walker's last (round where the
    /// player really stands now, else where they stood as it fired).
    fn list_chunks(&mut self, now: f32) {
        let (a0, b0, n) = self.cgrid;
        let v: Vec<(i32, i32)> = (0..self.marks.len()).filter(|&k| self.marks[k]).map(|k| (a0 + k as i32 % n, b0 + k as i32 / n)).collect();
        crate::meter::spend(20 * self.marks.len() as u64 + 2_000 * v.len() as u64);
        let d = |&(a, b): &(i32, i32)| (f64::from(a * 16 + 8 - self.cx)).hypot(f64::from(b * 16 + 8 - self.cz));
        let at = if self.walk_at.is_some() { WALKER.with(Cell::get).or(self.walk_at) } else { None };
        let rides = |&(a, b): &(i32, i32)| at.is_some_and(|p| (f64::from(a * 16 + 8) - p[0]).hypot(f64::from(b * 16 + 8) - p[1]) < WALK_R + 11.4);
        let (mut late, mut rest): (Vec<_>, Vec<_>) = v.into_iter().partition(rides);
        rest.sort_by(|a, b| d(a).total_cmp(&d(b)));
        late.sort_by(|a, b| d(a).total_cmp(&d(b)));
        // (on whole ticks: never two edits of the same chunk)
        let spread = |list: Vec<(i32, i32)>, t0: f32, t1: f32| {
            let m = list.len().max(1) as f32;
            list.into_iter().enumerate().map(move |(k, (a, b))| (a, b, ((t0 + (t1 - t0) * k as f32 / m) / 0.05).round() * 0.05))
        };
        // (from when they are listed if that is later than EQ_LAND, the read having come in late: none is due before it
        // can be made, so they are made as they fall due and never all at once, a stage at its cap tick after tick)
        let from = EQ_LAND.max(now + 0.5).min(EQ_LAND_END - 4.0);
        self.chunks = spread(rest, from, EQ_LAND_END).chain(spread(late, EQ_RIDER_FROM, EQ_RIDER_TO)).collect();
        crate::meter::spend(300 * self.chunks.len() as u64);
        DUE.with(|d| *d.borrow_mut() = self.chunks.iter().map(|&(a, b, t)| ((a, b), t)).collect());
    }

    /// Chunk (a, b)'s edits: at rest, every column of it to change, written once, as the plates were drawn coming to
    /// rest (the top HIDE of a gap's rubble and every heap of scree left out); and after the swap, what comes down at the
    /// steps' feet (those).
    fn chunk(&mut self, a: i32, b: i32) -> (Blocks, Blocks) {
        // (at rest: nothing put into a player, and what stood where they are put cleared: handed over onto a plate
        // that sank, they are inside the land as it was until this goes in)
        let mut e = Blocks { clear_of_player: true, clear_to_air: true, sent: Some(self.sent.clone()), ..Default::default() };
        // (the scree heaped at a step's foot: never round a player standing there)
        let mut after = Blocks { clear_of_player: true, clear_room: 3, ..Default::default() };
        let names: Vec<&'static str> = NAMES.with(|n| n.borrow().list.clone());
        crate::meter::spend(200 * names.len() as u64);
        // (which ids are a log with no axis written: told once an id, not once a run)
        for n in &names[self.plain_log.len().min(names.len())..] {
            self.plain_log.push(!n.contains('[') && tree_kind(n) == Kind::Log);
        }
        for z in b * 16..b * 16 + 16 {
            for x in a * 16..a * 16 + 16 {
                let Some(c) = self.idx(x, z) else { continue };
                let wn = self.win[c];
                if wn == W_CANYON {
                    crate::meter::spend(CHUNK_COL);
                    self.canyon_col(&mut e, c, x, z);
                } else if wn == W_RUBBLE {
                    crate::meter::spend(CHUNK_COL);
                    self.rubble_col(&mut e, &mut after, c, x, z);
                } else if usize::from(wn) < self.np {
                    crate::meter::spend(CHUNK_COL);
                    self.moved_col(&mut e, c, x, z, usize::from(wn), &names);
                }
                // (beside the canyon: rock from the lake's floor to its lava's top, after the column's own blocks)
                if wn != W_CANYON
                    && self.lakek[c] & LINED != 0
                    && let Some(l) = self.lake
                {
                    crate::meter::spend(CHUNK_COL / 4);
                    let h = eq_h(self.pl.seed, (x as u32).wrapping_mul(0x9e37_79b9) ^ z as u32, 96);
                    put(&mut e, x, z, l - 5, l, ["minecraft:blackstone", "minecraft:basalt", "minecraft:blackstone", "minecraft:smooth_basalt"][(h % 4) as usize]);
                }
                if (wn == W_SELF || usize::from(wn) < self.np) && self.scree[c] > 0 {
                    crate::meter::spend(CHUNK_COL / 4);
                    let g = i32::from(self.top[c]) + 1;
                    self.scree_runs(&mut after, x, z, g, g + i32::from(self.scree[c]) - 1);
                }
            }
        }
        (e, after)
    }
    fn scree_runs(&self, e: &mut Blocks, x: i32, z: i32, y0: i32, y1: i32) {
        const SCREE: [&str; 8] = ["minecraft:cobblestone", "minecraft:gravel", "minecraft:tuff", "minecraft:stone", "minecraft:coarse_dirt", "minecraft:andesite", "minecraft:cobblestone", "minecraft:mossy_cobblestone"];
        for y in y0..=y1 {
            let h = eq_h(self.pl.seed, (x as u32).wrapping_mul(0x9e37_79b9) ^ (z as u32).wrapping_mul(0x85eb_ca77) ^ (y as u32), 93);
            // (no gravel over air: it is laid from the ground up, so only its lowest could; kept to stone there)
            let m = SCREE[(h % 8) as usize];
            put(e, x, z, y, y, if y == y0 && m == "minecraft:gravel" { "minecraft:cobblestone" } else { m });
        }
    }
    /// A canyon column: its floor of blackstone, basalt and magma under two of lava, open above.
    fn canyon_col(&mut self, e: &mut Blocks, c: usize, x: i32, z: i32) {
        let f = i32::from(self.top[c]);
        let cut = self.cutk[c] != 0;
        let low = if cut { i32::from(self.cutf[c]) + 1 } else { f - 3 };
        const DEEP: [&str; 4] = ["minecraft:blackstone", "minecraft:basalt", "minecraft:blackstone", "minecraft:smooth_basalt"];
        const FLOOR: [&str; 4] = ["minecraft:magma_block", "minecraft:blackstone", "minecraft:basalt", "minecraft:magma_block"];
        let h = eq_h(self.pl.seed, (x as u32).wrapping_mul(0x9e37_79b9) ^ z as u32, 94);
        put(e, x, z, low.min(f - 3), f - 4, DEEP[(h % 4) as usize]);
        for y in f - 3..=f {
            put(e, x, z, y, y, FLOOR[((h >> (2 * (y - f + 3) as u32)) % 4) as usize]);
        }
        // (the lake's crust: rafts of dark rock on the lava, rimmed with magma, as the warp drew them forming)
        let top = match self.lake.map(|_| self.pl.crust(x, z)) {
            Some(v) if v >= super::earthquake::EQ_CRUST => ["minecraft:blackstone", "minecraft:basalt", "minecraft:blackstone", "minecraft:smooth_basalt"][(h >> 12) as usize % 4],
            Some(v) if v >= super::earthquake::EQ_CRUST - super::earthquake::EQ_CRUST_RIM => "minecraft:magma_block",
            _ => "minecraft:lava",
        };
        crate::meter::spend(600);
        put(e, x, z, f + 1, f + 1, "minecraft:lava");
        put(e, x, z, f + 2, f + 2, top);
        // (a slab's column: what was left standing in the trench has gone into the lake)
        if cut && self.slabs.iter().any(|s| s.holds(x, z)) {
            put(e, x, z, f + 3, 319, "minecraft:air");
        }
        if !cut {
            let reach = i32::from(self.base[c]) + i32::from(self.hi[c]);
            put(e, x, z, f + 3, reach.max(i32::from(self.base[c]) + BELOW as i32) - 1, "minecraft:air");
        }
    }
    /// A rubble gap's column: rubble from its cut's floor (or its own ground) up to HIDE under its top at rest (the gap
    /// as it was drawn, open), the rest of it and the scree over it after the swap.
    fn rubble_col(&mut self, e: &mut Blocks, after: &mut Blocks, c: usize, x: i32, z: i32) {
        let t = i32::from(self.top[c]);
        let cut = self.cutk[c] != 0;
        let low = if cut { i32::from(self.cutf[c]) + 1 } else { (t - 6).min(i32::from(self.base[c])) };
        let h = eq_h(self.pl.seed, (x as u32).wrapping_mul(0x9e37_79b9) ^ z as u32, 95);
        let fill = ["minecraft:stone", "minecraft:tuff", "minecraft:andesite", "minecraft:cobblestone"][(h % 4) as usize];
        let hide = t - HIDE;
        put(e, x, z, low, hide.min(t - 5), fill);
        if !cut {
            let reach = i32::from(self.base[c]) + i32::from(self.hi[c]);
            put(e, x, z, hide.max(low - 1) + 1, reach - 1, "minecraft:air");
        }
        put(after, x, z, (hide + 1).max(low), t - 5, fill);
        self.scree_runs(after, x, z, (t - 4).max(low).max(hide + 1), t);
    }
    /// A column a moved plate comes to rest on: what lies under it filled (strata on a face, rock inside), the source's
    /// blocks risen or dropped by the plate's rise, air over them up to where this column's own reached. A column lined
    /// as the cut passed is lined again the same (`Strata::line`), so its face at rest is the face drawn moving.
    fn moved_col(&mut self, e: &mut Blocks, c: usize, x: i32, z: i32, i: usize, names: &[&'static str]) {
        let o = self.offs[i];
        let Some(s) = self.idx(x - o[0], z - o[2]) else { return };
        let (sx, sz) = (x - o[0], z - o[2]);
        let bottom = i32::from(self.base[s]) + o[1];
        let g = i32::from(self.top[c]) + 1;
        let cut = self.cutk[c] != 0;
        let low = if cut { i32::from(self.cutf[c]) + 1 } else { i32::from(self.base[c]) };
        let (expose, ex, ez) = self.exposed(x, z);
        let face = expose < g - 3;
        let wall = self.walls.get(&(s as u32)).copied();
        let k = if face || wall.is_some() {
            crate::meter::spend(STRATA_COL);
            self.strata.shift(sx, sz) - o[1]
        } else {
            0
        };
        // (on a face, strata from under what shows; elsewhere rock under what was read)
        let fill_lo = if face { low.min(expose - 2) } else { low };
        // (what is written from the strata or the lining rather than the source's blocks, as heights at rest)
        let (keep0, keep1) = match wall {
            // (behind a step's face: its source's blocks, the lining laid over them where it is in view)
            Some(w) if only_open(&w) => (i32::MAX, i32::MIN),
            Some(w) => {
                let (f, top) = (i32::from(w.floor) + 1, i32::from(w.top));
                let l0 = if w.k >= 2 && w.flags & F_MAIN == 0 { f.max(top - SIDE_RELIEF) } else { f };
                let l1 = if w.flags & F_SOIL != 0 { i32::from(w.ground) + 1 } else { top };
                if top >= f { (l0 + o[1], l1 + o[1]) } else { (i32::MAX, i32::MIN) }
            }
            None if face => (fill_lo, g - 4),
            None => (i32::MAX, i32::MIN),
        };
        let under = keep0.min(bottom) - 1;
        if fill_lo <= under {
            if face {
                self.strata.runs(e, x, z, sx, sz, fill_lo, under, k);
            } else {
                rock(e, self.pl.seed, x, z, fill_lo, under);
            }
        }
        match wall {
            Some(w) if keep0 <= keep1 => {
                self.strata.line(e, x, z, sx, sz, &w, o[1]);
            }
            None if keep0 <= keep1 => self.strata.runs(e, x, z, sx, sz, keep0.max(under + 1), keep1, k),
            _ => {}
        }
        let over = wall.filter(only_open);
        let mut y = bottom;
        for &r in self.rle.of(self.slot[s], self.nrun[s]) {
            let len = (r & 0xff) as i32;
            let name = names.get((r >> 8) as usize).copied().unwrap_or("minecraft:air");
            // (a log lying on the land: the read has no block states, and written plain it would stand on end)
            let name = if len == 1 && self.plain_log.get((r >> 8) as usize).copied().unwrap_or(false) {
                crate::meter::spend(LYING_LOG);
                self.lying_log(sx, sz, y - o[1], name, names).unwrap_or(name)
            } else {
                name
            };
            // (the source's blocks round what the lining wrote)
            if keep0 > keep1 {
                put(e, x, z, y, y + len - 1, name);
            } else {
                for (y0, y1) in [(y, (y + len - 1).min(keep0 - 1)), (y.max(keep1 + 1), y + len - 1)] {
                    if y1 >= y0 {
                        put(e, x, z, y0, y1, name);
                    }
                }
            }
            y += len;
        }
        let y = if keep0 > keep1 { y } else { y.max(keep1 + 1) };
        if let Some(w) = over {
            self.strata.line(e, x, z, sx, sz, &w, o[1]);
        }
        // (a wall's lake rim, kept rock as it was lined)
        if let Some(w) = wall
            && w.rim1 >= w.rim0
        {
            let (r0, r1) = (i32::from(w.rim0) + o[1], i32::from(w.rim1) + o[1]);
            self.strata.runs(e, x, z, sx, sz, r0, r1, k);
            if face && expose < r0 && self.after.breaches.len() < 4 * BREACHES {
                self.after.breaches.push((x, z, r0, r1));
            }
        }
        // (air over it up to where this column's own blocks reached: nothing of what stood here left hanging)
        if !cut {
            let top = i32::from(self.base[c]) + i32::from(self.hi[c]);
            if top > y {
                put(e, x, z, y, top - 1, "minecraft:air");
            }
        }
        // (what is done afterwards here: rock let go off a high edge, water over a drop set flowing)
        if face && expose < g - 10 && self.scree[c] == 0 {
            let name = self.src_block(s, g - 1 - o[1], names);
            if !stands(name) && !name.contains('[') && is_air(self.src_block(s, g - o[1], names)) && self.after.falls.len() < 8 * FALLS {
                self.after.falls.push((x, g - 1, z, ex, ez, name));
            }
        }
        if face && expose < g - 1 && self.after.flows.len() < 4 * FLOWS {
            let over = self.src_block(s, g - o[1], names);
            if is_fluid(over) {
                self.after.flows.push((x + i32::from(ex), g, z + i32::from(ez)));
            }
        }
    }
}
/// A run of `name` up column (x, z), kept in the world's height.
fn put(e: &mut Blocks, x: i32, z: i32, y0: i32, y1: i32, name: &'static str) {
    let (y0, y1) = (y0.max(-64), y1.min(319));
    if y1 >= y0 {
        e.run(x, z, y0, y1, name);
    }
}
/// Rock from y0 to y1 up column (x, z) where nothing shows: stone (deepslate under 0).
fn rock(e: &mut Blocks, _seed: u32, x: i32, z: i32, y0: i32, y1: i32) {
    if y0 < 0 {
        put(e, x, z, y0, y1.min(-1), "minecraft:deepslate");
    }
    put(e, x, z, y0.max(0), y1, "minecraft:stone");
}

/// One stage of the land's work.
fn eq_work(q: &mut Plan, w: Rc<RefCell<Work>>, now: f32) {
    let now = now.max(super::clock());
    let more = {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        stage(q, wk, now)
    };
    let spent = crate::meter::spent();
    PEAK.with(|p| p.set(p.get().max(spent)));
    #[cfg(test)]
    if spent > 17_000_000 {
        eprintln!("heavy stage at {now:.2}: {:.1}M", spent as f64 / 1e6);
    }
    if more && now < EQ_REST + 6.0 {
        q.later(now + 0.05, move |q| eq_work(q, w, now + 0.05));
    } else {
        // (all of it made: what it held let go here)
        GATE.with(|g| g.borrow_mut().done = true);
    }
}

#[cfg(test)]
thread_local! {
    /// In the tests: each part of the work's native time and its count on the meter, summed.
    static PARTS: RefCell<[(f64, u64); 9]> = const { RefCell::new([(0.0, 0); 9]) };
}
/// Each part of a stage timed (in the tests) against what the meter counted for it.
struct Part {
    #[cfg(test)]
    t: std::time::Instant,
    #[cfg(test)]
    m: u64,
}
impl Part {
    fn start() -> Self {
        #[cfg(test)]
        return Part { t: std::time::Instant::now(), m: crate::meter::spent() };
        #[cfg(not(test))]
        Part {}
    }
    #[allow(unused_variables)]
    fn end(self, k: usize) {
        #[cfg(test)]
        PARTS.with(|p| {
            let mut p = p.borrow_mut();
            p[k].0 += self.t.elapsed().as_nanos() as f64;
            p[k].1 += crate::meter::spent() - self.m;
        });
    }
}

/// A stage: whether there is more to do.
fn stage(q: &mut Plan, wk: &mut Work, now: f32) -> bool {
    #[cfg(test)]
    let before = PARTS.with(|p| *p.borrow());
    let mut part = Part::start();
    let mut k = 0;
    let r = stage_parts(q, wk, now, &mut k, &mut part);
    part.end(k);
    #[cfg(test)]
    PARTS.with(|p| {
        let p = p.borrow();
        let d: Vec<(f64, f64)> = (0..9).map(|i| ((p[i].0 - before[i].0) / 1e6, (p[i].1 - before[i].1) as f64 / 1e6)).collect();
        if std::env::var("EQ_PARTS").is_ok_and(|v| d.iter().map(|x| x.0).sum::<f64>() > v.parse::<f64>().unwrap_or(0.7)) {
            eprintln!("stage at {now:.2}: (ms, counted M) by part {:?}", d.iter().map(|(a, b)| ((a * 100.0).round() / 100.0, (b * 10.0).round() / 10.0)).collect::<Vec<_>>());
        }
    });
    r
}
fn next_part(part: &mut Part, k: &mut usize, to: usize) {
    if *k != to {
        crate::trace(["earthquake land: cut", "earthquake land: read", "earthquake land: decide", "earthquake land: canyon", "earthquake land: gaps", "earthquake land: scree", "earthquake land: mark", "earthquake land: chunks", "earthquake land: trees"][to]);
        std::mem::replace(part, Part::start()).end(*k);
        *k = to;
    }
}
fn stage_parts(q: &mut Plan, wk: &mut Work, now: f32, kp: &mut usize, part: &mut Part) -> bool {
    wk.cap = if wk.cut_built { REST_STAGE } else { STAGE };
    // (the slabs of the lip, before any of the cut is made: the cut leaves them standing)
    if !wk.slabs_said {
        wk.slabs = find_slabs(&wk.pl);
        eq_slabs_publish(&wk.slabs, [wk.pl.block[0], wk.pl.block[1] + 1, wk.pl.block[2]]);
        wk.slabs_said = true;
        #[cfg(not(test))]
        crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("earthquake: {} slabs of the lip come away: {:?}", wk.slabs.len(), wk.slabs.iter().map(|s| (s.lo, s.hi, s.t0, s.amax as i32, s.fall as i32)).collect::<Vec<_>>()));
        // (a stage of its own: the cut begins with the next)
        return true;
    }
    if wk.pl.rest && now >= BIOME_AT {
        wk.biome_stage(q, now);
    }
    // the cut first: it keeps pace with the crack
    if !wk.cut_built {
        wk.cut_stage(q, now);
    }
    if std::mem::replace(&mut wk.said.0, wk.cut_built) != wk.cut_built {
        crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("earthquake land: the cut made at {now:.2} s"));
    }
    // the trees that fall, as soon as the cut is made and the land round the target is read (made into the read before
    // anything at rest is worked out from it), so they can fall with the plates' lurches
    if wk.cut_built && !wk.trees.done && (wk.taken > wk.tree_parts || (wk.taken == wk.tree_parts && wk.taking.is_none())) {
        next_part(part, kp, 8);
        if !wk.tree_stage(now) {
            return true;
        }
    }
    // the read, beside it (the trees' disc of it whatever the cut took, so it is in by the time the cut is made)
    next_part(part, kp, 1);
    if !wk.cut_built && (wk.taken < wk.tree_parts || (wk.taken == wk.tree_parts && wk.taking.is_some())) {
        wk.cap = wk.cap.max((crate::meter::spent() + TREE_READ).min(TREE_READ_TOP));
    }
    let read = wk.read_stage(q, now);
    if std::mem::replace(&mut wk.said.1, read) != read {
        crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("earthquake land: the read in at {now:.2} s, {} plates' columns to work out", wk.later.len()));
    }
    if !wk.cut_built || !read {
        return true;
    }
    let n = wk.plate.len();
    // the plates of the columns beside the cut, worked out now the crack has passed
    while wk.later_done < wk.later.len() {
        if crate::meter::spent() >= wk.cap {
            return true;
        }
        let c = wk.later[wk.later_done] as usize;
        wk.later_done += 1;
        if wk.plate[c] != P_LATER {
            continue;
        }
        counted_eval();
        let (x, z) = wk.xz(c);
        wk.plate[c] = wk.pl.column(x, z).map_or(P_FIXED, |i| i as u8);
    }
    wk.later = Vec::new();
    // (the trees, if their rows came in last of all)
    next_part(part, kp, 8);
    if !wk.trees.done && !wk.tree_stage(now) {
        return true;
    }
    // every column's outcome at rest, and its ground there
    next_part(part, kp, 2);
    // (the passes over the grid: their real work in the game is over twice what the meter counts of it)
    wk.cap = wk.cap.min(PASS_STAGE);
    if wk.win.is_empty() {
        wk.win = vec![W_UNSET; n];
        wk.top = vec![NOT; n];
        wk.scree = vec![0; n];
        crate::meter::spend(n as u64 * 2);
    }
    while wk.pass.decided < n {
        if crate::meter::spent() >= wk.cap {
            return true;
        }
        let c = wk.pass.decided;
        wk.pass.decided += 1;
        if wk.plate[c] == P_UNSET {
            crate::meter::spend(70);
            continue;
        }
        crate::meter::spend(DECIDE_COL + 60 * wk.np as u64);
        let (o, g) = wk.decide(c);
        // (the crack past the zone: left as it was cut, nothing laid in it at rest)
        let o = if o == W_GAP && wk.cutk[c] == 3 { W_LEAVE } else { o };
        wk.win[c] = o;
        if o == W_GAP && wk.cutk[c] == 2 {
            wk.canyon_seed(c);
        }
        if g != NOT {
            wk.top[c] = g - 1;
        }
    }
    // the canyon (one stage of its own), the rubble's tops
    next_part(part, kp, 3);
    if !wk.pass.canyon {
        if !wk.canyon() {
            return true;
        }
        wk.pass.canyon = true;
    }
    next_part(part, kp, 4);
    while wk.pass.gaps < n {
        if crate::meter::spent() >= wk.cap {
            return true;
        }
        let c = wk.pass.gaps;
        wk.pass.gaps += 1;
        if wk.win[c] == W_GAP {
            wk.win[c] = W_RUBBLE;
        }
        if wk.win[c] != W_RUBBLE {
            crate::meter::spend(70);
            continue;
        }
        crate::meter::spend(GAP_COL);
        wk.top[c] = wk.rubble_top(c);
    }
    // the scree at the steps' feet
    next_part(part, kp, 5);
    while wk.pass.scree < n {
        if crate::meter::spent() >= wk.cap {
            return true;
        }
        let c = wk.pass.scree;
        wk.pass.scree += 1;
        if wk.top[c] == NOT {
            crate::meter::spend(70);
            continue;
        }
        crate::meter::spend(SCREE_COL);
        wk.scree_from(c);
    }
    // the chunks to change
    next_part(part, kp, 6);
    while wk.pass.marked < n {
        if crate::meter::spent() >= wk.cap {
            return true;
        }
        let c = wk.pass.marked;
        wk.pass.marked += 1;
        crate::meter::spend(70);
        let wn = wk.win[c];
        if wn == W_CANYON || wn == W_RUBBLE || usize::from(wn) < wk.np || (wn == W_SELF && wk.scree[c] > 0) || wk.lakek[c] & LINED != 0 {
            wk.mark(c);
        }
    }
    if wk.chunks.is_empty() {
        if crate::meter::spent() + 2_000_000 >= wk.cap {
            return true;
        }
        wk.list_chunks(now);
        // (what is no longer needed let go now: the plates and the read's bookkeeping)
        wk.plate = Vec::new();
        wk.missing = Vec::new();
        if wk.chunks.is_empty() {
            return false;
        }
        return true;
    }
    // the chunks, each a stage LEAD before it is due, as many as the stage holds
    next_part(part, kp, 7);
    wk.cap = REST_STAGE;
    while wk.next < wk.chunks.len() {
        let (a, b, due) = wk.chunks[wk.next];
        // (and none while EQ_WAITING runs wait to go in: on land that came late every chunk is due at once, and made
        // as fast as the stages allow they pile up in the mod's memory, which is 64 MB)
        if due - LEAD > now || crate::meter::spent() + wk.chunk_cost > wk.cap || gate_waiting() > EQ_WAITING {
            return true;
        }
        let before = crate::meter::spent();
        let (e, after) = wk.chunk(a, b);
        wk.chunk_cost = wk.chunk_cost.max(crate::meter::spent() - before);
        wk.next += 1;
        if !after.runs.is_empty() {
            let mid = ((a * 16 + 8 - wk.pl.block[0]) as f32, (b * 16 + 8 - wk.pl.block[2]) as f32);
            let along = (mid.0 * wk.pl.fdir[0] + mid.1 * wk.pl.fdir[1]).abs();
            wk.post.push((along, after));
        }
        if e.runs.is_empty() {
            continue;
        }
        gate_made(q, due.max(now), e);
    }
    afterwards(q, wk);
    false
}

/// What is done once the land is at rest, worked out with the last chunk and played from the swap (`post_swap`): lake
/// rims breached and water over a drop set flowing (a block changed beside it, which the water hears), rock let go off
/// the cliffs' edges, and the rubble and scree coming down at the steps' feet, chunk by chunk out along the main fault
/// from the target, most of it in the first three seconds.
fn afterwards(q: &mut Plan, wk: &mut Work) {
    let seed = wk.pl.seed;
    let pick = |n: usize, want: usize, salt: u32| -> Vec<usize> {
        if n <= want {
            return (0..n).collect();
        }
        // (spread evenly over what was found, which lies in the chunks' order: from the middle out)
        (0..want).map(|k| (k * n / want + (eq_h(seed, salt, k as u32) as usize % (n / want).max(1))).min(n - 1)).collect()
    };
    let mut cmds: Vec<(f32, String)> = Vec::new();
    let breaches: Vec<_> = pick(wk.after.breaches.len(), BREACHES, 1).into_iter().map(|k| wk.after.breaches[k]).collect();
    for (k, (x, z, y0, y1)) in breaches.iter().enumerate() {
        cmds.push((0.6 + 0.12 * k as f32, format!("fill {x} {y0} {z} {x} {y1} {z} minecraft:air")));
    }
    let flows = pick(wk.after.flows.len(), FLOWS.saturating_sub(breaches.len()), 2);
    // (water runs in: it is heard, from POUR_MIN places up)
    if breaches.len() + flows.len() >= POUR_MIN {
        super::earthquake::eq_pour(q, &wk.pl);
    }
    #[cfg(not(test))]
    crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("earthquake: water set flowing at {} places", breaches.len() + flows.len()));
    for (k, &i) in flows.iter().enumerate() {
        let (x, y, z) = wk.after.flows[i];
        // (two a tick: the water's updates spread out)
        let t = 0.3 + 0.025 * k as f32;
        cmds.push((t, format!("setblock {x} {y} {z} minecraft:stone")));
        cmds.push((t + 0.05, format!("setblock {x} {y} {z} minecraft:air")));
    }
    let want = FALLS.min(wk.after.falls.len());
    let falls = pick(wk.after.falls.len(), want, 3);
    for (k, &i) in falls.iter().enumerate() {
        let (x, y, z, dx, dz, name) = wk.after.falls[i];
        let u = k as f32 / want.max(1) as f32;
        let t = 0.25 + 9.0 * u * u * u;
        let h = eq_h(seed, 0xfa11, k as u32);
        let v = 0.18 + 0.12 * (h % 100) as f32 / 100.0;
        cmds.push((t, format!("setblock {x} {y} {z} minecraft:air")));
        cmds.push((
            t,
            format!(
                "summon minecraft:falling_block {:.2} {y} {:.2} {{BlockState:{{Name:\"{name}\"}},Time:1,DropItem:0b,Motion:[{:.2},0.12,{:.2}]}}",
                f64::from(x) + 0.5,
                f64::from(z) + 0.5,
                f32::from(dx) * v,
                f32::from(dz) * v
            ),
        ));
    }
    crate::meter::spend(2_500 * cmds.len() as u64);
    wk.after = After { falls: Vec::new(), flows: Vec::new(), breaches: Vec::new() };
    let mut post = std::mem::take(&mut wk.post);
    post.sort_by(|a, b| a.0.total_cmp(&b.0));
    let n = post.len().max(1) as f32;
    let edits: Vec<(f32, Blocks)> = post.into_iter().enumerate().map(|(k, (_, e))| (POST_T0 + POST_LEN * (k as f32 / n).powi(2), e)).collect();
    q.later(EQ_REST, move |q| post_swap(q, cmds, edits, EQ_REST));
}
/// The rubble and scree come down from POST_T0 after the swap, the last POST_T0 + POST_LEN after it.
const POST_T0: f32 = 0.45;
const POST_LEN: f32 = 8.5;
/// What is done once the land is at rest, from the tick the hold lets go (it waits at rest while an edit is still out:
/// `eq_land_in`), on the strike's clock from then, so none of it is in the land swapped in.
fn post_swap(q: &mut Plan, cmds: Vec<(f32, String)>, edits: Vec<(f32, Blocks)>, now: f32) {
    let now = now.max(super::clock());
    if !eq_land_in() && now < EQ_HOLD_START + EQ_HOLD_MAX {
        q.later(now + 0.05, move |q| post_swap(q, cmds, edits, now + 0.05));
        return;
    }
    let tick = |t: f32| ((now + t) / 0.05).round() * 0.05;
    for (t, c) in cmds {
        q.at(tick(t), c);
    }
    let edits: VecDeque<(f32, Blocks)> = edits.into_iter().map(|(t, e)| (tick(t), e)).collect();
    post_edits(q, edits, now);
}
/// How far ahead of its time an edit after the swap is handed over, and the most runs a stage hands over.
const POST_AHEAD: f32 = 0.25;
const POST_RUNS: usize = 4_000;
/// The edits after the swap, in time order, handed over a few ticks' worth a stage: a stage is counted by the runs it
/// gives, so all of them given at once were a tick far over its fuel on the meter.
fn post_edits(q: &mut Plan, mut edits: VecDeque<(f32, Blocks)>, now: f32) {
    let now = now.max(super::clock());
    let mut runs = 0;
    while let Some((t, e)) = edits.front() {
        if runs > 0 && (*t > now + POST_AHEAD || runs + e.runs.len() > POST_RUNS) {
            break;
        }
        runs += e.runs.len().max(1);
        let Some((t, e)) = edits.pop_front() else { break };
        q.ev.push((t.max(now), Act::Blocks(Box::new(e))));
    }
    if let Some(&(t, _)) = edits.front() {
        let next = (t - POST_AHEAD + 0.05).max(now + 0.05);
        q.later(next, move |q| post_edits(q, edits, next));
    }
}

/// The mobs and items on a moved plate are tagged by 16-block cells (a cell whose middle and corners all lie on the plate)
/// at EQ_RIDE_TAG, and at rest each plate's are moved by its offset with one `tp`, so they stand where they stood on the land
/// that moved under them. Players are left alone. Those near a boundary stay where they are.
const EQ_RIDE_TAG: f32 = EQ_REST - 0.5;
const RIDE_BANDS: i32 = 6;
fn riders(q: &mut Plan, pl: &EqPlates, r: f64, band: i32) {
    let (bx, bz) = (pl.block[0], pl.block[2]);
    let n = (r / 16.0).ceil() as i32 + 1;
    let (a0, b0) = (bx >> 4, bz >> 4);
    for b in (b0 - n..=b0 + n).filter(|b| (b - (b0 - n)) % RIDE_BANDS == band) {
        for a in a0 - n..=a0 + n {
            let (x, z) = (a * 16, b * 16);
            if f64::from(x + 8 - bx).hypot(f64::from(z + 8 - bz)) > r {
                continue;
            }
            crate::meter::spend(5 * EVAL);
            let Some(i) = pl.column(x + 8, z + 8) else { continue };
            if pl.offset(i) == [0; 3] || [(0, 0), (15, 0), (0, 15), (15, 15)].iter().any(|&(dx, dz)| pl.column(x + dx, z + dz) != Some(i)) {
                continue;
            }
            q.at(EQ_RIDE_TAG, format!("tag @e[type=!minecraft:player,x={x},y=-64,z={z},dx=15,dy=384,dz=15] add orbital_eq_ride{i}"));
        }
    }
    let spent = crate::meter::spent();
    PEAK.with(|p| p.set(p.get().max(spent)));
    // (each plate's tp once, from the last band, after every band's tags)
    if band != RIDE_BANDS - 1 {
        return;
    }
    for i in 0..EQ_PLATES {
        let o = pl.offset(i);
        if o != [0; 3] {
            q.at(EQ_REST, format!("execute as @e[tag=orbital_eq_ride{i}] at @s run tp @s ~{} ~{} ~{}", o[0], o[1], o[2]));
            q.at(EQ_REST, format!("tag @e[tag=orbital_eq_ride{i}] remove orbital_eq_ride{i}"));
        }
    }
}

/// The chunks of the work's disc, a row of chunks a rectangle (x0, z0, x1, z1).
fn load_rows(cx: f64, cz: f64, r: f64) -> Vec<[i32; 4]> {
    let (z0, z1) = (((cz - r).floor() as i32) >> 4, ((cz + r).floor() as i32) >> 4);
    (z0..=z1)
        .filter_map(|c| {
            let (zl, zh) = (f64::from(c * 16), f64::from(c * 16 + 16));
            let d = if cz < zl { zl - cz } else if cz > zh { cz - zh } else { 0.0 };
            (d <= r).then(|| {
                let w = (r * r - d * d).sqrt();
                [((cx - w).floor() as i32 >> 4) * 16, c * 16, ((cx + w).floor() as i32 >> 4) * 16 + 15, c * 16 + 15]
            })
        })
        .collect()
}

/// The land's plan (terrain on, the plates resting displaced): the disc kept loaded from the fire to after the last edit,
/// and the chain of stages that cuts the faults, reads the land and moves it.
#[allow(clippy::clone_on_copy)]
pub(super) fn eq_land(p: &mut Plan, pl: &EqPlates, me: [f64; 3]) {
    gate_reset(pl.rest);
    eq_trees_reset();
    PEAK.with(|k| k.set(0));
    if !pl.rest {
        return;
    }
    let pl = pl.clone();
    let me = Some(me);
    let maxh = (0..EQ_PLATES).map(|i| offset_of(&pl, i)).map(|o| f64::from(o[0] * o[0] + o[2] * o[2]).sqrt()).fold(0.0, f64::max);
    let (mid, zr) = pl.zone();
    let r = zr + maxh + 7.0;
    let rows = load_rows(mid[0], mid[1], r);
    for [x0, z0, x1, z1] in &rows {
        p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
    }
    // (on the spare budget, which waits for the edits: let go after the last is in)
    for [x0, z0, x1, z1] in &rows {
        p.ev.push((EQ_REST + 14.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
    }
    // (what lives on the moved plates rides with them: `riders`, a band of rows of cells a stage, round the target, so
    // as far again as the zone's middle is from it)
    let rr = r + (mid[0] - f64::from(pl.block[0]) - 0.5).hypot(mid[1] - f64::from(pl.block[2]) - 0.5);
    for k in 0..RIDE_BANDS {
        let pl = pl.clone();
        p.later(EQ_RIDE_TAG - 1.0 + 0.05 * k as f32, move |q| riders(q, &pl, rr, k));
    }
    // (its state made on a stage of its own: the disc's grids are some megabytes)
    p.later(0.05, move |q| {
        crate::meter::spend(4_000_000);
        let work = Rc::new(RefCell::new(Work::new(pl, me)));
        GATE.with(|g| g.borrow_mut().sent = work.borrow().sent.clone());
        q.later(0.1, move |q| eq_work(q, work, 0.1));
    });
}

#[cfg(test)]
pub(super) fn stage_peak() -> u64 {
    PEAK.with(Cell::get)
}

#[cfg(test)]
mod tests {
    use super::super::earthquake::{EQ_CUT_MAIN_Y, EQ_CUT_Y, eq_plates};
    use super::super::{Target, sim};
    use super::*;
    use std::collections::{BTreeMap, HashSet};

    // ---- a synthetic land: hills, a lake, trees ------------------------------------------------------------------------
    fn hh(x: i32, z: i32, k: u32) -> u32 {
        eq_h(4242, (x as u32).wrapping_mul(0x8da6_b343) ^ (z as u32).wrapping_mul(0xd816_3841), k)
    }
    fn ground_h(x: i32, z: i32) -> i32 {
        let (fx, fz) = (x as f64, z as f64);
        let lake = 12.0 * (-((fx - 70.0).powi(2) + (fz + 50.0).powi(2)) / 1200.0).exp();
        (66.0 + 6.0 * (fx / 23.0).sin() * (fz / 31.0).cos() + 4.0 * ((fx + fz) / 17.0).sin() - lake).round() as i32
    }
    const SEA: i32 = 60;
    /// A tree's trunk at (x, z), if one stands there: on a grid of 11 with a jitter, on dry land.
    fn trunk(x: i32, z: i32) -> bool {
        let (gx, gz) = (x.div_euclid(11), z.div_euclid(11));
        let h = hh(gx, gz, 1);
        x == gx * 11 + 2 + (h % 7) as i32 && z == gz * 11 + 2 + ((h >> 8) % 7) as i32 && ground_h(x, z) > SEA
    }
    fn tree_near(x: i32, z: i32) -> Option<(i32, i32)> {
        for dz in -2..=2 {
            for dx in -2..=2 {
                if trunk(x + dx, z + dz) {
                    return Some((x + dx, z + dz));
                }
            }
        }
        None
    }
    /// The synthetic land's block: a cave band and ore here and there underground, so a wall's lining can be seen.
    pub(super) fn land_block(x: i32, y: i32, z: i32) -> &'static str {
        let g = ground_h(x, z);
        if y < 0 {
            return "minecraft:deepslate";
        }
        if y < g - 3 {
            if (30..33).contains(&y) && hh(x / 3, z / 3, 5) % 3 == 0 {
                return "minecraft:cave_air";
            }
            if hh(x, z, 6 + y as u32) % 40 == 0 {
                return "minecraft:coal_ore";
            }
            return "minecraft:stone";
        }
        if y < g {
            return "minecraft:dirt";
        }
        if y == g {
            return if g <= SEA { "minecraft:sand" } else { "minecraft:grass_block" };
        }
        if y <= SEA {
            return "minecraft:water";
        }
        if let Some((tx, tz)) = tree_near(x, z) {
            let tg = ground_h(tx, tz);
            if tx == x && tz == z && y <= tg + 5 {
                return "minecraft:oak_log";
            }
            let d = (x - tx).abs().max((z - tz).abs());
            if (y >= tg + 4 && y <= tg + 6 && d <= 2) || (y == tg + 7 && d <= 1) {
                return "minecraft:oak_leaves";
            }
        }
        if y == g + 1 && lying(x, z).is_some() {
            return "minecraft:birch_log";
        }
        if y == g + 1 && hh(x, z, 2) % 5 == 0 {
            return "minecraft:short_grass";
        }
        "minecraft:air"
    }
    /// A fallen tree's log lying on the ground at (x, z), and the way it lies: five in a row along x or z here and
    /// there on a grid of 29, on dry level ground clear of the trees.
    fn lying(x: i32, z: i32) -> Option<&'static str> {
        let (cx, cz) = (x.div_euclid(29), z.div_euclid(29));
        let h = hh(cx, cz, 77);
        if h % 3 != 0 {
            return None;
        }
        let (ox, oz) = (cx * 29 + 12, cz * 29 + 14);
        let (way, cells): (&'static str, Vec<(i32, i32)>) = if (h >> 4) & 1 == 0 { ("x", (0..5).map(|k| (ox + k, oz)).collect()) } else { ("z", (0..5).map(|k| (ox + 2, oz - 2 + k)).collect()) };
        let g = ground_h(ox, oz);
        (cells.contains(&(x, z)) && g > SEA && cells.iter().all(|&(a, b)| ground_h(a, b) == g && tree_near(a, b).is_none())).then_some(way)
    }
    /// The ground the world's `surface-height` gives: the first air over solid ground (logs count, water does not).
    fn survey(x: i32, z: i32) -> Option<i32> {
        Some(if trunk(x, z) { ground_h(x, z) + 6 } else if lying(x, z).is_some() { ground_h(x, z) + 2 } else { ground_h(x, z) + 1 })
    }
    fn survey_wet(x: i32, z: i32) -> Option<i32> {
        let g = ground_h(x, z);
        (g < SEA).then_some(SEA - g)
    }

    // ---- the world as edited, column by column ------------------------------------------------------------------------
    const Y0: i32 = -64;
    const YN: usize = 384;
    struct World {
        names: Vec<&'static str>,
        cols: HashMap<(i32, i32), Vec<u8>>,
    }
    impl World {
        fn new() -> Self {
            World { names: vec!["minecraft:air"], cols: HashMap::new() }
        }
        fn id(&mut self, n: &'static str) -> u8 {
            match self.names.iter().position(|m| *m == n) {
                Some(i) => i as u8,
                None => {
                    self.names.push(n);
                    (self.names.len() - 1) as u8
                }
            }
        }
        fn col(&mut self, x: i32, z: i32) -> &mut Vec<u8> {
            if !self.cols.contains_key(&(x, z)) {
                let v: Vec<u8> = (0..YN).map(|k| land_block(x, Y0 + k as i32, z)).collect::<Vec<_>>().into_iter().map(|n| self.id(n)).collect();
                self.cols.insert((x, z), v);
            }
            self.cols.get_mut(&(x, z)).unwrap()
        }
        fn at(&mut self, x: i32, y: i32, z: i32) -> &'static str {
            if y < Y0 || y >= Y0 + YN as i32 {
                return "minecraft:air";
            }
            let k = (y - Y0) as usize;
            let i = self.col(x, z)[k] as usize;
            self.names[i]
        }
        fn apply(&mut self, b: &Blocks) {
            for r in &b.runs {
                let name = b.palette[r.block as usize];
                let id = self.id(name);
                // (a filtered run: only over the block it names, or the leaves of its tag)
                let only = r.only.map(|f| b.filters[f as usize]);
                let pass: Option<Vec<bool>> = only.map(|f| self.names.iter().map(|n| if f == "#minecraft:leaves" { n.contains("leaves") } else { *n == f }).collect());
                let col = self.col(r.x, r.z);
                for y in r.y..r.y + r.height as i32 {
                    if y >= Y0 && ((y - Y0) as usize) < YN && pass.as_ref().is_none_or(|p| p.get(col[(y - Y0) as usize] as usize).copied().unwrap_or(false)) {
                        col[(y - Y0) as usize] = id;
                    }
                }
            }
        }
        /// The column as the world reads it now: from one over its highest motion-blocking block (leaves and plants left
        /// out), `below` under it and `above` from it up.
        fn read(&mut self, x: i32, z: i32, below: u32, above: u32) -> (i32, Vec<&'static str>) {
            let c = self.col(x, z).clone();
            let top = c
                .iter()
                .rposition(|&b| {
                    let n = self.names[b as usize];
                    !is_air(n) && !n.contains("leaves") && n != "minecraft:short_grass"
                })
                .map_or(Y0, |k| Y0 + k as i32 + 1);
            let v = (top - below as i32..top + above as i32).map(|y| self.at(x, y, z)).collect();
            (top, v)
        }
        /// One over the highest block that is the land (as `stands` has it).
        fn ground(&mut self, x: i32, z: i32) -> i32 {
            let c = self.col(x, z).clone();
            c.iter().rposition(|&b| !stands(self.names[b as usize])).map_or(Y0, |k| Y0 + k as i32 + 1)
        }
    }

    fn plan_eq(me: [f64; 3], seed: u32) -> Vec<(f32, Act)> {
        crate::strike::plan(&crate::lasers::EARTHQUAKE, &target(), true, "minecraft:overworld", seed as f32, me, 0)
    }
    fn target() -> Target {
        Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] }
    }
    struct Run {
        pl: EqPlates,
        me: [f64; 3],
        cmds: Vec<(f32, String)>,
        edits: Vec<(f32, f32, Blocks)>,
        stages: Vec<(f32, f32, f64)>,
        peak: u64,
        world: World,
    }
    /// A strike played against the synthetic land, the world's reads answered from the land as the edits have left it.
    fn run_with(seed: u32, me: [f64; 3], hole: Option<fn(i32, i32) -> bool>) -> Run {
        crate::ground::set_test(Some(survey));
        crate::ground::set_test_wet(Some(survey_wet));
        let pl = eq_plates(&target(), me, seed as f32, true);
        let ev = plan_eq(me, seed);
        let world = RefCell::new(World::new());
        let mut edits = Vec::new();
        let answer = |x: i32, z: i32, b: u32, a: u32| {
            if hole.is_some_and(|h| h(x, z)) {
                return None;
            }
            Some(world.borrow_mut().read(x, z, b, a))
        };
        let played = sim::play_each(ev, crate::lasers::EARTHQUAKE.length, &answer, &mut |t, due, b| {
            // (as lib.rs counts an edit gone into the world)
            if let Some(n) = &b.sent {
                n.set(n.get() + 1);
            }
            world.borrow_mut().apply(&b);
            edits.push((t, due, b));
        });
        let (stages, cmds) = (played.stages, played.cmds);
        let world = world.into_inner();
        Run { pl, me, cmds, edits, stages, peak: stage_peak(), world }
    }
    fn run(seed: u32, me: [f64; 3]) -> Run {
        run_with(seed, me, None)
    }
    pub(super) fn run_for_costs() -> usize {
        run(37, [10.5, 66.0, 260.0]).edits.len()
    }
    /// What the land's work holds at its most, past what was held before: played against the land as it was, no world
    /// kept (the edits counted out: the mod lets each go as it goes in).
    fn held(seed: u32, me: [f64; 3]) -> usize {
        crate::ground::set_test(Some(survey));
        crate::ground::set_test_wet(Some(survey_wet));
        let ev = plan_eq(me, seed);
        let live = crate::mem::live();
        crate::mem::reset_peak();
        let answer = |x: i32, z: i32, b: u32, a: u32| {
            let mut w = World::new();
            let r = w.read(x, z, b, a);
            Some(r)
        };
        sim::play_each(ev, crate::lasers::EARTHQUAKE.length, &answer, &mut |_, _, b| drop(b));
        crate::mem::peak().saturating_sub(live)
    }
    fn local(pl: &EqPlates, x: i32, z: i32) -> (f32, f32) {
        ((x - pl.block[0]) as f32 + 0.5, (z - pl.block[2]) as f32 + 0.5)
    }
    /// Every column the plates cut, worked out afresh column by column (no quadtree).
    fn cut_columns(pl: &EqPlates) -> BTreeMap<(i32, i32), super::super::earthquake::EqFault> {
        let (_, r) = pl.zone();
        let r = r as i32 + 2;
        let mut out = BTreeMap::new();
        for z in pl.block[2] - r..=pl.block[2] + r {
            for x in pl.block[0] - r..=pl.block[0] + r {
                if let Some(f) = pl.fault_at(x, z) {
                    out.insert((x, z), f);
                }
            }
        }
        // (and the main crack past the zone, as far as it runs)
        for (a, b, _) in pl.crack_chunks() {
            for z in b * 16..b * 16 + 16 {
                for x in a * 16..a * 16 + 16 {
                    if let Some(f) = pl.fault_at(x, z) {
                        out.insert((x, z), f);
                    }
                }
            }
        }
        out
    }
    /// The candidates of column (x, z) at rest worked out afresh from the plates (as `decide`, without the read).
    fn lands_on(pl: &EqPlates, x: i32, z: i32) -> (Vec<usize>, bool) {
        let cut = pl.fault_at(x, z).is_some();
        let own = !cut && pl.column(x, z).is_none_or(|i| offset_of(pl, i) == [0; 3]);
        let v = (0..EQ_PLATES).filter(|&i| offset_of(pl, i) != [0; 3]).filter(|&i| {
            let o = offset_of(pl, i);
            pl.column(x - o[0], z - o[2]) == Some(i) && pl.fault_at(x - o[0], z - o[2]).is_none()
        });
        (v.collect(), own)
    }
    /// The quadtree's slack: the cut found the same as column by column with less slack (`SLACK` is kept above the least
    /// that works); prints how many looks at the plates each takes.
    #[test]
    #[ignore]
    fn eq_land_quadtree_slack() {
        for sl in [0.8f32, 1.0, 1.2, 1.5, 2.0] {
            SLACK_T.with(|s| s.set(sl));
            let mut missed = 0;
            let mut evals = 0;
            for (seed, me) in CASES {
                let pl = eq_plates(&target(), me, seed as f32, true);
                let mut wk = Work::new(pl, None);
                EVALS.with(|e| e.set(0));
                let (a0, b0, cn) = wk.cgrid;
                for k in 0..(cn * cn) {
                    wk.eval((a0 + k % cn) * 16, (b0 + k / cn) * 16, 16);
                }
                evals += EVALS.with(Cell::get);
                for ((x, z), _) in cut_columns(&pl) {
                    if wk.idx(x, z).is_some_and(|c| wk.cutk[c] == 0) && wk.in_disc_xz(x, z) {
                        missed += 1;
                    }
                }
            }
            eprintln!("slack {sl}: {evals} looks, {missed} cut columns missed");
        }
    }
    const CASES: [(u32, [f64; 3]); 3] = [(37, [10.5, 66.0, 260.0]), (500, [70.5, 70.0, 37.0]), (123, [-40.5, 70.0, 20.0])];

    /// The cut: every column the plates name cut, each once, as the crack reaches it, at most two edits a chunk; the
    /// columns round it lined solid from its floor to under their ground, no water beside it.
    #[test]
    fn eq_land_cuts_the_faults_as_the_crack_passes() {
        for (seed, me) in CASES {
            let r = run(seed, me);
            let pl = r.pl;
            let slabs = super::super::eq_trees::eq_slabs_now();
            let want = cut_columns(&pl);
            let mut got: HashMap<(i32, i32), f32> = HashMap::new();
            // (counted apart: the zone's cut, and the main crack past the zone, which a chunk at the rim may share)
            let mut per_chunk: HashMap<(i32, i32, bool), usize> = HashMap::new();
            let by_crack: HashSet<(i32, i32)> = want.iter().filter(|(_, f)| f.crack).flat_map(|(&(x, z), _)| (-1..=1).flat_map(move |dz| (-1..=1).map(move |dx| (x + dx, z + dz)))).collect();
            let mut world = World::new();
            let mut last = 0.0f32;
            for (t, _, e) in r.edits.iter().filter(|e| e.2.urgent) {
                assert!(*t >= last, "seed {seed}: the cut's edits out of order");
                last = *t;
                let mut chunks: HashSet<(i32, i32)> = HashSet::new();
                let far = e.runs.iter().all(|u| by_crack.contains(&(u.x, u.z)));
                for u in &e.runs {
                    chunks.insert((u.x >> 4, u.z >> 4));
                    // (open to the sky, or a slab of the lip's column: one block of air over the lake, its land left)
                    let slab = slabs.iter().any(|s| s.holds(u.x, u.z)) && pl.lake() == Some(u.y - 1);
                    if e.palette[u.block as usize] == "minecraft:air" && u.only.is_none() && (u.y + u.height as i32 - 1 >= 319 || slab) {
                        assert!(got.insert((u.x, u.z), *t).is_none(), "seed {seed}: {},{} cut twice", u.x, u.z);
                    }
                }
                for (a, b) in chunks {
                    *per_chunk.entry((a, b, far)).or_default() += 1;
                }
                world.apply(e);
            }
            assert!(want.len() > 1500, "seed {seed}: {} cut columns", want.len());
            let max = per_chunk.values().max().copied().unwrap_or(0);
            assert!(max <= 2, "seed {seed}: a chunk cut in {max} edits");
            let (mut late, mut worst) = (0, 0.0f32);
            for (&(x, z), f) in &want {
                let Some(&t) = got.get(&(x, z)) else { panic!("seed {seed}: {x},{z} not cut") };
                assert!(t >= f.at - CUT_SPLIT - 0.06, "seed {seed}: {x},{z} cut at {t}, the crack at {}", f.at);
                if t > f.at + CUT_SPLIT + 0.06 {
                    late += 1;
                    if std::env::var("EQ_DEBUG").is_ok() && late % 200 == 1 {
                        eprintln!("late {x},{z}: cut {t:.2}, crack {:.2}, past the zone {}", f.at, f.crack);
                    }
                }
                worst = worst.max(t - f.at);
                // (open from its floor to the sky)
                assert_eq!(world.at(x, f.floor + 1, z), "minecraft:air");
                assert_eq!(world.at(x, 150, z), "minecraft:air");
                if !slabs.iter().any(|s| s.holds(x, z)) && pl.lake_at(x, z, f.main) == 0 {
                    assert_eq!(world.at(x, ground_h(x, z), z), "minecraft:air", "seed {seed}: {x},{z} not open");
                }
            }
            assert!(got.len() == want.len(), "seed {seed}: {} cut, {} named", got.len(), want.len());
            // (the crack's far end may run a little ahead of the cut where the land is busiest: within a second)
            // (the trench is five times the old cut's columns along the main fault: a sixth of them late, by 1.3 s at most)
            assert!(late * 6 < want.len() && worst < 1.3, "seed {seed}: {late} of {} columns cut late, the latest {worst:.2} s", want.len());
            // (every wall: no air, water, lava or ore from the cut's floor to under its ground)
            let mut walls = 0;
            for (&(x, z), _) in &want {
                for dz in -1..=1 {
                    for dx in -1..=1 {
                        let (wx, wz) = (x + dx, z + dz);
                        if want.contains_key(&(wx, wz)) || pl.where_at(local(&pl, wx, wz).0, local(&pl, wx, wz).1).0.is_none() && f64::from(wx - pl.block[0]).hypot(f64::from(wz - pl.block[2])) > pl.zone().1 {
                            continue;
                        }
                        let floor = (-1..=1).flat_map(|a| (-1..=1).map(move |b| (a, b))).filter_map(|(a, b)| want.get(&(wx + a, wz + b))).map(|f| f.floor).min().unwrap();
                        let g = if trunk(wx, wz) { ground_h(wx, wz) + 1 } else { survey(wx, wz).unwrap() };
                        walls += 1;
                        for y in floor + 1..=g - 4 {
                            let n = world.at(wx, y, wz);
                            // (air where the face's relief let it go, never a cave's)
                            assert!(n != "minecraft:cave_air" && !is_fluid(n) && !n.contains("ore"), "seed {seed}: wall {wx},{y},{wz} is {n}");
                        }
                        for y in g..g + 8 {
                            assert!(!world.at(wx, y, wz).contains("water"), "seed {seed}: water beside the cut at {wx},{y},{wz}");
                        }
                    }
                }
            }
            assert!(walls > 2000, "seed {seed}: {walls} walls");
            eprintln!("seed {seed}: {} cut columns, {} cut edits, the last cut edit at {last:.2} s, {late} late, the latest {worst:.2} s after the crack", want.len(), r.edits.iter().filter(|e| e.2.urgent).count());
        }
    }

    /// At rest: every moved column solid from the world's bottom to its ground; the main fault open over lava where the
    /// sides parted; rubble at the foot of the steps; nothing edited far outside.
    #[test]
    fn eq_land_at_rest_nothing_floats_and_the_canyon_glows() {
        for (seed, me) in CASES {
            let mut r = run(seed, me);
            let pl = r.pl;
            let mut cols: HashSet<(i32, i32)> = HashSet::new();
            for e in r.edits.iter().filter(|e| !e.2.urgent) {
                cols.extend(e.2.runs.iter().map(|u| (u.x, u.z)));
            }
            assert!(cols.len() > 20_000, "seed {seed}: {} columns", cols.len());
            let (mut moved, mut canyon, mut lava) = (0, 0, 0);
            for &(x, z) in &cols {
                let (lands, _) = lands_on(&pl, x, z);
                // (clear of the faces' relief, whose pockets may lie under a block or two of rock)
                let near = pl.where_at(local(&pl, x, z).0, local(&pl, x, z).1).1.abs() < 2.0
                    || lands.first().is_some_and(|&i| {
                        let o = offset_of(&pl, i);
                        pl.cut_clear(local(&pl, x - o[0], z - o[2]).0, local(&pl, x - o[0], z - o[2]).1) < RELIEF as f32 + 3.0
                    });
                let c = r.world.col(x, z).clone();
                let names = r.world.names.clone();
                let g = r.world.ground(x, z);
                if !lands.is_empty() && !near {
                    moved += 1;
                    let hole = ((g - 28).max(34)..g).find(|&y| is_air(names[c[(y - Y0) as usize] as usize]));
                    if hole.is_some() && std::env::var("EQ_DEBUG").is_ok() {
                        let i = lands[0];
                        let o = offset_of(&pl, i);
                        eprintln!("{x},{z}: lands {lands:?} o {o:?}, e {:.1} at the source {:.1}", pl.where_at(local(&pl, x, z).0, local(&pl, x, z).1).1, pl.where_at(local(&pl, x - o[0], z - o[2]).0, local(&pl, x - o[0], z - o[2]).1).1);
                        for y in (g - 30..g + 2).rev() {
                            eprintln!("  {y}: {}", names[c[(y - Y0) as usize] as usize]);
                        }
                    }
                    assert!(hole.is_none(), "seed {seed}: {x},{z} has air at {hole:?} under its ground {g}");
                }
                // (the canyon: lava two deep on its floor, open over it)
                let lv = (Y0..60).filter(|&y| names[c[(y - Y0) as usize] as usize] == "minecraft:lava").collect::<Vec<_>>();
                if lv.len() == 2 {
                    lava += 1;
                    let f = lv[0] - 1;
                    // (the lake's level, or lower where the land beside the canyon lies low)
                    let lake = pl.lake().expect("a lake");
                    assert!(f >= EQ_CUT_MAIN_Y && f <= lake - 2, "seed {seed}: the canyon's floor at {f}, the lake {lake}");
                    if (f + 3..120).all(|y| is_air(names[c[(y - Y0) as usize] as usize])) {
                        canyon += 1;
                    } else if std::env::var("EQ_DEBUG").is_ok() {
                        let y = (f + 3..120).find(|&y| !is_air(names[c[(y - Y0) as usize] as usize])).unwrap();
                        eprintln!("not open {x},{z}: {} at {y}, f {f}, cut {:?}, lands {lands:?}", names[c[(y - Y0) as usize] as usize], pl.fault_at(x, z).map(|f| f.main));
                    }
                }
            }
            assert!(moved > 10_000, "seed {seed}: {moved} moved");
            assert!(lava > 200 && canyon * 10 > lava * 9, "seed {seed}: {lava} columns of lava, {canyon} open over it");
            // (the steps' feet: a step down of 8 or more onto land has scree heaped at its foot)
            let (mut steps, mut footed) = (0, 0);
            for &(x, z) in cols.iter().filter(|&&(x, z)| (x + z) % 3 == 0) {
                let g = r.world.ground(x, z);
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let (nx, nz) = (x + dx, z + dz);
                    let gn = r.world.ground(nx, nz);
                    if g - gn < 6 || r.world.at(nx, gn - 1, nz) == "minecraft:lava" || (Y0..0).any(|y| r.world.at(nx, y, nz) == "minecraft:lava") {
                        continue;
                    }
                    steps += 1;
                    let n = r.world.at(nx, gn - 1, nz);
                    if ["cobblestone", "gravel", "tuff", "coarse_dirt", "andesite", "stone"].iter().any(|m| n.ends_with(m)) {
                        footed += 1;
                    }
                }
            }
            assert!(steps > 20 && footed * 10 > steps * 8, "seed {seed}: {footed} of {steps} steps with scree at the foot");
            // (far outside: nothing)
            let (_, zr) = pl.zone();
            assert!(cols.iter().all(|&(x, z)| f64::from(x - pl.block[0]).hypot(f64::from(z - pl.block[2])) < zr + 30.0));
            eprintln!("seed {seed}: {moved} moved, {lava} canyon columns, {footed}/{steps} steps footed, {} cmds", r.cmds.len());
            let _ = r.me;
        }
    }

    /// The scree's edit leaves the columns round a player standing there as they are from their feet up (never a well
    /// of rubble round them), and still lays what lies under their feet's level and everything further off.
    #[test]
    fn eq_scree_leaves_room_round_the_player() {
        let mut b = Blocks { clear_of_player: true, clear_room: 3, ..Default::default() };
        for x in -6..=6 {
            b.run(x, 0, 64, 66, "minecraft:cobblestone");
            b.run(x, 0, 60, 62, "minecraft:stone");
        }
        let e = b.edit_clear_of([0.5, 64.0, 0.5]);
        assert!(e.runs.iter().all(|r| r.x.abs() > 3 || r.y + r.height as i32 - 1 < 64));
        assert_eq!(e.runs.iter().filter(|r| r.y == 60).count(), 13);
        assert_eq!(e.runs.iter().filter(|r| r.y == 64).count(), 6);
    }

    /// A player put on a plate that sank stands inside the land as it was: the edit at rest still clears it (its air
    /// kept all the way up, air put where a plant or a layer of snow would have been put into them), and puts nothing
    /// in them; no column of the old land is left where they stand.
    #[test]
    fn eq_land_at_rest_clears_the_old_land_where_the_player_is_put() {
        let mut b = Blocks { clear_of_player: true, clear_to_air: true, ..Default::default() };
        for x in -2..=2 {
            b.run(x, 0, 0, 25, "minecraft:stone");
            b.run(x, 0, 26, 26, "minecraft:grass_block");
            b.run(x, 0, 27, 27, "minecraft:short_grass");
            b.run(x, 0, 28, 66, "minecraft:air");
        }
        let e = b.edit_clear_of([0.5, 27.0, 0.5]);
        let at = |x: i32, y: i32| e.runs.iter().find(|r| r.x == x && r.y <= y && y < r.y + r.height as i32).map(|r| e.palette[r.block as usize].as_str());
        for x in -2..=2 {
            for y in 0..=66 {
                let want = match y {
                    0..=25 => "minecraft:stone",
                    26 => "minecraft:grass_block",
                    27 if x != 0 => "minecraft:short_grass",
                    _ => "minecraft:air",
                };
                assert_eq!(at(x, y), Some(want), "{x} {y}");
            }
        }
        // (a tall run through them: split round their three cells)
        let mut b = Blocks { clear_of_player: true, clear_to_air: true, ..Default::default() };
        b.run(0, 0, 20, 40, "minecraft:stone");
        let e = b.edit_clear_of([0.5, 27.0, 0.5]);
        let at = |y: i32| e.runs.iter().find(|r| r.y <= y && y < r.y + r.height as i32).map(|r| e.palette[r.block as usize].as_str());
        assert!((20..=40).all(|y| at(y) == Some(if (27..=29).contains(&y) { "minecraft:air" } else { "minecraft:stone" })));
        // (without it, as before: the run left out, the air kept)
        let mut b = Blocks { clear_of_player: true, ..Default::default() };
        b.run(0, 0, 27, 27, "minecraft:cobblestone");
        b.run(0, 0, 28, 40, "minecraft:air");
        let e = b.edit_clear_of([0.5, 27.0, 0.5]);
        assert_eq!(e.runs.len(), 1);
        assert_eq!(e.palette[e.runs[0].block as usize], "minecraft:air");
    }

    /// Trees well inside a plate (clear of its cut, of the scree heaped at a step's foot and of the leaves' spread) come
    /// to rest whole, on their own ground, gone from where they stood: one or more checked on every plate that moves.
    #[test]
    fn eq_land_moves_the_trees_whole_onto_ground() {
        for (seed, me) in [CASES[0], CASES[1], CASES[2]] {
            let mut r = run(seed, me);
            let pl = r.pl;
            let fallen = super::super::eq_trees::eq_trees_now().1;
            let mut found = vec![0usize; EQ_PLATES];
            let (mid, zr) = pl.zone();
            let (g0x, g0z, gn) = ((mid[0] - zr) as i32 / 11 - 1, (mid[1] - zr) as i32 / 11 - 1, (2.0 * zr) as i32 / 11 + 3);
            for i in 0..EQ_PLATES {
                let o = offset_of(&pl, i);
                if o == [0; 3] {
                    continue;
                }
                for gz in g0z..g0z + gn {
                    for gx in g0x..g0x + gn {
                        let h = hh(gx, gz, 1);
                        let (tx, tz) = (gx * 11 + 2 + (h % 7) as i32, gz * 11 + 2 + ((h >> 8) % 7) as i32);
                        if !trunk(tx, tz) {
                            continue;
                        }
                        // (a tree that falls, or one whose crown reaches into one's box: strike/eq_trees.rs's, below)
                        if fallen.iter().any(|t| {
                            let [x0, z0, x1, z1] = t.rect();
                            tx + 2 >= x0 - 3 && tx - 2 <= x1 + 3 && tz + 2 >= z0 - 3 && tz - 2 <= z1 + 3
                        }) {
                            continue;
                        }
                        let (fx, fz) = local(&pl, tx, tz);
                        let ok = |x: f32, z: f32| {
                            let (p, e) = pl.where_at(x, z);
                            p == Some(i) && e > 12.0 && pl.cut_clear(x, z) > 10.0
                        };
                        // (its neighbours move with it, so it lands as far inside its plate as it stood; plates close on
                        // one another by a few blocks at most)
                        if !ok(fx, fz) {
                            continue;
                        }
                        let g = ground_h(tx, tz);
                        let (nx, nz, dy) = (tx + o[0], tz + o[2], o[1]);
                        for y in g + 1..=g + 5 {
                            assert_eq!(r.world.at(nx, y + dy, nz), "minecraft:oak_log", "seed {seed} plate {i}: the trunk of {tx},{tz}");
                        }
                        assert_eq!(r.world.at(nx, g + dy, nz), "minecraft:grass_block", "seed {seed}: on its ground");
                        assert_eq!(r.world.at(nx + 1, g + 5 + dy, nz), "minecraft:oak_leaves[persistent=true]");
                        assert_eq!(r.world.at(nx, g + 8 + dy, nz), "minecraft:air");
                        found[i] += 1;
                    }
                }
            }
            // (every plate that moves with room for one: a spot 12 inside it with a tree's whole grid cell round it)
            let mut deep = vec![0.0f32; EQ_PLATES];
            for gz in (g0z * 11..(g0z + gn) * 11).step_by(2) {
                for gx in (g0x * 11..(g0x + gn) * 11).step_by(2) {
                    let (fx, fz) = local(&pl, gx, gz);
                    if let (Some(i), e) = pl.where_at(fx, fz)
                        && ground_h(gx, gz) > SEA + 1
                    {
                        deep[i] = deep[i].max(e);
                    }
                }
            }
            for i in 0..EQ_PLATES {
                if offset_of(&pl, i) != [0; 3] && deep[i] > 12.0 + 8.0 {
                    assert!(found[i] > 0, "seed {seed}: plate {i} has a tree checked ({found:?}, room {deep:?})");
                }
            }
        }
    }

    /// The slabs of the low lip (strike/eq_trees.rs's EqSlab): some are found; each stands in the main fault's trench
    /// with a column of open trench all round it; the cut leaves its land standing over one block of air over the lake's
    /// lava; at rest its columns are open canyon over the lava; each goes with a lurch of its plate and is under by rest.
    #[test]
    fn eq_slabs_stand_in_the_trench_and_are_gone_at_rest() {
        use super::super::eq_trees::eq_slabs_now;
        let mut total = 0;
        for (seed, me) in [CASES[0], CASES[1], CASES[2]] {
            let r = run(seed, me);
            let pl = r.pl;
            let slabs = eq_slabs_now();
            let lake = pl.lake().expect("a lake");
            let (mut cut, mut swap) = cut_and_swap(&r);
            assert!(slabs.len() <= EQ_SLABS);
            for s in &slabs {
                assert!(s.yb == lake + 2 && s.amax > 4.0 && s.amax <= 72.0 && s.fall > 8.0, "seed {seed}: {s:?}");
                assert!((1..=4).any(|k| (0.2..=0.8).contains(&(s.t0 - pl.lurch(s.plate, k).t))), "seed {seed}: a slab at {}", s.t0);
                assert!(s.t0 + EQ_SLAB_T < EQ_REST - 5.0);
                for z in s.lo[1] - 1..=s.hi[1] + 1 {
                    for x in s.lo[0] - 1..=s.hi[0] + 1 {
                        assert!(pl.fault_at(x, z).is_some_and(|f| f.main && !f.crack), "seed {seed}: {x},{z} of a slab or beside it is no trench");
                        assert_eq!(cut.at(x, lake, z), "minecraft:lava", "seed {seed}: lava under {x},{z}");
                        assert_eq!(cut.at(x, lake + 1, z), "minecraft:air");
                        let g = ground_h(x, z);
                        if s.holds(x, z) {
                            // (its land left standing from two over the lava)
                            for y in lake + 2..=g {
                                assert_eq!(cut.at(x, y, z), land_block(x, y, z), "seed {seed}: the slab's {x},{y},{z}");
                            }
                        } else {
                            assert!((lake + 2..=g + 2).all(|y| is_air(cut.at(x, y, z))), "seed {seed}: the trench round a slab at {x},{z}");
                        }
                        // (at rest: the canyon, open over its lava)
                        // (the lava, or its crust)
                        let top = swap.at(x, lake, z);
                        assert!(matches!(top, "minecraft:lava" | "minecraft:magma_block" | "minecraft:blackstone" | "minecraft:basalt" | "minecraft:smooth_basalt"), "seed {seed}: at rest {x},{z} is {top}");
                        assert_eq!(swap.at(x, lake - 1, z), "minecraft:lava", "seed {seed}: at rest under {x},{z}");
                        assert!((lake + 1..=g + 8).all(|y| is_air(swap.at(x, y, z))), "seed {seed}: at rest something stands at {x},{z}");
                    }
                }
            }
            eprintln!("seed {seed}: {} slabs: {:?}", slabs.len(), slabs.iter().map(|s| (s.lo, s.hi, s.t0, s.amax as i32, s.fall as i32)).collect::<Vec<_>>());
            total += slabs.len();
        }
        assert!(total >= 12, "{total} slabs in three strikes");
    }

    /// A fallen tree's logs lying on a plate that moves lie the same way at rest (the read has no block states: each is
    /// named with its axis from the logs beside it), on their ground.
    #[test]
    fn eq_land_keeps_lying_logs_lying() {
        let mut found = 0;
        for (seed, me) in [CASES[0], CASES[1], CASES[2]] {
            let mut r = run(seed, me);
            let pl = r.pl;
            let fallen = super::super::eq_trees::eq_trees_now().1;
            let (_, zr) = pl.zone();
            let reach = zr as i32;
            for z in pl.block[2] - reach..=pl.block[2] + reach {
                for x in pl.block[0] - reach..=pl.block[0] + reach {
                    let Some(way) = lying(x, z) else { continue };
                    let (fx, fz) = local(&pl, x, z);
                    let (Some(i), e) = pl.where_at(fx, fz) else { continue };
                    let o = offset_of(&pl, i);
                    // (well inside a plate that moves, clear of the trees that fall)
                    if o == [0; 3] || e <= 14.0 || pl.cut_clear(fx, fz) <= 12.0 {
                        continue;
                    }
                    if fallen.iter().any(|t| {
                        let [x0, z0, x1, z1] = t.rect();
                        x >= x0 - 3 && x <= x1 + 3 && z >= z0 - 3 && z <= z1 + 3
                    }) {
                        continue;
                    }
                    let g = ground_h(x, z);
                    assert_eq!(land_block(x, g + 1, z), "minecraft:birch_log");
                    assert_eq!(r.world.at(x + o[0], g + 1 + o[1], z + o[2]), format!("minecraft:birch_log[axis={way}]"), "seed {seed} plate {i}: the log at {x},{z}");
                    assert_eq!(r.world.at(x + o[0], g + o[1], z + o[2]), "minecraft:grass_block", "seed {seed}: on its ground");
                    found += 1;
                }
            }
        }
        assert!(found >= 8, "{found} lying logs checked");
    }

    /// The trees that fall (strike/eq_trees.rs): some do, within reach, on plates that move enough, a block apart, each
    /// with one of its plate's lurches; at rest each lies where the warp draws it at its quarter turn (every block of its
    /// box that was the tree at its turned place, moved with its plate, unless that was the land), nothing of its box is
    /// left standing, and nothing of it is written twice.
    #[test]
    fn eq_trees_lie_where_the_warp_draws_them() {
        use super::super::eq_trees::{EQ_TREE_FALL, EQ_TREE_IN, EQ_TREE_LATE, eq_trees_now};
        let mut total = 0;
        for (seed, me) in CASES {
            let mut r = run(seed, me);
            let pl = r.pl;
            let (_, trees, origin) = eq_trees_now();
            assert!(trees.len() <= EQ_TREES);
            assert_eq!(origin, [pl.block[0], pl.block[1] + 1, pl.block[2]]);
            let rest: Vec<&Blocks> = r.edits.iter().filter(|e| !e.2.urgent && e.2.sent.is_some()).map(|e| &e.2).collect();
            let mut placed = 0;
            for (k, t) in trees.iter().enumerate() {
                let o = offset_of(&pl, t.plate);
                assert!(f64::from(o[0] * o[0] + o[1] * o[1] + o[2] * o[2]).sqrt() >= f64::from(EQ_TREE_MOVE));
                assert!(f64::from(t.h[0] - pl.block[0]).hypot(f64::from(t.h[2] - pl.block[2])) <= f64::from(EQ_TREE_REACH) + 1.0);
                assert!([1usize, 2, 3, 4].iter().any(|&l| (EQ_TREE_IN - 1e-4..=EQ_TREE_IN + EQ_TREE_LATE + 1e-4).contains(&(t.t0 - pl.lurch(t.plate, l).t))), "seed {seed}: tree {k} at {}", t.t0);
                assert!(t.t0 + EQ_TREE_FALL < EQ_REST - 5.0);
                for u in &trees[k + 1..] {
                    let (a, b) = (t.rect(), u.rect());
                    assert!(a[0] > b[2] + 1 || b[0] > a[2] + 1 || a[1] > b[3] + 1 || b[1] > a[3] + 1, "seed {seed}: two trees touch");
                }
                let tree = |n: &str| n.contains("_log") || n.contains("leaves");
                let mut dest = HashSet::new();
                for b in t.cells() {
                    let n = land_block(b[0], b[1], b[2]);
                    if !tree(n) {
                        continue;
                    }
                    let to = t.turn(b);
                    // (where the warp draws its middle at rest: turned a quarter about the hinge, moved with its plate)
                    let tt = EQ_REST - 0.1;
                    let m = t.turn_at([b[0] as f32 + 0.5, b[1] as f32 + 0.5, b[2] as f32 + 0.5], t.angle(tt));
                    let d = pl.disp(t.plate, tt);
                    for a in 0..3 {
                        assert!((m[a] + d[a] - (to[a] + o[a]) as f32 - 0.5).abs() < 1e-3, "seed {seed}: tree {k}'s {b:?} drawn at {m:?} + {d:?}, at rest {to:?}");
                    }
                    let free = t.in_box(to) || matches!(tree_kind(land_block(to[0], to[1], to[2])), Kind::Air | Kind::Plant);
                    if !free {
                        continue;
                    }
                    dest.insert(to);
                    let at = [to[0] + o[0], to[1] + o[1], to[2] + o[2]];
                    let want = if n.contains("_log") { format!("minecraft:oak_log[axis={}]", if t.e()[0] != 0 { "x" } else { "z" }) } else { "minecraft:oak_leaves[persistent=true]".to_string() };
                    assert_eq!(r.world.at(at[0], at[1], at[2]), want, "seed {seed}: tree {k}'s {b:?} lying at {at:?}");
                    // (written once: by one edit at rest, one run)
                    let writes: usize = rest.iter().map(|e| e.runs.iter().filter(|u| u.x == at[0] && u.z == at[2] && at[1] >= u.y && at[1] < u.y + u.height as i32).count()).sum();
                    assert_eq!(writes, 1, "seed {seed}: tree {k}'s {at:?} written {writes} times");
                    placed += 1;
                }
                // (nothing of its box left standing where its plate took it)
                for b in t.cells() {
                    if dest.contains(&b) {
                        continue;
                    }
                    let n = r.world.at(b[0] + o[0], b[1] + o[1], b[2] + o[2]);
                    assert!(!tree(n), "seed {seed}: tree {k}'s {b:?} left standing ({n})");
                }
            }
            eprintln!("seed {seed}: {} trees fall, {placed} blocks lying", trees.len());
            total += trees.len();
            if seed == CASES[0].0 {
                assert!(trees.len() >= 4, "seed {seed}: {} trees", trees.len());
            }
        }
        assert!(total >= 10, "{total} trees fall");
    }

    /// Each chunk edited once at rest, all of it behind the hold and in by EQ_LAND_END (the rider's after), in time; the
    /// fuel and the memory; the plan in time order; the riders; what is done afterwards.
    #[test]
    fn eq_land_each_chunk_once_in_time_and_light() {
        for (seed, me) in [(37u32, [10.5, 66.0, 260.0]), (997, [10.5, 66.0, 40.0]), (2, [300.5, 66.0, -3.5])] {
            let r = run(seed, me);
            let mut seen: BTreeMap<(i32, i32), usize> = BTreeMap::new();
            let rest: Vec<_> = r.edits.iter().filter(|e| !e.2.urgent && e.2.sent.is_some()).collect();
            for (k, e) in rest.iter().enumerate() {
                let mut ch: Vec<(i32, i32)> = e.2.runs.iter().map(|u| (u.x >> 4, u.z >> 4)).collect();
                ch.sort_unstable();
                ch.dedup();
                for c in ch {
                    assert!(seen.insert(c, k).is_none(), "seed {seed}: chunk {c:?} edited twice at rest");
                }
                assert!(e.2.clear_of_player, "seed {seed}: an edit at rest not kept clear of the player");
            }
            assert!(seen.len() > 200, "seed {seed}: {} chunks", seen.len());
            let first = rest.iter().map(|e| e.0).fold(f32::MAX, f32::min);
            let last = rest.iter().map(|e| e.0).fold(0.0f32, f32::max);
            assert!(first >= EQ_HOLD_START + 0.05, "seed {seed}: the first edit at {first}");
            // (every chunk by EQ_LAND_END but the walker's, round where the player stands, which go in last, from
            // EQ_RIDER_FROM, all of them before rest: the swap waits for every edit made to be in, `eq_land_in`)
            let at = [r.me[0], r.me[2]];
            let rides = |e: &Blocks| (f64::from((e.runs[0].x >> 4) * 16 + 8) - at[0]).hypot(f64::from((e.runs[0].z >> 4) * 16 + 8) - at[1]) < WALK_R + 11.4;
            let (mut riders, mut others) = (0, 0.0f32);
            for e in &rest {
                if rides(&e.2) {
                    riders += 1;
                    assert!(e.0 >= EQ_RIDER_FROM - 0.06 && e.0 <= EQ_RIDER_TO + 0.06, "seed {seed}: a walker's chunk at {}", e.0);
                } else {
                    others = others.max(e.0);
                }
            }
            assert!(others <= EQ_LAND_END + 0.06, "seed {seed}: the last edit but the rider's at {others}");
            assert!(last <= EQ_RIDER_TO + 0.06 && EQ_RIDER_TO < EQ_REST, "seed {seed}: the last edit at {last}");
            // (each chunk's time as listed for the walk: the edit never goes in sooner)
            for e in &rest {
                let due = eq_chunk_due(e.2.runs[0].x >> 4, e.2.runs[0].z >> 4).expect("listed");
                assert!(e.0 >= due - 0.001, "seed {seed}: an edit at {} due {due}", e.0);
            }
            eprintln!("seed {seed}: {riders} walker's chunks");
            assert!(eq_land_in(), "seed {seed}: the land's edits not all in after the strike");
            let (hold, _, _) = eq_frame(EQ_REST, true, false, 21.0, (true, 0));
            assert!(hold, "the swap waits while an edit is still out");
            assert!(r.edits.iter().all(|e| e.0 - e.1 < 0.3), "seed {seed}: an edit late");
            assert!(r.edits.iter().filter(|e| e.2.urgent).all(|e| e.0 < EQ_HOLD_START), "seed {seed}: a cut edit behind the hold");
            // (the cut's stages are counted at what the game counts of them now: HARD and a chunk's own work over it)
            assert!(r.peak < 28_000_000, "seed {seed}: a stage spent {:.1}M", r.peak as f64 / 1e6);
            let mem = held(seed, me);
            assert!(mem < 28 << 20, "seed {seed}: the land held {:.1} MB", crate::mem::mb(mem));
            eprintln!("seed {seed}: {} chunks, edits {first:.2}-{last:.2} s, {} stages, the heaviest {:.1}M, memory {:.1} MB", seen.len(), r.stages.len(), r.peak as f64 / 1e6, crate::mem::mb(mem));
            let ev = plan_eq(me, seed);
            assert!(ev.windows(2).all(|w| w[0].0 <= w[1].0));
            assert!(ev.iter().any(|e| matches!(&e.1, Act::Cmd(c) if c.starts_with("forceload add"))));
            assert!(ev.iter().any(|e| matches!(&e.1, Act::Spare(c) if c.starts_with("forceload remove"))));
            let tags = r.cmds.iter().filter(|c| c.1.starts_with("tag @e[type=!minecraft:player,")).count();
            let tps: Vec<f32> = r.cmds.iter().filter(|c| c.1.contains(" run tp @s ~")).map(|c| c.0).collect();
            assert!(tags > 100 && !tps.is_empty() && tps.iter().all(|&t| t >= EQ_REST), "seed {seed}: {tags} tags, the tp at {tps:?}");
            // (afterwards: rock let go off the cliffs, most of it in the first two seconds after rest; water set flowing)
            let falls: Vec<f32> = r.cmds.iter().filter(|c| c.1.starts_with("summon minecraft:falling_block")).map(|c| c.0).collect();
            assert!(falls.len() >= 40 && falls.len() <= 90, "seed {seed}: {} falling blocks", falls.len());
            assert!(falls.iter().all(|&t| t >= EQ_REST && t <= EQ_REST + 9.5));
            assert!(falls.iter().filter(|&&t| t < EQ_REST + 2.2).count() * 2 > falls.len());
            let per_tick = r.cmds.iter().fold(BTreeMap::<i32, usize>::new(), |mut m, c| {
                *m.entry((c.0 / 0.05).round() as i32).or_default() += 1;
                m
            });
            let _ = per_tick;
        }
    }

    /// The hold on the terrain covers every chunk the land edits at rest (lib.rs keeps it to `eq_hold_within`'s circle
    /// of the strike's params): each edited chunk's middle inside it.
    #[test]
    fn eq_land_hold_covers_every_edit_at_rest() {
        for (seed, me) in [(37u32, [10.5, 66.0, 260.0]), (997, [10.5, 66.0, 40.0]), (2, [300.5, 66.0, -3.5]), (123, [-40.5, 70.0, 20.0])] {
            let r = run(seed, me);
            let mut params = [0.0f32; 16];
            for (i, v) in r.pl.warp_params() {
                params[i] = v;
            }
            params[4] = target().point[0] as f32;
            params[5] = target().point[2] as f32;
            let (hx, hz, hr) = super::super::earthquake::eq_hold_within(&params);
            let mut worst = 0.0f64;
            for (_, _, e) in r.edits.iter().filter(|e| !e.2.urgent) {
                for u in &e.runs {
                    let d = (f64::from((u.x >> 4) * 16 + 8) - hx).hypot(f64::from((u.z >> 4) * 16 + 8) - hz);
                    worst = worst.max(d);
                    assert!(d < hr, "seed {seed}: a chunk at {},{} edited at rest {d:.0} from the hold's middle, its radius {hr:.0}", u.x >> 4, u.z >> 4);
                }
            }
            eprintln!("seed {seed}: the farthest chunk edited at rest {worst:.0} from the hold's middle, its radius {hr:.0}");
        }
    }

    /// The walker's land: the chunks round where the player really stands as they are listed (lib.rs says each tick,
    /// `eq_walker`) go in last, after every other, wherever that is now.
    #[test]
    fn eq_land_walker_chunks_go_in_last() {
        let me = [10.5, 66.0, 40.0];
        // (they walked off from where they fired: the chunks round where they are now go last)
        let at = [70.5, 30.5];
        eq_walker(Some(at));
        let r = run(37, me);
        eq_walker(None);
        let mut late = 0;
        for (t, _, e) in r.edits.iter().filter(|e| !e.2.urgent && e.2.sent.is_some()) {
            let (a, b) = (e.runs[0].x >> 4, e.runs[0].z >> 4);
            let near = (f64::from(a * 16 + 8) - at[0]).hypot(f64::from(b * 16 + 8) - at[1]) < WALK_R + 11.4;
            if near {
                late += 1;
                assert!(*t >= EQ_RIDER_FROM - 0.06 && *t <= EQ_RIDER_TO + 0.06, "a walker's chunk at {t}");
            } else {
                assert!(*t <= EQ_LAND_END + 0.06, "another chunk at {t}");
            }
        }
        assert!(late >= 30, "{late} walker's chunks");
        eprintln!("{late} walker's chunks");
    }

    /// Land the world never loads in part: those columns are never edited at rest and nothing is copied from them.
    #[test]
    fn eq_land_leaves_land_not_loaded_alone() {
        fn hole(x: i32, z: i32) -> bool {
            x > 40 && x < 90 && z > -20 && z < 30
        }
        let r = run_with(37, [10.5, 66.0, 260.0], Some(hole));
        let pl = r.pl;
        for e in r.edits.iter().filter(|e| !e.2.urgent) {
            for u in &e.2.runs {
                assert!(!hole(u.x, u.z), "{},{} edited, not loaded", u.x, u.z);
                for i in 0..EQ_PLATES {
                    let o = pl.offset(i);
                    if o != [0; 3] && hole(u.x - o[0], u.z - o[2]) && pl.column(u.x - o[0], u.z - o[2]) == Some(i) && pl.fault_at(u.x - o[0], u.z - o[2]).is_none() {
                        let (lands, _) = lands_on(&pl, u.x, u.z);
                        assert!(lands.len() > 1, "{},{} copied from land not loaded", u.x, u.z);
                    }
                }
            }
        }
        assert!(!r.edits.is_empty());
    }

    #[test]
    fn eq_land_terrain_off_reads_edits_and_holds_nothing() {
        for me in [[10.5, 66.0, 40.0], [10.5, 66.0, 260.0]] {
            let ev = crate::strike::plan(&crate::lasers::EARTHQUAKE, &target(), false, "minecraft:overworld", 37.0, me, 0);
            // (the one survey is the dust's: the land's heights, strike/eq_ground.rs)
            assert!(!ev.iter().any(|e| matches!(e.1, Act::Cmd(_) | Act::Blocks(_) | Act::Read { .. } | Act::Spare(_) | Act::Later(_))));
            assert_eq!(ev.iter().filter(|e| matches!(e.1, Act::Survey { .. })).count(), 1);
        }
        for t in [0.0f32, 9.0, 9.7, 15.0, 29.9, 30.0, 35.0] {
            let (hold, warp, _) = eq_frame(t, false, true, 0.0, (false, 0));
            assert!(!hold);
            assert_eq!(warp, (super::super::earthquake::EQ_WARP_START..super::super::earthquake::EQ_WARP_END).contains(&t));
        }
    }

    /// The hold and the warp through the swap: held from just before the first edit, let go at rest once the land is in
    /// (kept while it is not, up to the hold's limit), the warp a frame longer.
    #[test]
    fn eq_land_swap_holds_and_lets_go() {
        let rest = EQ_REST;
        assert_eq!(eq_frame(EQ_HOLD_START - 0.1, true, false, 0.0, (false, 0)).0, false);
        assert_eq!(eq_frame(EQ_HOLD_START, true, false, 0.0, (false, 0)), (true, true, 0));
        assert_eq!(eq_frame(rest - 0.05, true, true, 20.0, (true, 0)), (true, true, 0));
        assert_eq!(eq_frame(rest, true, true, 20.4, (true, 0)), (false, true, 1), "the frame it lets go, the warp still on");
        assert_eq!(eq_frame(rest, true, true, 20.4, (false, 1)), (false, false, 2));
        assert_eq!(eq_frame(rest + 1.0, true, false, 21.4, (true, 0)), (true, true, 0), "edits still waiting: held, the plates drawn at rest");
        assert_eq!(eq_frame(rest + 8.0, true, false, EQ_HOLD_MAX, (true, 0)), (false, true, 1));
        assert_eq!(eq_frame(20.0, true, false, EQ_HOLD_MAX, (true, 0)), (false, false, 1));
    }

    /// The strata read as layers: a column's runs are a few blocks thick, thick and thin, and a bed's height moves by a
    /// block at most from one column to the next.
    #[test]
    fn eq_land_strata_are_layers() {
        let s = Strata::new(37, [0.8, 0.6]);
        let mut e = Blocks::default();
        s.runs(&mut e, 0, 0, 0, 0, -40, 120, s.shift(0, 0));
        let mean = 161.0 / e.runs.len() as f64;
        assert!((2.0..7.0).contains(&mean), "beds {mean:.1} thick");
        let thin = e.runs.iter().filter(|r| r.height <= 2).count();
        let thick = e.runs.iter().filter(|r| r.height >= 6).count();
        assert!(thin >= 4 && thick >= 4, "{thin} thin beds, {thick} thick");
        for x in -300..300 {
            for z in [-200, -7, 0, 33, 150] {
                assert!((s.shift(x, z) - s.shift(x + 1, z)).abs() <= 1 && (s.shift(x, z) - s.shift(x, z + 1)).abs() <= 1, "the beds jump at {x},{z}");
            }
        }
    }

    /// The world after the cut and the world the swap shows (the cut, then every edit at rest, none of what comes after).
    fn cut_and_swap(r: &Run) -> (World, World) {
        let (mut cut, mut swap) = (World::new(), World::new());
        for (_, _, e) in &r.edits {
            if e.urgent {
                cut.apply(e);
                swap.apply(e);
            } else if e.sent.is_some() {
                swap.apply(e);
            }
        }
        (cut, swap)
    }
    /// The columns the cut lined (written and not cut), each with the lowest and the highest height it wrote.
    fn lined(r: &Run) -> HashMap<(i32, i32), (i32, i32)> {
        let mut out: HashMap<(i32, i32), (i32, i32)> = HashMap::new();
        for (_, _, e) in r.edits.iter().filter(|e| e.2.urgent) {
            for u in &e.runs {
                if r.pl.fault_at(u.x, u.z).is_some() {
                    continue;
                }
                let v = out.entry((u.x, u.z)).or_insert((i32::MAX, i32::MIN));
                v.0 = v.0.min(u.y);
                v.1 = v.1.max(u.y + u.height as i32 - 1);
            }
        }
        out
    }
    fn solid(n: &str) -> bool {
        !is_air(n) && !is_fluid(n) && !n.contains("leaves") && !n.contains("grass") && !n.ends_with("_log")
    }

    /// The faces' relief: let go where the face is set back, the same at the cut as at rest (every block the cut wrote
    /// beside it, in a column landing on its own, is the block the swap shows there risen), broken (the face's line jogs:
    /// many lined columns let go), and nothing over air by more than two blocks with nothing under it.
    #[test]
    fn eq_land_relief_is_the_same_at_the_cut_and_at_rest() {
        for (seed, me) in [CASES[0], CASES[1]] {
            let r = run(seed, me);
            let pl = r.pl;
            let (mut cut, mut swap) = cut_and_swap(&r);
            let lined = lined(&r);
            let (mut same, mut differ, mut carved) = (0usize, 0usize, 0usize);
            for (&(x, z), &(lo, hi)) in &lined {
                let Some(i) = pl.column(x, z) else { continue };
                let o = offset_of(&pl, i);
                if o == [0; 3] {
                    continue;
                }
                let (dx, dz) = (x + o[0], z + o[2]);
                if lands_on(&pl, dx, dz) != (vec![i], false) {
                    continue;
                }
                for y in lo.max(Y0 - o[1])..=hi {
                    // (at rest nothing is seen under the lake: a face let go down to it is the lake's there)
                    if pl.lake().is_some_and(|l| y + o[1] <= l + LAKE_CLEAR) {
                        continue;
                    }
                    let (a, b) = (cut.at(x, y, z), swap.at(dx, y + o[1], dz));
                    // (the lake's edge is sealed with blocks that draw nothing where the face is let go: air to the eye)
                    let a = if a == "minecraft:barrier" { "minecraft:air" } else { a };
                    if a == b {
                        same += 1;
                    } else {
                        differ += 1;
                        if std::env::var("EQ_DEBUG").is_ok() && (differ < 6 || differ % 700 == 0) {
                            eprintln!("DIFF {x},{y},{z} cut {a}, at rest {b} (plate {i}, lo {lo} hi {hi}); clear {:.2}", pl.cut_clear(local(&pl, x, z).0, local(&pl, x, z).1));
                        }
                    }
                    if is_air(a) && y < hi - 3 {
                        carved += 1;
                    }
                }
            }
            let nruns: usize = r.edits.iter().filter(|e| e.2.urgent).map(|e| e.2.runs.len()).sum();
            let nmain = lined.keys().filter(|&&(x, z)| (-1..=1).any(|a| (-1..=1).any(|b| pl.fault_at(x + a * 3, z + b * 3).is_some_and(|f| f.main)))).count();
            eprintln!("seed {seed}: {} lined columns ({nmain} by the main fault), {nruns} runs in the cut", lined.len());
            assert!(same > 200_000, "seed {seed}: {same} blocks compared");
            assert!(differ * 2000 < same, "seed {seed}: {differ} blocks of the faces differ at rest of {same}");
            assert!(carved > 20_000, "seed {seed}: {carved} blocks let go off the faces");
            // (nothing over air further than two blocks from rock under it, at the cut and at rest)
            let mut over = 0;
            for (&(x, z), &(lo, hi)) in &lined {
                for y in lo + 1..=hi {
                    // (the lake's seal draws nothing: no rock to the eye)
                    if solid(cut.at(x, y, z)) && cut.at(x, y, z) != "minecraft:barrier" && is_air(cut.at(x, y - 1, z)) {
                        let held = (-2..=2).any(|a| (-2..=2).any(|b| solid(cut.at(x + a, y - 1, z + b))));
                        if !held {
                            over += 1;
                            if std::env::var("EQ_DEBUG").is_ok() && over < 10 {
                                eprintln!("over air at {x},{y},{z}");
                            }
                        }
                    }
                }
            }
            assert!(over * 10_000 < same, "seed {seed}: {over} blocks hang over air");
            let _ = swap.at(0, 0, 0);
            eprintln!("seed {seed}: {same} face blocks the same at rest, {differ} not, {carved} let go, {over} over air");
        }
    }

    /// The swap shows nothing on a moved plate that was not drawn there the tick before (the cut's world risen with the
    /// plate): no block in view at rest where the plate drawn had air. The gaps' rubble's top and the scree come after.
    #[test]
    fn eq_land_nothing_pops_in_at_the_swap() {
        for (seed, me) in [CASES[0], CASES[2]] {
            let r = run(seed, me);
            let pl = r.pl;
            let (mut cut, mut swap) = cut_and_swap(&r);
            let mut cols: HashSet<(i32, i32)> = HashSet::new();
            for e in r.edits.iter().filter(|e| !e.2.urgent && e.2.sent.is_some()) {
                cols.extend(e.2.runs.iter().map(|u| (u.x, u.z)));
            }
            let (mut seen, mut popped) = (0usize, 0usize);
            for &(x, z) in &cols {
                let (lands, own) = lands_on(&pl, x, z);
                if lands.len() != 1 || own {
                    continue;
                }
                let i = lands[0];
                let o = offset_of(&pl, i);
                // (the plate's own column, not one its neighbour's bending lands next to)
                if (-1..=1).any(|a| (-1..=1).any(|b| lands_on(&pl, x + a, z + b).0 != vec![i])) {
                    continue;
                }
                // (the faces: within the relief of a fault at the source; caves deeper in the land are out of sight)
                if pl.cut_clear(local(&pl, x - o[0], z - o[2]).0, local(&pl, x - o[0], z - o[2]).1) > RELIEF as f32 + 3.0 {
                    continue;
                }
                let g = swap.ground(x, z);
                // (over the cut's floor: under it is the floor of a slot or the canyon, drawn dark)
                for y in (g - 60).max(EQ_CUT_Y + 1 + o[1]).max(-63)..g + 4 {
                    let n = swap.at(x, y, z);
                    // (nothing is seen under the lake)
                    if !solid(n) || pl.lake().is_some_and(|l| y <= l + LAKE_CLEAR) {
                        continue;
                    }
                    // (open to the air the cut and the move made: the land's own caves, cave air, are out of sight)
                    let open = [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, 1, 0)].iter().any(|&(a, b, c)| swap.at(x + a, y + b, z + c) == "minecraft:air");
                    if !open {
                        continue;
                    }
                    seen += 1;
                    if is_air(cut.at(x - o[0], y - o[1], z - o[2])) {
                        popped += 1;
                        if std::env::var("EQ_DEBUG").is_ok() && popped < 20 {
                            let nb: Vec<String> = [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, 1, 0)].iter().map(|&(a, b, c)| format!("{}:{}", swap.at(x + a, y + b, z + c).trim_start_matches("minecraft:"), cut.at(x + a - o[0], y + b - o[1], z + c - o[2]).trim_start_matches("minecraft:"))).collect();
                            eprintln!("popped {x},{y},{z}: {n} (plate {i}, from {},{},{}: {}), round it (at rest:cut) {nb:?}, e {:.1}", x - o[0], y - o[1], z - o[2], cut.at(x - o[0], y - o[1], z - o[2]), pl.where_at(local(&pl, x - o[0], z - o[2]).0, local(&pl, x - o[0], z - o[2]).1).1);
                        }
                    }
                }
            }
            assert!(seen > 30_000, "seed {seed}: {seen} blocks in view");
            assert!(popped * 1000 < seen, "seed {seed}: {popped} of {seen} blocks in view appear at the swap");
            // (the trees that fell: round each, lying, the land at rest is what the warp drew at the end of its fall: the
            // box's blocks turned a quarter about its hinge (left out where they went into the land, hidden in it), the
            // box left empty, the rest of the land as it stood; all moved with the plate)
            let tree = |n: &str| n.contains("_log") || n.contains("leaves");
            let (mut looked, mut wrong) = (0usize, 0usize);
            for t in &super::super::eq_trees::eq_trees_now().1 {
                let o = offset_of(&pl, t.plate);
                let [x0, z0, x1, z1] = t.rect();
                for sz in z0 - 1..=z1 + 1 {
                    for sx in x0 - 1..=x1 + 1 {
                        for sy in t.h[1] - 4..=t.h[1] + t.top + 1 {
                            let src = [sx, sy, sz];
                            let from = t.unturn(src);
                            let drawn_tree = if t.in_box(from) && tree(land_block(from[0], from[1], from[2])) {
                                true
                            } else if t.in_box(src) {
                                false
                            } else {
                                tree(cut.at(sx, sy, sz))
                            };
                            let n = swap.at(sx + o[0], sy + o[1], sz + o[2]);
                            looked += 1;
                            let hidden = drawn_tree && !tree(n) && !is_air(n);
                            if drawn_tree != tree(n) && !hidden {
                                wrong += 1;
                                if std::env::var("EQ_DEBUG").is_ok() && wrong < 20 {
                                    eprintln!("tree at {:?}: {src:?} drawn {} at rest {n}", t.h, if drawn_tree { "tree" } else { "none" });
                                }
                            }
                        }
                    }
                }
            }
            assert!(looked > 1000 && wrong == 0, "seed {seed}: {wrong} of {looked} blocks round the fallen trees change at the swap");
            // (and the scree and the gaps' rubble's top: every edit after the swap due from it, none sent before)
            let post: Vec<f32> = r.edits.iter().filter(|e| !e.2.urgent && e.2.sent.is_none()).map(|e| e.0).collect();
            assert!(post.len() > 50 && post.iter().all(|&t| t >= EQ_REST + POST_T0 - 0.01), "seed {seed}: {} edits after, the first at {:?}", post.len(), post.iter().copied().reduce(f32::min));
            let early = post.iter().filter(|&&t| t < EQ_REST + 3.5).count();
            assert!(early * 2 > post.len(), "seed {seed}: {early} of {} in the first three seconds", post.len());
            eprintln!("seed {seed}: {popped} of {seen} blocks in view appear at the swap; {} edits after it", post.len());
        }
    }

    /// A marker bed is followed along the main fault's face at rest: in neighbouring face columns of one plate its foot is
    /// at the same height or a block off.
    #[test]
    fn eq_land_marker_beds_run_along_the_face() {
        let mut r = run(37, CASES[0].1);
        let pl = r.pl;
        let mut cols: HashSet<(i32, i32)> = HashSet::new();
        for e in r.edits.iter().filter(|e| !e.2.urgent) {
            cols.extend(e.2.runs.iter().map(|u| (u.x, u.z)));
        }
        // (the canyon's columns: lava on their floor; the face columns beside them, high over it)
        let canyon: HashSet<(i32, i32)> = cols.iter().copied().filter(|&(x, z)| (-60..40).any(|y| r.world.at(x, y, z) == "minecraft:lava")).collect();
        let mut feet: HashMap<(i32, i32), Vec<i32>> = HashMap::new();
        for &(x, z) in &canyon {
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let (fx, fz) = (x + dx, z + dz);
                if canyon.contains(&(fx, fz)) || feet.contains_key(&(fx, fz)) {
                    continue;
                }
                let g = r.world.ground(fx, fz);
                let v: Vec<i32> = (-50..g).filter(|&y| r.world.at(fx, y, fz) == "minecraft:calcite" && r.world.at(fx, y - 1, fz) != "minecraft:calcite").collect();
                feet.insert((fx, fz), v);
            }
        }
        let (mut pairs, mut kept) = (0, 0);
        for (&(x, z), v) in &feet {
            let i = lands_on(&pl, x, z).0;
            for (dx, dz) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
                let Some(w) = feet.get(&(x + dx, z + dz)) else { continue };
                if lands_on(&pl, x + dx, z + dz).0 != i {
                    continue;
                }
                for &y in v {
                    let Some(near) = w.iter().map(|&b| (b - y).abs()).min() else { continue };
                    if near <= 4 {
                        pairs += 1;
                        if near <= 1 {
                            kept += 1;
                        }
                    }
                }
            }
        }
        assert!(pairs > 300 && kept * 100 > pairs * 95, "{kept} of {pairs} marker feet continue into the next column");
        eprintln!("{kept} of {pairs} marker feet continue into the next column");
    }

    // ---- pictures ------------------------------------------------------------------------------------------------------
    fn colour(n: &str) -> [f32; 3] {
        match n.trim_start_matches("minecraft:").split('[').next().unwrap_or("") {
            "water" => [0.2, 0.35, 0.8],
            "lava" => [1.0, 0.45, 0.05],
            "magma_block" => [0.7, 0.25, 0.05],
            "grass_block" => [0.4, 0.65, 0.3],
            "sand" => [0.85, 0.8, 0.55],
            "dirt" | "coarse_dirt" => [0.5, 0.35, 0.2],
            "oak_log" => [0.4, 0.3, 0.15],
            "oak_leaves" => [0.15, 0.45, 0.12],
            "stone" => [0.5, 0.5, 0.5],
            "andesite" => [0.6, 0.6, 0.58],
            "granite" => [0.62, 0.42, 0.36],
            "calcite" => [0.9, 0.9, 0.88],
            "tuff" => [0.42, 0.44, 0.38],
            "smooth_basalt" | "basalt" | "blackstone" => [0.18, 0.18, 0.2],
            "deepslate" | "polished_deepslate" | "cobbled_deepslate" => [0.28, 0.28, 0.3],
            "cobblestone" | "mossy_cobblestone" => [0.45, 0.45, 0.42],
            "gravel" => [0.55, 0.52, 0.5],
            "coal_ore" => [0.1, 0.1, 0.1],
            _ => [0.8, 0.0, 0.8],
        }
    }
    fn top_view(world: &mut World, cx: i32, cz: i32, half: i32) -> Vec<u8> {
        let mut img = Vec::with_capacity((4 * half * half * 3) as usize);
        for z in cz - half..cz + half {
            for x in cx - half..cx + half {
                let c = world.col(x, z).clone();
                let k = c.iter().rposition(|&b| !is_air(world.names[b as usize])).unwrap_or(0);
                let y = Y0 + k as i32;
                let base = colour(world.names[c[k] as usize]);
                // (lit from the north-west by the height's slope)
                let hn = |world: &mut World, x: i32, z: i32| {
                    let c = world.col(x, z).clone();
                    Y0 + c.iter().rposition(|&b| !is_air(world.names[b as usize])).unwrap_or(0) as i32
                };
                let slope = (y - hn(world, x - 1, z - 1)) as f32;
                let shade = ((0.55 + (y - 40) as f32 / 90.0) * (1.0 + slope * 0.08).clamp(0.4, 1.6)).clamp(0.05, 1.4);
                for ch in 0..3 {
                    img.push((base[ch] * shade * 255.0).clamp(0.0, 255.0) as u8);
                }
            }
        }
        img
    }
    fn write_ppm(path: &str, w: i32, h: i32, img: &[u8]) {
        let mut f = format!("P6\n{w} {h}\n255\n").into_bytes();
        f.extend_from_slice(img);
        std::fs::write(path, f).unwrap();
    }
    /// A slice down through the land across the main fault at the target, `span` each side, each block `px` pixels.
    fn side_view(world: &mut World, pl: &EqPlates, along: i32, span: i32, px: i32) -> (i32, i32, Vec<u8>) {
        let (y0, y1) = (-64, 160);
        let (w, h) = ((2 * span + 1) * px, (y1 - y0) * px);
        let mut img = vec![0u8; (w * h * 3) as usize];
        let (fx, fz) = (pl.fdir[0], pl.fdir[1]);
        for s in -span..=span {
            let x = pl.block[0] + (f64::from(fx) * f64::from(along) - f64::from(fz) * f64::from(s)).round() as i32;
            let z = pl.block[2] + (f64::from(fz) * f64::from(along) + f64::from(fx) * f64::from(s)).round() as i32;
            for y in y0..y1 {
                let n = world.at(x, y, z);
                let c = if is_air(n) { [0.7, 0.82, 0.95] } else { colour(n) };
                for py in 0..px {
                    for pxx in 0..px {
                        let (ix, iy) = ((s + span) * px + pxx, (y1 - 1 - y) * px + py);
                        let o = ((iy * w + ix) * 3) as usize;
                        for ch in 0..3 {
                            img[o + ch] = (c[ch] * 255.0) as u8;
                        }
                    }
                }
            }
        }
        (w, h, img)
    }

    /// The main fault's face as seen from the middle of the canyon looking across it (`way` 1 toward side A, -1 toward
    /// side B): along the fault 150 each way, the first block met within 60, darker the further, 2 pixels a block.
    fn face_view(world: &mut World, pl: &EqPlates, way: f32) -> (i32, i32, Vec<u8>) {
        let (y0, y1, span, px) = (-64, 160, 150, 2);
        let (w, h) = ((2 * span + 1) * px, (y1 - y0) * px);
        let mut img = vec![0u8; (w * h * 3) as usize];
        let (f, n) = (pl.fdir, [-pl.fdir[1] * way, pl.fdir[0] * way]);
        for u in -span..=span {
            for y in y0..y1 {
                let mut c = [0.7, 0.82, 0.95];
                for d in 0..60 {
                    let x = pl.block[0] + (f[0] * u as f32 + n[0] * d as f32).round() as i32;
                    let z = pl.block[2] + (f[1] * u as f32 + n[1] * d as f32).round() as i32;
                    let b = world.at(x, y, z);
                    if !is_air(b) {
                        let k = 1.0 - d as f32 / 90.0;
                        c = colour(b).map(|v| v * k);
                        break;
                    }
                }
                for py in 0..px {
                    for pxx in 0..px {
                        let (ix, iy) = ((u + span) * px + pxx, (y1 - 1 - y) * px + py);
                        let o = ((iy * w + ix) * 3) as usize;
                        for ch in 0..3 {
                            img[o + ch] = (c[ch] * 255.0) as u8;
                        }
                    }
                }
            }
        }
        (w, h, img)
    }

    /// `EQ_VIEW_OUT=DIR [EQ_SEED=N] cargo test --release eq_land_picture -- --ignored --nocapture`: the synthetic land from
    /// above before, after the cut and at rest (`before.ppm`, `cut.ppm`, `rest.ppm`), and slices down through it across the
    /// main fault at rest (`side.ppm`, `side_n.ppm`, `side_s.ppm`: at the target and 60 along it each way, 3 pixels a block).
    #[test]
    #[ignore]
    fn eq_land_picture() {
        let out = std::env::var("EQ_VIEW_OUT").unwrap_or_else(|_| "/tmp".into());
        let seed: u32 = std::env::var("EQ_SEED").map_or(37, |v| v.parse().unwrap());
        let me = [10.5, 66.0, 260.0];
        let mut r = run(seed, me);
        let pl = r.pl;
        let half = 220;
        let (cx, cz) = (pl.block[0], pl.block[2]);
        let mut world = World::new();
        write_ppm(&format!("{out}/before.ppm"), 2 * half, 2 * half, &top_view(&mut world, cx, cz, half));
        for e in r.edits.iter().filter(|e| e.2.urgent) {
            world.apply(&e.2);
        }
        write_ppm(&format!("{out}/cut.ppm"), 2 * half, 2 * half, &top_view(&mut world, cx, cz, half));
        write_ppm(&format!("{out}/rest.ppm"), 2 * half, 2 * half, &top_view(&mut r.world, cx, cz, half));
        for (name, along) in [("side", 0), ("side_n", 60), ("side_s", -60)] {
            let (w, h, img) = side_view(&mut r.world, &pl, along, 110, 3);
            write_ppm(&format!("{out}/{name}.ppm"), w, h, &img);
        }
        let (w, h, img) = side_view(&mut world, &pl, 0, 110, 3);
        write_ppm(&format!("{out}/side_cut.ppm"), w, h, &img);
        for (name, way) in [("face_a", 1.0), ("face_b", -1.0)] {
            let (w, h, img) = face_view(&mut r.world, &pl, way);
            write_ppm(&format!("{out}/{name}.ppm"), w, h, &img);
        }
        eprintln!("wrote {out}/before.ppm, cut.ppm, rest.ppm, side*.ppm ({} edits; offsets {:?})", r.edits.len(), (0..EQ_PLATES).map(|i| offset_of(&pl, i)).collect::<Vec<_>>());
    }

    /// `cargo test --release eq_land_stage_timing -- --ignored --nocapture`, on its own: no stage of the land's work over
    /// 1.3 ms natively (the Nuke's bound for a stage well under a tick's fuel).
    #[test]
    #[ignore]
    fn eq_land_stage_timing() {
        if cfg!(debug_assertions) {
            return;
        }
        let mut best: Vec<f64> = Vec::new();
        let mut when: Vec<f32> = Vec::new();
        for _ in 0..2 {
            let r = run(37, [10.5, 66.0, 260.0]);
            when = r.stages.iter().map(|s| s.1).collect();
            let ms: Vec<f64> = r.stages.iter().map(|s| s.2).collect();
            best = if best.is_empty() { ms } else { best.iter().zip(&ms).map(|(a, b)| a.min(*b)).collect() };
        }
        let mut idx: Vec<usize> = (0..best.len()).collect();
        idx.sort_by(|a, b| best[*b].total_cmp(&best[*a]));
        eprintln!("{} stages; the heaviest (at, ms) {:?}", best.len(), idx.iter().take(12).map(|&i| (when[i], (best[i] * 100.0).round() / 100.0)).collect::<Vec<_>>());
        assert!(best[idx[0]] < 1.3, "a stage took {:.2} ms", best[idx[0]]);
    }
}

#[cfg(test)]
mod costs {
    use super::super::earthquake::eq_plates;
    use std::collections::BTreeMap;
    use super::super::Target;
    use super::*;
    /// `cargo test --release eq_land_costs -- --ignored --nocapture`: nanoseconds natively for each piece of work the
    /// meter counts, beside `where_at`'s (whose count, EVAL, the fork's `mod_soak` measured): what the counts should be.
    #[test]
    #[ignore]
    fn eq_land_costs() {
        let t = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let pl = eq_plates(&t, [10.5, 66.0, 260.0], 37.0, true);
        let mut wk = Work::new(pl, None);
        let time = |n: usize, f: &mut dyn FnMut(usize)| {
            let s = std::time::Instant::now();
            for i in 0..n {
                f(i);
            }
            s.elapsed().as_nanos() as f64 / n as f64
        };
        let mut acc = 0.0f32;
        let ev = time(200_000, &mut |i| acc += pl.where_at((i % 400) as f32 - 200.0, (i / 400) as f32 - 250.0).1);
        // (the whole disc's plates, as the cut does it)
        let s = std::time::Instant::now();
        let (a0, b0, cn) = wk.cgrid;
        for k in 0..(cn * cn) {
            wk.eval((a0 + k % cn) * 16, (b0 + k / cn) * 16, 16);
            wk.cdone[k as usize] = true;
        }
        let all = s.elapsed().as_nanos() as f64;
        let cuts = wk.cutk.iter().filter(|&&k| k != 0).count();
        // (the cut's items and edits for every chunk, timed apart)
        crate::ground::set_test(Some(|x, z| Some(66 + (x + z).rem_euclid(3))));
        crate::ground::set_test_wet(Some(|_, _| None));
        crate::meter::reset();
        let s = std::time::Instant::now();
        let items: Vec<Vec<Item>> = (0..(cn * cn) as u32).map(|k| wk.cut_items(k)).filter(|v| !v.is_empty()).collect();
        let t_items = s.elapsed().as_nanos() as f64 / 1e6;
        let m_items = crate::meter::spent();
        crate::meter::reset();
        let nit: usize = items.iter().map(Vec::len).sum();
        let cols: Vec<(i32, i32)> = items.iter().flatten().filter(|t| t.wall).map(|t| (t.x, t.z)).collect();
        crate::ground::test_answer(crate::ground::new_tag(), &cols);
        let s = std::time::Instant::now();
        let mut nruns = 0;
        let mut cat: BTreeMap<(bool, u8), (usize, usize)> = BTreeMap::new();
        for it in items {
            for t in &it {
                let one = vec![*t];
                let n: usize = wk.cut_edits(one).iter().map(|e| e.1.runs.len()).sum();
                let v = cat.entry((t.main, if t.wall { t.k } else { 0 })).or_default();
                v.0 += 1;
                v.1 += n;
                nruns += n;
            }
        }
        eprintln!("(main, k): (columns, runs) {cat:?}");
        let t_edits = s.elapsed().as_nanos() as f64 / 1e6;
        let m_edits = crate::meter::spent();
        eprintln!("cut items {t_items:.1} ms ({nit} items, {:.0}M counted), edits {t_edits:.1} ms ({nruns} runs, {} walls, {:.0}M counted)", m_items as f64 / 1e6, wk.walls.len(), m_edits as f64 / 1e6);
        let n = wk.plate.len();
        let wall = time(n, &mut |c| acc += wk.wall_of(c).map_or(0.0, |w| w.0));
        let mut e = Blocks::default();
        let strata = time(20_000, &mut |i| wk.strata.runs(&mut e, i as i32, 0, i as i32, 0, -40, 90, wk.strata.shift(i as i32, 7)));
        let shift = time(100_000, &mut |i| acc += wk.strata.shift(i as i32, 3) as f32);
        eprintln!("where_at {ev:.0} ns ({EVAL} counted); the disc's plates {:.1} ms ({} cells, {cuts} cut), {:.0} ns a cell", all / 1e6, n, all / n as f64);
        eprintln!("wall_of {wall:.0} ns a cell; strata runs 130 high {strata:.0} ns; shift {shift:.0} ns ({acc})");
        let k = EVAL as f64 / ev;
        eprintln!("so a ns is about {k:.0} of the meter's");
        super::PARTS.with(|p| *p.borrow_mut() = [(0.0, 0); 9]);
        let _ = super::tests::run_for_costs();
        for (i, (ns, m)) in super::PARTS.with(|p| *p.borrow()).iter().enumerate() {
            eprintln!("part {i} ({}): {:.1} ms natively, {:.0}M by that, {:.0}M counted: {:.1} times", ["cut", "read", "decide", "canyon", "gaps", "scree", "mark", "chunks", "trees"][i], ns / 1e6, ns * k / 1e6, *m as f64 / 1e6, ns * k / (*m).max(1) as f64);
        }
    }
}
