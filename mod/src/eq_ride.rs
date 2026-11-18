//! The Earthquake's walk: a player on a moving plate walks, jumps and collides on it while it moves. The plates are only
//! drawn moved (the world warp); their real blocks stay where they were until the swap at EQ_REST. So the player stays
//! where the land really is and only the picture moves: each frame the camera is drawn from the displacement of the
//! plate under their real feet (`frame`, the fork's `render.set-view-offset`), the same the warp draws that plate with
//! (`EqPlates::drawn`), and the warp keeps that plate from rocking (params 13 and 14, `eq_rigid_param`), so feet and
//! ground agree. Stepping onto another plate (over a fault, or onto fixed land) the view eases onto it over EASE and the
//! plate left lets its rock back in over the same time.
//!
//! In flight nothing stands on a plate, so the view keeps the offset it has (`held`) instead of following the plate
//! under them: flying over a fault, or over a plate as it heaves, moves nothing. It is only kept within SLACK of that
//! plate's displacement a block of height over the land (past SKIM; the land's height from strike/eq_ground.rs's grid;
//! without it, none), so the drawn land never passes through them and they come down onto it where it is drawn: low
//! over a plate they ride it as a walker does. Out of flight again the view eases onto the plate under them.
//!
//! The land at rest is written behind the hold from EQ_LAND, the chunks round where the player really stands last (from
//! EQ_RIDER_FROM: strike/eq_land.rs). Before any of it goes in under them they are handed over (`tick`): put where they
//! are seen (`world.shift-player` by the view's offset, the offset 0 in the same call) and held there by the fork's
//! `world.carry-player` with their plate, as the Hurricane's and the Tsunami's carries hold (carry.rs, surge.rs): no
//! gravity, no fall distance, drawn smoothly. That is just before EQ_RIDER_FROM for anyone on a moved plate, or sooner
//! as soon as a chunk round them is due (they walked out of the land kept for last). They are let go once the real land
//! is swapped in at rest, standing on it where the drawn land had them; a small push keeps the game from putting a
//! creative player who was not flying back into flight. Sneak held half a second breaks free of the hold (the game
//! decides): left alone from then. One in flight at the hand-over is put where they are seen and not held at all: they
//! need no land under them. The terrain left alone (nothing written) the view follows the plates all strike long,
//! back home by EQ_BACK_END, and nobody is handed over. Nobody is killed: a survival player on a plate gets Resistance V
//! from the first heave.
#![cfg_attr(not(test), allow(dead_code))]
use crate::carry::CarryTick;
use crate::strike::{EQ_BACK_END, EQ_HEAVE, EQ_REST, EQ_RIDER_FROM, EqPlates};

/// The most it carries them a tick on any axis (the game's own clamp is 4).
const STEP: f64 = 3.5;
/// How soon before their plate's first heave Resistance V is given.
const LEAD: f64 = 0.1;
/// Moved further than this from where the carry put them, they were teleported.
const TELEPORT: f64 = 6.0;
/// How long the view takes to ease onto another plate, seconds.
pub const EASE: f64 = 0.25;
/// How soon before a chunk round them is due they are handed over (edits go in on their tick or later, never sooner).
const LOOK: f64 = 0.15;
/// How soon before the walker's chunks go in everyone on a moved plate is handed over.
const HAND: f64 = 0.15;
/// How far round their feet a chunk counts as theirs, blocks, and more by how far they moved the tick before.
const REACH: f64 = 2.0;
/// How far from their plate's displacement a flier's view may be, a block of height over the land past SKIM.
const SLACK: f64 = 0.5;
/// A flier this low over the land or lower rides the plate under them as a walker does, blocks.
const SKIM: f64 = 3.0;
/// The share of what a flier's view is out by that it closes a tick, and the least it closes, blocks (and all of what
/// the plate itself moved that tick).
const CLOSE: f64 = 0.35;
const CLOSE_MIN: f64 = 1.5;
/// Out of flight in the air the view eases onto the plate at this many blocks a second or faster.
const FALL: f64 = 40.0;
/// A tick, seconds.
const TICK: f64 = 0.05;

/// What the frame gives the game: the view's offset (`render.set-view-offset`) and the warp's params 13 and 14.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EqView {
    pub offset: [f64; 3],
    pub p13: f32,
    pub p14: f32,
}

/// One tick's asks: the carry's (`CarryTick`) and, at the hand-over, the shift (`world.shift-player`, with the view's
/// offset set to 0 in the same call).
#[derive(Default)]
pub struct RideTick {
    pub carry: CarryTick,
    pub shift: Option<[f64; 3]>,
}

pub struct EqRide {
    pl: EqPlates,
    /// The plate under their real feet (the view follows it), the one before it, and when it changed.
    cur: Option<usize>,
    prev: Option<usize>,
    since: f64,
    /// The view's offset less `cur`'s displacement when it changed (or as they came out of flight), eased away over
    /// `gap_dur` from `gap_since`.
    gap: [f64; 3],
    gap_since: f64,
    gap_dur: f64,
    /// In flight: the view's offset is `held`, at `held_t` and a tick on (the frames between go from one to the other).
    fly: bool,
    held: [[f64; 3]; 2],
    held_t: f64,
    /// Where they really stood as they were handed over (their plate's land at home), and the plate.
    anchor: Option<[f64; 3]>,
    /// Their feet the tick before (how far they move a tick).
    last: Option<[f64; 3]>,
    resisted: bool,
    /// Whether they were flying when handed over: only they go back to it as it lets go.
    flew: bool,
    free: bool,
    done: bool,
    asked: [bool; 2],
    /// Where the last carry was to put their feet.
    expect: Option<[f64; 3]>,
    pub handed_at: Option<f64>,
    pub freed_at: Option<f64>,
    pub left_at: Option<f64>,
}

fn ease(u: f64) -> f64 {
    let u = u.clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}

impl EqRide {
    /// The walk of a strike's plates, for the player wherever they stand.
    pub fn new(pl: EqPlates) -> EqRide {
        EqRide {
            pl,
            cur: None,
            prev: None,
            since: f64::NEG_INFINITY,
            gap: [0.0; 3],
            gap_since: f64::NEG_INFINITY,
            gap_dur: EASE,
            fly: false,
            held: [[0.0; 3]; 2],
            held_t: f64::NEG_INFINITY,
            anchor: None,
            last: None,
            resisted: false,
            flew: false,
            free: false,
            done: false,
            asked: [false; 2],
            expect: None,
            handed_at: None,
            freed_at: None,
            left_at: None,
        }
    }
    /// Whether it is over (let go, or the strike's end near).
    pub fn over(&self, t: f64) -> bool {
        self.done || t > f64::from(crate::lasers::EARTHQUAKE.length) - 0.2
    }
    /// Whether it holds them now.
    pub fn carried(&self) -> bool {
        self.anchor.is_some() && !self.free && !self.done
    }
    /// The plate under their real feet now.
    pub fn plate(&self) -> Option<usize> {
        self.cur
    }
    /// What to let them go with (`world.push-player` while carried, blocks a tick): a little down. None for one who was
    /// flying when handed over (the game puts them back into flight).
    pub fn set_down(&self) -> Option<[f32; 3]> {
        (!self.flew && self.carried()).then_some([0.0, -0.08, 0.0])
    }
    fn drawn(&self, i: Option<usize>, t: f64) -> [f64; 3] {
        let Some(i) = i else { return [0.0; 3] };
        let d = self.pl.drawn(i, t as f32);
        [f64::from(d[0]), f64::from(d[1]), f64::from(d[2])]
    }
    /// How far the view has eased onto `cur` at t, 0 to 1.
    fn eased(&self, t: f64) -> f64 {
        ease((t - self.since) / EASE)
    }
    /// The view's offset at t while they walk: their plate's displacement as drawn, and what is left of the ease. In
    /// flight: the offset the view keeps.
    fn walk_offset(&self, t: f64) -> [f64; 3] {
        if self.fly {
            let k = ((t - self.held_t) / TICK).clamp(0.0, 1.0);
            let [a, b] = self.held;
            return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k];
        }
        let d = self.drawn(self.cur, t);
        let k = 1.0 - ease((t - self.gap_since) / self.gap_dur);
        [d[0] + self.gap[0] * k, d[1] + self.gap[1] * k, d[2] + self.gap[2] * k]
    }
    /// A flier's tick: the view's offset a tick on. It keeps what it has (`from`, as shown now) but for what puts it
    /// further than the room their height gives from their plate's displacement then.
    /// `fell`: how far up or down they moved since the tick before.
    fn fly_tick(&mut self, t: f64, feet: [f64; 3], from: [f64; 3], fell: f64) {
        let (d0, d1) = (self.drawn(self.cur, t), self.drawn(self.cur, t + TICK));
        let room = crate::strike::eq_ground_height(feet[0], feet[2]).map_or(0.0, |g| SLACK * (feet[1] - g - SKIM).max(0.0));
        let mut to = from;
        for k in 0..3 {
            let need = from[k].clamp(d1[k] - room, d1[k] + room) - from[k];
            // (all of what the plate's own move and their own climb or fall ask for, and a share of the rest)
            let step = ((d1[k] - d0[k]).abs() + SLACK * fell + (need.abs() * CLOSE).max(CLOSE_MIN)).min(need.abs());
            to[k] = from[k] + need.signum() * step;
        }
        (self.held, self.held_t) = ([from, to], t);
    }
    /// One frame, the strike `t` seconds in (as the warp draws it: the ticks' clock and the partial tick); `warp`: the
    /// warp is on. One `drawn` of one plate: the plate under them is found each tick.
    pub fn frame(&self, t: f64, warp: bool) -> EqView {
        let s = self.eased(t) as f32;
        let p13 = crate::strike::eq_rigid_param(self.cur, s);
        let p14 = crate::strike::eq_rigid_param(self.prev, 1.0 - s);
        let walking = warp && !self.done && self.anchor.is_none();
        let offset = if walking { self.walk_offset(t) } else { [0.0; 3] };
        EqView { offset, p13, p14 }
    }
    /// The player is not there (no player this tick): nothing to follow, no ease when they are back.
    pub fn gone(&mut self) {
        (self.cur, self.prev, self.gap, self.since, self.last) = (None, None, [0.0; 3], f64::NEG_INFINITY, None);
        (self.fly, self.held, self.gap_since, self.gap_dur) = (false, [[0.0; 3]; 2], f64::NEG_INFINITY, EASE);
    }
    /// One tick, the strike `t` seconds in, the player's feet at `feet`; `held`: the game's last answer (about the carry
    /// asked two ticks ago; false: they broke free); `flying`: whether the game has them flying; `swapped`: the real land
    /// is in at rest (terrain on); `due`: when a chunk's edit at rest is due (strike::eq_chunk_due).
    pub fn tick(&mut self, t: f64, feet: [f64; 3], held: bool, flying: bool, swapped: bool, due: &dyn Fn(i32, i32) -> Option<f32>) -> RideTick {
        let mut out = RideTick::default();
        if self.done {
            return out;
        }
        let asked = self.asked[1];
        self.asked = [false, self.asked[0]];
        let moved = self.last.map_or(0.0, |l| (feet[0] - l[0]).hypot(feet[2] - l[2]));
        let fell = self.last.map_or(0.0, |l| (feet[1] - l[1]).abs());
        self.last = Some(feet);
        if self.free {
            return out;
        }
        let Some(anchor) = self.anchor else {
            // walking: the plate under their real feet. None where the land under them is already written at rest: they
            // got there without walking a plate (put there by a command, or off fixed land onto land already in), so
            // they stand in the world as it now really is: the view is their own and there is nothing to hand over.
            let here = ((feet[0].floor() as i32) >> 4, (feet[2].floor() as i32) >> 4);
            let at_rest = self.pl.rest && due(here.0, here.1).is_some_and(|d| f64::from(d) <= t);
            let under = if at_rest { None } else { self.pl.column(feet[0].floor() as i32, feet[2].floor() as i32) };
            // (the view's offset as shown now, before anything changes)
            let v = self.walk_offset(t);
            if under != self.cur {
                let d = self.drawn(under, t);
                (self.prev, self.cur, self.since) = (self.cur, under, t);
                if !self.fly {
                    (self.gap, self.gap_since, self.gap_dur) = ([v[0] - d[0], v[1] - d[1], v[2] - d[2]], t, EASE);
                }
            }
            if flying != self.fly {
                self.fly = flying;
                if !flying {
                    // (out of flight: onto the plate under them, the further off the longer)
                    let d = self.drawn(self.cur, t);
                    self.gap = [v[0] - d[0], v[1] - d[1], v[2] - d[2]];
                    let far = self.gap.iter().fold(0.0f64, |m, g| m.max(g.abs()));
                    (self.gap_since, self.gap_dur) = (t, EASE.max(far / FALL));
                }
            }
            if self.fly {
                self.fly_tick(t, feet, v, fell);
            }
            if !self.resisted && self.cur.is_some() && t + LEAD >= f64::from(EQ_HEAVE) {
                self.resisted = true;
                let secs = (f64::from(crate::lasers::EARTHQUAKE.length) - t).ceil().max(1.0) as i32;
                out.carry.cmds.push(format!("effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:resistance {secs} 4 true"));
            }
            if !self.pl.rest {
                // (the terrain left alone: nothing is written; the plates are home by EQ_BACK_END. A flier whose view
                // kept an offset of its own is put where they are seen, a tick before the warp goes off)
                let lifted = self.fly && v != [0.0; 3] && t + TICK >= f64::from(EQ_BACK_END);
                if lifted {
                    out.shift = Some(v);
                    self.handed_at = Some(t);
                }
                if lifted || t >= f64::from(EQ_BACK_END) {
                    self.done = true;
                    self.left_at = Some(t);
                }
                return out;
            }
            if t >= f64::from(EQ_REST) && swapped {
                self.done = true;
                self.left_at = Some(t);
                return out;
            }
            // terrain on: handed over before the land goes in under them
            let r = REACH + 3.0 * moved;
            let soon = (t + LOOK) as f32;
            let (a0, a1, b0, b1) = (((feet[0] - r).floor() as i32) >> 4, ((feet[0] + r).floor() as i32) >> 4, ((feet[2] - r).floor() as i32) >> 4, ((feet[2] + r).floor() as i32) >> 4);
            let near = (a0..=a1).any(|a| (b0..=b1).any(|b| due(a, b).is_some_and(|d| d <= soon)));
            // (only someone on a plate that moves: on fixed land, or in a cut, nothing goes in under them that they
            // are not already standing on, and holding them would only freeze a bystander)
            let on_moved = self.cur.is_some_and(|i| self.pl.offset(i) != [0; 3]);
            let last = t + HAND >= f64::from(EQ_RIDER_FROM);
            // (and a flier whose view kept an offset of its own, wherever they are: put where they are seen)
            let lifted = self.fly && v != [0.0; 3];
            if !((on_moved || lifted) && (near || last)) {
                return out;
            }
            self.anchor = Some(feet);
            self.flew = flying;
            self.handed_at = Some(t);
            out.shift = Some(v);
            if flying {
                // (in flight they need no land under them: put where they are seen and left to fly on, their plate
                // let rock again)
                self.free = true;
                self.freed_at = Some(t);
                (self.prev, self.cur, self.since) = (self.cur, None, t);
                return out;
            }
            let at = [feet[0] + v[0], feet[1] + v[1], feet[2] + v[2]];
            self.expect = None;
            return self.carry(out, t, at);
        };
        // (moved by more than a carry could: a teleport; held on from where it put them)
        if let Some(e) = self.expect
            && ((feet[0] - e[0]).powi(2) + (feet[1] - e[1]).powi(2) + (feet[2] - e[2]).powi(2)).sqrt() > TELEPORT
        {
            self.anchor = Some([anchor[0] + feet[0] - e[0], anchor[1] + feet[1] - e[1], anchor[2] + feet[2] - e[2]]);
        }
        if asked && !held {
            // (broken free: sneak held; let go at once)
            self.free = true;
            self.freed_at = Some(t);
            return out;
        }
        // let go: the real land in under them at rest
        if (t >= f64::from(EQ_REST) && swapped) || t > f64::from(crate::lasers::EARTHQUAKE.length) - 0.3 {
            out.carry.throw = self.set_down();
            self.done = true;
            self.left_at = Some(t);
            return out;
        }
        self.carry(out, t, feet)
    }
    /// The move a tick on: to where their plate puts the land they stood on then.
    fn carry(&mut self, mut out: RideTick, t: f64, feet: [f64; 3]) -> RideTick {
        let Some(a) = self.anchor else { return out };
        let d = self.drawn(self.cur, t + 0.05);
        let mut want = [a[0] + d[0] - feet[0], a[1] + d[1] - feet[1], a[2] + d[2] - feet[2]];
        let m = want.iter().fold(0.0f64, |m, v| m.max(v.abs()));
        if m > STEP {
            for v in &mut want {
                *v *= STEP / m;
            }
        }
        out.carry.carry = Some([want[0] as f32, want[1] as f32, want[2] as f32]);
        self.asked[0] = true;
        self.expect = Some([feet[0] + want[0], feet[1] + want[1], feet[2] + want[2]]);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::{EQ_STILL, Target, eq_plates};

    fn walk(rest: bool, me: [f64; 3]) -> (EqPlates, EqRide) {
        let t = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let pl = eq_plates(&t, me, 37.0, rest);
        (pl, EqRide::new(pl))
    }
    fn none(_: i32, _: i32) -> Option<f32> {
        None
    }
    fn sub(a: [f64; 3], b: [f64; 3]) -> f64 {
        (0..3).map(|k| (a[k] - b[k]).abs()).fold(0.0, f64::max)
    }
    /// A point on plate `i` some way inside it, and one on fixed land.
    fn on_plate(pl: &EqPlates, i: usize) -> [f64; 3] {
        find_on(pl, i).unwrap_or_else(|| panic!("no point on plate {i}"))
    }
    fn find_on(pl: &EqPlates, i: usize) -> Option<[f64; 3]> {
        for r in (0..300).step_by(3) {
            for k in 0..24 {
                let a = f64::from(k) * std::f64::consts::TAU / 24.0;
                let (x, z) = (f64::from(r) * a.cos(), f64::from(r) * a.sin());
                let (p, e) = pl.where_at(x as f32, z as f32);
                if p == Some(i) && e > 8.0 {
                    return Some([x.floor() + 0.5, 65.0, z.floor() + 0.5]);
                }
            }
        }
        None
    }

    /// Walking anywhere on a plate, at any moment, the view's offset is exactly where the warp draws that plate (its
    /// displacement and shudder, kept rigid), and that plate is the one the warp keeps from rocking; off every plate
    /// (fixed land) it is (0, 0, 0) and nothing is kept rigid.
    #[test]
    fn eq_walk_offset_is_the_plate_under_them_as_drawn() {
        for rest in [true, false] {
            let me = [0.5, 65.0, 110.0];
            let (pl, mut r) = walk(rest, me);
            let plates: Vec<usize> = (0..crate::strike::EQ_PLATES).filter(|&i| pl.offset(i) != [0; 3] && find_on(&pl, i).is_some()).collect();
            assert!(plates.len() > 5);
            let mut t = 0.0;
            for (n, &i) in plates.iter().enumerate() {
                let at = on_plate(&pl, i);
                // (stood there long enough for the ease to be over)
                // (before the hand-over: it comes just before EQ_RIDER_FROM)
                let t0 = 3.0 + n as f64 * 25.0 / plates.len() as f64;
                r.gone();
                r.tick(t0, at, true, false, false, &none);
                assert_eq!(r.plate(), Some(i));
                for s in 0..40 {
                    t = t0 + EASE + 0.02 + f64::from(s) * 0.037;
                    let v = r.frame(t, true);
                    let d = pl.drawn(i, t as f32);
                    for k in 0..3 {
                        assert!((v.offset[k] - f64::from(d[k])).abs() < 1e-9, "plate {i} at {t}: {:?} against {d:?}", v.offset);
                    }
                    assert_eq!(v.p13, crate::strike::eq_rigid_param(Some(i), 1.0));
                }
            }
            assert!(t > 20.0);
            // (fixed land, far outside the zone)
            r.gone();
            r.tick(30.0, [3000.5, 65.0, 0.5], true, false, false, &none);
            assert_eq!(r.plate(), None);
            let v = r.frame(30.0 + EASE, true);
            assert_eq!(v.offset, [0.0; 3]);
            assert_eq!(v.p13, 0.0);
            // (the warp off: nothing)
            r.gone();
            let at = on_plate(&pl, plates[0]);
            r.tick(15.0, at, true, false, false, &none);
            assert_eq!(r.frame(15.0 + EASE, false).offset, [0.0; 3]);
        }
    }

    /// Stepping from one plate onto another (or onto fixed land), the view eases across over EASE, never in a step: its
    /// change between frames at 60 stays small; the plate left lets its rock back in as the new one is kept from it.
    #[test]
    fn eq_walk_eases_across_a_fault() {
        let me = [0.5, 65.0, 110.0];
        let (pl, mut r) = walk(true, me);
        let mut by: Vec<(usize, f64)> = (0..crate::strike::EQ_PLATES).filter(|&i| find_on(&pl, i).is_some()).map(|i| (i, f64::from(pl.offset(i)[1]))).filter(|p| p.1 != 0.0).collect();
        by.sort_by(|a, b| a.1.total_cmp(&b.1));
        let (lo, hi) = (by[0].0, by[by.len() - 1].0);
        let (a, b) = (on_plate(&pl, hi), on_plate(&pl, lo));
        let t0 = 24.0;
        r.tick(t0 - 1.0, a, true, false, false, &none);
        r.tick(t0, b, true, false, false, &none);
        let mut v0 = r.frame(t0, true);
        assert!(sub(v0.offset, r.frame(t0 - 0.001, true).offset) < 1e-9, "no jump as it changes");
        let mut worst = 0.0f64;
        let mut f = t0;
        while f < t0 + EASE + 0.1 {
            f += 1.0 / 60.0;
            let v = r.frame(f, true);
            worst = worst.max(sub(v.offset, v0.offset));
            v0 = v;
        }
        let jump = sub(pl.drawn(hi, f as f32).map(f64::from), pl.drawn(lo, f as f32).map(f64::from));
        assert!(jump > 20.0, "the two plates {jump} apart");
        // (smoothstep over EASE: its fastest frame 1.5 times the even share)
        assert!(worst < jump * 1.5 / (EASE * 60.0) + 0.05, "a frame's change of {worst} across a step of {jump}");
        let v = r.frame(t0 + EASE + 0.01, true);
        assert!(sub(v.offset, pl.drawn(lo, (t0 + EASE + 0.01) as f32).map(f64::from)) < 1e-9);
        // (half way: both plates half rigid)
        let mid = r.frame(t0 + EASE / 2.0, true);
        assert!((mid.p13 - crate::strike::eq_rigid_param(Some(lo), 0.5)).abs() < 1e-4 && (mid.p14 - crate::strike::eq_rigid_param(Some(hi), 0.5)).abs() < 1e-4, "{mid:?}");
        // (onto fixed land: eased down to nothing)
        r.tick(t0 + 2.0, [3000.5, 65.0, 0.5], true, false, false, &none);
        assert!(sub(r.frame(t0 + 2.0, true).offset, pl.drawn(lo, (t0 + 2.0) as f32).map(f64::from)) < 1e-6);
        assert_eq!(r.frame(t0 + 2.0 + EASE, true).offset, [0.0; 3]);
    }

    /// In flight the view keeps the offset it has. High over the land, flying from one plate over another moves
    /// nothing. Coming down, it closes on the plate under them by their height, so they are never under the drawn land
    /// and land where it is drawn; low over a plate they ride it. Out of flight it eases onto the plate. A flier whose
    /// view is off the land under them is put where they are seen before the land goes in (and, the terrain left
    /// alone, before the warp goes off), wherever they are.
    #[test]
    fn eq_flight_keeps_the_view_until_the_land_is_near() {
        let me = [0.5, 65.0, 110.0];
        let (pl, mut r) = walk(true, me);
        crate::strike::eq_ground_set_test(Some((&pl, &|_, _| 0.0)));
        let mut by: Vec<(usize, f64)> = (0..crate::strike::EQ_PLATES).filter(|&i| find_on(&pl, i).is_some()).map(|i| (i, f64::from(pl.offset(i)[1]))).filter(|p| p.1 != 0.0).collect();
        by.sort_by(|a, b| a.1.total_cmp(&b.1));
        let (lo, hi) = (by[0].0, by[by.len() - 1].0);
        let (a, b) = (on_plate(&pl, hi), on_plate(&pl, lo));
        let up = |p: [f64; 3], h: f64| [p[0], p[1] + h, p[2]];
        let drawn = |i: usize, t: f64| pl.drawn(i, t as f32).map(f64::from);
        // (a tick of flight at `at`; the view's offset a tick on)
        fn fly(r: &mut EqRide, t: &mut f64, at: [f64; 3], flying: bool) -> [f64; 3] {
            *t += TICK;
            let o = r.tick(*t, at, true, flying, false, &none);
            assert!(o.shift.is_none());
            r.frame(*t + TICK, true).offset
        }
        let mut t = 21.2;
        r.tick(t, a, true, false, false, &none);
        t += 0.4;
        // (up into flight, high over it, then over the low plate: nothing moves)
        let kept = fly(&mut r, &mut t, up(a, 400.0), true);
        assert!(sub(kept, drawn(hi, t)) < 0.5 && kept[1] > 20.0, "off the high plate: {kept:?}");
        for n in 0..8 {
            let at = if n < 4 { up(a, 400.0) } else { up(b, 400.0) };
            let v = fly(&mut r, &mut t, at, true);
            assert!(sub(v, kept) < 1e-9, "tick {n}: {v:?} from {kept:?}");
        }
        assert_eq!(r.plate(), Some(lo));
        assert!(sub(kept, drawn(lo, t)) > 20.0);
        // (down onto the low plate, 5 blocks a tick: always over the drawn land, coming down all the way, within the
        // room their height gives, and on the plate once they skim it)
        let mut seen = f64::MAX;
        let mut h = 400.0;
        while h > 0.0 {
            h -= 5.0;
            let v = fly(&mut r, &mut t, up(b, h), true);
            let d = drawn(lo, t + TICK);
            let over = h + v[1] - d[1];
            assert!(over >= h.min(SKIM) - 1e-6, "{h} over the land really, {over} as seen");
            assert!(over <= seen + 1e-6, "seen going up ({seen} to {over}) while coming down");
            assert!(sub(v, d) <= SLACK * (h - SKIM).max(0.0) + 1e-6, "{h} up: {v:?} against {d:?}");
            seen = over;
        }
        assert!(sub(r.frame(t + TICK, true).offset, drawn(lo, t + TICK)) < 1e-6);
        // (skimming from the low plate over the high one: onto it within half a second, no tick more than its share)
        let step = sub(drawn(hi, t), drawn(lo, t));
        let mut v0 = r.frame(t + TICK, true).offset;
        for n in 0..14 {
            let v = fly(&mut r, &mut t, up(a, 2.0), true);
            assert!(sub(v, v0) <= step * CLOSE + CLOSE_MIN + 0.5, "tick {n}: {} of a step of {step}", sub(v, v0));
            v0 = v;
        }
        assert!(sub(v0, drawn(hi, t + TICK)) < 1e-6, "{v0:?}");
        // (high again and over the low plate, then out of flight there: no jump, and eased onto the plate)
        for at in [up(a, 400.0), up(b, 400.0)] {
            fly(&mut r, &mut t, at, true);
        }
        let v = r.frame(t + TICK, true).offset;
        t += TICK;
        r.tick(t, up(b, 400.0), true, false, false, &none);
        assert!(sub(r.frame(t, true).offset, v) < 1e-9, "no jump out of flight");
        let far = sub(v, drawn(lo, t));
        assert!(far > 20.0);
        let mut worst = 0.0f64;
        let (mut f, mut v0) = (t, v);
        while f < t + far / FALL + 0.1 {
            f += 1.0 / 60.0;
            let v = r.frame(f, true).offset;
            worst = worst.max(sub(v, v0));
            v0 = v;
        }
        assert!(worst < FALL * 1.5 / 60.0 + 0.05, "a frame's change of {worst}");
        assert!(sub(v0, drawn(lo, f)) < 1e-6);

        // (a flier whose view kept the high plate's offset, now over fixed land: handed over all the same)
        for rest in [true, false] {
            let (pl, mut r) = walk(rest, me);
            crate::strike::eq_ground_set_test(Some((&pl, &|_, _| 0.0)));
            let hi = (0..crate::strike::EQ_PLATES).filter(|&i| find_on(&pl, i).is_some()).max_by_key(|&i| pl.offset(i)[1]).unwrap();
            let a = on_plate(&pl, hi);
            let mut t = 22.0;
            r.tick(t, a, true, false, false, &none);
            t += 1.0;
            let away = [3000.5, 465.0, 0.5];
            let kept = fly(&mut r, &mut t, up(a, 400.0), true);
            assert!(kept[1] > 20.0);
            for _ in 0..10 {
                assert!(sub(fly(&mut r, &mut t, away, true), kept) < 1e-9);
            }
            assert_eq!(r.plate(), None);
            let end = if rest { f64::from(EQ_RIDER_FROM) - HAND } else { f64::from(EQ_BACK_END) - TICK };
            let o = r.tick(end - 0.2, away, true, true, false, &none);
            assert!(o.shift.is_none(), "not before its time");
            let o = r.tick(end + 0.001, away, true, true, false, &none);
            let s = o.shift.expect("put where they are seen");
            assert!(sub(s, kept) < 1e-9, "{s:?} against {kept:?}");
            assert!(o.carry.carry.is_none(), "not held: they fly");
            assert_eq!(r.frame(end + 0.01, true).offset, [0.0; 3]);
            assert!(!r.carried());
        }
        crate::strike::eq_ground_set_test(None);
    }

    /// The hand-over: just before the walker's chunks go in, they are put where they were seen (the shift is the view's
    /// offset, the view 0 after), no chunk round them has gone in before it, held with their plate by the carry until
    /// the swap and let go standing exactly where their plate's land is at rest; sneak breaks free of the hold.
    #[test]
    fn eq_walk_hands_over_where_they_were_seen() {
        let me = [0.5, 65.0, 110.0];
        let (pl, mut r) = walk(true, me);
        let i = pl.rider().expect("on the plate that rises");
        let start = on_plate(&pl, i);
        // (their chunks go in from EQ_RIDER_FROM; the others long before, none round them)
        let mine = (start[0].floor() as i32 >> 4, start[2].floor() as i32 >> 4);
        let due = move |a: i32, b: i32| Some(if (a - mine.0).abs() <= 4 && (b - mine.1).abs() <= 4 { EQ_RIDER_FROM } else { 15.0 });
        let mut feet = start;
        let mut shift = None;
        let mut seen = [0.0; 3];
        let mut thrown = None;
        let mut n = 0u32;
        loop {
            let t = f64::from(n) * 0.05;
            n += 1;
            if r.over(t) {
                break;
            }
            let swapped = t >= f64::from(EQ_REST) + 0.1;
            let o = r.tick(t, feet, true, false, swapped, &due);
            if let Some(v) = o.shift {
                assert!(shift.is_none(), "handed over twice");
                assert!(t + 0.0001 < f64::from(EQ_RIDER_FROM) && t > f64::from(EQ_RIDER_FROM) - 0.3, "handed over at {t}");
                assert!(sub(v, seen) < 1e-9, "shifted by {v:?}, seen from {seen:?}");
                for k in 0..3 {
                    feet[k] += v[k];
                }
                shift = Some(v);
            }
            thrown = thrown.or(o.carry.throw);
            if let Some(c) = o.carry.carry {
                for k in 0..3 {
                    feet[k] += f64::from(c[k]);
                }
            }
            // (the frame after: the view's offset as drawn while walking, 0 once handed over)
            let v = r.frame(t + 0.01, true);
            if r.handed_at.is_some() {
                assert_eq!(v.offset, [0.0; 3]);
            } else {
                // (walking: nothing moves their real feet)
                assert_eq!(feet, start);
            }
            seen = r.frame(t + 0.05, true).offset;
        }
        let v = shift.expect("handed over");
        let o = pl.offset(i);
        assert!(sub(v, o.map(f64::from)) < 1e-6, "shifted by {v:?}, the plate at rest {o:?}");
        for k in 0..3 {
            assert!((feet[k] - start[k] - f64::from(o[k])).abs() < 1e-3, "{feet:?} from {start:?} by {o:?}");
        }
        assert!(r.left_at.is_some_and(|t| t >= f64::from(EQ_REST)), "let go at {:?}", r.left_at);
        assert!(thrown.is_some_and(|v| v[1] < 0.0), "set down out of flight");
        // (sneak: broken free of the hold, left alone from then)
        let (_, mut r) = walk(true, me);
        let t0 = f64::from(EQ_RIDER_FROM) - 0.1;
        r.tick(t0 - 1.0, start, true, false, false, &due);
        assert!(r.tick(t0, start, true, false, false, &due).shift.is_some());
        let mut free = false;
        let mut t = t0;
        for _ in 0..4 {
            t += 0.05;
            free |= r.tick(t, start, false, false, false, &due).carry.carry.is_none() && r.freed_at.is_some();
        }
        assert!(free);
        assert_eq!(r.set_down(), None);
    }

    /// Walking out of the land kept for last before it goes in: handed over as soon as a chunk round them is due, early,
    /// and held with their plate as it still moves (no jump in their speed, never faster than STEP), let go on it at rest.
    #[test]
    fn eq_walk_hands_over_early_off_the_land_kept_for_last() {
        let me = [0.5, 65.0, 110.0];
        let (pl, mut r) = walk(true, me);
        let i = pl.rider().unwrap();
        let start = on_plate(&pl, i);
        let mine = (start[0].floor() as i32 >> 4, start[2].floor() as i32 >> 4);
        // (their own chunk is due at 16 s: they stand on land that goes in then)
        let due = move |a: i32, b: i32| Some(if (a, b) == mine { 16.0 } else { EQ_RIDER_FROM });
        let mut feet = start;
        let (mut v0, mut jerk, mut fastest) = ([0.0f64; 3], 0.0f64, 0.0f64);
        for n in 0..(50.0 / 0.05) as u32 {
            let t = f64::from(n) * 0.05;
            if r.over(t) {
                break;
            }
            let o = r.tick(t, feet, true, false, t >= f64::from(EQ_REST) + 0.1, &due);
            if let Some(v) = o.shift {
                assert!(t < 16.0 && t >= 16.0 - LOOK - 0.06, "handed over at {t}");
                for k in 0..3 {
                    feet[k] += v[k];
                }
            }
            if let Some(c) = o.carry.carry {
                let v = [f64::from(c[0]), f64::from(c[1]), f64::from(c[2])];
                for k in 0..3 {
                    fastest = fastest.max(v[k].abs());
                    if r.handed_at.is_some_and(|h| t > h + 0.06) {
                        jerk = jerk.max((v[k] - v0[k]).abs());
                    }
                    feet[k] += v[k];
                }
                v0 = v;
            }
        }
        assert!(fastest < STEP - 0.2, "{fastest}");
        assert!(jerk < 1.5, "the speed jumped by {jerk} blocks a tick");
        let o = pl.offset(i);
        for k in 0..3 {
            assert!((feet[k] - start[k] - f64::from(o[k])).abs() < 1e-3, "{feet:?} from {start:?} by {o:?}");
        }
        assert!(EQ_STILL > 16.0);
    }

    /// The terrain left alone: the view follows the plate all strike long and back home, nobody is handed over or
    /// carried, and it is over at EQ_BACK_END with the view at nothing.
    #[test]
    fn eq_walk_terrain_off_never_hands_over() {
        let me = [0.5, 65.0, 110.0];
        let (pl, mut r) = walk(false, me);
        let i = pl.rider().unwrap();
        let at = on_plate(&pl, i);
        let due = |_: i32, _: i32| Some(10.0f32);
        let mut top = 0.0f64;
        for n in 0..(50.0 / 0.05) as u32 {
            let t = f64::from(n) * 0.05;
            if r.over(t) {
                break;
            }
            let o = r.tick(t, at, true, false, false, &due);
            assert!(o.shift.is_none() && o.carry.carry.is_none());
            top = top.max(r.frame(t, true).offset[1].abs());
        }
        assert!(top > 20.0, "the view rose {top}");
        assert!(r.left_at.is_some_and(|t| t >= f64::from(EQ_BACK_END)));
        assert_eq!(r.frame(f64::from(EQ_BACK_END), true).offset, [0.0; 3]);
    }

    /// In flight at the hand-over they are put where they were seen and left to fly on: nothing holds them, then or
    /// after, and the view is their own from there.
    #[test]
    fn eq_walk_never_holds_a_flying_player() {
        let me = [0.5, 65.0, 110.0];
        let (pl, mut r) = walk(true, me);
        let i = pl.rider().unwrap();
        let start = on_plate(&pl, i);
        let due = |_: i32, _: i32| Some(23.0f32);
        let mut feet = [start[0], start[1] + 30.0, start[2]];
        let mut shifted = false;
        let mut t = 20.0;
        while t < 32.0 {
            let o = r.tick(t, feet, true, true, t >= f64::from(EQ_REST) + 0.1, &due);
            assert!(o.carry.carry.is_none() && o.carry.throw.is_none(), "held at {t}");
            assert!(!r.carried());
            if let Some(v) = o.shift {
                assert!(!shifted, "handed over twice");
                shifted = true;
                assert!(v[1].abs() > 1.0, "shifted by {v:?}");
                for k in 0..3 {
                    feet[k] += v[k];
                }
            }
            if shifted {
                let v = r.frame(t + 0.01, true);
                assert_eq!(v.offset, [0.0; 3]);
                assert_eq!(v.p13, 0.0);
            }
            t += 0.05;
        }
        assert!(shifted);
        assert!(r.handed_at.is_some_and(|h| h < 23.0 && h > 22.7), "handed over at {:?}", r.handed_at);
        assert_eq!(r.set_down(), None);
    }

    /// Put (by a command) onto land that is already written at rest, they stand in the world as it really is: the view
    /// is not moved and they are never handed over (a shift would put them into the rock).
    #[test]
    fn eq_walk_leaves_alone_someone_on_land_already_at_rest() {
        let me = [0.5, 65.0, 110.0];
        let (pl, mut r) = walk(true, me);
        let i = pl.rider().unwrap();
        let at = on_plate(&pl, i);
        // (every chunk went in at 17 s)
        let due = |_: i32, _: i32| Some(17.0f32);
        let far = [3000.5, 65.0, 0.5];
        let mut t = 12.0;
        while t < 32.0 {
            // (far off until 20 s, then put on the plate's home, long after its land was written)
            let feet = if t < 20.0 { far } else { at };
            let o = r.tick(t, feet, true, false, t >= f64::from(EQ_REST) + 0.1, &due);
            assert!(o.shift.is_none() && o.carry.carry.is_none(), "handed over at {t}");
            let v = r.frame(t + 0.01, true);
            assert_eq!(v.offset, [0.0; 3], "the view moved at {t}");
            assert_eq!(v.p13, 0.0);
            t += 0.05;
        }
        assert!(r.handed_at.is_none());
    }

    /// Teleported while held, they are held on from where they were put.
    #[test]
    fn eq_walk_a_teleport_moves_where_they_are_held() {
        let me = [0.5, 65.0, 110.0];
        let (pl, mut r) = walk(true, me);
        let i = pl.rider().unwrap();
        let start = on_plate(&pl, i);
        let due = |_: i32, _: i32| Some(12.0f32);
        let mut feet = start;
        let mut t = 11.0;
        let mut jumped = false;
        while t < 31.0 {
            if !jumped && t > 18.0 {
                feet[1] -= 70.0;
                jumped = true;
            }
            let o = r.tick(t, feet, true, false, false, &due);
            if let Some(v) = o.shift {
                for k in 0..3 {
                    feet[k] += v[k];
                }
            }
            if let Some(c) = o.carry.carry {
                for k in 0..3 {
                    feet[k] += f64::from(c[k]);
                }
            }
            t += 0.05;
        }
        let o = pl.offset(i);
        assert!((feet[1] - (start[1] - 70.0 + f64::from(o[1]))).abs() < 0.5, "{feet:?} {o:?}");
    }
}
