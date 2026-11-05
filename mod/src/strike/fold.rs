//! The Fold's plan: reality folded like paper, the mandala its crease pattern, the crater the scar. There is no beam. A
//! liquid-metal droplet comes down, stops dead over the target and melds into the land; everything after that is the
//! world's own geometry, far terrain included, through the fork's world warp (`render.set-warp`, shaders/fold_warp.wgsl,
//! its vertices and its fragments), timed by the strike clock; shaders/fold.wgsl draws what is not the world (the droplet,
//! the void and its stars, the point, the flash, the dust of the slams); the plan makes the sounds and the land.
//!
//! The timeline (strike seconds; FD_* here, FW_* in fold_warp.wgsl and fold.wgsl's in step, `the_warp_keeps_the_beats`):
//!   0 - FD_STOP       the droplet's fall out of the top of the sky: a glint, a plasma sheath, fire, a smoke trail
//!   FD_STOP           it stops dead in one frame, the fire rushes past it, the sound cuts to near silence
//!   FD_HANG           it has hung perfectly still; it lowers very slowly
//!   FD_TOUCH-FD_MELD  it touches the land and melds in like mercury; no splash
//!   FD_RIPPLE         the warp begins (off before it): rings running out, each bigger than the last
//!   FD_SCORE          the rings sharpen into hairline creases racing over the land, the mandala's pattern
//!   FD_TEAR           the creases split open on the void
//!   FD_FOLD-FD_SEAL   the land lifts ring by ring and closes
//!   FD_SEAL-FD_CRUSH  the bud: a globe of real land against the stars
//!   FD_CRUSH-FD_BEAT  it crushes to a point; FD_BEAT-FD_RELEASE silence, the point alone
//!   FD_RELEASE        the bloom (the one flash), then FD_SLAM: the rings slam back one after another, outermost first
//!   FD_SLAM[4]-FD_LEN the comedown: the creases fade, the void seals
//!
use super::{Act, Plan, Rng, Target, fold_land};
use crate::lasers::Laser;

pub(super) const FD_LEN: f32 = 56.0;
/// The world warp (shaders/fold_warp.wgsl): how many times it draws the land near the target again, how far from it, and
/// when it is on, the world's own culling back the rest of the time.
pub const FD_COPIES: u32 = 6;
pub const FD_COPY_R: f32 = 130.0;
pub const FD_WARP_START: f32 = 5.9;
pub const FD_WARP_END: f32 = 53.0;
/// The strike's beats (see the top of this file).
pub(super) const FD_STOP: f32 = 3.4;
pub(super) const FD_HANG: f32 = 3.9;
pub(super) const FD_TOUCH: f32 = 6.0;
pub(super) const FD_MELD: f32 = 7.2;
pub(super) const FD_RIPPLE: f32 = 6.6;
pub(super) const FD_SCORE: f32 = 12.0;
pub(super) const FD_TEAR: f32 = 16.0;
pub(super) const FD_FOLD: f32 = 19.0;
pub(super) const FD_SEAL: f32 = 31.0;
pub(super) const FD_CRUSH: f32 = 35.0;
pub(super) const FD_BEAT: f32 = 37.5;
pub(super) const FD_RELEASE: f32 = 38.7;
/// When each ring slams back down, outermost first (ring 4 at FD_SLAM[0], the eye's ring 0 last).
pub(super) const FD_SLAM: [f32; 5] = [39.8, 40.6, 41.4, 42.2, 43.1];
/// While the land's edits aren't held back by the frame time: from the sealed globe, where they can't be seen, until the
/// rings are down and the dust is flying, so the crater is whole as it is seen.
pub const FD_HIDDEN: std::ops::Range<f32> = 31.5..45.5;
/// The crease pattern's rings: their outer radii, blocks from the target (fold_warp.wgsl's FW_RING in step). Each is a
/// hinge of the fold; the crater is dug in the innermost three, the land (strike/fold_land.rs) scarred out to the fourth.
pub(super) const FD_RINGS: [f64; 5] = [44.0, 104.0, 176.0, 290.0, 480.0];

pub(super) fn fold_plan(laser: &'static Laser, target: &Target, terrain: bool, dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let s = shader_seed as u32;
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let dist = (me[0] - cx).hypot(me[2] - cz);

    // ---- sound (tools/sounds_fold.py) ------------------------------------------------------------------------------
    // (the fall, a roar cut dead on the stop; a tiny ring in the silence; the touch; then the land itself)
    p.csound(0.0, "descent", 10.0, 1.0);
    p.csound(FD_STOP, "stop", 6.0, 1.0);
    p.csound(FD_TOUCH, "meld", 8.0, 1.0);
    p.csound(FD_RIPPLE, "ripple", 7.0, 1.0);
    p.csound(FD_SCORE, "score", 8.0, 1.0);
    p.csound(FD_TEAR, "tear", 10.0, 1.0);
    // (the land bending: the groan under all of it, cut with the crush, and a huge creak as each ring goes)
    p.csound(FD_FOLD, "groan", 10.0, 1.0);
    for k in 0..5u8 {
        p.csound(FD_FOLD + 2.1 * f32::from(k), "creak", 10.0, [1.0, 0.86, 0.94, 0.78, 0.7][k as usize]);
    }
    p.csound(FD_CRUSH, "crush", 10.0, 1.0);
    p.csound(FD_RELEASE, "bloom", 10.0, 1.0);
    p.shake(FD_RELEASE, 0.3 * super::falloff(dist), 1.6);
    // (a deep thud a ring, heavier as they come in, and a jolt with each)
    for (k, t) in FD_SLAM.iter().enumerate() {
        let f = k as f32 / 4.0;
        p.csound(*t, "thud", 10.0, 1.1 - 0.35 * f);
        p.shake(*t, (0.22 + 0.3 * f) * super::falloff(dist * 0.5), 1.1 + 0.9 * f);
    }
    p.csound(FD_SLAM[4] + 1.0, "comedown", 8.0, 1.0);

    if !terrain {
        p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
        return p.ev;
    }
    // ---- the land: all of it strike/fold_land.rs ---------------------------------------------------------------------
    fold_land::land_plan(&mut p, s, dimension, me);
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
        for (name, v) in [("RIPPLE", FD_RIPPLE), ("SCORE", FD_SCORE), ("TEAR", FD_TEAR), ("FOLD", FD_FOLD), ("SEAL", FD_SEAL), ("CRUSH", FD_CRUSH), ("BEAT", FD_BEAT), ("REL", FD_RELEASE), ("SLAM4", FD_SLAM[4]), ("END", FD_WARP_END)] {
            assert!(warp.contains(&format!("const FW_{name}: f32 = {v:.1};")), "FW_{name}");
        }
        for (name, v) in [("STOP", FD_STOP), ("HANG", FD_HANG), ("TOUCH", FD_TOUCH), ("MELD", FD_MELD), ("FOLD", FD_FOLD), ("SEAL", FD_SEAL), ("CRUSH", FD_CRUSH), ("BEAT", FD_BEAT), ("REL", FD_RELEASE), ("SLAM0", FD_SLAM[0]), ("SLAM4", FD_SLAM[4])] {
            assert!(pass.contains(&format!("const FD_{name}: f32 = {v:.1};")), "FD_{name}");
        }
        for (i, r) in FD_RINGS.iter().enumerate() {
            assert!(warp.contains(&format!("case {i}: {{ return {r:.1}; }}")) || (i == 4 && warp.contains(&format!("const FW_LEN: f32 = {r:.1};"))), "ring {i}");
            assert!(pass.contains(&format!("{r:.1}")), "ring {i} in the pass");
        }
        for (k, t) in FD_SLAM.iter().enumerate() {
            let i = 4 - k;
            assert!(warp.contains(&format!("case {i}: {{ return {t:.1}; }}")) || i == 0, "slam {k}");
            assert!(pass.contains(&format!("{t:.1}")), "slam {k} in the pass");
        }
        assert!(warp.contains(&format!("const FW_DISC: f32 = {FD_COPY_R:.1};")));
        assert!(warp.contains(&format!("const FW_COPIES: f32 = {:.1};", f64::from(FD_COPIES))));
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
        assert!(ev.iter().any(|e| matches!(&e.1, Act::Sound { event, .. } if event == "orbital:fold.bloom")));
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
