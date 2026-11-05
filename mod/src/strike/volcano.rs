//! The Supervolcano's plan. A hairline beam touches the land (VC_BEAM to VC_HIT) and cuts out; for ten seconds almost
//! nothing happens but a tremor building. At VC_CRACK the land splits in a ring 560 across, steam jetting off it. At
//! VC_ERUPT the ring opens: a ring of vents feeds a column that climbs to about 1,800 blocks (a dark jet low down, rough
//! convective cauliflower higher up, overshooting at its top), lava bombs arc off it on ballistic paths (VC_BOMBS), its
//! lightning starts (VC_LIGHT), its umbrella spreads flat across the whole sky (VC_DARK), a ripple running out through
//! it, until the sky is dark at noon. At VC_COLLAPSE the column loses its buoyancy and falls back on itself, the land
//! inside the ring drops, and the fall feeds a wall of ash rolling out over the land in lobes and clefts (60 blocks a
//! second at the ring, slowing to 25: `vc_front`), which reaches a player 500 off at about 48 s. Behind it the ash lifts
//! off the land in new clouds (VC_LIFT), ash falling out of them, until the sky thins round a blood-red sun (VC_RED) and
//! everything is gone by VC_LEN. The story's times are in BEATS.md of the team notes; shaders/volcano.wgsl keeps its
//! VC_* in step with these.
//!
//! The pass reads (render.set-data, `mod_data`): the table (`vc_table`: the lava bombs from VC_BOMB, each with where it
//! lands, solved against the land) and the land's height (from VC_HF, as the Nuke's heightfield: the flows hug it).
//! What it leaves is real blocks, terrain on only: strike/vc_land.rs. With the terrain off it is light and sound only.
use super::*;
use std::rc::Rc;

/// The story's times (strike seconds). Keep in step with shaders/volcano.wgsl.
pub(super) const VC_HIT: f32 = 2.0;
pub(super) const VC_CRACK: f32 = 8.0;
pub(super) const VC_ERUPT: f32 = 12.0;
pub(super) const VC_BOMBS: f32 = 13.0;
pub(super) const VC_BOMBS_END: f32 = 30.0;
pub(super) const VC_LIGHT: f32 = 20.0;
pub(super) const VC_COLLAPSE: f32 = 44.0;
/// The ring of vents' radius.
pub(super) const VC_RING: f64 = 280.0;
/// The vent is at least this far in front of the player, along the way they aimed.
const VC_NEAR: f64 = 500.0;
/// The speed of sound, blocks a second (the eruption's sound and its pressure ring).
const VC_V: f64 = 343.0;

/// The table: the bombs from VC_BOMB, VC_BW words each (when thrown, from x y z, its velocity, when it lands), sorted by
/// when they are thrown; the land from VC_HF.
pub(super) const VC_BOMB: usize = 16;
pub(super) const VC_BW: usize = 8;
pub(super) const VC_BOMBS_N: usize = 96;
/// The bombs fall at this, blocks a second squared.
pub(super) const VC_G: f64 = 28.0;
pub(super) const VC_HF: usize = 1024;
pub(super) const VC_HN: usize = 128;

/// How far the wall of ash has come from the middle `c` seconds after the collapse (volcano.wgsl's `vc_front`): 60 blocks
/// a second at the ring, slowing to 25.
pub(super) fn vc_front(c: f64) -> f64 {
    VC_RING + 25.0 * c + 490.0 * (1.0 - (-c / 14.0).exp())
}

/// How far to move a designated `point` (x and z) so the vent lies at least VC_NEAR in front of the player, along the
/// way they aimed; none if it does already.
pub(crate) fn vc_vent(point: [f64; 3], me: [f64; 3]) -> [f64; 2] {
    let (dx, dz) = (point[0] - me[0], point[2] - me[2]);
    let d = dx.hypot(dz);
    if d >= VC_NEAR {
        return [0.0, 0.0];
    }
    if d < 1.0 {
        return [0.0, VC_NEAR];
    }
    [dx / d * (VC_NEAR - d), dz / d * (VC_NEAR - d)]
}

/// The columns the land's height is read from (row by row, z then x).
fn vc_hf_columns(bx: i32, bz: i32, reach: f64) -> Vec<(i32, i32)> {
    let n = VC_HN as i32;
    let step = 2.0 * reach / f64::from(n - 1);
    let at = |i: i32| (-reach + step * f64::from(i)).round() as i32;
    (0..n).flat_map(|k| (0..n).map(move |i| (bx + at(i), bz + at(k)))).collect()
}
/// How far the land's height reaches round the vent, for a player `dme` off.
fn vc_hf_reach(dme: f64) -> f64 {
    (dme * 1.3 + 600.0).clamp(1500.0, 2200.0)
}
/// The land's words (from VC_HF): its size, its reach, then from VC_HF + 8 a word a cell: the height in the low 16 bits
/// (an eighth of a block, from 512 under the vent's ground).
fn vc_hf_pack(heights: &[Option<f64>], reach: f64) -> Vec<u32> {
    let (sum, cnt) = heights.iter().flatten().fold((0.0, 0.0), |(s, c), &h| (s + h, c + 1.0));
    let guess = if cnt > 0.0 { sum / cnt } else { 0.0 };
    let mut w = vec![(VC_HN as f32).to_bits(), (reach as f32).to_bits(), 0, 0, 0, 0, 0, 0];
    w.extend(heights.iter().map(|h| ((h.unwrap_or(guess) + 512.0) * 8.0).round().clamp(0.0, 65535.0) as u32));
    w
}

/// What the pass reads (see VC_BOMB): worked out on the tick after it fires.
pub(super) fn vc_table(seed: f32, me: [f64; 3]) -> Vec<u32> {
    let mut w = vec![0.0f32; VC_HF];
    w[0] = 1.0;
    w[1] = VC_BOMBS_N as f32;
    w[2] = me[0] as f32;
    w[3] = me[2] as f32;
    w.into_iter().map(f32::to_bits).collect()
}

pub(super) fn volcano_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let rel = [me[0] - cx, me[1] - gy, me[2] - cz];
    let _ = terrain;

    // the pass's table, on the tick after it fires
    {
        let s = shader_seed;
        p.later(0.05, move |q| q.ev.push((0.05, Act::Table(vc_table(s, rel)))));
    }
    // (and the land's shape round it)
    {
        let reach = vc_hf_reach(rel[0].hypot(rel[2]));
        let columns = Rc::new(vc_hf_columns(bx, bz, reach));
        let tag = crate::ground::new_tag();
        let cols = columns.clone();
        p.later(0.1, move |q| q.ev.push((0.1, Act::Survey { tag, columns: cols.to_vec() })));
        p.later(0.4, move |q| vc_hf_step(q, tag, columns, reach, by + 1, 0.4));
    }

    // ---- the sounds: strike/vc_sound.rs, wired in at the merge ---------------------------------------------------------
    // [vc_sounds call site] vc_sound::vc_sounds(&mut p, ...);

    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// The land's height, once the world has answered (asking again a little later until it has, while there is time).
fn vc_hf_step(q: &mut Plan, tag: u32, columns: Rc<Vec<(i32, i32)>>, reach: f64, gy: i32, at_t: f32) {
    if !crate::ground::ready(tag) {
        if at_t < VC_ERUPT {
            q.later(at_t + 0.2, move |q| vc_hf_step(q, tag, columns, reach, gy, at_t + 0.2));
        }
        return;
    }
    crate::meter::spend(600 * columns.len() as u64);
    let heights: Vec<Option<f64>> = columns
        .iter()
        .map(|&(x, z)| crate::ground::at(x, z).map(|g| f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy)))
        .collect();
    q.ev.push((at_t, Act::Words { index: VC_HF as u32, words: vc_hf_pack(&heights, reach) }));
}

#[cfg(test)]
mod table {
    /// `CB_SEED=37 CB_OUT=path PL_ME=x,y,z cargo test --release vc_write_table -- --ignored`: the table the pass reads,
    /// for tools/preview.py (a line `index value` a word), the vent's ground at the preview's (0.5 65 0.5).
    #[test]
    #[ignore]
    fn vc_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let me: Vec<f64> = std::env::var("PL_ME").map_or(vec![0.0, 70.0, 560.0], |v| v.split(',').map(|x| x.parse().unwrap()).collect());
        let rel = [me[0] - 0.5, me[1] - 65.0, me[2] - 0.5];
        let mut w = super::vc_table(seed, rel);
        // (the land's shape, as tools/preview draws it: PL_HILLS=H its hills, flat otherwise)
        let hills: f64 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap());
        let reach = super::vc_hf_reach(rel[0].hypot(rel[2]));
        let f = |x: f64, z: f64| hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin());
        let f0 = if std::env::var("PL_FLUSH").is_ok_and(|v| v == "1") { f(0.5, 0.5) } else { 0.0 };
        let heights: Vec<Option<f64>> = super::vc_hf_columns(0, 0, reach).iter().map(|&(x, z)| Some(f(f64::from(x) + 0.5, f64::from(z) + 0.5) - f0)).collect();
        let hf = super::vc_hf_pack(&heights, reach);
        w.resize(super::VC_HF + hf.len(), 0);
        w[super::VC_HF..].copy_from_slice(&hf);
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}
