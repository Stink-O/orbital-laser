//! The Hurricane's plan: a hurricane spun up over the target. A spiral cloud deck gathers over it and starts to turn,
//! its bands reaching far out; the eye clears, the eyewall rises round it and the wind spins up; then the wind tears the
//! land up from the eyewall out: the plants and the leaves first, then whole trees, then the ground itself, and it all
//! goes up round the eyewall, thousands of blocks at once spiralling up into the cloud, whole trees tumbling among them.
//! Mobs are carried round with it, and the player too (`carry.rs`) if the wind reaches them; then the winds drop, the
//! storm flings everything out and it rains down, and the cloud breaks up.
//!
//! What it lifts is the real land: every column out to HU_READ is read (`world.read-columns`, as the Nuke's), and as the
//! wind's front reaches it (`front_t`) its trees, plants and loose top blocks are taken out of the world
//! (`world.edit-blocks`, a chunk's on one tick) and drawn by the pass (shaders/hurricane.wgsl) as voxels in their real
//! colours (strike/sh_land.rs's MATS, tinted by the biome as the game tints them): the trees whole, as rigid groups
//! (up to HU_NT, their trunks and their canopies as read, `hu_tree`), the rest as a field of blocks flying round the
//! eyewall in rings (the pass's `hu_debris`), each ring's blocks coloured from what was torn up under it (`Pal`).
//! As the storm flings it all out, it comes down as real blocks where the pass draws it landing (`hu_landings`): each
//! tree and piece of a building lying where it lands, rubble from what flew round each ring; the mobs flung with it.
//!
//! Timeline (HU_LEN 64 s): the cloud gathers and starts to turn (0-10 s); the wind spins up (to full by 26 s, `SPIN_K`),
//! the eye clearing by 14 s; the front tears at the land from the eyewall at HU_F0 (15 s) out to HU_R_LIFT by HU_F1
//! (35 s); the storm at its height to 44 s; at HU_FLING (46 s) the winds drop and everything is flung out, down by about
//! 52 s; the cloud breaks up from HU_CLEAR (54 s). A minute: as long as the slow, menacing spin-up and a peak long
//! enough to watch the debris go round take, and no longer than the Nuke's aftermath.
//!
//! Keep the HU_* here and in hurricane.wgsl in step (the timeline, the wind, the rings, the table's layout).
// (the pass's mirrors, which only the tests read here: kept in step with it all the same)
#![cfg_attr(not(test), allow(dead_code))]
use super::hu_blocks::{HU_BLOCKS, HuBlock};
use super::sh_land::{self, Class};
use super::{Act, Blocks, Plan, Rng, Target, mh, pk_load_rows, sound_from, vnoise};
use crate::sdk::atlas;
use crate::lasers::Laser;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;

// ---- the storm's life ---------------------------------------------------------------------------------------------
pub(super) const HU_LEN: f32 = 64.0;
pub(super) const HU_F0: f64 = 15.0;
pub(super) const HU_F1: f64 = 35.0;
pub(crate) const HU_FLING: f64 = 46.0;
#[allow(dead_code)]
pub(super) const HU_CLEAR: f64 = 54.0;
/// The eye (calm: nothing in it is touched or carried), the inner edge of what the wind tears at, the eyewall (the
/// strongest wind), how far out trees are uprooted, and how far out plants and leaves are stripped.
pub(crate) const HU_R_EYE: f64 = 26.0;
pub(super) const HU_R_IN: f64 = 32.0;
pub(super) const HU_R_W: f64 = 62.0;
pub(super) const HU_R_LIFT: f64 = 150.0;
pub(super) const HU_R_PLANTS: f64 = 175.0;
/// The band whose ground is torn up (one to three blocks deep, deepest under the eyewall).
const HU_DIG0: f64 = 34.0;
const HU_DIG1: f64 = 105.0;
/// The wind at the eyewall at its height, blocks a second; the storm turns cyclonically (seen from above, the way
/// from east to north: its angle round from +x towards +z falls).
pub(super) const HU_V: f64 = 40.0;
const HU_SPIN: f64 = -1.0;
/// How hard the wind blows (0 to 1) through the strike, at these times, straight between them.
const SPIN_K: [(f64, f64); 7] = [(0.0, 0.04), (8.0, 0.15), (26.0, 1.0), (44.0, 1.0), (50.0, 0.35), (58.0, 0.08), (64.0, 0.0)];

pub(crate) fn spin(t: f64) -> f64 {
    for w in SPIN_K.windows(2) {
        let ((t0, s0), (t1, s1)) = (w[0], w[1]);
        if t <= t1 {
            return s0 + (s1 - s0) * ((t - t0) / (t1 - t0)).clamp(0.0, 1.0);
        }
    }
    0.0
}
/// The wind's strength summed over the strike so far (seconds at full strength): how far round it has turned things.
pub(super) fn spin_int(t: f64) -> f64 {
    let mut s = 0.0;
    for w in SPIN_K.windows(2) {
        let ((t0, s0), (t1, s1)) = (w[0], w[1]);
        if t <= t0 {
            break;
        }
        let e = t.min(t1);
        let se = s0 + (s1 - s0) * (e - t0) / (t1 - t0);
        s += 0.5 * (s0 + se) * (e - t0);
    }
    s
}
/// The wind's shape out from the middle (a Rankine vortex, softened): rising to the eyewall, falling off past it.
pub(super) fn wind_shape(r: f64) -> f64 {
    if r < HU_R_W { r / HU_R_W } else { (HU_R_W / r).powf(0.55) }
}
/// How fast the wind turns round the middle at r at full strength (radians a second).
pub(crate) fn omega(r: f64) -> f64 {
    HU_V * wind_shape(r) / r.max(1.0)
}
/// How far round (radians) what the wind carries at r has turned by `t`, from where it was at the start.
pub(super) fn phase(r: f64, t: f64) -> f64 {
    HU_SPIN * omega(r) * spin_int(t)
}
/// When the wind's front reaches r (it starts to tear at the land there): from the eyewall at HU_F0, in to HU_R_IN
/// over 3 s and out to HU_R_LIFT by HU_F1, then on more slowly. None in the eye, and past HU_R_PLANTS.
pub(crate) fn front_t(r: f64) -> Option<f64> {
    if !(HU_R_IN..=HU_R_PLANTS).contains(&r) {
        return None;
    }
    Some(if r < HU_R_W {
        HU_F0 + 3.0 * (HU_R_W - r) / (HU_R_W - HU_R_IN)
    } else {
        HU_F0 + (HU_F1 - HU_F0) * ((r - HU_R_W) / (HU_R_LIFT - HU_R_W)).powf(1.25)
    })
}
fn smooth(a: f64, b: f64, x: f64) -> f64 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}

// ---- the field of blocks round the eyewall (the pass's hu_debris; kept in step) --------------------------------------
/// The rings the blocks fly round in: HU_NR of them, HU_RING_W wide from HU_RING0 out, each turning at its own middle's
/// rate; their blocks on a grid of HU_CELL-block cells round each ring and up it, a block at most in each.
pub(super) const HU_NR: usize = 13;
pub(super) const HU_RING0: f64 = 30.0;
pub(super) const HU_RING_W: f64 = 10.0;
pub(super) const HU_CELL: f64 = 3.0;
pub(super) fn ring_r(k: usize) -> f64 {
    HU_RING0 + HU_RING_W * (k as f64 + 0.5)
}
/// How high a ring's blocks go (they climb it and are lost in the eyewall's cloud, or skim the land further out), how
/// fast they climb at full strength, and how many of its cells hold a block at its height.
pub(super) fn ring_h(r: f64) -> f64 {
    30.0 + 218.0 * (1.0 - smooth(70.0, 150.0, r))
}
pub(super) fn ring_rise(r: f64) -> f64 {
    2.0 + 13.0 * (1.0 - smooth(60.0, 140.0, r))
}
pub(super) fn ring_dens(r: f64) -> f64 {
    0.045 + 0.115 * (1.0 - smooth(105.0, 160.0, r))
}
/// Whether a ring's blocks are about: from its front, when they start to rise out of the land (none appears in the
/// air: the pass's `hu_block` leaves empty the cells that were over the land as the front came), until the last has
/// come back down after the fling, shattering where it hits.
pub(super) fn ring_on(r: f64, t: f64) -> f64 {
    let Some(f) = front_t(r) else { return 0.0 };
    smooth(f, f + 1.0, t) * (1.0 - smooth(HU_FLING + 7.0, HU_FLING + 8.0, t))
}
/// How high a ring's blocks have climbed out of the land by `t` (they fill it from the ground up).
pub(super) fn ring_fill(r: f64, t: f64) -> f64 {
    let Some(f) = front_t(r) else { return 0.0 };
    (ring_rise(r) * (spin_int(t.min(HU_FLING)) - spin_int(f))).clamp(0.0, ring_h(r))
}
/// About how many blocks are in the air at `t` (the pass's field: its rings' cells times how many hold one).
pub(super) fn hu_in_air(t: f64) -> f64 {
    (0..HU_NR)
        .map(|k| {
            let r = ring_r(k);
            let around = (TAU * r / HU_CELL).floor();
            around * (ring_fill(r, t) / HU_CELL) * ring_dens(r) * ring_on(r, t)
        })
        .sum()
}
/// Of those, about how many are under the eyewall's cloud (below HU_SEEN over the land), in plain sight.
pub(super) const HU_SEEN: f64 = 110.0;
pub(super) fn hu_in_sight(t: f64) -> f64 {
    (0..HU_NR)
        .map(|k| {
            let r = ring_r(k);
            let around = (TAU * r / HU_CELL).floor();
            around * (ring_fill(r, t).min(HU_SEEN) / HU_CELL) * ring_dens(r) * ring_on(r, t)
        })
        .sum()
}

// ---- the table the pass reads (render.set-data) -------------------------------------------------------------------
/// A header (how many trees, the middle's ground over the target block's top, whether the land is the world's), the
/// rings' blocks from HU_PAL (HU_PN a ring: each a block type's number), the block types from HU_BK (HU_BKW words
/// each: `bk_words`; up to HU_NBK of them, each a block as tinted where it was torn up), the trees from HU_T (HU_TW
/// words each: `TreeRec::words`), the land's height round the middle from HU_G (HU_GR rings of HU_GA, each the ground
/// over the middle's).
///
/// Every block the pass draws is a block type and a face: its colour is looked up for that face (the pass's `hu_face`),
/// so drawing the game's own textures instead of the colours they average to needs only that lookup changed (and a
/// block type's second word's high half, its block in HU_BLOCKS now, to name its sprite).
pub(super) const HU_PAL: usize = 64;
pub(super) const HU_PN: usize = 32;
pub(super) const HU_BK: usize = 512;
pub(super) const HU_BKW: usize = 12;
pub(super) const HU_NBK: usize = 512;
pub(super) const HU_T: usize = HU_BK + HU_BKW * HU_NBK;
pub(super) const HU_TW: usize = 28;
pub(super) const HU_NT: usize = 128;
pub(super) const HU_G: usize = HU_T + HU_TW * HU_NT;
pub(super) const HU_GR: usize = 16;
pub(super) const HU_GA: usize = 64;
pub(super) const HU_G_STEP: f64 = 11.0;
pub(super) const HU_WORDS: usize = HU_G + HU_GR * HU_GA;

/// A colour (sRGB) as the pass reads it: 5-6-5.
fn c565(c: [u8; 3]) -> u32 {
    (u32::from(c[0]) >> 3) << 11 | (u32::from(c[1]) >> 2) << 5 | (u32::from(c[2]) >> 3)
}
/// Block `name`'s place in HU_BLOCKS (none for a block the table doesn't know: a mod's, left alone).
pub(super) fn hu_block(name: &str) -> Option<u16> {
    let n = name.split('[').next().unwrap_or(name);
    HU_BLOCKS.binary_search_by(|b| b.name.cmp(n)).ok().map(|i| i as u16)
}
/// Block `b`'s faces' colours (top, sides, bottom), tinted as the game tints it with `grass` and `foliage` (0xRRGGBB;
/// 0 the default's).
pub(super) fn bk_rgb(b: u16, grass: u32, foliage: u32) -> [[u8; 3]; 3] {
    let k: &HuBlock = &HU_BLOCKS[b as usize];
    let t = match k.tint {
        1 => if grass == 0 { 0x91BD59 } else { grass },
        2 => if foliage == 0 { 0x77AB2F } else { foliage },
        _ => 0xFFFFFF,
    };
    let tint = |c: [u8; 3]| -> [u8; 3] {
        let t = [(t >> 16) & 255, (t >> 8) & 255, t & 255];
        [0, 1, 2].map(|i| (u32::from(c[i]) * t[i] / 255) as u8)
    };
    // (a grass block's sides and bottom are its dirt: only its top is tinted)
    if b as usize == grass_block() {
        return [tint(k.top), k.side, k.bottom];
    }
    [tint(k.top), tint(k.side), tint(k.bottom)]
}
fn grass_block() -> usize {
    hu_block("minecraft:grass_block").map_or(usize::MAX, usize::from)
}
/// A block type's words for the pass (HU_BKW): its top's average colour and its sides', its bottom's and which block
/// it is; then for its top, its bottom and its sides (the game's up, down and north) the faces the game draws there
/// (`face_words`), the textures in the game's block sprite arrays (atlas.block-sprites), where it has them.
fn bk_words(b: u16, grass: u32, foliage: u32) -> [u32; HU_BKW] {
    let [t, s, d] = bk_rgb(b, grass, foliage);
    let mut w = [0u32; HU_BKW];
    w[0] = c565(t) | c565(s) << 16;
    w[1] = c565(d) | u32::from(b) << 16;
    // (its tints, to pack it again from the table alone: `hu_repack`)
    let q = |c: u32| if c == 0 { 0 } else { c565([(c >> 16) as u8, (c >> 8) as u8, c as u8]).max(1) };
    w[HU_BKW - 1] = q(grass) | q(foliage) << 16;
    if let Some(f) = sprites_of(b) {
        for (k, side) in [1usize, 0, 2].into_iter().enumerate() {
            w[2 + 3 * k..5 + 3 * k].copy_from_slice(&face_words(f.sides.get(side).map_or(&[][..], |v| &v[..]), grass, foliage));
        }
    }
    w
}
/// A side's faces as the pass reads them, three words: its first face (whole, on the side's plane), the face laid over
/// it if any (a grass block's tinted overlay), each `1 | cutout << 1 | layer << 2 | translucent << 15` (the pass sees
/// through a cut-out face's clear pixels and partly through a translucent one) and its tint (5-6-5, 0xFFFF none) over
/// it; then how the texture runs across the side (u0, v0, du-u, du-v, dv-u, dv-v, each -1, 0 or 1, two bits
/// apiece). A face in a sprite array past the first (a content mod's) is left to its colour.
fn face_words(faces: &[atlas::Face], grass: u32, foliage: u32) -> [u32; 3] {
    let tint = |t: &atlas::Tint| -> u32 {
        let c = match t {
            atlas::Tint::None => return 0xFFFF,
            atlas::Tint::Grass => if grass == 0 { 0x91BD59 } else { grass },
            atlas::Tint::Foliage | atlas::Tint::DryFoliage => if foliage == 0 { 0x77AB2F } else { foliage },
            atlas::Tint::Water => 0x3F76E4,
            atlas::Tint::Fixed(c) => *c,
        };
        c565([(c >> 16) as u8, (c >> 8) as u8, c as u8])
    };
    let word = |f: &atlas::Face| -> u32 {
        if f.sprite.array != 0 || f.sprite.layer >= 1 << 13 {
            return 0;
        }
        1 | u32::from(f.sprite.cutout) << 1 | f.sprite.layer << 2 | u32::from(f.translucent) << 15 | tint(&f.tint) << 16
    };
    let mut w = [0u32; 3];
    let flat: Vec<&atlas::Face> = faces.iter().filter(|f| f.inset < 0.01).collect();
    if let Some(f) = flat.first() {
        w[0] = word(f);
        if let Some(o) = flat.get(1) {
            w[1] = word(o);
        }
        let q = |v: f32| ((v.round() as i32).clamp(-1, 1) + 1) as u32;
        let (u0, v0, duu, duv, dvu, dvv) = f.uv;
        w[2] = q(u0) | q(v0) << 2 | q(duu) << 4 | q(duv) << 6 | q(dvu) << 8 | q(dvv) << 10;
    }
    w
}
thread_local! {
    /// Each block's sprites as the game last answered (by its place in HU_BLOCKS), and the resources they were for.
    static SPRITES: std::cell::RefCell<(u64, crate::ground::FxMap<u16, Option<std::rc::Rc<atlas::BlockFaces>>>)> = Default::default();
}
/// Block `b`'s sprites, asked of the game once per resources (`atlas.resources-version`).
fn sprites_of(b: u16) -> Option<std::rc::Rc<atlas::BlockFaces>> {
    SPRITES.with(|s| {
        let mut s = s.borrow_mut();
        let v = atlas::resources_version();
        if s.0 != v {
            *s = (v, Default::default());
        }
        s.1.entry(b)
            .or_insert_with(|| {
                crate::meter::spend(40_000);
                atlas::block_sprites(&[HU_BLOCKS[b as usize].name.to_string()]).pop().flatten().map(std::rc::Rc::new)
            })
            .clone()
    })
}
/// The resources the textures were last packed for changed (a resource pack turned on or off): the block types in
/// `data` (a Hurricane's table: how many in its header's word 3) packed again for the new layers, from the table alone.
pub(crate) fn hu_repack(data: &mut [u32]) {
    let n = (data.get(3).copied().unwrap_or(0) as usize).min(HU_NBK);
    if data.len() < HU_BK + HU_BKW * n {
        return;
    }
    let back = |c: u32| -> u32 {
        if c == 0 {
            return 0;
        }
        let (r, g, b) = ((c >> 11) & 31, (c >> 5) & 63, c & 31);
        (r << 3 | r >> 2) << 16 | (g << 2 | g >> 4) << 8 | (b << 3 | b >> 2)
    };
    for i in 0..n {
        let o = HU_BK + HU_BKW * i;
        let (b, t) = ((data[o + 1] >> 16) as u16, data[o + HU_BKW - 1]);
        if (b as usize) < HU_BLOCKS.len() {
            data[o..o + HU_BKW].copy_from_slice(&bk_words(b, back(t & 0xFFFF), back(t >> 16)));
        }
    }
}
/// The block types every strike's table starts with (its rings' blocks until the land is read): grass, dirt, oak
/// leaves, an oak log, coarse dirt.
fn default_kinds() -> Kinds {
    let mut k = Kinds::default();
    for n in ["minecraft:grass_block", "minecraft:dirt", "minecraft:oak_leaves", "minecraft:oak_log", "minecraft:coarse_dirt"] {
        if let Some(b) = hu_block(n) {
            k.of(b, 0, 0);
        }
    }
    k.told = k.list.len();
    k
}
/// The block types a strike's table holds (each a block as tinted where it was torn up), by what they are.
#[derive(Default)]
struct Kinds {
    list: Vec<(u16, u32, u32)>,
    told: usize,
}
impl Kinds {
    /// Block `b`'s type as tinted by `grass` and `foliage` (quantised, so a wood's leaves are a few types, not one a
    /// column); the last type once the table's room is taken.
    fn of(&mut self, b: u16, grass: u32, foliage: u32) -> u16 {
        crate::meter::spend(150);
        let q = |c: u32| c & 0xF0F0F0;
        let (g, f) = match HU_BLOCKS[b as usize].tint {
            1 => (q(grass), 0),
            2 => (0, q(foliage)),
            _ => (0, 0),
        };
        if let Some(i) = self.list.iter().position(|e| *e == (b, g, f)) {
            return i as u16;
        }
        if self.list.len() >= HU_NBK {
            return (HU_NBK - 1) as u16;
        }
        self.list.push((b, g, f));
        (self.list.len() - 1) as u16
    }
}

/// A rigid tree as the pass draws it: where it stood (off the middle), its ground over the middle's, when it is torn
/// up, its trunk (its height, its block) and its leaves' block, and its canopy over the 7 by 7 columns round its trunk (each column's lowest and
/// highest leaf over its ground, 0 to 31; none where the lowest is over the highest).
#[derive(Clone, Debug)]
pub(super) struct TreeRec {
    pub x: f64,
    pub z: f64,
    pub gdy: f64,
    pub t_up: f64,
    pub trunk: u8,
    /// Its trunk's and its leaves' block types (`Kinds`), and their blocks (HU_BLOCKS).
    pub wood_bk: u16,
    pub leaf_bk: u16,
    pub wood: u16,
    pub leaf: u16,
    pub spans: [(u8, u8); 49],
    /// Where it comes down (`tree_landing`): when, the real ground's top there (over the middle's ground, as `gdy`),
    /// and the way it lies (its trunk along it, radians round from +x towards +z); 1e9, 0, 0 if it is never flung.
    pub t_land: f64,
    pub yl: f64,
    pub yaw: f64,
    /// When it breaks apart in the air (its canopy and trunk flying apart as separate blocks, coming down as the
    /// field's do, shattered where they hit: no real landing of its own); 1e9 if it stays whole.
    pub t_break: f64,
}
impl TreeRec {
    pub fn words(&self) -> [u32; HU_TW] {
        let mut w = [0u32; HU_TW];
        w[0] = (self.x as f32).to_bits();
        w[1] = (self.z as f32).to_bits();
        w[2] = (self.gdy as f32).to_bits();
        w[3] = (self.t_up as f32).to_bits();
        let hi = self.spans.iter().filter(|s| s.0 <= s.1).map(|s| s.1).max().unwrap_or(0).max(self.trunk);
        w[4] = u32::from(self.trunk.min(31)) | u32::from(hi.min(31)) << 5;
        w[5] = u32::from(self.wood_bk) | u32::from(self.leaf_bk) << 16;
        w[6] = (self.t_break as f32).to_bits();
        // (how far the wind has turned things by the time it is torn up: its path's angle counts from it)
        w[7] = (spin_int(self.t_up) as f32).to_bits();
        for (c, s) in self.spans.iter().enumerate() {
            let v = if s.0 <= s.1 { u32::from(s.0.min(31)) | u32::from(s.1.min(31)) << 5 } else { 31 };
            w[8 + c / 3] |= v << (10 * (c % 3));
        }
        w[25] = (self.t_land as f32).to_bits();
        w[26] = (self.yl as f32).to_bits();
        w[27] = (self.yaw as f32).to_bits();
        w
    }
}

/// Tree `i`'s path (`seed` the strike's), as the pass's `hu_tree_at`: where its middle is at `t` (off the target's
/// middle, over the middle's ground), how far it has tumbled, and whether it is still up (none once it has come down).
/// Torn up at t_up, it rocks over on its roots for half a second, then is lifted, drawn in and up onto its orbit round
/// the eyewall (`r_orb`, `y_orb`), turning with the wind; flung out at HU_FLING, it falls and breaks up as it lands.
pub(super) struct TreeAt {
    pub p: [f64; 3],
    pub up: bool,
}
pub(super) fn tree_orbit(i: u32, seed: u32) -> (f64, f64) {
    (70.0 + 50.0 * mh(i, seed, 0xa1), 25.0 + 115.0 * mh(i, seed, 0xa2).powf(1.4))
}
fn tree_lifted(tr: &TreeRec, i: u32, seed: u32, t: f64) -> [f64; 3] {
    let (r_orb, y_orb) = tree_orbit(i, seed);
    let tau = (t - tr.t_up).max(0.0);
    let r0 = tr.x.hypot(tr.z);
    let a0 = tr.z.atan2(tr.x);
    let r = r_orb + (r0 - r_orb) * (-tau / 5.0).exp();
    let ly = 1.0 - (-(tau - 0.5).max(0.0) / 3.5).exp();
    let cm = 0.6 * f64::from(tr.trunk.max(3));
    let y = tr.gdy + cm + (y_orb - tr.gdy) * ly;
    let a = a0 + HU_SPIN * omega(r) * (spin_int(t) - spin_int(tr.t_up));
    [r * a.cos(), y, r * a.sin()]
}
/// Where a flung tree comes down and how it lies there, as the pass draws it and as its real blocks are laid
/// (`tree_cells`): flung at HU_FLING from `pf` at `v` (`tree_fling`), its middle falls as pf.y + v.y s - 7 s^2 and it
/// lands when that is `yl` + 0.5, `yl` the real ground's top where it comes down (solved twice over: the ground where
/// it would come down on the first guess, then there, then the fall solved again for that ground); it lies along its
/// way over the land, `d`.
pub(super) struct Landing {
    pub t: f64,
    pub yl: f64,
    pub yaw: f64,
    /// Its middle where it lands (off the target's middle), and the way it lies (a unit vector over the land).
    pub m: [f64; 2],
    pub d: [f64; 2],
}
pub(super) fn tree_landing(tr: &TreeRec, i: u32, seed: u32, ground: &dyn Fn(f64, f64) -> f64) -> Option<Landing> {
    if tr.t_up >= HU_FLING || tr.t_break < 1e8 {
        return None;
    }
    let (pf, v) = tree_fling(tr, i, seed);
    let solve = |yl: f64| (v[1] + (v[1] * v[1] + 28.0 * (pf[1] - yl - 0.5).max(0.0)).sqrt()) / 14.0;
    let mut yl = tr.gdy;
    for _ in 0..2 {
        let s = solve(yl);
        yl = ground(pf[0] + v[0] * s, pf[2] + v[2] * s);
    }
    let s = solve(yl);
    let h = v[0].hypot(v[2]).max(1e-9);
    let d = [v[0] / h, v[2] / h];
    Some(Landing { t: HU_FLING + s, yl, yaw: d[1].atan2(d[0]), m: [pf[0] + v[0] * s, pf[2] + v[2] * s], d })
}
/// Its landing, set on the record (for the pass's words).
fn set_landing(tr: &mut TreeRec, i: u32, seed: u32, ground: &dyn Fn(f64, f64) -> f64) {
    match tree_landing(tr, i, seed, ground) {
        Some(l) => (tr.t_land, tr.yl, tr.yaw) = (l.t, l.yl, l.yaw),
        None => (tr.t_land, tr.yl, tr.yaw) = (1e9, 0.0, 0.0),
    }
}
/// The cells of a landed tree (or piece) as blocks of the world (off the target block, over the middle's ground: add
/// the target block's x and z, and `gy`), each its block: lying along `d`, its local x across it
/// (a = (-d.z, d.x)), its trunk along d, its local z up; its foot (its trunk's bottom middle) at the landed middle less
/// `cm` along d, `yl` + 0.5 up. A cell (i, y, j) of its 7 by 7 columns is at foot + a (i - 3) + d (y + 0.5) + up (j - 3),
/// the block that point is in. Those in the ground (under `yl`) left out, and each block once; the trunk first, then
/// the canopy (or the piece) from its lowest, at most `cap` of them. (`true`: a trunk block.)
pub(super) fn tree_cells(tr: &TreeRec, l: &Landing, cap: usize) -> Vec<([i32; 3], bool)> {
    let cm = 0.6 * f64::from(tr.trunk.max(3));
    let (d, a) = (l.d, [-l.d[1], l.d[0]]);
    let foot = [l.m[0] - d[0] * cm, l.yl + 0.5, l.m[1] - d[1] * cm];
    let at = |i: i32, y: i32, j: i32| -> [i32; 3] {
        let (u, w, h) = (f64::from(i - 3), f64::from(y) + 0.5, f64::from(j - 3));
        // (the target's middle half a block into its block)
        [(0.5 + foot[0] + a[0] * u + d[0] * w).floor() as i32, (foot[1] + h).floor() as i32, (0.5 + foot[2] + a[1] * u + d[1] * w).floor() as i32]
    };
    let floor = l.yl.floor() as i32;
    let mut out: Vec<([i32; 3], bool)> = Vec::new();
    let put = |p: [i32; 3], trunk: bool, out: &mut Vec<([i32; 3], bool)>| {
        if p[1] >= floor && out.len() < cap && !out.iter().any(|e| e.0 == p) {
            out.push((p, trunk));
        }
    };
    for y in 0..i32::from(tr.trunk) {
        put(at(3, y, 3), true, &mut out);
    }
    // (the canopy's cells as the pass's hu_tree_cell has them: column (i, j)'s from its lowest - 1 to its highest - 1)
    for j in 3..7 {
        for i in 0..7 {
            let (lo, hi) = tr.spans[(j * 7 + i) as usize];
            if lo > hi {
                continue;
            }
            for y in i32::from(lo) - 1..i32::from(hi) {
                if y < 0 || (i == 3 && j == 3 && y < i32::from(tr.trunk)) {
                    continue;
                }
                put(at(i, y, j), false, &mut out);
            }
        }
    }
    crate::meter::spend(200 + 80 * out.len() as u64);
    out
}
/// Where tree `i` is as it is flung out, and how fast it goes (blocks a second).
fn tree_fling(tr: &TreeRec, i: u32, seed: u32) -> ([f64; 3], [f64; 3]) {
    let pf = tree_lifted(tr, i, seed, HU_FLING);
    let rf = pf[0].hypot(pf[2]).max(1.0);
    let (ox, oz) = (pf[0] / rf, pf[2] / rf);
    // (flung: on along the wind (its tangent the way the storm turns), out and up, then falling)
    let (tx, tz) = (-oz * HU_SPIN, ox * HU_SPIN);
    let vt = omega(rf) * rf * spin(HU_FLING) * 0.6;
    let vo = 6.0 + 6.0 * mh(i, seed, 0xa3);
    let vu = 3.0 + 4.0 * mh(i, seed, 0xa4);
    (pf, [tx * vt + ox * vo, vu, tz * vt + oz * vo])
}
pub(super) fn tree_at(tr: &TreeRec, i: u32, seed: u32, t: f64, ground: &dyn Fn(f64, f64) -> f64) -> TreeAt {
    if t < tr.t_up {
        return TreeAt { p: [tr.x, tr.gdy, tr.z], up: false };
    }
    if t <= HU_FLING || tr.t_up >= HU_FLING {
        return TreeAt { p: tree_lifted(tr, i, seed, t), up: true };
    }
    let (pf, v) = tree_fling(tr, i, seed);
    let s = t - HU_FLING;
    let p = [pf[0] + v[0] * s, pf[1] + v[1] * s - 7.0 * s * s, pf[2] + v[2] * s];
    let down = tree_landing(tr, i, seed, ground).map_or(f64::INFINITY, |l| l.t);
    TreeAt { p, up: t < down }
}

// ---- the land, read from the world -----------------------------------------------------------------------------------
/// How far out the land is read (and the chunks forceloaded), and how much of each column round its top.
const HU_READ: i32 = 180;
const HU_GW: i32 = 2 * HU_READ + 1;
const HU_BELOW: u32 = 36;
const HU_ABOVE: u32 = 1;
/// The reads: rings from the middle out, as many columns in each.
const HU_PARTS: i32 = 24;
/// How long the land's work waits for columns the world has not loaded before it leaves them out.
const HU_LAND_BY: f64 = 40.0;

#[derive(Clone, Copy, Debug)]
struct Col {
    known: bool,
    /// Water (or lava) over its ground: its bed left alone, and what grows in the water.
    fluid: bool,
    /// Its ground block's height (the first block down from its top that the wind can't tear up: the land, or a
    /// block that stays, `stays`), and its highest block.
    g: i32,
    top: i32,
    /// Its ground block, the one under it (HU_BLOCKS; NONE for a block the table doesn't know), and whether its ground
    /// is the land's own (dug where the ground is torn up), not a block that stays.
    ground: u16,
    under: u16,
    natural: bool,
    /// The logs standing straight up off its ground and their block; its leaves' block and the lowest and highest leaf
    /// over its ground (0 none).
    trunk: u8,
    wood: u16,
    leaf: u16,
    leaf_lo: u8,
    leaf_hi: u8,
    /// What stands on it that the wind takes, as runs of one block up the column (`Land::segs`, from `seg`, `segs` of
    /// them).
    seg: u32,
    segs: u8,
    /// Its biome's grass and foliage tints (0xRRGGBB).
    grass: u32,
    foliage: u32,
    /// Its edits have been worked out.
    done: bool,
}
impl Default for Col {
    fn default() -> Self {
        Col { known: false, fluid: false, g: 0, top: 0, ground: NONE, under: NONE, natural: false, trunk: 0, wood: NONE, leaf: NONE, leaf_lo: 0, leaf_hi: 0, seg: 0, segs: 0, grass: 0, foliage: 0, done: false }
    }
}
const NONE: u16 = u16::MAX;
/// A run of one block up a column: its lowest and highest, the block, and its class (`HuBlock::class`).
#[derive(Clone, Copy, Debug)]
struct Seg {
    y0: i32,
    y1: i32,
    b: u16,
    class: u8,
}

struct Land {
    cols: Vec<Col>,
    /// What stands on the columns that the wind takes (`Col::seg`).
    segs: Vec<Seg>,
    /// The columns of each part the world had not loaded when it answered, asked again till it has.
    missing: Vec<Vec<(i32, i32)>>,
    /// Columns that came in late, whose part's edits were already worked out.
    late: Vec<(i32, i32)>,
    /// The middle's ground over the target block's top.
    gdy0: i32,
}
impl Land {
    fn idx(bx: i32, bz: i32, x: i32, z: i32) -> Option<usize> {
        let (i, k) = (x - bx + HU_READ, z - bz + HU_READ);
        (i >= 0 && k >= 0 && i < HU_GW && k < HU_GW).then(|| (k * HU_GW + i) as usize)
    }
    fn at(&self, bx: i32, bz: i32, x: i32, z: i32) -> Option<&Col> {
        crate::meter::spend(30);
        Land::idx(bx, bz, x, z).and_then(|i| self.cols.get(i)).filter(|c| c.known)
    }
}

fn read_reach(part: i32) -> f64 {
    f64::from(HU_READ) * (f64::from(part + 1) / f64::from(HU_PARTS)).sqrt()
}
/// The columns of read part `part`: its ring's.
fn read_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let r1 = read_reach(part);
    let q0 = if part == 0 { -1.0 } else { read_reach(part - 1).powi(2) };
    let q1 = r1 * r1;
    let n = r1.ceil() as i32;
    let mut out = Vec::new();
    for dz in -n..=n {
        let d = f64::from(dz * dz);
        if d > q1 {
            continue;
        }
        let wo = (q1 - d).sqrt().floor() as i32;
        let wi = if q0 >= d { (q0 - d).sqrt().floor() as i32 } else { -1 };
        let keep = |dx: i32| {
            let e = d + f64::from(dx * dx);
            e > q0 && e <= q1
        };
        if wi < 0 {
            out.extend((-wo..=wo).filter(|&dx| keep(dx)).map(|dx| (bx + dx, bz + dz)));
        } else {
            out.extend((-wo..-wi).chain(wi + 1..=wo).filter(|&dx| keep(dx)).map(|dx| (bx + dx, bz + dz)));
        }
    }
    crate::meter::spend(60 * out.len() as u64 + 200 * (2 * n + 1) as u64);
    out
}

/// Whether the wind leaves block `name` where it is, whatever the wind: what can't be broken (bedrock, barriers, the
/// end portal's frame, command and structure blocks and the like) and what holds things (chests, barrels, shulker
/// boxes, furnaces, hoppers, shelves, pots and the like: left standing with what is in them, never emptied or lost).
fn stays(name: &str) -> bool {
    let n = name.trim_start_matches("minecraft:");
    const EXACT: [&str; 34] = [
        "bedrock", "barrier", "end_portal_frame", "end_portal", "end_gateway", "command_block", "chain_command_block",
        "repeating_command_block", "structure_block", "structure_void", "jigsaw", "light", "reinforced_deepslate",
        "spawner", "trial_spawner", "vault", "moving_piston", "nether_portal", "chest", "trapped_chest", "ender_chest",
        "barrel", "furnace", "blast_furnace", "smoker", "hopper", "dispenser", "dropper", "brewing_stand", "lectern",
        "chiseled_bookshelf", "decorated_pot", "crafter", "jukebox",
    ];
    EXACT.contains(&n)
        || n.ends_with("shulker_box")
        || n.ends_with("campfire")
        || n.ends_with("_shelf")
        || n == "beacon"
        || n == "conduit"
        || n == "respawn_anchor"
        || n == "lodestone"
        || n == "test_block"
        || n == "test_instance_block"
}

/// An answer taken in: each column's ground, what stands on it that the wind takes (by its block), its trunk, its
/// leaves and its tints (those not loaded kept to be asked again; with `late`, the ones that come in after their edits
/// were worked out kept for those too). Down each column from its top: what the wind can take (trees, plants, light
/// things, buildings: everything people build is torn at as the land's own blocks are, by how hard the wind blows and
/// how exposed it is, `hu_column`), down to the land's own ground, or to a block that stays (`stays`, and any block
/// the table doesn't know, a mod's: left as it is, and nothing under it touched).
fn take_in(land: &mut Land, a: &crate::columns::Answer, bx: i32, bz: i32, part: usize, gy: i32, late: bool) {
    // (each name's block and class: known blocks by the table, the rest by what the sinkhole makes of them)
    let kinds: Vec<(u16, u8)> = a
        .palette
        .iter()
        .map(|n| match hu_block(n) {
            Some(b) if stays(n) => (b, 8),
            Some(b) => (b, HU_BLOCKS[b as usize].class),
            None => (
                NONE,
                match sh_land::material(n).1 {
                    Class::Air => 0,
                    Class::Water => 1,
                    _ => 8,
                },
            ),
        })
        .collect();
    crate::meter::spend(2_000 + 6_000 * a.palette.len() as u64);
    for (i, &(x, z)) in a.columns.iter().enumerate() {
        let Some((surface, blocks)) = a.column(i) else {
            crate::meter::spend(60);
            land.missing[part].push((x, z));
            continue;
        };
        crate::meter::spend(260 + 16 * blocks.len() as u64);
        let base = surface - a.below;
        let mut c = Col { known: true, ..Default::default() };
        let (mut lo, mut hi) = (i32::MAX, i32::MIN);
        let mut ground = None;
        let mut top = None;
        let seg0 = land.segs.len();
        for j in (0..blocks.len()).rev() {
            let (b, class) = kinds.get(blocks[j] as usize).copied().unwrap_or((NONE, 8));
            let y = base + j as i32;
            match class {
                0 => continue,
                1 => c.fluid = true,
                2 | 8 => {
                    top.get_or_insert(y);
                    ground = Some(j);
                    c.ground = b;
                    c.natural = class == 2;
                    break;
                }
                _ => {
                    if class == 4 {
                        c.leaf = b;
                        lo = lo.min(y);
                        hi = hi.max(y);
                    }
                    // (runs of one block down the column: one edit run each)
                    let more = land.segs.len() > seg0;
                    match land.segs.last_mut() {
                        Some(s) if more && s.b == b && s.y0 == y + 1 => s.y0 = y,
                        _ => land.segs.push(Seg { y0: y, y1: y, b, class }),
                    }
                }
            }
            top.get_or_insert(y);
        }
        let Some(gj) = ground else {
            land.segs.truncate(seg0);
            continue;
        };
        c.g = base + gj as i32;
        c.top = top.unwrap_or(c.g);
        c.under = if gj >= 1 { kinds.get(blocks[gj - 1] as usize).map_or(c.ground, |k| if k.1 == 2 { k.0 } else { c.ground }) } else { c.ground };
        let mut n = 0;
        while gj + 1 + n < blocks.len() {
            match kinds.get(blocks[gj + 1 + n] as usize) {
                Some(&(b, 3)) => {
                    c.wood = b;
                    n += 1;
                }
                _ => break,
            }
        }
        c.trunk = n.min(31) as u8;
        if c.leaf != NONE {
            c.leaf_lo = (lo - c.g).clamp(1, 31) as u8;
            c.leaf_hi = (hi - c.g).clamp(1, 31) as u8;
        }
        c.seg = seg0 as u32;
        c.segs = (land.segs.len() - seg0).min(255) as u8;
        let (gt, ft) = a.tints(i);
        (c.grass, c.foliage) = (gt, ft);
        if let Some(k) = Land::idx(bx, bz, x, z) {
            let was = land.cols[k];
            c.done = was.done;
            if late && !was.known && was.done {
                land.late.push((x, z));
            }
            land.cols[k] = c;
        }
        if x == bx && z == bz {
            land.gdy0 = c.g + 1 - gy;
        }
    }
}

// ---- what the wind takes ---------------------------------------------------------------------------------------------
/// Each ring's colours: a sample of what was torn up under it (`keep`: the HU_PN with the highest keys, a block's key
/// its own hash to the power of one over its weight, so the sample is weighted as the land is), and the names of the
/// blocks sampled (what comes back down as rubble).
#[derive(Default, Clone)]
struct Pal {
    keep: Vec<(f64, u32, u16)>,
}
impl Pal {
    fn add(&mut self, key: f64, word: u32, name: u16) {
        crate::meter::spend(120);
        if self.keep.len() < HU_PN {
            self.keep.push((key, word, name));
            return;
        }
        let (lo, _) = self.keep.iter().enumerate().fold((0, f64::MAX), |b, (i, e)| if e.0 < b.1 { (i, e.0) } else { b });
        if key > self.keep[lo].0 {
            self.keep[lo] = (key, word, name);
        }
    }
}
fn ring_of(r: f64) -> Option<usize> {
    let k = ((r - HU_RING0) / HU_RING_W).floor();
    (k >= 0.0 && (k as usize) < HU_NR).then_some(k as usize)
}
/// How deep the ground is torn up at r (0 outside the band; deepest under the eyewall), in whole blocks.
fn dig_at(r: f64, x: i32, z: i32, seed: u32) -> i32 {
    if !(HU_DIG0..HU_DIG1).contains(&r) {
        return 0;
    }
    let bell = (-((r - 70.0) / 26.0).powi(2)).exp();
    let n = vnoise(f64::from(x), f64::from(z), 6.0, seed ^ 0x6d);
    let e = smooth(HU_DIG0, HU_DIG0 + 6.0, r) * (1.0 - smooth(HU_DIG1 - 10.0, HU_DIG1, r));
    ((0.5 + 2.8 * bell * (0.6 + 0.8 * n)) * e).floor() as i32
}
fn chance(x: i32, z: i32, seed: u32, k: u32) -> f64 {
    mh((x as u32).wrapping_mul(73_856_093) ^ (z as u32).wrapping_mul(19_349_663), seed, k)
}
/// When a column's chunk is torn at: as the front reaches the chunk's middle (every edit to a chunk on one tick, so the
/// game redraws its sections once). None in the eye.
fn chunk_t(bx: i32, bz: i32, x: i32, z: i32) -> Option<f64> {
    let (mx, mz) = (f64::from((x >> 4) * 16) + 8.0, f64::from((z >> 4) * 16) + 8.0);
    let r = (mx - f64::from(bx) - 0.5).hypot(mz - f64::from(bz) - 0.5);
    let rc = (f64::from(x - bx)).hypot(f64::from(z - bz));
    // (a column the wind tears at in a chunk whose middle it doesn't: the chunk's time from the nearest the front's)
    front_t(r.clamp(HU_R_IN, HU_R_PLANTS)).filter(|_| front_t(rc).is_some())
}

/// The land's work, a stage at a time: the reads, their answers, then the edits, the trees and the colours a part of
/// a ring at a time from the middle out.
struct Work {
    land: Land,
    tags: Vec<u32>,
    asked: usize,
    taken: usize,
    retry: Option<(u32, usize, f64)>,
    rnext: usize,
    rat: f64,
    sectors: std::collections::VecDeque<(f64, f64, f64, f64)>,
    trees: Vec<TreeRec>,
    /// How many trees the pass has been told of, and how many of the ring colours have changed since.
    told: usize,
    pal: Vec<Pal>,
    pal_dirty: bool,
    /// The block types the pass is told of (`Kinds`).
    kinds: Kinds,
    /// The land's height round the middle, summed with how many, for the pass.
    grid: Vec<(f64, u32)>,
    grid_dirty: bool,
    /// The middle's ground last told the pass.
    gdy_told: Option<i32>,
    /// The last crack heard, and its take.
    crack_last: f64,
    crack_take: u32,
    /// The trees torn up near enough to the player to be heard (when, and where).
    cracks: Vec<(f64, [f64; 3])>,
    /// The columns the flung rubble has come down on (one a column), and how many blocks have landed (for the tests and
    /// the log).
    rubble_at: crate::ground::FxMap<(i32, i32), ()>,
    landed: [usize; 2],
    /// The blocks the edits have taken out of the world, by class (for the tests and the log).
    gone: [u64; 8],
    /// How many trees are uprooted whole (at most HU_WHOLE: the special few).
    whole: u32,
    /// How many of the rigid groups are pieces of buildings (the rest are trees).
    pieces: usize,
    gy: i32,
    terrain: bool,
    seed: u32,
    me: [f64; 3],
    done: bool,
}

/// The rings of the land the edits go over (6 wide), split by angle into parts of about 450 columns, from the middle out.
fn hu_sectors() -> std::collections::VecDeque<(f64, f64, f64, f64)> {
    let mut out = std::collections::VecDeque::new();
    let mut r = HU_R_IN - 1.0;
    let mut k = 0;
    while r < HU_R_PLANTS {
        let e = (r + 6.0).min(HU_R_PLANTS + 1.0);
        let n = (PI * (e * e - r * r) / 450.0).ceil().max(1.0);
        let turn = TAU * (f64::from(k) * 0.618_034).fract();
        for j in 0..n as usize {
            out.push_back((r, e, turn + TAU * j as f64 / n, TAU / n));
        }
        r = e;
        k += 1;
    }
    out
}
fn sector_cells(bx: i32, bz: i32, (r0, r1, a0, da): (f64, f64, f64, f64)) -> Vec<(i32, i32)> {
    let n = r1.ceil() as i32 + 1;
    let mut out = Vec::new();
    let (q0, q1) = (r0 * r0, r1 * r1);
    for dz in -n..=n {
        let z2 = f64::from(dz) * f64::from(dz);
        if z2 > q1 {
            continue;
        }
        let xo = (q1 - z2).sqrt().ceil() as i32;
        let xi = if q0 > z2 { ((q0 - z2).sqrt().floor() as i32 - 1).max(0) } else { -1 };
        let mut span = |a: i32, b: i32| {
            for dx in a..=b {
                let q = f64::from(dx * dx) + z2;
                if q < q0 || q >= q1 {
                    continue;
                }
                if da < TAU - 1e-9 && (f64::from(dz).atan2(f64::from(dx)) - a0).rem_euclid(TAU) >= da {
                    continue;
                }
                out.push((bx + dx, bz + dz));
            }
        };
        if xi < 0 {
            span(-xo, xo);
        } else {
            span(-xo, -xi);
            span(xi, xo);
        }
    }
    crate::meter::spend(40 * out.len() as u64 + 400 * (2 * n + 1) as u64);
    out
}

impl Work {
    /// How far out every column has been read and taken in (short of the first part with columns still missing).
    fn ready(&self) -> f64 {
        if self.taken == self.tags.len() && self.unloaded() == 0 && self.retry.is_none() {
            return f64::INFINITY;
        }
        let r = if self.taken == 0 { 0.0 } else { read_reach(self.taken as i32 - 1) };
        let mut first = self.land.missing.iter().position(|m| !m.is_empty()).unwrap_or(usize::MAX);
        if let Some((_, part, _)) = &self.retry {
            first = first.min(*part);
        }
        if first == usize::MAX {
            return r;
        }
        r.min(if first == 0 { 0.0 } else { read_reach(first as i32 - 1) - 1.0 })
    }
    fn unloaded(&self) -> usize {
        self.land.missing.iter().map(Vec::len).sum()
    }
}

/// How long after a column's roof its walls go (`hu_column`): a second near the eyewall, four at the trees' reach, by
/// the distance of its chunk's middle (so a chunk's walls go on one tick).
fn wall_delay(bx: i32, bz: i32, x: i32, z: i32) -> f64 {
    let (mx, mz) = (f64::from((x >> 4) * 16) + 8.0, f64::from((z >> 4) * 16) + 8.0);
    let r = (mx - f64::from(bx) - 0.5).hypot(mz - f64::from(bz) - 0.5);
    1.0 + 3.0 * smooth(HU_R_W, HU_R_LIFT, r)
}
/// Whether the wind tears a building's run of blocks off a column r out, its top `h` over the land's own ground, `roof`
/// if it is the column's highest (`u` the column's own chance, so a column is stripped from its top down: what goes
/// higher up goes first). Everything people build, whatever it is, by how hard the wind blows there and how exposed it
/// is: all of it in the strong wind round the eyewall (out to some 100), further out its roofs and its high blocks
/// first, a fewer the further out, none past the trees' reach.
fn torn(r: f64, h: i32, roof: bool, u: f64) -> bool {
    if !(HU_R_IN..HU_R_LIFT).contains(&r) {
        return false;
    }
    let exposed = (0.15 + 0.07 * f64::from(h.max(0)) + if roof { 0.35 } else { 0.0 }).min(1.0);
    let p = (1.0 - smooth(128.0, HU_R_LIFT, r)) * (1.0 + (exposed - 1.0) * smooth(95.0, 125.0, r));
    u < p
}
/// A block a piece of a building can be made of: a whole block (not a door, a pane, a bed or the like, which can't fall
/// as one).
fn whole(b: u16) -> bool {
    let Some(k) = HU_BLOCKS.get(b as usize) else { return false };
    let n = k.name;
    k.class == 7 && !["door", "pane", "bars", "bed", "sign", "banner", "button", "lever", "torch", "lantern", "chain", "rail", "carpet", "pot", "ladder", "fence", "wall", "candle", "head", "skull", "plate", "rod", "glass"].iter().any(|s| n.contains(s))
}

/// The real ground's top at (xo, zo) off the target's middle, as the strike leaves it (over the middle's ground, as
/// TreeRec::gdy: the height of the first block of air over it), and whether it is water: the land's own ground less
/// what the wind digs out of it, or what it leaves standing on it (what `hu_column` takes, worked out the same way
/// from what was read); with the terrain off, what stands there. A column not read: the nearest read on the way in
/// to the middle, if any within some 60.
fn left_top(w: &Work, bx: i32, bz: i32, xo: f64, zo: f64) -> Option<(f64, bool)> {
    let r0 = xo.hypot(zo);
    for k in 0..30 {
        let f = if r0 > 1e-9 { (r0 - 2.0 * f64::from(k)).max(0.0) / r0 } else { 0.0 };
        let (x, z) = ((f64::from(bx) + 0.5 + xo * f).floor() as i32, (f64::from(bz) + 0.5 + zo * f).floor() as i32);
        if let Some(c) = w.land.at(bx, bz, x, z) {
            return Some((f64::from(col_top(w, c, bx, bz, x, z) + 1 - w.gy), c.fluid));
        }
        if f == 0.0 {
            break;
        }
    }
    None
}
/// Column (x, z)'s highest block once the strike is done with it (`left_top`).
fn col_top(w: &Work, c: &Col, bx: i32, bz: i32, x: i32, z: i32) -> i32 {
    crate::meter::spend(300 + 80 * u64::from(c.segs));
    if !w.terrain {
        return c.top;
    }
    if c.fluid {
        return c.top.max(c.g);
    }
    let r = f64::from(x - bx).hypot(f64::from(z - bz));
    let seed = w.seed;
    let g = c.g;
    let u = chance(x, z, seed, 0x70);
    let leaves_all = HU_R_LIFT + 8.0;
    let strip = chance(x, z, seed, 0x52) < 0.6 * (1.0 - (r - leaves_all) / (HU_R_PLANTS - leaves_all));
    let mut top = i32::MIN;
    let mut n7 = 0;
    let mut built_left = false;
    for i in c.seg..c.seg + u32::from(c.segs) {
        let sg = w.land.segs[i as usize];
        let take = match sg.class {
            3 | 6 => r < HU_R_LIFT,
            4 => r < leaves_all || strip,
            5 => r < HU_R_PLANTS,
            7 => {
                n7 += 1;
                let go = torn(r, sg.y1 - g, n7 == 1, u);
                built_left |= !go;
                go
            }
            _ => false,
        };
        if !take {
            top = top.max(sg.y1);
        }
    }
    let dig = if !c.natural || built_left { 0 } else { dig_at(r, x, z, seed) };
    top.max(g - dig)
}

/// One column's share of the wind's work, torn at at `t`: what it takes out of the world (`b` at once, `b2` its walls a
/// little later, `wall_delay`), whether a rigid tree or a piece of a building stands on it, what it adds to its ring's
/// blocks, the land's height under it.
///
/// What it takes is what was read standing on the column, block by block (each an edit run over just that block, so
/// whatever else is there now is left): out to HU_R_LIFT the trees (logs, wood, stems, leaves, mushroom caps) and the
/// light things people put up (fences, carpets, signs, torches, pots); out to HU_R_PLANTS the plants and what lies on
/// the land (grass, flowers, saplings, crops, cane, cactus, bamboo, vines, moss, mushrooms, snow, berries, pumpkins,
/// bee nests), the leaves all the way out to HU_R_LIFT + 8 (nothing left hanging off a tree that went) and in patches
/// past it. Buildings, whatever they are made of, go by how hard the wind blows and how exposed they are (`torn`):
/// their roofs as the front reaches them, their walls and floors a second or few later, all of them round the
/// eyewall; now and then a piece of one whole, lifted off where it stood (a rigid group, as a tree is). What stays
/// stays (`stays`: what can't be broken, and chests and the like with what is in them). Water and what grows in it are
/// left alone; the ground is torn up (its top one to three blocks) only where it is the land's own (`Col::natural`)
/// and nothing built on it is left standing.
#[allow(clippy::too_many_arguments)]
fn hu_column(w: &mut Work, b: &mut Blocks, b2: &mut Blocks, bx: i32, bz: i32, x: i32, z: i32, t: f64) {
    let Some(c) = w.land.at(bx, bz, x, z).copied() else { return };
    crate::meter::spend(900 + 120 * u64::from(c.segs));
    let (dx, dz) = (f64::from(x - bx), f64::from(z - bz));
    let r = dx.hypot(dz);
    let seed = w.seed;
    // (the land's height round the middle)
    let gi = (r / HU_G_STEP) as usize;
    if gi < HU_GR {
        let ai = ((dz.atan2(dx) / TAU).rem_euclid(1.0) * HU_GA as f64) as usize % HU_GA;
        let top = if c.fluid { c.top } else { c.g };
        let e = &mut w.grid[gi * HU_GA + ai];
        e.0 += f64::from(top + 1 - w.gy);
        e.1 += 1;
        w.grid_dirty = true;
    }
    let g = c.g;
    // (what of its buildings the wind takes: from its highest run of them down, `torn`; the rest left standing)
    let u = chance(x, z, seed, 0x70);
    let mut built = 0u32;
    let mut built_left = false;
    let mut built_top = 0;
    for i in c.seg..c.seg + u32::from(c.segs) {
        let sg = w.land.segs[i as usize];
        if sg.class == 7 {
            let go = torn(r, sg.y1 - g, built == 0, u);
            built += 1;
            built_left |= !go;
            if go {
                built_top = built_top.max(sg.y1 - g);
            }
        }
    }
    let ring = ring_of(r);
    let dig = if c.fluid || !c.natural || built_left { 0 } else { dig_at(r, x, z, seed) };
    // (what it adds to its ring's blocks: the ground torn up, the trunk, the leaves, what was built)
    if let Some(k) = ring {
        let key = |w8: f64, j: u32| chance(x, z, seed, 0x100 + j).max(1e-9).powf(1.0 / w8.max(1e-3));
        let add = |w: &mut Work, wt: f64, j: u32, blk: u16| {
            if blk != NONE {
                let kind = w.kinds.of(blk, c.grass, c.foliage);
                w.pal[k].add(key(wt, j), u32::from(kind), blk);
                w.pal_dirty = true;
            }
        };
        if dig > 0 {
            add(w, 1.0 + f64::from(dig), 0, c.ground);
            if dig > 1 {
                add(w, 0.6 * f64::from(dig), 1, c.under);
            }
        }
        if r < HU_R_LIFT && c.trunk > 0 {
            add(w, f64::from(c.trunk) * 0.4, 2, c.wood);
        }
        if c.leaf != NONE && r < HU_R_LIFT + 10.0 {
            add(w, f64::from(c.leaf_hi.saturating_sub(c.leaf_lo) + 1) * 0.5, 3, c.leaf);
        }
        if built > 0 {
            let mut n = 0u32;
            for i in c.seg..c.seg + u32::from(c.segs) {
                let sg = w.land.segs[i as usize];
                if sg.class == 7 && torn(r, sg.y1 - g, n == 0, u) {
                    add(w, 0.9 * f64::from(sg.y1 - sg.y0 + 1), 4 + n.min(8), sg.b);
                }
                n += u32::from(sg.class == 7);
            }
        }
    }
    if !w.terrain {
        return;
    }
    // a tree's fate (its trunk three or more high, now and then, none within 6 of another, while there is room): most
    // are shredded where they stand (no record: their logs and leaves go up as the field's blocks); of the rest, a few
    // uprooted whole (the bigger, nearer the eyewall, the likelier), some snapped at the trunk (the crown and the upper
    // trunk carried off whole, a jagged stump of 1-4 logs left standing as real blocks), some lifted whole to break
    // apart in the air
    let fate = if r < HU_R_LIFT && c.trunk >= 3 && c.wood != NONE && w.trees.len() < HU_NT && chance(x, z, seed, 0x51) < if r < 105.0 { 0.16 } else { 0.1 } && !w.trees.iter().any(|t| (t.x - dx).abs() < 6.0 && (t.z - dz).abs() < 6.0) {
        let size = (f64::from(c.trunk) + f64::from(c.leaf_hi)) / 16.0;
        let f = chance(x, z, seed, 0x59);
        let whole = (0.12 + 0.3 * wind_shape(r) * size.min(1.2)) * if w.whole < HU_WHOLE { 1.0 } else { 0.0 };
        Some(if f < whole { 0 } else if f < whole + 0.45 { 1 } else { 2 })
    } else {
        None
    };
    let stump = if fate == Some(1) { (1 + (chance(x, z, seed, 0x5a) * 4.0) as i32).min(i32::from(c.trunk) - 2) } else { 0 };
    // what stands on it, block by block, as far out as the wind takes each kind
    let leaves_all = HU_R_LIFT + 8.0;
    let strip = chance(x, z, seed, 0x52) < 0.6 * (1.0 - (r - leaves_all) / (HU_R_PLANTS - leaves_all));
    let mut n7 = 0u32;
    for i in c.seg..c.seg + u32::from(c.segs) {
        let sg = w.land.segs[i as usize];
        let (take, late) = match sg.class {
            3 | 6 => (r < HU_R_LIFT, false),
            4 => (r < leaves_all || strip, false),
            5 => (r < HU_R_PLANTS, false),
            // (a building's: its roof as the front reaches it, the rest a little later)
            7 => {
                n7 += 1;
                (torn(r, sg.y1 - g, n7 == 1, u), n7 > 1)
            }
            _ => (false, false),
        };
        // (a snapped tree's stump left standing)
        let y0 = if sg.class == 3 && stump > 0 { sg.y0.max(g + 1 + stump) } else { sg.y0 };
        if take && y0 <= sg.y1 {
            (if late { &mut *b2 } else { &mut *b }).put(x, z, y0, sg.y1, "minecraft:air", Some(HU_BLOCKS[sg.b as usize].name), false);
            w.gone[sg.class as usize] += (sg.y1 - y0 + 1) as u64;
        }
    }
    if r < HU_R_LIFT {
        // a rigid tree (whole, its snapped crown, or one to break apart in the air)
        if let Some(fate) = fate {
            let mut spans = [(31u8, 0u8); 49];
            let mut leaf = c.leaf;
            for j in 0..7 {
                for i in 0..7 {
                    if let Some(n) = w.land.at(bx, bz, x + i - 3, z + j - 3)
                        && n.leaf != NONE
                    {
                        // (its leaves over this tree's ground)
                        let lo = (i32::from(n.leaf_lo) + n.g - g).clamp(0, 31) as u8;
                        let hi = (i32::from(n.leaf_hi) + n.g - g).clamp(0, 31) as u8;
                        spans[(j * 7 + i) as usize] = (lo, hi);
                        if leaf == NONE {
                            leaf = n.leaf;
                        }
                    }
                }
            }
            let leaf = if leaf == NONE { hu_block("minecraft:oak_leaves").unwrap_or(0) } else { leaf };
            let (wood_bk, leaf_bk) = (w.kinds.of(c.wood, c.grass, c.foliage), w.kinds.of(leaf, c.grass, c.foliage));
            let mut tr = TreeRec { x: dx, z: dz, gdy: f64::from(g + 1 - w.gy), t_up: t, trunk: c.trunk, wood_bk, leaf_bk, wood: c.wood, leaf, spans, t_land: 1e9, yl: 0.0, yaw: 0.0, t_break: 1e9 };
            match fate {
                0 => w.whole += 1,
                // (snapped: what is over the stump, its foot the stump's top)
                1 => {
                    let st = stump as u8;
                    tr.trunk -= st;
                    tr.gdy += f64::from(stump);
                    for sp in &mut tr.spans {
                        *sp = if sp.0 > sp.1 || sp.1 < st { (31, 0) } else { (sp.0.saturating_sub(st), sp.1 - st) };
                    }
                }
                // (to break apart in the air some seconds after it is lifted, before the fling)
                _ => tr.t_break = (t + 2.5 + 4.5 * chance(x, z, seed, 0x5b)).min(HU_FLING - 1.0).max(t + 1.5),
            }
            land_it(w, &mut tr, bx, bz);
            w.trees.push(tr);
            let d = (f64::from(x) + 0.5 - w.me[0]).hypot(f64::from(z) + 0.5 - w.me[2]);
            if d < 230.0 {
                w.cracks.push((t, [f64::from(x) + 0.5, f64::from(g) + 3.0, f64::from(z) + 0.5]));
            }
        } else if built > 0 && built_top >= 3 && !built_left && r < 110.0 && w.trees.len() < HU_NT && w.pieces < HU_PIECES && chance(x, z, seed, 0x58) < 0.22 && !w.trees.iter().any(|t| (t.x - dx).abs() < 7.0 && (t.z - dz).abs() < 7.0) {
            house_piece(w, bx, bz, x, z, c, t + wall_delay(bx, bz, x, z));
        }
    }
    if dig > 0 {
        // the ground torn up, the dirt under it laid bare, scoured to coarse dirt and gravel here and there (under what
        // was built, with its walls)
        let b = if built > 0 { &mut *b2 } else { &mut *b };
        b.run(x, z, g - dig + 1, g, "minecraft:air");
        w.gone[2] += dig as u64;
        let n = chance(x, z, seed, 0x53);
        if n < 0.3 {
            b.run_only(x, z, g - dig, g - dig, "minecraft:coarse_dirt", "minecraft:dirt");
        } else if n < 0.38 {
            b.run_only(x, z, g - dig, g - dig, "minecraft:gravel", "minecraft:dirt");
        }
    } else if !c.fluid && c.natural && built == 0 && r < HU_R_LIFT + 10.0 && chance(x, z, seed, 0x55) < 0.65 * (1.0 - smooth(HU_DIG1, HU_R_LIFT + 10.0, r)) {
        // past the torn band the grass scoured off in streaks
        let to = if chance(x, z, seed, 0x56) < 0.5 { "minecraft:coarse_dirt" } else { "minecraft:dirt" };
        b.run_only(x, z, g, g, to, "minecraft:grass_block");
    }
}

/// How many of the rigid groups can be pieces of buildings (the rest of HU_NT left for the trees).
const HU_PIECES: usize = 48;
/// At most this many trees uprooted whole.
const HU_WHOLE: u32 = 36;
/// A piece of a building torn off whole where column (x, z) stands (`c`), lifted at `t_up` with its walls: what was
/// built on the 7 by 7 columns round it, below their roofs (each column's runs of building from its lowest to its
/// highest under the roof, over this column's ground), all of its commonest whole block, drawn by the pass as a rigid
/// group as a tree is (a TreeRec with no trunk). Its blocks go out of the world with their columns' walls.
fn house_piece(w: &mut Work, bx: i32, bz: i32, x: i32, z: i32, c: Col, t_up: f64) {
    let g = c.g;
    let mut spans = [(31u8, 0u8); 49];
    let mut count: Vec<(u16, u32)> = Vec::new();
    let mut any = 0;
    for j in 0..7 {
        for i in 0..7 {
            let Some(n) = w.land.at(bx, bz, x + i - 3, z + j - 3).copied() else { continue };
            crate::meter::spend(40 + 60 * u64::from(n.segs));
            let runs: Vec<Seg> = w.land.segs[n.seg as usize..(n.seg + u32::from(n.segs)) as usize].iter().filter(|s| s.class == 7).copied().collect();
            // (under its roof, if it has more than the one run)
            let walls = if runs.len() > 1 { &runs[1..] } else { &runs[..] };
            if walls.is_empty() {
                continue;
            }
            // (over this column's ground: the first block over it 1, as a tree's leaves are counted)
            let lo = walls.iter().map(|s| s.y0).min().unwrap_or(0) - g;
            let hi = walls.iter().map(|s| s.y1).max().unwrap_or(0) - g;
            if hi < 1 {
                continue;
            }
            spans[(j * 7 + i) as usize] = (lo.clamp(1, 31) as u8, hi.clamp(1, 31) as u8);
            any += 1;
            for s in walls {
                if whole(s.b) {
                    let len = (s.y1 - s.y0 + 1) as u32;
                    match count.iter_mut().find(|e| e.0 == s.b) {
                        Some(e) => e.1 += len,
                        None => count.push((s.b, len)),
                    }
                }
            }
        }
    }
    let Some(&(mat, _)) = count.iter().max_by_key(|e| e.1) else { return };
    if any < 6 {
        return;
    }
    let bk = w.kinds.of(mat, c.grass, c.foliage);
    let (dx, dz) = (f64::from(x - bx), f64::from(z - bz));
    let mut tr = TreeRec { x: dx, z: dz, gdy: f64::from(g + 1 - w.gy), t_up, trunk: 0, wood_bk: bk, leaf_bk: bk, wood: mat, leaf: mat, spans, t_land: 1e9, yl: 0.0, yaw: 0.0, t_break: 1e9 };
    land_it(w, &mut tr, bx, bz);
    w.trees.push(tr);
    w.pieces += 1;
}
/// A new tree's (or piece's) landing, from the land as read so far (`left_top`; where it isn't, its own ground's
/// height): worked out again as the strike flings them, the pass told again if it has changed (`hu_landings`).
fn land_it(w: &Work, tr: &mut TreeRec, bx: i32, bz: i32) {
    let i = w.trees.len() as u32;
    let g0 = tr.gdy;
    set_landing(tr, i, w.seed, &|x, z| left_top(w, bx, bz, x, z).map_or(g0, |v| v.0));
}

impl Blocks {
    fn run_only(&mut self, x: i32, z: i32, y0: i32, y1: i32, block: &'static str, only: &'static str) {
        self.put(x, z, y0, y1, block, Some(only), false);
    }
}

/// The pass's words for the trees from `from` on (and how many there are), the rings' colours and the land's height.
fn table_words(q: &mut Plan, w: &mut Work, now: f32) {
    // (the middle's ground, as read: the designator may have hit a treetop)
    if w.gdy_told != Some(w.land.gdy0) {
        q.ev.push((now, Act::Data { index: 1, value: w.land.gdy0 as f32 }));
        w.gdy_told = Some(w.land.gdy0);
    }
    if w.trees.len() > w.told {
        let words: Vec<u32> = w.trees[w.told..].iter().flat_map(|t| t.words()).collect();
        crate::meter::spend(200 * words.len() as u64);
        q.ev.push((now, Act::Words { index: (HU_T + HU_TW * w.told) as u32, words }));
        q.ev.push((now, Act::Data { index: 0, value: w.trees.len() as f32 }));
        w.told = w.trees.len();
    }
    if w.pal_dirty {
        let mut words = vec![0u32; HU_NR * HU_PN];
        for (k, p) in w.pal.iter().enumerate() {
            for j in 0..HU_PN {
                // (a ring with few blocks of its own sampled borrows its inner neighbour's)
                let e = p.keep.get(j % p.keep.len().max(1)).map(|e| e.1);
                let e = e.or_else(|| (0..k).rev().find_map(|kk| w.pal[kk].keep.get(j % w.pal[kk].keep.len().max(1)).map(|e| e.1)));
                words[k * HU_PN + j] = e.unwrap_or(0);
            }
        }
        crate::meter::spend(100 * words.len() as u64);
        q.ev.push((now, Act::Words { index: HU_PAL as u32, words }));
        w.pal_dirty = false;
    }
    if w.kinds.list.len() > w.kinds.told {
        let from = w.kinds.told;
        let words: Vec<u32> = w.kinds.list[from..].iter().flat_map(|&(b, g, f)| bk_words(b, g, f)).collect();
        q.ev.push((now, Act::Words { index: (HU_BK + HU_BKW * from) as u32, words }));
        w.kinds.told = w.kinds.list.len();
        q.ev.push((now, Act::Words { index: 3, words: vec![w.kinds.told as u32] }));
    }
    if w.grid_dirty {
        let words: Vec<u32> = w.grid.iter().map(|&(s, n)| (if n == 0 { f32::NAN } else { (s / f64::from(n)) as f32 }).to_bits()).collect();
        q.ev.push((now, Act::Words { index: HU_G as u32, words }));
        w.grid_dirty = false;
    }
}

/// What a stage of the land's work stops taking on more at (`meter`): it then waits for the next.
const HU_STAGE: u64 = 7_000_000;

/// One stage of the land's work.
fn hu_work(q: &mut Plan, w: Rc<RefCell<Work>>, now: f64) {
    let more = {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        let (bx, bz) = (q.bx, q.bz);
        // the reads: two parts a stage, from the middle out
        for _ in 0..2 {
            if wk.asked < wk.tags.len() {
                let part = wk.asked;
                q.ev.push((now as f32, Act::Read { tag: wk.tags[part], columns: read_columns(bx, bz, part as i32), below: HU_BELOW, above: HU_ABOVE }));
                wk.asked += 1;
            }
        }
        // their answers, as they come
        for _ in 0..2 {
            if wk.taken < wk.asked
                && !crate::meter::full()
                && let Some(a) = crate::columns::take(wk.tags[wk.taken])
            {
                take_in(&mut wk.land, &a, bx, bz, wk.taken, wk.gy, false);
                wk.taken += 1;
            }
        }
        // (the columns not loaded yet, as at a target far off whose chunks were only forceloaded as it fired: asked
        // again a part at a time until they are, or until HU_LAND_BY; their edits go in late as they come)
        if wk.taken == wk.tags.len() {
            if let Some((tag, part, since)) = wk.retry {
                if let Some(a) = crate::columns::take(tag) {
                    take_in(&mut wk.land, &a, bx, bz, part, wk.gy, true);
                    wk.retry = None;
                } else if now > since + 3.0 {
                    wk.retry = None;
                }
            }
            let left = wk.unloaded();
            if left > 0 && now > HU_LAND_BY {
                crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("hurricane: {left} columns of the land never loaded; left alone there"));
                for m in &mut wk.land.missing {
                    m.clear();
                }
            } else if left > 0 && wk.retry.is_none() && now >= wk.rat {
                let n = wk.land.missing.len();
                if let Some(part) = (0..n).map(|j| (wk.rnext + j) % n).find(|&j| !wk.land.missing[j].is_empty()) {
                    let cols = std::mem::take(&mut wk.land.missing[part]);
                    crate::meter::spend(40 * cols.len() as u64);
                    let tag = crate::columns::new_tag();
                    q.ev.push((now as f32, Act::Read { tag, columns: cols, below: HU_BELOW, above: HU_ABOVE }));
                    wk.retry = Some((tag, part, now));
                    wk.rnext = part + 1;
                    wk.rat = now + 0.25;
                }
            }
        }
        // the land's parts, in order from the middle out, as far as it is read (or, once its front is near, with
        // what is known of it); the columns that came in late after them
        // (some 900 columns a stage, and none once the stage has done well over a third of a tick's work)
        let mut budget = 900.0;
        let ready = wk.ready();
        while budget > 0.0 && crate::meter::spent() < HU_STAGE {
            let Some(&sec) = wk.sectors.front() else { break };
            let due = front_t(sec.0.max(HU_R_IN)).unwrap_or(HU_F0) - 1.5;
            if ready < sec.1 + 4.0 && !(wk.taken == wk.tags.len() && now >= due) {
                break;
            }
            wk.sectors.pop_front();
            let cells = sector_cells(bx, bz, sec);
            budget -= cells.len() as f64;
            let mut b = Blocks::default();
            // (the buildings' walls, a little after their roofs)
            let mut b2 = Blocks::default();
            let mut when: Vec<(i32, i32, f64)> = Vec::with_capacity(cells.len());
            for (x, z) in cells {
                let Some(t) = chunk_t(bx, bz, x, z) else { continue };
                let t = t.max(now + 0.1);
                let (before, before2) = (b.runs.len(), b2.runs.len());
                hu_column(wk, &mut b, &mut b2, bx, bz, x, z, t);
                if let Some(k) = Land::idx(bx, bz, x, z) {
                    wk.land.cols[k].done = true;
                }
                if b.runs.len() > before || b2.runs.len() > before2 {
                    when.push((x, z, t));
                }
            }
            let at: crate::ground::FxMap<(i32, i32), f64> = when.into_iter().map(|(x, z, t)| ((x, z), t)).collect();
            for (t, e) in b.split_by(|x, z| at.get(&(x, z)).copied().unwrap_or(now + 0.1) as f32) {
                q.ev.push((t, Act::Blocks(Box::new(e))));
            }
            if !b2.runs.is_empty() {
                for (t, e) in b2.split_by(|x, z| (at.get(&(x, z)).copied().unwrap_or(now + 0.1) + wall_delay(bx, bz, x, z)) as f32) {
                    q.ev.push((t, Act::Blocks(Box::new(e))));
                }
            }
        }
        if !wk.land.late.is_empty() && crate::meter::spent() < HU_STAGE {
            let n = wk.land.late.len().min(1500);
            let cols: Vec<(i32, i32)> = wk.land.late.drain(..n).collect();
            let mut b = Blocks::default();
            let mut b2 = Blocks::default();
            for (x, z) in cols {
                hu_column(wk, &mut b, &mut b2, bx, bz, x, z, now + 0.1);
            }
            if !b.runs.is_empty() {
                q.ev.push(((now + 0.1) as f32, Act::Blocks(Box::new(b))));
            }
            if !b2.runs.is_empty() {
                q.ev.push(((now + 1.1) as f32, Act::Blocks(Box::new(b2))));
            }
        }
        table_words(q, wk, now as f32);
        // (the trees' cracks heard where they are torn up near the player, no two within 0.7 s, never the same take
        // twice running: the game fades each with its distance)
        if !wk.cracks.is_empty() {
            let mut ts = std::mem::take(&mut wk.cracks);
            ts.sort_by(|a, b| a.0.total_cmp(&b.0));
            for (t, at) in ts {
                if t - wk.crack_last > 0.7 {
                    let mut k = (mh((t * 100.0) as u32, wk.seed, 0x5a) * 4.0) as u32 % 4 + 1;
                    if k == wk.crack_take {
                        k = k % 4 + 1;
                    }
                    wk.crack_take = k;
                    q.ev.push((t as f32, Act::Sound { event: format!("orbital:hurricane.crack{k}"), at: Some(at), volume: 0.8, pitch: 0.9 + 0.2 * mh((t * 10.0) as u32, wk.seed, 0x5b) as f32 }));
                    wk.crack_last = t;
                }
            }
        }
        if wk.sectors.is_empty() && wk.taken == wk.tags.len() && wk.unloaded() == 0 && wk.retry.is_none() && wk.land.late.is_empty() && !wk.done {
            wk.done = true;
        }
        !wk.done && now < HU_LAND_BY + 8.0
    };
    if more {
        q.later((now + 0.05) as f32, move |q| hu_work(q, w, now + 0.05));
    } else {
        // where everything it flings comes down: the trees and the pieces of buildings, and the rubble
        q.later((now + 0.05) as f32, move |q| hu_landings(q, w, 0, 0, now + 0.05));
    }
}

/// A block's name with its state, kept for the strike's edits (each name made once).
fn interned(name: String) -> &'static str {
    thread_local! {
        static NAMES: RefCell<std::collections::HashMap<String, &'static str>> = RefCell::new(Default::default());
    }
    NAMES.with(|m| *m.borrow_mut().entry(name.clone()).or_insert_with(|| Box::leak(name.into_boxed_str())))
}
/// A trunk's block lying along x or z (a log's, wood's, stem's or hyphae's axis; as it is otherwise).
fn lying(b: u16, along_x: bool) -> &'static str {
    let n = HU_BLOCKS[b as usize].name;
    let axis = n.ends_with("_log") || n.ends_with("_wood") || (n.ends_with("_stem") && !n.contains("mushroom")) || n.ends_with("_hyphae") || n.ends_with("bamboo_block");
    if axis { interned(format!("{n}[axis={}]", if along_x { "x" } else { "z" })) } else { n }
}
/// A block as it is laid down: leaves that don't decay.
fn laid(b: u16) -> &'static str {
    let n = HU_BLOCKS[b as usize].name;
    if n.ends_with("_leaves") { interned(format!("{n}[persistent=true]")) } else { n }
}
/// Whether a block torn up can come back down as rubble: the land's own ground, wood, leaves, a building's whole
/// blocks (no panes, doors, glass and the like: `whole`).
fn rubble_ok(b: u16) -> bool {
    HU_BLOCKS.get(b as usize).is_some_and(|k| matches!(k.class, 2..=4) || whole(b))
}
/// How far out the pass's flung blocks have come down from their ring's middle, those that were `y0` up as they were
/// flung, `s` seconds after: out along the eyewall's slope as they climbed (the pass's hu_flare at the storm's height),
/// then 9 a second (the pass's hu_flung).
fn flung_out(y0: f64, s: f64) -> f64 {
    (0.08 * y0 + 0.00045 * y0 * y0) * 1.2 + 9.0 * s
}
/// How long a flung block `y0` up takes to come down to its ground (y0 + 4 s - 7 s^2 = 0, as the pass's hu_flung).
fn flung_down(y0: f64) -> f64 {
    (4.0 + (16.0 + 28.0 * y0.max(0.0)).sqrt()) / 14.0
}
/// How many of the flung blocks come down as real rubble.
pub(super) const HU_RUBBLE: usize = 2400;
/// At most so many of a tree's (or a piece's) blocks are laid where it lands.
const HU_TREE_CAP: usize = 160;

/// Where everything the storm flings comes down, a stage at a time (from tree `i`, then rubble `k`): each tree and
/// piece of a building lands as real blocks lying where the pass lays it (`tree_landing`, `tree_cells`; the pass told
/// again where its landing has changed since it was torn up), and HU_RUBBLE blocks from the rings' samples (`Pal`)
/// come down one a column where the pass's flung blocks come down (`flung_out`), on the real ground as the strike
/// leaves it, never into water. Each only into air, and never where the player stands (`Blocks::clear_of_player`).
fn hu_landings(q: &mut Plan, w: Rc<RefCell<Work>>, mut i: usize, mut k: usize, now: f64) {
    let more = {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        let (bx, bz) = (q.bx, q.bz);
        let gy = wk.gy;
        let seed = wk.seed;
        let at = |t: f64| t.max(now + 0.05) as f32;
        // (what it gives counts as the stage's work too, a thousand a run: `Strike::work_out`)
        let mut made = 0u64;
        while i < wk.trees.len() && crate::meter::spent() + made < HU_STAGE {
            let mut tr = wk.trees[i].clone();
            let g0 = tr.gdy;
            let l = {
                let wr: &Work = wk;
                tree_landing(&tr, i as u32, seed, &|x, z| left_top(wr, bx, bz, x, z).map_or(g0, |v| v.0))
            };
            if let Some(l) = l {
                if (l.t - tr.t_land).abs() > 1e-6 || (l.yl - tr.yl).abs() > 1e-6 || (l.yaw - tr.yaw).abs() > 1e-6 {
                    (tr.t_land, tr.yl, tr.yaw) = (l.t, l.yl, l.yaw);
                    let words = tr.words();
                    q.ev.push((now as f32, Act::Words { index: (HU_T + HU_TW * i + 25) as u32, words: words[25..28].to_vec() }));
                    wk.trees[i] = tr.clone();
                }
                if wk.terrain && HU_BLOCKS.get(tr.wood as usize).is_some() && HU_BLOCKS.get(tr.leaf as usize).is_some() {
                    let along_x = l.d[0].abs() >= l.d[1].abs();
                    let (log, leaf) = (lying(tr.wood, along_x), laid(tr.leaf));
                    let mut b = Blocks { clear_of_player: true, ..Default::default() };
                    for (p, trunk) in tree_cells(&tr, &l, HU_TREE_CAP) {
                        b.put(bx + p[0], bz + p[2], gy + p[1], gy + p[1], if trunk { log } else { leaf }, Some("minecraft:air"), false);
                    }
                    wk.landed[0] += b.runs.len();
                    made += 1_000 * b.runs.len() as u64;
                    if !b.runs.is_empty() {
                        q.ev.push((at(l.t), Act::Blocks(Box::new(b))));
                    }
                }
            }
            i += 1;
        }
        if i >= wk.trees.len() && wk.terrain && k < HU_RUBBLE {
            // (each ring's share by how many blocks fly round in it)
            let wt: Vec<f64> = (0..HU_NR)
                .map(|n| {
                    let r = ring_r(n);
                    if wk.pal[n].keep.is_empty() { 0.0 } else { (TAU * r / HU_CELL).floor() * ring_h(r) / HU_CELL * ring_dens(r) }
                })
                .collect();
            let sum: f64 = wt.iter().sum();
            if sum <= 0.0 {
                // (nothing was torn up to come down)
                k = HU_RUBBLE;
            }
            let mut b = Blocks { clear_of_player: true, ..Default::default() };
            let mut when: crate::ground::FxMap<(i32, i32), f64> = Default::default();
            while k < HU_RUBBLE && sum > 0.0 && crate::meter::spent() + made < HU_STAGE {
                let n = k as u32;
                k += 1;
                crate::meter::spend(1_500);
                let mut u = mh(n, seed, 0x81) * sum;
                let ring = wt.iter().position(|&x| {
                    u -= x;
                    u < 0.0
                });
                let Some(ring) = ring else { continue };
                let y0 = ring_h(ring_r(ring)) * mh(n, seed, 0x82);
                let a = TAU * mh(n, seed, 0x83);
                let s = flung_down(y0);
                let r = ring_r(ring) + flung_out(y0, s);
                let (xo, zo) = (r * a.cos(), r * a.sin());
                let Some((yl, water)) = left_top(wk, bx, bz, xo, zo) else { continue };
                let (x, z) = ((f64::from(bx) + 0.5 + xo).floor() as i32, (f64::from(bz) + 0.5 + zo).floor() as i32);
                if water || wk.rubble_at.contains_key(&(x, z)) {
                    continue;
                }
                let keep = &wk.pal[ring].keep;
                let j0 = (mh(n, seed, 0x84) * keep.len() as f64) as usize;
                let Some(blk) = (0..keep.len()).map(|j| keep[(j0 + j) % keep.len()].2).find(|&b| rubble_ok(b)) else { continue };
                wk.rubble_at.insert((x, z), ());
                let y = gy + yl.round() as i32;
                b.put(x, z, y, y, laid(blk), Some("minecraft:air"), false);
                when.insert((x, z), HU_FLING + s);
                wk.landed[1] += 1;
                made += 1_000;
            }
            for (t, e) in b.split_by(|x, z| at(when.get(&(x, z)).copied().unwrap_or(HU_FLING))) {
                q.ev.push((t, Act::Blocks(Box::new(e))));
            }
        }
        let done = (i >= wk.trees.len() && (k >= HU_RUBBLE || !wk.terrain)) || now > f64::from(HU_LEN);
        if done {
            crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("hurricane: {} blocks of trees and buildings and {} of rubble land", wk.landed[0], wk.landed[1]));
        }
        !done
    };
    if more {
        q.later((now + 0.05) as f32, move |q| hu_landings(q, w, i, k, now + 0.05));
    }
}
// ---- the mobs ----------------------------------------------------------------------------------------------------------
/// The bands of land the mobs are carried round in (each its own speeds), out to the last.
const MOB_BANDS: [(f64, f64); 6] = [(30.0, 50.0), (50.0, 70.0), (70.0, 92.0), (92.0, 118.0), (118.0, 145.0), (145.0, 176.0)];
/// One second's carrying of the mobs (and the items lying about) from `t0`: each tick each band's moved round the
/// middle the way the wind blows, drawn in towards the eyewall and lifted (`tp` along the way they face it from,
/// `^` local steps), their own motion stopped so the game's gravity doesn't pile up on them; once their band is in the
/// wind's front. (cx, y0, cz): the middle, a little up so a band's distance is about its own.
fn mob_second(q: &mut Plan, t0: f64, cx: f64, y0: f64, cz: f64) {
    let sel = "type=!minecraft:player,type=!minecraft:falling_block";
    for k in 0..20 {
        let t = t0 + 0.05 * f64::from(k);
        if t >= HU_FLING {
            break;
        }
        let s = spin(t);
        let mut out = 0.0f64;
        for &(a, b) in &MOB_BANDS {
            let Some(f) = front_t(a.max(HU_R_IN)) else { continue };
            if t < f + 0.5 {
                continue;
            }
            out = out.max(b);
            let m = 0.5 * (a + b);
            let along = HU_V * wind_shape(m) * s * 0.55 / 20.0;
            let inward = ((m - 78.0) * 0.004).clamp(-0.12, 0.25) * s;
            let up = (0.06 + 0.1 * (1.0 - smooth(60.0, 160.0, m))) * s.max(0.3);
            // (facing the middle, ^ is to their left: the storm turning the other way round, cyclonically, it is ^-)
            let left = along * HU_SPIN;
            q.at(t as f32, format!(
                "execute positioned {cx:.1} {y0:.1} {cz:.1} as @e[{sel},distance={a:.0}..{b:.0}] at @s facing {cx:.1} ~ {cz:.1} run tp @s ^{left:.3} ^{up:.3} ^{inward:.3}"
            ));
        }
        if out > 0.0 {
            q.at(t as f32, format!("execute positioned {cx:.1} {y0:.1} {cz:.1} as @e[{sel},distance=30..{out:.0}] run data merge entity @s {{Motion:[0.0d,0.0d,0.0d]}}"));
        }
    }
}

// ---- the eyewall's lightning and its thunder -------------------------------------------------------------------------
/// The pass's flashes (hurricane.wgsl's hu_flashes, hu_flash_rate, hu_inten, hu_widen, hu_flare: keep in step), worked
/// out from the same hashes: when each begins, where it is off the middle's ground, and the foot of its bolt if one
/// strikes the land. A fifth of a second a slot, a flash at most in each.
struct HuFlash {
    t: f64,
    p: [f64; 3],
    foot: Option<[f64; 2]>,
    band: bool,
}
const HU_SLOT: f64 = 0.2;
fn hu_flash_rate(t: f64) -> f64 {
    const K: [(f64, f64); 10] = [(11.0, 0.0), (15.0, 1.0), (18.0, 4.0), (27.0, 3.2), (32.0, 1.3), (41.0, 1.5), (44.5, 3.6), (47.0, 1.2), (52.0, 0.4), (55.0, 0.0)];
    if t <= K[0].0 {
        return 0.0;
    }
    for w in K.windows(2) {
        if t <= w[1].0 {
            return w[0].1 + (w[1].1 - w[0].1) * (t - w[0].0) / (w[1].0 - w[0].0);
        }
    }
    0.0
}
fn hu_wall_in(y: f64, t: f64) -> f64 {
    let inten = smooth(9.0, 30.0, t) * (1.0 - 0.45 * smooth(HU_FLING, HU_CLEAR + 4.0, t));
    let widen = (0.55 + 0.45 * inten) * (1.0 + 0.2 * smooth(36.0, 43.0, t) * (1.0 - smooth(HU_FLING, HU_FLING + 6.0, t)));
    let yy = y.max(0.0);
    HU_R_EYE + 3.0 + (0.08 * yy + 0.00045 * yy * yy) * widen
}
fn hu_wall_out(y: f64, t: f64) -> f64 {
    hu_wall_in(y, t) + 46.0 + 0.1 * y.max(0.0)
}
fn hu_flash_list(seed: u32) -> Vec<HuFlash> {
    let pcg = super::pcg;
    let sh = pcg(seed ^ 0x7a11);
    let mut out = Vec::new();
    for s in 0..(f64::from(HU_LEN) / HU_SLOT) as u32 {
        let ts = f64::from(s) * HU_SLOT;
        let rate = hu_flash_rate(ts);
        if rate <= 0.0 {
            continue;
        }
        let h = pcg(s.wrapping_mul(0x9E37_79B1) ^ sh);
        if f64::from(h & 0xFFFF) / 65535.0 >= rate * HU_SLOT {
            continue;
        }
        let (ha, hb) = (pcg(h), pcg(pcg(h)));
        let hc = pcg(hb);
        let f = |v: u32| f64::from(v) / 65535.0;
        let u = [f(ha & 0xFFFF), f(ha >> 16), f(hb & 0xFFFF), f(hb >> 16)];
        let w = [f(hc & 0xFFFF), f(hc >> 16)];
        let t = ts + HU_SLOT * f(h >> 16);
        let ang = TAU * u[0];
        let dir = [ang.cos(), ang.sin()];
        if u[1] < 0.2 {
            let r = 280.0 + 900.0 * u[2];
            out.push(HuFlash { t, p: [dir[0] * r, 110.0 + 80.0 * u[3], dir[1] * r], foot: None, band: true });
        } else if w[0] < 0.36 {
            let y = 70.0 + 90.0 * u[2];
            let r = hu_wall_out(y, t) - 6.0;
            let fa = ang + HU_SPIN * 0.15 * (w[1] - 0.3);
            let fr = hu_wall_out(0.0, t) + 6.0 + 55.0 * (w[0] * 2.77 + w[1]).fract();
            out.push(HuFlash { t, p: [dir[0] * r, y, dir[1] * r], foot: Some([fa.cos() * fr, fa.sin() * fr]), band: false });
        } else {
            let y = 90.0 + 250.0 * u[2];
            let r = hu_wall_in(y, t) + 12.0 + 26.0 * u[3];
            out.push(HuFlash { t, p: [dir[0] * r, y, dir[1] * r], foot: None, band: false });
        }
    }
    out
}
/// A bolt's thunder `d` blocks off as a file's loudest 400 ms in dB (strike/storm.rs's thunder_db, the Supercell's): 4 dB
/// down each time the distance doubles past 60.
fn hu_thunder_db(d: f64) -> f64 {
    -15.0 - 4.0 * (d.max(60.0) / 60.0).log2()
}
/// The thunder of the flashes at the player `me` (the middle at `c`), as tools/sounds_hurricane.py's LEVEL has each kind:
/// a bolt's by its distance (a crack within 110 blocks, a duller clap to 320, mostly roll past it), a flash deep in the
/// eyewall or out in a band a roll up in the cloud (most of them: some unheard under the wind). Late by the distance;
/// two within 0.2 s of each other heard as one clap (their power added, the nearer's take); one while louder still
/// rolls let down a little; a kind's take never one of its last two.
fn hu_thunder(s: u32, c: [f64; 3], me: [f64; 3]) -> Vec<(f32, String, f32, f32)> {
    let mut order: Vec<(f64, f64, bool, u32)> = Vec::new();
    for (i, f) in hu_flash_list(s).iter().enumerate() {
        let i = i as u32;
        let (src, bolt) = match f.foot {
            Some(ft) => ([c[0] + ft[0], c[1], c[2] + ft[1]], true),
            None => ([c[0] + f.p[0], c[1] + f.p[1], c[2] + f.p[2]], false),
        };
        // (a third of the eyewall's flashes and half the bands' unheard under the storm)
        if !bolt && mh(i, s, 0xe1) < if f.band { 0.5 } else { 0.33 } {
            continue;
        }
        let (late, d) = sound_from(src, me);
        order.push((f.t + f64::from(late), d, bolt, i));
    }
    order.sort_by(|a, b| a.0.total_cmp(&b.0));
    let power = |d: f64, bolt: bool| 10f64.powf((hu_thunder_db(d) - if bolt { 0.0 } else { 6.0 }) / 10.0);
    // (the claps: when, the nearest's distance, a bolt's or not, which, their power together)
    let mut claps: Vec<(f64, f64, bool, u32, f64)> = Vec::new();
    for (at, d, bolt, i) in order {
        let pw = power(d, bolt);
        match claps.last_mut() {
            Some(l) if at - l.0 < 0.2 => {
                if pw > power(l.1, l.2) {
                    (l.1, l.2, l.3) = (d, bolt, i);
                }
                l.4 += pw;
            }
            _ => claps.push((at, d, bolt, i, pw)),
        }
    }
    let mut recent: Vec<(&'static str, u32)> = Vec::new();
    let mut rolling: Vec<(f64, f64)> = Vec::new();
    let mut out = Vec::new();
    for (at, d, bolt, i, pw) in claps {
        let (kind, level) = match (bolt, d) {
            (true, d) if d < 110.0 => ("thunder", -14.0),
            (true, d) if d < 320.0 => ("thunder_mid", -17.5),
            (true, _) => ("thunder_far", -21.0),
            (false, _) => ("rumble", -25.5),
        };
        let db = 10.0 * pw.log10();
        let loud = 10f64.powf(db / 20.0);
        let busy: f64 = rolling.iter().map(|(t, l)| l * (-(at - t).max(0.0) / 1.2).exp()).sum();
        let duck = (1.0 / (1.0 + 0.6 * busy / loud)).max(0.6);
        rolling.push((at, loud * duck));
        let last2: Vec<u32> = recent.iter().rev().filter(|(k, _)| *k == kind).take(2).map(|(_, v)| *v).collect();
        let free: Vec<u32> = (1..=4).filter(|v| !last2.contains(v)).collect();
        let take = free[((mh(i, s, 0xe2) * free.len() as f64) as usize).min(free.len() - 1)];
        recent.push((kind, take));
        let volume = (10f64.powf((db - level) / 20.0).min(1.0) * duck) as f32;
        out.push((at as f32, format!("{kind}{take}"), volume, 0.9 + 0.16 * mh(i, s, 0xe3) as f32));
    }
    out
}

// ---- the plan ------------------------------------------------------------------------------------------------------------
pub(super) fn hurricane_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let s = shader_seed as u32;
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let len = laser.length;

    // ---- the pass's table (empty of trees and colours until the land is read), and the land's work ---------------------
    p.ev.push((0.05, Act::Table(hu_table_empty(terrain))));
    let work = Rc::new(RefCell::new(Work {
        land: Land { cols: vec![Col::default(); (HU_GW * HU_GW) as usize], segs: Vec::new(), missing: vec![Vec::new(); HU_PARTS as usize], late: Vec::new(), gdy0: 0 },
        tags: (0..HU_PARTS).map(|_| crate::columns::new_tag()).collect(),
        asked: 0,
        taken: 0,
        retry: None,
        rnext: 0,
        rat: 0.0,
        sectors: hu_sectors(),
        trees: Vec::new(),
        told: 0,
        pal: vec![Pal::default(); HU_NR],
        pal_dirty: false,
        kinds: default_kinds(),
        grid: vec![(0.0, 0); HU_GR * HU_GA],
        grid_dirty: false,
        gdy_told: None,
        crack_last: f64::MIN,
        crack_take: 0,
        cracks: Vec::new(),
        rubble_at: Default::default(),
        landed: [0; 2],
        gone: [0; 8],
        whole: 0,
        pieces: 0,
        gy: by + 1,
        terrain,
        seed: s,
        me,
        done: false,
    }));
    {
        let w = work.clone();
        p.later(0.1, move |q| hu_work(q, w, 0.1));
    }

    // ---- the sounds: three continuous beds (tools/sounds_hurricane.py), the storm's whole life written into each,
    // played once from the start, each as loud as the distance lets it be; the debris over them now and then -----------
    let (_, dist) = sound_from([cx, gy, cz], me);
    // (from the eyewall: all of it within 60 of it, a third at 400 off)
    let near = (1.0 / (1.0 + (dist - HU_R_W).max(0.0) / 170.0)) as f32;
    p.csound(0.0, "wind", 10.0 * (0.55 + 0.45 * near), 1.0);
    p.csound(0.0, if dist > 330.0 { "roar_far" } else { "roar" }, 10.0 * (0.3 + 0.7 * near).min(1.0), 1.0);
    p.csound(0.0, "rain", 10.0 * (0.5 + 0.5 * near), 1.0);
    let mut t = HU_F0 + 4.0;
    let mut n = 0u32;
    let mut last = 0u32;
    while t < HU_FLING + 1.0 {
        // (a take never the last one again)
        let mut k = (mh(n, s, 0x71) * 4.0) as u32 % 4 + 1;
        if k == last {
            k = k % 4 + 1;
        }
        last = k;
        p.ev.push((t as f32, Act::Sound { event: format!("orbital:hurricane.debris{k}"), at: None, volume: (0.25 + 0.45 * spin(t)) as f32 * near, pitch: 0.92 + 0.16 * mh(n, s, 0x72) as f32 }));
        t += 2.6 + 2.2 * mh(n, s, 0x73);
        n += 1;
    }
    // (the eyewall's lightning heard: its thunder, in the order it reaches the player)
    for (at, event, volume, pitch) in hu_thunder(s, [cx, gy, cz], me) {
        p.csound(at, &event, 10.0 * volume, pitch);
    }
    // (the ground trembling under it, the more as it strengthens and the nearer)
    let fo = (1.5 / (1.0 + (dist - HU_R_W).max(0.0) / 120.0)).min(1.0) as f32;
    let mut t = HU_F0 - 3.0;
    while t < HU_FLING + 2.0 {
        p.shake(t as f32, (0.04 + 0.2 * spin(t)) as f32 * fo, 0.45);
        t += 0.35;
    }

    // ---- the mobs carried round, flung out as it drops, coming down where they fall -----------------------------------
    if terrain {
        let y0 = gy + 30.0;
        let mut t = HU_F0 + 2.0;
        while t < HU_FLING {
            let t0 = t;
            p.later((t0 - 0.5) as f32, move |q| mob_second(q, t0, cx, y0, cz));
            t += 1.0;
        }
        // (flung: given their own motion, out and on along the wind and up, by the 40-block square they are over (each
        // square's way out from the middle); then they fly and fall as the game moves them, and the fall hurts)
        let sel = "type=!minecraft:player,type=!minecraft:falling_block";
        let sq = 40.0;
        for i in -5..5 {
            for j in -5..5 {
                let (mx, mz) = ((f64::from(i) + 0.5) * sq, (f64::from(j) + 0.5) * sq);
                let r = mx.hypot(mz);
                if r > 205.0 {
                    continue;
                }
                let (ox, oz) = (mx / r, mz / r);
                let (tx, tz) = (-oz * HU_SPIN, ox * HU_SPIN);
                let (out, on) = (0.9, 0.6 * wind_shape(r.max(HU_R_IN)));
                let (vx, vz) = (ox * out + tx * on, oz * out + tz * on);
                let (x0, z0) = (cx + f64::from(i) * sq, cz + f64::from(j) * sq);
                p.at(HU_FLING as f32, format!(
                    "execute positioned {x0:.1} {:.1} {z0:.1} as @e[{sel},dx={sq:.0},dy=400,dz={sq:.0}] run data merge entity @s {{Motion:[{vx:.3}d,0.9d,{vz:.3}d]}}",
                    gy - 40.0
                ));
            }
        }
        // (the chunks it works in kept loaded while it does, a target far off too)
        let load = pk_load_rows([cx, gy, cz], 0.0, f64::from(HU_READ) + 4.0);
        for [x0, z0, x1, z1] in &load {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for [x0, z0, x1, z1] in &load {
            p.ev.push((len - 0.5, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// The table before the land is read: no trees, the rings' colours grass, dirt and leaves.
fn hu_table_empty(terrain: bool) -> Vec<u32> {
    let mut w = vec![0u32; HU_WORDS];
    w[2] = f32::from(u8::from(terrain)).to_bits();
    let k0 = default_kinds();
    w[3] = k0.list.len() as u32;
    for (i, &(b, g, f)) in k0.list.iter().enumerate() {
        w[HU_BK + HU_BKW * i..HU_BK + HU_BKW * (i + 1)].copy_from_slice(&bk_words(b, g, f));
    }
    for k in 0..HU_NR {
        for j in 0..HU_PN {
            w[HU_PAL + k * HU_PN + j] = ((j * 7 + k) % k0.list.len()) as u32;
        }
    }
    for v in &mut w[HU_G..HU_G + HU_GR * HU_GA] {
        *v = f32::NAN.to_bits();
    }
    w
}

/// The land for the tests and the preview: rolling hills `hills` high (as tools/preview's `hills_h`, the target's ground
/// at `ty`) wooded as the preview's `trees=1` wood is (its trees where its trees are), a lake east of it now and then.
#[cfg(test)]
pub(super) fn synth_column(x: i32, z: i32, below: u32, above: u32, ty: i32, hills: f32, forest: bool) -> Option<(i32, Vec<&'static str>)> {
    let hash = |x: i32, z: i32| -> f32 {
        let mut h = (x as u32).wrapping_mul(374_761_393) ^ (z as u32).wrapping_mul(668_265_263);
        h = (h ^ (h >> 13)).wrapping_mul(1_274_126_177);
        ((h ^ (h >> 16)) & 0xFFFF) as f32 / 65535.0
    };
    let (fx, fz) = (x as f32 + 0.5, z as f32 + 0.5);
    let hill = |x: f32, z: f32| hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin());
    let g = ty + (hill(fx, fz) - hill(0.5, 0.5)).round() as i32 - 1;
    // (a tree: as the preview's, in cells of 7, its crown a diamond 2-3 out, 7-13 high)
    let (cx, cz) = (x.div_euclid(7), z.div_euclid(7));
    let mut trunk = 0;
    let mut crown: Option<(i32, i32)> = None;
    if forest {
        for (ccx, ccz) in [(cx, cz), (cx - 1, cz), (cx + 1, cz), (cx, cz - 1), (cx, cz + 1)] {
            if hash(ccx, ccz + 911) < 0.62 {
                continue;
            }
            let ox = ccx * 7 + 1 + (hash(ccx + 5, ccz) * 4.0) as i32;
            let oz = ccz * 7 + 1 + (hash(ccx, ccz + 5) * 4.0) as i32;
            let rr = 2 + (hash(ccx + 9, ccz + 3) * 1.6) as i32;
            let h = 7 + (hash(ccx + 2, ccz + 7) * 6.0) as i32;
            let (dx, dz) = ((x - ox).abs(), (z - oz).abs());
            if dx == 0 && dz == 0 {
                trunk = h - 2;
            }
            if dx.max(dz) <= rr && dx + dz <= rr + 1 {
                crown = Some((h - 4 - (dx + dz) / 2, h - (dx + dz) / 2));
            }
        }
    }
    let top = crown.map_or(g + trunk.max(0), |c| g + c.1.max(trunk));
    let per = (below + above) as usize;
    let y0 = top + 1 - below as i32;
    let mut v = Vec::with_capacity(per);
    for i in 0..per as i32 {
        let y = y0 + i;
        v.push(if y > top {
            "minecraft:air"
        } else if y == g {
            "minecraft:grass_block"
        } else if y < g - 4 {
            "minecraft:stone"
        } else if y < g {
            "minecraft:dirt"
        } else if y <= g + trunk {
            "minecraft:oak_log"
        } else if let Some((lo, hi)) = crown
            && y >= g + lo
            && y <= g + hi
        {
            "minecraft:oak_leaves"
        } else if y == g + 1 && hash(x, z) < 0.3 {
            "minecraft:short_grass"
        } else {
            "minecraft:air"
        });
    }
    Some((top + 1, v))
}

/// `HU_OUT=path HU_ME=z cargo test --release hu_write_sounds -- --ignored`: the sounds a player HU_ME blocks south of the
/// target hears (`t event volume pitch`, a positioned one's volume as the game fades it, linearly to 256 blocks), the
/// land a wood; with HU_CARRY=1 the player carried off by the wind as the carry would (its whooshes).
#[cfg(test)]
#[test]
#[ignore]
fn hu_write_sounds() {
    let z: f64 = std::env::var("HU_ME").map_or(150.0, |v| v.parse().unwrap());
    let carry = std::env::var("HU_CARRY").is_ok_and(|v| v == "1");
    let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
    let me = [0.5, 66.0, 0.5 + z];
    let laser = crate::lasers::LASERS.iter().find(|l| l.key == "hurricane").unwrap();
    let ev = crate::strike::plan(laser, &target, true, "minecraft:overworld", 37.0, me, 0);
    let mut out = String::new();
    let mut ev = ev;
    crate::columns::clear();
    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
    while let Some((t, a)) = ev.pop() {
        match a {
            Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| synth_column(x, z, below, above, 65, 0.0, true)),
            Act::Sound { event, at, volume, pitch } => {
                let v = at.map_or(volume, |p| volume * (1.0 - ((p[0] - me[0]).hypot(p[2] - me[2]) / 256.0).min(1.0)) as f32);
                out += &format!("{t:.3} {event} {v:.3} {pitch:.3}\n");
            }
            Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                ev.extend(job());
                ev.sort_by(|a, b| b.0.total_cmp(&a.0));
            }
            _ => {}
        }
    }
    if carry {
        let mut c = crate::carry::Carry::new([0.5, 65.0, 0.5]);
        let mut feet = me;
        for n in 1..(64 * 20) {
            let t = f64::from(n) * 0.05;
            let o = c.tick(t, feet, true, false, true);
            if let Some(next) = c.target {
                feet = next;
            }
            for (event, volume, pitch) in o.sounds {
                out += &format!("{t:.3} {event} {volume:.3} {pitch:.3}\n");
            }
        }
    }
    std::fs::write(std::env::var("HU_OUT").unwrap(), out).unwrap();
}

#[cfg(test)]
mod table {
    /// `CB_SEED=37 CB_OUT=path PL_HILLS=H cargo test --release hu_write_table -- --ignored`: the table the pass reads, for
    /// tools/preview.py (a line `index value` a word): the target at the preview's 0.5 65 0.5, on its wooded land (the
    /// trees torn up as the front reaches them), played through the plan so the trees and colours are the real ones.
    #[test]
    #[ignore]
    fn hu_write_table() {
        use super::*;
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let hills: f32 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap());
        let forest = std::env::var("HU_FOREST").map_or(true, |v| v != "0");
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let laser = crate::lasers::LASERS.iter().find(|l| l.key == "hurricane").unwrap();
        let ev = crate::strike::plan(laser, &target, true, "minecraft:overworld", seed, [0.5, 66.0, 300.5], 0);
        let mut data: Vec<u32> = Vec::new();
        // (HU_GLASS=1: some of the land's top blocks glass, stained glass and ice, to see the pass draw them through)
        let glass = std::env::var("HU_GLASS").is_ok_and(|v| v == "1");
        let answer = move |x: i32, z: i32, b: u32, a: u32| {
            let mut c = synth_column(x, z, b, a, 65, hills, forest);
            let h = (x as u32).wrapping_mul(2_654_435_761) ^ (z as u32).wrapping_mul(40_503);
            if glass && (h >> 7) % 5 < 2 {
                const GLASS: [&str; 4] = ["minecraft:glass", "minecraft:red_stained_glass", "minecraft:light_blue_stained_glass", "minecraft:ice"];
                if let Some((_, v)) = c.as_mut() {
                    for s in v.iter_mut().filter(|s| **s == "minecraft:grass_block") {
                        *s = GLASS[((h >> 13) % 4) as usize];
                    }
                }
            }
            c
        };
        crate::columns::clear();
        let mut ev = ev;
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        while let Some((_, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| answer(x, z, below, above)),
                Act::Table(w) => {
                    if data.len() < w.len() {
                        data.resize(w.len(), 0);
                    }
                    data[..w.len()].copy_from_slice(&w);
                }
                Act::Words { index, words } => {
                    let i = index as usize;
                    if data.len() < i + words.len() {
                        data.resize(i + words.len(), 0);
                    }
                    data[i..i + words.len()].copy_from_slice(&words);
                }
                Act::Data { index, value } => {
                    if data.len() <= index as usize {
                        data.resize(index as usize + 1, 0);
                    }
                    data[index as usize] = value.to_bits();
                }
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        let text: String = data.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
    /// The preview's village: six houses 40 to 160 out from the target at the preview's 0 64 0 (its ground's top at 64),
    /// each of planks or cobblestone, glass in its walls, a door, a roof of stairs round its edge and slabs over it, a
    /// chest and torches inside; a wood west of x -60 (the preview's synthetic trees, `synth_column`), open grass
    /// elsewhere. A column as `test_answer` takes it: its top block's height + 1, and its blocks from `below` under
    /// that to `above` over it.
    pub(super) fn village_column(x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        // (x0, z0, width, depth, wall)
        const HOUSES: [(i32, i32, i32, i32, &str); 6] = [
            (48, 6, 7, 9, "minecraft:oak_planks"),
            (-30, 62, 9, 7, "minecraft:cobblestone"),
            (80, -66, 7, 7, "minecraft:spruce_planks"),
            (-104, -36, 11, 7, "minecraft:oak_planks"),
            (14, -124, 7, 9, "minecraft:cobblestone"),
            (118, 56, 9, 9, "minecraft:birch_planks"),
        ];
        let mut top: Vec<&'static str> = Vec::new();
        let mut ground = "minecraft:grass_block";
        for &(x0, z0, w, d, wall) in &HOUSES {
            let (i, j) = (x - x0, z - z0);
            if i < 0 || j < 0 || i >= w || j >= d {
                continue;
            }
            ground = "minecraft:dirt";
            let edge = i == 0 || j == 0 || i == w - 1 || j == d - 1;
            let corner = (i == 0 || i == w - 1) && (j == 0 || j == d - 1);
            let roof = if edge { "minecraft:oak_stairs" } else { "minecraft:oak_slab" };
            top = if !edge {
                let mut v = vec!["minecraft:oak_planks", "minecraft:air", "minecraft:air", "minecraft:air", "minecraft:air", roof];
                if (i, j) == (1, 1) {
                    v[1] = "minecraft:chest";
                } else if (i, j) == (w - 2, d - 2) {
                    v[1] = "minecraft:torch";
                } else if (i, j) == (1, d / 2) {
                    v[3] = "minecraft:wall_torch";
                }
                v
            } else if corner {
                vec!["minecraft:cobblestone", "minecraft:oak_log", "minecraft:oak_log", "minecraft:oak_log", "minecraft:oak_log", roof]
            } else if j == 0 && i == w / 2 {
                vec!["minecraft:cobblestone", "minecraft:oak_door", "minecraft:oak_door", wall, wall, roof]
            } else if (i + j) % 2 == 0 {
                vec!["minecraft:cobblestone", wall, "minecraft:glass_pane", wall, wall, roof]
            } else {
                vec!["minecraft:cobblestone", wall, wall, wall, wall, roof]
            };
        }
        if top.is_empty() {
            // (a wood to the west, open grass and flowers elsewhere)
            return super::synth_column(x, z, below, above, 65, 0.0, x < -60);
        }
        let surface = 65 + top.len() as i32;
        let y0 = surface - below as i32;
        let v = (0..(below + above) as i32)
            .map(|k| {
                let y = y0 + k;
                if y > 64 {
                    top.get((y - 65) as usize).copied().unwrap_or("minecraft:air")
                } else if y == 64 {
                    ground
                } else if y > 60 {
                    "minecraft:dirt"
                } else {
                    "minecraft:stone"
                }
            })
            .collect();
        Some((surface, v))
    }

    /// `CB_SEED=37 CB_OUT=path HU_VOX_TIMES=10,20,30 HU_VOX_DIR=dir cargo test --release hu_write_village -- --ignored`:
    /// the strike over the preview's village (`village_column`) played through: the pass's table, as `hu_write_table`
    /// writes it, and for each of the times every block standing over the ground then (the village as built, less
    /// every edit made by then, with what has landed by then), a line `x y z r g b` a block (its side's colour 0-1,
    /// leaves and grass tinted as the plains' are) in HU_VOX_DIR/vox_<t>.txt, for tools/preview's `vox=1`.
    #[test]
    #[ignore]
    fn hu_write_village() {
        use super::*;
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let times: Vec<f32> = std::env::var("HU_VOX_TIMES").map_or(vec![], |v| v.split(',').filter(|s| !s.is_empty()).map(|s| s.trim().parse().unwrap()).collect());
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let laser = crate::lasers::LASERS.iter().find(|l| l.key == "hurricane").unwrap();
        let mut ev = crate::strike::plan(laser, &target, true, "minecraft:overworld", seed, [0.5, 66.0, 300.5], 0);
        let mut data: Vec<u32> = Vec::new();
        let mut edits: Vec<(f32, Blocks)> = Vec::new();
        crate::columns::clear();
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| village_column(x, z, below, above)),
                Act::Table(w) => {
                    if data.len() < w.len() {
                        data.resize(w.len(), 0);
                    }
                    data[..w.len()].copy_from_slice(&w);
                }
                Act::Words { index, words } => {
                    let i = index as usize;
                    if data.len() < i + words.len() {
                        data.resize(i + words.len(), 0);
                    }
                    data[i..i + words.len()].copy_from_slice(&words);
                }
                Act::Data { index, value } => {
                    if data.len() <= index as usize {
                        data.resize(index as usize + 1, 0);
                    }
                    data[index as usize] = value.to_bits();
                }
                Act::Blocks(b) => edits.push((t, *b)),
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        if let Ok(out) = std::env::var("CB_OUT") {
            let text: String = data.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
            std::fs::write(out, text).unwrap();
        }
        if times.is_empty() {
            return;
        }
        // the world over the ground: the village as built, out to where the strike reads it
        let mut world: std::collections::HashMap<(i32, i32, i32), &'static str> = Default::default();
        let n = HU_READ + 2;
        for z in -n..=n {
            for x in -n..=n {
                if x * x + z * z > n * n {
                    continue;
                }
                let Some((surface, v)) = village_column(x, z, HU_BELOW, 1) else { continue };
                let y0 = surface - HU_BELOW as i32;
                for (k, b) in v.iter().enumerate() {
                    let y = y0 + k as i32;
                    if y > 64 && *b != "minecraft:air" {
                        world.insert((x, y, z), b);
                    }
                }
            }
        }
        let bare = |n: &str| -> String { n.split('[').next().unwrap_or(n).to_string() };
        edits.sort_by(|a, b| a.0.total_cmp(&b.0));
        let mut next = 0;
        let dir = std::path::PathBuf::from(std::env::var("HU_VOX_DIR").unwrap_or(".".into()));
        std::fs::create_dir_all(&dir).unwrap();
        let mut times = times;
        times.sort_by(|a, b| a.total_cmp(b));
        for t in times {
            // (every edit due by then, made as the game makes it: a run's blocks set where they are what it is `only`
            // for, or all of them)
            while next < edits.len() && edits[next].0 <= t {
                let b = &edits[next].1;
                for r in &b.runs {
                    let block = b.palette[r.block as usize];
                    let only = r.only.map(|f| b.filters[f as usize]);
                    for y in r.y..r.y + r.height as i32 {
                        let here = world.get(&(r.x, y, r.z)).copied().unwrap_or("minecraft:air");
                        if only.is_some_and(|f| bare(f) != bare(here)) {
                            continue;
                        }
                        if block == "minecraft:air" {
                            world.remove(&(r.x, y, r.z));
                        } else if y > 64 {
                            world.insert((r.x, y, r.z), block);
                        }
                    }
                }
                next += 1;
            }
            let mut text = String::new();
            for (&(x, y, z), &n) in &world {
                let Some(k) = hu_block(&bare(n)).map(|b| &HU_BLOCKS[b as usize]) else { continue };
                // (grass and leaves tinted as the plains tint them)
                let tint: [u8; 3] = match k.tint {
                    1 => [0x91, 0xBD, 0x59],
                    2 => [0x77, 0xAB, 0x2F],
                    _ => [255, 255, 255],
                };
                let c = |i: usize| f32::from(k.side[i]) / 255.0 * f32::from(tint[i]) / 255.0;
                text += &format!("{x} {y} {z} {:.3} {:.3} {:.3}\n", c(0), c(1), c(2));
            }
            let path = dir.join(format!("vox_{t}.txt"));
            eprintln!("{}: {} blocks", path.display(), world.len());
            std::fs::write(path, text).unwrap();
        }
    }

}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    fn the_laser() -> &'static Laser {
        crate::lasers::LASERS.iter().find(|l| l.key == "hurricane").expect("the hurricane")
    }
    /// The plan played as the mod plays it, a stage a tick, the land answered as `hills` and `forest` say.
    fn played(terrain: bool, me: [f64; 3], hills: f32, forest: bool) -> crate::strike::sim::Played {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let ev = plan(the_laser(), &target, terrain, "minecraft:overworld", 37.0, me, 0);
        crate::strike::sim::play(ev, HU_LEN, &move |x, z, b, a| synth_column(x - 10, z + 3, b, a, 65, hills, forest))
    }

    #[test]
    fn hurricane_spins_up_peaks_and_dies_away() {
        assert!(spin(0.0) < 0.1 && spin(26.0) > 0.99 && spin(40.0) > 0.99 && spin(f64::from(HU_LEN)) < 0.01);
        // (its sum rising all the way, faster at its height)
        let (a, b) = (spin_int(20.0) - spin_int(10.0), spin_int(40.0) - spin_int(30.0));
        assert!(b > 2.0 * a && (spin_int(64.0) - spin_int(63.0)) < 0.05);
        assert!((spin_int(30.0) - spin_int(29.0) - 1.0).abs() < 1e-9);
        // (the front: at the eyewall first, in to the eye's edge and out to the trees' reach on time)
        assert_eq!(front_t(HU_R_W), Some(HU_F0));
        assert!((front_t(HU_R_LIFT).unwrap() - HU_F1).abs() < 1e-9);
        assert!(front_t(HU_R_EYE).is_none() && front_t(HU_R_PLANTS + 1.0).is_none());
        assert!(front_t(HU_R_IN).unwrap() < HU_F0 + 3.01);
        // (the wind fastest at the eyewall, a full turn there in some ten seconds at its height)
        let turn = TAU / omega(HU_R_W);
        assert!((8.0..12.0).contains(&turn), "{turn}");
        assert!(omega(HU_R_W) * HU_R_W > omega(140.0) * 140.0);
    }

    #[test]
    fn hurricane_has_thousands_of_blocks_in_the_air_within_the_tables_room() {
        // (at its height some tens of thousands round the eyewall, thousands of them in plain sight under its cloud;
        // none before the front, none once it has rained back down)
        let peak = hu_in_air(42.0);
        let seen = hu_in_sight(42.0);
        eprintln!("in the air at 42 s: {peak:.0} ({seen:.0} under the cloud); at 20 s {:.0}; at 30 s {:.0}", hu_in_air(20.0), hu_in_air(30.0));
        assert!(seen > 3000.0 && peak > seen && peak < 60_000.0, "{peak} {seen}");
        assert!(hu_in_air(HU_F0 - 1.0) < 1.0 && hu_in_air(HU_FLING + 8.5) < 1.0 && hu_in_air(HU_F0 + 0.5) < 400.0);
        assert!(hu_in_air(20.0) < hu_in_air(30.0) && hu_in_air(30.0) <= hu_in_air(40.0) + 1.0);
        // (the table: everything where the pass reads it, under the game's limit)
        assert!(HU_PAL + HU_NR * HU_PN <= HU_T && HU_T + HU_TW * HU_NT == HU_G && HU_WORDS <= 1 << 18);
        let tr = TreeRec { x: 1.0, z: 2.0, gdy: 0.0, t_up: 20.0, trunk: 6, wood_bk: 0, leaf_bk: 2, wood: 0, leaf: 0, spans: [(4, 8); 49], t_land: 50.5, yl: -2.0, yaw: 1.25, t_break: 1e9 };
        let w = tr.words();
        assert_eq!((f32::from_bits(w[25]), f32::from_bits(w[26]), f32::from_bits(w[27])), (50.5, -2.0, 1.25));
        assert_eq!(w[4] & 31, 6);
        assert_eq!((w[8 + 48 / 3] >> (10 * (48 % 3))) & 1023, 4 | 8 << 5);
    }

    #[test]
    fn hurricane_tears_up_the_trees_and_the_ground_as_its_front_reaches_them() {
        let p = played(true, [10.5, 66.0, 297.5], 0.0, true);
        let (cx, cz) = (10.5, -2.5);
        let mut logs = 0;
        let mut dug = 0;
        // (what it tears up: what comes down as it lands is its own test's)
        for (t, due, b) in p.edits.iter().filter(|e| !e.2.clear_of_player) {
            for f in b.as_fills() {
                let w: Vec<f64> = f.split_whitespace().skip(1).take(6).map(|v| v.parse().unwrap_or(0.0)).collect();
                let r = (w[0] + 0.5 - cx).hypot(w[2] + 0.5 - cz);
                // (nothing in the eye, nothing past the plants' reach; nothing before the front reaches its chunk)
                assert!(r > HU_R_IN - 12.0 && r < HU_R_PLANTS + 12.0, "{f}");
                assert!(*due >= HU_F0 as f32 - 4.0, "{due} {f}");
                assert!(*t - *due < 0.3, "an edit {:.2} s late (due {due:.2}): {f}", t - due);
                if f.contains("replace minecraft:oak_log") {
                    assert!(r < HU_R_LIFT + 1.0, "{f}");
                    logs += 1;
                }
                if f.ends_with("minecraft:air strict") {
                    dug += 1;
                }
            }
        }
        assert!(logs > 300 && dug > 10_000, "{logs} trunks, {dug} dug");
        // (the stages light, the mobs carried and the blocks thrown back down)
        let worst = p.stages.iter().map(|s| s.2).fold(0.0, f64::max);
        eprintln!("{} stages, heaviest {worst:.2} ms; {} edits", p.stages.len(), p.edits.len());
        assert!(p.cmds.iter().filter(|(_, c)| c.contains("run tp @s ^")).count() > 2000);
        // (flung, given their own motion, never killed at the end; the trees and the rubble laid down where they land)
        assert!(p.cmds.iter().filter(|(t, c)| (*t - HU_FLING as f32).abs() < 0.1 && c.contains("data merge entity @s {Motion:[")).count() > 50);
        assert!(!p.cmds.iter().any(|(_, c)| c.contains(" kill ") || c.contains("summon minecraft:falling_block")));
        let laid: usize = p.edits.iter().filter(|e| e.2.clear_of_player).map(|e| e.2.runs.len()).sum();
        eprintln!("{laid} runs laid down as it all lands");
        assert!(laid > 3000, "{laid}");
    }

    #[test]
    fn hurricane_leaves_the_land_alone_with_the_terrain_off() {
        let p = played(false, [10.5, 66.0, 297.5], 0.0, true);
        assert!(p.edits.iter().all(|e| e.2.runs.is_empty()), "an edit with the terrain off");
        for (_, c) in &p.cmds {
            assert!(!c.contains("forceload") && !c.contains("summon") && !c.contains("tp @s") && !c.contains("kill"), "{c}");
        }
    }

    #[test]
    fn hurricane_lifts_real_trees_whole_within_the_tables_room() {
        // (the trees the pass draws whole are the land's own, where they stood, torn up as the front reaches them)
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let ev = plan(the_laser(), &target, true, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let mut trees = 0.0f32;
        let mut words: Vec<(u32, Vec<u32>)> = Vec::new();
        let mut ev = ev;
        crate::columns::clear();
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        while let Some((_, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| synth_column(x, z, below, above, 65, 0.0, true)),
                Act::Data { index: 0, value } => trees = value,
                Act::Words { index, words: w } => words.push((index, w)),
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        assert!(trees as usize > 60 && trees as usize <= HU_NT, "{trees} trees");
        let first = words.iter().find(|(i, _)| *i == HU_T as u32).expect("the trees' words");
        let (x, z, t_up) = (f32::from_bits(first.1[0]), f32::from_bits(first.1[1]), f32::from_bits(first.1[3]));
        let r = f64::from(x).hypot(f64::from(z));
        assert!(r > HU_R_IN - 1.0 && r < HU_R_LIFT, "{r}");
        let f = front_t(r).unwrap();
        assert!((f64::from(t_up) - f).abs() < 6.0, "torn up at {t_up}, its front at {f}");
        assert!(first.1[4] & 31 >= 3, "a trunk");
        // (and its path: up off the land, round the eyewall, flung out and back down before the end)
        let tr = TreeRec { x: f64::from(x), z: f64::from(z), gdy: 0.0, t_up: f64::from(t_up), trunk: 6, wood_bk: 0, leaf_bk: 2, wood: 0, leaf: 0, spans: [(4, 8); 49], t_land: 1e9, yl: 0.0, yaw: 0.0, t_break: 1e9 };
        let g = |_: f64, _: f64| 0.0;
        let mid = tree_at(&tr, 0, 37, 40.0, &g);
        assert!(mid.up && mid.p[1] > 20.0 && mid.p[0].hypot(mid.p[2]) > 50.0, "{:?}", mid.p);
        assert!(!tree_at(&tr, 0, 37, f64::from(HU_LEN) - 1.0, &g).up);
    }

    #[test]
    fn every_block_the_test_worlds_read_has_its_own_colours() {
        // (the table sorted, so its binary search finds every name; every block of every test world's columns, the
        // trees' woods and leaves of every kind among them, known by name: none falls back to a guess)
        assert!(HU_BLOCKS.windows(2).all(|w| w[0].name < w[1].name));
        for (i, b) in HU_BLOCKS.iter().enumerate() {
            assert_eq!(hu_block(b.name), Some(i as u16), "{}", b.name);
        }
        let mut names: Vec<&str> = vec![
            "minecraft:grass_block", "minecraft:dirt", "minecraft:stone", "minecraft:oak_log", "minecraft:oak_leaves", "minecraft:short_grass",
            "minecraft:water", "minecraft:lava", "minecraft:sand", "minecraft:red_sand", "minecraft:gravel", "minecraft:coarse_dirt",
            "minecraft:snow", "minecraft:spruce_log", "minecraft:spruce_leaves", "minecraft:vine", "minecraft:hanging_roots", "minecraft:moss_block",
            "minecraft:tuff", "minecraft:deepslate", "minecraft:cobblestone", "minecraft:mossy_cobblestone", "minecraft:blackstone", "minecraft:magma_block",
        ];
        for w in ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "pale_oak"] {
            for suffix in ["_log", "_wood", "_leaves"] {
                names.push(Box::leak(format!("minecraft:{w}{suffix}").into_boxed_str()));
                names.push(Box::leak(format!("minecraft:stripped_{w}{suffix}").into_boxed_str()));
            }
        }
        names.retain(|n| !n.contains("stripped") || !n.ends_with("_leaves"));
        names.extend(["minecraft:crimson_stem", "minecraft:warped_stem", "minecraft:mushroom_stem", "minecraft:bamboo_block", "minecraft:azalea_leaves", "minecraft:flowering_azalea_leaves"]);
        for n in &names {
            let b = hu_block(n).unwrap_or_else(|| panic!("{n} not known"));
            let k = &HU_BLOCKS[b as usize];
            assert!(k.class != 0 && k.side != [0, 0, 0], "{n}");
            if n.ends_with("_log") || n.ends_with("_wood") || n.ends_with("_stem") {
                assert_eq!(k.class, 3, "{n}");
            }
            if n.ends_with("_leaves") {
                assert_eq!(k.class, 4, "{n}");
            }
        }
        // (what the old lookup, the sinkhole's 63 materials, made of the trees' blocks, where it was far off their own)
        let far = |a: [u8; 3], b: [u8; 3]| (0..3).map(|i| (i32::from(a[i]) - i32::from(b[i])).abs()).sum::<i32>() > 60;
        let mut off = Vec::new();
        for k in HU_BLOCKS.iter().filter(|k| k.class == 3 || k.class == 4) {
            let (m, _) = sh_land::material(k.name);
            let (top, side, _, kind) = sh_land::MATS[m as usize];
            let side = if kind & 7 == 1 { top } else { side };
            if k.tint == 0 && far(side, k.side) {
                off.push(format!("{} (was {:?}, is {:?})", k.name.trim_start_matches("minecraft:"), side, k.side));
            }
        }
        eprintln!("the trees' blocks the old lookup coloured wrong ({}): {}", off.len(), off.join(", "));
    }

    /// The fills a strike over the target at the middle makes, the land answered from `stacks` where it has them
    /// (each a column bottom up, its top block at 64), the rest flat and bare; and the trees' and pieces' records.
    fn played_over(stacks: Vec<((i32, i32), Vec<&'static str>)>) -> (Vec<String>, Vec<(f32, Vec<String>)>) {
        let below = HU_BELOW;
        let kept: std::collections::HashMap<(i32, i32), Vec<&'static str>> = stacks.into_iter().collect();
        crate::columns::clear();
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let ev = plan(the_laser(), &target, true, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let answer = move |x: i32, z: i32, b: u32, _a: u32| -> Option<(i32, Vec<&'static str>)> {
            assert_eq!(b, below);
            match kept.get(&(x, z)) {
                Some(v) => Some((64 + (v.len() as i32 - below as i32), v.clone())),
                None => synth_column(x, z, b, 1, 65, 0.0, false),
            }
        };
        let p = crate::strike::sim::play(ev, HU_LEN, &answer);
        let fills = p.edits.iter().flat_map(|e| e.2.as_fills()).collect();
        let timed = p.edits.iter().map(|e| (e.0, e.2.as_fills())).collect();
        (fills, timed)
    }
    /// A village everywhere: a 7 by 7 house of spruce planks on a cobblestone footing, its roof of stairs and slabs, in
    /// every 12 by 12, bare flat land between.
    fn houses_everywhere(x: i32, z: i32) -> Option<(i32, Vec<&'static str>)> {
        let (i, j) = (x.rem_euclid(12), z.rem_euclid(12));
        if i > 6 || j > 6 {
            return synth_column(x, z, HU_BELOW, 1, 65, 0.0, false);
        }
        let edge = i == 0 || i == 6 || j == 0 || j == 6;
        let top: Vec<&'static str> = if edge {
            vec!["minecraft:cobblestone", "minecraft:spruce_planks", "minecraft:spruce_planks", "minecraft:spruce_planks", "minecraft:spruce_planks", "minecraft:spruce_stairs"]
        } else {
            vec!["minecraft:spruce_planks", "minecraft:air", "minecraft:air", "minecraft:air", "minecraft:air", "minecraft:spruce_slab"]
        };
        Some((65, stack(&top, "minecraft:dirt")))
    }
    /// A column bottom up: stone, its ground, what stands on it, air over it.
    fn stack(top: &[&'static str], ground: &'static str) -> Vec<&'static str> {
        let mut v = vec!["minecraft:stone"; HU_BELOW as usize - 1 - top.len()];
        v.push(ground);
        v.extend_from_slice(top);
        v.push("minecraft:air");
        v
    }
    /// The fills of column (x, z).
    fn at<'a>(fills: &'a [String], x: i32, z: i32) -> Vec<&'a String> {
        let p = format!("fill {x} ");
        fills.iter().filter(|f| f.starts_with(&p) && f.split_whitespace().nth(3) == Some(&z.to_string())).collect()
    }

    #[test]
    fn hurricane_takes_everything_that_should_go_and_leaves_the_water() {
        // a column of everything the wind should take standing on the land (in the eyewall's band), and one under a
        // pond's water
        let mut stacks: Vec<((i32, i32), Vec<&'static str>)> = Vec::new();
        let things = [
            &["minecraft:sugar_cane", "minecraft:sugar_cane", "minecraft:sugar_cane"][..],
            &["minecraft:oak_fence"],
            &["minecraft:oak_sapling"],
            &["minecraft:poppy"],
            &["minecraft:red_mushroom"],
            &["minecraft:snow"],
            &["minecraft:sweet_berry_bush"],
            &["minecraft:bamboo", "minecraft:bamboo", "minecraft:bamboo", "minecraft:bamboo"],
            &["minecraft:cactus", "minecraft:cactus"],
            &["minecraft:moss_carpet"],
            &["minecraft:tall_grass", "minecraft:tall_grass"],
            &["minecraft:wheat"],
            &["minecraft:pumpkin"],
            &["minecraft:torch"],
            &["minecraft:white_carpet"],
            &["minecraft:pink_petals"],
            &["minecraft:oak_log", "minecraft:oak_log", "minecraft:oak_log", "minecraft:bee_nest", "minecraft:oak_leaves", "minecraft:snow"],
            &["minecraft:mangrove_roots", "minecraft:mangrove_log", "minecraft:mangrove_leaves", "minecraft:vine"],
            &["minecraft:cherry_log", "minecraft:cherry_log", "minecraft:cherry_leaves", "minecraft:cherry_leaves"],
            &["minecraft:pale_oak_log", "minecraft:pale_oak_leaves", "minecraft:pale_hanging_moss"],
        ];
        for (i, t) in things.iter().enumerate() {
            stacks.push(((60 + i as i32, 0), stack(t, "minecraft:grass_block")));
        }
        stacks.push(((60, 5), stack(&["minecraft:water", "minecraft:seagrass", "minecraft:water", "minecraft:lily_pad"], "minecraft:sand")));
        let (fills, _) = played_over(stacks);
        let fills: Vec<String> = fills.into_iter().filter(|f| {
            let w: Vec<i32> = f.split_whitespace().skip(1).take(6).map(|v| v.parse().unwrap_or(0)).collect();
            w.len() == 6 && w[2] >= 0 && w[2] <= 5 && w[0] >= 60 && w[0] < 60 + things.len() as i32
        }).collect();
        // (every one of them taken, block by block: nothing left standing)
        for (i, t) in things.iter().enumerate() {
            let x = 60 + i as i32;
            for name in t.iter().filter(|n| !n.ends_with("mangrove_roots")) {
                assert!(fills.iter().any(|f| f.starts_with(&format!("fill {x} ")) && f.contains(&format!("replace {name} strict"))), "{name} at {x} left: {fills:?}");
            }
        }
        // (the water and the seagrass in it left, the lily pad on the pond taken)
        for f in &fills {
            for kept in ["water", "seagrass", "replaceable_by"] {
                assert!(!f.contains(&format!("replace minecraft:{kept}")) && !f.contains(&format!("replace #minecraft:{kept}")), "{f}");
            }
        }
        assert!(fills.iter().any(|f| f.contains("replace minecraft:lily_pad")));
    }

    #[test]
    fn hurricane_tears_a_house_apart_and_leaves_what_stays() {
        // a house in the strong wind (70-76 out, 7 by 7): cobblestone floor over dirt, oak plank walls four high with
        // glass in them and a door, a roof of stairs round its edge and slabs over it; inside a chest, a torch on the
        // floor and one on a wall
        let mut stacks: Vec<((i32, i32), Vec<&'static str>)> = Vec::new();
        let (x0, z0) = (70, -3);
        for i in 0..7 {
            for j in 0..7 {
                let (x, z) = (x0 + i, z0 + j);
                let edge = i == 0 || i == 6 || j == 0 || j == 6;
                let top: Vec<&'static str> = if edge {
                    if i == 0 && j == 3 {
                        vec!["minecraft:cobblestone", "minecraft:oak_door", "minecraft:oak_door", "minecraft:oak_planks", "minecraft:oak_planks", "minecraft:oak_stairs"]
                    } else if j == 0 && (i == 2 || i == 4) {
                        vec!["minecraft:cobblestone", "minecraft:oak_planks", "minecraft:glass", "minecraft:glass_pane", "minecraft:oak_planks", "minecraft:oak_stairs"]
                    } else {
                        vec!["minecraft:cobblestone", "minecraft:oak_planks", "minecraft:oak_planks", "minecraft:oak_planks", "minecraft:oak_planks", "minecraft:oak_stairs"]
                    }
                } else if (i, j) == (3, 3) {
                    vec!["minecraft:oak_planks", "minecraft:chest", "minecraft:air", "minecraft:air", "minecraft:air", "minecraft:oak_slab"]
                } else if (i, j) == (2, 4) {
                    vec!["minecraft:oak_planks", "minecraft:torch", "minecraft:air", "minecraft:air", "minecraft:air", "minecraft:oak_slab"]
                } else if (i, j) == (1, 2) {
                    vec!["minecraft:oak_planks", "minecraft:air", "minecraft:air", "minecraft:wall_torch", "minecraft:air", "minecraft:oak_slab"]
                } else {
                    vec!["minecraft:oak_planks", "minecraft:air", "minecraft:air", "minecraft:air", "minecraft:air", "minecraft:oak_slab"]
                };
                stacks.push(((x, z), stack(&top, "minecraft:dirt")));
            }
        }
        // and what stays, even in the strongest wind: what can't be broken, a barrel, a shulker box, a mod's block
        let stay = [
            &["minecraft:bedrock", "minecraft:bedrock"][..],
            &["minecraft:barrier"],
            &["minecraft:command_block"],
            &["minecraft:end_portal_frame"],
            &["minecraft:barrel"],
            &["minecraft:red_shulker_box"],
            &["somemod:strange_block"],
            // (a plank on a barrier: the plank taken, the barrier and all under it left)
            &["minecraft:barrier", "minecraft:oak_planks"],
        ];
        for (k, t) in stay.iter().enumerate() {
            stacks.push(((60 + k as i32, 10), stack(t, "minecraft:grass_block")));
        }
        let (fills, timed) = played_over(stacks);
        // (every block of it torn out, by its name: walls, glass, door, roof, floor and torches)
        let house: Vec<&String> = (0..7).flat_map(|i| (0..7).map(move |j| (x0 + i, z0 + j))).flat_map(|(x, z)| at(&fills, x, z)).collect();
        for name in ["oak_planks", "glass", "glass_pane", "oak_door", "oak_stairs", "oak_slab", "cobblestone", "torch", "wall_torch"] {
            assert!(house.iter().any(|f| f.ends_with(&format!("replace minecraft:{name} strict"))), "the house's {name} left standing: {house:?}");
        }
        // (every wall column stripped to its floor; the roof as the front reaches it, the walls after)
        for i in 0..7 {
            assert!(at(&fills, x0 + i, z0).iter().any(|f| f.contains("replace minecraft:oak_planks")), "wall at {}", x0 + i);
        }
        eprintln!("the house: {} fills; the roof's stairs at {:.2} s", house.len(), timed.iter().filter(|(_, f)| f.iter().any(|f| f.contains("oak_stairs"))).map(|e| e.0).fold(f32::MAX, f32::min));
        let when = |name: &str| timed.iter().filter(|(_, f)| f.iter().any(|f| f.contains(&format!(" {} ", z0)) && f.ends_with(&format!("replace minecraft:{name} strict")))).map(|e| e.0).fold(f32::MAX, f32::min);
        assert!(when("oak_stairs") + 0.5 < when("oak_planks"), "the roof at {} and the walls at {}", when("oak_stairs"), when("oak_planks"));
        // (the chest left with what is in it, and nothing under it touched)
        assert!(at(&fills, x0 + 3, z0 + 3).iter().all(|f| f.contains("replace minecraft:oak_slab")), "{:?}", at(&fills, x0 + 3, z0 + 3));
        assert!(!fills.iter().any(|f| f.contains("chest")));
        // (what stays stays; what stood on it goes)
        for f in &fills {
            for kept in ["bedrock", "barrier", "command_block", "end_portal_frame", "barrel", "shulker_box", "strange_block"] {
                assert!(!f.contains(kept), "{f}");
            }
        }
        for k in 0..stay.len() as i32 - 1 {
            assert!(at(&fills, 60 + k, 10).is_empty(), "{:?}", at(&fills, 60 + k, 10));
        }
        assert!(at(&fills, 60 + stay.len() as i32 - 1, 10).iter().any(|f| f.contains("replace minecraft:oak_planks")));
    }

    #[test]
    fn hurricane_lifts_pieces_of_buildings_whole() {
        // (a village's worth of houses round the eyewall: some torn off whole, as rigid groups, of a block that can
        // fall as one, lifted with their walls)
        crate::columns::clear();
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let mut ev = plan(the_laser(), &target, true, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let house = |x: i32, z: i32| houses_everywhere(x, z);
        let mut words: Vec<(u32, Vec<u32>)> = Vec::new();
        let mut n = 0.0f32;
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        while let Some((_, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &house),
                Act::Data { index: 0, value } => n = value,
                Act::Words { index, words: w } => words.push((index, w)),
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        let mut table = vec![0u32; HU_WORDS];
        for (i, w) in &words {
            let i = *i as usize;
            if i + w.len() <= table.len() {
                table[i..i + w.len()].copy_from_slice(w);
            }
        }
        let n = n as usize;
        eprintln!("{n} pieces of buildings lifted whole");
        assert!(n >= 5 && n <= HU_PIECES, "{n} pieces");
        let kinds = table[3] as usize;
        for k in 0..n {
            let w = &table[HU_T + HU_TW * k..HU_T + HU_TW * (k + 1)];
            let (x, z, t_up) = (f32::from_bits(w[0]), f32::from_bits(w[1]), f32::from_bits(w[3]));
            let r = f64::from(x).hypot(f64::from(z));
            assert!(r < 110.0 && w[4] & 31 == 0 && (w[4] >> 5) & 31 >= 3, "piece {k}: {r} {:x}", w[4]);
            let (wood, leaf) = ((w[5] & 0xFFFF) as usize, (w[5] >> 16) as usize);
            assert!(wood < kinds && leaf < kinds, "piece {k}: kinds {wood} {leaf} of {kinds}");
            // (lifted with its walls, after the front reaches it)
            assert!(f64::from(t_up) >= front_t(r.max(HU_R_IN)).unwrap() - 2.0, "{t_up} at {r}");
        }
        // (and played as the mod plays it, a village everywhere: the edits on time; its stages timed in
        // hurricane_no_stage_too_heavy_anywhere)
        crate::columns::clear();
        let ev = plan(the_laser(), &target, true, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let p = crate::strike::sim::play(ev, HU_LEN, &|x, z, _, _| house(x, z));
        let late = p.edits.iter().map(|e| e.0 - e.1).fold(0.0f32, f32::max);
        let runs: usize = p.edits.iter().map(|e| e.2.runs.len()).sum();
        eprintln!("a village: {} edits, {runs} runs, the latest {late:.2} s late", p.edits.len());
        assert!(late < 0.3, "an edit {late:.2} s late");
    }

    /// A strike over the target (0 64 0) played through, the land answered by `answer`: the pass's table at the end,
    /// and every edit with when it is due.
    #[test]
    fn hurricane_gives_trees_a_mix_of_fates_and_leaves_the_snapped_ones_stumps() {
        // (a dense wood: most trees shredded where they stand (no record), a few uprooted whole, some snapped at the
        // trunk (their stump of 1-4 logs left as real blocks, their record's foot on its top), some to break apart in
        // the air (no real landing of their own))
        let (table, edits) = table_and_edits(&|x, z, b, a| synth_column(x, z, b, a, 65, 0.0, true));
        let n = f32::from_bits(table[0]) as usize;
        let (mut whole, mut snapped, mut broken) = (0, 0, 0);
        let fills: Vec<String> = edits.iter().flat_map(|e| e.1.as_fills()).collect();
        for i in 0..n {
            let w = &table[HU_T + HU_TW * i..HU_T + HU_TW * (i + 1)];
            let f = |k: usize| f32::from_bits(w[k]);
            if w[4] & 31 == 0 {
                continue;
            }
            if f(6) < 1e8 {
                broken += 1;
                assert!(f(6) > f(3) && f(6) < HU_FLING as f32 && f(25) > 1e8, "tree {i}: breaks at {} (up at {})", f(6), f(3));
            } else if f(2) >= 1.0 {
                snapped += 1;
                // (its trunk's logs taken only over the stump)
                let (x, z, stump) = (f(0).floor() as i32, f(1).floor() as i32, f(2) as i32);
                let logs: Vec<&String> = fills.iter().filter(|e| e.starts_with(&format!("fill {x} ")) && e.contains(&format!(" {z} {x} ")) && e.contains("minecraft:air replace") && e.contains("_log")).collect();
                assert!(logs.iter().all(|e| e.split_whitespace().nth(2).unwrap().parse::<i32>().unwrap() >= 65 + stump), "tree {i}: its stump taken: {logs:?}");
            } else {
                whole += 1;
            }
        }
        eprintln!("{n} records: {whole} uprooted whole, {snapped} snapped, {broken} to break apart in the air");
        assert!(whole > 0 && snapped > 0 && broken > 0, "{whole} {snapped} {broken}");
        assert!(whole <= HU_WHOLE as usize && whole < snapped + broken);
    }

    fn table_and_edits(answer: &dyn Fn(i32, i32, u32, u32) -> Option<(i32, Vec<&'static str>)>) -> (Vec<u32>, Vec<(f32, Blocks)>) {
        crate::columns::clear();
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let mut ev = plan(the_laser(), &target, true, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let mut table = vec![0u32; HU_WORDS];
        let mut edits = Vec::new();
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| answer(x, z, below, above)),
                Act::Words { index, words } => {
                    let i = index as usize;
                    table[i..i + words.len()].copy_from_slice(&words);
                }
                Act::Data { index, value } => table[index as usize] = value.to_bits(),
                Act::Blocks(b) => edits.push((t, *b)),
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        (table, edits)
    }

    #[test]
    fn hurricane_lays_each_tree_down_where_the_pass_lays_it() {
        // (on wooded flat land: each flung tree's blocks laid as its words say it lands (the contract with the pass's
        // hu_tree_at): at t_land, on the real ground's top yl, lying along yaw, its foot cm back from where its middle
        // lands; its trunk logs along x or z)
        let (table, edits) = table_and_edits(&|x, z, b, a| synth_column(x, z, b, a, 65, 0.0, true));
        let n = f32::from_bits(table[0]) as usize;
        assert!(n > 40, "{n} trees");
        let laid: Vec<&(f32, Blocks)> = edits.iter().filter(|e| e.1.clear_of_player).collect();
        let mut checked = 0;
        for i in 0..n {
            let w = &table[HU_T + HU_TW * i..HU_T + HU_TW * (i + 1)];
            let f = |k: usize| f64::from(f32::from_bits(w[k]));
            let mut spans = [(31u8, 0u8); 49];
            for (c, sp) in spans.iter_mut().enumerate() {
                let v = (w[8 + c / 3] >> (10 * (c % 3))) & 1023;
                *sp = ((v & 31) as u8, (v >> 5) as u8);
            }
            let tr = TreeRec { x: f(0), z: f(1), gdy: f(2), t_up: f(3), trunk: (w[4] & 31) as u8, wood_bk: 0, leaf_bk: 0, wood: 0, leaf: 0, spans, t_land: f(25), yl: f(26), yaw: f(27), t_break: f(6) };
            if tr.t_up >= HU_FLING || tr.t_break < 1e8 {
                assert!(tr.t_land > 1e8);
                continue;
            }
            // (its fall: from where the pass flings it, its middle down to yl + 0.5 at t_land)
            let (pf, v) = tree_fling(&tr, i as u32, 37);
            let s = tr.t_land - HU_FLING;
            assert!((pf[1] + v[1] * s - 7.0 * s * s - (tr.yl + 0.5)).abs() < 2e-3, "tree {i}: lands at {} not {}", pf[1] + v[1] * s - 7.0 * s * s, tr.yl + 0.5);
            let d = [tr.yaw.cos(), tr.yaw.sin()];
            let h = v[0].hypot(v[2]);
            assert!((d[0] - v[0] / h).abs() < 1e-3 && (d[1] - v[2] / h).abs() < 1e-3, "tree {i}: yaw");
            // (flat land at 65, the ground the strike leaves: dug at most three, or over what it leaves standing (a stump, a
            // tree past the wind's reach) where it comes down on it)
            assert!(tr.yl <= 16.0 && tr.yl >= -3.0 && tr.yl.fract() == 0.0, "tree {i}: yl {}", tr.yl);
            // (its trunk's foot: the block at foot + d * 0.5)
            let cm = 0.6 * f64::from(tr.trunk.max(3));
            let m = [pf[0] + v[0] * s, pf[2] + v[2] * s];
            let foot = [m[0] - d[0] * cm, tr.yl + 0.5, m[1] - d[1] * cm];
            let b0 = [(0.5 + foot[0] + d[0] * 0.5).floor() as i32, 65 + foot[1].floor() as i32, (0.5 + foot[2] + d[1] * 0.5).floor() as i32];
            let axis = if d[0].abs() >= d[1].abs() { "[axis=x]" } else { "[axis=z]" };
            let at_land: Vec<String> = laid.iter().filter(|e| (e.0 - tr.t_land as f32).abs() < 0.06).flat_map(|e| e.1.as_fills()).collect();
            let want = format!("fill {} {} {} {} {} {} minecraft:oak_log{axis} replace minecraft:air strict", b0[0], b0[1], b0[2], b0[0], b0[1], b0[2]);
            let near = |f: &String| {
                let p: Vec<i32> = f.split_whitespace().skip(1).take(3).map(|v| v.parse().unwrap_or(0)).collect();
                f.contains("oak_log") && (p[0] - b0[0]).abs() <= 1 && (p[2] - b0[2]).abs() <= 1
            };
            assert!(at_land.iter().any(|f| *f == want || (f.starts_with(&format!("fill {} {} {} ", b0[0], b0[1], b0[2])) && f.contains(&format!("oak_log{axis}")))), "tree {i}: no {want} at {:.2} s: {:?}", tr.t_land, at_land.iter().filter(|f| near(f)).collect::<Vec<_>>());
            assert!(at_land.iter().filter(|f| f.contains("oak_leaves[persistent=true]")).count() > 3, "tree {i}: its leaves");
            checked += 1;
        }
        eprintln!("{checked} trees laid down where they land");
        assert!(checked > 30);
        // (every block laid only into air)
        for e in &laid {
            for f in e.1.as_fills() {
                assert!(f.ends_with("replace minecraft:air strict"), "{f}");
            }
        }
    }

    #[test]
    fn hurricane_rubble_comes_down_on_the_ground_never_in_water_or_the_player() {
        // (flat land, a pond east of the middle: some two thousand blocks come down, one a column, each on the ground's
        // top as the strike leaves it, from what flew round there, none into the pond)
        let pond = |x: i32, z: i32| (60..140).contains(&x) && (-40..40).contains(&z);
        let (_, edits) = table_and_edits(&|x, z, b, a| {
            if pond(x, z) {
                let mut v = vec!["minecraft:sand"; b as usize - 3];
                v.extend_from_slice(&["minecraft:water", "minecraft:water", "minecraft:water", "minecraft:air"]);
                return Some((65, v));
            }
            synth_column(x, z, b, a, 65, 0.0, false)
        });
        let rubble: Vec<(f32, String)> = edits.iter().filter(|e| e.1.clear_of_player).flat_map(|e| e.1.as_fills().into_iter().map(move |f| (e.0, f))).collect();
        eprintln!("{} blocks of rubble", rubble.len());
        assert!(rubble.len() > 1500 && rubble.len() <= HU_RUBBLE, "{}", rubble.len());
        let mut cols = std::collections::HashSet::new();
        for (t, f) in &rubble {
            let p: Vec<i32> = f.split_whitespace().skip(1).take(6).map(|v| v.parse().unwrap_or(0)).collect();
            assert!(cols.insert((p[0], p[2])), "two in one column: {f}");
            assert!(!pond(p[0], p[2]), "into the pond: {f}");
            // (on bare flat land, its top at 64: dug at most three, laid on what is left)
            assert!((61..=65).contains(&p[1]), "{f}");
            assert!(f.ends_with("replace minecraft:air strict"), "{f}");
            assert!(*t >= HU_FLING as f32 && *t < HU_FLING as f32 + 8.0, "{t}");
            let r = (f64::from(p[0]) + 0.5).hypot(f64::from(p[2]) + 0.5);
            assert!(r > HU_RING0 && r < 260.0, "{r}");
        }
        // (and none ever where the player is: the runs in their body left out as the edit is made)
        let b = &edits.iter().find(|e| e.1.clear_of_player && !e.1.runs.is_empty()).unwrap().1;
        let r = &b.runs[0];
        let feet = [f64::from(r.x) + 0.5, f64::from(r.y) - 1.0, f64::from(r.z) + 0.5];
        assert!(crate::strike::in_player(r.x, r.z, r.y, r.y, feet));
        assert_eq!(b.edit_clear_of(feet).runs.len() + 1, b.runs.len());
        assert_eq!(b.edit_clear_of([1e6, 0.0, 1e6]).runs.len(), b.runs.len());
        assert!(!crate::strike::in_player(r.x + 1, r.z, r.y, r.y, feet) && !crate::strike::in_player(r.x, r.z, r.y + 2, r.y + 2, feet));
    }

    #[test]
    fn hurricane_stages_are_light() {
        // (each stage's work, on the meter, well under a tick's, on wooded hills: the tests' stages reset it as on a
        // tick of their own)
        crate::columns::clear();
        let target = Target { block: [-1041, 64, 860], point: [-1040.5, 65.0, 860.5] };
        let mut ev = plan(the_laser(), &target, true, "minecraft:overworld", 19.0, [-1040.5, 70.0, 1160.5], 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut worst = (0u64, 0.0f32, 0usize);
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| synth_column(x + 1041, z - 860, below, above, 65, 30.0, true)),
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                    let more = job();
                    let made: u64 = more.iter().map(|(_, a)| if let Act::Blocks(b) = a { 1_000 * b.runs.len() as u64 } else { 1_000 }).sum();
                    let spent = crate::meter::spent() + made;
                    if spent > worst.0 {
                        worst = (spent, t, more.len());
                    }
                    ev.extend(more);
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        eprintln!("heaviest stage: {:.2}M at {:.2} s ({} acts)", worst.0 as f64 / 1e6, worst.1, worst.2);
        assert!(worst.0 < crate::meter::SOFT * 3 / 4, "a stage of {:.2}M at {:.2} s", worst.0 as f64 / 1e6, worst.1);
    }

    /// (timed: run it on its own, as the Nuke's, `cargo test --release hurricane_no_stage -- --ignored`)
    #[test]
    #[ignore]
    fn hurricane_no_stage_too_heavy_anywhere() {
        // (timed, natively: no stage over 1.3 ms wherever it strikes: flat, wooded hills, steep bare hills, open land)
        if cfg!(debug_assertions) {
            return;
        }
        for (hills, forest) in [(0.0, true), (30.0, true), (60.0, false), (0.0, false)] {
            let mut best: Vec<f64> = Vec::new();
            for _ in 0..2 {
                let p = played(true, [10.5, 66.0, 497.5], hills, forest);
                let ms: Vec<f64> = p.stages.iter().map(|s| s.2).collect();
                best = if best.is_empty() { ms } else { best.iter().zip(&ms).map(|(a, b)| a.min(*b)).collect() };
            }
            let worst = best.iter().copied().fold(0.0, f64::max);
            eprintln!("hills {hills} forest {forest}: {} stages, heaviest {worst:.2} ms", best.len());
            assert!(worst < 1.3, "hills {hills}: a stage took {worst:.2} ms");
        }
        // (and over a village everywhere: buildings torn apart, pieces of them lifted whole and laid down)
        let mut best: Vec<f64> = Vec::new();
        for _ in 0..2 {
            crate::columns::clear();
            let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
            let ev = plan(the_laser(), &target, true, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
            let p = crate::strike::sim::play(ev, HU_LEN, &|x, z, _, _| houses_everywhere(x, z));
            let ms: Vec<f64> = p.stages.iter().map(|s| s.2).collect();
            best = if best.is_empty() || best.len() != ms.len() { ms } else { best.iter().zip(&ms).map(|(a, b)| a.min(*b)).collect() };
        }
        let worst = best.iter().copied().fold(0.0, f64::max);
        eprintln!("a village: {} stages, heaviest {worst:.2} ms", best.len());
        assert!(worst < 1.3, "a village: a stage took {worst:.2} ms");
    }
}

/// The plan as it is made on the fire tick stays light (`meter`): what is heavy waits for stages of its own.
#[cfg(test)]
#[test]
fn hu_fire_cost() {
    let laser = crate::lasers::LASERS.iter().find(|l| l.key == "hurricane").unwrap();
    let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
    for terrain in [false, true] {
        crate::meter::reset();
        let ev = crate::strike::plan(laser, &target, terrain, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let spent = crate::meter::spent();
        eprintln!("terrain {terrain}: plan {:.2}M on the meter, {} acts", spent as f64 / 1e6, ev.len());
        assert!(spent < 2_000_000, "the plan took {:.2}M", spent as f64 / 1e6);
    }
}
