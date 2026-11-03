//! The follow camera (`/orbital follow on`, the wheel's FOLLOW switch): an orbit camera round the Nuke's or the
//! Payload's bomb. The player's own mouse sets the angle: the camera sits `distance` blocks from the bomb straight back
//! along the way the player looks, so turning the view orbits it, the bomb staying in the middle of the picture. The
//! mod never turns the view; it only moves the player.
//!
//! It moves them as the game moves a player itself: a kick to their velocity each tick (`world.push-player`, added on
//! the client, as an explosion's knockback is), so the game's own movement carries them and its frame interpolation
//! draws it smoothly. (A `tp` a frame, as this used to be, runs on the integrated server's thread between its ticks and
//! comes back to the window as a position packet that snaps the player, `previous_position` and all, and turns them:
//! a step every tick or two out of time with the frames, the bomb jumping about in the picture.) The kick is worked out
//! from where they are, and how they moved on the tick before, to land them on the orbit's next point: the air's drag
//! and gravity, or flight's, taken off (which of the two is read from how they moved); a tick their chunk isn't ready
//! and the game holds them still is seen and allowed for.
//!
//! The camera keeps to the land already loaded round where the player stood (a player only moves where their chunk is
//! loaded, and every chunk further out would have to be generated, sent and drawn, and the far terrain sampled anew,
//! as the old one's trip 2.6 km out and a kilometre up did): until the bomb comes within `REACH` of them the view is
//! their own, free to watch it streak in; then the camera flies out to the orbit, rides it down, backs off as the burst
//! nears (never inside the blast), orbits the fireball and the cloud, and at the end the player is put back where they
//! stood (one `tp` keeping their view: `~ ~`).
use crate::strike::BombPath;

/// The orbit's distance from the bomb unless `/orbital follow distance` sets another.
pub const DISTANCE: f64 = 70.0;
pub const DISTANCE_MIN: f64 = 10.0;
pub const DISTANCE_MAX: f64 = 400.0;
/// How near the bomb comes (level, from where the player stood) before the camera leaves them for it.
const REACH: f64 = 440.0;
/// How long the flight out to the orbit takes.
const JOIN: f64 = 1.6;
/// The player's eyes over their feet.
const EYE: f64 = 1.62;
/// The most one kick may give (the game takes 4 a call; a tick takes several).
const KICK: f64 = 3.9;
/// The most kicks a tick (so no more than 117 blocks a tick, whatever goes wrong).
const KICKS: usize = 30;
/// The fastest the camera moves the player, blocks a tick on any axis: the game's collision sweep of a move this
/// long stays a few percent of its million-block budget (a 230-block jump in one tick crashed the game).
pub(crate) const VMAX: f64 = 24.0;

/// How the orbit backs off for each bomb: from `safe_from` seconds before it bursts to `safe_by` before, out to `safe`
/// (or the orbit's own distance, if more); then `grow` times that as the cloud climbs, `settle` seconds after the burst.
/// The cloud's middle (what is orbited after the burst) rises from `low` to `high` over the ground, `settle` seconds
/// after; the camera stays `floor` over the target's ground at least; the player is put back at `end`.
struct Shot {
    safe_from: f64,
    safe_by: f64,
    safe: f64,
    grow: f64,
    settle: f64,
    low: f64,
    high: f64,
    floor: f64,
    end: f64,
}
const NUKE: Shot = Shot { safe_from: 2.6, safe_by: 0.3, safe: 380.0, grow: 1.3, settle: 22.0, low: 12.0, high: 200.0, floor: 10.0, end: 40.0 };
const PAYLOAD: Shot = Shot { safe_from: 1.6, safe_by: 0.2, safe: 170.0, grow: 1.25, settle: 18.0, low: 4.0, high: 90.0, floor: 8.0, end: 32.0 };

fn add(a: [f64; 3], b: [f64; 3], k: f64) -> [f64; 3] {
    [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k]
}
fn sub(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    add(a, b, -1.0)
}
fn lerp(a: [f64; 3], b: [f64; 3], k: f64) -> [f64; 3] {
    add(a, sub(b, a), k)
}
fn len(a: [f64; 3]) -> f64 {
    (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt()
}
/// 0 to 1 from `a` to `b`, eased in and out with no jerk at either end.
fn ease(a: f64, b: f64, t: f64) -> f64 {
    let x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    x * x * x * (x * (6.0 * x - 15.0) + 10.0)
}
/// The way yaw and pitch look (the game's: yaw 0 looks along +z, 90 along -x; pitch 90 straight down).
pub fn look(yaw: f32, pitch: f32) -> [f64; 3] {
    let (y, p) = (f64::from(yaw).to_radians(), f64::from(pitch).to_radians());
    [-y.sin() * p.cos(), -p.sin(), y.cos() * p.cos()]
}

/// The player's motion as the game works it out after it moves them (`Player.travel`): the air's drag (0.91 level),
/// and up and down gravity and drag, or in creative flight 0.6 of it kept.
pub fn drag(v: [f64; 3], flying: bool) -> [f64; 3] {
    [v[0] * 0.91, if flying { v[1] * 0.6 } else { (v[1] - 0.08) * 0.98 }, v[2] * 0.91]
}

pub struct Follow {
    path: BombPath,
    shot: &'static Shot,
    /// The orbit's distance.
    distance: f64,
    /// Where the player stood as it fired, and when the camera leaves them for the bomb.
    feet0: [f64; 3],
    join: f64,
    /// The eye the flight out starts from (where the player is as it starts).
    from: Option<[f64; 3]>,
    /// The controller that moves them.
    drive: Drive,
}

/// The controller the follow camera and the Hurricane's carry (`carry.rs`) move the player with: a kick to their
/// velocity each tick, worked out from where they are and how they moved on the tick before so they are where they
/// should be a tick later (the game's drag and gravity, or flight's, taken off). It remembers where the player was a
/// tick ago, how they moved then, the kick given then, what their velocity is thought to be now, and whether they fly.
#[derive(Default)]
pub struct Drive {
    last: Option<[f64; 3]>,
    moved: Option<[f64; 3]>,
    kick: [f64; 3],
    velocity: [f64; 3],
    flying: bool,
    /// Whether they fly, for the carry's cue to let go: how many ticks running their move up or down only flight
    /// explained (or, negative, falling, with slow falling or without); ticks held still while their chunk loads, or
    /// too gentle to tell, leave it.
    flight: i32,
    /// How far their last move missed what the kicks and the drag should have made of it (their own steering).
    miss: f64,
}
impl Drive {
    /// The kicks (blocks a tick, each within the game's 4) that take a player standing at `feet` by `want` over the
    /// next tick: never faster than VMAX a tick on any axis.
    pub fn kicks(&mut self, feet: [f64; 3], want: [f64; 3]) -> Vec<[f32; 3]> {
        // what they did since the last tick: moved by what they had (thus their velocity now, the drag taken off),
        // or held still while their chunk wasn't ready (what they had kept, the kick on top)
        if let Some(last) = self.last {
            let m = sub(feet, last);
            let had = add(self.velocity, self.kick, 1.0);
            if m == [0.0; 3] && len(had) > 1e-3 {
                self.velocity = had;
                self.moved = None;
            } else {
                // (flying or falling: whichever of the two would have moved them as they did up and down)
                if let Some(pm) = self.moved {
                    let fly = drag(pm, true)[1] + self.kick[1];
                    let fall = drag(pm, false)[1] + self.kick[1];
                    if (fly - fall).abs() > 0.03 {
                        self.flying = (m[1] - fly).abs() < (m[1] - fall).abs();
                    }
                    // (flight against falling, slow falling's too: an eighth of the air's gravity once falling)
                    let slow = if pm[1] <= 0.0 { (pm[1] - 0.01) * 0.98 } else { (pm[1] - 0.08) * 0.98 } + self.kick[1];
                    let (df, dn) = ((m[1] - fly).abs(), (m[1] - fall).abs().min((m[1] - slow).abs()));
                    if (fly - fall).abs().min((fly - slow).abs()) > 0.006 {
                        self.flight = if df < dn { self.flight.max(0) + 1 } else { self.flight.min(0) - 1 }.clamp(-60, 60);
                    }
                }
                self.miss = len(sub(m, had));
                self.velocity = drag(m, self.flying);
                self.moved = Some(m);
            }
        }
        self.last = Some(feet);
        // (never faster than VMAX a tick on any axis, the kicks taking it back down if it is: the game sweeps the
        // player's box along its whole move for collisions, and gives up, crashing, past a million blocks)
        let mut total = want;
        let fast = total.iter().fold(0.0f64, |a, v| a.max(v.abs()));
        if fast > VMAX {
            total = total.map(|v| v * VMAX / fast);
        }
        let mut kick = sub(total, self.velocity);
        // (however far off, no more than KICKS a tick)
        let most = KICK * KICKS as f64;
        let big = kick.iter().fold(0.0f64, |a, v| a.max(v.abs()));
        if big > most {
            kick = kick.map(|v| v * most / big);
        }
        self.kick = kick;
        let n = (big.min(most) / KICK).ceil().max(1.0) as usize;
        (0..n).map(|_| kick.map(|v| (v / n as f64) as f32)).collect()
    }
    /// How many ticks running it has seen them fly (or, negative, fall), and how far their last move missed what it
    /// expected of it.
    pub fn flight(&self) -> (i32, f64) {
        (self.flight, self.miss)
    }
}

impl Follow {
    /// A follow of `path`'s bomb at `distance`, the player standing at `feet` as it fires.
    pub fn new(path: BombPath, feet: [f64; 3], distance: f64) -> Follow {
        let shot = if path.big { &NUKE } else { &PAYLOAD };
        // (the camera leaves the player once the bomb is within REACH of them, level; at the latest well before it
        // bursts)
        let near = |t: f64| {
            let b = Self::bomb_of(&path, t);
            (b[0] - feet[0]).hypot(b[2] - feet[2]) <= REACH
        };
        let latest = path.hit - shot.safe_from - JOIN;
        let mut join = latest;
        let mut t = path.seen;
        while t < latest {
            if near(t) {
                join = t;
                break;
            }
            t += 0.05;
        }
        Follow { path, shot, distance: distance.clamp(DISTANCE_MIN, DISTANCE_MAX), feet0: feet, join, from: None, drive: Drive::default() }
    }
    fn bomb_of(path: &BombPath, t: f64) -> [f64; 3] {
        let p = &path.pts;
        let u = ((t - path.seen) / path.dt).clamp(0.0, (p.len() - 1) as f64);
        let i = (u.floor() as usize).min(p.len().saturating_sub(2));
        lerp(p[i], p[(i + 1).min(p.len() - 1)], u - i as f64)
    }
    /// What the camera orbits at strike time `t`: the bomb, then the fireball rising into the cloud.
    pub fn centre(&self, t: f64) -> [f64; 3] {
        let s = self.shot;
        if t < self.path.hit {
            return Self::bomb_of(&self.path, t);
        }
        let g = self.path.ground;
        let burst = Self::bomb_of(&self.path, self.path.hit);
        let k = ease(self.path.hit, self.path.hit + s.settle, t);
        [burst[0], g[1] + s.low + (s.high - s.low) * k, burst[2]]
    }
    /// The orbit's distance at `t`: backing off as the burst nears, further as the cloud climbs.
    pub fn reach(&self, t: f64) -> f64 {
        let s = self.shot;
        let h = self.path.hit;
        let safe = s.safe.max(self.distance);
        let d = self.distance + (safe - self.distance) * ease(h - s.safe_from, h - s.safe_by, t);
        d * (1.0 + (s.grow - 1.0) * ease(h, h + s.settle, t))
    }
    /// Where the eye goes at `t`, the player looking along `dir`: back from what it orbits, over the ground.
    pub fn orbit(&self, t: f64, dir: [f64; 3]) -> [f64; 3] {
        let mut e = add(self.centre(t), dir, -self.reach(t));
        e[1] = e[1].max(self.path.ground[1] + self.shot.floor);
        e
    }
    /// Whether it is over by strike time `t`.
    pub fn over(&self, t: f64) -> bool {
        t >= self.shot.end
    }
    /// Whether the camera has left the player yet at `t`.
    pub fn joined(&self, t: f64) -> bool {
        t >= self.join
    }
    /// One tick: the player stands at `feet` looking along `dir`, the strike `t` seconds in. The kicks to give them
    /// (blocks a tick, each within the game's 4) so they are where the orbit is a tick later.
    pub fn tick(&mut self, t: f64, feet: [f64; 3], dir: [f64; 3]) -> Vec<[f32; 3]> {
        if !self.joined(t) {
            return Vec::new();
        }
        let from = *self.from.get_or_insert(add(feet, [0.0, EYE, 0.0], 1.0));
        let next = t + 0.05;
        let eye = lerp(from, self.orbit(next, dir), ease(self.join, self.join + JOIN, next));
        let want = sub(sub(eye, [0.0, EYE, 0.0]), feet);
        self.drive.kicks(feet, want)
    }
    /// What ends it: the player back where they stood, their view left as it is.
    pub fn finish(&self) -> Vec<String> {
        let [x, y, z] = self.feet0;
        vec![format!("tp @s {x:.4} {y:.4} {z:.4} ~ ~")]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::{Target, bomb_path};

    fn follow(key: &str, me: [f64; 3]) -> Follow {
        let target = Target { block: [100, 70, -40], point: [100.5, 71.0, -39.5] };
        Follow::new(bomb_path(key, &target, 211.0, me).expect("a bomb"), me, DISTANCE)
    }

    /// A player as the game moves them each tick (their velocity, the kicks added, then moved and dragged), flying or
    /// not, held still on the ticks `frozen` says (their chunk not ready); looking round as a mouse would.
    struct Player {
        feet: [f64; 3],
        velocity: [f64; 3],
        flying: bool,
    }
    fn play(key: &str, flying: bool, frozen: impl Fn(u32) -> bool, off: f64) -> (Follow, f64, f64) {
        let me = [400.0, 72.0, -40.0];
        let mut f = follow(key, me);
        let mut p = Player { feet: me, velocity: [0.0; 3], flying };
        let (mut worst, mut nearest) = (0.0f64, f64::MAX);
        let mut before = look(90.0, 10.0);
        let mut k = 0u32;
        loop {
            k += 1;
            let t = f64::from(k) * 0.05;
            if f.over(t) {
                break;
            }
            // the game moves them (unless their chunk isn't ready)
            if !frozen(k) {
                p.feet = add(p.feet, p.velocity, 1.0);
                // (`off`: the game's drag a little other than the mod thinks)
                p.velocity = drag(p.velocity, p.flying).map(|v| v * (1.0 - off));
                // (standing on the ground where they stood)
                if p.feet[1] < me[1] {
                    p.feet[1] = me[1];
                    p.velocity[1] = 0.0;
                }
            }
            // the mouse: the view turning round slowly, up and down a little
            let (yaw, pitch) = (90.0 + 40.0 * (t * 0.3).sin(), 10.0 + 20.0 * (t * 0.5).sin());
            let dir = look(yaw as f32, pitch as f32);
            let kicks = f.tick(t, p.feet, dir);
            let eye = add(p.feet, [0.0, EYE, 0.0], 1.0);
            if t > f.join + JOIN + 0.2 && !frozen(k) && !frozen(k.saturating_sub(1)) {
                worst = worst.max(len(sub(eye, f.orbit(t, before))));
            }
            before = dir;
            for kick in kicks {
                assert!(kick.iter().all(|v| v.abs() <= 4.0));
                p.velocity = add(p.velocity, kick.map(f64::from), 1.0);
            }
            // never a move the game's collision sweep can't take (its budget a million blocks)
            let sweep = (p.velocity[0].abs() + 0.6) * (p.velocity[1].abs() + 1.8) * (p.velocity[2].abs() + 0.6);
            assert!(sweep < 100_000.0, "{key} at {t}: velocity {:?} sweeps {sweep:.0}", p.velocity);
            // how near the blast
            if t >= f.path.hit - 0.1 && t <= f.path.hit + 15.0 {
                nearest = nearest.min(len(sub(eye, f.centre(f.path.hit))));
            }
            // and never far from where they stood (the land loaded round them)
            assert!((eye[0] - me[0]).hypot(eye[2] - me[2]) < 900.0, "{key} at {t}: {eye:?}");
        }
        (f, worst, nearest)
    }

    #[test]
    fn the_orbit_follows_the_look_and_keeps_clear_of_the_blast() {
        for key in ["nuke", "payload"] {
            for flying in [false, true] {
                let (f, worst, nearest) = play(key, flying, |_| false, 0.0);
                eprintln!("{key} flying {flying}: joins at {:.2} s, at most {worst:.2} off the orbit, {nearest:.0} from the burst at the nearest", f.join);
                // (where the eye is against where the orbit wanted it, with the view as it was a tick before)
                assert!(worst < 3.0, "{key} flying {flying}: {worst} blocks off the orbit");
                let safe = if key == "nuke" { 350.0 } else { 150.0 };
                assert!(nearest > safe, "{key}: {nearest} from the burst");
                assert!(f.join > f.path.seen && f.join < f.path.hit - 2.0, "{key}: joins at {}", f.join);
            }
        }
        // held still a few ticks (their chunk not ready): catching back up at no more than VMAX a tick, a tick or two
        // behind (never a jump the game's collision sweep can't take)
        let (_, worst, _) = play("nuke", false, |k| (180..184).contains(&k), 0.0);
        assert!(worst < 2.0 * VMAX, "{worst}");
        // the game's drag 3% other than the mod's: still on the orbit, near enough (it corrects each tick)
        for off in [-0.03, 0.03] {
            let (_, worst, _) = play("nuke", true, |_| false, off);
            eprintln!("drag {off}: at most {worst:.2} off the orbit");
            assert!(worst < 3.0, "{off}: {worst}");
        }
    }

    #[test]
    fn the_orbit_is_the_look_reversed() {
        let f = follow("nuke", [400.0, 72.0, -40.0]);
        let t = f.path.hit - 3.0;
        for (yaw, pitch) in [(0.0, 0.0), (90.0, 30.0), (-135.0, -20.0)] {
            let d = look(yaw, pitch);
            let e = f.orbit(t, d);
            let back = sub(f.centre(t), e);
            // (along the look, the bomb straight ahead, at the orbit's distance)
            assert!((len(back) - DISTANCE).abs() < 1e-6);
            assert!(len(sub(back, d.map(|v| v * DISTANCE))) < 1e-6);
        }
        // and it only ever moves the player: the one command it gives keeps their view
        assert!(f.finish()[0].ends_with(" ~ ~"));
    }
}
