//! The Supervolcano's sounds: what plays when, as tools/sounds_volcano.py builds them (its notes say what each is).
//! Everything from the vent is late by the distance (343 blocks a second); what comes through the ground, five times
//! sooner. The one exception is the mount (2 to 17 s): all of it stops dead at the hush with the picture, wherever the
//! player is, so what plays then is on the strike's clock and ends by 17 s; the hush's own swell starts on that same
//! tick, and it and the jolt through the ground hold the wait until the report cuts them. The player may well fly in a strike this
//! long, so the plan asks where they are as each part comes due (the mount, the eruption, each bomb, the collapse),
//! rather than once as it fires. They are at least 1,000 blocks off as it fires; they can fly closer, so nothing here
//! breaks at any distance.

use std::cell::Cell;
use std::rc::Rc;

use super::{Act, Plan, mh, pcg, sound_from};

// ---- the beats (BEATS.md, volcano.rs's): keep in step ------------------------------------------------------------------
const VC_HIT: f32 = 2.0;           // the satellite's beam fires (volcano.wgsl's vc_opening)
const VC_CRACK: f32 = 6.0;
const VC_SWELL: f32 = 7.0;
const VC_HUSH: f32 = 17.0;
const VC_ERUPT: f32 = 18.0;
const VC_LIGHT: f32 = 26.0;
const VC_DARK: f32 = 36.0;
const VC_COLLAPSE: f32 = 50.0;
/// The flow comes out of the umbrella's foot about now.
const VC_FOOT: f32 = 56.0;
const VC_LIFT: f32 = 66.0;
const VC_RED: f32 = 80.0;
const VC_LEN: f32 = 88.0;
/// Where the flow sets off from, and how high over the land its wall stands (volcano.wgsl's nose, a little more).
const VC_RING: f64 = 280.0;
const VC_WALL: f64 = 300.0;
/// volcano.wgsl's VC_SPREAD, VC_HU.
const VC_SPREAD: f64 = 28.0;
const VC_HU: f64 = 1500.0;

// ---- the files (tools/sounds_volcano.py): keep in step -----------------------------------------------------------------
/// flow_rise1-3's lengths: each ends on the hit.
const VC_RISES: [f32; 3] = [6.0, 11.0, 17.0];
/// flow_in1-3's lengths.
const VC_INS: [f32; 3] = [14.0, 9.0, 5.0];
/// flow_far's.
const VC_FAR: f32 = 22.0;
/// The silence at the start of the report's and the hit's files.
const VC_LEAD: f32 = 0.02;
/// The report cuts `hush` and `seism` this long after it comes, under its front.
const VC_CUT: f32 = 0.05;
/// The land mass dropping, into `collapse`.
const VC_DROP: f32 = 3.0;
/// When `after` and `patter` start: both end at 87.8 s.
const VC_AFTER_AT: f32 = 66.3;
const VC_PATTER_AT: f32 = 70.3;
/// The longest of the Hurricane's thunder files this plays (its rolls run 8 s), whistle1-3's, rockfall1-3's; crack's and
/// the longest creak's.
const VC_ROLL: f32 = 8.0;
const VC_WHISTLES: [f32; 3] = [3.2, 4.2, 2.6];
const VC_ROCKFALLS: [f32; 3] = [3.2, 4.0, 4.8];
const VC_CRACK_LEN: f32 = 2.2;
/// `tick`'s length (tools/sounds_volcano.py's TICK_D).
const VC_TICK_LEN: f32 = 6.5;
const VC_CREAK_LEN: f32 = 2.4;

const GROUND_V: f64 = 1715.0;
/// How far off a bomb's own landing can be heard at all: past this only a thump. Nothing small carries hundreds of blocks.
const NEAR: f64 = 230.0;
/// How far off the stones a bomb throws up are heard.
const NEAR_STONES: f64 = 120.0;
/// How far off the trees and the rock in the flow's front are.
const NEAR_FRONT: f64 = 140.0;

fn ev(name: &str) -> String {
    format!("orbital:supervolcano.{name}")
}
/// A sound at the player's ears.
fn play(p: &mut Plan, t: f32, name: &str, volume: f64, pitch: f32) {
    p.ev.push((t, Act::Sound { event: ev(name), at: None, volume: volume.clamp(0.0, 1.0) as f32, pitch }));
}
/// A sound at a place, fading with the distance as the game's own do (256 blocks: sounds.json).
fn play_at(p: &mut Plan, t: f32, name: &str, at: [f64; 3], volume: f64, pitch: f32) {
    p.ev.push((t, Act::Sound { event: ev(name), at: Some(at), volume: volume.clamp(0.0, 1.0) as f32, pitch }));
}

/// Where the player is now, or was if the game can't say.
fn live(me: [f64; 3]) -> [f64; 3] {
    crate::sdk::game::get_player().map_or(me, |p| [p.x, p.y, p.z])
}

/// How much of what comes from the vent is its `_far` file at `d` blocks (the rest the near one): none within 500, all
/// past 1,700, about half at 1,000 where the strike fires. The two are the same sound, so they cross-fade by power.
fn far_share(d: f64) -> f64 {
    let u = ((d - 500.0) / 1200.0).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}
/// How loud the vent is at `d` blocks: all of it within 1,000, 2.4 dB down each time the distance doubles. Something
/// this size carries.
fn air(d: f64) -> f64 {
    (1000.0 / d.max(1000.0)).powf(0.4)
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

/// One of the big plates comes down at `t`, `at` in the world (strike/vc_lodge.rs): one heavy blow, late by the distance.
pub(super) fn plate_down(p: &mut Plan, t: f32, at: [f64; 3], me: [f64; 3], size: f64) {
    let m = live_rel(me, at);
    let (late, d) = sound_from(at, m);
    let big = (size / 22_000.0).clamp(0.4, 1.0);
    let k = (1.0 - d / 1800.0).clamp(0.15, 1.0);
    play(p, t + late, "plate_sub", 0.6 * big * k, 0.6 + 0.12 * (1.0 - big as f32));
    play(p, t + late, "thud_far1", 0.9 * k, 0.55 + 0.15 * (1.0 - big as f32));
    p.shake(t + late, (0.75 * big * (1.0 - d / 1100.0)).clamp(0.0, 0.8) as f32, 1.5);
}
/// Where the player is in the world, `me` from the vent under `at`'s if the game can't say.
fn live_rel(me: [f64; 3], at: [f64; 3]) -> [f64; 3] {
    crate::sdk::game::get_player().map_or([at[0] + me[0], at[1] + me[1], at[2] + me[2]], |p| [p.x, p.y, p.z])
}
/// How far the wall of ash has come from the middle at time `t` (volcano.wgsl's vc_front): 60 blocks a second at the
/// ring, slowing to 25.
fn front_r(t: f32) -> f64 {
    let c = f64::from(t - VC_COLLAPSE).max(0.0);
    VC_RING + 25.0 * c + 490.0 * (1.0 - (-c / 14.0).exp())
}
/// volcano.wgsl's vc_n1 and vc_lobes: the wall's fingers and clefts, so the hit is when the pass shows it reach the player.
fn n1(x: f64, per: u32, k: u32) -> f64 {
    let i = x.floor();
    let f = x - i;
    let u = f * f * (3.0 - 2.0 * f);
    let n = i as i32 as u32 % per;
    let (a, b) = (f64::from(pcg(n ^ k) & 0xffff) / 65535.0, f64::from(pcg(((n + 1) % per) ^ k) & 0xffff) / 65535.0);
    a + (b - a) * u
}
fn lobes(ang: f64, rho: f64) -> f64 {
    let u = (ang + std::f64::consts::PI + 0.00022 * rho + 0.2 * (rho * 0.0031).sin()) / std::f64::consts::TAU + 1.0;
    let n = 0.6 * n1(u * 9.0, 9, 0x71) + 0.28 * n1(u * 23.0, 23, 0x72) + 0.12 * n1(u * 61.0, 61, 0x73);
    let cl = n1(u * 17.0, 17, 0x74);
    let c = ((cl - 0.5).abs() / 0.16).clamp(0.0, 1.0);
    n - 0.5 - 0.3 * (1.0 - c * c * (3.0 - 2.0 * c))
}
/// When the wall reaches a place at `rho` from the vent, bearing `ang`, if it does with time left to play it.
pub(super) fn front_at(rho: f64, ang: f64) -> Option<f32> {
    let lob = lobes(ang, rho);
    let mut t = VC_COLLAPSE + 0.05;
    while t <= VC_LEN - VC_INS[2] - 0.2 {
        let rf = front_r(t);
        if rf - rho - (4.0 * (rf - VC_RING) + 30.0).min(520.0) * lob > 0.0 {
            return Some(t);
        }
        t += 0.05;
    }
    None
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

fn smooth(a: f64, b: f64, x: f64) -> f64 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}
/// The lightning, as volcano.wgsl's vc_flash has it, slot by slot, from `from` s up to `to`: each (time, where off the
/// vent, how bright, in the cloud's sheet). In the plume to begin with, out through the umbrella's rings, kilometres off,
/// from about 36 s.
fn flashes(s: u32, from: f32, to: f32) -> Vec<(f32, [f64; 3], f64, bool)> {
    const DT: f64 = 0.13;
    let (light, dark, collapse) = (f64::from(VC_LIGHT), f64::from(VC_DARK), f64::from(VC_COLLAPSE));
    let mut out = Vec::new();
    let mut slot = (f64::from(from) / DT).ceil() as u32;
    while slot as f64 * DT < f64::from(to) {
        let t = slot as f64 * DT;
        let k = slot;
        slot += 1;
        let on = smooth(light - 2.0, light + 8.0, t) * (1.0 - smooth(collapse + 10.0, f64::from(VC_RED), t));
        if mh(k, s, 0x901) > 0.62 * on + if t >= light { 0.03 * on } else { 0.0 } {
            continue;
        }
        let th = std::f64::consts::TAU * mh(k, s, 0x902);
        let cloud = mh(k, s, 0x903) < smooth(dark - 4.0, dark + 4.0, t);
        let p = if cloud {
            let u = (t - VC_SPREAD).max(0.0);
            let ru = 620.0 * smooth(0.0, 3.0, u) + 130.0 * u.powf(1.28);
            let r = (0.3 + 0.28 * (mh(k, s, 0x904) * 3.0).floor()) * ru.min(5200.0);
            [th.cos() * r, VC_HU - 90.0, th.sin() * r]
        } else {
            let hy = 380.0 + 1100.0 * mh(k, s, 0x905);
            let rr = VC_RING - 155.0 * smooth(0.0, 190.0, hy);
            let ww = 76.0 + 0.52 * hy.min(190.0) + 0.13 * (hy - 190.0).clamp(0.0, 330.0) + 0.24 * (hy - 520.0).max(0.0);
            let r = (rr + ww) * (0.75 + 0.2 * mh(k, s, 0x906));
            let a = (t - f64::from(VC_ERUPT)).max(0.0);
            let h = 130.0 + 270.0 * (1.0 - (-a / 3.0).exp()) + 1560.0 * (1.0 - (-(a - 4.0).max(0.0) / 7.5).exp());
            let c = (t - collapse).max(0.0);
            [th.cos() * r, hy.min((h - 13.0 * c * c - 8.0 * c).max(60.0)), th.sin() * r]
        };
        out.push((t as f32, p, 0.5 + 0.8 * mh(k, s, 0x908), cloud));
    }
    out
}

/// A bolt's thunder `d` blocks off as a file's loudest 400 ms in dB: strike/hurricane.rs's hu_thunder_db, 4 dB down each
/// time the distance doubles, 11 dB over it. This lightning is far bigger than an eyewall's, and is heard from a kilometre.
fn thunder_db(d: f64) -> f64 {
    -4.0 - 4.0 * (d.max(60.0) / 60.0).log2()
}

/// The lightning from `from` s up to `to` as heard at `me`, with the Hurricane's own thunder (its events, its files, and
/// the way strike/hurricane.rs's hu_thunder plays them: keep in step): a stroke in the plume by its distance, a crack
/// within 110 blocks, a duller clap to 320, mostly roll past it; a flash in the cloud's sheet a roll up in the cloud, half
/// of those unheard. Late by the distance; two within 0.2 s of each other are one clap (their power added, the nearer's
/// take); one while louder still rolls is let down a little; a kind's take is never one of its last two. Only what's
/// heard in `when` plays, and none of it between `mute`'s two times; `quiet` lets all of it down.
#[allow(clippy::too_many_arguments)]
fn thunder(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3], (from, to): (f32, f32), when: (f32, f32), mute: (f32, f32), quiet: f64) {
    let power = |d: f64, cloud: bool, k: f64| 10f64.powf((thunder_db(d) - if cloud { 6.0 } else { 0.0 }) / 10.0) * (quiet * k.min(1.0)).powi(2);
    let mut heard: Vec<(f32, f64, bool, f64, u32)> = flashes(s, from, to)
        .iter()
        .enumerate()
        .filter(|(i, f)| !f.3 || mh(*i as u32, s, 0xc1) >= 0.5)
        .map(|(i, (t, o, k, cloud))| {
            let (late, d) = sound_from([vent[0] + o[0], vent[1] + o[1], vent[2] + o[2]], me);
            (*t + late, d, *cloud, *k, i as u32)
        })
        .filter(|h| h.0 >= when.0 && h.0 < when.1.min(VC_LEN - VC_ROLL / 0.9) && (h.0 < mute.0 || h.0 > mute.1))
        .collect();
    heard.sort_by(|a, b| a.0.total_cmp(&b.0));
    // (the claps: when, the nearest's distance, a flash in the cloud or not, which, their power together)
    let mut claps: Vec<(f32, f64, bool, u32, f64, f64)> = Vec::new();
    for (at, d, cloud, k, i) in heard {
        let pw = power(d, cloud, k);
        match claps.last_mut() {
            Some(l) if at - l.0 < 0.2 => {
                if pw > l.5 {
                    (l.1, l.2, l.3, l.5) = (d, cloud, i, pw);
                }
                l.4 += pw;
            }
            _ => claps.push((at, d, cloud, i, pw, pw)),
        }
    }
    let mut recent: Vec<(&'static str, u32)> = Vec::new();
    let mut rolling: Vec<(f32, f64)> = Vec::new();
    for (at, d, cloud, i, pw, _) in claps {
        // (tools/sounds_hurricane.py's LEVEL for each kind)
        let (kind, level) = match (cloud, d) {
            (true, _) => ("rumble", -25.5),
            (false, d) if d < 110.0 => ("thunder", -14.0),
            (false, d) if d < 320.0 => ("thunder_mid", -17.5),
            (false, _) => ("thunder_far", -21.0),
        };
        let db = 10.0 * pw.log10();
        let loud = 10f64.powf(db / 20.0);
        let busy: f64 = rolling.iter().map(|(t, l)| l * (-f64::from(at - t).max(0.0) / 1.2).exp()).sum();
        let duck = (1.0 / (1.0 + 0.6 * busy / loud)).max(0.6);
        rolling.push((at, loud * duck));
        let last2: Vec<u32> = recent.iter().rev().filter(|(k, _)| *k == kind).take(2).map(|(_, v)| *v).collect();
        let free: Vec<u32> = (1..=4).filter(|v| !last2.contains(v)).collect();
        let take = free[((mh(i, s, 0xc9) * free.len() as f64) as usize).min(free.len() - 1)];
        recent.push((kind, take));
        let volume = (10f64.powf((db - level) / 20.0).min(1.0) * duck) as f32;
        p.ev.push((at, Act::Sound { event: format!("orbital:hurricane.{kind}{take}"), at: None, volume, pitch: 0.9 + 0.16 * mh(i, s, 0xc7) as f32 }));
    }
}

/// The mount, 2 to 17 s. Most of it comes through the ground, so reaches a player a long way off: the tremor (with the
/// land's lurches in it), and cracks, dull knocks by the time they get here. Falls of rock off its flanks and the lava
/// fountains come by the air, dark and low; stone creaking under the feet and the steam's hiss only for one who has
/// flown close. All of it on the strike's clock and over by the hush: not a thing rings on into it, whatever the distance.
fn mount(p: &mut Plan, s: u32, d: f64) {
    play(p, VC_HIT, "tremor", (1500.0 / d.max(1500.0)).sqrt(), 1.0);
    play(p, VC_SWELL, "fountain", (1000.0 / d.max(1000.0)).powf(1.2), 1.0);
    let steam = smooth(900.0, 520.0, d);
    if steam > 0.0 {
        play(p, VC_CRACK, "steam", steam, 1.0);
    }
    let (ground, close) = (1.0 - 0.75 * smooth(1500.0, 2600.0, d), 1.0 - smooth(500.0, 900.0, d));
    let (mut t, mut n, mut c, mut k) = (VC_CRACK + 0.2, 0u32, 0u32, 0u32);
    while t < VC_HUSH {
        let u = f64::from((t - VC_CRACK) / (VC_HUSH - VC_CRACK));
        let pitch = 0.85 + 0.25 * mh(n, s, 0xa4) as f32;
        if mh(n, s, 0xa1) < 0.55 + 0.3 * u {
            if t + VC_CRACK_LEN / pitch < VC_HUSH - 0.05 {
                let v = take(&mut c, 4, mh(n, s, 0xa2));
                play(p, t, &format!("crack{v}"), ground * (0.2 + 0.8 * u) * (0.6 + 0.4 * mh(n, s, 0xa3)), pitch);
            }
        } else if close > 0.0 && t + VC_CREAK_LEN / (0.8 * pitch) < VC_HUSH - 0.05 {
            let v = take(&mut k, 4, mh(n, s, 0xa5));
            play(p, t, &format!("creak{v}"), close * (0.35 + 0.65 * u) * (0.6 + 0.4 * mh(n, s, 0xa6)), 0.8 * pitch);
        }
        t += (1.3 - 0.8 * u.sqrt()) as f32 * (0.6 + 0.8 * mh(n, s, 0xa8) as f32);
        n += 1;
    }
    // (rock off the flanks, more of it as the mount steepens)
    let (mut t, mut n, mut last) = (VC_SWELL + 1.5, 0u32, 0u32);
    let gain = (1000.0 / d.max(1000.0)).powf(0.8);
    while t < VC_HUSH {
        let u = f64::from((t - VC_SWELL) / (VC_HUSH - VC_SWELL));
        let v = take(&mut last, 3, mh(n, s, 0xaa));
        let pitch = 0.85 + 0.2 * mh(n, s, 0xab) as f32;
        if t + VC_ROCKFALLS[v as usize - 1] / pitch < VC_HUSH - 0.05 {
            play(p, t, &format!("rockfall{v}"), gain * (0.45 + 0.55 * u) * (0.7 + 0.3 * mh(n, s, 0xac)), pitch);
        }
        t += (2.3 - 1.2 * u as f32) * (0.7 + 0.6 * mh(n, s, 0xad) as f32);
        n += 1;
    }
}

/// Bombs landing (`bombs`: when, and where off the vent), each worked out as it comes due, for wherever the player is by
/// then: within `NEAR` of them a tearing whistle, a real impact where it lands and, closer still, the stones it throws;
/// past that only a dull thump, and only the bigger ones the further off they are. (About a third of the bombs are thrown
/// to come down round the player: volcano.rs's vc_bombs.) Nothing whistles before the report has been heard.
fn land_bombs(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3], report: f32, bombs: &[(f32, f64, f64)]) {
    let prev = Rc::new(Cell::new(f32::MIN));
    let (mut wh, mut th, mut sp, mut far) = (0u32, 0u32, 0u32, 0u32);
    let mut order: Vec<usize> = (0..bombs.len()).collect();
    order.sort_by(|a, b| bombs[*a].0.total_cmp(&bombs[*b].0));
    for i in order {
        let (t, x, z) = bombs[i];
        let i = i as u32;
        let at = [vent[0] + x, vent[1], vent[2] + z];
        let (w, h, st, f) = (take(&mut wh, 3, mh(i, s, 0xb6)), take(&mut th, 4, mh(i, s, 0xb7)), take(&mut sp, 3, mh(i, s, 0xbb)), take(&mut far, 3, mh(i, s, 0xb8)));
        let flight = VC_WHISTLES[w as usize - 1];
        let prev = prev.clone();
        p.later((t - flight - 0.2).max(VC_ERUPT), move |q| {
            let (late, d) = sound_from(at, live(me));
            let pitch = 0.85 + 0.3 * mh(i, s, 0xb5) as f32;
            if d < NEAR {
                // (ending on its landing as the player hears that)
                if t + late - flight > report + 1.0 {
                    play_at(q, t + late - flight, &format!("whistle{w}"), at, 1.0, 1.0);
                }
                play_at(q, t + late, &format!("thud{h}"), at, 1.0, pitch);
                if d < NEAR_STONES {
                    play_at(q, t + late, &format!("spatter{st}"), at, 1.0 - d / NEAR_STONES, 0.9 + 0.2 * mh(i, s, 0xbc) as f32);
                }
            } else if t < VC_COLLAPSE {
                let (at, v) = (t + late, (0.4 + 0.6 * mh(i, s, 0xb4)) * (1.0 - (d - NEAR) / 1000.0));
                if v > 0.2 && at - prev.get() > 0.3 {
                    prev.set(at);
                    play(q, at, &format!("thud_far{f}"), v, pitch);
                }
            }
        });
    }
}

/// The flow, for the player `me`: when it hits them if it does, else the rush of it past where it stops, or below them.
/// The wall reaches 1,000 blocks at about 67 s and goes on spending itself: the later it comes, the less of a blow.
fn flow(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3], drop: f32) -> Option<f32> {
    let (dx, dz) = (me[0] - vent[0], me[2] - vent[2]);
    let d = dx.hypot(dz);
    let hit = if me[1] - vent[1] < VC_WALL { front_at(d, dz.atan2(dx)) } else { None };
    let Some(hit) = hit else {
        // (a dark rush coming and ebbing away, no hit)
        let at = (VC_FOOT + ((d - 1000.0).max(0.0) / 343.0) as f32).min(VC_LEN - VC_FAR);
        play(p, at, "flow_far", (1200.0 / d.max(1200.0)).powf(0.7), 1.0);
        return None;
    };
    let spent = 1.0 - 0.6 * smooth(68.0, 82.0, f64::from(hit));
    // (the first the player can hear of it: the ring's sound, come across the land; by the foot it is out in the open)
    let heard = (VC_COLLAPSE + ((d - VC_RING).max(0.0) / 343.0) as f32).min(VC_FOOT);
    if let Some(k) = (0..VC_RISES.len()).rev().find(|k| hit - VC_RISES[*k] >= heard) {
        play(p, hit - VC_RISES[k], &format!("flow_rise{}", k + 1), spent.sqrt(), 1.0);
    }
    // (trees and rock in the front, only as it gets close: where along the front the sound comes from wanders a little)
    let (ux, uz) = (dx / d.max(1.0), dz / d.max(1.0));
    let (mut t, mut n, mut sp, mut gr) = ((hit - 12.0).max(VC_COLLAPSE + 0.5), 0u32, 0u32, 0u32);
    while t < hit - 0.1 {
        let (gap, side) = (front_r(hit) - front_r(t), 170.0 * (mh(n, s, 0xd1) - 0.5));
        if gap < NEAR_FRONT {
            let r = d - gap;
            let at = [vent[0] + ux * r - uz * side, vent[1], vent[2] + uz * r + ux * side];
            let heard = t + (gap.hypot(side) / 343.0) as f32;
            let v = spent * (1.0 - gap / NEAR_FRONT).sqrt();
            if mh(n, s, 0xd2) < 0.72 {
                let k = take(&mut sp, 3, mh(n, s, 0xd3));
                play_at(p, heard, &format!("splinter{k}"), at, v, 0.85 + 0.3 * mh(n, s, 0xd4) as f32);
            } else {
                let k = take(&mut gr, 2, mh(n, s, 0xd5));
                play_at(p, heard, &format!("grind{k}"), at, v, 0.85 + 0.3 * mh(n, s, 0xd6) as f32);
            }
        }
        t += 0.3 + 0.5 * mh(n, s, 0xd7) as f32;
        n += 1;
    }
    // (under the collapse's thunder it needn't be as much: the two would be all the game's limiter heard)
    play(p, hit - VC_LEAD, "flow_hit", spent * (0.85 + 0.15 * smooth(6.0, 14.0, f64::from(hit - drop))), 1.0);
    // (the land's drop's sub holds for seconds: it goes as the hit lands (a stopsound is heard a tick late), so the two
    // never stack under the game's limiter; the report's own is long over by then)
    p.ev.push((hit - VC_LEAD - 0.05, Act::Cmd(format!("stopsound @s * {}", ev("report_sub")))));
    // (the hit is the loudest thing there is for a moment: under it the jet's top goes, so nothing but the inside is left)
    for name in ["column", "column_far"] {
        p.ev.push((hit + 0.05, Act::Cmd(format!("stopsound @s * {}", ev(name)))));
    }
    if let Some(k) = (0..VC_INS.len()).find(|k| hit + 0.1 + VC_INS[*k] <= VC_LEN) {
        play(p, hit + 0.1, &format!("flow_in{}", k + 1), 1.0, 1.0);
    }
    Some(hit)
}

/// The Supervolcano's sounds, on plan `p`: the vent at `vent`, the player at `me` as it fires, `s` the pass's seed (the
/// lightning is the pass's own, `flashes`), `bombs` when and where (off the vent) the pass's lava bombs land.
pub(super) fn vc_sounds(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3], bombs: Vec<(f32, f64, f64)>) {
    // ---- the satellite: its aim and charge on the strike's clock (`beam`, cut on the shot), the shot and the crust
    // seething under it late by the distance (`tick`), then the mount
    play(p, 0.0, "beam", 1.0, 1.0);
    p.later(VC_HIT - 0.1, move |q| {
        let (late, d) = sound_from(vent, live(me));
        // (the shot carries: heard however far off, so long as it's over by the hush, as everything of the mount is)
        if VC_HIT + late + VC_TICK_LEN < VC_HUSH - 0.05 {
            play(q, VC_HIT + late, "tick", (1000.0 / d.max(1000.0)).powf(1.3), 1.0);
        }
        mount(q, s, d);
    });
    // ---- the hush: every sound of the mount ends here of itself (`mount`), and whatever the game had playing goes with
    // them; in their place, on the same tick, the deep pressure swelling under the wait (`hush`), so it never goes silent
    p.later(VC_HUSH - 0.1, move |q| {
        q.ev.push((VC_HUSH - 0.05, Act::Cmd("stopsound @s music".into())));
        let (_, d) = sound_from(vent, live(me));
        play(q, VC_HUSH, "hush", (1500.0 / d.max(1500.0)).sqrt(), 1.0);
    });
    // ---- the eruption: first a jolt through the ground and the ground shaking on under the hush, the air's report and
    // the column long after it, one moment late by the distance, cutting the wait's sounds; the bombs and the lightning
    // on it
    p.later(VC_ERUPT - 0.1, move |q| {
        let me = live(me);
        let (late, d) = sound_from(vent, me);
        play(q, VC_ERUPT + (d / GROUND_V) as f32, "seism", (1500.0 / d.max(1500.0)).powf(0.7), 1.0);
        let report = VC_ERUPT + late;
        for name in ["hush", "seism"] {
            q.ev.push((report + VC_CUT, Act::Cmd(format!("stopsound @s * {}", ev(name)))));
        }
        near_far(q, report - VC_LEAD, "report", d);
        play(q, report - VC_LEAD, "report_sub", 0.55 * air(d), 1.0);
        near_far(q, report, "column", d);
        land_bombs(q, s, vent, me, report, &bombs);
        thunder(q, s, vent, me, (VC_LIGHT - 2.0, VC_COLLAPSE), (0.0, VC_COLLAPSE), (0.0, 0.0), 1.0);
    });
    // ---- the collapse, the flow, what's left
    // (the collapse's sounds worked out over three stages, ahead of it: the flow's schedule and each stretch of the thunder
    // walk the pass's flow and flashes, and a stage has to stay well under a tick)
    let heard: std::rc::Rc<std::cell::Cell<Option<f32>>> = Default::default();
    let h1 = heard.clone();
    p.later(VC_COLLAPSE - 0.6, move |q| {
        crate::meter::spend(8_000_000);
        let me = live(me);
        let (late, d) = sound_from(vent, me);
        near_far(q, VC_COLLAPSE + late, "collapse", d);
        let drop = VC_COLLAPSE + late + VC_DROP - VC_LEAD;
        let hit = flow(q, s, vent, me, drop);
        h1.set(hit);
        // (the land's drop, unless the flow's hit is on it: the two would be all the game's limiter heard; a little under
        // the report's, since its pressure holds on for seconds under the land falling and the flow closing)
        if hit.is_none_or(|h| (h - drop).abs() > 0.8) {
            play(q, drop, "report_sub", 0.5 * air(d), 0.8);
        }
    });
    // (the lightning goes on in the ash: from inside the flow, under its near-black, nothing of it gets through
    let h2 = heard.clone();
    p.later(VC_COLLAPSE - 0.4, move |q| {
        crate::meter::spend(8_000_000);
        let mute = h2.get().map_or((0.0, 0.0), |h| (h, h + 8.0));
        thunder(q, s, vent, live(me), (VC_LIGHT - 2.0, VC_LIFT), (VC_COLLAPSE, VC_LEN), mute, 0.8);
    });
    p.later(VC_COLLAPSE - 0.2, move |q| {
        crate::meter::spend(8_000_000);
        let me = live(me);
        let (_, d) = sound_from(vent, me);
        let mute = heard.get().map_or((0.0, 0.0), |h| (h, h + 8.0));
        thunder(q, s, vent, me, (VC_LIFT, VC_LEN), (VC_COLLAPSE, VC_LEN), mute, 0.45);
        play(q, VC_AFTER_AT, "after", 0.75 + 0.25 * air(d), 1.0);
        play(q, VC_PATTER_AT, "patter", (1800.0 / d.max(1800.0)).powf(2.0), 1.0);
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::Rng;

    fn plan_for_test() -> Plan {
        Plan { laser: &crate::lasers::LASERS[0], ev: Vec::new(), rng: Rng::new(7), bx: 0, by: 64, bz: 0 }
    }

    /// Where the pass's bombs land for a player at `rel` from the vent, as volcano_plan works them out.
    fn bombs(s: u32, rel: [f64; 3]) -> Vec<(f32, f64, f64)> {
        super::super::volcano::vc_bombs(s as f32, rel, &|_, _| 0.0)
            .iter()
            .map(|b| {
                let c = b.tl - b.t0;
                (b.tl as f32, b.p0[0] + b.v[0] * c, b.p0[2] + b.v[2] * c)
            })
            .collect()
    }

    fn heard(z: f64) -> Vec<(f32, String, f32, f32, bool)> {
        let me = [0.5, 66.0, 0.5 + z];
        let mut p = plan_for_test();
        vc_sounds(&mut p, 37, [0.5, 65.0, 0.5], me, bombs(37, [0.0, 1.0, z]));
        let mut ev = std::mem::take(&mut p.ev);
        let mut out = Vec::new();
        // (in time order, as the game plays them: a stage may use what an earlier one worked out)
        while !ev.is_empty() {
            ev.sort_by(|a, b| b.0.total_cmp(&a.0));
            let (t, a) = ev.pop().unwrap();
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

    /// `hush`'s and `seism`'s lengths (tools/sounds_volcano.py's HUSH_D, SEISM_D): long enough for a report heard from
    /// 3,000 blocks, which cuts both.
    const VC_HUSH_LEN: f32 = 12.0;
    const VC_SEISM_LEN: f32 = 10.0;

    /// How long each file lasts at pitch 1, for the checks on what ends when.
    fn len_of(name: &str) -> f32 {
        let take = |n: &str, list: &[f32]| n.parse::<usize>().ok().and_then(|k| list.get(k.wrapping_sub(1))).copied();
        match name {
            "tremor" => VC_HUSH - VC_HIT,
            "fountain" => VC_HUSH - VC_SWELL,
            "steam" => VC_HUSH - VC_CRACK,
            "tick" => VC_TICK_LEN,
            "hush" => VC_HUSH_LEN,
            "seism" => VC_SEISM_LEN,
            "after" => 21.5,
            "patter" => 17.5,
            "flow_far" => VC_FAR,
            n if n.starts_with("crack") => VC_CRACK_LEN,
            n if n.starts_with("creak") => VC_CREAK_LEN,
            n if n.starts_with("rockfall") => take(&n[8..], &VC_ROCKFALLS).unwrap(),
            n if n.starts_with("flow_in") => take(&n[7..], &VC_INS).unwrap(),
            n if n.starts_with("rumble") || n.starts_with("thunder") => VC_ROLL,
            _ => 0.0,
        }
    }

    #[test]
    fn vc_sound_report_is_late_by_the_distance() {
        for z in [1000.0, 1400.0, 2000.0] {
            let h = heard(z);
            let (late, _) = sound_from([0.5, 65.0, 0.5], [0.5, 66.0, 0.5 + z]);
            let t = h.iter().find(|e| e.1.contains(".report")).expect("the report").0;
            assert!((t - (VC_ERUPT + late - VC_LEAD)).abs() < 0.01, "{z}: {t}");
            let c = h.iter().find(|e| e.1.contains(".collapse")).expect("the collapse").0;
            assert!((c - (VC_COLLAPSE + late)).abs() < 0.01, "{z}: {c}");
            // (in the wait only the hush and the jolt through the ground, and the report cuts both)
            let s = h.iter().find(|e| e.1.contains(".seism")).expect("the seism").0;
            assert!((s - (VC_ERUPT + (z / GROUND_V) as f32)).abs() < 0.01, "{z}: {s}");
            let other = |e: &&(f32, String, f32, f32, bool)| !e.1.contains(".seism") && !e.1.contains(".hush") && !e.1.starts_with("stop");
            assert!(!h.iter().filter(other).any(|e| e.0 > VC_HUSH && e.0 < t - 0.05), "{z}: something else plays in the wait");
            for name in ["hush", "seism"] {
                let stop = format!("stop orbital:supervolcano.{name}");
                let cut = h.iter().find(|e| e.1 == stop).unwrap_or_else(|| panic!("{z}: {name} isn't cut")).0;
                assert!((cut - (t + VC_LEAD + VC_CUT)).abs() < 0.01, "{z}: {name} cut at {cut}");
            }
        }
    }

    /// The wait between the mount's stopping and the report is never silent: the hush starts on the tremor's last sample,
    /// on the strike's clock, and it and the seism last until the report cuts them, however far off the player is.
    #[test]
    fn vc_sound_the_wait_is_filled_until_the_report() {
        for z in [500.0, 1000.0, 1400.0, 2000.0, 3000.0] {
            let h = heard(z);
            let hush = h.iter().find(|e| e.1.ends_with(".hush")).expect("the hush");
            assert!((hush.0 - VC_HUSH).abs() < 1e-4 && hush.2 > 0.5, "{z}: the hush at {} at {}", hush.0, hush.2);
            let t = h.iter().find(|e| e.1.ends_with(".report") || e.1.ends_with(".report_far")).expect("the report").0;
            let s = h.iter().find(|e| e.1.ends_with(".seism")).expect("the seism").0;
            assert!(VC_HUSH + VC_HUSH_LEN > t + VC_LEAD + VC_CUT + 0.2, "{z}: the hush ends before the report");
            assert!(s + VC_SEISM_LEN > t + VC_LEAD + VC_CUT + 0.2, "{z}: the seism ends before the report");
        }
    }

    #[test]
    fn vc_sound_the_mount_stops_dead_at_the_hush() {
        for z in [300.0, 600.0, 1000.0, 1400.0, 2000.0, 3000.0] {
            for (t, event, _, pitch, _) in heard(z) {
                if let Some(name) = event.strip_prefix("orbital:supervolcano.") {
                    if t < VC_HUSH {
                        let end = t + len_of(name) / pitch;
                        assert!(end <= VC_HUSH + 0.01, "{z}: {name} at {t} rings on to {end}");
                    }
                }
            }
        }
    }

    #[test]
    fn vc_sound_flow_is_heard_by_the_distance() {
        assert!((front_r(VC_COLLAPSE + 4.0) - 500.0).abs() < 8.0, "{}", front_r(VC_COLLAPSE + 4.0));
        // (the lobes put the wall a little ahead of or behind that)
        assert!((-0.8..0.5).contains(&lobes(1.0, 500.0)));
        let hit = |h: &[(f32, String, f32, f32, bool)]| h.iter().find(|e| e.1.contains(".flow_hit")).map(|e| e.0);
        let (near, far) = (heard(1000.0), heard(2500.0));
        let t = hit(&near).expect("the hit");
        assert!((60.0..76.0).contains(&t), "{t}");
        assert!(near.iter().any(|e| e.1.contains("flow_in")), "inside it");
        assert!(near.iter().any(|e| e.1.contains("flow_rise") && t - e.0 > 5.0), "it closes for a long stretch");
        assert!(near.iter().any(|e| e.1.starts_with("stop") && e.1.contains("column")), "the jet's top goes in the hit");
        assert!(!near.iter().any(|e| e.0 > t + 0.2 && e.0 < t + 8.0 && e.1.contains("hurricane.")), "no lightning heard from inside");
        assert!(hit(&far).is_none(), "not this far out");
        assert!(far.iter().any(|e| e.1.contains("flow_far")), "the rush");
    }

    /// Nothing small carries: every whistle, close impact, stone, tree or grinding rock is played at a place, near the
    /// player, however far they are from the vent; the flow's only with the front on them.
    #[test]
    fn vc_sound_nothing_small_is_heard_from_afar() {
        for z in [1000.0, 1400.0, 1700.0, 2500.0] {
            let me = [0.5, 66.0, 0.5 + z];
            let mut p = plan_for_test();
            vc_sounds(&mut p, 37, [0.5, 65.0, 0.5], me, bombs(37, [0.0, 1.0, z]));
            let mut ev = std::mem::take(&mut p.ev);
            while let Some((t, a)) = ev.pop() {
                match a {
                    Act::Later(job) => ev.extend(job()),
                    Act::Sound { event, at, .. } => {
                        let name = event.strip_prefix("orbital:supervolcano.").unwrap_or(&event);
                        if ["whistle", "thud1", "thud2", "thud3", "thud4", "spatter", "splinter", "grind"].iter().any(|n| name.starts_with(n)) {
                            let q = at.unwrap_or_else(|| panic!("{name} at {t} isn't at a place"));
                            let d = (q[0] - me[0]).hypot(q[2] - me[2]);
                            let reach = if name.starts_with("whistle") || name.starts_with("thud") { NEAR } else if name.starts_with("spatter") { NEAR_STONES } else { NEAR_FRONT + 90.0 };
                            assert!(d < reach, "{name} at {t}, {d} blocks off");
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    /// The bombs thrown at the player are heard coming, one after another, from before 31 s.
    #[test]
    fn vc_sound_bombs_come_down_round_the_player() {
        for z in [1000.0, 1700.0] {
            let h = heard(z);
            let whistles: Vec<f32> = h.iter().filter(|e| e.1.contains(".whistle")).map(|e| e.0).collect();
            assert!(whistles.len() >= 12, "{z}: {} whistles", whistles.len());
            assert!(whistles[0] < 34.0, "{z}: the first at {}", whistles[0]);
            assert!(h.iter().filter(|e| e.1.contains(".thud") && !e.1.contains("far")).count() >= whistles.len());
            assert!(h.iter().any(|e| e.1.contains(".spatter")), "{z}: no stones");
        }
    }

    #[test]
    fn vc_sound_every_event_has_its_file_and_ends_in_time() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../orbital-sounds/assets/orbital");
        let events = std::fs::read_to_string(root.join("sounds.json")).unwrap();
        for z in [500.0, 800.0, 1000.0, 1200.0, 1400.0, 1500.0, 1700.0, 2000.0, 2500.0] {
            for (t, event, v, pitch, _) in heard(z) {
                if let Some((laser, name)) = event.strip_prefix("orbital:").and_then(|e| e.split_once('.')) {
                    assert!(events.contains(&format!("\"{laser}.{name}\"")), "{event} not in sounds.json");
                    assert!(root.join(format!("sounds/{laser}/{name}.ogg")).exists(), "{event} has no file");
                    assert!((0.0..=1.0).contains(&v) && (0.5..=2.0).contains(&pitch), "{event}: {v} {pitch}");
                    let end = t + len_of(name) / pitch;
                    assert!(end <= VC_LEN + 0.01, "{name} at {t} runs to {end}");
                }
            }
        }
    }

    /// The lightning is heard with the Hurricane's thunder, by kind for the distance, late by it; none of ours.
    #[test]
    fn vc_sound_lightning_is_the_hurricanes() {
        let h = heard(1000.0);
        let claps: Vec<_> = h.iter().filter(|e| e.1.starts_with("orbital:hurricane.")).collect();
        assert!(claps.len() >= 20, "{} claps", claps.len());
        assert!(claps.iter().all(|e| e.1.contains(".thunder_far") || e.1.contains(".rumble")), "a kilometre off: rolls");
        assert!(claps.iter().any(|e| e.1.contains(".rumble")) && claps.iter().any(|e| e.1.contains(".thunder_far")));
        let (late, _) = sound_from([0.5, 65.0, 0.5], [0.5, 66.0, 1000.5]);
        assert!(claps[0].0 >= VC_LIGHT - 2.0 + late, "{}", claps[0].0);
        assert!(!h.iter().any(|e| e.1.contains(".bolt")));
        assert!(claps.iter().all(|e| e.2 > 0.0 && e.2 <= 1.0 && (0.9..=1.06).contains(&e.3)));
    }

    /// The plan's sounds as a timeline for tools/sounds_volcano.py's mixes: `t event volume pitch` a line, `t stop event` for
    /// a stopsound; VC_ME the player's distance from the vent, VC_OUT the file.
    #[test]
    #[ignore]
    fn vc_write_sounds() {
        let z: f64 = std::env::var("VC_ME").map_or(1000.0, |v| v.parse().unwrap());
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
