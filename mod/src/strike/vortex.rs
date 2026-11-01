//! Vortices: the funnels a storm lets down onto the land, as reusable pieces. The Supercell drops a few thin landspouts
//! out of its wall cloud (storm.rs); a full tornado strike is meant to be built from the same parts, scaled up.
//!
//! - `Funnel` and `wander`: a funnel's life (it comes down out of the cloud over VX_DOWN seconds, touches the land,
//!   wanders across it, lifts back up) and its track, a smooth random path sampled every VX_DT, deterministic per strike.
//! - `vx_words`: what the pass reads of a funnel (its times, its touch radius and its track, with the ground under it),
//!   VX_W words each: shaders/supercell.wgsl's vortex section (`vx_*`) draws the funnel from them. Keep VX_* in step.
//! - `scour`: the light terrain along its track, a stage a stretch of it: the grass and small plants stripped, the
//!   leaves torn off the trees it passes through, the grass scoured to dirt, a few blocks thrown up and out. No digging.
//! - `roar`: its roar played where it is, again every second as it moves, so the sound follows it.
//!
//! A full tornado: the same `Funnel` with a touch radius of 30-80 and a slower, longer wander (a minute or more, the
//! keep-in radius wider); `scour` taking more (logs felled, the top block torn up in patches, many more thrown); the
//! pass's `vx_radius` scaled with the touch radius and its debris cloud with it; the roar louder and further heard.
use super::{Act, Blocks, Plan, TIDY_FLOWERS, TIDY_LOOSE, mh, vnoise};
use std::f64::consts::PI;

/// Seconds between a funnel's track samples, the most samples a funnel has, and the pass's words for one.
pub(super) const VX_DT: f64 = 0.5;
pub(super) const VX_S: usize = 48;
pub(super) const VX_W: usize = 4 + 3 * VX_S;
/// Seconds a funnel takes to come down out of the cloud to the land, and to lift back off it.
pub(super) const VX_DOWN: f64 = 3.5;
/// Seconds before it is gone that it lifts off the land (it ropes out over the 4 s before: supercell.wgsl's VX_ROPE).
pub(super) const VX_LIFT: f64 = 1.6;

#[derive(Clone, Debug)]
pub(super) struct Funnel {
    /// When it starts down out of the cloud, and when it is gone back up into it.
    pub t0: f64,
    pub t1: f64,
    /// Its foot every VX_DT from t0, off the storm's middle (x, z).
    pub path: Vec<[f64; 2]>,
    /// How far round its foot it scours the land while it touches.
    pub touch_r: f64,
}

impl Funnel {
    /// Where its foot is at `t` (off the storm's middle).
    pub fn at(&self, t: f64) -> [f64; 2] {
        let u = ((t - self.t0) / VX_DT).clamp(0.0, (self.path.len() - 1) as f64);
        let i = (u.floor() as usize).min(self.path.len().saturating_sub(2));
        let f = u - i as f64;
        let (a, b) = (self.path[i], self.path[(i + 1).min(self.path.len() - 1)]);
        [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]
    }
    /// How much it is on the land at `t`: 0 aloft (coming down or lifting), 1 touching.
    pub fn touch(&self, t: f64) -> f64 {
        let s = |a: f64, b: f64, x: f64| {
            let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
            u * u * (3.0 - 2.0 * u)
        };
        s(self.t0 + 0.8 * VX_DOWN, self.t0 + VX_DOWN, t) * (1.0 - s(self.t1 - VX_LIFT - 0.2, self.t1 - VX_LIFT + 0.4, t))
    }
}

/// A smooth random wander for funnel `k` of `seed`: from `start` (off the middle), heading `h0` (radians round from +x
/// towards +z), at about `speed` blocks a second, turning slowly back and forth; drawn back in towards the middle once it
/// is past `keep` blocks out, so it stays under its cloud.
pub(super) fn wander(seed: u32, k: u32, start: [f64; 2], h0: f64, speed: f64, t0: f64, t1: f64, keep: f64, touch_r: f64) -> Funnel {
    let n = (((t1 - t0) / VX_DT).ceil() as usize + 1).min(VX_S);
    let r = |j: u32| mh(k * 31 + j, seed, 0x7a11);
    let (w1, w2) = (0.25 + 0.2 * r(1), 0.6 + 0.4 * r(2));
    let (p1, p2) = (2.0 * PI * r(3), 2.0 * PI * r(4));
    let (a1, a2) = (0.9 + 0.5 * r(5), 0.35 * r(6));
    let mut p = start;
    let mut path = Vec::with_capacity(n);
    for i in 0..n {
        path.push(p);
        let t = i as f64 * VX_DT;
        let mut h = h0 + a1 * (w1 * t + p1).sin() + a2 * (w2 * t + p2).sin();
        // (past `keep`, steered back in: towards the middle, more the further out)
        let rr = p[0].hypot(p[1]);
        if rr > keep {
            let home = (-p[1]).atan2(-p[0]);
            let pull = ((rr - keep) / 30.0).min(1.0);
            let d = (home - h + PI).rem_euclid(2.0 * PI) - PI;
            h += d * pull;
        }
        let v = speed * (1.0 + 0.3 * (0.7 * t + p2).sin());
        p = [p[0] + h.cos() * v * VX_DT, p[1] + h.sin() * v * VX_DT];
    }
    Funnel { t0, t1: t0 + (n - 1) as f64 * VX_DT, path, touch_r }
}

/// Where the land is asked round each sample of a track (`ground_track`): the sample's own column and eight round it,
/// three and four blocks out.
pub(super) const VX_PROBE: [(i32, i32); 9] = [(0, 0), (3, 0), (-3, 0), (0, 3), (0, -3), (3, 3), (-3, -3), (3, -3), (-3, 3)];
/// The land under a funnel's track, as its foot glides over it: at each sample the lowest of the land round it
/// (`ground`: the world's ground, which counts a tree's trunk), so it never climbs a tree or a wall it passes, then
/// smoothed along the track (twice over two seconds or so) so it never hops on a step of the land. None where nothing
/// round a sample is known: the known ones round it carry over, 0 if there are none.
pub(super) fn ground_track(path: &[[f64; 2]], ground: impl Fn(f64, f64) -> Option<f64>) -> Vec<f64> {
    crate::meter::spend(2_000 * path.len() as u64);
    let raw: Vec<Option<f64>> = path
        .iter()
        .map(|p| VX_PROBE.iter().filter_map(|&(dx, dz)| ground(p[0] + f64::from(dx), p[1] + f64::from(dz))).reduce(f64::min))
        .collect();
    let known: Vec<(usize, f64)> = raw.iter().enumerate().filter_map(|(i, v)| v.map(|v| (i, v))).collect();
    let mut h: Vec<f64> = (0..path.len())
        .map(|i| raw[i].unwrap_or_else(|| known.iter().min_by_key(|(j, _)| j.abs_diff(i)).map_or(0.0, |k| k.1)))
        .collect();
    for _ in 0..2 {
        h = (0..h.len())
            .map(|i| {
                let (a, b) = (i.saturating_sub(2), (i + 2).min(h.len() - 1));
                h[a..=b].iter().sum::<f64>() / (b - a + 1) as f64
            })
            .collect();
    }
    h
}

/// The pass's words for a funnel (VX_W of them): t0, t1, how many samples, its touch radius, then each sample's x, z
/// (off the middle) and the land's height there over the middle's (`dy`, from `ground_track`: one a sample).
pub(super) fn vx_words(f: &Funnel, dy: &[f64]) -> Vec<u32> {
    let mut w = vec![0u32; VX_W];
    w[0] = (f.t0 as f32).to_bits();
    w[1] = (f.t1 as f32).to_bits();
    w[2] = (f.path.len() as f32).to_bits();
    w[3] = (f.touch_r as f32).to_bits();
    for (i, p) in f.path.iter().enumerate() {
        w[4 + 3 * i] = (p[0] as f32).to_bits();
        w[5 + 3 * i] = (p[1] as f32).to_bits();
        w[6 + 3 * i] = (dy.get(i).copied().unwrap_or(0.0) as f32).to_bits();
    }
    w
}

/// What the funnel scours where it touches, over its track's samples k0..k1: each column within its touch radius (a
/// little ragged) once, when the funnel first reaches it: the loose plants and flowers gone, the leaves over it torn off
/// up to 24 high, the grass scoured to dirt in streaks; and now and then a block of the ground thrown up and out, spun
/// round it. `seen` holds the columns already scoured (the track crosses itself). (cx, cz): the storm's middle.
pub(super) fn scour(q: &mut Plan, f: &Funnel, k0: usize, k1: usize, cx: i32, cz: i32, seed: u32, seen: &mut crate::ground::FxSet<(i32, i32)>) {
    let mut b = Blocks::default();
    let mut when: crate::ground::FxMap<(i32, i32), f32> = Default::default();
    let r = f.touch_r;
    let ri = r.ceil() as i32 + 1;
    for k in k0..k1.min(f.path.len()) {
        let t = f.t0 + k as f64 * VX_DT;
        if f.touch(t) < 0.5 {
            continue;
        }
        let [px, pz] = f.path[k];
        let (fx, fz) = (f64::from(cx) + 0.5 + px, f64::from(cz) + 0.5 + pz);
        let (ix, iz) = (fx.floor() as i32, fz.floor() as i32);
        for dz in -ri..=ri {
            for dx in -ri..=ri {
                let (x, z) = (ix + dx, iz + dz);
                let d = (f64::from(x) + 0.5 - fx).hypot(f64::from(z) + 0.5 - fz);
                crate::meter::spend(40);
                if d > r * (0.8 + 0.35 * vnoise(f64::from(x), f64::from(z), 3.0, seed ^ 0x51)) || !seen.insert((x, z)) {
                    continue;
                }
                when.insert((x, z), t as f32);
                b.put(x, z, 0, 3, "minecraft:air", Some(TIDY_LOOSE), true);
                b.put(x, z, 0, 2, "minecraft:air", Some(TIDY_FLOWERS), true);
                b.put(x, z, 0, 24, "minecraft:air", Some("#minecraft:leaves"), true);
                if mh((x as u32).wrapping_mul(73_856_093) ^ (z as u32).wrapping_mul(19_349_663), seed, 0x5c) < 0.55 + 0.4 * (1.0 - d / r) {
                    let to = if mh(x as u32 ^ (z as u32).rotate_left(13), seed, 0x5d) < 0.6 { "minecraft:coarse_dirt" } else { "minecraft:dirt" };
                    b.put(x, z, -1, -1, to, Some("minecraft:grass_block"), true);
                }
            }
        }
        // (a block of the ground thrown up and out every so often, spun round the funnel: falling blocks, which come
        // down a few seconds later off the track, breaking up where they land)
        if k % 3 == 0 {
            let a = 2.0 * PI * mh(k as u32, seed, 0x5e);
            let (ox, oz) = (a.cos() * r * 0.8, a.sin() * r * 0.8);
            let (vx, vz) = (-a.sin() * 0.55 + a.cos() * 0.25, a.cos() * 0.55 + a.sin() * 0.25);
            let vy = 0.7 + 0.4 * mh(k as u32, seed, 0x5f);
            let blk = ["minecraft:dirt", "minecraft:coarse_dirt", "minecraft:oak_leaves", "minecraft:gravel"][(mh(k as u32, seed, 0x60) * 4.0) as usize % 4];
            let (x, z) = ((fx + ox).floor() as i32, (fz + oz).floor() as i32);
            q.ev.push((
                t as f32,
                Act::Cmd(format!(
                    "execute positioned {x} 0 {z} positioned over motion_blocking_no_leaves run summon minecraft:falling_block ~ ~0.5 ~ {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b,CancelDrop:1b,Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"
                )),
            ));
        }
    }
    for (t, e) in b.split_by(|x, z| when.get(&(x, z)).copied().unwrap_or(0.0)) {
        q.ev.push((t, Act::Blocks(Box::new(e))));
    }
}

/// The funnel's roar, played where it is every second of its life (each a few seconds long, faded in and out, so they
/// overlap into one that moves with it): quieter while it is aloft. `track`: the land under its track over `c`'s
/// (`ground_track`).
pub(super) fn roar(q: &mut Plan, f: &Funnel, event: &str, c: [f64; 3], track: &[f64]) {
    let mut t = f.t0;
    while t < f.t1 - 0.5 {
        let p = f.at(t + 0.8);
        let k = (((t + 0.8 - f.t0) / VX_DT).round() as usize).min(track.len().saturating_sub(1));
        let at = [c[0] + p[0], c[1] + track.get(k).copied().unwrap_or(0.0) + 6.0, c[2] + p[1]];
        let v = 0.45 + 0.55 * f.touch(t + 0.8);
        q.ev.push((t as f32, Act::Sound { event: event.to_string(), at: Some(at), volume: v as f32, pitch: 1.0 }));
        t += 1.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_funnel_wanders_smoothly_and_stays_under_its_cloud() {
        for k in 0..4 {
            let f = wander(37, k, [40.0, -10.0], 1.2, 5.0, 14.0, 30.0, 95.0, 4.0);
            assert!(f.path.len() > 20 && f.path.len() <= VX_S);
            for w in f.path.windows(2) {
                let step = (w[1][0] - w[0][0]).hypot(w[1][1] - w[0][1]);
                assert!(step < 5.0 * 1.31 * VX_DT + 1e-6, "{step}");
            }
            assert!(f.path.iter().all(|p| p[0].hypot(p[1]) < 140.0), "{:?}", f.path);
            assert_eq!(f.touch(f.t0), 0.0);
            assert!(f.touch(0.5 * (f.t0 + f.t1)) > 0.99);
            assert!(f.touch(f.t1) < 1e-9);
        }
    }

    #[test]
    fn a_funnel_glides_over_the_land_under_the_trees() {
        let f = wander(37, 0, [40.0, -10.0], 1.2, 5.0, 14.0, 30.0, 95.0, 4.0);
        // (flat land at 0 with trunks 8 high every few blocks, and a step of 4 half way)
        let ground = |x: f64, z: f64| -> Option<f64> {
            let step = if x > 45.0 { 4.0 } else { 0.0 };
            let trunk = ((x.floor() as i64 * 7 + z.floor() as i64 * 13) % 9) == 0;
            Some(step + if trunk { 8.0 } else { 0.0 })
        };
        let h = ground_track(&f.path, ground);
        assert_eq!(h.len(), f.path.len());
        for w in h.windows(2) {
            assert!((w[1] - w[0]).abs() < 1.5, "a hop: {w:?}");
        }
        assert!(h.iter().all(|&v| v < 4.5), "it climbed a tree: {h:?}");
    }
}
