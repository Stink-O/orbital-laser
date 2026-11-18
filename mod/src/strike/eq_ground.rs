//! The land's own heights under the Earthquake's dust (shaders/earthquake_dust.wgsl's `eqd_land`): a grid over the box
//! the dust is marched in, in the fault's own frame (u along it from the zone's near end to where the crack ends, v
//! `EQ_HALF_V` to each side), asked of the world as the strike fires (`world.surface-height`, ground.rs: the ground
//! under leaves, the water's top where it stands) and given to the pass once answered (`eq_ground_take`), from word `EQ_H`: 1 (it is in),
//! u's two ends, the lowest and the highest height, three words spare, then `EQ_HU` x `EQ_HV` heights over the target's
//! level, a row a v. Until it is in the pass takes the land as level. Keep `EQ_H`, `EQ_HU`, `EQ_HV`, `EQ_HALF_V` in
//! step with the pass's `EQD_H`, `EQD_HU`, `EQD_HV`, `EQD_HALF_V` (`eq_ground_in_step`).
use super::earthquake::{EQ_CAP, EqPlates};
use super::{Act, Plan};
use std::cell::RefCell;

pub(crate) const EQ_H: usize = 512;
pub(crate) const EQ_HU: usize = 64;
pub(crate) const EQ_HV: usize = 56;
pub(crate) const EQ_HALF_V: f32 = 250.0;
/// The words before the heights.
const HEAD: usize = 8;
/// A height further than this from the target's level is taken as this far.
const SPAN: f32 = 120.0;
/// Asked again until answered; not after this.
const BY: f32 = 12.0;
/// Until `LIGHT_BY` seconds in the grid is worked out only on a tick whose work so far is under `LIGHT`.
const LIGHT: u64 = 8_000_000;
const LIGHT_BY: f32 = 1.6;

/// u's two ends: the dust's box along the fault (the pass's `U0`, `U1` in `eqd_march`).
fn ends(pl: &EqPlates) -> (f32, f32) {
    let u0 = (EQ_CAP + 1.07) * pl.reach + 24.0;
    (-u0, u0.max(pl.crack_end + 24.0))
}
/// The grid's columns, a row a v.
fn columns(pl: &EqPlates) -> Vec<(i32, i32)> {
    let (lo, hi) = ends(pl);
    (0..EQ_HV)
        .flat_map(|j| {
            (0..EQ_HU).map(move |i| {
                let u = lo + (hi - lo) * i as f32 / (EQ_HU - 1) as f32;
                let v = -EQ_HALF_V + 2.0 * EQ_HALF_V * j as f32 / (EQ_HV - 1) as f32;
                let w = pl.world_of([u, v]);
                (w[0].floor() as i32, w[1].floor() as i32)
            })
        })
        .collect()
}
/// The grid as the pass takes it: what the world did not answer the mean of what it did, a trunk or a pillar caught on
/// a point put down to the land round it (each point the median of itself and its eight neighbours).
fn smooth(raw: &[Option<f32>]) -> Vec<f32> {
    let (sum, n) = raw.iter().flatten().fold((0.0f32, 0u32), |(s, n), h| (s + h, n + 1));
    let mean = if n > 0 { sum / n as f32 } else { 0.0 };
    let at = |i: usize, j: usize| raw[j * EQ_HU + i].unwrap_or(mean).clamp(-SPAN, SPAN);
    let mut out = Vec::with_capacity(raw.len());
    for j in 0..EQ_HV {
        for i in 0..EQ_HU {
            let mut near = [0.0f32; 9];
            let mut k = 0;
            for b in j.saturating_sub(1)..=(j + 1).min(EQ_HV - 1) {
                for a in i.saturating_sub(1)..=(i + 1).min(EQ_HU - 1) {
                    near[k] = at(a, b);
                    k += 1;
                }
            }
            let near = &mut near[..k];
            near.sort_by(f32::total_cmp);
            out.push(near[k / 2]);
        }
    }
    out
}
/// The pass's words from `EQ_H`.
fn words(pl: &EqPlates, raw: &[Option<f32>]) -> Vec<u32> {
    words_of(pl, &smooth(raw))
}
/// The same, of the grid already smoothed.
fn words_of(pl: &EqPlates, h: &[f32]) -> Vec<u32> {
    let (lo, hi) = ends(pl);
    let (min, max) = h.iter().fold((f32::MAX, f32::MIN), |(a, b), &v| (a.min(v), b.max(v)));
    let mut w = vec![1.0, lo, hi, min, max, 0.0, 0.0, 0.0];
    debug_assert_eq!(w.len(), HEAD);
    w.extend_from_slice(h);
    w.iter().map(|v| v.to_bits()).collect()
}

/// The smoothed grid kept once answered, for the walk (eq_ride.rs asks how high over the land a flier is).
struct Kept {
    pl: EqPlates,
    h: Vec<f32>,
}
thread_local! {
    static KEPT: RefCell<Option<Kept>> = const { RefCell::new(None) };
}
/// The land's height at the world's (x, z) as the grid has it (the y of the first air over it, between the grid's
/// points; outside the grid, as at its nearest edge): none until the world has answered.
pub fn eq_ground_height(x: f64, z: f64) -> Option<f64> {
    KEPT.with(|k| {
        let k = k.borrow();
        let k = k.as_ref()?;
        let (pl, f) = (&k.pl, k.pl.fdir);
        let (lo, hi) = ends(pl);
        let p = [(x - f64::from(pl.block[0])) as f32, (z - f64::from(pl.block[2])) as f32];
        let u = p[0] * f[0] + p[1] * f[1] - pl.shift[0] as f32;
        let v = -p[0] * f[1] + p[1] * f[0] - pl.shift[1] as f32;
        let gi = ((u - lo) / (hi - lo) * (EQ_HU - 1) as f32).clamp(0.0, (EQ_HU - 1) as f32);
        let gj = ((v + EQ_HALF_V) / (2.0 * EQ_HALF_V) * (EQ_HV - 1) as f32).clamp(0.0, (EQ_HV - 1) as f32);
        let (i, j) = ((gi as usize).min(EQ_HU - 2), (gj as usize).min(EQ_HV - 2));
        let (a, b) = (gi - i as f32, gj - j as f32);
        let at = |i: usize, j: usize| k.h[j * EQ_HU + i];
        let h = (at(i, j) * (1.0 - a) + at(i + 1, j) * a) * (1.0 - b) + (at(i, j + 1) * (1.0 - a) + at(i + 1, j + 1) * a) * b;
        Some(f64::from(h) + f64::from(pl.block[1] + 1))
    })
}
/// In the tests: the grid of a land whose height over the target's level at the world's (x, z) is `f`; none: no grid.
#[cfg(test)]
pub fn eq_ground_set_test(land: Option<(&EqPlates, &dyn Fn(f64, f64) -> f32)>) {
    let kept = land.map(|(pl, f)| {
        let raw: Vec<Option<f32>> = columns(pl).iter().map(|&(x, z)| Some(f(f64::from(x) + 0.5, f64::from(z) + 0.5))).collect();
        Kept { pl: *pl, h: smooth(&raw) }
    });
    KEPT.with(|k| *k.borrow_mut() = kept);
}

/// The pass's words from `EQ_H` for a land whose height over the target's level at the world's (x, z) is `f` (the
/// preview's hills: strike/earthquake.rs's `eq_write_table`).
#[cfg(test)]
pub(super) fn eq_ground_words(pl: &EqPlates, f: impl Fn(f64, f64) -> f32) -> Vec<u32> {
    let raw: Vec<Option<f32>> = columns(pl).iter().map(|&(x, z)| Some(f(f64::from(x) + 0.5, f64::from(z) + 0.5))).collect();
    words(pl, &raw)
}

/// What waits for the world's answer: the query, its columns, the plates.
struct Wait {
    tag: u32,
    cols: Vec<(i32, i32)>,
    pl: EqPlates,
}
thread_local! {
    static WAIT: RefCell<Option<Wait>> = const { RefCell::new(None) };
}

/// Ask the grid of the world as the strike fires. No stage of the plan waits for the answer (a stage takes a tick of
/// its own, and the land's work has none to spare): lib.rs asks `eq_ground_take` each tick of the strike.
pub(super) fn eq_ground(p: &mut Plan, pl: &EqPlates) {
    let cols = columns(pl);
    let tag = crate::ground::new_tag();
    p.ev.push((0.1, Act::Survey { tag, columns: cols.clone() }));
    WAIT.with(|w| *w.borrow_mut() = Some(Wait { tag, cols, pl: *pl }));
    KEPT.with(|k| *k.borrow_mut() = None);
}
/// The grid's words and where they go, once the world has answered (once: nothing after); given up `BY` seconds in.
pub fn eq_ground_take(now: f32) -> Option<(u32, Vec<u32>)> {
    WAIT.with(|w| {
        let mut w = w.borrow_mut();
        let wait = w.as_ref()?;
        if !crate::ground::ready(wait.tag) {
            if now > BY {
                *w = None;
            }
            return None;
        }
        // (not on a tick a heavy stage has taken, in the strike's first seconds: the crack's breath can wait a tick)
        if now < LIGHT_BY && crate::meter::spent() > LIGHT {
            return None;
        }
        let wait = w.take()?;
        crate::meter::spend(700 * wait.cols.len() as u64);
        let gy = wait.pl.block[1] + 1;
        let raw: Vec<Option<f32>> = wait.cols.iter().map(|&(x, z)| crate::ground::at(x, z).map(|g| (g + crate::ground::water(x, z).unwrap_or(0) - gy) as f32)).collect();
        let h = smooth(&raw);
        let words = words_of(&wait.pl, &h);
        KEPT.with(|k| *k.borrow_mut() = Some(Kept { pl: wait.pl, h }));
        Some((EQ_H as u32, words))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::{Target, eq_plates};

    fn plates() -> EqPlates {
        let t = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        eq_plates(&t, [10.5, 66.0, 150.0], 37.0, true)
    }

    #[test]
    fn eq_ground_in_step() {
        let pass = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/shaders/earthquake_dust.wgsl")).unwrap();
        for (name, v) in [("EQD_H", EQ_H), ("EQD_HU", EQ_HU), ("EQD_HV", EQ_HV), ("EQD_HEAD", HEAD)] {
            assert!(pass.contains(&format!("const {name}: u32 = {v}u;")), "{name}");
        }
        assert!(pass.contains(&format!("const EQD_HALF_V: f32 = {EQ_HALF_V:.1};")), "EQD_HALF_V");
        // (past the plates' words: strike/eq_fx.rs)
        assert!(super::super::eq_fx::EQ_FX + super::super::eq_fx::EQ_FX_STRIDE * crate::strike::EQ_PLATES <= EQ_H);
    }

    /// The grid's columns are where the pass looks them up: a point's (u, v) in the fault's frame, worked out as the
    /// pass does from its place over the target block's corner, lands on its own grid node.
    #[test]
    fn eq_ground_columns_are_where_the_pass_reads_them() {
        let pl = plates();
        let cols = columns(&pl);
        assert_eq!(cols.len(), EQ_HU * EQ_HV);
        let (lo, hi) = ends(&pl);
        let f = pl.fdir;
        for (n, &(x, z)) in cols.iter().enumerate() {
            let (i, j) = (n % EQ_HU, n / EQ_HU);
            // (the pass: P over the target block's corner; u, v by the fault's direction, less the shift)
            let p = [(x - pl.block[0]) as f32 + 0.5, (z - pl.block[2]) as f32 + 0.5];
            let u = p[0] * f[0] + p[1] * f[1] - pl.shift[0] as f32;
            let v = -p[0] * f[1] + p[1] * f[0] - pl.shift[1] as f32;
            let gi = (u - lo) / (hi - lo) * (EQ_HU - 1) as f32;
            let gj = (v + EQ_HALF_V) / (2.0 * EQ_HALF_V) * (EQ_HV - 1) as f32;
            assert!((gi - i as f32).abs() < 0.12 && (gj - j as f32).abs() < 0.12, "node {i} {j} read at {gi} {gj}");
        }
    }

    /// A trunk on one point is put down to the land round it; a slope is kept; what the world did not answer is the
    /// mean of what it did.
    #[test]
    fn eq_ground_smooths_a_trunk_and_keeps_a_slope() {
        let mut raw: Vec<Option<f32>> = (0..EQ_HU * EQ_HV).map(|n| Some((n % EQ_HU) as f32 * 0.5)).collect();
        let spike = 20 * EQ_HU + 30;
        raw[spike] = Some(15.0 + 7.0);
        raw[5] = None;
        let h = smooth(&raw);
        assert!((h[spike] - 15.0).abs() < 0.51, "{}", h[spike]);
        assert!((h[10 * EQ_HU + 40] - 20.0).abs() < 0.01);
        let w = words(&plates(), &raw);
        assert_eq!(w.len(), HEAD + EQ_HU * EQ_HV);
        assert_eq!(f32::from_bits(w[0]), 1.0);
        assert!(f32::from_bits(w[3]) <= 0.5 && f32::from_bits(w[4]) > 30.0);
        let none = smooth(&vec![None; EQ_HU * EQ_HV]);
        assert!(none.iter().all(|&v| v == 0.0));
    }
}
