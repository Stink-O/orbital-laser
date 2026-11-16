//! The Convergence's plan: the Nether breaks out of the ground under the target, the Aether out of the sky over it,
//! their columns of energy meet over the target, struggle, and end in one huge blast that leaves a crater split down
//! the middle between the two (built on strike/rod.rs: its land read, wave, felled trees, rubble and thrown blocks).
//!
//! The beats (strike seconds; the pass, shaders/convergence.wgsl, keeps the same in its `cv_*` constants):
//! CV_OMEN (0) the ground trembles, the ground fractures out from the target (drawn by the pass: no block changes before the break), a seam of light opens high
//! over it; CV_BREAK (5) the cracks open into fissures, fire and ash rushing out of them, netherrack creeps out along
//! veins, basalt columns shoulder up, a fountain of fire stands out of the ground while the seam tears into a rift with
//! a stub of light under it; CV_CROUCH (12.33) both gather their light; CV_FIRE (12.45) two columns race at each other, at speed at once; CV_MEET (13)
//! they strike in the air over the target (`cv_meet_y`: a shell out from the point, a jolt as it reaches the player) and
//! shove each other up and down, each surge (CV_SURGES) a smaller shell and a jolt; the land takes sides, one half going Nether, the other pale (the seam between them
//! along the bearing `cv_seam`); CV_DRAW (23) the meeting point tightens and drops; CV_HIT (26) the blast: one huge
//! burst on the target, a double front over the land, the player thrown back, the crater dug as the front passes;
//! CV_CLOSE (31) to CV_END (40) the aftermath: the crater split down the middle (half Nether, half pale, a seam of
//! obsidian between), a few small islands of real blocks left hanging in the sky over it (`cv_islands`), the rift
//! closing.
//!
//! What it leaves is real blocks: a crater about cr() * 2 across and cdp() deep, its rim heaped out to
//! cr() * CV_RIM, the land flattened (trees felled) out to CV_FLAT, a band past it of stripped crowns, the
//! grass turned (Nether one side, pale the other) out to cv_char(), rubble to CV_RUBBLE, mobs and items killed within
//! CV_KILL; all of it as one wave from the middle out (Wave, cv_work), as the Rod's.
//!
//! Sounds (`cv_sounds`): its own layers (tools/sounds_convergence.py) in three distance tiers, the beats on the
//! picture's clock, each explosion's hit on the picture's frame; the blast's sequence (the drive cut before it, the
//! wall, stunned to the tear, the tear as the second release); over it hell (a voice, a furnace) and heaven (a choir,
//! the rift's thunder); what burns, roars, sings or rolls from CC0 recordings (NOTICE).
#![cfg_attr(not(test), allow(dead_code))] // (some of the CV_* the pass mirrors are read only by the tests)
use super::{Act, Blocks, Col, Plan, Rng, TIDY_BORDER, Target, falloff, mh, pk_load_rows, sound_from, tidy, vnoise};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;

// ---- the shared clock and geometry (shaders/convergence.wgsl's `cv_*` block mirrors every one) -----------------------
/// The beats, strike seconds.
pub(super) const CV_OMEN: f32 = 0.0;
pub(super) const CV_BREAK: f32 = 5.0;
/// The red column starts climbing and the gold one coming down (both reach the meeting point at CV_MEET).
pub(super) const CV_RED0: f32 = 6.0;
pub(super) const CV_GOLD0: f32 = 7.5;
/// Both gather their light over CV_CROUCH..CV_FIRE (neither draws back), then race at each other and strike in the
/// air at CV_MEET.
pub(super) const CV_CROUCH: f32 = 12.33;
pub(super) const CV_FIRE: f32 = 12.45;
pub(super) const CV_MEET: f32 = 13.0;
pub(super) const CV_DRAW: f32 = 23.0;
/// The blast (the Rod's RD_HIT: the wave, the knockback and the blast's sounds key off it).
pub(super) const CV_HIT: f32 = 26.0;
pub(super) const CV_CLOSE: f32 = 31.0;
pub(super) const CV_END: f32 = 40.0;
/// The surges of the clash: each shoves the meeting point (up for the Nether, down for the Aether: CV_SURGE_SIGN),
/// sends a shell out from it (its knock and its sound timed at CV_RING_V blocks a second) and jolts the camera as it
/// reaches the player.
pub(super) const CV_SURGES: [f32; 6] = [14.4, 16.2, 17.6, 19.4, 20.9, 22.2];
pub(super) const CV_SURGE_SIGN: [f32; 6] = [1.0, -1.0, 1.0, -1.0, 1.0, -1.0];
/// How far each shoves the meeting point (blocks) and how heavily (seconds): the pass's cv_surge_amp and
/// cv_surge_atk.
pub(super) const CV_SURGE_AMP: [f64; 6] = [22.0, 34.0, 18.0, 40.0, 28.0, 26.0];
pub(super) const CV_SURGE_ATK: [f64; 6] = [0.16, 0.12, 0.28, 0.11, 0.22, 0.14];
pub(super) const CV_RING_V: f64 = 160.0;
/// Heights over the target's ground: where the columns meet, the rift's plane, the burst.
pub(super) const CV_MEET_Y: f64 = 130.0;
pub(super) const CV_RIFT_Y: f64 = 260.0;
pub(super) const CV_RIFT_R: f64 = 80.0;
pub(super) const CV_BURST: f64 = 14.0;
/// Before they fire: how high the fire's fountain stands, how far the light hangs under the rift (the LOWs the same:
/// neither draws back); the impact's shell in the air, blocks a second (its jolt keys off it).
pub(super) const CV_RED_STUB: f64 = 30.0;
pub(super) const CV_RED_LOW: f64 = 30.0;
pub(super) const CV_GOLD_STUB: f64 = 36.0;
pub(super) const CV_GOLD_LOW: f64 = 36.0;
pub(super) const CV_IMPACT_V: f64 = 240.0;
/// The table the pass reads (Act::Table, render.set-data from word 0): CV_FR words. Word 0 CV_MAGIC (so the pass can
/// tell it is in), 1 the seam's bearing (radians, x towards east, z south: the Nether half is the bearings within PI
/// past it), 2 the seed; 3..15 free; from CV_CRK the cracks (`cv_crack_words`); 31..47 kept for tables written each tick; from CV_SPR the block sprites the sky's
/// islands are textured with (`cv_sprites`); 54..63 free; from CV_ISL the islands grown in the sky (`cv_islands`).
pub(super) const CV_FR: usize = CV_CRH + 1 + CV_CRH_N * CV_CRACKS as usize;
/// Word CV_CRH: 1.0 once the land's heights along the cracks are in (a few ticks after it fires: `cv_crack_step`);
/// then CV_CRH_N words a crack (crack k's from CV_CRH + 1 + CV_CRH_N * k): the land's height over the target's ground
/// at r = j * CV_CRACK_R / (CV_CRH_N - 1) out along it. The pass stands the cracks' fire on them.
pub(super) const CV_CRH: usize = CV_ISL + 1 + 5 * 16;
pub(super) const CV_CRH_N: usize = 6;
/// Word CV_ISL: how many islands; then 5 words each: dx, dz from the target (blocks), height of its top over the
/// target's ground (blocks; the land may raise it to clear a hill under it), radius (blocks), when it starts to grow
/// (strike seconds; its top whole CV_GROW_STEP * 3 later, its underside some 5 s after that).
pub(super) const CV_ISL: usize = 64;
/// Words CV_CRK..+7 the cracks' base bearings (radians), +7..+14 their reaches (blocks), +14 7.0 once filled: each
/// crack k runs out along `bearing_k + 0.16 sin(0.09 r + 1.7 k) + 0.06 sin(0.31 r + k)` at r blocks out (`cv_crack`).
pub(super) const CV_CRK: usize = 16;
/// Word CV_SPR: 1.0 once the sprites are in; CV_SPR + 1.. the atlas layers (u32) of CV_SPRITES' top faces, in order.
pub(super) const CV_SPR: usize = 48;
pub(super) const CV_SPRITES: [&str; 5] = ["minecraft:grass_block", "minecraft:calcite", "minecraft:sand", "minecraft:oak_leaves", "minecraft:diorite"];
pub(super) const CV_MAGIC: f32 = 7171.0;

/// How high over the target's ground the meeting point is at strike second `t` (shaders/convergence.wgsl's
/// `cv_meet_y`, step for step): CV_MEET_Y as they meet, driven up toward the rift by the Nether's surges, drawn down to
/// CV_BURST over CV_DRAW..CV_HIT, accelerating; CV_BURST from then on.
pub(super) fn cv_meet_y(t: f64) -> f64 {
    // (one of the Nether's surges u seconds after it starts, as a share of its reach: from rest, to rest, no overshoot,
    // nothing given back: the pass's cv_shove)
    let shove = |u: f64, atk: f64| {
        if u <= 0.0 {
            0.0
        } else {
            let x = u / atk;
            1.0 - (1.0 + x) * (-x).exp()
        }
    };
    // (the little drift and the dip as they strike: the pass's cv_wander and cv_recoil)
    let wander = |t: f64| {
        let m = f64::from(CV_MEET);
        smooth01((t - m - 0.2) / 1.4) * (2.0 * (0.9 * t + 1.3).sin() + 1.2 * (2.3 * t + 4.1).sin() + 0.6 * (5.1 * t + 0.7).sin())
    };
    let recoil = |t: f64| {
        let u = t - f64::from(CV_MEET);
        if u <= 0.0 {
            0.0
        } else {
            let x = u / 0.09;
            -9.0 * (1.0 - (1.0 + x) * (-x).exp()) * (-u / 0.9).exp()
        }
    };
    // (one way only: the Nether's surges, the even ones, drive it up and keep what they take; the Aether's hold it)
    let clash = |t: f64| {
        let mut y = CV_MEET_Y + wander(t) + recoil(t);
        for i in (0..CV_SURGES.len()).step_by(2) {
            y += 0.75 * CV_SURGE_AMP[i] * shove(t - f64::from(CV_SURGES[i]), 2.5 * CV_SURGE_ATK[i]);
        }
        y
    };
    let (draw, hit) = (f64::from(CV_DRAW), f64::from(CV_HIT));
    if t < draw {
        clash(t)
    } else if t < hit {
        let u = (t - draw) / (hit - draw);
        clash(draw) + (CV_BURST - clash(draw)) * u * u * u
    } else {
        CV_BURST
    }
}
/// The race's snap (the pass's CV_SNAP): this share of its mean speed from the first instant.
const CV_SNAP: f64 = 0.6;
/// How far a column has come from its root at `t` (the pass's `cv_reach`, step for step): it stands `stub` out from
/// `t0`, holds `low` (the same: it never draws back) to CV_FIRE, then races (at CV_SNAP of its mean speed at once,
/// gathering more all the way) the `full` way by CV_MEET.
fn cv_reach(t: f64, t0: f32, stub: f64, low: f64, full: f64) -> f64 {
    let (crouch, fire, meet) = (f64::from(CV_CROUCH), f64::from(CV_FIRE), f64::from(CV_MEET));
    if t >= fire {
        let u = ((t - fire) / (meet - fire)).clamp(0.0, 1.0);
        low + (full - low) * (CV_SNAP * u + (1.0 - CV_SNAP) * u.powf(2.4))
    } else if t >= crouch {
        let u = (t - crouch) / (fire - crouch);
        stub + (low - stub) * u * u * (3.0 - 2.0 * u)
    } else {
        let u = ((t - f64::from(t0)) / (crouch - f64::from(t0))).clamp(0.0, 1.0);
        stub * (1.0 - (1.0 - u).powi(3))
    }
}
/// The red column's top over the target's ground at `t` (none before CV_RED0), the gold column's foot (the rift's
/// plane before CV_GOLD0): a fountain and a stub of light until CV_FIRE, then both race onto the meeting point.
pub(super) fn cv_red_top(t: f64) -> f64 {
    if t >= f64::from(CV_MEET) {
        return cv_meet_y(t);
    }
    cv_reach(t, CV_RED0, CV_RED_STUB, CV_RED_LOW, CV_MEET_Y)
}
pub(super) fn cv_gold_foot(t: f64) -> f64 {
    if t >= f64::from(CV_MEET) {
        return cv_meet_y(t);
    }
    CV_RIFT_Y - cv_reach(t, CV_GOLD0, CV_GOLD_STUB, CV_GOLD_LOW, CV_RIFT_Y - CV_MEET_Y)
}
/// The seam's bearing for a strike seeded `seed`: the Nether half lies within PI past it (`cv_side`).
pub(super) fn cv_seam(seed: u32) -> f64 {
    CV_SEAM_FACE.with(std::cell::Cell::get).unwrap_or(TAU * mh(4, seed, 0xc5))
}
thread_local! {
    /// The seam's bearing for the strike under way, when it was laid to face the player (`cv_face_seam`).
    static CV_SEAM_FACE: std::cell::Cell<Option<f64>> = const { std::cell::Cell::new(None) };
}
/// Lays the seam along the line from the player to the target, so that from where they fired the land and the sky
/// are split left and right of the columns (which world takes which side by the seed). Standing on the target, the
/// seed's own bearing.
fn cv_face_seam(seed: u32, me: [f64; 3], cx: f64, cz: f64) {
    let (dx, dz) = (cx - me[0], cz - me[2]);
    let face = (dx.hypot(dz) > 8.0).then(|| (dz.atan2(dx) + if mh(4, seed, 0xc5) < 0.5 { 0.0 } else { PI }).rem_euclid(TAU));
    CV_SEAM_FACE.with(|c| c.set(face));
}
/// Which side bearing `a` (radians, atan2(dz, dx)) lies on: 0 the Nether, 1 the Aether (pale); and how far off the
/// seam the point (dx, dz) lies (blocks, across it).
fn cv_side(seam: f64, dx: f64, dz: f64) -> (u8, f64) {
    let a = dz.atan2(dx);
    let s = (a - seam).rem_euclid(TAU);
    (u8::from(s >= PI), (dx * seam.sin() - dz * seam.cos()).abs())
}

/// The table the pass reads (see CV_FR), on the tick after it fires.
pub(super) fn cv_table(seed: f32) -> Vec<u32> {
    let mut w = vec![0.0f32; CV_FR];
    w[0] = CV_MAGIC;
    w[1] = cv_seam(seed as u32) as f32;
    w[2] = seed;
    for k in 0..CV_CRACKS {
        let (phi, reach) = cv_crack_line(seed as u32, k);
        w[CV_CRK + k as usize] = phi as f32;
        w[CV_CRK + 7 + k as usize] = reach as f32;
    }
    w[CV_CRK + 14] = CV_CRACKS as f32;
    let isl = cv_islands(seed as u32);
    w[CV_ISL] = isl.len().min(16) as f32;
    for (k, (dx, dz, h, r, t0)) in isl.into_iter().take(16).enumerate() {
        w[CV_ISL + 1 + 5 * k..CV_ISL + 6 + 5 * k].copy_from_slice(&[dx as f32, dz as f32, h as f32, r as f32, t0]);
    }
    let mut w: Vec<u32> = w.into_iter().map(f32::to_bits).collect();
    if let Some(l) = cv_sprites() {
        w[CV_SPR + 1..CV_SPR + 1 + l.len()].copy_from_slice(&l);
        w[CV_SPR] = 1.0f32.to_bits();
    }
    w
}
/// The atlas layers of CV_SPRITES' top faces (the first flat face of each block's up side, in the game's first block
/// sprite array), or none if any is missing (a resource pack without one, or the atlas not ready).
fn cv_sprites() -> Option<[u32; 5]> {
    use crate::sdk::atlas;
    crate::meter::spend(200_000);
    let names: Vec<String> = CV_SPRITES.iter().map(|n| (*n).to_string()).collect();
    let got = atlas::block_sprites(&names);
    let mut out = [0u32; 5];
    for (o, f) in out.iter_mut().zip(&got) {
        let face = f.as_ref()?.sides.get(1)?.iter().find(|f| f.inset < 0.01)?;
        if face.sprite.array != 0 {
            return None;
        }
        *o = face.sprite.layer;
    }
    Some(out)
}

// ---- before the blast: the cracks, the fissures, the veins, the basalt, the land taking sides ------------------------
/// The cracks: CV_CRACKS of them out from the target to CV_CRACK_R, fracturing out over the omen (drawn by the pass only), opened into
/// fissures from CV_BREAK; netherrack creeping out along veins round them to CV_VEIN_R over CV_BREAK..CV_MEET.
const CV_CRACKS: u32 = 7;
const CV_CRACK_R: f64 = 50.0;
const CV_VEIN_R: f64 = 62.0;
/// The basalt: CV_PILLARS clusters on the Nether half, CV_PILLAR_R0..CV_PILLAR_R1 out, shouldering up in steps.
const CV_PILLARS: u32 = 16;
const CV_PILLAR_R0: f64 = 14.0;
const CV_PILLAR_R1: f64 = 56.0;
/// The land taking sides out to CV_SIDE_R over CV_MEET..CV_DRAW.
const CV_SIDE_R: f64 = 100.0;
/// The islands left in the sky: CV_ISLANDS of them (`/orbital tune islands`), most over the Aether's half, each grown
/// out of the rift's light from CV_ISLAND_AT on, after the blast (its top first, then down layer by layer, then its
/// tree), whole before the rift has shut.
const CV_ISLANDS: u32 = 7;
const CV_ISLAND_AT: f32 = CV_HIT + 2.5;
/// How long apart the islands start, and the step each grows by.
const CV_ISLAND_GAP: f32 = 0.8;
const CV_GROW_STEP: f32 = 0.35;

/// Crack k's base bearing (radians) and reach (blocks): the table's words from CV_CRK hold the same.
fn cv_crack_line(seed: u32, k: u32) -> (f64, f64) {
    (TAU * (f64::from(k) + 0.6 * mh(k, seed, 0xc6)) / f64::from(CV_CRACKS), CV_CRACK_R * (0.65 + 0.35 * mh(k, seed, 0xc7)))
}
/// The columns the cracks' heights are read at: CV_CRH_N a crack, in the table's order.
fn cv_crack_columns(seed: u32, bx: i32, bz: i32) -> Vec<(i32, i32)> {
    let mut out = Vec::with_capacity(CV_CRH_N * CV_CRACKS as usize);
    for k in 0..CV_CRACKS {
        let (base, _) = cv_crack_line(seed, k);
        let fk = f64::from(k);
        for j in 0..CV_CRH_N {
            let r = CV_CRACK_R * j as f64 / (CV_CRH_N - 1) as f64;
            // (the crack's wander, as the pass's cvg_crack_phi)
            let phi = base + 0.16 * (r * 0.09 + fk * 1.7).sin() + 0.06 * (r * 0.31 + fk).sin();
            out.push((bx + (0.5 + r * phi.cos()).floor() as i32, bz + (0.5 + r * phi.sin()).floor() as i32));
        }
    }
    out
}
/// The land's heights along the cracks into the table once the world has answered (asked again till CV_HIT).
fn cv_crack_step(q: &mut Plan, tag: u32, columns: Rc<Vec<(i32, i32)>>, gy: i32, at_t: f32) {
    if !crate::ground::ready(tag) {
        if at_t < CV_HIT {
            q.later(at_t + 0.2, move |q| cv_crack_step(q, tag, columns, gy, at_t + 0.2));
        }
        return;
    }
    crate::meter::spend(600 * columns.len() as u64);
    let mut w = vec![1.0f32];
    w.extend(columns.iter().map(|&(x, z)| crate::ground::at(x, z).map_or(0.0, |g| (g - gy).clamp(-24, 24) as f32)));
    q.ev.push((at_t, Act::Words { index: CV_CRH as u32, words: w.iter().map(|x| x.to_bits()).collect() }));
}
/// How far column (dx, dz) from the target is off the nearest crack (blocks across).
fn cv_crack(seed: u32, dx: f64, dz: f64) -> f64 {
    let r = dx.hypot(dz);
    let a = dz.atan2(dx);
    let mut best = f64::MAX;
    for k in 0..CV_CRACKS {
        let (base, reach) = cv_crack_line(seed, k);
        let phi = base + 0.16 * (r * 0.09 + f64::from(k) * 1.7).sin() + 0.06 * (r * 0.31 + f64::from(k)).sin();
        let d = ((a - phi + PI).rem_euclid(TAU) - PI).abs() * r;
        best = best.min(if r <= reach { d } else { d + (r - reach) * 3.0 });
    }
    best
}
/// The basalt clusters: their middles (dx, dz from the target), radius, height and when each starts to rise.
pub(super) fn cv_pillars(seed: u32) -> Vec<(f64, f64, f64, i32, f32)> {
    let seam = cv_seam(seed);
    (0..CV_PILLARS)
        .map(|k| {
            let h = |s: u32| mh(k, seed, s);
            let a = seam + 0.15 + (PI - 0.3) * h(0xd1);
            let r = CV_PILLAR_R0 + (CV_PILLAR_R1 - CV_PILLAR_R0) * h(0xd2).sqrt();
            (a.cos() * r, a.sin() * r, 1.6 + 1.6 * h(0xd3), (5.0 + 10.0 * h(0xd4)).round() as i32, CV_BREAK + 1.0 + 6.0 * h(0xd5) as f32)
        })
        .collect()
}
/// The islands: their middles (dx, dz from the target), height over the target's ground, radius, and when each starts
/// to grow. Most hang over the Aether's half (bearings PI to TAU past the seam), spread round it, 30 to 95 out and 45 to
/// 100 up: from 150 to 300 blocks off on the ground they stand 10 to 30 degrees up, over the crater.
pub(super) fn cv_islands(seed: u32) -> Vec<(f64, f64, f64, f64, f32)> {
    let n = tuned().islands;
    let seam = cv_seam(seed);
    (0..n)
        .map(|k| {
            let h = |s: u32| mh(k, seed, s);
            // (one in four over the Nether's half, torn loose; the rest spread evenly over the Aether's)
            let nether = k % 4 == 3;
            let m = n - (n + 1) / 4;
            let j = k - (k + 1) / 4;
            let a = if nether { seam + 0.4 + (PI - 0.8) * h(0xe1) } else { seam + PI + 0.25 + (PI - 0.5) * (f64::from(j) + 0.2 + 0.6 * h(0xe1)) / f64::from(m.max(1)) };
            let r = 30.0 + 65.0 * h(0xe2);
            (a.cos() * r, a.sin() * r, 55.0 + 55.0 * h(0xe3), 8.0 + 7.0 * h(0xe4), CV_ISLAND_AT + CV_ISLAND_GAP * k as f32)
        })
        .collect()
}
/// The Nether's top block for a column of the creeping land (netherrack mostly, crimson nylium, soul soil, blackstone,
/// a magma vein), and what grows on it (crimson roots, a fungus, soul fire on soul soil: none of them spreads).
fn nether_top(x: i32, z: i32, seed: u32) -> (&'static str, Option<&'static str>) {
    let n = vnoise(f64::from(x), f64::from(z), 6.0, seed ^ 0xa1);
    let f = mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, seed, 0xa2);
    if n > 0.74 {
        ("minecraft:crimson_nylium", if f < 0.12 { Some("minecraft:crimson_roots") } else if f < 0.15 { Some("minecraft:crimson_fungus") } else { None })
    } else if n < 0.18 {
        ("minecraft:soul_soil", if f < 0.06 { Some("minecraft:soul_fire") } else { None })
    } else if f < 0.04 {
        ("minecraft:magma_block", None)
    } else if n < 0.3 {
        ("minecraft:blackstone", None)
    } else {
        ("minecraft:netherrack", None)
    }
}
/// The Aether-touched top block (pale moss and calcite mostly, diorite, now and then gold or a light) and what grows
/// on it (pale moss carpet, a white flower).
/// The Aether-touched top block: pale moss for its pale grass mostly, calcite and diorite for its pale stone in
/// patches, a glowing yellow (glowstone) or gold now and then; what grows on it (pale moss
/// carpet, its white and purple flowers).
fn pale_top(x: i32, z: i32, seed: u32) -> (&'static str, Option<&'static str>) {
    let n = vnoise(f64::from(x), f64::from(z), 6.0, seed ^ 0xb1);
    let f = mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, seed, 0xb2);
    if f < 0.01 {
        ("minecraft:glowstone", None)
    } else if f < 0.02 {
        ("minecraft:raw_gold_block", None)
    } else if n > 0.78 {
        // (pale stone in patches: diorite and andesite for the pale stone's grey, calcite only now and then: a field of
        // calcite reads as snow)
        (if f < 0.25 { "minecraft:calcite" } else if f < 0.6 { "minecraft:diorite" } else { "minecraft:andesite" }, None)
    } else {
        ("minecraft:pale_moss_block", if f < 0.06 { Some("minecraft:lily_of_the_valley") } else if f < 0.085 { Some("minecraft:allium") } else if f < 0.16 { Some("minecraft:pale_moss_carpet") } else { None })
    }
}
/// The seam between the halves: obsidian and crying obsidian (the purple of a portal's frame).
fn seam_block(x: i32, z: i32, seed: u32) -> &'static str {
    if mh((x.wrapping_mul(19_349_663) ^ z.wrapping_mul(73_856_093)) as u32, seed, 0xb3) < 0.35 { "minecraft:crying_obsidian" } else { "minecraft:obsidian" }
}

// ---- the blast's reach ------------------------------------------------------------------------------------------------
/// The crater's mean radius and depth, how far its rim's heap reaches (in its radii), the land flattened and the trees
/// felled out to CV_FLAT, the grass turned out to cv_char(), the rubble strewn out to CV_RUBBLE; past the flattened land
/// a band CV_BAND wide of stripped crowns and some trees knocked flat.
const CV_CRATER_R: f64 = 84.0;
const CV_CRATER_D: f64 = 42.0;
const CV_RIM: f64 = 1.5;
const CV_FLAT: f64 = 190.0;
/// The numbers `/orbital tune` sets (tune.rs `KNOBS`, the "convergence" lines), taken as each strike is planned
/// (`cv_take_tune`) and read by its stages: the crater's radius and depth, how far the land turns, the knockback's and
/// the camera jolts' strengths, the islands left in the sky.
#[derive(Clone, Copy, Debug)]
pub(super) struct CvTune {
    crater: f64,
    depth: f64,
    turn: f64,
    knock: f32,
    jolt: f32,
    islands: u32,
}
const CV_TUNE0: CvTune = CvTune { crater: CV_CRATER_R, depth: CV_CRATER_D, turn: CV_CHAR, knock: 1.0, jolt: 1.0, islands: CV_ISLANDS };
thread_local! {
    static CV_TUNE: std::cell::Cell<CvTune> = const { std::cell::Cell::new(CV_TUNE0) };
}
fn tuned() -> CvTune {
    CV_TUNE.with(std::cell::Cell::get)
}
fn cv_take_tune() {
    let g = |k: &str| f64::from(crate::tune::get("convergence", k));
    CV_TUNE.with(|c| {
        c.set(CvTune {
            crater: g("crater"),
            depth: g("depth"),
            turn: g("turn").min(f64::from(CV_READ) - 8.0),
            knock: g("knock") as f32,
            jolt: g("jolt") as f32,
            islands: g("islands").round().clamp(0.0, 16.0) as u32,
        });
    });
}
/// The crater's radius and depth, and how far the land turns, as tuned for this strike.
fn cr() -> f64 {
    tuned().crater
}
fn cdp() -> f64 {
    tuned().depth
}
fn cv_char() -> f64 {
    tuned().turn
}
const CV_CHAR: f64 = 220.0;
const CV_RUBBLE: f64 = 250.0;
const CV_BAND: f64 = 40.0;
/// The land read: every column out to CV_READ, CV_BELOW under its top (a tall tree's top down to its ground).
const CV_READ: i32 = 256;
const CV_GW: i32 = 2 * CV_READ + 1;
const CV_BELOW: u32 = 36;
const CV_ABOVE: u32 = 1;
const CV_PARTS: i32 = 48;
/// Mobs and dropped items within CV_KILL killed as it strikes.
const CV_KILL: i32 = 200;
/// Real blocks thrown out of the crater as it strikes (cv_thrown).
const CV_THROWN: usize = 240;
/// The rays the ejecta lie in round the crater (the turned grass and the rubble follow them).
const CV_RAYS: f64 = 17.0;

// ---- the land, read from the world ------------------------------------------------------------------------------
/// What a block is to the blast: nothing, water or lava (water left alone; lava as `lava_worked` says), leaves, a log, something standing on the ground
/// (plants, snow, fences, a shed), or the ground itself.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Kind {
    Air,
    Fluid,
    Leaves,
    Log,
    Loose,
    Ground,
}
const WOODS: [&str; 9] = ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "pale_oak"];
pub(super) const LOG_X: [&str; 9] = [
    "minecraft:oak_log[axis=x]",
    "minecraft:spruce_log[axis=x]",
    "minecraft:birch_log[axis=x]",
    "minecraft:jungle_log[axis=x]",
    "minecraft:acacia_log[axis=x]",
    "minecraft:dark_oak_log[axis=x]",
    "minecraft:mangrove_log[axis=x]",
    "minecraft:cherry_log[axis=x]",
    "minecraft:pale_oak_log[axis=x]",
];
pub(super) const LOG_Z: [&str; 9] = [
    "minecraft:oak_log[axis=z]",
    "minecraft:spruce_log[axis=z]",
    "minecraft:birch_log[axis=z]",
    "minecraft:jungle_log[axis=z]",
    "minecraft:acacia_log[axis=z]",
    "minecraft:dark_oak_log[axis=z]",
    "minecraft:mangrove_log[axis=z]",
    "minecraft:cherry_log[axis=z]",
    "minecraft:pale_oak_log[axis=z]",
];
pub(super) const LOG_Y: [&str; 9] = [
    "minecraft:oak_log",
    "minecraft:spruce_log",
    "minecraft:birch_log",
    "minecraft:jungle_log",
    "minecraft:acacia_log",
    "minecraft:dark_oak_log",
    "minecraft:mangrove_log",
    "minecraft:cherry_log",
    "minecraft:pale_oak_log",
];
pub(super) const LEAF_NAMES: [&str; 9] = [
    "minecraft:oak_leaves",
    "minecraft:spruce_leaves",
    "minecraft:birch_leaves",
    "minecraft:jungle_leaves",
    "minecraft:acacia_leaves",
    "minecraft:dark_oak_leaves",
    "minecraft:mangrove_leaves",
    "minecraft:cherry_leaves",
    "minecraft:pale_oak_leaves",
];
pub(super) const LEAVES: [&str; 9] = [
    "minecraft:oak_leaves[persistent=true]",
    "minecraft:spruce_leaves[persistent=true]",
    "minecraft:birch_leaves[persistent=true]",
    "minecraft:jungle_leaves[persistent=true]",
    "minecraft:acacia_leaves[persistent=true]",
    "minecraft:dark_oak_leaves[persistent=true]",
    "minecraft:mangrove_leaves[persistent=true]",
    "minecraft:cherry_leaves[persistent=true]",
    "minecraft:pale_oak_leaves[persistent=true]",
];
fn wood_of(name: &str, suffix: &str) -> u8 {
    let n = name.strip_prefix("minecraft:").unwrap_or(name);
    n.strip_suffix(suffix).and_then(|w| WOODS.iter().position(|x| *x == w)).map_or(0, |i| i as u8)
}
fn kind(name: &str) -> (Kind, u8) {
    let n = name.strip_prefix("minecraft:").unwrap_or(name);
    if n.ends_with("air") {
        return (Kind::Air, 0);
    }
    if matches!(n, "water" | "lava" | "bubble_column" | "seagrass" | "tall_seagrass" | "kelp" | "kelp_plant") {
        return (Kind::Fluid, 0);
    }
    if n.ends_with("_leaves") {
        return (Kind::Leaves, wood_of(name, "_leaves"));
    }
    if n.ends_with("_log") || n.ends_with("_wood") || n.ends_with("_stem") {
        return (Kind::Log, wood_of(name, "_log"));
    }
    const GROUND: [&str; 34] = [
        "grass_block", "dirt", "podzol", "mycelium", "stone", "deepslate", "sand", "gravel", "clay", "terracotta", "ice",
        "snow_block", "mud", "moss_block", "granite", "diorite", "andesite", "tuff", "calcite", "basalt", "blackstone",
        "netherrack", "_ore", "bedrock", "sandstone", "rooted_dirt", "farmland", "dirt_path", "obsidian", "magma_block",
        "pale_moss_block", "soul_sand", "soul_soil", "cobblestone",
    ];
    if GROUND.iter().any(|g| n.contains(g)) && !n.contains("_slab") && !n.contains("_stairs") && !n.contains("_wall") {
        return (Kind::Ground, u8::from(n == "grass_block") + 2 * u8::from(n == "dirt" || n == "podzol" || n == "mycelium" || n == "rooted_dirt"));
    }
    (Kind::Loose, 0)
}

/// A column as read: its ground block's height, the highest block over it (its ground if nothing stands on it), the
/// trunk standing on it (its height and wood), the leaves over it, what its ground is (1 grass, 2 dirt), and whether
/// water or lava is there (water left alone; lava dug and cooled in the crater and its rim, `lava_worked`).
#[derive(Clone, Copy, Debug, Default)]
pub(super) struct Column {
    pub(super) known: bool,
    pub(super) fluid: bool,
    /// The fluid is lava (dug like dry land in the crater, cooled in its rim, left past it).
    pub(super) lava: bool,
    /// The water's own surface here (not what hangs over it).
    pub(super) wtop: i32,
    pub(super) g: i32,
    pub(super) top: i32,
    pub(super) trunk: u8,
    pub(super) wood: u8,
    pub(super) leaves: u8,
    pub(super) ground: u8,
}

pub(super) struct Land {
    pub(super) cols: Vec<Column>,
    /// The columns of each ring (part) of the read the world had not loaded when it answered, asked again till it has.
    pub(super) missing: Vec<Vec<(i32, i32)>>,
    /// How many trunks of each wood stand on it (the commonest is the one strewn and thrown).
    pub(super) woods: [u32; 9],
    /// Every part taken in (the stages that use it wait for it).
    pub(super) done: bool,
}

fn at(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> Option<&Column> {
    crate::meter::spend(30);
    let (i, k) = (x - bx + CV_READ, z - bz + CV_READ);
    if i < 0 || k < 0 || i >= CV_GW || k >= CV_GW {
        return None;
    }
    land.cols.get((k * CV_GW + i) as usize).filter(|c| c.known)
}

/// How far out part `part` of the land's read reaches: the parts are rings from the middle out, as many columns in
/// each (the wave's stages wait only for the rings they reach into).
fn read_reach(part: i32) -> f64 {
    f64::from(CV_READ) * (f64::from(part + 1) / f64::from(CV_PARTS)).sqrt()
}
/// The columns read in part `part`: those of its ring.
fn read_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let r1 = read_reach(part).min(f64::from(CV_READ));
    let q0 = if part == 0 { -1.0 } else { read_reach(part - 1).powi(2) };
    ring_columns(bx, bz, q0, r1)
}
/// The columns of the ring from squared radius `q0` (exclusive) out to radius `r1` round (bx, bz).
pub(super) fn ring_columns(bx: i32, bz: i32, q0: f64, r1: f64) -> Vec<(i32, i32)> {
    let q1 = r1 * r1;
    let n = r1.ceil() as i32;
    let mut out = Vec::new();
    for dz in -n..=n {
        let d = f64::from(dz * dz);
        if d > q1 {
            continue;
        }
        // (the row's run within r1 less its run within r0)
        let wo = (q1 - d).sqrt().floor() as i32;
        let wi = if q0 >= d { (q0 - d).sqrt().floor() as i32 } else { -1 };
        // (only the ring's own columns gone over, not the whole disc within it: the outer rings' discs are some
        // hundred thousand columns, and two are asked a stage)
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

/// One answer for ring `part` taken in: each column's ground, what stands on it and over it (those not loaded kept to
/// be asked again).
fn take_in(land: &mut Land, a: &crate::columns::Answer, bx: i32, bz: i32, part: usize) {
    take_in_grid(land, a, bx, bz, part, CV_READ, false);
}
/// The same for a land's square reaching `read` columns round (bx, bz). `tall`: a column with no ground within the read
/// but something solid on it (a very tall tree, a wall of a mountain) is kept too, the bottom of the read as its ground.
pub(super) fn take_in_grid(land: &mut Land, a: &crate::columns::Answer, bx: i32, bz: i32, part: usize, read: i32, tall: bool) {
    let gw = 2 * read + 1;
    let kinds: Vec<(Kind, u8)> = a.palette.iter().map(|n| kind(n)).collect();
    let lavas: Vec<bool> = a.palette.iter().map(|n| n.contains("lava")).collect();
    crate::meter::spend(2_000 + 4_000 * a.palette.len() as u64);
    for (i, &(x, z)) in a.columns.iter().enumerate() {
        let Some((surface, blocks)) = a.column(i) else {
            crate::meter::spend(60);
            land.missing[part].push((x, z));
            continue;
        };
        let base = surface - a.below;
        // (as the game counts it: some 2M a part's answer of 4,400 columns)
        crate::meter::spend(200 + 12 * blocks.len() as u64);
        let mut c = Column { known: true, leaves: 255, ..Default::default() };
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
                    if !c.fluid {
                        c.wtop = base + j as i32;
                    }
                    c.fluid = true;
                    c.lava |= lavas.get(blocks[j] as usize).copied().unwrap_or(false);
                    top.get_or_insert(base + j as i32);
                }
                Kind::Leaves => {
                    if c.leaves == 255 {
                        c.leaves = w;
                    }
                    top.get_or_insert(base + j as i32);
                }
                _ => {
                    top.get_or_insert(base + j as i32);
                }
            }
        }
        // (no ground within reach: a very tall tree, or over the void; left alone unless asked for)
        if g.is_none() && !(tall && top.is_some() && !c.fluid) {
            continue;
        }
        let gj = g.unwrap_or(0);
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
        if c.trunk > 0 {
            land.woods[c.wood as usize] += 1;
        }
        let (ii, kk) = (x - bx + read, z - bz + read);
        if (0..gw).contains(&ii) && (0..gw).contains(&kk) {
            land.cols[(kk * gw + ii) as usize] = c;
        }
    }
}

// ---- the crater and what lies round it -------------------------------------------------------------------------------
/// The crater's shape round the target: its edge wanders; split down the middle along the seam (`cv_side`).
#[derive(Clone, Copy)]
struct Shape {
    cx: f64,
    cz: f64,
    ph: [f64; 3],
    seed: u32,
    seam: f64,
}
impl Shape {
    fn wob(&self, a: f64) -> f64 {
        1.0 + 0.06 * (3.0 * a + self.ph[0]).sin() + 0.04 * (5.0 * a + self.ph[1]).sin() + 0.025 * (9.0 * a + self.ph[2]).sin()
    }
    /// What the blast makes of column (x, z): how far its ground goes down (or up, its rim's heap), whether it is
    /// flattened, and how far out it is (in the crater's radii).
    fn at(&self, x: i32, z: i32) -> (f64, f64, f64) {
        crate::meter::spend(500);
        let (dx, dz) = (f64::from(x) + 0.5 - self.cx, f64::from(z) + 0.5 - self.cz);
        let r = dx.hypot(dz);
        let a = dz.atan2(dx);
        let rc = cr() * self.wob(a) * (0.97 + 0.06 * vnoise(f64::from(x), f64::from(z), 14.0, self.seed ^ 0x31));
        (r, a, r / rc)
    }
    fn flat(&self, a: f64) -> f64 {
        CV_FLAT * (1.0 + 0.08 * (2.0 * a + self.ph[2]).sin() + 0.05 * (7.0 * a + self.ph[0]).sin())
    }
    /// How strongly bearing `a` lies in one of the ejecta's rays (0 to 1).
    fn ray(&self, a: f64) -> f64 {
        let k = CV_RAYS / PI;
        let st = vnoise(a.cos() * k, a.sin() * k, 1.0, self.seed ^ 0x73);
        ((st - 0.5) / 0.25).clamp(0.0, 1.0)
    }
    /// Which half column (x, z) is on: 0 the Nether, 1 the Aether, 2 the seam between them (CV_SEAM_W across).
    fn side(&self, x: i32, z: i32) -> u8 {
        let (s, d) = cv_side(self.seam, f64::from(x) + 0.5 - self.cx, f64::from(z) + 0.5 - self.cz);
        if d < CV_SEAM_W { 2 } else { s }
    }
}
/// The seam's width across, blocks.
const CV_SEAM_W: f64 = 1.6;
/// How deep the crater is at u (its radii out): a bowl, a broad floor, its walls rising to the rim.
fn bowl(u: f64) -> f64 {
    if u >= 1.0 {
        return 0.0;
    }
    cdp() * (1.0 - u.powi(3)).powf(0.8)
}
/// The rim's heap past the edge (u in crater radii): a ridge just past the edge, falling away, ragged (`n`, 0 to 1).
fn heap(u: f64, n: f64) -> f64 {
    if u < 1.0 || u > CV_RIM {
        return 0.0;
    }
    let k = cr() / 64.0;
    let ridge = 7.5 * k * (-(u - 1.05).powi(2) / 0.004).exp() + 3.0 * k * (1.0 - (u - 1.0) / (CV_RIM - 1.0));
    ridge * (0.4 + 0.9 * n)
}
/// The crater's floor and walls, by half: the Nether's (netherrack, blackstone, magma, basalt, soul soil, nether
/// wart block, glowstone now and then), the Aether's (calcite, diorite, smooth quartz, pale moss on the floor, gold and
/// glowstone now and then), and the seam's (obsidian, crying obsidian).
fn scorched(x: i32, y: i32, z: i32, u: f64, seed: u32, side: u8) -> &'static str {
    let n = vnoise(f64::from(x) + f64::from(y) * 0.37, f64::from(z), 4.0, seed ^ 0x51);
    let m = vnoise(f64::from(x), f64::from(z) - f64::from(y) * 0.5, 2.2, seed ^ 0x52);
    let f = mh((x.wrapping_mul(73_856_093) ^ y.wrapping_mul(19_349_663) ^ z.wrapping_mul(83_492_791)) as u32, seed, 0x54);
    match side {
        2 => seam_block(x, z, seed ^ y as u32),
        0 => {
            if f < 0.03 {
                "minecraft:magma_block"
            } else if f < 0.04 {
                "minecraft:glowstone"
            } else if n > 0.75 {
                "minecraft:basalt"
            } else if m > 0.7 && u < 0.7 {
                "minecraft:soul_soil"
            } else if n < 0.22 {
                "minecraft:blackstone"
            } else if m < 0.2 {
                "minecraft:nether_wart_block"
            } else {
                "minecraft:netherrack"
            }
        }
        _ => {
            if f < 0.02 {
                "minecraft:glowstone"
            } else if f < 0.05 {
                "minecraft:raw_gold_block"
            } else if m > 0.6 && u < 0.8 {
                "minecraft:pale_moss_block"
            } else if n > 0.62 {
                "minecraft:andesite"
            } else if n < 0.3 {
                "minecraft:calcite"
            } else {
                "minecraft:diorite"
            }
        }
    }
}
/// The rim's heap by half: the deep rock turned over on top (`k`: how far up the heap, 0 its foot, 1 its top), the soil
/// under it.
fn ejecta(x: i32, y: i32, z: i32, k: f64, seed: u32, side: u8) -> &'static str {
    let n = vnoise(f64::from(x) * 1.3 + f64::from(y) * 0.71, f64::from(z) * 1.3, 3.0, seed ^ 0x61);
    let k = k + 0.3 * (n - 0.5);
    match side {
        2 => seam_block(x, z, seed ^ y as u32),
        0 if k > 0.5 => {
            if n > 0.7 { "minecraft:blackstone" } else if n < 0.25 { "minecraft:basalt" } else { "minecraft:netherrack" }
        }
        1 if k > 0.5 => {
            if n > 0.6 { "minecraft:andesite" } else if n < 0.25 { "minecraft:calcite" } else { "minecraft:diorite" }
        }
        _ => {
            if n < 0.35 { "minecraft:rooted_dirt" } else if n < 0.6 { "minecraft:coarse_dirt" } else { "minecraft:dirt" }
        }
    }
}
/// The grass round it turned by what the crater threw out, by half, in rays out to about CV_CHAR: the Nether's own
/// (`nether_top`) one side, the Aether's (`pale_top`) the other, the seam's between.
fn charred(s: &Shape, x: i32, z: i32, r: f64, a: f64, seed: u32) -> Option<(&'static str, Option<&'static str>)> {
    let n = vnoise(f64::from(x), f64::from(z), 5.0, seed ^ 0x71);
    let m = vnoise(f64::from(x), f64::from(z), 2.0, seed ^ 0x72);
    let ray = s.ray(a);
    let reach = cv_char() * (0.7 + 0.3 * ray);
    let k = (1.0 - ((r - cr() * CV_RIM) / (reach - cr() * CV_RIM).max(1.0)).clamp(0.0, 1.0)).powf(0.55);
    let v = 0.6 * n + 0.4 * m;
    let w = k * (0.55 + 0.45 * ray) + 0.08;
    if v >= w + 0.15 || k <= 0.0 {
        return None;
    }
    Some(match s.side(x, z) {
        2 => (seam_block(x, z, seed), None),
        0 => nether_top(x, z, seed),
        _ => pale_top(x, z, seed),
    })
}

/// How hard the blast still hits column (x, z) in the band past the flattened land: 1 at its inner edge, to 0 at its
/// outer (None outside it). (`ra`: its radius and bearing, from `Shape::at`.)
fn band_ra(s: &Shape, (r, a): (f64, f64)) -> Option<f64> {
    let e = r - s.flat(a);
    (0.0..CV_BAND).contains(&e).then(|| 1.0 - e / CV_BAND)
}
fn band(s: &Shape, x: i32, z: i32) -> Option<f64> {
    let (r, a, _) = s.at(x, z);
    band_ra(s, (r, a))
}
/// A tree in the band knocked flat (more of them near the flattened land).
fn knocked_ra(c: &Column, s: &Shape, x: i32, z: i32, ra: (f64, f64)) -> bool {
    c.trunk >= 3 && !c.fluid && band_ra(s, ra).is_some_and(|p| mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917)) as u32, s.seed, 0x91) < 0.75 * p.powf(1.1))
}
fn knocked(c: &Column, s: &Shape, x: i32, z: i32) -> bool {
    let (r, a, _) = s.at(x, z);
    knocked_ra(c, s, x, z, (r, a))
}
/// What the blast makes of column (x, z): Kept, or its new ground's top (`Some`) and whether it was cleared. (`rau`:
/// `Shape::at`'s.)
fn new_ground_at(c: &Column, s: &Shape, x: i32, z: i32, (r, a, u): (f64, f64, f64)) -> Option<i32> {
    if u < 1.0 {
        Some(c.g - bowl(u).round() as i32)
    } else if u < CV_RIM {
        let n = vnoise(f64::from(x), f64::from(z), 8.0, s.seed ^ 0x35);
        Some(c.g + heap(u, n).round() as i32)
    } else if r < s.flat(a) || knocked_ra(c, s, x, z, (r, a)) {
        Some(c.g)
    } else {
        None
    }
}
fn new_ground(c: &Column, s: &Shape, x: i32, z: i32) -> Option<i32> {
    new_ground_at(c, s, x, z, s.at(x, z))
}
/// Water or lava within a column's reach: dig nothing there or next to it.
fn wet_near(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> bool {
    fluid_near(land, bx, bz, x, z, 0)
}
/// The same for water only (lava is dug, heaped over and cooled as the land round it is: `cv_blast_col`).
fn water_near(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> bool {
    fluid_near(land, bx, bz, x, z, 1)
}
/// The same for lava only.
fn lava_near(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> bool {
    fluid_near(land, bx, bz, x, z, 2)
}
/// (`which`: 0 any fluid, 1 water only, 2 lava only)
fn fluid_near(land: &Land, bx: i32, bz: i32, x: i32, z: i32, which: u8) -> bool {
    // (the crater is deep: two columns of ground kept between it and any water)
    [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        .iter()
        .any(|(dx, dz)| at(land, bx, bz, x + dx, z + dz).is_some_and(|c| c.fluid && (which == 0 || (which == 2) == c.lava)))
}
/// Whether the blast works lava column `c` at `u` (crater radii out) through as it does dry land: in the crater and
/// its rim (dug, or cooled and heaped over); past the rim a pool is left, held back by the rim's cooled lava.
fn lava_worked(c: &Column, u: f64) -> bool {
    c.lava && u < CV_RIM
}

// ---- the wave: the crater dug out, then lined, the land round it after ----------------------------------------------
/// The blast's changes go into the world in two waves, a ring at a time from the middle out. The first, the carve, digs
/// the crater out as it strikes: every block over each column's finished floor turned to air (and the lava in the
/// ground it bares sealed), out with the shockwave as fast as the world takes the air (CV_CARVE_RATE a second, by
/// `cv_carve_cost`), so the pit opens at once, done by some 0.7 s after the impact. The second, the lining, follows
/// once the whole pit is open (CV_LINE_GAP after it): from the middle out, the floor's quartz, calcite and gold out to its walls, then on out over the rim, the flattened land and
/// its felled trees, the dusted grass, the stripped crowns, out to the land read, as soon as the world takes the blocks
/// the rings before it change (`cv_cost`, at CV_RATE a second). A chunk's edits go in on one tick in each: twice in the
/// crater (dug, then lined), once round it.
const CV_RATE: f64 = 350_000.0;
/// The carve's pace: air is cheap to set, so it runs at more than twice the lining's.
const CV_CARVE_RATE: f64 = 900_000.0;
/// How long the pit stands open, dug to its floor, before the lining begins at its middle.
const CV_LINE_GAP: f64 = 0.1;
/// How far out the carve reaches: just past the crater's edge however its edge wanders (cr() times its wobble,
/// at most some 1.16).
fn cave() -> usize {
    (cr() * 1.19).ceil() as usize
}
/// How far out its wave runs: to the middle of the farthest chunk holding any of the crater (cave() and the half
/// diagonal of a chunk).
fn carve_to() -> usize {
    cave() + 12
}
/// The rings (CV_RING wide) are worked out in parts of about CV_ITEM columns, split by angle, never by rows.
const CV_RING: f64 = 4.0;
const CV_ITEM: f64 = 250.0;
/// What the carve is expected to turn to air in a column at radius r (blocks): the crater's depth there, what stood
/// over its ground and its share of its chunk sent again, the depth spread over a chunk's width (each chunk is dug on
/// one tick, when the wave reaches its middle: so the chunks round the crater's edge, part pit and part not, are dug
/// over the ticks their share takes, not all on the last).
fn cv_carve_cost(r: f64) -> f64 {
    let mut d = 0.0;
    for k in -8..=8 {
        let u = (r + f64::from(k)).max(0.0) / cr();
        d += bowl(u) / 17.0;
    }
    // (and a chunk sent again a share of each of its columns, as in the pace's count: a chunk as much as 2,048 blocks)
    d + 8.0
}
/// What the lining is expected to change in a column at radius r (blocks), for its pace: in the crater a block or two
/// of its floor (and the chunk sent again); round it the land's changes.
fn cv_cost(r: f64) -> f64 {
    let u = r / cr();
    if u < 1.0 {
        8.0
    } else if u < CV_RIM {
        heap(u, 0.5) + 8.0
    } else if r < CV_FLAT {
        // (the trees swept off and their crowns tidied: a lot of light for the game to work out again)
        10.0
    } else {
        6.0
    }
}
/// When the waves reach radius r (a block at a time): the carve (`carve`, out to carve_to()) and the lining (`line`,
/// out to past CV_READ), both rising from the middle out.
#[derive(Clone)]
struct Wave {
    carve: Rc<Vec<f32>>,
    line: Rc<Vec<f32>>,
}
impl Wave {
    fn new() -> Self {
        let shock = |r: f64| (r * r + CV_BURST * CV_BURST).sqrt() / 343.0;
        // (the carve: out with the shock, or as soon after it as the air goes in)
        let mut carve = vec![0.0f32; carve_to()];
        let mut work = 0.0;
        for (r, o) in carve.iter_mut().enumerate() {
            let rf = r as f64;
            *o = CV_HIT + 0.05 + shock(rf).max(work / CV_CARVE_RATE) as f32;
            work += TAU * (rf + 0.5) * cv_carve_cost(rf + 0.5);
        }
        // (the lining: from the middle once the whole pit is open)
        let start = f64::from(carve[carve_to() - 1] - CV_HIT) + CV_LINE_GAP;
        let n = CV_READ as usize + 16;
        let mut line = vec![0.0f32; n + 1];
        let mut work = 0.0;
        for (r, o) in line.iter_mut().enumerate() {
            let rf = r as f64;
            *o = CV_HIT + (start + work / CV_RATE).max(0.05 + shock(rf)) as f32;
            work += TAU * (rf + 0.5) * cv_cost(rf + 0.5);
        }
        Wave { carve: Rc::new(carve), line: Rc::new(line) }
    }
    /// When the lining reaches radius r.
    fn at(&self, r: f64) -> f32 {
        self.line[(r.max(0.0) as usize).min(self.line.len() - 1)]
    }
    /// When the carve reaches radius r (its last ring's past the crater).
    fn carve_at(&self, r: f64) -> f32 {
        self.carve[(r.max(0.0) as usize).min(carve_to() - 1)]
    }
    /// When the carve is done: the whole pit open.
    #[cfg(test)]
    fn dug(&self) -> f32 {
        self.carve[carve_to() - 1]
    }
    /// When the lining has swept the whole of the chunk column holding block column (x, z) (`cx`, `cz` the target's
    /// middle): the later of its nearest and its farthest point. Every edit to a chunk goes in on the one tick (in the
    /// crater one tick to dig it, one to line it), so the game redraws each of its sections once a wave, not once a
    /// ring.
    fn chunk(&self, cx: f64, cz: f64, x: i32, z: i32) -> f32 {
        let d = Self::chunk_d(cx, cz, x, z);
        self.at(d - 11.4).max(self.at(d + 11.4))
    }
    /// The carve's for that chunk: as it reaches the chunk's middle (its cost is spread over a chunk's width for that,
    /// `cv_carve_cost`; the shock there a tick at most from any of it).
    fn carve_chunk(&self, cx: f64, cz: f64, x: i32, z: i32) -> f32 {
        self.carve_at(Self::chunk_d(cx, cz, x, z))
    }
    fn chunk_d(cx: f64, cz: f64, x: i32, z: i32) -> f64 {
        let (mx, mz) = (f64::from((x >> 4) * 16) + 8.0, f64::from((z >> 4) * 16) + 8.0);
        (mx - cx).hypot(mz - cz)
    }
}
/// A part of a ring: radii r0..r1 from the target's middle, its angles a0 to a0 + da.
#[derive(Clone, Copy, Debug)]
pub(super) struct Sector {
    pub(super) r0: f64,
    pub(super) r1: f64,
    pub(super) a0: f64,
    pub(super) da: f64,
    /// How far through its ring's parts it is (0 the first): its edits go in that far between the wave reaching the
    /// ring's inner edge and its outer, so a ring's parts go in over the ticks between, not all in one.
    pub(super) frac: f64,
}
impl Sector {
    fn when(&self, wave: &Wave) -> f32 {
        let (t0, t1) = (wave.at(self.r0), wave.at(self.r1));
        t0 + (t1 - t0) * self.frac as f32
    }
}
impl Sector {
    pub(super) fn holds(&self, dx: f64, dz: f64) -> bool {
        let q = dx * dx + dz * dz;
        if q < self.r0 * self.r0 || q >= self.r1 * self.r1 {
            return false;
        }
        self.da >= TAU - 1e-9 || (dz.atan2(dx) - self.a0).rem_euclid(TAU) < self.da
    }
    /// The block columns whose middles lie in it, round (cx, cz); and the box they lie in.
    pub(super) fn cells(&self, cx: f64, cz: f64) -> (Vec<(i32, i32)>, [i32; 4]) {
        // (its box: the corners and wherever it crosses an axis)
        let (mut x0, mut z0, mut x1, mut z1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        let mut add = |a: f64, r: f64| {
            let (x, z) = (cx + a.cos() * r, cz + a.sin() * r);
            x0 = x0.min(x);
            z0 = z0.min(z);
            x1 = x1.max(x);
            z1 = z1.max(z);
        };
        let n = 12;
        for k in 0..=n {
            let a = self.a0 + self.da.min(TAU) * f64::from(k) / f64::from(n);
            add(a, self.r0);
            add(a, self.r1);
        }
        let (x0, z0, x1, z1) = ((x0 - 1.0).floor() as i32, (z0 - 1.0).floor() as i32, (x1 + 1.0).ceil() as i32, (z1 + 1.0).ceil() as i32);
        let mut out = Vec::new();
        crate::meter::spend(200 * ((x1 - x0 + 1) as u64) * ((z1 - z0 + 1) as u64));
        let (q0, q1) = (self.r0 * self.r0, self.r1 * self.r1);
        for z in z0..=z1 {
            let dz = f64::from(z) + 0.5 - cz;
            for x in x0..=x1 {
                let dx = f64::from(x) + 0.5 - cx;
                let q = dx * dx + dz * dz;
                if q >= q0 && q < q1 && self.holds(dx, dz) {
                    out.push((x, z));
                }
            }
        }
        (out, [x0, z0, x1, z1])
    }
}
/// The rings from r0 to r1, `w` wide (twice that past the crater), each split by angle into parts of about `item`
/// columns and no more than `arc` blocks along (their seams turned from ring to ring).
fn sectors(r0: f64, r1: f64, w: f64, item: f64, arc: f64) -> Vec<Sector> {
    let mut out = Vec::new();
    let mut r = r0;
    let mut k = 0;
    while r < r1 {
        let w = if r >= cr() { 2.0 * w } else { w };
        // (no ring left thinner than half its width at the end)
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

// ---- the water: only what the crater breaks into, to its own level ----------------------------------------------
/// How far down the ground under column (x, z)'s new floor `top` is opened to its neighbours: down past the lowest of
/// their new floors (each worked out near enough from its ground and how far out it lies), so the water and lava in the
/// ground there are sealed over the whole of the face the crater bares.
fn seal_lo(land: &Land, bx: i32, bz: i32, x: i32, z: i32, top: i32, r: f64, ang: f64, u: f64) -> i32 {
    let rc = if u > 1e-6 { r / u } else { cr() };
    let (ca, sa) = (ang.cos(), ang.sin());
    let mut lo = top;
    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let Some(n) = at(land, bx, bz, x + dx, z + dz) else { continue };
        let un = u + (f64::from(dx) * ca + f64::from(dz) * sa) / rc;
        let f = if un < 1.0 { n.g - bowl(un.max(0.0)).round() as i32 } else { n.g };
        lo = lo.min(f);
    }
    lo - 3
}

/// The blast's edits to column (x, z): the crater dug (into `cv`, the carve's: air over its floor, the lava it
/// bares sealed) and lined (its floor, by half), its rim heaped, the land flattened and charred, the crowns
/// stripped (into `b`, the lining's).
fn cv_blast_col(b: &mut Blocks, cv: &mut Blocks, land: &Land, s: &Shape, bx: i32, bz: i32, x: i32, z: i32, cleared: Option<&mut bool>) {
    crate::meter::spend(400);
    let Some(c) = at(land, bx, bz, x, z) else { return };
    let (r, ang, u) = s.at(x, z);
    if r > f64::from(CV_READ) {
        return;
    }
    // (the rim's heap is kept off water only: lava is dug and heaped over like dry land)
    let wet = water_near(land, bx, bz, x, z);
    let ng = new_ground_at(c, s, x, z, (r, ang, u));
    let worked = !c.fluid || lava_worked(c, u);
    if let Some(k) = cleared {
        *k = worked && ng.is_some();
    }
    // (lava by the crater not dug out with it (its rim, the edge where the bowl rounds to nothing), a pool the crater
    // cuts through: cooled as the crater is dug, so none pours in over the open pit before the rim is heaped; basalt
    // with a crust of magma at the pool's surface, the rim's heap then put over it. The pool past the rim stays lava,
    // held back by it.)
    let crust = if lava_worked(c, u) && ng.is_some_and(|t| t >= c.g) { c.wtop } else { c.g };
    if crust > c.g {
        cv.put(x, z, c.g + 1, crust - 1, "minecraft:basalt", Some("minecraft:lava"), false);
        cv.put(x, z, crust, crust, "minecraft:magma_block", Some("minecraft:lava"), false);
    }
    match ng {
        Some(top) if top < c.g => {
            // the crater: dug, everything over it gone, its new face scorched (two deep near the middle), the water and
            // lava in the ground it bares sealed; where it broke into a body of water at the surface (a lake, a river,
            // the sea) and is joined to it below its level, filled with still water to that level (never higher than
            // the land stood)
            // (water it cuts into goes like any other block: what is left of it flows in, as round a TNT blast)
            // (dug out first, as it strikes: the pit open to its floor before any of it is lined)
            cv.run(x, z, top + 1, c.top.max(c.g), "minecraft:air");
            // (the lava in the ground it bares sealed as it is dug: lava pouring in would burn everything)
            let lo = seal_lo(land, bx, bz, x, z, top, r, ang, u);
            cv.put(x, z, lo, top - 1, "minecraft:stone", Some("minecraft:lava"), false);
            // (then lined, by half: the Nether's, the Aether's, the seam between; a soul fire now and then on the
            // Nether's soul soil, which never spreads)
            let side = s.side(x, z);
            for y in top - 1..=top {
                b.run(x, z, y, y, scorched(x, y, z, u, s.seed, side));
            }
            // (fire on the Nether half's floor: soul fire on soul soil, fire on netherrack, which burns on it for good;
            // nothing in the crater burns, so neither spreads)
            let fl = scorched(x, top, z, u, s.seed, side);
            let hf = mh((x * 31 + z * 17) as u32, s.seed, 0x82);
            if side == 0 && fl == "minecraft:soul_soil" && hf < 0.3 {
                b.run(x, z, top + 1, top + 1, "minecraft:soul_fire");
            } else if side == 0 && fl == "minecraft:netherrack" && u < 0.85 && hf < 0.035 {
                b.run(x, z, top + 1, top + 1, "minecraft:fire");
            }
        }
        Some(top) if top > c.g && !wet && worked => {
            // the rim: earth heaped on it, what stood there swept off (none heaped in or by the water); right by the
            // crater's edge, what its wall bares sealed
            let hk = f64::from((top - c.g).max(1));
            for y in c.g + 1..=top {
                b.run(x, z, y, y, ejecta(x, y, z, f64::from(y - c.g) / hk, s.seed, s.side(x, z)));
            }
            // (over a cooled pool: only what stood over its surface)
            if c.top > top.max(crust) {
                b.run(x, z, top.max(crust) + 1, c.top, "minecraft:air");
            }
            if u < 1.08 {
                let lo = seal_lo(land, bx, bz, x, z, c.g, r, ang, u);
                if lo < c.g - 3 {
                    b.put(x, z, lo, c.g, "minecraft:stone", Some("minecraft:lava"), false);
                }
            }
        }
        _ if c.fluid && !c.lava => {}
        Some(_) => {
            // flattened: everything standing on the land swept off (a felled tree's stump left), the grass charred; over
            // lava (a pool on the flattened land, or the rim's where no heap went on it) only what stood over its surface
            let stump = if c.trunk > 0 { 1 + (mh((x * 31 + z * 17) as u32, s.seed, 0x81) * 2.0) as i32 } else { 0 };
            let base = if c.lava { c.wtop.max(crust) } else { c.g + stump };
            if c.top > base {
                b.run(x, z, base + 1, c.top, "minecraft:air");
            }
            if c.ground == 1
                && !c.lava
                && let Some((m, grow)) = charred(s, x, z, r, ang, s.seed)
            {
                b.put(x, z, c.g, c.g, m, Some("minecraft:grass_block"), false);
                if let Some(fl) = grow {
                    b.put(x, z, c.g + 1, c.g + 1, fl, Some("minecraft:air"), false);
                }
            }
        }
        None => {
            if c.ground == 1
                && let Some((m, grow)) = charred(s, x, z, r, ang, s.seed)
            {
                b.put(x, z, c.g, c.g, m, Some("minecraft:grass_block"), false);
                if let Some(fl) = grow {
                    b.put(x, z, c.g + 1, c.g + 1, fl, Some("minecraft:air"), false);
                }
            }
            // in the band past it: the crowns stripped, in patches, wholly near it and their tops further out
            if c.leaves != 255
                && let Some(p) = band_ra(s, (r, ang))
                && vnoise(f64::from(x), f64::from(z), 5.0, s.seed ^ 0x93) < 0.25 + 0.75 * p
            {
                let keep = ((f64::from(c.top - c.g)) * (1.0 - (0.35 + 0.8 * p).min(1.0))).floor() as i32;
                b.put(x, z, c.g + 1 + keep, c.top, "minecraft:air", Some(LEAF_NAMES[c.leaves as usize]), false);
                // (and the snow that lay on them: it would be left in the air)
                b.put(x, z, c.g + 1 + keep, c.top + 1, "minecraft:air", Some(super::TIDY_SNOW), false);
            }
        }
    }
}

/// Edits sorted into the ticks they go in at.
#[derive(Default)]
pub(super) struct Due(pub(super) std::collections::BTreeMap<i32, Blocks>);
impl Due {
    pub(super) fn get(&mut self, t: f32) -> &mut Blocks {
        self.0.entry((t / 0.05).ceil() as i32).or_default()
    }
    pub(super) fn push(self, q: &mut Plan) {
        for (k, b) in self.0 {
            if !b.runs.is_empty() {
                q.ev.push((k as f32 * 0.05, Act::Blocks(Box::new(b))));
            }
        }
    }
}

/// One part of a ring of the blast: its edits as the wave reaches it, what they leave hanging tidied the tick after,
/// and the trees standing in it felled (lying out over the land past it, once the wave has swept that too).
/// How much more than its estimate it cost (1 for land of the usual height: tall forest is dearer).
fn cv_blast_part(q: &mut Plan, land: &Land, s: &Shape, used: &mut Used, cache: &mut [u8], wave: &Wave, sec: &Sector) -> f64 {
    let (bx, bz) = (q.bx, q.bz);
    let (cells, [x0, z0, x1, z1]) = sec.cells(s.cx, s.cz);
    let t = sec.when(wave);
    let (mut b, mut cv) = (Blocks::default(), Blocks::default());
    // (what each column was made, for the tidying: cleared through or left)
    let gw = (x1 - x0 + 1) as usize;
    let mut grid = vec![false; gw * (z1 - z0 + 1) as usize];
    for &(x, z) in &cells {
        cv_blast_col(&mut b, &mut cv, land, s, bx, bz, x, z, grid.get_mut((z - z0) as usize * gw + (x - x0) as usize));
    }
    // (each chunk's edits on the tick each wave has swept all of it: its sections redrawn once a wave; the crater's dug
    // out on the carve's, as it reaches the chunk's middle, well before the lining's)
    for (tc, b) in cv.split_by(|x, z| wave.carve_chunk(s.cx, s.cz, x, z)) {
        q.ev.push((tc, Act::Blocks(Box::new(b))));
    }
    let when = |x: i32, z: i32| wave.chunk(s.cx, s.cz, x, z).max(t);
    for (tc, b) in b.split_by(when) {
        q.ev.push((tc, Act::Blocks(Box::new(b))));
    }
    // (what is left hanging round what changed: leaves of a tree whose trunk went, plants whose ground went)
    // (well within the flattened land, where every column is cleared through, nothing is left hanging: only by water,
    // lava or a column not read)
    let inner = sec.r1 + f64::from(TIDY_BORDER) + 1.0 < 0.86 * CV_FLAT;
    let need = !inner || grid.iter().zip(0..).any(|(&k, i)| !k && sec.holds(f64::from(x0 + i % gw as i32) + 0.5 - s.cx, f64::from(z0 + i / gw as i32) + 0.5 - s.cz)) || {
        let b = TIDY_BORDER;
        (z0 - b..=z1 + b).any(|z| (x0 - b..=x1 + b).any(|x| at(land, bx, bz, x, z).is_none_or(|c| c.fluid)))
    };
    // (the columns round it, outside it, as the wave leaves them: so nothing is tidied twice; what each is made of
    // worked out once and kept)
    for &(x, z) in &cells {
        let i = ((z - bz + CV_READ) * CV_GW + x - bx + CV_READ) as usize;
        if let Some(k) = cache.get_mut(i) {
            *k = if grid[(z - z0) as usize * gw + (x - x0) as usize] { 1 } else { 2 };
        }
    }
    let tb = if !need { Blocks::default() } else { tidy(x0, z0, x1, z1, 40, -1, |x, z| {
        let (i, k) = (x - bx + CV_READ, z - bz + CV_READ);
        if i < 0 || k < 0 || i >= CV_GW || k >= CV_GW {
            return Col::Kept;
        }
        let ix = (k * CV_GW + i) as usize;
        if cache[ix] == 0 {
            let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
            let cleared = match at(land, bx, bz, x, z) {
                Some(c) if c.fluid && !(c.lava && lava_worked(c, s.at(x, z).2)) => false,
                // (well within the flattened land: cleared through, whatever its edge does)
                Some(_) if dx * dx + dz * dz < (0.86 * CV_FLAT).powi(2) => true,
                // (well past it: only a tree knocked flat)
                Some(c) if dx * dx + dz * dz > (1.14 * CV_FLAT).powi(2) && c.trunk < 3 => false,
                Some(c) => new_ground(c, s, x, z).is_some(),
                None => false,
            };
            // (3, 4: what the wave will make of it, not reached yet)
            cache[ix] = if cleared { 3 } else { 4 };
        }
        if cache[ix] == 1 || cache[ix] == 3 { Col::Cleared } else { Col::Kept }
    }) };
    // (what hangs over a column left as it was reaches no higher than what the read saw on it: the runs cut to that, and
    // none where nothing stood over its ground)
    let mut tb = tb;
    tb.runs.retain_mut(|r| {
        // (none over a column the wave has not reached yet: its own part tidies round it)
        let (i, k) = (r.x - bx + CV_READ, r.z - bz + CV_READ);
        if i < 0 || k < 0 || i >= CV_GW || k >= CV_GW || cache[(k * CV_GW + i) as usize] > 2 {
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
    // (on the same tick as the chunk's edits, after them: one redraw)
    for (tc, b) in tb.split_by(when) {
        q.ev.push((tc, Act::Blocks(Box::new(b))));
    }
    let mut due = Due::default();
    cv_fell(&mut due, land, s, used, wave, bx, bz, &cells);
    due.push(q);
    let tall: i32 = cells.iter().filter_map(|&(x, z)| at(land, bx, bz, x, z)).filter(|c| !c.fluid || c.lava).map(|c| (c.top - c.g).max(0)).sum();
    1.0 + f64::from(tall) / cells.len().max(1) as f64 / 35.0
}

/// The trees standing on `cells` felled, lying on the land pointing away from the blast (their leaves crushed round
/// their crowns, stripped off near it), each put in once the wave has swept the land it lies on.
// (a cheap hash: the standard one costs far more fuel a lookup)
pub(super) type Used = crate::ground::FxSet<(i32, i32)>;
fn cv_fell(due: &mut Due, land: &Land, s: &Shape, used: &mut Used, wave: &Wave, bx: i32, bz: i32, cells: &[(i32, i32)]) {
    // (a column a log may lie on: flattened, not the crater or its rim, dry, its ground near the last one's)
    let lie = |x: i32, z: i32, gy: i32| -> Option<i32> {
        let c = at(land, bx, bz, x, z)?;
        let (r, a, u) = s.at(x, z);
        if c.fluid || u < CV_RIM || (c.g - gy).abs() > 1 || wet_near(land, bx, bz, x, z) {
            return None;
        }
        // (past the flattened land: only on open ground)
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
        if u < CV_RIM || (r > s.flat(a) - 1.0 && !knocked(c, s, x, z)) {
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
        // (the crown crushed round its end, further out where the blast has not stripped it)
        if let (Some((lx, lz)), true) = (last, r > 110.0 && c.leaves != 255) {
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
        // (down once the wave has swept the farthest of it, a ring past)
        let far = put.iter().map(|&(px, pz, _, _)| (f64::from(px) + 0.5 - s.cx).hypot(f64::from(pz) + 0.5 - s.cz)).fold(0.0, f64::max);
        let b = due.get(put.iter().map(|&(px, pz, _, _)| wave.chunk(s.cx, s.cz, px, pz)).fold(wave.at(far + CV_RING + 1.0), f32::max) + 0.05);
        for (px, pz, y, m) in put {
            b.run(px, pz, y, y, m);
        }
    }
}

/// The rubble: chunks of the ground thrown out, more near it, landing over a few seconds.
/// Each lands just after the wave has swept where it lands, the nearer sooner.
/// It goes in CV_RUBBLE_PARTS parts (each a stage's job, one stream of `rng` carried from one to the next, so the
/// parts together make what one job would): two of the stones, two of the leaves and branches.
const CV_RUBBLE_PARTS: u32 = 4;
fn cv_rubble(q: &mut Plan, land: &Land, s: &Shape, used: &mut Used, wave: &Wave, rng: &mut Rng, part: u32) {
    let (bx, bz) = (q.bx, q.bz);
    let mut due = Due::default();
    let lands = |r: f64, k: f64| wave.at(r + 2.0 * CV_RING) + (0.2 + 0.3 * k) as f32;
    // (by half: what each side's lining threw out)
    const RUBBLE_N: [&str; 6] = ["minecraft:netherrack", "minecraft:netherrack", "minecraft:blackstone", "minecraft:basalt", "minecraft:magma_block", "minecraft:cobblestone"];
    const RUBBLE_P: [&str; 6] = ["minecraft:diorite", "minecraft:andesite", "minecraft:diorite", "minecraft:calcite", "minecraft:raw_gold_block", "minecraft:cobblestone"];
    crate::meter::spend(2_400 * 1100 / u64::from(CV_RUBBLE_PARTS));
    let stones = if part < 2 { part as usize * 1100..(part as usize + 1) * 1100 } else { 0..0 };
    for _ in stones {
        // (in rays out from the crater: all round it near the rim, further out only along them, the longest out to
        // CV_RUBBLE)
        let r = cr() * 1.05 + (CV_RUBBLE - cr() * 1.05) * rng.next().powf(1.5);
        let a = rng.uniform(0.0, TAU);
        let ray = s.ray(a);
        let reach = cr() * 2.0 + (CV_RUBBLE - cr() * 2.0) * ray;
        if r > cr() * 1.8 && (r > reach || rng.next() > 0.1 + 0.9 * ray) {
            continue;
        }
        let (x, z) = ((s.cx + a.cos() * r).floor() as i32, (s.cz + a.sin() * r).floor() as i32);
        let Some(c) = at(land, bx, bz, x, z) else { continue };
        if c.fluid || used.contains(&(x, z)) || wet_near(land, bx, bz, x, z) {
            continue;
        }
        let y = match new_ground(c, s, x, z) {
            Some(top) => top + 1,
            // (past the flattened land: only where nothing taller than a plant stands)
            None if c.top <= c.g + 1 && c.trunk == 0 => c.g + 1,
            None => continue,
        };
        let m = if s.side(x, z) == 0 { *rng.pick(&RUBBLE_N) } else { *rng.pick(&RUBBLE_P) };
        let t = lands(r, rng.next());
        due.get(t).run(x, z, y, y, m);
        used.insert((x, z));
        // (now and then a bigger chunk: two side by side)
        if rng.next() < 0.25 && r < 140.0 {
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
    // leaves and broken branches strewn over the outer land and the band, of the wood that grows here
    let woods = land.woods;
    let wood = (0..9).max_by_key(|&i| woods[i]).unwrap_or(0);
    if woods[wood] > 0 && part >= 2 {
        for n in (part as usize - 2) * 600..(part as usize - 1) * 600 {
            let r = cr() * 1.45 + (CV_FLAT * 1.1 + CV_BAND - cr() * 1.45) * rng.next().powf(0.8);
            let a = rng.uniform(0.0, TAU);
            let (x, z) = ((s.cx + a.cos() * r).floor() as i32, (s.cz + a.sin() * r).floor() as i32);
            let Some(c) = at(land, bx, bz, x, z) else { continue };
            if c.fluid || used.contains(&(x, z)) || wet_near(land, bx, bz, x, z) {
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

/// The basalt the Nether leaves round its half of the crater: CV_AFTER_PILLARS clusters on the land past the rim,
/// taller nearer it, each rising out of the ground over CV_RISE_STEPS steps once the blast's wave has swept it and the
/// aftermath has begun (on the ground the blast left: its rim's heap, the flattened land).
const CV_AFTER_PILLARS: u32 = 11;
fn cv_after_pillars(q: &mut Plan, land: &Land, s: &Shape, used: &mut Used, wave: &Wave) {
    let (bx, bz) = (q.bx, q.bz);
    let mut due = Due::default();
    for k in 0..CV_AFTER_PILLARS {
        let h = |t: u32| mh(k, s.seed, t);
        let a = s.seam + 0.25 + (PI - 0.5) * (f64::from(k) + 0.15 + 0.7 * h(0x61)) / f64::from(CV_AFTER_PILLARS);
        let r = cr() * (1.1 + 0.85 * h(0x62).powf(0.8));
        let pr = 1.6 + 1.8 * h(0x63);
        let tall = (9.0 + 15.0 * (1.0 - (r / cr() - 1.1) / 0.85) * (0.6 + 0.4 * h(0x64))).max(6.0);
        let (px, pz) = (s.cx + a.cos() * r, s.cz + a.sin() * r);
        let n = pr.ceil() as i32 + 1;
        let mut cols = Vec::new();
        for oz in -n..=n {
            for ox in -n..=n {
                crate::meter::spend(800);
                let (x, z) = (px.floor() as i32 + ox, pz.floor() as i32 + oz);
                let d = (f64::from(x) + 0.5 - px).hypot(f64::from(z) + 0.5 - pz);
                if d >= pr {
                    continue;
                }
                let Some(c) = at(land, bx, bz, x, z) else { continue };
                if c.fluid || wet_near(land, bx, bz, x, z) || s.side(x, z) != 0 {
                    continue;
                }
                let g = match new_ground(c, s, x, z) {
                    Some(t) => t,
                    None if c.top <= c.g + 1 => c.g,
                    None => continue,
                };
                let jag = mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917)) as u32, s.seed, 0x65);
                let hh = (tall * (1.0 - 0.4 * d / pr) * (0.8 + 0.4 * jag)).round().max(2.0) as i32;
                cols.push((x, z, g, hh));
            }
        }
        if cols.is_empty() {
            continue;
        }
        // (after the wave and its tidying have been through every chunk it stands in)
        let t0 = cols.iter().map(|&(x, z, _, _)| wave.chunk(s.cx, s.cz, x, z)).fold(CV_CLOSE + 4.0 * h(0x66) as f32, f32::max) + 0.3;
        for &(x, z, g, hh) in &cols {
            used.insert((x, z));
            let mut last = 0;
            for st in 1..=CV_RISE_STEPS {
                let y = hh * st / CV_RISE_STEPS;
                if y > last {
                    due.get(t0 + CV_PRE_STEP * (st - 1) as f32).run(x, z, g + 1 + last, g + y, "minecraft:basalt");
                    last = y;
                }
            }
        }
    }
    due.push(q);
}

/// Real blocks thrown out of the crater as it is blasted open: the ground that was there (grass and dirt off its top, the
/// stone and tuff under it, now and then a log of the wood growing round it), flung outward and up over the first second
/// and a half, at all speeds, so some come down by the rim and some arc far out over the flattened land. Some land as
/// blocks, the rest break up where they land (CancelDrop); none drops an item.
fn cv_thrown(q: &mut Plan, land: &Land, s: &Shape, part: u64) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7410 ^ (part << 20));
    let woods = land.woods;
    let wood = (0..9).max_by_key(|&i| woods[i]).filter(|&i| woods[i] > 0);
    let mut n = 0;
    crate::meter::spend(CV_THROWN as u64 * 3 / 2 * 3_000);
    for _ in 0..CV_THROWN * 3 / 2 {
        if n >= CV_THROWN / 2 {
            break;
        }
        // (from anywhere in the crater, more from its middle)
        let r = 4.0 + (cr() * 0.85 - 4.0) * rng.next().sqrt();
        let a = rng.uniform(0.0, TAU);
        let (x, z) = (s.cx + a.cos() * r, s.cz + a.sin() * r);
        let (ix, iz) = (x.floor() as i32, z.floor() as i32);
        let Some(c) = at(land, bx, bz, ix, iz) else { continue };
        if !c.known || c.fluid || wet_near(land, bx, bz, ix, iz) {
            continue;
        }
        let deep = rng.next();
        let nether = s.side(ix, iz) == 0;
        let blk = match (c.ground, deep) {
            (_, d) if d < 0.08 && wood.is_some() => LOG_Y[wood.unwrap_or(0)],
            (1, d) if d < 0.3 => "minecraft:grass_block",
            (1 | 2, d) if d < 0.5 => "minecraft:dirt",
            (_, d) if d < 0.75 => if nether { "minecraft:netherrack" } else { "minecraft:calcite" },
            (_, d) if d < 0.85 => if nether { "minecraft:blackstone" } else { "minecraft:diorite" },
            (_, d) if d < 0.92 => "minecraft:stone",
            _ => if nether { "minecraft:magma_block" } else { "minecraft:raw_gold_block" },
        };
        // (outward from the middle (straight up near it, leaning out further off), at speeds from a lob that lands by
        // the rim to a hard throw that comes down a hundred blocks off; blocks a tick)
        let ang = if r > 1.0 { a } else { rng.uniform(0.0, TAU) };
        let h = 0.3 + 1.6 * rng.next().powf(1.3);
        let vy = 2.0 + 2.6 * rng.next();
        let (vx, vz) = (ang.cos() * h, ang.sin() * h);
        let y = f64::from(c.g) + 1.2 + 2.5 * rng.next();
        // (as it strikes, with the shock and the carve)
        let t = CV_HIT + 0.1 + (r / 343.0) as f32 + 1.25 * rng.next().powf(1.3) as f32;
        let keep = if rng.next() < 0.45 { "" } else { ",CancelDrop:1b" };
        q.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
        n += 1;
    }
}

// ---- before the blast: the land's own changes, column by column -------------------------------------------------------
/// The pre-blast edits go in on steps this long (each chunk resent at most so often while the land creeps).
const CV_PRE_STEP: f32 = 0.4;
/// The basalt rises over this many steps.
const CV_RISE_STEPS: i32 = 7;
fn pre_t(t: f32) -> f32 {
    (t / CV_PRE_STEP).ceil() * CV_PRE_STEP
}
/// What happens to the land of sector `sec` before the blast: the cracks glowing then opening, the veins of
/// netherrack, the basalt shouldering up, then the land taking sides (Nether, Aether, the seam between). Each column's
/// tallest new block kept in the land (`top`), so the blast clears it.
fn cv_pre_part(q: &mut Plan, land: &mut Land, s: &Shape, pillars: &[(f64, f64, f64, i32, f32)], sec: &Sector) {
    let (bx, bz) = (q.bx, q.bz);
    let seed = s.seed;
    let (cells, _) = sec.cells(s.cx, s.cz);
    let mut due = Due::default();
    for &(x, z) in &cells {
        crate::meter::spend(2_500);
        let Some(c) = at(land, bx, bz, x, z).copied() else { continue };
        if c.fluid {
            continue;
        }
        let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
        let r = dx.hypot(dz);
        let n = vnoise(f64::from(x), f64::from(z), 7.0, seed ^ 0xc8);
        // (how far from the nearest crack: read only by the cracks and the veins, so worked out only within their reach)
        let dc = if r < CV_CRACK_R.max(CV_VEIN_R) { cv_crack(seed, dx, dz) } else { f64::MAX };
        let mut top = c.top;
        // the cracks: drawn by the pass over the omen (no block changes before the break); opened into fissures from
        // the break, out from the middle as the fire stands in them, magma at their foot
        if dc < 0.75 && r < CV_CRACK_R {
            // (not by lava: it would pour into the fissure)
            if !lava_near(land, bx, bz, x, z) {
                let t1 = CV_BREAK + 0.3 + 4.0 * (r / CV_CRACK_R) as f32;
                let deep = 2 + (4.0 * (1.0 - r / CV_CRACK_R)) as i32;
                let b = due.get(pre_t(t1));
                b.run(x, z, c.g - deep - 1, c.g - deep - 1, "minecraft:magma_block");
                b.run(x, z, c.g - deep, c.top.max(c.g), "minecraft:air");
            }
            continue;
        }
        // the veins: netherrack creeping out round the cracks, magma along their middles
        let w = 0.8 + 3.2 * n;
        if r < CV_VEIN_R && dc < w {
            let t = CV_BREAK + 0.8 + 7.0 * (r / CV_VEIN_R) as f32 + 0.35 * dc as f32;
            due.get(pre_t(t)).run(x, z, c.g, c.g, if dc < 1.4 { "minecraft:magma_block" } else { "minecraft:netherrack" });
        }
        // the basalt: shouldering up in three steps (no cluster reaches past CV_PILLAR_R1 and its widest radius)
        let near: &[(f64, f64, f64, i32, f32)] = if r < CV_PILLAR_R1 + 4.0 { pillars } else { &[] };
        for &(px, pz, pr, ph, pt) in near {
            let d = (dx - px).hypot(dz - pz);
            if d < pr {
                let jag = mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917)) as u32, seed, 0xd6);
                let h = (f64::from(ph) * (1.0 - 0.45 * d / pr) * (0.8 + 0.4 * jag)).round().max(2.0) as i32;
                // (rising out of the ground over CV_RISE_STEPS steps, a block or two each)
                let mut last = 0;
                for k in 1..=CV_RISE_STEPS {
                    let y = h * k / CV_RISE_STEPS;
                    if y > last {
                        due.get(pre_t(pt + CV_PRE_STEP * (k - 1) as f32)).run(x, z, c.g + 1 + last, c.g + y, "minecraft:basalt");
                        last = y;
                    }
                }
                top = top.max(c.g + h);
                break;
            }
        }
        // the land taking sides, out from the middle
        if r < CV_SIDE_R {
            let t = CV_MEET + 0.3 + 9.2 * ((r / CV_SIDE_R) * (0.85 + 0.3 * n)).min(1.0) as f32;
            let (side, ds) = cv_side(s.seam, dx, dz);
            let (blk, grow) = if ds < CV_SEAM_W {
                (seam_block(x, z, seed), None)
            } else if side == 0 {
                nether_top(x, z, seed)
            } else {
                pale_top(x, z, seed)
            };
            let b = due.get(pre_t(t));
            b.run(x, z, c.g, c.g, blk);
            if let Some(g) = grow
                && c.trunk == 0
                && c.top <= c.g + 1
                && top == c.top
            {
                b.run(x, z, c.g + 1, c.g + 1, g);
                top = top.max(c.g + 1);
            }
        }
        if top > c.top {
            let (i, k) = (x - bx + CV_READ, z - bz + CV_READ);
            if let Some(col) = land.cols.get_mut((k * CV_GW + i) as usize) {
                col.top = top;
            }
        }
    }
    due.push(q);
}

/// The islands left hanging in the sky over the crater (`cv_islands`), small pieces of the Aether: a top of pale
/// grass (pale moss, a flower or two), pale stone under it (calcite, diorite) with glowing yellow (glowstone) and gold
/// in it, tapering underneath to a pale yellow point (smooth sandstone); a tree on it (an oak) and a cloud or two
/// beside it (white and pale blue glass). Each grows out of the clash's
/// light from its start: its top spreading from the middle out, then down a layer a step, then its tree up and its
/// crown; never all at once. Each hangs at least CV_ISLAND_CLEAR over the highest ground under it.
const CV_ISLAND_CLEAR: i32 = 24;
fn cv_islands_part(q: &mut Plan, land: &Land, s: &Shape, gy: i32, only: usize) {
    let (bx, bz) = (q.bx, q.bz);
    let mut due = Due::default();
    for (k, (dx, dz, h, rr, t0)) in cv_islands(s.seed).into_iter().enumerate().filter(|e| e.0 == only) {
        let ks = k as u32;
        let (ix, iz) = ((s.cx + dx).floor() as i32, (s.cz + dz).floor() as i32);
        let n = rr.ceil() as i32 + 1;
        // (its columns: how far each reaches down, from the top's height)
        let mut cols = Vec::new();
        let mut under = gy;
        for oz in -n..=n {
            for ox in -n..=n {
                crate::meter::spend(600);
                let (x, z) = (ix + ox, iz + oz);
                let wob = 1.0 + 0.36 * (vnoise(f64::from(x), f64::from(z), 3.0, s.seed ^ (0xf0 + ks)) - 0.5);
                let d = f64::from(ox).hypot(f64::from(oz)) / (rr * wob);
                if d >= 1.0 {
                    continue;
                }
                let rough = vnoise(f64::from(x), f64::from(z), 2.0, s.seed ^ (0xf8 + ks));
                let depth = ((rr * 1.25) * (1.0 - d * d).powf(0.9) * (0.75 + 0.5 * rough)).round().max(1.0) as i32;
                if let Some(c) = at(land, bx, bz, x, z) {
                    under = under.max(c.top);
                }
                cols.push((x, z, d, depth));
            }
        }
        let deepest = cols.iter().map(|c| c.3).max().unwrap_or(1);
        let y0 = (gy + h.round() as i32).max(under + CV_ISLAND_CLEAR + deepest).min(300);
        // the top, spreading from its middle out (CV_GROW_STEP a ring of a third of its radius)
        for &(x, z, d, _) in &cols {
            let f = mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, s.seed, 0xf1);
            let t = t0 + CV_GROW_STEP * (d * 3.0).floor() as f32;
            let b = due.get(t);
            b.run(x, z, y0, y0, "minecraft:pale_moss_block");
            // (flowers on it, never where the tree stands)
            if d > 0.3 && d < 0.85 {
                if f < 0.05 {
                    b.run(x, z, y0 + 1, y0 + 1, "minecraft:lily_of_the_valley");
                } else if f < 0.07 {
                    b.run(x, z, y0 + 1, y0 + 1, "minecraft:allium");
                } else if f < 0.14 {
                    b.run(x, z, y0 + 1, y0 + 1, "minecraft:pale_moss_carpet");
                }
            }
        }
        // the body, down a layer a step once the top is whole: pale stone, its last block or two pale yellow
        let body = t0 + CV_GROW_STEP * 3.0;
        for &(x, z, _, depth) in &cols {
            for l in 1..=depth {
                let y = y0 - l;
                let f = mh((x.wrapping_mul(19_349_663) ^ y.wrapping_mul(83_492_791) ^ z.wrapping_mul(73_856_093)) as u32, s.seed, 0xf2);
                let m = vnoise(f64::from(x) + f64::from(y) * 0.4, f64::from(z), 3.0, s.seed ^ 0xf3);
                let blk = if l >= depth - 1 && depth > 2 {
                    "minecraft:smooth_sandstone"
                } else if f < 0.05 {
                    "minecraft:glowstone"
                } else if f < 0.08 {
                    "minecraft:raw_gold_block"
                } else if m > 0.6 {
                    "minecraft:andesite"
                } else if m < 0.3 {
                    "minecraft:calcite"
                } else {
                    "minecraft:diorite"
                };
                due.get(body + CV_GROW_STEP * (l - 1) as f32).run(x, z, y, y, blk);
            }
        }
        // its tree (an oak on the middle), up a block a step once the body is down, then its crown
        let tt = body + CV_GROW_STEP * deepest as f32;
        let trunk = 5 + (mh(ks, s.seed, 0xf4) * 3.0) as i32 + i32::from(rr > 11.0);
        let crown: i32 = if rr > 11.0 { 3 } else { 2 };
        for l in 1..=trunk {
            due.get(tt + CV_GROW_STEP * 0.5 * (l - 1) as f32).run(ix, iz, y0 + l, y0 + l, "minecraft:oak_log");
        }
        let tc = tt + CV_GROW_STEP * 0.5 * trunk as f32;
        for oy in -1..=2 {
            let w: i32 = if oy >= 2 { crown - 1 } else { crown };
            for oz in -w..=w {
                for ox in -w..=w {
                    if (ox == 0 && oz == 0 && oy < 1) || (ox.abs() == w && oz.abs() == w && (oy == 2 || mh((ox * 7 + oz * 13 + oy * 29) as u32, s.seed ^ ks, 0xf5) < 0.5)) {
                        continue;
                    }
                    due.get(tc + CV_GROW_STEP * (oy + 1) as f32).run(ix + ox, iz + oz, y0 + trunk + oy, y0 + trunk + oy, "minecraft:oak_leaves[persistent=true]");
                }
            }
        }
        // a cloud or two drifting by it, flat, a little under its top, filling in over two steps
        let nc = 1 + (mh(ks, s.seed, 0xf6) * 2.0) as i32;
        for c in 0..nc {
            let a = TAU * mh(ks * 3 + c as u32, s.seed, 0xf7);
            let dist = rr + 4.0 + 4.0 * mh(ks * 3 + c as u32, s.seed, 0xf8);
            let (ccx, ccz) = (ix + (a.cos() * dist).round() as i32, iz + (a.sin() * dist).round() as i32);
            let cy = y0 - 2 - (mh(ks * 3 + c as u32, s.seed, 0xf9) * 4.0) as i32;
            let blk = if c == 1 { "minecraft:light_blue_stained_glass" } else { "minecraft:white_stained_glass" };
            let (lx, lz) = (3 + (c % 2), 2);
            for oz in -lz..=lz {
                for ox in -lx..=lx {
                    let e = (f64::from(ox) / f64::from(lx) + 0.1).powi(2) + (f64::from(oz) / f64::from(lz) + 0.1).powi(2);
                    if e > 1.15 {
                        continue;
                    }
                    let t = tt + CV_GROW_STEP * (if e < 0.5 { 0.0 } else { 1.0 });
                    due.get(t).run(ccx + ox, ccz + oz, cy, cy + i32::from(e < 0.3), blk);
                }
            }
        }
    }
    due.push(q);
}

// ---- the land's work: one stage a tick, in order --------------------------------------------------------------------
/// All the land's work is one chain of stages, a tick each, so none of it ever waits behind the rest or queues out of
/// order: the land read (its rings asked from the middle out and taken in as they are answered), then the blast's parts
/// ring by ring from the middle out.
/// Each stage does about CV_BUDGET columns' worth (well under a tick's fuel).
const CV_BUDGET: f64 = 1200.0;
/// About what a unit of that work costs in instructions (the game's count of the stages' fuel over their estimates).
const CV_UNIT: f64 = 15_000.0;
/// A job after the first of a stage starts only if the meter, with as much again as the job before it took (or its
/// estimate, if more), stays under this: the blast's parts in the crater cost the game up to half as much again as the
/// meter reads, so a stage of them stays under about a third of a tick's fuel.
const CV_STAGE_SOFT: u64 = 10_000_000;
/// How long the land's work waits for columns the world has not loaded (a target far off, its chunks forceloaded and
/// generated as the strike goes on) before it leaves them out: some 35 s after the burst.
const CV_LAND_BY: f32 = CV_HIT + 20.0;
/// How long, once the crater's land is in, it waits for more of the rest to come.
const CV_PATIENCE: f32 = 4.0;
enum Job {
    After,
    Pre(Sector),
    Islands(usize),
    Thrown(u64),
    Rubble(u32),
    Blast(Sector),
}
struct Work {
    land: Land,
    s: Shape,
    wave: Wave,
    used: Used,
    /// What the blast made of each column of the land's square (0 not yet known, 1 cleared through, 2 left), for the
    /// tidying.
    made: Vec<u8>,
    gy: i32,
    tags: Vec<u32>,
    asked: usize,
    taken: usize,
    /// The ring of unloaded columns asked again (one at a time, the rings in turn): its tag, ring, columns and when.
    retry: Option<(u32, usize, Vec<(i32, i32)>, f32)>,
    /// The ring to ask again next, and when.
    rnext: usize,
    rat: f32,
    /// Columns not loaded at the last stage, and when last some came.
    left: usize,
    came: f32,
    jobs: std::collections::VecDeque<Job>,
    pillars: Vec<(f64, f64, f64, i32, f32)>,
    /// The rubble's one stream of chances, carried from each of its parts to the next.
    rubble: Rng,
}
impl Work {
    fn new(s: Shape, gy: i32) -> Self {
        let mut jobs = std::collections::VecDeque::new();
        // (400 columns a part: one costs the game about a fifth of a tick's fuel)
        for sec in sectors(0.0, CV_SIDE_R + 1.0, 8.0, 400.0, 200.0) {
            jobs.push_back(Job::Pre(sec));
        }
        // (the islands after the land's changes before the blast: they start to grow only in the clash)
        for k in 0..tuned().islands as usize {
            jobs.push_back(Job::Islands(k));
        }
        jobs.push_back(Job::Thrown(0));
        jobs.push_back(Job::Thrown(1));
        let mut rubble = false;
        for sec in sectors(0.0, f64::from(CV_READ) + 1.0, CV_RING, CV_ITEM, 150.0) {
            if !rubble && sec.r0 >= cr() * CV_RIM {
                jobs.push_back(Job::After);
                for k in 0..CV_RUBBLE_PARTS {
                    jobs.push_back(Job::Rubble(k));
                }
                rubble = true;
            }
            jobs.push_back(Job::Blast(sec));
        }
        Work {
            land: Land { cols: zeroed_cols((CV_GW * CV_GW) as usize), missing: vec![Vec::new(); CV_PARTS as usize], woods: [0; 9], done: false },
            s,
            wave: Wave::new(),
            used: Default::default(),
            made: vec![0; (CV_GW * CV_GW) as usize],
            gy,
            tags: (0..CV_PARTS).map(|_| crate::columns::new_tag()).collect(),
            asked: 0,
            taken: 0,
            retry: None,
            rnext: 0,
            rat: 0.0,
            left: usize::MAX,
            came: 0.0,
            jobs,
            pillars: cv_pillars(s.seed),
            rubble: Rng::new(u64::from(s.seed) ^ 0x7e57),
        }
    }
    /// How far out the land is in (every column within it read): out to the rings taken in, short of the first ring
    /// with columns the world had not loaded (those asked again, and the ring being asked). A few dozen steps however
    /// much is missing: it is asked again for each job each stage.
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
    /// Columns still not loaded.
    fn unloaded(&self) -> usize {
        self.land.missing.iter().map(Vec::len).sum::<usize>() + self.retry.as_ref().map_or(0, |r| r.2.len())
    }
    /// Whether job `j` can be done now; and whether the jobs after it must wait for it (the wave's parts go in order).
    fn can(&self, j: &Job) -> (bool, bool) {
        match j {
            Job::Pre(sec) => (self.ready() >= sec.r1 + 4.0, false),
            Job::Islands(_) => (self.ready() >= 112.0, false),
            Job::Thrown(_) => (self.ready() >= cr() * 1.3, false),
            Job::Rubble(_) | Job::After => (self.land.done, false),
            Job::Blast(sec) => (self.ready() >= sec.r1 + 12.0, true),
        }
    }
    fn cost(j: &Job) -> f64 {
        match j {
            Job::Pre(s) => s.da.min(TAU) / 2.0 * (s.r1 * s.r1 - s.r0 * s.r0) * 2.5,
            Job::Islands(_) => CV_BUDGET,
            Job::Thrown(_) => 900.0,
            Job::Rubble(_) => CV_BUDGET / 2.0,
            Job::After => 400.0,
            Job::Blast(s) => {
                let a = s.da.min(TAU) / 2.0 * (s.r1 * s.r1 - s.r0 * s.r0);
                // (a column's work: the crater's, its rim's, the flattened land's, the band's past it (tidied), the
                // measured)
                let u = s.r0 / cr();
                let k = if u < 1.0 {
                    0.9
                } else if u < CV_RIM {
                    0.6
                } else if s.r1 + 4.0 < 0.86 * CV_FLAT {
                    0.6
                } else {
                    0.75
                };
                a * k
            }
        }
    }
}

/// `n` columns, none known, allocated zeroed: the land's grid of 263,000 columns cloned one by one took most of the
/// set-up stage (1.3-1.8 ms natively), zeroed memory nearly none.
fn zeroed_cols(n: usize) -> Vec<Column> {
    if n == 0 {
        return Vec::new();
    }
    let layout = std::alloc::Layout::array::<Column>(n).expect("the land's grid");
    // SAFETY: every field of Column is a bool or an integer, for which all zero bits are valid (and are its Default);
    // the pointer comes from the global allocator with Column's own layout, its length and capacity both n.
    unsafe {
        let p = std::alloc::alloc_zeroed(layout).cast::<Column>();
        if p.is_null() {
            std::alloc::handle_alloc_error(layout);
        }
        Vec::from_raw_parts(p, n, n)
    }
}

/// One stage of the land's work.
fn cv_work(q: &mut Plan, w: Rc<RefCell<Work>>, now: f32) {
    let more = {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        let (bx, bz) = (q.bx, q.bz);
        let mut spent = 0.0;
        // the reads: the land's rings two a stage from the middle out
        if wk.asked < wk.tags.len() {
            // (two a stage: the parts are small, so none is much to take in on a tick)
            for _ in 0..2.min(wk.tags.len() - wk.asked) {
                let part = wk.asked;
                q.ev.push((now, Act::Read { tag: wk.tags[part], columns: read_columns(bx, bz, part as i32), below: CV_BELOW, above: CV_ABOVE }));
                wk.asked += 1;
                spent += 75.0;
            }
        }
        // their answers taken in as they come (up to four a stage)
        // (their take-in counts high: the game's count of its fuel is a fraction of the meter's)
        for _ in 0..4 {
            if wk.taken < wk.asked
                && !crate::meter::full()
                && let Some(a) = crate::columns::take(wk.tags[wk.taken])
            {
                let part = wk.taken;
                take_in(&mut wk.land, &a, bx, bz, part);
                if part == 0 {
                    // (the burst's ground from the land read, not from where the designator's ray met it: far off that is
                    // the far terrain's rough copy of it)
                    if let Some(c) = wk.land.cols.get((CV_READ * CV_GW + CV_READ) as usize).filter(|c| c.known) {
                        wk.gy = if c.fluid { c.wtop } else { c.g } + 1;
                    }
                }
                wk.taken += 1;
                spent += 300.0;
            }
        }
        if wk.taken == wk.tags.len() && !wk.land.done {
            // (the columns the world had not loaded yet, as at a target far off in the far terrain, its chunks only
            // forceloaded as the strike began: asked again a ring at a time, the rings in turn, until it has, and the
            // land's work waits for them (parked: a few steps a stage), its changes going in late as they come; given up
            // on long after the burst)
            if let Some((tag, part, _, since)) = &wk.retry {
                let (tag, part, since) = (*tag, *part, *since);
                if let Some(a) = crate::columns::take(tag) {
                    take_in(&mut wk.land, &a, bx, bz, part);
                    wk.retry = None;
                    spent += 300.0;
                } else if now > since + 3.0 {
                    // (the answer lost: its columns asked again later)
                    if let Some((_, part, cols, _)) = wk.retry.take() {
                        wk.land.missing[part] = cols;
                    }
                }
            }
            let left = wk.unloaded();
            if left < wk.left && wk.left != usize::MAX {
                wk.came = now;
            }
            wk.left = left;
            // (the crater's land in and nothing more coming for a while, as land that will not load past the edge of
            // what the world has: the rest left out, not the whole of the land held back for it)
            let stalled = now - wk.came > CV_PATIENCE && wk.ready() >= cr() * 1.3;
            if left == 0 {
                wk.land.done = true;
            } else if now > CV_LAND_BY || stalled {
                crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("convergence: {left} columns of the land never loaded; the terrain left out there"));
                wk.land.done = true;
            } else if wk.retry.is_none() && now >= wk.rat {
                let n = wk.land.missing.len();
                if let Some(part) = (0..n).map(|j| (wk.rnext + j) % n).find(|&j| !wk.land.missing[j].is_empty()) {
                    let cols = std::mem::take(&mut wk.land.missing[part]);
                    crate::meter::spend(40 * cols.len() as u64);
                    let tag = crate::columns::new_tag();
                    q.ev.push((now, Act::Read { tag, columns: cols.clone(), below: CV_BELOW, above: CV_ABOVE }));
                    wk.retry = Some((tag, part, cols, now));
                    wk.rnext = part + 1;
                    // (the next a little later: the world given time to load them)
                    wk.rat = now + 0.1;
                    spent += 150.0;
                }
            }
        }
        crate::trace("cv land taken");
        // the jobs: the first that can be done (never past one of the wave's parts that cannot yet: they go in order)
        let mut last = 0u64;
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
            // (and none past the tick's mark for its work, whatever the estimates said: `meter`)
            let ahead = last.max((c * CV_UNIT) as u64);
            if spent > 0.0 && (spent + c > CV_BUDGET || crate::meter::full() || crate::meter::spent() + ahead > CV_STAGE_SOFT) {
                break;
            }
            let before = crate::meter::spent();
            spent += c;
            // (what the job is expected to cost, on top of what its loops count: `meter` reads high, not low)
            crate::meter::spend((c * CV_UNIT) as u64);
            let job = wk.jobs.remove(i).unwrap_or(Job::After);
            let job_kind = match &job { Job::Thrown(_) => 0, Job::Rubble(_) | Job::After => 1, Job::Blast(_) => 2, Job::Pre(_) | Job::Islands(_) => 3 };
            match job {
                Job::Pre(sec) => {
                    let pillars = std::mem::take(&mut wk.pillars);
                    cv_pre_part(q, &mut wk.land, &wk.s, &pillars, &sec);
                    wk.pillars = pillars;
                }
                Job::Islands(k) => cv_islands_part(q, &wk.land, &wk.s, wk.gy, k),
                Job::Thrown(part) => cv_thrown(q, &wk.land, &wk.s, part),
                Job::After => {
                    let wave = wk.wave.clone();
                    cv_after_pillars(q, &wk.land, &wk.s, &mut wk.used, &wave);
                }
                Job::Rubble(part) => {
                    let wave = wk.wave.clone();
                    cv_rubble(q, &wk.land, &wk.s, &mut wk.used, &wave, &mut wk.rubble, part);
                }
                Job::Blast(sec) => {
                    let wave = wk.wave.clone();
                    let k = cv_blast_part(q, &wk.land, &wk.s, &mut wk.used, &mut wk.made, &wave, &sec);
                    spent += c * (k - 1.0);
                }
            }
            crate::trace(match &job_kind { 0 => "cv thrown", 1 => "cv rubble", 2 => "cv blast", _ => "cv before" });
            last = crate::meter::spent() - before;
        }
        !wk.jobs.is_empty()
    };
    // (and given up long after the burst if the world never answers: the land's changes may go in this late, a target
    // far off loading slowly)
    if more && now < CV_LAND_BY + 10.0 {
        q.later(now + 0.05, move |q| cv_work(q, w, now + 0.05));
    }
}

/// The blast's front reaching the player at `t`, `fo` as hard: a violent hit, kicked again and again, then a shudder
/// dying away over five or six seconds (the Rod's). The pass knocks the picture about on top of it (`cv_jolt` in
/// convergence.wgsl).
fn cv_jolt(p: &mut Plan, t: f32, fo: f32) {
    p.shake(t, fo, 1.8);
    for n in 0..12 {
        let u = n as f32 / 12.0;
        p.shake(t + 0.05 + 0.08 * n as f32, (1.0 - 0.4 * u) * fo, 0.2);
    }
    p.shake(t + 0.3, 0.65 * fo, 6.0);
    let mut ts = t + 1.2;
    while ts < t + 6.0 {
        let u = (ts - t - 1.2) / 4.8;
        p.shake(ts, (0.6 * (1.0 - u).powf(1.4) + 0.08) * fo, 0.28);
        ts += 0.13 + 0.1 * u;
    }
}

/// The blast front's knockback (`Act::Shove`): blocks a tick out from the burst and up, none past CV_KNOCK_REACH.
pub(super) const CV_KNOCK_OUT: f32 = 0.7;
pub(super) const CV_KNOCK_UP: f32 = 0.5;
pub(super) const CV_KNOCK_REACH: f32 = 450.0;

// ---- the sounds (tools/sounds_convergence.py builds the files: orbital-sounds/assets/orbital/sounds/convergence/) -------
/// When heaven's win (the choir arriving after the blast) starts. tools/sounds_convergence.py's WIN0.
const CV_WIN0: f32 = 26.9;
/// The layers of hell and heaven, each its own event: (event, its file's start on the strike clock, whether it carries
/// as the columns do). tools/sounds_convergence.py's LAYERS and LAYER_GAIN.
const CV_LAYERS: [(&str, f32, bool); 4] = [("hell", 3.0, false), ("furnace", 6.0, false), ("choir", 5.0, false), ("thunder", 4.8, false)];
fn smooth01(x: f64) -> f64 {
    let x = x.clamp(0.0, 1.0);
    x * x * (3.0 - 2.0 * x)
}
/// The files' distance tiers and their weights `dist` blocks from the target: the near files alone out to 500 (as far
/// as it is watched from: heard close and whole), near to mid over 500-900, mid to far over 1100-2000 (each file carries
/// its own distance; a tier under 0.001 is left out).
fn cv_tiers(dist: f64) -> Vec<(&'static str, f32)> {
    let a = smooth01((dist - 500.0) / 400.0);
    let b = smooth01((dist - 1100.0) / 900.0);
    [("near", 1.0 - a), ("mid", a * (1.0 - b)), ("far", a * b)].into_iter().filter(|t| t.1 >= 0.001).map(|(n, w)| (n, w as f32)).collect()
}
/// The volume for distance alone, whole out to 450 blocks: the columns (as tall as the sky, they carry), and everything
/// else.
fn cv_gain_columns(dist: f64) -> f32 {
    (1.0 / (1.0 + (dist - 450.0).max(0.0) / 1500.0)).clamp(0.6, 1.0) as f32
}
fn cv_gain(dist: f64) -> f32 {
    (1.0 / (1.0 + (dist - 450.0).max(0.0) / 700.0)).clamp(0.45, 1.0) as f32
}
/// Where the blast's hit lands in its file, and each surge's (its file from that long before its push peaks).
/// tools/sounds_convergence.py's BLAST_AT and SURGE_HIT.
const CV_BLAST_HIT: f32 = 0.25;
const CV_SURGE_HIT: f32 = 0.45;
/// The file for event `role` (`blast`, `surge_3`, ...) in tier `tier`: `role_tier`, or `role` with no tier
/// (tools/sounds_convergence.py's `name_of`).
fn cv_file(role: &str, tier: &str) -> String {
    if tier.is_empty() { role.to_string() } else { format!("{role}_{tier}") }
}

/// The sounds, every one following the player (tools/sounds_convergence.py builds them, its `cues` mirrors this). The beats the player watches are heard as they are
/// seen, on the strike clock and never late by the distance (each file carries its distance in its tier): the cracks
/// giving on CV_BREAK and the fire erupting on CV_RED0 (`erupt`, from 3.0), the rift opening (inside `aether`), the
/// impact's hit on CV_MEET, each surge's blow on the peak of its push (CV_SURGE_ATK after its start, CV_SURGE_HIT into
/// its file), heaven's drive down ending on CV_HIT (`drive`), the blast's blow on CV_HIT (CV_BLAST_HIT into its file). Before CV_CROUCH no
/// column: the ground's voice and the sky's (`nether`, `aether`, their draw-back built in); from CV_CROUCH the impact's
/// file (the held breath, the launch, the hit 1.0 s in); from CV_MEET the two columns pressed together (`clash`) to
/// their cut into the blast; the fire from CV_BREAK under it all to the blast (`fire`); the land torn in two after the
/// blast (`sunder`). Only the ground's quake (through the ground, ahead of the air) and the aftermath (`after`) come
/// late by the burst's distance (`late`). Over it the layers of hell and heaven (CV_LAYERS) and heaven's win from
/// CV_WIN0, on the strike clock.
/// `dist`: blocks from the burst. Every file is this laser's own.
/// How much louder than its file each explosion plays (tools/sounds_convergence.py's BOOST): the surges as their
/// files, the impact 1.35 times, the eruption 1.2, the land's tear 1.6, the blast 2 (out of the game's mixer, near:
/// a surge on its own about -13 dBFS, the impact -10.5, the eruption -11.5, the blast -6.7, 4 dB over anything
/// before it, its limiter taking nothing on the blast). A voice's volume tops out at 1 and the game pans a centred voice to 0.6
/// a side, so any extra goes in as more voices of the same file.
const CV_BOOST: [(&str, f32); 5] = [("surge", 1.0), ("impact", 1.35), ("erupt", 1.2), ("sunder", 1.6), ("blast", 2.0)];
fn cv_boost(role: &str) -> f32 {
    let ev = role.split('_').next().unwrap_or(role);
    CV_BOOST.iter().find(|b| b.0 == ev).map_or(1.0, |b| b.1)
}
/// Event `role` at `t`, `v` times its file's level in tier `tier` (as many voices as it takes).
fn cv_play(p: &mut Plan, t: f32, role: &str, tier: &str, v: f32) {
    let mut left = v * cv_boost(role);
    while left > 0.004 {
        p.csound(t, &cv_file(role, tier), 10.0 * left.min(1.0), 1.0);
        left -= 1.0;
    }
}
fn cv_sounds(p: &mut Plan, dist: f64, late: f32, _me: [f64; 3], _seed: u32) {
    /// Where the hit lands in the impact's file (it starts at CV_CROUCH), the thud in the quake's; when the eruption's
    /// file starts (its cracks at CV_BREAK, its eruption at CV_RED0).
    const IMPACT_AT: f32 = 1.0;
    const QUAKE_HIT: f32 = 0.02;
    const ERUPT_FROM: f32 = 3.0;
    let f = cv_file;
    let (gc, gr) = (cv_gain_columns(dist), cv_gain(dist));
    for (tier, w) in cv_tiers(dist) {
        p.csound(0.0, &f("nether", tier), 10.0 * w * gc, 1.0);
        p.csound(0.5, &f("aether", tier), 10.0 * w * gc, 1.0);
        cv_play(p, ERUPT_FROM, "erupt", tier, w * gr);
        p.csound(CV_BREAK, &f("fire", tier), 10.0 * w * gr, 1.0);
        cv_play(p, CV_MEET - IMPACT_AT, "impact", tier, w * gr);
        p.csound(CV_MEET, &f("clash", tier), 10.0 * w * gc, 1.0);
        for (i, s) in CV_SURGES.iter().enumerate() {
            cv_play(p, *s + CV_SURGE_ATK[i] as f32 - CV_SURGE_HIT, &format!("surge_{}", i + 1), tier, w * gr);
        }
        p.csound(CV_DRAW, &f("drive", tier), 10.0 * w * gr, 1.0);
        cv_play(p, CV_HIT - CV_BLAST_HIT, "blast", tier, w * gr);
        cv_play(p, CV_HIT, "sunder", tier, w * gr);
        p.csound(CV_CLOSE - 0.5 + late, &f("after", tier), 10.0 * w * gr, 1.0);
        p.csound(CV_WIN0, &f("win", tier), 10.0 * w * gr, 1.0);
        for (role, at, columns) in CV_LAYERS {
            p.csound(at, &f(role, tier), 10.0 * w * if columns { gc } else { gr }, 1.0);
        }
    }
    // the quake: 0.15 of it close by (the blast's own hit lands on it there), all of it past 300 blocks
    let share = 0.15 + 0.85 * smooth01((dist - 50.0) / 250.0) as f32;
    p.csound(CV_HIT + (dist / (5.0 * 343.0)) as f32 - QUAKE_HIT, &cv_file("quake", ""), 10.0 * gr * share, 1.0);
}
/// When surge `s`'s ring reaches a player `dist` blocks off (its camera jolt).
fn cv_surge_dist(p: &Plan, me: [f64; 3], s: f32) -> f64 {
    let m = [f64::from(p.bx) + 0.5, f64::from(p.by) + 1.0 + cv_meet_y(f64::from(s)), f64::from(p.bz) + 0.5];
    ((me[0] - m[0]).powi(2) + (me[1] - m[1]).powi(2) + (me[2] - m[2]).powi(2)).sqrt()
}
fn cv_surge_felt(s: f32, dist: f64) -> f32 {
    s + (dist / CV_RING_V).min(4.0) as f32
}

/// The Convergence: the omen (cracks, a seam in the sky), both breaking in, the clash and its surges, the draw, the
/// blast, the aftermath (see the top of this file).
pub(super) fn convergence_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    cv_take_tune();
    let tu = tuned();
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let sd = shader_seed as u32;
    cv_face_seam(sd, me, cx, cz);
    let burst = [cx, gy + CV_BURST, cz];
    let (late, dist) = sound_from(burst, me);
    let fo = falloff(dist * 0.4).max(0.45);

    // the pass's table, on the tick after it fires
    p.later(0.05, move |q| q.ev.push((0.05, Act::Table(cv_table(shader_seed)))));

    // (the land's heights along the cracks, asked of the world as it starts)
    {
        let columns = Rc::new(cv_crack_columns(sd, bx, bz));
        let tag = crate::ground::new_tag();
        let cols = columns.clone();
        p.later(0.1, move |q| q.ev.push((0.1, Act::Survey { tag, columns: cols.to_vec() })));
        p.later(0.4, move |q| cv_crack_step(q, tag, columns, by + 1, 0.4));
    }

    cv_sounds(&mut p, dist, late, me, sd);
    // ---- the omen: the ground trembling at the target ---------------------------------------------------------------
    let mut ts = CV_OMEN + 0.3;
    while ts < CV_BREAK {
        p.shake(ts, (0.06 + 0.05 * (ts / CV_BREAK)) * fo, 0.5);
        ts += p.rng.uniform(0.35, 0.7) as f32;
    }
    // ---- both breaking in: a harder jolt, embers jetting up the fissures -------------------------------------------
    p.shake(CV_BREAK, 0.35 * fo, 1.2);
    let mut te = CV_BREAK;
    while te < CV_HIT {
        let n = if te < CV_MEET { 30 } else { 60 };
        p.at(te, format!("particle minecraft:lava {cx:.1} {:.1} {cz:.1} 18 1 18 0 {n} force", gy + 0.5));
        p.at(te + 0.1, format!("particle minecraft:flame {cx:.1} {:.1} {cz:.1} 6 4 6 0.08 {} force", gy + 3.0, n / 2));
        if te > CV_GOLD0 {
            // (gold motes drifting down out of the rift's light)
            p.at(te + 0.2, format!("particle minecraft:end_rod {cx:.1} {:.1} {cz:.1} 30 20 30 0.02 {} force", gy + 60.0, n / 3));
        }
        te += 0.5;
    }
    // ---- the impact in the air: its shell jolting the player as it reaches them ---------------------------------------
    {
        let dm = ((me[0] - cx).powi(2) + (me[1] - gy - CV_MEET_Y).powi(2) + (me[2] - cz).powi(2)).sqrt();
        let g = (1.8 / (1.0 + dm / 300.0)).clamp(0.2, 0.9) as f32 * tu.jolt;
        p.shake(CV_MEET + (dm / CV_IMPACT_V).min(4.0) as f32, g, 0.9);
    }
    // ---- the clash: each surge's ring jolting the player as it reaches them ------------------------------------------
    for (k, s) in CV_SURGES.iter().enumerate() {
        let t = cv_surge_felt(*s, cv_surge_dist(&p, me, *s));
        let g = (1.6 / (1.0 + dist / 250.0)).clamp(0.15, 0.7) as f32 * tu.jolt;
        p.shake(t, g * (0.8 + 0.2 * k as f32 / 5.0), 0.7);
    }
    // ---- the draw: the ground shaking harder and harder into the blast ---------------------------------------------
    let mut ts = CV_DRAW;
    while ts < CV_HIT {
        let u = (ts - CV_DRAW) / (CV_HIT - CV_DRAW);
        p.shake(ts, (0.15 + 0.35 * u) * fo, 0.4);
        ts += 0.25;
    }
    // ---- the blast: the jolt and the push as its front reaches the player ---------------------------------------------
    let arrive = CV_HIT + late;
    let jo = (2.0 / (1.0 + dist / 400.0)).clamp(0.3, 1.0) as f32 * tu.jolt;
    cv_jolt(&mut p, arrive, jo);
    // (the hit itself, on its impact frames and its sound, wherever the player stands; the front's jolt follows)
    p.shake(CV_HIT, 0.6 * jo, 0.5);
    p.ev.push((arrive, Act::Shove { from: [cx, gy, cz], out: CV_KNOCK_OUT * tu.knock, up: CV_KNOCK_UP * tu.knock, reach: CV_KNOCK_REACH }));
    for t in [CV_HIT + 0.1, CV_HIT + 1.0, CV_HIT + 3.0, CV_HIT + 6.0] {
        p.at(t, format!("execute positioned {cx:.1} {gy} {cz:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{CV_KILL}]"));
    }
    p.at(CV_HIT + 0.05, format!("particle minecraft:explosion_emitter {cx:.1} {:.1} {cz:.1} 12 4 12 0 12 force", gy + 2.0));
    // ---- the aftermath: ash and gold motes falling ------------------------------------------------------------------
    let mut ta = CV_HIT + 2.0;
    while ta < CV_END {
        p.at(ta, format!("particle minecraft:white_ash {cx:.1} {:.1} {cz:.1} 50 25 50 0 200 force", gy + 30.0));
        p.at(ta + 0.25, format!("particle minecraft:end_rod {cx:.1} {:.1} {cz:.1} 40 30 40 0.01 30 force", gy + 70.0));
        ta += 0.5;
    }

    if terrain {
        // ---- loose ground lifting toward the rift in the clash (real blocks, falling back) ---------------------------
        for k in 0..36 {
            let t = CV_MEET + 0.5 + 9.0 * k as f32 / 36.0;
            let a = p.rng.uniform(0.0, TAU);
            let r = p.rng.uniform(15.0, 70.0);
            let (x, z) = ((cx + a.cos() * r).floor() as i32, (cz + a.sin() * r).floor() as i32);
            let vy = p.rng.uniform(0.7, 1.1);
            let blk = if cv_side(cv_seam(sd), a.cos(), a.sin()).0 == 0 { "minecraft:netherrack" } else { "minecraft:calcite" };
            p.at(t, super::surf(x, z, &format!("summon minecraft:falling_block ~ ~0.2 ~ {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b,CancelDrop:1b,Motion:[0d,{vy:.2}d,0d]}}")));
        }
        let point = [cx, gy, cz];
        let load = pk_load_rows(point, 0.0, CV_READ as f64 + 4.0);
        for [x0, z0, x1, z1] in &load {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for [x0, z0, x1, z1] in &load {
            p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        // the land's work, one chain of stages from as it starts: the land before the blast, then the blast's changes
        // going in from the middle out with the wave
        let shape = Shape { cx, cz, ph: [TAU * mh(1, sd, 0xc1), TAU * mh(2, sd, 0xc1), TAU * mh(3, sd, 0xc1)], seed: sd, seam: cv_seam(sd) };
        p.later(0.1, move |q| {
            crate::meter::spend(9_000_000);
            let work = Rc::new(RefCell::new(Work::new(shape, by + 1)));
            q.later(0.15, move |q| cv_work(q, work, 0.15));
        });
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    /// The pass's own copy of the clock and the geometry (shaders/convergence.wgsl's `[cv shared]`) as here.
    #[test]
    fn cv_pass_keeps_the_shared_clock_and_geometry_in_step() {
        let src = include_str!("../../shaders/convergence.wgsl");
        // (the clock and the geometry only in the shared file: the sky and the ground sides read it, never their own copy)
        for side in [include_str!("../../shaders/convergence_sky.wgsl"), include_str!("../../shaders/convergence_ground.wgsl"), include_str!("../../shaders/convergence_cracks.wgsl")] {
            assert!(!side.contains("const CV_HIT") && !side.contains("fn cv_meet_y") && !side.contains("fn cv_surge("));
        }
        let val = |name: &str| -> f64 {
            let line = src.lines().find(|l| l.starts_with(&format!("const {name}: f32 = "))).unwrap_or_else(|| panic!("{name} in the pass"));
            line.split('=').nth(1).unwrap().trim().trim_end_matches(';').split(';').next().unwrap().trim().parse().unwrap()
        };
        for (name, v) in [
            ("CV_OMEN", f64::from(CV_OMEN)),
            ("CV_BREAK", f64::from(CV_BREAK)),
            ("CV_RED0", f64::from(CV_RED0)),
            ("CV_GOLD0", f64::from(CV_GOLD0)),
            ("CV_CROUCH", f64::from(CV_CROUCH)),
            ("CV_FIRE", f64::from(CV_FIRE)),
            ("CV_MEET", f64::from(CV_MEET)),
            ("CV_DRAW", f64::from(CV_DRAW)),
            ("CV_HIT", f64::from(CV_HIT)),
            ("CV_CLOSE", f64::from(CV_CLOSE)),
            ("CV_END", f64::from(CV_END)),
            ("CV_LEN", f64::from(crate::lasers::CONVERGENCE.length)),
            ("CV_RING_V", CV_RING_V),
            ("CV_MEET_Y", CV_MEET_Y),
            ("CV_RIFT_Y", CV_RIFT_Y),
            ("CV_RIFT_R", CV_RIFT_R),
            ("CV_BURST", CV_BURST),
            ("CV_RED_STUB", CV_RED_STUB),
            ("CV_RED_LOW", CV_RED_LOW),
            ("CV_GOLD_STUB", CV_GOLD_STUB),
            ("CV_GOLD_LOW", CV_GOLD_LOW),
            ("CV_IMPACT_V", CV_IMPACT_V),
            ("CV_MAGIC", f64::from(CV_MAGIC)),
        ] {
            assert!((val(name) - v).abs() < 1e-6, "{name}: the pass has {}, the plan {v}", val(name));
        }
        let surges: String = CV_SURGES.iter().map(|s| format!("{s:.1}")).collect::<Vec<_>>().join(", ");
        assert!(src.contains(&format!("array<f32, 6>({surges})")), "the surges: {surges}");
        for (name, a) in [("reaches", CV_SURGE_AMP.map(|a| format!("{a:.1}"))), ("attacks", CV_SURGE_ATK.map(|a| format!("{a:.2}")))] {
            assert!(src.contains(&format!("array<f32, 6>({})", a.join(", "))), "the surges' {name}");
        }
        // (the signs: up, down, in turn, as the pass's cv_surge_sign)
        assert!(CV_SURGE_SIGN.iter().enumerate().all(|(i, &s)| s == if i % 2 == 0 { 1.0 } else { -1.0 }));
    }

    #[test]
    fn cv_columns_meet_struggle_and_drop_into_the_burst() {
        // (the beats in order)
        assert!(CV_OMEN < CV_BREAK && CV_BREAK < CV_RED0 && CV_RED0 < CV_GOLD0 && CV_GOLD0 < CV_CROUCH && CV_CROUCH < CV_FIRE && CV_FIRE < CV_MEET && CV_MEET < CV_SURGES[0]);
        assert!(CV_SURGES.windows(2).all(|w| w[0] < w[1]) && CV_SURGES[5] < CV_DRAW && CV_DRAW < CV_HIT && CV_HIT < CV_CLOSE && CV_CLOSE < CV_END);
        assert!(CV_END < crate::lasers::CONVERGENCE.length);
        // (the red one climbing from the ground, the gold one coming down from the rift, meeting at CV_MEET)
        assert!(cv_red_top(f64::from(CV_RED0)).abs() < 1e-9 && (cv_gold_foot(f64::from(CV_GOLD0)) - CV_RIFT_Y).abs() < 1e-9);
        let m = f64::from(CV_MEET);
        assert!((cv_red_top(m - 1e-6) - CV_MEET_Y).abs() < 0.01 && (cv_gold_foot(m - 1e-6) - CV_MEET_Y).abs() < 0.01);
        // (driven up toward the rift by the Nether's surges, never back, smoothly; then drawn down into the burst)
        let (mut lo, mut hi) = (f64::MAX, f64::MIN);
        let mut last = cv_meet_y(m);
        let mut t = m;
        while t < f64::from(CV_HIT) + 1.0 {
            let y = cv_meet_y(t);
            assert!((y - last).abs() < 6.0, "{t}: {last} to {y}");
            if t < f64::from(CV_DRAW) {
                lo = lo.min(y);
                hi = hi.max(y);
            }
            last = y;
            t += 0.01;
        }
        assert!(hi > CV_MEET_Y + 35.0 && lo > CV_MEET_Y - 14.0 && hi < CV_RIFT_Y - 50.0, "{lo} {hi}");
        assert!((cv_meet_y(f64::from(CV_HIT)) - CV_BURST).abs() < 1e-6);
        // (the seam splits every bearing into two halves of the land)
        let seam = cv_seam(37);
        let (a, _) = cv_side(seam, (seam + 1.0).cos(), (seam + 1.0).sin());
        let (b, _) = cv_side(seam, (seam - 1.0).cos(), (seam - 1.0).sin());
        assert_eq!((a, b), (0, 1));
        let w = cv_table(37.0);
        assert_eq!(w.len(), CV_FR);
        assert_eq!(f32::from_bits(w[0]), CV_MAGIC);
        assert!((f64::from(f32::from_bits(w[1])) - seam).abs() < 1e-5);
        // (the cracks the pass draws fire along are the land's: on crack k's line at half its reach, cv_crack is 0)
        assert_eq!(f32::from_bits(w[CV_CRK + 14]), 7.0);
        for k in 0..7 {
            let (phi, reach) = (f64::from(f32::from_bits(w[CV_CRK + k])), f64::from(f32::from_bits(w[CV_CRK + 7 + k])));
            let r = reach * 0.5;
            let a = phi + 0.16 * (r * 0.09 + k as f64 * 1.7).sin() + 0.06 * (r * 0.31 + k as f64).sin();
            assert!(cv_crack(37, a.cos() * r, a.sin() * r) < 0.01, "crack {k}");
        }
    }

    #[test]
    fn cv_sounds_follow_the_cue_sheet() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let json = include_str!("../../../orbital-sounds/assets/orbital/sounds.json");
        for (me, tiers) in [([10.5, 66.0, 40.0], 1), ([10.5, 66.0, 400.0], 1), ([10.5, 66.0, 700.0], 2), ([10.5, 66.0, 1500.0], 2), ([10.5, 66.0, 2200.0], 1)] {
            let ev = plan(&crate::lasers::CONVERGENCE, &target, false, "minecraft:overworld", 37.0, me, 0);
            let sounds: Vec<(f32, String, f32, f32)> = ev.iter().filter_map(|(t, a)| if let Act::Sound { event, volume, pitch, .. } = a { Some((*t, event.clone(), *volume, *pitch)) } else { None }).collect();
            for (_, e, _, _) in &sounds {
                let key = e.strip_prefix("orbital:").unwrap();
                // (every event this laser's own: its entry names a file of this laser's, and the file is there)
                let at = json.find(&format!("\"{key}\"")).unwrap_or_else(|| panic!("{e} in sounds.json"));
                let name = json[at..].split("\"name\": \"").nth(1).and_then(|r| r.split('"').next()).unwrap();
                assert!(key.starts_with("convergence.") && name.starts_with("orbital:convergence/"), "{e}: {name}");
                let file = format!("../orbital-sounds/assets/orbital/sounds/{}.ogg", name.trim_start_matches("orbital:"));
                assert!(std::path::Path::new(&file).exists(), "{file}");
            }
            let at = |s: &str| sounds.iter().filter(|e| e.1.contains(s)).map(|e| e.0).collect::<Vec<_>>();
            // (how many files play for an event: one a tier, however many voices of it)
            let files = |s: &str| sounds.iter().filter(|e| e.1.contains(s)).map(|e| e.1.clone()).collect::<std::collections::BTreeSet<_>>().len();
            let k = |role: &str| format!(".{}_", cv_file(role, ""));
            for role in ["nether", "aether", "erupt", "fire", "impact", "clash", "drive", "blast", "sunder", "after", "win"] {
                assert_eq!(files(&k(role)), tiers, "{role} {me:?}");
            }
            for i in 1..=CV_SURGES.len() {
                assert_eq!(files(&k(&format!("surge_{i}"))), tiers, "surge {i} {me:?}");
            }
            // (the explosions at their files' level times CV_BOOST, as voices of at most 1: close by, a surge as its
            // file, the impact 1.35, the blast 2)
            if me[2] < 300.0 {
                let vol = |s: &str| sounds.iter().filter(|e| e.1.contains(s)).map(|e| e.2).sum::<f32>();
                let voices = |s: &str| sounds.iter().filter(|e| e.1.contains(s)).count();
                assert!(sounds.iter().all(|e| e.2 <= 1.0));
                assert!((vol(&k("surge_2")) - 1.0).abs() < 1e-3 && (vol(&k("impact")) - 1.35).abs() < 1e-3 && (vol(&k("blast")) - 2.0).abs() < 1e-3, "{me:?}");
                assert!((vol(&k("erupt")) - 1.2).abs() < 1e-3 && (vol(&k("sunder")) - 1.6).abs() < 1e-3 && (vol(&k("clash")) - 1.0).abs() < 1e-3, "{me:?}");
                assert!(voices(&k("surge_2")) == 1 && voices(&k("blast")) == 2, "{me:?}");
            }
            // (the beats as the picture shows them, at every distance: the cracks on CV_BREAK and the eruption on
            // CV_RED0 (the eruption's file from 3.0: 2.0 and 3.0 in), the impact's hit on CV_MEET, the columns pressed
            // together from the same moment, each surge's blow on the peak of its push, the drive ending on the blast's
            // blow on CV_HIT, the land tearing from it)
            assert!(at(&k("erupt")).iter().all(|&t| (t + 2.0 - CV_BREAK).abs() < 1e-4 && (t + 3.0 - CV_RED0).abs() < 1e-4));
            assert!(at(&k("fire")).iter().all(|&t| (t - CV_BREAK).abs() < 1e-4));
            assert!(at(&k("nether")).iter().all(|&t| t.abs() < 1e-4));
            assert!(at(&k("aether")).iter().all(|&t| (t - 0.5).abs() < 1e-4));
            assert!(at(&k("impact")).iter().all(|&t| (t + 1.0 - CV_MEET).abs() < 1e-4), "{me:?}");
            assert!(at(&k("clash")).iter().all(|&t| (t - CV_MEET).abs() < 1e-4));
            for (i, s) in CV_SURGES.iter().enumerate() {
                assert!(at(&k(&format!("surge_{}", i + 1))).iter().all(|&t| (t + CV_SURGE_HIT - s - CV_SURGE_ATK[i] as f32).abs() < 1e-4), "surge {i}");
            }
            assert!(at(&k("drive")).iter().all(|&t| (t + 3.0 - CV_HIT).abs() < 1e-4));
            assert!(at(&k("blast")).iter().all(|&t| (t + CV_BLAST_HIT - CV_HIT).abs() < 1e-4));
            assert!(at(&k("sunder")).iter().all(|&t| (t - CV_HIT).abs() < 1e-4));
            assert!(at(&k("win")).iter().all(|&t| (t - CV_WIN0).abs() < 1e-4));
            // (the layers of hell and heaven, each its own event, on the strike clock at every distance)
            for (role, t0, _) in CV_LAYERS {
                assert_eq!(at(&k(role)).len(), tiers, "{role} {me:?}");
                assert!(at(&k(role)).iter().all(|&t| (t - t0).abs() < 1e-4), "{role}");
            }
            // (the aftermath late by the burst's distance; the quake through the ground, ahead of the air)
            let late = (f64::from(me[0]) - 10.5).hypot(f64::from(me[2]) + 2.5).hypot(f64::from(me[1]) - 65.0 - CV_BURST) as f32 / 343.0;
            assert!(at(&k("after")).iter().all(|&t| (t - (CV_CLOSE - 0.5 + late)).abs() < 0.05));
            assert_eq!(at(".quake").len(), 1);
            assert!(at(".quake")[0] < CV_HIT + late);
            // (one file per event and tier, plain names)
            assert!(at(".t1_").is_empty() && at(".t2_").is_empty());
            // (the files carry their size and pitch: every cue at pitch 1)
            assert!(sounds.iter().all(|e| e.3 == 1.0));
            assert!(ev.iter().any(|(_, a)| matches!(a, Act::Cmd(c) if c.contains("kill @e[type=!minecraft:player"))));
            let shakes: Vec<f32> = ev.iter().filter_map(|(t, a)| matches!(a, Act::Shake { .. }).then_some(*t)).collect();
            for s in CV_SURGES {
                assert!(shakes.iter().any(|&t| t > s && t < s + 4.1), "a jolt for the surge at {s}");
            }
        }
    }

    /// A forest on rolling land (its ground about 64): oaks now and then, a pond south-west of the target.
    fn ground_h(x: i32, z: i32) -> i32 {
        (64.0 + 3.0 * (f64::from(x) * 0.05).sin() * (f64::from(z) * 0.04).cos()).round() as i32
    }
    fn tree(x: i32, z: i32) -> bool {
        mh((x.wrapping_mul(73) ^ z.wrapping_mul(179)) as u32, 5, 0x99) > 0.985
    }
    fn pond(x: i32, z: i32) -> bool {
        ((x + 40) * (x + 40) + (z - 30) * (z - 30)) < 49
    }
    thread_local! {
        /// The land the tests' world answers with: 0 the forest with its pond; 1 the forest over an aquifer (water
        /// in the ground 8 to 14 under it everywhere) with a river 200 off; 2 the forest by the sea (west of x -50,
        /// its surface at 62); 3 the forest with a river through the crater (12 wide at z 75, its surface at 62);
        /// 10 flat open land; 11 a hill in the crater with a pool of lava on its top, 12 a pool of lava on flat land
        /// the crater's edge cuts through, 13 one its rim's outer edge cuts through (`POOL` its middle).
        static LAND: std::cell::Cell<u8> = const { std::cell::Cell::new(0) };
        static POOL: std::cell::Cell<(i32, i32)> = const { std::cell::Cell::new((0, 0)) };
    }
    /// The water standing over column (x, z), if any: its bed and its surface.
    fn water_at(x: i32, z: i32) -> Option<(i32, i32)> {
        match LAND.with(|l| l.get()) {
            0 => pond(x, z).then(|| (ground_h(x, z) - 3, ground_h(x, z))),
            1 => ((z - 197).abs() < 6).then_some((55, 62)),
            2 => (x < -30).then_some((50, 62)),
            4 => Some((40, 62)),
            3 => ((z - 75).abs() < 6).then_some((55, 62)),
            _ => None,
        }
    }
    /// The worst cases for a stage's work (LAND 5 on): 5 deep ocean (water from 20 to 62, deeper than a read sees),
    /// 6 lakes and land in a pattern, 7 mountains (60 high, steep), 8 a dense jungle (every column a tall tree), 9
    /// the forest only half loaded (nothing east of x 150), 14 lakes of lava and land in a pattern.
    fn worst(land: u8, x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let (below, above) = (below as i32, above as i32);
        let make = |top: i32, f: &dyn Fn(i32) -> &'static str| Some((top, (top - below..top + above).map(f).collect()));
        match land {
            5 => make(62, &|y| if y < 20 { "minecraft:stone" } else if y <= 62 { "minecraft:water" } else { "minecraft:air" }),
            6 | 14 => {
                let wet = (f64::from(x) * 0.031).sin() * (f64::from(z) * 0.027).cos() > 0.3;
                if wet && land == 14 {
                    make(62, &|y| if y < 52 { "minecraft:stone" } else if y <= 62 { "minecraft:lava" } else { "minecraft:air" })
                } else if wet {
                    make(62, &|y| if y < 52 { "minecraft:sand" } else if y <= 62 { "minecraft:water" } else { "minecraft:air" })
                } else {
                    make(66, &|y| if y < 66 { "minecraft:dirt" } else if y == 66 { "minecraft:grass_block" } else { "minecraft:air" })
                }
            }
            7 => {
                let g = (100.0 + 60.0 * (f64::from(x) * 0.02).sin() * (f64::from(z) * 0.025).cos()).round() as i32;
                make(g, &move |y| if y < g { "minecraft:stone" } else if y == g { "minecraft:snow_block" } else { "minecraft:air" })
            }
            8 => {
                let g = 70;
                let h = 20 + ((x * 7 + z * 13).rem_euclid(14));
                make(g + h + 3, &move |y| {
                    if y < g {
                        "minecraft:dirt"
                    } else if y == g {
                        "minecraft:grass_block"
                    } else if y <= g + h && (x + z) % 2 == 0 {
                        "minecraft:jungle_log"
                    } else {
                        "minecraft:jungle_leaves"
                    }
                })
            }
            11..=13 => {
                let (px, pz) = POOL.with(std::cell::Cell::get);
                let d = f64::from(x - px).hypot(f64::from(z - pz));
                let (g, pool) = lava_pool_at(land, d);
                let lava = pool.map_or(0, |n| g - n);
                make(g, &move |y| {
                    if y > g {
                        "minecraft:air"
                    } else if y > lava && pool.is_some() {
                        "minecraft:lava"
                    } else if y < g - 3 || pool.is_some() {
                        "minecraft:stone"
                    } else if y < g {
                        "minecraft:dirt"
                    } else {
                        "minecraft:grass_block"
                    }
                })
            }
            _ => {
                if x > 150 {
                    return None;
                }
                LAND.with(|l| l.set(0));
                let c = column(x, z, below as u32, above as u32);
                LAND.with(|l| l.set(9));
                c
            }
        }
    }
    /// The land of LAND 11 to 13 at `d` from the pool's middle: its top, and how deep the lava over its ground is
    /// (None outside the pool). 11: a hill 23 over the land round it, flat-topped out to 9, the pool 6 across its top
    /// and 3 deep; 12, 13: flat land at 64, the pool 7 round and 4 deep.
    fn lava_pool_at(land: u8, d: f64) -> (i32, Option<i32>) {
        if land == 11 {
            let g = 64 + (30.0 * (1.0 - d.max(9.0) / 40.0)).max(0.0).round() as i32;
            (g, (d < 6.0).then_some(3))
        } else {
            (64, (d < 7.0).then_some(4))
        }
    }
    fn column(x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let land = LAND.with(|l| l.get());
        if land >= 5 {
            return worst(land, x, z, below, above);
        }
        let wet = water_at(x, z);
        let g = if land == 0 { ground_h(x, z) } else { wet.map_or(64, |w| w.0) };
        // (10: flat open land, its ground at 64, nothing on it)
        let t = wet.is_none() && tree(x, z) && land != 10;
        let block = |y: i32| -> &'static str {
            if let Some((bed, top)) = wet {
                return if y < bed { "minecraft:dirt" } else if y <= top { "minecraft:water" } else { "minecraft:air" };
            }
            if land == 1 && y < g - 8 && y >= g - 14 {
                return "minecraft:water";
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
            } else if y == g + 1 && (x + z) % 3 == 0 {
                "minecraft:short_grass"
            } else {
                "minecraft:air"
            }
        };
        let top = if let Some((_, w)) = wet { w } else if t { g + 9 } else { g + 2 };
        let (below, above) = (below as i32, above as i32);
        Some((top, (top - below..top + above).map(block).collect()))
    }

    fn played(terrain: bool) -> Vec<(f32, Blocks)> {
        played_all(terrain).0
    }
    fn played_all(terrain: bool) -> (Vec<(f32, Blocks)>, Vec<(f32, String)>) {
        crate::columns::clear();
        let mut cmds = Vec::new();
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let mut ev = plan(&crate::lasers::CONVERGENCE, &target, terrain, "minecraft:overworld", 37.0, [10.5, 66.0, 400.0], 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut out = Vec::new();
        let mut table = false;
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| column(x, z, below, above)),
                Act::Blocks(b) => out.push((t, *b)),
                Act::Cmd(c) => cmds.push((t, c)),
                Act::Table(w) => {
                    assert_eq!(w.len(), CV_FR);
                    table = true;
                }
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        assert!(table);
        (out, cmds)
    }


    fn fills_of(blocks: &[(f32, Blocks)]) -> Vec<(f32, String)> {
        blocks.iter().flat_map(|(t, b)| b.as_fills().into_iter().map(move |f| (*t, f))).collect()
    }
    fn xyz(f: &str) -> (f64, f64, f64, f64) {
        let w: Vec<f64> = f.split_whitespace().skip(1).take(6).map(|v| v.parse().unwrap_or(0.0)).collect();
        (w[0], w[1], w[2], w[4])
    }

    #[test]
    fn cv_land_breaks_open_takes_sides_and_is_split_by_the_crater() {
        LAND.with(|l| l.set(0));
        let blocks = played(true);
        let fills = fills_of(&blocks);
        let count = |m: &str, t0: f32, t1: f32| fills.iter().filter(|(t, f)| *t >= t0 && *t < t1 && f.contains(&format!("minecraft:{m} "))).count();
        // the omen: nothing placed before the break (the pass draws the fracture); the fissures opened with magma at
        // their foot, the veins, the basalt after it
        assert!(fills.iter().all(|(t, _)| *t >= CV_BREAK), "{:?}", fills.iter().find(|(t, _)| *t < CV_BREAK));
        assert!(count("magma_block", CV_BREAK, CV_BREAK + 5.0) > 40, "{}", count("magma_block", CV_BREAK, CV_BREAK + 5.0));
        assert!(count("netherrack", CV_BREAK, CV_MEET) > 100 && count("basalt", CV_BREAK, CV_MEET) > 30);
        // the land taking sides in the clash: both halves and the seam between
        assert!(count("calcite", CV_MEET, CV_DRAW) + count("pale_moss_block", CV_MEET, CV_DRAW) > 1000);
        assert!(count("netherrack", CV_MEET, CV_DRAW) + count("crimson_nylium", CV_MEET, CV_DRAW) > 1000);
        assert!(count("obsidian", CV_MEET, CV_DRAW) + count("crying_obsidian", CV_MEET, CV_DRAW) > 30);
        // nothing that flows or spreads placed (soul fire never spreads; magma only in the ground)
        for (_, f) in &fills {
            for bad in ["lava ", "water ", "sand "] {
                assert!(!f.contains(&format!(" minecraft:{bad}")) || f.contains(" replace "), "{f}");
            }
        }
        // the crater split: its floor's Nether blocks on one side of the seam, its pale ones on the other
        let seam = cv_seam(37);
        let mut sides = [[0u32; 2]; 2];
        for (t, f) in &fills {
            if *t < CV_HIT {
                continue;
            }
            let (x, y, z, _) = xyz(f);
            let (dx, dz) = (x + 0.5 - 10.5, z + 0.5 + 2.5);
            if dx.hypot(dz) > 50.0 || y > f64::from(ground_h(x as i32, z as i32)) - 4.0 {
                continue;
            }
            let (s, d) = cv_side(seam, dx, dz);
            if d < 3.0 {
                continue;
            }
            let k = if f.ends_with("netherrack strict") || f.ends_with("blackstone strict") { 0 } else if f.ends_with("calcite strict") || f.ends_with("diorite strict") { 1 } else { continue };
            sides[s as usize][k] += 1;
        }
        assert!(sides[0][0] > 300 && sides[1][1] > 300 && sides[0][1] == 0 && sides[1][0] == 0, "{sides:?}");
        // the islands left hanging in the sky over it: grown after the blast (never all at once), whole about as the
        // rift shuts, high over the land
        let isl: Vec<&(f32, String)> = fills.iter().filter(|(t, f)| *t > CV_HIT && *t < CV_END + 4.0 && f.ends_with("minecraft:oak_log strict")).collect();
        assert!(isl.len() >= 7 * 4, "{}", isl.len());
        let grow: Vec<f32> = fills.iter().filter(|(_, f)| { let (_, y, _, _) = xyz(f); y > 64.0 + 40.0 }).map(|(t, _)| *t).collect();
        let (t0, t1) = (grow.iter().copied().fold(f32::MAX, f32::min), grow.iter().copied().fold(0.0, f32::max));
        assert!(t0 >= CV_HIT && t1 > t0 + 8.0 && t1 < CV_END + 4.0, "{t0} {t1}");
        let mut per: std::collections::BTreeMap<i32, usize> = Default::default();
        for t in &grow {
            *per.entry((t / 0.05).round() as i32).or_default() += 1;
        }
        assert!(per.len() > 40, "the islands put in on {} ticks only", per.len());
        // fire only on the Nether half's crater floor
        for (t, f) in &fills {
            if f.ends_with(" minecraft:fire strict") {
                let (x, _, z, _) = xyz(f);
                assert!(*t >= CV_HIT && (x + 0.5 - 10.5).hypot(z + 0.5 + 2.5) < CV_CRATER_R, "{f}");
            }
        }
        // the crater dug about cdp() deep in its middle
        let mid = fills.iter().find(|(t, f)| *t >= CV_HIT && f.starts_with("fill 10 ") && f.contains(" -3 10 ") && f.ends_with("minecraft:air strict")).expect("the middle dug");
        let y0 = xyz(&mid.1).1 as i32;
        assert!((ground_h(10, -3) - y0 + 1 - cdp() as i32).abs() <= 1, "{}", mid.1);
        // trees felled out over the flattened land
        assert!(fills.iter().filter(|(_, f)| f.contains("_log[axis=")).count() > 20);
    }

    #[test]
    fn cv_basalt_is_cleared_by_the_blast() {
        // (every basalt column put up before the blast within the crater cleared by it)
        LAND.with(|l| l.set(10));
        let mut blocks = played(true);
        blocks.sort_by(|a, b| a.0.total_cmp(&b.0));
        let mut top: std::collections::HashMap<(i32, i32), (i32, f32)> = Default::default();
        for (t, b) in &blocks {
            for f in b.as_fills() {
                let (x, y, z, y1) = xyz(&f);
                if f.ends_with("minecraft:basalt strict") && *t < CV_HIT {
                    top.insert((x as i32, z as i32), (y1 as i32, *t));
                }
                let _ = y;
            }
        }
        assert!(!top.is_empty());
        let s = Shape { cx: 10.5, cz: -2.5, ph: [TAU * mh(1, 37, 0xc1), TAU * mh(2, 37, 0xc1), TAU * mh(3, 37, 0xc1)], seed: 37, seam: cv_seam(37) };
        for (&(x, z), &(y1, _)) in &top {
            if s.at(x, z).2 >= 0.95 {
                continue;
            }
            let cleared = blocks.iter().filter(|(t, _)| *t >= CV_HIT).flat_map(|(_, b)| b.as_fills()).any(|f| {
                let (fx, fy, fz, fy1) = xyz(&f);
                fx as i32 == x && fz as i32 == z && f.ends_with("minecraft:air strict") && fy <= 65.0 && fy1 as i32 >= y1
            });
            assert!(cleared, "basalt at {x} {z} up to {y1} left standing");
        }
        LAND.with(|l| l.set(0));
    }

    /// The land round the pool after the strike's edits, tick by tick: (x, y, z) to block, from `column`, each edit
    /// applied as the world would (a `replace` only over its filter). `f` sees each tick's state once its edits are in.
    fn lava_world(blocks: &[(f32, Blocks)], (px, pz): (i32, i32), n: i32, mut f: impl FnMut(f32, &std::collections::HashMap<(i32, i32, i32), String>)) {
        let mut w: std::collections::HashMap<(i32, i32, i32), String> = Default::default();
        for x in px - n..=px + n {
            for z in pz - n..=pz + n {
                let (top, col) = column(x, z, 100, 40).expect("loaded");
                for (k, b) in col.iter().enumerate() {
                    w.insert((x, top - 100 + k as i32, z), (*b).to_string());
                }
            }
        }
        let mut fills: Vec<(f32, String)> = fills_of(blocks);
        fills.sort_by(|a, b| a.0.total_cmp(&b.0));
        let mut i = 0;
        while i < fills.len() {
            let t = fills[i].0;
            while i < fills.len() && fills[i].0 == t {
                let tk: Vec<&str> = fills[i].1.split_whitespace().collect();
                i += 1;
                if tk[0] != "fill" {
                    continue;
                }
                let v: Vec<i32> = tk[1..7].iter().map(|s| s.parse().unwrap()).collect();
                let only = (tk.get(8) == Some(&"replace")).then(|| tk[9]);
                if (v[0] - px).abs() > n || (v[2] - pz).abs() > n {
                    continue;
                }
                for y in v[1]..=v[4] {
                    if let Some(b) = w.get_mut(&(v[0], y, v[2]))
                        && only.is_none_or(|o| b == o)
                    {
                        *b = tk[7].to_string();
                    }
                }
            }
            f(t, &w);
        }
    }
    /// The lava blocks of the land round the pool open to the air beside or under them (that would pour out).
    fn lava_open(w: &std::collections::HashMap<(i32, i32, i32), String>, (px, pz): (i32, i32), n: i32) -> Vec<(i32, i32, i32)> {
        let air = |p: (i32, i32, i32)| w.get(&p).is_some_and(|b| b.ends_with("air") || b.ends_with("fire"));
        w.iter()
            .filter(|&(&(x, _, z), b)| b == "minecraft:lava" && (x - px).abs() < n && (z - pz).abs() < n)
            .filter(|&(&(x, y, z), _)| [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, -1, 0)].iter().any(|(a, b, c)| air((x + a, y + b, z + c))))
            .map(|(&p, _)| p)
            .collect()
    }
    /// LAND 11 to 13 played with the pool `at` (dx, dz) off the target, checked over the land `n` round it: no lava left
    /// open to the air for more than half a second (the game's lava waits 1.5 s before it flows), none at the end.
    /// The world as it ends, and its shape.
    fn lava_played(land: u8, at: (i32, i32), n: i32) -> (std::collections::HashMap<(i32, i32, i32), String>, Shape) {
        let pool = (10 + at.0, -3 + at.1);
        LAND.with(|l| l.set(land));
        POOL.with(|p| p.set(pool));
        let blocks = played(true);
        let mut open: std::collections::HashMap<(i32, i32, i32), f32> = Default::default();
        let mut end = Default::default();
        lava_world(&blocks, pool, n, |t, w| {
            let now = lava_open(w, pool, n);
            open.retain(|p, _| now.contains(p));
            for p in now {
                let t0 = *open.entry(p).or_insert(t);
                assert!(t - t0 < 0.5, "land {land}: lava at {p:?} open to the air from {t0:.2} s to {t:.2} s");
            }
            end = w.clone();
        });
        assert!(open.is_empty(), "land {land}: lava left open to the air at {:?}", open.keys().collect::<Vec<_>>());
        LAND.with(|l| l.set(0));
        (end, Shape { cx: 10.5, cz: -2.5, ph: [TAU * mh(1, 37, 0xc1), TAU * mh(2, 37, 0xc1), TAU * mh(3, 37, 0xc1)], seed: 37, seam: cv_seam(37) })
    }
    fn lava_top(w: &std::collections::HashMap<(i32, i32, i32), String>, x: i32, z: i32) -> i32 {
        w.iter().filter(|&(&(a, _, c), b)| a == x && c == z && !b.ends_with("air") && !b.ends_with("fire")).map(|(&(_, y, _), _)| y).max().unwrap_or(i32::MIN)
    }
    /// The edge of the crater (`k` 1) or of its rim (`k` CV_RIM) along the +x axis from the target, dx.
    fn lava_edge(k: f64) -> i32 {
        let s = Shape { cx: 10.5, cz: -2.5, ph: [TAU * mh(1, 37, 0xc1), TAU * mh(2, 37, 0xc1), TAU * mh(3, 37, 0xc1)], seed: 37, seam: cv_seam(37) };
        (0..300).find(|&d| s.at(10 + d, -3).2 >= k).expect("an edge")
    }

    #[test]
    fn cv_lava_on_a_hill_in_the_crater_is_dug_out() {
        // (a hill in the crater with a pool of lava on its top: dug to the crater's floor like the hill round it, no
        // pillar left standing, no lava left)
        let (w, s) = lava_played(11, (28, 12), 12);
        let (px, pz) = (38, 9);
        assert!(!w.values().any(|b| b == "minecraft:lava"), "lava left in the crater");
        let pool: Vec<(i32, i32)> = (px - 6..=px + 6).flat_map(|x| (pz - 6..=pz + 6).map(move |z| (x, z))).filter(|&(x, z)| f64::from(x - px).hypot(f64::from(z - pz)) < 6.0).collect();
        let ring: Vec<(i32, i32)> = (px - 9..=px + 9).flat_map(|x| (pz - 9..=pz + 9).map(move |z| (x, z))).filter(|&(x, z)| (7.0..9.0).contains(&f64::from(x - px).hypot(f64::from(z - pz)))).collect();
        let ring_top = ring.iter().map(|&(x, z)| lava_top(&w, x, z)).max().unwrap();
        for &(x, z) in &pool {
            let t = lava_top(&w, x, z);
            let floor = 87 - 3 - bowl(s.at(x, z).2).round() as i32;
            assert!(t <= ring_top + 1 && t <= floor + 1, "the pool's column {x} {z} stands to {t}: the hill round it to {ring_top}, its floor {floor}");
        }
    }

    #[test]
    fn cv_lava_cut_by_the_crater_is_cooled_at_the_cut() {
        // (a pool the crater's edge cuts through: the part in the crater dug out, the rest cooled (basalt, a crust of
        // magma, the rim's heap over it) and none of it pouring into the pit)
        let e = lava_edge(1.0);
        let (w, s) = lava_played(12, (e, 0), 11);
        let (px, pz) = (10 + e, -3);
        let mut dug = 0;
        let mut cooled = 0;
        for x in px - 6..=px + 6 {
            for z in pz - 6..=pz + 6 {
                if f64::from(x - px).hypot(f64::from(z - pz)) >= 7.0 {
                    continue;
                }
                let lava = (61..=64).filter(|&y| w.get(&(x, y, z)).is_some_and(|b| b == "minecraft:lava")).count();
                assert_eq!(lava, 0, "lava left at {x} {z}");
                if s.at(x, z).2 < 1.0 && lava_top(&w, x, z) < 60 {
                    dug += 1;
                }
                // (past the edge: cooled, then the rim's heap over it)
                if s.at(x, z).2 >= 1.0 && (61..=64).all(|y| w.get(&(x, y, z)).is_some_and(|b| !b.ends_with("air"))) {
                    cooled += 1;
                }
            }
        }
        assert!(dug > 10 && cooled > 10, "{dug} columns dug, {cooled} cooled");
    }

    #[test]
    fn cv_lava_past_the_rim_is_held_back() {
        // (a pool the rim's outer edge cuts through: what lies in the rim cooled, the rest left lava, and none of it open)
        let e = lava_edge(CV_RIM);
        let (w, _) = lava_played(13, (e, 0), 11);
        assert!(w.values().any(|b| b == "minecraft:lava"), "the pool past the rim kept");
        assert!(w.values().any(|b| b == "minecraft:magma_block"), "the rim's lava cooled");
    }

    #[test]
    fn cv_leaves_the_land_alone_with_the_terrain_off() {
        let (blocks, cmds) = played_all(false);
        assert!(blocks.is_empty());
        assert!(!cmds.iter().any(|(_, c)| c.contains("falling_block {") || c.contains("forceload")));
    }

    /// `cargo test --release cv_no_stage_too_heavy_anywhere -- --ignored --nocapture`, on its own.
    #[test]
    #[ignore]
    fn cv_no_stage_too_heavy_anywhere() {
        cv_anywhere(true);
    }
    /// Wherever it strikes, the land's edits go in on time (but in a jungle of tall trees) and the blast's from the
    /// middle out.
    #[test]
    fn cv_land_goes_in_in_order_anywhere() {
        cv_anywhere(false);
    }
    fn cv_anywhere(timed: bool) {
        if timed && cfg!(debug_assertions) {
            return;
        }
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        for land in [0u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 14] {
            LAND.with(|l| l.set(land));
            let ev = plan(&crate::lasers::CONVERGENCE, &target, true, "minecraft:overworld", 37.0, [10.5, 66.0, 500.0], 0);
            let p = crate::strike::sim::play(ev, 50.0, &column);
            // (the edits before the blast may run a little late at the very start, as the land read comes in)
            let late = p.edits.iter().filter(|e| e.1 > 2.5).map(|e| e.0 - e.1).fold(0.0f32, f32::max);
            let worst = p.stages.iter().map(|s| s.2).fold(0.0, f64::max);
            let mut st = p.stages.clone();
            st.sort_by(|a, b| b.2.total_cmp(&a.2));
            eprintln!("LAND {land} heaviest: {:?}", &st[..4.min(st.len())]);
            eprintln!("LAND {land}: {} stages, edits {late:.2} s late at most, heaviest {worst:.2} ms", p.stages.len());
            assert!(!timed || worst < 1.3, "land {land}: a stage took {worst:.2} ms");
            // (land 9, half of it never loaded: the read's retries share the stages with the land before the blast, whose
            // last cracks go in up to a second late)
            assert!(late < if land == 8 { 5.0 } else if land == 9 { 1.5 } else { 0.3 }, "land {land}: an edit {late:.2} s late");
            // (the blast's edits sweep out from the middle: each tick's middle further out than the last's, but for
            // what lands a moment behind the wave)
            let mut last = 0.0f64;
            let end = Wave::new().at(f64::from(CV_READ));
            let mut by: std::collections::BTreeMap<i32, Vec<f64>> = Default::default();
            for (t, due, b) in &p.edits {
                if *due < CV_HIT + Wave::new().dug() - CV_HIT + 0.05 {
                    continue;
                }
                // (the land's, not the islands' in the sky nor the basalt rising after the blast)
                for u in b.runs.iter().filter(|u| u.y < 64 + 30 && *t < CV_CLOSE) {
                    by.entry((t / 0.05).round() as i32).or_default().push((f64::from(u.x) - 10.0).hypot(f64::from(u.z) + 3.0));
                }
            }
            for (k, mut r) in by {
                r.sort_by(f64::total_cmp);
                let m = r[r.len() / 2];
                if (k as f32) * 0.05 < end {
                    assert!(m >= last - 80.0, "land {land}: tick {k}: the lining at {m:.0} after {last:.0}");
                }
                last = last.max(m);
            }
        }
        LAND.with(|l| l.set(0));
    }

    #[test]
    fn cv_throws_real_blocks_out_of_the_crater() {
        let (_, cmds) = played_all(true);
        let thrown: Vec<&(f32, String)> = cmds.iter().filter(|(t, c)| *t >= CV_HIT && c.starts_with("summon minecraft:falling_block")).collect();
        assert!(thrown.len() >= 60 && thrown.len() <= CV_THROWN, "{} thrown", thrown.len());
        for (t, c) in &thrown {
            assert!(*t > CV_HIT && *t < CV_HIT + 1.6 && c.contains("DropItem:0b"), "{t} {c}");
        }
        // (and ground lifted toward the rift in the clash)
        assert!(cmds.iter().filter(|(t, c)| *t > CV_MEET && *t < CV_DRAW && c.contains("falling_block")).count() > 20);
    }
}

#[cfg(test)]
mod table {
    /// `CB_SEED=37 CB_OUT=path cargo test --release cv_write_table -- --ignored`: the table the pass reads, for
    /// tools/preview.py (a line `index value` a word).
    #[test]
    #[ignore]
    fn cv_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let text: String = super::cv_table(seed).iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}

#[cfg(test)]
mod wave_t {
    /// `cargo test --release cv_wave_times -- --ignored --nocapture`: when the blast's waves reach each radius.
    #[test]
    #[ignore]
    fn cv_wave_times() {
        let w = super::Wave::new();
        println!("the pit dug by {:.2} s after the burst", w.dug() - super::CV_HIT);
        for r in [0.0, 20.0, 40.0, 64.0, 80.0, 100.0, 140.0, 190.0, 256.0] {
            println!("r {r:4}: lined {:.2} s after the burst", w.at(r) - super::CV_HIT);
        }
    }
}
