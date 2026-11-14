//! The World Eater's plan (laser 19; the pass shaders/worldeater*.wgsl): a mountain-sized worm. Its wormsign ploughs
//! through the land to the target, it bursts out of it there, arcs over, bites back into the land and pours through,
//! along a path that is data (strike/we_path.rs, the table the pass reads from word 0 of mod_data).
//!
//! Two takes (`/orbital worldeater hunt|scripted`, lib.rs passes it in `option`):
//! - SCRIPTED: PLAN.md's one-arch show (`we_default_plan`), 46 s.
//! - HUNT (the default): the worm decides as it goes (strike/we_land_hunt.rs). Arch 0 (out of the target at the breach)
//!   is aimed at the player as it fires; each arch after it is planned and appended while the head is still in the air
//!   on the one before (`decide`, 1.6 s before it comes down), aimed at where the player is then, on land the world says
//!   is loaded (`scout` asks 1 s before), within the hunt's limits. Two or three low hops, then the big arch with the
//!   bellow; at most WE_HUNT_LEN.
//!
//! For every arch, as it is planned (`arch_events`): its sounds (strike/we_sounds.rs), the jolts and the knockback of
//! its breach and its bite, the mobs and items along it killed, its chunks forceloaded, its holes' land
//! (strike/we_land.rs), the check whether its mouth closes over the player (`Catch`, strike/we_land_catch.rs) and the
//! next arch's planning. A watcher (`watch`) sinks each tunnelled stretch into a trench once its tail has gone in.
//!
//! The per-tick part (`WeHand`, given as the strike's `Act::Hand`: lib.rs calls its `tick` every tick of the strike with
//! the player's place) samples where the player is, makes the knockback as each front reaches them, and carries a
//! swallowed player (`world.carry-player`). The land's words for the pass are at WE_LAND_T (see `land_words`).
#[allow(unused_imports)]
use super::we_land::Hyp;
use super::we_land::{self as land, Hole, Trench};
use super::we_land_catch::{Catch, CatchKind};
use super::we_land_hunt::{self as hunt, Kind};
use super::we_path::{self, WE_BODY_T, WE_FX_T, WE_BREACH, WE_LAND_T, WE_LEN, WE_LEN_S, WE_R, WE_SIGN_T, WeGeo, WePath};
use super::we_sounds as we_snd;
use super::{Act, HandLight, Plan, Rng, Target, bedrock_top, falloff, mh};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::collections::BTreeSet;
use std::rc::Rc;

/// The path, shared by the stages that work it out and fill it in (the land's heights at its knots, more arches).
pub(super) type SharedPath = Rc<RefCell<WePath>>;

/// lib.rs's `option` for the World Eater: bit 0 the scripted take, bit 1 the knockback off.
pub(crate) const WE_OPT_SCRIPTED: usize = 1;
pub(crate) const WE_OPT_NO_KNOCK: usize = 2;
/// The strike's length for each take.
pub(crate) fn we_length(option: usize) -> f32 {
    if option & WE_OPT_SCRIPTED != 0 { WE_LEN_S as f32 } else { hunt::WE_HUNT_LEN as f32 }
}

/// The holes: P0's (the breach's) and every other knot's (a bite's, with its funnel).
const R_BREACH: f64 = 40.0;
const R_BITE: f64 = 45.0;
const RF_BITE: f64 = 60.0;
/// How long a hole takes to dig, from the middle out (under the body first: the body fills it the while).
const DIG_T: f32 = 2.6;
/// How far round a hole and along each arch's line mobs and items are killed.
const KILL: f64 = 110.0;
/// The chunks held round each knot and along each line (forceloaded as each is planned, let go at the end).
const LOAD_KNOT: f64 = 130.0;
const LOAD_LINE: f64 = 64.0;

// ---- the land's words (mod_data from WE_LAND_T, f32) ------------------------------------------------------------------
/// 0: 1 once given; 1: 1 for a hunt; 2: 1 with the terrain on.
/// 3: 2 (the words' layout: path contract v2).
/// 4..10, CAUGHT: t_close (the jaws shut over the player; -1 none), t_spit (spat: the arc out of the mouth begins),
/// t_free (let go, thrown), kind (1 a dive's, 2 a breach's), the hole it happened at (as `we_holes` numbers them: 2 i
/// arch i's breach, 2 i + 1 its dive), how deep they are held under its ground (negative: over it). The mouth closes
/// over them through the second before t_close; they are inside from t_close until t_spit (on a dive: down it, along
/// the run, up the next breach); out of the body by about t_spit + 0.4.
pub(super) const WL_CAUGHT: usize = 4;
/// 12, 13: the count of holes and of runs given.
pub(super) const WL_HOLES_N: usize = 12;
pub(super) const WL_RUNS_N: usize = 13;
/// From 16, a hole (WL_HW words; 2 i arch i's breach A_i, 2 i + 1 its dive D_i): x, y, z (from the origin), its radius,
/// its funnel's outer radius, when it opens (the head through it), when it is open to its edge, when its rim caves
/// (from, to; -1 none), its arch, its rim's reach, its felled trees' reach, 1 a breach or 2 a dive.
pub(super) const WL_HOLE: usize = 16;
pub(super) const WL_HW: usize = 16;
/// From 224, a tunnel (WL_RW words; the run into arch i, the first from W0): from x, y, z (where the run starts: W0, or
/// D_i-1), to x, y, z (A_i), when its rings start and end caving in behind the tail (from `from` to `to`, evenly; -1 not
/// yet planned), its half width, its depth, its rings, when the tail goes into it, when it leaves it.
pub(super) const WL_RUN: usize = 224;
pub(super) const WL_RW: usize = 16;
/// From 320: the furrow (from W0 to A_0): when it starts and ends being laid, its half width, how far behind the mound.
pub(super) const WL_FURROW: usize = 320;
pub(super) const WL_END: usize = 328;

// ---- the per-tick part ------------------------------------------------------------------------------------------------
/// A knockback due: when its front reaches the player, from (world), out and up (blocks a tick), how far it reaches.
#[derive(Clone, Copy, Debug)]
struct Shove {
    t: f64,
    from: [f64; 3],
    out: f64,
    up: f64,
    reach: f64,
}
/// A catch decided ahead (the gulp is cued 0.85 s before the jaws shut): made at `catch.t_close` if the player is still
/// within `within` (level) of the axis, else called off.
struct Pending {
    catch: Catch,
    within: f64,
    /// The hole the jaws close at (world).
    at: [f64; 3],
}
#[derive(Default)]
struct LiveState {
    /// Where the player has been (strike time, feet), the last second.
    samples: std::collections::VecDeque<(f64, [f64; 3])>,
    shoves: Vec<Shove>,
    pending: Option<Pending>,
    catch: Option<Catch>,
    /// A catch called off at the last moment (the words given for it taken back by `confirm`).
    called_off: bool,
    knock: bool,
    held: bool,
    /// Where a catch let go of them (for the tests).
    released: Option<(f64, [f64; 3])>,
    /// This strike's holes: their middles (world, the ground's height) and how far out they reach (level), for the
    /// guard after a catch lets go (`WeHand::tick`).
    holes: Vec<([f64; 3], f64)>,
}
type Live = Rc<RefCell<LiveState>>;

/// The game's calls the carry makes (in the tests, recorded for the stand-in player).
mod io {
    #[cfg(not(test))]
    pub fn carry(m: [f32; 3], turn: f32) -> bool {
        crate::sdk::world::carry_player(m[0], m[1], m[2], turn)
    }
    #[cfg(not(test))]
    pub fn push(v: [f32; 3]) {
        crate::sdk::world::push_player(v[0], v[1], v[2]);
    }
    #[cfg(not(test))]
    pub fn cmds(c: &[String]) {
        crate::sdk::world::run_commands(c);
    }
    #[cfg(test)]
    thread_local! {
        pub static LOG: std::cell::RefCell<(Option<[f32; 3]>, Option<[f32; 3]>, Vec<String>)> = Default::default();
    }
    #[cfg(test)]
    pub fn carry(m: [f32; 3], _turn: f32) -> bool {
        LOG.with(|l| l.borrow_mut().0 = Some(m));
        true
    }
    #[cfg(test)]
    pub fn push(v: [f32; 3]) {
        LOG.with(|l| l.borrow_mut().1 = Some(v));
    }
    #[cfg(test)]
    pub fn cmds(c: &[String]) {
        LOG.with(|l| l.borrow_mut().2.extend(c.iter().cloned()));
    }
}

/// The first approach's way (`sign_dir`, W0 to the target): turned towards the player so its line passes SIGN_PASS
/// beside them (the side by the seed), W0 `WE_SIGN` back along it, nearer them than the target is or as near as it can be
/// while staying within SIGN_NEAR: the head starts close to them and runs past them to the target, its crest in plain
/// view from the first second (at render distance 20 the game draws ~320 round the player; the scaffold's way put W0
/// ~510 off a player 280 from the target, and round 3's ~290).
const SIGN_NEAR: f64 = 290.0;
const SIGN_PASS: f64 = 70.0;
fn sign_way(me: [f64; 3], seed: u32) -> [f64; 2] {
    let d = me[0].hyp(me[2]);
    if d < 1.0 {
        return we_path::we_dir_rule(me, seed);
    }
    let u = [me[0] / d, me[2] / d];
    let l = we_path::WE_SIGN;
    // (W0 at angle th from the way to the player: |W0 - me|^2 = l^2 + d^2 - 2 l d cos th; the line passes d sin th from
    // them while they are nearer the target than W0)
    let th_near = ((l * l + d * d - SIGN_NEAR * SIGN_NEAR) / (2.0 * l * d)).clamp(-1.0, 1.0).acos();
    let th_pass = if d < l { (SIGN_PASS / d).min(1.0).asin() } else { 0.0 };
    let th = th_pass.min(th_near.max(0.0));
    let side = if seed % 2 == 1 { 1.0 } else { -1.0 };
    let (sn, cs) = (th * side).sin_cos();
    // (W0 = -sign_dir * l: the way from W0 to the target is minus the way to W0)
    let w = [u[0] * cs - u[1] * sn, u[0] * sn + u[1] * cs];
    [-w[0], -w[1]]
}

/// A line in the game's log about a catch (nobody can see a carry go wrong otherwise).
fn catch_log(text: &str) {
    #[cfg(not(test))]
    crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("worldeater catch: {text}"));
    #[cfg(test)]
    if std::env::var("WE_CATCH_LOG").is_ok() {
        eprintln!("worldeater catch: {text}");
    }
}

/// lib.rs's knockback, as the Nuke's (`Act::Shove`): out from under `from` and up, as hard as `knock_share` says.
fn knockback(s: &Shove, at: [f64; 3]) -> Option<[f32; 3]> {
    let (dx, dz) = (at[0] - s.from[0], at[2] - s.from[2]);
    let d = dx.hyp(dz);
    let k = super::knock_share(d, s.reach as f32);
    if k < 0.03 {
        return None;
    }
    let (ux, uz) = if d > 0.5 { (dx / d, dz / d) } else { (0.0, 1.0) };
    let k = f64::from(k);
    Some([(ux * s.out * k) as f32, (s.up * (0.35 + 0.65 * k.min(1.0))) as f32, (uz * s.out * k) as f32])
}

/// The strike's per-tick hook (its `Act::Hand`): see the module's notes. The hand darkens inside the worm.
struct WeHand {
    live: Live,
    /// When the way of a held-back carry may next be cut again; the world's bottom (bedrock's top) it never cuts into.
    recut: f64,
    floor: i32,
}
impl HandLight for WeHand {
    fn tick(&mut self, t: f32, at: [f64; 3]) {
        let t = f64::from(t);
        let mut l = self.live.borrow_mut();
        l.samples.push_back((t, at));
        while l.samples.len() > 21 {
            l.samples.pop_front();
        }
        // (a catch due: made if they are still there, else called off)
        if l.pending.as_ref().is_some_and(|p| t >= p.catch.t_close) {
            let p = l.pending.take().unwrap_or_else(|| unreachable!());
            let a = p.at;
            if (at[0] - a[0]).hyp(at[2] - a[2]) <= p.within && at[1] > a[1] - 70.0 && at[1] < a[1] + 90.0 {
                catch_log(&format!("jaws shut at {t:.2}: the player at {:.1} {:.1} {:.1}, {} track steps, spat at {:.2}", at[0], at[1], at[2], p.catch.track.len(), p.catch.t_spit));
                l.catch = Some(p.catch);
                l.held = true;
            } else {
                catch_log(&format!("called off at {t:.2}: the player at {:.1} {:.1} {:.1}, {:.1} from the hole", at[0], at[1], at[2], (at[0] - a[0]).hyp(at[2] - a[2])));
                l.called_off = true;
            }
        }
        let inside = l.catch.as_ref().is_some_and(|c| !c.done);
        // (the fronts' knockback, none while they are inside it)
        let knock = l.knock;
        let mut pushes = Vec::new();
        l.shoves.retain(|s| {
            if s.t > t {
                return true;
            }
            if knock && !inside && let Some(v) = knockback(s, at) {
                pushes.push(v);
            }
            false
        });
        for v in pushes.into_iter().take(1) {
            io::push(v);
        }
        let held = l.held;
        if l.catch.as_ref().is_some_and(|c| c.done) {
            drop(l);
            self.guard(t, at);
            return;
        }
        let Some(c) = l.catch.as_mut().filter(|c| !c.done) else { return };
        // (held back inside (the land in the way: a stretch of the passage not cut, a fill that found its chunk not yet
        // loaded): the way from where they are to where the track will be in half a second cut again, at most twice a second)
        if t > c.t_close + super::we_land_catch::SWALLOW && t < c.t_free() && dist(c.target(t), at) > 8.0 && t >= self.recut {
            self.recut = t + 0.5;
            let to = c.target(t + 0.5);
            let n = (dist(to, at) / 4.0).ceil().clamp(1.0, 12.0) as usize;
            let mut cmds = Vec::new();
            for i in 0..n {
                let (f0, f1) = (i as f64 / n as f64, (i + 1) as f64 / n as f64);
                let p0 = [at[0] + (to[0] - at[0]) * f0, at[1] + (to[1] - at[1]) * f0, at[2] + (to[2] - at[2]) * f0];
                let p1 = [at[0] + (to[0] - at[0]) * f1, at[1] + (to[1] - at[1]) * f1, at[2] + (to[2] - at[2]) * f1];
                let lo = [p0[0].min(p1[0]).floor() as i32 - 1, p0[1].min(p1[1]).floor() as i32 - 1, p0[2].min(p1[2]).floor() as i32 - 1];
                let hi = [p0[0].max(p1[0]).floor() as i32 + 1, p0[1].max(p1[1]).floor() as i32 + 2, p0[2].max(p1[2]).floor() as i32 + 1];
                let lo1 = lo[1].max(self.floor + 1);
                cmds.insert(i, format!("fill {} {} {} {} {} {} minecraft:tuff replace minecraft:water", lo[0] - 1, lo1 - 1, lo[2] - 1, hi[0] + 1, hi[1] + 1, hi[2] + 1));
                cmds.push(format!("fill {} {lo1} {} {} {} {} minecraft:air", lo[0], lo[2], hi[0], hi[1], hi[2]));
            }
            // (all the seals before any cut: see make_catch)
            catch_log(&format!("{t:.2}: held back {:.1} off the track at {:.1} {:.1} {:.1}: its way cut again", dist(c.target(t), at), at[0], at[1], at[2]));
            io::cmds(&cmds);
        }
        // (nothing picked up while carried: items lying where the carry passes (saplings and sticks from the leaves of
        // the trees whose trunks the strike took) would unlock recipes, the game's toast in the throat)
        if c.inside(t) && ((t - c.t_close) / 0.05).round() as i64 % 5 == 0 {
            io::cmds(&["execute at @s run kill @e[type=minecraft:item,distance=..6]".into()]);
        }
        let o = c.tick(t, at, held);
        let done = c.done;
        // (where it wants them and where they are, every half second; broken free or let go)
        if ((t - c.t_close) / 0.05).round() as i64 % 10 == 0 {
            let w = c.target(t);
            catch_log(&format!("{t:.2}: target {:.1} {:.1} {:.1}, the player at {:.1} {:.1} {:.1} ({:.1} off)", w[0], w[1], w[2], at[0], at[1], at[2], dist(w, at)));
        }
        if c.freed {
            catch_log(&format!("broken free at {t:.2} at {:.1} {:.1} {:.1}", at[0], at[1], at[2]));
        } else if let Some(v) = o.throw {
            catch_log(&format!("spat out at {t:.2} from {:.1} {:.1} {:.1}, thrown {:.2} {:.2} {:.2}", at[0], at[1], at[2], v[0], v[1], v[2]));
            if o.cmds.iter().any(|c| c.contains("run tp @s")) {
                let e = c.spit_end();
                catch_log(&format!("NOT where the arc ends ({:.1} {:.1} {:.1}, {:.1} off): put on the land there (a last resort: something held the carry back)", e[0], e[1], e[2], dist(e, at)));
            }
        }
        if let Some(v) = o.throw {
            io::push(v);
        }
        if !o.cmds.is_empty() {
            io::cmds(&o.cmds);
        }
        if done {
            l.released = Some((t, at));
        }
        if l.released.is_some_and(|r| r.0 + 4.0 > t && r.0 + 3.95 <= t) {
            catch_log(&format!("4 s after the release the player is at {:.1} {:.1} {:.1}", at[0], at[1], at[2]));
        }
        l.held = match o.carry {
            Some(m) => io::carry(m, o.turn),
            None => true,
        };
    }
    fn frame(&self, t: f32) -> ([f32; 3], [f32; 3]) {
        let l = self.live.borrow();
        let dark = l.catch.as_ref().is_some_and(|c| c.inside(f64::from(t)) && f64::from(t) > c.t_close + 0.4);
        (if dark { [0.24, 0.34, 0.36] } else { [1.0; 3] }, [1.0; 3])
    }
}
impl WeHand {
    /// For GUARD_T after a catch lets them go: if they are over one of this strike's holes and falling, or down in it,
    /// put them on the land past its reach (the way out from its middle to them), so a let-go never ends in a hole.
    fn guard(&mut self, t: f64, at: [f64; 3]) {
        let mut l = self.live.borrow_mut();
        let Some((tr, _)) = l.released else { return };
        if t > tr + GUARD_T {
            return;
        }
        let falling = l.samples.len() >= 2 && l.samples[l.samples.len() - 2].1[1] > at[1] + 0.05;
        let hit = l.holes.iter().find(|(c, reach)| (at[0] - c[0]).hyp(at[2] - c[2]) < *reach && (falling || at[1] < c[1] - 1.0)).copied();
        let Some((c, reach)) = hit else { return };
        let d = (at[0] - c[0]).hyp(at[2] - c[2]);
        let way = if d > 1.0 { [(at[0] - c[0]) / d, (at[2] - c[2]) / d] } else { l.catch.as_ref().map_or([1.0, 0.0], |k| k.dir) };
        let p = [c[0] + way[0] * (reach + 6.0), c[2] + way[1] * (reach + 6.0)];
        catch_log(&format!("{t:.2}: the player over hole at {:.0} {:.0} (falling: {falling}, at {:.1} {:.1} {:.1}): put on the land at {:.1} {:.1}", c[0], c[2], at[0], at[1], at[2], p[0], p[1]));
        // (and a moment's grace so this tick's move doesn't count as falling again)
        l.samples.clear();
        drop(l);
        io::cmds(&[super::we_land_catch::on_land(p[0], p[1]), "effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:resistance 10 4 true".into()]);
    }
}
/// How long after a catch lets go the guard watches.
const GUARD_T: f64 = 8.0;
impl Drop for WeHand {
    /// The strike over (stopped, or ended) while they are still inside: put on the land beside the hole, not left in it.
    fn drop(&mut self) {
        let l = self.live.borrow();
        if let Some(c) = l.catch.as_ref().filter(|c| !c.done) {
            let p = [c.axis[0] + c.dir[0] * (hunt::KNOT_GAP * 0.55), c.axis[1] + 2.0, c.axis[2] + c.dir[1] * (hunt::KNOT_GAP * 0.55)];
            io::cmds(&[
                format!("tp @s {:.2} {:.2} {:.2}", p[0], p[1], p[2]),
                "effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:slow_falling 10 0 true".into(),
                "effect give @s[gamemode=!creative,gamemode=!spectator] minecraft:resistance 15 4 true".into(),
            ]);
        }
    }
}

// ---- the strike's state ---------------------------------------------------------------------------------------------
/// A hole: arch i's breach A_i (2 i) or its dive D_i (2 i + 1), as `we_holes` numbers them.
struct HoleRec {
    hole: Hole,
    site: Option<land::Shared>,
    breach: bool,
    /// Its words: when it opens (the head through it) and is open to its edge, when its rim caves (from, to).
    t_open: f64,
    t_open_end: f64,
    cave: (f64, f64),
    /// When its land's stages are all worked out (the next hole's start after it).
    jobs_end: f32,
    /// Its dig's edits made, and gone in (lib.rs counts them as they go in: `Blocks::sent`).
    dig_made: Rc<std::cell::Cell<u32>>,
    dig_in: Rc<std::cell::Cell<u32>>,
}
/// A tunnel: the underground run into arch i (the first from W0), as `we_tunnels` has them; its land and its trench.
struct RunRec {
    site: Option<land::Shared>,
    trench: Option<Trench>,
    tail_in: f64,
    tail_out: f64,
}
struct World {
    geo: WeGeo,
    origin: [f64; 3],
    seed: u32,
    terrain: bool,
    hunt: bool,
    floor: i32,
    length: f64,
    hops: usize,
    path: SharedPath,
    holes: Vec<HoleRec>,
    runs: Vec<RunRec>,
    /// No more arches will be appended.
    done: bool,
    /// The scouted picks for the arch after arch k, and their survey's tag.
    scout: Option<(usize, u32, Vec<hunt::Pick>)>,
    rings: u32,
    settled: bool,
    loaded: BTreeSet<(i32, i32)>,
    live: Live,
    me0: [f64; 3],
    caught: [f64; 6],
    /// fx's Caught words (WE_FX_T): the jaws' time and the spit's; 0 none (cleared after the spit).
    fx_caught: [f64; 2],
    furrow: [f64; 4],
}
type St = Rc<RefCell<World>>;

impl World {
    fn world(&self, p: [f64; 3]) -> [f64; 3] {
        [self.origin[0] + p[0], self.origin[1] + p[1], self.origin[2] + p[2]]
    }
    /// Where the player is now (in the world): the last sample, or as it fired.
    fn me(&self) -> [f64; 3] {
        let l = self.live.borrow();
        l.samples.back().map(|s| s.1).or_else(|| crate::sdk::game::get_player().map(|p| [p.x, p.y, p.z])).unwrap_or(self.me0)
    }
    /// How fast the player has been moving (level, blocks a second) over the last second.
    fn me_v(&self) -> [f64; 2] {
        let l = self.live.borrow();
        match (l.samples.front(), l.samples.back()) {
            (Some(a), Some(b)) if b.0 - a.0 > 0.2 => [(b.1[0] - a.1[0]) / (b.0 - a.0), (b.1[2] - a.1[2]) / (b.0 - a.0)],
            _ => [0.0; 2],
        }
    }
    /// Whether a catch is under way or waiting.
    fn catching(&self) -> bool {
        let l = self.live.borrow();
        l.pending.is_some() || l.catch.as_ref().is_some_and(|c| !c.done)
    }
    /// Hole `h` (2 i arch i's breach, 2 i + 1 its dive), from the origin.
    fn hole_at(&self, h: usize) -> [f64; 3] {
        let p = self.path.borrow();
        let a = &p.arches[h / 2];
        if h % 2 == 0 { a.from } else { a.to }
    }
    fn hole_of(&self, h: usize) -> Hole {
        let w = self.world(self.hole_at(h));
        let (r, rf) = if h % 2 == 0 { (R_BREACH, R_BREACH) } else { (R_BITE, RF_BITE) };
        Hole::new(w[0], w[2], w[1].floor() as i32 - 1, r, rf, self.seed ^ (0x9e37 * (h as u32 + 1)))
    }
    /// Whether column (x, z) is in any hole but `h` (or its wall), `pad` further out.
    fn in_other(&self, h: usize, x: i32, z: i32, pad: f64) -> bool {
        self.holes.iter().enumerate().any(|(j, o)| j != h && o.hole.holds(x, z, pad))
    }
    /// The strike's end for fx (its dust faded by then): the last tail in and 15 s of settling, or the last trench's
    /// last ring and 4, within the strike's length.
    fn fx_end(&self) -> f64 {
        let pa = self.path.borrow();
        let Some(last) = pa.arches.last() else { return self.length - 0.5 };
        let tail = hunt::time_at(&pa.knots(), last.s1() + WE_LEN);
        let rings = self.runs.iter().filter_map(|r| r.trench.map(|t| f64::from(t.t1) + 4.0)).fold(0.0, f64::max);
        (tail + 15.0).max(rings).min(self.length - 0.5)
    }
    /// The land's words (WE_LAND_T on), as they stand.
    fn words(&self) -> Vec<u32> {
        let mut w = vec![-1.0f32; WL_END];
        w[0] = 1.0;
        w[1] = if self.hunt { 1.0 } else { 0.0 };
        w[2] = if self.terrain { 1.0 } else { 0.0 };
        w[3] = 2.0;
        w[WL_CAUGHT..WL_CAUGHT + 6].copy_from_slice(&self.caught.map(|v| v as f32));
        w[WL_HOLES_N] = self.holes.len() as f32;
        w[WL_RUNS_N] = self.runs.len() as f32;
        let pa = self.path.borrow();
        for (h, r) in self.holes.iter().enumerate().take((WL_RUN - WL_HOLE) / WL_HW) {
            let a = &pa.arches[h / 2];
            let at = if r.breach { a.from } else { a.to };
            let o = WL_HOLE + h * WL_HW;
            let row = [at[0], at[1], at[2], r.hole.r, r.hole.rf, r.t_open, r.t_open_end, r.cave.0, r.cave.1, (h / 2) as f64, r.hole.rim, r.hole.fell, if r.breach { 1.0 } else { 2.0 }];
            for (j, v) in row.iter().enumerate() {
                w[o + j] = *v as f32;
            }
        }
        for (k, r) in self.runs.iter().enumerate().take((WL_FURROW - WL_RUN) / WL_RW) {
            let a = &pa.arches[k];
            let o = WL_RUN + k * WL_RW;
            let (t0, t1, rings) = r.trench.map_or((-1.0, -1.0, 0.0), |t| (f64::from(t.t0), f64::from(t.t1), f64::from(t.rings)));
            let row = [a.run_from[0], a.run_from[1], a.run_from[2], a.from[0], a.from[1], a.from[2], t0, t1, land::TR_W, land::TR_D, rings, r.tail_in, r.tail_out];
            for (j, v) in row.iter().enumerate() {
                w[o + j] = *v as f32;
            }
        }
        w[WL_FURROW..WL_FURROW + 4].copy_from_slice(&self.furrow.map(|v| v as f32));
        w.into_iter().map(f32::to_bits).collect()
    }
}
fn give_words(q: &mut Plan, st: &World, t: f32) {
    q.ev.push((t, Act::Words { index: WE_LAND_T as u32, words: st.words() }));
    // (fx's: the jaws' time and the spit's (0: none), the strike's end for its dust to fade by)
    let fx = [st.fx_caught[0], st.fx_caught[1], st.fx_end()].map(|v| (v as f32).to_bits());
    q.ev.push((t, Act::Words { index: WE_FX_T as u32, words: fx.to_vec() }));
}

/// The World Eater's world warp's params now (lib.rs's `frame`, each frame), from the path's table: while the head is
/// under the land on a run or the land domes over its next breach (`WePath::mound`), fx's five:
/// [params 0, 1, 2, 10, 6] = the mound's x, its height, its z (x and z from the origin; the dome's place while the
/// dome is up), the dome's height, the way the head goes under the land (radians; `last` kept while it goes straight
/// up or down). None: the warp off.
pub(crate) fn we_warp_params(data: &[u32], t: f32, last: f32) -> Option<[f32; 5]> {
    let path = WePath::from_words(data);
    let m = path.mound(f64::from(t));
    if m.arch.is_none() && m.dome <= 0.0 {
        return None;
    }
    let at = if m.dome > 0.0 { m.dome_at } else { m.at };
    let tan = path.point(path.head(f64::from(t)).0).1;
    let ang = if tan[0].hyp(tan[2]) > 0.2 { tan[2].atan2(tan[0]) as f32 } else { last };
    Some([at[0] as f32, m.h as f32, at[2] as f32, m.dome as f32, ang])
}

/// [perf] Whether `t` is within a second of the jaws shutting over the player (CAUGHT's t_close) or of the spit: the
/// game's frames there are left to the swallow and the ride, the land's edits that can wait held back (lib.rs's `edit`).
pub(crate) fn we_quiet(data: &[u32], t: f32) -> bool {
    let w = |i: usize| data.get(WE_LAND_T as usize + WL_CAUGHT + i).map(|&b| f32::from_bits(b));
    [w(0), w(1)].into_iter().flatten().any(|c| c >= 0.0 && (t - c).abs() < 1.0)
}

thread_local! {
    /// [perf] The QUALITY tier (lib.rs's `we_tier`: 2 FULL, 1 FAST, 0 PERFORMANCE): at PERFORMANCE the land's dressing
    /// (the optional jobs: sculk, what hangs, felled logs, thrown blocks) is left out.
    static TIER: std::cell::Cell<u8> = const { std::cell::Cell::new(1) };
}
pub(crate) fn we_set_tier(t: u8) {
    TIER.with(|c| c.set(t));
}

/// The chunks within `reach` of the segments (from the origin, level), as forceload boxes a row of chunks each, less
/// those already held (`held`, which takes them in).
fn load_boxes(origin: [f64; 3], segs: &[([f64; 3], [f64; 3])], reach: f64, held: &mut BTreeSet<(i32, i32)>) -> Vec<[i32; 4]> {
    let mut set = BTreeSet::new();
    for (a, b) in segs {
        let (ax, az) = (origin[0] + a[0], origin[2] + a[2]);
        let (bx, bz) = (origin[0] + b[0], origin[2] + b[2]);
        let (c0, c1) = (((ax.min(bx) - reach) / 16.0).floor() as i32, ((ax.max(bx) + reach) / 16.0).floor() as i32);
        let (k0, k1) = (((az.min(bz) - reach) / 16.0).floor() as i32, ((az.max(bz) + reach) / 16.0).floor() as i32);
        let (dx, dz) = (bx - ax, bz - az);
        let l2 = (dx * dx + dz * dz).max(1e-9);
        for k in k0..=k1 {
            for c in c0..=c1 {
                let (mx, mz) = (f64::from(c * 16) + 8.0, f64::from(k * 16) + 8.0);
                let u = (((mx - ax) * dx + (mz - az) * dz) / l2).clamp(0.0, 1.0);
                if (mx - ax - u * dx).hyp(mz - az - u * dz) <= reach + 11.4 && held.insert((k, c)) {
                    set.insert((k, c));
                }
            }
        }
    }
    crate::meter::spend(2_000 * set.len() as u64);
    let mut out: Vec<[i32; 4]> = Vec::new();
    for (k, c) in set {
        match out.last_mut() {
            Some(l) if l[1] == k * 16 && l[2] == c * 16 - 1 && (l[2] - l[0] + 1) / 16 < 32 => l[2] = c * 16 + 15,
            _ => out.push([c * 16, k * 16, c * 16 + 15, k * 16 + 15]),
        }
    }
    out
}
/// The chunks within `reach` of every tunnel and every arch (from W0 on), as forceload boxes.
pub(super) fn we_load_boxes(origin: [f64; 3], path: &WePath, reach: f64) -> Vec<[i32; 4]> {
    let segs: Vec<([f64; 3], [f64; 3])> = path.arches.iter().flat_map(|a| [(a.run_from, a.from), (a.from, a.to)]).collect();
    load_boxes(origin, &segs, reach, &mut BTreeSet::new())
}
fn forceload(q: &mut Plan, st: &mut World, t: f32, segs: &[([f64; 3], [f64; 3])], reach: f64) {
    if !st.terrain {
        return;
    }
    let origin = st.origin;
    for [x0, z0, x1, z1] in load_boxes(origin, segs, reach, &mut st.loaded) {
        q.at(t, format!("forceload add {x0} {z0} {x1} {z1}"));
        q.ev.push(((st.length - 1.0) as f32, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
    }
}

/// A heavy jolt for a breach or a bite `d` blocks off, `big` how hard at its heart (0 to 1).
fn jolt(q: &mut Plan, t: f64, d: f64, big: f32) {
    let fo = falloff(d);
    let t = t as f32 + (d / 1715.0) as f32;
    q.shake(t, big * fo, 1.6);
    for n in 0..6 {
        q.shake(t + 0.08 + 0.12 * n as f32, (1.0 - 0.12 * n as f32) * big * fo * 0.8, 0.25);
    }
    q.shake(t + 0.6, 0.5 * big * fo, 4.0);
}

fn dist(a: [f64; 3], b: [f64; 3]) -> f64 {
    ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
}
fn kill_along(q: &mut Plan, t: f64, a: [f64; 3], b: [f64; 3]) {
    let n = ((b[0] - a[0]).hyp(b[2] - a[2]) / 70.0).ceil().max(1.0) as usize;
    for j in 0..=n {
        let f = j as f64 / n as f64;
        let p = [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
        q.at(t as f32 + 0.05 * j as f32, format!("execute positioned {:.1} {:.1} {:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{KILL}]", p[0], p[1], p[2]));
    }
}

/// Everything arch `k` brings, as it is planned (at the start for the first, or as it is appended): its tunnel's and its
/// line's chunks, its two holes (the breach A_k as it comes out, the dive D_k as it goes in) and their land, jolts,
/// knockback and kills, its tunnel's land, the check whether it closes over the player, and the next arch's planning.
fn arch_events(q: &mut Plan, st: &St, k: usize, now: f32) {
    let (a, a_w, d_w, run_w, me, len) = {
        let s = st.borrow();
        let a = s.path.borrow().arches[k].clone();
        (a.clone(), s.world(a.from), s.world(a.to), s.world(a.run_from), s.me(), s.length)
    };
    let big = a.hold.is_some() || a.apex >= 200.0;
    {
        let mut s = st.borrow_mut();
        forceload(q, &mut s, now, &[(a.run_from, a.from), (a.from, a.to)], LOAD_LINE);
        forceload(q, &mut s, now, &[(a.from, a.from), (a.to, a.to)], LOAD_KNOT);
        drop(s);
        // (the wormsign's run worked out on a stage of its own: a point and a head a tick of the run, hundreds)
        let st2 = st.clone();
        q.soon(now + 0.05, move |q| buck_run(q, &st2, k, super::clock().max(now + 0.05)));
        let mut s = st.borrow_mut();
        let (hb, hd) = (s.hole_of(2 * k), s.hole_of(2 * k + 1));
        let dig = f64::from(DIG_T);
        {
            let mut l = s.live.borrow_mut();
            for h in [&hb, &hd] {
                l.holes.push(([h.cx, f64::from(h.g + 1), h.cz], h.reach_max() + 2.0));
            }
        }
        s.holes.push(HoleRec { hole: hb, site: None, breach: true, t_open: a.t_out, t_open_end: a.t_out + dig, cave: (-1.0, -1.0), jobs_end: 0.0, dig_made: Rc::default(), dig_in: Rc::default() });
        s.holes.push(HoleRec { hole: hd, site: None, breach: false, t_open: a.t_in, t_open_end: a.t_in + dig, cave: (a.t_in + dig + 0.6, a.t_in + dig + 3.6), jobs_end: 0.0, dig_made: Rc::default(), dig_in: Rc::default() });
        s.runs.push(RunRec { site: None, trench: None, tail_in: -1.0, tail_out: -1.0 });
    }
    // ---- each hole's dig, logged as it goes in against when it was due
    if st.borrow().terrain {
        for (h, due) in [(2 * k, a.t_out), (2 * k + 1, a.t_in)] {
            let st2 = st.clone();
            let at = (due as f32 + DIG_T).max(now + 0.1);
            q.later(at, move |q| hole_log(q, &st2, h, due as f32, at));
        }
    }
    // ---- out at A_k: the breach
    let d_out = dist(a_w, me);
    jolt(q, a.t_out, d_out, if k == 0 { 0.9 } else if big { 0.8 } else { 0.6 });
    let (out, up, reach) = if k == 0 { (0.7, 0.5, 300.0) } else { (0.5, 0.4, 220.0) };
    st.borrow().live.borrow_mut().shoves.push(Shove { t: a.t_out + d_out / 343.0, from: a_w, out, up, reach });
    if st.borrow().terrain {
        // (round where it came out, and along the land over its run)
        kill_along(q, a.t_out + 0.1, a_w, a_w);
        kill_along(q, a.t_out + 0.3, run_w, a_w);
    }
    {
        let st2 = st.clone();
        q.later(((a.t_out - 1.0) as f32).max(now + 0.05), move |q| breach_catch(q, &st2, k));
    }
    breach_land(q, st, k, now);
    // ---- in at D_k: the bite
    let d_in = dist(d_w, me);
    jolt(q, a.t_in, d_in, if big { 1.0 } else { 0.65 });
    let (out, up, reach) = if big { (0.9, 0.6, 420.0) } else { (0.55, 0.4, 230.0) };
    st.borrow().live.borrow_mut().shoves.push(Shove { t: a.t_in + d_in / 343.0, from: d_w, out, up, reach });
    if st.borrow().terrain {
        kill_along(q, a.t_in + 0.2, a_w, d_w);
        q.at(a.t_in as f32 + 6.0, format!("execute positioned {:.1} {:.1} {:.1} run kill @e[type=minecraft:item,distance=..{KILL}]", d_w[0], d_w[1], d_w[2]));
    }
    bite_land(q, st, 2 * k + 1, a.t_in, now);
    // ---- its tunnel's land, read once the breach's hole is in (it caves in behind the tail: `watch`)
    {
        let st2 = st.clone();
        q.later(((a.t_out + 3.0) as f32).max(now + 0.5).min(len as f32 - 2.0), move |q| run_read(q, &st2, k));
    }
    // ---- what comes next: the scout and the decision 1.6 s before it comes down
    {
        let st2 = st.clone();
        q.soon(((a.t_in - 3.0) as f32).max(now + 0.05), move |q| scout(q, &st2, k));
        let st2 = st.clone();
        q.soon(((a.t_in - 2.0) as f32).max(now + 0.1), move |q| decide(q, &st2, k));
    }
    let s = st.borrow();
    give_words(q, &s, now.max(0.05));
}

/// A piece of the land's work, done by the pump (`pump`) once due.
type Job = Box<dyn FnOnce(&mut Plan)>;
/// The land's work waiting: when each is due, whether it may be shed when far behind (dressing nobody waits for:
/// sculk, what hangs, the felled logs, the thrown blocks), the job. Earliest first.
struct Queued {
    due: f32,
    optional: bool,
    job: Job,
}
thread_local! {
    static PUMP: RefCell<Vec<Queued>> = const { RefCell::new(Vec::new()) };
}
/// How far behind an optional job is shed, and how much of a stage the pump fills before it leaves the rest for the next.
const SHED: f32 = 1.0;
const PUMP_FILL: u64 = 2_500_000;
/// A hole's work: its jobs due from `start`, `dt` apart; those from `opt_from` on optional.
fn seq(_q: &mut Plan, start: f32, dt: f32, jobs: Vec<Job>, opt_from: usize) {
    PUMP.with(|p| {
        let mut p = p.borrow_mut();
        for (i, job) in jobs.into_iter().enumerate() {
            let due = start + dt * i as f32;
            let at = p.partition_point(|x| x.due <= due);
            p.insert(at, Queued { due, optional: i >= opt_from, job });
        }
    });
}
/// The land's own stage, every tick it has work due: as many due jobs as fit in the stage (the earliest first, so the
/// hole the body is about to go through comes before dressing behind it), optional ones more than SHED late dropped.
/// One stage a tick is all the game works through for a strike, so this is how the land keeps up.
fn pump(q: &mut Plan, at: f32, until: f32) {
    let now = super::clock().max(at);
    let mut shed = 0;
    loop {
        let next = PUMP.with(|p| {
            let mut p = p.borrow_mut();
            if p.first().is_some_and(|x| x.due <= now) { Some(p.remove(0)) } else { None }
        });
        let Some(j) = next else { break };
        if j.optional && (now - j.due > SHED || TIER.with(std::cell::Cell::get) == 0) {
            shed += 1;
            continue;
        }
        let from = q.ev.len();
        (j.job)(q);
        if j.optional {
            // (its edits dressing in the game's queue too: left out there when the frames run long, `Blocks::shed`)
            for (_, a) in &mut q.ev[from..] {
                if let Act::Blocks(b) = a {
                    b.shed = true;
                }
            }
        }
        if crate::meter::spent() >= PUMP_FILL {
            break;
        }
    }
    if shed > 0 {
        crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("worldeater: {shed} pieces of dressing shed at {now:.1} s (behind)"));
    }
    let busy = PUMP.with(|p| p.borrow().first().is_some_and(|x| x.due <= now + 0.05));
    if at < until {
        let t = at + if busy { 0.1 } else { 0.2 };
        q.later(t, move |q| pump(q, t, until));
    }
}
/// Part `p` of `n` of a site's cells within `r` (rows) of a hole's middle row `cz` (the hole's own work is all there: the
/// parts even).
fn part_rows(site: &land::Shared, p: usize, n: usize, cz: f64, r: f64) -> (usize, usize) {
    let (a, b) = site.borrow().rows((cz - r).floor() as i32, (cz + r).ceil() as i32);
    let per = (b - a).div_ceil(n).max(1);
    (a + p * per, (a + (p + 1) * per).min(b))
}
/// Part `p` of `n` of a site's cells (worked out as the job runs: the site is made after the jobs are planned).
fn part(site: &land::Shared, p: usize, n: usize) -> (usize, usize) {
    let len = site.borrow().cells.len();
    let per = len.div_ceil(n).max(1);
    (p * per, (p + 1) * per)
}

const BITE_SITE_R: f64 = 100.0;

/// The land at hole `j` (a dive's) for the head coming down at `t_in`: read now, worked out in the seconds before
/// (each edit timed: the hole from the middle out as the head goes in, its rim caving after, the trees round it felled,
/// what hangs, the sculk creeping out).
fn bite_land(q: &mut Plan, st: &St, j: usize, t_in: f64, now: f32) {
    let (terrain, hole, floor, made, dug) = {
        let s = st.borrow();
        (s.terrain, s.holes[j].hole, s.floor, s.holes[j].dig_made.clone(), s.holes[j].dig_in.clone())
    };
    if !terrain {
        return;
    }
    let site: land::Shared = Rc::default();
    st.borrow_mut().holes[j].site = Some(site.clone());
    let t_in = t_in as f32;
    // (after its arch's breach's own work, which comes first)
    let after = st.borrow().holes[j - 1].jobs_end;
    let start = (now + 1.7).max(t_in - 5.0).max(after).min(t_in - 1.0);
    // (read shortly before its work: the site's take-in stages kept out of the breach's)
    // (its work reaches 82 out, its sculk a little past 100: a disc of 100 read, two thirds of a breach's)
    land::read_new(q, (start - 1.3).max(now + 0.05), &site, start, move || land::disc(hole.cx, hole.cz, BITE_SITE_R));
    let mut jobs: Vec<Job> = Vec::new();
    for (pi, pn) in (0..9).map(|p| (p, 9usize)) {
        let (site, made, dug) = (site.clone(), made.clone(), dug.clone());
        jobs.push(Box::new(move |q| {
            let (i0, i1) = part_rows(&site, pi, pn, hole.cz, hole.reach_max() + 1.0);
            land::dig(q, &mut site.borrow_mut(), &hole, floor, t_in + 0.05, t_in + DIG_T, i0, i1, Some((&made, &dug)));
        }));
    }
    for (pi, pn) in (0..4).map(|p| (p, 4usize)) {
        let site = site.clone();
        jobs.push(Box::new(move |q| {
            let (i0, i1) = part_rows(&site, pi, pn, hole.cz, hole.reach_max() + 1.0);
            land::funnel(q, &mut site.borrow_mut(), &hole, t_in + DIG_T + 0.6, t_in + DIG_T + 3.6, i0, i1);
        }));
    }
    for (pi, pn) in (0..12).map(|p| (p, 12usize)) {
        let (site, st2) = (site.clone(), st.clone());
        jobs.push(Box::new(move |q| {
            let (i0, i1) = part_rows(&site, pi, pn, hole.cz, 82.0);
            let s = st2.borrow();
            let other = |x: i32, z: i32| s.in_other(j, x, z, 2.0);
            land::heap(q, &mut site.borrow_mut(), &hole, 0.0, 80.0, t_in + 0.4, i0, i1, &other);
        }));
    }
    let opt_from = jobs.len();
    {
        let site = site.clone();
        jobs.push(Box::new(move |q| land::felled(q, &mut site.borrow_mut(), &hole, t_in + 0.4, 0, usize::MAX)));
    }
    tidy_jobs(&mut jobs, &site, &hole, 82.0, t_in + DIG_T + 3.8);
    for (pi, pn) in (0..3).map(|p| (p, 3usize)) {
        let site = site.clone();
        jobs.push(Box::new(move |q| {
            let (i0, i1) = part_rows(&site, pi, pn, hole.cz, hole.reach_max() + 44.0);
            land::sculk(q, &mut site.borrow_mut(), &hole, t_in + DIG_T + 3.0, 7.0, i0, i1);
        }));
    }
    let dt = ((t_in - 0.3 - start) / jobs.len() as f32).clamp(0.05, 0.25);
    seq(q, start, dt, jobs, opt_from);
}
/// What hangs round a hole, in four bands of rows (edits at `t`).
fn tidy_jobs(jobs: &mut Vec<Job>, site: &land::Shared, hole: &Hole, reach: f64, t: f32) {
    let rr = reach.ceil() as i32 + 2;
    let iz = hole.cz.floor() as i32;
    let bands = if reach < 100.0 { 2 } else { 4 };
    let per = (2 * rr + 1 + bands - 1) / bands;
    for b in 0..bands {
        let (site, hole) = (site.clone(), *hole);
        let (z0, z1) = (iz - rr + b * per, (iz - rr + (b + 1) * per - 1).min(iz + rr));
        jobs.push(Box::new(move |q| land::tidy_rows(q, &site.borrow(), &hole, reach, z0, z1, t)));
    }
}

/// Arch `k`'s breach hole A_k: read as it is planned, worked out before the head breaks out at `t_out` (the hole dug
/// from then, as the body comes up through it), its rim heaped and the trees round it felled, blocks and trees thrown
/// out, sculk creeping out after.
fn breach_land(q: &mut Plan, st: &St, k: usize, now: f32) {
    let h = 2 * k;
    let (hole, floor, terrain, t_out, made, dug) = {
        let s = st.borrow();
        let t = s.path.borrow().arches[k].t_out;
        (s.holes[h].hole, s.floor, s.terrain, t, s.holes[h].dig_made.clone(), s.holes[h].dig_in.clone())
    };
    if !terrain {
        return;
    }
    let site: land::Shared = Rc::default();
    st.borrow_mut().holes[h].site = Some(site.clone());
    let t = t_out as f32;
    let start = (now + 1.3).max(t - 6.5);
    land::read_new(q, now + 0.05, &site, start - 0.1, move || land::disc(hole.cx, hole.cz, land::SITE_R));
    let mut jobs: Vec<Job> = Vec::new();
    for (pi, pn) in (0..9).map(|p| (p, 9usize)) {
        let (site, made, dug) = (site.clone(), made.clone(), dug.clone());
        jobs.push(Box::new(move |q| {
            let (i0, i1) = part_rows(&site, pi, pn, hole.cz, hole.reach_max() + 1.0);
            land::dig(q, &mut site.borrow_mut(), &hole, floor, t, t + DIG_T, i0, i1, Some((&made, &dug)));
        }));
    }
    let (rim, n) = if k == 0 { (6.0, 110) } else { (4.5, 80) };
    for (pi, pn) in (0..24).map(|p| (p, 24usize)) {
        let (site, st2) = (site.clone(), st.clone());
        jobs.push(Box::new(move |q| {
            let (i0, i1) = part(&site, pi, pn);
            let s = st2.borrow();
            let other = |x: i32, z: i32| s.in_other(h, x, z, 2.0);
            land::heap(q, &mut site.borrow_mut(), &hole, rim, 120.0, t + 0.05, i0, i1, &other);
        }));
    }
    let opt_from = jobs.len();
    {
        let s2 = site.clone();
        jobs.push(Box::new(move |q| land::thrown(q, &s2.borrow(), &hole, t, n, if k == 0 { 5 } else { 3 })));
        let site = site.clone();
        jobs.push(Box::new(move |q| land::felled(q, &mut site.borrow_mut(), &hole, t + 0.05, 0, usize::MAX)));
    }
    tidy_jobs(&mut jobs, &site, &hole, 122.0, t + DIG_T + 0.6);
    for (pi, pn) in (0..3).map(|p| (p, 3usize)) {
        let site = site.clone();
        jobs.push(Box::new(move |q| {
            let (i0, i1) = part_rows(&site, pi, pn, hole.cz, hole.reach_max() + 44.0);
            land::sculk(q, &mut site.borrow_mut(), &hole, t + DIG_T + 1.0, 7.0, i0, i1);
        }));
    }
    // (packed: the stages after it, the dive's, get the room)
    let dt = ((t + 1.5 - start) / jobs.len() as f32).clamp(0.05, 0.1);
    st.borrow_mut().holes[h].jobs_end = start + dt * jobs.len() as f32;
    seq(q, start, dt, jobs, opt_from);
}

/// Tunnel `k`'s land (the run into arch k: W0 to A_0, or D_k-1 to A_k), read once its breach's hole is in.
fn run_read(q: &mut Plan, st: &St, k: usize) {
    crate::trace("we run_read begins");
    let (terrain, a, b, holes) = {
        let s = st.borrow();
        let pa = s.path.borrow();
        let ar = &pa.arches[k];
        let (a, b) = (s.world(ar.run_from), s.world(ar.from));
        (s.terrain, [a[0], a[2]], [b[0], b[2]], s.holes.iter().map(|h| h.hole).collect::<Vec<_>>())
    };
    if !terrain {
        return;
    }
    // (only the holes near its line asked about each of its columns: every hole of the strike, every column, was most
    // of this stage's fuel; the corridor built 120 blocks of its length a stage, the site made after)
    let w = land::TR_W * 1.35;
    let (dx, dz) = (b[0] - a[0], b[1] - a[1]);
    let l2 = (dx * dx + dz * dz).max(1e-9);
    let near: Rc<Vec<Hole>> = Rc::new(
        holes
            .into_iter()
            .filter(|h| {
                let u = (((h.cx - a[0]) * dx + (h.cz - a[1]) * dz) / l2).clamp(0.0, 1.0);
                (h.cx - a[0] - u * dx).hyp(h.cz - a[1] - u * dz) < w + h.reach_max() + 2.0
            })
            .collect(),
    );
    let cols: Rc<RefCell<Vec<(i32, i32)>>> = Rc::default();
    let now = super::clock().max(0.0);
    let len = st.borrow().length as f32;
    let parts = (l2.sqrt() / 120.0).ceil().max(1.0) as usize;
    for p in 0..parts {
        let (cols, near, st2) = (cols.clone(), near.clone(), st.clone());
        q.later(now + 0.05 * p as f32, move |q| {
            let mut part = land::corridor_part(a, b, w, |x, z| near.iter().any(|h| h.holds(x, z, 0.0)), p, parts);
            crate::meter::spend(300 * part.len() as u64 * (1 + near.len() as u64));
            cols.borrow_mut().append(&mut part);
            if p + 1 == parts {
                let site: land::Shared = Rc::new(RefCell::new(land::Site::new(std::mem::take(&mut *cols.borrow_mut()))));
                st2.borrow_mut().runs[k].site = Some(site.clone());
                let t = super::clock().max(0.0);
                land::read(q, t + 0.05, &site, len - 3.0);
            }
        });
    }
}

/// Every half second: the trenches over the tunnels whose tail is about to go through (once that time can no longer
/// change), the settling after the last.
fn watch(q: &mut Plan, st: &St, at: f32) {
    crate::trace("we watch begins");
    let now = super::clock().max(at);
    let mut fire = Vec::new();
    {
        let s = st.borrow();
        let pa = s.path.borrow();
        let kn = pa.knots();
        // (the schedule is fixed up to the last arch's landing; past it only once no more arches can come)
        let fixed = if s.done { f64::MAX } else { pa.arches.last().map_or(0.0, |a| a.t_in) };
        for (k, r) in s.runs.iter().enumerate() {
            if r.trench.is_some() {
                continue;
            }
            let a = &pa.arches[k];
            let tail_in = hunt::time_at(&kn, a.run_s() + WE_LEN);
            let tail_out = hunt::time_at(&kn, a.s0 + WE_LEN);
            if tail_out <= fixed && tail_in - f64::from(now) <= 2.2 {
                fire.push((k, tail_in, tail_out));
            }
        }
    }
    for (k, tail_in, tail_out) in fire {
        sink(q, st, k, tail_in, tail_out, now);
    }
    let (done_all, settle) = {
        let s = st.borrow();
        let all = s.done && s.runs.iter().all(|r| r.trench.is_some());
        let last = s.runs.iter().filter_map(|r| r.trench.map(|t| (t.t1, t.ring_mid(t.rings / 2)))).max_by(|a, b| a.0.total_cmp(&b.0));
        (all && !s.settled, last)
    };
    if done_all {
        let mut s = st.borrow_mut();
        s.settled = true;
        let t = settle.map_or(f64::from(now) + 1.0, |x| f64::from(x.0) + 0.6);
        let at = settle.map_or([0.0; 3], |x| [x.1[0] - s.origin[0], 0.0, x.1[1] - s.origin[2]]);
        let me = s.me();
        if t < s.length - 1.0 {
            q.ev.extend(we_snd::we_settle_cue(&s.geo, t, at, me)); // sound: settle after the last ring
        }
    }
    let len = st.borrow().length as f32;
    if at + 0.5 < len - 1.0 && !st.borrow().settled {
        let st2 = st.clone();
        q.later(at + 0.5, move |q| watch(q, &st2, at + 0.5));
    }
}

/// Tunnel `k`'s tail goes through it from `tail_in` (at its start) to `tail_out` (out of the breach): the land over it
/// caves in behind the tail, ring by ring from its start to the breach.
fn sink(q: &mut Plan, st: &St, k: usize, tail_in: f64, tail_out: f64, now: f32) {
    crate::trace("we sink begins");
    let (tr, site, me, geo, origin, ring0, terrain) = {
        let mut s = st.borrow_mut();
        let (a, b) = {
            let pa = s.path.borrow();
            let ar = &pa.arches[k];
            (s.world(ar.run_from), s.world(ar.from))
        };
        let l = (b[0] - a[0]).hyp(b[2] - a[2]);
        let t0 = (tail_in + 0.3) as f32;
        let t1 = ((tail_out + 0.3) as f32).max(t0 + 3.0).min(s.length as f32 - 2.5).max(t0 + 1.0);
        let rings = ((l / 22.0).round() as u32).clamp(6, 18);
        let tr = Trench { a: [a[0], a[2]], b: [b[0], b[2]], seed: s.seed ^ (0x51 * (k as u32 + 3)), t0, t1, rings };
        s.runs[k].trench = Some(tr);
        (s.runs[k].tail_in, s.runs[k].tail_out) = (tail_in, tail_out);
        let r0 = s.rings;
        s.rings += rings;
        (tr, s.runs[k].site.clone(), s.me(), s.geo, s.origin, r0, s.terrain)
    };
    give_words(q, &st.borrow(), now.max(0.05));
    // (each ring heard as it gives way, ones closer than half a second apart left out; the player on it spared the fall)
    let mut last = -1.0f32;
    for j in 0..tr.rings {
        let t = tr.t0 + (tr.t1 - tr.t0) * j as f32 / (tr.rings - 1).max(1) as f32;
        let m = tr.ring_mid(j);
        if t - last >= 0.5 {
            q.ev.extend(we_snd::we_sink_cue(&geo, f64::from(t), [m[0] - origin[0], 0.0, m[1] - origin[2]], ring0 + j, me)); // sound: a tunnel ring
            last = t;
        }
        if terrain {
            q.at(t - 0.1, format!("effect give @a[x={:.1},y={:.1},z={:.1},distance=..{:.0},gamemode=!creative,gamemode=!spectator] minecraft:slow_falling 6 0 true", m[0], origin[1], m[1], land::TR_W + 30.0));
        }
    }
    let Some(site) = site.filter(|_| terrain) else { return };
    let n = site.borrow().cells.len();
    let parts = n.div_ceil(1800).max(1);
    let per = n.div_ceil(parts);
    // (a part a stage, its floors then its rings, spread over the time before it caves in)
    let t = now + 0.05;
    let dt = ((tr.t0 - 0.2 - t) / parts as f32).clamp(0.05, 0.15);
    let mut jobs: Vec<Job> = Vec::new();
    for p in 0..parts {
        let (site, i0, st2) = (site.clone(), p * per, st.clone());
        jobs.push(Box::new(move |q| {
            // (never in a hole planned since its land was read: a dive come down on the player beside it is dug as the
            // jaws shut, and the land under them stays till then)
            let holes: Vec<Hole> = st2.borrow().holes.iter().map(|h| h.hole).collect();
            let mut s = site.borrow_mut();
            land::trench_floors(&mut s, &tr, i0, i0 + per, &|x, z| holes.iter().any(|h| h.holds(x, z, 3.0)));
            land::trench_rings(q, &mut s, &tr, i0, i0 + per);
        }));
    }
    seq(q, t, dt, jobs, usize::MAX);
}

/// Where to aim (from the origin, level): the player now, led by half the time to `t_in` and at most 120 blocks.
fn aim_of(s: &World, t_in: f64) -> [f64; 2] {
    let me = s.me();
    let v = s.me_v();
    let lead = 0.5 * (t_in - f64::from(super::clock().max(0.0))).max(0.0);
    let (mut lx, mut lz) = (v[0] * lead, v[1] * lead);
    let ll = lx.hyp(lz);
    if ll > 120.0 {
        lx *= 120.0 / ll;
        lz *= 120.0 / ll;
    }
    [me[0] + lx - s.origin[0], me[2] + lz - s.origin[2]]
}
/// The picks for the arch after arch `k`, of `kind` (a swallowed player in its run: `caught`).
fn next_picks(s: &World, k: usize, kind: Kind, caught: bool) -> Vec<hunt::Pick> {
    let pa = s.path.borrow();
    let r = mh(k as u32 + 1, s.seed, 0x3a1);
    let (run_len, _) = hunt::run_want(mh(k as u32 + 1, s.seed, 0x3a3));
    // (a swallowed player's run as short as a run can be: the carry not a long ride in the dark)
    let run_len = if caught { we_path::WE_RUN_MIN } else { run_len };
    let t_in = pa.arches[k].t_in + 8.0;
    let next = if s.hunt { hunt::kind_of(k + 2, s.hops) } else { None };
    hunt::picks(&pa, aim_of(s, t_in), kind, next, run_len, caught, r)
}

/// The picks for the arch after arch `k`, scouted 2.6 s before it comes down: the world asked whether their land is
/// loaded (A and four points round it, and D).
fn scout(q: &mut Plan, st: &St, k: usize) {
    crate::trace("we scout begins");
    let s = st.borrow();
    if s.done {
        return;
    }
    // (the hunt's next, or, after its last arch or in the show, a spit arch in case the jaws close over the player)
    let (kind, caught) = match hunt::kind_of(k + 1, s.hops).filter(|_| s.hunt) {
        Some(kind) => (kind, false),
        None => (Kind::Spit, true),
    };
    let picks = next_picks(&s, k, kind, caught);
    // (the best eight, and six more spread over the rest: if the land the best are on is not loaded, the hunt goes on
    // over land that is)
    // (picks: the best 60, best first, then the best for each breach on the ring)
    let step = (picks.len().saturating_sub(8) / 6).max(1);
    let picks: Vec<hunt::Pick> = picks.iter().take(8).chain(picks.iter().skip(8).step_by(step).take(6)).copied().collect();
    let tag = crate::ground::new_tag();
    let mut cols = Vec::new();
    for c in picks.iter() {
        let (wa, wd) = (s.world(c.a), s.world(c.d));
        for (dx, dz) in [(0.0, 0.0), (40.0, 0.0), (-40.0, 0.0), (0.0, 40.0), (0.0, -40.0)] {
            cols.push(((wa[0] + dx).floor() as i32, (wa[2] + dz).floor() as i32));
        }
        cols.push((wd[0].floor() as i32, wd[2].floor() as i32));
    }
    let now = super::clock().max(0.0);
    q.ev.push((now, Act::Survey { tag, columns: cols }));
    drop(s);
    st.borrow_mut().scout = Some((k, tag, picks));
}

/// The jaws coming down at arch `k`'s dive, 1.6 s before: whether they close over the player; then the next arch planned
/// and appended (a hunt's next, or a small one to spit a swallowed player out).
fn decide(q: &mut Plan, st: &St, k: usize) {
    crate::trace("we decide begins");
    let now = super::clock().max(0.0);
    let (caught, kind, t_in) = {
        let s = st.borrow();
        let pa = s.path.borrow();
        let a = &pa.arches[k];
        let to = s.world(a.to);
        let me = s.me();
        let knock = s.live.borrow().knock;
        let over = (me[0] - to[0]).hyp(me[2] - to[2]) <= R_BITE + 2.0 && me[1] > to[1] - 60.0 && me[1] < to[1] + 70.0;
        // (with terrain off nothing is caught: the player can't be carried through the land, and the throat is drawn
        // only round a player inside the body)
        // (nor on the show's bite: its 46 seconds hold no spit arch carried out of the mouth; a breach's catch it keeps)
        let caught = knock && s.terrain && s.hunt && over && !s.catching() && pa.arches.len() == k + 1;
        if s.hunt || caught {
            catch_log(&format!(
                "the jaws at dive {k} come down {:.0} from the player ({:.0} over its ground): {}",
                (me[0] - to[0]).hyp(me[2] - to[2]),
                me[1] - to[1],
                if caught { "caught" } else if !knock { "catching is off" } else if !s.terrain { "terrain off: no catch" } else if !over { "out of reach" } else { "already caught, or the next arch planned" }
            ));
        }
        let kind = if s.done || pa.arches.len() > k + 1 {
            None
        } else if s.hunt {
            hunt::kind_of(k + 1, s.hops).or(caught.then_some(Kind::Spit))
        } else {
            caught.then_some(Kind::Spit)
        };
        (caught, kind, a.t_in)
    };
    let planned = kind.is_some_and(|kind| plan_next(q, st, k, kind, caught));
    if !planned {
        // (no more: what it has done is all; a hunt's last tails cued at their final times)
        let mut s = st.borrow_mut();
        if s.path.borrow().arches.len() == k + 1 && !s.done {
            s.done = true;
            if s.hunt {
                let me = s.me();
                let pa = s.path.borrow();
                q.ev.extend(we_snd::we_last_tails(&s.geo, &pa, me)); // sound: the last tails, once
            }
        }
    }
    if caught {
        // (on the next tick: the catch's own work, apart from the next arch's)
        let st2 = st.clone();
        q.soon(now + 0.05, move |q| make_catch(q, &st2, 2 * k + 1, t_in, super::clock().max(0.0)));
    }
}

/// Plan arch `k + 1` after arch `k`'s dive, of `kind` (its run short when it carries a swallowed player).
fn plan_next(q: &mut Plan, st: &St, k: usize, kind: Kind, caught: bool) -> bool {
    crate::trace("we plan_next begins");
    let now = super::clock().max(0.0);
    let picks = {
        let s = st.borrow();
        // (the scouted ones; with a swallowed player only those whose run is short enough to carry them along)
        let from = s.path.borrow().end_knot();
        let short = |c: &hunt::Pick| !caught || (c.a[0] - from[0]).hyp(c.a[2] - from[2]) <= hunt::RUN_CAUGHT + 1.0;
        match &s.scout {
            Some((sk, _, c)) if *sk == k && c.iter().any(short) => c.iter().copied().filter(short).collect(),
            _ => next_picks(&s, k, kind, caught),
        }
    };
    let mut best: Option<WePath> = None;
    let mut guessed = false;
    {
        let s = st.borrow();
        let pa = s.path.borrow();
        let r = mh(k as u32 + 1, s.seed, 0x3a2);
        let (_, v_run) = hunt::run_want(mh(k as u32 + 1, s.seed, 0x3a3));
        let v_run = if caught { hunt::RUN_V_CAUGHT } else { v_run };
        let cap = if kind == Kind::Spit { if s.hunt { hunt::LAST_T_IN_SPIT } else { s.length - 9.0 } } else { hunt::LAST_T_IN };
        let gy = s.origin[1].floor() as i32;
        let last_y = pa.end_knot()[1];
        let (v_out, _) = kind.speeds();
        let me = s.me();
        // (on land the world says is loaded (A and four points 40 round it, and D) if one there is nearly as good; else on
        // land it hasn't loaded (the far terrain round the target: forceloaded as the arch is planned), its heights
        // guessed from what is known near it and asked again once it loads (`refine`))
        let mut loaded: Option<(f64, WePath)> = None;
        let mut unloaded: Option<(f64, WePath)> = None;
        let mut tried = 0;
        for c in picks.iter().take(14) {
            if loaded.as_ref().is_some_and(|l| c.score + PREFER_LOADED >= l.0) {
                break;
            }
            // (each try some 400,000 instructions in the game's WebAssembly: no more than ten, and fewer once one is had)
            if tried >= 10 || ((loaded.is_some() || unloaded.is_some()) && (tried >= 6 || crate::meter::spent() > crate::meter::SOFT / 2)) {
                break;
            }
            let (wa, wd) = (s.world(c.a), s.world(c.d));
            let at = |w: [f64; 3], dx: f64, dz: f64| crate::ground::at((w[0] + dx).floor() as i32, (w[2] + dz).floor() as i32);
            let height = |w: [f64; 3], dx: f64, dz: f64| at(w, dx, dz).map(|g| f64::from(g + crate::ground::water((w[0] + dx).floor() as i32, (w[2] + dz).floor() as i32).unwrap_or(0) - gy));
            let round: Vec<Option<f64>> = [(0.0, 0.0), (40.0, 0.0), (-40.0, 0.0), (0.0, 40.0), (0.0, -40.0)].iter().map(|&(dx, dz)| height(wa, dx, dz)).collect();
            let known: Vec<f64> = round.iter().flatten().copied().collect();
            let all = known.len() == round.len();
            let hd = height(wd, 0.0, 0.0);
            let ya = round[0].unwrap_or_else(|| if known.is_empty() { hd.unwrap_or(last_y) } else { known.iter().sum::<f64>() / known.len() as f64 });
            let yd = hd.unwrap_or(ya);
            let full = all && hd.is_some();
            // (land not loaded only near the player: what the game draws round them, if not yet answered; never the far
            // terrain's LOD out past it, where the land may never load)
            let near_me = |w: [f64; 3]| (w[0] - me[0]).hyp(w[2] - me[2]) <= UNLOADED_NEAR;
            if !full && (unloaded.is_some() || !near_me(wa) || !near_me(wd)) {
                continue;
            }
            let p = hunt::Pick { a: [c.a[0], ya, c.a[2]], d: [c.d[0], yd, c.d[2]], score: c.score };
            tried += 1;
            crate::meter::spend(250_000);
            let np = hunt::with_pick(&pa, &p, kind, v_out, v_run, f64::from(now) + 2.6, r);
            #[cfg(test)]
            if std::env::var("WE_PICKS").is_ok() {
                eprintln!("{kind:?} pick {:?} loaded {full} -> {:?}", (c.a, c.d, c.score), np.as_ref().map(|n| (n.arches.last().unwrap().t_in, hunt::clear_of_itself(n))));
            }
            let Some(np) = np else { continue };
            if np.arches.last().is_none_or(|a| a.t_in > cap) || !hunt::clear_of_itself(&np) {
                continue;
            }
            if full {
                loaded = Some((c.score, np));
            } else {
                unloaded = Some((c.score, np));
            }
        }
        // (a spit arch must come out: anywhere it can, its holes as high as the dive it comes from)
        if loaded.is_none() && unloaded.is_none() && kind == Kind::Spit {
            for c in picks.iter().take(14) {
                let p = hunt::Pick { a: [c.a[0], last_y, c.a[2]], d: [c.d[0], last_y, c.d[2]], score: c.score };
                if let Some(np) = hunt::with_pick(&pa, &p, kind, v_out, v_run, f64::from(now) + 2.6, r)
                    && np.arches.last().is_some_and(|a| a.t_in <= cap)
                    && hunt::clear_of_itself(&np)
                {
                    unloaded = Some((c.score, np));
                    break;
                }
            }
        }
        best = match (loaded, unloaded) {
            (Some(l), Some(u)) if u.0 + PREFER_LOADED < l.0 => {
                guessed = true;
                Some(u.1)
            }
            (Some(l), _) => Some(l.1),
            (None, Some(u)) => {
                guessed = true;
                Some(u.1)
            }
            (None, None) => None,
        };
    }
    let Some(np) = best else { return false };
    {
        let s = st.borrow();
        *s.path.borrow_mut() = np;
        let pa = s.path.borrow();
        q.ev.push((now, Act::Words { index: 0, words: pa.words() }));
        let me = s.me();
        q.ev.extend(we_snd::we_arch_cues_at(&s.geo, &pa, k + 1, me, f64::from(now))); // sound: the appended arch (its run's wormsign with it; its ground from now)
    }
    st.borrow_mut().scout = None;
    arch_events(q, st, k + 1, now);
    if guessed {
        let st2 = st.clone();
        q.soon(now + 0.5, move |q| refine(q, &st2, k + 1, None, now + 0.5));
    }
    true
}

/// The land along a catch's spit arc answered (`tag`): the arc's top lifted to clear it; asked again until it is, up to the
/// spit.
fn arc_land(q: &mut Plan, st: &St, tag: u32, cols: Vec<(i32, i32)>, t_spit: f64, at: f32) {
    let now = super::clock().max(at);
    if crate::ground::ready(tag) {
        let known: Vec<i32> = cols.iter().filter_map(|&(x, z)| crate::ground::at(x, z).map(|g| g + crate::ground::water(x, z).unwrap_or(0))).collect();
        let all = known.len() == cols.len();
        let hi = known.into_iter().max();
        if let Some(hi) = hi {
            let s = st.borrow();
            let mut l = s.live.borrow_mut();
            let l = &mut *l;
            let c = match l.pending.as_mut() {
                Some(p) => Some(&mut p.catch),
                None => l.catch.as_mut(),
            };
            if let Some(c) = c {
                c.lift(f64::from(hi));
                catch_log(&format!("the land along the spit's arc as high as {hi}: its top {:.0}", c.top.unwrap_or(0.0)));
                // (a flight out of the mouth: let go FLY_LIFT over the highest land under it, and the pass told)
                if let Some((e, _, o)) = c.eye.as_mut()
                    && let Some(f) = e.flight.as_mut()
                {
                    f[8] = f[8].max(f64::from(hi) - o[1] + FLY_LIFT);
                    let mut e2 = e.clone();
                    if let Some(st) = c.start {
                        e2.stand = [st[0] - o[0], st[1] - o[1], st[2] - o[2]];
                    }
                    q.ev.push((now, Act::Words { index: we_path::WE_EYE_T as u32, words: e2.words() }));
                }
            }
            // (some of it not loaded yet: asked again, the arc lifted over what is known meanwhile; it only rises)
            if !all && f64::from(now) + 1.0 < t_spit {
                let st2 = st.clone();
                let tag = crate::ground::new_tag();
                q.ev.push((now, Act::Survey { tag, columns: cols.clone() }));
                q.later(now + 0.5, move |q| arc_land(q, &st2, tag, cols, t_spit, now + 0.5));
            }
            return;
        }
    }
    if f64::from(now) + 0.5 < t_spit {
        let st2 = st.clone();
        if crate::ground::ready(tag) {
            // (none of it loaded yet: asked again)
            let tag = crate::ground::new_tag();
            q.ev.push((now, Act::Survey { tag, columns: cols.clone() }));
            q.later(now + 0.5, move |q| arc_land(q, &st2, tag, cols, t_spit, now + 0.5));
        } else {
            q.later(now + 0.2, move |q| arc_land(q, &st2, tag, cols, t_spit, now + 0.2));
        }
    }
}

/// Hole `h`'s dig (due from `due` to `due + DIG_T`): logged once its edits are all in, how late the last of them went in
/// (to a tenth of a second); or, ten seconds on, how many never did.
fn hole_log(q: &mut Plan, st: &St, h: usize, due: f32, at: f32) {
    let now = super::clock().max(at);
    let (made, dug) = {
        let s = st.borrow();
        let Some(r) = s.holes.get(h) else { return };
        (r.dig_made.get(), r.dig_in.get())
    };
    let late = now - (due + DIG_T);
    if made > 0 && dug >= made {
        crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("worldeater land: hole {h} dug ({made} edits), due {due:.2} to {:.2} s, all in by {now:.2} s ({:.2} s late at most)", due + DIG_T, late.max(0.0)));
        return;
    }
    if late > 10.0 || now > st.borrow().length as f32 - 0.5 {
        crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("worldeater land: hole {h} (due {due:.2} s): {dug} of its {made} dig edits in by {now:.2} s"));
        return;
    }
    let st2 = st.clone();
    q.later(now + 0.1, move |q| hole_log(q, &st2, h, due, now + 0.1));
}

/// Arch `k`'s holes' heights, guessed where the world hadn't loaded their land as it was planned: asked again (the land
/// forceloaded by now, or soon), and set as the answers come, until a second before it breaches.
const PREFER_LOADED: f64 = 60.0;
/// How near the player a hole may be on land the world hasn't said it has loaded.
const UNLOADED_NEAR: f64 = 340.0;
fn refine(q: &mut Plan, st: &St, k: usize, asked: Option<u32>, at: f32) {
    let now = super::clock().max(at);
    let (cols, t_out, gy) = {
        let s = st.borrow();
        let pa = s.path.borrow();
        let Some(a) = pa.arches.get(k) else { return };
        let c: Vec<(i32, i32)> = [a.from, a.to].iter().map(|&p| s.world(p)).map(|w| (w[0].floor() as i32, w[2].floor() as i32)).collect();
        (c, a.t_out, s.origin[1].floor() as i32)
    };
    if f64::from(now) > t_out - 1.0 {
        catch_log(&format!("arch {k}'s land never loaded before it breached: its holes' heights guessed"));
        return;
    }
    let tag = match asked {
        Some(tag) if crate::ground::ready(tag) => {
            let h = |(x, z): (i32, i32)| crate::ground::at(x, z).map(|g| f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy));
            let (ya, yd) = (h(cols[0]), h(cols[1]));
            // (never while a catch is under way: its carry's track was worked out on the path as it is, and the body is
            // drawn on the path: moved now, the body would leave the player where the track has them)
            if st.borrow().catching() {
                catch_log(&format!("arch {k}'s holes' heights left as guessed: a catch is under way"));
                return;
            }
            if ya.is_some() || yd.is_some() {
                let mut s = st.borrow_mut();
                {
                    let mut pa = s.path.borrow_mut();
                    let a = &pa.arches[k];
                    catch_log(&format!("arch {k}'s holes' heights, guessed {:.0} and {:.0}, now {:?} and {:?}", a.from[1], a.to[1], ya, yd));
                    if let Some(y) = ya {
                        pa.set_hole_height(2 * k, y);
                    }
                    if let Some(y) = yd {
                        pa.set_hole_height(2 * k + 1, y);
                    }
                    q.ev.push((now, Act::Words { index: 0, words: pa.words() }));
                }
                for i in [2 * k, 2 * k + 1] {
                    if i < s.holes.len() {
                        let g = s.hole_of(i).g;
                        s.holes[i].hole.g = g;
                    }
                }
            }
            if ya.is_some() && yd.is_some() {
                return;
            }
            None
        }
        Some(tag) => Some(tag),
        None => None,
    };
    let tag = tag.unwrap_or_else(|| {
        let tag = crate::ground::new_tag();
        q.ev.push((now, Act::Survey { tag, columns: cols.clone() }));
        tag
    });
    let st2 = st.clone();
    q.later(now + 0.5, move |q| refine(q, &st2, k, Some(tag), now + 0.5));
}

/// The head coming up out of arch `k`'s breach, a second before: whether it comes up under the player.
fn breach_catch(q: &mut Plan, st: &St, k: usize) {
    let now = super::clock().max(0.0);
    let t_out = {
        let s = st.borrow();
        let pa = s.path.borrow();
        let a = &pa.arches[k];
        let from = s.world(a.from);
        let me = s.me();
        let over = (me[0] - from[0]).hyp(me[2] - from[2]) <= R_BREACH + 2.0 && me[1] > f64::from(s.floor) - 2.0 && me[1] < from[1] + 80.0;
        if !(over && s.terrain && s.live.borrow().knock && !s.catching()) {
            return;
        }
        a.t_out
    };
    make_catch(q, st, 2 * k, t_out, now);
}

/// The eye's place behind the head's tip as the spit starts (the jaws' hinge 40 behind it, and 15 more), where it is
/// let go (past the tip), the time it slides back after the shut, and the carry's fastest along the body (blocks a
/// second: inside the game's clamp of 4 a tick on any axis).
const MOUTH_B: f64 = 55.0;
const FALL_T: f64 = 2.7;
/// The swallow: at rest for EYE_BEAT after the jaws shut (the mouth passing over them), then drawn onto the centreline and
/// along it, easing in over EYE_EASE.
const EYE_BEAT: f64 = 0.7;
const EYE_EASE: f64 = 1.5;
const VMAX: f64 = 78.0;
/// The push and the flight: the push from riding MOUTH_B behind to out of the tip (seconds), the eye leaving the tip at
/// EXIT_V (blocks a second along the head's way), its flight to the let-go (seconds), and where that is from the tip:
/// FLY_FWD on along the head's way, FLY_SIDE out to the side (clear of the body, 34 round, and its holes), FLY_LIFT over
/// the land.
const PUSH_T: f64 = 2.4;
const EXIT_V: f64 = 50.0;
const FLY_T: f64 = 1.6;
const FLY_FWD: f64 = 25.0;
const FLY_SIDE: f64 = 65.0;
const FLY_LIFT: f64 = 8.0;

/// A catch at hole `h` (a breach's: the head up under them; a dive's: the jaws down on them) closing at `t_close`,
/// decided at `now`: its track worked out, its tunnel dug for it, its sounds and words.
fn make_catch(q: &mut Plan, st: &St, h: usize, t_close: f64, now: f32) {
    let s = st.borrow();
    let pa = s.path.borrow();
    let depth = if s.terrain { super::we_land_catch::DEPTH } else { -1.0 };
    let next = (h % 2 == 1).then(|| pa.arches.get(h / 2 + 1)).flatten();
    // (a dive: carried down it and along the run behind the head, up the next breach; else held and carried up the hole)
    // (when the carry gets how far along the path: the passage's stretches cut a little ahead of it)
    let mut reach_at: Vec<(f64, f64)> = Vec::new();
    // (a bite's carry out through the mouth: when they are let go, when the spit starts, the throw)
    let mut exit: Option<(f64, f64, [f64; 3])> = None;
    let mut eye: Option<we_path::WeEye> = None;
    let (kind, spit_h, track) = match next {
        Some(n) => {
            let k = h / 2;
            let kn = pa.knots();
            let mut track = Vec::new();
            // (the eye's place along the body: swallowed, it slides down the throat away from the mouth; then it closes on
            // the head along the run and up the spit arch, MOUTH_B behind the tip (15 behind the jaws' hinge) by the
            // spit's start, and is carried out through the open mouth at the arch's top, let go just past the tip)
            use super::we_land_catch::{CARRY_V, IN_MOUTH};
            let (h0, _) = n.hold.map_or((n.t_in - 1.0, n.t_in), |h| (h.0, h.1));
            // (the push: from riding MOUTH_B behind, the eye speeds up through the open mouth, past the teeth, and leaves
            // the tip at EXIT_V along the head's way; then flies, carried on a smooth arc clear of the body, to the
            // let-go, falling and moving out)
            let t_p = h0 + 0.2;
            let t_x = t_p + PUSH_T;
            let t_free = t_x + FLY_T;
            let t_spit = t_x - 0.5;
            let mut sp = pa.arches[k].s1() - 3.0;
            let mut v = 0.0f64;
            let mut t = t_close;
            let mut knots: Vec<[f64; 3]> = Vec::new();
            let mut deepest = (0.0f64, t_close);
            let mut fall_b: Option<f64> = None;
            while t <= t_p + 1e-6 && track.len() < 1200 {
                crate::meter::spend(3_000);
                let head = hunt::head_at(&kn, t).0;
                let hv = hunt::head_at(&kn, t + 0.05).0 - head;
                let (want, acc, vmax) = if t < t_close + FALL_T {
                    // (at rest for a beat as the mouth and throat pass over them, then drawn along, easing in, into the
                    // slide back: the throat's own pull, the head plunging away from them)
                    let u = ((t - t_close - EYE_BEAT) / EYE_EASE).clamp(0.0, 1.0);
                    (CARRY_V * u * u * (3.0 - 2.0 * u), 60.0, CARRY_V)
                } else {
                    // (closing on the head over the run, steadily, to MOUTH_B behind as the rise begins: the teeth come
                    // into view as it climbs; then riding there)
                    let b0 = *fall_b.get_or_insert(head - sp);
                    let t0 = t_close + FALL_T;
                    let f = ((n.t_out - t) / (n.t_out - t0).max(0.1)).clamp(0.0, 1.0);
                    let goal = head - (MOUTH_B + (b0 - MOUTH_B).max(0.0) * f);
                    (((goal - sp) / 0.6 + hv / 0.05).max(0.0), 45.0, VMAX)
                };
                v += (want.min(vmax) - v).clamp(-acc * 0.05, acc * 0.05);
                v = v.max(0.0);
                sp += v * 0.05;
                if sp > head - IN_MOUTH {
                    sp = (head - IN_MOUTH).max(sp - v * 0.05);
                }
                if head - sp > deepest.0 {
                    deepest = (head - sp, t);
                }
                // (a knot of the eye's cubic every quarter second: its place and speed along the centreline)
                let i = ((t - t_close) / 0.05).round() as usize;
                if i % 5 == 0 {
                    knots.push([t, sp, v]);
                }
                let p = pa.point(sp).0;
                track.push(s.world(p));
                reach_at.push((sp, t));
                t += 0.05;
            }
            // (riding at the head's own speed as the push starts, out of the tip at EXIT_V)
            // (the ride's own place and speed where the push starts: no step in s or its speed)
            let t_p = t - 0.05;
            knots.retain(|k| k[0] < t_p - 0.1);
            knots.push([t_p, sp, v]);
            let s_x = hunt::head_at(&kn, t_x).0;
            knots.push([t_x, s_x, EXIT_V]);
            // (its flight: from the tip moving along the head's way, out to one side of the arch and down, let go
            // falling and moving out: clear of the body, its holes and its way on)
            let (p0, tan) = pa.point(s_x);
            let v0 = [tan[0] * EXIT_V, tan[1] * EXIT_V, tan[2] * EXIT_V];
            let (ax, az) = {
                let l = tan[0].hyp(tan[2]);
                if l > 0.2 { (tan[0] / l, tan[2] / l) } else {
                    let (dx, dz) = (n.to[0] - n.from[0], n.to[2] - n.from[2]);
                    let l = dx.hyp(dz).max(1e-6);
                    (dx / l, dz / l)
                }
            };
            let holes: Vec<[f64; 3]> = pa.arches.iter().flat_map(|a| [a.from, a.to]).collect();
            let side = [1.0f64, -1.0]
                .into_iter()
                .max_by(|a, b| {
                    let clear = |sg: f64| {
                        let (lx, lz) = (p0[0] + ax * FLY_FWD - az * sg * FLY_SIDE, p0[2] + az * FLY_FWD + ax * sg * FLY_SIDE);
                        holes.iter().map(|h| (h[0] - lx).hyp(h[2] - lz)).fold(f64::MAX, f64::min)
                    };
                    clear(*a).total_cmp(&clear(*b))
                })
                .unwrap_or(1.0);
            let (nx, nz) = (-az * side, ax * side);
            let ground = n.from[1].max(n.to[1]);
            let l = [p0[0] + ax * FLY_FWD + nx * FLY_SIDE, ground + FLY_LIFT, p0[2] + az * FLY_FWD + nz * FLY_SIDE];
            let vl = [ax * 8.0 + nx * 14.0, -22.0, az * 8.0 + nz * 14.0];
            let me = s.me();
            eye = Some(we_path::WeEye {
                t_close,
                t_free,
                beat: EYE_BEAT,
                blend: EYE_EASE,
                stand: [me[0] - s.origin[0], me[1] - s.origin[1], me[2] - s.origin[2]],
                flight: Some([t_x, p0[0], p0[1], p0[2], v0[0], v0[1], v0[2], l[0], l[1], l[2], vl[0], vl[1], vl[2]]),
                knots: knots.into_iter().take(we_path::WE_EYE_MAX).collect(),
            });
            let e = eye.as_ref().unwrap_or_else(|| unreachable!());
            // (the track to its let-go, a place a tick: the passage's timing and the catch's last place)
            let mut tt = t_p + 0.05;
            while tt <= t_free + 1e-6 {
                let p = e.at(&pa, tt);
                track.push(s.world([p[0], p[1], p[2]]));
                tt += 0.05;
            }
            // (let go moving as the eye moves (blocks a tick): the view handed back with no jump)
            let throw = [vl[0] * 0.05, vl[1] * 0.05, vl[2] * 0.05];
            exit = Some((t_free, t_spit, throw));
            let closed = reach_at.iter().find(|r| r.1 > deepest.1 && hunt::head_at(&kn, r.1).0 - r.0 <= MOUTH_B + 1.0).map_or(-1.0, |r| r.1);
            catch_log(&format!(
                "the carry: shut {t_close:.2}, furthest behind the head {:.0} at {:.2}, closed up to {MOUTH_B} behind at {closed:.2}, pushed from {t_p:.2}, out of the mouth at {t_x:.2} at {EXIT_V} a second, let go {t_free:.2} at {:.0} {:.0} {:.0} (from the origin)",
                deepest.0,
                deepest.1,
                l[0],
                l[1],
                l[2]
            ));            (CatchKind::Bite, h + 1, track)
        }
        None => {
            let w = s.world(s.hole_at(h));
            (if h % 2 == 1 { CatchKind::Bite } else { CatchKind::Breach }, h, super::we_land_catch::breach_track(w, depth))
        }
    };
    let axis = s.world(s.hole_at(spit_h));
    let dir = spit_dir(&s, &pa, spit_h);
    // (with the terrain on, the run's own tunnel dug for them: three wide and four high along its middle)
    // (with the terrain on, a passage for them along the whole track, from over the dive's land to past the breach's:
    // fills, ahead of the holes' paced edits, so the carry, a collision move, is never stopped by land not dug yet)
    if s.terrain && let Some(n) = next {
        let (s_a, s_b) = (pa.arches[h / 2].s1() - 3.0, n.s0 + 40.0);
        let mut sp = s_a;
        let mut fills = 0;
        let mut cuts: Vec<(f64, [i32; 6])> = Vec::new();
        while sp < s_b {
            let (p0, p1) = (s.world(pa.point(sp).0), s.world(pa.point((sp + 4.0).min(s_b)).0));
            let (x0, x1) = (p0[0].min(p1[0]).floor() as i32 - 1, p0[0].max(p1[0]).floor() as i32 + 1);
            let (y0, y1) = (p0[1].min(p1[1]).floor() as i32 - 1, p0[1].max(p1[1]).floor() as i32 + 2);
            let (z0, z1) = (p0[2].min(p1[2]).floor() as i32 - 1, p0[2].max(p1[2]).floor() as i32 + 1);
            let y0 = y0.max(s.floor + 1);
            // (each stretch cut a second before the carry gets there, and never before the jaws shut: not under the
            // player's feet while they still stand there, and on land the run's forceloads have loaded by then (a fill
            // into a chunk not loaded does nothing))
            let reach = reach_at.iter().find(|r| r.0 >= sp).map_or(t_close, |r| r.1);
            cuts.push((reach, [x0, y0, z0, x1, y1, z1]));
            sp += 4.0;
        }
        // (the water round each stretch turned to tuff first, a block wider all round: a command sets water flowing, and
        // a passage cut by a river, a lake or an aquifer would flood. Every seal goes in before any stretch next to it is
        // cut (a seal a block wider than its own stretch reaches into its neighbour's, and water flowed into a stretch
        // cut already would be turned to tuff in the carry's way); the stretch cut 1.5 s before the carry gets there,
        // never before the jaws shut, and cut again 0.4 s before (a fill into a chunk not yet loaded does nothing))
        let at = |r: f64, lead: f64| (r - lead).max(t_close + 0.05).max(f64::from(now)) as f32;
        for (r, b) in &cuts {
            q.at(at(*r, 2.2), format!("fill {} {} {} {} {} {} minecraft:tuff replace minecraft:water", b[0] - 1, b[1] - 1, b[2] - 1, b[3] + 1, b[4] + 1, b[5] + 1));
        }
        for (r, b) in &cuts {
            q.at(at(*r, 1.5), format!("fill {} {} {} {} {} {} minecraft:air", b[0], b[1], b[2], b[3], b[4], b[5]));
        }
        for (r, b) in &cuts {
            q.at(at(*r, 0.4), format!("fill {} {} {} {} {} {} minecraft:air", b[0], b[1], b[2], b[3], b[4], b[5]));
        }
        fills += 3 * cuts.len() as u64;
        crate::meter::spend(3_000 * fills);
    }
    let mut c = Catch::new(kind, axis, t_close, track, dir);
    if let Some((t_free, t_spit, throw)) = exit {
        c.t_spit = t_spit;
        c.exit = Some((t_free, throw));
    }
    if let Some(e) = eye {
        // (the pass's eye: given now, where they stand now; given again as the jaws shut, where they stood then)
        q.ev.push((now, Act::Words { index: we_path::WE_EYE_T as u32, words: e.words() }));
        c.eye = Some((e, pa.clone(), s.origin));
    }
    // (let go past the reach of the hole it spits them from and of any hole near its arc's end)
    c.clear = s.hole_of(spit_h).reach_max() + super::we_land_catch::CLEAR_PAD;
    let (t_spit, t_free) = (c.t_spit, c.t_free());
    drop(pa);
    let within = if h % 2 == 0 { R_BREACH } else { R_BITE } + 14.0;
    // (the land along the spit's arc asked now: its top lifted over it before they are spat)
    let tag = crate::ground::new_tag();
    q.ev.push((now, Act::Survey { tag, columns: c.arc_columns() }));
    {
        let (st2, cols, t_spit) = (st.clone(), c.arc_columns(), c.t_spit);
        q.later(now + 0.2, move |q| arc_land(q, &st2, tag, cols, t_spit, now + 0.2));
    }
    s.live.borrow_mut().pending = Some(Pending { catch: c, within, at: s.world(s.hole_at(h)) });
    drop(s);
    {
        let mut s = st.borrow_mut();
        s.caught = [t_close, t_spit, t_free, if kind == CatchKind::Bite { 1.0 } else { 2.0 }, h as f64, depth];
        s.fx_caught = [t_close, t_spit];
    }
    // (fx's flag cleared once they are out and back in the world)
    {
        let st2 = st.clone();
        q.later((t_free + 1.6) as f32, move |q| {
            let mut s = st2.borrow_mut();
            if s.fx_caught[0] == t_close {
                s.fx_caught = [0.0; 2];
                drop(s);
                give_words(q, &st2.borrow(), (t_free + 1.6) as f32);
            }
        });
    }
    catch_log(&format!("decided at {now:.2}: {kind:?} at hole {h}, the jaws shut at {t_close:.2}, spat at {t_spit:.2} out of hole {spit_h}, let go at {t_free:.2}"));
    q.ev.extend(we_snd::we_caught_cues(t_close, t_spit)); // sound: caught
    give_words(q, &st.borrow(), now.max(0.05));
    // (called off at the last moment: the words taken back)
    let st2 = st.clone();
    q.soon((t_close + 0.1) as f32, move |q| {
        let off = std::mem::take(&mut st2.borrow().live.borrow_mut().called_off);
        if off {
            st2.borrow_mut().caught = [-1.0; 6];
            st2.borrow_mut().fx_caught = [0.0; 2];
            give_words(q, &st2.borrow(), (t_close + 0.1) as f32);
            q.ev.push(((t_close + 0.1) as f32, Act::Words { index: we_path::WE_EYE_T as u32, words: vec![0] }));
        } else {
            // (the eye's start where they really stood as the jaws shut)
            let s = st2.borrow();
            let l = s.live.borrow();
            if let Some(c) = l.catch.as_ref()
                && let (Some((e, _, o)), Some(st)) = (c.eye.as_ref(), c.start)
            {
                let mut e = e.clone();
                e.stand = [st[0] - o[0], st[1] - o[1], st[2] - o[2]];
                q.ev.push(((t_close + 0.1) as f32, Act::Words { index: we_path::WE_EYE_T as u32, words: e.words() }));
            }
        }
    });
}

/// The way to spit them out of hole `h`: of twelve, the one whose landing (some 80 out) is furthest from every other
/// hole, every arch's line and every tunnel's (where the land caves in).
fn spit_dir(_s: &World, pa: &WePath, h: usize) -> [f64; 2] {
    let at = if h % 2 == 0 { pa.arches[h / 2].from } else { pa.arches[h / 2].to };
    let holes: Vec<[f64; 3]> = pa.arches.iter().flat_map(|a| [a.from, a.to]).collect();
    let seg = |p: [f64; 2], a: [f64; 3], b: [f64; 3]| {
        let (dx, dz) = (b[0] - a[0], b[2] - a[2]);
        let l2 = (dx * dx + dz * dz).max(1e-9);
        let u = (((p[0] - a[0]) * dx + (p[1] - a[2]) * dz) / l2).clamp(0.0, 1.0);
        (p[0] - a[0] - u * dx).hyp(p[1] - a[2] - u * dz)
    };
    let mut best = ([1.0, 0.0], f64::MIN);
    for i in 0..12 {
        let a = std::f64::consts::TAU * f64::from(i) / 12.0;
        let d = [a.cos(), a.sin()];
        let land = [at[0] + d[0] * 82.0, at[2] + d[1] * 82.0];
        let mut score = holes.iter().enumerate().filter(|(k, _)| *k != h).map(|(_, k)| (k[0] - land[0]).hyp(k[2] - land[1]) - RF_BITE - 12.0).fold(200.0, f64::min);
        for ar in &pa.arches {
            score = score.min(seg(land, ar.from, ar.to) - 45.0).min(seg(land, ar.run_from, ar.from) - land::TR_W - 10.0);
        }
        if score > best.1 {
            best = (d, score);
        }
    }
    best.0
}

/// The land bucking over arch `k`'s run as the head passes under it (the first approach from W0 and every run after a
/// dive), from its first tick right up to its breach's hole: blocks thrown up in clusters (near the player), the ground
/// left disturbed, trees toppled away from the line (strike/we_land.rs's `buck_*`). Nothing with the terrain off.
fn buck_run(q: &mut Plan, st: &St, k: usize, now: f32) {
    let (terrain, a, b, along, seed, me) = {
        let s = st.borrow();
        let pa = s.path.borrow();
        let ar = &pa.arches[k];
        let (a, b) = (s.world(ar.run_from), s.world(ar.from));
        let (ex, ez) = (b[0] - a[0], b[2] - a[2]);
        let l = ex.hyp(ez).max(1.0);
        // (where the head is along the line a tick at a time, from the run's start to the breach)
        let n = ((ar.t_out - ar.run_t) / 0.05).ceil().max(1.0) as usize;
        crate::meter::spend(3_000 * n as u64);
        let along: Vec<(f32, f64)> = (0..=n)
            .map(|i| {
                let t = ar.run_t + 0.05 * i as f64;
                let m = s.world(pa.point(pa.head(t).0).0);
                (t as f32, ((m[0] - a[0]) * ex + (m[2] - a[2]) * ez) / l)
            })
            .collect();
        (s.terrain, [a[0], a[2]], [b[0], b[2]], Rc::new(along), s.seed ^ (0xb5 * (k as u32 + 1)), s.me())
    };
    #[cfg(test)]
    if std::env::var("WE_ALONG").is_ok() {
        eprintln!("run {k}: along {:?} .. {:?} ({} ticks)", &along[..4.min(along.len())], along.last(), along.len());
    }
    if k == 0 {
        st.borrow_mut().furrow = [f64::from(along.first().map_or(0.0, |x| x.0)), f64::from(along.last().map_or(0.0, |x| x.0)), land::BUCK_W, 0.0];
    }
    if !terrain {
        return;
    }
    let len = (b[0] - a[0]).hyp(b[1] - a[1]);
    // (thrown and ground: a stage each part of the line, as early as the run allows)
    let parts = (len / 80.0).ceil().max(1.0) as usize;
    let nt = along.len();
    // (each part due a little before the head gets there, the first at once: its throw and its ground two jobs)
    let first_t = |u: f64| along.iter().find(|x| x.1 >= u).map_or(now, |x| x.0);
    for p in 0..parts {
        let (u0, u1) = (len * p as f64 / parts as f64, len * (p + 1) as f64 / parts as f64);
        let (al, al2) = (along.clone(), along.clone());
        let throw: Job = Box::new(move |q| {
            let bk = land::Buck { a, b, along: &al, seed };
            let (j0, j1) = (al.partition_point(|x| x.1 < u0 - 6.0), al.partition_point(|x| x.1 < u1 - 6.0));
            land::buck_throw(q, &bk, me, j0, if p + 1 == parts { nt } else { j1 });
        });
        let ground: Job = Box::new(move |q| {
            let bk = land::Buck { a, b, along: &al2, seed };
            land::buck_ground(q, &bk, u0, u1);
        });
        seq(q, (first_t(u0) - 1.5).max(now + 0.05), 0.0, vec![throw, ground], usize::MAX);
    }
    // (the trees: the strip's land read along it, a part a stage)
    let site: land::Shared = Rc::default();
    // (only the strip and a block or two beside it, and only where the player can see it fall: the read is most of the
    // work)
    land::read_new(q, now + 0.05, &site, now + 2.0, move || {
        land::corridor(a, b, land::BUCK_W + 2.0, |x, z| (f64::from(x) - me[0]).hyp(f64::from(z) - me[2]) > land::BUCK_SEEN)
    });
    let mut jobs: Vec<Job> = Vec::new();
    for p in 0..3 {
        let (site, along) = (site.clone(), along.clone());
        jobs.push(Box::new(move |q| {
            let bk = land::Buck { a, b, along: &along, seed };
            let (i0, i1) = part(&site, p, 3);
            land::buck_trees(q, &mut site.borrow_mut(), &bk, i0, i1);
        }));
    }
    seq(q, now + 1.0, 0.1, jobs, 0);
}

/// The strike's start, on the tick after it fires: a hunt's first arch (its first hop, aimed at the player), the pass's
/// table and the body's (tinted once the land at the target is read), the sounds, every arch's events, the furrow,
/// every hole's and W0's land heights, the watcher.
fn start(q: &mut Plan, st: &St, hunting: bool, gy: i32) {
    crate::trace("we start begins");
    let t0 = 0.05;
    {
        let s = st.borrow();
        let sign = sign_way(s.geo.me, s.seed);
        // (the show's one arch, as we_default_plan has it, its approach from W0 on the sign's way)
        let mut path = WePath::new(sign);
        {
            use we_path::*;
            let (len, _) = we_arc_table(0.5 * WE_SPAN, WE_APEX);
            let pour = len / (WE_TAIL_IN - WE_TAIL_OUT);
            if path.try_push([0.0; 3], s.geo.d, WE_APEX, WE_BREACH, WE_V_BREACH, WE_BITE, pour, Some((WE_BELLOW.0, WE_BELLOW.1, 0.5 * len, WE_V_HOLD))).is_err() {
                path = we_default_plan(&s.geo);
            }
        }
        if hunting {
            let (seed, hops) = (s.seed, s.hops);
            let empty = WePath::new(sign);
            let me = s.me();
            let aim = [me[0] - s.origin[0], me[2] - s.origin[2]];
            let picks = hunt::picks(&empty, aim, Kind::Hop, hunt::kind_of(1, hops), 0.0, false, mh(0, seed, 0x3a1));
            if let Some(np) = picks.iter().take(14).find_map(|c| hunt::with_pick(&empty, c, Kind::Hop, Kind::Hop.speeds().0, 100.0, 0.0, mh(0, seed, 0x3a2))) {
                path = np;
            }
        }
        *s.path.borrow_mut() = path;
    }
    {
        // the pass's table (the path from word 0, the body's words at WE_BODY_T), the sounds of every arch it has now
        let s = st.borrow();
        let pa = s.path.borrow();
        q.ev.push((t0, Act::Table(pa.words())));
        q.ev.push((t0, Act::Words { index: WE_BODY_T as u32, words: super::we_body::we_body_words(&pa, s.seed) }));
        // (the fx's blocks: strike/we_fx.rs)
        q.ev.push((t0, Act::Words { index: (WE_FX_T + super::we_fx::WEF_BK) as u32, words: super::we_fx::we_fx_words(0, 0) }));
        if s.hunt {
            q.ev.extend(we_snd::we_arch_cues(&s.geo, &pa, 0, s.me0)); // sound: the hunt's first arch (the rest as appended)
        } else {
            q.ev.extend(we_snd::we_cues(&s.geo, &pa, s.me0)); // sound: the whole show
        }
    }
    let n = st.borrow().path.borrow().arches.len();
    for k in 0..n {
        arch_events(q, st, k, t0);
    }
    // every hole's land and W0's asked; the heights put on the path (and the table given again) once the world answers;
    // the body's words again with the biome's tints of the land at the target
    {
        let (cols, w0, tc) = {
            let s = st.borrow();
            let pa = s.path.borrow();
            let c: Vec<(i32, i32)> = pa.arches.iter().flat_map(|a| [a.from, a.to]).map(|k| s.world(k)).map(|w| (w[0].floor() as i32, w[2].floor() as i32)).collect();
            let w = s.world(pa.arches[0].run_from);
            (c, (w[0].floor() as i32, w[2].floor() as i32), (s.origin[0].floor() as i32, s.origin[2].floor() as i32))
        };
        let tag = crate::ground::new_tag();
        let mut all = cols.clone();
        all.push(w0);
        q.ev.push((0.1, Act::Survey { tag, columns: all }));
        let tint = crate::columns::new_tag();
        q.ev.push((0.1, Act::Read { tag: tint, columns: vec![tc], below: 1, above: 1 }));
        fn feet(q: &mut Plan, tag: u32, tint: u32, cols: Vec<(i32, i32)>, w0: (i32, i32), st: St, gy: i32, at: f32) {
            if !crate::ground::ready(tag) {
                if at < WE_BREACH as f32 - 1.0 {
                    q.later(at + 0.2, move |q| feet(q, tag, tint, cols, w0, st, gy, at + 0.2));
                }
                return;
            }
            let h = |(x, z): (i32, i32)| crate::ground::at(x, z).map(|g| f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy));
            {
                let s = st.borrow();
                let mut pa = s.path.borrow_mut();
                for (i, &c) in cols.iter().enumerate() {
                    if let Some(y) = h(c) {
                        pa.set_hole_height(i, y);
                    }
                }
                if let Some(y) = h(w0) {
                    pa.set_sign_height(y);
                }
                q.ev.push((at, Act::Words { index: 0, words: pa.words() }));
                if let Some(a) = crate::columns::take(tint) {
                    let (g, f) = a.tints(0);
                    q.ev.push((at, Act::Words { index: WE_BODY_T as u32, words: super::we_body::we_body_words_tinted(g, f) }));
                    q.ev.push((at, Act::Words { index: (WE_FX_T + super::we_fx::WEF_BK) as u32, words: super::we_fx::we_fx_words(g, f) }));
                }
            }
            // (the holes' ground with it)
            let mut s = st.borrow_mut();
            for i in 0..s.holes.len().min(cols.len()) {
                let g = s.hole_of(i).g;
                s.holes[i].hole.g = g;
            }
        }
        let st = st.clone();
        q.later(0.4, move |q| feet(q, tag, tint, cols, w0, st, gy, 0.4));
    }
    {
        let st2 = st.clone();
        q.later(1.0, move |q| watch(q, &st2, 1.0));
    }
    let s = st.borrow();
    give_words(q, &s, t0);
}

pub(super) fn worldeater_plan(laser: &'static Laser, target: &Target, terrain: bool, dimension: &str, shader_seed: f32, me: [f64; 3], option: usize) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed_i = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed_i as u64), bx, by, bz };
    let origin = [f64::from(bx) + 0.5, f64::from(by) + 1.0, f64::from(bz) + 0.5];
    let seed = shader_seed as u32;
    let geo = we_path::we_geo(origin, me, seed);
    let hunting = option & WE_OPT_SCRIPTED == 0;
    let length = f64::from(we_length(option));
    let hops = 2 + usize::from(mh(1, seed, 0x3a0) < 0.5);
    // (none yet: the show's arch, or a hunt's first, is worked out on the tick after it fires, `start`)
    let path: SharedPath = Rc::new(RefCell::new(WePath::new(geo.dir)));
    let live: Live = Rc::new(RefCell::new(LiveState { knock: option & WE_OPT_NO_KNOCK == 0, held: true, ..Default::default() }));
    let st: St = Rc::new(RefCell::new(World {
        geo,
        origin,
        seed,
        terrain,
        hunt: hunting,
        floor: bedrock_top(dimension),
        length,
        hops,
        path,
        holes: Vec::new(),
        runs: Vec::new(),
        done: false,
        scout: None,
        rings: 0,
        settled: false,
        loaded: BTreeSet::new(),
        live: live.clone(),
        me0: me,
        caught: [-1.0; 6],
        fx_caught: [0.0; 2],
        furrow: [-1.0; 4],
    }));
    let floor = st.borrow().floor;
    p.ev.push((0.0, Act::Hand(Box::new(WeHand { live, recut: 0.0, floor }))));
    // (the ground's tremor building as the head comes in under the land)
    let d = (me[0] - origin[0]).hyp(me[2] - origin[2]);
    let fo = falloff(d);
    let mut t = 2.0;
    while t < WE_SIGN_T as f32 {
        p.shake(t, 0.05 + 0.1 * t / WE_SIGN_T as f32 * fo, 0.8);
        t += 0.7;
    }
    if terrain {
        let sw = sign_way(geo.me, seed);
        let half = 0.5 * we_path::WE_SIGN;
        p.at(WE_SIGN_T as f32, format!("execute positioned {:.1} {:.1} {:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{KILL}]", origin[0] - sw[0] * half, origin[1], origin[2] - sw[1] * half));
    }
    // (the land's pump: a fresh queue for this strike)
    PUMP.with(|p| p.borrow_mut().clear());
    {
        let until = length as f32 - 0.5;
        p.later(0.1, move |q| pump(q, 0.1, until));
    }
    // the rest on the tick after it fires (the plan's own call kept light: a tick's fuel)
    {
        let st = st.clone();
        p.later(0.05, move |q| start(q, &st, hunting, by + 1));
    }
    let _ = WE_R;
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

#[cfg(test)]
mod tests {
    use super::super::we_land::tests::{column, ground_h};
    use super::super::{Blocks, Stage};
    use super::*;
    use std::collections::{HashMap, VecDeque};

    const AT: Target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
    const O: [f64; 3] = [10.5, 65.0, -2.5];
    fn laser() -> &'static Laser {
        crate::lasers::LASERS.iter().find(|l| l.key == "worldeater").expect("the World Eater")
    }
    fn gt(x: i32, z: i32) -> Option<i32> {
        Some(ground_h(x, z) + 1)
    }
    /// The land loaded only within 650 of the target (the rest of the world far terrain).
    fn gt_near(x: i32, z: i32) -> Option<i32> {
        (f64::from(x) - O[0]).hyp(f64::from(z) - O[2]).lt(&650.0).then(|| ground_h(x, z) + 1)
    }

    /// A strike played out: everything it did, tick by tick.
    #[derive(Default)]
    struct Run {
        /// (tick time, due, the edit)
        edits: Vec<(f32, f32, Blocks)>,
        cmds: Vec<(f32, String)>,
        sounds: Vec<(f32, String)>,
        /// (due, ran, meter spent)
        stages: Vec<(f32, f32, u64)>,
        data: Vec<u32>,
        /// When the path's table was given with each count of arches.
        tables: Vec<(f32, usize)>,
        /// The player's feet each tick, whether a carry moved them.
        feet: Vec<(f32, [f64; 3], bool)>,
        released: Option<(f64, [f64; 3])>,
        pushes: u32,
        /// The hook's teleports onto the land (when, where to).
        tps: Vec<(f32, [f64; 3])>,
        length: f32,
        path: WePath,
    }
    impl Run {
        fn word(&self, i: usize) -> f64 {
            f64::from(f32::from_bits(self.data.get(WE_LAND_T + i).copied().unwrap_or(0)))
        }
    }

    /// Play a strike of `option` with the player moving by `walk(t, feet)` (their own move each tick, while nothing
    /// carries or throws them), the land loaded as `ground` says. The carry moves them (stopped by the land as its
    /// edits leave it); thrown, they fly and fall until they land.
    fn play(option: usize, terrain: bool, me0: [f64; 3], walk: &dyn Fn(f64, [f64; 3]) -> [f64; 3], ground: fn(i32, i32) -> Option<i32>) -> Run {
        play_wet(option, terrain, me0, walk, ground, None)
    }
    fn play_wet(option: usize, terrain: bool, me0: [f64; 3], walk: &dyn Fn(f64, [f64; 3]) -> [f64; 3], ground: fn(i32, i32) -> Option<i32>, wet: Option<fn(i32, i32) -> Option<i32>>) -> Run {
        crate::ground::set_test(Some(ground));
        crate::ground::set_test_wet(wet);
        crate::columns::clear();
        io::LOG.with(|l| *l.borrow_mut() = Default::default());
        let length = we_length(option);
        let seed: f32 = SEED.with(|s| s.get()).unwrap_or_else(|| std::env::var("WE_SEED").map_or(37.0, |v| v.parse().unwrap()));
        let mut plan = super::super::plan(laser(), &AT, terrain, "minecraft:overworld", seed, me0, option);
        plan.sort_by(|a, b| a.0.total_cmp(&b.0));
        let mut run = Run { length, ..Default::default() };
        let (mut urgent, mut waiting): (VecDeque<(f32, Stage)>, VecDeque<(f32, Stage)>) = Default::default();
        let mut hand: Option<Box<dyn HandLight>> = None;
        let mut floor: HashMap<(i32, i32), i32> = HashMap::new();
        let first_air = |floor: &HashMap<(i32, i32), i32>, x: f64, z: f64| -> f64 {
            let c = (x.floor() as i32, z.floor() as i32);
            f64::from(floor.get(&c).copied().unwrap_or_else(|| ground(c.0, c.1).unwrap_or_else(|| ground_h(c.0, c.1) + 1)))
        };
        let mut feet = me0;
        let mut v = [0.0f64; 3];
        let mut carried = false;
        let mut free_fall = false;
        let mut passages: Vec<[i32; 6]> = Vec::new();
        let mut stood = f64::NAN;
        let mut seen_cmds = 0;
        let mut was_caught = false;
        let mut next = 0;
        let mut ticks = 0u32;
        loop {
            ticks += 1;
            let now = ticks as f32 * 0.05;
            crate::meter::reset();
            super::super::set_clock(now);
            crate::sdk::fake::with(|w| w.player = Some(horizon_mod_sdk::game::Player { x: feet[0], y: feet[1], z: feet[2], yaw: 0.0, pitch: 0.0, health: 20.0, food: 20, dimension: "minecraft:overworld".into() }));
            let mut worked_out = false;
            let mut work = |job: Stage, due: f32, plan: &mut Vec<(f32, Act)>, next: usize, run: &mut Run| {
                crate::meter::reset();
                let clock = std::time::Instant::now();
                let more = job();
                let ms = clock.elapsed().as_secs_f64() * 1e3;
                if std::env::var("WE_SLOW").is_ok() && ms > 1.0 {
                    eprintln!("slow stage due {due:.2} at {now:.2}: {ms:.2} ms, {:.2}M counted", crate::meter::spent() as f64 / 1e6);
                }
                // (and what lib.rs's work_out counts for what it gave: a run or a command a thousand)
                let made: u64 = more.iter().map(|(_, a)| match a {
                    Act::Blocks(b) => 1_000 * b.runs.len() as u64,
                    Act::Cmd(_) | Act::Spare(_) => 1_000,
                    _ => 0,
                }).sum();
                run.stages.push((due, now, crate::meter::spent() + made));
                if std::env::var("WE_FUEL").is_ok() {
                    eprintln!("stage due {due:.2} ran {now:.2}");
                }
                if std::env::var("WE_TRACE").is_ok() && crate::meter::spent() + made > 14_000_000 {
                    eprintln!("HEAVY STAGE due {due:.2}: {:.2}M ({:.2}M made)", (crate::meter::spent() + made) as f64 / 1e6, made as f64 / 1e6);
                }
                let mut rest = plan.split_off(next);
                rest.extend(more);
                rest.sort_by(|a, b| a.0.total_cmp(&b.0));
                plan.extend(rest);
            };
            if let Some((due, job)) = urgent.pop_front().or_else(|| waiting.pop_front()) {
                work(job, due, &mut plan, next, &mut run);
                worked_out = true;
            }
            while next < plan.len() && plan[next].0 <= now {
                let (t, act) = std::mem::replace(&mut plan[next], (0.0, Act::Cmd(String::new())));
                next += 1;
                let mut put = |i: usize, w: &[u32], run: &mut Run| {
                    if run.data.len() < i + w.len() {
                        run.data.resize(i + w.len(), 0);
                    }
                    run.data[i..i + w.len()].copy_from_slice(w);
                };
                match act {
                    Act::Cmd(c) | Act::Spare(c) => run.cmds.push((now, c)),
                    Act::Sound { event, .. } => run.sounds.push((now, event)),
                    Act::Blocks(b) => {
                        // (in at once, as if the game's pacing held none back)
                        if let Some(c) = &b.sent {
                            c.set(c.get() + 1);
                        }
                        for r in &b.runs {
                            if r.only.is_some() || r.surface.is_some() {
                                continue;
                            }
                            let air = b.edit().palette[r.block as usize].contains(":air");
                            if std::env::var("WE_FLOOR_DBG").is_ok() && r.x == feet[0].floor() as i32 && r.z == feet[2].floor() as i32 && air {
                                eprintln!("{now:.2}: air at the player's column from {} ({} runs, urgent {}, shed {}, first {:?})", r.y, b.runs.len(), b.urgent, b.shed, b.as_fills().first());
                            }
                            let e = floor.entry((r.x, r.z)).or_insert_with(|| ground(r.x, r.z).unwrap_or_else(|| ground_h(r.x, r.z) + 1));
                            if air && r.y <= *e {
                                *e = r.y;
                            } else if !air && r.y <= *e {
                                *e = (*e).max(r.y + r.height as i32);
                            }
                        }
                        run.edits.push((now, t, *b));
                    }
                    Act::Read { tag, columns, below, above } => {
                        if std::env::var("WE_FUEL").is_ok() {
                            eprintln!("read {} columns at {now:.2}", columns.len());
                        }
                        crate::columns::test_answer(tag, &columns, below, above, &|x, z| column(x, z, below, above))
                    }
                    Act::Survey { tag, columns } => crate::ground::test_answer(tag, &columns),
                    Act::Hand(h) => hand = Some(h),
                    Act::Table(w) => {
                        run.tables.push((now, WePath::from_words(&w).arches.len()));
                        put(0, &w, &mut run);
                    }
                    Act::Words { index, words } => {
                        if index == 0 {
                            run.tables.push((now, WePath::from_words(&words).arches.len()));
                        }
                        put(index as usize, &words, &mut run);
                    }
                    Act::Soon(job) if worked_out => urgent.push_back((t, job)),
                    Act::Later(job) | Act::Cleanup(job) if worked_out => waiting.push_back((t, job)),
                    Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                        work(job, t, &mut plan, next, &mut run);
                        worked_out = true;
                    }
                    _ => {}
                }
            }
            // (the per-tick hook, and what it asked of the game)
            if let Some(h) = &mut hand {
                h.tick(now, feet);
            }
            let (m, push, cmds) = io::LOG.with(|l| std::mem::take(&mut *l.borrow_mut()));
            // (the hook's teleports onto the land, as the game makes them)
            let tp: Option<(f64, f64)> = cmds.iter().rev().find_map(|c| {
                let w: Vec<&str> = c.strip_prefix("execute positioned ")?.split_whitespace().collect();
                if !c.ends_with("run tp @s ~ ~1 ~") {
                    return None;
                }
                Some((w[0].parse().ok()?, w[2].parse().ok()?))
            });
            run.cmds.extend(cmds.into_iter().map(|c| (now, c)));
            // (the passage's fills, as boxes the land can't hold)
            for c in &run.cmds[seen_cmds..] {
                if let Some(rest) = c.1.strip_prefix("fill ")
                    && rest.ends_with(" minecraft:air")
                {
                    let w: Vec<i32> = rest.split_whitespace().take(6).filter_map(|v| v.parse().ok()).collect();
                    if w.len() == 6 {
                        if std::env::var("WE_FLOOR_DBG").is_ok() && (w[0]..=w[3]).contains(&(feet[0].floor() as i32)) && (w[2]..=w[5]).contains(&(feet[2].floor() as i32)) {
                            eprintln!("{now:.2}: a fill over the player's column: {}", c.1);
                        }
                        passages.push([w[0], w[1], w[2], w[3], w[4], w[5]]);
                        // (where it opens the land's top, the ground there gone down to its bottom)
                        for x in w[0]..=w[3] {
                            for z in w[2]..=w[5] {
                                let e = floor.entry((x, z)).or_insert_with(|| ground(x, z).unwrap_or_else(|| ground_h(x, z) + 1));
                                if *e >= w[1] && *e <= w[4] + 1 {
                                    *e = w[1];
                                }
                            }
                        }
                    }
                }
            }
            seen_cmds = run.cmds.len();
            match (m, push) {
                (Some(d), _) => {
                    let d = d.map(f64::from);
                    assert!(d.iter().all(|x| x.abs() <= 4.0), "a carry over the game's clamp at {now}: {d:?}");
                    // (a collision move, as the game's: into land standing over where it would put them, only the
                    // climb goes; else lifted onto a step of up to a block)
                    // (in the passage dug for them (fills the stand-in land can't hold), nothing stops it)
                    let f = first_air(&floor, feet[0] + d[0], feet[2] + d[2]);
                    let to = [feet[0] + d[0], feet[1] + d[1], feet[2] + d[2]];
                    // (the player's whole box in one of the passage's boxes: 0.6 across, 1.8 tall, as the game's collision)
                    let fits = |b: &[i32; 6]| {
                        to[0] - 0.3 >= f64::from(b[0]) && to[0] + 0.3 <= f64::from(b[3]) + 1.0 && to[2] - 0.3 >= f64::from(b[2]) && to[2] + 0.3 <= f64::from(b[5]) + 1.0 && to[1] >= f64::from(b[1]) && to[1] + 1.8 <= f64::from(b[4]) + 1.0
                    };
                    let dug = passages.iter().any(fits);
                    if !dug && std::env::var("WE_CUT_DBG").is_ok() && f > feet[1] + d[1] + 1.0 {
                        eprintln!("{now:.2}: blocked at {to:?} (the land's top there {f}); nearest box {:?}", passages.iter().min_by(|a, b| {
                            let c = |b: &[i32; 6]| (f64::from(b[0] + b[3]) * 0.5 - to[0]).hyp(f64::from(b[2] + b[5]) * 0.5 - to[2]).hyp(f64::from(b[1] + b[4]) * 0.5 - to[1]);
                            c(a).total_cmp(&c(b))
                        }));
                    }
                    feet = if dug {
                        to
                    } else if f > feet[1] + d[1] + 1.0 {
                        [feet[0], (feet[1] + d[1]).max(first_air(&floor, feet[0], feet[2])), feet[2]]
                    } else {
                        [feet[0] + d[0], (feet[1] + d[1]).max(f), feet[2] + d[2]]
                    };
                    v = d;
                    carried = true;
                    was_caught = true;
                }
                (None, Some(p)) => {
                    // (thrown as a carry lets go, or a knockback)
                    run.pushes += 1;
                    if carried {
                        v = p.map(f64::from);
                        free_fall = true;
                    }
                    carried = false;
                }
                (None, None) => {
                    if carried {
                        free_fall = true;
                    }
                    carried = false;
                }
            }
            if let Some((x, z)) = tp {
                feet = [x, first_air(&floor, x, z) + 1.0, z];
                run.tps.push((now, feet));
                if !carried {
                    free_fall = true;
                }
            }
            // (the land gone from under them where they stood on it: they fall)
            let under = first_air(&floor, feet[0], feet[2]);
            if !carried && !free_fall && feet[1] > under + 0.01 && (feet[1] - stood).abs() < 0.01 {
                free_fall = true;
            }
            if !carried {
                if free_fall {
                    feet = [feet[0] + v[0], feet[1] + v[1], feet[2] + v[2]];
                    v = [v[0] * 0.91, (v[1] - 0.08) * 0.98, v[2] * 0.91];
                    let f = first_air(&floor, feet[0], feet[2]);
                    if feet[1] <= f {
                        feet[1] = f;
                        free_fall = false;
                        v = [0.0; 3];
                    }
                } else if !was_caught {
                    feet = walk(f64::from(now), feet);
                }
            }
            run.feet.push((now, feet, carried));
            stood = first_air(&floor, feet[0], feet[2]);
            if now >= length && urgent.is_empty() && waiting.is_empty() {
                break;
            }
            assert!(now < length + 30.0, "it never ended");
        }
        if let Some(h) = hand.take() {
            drop(h);
        }
        run.released = run.feet.iter().rev().find(|f| f.2).map(|f| (f64::from(f.0), f.1));
        run.path = WePath::from_words(&run.data);
        run
    }

    fn dug_at(run: &Run, x: f64, z: f64) -> bool {
        let (x, z) = (x.floor() as i32, z.floor() as i32);
        run.edits.iter().any(|(_, _, b)| {
            let e = b.edit();
            b.runs.iter().any(|r| r.x == x && r.z == z && r.y <= -57 && r.only.is_none() && e.palette[r.block as usize].contains(":air"))
        })
    }
    fn sunk_at(run: &Run, x: f64, z: f64, below: i32) -> bool {
        let (x, z) = (x.floor() as i32, z.floor() as i32);
        let g = ground_h(x, z);
        run.edits.iter().any(|(_, _, b)| {
            let e = b.edit();
            b.runs.iter().any(|r| r.x == x && r.z == z && r.y <= g - below && r.y > -50 && r.only.is_none() && e.palette[r.block as usize].contains(":air"))
        })
    }
    fn angle(a: [f64; 2], b: [f64; 2]) -> f64 {
        (a[0] * b[0] + a[1] * b[1]).clamp(-1.0, 1.0).acos().to_degrees()
    }

    /// What every strike must keep: the arches within the hunt's limits, each appended in time, none through one still
    /// standing; every hole dug where the path says and every run sunk; the budgets; and it ends.
    fn check(run: &Run, hunting: bool, terrain: bool, label: &str) {
        let p = &run.path;
        let n = p.arches.len();
        assert!(n >= 1, "{label}: no arches");
        p.check(f64::from(run.length)).unwrap_or_else(|v| panic!("{label}: the head stops ({v})"));
        assert!((p.arches[0].t_out - WE_BREACH).abs() < 1e-3, "{label}: out at the breach");
        let runs = p.runs();
        assert!(runs[n - 1].tail_in < f64::from(run.length) - 3.0, "{label}: the tail in at {} of {}", runs[n - 1].tail_in, run.length);
        let g = we_path::we_geo(O, [0.0; 3], 37);
        let _ = g;
        for k in 0..n {
            let a = &p.arches[k];
            let span = (a.to[0] - a.from[0]).hyp(a.to[2] - a.from[2]);
            if hunting {
                assert!((120.0..=330.0).contains(&span), "{label}: arch {k} spans {span}");
                let way = |f: [f64; 3], t: [f64; 3]| {
                    let l = (t[0] - f[0]).hyp(t[2] - f[2]).max(1e-9);
                    [(t[0] - f[0]) / l, (t[2] - f[2]) / l]
                };
                let own = way(a.from, a.to);
                if k == 0 {
                    assert!(angle(p.sign_dir, own) <= hunt::TURN_FIRST + 0.5, "{label}: arch 0 turns {}", angle(p.sign_dir, own));
                } else {
                    let b = &p.arches[k - 1];
                    let run = way(b.to, a.from);
                    let hd = (a.from[0] - b.to[0]).hyp(a.from[2] - b.to[2]);
                    assert!((we_path::WE_RUN_MIN - 1e-3..=we_path::WE_RUN_MAX + 1e-3).contains(&hd), "{label}: run {k} {hd}");
                    assert!(angle(way(b.from, b.to), run) <= hunt::RUN_TURN + 0.5, "{label}: run {k} turns {}", angle(way(b.from, b.to), run));
                    let lim = if a.hold.is_some() { hunt::TURN_FIRST } else { hunt::TURN_MAX };
                    assert!(angle(run, own) <= lim + 0.5, "{label}: arch {k} turns {}", angle(run, own));
                }
                // (appended before the head went in at the knot before)
                if k > 0 {
                    let when = run.tables.iter().find(|t| t.1 > k).map(|t| t.0).expect("appended");
                    assert!(f64::from(when) <= p.arches[k - 1].t_in - 0.5, "{label}: arch {k} appended at {when}, the head in at {}", p.arches[k - 1].t_in);
                }
                let mut pre = p.clone();
                pre.arches.truncate(k + 1);
                assert!(hunt::clear_of_itself(&pre), "{label}: arch {k} through one still standing");
            }
            for b in &p.arches[..k] {
                for (q, r) in [(b.from, a.from), (b.from, a.to), (b.to, a.from), (b.to, a.to)] {
                    assert!((q[0] - r[0]).hyp(q[2] - r[2]) >= hunt::KNOT_GAP - 1e-6, "{label}: holes of arch {k} too near an earlier one");
                }
            }
        }
        // (holds only on the big one)
        assert!(p.arches.iter().filter(|a| a.hold.is_some() && a.apex >= 150.0).count() <= 1, "one big arch held over its top at most (a spit arch is held at its own)");
        if terrain {
            for (k, h) in p.arches.iter().flat_map(|a| [a.from, a.to]).enumerate() {
                assert!(dug_at(run, O[0] + h[0], O[2] + h[2]), "{label}: hole {k} not dug");
            }
            // (each tunnel caved in behind its tail: the land over its middle sunk, none under an arch)
            let tunnels = p.tunnels();
            for (k, a) in p.arches.iter().enumerate() {
                let m = [O[0] + 0.5 * (a.run_from[0] + a.from[0]), O[2] + 0.5 * (a.run_from[2] + a.from[2])];
                let span = (a.from[0] - a.run_from[0]).hyp(a.from[2] - a.run_from[2]);
                assert!(span < 2.0 * (RF_BITE * 1.2) || sunk_at(run, m[0], m[1], 12), "{label}: run {k}'s trench not sunk in its middle ({:?} {:?}; words {:?})", a.from, a.to, (0..12).map(|j| run.word(WL_RUN + k * WL_RW + j)).collect::<Vec<_>>());
                let t0 = run.word(WL_RUN + k * WL_RW + 6);
                assert!(t0 >= tunnels[k].tail_in - 0.01 && t0 < tunnels[k].tail_in + 1.0, "{label}: tunnel {k} sinks at {t0}, its tail in at {}", tunnels[k].tail_in);
                let mid = [O[0] + 0.5 * (a.from[0] + a.to[0]), O[2] + 0.5 * (a.from[2] + a.to[2])];
                let under_arch = (a.to[0] - a.from[0]).hyp(a.to[2] - a.from[2]) > 2.0 * RF_BITE * 1.25 && !p.arches.iter().any(|b| {
                    let (dx, dz) = (b.from[0] - b.run_from[0], b.from[2] - b.run_from[2]);
                    let l2 = (dx * dx + dz * dz).max(1e-9);
                    let (px, pz) = (mid[0] - O[0] - b.run_from[0], mid[1] - O[2] - b.run_from[2]);
                    let u = ((px * dx + pz * dz) / l2).clamp(0.0, 1.0);
                    (px - u * dx).hyp(pz - u * dz) < 60.0
                });
                assert!(!under_arch || !sunk_at(run, mid[0], mid[1], 12), "{label}: the land under arch {k} sunk");
            }
        } else {
            assert!(run.edits.is_empty() && !run.cmds.iter().any(|c| c.1.starts_with("forceload") || c.1.contains("summon")), "{label}: the land changed with the terrain off");
        }
        // (nothing past the strike's end, every stage within the fuel the meter keeps it to)
        assert!(run.cmds.iter().all(|c| c.0 <= run.length + 0.05 || c.1.starts_with("forceload remove")), "{label}");
        let worst = run.stages.iter().map(|s| s.2).max().unwrap_or(0);
        assert!(worst < crate::meter::SOFT, "{label}: a stage spent {:.1}M (due {:?}; arches out/in {:?})", worst as f64 / 1e6, run.stages.iter().filter(|s| s.2 == worst).map(|s| s.0).collect::<Vec<_>>(), p.arches.iter().map(|a| (a.t_out, a.t_in)).collect::<Vec<_>>());
        for (due, ran, _) in &run.stages {
            if ran - due >= 3.0 {
                let mut bins = std::collections::BTreeMap::new();
                for st in &run.stages {
                    *bins.entry((st.0 * 2.0).floor() as i32).or_insert(0) += 1;
                }
                panic!("{label}: a stage due at {due} ran at {ran}; stages due a half second: {:?}", bins.iter().filter(|b| (*b.0 as f32) * 0.5 > due - 6.0 && (*b.0 as f32) * 0.5 < due + 1.0).collect::<Vec<_>>());
            }
        }
        // (the commands a tick within the carve budget, edits a tick within what pace lets through unheld)
        let mut cmds: HashMap<i32, usize> = HashMap::new();
        for (t, c) in &run.cmds {
            if crate::strike::block_cost(c).is_some() {
                *cmds.entry((t * 20.0).round() as i32).or_default() += 1;
            }
        }
        let most = cmds.values().max().copied().unwrap_or(0);
        assert!(most <= crate::CARVE_CMDS, "{label}: {most} world commands on one tick");
    }

    fn me_at(d: f64, a: f64) -> [f64; 3] {
        [O[0] + d * a.sin(), 70.0, O[2] + d * a.cos()]
    }
    fn still(_: f64, f: [f64; 3]) -> [f64; 3] {
        f
    }

    /// `cargo test --release we_catch_sweep -- --ignored --nocapture`: a standing player at 200 to 300 all round, on
    /// level land and 12 under the target: caught or not, and how far from them the big bite came down.
    #[test]
    #[ignore]
    fn we_catch_sweep() {
        let mut missed = 0;
        let mut n = 0;
        let one: Option<(f64, i32)> = std::env::var("WE_SWEEP_ONE").ok().map(|v| {
            let w: Vec<f64> = v.split(',').map(|x| x.parse().unwrap()).collect();
            (w[0], w[1] as i32)
        });
        for d in [200.0, 238.0, 260.0, 300.0] {
            for k in 0..8 {
                for dy in [0.0, -12.0] {
                    if one.is_some_and(|o| o != (d, k) || dy != 0.0) {
                        continue;
                    }
                    let mut me = me_at(d, f64::from(k) * 0.785 + 0.2);
                    me[1] += dy;
                    let run = play(0, true, me, &still, gt);
                    let p = &run.path;
                    let big = p.arches.iter().position(|a| a.hold.is_some());
                    let dist = big.map(|b| (O[0] + p.arches[b].to[0] - me[0]).hyp(O[2] + p.arches[b].to[2] - me[2]));
                    let caught = run.word(WL_CAUGHT + 3);
                    n += 1;
                    if caught <= 0.0 || dist.is_none_or(|d| d > R_BITE) {
                        missed += 1;
                    }
                    eprintln!("d {d} angle {k} dy {dy}: big {big:?} at {dist:?}, caught {caught}, arches {}", p.arches.len());
                }
            }
        }
        eprintln!("missed {missed} of {n}");
    }

    thread_local! {
        /// The seed `play` fires with (none: WE_SEED, or 37).
        static SEED: std::cell::Cell<Option<f32>> = const { std::cell::Cell::new(None) };
    }
    /// Steep hills everywhere but round the target (up to 40 over the land, in patches): the land a spit's arc may run into.
    fn gt_ridges(x: i32, z: i32) -> Option<i32> {
        let (fx, fz) = (f64::from(x), f64::from(z));
        let bump = ((fx / 23.0).sin() * (fz / 29.0).cos()).max(0.0);
        let near = ((fx - O[0]).hyp(fz - O[2]) / 60.0).clamp(0.0, 1.0);
        Some(ground_h(x, z) + 1 + (40.0 * bump * bump * near).round() as i32)
    }
    /// Plateaus 50 high in a checkerboard of 90-block squares, with sheer cliffs (none round the target).
    fn gt_cliffs(x: i32, z: i32) -> Option<i32> {
        let up = (x.div_euclid(90) + z.div_euclid(90)).rem_euclid(2) == 1 && (f64::from(x) - O[0]).hyp(f64::from(z) - O[2]) > 60.0;
        Some(ground_h(x, z) + 1 + if up { 50 } else { 0 })
    }

    /// A strike fired by a player standing at the bottom of an earlier hole, far under the land round (int R11L): no
    /// stage over a third of the tick's fuel by the meter.
    #[test]
    fn we_player_down_a_hole_costs_no_more() {
        for (d, k) in [(40.0, 0), (40.0, 3), (90.0, 5), (150.0, 2)] {
            let mut me = me_at(d, f64::from(k) * 0.785 + 0.2);
            LAKE.with(|l| l.set((me[0], me[2], false)));
            me[1] = 8.0;
            let run = play(0, true, me, &still, gt_pit);
            let worst = run.stages.iter().max_by_key(|s| s.2).unwrap();
            eprintln!("down a hole {d} {k}: worst stage {:.2}M due {:.2}", worst.2 as f64 / 1e6, worst.0);
            assert!(worst.2 < crate::meter::SOFT, "{:.2}M at {:.2}", worst.2 as f64 / 1e6, worst.0);
        }
    }

    /// `cargo test --release we_pick_bench -- --ignored --nocapture`: what a pick search and a try cost natively.
    #[test]
    #[ignore]
    fn we_pick_bench() {
        let run = play(0, true, me_at(250.0, 0.4), &still, gt);
        let p = run.path.clone();
        let mut short = p.clone();
        short.arches.truncate(3);
        let short = WePath::from_words(&short.words());
        let aim = [100.0, 150.0];
        let t = std::time::Instant::now();
        let picks = hunt::picks(&short, aim, Kind::Big, Some(Kind::Spit), 300.0, false, 0.5);
        let a = t.elapsed();
        let t = std::time::Instant::now();
        let mut ok = 0;
        for c in picks.iter().take(10) {
            if hunt::with_pick(&short, c, Kind::Hop, Kind::Hop.speeds().0, 100.0, short.arches.last().unwrap().t_in + 2.6, 0.5).is_some() {
                ok += 1;
            }
        }
        eprintln!("picks: {} in {:?}; 10 tries ({ok} made) in {:?}", picks.len(), a, t.elapsed());
    }

    /// The target at the bottom of an old pit 50 round (the land round it 65 higher), the player at the bottom of a well
    /// 10 round (`LAKE`'s middle) 57 under the target.
    fn gt_pit(x: i32, z: i32) -> Option<i32> {
        let (lx, lz, _) = LAKE.with(|l| l.get());
        let (fx, fz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
        Some(if (fx - lx).hyp(fz - lz) < 10.0 {
            8
        } else if (fx - O[0]).hyp(fz - O[2]) < 50.0 {
            65
        } else {
            130
        })
    }

    /// How far off the body's centreline the throat view holds (the body's word to come).
    const THROAT_OFF: f64 = 6.0;
    fn we_land_catch_swallow() -> f64 {
        super::super::we_land_catch::SWALLOW
    }

    /// Spits over many paths (seeds), players' places (so holes and ways out), on level land and among steep hills that
    /// hold the carry back: the let-go point is never over a hole of the strike, nor are they in one in the four seconds
    /// after (falling into it or down in it).
    #[test]
    fn we_spits_never_land_in_a_hole() {
        let mut n = 0;
        for seed in [7.0f32, 37.0, 11.0] {
            if std::env::var("WE_SPIT_ONE").is_ok_and(|v| v.parse::<f32>().unwrap_or(7.0) != seed) {
                continue;
            }
            SEED.with(|s| s.set(Some(seed)));
            for (d, k) in [(200.0, 0), (250.0, 3), (300.0, 5), (230.0, 6)] {
                if std::env::var("WE_SPIT_K").is_ok_and(|v| v.parse::<i32>().unwrap_or(-1) != k) {
                    continue;
                }
                for (ground, wet) in [
                    (gt as fn(i32, i32) -> Option<i32>, None),
                    (gt_ridges, None),
                    (gt_cliffs, None),
                    (gt_hill, Some(wet_hill as fn(i32, i32) -> Option<i32>)),
                    (gt_hill_limited, Some(wet_hill as fn(i32, i32) -> Option<i32>)),
                    (gt_river, Some(wet_river as fn(i32, i32) -> Option<i32>)),
                ] {
                    let me = me_at(d, f64::from(k) * 0.785 + 0.2);
                    let mut me = me;
                    LAKE.with(|l| l.set((me[0], me[2], false)));
                    ASKED.with(|a| a.borrow_mut().clear());
                    me[1] = f64::from(ground(me[0].floor() as i32, me[2].floor() as i32).unwrap()) + if wet.is_some_and(|w| w(me[0].floor() as i32, me[2].floor() as i32).is_some()) { 4.0 } else { 0.0 };
                    let run = play_wet(0, true, me, &still, ground, wet);
                    if run.word(WL_CAUGHT + 3) <= 0.0 {
                        continue;
                    }
                    n += 1;
                    let p = &run.path;
                    let holes: Vec<([f64; 3], f64)> = p
                        .arches
                        .iter()
                        .flat_map(|a| [(a.from, R_BREACH, R_BREACH), (a.to, R_BITE, RF_BITE)])
                        .map(|(h, r, rf)| ([O[0] + h[0], O[1] + h[1], O[2] + h[2]], Hole::new(0.0, 0.0, 0, r, rf, 1).reach_max()))
                        .collect();
                    // (no seal of the passage after a cut it reaches into: water that flowed into the cut would be tuff
                    // in the carry's way)
                    let mut cut: Vec<[i32; 6]> = Vec::new();
                    for c in &run.cmds {
                        let Some(rest) = c.1.strip_prefix("fill ") else { continue };
                        let w: Vec<i32> = rest.split_whitespace().take(6).filter_map(|v| v.parse().ok()).collect();
                        if w.len() < 6 {
                            continue;
                        }
                        if rest.ends_with(" minecraft:air") {
                            cut.push([w[0], w[1], w[2], w[3], w[4], w[5]]);
                        } else if rest.ends_with("minecraft:tuff replace minecraft:water") {
                            let hit = cut.iter().find(|b| (0..3).all(|i| b[i] <= w[i + 3] && w[i] <= b[i + 3]));
                            assert!(hit.is_none(), "seed {seed} d {d} k {k}: a seal {w:?} at {:.2} after a cut {:?} it reaches into", c.0, hit);
                        }
                    }
                    let last = run.feet.iter().rposition(|f| f.2).expect("carried");
                    let t0 = run.feet[last].0;
                    // (standing on the land until the jaws shut: nothing opens under them once the catch is decided (a step of the
                    // wormsign's scar at most))
                    let t_close = run.word(WL_CAUGHT) as f32;
                    let before: Vec<&(f32, [f64; 3], bool)> = run.feet.iter().filter(|f| f.0 > t_close - 1.85 && f.0 < t_close - 0.02).collect();
                    let y0 = before.first().map_or(0.0, |f| f.1[1]);
                    assert!(before.iter().all(|f| f.1[1] >= y0 - 1.5), "seed {seed} d {d} k {k}: the ground fell away under them before the jaws shut at {t_close}: {:?}", before.iter().map(|f| (f.0, f.1[1])).collect::<Vec<_>>());
                    // (the player on the pass's eye (we_eye, from the words as the pass reads them) every tick of the carry,
                    // within a block, and within half a block at the let-go, moving as it moves)
                    if let Some(eye) = we_path::WeEye::from_words(&run.data) {
                        let path = WePath::from_words(&run.data);
                        for f in run.feet.iter().filter(|f| f64::from(f.0) >= eye.t_close + 0.06 && f64::from(f.0) <= eye.t_free - 0.01) {
                            // (the stand-in records a tick's place under its start: the carry made that tick put them
                            // where the eye is at its end)
                            let e = eye.at(&path, f64::from(f.0) + 0.05);
                            let off = (O[0] + e[0] - f.1[0]).hyp(O[2] + e[2] - f.1[2]).hyp(O[1] + e[1] - f.1[1]);
                            assert!(off < 1.0, "seed {seed} d {d} k {k}: at {:.2} the player {off:.2} off the eye", f.0);
                        }
                        let e = eye.at(&path, eye.t_free);
                        let held = run.feet[last].1;
                        let off = (O[0] + e[0] - held[0]).hyp(O[2] + e[2] - held[2]).hyp(O[1] + e[1] - held[1]);
                        assert!(off < 0.5, "seed {seed} d {d} k {k}: let go {off:.2} off the eye");
                    } else {
                        panic!("seed {seed} d {d} k {k}: no eye written");
                    }
                    // (inside the body all the way: every tick of the carry, from the throat's first second to the spit, on the
                    // body's centreline as the strike's final path draws it (within THROAT_OFF), behind its mouth)
                    let first = run.feet.iter().position(|f| f.2).expect("carried");
                    for f in &run.feet[first..=last] {
                        let t = f64::from(f.0);
                        if t < t_close as f64 + we_land_catch_swallow() || t > f64::from(run.word(WL_CAUGHT + 1) as f32) {
                            continue;
                        }
                        let head = p.head(t).0;
                        let mut best = (f64::MAX, 0.0);
                        let mut sp = head - 400.0;
                        while sp <= head {
                            let c = p.point(sp).0;
                            let d = (O[0] + c[0] - f.1[0]).hyp(O[2] + c[2] - f.1[2]).hyp(O[1] + c[1] - f.1[1]);
                            if d < best.0 {
                                best = (d, head - sp);
                            }
                            sp += 0.5;
                        }
                        assert!(best.0 < THROAT_OFF, "seed {seed} d {d} k {k}: at {t:.2} the player {:.1} off the body's centreline (nearest {:.1} behind the head) at {:?}", best.0, best.1, f.1);
                    }
                    // (a survival player takes no damage from the fall: Resistance V (amplifier 4: all damage) given at
                    // the let-go lasts till a second after they have landed, in water or on a slope as anywhere)
                    let land = run.feet[last + 1..].windows(3).find(|w| w[0].1 == w[1].1 && w[1].1 == w[2].1).map(|w| w[0].0);
                    let land = land.expect("landed");
                    if std::env::var("WE_SPIT_LOG").is_ok()
                        && let Some(eye) = we_path::WeEye::from_words(&run.data)
                        && let Some(fl) = eye.flight
                    {
                        let spit = p.arches.iter().find(|a| (a.t_out - eye.t_close) > 0.0).map(|a| a.from).unwrap_or([0.0; 3]);
                        let end = run.feet.iter().find(|f| f.0 >= land).map_or([0.0; 3], |f| f.1);
                        eprintln!(
                            "THROW seed {seed} d {d} k {k}: out of the mouth {:.0} over the land it lands on, let go {:.0} over it, landed {:.0} from the spit hole's middle",
                            O[1] + fl[2] - end[1],
                            O[1] + fl[8] - end[1],
                            (end[0] - O[0] - spit[0]).hyp(end[2] - O[2] - spit[2])
                        );
                    }
                    // (clear of the worm and its holes from the let-go till they land: more than its radius and 10 from its
                    // centreline (the body as it is at that moment, tail to head), more than 12 outside every hole's reach)
                    for f in run.feet.iter().filter(|f| f.0 > t0 && f.0 <= land) {
                        let t = f64::from(f.0);
                        let head = p.head(t).0;
                        let mut sb = head - WE_LEN;
                        let mut near = f64::MAX;
                        while sb <= head {
                            let c = p.point(sb).0;
                            near = near.min((O[0] + c[0] - f.1[0]).hyp(O[2] + c[2] - f.1[2]).hyp(O[1] + c[1] - f.1[1]));
                            sb += 3.0;
                        }
                        assert!(near > WE_R + 10.0, "seed {seed} d {d} k {k}: at {t:.2} after the let-go {near:.1} from the body's centreline at {:?}", f.1);
                        for (c, reach) in &holes {
                            let r = (f.1[0] - c[0]).hyp(f.1[2] - c[2]);
                            assert!(r > reach + 12.0, "seed {seed} d {d} k {k}: at {t:.2} after the let-go {r:.1} from a hole's middle (reach {reach:.1})");
                        }
                    }
                    let res = run.cmds.iter().filter(|c| c.0 <= t0 + 0.11 && c.1.contains("minecraft:resistance") && c.1.contains(" 4 true")).last().expect("Resistance V given");
                    let secs: f32 = res.1.split_whitespace().rev().nth(2).and_then(|v| v.parse().ok()).expect("its seconds");
                    assert!(land + 1.0 <= res.0 + secs, "seed {seed} d {d} k {k}: landed at {land:.2}, Resistance V from {:.2} for {secs}", res.0);
                    // (but where the land along the arc never loads, as only the stand-in's can, the arc can't be lifted over it)
                    let limited = ground == gt_hill_limited as fn(i32, i32) -> Option<i32>;
                    assert!(limited || run.tps.is_empty(), "seed {seed} d {d} k {k}: put on the land {:?} (let go from {:?})", run.tps, run.feet[last].1);
                    if std::env::var("WE_SPIT_LOG").is_ok() {
                        let near = holes.iter().map(|(c, r)| ((run.feet[last + 1].1[0] - c[0]).hyp(run.feet[last + 1].1[2] - c[2]), *r)).min_by(|a, b| a.0.total_cmp(&b.0));
                        eprintln!("seed {seed} d {d} k {k}: let go at {:?} (held at {:?}), nearest hole {near:?}", run.feet[last + 1].1, run.feet[last].1);
                    }
                    for f in &run.feet[last + 1..] {
                        if f.0 > t0 + 4.0 {
                            break;
                        }
                        for (c, reach) in &holes {
                            let r = (f.1[0] - c[0]).hyp(f.1[2] - c[2]);
                            // (the let-go point: never over a hole; after it, never down in one)
                            let first = f.0 <= t0 + 0.1;
                            assert!(!(r < *reach && (first || f.1[1] < c[1] - 2.0)), "seed {seed} d {d} k {k}: at {:.2} s ({:.2} after the let-go) at {:?}, {r:.1} from a hole's middle (reach {reach:.1}, ground {:.0}); tps {:?}", f.0, f.0 - t0, f.1, c[1], run.tps);
                        }
                    }
                }
            }
        }
        SEED.with(|s| s.set(None));
        LAKE.with(|l| l.set((0.0, 0.0, false)));
        assert!(n >= 20, "only {n} caught");
    }

    thread_local! {
        /// The lake's middle for `gt_hill` (where the player stands), and whether only the land near them and the target is loaded.
        static LAKE: std::cell::Cell<(f64, f64, bool)> = const { std::cell::Cell::new((0.0, 0.0, false)) };
    }
    /// The target on a hill 30 over the land round it (falling away from 40 out to 140), a shallow lake 30 round the
    /// player's place (its bed 4 under its top); with `LAKE`'s flag only the land within 250 of them or 140 of the target
    /// loaded (the far terrain's LOD past that).
    fn gt_hill(x: i32, z: i32) -> Option<i32> {
        let (lx, lz, limited) = LAKE.with(|l| l.get());
        let (fx, fz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
        let dt = (fx - O[0]).hyp(fz - O[2]);
        let dl = (fx - lx).hyp(fz - lz);
        if limited && dt > 140.0 && dl > 250.0 {
            return None;
        }
        let g = ground_h(x, z) + 1 - (30.0 * ((dt - 40.0) / 100.0).clamp(0.0, 1.0)).round() as i32;
        Some(if dl < 30.0 { g - 4 } else { g })
    }
    /// A river 24 wide running north-south 40 east of where the player stands (`LAKE`), its bed 4 under the land.
    fn gt_river(x: i32, z: i32) -> Option<i32> {
        let (lx, _, _) = LAKE.with(|l| l.get());
        let g = ground_h(x, z) + 1;
        Some(if (f64::from(x) + 0.5 - lx - 40.0).abs() < 12.0 { g - 4 } else { g })
    }
    fn wet_river(x: i32, z: i32) -> Option<i32> {
        let (lx, _, _) = LAKE.with(|l| l.get());
        ((f64::from(x) + 0.5 - lx - 40.0).abs() < 12.0).then_some(4)
    }
    /// `gt_hill` with only the land within 250 of the player and 140 of the target loaded.
    fn gt_hill_limited(x: i32, z: i32) -> Option<i32> {
        let (lx, lz, _) = LAKE.with(|l| l.get());
        let (fx, fz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
        // (land not loaded the first time it is asked about, loaded after: forceloaded, as the arch planned on it does)
        let far = (fx - O[0]).hyp(fz - O[2]) > 140.0 && (fx - lx).hyp(fz - lz) > 130.0;
        if far && ASKED.with(|a| a.borrow_mut().insert((x, z))) {
            return None;
        }
        // (and that land a plateau 40 over the rest: what is guessed of it before it loads, far off)
        gt_hill(x, z).map(|g| if far { g + 40 } else { g })
    }
    thread_local! {
        static ASKED: std::cell::RefCell<std::collections::HashSet<(i32, i32)>> = Default::default();
    }
    fn wet_hill(x: i32, z: i32) -> Option<i32> {
        let (lx, lz, _) = LAKE.with(|l| l.get());
        ((f64::from(x) + 0.5 - lx).hyp(f64::from(z) + 0.5 - lz) < 30.0).then_some(4)
    }

    /// `cargo test --release we_catch_sweep_lake -- --ignored --nocapture`: as `we_catch_sweep`, the player standing in
    /// a lake 30 under a target on a hill, 150 to 300 off, all the land loaded and then only near them and the target.
    #[test]
    #[ignore]
    fn we_catch_sweep_lake() {
        let mut missed = 0;
        let mut n = 0;
        for limited in [false, true] {
            for d in [150.0, 180.0, 200.0, 250.0, 300.0] {
                for k in 0..8 {
                    let mut me = me_at(d, f64::from(k) * 0.785 + 0.2);
                    LAKE.with(|l| l.set((me[0], me[2], limited)));
                    me[1] = f64::from(gt_hill(me[0].floor() as i32, me[2].floor() as i32).unwrap()) + 4.0;
                    let run = play_wet(0, true, me, &still, gt_hill, Some(wet_hill));
                    let p = &run.path;
                    let big = p.arches.iter().position(|a| a.hold.is_some());
                    let dist = big.map(|b| (O[0] + p.arches[b].to[0] - me[0]).hyp(O[2] + p.arches[b].to[2] - me[2]));
                    let caught = run.word(WL_CAUGHT + 3);
                    n += 1;
                    if caught <= 0.0 {
                        missed += 1;
                    }
                    eprintln!("limited {limited} d {d} angle {k}: big {big:?} at {dist:?}, caught {caught}, arches {}", p.arches.len());
                }
            }
        }
        LAKE.with(|l| l.set((0.0, 0.0, false)));
        eprintln!("missed {missed} of {n}");
    }

    #[test]
    fn we_scripted_show_keeps_its_beats_and_leaves_its_land() {
        let me = me_at(300.0, 0.0);
        let run = play(WE_OPT_SCRIPTED, true, me, &still, gt);
        check(&run, false, true, "scripted");
        assert_eq!(run.path.arches.len(), 1);
        assert!((run.path.arches[0].t_in - we_path::WE_BITE).abs() < 1e-3);
        assert!((run.length - 46.0).abs() < 1e-6);
        // (the first approach's tunnel (W0 to the target) caves in behind the tail as it goes through: 24 to 27)
        let (t0, t1) = (run.word(WL_RUN + 6), run.word(WL_RUN + 7));
        let tu = run.path.tunnels()[0];
        assert!((t0 - tu.tail_in - 0.3).abs() < 0.05 && (t1 - tu.tail_out - 0.3).abs() < 0.05 && t1 < 30.0, "{t0} {t1} {tu:?}");
        // (the land bucking over the head from the approach's first second right up to the breach: blocks thrown in the
        // strip over its line, the ground disturbed)
        let a = &run.path.arches[0];
        let (w0, l) = ([O[0] + a.run_from[0], O[2] + a.run_from[2]], a.run_from[0].hyp(a.run_from[2]));
        let thrown: Vec<(f32, f64, f64)> = run
            .cmds
            .iter()
            .filter(|c| c.1.contains("summon minecraft:falling_block ~0.5"))
            .map(|c| {
                let w: Vec<f64> = c.1.split_whitespace().skip(2).take(3).filter_map(|v| v.parse().ok()).collect();
                let (px, pz) = (w[0] + 0.5 - w0[0], w[2] + 0.5 - w0[1]);
                let (dx, dz) = (-a.run_from[0] / l, -a.run_from[2] / l);
                (c.0, px * dx + pz * dz, (-px * dz + pz * dx).abs())
            })
            .collect();
        assert!(thrown.len() > 60, "{} thrown", thrown.len());
        assert!(thrown.iter().all(|t| t.2 <= land::BUCK_W + 1.5 && t.0 < 9.2), "{:?}", thrown.iter().find(|t| t.2 > land::BUCK_W + 1.5 || t.0 >= 9.2));
        assert!(thrown.iter().any(|t| t.0 < 2.0) && thrown.iter().any(|t| t.1 > l - land::BUCK_END - 8.0), "from the start right into the breach's rim");
        // (at its most violent there: more a metre in its last stretch than over the rest)
        let rim = thrown.iter().filter(|t| t.1 > l - land::BUCK_END - 60.0).count() as f64 / 60.0;
        let rest = thrown.iter().filter(|t| t.1 <= l - land::BUCK_END - 60.0).count() as f64 / (l - land::BUCK_END - 60.0);
        assert!(rim > 1.3 * rest, "{rim:.2} a block by the rim, {rest:.2} before");
        let ground: Vec<f32> = run.edits.iter().filter(|e| e.1 < 9.2 && e.2.runs.iter().any(|r| r.surface.is_some())).map(|e| e.1).collect();
        assert!(ground.len() > 10, "{}", ground.len());
        // (W0 within reach of the player's drawn land)
        let me = me_at(300.0, 0.0);
        assert!((w0[0] - me[0]).hyp(w0[1] - me[2]) <= 300.0, "W0 {:?}", w0);
        assert!(run.word(0) == 1.0 && run.word(1) == 0.0 && run.word(WL_HOLES_N) == 2.0 && run.word(WL_RUNS_N) == 1.0);
        assert_eq!(run.word(WL_CAUGHT), -1.0, "nobody caught 300 off");
        assert!(run.sounds.iter().any(|e| e.1.contains("worldeater.breach")) && run.sounds.iter().any(|e| e.1.contains("worldeater.") && (e.1.contains("sink") || e.1.contains("slump"))), "{:?}", &run.sounds[..5]);
        // (mobs killed along it, never a player or a falling block)
        let kills: Vec<&String> = run.cmds.iter().map(|c| &c.1).filter(|c| c.contains("kill @e")).collect();
        assert!(kills.len() >= 5 && kills.iter().all(|c| c.contains("type=!minecraft:player") || c.contains("type=minecraft:item")));
    }

    #[test]
    fn we_terrain_off_is_light_and_sound_only() {
        for opt in [0, WE_OPT_SCRIPTED] {
            let run = play(opt, false, me_at(300.0, 0.0), &still, gt);
            check(&run, opt == 0, false, "terrain off");
            assert!(!run.sounds.is_empty());
        }
    }

    #[test]
    fn we_hunts_a_player_standing_still_and_swallows_them() {
        let me = me_at(300.0, 0.4);
        let run = play(0, true, me, &still, gt);
        check(&run, true, true, "standing");
        let p = &run.path;
        let big = p.arches.iter().position(|a| a.hold.is_some()).expect("the big arch");
        assert!(big == 2 || big == 3, "{big} hops");
        // (each hop surfaces nearer them; the big one comes down on them)
        let d = |k: [f64; 3]| (O[0] + k[0] - me[0]).hyp(O[2] + k[2] - me[2]);
        eprintln!("standing knots {:?}, me {:?}", p.arches.iter().map(|a| [a.to[0].round(), a.to[2].round(), a.t_in]).collect::<Vec<_>>(), [me[0] - O[0], me[2] - O[2]]);
        assert!(d(p.arches[big].to) < R_BITE, "the bite {} from them", d(p.arches[big].to));
        // (caught on it: carried, spat out by one more small arch, let go on the land beside the hole)
        assert_eq!(run.word(WL_CAUGHT + 3), 1.0, "a bite's catch");
        assert_eq!(p.arches.len(), big + 2, "the spit arch");
        let (t_close, t_spit, t_free) = (run.word(WL_CAUGHT), run.word(WL_CAUGHT + 1), run.word(WL_CAUGHT + 2));
        assert!((t_close - p.arches[big].t_in).abs() < 1e-3);
        assert!((7.0..=10.0).contains(&(t_spit - t_close)), "inside {:.2} s", t_spit - t_close);
        let carried: Vec<&(f32, [f64; 3], bool)> = run.feet.iter().filter(|f| f.2).collect();
        // (carried down the dive and along the run under the land, up the spit arch's breach)
        let dive = [O[0] + p.arches[big].to[0], O[2] + p.arches[big].to[2]];
        let gy = O[1] + p.arches[big].to[1];
        let lowest = carried.iter().map(|f| f.1[1]).fold(f64::MAX, f64::min);
        assert!(lowest < gy - 30.0, "held {lowest} (the dive's ground {gy})");
        let spit = &p.arches[big + 1];
        let axis = [O[0] + spit.from[0], O[2] + spit.from[2]];
        let far = carried.iter().map(|f| (f.1[0] - dive[0]).hyp(f.1[2] - dive[1])).fold(0.0, f64::max);
        assert!(far > 140.0, "carried only {far} from the dive");
        let (tr, at) = run.released.expect("let go");
        assert!((tr - t_free).abs() < 0.2, "{tr} {t_free}");
        let end = run.feet.last().unwrap().1;
        let out = (end[0] - axis[0]).hyp(end[2] - axis[1]);
        let fa = ground_h(end[0].floor() as i32, end[2].floor() as i32) + 1;
        assert!(out > 60.0, "landed {out} from the hole");
        // (on the land, not in a hole or a trench: no knot's hole there)
        assert!((end[1] - f64::from(fa)).abs() <= 7.0, "landed at {:?}, the land at {fa}", end);
        for k in std::iter::once([0.0; 3]).chain(p.arches.iter().map(|a| a.to)) {
            assert!((end[0] - O[0] - k[0]).hyp(end[2] - O[2] - k[2]) > RF_BITE + 2.0, "landed in a hole: {end:?}");
        }
        eprintln!("standing: {} arches, caught at {t_close:.2}, spat {t_spit:.2}, let go at {at:?}, landed at {end:?} ({out:.0} out)", p.arches.len());
        assert!(run.cmds.iter().any(|c| c.1.contains("resistance")));
        // (fx's words: the flag cleared after the spit, the end after the last tail in and within the strike)
        let fx = |i: usize| f64::from(f32::from_bits(run.data[WE_FX_T + i]));
        assert_eq!((fx(0), fx(1)), (0.0, 0.0));
        let tail = run.path.runs().last().unwrap().tail_in;
        assert!(fx(2) >= tail + 14.9 && fx(2) <= f64::from(run.length), "{} {tail}", fx(2));
        // (the warp's domes: over each later knot while the worm loops under it, till it breaks out again)
        // (the warp's mound under the land on each run, the dome before each breach; none while it arches over)
        let mid = 0.5 * (run.path.arches[0].t_in + run.path.arches[1].t_out) as f32;
        let w = we_warp_params(&run.data, mid, 0.0).expect("the mound between the first two surfacings");
        assert!(w[1] > 0.0, "{w:?}");
        assert!(we_warp_params(&run.data, 5.0, 0.0).is_some(), "the first approach");
        let air = 0.5 * (run.path.arches[0].t_out + run.path.arches[0].t_in) as f32;
        assert!(we_warp_params(&run.data, air, 0.0).is_none(), "over the land at {air}");
    }

    #[test]
    fn we_hunts_a_player_walking_away_flying_fast_and_flying_up() {
        let away = |t: f64, f: [f64; 3]| if t > 2.0 { [f[0] + 0.0, f[1], f[2] + 4.3 * 0.05] } else { f };
        let fast = |t: f64, f: [f64; 3]| if t > 2.0 && t < 30.0 { [f[0] + 200.0 * 0.05, 100.0, f[2]] } else { f };
        let up = |t: f64, f: [f64; 3]| if t > 2.0 { [f[0], (f[1] + 20.0 * 0.05).min(420.0), f[2]] } else { f };
        let cases: [(&str, &dyn Fn(f64, [f64; 3]) -> [f64; 3], fn(i32, i32) -> Option<i32>); 4] = [("walking away", &away, gt), ("flying fast", &fast, gt), ("flying up", &up, gt), ("flying fast, far land unloaded", &fast, gt_near)];
        for (label, walk, ground) in cases {
            let run = play(0, true, me_at(300.0, 0.4), walk, ground);
            check(&run, true, true, label);
            let p = &run.path;
            eprintln!("{label}: {} arches, knots {:?}, caught {}", p.arches.len(), p.arches.iter().map(|a| [a.to[0].round(), a.to[2].round()]).collect::<Vec<_>>(), run.word(WL_CAUGHT));
            if label.starts_with("flying up") {
                assert_eq!(run.word(WL_CAUGHT), -1.0, "{label}: caught out of reach");
            }
            if ground == gt_near as fn(i32, i32) -> Option<i32> {
                for a in &p.arches {
                    assert!((a.to[0]).hyp(a.to[2]) < 650.0, "{label}: onto land not loaded: {:?}", a.to);
                }
            }
        }
        // (and from a long way off: still a clean end)
        let run = play(0, true, me_at(1000.0, 2.0), &still, gt);
        check(&run, true, true, "1000 off");
    }

    #[test]
    fn we_catches_on_the_breach_and_spits_them_clear() {
        // (standing over the target: the head comes up under them)
        let me = [O[0] + 6.0, O[1] + 1.0, O[2] - 4.0];
        let run = play(0, true, me, &still, gt);
        check(&run, true, true, "on the target");
        assert_eq!(run.word(WL_CAUGHT + 3), 2.0, "a breach's catch");
        assert!((run.word(WL_CAUGHT) - WE_BREACH).abs() < 1e-3);
        let end = run.feet.last().unwrap().1;
        assert!((end[0] - O[0]).hyp(end[2] - O[2]) > 60.0, "{end:?}");
        assert!((end[1] - f64::from(ground_h(end[0].floor() as i32, end[2].floor() as i32) + 1)).abs() <= 7.0, "{end:?}");
    }

    #[test]
    fn we_scripted_bite_catch_adds_one_small_arch() {
        // (fired from 300 off, then walked under where the show's bite comes down: D, 260 along the line. The show's 46
        // seconds hold no spit arch carried out of the mouth (round 11): its bite catches nobody, the show unchanged)
        let me0 = me_at(300.0, 0.0);
        let g = we_path::we_geo(O, me0, 37);
        let d = [O[0] + g.d[0] + 4.0, O[1] + 1.0, O[2] + g.d[2] + 2.0];
        let walk = move |t: f64, f: [f64; 3]| if t > 12.0 { d } else { f };
        let run = play(WE_OPT_SCRIPTED, true, me0, &walk, gt);
        check(&run, false, true, "scripted, bitten");
        assert_eq!(run.path.arches.len(), 1, "the show alone");
        assert_eq!(run.word(WL_CAUGHT), -1.0, "nobody caught on the show's bite");
        assert!(!run.feet.iter().any(|f| f.2));
    }

    #[test]
    fn we_terrain_off_catches_nobody() {
        for opt in [0, WE_OPT_SCRIPTED] {
            let me = if opt == 0 { me_at(300.0, 0.4) } else { [O[0], O[1], O[2]] };
            let run = play(opt, false, me, &still, gt);
            assert_eq!(run.word(WL_CAUGHT), -1.0, "option {opt}: caught with terrain off");
            assert!(!run.feet.iter().any(|f| f.2));
        }
    }

    #[test]
    fn we_no_catch_and_no_knockback_with_it_off() {
        let run = play(WE_OPT_NO_KNOCK, true, me_at(300.0, 0.4), &still, gt);
        assert_eq!(run.word(WL_CAUGHT), -1.0);
        assert_eq!(run.pushes, 0);
        assert!(!run.feet.iter().any(|f| f.2));
    }

    #[test]
    fn worldeater_plans_and_gives_its_table() {
        let laser = laser();
        for terrain in [false, true] {
            let ev = super::super::plan(laser, &AT, terrain, "minecraft:overworld", 37.0, [10.5, 70.0, 297.5], WE_OPT_SCRIPTED);
            // (the per-tick hook as it fires; the rest from a stage on the next tick)
            assert!(ev.iter().any(|e| matches!(e.1, Act::Hand(_))) && ev.iter().any(|e| matches!(e.1, Act::Later(_))));
            assert!(ev.iter().all(|e| e.0 >= 0.0 && e.0 <= laser.length));

        }
        let g = we_path::we_geo([10.5, 65.0, -2.5], [10.5, 70.0, 297.5], 37);
        let boxes = we_load_boxes([10.5, 65.0, -2.5], &we_path::we_default_plan(&g), 64.0);
        let chunks: i32 = boxes.iter().map(|b| (b[2] - b[0] + 1) / 16).sum();
        assert!(chunks > 100 && chunks < 600, "{chunks}");
    }

    /// `WE_SLOW=1 cargo test --release --lib we_soak_geometry -- --ignored --nocapture`: the fork's soak's strike (the
    /// player 520 off, the land loaded round them only), each slow stage printed.
    #[test]
    #[ignore]
    fn we_soak_geometry() {
        fn near_me(x: i32, z: i32) -> Option<i32> {
            (f64::from(x) - O[0] + 73.0).hyp(f64::from(z) - O[2] - 520.0).lt(&200.0).then(|| ground_h(x, z) + 1)
        }
        for seed_me in [[O[0] - 73.0, 70.0, O[2] + 520.0], [O[0] + 300.0, 70.0, O[2] - 400.0]] {
            let run = play(0, true, seed_me, &still, near_me);
            eprintln!("{} arches", run.path.arches.len());
        }
    }

    /// `cargo test --release --lib we_land_profile -- --ignored --nocapture`: a hunt (standing player, swallowed) and
    /// the scripted show played out, their busiest ticks: edits (pace units, runs, blocks), world commands, and the
    /// heaviest stages.
    #[test]
    #[ignore]
    fn we_land_profile() {
        for (label, opt) in [("hunt", 0), ("scripted", WE_OPT_SCRIPTED)] {
            let run = play(opt, true, me_at(300.0, 0.4), &still, gt);
            let mut ticks: std::collections::BTreeMap<i32, (u32, usize, u64, usize)> = Default::default();
            for (_, due, b) in &run.edits {
                let e = ticks.entry((due * 20.0).ceil() as i32).or_default();
                e.0 += crate::pace::cost(&b.runs);
                e.1 += b.runs.len();
                e.2 += b.runs.iter().map(|r| u64::from(r.height)).sum::<u64>();
            }
            for (t, c) in &run.cmds {
                if crate::strike::block_cost(c).is_some() {
                    ticks.entry((t * 20.0).round() as i32).or_default().3 += 1;
                }
            }
            let mut v: Vec<(i32, (u32, usize, u64, usize))> = ticks.into_iter().collect();
            let total: u64 = v.iter().map(|x| x.1.2).sum();
            v.sort_by_key(|x| std::cmp::Reverse(x.1.0));
            eprintln!("{label}: {} arches, {} edits, {:.1}M blocks; busiest ticks (pace units, runs, blocks, world commands):", run.path.arches.len(), run.edits.len(), total as f64 / 1e6);
            for (t, (u, r, b, c)) in v.iter().take(12) {
                eprintln!("  {:6.2} s  {u:4}  {r:6}  {b:8}  {c:4}", *t as f32 * 0.05);
            }
            let most_cmds = v.iter().map(|x| x.1.3).max().unwrap_or(0);
            let mut summons: std::collections::BTreeMap<i32, usize> = Default::default();
            let mut all: std::collections::BTreeMap<i32, usize> = Default::default();
            for (t, c) in &run.cmds {
                *all.entry((t * 20.0).round() as i32).or_default() += 1;
                if c.contains("summon minecraft:falling_block") {
                    *summons.entry((t * 20.0).round() as i32).or_default() += 1;
                }
            }
            let (st_, sn) = summons.iter().max_by_key(|x| *x.1).map_or((0, 0), |x| (*x.0, *x.1));
            let total_s: usize = summons.values().sum();
            eprintln!("  falling blocks: {total_s} in all, at most {sn} a tick (at {:.2} s); commands of any kind at most {} a tick", st_ as f32 * 0.05, all.values().max().unwrap_or(&0));
            let mut st = run.stages.clone();
            st.sort_by_key(|s| std::cmp::Reverse(s.2));
            eprintln!("  most world commands a tick: {most_cmds}; heaviest stages (meter): {:?}", st.iter().take(6).map(|s| format!("{:.2}M at {:.2}", s.2 as f64 / 1e6, s.1)).collect::<Vec<_>>());
            eprintln!("  stages: {}, latest {:.2} s late", run.stages.len(), run.stages.iter().map(|s| s.1 - s.0).fold(0.0, f32::max));
            let mut by: std::collections::BTreeMap<String, (u64, u64)> = Default::default();
            for (_, _, b) in &run.edits {
                let e = b.edit();
                for r in &e.runs {
                    let k = by.entry(e.palette[r.block as usize].clone()).or_default();
                    k.0 += u64::from(r.height);
                    k.1 += 1;
                }
            }
            let mut byv: Vec<_> = by.into_iter().collect();
            byv.sort_by_key(|x| std::cmp::Reverse(x.1.0));
            eprintln!("  blocks by kind (blocks, runs): {:?}", &byv[..byv.len().min(10)]);
            // the edits through the game's pacing at a fixed budget a tick (lib.rs's `edit`: the urgent first, up to 64
            // units whatever the budget, dressing over 1.5 s behind left out): how late the last goes in
            let mut due: Vec<(f32, u32, bool, bool)> = run.edits.iter().map(|(_, d, b)| (*d, crate::pace::cost(&b.runs), b.urgent, b.shed)).collect();
            due.sort_by(|a, b| a.0.total_cmp(&b.0));
            let units: u64 = due.iter().map(|d| u64::from(d.1)).sum();
            let urgent: u64 = due.iter().filter(|d| d.2).map(|d| u64::from(d.1)).sum();
            let dressing: u64 = due.iter().filter(|d| d.3).map(|d| u64::from(d.1)).sum();
            eprintln!("  pace units {units}: urgent {urgent}, dressing {dressing}");
            for budget in [8u32, 16, 32, 64, 96] {
                let mut q: std::collections::VecDeque<(f32, u32, bool, bool)> = Default::default();
                let (mut i, mut tick, mut late_u, mut late, mut shed) = (0usize, 0i32, 0.0f32, 0.0f32, 0);
                while i < due.len() || !q.is_empty() {
                    let now = tick as f32 * 0.05;
                    while i < due.len() && due[i].0 <= now {
                        if due[i].2 {
                            let at = q.iter().take_while(|e| e.2).count();
                            q.insert(at, due[i]);
                        } else {
                            q.push_back(due[i]);
                        }
                        i += 1;
                    }
                    let mut u = 0;
                    while let Some(e) = q.front().copied() {
                        if e.3 && !e.2 && now - e.0 > 1.5 {
                            q.pop_front();
                            shed += 1;
                            continue;
                        }
                        if !e.2 || (u > 0 && u + e.1 > 64) {
                            break;
                        }
                        q.pop_front();
                        u += e.1;
                        late_u = late_u.max(now - e.0);
                    }
                    let b = budget.saturating_sub(u).max(4);
                    let mut spent = 0;
                    let mut n = 0;
                    while let Some(e) = q.front().copied() {
                        if e.2 || (e.3 && now - e.0 > 1.5) || (n > 0 && spent + e.1 > b) {
                            break;
                        }
                        q.pop_front();
                        spent += e.1;
                        n += 1;
                        late = late.max(now - e.0);
                    }
                    tick += 1;
                }
                eprintln!("  at {budget}/tick: the urgent at most {late_u:.2} s late, the rest {late:.2} s, {shed} edits of dressing left out");
            }
        }
    }

    /// `CB_SEED=37 CB_OUT=path PL_ME=x,y,z WE_PLAN=1|3 WE_DEBUG=1 cargo test --release we_write_table -- --ignored`:
    /// the table the pass reads, for tools/preview.py (a line `index value` a word), the target's ground at the
    /// preview's (0.5 65 0.5); with WE_DEBUG Rust's own samples for the pass to check its centreline against (WE_DBG_T).
    #[test]
    #[ignore]
    fn we_write_table() {
        let seed: u32 = std::env::var("CB_SEED").map_or(37, |v| v.parse::<f32>().unwrap() as u32);
        let me: Vec<f64> = std::env::var("PL_ME").map_or(vec![0.0, 65.0, 300.0], |v| v.split(',').map(|x| x.parse().unwrap()).collect());
        let which: u32 = std::env::var("WE_PLAN").map_or(1, |v| v.parse().unwrap());
        let g = we_path::we_geo([0.5, 65.0, 0.5], [me[0], me[1], me[2]], seed);
        let path = we_path::we_plan(&g, which);
        let mut w = path.words();
        let body = super::super::we_body::we_body_words(&path, seed);
        if !body.is_empty() {
            w.resize(WE_BODY_T + body.len(), 0);
            w[WE_BODY_T..].copy_from_slice(&body);
        }
        let fx = super::super::we_fx::we_fx_words(0, 0);
        let o = WE_FX_T + super::super::we_fx::WEF_BK;
        if w.len() < o + fx.len() {
            w.resize(o + fx.len(), 0);
        }
        w[o..o + fx.len()].copy_from_slice(&fx);
        if std::env::var("WE_DEBUG").is_ok_and(|v| v == "1") {
            let d = we_path::we_debug_words(&path);
            w.resize(we_path::WE_DBG_T + d.len(), 0);
            w[we_path::WE_DBG_T..].copy_from_slice(&d);
        }
        let out: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), out).unwrap();
    }
}
