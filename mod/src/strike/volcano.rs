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
use std::cell::RefCell;
use std::rc::Rc;

/// The story's times (strike seconds). Keep in step with shaders/volcano.wgsl.
pub(super) const VC_HIT: f32 = 2.0;
pub(super) const VC_CRACK: f32 = 6.0;
pub(super) const VC_HUSH: f32 = 17.0;
pub(super) const VC_ERUPT: f32 = 18.0;
pub(super) const VC_BOMBS: f32 = 19.0;
pub(super) const VC_BOMBS_END: f32 = 36.0;
pub(super) const VC_LIGHT: f32 = 26.0;
pub(super) const VC_COLLAPSE: f32 = 50.0;
/// The ring of vents' radius.
pub(super) const VC_RING: f64 = 280.0;
/// The vent is at least this far in front of the player, along the way they aimed.
const VC_NEAR: f64 = 500.0;
/// The wall's knockback as it reaches the player: blocks a tick out and up, none past VC_KNOCK_REACH.
const VC_KNOCK_OUT: f32 = 0.7;
const VC_KNOCK_UP: f32 = 0.4;
const VC_KNOCK_REACH: f32 = 1500.0;
/// The speed of sound, blocks a second (the eruption's sound and its pressure ring).
const VC_V: f64 = 343.0;

/// The table: the bombs from VC_BOMB, VC_BW words each (when thrown, from x y z, its velocity, when it lands), sorted by
/// when they are thrown; the land from VC_HF.
pub(super) const VC_BOMB: usize = 16;
pub(super) const VC_BW: usize = 8;
pub(super) const VC_BOMBS_N: usize = 64;
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
/// The land's height round the vent as the world last gave it (from the vent's ground), for the land's work.
#[derive(Default)]
pub(super) struct Hf {
    n: usize,
    reach: f64,
    h: Vec<f32>,
}
impl Hf {
    fn set(&mut self, heights: &[Option<f64>], reach: f64) {
        let (sum, cnt) = heights.iter().flatten().fold((0.0, 0.0), |(s, c), &h| (s + h, c + 1.0));
        let guess = if cnt > 0.0 { sum / cnt } else { 0.0 };
        self.n = VC_HN;
        self.reach = reach;
        self.h = heights.iter().map(|h| h.unwrap_or(guess) as f32).collect();
    }
    /// The height at (x, z) from the vent, smoothly between the cells.
    pub(super) fn at(&self, x: f64, z: f64) -> f64 {
        if self.n < 2 {
            return 0.0;
        }
        let step = 2.0 * self.reach / (self.n - 1) as f64;
        let fi = ((x + self.reach) / step).clamp(0.0, (self.n - 1) as f64 - 0.001);
        let fk = ((z + self.reach) / step).clamp(0.0, (self.n - 1) as f64 - 0.001);
        let (i, k) = (fi as usize, fk as usize);
        let (u, v) = (fi - i as f64, fk - k as f64);
        let c = k * self.n + i;
        let h = |j: usize| f64::from(self.h[j]);
        (h(c) * (1.0 - u) + h(c + 1) * u) * (1.0 - v) + (h(c + self.n) * (1.0 - u) + h(c + self.n + 1) * u) * v
    }
    /// The highest the land's cells stand round (x, z).
    pub(super) fn max_near(&self, x: f64, z: f64) -> f64 {
        if self.n < 2 {
            return 0.0;
        }
        let step = 2.0 * self.reach / (self.n - 1) as f64;
        let i = (((x + self.reach) / step) as isize).clamp(1, self.n as isize - 3) as usize;
        let k = (((z + self.reach) / step) as isize).clamp(1, self.n as isize - 3) as usize;
        let mut m = f64::MIN;
        for j in k - 1..=k + 2 {
            for l in i - 1..=i + 2 {
                m = m.max(f64::from(self.h[j * self.n + l]));
            }
        }
        m
    }
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

/// The lava bombs (from the vent, in order of when they are thrown): when, from where, how fast; and when each meets the
/// land (`land`: x, z to its height).
pub(super) struct Bomb {
    pub t0: f64,
    pub p0: [f64; 3],
    pub v: [f64; 3],
    pub tl: f64,
}
pub(super) fn vc_bombs(seed: f32, land: &dyn Fn(f64, f64) -> f64) -> Vec<Bomb> {
    let s = seed as u32;
    (0..VC_BOMBS_N)
        .map(|i| {
            let k = i as u32;
            let u = (i as f64 + 0.8 * mh(k, s, 0xb1)) / VC_BOMBS_N as f64;
            let t0 = f64::from(VC_BOMBS) + f64::from(VC_BOMBS_END - VC_BOMBS) * u.powf(0.8);
            let th = 2.0 * PI * mh(k, s, 0xb2);
            let r0 = VC_RING + 50.0 * (mh(k, s, 0xb3) - 0.5);
            let p0 = [r0 * th.cos(), 40.0 + 80.0 * mh(k, s, 0xb4), r0 * th.sin()];
            // (up hard, out at most a little: arcs a few hundred blocks out, the big throws a kilometre)
            let vo = 16.0 + 62.0 * mh(k, s, 0xb5).powf(1.6);
            let vy = 120.0 + 140.0 * mh(k, s, 0xb6);
            let sway = th + 0.5 * (mh(k, s, 0xb7) - 0.5);
            let v = [vo * sway.cos(), vy, vo * sway.sin()];
            // (down its fall, a step at a time, to where it meets the land)
            let mut tau = vy / VC_G;
            let at = |tau: f64| [p0[0] + v[0] * tau, p0[1] + v[1] * tau - 0.5 * VC_G * tau * tau, p0[2] + v[2] * tau];
            for _ in 0..200 {
                let p = at(tau);
                if p[1] <= land(p[0], p[2]) {
                    break;
                }
                tau += 0.1;
            }
            // (the last of the way worked out)
            let p = at(tau);
            let vf = (VC_G * tau - vy).max(1.0);
            tau -= (land(p[0], p[2]) - p[1]) / vf;
            Bomb { t0, p0, v, tl: t0 + tau }
        })
        .collect()
}
/// The bombs' words (from VC_BOMB).
fn vc_bomb_words(bombs: &[Bomb]) -> Vec<u32> {
    let mut w = Vec::with_capacity(bombs.len() * VC_BW);
    for b in bombs {
        let f = [b.t0, b.p0[0], b.p0[1], b.p0[2], b.v[0], b.v[1], b.v[2], b.tl];
        w.extend(f.iter().map(|x| (*x as f32).to_bits()));
    }
    w
}

/// What the pass reads (see VC_BOMB): worked out on the tick after it fires, the bombs over flat land until the land's
/// height is in.
pub(super) fn vc_table(seed: f32, _me: [f64; 3]) -> Vec<u32> {
    let mut w = vec![0u32; VC_HF];
    w[0] = 1f32.to_bits();
    w[1] = (VC_BOMBS_N as f32).to_bits();
    let b = vc_bomb_words(&vc_bombs(seed, &|_, _| 0.0));
    w[VC_BOMB..VC_BOMB + b.len()].copy_from_slice(&b);
    w
}

/// When the wall of ash reaches `dist` blocks from the vent.
fn vc_wall_at(dist: f64) -> f32 {
    super::vc_land::vc_due(dist.max(280.0))
}

pub(super) fn volcano_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let rel = [me[0] - cx, me[1] - gy, me[2] - cz];
    let dist = rel[0].hypot(rel[2]);
    let (late, sdist) = sound_from([cx, gy, cz], me);
    let hf: Rc<RefCell<Hf>> = Default::default();

    // the pass's table, on the tick after it fires
    {
        let s = shader_seed;
        p.later(0.05, move |q| q.ev.push((0.05, Act::Table(vc_table(s, rel)))));
    }
    // (and the land's shape round it, asked as it starts and again once the chunks forceloaded have come in; the bombs'
    // landings worked out on it before the first is thrown)
    {
        let reach = vc_hf_reach(dist);
        let columns = Rc::new(vc_hf_columns(bx, bz, reach));
        for (t, again) in [(0.1, false), (9.0, true)] {
            if again && !terrain {
                continue;
            }
            let tag = crate::ground::new_tag();
            let (cols, c2, h2) = (columns.clone(), columns.clone(), hf.clone());
            p.later(t, move |q| q.ev.push((t, Act::Survey { tag, columns: cols.to_vec() })));
            p.later(t + 0.3, move |q| vc_hf_step(q, tag, c2, reach, by + 1, t + 0.3, shader_seed, h2));
        }
    }

    // ---- the mount: strike/vc_mount.rs, drawn whatever the terrain setting ----------------------------------------------
    super::vc_mount::vm_plan(&mut p, shader_seed as u32, hf.clone());

    // ---- the sounds: strike/vc_sound.rs ----------------------------------------------------------------------------------
    {
        let bombs: Vec<(f32, f64, f64)> = vc_bombs(shader_seed, &|_, _| 0.0)
            .iter()
            .map(|b| {
                let c = b.tl - b.t0;
                (b.tl as f32, b.p0[0] + b.v[0] * c, b.p0[2] + b.v[2] * c)
            })
            .collect();
        vc_sound::vc_sounds(&mut p, shader_seed as u32, [cx, gy, cz], me, bombs);
    }

    // ---- the ground shaking: a tremor building from the hit, faster and harder, the eruption's jolt late by the distance,
    // the column's roar in the ground, the collapse, the wall arriving -------------------------------------------------
    let fo = (1.6 / (1.0 + dist / 500.0)).clamp(0.25, 1.0) as f32;
    let mut ts = VC_HIT + 0.5;
    // (nothing at the hush: one held breath before it goes)
    while ts < VC_HUSH {
        let u = (ts - VC_HIT) / (VC_HUSH - VC_HIT);
        p.shake(ts, (0.05 + 0.4 * u * u) * fo, 0.5 + 0.5 * u);
        ts += 0.9 - 0.6 * u;
    }
    let arrive = VC_ERUPT + late;
    p.shake(arrive, fo, 2.5);
    let mut ts = arrive + 1.5;
    while ts < VC_COLLAPSE {
        let s = p.rng.uniform(0.1, 0.22) as f32 * fo;
        p.shake(ts, s, 1.2);
        ts += p.rng.uniform(0.8, 1.6) as f32;
    }
    p.shake(VC_COLLAPSE + late, 0.8 * fo, 3.5);
    let wall = vc_wall_at(dist);
    if dist < 1700.0 {
        p.shake(wall, 1.0, 2.0);
        let mut ts = wall + 1.0;
        while ts < wall + 10.0 {
            p.shake(ts, 0.3, 1.0);
            ts += 0.7;
        }
        p.ev.push((wall, Act::Shove { from: [cx, gy, cz], out: VC_KNOCK_OUT, up: VC_KNOCK_UP, reach: VC_KNOCK_REACH }));
    }
    let _ = sdist;

    if terrain {
        super::vc_land::vc_land_plan(&mut p, laser, shader_seed as u32, hf.clone());
        // (the bombs' craters, each as it lands, wherever the world has land loaded there)
        let h3 = hf.clone();
        let s = shader_seed;
        p.later(VC_BOMBS - 0.5, move |q| {
            let hf = h3.borrow();
            for (i, b) in vc_bombs(s, &|x, z| hf.at(x, z)).iter().enumerate() {
                let x = (cx + b.p0[0] + b.v[0] * (b.tl - b.t0)).floor() as i32;
                let z = (cz + b.p0[2] + b.v[2] * (b.tl - b.t0)).floor() as i32;
                let r = 2 + i32::from(mh(i as u32, s as u32, 0xb8) > 0.5) + i32::from(mh(i as u32, s as u32, 0xb9) > 0.8);
                q.ev.push((b.tl as f32, Act::Blocks(Box::new(super::vc_land::vc_bomb_crater(x, z, r, s as u32)))));
            }
        });
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// The land's height, once the world has answered (asking again a little later until it has, while there is time): sent
/// to the pass with the bombs' landings worked out on it, kept for the land's work.
#[allow(clippy::too_many_arguments)]
fn vc_hf_step(q: &mut Plan, tag: u32, columns: Rc<Vec<(i32, i32)>>, reach: f64, gy: i32, at_t: f32, seed: f32, hf: Rc<RefCell<Hf>>) {
    if !crate::ground::ready(tag) {
        if at_t < VC_ERUPT {
            q.later(at_t + 0.2, move |q| vc_hf_step(q, tag, columns, reach, gy, at_t + 0.2, seed, hf));
        }
        return;
    }
    crate::meter::spend(800 * columns.len() as u64);
    let heights: Vec<Option<f64>> = columns
        .iter()
        .map(|&(x, z)| crate::ground::at(x, z).map(|g| f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy)))
        .collect();
    let mut h = hf.borrow_mut();
    h.set(&heights, reach);
    q.ev.push((at_t, Act::Words { index: VC_HF as u32, words: vc_hf_pack(&heights, reach) }));
    let hh = &*h;
    q.ev.push((at_t, Act::Words { index: VC_BOMB as u32, words: vc_bomb_words(&vc_bombs(seed, &|x, z| hh.at(x, z))) }));
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
        // (VM_NOLAND=1: the land never read, as far off with the terrain off)
        let noland = std::env::var("VM_NOLAND").is_ok_and(|v| v == "1");
        for (i, words) in super::super::vc_mount::table::all(seed as u32, &|x, z| (!noland).then(|| super::super::vc_mount::table::preview_col(x, z, hills))) {
            if w.len() < i + words.len() {
                w.resize(i + words.len(), 0);
            }
            w[i..i + words.len()].copy_from_slice(&words);
        }
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    #[test]
    fn the_vent_keeps_its_distance_from_the_player() {
        assert_eq!(vc_vent([10.0, 64.0, 600.0], [10.0, 64.0, 0.0]), [0.0, 0.0]);
        let d = vc_vent([0.0, 64.0, 120.0], [0.0, 64.0, 0.0]);
        assert!(d[0].abs() < 1e-6 && (d[1] - 380.0).abs() < 1e-6, "{d:?}");
        let e = vc_vent([3.0, 64.0, 4.0], [0.0, 64.0, 0.0]);
        assert!(((3.0 + e[0]).hypot(4.0 + e[1]) - VC_NEAR).abs() < 1e-6);
    }
    #[test]
    fn its_front_reaches_500_at_about_48_s() {
        let c = 4.0;
        assert!((vc_front(c) - 500.0).abs() < 16.0, "{}", vc_front(c));
        let v0 = vc_front(0.01) - vc_front(0.0);
        assert!((v0 * 100.0 - 60.0).abs() < 1.5, "{v0}");
    }
    #[test]
    fn the_bombs_come_down_on_the_land_in_order_thrown() {
        let bombs = vc_bombs(37.0, &|_, _| 3.0);
        assert_eq!(bombs.len(), VC_BOMBS_N);
        assert!(bombs.windows(2).all(|w| w[0].t0 <= w[1].t0));
        for b in &bombs {
            let s = b.tl - b.t0;
            assert!(s > 5.0 && s < 24.0, "in the air {s} s");
            let y = b.p0[1] + b.v[1] * s - 0.5 * VC_G * s * s;
            assert!((y - 3.0).abs() < 6.0, "lands at {y}");
            let (x, z) = (b.p0[0] + b.v[0] * s, b.p0[2] + b.v[2] * s);
            assert!(x.hypot(z) < 1800.0);
        }
    }
    #[test]
    fn with_the_terrain_off_it_leaves_the_world_alone() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let ev = plan(&crate::lasers::SUPERVOLCANO, &target, false, "minecraft:overworld", 37.0, [10.5, 66.0, 600.0], 0);
        assert!(!ev.iter().any(|e| matches!(e.1, Act::Blocks(_) | Act::Cmd(_) | Act::Spare(_))));
        let on = plan(&crate::lasers::SUPERVOLCANO, &target, true, "minecraft:overworld", 37.0, [10.5, 66.0, 600.0], 0);
        let cmds: Vec<&String> = on.iter().filter_map(|e| if let Act::Cmd(c) = &e.1 { Some(c) } else { None }).collect();
        assert!(cmds.iter().filter(|c| c.starts_with("forceload add")).count() > 40);
        assert!(cmds.iter().filter(|c| c.contains("kill")).all(|c| c.contains("type=!minecraft:player")));
    }
}
