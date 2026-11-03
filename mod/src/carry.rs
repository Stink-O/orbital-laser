//! The Hurricane's carry: a player the wind reaches is picked up and carried round the storm with the debris, round
//! and round the eyewall, then thrown out as it flings everything. With the KNOCKBACK switch off (`/orbital knockback
//! off`) they are left standing.
//!
//! It carries them through the fork's `world.carry-player`: each tick their move in place of their own (the game's
//! collision move, no gravity, no drag, their fall distance kept at nothing, out of creative flight and any glide),
//! drawn smoothly between ticks as a ride is, and a turn of their view spread over the tick's frames. Never faster
//! than a few blocks a tick (the game clamps each axis to 4; follow.rs's VMAX, 24, is where its collision sweep gave
//! out). Their path: as the wind's front reaches where they stand (none in the calm eye, none past CARRY_R), lifted
//! off the land, eased into the spin (no snap from still to fast) and drawn in towards ORBIT_R round the middle,
//! ORBIT_H over its ground, turning with the wind (most of its speed there: the debris overtakes them), buffeted by
//! slow gusts, never drawn into the eye; at the fling (HU_FLING) swept out, faster and faster, round with the wind, out
//! and up, and over THROW seconds into the throw
//! (THROW_V: out, round with the wind, up), then let go with it (`world.push-player` while carried is the throw the
//! game lets them go with): the game's own physics from there, falling where it throws them. A player who may not
//! fly is given a few seconds of Resistance V as they are thrown, so the landing does not kill them outright. Their
//! view turns a little with them round the storm and sways with the gusts (CARRY_TURN of the turn round it;
//! `/orbital carryview still` keeps it their own).
//!
//! Only a deliberate break-free lets go (the game decides: sneak held half a second; a tap of sneak, a jump or a
//! double jump does nothing while carried): the next carry answers false and the carry lets go at once (a gust's
//! whoosh); the game leaves them only a little of the carry's motion and puts a creative player back into flight. One
//! already flying, standing, falling, gliding or swimming when the wind reaches them is picked up all the same. Free,
//! they are left alone while they fly (the game's own flying, `game.player-flying`): flying away is the way out; once
//! they stop flying (landed, or out of flight in mid-air) for REARM seconds, still in the wind's reach while it blows,
//! it picks them up again, eased in afresh, as often as they break free. Ticks they are held still while their chunk
//! loads keep the carry where it was.
#![cfg_attr(not(test), allow(dead_code))]
use crate::strike::{HU_FLING, HU_R_EYE, hu_front_t, hu_omega, hu_spin};

/// How far out the wind picks the player up, and the orbit it carries them on (out from the middle, up over its
/// ground).
pub const CARRY_R: f64 = 175.0;
pub const ORBIT_R: f64 = 108.0;
pub const ORBIT_H: f64 = 50.0;
/// From the fling, how long they are swept out before they are let go, and the throw they are let go with (blocks a
/// tick: out from the middle, round with the wind, up).
pub const THROW: f64 = 1.4;
pub const THROW_V: [f64; 3] = [2.1, 2.2, 0.95];
/// How much of their turn round the storm their view turns with them (the rest: they see it swing past), the most it
/// turns a tick (degrees), and how far the gusts sway it (degrees).
pub const CARRY_TURN: f64 = 0.55;
const TURN_MAX: f64 = 1.5;
const SWAY: f64 = 2.5;

/// What a tick of the carry does: the move to carry the player by (blocks, this tick) and the turn of their view
/// (degrees of yaw, over the tick), the throw to let them go with (`world.push-player`, blocks a tick) and the commands
/// to run as it is, the sounds to play (event, volume, pitch).
#[derive(Default)]
pub struct CarryTick {
    pub carry: Option<[f32; 3]>,
    pub turn: f32,
    pub throw: Option<[f32; 3]>,
    pub cmds: Vec<String>,
    pub sounds: Vec<(String, f32, f32)>,
}

/// The most it carries them a tick on any axis (the game's own clamp is 4).
const STEP: f64 = 3.5;
/// Broken free, how long they must be out of flight before the wind can have them again (ticks).
const REARM: u32 = 20;

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
    /// Broken free, and for how many ticks running they have been out of flight since (to be picked up again).
    free: bool,
    last: Option<[f64; 3]>,
    grounded: u32,
    /// Whether a carry was asked for one and two ticks ago (the game's answer, `world.carry-player`'s, is about the
    /// one asked two ticks ago: the mod hears it as it asks the next).
    asked: [bool; 2],
    /// The sway of their view last tick (degrees).
    sway: f64,
    /// When they broke free, and when and with what they were thrown, for the tests.
    pub freed_at: Option<f64>,
    pub thrown: Option<(f64, [f64; 3])>,
}

fn ease(a: f64, b: f64, t: f64) -> f64 {
    let x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    x * x * x * (x * (6.0 * x - 15.0) + 10.0)
}
/// A step from 0 to 1 with no kick at its start (a critically damped approach, `k` seconds its time constant).
fn approach(tau: f64, k: f64) -> f64 {
    let x = tau.max(0.0) / k;
    1.0 - (1.0 + x) * (-x).exp()
}

impl Carry {
    pub fn new(c: [f64; 3]) -> Carry {
        Carry { c, lift: None, done: false, next_whoosh: 0.0, n: 0, target: None, free: false, last: None, grounded: 0, asked: [false; 2], sway: 0.0, freed_at: None, thrown: None }
    }
    /// Whether it is over (the player thrown, or never picked up and the wind dropping).
    pub fn over(&self, t: f64) -> bool {
        self.done || (self.lift.is_none() && t > HU_FLING - 4.0)
    }
    pub fn lifted(&self) -> bool {
        self.lift.is_some() && !self.done && !self.free
    }
    /// How hard the wind has them at `t` (0 still, 1 in its full spin): eased in as they are picked up.
    fn grip(l: &Lift, t: f64) -> f64 {
        ease(0.0, 2.5, (t - l.t0).max(0.0))
    }
    /// How far out from the middle they are carried at `t`.
    fn radius(l: &Lift, t: f64) -> f64 {
        let tau = (t - l.t0).max(0.0);
        let buffet = (1.6 * (2.3 * tau + 0.7).sin() + 0.8 * (4.1 * tau + 2.0).sin()) * ease(0.0, 2.5, tau);
        l.r0 + (ORBIT_R - l.r0) * approach(tau, 3.0) + buffet
    }
    /// Where their feet should be at `t` (once they are picked up), at angle `a` round the middle.
    fn at(&self, t: f64, a: f64) -> Option<[f64; 3]> {
        let l = self.lift.as_ref()?;
        let tau = (t - l.t0).max(0.0);
        let r = Self::radius(l, t);
        let rise = approach(tau, 1.8);
        let gust = (5.0 * (0.7 * tau).sin() + 1.5 * (1.9 * tau).sin() + 0.6 * (3.1 * tau + 1.0).sin()) * ease(0.0, 2.5, tau);
        let peak = self.c[1] + ORBIT_H + gust;
        let y = l.y0 + (peak - l.y0) * rise;
        Some([self.c[0] + r * a.cos(), y, self.c[2] + r * a.sin()])
    }
    /// The throw at angle `a` round the middle (blocks a tick): out, round with the wind (the way the angle falls), up.
    fn throw_at(a: f64) -> [f64; 3] {
        let (c, s) = (a.cos(), a.sin());
        let [o, w, u] = THROW_V;
        [o * c + w * s, u, o * s - w * c]
    }
    /// One tick, the strike `t` seconds in, the player's feet at `feet`; `held`: the game's last answer (about the
    /// carry asked two ticks ago; false: they broke free); `flying`: whether the game has them flying; `turn`: whether
    /// their view turns with them.
    pub fn tick(&mut self, t: f64, feet: [f64; 3], held: bool, flying: bool, turn: bool) -> CarryTick {
        let mut out = CarryTick::default();
        if self.done {
            return out;
        }
        let asked = self.asked[1];
        self.asked = [false, self.asked[0]];
        // (free: left alone while they fly; out of flight a second running (landed, or stopped flying in mid-air),
        // the wind may have them again: picked up afresh below if it still blows where they are)
        if self.free {
            self.grounded = if flying { 0 } else { self.grounded + 1 };
            self.last = Some(feet);
            if self.grounded < REARM {
                return out;
            }
            self.free = false;
            self.lift = None;
            self.asked = [false; 2];
        }
        if self.lift.is_none() {
            let (dx, dz) = (feet[0] - self.c[0], feet[2] - self.c[2]);
            let d = dx.hypot(dz);
            let reached = hu_front_t(d).is_some_and(|f| t >= f);
            if t < HU_FLING - 4.0 && reached && d > HU_R_EYE + 4.0 && d <= CARRY_R {
                self.lift = Some(Lift { t0: t, r0: d, y0: feet[1], a: dz.atan2(dx) });
                self.next_whoosh = t + 0.4;
                self.sway = 0.0;
            } else {
                return out;
            }
        } else if asked && !held {
            // (broken free: sneak held; let go at once, the gust heard)
            self.free = true;
            self.freed_at = Some(t);
            self.grounded = 0;
            self.last = Some(feet);
            out.sounds.push(("orbital:hurricane.whoosh2".into(), 0.9, 0.75));
            out.sounds.push(("orbital:hurricane.whoosh4".into(), 0.7, 1.1));
            return out;
        }
        self.last = Some(feet);
        let Some(l) = &mut self.lift else { return out };
        // (thrown: let go with the throw, no carry asked, the game's physics from here; spared the landing's worst)
        if t >= HU_FLING + THROW {
            let v = Self::throw_at(l.a);
            self.done = true;
            self.thrown = Some((t, v));
            out.throw = Some([v[0] as f32, v[1] as f32, v[2] as f32]);
            out.cmds.push("effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:resistance 12 4 true".into());
            out.sounds.push(("orbital:hurricane.whoosh1".into(), 1.0, 0.7));
            out.sounds.push(("orbital:hurricane.whoosh3".into(), 0.8, 0.95));
            return out;
        }
        // (turned on round the middle with the wind where they are, a little behind it, eased in as they are picked up)
        let r = Self::radius(l, t);
        let tau = (t - l.t0).max(0.0);
        let da = 0.8 * -1.0 * hu_omega(r) * hu_spin(t) * 0.05 * ease(0.0, 2.5, tau);
        l.a += da;
        let a = l.a;
        let grip = Self::grip(l, t);
        let Some(next) = self.at(t + 0.05, a) else { return out };
        self.target = Some(next);
        let mut want = [next[0] - feet[0], next[1] - feet[1], next[2] - feet[2]];
        // (swept out from the fling: more and more of the throw in place of the orbit, so they leave with it)
        let k = ease(HU_FLING, HU_FLING + THROW, t + 0.05);
        if k > 0.0 {
            let v = Self::throw_at(a);
            for i in 0..3 {
                want[i] = want[i] * (1.0 - k) + v[i] * k;
            }
        }
        let m = want.iter().fold(0.0f64, |m, v| m.max(v.abs()));
        let s = if m > STEP { STEP / m } else { 1.0 };
        out.carry = Some([(want[0] * s) as f32, (want[1] * s) as f32, (want[2] * s) as f32]);
        self.asked[0] = true;
        // (their view: turned with a share of their turn round the storm (yaw grows as the angle round it does), and
        // swayed by the gusts, both as hard as the wind has them)
        if turn {
            let sway = SWAY * ((0.8 * tau).sin() + 0.45 * (1.9 * tau + 1.0).sin()) * grip;
            let w = CARRY_TURN * da.to_degrees() + (sway - self.sway);
            self.sway = sway;
            out.turn = w.clamp(-TURN_MAX, TURN_MAX) as f32;
        }
        // (the debris rushing past them)
        if t >= self.next_whoosh && t < HU_FLING + THROW {
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

    /// The land, flat at 65.
    const LAND: f64 = 65.0;
    /// The game's part, as the fork plays a carry (`MotionWorld::carry_step`): moved by the carry (colliding with the
    /// land, no gravity, their fall distance nothing, out of flight) unless they broke free (sneak held CARRY_BREAK
    /// ticks running) or none is asked; let go (broken free or none asked after one), a little of the carry's motion
    /// kept and back into flight if they may fly and are off the land, or thrown with exactly a push made while it
    /// held them; else their own motion (the air's drag and gravity, or flight's).
    struct Game {
        feet: [f64; 3],
        v: [f64; 3],
        flying: bool,
        may_fly: bool,
        asked: bool,
        free: bool,
        sneak: u32,
        throw: Option<[f64; 3]>,
    }
    const CARRY_BREAK: u32 = 10;
    const KEEP: f64 = 0.45;
    impl Game {
        fn release(&mut self) {
            let across = self.v[0].hypot(self.v[2]);
            let k = if across * 0.35 > KEEP { KEEP / across } else { 0.35 };
            self.v = [self.v[0] * k, (self.v[1] * 0.3).clamp(-0.3, 0.1), self.v[2] * k];
            if self.may_fly && self.feet[1] > LAND + 1e-6 {
                self.flying = true;
            }
        }
        /// A push from the mod (`world.push-player`): the throw while a carry holds them.
        fn push(&mut self, p: [f32; 3]) {
            let p = p.map(f64::from);
            if self.asked && !self.free {
                self.throw = Some(p);
            } else {
                self.v = [self.v[0] + p[0], self.v[1] + p[1], self.v[2] + p[2]];
            }
        }
        /// Their tick; whether the carry held them.
        fn tick(&mut self, carry: Option<[f32; 3]>, sneaking: bool) -> bool {
            let was = std::mem::replace(&mut self.asked, carry.is_some());
            let held = match carry {
                None => {
                    if was && !self.free {
                        match self.throw.take() {
                            Some(v) => {
                                self.v = v;
                                self.flying = false;
                            }
                            None => self.release(),
                        }
                    }
                    self.free = false;
                    self.sneak = 0;
                    false
                }
                Some(d) => {
                    if !was {
                        self.free = false;
                        self.sneak = 0;
                    }
                    if self.free {
                        false
                    } else {
                        self.sneak = if sneaking { self.sneak + 1 } else { 0 };
                        if self.sneak >= CARRY_BREAK {
                            self.free = true;
                            self.release();
                            false
                        } else {
                            self.flying = false;
                            let d = d.map(f64::from);
                            self.feet = [self.feet[0] + d[0], (self.feet[1] + d[1]).max(LAND), self.feet[2] + d[2]];
                            self.v = d;
                            true
                        }
                    }
                }
            };
            if !held {
                self.feet = [self.feet[0] + self.v[0], self.feet[1] + self.v[1], self.feet[2] + self.v[2]];
                self.v = drag(self.v, self.flying);
                if self.feet[1] <= LAND {
                    self.feet[1] = LAND;
                    self.v = [self.v[0] * 0.546, 0.0, self.v[2] * 0.546];
                    self.flying = false;
                }
            }
            held
        }
    }

    /// What a run did: when they were picked up, broke free or were thrown (and with what), how fast they were carried
    /// and how sharply it changed (blocks a tick, and a tick on a tick: overall and as picked up), how far off its
    /// path, how high, how far from the middle at 45.7 s and how far they moved over the second before (`eye_at`, `eye_moved`), the most their
    /// view turned a tick and in all, how fast they went after breaking free, whether they were flying at the end, and
    /// how far from the middle they came down.
    struct Run {
        lifted_at: f64,
        freed_at: Option<f64>,
        thrown: Option<(f64, [f64; 3])>,
        fastest: f64,
        jerk: f64,
        jerk_pickup: f64,
        off: f64,
        high: f64,
        eye_at: f64,
        eye_moved: f64,
        turn_max: f64,
        turned: f64,
        after_free_v: f64,
        flying_after: bool,
        landed_r: f64,
        /// Every time they were picked up, and broke free.
        pickups: Vec<f64>,
        frees: Vec<f64>,
    }
    struct Opts {
        flying0: bool,
        may_fly: bool,
        /// Sneak held over these times.
        sneak: fn(f64) -> bool,
        hold: fn(f64) -> bool,
        turn: bool,
        /// Out of flight at these times if flying: Some(true) landing (feet put on the land), Some(false) where they are.
        stop_flying: fn(f64) -> Option<bool>,
        /// Carried on to the end even once free (for the re-grabs).
        whole: bool,
    }
    const PLAIN: Opts = Opts { flying0: false, may_fly: true, sneak: |_| false, hold: |_| false, turn: true, stop_flying: |_| None, whole: false };

    fn carry(start: [f64; 3], o: &Opts) -> Run {
        let c = [0.5, 65.0, 0.5];
        let mut k = Carry::new(c);
        let mut g = Game { feet: start, v: [0.0; 3], flying: o.flying0, may_fly: o.may_fly, asked: false, free: false, sneak: 0, throw: None };
        let mut pending: Option<[f32; 3]> = None;
        let mut held = true;
        let mut heard = true;
        let mut run = Run { lifted_at: -1.0, freed_at: None, thrown: None, fastest: 0.0, jerk: 0.0, jerk_pickup: 0.0, off: 0.0, high: 0.0, eye_at: f64::MAX, eye_moved: 0.0, turn_max: 0.0, turned: 0.0, after_free_v: 0.0, flying_after: false, landed_r: 0.0, pickups: Vec::new(), frees: Vec::new() };
        let mut last_d: Option<[f64; 3]> = None;
        let mut eye_from = None;
        let mut was_lifted = false;
        let mut last_free = None;
        for n in 1..=(70 * 20) {
            let t = f64::from(n) * 0.05;
            if !(o.hold)(t) {
                let carry = pending.take();
                held = g.tick(carry, (o.sneak)(t));
                if let Some(d) = carry.filter(|_| held) {
                    let d = d.map(f64::from);
                    run.fastest = run.fastest.max(d.iter().fold(0.0f64, |a, x| a.max(x.abs())));
                    if let Some(p) = last_d {
                        let j = ((d[0] - p[0]).powi(2) + (d[1] - p[1]).powi(2) + (d[2] - p[2]).powi(2)).sqrt();
                        run.jerk = run.jerk.max(j);
                        if t < run.lifted_at + 1.5 {
                            run.jerk_pickup = run.jerk_pickup.max(j);
                        }
                    }
                    last_d = Some(d);
                } else {
                    last_d = None;
                }
            }
            // (where they are against where the last tick sent them)
            if let Some(w) = k.target
                && k.lifted()
                && t > run.lifted_at + 0.5
                && t < HU_FLING
                && !(o.hold)(t)
            {
                run.off = run.off.max(((g.feet[0] - w[0]).powi(2) + (g.feet[1] - w[1]).powi(2) + (g.feet[2] - w[2]).powi(2)).sqrt());
            }
            if let Some(f) = (o.stop_flying)(t)
                && g.flying
            {
                // (out of flight: landed (feet on the land) or stopped flying where they are)
                g.flying = false;
                if f {
                    g.feet[1] = LAND;
                    g.v = [0.0; 3];
                }
            }
            let out = k.tick(t, g.feet, heard, g.flying, o.turn);
            if k.lifted() && !was_lifted {
                run.pickups.push(t);
            }
            was_lifted = k.lifted();
            if k.freed_at.is_some() && k.freed_at != last_free {
                last_free = k.freed_at;
                run.frees.push(t);
            }
            heard = held;
            if let Some(p) = out.throw {
                g.push(p);
                assert!(out.carry.is_none() && out.cmds.iter().any(|c| c.contains("resistance")));
                run.thrown = k.thrown;
            }
            if k.lifted() && run.lifted_at < 0.0 {
                run.lifted_at = t;
            }
            run.turn_max = run.turn_max.max(f64::from(out.turn).abs());
            run.turned += f64::from(out.turn);
            pending = out.carry;
            if let Some(f) = k.freed_at {
                assert!(out.carry.is_none() || t > f || k.lifted(), "carried on after breaking free");
                if run.freed_at.is_none() {
                    run.freed_at = Some(f);
                    assert!(out.sounds.iter().any(|s| s.0.contains("whoosh")), "no gust as they break free");
                }
                run.after_free_v = run.after_free_v.max(g.v[0].hypot(g.v[2])).max(g.v[1]);
            }
            run.high = run.high.max(g.feet[1] - 65.0);
            if (t - 44.7).abs() < 0.03 {
                eye_from = Some(g.feet);
            }
            if (t - 45.7).abs() < 0.03 {
                run.eye_at = (g.feet[0] - c[0]).hypot(g.feet[2] - c[2]);
                if let Some(e) = eye_from {
                    run.eye_moved = ((g.feet[0] - e[0]).powi(2) + (g.feet[1] - e[1]).powi(2) + (g.feet[2] - e[2]).powi(2)).sqrt();
                }
            }
            if !o.whole && k.freed_at.is_some_and(|f| t > f + 3.0) {
                break;
            }
        }
        run.flying_after = g.flying;
        run.landed_r = (g.feet[0] - c[0]).hypot(g.feet[2] - c[2]);
        run
    }

    /// `CARRY_OUT=path cargo test --release hu_write_carry_path -- --ignored`: a player standing 120 east of the middle
    /// carried as the game would carry them (`t x y z yaw` a tick, their feet and their view's turn so far), for an
    /// offscreen clip from their view.
    #[test]
    #[ignore]
    fn hu_write_carry_path() {
        let mut k = Carry::new([0.5, 65.0, 0.5]);
        let mut g = Game { feet: [120.0, 65.0, 0.5], v: [0.0; 3], flying: false, may_fly: true, asked: false, free: false, sneak: 0, throw: None };
        let mut yaw = 0.0f64;
        let mut out = String::new();
        let mut pending: Option<[f32; 3]> = None;
        for n in 1..=(64 * 20) {
            let t = f64::from(n) * 0.05;
            g.tick(pending.take(), false);
            let o = k.tick(t, g.feet, true, g.flying, true);
            if let Some(p) = o.throw {
                g.push(p);
            }
            pending = o.carry;
            yaw += f64::from(o.turn);
            out += &format!("{t:.3} {:.4} {:.4} {:.4} {yaw:.3}\n", g.feet[0], g.feet[1], g.feet[2]);
        }
        std::fs::write(std::env::var("CARRY_OUT").unwrap(), out).unwrap();
    }

    #[test]
    fn the_wind_carries_the_player_round_the_eyewall_and_throws_them() {
        for start in [[120.0, 65.0, 0.5], [0.5, 65.0, -160.0], [45.0, 65.0, 30.0]] {
            let r = carry(start, &PLAIN);
            eprintln!("from {start:?}: picked up at {:.2} s, at most {:.2} blocks a tick (changing by {:.3}, {:.3} as picked up), {:.2} off its path, {:.0} up, {:.1} from the middle at 45.7 s (moving {:.1} in the second before), thrown {:?}, down {:.0} from the middle, view turned {:.0} degrees (at most {:.2} a tick)", r.lifted_at, r.fastest, r.jerk, r.jerk_pickup, r.off, r.high, r.eye_at, r.eye_moved, r.thrown, r.landed_r, r.turned, r.turn_max);
            let d = (start[0] - 0.5).hypot(start[2] - 0.5);
            assert!((r.lifted_at - hu_front_t(d).unwrap()).abs() < 0.11, "picked up at {}", r.lifted_at);
            // (never near the speed the game's collision sweep can't take: a few blocks a tick)
            assert!(r.fastest <= STEP + 1e-6 && r.fastest < crate::follow::VMAX * 0.2, "{} blocks a tick", r.fastest);
            // (eased into the spin, no snap from still to fast; no sudden change of speed anywhere along it)
            assert!(r.jerk_pickup < 0.07, "picked up with a jolt of {} blocks a tick", r.jerk_pickup);
            assert!(r.jerk < 0.3, "a jolt of {} blocks a tick", r.jerk);
            assert!(r.off < 3.0, "{} off its path", r.off);
            assert!(r.high > 35.0, "only {} up", r.high);
            // (never drawn into the eye: round the eyewall in the wind to the last, moving with it)
            assert!(r.eye_at > HU_R_EYE + 40.0, "drawn in to {:.1} from the middle at 45.7 s", r.eye_at);
            assert!(r.eye_moved > 15.0, "moved only {} in the second before the fling", r.eye_moved);
            // (thrown out of it with real speed, out and up, then left to the game: landing well out)
            let (at, v) = r.thrown.expect("never thrown");
            assert!((at - (HU_FLING + THROW)).abs() < 0.06 && v[1] > 0.5 && v[0].hypot(v[2]) > 2.5, "thrown at {at} with {v:?}");
            assert!(r.landed_r > 60.0 && !r.flying_after, "came down {} from the middle", r.landed_r);
            // (their view turned with them round the storm, gently)
            assert!(r.turned.abs() > 30.0 && r.turn_max <= TURN_MAX + 1e-6, "turned {} (at most {} a tick)", r.turned, r.turn_max);
        }
        // (in the calm of the eye, or far out, never picked up)
        for start in [[10.0, 65.0, 10.0], [0.5, 65.0, 300.0]] {
            let r = carry(start, &PLAIN);
            assert!(r.lifted_at < 0.0 && r.high < 1e-9, "{start:?}");
        }
        // (their view left their own with `/orbital carryview still`)
        let r = carry([120.0, 65.0, 0.5], &Opts { turn: false, ..PLAIN });
        assert!(r.turn_max == 0.0);
    }

    #[test]
    fn only_sneak_held_breaks_free_and_gently() {
        // (taps of sneak, however many, and ticks held still while their chunk loads: carried on, never let go)
        let r = carry([45.0, 65.0, 30.0], &Opts { sneak: |t| (t * 20.0) as u32 % 23 < 7, hold: |t| (t * 20.0) as u32 % 37 < 6 || (25.0..25.6).contains(&t), ..PLAIN });
        assert!(r.freed_at.is_none() && r.thrown.is_some(), "let go at {:?} by taps of sneak", r.freed_at);
        // (sneak held half a second: let go, a gust heard; a creative player back in flight, not flung)
        for at in [24.0, 31.3, 36.0, 43.0] {
            let sneak: fn(f64) -> bool = match at as u32 {
                24 => |t| t >= 24.0,
                31 => |t| t >= 31.3,
                36 => |t| t >= 36.0,
                _ => |t| t >= 43.0,
            };
            let r = carry([45.0, 65.0, 30.0], &Opts { sneak, ..PLAIN });
            let f = r.freed_at.unwrap_or_else(|| panic!("sneaking from {at}: never let go"));
            eprintln!("sneaking from {at}: let go at {f:.2} s, going at most {:.2} after, flying {}", r.after_free_v, r.flying_after);
            assert!(f - at >= 0.45 && f - at <= 0.65, "sneaking from {at}: let go at {f}");
            assert!(r.after_free_v <= KEEP + 1e-6, "flung at {}", r.after_free_v);
            assert!(r.flying_after && r.thrown.is_none(), "dropped or thrown");
        }
        // (one who may not fly falls from there, with no fling up)
        let r = carry([45.0, 65.0, 30.0], &Opts { may_fly: false, sneak: |t| t >= 31.3, ..PLAIN });
        assert!(r.freed_at.is_some() && !r.flying_after && r.after_free_v <= KEEP + 1e-6);
    }

    #[test]
    fn broken_free_they_are_grabbed_again_once_out_of_flight_and_never_while_flying() {
        // (break free (back into flight), then land: grabbed again a second later, eased in)
        let r = carry([45.0, 65.0, 30.0], &Opts { sneak: |t| (24.0..24.6).contains(&t), stop_flying: |t| (t >= 26.0).then_some(true), whole: true, ..PLAIN });
        eprintln!("landed: picked up at {:?}, free at {:?}", r.pickups, r.frees);
        assert!(r.frees.len() == 1 && r.pickups.len() == 2, "picked up at {:?}", r.pickups);
        assert!((r.pickups[1] - 27.0).abs() < 0.2 && r.thrown.is_some(), "picked up again at {:?}", r.pickups);
        // (break free, then stop flying in mid-air: grabbed again as they fall)
        let r = carry([45.0, 65.0, 30.0], &Opts { sneak: |t| (24.0..24.6).contains(&t), stop_flying: |t| (t >= 25.5).then_some(false), whole: true, ..PLAIN });
        eprintln!("mid-air: picked up at {:?}, free at {:?}", r.pickups, r.frees);
        assert!(r.pickups.len() == 2 && (r.pickups[1] - 26.5).abs() < 0.2 && r.thrown.is_some(), "picked up at {:?}", r.pickups);
        // (a player who may not fly, falling once free: grabbed again as they fall)
        let r = carry([45.0, 65.0, 30.0], &Opts { may_fly: false, sneak: |t| (24.0..24.6).contains(&t), whole: true, ..PLAIN });
        assert!(r.pickups.len() == 2 && (r.pickups[1] - 25.5).abs() < 0.2, "picked up at {:?}", r.pickups);
        // (break free and keep flying: never grabbed again, never thrown)
        let r = carry([45.0, 65.0, 30.0], &Opts { sneak: |t| (24.0..24.6).contains(&t), whole: true, ..PLAIN });
        assert!(r.pickups.len() == 1 && r.thrown.is_none() && r.flying_after, "picked up at {:?}", r.pickups);
        // (again and again in one strike: three breaks, three re-grabs, each eased in, then thrown)
        let r = carry([45.0, 65.0, 30.0], &Opts { sneak: |t| [20.0, 27.0, 34.0].iter().any(|s| (*s..s + 0.6).contains(&t)), stop_flying: |t| [22.0, 29.0, 36.0].iter().any(|s| (*s..s + 0.05).contains(&t)).then_some(false), whole: true, ..PLAIN });
        eprintln!("again: picked up at {:?}, free at {:?}, worst jolt {:.3}", r.pickups, r.frees, r.jerk);
        assert!(r.frees.len() == 3 && r.pickups.len() == 4 && r.thrown.is_some(), "picked up at {:?}, free at {:?}", r.pickups, r.frees);
        assert!(r.jerk_pickup < 0.07);
    }

    #[test]
    fn a_player_flying_or_already_up_is_picked_up_and_carried() {
        // (hovering in creative flight, on the land or over it, when the wind reaches them: carried all the same,
        // round the storm and thrown, never let go as if they had broken free)
        for start in [[120.0, 65.0, 0.5], [120.0, 93.0, 0.5], [0.5, 80.0, -160.0]] {
            let r = carry(start, &Opts { flying0: true, ..PLAIN });
            let d = (start[0] - 0.5).hypot(start[2] - 0.5);
            assert!((r.lifted_at - hu_front_t(d).unwrap()).abs() < 0.11, "{start:?}: picked up at {}", r.lifted_at);
            assert!(r.freed_at.is_none() && r.thrown.is_some(), "{start:?}: let go at {:?}", r.freed_at);
            assert!(r.eye_at > HU_R_EYE + 40.0, "{start:?}: drawn in to {:.1} from the middle at 45.7 s", r.eye_at);
            assert!(r.jerk_pickup < 0.07, "{start:?}: picked up with a jolt of {}", r.jerk_pickup);
        }
    }
}
