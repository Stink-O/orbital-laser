//! The Supervolcano's sounds: what plays when, as tools/sounds_volcano.py builds them (its notes say what each is).
//! Everything from the vent is late by the distance (343 blocks a second); what comes through the ground, five times
//! sooner. The player may well fly in a strike this long, so the plan asks where they are as each part comes due (the
//! tremor, the eruption, the collapse), rather than once as it fires.

use super::{Act, Plan, mh, sound_from};

// ---- the beats (BEATS.md, volcano.rs's): keep in step ------------------------------------------------------------------
const VC_HIT: f32 = 2.0;
const VC_CRACK: f32 = 8.0;
const VC_ERUPT: f32 = 12.0;
const VC_BOMBS: f32 = 13.0;
const VC_LIGHT: f32 = 20.0;
const VC_COLLAPSE: f32 = 44.0;
const VC_LIFT: f32 = 60.0;
const VC_LEN: f32 = 80.0;
/// Where the flow sets off from, and where it has got to when it lifts.
const VC_RING: f64 = 280.0;
const VC_REACH: f64 = 989.0;

// ---- the files (tools/sounds_volcano.py): keep in step -----------------------------------------------------------------
/// flow_rise1-3's lengths: each ends on the hit.
const VC_RISES: [f32; 3] = [3.4, 7.0, 13.0];
/// flow_in1-2's lengths.
const VC_INS: [f32; 2] = [22.0, 12.0];
/// The silence at the start of the report's and the hit's files.
const VC_LEAD: f32 = 0.02;
/// The land mass dropping, into `collapse`.
const VC_DROP: f32 = 3.0;
const VC_AFTER_AT: f32 = 57.5;
const VC_PATTER_AT: f32 = 59.0;
/// bolt_far's length, whistle1-3's.
const VC_BOLT_FAR: f32 = 5.0;
const VC_WHISTLES: [f32; 3] = [3.2, 4.2, 2.6];

const GROUND_V: f64 = 1715.0;
/// How far off a bomb's own landing, or the trees and rock in the flow's front, can be heard at all: the rest is only
/// thumps and the roar. Nothing small carries hundreds of blocks.
const NEAR: f64 = 230.0;

fn ev(name: &str) -> String {
    format!("orbital:supervolcano.{name}")
}
/// A sound at the player's ears.
fn play(p: &mut Plan, t: f32, name: &str, volume: f64, pitch: f32) {
    p.ev.push((t, Act::Sound { event: ev(name), at: None, volume: volume.clamp(0.0, 1.0) as f32, pitch }));
}
/// A sound at a place, fading with the distance as the game's own do (256 blocks: sounds.json).
fn play_at(p: &mut Plan, t: f32, name: &str, at: [f64; 3], pitch: f32) {
    p.ev.push((t, Act::Sound { event: ev(name), at: Some(at), volume: 1.0, pitch }));
}

/// Where the player is now, or was if the game can't say.
fn live(me: [f64; 3]) -> [f64; 3] {
    crate::sdk::game::get_player().map_or(me, |p| [p.x, p.y, p.z])
}
fn ground_dist(a: [f64; 3], b: [f64; 3]) -> f64 {
    (a[0] - b[0]).hypot(a[2] - b[2])
}

/// How much of what comes from the vent is its `_far` file at `d` blocks (the rest the near one): none within 550, all
/// past 1,150. The two are the same sound, so they cross-fade by power.
fn far_share(d: f64) -> f64 {
    let u = ((d - 550.0) / 600.0).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}
/// How loud the vent is at `d` blocks: all of it within 500, 2.4 dB down each time the distance doubles. Something this
/// size carries.
fn air(d: f64) -> f64 {
    (500.0 / d.max(500.0)).powf(0.4)
}
fn near_far(p: &mut Plan, t: f32, name: &str, d: f64) {
    let f = far_share(d);
    if f < 1.0 {
        play(p, t, name, air(d) * (1.0 - f).sqrt(), 1.0);
    }
    if f > 0.0 {
        play(p, t, &format!("{name}_far"), air(d) * f.sqrt(), 1.0);
    }
}

/// The flow's front, its distance from the vent `t` s into the strike: 60 blocks a second at the ring, easing to 25, at
/// r=500 by about 48 s. Keep in step with volcano.rs's.
fn front_r(t: f32) -> f64 {
    let u = f64::from(t - VC_COLLAPSE).max(0.0);
    (VC_RING + 25.0 * u + 420.0 * (1.0 - (-u / 12.0).exp())).min(VC_REACH + 1.0)
}
/// When the front reaches `d` blocks out, if it does before the flow lifts.
fn front_at(d: f64) -> Option<f32> {
    if d > VC_REACH {
        return None;
    }
    let mut t = VC_COLLAPSE;
    while front_r(t) < d && t < VC_LIFT {
        t += 0.05;
    }
    Some(t)
}

/// A take of `count` that isn't the last one played.
fn take(last: &mut u32, count: u32, h: f64) -> u32 {
    let mut k = (h * f64::from(count)) as u32 % count + 1;
    if k == *last {
        k = k % count + 1;
    }
    *last = k;
    k
}

/// A bomb landing.
pub(super) struct Bomb {
    pub t: f32,
    pub x: f64,
    pub z: f64,
    pub size: f64,
}
/// Where and when the bombs land, off the vent. (The pass's own would do better, if volcano.rs lists them.)
pub(super) fn vc_bombs(s: u32) -> Vec<Bomb> {
    (0..64u32)
        .map(|i| {
            let (a, r) = (mh(i, s, 0xb1) * std::f64::consts::TAU, 130.0 + 520.0 * mh(i, s, 0xb2).powf(1.7));
            Bomb { t: VC_BOMBS + 3.0 + 16.0 * mh(i, s, 0xb3) as f32, x: a.cos() * r, z: a.sin() * r, size: 0.4 + 0.6 * mh(i, s, 0xb4) }
        })
        .collect()
}
/// Plume lightning: strokes in bursts, each (t, x, y, z) off the vent, from `from` to `to` s in the strike.
pub(super) fn vc_strokes(s: u32, from: f32, to: f32) -> Vec<(f32, [f64; 3])> {
    let mut out = Vec::new();
    let (mut t, mut b) = (from, 0u32);
    while t < to {
        let n = 2 + (mh(b, s, 0xc1) * 5.0) as u32;
        for i in 0..n {
            let k = b * 16 + i;
            let (a, r) = (mh(k, s, 0xc2) * std::f64::consts::TAU, 30.0 + 240.0 * mh(k, s, 0xc3));
            out.push((t + 0.9 * mh(k, s, 0xc4) as f32, [a.cos() * r, 280.0 + 800.0 * mh(k, s, 0xc5), a.sin() * r]));
        }
        t += 1.0 + 2.8 * mh(b, s, 0xc6) as f32;
        b += 1;
    }
    out.sort_by(|a, b| a.0.total_cmp(&b.0));
    out
}

/// One flurry of `vc_strokes` heard at `me`: late by the distance, the near ones `bolt` and the rest a stutter of
/// `bolt_far`, those within 0.16 s of each other one stroke (a flam's no use here: they're many strokes close together
/// already, in each file). `after` drops what would be heard after it, `quiet` lets all of it down.
fn thunder(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3], strokes: &[(f32, [f64; 3])], after: f32, quiet: f64) {
    let mut heard: Vec<(f32, f64, u32)> = strokes
        .iter()
        .enumerate()
        .map(|(i, (t, o))| {
            let (late, d) = sound_from([vent[0] + o[0], vent[1] + o[1], vent[2] + o[2]], me);
            (*t + late, d, i as u32)
        })
        .collect();
    heard.sort_by(|a, b| a.0.total_cmp(&b.0));
    let (mut last_near, mut last_far, mut prev) = (0u32, 0u32, f32::MIN);
    for (at, d, i) in heard {
        if at - prev < 0.16 || at > after {
            continue;
        }
        prev = at;
        let pitch = 0.9 + 0.2 * mh(i, s, 0xc7) as f32;
        let v = quiet * (0.55 + 0.45 * mh(i, s, 0xc8));
        if d < 950.0 {
            let k = take(&mut last_near, 4, mh(i, s, 0xc9));
            play(p, at, &format!("bolt{k}"), v * (620.0 / d.max(620.0)).powf(1.4), pitch);
        } else {
            let k = take(&mut last_far, 4, mh(i, s, 0xca));
            play(p, at, &format!("bolt_far{k}"), v * (1200.0 / d.max(1200.0)).powf(0.8), pitch);
        }
    }
}

/// The dread: the tremor out of the ground, stone creaking and cracking under the player (they fade with no distance:
/// it is the ground they stand on, though it carries less the further they are).
fn underfoot(p: &mut Plan, s: u32, d: f64) {
    play(p, VC_HIT + (d / GROUND_V) as f32, "tremor", 1.0, 1.0);
    let g = 1.0 / (1.0 + d / 2500.0);
    let (mut t, mut n, mut c, mut k) = (4.1f32, 0u32, 0u32, 0u32);
    while t < VC_ERUPT - 0.2 {
        let u = f64::from((t - 4.0) / (VC_ERUPT - 4.0));
        if u > 0.3 && mh(n, s, 0xa1) < 0.2 + 0.45 * u {
            let v = take(&mut c, 4, mh(n, s, 0xa2));
            play(p, t, &format!("crack{v}"), g * (0.3 + 0.7 * u) * (0.6 + 0.4 * mh(n, s, 0xa3)), 0.85 + 0.25 * mh(n, s, 0xa4) as f32);
        } else {
            let v = take(&mut k, 4, mh(n, s, 0xa5));
            play(p, t, &format!("creak{v}"), g * (0.35 + 0.65 * u) * (0.6 + 0.4 * mh(n, s, 0xa6)), 0.8 + 0.35 * mh(n, s, 0xa7) as f32);
        }
        t += (1.5 - 1.15 * u.sqrt()) as f32 * (0.6 + 0.8 * mh(n, s, 0xa8) as f32);
        n += 1;
    }
}

/// Bombs landing, off the vent at `vent`: within `NEAR` of the player a whistle and a real impact where it lands, past
/// that only a dull thump, and only the bigger ones the further off they are.
fn bombs(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3]) {
    let (mut wh, mut th, mut far, mut prev) = (0u32, 0u32, 0u32, f32::MIN);
    for (i, b) in vc_bombs(s).iter().enumerate() {
        let i = i as u32;
        let at = [vent[0] + b.x, vent[1], vent[2] + b.z];
        let (late, d) = sound_from(at, me);
        let pitch = 0.85 + 0.3 * mh(i, s, 0xb5) as f32;
        if d < NEAR {
            let v = take(&mut wh, 3, mh(i, s, 0xb6));
            // (the whistle is high in the air and moving, so it's heard at once, not late)
            play_at(p, b.t - VC_WHISTLES[v as usize - 1], &format!("whistle{v}"), at, 1.0);
            let v = take(&mut th, 4, mh(i, s, 0xb7));
            play_at(p, b.t + late, &format!("thud{v}"), at, pitch);
        } else {
            let at = b.t + late;
            let v = b.size * (1.0 - (d - NEAR) / 1000.0);
            if v > 0.2 && at - prev > 0.3 {
                prev = at;
                let k = take(&mut far, 3, mh(i, s, 0xb8));
                play(p, at, &format!("thud_far{k}"), v, pitch);
            }
        }
    }
}

/// The flow, for a player `d` blocks out along the ground: hit, or left out past where it stops.
fn flow(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3], d: f64) -> Option<f32> {
    let Some(hit) = front_at(d) else {
        // (past its reach: a dark rush coming and ebbing away, no hit)
        let late = (d / 343.0) as f32;
        play(p, VC_COLLAPSE + 2.0 + late, "flow_far", (1200.0 / d.max(1200.0)).powf(0.7), 1.0);
        return None;
    };
    // (the first the player can hear of it: the ring's sound, come across the land)
    let heard = VC_COLLAPSE + ((d - VC_RING).max(0.0) / 343.0) as f32;
    if let Some(k) = (0..VC_RISES.len()).rev().find(|k| hit - VC_RISES[*k] >= heard) {
        play(p, hit - VC_RISES[k], &format!("flow_rise{}", k + 1), 1.0, 1.0);
    }
    // (trees and rock in the front, only as it gets close: where along the front the sound comes from wanders a little)
    let (dx, dz) = ((me[0] - vent[0]) / d.max(1.0), (me[2] - vent[2]) / d.max(1.0));
    let (mut t, mut n, mut sp, mut gr) = (VC_COLLAPSE + 0.5, 0u32, 0u32, 0u32);
    while t < hit - 0.1 {
        let (r, side) = (front_r(t), 170.0 * (mh(n, s, 0xd1) - 0.5));
        let gap = d - r;
        if gap < NEAR {
            let at = [vent[0] + dx * r - dz * side, vent[1], vent[2] + dz * r + dx * side];
            let late = t + (gap.hypot(side) / 343.0) as f32;
            if mh(n, s, 0xd2) < 0.72 {
                let k = take(&mut sp, 3, mh(n, s, 0xd3));
                play_at(p, late, &format!("splinter{k}"), at, 0.85 + 0.3 * mh(n, s, 0xd4) as f32);
            } else {
                let k = take(&mut gr, 2, mh(n, s, 0xd5));
                play_at(p, late, &format!("grind{k}"), at, 0.85 + 0.3 * mh(n, s, 0xd6) as f32);
            }
        }
        t += 0.3 + 0.5 * mh(n, s, 0xd7) as f32;
        n += 1;
    }
    play(p, hit - VC_LEAD, "flow_hit", 1.0, 1.0);
    // (the hit is the loudest thing there is for a moment: under it the jet's top goes, so nothing but the inside is left)
    for name in ["column", "column_far"] {
        p.ev.push((hit + 0.05, Act::Cmd(format!("stopsound @s * {}", ev(name)))));
    }
    let k = usize::from(hit + VC_INS[0] > 78.0);
    play(p, hit + 0.1, &format!("flow_in{}", k + 1), 1.0, 1.0);
    Some(hit)
}

/// The Supervolcano's sounds, on plan `p`: the vent at `vent`, the player at `me` as it fires, `s` its seed.
pub(super) fn vc_sounds(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3]) {
    // ---- the beam: almost nothing, the tick at the hit late by the distance, then silence that feels wrong
    play(p, 0.0, "beam", 1.0, 1.0);
    p.later(VC_HIT - 0.1, move |q| {
        let me = live(me);
        let (late, d) = sound_from(vent, me);
        play(q, VC_HIT + late, "tick", (800.0 / d.max(800.0)).powf(1.4), 1.0);
        underfoot(q, s, d);
    });
    // ---- the ring cracks: steam, only near
    p.later(VC_CRACK - 0.1, move |q| {
        let (late, d) = sound_from(vent, live(me));
        let u = ((800.0 - d) / 280.0).clamp(0.0, 1.0);
        if u > 0.0 {
            play(q, VC_CRACK + late, "steam", u * u * (3.0 - 2.0 * u), 1.0);
        }
    });
    // ---- the eruption: the report and the column, one moment late by the distance; the bombs and the lightning on it
    p.later(VC_ERUPT - 0.1, move |q| {
        let me = live(me);
        let (late, d) = sound_from(vent, me);
        near_far(q, VC_ERUPT + late - VC_LEAD, "report", d);
        play(q, VC_ERUPT + late - VC_LEAD, "report_sub", air(d), 1.0);
        near_far(q, VC_ERUPT + late, "column", d);
        bombs(q, s, vent, me);
        let strokes = vc_strokes(s, VC_LIGHT, VC_COLLAPSE);
        thunder(q, s, vent, me, &strokes, f32::MAX, 1.0);
    });
    // ---- the collapse, the flow, what's left
    p.later(VC_COLLAPSE - 0.1, move |q| {
        let me = live(me);
        let (late, d) = sound_from(vent, me);
        near_far(q, VC_COLLAPSE + late, "collapse", d);
        play(q, VC_COLLAPSE + late + VC_DROP - VC_LEAD, "report_sub", air(d), 0.8);
        let hit = flow(q, s, vent, me, ground_dist(vent, me));
        // (lightning on in the ash, up in what's left of the column: from inside the flow nothing of it gets through)
        let strokes = vc_strokes(s ^ 0x5a5a, VC_COLLAPSE, VC_LIFT);
        thunder(q, s, vent, me, &strokes, hit.unwrap_or(VC_LIFT + 6.0), 0.7);
        play(q, VC_AFTER_AT, "after", 0.75 + 0.25 * air(d), 1.0);
        play(q, VC_PATTER_AT, "patter", (1800.0 / d.max(1800.0)).powf(2.0), 1.0);
        // (faint distant thunder, further and further between, each done before the strike is)
        let (mut t, mut n, mut k) = (64.0 + 2.0 * mh(0, s, 0xe1) as f32, 0u32, 0u32);
        while t < VC_LEN - VC_BOLT_FAR - 1.0 {
            let v = take(&mut k, 4, mh(n, s, 0xe2));
            play(q, t, &format!("bolt_far{v}"), 0.4 * (1.0 - f64::from(t - 64.0) / 14.0).max(0.25), 0.8 + 0.1 * mh(n, s, 0xe3) as f32);
            t += 3.5 + 3.0 * mh(n, s, 0xe4) as f32;
            n += 1;
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::Rng;

    fn plan_for_test() -> Plan {
        Plan { laser: &crate::lasers::LASERS[0], ev: Vec::new(), rng: Rng::new(7), bx: 0, by: 64, bz: 0 }
    }

    fn heard(z: f64) -> Vec<(f32, String, f32, f32, bool)> {
        let me = [0.5, 66.0, 0.5 + z];
        let mut p = plan_for_test();
        vc_sounds(&mut p, 41, [0.5, 65.0, 0.5], me);
        let mut ev = std::mem::take(&mut p.ev);
        let mut out = Vec::new();
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Later(job) => ev.extend(job()),
                Act::Sound { event, at, volume, pitch } => {
                    // (as the game plays a sound at a place: fading with the distance to nothing at 256 blocks)
                    let v = at.map_or(volume, |q| volume * (1.0 - ((q[0] - me[0]).hypot(q[2] - me[2]) / 256.0).min(1.0)) as f32);
                    out.push((t, event, v, pitch, at.is_some()));
                }
                Act::Cmd(c) => out.push((t, format!("stop {}", c.rsplit(' ').next().unwrap()), 0.0, 1.0, false)),
                _ => {}
            }
        }
        out.sort_by(|a, b| a.0.total_cmp(&b.0));
        out
    }

    #[test]
    fn vc_sound_report_is_late_by_the_distance() {
        for z in [500.0, 900.0, 1500.0] {
            let h = heard(z);
            let (late, _) = sound_from([0.5, 65.0, 0.5], [0.5, 66.0, 0.5 + z]);
            let t = h.iter().find(|e| e.1.contains(".report")).expect("the report").0;
            assert!((t - (12.0 + late - VC_LEAD)).abs() < 0.01, "{z}: {t}");
            let c = h.iter().find(|e| e.1.contains(".collapse")).expect("the collapse").0;
            assert!((c - (44.0 + late)).abs() < 0.01, "{z}: {c}");
            // (and nothing between the eruption and the report that would spoil the wait)
            assert!(!h.iter().any(|e| e.0 > 12.0 && e.0 < t - 0.05), "{z}: something plays in the wait");
        }
    }

    #[test]
    fn vc_sound_flow_is_heard_by_the_distance() {
        assert!((front_r(48.0) - 500.0).abs() < 8.0, "{}", front_r(48.0));
        let hit = |h: &[(f32, String, f32, f32, bool)]| h.iter().find(|e| e.1.contains(".flow_hit")).map(|e| e.0);
        let (near, far) = (heard(500.0), heard(1500.0));
        let t = hit(&near).expect("the hit");
        assert!((47.0..49.5).contains(&t), "{t}");
        assert!(near.iter().any(|e| e.1.contains("flow_in")), "inside it");
        assert!(near.iter().any(|e| e.1.starts_with("stop") && e.1.contains("column")), "the jet's top goes in the hit");
        assert!(!near.iter().any(|e| e.0 > t + 0.2 && e.0 < 60.0 && e.1.contains(".bolt")), "no lightning heard from inside");
        assert!(hit(&far).is_none(), "not this far out");
        assert!(far.iter().any(|e| e.1.contains("flow_far")), "the rush");
        // (nothing small carries: a splinter or a bomb's landing from afar is never heard)
        assert!(!far.iter().any(|e| e.1.contains(".splinter") || e.1.contains(".grind") || e.1.contains(".whistle")));
    }

    #[test]
    fn vc_sound_every_event_has_its_file_and_ends_in_time() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../orbital-sounds/assets/orbital");
        let events = std::fs::read_to_string(root.join("sounds.json")).unwrap();
        for z in [500.0, 620.0, 900.0, 1500.0, 2500.0] {
            for (t, event, v, pitch, _) in heard(z) {
                if let Some(name) = event.strip_prefix("orbital:supervolcano.") {
                    assert!(events.contains(&format!("\"supervolcano.{name}\"")), "{event} not in sounds.json");
                    assert!(root.join(format!("sounds/supervolcano/{name}.ogg")).exists(), "{event} has no file");
                    assert!((0.0..=1.0).contains(&v) && (0.5..=2.0).contains(&pitch), "{event}: {v} {pitch}");
                    let ends = |at: f32, len: f32| at + len <= VC_LEN + 0.01;
                    match name {
                        "after" => assert!(ends(t, 22.45), "{t}"),
                        "patter" => assert!(ends(t, 21.0), "{t}"),
                        "flow_in1" => assert!(ends(t, VC_INS[0]), "{t}"),
                        "flow_in2" => assert!(ends(t, VC_INS[1]), "{t}"),
                        n if n.starts_with("bolt_far") => assert!(ends(t, VC_BOLT_FAR / pitch), "{t}"),
                        _ => {}
                    }
                }
            }
        }
    }

    /// The plan's sounds as a timeline for tools/sounds_volcano.py's mixes: `t event volume pitch` a line, `t stop event` for
    /// a stopsound; VC_ME the player's distance from the vent, VC_OUT the file.
    #[test]
    #[ignore]
    fn vc_write_sounds() {
        let z: f64 = std::env::var("VC_ME").map_or(500.0, |v| v.parse().unwrap());
        let mut out = String::new();
        for (t, event, v, pitch, _) in heard(z) {
            match event.strip_prefix("stop ") {
                Some(e) => out += &format!("{t:.3} stop {e}\n"),
                None => out += &format!("{t:.3} {event} {v:.3} {pitch:.3}\n"),
            }
        }
        std::fs::write(std::env::var("VC_OUT").unwrap(), out).unwrap();
    }
}
