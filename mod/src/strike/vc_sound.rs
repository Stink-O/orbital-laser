//! The Supervolcano's sounds: what plays when, as tools/sounds_volcano.py builds them (its notes say what each is).
//! Everything from the vent is late by the distance (343 blocks a second); what comes through the ground, five times
//! sooner. The player may well fly in a strike this long, so the plan asks where they are as each part comes due (the
//! tremor, the eruption, the collapse), rather than once as it fires.

use super::{Act, Plan, mh, pcg, sound_from};

// ---- the beats (BEATS.md, volcano.rs's): keep in step ------------------------------------------------------------------
const VC_HIT: f32 = 2.0;
const VC_CRACK: f32 = 8.0;
const VC_ERUPT: f32 = 12.0;
const VC_LIGHT: f32 = 20.0;
const VC_COLLAPSE: f32 = 44.0;
const VC_LIFT: f32 = 60.0;
const VC_LEN: f32 = 80.0;
/// Where the flow sets off from, and how high over the land its wall stands (volcano.wgsl's nose, a little more).
const VC_RING: f64 = 280.0;
const VC_WALL: f64 = 300.0;

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
/// When the wall reaches a place at `rho` from the vent, bearing `ang`, if it does while it is still a wall.
fn front_at(rho: f64, ang: f64) -> Option<f32> {
    let lob = lobes(ang, rho);
    let mut t = VC_COLLAPSE + 0.05;
    while t <= VC_LIFT + 2.0 {
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
/// vent, how bright). In the plume to begin with, out through the umbrella's rings, kilometres off, from about 30 s.
fn flashes(s: u32, from: f32, to: f32) -> Vec<(f32, [f64; 3], f64)> {
    const DT: f64 = 0.13;
    let mut out = Vec::new();
    let mut slot = (f64::from(from) / DT).ceil() as u32;
    while slot as f64 * DT < f64::from(to) {
        let t = slot as f64 * DT;
        let k = slot;
        slot += 1;
        let on = smooth(18.0, 28.0, t) * (1.0 - smooth(54.0, 72.0, t));
        if mh(k, s, 0x901) > 0.62 * on + if t >= 20.0 { 0.03 * on } else { 0.0 } {
            continue;
        }
        let th = std::f64::consts::TAU * mh(k, s, 0x902);
        let p = if mh(k, s, 0x903) < smooth(26.0, 34.0, t) {
            let u = (t - 23.0).max(0.0);
            let ru = 520.0 * smooth(0.0, 3.0, u) + 130.0 * u.powf(1.28);
            let r = (0.3 + 0.28 * (mh(k, s, 0x904) * 3.0).floor()) * ru.min(5200.0);
            [th.cos() * r, 1410.0, th.sin() * r]
        } else {
            let hy = 380.0 + 1100.0 * mh(k, s, 0x905);
            let rr = VC_RING - 155.0 * smooth(0.0, 520.0, hy);
            let ww = 52.0 + 0.35 * hy.min(520.0) + 0.24 * (hy - 520.0).max(0.0);
            let r = (rr + ww) * (0.75 + 0.2 * mh(k, s, 0x906));
            let a = (t - f64::from(VC_ERUPT)).max(0.0);
            let h = 1900.0 * (1.0 - (-(a + 0.15) / 8.5).exp()) + 3.0 * a.min(30.0);
            let c = (t - f64::from(VC_COLLAPSE)).max(0.0);
            [th.cos() * r, hy.min((h - 13.0 * c * c - 8.0 * c).max(60.0)), th.sin() * r]
        };
        out.push((t as f32, p, 0.5 + 0.8 * mh(k, s, 0x908)));
    }
    out
}

/// The lightning from `from` s up to `to` as heard at `me`: late by the distance, the near strokes `bolt` and the rest
/// a stutter of `bolt_far` (each file is many strokes close together already, so those that come on top of each other are
/// one take; the far ones run on into each other the sooner). Only what's heard in `when` plays, and none of it between
/// `mute`'s two times; `quiet` lets all of it down.
#[allow(clippy::too_many_arguments)]
fn thunder(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3], (from, to): (f32, f32), when: (f32, f32), mute: (f32, f32), quiet: f64) {
    let mut heard: Vec<(f32, f64, f64, u32)> = flashes(s, from, to)
        .iter()
        .enumerate()
        .map(|(i, (t, o, k))| {
            let (late, d) = sound_from([vent[0] + o[0], vent[1] + o[1], vent[2] + o[2]], me);
            (*t + late, d, *k, i as u32)
        })
        .filter(|h| h.0 >= when.0 && h.0 < when.1.min(VC_LEN - VC_BOLT_FAR / 0.9) && (h.0 < mute.0 || h.0 > mute.1))
        .collect();
    heard.sort_by(|a, b| a.0.total_cmp(&b.0));
    let (mut last_near, mut last_far, mut prev_near, mut prev_far) = (0u32, 0u32, f32::MIN, f32::MIN);
    for (at, d, k, i) in heard {
        let pitch = 0.9 + 0.2 * mh(i, s, 0xc7) as f32;
        let v = quiet * k.min(1.0);
        if d < 1050.0 {
            if at - prev_near >= 0.35 {
                prev_near = at;
                let t = take(&mut last_near, 4, mh(i, s, 0xc9));
                play(p, at, &format!("bolt{t}"), v * (620.0 / d.max(620.0)).powf(1.4), pitch);
            }
        } else if at - prev_far >= 0.7 && d < 4200.0 {
            prev_far = at;
            let t = take(&mut last_far, 4, mh(i, s, 0xca));
            play(p, at, &format!("bolt_far{t}"), v * (1400.0 / d.max(1400.0)).powf(0.9), pitch);
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

/// Bombs landing (`bombs`: when, and where off the vent): within `NEAR` of the player a whistle and a real impact where
/// it lands, past that only a dull thump, and only the bigger ones the further off they are.
fn land_bombs(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3], bombs: &[(f32, f64, f64)]) {
    let (mut wh, mut th, mut far, mut prev) = (0u32, 0u32, 0u32, f32::MIN);
    let mut order: Vec<usize> = (0..bombs.len()).filter(|i| bombs[*i].0 < VC_COLLAPSE).collect();
    order.sort_by(|a, b| bombs[*a].0.total_cmp(&bombs[*b].0));
    for i in order {
        let (t, x, z) = bombs[i];
        let i = i as u32;
        let at = [vent[0] + x, vent[1], vent[2] + z];
        let (late, d) = sound_from(at, me);
        let pitch = 0.85 + 0.3 * mh(i, s, 0xb5) as f32;
        if d < NEAR {
            let v = take(&mut wh, 3, mh(i, s, 0xb6));
            // (ending on its landing as the player hears that)
            play_at(p, t + late - VC_WHISTLES[v as usize - 1], &format!("whistle{v}"), at, 1.0);
            let v = take(&mut th, 4, mh(i, s, 0xb7));
            play_at(p, t + late, &format!("thud{v}"), at, pitch);
        } else {
            let at = t + late;
            let v = (0.4 + 0.6 * mh(i, s, 0xb4)) * (1.0 - (d - NEAR) / 1000.0);
            if v > 0.2 && at - prev > 0.3 {
                prev = at;
                let k = take(&mut far, 3, mh(i, s, 0xb8));
                play(p, at, &format!("thud_far{k}"), v, pitch);
            }
        }
    }
}

/// The flow, for the player `me`: when it hits them if it does, else the rush of it past where it stops, or below them.
fn flow(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3], drop: f32) -> Option<f32> {
    let (dx, dz) = (me[0] - vent[0], me[2] - vent[2]);
    let d = dx.hypot(dz);
    let hit = if me[1] - vent[1] < VC_WALL { front_at(d, dz.atan2(dx)) } else { None };
    let Some(hit) = hit else {
        // (a dark rush coming and ebbing away, no hit)
        play(p, VC_COLLAPSE + 2.0 + (d / 343.0) as f32, "flow_far", (1200.0 / d.max(1200.0)).powf(0.7), 1.0);
        return None;
    };
    // (the first the player can hear of it: the ring's sound, come across the land)
    let heard = VC_COLLAPSE + ((d - VC_RING).max(0.0) / 343.0) as f32;
    if let Some(k) = (0..VC_RISES.len()).rev().find(|k| hit - VC_RISES[*k] >= heard) {
        play(p, hit - VC_RISES[k], &format!("flow_rise{}", k + 1), 1.0, 1.0);
    }
    // (trees and rock in the front, only as it gets close: where along the front the sound comes from wanders a little)
    let (ux, uz) = (dx / d.max(1.0), dz / d.max(1.0));
    let (mut t, mut n, mut sp, mut gr) = (VC_COLLAPSE + 0.5, 0u32, 0u32, 0u32);
    while t < hit - 0.1 {
        let (gap, side) = (front_r(hit) - front_r(t), 170.0 * (mh(n, s, 0xd1) - 0.5));
        if gap < NEAR {
            let r = d - gap;
            let at = [vent[0] + ux * r - uz * side, vent[1], vent[2] + uz * r + ux * side];
            let heard = t + (gap.hypot(side) / 343.0) as f32;
            if mh(n, s, 0xd2) < 0.72 {
                let k = take(&mut sp, 3, mh(n, s, 0xd3));
                play_at(p, heard, &format!("splinter{k}"), at, 0.85 + 0.3 * mh(n, s, 0xd4) as f32);
            } else {
                let k = take(&mut gr, 2, mh(n, s, 0xd5));
                play_at(p, heard, &format!("grind{k}"), at, 0.85 + 0.3 * mh(n, s, 0xd6) as f32);
            }
        }
        t += 0.3 + 0.5 * mh(n, s, 0xd7) as f32;
        n += 1;
    }
    play(p, hit - VC_LEAD, "flow_hit", if (hit - drop).abs() > 0.8 { 0.85 } else { 0.7 }, 1.0);
    // (the hit is the loudest thing there is for a moment: under it the jet's top goes, so nothing but the inside is left)
    for name in ["column", "column_far"] {
        p.ev.push((hit + 0.05, Act::Cmd(format!("stopsound @s * {}", ev(name)))));
    }
    let k = usize::from(hit + VC_INS[0] > 78.0);
    play(p, hit + 0.1, &format!("flow_in{}", k + 1), 1.0, 1.0);
    Some(hit)
}

/// The Supervolcano's sounds, on plan `p`: the vent at `vent`, the player at `me` as it fires, `s` the pass's seed (the
/// lightning is the pass's own, `flashes`), `bombs` when and where (off the vent) the pass's lava bombs land.
pub(super) fn vc_sounds(p: &mut Plan, s: u32, vent: [f64; 3], me: [f64; 3], bombs: Vec<(f32, f64, f64)>) {
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
        let u = smooth(800.0, 520.0, d);
        if u > 0.0 {
            play(q, VC_CRACK + late, "steam", u, 1.0);
        }
    });
    // ---- the eruption: the report and the column, one moment late by the distance; the bombs and the lightning on it
    p.later(VC_ERUPT - 0.1, move |q| {
        let me = live(me);
        let (late, d) = sound_from(vent, me);
        near_far(q, VC_ERUPT + late - VC_LEAD, "report", d);
        play(q, VC_ERUPT + late - VC_LEAD, "report_sub", 0.85 * air(d), 1.0);
        near_far(q, VC_ERUPT + late, "column", d);
        land_bombs(q, s, vent, me, &bombs);
        thunder(q, s, vent, me, (VC_LIGHT - 2.0, VC_COLLAPSE), (0.0, VC_COLLAPSE), (0.0, 0.0), 1.0);
    });
    // ---- the collapse, the flow, what's left
    p.later(VC_COLLAPSE - 0.1, move |q| {
        let me = live(me);
        let (late, d) = sound_from(vent, me);
        near_far(q, VC_COLLAPSE + late, "collapse", d);
        let drop = VC_COLLAPSE + late + VC_DROP - VC_LEAD;
        let hit = flow(q, s, vent, me, drop);
        // (the land's drop, unless the flow's hit is on it: the two would be all the game's limiter heard)
        if hit.is_none_or(|h| (h - drop).abs() > 0.8) {
            play(q, drop, "report_sub", 0.85 * air(d), 0.8);
        }
        // (the lightning goes on in the ash: from inside the flow nothing of it gets through, and from 60 s it is faint)
        let mute = hit.map_or((0.0, 0.0), |h| (h, VC_LIFT + 2.0));
        thunder(q, s, vent, me, (VC_LIGHT - 2.0, VC_LIFT), (VC_COLLAPSE, VC_LEN), mute, 0.8);
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

    /// Where the pass's bombs land on flat land (volcano.rs's vc_bombs).
    fn bombs(s: u32) -> Vec<(f32, f64, f64)> {
        (0..64u32)
            .map(|k| {
                let u = (f64::from(k) + 0.8 * mh(k, s, 0xb1)) / 64.0;
                let t0 = 13.0 + 17.0 * u.powf(0.8);
                let th = std::f64::consts::TAU * mh(k, s, 0xb2);
                let r0 = VC_RING + 50.0 * (mh(k, s, 0xb3) - 0.5);
                let (y0, vo, vy) = (40.0 + 80.0 * mh(k, s, 0xb4), 16.0 + 62.0 * mh(k, s, 0xb5).powf(1.6), 120.0 + 140.0 * mh(k, s, 0xb6));
                let tau = (vy + (vy * vy + 2.0 * 28.0 * y0).sqrt()) / 28.0;
                let sway = th + 0.5 * (mh(k, s, 0xb7) - 0.5);
                ((t0 + tau) as f32, r0 * th.cos() + vo * sway.cos() * tau, r0 * th.sin() + vo * sway.sin() * tau)
            })
            .collect()
    }

    fn heard(z: f64) -> Vec<(f32, String, f32, f32, bool)> {
        let me = [0.5, 66.0, 0.5 + z];
        let mut p = plan_for_test();
        vc_sounds(&mut p, 37, [0.5, 65.0, 0.5], me, bombs(37));
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
        // (the lobes put the wall a little ahead of or behind that)
        assert!((-0.5..0.5).contains(&lobes(1.0, 500.0)));
        let hit = |h: &[(f32, String, f32, f32, bool)]| h.iter().find(|e| e.1.contains(".flow_hit")).map(|e| e.0);
        let (near, far) = (heard(500.0), heard(1500.0));
        let t = hit(&near).expect("the hit");
        assert!((45.0..54.0).contains(&t), "{t}");
        assert!(near.iter().any(|e| e.1.contains("flow_in")), "inside it");
        assert!(near.iter().any(|e| e.1.starts_with("stop") && e.1.contains("column")), "the jet's top goes in the hit");
        assert!(!near.iter().any(|e| e.0 > t + 0.2 && e.0 < 62.0 && e.1.contains(".bolt")), "no lightning heard from inside");
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
