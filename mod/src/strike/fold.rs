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
//!   FD_FOLDS          a branch of land comes over the hole's rim and down to the target, slower and slower, thinner at
//!                     each stage; FD_BEAT its tip touches it: a tiny light and a ding; stillness to FD_RELEASE
//!   FD_RELEASE        all of it runs backwards, gathering slowly: the sphere opens, the bud stands again with every ring up
//!   FD_SLAM           ring by ring, outermost first, each falls and bangs down, a pause and a shock to each
//!   FD_SLAM[4]        the last ring lands, and the crater shows (FD_REVEAL)
//!   FD_SLAM[4]-FD_LEN the comedown: the creases fade, the void seals
//!
use super::{Act, Plan, Rng, Target, fold_land};
use crate::lasers::Laser;

pub(super) const FD_LEN: f32 = 59.7;
/// The world warp (shaders/fold_warp.wgsl): how many times it draws the land near the target again, how far from it, and
/// when it is on, the world's own culling back the rest of the time.
pub const FD_COPIES: u32 = 5;
pub const FD_COPY_R: f32 = 130.0;
/// When the copies are drawn: the cones of the fold down, out and back.
pub const FD_COPY_ON: std::ops::Range<f32> = 34.9..42.1;
pub const FD_WARP_START: f32 = 5.5;
pub const FD_WARP_END: f32 = 56.7;
/// The strike's beats (see the top of this file).
pub(super) const FD_STOP: f32 = 3.4;
pub(super) const FD_HANG: f32 = 4.9;
pub(super) const FD_TOUCH: f32 = 6.0;
pub(super) const FD_MELD: f32 = 6.3;
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
/// The terrain on screen held as it stands, the land's edits going in behind it, not paced by the frame time.
pub const FD_HIDDEN: std::ops::Range<f32> = FD_SEAL - 0.5..FD_REVEAL;
/// The world closed round the player, from the walls coming in to their opening again: the sphere goes with them (fold_warp's
/// fw_stay), so they can't leave it or see its outside, and lib.rs keeps their flight to vanilla's and them from going too far.
pub const FD_STAY: std::ops::Range<f32> = 27.0..43.5;
/// The sphere has fully hold of them from here: moving them now doesn't show.
pub const FD_TETHER_ON: f32 = 30.0;
/// How far they are let go from where they fired (real blocks): anything past FD_TETHER is brought back (the land round the
/// target has to stay loaded). Far past where fw_reach's limit has flattened, so it doesn't show.
pub const FD_TETHER: f64 = 320.0;
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
    // (the seal and the fold running down to nothing; the ding alone; everything going back, gathering, till the first ring lands)
    p.csound(FD_SEAL, "foldown", 10.0, 1.0);
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
        }
        p.shake(*t, (0.5 + 0.4 * f) * super::falloff(dist * 0.5), 0.6 + 0.9 * f);
    }
    p.csound(FD_SLAM[4] + 1.0, "comedown", 10.0, 1.0);

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
        for (name, v) in [("RIPPLE", FD_RIPPLE), ("SCORE", FD_SCORE), ("TEAR", FD_TEAR), ("FOLD", FD_FOLD), ("SEAL", FD_SEAL), ("CRUSH", FD_CRUSH), ("BEAT", FD_BEAT), ("REL", FD_RELEASE), ("FLAT", FD_SLAM[0]), ("SLAM4", FD_SLAM[4]), ("FALL", FD_FALL), ("END", FD_WARP_END)] {
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
            assert!(pass.contains(&format!("{t:.1}")), "slam {k} in the pass");
        }
        for (k, t) in FD_FOLDS.iter().enumerate() {
            assert!(warp.contains(&format!("case {k}: {{ return {t:.1}; }}")), "fold {k}");
        }
        assert!(warp.contains(&format!("const FW_DISC: f32 = {FD_COPY_R:.1};")));
        // (the land's height as it meets the drop: the warp moves the land, the pass draws the metal and the glow on it)
        assert!(warp.contains("const FW_MEET: f32 = -0.08;") && pass.contains("const FD_MEET: f32 = -0.08;"));
        for name in ["sink", "wide", "land", "side"] {
            let body = |src: &str, p: &str| {
                let from = src.find(&format!("fn {p}_{name}(")).unwrap_or_else(|| panic!("{p}_{name}"));
                let to = from + src[from..].find("\n}\n").expect("its end");
                src[from..to].replace("FW_", "F_").replace("FD_", "F_").replace("fw_", "f_").replace("fd_", "f_").replace("globals.warp[2].x", "seed_v()")
            };
            assert_eq!(body(warp, "fw"), body(pass, "fd"), "{name}");
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
