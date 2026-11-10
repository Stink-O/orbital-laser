//! The Sky Breaks' hand (shaders/skybreak.wgsl's `[hand]` draws it): the one behind the sky punches through it as it
//! cracks, and at the end throws its fist straight back down through the hole and slams it into the land on the
//! target. This lays its crater: the land caved in round where the fist went in, a bowl (SB_BOWL) falling away in broken
//! steps to the fist's own print at its bottom (the four knuckles' dents, the middle one's deepest, the flat of the
//! fingers behind them, the row of their second joints; keep `HD_KNUCKLES` in step with the pass's `hd_knuckle`), the
//! dark of what is behind the sky pressed into that (obsidian, blackstone, a fleck of crying obsidian), the bowl's floor
//! crushed stone, its outer steps tilted turf; the earth it pushed out heaped round it, cracks running out from it, and
//! past that, out to SB_BAND, everything that stood swept off and the trees laid flat pointing away. Through
//! `world.edit-blocks`, a chunk at a time on what a read says stands there, worked out as the hand comes down and let in
//! from the slam, the middle first, paced like the other lasers' land (pace.rs).
//!
//! The pass's words for it are at SB_HD (`Hand::words`): where it comes down, which way, which hand, the land's height there.
use super::nuke::{Kind, LEAVES, LOG_X, LOG_Z, kind};
use super::sb_lodge::{Col, Shard, column_of, heap_block, qnoise};
use super::skybreak::{SB_CRACK, SB_H, TAU};
use super::*;
use std::cell::RefCell;
use std::rc::Rc;

/// The first shard the arm drags up falls off it (skybreak.wgsl's HD_LET_GO).
pub(super) const SB_LET_GO: f32 = 10.0;
/// The eye flares; the hand comes down through the hole; it slams the land (skybreak.wgsl's HD_FLARE, HD_DOWN, HD_PRESS).
pub(super) const SB_FLARE: f32 = 35.1;
pub(super) const SB_DOWN: f32 = 36.0;
pub(super) const SB_PRESS: f32 = 37.5;
/// Its words in the pass's table (render.set-data): skybreak.wgsl's HD. Past the table's own (to SB_WORDS) and the lift's
/// (sb_lift.rs's SB_LF, 12288 to 22144).
pub(super) const SB_HD: usize = 24_576;
pub(super) const SB_HDW: usize = 16;
/// Its size, blocks to its bones' unit (skybreak.wgsl's HD_SC), and how deep its knuckles go into the land, in its bones'
/// units (the pass's `deep`).
pub(super) const SB_SC: f64 = 2.8;
const SB_DEEP: f64 = 12.0;
/// The bowl the land caves into round it: its radius along its back and across it (its bones' units; ragged by a tenth),
/// how deep it is at its middle (blocks), and the broken steps it falls away in (where, a share of its radius, and how far
/// each drops, blocks).
const SB_BOWL: [f64; 2] = [24.0, 25.5];
const SB_BOWL_DEEP: f64 = 20.0;
const SB_STEPS: [(f64, f64); 3] = [(0.92, 2.0), (0.77, 2.6), (0.6, 2.2)];
/// The earth it pushed out heaped round it, out to this share of the bowl's radius; past that, out to SB_BAND blocks
/// further, what stood is swept off and the trees laid flat.
const SB_RIM: f64 = 1.4;
const SB_BAND: f64 = 24.0;
/// Mobs and dropped items this near it die.
const SB_KILL: i32 = 125;
/// The blocks read under each column's top; how many chunks a read asks at a time, how many may be out at once; a stage's
/// work on the blocks, counted.
const SB_BELOW: u32 = 40;
const SB_LOT: usize = 12;
const SB_FLIGHT: usize = 3;
const SB_TICK: u64 = 6_000_000;
/// The most runs of blocks a stage lets in once the fist is down.
const SB_RUNS: usize = 9_000;
/// A chunk not loaded as its blocks are wanted is asked again until this, then left out (and said so).
const SB_GIVE_UP: f32 = super::skybreak::SB_LEN - 3.0;

/// The fist's knuckles as they go into the land (u out along its back from the middle of its face, v across to its thumb;
/// its bones' units: skybreak.wgsl's `hd_knuckle`, the face's middle HD_FIST_MID in from the wrist's line): each one's place, how
/// much less deep it goes than the middle one, its radius.
pub(super) const HD_KNUCKLES: [(f64, f64, f64, f64); 4] = [(6.9, 10.9, 0.5, 4.0), (7.6, 3.5, 0.0, 4.2), (6.4, -3.9, 1.4, 3.8), (4.0, -11.0, 3.0, 3.3)];
/// The fist's face: its middle (u, v), half its size, the radius of its corners (its bones' units).
const HD_FACE: ([f64; 2], [f64; 2], f64) = ([0.0, 0.2], [11.8, 14.6], 4.0);

/// What part of the crater a column is in.
#[derive(Clone, Copy, PartialEq, Debug)]
enum Part {
    /// the fist's print, at the bottom
    Print,
    /// the bowl's floor, and the edge of one of its broken steps
    Bowl,
    Step,
    /// the earth heaped round it
    Rim,
    /// swept: what stood there is gone, its trees laid flat
    Band,
    Out,
}
/// Where the fist comes down, and its crater.
pub(super) struct Print {
    /// The middle of its face (x, z from the target's column), the way the back of its hand faces (side on to the player),
    /// which hand (its thumb's side: across is `side` times (dz, -dx)).
    pub site: [f64; 2],
    pub dir: [f64; 2],
    pub side: f64,
    /// The land's height at it, from the target's ground (once asked).
    pub g0: f64,
    cracks: Vec<[f64; 5]>,
    seed: u32,
    /// Where the panes lie, and how far round each its blocks are.
    panes: Vec<([f64; 2], f64)>,
}

/// Distance from p to the segment a-b (2D), and how far along it.
fn seg(p: [f64; 2], a: [f64; 2], b: [f64; 2]) -> (f64, f64) {
    let (ex, ez) = (b[0] - a[0], b[1] - a[1]);
    let h = (((p[0] - a[0]) * ex + (p[1] - a[1]) * ez) / (ex * ex + ez * ez).max(1e-9)).clamp(0.0, 1.0);
    let (dx, dz) = (p[0] - a[0] - ex * h, p[1] - a[1] - ez * h);
    ((dx * dx + dz * dz).sqrt(), h)
}
fn smooth(a: f64, b: f64, x: f64) -> f64 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}
/// How far (x, y) is outside a box with rounded corners round the origin (half-size h, corner radius r).
fn rbox(x: f64, y: f64, h: [f64; 2], r: f64) -> f64 {
    let (qx, qy) = (x.abs() - h[0] + r, y.abs() - h[1] + r);
    qx.max(0.0).hypot(qy.max(0.0)) + qx.max(qy).min(0.0) - r
}

impl Print {
    /// On the target (the middle of its face on the target's column), side on to the player at `me` (from the target's
    /// ground): the back of the fist faces square to the way they look, to one side or the other by the seed (`shards`:
    /// where the panes lie; their blocks are left alone but where the bowl digs).
    pub fn new(me: [f64; 3], shards: &[Shard], seed: u32) -> Print {
        let bme = if me[0].hypot(me[2]) > 1.0 { me[2].atan2(me[0]) } else { TAU * mh(3, seed, 0x1a1) };
        let first = if mh(1, seed, 0x1a2) < 0.5 { 1.0 } else { -1.0 };
        let a = bme + first * 0.5 * PI;
        let dir = [a.cos(), a.sin()];
        // (which hand: by which side of `dir` the player is, as ever; by the seed for a player on the target)
        let cross = me[0] * dir[1] - me[2] * dir[0];
        let side = if me[0].hypot(me[2]) > 1.0 { if cross >= 0.0 { 1.0 } else { -1.0 } } else { first };
        let panes = shards.iter().map(|s| (s.site, 0.5 * s.size() + 8.0)).collect();
        let mut p = Print { site: [0.0, 0.0], dir, side, g0: 0.0, cracks: Vec::new(), seed, panes };
        p.make_cracks();
        p
    }
    /// Whether (x, z) (from the target's column) is where a pane lies (its blocks are left alone, but where the bowl is).
    fn on_pane(&self, x: f64, z: f64) -> bool {
        self.panes.iter().any(|&(c, r)| (x - c[0]).hypot(z - c[1]) < r)
    }
    /// The pass's words.
    pub fn words(&self, laid: bool) -> Vec<u32> {
        let mut w = [0.0f64; SB_HDW];
        w[0] = self.site[0];
        w[1] = self.site[1];
        w[2] = self.dir[0];
        w[3] = self.dir[1];
        w[4] = self.side;
        w[5] = self.g0;
        w[6] = f64::from(SB_PRESS);
        w[7] = if laid { 1.0 } else { 0.0 };
        w.iter().map(|v| (*v as f32).to_bits()).collect()
    }
    /// (u along the back of its hand, v across to its thumb) of (x, z) from the target's column.
    fn local(&self, x: f64, z: f64) -> (f64, f64) {
        let (ox, oz) = (x - self.site[0], z - self.site[1]);
        (ox * self.dir[0] + oz * self.dir[1], self.side * (ox * self.dir[1] - oz * self.dir[0]))
    }
    /// (x, z) from the target's column of (u, v).
    fn world(&self, u: f64, v: f64) -> [f64; 2] {
        let (dx, dz) = (self.dir[0], self.dir[1]);
        [self.site[0] + u * dx + self.side * v * dz, self.site[1] + u * dz - self.side * v * dx]
    }
    /// (u, v)'s share of the bowl's radius there (its edge a little ragged).
    fn bowl_r(&self, u: f64, v: f64) -> f64 {
        let (fu, fv) = (u / SB_SC, v / SB_SC);
        let a = fv.atan2(fu);
        let rag = 1.0 + 0.18 * (qnoise(3.0 * a.cos() + 7.0, 3.0 * a.sin(), 1.0, self.seed ^ 0x51) - 0.5);
        (fu / SB_BOWL[0]).hypot(fv / SB_BOWL[1]) / rag
    }
    /// The crater at (u, v) (blocks): how far down the land is (0 outside it), how high earth is heaped on it, what part
    /// of it this is. `n`: noise from 0 to 1 there.
    fn dig(&self, u: f64, v: f64, n: f64) -> (f64, f64, Part) {
        crate::meter::spend(1_600);
        let r = self.bowl_r(u, v);
        let out = (r - SB_RIM) * 0.5 * (SB_BOWL[0] + SB_BOWL[1]) * SB_SC;
        if out > SB_BAND {
            return (0.0, 0.0, Part::Out);
        }
        let (mut down, mut part) = (0.0, Part::Band);
        if r < 1.0 {
            // (the bowl: the land caved in, falling away in broken steps)
            let rj = r + 0.025 * (n - 0.5);
            down = SB_BOWL_DEEP * (1.0 - r * r).powf(1.4);
            part = Part::Bowl;
            for &(at, drop) in &SB_STEPS {
                if rj < at {
                    down += drop;
                    if at - rj < 0.022 {
                        part = Part::Step;
                    }
                }
            }
        }
        // (the fist's print: its face pressed in, each finger's line a groove from its knuckle, the deepest, back to its second
        // joint, ridges left between them; its edge scalloped by the fingers)
        let (fu, fv) = (u / SB_SC, v / SB_SC);
        let mut fd = rbox(fu - HD_FACE.0[0], fv - HD_FACE.0[1], [HD_FACE.1[0] - 2.5, HD_FACE.1[1] - 3.0], HD_FACE.2);
        if fd < 8.0 {
            crate::meter::spend(1_200);
            let mut face = SB_DEEP - 4.4 - 1.2 * smooth(-2.0, -11.0, fu) - 0.13 * (-fv).max(0.0);
            for &(ku, kv, less, kr) in &HD_KNUCKLES {
                let (d, h) = seg([fu, fv], [ku, kv], [-9.5, kv * 0.92]);
                let w = kr * 1.05;
                fd = fd.min(d - w);
                if d < w {
                    face = face.max(SB_DEEP - less - 1.0 - 1.6 * h - 1.6 * (d / w).powi(2));
                }
                let dk = (fu - ku).hypot(fv - kv);
                if dk < kr {
                    face = face.max(SB_DEEP - less - 1.5 * (dk / kr).powi(2));
                }
                let dj = (fu + 9.5).hypot(fv - kv * 0.92);
                if dj < 3.0 {
                    face = face.max(SB_DEEP - less - 2.4 - 1.2 * (dj / 3.0).powi(2));
                }
            }
            // (its walls steep, the lip broken down)
            let w = smooth(3.5, -1.0, fd);
            let pressed = face * SB_SC * w;
            if pressed > down {
                down = pressed;
                if fd < 0.3 {
                    part = Part::Print;
                }
            }
        }
        // (the earth it pushed out, heaped round it)
        let mut up = 0.0;
        if r > 0.94 && r < SB_RIM {
            up = (4.5 + 4.5 * n) * (-((r - 1.07) / 0.11).powi(2)).exp() + 2.2 * (-(r - 1.0).max(0.0) / 0.22).exp() * (0.4 + n);
            if down < 0.5 {
                part = Part::Rim;
            }
        }
        (down, up, part)
    }
    /// The cracks running out from it: segments (x0, z0, x1, z1, half-width) from the target's column; from inside the
    /// bowl, out past its rim.
    fn make_cracks(&mut self) {
        let s = self.seed ^ 0x6a1d;
        let m = |k: u32, q: u32| mh(k, s, q);
        for k in 0..13u32 {
            let a = TAU * (f64::from(k) + 0.7 * m(k, 0x10)) / 13.0;
            let r0 = 0.55 + 0.3 * m(k, 0x15);
            let mut p = self.world(SB_BOWL[0] * r0 * a.cos() * SB_SC, SB_BOWL[1] * r0 * a.sin() * SB_SC);
            let mut b = (p[1] - self.site[1]).atan2(p[0] - self.site[0]);
            let mut left = 40.0 + 60.0 * m(k, 0x11).powi(2);
            let mut wd = 1.6 + 1.2 * m(k, 0x12);
            let mut j = 0;
            while left > 0.0 {
                let st = 4.0 + 5.0 * m(k * 7 + j, 0x13);
                b += 1.0 * (m(k * 7 + j, 0x14) - 0.5);
                let q = [p[0] + st * b.cos(), p[1] + st * b.sin()];
                self.cracks.push([p[0], p[1], q[0], q[1], wd]);
                p = q;
                left -= st;
                wd = (wd * 0.88).max(0.6);
                j += 1;
            }
        }
    }
    /// How far (x, z) is inside the nearest crack's half-width (under 1: in it).
    fn cracked(&self, x: f64, z: f64, near: &[usize]) -> f64 {
        let mut best = f64::MAX;
        for &i in near {
            let c = &self.cracks[i];
            let (d, _) = seg([x, z], [c[0], c[1]], [c[2], c[3]]);
            best = best.min(d / c[4]);
        }
        crate::meter::spend(40 * near.len() as u64);
        best
    }
    /// The chunks it changes (corners), its middle's first, then out from it.
    pub fn chunks(&self, bx: i32, bz: i32) -> Vec<(i32, i32)> {
        let mut set: crate::ground::FxMap<(i32, i32), ()> = Default::default();
        let reach = SB_RIM * SB_BOWL[1] * SB_SC * 1.12 + SB_BAND + 6.0;
        let mut u = -reach;
        while u <= reach {
            let mut v = -reach;
            while v <= reach {
                if self.dig(u, v, 0.5).2 != Part::Out || self.bowl_r(u, v) < SB_RIM {
                    let [x, z] = self.world(u, v);
                    set.insert(((x.floor() as i32 + bx) >> 4, (z.floor() as i32 + bz) >> 4), ());
                }
                v += 6.0;
            }
            u += 6.0;
        }
        for c in &self.cracks {
            set.insert(((c[2].floor() as i32 + bx) >> 4, (c[3].floor() as i32 + bz) >> 4), ());
        }
        let mut out: Vec<(i32, i32)> = set.keys().map(|&(a, b)| (a * 16, b * 16)).collect();
        let (fx, fz) = (self.site[0] + f64::from(bx), self.site[1] + f64::from(bz));
        out.sort_by_key(|c| ((f64::from(c.0) + 8.0 - fx).powi(2) + (f64::from(c.1) + 8.0 - fz).powi(2)) as i64);
        crate::meter::spend(200 * out.len() as u64 + 400_000);
        out
    }
    /// The columns asked for the land's height where it comes down.
    pub fn asked(&self, bx: i32, bz: i32) -> Vec<(i32, i32)> {
        let mut out = Vec::new();
        for k in -3..=3 {
            for i in -3..=3 {
                let [x, z] = self.world(f64::from(i) * 4.5 * SB_SC, f64::from(k) * 4.5 * SB_SC);
                out.push((x.floor() as i32 + bx, z.floor() as i32 + bz));
            }
        }
        out
    }
    /// The edits of the chunk with corner (x0, z0) (`read`: what stands on each of its columns, x then z; `lava`: where
    /// lava is in each, a bit a block up from a height), the target's column (bx, bz) and its ground's Y `gy`. The bowl
    /// is pressed down from the land where the fist came down at its middle, from the land as it lies towards its rim
    /// (so on a hill it follows the hill); water is dug like any block; lava the crater bares is sealed (magma); where a
    /// pane lies, only the bowl touches it.
    pub fn chunk(&self, x0: i32, z0: i32, bx: i32, bz: i32, gy: i32, read: Option<&[Option<Col>]>, lava: Option<&[(i32, u64)]>) -> Blocks {
        let mut b = Blocks::default();
        let s = self.seed;
        let plane = gy as f64 + self.g0;
        let (mx, mz) = (f64::from(x0 - bx) + 8.0, f64::from(z0 - bz) + 8.0);
        let near: Vec<usize> = (0..self.cracks.len())
            .filter(|&i| {
                let c = &self.cracks[i];
                ((c[0] + c[2]) * 0.5 - mx).abs() < 16.0 + (c[0] - c[2]).abs() && ((c[1] + c[3]) * 0.5 - mz).abs() < 16.0 + (c[1] - c[3]).abs()
            })
            .collect();
        let air = "minecraft:air";
        let mut gs = [None; 256];
        let mut band = [false; 256];
        for z in z0..z0 + 16 {
            for x in x0..x0 + 16 {
                let j = ((z - z0) * 16 + x - x0) as usize;
                let (wx, wz) = (f64::from(x - bx) + 0.5, f64::from(z - bz) + 0.5);
                let (u, v) = self.local(wx, wz);
                let n = qnoise(wx, wz, 5.0, s ^ 0x71);
                let n2 = qnoise(wx, wz, 2.2, s ^ 0x72);
                let (down, up, mut part) = self.dig(u, v, n);
                crate::meter::spend(1_500);
                if matches!(part, Part::Band | Part::Rim) && self.on_pane(wx, wz) {
                    part = Part::Out;
                }
                let col = read.and_then(|r| r[j].as_ref());
                if part == Part::Out {
                    gs[j] = col.map(|c| c.g);
                    continue;
                }
                let fd = rbox(u / SB_SC - HD_FACE.0[0], v / SB_SC - HD_FACE.0[1], HD_FACE.1, HD_FACE.2);
                let r = self.bowl_r(u, v);
                let Some(c) = col else {
                    // (no read: on the ground as it would be, from the surface)
                    let dig = down.round() as i32;
                    if dig > 0 {
                        b.put(x, z, -dig, -1, air, None, true);
                        b.put(x, z, -dig - 2, -dig - 1, floor_block(part, n, n2, fd, r), None, true);
                    }
                    continue;
                };
                // (the land's top, or the water's; what is solid under it)
                let surf = if c.fluid { c.top } else { c.g };
                let top = c.top.max(surf);
                let cr = self.cracked(wx, wz, &near);
                // (lava it bares sealed: any in the bowl or by its edge, from a little under its floor up)
                if let Some(&(lb, mask)) = lava.and_then(|l| l.get(j))
                    && mask != 0
                    && r < 1.15
                {
                    let from = (plane - SB_DEEP * SB_SC).floor() as i32 - 4;
                    for k in 0..64 {
                        let y = lb + k;
                        if mask >> k & 1 == 1 && y >= from {
                            b.run(x, z, y, y, "minecraft:magma_block");
                        }
                    }
                    crate::meter::spend(4_000);
                }
                if down > 0.5 {
                    // (caved in: from the land where the fist came down at the middle, from the land here towards the rim)
                    let reff = plane + (f64::from(surf) - plane) * smooth(0.3, 1.0, r);
                    let mut f = (reff - down).round() as i32;
                    if cr < 0.5 && part != Part::Print {
                        f -= 3;
                    }
                    if f < top {
                        b.run(x, z, f + 1, top, air);
                    }
                    // (its floor; where the land was already lower (the hole the opening's island left, on the
                    // target), filled up to it with the same)
                    b.run(x, z, (f - 1).min(c.g + 1), f, floor_block(part, n, n2, fd, r));
                    gs[j] = Some(f);
                    continue;
                }
                let g = surf;
                let h = up.round() as i32;
                let mut gt = g;
                if top > g {
                    b.run(x, z, g + 1, top, air);
                }
                if h > 0 && !c.fluid {
                    gt = g + h;
                    b.run(x, z, g + 1, gt - 1, if n2 < 0.5 { "minecraft:dirt" } else { "minecraft:coarse_dirt" });
                    b.run(x, z, gt, gt, if n > 0.62 && h < 3 { "minecraft:grass_block" } else { heap_block(n, n2) });
                }
                if cr < 1.0 && !c.fluid {
                    // (a crack: open down its middle, tuff either side)
                    if cr < 0.45 {
                        b.run(x, z, gt - 5, gt - 4, "minecraft:tuff");
                        b.run(x, z, gt - 3, gt, air);
                        gt -= 4;
                    } else {
                        b.run(x, z, gt - 2, gt, "minecraft:tuff");
                    }
                }
                gs[j] = Some(gt);
                band[j] = part == Part::Band && !c.fluid;
            }
        }
        // (the trees that stood in the band, laid flat pointing away from it, inside this chunk; their crowns at their ends)
        if let Some(read) = read {
            let inside = |lx: i32, lz: i32| lx >= x0 && lz >= z0 && lx < x0 + 16 && lz < z0 + 16;
            let at = |lx: i32, lz: i32| ((lz - z0) * 16 + lx - x0) as usize;
            for z in z0..z0 + 16 {
                for x in x0..x0 + 16 {
                    let j = at(x, z);
                    let (Some(c), Some(_)) = (read[j].as_ref(), gs[j]) else { continue };
                    if c.trunk < 3 || !band[j] {
                        continue;
                    }
                    let (ox, oz) = (f64::from(x - bx) - self.site[0], f64::from(z - bz) - self.site[1]);
                    let (sx, sz) = if ox.abs() >= oz.abs() { (if ox > 0.0 { 1 } else { -1 }, 0) } else { (0, if oz > 0.0 { 1 } else { -1 }) };
                    let full = i32::from(c.trunk.min(10));
                    let fits = |len: i32| (1..=len + 1).all(|k| inside(x + sx * k, z + sz * k) && band[at(x + sx * k, z + sz * k)]);
                    let Some(len) = (3..=full).rev().find(|&l| fits(l)) else { continue };
                    let log = if sx != 0 { LOG_X[c.wood as usize % 9] } else { LOG_Z[c.wood as usize % 9] };
                    let leaves = LEAVES[c.wood as usize % 9];
                    for k in 1..=len {
                        let (lx, lz) = (x + sx * k, z + sz * k);
                        if let Some(g) = gs[at(lx, lz)] {
                            b.run(lx, lz, g + 1, g + 1, log);
                        }
                    }
                    let (ex, ez) = (x + sx * (len + 1), z + sz * (len + 1));
                    for (dx, dz) in [(0, 0), (sz, sx), (-sz, -sx)] {
                        if inside(ex + dx, ez + dz)
                            && band[at(ex + dx, ez + dz)]
                            && let Some(g) = gs[at(ex + dx, ez + dz)]
                        {
                            b.run(ex + dx, ez + dz, g + 1, g + 1 + i32::from((dx, dz) == (0, 0)), leaves);
                        }
                    }
                    crate::meter::spend(3_000);
                }
            }
        }
        crate::meter::spend(30_000);
        b
    }
}
/// The crater's floor (its top two blocks): in the fist's print, what is behind the sky pressed into the land; the bowl's
/// floor crushed stone, darker towards the print, its outer steps tilted turf; the steps' edges bare stone. `fd`: how far
/// outside the fist's face (its bones' units); `r`: the share of the bowl's radius.
fn floor_block(part: Part, n: f64, n2: f64, fd: f64, r: f64) -> &'static str {
    match part {
        Part::Print => {
            if n2 > 0.9 {
                "minecraft:crying_obsidian"
            } else if n < 0.42 {
                "minecraft:obsidian"
            } else if n < 0.85 {
                "minecraft:blackstone"
            } else {
                "minecraft:basalt"
            }
        }
        Part::Step => {
            if n < 0.45 {
                "minecraft:stone"
            } else if n2 < 0.5 {
                "minecraft:tuff"
            } else {
                "minecraft:andesite"
            }
        }
        _ if fd < 5.0 || r < 0.42 => {
            if n2 > 0.7 {
                "minecraft:blackstone"
            } else if n < 0.5 {
                "minecraft:cobbled_deepslate"
            } else {
                "minecraft:tuff"
            }
        }
        _ if r > 0.78 && n2 > 0.35 => {
            if n > 0.55 {
                "minecraft:grass_block"
            } else {
                "minecraft:coarse_dirt"
            }
        }
        _ => {
            if n2 > 0.72 {
                "minecraft:gravel"
            } else if n < 0.35 {
                "minecraft:cobblestone"
            } else if n < 0.7 {
                "minecraft:coarse_dirt"
            } else {
                "minecraft:tuff"
            }
        }
    }
}

// ---- the arm: where it is, worked out here and handed to the pass a frame each 30th of a second ----------------------
// The hand and its arm always come and go through the hole (skybreak.rs's SB_OPEN: every cell within that of the middle
// goes as the fist hits). The arm is a chain hung from a shoulder far up in the dark, and it is the shoulder that is
// moved: it lets the arm down through the hole, leans it, draws it back and throws it, the elbow's bend and the wrist's
// each following in their own time, the fingers last (`hang` is the chain from the shoulder down, `shoulder_for` the
// shoulder that puts the wrist at a place: the key poses, and the fist while it lies in the land). Through the hole the
// arm runs through a port near its middle: the forearm through it while the elbow is still over the glass, the upper
// arm once it is under (`tests::the_arm_keeps_to_the_hole` checks every part of it against the glass still standing,
// the whole strike long). Nothing is held dead still (`drift`), nothing rings: what follows a blow is a critically
// damped settle, once. The pass (skybreak.wgsl's `hd_pose`) reads its poses at SB_HP and draws the hand's bones on them.
/// Its poses in the pass's table: two stretches (from, how many) a 30th of a second apart, SB_HP_W words each: the wrist,
/// the elbow, the shoulder, the way to its fingers, the way its back faces, each finger's curl, the thumb's, how spread,
/// how much of it there is, how far each finger's joints' curl leads its knuckle's.
pub(super) const SB_HP: usize = SB_HD + SB_HDW;
/// Where the sculpted hand's grids are in the pass's words (skybreak.wgsl's HB): well past the poses, which may grow.
pub(super) const SB_HB: usize = 65_536;
/// The sculpted hand and arm: a real sculpted arm cut at its joints into rigid pieces, each a small grid of distances in
/// its own bone's frame, which the pass reads where the bone is (skybreak.wgsl's `hd_hand_b`). Made offline by
/// `tools/bake_hand.py` (which also writes the pass's table of the grids: the two go together); four words of heading
/// (a mark, a version, the pieces, the words in all), then the grids, ten bits a sample.
static SB_HAND_BIN: &[u8] = include_bytes!("../../assets/sb_hand.bin");
/// The grids as the pass's words (from SB_HB).
pub(super) fn sb_hand_grids() -> Vec<u32> {
    let w: Vec<u32> = SB_HAND_BIN.chunks_exact(4).map(|c| u32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect();
    crate::meter::spend(12 * w.len() as u64);
    w
}
pub(super) const SB_HP_RATE: f64 = 30.0;
pub(super) const SB_HP_W: usize = 26;
pub(super) const SB_HP_WIN: [(f64, usize); 2] = [(6.3, 199), (33.8, 277)];
// (the poses end before the grids begin, and the grids fit in one render.set-data: 262,144 words)
const _: () = assert!(SB_HP + (SB_HP_WIN[0].1 + SB_HP_WIN[1].1) * SB_HP_W <= SB_HB && SB_HB + SB_HAND_BIN.len() / 4 <= 262_144);
/// The arm's bones (its bones' units; times SB_SC for blocks: skybreak.wgsl's HD_FORE, HD_UPPER, HD_REACH): the forearm,
/// the upper arm, from the wrist to the front of the closed fist's knuckles, from the wrist to the palm's middle.
pub(super) const HD_FORE: f64 = 96.0;
pub(super) const HD_UPPER: f64 = 138.0;
const HD_REACH: f64 = 36.0;
const HD_PALM: f64 = 24.0;
/// The fist's middle is this far in from the wrist's line, towards the palm (its bones' units).
const HD_FIST_MID: f64 = 6.0;
/// The finale's moments after the blow (SB_DOWN to SB_PRESS): the fist leaves the land; the arm is gone.
const SB_LIFT: f64 = 38.9;
const SB_GONE: f64 = 42.6;

type V3 = [f64; 3];
fn vadd(a: V3, b: V3) -> V3 {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}
fn vsub(a: V3, b: V3) -> V3 {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
fn vmul(a: V3, k: f64) -> V3 {
    [a[0] * k, a[1] * k, a[2] * k]
}
fn vdot(a: V3, b: V3) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn vcross(a: V3, b: V3) -> V3 {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}
fn vnorm(a: V3) -> V3 {
    vmul(a, 1.0 / vdot(a, a).sqrt().max(1e-9))
}
fn vmix(a: V3, b: V3, u: f64) -> V3 {
    vadd(a, vmul(vsub(b, a), u))
}
fn ease(u: f64) -> f64 {
    let x = u.clamp(0.0, 1.0);
    x * x * (3.0 - 2.0 * x)
}
const UP: V3 = [0.0, 1.0, 0.0];
/// A channel through knots (when, its value, how fast it is changing there): between two it goes as a quintic that
/// leaves and arrives without acceleration, so its speed and acceleration never step at a knot; before the first and
/// after the last it keeps their values.
fn chan(k: &[(f64, f64, f64)], t: f64) -> f64 {
    if t <= k[0].0 {
        return k[0].1;
    }
    for i in 1..k.len() {
        if t < k[i].0 {
            let (t0, p0, v0) = k[i - 1];
            let (t1, p1, v1) = k[i];
            let d = t1 - t0;
            let u = (t - t0) / d;
            let (u3, u4, u5) = (u * u * u, u * u * u * u, u * u * u * u * u);
            let h01 = 10.0 * u3 - 15.0 * u4 + 6.0 * u5;
            return p0 + (p1 - p0) * h01 + (u - 6.0 * u3 + 8.0 * u4 - 3.0 * u5) * d * v0 + (-4.0 * u3 + 7.0 * u4 - 3.0 * u5) * d * v1;
        }
    }
    k[k.len() - 1].1
}
/// 0 to 1 with no speed or acceleration at either end.
fn ease5(u: f64) -> f64 {
    let x = u.clamp(0.0, 1.0);
    x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
}
/// A slow wander in -1..1 that never repeats and is no wave: values drawn by a hash a unit apart, eased between, a
/// second such at more than twice the rate laid over them (a held arm is never still, and never rings).
fn drift(x: f64) -> f64 {
    fn h(i: f64) -> f64 {
        let mut n = (i as i64 as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        n ^= n >> 29;
        n = n.wrapping_mul(0xBF58_476D_1CE4_E5B9);
        n ^= n >> 32;
        (n & 0xFFFF) as f64 / 32767.5 - 1.0
    }
    fn n1(x: f64) -> f64 {
        let i = x.floor();
        h(i) + (h(i + 1.0) - h(i)) * ease5(x - i)
    }
    0.7 * n1(x) + 0.3 * n1(x * 2.17 + 31.4)
}
/// `v` turned by the least turn that takes the unit `a` to the unit `b`.
fn rot_to(a: V3, b: V3, v: V3) -> V3 {
    let k = vcross(a, b);
    let c = vdot(a, b);
    vadd(vadd(vmul(v, c), vcross(k, v)), vmul(k, vdot(k, v) / (1.0 + c).max(1e-6)))
}
/// `v` turned by `ang` about the unit `k`.
fn rot_about(k: V3, ang: f64, v: V3) -> V3 {
    let (s, c) = ang.sin_cos();
    vadd(vadd(vmul(v, c), vmul(vcross(k, v), s)), vmul(k, vdot(k, v) * (1.0 - c)))
}
/// The part of `v` square to the unit `n`, made a unit.
fn square_to(v: V3, n: V3) -> V3 {
    vnorm(vsub(v, vmul(n, vdot(v, n))))
}
/// A hand's frame (the way to its fingers, the way its back faces) turned from `(az, ay)`: rolled by `roll` about the
/// forearm `f` (its bones turning over each other), then bent at the wrist by `flex` towards its palm.
fn hand_frame(az: V3, ay: V3, f: V3, roll: f64, flex: f64) -> (V3, V3) {
    let (az, ay) = (rot_about(f, roll, az), rot_about(f, roll, ay));
    let (s, c) = flex.sin_cos();
    frame(vsub(vmul(az, c), vmul(ay, s)), vadd(vmul(ay, c), vmul(az, s)))
}
/// A finger's two curls, at its knuckle and at its joints, as (their mean, the joints' lead over the knuckle): what the
/// pass draws it from (skybreak.wgsl's `hd_set`).
fn curl(m: f64, p: f64) -> (f64, f64) {
    (0.5 * (m + p), p - m)
}

/// A vector's channel through knots (when, where, how fast), each part as `chan`.
fn chan3(k: &[(f64, V3, V3)], t: f64) -> V3 {
    let mut out = [0.0; 3];
    for (i, o) in out.iter_mut().enumerate() {
        let mut one = [(0.0, 0.0, 0.0); 8];
        for (a, b) in one.iter_mut().zip(k) {
            *a = (b.0, b.1[i], b.2[i]);
        }
        *o = chan(&one[..k.len().min(8)], t);
    }
    out
}
/// `x` where it is well over nothing, nothing where it is well under, and a smooth bend between (within `r` of nothing;
/// neither its slope nor its curve steps).
fn corner(x: f64, r: f64) -> f64 {
    if x <= -r {
        0.0
    } else if x >= r {
        x
    } else {
        let u = (x + r) / (2.0 * r);
        r * u * u * u * (2.0 - u)
    }
}
/// An arm hung from its shoulder `s` down through the hole at `p`, its elbow bent by `beta` towards `hint`: its elbow
/// and its wrist. Whichever of its bones is in the hole passes through `p`: the forearm while the elbow is still over
/// the glass, the upper arm once it is under.
fn hang(s: V3, p: V3, beta: f64, hint: V3, lu: f64, lf: f64) -> (V3, V3) {
    let n = vsub(p, s);
    let dd = vdot(n, n).sqrt().max(1e-6);
    let n = vmul(n, 1.0 / dd);
    let b = square_to(hint, n);
    let (sb, cb) = beta.sin_cos();
    // (how far down the forearm from the elbow the hole is: under nothing, the elbow is through)
    let x = -lu * cb + (dd * dd - lu * lu * sb * sb).max(0.0).sqrt();
    let g = (corner(x, 30.0) * sb / dd).clamp(-1.0, 1.0).asin();
    let u = vsub(vmul(n, g.cos()), vmul(b, g.sin()));
    let f = vadd(vmul(n, (beta - g).cos()), vmul(b, (beta - g).sin()));
    let el = vadd(s, vmul(u, lu));
    (el, vadd(el, vmul(f, lf)))
}
/// The shoulder that puts such an arm's wrist at `w` (its elbow under the glass, its upper arm through `p`).
fn shoulder_for(w: V3, p: V3, beta: f64, hint: V3, lu: f64, lf: f64) -> V3 {
    let pw = vsub(w, p);
    let r = vdot(pw, pw).sqrt().max(1e-6);
    let n = vmul(pw, 1.0 / r);
    let b = square_to(hint, n);
    let sb = beta.sin();
    let a = -lf * beta.cos() + (r * r - lf * lf * sb * sb).max(0.0).sqrt();
    let g = (lf * sb / r).clamp(-1.0, 1.0).asin();
    let u = vsub(vmul(n, g.cos()), vmul(b, g.sin()));
    vsub(p, vmul(u, lu - a))
}
/// An arm thrown down through the hole at `p`, its wrist `r` along the line `n` from it (under nothing: still over the
/// glass), its elbow bent by `beta` towards `hint`: its shoulder, its elbow and its wrist. The forearm comes down the
/// line; once the elbow is through, the upper arm is in the hole and the forearm swings on past the line (as `hang`
/// and `shoulder_for` have it), the one giving way to the other over 70 blocks either side.
fn thrown(p: V3, n: V3, r: f64, beta: f64, hint: V3, lu: f64, lf: f64) -> (V3, V3, V3) {
    let b = square_to(hint, n);
    let g = (lf * beta.sin() / (lf + corner(r - lf, 70.0))).clamp(-1.0, 1.0).asin();
    let f = vadd(vmul(n, (beta - g).cos()), vmul(b, (beta - g).sin()));
    let u = vsub(vmul(n, g.cos()), vmul(b, g.sin()));
    let w = vadd(p, vmul(n, r));
    let el = vsub(w, vmul(f, lf));
    (vsub(el, vmul(u, lu)), el, w)
}
/// Where the arm is at a moment (blocks, from the target's ground point).
#[derive(Clone, Copy, Debug)]
pub(super) struct ArmPose {
    pub w: V3,
    pub el: V3,
    pub sh: V3,
    /// the way to its fingers and the way its back faces
    pub az: V3,
    pub ay: V3,
    /// each finger's curl (the mean of its knuckle's and its joints'), and how far its joints lead its knuckle
    pub fl: [f64; 4],
    pub hk: [f64; 4],
    pub th: f64,
    pub spread: f64,
    pub k: f64,
}
impl ArmPose {
    /// Its palm's middle.
    pub fn palm(&self) -> V3 {
        vadd(self.w, vmul(self.az, HD_PALM * SB_SC))
    }
    /// A point in the hand's own frame (x across to the thumb, y its back, z to its fingers; its bones' units).
    pub fn at(&self, side: f64, l: V3) -> V3 {
        let ax = vcross(self.ay, self.az);
        let p = self.palm();
        vadd(p, vadd(vmul(ax, side * l[0] * SB_SC), vadd(vmul(self.ay, l[1] * SB_SC), vmul(self.az, l[2] * SB_SC))))
    }
}
/// A hand's frame from the way to its fingers and a hint of the way its back faces.
fn frame(az: V3, back: V3) -> (V3, V3) {
    let az = vnorm(az);
    let ay = vnorm(vadd(vsub(back, vmul(az, vdot(back, az))), [1e-6, 0.0, 0.0]));
    (az, ay)
}
/// The arm for a strike: which way the player was (from the target), where the fist comes down, its back's way, which
/// hand, the land's height there.
pub(super) struct Arm {
    fw: V3,
    site: [f64; 2],
    dir: [f64; 2],
    side: f64,
    g0: f64,
    /// Where in its wandering it starts (`phase`).
    ph: f64,
    keys: SlamKeys,
}
/// What of the slam is the same the whole stretch long, worked out once (`Arm::slam_keys`): its shoulder (as
/// `Arm::slam_polar` has it) leaves the land through (when, where, how fast); its elbow's bend as it leaves, and how
/// fast that is changing.
#[derive(Clone, Copy, Default)]
struct SlamKeys {
    lift: [(f64, V3, V3); 6],
    b_r: f64,
    vb_r: f64,
}
/// The slam's elbow's bend: cocked over the glass before the blow, and as it hits.
const SLAM_BEND: (f64, f64) = (0.56, 0.29);
/// How far over the hole the slam's wrist is before the blow, back up the line it comes down (blocks: its knuckles
/// some 90 over the glass), and how many times its mean speed the fist lands at (from rest, faster all the way: 2.5
/// is the most that never slows).
const SLAM_TOP: f64 = 200.0;
const SLAM_WHIP: f64 = 2.4;
impl Arm {
    pub fn new(print: &Print, me: [f64; 3]) -> Arm {
        let l = me[0].hypot(me[2]);
        let fw = if l > 1.0 { [me[0] / l, 0.0, me[2] / l] } else { [0.0, 0.0, 1.0] };
        let ph = 40.0 * mh(5, print.seed, 0x1a4);
        let mut arm = Arm { fw, site: print.site, dir: print.dir, side: print.side, g0: print.g0, ph, keys: SlamKeys::default() };
        arm.keys = arm.slam_keys();
        arm
    }
    /// The slam's lines: the way the fist faces along the land, and square to it.
    fn slam_dirs(&self) -> (V3, V3) {
        let d = [self.dir[0], 0.0, self.dir[1]];
        (d, [-d[2], 0.0, d[0]])
    }
    /// Where in the hole the slam's arm passes: its middle, never quite still.
    fn slam_port(&self, t: f64) -> V3 {
        vadd([0.0, SB_H, 0.0], vmul(self.slam_dirs().0, 2.5 * drift(t * 0.4 + self.phase() + 40.0)))
    }
    /// The wrist's heights with the fist's face as it hits the land (pressed in a little over half of SB_DEEP) and
    /// pressed all the way in.
    fn slam_heights(&self) -> (f64, f64) {
        let top = self.g0 + HD_REACH * SB_SC;
        (top - SB_DEEP * SB_SC * 0.55, top - SB_DEEP * SB_SC)
    }
    /// The wrist a share `k` of the way out to its line over the face's middle (the site), at a height.
    fn slam_at(&self, k: f64, y: f64) -> V3 {
        let d = self.slam_dirs().0;
        let wxz = vadd([self.site[0], 0.0, self.site[1]], vmul(d, HD_FIST_MID * SB_SC));
        [wxz[0] * k, y, wxz[2] * k]
    }
    /// The shoulder that puts the slam's wrist at `w` (the elbow bends back towards the target).
    fn slam_ik(&self, w: V3, t: f64, beta: f64) -> V3 {
        shoulder_for(w, self.slam_port(t), beta, vmul(self.slam_dirs().0, -1.0), HD_UPPER * SB_SC, HD_FORE * SB_SC)
    }
    /// A shoulder as the arm has it: how much of the arm is still over the hole, how far the arm leans out from it
    /// through the hole, how far off to a side it is. The arm is let down and drawn up through the hole by the first
    /// and swung by the second, each in its own time.
    fn slam_polar(&self, sh: V3, t: f64) -> V3 {
        let (d, s) = self.slam_dirs();
        let r = vsub(sh, self.slam_port(t));
        let (x, y) = (vdot(r, d), r[1]);
        [x.hypot(y), (-x).atan2(y), vdot(r, s)]
    }
    /// The slam's fist in the land (its shoulder, its elbow's bend): the fist where the land lets it, most of the way
    /// in at once and the rest as its weight bears down; the elbow buckling as the arm above carries on, then coming
    /// back to rest a little more bent than it hit; then the shoulder drawing the arm straight, the fist still in.
    fn planted(&self, t: f64) -> (V3, f64) {
        let a = t - f64::from(SB_PRESS);
        let (w_hit, w_in) = self.slam_heights();
        let b_hit = SLAM_BEND.1;
        let y = w_hit + (w_in - w_hit) * (0.85 * (1.0 - (-a / 0.07).exp()) + 0.15 * ease5(a / 1.1));
        let x = a / 0.2;
        let beta = b_hit + 0.18 * (1.0 - (-a / 0.05).exp()) - 0.12 * (1.0 - (1.0 + x) * (-x).exp())
            + 0.012 * ease5((a - 0.3) / 0.5) * drift(t * 0.8 + self.phase() + 40.0)
            - (b_hit + 0.06 - 0.11) * ease5((a - 0.9) / 0.9);
        (self.slam_ik(self.slam_at(1.0, y), t, beta), beta)
    }
    fn slam_keys(&self) -> SlamKeys {
        crate::meter::spend(12_000);
        let (_, w_in) = self.slam_heights();
        let pose = |k: f64, y: f64, t: f64, beta: f64| self.slam_polar(self.slam_ik(self.slam_at(k, y), t, beta), t);
        // (from the pose and the speed it leaves the land with: straight up first, then swung in under the hole, then
        // up through it and away; through each pose between at the speed that joins its neighbours)
        let h = 1.0 / 240.0;
        let z = [0.0; 3];
        let ((s0, b0), (s1, b1), (s_r, b_r)) = (self.planted(SB_LIFT - h), self.planted(SB_LIFT + h), self.planted(SB_LIFT));
        let k = [
            (SB_LIFT, self.slam_polar(s_r, SB_LIFT), vmul(vsub(self.slam_polar(s1, SB_LIFT + h), self.slam_polar(s0, SB_LIFT - h)), 0.5 / h)),
            (SB_LIFT + 0.45, pose(0.98, w_in + 34.0, SB_LIFT + 0.45, 0.12), z),
            (SB_LIFT + 0.95, pose(0.66, self.g0 + 215.0, SB_LIFT + 0.95, 0.2), z),
            (SB_LIFT + 1.65, [700.0, 0.006, 0.0], z),
            (SB_LIFT + 2.6, [1080.0, 0.0, 0.0], z),
            (SB_LIFT + 3.8, [1300.0, 0.0, 0.0], z),
        ];
        let mut lift = k;
        for i in 1..k.len() - 1 {
            lift[i].2 = vmul(vsub(k[i + 1].1, k[i - 1].1), 1.0 / (k[i + 1].0 - k[i - 1].0));
        }
        SlamKeys {
            lift,
            b_r,
            vb_r: (b1 - b0) * 0.5 / h,
        }
    }
    pub fn side(&self) -> f64 {
        self.side
    }
    /// Where in its wandering this strike's arm is (no two strikes' the same).
    fn phase(&self) -> f64 {
        self.ph
    }
    pub fn pose(&self, t: f64) -> ArmPose {
        crate::meter::spend(if t < 25.0 { 6_000 } else { 16_000 });
        if t < 25.0 { self.punch(t) } else { self.slam(t) }
    }
    /// The punch, as a man throws one down through a pane. First the press, behind the unbroken sky (none of it drawn
    /// but its shadow on the glass, the pass's `hd_shade`): an open hand comes down out of the dark along its forearm's
    /// line and is laid flat on the glass over the target, its fingers towards the player, and leans on it; the fingers
    /// curl under as its heel lifts and it rolls up onto its knuckles, a fist stood on the glass. That fist
    /// is drawn back, the elbow out and bent, the fist turned half over; then thrown, the shoulder first,
    /// the elbow straightening and the forearm turning the fist over as it comes, fastest as its knuckles meet the glass
    /// at SB_CRACK (there, its middle on the hole's middle, its back to the player, as ever). The glass checks it at
    /// once and it carries on through, slowing to nothing over a third of a second as its own weight bends the wrist
    /// over and the arm swings in line; it never stops dead, but drifts, already beginning to give; then it is drawn out
    /// by the elbow, slowly first, the elbow going up and out and bending, the hand trailing after its wrist, the
    /// fingers loosening only once they are past the glass. The forearm keeps to one place in the hole as it turns
    /// (`port`), so the fist's path below it is a curve.
    fn punch(&self, t: f64) -> ArmPose {
        let a = t - f64::from(SB_CRACK);
        let sc = SB_SC;
        let (lf, lu) = (HD_FORE * sc, HD_UPPER * sc);
        let fw = self.fw;
        // (the pass draws the punch with a right hand; `out` is to its elbow's side, away from its thumb)
        let out = [-fw[2], 0.0, fw[0]];
        let ph = self.phase();
        let live = ease5((a - 0.1) / 0.5);
        // (how far its knuckles are below the glass: drawn back; thrown, faster and faster to the glass; checked there,
        // and on to rest as a weight on a damper does, without coming back; less what it has been lifted, which begins
        // before it has quite come to rest)
        const V_HIT: f64 = 1150.0;
        // (the press: from where the table begins; laid on the glass; leant on; up on its knuckles)
        const PR_FROM: f64 = -2.7;
        const PR_TOUCH: f64 = -1.85;
        const PR_LEAN: f64 = -1.5;
        const PR_FIST: f64 = -1.08;
        // (its wrist bent back so far with the hand flat on the glass, the forearm leaning as it does then)
        const PR_FLAT: f64 = -1.0;
        let reach = HD_REACH * sc;
        let (far, tau) = (214.0, 0.16);
        let mut dk = if a < 0.0 {
            // (the press: its wrist 24 over the glass with the hand laid flat, a little less as it leans, a fist's reach
            // over it once it is up on its knuckles)
            chan(&[(PR_FROM, reach - 430.0, 480.0), (PR_TOUCH, reach - 24.0, 0.0), (PR_LEAN, reach - 21.0, 0.0), (PR_FIST, 3.0, 0.0), (-0.42, -286.0, 0.0), (0.0, 0.0, V_HIT)], a)
        } else {
            far - (far + (far / tau - V_HIT) * a) * (-a / tau).exp()
        };
        dk -= chan(&[(0.4, 0.0, 0.0), (1.3, 26.0, 55.0), (2.35, 222.0, 330.0), (3.75, 800.0, 420.0)], a);
        dk += 2.5 * live * drift(a * 0.9 + ph);
        // (the forearm's lean from straight down: its elbow out to the side and back from the player as it is drawn
        // back, swinging in line as it straightens through the glass and a little past, then led up and out again)
        let lean_out = chan(&[(PR_FROM, 0.14, 0.0), (PR_TOUCH, 0.1, 0.0), (PR_FIST, 0.09, 0.0), (-0.3, 0.11, 0.0), (0.0, 0.06, -0.35), (0.45, -0.015, 0.0), (1.4, 0.01, 0.05), (2.5, 0.13, 0.12), (3.8, 0.2, 0.0)], a)
            + 0.012 * live * drift(a * 0.7 + ph + 3.1);
        let lean_back = chan(&[(PR_FROM, 0.6, 0.0), (PR_TOUCH, 0.7, 0.0), (PR_LEAN, 0.74, 0.0), (PR_FIST, 0.12, 0.0), (-0.3, 0.085, 0.0), (0.0, 0.045, -0.3), (0.5, -0.03, 0.0), (1.4, -0.01, 0.04), (2.6, 0.1, 0.1), (3.8, 0.16, 0.0)], a)
            + 0.01 * live * drift(a * 0.6 + ph + 7.7);
        let fore = |lo: f64, lb: f64| vnorm(vadd([0.0, -1.0, 0.0], vsub(vmul(fw, lb), vmul(out, lo))));
        let (f0, f) = (fore(0.06, 0.045), fore(lean_out, lean_back));
        // (where the forearm's line crosses the glass: one place, which the arm slides through and turns about; it eases
        // in towards the hole's middle as the thick of the forearm comes into it, and over to make room for the trailing
        // hand as that comes back through; and it wanders a little)
        let slide = chan(&[(0.0, 0.0, 0.0), (0.5, -9.0, 0.0), (1.4, -7.0, 6.0), (2.3, 14.0, 14.0), (3.3, 22.0, 0.0)], a);
        // (pressing, it is back from there: its knuckles lie where the fist will stand on them)
        let back = chan(&[(PR_FROM, 100.0, 0.0), (PR_TOUCH, 78.0, 0.0), (PR_LEAN, 76.0, 0.0), (PR_FIST, 0.0, 0.0)], a);
        let port = vadd(
            vadd(vmul(fw, HD_FIST_MID * sc + slide - back), vmul([f0[0], 0.0, f0[2]], reach / -f0[1])),
            vadd(vmul(fw, 2.5 * live * drift(a * 0.5 + ph + 11.0)), vmul(out, 3.0 * live * drift(a * 0.45 + ph + 19.0))),
        );
        let below = dk - reach;
        let w = vadd([port[0], SB_H, port[2]], vmul(f, below / -f[1]));
        let el = vsub(w, vmul(f, lf));
        // (the elbow: bent as it is drawn back, straightening into the blow and still straightening as it lands, bending
        // again as it leads the arm back up; the shoulder beyond the target and in towards the body)
        let beta = chan(&[(PR_FROM, 1.1, 0.0), (PR_TOUCH, 1.3, 0.0), (PR_LEAN, 1.4, 0.0), (PR_FIST, 1.62, 0.0), (-0.4, 1.85, 0.0), (0.0, 0.8, -2.6), (0.42, 0.3, 0.0), (1.3, 0.36, 0.12), (2.6, 0.85, 0.4), (3.8, 1.1, 0.0)], a);
        let bend = square_to(vadd(vmul(fw, 0.9), vmul(out, -0.4)), f);
        let sh = vsub(el, vmul(vadd(vmul(f, beta.cos()), vmul(bend, beta.sin())), lu));
        // (the hand: carried by the forearm, less so as it trails on the way back; turned half over as it is drawn back
        // and turning knuckles-level into the blow, a little past, and back; the wrist bent back, then thrown level,
        // bent over once by the hand's own weight as the arm is checked, and bent again as the hand trails)
        let carry = 1.0 - 0.45 * ease5((a - 1.3) / 1.4);
        let fh = vnorm(vmix(f0, f, carry));
        let roll = chan(&[(PR_FIST - 0.1, 0.0, 0.0), (-0.34, 0.55, 0.0), (0.0, 0.0, -2.0), (0.32, -0.28, 0.0), (1.2, -0.12, 0.08), (2.4, 0.1, 0.25), (3.8, 0.4, 0.0)], a)
            + 0.03 * live * drift(a * 0.55 + ph + 23.0);
        let flex = chan(&[(PR_FROM, -0.74, 0.0), (PR_TOUCH + 0.08, PR_FLAT, 0.0), (PR_LEAN, PR_FLAT - 0.015, 0.0), (PR_FIST, -0.12, 0.0), (-0.3, -0.16, 0.0), (0.0, 0.0, 0.9), (0.24, 0.13, 0.0), (0.8, 0.04, -0.03), (1.5, 0.06, 0.08), (2.35, 0.2, 0.2), (3.1, 0.5, 0.2), (3.8, 0.6, 0.0)], a)
            + 0.02 * live * drift(a * 0.65 + ph + 29.0);
        let (az, ay) = hand_frame(rot_to(f0, fh, [0.0, -1.0, 0.0]), rot_to(f0, fh, fw), f, roll, flex);
        // (the fist: made on the glass from the open hand, the fingers straightening and spreading as they are laid on it,
        // then curling under, the index first, their joints before their knuckles, the thumb closing over them last;
        // clenched harder as it hits, slackening as it is held; opened only past the glass, the index first, each
        // finger's knuckle before its joints, the thumb after them)
        let sq = 0.05 * chan(&[(-0.1, 0.0, 0.0), (0.22, 1.0, 0.0), (1.3, 0.5, -0.4), (2.3, 0.0, 0.0)], a);
        let open = [0.32, 0.42, 0.5, 0.62];
        let (mut fl, mut hk) = ([0.0; 4], [0.0; 4]);
        for i in 0..4 {
            let shut = 1.0 + sq * (0.75 + 0.25 * i as f64);
            let t0 = 2.45 + [0.0, 0.09, 0.19, 0.31][i];
            let laid = [0.22, 0.24, 0.27, 0.32][i] + ([0.07, 0.08, 0.09, 0.11][i] - [0.22, 0.24, 0.27, 0.32][i]) * ease5((a - PR_TOUCH + 0.4) / 0.45);
            let tc = PR_LEAN + 0.03 * i as f64;
            let m = laid + (shut - laid) * ease5((a - tc) / 0.42) + (open[i] - shut) * ease5((a - t0) / 0.8);
            let p = laid + (shut - laid) * ease5((a - tc + 0.08) / 0.42) + (open[i] - shut) * ease5((a - t0 - 0.2) / 0.85);
            (fl[i], hk[i]) = curl(m, p);
        }
        let th = (0.12 * (1.0 - ease5((a - PR_TOUCH + 0.35) / 0.4)) + ease5((a - PR_LEAN - 0.1) / 0.45)).min(1.0) * (1.0 - 0.6 * ease5((a - 2.8) / 0.9));
        let spread = (0.25 + 0.4 * ease5((a - PR_TOUCH + 0.3) / 0.4)) * (1.0 - ease5((a - PR_LEAN) / 0.3));
        let k = ease((a + 0.6) / 0.3) * (1.0 - ease((a - 2.9) / 0.7));
        ArmPose { w, el, sh, az, ay, fl, hk, th, spread, k }
    }
    /// The slam: one blow, straight down. The fist is made over the glass, in the dark, the elbow bent and the wrist
    /// cocked back; from SB_DOWN it is thrown down through the hole and on to the land along one line (`thrown`: the
    /// line from the hole to where it lands), from rest and faster all the way, never held and never drawn back, the
    /// elbow straightening into it, the fist tightening and the wrist thrown level last, at its fastest as it lands
    /// at SB_PRESS. There the fist stops dead and the land gives under it; from here the arm is hung from a shoulder
    /// far up in the dark (never seen) and always through the hole (`hang`): the arm above carries on, the elbow
    /// buckling once and coming back as its weight
    /// rests; then the shoulder takes it up, the arm pulled straight before the fist leaves the land (SB_LIFT), the
    /// fist hanging from the wrist and slackening as it is swung in under the hole and drawn up through it, opening
    /// only once it is through.
    fn slam(&self, t: f64) -> ArmPose {
        let sc = SB_SC;
        let (lf, lu) = (HD_FORE * sc, HD_UPPER * sc);
        let d = [self.dir[0], 0.0, self.dir[1]];
        let s = [-d[2], 0.0, d[0]];
        let ph = self.phase() + 40.0;
        let (down, hit) = (f64::from(SB_DOWN), f64::from(SB_PRESS));
        // (where in the hole the arm passes; the elbow bends back towards the target)
        let port = |t: f64| self.slam_port(t);
        let hint0 = vmul(d, -1.0);
        let (b_up, b_hit) = SLAM_BEND;
        let key = &self.keys;
        let unpolar = |q: V3, t: f64| vadd(port(t), vadd(vadd(vmul(d, -q[0] * q[1].sin()), vmul(UP, q[0] * q[1].cos())), vmul(s, q[2])));
        // (the blow: its wrist down the line from the hole to where it lands, from rest SLAM_TOP back up it, its speed
        // as it lands SLAM_WHIP times its mean; the elbow straightening with it)
        let blow = |t: f64| -> (V3, V3, V3) {
            let line = vsub(self.slam_at(1.0, self.slam_heights().0), port(hit));
            let far = vdot(line, line).sqrt();
            let v = SLAM_WHIP / (hit - down);
            let r = chan(&[(down, -SLAM_TOP, 0.0), (hit, far, v * (far + SLAM_TOP))], t);
            let beta = chan(&[(down, b_up, 0.0), (hit, b_hit, v * (b_hit - b_up))], t);
            thrown(port(t), vmul(line, 1.0 / far), r, beta, hint0, lu, lf)
        };
        // (free of the land again: how far it is let down, its lean, its elbow's bend)
        let free = |t: f64| -> (V3, f64) {
            let beta = chan(&[(SB_LIFT, key.b_r, key.vb_r), (SB_LIFT + 0.45, 0.12, 0.0), (SB_LIFT + 0.95, 0.2, 0.0), (SB_LIFT + 1.65, 0.12, -0.05), (SB_LIFT + 2.6, 0.1, 0.0)], t);
            (unpolar(chan3(&key.lift, t), t), beta)
        };
        let planted = |t: f64| self.planted(t);
        // (a held arm is never still: once it is lifted its shoulder, its elbow and its place in the hole wander)
        let live_at = |t: f64| ease5((t - SB_LIFT - 0.1) / 0.9);
        let arm_at = |t: f64| -> (V3, V3, V3) {
            if t <= hit {
                return blow(t);
            }
            let live = live_at(t);
            let (mut sh, mut beta) = if t >= SB_LIFT { free(t) } else { planted(t) };
            sh = vadd(sh, vmul(d, 3.0 * live * drift(t * 0.5 + ph + 3.0)));
            sh = vadd(sh, vmul(UP, 3.0 * live * drift(t * 0.43 + ph + 7.0)));
            sh = vadd(sh, vmul(s, 4.0 * live * drift(t * 0.37 + ph + 11.0)));
            beta += 0.012 * live * drift(t * 0.6 + ph + 17.0);
            let hint = vnorm(vadd(hint0, vmul(s, 0.14 * live * drift(t * 0.33 + ph + 23.0))));
            let p = vadd(port(t), vmul(s, 2.0 * live * drift(t * 0.29 + ph + 29.0)));
            let (el, w) = hang(sh, p, beta, hint, lu, lf);
            (sh, el, w)
        };
        let (sh, el, w) = arm_at(t);
        let live = live_at(t);
        // (the hand comes after the forearm: loose, it points the way the forearm did a moment ago)
        let (_, el_l, w_l) = arm_at(t - 0.12);
        let trail = vnorm(vsub(w_l, el_l));
        // (a fist: its face level to the land as it lands whatever the arm does; cocked back at the wrist as it comes,
        // thrown level over the last of the blow)
        let c = chan(&[(hit - 0.45, 0.34, 0.0), (hit, 0.0, -1.8)], t);
        let az_t = vadd(vmul(UP, -c.cos()), vmul(d, c.sin()));
        let back_t = vadd(vmul(d, c.cos()), vmul(UP, c.sin()));
        // (lifted: hanging from the wrist by its own weight)
        let az_h = vnorm(vmix(trail, vmul(UP, -1.0), 0.55));
        let w_h = ease5((t - SB_LIFT - 0.05) / 1.1);
        let az = vmix(az_t, az_h, w_h);
        let back = vadd(vmix(back_t, d, w_h), vmul(s, 0.035 * live * drift(t * 0.7 + ph + 37.0)));
        let (az, ay) = frame(az, back);
        // (the fingers: shut from the first, tightening into the blow; slackening once lifted, the knuckles first;
        // opening once through the hole)
        let t_open = SB_LIFT + 1.95;
        let (mut fl, mut hk) = ([0.0; 4], [0.0; 4]);
        for i in 0..4 {
            let fi = i as f64;
            let tight = 1.0 + 0.04 * ease5((t - hit + 0.6) / 0.45);
            let slack = ease5((t - SB_LIFT - 0.2 - 0.07 * fi) / 0.9);
            let mut m = tight - [0.2, 0.17, 0.14, 0.12][i] * slack;
            let mut p = tight - 0.06 * slack;
            let off = [0.0, 0.09, 0.19, 0.31][i];
            m += ([0.2, 0.26, 0.32, 0.4][i] - m) * ease5((t - t_open - off) / 0.8);
            p += ([0.4, 0.46, 0.52, 0.6][i] - p) * ease5((t - t_open - off - 0.2) / 0.85);
            (fl[i], hk[i]) = curl(m, p);
        }
        // (the thumb: across the fingers, let go after them)
        let th = 1.0 - 0.7 * ease5((t - t_open - 0.25) / 0.9);
        let spread = 0.2 * ease5((t - t_open - 0.3) / 0.9);
        // (it comes to be over the glass, in the dark, before it moves much)
        let k = ease((t - down) / 0.4) * (1.0 - ease((t - (SB_GONE - 1.4)) / 1.4));
        ArmPose { w, el, sh, az, ay, fl, hk, th, spread, k }
    }
    /// The pass's poses (SB_HP on): the punch's stretch, or the slam's.
    pub fn table(&self, which: usize) -> Vec<u32> {
        let (t0, n) = SB_HP_WIN[which];
        let mut out = Vec::with_capacity(n * SB_HP_W);
        for i in 0..n {
            let p = self.pose(t0 + i as f64 / SB_HP_RATE);
            let mut w = [0.0f64; SB_HP_W];
            w[0..3].copy_from_slice(&p.w);
            w[3..6].copy_from_slice(&p.el);
            w[6..9].copy_from_slice(&p.sh);
            w[9..12].copy_from_slice(&p.az);
            w[12..15].copy_from_slice(&p.ay);
            w[15..19].copy_from_slice(&p.fl);
            w[19] = p.th;
            w[20] = p.spread;
            w[21] = p.k;
            w[22..26].copy_from_slice(&p.hk);
            out.extend(w.iter().map(|v| (*v as f32).to_bits()));
        }
        out
    }
    /// Where its stretch of the table starts.
    pub fn table_index(which: usize) -> usize {
        SB_HP + if which == 0 { 0 } else { SB_HP_WIN[0].1 * SB_HP_W }
    }
}

// ---- the hand as the strike goes on ----------------------------------------------------------------------------------
/// Chunks of it asked of the world together.
struct Lot {
    tag: u32,
    asked: f32,
    chunks: Vec<(i32, i32)>,
    next: usize,
    read: Option<Rc<crate::columns::Answer>>,
    kinds: Vec<(Kind, u8)>,
    /// Which of the read's kinds of block are lava.
    lava: Vec<bool>,
    answered: bool,
}
pub(super) struct Hand {
    pub print: Print,
    /// Where the player was as it fired (from the target's ground).
    me: [f64; 3],
    terrain: bool,
    todo: Vec<(i32, i32)>,
    next: usize,
    lots: std::collections::VecDeque<Lot>,
    /// Made, waiting for the slam (each with its distance from where the fist comes down).
    made: Vec<(f64, Blocks)>,
    sent: u32,
    lost: u32,
    pub done: bool,
}
pub(super) type SharedHand = Rc<RefCell<Hand>>;
impl Hand {
    pub fn new(print: Print, terrain: bool, me: [f64; 3]) -> Hand {
        Hand { print, me, terrain, todo: Vec::new(), next: 0, lots: Default::default(), made: Vec::new(), sent: 0, lost: 0, done: false }
    }
}

/// The hand's part of the plan: its words; the land where it comes down asked; its crater's chunks read as it comes down,
/// made into blocks and let in from the slam; the mobs under it killed; the jolts of the punch, the eye's flare and the
/// slam.
pub(super) fn sb_hand_plan(p: &mut Plan, h: SharedHand, me: [f64; 3]) {
    let (cx, cz) = (f64::from(p.bx) + 0.5, f64::from(p.bz) + 0.5);
    let gy = f64::from(p.by) + 1.0;
    let (site, terrain) = {
        let hb = h.borrow();
        (hb.print.site, hb.terrain)
    };
    let words = h.borrow().print.words(terrain);
    p.later(0.05, move |q| q.ev.push((0.05, Act::Words { index: SB_HD as u32, words })));
    // (the sculpted hand's grids, once: with the strike's other words they are sent the handful of times those change)
    p.later(0.07, move |q| q.ev.push((0.07, Act::Words { index: SB_HB as u32, words: sb_hand_grids() })));
    // (the arm's poses: the punch's now; the slam's once the land's height where it comes down is known)
    {
        let h2 = h.clone();
        p.later(0.06, move |q| {
            let words = Arm::new(&h2.borrow().print, me).table(0);
            q.ev.push((0.06, Act::Words { index: Arm::table_index(0) as u32, words }));
        });
    }
    // (the land's height where it comes down, for where the pass drives the fist in)
    {
        let tag = crate::ground::new_tag();
        let cols = h.borrow().print.asked(p.bx, p.bz);
        p.later(0.12, move |q| q.ev.push((0.12, Act::Survey { tag, columns: cols })));
        let h2 = h.clone();
        fn ground_step(q: &mut Plan, h: SharedHand, tag: u32, at: f32) {
            let gy = q.by + 1;
            if crate::ground::ready(tag) || at > SB_PRESS - 4.5 {
                let mut hs: Vec<i32> = {
                    let hb = h.borrow();
                    hb.print.asked(q.bx, q.bz).iter().filter_map(|&(x, z)| crate::ground::at(x, z).map(|g| g + crate::ground::water(x, z).unwrap_or(0) - gy)).collect()
                };
                crate::meter::spend(200 * hs.len() as u64);
                hs.sort_unstable();
                let g0 = hs.get(hs.len() / 2).copied().unwrap_or(0);
                h.borrow_mut().print.g0 = f64::from(g0);
                q.ev.push((at, Act::Data { index: (SB_HD + 5) as u32, value: g0 as f32 }));
                let me = h.borrow().me;
                let words = Arm::new(&h.borrow().print, me).table(1);
                q.ev.push((at, Act::Words { index: Arm::table_index(1) as u32, words }));
            } else {
                let t = at + 0.25;
                q.later(t, move |q| ground_step(q, h, tag, t));
            }
        }
        p.later(0.5, move |q| ground_step(q, h2, tag, 0.5));
    }
    // (the jolts: the punch, the eye's flare, the slam reaching them through the ground)
    p.shake(SB_CRACK + 0.02, 0.62, 0.3);
    p.shake(SB_FLARE + 0.03, 0.34, 0.9);
    let mw = [me[0] + cx, me[1] + gy, me[2] + cz];
    let at = [cx + site[0], gy, cz + site[1]];
    let dist = (mw[0] - at[0]).hypot(mw[2] - at[2]);
    let late = (dist / 1715.0) as f32;
    let fo = (2.2 / (1.0 + dist / 300.0)).clamp(0.35, 1.0) as f32;
    // (a thump through the ground first and the rumble it starts; then the shockwave reaching them through the air,
    // with the boom (skybreak.wgsl's hd_shock: its front 30 out at once, then 343 blocks a second; its muck on the lens,
    // hd_lens, lands from then): the Payload's jolt, a hard hit, sharp aftershocks every other tick for half a second,
    // a shudder of small quick jolts fading over two more, a long rumble under it, a few faint ones after; then the
    // dust wall's buffet as it rolls over them: skybreak.wgsl's hd_dust_k has its front, 70 + 450 (1 - e^(-a / 2.6)))
    let t0 = SB_PRESS + late;
    let t1 = SB_PRESS + ((dist - 30.0).max(0.0) / 343.0) as f32;
    p.shake(t0, 0.55 * fo, 0.3);
    p.shake(t0 + 0.15, 0.5 * fo, 3.2);
    super::payload::pl_jolt(p, t1, fo);
    for (dt, s, len) in [(2.7, 0.1, 0.5), (3.5, 0.07, 0.45), (4.6, 0.08, 0.55), (5.5, 0.05, 0.4)] {
        p.shake(t1 + dt, s * fo, len);
    }
    if dist < 500.0 {
        let a = (-2.6 * (1.0 - (dist - 70.0).max(0.0) / 450.0).ln()) as f32;
        p.shake(SB_PRESS + a, 0.5 * fo, 1.6);
    }
    let (x, y, z) = (at[0], at[1], at[2]);
    p.at(SB_PRESS + 0.05, format!("particle minecraft:explosion_emitter {x:.1} {:.1} {z:.1} 30 4 30 0 14 force", y + 3.0));
    p.at(SB_PRESS + 0.1, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {x:.1} {:.1} {z:.1} 45 8 45 1.0 700 force"#, y + 4.0));
    p.at(SB_PRESS + 0.15, format!(r#"particle minecraft:block{{block_state:"minecraft:obsidian"}} {x:.1} {:.1} {z:.1} 26 5 26 0.8 320 force"#, y + 3.0));
    if !terrain {
        return;
    }
    // (what it throws out from under it: earth, and the dark it pressed in, flung out over the land, half of it landing as
    // blocks)
    let mut rng = Rng::new(u64::from(h.borrow().print.seed) ^ 0x4a7d);
    for n in 0..44 {
        let a = rng.uniform(0.0, TAU);
        let r = rng.uniform(25.0, 80.0);
        let (bx2, bz2) = (x + a.cos() * r, z + a.sin() * r);
        let blk = match rng.next() {
            d if d < 0.35 => "minecraft:dirt",
            d if d < 0.55 => "minecraft:coarse_dirt",
            d if d < 0.7 => "minecraft:blackstone",
            d if d < 0.82 => "minecraft:obsidian",
            d if d < 0.92 => "minecraft:cobblestone",
            _ => "minecraft:gravel",
        };
        let hsp = 0.6 + 1.8 * rng.next().powf(1.3);
        let vy = 0.9 + 1.4 * rng.next();
        let (vx, vz) = (a.cos() * hsp, a.sin() * hsp);
        let yy = y + 3.0 + 4.0 * rng.next();
        let t = SB_PRESS + 0.05 + 0.6 * rng.next().powf(1.5) as f32;
        let keep = if n % 2 == 0 { "" } else { ",CancelDrop:1b" };
        p.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {bx2:.2} {yy:.2} {bz2:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
    }
    for t in [SB_PRESS + 0.05, SB_PRESS + 1.5] {
        p.at(t, format!("execute positioned {x:.1} {y:.1} {z:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{SB_KILL}]"));
    }
    // (its chunks force-loaded from as it fires: skybreak.rs's load rows, with the panes')
    p.later(SB_PRESS - 4.7, move |q| hd_tick(q, h, SB_PRESS - 4.7));
}
/// A stage a tick from as the hand starts down: its chunks read, made into blocks, let in from the slam.
fn hd_tick(q: &mut Plan, h: SharedHand, now: f32) {
    let now = now.max(clock());
    let more = {
        let mut g = h.borrow_mut();
        let w = &mut *g;
        let (bx, bz, gy) = (q.bx, q.bz, q.by + 1);
        if w.todo.is_empty() && w.next == 0 && w.made.is_empty() && w.sent == 0 {
            crate::trace("hd chunks<");
            w.todo = w.print.chunks(bx, bz);
            crate::trace("hd chunks>");
            crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("skybreak: the hand comes down at {:.0} {:.0} {:.0}, {} chunks", f64::from(bx) + 0.5 + w.print.site[0], f64::from(gy) + w.print.g0, f64::from(bz) + 0.5 + w.print.site[1], w.todo.len()));
        }
        // (the reads, a few lots out at once)
        if w.lots.len() < SB_FLIGHT && w.next < w.todo.len() {
            let end = (w.next + SB_LOT).min(w.todo.len());
            let chunks: Vec<(i32, i32)> = w.todo[w.next..end].to_vec();
            w.next = end;
            let columns: Vec<(i32, i32)> = chunks.iter().flat_map(|c| (0..256).map(move |j| (c.0 + (j & 15), c.1 + (j >> 4)))).collect();
            let tag = crate::columns::new_tag();
            crate::meter::spend(40 * columns.len() as u64);
            q.ev.push((now, Act::Read { tag, columns, below: SB_BELOW, above: 1 }));
            w.lots.push_back(Lot { tag, asked: now, chunks, next: 0, read: None, kinds: Vec::new(), lava: Vec::new(), answered: false });
        }
        // (what's been read made into blocks, as much as a tick should)
        let (sx, sz) = (w.print.site[0] + f64::from(bx), w.print.site[1] + f64::from(bz));
        while crate::meter::spent() < SB_TICK {
            let Some(lot) = w.lots.front_mut() else { break };
            if !lot.answered {
                if let Some(a) = crate::columns::take(lot.tag) {
                    lot.kinds = a.palette.iter().map(|n| kind(n)).collect();
                    lot.lava = a.palette.iter().map(|n| n.contains("lava")).collect();
                    crate::meter::spend(2_000 + 4_000 * a.palette.len() as u64);
                    lot.read = Some(a);
                    lot.answered = true;
                } else if now > lot.asked + 3.5 {
                    crate::columns::forget(lot.tag);
                    lot.answered = true;
                } else {
                    break;
                }
            }
            let (x0, z0) = lot.chunks[lot.next];
            let read = lot.read.as_ref().map(|a| {
                let base = lot.next * 256;
                crate::meter::spend(4_000);
                (0..256).map(|j| column_of(a, base + j, &lot.kinds)).collect::<Vec<Option<Col>>>()
            });
            // (where lava is in each column, if any was read)
            let lavas = lot.read.as_ref().filter(|_| lot.lava.iter().any(|&l| l)).map(|a| {
                let base = lot.next * 256;
                (0..256)
                    .map(|j| {
                        a.column(base + j).map_or((0, 0u64), |(surface, blocks)| {
                            crate::meter::spend(20 * blocks.len() as u64);
                            let m = blocks.iter().take(64).enumerate().filter(|(_, bk)| lot.lava.get(**bk as usize).copied().unwrap_or(false)).fold(0u64, |m, (k, _)| m | 1 << k);
                            (surface - a.below as i32, m)
                        })
                    })
                    .collect::<Vec<(i32, u64)>>()
            });
            let unloaded = lot.read.as_ref().is_none_or(|a| (0..256).filter(|&j| a.bases.get(lot.next * 256 + j).copied().flatten().is_none()).count() > 128);
            lot.next += 1;
            if lot.next >= lot.chunks.len() {
                w.lots.pop_front();
            }
            if unloaded {
                crate::meter::spend(30_000);
                if now < SB_GIVE_UP {
                    w.todo.push((x0, z0));
                } else {
                    w.lost += 1;
                }
                continue;
            }
            crate::trace("hd chunk<");
            let mut b = w.print.chunk(x0, z0, bx, bz, gy, read.as_deref(), lavas.as_deref());
            crate::trace("hd chunk>");
            b.runs.shrink_to_fit();
            b.cleanup = true;
            b.clear_of_player = true;
            let d = (f64::from(x0) + 8.0 - sx).hypot(f64::from(z0) + 8.0 - sz);
            w.made.push((d, b));
        }
        // (from the slam: what's made goes in, the middle first, as much a tick as a stage should give (the playback counts
        // each run it gives))
        if now >= SB_PRESS && !w.made.is_empty() {
            w.made.sort_by(|a, b| b.0.total_cmp(&a.0));
            let mut runs = 0;
            while let Some((d, b)) = w.made.pop() {
                if runs > 0 && runs + b.runs.len() > SB_RUNS {
                    w.made.push((d, b));
                    break;
                }
                runs += b.runs.len();
                q.ev.push((now.max(SB_PRESS + 0.05 + (d / 900.0) as f32), Act::Blocks(Box::new(b))));
                w.sent += 1;
            }
        }
        let busy = w.next < w.todo.len() || !w.lots.is_empty() || !w.made.is_empty();
        if !busy && !w.done && now >= SB_PRESS {
            w.done = true;
            crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("skybreak: the hand's print laid, {} chunks{}", w.sent, if w.lost > 0 { format!(", {} never loaded", w.lost) } else { String::new() }));
        }
        // (all made before the slam: nothing to do until it)
        if busy { Some(now + 0.05) } else if now < SB_PRESS { Some(SB_PRESS) } else { None }
    };
    if let Some(t) = more {
        q.later(t, move |q| hd_tick(q, h, t));
    }
}

/// A column of the preview's land (strike/skybreak.rs's sb_write_table: `SB_LAND`): its ground's top, the water's top on
/// it if any, the lava under it if any (lowest, highest).
#[cfg(test)]
#[derive(Clone, Copy)]
pub(super) struct Land {
    pub ground: i32,
    pub water: Option<i32>,
    pub lava: Option<(i32, i32)>,
}
/// The preview's land round the crater: flat, or `hills` high (the preview's `hills_h`), or (`lake`) flat with a lake at
/// the edge of the bowl and a pocket of lava under its side, `gy` the target's ground's Y.
#[cfg(test)]
pub(super) fn land_of(p: &Print, gy: i32, hills: f64, lake: bool) -> impl Fn(i32, i32) -> Land + '_ {
    move |x: i32, z: i32| {
        let (fx, fz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
        let h = hills * (0.5 * (fx * 0.045 + 0.7).sin() * (fz * 0.038).cos() + 0.5 * (fx * 0.013 - fz * 0.017).sin());
        let mut l = Land { ground: gy - 1 + h.round() as i32, water: None, lava: None };
        if lake {
            let (u, v) = p.local(fx, fz);
            // (the lake: out past the bowl's rim on its far side, and in over it)
            let q = ((u - 85.0) / 70.0).hypot((v - 15.0) / 52.0);
            if q < 1.0 {
                let deep = (8.0 * (1.0 - q * q)).round() as i32 + 1;
                l.ground = gy - 1 - deep;
                l.water = Some(gy - 2);
            }
            // (the lava: under the bowl's side, 15 to 20 down)
            if (u + 10.0).hypot(v - 50.0) < 26.0 {
                l.lava = Some((gy - 21, gy - 16));
            }
        }
        l
    }
}
/// The crater played on the preview's land (`land`; its grass on dirt, the wood of `wood_at`): each column it changes,
/// its blocks from `gy` - 70 up.
#[cfg(test)]
pub(super) fn play(p: &Print, gy: i32, land: &dyn Fn(i32, i32) -> Land) -> std::collections::HashMap<(i32, i32), Vec<String>> {
    use std::collections::HashMap;
    let mut cols: HashMap<(i32, i32), Vec<String>> = HashMap::new();
    let base = gy - 70;
    let fresh = |x: i32, z: i32| -> Vec<String> {
        let l = land(x, z);
        let (trunk, crown) = if l.water.is_some() { (false, false) } else { super::sb_lodge::wood_at(x, z) };
        let g = l.ground;
        (base..g + 9)
            .map(|y| {
                match y {
                    _ if l.lava.is_some_and(|(a, b)| y >= a && y <= b) => "minecraft:lava",
                    _ if y == g => if l.water.is_some() { "minecraft:sand" } else { "minecraft:grass_block" },
                    _ if y < g - 4 => "minecraft:stone",
                    _ if y < g => "minecraft:dirt",
                    _ if l.water.is_some_and(|w| y <= w) => "minecraft:water",
                    _ if trunk && y <= g + 6 => "minecraft:oak_log",
                    _ if crown && y >= g + 5 && y <= g + 8 => "minecraft:oak_leaves",
                    _ => "minecraft:air",
                }
                .to_string()
            })
            .collect()
    };
    for (x0, z0) in p.chunks(0, 0) {
        let mut read = Vec::with_capacity(256);
        let mut lava = Vec::with_capacity(256);
        for j in 0..256 {
            let (x, z) = (x0 + (j & 15), z0 + (j >> 4));
            let l = land(x, z);
            let (trunk, crown) = if l.water.is_some() { (false, false) } else { super::sb_lodge::wood_at(x, z) };
            let top = l.water.unwrap_or(if crown { l.ground + 8 } else if trunk { l.ground + 6 } else { l.ground });
            read.push(Some(Col { g: l.ground, top, fluid: l.water.is_some(), trunk: if trunk { 6 } else { 0 }, wood: 0 }));
            let lb = l.ground - 40;
            lava.push((lb, l.lava.map_or(0, |(a, b)| (a..=b).filter(|y| y - lb >= 0 && y - lb < 64).fold(0u64, |m, y| m | 1 << (y - lb)))));
        }
        let e = p.chunk(x0, z0, 0, 0, gy, Some(&read), Some(&lava)).edit();
        for r in &e.runs {
            let name = e.palette[r.block as usize].clone();
            let c = cols.entry((r.x, r.z)).or_insert_with(|| fresh(r.x, r.z));
            for y in r.y..r.y + r.height as i32 {
                let i = y - base;
                if i < 0 {
                    continue;
                }
                let i = i as usize;
                if c.len() <= i {
                    c.resize(i + 1, "minecraft:air".to_string());
                }
                c[i] = name.clone();
            }
        }
    }
    cols
}
/// The crater as the preview's voxels (`x y z r g b` a line) on the preview's land: each column it changes, its top dozen
/// blocks in their colours.
#[cfg(test)]
pub(super) fn voxels(p: &Print, gy: i32, land: &dyn Fn(i32, i32) -> Land) -> String {
    let base = gy - 70;
    let mut out = String::new();
    for ((x, z), c) in play(p, gy, land) {
        let Some(top) = c.iter().rposition(|n| !n.ends_with(":air")) else { continue };
        for (i, n) in c.iter().enumerate().skip(top.saturating_sub(14)) {
            if n.ends_with(":air") {
                continue;
            }
            let rgb = match n.as_str() {
                "minecraft:grass_block" => [96, 150, 70],
                "minecraft:obsidian" => [20, 18, 32],
                "minecraft:crying_obsidian" => [60, 20, 110],
                "minecraft:blackstone" => [44, 37, 43],
                "minecraft:water" => [48, 86, 190],
                "minecraft:lava" => [235, 115, 25],
                "minecraft:magma_block" => [150, 62, 30],
                "minecraft:sand" => [214, 200, 150],
                _ if n.contains("leaves") => [58, 110, 40],
                _ if n.contains("_log") => [104, 82, 50],
                _ => super::hurricane::hu_block(n).map_or([128, 128, 128], |b| super::hu_blocks::HU_BLOCKS[b as usize].top),
            };
            out.push_str(&format!("{x} {} {z} {:.3} {:.3} {:.3}\n", base + i as i32, f64::from(rgb[0]) / 255.0, f64::from(rgb[1]) / 255.0, f64::from(rgb[2]) / 255.0));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::super::skybreak::{Mesh, sb_shards};
    use super::*;

    const ME: [f64; 3] = [0.0, 5.0, 300.0];
    fn print(seed: u32) -> Print {
        print_at(seed, ME)
    }
    fn print_at(seed: u32, me: [f64; 3]) -> Print {
        let mesh = Mesh::new(seed, me);
        let shards = sb_shards(&mesh, seed, me);
        Print::new(me, &shards, seed)
    }
    /// The print, read from a flat land with nothing on it: the column at (x, z) of the world after its edits, as its
    /// ground's height (ground at 64, the target's ground at 65).
    fn heights(p: &Print) -> std::collections::HashMap<(i32, i32), i32> {
        let mut out = std::collections::HashMap::new();
        for (x0, z0) in p.chunks(0, 0) {
            let read: Vec<Option<Col>> = (0..256).map(|_| Some(Col { g: 64, top: 64, fluid: false, trunk: 0, wood: 0 })).collect();
            let e = p.chunk(x0, z0, 0, 0, 65, Some(&read), None).edit();
            for j in 0..256 {
                out.insert((x0 + (j & 15), z0 + (j >> 4)), 64);
            }
            for r in &e.runs {
                let n = &e.palette[r.block as usize];
                let top = r.y + r.height as i32 - 1;
                let h = out.get_mut(&(r.x, r.z)).unwrap();
                if n.ends_with(":air") {
                    if r.y <= *h {
                        *h = r.y - 1;
                    }
                } else if top > *h {
                    *h = top;
                }
            }
        }
        out
    }
    /// The fist's crater: its knuckles' dents deepest (the middle one most), each deeper than the land between it and the
    /// next, the flat of the fingers behind them a little less; a bowl round it falling away to its rim, the earth heaped
    /// there.
    #[test]
    fn the_fist_leaves_its_crater() {
        for seed in [37u32, 5, 1234] {
            let p = print(seed);
            let h = heights(&p);
            let at = |u: f64, v: f64| {
                let [x, z] = p.world(u * SB_SC, v * SB_SC);
                64 - h.get(&(x.floor() as i32, z.floor() as i32)).copied().unwrap_or(64)
            };
            let deepest = (SB_DEEP * SB_SC).round() as i32;
            let mid = at(HD_KNUCKLES[1].0, HD_KNUCKLES[1].1);
            assert!((mid - deepest).abs() <= 3, "seed {seed}: the middle knuckle {mid} deep");
            for w in HD_KNUCKLES.windows(2) {
                let (a, b) = (at(w[0].0, w[0].1), at(w[1].0, w[1].1));
                let between = at(0.5 * (w[0].0 + w[1].0), 0.5 * (w[0].1 + w[1].1));
                assert!(a.max(b) > between, "seed {seed}: no dents ({a} {between} {b})");
            }
            let flat = at(-2.0, 2.0);
            assert!(flat < mid && flat > mid - 12, "seed {seed}: the fingers' flat {flat} deep");
            // (down a line out from it the bowl rises to its rim, never far back down on the way)
            for a in [0.3f64, 1.9, 3.5, 5.0] {
                let mut last = at(0.0, 0.0);
                for k in 1..30 {
                    let rr = f64::from(k) * 1.2;
                    let d = at(rr * a.cos() * SB_BOWL[0] / 24.0, rr * a.sin() * SB_BOWL[1] / 24.0);
                    if rr > 15.0 && rr < 22.0 {
                        assert!(d <= last + 3, "seed {seed}: the bowl {d} deep at {rr} past {last}");
                    }
                    last = d;
                }
            }
            let (mut lip, mut heaped) = (0, 0);
            for k in 0..64 {
                let a = TAU * f64::from(k) / 64.0;
                for rr in [1.06, 1.08] {
                    let (u, v) = (SB_BOWL[0] * rr * a.cos(), SB_BOWL[1] * rr * a.sin());
                    if (p.bowl_r(u * SB_SC, v * SB_SC) - 1.07).abs() < 0.03 {
                        lip += 1;
                        heaped += usize::from(at(u, v) < 0);
                    }
                }
            }
            assert!(heaped * 10 > lip * 6, "seed {seed}: only {heaped} of {lip} round it heaped");
        }
    }
    /// The fist comes down on the target wherever the player stands (on it, too): the middle of its face on the target's
    /// column, its back square to the way they look, the same hand as the side they are on.
    #[test]
    fn sb_the_fist_comes_down_on_the_target() {
        let places = [ME, [0.0, 5.0, 40.0], [-240.0, 2.0, 110.0], [700.0, 30.0, -300.0], [3.0, 0.0, -2.0], [0.4, 0.0, 0.3], [0.0, 0.0, 0.0], [-1000.0, 60.0, 5.0]];
        for seed in [37u32, 5, 1234, 77, 9, 4242] {
            for me in places {
                let p = print_at(seed, me);
                assert!(p.site[0].hypot(p.site[1]) < 1.0, "seed {seed} at {me:?}: the fist {:?} off the target", p.site);
                assert!((p.dir[0].hypot(p.dir[1]) - 1.0).abs() < 1e-9 && p.side.abs() == 1.0, "seed {seed} at {me:?}");
                let l = me[0].hypot(me[2]);
                if l > 1.0 {
                    let along = (me[0] * p.dir[0] + me[2] * p.dir[1]) / l;
                    assert!(along.abs() < 1e-6, "seed {seed} at {me:?}: not side on ({along})");
                    assert_eq!(p.side, if me[0] * p.dir[1] - me[2] * p.dir[0] >= 0.0 { 1.0 } else { -1.0 });
                }
                let arm = Arm::new(&p, me);
                for i in 0..=40 {
                    let q = arm.pose(36.0 + 0.165 * f64::from(i));
                    assert!(q.w.iter().chain(&q.el).chain(&q.sh).all(|v| v.is_finite()), "seed {seed} at {me:?}");
                }
            }
        }
    }
    /// The slam's arm (36.0 to 42.6 s, a 240th of a second apart): every part of its pose finite, and its wrist, elbow and
    /// shoulder never jump between samples (the most each moves in a sample: the fist lands at 2.4 times its mean speed,
    /// some 1,500 blocks a second, so 7 blocks; the shoulder and elbow follow from the same chain); seeds and players as
    /// the fist comes down on the target from every side.
    #[test]
    fn sb_the_slam_arm_never_jumps() {
        let dt = 1.0 / 240.0;
        let mut worst = [0.0f64; 3];
        for seed in [37u32, 5, 1234, 77, 9] {
            for me in [ME, [0.0, 5.0, 40.0], [-240.0, 2.0, 110.0], [0.3, 0.0, 0.2], [500.0, 10.0, 500.0]] {
                let mut p = print_at(seed, me);
                p.g0 = 3.0;
                let arm = Arm::new(&p, me);
                let mut last: Option<ArmPose> = None;
                let mut t = 36.0;
                while t <= 42.6 {
                    let q = arm.pose(t);
                    let parts = [q.w, q.el, q.sh, q.az, q.ay];
                    assert!(parts.iter().flatten().chain(&q.fl).chain(&q.hk).all(|v| v.is_finite()) && q.th.is_finite() && q.k.is_finite(), "seed {seed} at {me:?}: {t:.3} s");
                    if let Some(o) = last {
                        for (k, (a, b)) in [(q.w, o.w), (q.el, o.el), (q.sh, o.sh)].iter().enumerate() {
                            let d = vsub(*a, *b);
                            let m = vdot(d, d).sqrt();
                            worst[k] = worst[k].max(m);
                            assert!(m < 9.0, "seed {seed} at {me:?}: part {k} jumps {m:.1} at {t:.3} s");
                        }
                        // (the hand's frame turns smoothly too)
                        assert!(vdot(q.az, o.az) > 0.99 && vdot(q.ay, o.ay) > 0.99, "seed {seed} at {me:?}: the hand turns over at {t:.3} s");
                    }
                    last = Some(q);
                    t += dt;
                }
            }
        }
        eprintln!("the most the wrist, elbow and shoulder move in a 240th: {:.2} {:.2} {:.2}", worst[0], worst[1], worst[2]);
    }
    /// The sky's glass as the pass has it (skybreak.wgsl's sb_open and its healing): each cell, how near and far it
    /// comes from the middle, and when it is half gone.
    struct Sky {
        cells: Vec<(Vec<[f64; 2]>, f64, f64, f64)>,
    }
    impl Sky {
        fn new(seed: u32, me: [f64; 3]) -> Sky {
            use super::super::skybreak::{SB_K, SB_KNOCK, SB_SAG, cell_id, near, sb_crushed, sb_fragments};
            let mesh = Mesh::new(seed, me);
            let shards = sb_shards(&mesh, seed, me);
            let frags = sb_fragments(&mesh, seed);
            let mut when: std::collections::HashMap<usize, f64> = Default::default();
            for (id, code) in sb_crushed(&mesh, seed) {
                when.insert(id, if code == 63 { f64::from(SB_CRACK) + 0.045 } else { f64::from(SB_KNOCK) + 0.1 + 0.045 });
            }
            for s in &shards {
                when.insert(s.cell, f64::from(s.tr - SB_SAG) + 0.075);
            }
            for f in &frags {
                when.insert(f.0, if f.4 { f64::from(SB_CRACK) } else { f64::from(f.3) } + 0.045);
            }
            let mut cells = Vec::new();
            for k in 0..SB_K {
                for (part, n, poly) in mesh.cells(k) {
                    let far = poly.iter().map(|v| v[0].hypot(v[1])).fold(0.0, f64::max);
                    let nr = near(&poly);
                    let t = when.get(&cell_id(k, part, n)).copied().unwrap_or(f64::MAX);
                    cells.push((poly, nr, far, t));
                }
            }
            Sky { cells }
        }
        fn inside(poly: &[[f64; 2]], q: [f64; 2]) -> bool {
            let mut c = false;
            let n = poly.len();
            for i in 0..n {
                let (a, b) = (poly[i], poly[(i + n - 1) % n]);
                if (a[1] > q[1]) != (b[1] > q[1]) && q[0] < (b[0] - a[0]) * (q[1] - a[1]) / (b[1] - a[1]) + a[0] {
                    c = !c;
                }
            }
            c
        }
        /// Whether the glass at (x, z) on the sky is gone at t (healing closed again from the edge of its hole).
        fn open(&self, q: [f64; 2], t: f64) -> bool {
            let r = q[0].hypot(q[1]);
            let Some(cell) = self.cells.iter().find(|c| r >= c.1 - 1e-6 && r <= c.2 + 1e-6 && Sky::inside(&c.0, q)) else { return false };
            if t < cell.3 {
                return false;
            }
            let heal = smooth(f64::from(super::super::skybreak::SB_HEAL), 46.5, t) * 120.0;
            if heal > 0.0 {
                // (as far from the glass still standing as the healing has come in)
                for c in self.cells.iter().filter(|c| t < c.3 && c.1 < r + heal + 1.0) {
                    let d = (0..c.0.len()).map(|i| seg(q, c.0[i], c.0[(i + 1) % c.0.len()]).0).fold(f64::MAX, f64::min);
                    if d < heal {
                        return false;
                    }
                }
            }
            true
        }
    }
    /// The arm (and the hand, once its fist has broken through) only ever comes through the sky where the glass is
    /// gone: through the punch, its hanging, going back, and the finale's reach down, slam, grinding and lifting out.
    /// Its forearm (as wide as the pass draws it, its ridge and all), elbow, upper arm and hand are checked, as balls along
    /// them, wherever they meet the sky, a 50th of a second apart.
    #[test]
    fn the_arm_keeps_to_the_hole() {
        let sc = SB_SC;
        // (skybreak.wgsl's `hd_fore_ab`, and how far its belly and its bow stand off its line)
        let fore = |c: f64| sc * (10.3 + 1.0 * c + 7.7 * smooth(0.03, 0.72, c) - 3.4 * smooth(0.82, 1.0, c) + 3.2);
        for (seed, me) in [(37u32, ME), (5, [-220.0, 5.0, 200.0]), (1234, [260.0, 20.0, -90.0]), (77, [0.0, 0.0, 600.0])] {
            let sky = Sky::new(seed, me);
            let mut p = print_at(seed, me);
            p.g0 = 4.0;
            let arm = Arm::new(&p, me);
            let mut worst = (f64::MAX, 0.0, "");
            let mut t = f64::from(SB_CRACK) - 0.1;
            while t < 50.0 {
                if (12.9..33.8).contains(&t) {
                    t = 33.8;
                }
                let a = arm.pose(t);
                if a.k > 0.02 {
                    // (balls along it: the forearm, the elbow, the upper arm; and the hand, once its fist has gone through.
                    // Sizes that hold both builds of it: the forearm the rounded one's, the wider; the elbow and
                    // the upper arm the sculpted one's furthest reach from its bones' line (review/NOTES-bake.txt))
                    let mut balls: Vec<(V3, f64, &str)> = Vec::new();
                    for i in 0..=40 {
                        let c = f64::from(i) / 40.0;
                        balls.push((vmix(a.w, a.el, c), fore(c), "forearm"));
                    }
                    let ue = vnorm(vsub(a.el, a.sh));
                    balls.push((vadd(a.el, vmul(ue, 3.0 * sc)), 21.9 * sc, "elbow"));
                    for i in 0..=60 {
                        let c = f64::from(i) / 60.0;
                        balls.push((vmix(a.el, a.sh, c), sc * 20.3, "upper arm"));
                    }
                    if t > f64::from(SB_CRACK) + 0.15 {
                        for l in [[0.0, -1.0, -6.0], [0.0, -4.0, 12.0], [0.0, -2.0, 30.0 - 18.0 * a.fl[1].min(1.0)]] {
                            balls.push((a.at(arm.side(), l), 17.0 * sc, "hand"));
                        }
                    }
                    for (c, r, what) in balls {
                        let dy = (c[1] - SB_H).abs();
                        if dy >= r {
                            continue;
                        }
                        let rr = (r * r - dy * dy).sqrt();
                        for j in 0..=16 {
                            let (x, z) = if j == 16 {
                                (c[0], c[2])
                            } else {
                                let ang = TAU * f64::from(j) / 16.0;
                                (c[0] + rr * ang.cos(), c[2] + rr * ang.sin())
                            };
                            assert!(sky.open([x, z], t), "seed {seed}: its {what} through the glass at {t:.2} s, at {x:.0} {z:.0} ({:.0} out)", x.hypot(z));
                            if x.hypot(z) > 80.0 - worst.0 {
                                worst = (80.0 - x.hypot(z), t, what);
                            }
                        }
                    }
                }
                t += 0.02;
            }
            eprintln!("seed {seed}: the arm's widest through the sky {:.0} out, at {:.2} s ({})", 80.0 - worst.0, worst.1, worst.2);
        }
    }
    /// The arm's whole motion as numbers, for looking at how it moves (review/work/armcheck.py reads it): a line every
    /// 240th of a second to the file $ARM_DUMP, both stretches, for the seed $ARM_SEED (37).
    #[test]
    #[ignore]
    fn arm_motion() {
        use std::io::Write;
        let seed = std::env::var("ARM_SEED").ok().and_then(|v| v.parse().ok()).unwrap_or(37u32);
        let me = ME;
        let mut p = print_at(seed, me);
        p.g0 = 4.0;
        let arm = Arm::new(&p, me);
        let path = std::env::var("ARM_DUMP").unwrap_or_else(|_| "/dev/stderr".into());
        let mut f = std::fs::File::create(path).unwrap();
        writeln!(f, "# fw {} {} {} dir {} 0 {} site {} {} side {} g0 {} sky {}", arm.fw[0], arm.fw[1], arm.fw[2], p.dir[0], p.dir[1], p.site[0], p.site[1], p.side, p.g0, SB_H).unwrap();
        for (t0, n) in SB_HP_WIN {
            for i in 0..((n - 1) * 8 + 1) {
                let t = t0 + i as f64 / 240.0;
                let a = arm.pose(t);
                let mut v = vec![t];
                for x in [a.w, a.el, a.sh, a.az, a.ay] {
                    v.extend(x);
                }
                v.extend(a.fl);
                v.extend(a.hk);
                v.extend([a.th, a.spread, a.k]);
                writeln!(f, "{}", v.iter().map(|x| format!("{x:.6}")).collect::<Vec<_>>().join(" ")).unwrap();
            }
        }
    }
    /// What a pose costs natively (run in release: `cargo test --release --lib arm_table_cost -- --ignored --nocapture`),
    /// to keep `pose`'s `meter::spend` honest: a nanosecond is three or four of the mod's instructions.
    #[test]
    #[ignore]
    fn arm_table_cost() {
        let mut p = print_at(37, ME);
        p.g0 = 4.0;
        let arm = Arm::new(&p, ME);
        for which in 0..2 {
            let t = std::time::Instant::now();
            let mut n = 0;
            for _ in 0..200 {
                n += std::hint::black_box(arm.table(which)).len() / SB_HP_W;
            }
            println!("stretch {which}: {:.0} ns a pose", t.elapsed().as_nanos() as f64 / n as f64);
        }
        for at in [9.0, 34.5, 36.0, 37.2, 38.0, 40.0, 41.5] {
            let t = std::time::Instant::now();
            for i in 0..2000 {
                std::hint::black_box(arm.pose(at + f64::from(i) * 1e-5));
            }
            println!("  at {at}: {:.0} ns", t.elapsed().as_nanos() as f64 / 2000.0);
        }
    }
    /// The arm's two stretches, a 240th of a second apart (both seeds' hands).
    fn stretches() -> Vec<(Arm, f64, ArmPose)> {
        let mut out = Vec::new();
        for (seed, me) in [(37u32, ME), (5, [-220.0, 5.0, 200.0]), (1234, [260.0, 20.0, -90.0])] {
            let mut p = print_at(seed, me);
            p.g0 = 4.0;
            for (t0, n) in SB_HP_WIN {
                for i in 0..(n as f64 / SB_HP_RATE * 240.0) as usize {
                    let t = t0 + i as f64 / 240.0;
                    let arm = Arm::new(&p, me);
                    let a = arm.pose(t);
                    out.push((arm, t, a));
                }
            }
        }
        out
    }
    #[test]
    #[ignore]
    fn arm_dump() {
        let me = ME;
        let mut p = print_at(37, me);
        p.g0 = 4.0;
        let arm = Arm::new(&p, me);
        eprintln!("site {:?} dir {:?} side {} sky {}", p.site, p.dir, p.side, SB_H);
        let mut t = 33.8;
        while t < 43.0 {
            let a = arm.pose(t);
            let f = vnorm(vsub(a.w, a.el));
            eprintln!("{t:.2} el.y {:.0} el.out {:.0} w.y {:.0} w.out {:.0} lean {:.0} flex {:.0} fl {:.2} {:.2} th {:.2} k {:.2}", a.el[1], a.el[0].hypot(a.el[2]), a.w[1], a.w[0].hypot(a.w[2]), f[1].acos().to_degrees(), vdot(f, a.ay).asin().to_degrees(), a.fl[0], a.fl[3], a.th, a.k);
            t += 0.1;
        }
    }
    /// The press before the punch, in numbers (`cargo test --lib press_dump -- --ignored --nocapture`): its wrist's height
    /// over the glass, the middle knuckle's height and place (towards the player, to the elbow's side), how far the hand
    /// is tipped from flat, the forearm's lean, the wrist's bend, and each 240th's biggest step.
    #[test]
    #[ignore]
    fn press_dump() {
        let me = ME;
        let mut p = print_at(37, me);
        p.g0 = 4.0;
        let arm = Arm::new(&p, me);
        let fw = arm.fw;
        let out = [-fw[2], 0.0, fw[0]];
        let mut t = 6.3;
        while t < 9.05 {
            let a = arm.pose(t);
            let kn = a.at(arm.side(), [3.5, 1.6, 7.7]);
            let pm = a.palm();
            let f = vnorm(vsub(a.w, a.el));
            let b = arm.pose(t + 1.0 / 240.0);
            let turn = vdot(a.az, b.az).clamp(-1.0, 1.0).acos().to_degrees() * 240.0;
            eprintln!(
                "{t:.2} wrist {:.0} fw {:.0} | knuckle {:.0} fw {:.0} out {:.0} | palm fw {:.0} out {:.0} | tip {:.0} lean {:.0} flex {:.0} | fl {:.2} {:.2} hk {:.2} th {:.2} sp {:.2} | wrist {:.0}/s hand {:.0} deg/s k {:.2}",
                a.w[1] - SB_H, vdot(a.w, fw), kn[1] - SB_H, vdot(kn, fw), vdot(kn, out), vdot(pm, fw), vdot(pm, out),
                (-a.az[1]).asin().to_degrees(), f[1].abs().acos().to_degrees(), vdot(f, a.ay).asin().to_degrees(),
                a.fl[0], a.fl[3], a.hk[0], a.th, a.spread,
                (0..3).map(|i| (b.w[i] - a.w[i]).powi(2)).sum::<f64>().sqrt() * 240.0, turn, a.k
            );
            if std::env::var("ARM_JOINTS").is_ok() {
                eprintln!("     w {:.0?} el {:.0?} sh {:.0?}", a.w, a.el, a.sh);
            }
            t += 0.05;
        }
    }
    /// Every pose of it is one a man's arm can take: no finger bent back or past a fist, the thumb and the spread within
    /// their ends, the wrist bent no further forward, back or to a side than a wrist goes, the elbow not folded shut.
    #[test]
    fn the_arm_keeps_to_a_mans_ranges() {
        let mut worst = [0.0f64; 4];
        for (arm, t, a) in stretches() {
            if a.k < 0.02 {
                continue;
            }
            for f in a.fl {
                assert!((-0.05..=1.08).contains(&f), "a finger at {f:.2} at {t:.2} s");
            }
            assert!((0.0..=1.0).contains(&a.th) && (0.0..=1.0).contains(&a.spread), "its thumb {:.2}, its spread {:.2} at {t:.2} s", a.th, a.spread);
            assert!((vdot(a.az, a.az) - 1.0).abs() < 1e-6 && (vdot(a.ay, a.ay) - 1.0).abs() < 1e-6 && vdot(a.az, a.ay).abs() < 1e-6, "its frame at {t:.2} s");
            // (the forearm's way in the hand's frame: bent to the palm it leans to the hand's back, and so on)
            let f = vnorm(vsub(a.w, a.el));
            let ax = vmul(vcross(a.ay, a.az), arm.side());
            let flex = vdot(f, a.ay).asin().to_degrees();
            let dev = vdot(f, ax).asin().to_degrees();
            assert!((-65.0..=80.0).contains(&flex), "its wrist bent {flex:.0} degrees at {t:.2} s");
            assert!(dev.abs() <= 30.0, "its wrist {dev:.0} degrees to a side at {t:.2} s");
            assert!(vdot(f, a.az) > 0.0, "its hand folded back on its forearm at {t:.2} s");
            let elbow = vdot(vnorm(vsub(a.sh, a.el)), vnorm(vsub(a.w, a.el))).acos().to_degrees();
            assert!(elbow >= 35.0, "its elbow folded to {elbow:.0} degrees at {t:.2} s");
            worst = [worst[0].max(flex), worst[1].max(-flex), worst[2].max(dev.abs()), worst[3].max(180.0 - elbow)];
        }
        eprintln!("the wrist at most {:.0} forward, {:.0} back, {:.0} to a side; the elbow bent at most {:.0}", worst[0], worst[1], worst[2], worst[3]);
    }
    /// Nothing in it starts or stops in an instant: from one 240th of a second to the next its wrist's, its elbow's and
    /// its fingers' ends' speeds change by no more than a heavy arm's could, and its fingers' curling likewise (but as
    /// the fist meets the land).
    #[test]
    fn the_arm_never_jerks() {
        let all = stretches();
        let dt = 1.0 / 240.0;
        let mut worst = (0.0, 0.0, "");
        for w in all.windows(3) {
            let (t, same) = (w[1].1, (w[2].1 - w[0].1 - 2.0 * dt).abs() < 1e-9);
            if !same || w[0].2.k < 0.02 || (t - f64::from(SB_PRESS)).abs() < 0.06 {
                continue;
            }
            let tip = |i: usize| w[i].2.at(w[i].0.side(), [0.0, 0.0, 30.0]);
            for (what, p) in [("wrist", [w[0].2.w, w[1].2.w, w[2].2.w]), ("elbow", [w[0].2.el, w[1].2.el, w[2].2.el]), ("hand", [tip(0), tip(1), tip(2)])] {
                let dv = vmul(vadd(vsub(p[2], p[1]), vsub(p[0], p[1])), 1.0 / dt);
                let j = vdot(dv, dv).sqrt();
                if j > worst.0 {
                    worst = (j, t, what);
                }
                // (its hardest honest ones: the wrist let go into the punch, 37; the elbow thrown out in the drive, 35)
                assert!(j < 45.0, "its {what} jerks at {t:.3} s: {j:.0} blocks a second in a 240th");
            }
            for i in 0..4 {
                let j = (w[2].2.fl[i] - 2.0 * w[1].2.fl[i] + w[0].2.fl[i]).abs() / dt;
                assert!(j < 0.3, "finger {i} jerks at {t:.3} s: {j:.2} a second in a 240th");
            }
            let j = (w[2].2.th - 2.0 * w[1].2.th + w[0].2.th).abs() / dt;
            assert!(j < 0.3, "its thumb jerks at {t:.3} s");
        }
        eprintln!("the hardest change of speed: {:.1} blocks a second in a 240th, its {} at {:.2} s", worst.0, worst.2, worst.1);
    }
    /// On a hill the bowl follows the land towards its rim (no cliff cut into the hill, and its floor no deeper below
    /// the land there than on the flat), and still goes as deep under the fist as the fist went in.
    #[test]
    fn the_crater_follows_a_hill() {
        for seed in [37u32, 5] {
            let mut p = print(seed);
            let hills = 40.0;
            let g0 = {
                let land = land_of(&p, 65, hills, false);
                f64::from(land(p.site[0].floor() as i32, p.site[1].floor() as i32).ground + 1 - 65)
            };
            p.g0 = g0;
            let land = land_of(&p, 65, hills, false);
            let cols = play(&p, 65, &land);
            let top = |x: i32, z: i32| cols.get(&(x, z)).and_then(|c| c.iter().rposition(|n| !n.ends_with(":air")).map(|i| 65 - 70 + i as i32));
            let mut worst_step = 0;
            for (&(x, z), _) in cols.iter() {
                let (u, v) = p.local(f64::from(x) + 0.5, f64::from(z) + 0.5);
                let r = p.bowl_r(u, v);
                let (Some(a), Some(b)) = (top(x, z), top(x + 1, z)) else { continue };
                if (0.45..0.95).contains(&r) {
                    worst_step = worst_step.max((a - b).abs());
                }
                if (0.86..0.92).contains(&r) {
                    let below = land(x, z).ground - a;
                    assert!(below < 14, "seed {seed}: the bowl {below} under the hill near its rim at {x} {z}");
                }
            }
            assert!(worst_step <= 9, "seed {seed}: a cliff {worst_step} high in the bowl");
            let [kx, kz] = p.world(HD_KNUCKLES[1].0 * SB_SC, HD_KNUCKLES[1].1 * SB_SC);
            let fist = 65 + p.g0 as i32 - top(kx.floor() as i32, kz.floor() as i32).unwrap();
            assert!((fist - (SB_DEEP * SB_SC).round() as i32).abs() <= 3, "seed {seed}: the middle knuckle {fist} in");
        }
    }
    /// By a lake and over lava: the water in the bowl is dug out like any block, nothing laid on it; the lava it bares is
    /// sealed (none left within reach of the bowl's floor and walls).
    #[test]
    fn the_crater_digs_water_and_seals_lava() {
        for seed in [37u32, 1234] {
            let p = print(seed);
            let land = land_of(&p, 65, 0.0, true);
            let cols = play(&p, 65, &land);
            let (mut water_cols, mut lava_cols) = (0, 0);
            let deepest = 65 + p.g0 as i32 - (SB_DEEP * SB_SC).round() as i32;
            for (&(x, z), c) in cols.iter() {
                let (u, v) = p.local(f64::from(x) + 0.5, f64::from(z) + 0.5);
                let r = p.bowl_r(u, v);
                let l = land(x, z);
                let floor = c.iter().rposition(|n| !n.ends_with(":air") && !n.ends_with(":water")).map(|i| 65 - 70 + i as i32).unwrap_or(-999);
                if r < 0.9 && l.water.is_some() {
                    water_cols += 1;
                }
                // (nothing left hanging: no water or block over a gap the dig left)
                if let Some(first) = c.iter().rposition(|n| !n.ends_with(":air")) {
                    assert!(!c[..first].iter().any(|n| n.ends_with(":air")), "seed {seed}: something left hanging at {x} {z} (its floor {floor})");
                }
                if r < 1.1 && l.lava.is_some() {
                    lava_cols += 1;
                    for (i, n) in c.iter().enumerate() {
                        let y = 65 - 70 + i as i32;
                        assert!(!(n.ends_with(":lava") && y >= deepest - 4), "seed {seed}: lava bared at {x} {y} {z}");
                    }
                }
            }
            assert!(water_cols > 20 && lava_cols > 20, "seed {seed}: the lake ({water_cols}) or the lava ({lava_cols}) missed it");
        }
    }
    /// Where a pane lies its blocks are left alone, but where the bowl itself goes; and the bowl is clear of them where it
    /// can be.
    #[test]
    fn the_crater_leaves_the_panes() {
        for seed in [37u32, 5, 1234, 99, 77, 9] {
            let mesh = Mesh::new(seed, ME);
            let shards = sb_shards(&mesh, seed, ME);
            let p = Print::new(ME, &shards, seed);
            let land = land_of(&p, 65, 0.0, false);
            let cols = play(&p, 65, &land);
            for (&(x, z), _) in cols.iter() {
                let (fx, fz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
                if p.on_pane(fx, fz) {
                    let (u, v) = p.local(fx, fz);
                    let (down, _, _) = p.dig(u, v, 0.5);
                    let cracked = p.cracked(fx, fz, &(0..p.cracks.len()).collect::<Vec<_>>()) < 1.0;
                    assert!(down > 0.0 || cracked, "seed {seed}: a pane's blocks swept at {x} {z}: {:?} r {:.2} col {:?}", p.dig(u, v, 0.5), p.bowl_r(u, v), cols.get(&(x, z)).map(|c| c.iter().rev().take(80).filter(|n| !n.ends_with(":air")).take(3).cloned().collect::<Vec<_>>()));
                }
            }
            // (how much of each pane's ground (a disc half its length across its site) the bowl digs, and how much more
            // the rim and the swept band reach (left alone there))
            let mut say = Vec::new();
            for sh in &shards {
                let rr = 0.5 * sh.size();
                let (mut all, mut dug, mut near) = (0, 0, 0);
                let mut x = -rr;
                while x <= rr {
                    let mut z = -rr;
                    while z <= rr {
                        if x.hypot(z) <= rr {
                            let (u, v) = p.local(sh.site[0] + x, sh.site[1] + z);
                            let (down, _, part) = p.dig(u, v, 0.5);
                            all += 1;
                            dug += usize::from(down > 0.5);
                            near += usize::from(down <= 0.5 && part != Part::Out);
                        }
                        z += 2.0;
                    }
                    x += 2.0;
                }
                if dug + near > 0 {
                    say.push(format!("pane {} ({:.0} out, {:.0} long): {}% dug, {}% in the rim/band", sh.i, sh.site[0].hypot(sh.site[1]), sh.size(), 100 * dug / all, 100 * near / all));
                }
            }
            eprintln!("seed {seed}: {}", if say.is_empty() { "no pane under the crater".to_string() } else { say.join("; ") });
        }
    }
    /// The hole the opening's island left at the target (14 deep in its middle; or, deeper than the print, 45) is under
    /// the print: the crater over it comes out as on whole land, its floor filled up to where the print's is, nothing left
    /// open under it.
    #[test]
    fn sb_the_crater_covers_the_islands_hole() {
        for seed in [37u32, 5, 1234] {
            for deep in [14, 45] {
                let p = print(seed);
                let flat = land_of(&p, 65, 0.0, false);
                let holed = |x: i32, z: i32| {
                    let mut l = flat(x, z);
                    let r = (f64::from(x) + 0.5).hypot(f64::from(z) + 0.5);
                    if r < 9.0 {
                        l.ground -= (f64::from(deep) * (1.0 - (r / 9.0).powi(2)).max(0.0).powf(0.8)).round().max(2.0) as i32;
                    }
                    l
                };
                let (a, b) = (play(&p, 65, &flat), play(&p, 65, &holed));
                let top = |c: &Vec<String>| c.iter().rposition(|n| !n.ends_with(":air"));
                for x in -12..12 {
                    for z in -12..12 {
                        let (Some(ca), Some(cb)) = (a.get(&(x, z)), b.get(&(x, z))) else { panic!("seed {seed}: column {x} {z} missed") };
                        let (ta, tb) = (top(ca).unwrap(), top(cb).unwrap());
                        assert_eq!(ta, tb, "seed {seed}, {deep} deep: the floor at {x} {z} {} from whole land's", tb as i32 - ta as i32);
                        assert!(!cb[..tb].iter().any(|n| n.ends_with(":air")), "seed {seed}, {deep} deep: a pit left under the print at {x} {z}");
                    }
                }
            }
        }
    }
    /// No chunk of the print outweighs a stage.
    #[test]
    fn a_chunk_of_the_print_is_cheap() {
        let p = print(37);
        let chunks = p.chunks(0, 0);
        assert!(chunks.len() < 260, "{} chunks", chunks.len());
        let mut most = 0;
        for (x0, z0) in chunks.iter().take(40) {
            let read: Vec<Option<Col>> = (0..256).map(|j| Some(Col { g: 64, top: 70, fluid: false, trunk: if j % 37 == 0 { 6 } else { 0 }, wood: 0 })).collect();
            crate::meter::reset();
            let _ = p.chunk(*x0, *z0, 0, 0, 65, Some(&read), None);
            let spent = crate::meter::spent();
            most = most.max(spent);
            assert!(spent < 3_000_000, "chunk {x0} {z0}: {spent}");
        }
        eprintln!("{} chunks, the costliest {most}", chunks.len());
    }
}
