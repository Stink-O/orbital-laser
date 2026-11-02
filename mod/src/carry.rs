//! The Hurricane's carry: a player the wind reaches is picked up and carried round the storm with the debris, then put
//! back down as it drops. With the KNOCKBACK switch off (`/orbital knockback off`) they are left standing.
//!
//! It carries them through the fork's `world.carry-player`: each tick their move in place of their own (the game's
//! collision move, no gravity, no drag, their fall distance kept at nothing), drawn smoothly between ticks as a ride
//! is: no fight with gravity, no slow falling. Never faster than a few blocks a tick (the game clamps each axis to 4;
//! follow.rs's VMAX, 24, is where its collision sweep gave out). Their path: as the wind's front reaches where they
//! stand (none in the calm eye, none past CARRY_R), lifted off the land and drawn in towards ORBIT_R round the middle,
//! ORBIT_H over its ground, turning with the wind (most of its speed there: the debris overtakes them), buffeted;
//! then, as the storm peaks (EYE0 to EYE1), drawn in through the eyewall into the calm of the eye, EYE_R from the
//! middle and EYE_H up: sudden stillness, blue sky and sunlight straight down the stadium all round them; from the
//! fling (HU_FLING) thrown back out through the far eyewall with everything else and let down over DOWN seconds onto
//! the land past it, carried on down till they stand on it (the move stops them there), then let go: never dropped.
//!
//! A player breaks free by flying (a double jump in creative flight) or sneaking: the game moves them as their own
//! that tick and the next carry answers false; the carry lets go at once (a gust's whoosh). Free, they are left alone
//! while they fly; if they come back down and stand on the land while the wind still blows there, it picks them up
//! again. Ticks they are held still while their chunk loads keep the carry where it was.
#![cfg_attr(not(test), allow(dead_code))]
use crate::strike::{HU_FLING, HU_R_EYE, hu_front_t, hu_omega, hu_spin};

/// How far out the wind picks the player up, the orbit it carries them on (out from the middle, up over its ground),
/// and how long it takes to let them back down.
pub const CARRY_R: f64 = 175.0;
pub const ORBIT_R: f64 = 108.0;
pub const ORBIT_H: f64 = 50.0;
pub const DOWN: f64 = 7.0;
/// Drawn into the eye from EYE0 to EYE1 (or over 3.5 s from a second after they were picked up, if later), to EYE_R
/// out and EYE_H over the middle's ground; flung back out to FLUNG_R as they are let down.
pub const EYE0: f64 = 38.0;
pub const EYE1: f64 = 41.5;
pub const EYE_R: f64 = 14.0;
pub const EYE_H: f64 = 90.0;
pub const FLUNG_R: f64 = 132.0;

/// What a tick of the carry does: the move to carry the player by (blocks, this tick), the commands to run on them,
/// the sounds to play (event, volume, pitch).
#[derive(Default)]
pub struct CarryTick {
    pub carry: Option<[f32; 3]>,
    pub cmds: Vec<String>,
    pub sounds: Vec<(String, f32, f32)>,
}

/// The most it carries them a tick on any axis (the game's own clamp is 4).
const STEP: f64 = 3.5;
/// After DOWN, how long it carries them on down at most before letting go wherever they are.
const SETTLE: f64 = 6.0;

struct Lift {
    t0: f64,
    r0: f64,
    y0: f64,
    /// How far round the middle they are: turned on a tick at a time with the wind where they are.
    a: f64,
}

pub struct Carry {
    /// The storm's middle on its ground.
    c: [f64; 3],
    lift: Option<Lift>,
    done: bool,
    next_whoosh: f64,
    n: u32,
    /// Where the last tick sent them (for the tests).
    pub target: Option<[f64; 3]>,
    /// Broken free, and since when they have stood still on the land (to be picked up again).
    free: bool,
    last: Option<[f64; 3]>,
    stood: u32,
    /// Whether a carry was asked for one and two ticks ago (the game's answer, `world.carry-player`'s, is about the
    /// one asked two ticks ago: the mod hears it as it asks the next), and for how many ticks running the let-down has
    /// found the land under them.
    asked: [bool; 2],
    landed: u32,
    /// When they broke free, for the tests.
    pub freed_at: Option<f64>,
}

fn ease(a: f64, b: f64, t: f64) -> f64 {
    let x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    x * x * x * (x * (6.0 * x - 15.0) + 10.0)
}

impl Carry {
    pub fn new(c: [f64; 3]) -> Carry {
        Carry { c, lift: None, done: false, next_whoosh: 0.0, n: 0, target: None, free: false, last: None, stood: 0, asked: [false; 2], landed: 0, freed_at: None }
    }
    /// Whether it is over (the player let go, or never picked up and the wind dropping).
    pub fn over(&self, t: f64) -> bool {
        self.done || (self.lift.is_none() && t > HU_FLING - 4.0)
    }
    pub fn lifted(&self) -> bool {
        self.lift.is_some() && !self.done && !self.free
    }
    /// How far into the eye they have been drawn at `t` (0 none, 1 in its middle's calm).
    fn eye(l: &Lift, t: f64) -> f64 {
        let e0 = EYE0.max(l.t0 + 1.0);
        ease(e0, EYE1.max(e0 + 4.5), t)
    }
    /// How far out from the middle they are carried at `t`.
    fn radius(l: &Lift, t: f64) -> f64 {
        let tau = (t - l.t0).max(0.0);
        let e = Self::eye(l, t);
        let buffet = (1.6 * (2.3 * tau + 0.7).sin() + 0.8 * (4.1 * tau + 2.0).sin()) * (1.0 - e);
        let round = ORBIT_R + (l.r0 - ORBIT_R) * (-tau / 6.0).exp() + buffet * (1.0 - (-tau).exp());
        let r = round + (EYE_R - round) * e;
        r + (FLUNG_R - r) * ease(HU_FLING, HU_FLING + DOWN * 0.6, t)
    }
    /// Where their feet should be at `t` (once they are picked up), at angle `a` round the middle.
    fn at(&self, t: f64, a: f64) -> Option<[f64; 3]> {
        let l = self.lift.as_ref()?;
        let tau = (t - l.t0).max(0.0);
        let r = Self::radius(l, t);
        let rise = (1.0 - (-tau / 4.0).exp()) * ease(0.0, 1.2, tau);
        let e = Self::eye(l, t);
        let peak = self.c[1] + ORBIT_H + (5.0 * (0.7 * tau).sin() + 1.5 * (1.9 * tau).sin()) * (1.0 - e) + (EYE_H - ORBIT_H) * e;
        let mut y = l.y0 + (peak - l.y0) * rise;
        // (let down from the fling, drifting out, towards the land under the middle's ground (or where they stood):
        // carried on down after till they stand on it)
        let u = ease(HU_FLING, HU_FLING + DOWN, t);
        y += (self.c[1].min(l.y0) - 1.0 - y) * u;
        Some([self.c[0] + r * a.cos(), y, self.c[2] + r * a.sin()])
    }
    /// One tick, the strike `t` seconds in, the player's feet at `feet`; `held`: the game's last answer (about the
    /// carry asked two ticks ago; false: they broke free).
    pub fn tick(&mut self, t: f64, feet: [f64; 3], held: bool) -> CarryTick {
        let mut out = CarryTick::default();
        if self.done {
            return out;
        }
        let asked = self.asked[1];
        self.asked = [false, self.asked[0]];
        // (free: left alone while they fly; standing still on the land again (their feet on a block's top, unmoving
        // for a second), the wind picks them up again if it still blows there)
        if self.free {
            let still = self.last.is_some_and(|l| l == feet) && (feet[1] - feet[1].round()).abs() < 1e-3;
            self.stood = if still { self.stood + 1 } else { 0 };
            self.last = Some(feet);
            if self.stood < 20 {
                return out;
            }
            self.free = false;
            self.lift = None;
        }
        if self.lift.is_none() {
            let (dx, dz) = (feet[0] - self.c[0], feet[2] - self.c[2]);
            let d = dx.hypot(dz);
            let reached = hu_front_t(d).is_some_and(|f| t >= f);
            if t < HU_FLING - 4.0 && reached && d > HU_R_EYE + 4.0 && d <= CARRY_R {
                self.lift = Some(Lift { t0: t, r0: d, y0: feet[1], a: dz.atan2(dx) });
                self.next_whoosh = t + 0.4;
                self.landed = 0;
            } else {
                return out;
            }
        } else if asked && !held {
            // (broken free: they fly or sneak; let go at once, the gust heard)
            self.free = true;
            self.freed_at = Some(t);
            self.stood = 0;
            self.last = Some(feet);
            out.sounds.push(("orbital:hurricane.whoosh2".into(), 0.9, 0.75));
            out.sounds.push(("orbital:hurricane.whoosh4".into(), 0.7, 1.1));
            return out;
        }
        // (set down: once let down, standing on the land (the move stopped short of where it was carried down to) a
        // few ticks running, or after SETTLE more, let go)
        if t > HU_FLING + DOWN {
            let stopped = self.last.is_some_and(|l| (l[1] - feet[1]).abs() < 1e-3);
            self.landed = if stopped { self.landed + 1 } else { 0 };
            if self.landed >= 3 || t > HU_FLING + DOWN + SETTLE {
                self.done = true;
                return out;
            }
        }
        self.last = Some(feet);
        // (turned on round the middle with the wind where they are, a little behind it)
        let Some(l) = &mut self.lift else { return out };
        let r = Self::radius(l, t);
        // (the eye calm: hardly turning in it)
        let calm = 0.15 + 0.85 * ((r - HU_R_EYE) / 30.0).clamp(0.0, 1.0);
        l.a += 0.8 * -1.0 * hu_omega(r) * hu_spin(t) * 0.05 * calm;
        let a = l.a;
        let Some(mut next) = self.at((t + 0.05).min(HU_FLING + DOWN), a) else { return out };
        if t > HU_FLING + DOWN {
            // (on down, a block a tick, till the land stops them)
            next = [next[0], feet[1] - 1.0, next[2]];
        }
        self.target = Some(next);
        let want = [next[0] - feet[0], next[1] - feet[1], next[2] - feet[2]];
        let m = want.iter().fold(0.0f64, |m, v| m.max(v.abs()));
        let k = if m > STEP { STEP / m } else { 1.0 };
        out.carry = Some([(want[0] * k) as f32, (want[1] * k) as f32, (want[2] * k) as f32]);
        self.asked[0] = true;
        // (the debris rushing past them)
        if t >= self.next_whoosh && t < HU_FLING + 2.0 && r > HU_R_EYE + 12.0 {
            self.n += 1;
            let h = |k: u32| crate::strike::hash01(self.n.wrapping_mul(7) ^ k);
            out.sounds.push((format!("orbital:hurricane.whoosh{}", 1 + (h(1) * 4.0) as u32 % 4), 0.35 + 0.2 * h(2) as f32, 0.88 + 0.24 * h(3) as f32));
            self.next_whoosh = t + 1.1 + 1.2 * h(4);
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::follow::drag;

    /// A player as the game moves them: carried (`world.carry-player`: moved by the carry, colliding with flat land
    /// at 65, no gravity, their fall distance nothing) unless they fly (from `fly_at`) or none is asked; else their own
    /// motion (the air's drag and gravity, or flight's); held still (their chunk not loaded) over the ticks `hold` says.
    /// Returns when they were picked up and let go (or broke free), how fast they were carried, how far off its path,
    /// how high, where they ended, how far from the middle at 44 s, and the worst fall they took (blocks).
    struct Run {
        lifted_at: f64,
        freed_at: Option<f64>,
        fastest: f64,
        off: f64,
        high: f64,
        end: [f64; 3],
        eye_at: f64,
        worst_fall: f64,
    }
    fn carry(start: [f64; 3], flying0: bool, fly_at: f64, hold: impl Fn(f64) -> bool) -> Run {
        let c = [0.5, 65.0, 0.5];
        let mut k = Carry::new(c);
        let (mut feet, mut v) = (start, [0.0f64; 3]);
        let mut flying = flying0;
        let mut pending: Option<[f32; 3]> = None;
        let mut held = true;
        let mut heard = true;
        let mut run = Run { lifted_at: -1.0, freed_at: None, fastest: 0.0, off: 0.0, high: 0.0, end: start, eye_at: f64::MAX, worst_fall: 0.0 };
        let mut fall = 0.0f64;
        for n in 1..=(70 * 20) {
            let t = f64::from(n) * 0.05;
            if t >= fly_at {
                flying = true;
            }
            if !hold(t) {
                match pending.take() {
                    Some(d) if !flying => {
                        let d = [f64::from(d[0]), f64::from(d[1]), f64::from(d[2])];
                        feet = [feet[0] + d[0], (feet[1] + d[1]).max(65.0), feet[2] + d[2]];
                        v = d;
                        fall = 0.0;
                        held = true;
                        run.fastest = run.fastest.max(d.iter().fold(0.0f64, |a, x| a.max(x.abs())));
                    }
                    p => {
                        held = p.is_none();
                        feet = [feet[0] + v[0], feet[1] + v[1], feet[2] + v[2]];
                        if v[1] < 0.0 && !flying {
                            fall -= v[1];
                        }
                        v = drag(v, flying);
                        if feet[1] <= 65.0 {
                            feet[1] = 65.0;
                            v[1] = 0.0;
                            run.worst_fall = run.worst_fall.max(fall);
                            fall = 0.0;
                        }
                    }
                }
            }
            // (where they are against where the last tick sent them)
            if let Some(w) = k.target
                && k.lifted()
                && t > run.lifted_at + 0.5
                && t < HU_FLING
                && !hold(t)
            {
                run.off = run.off.max(((feet[0] - w[0]).powi(2) + (feet[1] - w[1]).powi(2) + (feet[2] - w[2]).powi(2)).sqrt());
            }
            let o = k.tick(t, feet, heard);
            heard = held;
            if k.lifted() && run.lifted_at < 0.0 {
                run.lifted_at = t;
            }
            pending = o.carry;
            if let Some(f) = k.freed_at {
                assert!(o.carry.is_none() || t > f, "carried on after breaking free");
                if run.freed_at.is_none() {
                    run.freed_at = Some(f);
                    assert!(o.sounds.iter().any(|s| s.0.contains("whoosh")), "no gust as they break free");
                }
            }
            run.high = run.high.max(feet[1] - 65.0);
            if (t - 44.0).abs() < 0.03 {
                run.eye_at = (feet[0] - c[0]).hypot(feet[2] - c[2]);
            }
            if k.freed_at.is_some() && t > k.freed_at.unwrap() + 1.0 {
                break;
            }
        }
        run.end = feet;
        run
    }

    /// `CARRY_OUT=path cargo test --release hu_write_carry_path -- --ignored`: a player standing 120 east of the middle
    /// carried as the game would carry them (`t x y z` a tick, their feet), for an offscreen clip from their view.
    #[test]
    #[ignore]
    fn hu_write_carry_path() {
        let mut k = Carry::new([0.5, 65.0, 0.5]);
        let mut feet = [120.0f64, 65.0, 0.5];
        let mut out = String::new();
        let mut pending: Option<[f32; 3]> = None;
        for n in 1..=(64 * 20) {
            let t = f64::from(n) * 0.05;
            if let Some(d) = pending.take() {
                feet = [feet[0] + f64::from(d[0]), (feet[1] + f64::from(d[1])).max(65.0), feet[2] + f64::from(d[2])];
            }
            pending = k.tick(t, feet, true).carry;
            out += &format!("{t:.3} {:.4} {:.4} {:.4}\n", feet[0], feet[1], feet[2]);
        }
        std::fs::write(std::env::var("CARRY_OUT").unwrap(), out).unwrap();
    }

    #[test]
    fn the_wind_carries_the_player_round_and_puts_them_down() {
        for start in [[120.0, 65.0, 0.5], [0.5, 65.0, -160.0], [45.0, 65.0, 30.0]] {
            let r = carry(start, false, f64::MAX, |_| false);
            eprintln!("from {start:?}: picked up at {:.2} s, at most {:.2} blocks a tick, {:.2} off its path, {:.0} up, {:.1} from the middle at 44 s, down at {:?}, worst fall {:.1}", r.lifted_at, r.fastest, r.off, r.high, r.eye_at, r.end, r.worst_fall);
            let d = (start[0] - 0.5).hypot(start[2] - 0.5);
            assert!((r.lifted_at - hu_front_t(d).unwrap()).abs() < 0.11, "picked up at {}", r.lifted_at);
            // (never near the speed the game's collision sweep can't take: a few blocks a tick)
            assert!(r.fastest <= STEP + 1e-6 && r.fastest < crate::follow::VMAX * 0.2, "{} blocks a tick", r.fastest);
            assert!(r.off < 3.0, "{} off its path", r.off);
            assert!(r.high > 35.0, "only {} up", r.high);
            // (in the eye's calm at the storm's height)
            assert!(r.eye_at < HU_R_EYE, "only {:.1} from the middle at 44 s", r.eye_at);
            // (set down on the land, never dropped: no fall worth a hit point)
            assert!(r.end[1] < 65.0 + 0.01 && r.worst_fall <= 3.0, "left {} up, fell {}", r.end[1] - 65.0, r.worst_fall);
            assert!((r.end[0] - start[0]).hypot(r.end[2] - start[2]) < 400.0);
        }
        // (in the calm of the eye, or far out, never picked up)
        for start in [[10.0, 65.0, 10.0], [0.5, 65.0, 300.0]] {
            let r = carry(start, false, f64::MAX, |_| false);
            assert!(r.lifted_at < 0.0 && r.high < 1e-9, "{start:?}");
        }
    }

    #[test]
    fn a_carried_player_who_flies_breaks_free_and_one_held_still_does_not() {
        for fly_at in [24.0, 31.3, 36.0, 43.0] {
            let r = carry([45.0, 65.0, 30.0], false, fly_at, |_| false);
            let f = r.freed_at.unwrap_or_else(|| panic!("flying at {fly_at}: never let go"));
            eprintln!("flying at {fly_at}: let go at {f:.2} s ({:.0} ticks)", (f - fly_at) / 0.05);
            assert!(f >= fly_at && f - fly_at <= 0.16, "flying at {fly_at}: let go at {f}");
        }
        // (held still a tick or several at a time while their chunk loads, never flying: carried on, never let go)
        let r = carry([45.0, 65.0, 30.0], false, f64::MAX, |t| (t * 20.0) as u32 % 37 < 6 || (25.0..25.6).contains(&t));
        assert!(r.freed_at.is_none(), "let go at {:?} while held still", r.freed_at);
        let r = carry([120.0, 65.0, 0.5], false, f64::MAX, |_| false);
        assert!(r.freed_at.is_none(), "let go at {:?} without flying", r.freed_at);
    }
}
