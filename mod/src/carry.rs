//! The Hurricane's carry: a player the wind reaches is picked up and carried round the storm with the debris, then put
//! back down as it drops. With the KNOCKBACK switch off (`/orbital knockback off`) they are left standing.
//!
//! It moves them as the follow camera does (follow.rs's `Drive`): a kick to their velocity each tick
//! (`world.push-player`) that lands them on the next point of their path, the game's own movement carrying them and its
//! frame interpolation drawing it smoothly; never faster than follow.rs's VMAX (24 blocks a tick on any axis: a bigger
//! move crashed the game's collision sweep), and in practice a block or two a tick. Their path: as the wind's front
//! reaches where they stand (none in the calm eye, none past CARRY_R), drawn in towards ORBIT_R round the middle and
//! lifted ORBIT_H over its ground, turning with the wind (most of its speed there: the debris overtakes them),
//! buffeted; from the fling (HU_FLING) let down over DOWN seconds onto the land a few blocks over the middle's ground,
//! drifting out, then let go. Slow falling is given as they are picked up, for long enough to see them down, so
//! however they come down (a hill under them, a valley, the strike stopped) they land softly.
#![cfg_attr(not(test), allow(dead_code))]
use crate::follow::Drive;
use crate::strike::{HU_FLING, HU_R_EYE, hu_front_t, hu_omega, hu_spin};

/// How far out the wind picks the player up, the orbit it carries them on (out from the middle, up over its ground),
/// and how long it takes to let them back down.
pub const CARRY_R: f64 = 175.0;
pub const ORBIT_R: f64 = 108.0;
pub const ORBIT_H: f64 = 50.0;
pub const DOWN: f64 = 7.0;

/// What a tick of the carry does: the kicks to give the player, the commands to run on them, the sounds to play
/// (event, volume, pitch).
#[derive(Default)]
pub struct CarryTick {
    pub kicks: Vec<[f32; 3]>,
    pub cmds: Vec<String>,
    pub sounds: Vec<(String, f32, f32)>,
}

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
    drive: Drive,
    done: bool,
    next_whoosh: f64,
    n: u32,
    /// Where the last tick sent them (for the tests).
    pub target: Option<[f64; 3]>,
}

fn ease(a: f64, b: f64, t: f64) -> f64 {
    let x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    x * x * x * (x * (6.0 * x - 15.0) + 10.0)
}

impl Carry {
    pub fn new(c: [f64; 3]) -> Carry {
        Carry { c, lift: None, drive: Drive::default(), done: false, next_whoosh: 0.0, n: 0, target: None }
    }
    /// Whether it is over (the player let go, or never picked up and the wind dropping).
    pub fn over(&self, t: f64) -> bool {
        self.done || (self.lift.is_none() && t > HU_FLING - 4.0)
    }
    pub fn lifted(&self) -> bool {
        self.lift.is_some() && !self.done
    }
    /// How far out from the middle they are carried at `t`.
    fn radius(l: &Lift, t: f64) -> f64 {
        let tau = (t - l.t0).max(0.0);
        let buffet = 1.6 * (2.3 * tau + 0.7).sin() + 0.8 * (4.1 * tau + 2.0).sin();
        ORBIT_R + (l.r0 - ORBIT_R) * (-tau / 6.0).exp() + buffet * (1.0 - (-tau).exp()) + 12.0 * ease(HU_FLING, HU_FLING + DOWN, t)
    }
    /// Where their feet should be at `t` (once they are picked up), at angle `a` round the middle.
    fn at(&self, t: f64, a: f64) -> Option<[f64; 3]> {
        let l = self.lift.as_ref()?;
        let tau = (t - l.t0).max(0.0);
        let r = Self::radius(l, t);
        let rise = (1.0 - (-tau / 4.0).exp()) * ease(0.0, 1.2, tau);
        let peak = self.c[1] + ORBIT_H + 5.0 * (0.7 * tau).sin() + 1.5 * (1.9 * tau).sin();
        let mut y = l.y0 + (peak - l.y0) * rise;
        // (let down from the fling, drifting out, onto the land a few blocks over the middle's ground or where they stood)
        let u = ease(HU_FLING, HU_FLING + DOWN, t);
        y += (self.c[1].max(l.y0) + 3.0 - y) * u;
        Some([self.c[0] + r * a.cos(), y, self.c[2] + r * a.sin()])
    }
    /// One tick, the strike `t` seconds in, the player's feet at `feet`.
    pub fn tick(&mut self, t: f64, feet: [f64; 3]) -> CarryTick {
        let mut out = CarryTick::default();
        if self.done {
            return out;
        }
        if self.lift.is_none() {
            let (dx, dz) = (feet[0] - self.c[0], feet[2] - self.c[2]);
            let d = dx.hypot(dz);
            let reached = hu_front_t(d).is_some_and(|f| t >= f);
            if t < HU_FLING - 4.0 && reached && d > HU_R_EYE + 4.0 && d <= CARRY_R {
                self.lift = Some(Lift { t0: t, r0: d, y0: feet[1], a: dz.atan2(dx) });
                out.cmds.push(format!("effect give @s minecraft:slow_falling {} 0 true", (HU_FLING + DOWN - t + 14.0).ceil() as i32));
                self.next_whoosh = t + 0.4;
            } else {
                return out;
            }
        }
        if t > HU_FLING + DOWN {
            self.done = true;
            return out;
        }
        // (turned on round the middle with the wind where they are, a little behind it)
        let Some(l) = &mut self.lift else { return out };
        let r = Self::radius(l, t);
        l.a += 0.8 * -1.0 * hu_omega(r) * hu_spin(t) * 0.05;
        let a = l.a;
        let Some(next) = self.at(t + 0.05, a) else { return out };
        self.target = Some(next);
        let want = [next[0] - feet[0], next[1] - feet[1], next[2] - feet[2]];
        out.kicks = self.drive.kicks(feet, want);
        // (the debris rushing past them)
        if t >= self.next_whoosh && t < HU_FLING + 2.0 {
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
    use crate::follow::{VMAX, drag};

    /// A player as the game moves them (their velocity, the kicks added, moved, then the air's drag and gravity, or
    /// slow falling's), standing on flat land at `ground` unless carried off it.
    fn carry(start: [f64; 3], flying: bool) -> (f64, f64, f64, f64, [f64; 3]) {
        let c = [0.5, 65.0, 0.5];
        let mut k = Carry::new(c);
        let (mut feet, mut v) = (start, [0.0f64; 3]);
        let (mut fastest, mut off, mut high) = (0.0f64, 0.0f64, 0.0f64);
        let mut lifted_at = None;
        for n in 1..=(64 * 20) {
            let t = f64::from(n) * 0.05;
            feet = [feet[0] + v[0], feet[1] + v[1], feet[2] + v[2]];
            let falling = v[1] <= 0.0;
            v = drag(v, flying);
            // (slow falling: its gravity an eighth of the air's, once they fall)
            if !flying && k.lifted() && falling {
                v[1] += 0.07 * 0.98;
            }
            if feet[1] < 65.0 {
                feet[1] = 65.0;
                v[1] = 0.0;
            }
            let o = k.tick(t, feet);
            if k.lifted() && lifted_at.is_none() {
                lifted_at = Some(t);
            }
            for kick in &o.kicks {
                assert!(kick.iter().all(|x| x.abs() <= 4.0));
                v = [v[0] + f64::from(kick[0]), v[1] + f64::from(kick[1]), v[2] + f64::from(kick[2])];
            }
            fastest = fastest.max(v.iter().fold(0.0f64, |a, x| a.max(x.abs())));
            if let Some(w) = k.target
                && k.lifted()
                && t > lifted_at.unwrap_or(0.0) + 0.5
            {
                off = off.max(((feet[0] + v[0] - w[0]).powi(2) + (feet[1] + v[1] - w[1]).powi(2) + (feet[2] + v[2] - w[2]).powi(2)).sqrt());
            }
            high = high.max(feet[1] - 65.0);
        }
        (lifted_at.unwrap_or(-1.0), fastest, off, high, feet)
    }

    #[test]
    fn the_wind_carries_the_player_round_and_puts_them_down() {
        for (start, flying) in [([120.0, 65.0, 0.5], false), ([0.5, 65.0, -160.0], true), ([45.0, 65.0, 30.0], false)] {
            let (at, fastest, off, high, end) = carry(start, flying);
            eprintln!("from {start:?} flying {flying}: picked up at {at:.2} s, at most {fastest:.2} blocks a tick, {off:.2} off its path, {high:.0} up, down at {end:?}");
            let d = (start[0] - 0.5).hypot(start[2] - 0.5);
            assert!((at - hu_front_t(d).unwrap()).abs() < 0.11, "picked up at {at}");
            // (never near the speed the game's collision sweep can't take: a block or two a tick)
            assert!(fastest < VMAX * 0.25, "{fastest} blocks a tick");
            assert!(off < 2.0, "{off} off its path");
            assert!(high > 35.0, "only {high} up");
            // (put down near the ground, a long way round from where they stood but within the land loaded round them)
            assert!(end[1] < 65.0 + 4.5, "left {} up", end[1] - 65.0);
            assert!((end[0] - start[0]).hypot(end[2] - start[2]) < 400.0);
        }
        // (in the calm of the eye, or far out, never picked up)
        for start in [[10.0, 65.0, 10.0], [0.5, 65.0, 300.0]] {
            let (at, fastest, _, high, _) = carry(start, false);
            assert!(at < 0.0 && fastest < 0.1 && high < 1e-9, "{start:?}");
        }
    }
}
