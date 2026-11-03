//! The Supercell's plan: a storm called down on the target. The sky darkens and a huge, low, slowly turning wall cloud
//! and an anvil-topped storm cloud boil up over it and spread; the wind gusts, thunder rumbles far off. Then the storm,
//! building with no pause: lightning all over the land under the cloud out to SC_REACH, small lone bolts coming faster,
//! then waves of more and more at once (with the terrain on, each bolt hurting what it hits and setting its foot
//! alight), drawing in onto the target; then the finale's run-in, a rapid run of bolts snapping down closer and closer
//! onto it (`FIN_RUN`, each in time with a crack of the finale's sound), a hush, and one colossal strike on it, the ring
//! of bolts round the wall cloud snapping into it in the same instant, a shockwave and a jolt;
//! heavy rain falling out of the cloud, a few thin funnels (vortex.rs) coming down out of the wall cloud and wandering
//! over the land; then the storm dies away.
//!
//! What it leaves is light: a small scorched pit where each bolt struck (blackstone, basalt, tinted glass, a seam of
//! magma, glassy sand), charred grass round it, the funnels' scoured tracks; and the finale's: a crater about 70 across
//! and 24 deep, fulgurite veins of glass branching out from it, an overturned rim, the trees round it blasted and set
//! alight, the land scorched far out (`fc_band`). The world's weather is left alone (the pass draws the rain), and the fires
//! the bolts light are left burning, to burn out or spread as fire does.
//!
//! The bolts are not vanilla's `lightning_bolt`s: one plays its own full-scale thunder at the flash, however far off,
//! and `stopsound` can only cut it a tick or more in (a pop and a click, then ours on top). Each bolt instead hurts what
//! stands at its foot (`damage ... minecraft:lightning_bolt`) and sets a few fires there, as a vanilla bolt does. Its
//! thunder (tools/sounds_storm.py) arrives late by the distance (343 blocks a second) and is chosen by it (`thunder_of`):
//! a crack close by, a duller clap further, mostly rumble far off; the take picked here, never one of the last two.
//!
//! shaders/supercell.wgsl draws the cloud, the rain, the bolts, the funnels and the flashes from the table `sc_table`
//! hands it (render.set-data). Keep the SC_* here and there in step.
use super::vortex::{self, Funnel, VX_W};
use super::{Act, Blocks, Plan, Rng, TIDY_LOOSE, Target, mh, pk_load_rows, sound_from, vnoise};
use crate::lasers::Laser;
use std::f64::consts::PI;
use std::rc::Rc;

/// The storm's timeline: the cloud formed by SC_FORMED; the bolts from SC_STORM0 to SC_STORM1, building (`sc_bolts`):
/// the flurry's lone small bolts coming faster, from SC_WAVES more and more of them at once up to SC_CAP, from SC_CONV
/// their feet drawn in on the target and their roots in to the wall cloud's middle; then the finale's run-in (`FIN_RUN`:
/// from SC_STORM1 a rapid run of lone bolts, each instant, closer and closer onto the target, in time with its sound's
/// cracks), the hush (FIN_SUCK) and the colossal strike at SC_FINALE; the rain stopping and the cloud dying away from
/// SC_CLEAR (gone by the strike's end, lasers.rs's length). (SC_FORMED, SC_WAVES, SC_CONV, SC_STORM1 and SC_CLEAR the
/// pass reads too: kept here in step.)
#[allow(dead_code)]
pub(super) const SC_FORMED: f32 = 6.5;
pub(super) const SC_STORM0: f32 = 4.0;
pub(super) const SC_WAVES: f32 = 15.0;
pub(super) const SC_CONV: f32 = 24.0;
pub(super) const SC_STORM1: f32 = 27.85;
pub(super) const SC_FINALE: f32 = 29.0;
#[allow(dead_code)]
pub(super) const SC_CLEAR: f32 = 32.5;
/// The most bolts over the storm (the table's room), the most striking at once, and how far out from the middle they
/// strike before they draw in.
pub(super) const SC_NB: usize = 140;
pub(super) const SC_CAP: usize = 5;
pub(super) const SC_REACH: f64 = 120.0;
/// The flickers in the cloud (no bolt to the ground).
pub(super) const SC_NK: usize = 56;
/// The table (`mod_data`): a header (bolts, finale time, funnels, flickers, the middle's ground), the bolts from SC_B
/// (SC_BW words each: t, x, z off the middle, the ground there over the middle's; in the order they strike), the
/// funnels from SC_F (VX_W words each), the flickers from SC_K (t, x, z), and from SC_I for each whole second the first
/// bolt still to be seen then (struck no more than a second and a bit before it), so the pass looks at only those.
pub(super) const SC_B: usize = 16;
pub(super) const SC_BW: usize = 4;
pub(super) const SC_F: usize = SC_B + SC_BW * SC_NB;
pub(super) const SC_NF: usize = 3;
pub(super) const SC_K: usize = 1024;
pub(super) const SC_I: usize = SC_K + 3 * SC_NK;
pub(super) const SC_NI: usize = 64;
/// How far out it works in the land (the chunks forceloaded for it).
const SC_SWEEP: f64 = 150.0;

/// A bolt: when, and where off the middle.
#[derive(Clone, Copy, Debug)]
pub(super) struct Bolt {
    pub t: f32,
    pub x: f64,
    pub z: f64,
}

/// The finale's run-in, off SC_FINALE: when each crack of its sound's run-in is (tools/sounds_storm.py's `run_in`, its
/// onsets as that sound is made, seeded: keep in step) and how many bolts strike on it. The cracks come faster and
/// faster into the hush (FIN_SUCK), from 0.22 s apart to 0.025; the pass draws each bolt as it strikes, instantly.
pub(super) const FIN_RUN: [(f32, u32); 10] =
    [(-1.072, 1), (-0.854, 1), (-0.698, 2), (-0.561, 1), (-0.463, 2), (-0.38, 2), (-0.316, 2), (-0.255, 3), (-0.215, 3), (-0.19, 3)];
const FIN_RUN_N: usize = 20;

fn smooth(a: f64, b: f64, x: f64) -> f64 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}
/// How many bolts strike at once at `t`: one through the flurry, then more and more up to SC_CAP by SC_CONV.
pub(super) fn sc_at_once(t: f64, h: f64) -> usize {
    let u = ((t - f64::from(SC_WAVES)) / f64::from(SC_CONV - SC_WAVES)).clamp(0.0, 1.0);
    (1.0 + (SC_CAP as f64 - 1.0) * u.powf(1.3) + 0.7 * (h - 0.5)).round().clamp(1.0, SC_CAP as f64) as usize
}
/// The gap after a wave struck at `t` to the next: 1.7 s as the flurry starts, closing to 0.6 by SC_WAVES, to 0.45 by
/// SC_CONV and 0.36 at the end.
fn sc_gap(t: f64, h: f64) -> f64 {
    let (s0, sw, sc, s1) = (f64::from(SC_STORM0), f64::from(SC_WAVES), f64::from(SC_CONV), f64::from(SC_STORM1));
    let g = if t < sw {
        1.7 * (0.6f64 / 1.7).powf(((t - s0) / (sw - s0)).clamp(0.0, 1.0))
    } else if t < sc {
        0.6 + (0.45 - 0.6) * (t - sw) / (sc - sw)
    } else {
        0.45 + (0.36 - 0.45) * ((t - sc) / (s1 - sc)).clamp(0.0, 1.0)
    };
    g * (0.75 + 0.5 * h)
}
/// How far out the bolts strike at `t`: anywhere out to SC_REACH, drawn in from SC_CONV, the last ones hugging the
/// target (out to 12).
pub(super) fn sc_reach(t: f64) -> f64 {
    let c = smooth(f64::from(SC_CONV), f64::from(SC_STORM1), t);
    12.0 + (SC_REACH - 12.0) * (1.0 - c).powf(1.4)
}

/// The bolts of strike `seed` (the player at `me`, off the middle), in the order they strike: the flurry's lone bolts
/// from SC_STORM0 coming faster and faster, then from SC_WAVES waves of more and more at once (`sc_at_once`, the bolts
/// of a wave within 0.15 s of each other), their gaps closing; from SC_CONV their feet drawn in towards the target
/// (`sc_reach`) until the last wave just before SC_STORM1 strikes round it; then the finale's run-in (`FIN_RUN`): on each
/// of its cracks one to three bolts, their feet closer and closer onto the target, from 24 out to 2. Never within 10
/// blocks of the player.
pub(super) fn sc_bolts(seed: u32, me: [f64; 2]) -> Vec<Bolt> {
    let mut out: Vec<Bolt> = Vec::with_capacity(SC_NB);
    let mut t = f64::from(SC_STORM0) + 0.4 * mh(0, seed, 0xb0);
    let mut w = 0u32;
    let away = |x: f64, z: f64| {
        let d = (x - me[0]).hypot(z - me[1]);
        if d < 10.0 {
            let k = 10.0 / d.max(0.1);
            (me[0] + (x - me[0]) * k, me[1] + (z - me[1]) * k)
        } else {
            (x, z)
        }
    };
    while t <= f64::from(SC_STORM1) - 0.15 && out.len() < SC_NB - FIN_RUN_N {
        let k = sc_at_once(t, mh(w, seed, 0xb4));
        // (a wave's bolts spread round the land, not bunched: each a share of the circle, jittered)
        let a0 = 2.0 * PI * mh(w, seed, 0xb5);
        for j in 0..k {
            if out.len() == SC_NB - FIN_RUN_N {
                break;
            }
            let i = out.len() as u32;
            // (striking closer together as they draw in)
            let tj = t + if j == 0 { 0.0 } else { 0.02 + (0.12 - 0.08 * smooth(f64::from(SC_CONV), f64::from(SC_STORM1), t)) * mh(i, seed, 0xb3) };
            let a = a0 + 2.0 * PI * (j as f64 + 0.7 * mh(i, seed, 0xb1)) / k as f64;
            let reach = sc_reach(tj);
            let r = (14.0f64).min(0.4 * reach) + (reach - (14.0f64).min(0.4 * reach)) * mh(i, seed, 0xb2).powf(0.75);
            let (x, z) = away(a.cos() * r, a.sin() * r);
            out.push(Bolt { t: tj as f32, x, z });
        }
        // (and the last wave right on the finale's heels: no pause before it)
        let next = t + sc_gap(t, mh(w, seed, 0xb6));
        let end = f64::from(SC_STORM1) - 0.15;
        t = if next > end && t < end - 0.24 { end } else { next };
        w += 1;
    }
    // (the run-in: on each crack its bolts within a frame of each other, spread round the target, the feet drawn in)
    for (k, &(at, n)) in FIN_RUN.iter().enumerate() {
        let u = k as f64 / (FIN_RUN.len() - 1) as f64;
        let reach = 24.0 - 22.0 * u.powf(0.8);
        let a0 = 2.0 * PI * mh(k as u32, seed, 0xe0);
        for j in 0..n {
            let i = (k * 3) as u32 + j;
            let a = a0 + 2.0 * PI * (f64::from(j) + 0.6 * mh(i, seed, 0xe1)) / f64::from(n);
            let r = reach * (0.55 + 0.45 * mh(i, seed, 0xe2));
            let (x, z) = away(a.cos() * r, a.sin() * r);
            out.push(Bolt { t: SC_FINALE + at + 0.006 * j as f32, x, z });
        }
    }
    out.sort_by(|a, b| a.t.total_cmp(&b.t));
    out
}

/// The flickers in the cloud: throughout the storm, a few in the build-up and more and more with the bolts, high in the
/// cloud anywhere over the land.
pub(super) fn sc_flickers(seed: u32) -> Vec<[f32; 3]> {
    (0..SC_NK)
        .map(|i| {
            let u = (i as f64 + mh(i as u32, seed, 0xc0)) / SC_NK as f64;
            let t = 2.5 + f64::from(SC_FINALE - 3.0) * u.powf(0.7);
            let a = 2.0 * PI * mh(i as u32, seed, 0xc1);
            let r = 200.0 * mh(i as u32, seed, 0xc2).sqrt();
            [t as f32, (a.cos() * r) as f32, (a.sin() * r) as f32]
        })
        .collect()
}

/// The funnels: SC_NF thin landspouts let down out of the wall cloud through the storm, overlapping, each wandering
/// for 10 to 12.5 seconds, the last lifting back up as the bolts draw in.
pub(super) fn sc_funnels(seed: u32) -> Vec<Funnel> {
    let starts = [6.5, 10.5, 14.5];
    (0..SC_NF as u32)
        .map(|k| {
            let r = |j: u32| mh(k * 7 + j, seed, 0xf0);
            let t0 = starts[k as usize] + 1.2 * r(0);
            let len = 10.0 + 2.5 * r(1);
            let a = 2.0 * PI * r(2);
            let d = 25.0 + 35.0 * r(3);
            // (heading round the middle the way the storm turns, a little outward)
            let h0 = a + PI / 2.0 - 0.35 + 0.3 * r(4);
            vortex::wander(seed, k, [a.cos() * d, a.sin() * d], h0, 4.0 + 2.5 * r(5), t0, t0 + len, 100.0, 3.5 + 1.5 * r(6))
        })
        .collect()
}

/// The pass's table for strike `seed` (the player at `me`, off the middle), the ground under each bolt and funnel's
/// track as `dy` says (None: not known yet, taken as the middle's).
pub(super) fn sc_table(seed: u32, me: [f64; 2], dy: &dyn Fn(f64, f64) -> Option<f64>) -> Vec<u32> {
    let bolts = sc_bolts(seed, me);
    let funnels = sc_funnels(seed);
    let flick = sc_flickers(seed);
    let mut w = vec![0u32; SC_I + SC_NI];
    let f = |v: f64| (v as f32).to_bits();
    w[0] = f(bolts.len() as f64);
    w[1] = SC_FINALE.to_bits();
    w[2] = f(funnels.len() as f64);
    w[3] = f(flick.len() as f64);
    w[4] = f(dy(0.0, 0.0).unwrap_or(0.0));
    for (i, b) in bolts.iter().enumerate() {
        let o = SC_B + SC_BW * i;
        w[o] = b.t.to_bits();
        w[o + 1] = f(b.x);
        w[o + 2] = f(b.z);
        w[o + 3] = f(dy(b.x, b.z).unwrap_or(0.0));
    }
    for (k, fu) in funnels.iter().enumerate() {
        let track = vortex::ground_track(&fu.path, |x, z| dy(x, z));
        let words = vortex::vx_words(fu, &track);
        w[SC_F + VX_W * k..SC_F + VX_W * (k + 1)].copy_from_slice(&words);
    }
    for (i, k) in flick.iter().enumerate() {
        w[SC_K + 3 * i] = k[0].to_bits();
        w[SC_K + 3 * i + 1] = k[1].to_bits();
        w[SC_K + 3 * i + 2] = k[2].to_bits();
    }
    // (for each whole second s, the first bolt struck after s - 1.1: none before it is still seen at s or later)
    for (s, word) in w[SC_I..SC_I + SC_NI].iter_mut().enumerate() {
        *word = bolts.iter().position(|b| b.t > s as f32 - 1.1).unwrap_or(bolts.len()) as u32;
    }
    w
}

/// The columns whose ground the pass needs: under each bolt and along each funnel's track (and the middle).
fn sc_columns(seed: u32, me: [f64; 2], bx: i32, bz: i32) -> Vec<(i32, i32)> {
    let c = |x: f64, z: f64| ((f64::from(bx) + 0.5 + x).floor() as i32, (f64::from(bz) + 0.5 + z).floor() as i32);
    let mut out = vec![(bx, bz)];
    out.extend(sc_bolts(seed, me).iter().map(|b| c(b.x, b.z)));
    for f in sc_funnels(seed) {
        for p in &f.path {
            out.extend(vortex::VX_PROBE.iter().map(|&(dx, dz)| c(p[0] + f64::from(dx), p[1] + f64::from(dz))));
        }
    }
    out
}

/// The ground off the middle (bx, by, bz) at (x, z), over the middle's ground (by + 1), where the world has answered.
fn ground_dy(bx: i32, by: i32, bz: i32, x: f64, z: f64) -> Option<f64> {
    let (ix, iz) = ((f64::from(bx) + 0.5 + x).floor() as i32, (f64::from(bz) + 0.5 + z).floor() as i32);
    crate::ground::at(ix, iz).map(|g| f64::from(g - by - 1))
}

const LINING: [(&str, f32); 5] = [
    ("minecraft:blackstone", 0.35),
    ("minecraft:smooth_basalt", 0.2),
    ("minecraft:tinted_glass", 0.2),
    ("minecraft:obsidian", 0.1),
    ("minecraft:basalt", 0.15),
];
const CHAR: [(&str, f32); 3] = [("minecraft:coarse_dirt", 0.6), ("minecraft:podzol", 0.25), ("minecraft:blackstone", 0.15)];

/// A bolt's pit at (x, z), struck at `t`: a few blocks dug a block or two into the ground (counted from the column's own
/// top, read as the edit goes in), lined with fused stone and glass, a block of magma glowing at the middle, the sand
/// round it fused to glass, the grass round it charred in a ragged ring and its plants burnt off. `big`: the finale's.
fn pit(b: &mut Blocks, rng: &mut Rng, x: i32, z: i32, r_pit: f64, r_char: f64, seed: u32) {
    let ri = r_char.ceil() as i32 + 1;
    for dz in -ri..=ri {
        for dx in -ri..=ri {
            let d = f64::from(dx).hypot(f64::from(dz));
            let (cx, cz) = (x + dx, z + dz);
            if d <= r_pit {
                let dig = if d < 0.45 * r_pit { 2 } else { 1 };
                b.put(cx, cz, -dig, -1, "minecraft:air", None, true);
                let floor = if d < 0.7 { "minecraft:magma_block" } else { rng.weighted(&LINING) };
                b.put(cx, cz, -dig - 1, -dig - 1, floor, None, true);
            } else if d <= r_char * (0.75 + 0.4 * vnoise(f64::from(cx), f64::from(cz), 2.5, seed ^ 0x3c)) {
                if d <= r_pit + 1.5 {
                    b.put(cx, cz, -1, -1, "minecraft:glass", Some("#minecraft:sand"), true);
                }
                b.put(cx, cz, -1, -1, rng.weighted(&CHAR), Some("minecraft:grass_block"), true);
                b.put(cx, cz, 0, 1, "minecraft:air", Some(TIDY_LOOSE), true);
            }
        }
    }
}

// ---- the finale's land: a crater ~70 across and 24 deep, fulgurite veins branching out from it, an overturned rim,
// the trees round it blasted and set alight, the land scorched in a wide ring, blocks thrown out --------------------------
const FC_R: f64 = 35.0;
const FC_D: f64 = 24.0;
const FC_RIM: f64 = 13.0;
const FC_SCORCH: f64 = 112.0;
const FC_BANDS: usize = 40;
const FC_VEINS: usize = 9;
const FC_KILL: i32 = 80;
const FC_THROWN: usize = 60;
/// The shockwave's front over the land, blocks a second (the pass's ring goes as fast).
const FC_V: f64 = 140.0;
const FC_GLASS: [(&str, f32); 3] = [("minecraft:tinted_glass", 0.45), ("minecraft:glass", 0.25), ("minecraft:obsidian", 0.3)];
const FC_RIM_TOP: [(&str, f32); 5] = [
    ("minecraft:coarse_dirt", 0.3),
    ("minecraft:dirt", 0.2),
    ("minecraft:stone", 0.2),
    ("minecraft:gravel", 0.15),
    ("minecraft:rooted_dirt", 0.15),
];
const FC_RIM_BODY: [(&str, f32); 3] = [("minecraft:dirt", 0.5), ("minecraft:stone", 0.3), ("minecraft:cobblestone", 0.2)];

/// When the finale's front reaches r out.
fn fc_wave(t: f32, r: f64) -> f32 {
    t + 0.05 + (r / FC_V) as f32
}
/// A column's own pick of `items` (as `Rng::weighted`, from its own hash, so a column's blocks never depend on the
/// stage it falls in).
fn pick_at(items: &[(&'static str, f32)], x: i32, z: i32, seed: u32, k: u32) -> &'static str {
    let total: f32 = items.iter().map(|i| i.1).sum();
    let mut r = mh((x as u32).wrapping_mul(73_856_093) ^ (z as u32).wrapping_mul(19_349_663), seed, k) as f32 * total;
    for (name, w) in items {
        if r < *w {
            return name;
        }
        r -= w;
    }
    items[items.len() - 1].0
}
fn chance(x: i32, z: i32, seed: u32, k: u32) -> f64 {
    mh((x as u32).wrapping_mul(73_856_093) ^ (z as u32).wrapping_mul(19_349_663), seed, k)
}
/// The fulgurites: FC_VEINS veins of fused glass from the crater's middle out through the ground to 55-85 blocks, each
/// wandering and forking twice, a block or two wide; magma at their hottest, nearest the strike. (x, z) off the middle
/// -> 0 glass, 1 magma.
fn fc_veins(seed: u32) -> crate::ground::FxMap<(i32, i32), u8> {
    let mut out: crate::ground::FxMap<(i32, i32), u8> = Default::default();
    let trace = |a0: f64, r0: f64, r1: f64, k: u32, out: &mut crate::ground::FxMap<(i32, i32), u8>| {
        let ph = 2.0 * PI * mh(k, seed, 0xe1);
        let mut r = r0;
        while r < r1 {
            crate::meter::spend(400);
            let a = a0 + 0.18 * (r * 0.09 + ph).sin() + 0.08 * (r * 0.31 + 2.0 * ph).sin();
            let (x, z) = ((a.cos() * r).round() as i32, (a.sin() * r).round() as i32);
            let hot = u8::from(r < FC_R * 0.9 || (r < FC_R + 15.0 && chance(x, z, seed, 0xe2) < 0.3));
            let w = if r < r0 + 0.7 * (r1 - r0) { 1 } else { 0 };
            for (dx, dz) in [(0, 0), (w, 0), (0, w)] {
                let e = out.entry((x + dx, z + dz)).or_insert(hot);
                *e = (*e).max(hot);
            }
            r += 0.7;
        }
    };
    for k in 0..FC_VEINS as u32 {
        let a0 = 2.0 * PI * (f64::from(k) + 0.6 * mh(k, seed, 0xe3)) / FC_VEINS as f64;
        let r1 = 55.0 + 30.0 * mh(k, seed, 0xe4);
        trace(a0, 4.0, r1, k, &mut out);
        for f in 0..2u32 {
            let rf = 20.0 + (r1 - 30.0) * mh(k * 3 + f, seed, 0xe5);
            let side = if f == 0 { 1.0 } else { -1.0 };
            trace(a0 + side * (0.25 + 0.2 * mh(k * 3 + f, seed, 0xe6)), rf, rf + 12.0 + 18.0 * mh(k * 3 + f, seed, 0xe7), 50 + k * 3 + f, &mut out);
        }
    }
    out
}
/// A run counted from a column's top on heightmap `h` (`Blocks::put` counts from the one without leaves).
fn put_on(b: &mut Blocks, x: i32, z: i32, y0: i32, y1: i32, block: &'static str, only: Option<&'static str>, h: horizon_mod_sdk::world::Heightmap) {
    crate::meter::spend(60 + 8 * b.palette.len() as u64);
    let block = Blocks::index(&mut b.palette, block);
    let only = only.map(|f| Blocks::index(&mut b.filters, f));
    b.runs.push(horizon_mod_sdk::world::BlockRun { x, z, y: y0, height: (y1 - y0 + 1) as u32, surface: Some(h), block, only });
}
/// Band `k` of FC_BANDS (equal areas out to FC_SCORCH) of the finale's land, struck at `t`, going in with its front.
fn fc_band(q: &mut Plan, k: usize, t: f32, seed: u32, veins: &crate::ground::FxMap<(i32, i32), u8>) {
    use horizon_mod_sdk::world::Heightmap;
    let (bx, bz) = (q.bx, q.bz);
    let r0 = FC_SCORCH * (k as f64 / FC_BANDS as f64).sqrt();
    let r1 = FC_SCORCH * ((k + 1) as f64 / FC_BANDS as f64).sqrt();
    let mut b = Blocks { cleanup: false, ..Default::default() };
    // (only the band's own columns visited, a row's span either side of the middle: never the square round it)
    let ri = r1.ceil() as i32;
    let mut cols = Vec::new();
    for dz in -ri..=ri {
        let z2 = f64::from(dz) * f64::from(dz);
        let xo = (r1 * r1 - z2).max(0.0).sqrt().ceil() as i32;
        let xi = if r0 * r0 > z2 { ((r0 * r0 - z2).sqrt().floor() as i32 - 1).max(0) } else { -1 };
        crate::meter::spend(300);
        let mut span = |a: i32, c: i32| cols.extend((a..=c).map(|dx| (dx, dz)));
        if xi < 0 {
            span(-xo, xo);
        } else {
            span(-xo, -xi);
            span(xi, xo);
        }
    }
    for (dx, dz) in cols {
        {
            let r = f64::from(dx).hypot(f64::from(dz));
            crate::meter::spend(400);
            if r < r0 || r >= r1 {
                continue;
            }
            let (x, z) = (bx + dx, bz + dz);
            let wob = 0.9 + 0.2 * vnoise(f64::from(x), f64::from(z), 7.0, seed ^ 0x71);
            let rr = r / wob;
            let vein = veins.get(&(dx, dz)).copied();
            if rr < FC_R {
                // the crater: dug, everything over it gone, its face fused (two deep), the veins in it glass and magma
                let u = rr / FC_R;
                let dig = ((FC_D * (1.0 - u * u).powf(0.8)).round() as i32).max(1);
                b.put(x, z, -dig, 45, "minecraft:air", None, true);
                let face = match vein {
                    Some(1) => "minecraft:magma_block",
                    Some(_) => pick_at(&FC_GLASS, x, z, seed, 0x81),
                    None => pick_at(&LINING, x, z, seed, 0x82),
                };
                b.put(x, z, -dig - 1, -dig - 1, face, None, true);
                b.put(x, z, -dig - 2, -dig - 2, pick_at(&LINING, x, z, seed, 0x83), None, true);
                continue;
            }
            // round it: the trees blasted (crowns torn off near it; trunks charred out to 70, gone under the rim),
            // the plants burnt off, the grass scorched in patches thinning out
            if rr < FC_R + FC_RIM {
                b.put(x, z, -30, -1, "minecraft:air", Some(super::TIDY_LOGS), true);
            } else if r < 70.0 && chance(x, z, seed, 0x84) < 0.8 {
                b.put(x, z, -30, -1, "minecraft:basalt", Some(super::TIDY_LOGS), true);
            }
            if r < 62.0 {
                b.put(x, z, 0, 30, "minecraft:air", Some("#minecraft:leaves"), true);
            }
            if r < 95.0 {
                b.put(x, z, 0, 2, "minecraft:air", Some(TIDY_LOOSE), true);
            }
            let p = (1.0 - (rr - FC_R) / (FC_SCORCH - FC_R)).clamp(0.0, 1.0).powf(0.7);
            if chance(x, z, seed, 0x85) < 0.25 + 0.75 * p {
                b.put(x, z, -1, -1, pick_at(&CHAR, x, z, seed, 0x86), Some("minecraft:grass_block"), true);
            }
            // the fulgurites through the ground, glass showing at the top
            if let Some(v) = vein {
                let core = if v == 1 { "minecraft:magma_block" } else { pick_at(&FC_GLASS, x, z, seed, 0x87) };
                b.put(x, z, -3, -1, core, None, true);
            }
            // the rim: the ground thrown up and turned over, stone and raw earth on top
            let h = (5.0 * (-((rr - FC_R - 3.0) / 4.5).powi(2)).exp() * (0.7 + 0.6 * vnoise(f64::from(x), f64::from(z), 4.0, seed ^ 0x72))).round() as i32;
            if h > 0 {
                if h > 1 {
                    b.put(x, z, 0, h - 2, pick_at(&FC_RIM_BODY, x, z, seed, 0x88), None, true);
                }
                b.put(x, z, h - 1, h - 1, pick_at(&FC_RIM_TOP, x, z, seed, 0x89), None, true);
            }
            // set alight: fires on the treetops and the land round it, put out by the sweeps as the storm ends
            if (45.0..95.0).contains(&r) && chance(x, z, seed, 0x8a) < 0.07 * (1.0 - (r - 45.0) / 60.0) {
                put_on(&mut b, x, z, 0, 0, "minecraft:fire", Some("minecraft:air"), Heightmap::MotionBlocking);
            }
        }
    }
    let (cxf, czf) = (f64::from(bx), f64::from(bz));
    for (tk, e) in b.split_by(|x, z| fc_wave(t, (f64::from(x) - cxf).hypot(f64::from(z) - czf))) {
        q.ev.push((tk, Act::Blocks(Box::new(e))));
    }
}
/// Blocks of the ground thrown out of the crater as it is struck, up and out, half breaking up where they land.
fn fc_thrown(q: &mut Plan, t: f32, seed: u32) {
    let (bx, bz) = (q.bx, q.bz);
    for i in 0..FC_THROWN as u32 {
        let a = 2.0 * PI * mh(i, seed, 0x91);
        let r = FC_R * 0.8 * mh(i, seed, 0x92).sqrt();
        let (x, z) = (bx + (a.cos() * r).round() as i32, bz + (a.sin() * r).round() as i32);
        let out = 0.6 + 0.9 * mh(i, seed, 0x93);
        let (vx, vz, vy) = (a.cos() * out, a.sin() * out, 0.9 + 0.8 * mh(i, seed, 0x94));
        let blk = pick_at(&[("minecraft:dirt", 0.3), ("minecraft:stone", 0.25), ("minecraft:blackstone", 0.2), ("minecraft:coarse_dirt", 0.15), ("minecraft:magma_block", 0.1)], x, z, seed, 0x95);
        let keep = if mh(i, seed, 0x96) < 0.5 { ",CancelDrop:1b" } else { "" };
        let tk = fc_wave(t, r) + 0.02 * (i % 10) as f32;
        q.ev.push((tk, Act::Cmd(format!(
            "execute positioned {x} 0 {z} positioned over motion_blocking_no_leaves run summon minecraft:falling_block ~0.5 ~1 ~0.5 {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"
        ))));
    }
}


/// How far into the finale's sound its crack is (tools/sounds_storm.py's FIN_PRE): before it, the run-in, its bolts'
/// cracks (`FIN_RUN`) stacking up faster and faster into it.
const FIN_PRE: f32 = 1.2;
/// The hush before the finale's crack (sounds_storm.py's FIN_SUCK, supercell.wgsl's SC_SUCK): its run-in falls away
/// FIN_SUCK before the crack, so it lands out of silence; the storm's beds are cut (`FIN_CUT`) a little before that,
/// under the run-in's last, loudest cracks, so the cut is not heard as one.
const FIN_SUCK: f32 = 0.16;
const FIN_CUT: f32 = FIN_SUCK + 0.1;
/// What the finale cuts (`stopsound`): the storm's beds and every bolt's and flicker's thunder still rolling.
fn sc_beds() -> Vec<String> {
    let mut v: Vec<String> = ["buildup", "gusts", "rain", "roar"].iter().map(|k| format!("orbital:supercell.{k}")).collect();
    for (kind, n) in [("crack", 6), ("crack_mid", 5), ("crack_far", 5), ("rumble", 5)] {
        v.extend((1..=n).map(|k| format!("orbital:supercell.{kind}{k}")));
    }
    v
}
/// How much of the finale is heard as the far one (`finale_far`), `dist` blocks off: none within 250, all of it past
/// 800 (as the Rod's blast).
fn fc_far(dist: f64) -> f32 {
    let u = ((dist - 250.0) / 550.0).clamp(0.0, 1.0);
    (u * u * (3.0 - 2.0 * u)) as f32
}
/// The finale's crack reaching the player at `t`, `fo` as hard: a violent hit (the camera at the game's hardest for two
/// seconds, kicked again and again, as the Nuke's), then a heavy shudder dying away over seven. The pass knocks the
/// picture about on top of it (supercell.wgsl's `sc_jolt`) and punches it pale (`sc_press`).
fn fc_jolt(p: &mut Plan, t: f32, fo: f32) {
    p.shake(t, fo, 2.2);
    for n in 0..16 {
        let u = n as f32 / 16.0;
        p.shake(t + 0.05 + 0.085 * n as f32, (1.0 - 0.35 * u) * fo, 0.22);
    }
    p.shake(t + 0.35, 0.75 * fo, 7.5);
    let mut ts = t + 1.5;
    while ts < t + 7.5 {
        let u = (ts - t - 1.5) / 6.0;
        p.shake(ts, (0.7 * (1.0 - u).powf(1.3) + 0.1) * fo, 0.3);
        ts += 0.12 + 0.1 * u;
    }
}
/// How loud a bolt's thunder is `d` blocks off, as a file's loudest 400 ms in dB (tools/sounds_storm.py's LEVEL): a
/// -15 at 60 blocks (a close crack's own -14 is its most: its volume can't pass 1; the finale's -8.6 stands well over
/// it), then 4 dB down each time the
/// distance doubles (a channel kilometres long, not a point: thunder fades slower than a bang, and a bolt seen must be
/// heard well over the wind and the rain).
fn thunder_db(d: f64) -> f64 {
    -15.0 - 4.0 * (d.max(60.0) / 60.0).log2()
}
/// How much quieter a bolt struck at `t` is for its size: the flurry's small ones 5.5 dB under the waves' (the pass's
/// `sc_size`, as dB).
fn size_db(t: f32) -> f64 {
    let size = 0.45 + 0.55 * smooth(f64::from(SC_STORM0), f64::from(SC_WAVES), f64::from(t));
    16.0 * size.log10()
}
/// The rumble's level (sounds_storm.py's LEVEL).
const RUMBLE_DB: f64 = -25.5;
/// The thunder of a bolt `d` blocks off: its sound, how many takes it has and the takes' level (sounds_storm.py's
/// LEVEL). A crack close by, a duller clap further off, mostly rumble past 260.
fn thunder_of(d: f64) -> (&'static str, u32, f64) {
    if d < 90.0 {
        ("crack", 6, -14.0)
    } else if d < 260.0 {
        ("crack_mid", 5, -17.5)
    } else {
        ("crack_far", 5, -21.0)
    }
}
/// The takes played so far, so the next of a kind is never one of its last two.
#[derive(Default)]
struct Takes(Vec<(&'static str, u32)>);
impl Takes {
    fn pick(&mut self, kind: &'static str, n: u32, h: f64) -> u32 {
        let recent: Vec<u32> = self.0.iter().rev().filter(|(k, _)| *k == kind).take(2).map(|(_, v)| *v).collect();
        let free: Vec<u32> = (1..=n).filter(|v| !recent.contains(v)).collect();
        let v = free[((h * free.len() as f64) as usize).min(free.len() - 1)];
        self.0.push((kind, v));
        v
    }
}
/// A bolt's thunder as the player hears it.
#[derive(Clone, Debug)]
pub(super) struct Heard {
    pub at: f32,
    pub event: String,
    pub volume: f32,
    pub pitch: f32,
    pub d: f64,
    /// How many bolts' thunder it is (a wave's heard together), and the nearest's size (`size_db`).
    pub bolts: u32,
    pub size_db: f64,
}
/// The bolts' thunder at the player `me` (the target's middle at `c`), in the order it reaches them: late by the
/// distance, a crack, a clap or a rumble by it (`thunder_of`), its level by it (`thunder_db`) and by the bolt's size
/// (`size_db`: the flurry's quieter, so the storm's thunder grows with its bolts). None heard in `quiet`
/// (the finale's own run-in and crack: its file holds the last waves' cracks, stacked). Two never start within 0.15 s of
/// each other: one due sooner after the last is heard in it, the two as one louder clap (their power added, the nearer's
/// crack), as a wave of bolts striking together is, so as the waves grow the claps come thick and loud rather than
/// flamming or falling behind. One heard while louder thunder still rolls is let down a little, never more than 4.4 dB
/// (the waves' close cracks come thick enough to pile up past full scale otherwise), so a fast run stays a run of claps.
pub(super) fn sc_thunder(seed: u32, bolts: &[Bolt], me: [f64; 3], c: [f64; 3], quiet: (f32, f32)) -> Vec<Heard> {
    let mut order: Vec<(f32, f64, usize)> = bolts
        .iter()
        .enumerate()
        .map(|(i, b)| {
            let (late, d) = sound_from([c[0] + b.x, c[1], c[2] + b.z], me);
            (b.t + late, d, i)
        })
        .filter(|(at, _, _)| *at < quiet.0 || *at > quiet.1)
        .collect();
    order.sort_by(|a, b| a.0.total_cmp(&b.0));
    // (the claps: when, the nearest bolt's distance and which it is, their power together, how many)
    let mut claps: Vec<(f32, f64, usize, f64, u32)> = Vec::new();
    for (at, d, i) in order {
        let p = 10f64.powf((thunder_db(d) + size_db(bolts[i].t)) / 10.0);
        match claps.last_mut() {
            Some(last) if at - last.0 < 0.15 => {
                if d < last.1 {
                    (last.1, last.2) = (d, i);
                }
                last.3 += p;
                last.4 += 1;
            }
            _ => claps.push((at, d, i, p, 1)),
        }
    }
    let mut takes = Takes::default();
    let mut rolling: Vec<(f32, f32)> = Vec::new();
    let mut out = Vec::new();
    for (at, d, i, power, n) in claps {
        let (kind, k, level) = thunder_of(d);
        // (a clap of several as loud as their power together, the nearest's crack heard)
        let db = 10.0 * power.log10();
        let loud = 10f64.powf(db / 20.0) as f32;
        let busy: f32 = rolling.iter().map(|(t, l)| l * (-(at - t).max(0.0) / 1.2).exp()).sum();
        // (and, however loud it is itself, a little while the thunder before it still rolls loud: the close cracks of the
        // waves would pile up past full scale)
        let full = 10f64.powf(thunder_db(0.0) / 20.0) as f32;
        let duck = (1.0 / (1.0 + 0.6 * busy / loud)).min(1.0 / (1.0 + 0.2 * busy / full)).max(0.6);
        rolling.push((at, loud * duck));
        let take = takes.pick(kind, k, mh(i as u32, seed, 0xd2));
        out.push(Heard {
            at,
            event: format!("{kind}{take}"),
            volume: (10f64.powf((db - level) / 20.0) as f32).min(1.0) * duck,
            pitch: 0.9 + 0.16 * mh(i as u32, seed, 0xd1) as f32,
            d,
            bolts: n,
            size_db: size_db(bolts[i].t),
        });
    }
    out
}

pub(super) fn supercell_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let s = shader_seed as u32;
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let mer = [me[0] - cx, me[2] - cz];
    let len = laser.length;

    // ---- the pass's table, and the ground under the bolts and the funnels asked of the world, put in when answered
    // (and again a little later, for land that loads as it goes) -------------------------------------------------------
    p.later(0.05, move |q| q.ev.push((0.05, Act::Table(sc_table(s, mer, &|_, _| None)))));
    for (ask, put) in [(0.1f32, 1.0f32), (5.0, 6.5), (12.0, 13.5)] {
        let tag = crate::ground::new_tag();
        p.later(ask, move |q| {
            let columns = sc_columns(s, mer, q.bx, q.bz);
            q.ev.push((ask, Act::Survey { tag, columns }));
        });
        p.later(put, move |q| {
            let (bx, by, bz) = (q.bx, q.by, q.bz);
            let w = sc_table(s, mer, &|x, z| ground_dy(bx, by, bz, x, z));
            q.ev.push((put, Act::Words { index: 0, words: w }));
        });
    }

    // ---- the build-up: the sky darkening, the wind, thunder far off ---------------------------------------------------
    p.csound(0.0, "buildup", 10.0, 1.0);
    // (the wind and the rain a bed under the thunder: each clap stands out of them)
    for (i, t) in [4.5f32, 15.0, 25.0].iter().enumerate() {
        p.csound(*t, "gusts", [5.0, 5.5, 5.0][i], 1.0);
    }
    for (i, t) in [4.0f32, 13.0, 22.0].iter().enumerate() {
        p.csound(*t, "rain", [4.5, 6.0, 6.0][i], 1.0);
    }

    // ---- the bolts ------------------------------------------------------------------------------------------------------
    let bolts = sc_bolts(s, mer);
    for b in &bolts {
        let (x, z) = ((cx + b.x).floor() as i32, (cz + b.z).floor() as i32);
        // (with the terrain on, what stands at its foot hurt as by a vanilla bolt, its foot set alight with its pit (`pit`):
        // its fires left burning, to burn out or spread as fire does)
        if terrain {
            p.at(b.t, format!("execute positioned {x} 0 {z} positioned over motion_blocking as @e[type=!minecraft:player,distance=..3.5] run damage @s 5 minecraft:lightning_bolt"));
        }
        p.at(b.t + 0.6, format!("execute positioned {x} 0 {z} positioned over motion_blocking_no_leaves run particle minecraft:large_smoke ~0.5 ~0.5 ~0.5 1 0.6 1 0.02 14 force"));
        if terrain {
            let t = b.t;
            p.later(t - 0.4, move |q| {
                let mut e = Blocks::default();
                let rp = 1.4 + 1.2 * q.rng.next();
                let rc = 3.5 + 2.0 * q.rng.next();
                let mut rng = Rng::new((x as u64) << 32 ^ z as u32 as u64 ^ u64::from(s));
                pit(&mut e, &mut rng, x, z, rp, rc, s);
                // (its foot and a few blocks round it set alight, as a vanilla bolt's, and left burning)
                for k in 0..4u32 {
                    let (dx, dz) = if k == 0 { (0, 0) } else { ((rng.next() * 3.0) as i32 - 1, (rng.next() * 3.0) as i32 - 1) };
                    put_on(&mut e, x + dx, z + dz, 0, 0, "minecraft:fire", Some("minecraft:air"), horizon_mod_sdk::world::Heightmap::MotionBlocking);
                }
                q.ev.push((t + 0.1, Act::Blocks(Box::new(e))));
            });
        }
    }
    // (their thunder, in the order it reaches the player; the run-in's in the finale's own sound, its cracks in time with
    // them (`FIN_RUN`), none of the waves' heard over them)
    let (late, dist) = sound_from([cx, gy, cz], me);
    let arrive = SC_FINALE + 0.05 + late;
    let waves = bolts.iter().take_while(|b| b.t < SC_STORM1).count();
    let heard = sc_thunder(s, &bolts[..waves], me, [cx, gy, cz], (arrive - FIN_PRE + 0.1, arrive + 3.0));
    for h in &heard {
        p.csound(h.at, &h.event, 10.0 * h.volume, h.pitch);
        if h.d < 120.0 {
            p.shake(h.at, (0.25 * (1.0 - h.d / 120.0)) as f32 + 0.05, 0.5);
        }
    }

    // ---- the flickers in the cloud: thunder far off for about half of them, under the bolts' (none rolling into the
    // finale's crack, nor within 0.4 s of a bolt's: each clap heard on its own) ---------------------------------------------
    let mut takes = Takes::default();
    for (i, k) in sc_flickers(s).iter().enumerate() {
        if i % 2 == 0 {
            let (late, d) = sound_from([cx + f64::from(k[1]), gy + 100.0, cz + f64::from(k[2])], me);
            let at = k[0] + late;
            if (at > arrive - FIN_PRE - 4.0 && at < arrive + 3.0) || heard.iter().any(|h| (h.at - at).abs() < 0.4) {
                continue;
            }
            let v = 10f64.powf((thunder_db(d) - 6.0 - RUMBLE_DB) / 20.0).min(0.9) as f32;
            let take = takes.pick("rumble", 5, mh(i as u32, s, 0xd3));
            p.csound(at, &format!("rumble{take}"), 10.0 * v, 0.9 + 0.2 * mh(i as u32, s, 0xd0) as f32);
        }
    }

    // ---- the funnels: their roar where they are, and with the terrain on, their tracks scoured ---------------------------
    for (k, f) in sc_funnels(s).into_iter().enumerate() {
        let f = Rc::new(f);
        let fr = f.clone();
        p.later(f.t0 as f32 - 0.5, move |q| {
            let (bx, by, bz) = (q.bx, q.by, q.bz);
            let track = vortex::ground_track(&fr.path, |x, z| ground_dy(bx, by, bz, x, z));
            vortex::roar(q, &fr, "orbital:supercell.roar", [cx, gy, cz], &track);
        });
        if terrain {
            let seen: Rc<std::cell::RefCell<crate::ground::FxSet<(i32, i32)>>> = Default::default();
            let per = 8;
            for k0 in (0..f.path.len()).step_by(per) {
                let (f, seen) = (f.clone(), seen.clone());
                let t = (f.t0 + k0 as f64 * vortex::VX_DT) as f32 - 0.6;
                p.later(t, move |q| {
                    let (bx, bz) = (q.bx, q.bz);
                    vortex::scour(q, &f, k0, k0 + per, bx, bz, s ^ (k as u32 * 977), &mut seen.borrow_mut());
                });
            }
        }
    }

    // ---- the finale: the bolts collapsing into one colossal strike on the target, a shockwave and a jolt ------------------
    let tf = SC_FINALE;
    // (heard and felt late by the distance: its run-in of the last waves' cracks stacking up, the ground trembling more
    // and more as the bolts draw in; the storm's beds cut under its last cracks, a hush, then the crack and the blast
    // out of silence, the jolt and the push with it; the rain and the wind coming back under its tail)
    // (the two cross-faded at constant power: half way, 500 blocks off, still nearly as loud as close by)
    let far = fc_far(dist);
    if far < 1.0 {
        p.csound(arrive - FIN_PRE, "finale", 10.0 * (1.0 - far).sqrt(), 1.0);
    }
    if far > 0.0 {
        p.csound(arrive - FIN_PRE, "finale_far", 10.0 * far.sqrt() * ((1.25 / (1.0 + dist / 2000.0)).min(1.0) as f32), 1.0);
    }
    for e in sc_beds() {
        p.at(arrive - FIN_CUT, format!("stopsound @s * {e}"));
    }
    p.csound(arrive + 0.9, "after", 5.5, 1.0);
    let fo = (2.0 / (1.0 + dist / 400.0)).clamp(0.3, 1.0) as f32;
    let mut tq = SC_CONV + late;
    while tq < arrive - FIN_SUCK {
        let u = (tq - SC_CONV - late) / (arrive - SC_CONV - late);
        p.shake(tq, (0.05 + 0.25 * u * u) * fo, 0.3f32.min(arrive - FIN_SUCK + 0.05 - tq));
        tq += 0.25;
    }
    fc_jolt(&mut p, arrive, fo);
    p.ev.push((arrive, Act::Shove { from: [cx, gy, cz], out: 0.7, up: 0.5, reach: 450.0 }));
    p.at(tf + 0.1, format!("particle minecraft:explosion_emitter {cx:.1} {:.1} {cz:.1} 12 3 12 0 14 force", gy + 1.0));
    p.at(tf + 0.15, format!("particle minecraft:large_smoke {cx:.1} {:.1} {cz:.1} 20 4 20 0.08 500 force", gy + 2.0));
    p.at(tf + 0.2, format!(r#"particle minecraft:block{{block_state:"minecraft:blackstone"}} {cx:.1} {:.1} {cz:.1} 18 3 18 1.4 900 force"#, gy + 2.0));
    p.at(tf + 0.3, format!("particle minecraft:electric_spark {cx:.1} {:.1} {cz:.1} 25 4 25 0.6 600 force", gy + 2.0));
    for k in [0.15f32, 1.5, 4.0] {
        p.at(tf + k, format!("execute positioned {cx:.1} {gy} {cz:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{FC_KILL}]"));
    }
    if terrain {
        // (its land worked out well ahead, a band a stage, going in with the front from the middle out)
        let veins: Rc<std::cell::RefCell<Option<crate::ground::FxMap<(i32, i32), u8>>>> = Default::default();
        {
            let v = veins.clone();
            p.later(tf - 8.0, move |_| *v.borrow_mut() = Some(fc_veins(s)));
        }
        for k in 0..FC_BANDS {
            let v = veins.clone();
            p.later(tf - 7.8 + 0.1 * k as f32, move |q| {
                let empty = Default::default();
                let g = v.borrow();
                fc_band(q, k, tf, s, g.as_ref().unwrap_or(&empty));
            });
        }
        p.later(tf - 0.5, move |q| fc_thrown(q, tf, s));
    }

    // ---- the storm dies away: the rain stops, the fires it left burning ------------------------------------------------------
    if terrain {
        let load = pk_load_rows([cx, gy, cz], 0.0, SC_SWEEP + 4.0);
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

#[cfg(test)]
mod table {
    /// `CB_SEED=37 CB_OUT=path PL_ME=x,y,z cargo test --release sc_write_table -- --ignored`: the table the pass reads, for
    /// tools/preview.py (a line `index value` a word), the target at the preview's (0.5 65 0.5) on flat land.
    #[test]
    #[ignore]
    fn sc_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let me: Vec<f64> = std::env::var("PL_ME").map_or(vec![0.0, 70.0, 300.0], |v| v.split(',').map(|x| x.parse().unwrap()).collect());
        // (SC_FOREST=1: the land a wood, trunks 9 high now and then, as the world's ground counts them; SC_RAW=1: the
        // funnels' feet on the ground right under them, unsmoothed, as they were before `ground_track`)
        let forest = std::env::var("SC_FOREST").is_ok_and(|v| v == "1");
        let ground = move |x: f64, z: f64| -> Option<f64> {
            let trunk = forest && (x.floor() as i64 * 7 + z.floor() as i64 * 13).rem_euclid(9) == 0;
            Some(if trunk { 9.0 } else { 0.0 })
        };
        let mut w = super::sc_table(seed as u32, [me[0] - 0.5, me[2] - 0.5], &ground);
        if std::env::var("SC_RAW").is_ok_and(|v| v == "1") {
            for (k, f) in super::sc_funnels(seed as u32).iter().enumerate() {
                let raw: Vec<f64> = f.path.iter().map(|p| ground(p[0], p[1]).unwrap_or(0.0)).collect();
                let words = super::vortex::vx_words(f, &raw);
                w[super::SC_F + super::VX_W * k..super::SC_F + super::VX_W * (k + 1)].copy_from_slice(&words);
            }
        }
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}

/// `SC_OUT=path SC_ME=z cargo test --release sc_write_sounds -- --ignored`: the sounds a player SC_ME blocks south of the
/// target hears (`t event volume pitch`, the roar's at their points' distance), for tools/sounds_storm.py's listening
/// mix (SC_TERRAIN=1: as planned with the terrain on).
#[cfg(test)]
#[test]
#[ignore]
fn sc_write_sounds() {
    let z: f64 = std::env::var("SC_ME").map_or(300.0, |v| v.parse().unwrap());
    let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
    let me = [0.5, 66.0, 0.5 + z];
    let laser = crate::lasers::LASERS.iter().find(|l| l.key == "supercell").unwrap();
    let terrain = std::env::var("SC_TERRAIN").is_ok_and(|v| v == "1");
    let mut ev = crate::strike::plan(laser, &target, terrain, "minecraft:overworld", 37.0, me, 0);
    let mut out = String::new();
    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
    while let Some((t, a)) = ev.pop() {
        match a {
            Act::Sound { event, at, volume, pitch } => {
                // (a positioned sound: as the game fades it, linearly to its range, 320 blocks)
                let v = at.map_or(volume, |p| volume * (1.0 - ((p[0] - me[0]).hypot(p[2] - me[2]) / 320.0).min(1.0)) as f32);
                out += &format!("{t:.3} {event} {v:.3} {pitch:.3}\n");
            }
            // (and the sounds the plan stops: `t stop event`)
            Act::Cmd(c) if c.starts_with("stopsound") => {
                out += &format!("{t:.3} stop {}\n", c.rsplit(' ').next().unwrap_or(""));
            }
            Act::Later(job) | Act::Cleanup(job) => {
                ev.extend(job());
                ev.sort_by(|a, b| b.0.total_cmp(&a.0));
            }
            _ => {}
        }
    }
    std::fs::write(std::env::var("SC_OUT").unwrap(), out).unwrap();
}

/// `cargo test --release sc_print_bolts -- --ignored --nocapture`: the bolts of seed 37 a second at a time (how many, the
/// most at once, how far out the farthest), for tuning the build-up.
#[cfg(test)]
#[test]
#[ignore]
fn sc_print_bolts() {
    let b = sc_bolts(37, [0.0, 300.0]);
    println!("{} bolts, the first {:.2}, the last {:.2}", b.len(), b[0].t, b[b.len() - 1].t);
    for s in 0..30 {
        let sec: Vec<&Bolt> = b.iter().filter(|x| x.t >= s as f32 && x.t < s as f32 + 1.0).collect();
        let once = sec.iter().map(|x| b.iter().filter(|y| y.t >= x.t && y.t < x.t + 0.12).count()).max().unwrap_or(0);
        let far = sec.iter().map(|x| x.x.hypot(x.z)).fold(0.0, f64::max);
        println!("{s:2} s: {:2} bolts, {once} at once, out to {far:5.1}", sec.len());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    fn the_laser() -> &'static Laser {
        crate::lasers::LASERS.iter().find(|l| l.key == "supercell").expect("the supercell")
    }
    fn played(terrain: bool, me: [f64; 3]) -> (Vec<(f32, Blocks)>, Vec<(f32, String)>, Vec<(f32, Act)>, usize) {
        crate::ground::clear();
        crate::ground::set_test(Some(|_, _| Some(65)));
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let mut ev = plan(the_laser(), &target, terrain, "minecraft:overworld", 37.0, me, 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let (mut blocks, mut cmds, mut other) = (Vec::new(), Vec::new(), Vec::new());
        let mut stages = 0;
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Survey { tag, columns } => crate::ground::test_answer(tag, &columns),
                Act::Blocks(b) => blocks.push((t, *b)),
                Act::Cmd(c) | Act::Spare(c) => cmds.push((t, c)),
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                    stages += 1;
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                a => other.push((t, a)),
            }
        }
        crate::ground::set_test(None);
        (blocks, cmds, other, stages)
    }

    #[test]
    fn supercell_strikes_its_bolts_under_its_cloud_without_vanillas_thunder() {
        let me = [10.5, 66.0, 297.5];
        let (_, cmds, other, _) = played(true, me);
        // (no vanilla bolt, whose own thunder can't be silenced in time: each bolt hurts what is at its foot instead)
        assert!(!cmds.iter().any(|(_, c)| c.contains("lightning_bolt ~")));
        // (the only sounds stopped the storm's own beds and thunder, all at once, right before the finale's crack reaches
        // the player: cut under its run-in's last cracks, so it lands out of a hush)
        let (late, _) = sound_from([10.5, 65.0, -2.5], me);
        let stops: Vec<&(f32, String)> = cmds.iter().filter(|(_, c)| c.starts_with("stopsound")).collect();
        assert_eq!(stops.len(), sc_beds().len());
        for (t, c) in &stops {
            assert!((*t - (SC_FINALE + 0.05 + late - FIN_CUT)).abs() < 1e-3 && c.starts_with("stopsound @s * orbital:supercell.") && !c.contains("finale"), "{t} {c}");
        }
        let bolts: Vec<&(f32, String)> = cmds.iter().filter(|(_, c)| c.contains("run damage @s 5 minecraft:lightning_bolt")).collect();
        let planned = sc_bolts(37, [0.0, 300.0]);
        assert_eq!(bolts.len(), planned.len());
        assert!(planned.len() > 80 && planned.len() <= SC_NB, "{}", planned.len());
        for (t, c) in &bolts {
            assert!(*t >= SC_STORM0 && *t < SC_FINALE - FIN_SUCK, "{t}");
            let w: Vec<f64> = c.split_whitespace().map(|v| v.parse().unwrap_or(0.0)).collect();
            assert!((w[2] - 10.5).hypot(w[4] + 2.5) < SC_REACH + 2.0, "{c}");
        }
        // (faster and faster: more in the storm's second half than its first)
        let mid = 0.5 * (SC_STORM0 + SC_STORM1);
        assert!(bolts.iter().filter(|(t, _)| *t > mid).count() > bolts.iter().filter(|(t, _)| *t < mid).count() + 10);
        // (each heard, a take of its own; the world's weather left alone; the pass's table given)
        let sounds: Vec<&str> = other.iter().filter_map(|(_, a)| if let Act::Sound { event, .. } = a { Some(event.as_str()) } else { None }).collect();
        // (a wave's heard together as one clap, the last waves' in the finale's run-in: fewer claps than bolts, but most)
        let claps = sounds.iter().filter(|e| e.contains("supercell.crack")).count();
        assert!(claps <= planned.len() && claps * 5 > planned.len() * 2, "{claps} of {}", planned.len());
        assert!(sounds.iter().any(|e| e.ends_with("supercell.finale")) && sounds.iter().any(|e| e.ends_with("supercell.roar")));
        assert!(!cmds.iter().any(|(_, c)| c.starts_with("weather")));
        assert!(other.iter().any(|(_, a)| matches!(a, Act::Table(w) if w.len() == SC_I + SC_NI)));
        assert!(other.iter().any(|(_, a)| matches!(a, Act::Shove { .. })));
        // (the finale near and the rain and the wind back under its tail after the cut)
        let at = |name: &str| other.iter().find_map(|(t, a)| matches!(a, Act::Sound { event, .. } if event.ends_with(name)).then_some(*t));
        assert!(at("supercell.after").unwrap() > stops[0].0 + 0.5);
        // (300 blocks off: mostly the near one, a little of the far one in it)
        let vol = |name: &str| other.iter().find_map(|(_, a)| if let Act::Sound { event, volume, .. } = a { event.ends_with(name).then_some(*volume) } else { None });
        assert!(at("supercell.finale").is_some() && vol("supercell.finale").unwrap() > 0.95 && vol("supercell.finale_far").unwrap() < 0.2);
    }

    #[test]
    fn supercell_finale_far_off_is_the_far_one() {
        // (heard 900 blocks off: all of it the far finale, the beds still cut)
        let me = [0.5, 66.0, 900.5];
        let (_, cmds, other, _) = played(false, me);
        let sounds: Vec<(&str, f32)> = other.iter().filter_map(|(_, a)| if let Act::Sound { event, volume, .. } = a { Some((event.as_str(), *volume)) } else { None }).collect();
        assert!(!sounds.iter().any(|(e, _)| e.ends_with("supercell.finale")));
        assert!(sounds.iter().any(|(e, v)| e.ends_with("supercell.finale_far") && *v > 0.6));
        assert_eq!(cmds.iter().filter(|(_, c)| c.starts_with("stopsound")).count(), sc_beds().len());
    }

    #[test]
    fn supercell_thunder_is_late_by_the_distance_its_takes_never_repeat_and_it_never_flams() {
        for z in [20.0, 150.0, 500.0] {
            let me = [0.5, 66.0, 0.5 + z];
            let bolts = sc_bolts(37, [0.0, z]);
            let heard = sc_thunder(37, &bolts, me, [0.5, 65.0, 0.5], (1.0e9, 1.0e9));
            assert!(heard.len() <= bolts.len() && heard.len() * 5 > bolts.len() * 2, "{} of {}", heard.len(), bolts.len());
            assert_eq!(heard.iter().map(|h| h.bolts as usize).sum::<usize>(), bolts.len());
            for w in heard.windows(2) {
                // (in the order heard, never two starting together, never the same take twice running)
                assert!(w[1].at - w[0].at >= 0.149, "{} {}", w[0].at, w[1].at);
                assert_ne!(w[0].event, w[1].event);
            }
            for w in heard.windows(3) {
                let kind = |e: &str| e.trim_end_matches(char::is_numeric).to_string();
                if kind(&w[0].event) == kind(&w[2].event) {
                    assert_ne!(w[0].event, w[2].event);
                }
            }
            for h in &heard {
                // (no sooner than the sound could come, a crack only close by, a rumble only far off)
                let b = bolts.iter().map(|b| (b.t + (h.d / 343.0) as f32 - h.at).abs()).fold(f32::MAX, f32::min);
                assert!(b < 0.5, "{h:?}");
                assert!(h.event.starts_with(thunder_of(h.d).0) && h.volume > 0.05 && h.volume <= 1.0, "{h:?}");
                assert!((0.89..1.07).contains(&h.pitch));
            }
            // (and louder the nearer: the nearest lone bolt's crack louder than the farthest's)
            let near = heard.iter().filter(|h| h.bolts == 1).min_by(|a, b| a.d.total_cmp(&b.d)).unwrap();
            let far = heard.iter().filter(|h| h.bolts == 1).max_by(|a, b| a.d.total_cmp(&b.d)).unwrap();
            let loud = |h: &Heard| 20.0 * f64::from(h.volume).log10() + thunder_of(h.d).2 - h.size_db;
            // (by the distance's fall-off, less at most the 4.4 dB a crack is let down while louder thunder rolls)
            assert!(loud(near) - loud(far) > thunder_db(near.d) - thunder_db(far.d) - 4.5, "{near:?} {far:?}");
            assert!(thunder_db(near.d) > thunder_db(far.d) + 1.0);
        }
    }

    #[test]
    fn supercell_bolts_build_from_a_lone_flurry_to_waves_that_draw_in_onto_the_target() {
        for seed in [37, 5, 911] {
            let b = sc_bolts(seed, [0.0, 300.0]);
            // (the most striking within 0.12 s of one: one in the flurry, SC_CAP by the end)
            let at_once = |t0: f32, t1: f32| {
                b.iter().filter(|x| x.t >= t0 && x.t < t1).map(|x| b.iter().filter(|y| y.t >= x.t && y.t < x.t + 0.12).count()).max().unwrap_or(0)
            };
            assert_eq!(at_once(SC_STORM0, SC_WAVES - 0.5), 1, "{seed}");
            assert!(at_once(SC_WAVES, SC_WAVES + 3.0) <= 3, "{seed}");
            assert!((SC_CAP..=SC_CAP + 2).contains(&at_once(SC_CONV, SC_STORM1)), "{seed}: {}", at_once(SC_CONV, SC_STORM1));
            // (coming faster: each third of the flurry has more than the one before; the first early, near the start)
            assert!(b[0].t < SC_STORM0 + 0.5);
            let third = (SC_WAVES - SC_STORM0) / 3.0;
            let n = |k: f32| b.iter().filter(|x| x.t >= SC_STORM0 + k * third && x.t < SC_STORM0 + (k + 1.0) * third).count();
            assert!(n(0.0) < n(2.0) && n(0.0) <= n(1.0) && n(1.0) <= n(2.0) + 1, "{seed}: {} {} {}", n(0.0), n(1.0), n(2.0));
            assert!(b.len() < SC_NB, "{seed}: the table's room all taken");
            // (no pause before the finale: the last wave within 0.7 s of it, hugging the target, and the waves drawn in
            // all through the last seconds)
            let last = b.last().unwrap();
            assert!(last.t > SC_FINALE - 0.7 && last.t < SC_FINALE, "{seed}: {}", last.t);
            for x in b.iter().filter(|x| x.t > SC_FINALE - 0.6) {
                assert!(x.x.hypot(x.z) < 16.0, "{seed}: {x:?}");
            }
            let far = |t0: f32, t1: f32| b.iter().filter(|x| x.t >= t0 && x.t < t1).map(|x| x.x.hypot(x.z)).fold(0.0, f64::max);
            assert!(far(SC_CONV - 3.0, SC_CONV) > 90.0 && far(SC_STORM1 - 2.0, SC_STORM1 - 1.0) < 60.0, "{seed}");
            for w in b.windows(2) {
                let most = if w[0].t > SC_CONV { 0.6 } else if w[0].t > SC_WAVES { 0.8 } else { 2.2 };
                assert!(w[1].t - w[0].t < most, "{seed}: a pause at {}", w[0].t);
            }
            // (the run-in: after the waves, a bolt or a few on each of its sound's cracks, then nothing in the hush; drawn
            // in closer and closer, the last right round the target)
            let run: Vec<&Bolt> = b.iter().filter(|x| x.t > SC_STORM1).collect();
            assert_eq!(FIN_RUN.iter().map(|r| r.1 as usize).sum::<usize>(), FIN_RUN_N);
            assert_eq!(run.len(), FIN_RUN_N, "{seed}");
            for &(at, n) in &FIN_RUN {
                let on: Vec<&&Bolt> = run.iter().filter(|x| x.t - SC_FINALE - at > -1e-4 && x.t - SC_FINALE - at < 0.02).collect();
                assert_eq!(on.len(), n as usize, "{seed}: {at}");
            }
            assert!(run.iter().all(|x| x.t < SC_FINALE - FIN_SUCK - 0.015), "{seed}");
            let mean = |v: &[&Bolt]| v.iter().map(|x| x.x.hypot(x.z)).sum::<f64>() / v.len() as f64;
            assert!(mean(&run[..5]) > 2.5 * mean(&run[run.len() - 5..]), "{seed}");
            assert!(run[run.len() - 9..].iter().all(|x| x.x.hypot(x.z) < 6.1), "{seed}");
        }
    }

    #[test]
    fn supercell_leaves_the_land_alone_with_the_terrain_off() {
        let (blocks, cmds, _, _) = played(false, [10.5, 66.0, 297.5]);
        assert!(blocks.is_empty());
        for (_, c) in &cmds {
            assert!(!c.contains("forceload") && !c.contains("summon"), "{c}");
        }
    }

    #[test]
    fn supercell_pits_are_small_its_finale_crater_is_70_across_and_its_fires_burn_on() {
        let (blocks, cmds, _, _) = played(true, [10.5, 66.0, 297.5]);
        let fills: Vec<(f32, String)> = blocks.iter().flat_map(|(t, b)| b.as_fills().into_iter().map(move |f| (*t, f))).collect();
        // nothing that flows or burns placed; the digs a couple of blocks deep at a bolt, at most 6 at the finale
        for (_, f) in &fills {
            for bad in ["lava", "water", " minecraft:fire", "coal_block"] {
                assert!(!f.contains(bad) || f.contains(" replace "), "{f}");
            }
        }
        let crater: Vec<&(f32, String)> = fills.iter().filter(|(t, f)| (*t - SC_FINALE).abs() < 0.5 && f.contains("~ minecraft:air strict")).collect();
        let reach = crater
            .iter()
            .map(|(_, f)| {
                let w: Vec<f64> = f.split_whitespace().map(|v| v.parse().unwrap_or(0.0)).collect();
                (w[2] - 10.0).hypot(w[4] + 3.0)
            })
            .fold(0.0, f64::max);
        assert!(reach > 32.0 && reach < 40.0, "the crater reaches {reach}");
        // (and digs about FC_D deep in the middle, its front going out from the middle)
        let deepest = crater.iter().map(|(_, f)| f.split_whitespace().nth(11).and_then(|v| v.trim_start_matches('~').parse::<i32>().ok()).unwrap_or(0)).min().unwrap();
        assert!(deepest <= -(FC_D as i32) + 1, "{deepest}");
        // (the fulgurites: glass veins out through the ground well past the crater, an overturned rim, fires set)
        let far_glass = fills.iter().filter(|(_, f)| f.contains("glass") && !f.contains("replace")).filter(|(_, f)| {
            let w: Vec<f64> = f.split_whitespace().map(|v| v.parse().unwrap_or(0.0)).collect();
            (w[2] - 10.0).hypot(w[4] + 3.0) > 50.0
        }).count();
        assert!(far_glass > 40, "{far_glass}");
        assert!(fills.iter().any(|(t, f)| (*t - SC_FINALE).abs() < 1.0 && f.contains("minecraft:fire replace minecraft:air")));
        // (its fires left burning: nothing puts them out)
        assert!(!fills.iter().any(|(_, f)| f.contains("replace #minecraft:fire")));
        // (the chunks it works in forceloaded and let go)
        assert!(cmds.iter().any(|(_, c)| c.starts_with("forceload add")) && cmds.iter().any(|(_, c)| c.starts_with("forceload remove")));
        // (the funnels' tracks scoured: plants and leaves only, and a few blocks thrown)
        assert!(fills.iter().filter(|(_, f)| f.contains("replace #minecraft:leaves")).count() > 300);
        assert!(cmds.iter().filter(|(_, c)| c.contains("summon minecraft:falling_block")).count() >= 10);
    }

    #[test]
    fn supercell_stages_are_light() {
        // (each stage's work, on the meter, well under a tick's: the tests' stages reset it as on a tick of their own)
        crate::ground::clear();
        crate::ground::set_test(Some(|_, _| Some(65)));
        let target = Target { block: [-1041, 64, 860], point: [-1040.5, 65.0, 860.5] };
        let mut ev = plan(the_laser(), &target, true, "minecraft:overworld", 19.0, [-1040.5, 70.0, 1160.5], 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut worst = (0u64, 0.0f32, 0usize);
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Survey { tag, columns } => crate::ground::test_answer(tag, &columns),
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
        crate::ground::set_test(None);
        eprintln!("heaviest stage: {:.2}M at {:.2} s ({} acts)", worst.0 as f64 / 1e6, worst.1, worst.2);
        assert!(worst.0 < crate::meter::SOFT * 3 / 4, "a stage of {:.2}M at {:.2} s", worst.0 as f64 / 1e6, worst.1);
    }

    #[test]
    fn supercell_table_holds_its_bolts_and_funnels_where_the_pass_reads_them() {
        let w = sc_table(37, [0.0, 300.0], &|_, _| Some(2.0));
        let b = sc_bolts(37, [0.0, 300.0]);
        assert_eq!(f32::from_bits(w[0]) as usize, b.len());
        assert!(SC_B + SC_BW * SC_NB <= SC_F && SC_F + VX_W * SC_NF <= SC_K && SC_K + 3 * SC_NK <= SC_I);
        // (the bolts in the order they strike, and each second's first still seen: none before it seen at that second)
        assert!(b.windows(2).all(|p| p[0].t <= p[1].t));
        for s in 0..SC_NI {
            let first = w[SC_I + s] as usize;
            assert!(b[..first].iter().all(|x| x.t <= s as f32 - 1.1) && b[first..].iter().all(|x| x.t > s as f32 - 1.1), "{s}");
        }
        assert_eq!(f32::from_bits(w[SC_B + SC_BW * 5]), b[5].t);
        assert_eq!(f32::from_bits(w[SC_B + SC_BW * 5 + 3]), 2.0);
        let f = sc_funnels(37);
        assert_eq!(f32::from_bits(w[SC_F + VX_W]) as f64, f[1].t0 as f32 as f64);
        // (the funnels overlap through the storm, all touching down before the finale)
        assert!(f.iter().all(|f| f.t1 < f64::from(SC_FINALE) && f.t0 > f64::from(SC_STORM0)));
    }
}

/// The plan as it is made on the fire tick stays light (`meter`): what is heavy waits for stages of its own.
#[cfg(test)]
#[test]
fn sc_fire_cost() {
    crate::ground::clear();
    let laser = crate::lasers::LASERS.iter().find(|l| l.key == "supercell").unwrap();
    let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
    for terrain in [false, true] {
        crate::meter::reset();
        let t = std::time::Instant::now();
        let ev = crate::strike::plan(laser, &target, terrain, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let spent = crate::meter::spent();
        println!("terrain {terrain}: plan {:.2}M on the meter, {:?}, {} acts", spent as f64 / 1e6, t.elapsed(), ev.len());
        assert!(spent < 2_000_000, "the plan took {:.2}M", spent as f64 / 1e6);
    }
}
