//! The Six Stars' plan: a wanted level climbing to six stars, the last of them torn out of the screen and brought
//! down on the target as a burning star the size of a hill (the land's read, wave, felled trees, rubble and thrown
//! blocks follow strike/rod.rs; the table the pass reads follows strike/payload.rs's).
//!
//! The beats (strike seconds; shaders/sixstars.wgsl keeps the same in its `SS_*`): SS_HUD (0.3) a row of six empty
//! stars fades in at the top right of the screen; SS_STARS the six light one by one from the right, each with a soft
//! tick, police sirens rising far off, while the whole sky turns to a hazy golden-hour sunset, the low sun swelling a
//! step with each star and the land shimmering in the heat (the pass alone); SS_PEEL (8.2) the leftmost star, the last
//! lit, snaps out of its slot and, still the screen's flat star, swoops across the picture to where it will hang,
//! turning there into the star in the world, its thickness growing in (the pass); SS_STATION (11.2) it hangs high over
//! the target, SS_DROP (11.8) it falls, tipping over to land flat, burning, shedding burning blocks, its cracks
//! widening; SS_HIT (17.0) it strikes: its middle bursts into a dirty
//! fireball and a column of black smoke, its five points break off and plough out over the land for SS_PLOUGH seconds,
//! each cutting a burning trench; the dust of the blast's front flattens the forest round it.
//!
//! What it leaves is real blocks: a five-pointed crater (`Shape`: its points out to SS_TIP, the land between them to
//! SS_IN, deepest in the middle, the trenches shallower towards their tips), scorched black with lava in its cracks and
//! a few fires burning in the trenches, the white wreck of each point lying at its trench's end, a band of black
//! round the whole star out to SS_BURN of its edge so it reads from above, the earth heaped on its rim, the land
//! flattened and the trees felled pointing away out to SS_FLAT, crowns stripped past it, the grass charred in rays and
//! rubble strewn out to SS_RUBBLE, mobs and items killed within SS_KILL. The middle is dug as it strikes, each trench as
//! the point ploughing it reaches it (Wave), all of it lined from the middle out after.
//!
//! Sounds (`ss_sounds`): its own (tools/sounds_sixstars.py): the bed under the climb, a beat for each star, the peel,
//! the fall, the blast in three tiers by distance and through the ground ahead of it, the points ploughing, the
//! aftermath.
use super::rod::{Column, Due, LEAF_NAMES, LEAVES, LOG_X, LOG_Y, LOG_Z, Land, Sector, Used, ring_columns, take_in_grid};
use super::{Act, Blocks, Col, Plan, Rng, TIDY_BORDER, Target, falloff, mh, pk_load_rows, sound_from, tidy, vnoise};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;

// ---- the clock (shaders/sixstars.wgsl's SS_* mirror every one) --------------------------------------------------------
pub(super) const SS_HUD: f32 = 0.3;
pub(super) const SS_STARS: [f32; 6] = [1.2, 2.35, 3.5, 4.65, 5.8, 6.95];
pub(super) const SS_PEEL: f32 = 8.2;
pub(super) const SS_STATION: f32 = 11.2;
pub(super) const SS_DROP: f32 = 11.8;
pub(super) const SS_HIT: f32 = 17.0;
/// How long the points plough out after it strikes, their tips from SS_R to SS_TIP, slowing (SS_PLOUGH_K).
pub(super) const SS_PLOUGH: f32 = 2.4;
const SS_PLOUGH_K: f64 = 0.8;

// ---- the star and the crater (the pass's SS_R, SS_THICK, SS_IN_K, SS_TIP, SS_IN) ---------------------------------------
/// The falling star: its points' radius and its thickness at the middle (blocks); its inner corners at SS_IN_K of SS_R.
pub(super) const SS_R: f64 = 75.0;
pub(super) const SS_THICK: f64 = 22.0;
pub(super) const SS_IN_K: f64 = 0.42;
/// Where it hangs before it falls: SS_H over the target's ground, SS_BACK beyond the target from the player.
pub(super) const SS_H: f64 = 520.0;
pub(super) const SS_BACK: f64 = 140.0;
/// The crater: its points out to SS_TIP, the land between them in to SS_IN; deepest SS_DEPTH in the middle, the
/// trenches SS_TIP_DEPTH at their tips (at their middles; their walls steep).
pub(super) const SS_TIP: f64 = 170.0;
pub(super) const SS_IN: f64 = 60.0;
const SS_DEPTH: f64 = 40.0;
const SS_TIP_DEPTH: f64 = 15.0;
/// The rim's heap out to SS_RIM of its edge; the band of black round the star out to SS_BURN of it.
const SS_RIM: f64 = 1.22;
const SS_BURN: f64 = 1.42;
/// The land flattened and the trees felled out to SS_FLAT, the crowns stripped SS_BAND past it, the grass charred in
/// rays out to SS_CHAR, the rubble out to SS_RUBBLE.
const SS_FLAT: f64 = 225.0;
const SS_BAND: f64 = 40.0;
const SS_CHAR: f64 = 255.0;
const SS_RUBBLE: f64 = 268.0;
/// The ejecta's rays (the charring and the rubble follow them).
const SS_RAYS: f64 = 17.0;
/// The land read: every column out to SS_READ, SS_BELOW under its top.
const SS_READ: i32 = 272;
const SS_GW: i32 = 2 * SS_READ + 1;
const SS_BELOW: u32 = 36;
const SS_ABOVE: u32 = 1;
const SS_PARTS: i32 = 52;
/// Mobs and dropped items within SS_KILL killed as it strikes.
const SS_KILL: i32 = 260;
/// Real blocks thrown out of the crater as it strikes.
const SS_THROWN: usize = 200;
/// The front's knockback close in (`Act::Shove`).
const SS_KNOCK_OUT: f32 = 0.75;
const SS_KNOCK_UP: f32 = 0.55;
const SS_KNOCK_REACH: f32 = 500.0;

// ---- where it is ---------------------------------------------------------------------------------------------------
/// The star's path from where it hangs to where it strikes, and which way its points lie when it lands.
#[derive(Clone, Debug)]
pub(super) struct SsGeo {
    pub seed: u32,
    /// Away from the player, level (unit, x and z): it hangs beyond the target that way, and its first point lies that
    /// way when it lands (`yaw`, radians, atan2(z, x)).
    away: (f64, f64),
    pub yaw: f64,
    /// The wind (blocks a second, x and z): the smoke drifts with it.
    pub wind: (f64, f64),
    /// The sunset's sun: its bearing (radians, atan2(z, x)), off to one side of the target as the player looks.
    pub sun: f64,
}
fn smooth01(x: f64) -> f64 {
    let x = x.clamp(0.0, 1.0);
    x * x * (3.0 - 2.0 * x)
}
impl SsGeo {
    /// `me`: the player from the target's ground point.
    pub fn new(seed: f32, me: [f64; 3]) -> Self {
        let seed = seed as u32;
        let r = |k: u32| mh(k, seed, 0x5a5);
        let d = me[0].hypot(me[2]);
        let away = if d > 8.0 { (-me[0] / d, -me[2] / d) } else { let a = TAU * r(1); (a.cos(), a.sin()) };
        let yaw = away.1.atan2(away.0);
        let wa = TAU * r(9);
        let ws = 2.0 + 2.5 * r(10);
        // (the sun low beyond the target, 30 to 50 degrees to one side of it)
        let side = if r(2) < 0.5 { -1.0 } else { 1.0 };
        let sun = yaw + side * (30.0 + 20.0 * r(3)).to_radians();
        SsGeo { seed, away, yaw, wind: (wa.cos() * ws, wa.sin() * ws), sun }
    }
    /// Where its middle is at strike time `t` (from the target's ground), SS_STATION to SS_HIT: hanging (drawn up a few
    /// blocks as it gathers itself), then falling faster and faster, a little towards the player, flat onto the target.
    pub fn pos(&self, t: f64) -> [f64; 3] {
        let (st, drop, hit) = (f64::from(SS_STATION), f64::from(SS_DROP), f64::from(SS_HIT));
        let h0 = SS_H + 6.0;
        if t < drop {
            let y = SS_H + 6.0 * smooth01((t - st) / (drop - st));
            return [self.away.0 * SS_BACK, y, self.away.1 * SS_BACK];
        }
        let u = ((t - drop) / (hit - drop)).clamp(0.0, 1.0);
        // (its middle meets the ground as its underside does: half its thickness over it then)
        let y = SS_THICK * 0.5 + (h0 - SS_THICK * 0.5) * (1.0 - u.powf(2.3));
        let k = 1.0 - u.powf(1.6);
        [self.away.0 * SS_BACK * k, y, self.away.1 * SS_BACK * k]
    }
}

// ---- the table the pass reads (render.set-data) --------------------------------------------------------------------
/// Words 0..16 the header: the path's samples, its first sample's time, their spacing, the wind's x and z, the column's
/// height, the billows, the pieces shed, the debris, the yaw, SS_R, SS_THICK, SS_TIP, SS_IN, the sun's bearing,
/// SS_MAGIC. From SS_P the path (three words a sample, from the target's ground), from SS_PF the billows, from SS_FR the
/// pieces shed, from SS_HF the land's heightfield, from SS_DB the debris.
pub(super) const SS_N: usize = 128;
pub(super) const SS_P: usize = 24;
pub(super) const SS_PF: usize = 416;
pub(super) const SS_PW: usize = 8;
pub(super) const SS_PUFFS: usize = 18;
pub(super) const SS_FR: usize = 560;
pub(super) const SS_FW: usize = 12;
pub(super) const SS_CHUNKS: usize = 20;
pub(super) const SS_SPARKS: usize = 12;
/// The column's height (the pass's billows climb to about this).
pub(super) const SS_HC: f64 = 340.0;
pub(super) const SS_MAGIC: f32 = 6006.0;

/// The column's billows: (launch after the strike, rise time, share of the column's height, radius, x and z off its
/// axis): the Payload's, wider, the stem a broad fireball's.
pub(super) fn ss_puffs(seed: u32) -> Vec<[f64; 6]> {
    (0..SS_PUFFS)
        .map(|i| {
            let h = |k: u32| mh(i as u32, seed, 0x5f0 + k);
            let (t0, hf, rad) = if i < 5 {
                (0.05 + 0.3 * h(0), 0.05 + 0.28 * (i as f64 / 5.0) + 0.06 * h(1), 31.0 + 12.0 * h(2))
            } else if i < 11 {
                (0.05 + 0.25 * h(0), 0.38 + 0.34 * ((i - 5) as f64 / 6.0) + 0.06 * h(1), 40.0 + 16.0 * h(2))
            } else {
                (0.0 + 0.12 * h(0), 0.72 + 0.28 * ((i - 11) as f64 / 7.0) + 0.05 * h(1), 60.0 + 20.0 * h(2))
            };
            let tau = 0.7 + 0.45 * h(3);
            let a = TAU * h(4);
            let off = rad * (0.2 + 0.55 * h(5)) * if i < 2 { 1.1 } else if i < 5 { 0.5 } else { 1.0 };
            [t0, tau, hf, rad, a.cos() * off, a.sin() * off]
        })
        .collect()
}

/// The burning blocks it sheds as it falls: chunks torn off its edges, flung out and falling away behind it, burning a
/// second or three, each trailing its own thin smoke; and in its last seconds a spray of sparks. Each: when, how long it
/// burns, its size, 1 for a spark, its drag, where it starts, its speed (from the target's ground).
pub(super) fn ss_fragments(g: &SsGeo) -> Vec<[f64; 11]> {
    let mut out = Vec::new();
    let vel = |t: f64| {
        let (a, b) = (g.pos(t - 0.02), g.pos(t + 0.02));
        [(b[0] - a[0]) / 0.04, (b[1] - a[1]) / 0.04, (b[2] - a[2]) / 0.04]
    };
    for i in 0..SS_CHUNKS + SS_SPARKS {
        let h = |k: u32| mh(i as u32, g.seed, 0x7a0 + k);
        let spark = i >= SS_CHUNKS;
        let (drop, hit) = (f64::from(SS_DROP), f64::from(SS_HIT));
        let t0 = if spark { hit - 3.0 + 2.85 * h(0).sqrt() } else { drop + 0.3 + (hit - drop - 0.6) * h(0).powf(0.8) };
        let c = g.pos(t0);
        let v = vel(t0);
        // (off its edge: somewhere round it, most of the way out)
        let a = TAU * h(1);
        let (ca, sa) = (a.cos(), a.sin());
        let rr = SS_R * (0.55 + 0.4 * h(8));
        // (its plane faces the player as it starts to fall and lies level as it lands: near enough, the edge's offset
        // is level round it and a little up and down)
        let off = [ca * rr, (h(9) - 0.5) * SS_THICK, sa * rr];
        let p0 = [c[0] + off[0], c[1] + off[1], c[2] + off[2]];
        let kick = if spark { 30.0 + 80.0 * h(2) } else { 25.0 + 60.0 * h(2) };
        let keep = if spark { 0.55 + 0.3 * h(3) } else { 0.25 + 0.35 * h(3) };
        let v0 = [v[0] * keep + ca * kick, v[1] * keep + if spark { 0.0 } else { 18.0 * h(4) }, v[2] * keep + sa * kick];
        let life = if spark { 0.4 + 0.6 * h(5) } else { 1.8 + 2.4 * h(5) };
        let size = if spark { 0.5 + 0.6 * h(6) } else { 2.2 + 3.0 * h(6) };
        let drag = if spark { 1.6 + 1.5 * h(7) } else { 0.3 + 0.4 * h(7) };
        out.push([t0, life, size, if spark { 1.0 } else { 0.0 }, drag, p0[0], p0[1], p0[2], v0[0], v0[1], v0[2]]);
    }
    out
}

/// What the pass reads (see SS_P), worked out on the tick after it fires.
pub(super) fn ss_table(seed: f32, me: [f64; 3]) -> Vec<u32> {
    let g = SsGeo::new(seed, me);
    let mut w = vec![0.0f32; SS_FR + (SS_CHUNKS + SS_SPARKS) * SS_FW];
    let dt = f64::from(SS_HIT - SS_STATION) / (SS_N - 1) as f64;
    w[0] = SS_N as f32;
    w[1] = SS_STATION;
    w[2] = dt as f32;
    w[3] = g.wind.0 as f32;
    w[4] = g.wind.1 as f32;
    w[5] = SS_HC as f32;
    w[6] = SS_PUFFS as f32;
    w[7] = (SS_CHUNKS + SS_SPARKS) as f32;
    w[8] = SS_DEBRIS as f32;
    w[9] = g.yaw as f32;
    w[10] = SS_R as f32;
    w[11] = SS_THICK as f32;
    w[12] = SS_TIP as f32;
    w[13] = SS_IN as f32;
    w[14] = g.sun as f32;
    w[15] = SS_MAGIC;
    for i in 0..SS_N {
        let p = g.pos(f64::from(SS_STATION) + dt * i as f64);
        for k in 0..3 {
            w[SS_P + 3 * i + k] = p[k] as f32;
        }
    }
    for (i, p) in ss_puffs(g.seed).iter().enumerate() {
        for k in 0..6 {
            w[SS_PF + SS_PW * i + k] = p[k] as f32;
        }
    }
    for (i, f) in ss_fragments(&g).iter().enumerate() {
        for k in 0..11 {
            w[SS_FR + SS_FW * i + k] = f[k] as f32;
        }
    }
    w.into_iter().map(f32::to_bits).collect()
}

/// The debris the pass draws (chunks of earth and of the star thrown out, falling back far round it): from SS_DB,
/// SS_DW words each: its bearing (x and z), how far out it is torn up, its speed out and up, when, its size, e^(k t0),
/// its spin. Keep in step with sixstars.wgsl's pl_chunk.
pub(super) const SS_DB: usize = 12288;
pub(super) const SS_DW: usize = 10;
pub(super) const SS_DEBRIS: usize = 120;
fn ss_debris_words(seed: u32) -> Vec<u32> {
    let mut w = vec![0.0f32; SS_DEBRIS * SS_DW];
    for i in 0..SS_DEBRIS {
        let h = |k: u32| mh(i as u32, seed, k);
        let ang = h(0x301) * TAU;
        let big = h(0x303);
        let r0 = 6.0 + 60.0 * h(0x306).sqrt();
        let far = h(0x307) < 0.35;
        let el = if far { 0.45 + 0.4 * h(0x302) } else { 0.4 + 0.8 * h(0x302) };
        let sp = (if far { 100.0 + 50.0 * h(0x304) } else { 40.0 + 60.0 * h(0x304).powf(0.7) }) * (1.0 - 0.25 * big);
        let t0 = r0 / 343.0 + 0.15 * h(0x305);
        let row = [ang.cos(), ang.sin(), r0, el.cos() * sp, el.sin() * sp, t0, 0.2 + 1.4 * big * big * big, (0.06 * t0).exp(), 3.0 + 6.0 * h(0x308), 0.0];
        for (k, x) in row.iter().enumerate() {
            w[SS_DW * i + k] = *x as f32;
        }
    }
    w.into_iter().map(f32::to_bits).collect()
}

// ---- the land's shape round it, for the pass: the dust follows it (rod.rs's, as the Payload's) -------------------
pub(super) const SS_HF: usize = 2048;
pub(super) const SS_HN: usize = 96;
fn ss_hf_reach(dme: f64) -> f64 {
    (dme * 1.25 + 300.0).clamp(500.0, 1600.0)
}
fn ss_hf_columns(bx: i32, bz: i32, reach: f64) -> Vec<(i32, i32)> {
    let n = SS_HN as i32;
    let step = 2.0 * reach / f64::from(n - 1);
    let at = |i: i32| (-reach + step * f64::from(i)).round() as i32;
    (0..n).flat_map(|k| (0..n).map(move |i| (bx + at(i), bz + at(k)))).collect()
}
fn ss_hf_ground(heights: &[Option<f64>]) -> Vec<f64> {
    let n = SS_HN;
    let (sum, cnt) = heights.iter().flatten().fold((0.0, 0.0), |(s, c), &h| (s + h, c + 1.0));
    let guess = if cnt > 0.0 { sum / cnt } else { 0.0 };
    let raw: Vec<f64> = heights.iter().map(|h| h.unwrap_or(guess)).collect();
    let mut h = raw.clone();
    for k in 1..n - 1 {
        for i in 1..n - 1 {
            let c = k * n + i;
            let mut v = [raw[c - 1], raw[c + 1], raw[c - n], raw[c + n]];
            v.sort_by(f64::total_cmp);
            let med = 0.5 * (v[1] + v[2]);
            if raw[c] > med + 4.0 {
                h[c] = med;
            }
        }
    }
    h
}
fn ss_hf_shelter(h: &[f64], reach: f64, k0: usize, k1: usize) -> Vec<f64> {
    let n = SS_HN;
    let step = 2.0 * reach / (n - 1) as f64;
    let pos = |i: usize| -reach + step * i as f64;
    let at = |x: f64, z: f64| {
        let fi = ((x + reach) / step).clamp(0.0, (n - 1) as f64);
        let fk = ((z + reach) / step).clamp(0.0, (n - 1) as f64);
        let (i, k) = ((fi as usize).min(n - 2), (fk as usize).min(n - 2));
        let (u, v) = (fi - i as f64, fk - k as f64);
        let c = k * n + i;
        (h[c] * (1.0 - u) + h[c + 1] * u) * (1.0 - v) + (h[c + n] * (1.0 - u) + h[c + n + 1] * u) * v
    };
    (k0 * n..k1 * n)
        .map(|c| {
            let (x, z) = (pos(c % n), pos(c / n));
            let r = x.hypot(z);
            if r < 40.0 {
                return 0.0;
            }
            let (src, dst) = (10.0, h[c] + 3.0);
            let steps = ((r / step) as usize).clamp(2, 10);
            let mut over: f64 = 0.0;
            for j in 1..steps {
                let f = j as f64 / steps as f64;
                over = over.max(at(x * f, z * f) - (src + (dst - src) * f));
            }
            let s = (over / 14.0).clamp(0.0, 1.0);
            s * s * (3.0 - 2.0 * s)
        })
        .collect()
}
fn ss_hf_pack(h: &[f64], shelter: &[f64], reach: f64) -> Vec<u32> {
    let (lo, hi) = h.iter().fold((f64::MAX, f64::MIN), |(a, b), &x| (a.min(x), b.max(x)));
    let mut w = vec![(SS_HN as f32).to_bits(), (reach as f32).to_bits(), (lo as f32).to_bits(), (hi as f32).to_bits(), 0, 0, 0, 0];
    let q = |x: f64| ((x + 512.0) * 8.0).round().clamp(0.0, 65535.0) as u32;
    let b = |x: f64| (x * 255.0).round().clamp(0.0, 255.0) as u32;
    w.extend(h.iter().zip(shelter).map(|(&g, &s)| q(g) | b(s) << 16));
    w
}
#[cfg(test)]
fn ss_hf_words(heights: &[Option<f64>], reach: f64) -> Vec<u32> {
    let h = ss_hf_ground(heights);
    let s = ss_hf_shelter(&h, reach, 0, SS_HN);
    ss_hf_pack(&h, &s, reach)
}
/// The heightfield, once the world has answered (asking again a little later until it has, while there is time): its
/// ground on one stage, its shelter on three more, then sent.
fn ss_hf_step(q: &mut Plan, tag: u32, columns: Rc<Vec<(i32, i32)>>, reach: f64, gy: i32, at_t: f32) {
    if !crate::ground::ready(tag) {
        if at_t < SS_HIT {
            q.later(at_t + 0.2, move |q| ss_hf_step(q, tag, columns, reach, gy, at_t + 0.2));
        }
        return;
    }
    crate::meter::spend(600 * columns.len() as u64);
    let heights: Vec<Option<f64>> = columns
        .iter()
        .map(|&(x, z)| crate::ground::at(x, z).map(|g| f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy)))
        .collect();
    let h = Rc::new(ss_hf_ground(&heights));
    let parts = 3;
    let shelter: Rc<RefCell<Vec<f64>>> = Default::default();
    for j in 0..parts {
        let (h, shelter) = (h.clone(), shelter.clone());
        let t = at_t + 0.05 * (j + 1) as f32;
        q.later(t, move |q| {
            let (k0, k1) = (j * SS_HN / parts, (j + 1) * SS_HN / parts);
            crate::meter::spend(9_000_000);
            shelter.borrow_mut().extend(ss_hf_shelter(&h, reach, k0, k1));
            if j + 1 == parts {
                q.ev.push((t, Act::Words { index: SS_HF as u32, words: ss_hf_pack(&h, &shelter.borrow(), reach) }));
            }
        });
    }
}

// ---- the land, read from the world (rod.rs's columns) ---------------------------------------------------------------
fn at(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> Option<&Column> {
    crate::meter::spend(30);
    let (i, k) = (x - bx + SS_READ, z - bz + SS_READ);
    if i < 0 || k < 0 || i >= SS_GW || k >= SS_GW {
        return None;
    }
    land.cols.get((k * SS_GW + i) as usize).filter(|c| c.known)
}
fn read_reach(part: i32) -> f64 {
    f64::from(SS_READ) * (f64::from(part + 1) / f64::from(SS_PARTS)).sqrt()
}
fn read_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let r1 = read_reach(part).min(f64::from(SS_READ));
    let q0 = if part == 0 { -1.0 } else { read_reach(part - 1).powi(2) };
    ring_columns(bx, bz, q0, r1)
}
fn take_in(land: &mut Land, a: &crate::columns::Answer, bx: i32, bz: i32, part: usize) {
    take_in_grid(land, a, bx, bz, part, SS_READ, false);
}

// ---- the crater and what lies round it -------------------------------------------------------------------------------
/// How far out the star's edge lies at `d` radians off the nearest point's axis (0 to PI/5): on the straight line from
/// its tip (`tip` out on the axis) to its inner corner (`inner` out, PI/5 round).
fn star_edge(d: f64, tip: f64, inner: f64) -> f64 {
    let (c, s) = ((PI / 5.0).cos(), (PI / 5.0).sin());
    let (ex, ez) = (inner * c - tip, inner * s);
    // (where the ray at d meets that line: |p1 x e| / |dir x e|)
    let num = tip * ez;
    let den = d.cos() * ez - d.sin() * ex;
    num / den.max(1e-9)
}
/// The crater's shape round the target: a five-pointed star, its first point along `yaw`, its edge wandering a little.
#[derive(Clone, Copy)]
struct Shape {
    cx: f64,
    cz: f64,
    yaw: f64,
    ph: [f64; 3],
    seed: u32,
}
impl Shape {
    /// Which point bearing `a` is nearest (0 to 4), and how far off its axis (radians, 0 to PI/5).
    fn point(&self, a: f64) -> (u32, f64) {
        let rel = (a - self.yaw).rem_euclid(TAU);
        let k = (rel / (TAU / 5.0)).round();
        ((k as u32) % 5, (rel - k * TAU / 5.0).abs())
    }
    /// The edge's radius at bearing `a` (and column x, z for its wander).
    fn edge(&self, a: f64, x: i32, z: i32) -> f64 {
        let (_, d) = self.point(a);
        let w = 1.0 + 0.025 * (3.0 * a + self.ph[0]).sin() + 0.06 * (vnoise(f64::from(x), f64::from(z), 18.0, self.seed ^ 0x31) - 0.5);
        star_edge(d, SS_TIP, SS_IN) * w
    }
    /// What the blast makes of column (x, z): how far out it is, its bearing, and how far out it is in the star's own
    /// radius there (1 its edge).
    fn at(&self, x: i32, z: i32) -> (f64, f64, f64) {
        crate::meter::spend(600);
        let (dx, dz) = (f64::from(x) + 0.5 - self.cx, f64::from(z) + 0.5 - self.cz);
        let r = dx.hypot(dz);
        let a = dz.atan2(dx);
        (r, a, r / self.edge(a, x, z))
    }
    fn flat(&self, a: f64) -> f64 {
        SS_FLAT * (1.0 + 0.06 * (2.0 * a + self.ph[2]).sin() + 0.04 * (7.0 * a + self.ph[0]).sin())
    }
    fn ray(&self, a: f64) -> f64 {
        let k = SS_RAYS / PI;
        let st = vnoise(a.cos() * k, a.sin() * k, 1.0, self.seed ^ 0x73);
        ((st - 0.5) / 0.25).clamp(0.0, 1.0)
    }
}
/// How deep the crater is at r out, u of its edge: steep walls; deepest in the middle, the trenches shallower towards
/// their tips.
fn bowl(r: f64, u: f64) -> f64 {
    if u >= 1.0 {
        return 0.0;
    }
    let d = SS_DEPTH - (SS_DEPTH - SS_TIP_DEPTH) * smooth01((r - 50.0) / (SS_TIP - 50.0));
    d * (1.0 - u.powi(4)).powf(0.55)
}
/// The rim's heap past the edge (u in its radii): the earth thrown up out of it, a ridge just past the edge falling away
/// over the rest, lower along the trenches' far reaches; ragged (`n`).
fn heap(r: f64, u: f64, n: f64) -> f64 {
    if u < 1.0 || u > SS_RIM {
        return 0.0;
    }
    let ridge = 6.0 * (-(u - 1.04).powi(2) / 0.002).exp() + 2.5 * (1.0 - (u - 1.0) / (SS_RIM - 1.0));
    ridge * (0.4 + 0.9 * n) * (0.45 + 0.55 * (1.0 - smooth01((r - 70.0) / 100.0)))
}
/// A crack in the floor at (x, z): along the ridges of a noise, a block or two wide.
fn crack(x: i32, z: i32, seed: u32) -> bool {
    let n = vnoise(f64::from(x), f64::from(z), 11.0, seed ^ 0x2c);
    let m = vnoise(f64::from(x), f64::from(z), 5.0, seed ^ 0x2d);
    (n - 0.5).abs() < 0.035 + 0.02 * m
}
/// The crater's floor and walls, burnt black: blackstone, basalt, coal, deepslate, a fleck of magma.
fn scorched(x: i32, y: i32, z: i32, u: f64, seed: u32) -> &'static str {
    let n = vnoise(f64::from(x) + f64::from(y) * 0.37, f64::from(z), 4.0, seed ^ 0x51);
    let m = vnoise(f64::from(x), f64::from(z) - f64::from(y) * 0.5, 2.2, seed ^ 0x52);
    let f = mh((x.wrapping_mul(73_856_093) ^ y.wrapping_mul(19_349_663) ^ z.wrapping_mul(83_492_791)) as u32, seed, 0x54);
    if u < 0.9 {
        if f < 0.05 {
            "minecraft:magma_block"
        } else if n > 0.72 {
            "minecraft:coal_block"
        } else if m > 0.66 {
            "minecraft:smooth_basalt"
        } else if n < 0.25 {
            "minecraft:polished_blackstone"
        } else if m < 0.3 {
            "minecraft:basalt"
        } else if f < 0.12 {
            "minecraft:deepslate"
        } else {
            "minecraft:blackstone"
        }
    } else if f < 0.02 {
        "minecraft:magma_block"
    } else if n > 0.7 {
        "minecraft:basalt"
    } else if n < 0.22 {
        "minecraft:cobbled_deepslate"
    } else if m > 0.7 {
        "minecraft:coal_block"
    } else if m < 0.25 {
        "minecraft:deepslate"
    } else {
        "minecraft:blackstone"
    }
}
/// The rim's heap: the earth thrown out of the crater, scorched black on top (it reads as the star's edge from above),
/// the soil under it; `k` how far up the heap.
fn ejecta(x: i32, y: i32, z: i32, k: f64, seed: u32) -> &'static str {
    let n = vnoise(f64::from(x) * 1.3 + f64::from(y) * 0.71, f64::from(z) * 1.3, 3.0, seed ^ 0x61);
    let k = k + 0.3 * (n - 0.5);
    if k > 0.7 {
        if n > 0.6 { "minecraft:blackstone" } else if n < 0.3 { "minecraft:coal_block" } else { "minecraft:basalt" }
    } else if k > 0.35 {
        if n > 0.6 { "minecraft:tuff" } else if n < 0.3 { "minecraft:cobblestone" } else { "minecraft:coarse_dirt" }
    } else if n < 0.4 {
        "minecraft:coarse_dirt"
    } else {
        "minecraft:dirt"
    }
}
/// The black band round the star (u from 1 to about SS_BURN, its outer edge dithered): the ground burnt black.
fn burnt(x: i32, z: i32, u: f64, seed: u32) -> Option<&'static str> {
    let n = vnoise(f64::from(x), f64::from(z), 6.0, seed ^ 0x81);
    let f = mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, seed, 0x82);
    let edge = SS_BURN + 0.07 * (n - 0.5) + 0.04 * (f - 0.5);
    if u >= edge {
        return None;
    }
    Some(if f < 0.03 {
        "minecraft:magma_block"
    } else if n > 0.68 {
        "minecraft:coal_block"
    } else if n < 0.3 {
        "minecraft:basalt"
    } else if f < 0.2 {
        "minecraft:black_concrete"
    } else if f < 0.32 {
        "minecraft:polished_blackstone"
    } else {
        "minecraft:blackstone"
    })
}
/// The grass round it charred, out past the black band in the ejecta's rays: coarse dirt, gravel, tuff, burnt patches.
fn charred(s: &Shape, x: i32, z: i32, r: f64, a: f64, seed: u32) -> Option<&'static str> {
    let n = vnoise(f64::from(x), f64::from(z), 5.0, seed ^ 0x71);
    let m = vnoise(f64::from(x), f64::from(z), 2.0, seed ^ 0x72);
    let f = mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, seed, 0x74);
    let ray = s.ray(a);
    let reach = SS_IN * 2.2 + (SS_CHAR * 1.2 - SS_IN * 2.2) * ray;
    let k = (1.0 - (r / reach.max(1.0)).clamp(0.0, 1.0)).powf(0.7);
    let v = 0.6 * n + 0.4 * m;
    let w = k * (0.55 + 0.45 * ray) + 0.06;
    if v < w {
        Some(if f < 0.25 {
            "minecraft:coarse_dirt"
        } else if m > 0.62 {
            "minecraft:tuff"
        } else if n > 0.6 {
            "minecraft:blackstone"
        } else if f < 0.4 {
            "minecraft:gravel"
        } else {
            "minecraft:coarse_dirt"
        })
    } else if v < w + 0.2 && k > 0.0 {
        Some("minecraft:dirt")
    } else {
        None
    }
}
/// How hard the blast still hits column (x, z) in the band past the flattened land (1 at its inner edge, 0 at its outer).
fn band_ra(s: &Shape, (r, a): (f64, f64)) -> Option<f64> {
    let e = r - s.flat(a);
    (0.0..SS_BAND).contains(&e).then(|| 1.0 - e / SS_BAND)
}
fn band(s: &Shape, x: i32, z: i32) -> Option<f64> {
    let (r, a, _) = s.at(x, z);
    band_ra(s, (r, a))
}
fn knocked_ra(c: &Column, s: &Shape, x: i32, z: i32, ra: (f64, f64)) -> bool {
    c.trunk >= 3 && !c.fluid && band_ra(s, ra).is_some_and(|p| mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917)) as u32, s.seed, 0x91) < 0.75 * p.powf(1.1))
}
fn knocked(c: &Column, s: &Shape, x: i32, z: i32) -> bool {
    let (r, a, _) = s.at(x, z);
    knocked_ra(c, s, x, z, (r, a))
}
/// What the blast makes of column (x, z): kept (None), or its new ground's top.
fn new_ground_at(c: &Column, s: &Shape, x: i32, z: i32, (r, a, u): (f64, f64, f64)) -> Option<i32> {
    if u < 1.0 {
        Some(c.g - bowl(r, u).round() as i32)
    } else if u < SS_RIM {
        let n = vnoise(f64::from(x), f64::from(z), 8.0, s.seed ^ 0x35);
        Some(c.g + heap(r, u, n).round() as i32)
    } else if r < s.flat(a) || knocked_ra(c, s, x, z, (r, a)) {
        Some(c.g)
    } else {
        None
    }
}
fn new_ground(c: &Column, s: &Shape, x: i32, z: i32) -> Option<i32> {
    new_ground_at(c, s, x, z, s.at(x, z))
}
fn wet_near(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> bool {
    [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2), (1, 1), (1, -1), (-1, 1), (-1, -1)].iter().any(|(dx, dz)| at(land, bx, bz, x + dx, z + dz).is_some_and(|c| c.fluid))
}
/// The new floor of a crater column near (x, z), worked out from its own ground (None past the crater or not read).
fn floor_of(land: &Land, s: &Shape, bx: i32, bz: i32, x: i32, z: i32) -> Option<i32> {
    let c = at(land, bx, bz, x, z)?;
    let (r, _, u) = s.at(x, z);
    (u < 1.0 && !c.fluid).then(|| c.g - bowl(r, u).round() as i32)
}

// ---- the points ploughing out ----------------------------------------------------------------------------------------
/// How far out the points' tips are `tau` seconds after it strikes: SS_R as it lands, SS_TIP once they stop, slowing all
/// the way (the pass's ss_tip, step for step).
pub(super) fn ss_tip(tau: f64) -> f64 {
    let p = f64::from(SS_PLOUGH);
    let k = (1.0 - (-tau.clamp(0.0, p) / SS_PLOUGH_K).exp()) / (1.0 - (-p / SS_PLOUGH_K).exp());
    SS_R + (SS_TIP - SS_R) * k
}
/// When (seconds after it strikes) the points' tips reach r: 0 under the star as it lands.
fn plough_t(r: f64) -> f64 {
    if r <= SS_R {
        return 0.0;
    }
    let p = f64::from(SS_PLOUGH);
    let f = ((r - SS_R) / (SS_TIP - SS_R)).min(1.0);
    -SS_PLOUGH_K * (1.0 - f * (1.0 - (-p / SS_PLOUGH_K).exp())).ln()
}
/// Where each point's wreck lies once it stops: the white blocks of the point, broken and half buried at its trench's
/// end. For column (x, z) on point k's axis, how high the wreck stands over the trench's floor there (None off it).
fn wreck(s: &Shape, x: i32, z: i32, r: f64, a: f64) -> Option<i32> {
    let (k, d) = s.point(a);
    let _ = k;
    let along = r * d.cos();
    let across = r * d.sin();
    // (the point's shape: from its base, some 0.6 SS_R back from its tip, to its tip at SS_TIP less a little)
    let (t0, t1) = (SS_TIP - 0.62 * SS_R, SS_TIP - 3.0);
    if along < t0 || along > t1 {
        return None;
    }
    let f = (along - t0) / (t1 - t0);
    let hw = 0.36 * SS_R * (1.0 - f) * 0.62 + 1.0;
    if across > hw {
        return None;
    }
    let n = vnoise(f64::from(x), f64::from(z), 3.0, s.seed ^ 0x41);
    let h = (2.0 + 4.5 * (1.0 - across / hw).sqrt() * (1.0 - 0.6 * f) + 2.5 * (n - 0.5)).round() as i32;
    (h >= 1).then_some(h)
}
fn wreck_block(x: i32, y: i32, z: i32, seed: u32) -> &'static str {
    let n = vnoise(f64::from(x) * 1.2 + f64::from(y) * 0.6, f64::from(z) * 1.2, 2.5, seed ^ 0x43);
    let f = mh((x.wrapping_mul(73_856_093) ^ y.wrapping_mul(19_349_663) ^ z.wrapping_mul(83_492_791)) as u32, seed, 0x44);
    if (n - 0.5).abs() < 0.05 {
        "minecraft:magma_block"
    } else if f < 0.08 {
        "minecraft:shroomlight"
    } else if n > 0.66 {
        "minecraft:white_concrete"
    } else if n < 0.3 {
        "minecraft:smooth_quartz"
    } else if f < 0.4 {
        "minecraft:quartz_block"
    } else {
        "minecraft:calcite"
    }
}

// ---- the wave: the crater dug as it strikes and as the points plough it, then lined from the middle out ------------
const SS_RATE: f64 = 350_000.0;
const SS_CARVE_RATE: f64 = 900_000.0;
const SS_LINE_GAP: f64 = 0.1;
/// How far out the carve reaches: past the tips however the edge wanders.
const SS_CAVE: usize = 186;
const SS_CARVE_TO: usize = SS_CAVE + 12;
const SS_RING: f64 = 4.0;
const SS_ITEM: f64 = 250.0;
/// What the carve turns to air in a column at radius r, on the mean round the ring (the share of it the star covers):
/// the crater's depth, what stood on it, its chunk sent again.
fn ss_carve_cost(r: f64) -> f64 {
    let mut d = 0.0;
    for j in 0..12 {
        let dd = (PI / 5.0) * (f64::from(j) + 0.5) / 12.0;
        let e = star_edge(dd, SS_TIP, SS_IN);
        d += bowl(r, r / e) / 12.0;
    }
    d + 8.0
}
fn ss_cost(r: f64) -> f64 {
    if r < SS_IN * 1.3 {
        8.0
    } else if r < SS_TIP * 1.1 {
        9.0
    } else if r < SS_FLAT {
        10.0
    } else {
        6.0
    }
}
#[derive(Clone)]
struct Wave {
    carve: Rc<Vec<f32>>,
    line: Rc<Vec<f32>>,
}
impl Wave {
    fn new() -> Self {
        let shock = |r: f64| r / 343.0;
        // (the carve: the middle with the shock, each trench as its point ploughs it, or as soon after as the air goes in)
        let mut carve = vec![0.0f32; SS_CARVE_TO];
        let mut work = 0.0;
        for (r, o) in carve.iter_mut().enumerate() {
            let rf = r as f64;
            *o = SS_HIT + 0.05 + shock(rf).max(plough_t(rf)).max(work / SS_CARVE_RATE) as f32;
            work += TAU * (rf + 0.5) * ss_carve_cost(rf + 0.5);
        }
        // (the lining: from the middle out, each ring once it is dug, as the world takes it)
        let n = SS_READ as usize + 16;
        let mut line = vec![0.0f32; n + 1];
        let mut prev = SS_HIT + 0.15;
        for (r, o) in line.iter_mut().enumerate() {
            let rf = r as f64;
            let dug = if r < SS_CARVE_TO { carve[r] + SS_LINE_GAP as f32 } else { 0.0 };
            *o = prev.max(dug).max(SS_HIT + 0.05 + shock(rf) as f32);
            prev = *o + (TAU * (rf + 0.5) * ss_cost(rf + 0.5) / SS_RATE) as f32;
        }
        Wave { carve: Rc::new(carve), line: Rc::new(line) }
    }
    fn at(&self, r: f64) -> f32 {
        self.line[(r.max(0.0) as usize).min(self.line.len() - 1)]
    }
    fn carve_at(&self, r: f64) -> f32 {
        self.carve[(r.max(0.0) as usize).min(SS_CARVE_TO - 1)]
    }
    #[cfg(test)]
    fn dug(&self) -> f32 {
        self.carve[SS_CARVE_TO - 1]
    }
    fn chunk(&self, cx: f64, cz: f64, x: i32, z: i32) -> f32 {
        let d = Self::chunk_d(cx, cz, x, z);
        self.at(d - 11.4).max(self.at(d + 11.4))
    }
    fn carve_chunk(&self, cx: f64, cz: f64, x: i32, z: i32) -> f32 {
        self.carve_at(Self::chunk_d(cx, cz, x, z))
    }
    fn chunk_d(cx: f64, cz: f64, x: i32, z: i32) -> f64 {
        let (mx, mz) = (f64::from((x >> 4) * 16) + 8.0, f64::from((z >> 4) * 16) + 8.0);
        (mx - cx).hypot(mz - cz)
    }
    fn when(&self, sec: &Sector) -> f32 {
        let (t0, t1) = (self.at(sec.r0), self.at(sec.r1));
        t0 + (t1 - t0) * sec.frac as f32
    }
}
fn sectors(r0: f64, r1: f64, w: f64, item: f64, arc: f64) -> Vec<Sector> {
    let mut out = Vec::new();
    let mut r = r0;
    let mut k = 0;
    while r < r1 {
        let w = if r >= SS_TIP { 2.0 * w } else { w };
        let e = if r + 1.5 * w >= r1 { r1 } else { r + w };
        let n = (PI * (e * e - r * r) / item).ceil().max((TAU * e / arc).ceil()).max(1.0);
        let turn = TAU * (f64::from(k) * 0.618_034).fract();
        for j in 0..n as usize {
            out.push(Sector { r0: r, r1: e, a0: turn + TAU * j as f64 / n, da: if n <= 1.0 { TAU } else { TAU / n }, frac: j as f64 / n });
        }
        r = e;
        k += 1;
    }
    out
}
/// How far down the ground under column (x, z)'s new floor `top` is opened to its neighbours (rod.rs's seal_lo).
fn seal_lo(land: &Land, s: &Shape, bx: i32, bz: i32, x: i32, z: i32, top: i32) -> i32 {
    let mut lo = top;
    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let Some(n) = at(land, bx, bz, x + dx, z + dz) else { continue };
        let (rn, _, un) = s.at(x + dx, z + dz);
        let f = if un < 1.0 { n.g - bowl(rn, un).round() as i32 } else { n.g };
        lo = lo.min(f);
    }
    lo - 3
}

/// The blast's edits to column (x, z): the crater dug (into `cv`, the carve's) and lined, lava in its cracks, fires in
/// its trenches, the points' wrecks at their ends, its rim heaped, the black band and the charred land round it, the
/// land flattened, the crowns stripped (into `b`, the lining's).
#[allow(clippy::too_many_arguments)]
fn ss_blast_col(b: &mut Blocks, cv: &mut Blocks, land: &Land, s: &Shape, bx: i32, bz: i32, x: i32, z: i32, cleared: Option<&mut bool>) {
    crate::meter::spend(500);
    let Some(c) = at(land, bx, bz, x, z) else { return };
    let (r, ang, u) = s.at(x, z);
    if r > f64::from(SS_READ) || c.lava {
        return;
    }
    let wet = wet_near(land, bx, bz, x, z);
    let ng = new_ground_at(c, s, x, z, (r, ang, u));
    if let Some(k) = cleared {
        *k = !c.fluid && ng.is_some();
    }
    match ng {
        Some(top) if top < c.g => {
            // the crater: dug out first (air over its floor, the lava it bares sealed), then lined black
            cv.run(x, z, top + 1, c.top.max(c.g), "minecraft:air");
            let lo = seal_lo(land, s, bx, bz, x, z, top);
            cv.put(x, z, lo, top - 1, "minecraft:stone", Some("minecraft:lava"), false);
            let d = if u < 0.7 { 1 } else { 0 };
            for y in top - d..=top {
                b.run(x, z, y, y, scorched(x, y, z, u, s.seed));
            }
            // (lava in its cracks, only where it lies no higher than the floor round it and no water is near: it stays
            // in its crack; magma where it would run)
            if u < 0.88 && crack(x, z, s.seed) {
                let far_wet = [(4, 0), (-4, 0), (0, 4), (0, -4), (6, 0), (-6, 0), (0, 6), (0, -6), (4, 4), (-4, 4), (4, -4), (-4, -4)]
                    .iter()
                    .any(|(dx, dz)| at(land, bx, bz, x + dx, z + dz).is_some_and(|c| c.fluid));
                let safe = !wet
                    && !far_wet
                    && [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().all(|(dx, dz)| floor_of(land, s, bx, bz, x + dx, z + dz).is_some_and(|f| f >= top));
                b.run(x, z, top, top, if safe { "minecraft:lava" } else { "minecraft:magma_block" });
            } else if r > SS_R && u < 0.75 && mh((x.wrapping_mul(19_349_663) ^ z.wrapping_mul(83_492_791)) as u32, s.seed, 0x4f) < 0.0035 {
                // (a fire burning in a trench, on netherrack: nothing round it burns)
                b.run(x, z, top, top, "minecraft:netherrack");
                b.run(x, z, top + 1, top + 1, "minecraft:fire");
            }
            // (the point's wreck at its trench's end)
            if let Some(h) = wreck(s, x, z, r, ang) {
                for y in top + 1..=top + h {
                    b.run(x, z, y, y, wreck_block(x, y, z, s.seed));
                }
            }
        }
        Some(top) if top > c.g && !wet && !c.fluid => {
            // the rim: earth heaped on it, what stood there swept off
            let hk = f64::from((top - c.g).max(1));
            for y in c.g + 1..=top {
                b.run(x, z, y, y, ejecta(x, y, z, f64::from(y - c.g) / hk, s.seed));
            }
            if c.top > top {
                b.run(x, z, top + 1, c.top, "minecraft:air");
            }
            if u < 1.06 {
                let lo = seal_lo(land, s, bx, bz, x, z, c.g);
                if lo < c.g - 3 {
                    b.put(x, z, lo, c.g, "minecraft:stone", Some("minecraft:lava"), false);
                }
            }
        }
        _ if c.fluid => {}
        Some(_) => {
            // flattened: everything standing on the land swept off (a felled tree's stump left), the ground burnt black
            // round the star and charred further out
            let stump = if c.trunk > 0 { 1 + (mh((x * 31 + z * 17) as u32, s.seed, 0x81) * 2.0) as i32 } else { 0 };
            if c.top > c.g + stump {
                b.run(x, z, c.g + 1 + stump, c.top, "minecraft:air");
            }
            if let Some(m) = burnt(x, z, u, s.seed) {
                if stump == 0 {
                    b.run(x, z, c.g, c.g, m);
                }
            } else if c.ground == 1
                && let Some(m) = charred(s, x, z, r, ang, s.seed)
            {
                b.put(x, z, c.g, c.g, m, Some("minecraft:grass_block"), false);
            }
        }
        None => {
            if c.ground == 1
                && let Some(m) = charred(s, x, z, r, ang, s.seed)
            {
                b.put(x, z, c.g, c.g, m, Some("minecraft:grass_block"), false);
            }
            if c.leaves != 255
                && let Some(p) = band_ra(s, (r, ang))
                && vnoise(f64::from(x), f64::from(z), 5.0, s.seed ^ 0x93) < 0.25 + 0.75 * p
            {
                let keep = ((f64::from(c.top - c.g)) * (1.0 - (0.35 + 0.8 * p).min(1.0))).floor() as i32;
                b.put(x, z, c.g + 1 + keep, c.top, "minecraft:air", Some(LEAF_NAMES[c.leaves as usize]), false);
            }
        }
    }
}

/// One part of a ring of the blast: its edits as the waves reach it, what they leave hanging tidied the tick after,
/// and the trees standing in it felled. How much more than its estimate it cost.
fn ss_blast_part(q: &mut Plan, land: &Land, s: &Shape, used: &mut Used, cache: &mut [u8], wave: &Wave, sec: &Sector) -> f64 {
    let (bx, bz) = (q.bx, q.bz);
    let (cells, [x0, z0, x1, z1]) = sec.cells(s.cx, s.cz);
    let t = wave.when(sec);
    let (mut b, mut cv) = (Blocks::default(), Blocks::default());
    let gw = (x1 - x0 + 1) as usize;
    let mut grid = vec![false; gw * (z1 - z0 + 1) as usize];
    for &(x, z) in &cells {
        ss_blast_col(&mut b, &mut cv, land, s, bx, bz, x, z, grid.get_mut((z - z0) as usize * gw + (x - x0) as usize));
    }
    for (tc, b) in cv.split_by(|x, z| wave.carve_chunk(s.cx, s.cz, x, z)) {
        q.ev.push((tc, Act::Blocks(Box::new(b))));
    }
    let when = |x: i32, z: i32| wave.chunk(s.cx, s.cz, x, z).max(t);
    for (tc, b) in b.split_by(when) {
        q.ev.push((tc, Act::Blocks(Box::new(b))));
    }
    let inner = sec.r1 + f64::from(TIDY_BORDER) + 1.0 < 0.86 * SS_FLAT;
    let need = !inner || grid.iter().zip(0..).any(|(&k, i)| !k && sec.holds(f64::from(x0 + i % gw as i32) + 0.5 - s.cx, f64::from(z0 + i / gw as i32) + 0.5 - s.cz)) || {
        let b = TIDY_BORDER;
        (z0 - b..=z1 + b).any(|z| (x0 - b..=x1 + b).any(|x| at(land, bx, bz, x, z).is_none_or(|c| c.fluid)))
    };
    for &(x, z) in &cells {
        let i = ((z - bz + SS_READ) * SS_GW + x - bx + SS_READ) as usize;
        if let Some(k) = cache.get_mut(i) {
            *k = if grid[(z - z0) as usize * gw + (x - x0) as usize] { 1 } else { 2 };
        }
    }
    let tb = if !need {
        Blocks::default()
    } else {
        tidy(x0, z0, x1, z1, 40, -1, |x, z| {
            let (i, k) = (x - bx + SS_READ, z - bz + SS_READ);
            if i < 0 || k < 0 || i >= SS_GW || k >= SS_GW {
                return Col::Kept;
            }
            let ix = (k * SS_GW + i) as usize;
            if cache[ix] == 0 {
                let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
                let cleared = match at(land, bx, bz, x, z) {
                    Some(c) if c.fluid => false,
                    Some(_) if dx * dx + dz * dz < (0.86 * SS_FLAT).powi(2) => true,
                    Some(c) if dx * dx + dz * dz > (1.14 * SS_FLAT).powi(2) && c.trunk < 3 => false,
                    Some(c) => new_ground(c, s, x, z).is_some(),
                    None => false,
                };
                cache[ix] = if cleared { 3 } else { 4 };
            }
            if cache[ix] == 1 || cache[ix] == 3 { Col::Cleared } else { Col::Kept }
        })
    };
    let mut tb = tb;
    tb.runs.retain_mut(|r| {
        let (i, k) = (r.x - bx + SS_READ, r.z - bz + SS_READ);
        if i < 0 || k < 0 || i >= SS_GW || k >= SS_GW || cache[(k * SS_GW + i) as usize] > 2 {
            return false;
        }
        if r.surface.is_none() || r.y != 2 {
            return true;
        }
        match at(land, bx, bz, r.x, r.z) {
            Some(c) if c.trunk == 0 && !c.fluid => {
                let h = c.top - c.g - 2;
                r.height = r.height.min(h.max(0) as u32);
                h > 0
            }
            _ => true,
        }
    });
    for (tc, b) in tb.split_by(when) {
        q.ev.push((tc, Act::Blocks(Box::new(b))));
    }
    let mut due = Due::default();
    ss_fell(&mut due, land, s, used, wave, bx, bz, &cells);
    due.push(q);
    let tall: i32 = cells.iter().filter_map(|&(x, z)| at(land, bx, bz, x, z)).filter(|c| !c.fluid).map(|c| (c.top - c.g).max(0)).sum();
    1.0 + f64::from(tall) / cells.len().max(1) as f64 / 35.0
}

/// The trees standing on `cells` felled, lying on the land pointing away from the blast (rod.rs's rd_fell).
#[allow(clippy::too_many_arguments)]
fn ss_fell(due: &mut Due, land: &Land, s: &Shape, used: &mut Used, wave: &Wave, bx: i32, bz: i32, cells: &[(i32, i32)]) {
    let lie = |x: i32, z: i32, gy: i32| -> Option<i32> {
        let c = at(land, bx, bz, x, z)?;
        let (r, a, u) = s.at(x, z);
        if c.fluid || u < SS_BURN || (c.g - gy).abs() > 1 || wet_near(land, bx, bz, x, z) {
            return None;
        }
        if r > s.flat(a) - 1.0 && (band(s, x, z).is_none() || c.trunk > 0 || c.top > c.g + 1) {
            return None;
        }
        Some(c.g)
    };
    for &(x, z) in cells {
        crate::meter::spend(40);
        let Some(c) = at(land, bx, bz, x, z) else { continue };
        if c.trunk < 3 || c.fluid {
            continue;
        }
        let (r, a, u) = s.at(x, z);
        if u < SS_BURN || (r > s.flat(a) - 1.0 && !knocked(c, s, x, z)) {
            continue;
        }
        let (dx, dz) = (a.cos(), a.sin());
        let (sx, sz, log) = if dx.abs() > dz.abs() { (dx.signum() as i32, 0, LOG_X[c.wood as usize]) } else { (0, dz.signum() as i32, LOG_Z[c.wood as usize]) };
        let h = |kk: u32| mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, s.seed, kk);
        let want = (i32::from(c.trunk) - 1).clamp(2, 4 + (h(1) * 4.0) as i32);
        let mut last = None;
        let mut gy = c.g;
        let mut put: Vec<(i32, i32, i32, &'static str)> = Vec::new();
        for n in 1..=want {
            let (lx, lz) = (x + sx * n, z + sz * n);
            if used.contains(&(lx, lz)) {
                break;
            }
            let Some(g2) = lie(lx, lz, gy) else { break };
            put.push((lx, lz, g2 + 1, log));
            used.insert((lx, lz));
            gy = g2;
            last = Some((lx, lz));
        }
        if let (Some((lx, lz)), true) = (last, r > 150.0 && c.leaves != 255) {
            let leaves = LEAVES[c.leaves as usize];
            for (ox, oz) in [(sx, sz), (sz, sx), (-sz, -sx), (sx + sz, sz + sx), (sx - sz, sz - sx)] {
                let (fx, fz) = (lx + ox, lz + oz);
                if used.contains(&(fx, fz)) {
                    continue;
                }
                if let Some(g2) = lie(fx, fz, gy) {
                    put.push((fx, fz, g2 + 1, leaves));
                    used.insert((fx, fz));
                }
            }
        }
        if put.is_empty() {
            continue;
        }
        let far = put.iter().map(|&(px, pz, _, _)| (f64::from(px) + 0.5 - s.cx).hypot(f64::from(pz) + 0.5 - s.cz)).fold(0.0, f64::max);
        let b = due.get(put.iter().map(|&(px, pz, _, _)| wave.chunk(s.cx, s.cz, px, pz)).fold(wave.at(far + SS_RING + 1.0), f32::max) + 0.05);
        for (px, pz, y, m) in put {
            b.run(px, pz, y, y, m);
        }
    }
}

/// The rubble: blackened earth and white pieces of the star thrown out, more near it, in rays, landing just after the
/// wave has swept where they land.
fn ss_rubble(q: &mut Plan, land: &Land, s: &Shape, used: &mut Used, wave: &Wave) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7e57);
    let mut due = Due::default();
    let lands = |r: f64, k: f64| wave.at(r + 2.0 * SS_RING) + (0.2 + 0.3 * k) as f32;
    const RUBBLE: [&str; 12] = [
        "minecraft:blackstone",
        "minecraft:blackstone",
        "minecraft:basalt",
        "minecraft:coal_block",
        "minecraft:cobblestone",
        "minecraft:cobbled_deepslate",
        "minecraft:coarse_dirt",
        "minecraft:tuff",
        "minecraft:calcite",
        "minecraft:quartz_block",
        "minecraft:white_concrete",
        "minecraft:magma_block",
    ];
    crate::meter::spend(2_400 * 1100);
    for _ in 0..2200 {
        let r = SS_TIP * 0.6 + (SS_RUBBLE - SS_TIP * 0.6) * rng.next().powf(1.3);
        let a = rng.uniform(0.0, TAU);
        let ray = s.ray(a);
        let reach = SS_TIP + (SS_RUBBLE - SS_TIP) * ray;
        let (x, z) = ((s.cx + a.cos() * r).floor() as i32, (s.cz + a.sin() * r).floor() as i32);
        let Some(c) = at(land, bx, bz, x, z) else { continue };
        let (_, _, u) = s.at(x, z);
        if u < SS_RIM || (r > SS_TIP * 1.1 && (r > reach || rng.next() > 0.12 + 0.88 * ray)) {
            continue;
        }
        if c.fluid || used.contains(&(x, z)) || wet_near(land, bx, bz, x, z) {
            continue;
        }
        let y = match new_ground(c, s, x, z) {
            Some(top) => top + 1,
            None if c.top <= c.g + 1 && c.trunk == 0 => c.g + 1,
            None => continue,
        };
        let m = *rng.pick(&RUBBLE);
        let t = lands(r, rng.next());
        due.get(t).run(x, z, y, y, m);
        used.insert((x, z));
        if rng.next() < 0.25 && r < 200.0 {
            let (x2, z2) = (x + rng.int(-1, 1), z + rng.int(-1, 1));
            if !used.contains(&(x2, z2))
                && let Some(c2) = at(land, bx, bz, x2, z2)
                && !c2.fluid
                && let Some(t2) = new_ground(c2, s, x2, z2)
                && t2 + 1 == y
            {
                due.get(t).run(x2, z2, y, y, m);
                used.insert((x2, z2));
            }
        }
    }
    let woods = land.woods;
    let wood = (0..9).max_by_key(|&i| woods[i]).unwrap_or(0);
    if woods[wood] > 0 {
        for n in 0..1200 {
            let r = SS_TIP * 1.1 + (SS_FLAT * 1.1 + SS_BAND - SS_TIP * 1.1) * rng.next().powf(0.8);
            let a = rng.uniform(0.0, TAU);
            let (x, z) = ((s.cx + a.cos() * r).floor() as i32, (s.cz + a.sin() * r).floor() as i32);
            let Some(c) = at(land, bx, bz, x, z) else { continue };
            if c.fluid || used.contains(&(x, z)) || wet_near(land, bx, bz, x, z) {
                continue;
            }
            let (_, _, u) = s.at(x, z);
            if u < SS_BURN {
                continue;
            }
            let y = match new_ground(c, s, x, z) {
                Some(top) if top == c.g => top + 1,
                None if c.top <= c.g + 1 && c.trunk == 0 => c.g + 1,
                _ => continue,
            };
            let m = if n % 6 == 0 { if rng.next() < 0.5 { LOG_X[wood] } else { LOG_Z[wood] } } else { LEAVES[wood] };
            due.get(lands(r, rng.next())).run(x, z, y, y, m);
            used.insert((x, z));
        }
    }
    due.push(q);
}

/// Real blocks thrown out of the crater as it strikes: the ground that was there and white pieces of the star, flung
/// out and up over the first second and a half (some land as blocks, the rest break up where they land).
fn ss_thrown(q: &mut Plan, land: &Land, s: &Shape, part: u64) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7410 ^ (part << 20));
    let woods = land.woods;
    let wood = (0..9).max_by_key(|&i| woods[i]).filter(|&i| woods[i] > 0);
    let mut n = 0;
    crate::meter::spend(SS_THROWN as u64 * 3 / 2 * 3_000);
    for _ in 0..SS_THROWN * 3 / 2 {
        if n >= SS_THROWN / 2 {
            break;
        }
        let r = 4.0 + (SS_IN * 0.9 - 4.0) * rng.next().sqrt();
        let a = rng.uniform(0.0, TAU);
        let (x, z) = (s.cx + a.cos() * r, s.cz + a.sin() * r);
        let (ix, iz) = (x.floor() as i32, z.floor() as i32);
        let Some(c) = at(land, bx, bz, ix, iz) else { continue };
        if !c.known || c.fluid || wet_near(land, bx, bz, ix, iz) {
            continue;
        }
        let deep = rng.next();
        let blk = match (c.ground, deep) {
            (_, d) if d < 0.08 && wood.is_some() => LOG_Y[wood.unwrap_or(0)],
            (1, d) if d < 0.3 => "minecraft:grass_block",
            (1 | 2, d) if d < 0.5 => "minecraft:dirt",
            (_, d) if d < 0.6 => "minecraft:coarse_dirt",
            (_, d) if d < 0.7 => "minecraft:calcite",
            (_, d) if d < 0.78 => "minecraft:white_concrete",
            (_, d) if d < 0.86 => "minecraft:blackstone",
            (_, d) if d < 0.93 => "minecraft:stone",
            (_, d) if d < 0.97 => "minecraft:magma_block",
            _ => "minecraft:cobblestone",
        };
        let ang = if r > 1.0 { a } else { rng.uniform(0.0, TAU) };
        let h = 0.6 + 2.0 * rng.next().powf(1.2);
        let vy = 1.6 + 2.4 * rng.next();
        let (vx, vz) = (ang.cos() * h, ang.sin() * h);
        let y = f64::from(c.g) + 2.0 + 3.0 * rng.next();
        let t = SS_HIT + 0.1 + (r / 343.0) as f32 + 1.25 * rng.next().powf(1.3) as f32;
        let keep = if rng.next() < 0.45 { "" } else { ",CancelDrop:1b" };
        q.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
        n += 1;
    }
}

// ---- the land's work: one chain of stages, a tick each (rod.rs's) ----------------------------------------------------
const SS_BUDGET: f64 = 750.0;
const SS_UNIT: f64 = 15_000.0;
const SS_LAND_BY: f32 = SS_HIT + 30.0;
const SS_PATIENCE: f32 = 4.0;
enum Job {
    Thrown(u64),
    Rubble,
    Blast(Sector),
}
struct Work {
    land: Land,
    s: Shape,
    wave: Wave,
    used: Used,
    made: Vec<u8>,
    gy: i32,
    tags: Vec<u32>,
    asked: usize,
    taken: usize,
    retry: Option<(u32, usize, Vec<(i32, i32)>, f32)>,
    rnext: usize,
    rat: f32,
    left: usize,
    came: f32,
    jobs: std::collections::VecDeque<Job>,
}
impl Work {
    fn new(s: Shape, gy: i32) -> Self {
        let mut jobs = std::collections::VecDeque::new();
        jobs.push_back(Job::Thrown(0));
        jobs.push_back(Job::Thrown(1));
        let mut rubble = false;
        for sec in sectors(0.0, f64::from(SS_READ) + 1.0, SS_RING, SS_ITEM, 150.0) {
            if !rubble && sec.r0 >= SS_TIP * SS_RIM {
                jobs.push_back(Job::Rubble);
                rubble = true;
            }
            jobs.push_back(Job::Blast(sec));
        }
        Work {
            land: Land { cols: vec![Column::default(); (SS_GW * SS_GW) as usize], missing: vec![Vec::new(); SS_PARTS as usize], woods: [0; 9], done: false },
            s,
            wave: Wave::new(),
            used: Default::default(),
            made: vec![0; (SS_GW * SS_GW) as usize],
            gy,
            tags: (0..SS_PARTS).map(|_| crate::columns::new_tag()).collect(),
            asked: 0,
            taken: 0,
            retry: None,
            rnext: 0,
            rat: 0.0,
            left: usize::MAX,
            came: 0.0,
            jobs,
        }
    }
    fn ready(&self) -> f64 {
        if self.land.done {
            return f64::INFINITY;
        }
        crate::meter::spend(400);
        let r = if self.taken == 0 { 0.0 } else { read_reach(self.taken as i32 - 1) };
        let mut first = self.land.missing.iter().position(|m| !m.is_empty()).unwrap_or(usize::MAX);
        if let Some((_, part, _, _)) = &self.retry {
            first = first.min(*part);
        }
        if first == usize::MAX {
            return r;
        }
        let inner = if first == 0 { 0.0 } else { read_reach(first as i32 - 1) };
        r.min(inner - 1.0)
    }
    fn unloaded(&self) -> usize {
        self.land.missing.iter().map(Vec::len).sum::<usize>() + self.retry.as_ref().map_or(0, |r| r.2.len())
    }
    fn can(&self, j: &Job) -> (bool, bool) {
        match j {
            Job::Thrown(_) => (self.ready() >= SS_IN * 1.3, false),
            Job::Rubble => (self.land.done, false),
            Job::Blast(sec) => (self.ready() >= sec.r1 + 12.0, true),
        }
    }
    fn cost(j: &Job) -> f64 {
        match j {
            Job::Thrown(_) => 900.0,
            Job::Rubble => SS_BUDGET,
            Job::Blast(s) => {
                let a = s.da.min(TAU) / 2.0 * (s.r1 * s.r1 - s.r0 * s.r0);
                let k = if s.r0 < SS_TIP * SS_RIM {
                    0.9
                } else if s.r1 + 4.0 < 0.86 * SS_FLAT {
                    0.65
                } else {
                    0.75
                };
                a * k
            }
        }
    }
}

/// One stage of the land's work (rod.rs's rd_work).
fn ss_work(q: &mut Plan, w: Rc<RefCell<Work>>, now: f32) {
    let more = {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        let (bx, bz) = (q.bx, q.bz);
        let mut spent = 0.0;
        if wk.asked < wk.tags.len() {
            for _ in 0..2.min(wk.tags.len() - wk.asked) {
                let part = wk.asked;
                q.ev.push((now, Act::Read { tag: wk.tags[part], columns: read_columns(bx, bz, part as i32), below: SS_BELOW, above: SS_ABOVE }));
                wk.asked += 1;
                spent += 75.0;
            }
        }
        for _ in 0..4 {
            if wk.taken < wk.asked
                && !crate::meter::full()
                && let Some(a) = crate::columns::take(wk.tags[wk.taken])
            {
                let part = wk.taken;
                take_in(&mut wk.land, &a, bx, bz, part);
                if part == 0
                    && let Some(c) = wk.land.cols.get((SS_READ * SS_GW + SS_READ) as usize).filter(|c| c.known)
                {
                    wk.gy = if c.fluid { c.wtop } else { c.g } + 1;
                }
                wk.taken += 1;
                spent += 300.0;
            }
        }
        if wk.taken == wk.tags.len() && !wk.land.done {
            if let Some((tag, part, _, since)) = &wk.retry {
                let (tag, part, since) = (*tag, *part, *since);
                if let Some(a) = crate::columns::take(tag) {
                    take_in(&mut wk.land, &a, bx, bz, part);
                    wk.retry = None;
                    spent += 300.0;
                } else if now > since + 3.0
                    && let Some((_, part, cols, _)) = wk.retry.take()
                {
                    wk.land.missing[part] = cols;
                }
            }
            let left = wk.unloaded();
            if left < wk.left && wk.left != usize::MAX {
                wk.came = now;
            }
            wk.left = left;
            let stalled = now - wk.came > SS_PATIENCE && wk.ready() >= SS_TIP * 1.1;
            if left == 0 {
                wk.land.done = true;
            } else if now > SS_LAND_BY || stalled {
                crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("sixstars: {left} columns of the land never loaded; the terrain left out there"));
                wk.land.done = true;
            } else if wk.retry.is_none() && now >= wk.rat {
                let n = wk.land.missing.len();
                if let Some(part) = (0..n).map(|j| (wk.rnext + j) % n).find(|&j| !wk.land.missing[j].is_empty()) {
                    let cols = std::mem::take(&mut wk.land.missing[part]);
                    crate::meter::spend(40 * cols.len() as u64);
                    let tag = crate::columns::new_tag();
                    q.ev.push((now, Act::Read { tag, columns: cols.clone(), below: SS_BELOW, above: SS_ABOVE }));
                    wk.retry = Some((tag, part, cols, now));
                    wk.rnext = part + 1;
                    wk.rat = now + 0.1;
                    spent += 150.0;
                }
            }
        }
        crate::trace("ss land taken");
        loop {
            let mut pick = None;
            for (i, j) in wk.jobs.iter().enumerate() {
                crate::meter::spend(300);
                let (can, blocks) = wk.can(j);
                if can {
                    pick = Some(i);
                    break;
                }
                if blocks {
                    break;
                }
            }
            let Some(i) = pick else { break };
            let c = Work::cost(&wk.jobs[i]);
            // A job counts about twice its charge on the meter (its loops on top): one that won't fit under the soft
            // line waits, so the fourth blast part of a tick never takes it to nearly half the tick's fuel.
            if spent > 0.0 && (spent + c > SS_BUDGET || !crate::meter::room((2.0 * c * SS_UNIT) as u64)) {
                break;
            }
            spent += c;
            crate::meter::spend((c * SS_UNIT) as u64);
            let job = wk.jobs.remove(i).unwrap_or(Job::Rubble);
            match job {
                Job::Thrown(part) => ss_thrown(q, &wk.land, &wk.s, part),
                Job::Rubble => {
                    let wave = wk.wave.clone();
                    ss_rubble(q, &wk.land, &wk.s, &mut wk.used, &wave);
                }
                Job::Blast(sec) => {
                    let wave = wk.wave.clone();
                    let k = ss_blast_part(q, &wk.land, &wk.s, &mut wk.used, &mut wk.made, &wave, &sec);
                    spent += c * (k - 1.0);
                }
            }
            crate::trace("ss job");
        }
        !wk.jobs.is_empty()
    };
    if more && now < SS_LAND_BY + 25.0 {
        q.later(now + 0.05, move |q| ss_work(q, w, now + 0.05));
    }
}

/// The blast's jolt reaching the player at `t`, `fo` as hard (rod.rs's rd_jolt, a little longer).
fn ss_jolt(p: &mut Plan, t: f32, fo: f32) {
    p.shake(t, fo, 2.0);
    for n in 0..12 {
        let u = n as f32 / 12.0;
        p.shake(t + 0.05 + 0.09 * n as f32, (1.0 - 0.4 * u) * fo, 0.2);
    }
    p.shake(t + 0.3, 0.7 * fo, 6.5);
    let mut ts = t + 1.2;
    while ts < t + 7.0 {
        let u = (ts - t - 1.2) / 5.8;
        p.shake(ts, (0.6 * (1.0 - u).powf(1.4) + 0.08) * fo, 0.28);
        ts += 0.13 + 0.1 * u;
    }
}

/// How much of the blast is heard through each tier, `dist` blocks off: the near alone out to 500 (it carries), near to
/// mid over 500 to 800, mid to far over 800 to 1,400.
fn ss_tiers(dist: f64) -> [f32; 3] {
    let s = |x: f64| {
        let x = x.clamp(0.0, 1.0);
        (x * x * (3.0 - 2.0 * x)) as f32
    };
    let m = s((dist - 500.0) / 300.0);
    let f = s((dist - 800.0) / 600.0);
    [1.0 - m, m * (1.0 - f), f]
}
/// One of its sounds at `v` (over 1: more voices of the same file, as the Convergence plays its loudest).
fn ss_play(p: &mut Plan, t: f32, role: &str, v: f32) {
    let mut left = v;
    while left > 0.004 {
        p.csound(t, role, 10.0 * left.min(1.0), 1.0);
        left -= 1.0;
    }
}
/// How fast the shock goes through the ground to the player (blocks a second): through rock, so the ground's blow
/// leaves no hush between the fall's end and the air's blast.
const SS_ROCK_V: f64 = 5000.0;
/// The star tearing out of the screen: its file starts this long before SS_PEEL, so its pop lands on it (a glass pop,
/// the air pulled away as it flies, the glass ringing on after).
const SS_POP_LEAD: f32 = 0.04;
/// How loud it plays: a subtle pop, under the flight that follows it (about 7 dB under its file).
const SS_POP_VOL: f32 = 0.45;
/// When the star's flight sound starts (just after its pop; it hands over to the fall's).
const SS_FLIGHT: f32 = 8.25;
/// When the far sirens start: one more far-off car comes in with each star, six by the sixth, fading into the peel.
const SS_SIRENS: f32 = 1.2;

/// The sounds (tools/sounds_sixstars.py builds them; its docstring the timeline): the climb's bed and each star's beat
/// in the player's ears (the stars are on their screen), the peel and the fall from the sky over them (the fall's file
/// ends on the impact), the ground's blow ahead of the air's, the blast as it reaches them in its tiers by distance,
/// the points ploughing late by the distance, the aftermath.
fn ss_sounds(p: &mut Plan, late: f32, dist: f64) {
    ss_play(p, 0.0, "climb", 1.0);
    for (k, &t) in SS_STARS.iter().enumerate() {
        ss_play(p, t, &format!("star{}", k + 1), 1.0);
    }
    // (police sirens far off under the climb, rising with the stars, gone into the peel)
    ss_play(p, SS_SIRENS, "sirens", 1.0);
    // (the star tearing out of the screen, its pop on SS_PEEL)
    ss_play(p, SS_PEEL - SS_POP_LEAD, "peel", SS_POP_VOL);
    // (and as it flies into the sky and hangs there, the air rushing after it and a warm swell growing under it, into
    // the fall: no hush between the pop and the fall)
    ss_play(p, SS_FLIGHT, "flight", 1.0);
    ss_play(p, SS_STATION, "fall", 1.2);
    // (the ground's file has its blow 0.03 s in, the blasts' fronts 0.02 s in)
    let tg = SS_HIT + (dist / SS_ROCK_V) as f32 - 0.03;
    ss_play(p, tg, "ground", (1.0 / (1.0 + dist / 1500.0)).clamp(0.4, 1.0) as f32);
    let arrive = SS_HIT + late;
    let w = ss_tiers(dist);
    for (k, tier) in ["blast_near", "blast_mid", "blast_far"].iter().enumerate() {
        if w[k] > 0.01 {
            ss_play(p, arrive - 0.02, tier, 1.5 * w[k]);
        }
    }
    ss_play(p, arrive, "plough", 0.7 * (1.0 / (1.0 + dist / 900.0)).clamp(0.35, 1.0) as f32);
    ss_play(p, SS_HIT + 1.0 + late, "after", 1.0);
}

/// The Six Stars: the stars climb, the sixth leaves the screen, falls and strikes.
pub(super) fn sixstars_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let rel = [me[0] - cx, me[1] - gy, me[2] - cz];
    let geo = SsGeo::new(shader_seed, rel);
    let (late, dist) = sound_from([cx, gy, cz], me);
    let fo = falloff(dist * 0.4).max(0.45);

    // the pass's table, on the tick after it fires
    {
        let s = shader_seed;
        p.later(0.05, move |q| {
            q.ev.push((0.05, Act::Table(ss_table(s, rel))));
            q.ev.push((0.05, Act::Words { index: SS_DB as u32, words: ss_debris_words(s as u32) }));
        });
    }
    // (and the land's shape round it, asked as it starts, the heightfield on a later tick)
    {
        let reach = ss_hf_reach(rel[0].hypot(rel[2]));
        let columns = Rc::new(ss_hf_columns(bx, bz, reach));
        let tag = crate::ground::new_tag();
        let cols = columns.clone();
        p.later(0.1, move |q| q.ev.push((0.1, Act::Survey { tag, columns: cols.to_vec() })));
        p.later(0.4, move |q| ss_hf_step(q, tag, columns, reach, by + 1, 0.4));
    }

    ss_sounds(&mut p, late, dist);
    // ---- the climb: each star's beat felt; the peel's tug; the fall's rumble building -------------------------------
    for (k, &t) in SS_STARS.iter().enumerate() {
        p.shake(t, 0.12 + 0.035 * k as f32, 0.45);
    }
    // (the star snapping out of its slot: a short, sharp kick on the whump)
    p.shake(SS_PEEL, 0.42, 0.32);
    let mut ts = SS_DROP + 1.5;
    while ts < SS_HIT - 0.1 {
        let u = (ts - SS_DROP) / (SS_HIT - SS_DROP);
        p.shake(ts, 0.05 + 0.25 * u * u, 0.35);
        ts += 0.3;
    }
    // ---- the impact: through the ground first, then the air: the jolt and the push as the front passes -------------
    let tg = SS_HIT + (dist / SS_ROCK_V) as f32;
    if late > tg - SS_HIT + 0.08 {
        p.shake(tg, 0.45 * (2.0 / (1.0 + dist / 400.0)).clamp(0.35, 1.0) as f32, 0.5);
    }
    let arrive = SS_HIT + late;
    ss_jolt(&mut p, arrive, (2.0 / (1.0 + dist / 450.0)).clamp(0.3, 1.0) as f32);
    p.ev.push((arrive, Act::Shove { from: [cx, gy, cz], out: SS_KNOCK_OUT, up: SS_KNOCK_UP, reach: SS_KNOCK_REACH }));
    let mut ts = arrive + 7.0;
    while ts < arrive + 14.0 {
        let s = p.rng.uniform(0.04, 0.1) as f32 * fo;
        let d = p.rng.uniform(0.4, 0.9) as f32;
        p.shake(ts, s, d);
        ts += p.rng.uniform(0.5, 1.2) as f32;
    }
    for t in [SS_HIT + 0.1, SS_HIT + 1.0, SS_HIT + 3.0, SS_HIT + 6.0] {
        p.at(t, format!("execute positioned {cx:.1} {gy} {cz:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{SS_KILL}]"));
    }
    p.at(SS_HIT + 0.05, format!("particle minecraft:explosion_emitter {cx:.1} {:.1} {cz:.1} 20 5 20 0 16 force", gy + 3.0));
    p.at(SS_HIT + 0.1, format!(r#"particle minecraft:block{{block_state:"minecraft:blackstone"}} {cx:.1} {:.1} {cz:.1} 40 10 40 1.2 900 force"#, gy + 4.0));
    for i in 0..10 {
        let t = SS_HIT + 1.0 + i as f32 * 1.6;
        p.at(t, format!("particle minecraft:campfire_signal_smoke {cx:.1} {:.1} {cz:.1} 40 3 40 0.03 60 force", gy + 1.0));
    }

    if terrain {
        let point = [cx, gy, cz];
        let load = pk_load_rows(point, 0.0, f64::from(SS_READ) + 4.0);
        for [x0, z0, x1, z1] in &load {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for [x0, z0, x1, z1] in &load {
            p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        let shape = Shape { cx, cz, yaw: geo.yaw, ph: [TAU * mh(1, geo.seed, 0xc1), TAU * mh(2, geo.seed, 0xc1), TAU * mh(3, geo.seed, 0xc1)], seed: geo.seed };
        p.later(0.15, move |q| {
            crate::meter::spend(9_000_000);
            let work = Rc::new(RefCell::new(Work::new(shape, by + 1)));
            q.later(0.2, move |q| ss_work(q, work, 0.2));
        });
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

#[cfg(test)]
mod table {
    /// `CB_SEED=37 CB_OUT=path PL_ME=x,y,z cargo test --release ss_write_table -- --ignored`: the table the pass reads,
    /// for tools/preview.py (a line `index value` a word), the target's ground at the preview's (0.5 65 0.5).
    #[test]
    #[ignore]
    fn ss_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let me: Vec<f64> = std::env::var("PL_ME").map_or(vec![0.0, 70.0, 300.0], |v| v.split(',').map(|x| x.parse().unwrap()).collect());
        let rel = [me[0] - 0.5, me[1] - 65.0, me[2] - 0.5];
        let mut w = super::ss_table(seed, rel);
        let hills: f64 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap());
        let reach = super::ss_hf_reach(rel[0].hypot(rel[2]));
        let f = |x: f64, z: f64| hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin());
        let f0 = if std::env::var("PL_FLUSH").is_ok_and(|v| v == "1") { f(0.5, 0.5) } else { 0.0 };
        let heights: Vec<Option<f64>> = super::ss_hf_columns(0, 0, reach).iter().map(|&(x, z)| Some(f(f64::from(x) + 0.5, f64::from(z) + 0.5) - f0)).collect();
        let hf = super::ss_hf_words(&heights, reach);
        w.resize(super::SS_HF + hf.len(), 0);
        w[super::SS_HF..].copy_from_slice(&hf);
        let db = super::ss_debris_words(seed as u32);
        w.resize(super::SS_DB + db.len(), 0);
        w[super::SS_DB..].copy_from_slice(&db);
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    fn ground_h(x: i32, z: i32) -> i32 {
        (64.0 + 3.0 * (f64::from(x) * 0.05).sin() * (f64::from(z) * 0.04).cos()).round() as i32
    }
    fn tree(x: i32, z: i32) -> bool {
        mh((x.wrapping_mul(73) ^ z.wrapping_mul(179)) as u32, 5, 0x99) > 0.985
    }
    thread_local! {
        /// 0 a forest on rolling land; 1 the same with a lake east of the target (x 120 to 160); 10 flat open land.
        static LAND: std::cell::Cell<u8> = const { std::cell::Cell::new(0) };
    }
    fn water_at(x: i32, z: i32) -> Option<(i32, i32)> {
        match LAND.with(|l| l.get()) {
            1 => ((120..160).contains(&x) && (-40..40).contains(&z)).then_some((55, 62)),
            _ => None,
        }
    }
    fn column(x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let land = LAND.with(|l| l.get());
        let wet = water_at(x, z);
        let g = if land == 10 { 64 } else { wet.map_or(ground_h(x, z), |w| w.0) };
        let t = wet.is_none() && tree(x, z) && land != 10;
        let block = |y: i32| -> &'static str {
            if let Some((bed, top)) = wet {
                return if y < bed { "minecraft:dirt" } else if y <= top { "minecraft:water" } else { "minecraft:air" };
            }
            if y < g - 3 {
                "minecraft:stone"
            } else if y < g {
                "minecraft:dirt"
            } else if y == g {
                "minecraft:grass_block"
            } else if t && y <= g + 6 {
                "minecraft:oak_log"
            } else if t && y <= g + 8 && y >= g + 4 {
                "minecraft:oak_leaves"
            } else {
                "minecraft:air"
            }
        };
        let top = if let Some((_, w)) = wet { w } else if t { g + 9 } else { g + 2 };
        let (below, above) = (below as i32, above as i32);
        Some((top, (top - below..top + above).map(block).collect()))
    }
    fn target() -> Target {
        Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] }
    }

    #[test]
    fn ss_star_edge_is_a_star() {
        // (its tips out at SS_TIP, its inner corners in at SS_IN, straight between)
        assert!((star_edge(0.0, SS_TIP, SS_IN) - SS_TIP).abs() < 1e-6);
        assert!((star_edge(PI / 5.0, SS_TIP, SS_IN) - SS_IN).abs() < 1e-6);
        let mid = star_edge(PI / 10.0, SS_TIP, SS_IN);
        assert!(mid > SS_IN && mid < SS_TIP);
        // (the points plough out, slowing, to SS_TIP)
        assert!((ss_tip(0.0) - SS_R).abs() < 1e-9 && (ss_tip(f64::from(SS_PLOUGH)) - SS_TIP).abs() < 1e-9);
        assert!(ss_tip(0.5) - ss_tip(0.0) > ss_tip(2.4) - ss_tip(1.9));
        for r in [80.0, 120.0, 165.0] {
            assert!((ss_tip(plough_t(r)) - r).abs() < 1e-6, "{r}");
        }
    }

    #[test]
    fn ss_falls_from_where_it_hangs_onto_the_target() {
        for seed in [3.0, 37.0, 512.0] {
            let me = [0.0, 5.0, 300.0];
            let g = SsGeo::new(seed, me);
            let p0 = g.pos(f64::from(SS_STATION));
            assert!((p0[1] - SS_H).abs() < 1e-6);
            // (beyond the target from the player)
            assert!(p0[2] < -SS_BACK + 1.0, "{p0:?}");
            let end = g.pos(f64::from(SS_HIT));
            assert!(end[0].hypot(end[2]) < 1e-6 && (end[1] - SS_THICK * 0.5).abs() < 1e-6, "{end:?}");
            // (its first point away from the player)
            assert!((g.yaw.sin() + 1.0).abs() < 1e-6, "{}", g.yaw);
            let mut last = g.pos(f64::from(SS_DROP))[1];
            let mut t = f64::from(SS_DROP);
            while t < f64::from(SS_HIT) {
                t += 0.05;
                let y = g.pos(t.min(f64::from(SS_HIT)))[1];
                assert!(y <= last + 1e-9);
                last = y;
            }
        }
        let w = ss_table(37.0, [0.0, 5.0, 300.0]);
        assert!(w.len() <= SS_HF && SS_P + 3 * SS_N <= SS_PF && SS_PF + SS_PW * SS_PUFFS <= SS_FR);
        assert!(SS_HF + 8 + SS_HN * SS_HN <= SS_DB);
        assert_eq!(f32::from_bits(w[15]), SS_MAGIC);
    }

    #[test]
    fn ss_pass_keeps_the_clock_and_the_star_in_step() {
        let src = include_str!("../../shaders/sixstars.wgsl");
        let num = |name: &str| -> f32 {
            let pre = format!("const {name}: f32 = ");
            let l = src.lines().find(|l| l.starts_with(&pre)).unwrap_or_else(|| panic!("{name}"));
            l.trim_start_matches(&pre).split(';').next().unwrap().trim().parse().unwrap()
        };
        assert_eq!(num("SS_PEEL"), SS_PEEL);
        assert_eq!(num("SS_STATION"), SS_STATION);
        assert_eq!(num("SS_DROP"), SS_DROP);
        assert_eq!(num("PL_HIT"), SS_HIT);
        assert_eq!(num("SS_PLOUGH"), SS_PLOUGH);
        assert_eq!(num("SS_PLOUGH_K"), SS_PLOUGH_K as f32);
        assert_eq!(num("SS_IN_K"), SS_IN_K as f32);
        assert_eq!(num("PL_LEN"), crate::lasers::SIX_STARS.length);
        for (k, &t) in SS_STARS.iter().enumerate() {
            assert_eq!(num(&format!("SS_STAR{}", k + 1)), t);
        }
        // (evenly spaced: the pass works each out from the first two)
        for k in 0..6 {
            assert!((SS_STARS[k] - (SS_STARS[0] + (SS_STARS[1] - SS_STARS[0]) * k as f32)).abs() < 1e-5);
        }
    }

    #[test]
    fn ss_sounds_are_its_own_and_the_blast_arrives_late_by_the_distance() {
        let sounds = |z: f64| -> Vec<(f32, String, f32)> {
            plan(&crate::lasers::SIX_STARS, &target(), false, "minecraft:overworld", 37.0, [10.5, 66.0, z], 0)
                .into_iter()
                .filter_map(|(t, a)| if let Act::Sound { event, volume, .. } = a { Some((t, event, volume)) } else { None })
                .collect()
        };
        let near = sounds(150.0);
        let has = |v: &[(f32, String, f32)], s: &str| v.iter().find(|e| e.1 == format!("orbital:sixstars.{s}")).map(|e| e.0);
        for s in ["climb", "star1", "star6", "sirens", "peel", "flight", "fall", "ground", "blast_near", "plough", "after"] {
            assert!(has(&near, s).is_some(), "{s}");
        }
        assert!(has(&near, "blast_far").is_none());
        let far = sounds(1600.0);
        assert!(has(&far, "blast_near").is_none() && has(&far, "blast_far").is_some());
        assert!(has(&far, "blast_far").unwrap() > has(&near, "blast_near").unwrap() + 2.5);
        assert!(has(&far, "ground").unwrap() < has(&far, "blast_far").unwrap());
        // (every event this laser plays is in sounds.json)
        let json = include_str!("../../../orbital-sounds/assets/orbital/sounds.json");
        for (_, e, _) in near.iter().chain(&far) {
            let key = e.trim_start_matches("orbital:");
            assert!(json.contains(&format!("\"{key}\"")), "{key} is not in sounds.json");
        }
    }

    #[test]
    fn ss_the_pop_lands_on_the_peel() {
        let ev = plan(&crate::lasers::SIX_STARS, &target(), false, "minecraft:overworld", 37.0, [10.5, 66.0, 300.0], 0);
        let t = ev.iter().find_map(|(t, a)| if let Act::Sound { event, .. } = a { (event == "orbital:sixstars.peel").then_some(*t) } else { None });
        assert_eq!(t, Some(SS_PEEL - SS_POP_LEAD));
    }

    fn played(land: u8, terrain: bool) -> crate::strike::sim::Played {
        LAND.with(|l| l.set(land));
        let ev = plan(&crate::lasers::SIX_STARS, &target(), terrain, "minecraft:overworld", 37.0, [10.5, 66.0, 400.0], 0);
        crate::strike::sim::play(ev, crate::lasers::SIX_STARS.length, &column)
    }
    /// The last block put at each place, from what went in.
    fn world(p: &crate::strike::sim::Played) -> std::collections::HashMap<(i32, i32, i32), String> {
        let mut w = std::collections::HashMap::new();
        let mut edits: Vec<&(f32, f32, Blocks)> = p.edits.iter().collect();
        edits.sort_by(|a, b| a.0.total_cmp(&b.0));
        for (_, _, b) in edits {
            for f in b.as_fills() {
                if f.contains(" replace ") || f.starts_with("fill ~") {
                    continue;
                }
                let v: Vec<&str> = f.split_whitespace().collect();
                let n: Vec<i32> = v[1..7].iter().map(|s| s.parse().unwrap()).collect();
                for y in n[1]..=n[4] {
                    w.insert((n[0], y, n[2]), v[7].to_string());
                }
            }
        }
        w
    }

    #[test]
    fn ss_leaves_a_five_pointed_star_burnt_into_the_land() {
        let p = played(0, true);
        let w = world(&p);
        let geo = SsGeo::new(37.0, [0.0, 1.0, 403.0]);
        let s = Shape { cx: 10.5, cz: -2.5, yaw: geo.yaw, ph: [0.0; 3], seed: 0 };
        let floor = |x: i32, z: i32| -> Option<i32> {
            // (the highest block dug to air over the column's old ground, less one: its floor)
            let g = ground_h(x, z);
            (g - 60..=g).rev().find(|&y| w.get(&(x, y, z)).is_some_and(|b| b != "minecraft:air") || w.get(&(x, y, z)).is_none()).filter(|&y| y < g)
        };
        // (dug deep along each point's axis, out to near its tip; left as it was between the points at the same radius)
        for k in 0..5 {
            let a = s.yaw + TAU * f64::from(k) / 5.0;
            for r in [40.0, 100.0, 150.0] {
                let (x, z) = ((10.5 + a.cos() * r).floor() as i32, (-2.5 + a.sin() * r).floor() as i32);
                let f = floor(x, z);
                assert!(f.is_some_and(|f| ground_h(x, z) - f >= 5), "point {k} at {r}: {f:?}");
            }
            let b = a + TAU / 10.0;
            let (x, z) = ((10.5 + b.cos() * 110.0).floor() as i32, (-2.5 + b.sin() * 110.0).floor() as i32);
            assert!(floor(x, z).is_none(), "between the points at 110: {:?}", floor(x, z));
        }
        // (black: the floor and the band round it; lava in its cracks, never where it can run)
        let count = |m: &str| w.values().filter(|b| *b == &format!("minecraft:{m}")).count();
        assert!(count("blackstone") + count("coal_block") + count("basalt") > 20_000, "{}", count("blackstone"));
        assert!(count("lava") > 50, "{}", count("lava"));
        for (&(x, y, z), b) in &w {
            if b == "minecraft:lava" {
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let n = w.get(&(x + dx, y, z + dz));
                    assert!(n.is_none_or(|n| n != "minecraft:air"), "lava at {x} {y} {z} runs into {dx} {dz}");
                }
            }
        }
        // (the points' white wrecks at their trenches' ends; fires burning on netherrack)
        assert!(count("calcite") + count("quartz_block") + count("smooth_quartz") + count("white_concrete") > 300);
        assert!(count("fire") >= 5 && count("fire") <= count("netherrack"));
        // (trees felled pointing away out round it)
        assert!(w.values().filter(|b| b.contains("_log[axis=")).count() > 20);
    }

    #[test]
    fn ss_digs_the_middle_as_it_strikes_and_each_trench_as_its_point_reaches_it() {
        let p = played(10, true);
        let wave = Wave::new();
        let mut first = f32::MAX;
        let mut tip_dug = 0.0f32;
        for (t, _, b) in &p.edits {
            for (u, f) in b.runs.iter().zip(b.as_fills()) {
                if !f.ends_with(" minecraft:air strict") {
                    continue;
                }
                let r = (f64::from(u.x) + 0.5 - 10.5).hypot(f64::from(u.z) + 0.5 + 2.5);
                first = first.min(*t);
                if r > 140.0 && r < 170.0 {
                    tip_dug = tip_dug.max(*t);
                }
                // (never before the points reach it, less a chunk's half)
                assert!(*t + 0.06 >= SS_HIT + plough_t((r - 12.0).max(0.0)) as f32, "dug at {r:.0} at {t}");
            }
        }
        assert!(first >= SS_HIT && first < SS_HIT + 0.3, "{first}");
        assert!(tip_dug > SS_HIT + 1.2 && tip_dug <= SS_HIT + SS_PLOUGH + 0.4, "{tip_dug}");
        assert!(wave.dug() <= SS_HIT + SS_PLOUGH + 0.3);
        // (nothing at all before it strikes)
        assert!(p.edits.iter().all(|(t, _, _)| *t >= SS_HIT));
    }

    #[test]
    fn ss_leaves_the_land_alone_with_the_terrain_off() {
        let p = played(0, false);
        assert!(p.edits.is_empty());
        assert!(p.cmds.iter().all(|(_, c)| !c.starts_with("forceload") && !c.starts_with("summon")));
    }

    #[test]
    fn ss_keeps_lava_from_the_lake() {
        let p = played(1, true);
        let w = world(&p);
        for (&(x, y, z), b) in &w {
            if b == "minecraft:lava" {
                assert!(!(116..164).contains(&x) || !(-44..44).contains(&z), "lava by the lake at {x} {y} {z}");
            }
        }
    }

    #[test]
    fn ss_no_stage_too_heavy() {
        // (each stage's work, counted by the meter, well under a tick's fuel)
        let p = played(0, true);
        let worst = p.stages.iter().map(|s| s.2).fold(0.0, f64::max);
        eprintln!("worst stage {worst:.1} ms over {} stages", p.stages.len());
        assert!(p.stages.len() > 50);
    }
}
