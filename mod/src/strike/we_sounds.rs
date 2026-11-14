//! The World Eater's sounds: what plays when, as tools/sounds_worldeater.py builds the files (orbital-sounds/assets/
//! orbital/sounds/worldeater/; its notes say what each is). The path is data, so every cue is worked out from it: an arch's breach, rise, bellow, dive, landing,
//! body and tail from the arch (`we_arch_cues`); the mound under the land, the tunnel's rings, the settling and the
//! catch from the land's plan, which calls these with where and when.
//!
//! Every cue follows the player (`at: None`): the files carry their own distance (near and `_far` takes, cross-faded),
//! the volume the rest. What happens on the land comes late by its distance through the air (343 blocks a second),
//! the ground's quake five times sooner, so the low end arrives first; the bellow, up in the sky, late by at most
//! 0.6 s so it stays on its jaws. The files sit at fixed levels against each other (the bite the loudest), so a cue's
//! volume is its distance only. Files are mono (the game sums a stereo file to mono as it loads it).
// (the land's plan calls the API's other functions as it lands: until then they would warn)
#![allow(dead_code)]
use super::we_path::{we_mound, we_tunnels, WeGeo, WePath, WE_LEN};
use super::{mh, Act};

/// The take each pick plays (the others' files are kept): one line to switch.
pub(super) const WE_BELLOW_TAKE: &str = "a"; // "a" Throat (the one played), "b" Mountain horn, "c" Cavern, "d" Bore
pub(super) const WE_BITE_TAKE: &str = "c"; // "a" Hammer, "b" Swallow, "c" Quake (the one played)
/// The picks (the other takes' files kept).
pub(super) const WE_BREACH_TAKE: &str = "x"; // "x": the burst set (WE_BURST) at three distances;
// round 4, matched to real events: "e" Blast, "f" Rockfall, "g" Collapse;
// round 2: "a" Heave, "b" Ringdown, "c" Air front, "d" Upheaval
pub(super) const WE_TAIL_TAKE: &str = "d"; // round 7: "d" the reference's roar letting go; // "a" Release, "b" Suck, "c" Last pass
pub(super) const WE_THROAT_TAKE: &str = "d"; // round 7: "d" the reference's being-eaten roar; // "a" Gullet, "b" Tunnel, "c" Pressure
pub(super) const WE_SINK_SET: &str = "slump"; // "slump" (round 2: slump1..3) or "sink" (round 1: sink1..6)
pub(super) const WE_SETTLE: &str = "settle_d"; // round 7; "settle_b" round 2; // "settle_b" (round 2) or "settle" (round 1)
/// The burst (a dynamite-like blast): the files' prefix, so the
/// synthesized match (take S) can be swapped in by its own prefix. `{WE_BURST}_{k1a..k1d|hop}_{close|mid|far} (`breach_burst_*`: the burst set's `burst_*` files)`, close and
/// mid also `_dk` (the bed dipped 4 dB under the croak).
pub(super) const WE_BURST: &str = "breach_burst";
/// The big breaches' variations, in turn, never the same twice running; `hop` on the small hops (7 dB lower, no croak).
const BURST_TAKES: [&str; 4] = ["k1a", "k1b", "k1c", "k1d"];
/// Where each file's step (the whump) falls: aligned to the head clearing the ground, as heard.
fn burst_step(take: &str) -> f64 {
    match take {
        "k1a" => 1.5,
        "k1b" => 1.2,
        "k1c" => 1.4,
        "k1d" => 1.0,
        _ => 0.7,
    }
}
/// The emergence croak starts this long after the step.
const CROAK_AFTER_STEP: f64 = 0.45;
/// Round 5: the bite and the tunnel rings with their close tier (false: as round 4).
pub(super) const WE_CLOSE_TIERS: bool = true;
/// Round 5: the burrowing heard close (grind pieces with the mound) and a hole's rim breaking while the body pours
/// through it (rim pieces).
pub(super) const WE_GRIND: bool = true;
pub(super) const WE_RIM: bool = true;
pub(super) const WE_GULP: &str = "gulp_d"; // round 7; "gulp_c" Weight, "gulp_b" Eclipse (round 2) or "gulp" (round 1)
// ---- the worm's VOICE (its own set, copied in as `voice_*`): the croak at
// every breach, the purr travelling under the land rising into it, the call at the bellow hold, the bite as the jaws
// shut on the land, the swallow after a catch. Phrases are fitted end to end (round 9), never two at once and cut only where none fits.
pub(super) const WE_VOICE: bool = true;
/// The emergence takes: B and E (the broken shape, the worm over the player) for a breach within VOICE_NEAR blocks,
/// the others in turn otherwise; never the same twice running. Each starts as the head clears the ground.
const VOICE_FAR_TAKES: [&str; 3] = ["a", "c", "d"];
const VOICE_NEAR_TAKES: [&str; 2] = ["b", "e"];
const VOICE_NEAR: f64 = 150.0;
/// `voice_travel_loop_*` loop (seamless) under the land; `voice_travel_rise_*` takes over VOICE_RISE_LEAD before the
/// step and lets go by itself (the file fades from 4.2 s to nothing by 5.5 s, under the croak's moan); nothing stops it.
pub(super) const VOICE_TRAVEL_LEN: f64 = 8.0;
const VOICE_RISE_LEAD: f64 = 3.0;
/// `voice_bellow_*`: its first creak this far in; it plays from the hold's start.
pub(super) const VOICE_CALL_AT: f64 = 0.3;
/// `voice_bite_{a|b}_*`: as the jaws shut; `voice_swallow_{a|b}_*`: after the swallow, heard from inside (the far tier:
/// low-passed and roomy, as the voice through the body).
const VOICE_SWALLOW_AFTER: f64 = 1.0;
/// Round 8c: `voice_jaws_{a|b}_*` as the jaws open before a dive (VOICE_JAWS_LEAD before the landing as heard, on
/// arches out of the land long enough for the emergence to have had its say: VOICE_JAWS_MIN); `voice_spit_*` as the
/// eye passes the tip (the land's t_spit is the mouth opening, the tip VOICE_SPIT_AFTER on); `voice_inside` once during
/// the ride (VOICE_INSIDE_AFTER after the shut; in place of the swallow, which a caught player would hear from inside
/// anyway); `voice_leave_far` as it leaves (VOICE_LEAVE_AFTER after the last landing).
const VOICE_JAWS_LEAD: f64 = 1.4;
const VOICE_JAWS_MIN: f64 = 4.5;
const VOICE_SPIT_AFTER: f64 = 0.3;
const VOICE_INSIDE_AFTER: f64 = 2.5;
const VOICE_LEAVE_AFTER: f64 = 4.5;
/// With the voice in, the earth is the bed under it: the breach's surge, the gulp and the throat at this, the rims
/// lower, the approved sign/sign_short/move under the purr at VOICE_TRAVEL_BED. The voice files sit 6-10 dB under
/// the others at the same peak (their pulse fronts): the beds come down so the voice stands over them.
pub(super) const VOICE_BED: f64 = 0.45;
pub(super) const VOICE_RIM_BED: f64 = 0.35;
pub(super) const VOICE_TRAVEL_BED: f64 = 0.6;
/// The quake under the burst at the breach, kept well under it so the burst leads.
const BREACH_BED: f64 = 0.4;
/// Round 13 (contrast): what builds into a hit (the wormsign, the dive) peaks this much before it, so each hit lands
/// out of a hole; the body's pieces leave one round every hit known when they are laid (`body_starts`).
const PRE_HOLE: f64 = 0.6;
/// The wormsign's peak this far before the breach (its fall after it takes 0.75 s to come 13 dB down).
const SIGN_HOLE: f64 = 1.2;
/// Round 13: the body's pieces (from 0.85), the hole's grind (from 0.55).
const BODY_V: f64 = 0.6;
const HOLE_V: f64 = 0.3;
/// Round 12: a small hop's burst against a big breach's.
const HOP_BURST: f64 = 0.7;
/// The ground's own set (the travel set's `_real` takes): "" leaves it out.
pub(super) const WE_GROUND: &str = "real";
/// The ground under each run, so the worm is heard moving through the ground, switched in
/// the game for this session (`/orbital wormground a|b|c|old|off`): 0-2 the PASS takes a (rockslide),
/// b (segments), c (grind); 3 the older `ground_travel` loop; 4 none. Default a.
pub(crate) const WORMGROUND: [&str; 5] = ["a", "b", "c", "old", "off"];
thread_local! {
    static GROUND: std::cell::Cell<u8> = const { std::cell::Cell::new(0) };
}
pub(crate) fn set_wormground(v: u8) {
    GROUND.with(|g| g.set(v.min(4)));
}
pub(crate) fn wormground() -> u8 {
    GROUND.with(|g| g.get())
}
/// The pass takes: the burst's step PASS_LEN s into each (a reverb tail rings on
/// after it), its closest approach PASS_CLOSEST s in; tiers close_near / close_far (the breach near the player or far
/// off), mid, far.
const PASS_LEN: f64 = 12.0;
const PASS_CLOSEST: [f64; 3] = [5.6, 6.0, 5.2];
/// The lead-in loop (8 s, seamless, the far character) for what of a run comes before its pass, at this much of the
/// pass's volume to meet its start (take a/b/c; before its far, mid, close pass).
const LEAD_LEN: f64 = 8.0;
const LEAD_V: [[f64; 3]; 3] = [[0.56, 0.38, 0.18], [0.93, 0.40, 0.21], [0.38, 0.27, 0.17]];
/// Round 10, from the game's recording: the rise's bed under the croak, the dive's under the call's end.
const VOICE_RISE_BED: f64 = 0.4;
const VOICE_DIVE_BED: f64 = 0.6;
/// The re-voice: the sounds with their tone lifted to sit with the
/// voice (NAME_rv, same timing and loudness). Off.
pub(super) const WE_REVOICE: bool = false;
const REVOICED: [&str; 11] = ["sign", "sign_short", "move1", "quake1", "rise", "dive", "body1", "tail_in", "spit", "bellow_a", "bite_c"];
/// Round 6: the ride's air down the throat ("a" At the ear, "b" Organ of the throat, "c" Draughts; "" none).
pub(super) const WE_RIDE: &str = "a";

// ---- where each file's beat is in it (tools/sounds_worldeater.py's constants: keep in step) --------------------------
/// `sign` peaks this far in; `sign_short` this far.
const SIGN_PEAK: f64 = 9.0;
const SIGN_SHORT_PEAK: f64 = 4.5;
/// The blow of `bite_*`, `land*`, `quake*`, `sink*`, `slump*`, `tail_in`.
const HIT_AT: f64 = 0.10;
/// `dive` ends on the landing this far in (its first 0.8 s fades in).
const DIVE_HIT: f64 = 5.5;
/// `bellow_*`: the jaws open this far in (the swell before it).
const BELLOW_LEAD: f64 = 0.45;
/// `tail_*`: the end leaving its hole.
const TAIL_AT: f64 = 0.35;
/// `gulp`: the jaws meet; `spit`: thrown out.
const GULP_SHUT: f64 = 0.85;
const SPIT_AT: f64 = 0.25;
/// `ride_*`: the start's length (the shut at 0), the middle's (loops end to start), where the end opens to the air.
const RIDE_START: f64 = 3.0;
const RIDE_LOOP: f64 = 6.0;
const RIDE_END_OPEN: f64 = 1.1;
/// `throat_*` loop end to start: their length.
const THROAT_LEN: f64 = 8.0;
/// Where each breach take's land breaks open (its beat) in its file.
fn breach_at(take: &str) -> f64 {
    match take {
        "a" | "e" | "f" | "g" | "x" => 0.6,
        "b" => 0.25,
        "c" => 0.2,
        _ => 0.9,
    }
}
/// `body1/2` are 7 s, laid every BODY_EVERY.
const BODY_EVERY: f64 = 4.2;

/// Sound through the air and through the ground (blocks a second).
const V_AIR: f64 = 343.0;
const V_GROUND: f64 = 5.0 * 343.0;
/// An arch this high or with a hold is a big one: its landing is the bite (else a smaller landing).
const BIG_APEX: f64 = 200.0;

/// Every file (sounds.json has an event for each).
pub(super) const WE_FILES: [&str; 268] = [
    "sign", "sign_short", "move1", "move2", "move3", "breach_a", "breach_a_far", "breach_b", "breach_b_far", "breach_c",
    "breach_c_far", "breach_d", "breach_d_far", "breach_e", "breach_e_far", "breach_f", "breach_f_far", "breach_g",
    "breach_g_far", "bite_close", "bite_mid", "slump_close1",
    "slump_close2", "slump_close3", "grind1", "grind2", "grind3", "rim1", "rim2", "rim3", "ride_a_start", "ride_a_loop",
    "ride_a_end", "ride_b_start", "ride_b_loop", "ride_b_end", "ride_c_start", "ride_c_loop", "ride_c_end", "tail_d",
    "settle_d", "gulp_d", "throat_d", "sign_rv", "sign_short_rv", "move1_rv", "quake1_rv", "rise_rv", "dive_rv", "body1_rv", "tail_in_rv", "spit_rv", "bellow_a_rv", "bite_c_rv", "quake1", "quake2", "rise", "body1", "body2", "dive", "bellow_a",
    "bellow_a_far", "bellow_b", "bellow_b_far", "bellow_c", "bellow_c_far", "bellow_d", "bellow_d_far", "bite_a",
    "bite_a_far", "bite_b", "bite_b_far", "bite_c", "bite_c_far", "land1", "land2", "tail_a", "tail_b", "tail_c",
    "tail_in", "sink1", "sink2", "sink3", "sink4", "sink5", "sink6", "slump1", "slump2", "slump3", "settle", "settle_b",
    "gulp", "gulp_b", "gulp_c", "throat_a", "throat_b", "throat_c", "spit",
    "voice_emerge_a_close", "voice_emerge_a_mid", "voice_emerge_a_far", "voice_emerge_b_close", "voice_emerge_b_mid",
    "voice_emerge_b_far", "voice_emerge_c_close", "voice_emerge_c_mid", "voice_emerge_c_far", "voice_emerge_d_close",
    "voice_emerge_d_mid", "voice_emerge_d_far", "voice_emerge_e_close", "voice_emerge_e_mid", "voice_emerge_e_far",
    "voice_travel_loop_close", "voice_travel_loop_mid", "voice_travel_loop_far", "ground_travel_close", "ground_travel_mid", "ground_travel_far", "ground_hole_close", "ground_hole_mid", "ground_thrash_big_a", "ground_thrash_big_b", "ground_thrash_mid_a", "ground_thrash_mid_b", "ground_travel_close_out", "ground_travel_mid_out", "ground_travel_far_out", "ground_hole_close_out", "ground_hole_mid_out",
    "breach_burst_k1a_close_short", "breach_burst_k1a_mid_short", "breach_burst_k1a_far_short", "breach_burst_k1b_close_short", "breach_burst_k1b_mid_short", "breach_burst_k1b_far_short", "breach_burst_k1c_close_short", "breach_burst_k1c_mid_short", "breach_burst_k1c_far_short", "breach_burst_k1d_close_short", "breach_burst_k1d_mid_short", "breach_burst_k1d_far_short",
    "ground_pass_a_close_near", "ground_pass_a_close_far", "ground_pass_a_mid", "ground_pass_a_far", "ground_pass_b_close_near", "ground_pass_b_close_far", "ground_pass_b_mid", "ground_pass_b_far", "ground_pass_c_close_near", "ground_pass_c_close_far", "ground_pass_c_mid", "ground_pass_c_far", "ground_lead_a", "ground_lead_b", "ground_lead_c", "voice_pass_a_close", "voice_pass_a_mid", "voice_pass_a_far", "voice_pass_b_close", "voice_pass_b_mid", "voice_pass_b_far", "voice_pass_c_close", "voice_pass_c_mid", "voice_pass_c_far",
    "ground_pass_a_close_near_c1", "ground_pass_a_close_near_c2", "ground_pass_a_close_far_c1", "ground_pass_a_close_far_c2", "ground_pass_a_mid_c1", "ground_pass_a_mid_c2", "ground_pass_a_far_c1", "ground_pass_a_far_c2", "ground_pass_b_close_near_c1", "ground_pass_b_close_near_c2", "ground_pass_b_close_far_c1", "ground_pass_b_close_far_c2", "ground_pass_b_mid_c1", "ground_pass_b_mid_c2", "ground_pass_b_far_c1", "ground_pass_b_far_c2", "ground_pass_c_close_near_c1", "ground_pass_c_close_near_c2", "ground_pass_c_close_far_c1", "ground_pass_c_close_far_c2", "ground_pass_c_mid_c1", "ground_pass_c_mid_c2", "ground_pass_c_far_c1", "ground_pass_c_far_c2", "voice_pass_a_close_c1", "voice_pass_a_close_c2", "voice_pass_a_mid_c1", "voice_pass_a_mid_c2", "voice_pass_a_far_c1", "voice_pass_a_far_c2", "voice_pass_b_close_c1", "voice_pass_b_close_c2", "voice_pass_b_mid_c1", "voice_pass_b_mid_c2", "voice_pass_b_far_c1", "voice_pass_b_far_c2", "voice_pass_c_close_c1", "voice_pass_c_close_c2", "voice_pass_c_mid_c1", "voice_pass_c_mid_c2", "voice_pass_c_far_c1", "voice_pass_c_far_c2",
    "voice_travel_out_close",
    "voice_travel_out_mid", "voice_travel_out_far", "voice_travel_rise_close",
    "voice_travel_rise_mid", "voice_travel_rise_far", "voice_bellow_close", "voice_bellow_mid", "voice_bellow_far",
    "voice_bite_a_close", "voice_bite_a_mid", "voice_bite_a_far", "voice_bite_b_close", "voice_bite_b_mid",
    "voice_bite_b_far", "voice_swallow_a_close", "voice_swallow_a_mid", "voice_swallow_a_far", "voice_swallow_b_close",
    "voice_swallow_b_mid", "voice_swallow_b_far",
    "bite_close_dk", "bite_mid_dk", "bite_c_far_dk",
    "voice_inside", "voice_leave_far", "voice_jaws_a_close", "voice_jaws_a_mid", "voice_jaws_a_far",
    "voice_jaws_b_close", "voice_jaws_b_mid", "voice_jaws_b_far", "voice_spit_close", "voice_spit_mid", "voice_spit_far",
    "breach_burst_k1a_close", "breach_burst_k1a_close_dk", "breach_burst_k1a_mid", "breach_burst_k1a_mid_dk", "breach_burst_k1a_far", "breach_burst_k1b_close",
    "breach_burst_k1b_close_dk", "breach_burst_k1b_mid", "breach_burst_k1b_mid_dk", "breach_burst_k1b_far", "breach_burst_k1c_close", "breach_burst_k1c_close_dk",
    "breach_burst_k1c_mid", "breach_burst_k1c_mid_dk", "breach_burst_k1c_far", "breach_burst_k1d_close", "breach_burst_k1d_close_dk", "breach_burst_k1d_mid",
    "breach_burst_k1d_mid_dk", "breach_burst_k1d_far", "breach_burst_hop_close", "breach_burst_hop_close_dk", "breach_burst_hop_mid", "breach_burst_hop_mid_dk",
    "breach_burst_hop_far",
];
/// The catch's own: never stopped.
fn inside(name: &str) -> bool {
    let name = name.strip_suffix("_rv").unwrap_or(name);
    name.starts_with("gulp") || name.starts_with("throat") || name.starts_with("ride_") || name == "spit"
        // (round 12: what the catch itself plays from the shut on, which the shut's stops must not cut: the bite's
        // croak and the thud of the jaws, the voice inside, the spit's cough)
        || ["voice_bite_a_close", "voice_bite_b_close", "voice_inside", "voice_spit_close", "breach_burst_hop_close"].contains(&name)
}
/// The tunnel's rings: the set's files.
fn sink_names() -> Vec<String> {
    let k = if WE_SINK_SET == "sink" { 6 } else { 3 };
    (1..=k).map(|i| format!("{WE_SINK_SET}{i}")).collect()
}

// ---- distance -------------------------------------------------------------------------------------------------------
/// Breach, rise, bellow, body, settle, sign (250 blocks: 1, 800: 0.58).
fn vol_big(d: f64) -> f64 {
    (1.5 / (1.0 + d / 500.0)).min(1.0)
}
/// The bite and the dive into it carry furthest (800: 0.73).
fn vol_bite(d: f64) -> f64 {
    (1.9 / (1.0 + d / 500.0)).min(1.0)
}
/// The tail, the tunnel's rings (800: 0.40).
fn vol_small(d: f64) -> f64 {
    (1.3 / (1.0 + d / 350.0)).min(1.0)
}
fn vol_quake(d: f64) -> f64 {
    0.75 / (1.0 + d / 700.0)
}
fn smooth(u: f64) -> f64 {
    let u = u.clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}
/// How much is the `_far` take at `d`: none within 250, all past 700.
fn far(d: f64) -> f64 {
    smooth((d - 250.0) / 450.0)
}
/// Round 5's three distances: how much of the close (within ~90 blocks all, gone by 200), the far (from 450, all by
/// 700) and the mid (the rest) a destruction event is at `d`. Walking in from 800 blocks to 50 is one continuous change.
fn tiers3(d: f64) -> (f64, f64, f64) {
    let close = 1.0 - smooth((d - 90.0) / 110.0);
    let farw = smooth((d - 450.0) / 250.0);
    (close, (1.0 - close - farw).max(0.0), farw)
}
/// The voice's files (round 8).
pub(super) fn voice_files() -> Vec<String> {
    let mut stems: Vec<String> = ["a", "b", "c", "d", "e"].iter().map(|t| format!("voice_emerge_{t}")).collect();
    stems.extend(["voice_travel_loop", "voice_travel_rise", "voice_bellow", "voice_bite_a", "voice_bite_b", "voice_swallow_a", "voice_swallow_b", "voice_jaws_a", "voice_jaws_b", "voice_spit"].map(String::from));
    let mut v: Vec<String> = stems.iter().flat_map(|s| ["close", "mid", "far"].map(|t| format!("{s}_{t}"))).collect();
    v.push("voice_inside".into());
    v.push("voice_leave_far".into());
    v
}
/// A voice phrase at three distances (its close, mid and far files at once, shared by `tiers3`). Phrases are placed so
/// that they don't meet (round 9: the game's recording showed every `stopsound` between them as a hard edge, and the
/// emergence croaks cut before their pulses began); only where one can't fit is it cut (`voice_stop`).
fn voice_tiers(c: &mut Cues, t: f64, stem: &str, v: f64, d: f64, pitch: f64) {
    let (cw, mw, fw) = tiers3(d);
    c.play(t, &format!("{stem}_close"), v * cw, pitch);
    c.play(t, &format!("{stem}_mid"), v * mw, pitch);
    c.play(t, &format!("{stem}_far"), v * fw, pitch);
}
/// Stops one phrase's three files at `t` (only where a phrase can't be fitted before the next).
fn voice_stop(c: &mut Cues, t: f64, stem: &str) {
    for tier in ["close", "mid", "far"] {
        c.0.push((t.max(0.0) as f32, Act::Cmd(format!("stopsound @s * orbital:worldeater.{stem}_{tier}"))));
    }
}
/// The emergence takes' phrases (moan and pulses, from the manifest), s; their tails ring ~0.5 s on.
fn emerge_core(take: &str) -> f64 {
    match take {
        "a" => 4.9,
        "b" => 4.3,
        "c" => 3.9,
        "d" => 2.6,
        _ => 4.8,
    }
}
/// When arch `k`'s call starts: its hold's start as heard, less its first creak's lead; waiting for the croak's phrase
/// (`croak_end`) by up to CALL_SLIP (a short climb leaves no room for both: round 9's game recording had the croak cut
/// before its pulses).
fn call_at(geo: &WeGeo, path: &WePath, k: usize, me: [f64; 3], croak_end: Option<f64>) -> f64 {
    let a = &path.arches[k];
    let Some((h0, _, mid, _)) = a.hold else { return f64::NAN };
    let t = h0 + (dist(geo, path.point(a.s0 + mid).0, me) / V_AIR).min(0.6) - VOICE_CALL_AT;
    croak_end.map_or(t, |e| t.max((e + 0.1).min(t + CALL_SLIP)))
}
const CALL_SLIP: f64 = 1.5;
/// The call's phrase (eight doublets) and the bite's, s.
const CALL_CORE: f64 = 5.6;
const BITE_CORE: f64 = 2.0;
/// Arch `k`'s croak, if it has one: (its take, when it starts, when its phrase is over), placed to fit before the
/// arch's call or, without one, its bite: its turn's take if it fits, else the longest that does, else the shortest
/// (then cut where the next phrase starts).
fn emerge_plan(geo: &WeGeo, path: &WePath, k: usize, me: [f64; 3]) -> Option<(&'static str, f64, f64)> {
    let a = path.arches.get(k)?;
    let big = a.hold.is_some() || a.apex >= BIG_APEX;
    if !(WE_VOICE && big) {
        return None;
    }
    let d_out = dist(geo, a.from, me);
    let start = a.t_out + d_out / V_AIR + CROAK_AFTER_STEP;
    // (before the call or the bite; the call may wait up to CALL_SLIP for it (`call_at`): its turn's take if it fits,
    // else the longest that does, else the shortest, cut)
    let next = match a.hold {
        Some(_) => call_at(geo, path, k, me, None) + CALL_SLIP,
        None => a.t_in + dist(geo, a.to, me) / V_AIR,
    };
    let room = next - start - 0.1;
    let first = voice_emerge_take(geo.seed, k as u32, d_out < VOICE_NEAR);
    let take = if emerge_core(first) <= room {
        first
    } else {
        ["a", "e", "b", "c", "d"].into_iter().filter(|t| emerge_core(t) <= room).max_by(|x, y| emerge_core(x).total_cmp(&emerge_core(y))).unwrap_or("d")
    };
    let core_end = start + emerge_core(take);
    Some((take, start, if core_end <= next { (core_end + 0.5).min(next) } else { next }))
}
/// Stops every voice file but `keep`'s at `t` (a phrase never sounds over another).
fn voice_cut(c: &mut Cues, t: f64, keep: &str) {
    for f in voice_files() {
        if !f.starts_with(keep) {
            c.0.push((t.max(0.0) as f32, Act::Cmd(format!("stopsound @s * orbital:worldeater.{f}"))));
        }
    }
}
/// Which emergence take arch `k` croaks with: B/E near the player, A/C/D otherwise, each set in turn from a place the
/// seed picks (never the same twice running within a set, and the sets share none).
fn voice_emerge_take(seed: u32, k: u32, near: bool) -> &'static str {
    if near {
        VOICE_NEAR_TAKES[((seed + k) % 2) as usize]
    } else {
        VOICE_FAR_TAKES[((seed + k) % 3) as usize]
    }
}
/// The bed's gain under the voice.
fn bed(g: f64) -> f64 {
    if WE_VOICE { g } else { 1.0 }
}

/// How near the burrowing or a hole's rim is, for their close layers: all within 40 blocks, none past 170.
fn nearness(d: f64) -> f64 {
    1.0 - smooth((d - 40.0) / 130.0)
}

/// The bellow's (`d` to the head up in the sky): none within 300, all past 800.
fn far_sky(d: f64) -> f64 {
    smooth((d - 300.0) / 500.0)
}

/// How far `at` (from the origin) is from the player `me` (in the world).
fn dist(geo: &WeGeo, at: [f64; 3], me: [f64; 3]) -> f64 {
    let w = [geo.origin[0] + at[0], geo.origin[1] + at[1], geo.origin[2] + at[2]];
    ((w[0] - me[0]).powi(2) + (w[1] - me[1]).powi(2) + (w[2] - me[2]).powi(2)).sqrt()
}

/// The events, built up; a cue past the strike's end or too quiet to hear is left out, volumes and pitches kept in
/// what the game takes.
#[derive(Default)]
struct Cues(Vec<(f32, Act)>);
impl Cues {
    fn play(&mut self, t: f64, name: &str, volume: f64, pitch: f64) {
        let rv;
        let name = if WE_REVOICE && REVOICED.contains(&name) {
            rv = format!("{name}_rv");
            rv.as_str()
        } else {
            name
        };
        if volume > 0.003 {
            self.0.push((
                t.max(0.0) as f32,
                Act::Sound { event: format!("orbital:worldeater.{name}"), at: None, volume: volume.clamp(0.0, 1.0) as f32, pitch: pitch.clamp(0.5, 2.0) as f32 },
            ));
        }
    }
    /// A near take and its `_far`, cross-faded by `share`.
    fn pair(&mut self, t: f64, name: &str, volume: f64, share: f64, pitch: f64) {
        self.play(t, name, volume * (1.0 - share), pitch);
        self.play(t, &format!("{name}_far"), volume * share, pitch);
    }
}

/// A number in [0, 1) from the seed, `i` and `k` (strike.wgsl's hash).
fn h(geo: &WeGeo, i: u32, k: u32) -> f64 {
    mh(i, geo.seed, 0x3e50 + k)
}

// ---- the API ------------------------------------------------------------------------------------------------------
/// Everything the path implies, for every arch it has now (worldeater.rs calls it once at plan time):
/// `we_arch_cues` for each arch.
pub(super) fn we_cues(geo: &WeGeo, path: &WePath, me: [f64; 3]) -> Vec<(f32, Act)> {
    let mut ev: Vec<(f32, Act)> = (0..path.arches.len()).flat_map(|k| we_arch_cues(geo, path, k, me)).collect();
    ev.extend(we_last_tails(geo, path, me));
    ev
}

/// The tails whose times only the last arch's going-on settles (added to the API in round 3): call it once no more
/// arches will be appended (`we_cues` does, for a plan known up front). A tail's time depends on where the head is
/// 1,836 blocks later, so `we_arch_cues(k)` cues only the tails that arch k's own schedule settles (the head's `s`
/// from arch k-1's dive to arch k's), and an append never leaves an early cue wrong; the rest (the head past the last
/// dive, going on at its last speed) come from here.
pub(super) fn we_last_tails(geo: &WeGeo, path: &WePath, me: [f64; 3]) -> Vec<(f32, Act)> {
    let mut c = Cues::default();
    if let Some(last) = path.arches.last() {
        tails(&mut c, geo, path, me, last.s1(), f64::INFINITY);
        // (round 10: the land settling over the last tail's hole, so the strike's sound lets go over ~9 s instead of
        // ending with the last body piece)
        let d = dist(geo, last.to, me);
        c.play(path.time_at(last.s1() + WE_LEN) - HIT_AT + d / V_AIR + 0.8, WE_SETTLE, 0.7 * vol_big(d), 0.92);
        if WE_VOICE {
            // (the last croak as it leaves: heard from far away whatever the distance)
            let d = dist(geo, last.to, me);
            let t = last.t_in + d / V_AIR + VOICE_LEAVE_AFTER;
            c.play(t, "voice_leave_far", 0.6, 1.0);
        }
    }
    c.0
}

/// Every arch's tail out of its breach and into its bite whose head position `s + WE_LEN` lies in (`lo`, `hi`].
fn tails(c: &mut Cues, geo: &WeGeo, path: &WePath, me: [f64; 3], lo: f64, hi: f64) {
    for (j, a) in path.arches.iter().enumerate() {
        let ji = j as u32;
        let s_out = a.s0 + WE_LEN;
        if s_out > lo && s_out <= hi {
            let d = dist(geo, a.from, me);
            // (round 12: 0.85, from 1.2: it outdid a hop's burst landing in the same second)
            c.play(path.time_at(s_out) - TAIL_AT + d / V_AIR, &format!("tail_{WE_TAIL_TAKE}"), 0.85 * vol_small(d), 0.95 + 0.1 * h(geo, ji, 3));
        }
        let s_in = a.s1() + WE_LEN;
        if s_in > lo && s_in <= hi {
            let d = dist(geo, a.to, me);
            c.play(path.time_at(s_in) - HIT_AT + d / V_AIR, "tail_in", 1.2 * vol_small(d), 1.0);
        }
    }
}

/// Arch `k`'s own sounds (call it for an arch APPENDED during the strike, right after `push`, with the player's
/// position then): the wormsign into its breach (the long one for arch 0, the short one after), the ground's quake
/// and the breach (breach1..3 by k), the rise, the bellow if it holds, the dive into its landing, the landing (the
/// picked bite on an arch that holds or stands 200+ high, else a smaller landing), the body pouring through it, its
/// tail out and its tail in.
pub(super) fn we_arch_cues(geo: &WeGeo, path: &WePath, k: usize, me: [f64; 3]) -> Vec<(f32, Act)> {
    we_arch_cues_at(geo, path, k, me, f64::NEG_INFINITY)
}
/// As `we_arch_cues`, for an arch appended at `now` (round 14): its run's ground and croak start no earlier (a pass
/// that can't is left out for the lead-in loop).
pub(super) fn we_arch_cues_at(geo: &WeGeo, path: &WePath, k: usize, me: [f64; 3], now: f64) -> Vec<(f32, Act)> {
    let mut c = Cues::default();
    let Some(a) = path.arches.get(k) else { return c.0 };
    let run = path.runs()[k];
    let big = a.hold.is_some() || a.apex >= BIG_APEX;
    let ki = k as u32;
    // (a small hop: a smaller head, higher and quieter)
    let (hop_pitch, hop_vol) = if big { (1.0, 1.0) } else { (1.06 + 0.09 * h(geo, ki, 1), 0.8) };

    // ---- out at its knot: the wormsign building into it, the ground's quake first, the breach as the air brings it
    let d_out = dist(geo, a.from, me);
    // (the wormsign along the run into it, its peak landing on the breach as heard)
    let heard = a.t_out + d_out / V_AIR - HIT_AT;
    run_cues(&mut c, geo, path, k, heard, me, now);
    // (round 12: a bed under the burst, which leads)
    // (round 13: on the burst's step, not the ground's earlier arrival: it filled the hole before the hit)
    c.play(a.t_out + d_out / V_AIR - HIT_AT, &format!("quake{}", 1 + k % 2), vol_quake(d_out) * hop_vol * BREACH_BED, hop_pitch);
    // (one take for now, each surfacing its own pitch; the per-surfacing variants come once a take is chosen)
    let bp = [1.0, 0.94, 1.06][k % 3] * hop_pitch;
    let tb = a.t_out + d_out / V_AIR - breach_at(WE_BREACH_TAKE) / bp;
    // (the step, the head clearing the ground as heard)
    let step = a.t_out + d_out / V_AIR;
    let em = emerge_plan(geo, path, k, me);
    let croak = em.is_some();
    if let Some((tk, start, end)) = em {
        // (the croak: the moan as the body rises out, the pulses after; none on a small hop; fitted before the call or
        // the bite, cut only if even the shortest take can't fit)
        voice_tiers(&mut c, start, &format!("voice_emerge_{tk}"), vol_big(d_out), d_out, 1.0);
        if start + emerge_core(tk) > end + 0.01 {
            // (even the shortest take's pulses run into the call: cut where it starts)
            voice_stop(&mut c, end, &format!("voice_emerge_{tk}"));
        }
    }
    if WE_BREACH_TAKE == "x" {
        // (the burst: k1a-k1d in turn on the big breaches, the hop's own on a small one, at full (round 12: as loud as
        // the Payload's blast at the same distance); under a croak its `_dk`, the plain file for the first second after
        // its step and dipped only from there)
        // (a small hop's breach too is a K1 burst, 3 dB down: an explosion at every breach; the
        // hop's own whump is the thud of the landings now)
        let take = BURST_TAKES[((geo.seed + ki) % 4) as usize];
        let (cw, mw, fw) = tiers3(d_out);
        let v = vol_big(d_out) * if big { 1.0 } else { HOP_BURST };
        // (round 13: its roll let go early (`_short`) when its own landing's thud follows within 6 s and no croak needs
        // the room)
        let short = !croak && a.t_in + dist(geo, a.to, me) / V_AIR - step < 6.0;
        let dk = if croak { "_dk" } else if short { "_short" } else { "" };
        let t0 = step - burst_step(take);
        c.play(t0, &format!("{WE_BURST}_{take}_close{dk}"), v * cw, 1.0);
        c.play(t0, &format!("{WE_BURST}_{take}_mid{dk}"), v * mw, 1.0);
        c.play(t0, &format!("{WE_BURST}_{take}_far{}", if short { "_short" } else { "" }), v * fw, 1.0);
        let _ = (tb, bp);
    } else {
        c.pair(tb, &format!("breach_{WE_BREACH_TAKE}"), vol_big(d_out) * hop_vol, far(d_out), bp);
    }
    // (the stone mass rising: only a bed, under the croak (round 10: at full it sat 2 dB over it) and under the burst
    // (round 12: 13 dB under its whump))
    let rise_v = VOICE_RISE_BED;
    c.play(a.t_out + 0.3 + d_out / V_AIR, "rise", 0.9 * vol_big(d_out) * hop_vol * rise_v, hop_pitch);

    // ---- the bellow, from the head up in the sky, through its hold
    let mut call_end = em.map_or(f64::NEG_INFINITY, |e| e.2);
    if let Some((h0, _, mid, _)) = a.hold {
        let d_sky = dist(geo, path.point(a.s0 + mid).0, me);
        // (the old bellow a bed under the call, round 10)
        c.pair(h0 - BELLOW_LEAD + (d_sky / V_AIR).min(0.6), &format!("bellow_{WE_BELLOW_TAKE}"), vol_big(d_sky) * bed(VOICE_BED), far_sky(d_sky), 1.0);
        if WE_VOICE {
            // (the call over the bellow, from the hold's start)
            let tc = call_at(geo, path, k, me, em.map(|e| e.1 + emerge_core(e.0)));
            voice_tiers(&mut c, tc, "voice_bellow", vol_big(d_sky), d_sky, 1.0);
            call_end = tc + CALL_CORE;
        }
    }

    // ---- the dive into its landing, and the landing
    let d_in = dist(geo, a.to, me);
    let landed = a.t_in + d_in / V_AIR - HIT_AT;
    // (from a second before the hold's end, or a second after it came out: a fall shorter than the dive's 5.5 s plays it faster, up
    // to 1.4 times; shorter still, the rise covers it)
    let room = a.t_in - a.hold.map_or(a.t_out + 1.0, |hd| hd.1 - 1.0);
    let dive_pitch = (DIVE_HIT / room.max(0.1)).max(1.0) * hop_pitch;
    if dive_pitch <= 1.4 * hop_pitch + 1e-9 {
        // (under the call's end, a little down: round 10)
        let dive_v = if a.hold.is_some() { bed(VOICE_DIVE_BED) } else { 1.0 };
        c.play(landed + HIT_AT - PRE_HOLE - DIVE_HIT / dive_pitch, "dive", 0.9 * vol_bite(d_in) * hop_vol * dive_v, dive_pitch);
    }
    c.play(landed, &format!("quake{}", 2 - k % 2), vol_quake(d_in) * hop_vol, hop_pitch);
    // (round 12: the weight of the head going back into the land, a heavy thud on the hit (the burst's hop whump, its
    // step on it), under the bite's croak)
    thud(&mut c, landed + HIT_AT, d_in, if big { 1.0 } else { 0.8 } * vol_bite(d_in));
    if big {
        let jaw_t = landed + HIT_AT - VOICE_JAWS_LEAD;
        if WE_VOICE && a.t_in - a.t_out >= VOICE_JAWS_MIN && jaw_t >= call_end + 0.3 {
            // (the jaws opening before the dive: a short croak, only in a gap the croak or the call left)
            voice_tiers(&mut c, jaw_t, &format!("voice_jaws_{}", ["a", "b"][((geo.seed + ki) % 2) as usize]), vol_bite(d_in), d_in, 1.0);
        }
        if WE_VOICE {
            // (the jaws shutting on the land: bite A or B in turn; the call's tail let go under it if it still runs)
            if call_end > landed + HIT_AT && a.hold.is_some() {
                voice_stop(&mut c, landed + HIT_AT, "voice_bellow");
            }
            voice_tiers(&mut c, landed + HIT_AT, &format!("voice_bite_{}", ["a", "b"][((geo.seed + ki) % 2) as usize]), vol_bite(d_in), d_in, 1.0);
        }
        if WE_CLOSE_TIERS && WE_BITE_TAKE == "c" {
            let (cw, mw, fw) = tiers3(d_in);
            let vb = vol_bite(d_in) * bed(VOICE_BED);
            let dk = if WE_VOICE { "_dk" } else { "" };
            c.play(landed, &format!("bite_close{dk}"), vb * cw, 1.0);
            c.play(landed, &format!("bite_mid{dk}"), vb * mw, 1.0);
            c.play(landed, &format!("bite_c_far{dk}"), vb * fw, 1.0);
        } else {
            c.pair(landed, &format!("bite_{WE_BITE_TAKE}"), vol_bite(d_in), far(d_in), 1.0);
        }
    } else {
        // (a smaller landing, in bite C's family: land1 and land2 in turn, each its own pitch; no far take, being small)
        let small = path.arches[..k].iter().filter(|b| b.hold.is_none() && b.apex < BIG_APEX).count();
        // (round 13: 0.6, from 0.8: its 6 s roll was still in the hole before the next breach; the thud carries the hit)
        c.play(landed, &format!("land{}", 1 + small % 2), 0.6 * vol_bite(d_in), 0.95 + 0.12 * h(geo, ki, 2));
    }

    // ---- the ground's own sounds near the player: the last lunge into the breach, the body
    // grinding through the breach hole until the tail is out, a heave as the head goes back in
    if !WE_GROUND.is_empty() {
        let near = |d: f64| 1.0 - smooth((d - 120.0) / 160.0);
        if near(d_out) > 0.0 {
            c.play(step - 1.2, &format!("ground_thrash_big_{}", ["a", "b"][((geo.seed + ki) % 2) as usize]), 0.8 * near(d_out), 1.0);
        }
        ground_loop(&mut c, "ground_hole", step + 1.0, run.tail_out + d_out / V_AIR, d_out, HOLE_V * vol_big(d_out), false);
        if near(d_in) > 0.0 {
            c.play(landed + HIT_AT + 0.3, &format!("ground_thrash_mid_{}", ["a", "b"][((geo.seed + ki + 1) % 2) as usize]), 0.6 * near(d_in), 1.0);
        }
    }

    // ---- the holes' rims breaking while the body pours through them (out of its breach until the tail is out, into its
    // bite until the tail is in)
    rim(&mut c, geo, a.from, a.t_out + 0.8, run.tail_out, 2 * ki, me, a.t_out + 6.0);
    rim(&mut c, geo, a.to, a.t_in + 0.8, run.tail_in, 2 * ki + 1, me, a.t_in + 4.0);

    // ---- the body pouring through it, from its landing until the tail has gone in
    let d_mid = dist(geo, path.point(a.s0 + 0.5 * a.len).0, me);
    for (j, (t, p)) in body_starts(a.t_in + 0.4 + d_mid / V_AIR, run.tail_in - 1.0 + d_mid / V_AIR, &hits(geo, path, me)).into_iter().enumerate() {
        let j = j as u32;
        c.play(t, &format!("body{}", 1 + (j + ki) % 2), BODY_V * vol_big(d_mid), p * (1.0 - 0.03 * f64::from(j % 3)));
    }

    // ---- the tails this arch's schedule settles (any arch's: see `we_last_tails`)
    let lo = if k == 0 { f64::NEG_INFINITY } else { path.arches[k - 1].s1() };
    tails(&mut c, geo, path, me, lo, a.s1());
    c.0
}

/// The wormsign along the run into arch `k`, its breach heard at `heard`. The first approach (the head charging in
/// from W0, 30 to 140 blocks a second): `sign`, whose climb is steepest at its end, as the charge is. A later run
/// (a 160-block dash to a 500-block stalk): `move` pieces at the mound from a second after the dive for as long as the
/// run lasts, then `sign_short` into the breach; a run shorter than `sign_short` plays it faster (up to 1.6 times),
/// shorter still from the dive on.
fn run_cues(c: &mut Cues, geo: &WeGeo, path: &WePath, k: usize, heard: f64, me: [f64; 3], now: f64) {
    let a = &path.arches[k];
    let d_out = dist(geo, a.from, me);
    let tun = we_tunnels(path)[k];
    if WE_VOICE {
        // (after the last arch's phrases: its croak and its bite)
        let mut from = tun.head_in.max(0.0) + if k == 0 { 0.0 } else { 0.8 };
        if k > 0 {
            let p = &path.arches[k - 1];
            if let Some((_, _, end)) = emerge_plan(geo, path, k - 1, me) {
                from = from.max(end + 1.0);
            }
            if p.hold.is_some() || p.apex >= BIG_APEX {
                from = from.max(p.t_in + dist(geo, p.to, me) / V_AIR + BITE_CORE + 0.5);
            }
        }
        // (nothing of this run's ground before a second after the last breach: its burst leads there)
        let not_before = if k > 0 { let p = &path.arches[k - 1]; now.max(p.t_out + dist(geo, p.from, me) / V_AIR + 1.0) } else { now };
        travel(c, geo, path, from, a.t_out + d_out / V_AIR, me, not_before);
    }
    if k == 0 {
        // (from the strike's start, a little faster where its peak couldn't otherwise come SIGN_HOLE early)
        let p = (SIGN_PEAK / (heard - SIGN_HOLE).max(0.1)).clamp(1.0, 1.2);
        c.play(heard - SIGN_HOLE - SIGN_PEAK / p, "sign", vol_big(d_out) * bed(VOICE_TRAVEL_BED), p);
        // (the burrowing close by, wherever the approach passes within reach)
        let mut t = tun.head_in.max(0.0);
        let mut n = 0u32;
        while t + 2.0 < a.t_out {
            grind(c, geo, path, (t + 2.0).min(a.t_out - 0.3), t, n, me);
            t += 3.0;
            n += 1;
        }
        return;
    }
    let start = tun.head_in + 1.0;
    let room = heard - SIGN_HOLE - start;
    if room < SIGN_SHORT_PEAK {
        let p = (SIGN_SHORT_PEAK / room.max(0.1)).min(1.6);
        c.play(heard - SIGN_HOLE - SIGN_SHORT_PEAK / p, "sign_short", vol_big(d_out) * bed(VOICE_TRAVEL_BED), p);
        return;
    }
    // (the pieces overlap their 1 s fades: one every 3 s, the last ending under the short sign's build)
    let end = heard - SIGN_HOLE - SIGN_SHORT_PEAK + 1.5;
    let mut t = start;
    let mut n = 0u32;
    while t + 1.0 < end {
        let m = we_mound(path, (t + 2.0).min(a.t_out));
        let d = dist(geo, m.at, me);
        c.play(t + d / V_GROUND, &format!("move{}", 1 + (n + 3 * k as u32) % 3), 0.9 * vol_big(d) * bed(VOICE_TRAVEL_BED), 0.97 + 0.06 * h(geo, n + 16 * k as u32, 4));
        grind(c, geo, path, (t + 2.0).min(a.t_out), t, n + 16 * k as u32, me);
        t += 3.0;
        n += 1;
    }
    c.play(heard - SIGN_HOLE - SIGN_SHORT_PEAK, "sign_short", vol_big(d_out) * bed(VOICE_TRAVEL_BED), 1.0);
}

/// Round 13: every hit the path knows now, as heard: each breach's step and each landing.
fn hits(geo: &WeGeo, path: &WePath, me: [f64; 3]) -> Vec<f64> {
    path.arches.iter().flat_map(|a| [a.t_out + dist(geo, a.from, me) / V_AIR, a.t_in + dist(geo, a.to, me) / V_AIR]).collect()
}
/// Round 13: the body's pieces from `from` to `until` (as heard), one every BODY_EVERY, but round each hit: the piece
/// that would sound over it gives way to one ending on it (its 3 s let-go a hole under the hit) and the next starts
/// 0.3 s after it (its 1.2 s rise the way back up).
fn body_starts(from: f64, until: f64, hits: &[f64]) -> Vec<(f64, f64)> {
    const LEN: f64 = 7.0;
    let mut out: Vec<(f64, f64)> = Vec::new();
    let mut t = from;
    while t < until {
        let h = hits.iter().copied().filter(|&h| h > t && h < t + LEN - 0.5).fold(f64::INFINITY, f64::min);
        if h.is_infinite() {
            out.push((t, 1.0));
            t += BODY_EVERY;
        } else {
            // (a piece ending on the hit: from where it would start, else from `t` a little faster (to 1.25 times), so
            // it never sounds over the hit before; none if even that can't fit)
            let start = (h - LEN).max(t - 0.3);
            let p = LEN / (h - start);
            if p <= 1.25 && out.last().is_none_or(|&(l, lp)| l + LEN / lp < h - 0.5) {
                out.push((start, p));
            }
            t = h + 0.3;
        }
    }
    out
}
/// Round 12: a heavy thud at `t` (its step there): the burst's hop whump at three distances.
fn thud(c: &mut Cues, t: f64, d: f64, v: f64) {
    let (cw, mw, fw) = tiers3(d);
    let t0 = t - burst_step("hop");
    c.play(t0, &format!("{WE_BURST}_hop_close"), v * cw, 1.0);
    c.play(t0, &format!("{WE_BURST}_hop_mid"), v * mw, 1.0);
    c.play(t0, &format!("{WE_BURST}_hop_far"), v * fw, 1.0);
}
/// Round 12: one of the ground's 10 s loops (`stem_{close|mid|far}`, the hole's without a far one: its mid for it)
/// back to back from `from` to `until`, fitted to end there at one pitch, its last copy the `_out` that lets go.
fn ground_loop(c: &mut Cues, stem: &str, from: f64, until: f64, d: f64, v: f64, has_far: bool) {
    const LEN: f64 = 10.0;
    let span = until - from;
    if span < 4.0 || v <= 0.0 {
        return;
    }
    let n = ((span / LEN).round() as usize).max(1);
    let p = (n as f64 * LEN / span).clamp(0.89, 1.12);
    let (cw, mw, fw) = tiers3(d);
    let (mw, fw) = if has_far { (mw, fw) } else { (mw + fw, 0.0) };
    let mut t = (until - n as f64 * LEN / p).max(from - 0.5);
    for i in 0..n {
        let out = if i + 1 == n { "_out" } else { "" };
        c.play(t, &format!("{stem}_close{out}"), v * cw, p);
        c.play(t, &format!("{stem}_mid{out}"), v * mw, p);
        if has_far {
            c.play(t, &format!("{stem}_far{out}"), v * fw, p);
        }
        t += LEN / p;
    }
}

/// The purr travelling under the land (round 8): the travel loop back to back from `from` up to the step at `until`,
/// as many copies as fill it, all at one pitch so they meet the step exactly, each at the tiers and loudness of the
/// mound's distance at its middle. The last copy is `voice_travel_out_*` (the loop letting go over its last
/// VOICE_RISE_LEAD s) and the rise starts as it begins to let go, so loop, rise and croak are one line (round 10: the
/// game's recording had the loop's last copy end at full level, 9 dB over the rise's start: a hard edge). A run too
/// short for a copy has the rise alone.
fn travel(c: &mut Cues, geo: &WeGeo, path: &WePath, from: f64, until: f64, me: [f64; 3], now: f64) {
    let rise_at = until - VOICE_RISE_LEAD;
    let from = from.max(now);
    let mode = wormground();
    if mode <= 2 {
        pass(c, geo, path, from, until, me, mode as usize, now);
    } else {
        croak_loops(c, geo, path, from, until, me, 1.0);
        if mode == 3 && !WE_GROUND.is_empty() {
            // (round 12: the ground heaving and grinding under the croak, its own 10 s loop over the same run)
            let d = dist(geo, we_mound(path, (0.5 * (from + until)).max(0.0)).at, me);
            ground_loop(c, "ground_travel", from, until + 1.0, d, 0.6 * vol_big(d), true);
        }
    }
    if rise_at >= from - 0.5 {
        let d = dist(geo, we_mound(path, until.max(0.0)).at, me);
        voice_tiers(c, rise_at + d / V_GROUND, "voice_travel_rise", 0.95 * vol_big(d), d, 1.0);
    }
}

/// The travelling croak's loop back to back from `from` to `until` (as heard), fitted to end there, its last copy the
/// `_out`, each at the mound's distance at its middle, all `gain` down.
fn croak_loops(c: &mut Cues, geo: &WeGeo, path: &WePath, from: f64, until: f64, me: [f64; 3], gain: f64) {
    let span = until - from;
    if span < VOICE_TRAVEL_LEN * 0.8 {
        return;
    }
    // (within two semitones; a run that can't be filled so starts a little late instead)
    let n = ((span / VOICE_TRAVEL_LEN).round() as usize).max(1);
    let p = (n as f64 * VOICE_TRAVEL_LEN / span).clamp(0.89, 1.12);
    let mut t = until - n as f64 * VOICE_TRAVEL_LEN / p;
    for i in 0..n {
        let mid_t = (t + VOICE_TRAVEL_LEN / p / 2.0).min(until);
        let d = dist(geo, we_mound(path, mid_t.max(0.0)).at, me);
        let (cw, mw, fw) = tiers3(d);
        let v = 0.9 * vol_big(d) * gain;
        let f = if i + 1 == n { "voice_travel_out" } else { "voice_travel_loop" };
        c.play(t + d / V_GROUND, &format!("{f}_close"), v * cw, p);
        c.play(t + d / V_GROUND, &format!("{f}_mid"), v * mw, p);
        c.play(t + d / V_GROUND, &format!("{f}_far"), v * fw, p);
        t += VOICE_TRAVEL_LEN / p;
    }
}

/// Where a run passes nearest the player: (when that is heard, how near), from the mound along the run.
fn closest(geo: &WeGeo, path: &WePath, from: f64, until: f64, me: [f64; 3]) -> (f64, f64) {
    let mut best = (until, f64::INFINITY);
    let mut t = from.max(0.0);
    while t <= until {
        // (only while the head is under the land: in the air the mound is none)
        let m = we_mound(path, t);
        if m.arch.is_some() {
            let d = dist(geo, m.at, me);
            if d < best.1 {
                best = (t + d / V_AIR, d);
            }
        }
        t += 0.1;
    }
    if best.1.is_infinite() {
        best = (until, dist(geo, we_mound(path, until.max(0.0)).at, me));
    }
    best
}

/// Round 14: the worm passing under the land on a run (`from` to the step at `until`, as heard; nothing before `now`,
/// a hunt's arch being known only a few seconds ahead): ONE pass file of take `tk`, its closest-approach mark on the
/// run's closest approach as heard and its end (its last second let go) on the step, stretched by one pitch within
/// 0.89-1.12; where the two can't both be met, its end on the step if the closest comes late (a breach near the
/// player), its closest mark kept if it comes early (and the far lead-in loop after it up to the step). What of the run
/// comes before the pass has the far lead-in loop. The tier by the closest distance. The travelling croak rides the
/// same nearness (`voice_pass_*`, its level shaped by the pass's), the croak loop low under the lead-in. If even the
/// fastest pass can't start by `now`, the lead-in alone.
#[allow(clippy::too_many_arguments)]
fn pass(c: &mut Cues, geo: &WeGeo, path: &WePath, from: f64, until: f64, me: [f64; 3], tk: usize, now: f64) {
    let x = ["a", "b", "c"][tk];
    let mark = PASS_CLOSEST[tk];
    let (hc, dc) = closest(geo, path, from, until, me);
    let d_breach = dist(geo, we_mound(path, until.max(0.0)).at, me);
    let (tier, ti) = if dc < 150.0 {
        (if d_breach < 150.0 { "close_near" } else { "close_far" }, 2)
    } else if dc < 400.0 {
        ("mid", 1)
    } else {
        ("far", 0)
    };
    let v = vol_big(dc);
    let lv = v * LEAD_V[tk][ti];
    // (the whole pass if it fits, else a cut one: from 2.5 s before its closest, else from its closest; from up to
    // 6 s before the run (the head still coming down on its last arch: the pass's far start quiet under that), never
    // before `now`; none for a run of under a second, the head straight out again)
    if until - from < 1.0 {
        return;
    }
    let lowest = now.max(0.0).max(from - 6.0);
    let mut chosen = None;
    for (cut, sfx) in [(0.0, ""), (mark - 2.5, "_c1"), (mark, "_c2")] {
        let (m, len) = (mark - cut, PASS_LEN - cut);
        let want = (len - m) / (until - hc).max(0.01);
        let mut p = want.clamp(0.89, 1.12);
        // (the end on the step, unless the closest comes so early the pass would end long before it: then its
        // closest mark kept and the lead-in after it)
        let mut start = if want >= 0.89 { until - len / p } else { hc - m / p };
        if start < lowest {
            p = 1.12;
            start = until - len / p;
        }
        if start >= lowest {
            chosen = Some((start, p, len, sfx));
            break;
        }
    }
    let Some((start, p, len, sfx)) = chosen else {
        lead(c, x, from, until, lv, geo, path, me);
        return;
    };
    let vc = 0.9 * vol_big(dc);
    let (cw, mw, fw) = tiers3(dc);
    c.play(start, &format!("ground_pass_{x}_{tier}{sfx}"), v, p);
    c.play(start, &format!("voice_pass_{x}_close{sfx}"), vc * cw, p);
    c.play(start, &format!("voice_pass_{x}_mid{sfx}"), vc * mw, p);
    c.play(start, &format!("voice_pass_{x}_far{sfx}"), vc * fw, p);
    if start - from > 1.0 && sfx.is_empty() {
        lead(c, x, from, start + 0.5, lv, geo, path, me);
    }
    let end = start + len / p;
    if until - end > 1.0 {
        lead(c, x, end - 0.5, until, lv, geo, path, me);
    }
}

/// The far lead-in: its loop from `from` to `until` at `v`, the croak loop under it at the pass croak's far level.
#[allow(clippy::too_many_arguments)]
fn lead(c: &mut Cues, x: &str, from: f64, until: f64, v: f64, geo: &WeGeo, path: &WePath, me: [f64; 3]) {
    let span = until - from;
    if span < 1.0 {
        return;
    }
    let n = ((span / LEAD_LEN).round() as usize).max(1);
    let p = (n as f64 * LEAD_LEN / span).clamp(0.89, 1.12);
    let mut t = until - n as f64 * LEAD_LEN / p;
    for _ in 0..n {
        c.play(t, &format!("ground_lead_{x}"), v, p);
        t += LEAD_LEN / p;
    }
    croak_loops(c, geo, path, from, until, me, 10f64.powf(PASS_CROAK_FAR_DB / 20.0));
}
const PASS_CROAK_FAR_DB: f64 = -12.0;

/// A piece of the burrowing heard close (round 5): rock ground and broken under the land, as loud as the mound (at its
/// place at `at_t`) is near; a 4 s piece from `t`.
fn grind(c: &mut Cues, geo: &WeGeo, path: &WePath, at_t: f64, t: f64, n: u32, me: [f64; 3]) {
    if !WE_GRIND || WE_VOICE {
        return;
    }
    let d = dist(geo, we_mound(path, at_t).at, me);
    c.play(t + d / V_GROUND, &format!("grind{}", 1 + (n + geo.seed) % 3), 0.95 * nearness(d), 0.95 + 0.1 * h(geo, n, 7));
}

/// A hole's rim breaking while the body pours through it (round 5): pieces every 4 s from `from` until `until`, as
/// loud as the hole is near, easing as the pour goes on.
fn rim(c: &mut Cues, geo: &WeGeo, at: [f64; 3], from: f64, until: f64, seed: u32, me: [f64; 3], phrase_until: f64) {
    if !WE_RIM {
        return;
    }
    let d = dist(geo, at, me);
    let near = nearness(d);
    if near < 0.01 {
        return;
    }
    let mut t = from;
    let mut n = 0u32;
    while t + 1.5 < until {
        let ease = 0.45 + 0.55 * (-(t - from) / 8.0).exp();
        // (ducked a further 6 dB under a voice phrase)
        let duck = if WE_VOICE && t < phrase_until { 0.5 } else { 1.0 };
        c.play(t + d / V_AIR, &format!("rim{}", 1 + (n + seed) % 3), 0.7 * near * ease * bed(VOICE_RIM_BED) * duck, 0.95 + 0.1 * h(geo, n + 32 * seed, 8));
        t += 4.0;
        n += 1;
    }
}

/// The mound moving under the land between surfacings (HUNT): one 4 s piece from `t`, the mound at `at`. Call it every
/// 3 s while it travels, `n` counting the pieces (0, 1, 2, ...).
pub(super) fn we_move_cue(geo: &WeGeo, t: f64, at: [f64; 3], n: u32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let mut c = Cues::default();
    let d = dist(geo, at, me);
    c.play(t + d / V_GROUND, &format!("move{}", 1 + n % 3), 0.9 * vol_big(d), 0.97 + 0.06 * h(geo, n, 4));
    c.0
}

/// One ring of a tunnel giving way at `t`, at `at`; `ring` numbers the rings over the whole strike (0, 1, 2, ...): the
/// variant (the set's files, `WE_SINK_SET`: never the same twice running) and pitch come from it and the seed. Rings closer than 0.5 s are
/// fine but crowd: their tails are 4 s.
pub(super) fn we_sink_cue(geo: &WeGeo, t: f64, at: [f64; 3], ring: u32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let mut c = Cues::default();
    let d = dist(geo, at, me);
    let names = sink_names();
    let vi = sink_variant(geo.seed, ring, names.len() as u32) as usize;
    let (v, p) = ((0.85 + 0.2 * h(geo, ring, 5)) * vol_small(d), 0.9 + 0.18 * h(geo, ring, 6));
    let t = t + d / V_AIR - HIT_AT;
    if WE_CLOSE_TIERS && WE_SINK_SET == "slump" {
        let (cw, _, _) = tiers3(d);
        c.play(t, &format!("slump_close{}", vi + 1), v * cw, p);
        c.play(t, &names[vi], v * (1.0 - cw), p);
    } else {
        c.play(t, &names[vi], v, p);
    }
    c.0
}
/// A ring's variant (0..count): all of them in turn from a place the seed picks, stepping back one each ring, so no
/// two rings running are the same.
fn sink_variant(seed: u32, ring: u32, count: u32) -> u32 {
    (seed % count + (count - 1) * (ring % count)) % count
}

/// After the last ring of the strike: the land settling, the middle of what caved at `at`, from `t`.
pub(super) fn we_settle_cue(geo: &WeGeo, t: f64, at: [f64; 3], me: [f64; 3]) -> Vec<(f32, Act)> {
    let mut c = Cues::default();
    let d = dist(geo, at, me);
    c.play(t + d / V_AIR, WE_SETTLE, 0.9 * vol_big(d), 1.0);
    c.0
}

/// Caught: the jaws shut over the player at `t_close`; spat out at `t_spit`. The gulp (starting 0.85 s before
/// `t_close`: plan it at least that early), the throat through the inside, the spit; and the outside's sounds
/// stopped as the jaws meet and kept stopped while inside (`stopsound`, under the gulp's close; the next
/// surfacing's breach still plays with the spit).
pub(super) fn we_caught_cues(t_close: f64, t_spit: f64) -> Vec<(f32, Act)> {
    let mut c = Cues::default();
    c.play(t_close - GULP_SHUT, WE_GULP, bed(VOICE_BED), 1.0);
    // (round 12: the weight of the jaws meeting over the player (the burst's hop whump at the ear, a thud, its step on
    // the shut) and of being thrown out through the teeth (the K1 d burst at 0.8, its step on the spit))
    c.play(t_close - burst_step("hop"), &format!("{WE_BURST}_hop_close"), 1.0, 0.92);
    c.play(t_spit - burst_step("k1d"), &format!("{WE_BURST}_k1d_close"), 1.0, 1.0);
    if WE_VOICE {
        // (the bite's voice on the jaws shutting, the swallow from the shut; the take from the moment, so two catches
        // differ)
        let tk = ["a", "b"][((t_close * 20.0) as usize) % 2];
        voice_cut(&mut c, t_close, &format!("voice_bite_{tk}"));
        c.play(t_close, &format!("voice_bite_{tk}_close"), 1.0, 1.0);
        // (inside, once, during the ride: the voice through the body)
        if t_spit - t_close > VOICE_INSIDE_AFTER + 4.0 {
            voice_cut(&mut c, t_close + VOICE_INSIDE_AFTER, "voice_inside");
            c.play(t_close + VOICE_INSIDE_AFTER, "voice_inside", 0.85, 1.0);
        }
        // (the spit: a hard cough as the eye passes the tip)
        voice_cut(&mut c, t_spit + VOICE_SPIT_AFTER, "voice_spit");
        c.play(t_spit + VOICE_SPIT_AFTER, "voice_spit_close", 1.0, 1.0);
    }
    let mut t = t_close + 0.5;
    while t < t_spit - 0.3 {
        c.play(t, &format!("throat_{WE_THROAT_TAKE}"), if WE_RIDE.is_empty() { 0.9 } else { 0.45 } * bed(VOICE_BED), 1.0);
        t += THROAT_LEN;
    }
    // (round 6: the ride's air: the start on the shut (the dark beat, the draw gathering speed), the middle back to
    // back, each copy a little faster as the speed gathers (0.95, 1.06, then 1.12), the end opening to the air on the
    // spit; the throat's own sound kept low under it)
    if !WE_RIDE.is_empty() && t_spit - RIDE_END_OPEN > t_close + RIDE_START {
        c.play(t_close, &format!("ride_{WE_RIDE}_start"), 1.0, 1.0);
        let open = t_spit - RIDE_END_OPEN;
        let mut t = t_close + RIDE_START;
        let mut k = 0usize;
        while t < open {
            let p = [0.95, 1.06, 1.12][k.min(2)];
            c.play(t, &format!("ride_{WE_RIDE}_loop"), 1.0, p);
            t += RIDE_LOOP / p;
            k += 1;
        }
        // (round 13: down under the exit's thud, which leads)
        c.play(open, &format!("ride_{WE_RIDE}_end"), 0.35, 1.0);
    }
    c.play(t_spit - SPIT_AT, "spit", 0.6, 1.0);
    let stop = |name: &str| Act::Cmd(format!("stopsound @s * orbital:worldeater.{name}"));
    // (out again: the throat cut under the spit's burst; the ride's middle cut as its end opens to the air)
    c.0.push(((t_spit - SPIT_AT + 0.12).max(0.0) as f32, stop(&format!("throat_{WE_THROAT_TAKE}"))));
    if !WE_RIDE.is_empty() {
        c.0.push(((t_spit - RIDE_END_OPEN).max(0.0) as f32, stop(&format!("ride_{WE_RIDE}_loop"))));
    }
    let shut = (t_close + 0.02).max(0.0) as f32;
    c.0.extend(WE_FILES.iter().filter(|n| !inside(n)).map(|n| (shut, stop(n))));
    // (what could start while inside, stopped again four times a second: heard for a tick at most as it fades in,
    // under the throat)
    let mut starting: Vec<String> = ["body1", "body2", "tail_in", "move1", "move2", "move3", "sign_short"].iter().map(|n| n.to_string()).collect();
    starting.push(format!("tail_{WE_TAIL_TAKE}"));
    starting.extend(sink_names());
    let mut t = t_close + 0.25;
    while t < t_spit - SPIT_AT - 0.1 {
        c.0.extend(starting.iter().map(|n| (t as f32, stop(n))));
        t += 0.25;
    }
    c.0
}

#[cfg(test)]
mod tests {
    use super::super::we_path::{we_default_plan, we_geo, we_plan3, WE_BELLOW, WE_BITE, WE_BREACH, WE_TAIL_IN, WE_TAIL_OUT};
    use super::*;

    fn root() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../orbital-sounds/assets/orbital")
    }
    /// A file's length in seconds, from its last Ogg page's granule position (44.1 kHz).
    fn len_of(name: &str) -> f64 {
        let b = std::fs::read(root().join(format!("sounds/worldeater/{name}.ogg"))).unwrap_or_else(|_| panic!("{name} has no file"));
        let i = (0..b.len() - 14).rev().find(|&i| &b[i..i + 4] == b"OggS").expect("an Ogg page");
        u64::from_le_bytes(b[i + 6..i + 14].try_into().unwrap()) as f64 / 44_100.0
    }
    fn sounds(ev: &[(f32, Act)]) -> Vec<(f64, String, f64, f64)> {
        let mut v: Vec<_> = ev
            .iter()
            .filter_map(|(t, a)| match a {
                Act::Sound { event, volume, pitch, at: None } => {
                    Some((f64::from(*t), event.strip_prefix("orbital:worldeater.").expect("ours").to_string(), f64::from(*volume), f64::from(*pitch)))
                }
                Act::Sound { .. } => panic!("a positioned cue"),
                _ => None,
            })
            .collect();
        v.sort_by(|a, b| a.0.total_cmp(&b.0));
        v
    }
    /// The target's ground at (10.5, 65, -2.5), the player `d` blocks off square to the line (seed 37).
    fn scene(d: f64) -> (WeGeo, [f64; 3]) {
        let me = [10.5, 65.0, -2.5 + d];
        (we_geo([10.5, 65.0, -2.5], me, 37), me)
    }
    fn first(c: &[(f64, String, f64, f64)], name: &str) -> (f64, f64) {
        c.iter().find(|e| e.1 == name).map(|e| (e.0, e.2)).unwrap_or_else(|| panic!("no {name} in {c:?}"))
    }

    /// Prints the cue sheet for a scene (`WE_DUMP=tx,ty,tz,px,py,pz,seed`): every sound and stop, in order.
    #[test]
    #[ignore]
    fn we_sounds_dump() {
        let v: Vec<f64> = std::env::var("WE_DUMP").unwrap_or("-420,96,2039,-420,64,2250,0".into()).split(',').map(|x| x.parse().unwrap()).collect();
        let mut me = [v[3], v[4], v[5]];
        let g = we_geo([v[0], v[1], v[2]], me, v[6] as u32);
        if let Ok(m) = std::env::var("WE_GROUNDMODE") {
            set_wormground(m.parse().unwrap());
        }
        // (WE_UNDER=k: the player stood over the middle of the run into arch k, for a pass right under them)
        if let Ok(k) = std::env::var("WE_UNDER") {
            let k: usize = k.parse().unwrap();
            {
                let path = if std::env::var("WE_PLAN").as_deref() == Ok("3") { we_plan3(&g) } else { we_default_plan(&g) };
                let tun = we_tunnels(&path)[k];
                let ts: Vec<f64> = (0..400).map(|i| tun.head_in.max(0.0) + f64::from(i) * 0.05).filter(|&t| t < path.arches[k].t_out && we_mound(&path, t).arch.is_some()).collect();
                let at = we_mound(&path, ts[ts.len() / 2]).at;
                // (the path kept as the first player made it: only the ear moves)
                me = [g.origin[0] + at[0] + 10.0, g.origin[1] + at[1] + 2.0, g.origin[2] + at[2]];
            }
        }
        let path = if std::env::var("WE_PLAN").as_deref() == Ok("3") { we_plan3(&g) } else { we_default_plan(&g) };
        let mut ev = we_cues(&g, &path, me);
        // (WE_CATCH=t_close,t_spit: caught, as the hunt plays it)
        if let Ok(cc) = std::env::var("WE_CATCH") {
            let t: Vec<f64> = cc.split(',').map(|x| x.parse().unwrap()).collect();
            ev.extend(we_caught_cues(t[0], t[1]));
        }
        // (the steps and landings as heard, for the level pictures)
        {
            let tun = we_tunnels(&path);
            for (k, a) in path.arches.iter().enumerate() {
                let (hc, dc) = closest(&g, &path, tun[k].head_in.max(0.0), a.t_out + dist(&g, a.from, me) / V_AIR, me);
                println!("# run {k} closest heard {hc:.2} at {dc:.0} blocks");
            }
        }
        for a in &path.arches {
            println!("# step {:.2} land {:.2} big {}", a.t_out + dist(&g, a.from, me) / V_AIR, a.t_in + dist(&g, a.to, me) / V_AIR, a.hold.is_some() || a.apex >= BIG_APEX);
        }
        ev.sort_by(|a, b| a.0.total_cmp(&b.0));
        for (t, a) in &ev {
            match a {
                Act::Sound { event, volume, pitch, .. } => println!("{t:7.2}  play {} v{volume:.2} p{pitch:.2}", event.trim_start_matches("orbital:worldeater.")),
                Act::Cmd(c) => println!("{t:7.2}  {}", c.replace("orbital:worldeater.", "")),
                _ => {}
            }
        }
    }

    /// Every file has its event in sounds.json and a subtitle, every event and every file in the folder is one of
    /// the World Eater's, and every file is played by something here (but the bellow takes the switch doesn't pick).
    #[test]
    fn we_sounds_every_event_has_its_file_and_every_file_is_used() {
        let json = std::fs::read_to_string(root().join("sounds.json")).unwrap();
        let lang = std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../orbital-laser-mod/assets/orbital/lang/en_us.json")).unwrap();
        assert_eq!(json.matches("\n  \"worldeater.").count(), WE_FILES.len(), "sounds.json's worldeater events");
        for name in WE_FILES {
            let key = format!("worldeater.{name}");
            assert!(json.contains(&format!("\n  \"{key}\": {{")), "{key} not in sounds.json");
            assert!(json.contains(&format!("\"orbital:worldeater/{name}\"")), "{key}'s file not in sounds.json");
            assert!(lang.contains(&format!("\"subtitles.orbital.{key}\"")), "{key} has no subtitle");
            assert!(len_of(name) > 1.0, "{name}");
        }
        for f in std::fs::read_dir(root().join("sounds/worldeater")).unwrap() {
            let n = f.unwrap().file_name().into_string().unwrap();
            let n = n.strip_suffix(".ogg").expect("only oggs");
            assert!(WE_FILES.contains(&n), "{n}.ogg isn't one of the World Eater's");
        }
        let mut used = std::collections::BTreeSet::new();
        // (round 14: every ground the game's switch picks)
        for mode in 0..5u8 {
        set_wormground(mode);
        for d in [0.0f64, 100.0, 300.0, 900.0, -1.0] {
            let (g, me) = scene(d.max(0.0));
            // (and a player standing by the bite's hole, for its close tier)
            let me = if d < 0.0 { [g.origin[0] + g.d[0] + 30.0, g.origin[1], g.origin[2] + g.d[2]] } else { me };
            for path in [we_default_plan(&g), we_plan3(&g)] {
                let mut ev = we_cues(&g, &path, me);
                for r in 0..6 {
                    ev.extend(we_sink_cue(&g, 31.0 + f64::from(r), [100.0, 0.0, 0.0], r, me));
                    ev.extend(we_move_cue(&g, 2.0 + f64::from(r), [-200.0, 0.0, 0.0], r, me));
                }
                ev.extend(we_settle_cue(&g, 39.0, [130.0, 0.0, 0.0], me));
                ev.extend(we_caught_cues(19.0, 29.0));
                ev.extend(we_caught_cues(19.05, 29.0));
                used.extend(sounds(&ev).into_iter().map(|e| e.1));
            }
        }
        }
        set_wormground(0);
        // (the burrowing's pieces rotate with the seed: a player standing on the target, three seeds)
        for seed in [36u32, 38, 39, 40] {
            for me in [[10.5, 65.0, -2.5], [10.5, 65.0, 297.5]] {
                let g = we_geo([10.5, 65.0, -2.5], [10.5, 65.0, 97.5], seed);
                used.extend(sounds(&we_cues(&g, &we_default_plan(&g), me)).into_iter().map(|e| e.1));
                used.extend(sounds(&we_cues(&g, &we_plan3(&g), me)).into_iter().map(|e| e.1));
            }
        }
        // (the takes and sets a switch at the top doesn't pick are kept for switching)
        let picked = |name: &str, pre: &str, pick: &str| !name.starts_with(pre) || name.starts_with(&format!("{pre}{pick}"));
        for name in WE_FILES {
            let switch = !picked(name, "bellow_", WE_BELLOW_TAKE)
                || !picked(name, "bite_", WE_BITE_TAKE)
                || !picked(name, "breach_", WE_BREACH_TAKE)
                || (name.starts_with("tail_") && name != "tail_in" && !picked(name, "tail_", WE_TAIL_TAKE))
                || !picked(name, "throat_", WE_THROAT_TAKE)
                || (name.starts_with("sink") && WE_SINK_SET != "sink")
                || (name.starts_with("slump") && WE_SINK_SET != "slump")
                || (name.starts_with("settle") && name != WE_SETTLE)
                || (name.starts_with("gulp") && name != WE_GULP)
                || (WE_CLOSE_TIERS && name == "bite_c")
                || (name.ends_with("_rv") && !WE_REVOICE)
                || (name.starts_with("grind") && WE_VOICE)
                || name.starts_with("voice_swallow")
                // (round 9: the emergence takes fitted before the call; the long ones (a, b, e: 4.3-4.9 s) only where
                // the climb leaves room, none in these plans)
                // (and the jaws only in a gap the call leaves)
                || ["voice_emerge_a", "voice_emerge_b", "voice_emerge_e", "voice_jaws_"].iter().any(|p| name.starts_with(p))
                // (the loop itself only on a run longer than one copy: these plans' runs are all one, `_out`)
                || name.starts_with("voice_travel_loop_")
                || (name.starts_with("voice_spit") && !name.ends_with("_close"))
                || (WE_VOICE && ["bite_close", "bite_mid", "bite_c_far"].contains(&name))
                // (a burst variation's tiers: each variation must sound somewhere, each tier only at its distances)
                || (name.starts_with("breach_burst_") && used.iter().any(|u: &String| u.starts_with(&name[..16])))
                // (an emergence take's tiers: every take must sound somewhere, each tier only at its distances)
                || (name.starts_with("voice_") && used.iter().any(|u: &String| u.starts_with(name.rsplit_once('_').unwrap().0)))
                // (round 14: a pass take's tiers: each take must sound somewhere, each tier only at its distances)
                || (name.starts_with("ground_pass_") && used.iter().any(|u: &String| u.starts_with(&name[..14])))
                // (the lead-in only on a run longer than its pass: these plans' runs are shorter)
                || name.starts_with("ground_lead_")
                // (round 12: the ground's loops: any tier of a loop sounding, or its `_out`, covers the loop)
                || (name.starts_with("ground_") && used.iter().any(|u: &String| u.starts_with(name.trim_end_matches("_out").rsplit_once('_').unwrap().0)))
                || (name.starts_with("ride_") && !name.starts_with(&format!("ride_{WE_RIDE}_")));
            assert!(used.contains(name) || switch, "{name} is never played");
        }
    }

    /// Volumes in 0..1, pitches in the game's 0.5..2, times inside the strike: for the player near and far, in both
    /// plans and every call.
    #[test]
    fn we_sounds_inside_the_games_limits() {
        for d in [0.0, 60.0, 250.0, 500.0, 800.0, 1200.0] {
            let (g, me) = scene(d);
            for path in [we_default_plan(&g), we_plan3(&g)] {
                let mut ev = we_cues(&g, &path, me);
                ev.extend(we_sink_cue(&g, 35.0, [130.0, 0.0, 0.0], 3, me));
                ev.extend(we_move_cue(&g, 4.0, [-150.0, 0.0, 0.0], 1, me));
                ev.extend(we_settle_cue(&g, 39.0, [130.0, 0.0, 0.0], me));
                ev.extend(we_caught_cues(19.0, 28.0));
                for (t, a) in &ev {
                    let end = (path.runs().last().unwrap().tail_in + 8.0).max(48.0);
                    assert!(*t >= 0.0 && f64::from(*t) < end, "{t} past {end}");
                    if let Act::Sound { volume, pitch, event, .. } = a {
                        assert!(*volume > 0.0 && *volume <= 1.0, "{event} {volume}");
                        assert!((0.5..=2.0).contains(pitch), "{event} {pitch}");
                    }
                }
            }
        }
    }

    /// The default show's cues land at the sheet's times: the sign peaks as the breach's blow is heard, the quake
    /// ahead of it through the ground, the bellow on its jaws, the dive ending on the bite, the bite as heard, the
    /// tail out and in as heard; near (250) and far (800) cross-faded.
    #[test]
    fn we_sounds_default_show_on_the_sheet() {
        for d in [250.0, 800.0] {
            let (g, me) = scene(d);
            let c = sounds(&we_cues(&g, &we_default_plan(&g), me));
            let d_d = d.hypot(260.0);
            let near = |t: f64, want: f64, what: &str| assert!((t - want).abs() < 0.03, "{what} at {d}: {t} not {want}");
            let sp = (SIGN_PEAK / (WE_BREACH + d / 343.0 - HIT_AT - SIGN_HOLE)).clamp(1.0, 1.2);
            near(first(&c, "sign").0, (WE_BREACH + d / 343.0 - HIT_AT - SIGN_HOLE - SIGN_PEAK / sp).max(0.0), "sign");
            near(first(&c, "quake1").0, WE_BREACH + d / 343.0 - HIT_AT, "quake1");
            let bc = c.iter().find(|e| e.1.starts_with("breach_burst_k1")).expect("the burst");
            let tk = &bc.1[13..16];
            near(bc.0, WE_BREACH + d / 343.0 - burst_step(tk), "breach");
            let sky = d.hypot(250.0);
            near(c.iter().find(|e| e.1.starts_with(&format!("bellow_{WE_BELLOW_TAKE}"))).expect("the bellow").0, WE_BELLOW.0 - BELLOW_LEAD + (sky / 343.0).min(0.6), "bellow");
            near(first(&c, "dive").0 + DIVE_HIT + PRE_HOLE, WE_BITE + d_d / 343.0, "dive's end");
            let bn = format!("{}{}", if WE_CLOSE_TIERS && d_d < 450.0 { "bite_mid" } else if d < 300.0 { "bite_c" } else { "bite_c_far" }, if WE_VOICE && WE_CLOSE_TIERS { "_dk" } else { "" });
            near(first(&c, &bn).0, WE_BITE + d_d / 343.0 - HIT_AT, "bite");
            near(first(&c, &format!("tail_{WE_TAIL_TAKE}")).0, WE_TAIL_OUT - TAIL_AT + d / 343.0, "tail out");
            near(first(&c, "tail_in").0, WE_TAIL_IN - HIT_AT + d_d / 343.0, "tail in");
            // (round 12: the burst at full, its tiers summing to the breach's loudness; the beds under it; the body
            // pouring from the bite to the tail)
            let burst_v: f64 = c.iter().filter(|e| e.1.starts_with("breach_burst_k1")).map(|e| e.2).sum();
            assert!(burst_v >= vol_big(d) - 0.05, "{burst_v}");
            assert!(first(&c, "rise").1 <= 0.4 * burst_v, "the rise a bed under the burst");
            let bodies: Vec<f64> = c.iter().filter(|e| e.1.starts_with("body")).map(|e| e.0).collect();
            let late = d_d / 343.0;
            assert!(bodies.len() >= 3 && bodies[0] - late < WE_BITE + 1.0 && *bodies.last().unwrap() - late > WE_TAIL_IN - 6.0, "{bodies:?}");
            let bellows: std::collections::BTreeSet<u64> = c.iter().filter(|e| e.1.starts_with("bellow_")).map(|e| e.0.to_bits()).collect();
            assert_eq!(bellows.len(), 1, "one bellow (near and far together)");
            assert_eq!(c.iter().filter(|e| e.1 == "sign").count(), 1);
        }
    }

    /// The three-arch chain: a different breach for each surfacing, the short sign before the later ones, the bellow
    /// on the one that holds, the hop's landing smaller (another take, higher) than the big bite; and the tunnel's
    /// rings never the same variant twice running, all six in six.
    #[test]
    fn we_sounds_chain_varies() {
        let (g, me) = scene(300.0);
        let c = sounds(&we_cues(&g, &we_plan3(&g), me));
        // (one burst a surfacing: the hop's on the small ones, a dynamite variation on the big one)
        let mut breaches: Vec<(f64, String)> = Vec::new();
        // (the steps as heard: not the thuds on the landings)
        let steps: Vec<f64> = we_plan3(&g).arches.iter().map(|a| a.t_out + dist(&g, a.from, me) / V_AIR).collect();
        for e in c.iter().filter(|e| e.1.starts_with("breach_burst_") && steps.iter().any(|s| (s - e.0 - burst_step(&e.1[13..16])).abs() < 0.06)) {
            if breaches.last().is_none_or(|p| (p.0 - e.0).abs() > 1e-6) {
                breaches.push((e.0, e.1[13..16].to_string()));
            }
        }
        assert_eq!(breaches.iter().map(|b| b.1.as_str()).collect::<Vec<_>>().len(), 3, "{breaches:?}");
        // (round 12: a K1 burst at every breach, a different one each time)
        assert!(breaches.iter().all(|b| b.1.starts_with("k1")), "{breaches:?}");
        assert!(breaches[0].1 != breaches[1].1 && breaches[1].1 != breaches[2].1, "{breaches:?}");
        assert_eq!(c.iter().filter(|e| e.1 == "sign").count(), 1);
        assert_eq!(c.iter().filter(|e| e.1 == "sign_short").count(), 2);
        assert_eq!(c.iter().filter(|e| e.1.starts_with("bellow_") && !e.1.ends_with("_far")).count(), 1);
        let landings: Vec<(String, f64)> = c.iter().filter(|e| (e.1.starts_with("bite_") || e.1.starts_with("land")) && !e.1.contains("_far")).map(|e| (e.1.clone(), e.3)).collect();
        assert_eq!(landings.len(), 3, "{landings:?}");
        assert!(landings[1].0.starts_with("bite_"), "{landings:?}");
        assert!(landings[0].0.starts_with("land") && landings[2].0.starts_with("land"), "{landings:?}");
        assert!(landings[0] != landings[2], "{landings:?}");
        for count in [3u32, 6] {
            for seed in [0u32, 1, 37, 1000] {
                let v: Vec<u32> = (0..12).map(|r| sink_variant(seed, r, count)).collect();
                assert!(v.windows(2).all(|w| w[0] != w[1]), "{v:?}");
                assert_eq!(v[..count as usize].iter().collect::<std::collections::BTreeSet<_>>().len(), count as usize, "{v:?}");
            }
        }
        let rings: Vec<String> = (0..8)
            .flat_map(|r| sounds(&we_sink_cue(&g, 31.0 + f64::from(r), [32.0 * f64::from(r), 0.0, 0.0], r, me)))
            .map(|e| e.1)
            .collect();
        assert_eq!(rings.len(), 8);
        assert!(rings.windows(2).all(|w| w[0] != w[1]), "{rings:?}");
    }

    /// The catch: the gulp's close on the jaws, the throat laid back to back through the inside, the spit on time,
    /// every outside sound stopped as the jaws meet, never the catch's own.
    #[test]
    fn we_sounds_caught() {
        let ev = we_caught_cues(19.0, 35.0);
        let c = sounds(&ev);
        assert!((first(&c, WE_GULP).0 + GULP_SHUT - 19.0).abs() < 1e-3);
        assert!((first(&c, "spit").0 + SPIT_AT - 35.0).abs() < 1e-3);
        let throats: Vec<f64> = c.iter().filter(|e| e.1.starts_with("throat_")).map(|e| e.0).collect();
        assert_eq!(throats.len(), 2);
        assert!((throats[1] - throats[0] - THROAT_LEN).abs() < 1e-3);
        for tk in ["a", "b", "c", "d"] {
            assert!((len_of(&format!("throat_{tk}")) - THROAT_LEN).abs() < 0.01);
        }
        let stops = ev.iter().filter(|e| (e.0 - 19.02).abs() < 1e-3 && matches!(e.1, Act::Cmd(_))).count();
        assert_eq!(stops, WE_FILES.iter().filter(|n| !inside(n)).count());
        assert!(!ev.iter().any(|e| matches!(&e.1, Act::Cmd(s) if s.contains(".gulp") || s.ends_with(".spit") || s.ends_with(".spit_rv"))));
        // (the throat stopped only once out, under the spit)
        let cut: Vec<f32> = ev.iter().filter(|e| matches!(&e.1, Act::Cmd(s) if s.contains("throat"))).map(|e| e.0).collect();
        assert_eq!(cut.len(), 1);
        assert!(f64::from(cut[0]) > 35.0 - SPIT_AT && f64::from(cut[0]) < 35.0);
    }

    /// A path built an arch at a time as a hunt would (each arch's cues on its append, the last tails at the end)
    /// cues every tail exactly once, at the times the whole path's schedule gives, the same as `we_cues` on it.
    #[test]
    fn we_sounds_tails_settle_on_append() {
        let (g, me) = scene(300.0);
        let full = we_plan3(&g);
        let mut ev = Vec::new();
        for k in 0..full.arches.len() {
            let mut part = full.clone();
            part.arches.truncate(k + 1);
            ev.extend(we_arch_cues(&g, &part, k, me));
        }
        ev.extend(we_last_tails(&g, &full, me));
        let tails = |c: &[(f64, String, f64, f64)]| -> Vec<(String, u64)> {
            let mut v: Vec<(String, u64)> = c.iter().filter(|e| e.1.starts_with("tail_")).map(|e| (e.1.clone(), (e.0 * 100.0).round() as u64)).collect();
            v.sort();
            v
        };
        let built = tails(&sounds(&ev));
        let whole = tails(&sounds(&we_cues(&g, &full, me)));
        assert_eq!(built.len(), 2 * full.arches.len(), "{built:?}");
        assert_eq!(built, whole);
        for (r, tun) in full.runs().iter().zip(0..) {
            let d = dist(&g, full.arches[tun].from, me);
            assert!(built.iter().any(|e| e.0.starts_with("tail_") && e.0 != "tail_in" && (e.1 as f64 / 100.0 - (r.tail_out - TAIL_AT + d / 343.0)).abs() < 0.02));
        }
    }

    /// The wormsign follows every run: the long sign into the first breach; on a long run the mound's pieces from a
    /// second after the dive up to the short sign into the next breach, each placed at the mound; on a short run only
    /// the short sign, quickened to fit.
    #[test]
    fn we_sounds_sign_follows_each_run() {
        let (g, me) = scene(300.0);
        let d0 = g.dir;
        let a1 = [d0[0] * 150.0, 0.0, d0[1] * 150.0];
        let b0 = [a1[0] + d0[1] * 420.0, 0.0, a1[2] - d0[0] * 420.0];
        let b1 = [b0[0] + d0[0] * 200.0, 0.0, b0[2] + d0[1] * 200.0];
        let mut path = WePath::new(g.dir);
        path.push([0.0; 3], a1, 90.0, 9.0, 120.0, 12.0, 120.0, None);
        let (_, late) = path.next_window(b0, 120.0).expect("a window");
        path.push(b0, b1, 200.0, late, 120.0, late + 4.0, 130.0, None);
        let c = sounds(&we_cues(&g, &path, me));
        assert_eq!(c.iter().filter(|e| e.1 == "sign").count(), 1);
        let moves: Vec<f64> = c.iter().filter(|e| e.1.starts_with("move")).map(|e| e.0).collect();
        let run = we_tunnels(&path)[1];
        assert!(!moves.is_empty() && moves.len() as f64 >= ((run.head_out - run.head_in - 6.0) / 3.0).floor(), "{moves:?} over {run:?}");
        assert!(moves[0] >= run.head_in + 0.9 && *moves.last().unwrap() < run.head_out, "{moves:?}");
        assert!(moves.windows(2).all(|w| (w[1] - w[0] - 3.0).abs() < 0.3));
        let short = first(&c, "sign_short");
        assert!(short.0 > moves[moves.len() - 1] - 3.0);
        // (the plan3 hop's runs are short: the short sign quickened, no pieces)
        let c3 = sounds(&we_cues(&g, &we_plan3(&g), me));
        assert!(!c3.iter().any(|e| e.1.starts_with("move")));
        assert!(c3.iter().filter(|e| e.1 == "sign_short").all(|e| e.3 > 1.0 && e.3 <= 1.6001));
    }

    /// The voice's plan (round 8, off until its files are in): every emergence take in turn, never the same twice
    /// running, for any seed; the planned names unique.
    #[test]
    fn we_sounds_voice_plan() {
        for seed in [0u32, 1, 2, 3, 37, 1000] {
            for near in [false, true] {
                let v: Vec<&str> = (0..12).map(|k| voice_emerge_take(seed, k, near)).collect();
                assert!(v.windows(2).all(|w| w[0] != w[1]), "{v:?}");
                let n = if near { 2 } else { 3 };
                assert_eq!(v[..n].iter().collect::<std::collections::BTreeSet<_>>().len(), n);
            }
        }
        let f = voice_files();
        assert_eq!(f.iter().collect::<std::collections::BTreeSet<_>>().len(), f.len());
        if WE_VOICE {
            for name in &f {
                assert!(len_of(name) > 0.5, "{name}");
            }
        }
    }
}
