//! The Colossi's plan: five stone giants rise out of the earth in a ring 300 out round the target, each slams a hammer
//! into the ground in front of it, one after another, then all five at once; the green cracks their blows opened run in jolts to the middle,
//! meet there and it all goes up; the giants are left broken, and converted into blocks.
//!
//! The giants and the hammer are the Tripo models, run through the converter (model2mc, github.com/Stink-O/model2mc):
//! `tools/colossi_assets.py` packs their display meshes for the pass (`mod/colossi/view.bin`, read from `mod_data`) and
//! the five broken statues as blocks (`mod/colossi/statues.bin`, voxelised with `--damage-seed`, turned to face the middle).
//! The pass (shaders/colossi.wgsl) draws the meshes and cuts them with the same seeded damage function, so what stands
//! when the display is gone is what it showed. Keep the CL_* times here and the pass's in step.
//!
//! Timeline (CL_LEN 34 s): 0-7.5 s the giants rise; each stamps a foot 3.2 s before its blow (a thud, a small shake),
//! and the hammers come down one after another (`slam1`: 11 s + 0.6 s a giant; a blast and a shake at each), then all
//! at once at SLAM2 (18 s), the cracks lunging on to the middle (T_BEAM0); at 20 s they meet and it goes up (CL_HIT) and a wave runs out at CL_WAVE blocks a
//! second; the crater is dug and the land scorched behind it; from 25 s (T_SWEEP0, 0.3 s apart), as they draw themselves up, a glowing line
//! sweeps down each giant over CL_SWEEP seconds and the real blocks take the place of what it has passed.
//!
//! The land (terrain on only): the chunks within 100 are forceloaded; the land round each giant is torn up as it rises, from
//! its feet out (`hv_setup`: cleared of what grows, broken, cracked, the earth it heaves up heaped on it); at the blast the target's mobs die, a crater ~320 across and ~62 deep is dug and lined, the land is scorched out to 60 and
//! the trees and plants cleared to 70; the statues go in slab by slab behind each sweep line.
use super::{Act, Blocks, Plan, Target, falloff, sound_from};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::OnceLock;

pub(crate) const CL_LEN: f32 = 34.0;
/// `mod_data`'s layout (tools/colossi_rig.py's, colossi.wgsl's): the five giants' records and the rigs.
const REC0: usize = 640;
const REC: usize = 64;
const RIG0: usize = 448;
const RIGS: usize = 96;
const MESH0: usize = 16;
/// How far out the giants stand, and the scale they are (CL_K, shaders/colossi.wgsl: 4.4 times the 50 blocks of the first
/// design's mesh): about 220 blocks, half the Planet Killer's towers and the most a block statue can be under the build limit.
const CL_K: f64 = 4.4;
const RING_R: f64 = 68.0 * CL_K;
const RING_DEG: [f64; 5] = [-90.0, -18.0, 54.0, 126.0, 198.0];
const T_RISE0: f32 = 0.2;
const T_RISE_STEP: f32 = 0.2;
/// The first giant's hammer hits the ground here, the others `SLAM_STEP` apart round the ring (`slam1`); then all five lift
/// again and strike together at `SLAM2`; from `T_BEAM0` the cracks run the rest of the way to the middle in five jolts (the pass's
/// `cl_run`) and meet at `CL_HIT`.
const SLAM0: f32 = 11.0;
const SLAM_STEP: f32 = 0.6;
const SLAM2: f32 = 18.0;
const T_BEAM0: f32 = 18.0;
const CL_HIT: f32 = 20.0;
/// The blast's light reaches the hammer heads and starts up each hammer (the pass's `CL_CHARGE`).
const CHARGE: f32 = 20.9;
/// The first giant's hammer and arms burst; each later giant `BURST_STEP` after (the pass's `CL_BURST`).
const BURST: f32 = 22.4;
const BURST_STEP: f32 = 0.15;
const CL_WAVE: f64 = 55.0 * CL_K;
const T_SWEEP0: f32 = 25.0;
const T_SWEEP_STEP: f32 = 0.3;
const CL_SWEEP: f32 = 4.5;
/// How far the land is forceloaded, and how far the blast kills mobs.
const LOAD_R: i32 = 400;
const KILL_R: i32 = 470;
const CRATER_R: f64 = 36.0 * CL_K;
const CRATER_D: f64 = 14.0 * CL_K;
/// How far out the trees are at least felled or snapped (the blast field, `BD_*`, takes them; a bound for the tests).
const TREE_R: f64 = 70.0 * CL_K;

static VIEW: &[u8] = include_bytes!("../../colossi/view.bin");
static STATUES: &[u8] = include_bytes!("../../colossi/statues.bin");

/// One of the five giants as `tools/colossi_assets.py` packed it.
pub(crate) struct Statue {
    pub design: u8,
    pub mirror: bool,
    pub height: u16,
    pub seed: u32,
    /// The converter's yaw in radians (negated for a mirrored one: its mirror comes after its turn).
    pub yaw: f32,
    pub grid: [u16; 3],
    pub cuts: u16,
    pub spec: [f32; 4],
    /// Where the display mesh lies over the blocks (see the assets tool).
    pub b: [f32; 3],
    /// The blocks' own grid, crouched (`STATUE_POSE` in tools/colossi_assets.py, tools/colossi_pose.py): its size, and where
    /// its corner lies from the standing grid's (`grid`, `b`: the pass's damage and sweep read those).
    pub pgrid: [u16; 3],
    pub pshift: [i16; 3],
    /// The kneel the pass sinks the giant into to stand over its blocks (record words 48-62).
    pub pose: [f32; 15],
    /// The block states; index 0 is air.
    pub palette: Vec<&'static str>,
    /// Runs of (palette index u8, length u32), five bytes each, in x + z * X + y * X * Z order: left in the file's bytes and
    /// read a stage at a time (all five statues' are half a million runs, which a single tick could not read).
    runs: &'static [u8],
}

struct Reader<'a>(&'a [u8], usize);
impl Reader<'_> {
    fn bytes(&mut self, n: usize) -> &[u8] {
        let s = &self.0[self.1..self.1 + n];
        self.1 += n;
        s
    }
    fn u8(&mut self) -> u8 {
        self.bytes(1)[0]
    }
    fn u16(&mut self) -> u16 {
        u16::from_le_bytes(self.bytes(2).try_into().unwrap())
    }
    fn u32(&mut self) -> u32 {
        u32::from_le_bytes(self.bytes(4).try_into().unwrap())
    }
    fn f32(&mut self) -> f32 {
        f32::from_bits(self.u32())
    }
}

/// The five statues, read once (their block names are kept for the life of the mod).
pub(crate) fn statues() -> &'static [Statue] {
    static CACHE: OnceLock<Vec<Statue>> = OnceLock::new();
    CACHE.get_or_init(|| {
        let mut r = Reader(STATUES, 0);
        assert_eq!(r.bytes(4), b"CLST");
        let n = r.u32();
        (0..n)
            .map(|_| {
                let (design, mirror, height, seed, yaw, npal) = (r.u8(), r.u8() != 0, r.u16(), r.u32(), r.f32(), r.u16());
                let grid = [r.u16(), r.u16(), r.u16()];
                let cuts = r.u16();
                let spec = [r.f32(), r.f32(), r.f32(), r.f32()];
                let _ = r.f32();
                let b = [r.f32(), r.f32(), r.f32()];
                let pgrid = [r.u16(), r.u16(), r.u16()];
                let pshift = [r.u16() as i16, r.u16() as i16, r.u16() as i16];
                let pose = std::array::from_fn(|_| r.f32());
                let palette = (0..npal)
                    .map(|_| {
                        let l = usize::from(r.u8());
                        let s: &'static str = Box::leak(String::from_utf8(r.bytes(l).to_vec()).unwrap().into_boxed_str());
                        s
                    })
                    .collect();
                let m = r.u32() as usize;
                let runs = &STATUES[r.1..r.1 + 5 * m];
                r.1 += 5 * m;
                Statue { design, mirror, height, seed, yaw: yaw.to_radians(), grid, cuts, spec, b, pgrid, pshift, pose, palette, runs }
            })
            .collect()
    })
}

/// A statue's blocks: (column x + z * X, y, palette index) in the order the runs give them (y rising).
struct Cells {
    v: Vec<(u32, u16, u8)>,
}

/// A statue's blocks sorted for the world: by the chunk column they fall in, then by their column in it, then y rising (so a
/// column's blocks of one kind one over another are one run), and each chunk's cells, the chunk with the highest block first.
struct Cols {
    v: Vec<(u32, u16, u8)>,
    groups: Vec<(usize, usize)>,
}

impl Cells {
    /// The blocks by chunk column, for a statue whose grid's corner is at (ox, oz) and `xs` wide, `zs` deep: a counting sort
    /// (stable, so y stays rising in each column), the work of a stage of its own.
    fn by_chunk(&self, ox: i32, oz: i32, xs: u32, zs: u32) -> Cols {
        let (cx0, cz0) = (ox >> 4, oz >> 4);
        let ncx = (((ox + xs as i32 - 1) >> 4) - cx0 + 1) as usize;
        let ncz = (((oz + zs as i32 - 1) >> 4) - cz0 + 1) as usize;
        let key = |col: u32| {
            let (x, z) = (ox + (col % xs) as i32, oz + (col / xs) as i32);
            (((x >> 4) - cx0) as usize + ((z >> 4) - cz0) as usize * ncx) * 256 + (x & 15) as usize + (z & 15) as usize * 16
        };
        let nk = ncx * ncz * 256;
        let mut start = vec![0usize; nk + 1];
        for c in &self.v {
            start[key(c.0) + 1] += 1;
        }
        for k in 0..nk {
            start[k + 1] += start[k];
        }
        let mut at = start.clone();
        let mut v = vec![(0u32, 0u16, 0u8); self.v.len()];
        for c in &self.v {
            let k = key(c.0);
            v[at[k]] = *c;
            at[k] += 1;
        }
        let mut groups: Vec<(u16, usize, usize)> = (0..ncx * ncz)
            .map(|ci| (start[ci * 256], start[ci * 256 + 256]))
            .filter(|(a, z)| z > a)
            .map(|(a, z)| (v[a..z].iter().map(|c| c.1).max().unwrap_or(0), a, z))
            .collect();
        groups.sort_by(|a, b| b.0.cmp(&a.0));
        // (what it really costs, measured in the soak: some 170 a cell)
        crate::meter::spend(180 * self.v.len() as u64 + 8 * nk as u64);
        Cols { v, groups: groups.into_iter().map(|(_, a, z)| (a, z)).collect() }
    }
}

impl Statue {
    fn run(&self, i: usize) -> (u8, u32) {
        let b = &self.runs[5 * i..5 * i + 5];
        (b[0], u32::from_le_bytes([b[1], b[2], b[3], b[4]]))
    }
    fn nruns(&self) -> usize {
        self.runs.len() / 5
    }
    /// The blocks as `Cells`: the non-air cells of the runs, worked out without ever holding the whole grid (a giant's grid is
    /// millions of cells, a few tens of thousands of them blocks).
    fn cells(&self) -> Cells {
        let [xs, _, zs] = self.pgrid.map(u32::from);
        let layer = xs * zs;
        let mut v = Vec::new();
        let mut pos = 0u32;
        for k in 0..self.nruns() {
            let (id, n) = self.run(k);
            if id != 0 {
                for i in pos..pos + n {
                    v.push((i % layer, (i / layer) as u16, id));
                }
            }
            pos += n;
        }
        crate::meter::spend(30 * v.len() as u64 + 40 * self.nruns() as u64);
        Cells { v }
    }
}

/// Where giant `g`'s grid has its corner (its lowest x and z), in the world.
fn corner(t: &Target, g: usize, st: &Statue) -> (i32, i32) {
    let th = RING_DEG[g].to_radians();
    let cx = f64::from(t.block[0]) + 0.5 + RING_R * th.cos();
    let cz = f64::from(t.block[2]) + 0.5 + RING_R * th.sin();
    ((cx - f64::from(st.grid[0]) / 2.0).round() as i32, (cz - f64::from(st.grid[2]) / 2.0).round() as i32)
}
/// The column of its middle, whose ground it stands on.
fn middle(t: &Target, g: usize, st: &Statue) -> (i32, i32) {
    let (ox, oz) = corner(t, g, st);
    (ox + i32::from(st.grid[0]) / 2, oz + i32::from(st.grid[2]) / 2)
}

fn hash(x: i32, z: i32, s: u32) -> f32 {
    let mut h = (x as u32).wrapping_mul(0x8DA6_B343) ^ (z as u32).wrapping_mul(0xD816_3841) ^ s.wrapping_mul(0xCB1A_B31F);
    h ^= h >> 16;
    h = h.wrapping_mul(0x7FEB_352D);
    h ^= h >> 15;
    h = h.wrapping_mul(0x846C_A68B);
    h ^= h >> 16;
    h as f32 * (1.0 / 4_294_967_296.0)
}

/// A swing's length in seconds, from the hammer hanging at the top to the blow: heavy, and a little different for each giant.
/// (slow for their size: the pass holds it to what each wind-up leaves room for, `cl_pose`'s sw)
fn swing_seconds(g: usize) -> f32 {
    1.6 + 0.15 * hash(g as i32, 5, 3)
}
/// When giant g's hammer first hits the ground: one after another round the ring, a little off the beat.
fn slam1(g: usize) -> f32 {
    SLAM0 + SLAM_STEP * g as f32 + 0.12 * (hash(g as i32, 7, 3) - 0.5)
}
/// Each giant's way of moving, so no two copy each other (the pass's `cl_pose` reads them, words 26-33): how far ahead of
/// its blows it starts heaving the hammer up (a scale on the wind-up, from its stamp to the blow: early and holding it
/// long, or late and hurried), how deep it crouches, how far it arches under the hammer (and how high it holds it), how far
/// it turns into the swing, its posture (hunched > 0, upright < 0), its head turned off the middle (radians), how restless
/// its weight is, and how hard it reacts (to the blast, and how soon it looks up at the cracks). Five characters, dealt round
/// the ring differently each strike.
const CHARACTER: [[f32; 8]; 5] = [
    // eager: early, deep, twisting hard, never still, flinches
    [1.25, 1.18, 1.1, 1.4, 0.45, 0.0, 1.8, 1.35],
    // stiff: late and short, upright, barely turns, still
    [0.78, 0.82, 0.6, 0.55, -0.7, 0.05, 0.45, 0.7],
    // showy: arches far back, hammer held high, head off to one side
    [1.05, 1.0, 1.5, 1.15, -0.25, -0.16, 1.0, 1.05],
    // brute: hunched, the deepest squat, slow to react
    [1.12, 1.25, 0.85, 0.8, 0.95, 0.0, 0.75, 0.75],
    // wary: a little late, head turned the other way, shifting its weight
    [0.9, 0.95, 1.0, 1.0, 0.15, 0.2, 1.4, 1.2],
];
/// The combined blow's roll: when each slot's hammer lands before `SLAM2`, 0.3 s apart, so its five blows are heard as
/// five, each its own. Every blow is heard as it lands, never late by the distance, so the gaps
/// the player hears are these.
const ROLL: [f32; 5] = [-1.2, -0.9, -0.6, -0.3, 0.0];
/// Which giant takes each slot of the roll: the strike's own deal (a factorial number's permutation of the five).
fn slam2_order(t: &Target) -> [usize; 5] {
    let mut k = (hash(t.block[0], t.block[2], 43) * 120.0) as usize;
    let mut left: Vec<usize> = (0..5).collect();
    let mut order = [0usize; 5];
    for (i, o) in order.iter_mut().enumerate() {
        let f = [24, 6, 2, 1, 1][i];
        *o = left.remove((k / f) % left.len());
        k %= f;
    }
    order
}
/// When giant g's hammer comes down in the blow all five make together: not on one frame but in a ragged roll over about
/// a second and a quarter, in its own order each strike (heard as five hits), the last at `SLAM2` (the
/// cracks lunge on from there, the pass's `cl_run`).
fn slam2(t: &Target, g: usize) -> f32 {
    let slot = slam2_order(t).iter().position(|&o| o == g).unwrap_or(4);
    let jit = if slot == 4 { 0.0 } else { 0.04 * (hash(g as i32, 17, t.block[0] as u32) - 0.5) };
    SLAM2 + ROLL[slot] + jit
}
fn character(t: &Target, g: usize) -> [f32; 8] {
    let deal = (hash(t.block[0], t.block[2], 41) * 5.0) as usize;
    CHARACTER[(g + deal) % 5]
}
/// The wind-up's scale before each of giant g's blows (`CHARACTER`'s first, kept short enough that it never starts before
/// the giant is up, or before its first blow has landed).
fn leads(t: &Target, g: usize) -> [f32; 2] {
    let l = character(t, g)[0];
    let up = T_RISE0 + T_RISE_STEP * g as f32 + CL_RISE_S;
    // (the first may begin as its head comes up, the last 0.4 s of its rise: the time it needs to be slow and heavy)
    [l.min((slam1(g) - up + 0.4) / 3.75).max(0.7), l.min((slam2(t, g) - slam1(g) - 0.7) / 3.75).max(0.7)]
}
/// Seconds a giant takes to come up (the pass's `CL_RISE`).
const CL_RISE_S: f32 = 6.5;
/// How far in front of its pelvis a giant's hammer comes down, in its mesh's units (50 a giant's height).
const SLAM_AHEAD: f64 = 40.0;
/// How tall the hammer is beside its giant's 50.
const HAMMER_TALL: f64 = 40.0;

/// How far the giants' feet stand sunk in the land, blocks (about half a foot's height: they stand in the ground, not on it).
const BURY: i32 = 9;

/// Where giant g's hammer comes down, x and z from the target block's middle: straight in front of its pelvis.
fn slam_point(t: &Target, g: usize, st: &Statue) -> [f64; 2] {
    let rig = pose::Rig::read(usize::from(st.design));
    let (ax, az) = (f64::from(t.block[0]) + 0.5, f64::from(t.block[2]) + 0.5);
    let (ox, oz) = corner(t, g, st);
    let (yaw, mirror, sc) = (f64::from(st.yaw), if st.mirror { -1.0 } else { 1.0 }, f64::from(st.height) / 50.0);
    let (s, c) = yaw.sin_cos();
    let (jx, jz) = (rig.j[0][0], rig.j[0][2] + SLAM_AHEAD);
    [
        f64::from(ox) - ax + f64::from(st.b[0]) + mirror * sc * (c * jx + s * jz),
        f64::from(oz) - az + f64::from(st.b[2]) + sc * (-s * jx + c * jz),
    ]
}
/// The column of the land the hammer comes down on.
fn slam_column(t: &Target, g: usize, st: &Statue) -> (i32, i32) {
    let [x, z] = slam_point(t, g, st);
    (t.block[0] + (x + 0.5).floor() as i32, t.block[2] + (z + 0.5).floor() as i32)
}

/// What the pass reads from `mod_data` (the layout is in shaders/colossi.wgsl): the packed meshes, then this strike's
/// five giants placed round the target, standing on `ground` (their middle columns' ground, or the target's).
pub(crate) fn table_words(t: &Target, ground: [i32; 5]) -> Vec<u32> {
    let mut w: Vec<u32> = VIEW.chunks_exact(4).map(|c| u32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect();
    crate::meter::spend(w.len() as u64 * 4);
    let (ax, az) = (f64::from(t.block[0]) + 0.5, f64::from(t.block[2]) + 0.5);
    let f = |v: f32| v.to_bits();
    w[3] = 3;
    w[4] = f((t.block[1] + 1) as f32);
    w[5] = w[4];
    for (g, st) in statues().iter().enumerate() {
        let base = REC0 + REC * g;
        let (ox, oz) = corner(t, g, st);
        let gf = g as f32;
        let ts = slam1(g);
        let rec = [
            u32::from(st.design),
            f(if st.mirror { -1.0 } else { 1.0 }),
            f(f32::from(st.height) / 50.0),
            f(st.yaw),
            f((f64::from(ox) - ax) as f32 + st.b[0]),
            f((ground[g] - BURY) as f32),
            f((f64::from(oz) - az) as f32 + st.b[2]),
            st.seed,
            f(0.85 + 0.3 * hash(g as i32, 3, 9)),
            f(T_RISE0 + T_RISE_STEP * gf),
            f(ts),
            f(T_SWEEP0 + T_SWEEP_STEP * gf),
            f(f32::from(st.grid[0])),
            f(f32::from(st.grid[1])),
            f(f32::from(st.grid[2])),
            u32::from(st.cuts),
            f(st.spec[0]),
            f(st.spec[1]),
            f(st.spec[2]),
            f(st.spec[3]),
            f(st.b[0]),
            f(st.b[1]),
            f(st.b[2]),
        ];
        w[base..base + rec.len()].copy_from_slice(&rec);
        for (i, v) in pose_words(t, g, st, ground[g]).into_iter().enumerate() {
            w[base + 23 + i] = v;
        }
        for (i, v) in st.pose.iter().enumerate() {
            w[base + 48 + i] = v.to_bits();
        }
    }
    w
}

/// The words 23 on of giant g's record (the pass reads them; see colossi.wgsl's header): when all five strike together, its
/// swing's length, its variation, the hammer's scale over the giant's and where its hammer comes down (the land's height there
/// `ground`, till the survey says).
fn pose_words(t: &Target, g: usize, st: &Statue, ground: i32) -> Vec<u32> {
    let rig = pose::Rig::read(usize::from(st.design));
    let [sx, sz] = slam_point(t, g, st);
    let mut w = vec![0u32; 25];
    w[0] = slam2(t, g).to_bits();
    w[1] = swing_seconds(g).to_bits();
    w[2] = hash(g as i32, 11, 3).to_bits();
    let ch = character(t, g);
    let ld = leads(t, g);
    w[3] = ld[0].to_bits();
    w[4] = ld[1].to_bits();
    for k in 1..8 {
        w[4 + k] = ch[k].to_bits();
    }
    w[13] = ((HAMMER_TALL / rig.hammer_ext[1]) as f32).to_bits();
    w[21] = (sx as f32).to_bits();
    w[22] = (ground as f32).to_bits();
    w[23] = (sz as f32).to_bits();
    w[24] = BURST_MASK[g];
    w
}

/// Which pieces of each giant burst with its hammer (bit k piece k: 3 and 5 the upper arms, 4 and 6 the forearms). The
/// statues are made without them (`GIANTS` in tools/colossi_assets.py holds the same masks).
const BURST_MASK: [u32; 5] = [0x50, 0x58, 0x78, 0x70, 0x50];

/// The designs' rigs, read from the packed meshes.
mod pose {
    pub type V = [f64; 3];
    pub struct Rig {
        pub j: [V; 15],
        pub hammer_ext: V,
    }
    fn word(i: usize) -> f64 {
        let b = &super::VIEW[4 * i..4 * i + 4];
        f64::from(f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
    impl Rig {
        pub fn read(design: usize) -> Rig {
            let base = super::RIG0 + super::RIGS * design;
            let j = std::array::from_fn(|n| [word(base + 3 * n), word(base + 3 * n + 1), word(base + 3 * n + 2)]);
            let hb = super::MESH0 + 16 * 26;
            Rig { j, hammer_ext: [word(hb + 7), word(hb + 8), word(hb + 9)] }
        }
    }
}

/// Forceloads for the chunks within `LOAD_R` of the target: a row of chunks each.
fn load_rows(t: &Target) -> Vec<[i32; 4]> {
    let (x0, x1) = ((t.block[0] - LOAD_R) >> 4, (t.block[0] + LOAD_R) >> 4);
    let (z0, z1) = ((t.block[2] - LOAD_R) >> 4, (t.block[2] + LOAD_R) >> 4);
    (z0..=z1).map(|cz| [x0 * 16, cz * 16, x1 * 16 + 15, cz * 16 + 15]).collect()
}

/// The ground under giant `g`, as the survey answered it (the target's, if it didn't).
struct Grounds {
    y: RefCell<[i32; 5]>,
    done: RefCell<bool>,
}

fn survey(q: &mut Plan, tag: u32, t: Rc<Target>, gr: Rc<Grounds>, at: f32, tries: u32) {
    if !crate::ground::ready(tag) && tries < 40 {
        q.soon(at + 0.1, move |q| survey(q, tag, t, gr, at + 0.1, tries + 1));
        return;
    }
    let mut y = [t.block[1] + 1; 5];
    for (g, st) in statues().iter().enumerate() {
        let (cx, cz) = middle(&t, g, st);
        if let Some(h) = crate::ground::at(cx, cz) {
            y[g] = h;
        }
        // (the ground's height under it, and where its hammer comes down)
        q.ev.push((at, Act::Words { index: (REC0 + REC * g + 5) as u32, words: vec![((y[g] - BURY) as f32).to_bits()] }));
        let (sx, sz) = slam_column(&t, g, st);
        let sy = crate::ground::at(sx, sz).unwrap_or(y[g]);
        q.ev.push((at, Act::Words { index: (REC0 + REC * g + 45) as u32, words: vec![(sy as f32).to_bits()] }));
    }
    *gr.y.borrow_mut() = y;
    *gr.done.borrow_mut() = true;
}

/// The pass's `cl_unit`: a number in 0..1 of a seed and three whole numbers.
fn unit(seed: u32, a: i32, b: i32, c: i32) -> f32 {
    let mut h = seed ^ (a as u32).wrapping_mul(0x8DA6_B343) ^ (b as u32).wrapping_mul(0xD816_3841) ^ (c as u32).wrapping_mul(0xCB1A_B31F);
    h ^= h >> 16;
    h = h.wrapping_mul(0x7FEB_352D);
    h ^= h >> 15;
    h = h.wrapping_mul(0x846C_A68B);
    h ^= h >> 16;
    h as f32 * (1.0 / 4_294_967_296.0)
}

fn ss(a: f32, b: f32, x: f32) -> f32 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}
/// The pass's `cl_n2`: value noise on `unit`'s lattice (layer 5), straight lines between.
fn n2(seed: u32, x: f32, z: f32) -> f32 {
    let (fx, fz) = (x.floor(), z.floor());
    let (ux, uz, ix, iz) = (x - fx, z - fz, fx as i32, fz as i32);
    let m = |a: f32, b: f32, u: f32| a + (b - a) * u;
    m(m(unit(seed, ix, 5, iz), unit(seed, ix + 1, 5, iz), ux), m(unit(seed, ix, 5, iz + 1), unit(seed, ix + 1, 5, iz + 1), ux), uz)
}
/// The pass's `cl_vs`: value noise on `unit`'s lattice (layer 6), eased between (the cracks the giants open as they rise).
fn vs(seed: u32, x: f32, z: f32) -> f32 {
    let (fx, fz) = (x.floor(), z.floor());
    let (ux, uz, ix, iz) = (x - fx, z - fz, fx as i32, fz as i32);
    let (ux, uz) = (ux * ux * (3.0 - 2.0 * ux), uz * uz * (3.0 - 2.0 * uz));
    let m = |a: f32, b: f32, u: f32| a + (b - a) * u;
    m(m(unit(seed, ix, 6, iz), unit(seed, ix + 1, 6, iz), ux), m(unit(seed, ix, 6, iz + 1), unit(seed, ix + 1, 6, iz + 1), ux), uz)
}
fn boxd(px: f32, pz: f32, bx: f32, bz: f32) -> f32 {
    let (dx, dz) = (px.abs() - bx, pz.abs() - bz);
    dx.max(0.0).hypot(dz.max(0.0)) + dx.max(dz).min(0.0)
}

// ---- the land each giant tears up as it comes up out of it -------------------------------------------------------------
// Every column round a giant's feet, and along its hammer where that came up out of the ground in front of it, is read as
// the giant starts to rise (`world.read-columns`, HV_BELOW under each column's top: a tall tree's crown down to its ground)
// and torn up a chunk at a time from its feet out over the rise (`hv_setup`, `hv_drive`, `hv_chunk`): whatever grows or
// stands on the land goes, whatever its height; the ground is broken into plates of torn earth and stone split by cracks
// radiating from its feet (`frac`; the pass's green ones, `cl_frac` in `cl_ground`, the same); and the earth it heaves up is heaped on each
// column's own ground (`Heave::terms`, the pass's `cl_mh`), in up to HV_STEPS lifts. The earth against each stance foot goes
// in as that foot is stamped down, the lip round the hammer as it is driven in. Its edge is ragged and fades into the land
// untouched (`Heave::edge`). With the terrain on the pass draws no heap outside the crater (flags bit 3): the blocks are
// the heap. Nothing of it inside the crater.

/// Blocks read under each column's top.
const HV_BELOW: u32 = 36;
/// Chunks one read asks for.
const HV_READ: usize = 24;
/// What one stage of a giant's tearing up may spend (meter instructions, charged near what the game's fuel counts: a chunk
/// of flat land is some 2.5 million, so a stage takes four or five; a chunk of hills, its columns taller, more, so fewer).
const HV_STAGE: u64 = 11_000_000;
/// How long before its first edit a chunk is worked out.
const HV_LEAD: f32 = 0.8;
/// Columns not loaded by then are left as they are.
const HV_LAST: f32 = 19.0;
/// The torn land fades out from this far inside the heap's edge to this far past it (blocks; `Heave::edge`).
const HV_TORN: [f32; 2] = [-6.0, 14.0];
/// Everything standing is cleared to this far past the edge, and leaves to this far (so no crown is left hanging).
const HV_STRIP: f32 = 18.0;
const HV_LEAVES: f32 = 26.0;
/// The most the edge's noise brings it in (`Heave::edge`).
const HV_RAGGED: f32 = 13.5;
/// Whether what stands round the hammer's blow (the lip's land, past the crater) is cleared and torn as the blow lands
/// rather than as the giant rises.
const HV_AT_BLOW: bool = true;
/// Whether a heap on grass gets a grass block on top (a second run on its last lift; off: the soak's memory and fuel).
const HV_GRASS_TOP: bool = false;
/// Where the pass reads each giant's torn land's colours (`mod_data` words HV_COL + 2 g: its surface's, what is under it;
/// 0xAABBGGRR sRGB, A 255 once known): `cl_heapcol` in colossi.wgsl.
pub(crate) const HV_COL: usize = 1008;
/// Most lifts a column's heap goes up in, the blocks a lift at least, and the time between them.
const HV_STEPS: i32 = 3;
const HV_LIFT: i32 = 7;
const HV_GAP: f32 = 0.6;
const HV_AIR: &str = "minecraft:air";
/// What the heap goes into.
const HV_INTO: &str = "#minecraft:replaceable";
/// The torn earth, a family to a plate of it (`Frac`): the first three the rock torn up near a giant's feet (the first also
/// the lips of its cracks and fissures), the rest the earth further out. Within a plate, patches of each a few blocks
/// across (`hv_mat`); a column's heap is the one block all through, so its lifts go in as one run each. The pass's heap
/// is coloured the same way (`cl_heapcol` in colossi.wgsl).
const HV_FAM: [[&str; 3]; 8] = [
    ["minecraft:cobbled_deepslate", "minecraft:deepslate", "minecraft:tuff"],
    ["minecraft:stone", "minecraft:cobblestone", "minecraft:andesite"],
    ["minecraft:tuff", "minecraft:stone", "minecraft:cobbled_deepslate"],
    ["minecraft:coarse_dirt", "minecraft:dirt", "minecraft:gravel"],
    ["minecraft:rooted_dirt", "minecraft:coarse_dirt", "minecraft:dirt"],
    ["minecraft:packed_mud", "minecraft:coarse_dirt", "minecraft:rooted_dirt"],
    ["minecraft:gravel", "minecraft:coarse_dirt", "minecraft:cobblestone"],
    ["minecraft:dirt", "minecraft:coarse_dirt", "minecraft:rooted_dirt"],
];
/// Main cracks round a giant's feet, and the width of the rings its broken plates lie in (CL_K units; `frac`).
const FR_N: f32 = 9.0;
const FR_RING: f32 = 3.6;

/// The ground a giant breaks as it rises, at q (CL_K units from the middle of its feet, world axes; seed 11 + its
/// index): FR_N cracks radiating from its feet, wide and deep near them and tapering out, each with up to two branches
/// veering off it; between them plates of broken ground in rings FR_RING wide, each tilted its own way, with a fissure
/// along most of their edges. The pass's `cl_frac` is the same, step for step.
#[derive(Clone, Copy, Default)]
struct Frac {
    /// How far into a crack (0: none; 1 its middle), how near its root (1) the crack is, and the nearest crack's distance
    /// over its half width.
    c: f32,
    nr: f32,
    x: f32,
    /// Blocks to the plate's fissure across its ring (99: none).
    ring: f32,
    /// The plate's two hashes, how far up its tilt (0..1) and its ring's middle (units).
    p: f32,
    p2: f32,
    ramp: f32,
    dj: f32,
}
fn frac(s: u32, q: [f32; 2]) -> Frac {
    use std::f32::consts::TAU;
    let d = q[0].hypot(q[1]).max(1.0e-3);
    let arc = TAU * d / FR_N;
    let warp = (3.4 * (vs(s, q[0] * 0.11, q[1] * 0.11) - 0.5) + 0.7 * (vs(s + 97, q[0] * 0.5, q[1] * 0.5) - 0.5)) * (d / 7.0).min(1.0);
    let u = q[1].atan2(q[0]) / TAU * FR_N + warp / arc;
    let k0 = u.floor();
    let f = u - k0;
    let id = |kk: f32| (kk as i32).rem_euclid(FR_N as i32);
    // (each crack set off its even spacing a little)
    let jit = |i: i32| 0.56 * (unit(s, i, 7, 9) - 0.5);
    let mut out = Frac { x: 99.0, ring: 99.0, ..Default::default() };
    let mut sub = 0;
    for (kk, side) in [(k0, 0.0f32), (k0 + 1.0, 0.0), (k0, 1.0), (k0 + 1.0, -1.0)] {
        let i = id(kk);
        let (st, half, at, nr);
        if side == 0.0 {
            let d0 = 2.2 + unit(s, i, 7, 2);
            let l = 12.0 + 9.0 * unit(s, i, 7, 1);
            st = ss(d0, d0 + 1.2, d) * (1.0 - ss(0.6 * l, l, d));
            nr = 1.0 - ss(d0, 13.0, d);
            half = 0.5 + 1.1 * nr;
            at = kk + jit(i);
        } else {
            let b = if side > 0.0 { 3 } else { 4 };
            if unit(s, i, 7, b) < 0.3 {
                continue;
            }
            let ds = 4.0 + 7.0 * unit(s, i, 7, b + 2);
            let l = ds + 4.0 + 7.0 * unit(s, i, 7, b + 4);
            let veer = 0.4 * ss(ds, ds + 5.0, d);
            at = kk + jit(i) + side * veer;
            if d > ds + 0.5 && d < l && (if side > 0.0 { u > at } else { u < at }) {
                sub |= if side > 0.0 { 1 } else { 2 };
            }
            st = ss(ds, ds + 1.0, d) * (1.0 - ss(0.5 * (ds + l), l, d));
            nr = 1.0 - ss(ds, 16.0, d);
            half = 0.4 + 0.5 * nr;
        }
        if st < 0.02 {
            continue;
        }
        let x = (u - at).abs() * arc * CL_K as f32 / half;
        let c = st * (1.0 - x);
        if c > out.c {
            out.c = c;
            out.nr = nr;
        }
        if st > 0.3 {
            out.x = out.x.min(x);
        }
    }
    // (the rings staggered from one plate's span to the next, and bent, so their edges never line up into circles)
    let pid = id(k0) * 4 + sub;
    let ph = unit(s, pid, 11, 0);
    let v = (d + 3.2 * (vs(s + 5, q[0] * 0.14, q[1] * 0.14) - 0.5)) / FR_RING + ph;
    let j = v.floor();
    let fr = v - j;
    if d > 3.0 && unit(s, pid, 8, (v + 0.5).floor() as i32) > 0.45 {
        out.ring = fr.min(1.0 - fr) * FR_RING * CL_K as f32;
    }
    out.p = unit(s, pid, 9, j as i32);
    out.p2 = unit(s, pid, 10, j as i32);
    out.ramp = if out.p2 < 0.4 {
        fr
    } else if out.p2 < 0.8 {
        1.0 - fr
    } else {
        f
    };
    out.dj = (j + 0.5 - ph) * FR_RING;
    out
}

/// Giant g's heave, in blocks from the target block's middle (the pass's `ClM`; `cl_mound` works out the same).
struct Heave {
    g: usize,
    seed: u32,
    sc: f32,
    /// The middle of its feet, and its own x and z axes over its scale.
    o: [f32; 2],
    ax: [f32; 2],
    az: [f32; 2],
    /// Its feet at rest (0, 1) and in the stance (2, 3), in its own units from `o`.
    feet: [[f32; 2]; 4],
    /// The hammer's head where it came up out of the ground, where it is driven in, the head's half width, its scale.
    hc: [f32; 2],
    sq: [f32; 2],
    hw: f32,
    hsr: f32,
    /// The circle the pass traces the hammer's heap in.
    o2: [f32; 2],
    r2: f32,
    bx: i32,
    bz: i32,
    /// When it starts to rise, when its feet stamp down, when its hammer is first driven in.
    tr: f32,
    stomp: [f32; 2],
    slam: f32,
    /// The land it tears up as read so far (`hv_chunk`): its surface's colour and what is under it, summed (sRGB 0..255), and
    /// how many columns; the pass colours its own heap with the averages (`HV_COL`).
    surf: std::cell::Cell<[f32; 7]>,
}
/// A column's share of the heap, in the giant's units before its scale: the ring, the feet at rest and the hammer's ridge
/// (as it rises), each stance foot, the lip round the hammer.
#[derive(Default, Clone, Copy)]
struct Terms {
    rise: f32,
    st: [f32; 2],
    lip: f32,
    n0: f32,
    keep: f32,
}
impl Heave {
    fn new(t: &Target, g: usize) -> Heave {
        let st = &statues()[g];
        let rig = pose::Rig::read(usize::from(st.design));
        let (ox, oz) = corner(t, g, st);
        let (yaw, mirror, sc) = (st.yaw, if st.mirror { -1.0f32 } else { 1.0 }, f32::from(st.height) / 50.0);
        let (s, c) = yaw.sin_cos();
        let j = |n: usize| [rig.j[n][0] as f32, rig.j[n][2] as f32];
        let (jr, jl) = (j(11), j(14));
        let fm = [0.5 * (jr[0] + jl[0]), 0.5 * (jr[1] + jl[1])];
        let o = [
            (ox - t.block[0]) as f32 - 0.5 + st.b[0] + mirror * sc * (c * fm[0] + s * fm[1]),
            (oz - t.block[2]) as f32 - 0.5 + st.b[2] + sc * (-s * fm[0] + c * fm[1]),
        ];
        let (ax, az) = ([mirror * c / sc, -s / sc], [mirror * s / sc, c / sc]);
        let (l, r) = ([jl[0] - fm[0], jl[1] - fm[1] + 1.6], [jr[0] - fm[0], jr[1] - fm[1] + 1.6]);
        let feet = [[l[0] + 2.0, l[1]], [r[0] - 2.0, r[1]], [l[0] + 2.5, l[1] + 3.4], [r[0] - 2.9, r[1] - 2.4]];
        let jp = j(0);
        let hsr = (HAMMER_TALL / rig.hammer_ext[1]) as f32;
        let hw = 0.5 * rig.hammer_ext[2] as f32 * hsr;
        let hc = [jp[0] - fm[0], jp[1] + 26.5 - fm[1]];
        let sq = [jp[0] - fm[0], jp[1] + SLAM_AHEAD as f32 - fm[1]];
        let zhi = sq[1] + 6.0 * hsr + 3.5;
        let qc = [hc[0], 0.5 * (16.0 + zhi)];
        let o2 = [o[0] + sc * sc * (ax[0] * qc[0] + az[0] * qc[1]), o[1] + sc * sc * (ax[1] * qc[0] + az[1] * qc[1])];
        let r2 = sc * (hw + 3.5).hypot(0.5 * (zhi - 16.0)) + 2.0;
        Heave {
            g,
            seed: st.seed,
            sc,
            o,
            ax,
            az,
            feet,
            hc,
            sq,
            hw,
            hsr,
            o2,
            r2,
            bx: t.block[0],
            bz: t.block[2],
            tr: T_RISE0 + T_RISE_STEP * g as f32,
            stomp: [slam1(g) - 3.2 * leads(t, g)[0], slam2(t, g) - 3.2 * leads(t, g)[1]],
            slam: slam1(g),
            surf: std::cell::Cell::new([0.0; 7]),
        }
    }
    /// Column (x, z) in the giant's own frame: its place (units from `o`), how far from `o`, from the hammer's ridge and
    /// from where it is driven in (units).
    fn shape(&self, x: i32, z: i32) -> ([f32; 2], f32, f32, f32) {
        let w = [(x - self.bx) as f32 - self.o[0], (z - self.bz) as f32 - self.o[1]];
        let qv = [w[0] * self.ax[0] + w[1] * self.ax[1], w[0] * self.az[0] + w[1] * self.az[1]];
        let rad = qv[0].hypot(qv[1]);
        let (pa, pb) = ([qv[0] - self.hc[0], qv[1] - self.hc[1]], [qv[0] - self.sq[0], qv[1] - self.sq[1]]);
        // (ragged, and the strip the head tore narrowing to its far end: the pass's `cl_mh` the same)
        let pn = n2(self.seed ^ 0x51, qv[0] * 0.45, qv[1] * 0.45) - 0.5;
        let boxa = boxd(pa[0], pa[1], self.hw, 7.5 * self.hsr) + 0.6 * self.hw * ss(-2.0 * self.hsr, 7.5 * self.hsr, pa[1]);
        let da = boxa.min(pa[0].hypot(pa[1] - pa[1].clamp(-24.0 * self.hsr, 0.0)) - 1.6 * self.hsr) + 1.4 * pn;
        let db = boxd(pb[0], pb[1], self.hw, 6.0 * self.hsr) + 1.2 * pn;
        (qv, rad, da, db)
    }
    /// What the pass's `cl_mh` heaps on column (x, z) at the end, term by term (its 2-block cell's noise, the column's own
    /// place; the ridge and the lip feathered to nothing at their edge).
    fn terms(&self, x: i32, z: i32, qv: [f32; 2], rad: f32, da: f32, db: f32) -> Terms {
        let mut t = Terms::default();
        // (the pass traces the hammer's heap only in a circle, `o2`, `r2`, and draws none outside the crater with the terrain
        // on: the blocks leave the circle out, so the ridge feathers out at its own edge)
        if rad > 19.5 && da.min(db) > 3.5 {
            return t;
        }
        let (cx, cz) = ((x - self.bx).div_euclid(2), (z - self.bz).div_euclid(2));
        let n = n2(self.seed, cx as f32 * 0.21, cz as f32 * 0.21);
        // (in patches a few cells across, not cell by cell)
        let n0 = 0.75 * vs(self.seed ^ 0x2F, cx as f32 * 0.4, cz as f32 * 0.4) + 0.25 * unit(self.seed, cx, 9, cz);
        t.n0 = n0;
        if rad <= 19.5 {
            let rr = (rad - 13.0 - 5.0 * (n - 0.5)) / 2.7;
            t.rise = (1.0 + 4.6 * n * n) * (-rr * rr).exp() + if n0 >= 0.45 { 0.32 * n0 * (1.0 - ss(8.0, 13.0, rad)) } else { 0.0 };
            for (k, f) in self.feet.iter().enumerate() {
                let e = ((qv[0] - f[0]) / 3.3).hypot((qv[1] - f[1]) / 5.2);
                let v = (2.1 + 2.2 * n + 0.6 * n0) * (1.0 - ss(0.7, 1.45, e));
                if k < 2 {
                    t.rise = t.rise.max(v);
                } else {
                    t.st[k - 2] = v;
                }
            }
        }
        if da <= 3.5 {
            let ra = (da - 1.2 - 1.6 * (n - 0.5)) / 1.5;
            t.rise = t.rise.max(((1.0 + 3.8 * n * n) * (-ra * ra).exp() + if n0 >= 0.4 && da <= 0.0 { 0.36 * n0 } else { 0.0 }) * (1.0 - ss(1.5, 3.5, da)));
        }
        if t.rise > 0.05 {
            // (each plate of it tipped up its own way, `frac`)
            let k = CL_K as f32;
            let fr = frac(11 + self.g as u32, [((2 * cx + 1) as f32 - self.o[0]) / k, ((2 * cz + 1) as f32 - self.o[1]) / k]);
            t.rise += (0.12 + 0.5 * fr.p) * fr.ramp * ss(0.45, 1.6, t.rise);
        }
        if db <= 3.5 {
            let rb = (db - 1.2 - 1.6 * (n - 0.5)) / 1.5;
            t.lip = (1.0 + 4.2 * n * n) * (-rb * rb).exp() * (1.0 - ss(1.5, 3.5, db));
        }
        // (and to nothing at the crater's edge, where the pass's own heap, drawn in the crater till the blast, fades too)
        let rt = ((x - self.bx) as f32).hypot((z - self.bz) as f32);
        t.keep = ss(CRATER_R as f32 + 2.0, CRATER_R as f32 + 14.0, rt);
        t
    }
    /// Blocks of heap for a sum of terms `v`.
    fn blocks(&self, t: &Terms, v: f32) -> i32 {
        (v * t.keep * self.sc + 0.6 * t.n0).floor().max(0.0) as i32
    }
    /// How far past the heap's edge column (x, z) is (blocks, ragged: below 0 inside it).
    fn edge(&self, x: i32, z: i32, rad: f32, da: f32, db: f32) -> f32 {
        let nb = vs(self.seed ^ 0x9E37, (x - self.bx) as f32 * 0.045, (z - self.bz) as f32 * 0.045);
        let nf = vs(self.seed ^ 0x3C1, (x - self.bx) as f32 * 0.11, (z - self.bz) as f32 * 0.11);
        (rad - 17.0).min(da - 0.8).min(db - 1.5) * self.sc + 18.0 * (nb - 0.5) + 9.0 * (nf - 0.5)
    }
    /// The cracks and plates the giant breaks the ground into at column (x, z) (`frac`; the pass's green cracks, `cl_frac` in
    /// `cl_ground`, run along the same lines).
    fn frac(&self, x: i32, z: i32) -> Frac {
        let k = CL_K as f32;
        frac(11 + self.g as u32, [((x - self.bx) as f32 - self.o[0]) / k, ((z - self.bz) as f32 - self.o[1]) / k])
    }
    /// How deep a crack through column (x, z) is dug (0: none): 2 to 7, deepest at its middle near the giant.
    fn crack(f: &Frac) -> i32 {
        if f.c <= 0.0 { 0 } else { 2 + (5.0 * f.c * (0.35 + 0.65 * f.nr)) as i32 }
    }
    /// The region read: whether a point (blocks from the target's middle) may lie within `pad` of what is torn or stripped.
    fn near(&self, x: f32, z: f32, pad: f32) -> bool {
        let (_, rad, da, db) = self.shape(self.bx + x.round() as i32, self.bz + z.round() as i32);
        let reach = HV_LEAVES + HV_RAGGED + pad;
        (rad - 17.0) * self.sc < reach || (da.min(db) - 1.5) * self.sc < reach
    }
}

/// What a block read is to a giant tearing up the land: 0 air, 1 water or lava (and what grows in it), 2 leaves, 3 what
/// stands or grows on the land (logs, plants, snow, what was built), 4 the ground, 5 what holds things (chests and the
/// like: their columns are left as they are).
fn hv_kind(name: &str) -> u8 {
    let n = name.strip_prefix("minecraft:").unwrap_or(name);
    let n = n.split('[').next().unwrap_or(n);
    if n.ends_with("air") {
        return 0;
    }
    const KEEP: [&str; 14] = [
        "chest", "barrel", "shulker_box", "furnace", "smoker", "hopper", "dispenser", "dropper", "lectern", "brewing_stand",
        "crafter", "decorated_pot", "shelf", "jukebox",
    ];
    if KEEP.iter().any(|k| n.contains(k)) {
        return 5;
    }
    if matches!(n, "water" | "lava" | "bubble_column" | "seagrass" | "tall_seagrass" | "kelp" | "kelp_plant") {
        return 1;
    }
    if n.ends_with("_leaves") {
        return 2;
    }
    const GROUND: [&str; 34] = [
        "grass_block", "dirt", "podzol", "mycelium", "stone", "deepslate", "sand", "gravel", "clay", "terracotta", "ice",
        "snow_block", "mud", "moss_block", "granite", "diorite", "andesite", "tuff", "calcite", "basalt", "blackstone",
        "netherrack", "_ore", "bedrock", "sandstone", "rooted_dirt", "farmland", "dirt_path", "obsidian", "magma_block",
        "pale_moss_block", "soul_sand", "soul_soil", "cobblestone",
    ];
    if GROUND.iter().any(|g| n.contains(g)) && !n.contains("_slab") && !n.contains("_stairs") && !n.contains("_wall") && !n.contains("button") && !n.contains("pressure") {
        return 4;
    }
    3
}

/// What the land's own surface (ground block `name`, under snow if `snow`) makes the top of the earth heaved up from it,
/// and what is under it there (0 earth, `HV_FAM`'s; 1 sand; 2 red sand; 3 rock): the heap is what was there, not always
/// dirt. None: a block of the family's own.
fn hv_surface(name: &str, snow: bool) -> (Option<&'static str>, u8) {
    let n = name.strip_prefix("minecraft:").unwrap_or(name);
    let n = n.split('[').next().unwrap_or(n);
    if snow || matches!(n, "snow_block" | "powder_snow") {
        return (Some("minecraft:snow_block"), 0);
    }
    match n {
        "grass_block" => (Some("minecraft:grass_block"), 0),
        "podzol" => (Some("minecraft:podzol"), 0),
        "mycelium" => (Some("minecraft:mycelium"), 0),
        "moss_block" | "pale_moss_block" => (Some("minecraft:moss_block"), 0),
        "mud" => (Some("minecraft:mud"), 0),
        "dirt_path" | "farmland" => (Some("minecraft:dirt"), 0),
        "clay" => (Some("minecraft:clay"), 0),
        "sand" | "suspicious_sand" => (Some("minecraft:sand"), 1),
        "sandstone" => (Some("minecraft:sandstone"), 1),
        "red_sand" => (Some("minecraft:red_sand"), 2),
        "red_sandstone" => (Some("minecraft:red_sandstone"), 2),
        "gravel" => (Some("minecraft:gravel"), 3),
        "stone" => (Some("minecraft:stone"), 3),
        "andesite" => (Some("minecraft:andesite"), 3),
        "diorite" => (Some("minecraft:diorite"), 3),
        "granite" => (Some("minecraft:granite"), 3),
        "tuff" => (Some("minecraft:tuff"), 3),
        "calcite" => (Some("minecraft:calcite"), 3),
        "deepslate" => (Some("minecraft:deepslate"), 3),
        "ice" | "packed_ice" | "blue_ice" => (Some("minecraft:packed_ice"), 3),
        _ if n.contains("terracotta") => (Some("minecraft:terracotta"), 2),
        _ => (None, 0),
    }
}
/// The heap's block under its top, by what is under the surface (`hv_surface`), the plate's family and the patch `k`.
fn hv_under(under: u8, fam: usize, k: usize) -> &'static str {
    const SAND: [&str; 3] = ["minecraft:sand", "minecraft:sandstone", "minecraft:sand"];
    const RED: [&str; 3] = ["minecraft:red_sand", "minecraft:red_sandstone", "minecraft:terracotta"];
    match under {
        1 => SAND[k],
        2 => RED[k],
        3 if fam >= 3 => HV_FAM[(fam + k) % 3][k],
        _ => HV_FAM[fam][k],
    }
}
/// A block's average colour (sRGB, the game's texture's: `sh_land::MATS`), its top's tinted by the biome's grass tint.
fn hv_rgb(name: &str, grass: u32) -> [f32; 3] {
    let (m, _) = super::sh_land::material(name);
    let e = super::sh_land::MATS[usize::from(m)];
    let c = e.0;
    if e.3 & super::sh_land::TINT_GRASS != 0 && grass != 0 {
        let t = [(grass >> 16) & 255, (grass >> 8) & 255, grass & 255];
        return std::array::from_fn(|i| f32::from(c[i]) * t[i] as f32 / 255.0);
    }
    if e.3 & super::sh_land::TINT_GRASS != 0 {
        return [99.0, 148.0, 66.0];
    }
    std::array::from_fn(|i| f32::from(c[i]))
}

/// Adds a torn column's surface (`top`) and under-colour (`under`) to the sums (sRGB; [6] how many), every fourth one.
fn d_count_colour(sum: &mut [f32; 7], top: [f32; 3], under: &'static str, cache: &mut Vec<(&'static str, [f32; 3])>) {
    sum[6] += 0.25;
    if sum[6].fract() != 0.0 {
        return;
    }
    // (the under-blocks are a few dozen literals: their colours kept by the name's address)
    let b = match cache.iter().find(|e| std::ptr::eq(e.0, under)) {
        Some(e) => e.1,
        None => {
            crate::meter::spend(8_000);
            let c = hv_rgb(under, 0);
            cache.push((under, c));
            c
        }
    };
    for i in 0..3 {
        sum[i] += 4.0 * top[i];
        sum[3 + i] += 4.0 * b[i];
    }
}
/// What a read's block (a palette entry) is to the heap's colours and top (worked out once a read, as its kinds are).
#[derive(Clone, Copy)]
struct HvPal {
    top: Option<&'static str>,
    sub: u8,
    snow: bool,
    grassy: bool,
    rgb: [f32; 3],
}
fn hv_pal(name: &str) -> HvPal {
    let (top, sub) = hv_surface(name, false);
    let n = name.split('[').next().unwrap_or(name);
    let rgb = hv_rgb(top.unwrap_or(n), 0);
    HvPal { top, sub, snow: n == "minecraft:snow", grassy: top == Some("minecraft:grass_block"), rgb }
}
/// A chunk of a giant's land waiting to be torn up: when its first edit is due, when it is worked out, the read that holds
/// its columns (from `off`, `n` of them) and how many chunks of that read are still to be worked out.
struct HvJob {
    t1: f32,
    due: f32,
    tag: u32,
    off: usize,
    n: usize,
    left: Rc<std::cell::Cell<u32>>,
    /// Its columns while its land is not loaded (`hv_drive`): `tag` 0 till its first column is asked again (then that column
    /// is `off` of read `tag`), and how many times that has been.
    wait: Option<Vec<(i32, i32)>>,
    tries: u8,
}
struct HvState {
    jobs: std::collections::VecDeque<HvJob>,
    /// The kinds of the last read's palette.
    kinds: (u32, Vec<u8>),
    /// Its palette as the heap's colours and top see it (`hv_pal`), and the under-blocks' colours.
    pal: Vec<HvPal>,
    under: Vec<(&'static str, [f32; 3])>,
}
fn hv_queue(jobs: &mut std::collections::VecDeque<HvJob>, job: HvJob) {
    let i = jobs.partition_point(|j| j.due <= job.due);
    jobs.insert(i, job);
}

/// Giant g's land: the chunks round its feet and along its hammer, each due as the rise reaches it out from its feet, read
/// a few dozen at a time (asked now: the answers come a tick or two later), then torn up by `hv_drive`.
fn hv_setup(q: &mut Plan, hv: Rc<Heave>, now: f32) {
    let (bx, bz) = (hv.bx, hv.bz);
    let reach = 17.0 * hv.sc + HV_LEAVES + HV_RAGGED;
    let r2 = hv.r2 + 1.5 * hv.sc + HV_LEAVES + HV_RAGGED;
    let (x0, x1) = ((hv.o[0] - reach).min(hv.o2[0] - r2), (hv.o[0] + reach).max(hv.o2[0] + r2));
    let (z0, z1) = ((hv.o[1] - reach).min(hv.o2[1] - r2), (hv.o[1] + reach).max(hv.o2[1] + r2));
    let crater = CRATER_R as f32 + 2.0;
    let mut chunks: Vec<(f32, i32, i32)> = Vec::new();
    for cz in (bz + z0.floor() as i32) >> 4..=(bz + z1.ceil() as i32) >> 4 {
        for cx in (bx + x0.floor() as i32) >> 4..=(bx + x1.ceil() as i32) >> 4 {
            crate::meter::spend(300);
            let (mx, mz) = ((cx * 16 + 8 - bx) as f32, (cz * 16 + 8 - bz) as f32);
            if mx.hypot(mz) + 12.0 < crater || !hv.near(mx, mz, 12.0) {
                continue;
            }
            let d = (mx - hv.o[0]).hypot(mz - hv.o[1]);
            chunks.push((hv.tr + 0.4 + 4.4 * (d / reach).clamp(0.0, 1.0).powf(0.85), cx, cz));
        }
    }
    chunks.sort_by(|a, b| a.0.total_cmp(&b.0));
    let mut jobs = std::collections::VecDeque::new();
    for part in chunks.chunks(HV_READ) {
        let tag = crate::columns::new_tag();
        let mut columns = Vec::with_capacity(part.len() * 256);
        let left = Rc::new(std::cell::Cell::new(part.len() as u32));
        for &(t1, cx, cz) in part {
            let off = columns.len();
            for z in cz * 16..cz * 16 + 16 {
                for x in cx * 16..cx * 16 + 16 {
                    if ((x - bx) as f32).hypot((z - bz) as f32) >= crater {
                        columns.push((x, z));
                    }
                }
            }
            crate::meter::spend(256 * 30);
            jobs.push_back(HvJob { t1, due: t1 - HV_LEAD, tag, off, n: columns.len() - off, left: Rc::clone(&left), wait: None, tries: 0 });
        }
        // (each read asked a little before its first chunk is due, so the answers come in a few at a time)
        q.ev.push((now.max(part[0].0 - HV_LEAD - 0.4), Act::Read { tag, columns, below: HV_BELOW, above: 0 }));
    }
    #[cfg(test)]
    HV_PEAK.with(|p| p.set(p.get().max(crate::meter::spent())));
    let Some(first) = jobs.front().map(|j| j.due) else { return };
    let st = Rc::new(RefCell::new(HvState { jobs, kinds: (0, Vec::new()), pal: Vec::new(), under: Vec::new() }));
    let at = first.max(now + 0.1);
    q.soon(at, move |q| hv_drive(q, hv, st, at));
}

/// Works out the chunks due (each one's edits handed on for when they go in), up to `HV_STAGE` a stage; a chunk whose read is
/// not in yet waits a little; a chunk whose land is not loaded is looked at again till `HV_LAST`: one of its columns asked
/// first (a chunk loads whole), all of them once that one is in, less often the longer it waits.
fn hv_drive(q: &mut Plan, hv: Rc<Heave>, st: Rc<RefCell<HvState>>, now: f32) {
    // (by the strike's clock: a tick works out one stage, so this one may run well after it was due, and must catch up with
    // everything due since rather than fall further behind a stage at a time)
    let now = now.max(super::clock());
    let start = crate::meter::spent();
    let mut s = st.borrow_mut();
    // (what this stage asks: a column of each chunk still waiting, and all the columns of those whose land has come)
    let (mut probe, mut probe_jobs): (Vec<(i32, i32)>, Vec<HvJob>) = (Vec::new(), Vec::new());
    let (mut ask, mut ask_jobs): (Vec<(i32, i32)>, Vec<HvJob>) = (Vec::new(), Vec::new());
    while crate::meter::spent() - start < HV_STAGE {
        let Some(mut job) = s.jobs.pop_front() else { break };
        if job.due > now {
            s.jobs.push_front(job);
            break;
        }
        crate::meter::spend(2_000);
        if let Some(cols) = &job.wait {
            if now + 0.3 >= HV_LAST {
                // (too late: left as it is)
                if job.tag != 0 {
                    job.left.set(job.left.get().saturating_sub(1));
                    if job.left.get() == 0 {
                        crate::columns::take(job.tag);
                    }
                }
                continue;
            }
            if job.tag == 0 {
                // (its probe asked)
                job.off = probe.len();
                probe.push(cols[0]);
                probe_jobs.push(job);
                continue;
            }
            let Some(a) = crate::columns::get(job.tag) else {
                hv_queue(&mut s.jobs, HvJob { due: now + 0.1, ..job });
                continue;
            };
            job.left.set(job.left.get().saturating_sub(1));
            if job.left.get() == 0 {
                crate::columns::take(job.tag);
            }
            if a.column(job.off).is_some() {
                // (its land has come: all of it asked)
                let cols = job.wait.take().unwrap_or_default();
                job.off = ask.len();
                job.n = cols.len();
                ask.extend(cols);
                ask_jobs.push(job);
            } else {
                // (not yet: again in half a second, then a second, then two)
                let wait = 0.5 * f32::from(1u8 << job.tries.min(2));
                let due = ((now + wait) / 0.25).ceil() * 0.25;
                hv_queue(&mut s.jobs, HvJob { t1: due, due, tag: 0, tries: job.tries + 1, ..job });
            }
            continue;
        }
        let Some(a) = crate::columns::get(job.tag) else {
            if now < HV_LAST {
                hv_queue(&mut s.jobs, HvJob { due: now + 0.1, ..job });
            }
            continue;
        };
        if s.kinds.0 != job.tag {
            crate::meter::spend(800 * a.palette.len() as u64);
            s.kinds = (job.tag, a.palette.iter().map(|n| hv_kind(n)).collect());
            crate::meter::spend(6_000 * a.palette.len() as u64);
            s.pal = a.palette.iter().map(|n| hv_pal(n)).collect();
        }
        let mut missing = Vec::new();
        let s = &mut *s;
        hv_chunk(q, &hv, &a, &s.kinds.1, &s.pal, &mut s.under, job.off, job.n, job.t1, now, &mut missing);
        job.left.set(job.left.get().saturating_sub(1));
        if job.left.get() == 0 {
            crate::columns::take(job.tag);
        }
        if !missing.is_empty() && now + 0.8 < HV_LAST {
            let due = ((now + 0.5) / 0.25).ceil() * 0.25;
            hv_queue(&mut s.jobs, HvJob { t1: due, due, tag: 0, off: 0, n: 0, left: Rc::new(std::cell::Cell::new(0)), wait: Some(missing), tries: 0 });
        }
    }
    for (cols, jobs, ahead) in [(probe, probe_jobs, 0.1), (ask, ask_jobs, 0.3)] {
        if jobs.is_empty() {
            continue;
        }
        let tag = crate::columns::new_tag();
        let left = Rc::new(std::cell::Cell::new(jobs.len() as u32));
        for job in jobs {
            hv_queue(&mut s.jobs, HvJob { t1: now + ahead, due: now + 0.1, tag, left: Rc::clone(&left), ..job });
        }
        q.ev.push((now, Act::Read { tag, columns: cols, below: HV_BELOW, above: 0 }));
    }
    #[cfg(test)]
    HV_PEAK.with(|p| p.set(p.get().max(crate::meter::spent() - start)));
    let Some(next) = s.jobs.front().map(|j| j.due) else { return };
    drop(s);
    let at = next.max(now + 0.05);
    q.soon(at, move |q| hv_drive(q, hv, st, at));
}
#[cfg(test)]
thread_local! {
    static HV_PEAK: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
}

/// One chunk of a giant's land torn up (the columns `off..off + n` of read `a`): what stands on it cleared, the ground broken,
/// the cracks dug, the heap heaped on it in lifts from `t1`, the earth against the stance feet and the hammer's lip later.
#[allow(clippy::too_many_arguments)]
fn hv_chunk(q: &mut Plan, hv: &Heave, a: &crate::columns::Answer, kinds: &[u8], pal: &[HvPal], under_rgb: &mut Vec<(&'static str, [f32; 3])>, off: usize, n: usize, t1: f32, now: f32, missing: &mut Vec<(i32, i32)>) {
    const NONE: i32 = i32::MIN;
    /// A column as read: its ground, the top of the water or lava over it, the highest thing standing on it, whether the
    /// block under its ground is ground too.
    #[derive(Clone, Copy)]
    struct C {
        x: i32,
        z: i32,
        g: i32,
        w: i32,
        s: i32,
        under: bool,
        top: Option<&'static str>,
        sub: u8,
        rgb: [f32; 3],
    }
    let mut cols: Vec<C> = Vec::with_capacity(n);
    let mut wet = [false; 256];
    for i in off..(off + n).min(a.columns.len()) {
        let (x, z) = a.columns[i];
        let Some((top, blocks)) = a.column(i) else {
            missing.push((x, z));
            continue;
        };
        let base = top - a.below;
        let (mut w, mut s, mut found, mut keep) = (NONE, NONE, None, false);
        for j in (0..blocks.len()).rev() {
            match kinds.get(blocks[j] as usize).copied().unwrap_or(3) {
                0 => {}
                1 => {
                    if w == NONE {
                        w = base + j as i32;
                    }
                }
                4 => {
                    found = Some(j);
                    break;
                }
                5 => {
                    keep = true;
                    break;
                }
                _ => {
                    if s == NONE {
                        s = base + j as i32;
                    }
                }
            }
        }
        crate::meter::spend(60 + 40 * (blocks.len() - found.unwrap_or(0)) as u64);
        // (no ground within reach, a deep sea's or under a very tall tree: left as it is; and a column with a chest or the
        // like in it, on the ground or in it as deep as a crack goes)
        let Some(j) = found else { continue };
        if keep || blocks[j.saturating_sub(8)..j].iter().any(|&b| kinds.get(b as usize) == Some(&5)) {
            continue;
        }
        let g = base + j as i32;
        if w != NONE {
            wet[((z & 15) * 16 + (x & 15)) as usize] = true;
        }
        // (its surface: the ground block, under snow if a layer of it lies on it)
        let none = HvPal { top: None, sub: 0, snow: false, grassy: false, rgb: [122.0, 112.0, 100.0] };
        let p = pal.get(blocks[j] as usize).copied().unwrap_or(none);
        let snow = blocks.get(j + 1).and_then(|&b| pal.get(b as usize)).is_some_and(|q| q.snow);
        let (top, sub, rgb) = if snow { (Some("minecraft:snow_block"), 0, [249.0, 254.0, 254.0]) } else { (p.top, p.sub, p.rgb) };
        // (grass by the biome's own tint)
        let gt = a.tints(i).0;
        let rgb = if p.grassy && !snow {
            if gt != 0 { [((gt >> 16) & 255) as f32 * 147.0 / 255.0, ((gt >> 8) & 255) as f32 * 147.0 / 255.0, (gt & 255) as f32 * 147.0 / 255.0] } else { [99.0, 148.0, 66.0] }
        } else {
            rgb
        };
        cols.push(C { x, z, g, w, s, under: j > 0 && kinds.get(blocks[j - 1] as usize) == Some(&4), top, sub, rgb });
    }
    // (what each column becomes: its heap as it rises and after each later blow, whether it is torn, stripped, cracked)
    struct D {
        c: C,
        h: [i32; 4],
        torn: bool,
        strip: u8,
        crack: i32,
        /// A fissure between plates (how deep), the torn ground's top raised (1) or dented (-1), its block.
        fiss: i32,
        bump: i32,
        mat: &'static str,
        /// The heap's top block (the land's own surface), and whether all of it waits for the hammer's blow (the lip
        /// round where it lands: what stands there cleared and the ground torn as it lands, not as the giant rises).
        top: &'static str,
        slam: bool,
    }
    let mut sum = hv.surf.get();
    let wet_at = |x: i32, z: i32| (x >> 4) == (cols.first().map_or(x, |c| c.x) >> 4) && (z >> 4) == (cols.first().map_or(z, |c| c.z) >> 4) && wet[((z & 15) * 16 + (x & 15)) as usize];
    let mut ds: Vec<D> = Vec::with_capacity(cols.len());
    let mut most = 0;
    // (the later blows in their order: the first stance foot, the hammer's lip, the second foot)
    let order = [(hv.stomp[0], 0usize), (hv.slam, 2), (hv.stomp[1], 1)];
    for &c in &cols {
        // (what a column really costs, measured in the soak: the shape, the edge, the heap's terms and its blocks; charged at
        // a fifth of it, five or six chunks went into one stage, some 15M of fuel, and on real hills past half a tick's)
        crate::meter::spend(6_000);
        let (qv, rad, da, db) = hv.shape(c.x, c.z);
        let e = hv.edge(c.x, c.z, rad, da, db);
        let t = hv.terms(c.x, c.z, qv, rad, da, db);
        let mut v = t.rise;
        let mut h = [hv.blocks(&t, v), 0, 0, 0];
        for (k, &(_, which)) in order.iter().enumerate() {
            v = v.max(if which == 2 { t.lip } else { t.st[which] });
            h[k + 1] = hv.blocks(&t, v);
        }
        let fluid = c.w != NONE && c.w > c.g;
        let dry_round = !fluid && !wet_at(c.x + 1, c.z) && !wet_at(c.x - 1, c.z) && !wet_at(c.x, c.z + 1) && !wet_at(c.x, c.z - 1);
        let fr = if e < 40.0 {
            crate::meter::spend(2_500);
            hv.frac(c.x, c.z)
        } else {
            Frac { x: 99.0, ring: 99.0, ..Default::default() }
        };
        // (the cracks run on past the torn ground's edge into the land, and the plates' fissures split the heap)
        let crack = if e < 26.0 && dry_round { Heave::crack(&fr) } else { 0 };
        let fiss = if crack == 0 && dry_round && e < -2.0 && fr.ring < 0.55 { 1 + i32::from(fr.dj < 8.0) } else { 0 };
        if crack > 0 || fiss > 0 {
            h = [0; 4];
        }
        // (the torn ground's edge broken up: fingers along the cracks and out along streaks, patches past it, in clusters
        // of blocks rather than block by block)
        let (rx, rz) = ((c.x - hv.bx) as f32, (c.z - hv.bz) as f32);
        let dir = [qv[0] / rad.max(1.0e-3), qv[1] / rad.max(1.0e-3)];
        let streak = vs(hv.seed ^ 0x77, dir[0] * 4.5 + qv[0] * 0.03, dir[1] * 4.5 + qv[1] * 0.03);
        let patch = vs(hv.seed ^ 0x5A, rx * 0.07, rz * 0.07);
        let et = e - if fr.x < 3.0 { 22.0 * (1.0 - fr.x / 3.0) } else { 0.0 } - 14.0 * ss(0.55, 0.85, streak) - 24.0 * ss(0.72, 0.9, patch);
        let clump = 0.7 * vs(hv.seed ^ 0x33, rx * 0.18, rz * 0.18) + 0.3 * hash(c.x, c.z, 91);
        let torn = h[3] > 0 || crack > 0 || fiss > 0 || clump < 1.0 - ss(HV_TORN[0], HV_TORN[1], et);
        let strip = if torn || e < HV_STRIP + 4.0 * (hash(c.x, c.z, 92) - 0.5) {
            2
        } else if e < HV_LEAVES {
            1
        } else {
            0
        };
        if !torn && strip == 0 {
            continue;
        }
        // (what it is torn into: its plate's family, dark rock at the lips of the cracks and the fissures, patches of the
        // family's blocks a few across)
        let near = (0.22 + 0.73 * (1.0 - ss(4.0, 12.0, fr.dj))).max(0.6 * (1.0 - ss(0.0, 3.5, da)));
        let p4 = (fr.p * 31.7 + fr.p2 * 17.3).fract();
        let fam = if fr.x < 1.8 {
            0
        } else if fr.ring < 0.9 {
            if near > 0.5 { 0 } else { 2 }
        } else if p4 < near {
            ((fr.p2 * 3.0) as usize).min(2)
        } else {
            3 + (((p4 * 7.1).fract() * 5.0) as usize).min(4)
        };
        let mi = 0.8 * vs(hv.seed ^ 0x41, rx * 0.3, rz * 0.3) + 0.2 * hash(c.x, c.z, 77);
        let mk = if mi < 0.5 { 0 } else if mi < 0.75 { 1 } else { 2 };
        let mat = hv_under(c.sub, fam, mk);
        // (the heap's top the land's own surface, near the giant's feet broken through to the rock in places)
        let top = match c.top {
            Some(tb) if !(fam < 3 && c.sub == 0 && p4 < 0.5 * near) => tb,
            _ => mat,
        };
        let slam = t.rise <= 0.0 && t.st[0] <= 0.0 && t.st[1] <= 0.0 && db - 1.5 < (rad - 17.0).min(da - 0.8);
        d_count_colour(&mut sum, c.rgb, mat, under_rgb);
        let tb = fr.ramp * (0.4 + fr.p) + 0.5 * (vs(hv.seed ^ 0x6B, rx * 0.25, rz * 0.25) - 0.5);
        let bump = if tb > 1.05 && et < -4.0 { 1 } else if tb < 0.12 { -1 } else { 0 };
        most = most.max(h[0]);
        ds.push(D { c, h, torn, strip, crack, fiss, bump, mat, top, slam });
    }
    let steps = ((most + HV_LIFT - 1) / HV_LIFT).clamp(1, HV_STEPS);
    let new = Blocks::default;
    let mut lifts: Vec<Blocks> = (0..steps).map(|_| new()).collect();
    let mut later: [Blocks; 3] = [new(), new(), new()];
    // (a lift of a column's heap from `from` blocks to `to` over its base, all of it the column's block (one run): from its
    // ground, through any water, the first time; only into what is air, water or a plant by then, never into the player)
    let lift = |b: &mut Blocks, c: &C, base: i32, from: i32, to: i32, m: &'static str, top: &'static str, last: bool| {
        if from == 0 && base > c.g {
            // (the water or lava under it filled, kelp and all)
            b.put(c.x, c.z, c.g + 1, base, m, None, false);
        }
        // (its top the land's own surface, what is under it the torn earth: as a second run only on its last lift, for
        // grass; a heap of snow, sand or the like is that all through, one run)
        if HV_GRASS_TOP && !std::ptr::eq(top, m) && top == "minecraft:grass_block" && last {
            b.put(c.x, c.z, base + from + 1, base + to - 1, m, Some(HV_INTO), false);
            b.put(c.x, c.z, base + to, base + to, top, Some(HV_INTO), false);
        } else {
            b.put(c.x, c.z, base + from + 1, base + to, if top == "minecraft:grass_block" { m } else { top }, Some(HV_INTO), false);
        }
        b.clear_of_player = true;
    };
    for d in &ds {
        let c = &d.c;
        let fluid = c.w != NONE && c.w > c.g;
        let base = if fluid { c.w } else { c.g };
        let first: &mut Blocks = if HV_AT_BLOW && d.slam { &mut later[1] } else { &mut lifts[0] };
        if d.crack > 0 {
            // (a crack: the ground split open a few blocks down, and what stood over it gone)
            first.put(c.x, c.z, c.g - d.crack + 1, c.g.max(c.s), HV_AIR, None, false);
            continue;
        }
        if d.fiss > 0 {
            // (a fissure between two plates: a block or two down, dark rock at its foot)
            if c.under {
                first.put(c.x, c.z, c.g - d.fiss, c.g - d.fiss, HV_FAM[0][0], None, false);
            }
            first.put(c.x, c.z, c.g - d.fiss + 1, c.g.max(c.s), HV_AIR, None, false);
            continue;
        }
        let hs = |k: i32| (d.h[0] * k + steps / 2) / steps;
        if d.strip == 2 {
            // (all of it, before the heap goes in where it stood)
            let from = if fluid { c.w + 1 } else { c.g + 1 };
            if c.s >= from {
                first.put(c.x, c.z, from, c.s, HV_AIR, None, false);
            }
        } else if d.strip == 1 && c.s > c.g {
            first.put(c.x, c.z, c.g + 1, c.s, HV_AIR, Some("#minecraft:leaves"), false);
        }
        if d.h[3] == 0 {
            if d.torn && !fluid {
                // (the ground broken up: its top, raised a block where its plate tips up, dented where it sinks)
                if d.bump < 0 && c.under {
                    first.put(c.x, c.z, c.g, c.g, HV_AIR, None, false);
                } else {
                    first.put(c.x, c.z, c.g, c.g, d.mat, None, false);
                    if d.bump > 0 {
                        first.put(c.x, c.z, c.g + 1, c.g + 1, d.mat, Some(HV_INTO), false);
                        first.clear_of_player = true;
                    }
                }
            }
            continue;
        }
        for k in 1..=steps {
            if hs(k) > hs(k - 1) {
                lift(&mut lifts[(k - 1) as usize], c, base, hs(k - 1), hs(k), d.mat, d.top, k == steps && d.h[3] == d.h[0]);
            }
        }
        for k in 0..3 {
            if d.h[k + 1] > d.h[k] {
                lift(&mut later[k], c, base, d.h[k], d.h[k + 1], d.mat, d.top, d.h[k + 1] == d.h[3]);
            }
        }
    }
    // (the colours of what it tears up so far, for the pass's own heap; sent a few times only, as it grows: each sends the pass all of its words again)
    let was = hv.surf.get()[6];
    hv.surf.set(sum);
    if [16.0f32, 128.0, 1024.0, 8192.0].iter().any(|&k| was < k && sum[6] >= k) {
        let k = 1.0 / sum[6];
        let pack = |o: usize| (0..3).fold(0xFF00_0000u32, |w, i| w | (((sum[o + i] * k).round().clamp(0.0, 255.0) as u32) << (8 * i)));
        q.ev.push((now, Act::Words { index: (HV_COL + 2 * hv.g) as u32, words: vec![pack(0), pack(3)] }));
    }
    let t0 = t1.max(now + 0.05);
    let last = t0 + HV_GAP * (steps - 1) as f32;
    for (k, b) in lifts.into_iter().enumerate() {
        if !b.runs.is_empty() {
            q.ev.push((t0 + HV_GAP * k as f32, Act::Blocks(Box::new(b))));
        }
    }
    for (b, &(t, _)) in later.into_iter().zip(order.iter()) {
        if !b.runs.is_empty() {
            q.ev.push(((t + 0.12).max(last + 0.05), Act::Blocks(Box::new(b))));
        }
    }
}

// ---- the crater: the land the blast reaches, a chunk an edit, from the middle out ------------------------------------------
/// How far the crater's rim and rubble reach (`BD_R` the land read: `world.read-columns`; a column not loaded is done
/// by the heightmap instead, `Blocks::put`'s `surface`). Past the lobes' rim (`CR_LOBE`).
const CR_READ: f64 = CRATER_R + 70.0;
/// The rim's width past the crater's edge, and how high it is heaped at most.
const CR_RIM: f64 = 6.0 * CL_K;
const CR_RIM_H: f64 = 11.0;
/// How deep each terrace of the bowl is, on average (each slab of the wall its own, `CR_SLAB`).
const CR_STEP: f64 = 6.0;
/// The wall broken into slabs about this wide (a warped grid's cells), each stepped down its own height and offset.
const CR_SLAB: f32 = 22.0;
/// Blocks read under each column's top (a tree's height and some ground under it).
const CR_BELOW: u32 = 34;
/// When the blast's land is listed and the work on it starts: the crater's middle (which nothing else touches) read and
/// worked out early, a stage every `CR_GAP` (the giants' land gets the ticks between), the blast field past the rim
/// (`BD_*`) alongside it, a stage every tick; the
/// crater's edge, its rim and its rubble (where the giants' heaped land may reach) read from `CR_ASK`, a stage a tick; and how fast its edits run out
/// from the middle (blocks a second, from `CL_HIT` + `CR_LAG`, past `CR_READ` `BD_WAVE`): the blast's light and dust hide it as it goes in.
const CR_SETUP: f32 = 12.0;
const CR_GAP: f32 = 0.1;
const CR_ASK: f32 = 18.2;
const CR_FRONT: f64 = 140.0;
const CR_LAG: f32 = 0.15;
/// Chunks a read covers, and the meter's work a stage does at most (about a millisecond natively: the meter's figures
/// for a column, `CR_COL_READ` and `CR_COL_FAR`, are set from the game's fuel, `mod_soak`).
const CR_PART: usize = 6;
const CR_STAGE: u64 = 9_000_000;
const CR_COL_READ: u64 = 4_000;
const CR_COL_FAR: u64 = 2_000;
/// How far in a chunk lies wholly inside the crater, whatever its edge does (the edge wanders 6.75% each way, and its
/// lobes only push it out).
const CR_INNER: f64 = CRATER_R * 0.93 - 2.0;
const CR_AIR: &str = "minecraft:air";
/// The crater's edge pulled out along each of the five crack lines (lobes): at most this share of `CRATER_R`, about this
/// wide (radians), with a smaller one off to one side of each (so none is a round bulge).
const CR_LOBE: f64 = 0.16;
const CR_LOBE_W: f64 = 0.17;

// ---- the blast field past the rim, out to the giants and past them ------------------------------------------------------
/// The field the blast leaves round the crater, worked out with it a column at a time from the same reads (`cr_column`,
/// its trees laid in `bd_fell`), graded with how far a column is past the crater's (lobed) edge, every bound ragged:
/// the trees felled, lying pointing away from the middle, out to about `BD_FELL` past it; snapped and stripped bare to
/// about `BD_SNAP`; their crowns thinned from the top in patches and the snow shaken off them out to `BD_R`; the ground
/// scoured and scorched in tongues (`BdZone::scorch`), ejecta and boulders strewn in rays (`Crater::rays`), thinning out
/// past the giants; the fissures run on out of the crater, shallower and narrower, faintly green low down. None of it
/// within a statue's box or a giant's torn land (`Crater::clear`): those are the statues' and the heaves'.
const BD_R: f64 = 384.0;
const BD_FELL: f64 = 82.0;
const BD_SNAP: f64 = 150.0;
/// How fast the field's edits run on out past `CR_READ` (blocks a second): the outer land goes in over a second and a
/// half, not all on a few ticks.
const BD_WAVE: f64 = 110.0;
/// The meter's work a stage of the field does at most, and its figure for a column (set as `CR_COL_*` are).
const BD_STAGE: u64 = 11_000_000;
const BD_COL: u64 = 350;
/// A column of the field (or the crater's edge) done by the heightmap, not read: its puts are most of it (the soak's fuel).
const BD_COL_FAR: u64 = 8_000;
/// When the field's reads and stages start: once the giants are up and their land torn (what is still to come of that,
/// the stamps and the hammers' lips, is within their torn land, which the field keeps off).
const BD_SETUP: f32 = 8.0;
/// A stage of the field every this many seconds (every other tick: a tick works out one stage, and the giants' land and the
/// other stages waiting get the ticks between).
const BD_GAP: f32 = 0.1;
/// The rays the ejecta is strewn in.
const BD_RAYS: usize = 21;
/// The field's reads in hand at once (each `CR_PART` chunks, some 0.15 MB): enough that a stage does a stage's work, not
/// two parts and a wait for the next answers (the field's stages then take every tick from 8 s to the blast, and the giants'
/// land and the statues, whose stages wait behind them, run late).
const BD_AHEAD: usize = 4;
/// The same for the crater's middle and its edge.
const CR_AHEAD: usize = 3;

/// When the blast's edit of land `r` blocks from the middle goes in.
fn cr_when(r: f64) -> f32 {
    let near = r.clamp(0.0, CR_READ);
    CL_HIT + CR_LAG + (near / CR_FRONT) as f32 + ((r - near).max(0.0) / BD_WAVE) as f32
}

/// An angle brought into -PI..PI (from within a turn or two of it: no `rem_euclid`, which costs a library call in the mod).
fn wrap(a: f64) -> f64 {
    use std::f64::consts::{PI, TAU};
    let mut a = a;
    while a > PI {
        a -= TAU;
    }
    while a < -PI {
        a += TAU;
    }
    a
}

/// The crater's plan round the target: its fissures (towards each giant's blow, and a few between), its lobes, its noise,
/// the blast field's rays, what the field keeps clear of and the ground it leaves round each hammer's wreck.
struct Crater {
    bx: i32,
    bz: i32,
    ref_y: i32,
    seed: u32,
    /// its direction (a unit vector), from, to (blocks out), how wide and deep
    fis: Vec<([f64; 2], f64, f64, f64)>,
    /// The five crack lines' bearings (towards each giant's blow) and how far the edge is pulled out along each.
    main: [f64; 5],
    lobe: [f64; 5],
    /// The ejecta's rays: bearing, half width (blocks), how far out.
    rays: Vec<(f64, f64, f64)>,
    /// Each statue's box of blocks (x0, z0, x1, z1) and each giant's torn land: the field keeps off them.
    boxes: [[i32; 4]; 5],
    heaves: Vec<Heave>,
    /// Where each hammer struck (`slam_column`), and the ground the blast leaves round it as the stages work it out
    /// (`hm_*` lays the wrecks on it).
    slams: [(i32, i32); 5],
    /// (a square `2 HM_R` across round each blow, a height a column from `ref_y`, `i16::MIN` not known: small, as the
    /// mod's memory is)
    floors: RefCell<Vec<i16>>,
    /// The heaves' edge round the chunk being worked out (`heave_grid`, when it is not `free`).
    hgrid: RefCell<[f32; 25]>,
    /// The boulders that may reach the chunk being worked out (`bd_rocks`, listed as each chunk starts).
    rocks: RefCell<Vec<([f64; 2], f64, f64, f64, f64, &'static str)>>,
    /// The chunk being worked out is clear of the statues and the heaves (`chunk_free`, set as each chunk starts).
    free: std::cell::Cell<bool>,
    /// What depends only on the bearing, worked out once round the circle (`CR_TAB` steps): the lobes' pull, and the
    /// field's noises for its fell, snap and strip bounds and its scorch's tongues.
    tab: Vec<[f32; 5]>,
    /// Each fissure's wander off its line and its width's noise, a block out at a time.
    fis_tab: Vec<Vec<[f32; 2]>>,
    /// For each of `CR_BINS` bearings, the fissures whose line comes within 0.45 radians of it (past 60 blocks out no
    /// other can be near: a fissure is never more than 24 off its line), and the ray nearest it.
    fis_bin: Vec<Vec<u8>>,
    ray_bin: Vec<u8>,
    fis_all: Vec<u8>,
}
const CR_BINS: usize = 1024;
const CR_TAB: usize = 2048;
/// What the crater is at a column: how far out, its edge's radius there, the bowl's depth under the target's ground, a
/// fissure's depth there (0 none), how near its middle (0..1), whether the column is on a fissure's dark lip, and the
/// wall's slab: how far up its step (0..1: from 0.62 a riser, under 0.18 the foot of the one above).
struct CrAt {
    rc: f64,
    rw: f64,
    d: f64,
    fd: i32,
    fc: f64,
    lip: bool,
    step: f64,
    /// Its bearing (0..TAU) and that bearing's `Crater::tab`.
    ang: f64,
    tb: [f32; 5],
}
/// How the blast field takes a column (blocks past the crater's edge each bound lies, ragged): trees felled inside `fell`,
/// snapped and stripped inside `snap`, thinned inside `strip`; `scorch` how hard the ground is burnt (above 0 burnt), `ray`
/// how much ejecta falls there (0..1).
struct BdZone {
    fell: f64,
    snap: f64,
    strip: f64,
    scorch: f64,
    ray: f64,
}
/// The radius the wrecks' ground is kept within, round each hammer's blow.
const HM_R: i32 = 64;
const HM_W: usize = 2 * HM_R as usize + 1;
impl Crater {
    fn new(t: &Target) -> Crater {
        let seed = (t.block[0] as u32).wrapping_mul(0x9E37_79B9) ^ (t.block[2] as u32).wrapping_mul(0x85EB_CA6B) ^ 0xC4A7_0001;
        let mut fis = Vec::new();
        let mut main = [0.0; 5];
        let mut lobe = [0.0; 5];
        let mut boxes = [[0; 4]; 5];
        let mut slams = [(0, 0); 5];
        for (g, st) in statues().iter().enumerate() {
            let [x, z] = slam_point(t, g, st);
            main[g] = z.atan2(x);
            lobe[g] = CR_LOBE * (0.6 + 0.4 * f64::from(hash(g as i32, 61, seed)));
            let (ox, oz) = corner(t, g, st);
            let (ox, oz) = (ox + i32::from(st.pshift[0]), oz + i32::from(st.pshift[2]));
            boxes[g] = [ox, oz, ox + i32::from(st.pgrid[0]) - 1, oz + i32::from(st.pgrid[2]) - 1];
            slams[g] = slam_column(t, g, st);
        }
        for (k, &a) in main.iter().enumerate() {
            // (on out through the rim towards the giant, shallower and narrower past the edge: `at`)
            fis.push(([a.cos(), a.sin()], 8.0, CRATER_R + 100.0, 1.0));
            if hash(k as i32, 3, seed) < 0.8 {
                let b = a + std::f64::consts::TAU / 10.0 + (f64::from(hash(k as i32, 4, seed)) - 0.5) * 0.35;
                fis.push(([b.cos(), b.sin()], 0.3 * CRATER_R, CRATER_R + 125.0, 0.6));
            }
            // (and one that opens only past the rim, out between the giants)
            let c = a - std::f64::consts::TAU / 10.0 + (f64::from(hash(k as i32, 8, seed)) - 0.5) * 0.4;
            fis.push(([c.cos(), c.sin()], CRATER_R * 0.85, CRATER_R + 95.0 + 40.0 * f64::from(hash(k as i32, 9, seed)), 0.45));
        }
        let rays: Vec<(f64, f64, f64)> = (0..BD_RAYS)
            .map(|k| {
                let u = |j: i32| f64::from(unit(seed ^ 0x5A75, k as i32, j, 0));
                ((k as f64 + 0.5 + 0.7 * (u(1) - 0.5)) / BD_RAYS as f64 * std::f64::consts::TAU, 5.0 + 11.0 * u(2), CRATER_R + 110.0 + 150.0 * u(3).powf(0.7))
            })
            .collect();
        let heaves = (0..5).map(|g| Heave::new(t, g)).collect();
        let tab = (0..CR_TAB)
            .map(|i| {
                let ang = i as f64 / CR_TAB as f64 * std::f64::consts::TAU;
                let (c, s) = (ang.cos() as f32, ang.sin() as f32);
                let mut l = 0.0;
                for k in 0..5 {
                    let da = wrap(ang - main[k]) / CR_LOBE_W;
                    let db = (wrap(ang - main[k]) - 0.28 * if k % 2 == 0 { 1.0 } else { -1.0 }) / (0.6 * CR_LOBE_W);
                    l += lobe[k] * ((-da * da).exp() + 0.45 * (-db * db).exp());
                }
                // (the scorch's tongues: two noises round the circle, raised to a power so a few reach far and most stop short)
                let t1 = n2(seed ^ 81, 4.0 + 3.0 * c, 4.0 + 3.0 * s);
                let t2 = n2(seed ^ 82, 11.0 + 9.0 * c, 11.0 + 9.0 * s);
                // (and the edge's wobble: two noises round the circle)
                let wob = n2(seed, 2.5 + 2.5 * c, 2.5 + 2.5 * s) + 0.5 * n2(seed ^ 7, 7.0 + 6.0 * c, 7.0 + 6.0 * s) - 0.75;
                [l as f32, n2(seed ^ 71, 3.0 + 2.2 * c, 3.0 + 2.2 * s), n2(seed ^ 72, 9.0 + 5.5 * c, 9.0 + 5.5 * s), 55.0 + 190.0 * t1 * t1 + 110.0 * t2 * t2 * t2, wob]
            })
            .collect();
        let fis_tab = (0..fis.len())
            .map(|k| {
                let ks = seed ^ (31 + k as u32);
                (0..=BD_R as usize)
                    .map(|r| {
                        let rc = r as f32 + 0.5;
                        [9.0 * (n2(ks, rc * 0.035, 3.0) - 0.5) + 3.0 * (n2(ks, rc * 0.13, 9.0) - 0.5), n2(ks ^ 5, rc * 0.05, 1.0)]
                    })
                    .collect()
            })
            .collect();
        let fang: Vec<f64> = fis.iter().map(|f| f.0[1].atan2(f.0[0])).collect();
        let fis_bin = (0..CR_BINS)
            .map(|i| {
                let ang = (i as f64 + 0.5) / CR_BINS as f64 * std::f64::consts::TAU;
                (0..fis.len()).filter(|&k| wrap(ang - fang[k]).abs() < 0.45 + std::f64::consts::PI / CR_BINS as f64).map(|k| k as u8).collect()
            })
            .collect();
        let ray_bin = (0..CR_BINS)
            .map(|i| {
                let ang = (i as f64 + 0.5) / CR_BINS as f64 * std::f64::consts::TAU;
                (0..BD_RAYS).min_by(|&a, &b| wrap(ang - rays[a].0).abs().total_cmp(&wrap(ang - rays[b].0).abs())).unwrap_or(0) as u8
            })
            .collect();
        let fis_all = (0..fis.len() as u8).collect();
        crate::meter::spend(1_000_000 + 4_000 * CR_TAB as u64 + 1_000 * 400 * fis.len() as u64 + 3_000 * CR_BINS as u64);
        Crater { bx: t.block[0], bz: t.block[2], ref_y: t.block[1], seed, fis, main, lobe, rays, boxes, heaves, slams, floors: RefCell::new(vec![i16::MIN; 5 * HM_W * HM_W]), free: std::cell::Cell::new(false), rocks: RefCell::default(), hgrid: RefCell::new([f32::MAX; 25]), tab, fis_tab, fis_bin, ray_bin, fis_all }
    }
    /// The bearing's entry of `tab`.
    fn tab(&self, ang: f64) -> [f32; 5] {
        let u = ang / std::f64::consts::TAU * CR_TAB as f64;
        self.tab[(u as usize).min(CR_TAB - 1)]
    }
    fn at(&self, x: i32, z: i32) -> CrAt {
        let (dx, dz) = (f64::from(x - self.bx), f64::from(z - self.bz));
        let rc = (dx * dx + dz * dz).sqrt();
        // (past the field only how far out matters)
        if rc > BD_R {
            return CrAt { rc, rw: CRATER_R, d: 0.0, fd: 0, fc: 0.0, lip: false, step: 0.0, ang: 0.0, tb: [0.0; 5] };
        }
        // (a ragged edge: two noises round the circle; and pulled out in lobes along the five cracks, each with a smaller
        // one beside it, the edge between them pinched: `tab`)
        let ang = dz.atan2(dx);
        let ang = if ang < 0.0 { ang + std::f64::consts::TAU } else { ang };
        let tb = self.tab(ang);
        let rw = CRATER_R * (1.0 + 0.09 * f64::from(tb[4]) + f64::from(tb[0]));
        let (fx, fz) = (x as f32, z as f32);
        let u = rc / rw;
        let (mut d, mut step) = (0.0, 0.0);
        if u < 1.0 {
            // (a bowl broken into slabs: the cells of a warped grid, each stepped down its own height from its own offset, so
            // the ledges break off at different heights from one slab to the next; a deeper pit in the middle)
            // (about (1 - u²)^0.8, of square roots: a power costs a library call in the mod)
            let v = 1.0 - u * u;
            let base = CRATER_D * v.sqrt() * v.sqrt().sqrt();
            let na = n2(self.seed ^ 41, fx * 0.04, fz * 0.04) - 0.5;
            let (wx, wz) = (fx + 10.0 * na, fz - 10.0 * na);
            let (px, pz) = ((wx / CR_SLAB).floor() as i32, (wz / CR_SLAB).floor() as i32);
            let sh = CR_STEP * f64::from(0.65 + 0.8 * hash(px, pz, self.seed ^ 43));
            let off = f64::from(hash(px, pz, self.seed ^ 44));
            let st = base / sh + off + 0.6 * f64::from(na);
            let fl = st.floor();
            step = st - fl;
            d = sh * (fl - off + f64::from(ss(0.62, 1.0, step as f32))) + 1.2 * f64::from(hash(x >> 1, z >> 1, self.seed ^ 45) - 0.5);
            if rc < 16.0 {
                d += 8.0 * (1.0 - rc / 16.0);
            }
            d = d.max(1.0);
        }
        // (the fissures, wandering a little off their lines, tapering at their ends; past the crater's edge narrower and
        // shallower the further out)
        let (mut fd, mut fc, mut lip) = (0, 0.0, false);
        let out = f64::from(ss(0.0, 110.0, (rc - rw) as f32));
        let bin = ((ang / std::f64::consts::TAU * CR_BINS as f64) as usize).min(CR_BINS - 1);
        let near: &[u8] = if rc < 60.0 { &self.fis_all } else { &self.fis_bin[bin] };
        for &k in near {
            let k = usize::from(k);
            let ([ux, uz], r0, r1, wk) = self.fis[k];
            if rc < r0 || rc > r1 {
                continue;
            }
            // (a fissure is never more than a dozen blocks off its line)
            let along = dx * ux + dz * uz;
            let side = dz * ux - dx * uz;
            if along <= 0.0 || side.abs() > 24.0 {
                continue;
            }
            let [off, wn] = self.fis_tab[k][(rc as usize).min(BD_R as usize)];
            let off = f64::from(off);
            let lat = (side - off).abs();
            let taper = f64::from(ss(r0 as f32, r0 as f32 + 16.0, rc as f32) * (1.0 - ss(r1 as f32 - 40.0, r1 as f32, rc as f32)));
            // (wide enough to read from far off and from above: 6-15 across in the crater, deep, a dark lip along each side)
            let w = wk * (3.4 + 4.2 * f64::from(wn)) * (0.35 + 0.65 * taper) * (1.0 - 0.6 * out);
            if taper <= 0.0 {
                continue;
            }
            if lat < w {
                let cc = 1.0 - lat / w;
                if cc > fc {
                    fc = cc;
                    fd = ((4.0 + 16.0 * cc.sqrt() * taper * wk) * (1.0 - 0.55 * out)).round() as i32;
                }
            } else if lat < w + 1.5 + 1.5 * f64::from(hash(x, z, 29)) {
                lip = true;
            }
        }
        crate::meter::spend(250);
        CrAt { rc, rw, d, fd, fc, lip, step, ang, tb }
    }
    /// Whether column (x, z) lies outside every statue's box (and a margin): a wreck's block may go there.
    fn clear_box(&self, x: i32, z: i32) -> bool {
        !self.boxes.iter().any(|b| x >= b[0] - 3 && x <= b[2] + 3 && z >= b[1] - 3 && z <= b[3] + 3)
    }
    /// Whether no column of chunk (cx, cz) can be within a statue's box or a giant's torn land (then `clear` need not
    /// look): its middle's distance from each heave's edge, less the edge's raggedness and the chunk's half diagonal.
    fn chunk_free(&self, cx: i32, cz: i32) -> bool {
        let (x0, z0) = (cx * 16, cz * 16);
        crate::meter::spend(5 * 6_000);
        if self.boxes.iter().any(|b| x0 + 15 >= b[0] - 3 && x0 <= b[2] + 3 && z0 + 15 >= b[1] - 3 && z0 <= b[3] + 3) {
            return false;
        }
        self.heaves.iter().all(|hv| {
            let (_, rad, da, db) = hv.shape(x0 + 8, z0 + 8);
            (rad - 17.0).min(da - 0.8).min(db - 1.5) * hv.sc > 6.0 + 13.5 + 2.0 * 0.7 * hv.sc + 12.0
        })
    }
    /// Whether the blast field may change column (x, z): not within a statue's box (and a margin) or a giant's torn land.
    fn clear(&self, x: i32, z: i32) -> bool {
        if self.free.get() {
            return true;
        }
        for b in &self.boxes {
            if x >= b[0] - 3 && x <= b[2] + 3 && z >= b[1] - 3 && z <= b[3] + 3 {
                return false;
            }
        }
        // (the heaves' edge as `heave_grid` sampled it round the chunk, between its points)
        let g = self.hgrid.borrow();
        let (u, v) = ((x & 15) as f32 / 4.0, (z & 15) as f32 / 4.0);
        let (i, k) = ((u as usize).min(3), (v as usize).min(3));
        let (fu, fv) = (u - i as f32, v - k as f32);
        let at = |i: usize, k: usize| g[k * 5 + i];
        let e = (at(i, k) * (1.0 - fu) + at(i + 1, k) * fu) * (1.0 - fv) + (at(i, k + 1) * (1.0 - fu) + at(i + 1, k + 1) * fu) * fv;
        e >= 6.0 + 4.0
    }
    /// The heaves' edge (`Heave::edge`, the least of the giants near) at every fourth column round chunk (cx, cz), for `clear`
    /// (a column of torn land is some thirty times the work of the rest of `clear`).
    fn heave_grid(&self, cx: i32, cz: i32) {
        let mut g = [f32::MAX; 25];
        for (n, e) in g.iter_mut().enumerate() {
            let (x, z) = (cx * 16 + 4 * (n % 5) as i32, cz * 16 + 4 * (n / 5) as i32);
            for hv in &self.heaves {
                let (px, pz) = ((x - self.bx) as f32 - hv.o[0], (z - self.bz) as f32 - hv.o[1]);
                if px * px + pz * pz > 260.0 * 260.0 {
                    continue;
                }
                let (_, rad, da, db) = hv.shape(x, z);
                *e = e.min(hv.edge(x, z, rad, da, db));
            }
        }
        crate::meter::spend(25 * 5 * 6_000);
        *self.hgrid.borrow_mut() = g;
    }
    /// The field's bounds and strengths at column (x, z), `rc` out and `e` past the edge.
    fn zone(&self, x: i32, z: i32, a: &CrAt) -> BdZone {
        let (rc, e, tb, ang) = (a.rc, a.rc - a.rw, a.tb, a.ang);
        let (fx, fz) = (x as f32, z as f32);
        let (n1, n2b) = (f64::from(tb[1]), f64::from(tb[2]));
        let nf = f64::from(n2(self.seed ^ 73, fx * 0.05, fz * 0.05)) - 0.5;
        let rw = rc - e;
        let fell = BD_FELL * (0.7 + 0.6 * n1) + 24.0 * nf;
        let snap = BD_SNAP * (0.78 + 0.45 * n2b) + 34.0 * nf;
        let strip = BD_R - 12.0 - 40.0 * n1 - rw + 20.0 * nf;
        // (the scorch in tongues: how far each bearing's tongue reaches, `tab`; its edge broken up by noise on the land)
        let tl = f64::from(tb[3]);
        let mut scorch = 1.0 - e / tl + 0.5 * nf;
        if scorch.abs() < 0.12 {
            scorch += 0.12 * (f64::from(n2(self.seed ^ 84, fx * 0.23, fz * 0.23)) - 0.5);
        }
        // (the rays nearest this bearing: they lie a bin each round the circle)
        let bin = ((ang / std::f64::consts::TAU * CR_BINS as f64) as usize).min(CR_BINS - 1);
        let mut ray: f64 = 0.0;
        let _ = ang;
        {
            let (a, w, reach) = self.rays[usize::from(self.ray_bin[bin])];
            // (across the ray a smooth hump, lat its distance off the ray's line, to nothing at its ends)
            let v = rc * wrap(ang - a).abs() / (w * (0.7 + 0.6 * rc / BD_R));
            if v < 1.6 {
                let m = 1.0 - v * v / 2.56;
                let end = if rc > reach - 70.0 { 1.0 - f64::from(ss((reach - 70.0) as f32, reach as f32, rc as f32)) } else { 1.0 };
                ray = m * m * end;
            }
        }
        crate::meter::spend(300);
        BdZone { fell, snap, strip, scorch, ray }
    }
    /// Whether column (x, z) is near a hammer's blow (its ground is kept for the wreck).
    fn near_slam(&self, x: i32, z: i32) -> bool {
        self.floor_at(x, z).is_some()
    }
    /// Where column (x, z)'s ground is kept in `floors` (within `HM_R` of a blow, each way).
    fn floor_at(&self, x: i32, z: i32) -> Option<usize> {
        self.slams.iter().enumerate().find_map(|(g, &(sx, sz))| {
            let (i, k) = (x - sx + HM_R, z - sz + HM_R);
            ((0..HM_W as i32).contains(&i) && (0..HM_W as i32).contains(&k)).then(|| (g * HM_W + k as usize) * HM_W + i as usize)
        })
    }
}

/// What the blocks a read saw are: `kind` 0 air, 1 water and lava, 2 leaves, 3 anything else standing (plants, what was
/// built), 4 ground, 5 what is kept (`hv_kind`), 6 grass on the ground, 7 a tree's logs (`#minecraft:logs`), 8 snow
/// lying (`minecraft:snow`), 9 soft ground (dirt and the like, snow blocks, moss): what the blast clears exactly. `wood`
/// a log's or leaves' tree (`BD_WOODS`, 255 none), `own` the stone a ground block stands for in the crater's walls.
struct CrPal {
    kind: Vec<u8>,
    wood: Vec<u8>,
    own: Vec<Option<&'static str>>,
}
fn cr_kinds(palette: &[String]) -> CrPal {
    let mut p = CrPal { kind: Vec::new(), wood: Vec::new(), own: Vec::new() };
    for name in palette {
        let n = name.strip_prefix("minecraft:").unwrap_or(name);
        let n = n.split('[').next().unwrap_or(n);
        let k = if n == "grass_block" {
            6
        } else if n.ends_with("_log") || n.ends_with("_wood") || n.ends_with("_stem") || n.ends_with("_hyphae") {
            7
        } else if n == "snow" {
            8
        } else {
            match hv_kind(name) {
                4 if matches!(n, "dirt" | "coarse_dirt" | "podzol" | "mycelium" | "rooted_dirt" | "mud" | "moss_block" | "pale_moss_block" | "snow_block" | "farmland" | "dirt_path") => 9,
                k => k,
            }
        };
        let tree = n.ends_with("_log") || n.ends_with("_leaves") || n.ends_with("_wood");
        let wood = BD_WOODS.iter().position(|w| tree && n.starts_with(w) && n[w.len()..].starts_with('_'));
        // (the stone under the land, for the crater's upper walls)
        let own = match n {
            "stone" | "andesite" | "diorite" | "granite" | "tuff" | "calcite" | "deepslate" | "gravel" | "sandstone" | "terracotta" | "red_sandstone" => {
                Some(BD_OWN.iter().copied().find(|o| o.strip_prefix("minecraft:") == Some(n)).unwrap_or("minecraft:stone"))
            }
            "sand" => Some("minecraft:sandstone"),
            "red_sand" => Some("minecraft:red_sandstone"),
            _ if n.ends_with("terracotta") => Some("minecraft:terracotta"),
            _ => None,
        };
        p.kind.push(k);
        p.wood.push(wood.map_or(255, |w| w as u8));
        p.own.push(own);
    }
    p
}
const BD_OWN: [&str; 11] = [
    "minecraft:stone", "minecraft:andesite", "minecraft:diorite", "minecraft:granite", "minecraft:tuff", "minecraft:calcite", "minecraft:deepslate",
    "minecraft:gravel", "minecraft:sandstone", "minecraft:terracotta", "minecraft:red_sandstone",
];
/// The trees a felled log may be, and their logs lying along x and z and their crushed leaves (payload.rs's lists).
const BD_WOODS: [&str; 9] = ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "pale_oak"];
const BD_LOG_X: [&str; 9] = [
    "minecraft:oak_log[axis=x]", "minecraft:spruce_log[axis=x]", "minecraft:birch_log[axis=x]", "minecraft:jungle_log[axis=x]", "minecraft:acacia_log[axis=x]",
    "minecraft:dark_oak_log[axis=x]", "minecraft:mangrove_log[axis=x]", "minecraft:cherry_log[axis=x]", "minecraft:pale_oak_log[axis=x]",
];
const BD_LOG_Z: [&str; 9] = [
    "minecraft:oak_log[axis=z]", "minecraft:spruce_log[axis=z]", "minecraft:birch_log[axis=z]", "minecraft:jungle_log[axis=z]", "minecraft:acacia_log[axis=z]",
    "minecraft:dark_oak_log[axis=z]", "minecraft:mangrove_log[axis=z]", "minecraft:cherry_log[axis=z]", "minecraft:pale_oak_log[axis=z]",
];
const BD_LEAVES: [&str; 9] = [
    "minecraft:oak_leaves[persistent=true]", "minecraft:spruce_leaves[persistent=true]", "minecraft:birch_leaves[persistent=true]",
    "minecraft:jungle_leaves[persistent=true]", "minecraft:acacia_leaves[persistent=true]", "minecraft:dark_oak_leaves[persistent=true]",
    "minecraft:mangrove_leaves[persistent=true]", "minecraft:cherry_leaves[persistent=true]", "minecraft:pale_oak_leaves[persistent=true]",
];

fn cr_pick(list: &[&'static str], h: f32) -> &'static str {
    list[((h * list.len() as f32) as usize).min(list.len() - 1)]
}
const CR_DEEP: [&str; 8] = [
    "minecraft:deepslate", "minecraft:deepslate", "minecraft:deepslate", "minecraft:cobbled_deepslate", "minecraft:cobbled_deepslate",
    "minecraft:blackstone", "minecraft:basalt", "minecraft:tuff",
];
const CR_MID: [&str; 7] = ["minecraft:tuff", "minecraft:tuff", "minecraft:deepslate", "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:basalt", "minecraft:andesite"];
const CR_HIGH: [&str; 7] = ["minecraft:stone", "minecraft:cobblestone", "minecraft:tuff", "minecraft:stone", "minecraft:gravel", "minecraft:coarse_dirt", "minecraft:andesite"];
const CR_RUBBLE: [&str; 7] = ["minecraft:coarse_dirt", "minecraft:gravel", "minecraft:tuff", "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:dirt"];
const CR_HEAP: [&str; 5] = ["minecraft:dirt", "minecraft:stone", "minecraft:cobblestone", "minecraft:tuff", "minecraft:dirt"];
/// The green the cracks leave in the stone: a fissure's bed, a few pools in the pit (sparing: the light is the froglight).
const CR_GLOW: &str = "minecraft:verdant_froglight";
const CR_VEIN: &str = "minecraft:dark_prismarine";
/// A fissure's dark lips, and the faces the blast blackened.
const CR_LIP: [&str; 5] = ["minecraft:blackstone", "minecraft:basalt", "minecraft:blackstone", "minecraft:cobbled_deepslate", "minecraft:polished_blackstone"];
const CR_BURNT: [&str; 6] = ["minecraft:blackstone", "minecraft:basalt", "minecraft:smooth_basalt", "minecraft:cobbled_deepslate", "minecraft:blackstone", "minecraft:deepslate"];
/// The rim's overturned top: the land's own earth, broken rock through it.
const CR_EJECTA: [&str; 7] = ["minecraft:coarse_dirt", "minecraft:dirt", "minecraft:rooted_dirt", "minecraft:coarse_dirt", "minecraft:gravel", "minecraft:cobblestone", "minecraft:tuff"];
/// The boulders the blast throws out: rock from deep down near the crater, more of the land's own further out.
const BD_ROCK: [&str; 8] = [
    "minecraft:cobbled_deepslate", "minecraft:deepslate", "minecraft:tuff", "minecraft:blackstone", "minecraft:stone", "minecraft:cobblestone", "minecraft:andesite", "minecraft:stone",
];
/// The ground the blast burns: hard (blackened), then charred, then singed.
const BD_CHAR: [&str; 4] = ["minecraft:blackstone", "minecraft:basalt", "minecraft:coal_block", "minecraft:smooth_basalt"];
const BD_SCORCH: [&str; 4] = ["minecraft:coarse_dirt", "minecraft:podzol", "minecraft:coarse_dirt", "minecraft:gravel"];
const BD_SINGE: [&str; 3] = ["minecraft:coarse_dirt", "minecraft:rooted_dirt", "minecraft:dirt"];
/// How steeply high land is cut back from the crater's edge (blocks up for each block out).
const CR_SLOPE: f64 = 1.1;

/// A fissure's bed: glowing down its middle, veined and dark towards its sides (in the crater, the glow a seam a few
/// blocks wide down in the slit, set back from the floor by the fissure's depth; past the edge a faint thread, froglight
/// only now and then, low down).
fn cr_fissure_bed(fc: f64, h2: f32) -> &'static str {
    if fc > 0.45 && h2 < 0.9 {
        CR_GLOW
    } else if fc > 0.2 && h2 < 0.75 {
        CR_VEIN
    } else if h2 < 0.35 {
        "minecraft:sculk"
    } else {
        "minecraft:blackstone"
    }
}
fn bd_fissure_bed(fc: f64, h2: f32) -> &'static str {
    if fc > 0.7 && h2 < 0.35 {
        CR_GLOW
    } else if fc > 0.4 && h2 < 0.6 {
        "minecraft:sculk"
    } else if fc > 0.2 && h2 < 0.5 {
        CR_VEIN
    } else {
        "minecraft:blackstone"
    }
}
/// The crater's stone at column (x, z), height y, `q` its depth's share of the crater's: the land's own stone near the
/// top, tuff and stone under it, deepslate and blackstone deep down, in strata and patches (a noise picks, a few columns
/// dithered from the next band down), not one grey.
fn cr_stone(seed: u32, x: i32, y: i32, z: i32, q: f32, own: Option<&'static str>) -> &'static str {
    let (fx, fy, fz) = (x as f32, y as f32, z as f32);
    let m = n2(seed ^ 52, fx * 0.08 + fy * 0.23, fz * 0.08 - fy * 0.07);
    let q = q + 0.2 * (m - 0.5) + if hash(x, z, 52) < 0.12 { 0.12 } else { 0.0 };
    let m = (m * 3.7).fract();
    if q < 0.1 {
        own.unwrap_or_else(|| cr_pick(&CR_HIGH, m))
    } else if q < 0.3 {
        cr_pick(&CR_HIGH, m)
    } else if q < 0.58 {
        cr_pick(&CR_MID, m)
    } else {
        cr_pick(&CR_DEEP, m)
    }
}

/// What `cr_column` leaves at a column for the passes after it: the ground's top once its edit is in (none: by the
/// heightmap), whether a log or a stone may lie on it (dry, nothing left standing, not kept clear), and a tree felled
/// there (its trunk's height, its wood, its leaves' wood; 0 / 255 none).
#[derive(Clone, Copy)]
struct CrOut {
    top: Option<i32>,
    open: bool,
    fell: u8,
    wood: u8,
    leaves: u8,
}
impl Default for CrOut {
    fn default() -> Self {
        CrOut { top: None, open: false, fell: 0, wood: 255, leaves: 255 }
    }
}

/// Column (x, z) of the blast's land into `b`: read (its top and its blocks, bottom first, `CR_BELOW` of them, and their
/// kinds) or not (then by the heightmap); its ground kept for the hammers' wrecks near their blows.
fn cr_column(b: &mut Blocks, cr: &Crater, x: i32, z: i32, read: Option<(i32, &[u16])>, pal: &CrPal) -> CrOut {
    let out = cr_column_in(b, cr, x, z, read, pal);
    if let Some(top) = out.top
        && cr.near_slam(x, z)
    {
        if let Some(i) = cr.floor_at(x, z) {
            cr.floors.borrow_mut()[i] = (top - cr.ref_y).clamp(-30_000, 30_000) as i16;
        }
    }
    out
}
fn cr_column_in(b: &mut Blocks, cr: &Crater, x: i32, z: i32, read: Option<(i32, &[u16])>, pal: &CrPal) -> CrOut {
    let a = cr.at(x, z);
    let mut out = CrOut::default();
    if a.rc >= BD_R {
        return out;
    }
    let kinds = &pal.kind;
    let e = a.rc - a.rw;
    let h = hash(x, z, 5);
    let h2 = hash(x, z, 6);
    let (fx, fz) = (x as f32, z as f32);
    let ground = read.and_then(|(base, bl)| bl.iter().rposition(|&p| matches!(kinds[p as usize], 4 | 6 | 9)).map(|i| (base, bl, i)));
    let Some((base, bl, gi)) = ground else {
        // (by the heightmap: one above each column's highest block that blocks motion, a tree's top log, a lake's water)
        if a.rc < a.rw {
            let d = (a.d.round() as i32).max(1) + a.fd;
            b.put(x, z, -d, 60, CR_AIR, None, true);
            b.put(x, z, -d - 1, -d - 1, cr_pick(&CR_DEEP, h), None, true);
            return out;
        }
        // (a trunk down from its top, the leaves round it or over open ground and the snow on them, out to where the trees
        // are snapped; the land scorched in its tongues)
        // (only out to TREE_R, and only what matters most: a land that never loads must not fill the mod's memory with
        // edits, a few runs a column for thousands of chunks)
        if a.rc >= TREE_R {
            return out;
        }
        let zn = cr.zone(x, z, &a);
        if e < zn.fell {
            b.put(x, z, -34, -1, CR_AIR, Some("#minecraft:logs"), true);
        }
        if e < zn.snap {
            b.put(x, z, -34, 30, CR_AIR, Some("#minecraft:leaves"), true);
            b.put(x, z, -34, 30, CR_AIR, Some("minecraft:snow"), true);
        }
        if zn.scorch > 0.3 && e < zn.fell && cr.clear(x, z) {
            b.put(x, z, -1, -1, if zn.scorch > 0.55 { cr_pick(&BD_CHAR, h) } else { cr_pick(&BD_SCORCH, h) }, Some("minecraft:grass_block"), true);
        }
        return out;
    };
    let y0 = base - CR_BELOW as i32;
    let g = y0 + gi as i32;
    let top = base - 1;
    let own = bl[..=gi].iter().find_map(|&p| pal.own[p as usize]);
    if a.rc < a.rw {
        // the bowl: everything over its floor gone (up to the column's own top, and a little over it near the edge, where
        // the land heaved round a giant may have come up since it was read), its floor and walls lined
        let d = a.d.round() as i32;
        let floor = (cr.ref_y - d).min(g - (f64::from(d) * 0.25).max(1.0) as i32) - a.fd;
        let over = if a.rc > a.rw - 10.0 { 24 } else { 0 };
        b.run(x, z, floor + 1, top.max(g) + over, CR_AIR);
        let q = (f64::from(cr.ref_y - floor) / CRATER_D) as f32;
        let pool = a.rc < 0.4 * CRATER_R && n2(cr.seed ^ 5, fx * 0.12, fz * 0.12) > 0.84;
        // (the risers' faces blackened by the blast, in patches; the middle scorched more)
        let riser = a.fd == 0 && a.step > 0.6;
        let burnt = n2(cr.seed ^ 55, fx * 0.09, fz * 0.09) + if a.rc < 0.35 * CRATER_R { 0.25 } else { 0.0 } > 0.55;
        let face = if a.fc > 0.0 {
            cr_fissure_bed(a.fc, h2)
        } else if a.lip {
            cr_pick(&CR_LIP, h)
        } else if pool && h2 < 0.7 {
            CR_GLOW
        } else if burnt && (riser || h2 < 0.3) {
            cr_pick(&CR_BURNT, n2(cr.seed ^ 56, fx * 0.2, fz * 0.2))
        } else {
            cr_stone(cr.seed, x, floor, z, q, own)
        };
        b.run(x, z, floor, floor, face);
        if a.fc > 0.0 {
            b.run(x, z, floor - 4, floor - 1, "minecraft:blackstone");
        } else if riser {
            // (a riser's face shows down to the tread under it: its stone in two strata, blackened where the blast burnt it)
            let split = floor - 2 - (h2 * 3.0) as i32;
            let upper = if burnt && h < 0.6 { cr_pick(&CR_BURNT, hash(x, z, 58)) } else { face };
            b.run(x, z, split + 1, floor - 1, upper);
            b.run(x, z, floor - 7, split, cr_stone(cr.seed, x, split - 2, z, q + 0.08, own));
        } else {
            b.run(x, z, floor - 4, floor - 1, if q > 0.4 { "minecraft:deepslate" } else { "minecraft:tuff" });
        }
        let mut topy = floor;
        // (rubble slid down to the foot of each wall, in clumps: 1-3 high)
        if a.fd == 0 && !a.lip && a.step < 0.2 && a.rc > 18.0 {
            let n = n2(cr.seed ^ 53, fx * 0.13, fz * 0.13);
            if n > 0.5 {
                let hh = 1 + ((n - 0.5) * 6.0 * (1.0 - a.step as f32 * 4.0)) as i32;
                b.run(x, z, floor + 1, floor + hh, cr_pick(&CR_RUBBLE, hash(x, z, 59)));
                topy = floor + hh;
            }
        }
        out.top = Some(topy);
        return out;
    }
    // past the edge: the trees and what grows felled, snapped or stripped as the field says, exactly where they stand and by
    // a filter each (the land heaved round a giant may have been laid there since the read)
    let rimw = e < CR_RIM;
    let zn = cr.zone(x, z, &a);
    let clear = cr.clear(x, z);
    let wet = bl[gi + 1..].iter().any(|&p| kinds[p as usize] == 1);
    let kept = bl.iter().any(|&p| kinds[p as usize] == 5);
    let mut trunk = 0;
    while gi + 1 + trunk < bl.len() && kinds[bl[gi + 1 + trunk] as usize] == 7 {
        trunk += 1;
    }
    let wood = if trunk > 0 { pal.wood[bl[gi + 1] as usize] } else { 255 };
    let leaves = bl[gi + 1..].iter().find(|&&p| kinds[p as usize] == 2).map_or(255, |&p| pal.wood[p as usize]);
    // (felled: inside its bound, and some knocked flat further out, fewer the further; stripped bare to the snap bound, the
    // trunks broken off at their own heights; thinned from the top past it, in patches)
    let knock = e < zn.snap && f64::from(unit(cr.seed ^ 0x91, x, 1, z)) < {
        let v = (1.0 - (e - zn.fell) / (zn.snap - zn.fell).max(1.0)).max(0.0);
        0.5 * v * v.sqrt()
    };
    let fell = rimw || e < zn.fell || knock;
    let snapped = !fell && e < zn.snap;
    let pstrip = (1.0 - (e - zn.snap) / (zn.strip - zn.snap).max(1.0)).clamp(0.0, 1.0);
    let stripped = fell || snapped || (e < zn.strip && f64::from(vs(cr.seed ^ 0x93, fx * 0.16, fz * 0.16)) < 0.2 + 0.7 * pstrip);
    let stump = if fell && !rimw && trunk > 0 { 1 + i32::from(h > 0.55) } else { 0 };
    let snap_at = 3 + (f64::from(h) * 6.0) as i32;
    let keep_h = if fell || snapped { 0 } else { ((f64::from(top - g)) * (1.0 - (0.3 + 0.7 * pstrip).min(1.0))).floor() as i32 };
    // (each kind cleared by one run over the span it is to go from, its filter leaving what lies between: a crown's
    // layers of leaves and snow are one run each, not one a layer: a land of thousands of chunks of edits waits in the
    // mod's memory till it goes in)
    let mut standing = false;
    let mut span = [(i32::MAX, i32::MIN); 4];
    for (i, &p) in bl.iter().enumerate().skip(gi + 1) {
        let y = y0 + i as i32;
        let k = kinds[p as usize];
        let (slot, go) = match k {
            // (the trunk kept to its stump, or snapped; the logs of the crown with it)
            7 => (0, if fell { y >= g + 1 + stump } else { snapped && y > g + snap_at }),
            2 => (1, stripped && y >= g + 1 + keep_h),
            // (the snow shaken off what stands, or melted off the ground the blast scorched or swept)
            8 => (2, if y <= g + 1 { fell || snapped || zn.scorch > 0.0 } else { stripped }),
            3 => (3, fell && y <= g + 3),
            _ => continue,
        };
        if go {
            span[slot] = (span[slot].0.min(y), span[slot].1.max(y));
        } else if k != 3 || !fell {
            standing |= k != 8 || y > g + 1;
        }
    }
    for (slot, only) in ["#minecraft:logs", "#minecraft:leaves", "minecraft:snow", super::TIDY_LOOSE].into_iter().enumerate() {
        let (a, z1) = span[slot];
        if a <= z1 {
            b.put(x, z, a, z1, CR_AIR, Some(only), false);
        }
    }
    if fell && !rimw && trunk >= 3 && !wet && clear && !kept {
        (out.fell, out.wood, out.leaves) = (trunk.min(40) as u8, wood, leaves);
    }
    if kept {
        out.top = Some(g);
        return out;
    }
    if !clear {
        // (a statue's box or a giant's torn land: nothing laid or dug, only the ground's top burnt as round it, so the
        // scorch has no straight edge where the box is)
        out.top = Some(g);
        // (only the grass, by a filter: whatever a giant has heaped there since is left as it is)
        if !wet && kinds[bl[gi] as usize] == 6 {
            let grass = Some("minecraft:grass_block");
            if zn.scorch > 0.22 {
                b.put(x, z, g, g, if zn.scorch > 0.55 { cr_pick(&BD_CHAR, h) } else { cr_pick(&BD_SCORCH, n2(cr.seed ^ 86, fx * 0.2, fz * 0.2)) }, grass, false);
            } else if e < zn.snap && n2(cr.seed ^ 87, fx * 0.11, fz * 0.11) > 0.58 - 0.2 * (1.0 - (e / zn.snap) as f32) {
                b.put(x, z, g, g, cr_pick(&BD_SINGE, h), grass, false);
            }
        }
        return out;
    }
    let rim = e / CR_RIM;
    // land higher than the target's ground is cut back from the edge in a broken slope, never left as a sheer wall over the
    // bowl (`CR_SLOPE`: blocks up for each out, ledges every CR_STEP), out to where the read reaches
    let (g, cut) = {
        let mut up = e * CR_SLOPE + 2.0 + 5.0 * f64::from(n2(cr.seed ^ 13, fx * 0.07, fz * 0.07) - 0.5);
        up = CR_STEP * (up / CR_STEP).floor() + f64::from(ss(0.55, 1.0, ((up / CR_STEP).fract()) as f32)) * CR_STEP;
        let allow = cr.ref_y + up.round() as i32;
        if g > allow && a.rc < CR_READ {
            b.run(x, z, allow + 1, top.max(g) + if e < 10.0 { 24 } else { 0 }, CR_AIR);
            let depth = (cr.ref_y + 60 - allow).clamp(0, 60) as f32 / 60.0;
            let face = if a.lip || a.fd > 0 {
                cr_pick(&CR_LIP, h)
            } else if n2(cr.seed ^ 55, fx * 0.09, fz * 0.09) > 0.62 {
                cr_pick(&CR_BURNT, h)
            } else {
                cr_stone(cr.seed, x, allow, z, 0.15 + 0.5 * depth * f32::from(u8::from((g - allow) > 12)), own)
            };
            b.run(x, z, allow, allow, face);
            (allow, true)
        } else {
            (g, false)
        }
    };
    out.top = Some(g);
    if a.fd > 0 {
        // a fissure on out through the rim and the field towards the giant's blow, shallower further out, faintly green
        // low down
        let fd = (f64::from(a.fd) * (1.0 - 0.5 * rim.clamp(0.0, 1.0))).round().max(3.0) as i32;
        b.run(x, z, g - fd + 1, top.max(g) + 24, CR_AIR);
        b.run(x, z, g - fd, g - fd, if e < CR_RIM { cr_fissure_bed(a.fc, h2) } else { bd_fissure_bed(a.fc, h2) });
        b.run(x, z, g - fd - 3, g - fd - 1, "minecraft:blackstone");
        out.top = Some(g - fd);
        return out;
    }
    if a.lip && !cut {
        // the fissure's lip, charred dark
        b.run(x, z, g, g, cr_pick(&CR_LIP, h));
    }
    if wet {
        return out;
    }
    let mut heap = 0;
    let mut cover = None;
    if rim < 1.0 {
        // the rim: heaped up and broken, highest at the edge and where the lobes threw most, in lumps and gaps; the land's
        // own earth overturned on top, broken rock through it
        let lump = 0.3 + 0.9 * n2(cr.seed ^ 3, fx * 0.09, fz * 0.09) + 0.5 * (n2(cr.seed ^ 61, fx * 0.24, fz * 0.24) - 0.5);
        let v = (1.0 - rim).max(0.0);
        let mut hh = CR_RIM_H * v * v.sqrt().sqrt() * f64::from(lump) * (0.75 + 0.5 * (a.rw / CRATER_R - 0.95).max(0.0) / CR_LOBE);
        if vs(cr.seed ^ 62, fx * 0.06, fz * 0.06) < 0.18 {
            hh *= 0.3;
        }
        heap = (hh + f64::from(h2) * 1.2).round() as i32;
        cover = Some(if n2(cr.seed ^ 63, fx * 0.18, fz * 0.18) > 0.68 { cr_pick(&BD_ROCK, h) } else { cr_pick(&CR_EJECTA, h) });
    } else if !standing {
        // the field: boulders and rubble strewn in rays (`bd_rock`)
        if let Some((hh, blk)) = bd_rock(cr, x, z, e, zn.ray) {
            heap = hh;
            cover = Some(blk);
        }
    }
    if heap > 0 {
        if heap > 1 {
            b.run(x, z, g + 1, g + heap - 1, if rim < 1.0 { cr_pick(&CR_HEAP, hash(x, z, 7)) } else { cover.unwrap_or("minecraft:stone") });
        }
        b.run(x, z, g + heap, g + heap, cover.unwrap_or("minecraft:stone"));
        out.top = Some(g + heap);
        return out;
    }
    if zn.scorch > 0.0 && !cut && (matches!(kinds[bl[gi] as usize], 6 | 9) || e < 40.0) {
        // the ground scorched in tongues: blackened near the crater, charred, then singed in patches
        let blk = if zn.scorch > 0.55 {
            cr_pick(&BD_CHAR, n2(cr.seed ^ 85, fx * 0.3, fz * 0.3) * 0.75 + 0.25 * h)
        } else if zn.scorch > 0.22 {
            cr_pick(&BD_SCORCH, n2(cr.seed ^ 86, fx * 0.2, fz * 0.2))
        } else {
            cr_pick(&BD_SINGE, h)
        };
        if zn.scorch > 0.22 || h2 < 0.6 {
            b.run(x, z, g, g, blk);
        }
    } else if e < zn.snap && !cut && matches!(kinds[bl[gi] as usize], 6 | 9) && n2(cr.seed ^ 87, fx * 0.11, fz * 0.11) > 0.58 - 0.2 * (1.0 - (e / zn.snap) as f32) {
        // (and singed in patches out to where the trees were snapped)
        b.run(x, z, g, g, cr_pick(&BD_SINGE, h));
    }
    out.open = !standing;
    out
}

/// A boulder or a lump of rubble on column (x, z), `e` past the crater's edge, `ray` the rays' strength there: blocks high
/// and what. The boulders sit on a jittered grid of cells, one at most a cell, more and bigger in the rays and near the
/// crater, each a squat lump of one rock, its sides broken up; the rubble a lump or two between them, in clusters.
/// The boulders that may reach chunk (cx, cz) (a stage lists them once a chunk, `Crater::rocks`): each cell of the grid
/// round it whose seeded chance, by the field at the cell's middle, says it holds one: its middle, size, bearing's sine
/// and cosine, how squat, its rock.
const BD_CELL: i32 = 9;
fn bd_rocks(cr: &Crater, cx: i32, cz: i32) -> Vec<([f64; 2], f64, f64, f64, f64, &'static str)> {
    let mut out = Vec::new();
    let (x0, z0) = ((cx * 16 - 5).div_euclid(BD_CELL), (cz * 16 - 5).div_euclid(BD_CELL));
    let (x1, z1) = ((cx * 16 + 20).div_euclid(BD_CELL), (cz * 16 + 20).div_euclid(BD_CELL));
    for gz in z0..=z1 {
        for gx in x0..=x1 {
            let u = |k: i32| f64::from(unit(cr.seed ^ 0xB0D, gx, k, gz));
            let (ox, oz) = (f64::from(gx * BD_CELL) + u(2) * f64::from(BD_CELL), f64::from(gz * BD_CELL) + u(3) * f64::from(BD_CELL));
            let a = cr.at(ox as i32, oz as i32);
            let e = a.rc - a.rw;
            if e < CR_RIM || a.rc >= BD_R {
                continue;
            }
            let ray = cr.zone(ox as i32, oz as i32, &a).ray;
            let near = ex(e / 70.0);
            if u(1) >= 0.8 * ray * ex(e / 230.0) + 0.35 * near {
                continue;
            }
            let r = 1.0 + 3.2 * u(4).powi(2) * (0.55 + 0.6 * near + 0.3 * ray);
            let (s, c) = (u(5) * std::f64::consts::PI).sin_cos();
            out.push(([ox, oz], r, s, c, 0.55 + 0.4 * u(6), cr_pick(&BD_ROCK, ((u(7) + 0.35 * near.min(1.0)) % 1.0) as f32)));
        }
    }
    out
}
/// About e^-x for x from 0 up, of multiplications (an `exp` costs a library call in the mod).
fn ex(x: f64) -> f64 {
    let t = 1.0 + x.max(0.0) / 8.0;
    let t2 = t * t;
    let t4 = t2 * t2;
    1.0 / (t4 * t4)
}
fn bd_rock(cr: &Crater, x: i32, z: i32, e: f64, ray: f64) -> Option<(i32, &'static str)> {
    let near = ex(e / 70.0);
    crate::meter::spend(300);
    for &([ox, oz], r, s, c, sq, rock) in cr.rocks.borrow().iter() {
        let (px, pz) = (f64::from(x) + 0.5 - ox, f64::from(z) + 0.5 - oz);
        if px.abs() > r + 1.0 || pz.abs() > r + 1.0 {
            continue;
        }
        let (a, b) = ((px * c + pz * s) / r, (pz * c - px * s) / (r * sq));
        let d = a.abs().max(b.abs()) * 0.6 + (a * a + b * b).sqrt() * 0.4 + 0.25 * f64::from(hash(x, z, 71));
        if d < 1.0 {
            let hh = ((r * 0.95 + 0.4) * (1.0 - d * d).sqrt() + 0.3 * f64::from(hash(x, z, 72))).round() as i32;
            if hh > 0 {
                return Some((hh, rock));
            }
        }
    }
    // (rubble between them, in clusters, thinning out)
    let p = (0.32 * ray * ex(e / 200.0) + 0.12 * near) * f64::from(ss(0.4, 0.7, n2(cr.seed ^ 74, x as f32 * 0.2, z as f32 * 0.2)));
    (f64::from(hash(x, z, 73)) < p).then(|| (1, cr_pick(&CR_RUBBLE, hash(x, z, 75))))
}

/// The trees felled in chunk (cx, cz), lying on the land pointing away from the middle, from their stumps (`outs`: each
/// column's `cr_column`): a log a column as far as the trunk was tall less a few, each on open ground no more than a
/// block from the last, the crown's leaves crushed round its end further out; within the chunk (its edit is the chunk's).
fn bd_fell(b: &mut Blocks, cr: &Crater, cx: i32, cz: i32, outs: &mut [CrOut]) {
    crate::meter::spend(256 * 100);
    for i in 0..256 {
        let o = outs[i];
        if o.fell < 3 || o.wood == 255 {
            continue;
        }
        let Some(gy) = o.top else { continue };
        let (x, z) = (cx * 16 + (i as i32 & 15), cz * 16 + (i as i32 >> 4));
        let (dx, dz) = (f64::from(x - cr.bx), f64::from(z - cr.bz));
        let (sx, sz, log) = if dx.abs() > dz.abs() { (dx.signum() as i32, 0, BD_LOG_X[o.wood as usize]) } else { (0, dz.signum() as i32, BD_LOG_Z[o.wood as usize]) };
        let want = (i32::from(o.fell) - 1).clamp(2, 4 + (unit(cr.seed, x, 81, z) * 5.0) as i32);
        crate::meter::spend(800 * want as u64);
        let (mut last, mut gy) = (None, gy);
        for n in 1..=want {
            let (lx, lz) = (x + sx * n, z + sz * n);
            if lx >> 4 != cx || lz >> 4 != cz {
                break;
            }
            let j = ((lx & 15) + (lz & 15) * 16) as usize;
            let t = &mut outs[j];
            let Some(g2) = t.top else { break };
            if !t.open || (g2 - gy).abs() > 1 {
                break;
            }
            b.run(lx, lz, g2 + 1, g2 + 1, log);
            t.open = false;
            gy = g2;
            last = Some((lx, lz));
        }
        // (the crown crushed round its end, where the blast has not stripped it to nothing)
        if let (Some((lx, lz)), true) = (last, o.leaves != 255 && (f64::from(dx.hypot(dz)) > CRATER_R + 50.0)) {
            for (ox, oz) in [(sx, sz), (sz, sx), (-sz, -sx), (sx + sz, sz + sx), (sx - sz, sz - sx)] {
                let (fx, fz) = (lx + ox, lz + oz);
                if fx >> 4 != cx || fz >> 4 != cz || hash(fx, fz, 83) < 0.3 {
                    continue;
                }
                let t = &mut outs[((fx & 15) + (fz & 15) * 16) as usize];
                if let (true, Some(g2)) = (t.open, t.top)
                    && (g2 - gy).abs() <= 1
                {
                    b.run(fx, fz, g2 + 1, g2 + 1, BD_LEAVES[o.leaves as usize]);
                    t.open = false;
                }
            }
        }
    }
}

/// The chunks the blast reaches, nearest the middle first (with how near), and the columns of one.
fn cr_chunks(t: &Target) -> Vec<(f64, i32, i32)> {
    let (bx, bz) = (t.block[0], t.block[2]);
    let r = BD_R.ceil() as i32;
    let mut out = Vec::new();
    for cz in (bz - r) >> 4..=(bz + r) >> 4 {
        for cx in (bx - r) >> 4..=(bx + r) >> 4 {
            let nx = bx.clamp(cx * 16, cx * 16 + 15) - bx;
            let nz = bz.clamp(cz * 16, cz * 16 + 15) - bz;
            let d = f64::from(nx).hypot(f64::from(nz));
            if d < BD_R {
                out.push((d, cx, cz));
            }
        }
    }
    out.sort_by(|a, b| a.0.total_cmp(&b.0));
    out
}
fn cr_cols(c: (i32, i32)) -> impl Iterator<Item = (i32, i32)> {
    (0..256).map(move |i| (c.0 * 16 + (i & 15), c.1 * 16 + (i >> 4)))
}

/// A run of the blast's land worked out in turn: chunks, and the read that holds their columns (none: by the heightmap).
struct CrPart {
    chunks: Vec<(f64, i32, i32)>,
    tag: Option<u32>,
}
fn cr_parts(chunks: &[(f64, i32, i32)], read: bool) -> Vec<CrPart> {
    chunks
        .chunks(CR_PART)
        .map(|c| CrPart { chunks: c.to_vec(), tag: read.then(crate::columns::new_tag) })
        .collect()
}
fn cr_ask(q: &mut Plan, part: &CrPart, now: f32) {
    if let Some(tag) = part.tag {
        let cols: Vec<(i32, i32)> = part.chunks.iter().flat_map(|c| cr_cols((c.1, c.2))).collect();
        q.ev.push((now, Act::Read { tag, columns: cols, below: CR_BELOW, above: 0 }));
    }
}

/// The blast's land, its chunks listed and worked out in three runs of stages (`cr_run`): the crater's middle (read early:
/// nothing else touches it), from `CR_SETUP`, a stage every `CR_GAP`; the blast field past the rubble out to `BD_R` (its
/// trees, plants, snow and ground, each by a filter), from `CR_SETUP` too, a stage a tick with two reads in hand;
/// the crater's edge, its rim and its rubble from `CR_ASK`, read once the giants' heaped land is in, a stage a tick. A
/// chunk's blocks an edit, due as the front reaches its nearest column. The stages go ahead of whatever else waits
/// (`Plan::soon`): the crater goes in on time. The hammers' wrecks (`hm_*`) go in after, on the ground the stages leave.
fn cr_setup(q: &mut Plan, t: &Target, now: f32) {
    // (the plan in a stage of its own, the chunks listed in the next)
    let cr = Rc::new(Crater::new(t));
    let t = Target { block: t.block, point: t.point };
    q.soon(now + 0.05, move |q| cr_list(q, cr, &t, now + 0.05));
}
fn cr_list(q: &mut Plan, cr: Rc<Crater>, t: &Target, now: f32) {
    let all = cr_chunks(t);
    crate::meter::spend(400 * all.len() as u64);
    let (bx, bz) = (t.block[0], t.block[2]);
    // (the farthest a chunk's column lies)
    let reach = |c: &(f64, i32, i32)| {
        let fx = (bx - c.1 * 16).abs().max((c.1 * 16 + 15 - bx).abs());
        let fz = (bz - c.2 * 16).abs().max((c.2 * 16 + 15 - bz).abs());
        f64::from(fx).hypot(f64::from(fz))
    };
    let inner: Vec<(f64, i32, i32)> = all.iter().filter(|c| reach(c) < CR_INNER).copied().collect();
    // (the edge's chunks clear of the giants' torn land are read early with the field; only those near it wait for CR_ASK)
    let (edge, mut far): (Vec<(f64, i32, i32)>, Vec<(f64, i32, i32)>) =
        all.iter().filter(|c| reach(c) >= CR_INNER && c.0 < CR_READ).copied().partition(|c| !cr.chunk_free(c.1, c.2));
    far.extend(all.iter().filter(|c| c.0 >= CR_READ).copied());
    crate::meter::spend(6_000 * all.len() as u64);
    let first = Rc::new(cr_parts(&inner, true));
    let ct = CR_SETUP.max(now);
    for part in first.iter().take(CR_AHEAD) {
        cr_ask(q, part, ct);
    }
    let c2 = Rc::clone(&cr);
    q.soon(ct + 0.1, move |q| cr_run(q, c2, first, 0, 0, ct + 0.1, CR_GAP, CR_STAGE));
    // (the field's first reads asked at once, then each `BD_AHEAD` parts ahead)
    let far = Rc::new(cr_parts(&far, true));
    let bt = BD_SETUP.max(now);
    for part in far.iter().take(BD_AHEAD) {
        cr_ask(q, part, bt);
    }
    let c3 = Rc::clone(&cr);
    q.soon(bt + 0.1, move |q| cr_run(q, c3, far, 0, 0, bt + 0.1, BD_GAP, BD_STAGE));
    // (the edge's first reads asked at CR_ASK, then each `CR_AHEAD` parts ahead: never more than that in hand at once)
    let edge = Rc::new(cr_parts(&edge, true));
    let at = CR_ASK.max(now);
    for part in edge.iter().take(CR_AHEAD) {
        cr_ask(q, part, at);
    }
    let c4 = Rc::clone(&cr);
    q.soon(at + 0.1, move |q| cr_run(q, c4, edge, 0, 0, at + 0.1, 0.05, CR_STAGE));
    // (the hammers' wrecks, each worked out once the statues are handed to the world: `HM_AT`)
    for g in 0..5 {
        let c = Rc::clone(&cr);
        let tb = HM_AT + HM_STEP * g as f32;
        let stump = Rc::new(RefCell::new(Blocks { clear_of_player: true, ..Default::default() }));
        q.later((tb - 0.45).max(now), move |q| hm_wreck(q, c, g, tb, 0, stump));
    }
}

/// Part `p` of a run of the blast's land, from its chunk `k`: worked out into edits (from its read, waiting a tick for the
/// answer while there is time, or by the heightmap), as much as a stage's work (`cap`) allows; the next part's read asked as
/// this one starts; the rest `gap` later.
#[cfg(test)]
thread_local! {
    /// Each stage of `cr_run` in the tests: when it ran, its run's gap, chunks done, how long natively (ms), its meter.
    static CR_LOG: RefCell<Vec<(f32, f32, usize, f64, u64)>> = const { RefCell::new(Vec::new()) };
}
#[allow(clippy::too_many_arguments)]
fn cr_run(q: &mut Plan, cr: Rc<Crater>, parts: Rc<Vec<CrPart>>, p: usize, k: usize, now: f32, gap: f32, cap: u64) {
    let start = crate::meter::spent();
    #[cfg(test)]
    let clock = std::time::Instant::now();
    let (mut p, mut k, mut done) = (p, k, 0);
    let mut edits: std::collections::BTreeMap<i32, Blocks> = Default::default();
    let mut wait = false;
    while let Some(part) = parts.get(p) {
        let answer = part.tag.and_then(crate::columns::get);
        if part.tag.is_some() && answer.is_none() && k == 0 && now + 0.05 < cr_when(part.chunks[0].0) - 0.3 {
            wait = true;
            break;
        }
        if k == 0
            && let Some(next) = parts.get(p + if cap == BD_STAGE { BD_AHEAD } else { CR_AHEAD })
        {
            cr_ask(q, next, now);
        }
        let pal = answer.as_ref().map(|a| cr_kinds(&a.palette)).unwrap_or(CrPal { kind: Vec::new(), wood: Vec::new(), own: Vec::new() });
        while k < part.chunks.len() && crate::meter::spent() - start < cap {
            let (d, cx, cz) = part.chunks[k];
            let b = edits.entry((cr_when(d) / 0.05).ceil() as i32).or_insert_with(|| Blocks { clear_of_player: true, ..Default::default() });
            let mut outs = [CrOut::default(); 256];
            let field = d + 23.0 > CRATER_R * 0.93;
            cr.free.set(field && cr.chunk_free(cx, cz));
            if field && !cr.free.get() {
                cr.heave_grid(cx, cz);
            }
            *cr.rocks.borrow_mut() = if field { bd_rocks(&cr, cx, cz) } else { Vec::new() };
            crate::meter::spend(30_000 + if field { 80_000 } else { 0 });
            for (i, (x, z)) in cr_cols((cx, cz)).enumerate() {
                let read = answer.as_ref().and_then(|a| a.column(k * 256 + i));
                crate::meter::spend(if read.is_none() { if d >= TREE_R { CR_COL_FAR / 2 } else if d + 23.0 > CRATER_R * 0.93 { BD_COL_FAR } else { CR_COL_FAR } } else if d < CR_READ { CR_COL_READ } else { BD_COL });
                outs[i] = cr_column(b, &cr, x, z, read, &pal);
            }
            if d + 23.0 > CRATER_R * 0.93 {
                bd_fell(b, &cr, cx, cz, &mut outs);
            }
            cr.free.set(false);
            k += 1;
            done += 1;
        }
        if k < part.chunks.len() {
            break;
        }
        if let Some(tag) = part.tag {
            crate::columns::take(tag);
        }
        p += 1;
        k = 0;
        if crate::meter::spent() - start >= cap {
            break;
        }
    }
    for (at, b) in edits {
        if !b.runs.is_empty() {
            q.ev.push(((at as f32 * 0.05).max(now), Act::Blocks(Box::new(b))));
        }
    }
    #[cfg(test)]
    CR_LOG.with(|l| l.borrow_mut().push((now, gap, done, clock.elapsed().as_secs_f64() * 1000.0, crate::meter::spent() - start)));
    if p < parts.len() {
        let next = if wait { now + 0.05 } else { now + gap };
        q.soon(next, move |q| cr_run(q, cr, parts, p, k, next, gap, cap));
    }
}

// ---- the hammers' wrecks -------------------------------------------------------------------------------------------------
/// When giant g's wreck goes in (`HM_AT + HM_STEP g`, its stages from 0.45 s before): after the statues are handed to the
/// world (`STATUE_AT`; a tick works out one stage, and the statues' must all be in before their sweep lines start), as the
/// bursts' dust and debris (from `BURST`, 22.4 s) settle.
const HM_AT: f32 = STATUE_AT + 0.5;
const HM_STEP: f32 = 0.25;
/// What is left of giant g's hammer where it struck once it has burst (`BURST + BURST_STEP g`), as real blocks in the
/// hammer's own stone (the statues' darker stones) with a little green glow in the breaks, on the ground the crater's
/// stages left (`Crater::floors`; where a column was not read, the crater's own depth under the target's ground):
///
/// - the stump (`hm_stump`): what is left of the head, buried in the floor across the blow (its long side along the
///   giant's own x axis, `Heave::ax`), broken off at one end, its top 6-14 over the floor; and the stub of the shaft jutting
///   out of it leaning back towards the giant, snapped off by a tilted break. In at `HM_AT + HM_STEP g`.
/// - the fragments (`hm_pieces(seed, g)`): broken lumps of it lying round out to `HM_FAR`, some half buried, each landing
///   at its own time (`HmPiece::land`, from 0.25 s after the stump; two waves an edit each).
///
/// For the pass's flying pieces to line up with these (agent burst): everything here is a seeded function of the
/// strike's `Crater::seed` (from the target block: `x * 0x9E3779B9 ^ z * 0x85EBCA6B ^ 0xC4A70001`, wrapping u32) and the
/// giant's index only, measured from the hammer's blow `slam_point` (the pass's record words 44-46): `hm_pieces` lists each
/// fragment's offset (x, z blocks), size and landing time.
const HM_FAR: f64 = 46.0;
/// The hammer's stones: the head's (darker) and the shaft's, its breaks' veins and glow.
const HM_HEAD: [&str; 5] = ["minecraft:polished_deepslate", "minecraft:deepslate_tiles", "minecraft:deepslate_bricks", "minecraft:polished_deepslate", "minecraft:chiseled_deepslate"];
const HM_SHAFT: [&str; 4] = ["minecraft:tuff_bricks", "minecraft:polished_tuff", "minecraft:deepslate_bricks", "minecraft:stone_bricks"];
const HM_VEIN: [&str; 3] = ["minecraft:dark_prismarine", "minecraft:prismarine", "minecraft:dark_prismarine"];

/// One fragment of a hammer: its middle's offset from the blow (blocks, world x and z), its half length and half width
/// (blocks), how high it stands, its bearing (radians), how deep it is sunk, when it lands (strike seconds), whether of the
/// head or the shaft.
#[derive(Clone, Copy, Debug)]
struct HmPiece {
    dx: f64,
    dz: f64,
    a: f64,
    b: f64,
    h: f64,
    yaw: f64,
    bury: i32,
    land: f32,
    head: bool,
}
/// Giant g's hammer's fragments, from the strike's seed (`Crater::seed`): 11-15 of them, thrown mostly out to the sides
/// and away from the giant, the biggest nearest.
fn hm_pieces(seed: u32, g: usize) -> Vec<HmPiece> {
    let n = 11 + (unit(seed ^ 0x4A11, g as i32, 0, 0) * 5.0) as usize;
    (0..n)
        .map(|i| {
            let u = |k: i32| f64::from(unit(seed ^ 0x4A11, g as i32, i as i32 + 1, k));
            let dist = 9.0 + (HM_FAR - 9.0) * u(1).powf(0.85);
            let ang = u(2) * std::f64::consts::TAU;
            let a = (2.0 + 7.5 * u(3).powf(1.5)) * (1.1 - 0.5 * dist / HM_FAR);
            let b = a * (0.45 + 0.4 * u(4));
            let h = (1.5 + a * (0.4 + 0.5 * u(5))).min(9.0);
            HmPiece {
                dx: dist * ang.cos(),
                dz: dist * ang.sin(),
                a,
                b,
                h,
                yaw: u(6) * std::f64::consts::PI,
                bury: (u(7) * 0.55 * h) as i32,
                land: HM_AT + HM_STEP * g as f32 + 0.25 + (0.022 * dist + 0.3 * u(8)) as f32,
                head: u(9) < 0.6,
            }
        })
        .collect()
}

/// The ground under column (x, z) for a wreck: as the crater's stages left it, or the crater's own depth there.
fn hm_floor(cr: &Crater, x: i32, z: i32) -> i32 {
    if let Some(i) = cr.floor_at(x, z) {
        let y = cr.floors.borrow()[i];
        if y != i16::MIN {
            return cr.ref_y + i32::from(y);
        }
    }
    let a = cr.at(x, z);
    if a.rc < a.rw { cr.ref_y - (a.d.round() as i32).max(1) - a.fd } else { cr.ref_y }
}

/// Giant g's wreck, in four stages (`part`: the head's stump a half at a time, the shaft's stub, the fragments): the stump
/// into one edit at `tb` (gathered in `stump` over the first three), the fragments into two as they land.
fn hm_wreck(q: &mut Plan, cr: Rc<Crater>, g: usize, tb: f32, part: u8, stump: Rc<RefCell<Blocks>>) {
    if part < 3 {
        let (c, s) = (Rc::clone(&cr), Rc::clone(&stump));
        q.later(tb - 0.45 + 0.05 * f32::from(part + 1), move |q| hm_wreck(q, c, g, tb, part + 1, s));
    }
    let cr = &*cr;
    let st = &statues()[g];
    let hv = &cr.heaves[g];
    let rig = pose::Rig::read(usize::from(st.design));
    let sc = f64::from(hv.sc);
    let hsr = f64::from(hv.hsr);
    let (sx, sz) = cr.slams[g];
    let u = |k: i32| f64::from(unit(cr.seed ^ 0x57A9, g as i32, k, 0));
    // (the head's long side along the giant's own x axis; the giant itself out along the blow's bearing)
    let (ax, az) = (f64::from(hv.ax[0]), f64::from(hv.ax[1]));
    let an = ax.hypot(az).max(1e-6);
    let (ax, az) = (ax / an, az / an);
    let (ox, oz) = (f64::from(sx - cr.bx), f64::from(sz - cr.bz));
    let on = ox.hypot(oz).max(1.0);
    let (rx, rz) = (ox / on, oz / on);
    let len = rig.hammer_ext[0] * hsr * sc;
    let thick = rig.hammer_ext[2] * hsr * sc;
    let keep = 0.55 + 0.25 * u(1);
    // (which end broke off, the head's top over the floor, its roll across and its tilt along)
    let side = if u(2) < 0.5 { -1.0 } else { 1.0 };
    let rise = 6.0 + 8.0 * u(3);
    let (roll, tilt) = (0.22 * (u(4) - 0.5), 0.14 * (u(5) - 0.5));
    // (the floor it lies in: round the blow, not the fissure under it: the upper of eight samples a ring round it)
    let mut ring: Vec<i32> = (0..8)
        .map(|k| {
            let a = f64::from(k) * std::f64::consts::TAU / 8.0;
            hm_floor(cr, sx + (16.0 * a.cos()).round() as i32, sz + (16.0 * a.sin()).round() as i32)
        })
        .collect();
    ring.sort_unstable();
    let gy = ring[5];
    let mut stump = stump.borrow_mut();
    let p_lo = -len * 0.5;
    let p_hi = -len * 0.5 + len * keep;
    // (the head's middle shifted to the part kept)
    let pc = 0.5 * (p_lo + p_hi) * side;
    let (hx, hz) = (f64::from(sx) + 0.5 + ax * pc, f64::from(sz) + 0.5 + az * pc);
    let rmax = (len * keep * 0.5).hypot(thick * 0.5) + 2.0;
    let head_top = |p: f64, qq: f64| f64::from(gy) + rise + roll * qq + tilt * p;
    let (z0, z1) = ((hz - rmax).floor() as i32, (hz + rmax).ceil() as i32);
    let zm = (z0 + z1) / 2;
    let rows = match part {
        0 => z0..=zm,
        1 => zm + 1..=z1,
        _ => 1..=0,
    };
    for z in rows {
        for x in (hx - rmax).floor() as i32..=(hx + rmax).ceil() as i32 {
            crate::meter::spend(600);
            let (px, pz) = (f64::from(x) + 0.5 - hx, f64::from(z) + 0.5 - hz);
            let p = px * ax + pz * az;
            let qq = pz * ax - px * az;
            let half = len * keep * 0.5;
            if p.abs() > half + 0.5 || qq.abs() > thick * 0.5 {
                continue;
            }
            crate::meter::spend(6_000);
            // (the broken end jagged, the long sides chipped at the corners)
            let jag = 3.0 * f64::from(n2(cr.seed ^ 0x57, qq as f32 * 0.4, g as f32 * 7.0)) + f64::from(hash(x, z, 91));
            let broke = if p * side > 0.0 { half - jag } else { half - 0.6 * f64::from(hash(x, z, 92)) };
            let chip = ((p.abs() - half + 4.0).max(0.0) + (qq.abs() - thick * 0.5 + 4.0).max(0.0)) * 0.6;
            if p.abs() > broke || qq.abs() > thick * 0.5 - chip.min(3.0) * f64::from(hash(x, z, 93)) {
                continue;
            }
            if !cr.clear_box(x, z) {
                continue;
            }
            let fl = hm_floor(cr, x, z);
            let mut ty = head_top(p, qq) + 1.2 * f64::from(n2(cr.seed ^ 0x58, x as f32 * 0.3, z as f32 * 0.3)) - chip;
            // (lower towards the broken end, where it sheared off)
            let tob = broke - p.abs();
            if p * side > 0.0 && tob < 6.0 {
                ty -= (6.0 - tob) * 0.8;
            }
            let ty = (ty.round() as i32).min(fl + rise as i32 + 10);
            if ty <= fl {
                continue;
            }
            let body = cr_pick(&HM_HEAD, n2(cr.seed ^ 0x59, x as f32 * 0.15 + ty as f32 * 0.1, z as f32 * 0.15));
            stump.run(x, z, fl - 4, ty - 1, body);
            // (the break and two cracks across the head glowing faintly)
            let crack = (f64::from(n2(cr.seed ^ 0x5A, p as f32 * 0.12, qq as f32 * 0.5)) - 0.5).abs() < 0.035;
            let top = if (p * side > 0.0 && tob < 2.5) || crack {
                if hash(x, z, 94) < 0.35 { CR_GLOW } else { cr_pick(&HM_VEIN, hash(x, z, 95)) }
            } else {
                body
            };
            stump.run(x, z, ty, ty, top);
        }
    }
    // (the shaft's stub, leaning back towards the giant, out of the head's top near the blow; snapped by a tilted break)
    let lean = 0.45 + 0.4 * u(6);
    let (dxz, dy) = (lean.sin(), lean.cos());
    let (dxs, dzs) = (rx * dxz / dy, rz * dxz / dy);
    let rs = (rig.hammer_ext[2] * 0.14 * hsr * sc).max(3.5);
    let ls = 18.0 + 26.0 * u(7);
    let y0 = head_top(0.0 - pc * side, 0.0) - 4.0;
    let (bx0, bz0) = (f64::from(sx) + 0.5, f64::from(sz) + 0.5);
    let (ex, ez) = (-rz, rx);
    let btilt = 0.5 * (u(8) - 0.5);
    let ext = if part == 2 { ls * dxz + rs + 2.0 } else { -1.0 };
    for z in (bz0 - ext).floor() as i32..=(bz0 + ext).ceil() as i32 {
        for x in (bx0 - ext).floor() as i32..=(bx0 + ext).ceil() as i32 {
            crate::meter::spend(800);
            if !cr.clear_box(x, z) {
                continue;
            }
            let (wx, wz) = (f64::from(x) + 0.5 - bx0, f64::from(z) + 0.5 - bz0);
            // (the heights s over y0 where the column is within rs of the axis: |w - d s| <= rs)
            let (aa, bb, cc) = (dxs * dxs + dzs * dzs, -2.0 * (wx * dxs + wz * dzs), wx * wx + wz * wz - rs * rs);
            let disc = bb * bb - 4.0 * aa * cc;
            if disc < 0.0 {
                continue;
            }
            let (s1, s2) = if aa < 1e-9 { if cc > 0.0 { continue } else { (-1e9, 1e9) } } else { ((-bb - disc.sqrt()) / (2.0 * aa), (-bb + disc.sqrt()) / (2.0 * aa)) };
            let lat = wx * ex + wz * ez;
            let s_top = ls * dy + btilt * lat + 1.5 * f64::from(hash(x, z, 96)) - 1.0;
            let (lo, hi) = (s1.max(0.0), s2.min(s_top));
            if hi < lo {
                continue;
            }
            crate::meter::spend(6_000);
            let fl = hm_floor(cr, x, z);
            // (each column's run reaching down as far as the lean carries the shaft over a block, so a run always
            // overlaps its neighbour's on the slant: no block touching the rest only at an edge)
            let slant = (dxs * dxs + dzs * dzs).sqrt();
            let (ya, yb) = ((y0 + lo - slant - 1.0).floor() as i32, (y0 + hi).round() as i32);
            // (down to the floor wherever its foot is in the head or the ground; nowhere left over air at its foot)
            let ya = if lo <= 0.5 { ya.min(fl - 2) } else { ya };
            if yb < ya {
                continue;
            }
            let body = cr_pick(&HM_SHAFT, n2(cr.seed ^ 0x5B, x as f32 * 0.2, z as f32 * 0.2 + ya as f32 * 0.05));
            stump.run(x, z, ya, yb, body);
            if hi >= s_top - 0.5 && s2 > s_top {
                stump.run(x, z, yb, yb, if hash(x, z, 97) < 0.4 { CR_GLOW } else { cr_pick(&HM_VEIN, hash(x, z, 98)) });
            }
        }
    }
    if part == 2 && !stump.runs.is_empty() {
        crate::meter::spend(600 * stump.runs.len() as u64 + 200_000);
        q.ev.push((tb + 0.05, Act::Blocks(Box::new(std::mem::take(&mut *stump)))));
    }
    drop(stump);
    if part != 3 {
        return;
    }
    // (the fragments, in two waves: those down first, the rest)
    let pieces = hm_pieces(cr.seed, g);
    let mid = HM_AT + HM_STEP * g as f32 + 0.7;
    let mut waves = [Blocks { clear_of_player: true, ..Default::default() }, Blocks { clear_of_player: true, ..Default::default() }];
    let mut t_wave = [0.0f32; 2];
    for (n, pc) in pieces.iter().enumerate() {
        let w = usize::from(pc.land > mid);
        t_wave[w] = t_wave[w].max(pc.land);
        let (cx, cz) = (f64::from(sx) + 0.5 + pc.dx, f64::from(sz) + 0.5 + pc.dz);
        let (s, c) = pc.yaw.sin_cos();
        let rr = pc.a.max(pc.b) + 1.0;
        let gc = hm_floor(cr, cx.floor() as i32, cz.floor() as i32);
        for z in (cz - rr).floor() as i32..=(cz + rr).ceil() as i32 {
            for x in (cx - rr).floor() as i32..=(cx + rr).ceil() as i32 {
                let (px, pz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
                let (pa, pb) = ((px * c + pz * s) / pc.a, (pz * c - px * s) / pc.b);
                // (a slab with its corners broken off and its sides chipped: no round lumps)
                crate::meter::spend(4_000);
                let d = pa.abs().max(pb.abs()).max((pa.abs() + pb.abs()) * 0.72) + 0.22 * f64::from(hash(x, z, 101 + n as u32));
                if d >= 1.0 || !cr.clear_box(x, z) {
                    continue;
                }
                let fl = hm_floor(cr, x, z);
                // (its top level across it, sloped where it lies on a slope, lower to its ends; sunk `bury`)
                let ty = (f64::from(gc.max(fl)) + pc.h * (1.0 - 0.35 * pa * pa) - f64::from(pc.bury) + 0.6 * f64::from(hash(x, z, 102))).round() as i32;
                if ty <= fl {
                    continue;
                }
                let body = if pc.head { cr_pick(&HM_HEAD, hash(n as i32, g as i32, 103)) } else { cr_pick(&HM_SHAFT, hash(n as i32, g as i32, 104)) };
                waves[w].run(x, z, fl - 1, ty - 1, body);
                // (the face it broke from, at one end, veined and now and then glowing)
                let top = if pa > 0.65 && hash(x, z, 105) < 0.55 { if hash(x, z, 106) < 0.3 { CR_GLOW } else { cr_pick(&HM_VEIN, hash(x, z, 107)) } } else { body };
                waves[w].run(x, z, ty, ty, top);
            }
        }
    }
    crate::meter::spend(1_500 * waves.iter().map(|w| w.runs.len() as u64).sum::<u64>() + 300_000);
    for (w, b) in waves.into_iter().enumerate() {
        if !b.runs.is_empty() {
            q.ev.push((t_wave[w].max(tb + 0.1), Act::Blocks(Box::new(b))));
        }
    }
}

/// When giant g's statue is read out of the file (a stage), sorted by chunk (the next) and handed to the world (the ones after):
/// well before its blocks are due, a giant at a time.
fn statue_read_at(g: usize) -> f32 {
    21.6 + 0.3 * g as f32
}
/// When a statue's blocks go in: once the giant drawn over them holds the statue's crouch (the pass's CL_SETTLE, 24.3 s), each
/// statue's at once (`STATUE_STEP`), before the first line starts down (T_SWEEP0, 25 s). The pass draws the giant over them, by depth, till its line
/// reveals them: blocks inside its mesh are hidden by it.
const STATUE_AT: f32 = 24.45;
/// Giant g's statue goes in `STATUE_STEP` g after the first: the five not handed over on one tick (some 180,000 runs, a third
/// of a tick's fuel to take in), each still well before its own line starts down (`T_SWEEP_STEP` apart).
const STATUE_STEP: f32 = 0.1;
/// The meter's work a stage of `place_statue` does at most before it hands the rest to the next.
const STATUE_STAGE: u64 = 2_500_000;

/// A statue's blocks, a chunk column's at a time, one edit each, the chunk with the highest block first: each chunk is changed
/// (and sent to the client) once. A column's blocks of one kind one over
/// another are one run. A few chunks a stage, the stages chained.
fn place_statue(q: &mut Plan, t: Rc<Target>, g: usize, gy: i32, cols: Rc<Cols>, k: usize, at: f32) {
    let st = &statues()[g];
    let (ox, oz) = corner(&t, g, st);
    let (ox, oz, oy) = (ox + i32::from(st.pshift[0]), oz + i32::from(st.pshift[2]), gy + i32::from(st.pshift[1]));
    let xs = u32::from(st.pgrid[0]);
    let start = crate::meter::spent();
    let mut k = k;
    while k < cols.groups.len() {
        let (a, z) = cols.groups[k];
        let mut b = Blocks { clear_of_player: true, ..Default::default() };
        let mut i = a;
        while i < z {
            let (col, y, id) = cols.v[i];
            let mut j = i + 1;
            while j < z && cols.v[j].0 == col && cols.v[j].1 == cols.v[j - 1].1 + 1 && cols.v[j].2 == id {
                j += 1;
            }
            b.run(ox + (col % xs) as i32, oz + (col / xs) as i32, oy + i32::from(y), oy + i32::from(cols.v[j - 1].1), st.palette[usize::from(id)]);
            i = j;
        }
        crate::meter::spend(20 * (z - a) as u64);
        if !b.runs.is_empty() {
            q.ev.push((STATUE_AT + STATUE_STEP * g as f32, Act::Blocks(Box::new(b))));
        }
        k += 1;
        if crate::meter::spent() - start > STATUE_STAGE && k < cols.groups.len() {
            q.soon(at + 0.05, move |q| place_statue(q, t, g, gy, cols, k, at + 0.05));
            return;
        }
    }
}

pub(super) fn colossi_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, _shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: super::Rng::new(seed as u64), bx, by, bz };
    let tgt = Rc::new(Target { block: target.block, point: target.point });
    let centre = [f64::from(bx) + 0.5, f64::from(by) + 1.0, f64::from(bz) + 0.5];
    let (_, dist) = sound_from(centre, me);
    let fo = falloff(dist);

    // ---- the pass's table: the meshes and the five giants (their ground a moment later, from the survey) --------------------
    {
        let t = Rc::clone(&tgt);
        p.later(0.04, move |q| {
            let g = [t.block[1] + 1; 5];
            q.ev.push((0.05, Act::Table(table_words(&t, g))));
        });
    }
    let gr = Rc::new(Grounds { y: RefCell::new([by + 1; 5]), done: RefCell::new(false) });
    {
        let tag = crate::ground::new_tag();
        let t = Rc::clone(&tgt);
        let columns: Vec<(i32, i32)> = statues().iter().enumerate().flat_map(|(g, st)| [middle(&t, g, st), slam_column(&t, g, st)]).collect();
        p.later(0.1, move |q| q.ev.push((0.1, Act::Survey { tag, columns })));
        let (t, gr2) = (Rc::clone(&tgt), Rc::clone(&gr));
        p.soon(0.5, move |q| survey(q, tag, t, gr2, 0.5, 0));
    }

    // ---- sounds and the camera: the earth heaving, the swings, the beam, the blast, the conversion ------------------------
    for i in 0..9 {
        p.shake(0.3 + i as f32 * 0.85, 0.05 * fo.max(0.4), 1.2);
    }
    // (the Colossi's own sounds, tools/sounds_colossi.py: a giant's come from where it stands and arrive late by the
    // distance, the lows through the ground five times sooner; the script's `schedule` plays this same arithmetic in its
    // mixdowns, and these leads are where each file puts its moment: keep the two in step)
    const CS_GROUND_V: f64 = 5.0 * 343.0;
    const CS_QUAKE_LEAD: f32 = 0.05;
    const CS_STAMP_LEAD: f32 = 0.05;
    const CS_HEAVE_AHEAD: f32 = 3.4;
    const CS_HEAVE_CATCH: f32 = 2.32;
    const CS_SLAM_PITCH: [f32; 5] = [1.04, 1.0, 0.97, 0.93, 1.01];
    const CS_KNEE_F: f32 = 0.74;
    const CS_KNEE_LEAD: f32 = 0.9;
    const CS_KNEE_VOL: f32 = 0.3;
    const CS_SLAM_LEAD: f32 = 1.25;
    const CS_SLAM2_LEAD: f32 = 0.05;
    const CS_SLAM_VOL: f32 = 0.65;
    const CS_MOVE_VOL: f32 = 0.75;
    const CS_SLAM2_VOL: f32 = 0.85;
    const CS_BLAST_LEAD: f32 = 0.02;
    const CS_GROUND_LEAD: f32 = 0.02;
    const CS_RUMBLE_AFTER: f32 = 1.0;
    const CS_BURST_LEAD: f32 = 0.03;
    const CS_BURST_VOL: f32 = 0.3;
    fn placed(p: &mut Plan, t: f32, role: String, at: [f64; 3], me: [f64; 3], vol: f32, pitch: f32) {
        if vol > 0.003 {
            let (late, _) = sound_from(at, me);
            let event = p.laser.sound(&role);
            p.ev.push((t + late, Act::Sound { event, at: Some(at), volume: vol.min(1.0), pitch }));
        }
    }
    // (a giant's own movements, its stamp, its hammer hauled up and its blow, are heard with the picture, never late by the
    // distance)
    fn now(p: &mut Plan, t: f32, role: String, at: [f64; 3], vol: f32, pitch: f32) {
        if vol > 0.003 {
            let event = p.laser.sound(&role);
            p.ev.push((t, Act::Sound { event, at: Some(at), volume: vol.min(1.0), pitch }));
        }
    }
    let sts = statues();
    let gy = centre[1];
    let giant = |g: usize, up: f64| {
        let (x, z) = middle(&tgt, g, &sts[g]);
        [f64::from(x) + 0.5, gy + up, f64::from(z) + 0.5]
    };
    let slam_at = |g: usize| {
        let [x, z] = slam_point(&tgt, g, &sts[g]);
        [centre[0] + x, gy, centre[2] + z]
    };
    // (a blow 250 blocks off and more cross-faded into its far take, all far by 800)
    let far_mix = |d: f64| {
        let u = ((d - 250.0) / 550.0).clamp(0.0, 1.0);
        (u * u * (3.0 - 2.0 * u)) as f32
    };
    // (giant g's take and pitch: no two giants in a row the same)
    let s3 = (seed as u32) % 3;
    let take = |g: usize| ((g as u32 + s3) % 3 + 1, 0.97 + 0.06 * hash(g as i32, 11, s3));
    // (giant g's blow: its character's own take, `character`'s deal, at that character's pitch with a little jitter)
    let deal = (hash(bx, bz, 41) * 5.0) as usize;
    let blow = |g: usize| ((g + deal) % 5 + 1, CS_SLAM_PITCH[(g + deal) % 5] * (0.985 + 0.03 * hash(g as i32, 11, s3)));
    let near_g = (0..5).map(|g| sound_from(giant(g, 0.0), me).1).fold(f64::MAX, f64::min);
    p.csound(T_RISE0 + (near_g / CS_GROUND_V) as f32 - CS_QUAKE_LEAD, "quake", 10.0, 1.0);
    for g in 0..5 {
        let (k, pitch) = take(g);
        placed(&mut p, T_RISE0 + T_RISE_STEP * g as f32, format!("rise{k}"), giant(g, 0.0), me, 0.75, pitch);
    }
    for g in 0..5 {
        let ti = slam1(g);
        let (k, pitch) = take(g);
        let (sp, fm) = (slam_at(g), far_mix(sound_from(slam_at(g), me).1));
        // the hammer heaved up over the shoulder, the stone joints grinding, then its swing and the blow
        let ld = leads(target, g);
        let (c, sp_) = blow(g);
        let hp = pitch / ld[0].sqrt();
        now(&mut p, ti - CS_HEAVE_CATCH * ld[0] - (CS_HEAVE_AHEAD - CS_HEAVE_CATCH) / hp, format!("heave{k}"), giant(g, 150.0), CS_MOVE_VOL, hp);
        now(&mut p, ti - CS_SLAM_LEAD / sp_, format!("slam{c}"), sp, CS_SLAM_VOL * (1.0 - fm), sp_);
        now(&mut p, ti - CS_SLAM_LEAD / sp_, format!("slam_far{c}"), sp, CS_SLAM_VOL * fm, sp_);
        // the foot stamped down before the swing (the pass's `cl_stomps`)
        now(&mut p, ti - 3.2 * ld[0] - CS_STAMP_LEAD / pitch, format!("stamp{k}"), giant(g, 0.0), CS_MOVE_VOL, pitch);
        p.shake(ti - 3.2 * ld[0], 0.22 * fo.max(0.3), 0.7);
        p.shake(ti, 0.55 * fo.max(0.3), 1.1);
    }
    // (all five again, each its next take; and what the five together add, through the ground)
    for g in 0..5 {
        let (k, pitch) = take(g + 1);
        let (sp, fm) = (slam_at(g), far_mix(sound_from(slam_at(g), me).1));
        let ld = leads(target, g);
        let t2 = slam2(target, g);
        let (c, sp_) = blow(g);
        let hp = pitch / ld[1].sqrt();
        now(&mut p, t2 - CS_HEAVE_CATCH * ld[1] - (CS_HEAVE_AHEAD - CS_HEAVE_CATCH) / hp, format!("heave{k}"), giant(g, 150.0), CS_MOVE_VOL * CS_SLAM2_VOL, hp);
        now(&mut p, t2 - 3.2 * ld[1] - CS_STAMP_LEAD / pitch, format!("stamp{k}"), giant(g, 0.0), CS_MOVE_VOL * CS_SLAM2_VOL, pitch);
        now(&mut p, t2 - CS_SLAM_LEAD / sp_, format!("slam{c}"), sp, CS_SLAM_VOL * CS_SLAM2_VOL * (1.0 - fm), sp_);
        now(&mut p, t2 - CS_SLAM_LEAD / sp_, format!("slam_far{c}"), sp, CS_SLAM_VOL * CS_SLAM2_VOL * fm, sp_);
        p.shake(t2, 0.3 * fo.max(0.3), 0.6);
    }
    p.csound(SLAM2 - CS_SLAM2_LEAD, "slam_all", 10.0, 1.0);
    p.shake(SLAM2, 0.7 * fo.max(0.3), 1.6);
    // the cracks running to the middle: their build-up from the ground there, timed as the blast it runs into, and a jolt
    // at each lunge (the pass's `cl_run`: five from T_BEAM0, the last meeting at CL_HIT)
    // (the finale is heard with the impact frames, not late by the distance)
    p.ev.push((T_BEAM0, Act::Sound { event: laser.sound("beam"), at: Some([centre[0], gy + 2.0, centre[2]]), volume: 1.0, pitch: 1.0 }));
    for i in 0..5 {
        p.shake(T_BEAM0 + i as f32 * (CL_HIT - T_BEAM0) / 4.35, (0.14 + 0.06 * i as f32) * fo.max(0.4), 0.4);
    }
    // the blast: the ground's answer first, then the air's (far cross-faded in by distance), the land rolling on after
    // (less of the ground's thump the closer it lands to the blast, which then carries it)
    let gap = dist / 343.0 - dist / CS_GROUND_V;
    let gv = ((1.0 / (1.0 + dist / 1200.0)).clamp(0.35, 1.0) * ((gap - 0.05) / 0.9).clamp(0.3, 1.0).powf(1.2)) as f32;
    p.csound(CL_HIT - CS_GROUND_LEAD, "ground", 10.0 * gv, 1.0);
    let fm = far_mix(dist);
    p.csound(CL_HIT - CS_BLAST_LEAD, "blast", 10.0 * (1.0 - fm).sqrt(), 1.0);
    p.csound(CL_HIT - CS_BLAST_LEAD, "blast_far", 10.0 * fm.sqrt() * (1.25 / (1.0 + dist / 2000.0)).min(1.0) as f32, 1.0);
    p.csound(CL_HIT + CS_RUMBLE_AFTER, "rumble", 10.0, 1.0);
    // the light running up each hammer into the arms, peaking as they burst apart in turn
    for g in 0..5 {
        let (k, pitch) = take(g);
        let tb = BURST + BURST_STEP * g as f32;
        let arms = giant(g, 130.0);
        let fm = far_mix(sound_from(arms, me).1);
        placed(&mut p, tb - (BURST - CHARGE) / pitch, format!("charge{k}"), arms, me, 0.42, pitch);
        placed(&mut p, tb - CS_BURST_LEAD / pitch, format!("burst{k}"), arms, me, CS_BURST_VOL * (1.0 - fm), pitch);
        placed(&mut p, tb - CS_BURST_LEAD / pitch, format!("burst_far{k}"), arms, me, CS_BURST_VOL * fm, pitch);
        // (down on one knee: the knee set down CS_KNEE_F of the way from the burst + 0.2 s to the pass's CL_SETTLE, 24.3 s)
        let tk = tb + 0.2 + CS_KNEE_F * (24.3 - tb - 0.2);
        placed(&mut p, tk - CS_KNEE_LEAD / pitch, format!("kneel{k}"), giant(g, 20.0), me, CS_KNEE_VOL, pitch);
    }
    p.shake(CL_HIT, 0.95 * fo, 3.5);
    for i in 0..6 {
        p.shake(CL_HIT + 1.5 + i as f32 * 0.9, (0.3 - 0.04 * i as f32).max(0.05) * fo, 1.2);
    }
    // the line down each giant, the stone setting into blocks behind it (the file lasts CL_SWEEP and a settling)
    for g in 0..5 {
        let ts = T_SWEEP0 + T_SWEEP_STEP * g as f32;
        let (k, pitch) = take(g);
        placed(&mut p, ts, format!("settle{k}"), giant(g, 100.0), me, 1.0, pitch);
    }

    // ---- the land ------------------------------------------------------------------------------------------------------
    if terrain {
        for [x0, z0, x1, z1] in load_rows(target) {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
            p.ev.push((CL_LEN - 0.5, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        // (the land round each giant torn up as it comes up out of it, from its feet out: `hv_setup`; the pass leaves the heap
        // outside the crater to the blocks, flags bit 3)
        for g in 0..5 {
            let t = Rc::clone(&tgt);
            let at = 0.06 + 0.03 * g as f32;
            p.later(at, move |q| {
                if g == 0 {
                    q.ev.push((at, Act::Words { index: 3, words: vec![3 | 8] }));
                }
                hv_setup(q, Rc::new(Heave::new(&t, g)), at);
            });
        }
        p.at(CL_HIT, format!("execute positioned {:.1} {} {:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{KILL_R}]", centre[0], by + 1, centre[2]));
        // (the blast's land: the crater, its rim and rubble read and dug from the middle out, a chunk an edit: `cr_setup`)
        let t = Rc::clone(&tgt);
        p.soon(BD_SETUP - 0.2, move |q| cr_setup(q, &t, BD_SETUP - 0.15));
        for g in 0..5 {
            let (t, gr2) = (Rc::clone(&tgt), Rc::clone(&gr));
            let at = statue_read_at(g);
            p.soon(at, move |q| {
                let gy = gr2.y.borrow()[g] - BURY;
                // (the blocks are read out of the file in a stage of their own, sorted by chunk in the next, then handed to the
                // world a few chunks a stage)
                let cells = statues()[g].cells();
                q.soon(at + 0.05, move |q| {
                    let st = &statues()[g];
                    let (ox, oz) = corner(&t, g, st);
                    let cols = Rc::new(cells.by_chunk(ox + i32::from(st.pshift[0]), oz + i32::from(st.pshift[2]), u32::from(st.pgrid[0]), u32::from(st.pgrid[2])));
                    q.soon(at + 0.1, move |q| place_statue(q, t, g, gy, cols, 0, at + 0.1));
                });
            });
        }
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::sim;

    fn the_laser() -> &'static Laser {
        crate::lasers::LASERS.iter().find(|l| l.key == "colossi").copied().expect("the colossi")
    }
    fn target() -> Target {
        Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] }
    }
    /// The combined blow's five hits reach the player apart, wherever they stand, and
    /// the last still lands at SLAM2, the first within the roll.
    #[test]
    fn the_combined_blow_is_heard_as_five() {
        let mut worst = f32::MAX;
        for (bx, bz) in [(0, 0), (37, -120), (-411, 905), (1290, 3)] {
            let t = Target { block: [bx, 64, bz], point: [f64::from(bx) + 0.5, 65.0, f64::from(bz) + 0.5] };
            for (d, a) in [(150.0f64, 0.0f64), (300.0, 1.1), (300.0, 2.6), (700.0, 4.0), (1000.0, 5.5)] {
                let me = [f64::from(bx) + 0.5 + d * a.cos(), 66.0, f64::from(bz) + 0.5 + d * a.sin()];
                let _ = me;
                let mut heard: Vec<f32> = (0..5).map(|g| slam2(&t, g)).collect();
                assert!((0..5).all(|g| slam2(&t, g) <= SLAM2 + 1.0e-4 && slam2(&t, g) >= SLAM2 + ROLL[0] - 0.03));
                heard.sort_by(f32::total_cmp);
                worst = worst.min(heard.windows(2).map(|w| w[1] - w[0]).fold(f32::MAX, f32::min));
            }
        }
        assert!(worst > 0.17, "two of the combined blow's hits arrive {worst} s apart");
    }
    fn land(_x: i32, _z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let mut col = vec!["minecraft:air"; (below + above) as usize];
        for (i, c) in col.iter_mut().enumerate() {
            if (i as u32) < below {
                *c = if i as u32 + 1 == below { "minecraft:grass_block" } else { "minecraft:stone" };
            }
        }
        Some((64, col))
    }

    #[test]
    fn the_five_statues_and_the_table_agree() {
        let st = statues();
        assert_eq!(st.len(), 5);
        let w = table_words(&target(), [64; 5]);
        assert!(w.len() > 100_000 && w.len() <= 262_144, "{} words", w.len());
        assert_eq!(w[0], 0xC010_5510);
        for (g, s) in st.iter().enumerate() {
            assert_eq!(w[REC0 + REC * g], u32::from(s.design));
            assert_eq!(f32::from_bits(w[REC0 + REC * g + 2]), f32::from(s.height) / 50.0);
            // (the cells decode to the grid)
            // (about 220 tall: the most that fits under the build limit on the land they stand on)
            assert!(s.height >= 200 && s.height <= 235, "{} tall", s.height);
            assert!(s.cells().v.len() > 10_000, "{} blocks", s.cells().v.len());
        }
    }
    #[test]
    fn the_ring_stands_45_out_and_every_giant_faces_the_middle() {
        let t = target();
        for (g, st) in statues().iter().enumerate() {
            let (cx, cz) = middle(&t, g, st);
            let r = f64::from(cx * cx + cz * cz).sqrt();
            assert!((r - RING_R).abs() < 2.0, "giant {g} at {r}");
            // (its front, local +z turned by yaw, then mirrored, points at the middle)
            let (s, c) = (f64::from(st.yaw).sin(), f64::from(st.yaw).cos());
            let front = (if st.mirror { -s } else { s }, c);
            let inward = (-f64::from(cx) / r, -f64::from(cz) / r);
            assert!(front.0 * inward.0 + front.1 * inward.1 > 0.97, "giant {g}: {front:?} vs {inward:?}");
        }
    }
    #[test]
    fn nothing_but_light_happens_with_the_terrain_off() {
        let plan = colossi_plan(the_laser(), &target(), false, "minecraft:overworld", 37.0, [0.5, 65.0, 120.0]);
        let played = sim::play_clocked(plan, CL_LEN, &|x, z, b, a| land(x, z, b, a));
        assert!(played.edits.is_empty() && played.cmds.is_empty());
    }
    #[test]
    fn the_land_is_dug_scorched_and_the_statues_go_in_behind_the_sweep() {
        crate::ground::set_test(Some(|_, _| Some(65)));
        let plan = colossi_plan(the_laser(), &target(), true, "minecraft:overworld", 37.0, [0.5, 65.0, 120.0]);
        let played = sim::play_clocked(plan, CL_LEN, &|x, z, b, a| land(x, z, b, a));
        crate::ground::set_test(None);
        let fills: Vec<String> = played.edits.iter().flat_map(|e| e.2.as_fills()).collect();
        assert!(played.edits.len() > 40, "{} edits", played.edits.len());
        // (the crater is dug and lined, the footprints cleared, the statues placed in blocks)
        assert!(fills.iter().any(|f| f.contains(CR_GLOW)) && fills.iter().any(|f| f.contains("minecraft:deepslate")), "no crater lining");
        assert!(played.edits.iter().filter(|e| e.1 < 8.0).count() > 50, "the heaps' ground uprooted");
        // (the statues: a chunk column's blocks in an edit, twice in all, a run up each column of one kind)
        let statue: Vec<(f32, &Blocks)> = played.edits.iter().filter(|e| is_statue(&e.2)).map(|e| (e.0, &e.2)).collect();
        let statue_blocks: u64 = statue.iter().flat_map(|e| e.1.runs.iter()).map(|r| u64::from(r.height)).sum();
        let statue_runs: usize = statue.iter().map(|e| e.1.runs.len()).sum();
        assert!(statue_blocks > 150_000 && statue_runs < statue_blocks as usize * 4 / 5, "{statue_blocks} blocks of statue in {statue_runs} runs");
        assert!(statue.len() < 400, "{} statue edits", statue.len());
        // (every statue block is in before its giant's line reveals it, all of them by 26 s)
        for (g, m) in statue_margins(&statue, 65).iter().enumerate() {
            assert!(m.0 >= 0.2 && m.2 <= 26.0, "giant {g}: {m:?}");
        }
        // (the earth heaved up round each giant's feet is left as blocks)
        // (as they rise: `hv_land_is_torn_up_as_the_giants_rise` holds the rest)
        let heaps: Vec<usize> = played.edits.iter().filter(|e| e.2.as_fills().iter().any(|f| f.contains(HV_INTO))).filter(|e| e.1 < 8.0).map(|e| e.2.runs.len()).collect();
        assert!(heaps.len() >= 5 && heaps.iter().sum::<usize>() > 20_000, "heaps {heaps:?}");
        // (and everything done before the end)
        let last = played.edits.iter().map(|e| e.1).fold(0.0, f32::max);
        assert!(last < CL_LEN - 0.3, "{last}");
        // (the chunks forceloaded are let go)
        let adds = played.cmds.iter().filter(|(_, c)| c.starts_with("forceload add")).count();
        let removes = played.cmds.iter().filter(|(_, c)| c.starts_with("forceload remove")).count();
        assert!(adds > 10 && adds == removes);
        // (and every stage is far from the tick's fuel)
        let worst = played.stages.iter().map(|s| s.2).fold(0.0, f64::max);
        assert!(worst < 30.0, "a stage took {worst} ms");
    }

    // ---- the land torn up round the giants as they rise, over hills, a river and trees ----
    fn hills_ground(x: i32, z: i32) -> i32 {
        60 + (x + 2 * z).div_euclid(9) + (6.0 * (x as f32 * 0.05).sin() * (z as f32 * 0.04).cos()) as i32
    }
    fn hills_river(x: i32, z: i32) -> bool {
        (z + x / 3).rem_euclid(120) < 7
    }
    fn hills_block(x: i32, z: i32, y: i32) -> &'static str {
        let g = hills_ground(x, z);
        if hills_river(x, z) {
            return if y < g - 3 { "minecraft:stone" } else if y == g - 3 { "minecraft:gravel" } else if y <= g { "minecraft:water" } else { "minecraft:air" };
        }
        if y < g {
            return if y < g - 3 { "minecraft:stone" } else { "minecraft:dirt" };
        }
        if y == g {
            return "minecraft:grass_block";
        }
        let (tx, tz) = ((x + 4).div_euclid(9) * 9, (z + 5).div_euclid(11) * 11);
        if !hills_river(tx, tz) && hash(tx, tz, 5) < 0.6 {
            let tg = hills_ground(tx, tz);
            if x == tx && z == tz && y > tg && y <= tg + 6 {
                return "minecraft:oak_log";
            }
            if (x - tx).abs() <= 2 && (z - tz).abs() <= 2 && y >= tg + 4 && y <= tg + 7 && y > g {
                return "minecraft:oak_leaves";
            }
        }
        "minecraft:air"
    }
    fn hills(x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let g = hills_ground(x, z);
        let top = (g..g + 24).rev().find(|&y| hills_block(x, z, y) != "minecraft:air").unwrap_or(g) + 1;
        Some((top, (top - below as i32..top + above as i32).map(|y| hills_block(x, z, y)).collect()))
    }

    /// The giants' land over hills: torn up from each one's feet out as it rises, the heap on the land itself (nothing left
    /// hanging, no wall at its edge), the trees gone, nothing in the crater, and every stage far under a tick's fuel.
    #[test]
    fn hv_land_is_torn_up_as_the_giants_rise() {
        crate::ground::set_test(Some(|x, z| Some(hills_ground(x, z) + 1)));
        HV_PEAK.with(|p| p.set(0));
        let plan = colossi_plan(the_laser(), &target(), true, "minecraft:overworld", 37.0, [0.5, 65.0, 120.0]);
        let mut played = sim::play_clocked(plan, 17.0, &|x, z, b, a| hills(x, z, b, a));
        played.edits.retain(|e| e.1 < CL_HIT);
        crate::ground::set_test(None);
        let peak = HV_PEAK.with(std::cell::Cell::get);
        // (the world as the edits leave it: the columns they touch, 16 under the ground to 40 over it)
        const Y0: i32 = 16;
        let mut names: Vec<&'static str> = vec!["minecraft:air"];
        let mut world: std::collections::HashMap<(i32, i32), Vec<u8>> = Default::default();
        let id = |names: &mut Vec<&'static str>, n: &'static str| names.iter().position(|m| *m == n).unwrap_or_else(|| {
            names.push(n);
            names.len() - 1
        }) as u8;
        let (mut runs, mut chunks, mut first) = (0usize, 0usize, f32::MAX);
        let crater = CRATER_R as f32 + 1.0;
        for (_, due, b) in &played.edits {
            let mut seen: std::collections::HashSet<(i32, i32)> = Default::default();
            for r in &b.runs {
                assert!(r.surface.is_none());
                assert!((r.x as f32 + 0.5).hypot(r.z as f32 + 0.5) >= crater, "an edit in the crater at {} {} due {due}", r.x, r.z);
                seen.insert((r.x >> 4, r.z >> 4));
                runs += 1;
                let g = hills_ground(r.x, r.z);
                let col = world.entry((r.x, r.z)).or_insert_with(|| (g - Y0..g + 40).map(|y| id(&mut names, hills_block(r.x, r.z, y))).collect());
                let blk = b.palette[r.block as usize];
                let only = r.only.map(|f| b.filters[f as usize]);
                for y in r.y..r.y + r.height as i32 {
                    let i = y - (g - Y0);
                    assert!((0..col.len() as i32).contains(&i), "an edit out of the window at {} {y} {}", r.x, r.z);
                    let cur = names[col[i as usize] as usize];
                    let ok = match only {
                        None => true,
                        Some(HV_INTO) => matches!(cur, "minecraft:air" | "minecraft:water" | "minecraft:short_grass"),
                        Some("#minecraft:leaves") => cur.ends_with("_leaves"),
                        Some(f) => panic!("filter {f}"),
                    };
                    if ok {
                        col[i as usize] = id(&mut names, blk);
                    }
                }
            }
            chunks += seen.len();
            first = first.min(*due);
        }
        // (the lifts as the giants rise, the rest as the feet stamp and the hammers are driven in)
        let rising = played.edits.iter().filter(|e| e.1 < 7.0).map(|e| e.2.runs.len()).sum::<usize>();
        let after = played.edits.iter().filter(|e| e.1 >= 7.0).map(|e| e.2.runs.len()).sum::<usize>();
        let last_rise = played.edits.iter().filter(|e| e.1 < 7.0).map(|e| e.1).fold(0.0, f32::max);
        println!("{} edits, {runs} runs ({rising} by 7 s, {after} after), {chunks} chunk edits, first {first:.2} s, last of the rise {last_rise:.2} s; heaviest stage {peak}", played.edits.len());
        assert!(first >= 0.5 && last_rise < 7.0 && rising > after, "first {first}, last {last_rise}");
        let solid = |n: &str| !matches!(n, "minecraft:air" | "minecraft:water") && !n.ends_with("_leaves") && !n.ends_with("_log");
        let heap = |n: &str| HV_FAM.iter().any(|f| f.contains(&n));
        let added = |x: i32, z: i32, world: &std::collections::HashMap<(i32, i32), Vec<u8>>| -> i32 {
            let g = hills_ground(x, z);
            let Some(col) = world.get(&(x, z)) else { return 0 };
            let top = (0..col.len()).rev().find(|&i| solid(names[col[i] as usize])).map_or(0, |i| i as i32) + g - Y0;
            top - g
        };
        let (mut floating, mut walls, mut logs, mut heaped, mut cracked) = (0, Vec::new(), 0, 0, 0);
        for (&(x, z), col) in &world {
            let a = added(x, z, &world);
            for i in 1..col.len() {
                let (n, under) = (names[col[i] as usize], names[col[i - 1] as usize]);
                if heap(n) && !solid(under) {
                    floating += 1;
                }
                if n.ends_with("_log") && a != 0 {
                    logs += 1;
                }
            }
            if a < -1 {
                cracked += 1;
            }
            if a > 0 {
                heaped += 1;
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    // (against the land as it was, a crack's side not counted; the river's water is the land there)
                    if added(x + dx, z + dz, &world) == 0 && !hills_river(x + dx, z + dz) {
                        walls.push(a);
                    }
                }
            }
        }
        // (`HV_MAP=file.ppm`: the land round the first giant from above, for a look: each column's top block in about its
        // colour, lit from the north-west by the heights, cracks black, water blue)
        if let Ok(path) = std::env::var("HV_MAP") {
            let hv = Heave::new(&target(), 0);
            let (cx, cz, r) = (hv.o[0].round() as i32, hv.o[1].round() as i32, 140);
            let colour = |n: &str| -> [f32; 3] {
                match n.trim_start_matches("minecraft:") {
                    "grass_block" => [0.36, 0.6, 0.25],
                    "cobbled_deepslate" => [0.3, 0.3, 0.31],
                    "deepslate" => [0.33, 0.33, 0.35],
                    "tuff" => [0.42, 0.43, 0.38],
                    "stone" => [0.49, 0.49, 0.49],
                    "cobblestone" => [0.45, 0.45, 0.45],
                    "andesite" => [0.53, 0.53, 0.52],
                    "coarse_dirt" => [0.47, 0.33, 0.23],
                    "dirt" => [0.53, 0.38, 0.26],
                    "rooted_dirt" => [0.56, 0.41, 0.31],
                    "packed_mud" => [0.56, 0.42, 0.31],
                    "gravel" => [0.51, 0.48, 0.47],
                    _ => [0.75, 0.68, 0.55],
                }
            };
            let mut img = format!("P6 {} {} 255\n", 2 * r, 2 * r).into_bytes();
            for z in cz - r..cz + r {
                for x in cx - r..cx + r {
                    let a = added(x, z, &world);
                    let g = hills_ground(x, z);
                    let topname = world.get(&(x, z)).map_or(hills_block(x, z, g), |c| names[c[(a + Y0).clamp(0, c.len() as i32 - 1) as usize] as usize]);
                    let px: [u8; 3] = if hills_river(x, z) && a == 0 {
                        [40, 70, 200]
                    } else if a < -1 {
                        [0, 0, 0]
                    } else {
                        let slope = (a + g - added(x - 1, z - 1, &world) - hills_ground(x - 1, z - 1)) as f32;
                        let l = (1.0 + 0.22 * slope).clamp(0.45, 1.5) * if a < 0 { 0.6 } else { 1.0 };
                        colour(topname).map(|v| (v * l * 255.0).min(255.0) as u8)
                    };
                    img.extend_from_slice(&px);
                }
            }
            std::fs::write(path, img).unwrap();
        }
        walls.sort_unstable();
        let over = walls.iter().filter(|&&w| w > 2).count();
        println!("{heaped} columns heaped, {cracked} cracked; {} edges against the land, {over} over 2 high (the highest {:?})", walls.len(), walls.last());
        assert_eq!(floating, 0, "heap blocks over air");
        assert_eq!(logs, 0, "logs left in the heaps or the cracks");
        assert!(cracked > 1000, "{cracked} columns cracked");
        assert!(over * 100 <= walls.len() && walls.last().is_some_and(|&w| w <= 3), "{over} of {} edges a wall over 2", walls.len());
        // (a stage stops once it has spent HV_STAGE, so at most one chunk past it)
        assert!(peak < HV_STAGE + 4_000_000, "a stage spent {peak}");
    }

    /// Land not loaded when it is first read is asked again, and torn up when it comes, before the hammers fall.
    #[test]
    fn hv_land_not_loaded_at_first_is_asked_again() {
        crate::ground::set_test(Some(|x, z| Some(hills_ground(x, z) + 1)));
        let runs = |late: bool| {
            let asked: RefCell<std::collections::HashSet<(i32, i32)>> = Default::default();
            let plan = colossi_plan(the_laser(), &target(), true, "minecraft:overworld", 37.0, [0.5, 65.0, 120.0]);
            let mut played = sim::play_clocked(plan, 17.0, &|x, z, b, a| {
                if late && hash(x >> 4, z >> 4, 3) < 0.3 && asked.borrow_mut().insert((x, z)) {
                    return None;
                }
                hills(x, z, b, a)
            });
            // (the heaves' edits: the blast's, from CL_HIT, are not these tests')
            played.edits.retain(|e| e.1 < CL_HIT);
            let lifts: Vec<f32> = played.edits.iter().filter(|e| e.2.runs.iter().any(|r| r.only.is_some())).map(|e| e.1).collect();
            (played.edits.iter().map(|e| e.2.runs.len()).sum::<usize>(), lifts.iter().copied().fold(0.0, f32::max))
        };
        let (all, _) = runs(false);
        let (late, last) = runs(true);
        crate::ground::set_test(None);
        println!("{all} runs with the land loaded, {late} with some of it late (the last lift due {last:.2} s)");
        assert!(late * 100 >= all * 99 && last < 16.0, "{late} of {all}, the last at {last}");
    }

    /// `CB_OUT=path cargo test --release cl_write_table -- --ignored`: the table the pass reads, for tools/preview.py.
    #[test]
    #[ignore]
    fn cl_write_table() {
        let t = target();
        // (PL_HILLS=H: the giants and their blows on tools/preview's hills (main.rs's hills_h), as the survey would put them)
        let hills: f32 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap_or(0.0));
        let hh = |x: f32, z: f32| hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin());
        let ground: [i32; 5] = std::array::from_fn(|g| {
            let (cx, cz) = middle(&t, g, &statues()[g]);
            64 + hh(cx as f32 + 0.5, cz as f32 + 0.5).round() as i32
        });
        let mut w = table_words(&t, ground);
        for (g, st) in statues().iter().enumerate() {
            let [sx, sz] = slam_point(&t, g, st);
            w[REC0 + REC * g + 45] = ((64.0 + hh(sx as f32 + 0.5, sz as f32 + 0.5).round()) as f32).to_bits();
        }
        let text: String = w.iter().enumerate().filter(|(_, v)| **v != 0).map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }

    /// Whether an edit is a statue's (`place_statue`'s: laid clear of the player, no run filtered; the heaps' runs all
    /// are, the blast's are not laid clear of the player).
    fn is_statue(b: &Blocks) -> bool {
        // (and within the statues' boxes, where the blast's field and the wrecks never go: `Crater::clear`)
        let cr = Crater::new(&target());
        b.clear_of_player && !b.runs.is_empty() && b.runs.iter().all(|r| r.only.is_none() && r.surface.is_none() && b.palette[r.block as usize] != CR_AIR) && b.runs.iter().all(|r| !cr.clear_box(r.x, r.z))
    }

    /// Each giant's statue edits (when each went in, its blocks; the giant on ground `ground`) against its line, which reveals
    /// height y of a grid ys tall at ts + CL_SWEEP (1 - y / ys) (the pass's `cl_cut`): the least time any block was in before
    /// its reveal, and when its first and last edits went in.
    fn statue_margins(statue: &[(f32, &Blocks)], ground: i32) -> [(f32, f32, f32); 5] {
        let t = target();
        std::array::from_fn(|g| {
            let st = &statues()[g];
            let (ox, oz) = corner(&t, g, st);
            let (ox, oz) = (ox + i32::from(st.pshift[0]), oz + i32::from(st.pshift[2]));
            let (xs, zs) = (i32::from(st.pgrid[0]), i32::from(st.pgrid[2]));
            let ts = T_SWEEP0 + T_SWEEP_STEP * g as f32;
            let _ = ground;
            let (mut margin, mut first, mut last) = (f32::MAX, f32::MAX, 0.0f32);
            // (a crouched block's height is not the height the line reads, the standing one's: the line starts down from
            // the top at ts, and reveals nothing before it)
            for (at, b) in statue {
                for r in b.runs.iter().filter(|r| r.x >= ox && r.x < ox + xs && r.z >= oz && r.z < oz + zs) {
                    margin = margin.min(ts - at);
                    first = first.min(*at);
                    last = last.max(*at);
                }
            }
            (margin, first, last)
        })
    }

    /// `cargo test --release cl_edit_profile -- --ignored --nocapture`: the statues' edits a quarter second at a time (edits,
    /// runs, blocks, chunk columns changed, the pace's cost units), the chunk resends in all, each giant's first and last
    /// block against its sweep line's reveal, and the heaviest stage by the meter.
    #[test]
    #[ignore]
    fn cl_edit_profile() {
        crate::ground::set_test(Some(|_, _| Some(65)));
        let mut ev = colossi_plan(the_laser(), &target(), true, "minecraft:overworld", 37.0, [0.5, 65.0, 120.0]);
        // (the stages run in time order, each metered on its own)
        let mut worst = (0u64, 0.0f32);
        let mut statue: Vec<(f32, Blocks)> = Vec::new();
        let mut blast: Vec<(f32, Blocks)> = Vec::new();
        let mut i = 0;
        ev.sort_by(|a, b| a.0.total_cmp(&b.0));
        while i < ev.len() {
            let (t, act) = std::mem::replace(&mut ev[i], (0.0, Act::Cmd(String::new())));
            i += 1;
            match act {
                Act::Blocks(b) if is_statue(&b) => statue.push((t, *b)),
                Act::Blocks(b) if b.clear_of_player => blast.push((t, *b)),
                Act::Later(job) | Act::Soon(job) => {
                    crate::meter::reset();
                    let more = job();
                    if crate::meter::spent() > worst.0 {
                        worst = (crate::meter::spent(), t);
                    }
                    let mut rest = ev.split_off(i);
                    rest.extend(more);
                    rest.sort_by(|a, b| a.0.total_cmp(&b.0));
                    ev.extend(rest);
                }
                _ => {}
            }
        }
        crate::ground::set_test(None);
        type Q = (usize, usize, u64, std::collections::HashSet<(i32, i32)>, u32);
        let mut qs: std::collections::BTreeMap<u32, Q> = Default::default();
        let (mut runs, mut blocks, mut resends, mut cost) = (0usize, 0u64, 0usize, 0u64);
        for (t, b) in &statue {
            let e = qs.entry((t / 0.25).floor() as u32).or_default();
            let chunks: std::collections::HashSet<(i32, i32)> = b.runs.iter().map(|r| (r.x >> 4, r.z >> 4)).collect();
            let c = crate::pace::cost(&b.runs);
            e.0 += 1;
            e.1 += b.runs.len();
            e.2 += b.runs.iter().map(|r| u64::from(r.height)).sum::<u64>();
            e.3.extend(chunks.iter().copied());
            e.4 += c;
            runs += b.runs.len();
            blocks += b.runs.iter().map(|r| u64::from(r.height)).sum::<u64>();
            resends += chunks.len();
            cost += u64::from(c);
        }
        println!("statues: {} edits, {runs} runs, {blocks} blocks, {resends} chunk resends, {cost} pace units", statue.len());
        println!("   time  edits    runs  blocks chunks units");
        for (k, v) in &qs {
            println!("{:6.2}  {:5} {:7} {:7} {:6} {:5}", *k as f32 * 0.25, v.0, v.1, v.2, v.3.len(), v.4);
        }
        let statue: Vec<(f32, &Blocks)> = statue.iter().map(|e| (e.0, &e.1)).collect();
        for (g, (margin, first, last)) in statue_margins(&statue, 65).into_iter().enumerate() {
            let ts = T_SWEEP0 + T_SWEEP_STEP * g as f32;
            println!("giant {g}: first block in at {first:.2} s, last at {last:.2} s, sweep {ts:.2}-{:.2} s, least margin before its reveal {margin:.2} s", ts + CL_SWEEP);
        }
        println!("heaviest stage: {:.1}M at {:.2} s", worst.0 as f64 / 1e6, worst.1);
        // (the crater's, the field's and the wrecks' edits, a quarter second at a time, as due)
        let mut qs: std::collections::BTreeMap<u32, Q> = Default::default();
        let (mut runs, mut blocks, mut resends, mut wreck) = (0usize, 0u64, 0usize, 0u64);
        for (t, b) in &blast {
            let e = qs.entry((t / 0.25).floor() as u32).or_default();
            let chunks: std::collections::HashSet<(i32, i32)> = b.runs.iter().map(|r| (r.x >> 4, r.z >> 4)).collect();
            let n: u64 = b.runs.iter().map(|r| u64::from(r.height)).sum();
            e.0 += 1;
            e.1 += b.runs.len();
            e.2 += n;
            e.3.extend(chunks.iter().copied());
            e.4 += crate::pace::cost(&b.runs);
            runs += b.runs.len();
            blocks += n;
            resends += chunks.len();
            if is_wreck(b) {
                wreck += n;
            }
        }
        println!("crater, field and wrecks: {} edits, {runs} runs, {blocks} blocks set (air included; {wreck} of the wrecks), {resends} chunk resends", blast.len());
        println!("   time  edits    runs  blocks chunks units");
        for (k, v) in &qs {
            println!("{:6.2}  {:5} {:7} {:7} {:6} {:5}", *k as f32 * 0.25, v.0, v.1, v.2, v.3.len(), v.4);
        }
    }

    /// The blast's land laid into a model of the world: each column the crater, the field or a wreck touches, 100 under its
    /// ground to 60 over it (`ground`, `block`: the land as it was), as names. Runs filtered as the game filters them.
    struct CrWorld {
        names: Vec<&'static str>,
        cols: std::collections::HashMap<(i32, i32), Vec<u8>>,
    }
    const CW_DN: i32 = 100;
    const CW_UP: i32 = 60;
    impl CrWorld {
        fn id(&mut self, n: &'static str) -> u8 {
            self.names.iter().position(|m| *m == n).unwrap_or_else(|| {
                self.names.push(n);
                self.names.len() - 1
            }) as u8
        }
        fn lay(&mut self, b: &Blocks, ground: &dyn Fn(i32, i32) -> i32, block: &dyn Fn(i32, i32, i32) -> &'static str) {
            let mut heights: std::collections::HashMap<(i32, i32), i32> = Default::default();
            for r in &b.runs {
                let g = ground(r.x, r.z);
                if !self.cols.contains_key(&(r.x, r.z)) {
                    let col: Vec<u8> = (g - CW_DN..g + CW_UP).map(|y| self.id(block(r.x, r.z, y))).collect();
                    self.cols.insert((r.x, r.z), col);
                }
                let names = self.names.clone();
                let base = match r.surface {
                    None => 0,
                    Some(_) => *heights.entry((r.x, r.z)).or_insert_with(|| {
                        let col = &self.cols[&(r.x, r.z)];
                        (0..col.len()).rev().find(|&i| !matches!(names[col[i] as usize], "minecraft:air" | "minecraft:snow") && !names[col[i] as usize].contains("_leaves")).map_or(0, |i| i as i32 + 1) + g - CW_DN
                    }),
                };
                let blk = b.palette[r.block as usize];
                let bi = self.id(blk);
                let names = self.names.clone();
                let only = r.only.map(|f| b.filters[f as usize]);
                let col = self.cols.get_mut(&(r.x, r.z)).unwrap();
                for y in base + r.y..base + r.y + r.height as i32 {
                    let i = y - (g - CW_DN);
                    if !(0..col.len() as i32).contains(&i) {
                        assert!(blk == CR_AIR || only.is_some() || hm_block(blk), "{blk} out of the window at {} {y} {}", r.x, r.z);
                        continue;
                    }
                    let cur = names[col[i as usize] as usize];
                    let ok = match only {
                        None => true,
                        Some("#minecraft:logs") => cur.contains("_log"),
                        Some("#minecraft:leaves") => cur.contains("_leaves"),
                        Some("minecraft:snow") => cur == "minecraft:snow",
                        Some("minecraft:grass_block") => cur == "minecraft:grass_block",
                        Some(HV_INTO) => matches!(cur, "minecraft:air" | "minecraft:water" | "minecraft:short_grass" | "minecraft:snow"),
                        Some(super::super::TIDY_LOOSE) => matches!(cur, "minecraft:short_grass" | "minecraft:fern"),
                        Some(f) => panic!("filter {f}"),
                    };
                    if ok {
                        col[i as usize] = bi;
                    }
                }
            }
        }
        fn name(&self, x: i32, z: i32, y: i32, ground: &dyn Fn(i32, i32) -> i32) -> Option<&'static str> {
            let g = ground(x, z);
            self.cols.get(&(x, z)).and_then(|c| c.get((y - (g - CW_DN)) as usize)).map(|&i| self.names[i as usize])
        }
        /// `CR_MAP`'s picture: the land from above out to `r`, each column's top in about its colour, lit by its slope
        /// from the west; the glow bright green, the wrecks' stone violet-grey, felled logs brown, leaves dark green.
        fn map(&self, path: &str, r: i32, ground: &dyn Fn(i32, i32) -> i32, block: &dyn Fn(i32, i32, i32) -> &'static str) {
            let top = |x: i32, z: i32| -> (i32, &'static str) {
                let g = ground(x, z);
                match self.cols.get(&(x, z)) {
                    Some(col) => {
                        let i = (0..col.len()).rev().find(|&i| self.names[col[i] as usize] != "minecraft:air").unwrap_or(0);
                        (i as i32 + g - CW_DN, self.names[col[i] as usize])
                    }
                    None => {
                        let y = (g - 4..g + 40).rev().find(|&y| block(x, z, y) != "minecraft:air").unwrap_or(g);
                        (y, block(x, z, y))
                    }
                }
            };
            let mut img = format!("P6 {} {} 255\n", 2 * r, 2 * r).into_bytes();
            for z in -r..r {
                for x in -r..r {
                    let (y, n) = top(x, z);
                    let (w, _) = top(x - 1, z);
                    let sh = (1.0 + 0.1 * (y - w) as f32).clamp(0.45, 1.6) * (0.85 + 0.004 * (y - 40) as f32).clamp(0.5, 1.3);
                    let c: [f32; 3] = match n.trim_start_matches("minecraft:").split('[').next().unwrap_or("") {
                        "verdant_froglight" => [0.55, 1.0, 0.55],
                        "dark_prismarine" | "prismarine" => [0.2, 0.5, 0.42],
                        "sculk" => [0.05, 0.25, 0.3],
                        "water" => [0.16, 0.27, 0.8],
                        "grass_block" => [0.36, 0.6, 0.25],
                        "snow" | "snow_block" => [0.95, 0.96, 0.98],
                        "blackstone" | "polished_blackstone" | "basalt" | "smooth_basalt" | "coal_block" => [0.16, 0.15, 0.17],
                        "coarse_dirt" | "podzol" | "rooted_dirt" => [0.45, 0.32, 0.22],
                        "dirt" => [0.53, 0.38, 0.26],
                        "gravel" => [0.55, 0.52, 0.5],
                        "deepslate" | "cobbled_deepslate" => [0.3, 0.3, 0.32],
                        "tuff" => [0.42, 0.43, 0.38],
                        n if hm_block(&format!("minecraft:{n}")) => [0.5, 0.38, 0.62],
                        n if n.ends_with("_log") => [0.5, 0.3, 0.12],
                        n if n.ends_with("_leaves") => [0.1, 0.35, 0.12],
                        _ => [0.5, 0.5, 0.5],
                    };
                    img.extend_from_slice(&c.map(|v| (v * sh * 255.0).clamp(0.0, 255.0) as u8));
                }
            }
            std::fs::write(path, img).unwrap();
        }
    }
    /// Whether a block is a hammer's wreck's.
    fn hm_block(n: &str) -> bool {
        HM_HEAD.contains(&n) || HM_SHAFT.contains(&n) || HM_VEIN[1] == n
    }
    fn is_wreck(b: &Blocks) -> bool {
        !is_statue(b) && b.runs.iter().any(|r| hm_block(b.palette[r.block as usize]))
    }

    /// The blast's land over hills with a river and trees, played as the mod plays it and laid into a model of the world: the
    /// crater dug from the middle out within about a second and a half of the blast, a chunk an edit, a bowl under the
    /// target's ground, nothing left hanging, no tree left standing near it, the field past it in by 24 s.
    /// `CR_MAP=file.ppm` draws it from above (see `CrWorld::map`).
    #[test]
    fn the_crater_goes_in_as_the_blast_hides_it() {
        crate::ground::set_test(Some(|x, z| Some(hills_ground(x, z) + 1)));
        let t = target();
        let plan = colossi_plan(the_laser(), &t, true, "minecraft:overworld", 37.0, [0.5, 65.0, 120.0]);
        let played = sim::play_clocked(plan, CL_LEN, &|x, z, b, a| hills(x, z, b, a));
        crate::ground::set_test(None);
        let worst = played.stages.iter().filter(|s| s.0 >= BD_SETUP && s.0 < CL_HIT + 3.0).map(|s| s.2).fold(0.0, f64::max);
        let log = CR_LOG.with(|l| std::mem::take(&mut *l.borrow_mut()));
        if std::env::var("CR_STAGES").is_ok() {
            for s in &log {
                println!("cr stage at {:.2} (gap {:.2}): {} chunks, {:.2} ms, {:.1}M", s.0, s.1, s.2, s.3, s.4 as f64 / 1e6);
            }
        }
        let cr_worst = log.iter().map(|s| s.3).fold(0.0, f64::max);
        let cr_last = log.iter().map(|s| s.0).fold(0.0, f32::max);
        println!("{} stages of the crater's land, the heaviest {cr_worst:.2} ms, the last at {cr_last:.2} s", log.len());
        // (the crater's and the field's edits: laid clear of the player, not a statue's, not a wreck's)
        let blast: Vec<&(f32, f32, Blocks)> = played.edits.iter().filter(|e| e.2.clear_of_player && e.1 >= CL_HIT && !is_statue(&e.2) && !is_wreck(&e.2)).collect();
        let wrecks: Vec<&(f32, f32, Blocks)> = played.edits.iter().filter(|e| is_wreck(&e.2)).collect();
        let mut w = CrWorld { names: vec!["minecraft:air"], cols: Default::default() };
        let mut chunk_edits: std::collections::HashMap<(i32, i32), u32> = Default::default();
        let (mut runs, mut last, mut last_bowl, mut first) = (0usize, 0.0f32, 0.0f32, f32::MAX);
        let mut out_of_order = 0;
        let mut prev = (0.0f32, 0.0f64);
        for (now, _, b) in &blast {
            let chunks: std::collections::HashSet<(i32, i32)> = b.runs.iter().map(|r| (r.x >> 4, r.z >> 4)).collect();
            let nearest = b.runs.iter().map(|r| (f64::from(r.x) + 0.5).hypot(f64::from(r.z) + 0.5)).fold(f64::MAX, f64::min);
            runs += b.runs.len();
            w.lay(b, &hills_ground, &hills_block);
            for c in chunks {
                *chunk_edits.entry(c).or_default() += 1;
            }
            if *now < prev.0 + 0.01 && nearest + 24.0 < prev.1 {
                out_of_order += 1;
            }
            prev = (*now, nearest);
            last = last.max(*now);
            if nearest < CR_READ {
                last_bowl = last_bowl.max(*now);
            }
            first = first.min(*now);
        }
        let solid = |n: &str| !matches!(n, "minecraft:air" | "minecraft:water");
        let cr = Crater::new(&t);
        let (mut shallow, mut hanging, mut trees, mut glow, mut dug) = (0, 0, 0, 0, 0);
        let mut deepest = 0;
        for (&(x, z), col) in &w.cols {
            let rc = (f64::from(x) + 0.5).hypot(f64::from(z) + 0.5);
            let g = hills_ground(x, z);
            let top = (0..col.len()).rev().find(|&i| solid(w.names[col[i] as usize]) && !w.names[col[i] as usize].contains("_leaves") && !w.names[col[i] as usize].contains("_log"));
            let top = top.map_or(g - CW_DN, |i| i as i32 + g - CW_DN);
            if rc < 0.9 * CRATER_R {
                dug += 1;
                if top >= g.min(t.block[1]) {
                    shallow += 1;
                }
                deepest = deepest.max(t.block[1] - top);
                glow += usize::from(w.names[col[(top - (g - CW_DN)) as usize] as usize] == CR_GLOW);
            }
            let a = cr.at(x, z);
            if rc < CR_READ && a.rc - a.rw < 40.0 {
                // (near it no tree standing: no leaves, no upright log over a stump's height)
                trees += col.iter().enumerate().filter(|&(i, &c)| {
                    let n = w.names[c as usize];
                    n.contains("_leaves") || n.ends_with("_log") && i as i32 + g - CW_DN > top + 2
                }).count();
            }
            if rc < CR_READ {
                // (nothing over air: the lowest air in the column, and anything solid above it)
                if let Some(a) = col.iter().position(|&c| w.names[c as usize] == "minecraft:air") {
                    hanging += col[a..].iter().filter(|&&c| solid(w.names[c as usize])).count();
                }
            }
        }
        let resent = chunk_edits.values().filter(|&&n| n > 1).count();
        if std::env::var("CR_PROFILE").is_ok() {
            // (`CR_PROFILE=1`: the crater's, the field's and the wrecks' edits a quarter second at a time as they went in:
            // edits, runs, chunks changed, the pace's cost units)
            let mut qs: std::collections::BTreeMap<u32, (usize, usize, usize, u32)> = Default::default();
            for (now, _, b) in blast.iter().chain(wrecks.iter()) {
                let e = qs.entry((now / 0.25).floor() as u32).or_default();
                let chunks: std::collections::HashSet<(i32, i32)> = b.runs.iter().map(|r| (r.x >> 4, r.z >> 4)).collect();
                e.0 += 1;
                e.1 += b.runs.len();
                e.2 += chunks.len();
                e.3 += crate::pace::cost(&b.runs);
            }
            println!("   time  edits    runs chunks units");
            for (k, v) in &qs {
                println!("{:6.2}  {:5} {:7} {:6} {:5}", *k as f32 * 0.25, v.0, v.1, v.2, v.3);
            }
        }
        println!(
            "{} blast edits, {runs} runs, {} chunks, first in at {first:.2} s, the crater's last at {last_bowl:.2} s, the field's at {last:.2} s; {dug} columns in the bowl, the deepest {deepest} under the target, {glow} glowing; {} wreck edits; worst stage {worst:.2} ms",
            blast.len(),
            chunk_edits.len(),
            wrecks.len()
        );
        if let Ok(path) = std::env::var("CR_MAP") {
            for (_, _, b) in &wrecks {
                w.lay(b, &hills_ground, &hills_block);
            }
            w.map(&path, 420, &hills_ground, &hills_block);
        }
        assert!(dug > 50_000 && shallow * 200 <= dug, "{shallow} of {dug} columns of the bowl not dug under the land");
        assert!(deepest as f64 >= CRATER_D * 0.9, "the deepest {deepest}");
        assert!(glow > 200 && glow * 12 < dug, "{glow} glowing of {dug}");
        assert_eq!(trees, 0, "trees left standing");
        assert_eq!(hanging, 0, "blocks left over air");
        assert!(first >= CL_HIT && last_bowl <= CL_HIT + 2.2 && last <= 24.0, "{first} to {last_bowl}, the field {last}");
        assert_eq!(resent, 0, "chunks edited twice");
        assert_eq!(out_of_order, 0, "edits out of order from the middle out");
        assert!(worst < 25.0, "a stage took {worst} ms");
    }

    // ---- the blast field over a snowy spruce forest (the land of the last in-game run) ----
    fn snowy_ground(x: i32, z: i32) -> i32 {
        64 + (4.0 * (x as f32 * 0.03).sin() * (z as f32 * 0.025).cos()) as i32
    }
    /// A spruce's log or leaves at (x, y, z): spruces on a jittered grid, 7-13 tall, a cone of leaves from 3 up.
    fn spruce(x: i32, z: i32, y: i32) -> Option<&'static str> {
        let (cx, cz) = (x.div_euclid(6), z.div_euclid(6));
        for oz in -1..=1 {
            for ox in -1..=1 {
                let (gx, gz) = (cx + ox, cz + oz);
                if hash(gx, gz, 301) > 0.75 {
                    continue;
                }
                let (tx, tz) = (gx * 6 + 1 + (hash(gx, gz, 302) * 4.0) as i32, gz * 6 + 1 + (hash(gx, gz, 303) * 4.0) as i32);
                let tg = snowy_ground(tx, tz);
                let th = 7 + (hash(gx, gz, 304) * 7.0) as i32;
                let lv = y - tg;
                if x == tx && z == tz && lv > 0 && lv < th {
                    return Some("minecraft:spruce_log");
                }
                let d = (x - tx).abs().max((z - tz).abs());
                if lv >= 3 && lv <= th && d <= ((th - lv + 1) / 3).min(2) {
                    return Some("minecraft:spruce_leaves");
                }
            }
        }
        None
    }
    fn snowy_block(x: i32, z: i32, y: i32) -> &'static str {
        let g = snowy_ground(x, z);
        if y < g {
            return if y < g - 3 { "minecraft:stone" } else { "minecraft:dirt" };
        }
        if y == g {
            return "minecraft:grass_block";
        }
        if let Some(b) = spruce(x, z, y) {
            return b;
        }
        // (snow on each crown's top and on the ground)
        if y == g + 1 || spruce(x, z, y - 1) == Some("minecraft:spruce_leaves") { "minecraft:snow" } else { "minecraft:air" }
    }
    fn snowy(x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let g = snowy_ground(x, z);
        let top = (g..g + 24).rev().find(|&y| snowy_block(x, z, y) != "minecraft:air").unwrap_or(g) + 1;
        Some((top, (top - below as i32..top + above as i32).map(|y| snowy_block(x, z, y)).collect()))
    }

    /// The field over a snowy spruce forest: past the rim no snow or leaves left hanging (the last run's floating snow), the
    /// trees felled lying away from the middle, snapped and stripped further out, the ground scorched, boulders strewn,
    /// fissures out of the crater glowing faintly; nothing where a statue goes; and the wrecks: every block of them
    /// joined to the ground, a few thousand a giant. `CR_MAP=file.ppm` draws it.
    #[test]
    fn the_field_and_the_wrecks_over_a_snowy_forest() {
        crate::ground::set_test(Some(|x, z| Some(snowy_ground(x, z) + 1)));
        let t = target();
        let plan = colossi_plan(the_laser(), &t, true, "minecraft:overworld", 37.0, [0.5, 65.0, 120.0]);
        let played = sim::play_clocked(plan, CL_LEN, &|x, z, b, a| snowy(x, z, b, a));
        crate::ground::set_test(None);
        let _ = CR_LOG.with(|l| std::mem::take(&mut *l.borrow_mut()));
        let cr = Crater::new(&t);
        let mut w = CrWorld { names: vec!["minecraft:air"], cols: Default::default() };
        for (_, _, b) in played.edits.iter().filter(|e| e.2.clear_of_player && e.1 >= CL_HIT && !is_statue(&e.2) && !is_wreck(&e.2)) {
            w.lay(b, &snowy_ground, &snowy_block);
        }
        let field: Vec<(i32, i32)> = w.cols.keys().copied().collect();
        // (nothing laid where a statue goes: only the trees and the snow cleared there, by their filters)
        let in_box = played.edits.iter().filter(|e| e.2.clear_of_player && e.1 >= CL_HIT && !is_statue(&e.2)).flat_map(|e| e.2.runs.iter().map(move |r| (r, &e.2))).filter(|(r, b)| b.palette[r.block as usize] != CR_AIR && !cr.clear_box(r.x, r.z) && (r.surface.is_some() || r.y + r.height as i32 - 1 > snowy_ground(r.x, r.z) || r.y < snowy_ground(r.x, r.z))).count();
        let (mut hanging, mut felled, mut stumps, mut scorched, mut rocks, mut glow_out, mut stripped, mut kept_crowns) = (0, 0, 0, 0, 0, 0, 0, 0);
        for &(x, z) in &field {
            let a = cr.at(x, z);
            let e = a.rc - a.rw;
            let g = snowy_ground(x, z);
            let col = &w.cols[&(x, z)];
            let nm = |y: i32| w.names[col[(y - (g - CW_DN)) as usize] as usize];
            if e < CR_RIM || a.rc >= BD_R {
                continue;
            }
            // (snow over air, past the rim: the floating snow of the last run)
            for y in g + 2..g + 30 {
                if nm(y) == "minecraft:snow" && nm(y - 1) == "minecraft:air" {
                    hanging += 1;
                }
            }
            let n0 = nm(g);
            felled += usize::from(nm(g + 1).contains("_log[axis"));
            stumps += usize::from(nm(g + 1) == "minecraft:spruce_log" && nm(g + 3) == "minecraft:air");
            scorched += usize::from(matches!(n0, "minecraft:coarse_dirt" | "minecraft:podzol" | "minecraft:blackstone" | "minecraft:basalt" | "minecraft:coal_block" | "minecraft:smooth_basalt" | "minecraft:gravel"));
            rocks += usize::from(BD_ROCK.contains(&nm(g + 1)));
            glow_out += usize::from((g - 12..g).any(|y| nm(y) == CR_GLOW));
            if e > 170.0 && snowy_block(x, z, g + 9) == "minecraft:spruce_leaves" && nm(g + 9) == "minecraft:air" {
                stripped += 1;
            }
        }
        // (far out, past the giants, most crowns still there: the field thins out, it does not stop at a circle)
        for z in (-BD_R as i32..BD_R as i32).step_by(3) {
            for x in (-BD_R as i32..BD_R as i32).step_by(3) {
                let a = cr.at(x, z);
                if a.rc - a.rw > 170.0 && snowy_block(x, z, snowy_ground(x, z) + 9) == "minecraft:spruce_leaves" && w.name(x, z, snowy_ground(x, z) + 9, &snowy_ground).is_none_or(|n| n != "minecraft:air") {
                    kept_crowns += 1;
                }
            }
        }
        // the wrecks: each a few thousand blocks, every one joined to the ground through the others
        let mut solid: std::collections::HashSet<(i32, i32, i32)> = Default::default();
        let mut per = [0usize; 5];
        for (_, _, b) in played.edits.iter().filter(|e| is_wreck(&e.2)) {
            for r in &b.runs {
                let blk = b.palette[r.block as usize];
                let g = (0..5).min_by_key(|&g| (r.x - cr.slams[g].0).pow(2) + (r.z - cr.slams[g].1).pow(2)).unwrap();
                for y in r.y..r.y + r.height as i32 {
                    if blk != CR_AIR && solid.insert((r.x, y, r.z)) {
                        per[g] += 1;
                    }
                }
            }
            w.lay(b, &snowy_ground, &snowy_block);
        }
        // (a wreck block rests on the ground where what is under it is the land's, not air and not the wreck's)
        let ground_at = |x: i32, y: i32, z: i32| w.name(x, z, y, &snowy_ground).is_some_and(|n| !matches!(n, "minecraft:air" | "minecraft:water") && !hm_block(n) && n != CR_GLOW && !HM_VEIN.contains(&n));
        let mut seen: std::collections::HashSet<(i32, i32, i32)> = solid.iter().copied().filter(|&(x, y, z)| ground_at(x, y - 1, z)).collect();
        let mut todo: Vec<(i32, i32, i32)> = seen.iter().copied().collect();
        while let Some((x, y, z)) = todo.pop() {
            for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                let p = (x + dx, y + dy, z + dz);
                if solid.contains(&p) && seen.insert(p) {
                    todo.push(p);
                }
            }
        }
        let floating = solid.len() - seen.len();
        for p in solid.iter().filter(|p| !seen.contains(p)).take(10) {
            println!("wreck block not joined: {p:?} {:?} under {:?}", w.name(p.0, p.2, p.1, &snowy_ground), w.name(p.0, p.2, p.1 - 1, &snowy_ground));
        }
        println!(
            "field: {} columns; {hanging} snow or leaves over air; {felled} felled logs, {stumps} stumps, {scorched} scorched, {rocks} boulder or rubble columns, {glow_out} glowing low in fissures past the edge; far out {stripped} crowns stripped, {kept_crowns} kept; {in_box} columns in a statue's box; wrecks {per:?} blocks, {floating} not joined to the ground",
            field.len()
        );
        if let Ok(path) = std::env::var("CR_MAP") {
            w.map(&path.replace(".ppm", "_snowy.ppm"), 420, &snowy_ground, &snowy_block);
        }
        assert_eq!(hanging, 0, "snow or leaves left hanging");
        assert!(felled > 2_000 && stumps > 300, "{felled} felled, {stumps} stumps");
        assert!(scorched > 20_000 && rocks > 1_000 && glow_out > 30, "{scorched} scorched, {rocks} rocks, {glow_out} glowing");
        assert!(stripped > 100 && kept_crowns > 100, "{stripped} stripped, {kept_crowns} kept");
        assert_eq!(in_box, 0, "the field in a statue's box");
        assert!(per.iter().all(|&n| n > 2_000), "wrecks {per:?}");
        assert_eq!(floating, 0, "wreck blocks not joined to the ground");
    }
}
