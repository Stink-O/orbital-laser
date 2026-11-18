//! The Earthquake's trees that fall (terrain on): some trees on the plates that move a lot fall over while the plates
//! move and lie there as real blocks afterwards.
//!
//! A tree that falls is a box of the world turned a quarter turn about a level line through the middle of its lowest log
//! (the hinge), toward one of +x, -x, +z, -z. The box is its trunk's lowest two logs' cells and the crown over them
//! (`EqTree::in_box`). A quarter turn about a line through a block's middle maps the block grid onto itself (`turn`), so
//! the tree lying is real blocks: what the warp draws at the end of the fall and the land at rest agree to the block.
//!
//! - The picture (shaders/earthquake_warp.wgsl's `eq_tree_*`): the fork draws the sections near the trees again as a copy
//!   (`render.warp-on`'s copies, `eq_trees_copy`); in it a vertex in a falling tree's box is turned by the tree's angle
//!   now about its hinge, then moved with its plate; every other vertex of the copy is cut and sent to the eye, so its
//!   faces have no area. The pixels of the land (`copy` 0) whose block lies in a box that has begun to fall are left out,
//!   and the copy's whose block does not. The warp reads the trees from `globals.warp_data` (`render.set-warp-data`,
//!   `eq_tree_data`): two vec4 a tree after one for the count.
//! - The land at rest (strike/eq_land.rs): the trees are found from the land's read once it is in (`eq_tree_at`), and
//!   the read itself changed as if each had fallen (`eq_tree_edits`): the box's blocks left out where they stood and put
//!   down turned (logs along the way they lie, leaves that never decay), only into air, plants or the box's own cells; the
//!   plants where it lies are gone (the warp leaves their pixels out as the crown comes down: `eq_tree_lain`). The chunks
//!   at rest then carry them with their plate like everything else.
//! - When: each with one of its plate's lurches after it is known, two in five with the climax, `EQ_TREE_IN` to that plus
//!   `EQ_TREE_LATE` into it, over `EQ_TREE_FALL` seconds (`eq_tree_turn`: slow, then fast, a small bounce).
use super::earthquake::{EQ_PLATES, EqPlates, eq_h};
use std::cell::RefCell;

/// How many trees fall at most, and how many slabs of the lip (the warp's data holds 63 vec4 after the count: two a tree,
/// then two a slab).
pub(crate) const EQ_TREES: usize = 21;
pub(crate) const EQ_SLABS: usize = 10;
/// How long a slab takes to lean over and go under the lake's lava, seconds (the warp's EQ_SLAB_T).
pub const EQ_SLAB_T: f32 = 2.4;

/// A slab of the low side's lip that comes away (strike/eq_land.rs's `slabs`): a box of the world's columns left
/// standing in the main fault's trench as it is cut, one column of open trench all round it and one block of air over
/// the lake's lava under it, so all its faces are real. It moves with the lip's plate; from `t0` it leans toward the
/// fault about its foot's edge on that side by up to `amax` and drops `fall` under the lava (the warp's copy draws it
/// so; the land's own picture leaves its blocks out from then). At rest its columns are the canyon's.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EqSlab {
    /// Its columns: from (lo) to (hi), world x and z, inclusive.
    pub lo: [i32; 2],
    pub hi: [i32; 2],
    /// Its lowest block's y: everything of its columns from there up is the slab.
    pub yb: i32,
    /// The way it leans: 0 +x, 1 -x, 2 +z, 3 -z.
    pub dir: u8,
    pub plate: usize,
    pub t0: f32,
    /// How far it leans at the most, degrees; how far it drops, blocks.
    pub amax: f32,
    pub fall: f32,
}
impl EqSlab {
    pub fn holds(&self, x: i32, z: i32) -> bool {
        (self.lo[0]..=self.hi[0]).contains(&x) && (self.lo[1]..=self.hi[1]).contains(&z)
    }
}
/// A fall's length, seconds; the share of it before the crown hits the land; how far it bounces back, of the quarter turn.
pub(crate) const EQ_TREE_FALL: f32 = 0.9;
const EQ_TREE_A: f32 = 0.82;
const EQ_TREE_BOUNCE: f32 = 0.05;
/// A tree falls this long into its lurch at the soonest, and up to this much more: with the jolt.
pub(crate) const EQ_TREE_IN: f32 = 0.05;
pub(crate) const EQ_TREE_LATE: f32 = 0.45;
/// Trees fall only within this far of the target, on a plate whose offset is this long at least.
pub(crate) const EQ_TREE_REACH: f32 = 110.0;
pub(crate) const EQ_TREE_MOVE: f32 = 4.0;
/// A tree's trunk stands this far inside its plate at least (in columns); the whole of it, standing and lying, on its
/// plate's own columns (none of a cut, none lined beside one: a lined column's blocks at rest are not all its own).
pub(crate) const EQ_TREE_SPARE: i32 = 1;
/// A lying trunk is nowhere further than this over the land; its crown lies over land no further down than this.
const EQ_TREE_GAP: i32 = 2;
const EQ_TREE_HANG: i32 = 4;
/// A trunk's logs at least and at most; the crown's reach from the trunk at most; how far over the top log it looks.
pub(crate) const EQ_TREE_LOGS: (i32, i32) = (4, 14);
const EQ_TREE_R: i32 = 3;
const EQ_TREE_OVER: i32 = 5;
/// Vines under a tree's crown go with it this far under its hinge.
pub(crate) const EQ_TREE_HUNG: i32 = 6;
/// A tree is known this long before its fall at least (the warp's data goes up with the next frame).
const EQ_TREE_KNOWN: f32 = 0.5;

/// What a block of the read is, to a tree.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Kind {
    Air,
    /// What stands on the land and is no tree (grass, flowers): a lying tree may go where it is.
    Plant,
    /// A vine: it hangs on a tree and goes when the tree does (left out of the box, from where it lies, and from under
    /// its crown).
    Vine,
    Log,
    Leaves,
    Fluid,
    /// The land, or anything else (a bee nest, cocoa): a box holding one doesn't fall.
    Other,
}

/// What the finding asks of the land as read (world blocks and columns).
pub(crate) trait Look {
    fn kind(&mut self, x: i32, y: i32, z: i32) -> Kind;
    /// The column's ground: one over its highest block that is the land (none: not read).
    fn ground(&mut self, x: i32, z: i32) -> Option<i32>;
    /// The column's plate (none: fixed land, a fault's cut or its lining, not read).
    fn plate(&mut self, x: i32, z: i32) -> Option<usize>;
}

/// One tree that falls (world blocks).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EqTree {
    /// The hinge: the trunk's lowest log.
    pub h: [i32; 3],
    /// The crown's box from the trunk: how far toward -x and -z, and toward +x and +z (0 to 7).
    pub lo: [i32; 2],
    pub hi: [i32; 2],
    /// The crown's box's top block over the hinge (its bottom is two over it).
    pub top: i32,
    /// The way it falls: 0 +x, 1 -x, 2 +z, 3 -z.
    pub dir: u8,
    pub plate: usize,
    /// When it starts to fall, strike seconds.
    pub t0: f32,
}

/// How far through its quarter turn a tree is, `u` of the way through its fall (0 to 1): slow, then fast, a small
/// bounce back as the crown hits the land (shaders/earthquake_warp.wgsl's `eq_tree_turn`).
pub fn eq_tree_turn(u: f32) -> f32 {
    if u <= 0.0 {
        return 0.0;
    }
    if u >= 1.0 {
        return 1.0;
    }
    if u < EQ_TREE_A {
        let s = u / EQ_TREE_A;
        return s * s * (0.35 + 0.65 * s);
    }
    1.0 - EQ_TREE_BOUNCE * (std::f32::consts::PI * (u - EQ_TREE_A) / (1.0 - EQ_TREE_A)).sin()
}

impl EqTree {
    /// The way it falls, a unit step (x, z).
    pub fn e(&self) -> [i32; 2] {
        [[1, 0], [-1, 0], [0, 1], [0, -1]][usize::from(self.dir & 3)]
    }
    /// Whether block b is in the box: the trunk's cells at the hinge and over it, or the crown's box from two over it.
    pub fn in_box(&self, b: [i32; 3]) -> bool {
        let [hx, hy, hz] = self.h;
        if b[0] == hx && b[2] == hz && (hy..=hy + 1).contains(&b[1]) {
            return true;
        }
        (hx - self.lo[0]..=hx + self.hi[0]).contains(&b[0]) && (hy + 2..=hy + self.top).contains(&b[1]) && (hz - self.lo[1]..=hz + self.hi[1]).contains(&b[2])
    }
    /// Whether the point p (world) lies in the box or on it: what the warp turns of the copy (`eq_tree_vertex_in`).
    pub fn vertex_in(&self, p: [f32; 3]) -> bool {
        let [hx, hy, hz] = self.h.map(|v| v as f32);
        let within = |v: f32, a: f32, b: f32| v >= a - 0.001 && v <= b + 0.001;
        let trunk = within(p[0], hx, hx + 1.0) && within(p[1], hy, hy + 2.0) && within(p[2], hz, hz + 1.0);
        let crown = within(p[0], hx - self.lo[0] as f32, hx + self.hi[0] as f32 + 1.0)
            && within(p[1], hy + 2.0, hy + self.top as f32 + 1.0)
            && within(p[2], hz - self.lo[1] as f32, hz + self.hi[1] as f32 + 1.0);
        trunk || crown
    }
    /// Where block b lies once the tree has fallen: (along the fall, up) -> (up, -along) from the hinge.
    pub fn turn(&self, b: [i32; 3]) -> [i32; 3] {
        let e = self.e();
        let d = [b[0] - self.h[0], b[1] - self.h[1], b[2] - self.h[2]];
        let along = d[0] * e[0] + d[2] * e[1];
        let side = [d[0] - along * e[0], d[2] - along * e[1]];
        [self.h[0] + side[0] + d[1] * e[0], self.h[1] - along, self.h[2] + side[1] + d[1] * e[1]]
    }
    /// The block that lies at b once the tree has fallen (`turn`'s inverse).
    pub fn unturn(&self, b: [i32; 3]) -> [i32; 3] {
        let e = self.e();
        let d = [b[0] - self.h[0], b[1] - self.h[1], b[2] - self.h[2]];
        let along = d[0] * e[0] + d[2] * e[1];
        let side = [d[0] - along * e[0], d[2] - along * e[1]];
        [self.h[0] + side[0] - d[1] * e[0], self.h[1] + along, self.h[2] + side[1] - d[1] * e[1]]
    }
    /// The point p (world) turned by `a` radians of the fall about the hinge's middle (the warp's `eq_tree_rot`).
    pub fn turn_at(&self, p: [f32; 3], a: f32) -> [f32; 3] {
        let e = self.e().map(|v| v as f32);
        let c = self.h.map(|v| v as f32 + 0.5);
        let d = [p[0] - c[0], p[1] - c[1], p[2] - c[2]];
        let along = d[0] * e[0] + d[2] * e[1];
        let side = [d[0] - along * e[0], d[2] - along * e[1]];
        let (s, k) = a.sin_cos();
        let na = k * along + s * d[1];
        let ny = -s * along + k * d[1];
        [c[0] + side[0] + na * e[0], c[1] + ny, c[2] + side[1] + na * e[1]]
    }
    /// The angle of its fall at strike second t, radians.
    pub fn angle(&self, t: f32) -> f32 {
        std::f32::consts::FRAC_PI_2 * eq_tree_turn((t - self.t0) / EQ_TREE_FALL)
    }
    /// Every block of the box, low to high.
    pub fn cells(&self) -> Vec<[i32; 3]> {
        let [hx, hy, hz] = self.h;
        let mut v = vec![[hx, hy, hz], [hx, hy + 1, hz]];
        for y in hy + 2..=hy + self.top {
            for z in hz - self.lo[1]..=hz + self.hi[1] {
                for x in hx - self.lo[0]..=hx + self.hi[0] {
                    v.push([x, y, z]);
                }
            }
        }
        v
    }
    /// The columns the tree takes up, standing and lying: (x0, z0, x1, z1), inclusive.
    pub fn rect(&self) -> [i32; 4] {
        let [hx, _, hz] = self.h;
        let (mut x0, mut z0, mut x1, mut z1) = (hx - self.lo[0], hz - self.lo[1], hx + self.hi[0], hz + self.hi[1]);
        let e = self.e();
        // (lying: the crown's sides kept, its height laid along the fall)
        let reach = self.top;
        let (lx0, lx1) = if e[0] != 0 { (hx.min(hx + reach * e[0]), hx.max(hx + reach * e[0])) } else { (x0, x1) };
        let (lz0, lz1) = if e[1] != 0 { (hz.min(hz + reach * e[1]), hz.max(hz + reach * e[1])) } else { (z0, z1) };
        x0 = x0.min(lx0);
        x1 = x1.max(lx1);
        z0 = z0.min(lz0);
        z1 = z1.max(lz1);
        [x0, z0, x1, z1]
    }
}

/// The warp's data for these trees (`render.set-warp-data`), from `origin` (the target block's corner, the land one over
/// it: the warp's `eq_warp_origin`): (the count, a circle round every column of theirs standing and lying: x, z, radius),
/// then two vec4 a tree: (hinge x, y, z, t0), (the box's reach toward -x and -z packed (x + 16 z), toward +x and +z the
/// same, the way it falls + 4 x its plate, the crown's top over the hinge).
/// The slabs come after the trees, two vec4 each: (the box's first column x, z and its last x, z, from the origin), (its
/// lowest block's y from the origin, the second it starts to lean, the way it leans + 4 x its plate + 128 x the most it
/// leans in whole degrees, how far it drops); the count is the trees' + 64 x the slabs'.
pub fn eq_tree_data(trees: &[EqTree], slabs: &[EqSlab], origin: [i32; 3]) -> Vec<f32> {
    let n = trees.len().min(EQ_TREES);
    let m = slabs.len().min(EQ_SLABS);
    let (mut x0, mut z0, mut x1, mut z1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
    for t in &trees[..n] {
        let r = t.rect();
        (x0, z0, x1, z1) = (x0.min(r[0]), z0.min(r[1]), x1.max(r[2] + 1), z1.max(r[3] + 1));
    }
    for s in &slabs[..m] {
        (x0, z0, x1, z1) = (x0.min(s.lo[0]), z0.min(s.lo[1]), x1.max(s.hi[0] + 1), z1.max(s.hi[1] + 1));
    }
    let mut v = if n + m == 0 {
        vec![0.0; 4]
    } else {
        let (cx, cz) = ((x0 + x1) as f32 * 0.5, (z0 + z1) as f32 * 0.5);
        vec![(n + 64 * m) as f32, cx - origin[0] as f32, cz - origin[2] as f32, 0.5 * ((x1 - x0) as f32).hypot((z1 - z0) as f32) + 1.0]
    };
    for t in &trees[..n] {
        v.extend([(t.h[0] - origin[0]) as f32, (t.h[1] - origin[1]) as f32, (t.h[2] - origin[2]) as f32, t.t0]);
        v.extend([(t.lo[0] + 16 * t.lo[1]) as f32, (t.hi[0] + 16 * t.hi[1]) as f32, (u32::from(t.dir) + 4 * t.plate as u32) as f32, t.top as f32]);
    }
    for s in &slabs[..m] {
        v.extend([(s.lo[0] - origin[0]) as f32, (s.lo[1] - origin[2]) as f32, (s.hi[0] - origin[0]) as f32, (s.hi[1] - origin[2]) as f32]);
        v.extend([(s.yb - origin[1]) as f32, s.t0, (u32::from(s.dir) + 4 * s.plate as u32 + 128 * s.amax.round().clamp(0.0, 89.0) as u32) as f32, s.fall]);
    }
    // (the last of the 64 vec4: a circle round the trees alone (x, z from the origin, radius; 0 with none), so what is
    // asked of every tree is asked only near them, not all along the lake where the slabs stand)
    if n + m > 0 {
        v.resize(4 * 63, 0.0);
        let (mut x0, mut z0, mut x1, mut z1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        for t in &trees[..n] {
            let r = t.rect();
            (x0, z0, x1, z1) = (x0.min(r[0]), z0.min(r[1]), x1.max(r[2] + 1), z1.max(r[3] + 1));
        }
        if n == 0 {
            v.extend([0.0; 4]);
        } else {
            v.extend([(x0 + x1) as f32 * 0.5 - origin[0] as f32, (z0 + z1) as f32 * 0.5 - origin[2] as f32, 0.5 * ((x1 - x0) as f32).hypot((z1 - z0) as f32) + 2.0, 0.0]);
        }
    }
    v
}

/// The copy's anchor (world) and radius for these trees: every column of theirs, standing and lying, and where their
/// plates move them (`render.warp-on`; the game copies the sections whose middles lie within it and 12 more).
pub fn eq_trees_copy(trees: &[EqTree], slabs: &[EqSlab], pl: &EqPlates) -> Option<([f64; 3], f32)> {
    if trees.is_empty() && slabs.is_empty() {
        return None;
    }
    // (every tree's and every slab's columns: the middle of them all, and how far the farthest corner lies from it)
    let rects: Vec<([i32; 4], i32)> = trees.iter().map(|t| (t.rect(), t.h[1])).chain(slabs.iter().map(|s| ([s.lo[0], s.lo[1], s.hi[0], s.hi[1]], s.yb + 20))).collect();
    let n = rects.len() as f64;
    let mid = [
        rects.iter().map(|(r, _)| f64::from(r[0] + r[2]) * 0.5).sum::<f64>() / n,
        rects.iter().map(|(_, y)| f64::from(*y)).sum::<f64>() / n,
        rects.iter().map(|(r, _)| f64::from(r[1] + r[3]) * 0.5).sum::<f64>() / n,
    ];
    let mut r = 0.0f64;
    for ([x0, z0, x1, z1], _) in &rects {
        for (x, z) in [(x0, z0), (&(x1 + 1), z0), (x0, &(z1 + 1)), (&(x1 + 1), &(z1 + 1))] {
            r = r.max((f64::from(*x) - mid[0]).hypot(f64::from(*z) - mid[2]));
        }
    }
    let far = (0..EQ_PLATES).map(|i| pl.offset(i)).map(|o| f64::from(o[0]).hypot(f64::from(o[2]))).fold(0.0, f64::max);
    Some((mid, (r + far + 4.0) as f32))
}

/// A tree whose trunk stands at (x, y, z) with `logs` logs (found from the read), if it can fall on plate `plate` and its
/// standing and lying both lie on it (its trunk EQ_TREE_SPARE inside it): a single trunk; a crown of logs, leaves and plants only
/// (no vines, nests or snow), the land under it no higher than its box's foot; the way it falls the first of `ways` that
/// leaves it lying on the land: its trunk on air or plants, the land under it no higher than the hinge and never more
/// than EQ_TREE_GAP under it, its crown over land no further down than EQ_TREE_HANG, no other trunk where it
/// lies. Its time is the caller's (`eq_tree_when`).
pub(crate) fn eq_tree_at(look: &mut dyn Look, h: [i32; 3], logs: i32, plate: usize, ways: [u8; 4]) -> Option<EqTree> {
    let [hx, hy, hz] = h;
    if logs < EQ_TREE_LOGS.0 || logs > EQ_TREE_LOGS.1 {
        why(0);
        return None;
    }
    // (first what costs least: its trunk's own plate round it with room to spare)
    let s = EQ_TREE_SPARE;
    for z in hz - s..=hz + s {
        for x in hx - s..=hx + s {
            if look.plate(x, z) != Some(plate) {
                why(1);
                return None;
            }
        }
    }
    // (a single trunk: no log beside its lowest two)
    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
        for y in hy..=hy + 1 {
            if look.kind(hx + dx, y, hz + dz) == Kind::Log {
                why(3);
                return None;
            }
        }
    }
    // (how far its box may reach each way, as far as EQ_TREE_R: short of any other trunk standing there, whose side of
    // the leaves is left with it)
    let mut far = ([EQ_TREE_R; 2], [EQ_TREE_R; 2]);
    for dz in -EQ_TREE_R..=EQ_TREE_R {
        for dx in -EQ_TREE_R..=EQ_TREE_R {
            if (dx, dz) == (0, 0) || dx < -far.0[0] || dx > far.1[0] || dz < -far.0[1] || dz > far.1[1] {
                continue;
            }
            let (x, z) = (hx + dx, hz + dz);
            if look.ground(x, z).is_some_and(|g| look.kind(x, g, z) == Kind::Log) {
                if dx.abs() >= dz.abs() {
                    if dx > 0 { far.1[0] = dx - 1 } else { far.0[0] = -dx - 1 }
                } else if dz > 0 {
                    far.1[1] = dz - 1
                } else {
                    far.0[1] = -dz - 1
                }
            }
        }
    }
    // (the crown: the columns round the trunk with a log or leaves from two over the hinge, that far; and the ones with
    // a vine there, which hang on its outside and go with it)
    let ytop = hy + logs - 1 + EQ_TREE_OVER;
    let (mut lo, mut hi, mut top) = ([0i32; 2], [0i32; 2], logs - 1);
    for dz in -far.0[1]..=far.1[1] {
        for dx in -far.0[0]..=far.1[0] {
            let mut any = false;
            for y in hy + 2..=ytop {
                let k = look.kind(hx + dx, y, hz + dz);
                if k == Kind::Log || k == Kind::Leaves {
                    any = true;
                    top = top.max(y - hy);
                } else if k == Kind::Vine {
                    any = true;
                }
            }
            if any {
                lo = [lo[0].max(-dx), lo[1].max(-dz)];
                hi = [hi[0].max(dx), hi[1].max(dz)];
            }
        }
    }
    let base = EqTree { h, lo, hi, top, dir: 0, plate, t0: 0.0 };
    // (nothing in it but the tree, plants and air; no other trunk; the land under its crown no higher than the box's foot)
    for b in base.cells() {
        match look.kind(b[0], b[1], b[2]) {
            Kind::Air | Kind::Leaves | Kind::Plant | Kind::Vine => {}
            Kind::Log if b[1] >= hy + 2 || (b[0] == hx && b[2] == hz) => {}
            _ => {
                why(4);
                return None;
            }
        }
    }
    for z in hz - lo[1]..=hz + hi[1] {
        for x in hx - lo[0]..=hx + hi[0] {
            if look.ground(x, z).is_none_or(|g| g > hy + 2) {
                why(5);
                return None;
            }
            // (another trunk under the crown still: it would be cut through)
            if (x, z) != (hx, hz) && (look.kind(x, hy, z) == Kind::Log || look.kind(x, hy + 1, z) == Kind::Log || look.ground(x, z).is_some_and(|g| look.kind(x, g, z) == Kind::Log)) {
                why(6);
                return None;
            }
        }
    }
    'ways: for &dir in &ways {
        let t = EqTree { dir, ..base };
        let e = t.e();
        // (all of it, standing and lying, on its plate: what costs least first)
        let [x0, z0, x1, z1] = t.rect();
        for z in z0..=z1 {
            for x in x0..=x1 {
                if look.plate(x, z) != Some(plate) {
                    why(10);
                    continue 'ways;
                }
            }
        }
        // (its trunk: on air or plants all its length, the land under it no higher than the hinge and nowhere more than
        // EQ_TREE_GAP under it)
        for k in 1..logs {
            let (x, z) = (hx + k * e[0], hz + k * e[1]);
            if look.ground(x, z).is_none_or(|g| g > hy || hy - g > EQ_TREE_GAP) || !matches!(look.kind(x, hy, z), Kind::Air | Kind::Plant | Kind::Vine) {
                why(8);
                continue 'ways;
            }
        }
        // (where its crown lies: the land no higher than two over the hinge, no further down than EQ_TREE_HANG, no other
        // trunk standing there)
        let side = if e[0] != 0 { (hz - lo[1], hz + hi[1]) } else { (hx - lo[0], hx + hi[0]) };
        for k in 2..=t.top {
            for w in side.0..=side.1 {
                let (x, z) = if e[0] != 0 { (hx + k * e[0], w) } else { (w, hz + k * e[1]) };
                if look.ground(x, z).is_none_or(|g| g > hy + 2 || hy - g > EQ_TREE_HANG) {
                    why(9);
                    continue 'ways;
                }
                for y in hy..=hy + 1 {
                    if look.kind(x, y, z) == Kind::Log && !t.in_box([x, y, z]) {
                        why(9);
                        continue 'ways;
                    }
                }
            }
        }
        return Some(t);
    }
    why(7);
    None
}

/// The ways a tree on a plate with offset `o` tries to fall: away from the way the plate jumps, across it either way, then
/// with it.
pub(crate) fn eq_tree_ways(o: [i32; 3], salt: u32) -> [u8; 4] {
    let away = if o[0].abs() >= o[2].abs() { if o[0] > 0 { 1 } else { 0 } } else if o[2] > 0 { 3 } else { 2 };
    let across = if away < 2 { [2, 3] } else { [0, 1] };
    if salt & 1 == 0 { [away, across[0], across[1], away ^ 1] } else { [away, across[1], across[0], away ^ 1] }
}

/// When a tree on plate `plate` falls, known at strike second `now`: with one of its plate's lurches after then (the
/// second, the third, the fourth or the climax, two in five with the climax), EQ_TREE_IN to that and EQ_TREE_LATE more
/// into it. None: too late for any.
pub(crate) fn eq_tree_when(pl: &EqPlates, plate: usize, now: f32, salt: u32) -> Option<f32> {
    let h = eq_h(pl.seed, 400 + (salt & 0xffff), salt >> 16);
    let first = match h % 20 {
        0..=3 => 0,
        4..=7 => 1,
        8..=11 => 2,
        _ => 3,
    };
    let ks = [1usize, 2, 3, super::earthquake::EQ_K_CLIMAX];
    let u = ((h >> 8) & 1023) as f32 / 1023.0;
    ks[first..].iter().map(|&k| pl.lurch(plate, k).t + EQ_TREE_IN + EQ_TREE_LATE * u).find(|&t0| t0 >= now + EQ_TREE_KNOWN)
}

/// The read changed as if the tree had fallen: (block, the block of the box whose block goes there; none: air) for each
/// block that changes. The box's logs, leaves, plants and vines left out; the plants and vines where it lies left out too
/// (every cell the box turns onto, and the one over it: shaders/earthquake_warp.wgsl's `eq_tree_lain`), and the vines
/// under its crown as far as EQ_TREE_HUNG under its hinge (`eq_tree_under`); each log and leaf put where
/// `turn` takes it if that is air, a plant or one of the box's own cells (else left out: into the land or something
/// else). The caller lays logs along the way it lies.
pub(crate) fn eq_tree_edits(look: &mut dyn Look, t: &EqTree) -> Vec<([i32; 3], Option<[i32; 3]>)> {
    let mut out: std::collections::BTreeMap<[i32; 3], Option<[i32; 3]>> = std::collections::BTreeMap::new();
    let cells = t.cells();
    let kinds: Vec<Kind> = cells.iter().map(|b| look.kind(b[0], b[1], b[2])).collect();
    for (b, k) in cells.iter().zip(&kinds) {
        if matches!(k, Kind::Log | Kind::Leaves | Kind::Plant | Kind::Vine) {
            out.insert(*b, None);
        }
    }
    for b in &cells {
        let to = t.turn(*b);
        for p in [to, [to[0], to[1] + 1, to[2]]] {
            if !out.contains_key(&p) && matches!(look.kind(p[0], p[1], p[2]), Kind::Plant | Kind::Vine) {
                out.insert(p, None);
            }
        }
    }
    // (the vines that hung from its crown, under the box: `eq_tree_under`)
    let [hx, hy, hz] = t.h;
    for z in hz - t.lo[1]..=hz + t.hi[1] {
        for x in hx - t.lo[0]..=hx + t.hi[0] {
            for y in hy - EQ_TREE_HUNG..=hy + 1 {
                let p = [x, y, z];
                if !out.contains_key(&p) && look.kind(x, y, z) == Kind::Vine {
                    out.insert(p, None);
                }
            }
        }
    }
    for (b, k) in cells.iter().zip(&kinds) {
        if !matches!(k, Kind::Log | Kind::Leaves) {
            continue;
        }
        let to = t.turn(*b);
        if t.in_box(to) || out.contains_key(&to) || look.kind(to[0], to[1], to[2]) == Kind::Air {
            out.insert(to, Some(*b));
        }
    }
    out.into_iter().collect()
}

thread_local! {
    /// Why trunks looked at could not fall, counted (the log's line).
    static WHY: std::cell::Cell<[u32; 13]> = const { std::cell::Cell::new([0; 13]) };
    /// The trees of the strike under way, published by the land's work once known: a count that changes with them, the
    /// trees, the warp's origin.
    static SET: RefCell<(u32, Vec<EqTree>, [i32; 3])> = const { RefCell::new((0, Vec::new(), [0; 3])) };
    /// The slabs of the strike under way.
    static SLABS: RefCell<Vec<EqSlab>> = const { RefCell::new(Vec::new()) };
}
/// One more trunk that could not fall for reason `k`.
pub(crate) fn why(k: usize) {
    WHY.with(|w| {
        let mut v = w.get();
        v[k] += 1;
        w.set(v);
    });
}
/// The counts so far, cleared.
pub(crate) fn why_take() -> [u32; 13] {
    WHY.with(|w| w.replace([0; 13]))
}
/// No trees (a new strike).
pub(crate) fn eq_trees_reset() {
    SLABS.with(|s| s.borrow_mut().clear());
    SET.with(|s| {
        let mut s = s.borrow_mut();
        s.0 = s.0.wrapping_add(1);
        s.1.clear();
    });
}
/// These trees fall in the strike under way, the warp's origin `origin`.
pub(crate) fn eq_trees_publish(trees: &[EqTree], origin: [i32; 3]) {
    SET.with(|s| {
        let mut s = s.borrow_mut();
        s.0 = s.0.wrapping_add(1);
        s.1 = trees.to_vec();
        s.2 = origin;
    });
}
/// The trees as published: a count that changes with them (and with the slabs), the trees, the warp's origin.
pub fn eq_trees_now() -> (u32, Vec<EqTree>, [i32; 3]) {
    SET.with(|s| s.borrow().clone())
}
/// These slabs come away in the strike under way, the warp's origin `origin`.
pub(crate) fn eq_slabs_publish(slabs: &[EqSlab], origin: [i32; 3]) {
    SLABS.with(|s| *s.borrow_mut() = slabs.to_vec());
    SET.with(|s| {
        let mut s = s.borrow_mut();
        s.0 = s.0.wrapping_add(1);
        s.2 = origin;
    });
}
/// The slabs as published.
pub fn eq_slabs_now() -> Vec<EqSlab> {
    SLABS.with(|s| s.borrow().clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tree(dir: u8) -> EqTree {
        EqTree { h: [5, 70, -9], lo: [2, 3], hi: [3, 1], top: 9, dir, plate: 4, t0: 18.9 }
    }

    #[test]
    fn eq_tree_turn_maps_blocks_to_blocks_and_back() {
        for dir in 0..4 {
            let t = tree(dir);
            let e = t.e();
            // (the hinge stays; the trunk lies along the way it falls on the hinge's level; the crown's sides are kept)
            assert_eq!(t.turn(t.h), t.h);
            assert_eq!(t.turn([5, 73, -9]), [5 + 3 * e[0], 70, -9 + 3 * e[1]]);
            let mut seen = std::collections::HashSet::new();
            for b in t.cells() {
                let to = t.turn(b);
                assert_eq!(t.unturn(to), b, "dir {dir}: {b:?}");
                assert!(seen.insert(to), "dir {dir}: two blocks to {to:?}");
                // (the same as the continuous turn at a quarter, block middle to block middle)
                let m = t.turn_at([b[0] as f32 + 0.5, b[1] as f32 + 0.5, b[2] as f32 + 0.5], std::f32::consts::FRAC_PI_2);
                for k in 0..3 {
                    assert!((m[k] - (to[k] as f32 + 0.5)).abs() < 1e-4, "dir {dir}: {b:?} {m:?} {to:?}");
                }
                // (and its corners onto the corners of the block it goes to)
                let c = t.turn_at([b[0] as f32, b[1] as f32, b[2] as f32], std::f32::consts::FRAC_PI_2);
                for k in 0..3 {
                    let f = c[k].round();
                    assert!((c[k] - f).abs() < 1e-4 && (to[k] as f32..=to[k] as f32 + 1.0).contains(&f));
                }
                // (lying: within its rect)
                let [x0, z0, x1, z1] = t.rect();
                assert!((x0..=x1).contains(&to[0]) && (z0..=z1).contains(&to[2]), "dir {dir}: {to:?} out of {:?}", t.rect());
            }
            let s = t.turn_at([1.3, 80.2, 4.4], 0.0);
            assert!((s[0] - 1.3).abs() < 1e-5 && (s[1] - 80.2).abs() < 1e-5 && (s[2] - 4.4).abs() < 1e-5);
        }
    }

    #[test]
    fn eq_tree_box_the_warp_and_the_land_agree_on_its_blocks_and_shell() {
        // The land's box (in_box), the warp's vertices (vertex_in: every corner of a block in the box, and none of a block
        // of its shell wholly in the box's inside) and the warp's pixels (`frag_in`: a pixel's block as the warp finds it).
        for dir in 0..4 {
            let t = tree(dir);
            let [hx, hy, hz] = t.h;
            for y in hy - 2..=hy + t.top + 2 {
                for z in hz - t.lo[1] - 2..=hz + t.hi[1] + 2 {
                    for x in hx - t.lo[0] - 2..=hx + t.hi[0] + 2 {
                        let b = [x, y, z];
                        let inside = t.in_box(b);
                        assert_eq!(inside, frag_in(&t, b), "{b:?}");
                        let corners = (0..8).map(|k| [(x + (k & 1)) as f32, (y + ((k >> 1) & 1)) as f32, (z + (k >> 2)) as f32]);
                        let all = corners.clone().all(|p| t.vertex_in(p));
                        if inside {
                            assert!(all, "{b:?}: a block of the box whose corners are not all turned");
                        }
                        // (a block outside whose every corner is turned lies against the box: its faces drawn turned are
                        // left out by the pixels' test)
                        if !inside && all {
                            assert!(!frag_in(&t, b));
                        }
                        // (the middle of a block's face, stepped a hair into it, is the block: what the pixels' test finds)
                        for (n, f) in [([1.0f32, 0.0, 0.0], 0.5f32), ([-1.0, 0.0, 0.0], 0.5), ([0.0, 1.0, 0.0], 0.5), ([0.0, -1.0, 0.0], 0.5), ([0.0, 0.0, 1.0], 0.5), ([0.0, 0.0, -1.0], 0.5)] {
                            let p = [x as f32 + 0.5 + n[0] * f, y as f32 + 0.5 + n[1] * f, z as f32 + 0.5 + n[2] * f];
                            let q = [p[0] - 0.02 * n[0], p[1] - 0.02 * n[1], p[2] - 0.02 * n[2]].map(|v| v.floor() as i32);
                            assert_eq!(q, b);
                        }
                    }
                }
            }
        }
    }
    /// The warp's pixels' test, as shaders/earthquake_warp.wgsl's `eq_tree_block_in` has it (a block from the origin).
    fn frag_in(t: &EqTree, b: [i32; 3]) -> bool {
        let lo = [t.h[0] - t.lo[0], t.h[1] + 2, t.h[2] - t.lo[1]];
        let hi = [t.h[0] + t.hi[0] + 1, t.h[1] + t.top + 1, t.h[2] + t.hi[1] + 1];
        let crown = (0..3).all(|k| b[k] >= lo[k] && b[k] < hi[k]);
        let trunk = b[0] == t.h[0] && b[2] == t.h[2] && b[1] >= t.h[1] && b[1] <= t.h[1] + 1;
        crown || trunk
    }

    #[test]
    fn eq_tree_falls_slow_then_fast_and_rests_on_a_quarter() {
        assert_eq!(eq_tree_turn(-1.0), 0.0);
        assert_eq!(eq_tree_turn(1.0), 1.0);
        assert!((eq_tree_turn(EQ_TREE_A) - 1.0).abs() < 1e-6);
        // (slow, then fast)
        assert!(eq_tree_turn(0.3) < 0.15 && eq_tree_turn(0.7) - eq_tree_turn(0.6) > 2.0 * (eq_tree_turn(0.2) - eq_tree_turn(0.1)));
        // (a small bounce, never past the quarter)
        let low = (0..100).map(|i| eq_tree_turn(EQ_TREE_A + (1.0 - EQ_TREE_A) * i as f32 / 100.0)).fold(1.0, f32::min);
        assert!(low > 0.9 && low < 0.99);
        assert!((0..=200).all(|i| eq_tree_turn(i as f32 / 200.0) <= 1.0 + 1e-6));
    }

    #[test]
    fn eq_tree_data_packs_two_vec4_a_tree() {
        let t = tree(2);
        let d = eq_tree_data(&[t, t], &[], [0, 65, -10]);
        assert_eq!(d.len(), 256);
        assert!(d[252 + 2] > 0.0 && d[20..252].iter().all(|v| *v == 0.0), "the trees' own circle in the last vec4");
        assert_eq!(&d[4..8], &[5.0, 5.0, 1.0, 18.9]);
        assert_eq!(d[0], 2.0);
        // (the circle round them holds every column of theirs, standing and lying)
        let [x0, z0, x1, z1] = t.rect();
        for (x, z) in [(x0, z0), (x1 + 1, z0), (x0, z1 + 1), (x1 + 1, z1 + 1)] {
            assert!(((x as f32 - d[1]).hypot(z as f32 + 10.0 - d[2])) <= d[3]);
        }
        assert_eq!(eq_tree_data(&[], &[], [0; 3]), vec![0.0; 4]);
        // (the slabs after the trees, two vec4 each, the count the trees' + 64 x theirs)
        let s = EqSlab { lo: [3, -4], hi: [9, 6], yb: 3, dir: 2, plate: 13, t0: 18.9, amax: 41.4, fall: 33.0 };
        let d2 = eq_tree_data(&[t], &[s, s], [0, 65, -10]);
        assert_eq!(d2.len(), 256);
        assert_eq!(d2[0], (1 + 64 * 2) as f32);
        assert_eq!(&d2[12..20], &[3.0, 6.0, 9.0, 16.0, -62.0, 18.9, (2 + 4 * 13 + 128 * 41) as f32, 33.0]);
        assert_eq!(&d[8..12], &[(2 + 16 * 3) as f32, (3 + 16) as f32, (2 + 16) as f32, 9.0]);
        let many = vec![t; 40];
        assert_eq!(eq_tree_data(&many, &[s; 20], [0; 3]).len(), 256, "the warp's 64 vec4");
        assert!(1 + 2 * EQ_TREES + 2 * EQ_SLABS <= 63, "the last vec4 is the trees' circle");
    }

    #[test]
    fn eq_tree_wgsl_in_step() {
        let src = include_str!("../../shaders/earthquake_warp.wgsl");
        let val = |name: &str| -> f32 {
            let line = src.lines().find(|l| l.starts_with(&format!("const {name}: f32 = "))).unwrap_or_else(|| panic!("{name} in the warp"));
            line.split('=').nth(1).unwrap().split(';').next().unwrap().trim().parse().unwrap()
        };
        for (name, v) in [("EQ_TREE_FALL", EQ_TREE_FALL), ("EQ_TREE_A", EQ_TREE_A), ("EQ_TREE_BOUNCE", EQ_TREE_BOUNCE)] {
            assert!((val(name) - v).abs() < 1e-6, "{name}: the warp has {}, the plan {v}", val(name));
        }
        // (the curve, the box, the turn and the data's layout written as here)
        for line in [
            "return s * s * (0.35 + 0.65 * s);",
            "return 1.0 - EQ_TREE_BOUNCE * sin(EQ_PI * (u - EQ_TREE_A) / (1.0 - EQ_TREE_A));",
            "t.lo = vec3<f32>(a.x - f32(lo % 16u), a.y + 2.0, a.z - f32(lo / 16u));",
            "t.hi = vec3<f32>(a.x + f32(hi % 16u) + 1.0, a.y + b.w + 1.0, a.z + f32(hi / 16u) + 1.0);",
            "let crown = all(b >= t.lo) && all(b < t.hi);",
            "let trunk = b.x == t.h.x && b.z == t.h.z && b.y >= t.h.y && b.y <= t.h.y + 1.0;",
            "let crown = all(p >= t.lo - 0.001) && all(p <= t.hi + 0.001);",
            "let trunk = all(p >= t.h - 0.001) && all(p <= t.h + vec3<f32>(1.0, 2.0, 1.0) + 0.001);",
            "let na = k * along + s * d.y;",
            "let ny = -s * along + k * d.y;",
            "let blk = floor(rel - 0.02 * out_home);",
        ] {
            assert!(src.contains(line), "the warp has no `{line}`");
        }
        // (the lake's crust, as strike/earthquake.rs has it)
        use super::super::earthquake::{EQ_CRUST, EQ_CRUST_RIM};
        assert!(src.contains(&format!("const EQ_CRUST: f32 = {EQ_CRUST};")) && src.contains(&format!("const EQ_CRUST_RIM: f32 = {EQ_CRUST_RIM};")));
        assert!(src.contains("return eq_vn(seed, q * (1.0 / 11.0), 61u) + 0.35 * (eq_vn(seed, q * 0.25, 62u) - 0.5);"));
        // (the count: the trees' + 64 x the slabs'; the slabs' numbers)
        assert!(src.contains("return i32(clamp(globals.warp_data[0].x, 0.0, 4095.0) + 0.5) % 64;") && src.contains("return i32(clamp(globals.warp_data[0].x, 0.0, 4095.0) + 0.5) / 64;"));
        assert!(EQ_TREES < 64 && src.contains(&format!("const EQ_SLAB_T: f32 = {EQ_SLAB_T};")));
        for line in ["let k = 1 + 2 * eq_trees_n() + 2 * j;", "s.plate = i32((dp / 4u) % 32u);", "s.amax = f32(dp / 128u) * (EQ_PI / 180.0);", "let ang = s.amax * k * k * (0.4 + 0.6 * k);", "let q = clamp((u - 0.2) / 0.8, 0.0, 1.0);"] {
            assert!(src.contains(line), "the warp has no `{line}`");
        }
        assert!(src.contains("fn eq_trees_near(p: vec3<f32>) -> bool {\n    let d = globals.warp_data[0];\n    return length(p.xz - d.yz) <= d.w;"));
    }
}
