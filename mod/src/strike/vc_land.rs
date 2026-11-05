//! What the Supervolcano leaves: real blocks, terrain on only, going in behind the wall of ash from VC_COLLAPSE. Inside
//! the ring a caldera (`Shape`: about 560 across, its edge scalloped and slumped) with cliffs some 90 high, stepped in
//! slumped benches, on a floor of black crust plates (blackstone, basalt, magma) with lava in the cracks between them;
//! round it a broken, stepped rim out to about 320, cut by the ring's fractures; ignimbrite (tuff and grey ash) out to
//! about 440, deeper in the low ground and thin on the ridges; the trees felled pointing away from the vent out to 520.
//! Water and lava the walls cut into are sealed. The chunks within VC_LOAD (about 2,500) are force-loaded from the
//! moment it fires; past that only what the world has loaded (round the player) changes.
//!
//! The work goes a chunk at a time (`vc_chunk`), in order of when each is due: past the ring as the wall of ash goes over
//! it, inside the ring from the edge in as fast as the world takes the blocks (VC_RATE), so every chunk's edits go in on
//! one tick and the game redraws it once. The caldera needs no read of the land (its runs reach from its floor up past
//! the land's height, known from the pass's heightfield); what lies round it does (`read_columns`, a ring of parts).
use super::nuke::{Kind, LOG_X, LOG_Z, kind};
use super::volcano::{Hf, VC_COLLAPSE, vc_front};
use super::*;
use std::cell::RefCell;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;
/// The land read reaches from VC_READ0 to VC_READ, the square of columns round the vent.
const VC_READ0: f64 = 236.0;
const VC_READ: i32 = 522;
const VC_GW: i32 = 2 * VC_READ + 1;
const VC_BELOW: u32 = 34;
const VC_ABOVE: u32 = 1;
const VC_PARTS: i32 = 168;
/// The chunks within this are force-loaded.
pub(super) const VC_LOAD: f64 = 448.0;
/// What each reaches to: the caldera's cliffs' width, the rim, the ignimbrite, the felled trees.
const VC_CLIFF: f64 = 36.0;
const VC_RIM: f64 = 320.0;
const VC_IGN: f64 = 440.0;
const VC_FELL: f64 = 516.0;
/// The depth of the caldera.
const VC_DEEP: f64 = 90.0;
/// Past this the chunks go in with the wall; inside it from the edge in, VC_RATE blocks a second (PK_RATE's class).
const VC_IN: f64 = 262.0;
const VC_RATE: f64 = 1_200_000.0;
/// How long ahead of its time a chunk's edits are worked out.
const VC_LEAD: f32 = 1.6;
/// A chunk's blocks inside the ring, for the pace.
const VC_COL: f64 = 118.0;
/// What the work of a column is reckoned at, in instructions, besides what `Blocks` counts of its runs.
const VC_UNIT: u64 = 700;

/// A column as read, packed into a word (0: not read), 8 MB of them.
#[derive(Clone, Copy, Debug, Default)]
struct Col {
    g: i32,
    top: i32,
    trunk: u8,
    wood: u8,
    /// Its leaves' wood, 15 none.
    leaves: u8,
    /// 1 grass, 2 dirt.
    ground: u8,
    fluid: bool,
}
impl Col {
    fn pack(&self) -> u64 {
        1 | u64::from(self.fluid) << 1
            | u64::from(self.ground) << 2
            | u64::from(self.leaves) << 4
            | u64::from(self.wood) << 8
            | u64::from(self.trunk) << 12
            | ((self.g + 2048) as u64 & 0xffff) << 20
            | ((self.top + 2048) as u64 & 0xffff) << 36
    }
    fn unpack(w: u64) -> Option<Col> {
        if w & 1 == 0 {
            return None;
        }
        Some(Col {
            fluid: w >> 1 & 1 != 0,
            ground: (w >> 2 & 3) as u8,
            leaves: (w >> 4 & 15) as u8,
            wood: (w >> 8 & 15) as u8,
            trunk: (w >> 12 & 255) as u8,
            g: (w >> 20 & 0xffff) as i32 - 2048,
            top: (w >> 36 & 0xffff) as i32 - 2048,
        })
    }
}

/// How far out part `part` of the read reaches: rings from VC_READ0 out, as many columns in each.
fn read_reach(part: i32) -> f64 {
    let (a, b) = (VC_READ0 * VC_READ0, f64::from(VC_READ * VC_READ));
    (a + (b - a) * f64::from(part) / f64::from(VC_PARTS)).sqrt()
}
/// The columns of ring `part`.
fn read_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let (r0, r1) = (read_reach(part), read_reach(part + 1));
    let (q0, q1) = (r0 * r0, r1 * r1);
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
/// One answer taken in: each column's ground and what stands on it; those not loaded kept to be asked again.
fn take_in(cols: &mut [u64], missing: &mut Vec<(i32, i32)>, a: &crate::columns::Answer, bx: i32, bz: i32) {
    let kinds: Vec<(Kind, u8)> = a.palette.iter().map(|n| kind(n)).collect();
    crate::meter::spend(2_000 + 4_000 * a.palette.len() as u64);
    for (i, &(x, z)) in a.columns.iter().enumerate() {
        let Some((surface, blocks)) = a.column(i) else {
            crate::meter::spend(60);
            missing.push((x, z));
            continue;
        };
        let base = surface - a.below;
        crate::meter::spend(200 + 12 * blocks.len() as u64);
        let mut c = Col { leaves: 15, ..Default::default() };
        let mut top = None;
        let mut g = None;
        for j in (0..blocks.len()).rev() {
            let (k, w) = kinds.get(blocks[j] as usize).copied().unwrap_or((Kind::Loose, 0));
            match k {
                Kind::Air => {}
                Kind::Ground => {
                    top.get_or_insert(base + j as i32);
                    g = Some(j);
                    c.ground = w;
                    break;
                }
                Kind::Fluid => {
                    c.fluid = true;
                    top.get_or_insert(base + j as i32);
                }
                Kind::Leaves => {
                    if c.leaves == 15 {
                        c.leaves = w;
                    }
                    top.get_or_insert(base + j as i32);
                }
                _ => {
                    top.get_or_insert(base + j as i32);
                }
            }
        }
        let Some(gj) = g else { continue };
        c.g = base + gj as i32;
        c.top = top.unwrap_or(c.g);
        let mut n = 0;
        while gj + 1 + n < blocks.len() {
            match kinds.get(blocks[gj + 1 + n] as usize) {
                Some(&(Kind::Log, w)) => {
                    c.wood = w;
                    n += 1;
                }
                _ => break,
            }
        }
        c.trunk = n.min(40) as u8;
        let (ii, kk) = (x - bx + VC_READ, z - bz + VC_READ);
        if (0..VC_GW).contains(&ii) && (0..VC_GW).contains(&kk) {
            cols[(kk * VC_GW + ii) as usize] = c.pack();
        }
    }
}

// ---- the shape --------------------------------------------------------------------------------------------------
#[derive(Clone, Copy)]
pub(super) struct Shape {
    cx: f64,
    cz: f64,
    seed: u32,
    ph: [f64; 5],
    gy: i32,
    /// The caldera's floor.
    floor: i32,
}
impl Shape {
    fn new(cx: f64, cz: f64, seed: u32, gy: i32) -> Self {
        let ph = [1u32, 2, 3, 4, 5].map(|k| TAU * mh(k, seed, 0xc7));
        Shape { cx, cz, seed, ph, gy, floor: gy - VC_DEEP as i32 }
    }
    /// The caldera's edge at bearing a: wandering, bitten into in scallops where its walls slumped.
    fn edge(&self, a: f64) -> f64 {
        let p = self.ph;
        VC_RING_F + 9.0 * (3.0 * a + p[0]).sin() + 7.0 * (5.0 * a + p[1]).sin() + 4.5 * (11.0 * a + p[2]).sin() + 2.5 * (23.0 * a + p[3]).sin() - 12.0 * (7.0 * a + p[4]).sin().abs()
    }
}
const VC_RING_F: f64 = 284.0;

/// The caldera's floor at (x, z): crust plates (a jittered lattice of cells) parted by cracks. How far its top stands
/// from the floor, whether it is a crack, how near one, and the plate's number.
fn crust(x: i32, z: i32, seed: u32) -> (i32, bool, f64, u32) {
    const S: f64 = 15.0;
    let (fx, fz) = (f64::from(x) / S, f64::from(z) / S);
    let (ix, iz) = (fx.floor() as i32, fz.floor() as i32);
    let (mut d1, mut d2, mut id) = (9.0f64, 9.0f64, 0u32);
    for dz in -1..=1 {
        for dx in -1..=1 {
            let (cx, cz) = (ix + dx, iz + dz);
            let h = pcg((cx as u32).wrapping_mul(0x9E37_79B1) ^ (cz as u32).wrapping_mul(0x85EB_CA6B) ^ seed);
            let (jx, jz) = (f64::from(h & 1023) / 1023.0, f64::from(h >> 10 & 1023) / 1023.0);
            let d = (f64::from(cx) + jx - fx).hypot(f64::from(cz) + jz - fz);
            if d < d1 {
                d2 = d1;
                d1 = d;
                id = h;
            } else if d < d2 {
                d2 = d;
            }
        }
    }
    let gap = (d2 - d1) * S;
    (((id >> 20) % 3) as i32 - 1, gap < 1.35, gap, id)
}
fn crust_block(x: i32, y: i32, z: i32, near: f64, id: u32) -> &'static str {
    let h = mh((x * 31 + z * 57 + y * 11) as u32, id, 0xc8);
    if near < 3.2 && h < 0.55 {
        "minecraft:magma_block"
    } else if id & 4 != 0 {
        if h < 0.8 { "minecraft:blackstone" } else { "minecraft:basalt" }
    } else if h < 0.72 {
        "minecraft:basalt"
    } else {
        "minecraft:smooth_basalt"
    }
}
/// The walls' rock, in bands that lean a little: tuff over deepslate over blackstone, the seams of magma low down.
fn wall_block(x: i32, y: i32, z: i32, depth: f64, seed: u32) -> &'static str {
    let h = mh((x * 13 + y * 101 + z * 7) as u32, seed, 0xc9);
    if depth < 26.0 + 7.0 * h {
        if h < 0.7 { "minecraft:tuff" } else { "minecraft:smooth_basalt" }
    } else if depth < 62.0 + 8.0 * h {
        if h < 0.6 { "minecraft:cobbled_deepslate" } else { "minecraft:deepslate" }
    } else if h < 0.1 {
        "minecraft:magma_block"
    } else {
        "minecraft:blackstone"
    }
}
/// The ash laid out over the land.
fn ash_block(x: i32, y: i32, z: i32, seed: u32) -> &'static str {
    let h = vnoise(f64::from(x), f64::from(z), 9.0, seed ^ 0x51) + 0.3 * mh((x * 5 + y * 19 + z * 3) as u32, seed, 0xca);
    if h < 0.5 {
        "minecraft:tuff"
    } else if h < 0.72 {
        "minecraft:gray_terracotta"
    } else if h < 0.92 {
        "minecraft:light_gray_terracotta"
    } else {
        "minecraft:gravel"
    }
}
/// What the rim's broken ground is made of.
fn rim_block(x: i32, y: i32, z: i32, seed: u32) -> &'static str {
    let h = mh((x * 7 + y * 23 + z * 41) as u32, seed, 0xcb);
    if h < 0.45 {
        "minecraft:tuff"
    } else if h < 0.8 {
        "minecraft:basalt"
    } else {
        "minecraft:blackstone"
    }
}

/// The edits to column (x, z), `y1` over the highest the land reaches round it; the land's height there in `hl`.
fn vc_col_edit(b: &mut Blocks, s: &Shape, c: Option<Col>, x: i32, z: i32, y1: i32, hl: f64) {
    crate::meter::spend(VC_UNIT);
    let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
    let r = dx.hypot(dz);
    let a = dz.atan2(dx);
    let e = s.edge(a);
    let u = e - r;
    let air = "minecraft:air";
    if u >= VC_CLIFF {
        // the floor: the land gone, black crust plates, lava in the cracks
        let (off, crack, near, id) = crust(x, z, s.seed);
        let f = s.floor;
        if crack {
            b.run(x, z, f - 3, f - 2, "minecraft:magma_block");
            b.run(x, z, f - 1, f - 1, "minecraft:lava");
            b.run(x, z, f, y1, air);
        } else {
            let top = f + off;
            for y in top - 2..=top {
                b.run(x, z, y, y, crust_block(x, y, z, near, id));
            }
            b.run(x, z, top + 1, y1, air);
        }
        return;
    }
    if u > 0.0 {
        // the cliffs: down from the land to the floor in slumped benches, each its own width round the wall
        let land = hl.max(f64::from(s.floor) + 8.0);
        let k = vnoise(f64::from(x), f64::from(z), 11.0, s.seed ^ 0x77);
        let w = ((u + 7.0 * (k - 0.5)) / 9.0).floor().clamp(0.0, 4.0);
        let drop = (w / 4.0).powf(0.8);
        let top = (land + (f64::from(s.floor) - land) * drop + 3.0 * (k - 0.5)).round() as i32;
        let top = top.max(s.floor + 1);
        for y in top - 2..=top {
            b.run(x, z, y, y, wall_block(x, y, z, land - f64::from(y), s.seed));
        }
        b.run(x, z, top + 1, y1, air);
        // (what the wall cuts into sealed)
        b.put(x, z, s.floor - 4, top - 3, "minecraft:tuff", Some("minecraft:water"), false);
        b.put(x, z, s.floor - 4, top - 3, "minecraft:magma_block", Some("minecraft:lava"), false);
        return;
    }
    let Some(c) = c else { return };
    // past the edge
    if u > -4.0 {
        b.put(x, z, s.floor - 4, c.g, "minecraft:tuff", Some("minecraft:water"), false);
        b.put(x, z, s.floor - 4, c.g, "minecraft:magma_block", Some("minecraft:lava"), false);
    }
    let wide = VC_RIM - e;
    if r < VC_RIM + 8.0 * (vnoise(f64::from(x), f64::from(z), 23.0, s.seed ^ 0x33) - 0.5) && !c.fluid {
        // the rim: broken down in steps towards the edge, cut by the ring's fractures, blackened
        let n = vnoise(f64::from(x), f64::from(z), 7.0, s.seed ^ 0x19);
        let k = (-u + 6.0 * (n - 0.5)) / wide;
        let step = ((1.0 - k.clamp(0.0, 1.0)) * 4.0).floor() * 2.0;
        let frac = ((-u + 9.0 * (vnoise(f64::from(x), f64::from(z), 31.0, s.seed ^ 0x61) - 0.5)).rem_euclid(13.0) - 6.5).abs() < 0.9;
        let top = c.g - step as i32 - if frac { 4 } else { 0 } + (n * 2.0) as i32;
        b.run(x, z, top + 1, c.top.max(c.g), air);
        let d = if frac { 2 } else { 1 };
        for y in top - d..=top {
            b.run(x, z, y, y, rim_block(x, y, z, s.seed));
        }
        return;
    }
    if r < VC_IGN + 26.0 * (vnoise(f64::from(x), f64::from(z), 37.0, s.seed ^ 0x47) - 0.5) {
        // the ignimbrite: filling the low ground up towards one level, thin on the ridges, everything standing swept off
        if c.fluid {
            return;
        }
        let fall = 1.0 - ((r - 330.0) / (VC_IGN - 330.0)).clamp(0.0, 1.0).powi(2);
        let t = ((hl + 3.0 - f64::from(c.g)).clamp(0.0, 16.0) * fall + 1.0 + 1.6 * vnoise(f64::from(x), f64::from(z), 6.0, s.seed ^ 0x29)).round() as i32;
        let top = c.g + t;
        if c.top > top {
            b.run(x, z, top + 1, c.top, air);
        }
        let low = (top - 3).max(c.g + 1);
        if low > c.g + 1 {
            b.run(x, z, c.g + 1, low - 1, "minecraft:tuff");
        }
        for y in low..=top {
            b.run(x, z, y, y, ash_block(x, y, z, s.seed));
        }
        return;
    }
    if r < VC_FELL + 16.0 * (vnoise(f64::from(x), f64::from(z), 29.0, s.seed ^ 0x13) - 0.5) {
        // the trees swept off (their trunks laid down by `vc_fell`), the ground dusted with ash thinning away
        if c.trunk > 0 || c.leaves != 15 {
            let stump = if c.trunk > 0 { 1 + (mh((x * 31 + z * 17) as u32, s.seed, 0x81) * 1.6) as i32 } else { 0 };
            if c.top > c.g + stump {
                b.run(x, z, c.g + 1 + stump, c.top, air);
            }
        }
        let thin = ((r - VC_IGN) / (VC_FELL - VC_IGN)).clamp(0.0, 1.0);
        if c.ground == 1 && vnoise(f64::from(x), f64::from(z), 5.0, s.seed ^ 0x83) > 0.28 + 0.5 * thin {
            b.put(x, z, c.g, c.g, ash_block(x, c.g, z, s.seed), Some("minecraft:grass_block"), false);
        }
    }
}

/// The trees standing on (x, z)'s chunk felled: lying on the land pointing away from the vent, once the wall has swept
/// the land they lie on.
fn vc_fell(due: &mut Vec<(f32, Blocks)>, w: &Work, s: &Shape, x0: i32, z0: i32, bx: i32, bz: i32) {
    let at = |x: i32, z: i32| -> Option<Col> {
        let (i, k) = (x - bx + VC_READ, z - bz + VC_READ);
        if i < 0 || k < 0 || i >= VC_GW || k >= VC_GW {
            return None;
        }
        Col::unpack(w.cols[(k * VC_GW + i) as usize])
    };
    let mut b = Blocks::default();
    let mut far = 0.0f64;
    for z in z0..z0 + 16 {
        for x in x0..x0 + 16 {
            crate::meter::spend(40);
            let Some(c) = at(x, z) else { continue };
            if c.trunk < 3 || c.fluid {
                continue;
            }
            let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
            let r = dx.hypot(dz);
            if !(VC_RIM + 40.0..VC_FELL - 2.0).contains(&r) {
                continue;
            }
            let (ux, uz) = (dx / r, dz / r);
            let (sx, sz, log) = if ux.abs() > uz.abs() { (ux.signum() as i32, 0, LOG_X[c.wood as usize]) } else { (0, uz.signum() as i32, LOG_Z[c.wood as usize]) };
            // (buried under the ash close in, showing further out)
            let lift = if r < VC_IGN { ((VC_IGN + 10.0 - r) * 0.16) as i32 } else { 0 };
            let want = (i32::from(c.trunk) - 1).clamp(2, 7);
            let mut y = c.g + 1 + lift;
            for n in 1..=want {
                let (lx, lz) = (x + sx * n, z + sz * n);
                let Some(l) = at(lx, lz) else { break };
                if l.fluid || (l.g + 1 + lift - y).abs() > 1 {
                    break;
                }
                y = l.g + 1 + lift;
                b.run(lx, lz, y, y, log);
            }
            far = far.max(r + f64::from(want));
        }
    }
    if !b.runs.is_empty() {
        due.push((vc_due(far + 10.0) + 0.4, b));
    }
}

/// When the wall of ash reaches r, past VC_IN; inside it, when the caldera's chunks there are due.
pub(super) fn vc_due(r: f64) -> f32 {
    if r >= VC_IN {
        // (the front's speed is falling, its way known only forward: a few steps of Newton)
        let mut c: f64 = 0.0;
        for _ in 0..6 {
            let v = 25.0 + 35.0 * (-c / 14.0).exp();
            c = (c + (r - vc_front(c)) / v).max(0.0);
        }
        return VC_COLLAPSE + c as f32 + 0.25;
    }
    let area = PI * (VC_IN * VC_IN - r * r);
    VC_COLLAPSE + 1.0 + (area * VC_COL / VC_RATE) as f32
}

struct Work {
    s: Shape,
    hf: Rc<RefCell<Hf>>,
    cols: Vec<u64>,
    tags: Vec<u32>,
    asked: usize,
    taken: usize,
    missing: Vec<(i32, i32)>,
    retry: Option<(u32, f32)>,
    /// The chunks' corners, by when they are due.
    chunks: Vec<(f32, i32, i32)>,
    next: usize,
}
impl Work {
    fn new(s: Shape, bx: i32, bz: i32) -> Self {
        let mut chunks = Vec::new();
        let n = (f64::from(VC_READ) + 24.0) as i32 / 16 + 1;
        let (c0x, c0z) = (bx >> 4, bz >> 4);
        for dz in -n..=n {
            for dx in -n..=n {
                let (x, z) = ((c0x + dx) * 16, (c0z + dz) * 16);
                // (its middle, and the far corner: the wall has passed all of it)
                let (mx, mz) = (f64::from(x) + 8.0 - s.cx, f64::from(z) + 8.0 - s.cz);
                let rm = mx.hypot(mz);
                if rm - 12.0 > f64::from(VC_READ) {
                    continue;
                }
                chunks.push((vc_due(if rm + 11.4 >= VC_IN { rm + 11.4 } else { rm }), x, z));
            }
        }
        chunks.sort_by(|a, b| a.0.total_cmp(&b.0));
        crate::meter::spend(800 * chunks.len() as u64);
        Work { s, hf: Default::default(), cols: Vec::new(), tags: (0..VC_PARTS).map(|_| crate::columns::new_tag()).collect(), asked: 0, taken: 0, missing: Vec::new(), retry: None, chunks, next: 0 }
    }
}

/// One chunk's edits, due at `t`.
fn vc_chunk(q: &mut Plan, w: &Work, t: f32, x0: i32, z0: i32) {
    let (bx, bz) = (q.bx, q.bz);
    let s = w.s;
    let hf = w.hf.borrow();
    let (ox, oz) = (f64::from(x0) + 8.0 - s.cx, f64::from(z0) + 8.0 - s.cz);
    let y1 = (f64::from(s.gy) + hf.max_near(ox, oz) + 48.0).min(318.0) as i32;
    let mut b = Blocks::default();
    for z in z0..z0 + 16 {
        for x in x0..x0 + 16 {
            let c = {
                let (i, k) = (x - bx + VC_READ, z - bz + VC_READ);
                if i < 0 || k < 0 || i >= VC_GW || k >= VC_GW { None } else { w.cols.get((k * VC_GW + i) as usize).and_then(|&v| Col::unpack(v)) }
            };
            let hl = f64::from(s.gy) + hf.at(f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
            vc_col_edit(&mut b, &s, c, x, z, y1, hl);
        }
    }
    if !b.runs.is_empty() {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
    if !w.cols.is_empty() {
        let mut due = Vec::new();
        vc_fell(&mut due, w, &s, x0, z0, bx, bz);
        for (tf, b) in due {
            q.ev.push((tf, Act::Blocks(Box::new(b))));
        }
    }
}

/// One stage of the land's work: the reads, then the chunks coming due.
fn vc_work(q: &mut Plan, w: Rc<RefCell<Work>>, now: f32) {
    let more = {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        let (bx, bz) = (q.bx, q.bz);
        if wk.cols.is_empty() {
            // (zeroed by the allocator: the land's square costs no fuel to make, the pages only when written)
            wk.cols = vec![0u64; (VC_GW * VC_GW) as usize];
        }
        if wk.asked < wk.tags.len() {
            for _ in 0..2.min(wk.tags.len() - wk.asked) {
                let part = wk.asked;
                q.ev.push((now, Act::Read { tag: wk.tags[part], columns: read_columns(bx, bz, part as i32), below: VC_BELOW, above: VC_ABOVE }));
                wk.asked += 1;
            }
        }
        for _ in 0..4 {
            if wk.taken < wk.asked
                && !crate::meter::full()
                && let Some(a) = crate::columns::take(wk.tags[wk.taken])
            {
                take_in(&mut wk.cols, &mut wk.missing, &a, bx, bz);
                wk.taken += 1;
            }
        }
        // (what the world had not loaded asked again, in lots, while there is time)
        if wk.taken == wk.tags.len() && now < VC_COLLAPSE + 2.0 {
            if let Some((tag, since)) = wk.retry {
                if let Some(a) = crate::columns::take(tag) {
                    take_in(&mut wk.cols, &mut wk.missing, &a, bx, bz);
                    wk.retry = None;
                } else if now > since + 3.0 {
                    wk.retry = None;
                }
            } else if !wk.missing.is_empty() {
                let n = wk.missing.len().min(6000);
                let cols: Vec<(i32, i32)> = wk.missing.drain(..n).collect();
                crate::meter::spend(40 * cols.len() as u64);
                let tag = crate::columns::new_tag();
                q.ev.push((now, Act::Read { tag, columns: cols, below: VC_BELOW, above: VC_ABOVE }));
                wk.retry = Some((tag, now));
            }
        }
        while wk.next < wk.chunks.len() && wk.chunks[wk.next].0 <= now + VC_LEAD && !crate::meter::full() {
            let (t, x, z) = wk.chunks[wk.next];
            vc_chunk(q, wk, t, x, z);
            wk.next += 1;
        }
        wk.next < wk.chunks.len()
    };
    if more {
        q.later(now + 0.05, move |q| vc_work(q, w, now + 0.05));
    }
}

/// The land's work in the plan: the chunks round it force-loaded, its stages from a little after it fires; the land's
/// height handed over as it comes (`hf`).
pub(super) fn vc_land_plan(p: &mut Plan, laser: &'static Laser, seed: u32, hf: Rc<RefCell<Hf>>) {
    let (bx, by, bz) = (p.bx, p.by, p.bz);
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let point = [cx, f64::from(by) + 1.0, cz];
    let load = pk_load_rows(point, 0.0, VC_LOAD);
    for [x0, z0, x1, z1] in &load {
        p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
    }
    for [x0, z0, x1, z1] in &load {
        p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
    }
    let s = Shape::new(cx, cz, seed, by + 1);
    p.later(0.2, move |q| {
        let mut w = Work::new(s, q.bx, q.bz);
        w.hf = hf;
        let w = Rc::new(RefCell::new(w));
        // (the land asked for once its chunks have had a moment to load)
        q.later(3.0, move |q| vc_work(q, w, 3.0));
    });
    // (what lives there dies as the wall goes over)
    for r in [300, 400, 520] {
        let t = vc_due(f64::from(r));
        p.at(t, format!("execute positioned {cx:.1} {} {cz:.1} run kill @e[type=!minecraft:player,distance=..{r}]", by + 1));
    }
}

/// The crater a lava bomb leaves where it lands: a few blocks of the land gone, lined with basalt and magma (counted from
/// each column's ground, so it needs no read).
pub(super) fn vc_bomb_crater(x: i32, z: i32, r: i32, seed: u32) -> Blocks {
    let mut b = Blocks::default();
    for dz in -r..=r {
        for dx in -r..=r {
            let q = dx * dx + dz * dz;
            if q > r * r {
                continue;
            }
            let u = 1.0 - f64::from(q).sqrt() / f64::from(r + 1);
            let d = (u * f64::from(r) * 0.8).ceil() as i32;
            let (px, pz) = (x + dx, z + dz);
            b.put(px, pz, -d, 8, "minecraft:air", None, true);
            let m = if mh((px * 7 + pz * 13) as u32, seed, 0xcc) < 0.3 { "minecraft:magma_block" } else { "minecraft:basalt" };
            b.put(px, pz, -d - 1, -d - 1, m, None, true);
        }
    }
    b
}

#[cfg(test)]
mod tests {
    use super::*;

    fn flat(_: i32, _: i32) {}
    #[test]
    fn the_caldera_has_its_shape() {
        let _ = flat;
        let s = Shape::new(0.5, 0.5, 37, 65);
        let mut b = Blocks::default();
        // (the middle: down to the floor, up past the land)
        vc_col_edit(&mut b, &s, None, 0, 0, 120, 65.0);
        let hi = b.runs.iter().map(|r| r.y + r.height as i32 - 1).max().unwrap();
        let lo = b.runs.iter().map(|r| r.y).min().unwrap();
        assert_eq!(hi, 120);
        assert!((-30..=-26).contains(&lo), "floor at {lo}");
        // (its edge wanders about the ring, and stays inside the reach of the read)
        let mut lo_e = f64::MAX;
        let mut hi_e: f64 = 0.0;
        for k in 0..720 {
            let e = s.edge(f64::from(k) * TAU / 720.0);
            lo_e = lo_e.min(e);
            hi_e = hi_e.max(e);
        }
        assert!(lo_e > VC_READ0 + 8.0 && hi_e < VC_RIM - 6.0, "{lo_e}..{hi_e}");
        // (the wall comes down in steps from the land to the floor)
        let top = |x: i32| {
            let mut b = Blocks::default();
            let g = Col { g: 64, top: 64, leaves: 15, ..Default::default() };
            vc_col_edit(&mut b, &s, Some(g), x, 0, 120, 65.0);
            b.runs.iter().filter(|r| b.palette[r.block as usize] == "minecraft:air").map(|r| r.y).min().unwrap_or(65)
        };
        let e = s.edge(0.0) as i32;
        assert!(top(e - 40) < -20, "floor {}", top(e - 40));
        assert!(top(e - 3) > 40, "lip {}", top(e - 3));
    }
    #[test]
    fn a_column_packs_and_unpacks() {
        let c = Col { g: -40, top: 200, trunk: 17, wood: 8, leaves: 15, ground: 2, fluid: true };
        let u = Col::unpack(c.pack()).unwrap();
        assert_eq!((u.g, u.top, u.trunk, u.wood, u.leaves, u.ground, u.fluid), (-40, 200, 17, 8, 15, 2, true));
        assert!(Col::unpack(0).is_none());
    }
    #[test]
    fn the_land_goes_in_behind_the_wall_and_by_the_end() {
        for r in [270.0, 320.0, 400.0, 500.0, 530.0] {
            let t = vc_due(r);
            let f = vc_front(f64::from(t - VC_COLLAPSE));
            assert!(f >= r, "{r} due at {t} with the front at {f}");
            assert!(f < r + 40.0, "{r} due at {t} with the front at {f}");
        }
        assert!(vc_due(0.0) < 72.0, "the middle at {}", vc_due(0.0));
    }
    #[test]
    fn a_chunk_stays_light() {
        crate::meter::reset();
        let s = Shape::new(0.5, 0.5, 37, 65);
        let w = Work { s, hf: Default::default(), cols: vec![Col { g: 64, top: 74, leaves: 2, trunk: 6, ground: 1, ..Default::default() }.pack(); (VC_GW * VC_GW) as usize], tags: Vec::new(), asked: 0, taken: 0, missing: Vec::new(), retry: None, chunks: Vec::new(), next: 0 };
        let mut worst = 0;
        for (x, z) in [(0, 0), (0, 268), (288, 0), (0, 350), (-420, 0), (0, 490)] {
            crate::meter::reset();
            let mut p = Plan { laser: &crate::lasers::SUPERVOLCANO, ev: Vec::new(), rng: Rng::new(7), bx: 0, by: 64, bz: 0 };
            let t0 = std::time::Instant::now();
            vc_chunk(&mut p, &w, 50.0, x, z);
            let el = t0.elapsed();
            let m = crate::meter::spent();
            worst = worst.max(m);
            let runs: usize = p.ev.iter().map(|e| if let Act::Blocks(b) = &e.1 { b.runs.len() } else { 0 }).sum();
            eprintln!("chunk {x} {z}: {runs} runs, {:.2}M counted, {el:?}", m as f64 / 1e6);
            assert!(m < 1_200_000, "a chunk at {x} {z} counted {m}");
        }
    }
}
