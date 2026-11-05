//! The Tsunami's surge: once the water has the player (its surface over their head), it carries them. Not a snap: eased
//! in, lifted off the ground to ride in the water a few blocks down from its surface, borne along with the flow (the
//! way the wave moves, slowing as it holds, then back the way it came as it drains), tumbled a little, buffeted; and put
//! down as the level falls past them, on the land it has scoured.
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
/// How far under the surface they ride, and how high over where they were they are lifted at most.
const RIDE: f64 = 5.0;
const LIFT: f64 = 24.0;

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
        Surge { geo, lift: None, done: false, free: false, grounded: 0, asked: [false; 2], sway: 0.0, n: 0, freed_at: None, left_at: None }
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
    /// holds, back the way it came as it drains.
    fn flow(&self, x: f64, z: f64, t: f64) -> [f64; 2] {
        let (s, u) = self.geo.su(x, z);
        let tau = t - self.geo.arr(s, u);
        let v = TsGeo::vel(s);
        let tr = TsGeo::rise_t(s);
        let rise = 0.25 * v * (1.0 - 0.8 * ease(tr, tr + crate::strike::TS_HOLD, tau));
        let drain = ease(tr + crate::strike::TS_HOLD, tr + crate::strike::TS_HOLD + crate::strike::TS_DRAIN, tau);
        let along = rise * (1.0 - drain) - 16.0 * drain * (1.0 - ease(tr + crate::strike::TS_HOLD + crate::strike::TS_DRAIN, tr + crate::strike::TS_HOLD + crate::strike::TS_DRAIN + 3.0, tau));
        [self.geo.m[0] * along, self.geo.m[1] * along]
    }
    /// One tick, the strike `t` seconds in, the player's feet at `feet`; `held`: the game's last answer (about the carry asked
    /// two ticks ago; false: they broke free); `flying`: whether the game has them flying; `turn`: whether their view
    /// turns and sways with them.
    pub fn tick(&mut self, t: f64, feet: [f64; 3], held: bool, flying: bool, turn: bool) -> CarryTick {
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
                out.cmds.push("effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:resistance 24 4 true".into());
                out.cmds.push("effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:slow_falling 18 0 true".into());
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
        let draining = t - self.geo.arr(s, u) > TsGeo::rise_t(s) + crate::strike::TS_HOLD;
        let late = t - self.geo.arr(s, u) > TsGeo::rise_t(s) + crate::strike::TS_HOLD + 0.75 * crate::strike::TS_DRAIN;
        if ((draining && d < LEAVE + 0.4) || late) && tau > 1.0 {
            self.done = true;
            self.left_at = Some(t);
            return out;
        }
        let k = ease(0.0, 1.6, tau);
        // where they should be a tick on: borne along with the flow, lifted and bobbing, never nearer the surface than RIDE
        let v = self.flow(feet[0], feet[2], t);
        let buffet = [(1.7 * (2.3 * tau + l.ph).sin() + 0.8 * (4.1 * tau + 2.0).sin()) * 0.4, (1.5 * (1.9 * tau + 1.0 + l.ph).sin() + 0.7 * (3.7 * tau).sin()) * 0.4];
        let (nx, nz) = (-self.geo.m[1], self.geo.m[0]);
        let want_h = [v[0] * 0.05 * k + nx * buffet[0] * 0.05 * 6.0 * k, v[1] * 0.05 * k + nz * buffet[0] * 0.05 * 6.0 * k];
        let top = feet[1] + d - RIDE;
        let rise = LIFT * k + 6.0 * (0.9 * tau).sin() * k;
        let y_t = (l.y0 + rise).min(top).max(l.y0.min(top));
        let dy = ((y_t - feet[1]) * 0.22).clamp(-1.0, 1.3) + buffet[1] * 0.05;
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
        // (their view: tumbled a little by the flow, gusting)
        if turn {
            let sway = 3.2 * ((0.9 * tau + l.ph).sin() + 0.5 * (2.1 * tau + 1.0).sin()) * k;
            let w = sway - self.sway;
            self.sway = sway;
            out.turn = w.clamp(-1.6, 1.6) as f32;
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
        let mut held = true;
        for i in 0..(42.0 / 0.05) as u32 {
            let t = f64::from(i) * 0.05;
            if s.over(t) {
                break;
            }
            let o = s.tick(t, feet, held, false, true);
            if let Some(c) = o.carry {
                taken.get_or_insert(t);
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
        assert!(left > a + 7.0 && left < 36.0, "put down at {left}");
        // (it never carries them when the water is not over them: far past its reach)
        let far = geo(900.0);
        let mut s = Surge::new(far);
        for i in 0..800 {
            assert!(s.tick(f64::from(i) * 0.05, [0.5, 65.0, 900.0], true, false, true).carry.is_none());
        }
    }
    #[test]
    fn sneaking_breaks_free() {
        let g = geo(300.0);
        let mut s = Surge::new(g.clone());
        let (a, imm) = g.at_player(65.0);
        let mut t = imm.unwrap() + 0.1;
        assert!(s.tick(t, [0.5, 65.0, 300.0], true, false, false).carry.is_some());
        let mut free = false;
        for _ in 0..6 {
            t += 0.05;
            let o = s.tick(t, [0.5, 66.0, 300.0], false, false, false);
            free |= o.carry.is_none();
        }
        assert!(free && s.freed_at.is_some() && a < t);
    }
}
