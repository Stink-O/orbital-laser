//! The Fold's plan: reality folded like paper, the mandala its crease pattern, the crater the scar. There is no beam. A
//! liquid-metal droplet comes down, stops dead over the target and melds into the land; everything after that is the
//! world's own geometry, far terrain included, through the fork's world warp (`render.set-warp`, shaders/fold_warp.wgsl,
//! its vertices and its fragments), timed by the strike clock; shaders/fold.wgsl draws what is not the world (the droplet,
//! the void and its stars, the light at the touch, the dust of the slams); the plan makes the sounds and the land.
//!
//! The timeline (strike seconds; FD_* here, FW_* in fold_warp.wgsl and fold.wgsl's in step, `the_warp_keeps_the_beats`):
//!   0 - FD_STOP       the droplet's fall out of the top of the sky: a glint, a plasma sheath, fire, a smoke trail
//!   FD_STOP           it stops dead in one frame, the fire rushes past it, the sound cuts to near silence
//!   FD_HANG           it has hung perfectly still; it is let go and falls to the land under gravity
//!   FD_TOUCH-FD_MELD  it falls straight into the land without slowing, the land closing over it; no splash
//!   FD_RIPPLE         the warp begins (off before it): rings running out, each bigger than the last
//!   FD_SCORE          the rings sharpen into hairline creases racing over the land, the mandala's pattern
//!   FD_TEAR           the creases split open on the void
//!   FD_FOLD-FD_SEAL   the land lifts ring by ring; the far land closes round the player, the rings lying back to a mound
//!   FD_SEAL           the player is inside a sphere, real land on its walls, a hole left in its roof
//!   FD_FOLDS          a branch of land grows out of the wall by the hole's rim, its foot swelling from 34.5, and comes round and down
//!                     to the target, slower and slower, thinner at each stage; FD_BEAT its tip touches it: a tiny light and a ding;
//!                     stillness to FD_RELEASE
//!   FD_RELEASE        all of it runs backwards, gathering slowly: the sphere opens, the bud stands again with every ring up
//!   FD_SLAM           ring by ring, outermost first, each falls and bangs down, a pause and a shock to each
//!   FD_SLAM[4]        the last ring lands, breaking the land along its creases: the crater goes in held up at the land's level (FD_REVEAL), and
//!                     falls in over about 3 s, kite by kite, from the middle out (fold_warp.wgsl's fw_sunk)
//!   FD_SLAM[4]-FD_LEN the comedown: the creases fade, the void seals
//!
use super::{Act, Plan, Rng, Target, fold_land};
use crate::lasers::Laser;

pub(super) const FD_LEN: f32 = 59.7;
/// The world warp (shaders/fold_warp.wgsl): how many times it draws the land near the target again, how far from it, and
/// when it is on, the world's own culling back the rest of the time.
pub const FD_COPIES: u32 = 5;
pub const FD_COPY_R: f32 = 130.0;
/// When the copies are drawn: the root swelling on the wall from 34.5 (fold_warp.wgsl's fw_swell), the arm out and back.
pub const FD_COPY_ON: std::ops::Range<f32> = 34.45..42.1;
pub const FD_WARP_START: f32 = 5.5;
pub const FD_WARP_END: f32 = 56.7;
/// The strike's beats (see the top of this file).
pub(super) const FD_STOP: f32 = 3.4;
pub(super) const FD_HANG: f32 = 4.5;
pub(super) const FD_TOUCH: f32 = 6.0;
pub(super) const FD_MELD: f32 = 6.2;
pub(super) const FD_RIPPLE: f32 = 6.6;
pub(super) const FD_SCORE: f32 = 12.0;
pub(super) const FD_TEAR: f32 = 16.0;
pub(super) const FD_FOLD: f32 = 19.0;
pub(super) const FD_SEAL: f32 = 35.0;
pub(super) const FD_CRUSH: f32 = 35.0;
pub(super) const FD_BEAT: f32 = 40.0;
pub(super) const FD_RELEASE: f32 = 40.5;
/// When each of the branch's six stages starts (the last ends at 39.0, the tip a few blocks short of the target: there it
/// creeps and waits, and closes the last of it in the 0.3 s up to FD_BEAT): shorter and shorter, slower and slower.
pub(super) const FD_FOLDS: [f32; 6] = [35.0, 35.5, 36.1, 36.8, 37.5, 38.2];
/// When each ring bangs down, outermost first (ring 4 at FD_SLAM[0], with the far land, ring 0 last): the last shows the
/// crater. Each falls for 0.8 s and stops dead, so there is a stillness before each but the first.
pub(super) const FD_SLAM: [f32; 5] = [44.1, 45.2, 46.3, 47.4, 48.7];
/// How long each ring falls (fold_warp.wgsl's FW_FALL): a ring's sound starts this far before its bang, its fall in the same file.
pub(super) const FD_FALL: f32 = 0.8;
/// When the crater takes its place: the one frame the game's hold on the terrain lets go (`render.hold-world`).
pub const FD_REVEAL: f32 = FD_SLAM[4];
/// The terrain on screen held as it stands, the land's edits going in behind it, not paced by the frame time. The hold lets go a
/// frame ahead of the reveal: the swap shows the frame after it is asked for, and the warp lifting the old land for that frame is a dome.
pub const FD_HIDDEN: std::ops::Range<f32> = FD_SEAL - 4.5..FD_REVEAL - 0.03;
/// The world closed round the player, from the walls coming in to their opening again: the sphere goes with them (fold_warp's
/// fw_stay), so they can't leave it or see its outside, and lib.rs keeps their flight to vanilla's and them from going too far.
pub const FD_STAY: std::ops::Range<f32> = 27.0..43.5;
/// The sphere has fully hold of them from here: moving them now doesn't show.
pub const FD_TETHER_ON: f32 = 30.0;
/// How far they are let go from where they fired (real blocks): anything past FD_TETHER is brought back (the land round the
/// target has to stay loaded). The sphere goes with them whole (fold_warp's fw_stay), so it doesn't show.
pub const FD_TETHER: f64 = 320.0;
/// The crease pattern's rings: their outer radii, blocks from the target (fold_warp.wgsl's FW_RING in step). Each is a
/// hinge of the fold; the crater is the pattern inside the fourth (strike/fold_land.rs), its fissures run out along the big creases.
pub(super) const FD_RINGS: [f64; 5] = [44.0, 104.0, 176.0, 290.0, 480.0];

/// The crease pattern as the mod needs it (fold_warp.wgsl's cp_dir and CP_INV, `the_warp_keeps_the_beats`): big creases' bearings, degrees, and
/// one over how far out each ring meets each.
const FD_CREASES: [f32; 8] = [0.0, 38.0, 109.0, 125.0, 180.0, 263.0, 289.0, 332.0];
const FD_INV: [[f32; 5]; 8] = [
    [0.019573, 0.011678, 0.004623, 0.004120, 0.001782],
    [0.027736, 0.008565, 0.006843, 0.002906, 0.002638],
    [0.020483, 0.011177, 0.005123, 0.004379, 0.001742],
    [0.025310, 0.007770, 0.007426, 0.002897, 0.002555],
    [0.020316, 0.010662, 0.004848, 0.003851, 0.001855],
    [0.026149, 0.008739, 0.006787, 0.002974, 0.002662],
    [0.019413, 0.011845, 0.004865, 0.004264, 0.001793],
    [0.026306, 0.007756, 0.007470, 0.002833, 0.002597],
];
/// Bearing `a` (radians) in the pattern turned by `turn` degrees: its wedge's big creases k and k + 1, and the unit vector at `a` as u e_k + v e_k1.
#[derive(Clone, Copy)]
pub(super) struct FdWedge {
    pub k: usize,
    pub k1: usize,
    pub u: f64,
    pub v: f64,
}
pub(super) fn fd_wedge(a: f64, turn: f64) -> FdWedge {
    let x = (a.to_degrees() - turn).rem_euclid(360.0);
    let k = FD_CREASES.iter().rposition(|c| x >= f64::from(*c)).unwrap_or(7);
    let k1 = (k + 1) % 8;
    let cr = |p: f64, q: f64| (q - p).to_radians().sin();
    let (a0, a1) = (f64::from(FD_CREASES[k]), f64::from(FD_CREASES[k1]));
    FdWedge { k, k1, u: cr(x, a1) / cr(a0, a1), v: cr(a0, x) / cr(a0, a1) }
}
impl FdWedge {
    /// One over how far out ring i's chord is at this bearing (fold_warp.wgsl's cp_ix).
    pub fn ix(&self, i: usize) -> f64 {
        self.u * f64::from(FD_INV[self.k][i]) + self.v * f64::from(FD_INV[self.k1][i])
    }
    /// Crease k's bearing, radians, in the world.
    pub fn bearing(k: usize, turn: f64) -> f64 {
        (f64::from(FD_CREASES[k]) + turn).to_radians()
    }
    /// How far out the last ring meets crease k.
    pub fn reach(k: usize) -> f64 {
        1.0 / f64::from(FD_INV[k][4])
    }
}
/// How the pattern is turned, degrees, for the strike's shader seed (fold_warp.wgsl's cp_wedge).
pub(super) fn fd_turn(seed: f32) -> f64 {
    f64::from((seed * 0.618_034).fract() * 360.0)
}

/// Which kite of the pattern the player stood in as it fired, for the warp to leave alone (fold_warp.wgsl's cp_pin): 6 k + its cell, 5 past the rings.
pub fn fd_pin(target: [f64; 3], me: [f64; 3], seed: f32) -> u32 {
    let (dx, dz) = ((me[0] - target[0]) as f32, (me[2] - target[2]) as f32);
    let r = dx.hypot(dz);
    let turn = (seed * 0.618_034).fract() * 360.0;
    let x = (dz.atan2(dx).to_degrees() - turn).rem_euclid(360.0);
    let k = FD_CREASES.iter().rposition(|c| x >= *c).unwrap_or(7);
    let k1 = (k + 1) % 8;
    let cr = |a: f32, b: f32| (b - a).to_radians().sin();
    let (a0, a1) = (FD_CREASES[k], FD_CREASES[k1]);
    let (u, v) = (cr(x, a1) / cr(a0, a1), cr(a0, x) / cr(a0, a1));
    let cell = (0..5).find(|i| r * (u * FD_INV[k][*i] + v * FD_INV[k1][*i]) < 1.0).unwrap_or(5);
    (6 * k + cell) as u32
}
/// params[10]: the land's level (`fd_level`, a whole number, 0 or under) and under it the player's kite (`fd_pin`), as the warp reads them.
pub fn fd_lie(level: f32, pin: u32) -> f32 {
    level - (pin + 1) as f32 / 64.0
}

/// The columns asked of the world at the strike's start, for how low the land lies round the target (`fd_level`).
pub fn fd_survey(block: [i32; 3]) -> Vec<(i32, i32)> {
    let mut out = Vec::with_capacity(FD_SURVEY_RINGS.len() * FD_SURVEY_ROUND);
    for r in FD_SURVEY_RINGS {
        for k in 0..FD_SURVEY_ROUND {
            let a = (k as f64 + 0.5 * f64::from(r > 200.0)) * std::f64::consts::TAU / FD_SURVEY_ROUND as f64;
            out.push((block[0] + (r * a.cos()) as i32, block[2] + (r * a.sin()) as i32));
        }
    }
    out
}
const FD_SURVEY_RINGS: [f64; 4] = [90.0, 170.0, 280.0, 420.0];
const FD_SURVEY_ROUND: usize = 16;
/// The level the land's relief is pressed towards as it creases (fold_warp.wgsl's cp_level, params[10]), blocks from the target, 0 or under:
/// a little under what most of the land round it stands on, water's top where there is water, so that hardly any is under it and it isn't
/// pulled further than it has to be: a plateau is pressed to itself, not to the sea. `heights` the columns' tops, none not loaded.
pub fn fd_level(target_y: i32, heights: &[Option<i32>]) -> f32 {
    let mut h: Vec<i32> = heights.iter().flatten().copied().collect();
    if h.is_empty() {
        return 0.0;
    }
    h.sort_unstable();
    let low = h[h.len() / 6];
    ((low - target_y - 1) as f32).clamp(-80.0, 0.0)
}

pub(super) fn fold_plan(laser: &'static Laser, target: &Target, terrain: bool, dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let s = shader_seed as u32;
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let dist = (me[0] - cx).hypot(me[2] - cz);

    // ---- sound (tools/sounds_fold.py) ------------------------------------------------------------------------------
    // (the fall, a roar cut dead on the stop; a heavy settle in the silence; the air arriving late by the distance)
    p.csound(0.0, "descent", 10.0, 1.0);
    p.csound(FD_STOP + 0.09, "wobble", 10.0, 1.0);
    p.csound(FD_STOP + (dist as f32 / 343.0).clamp(0.2, 1.0), "air", 10.0, 1.0);
    // (let go, the air over it as it falls; it lands at full speed, the land shutting over it; then the land like water, then ice:
    // the creases as stones skipped over a frozen lake)
    p.csound(FD_HANG, "letgo", 10.0, 1.0);
    p.csound(FD_TOUCH - 0.4, "meld", 10.0, 1.0);
    p.csound(FD_TOUCH + 1.5, "ripple", 10.0, 1.0);
    p.csound(FD_SCORE, "score", 10.0, 1.0);
    p.csound(FD_FOLD, "unravel", 10.0, 1.0);
    p.csound(FD_FOLD, "groan", 10.0, 1.0);
    // (the rim gathering at the hole and the land pouring down it to nothing; the ding alone; everything going back, till the first ring lands)
    p.csound(FD_SEAL - 0.5, "foldown", 10.0, 1.0);
    p.csound(FD_BEAT, "ding", 10.0, 1.0);
    p.csound(FD_RELEASE, "reverse", 10.0, 1.0);
    p.shake(FD_RELEASE + 1.5, 0.3 * super::falloff(dist), 1.6);
    // (each ring its own fall and its own bang, in one file, and a jolt with each; the last's fall and the slam apart)
    for (k, t) in FD_SLAM.iter().enumerate() {
        let f = k as f32 / 4.0;
        if k < 4 {
            p.csound(*t - FD_FALL, &format!("bang{}", k + 1), 10.0, 1.0);
        } else {
            p.csound(*t - FD_FALL, "fall", 10.0, 1.0);
            p.csound(*t, "slam", 10.0, 1.0);
            p.csound(*t, "sink", 10.0, 1.0);
        }
        p.shake(*t, (0.5 + 0.4 * f) * super::falloff(dist * 0.5), 0.6 + 0.9 * f);
    }
    // (the panel under the player lets go on the slam and lands by how deep the crater is there: fw_sunk's fall, a crater 300 in radius)
    if dist < 295.0 {
        let u = dist as f32 / 300.0;
        p.csound(FD_SLAM[4] + (66.0 * (1.0 - u * u * u).powf(0.75) / 18.0).sqrt(), "underfoot", 10.0, 1.0);
    }
    p.csound(FD_SLAM[4] + 4.6, "comedown", 10.0, 1.0);

    if !terrain {
        p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
        return p.ev;
    }
    // ---- the land: all of it strike/fold_land.rs ---------------------------------------------------------------------
    fold_land::land_plan(&mut p, s, fd_turn(shader_seed), dimension, me);
    // (playback goes through the plan in order, and stops at the first not due: one out of order holds up all after it)
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::{Target, plan};

    /// The warp's beats are the plan's and the pass's, and its copies' radius what lib.rs asks the game for.
    #[test]
    fn the_warp_keeps_the_beats() {
        let warp = include_str!("../../shaders/fold_warp.wgsl");
        let pass = include_str!("../../shaders/fold.wgsl");
        for (name, v) in [("RIPPLE", FD_RIPPLE), ("SCORE", FD_SCORE), ("TEAR", FD_TEAR), ("FOLD", FD_FOLD), ("SEAL", FD_SEAL), ("CRUSH", FD_CRUSH), ("BEAT", FD_BEAT), ("REL", FD_RELEASE), ("FLAT", FD_SLAM[0]), ("SLAM4", FD_SLAM[4]), ("FALL", FD_FALL), ("END", FD_WARP_END)] {
            assert!(warp.contains(&format!("const FW_{name}: f32 = {v:.1};")), "FW_{name}");
        }
        for (name, v) in [("STOP", FD_STOP), ("HANG", FD_HANG), ("TOUCH", FD_TOUCH), ("MELD", FD_MELD), ("FOLD", FD_FOLD), ("SEAL", FD_SEAL), ("CRUSH", FD_CRUSH), ("BEAT", FD_BEAT), ("REL", FD_RELEASE), ("SLAM0", FD_SLAM[0]), ("SLAM4", FD_SLAM[4])] {
            assert!(pass.contains(&format!("const FD_{name}: f32 = {v:.1};")), "FD_{name}");
        }
        assert!(warp.contains(&format!("const FW_BOWL: f32 = {:.1};", super::fold_land::FD_BOWL)), "FW_BOWL");
        for (i, r) in FD_RINGS.iter().enumerate() {
            assert!(warp.contains(&format!("case {i}: {{ return {r:.1}; }}")) || (i == 4 && warp.contains(&format!("const FW_LEN: f32 = {r:.1};"))), "ring {i}");
            assert!(pass.contains(&format!("{r:.1}")), "ring {i} in the pass");
        }
        for (k, t) in FD_SLAM.iter().enumerate() {
            assert!(pass.contains(&format!("{t:.1}")), "slam {k} in the pass");
        }
        for (k, t) in FD_FOLDS.iter().enumerate() {
            assert!(warp.contains(&format!("case {k}: {{ return {t:.1}; }}")), "fold {k}");
        }
        assert!(warp.contains(&format!("const FW_DISC: f32 = {FD_COPY_R:.1};")));
        // (the land's height as it meets the drop: the warp moves the land, the pass draws the metal and the glow on it)
        assert!(warp.contains("const FW_MEET: f32 = -0.08;") && pass.contains("const FD_MEET: f32 = -0.08;"));
        // (its fall)
        assert!(warp.contains(&format!("const FW_DROP: f32 = {:.1};", FD_TOUCH - FD_HANG)) && pass.contains(&format!("const FD_DROP: f32 = {:.1};", FD_TOUCH - FD_HANG)));
        // (the land the drop falls on, the drop's fall; where the branch's tip ends, which is where the pass's light is)
        for name in ["sink", "wide", "land", "side", "high", "over", "seat", "turned"] {
            let body = |src: &str, p: &str| {
                let from = src.find(&format!("fn {p}_{name}(")).unwrap_or_else(|| panic!("{p}_{name}"));
                let to = from + src[from..].find("\n}\n").expect("its end");
                src[from..to].replace("FW_", "F_").replace("FD_", "F_").replace("fw_", "f_").replace("fd_", "f_").replace("globals.warp[2].x", "seed_v()")
            };
            assert_eq!(body(warp, "fw"), body(pass, "fd"), "{name}");
        }
    }

    /// The mod and the warp agree on the pattern, and on where the kite goes.
    #[test]
    fn the_pin_is_the_warps() {
        let warp = include_str!("../../shaders/fold_warp.wgsl");
        for row in FD_INV {
            for x in row {
                assert!(warp.contains(&format!("{x:.6}")), "{x} in CP_INV");
            }
        }
        let from = warp.find("fn cp_dir(").expect("cp_dir");
        let dirs: Vec<f32> = warp[from..from + warp[from..].find("\n}\n").expect("its end")]
            .lines()
            .filter(|l| l.contains("return"))
            .map(|l| {
                let v: Vec<f32> = l.split("vec2<f32>(").nth(1).unwrap().split(')').next().unwrap().split(", ").map(|x| x.parse().unwrap()).collect();
                v[1].atan2(v[0]).to_degrees().rem_euclid(360.0)
            })
            .collect();
        for (k, c) in FD_CREASES.iter().enumerate() {
            assert!((dirs[k] - c).abs() < 0.01, "crease {k} at {c}, the warp's {}", dirs[k]);
        }
        // (on a crease's own bearing, with no turn: the seed's turn is its fractional part of a turn)
        assert_eq!(fd_pin([0.0; 3], [100.0, 0.0, 1.0], 0.0), 2);
        assert_eq!(fd_pin([0.0; 3], [-30.0, 0.0, -1.0], 0.0), 6 * 4);
        assert_eq!(fd_pin([0.0; 3], [2000.0, 0.0, 1.0], 0.0), 5);
        assert_eq!(fd_lie(-45.0, 7), -45.0 - 8.0 / 64.0);
    }

    /// A plateau is pressed to itself, not to the sea; a few low columns don't drag it down; land not loaded says nothing.
    #[test]
    fn the_pressing_level_is_the_lands_own() {
        let flat: Vec<Option<i32>> = vec![Some(200); 64];
        assert_eq!(fd_level(200, &flat), -1.0);
        let mut pits = flat.clone();
        for p in pits.iter_mut().take(6) {
            *p = Some(70);
        }
        assert_eq!(fd_level(200, &pits), -1.0);
        let mut low: Vec<Option<i32>> = vec![Some(70); 32];
        low.extend(vec![Some(109); 32]);
        assert_eq!(fd_level(109, &low), -40.0);
        assert_eq!(fd_level(109, &[None, None]), 0.0);
        assert_eq!(fd_survey([0, 64, 0]).len(), 64);
    }

    /// The crease pattern (fold_warp.wgsl's cp_*): its big creases fold flat (Kawasaki's theorem: every other angle round
    /// the target adds up to 180 degrees), so its zigzag of one slope closes on itself, and each is a mountain or a valley in turn.
    #[test]
    fn the_creases_fold_flat() {
        let warp = include_str!("../../shaders/fold_warp.wgsl");
        let table = |name: &str, one: fn(&str) -> f64| -> Vec<f64> {
            let from = warp.find(&format!("fn {name}(")).expect(name);
            let to = from + warp[from..].find("\n}\n").expect("its end");
            warp[from..to].lines().filter(|l| l.contains("return")).map(|l| one(l)).collect()
        };
        let dirs = table("cp_dir", |l| {
            let v: Vec<f64> = l.split("vec2<f32>(").nth(1).unwrap().split(')').next().unwrap().split(", ").map(|x| x.parse().unwrap()).collect();
            v[1].atan2(v[0]).to_degrees().rem_euclid(360.0)
        });
        let rise = table("cp_rise", |l| l.split("return ").nth(1).unwrap().trim_end_matches(|c| c == ';' || c == ' ' || c == '}').parse().unwrap());
        assert_eq!((dirs.len(), rise.len()), (8, 8));
        let gap = |k: usize| (dirs[(k + 1) % 8] - dirs[k]).rem_euclid(360.0);
        let odd: f64 = (0..8).step_by(2).map(gap).sum();
        assert!((odd - 180.0).abs() < 1.0e-3, "every other angle adds up to {odd}");
        for k in 0..8 {
            let up = rise[(k + 1) % 8] - rise[k];
            assert!((up.abs() - gap(k).to_radians()).abs() < 0.002, "wedge {k}: a slope of {}", up.abs() / gap(k).to_radians());
            assert!(up * (rise[(k + 2) % 8] - rise[(k + 1) % 8]) < 0.0, "crease {} neither a mountain nor a valley", (k + 1) % 8);
        }
    }

    fn the_laser() -> &'static Laser {
        crate::lasers::LASERS.iter().find(|l| l.key == "fold").expect("the fold")
    }
    fn target() -> Target {
        Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] }
    }

    /// Playback takes the plan in order and stops at the first entry not due: the plan must be in time order, or what
    /// follows a later entry waits for it (the crater's tiles waited for the forceload's end, and only one went in).
    #[test]
    fn the_plan_is_in_time_order() {
        for terrain in [false, true] {
            let ev = plan(the_laser(), &target(), terrain, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
            assert!(ev.windows(2).all(|w| w[0].0 <= w[1].0), "terrain {terrain}");
        }
    }

    /// With the terrain left alone there is only sound, and the jolts.
    #[test]
    fn without_terrain_the_fold_is_light_and_sound() {
        let ev = plan(the_laser(), &target(), false, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        assert!(ev.iter().all(|e| matches!(e.1, Act::Sound { .. } | Act::Shake { .. })), "only sounds and a jolt");
        assert!(ev.iter().any(|e| matches!(&e.1, Act::Sound { event, .. } if event == "orbital:fold.slam")));
    }

    /// Every sound the plan plays is an event with a file (tools/sounds_fold.py), each ring's starting its fall before its bang.
    #[test]
    fn the_sounds_are_there_and_on_their_beats() {
        let events = include_str!("../../../orbital-sounds/assets/orbital/sounds.json");
        let ev = plan(the_laser(), &target(), false, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
        let when = |name: &str| ev.iter().find(|e| matches!(&e.1, Act::Sound { event, .. } if event == &format!("orbital:fold.{name}"))).map(|e| e.0);
        for e in &ev {
            if let Act::Sound { event, .. } = &e.1 {
                let name = event.strip_prefix("orbital:").expect("the mod's");
                assert!(events.contains(&format!("\"{name}\"")), "{name} isn't in sounds.json");
            }
        }
        assert_eq!(when("letgo"), Some(FD_HANG));
        for k in 0..4 {
            assert_eq!(when(&format!("bang{}", k + 1)), Some(FD_SLAM[k] - FD_FALL), "bang {k}");
        }
        assert_eq!(when("fall"), Some(FD_SLAM[4] - FD_FALL));
        assert_eq!(when("slam"), Some(FD_SLAM[4]));
        assert_eq!(when("sink"), Some(FD_SLAM[4]));
        assert_eq!(when("comedown"), Some(FD_SLAM[4] + 4.6));
        assert!(when("underfoot").is_none(), "a player on the rim has no panel under them");
        let ev = plan(the_laser(), &target(), false, "minecraft:overworld", 37.0, [0.5, 66.0, 170.5], 0);
        let t = ev.iter().find(|e| matches!(&e.1, Act::Sound { event, .. } if event == "orbital:fold.underfoot")).map(|e| e.0).expect("a player inside the crater");
        assert!(t > FD_SLAM[4] + 1.5 && t < FD_SLAM[4] + 2.0, "underfoot at {t}");
    }

    /// The plan as it is made on the fire tick stays light: the tiles wait for stages of their own.
    #[test]
    fn fold_fire_cost() {
        for terrain in [false, true] {
            crate::meter::reset();
            let ev = plan(the_laser(), &target(), terrain, "minecraft:overworld", 37.0, [0.5, 66.0, 300.5], 0);
            let spent = crate::meter::spent();
            eprintln!("terrain {terrain}: plan {:.2}M on the meter, {} acts", spent as f64 / 1e6, ev.len());
            assert!(spent < 2_000_000, "the plan took {:.2}M", spent as f64 / 1e6);
        }
    }
}
