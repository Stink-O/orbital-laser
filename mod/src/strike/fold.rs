//! The Fold's plan: a strike that attacks the shape of the world. There is no beam. Everything that moves is the world's
//! own geometry, far terrain included, through the fork's world warp (`render.set-warp`, shaders/fold_warp.wgsl), timed by
//! the strike clock; shaders/fold.wgsl only adds what is over the picture (the jolts, the sky going out, the point, the
//! blast's flash); the plan makes the sounds and, as the world snaps back, the land.
//!
//! Timeline (FD_LEN 50 s): the hook (0-2 s: the ground bucks at the target and a wave comes out over the land, reaching the
//! player at about 2 s whatever the range); the bend (2-29 s: the wave covers all in view, the land behind it rolls into
//! rings, the horizon curls up and over, the land near the target comes up out of it again as islands round it); the
//! convergence (29-36 s: all of it drawn in to one globe of land at the target, which falls in to a point; a beat of near
//! silence from FD_BEAT); the release (FD_RELEASE, 37 s: the blast, the world flung back straight, the crater in it) and the
//! comedown (39-50 s: colours drain).
//!
//! What is left is the real mandala: a twelve-fold crater (FD_R across 64 blocks) dug into the land in six terraced
//! rings, each its own motif (an eye, twelve petals, twenty-four diamonds, scallops, rainbow spokes, a sunburst), lined
//! in glazed terracotta and coloured concrete, a heaped rim of mycelium round it and giant mushrooms standing where the
//! pass's grew (`fl_giant`). Its columns go in through `world.edit-blocks` as one wave from the middle out, timed with
//! the pass's shockwave, each tile of 16 by 16 worked out by a stage of its own a few ticks before (so no tick does more
//! than a few hundred columns). It reads nothing: every dig and every height is from the column's own ground (a run
//! counted from the heightmap, read before the edit), so it follows hills.
//!
//! Keep FD_* here and in fold.wgsl in step.
use super::{Act, Blocks, Plan, Rng, Target, mh};
use crate::lasers::Laser;
use std::f64::consts::PI;

const TAU: f64 = 2.0 * PI;

pub(super) const FD_LEN: f32 = 50.0;
/// The world warp (shaders/fold_warp.wgsl): how many times it draws the land near the target again, how far from it, and
/// when it is off, the world straight again.
pub const FD_COPIES: u32 = 6;
pub const FD_COPY_R: f32 = 130.0;
pub const FD_WARP_END: f32 = 46.5;
/// The strike's beats: the pass's timeline (fold.wgsl's FD_*).
pub(super) const FD_RELEASE: f32 = 37.0;
#[allow(dead_code)]
pub(super) const FD_BEAT: f32 = 36.0;
/// The mandala: how many folds, how far it is dug, and how far the rim of mycelium reaches.
pub(super) const FD_N: f64 = 12.0;
pub(super) const FD_R: f64 = 64.0;
pub(super) const FD_RIM: f64 = 92.0;
/// Air is cleared this far over the ground (in the mandala; round it).
const FD_CLEAR: i32 = 30;
const FD_CLEAR_RIM: i32 = 20;
/// The land goes in as a wave from the middle out, over this long from FD_RELEASE.
const FD_WAVE: f64 = 1.8;
/// A tile of the work: columns a side.
const FD_TILE: i32 = 16;
/// Where the giant mushrooms stand (the pass grows them at the same place): how far out, how many.
pub(super) const FD_GIANT_R: f64 = 82.0;
pub(super) const FD_GIANTS: usize = 12;

// ---- the blocks ------------------------------------------------------------------------------------------------
/// The rainbow, in coloured concrete and in glazed terracotta (twelve each, the same hues).
const CONC: [&str; 12] = [
    "minecraft:red_concrete",
    "minecraft:orange_concrete",
    "minecraft:yellow_concrete",
    "minecraft:lime_concrete",
    "minecraft:green_concrete",
    "minecraft:cyan_concrete",
    "minecraft:light_blue_concrete",
    "minecraft:blue_concrete",
    "minecraft:purple_concrete",
    "minecraft:magenta_concrete",
    "minecraft:pink_concrete",
    "minecraft:white_concrete",
];
const GLAZED: [&str; 12] = [
    "minecraft:red_glazed_terracotta",
    "minecraft:orange_glazed_terracotta",
    "minecraft:yellow_glazed_terracotta",
    "minecraft:lime_glazed_terracotta",
    "minecraft:green_glazed_terracotta",
    "minecraft:cyan_glazed_terracotta",
    "minecraft:light_blue_glazed_terracotta",
    "minecraft:blue_glazed_terracotta",
    "minecraft:purple_glazed_terracotta",
    "minecraft:magenta_glazed_terracotta",
    "minecraft:pink_glazed_terracotta",
    "minecraft:white_glazed_terracotta",
];
fn conc(i: i32) -> &'static str {
    CONC[i.rem_euclid(12) as usize]
}
fn glazed(i: i32) -> &'static str {
    GLAZED[i.rem_euclid(12) as usize]
}

/// What the mandala makes of a column.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) enum Kind {
    /// Dug `dig` blocks (built up `-dig` over the ground if negative): `top` on it, `under` below, the air over it
    /// cleared to `clear` above the ground.
    Dug { dig: i32, top: &'static str, under: &'static str, clear: i32 },
    /// Only the ground's top block turned to this (where it is dirt, grass, podzol...): the mycelium garden.
    Surface(&'static str),
}

/// The wedge coordinate of angle `a` in a `n`-fold pattern: 0 on a wedge's middle line, 1 on its edge (a mirror
/// axis), the same either side of both: what makes the pattern a kaleidoscope's.
fn wedge(a: f64, n: f64) -> f64 {
    let w = TAU / n;
    ((a.rem_euclid(w) - w / 2.0).abs() / (w / 2.0)).clamp(0.0, 1.0)
}

/// The mandala's column at (`dx`, `dz`) blocks from its middle (continuous: the tests ask at any point). None past the
/// rim. `seed` picks which rainbow phase it starts at.
pub(super) fn mandala(dx: f64, dz: f64, seed: u32) -> Option<Kind> {
    let r = dx.hypot(dz);
    if r >= FD_RIM {
        return None;
    }
    let a = dz.atan2(dx);
    let w = wedge(a, FD_N);
    let phase = (seed % 12) as i32;
    // (the rainbow turns with the radius: every ring its own hue, every motif the hue five along)
    let hue = |r: f64| phase + (r / FD_R * 11.0).floor() as i32;
    let dug = |dig: i32, top: &'static str, under: &'static str| Some(Kind::Dug { dig, top, under, clear: FD_CLEAR });
    if r < 7.0 {
        // the eye: a deep well, a light in its floor
        return if r < 3.0 { dug(24, "minecraft:sea_lantern", "minecraft:white_concrete") } else { dug(22, glazed(hue(r) + (w * 3.0) as i32 + 6), conc(hue(r))) };
    }
    if r < 17.0 {
        // twelve petals, leaf-shaped, each a terrace higher than the field between them, and a line round every one
        let u = (r - 7.0) / 10.0;
        let pw = 0.06 + 0.94 * (u * PI).sin().powf(0.6);
        let arc = (w - pw) * r * (PI / FD_N);
        if arc.abs() < 0.55 {
            return dug(17, glazed(hue(r) + 3), conc(hue(r) + 6));
        }
        return if w < pw { dug(18, glazed(hue(r) + 5 + (u * 3.0) as i32), conc(hue(r) + 2)) } else { dug(15, conc(hue(r)), conc(hue(r) + 4)) };
    }
    if r < 27.0 {
        // twenty-four diamonds on a field, a core in each
        let w24 = wedge(a, FD_N * 2.0);
        let arc = w24 * r * (PI / (FD_N * 2.0));
        let v = (r - 22.0).abs() / 5.0 + arc / 4.0;
        if v < 0.4 {
            return dug(11, glazed(hue(r) + 8), conc(hue(r) + 2));
        }
        if v < 1.0 {
            return dug(12, glazed(hue(r) + 4), conc(hue(r) + 7));
        }
        return dug(14, conc(hue(r) + (r > 22.0) as i32), conc(hue(r) + 5));
    }
    if r < 39.0 {
        // scallops: the ring's edge bulging out at every wedge's edge, a line along it
        let re = 33.0 + 4.0 * (a * FD_N).cos();
        if (r - re).abs() < 0.9 {
            return dug(10, glazed(hue(r) + 9), conc(hue(r) + 3));
        }
        return if r < re { dug(11, glazed(hue(r) + 2 + (w * 2.0) as i32), conc(hue(r) + 5)) } else { dug(9, conc(hue(r) + 6), conc(hue(r))) };
    }
    if r < 51.0 {
        // spokes, thirty-six of them, every other one a step down, the rainbow running across each wedge
        let w36 = wedge(a, FD_N * 3.0);
        let k = (w * 5.99) as i32;
        if w36 < 0.5 {
            return dug(7, glazed(hue(r) + k * 2), conc(hue(r) + k));
        }
        return dug(5, conc(hue(r) + k * 2 + 1), conc(hue(r) + k + 4));
    }
    if r < FD_R {
        // a sunburst: twelve long spikes and twelve short between them, standing up out of a step down
        let u = (r - 51.0) / (FD_R - 51.0);
        if w < 1.0 - u {
            return Some(Kind::Dug { dig: -3, top: glazed(hue(r) + 7), under: conc(hue(r) + 1), clear: FD_CLEAR });
        }
        if w > 0.75 + 0.2 * u && u < 0.55 {
            return Some(Kind::Dug { dig: -1, top: glazed(hue(r) + 2), under: conc(hue(r) + 8), clear: FD_CLEAR });
        }
        return dug(3, conc(hue(r) + 3), conc(hue(r) + 9));
    }
    if r < FD_R + 12.0 {
        // the rim: a heap of earth round it, mycelium on top
        let u = (r - FD_R) / 12.0;
        let wob = 0.75 + 0.5 * mh((a * 48.0).floor() as i32 as u32, seed, 21);
        let h = (3.6 * (u * PI).sin().powf(1.2) * wob).round() as i32;
        let top = if mh(((dx.floor() as i32 as u32).wrapping_mul(73_856_093)) ^ ((dz.floor() as i32 as u32).wrapping_mul(19_349_663)), seed, 22) < 0.28 { "minecraft:podzol" } else { "minecraft:mycelium" };
        return Some(Kind::Dug { dig: -h, top, under: "minecraft:dirt", clear: FD_CLEAR_RIM });
    }
    // the garden beyond it: mycelium and podzol on the ground, thinning out
    let u = (r - (FD_R + 12.0)) / (FD_RIM - FD_R - 12.0);
    let h = mh((dx.floor() as i32 as u32).wrapping_mul(2_654_435_761) ^ (dz.floor() as i32 as u32).wrapping_mul(40_503), seed, 23);
    if h < 0.9 * (1.0 - u * u) {
        return Some(Kind::Surface(if h < 0.25 { "minecraft:podzol" } else { "minecraft:mycelium" }));
    }
    None
}

/// When the wave reaches radius `r` (strike seconds): from the middle out, a touch faster at first.
pub(super) fn due(r: f64) -> f32 {
    FD_RELEASE + (FD_WAVE * (r / FD_RIM).clamp(0.0, 1.0).powf(0.8)) as f32
}

/// How far from the middle the crater is cut to the one level; past it that eases into the land's own heights, to
/// the rim.
const FD_LEVEL_R: f64 = 70.0;
/// The most a hollow is filled up under the crater's floor.
const FD_FILL: i32 = 40;
/// Strike seconds past which a column still not loaded is left out (logged): the forceload is given back at FD_LEN.
const FD_LAND_BY: f32 = FD_LEN - 4.0;

/// One column of the mandala into `b`: `g` its ground (the first air over it, as the world answered), `level` the one
/// height the whole crater is cut to, so hills are cut away (or hollows filled) to a clean floor, not followed.
fn column(b: &mut Blocks, x: i32, z: i32, cx: f64, cz: f64, seed: u32, level: i32, g: i32) {
    let (dx, dz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
    let Some(kind) = mandala(dx, dz, seed) else { return };
    // (the level eased into the land's own height over the rim: a round blend, not a cliff)
    let t = ((FD_RIM - dx.hypot(dz)) / (FD_RIM - FD_LEVEL_R)).clamp(0.0, 1.0);
    let lv = g + (f64::from(level - g) * t * t * (3.0 - 2.0 * t)).round() as i32;
    match kind {
        Kind::Surface(block) => b.put(x, z, g - 1, g - 1, block, Some("#minecraft:dirt"), false),
        Kind::Dug { dig, top, under, clear } => {
            // (the top block's height; a hollow under it filled in with the stone, then the top, then the air to well over
            // the highest of the old ground and the new, trees and all)
            let (yt, air_from) = if dig > 0 { (lv - dig - 1, lv - dig) } else { (lv - dig.max(-64) - 1, lv - dig) };
            let h = (-dig).max(0);
            if g - 1 < yt || h > 1 {
                let lo = if g - 1 < yt { (g - 2).max(yt - FD_FILL) } else { lv };
                b.put(x, z, lo, yt - 1, under, None, false);
            }
            if dig > 0 || h == 0 {
                b.put(x, z, yt - 1, yt - 1, under, None, false);
            }
            b.put(x, z, yt, yt, top, None, false);
            b.put(x, z, air_from, g.max(air_from) + clear, "minecraft:air", None, false);
        }
    }
}

/// A giant mushroom's place (k of FD_GIANTS), from the target.
pub(super) fn fl_giant(k: usize) -> (f64, f64) {
    let a = (k as f64 + 0.5) * TAU / FD_GIANTS as f64;
    (FD_GIANT_R * a.cos(), FD_GIANT_R * a.sin())
}

/// A mushroom's blocks: a stem `h` high, a dome of `cap` blocks' radius on it in `cap_block`.
fn mushroom(b: &mut Blocks, x: i32, z: i32, h: i32, cap: i32, cap_block: &'static str) {
    b.put(x, z, 0, h - 1, "minecraft:mushroom_stem", None, true);
    for dy in 0..cap.max(1) {
        let rr = f64::from(cap - dy) + 0.5;
        let n = rr.ceil() as i32;
        for ix in -n..=n {
            for iz in -n..=n {
                if f64::from(ix * ix + iz * iz).sqrt() <= rr {
                    b.put(x + ix, z + iz, h + dy, h + dy, cap_block, None, true);
                }
            }
        }
    }
}

/// The mushrooms left round the rim: a giant where each of the pass's grew, smaller ones scattered, little ones among them.
fn mushrooms(q: &mut Plan, cx: f64, cz: f64, seed: u32) {
    let mut b = Blocks { clear_of_player: true, ..Default::default() };
    for k in 0..FD_GIANTS {
        let (ox, oz) = fl_giant(k);
        let (x, z) = ((cx + ox).floor() as i32, (cz + oz).floor() as i32);
        let cap = if k % 2 == 0 { "minecraft:red_mushroom_block" } else { "minecraft:brown_mushroom_block" };
        mushroom(&mut b, x, z, 7 + (k % 3) as i32, 5, cap);
    }
    for i in 0..44u32 {
        let a = mh(i, seed, 31) * TAU;
        let r = FD_R + 6.0 + mh(i, seed, 32) * (FD_RIM - FD_R - 8.0);
        let (x, z) = ((cx + r * a.cos()).floor() as i32, (cz + r * a.sin()).floor() as i32);
        let cap = if mh(i, seed, 33) < 0.5 { "minecraft:red_mushroom_block" } else { "minecraft:brown_mushroom_block" };
        mushroom(&mut b, x, z, 2 + (mh(i, seed, 34) * 3.0) as i32, 1 + (mh(i, seed, 35) * 2.0) as i32, cap);
    }
    for i in 0..120u32 {
        let a = mh(i, seed, 41) * TAU;
        let r = FD_R + 3.0 + mh(i, seed, 42) * (FD_RIM - FD_R - 3.0);
        let (x, z) = ((cx + r * a.cos()).floor() as i32, (cz + r * a.sin()).floor() as i32);
        b.put(x, z, 0, 0, if mh(i, seed, 43) < 0.5 { "minecraft:red_mushroom" } else { "minecraft:brown_mushroom" }, Some("minecraft:air"), true);
    }
    for (t, part) in b.split_by(|x, z| due((f64::from(x) + 0.5 - cx).hypot(f64::from(z) + 0.5 - cz)) + 0.3) {
        q.ev.push((t, Act::Blocks(Box::new(part))));
    }
}

pub(super) fn fold_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let s = shader_seed as u32;
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let dist = (me[0] - cx).hypot(me[2] - cz);

    // ---- sound: the drone (the whole of it, the beat of near silence in it), the bloom, the comedown ----------------
    p.csound(0.0, "drone", 8.0, 1.0);
    p.csound(FD_RELEASE, "bloom", 10.0, 1.0);
    p.csound(FD_RELEASE + 2.0, "comedown", 8.0, 1.0);
    // (one jolt as it snaps back, felt more the nearer they are; nothing shakes the rest of the time)
    p.shake(FD_RELEASE, 0.3 * super::falloff(dist), 2.5);
    // (and the hook: the ground bucking, then the wave going under them)
    p.shake(0.1, 0.12 * super::falloff(dist), 1.2);
    p.shake(2.0, 0.16, 1.4);

    if !terrain {
        p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
        return p.ev;
    }
    // ---- the land: the chunks it goes into loaded, the mandala a tile a stage, the mushrooms after it -----------------
    let (x0, z0, x1, z1) = (bx - 100, bz - 100, bx + 100, bz + 100);
    p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
    p.ev.push((FD_LEN - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
    let mut k = 0;
    let n = (FD_RIM as i32 + FD_TILE - 1) / FD_TILE;
    // (nearest the middle first)
    let mut tiles: Vec<(i32, i32)> = (-n..n).flat_map(|i| (-n..n).map(move |j| (i, j))).collect();
    let reach = |(i, j): (i32, i32)| {
        let nx = (f64::from(i * FD_TILE) + 0.5 * f64::from(FD_TILE)).abs() - 0.5 * f64::from(FD_TILE);
        let nz = (f64::from(j * FD_TILE) + 0.5 * f64::from(FD_TILE)).abs() - 0.5 * f64::from(FD_TILE);
        nx.max(0.0).hypot(nz.max(0.0))
    };
    tiles.retain(|&t| reach(t) < FD_RIM);
    tiles.sort_by(|a, b| reach(*a).total_cmp(&reach(*b)));
    // (each tile asks the world for its columns' ground first, then is cut once every one of them has answered: a column
    // the world has not loaded yet is asked for again, so none is left standing or edited into the void)
    let level = by + 1;
    for (i, j) in tiles {
        let at = 20.0 + 0.09 * k as f32;
        k += 1;
        let (tx, tz) = (bx + i * FD_TILE, bz + j * FD_TILE);
        // (worked out in the tile's own stage: every column of the crater at once is far over a tick's fuel at the fire)
        p.later(at, move |q| {
            crate::meter::spend(4_000 * (FD_TILE * FD_TILE) as u64);
            let cols: Vec<(i32, i32)> = (tx..tx + FD_TILE).flat_map(|x| (tz..tz + FD_TILE).map(move |z| (x, z))).filter(|&(x, z)| mandala(f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz, s).is_some()).collect();
            if !cols.is_empty() {
                fl_tile(q, at, None, cols, cx, cz, s, level);
            }
        });
    }
    p.later(at_mushrooms(k), move |q| mushrooms(q, cx, cz, s));
    // (playback goes through the plan in order, and stops at the first not due: one out of order holds up all after it)
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}
/// A tile's stage: ask for its columns' ground (those not known yet), and when all are in, cut it; else look again.
fn fl_tile(q: &mut Plan, now: f32, asked: Option<u32>, cols: Vec<(i32, i32)>, cx: f64, cz: f64, seed: u32, level: i32) {
    // (the answer to the last ask still to come: wait for it rather than ask again)
    if let Some(t) = asked
        && !crate::ground::ready(t)
        && now < FD_LAND_BY
    {
        let next = now + 0.2;
        q.later(next, move |q| fl_tile(q, next, asked, cols, cx, cz, seed, level));
        return;
    }
    let missing: Vec<(i32, i32)> = cols.iter().copied().filter(|&(x, z)| crate::ground::at(x, z).is_none()).collect();
    crate::meter::spend(40 * cols.len() as u64);
    if !missing.is_empty() && now < FD_LAND_BY {
        let tag = crate::ground::new_tag();
        let next = now + 0.3;
        q.ev.push((now, Act::Survey { tag, columns: missing }));
        q.later(next, move |q| fl_tile(q, next, Some(tag), cols, cx, cz, seed, level));
        return;
    }
    if !missing.is_empty() {
        crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("fold: {} columns of the land never loaded; left out", missing.len()));
    }
    let mut b = Blocks { clear_of_player: true, ..Default::default() };
    for &(x, z) in &cols {
        if let Some(g) = crate::ground::at(x, z) {
            column(&mut b, x, z, cx, cz, seed, level, g);
        }
    }
    // (late ones go in at once: no wave left to time them to)
    for (t, part) in b.split_by(|x, z| due((f64::from(x) + 0.5 - cx).hypot(f64::from(z) + 0.5 - cz)).max(now)) {
        q.ev.push((t, Act::Blocks(Box::new(part))));
    }
}
/// When the mushrooms are worked out: after the last tile's stage.
fn at_mushrooms(tiles: usize) -> f32 {
    20.5 + 0.09 * tiles as f32
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::{Target, plan, sim};

    /// The warp's beats are the plan's and the pass's, and its copies' radius what lib.rs asks the game for.
    #[test]
    fn the_warp_keeps_the_beats() {
        let warp = include_str!("../../shaders/fold_warp.wgsl");
        let pass = include_str!("../../shaders/fold.wgsl");
        assert!(warp.contains(&format!("const FW_REL: f32 = {FD_RELEASE:.1};")));
        assert!(warp.contains(&format!("const FW_BEAT: f32 = {FD_BEAT:.1};")));
        assert!(warp.contains(&format!("const FW_DISC: f32 = {FD_COPY_R:.1};")));
        assert!(warp.contains(&format!("const FW_COPIES: f32 = {:.1};", f64::from(FD_COPIES))));
        assert!(pass.contains(&format!("const FD_REL: f32 = {FD_RELEASE:.1};")));
    }

    fn the_laser() -> &'static Laser {
        crate::lasers::LASERS.iter().find(|l| l.key == "fold").expect("the fold")
    }
    fn target() -> Target {
        Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] }
    }

    /// The mandala is a kaleidoscope: turning it a twelfth of a turn, or mirroring it across a wedge's edge, gives the
    /// same column (every dig, every block), wherever it is asked.
    #[test]
    fn the_mandala_is_twelvefold_and_mirrored() {
        let mut checked = 0;
        for i in 0..4000u32 {
            let r = 1.0 + 62.0 * mh(i, 5, 1);
            let a = mh(i, 5, 2) * TAU;
            // (the rim's wobble and the garden are from the block's own cell: only the rings are symmetric)
            let k = mandala(r * a.cos(), r * a.sin(), 3);
            for turn in [1.0, 5.0, 11.0] {
                let b = a + turn * TAU / FD_N;
                assert_eq!(k, mandala(r * b.cos(), r * b.sin(), 3), "turned {turn} at r {r:.2}, angle {a:.3}");
            }
            let m = -a; // (the mirror across the x axis, an edge)
            assert_eq!(k, mandala(r * m.cos(), r * m.sin(), 3), "mirrored at r {r:.2}, angle {a:.3}");
            checked += 1;
        }
        assert_eq!(checked, 4000);
    }

    /// The rings are terraced: every column of the mandala is dug between a built-up three and a well of 24, and it
    /// has more than a few hues.
    #[test]
    fn the_mandala_is_terraced_and_colourful() {
        let mut hues = std::collections::BTreeSet::new();
        let mut depths = std::collections::BTreeSet::new();
        for i in -64..64 {
            for j in -64..64 {
                if let Some(Kind::Dug { dig, top, .. }) = mandala(f64::from(i) + 0.5, f64::from(j) + 0.5, 3)
                    && (f64::from(i).hypot(f64::from(j)) as f64) < FD_R
                {
                    assert!((-3..=24).contains(&dig), "{dig}");
                    depths.insert(dig);
                    hues.insert(top);
                }
            }
        }
        assert!(hues.len() >= 16, "{} blocks on top", hues.len());
        assert!(depths.len() >= 10, "{depths:?}");
    }

    /// The whole land goes in as one wave from the middle out, from the release to a couple of seconds after it, in
    /// edits no bigger than a tile's, and nothing is placed past the rim and its mushrooms.
    #[test]
    fn the_land_goes_in_as_a_wave_from_the_middle_out() {
        crate::columns::clear();
        crate::ground::set_test(Some(|_, _| Some(65)));
        let ev = plan(the_laser(), &target(), true, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let p = sim::play(ev, FD_LEN, &|_, _, _, _| None);
        let runs: usize = p.edits.iter().map(|e| e.2.runs.len()).sum();
        assert!(runs > 20_000, "{runs} runs");
        let mut last = 0.0f32;
        for (_, t, b) in &p.edits {
            assert!(*t >= FD_RELEASE - 0.01 && *t <= FD_RELEASE + 2.4, "an edit due at {t}");
            last = last.max(*t);
            for r in &b.runs {
                assert!(f64::from(r.x).hypot(f64::from(r.z)) < FD_RIM + 8.0, "a run at {} {}", r.x, r.z);
            }
        }
        assert!(last > FD_RELEASE + 1.2, "the wave ended at {last}");
        // (the middle first: the well's edit is earlier than the sunburst's)
        let first = |rl: f64, rh: f64| p.edits.iter().filter(|e| e.2.runs.iter().any(|r| (f64::from(r.x) + 0.5).hypot(f64::from(r.z) + 0.5) >= rl && (f64::from(r.x) + 0.5).hypot(f64::from(r.z) + 0.5) < rh)).map(|e| e.1).fold(f32::MAX, f32::min);
        assert!(first(0.0, 8.0) < first(50.0, 64.0));
        // (forceloaded as it begins, and given back at the end)
        assert!(p.cmds.iter().any(|c| c.1.starts_with("forceload add")));
    }

    fn hills(x: i32, z: i32) -> Option<i32> {
        // (hilly: up to 14 over and 9 under the target's, rolling; the strip x >= 70 not loaded)
        let h = 65.0 + 9.0 * (f64::from(x) * 0.07).sin() + 5.0 * (f64::from(z) * 0.11).cos();
        (x < 70).then_some(h as i32)
    }

    /// Every column inside the crater's radius is edited, on hilly land, and the crater is one level cut (its floor
    /// tops at the one height, whatever the ground) with the air cleared over the old ground; land loaded late is
    /// waited for (the strip of it not loaded for the first seconds comes in late, nothing left standing).
    #[test]
    fn every_column_of_the_crater_is_cut_on_hills() {
        crate::ground::set_test(Some(|x, z| hills(x, z)));
        let ev = plan(the_laser(), &target(), true, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let p = sim::play(ev, FD_LEN, &|_, _, _, _| None);
        let mut cut: std::collections::HashSet<(i32, i32)> = Default::default();
        for (_, _, b) in &p.edits {
            for r in &b.runs {
                cut.insert((r.x, r.z));
            }
        }
        let mut miss = 0;
        for x in -80..80 {
            for z in -80..80 {
                let (dx, dz) = (f64::from(x) + 0.5 - 0.5, f64::from(z) + 0.5 - 0.5);
                if mandala(dx, dz, 37).is_some() && hills(x, z).is_some() && !cut.contains(&(x, z)) {
                    miss += 1;
                }
            }
        }
        assert_eq!(miss, 0, "{miss} columns of the crater left standing");
        crate::ground::set_test(None);
    }

    /// Playback takes the plan in order and stops at the first entry not due: the plan must be in time order, or what
    /// follows a later entry waits for it (the crater's tiles waited for the forceload's end, and only one went in).
    #[test]
    fn the_plan_is_in_time_order() {
        for terrain in [false, true] {
            let ev = plan(the_laser(), &target(), terrain, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
            assert!(ev.windows(2).all(|w| w[0].0 <= w[1].0), "terrain {terrain}");
        }
    }

    /// With the terrain left alone there is only sound, and the jolts.
    #[test]
    fn without_terrain_the_fold_is_light_and_sound() {
        let ev = plan(the_laser(), &target(), false, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        assert!(ev.iter().all(|e| matches!(e.1, Act::Sound { .. } | Act::Shake { .. })), "only sounds and a jolt");
        assert!(ev.iter().any(|e| matches!(&e.1, Act::Sound { event, .. } if event == "orbital:fold.bloom")));
    }

    /// The plan as it is made on the fire tick stays light: the tiles wait for stages of their own.
    #[test]
    fn fold_fire_cost() {
        for terrain in [false, true] {
            crate::meter::reset();
            let ev = plan(the_laser(), &target(), terrain, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
            let spent = crate::meter::spent();
            eprintln!("terrain {terrain}: plan {:.2}M on the meter, {} acts", spent as f64 / 1e6, ev.len());
            assert!(spent < 2_000_000, "the plan took {:.2}M", spent as f64 / 1e6);
        }
    }

    /// (timed: run it on its own, `cargo test --release fold_no_stage -- --ignored`)
    #[test]
    #[ignore]
    fn fold_no_stage_too_heavy_anywhere() {
        // (timed, natively: no stage over 1.3 ms, wherever it strikes)
        if cfg!(debug_assertions) {
            return;
        }
        let mut best: Vec<f64> = Vec::new();
        for _ in 0..3 {
            crate::columns::clear();
            crate::ground::set_test(Some(|_, _| Some(65)));
            let ev = plan(the_laser(), &target(), true, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
            let p = sim::play(ev, FD_LEN, &|_, _, _, _| None);
            let ms: Vec<f64> = p.stages.iter().map(|s| s.2).collect();
            best = if best.is_empty() || best.len() != ms.len() { ms } else { best.iter().zip(&ms).map(|(a, b)| a.min(*b)).collect() };
        }
        let worst = best.iter().copied().fold(0.0, f64::max);
        eprintln!("{} stages, heaviest {worst:.2} ms", best.len());
        assert!(worst < 1.3, "a stage took {worst:.2} ms");
    }

    /// The land as voxels for the preview (tools/preview.py's `vox=2` views), written to $FL_OUT: a line `x y z r g b` a
    /// block, over flat land with its ground at y 65.
    #[test]
    #[ignore]
    fn fl_dump_land() {
        let out = std::env::var("FL_OUT").unwrap_or("../dist/preview/fold_land.txt".into());
        crate::columns::clear();
        let ev = plan(the_laser(), &target(), true, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let p = sim::play(ev, FD_LEN, &|_, _, _, _| None);
        let rgb = |name: &str| -> Option<[f32; 3]> {
            let n = name.strip_prefix("minecraft:")?;
            let hue = |c: &str| -> [f32; 3] {
                match c {
                    "red" => [0.69, 0.18, 0.15],
                    "orange" => [0.85, 0.4, 0.07],
                    "yellow" => [0.94, 0.72, 0.1],
                    "lime" => [0.44, 0.7, 0.1],
                    "green" => [0.29, 0.4, 0.14],
                    "cyan" => [0.08, 0.52, 0.55],
                    "light_blue" => [0.2, 0.55, 0.78],
                    "blue" => [0.18, 0.2, 0.62],
                    "purple" => [0.4, 0.14, 0.62],
                    "magenta" => [0.7, 0.2, 0.65],
                    "pink" => [0.9, 0.5, 0.65],
                    _ => [0.9, 0.9, 0.9],
                }
            };
            Some(if let Some(c) = n.strip_suffix("_glazed_terracotta") {
                let h = hue(c);
                [h[0] * 0.95 + 0.04, h[1] * 0.95 + 0.04, h[2] * 0.95 + 0.04]
            } else if let Some(c) = n.strip_suffix("_concrete") {
                hue(c)
            } else {
                match n {
                    "sea_lantern" => [1.3, 1.4, 1.3],
                    "mycelium" => [0.45, 0.36, 0.45],
                    "podzol" => [0.35, 0.24, 0.1],
                    "dirt" => [0.4, 0.28, 0.18],
                    "mushroom_stem" => [0.85, 0.8, 0.7],
                    "red_mushroom_block" => [0.75, 0.1, 0.1],
                    "brown_mushroom_block" => [0.5, 0.35, 0.2],
                    "red_mushroom" | "brown_mushroom" => [0.6, 0.2, 0.2],
                    _ => return None,
                }
            })
        };
        let mut cols: std::collections::HashMap<(i32, i32), Vec<(i32, [f32; 3])>> = Default::default();
        for (_, _, b) in &p.edits {
            for r in &b.runs {
                let name = b.edit().palette[r.block as usize].clone();
                for dy in 0..r.height as i32 {
                    // (relative to the ground: its top block at -1, the surface at 65)
                    let y = 65 + r.y + dy;
                    let v = cols.entry((r.x, r.z)).or_default();
                    v.retain(|e| e.0 != y);
                    if let Some(c) = rgb(&name) {
                        v.push((y, c));
                    }
                }
            }
        }
        let mut s = String::new();
        for ((x, z), v) in &cols {
            let top = v.iter().map(|e| e.0).max().unwrap_or(64);
            for (y, c) in v {
                s.push_str(&format!("{x} {y} {z} {} {} {}\n", c[0], c[1], c[2]));
            }
            // (the rock under it, so the terraces' walls are solid)
            for y in (top - 9)..top {
                if !v.iter().any(|e| e.0 == y) {
                    s.push_str(&format!("{x} {y} {z} 0.36 0.3 0.26\n"));
                }
            }
        }
        std::fs::create_dir_all(std::path::Path::new(&out).parent().unwrap()).unwrap();
        std::fs::write(&out, s).unwrap();
        eprintln!("{} columns -> {out}", cols.len());
    }
}
