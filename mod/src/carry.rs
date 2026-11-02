//! The Hurricane's carry: a player the wind reaches is picked up and carried round the storm with the debris, then put
//! back down as it drops. With the KNOCKBACK switch off (`/orbital knockback off`) they are left standing.
//!
//! It moves them as the follow camera does (follow.rs's `Drive`): a kick to their velocity each tick
//! (`world.push-player`) that lands them on the next point of their path, the game's own movement carrying them and its
//! frame interpolation drawing it smoothly; never faster than follow.rs's VMAX (24 blocks a tick on any axis: a bigger
//! move crashed the game's collision sweep), and in practice a block or two a tick. Their path: as the wind's front
//! reaches where they stand (none in the calm eye, none past CARRY_R), drawn in towards ORBIT_R round the middle and
//! lifted ORBIT_H over its ground, turning with the wind (most of its speed there: the debris overtakes them),
//! buffeted; then, as the storm peaks (EYE0 to EYE1), drawn in through the eyewall into the calm of the eye, EYE_R
//! from the middle and EYE_H up: sudden stillness, blue sky and sunlight straight down the stadium all round them;
//! from the fling (HU_FLING) thrown back out through the far eyewall with everything else and let down over DOWN
//! seconds onto the land past it, a few blocks over the middle's ground, then let go. Slow falling is given as they
//! are picked up, for long enough to see them down, so however they come down (a hill under them, a valley, the
//! strike stopped) they land softly.
//!
//! A player can break free by flying: the carry lets go at once (no more kicks, a gust's whoosh; the slow falling
//! kept, harmless) when the controller sees them take to the air themselves (`Drive::flight`: their moves up and down
//! turning from a fall's, slow falling's or not, to flight's, after it had seen them fall: a player already flying
//! when picked up isn't let go for flying alone), or steer hard against it for a quarter of a second (their own
//! flight at a raised fly speed). Ticks they are held still while their chunk loads count for neither. Once free they
//! are left alone while they fly; if they come back down and stand on the land while the wind still blows there, it
//! picks them up again.
#![cfg_attr(not(test), allow(dead_code))]
use crate::follow::Drive;
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

/// How many ticks running a player must steer against the carry, and how hard (blocks a tick off what it expected), to
/// break free.
const STEER_TICKS: u32 = 5;
const STEER: f64 = 0.4;

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
    /// Broken free (flying), and since when they have stood still on the land (to be picked up again).
    free: bool,
    seen_fall: bool,
    steer: u32,
    last: Option<[f64; 3]>,
    stood: u32,
    /// When they broke free, for the tests.
    pub freed_at: Option<f64>,
}

fn ease(a: f64, b: f64, t: f64) -> f64 {
    let x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    x * x * x * (x * (6.0 * x - 15.0) + 10.0)
}

impl Carry {
    pub fn new(c: [f64; 3]) -> Carry {
        Carry { c, lift: None, drive: Drive::default(), done: false, next_whoosh: 0.0, n: 0, target: None, free: false, seen_fall: false, steer: 0, last: None, stood: 0, freed_at: None }
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
        ease(e0, EYE1.max(e0 + 3.5), t)
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
            self.drive = Drive::default();
            self.seen_fall = false;
            self.steer = 0;
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
        // (the eye calm: hardly turning in it)
        let calm = 0.15 + 0.85 * ((r - HU_R_EYE) / 30.0).clamp(0.0, 1.0);
        l.a += 0.8 * -1.0 * hu_omega(r) * hu_spin(t) * 0.05 * calm;
        let a = l.a;
        let Some(next) = self.at(t + 0.05, a) else { return out };
        self.target = Some(next);
        let want = [next[0] - feet[0], next[1] - feet[1], next[2] - feet[2]];
        let kicks = self.drive.kicks(feet, want);
        // (breaking free: flying where it had seen them fall, or steering hard against it)
        let (flight, miss) = self.drive.flight();
        self.seen_fall |= flight <= -2;
        let moved = self.last.is_none_or(|l| l != feet);
        self.last = Some(feet);
        if moved {
            self.steer = if miss > STEER { self.steer + 1 } else { 0 };
        }
        if (self.seen_fall && flight >= 2) || self.steer >= STEER_TICKS {
            self.free = true;
            self.freed_at = Some(t);
            self.stood = 0;
            out.sounds.push(("orbital:hurricane.whoosh2".into(), 0.9, 0.75));
            out.sounds.push(("orbital:hurricane.whoosh4".into(), 0.7, 1.1));
            return out;
        }
        out.kicks = kicks;
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
    use crate::follow::{VMAX, drag};

    /// A player as the game moves them (their velocity, the kicks added, moved, then the air's drag and gravity, or
    /// slow falling's), standing on flat land at `ground` unless carried off it.
    fn carry(start: [f64; 3], flying: bool) -> (f64, f64, f64, f64, [f64; 3], f64) {
        let c = [0.5, 65.0, 0.5];
        let mut k = Carry::new(c);
        let (mut feet, mut v) = (start, [0.0f64; 3]);
        let (mut fastest, mut off, mut high) = (0.0f64, 0.0f64, 0.0f64);
        let mut lifted_at = None;
        let mut eye_at = f64::MAX;
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
            if (t - 44.0).abs() < 0.03 {
                eye_at = (feet[0] - c[0]).hypot(feet[2] - c[2]);
            }
        }
        (lifted_at.unwrap_or(-1.0), fastest, off, high, feet, eye_at)
    }

    /// A carried player who takes to the air themselves at `fly_at` (none: never), held still (their chunk not
    /// loaded) over the ticks `hold` says: when the carry let them go, and how high they were then.
    fn breaks_free(start: [f64; 3], fly_at: f64, hold: impl Fn(f64) -> bool) -> (Option<f64>, f64) {
        let mut k = Carry::new([0.5, 65.0, 0.5]);
        let (mut feet, mut v) = (start, [0.0f64; 3]);
        let mut flying = false;
        for n in 1..=(64 * 20) {
            let t = f64::from(n) * 0.05;
            if t >= fly_at && !flying {
                flying = true;
            }
            if !hold(t) {
                feet = [feet[0] + v[0], feet[1] + v[1], feet[2] + v[2]];
                let falling = v[1] <= 0.0;
                v = drag(v, flying);
                if !flying && k.lifted() && falling {
                    v[1] += 0.07 * 0.98;
                }
                if feet[1] < 65.0 {
                    feet[1] = 65.0;
                    v[1] = 0.0;
                }
            }
            let o = k.tick(t, feet);
            for kick in &o.kicks {
                v = [v[0] + f64::from(kick[0]), v[1] + f64::from(kick[1]), v[2] + f64::from(kick[2])];
            }
            if let Some(f) = k.freed_at {
                // (let go: no kick from then on, and the gust heard as it happens)
                assert!(o.kicks.is_empty());
                if (t - f).abs() < 1e-9 {
                    assert!(o.sounds.iter().any(|s| s.0.contains("whoosh")));
                }
            }
            if k.freed_at.is_some() && t > k.freed_at.unwrap() + 1.0 {
                return (k.freed_at, feet[1] - 65.0);
            }
        }
        (k.freed_at, feet[1] - 65.0)
    }

    #[test]
    fn a_carried_player_who_flies_breaks_free_and_one_held_still_does_not() {
        for fly_at in [24.0, 31.3, 36.0, 43.0] {
            let (freed, up) = breaks_free([45.0, 65.0, 30.0], fly_at, |_| false);
            let f = freed.unwrap_or_else(|| panic!("flying at {fly_at}: never let go"));
            eprintln!("flying at {fly_at}: let go at {f:.2} s ({:.0} ticks), {up:.0} up", (f - fly_at) / 0.05);
            assert!(f >= fly_at && f - fly_at <= 0.3, "flying at {fly_at}: let go at {f}");
        }
        // (held still a tick or several at a time while their chunk loads, never flying: carried on, never let go)
        let (freed, _) = breaks_free([45.0, 65.0, 30.0], f64::MAX, |t| (t * 20.0) as u32 % 37 < 6 || (25.0..25.6).contains(&t));
        assert!(freed.is_none(), "let go at {freed:?} while held still");
        let (freed, _) = breaks_free([120.0, 65.0, 0.5], f64::MAX, |_| false);
        assert!(freed.is_none(), "let go at {freed:?} without flying");
    }

    #[test]
    fn the_wind_carries_the_player_round_and_puts_them_down() {
        for (start, flying) in [([120.0, 65.0, 0.5], false), ([0.5, 65.0, -160.0], true), ([45.0, 65.0, 30.0], false)] {
            let (at, fastest, off, high, end, eye_at) = carry(start, flying);
            eprintln!("from {start:?} flying {flying}: picked up at {at:.2} s, at most {fastest:.2} blocks a tick, {off:.2} off its path, {high:.0} up, down at {end:?}");
            let d = (start[0] - 0.5).hypot(start[2] - 0.5);
            assert!((at - hu_front_t(d).unwrap()).abs() < 0.11, "picked up at {at}");
            // (never near the speed the game's collision sweep can't take: a block or two a tick)
            assert!(fastest < VMAX * 0.25, "{fastest} blocks a tick");
            assert!(off < 2.0, "{off} off its path");
            assert!(high > 35.0, "only {high} up");
            // (in the eye's calm at the storm's height)
            assert!(eye_at < HU_R_EYE, "only {eye_at:.1} from the middle at 44 s");
            // (put down near the ground, a long way round from where they stood but within the land loaded round them)
            assert!(end[1] < 65.0 + 4.5, "left {} up", end[1] - 65.0);
            assert!((end[0] - start[0]).hypot(end[2] - start[2]) < 400.0);
        }
        // (in the calm of the eye, or far out, never picked up)
        for start in [[10.0, 65.0, 10.0], [0.5, 65.0, 300.0]] {
            let (at, fastest, _, high, _, _) = carry(start, false);
            assert!(at < 0.0 && fastest < 0.1 && high < 1e-9, "{start:?}");
        }
    }
}
