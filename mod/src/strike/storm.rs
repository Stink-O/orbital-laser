//! The Supercell's plan: a storm called down on the target. The sky darkens and a huge, low, slowly turning wall cloud
//! and an anvil-topped storm cloud boil up over it and spread; the wind gusts, thunder rumbles far off. Then the storm:
//! lightning all over the land under the cloud out to SC_REACH, faster and faster, each bolt a real vanilla
//! `lightning_bolt` (its fire, its flash, what it strikes), heavy rain falling out of the cloud, and a few thin funnels
//! (vortex.rs) coming down out of the wall cloud and wandering over the land. Then one colossal strike on the target
//! itself, a shockwave and a jolt, and the storm dies away.
//!
//! What it leaves is light: a small scorched pit where each bolt struck (blackstone, basalt, tinted glass, a seam of
//! magma, glassy sand), charred grass round it, the funnels' scoured tracks, the finale's crater about 20 across, and the
//! fires the bolts lit, kept in check by the rain (the world's weather is rain while it lasts: rain puts out fires
//! under the open sky) and swept out within SC_SWEEP of the middle as it ends.
//!
//! Vanilla's own thunder is stopped as each bolt plays it (`stopsound` on the ticks after): it is a full-scale boom with
//! no crack, which would bury ours or clip with it; ours (tools/sounds_storm.py) is the crack and the roll, delayed by
//! distance. Its impact crackle stays.
//!
//! shaders/supercell.wgsl draws the cloud, the rain, the bolts, the funnels and the flashes from the table `sc_table`
//! hands it (render.set-data). Keep the SC_* here and there in step.
use super::vortex::{self, Funnel, VX_W};
use super::{Act, Blocks, Plan, Rng, TIDY_LOOSE, Target, falloff, mh, pk_load_rows, sound_from, vnoise};
use crate::lasers::Laser;
use std::f64::consts::PI;
use std::rc::Rc;

/// The storm's timeline: the cloud formed by SC_FORMED, the bolts from SC_STORM0 to SC_STORM1, the colossal strike at
/// SC_FINALE, the rain stopping and the cloud dying away from SC_CLEAR (gone by the strike's end, lasers.rs's length).
pub(super) const SC_FORMED: f32 = 9.0;
pub(super) const SC_STORM0: f32 = 9.5;
pub(super) const SC_STORM1: f32 = 42.0;
pub(super) const SC_FINALE: f32 = 45.0;
pub(super) const SC_CLEAR: f32 = 50.0;
/// The bolts over the storm, and how far out from the middle they strike.
pub(super) const SC_NB: usize = 72;
pub(super) const SC_REACH: f64 = 120.0;
/// The flickers in the cloud (no bolt to the ground).
pub(super) const SC_NK: usize = 56;
/// The table (`mod_data`): a header (bolts, finale time, funnels, flickers), the bolts from SC_B (SC_BW words each: t,
/// x, z off the middle, the ground there over the middle's), the funnels from SC_F (VX_W words each), the flickers
/// from SC_K (t, x, z).
pub(super) const SC_B: usize = 16;
pub(super) const SC_BW: usize = 4;
pub(super) const SC_F: usize = SC_B + SC_BW * 96;
pub(super) const SC_NF: usize = 3;
pub(super) const SC_K: usize = 1024;
/// How far out the fires are swept as it ends, and the bands a sweep is split into (a stage each).
const SC_SWEEP: f64 = 150.0;
const SC_SWEEP_BANDS: usize = 12;

/// A bolt: when, and where off the middle.
#[derive(Clone, Copy, Debug)]
pub(super) struct Bolt {
    pub t: f32,
    pub x: f64,
    pub z: f64,
}

/// The bolts of strike `seed` (the player at `me`, off the middle): coming faster and faster over the storm, anywhere
/// under the cloud out to SC_REACH (a little more of them further in), never within 10 blocks of the player.
pub(super) fn sc_bolts(seed: u32, me: [f64; 2]) -> Vec<Bolt> {
    (0..SC_NB)
        .map(|i| {
            let u = (i as f64 + 0.5 * mh(i as u32, seed, 0xb0)) / SC_NB as f64;
            let t = f64::from(SC_STORM0) + f64::from(SC_STORM1 - SC_STORM0) * u.powf(0.62);
            let a = 2.0 * PI * mh(i as u32, seed, 0xb1);
            let r = 14.0 + (SC_REACH - 14.0) * mh(i as u32, seed, 0xb2).powf(0.75);
            let (mut x, mut z) = (a.cos() * r, a.sin() * r);
            let d = (x - me[0]).hypot(z - me[1]);
            if d < 10.0 {
                let k = 10.0 / d.max(0.1);
                x = me[0] + (x - me[0]) * k;
                z = me[1] + (z - me[1]) * k;
            }
            Bolt { t: t as f32, x, z }
        })
        .collect()
}

/// The flickers in the cloud: throughout the storm, a few in the build-up, high in the cloud anywhere over the land.
pub(super) fn sc_flickers(seed: u32) -> Vec<[f32; 3]> {
    (0..SC_NK)
        .map(|i| {
            let u = (i as f64 + mh(i as u32, seed, 0xc0)) / SC_NK as f64;
            let t = 5.0 + f64::from(SC_FINALE - 5.5) * u.powf(0.8);
            let a = 2.0 * PI * mh(i as u32, seed, 0xc1);
            let r = 200.0 * mh(i as u32, seed, 0xc2).sqrt();
            [t as f32, (a.cos() * r) as f32, (a.sin() * r) as f32]
        })
        .collect()
}

/// The funnels: SC_NF thin landspouts let down out of the wall cloud through the storm, overlapping, each wandering
/// for 12 to 16 seconds.
pub(super) fn sc_funnels(seed: u32) -> Vec<Funnel> {
    let starts = [13.0, 21.0, 29.5];
    (0..SC_NF as u32)
        .map(|k| {
            let r = |j: u32| mh(k * 7 + j, seed, 0xf0);
            let t0 = starts[k as usize] + 1.5 * r(0);
            let len = 13.0 + 3.0 * r(1);
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
    let mut w = vec![0u32; SC_K + 3 * SC_NK];
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
        let words = vortex::vx_words(fu, |p| dy(p[0], p[1]).unwrap_or(0.0));
        w[SC_F + VX_W * k..SC_F + VX_W * (k + 1)].copy_from_slice(&words);
    }
    for (i, k) in flick.iter().enumerate() {
        w[SC_K + 3 * i] = k[0].to_bits();
        w[SC_K + 3 * i + 1] = k[1].to_bits();
        w[SC_K + 3 * i + 2] = k[2].to_bits();
    }
    w
}

/// The columns whose ground the pass needs: under each bolt and along each funnel's track (and the middle).
fn sc_columns(seed: u32, me: [f64; 2], bx: i32, bz: i32) -> Vec<(i32, i32)> {
    let c = |x: f64, z: f64| ((f64::from(bx) + 0.5 + x).floor() as i32, (f64::from(bz) + 0.5 + z).floor() as i32);
    let mut out = vec![(bx, bz)];
    out.extend(sc_bolts(seed, me).iter().map(|b| c(b.x, b.z)));
    for f in sc_funnels(seed) {
        out.extend(f.path.iter().map(|p| c(p[0], p[1])));
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

/// The finale's crater at the middle (bx, bz), going in from the middle out over `a0` .. as its shockwave goes: a bowl
/// about 20 across and 5 deep, lined like a pit, its rim ragged, the land round it charred out to 22, its plants burnt
/// off and the leaves stripped off the trees out to 14.
fn crater(q: &mut Plan, t: f32, seed: u32) {
    let (bx, bz) = (q.bx, q.bz);
    let mut b = Blocks::default();
    let (r, depth, r_char, r_leaf) = (10.0f64, 5.0f64, 22.0f64, 14.0f64);
    let ri = r_char.ceil() as i32 + 2;
    for dz in -ri..=ri {
        for dx in -ri..=ri {
            let (x, z) = (bx + dx, bz + dz);
            let d = f64::from(dx).hypot(f64::from(dz));
            let wob = 0.85 + 0.3 * vnoise(f64::from(x), f64::from(z), 3.0, seed ^ 0x77);
            let u = d / (r * wob);
            if u < 1.0 {
                let dig = ((depth * (1.0 - u * u)).round() as i32).max(1);
                b.put(x, z, -dig, 30, "minecraft:air", None, true);
                let floor = if d < 1.5 { "minecraft:magma_block" } else { q.rng.weighted(&LINING) };
                b.put(x, z, -dig - 1, -dig - 1, floor, None, true);
                if u < 0.8 && q.rng.next() < 0.5 {
                    b.put(x, z, -dig - 2, -dig - 2, q.rng.weighted(&LINING), None, true);
                }
            } else if d < r_char * wob {
                b.put(x, z, -1, -1, "minecraft:glass", Some("#minecraft:sand"), true);
                if q.rng.next() < 0.85 - 0.5 * (d / r_char) {
                    b.put(x, z, -1, -1, q.rng.weighted(&CHAR), Some("minecraft:grass_block"), true);
                }
                b.put(x, z, 0, 2, "minecraft:air", Some(TIDY_LOOSE), true);
                if d < r_leaf {
                    b.put(x, z, 0, 24, "minecraft:air", Some("#minecraft:leaves"), true);
                }
            }
        }
    }
    for (tk, e) in b.split_by(|x, z| t + (f64::from(x - bx).hypot(f64::from(z - bz)) / 150.0) as f32) {
        q.ev.push((tk, Act::Blocks(Box::new(e))));
    }
}

/// The fires swept out of band `k` of SC_SWEEP_BANDS (equal areas out to SC_SWEEP) at `t`: every fire from two under each
/// column's top to 42 over it (its trees' crowns) put out. Only fire changes.
fn sweep(q: &mut Plan, k: usize, t: f32) {
    let (bx, bz) = (q.bx, q.bz);
    let r0 = SC_SWEEP * (k as f64 / SC_SWEEP_BANDS as f64).sqrt();
    let r1 = SC_SWEEP * ((k + 1) as f64 / SC_SWEEP_BANDS as f64).sqrt();
    let mut b = Blocks::default();
    let ri = r1.ceil() as i32;
    for dz in -ri..=ri {
        let z = f64::from(dz);
        // (the row's columns between the band's two circles: one span either side, or one across where it misses r0)
        let outer = (r1 * r1 - z * z).max(0.0).sqrt();
        let inner = (r0 * r0 - z * z).max(0.0).sqrt();
        let xo = outer.floor() as i32;
        let xi = if r0 * r0 > z * z { inner.ceil() as i32 } else { -1 };
        let mut span = |a: i32, c: i32| {
            for dx in a..=c {
                b.put(bx + dx, bz + dz, -2, 42, "minecraft:air", Some("#minecraft:fire"), true);
            }
        };
        if xi < 0 {
            span(-xo, xo);
        } else if xi <= xo {
            span(-xo, -xi);
            span(xi, xo);
        }
    }
    q.ev.push((t, Act::Blocks(Box::new(b))));
}

pub(super) fn supercell_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let s = shader_seed as u32;
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let mer = [me[0] - cx, me[2] - cz];
    let bar = |text: &str, color: &str| format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#);
    let len = laser.length;

    // ---- the pass's table, and the ground under the bolts and the funnels asked of the world, put in when answered
    // (and again a little later, for land that loads as it goes) -------------------------------------------------------
    p.later(0.05, move |q| q.ev.push((0.05, Act::Table(sc_table(s, mer, &|_, _| None)))));
    for (ask, put) in [(0.1f32, 1.0f32), (6.0, 7.5), (16.0, 17.5)] {
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
    p.at(0.5, bar("ORBITAL WEATHER CONTROL: STORM FORMING", "dark_aqua"));
    p.csound(0.0, "buildup", 10.0, 1.0);
    p.at(5.0, "weather rain");
    for (i, t) in [10.0f32, 23.0, 36.0].iter().enumerate() {
        p.csound(*t, "gusts", [8.0, 9.0, 8.5][i], 1.0);
    }
    for (i, t) in [6.0f32, 16.0, 26.0, 36.0, 44.0].iter().enumerate() {
        p.csound(*t, "rain", [5.0, 8.0, 9.0, 9.0, 7.0][i], 1.0);
    }
    p.at(SC_STORM0, bar("SUPERCELL", "dark_aqua"));

    // ---- the flickers in the cloud: thunder far off for about half of them --------------------------------------------
    for (i, k) in sc_flickers(s).iter().enumerate() {
        if i % 2 == 0 {
            let (late, d) = sound_from([cx + f64::from(k[1]), gy + 100.0, cz + f64::from(k[2])], me);
            let v = (1.4 / (1.0 + d / 200.0)).clamp(0.3, 0.9) as f32;
            p.csound(k[0] + late, "rumble", 10.0 * v, 0.9 + 0.2 * mh(i as u32, s, 0xd0) as f32);
        }
    }

    // ---- the bolts ------------------------------------------------------------------------------------------------------
    let bolts = sc_bolts(s, mer);
    // (the cracks heard while others still roll are let down, so a fast run of near bolts never piles up past full scale)
    let mut load: Vec<(f32, f32)> = Vec::new();
    for (i, b) in bolts.iter().enumerate() {
        let (x, z) = ((cx + b.x).floor() as i32, (cz + b.z).floor() as i32);
        p.at(b.t, format!("execute positioned {x} 0 {z} positioned over motion_blocking run summon minecraft:lightning_bolt ~0.5 ~ ~0.5"));
        // (vanilla's thunder stopped on the ticks after the bolt plays it: the summon runs on the tick after it is due,
        // the bolt plays its thunder later that tick, after the mod's commands; a few ticks' worth, in case it is late)
        for k in 1..6 {
            p.at(b.t + 0.05 * k as f32 + 0.04, "stopsound @a * minecraft:entity.lightning_bolt.thunder");
        }
        let (late, d) = sound_from([cx + b.x, gy, cz + b.z], me);
        let v0 = (1.5 / (1.0 + d / 110.0)).clamp(0.3, 1.0) as f32;
        let at = b.t + late;
        let busy: f32 = load.iter().map(|(t, v)| v * (-(at - t).abs() / 1.2).exp()).sum();
        let v = v0 / (1.0 + 0.9 * busy);
        load.push((at, v));
        let near = d < 170.0;
        p.csound(b.t + 0.05 + late, if near { "crack" } else { "crack_far" }, 10.0 * v, 0.94 + 0.12 * mh(i as u32, s, 0xd1) as f32);
        if d < 120.0 {
            p.shake(b.t + 0.05 + late, (0.25 * (1.0 - d / 120.0)) as f32 + 0.05, 0.5);
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
                q.ev.push((t + 0.1, Act::Blocks(Box::new(e))));
            });
        }
    }

    // ---- the funnels: their roar where they are, and with the terrain on, their tracks scoured ---------------------------
    for (k, f) in sc_funnels(s).into_iter().enumerate() {
        let f = Rc::new(f);
        let fr = f.clone();
        p.later(f.t0 as f32 - 0.5, move |q| {
            let (bx, by, bz) = (q.bx, q.by, q.bz);
            vortex::roar(q, &fr, "orbital:supercell.roar", [cx, gy, cz], |pt| gy + ground_dy(bx, by, bz, pt[0], pt[1]).unwrap_or(0.0));
        });
        if k == 0 {
            p.at(f.t0 as f32 + 1.0, bar("FUNNEL CLOUD", "gray"));
        }
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

    // ---- the finale: one colossal strike on the target, a shockwave and a jolt ---------------------------------------------
    let tf = SC_FINALE;
    p.at(tf - 3.0, bar("ORBITAL WEATHER CONTROL: DISCHARGE", "aqua"));
    for k in 0..5 {
        let a = 2.0 * PI * f64::from(k) / 5.0;
        let (x, z) = ((cx + a.cos() * 2.0).floor() as i32, (cz + a.sin() * 2.0).floor() as i32);
        p.at(tf + 0.05 * (k % 2) as f32, format!("execute positioned {x} 0 {z} positioned over motion_blocking run summon minecraft:lightning_bolt ~0.5 ~ ~0.5"));
    }
    for k in 1..5 {
        p.at(tf + 0.05 * k as f32 + 0.04, "stopsound @a * minecraft:entity.lightning_bolt.thunder");
    }
    let (late, dist) = sound_from([cx, gy, cz], me);
    p.csound(tf + 0.05 + late, "finale", 10.0, 1.0);
    let fo = falloff(dist).max(0.3);
    p.shake(tf + late, fo, 0.7);
    p.shake(tf + late + 0.05, 0.5 * fo, 2.5);
    for n in 0..8 {
        p.shake(tf + late + 0.1 * (n + 1) as f32, (0.8 - 0.08 * n as f32) * fo, 0.12);
    }
    p.ev.push((tf + (dist / 150.0) as f32, Act::Shove { from: [cx, gy, cz], out: 0.45, up: 0.3, reach: 70.0 }));
    p.at(tf + 0.1, format!("particle minecraft:explosion_emitter {cx:.1} {:.1} {cz:.1} 3 1 3 0 4 force", gy + 1.0));
    p.at(tf + 0.15, format!("particle minecraft:large_smoke {cx:.1} {:.1} {cz:.1} 6 2 6 0.05 160 force", gy + 1.5));
    p.at(tf + 0.2, format!(r#"particle minecraft:block{{block_state:"minecraft:blackstone"}} {cx:.1} {:.1} {cz:.1} 5 2 5 1.2 300 force"#, gy + 2.0));
    p.at(tf + 1.0, bar("DIRECT HIT", "white"));
    if terrain {
        p.later(tf - 0.6, move |q| crater(q, tf + 0.05, s));
    }

    // ---- the storm dies away: the rain stops, the fires it left are put out -------------------------------------------------
    p.at(SC_CLEAR + 2.0, "weather clear");
    p.at(SC_CLEAR + 1.0, bar("STORM DISSIPATING", "gray"));
    if terrain {
        let load = pk_load_rows([cx, gy, cz], 0.0, SC_SWEEP + 4.0);
        for [x0, z0, x1, z1] in &load {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for [x0, z0, x1, z1] in &load {
            p.ev.push((len - 0.5, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        for t0 in [SC_CLEAR + 3.0, len - 3.0] {
            for k in 0..SC_SWEEP_BANDS {
                let t = t0 + 0.1 * k as f32;
                p.later(t - 0.3, move |q| sweep(q, k, t));
            }
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
        let w = super::sc_table(seed as u32, [me[0] - 0.5, me[2] - 0.5], &|_, _| Some(0.0));
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}

/// `SC_OUT=path SC_ME=z cargo test --release sc_write_sounds -- --ignored`: the sounds a player SC_ME blocks south of the
/// target hears (`t event volume`, the roar's at their points' distance), for tools/sounds_storm.py's listening mix.
#[cfg(test)]
#[test]
#[ignore]
fn sc_write_sounds() {
    let z: f64 = std::env::var("SC_ME").map_or(300.0, |v| v.parse().unwrap());
    let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
    let me = [0.5, 66.0, 0.5 + z];
    let laser = crate::lasers::LASERS.iter().find(|l| l.key == "supercell").unwrap();
    let mut ev = crate::strike::plan(laser, &target, false, "minecraft:overworld", 37.0, me, 0);
    let mut out = String::new();
    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
    while let Some((t, a)) = ev.pop() {
        match a {
            Act::Sound { event, at, volume, .. } => {
                // (a positioned sound: as the game fades it, linearly to its range, 320 blocks)
                let v = at.map_or(volume, |p| volume * (1.0 - ((p[0] - me[0]).hypot(p[2] - me[2]) / 320.0).min(1.0)) as f32);
                out += &format!("{t:.3} {event} {v:.3}\n");
            }
            Act::Later(job) => {
                ev.extend(job());
                ev.sort_by(|a, b| b.0.total_cmp(&a.0));
            }
            _ => {}
        }
    }
    std::fs::write(std::env::var("SC_OUT").unwrap(), out).unwrap();
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
                Act::Later(job) | Act::Soon(job) => {
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
    fn supercell_strikes_real_bolts_under_its_cloud_and_stops_vanillas_thunder() {
        let me = [10.5, 66.0, 297.5];
        let (_, cmds, other, _) = played(false, me);
        let bolts: Vec<&(f32, String)> = cmds.iter().filter(|(_, c)| c.contains("summon minecraft:lightning_bolt")).collect();
        assert_eq!(bolts.len(), SC_NB + 5);
        for (t, c) in &bolts {
            assert!(*t >= SC_STORM0 && *t <= SC_FINALE + 0.1, "{t}");
            let w: Vec<f64> = c.split_whitespace().map(|v| v.parse().unwrap_or(0.0)).collect();
            assert!((w[2] - 10.5).hypot(w[4] + 2.5) < SC_REACH + 2.0, "{c}");
            // (each followed by vanilla's thunder stopped)
            assert!(cmds.iter().any(|(t2, s)| s.starts_with("stopsound") && *t2 > *t && *t2 < t + 0.2), "{t}");
        }
        // (faster and faster: more in the storm's second half than its first)
        let mid = 0.5 * (SC_STORM0 + SC_STORM1);
        assert!(bolts.iter().filter(|(t, _)| *t > mid).count() > bolts.iter().filter(|(t, _)| *t < mid).count() + 10);
        // (each heard, and a crack for each; the weather rains, then clears; the pass's table given)
        let sounds: Vec<&str> = other.iter().filter_map(|(_, a)| if let Act::Sound { event, .. } = a { Some(event.as_str()) } else { None }).collect();
        assert_eq!(sounds.iter().filter(|e| e.contains("supercell.crack")).count(), SC_NB);
        assert!(sounds.iter().any(|e| e.ends_with("supercell.finale")) && sounds.iter().any(|e| e.ends_with("supercell.roar")));
        assert!(cmds.iter().any(|(_, c)| c == "weather rain") && cmds.iter().any(|(_, c)| c == "weather clear"));
        assert!(other.iter().any(|(_, a)| matches!(a, Act::Table(w) if w.len() == SC_K + 3 * SC_NK)));
        assert!(other.iter().any(|(_, a)| matches!(a, Act::Shove { .. })));
    }

    #[test]
    fn supercell_leaves_the_land_alone_with_the_terrain_off() {
        let (blocks, cmds, _, _) = played(false, [10.5, 66.0, 297.5]);
        assert!(blocks.is_empty());
        assert!(!cmds.iter().any(|(_, c)| c.contains("forceload") || c.contains("falling_block")));
    }

    #[test]
    fn supercell_pits_are_small_its_crater_is_20_across_and_its_fires_are_swept() {
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
        assert!(reach > 8.0 && reach < 13.0, "the crater reaches {reach}");
        // (the fires put out, out to SC_SWEEP, twice as it ends)
        let swept: Vec<&(f32, String)> = fills.iter().filter(|(_, f)| f.contains("replace #minecraft:fire")).collect();
        assert!(swept.len() as f64 > 2.0 * 0.95 * PI * SC_SWEEP * SC_SWEEP, "{}", swept.len());
        assert!(swept.iter().all(|(t, _)| *t > SC_CLEAR));
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
                Act::Later(job) | Act::Soon(job) => {
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
        assert_eq!(f32::from_bits(w[0]) as usize, SC_NB);
        assert!(SC_B + SC_BW * SC_NB <= SC_F && SC_F + VX_W * SC_NF <= SC_K);
        let b = sc_bolts(37, [0.0, 300.0]);
        assert_eq!(f32::from_bits(w[SC_B + SC_BW * 5]), b[5].t);
        assert_eq!(f32::from_bits(w[SC_B + SC_BW * 5 + 3]), 2.0);
        let f = sc_funnels(37);
        assert_eq!(f32::from_bits(w[SC_F + VX_W]) as f64, f[1].t0 as f32 as f64);
        // (the funnels overlap through the storm, all touching down before the finale)
        assert!(f.iter().all(|f| f.t1 < f64::from(SC_FINALE) && f.t0 > f64::from(SC_STORM0)));
    }
}
