//! The Sky Breaks' sounds, but for the panes' own (strike/skybreak.rs's `sb_pane_events`, played as each pane's pose
//! settles): what plays when, as tools/sounds_skybreak.py builds them (its notes say what each is). Everything in the
//! sky is heard on the picture wherever the player is: a sound from 560 blocks up can't wait out its distance and still
//! be on its picture (films play it on the picture too), and the build into the crack must never go quiet. What happens
//! on the land, the slam, comes late by the distance (343 blocks a second), the ground's thump sooner (five times), its
//! `_far` file cross-faded in from a few hundred blocks; the hand's descent is late with it, so it runs on to the slam
//! as the player hears it. The tear is the hook: on the picture, its `_far` file for a player far off.

use super::{Act, sound_from};

// ---- round 4's beats: the strike's own (tools/sounds_skybreak.py keeps copies: keep it in step) -----------------------
/// Round 3's beats come this much later (skybreak.rs's SB_LEAD).
const LEAD: f32 = super::skybreak::SB_LEAD;
/// The island's top meets the sky's shell and it sinks in; the sky rings from IN (strike/sb_lift.rs's LF_TOUCH, LF_RIPPLE).
const TOP: f32 = super::sb_lift::LF_TOUCH;
const IN: f32 = super::sb_lift::LF_RIPPLE;
/// The hand punches through: the first crack.
const CRACK: f32 = super::skybreak::SB_CRACK;
/// The eye's gaze lands on the player (skybreak.rs's SB_LOCK + 0.45).
const LOCK_HIT: f32 = super::skybreak::SB_LOCK + 0.45;
/// The shattered middle round the fist blown down (skybreak.rs's SB_COLLAPSE, a hair after the crack: its shatter heard
/// from up there a little after the crack's own); what looks through the holes, round 3's LEAD later (between the eye
/// opening and its gaze landing, as in round 3).
const COLLAPSE: f32 = super::skybreak::SB_COLLAPSE;
const VOID: f32 = 9.5 + LEAD;
/// The eye flares; the hand starts down through the hole; it slams the land on the target (strike/sb_hand.rs).
const FLARE: f32 = super::sb_hand::SB_FLARE;
const DOWN: f32 = super::sb_hand::SB_DOWN;
const SLAM: f32 = super::sb_hand::SB_PRESS;
/// The slam's shudder knocks the middle's outer ring loose from here, over 0.85 s (skybreak.rs's SB_KNOCK).
const KNOCK: f32 = super::skybreak::SB_KNOCK;
/// The sky heals over from here (skybreak.rs's SB_HEAL).
const HEAL: f32 = super::skybreak::SB_HEAL;
/// The sky's pane, this far over the target's ground (skybreak.rs's SB_H).
const SKY: f64 = super::skybreak::SB_H;

// ---- the files (tools/sounds_skybreak.py): where each one's beat is in it, keep in step -------------------------------
const SINK_AT: f32 = 0.3;
const RIPPLE_AT: f32 = 0.05;
const CRACK_AT: f32 = 0.02;
const WITHDRAW_AFTER: f32 = 0.3;
const GAZE_HIT: f32 = 7.6;
const FLARE_AT: f32 = 4.0;
/// (the Payload's blast_alt: its blow this far in)
const SMASH_AT: f32 = 0.02;
const SHUDDER_AT: f32 = 0.1;
/// The ground carries a blow five times as fast as the air.
const GROUND_V: f64 = 1715.0;

/// `name` a file of the Sky Breaks', or `@laser.name` another laser's (the slam's, the Payload's).
fn event(name: &str) -> String {
    match name.strip_prefix('@') {
        Some(other) => format!("orbital:{other}"),
        None => format!("orbital:skybreak.{name}"),
    }
}

/// How much of what happens on the land is its `_far` file at `d` blocks: none within `near`, all past `all`.
fn far_share(d: f64, near: f64, all: f64) -> f64 {
    let u = ((d - near) / (all - near)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}

/// The strike's sounds but the panes', for the player at `me` (in the world) and the target's ground point `at`; `hits`
/// the panes' landings (the rumble follows the last before the finale). The slam's own is the target's: the fist comes
/// down on it.
pub(super) fn sb_cues(at: [f64; 3], me: [f64; 3], hits: &[(f32, [f64; 3], f64)]) -> Vec<(f32, Act)> {
    let mut out = Vec::new();
    let mut play = |t: f32, name: &str, volume: f64| {
        if volume > 0.001 {
            out.push((t.max(0.0), Act::Sound { event: event(name), at: None, volume: volume.clamp(0.0, 1.0) as f32, pitch: 1.0 }));
        }
    };
    let (late, d) = sound_from(at, me);
    let (sky_late, _) = sound_from([at[0], at[1] + SKY, at[2]], me);
    let sky_late = sky_late.min(1.2);
    // (the lift: the land torn out, the hook, on the picture; it going up, more of the sky's than the land's)
    let far = far_share(d, 200.0, 800.0);
    let v = (1.25 / (1.0 + d / 400.0)).min(1.0);
    play(0.0, "tear", v * (1.0 - far).sqrt());
    play(0.0, "tear_far", v * far.sqrt());
    play(0.0, "rise", 0.75 + 0.25 / (1.0 + d / 300.0));
    // (into the sky, its stiff ripple, and the pressure building on to the crack, never dipping)
    play(TOP - SINK_AT, "sink", 1.0);
    play(IN - RIPPLE_AT, "ripple", 1.0);
    play(IN, "pressure", 1.0);
    // (the hand punching through, drawing back up through the hole; the sky under load from then to the last pane)
    play(CRACK - CRACK_AT, "crack", 1.0);
    play(CRACK + WITHDRAW_AFTER, "withdraw", 1.0);
    play(CRACK + 0.6, "strain", 1.0);
    // (the eye sliding in to the hole, opening, its gaze landing on them GAZE_HIT into the file)
    play(LOCK_HIT - GAZE_HIT, "gaze", 1.0);
    // (the middle falling out, high up; what looks through the holes, on into the heal; the ground settling after the
    // last pane before the finale)
    play(COLLAPSE - 0.15 + sky_late * 0.5, "collapse", 1.0);
    play(VOID, "void", 1.0);
    let last = hits.iter().map(|h| h.0).filter(|&t| t < FLARE - 3.0).fold(COLLAPSE, f32::max);
    play(last + 2.0, "rumble", 1.0);
    // (the eye's last flare, its breath drawn in from FLARE_AT before it; the hand coming down, cut on the slam as the
    // player hears it)
    play(FLARE - FLARE_AT, "flare", 1.0);
    play(DOWN + late, "descend", 1.0);
    // (the slam: the Payload's alternative blast as it plays it, through the ground first, then the air with its rush,
    // and its long rolling tail; from far off through a long stretch of air, 500 to 1,500 blocks)
    let tg = SLAM + (d / GROUND_V) as f32;
    let gap = f64::from(SLAM + late - tg);
    play(tg - 0.02, "@payload.ground_alt", (1.0 / (1.0 + d / 900.0)).clamp(0.3, 1.0) * ((gap - 0.05) / 0.9).clamp(0.25, 1.0).powf(1.5));
    let far = far_share(d, 500.0, 1500.0);
    play(SLAM + late - SMASH_AT, "@payload.blast_alt", 1.0 - far);
    play(SLAM + late - SMASH_AT, "@payload.blast_alt_far", far);
    play(SLAM + late - 0.15, "@payload.rush", 1.0);
    play(SLAM + late + 2.4, "@payload.tail", 1.0);
    // (its shudder up through the glass, the last ring of the middle cracking loose: in the sky, on the picture, but never
    // ahead of the slam it follows from)
    play((KNOCK + sky_late * 0.5).max(SLAM + late + 0.3) - SHUDDER_AT, "shudder", 1.0);
    play(HEAL - 1.0, "heal", 1.0);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const AT: [f64; 3] = [0.5, 65.0, 0.5];

    /// The cues for a player `z` blocks south of the target, 5 up: (seconds, file, volume).
    fn cues(z: f64, hits: &[f32]) -> Vec<(f32, String, f32)> {
        let hits: Vec<(f32, [f64; 3], f64)> = hits.iter().map(|&t| (t, [0.0; 3], 100.0)).collect();
        let mut v: Vec<(f32, String, f32)> = sb_cues(AT, [0.5, 70.0, 0.5 + z], &hits)
            .into_iter()
            .map(|(t, a)| match a {
                Act::Sound { event, volume, pitch, at } => {
                    assert!(at.is_none() && pitch == 1.0, "{event}");
                    let name = match event.strip_prefix("orbital:skybreak.") {
                        Some(n) => n.to_string(),
                        None => format!("@{}", event.strip_prefix("orbital:").unwrap()),
                    };
                    (t, name, volume)
                }
                _ => panic!("a cue that isn't a sound"),
            })
            .collect();
        v.sort_by(|a, b| a.0.total_cmp(&b.0));
        v
    }
    fn at(c: &[(f32, String, f32)], name: &str) -> f32 {
        c.iter().find(|e| e.1 == name).unwrap_or_else(|| panic!("no {name}")).0
    }
    fn root() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../orbital-sounds/assets/orbital")
    }
    /// A file's length in seconds, from its last Ogg page's granule position (44.1 kHz).
    fn len_of(name: &str) -> f32 {
        let file = match name.strip_prefix('@') {
            Some(o) => o.replacen('.', "/", 1),
            None => format!("skybreak/{name}"),
        };
        let b = std::fs::read(root().join(format!("sounds/{file}.ogg"))).unwrap_or_else(|_| panic!("{name} has no file"));
        let i = (0..b.len() - 14).rev().find(|&i| &b[i..i + 4] == b"OggS").expect("an Ogg page");
        u64::from_le_bytes(b[i + 6..i + 14].try_into().unwrap()) as f32 / 44_100.0
    }

    #[test]
    fn sb_sounds_every_cue_has_its_file() {
        let events = std::fs::read_to_string(root().join("sounds.json")).unwrap();
        for z in [0.0, 30.0, 300.0, 600.0, 800.0, 1500.0] {
            for (t, name, v) in cues(z, &[22.0, 25.0, 30.0]) {
                let key = name.strip_prefix('@').map_or(format!("skybreak.{name}"), str::to_string);
                assert!(events.contains(&format!("\"{key}\"")), "{name} not in sounds.json");
                assert!(t >= 0.0 && v > 0.0 && v <= 1.0, "{name} at {t}: {v}");
                assert!(len_of(&name) > 0.5, "{name}");
            }
        }
        for gone in ["fracture", "spread"] {
            assert!(!events.contains(&format!("\"skybreak.{gone}\"")), "round 3's {gone} is still in sounds.json");
        }
    }

    /// The sky's sounds are on the picture wherever the player is: the crack lands on 9.0, and from the click to it
    /// something is always sounding (the build never goes quiet), the pressure reaching it.
    #[test]
    fn sb_sounds_the_build_never_goes_quiet() {
        for z in [30.0, 300.0, 800.0, 1500.0] {
            let c = cues(z, &[22.0]);
            assert!((at(&c, "crack") + CRACK_AT - CRACK).abs() < 1e-4, "{z}: the crack at {}", at(&c, "crack"));
            assert!(at(&c, "pressure") <= IN && at(&c, "pressure") + len_of("pressure") > CRACK + 0.2, "{z}: the pressure");
            assert!(c.iter().any(|e| e.0 == 0.0 && e.1.starts_with("tear")), "{z}: the hook");
            let mut t = 0.0;
            while t < CRACK {
                assert!(c.iter().any(|e| e.0 <= t && t < e.0 + len_of(&e.1) - 0.3), "{z}: nothing sounding at {t}");
                t += 0.05;
            }
            let gaze = at(&c, "gaze");
            assert!((gaze + GAZE_HIT - LOCK_HIT).abs() < 1e-4 && gaze > CRACK + 2.0, "the gaze at {gaze}");
        }
    }

    /// The slam comes late by the distance, the ground's thump first; the descent runs on to it as the player hears
    /// it; far off it is the `_far` file; the glass shudders loose after it, never ahead of it; and nothing runs on past
    /// the heal's end but the slam itself and what follows it, late by the distance.
    #[test]
    fn sb_sounds_the_slam_comes_late_by_distance() {
        for z in [30.0, 300.0, 800.0, 1500.0] {
            let c = cues(z, &[22.0, 50.0]);
            let (late, d) = sound_from(AT, [0.5, 70.0, 0.5 + z]);
            let smash = c.iter().filter(|e| e.1.starts_with("@payload.blast_alt")).map(|e| e.0).fold(f32::MAX, f32::min);
            assert!((smash + SMASH_AT - SLAM - late).abs() < 1e-3, "{z}: the smash at {smash}");
            assert!(at(&c, "@payload.ground_alt") < smash, "{z}: the ground's thump first");
            let down = at(&c, "descend");
            assert!((down + len_of("descend") - smash - SMASH_AT).abs() < 0.05, "{z}: the descent ends at {} on a smash at {smash}", down + len_of("descend"));
            assert!(c.iter().any(|e| e.1 == if d < 500.0 { "@payload.blast_alt" } else { "@payload.blast_alt_far" }), "{z}");
            let sh = at(&c, "shudder") + SHUDDER_AT;
            assert!(sh >= KNOCK && sh >= smash + SMASH_AT + 0.25, "{z}: the shudder at {sh} on a smash at {smash}");
            assert!(c.iter().filter(|e| e.1 == "rumble").all(|e| e.0 < FLARE || e.0 > smash), "{z}: a rumble following a pane of the finale");
            let end = c.iter().filter(|e| e.0 < smash - 0.01 && !e.1.starts_with("@payload")).map(|e| e.0 + len_of(&e.1)).fold(0.0, f32::max);
            assert!(end <= HEAL - 1.0 + len_of("heal") + 0.01, "{z}: runs to {end}");
        }
    }

    /// The cues as a timeline for tools/sounds_skybreak.py's mixes: `t event volume pitch` a line. SB_ME the player's
    /// distance south of the target, SB_HITS the panes' landings (seconds, commas), SB_OUT the file.
    #[test]
    #[ignore]
    fn sb_write_cues() {
        let z: f64 = std::env::var("SB_ME").map_or(300.0, |v| v.parse().unwrap());
        let hits: Vec<f32> = std::env::var("SB_HITS").map_or(Vec::new(), |v| v.split(',').filter(|s| !s.is_empty()).map(|s| s.parse().unwrap()).collect());
        let out: String = cues(z, &hits).iter().map(|(t, name, v)| format!("{t:.3} orbital:skybreak.{name} {v:.3} 1.000\n")).collect();
        std::fs::write(std::env::var("SB_OUT").unwrap(), out).unwrap();
    }
}
