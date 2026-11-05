//! The Tsunami's sounds on the strike's clock (tools/sounds_tsunami.py makes the files; its `schedule` is the same
//! arithmetic, for its mix checks). `tp` is when the water closes over the player's head (the pass's engulf), `t_t` when
//! the front reaches the target.
use super::tsunami::{TsGeo, smooth};
use super::{Act, Plan, mh};

fn sound(p: &mut Plan, t: f64, name: &str, volume: f64) {
    if volume <= 0.001 {
        return;
    }
    p.ev.push((t.max(0.0) as f32, Act::Sound { event: format!("orbital:tsunami.{name}"), at: None, volume: volume.min(1.0) as f32, pitch: 1.0 }));
}

pub(super) fn ts_sounds(p: &mut Plan, geo: &TsGeo, me: [f64; 3], s: u32, t_t: f64, tp: f64, immersed: bool) {
    let dp = geo.dp;
    let late = dp / 343.0;
    let far = smooth(250.0, 800.0, dp);
    let share = (0.6 + 0.0017 * (dp - 300.0)).clamp(0.6, 1.0);
    sound(p, 0.0, "rupture", 1.0);
    sound(p, 1.5, "rumble", 1.0);
    sound(p, 2.5, "roar_far", (0.35 + 0.0013 * dp).clamp(0.6, 1.0));
    sound(p, (tp - 9.0).max(1.0), "roar_mid", 1.0);
    sound(p, tp - 4.0, "roar_near", (0.63 + 0.0022 * (dp - 250.0)).clamp(0.63, 1.0));
    sound(p, t_t + late - 0.06, "crash", share * (1.0 - far));
    sound(p, t_t + late - 0.06, "crash_far", share * far * (1.25 / (1.0 + dp / 2000.0)).min(1.0));
    if immersed {
        sound(p, tp, "engulf", (0.72 + 0.0028 * (dp - 250.0)).clamp(0.72, 1.0));
        sound(p, tp + 0.3, "under", 1.0);
        sound(p, tp + 8.5, "surface", 1.0);
    }
    sound(p, tp + 9.0, "drain", 1.0);
    sound(p, tp + 9.5, "roar_back", 1.0);
    sound(p, tp + 9.0, "rumble_after", 1.0);
    sound(p, tp + 17.0, "trickle", 1.0);
    // (the trees and the walls the front reaches round the player, heard where it is as it gets there: not while they are
    // under, which the file for it covers)
    let mut t = tp - 3.5;
    let mut n = 0u32;
    let mut last = [0u32; 2];
    while t < tp - 0.3 {
        let wood = mh(n, s, 0x81) < 0.65;
        let d = 20.0 + 100.0 * mh(n, s, 0x82);
        let across = (mh(n, s, 0x83) * 2.0 - 1.0) * 90.0;
        // (upstream of the player along the wave's way: where the front is when it gets there)
        let at = [me[0] - geo.m[0] * d + geo.n[0] * across, me[1], me[2] - geo.m[1] * d + geo.n[1] * across];
        let (ss, uu) = geo.su(at[0], at[2]);
        let ta = geo.arr(ss, uu) - 0.1;
        let nk: u32 = if wood { 4 } else { 3 };
        let mut k = (mh(n, s, 0x84) * f64::from(nk)) as u32 % nk + 1;
        let slot = usize::from(!wood);
        if k == last[slot] {
            k = k % nk + 1;
        }
        last[slot] = k;
        p.ev.push((ta.max(0.0) as f32, Act::Sound { event: format!("orbital:tsunami.{}{k}", if wood { "crack" } else { "slap" }), at: Some(at), volume: (0.8 + 0.2 * mh(n, s, 0x85)) as f32, pitch: 0.9 + 0.2 * mh(n, s, 0x86) as f32 }));
        t += 0.4 + 0.5 * mh(n, s, 0x87);
        n += 1;
    }
    // a few slaps as the water leaves
    for i in 0..4u32 {
        let at = [me[0] + (mh(i, s, 0x91) - 0.5) * 80.0, me[1], me[2] + (mh(i, s, 0x92) - 0.5) * 80.0];
        let k = 1 + (mh(i, s, 0x93) * 3.0) as u32 % 3;
        p.ev.push(((tp + 8.8 + 1.6 * f64::from(i)) as f32, Act::Sound { event: format!("orbital:tsunami.slap{k}"), at: Some(at), volume: 0.55, pitch: 0.95 + 0.1 * mh(i, s, 0x94) as f32 }));
    }
}
