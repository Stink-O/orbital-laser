//! The Tsunami's surge: once the water has the player (its surface over their head), it carries them. Not a snap: eased
//! in, thrown along with the flow, tumbled and buffeted in the deep of it, drawn up as it holds; at SURF seconds they
//! break the surface, and from there they ride it down as it falls, borne back the way it came with the torrent, their
//! view turned to look the way the water is going, over what it has left; and put down as it runs out from under them.
//!
//! It carries them through the fork's `world.carry-player`, as the Hurricane's wind does (carry.rs): each tick their move
//! in place of their own (the game's collision move, no gravity, no drag), a turn of their view spread over the tick's
//! frames. Never faster than a few blocks a tick. With the KNOCKBACK switch off (`/orbital knockback off`) they are left
//! standing. A deliberate break-free (sneak held half a second: the game decides) lets go at once; they are left alone
//! while they fly, and once they stop flying for REARM ticks while the water still has the place they are at, it takes
//! them again.
//!
//! The water is the strike's closed-form model (strike/tsunami.rs's `TsGeo`), so this needs nothing from the world: its
//! depth over them is `level` less their height.
#![cfg_attr(not(test), allow(dead_code))]
use crate::carry::CarryTick;
use crate::strike::TsGeo;

/// The most it carries them a tick on any axis (the game's own clamp is 4).
const STEP: f64 = 3.2;
/// Broken free, how long they must be out of flight before the water can have them again (ticks).
const REARM: u32 = 20;
/// How deep the water must be over their feet for it to take them, and the depth under which it lets them go.
const TAKE: f64 = 2.5;
const LEAVE: f64 = 0.6;
/// When their head breaks the surface, seconds after it took them (tools/sounds_tsunami.py's SURF_AT, strike/ts_sounds.rs),
/// and how far under the surface their feet ride from then on (their eye about half a block over it).
pub const SURF: f64 = 6.5;
const RIDE: f64 = 1.1;
/// How fast their view turns to look the way the water goes (degrees a tick at most).
const FACE: f64 = 2.2;

struct Lift {
    t0: f64,
    y0: f64,
    /// Their drift across the flow, and its phase.
    ph: f64,
}

pub struct Surge {
    geo: TsGeo,
    lift: Option<Lift>,
    done: bool,
    free: bool,
    grounded: u32,
    asked: [bool; 2],
    sway: f64,
    n: u32,
    /// Where their feet were a tick ago and the rise or fall it asked for then; the ticks the land has held them up.
    last: (f64, f64),
    held_up: u32,
    pub freed_at: Option<f64>,
    /// When it let them go, for the tests.
    pub left_at: Option<f64>,
}

fn ease(a: f64, b: f64, t: f64) -> f64 {
    let x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    x * x * x * (x * (6.0 * x - 15.0) + 10.0)
}

impl Surge {
    pub fn new(geo: TsGeo) -> Surge {
        Surge { geo, lift: None, done: false, free: false, grounded: 0, asked: [false; 2], sway: 0.0, n: 0, last: (0.0, 0.0), held_up: 0, freed_at: None, left_at: None }
    }
    /// Whether it is over: the water gone from them, or the strike's end near.
    pub fn over(&self, t: f64) -> bool {
        self.done || t > f64::from(crate::strike::TS_LEN) - 0.2
    }
    pub fn lifted(&self) -> bool {
        self.lift.is_some() && !self.done && !self.free
    }
    /// The water over a point at `t`: its surface less the height given (`y`), none where there is none.
    fn depth(&self, x: f64, y: f64, z: f64, t: f64) -> Option<f64> {
        let (s, u) = self.geo.su(x, z);
        self.geo.level(s, u, t).map(|l| l - (y - self.geo.t[1]))
    }
    /// The flow's velocity at (x, z) at `t`, blocks a second, along the wave's way: fast as the face goes over, slowing as it
    /// holds, back the way it came as it drains (the pass's ts_flow).
    fn flow(&self, x: f64, z: f64, t: f64) -> [f64; 2] {
        let (s, u) = self.geo.su(x, z);
        let tau = t - self.geo.arr(s, u);
        let v = TsGeo::vel(s);
        let tr = TsGeo::rise_t(s);
        let rise = 0.25 * v * (1.0 - 0.8 * ease(tr, tr + crate::strike::TS_HOLD, tau));
        let x = self.geo.drained(t, s);
        let drain = ease(0.0, 0.5, x);
        let along = rise * (1.0 - drain) - 24.0 * drain * (1.0 - ease(0.8, 1.0, x));
        [self.geo.m[0] * along, self.geo.m[1] * along]
    }
    /// One tick, the strike `t` seconds in, the player's feet at `feet`, their yaw; `held`: the game's last answer (about the
    /// carry asked two ticks ago; false: they broke free); `flying`: whether the game has them flying; `turn`: whether their
    /// view turns and sways with them.
    pub fn tick(&mut self, t: f64, feet: [f64; 3], yaw: f64, held: bool, flying: bool, turn: bool) -> CarryTick {
        let mut out = CarryTick::default();
        if self.done {
            return out;
        }
        let asked = self.asked[1];
        self.asked = [false, self.asked[0]];
        let depth = self.depth(feet[0], feet[1], feet[2], t);
        if self.free {
            self.grounded = if flying { 0 } else { self.grounded + 1 };
            if self.grounded < REARM || depth.is_none_or(|d| d < TAKE) {
                return out;
            }
            self.free = false;
            self.lift = None;
            self.asked = [false; 2];
        }
        if self.lift.is_none() {
            // (taken: the water over their head and rising or holding, not a thin film)
            let (s, u) = self.geo.su(feet[0], feet[2]);
            let tau = t - self.geo.arr(s, u);
            if depth.is_some_and(|d| d >= TAKE) && tau < TsGeo::rise_t(s) + crate::strike::TS_HOLD + 2.0 {
                self.lift = Some(Lift { t0: t, y0: feet[1], ph: f64::from(self.n) });
                // (a soft landing wherever it sets them down; the creative and spectators need none)
                out.cmds.push("effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:resistance 28 4 true".into());
                out.cmds.push("effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:slow_falling 26 0 true".into());
            } else {
                return out;
            }
        } else if asked && !held {
            // (broken free: sneak held; let go at once)
            self.free = true;
            self.freed_at = Some(t);
            self.grounded = 0;
            return out;
        }
        let Some(l) = &self.lift else { return out };
        let tau = (t - l.t0).max(0.0);
        // (put down: the water gone from under them as it drains)
        let d = depth.unwrap_or(0.0);
        let (s, u) = self.geo.su(feet[0], feet[2]);
        let draining = self.geo.drained(t, s) > 0.0;
        let late = self.geo.drained(t, s) > 0.85;
        let _ = u;
        // (they ride down with the surface until the land stops them going any lower)
        if self.last.1 < -0.08 && feet[1] - self.last.0 > self.last.1 * 0.4 {
            self.held_up += 1;
        } else {
            self.held_up = 0;
        }
        if ((draining && self.held_up >= 4) || depth.is_none() || late) && tau > SURF + 1.0 {
            self.done = true;
            self.left_at = Some(t);
            return out;
        }
        let k = ease(0.0, 1.6, tau);
        // where they should be a tick on: borne along with the flow, and up: most of the way drawn up in the deep, then
        // hauled the rest; from SURF they stay with the surface
        let v = self.flow(feet[0], feet[2], t);
        let up = ease(SURF - 0.6, SURF + 0.4, tau);
        let buffet = [(1.7 * (2.3 * tau + l.ph).sin() + 0.8 * (4.1 * tau + 2.0).sin()) * 0.4, (1.5 * (1.9 * tau + 1.0 + l.ph).sin() + 0.7 * (3.7 * tau).sin()) * 0.4];
        let (nx, nz) = (-self.geo.m[1], self.geo.m[0]);
        let shake = 1.0 - 0.8 * up;
        let want_h = [v[0] * 0.05 * k + nx * buffet[0] * 0.05 * 6.0 * k * shake, v[1] * 0.05 * k + nz * buffet[0] * 0.05 * 6.0 * k * shake];
        // (where the surface will be a tick on: following it, not chasing it)
        let d1 = self.depth(feet[0], feet[1], feet[2], t + 0.05).unwrap_or(d);
        let surf = feet[1] + d1 - RIDE;
        let frac = 0.42 * ease(0.6, SURF - 1.3, tau) + 0.58 * ease(SURF - 1.75, SURF - 0.05, tau);
        let bob = 0.25 * (1.3 * tau).sin() * up;
        let y_t = l.y0 + (surf - l.y0).max(0.0) * frac + bob;
        let dy = if tau >= SURF { y_t.min(surf + 0.6) - feet[1] } else { (y_t - feet[1]) * 0.5 };
        let dy = dy.clamp(-2.6, STEP) + buffet[1] * 0.05 * shake;
        let mut want = [want_h[0], dy, want_h[1]];
        let m = want.iter().fold(0.0f64, |m, v| m.max(v.abs()));
        if m > STEP {
            let s = STEP / m;
            for v in &mut want {
                *v *= s;
            }
        }
        out.carry = Some([want[0] as f32, want[1] as f32, want[2] as f32]);
        self.asked[0] = true;
        self.last = (feet[1], want[1]);
        // (their view: tumbled a little by the flow, gusting; up, turned to look the way the water is going)
        if turn {
            let sway = 3.2 * ((0.9 * tau + l.ph).sin() + 0.5 * (2.1 * tau + 1.0).sin()) * k * shake;
            let mut w = sway - self.sway;
            self.sway = sway;
            if tau > SURF - 0.3 {
                // (yaw 0 looks along +z, 90 along -x; the way the water goes is back along m)
                let want_yaw = self.geo.m[0].atan2(-self.geo.m[1]).to_degrees();
                let diff = (want_yaw - yaw + 540.0).rem_euclid(360.0) - 180.0;
                w += (diff * 0.06).clamp(-FACE, FACE);
                out.turn = w.clamp(-3.2, 3.2) as f32;
            } else {
                out.turn = w.clamp(-1.6, 1.6) as f32;
            }
        }
        self.n = self.n.wrapping_add(1);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::Target;

    fn geo(dp: f64) -> TsGeo {
        TsGeo::new(&Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] }, [0.5, 65.0, dp], 37.0)
    }
    #[test]
    fn the_water_takes_the_player_carries_them_and_puts_them_down() {
        let g = geo(400.0);
        let mut s = Surge::new(g.clone());
        let mut feet = [0.5, 65.0, 400.0];
        let (mut taken, mut max_step, mut ticks) = (None, 0.0f64, 0u32);
        let (mut yaw, mut surfaced) = (180.0f64, None);
        let mut held = true;
        for i in 0..(42.0 / 0.05) as u32 {
            let t = f64::from(i) * 0.05;
            if s.over(t) {
                break;
            }
            let o = s.tick(t, feet, yaw, held, false, true);
            if let Some(c) = o.carry {
                yaw += f64::from(o.turn);
                taken.get_or_insert(t);
                let head = feet[1] + 1.62 - g.t[1];
                if surfaced.is_none() && g.level(g.su(feet[0], feet[2]).0, g.su(feet[0], feet[2]).1, t).is_some_and(|l| head >= l) {
                    surfaced = Some(t);
                }
                ticks += 1;
                for k in 0..3 {
                    max_step = max_step.max(f64::from(c[k]).abs());
                    feet[k] += f64::from(c[k]);
                }
                feet[1] = feet[1].max(65.0);
                held = true;
            }
        }
        let (a, imm) = g.at_player(65.0);
        let taken = taken.expect("taken");
        assert!(taken >= imm.unwrap() - 0.1 && taken < a + 3.0, "taken at {taken}, the face reached them at {a}");
        assert!(max_step <= STEP + 1e-9, "steps of {max_step}");
        assert!(ticks > 100, "{ticks} ticks carried");
        let left = s.left_at.expect("put down");
        assert!(left > a + 8.0 && left < 38.0, "put down at {left}");
        // (their head breaks the surface when the sounds say, they end looking the way the water went, and on the land
        // it has been over)
        let surfaced = surfaced.expect("surfaced");
        assert!((surfaced - (imm.unwrap() + SURF)).abs() < 0.5, "surfaced at {surfaced}, the water closed at {}", imm.unwrap());
        let (dx, dz) = (-yaw.to_radians().sin(), yaw.to_radians().cos());
        assert!(dx * g.m[0] + dz * g.m[1] < -0.95, "looking {dx} {dz}");
        let (s_end, _) = g.su(feet[0], feet[2]);
        assert!(s_end > -100.0 && s_end < g.send - 40.0, "put down at s = {s_end}");
        // (it never carries them when the water is not over them: far past its reach)
        let far = geo(900.0);
        let mut s = Surge::new(far);
        for i in 0..800 {
            assert!(s.tick(f64::from(i) * 0.05, [0.5, 65.0, 900.0], 0.0, true, false, true).carry.is_none());
        }
    }
    #[test]
    fn sneaking_breaks_free() {
        let g = geo(300.0);
        let mut s = Surge::new(g.clone());
        let (a, imm) = g.at_player(65.0);
        let mut t = imm.unwrap() + 0.1;
        assert!(s.tick(t, [0.5, 65.0, 300.0], 0.0, true, false, false).carry.is_some());
        let mut free = false;
        for _ in 0..6 {
            t += 0.05;
            let o = s.tick(t, [0.5, 66.0, 300.0], 0.0, false, false, false);
            free |= o.carry.is_none();
        }
        assert!(free && s.freed_at.is_some() && a < t);
    }
}
