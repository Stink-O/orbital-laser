//! The World Eater's catch: a player the mouth closes over is carried inside the body and spat out.
//! Pure: the per-tick hook (strike/worldeater.rs's `WeHand`) hands the moves to the game (`world.carry-player`, as the
//! Hurricane's and the Tsunami's carries), and the tests play them against a stand-in.
//!
//! Its phases, from `t_close` (the jaws shut: the head coming down on a bite, or up under them on a breach), as a track
//! worked out once (a place a tick, `track`; strike/worldeater.rs builds it from the path):
//! - swallowed (SWALLOW s): drawn from where they stood onto the track.
//! - inside, along the track: on a breach, held on the hole's axis `DEPTH` under its ground (the body pouring up round
//!   them), then carried up it; on a bite (path contract v2), down the dive hole and along the underground run behind
//!   the head (at most `CARRY_V`, never past the head), up the next breach's hole, to SPIT_FROM over its ground.
//! - spat (SPIT_T s, from `t_spit`, the track's end): out along an arc up and away from that hole (`dir`), then let go
//!   with a throw (`world.push-player` while carried), landing some 80 blocks out on the land: never back in the hole.
//!   Non-creative players get Resistance V from the moment they are swallowed (a strike stopped part way lets them fall).
use crate::carry::CarryTick;

/// Seconds to be drawn down into the throat; to be spat along the arc.
pub(super) const SWALLOW: f64 = 1.4;
pub(super) const SPIT_T: f64 = 1.5;
/// How far out (level) and up over the hole's ground the spit's arc ends; the throw they are let go with (blocks a tick,
/// out and up).
pub(super) const SPIT_OUT: f64 = 64.0;
pub(super) const SPIT_UP: f64 = 30.0;
pub(super) const THROW: [f64; 2] = [0.8, 0.35];
/// How far past the hole's reach (its edge at its widest, its funnel) the spit lets them go, at the least.
pub(super) const CLEAR_PAD: f64 = 12.0;
/// Where the spit's arc starts, over the hole's ground; how far inside the mouth they ride up.
pub(super) const SPIT_FROM: f64 = 14.0;
pub(super) const IN_MOUTH: f64 = 8.0;
/// How far under the hole's ground they are held (the loop's neck is 40 under it).
pub(super) const DEPTH: f64 = 26.0;
/// On a breach: how long they are held inside before they are carried up, and how fast (blocks a tick).
pub(super) const BREACH_HOLD: f64 = 2.0;
pub(super) const BREACH_RISE: f64 = 2.5;
/// The fastest it carries them along a run (blocks a second: inside the game's clamp on any axis).
pub(super) const CARRY_V: f64 = 64.0;
/// The most it moves them a tick on any axis (the game's clamp is 4).
const STEP: f64 = 3.9;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum CatchKind {
    Bite,
    Breach,
}

#[derive(Clone, Debug)]
pub(super) struct Catch {
    pub kind: CatchKind,
    /// The hole they are spat out of: its middle (world), its ground's height (the first air over it).
    pub axis: [f64; 3],
    pub t_close: f64,
    /// Where their feet go a tick at a time from `t_close` (world); its last is SPIT_FROM over `axis`.
    pub track: Vec<[f64; 3]>,
    pub t_spit: f64,
    /// The way they are spat (level, unit).
    pub dir: [f64; 2],
    /// Where they were as the jaws shut (world).
    pub start: Option<[f64; 3]>,
    pub done: bool,
    /// Broke free (sneak held: the game's call): let go there and then.
    pub freed: bool,
    pub thrown: Option<(f64, [f64; 3])>,
    /// How far from the hole's middle (level) they must be let go: the hole's reach and CLEAR_PAD. The spit's arc ends
    /// past it; if the land held them back short of it, they are put at the arc's end on the land (`release`).
    pub clear: f64,
    /// The top of the spit's arc (world), once the land along it is known: high enough to clear it (`lift`).
    pub top: Option<f64>,
    /// Carried out through the mouth (a bite's carry, path contract v2): the track runs on to the let-go, out past the
    /// jaws, and they are let go there at this time with this throw (blocks a tick), not spat along an arc.
    pub exit: Option<(f64, [f64; 3])>,
    /// A bite's carry: the eye it follows (the pass draws the throat from it), the path it is on, the origin (world).
    pub eye: Option<(super::we_path::WeEye, super::we_path::WePath, [f64; 3])>,
    asked: [bool; 2],
}

fn ease(x: f64) -> f64 {
    let x = x.clamp(0.0, 1.0);
    x * x * x * (x * (6.0 * x - 15.0) + 10.0)
}

/// A breach's track: held on the axis `depth` under its ground (swaying a little) for SWALLOW + BREACH_HOLD, then carried
/// up it to SPIT_FROM over it.
pub(super) fn breach_track(axis: [f64; 3], depth: f64) -> Vec<[f64; 3]> {
    let hold = ((SWALLOW + BREACH_HOLD) / 0.05).round() as usize;
    let rise = ((depth + SPIT_FROM) / BREACH_RISE).ceil() as usize;
    let mut out = Vec::with_capacity(hold + rise + 1);
    for k in 0..hold {
        let tau = k as f64 * 0.05;
        let sway = ease(tau / 2.0);
        out.push([axis[0] + 1.2 * (0.9 * tau).sin() * sway, axis[1] - depth, axis[2] + 1.2 * (0.7 * tau + 1.3).cos() * sway]);
    }
    for k in 1..=rise {
        let f = k as f64 / rise as f64;
        out.push([axis[0], axis[1] - depth + (depth + SPIT_FROM) * f, axis[2]]);
    }
    out
}

impl Catch {
    pub fn new(kind: CatchKind, axis: [f64; 3], t_close: f64, track: Vec<[f64; 3]>, dir: [f64; 2]) -> Catch {
        let t_spit = t_close + 0.05 * track.len() as f64;
        Catch { kind, axis, t_close, track, t_spit, dir, start: None, done: false, freed: false, thrown: None, clear: SPIT_OUT - 10.0, top: None, exit: None, eye: None, asked: [false; 2] }
    }
    /// When they are let go, thrown.
    pub fn t_free(&self) -> f64 {
        self.exit.map_or(self.t_spit + SPIT_T, |e| e.0)
    }
    /// Where their feet should be at `t`.
    pub fn target(&self, t: f64) -> [f64; 3] {
        if let Some((eye, path, o)) = &self.eye {
            // (where they stood as the jaws shut, the eye's own start, for the blend)
            let mut e = eye.clone();
            if let Some(st) = self.start {
                e.stand = [st[0] - o[0], st[1] - o[1], st[2] - o[2]];
            }
            let p = e.at(path, t.min(e.t_free));
            return [o[0] + p[0], o[1] + p[1], o[2] + p[2]];
        }
        if (t >= self.t_spit && self.exit.is_none()) || self.track.is_empty() {
            let u = ((t - self.t_spit) / SPIT_T).clamp(0.0, 1.0);
            let out = self.spit_out() * u.powf(1.6);
            let top = self.top.unwrap_or(self.axis[1] + SPIT_UP).max(self.axis[1] + SPIT_UP);
            let y = self.axis[1] + SPIT_FROM + (top - self.axis[1] - SPIT_FROM) * (u * std::f64::consts::FRAC_PI_2).sin();
            return [self.axis[0] + self.dir[0] * out, y, self.axis[2] + self.dir[1] * out];
        }
        let tau = (t - self.t_close).max(0.0);
        let k = ((tau / 0.05) as usize).min(self.track.len() - 1);
        let h = self.track[k];
        if tau >= SWALLOW {
            return h;
        }
        let start = self.start.unwrap_or(h);
        // (onto the track quickly across, down a little behind)
        let (a, b) = (ease(tau / (0.7 * SWALLOW)), ease(tau / SWALLOW));
        [start[0] + (h[0] - start[0]) * a, start[1] + (h[1] - start[1]) * b, start[2] + (h[2] - start[2]) * a]
    }
    /// How far out (level) the spit's arc ends: past `clear`.
    pub fn spit_out(&self) -> f64 {
        SPIT_OUT.max(self.clear + 8.0)
    }
    /// Where the spit's arc ends (world).
    pub fn spit_end(&self) -> [f64; 3] {
        if let Some((e, _, o)) = &self.eye
            && let Some(f) = e.flight
        {
            return [o[0] + f[7], o[1] + f[8], o[2] + f[9]];
        }
        if self.exit.is_some() {
            return self.track.last().copied().unwrap_or(self.axis);
        }
        self.target(self.t_free())
    }
    /// Where (level, world) the land along the spit's arc is to be asked: its end and the way to it.
    pub fn arc_columns(&self) -> Vec<(i32, i32)> {
        // (a flight out of the mouth: the land under it, from the tip to the let-go and round where it lands)
        if let Some((e, _, o)) = &self.eye
            && let Some(f) = e.flight
        {
            let mut v = Vec::new();
            for k in 0..=16 {
                let u = f64::from(k) / 16.0;
                let (x, z) = (o[0] + f[1] + (f[7] - f[1]) * u, o[2] + f[3] + (f[9] - f[3]) * u);
                v.push((x.floor() as i32, z.floor() as i32));
            }
            for (dx, dz) in [(4, 0), (-4, 0), (0, 4), (0, -4), (8, 8), (-8, -8), (8, -8), (-8, 8)] {
                v.push(((o[0] + f[7]).floor() as i32 + dx, (o[2] + f[9]).floor() as i32 + dz));
            }
            return v;
        }
        let out = self.spit_out();
        let mut v = Vec::new();
        for k in 4..=20 {
            let r = out * f64::from(k) / 20.0;
            for o in [-1.5, 0.0, 1.5] {
                let (x, z) = (self.axis[0] + self.dir[0] * r - self.dir[1] * o, self.axis[2] + self.dir[1] * r + self.dir[0] * o);
                v.push((x.floor() as i32, z.floor() as i32));
            }
        }
        v
    }
    /// The land along the arc known (its highest first air): the arc's top lifted to clear it by 6.
    pub fn lift(&mut self, highest: f64) {
        self.top = Some((highest + 6.0).max(self.axis[1] + SPIT_UP));
    }
    /// Whether they are inside the body at `t` (the hand darkened, the hunt's other pushes held off).
    pub fn inside(&self, t: f64) -> bool {
        !self.done && t >= self.t_close && t < self.t_spit + 0.4
    }
    /// One tick, `t`, their feet at `feet`; `held`: the game's last answer (false: they broke free).
    pub fn tick(&mut self, t: f64, feet: [f64; 3], held: bool) -> CarryTick {
        let mut out = CarryTick::default();
        if self.done || t < self.t_close {
            return out;
        }
        let asked = self.asked[1];
        self.asked = [false, self.asked[0]];
        if self.start.is_none() {
            self.start = Some(feet);
            // (spared a fall if the strike stops while they are inside; spared the landing)
            out.cmds.push("effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:resistance 40 4 true".into());
        } else if asked && !held {
            self.freed = true;
            self.done = true;
            return out;
        }
        if t >= self.t_free() {
            let v = self.exit.map_or([self.dir[0] * THROW[0], THROW[1], self.dir[1] * THROW[0]], |e| e.1);
            self.done = true;
            self.thrown = Some((t, v));
            // (never let go over the hole: held back short of the arc's end by the land (a carry is a collision move),
            // they are put there, on the land's top, first)
            let end = self.spit_end();
            let off = (feet[0] - self.axis[0]).hypot(feet[2] - self.axis[2]);
            if off < self.clear || (feet[0] - end[0]).hypot(feet[2] - end[2]) > 8.0 {
                out.cmds.push(on_land(end[0], end[2]));
            }
            out.throw = Some([v[0] as f32, v[1] as f32, v[2] as f32]);
            // (Resistance V till well after they land: 15 s and a second for every 10 blocks they are over the hole's
            // ground, so no fall outlasts it)
            let secs = 15 + ((feet[1] - self.axis[1]).max(0.0) / 10.0).ceil() as i32;
            out.cmds.push(format!("effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:resistance {secs} 4 true"));
            return out;
        }
        let next = self.target(t + 0.05);
        let want = [next[0] - feet[0], next[1] - feet[1], next[2] - feet[2]];
        let m = want.iter().fold(0.0f64, |m, v| m.max(v.abs()));
        let s = if m > STEP { STEP / m } else { 1.0 };
        out.carry = Some([(want[0] * s) as f32, (want[1] * s) as f32, (want[2] * s) as f32]);
        self.asked[0] = true;
        // (a slow roll of the view while inside, eased in and out)
        if self.inside(t) {
            let k = ease((t - self.t_close) / 1.5) * (1.0 - ease((t - self.t_spit + 0.6) / 0.6));
            out.turn = (0.7 * k) as f32;
        }
        out
    }
}

/// The command that puts the player on the land's top at (x, z) (world), a block over it.
pub(super) fn on_land(x: f64, z: f64) -> String {
    format!("execute positioned {x:.2} 0 {z:.2} positioned over motion_blocking_no_leaves run tp @s ~ ~1 ~")
}

#[cfg(test)]
pub(super) mod tests {
    use super::*;

    /// The game's side, as carry.rs's tests play it: moved by each carry (stopped by the land at `floor` unless the
    /// hole is there), thrown by a push made while carried, then the air's drag and gravity.
    pub struct Body {
        pub feet: [f64; 3],
        pub v: [f64; 3],
        asked: bool,
        throw: Option<[f64; 3]>,
    }
    impl Body {
        pub fn new(feet: [f64; 3]) -> Self {
            Body { feet, v: [0.0; 3], asked: false, throw: None }
        }
        /// `floor(x, z)`: the land's height there (the first air).
        pub fn tick(&mut self, o: &CarryTick, floor: &dyn Fn(f64, f64) -> f64) {
            if let Some(v) = o.throw {
                self.throw = Some(v.map(f64::from));
            }
            let was = std::mem::replace(&mut self.asked, o.carry.is_some());
            match o.carry {
                Some(d) => {
                    let d = d.map(f64::from);
                    assert!(d.iter().all(|x| x.abs() <= 4.0), "a move over the game's clamp: {d:?}");
                    let f = floor(self.feet[0] + d[0], self.feet[2] + d[2]);
                    self.feet = [self.feet[0] + d[0], (self.feet[1] + d[1]).max(f), self.feet[2] + d[2]];
                    self.v = d;
                }
                None => {
                    if was {
                        self.v = self.throw.take().unwrap_or([self.v[0] * 0.3, 0.0, self.v[2] * 0.3]);
                    }
                    self.feet = [self.feet[0] + self.v[0], self.feet[1] + self.v[1], self.feet[2] + self.v[2]];
                    self.v = [self.v[0] * 0.91, (self.v[1] - 0.08) * 0.98, self.v[2] * 0.91];
                    let f = floor(self.feet[0], self.feet[2]);
                    if self.feet[1] <= f {
                        self.feet[1] = f;
                        self.v = [0.0; 3];
                    }
                }
            }
        }
    }

    #[test]
    fn a_breach_catch_holds_them_inside_then_spits_them_clear_of_the_hole() {
        let axis = [100.5, 65.0, 50.5];
        let mut c = Catch::new(CatchKind::Breach, axis, 9.0, breach_track(axis, DEPTH), [0.6, 0.8]);
        assert!((3.0..=5.0).contains(&(c.t_spit - c.t_close)), "{}", c.t_spit - c.t_close);
        let floor = |x: f64, z: f64| if (x - axis[0]).hypot(z - axis[2]) < 40.0 { -59.0 } else { 65.0 };
        let mut b = Body::new([110.0, 65.0, 45.0]);
        let mut t = 9.0;
        let mut lowest = 1e9f64;
        while t < 30.0 {
            let o = c.tick(t, b.feet, true);
            b.tick(&o, &floor);
            if t < c.t_spit && t > 9.0 + SWALLOW {
                assert!((b.feet[0] - axis[0]).hypot(b.feet[2] - axis[2]) < 3.0, "off the axis inside at {t}");
                lowest = lowest.min(b.feet[1]);
            }
            t += 0.05;
        }
        assert!(c.done && c.thrown.is_some());
        assert!((lowest - (axis[1] - DEPTH)).abs() < 1.5, "{lowest}");
        let out = (b.feet[0] - axis[0]).hypot(b.feet[2] - axis[2]);
        assert!(out > 60.0 && (b.feet[1] - 65.0).abs() < 1e-6, "ended {out} out at {:?}", b.feet);
    }

    #[test]
    fn a_carry_along_a_track_ends_at_the_far_hole() {
        // (a stand-in run: down 40 at x 0, along to x 250 at that depth, up again)
        let axis = [250.5, 70.0, 0.5];
        let mut track = Vec::new();
        let mut p = [0.5f64, 70.0, 0.5];
        while p[1] > 30.0 {
            p[1] -= 3.0;
            track.push(p);
        }
        while p[0] < 250.5 {
            p[0] = (p[0] + 3.0).min(250.5);
            track.push(p);
        }
        while p[1] < 84.0 {
            p[1] = (p[1] + 3.0).min(84.0);
            track.push(p);
        }
        let mut c = Catch::new(CatchKind::Bite, axis, 9.0, track, [1.0, 0.0]);
        let mut b = Body::new([5.0, 70.0, -3.0]);
        let mut t = 9.0;
        while t < 40.0 {
            let o = c.tick(t, b.feet, true);
            b.tick(&o, &|_, _| -100.0);
            t += 0.05;
        }
        assert!(b.feet[0] > 250.0 + 60.0, "{:?}", b.feet);
    }
}
