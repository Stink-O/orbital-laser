//! The Earthquake's sounds: what plays when, as tools/sounds_earthquake.py builds them (its notes say what each is; its
//! `cues` mirrors this for the listening mixes: keep both in step).
//!
//! Two takes (`/orbital quakesound synth|real`, `crate::quake_synth`): the synthesized set (`syn_*`, the default) and
//! the earlier set shaped from recordings (tools/sounds_earthquake_rec.py), both on the same timeline.
//!
//! Every file sits at a fixed level against the others, so a cue's volume is its distance only. Events heard from more
//! than one distance have `_near`, `_mid` and `_far` files, cross-faded by the player's distance (`weights`); trees,
//! grinding, falls, scree and water have no `_far` file. Two clocks: what comes through the ground (the bed, the blows,
//! the settle) late by the distance over 1700 blocks a second, so a near player has the blows' bass on the picture; what
//! comes through the air (tearing, grinding, falls, trees, water) late by the distance over 343. The distance is the
//! player's from the fault in the zone (the cliff), the crack's own from where it passes them, the crack's opening round
//! the target from the target. The lurches are the player's plate's (`EqPlates::near`), each plate's own times jittered:
//! the first is the heave, the one at `EQ_CLIMAX` the climax, those between the plates working, those after it the
//! plates going back home (terrain off).
//!
//! The trees that fall on the moving plates (terrain on, strike/eq_trees.rs) each play one of three files as they are
//! found (`eq_tree_cues`): placed at the trunk, its crash on the picture's crown hitting the land.

use super::super::{Act, Plan};
use super::super::eq_trees::{EQ_TREE_FALL, EqTree};
use super::{EQ_BASE, EQ_CAP, EQ_CLIMAX, EQ_CRACK, EQ_REST, EQ_SEG, EqPlates, K_MAIN, K_SEG, eq_h};

// ---- where each file's beat is in it (tools/sounds_earthquake.py: keep in step) ----------------------------------------
/// The blow underfoot's hit.
const BLOW_AT: f32 = 0.05;
/// The crack's loudest, passing the player; when it starts right by them, `tearclose`'s.
const TEAR_PASS: f32 = 1.6;
const TEARCLOSE_PASS: f32 = 0.35;
/// The first heave's blow (after the ground's lift) and its rip in the air.
const HEAVEBLOW_AT: f32 = 0.25;
const HEAVE_AT: f32 = 0.05;
/// A lurch's grind's hard start, its blow through the ground.
const GRIND_AT: f32 = 0.04;
const KNOCK_AT: f32 = 0.15;
/// The build ends on the climax this far in (the synthesized take's, the earlier take's).
const BUILD_LEN: f32 = 4.5;
const REAL_BUILD_LEN: f32 = 4.0;
/// The climax's blow (after the ground's lift) and its roar in the air.
const CLIMAXBLOW_AT: f32 = 0.4;
const CLIMAX_AT: f32 = 0.05;
const SETTLE_AT: f32 = 0.2;
// ---- the schedule's own numbers -----------------------------------------------------------------------------------------
/// Trees go over this long after the first heave (the earlier take only: no tree is seen to fall, they ride their
/// plates).
const TREES_AFTER: f32 = 0.5;
/// Rock comes off the cliff: this long after the second lurch; and in the build, this long before the climax.
const FALL1_AFTER: f32 = 1.2;
const FALL2_BEFORE: f32 = 2.2;
/// Rock still coming off the standing cliff (synthesized take, terrain on): (after the climax, volume).
const STANDS: [(f32, f64); 3] = [(3.2, 0.95), (6.4, 0.85), (9.7, 0.75)];
/// The earlier take's falls: (after lurch k, this long after it starts).
const REAL_FALLS: [(usize, f32); 2] = [(2, 1.6), (3, 1.2)];
/// The aftermath's slides (strike second, volume): louder first, the gaps growing, while the rubble and scree come
/// down (eq_land's `post_swap`: from 0.3 s after the swap, most of it in the first three seconds, the last 9 s after).
const SLIDES: [(f32, f32); 4] = [(31.5, 1.0), (33.4, 0.85), (35.7, 0.7), (38.3, 0.55)];
/// Water pours into the canyon from here (only where the land finds water set flowing: `eq_pour`).
const POUR_T: f32 = 33.0;
/// The crack's opening round the target is heard from afar past this far from it.
const RIP_FROM: f64 = 200.0;
const GROUND_V: f64 = 1700.0;
const AIR_V: f64 = 343.0;
// ---- one tree going over (tools/sounds_earthquake.py's TREE_*: keep in step) --------------------------------------------
/// A tree's file: its trunk splits this far in, and its crown hits the land TREE_CRASH after that: the picture's
/// EQ_TREE_FALL * EQ_TREE_A, TREE_A being where strike/eq_trees.rs's `eq_tree_turn` first reaches the quarter turn.
const TREE_SPLIT: f32 = 0.04;
const TREE_A: f32 = 0.82;
const TREE_CRASH: f32 = EQ_TREE_FALL * TREE_A;
/// The three files, picked by the hinge's hash.
const TREE_FILES: u32 = 3;
const TREE_HASH: u32 = 0x7ee5;

/// The tiers.
const TIERS: [&str; 3] = ["near", "mid", "far"];
const NM: [&str; 2] = ["near", "mid"];
/// The synthesized take's prefix.
const SYN: &str = "syn_";
/// The synthesized take's events and the tiers each has files for (`syn_{event}_{tier}`).
pub(crate) const EQ_SYN_EVENTS: [(&str, &[&str]); 29] = [
    ("bed", &TIERS),
    ("blow", &TIERS),
    ("tear", &TIERS),
    ("tearclose", &TIERS),
    ("rip", &["mid", "far"]),
    ("branch", &NM),
    ("heaveblow", &TIERS),
    ("heave", &TIERS),
    ("grind1", &NM),
    ("grind2", &NM),
    ("grind3", &NM),
    ("knock", &TIERS),
    ("fall1", &NM),
    ("fall2", &NM),
    ("fall3", &NM),
    ("fall4", &NM),
    ("fall5", &NM),
    ("build", &TIERS),
    ("climaxblow", &TIERS),
    ("climax", &TIERS),
    ("settle", &TIERS),
    ("slide1", &NM),
    ("slide2", &NM),
    ("slide3", &NM),
    ("slide4", &NM),
    ("pour", &NM),
    ("tree1", &NM),
    ("tree2", &NM),
    ("tree3", &NM),
];
/// The earlier take's events (`{event}_{tier}`); its `swell` (the ground waves, gone from the timeline) is not played.
pub(crate) const EQ_REAL_EVENTS: [(&str, &[&str]); 27] = [
    ("bed", &TIERS),
    ("blow", &TIERS),
    ("tear", &TIERS),
    ("tearclose", &TIERS),
    ("rip", &["mid", "far"]),
    ("branch", &NM),
    ("swell", &TIERS),
    ("heaveblow", &TIERS),
    ("heave", &TIERS),
    ("trees", &NM),
    ("grind1", &NM),
    ("grind2", &NM),
    ("grind3", &NM),
    ("grind4", &NM),
    ("knock", &TIERS),
    ("fall1", &NM),
    ("fall2", &NM),
    ("fall3", &NM),
    ("build", &TIERS),
    ("climaxblow", &TIERS),
    ("climax", &TIERS),
    ("settle", &TIERS),
    ("slide1", &NM),
    ("slide2", &NM),
    ("slide3", &NM),
    ("slide4", &NM),
    ("pour", &NM),
];

fn smooth(x: f64) -> f64 {
    let x = x.clamp(0.0, 1.0);
    x * x * (3.0 - 2.0 * x)
}

/// (near, mid, far) at `d` blocks: near to mid over 60-160, mid to far over 350-650, equal power.
fn weights(d: f64) -> [f64; 3] {
    use std::f64::consts::FRAC_PI_2;
    let x = smooth((d - 60.0) / 100.0) * FRAC_PI_2;
    let y = smooth((d - 350.0) / 300.0) * FRAC_PI_2;
    [x.cos(), x.sin() * y.cos(), x.sin() * y.sin()]
}

/// The whole strike's fall with distance (the tiers do the darkening).
fn gain(d: f64) -> f64 {
    (1.0 / (1.0 + (d - 60.0).max(0.0) / 500.0)).clamp(0.3, 1.0)
}

/// The distances each tier's file fades in and out over (`Act::SoundFrom`'s band; `weights` says the same of a
/// distance known as the strike fires): near, mid, far.
const BANDS: [[f32; 4]; 3] = [[0.0, 0.0, 60.0, 160.0], [60.0, 160.0, 350.0, 650.0], [350.0, 650.0, 0.0, 0.0]];

/// Event `name` of the take at strike second `t`, `vol` (0-1) of it, in each tier it has. With `from` (the line it is
/// made along): played there, each tier's file by how far that is from the player as it starts, the game fading it
/// with their distance. With none (what has no place: the rumble under everything): in the player's ears, its tiers
/// and level by `d`, how far off they stood as the strike fired.
fn play(p: &mut Plan, synth: bool, t: f32, name: &str, vol: f64, d: f64, from: Option<[[f64; 3]; 2]>) {
    let list: &[(&str, &[&str])] = if synth { &EQ_SYN_EVENTS } else { &EQ_REAL_EVENTS };
    let Some((_, tiers)) = list.iter().find(|e| e.0 == name) else { return };
    let (w, g) = (weights(d), gain(d));
    let pre = if synth { SYN } else { "" };
    for (k, tr) in TIERS.iter().enumerate() {
        if !tiers.contains(tr) {
            continue;
        }
        let event = format!("orbital:earthquake.{pre}{name}_{tr}");
        match from {
            Some([from, to]) => p.ev.push((t.max(0.0), Act::SoundFrom { event, from, to, volume: vol.min(1.0) as f32, pitch: 1.0, band: BANDS[k] })),
            None => {
                let v = vol * w[k] * g;
                if v > 0.002 {
                    p.ev.push((t.max(0.0), Act::Sound { event, at: None, volume: v.min(1.0) as f32, pitch: 1.0 }));
                }
            }
        }
    }
}

/// Where the strike's sounds in the air are made, each a line (its ends): the main fault's cliff inside the zone, the
/// crack as far as it runs toward the player, the target (a point). A sound comes from its line's nearest point to the
/// player as it starts.
fn sources(pl: &EqPlates) -> ([[f64; 3]; 2], [[f64; 3]; 2], [[f64; 3]; 2]) {
    let [u, _] = pl.me_uv;
    let y = f64::from(pl.block[1]) + 1.0;
    let at = |u: f32| {
        let [x, z] = pl.world_of([u, 0.0]);
        [x + 0.5, y, z + 0.5]
    };
    let zone = (EQ_CAP + 1.0) * pl.reach;
    let (back, fore) = if u >= 0.0 { ((EQ_CAP + 1.07) * pl.reach, pl.crack_end) } else { (pl.crack_end, (EQ_CAP + 1.07) * pl.reach) };
    let target = [f64::from(pl.block[0]) + 0.5, y, f64::from(pl.block[2]) + 0.5];
    ([at(-zone), at(zone)], [at(-back), at(fore)], [target, target])
}

/// Which of the plates' lurches is the climax (the one at `EQ_CLIMAX`): the heave is the first, the plates' working
/// ones lie between, those after it take the plates back home.
fn climax_index() -> usize {
    EQ_BASE.iter().position(|t| (t - EQ_CLIMAX).abs() < 1e-3).unwrap_or(EQ_BASE.len() - 1)
}

/// The strike's sounds for the player where they stood as it fired (`pl.me_uv`), `dist` blocks from the target.
pub(super) fn eq_sounds(p: &mut Plan, pl: &EqPlates, dist: f64, _late: f32) {
    let synth = crate::quake_synth();
    let n = pl.near();
    let [u, v] = pl.me_uv;
    // (from the fault in the zone: the cliff, the canyon, the plates working)
    let dz = f64::from((u.abs() - (EQ_CAP + 1.0) * pl.reach).max(0.0).hypot(v));
    // (from the crack where it passes them: it runs out toward them, past the zone)
    let end = if u >= 0.0 { pl.crack_end } else { (EQ_CAP + 1.07) * pl.reach };
    let dc = f64::from((u.abs() - end).max(0.0).hypot(v));
    let (gl, al) = ((dz / GROUND_V) as f32, (dz / AIR_V) as f32);
    // where each is made: the cliff where it is nearest them, the crack where it passes them, the target
    let (cliff, crack, far) = sources(pl);
    let (cliff, crack, far) = (Some(cliff), Some(crack), Some(far));
    let l = |k: usize| pl.lurch(n, k);
    let ci = climax_index();

    play(p, synth, gl, "bed", 1.0, dz, None);
    // (its hit BLOW_AT in: with the first jolt, at 0.05 s and the ground's delay; the blows are made at the cliff too:
    // only the rumble under everything and the last settle have no place)
    play(p, synth, gl, "blow", 1.0, dz, cliff);
    // the crack: loudest as it passes them, or ripping open right by them when it starts too close to run up from far
    // (past the zone it is a crack only, no plates moving: quieter the further out it passes them)
    let heard = pl.arrive([u.clamp(-pl.crack_end, pl.crack_end), 0.0], K_MAIN) + (dc / AIR_V) as f32;
    let tv = (1.0 / (1.0 + f64::from(u.abs() - (EQ_CAP + 1.07) * pl.reach).max(0.0) / 250.0)).max(0.35);
    if heard - TEAR_PASS >= EQ_CRACK - 0.1 {
        play(p, synth, heard - TEAR_PASS, "tear", tv, dc, crack);
    } else {
        play(p, synth, (heard - TEARCLOSE_PASS).max(EQ_CRACK - 0.05), "tearclose", tv, dc, crack);
    }
    if dist > RIP_FROM {
        play(p, synth, EQ_CRACK + (dist / AIR_V) as f32, "rip", 0.8, dist, far);
    }
    play(p, synth, pl.arrive([EQ_SEG * pl.reach, 0.0], K_SEG) + al, "branch", 0.9, dz, cliff);
    // the first heave
    let h = l(0).t;
    play(p, synth, h - HEAVEBLOW_AT + gl, "heaveblow", 1.0, dz, cliff);
    play(p, synth, h - HEAVE_AT + al, "heave", 1.0, dz, cliff);
    if !synth {
        play(p, synth, h + TREES_AFTER + al, "trees", 1.0, dz, cliff);
    }
    // the plates working: each lurch a grind and a blow sized by its share (the earlier take's long fourth grind on the
    // last of them, running on into the build)
    for k in 1..ci {
        let lk = l(k);
        let name = if synth { format!("grind{}", (k - 1) % 3 + 1) } else if k + 1 == ci { "grind4".to_string() } else { format!("grind{}", k.min(3)) };
        play(p, synth, lk.t - GRIND_AT + al, &name, 1.0, dz, cliff);
        play(p, synth, lk.t - KNOCK_AT + gl, "knock", 0.55 + 3.0 * f64::from(lk.w.abs()), dz, cliff);
    }
    // rock off the cliff, the build and the climax: the blow's bass on the picture close by
    let c = l(ci).t;
    if synth {
        if ci > 2 {
            play(p, synth, l(2).t + FALL1_AFTER + al, "fall1", 1.0, dz, cliff);
        }
        play(p, synth, c - FALL2_BEFORE + al, "fall2", 0.8, dz, cliff);
        play(p, synth, c - BUILD_LEN + al, "build", 1.0, dz, cliff);
    } else {
        for (i, (k, after)) in REAL_FALLS.iter().enumerate() {
            if *k < ci {
                play(p, synth, l(*k).t + after + al, &format!("fall{}", i + 1), 1.0, dz, cliff);
            }
        }
        play(p, synth, c - FALL2_BEFORE + al, "fall3", 0.8, dz, cliff);
        play(p, synth, c - REAL_BUILD_LEN + al, "build", 1.0, dz, cliff);
    }
    play(p, synth, c - CLIMAXBLOW_AT + gl, "climaxblow", 1.0, dz, cliff);
    play(p, synth, c - CLIMAX_AT + al, "climax", 1.0, dz, cliff);
    // the land standing: rock still coming off the cliff
    if synth && pl.rest {
        for (k, (after, vol)) in STANDS.iter().enumerate() {
            play(p, synth, c + after + al, &format!("fall{}", k + 3), *vol, dz, cliff);
        }
    }
    play(p, synth, EQ_REST - SETTLE_AT + gl, "settle", 1.0, dz, None);
    // the aftermath: rock off the scarps, water into the canyon; with the terrain left alone the plates grind back home
    // instead and only the first slides are heard
    for (k, (t, vol)) in SLIDES.iter().enumerate().take(if pl.rest { 4 } else { 2 }) {
        play(p, synth, t + al, &format!("slide{}", k + 1), f64::from(*vol), dz, cliff);
    }
    if !pl.rest {
        for (k, name) in (ci + 1..pl.lurch_n()).zip(["grind2", "grind3"]) {
            play(p, synth, l(k).t - GRIND_AT + al, name, 0.7, dz, cliff);
        }
    }
}

/// Water pouring into the canyon, from a stage of the land's once it has found water it sets flowing.
pub(super) fn eq_pour(p: &mut Plan, pl: &EqPlates) {
    let [u, v] = pl.me_uv;
    let dz = f64::from((u.abs() - (EQ_CAP + 1.0) * pl.reach).max(0.0).hypot(v));
    play(p, crate::quake_synth(), POUR_T + (dz / AIR_V) as f32, "pour", 1.0, dz, Some(sources(pl).0));
}

/// Which of the three tree files a hinge plays (1 to 3).
fn tree_file(h: [i32; 3]) -> u32 {
    eq_h(TREE_HASH, h[0] as u32, (h[2] as u32) ^ (h[1] as u32).wrapping_mul(0x27d4_eb2f)) % TREE_FILES + 1
}

/// The sounds of the trees that fall, for a player at `me` as they are found: for each tree one of the three files (by
/// its hinge's hash), placed at its trunk, starting `d / 343` after its fall starts less the file's lead-in, each tier
/// by how far it is from the player as it starts (`Act::SoundFrom`, from = to = the tree). Both takes play these files.
/// In time order.
pub fn eq_tree_cues(trees: &[EqTree], me: [f64; 3]) -> Vec<(f32, Act)> {
    let mut out = Vec::with_capacity(trees.len() * NM.len());
    for tree in trees {
        let at = [f64::from(tree.h[0]) + 0.5, f64::from(tree.h[1]) + 1.5, f64::from(tree.h[2]) + 0.5];
        let d = ((at[0] - me[0]).powi(2) + (at[1] - me[1]).powi(2) + (at[2] - me[2]).powi(2)).sqrt();
        let t = (tree.t0 + (d / AIR_V) as f32 - TREE_SPLIT).max(0.0);
        let k = tree_file(tree.h);
        for (i, tr) in NM.iter().enumerate() {
            let event = format!("orbital:earthquake.{SYN}tree{k}_{tr}");
            out.push((t, Act::SoundFrom { event, from: at, to: at, volume: 1.0, pitch: 1.0, band: BANDS[i] }));
        }
    }
    out.sort_by(|a, b| a.0.total_cmp(&b.0));
    out
}

/// The sounds of the slabs of the lip that come away, for a player at `me`: for each one of the five falls of rock (by
/// its place), placed at the slab, starting `d / 343` after it begins to go, each tier by how far it is from the
/// player. In time order.
pub fn eq_slab_cues(slabs: &[super::super::eq_trees::EqSlab], me: [f64; 3]) -> Vec<(f32, Act)> {
    let mut out = Vec::with_capacity(slabs.len() * NM.len());
    for s in slabs {
        let at = [f64::from(s.lo[0] + s.hi[0]) * 0.5 + 0.5, f64::from(s.yb) + 12.0, f64::from(s.lo[1] + s.hi[1]) * 0.5 + 0.5];
        let d = ((at[0] - me[0]).powi(2) + (at[1] - me[1]).powi(2) + (at[2] - me[2]).powi(2)).sqrt();
        let t = s.t0 + 0.15 + (d / AIR_V) as f32;
        let k = 1 + (s.lo[0].wrapping_mul(31) ^ s.lo[1].wrapping_mul(17)).rem_euclid(5);
        for (i, tr) in NM.iter().enumerate() {
            let event = format!("orbital:earthquake.{SYN}fall{k}_{tr}");
            out.push((t, Act::SoundFrom { event, from: at, to: at, volume: 1.0, pitch: 0.85, band: BANDS[i] }));
        }
    }
    out.sort_by(|a, b| a.0.total_cmp(&b.0));
    out
}

#[cfg(test)]
mod tests {
    use super::super::super::{Act, Target, plan};
    use super::super::{EQ_CLIMAX, EQ_CRACK, EQ_REST};
    use super::*;

    fn root() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../orbital-sounds/assets/orbital")
    }

    fn take_files() -> Vec<String> {
        let mut files = Vec::new();
        for (pre, list) in [(SYN, &EQ_SYN_EVENTS[..]), ("", &EQ_REAL_EVENTS[..])] {
            for (name, tiers) in list.iter() {
                for tr in tiers.iter() {
                    files.push(format!("{pre}{name}_{tr}"));
                }
            }
        }
        files
    }

    /// Every file of both takes has its event in sounds.json (its own file, a subtitle the language file has), every
    /// earthquake event in sounds.json and every file in the folder is one of them.
    #[test]
    fn eq_sounds_match_sounds_json() {
        let json = std::fs::read_to_string(root().join("sounds.json")).unwrap();
        let lang = std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../orbital-laser-mod/assets/orbital/lang/en_us.json")).unwrap();
        let files = take_files();
        assert_eq!(json.matches("\n  \"earthquake.").count(), files.len(), "sounds.json's earthquake events");
        for f in &files {
            let at = json.find(&format!("\n  \"earthquake.{f}\": {{")).unwrap_or_else(|| panic!("{f} not in sounds.json"));
            let body = &json[at..at + json[at..].find("\n  },").unwrap_or(json.len() - at)];
            assert!(body.contains(&format!("\"orbital:earthquake/{f}\"")), "{f}'s file");
            assert!(body.contains("\"attenuation_distance\": 1200"), "{f}: heard to 1,200 blocks (the game fades a placed sound over that)");
            let sub = body.split("\"subtitle\": \"").nth(1).and_then(|r| r.split('"').next()).unwrap();
            assert!(lang.contains(&format!("\"{sub}\":")), "{f}'s subtitle {sub}");
            assert!(root().join(format!("sounds/earthquake/{f}.ogg")).exists(), "{f}.ogg");
        }
        for e in std::fs::read_dir(root().join("sounds/earthquake")).unwrap() {
            let name = e.unwrap().file_name().into_string().unwrap();
            assert!(files.iter().any(|f| format!("{f}.ogg") == name), "{name} is in the folder but in neither take");
        }
    }

    #[test]
    fn eq_sound_tiers_cross_fade_at_equal_power() {
        for d in [0.0, 60.0, 100.0, 160.0, 250.0, 400.0, 650.0, 2000.0] {
            let w = weights(d);
            assert!((w.iter().map(|x| x * x).sum::<f64>() - 1.0).abs() < 1e-9, "{d}");
        }
        assert_eq!(weights(30.0)[0], 1.0);
        assert!(weights(900.0)[2] > 0.999);
    }

    /// The sounds on the timeline, both takes: the bed first and the blow underfoot with it, the crack passing the
    /// player when the crack does, the first heave's and the climax's blows on their picture (late only by the ground),
    /// the build ending on the climax, a grind and a blow on every lurch, every cue in the strike and its volume in
    /// (0, 1]; each event only in the tiers it has and only its take's files; terrain on or off.
    #[test]
    fn eq_sounds_keep_to_the_timeline() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let ci = climax_index();
        for synth in [true, false] {
            crate::QUAKE_SYNTH.with(|q| q.set(synth));
            let list: &[(&str, &[&str])] = if synth { &EQ_SYN_EVENTS } else { &EQ_REAL_EVENTS };
            let (pre, build_len) = if synth { (SYN, BUILD_LEN) } else { ("", REAL_BUILD_LEN) };
            for terrain in [false, true] {
                for (d, deg) in [(30.0, 40.0), (60.0, 90.0), (250.0, 90.0), (520.0, 200.0), (900.0, 10.0)] {
                    let a: f64 = f64::to_radians(deg);
                    let me = [10.5 + d * a.cos(), 66.0, -2.5 + d * a.sin()];
                    let ev = plan(&crate::lasers::EARTHQUAKE, &target, terrain, "minecraft:overworld", 37.0, me, 0);
                    let pl = super::super::eq_plates(&target, me, 37.0, terrain);
                    let n = pl.near();
                    let [u, v] = pl.me_uv;
                    let dz = f64::from((u.abs() - (EQ_CAP + 1.0) * pl.reach).max(0.0).hypot(v));
                    let (gl, al) = ((dz / GROUND_V) as f32, (dz / AIR_V) as f32);
                    let s: Vec<(f32, String, f32, bool)> = ev.iter().filter_map(|(t, a)| match a {
                        Act::Sound { event, volume, .. } | Act::SoundFrom { event, volume, .. } if event.starts_with("orbital:earthquake.") => {
                            Some((*t, event["orbital:earthquake.".len()..].to_string(), *volume, matches!(a, Act::Sound { .. })))
                        }
                        _ => None,
                    }).collect();
                    for c in &s {
                        assert_eq!(c.1.starts_with(SYN), synth, "{}: only the take's own files", c.1);
                    }
                    let when = |name: &str| s.iter().filter(|c| c.1[pre.len()..].rsplit_once('_').unwrap().0 == name).map(|c| c.0).collect::<Vec<f32>>();
                    let one = |name: &str| {
                        let w = when(name);
                        assert!(!w.is_empty(), "{d} {deg}: {name} never plays");
                        assert!(w.iter().all(|t| (t - w[0]).abs() < 1e-6), "{name}'s tiers together");
                        w[0]
                    };
                    for (t, f, vol, _) in &s {
                        assert!(*t >= 0.0 && *t < crate::lasers::EARTHQUAKE.length - 3.0, "{f} at {t}");
                        assert!(*vol > 0.0 && *vol <= 1.0, "{f}: {vol}");
                        let (name, tr) = f[pre.len()..].rsplit_once('_').unwrap();
                        let has = list.iter().find(|e| e.0 == name).unwrap_or_else(|| panic!("{f}"));
                        assert!(has.1.contains(&tr), "{f}: no such tier");
                    }
                    assert!((one("bed") - gl).abs() < 1e-5 && (one("blow") + BLOW_AT - (0.05 + gl)).abs() < 1e-5);
                    let crack = if when("tear").is_empty() { one("tearclose") + TEARCLOSE_PASS } else { one("tear") + TEAR_PASS };
                    assert!(crack >= EQ_CRACK && crack < 6.0, "{d} {deg}: the crack heard passing at {crack}");
                    assert!((one("heaveblow") + HEAVEBLOW_AT - (pl.lurch(n, 0).t + gl)).abs() < 1e-4);
                    assert!((one("climaxblow") + CLIMAXBLOW_AT - (pl.lurch(n, ci).t + gl)).abs() < 1e-4);
                    assert!((one("climaxblow") + CLIMAXBLOW_AT - EQ_CLIMAX).abs() < 0.2 + gl, "the climax on its picture");
                    assert!((one("build") + build_len - (one("climax") + CLIMAX_AT)).abs() < 1e-4, "the build ends on the climax");
                    // (a grind on every lurch, within the air's delay; none from the far tier's distance, which has no file)
                    let grinds: Vec<f32> = s.iter().filter(|c| c.1[pre.len()..].starts_with("grind")).map(|c| c.0 + GRIND_AT).collect();
                    for k in 1..ci {
                        let t = pl.lurch(n, k).t + al;
                        assert!(grinds.iter().any(|g| (g - t).abs() < 1e-4) || (dz > 600.0 && grinds.is_empty()), "the grind of lurch {k} at {dz}");
                    }
                    let mut knocks = when("knock");
                    knocks.dedup_by(|a, b| (*a - *b).abs() < 1e-6);
                    assert_eq!(knocks.len(), ci - 1, "a blow for each lurch");
                    assert!((one("settle") + SETTLE_AT - (EQ_REST + gl)).abs() < 1e-4);
                    if dz > 700.0 {
                        assert!(s.iter().all(|c| !c.3 || !c.1.ends_with("_near")), "{d}: nothing near in their ears at {dz}");
                    }
                    if dz < 600.0 {
                        assert!(when("pour").is_empty(), "the water's sound only from the land, where water runs in");
                        assert_eq!(when("trees").is_empty(), synth);
                        assert_eq!(when("slide4").is_empty(), !terrain);
                    }
                }
            }
        }
        crate::QUAKE_SYNTH.with(|q| q.set(true));
    }

    /// Everything with a place (rock tearing, grinding, falling, the blows, water) is played where it is made, along
    /// the cliff or the crack, each tier's file with its band; only the rumble under everything and the last settle
    /// are in the player's ears. A line's point lies on it, leant toward its middle; an event's tiers are at equal
    /// power at any distance.
    #[test]
    fn eq_sounds_come_from_where_they_are_made() {
        use super::super::super::{SOUND_LEAN, band_weight, sound_from_line};
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        crate::QUAKE_SYNTH.with(|q| q.set(true));
        let ears = ["bed", "settle"];
        for (d, deg) in [(30.0f64, 40.0f64), (250.0, 90.0), (520.0, 200.0)] {
            let a = deg.to_radians();
            let me = [10.5 + d * a.cos(), 66.0, -2.5 + d * a.sin()];
            let ev = plan(&crate::lasers::EARTHQUAKE, &target, true, "minecraft:overworld", 37.0, me, 0);
            let mut placed = 0;
            for (_, act) in &ev {
                match act {
                    Act::Sound { event, at, .. } if event.starts_with("orbital:earthquake.") => {
                        let name = event["orbital:earthquake.syn_".len()..].rsplit_once('_').unwrap().0;
                        assert!(at.is_none() && ears.contains(&name), "{name} in the ears");
                    }
                    Act::SoundFrom { event, from, to, band, .. } => {
                        let (name, tr) = event["orbital:earthquake.syn_".len()..].rsplit_once('_').unwrap();
                        assert!(!ears.contains(&name), "{name} from a place");
                        placed += 1;
                        assert_eq!(*band, BANDS[TIERS.iter().position(|t| *t == tr).unwrap()]);
                        // (made within the strike's land: no further from the target than the crack runs)
                        assert!((from[0] - 10.5).hypot(from[2] + 2.5) < 700.0 && (to[0] - 10.5).hypot(to[2] + 2.5) < 700.0);
                    }
                    _ => {}
                }
            }
            assert!(placed >= 20, "{d} {deg}: {placed} sounds placed");
        }
        for d in [0.0, 60.0, 100.0, 160.0, 250.0, 400.0, 650.0, 2000.0] {
            let w: Vec<f64> = BANDS.iter().map(|b| f64::from(band_weight(*b, d))).collect();
            let old = weights(d);
            assert!(w.iter().zip(old).all(|(a, b)| (a - b).abs() < 1e-6), "{d}: {w:?}");
        }
        // (a point: there, and how far)
        assert_eq!(sound_from_line([0.0, 0.0, 0.0], [3.0, 4.0, 0.0], [3.0, 4.0, 0.0]), ([3.0, 4.0, 0.0], 5.0));
        // (a line 100 off to the east running north to south, the player level with its middle: due east of them)
        assert_eq!(sound_from_line([0.0, 0.0, 0.0], [100.0, 0.0, -300.0], [100.0, 0.0, 300.0]), ([100.0, 0.0, 0.0], 100.0));
        // (standing by its south end, 30 to its west: from SOUND_LEAN up the line, and the line 30 off)
        let (p, d) = sound_from_line([70.0, 0.0, 300.0], [100.0, 0.0, -300.0], [100.0, 0.0, 300.0]);
        assert!((p[0] - 100.0).abs() < 1e-9 && (p[2] - (300.0 - SOUND_LEAN)).abs() < 1e-9 && (d - 30.0).abs() < 1e-9);
    }

    fn trees_at(n: i32) -> Vec<EqTree> {
        (0..n)
            .map(|i| EqTree { h: [(i * 37) % 211 - 105, 64 + i % 11, (i * 53) % 197 - 98], lo: [2, 2], hi: [2, 2], top: 8, dir: (i % 4) as u8, plate: 0, t0: 11.2 + (i % 9) as f32 * 0.9 })
            .collect()
    }

    /// The trees' cues: every event in sounds.json with its file (the take's list), near and mid at the trunk with
    /// their bands, in time order, each tree's two tiers together and its crash heard on the picture's (late by the
    /// air only); the three files all played over many hinges.
    #[test]
    fn eq_sound_trees_on_the_picture() {
        let json = std::fs::read_to_string(root().join("sounds.json")).unwrap();
        let me = [3.5, 66.0, -20.5];
        let trees = trees_at(240);
        let cues = eq_tree_cues(&trees, me);
        assert_eq!(cues.len(), trees.len() * 2);
        assert!(cues.windows(2).all(|w| w[0].0 <= w[1].0), "in time order");
        let mut used = [0usize; 3];
        for tree in &trees {
            let at = [f64::from(tree.h[0]) + 0.5, f64::from(tree.h[1]) + 1.5, f64::from(tree.h[2]) + 0.5];
            let mine: Vec<&(f32, Act)> = cues.iter().filter(|(_, a)| matches!(a, Act::SoundFrom { from, .. } if *from == at)).collect();
            assert_eq!(mine.len(), 2, "{:?}: near and mid", tree.h);
            let d = ((at[0] - me[0]).powi(2) + (at[1] - me[1]).powi(2) + (at[2] - me[2]).powi(2)).sqrt();
            let k = tree_file(tree.h);
            used[k as usize - 1] += 1;
            for (i, (t, a)) in mine.iter().enumerate() {
                let Act::SoundFrom { event, from, to, volume, band, .. } = a else { unreachable!() };
                assert_eq!(from, to);
                assert_eq!(*event, format!("orbital:earthquake.{SYN}tree{k}_{}", NM[i]));
                assert_eq!(*band, BANDS[i]);
                assert!(*volume > 0.0 && *volume <= 1.0);
                let f = &event["orbital:earthquake.".len()..];
                assert!(json.contains(&format!("\n  \"earthquake.{f}\": {{")), "{f} in sounds.json");
                assert!(root().join(format!("sounds/earthquake/{f}.ogg")).exists(), "{f}.ogg");
                assert!(EQ_SYN_EVENTS.iter().any(|e| f == format!("{SYN}{}_{}", e.0, NM[i]) && e.1.contains(&NM[i])));
                // (the crash in the file, TREE_SPLIT + TREE_CRASH in, heard as the crown hits the land, late by the air)
                let crash = t + TREE_SPLIT + TREE_CRASH;
                assert!((crash - (tree.t0 + EQ_TREE_FALL * TREE_A + (d / AIR_V) as f32)).abs() < 1e-4, "{:?}", tree.h);
                assert!(*t >= tree.t0 - TREE_SPLIT && *t <= tree.t0 + 1.0, "{:?}: starts with its fall", tree.h);
            }
        }
        assert!(used.iter().all(|&u| u > trees.len() / 6), "the three files all played: {used:?}");
        assert!(eq_tree_cues(&[], me).is_empty());
    }

    /// The crash's time in the files is the picture's: TREE_A is where the tree first lies on the land
    /// (`eq_tree_turn`), and the script that makes the files has the same numbers (its `--check` measures the crash in
    /// each file against them).
    #[test]
    fn eq_sound_trees_crash_in_step() {
        use super::super::super::eq_trees::eq_tree_turn;
        assert!((eq_tree_turn(TREE_A) - 1.0).abs() < 1e-6 && eq_tree_turn(TREE_A - 0.01) < 0.99, "the crown lands at TREE_A");
        assert!((TREE_CRASH - 0.738).abs() < 1e-4);
        let py = std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../tools/sounds_earthquake.py")).unwrap();
        for line in [format!("TREE_SPLIT = {TREE_SPLIT}\n"), format!("TREE_CRASH = {EQ_TREE_FALL} * {TREE_A}\n"), format!("TREE_HASH = 0x{TREE_HASH:X}\n")] {
            assert!(py.contains(&line), "tools/sounds_earthquake.py: {line}");
        }
    }

    /// `EQ_CUES_OUT=FILE EQ_TARGET=x,y,z PL_ME=x,y,z CB_SEED=7 [EQ_TERRAIN=0] cargo test --release eq_write_cues --
    /// --ignored`: a strike's sounds as the game is given them (`second event volume`), with the plates' fault line as
    /// the mod logs it, the lurches of the plate nearest the player and the camera's jolts, to lay over a recording.
    #[test]
    #[ignore]
    fn eq_write_cues() {
        let v = |k: &str, d: &str| -> Vec<f64> { std::env::var(k).unwrap_or(d.into()).split(',').map(|x| x.parse().unwrap()).collect() };
        let (t, me) = (v("EQ_TARGET", "0,64,0"), v("PL_ME", "0.5,65,100.5"));
        let seed: f32 = std::env::var("CB_SEED").map_or(7.0, |x| x.parse().unwrap());
        let terrain = std::env::var("EQ_TERRAIN").map_or(true, |x| x != "0");
        let target = Target { block: [t[0] as i32, t[1] as i32, t[2] as i32], point: [t[0] + 0.5, t[1] + 1.0, t[2] + 0.5] };
        let me = [me[0], me[1], me[2]];
        let ev = plan(&crate::lasers::EARTHQUAKE, &target, terrain, "minecraft:overworld", seed, me, 0);
        let pl = super::super::eq_plates(&target, me, seed, terrain);
        let n = pl.near();
        let mut text = format!("# fault {:.4} {:.4} shift {} {} rider {} crack_end {:.1} near {n}\n", pl.fdir[0], pl.fdir[1], pl.shift[0], pl.shift[1], pl.ride, pl.crack_end);
        for k in 0..pl.lurch_n() {
            let l = pl.lurch(n, k);
            text += &format!("# lurch {k} {:.3} {:.3} {:.3}\n", l.t, l.d, l.w);
        }
        for (t, a) in &ev {
            match a {
                Act::Shake { strength, seconds } => text += &format!("# shake {t:.3} {strength:.4} {seconds:.2}\n"),
                Act::Sound { event, volume, .. } => text += &format!("{t:.3} {} {volume:.4}\n", &event["orbital:earthquake.".len()..]),
                Act::SoundFrom { event, volume, from, to, band, .. } => {
                    text += &format!("{t:.3} {} {volume:.4} from {:.1} {:.1} {:.1} to {:.1} {:.1} {:.1} band {} {} {} {}\n", &event["orbital:earthquake.".len()..], from[0], from[1], from[2], to[0], to[1], to[2], band[0], band[1], band[2], band[3]);
                }
                _ => {}
            }
        }
        std::fs::write(std::env::var("EQ_CUES_OUT").unwrap(), text).unwrap();
    }
}
