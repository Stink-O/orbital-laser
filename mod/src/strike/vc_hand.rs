//! The light on the player's own hand under the Supervolcano (`render.set-hand-tint`: the game draws the hand and what it
//! holds after the post pass, out of its reach). What volcano.wgsl does to the land where the player stands: `vc_dim`'s
//! sun and sky shut out by the sheet and browned by the ash, near black inside the wall of ash (`vc_flow`'s depth past the
//! front, as the pass's engulfing), worked out a tick at a time; and on top, each frame, the quick light: the white-out
//! (volcano_mount.wgsl's `vm_over`), the eruption's flash, and the lightning near them (`vc_sound::flash`, the pass's
//! `vc_flash`, with its strokes).
use std::cell::RefCell;
use std::rc::Rc;

use super::HandLight;
use super::vc_sound::{FLASH_DT, flash, front_r, lobes, smooth};
use super::volcano::{Hf, VC_COLLAPSE, VC_ERUPT, VC_RED, VC_RING};
use super::mh;

/// volcano.wgsl's VC_SPREAD, VC_HU, VC_LEN.
const SPREAD: f64 = 28.0;
const HU: f64 = 1500.0;
const LEN: f64 = 88.0;
/// A flash's light on the hand by how far off it is: a bolt's foot (the pass's `vc_flash_land` lights the land round it
/// within ~80; the hand is given a little more reach, as its light fills the air), and one in the cloud or out of it.
const BOLT_R2: f64 = 300.0 * 300.0;
const CLOUD_R2: f64 = 900.0 * 900.0;
/// The most flashes the hand keeps at once (three slots of 0.13 s are alive at a time).
const FLASHES: usize = 4;

/// A flash near enough to light the hand: when it began, how bright it is on the hand at most, and its strokes (a bolt's
/// re-strokes at `r0`, `r1`; a cloud's flickers at `ts` with weights `w`).
#[derive(Clone, Copy, Default)]
struct Flash {
    t0: f32,
    amp: f32,
    bolt: bool,
    r0: f32,
    r1: f32,
    ts: [f32; 4],
    w: [f32; 4],
}

pub(super) struct VcHand {
    s: u32,
    vent: [f64; 3],
    /// Where the player stood as it fired, off the vent (the pass's `vc_me`: which flashes are bolts).
    me: [f64; 2],
    hf: Rc<RefCell<Hf>>,
    steady: [f32; 3],
    fl: [Flash; FLASHES],
    n: usize,
}

impl VcHand {
    pub(super) fn new(s: u32, vent: [f64; 3], me: [f64; 3], hf: Rc<RefCell<Hf>>) -> VcHand {
        VcHand { s, vent, me: [me[0] - vent[0], me[2] - vent[2]], hf, steady: [1.0; 3], fl: [Flash::default(); FLASHES], n: 0 }
    }
}

/// The sun's direction at `day_time` (vanilla's celestial angle: up at noon, rising in the east, +x).
fn sun_dir(day_time: u64) -> [f64; 3] {
    let d = ((day_time % 24_000) as f64 / 24_000.0 - 0.25).rem_euclid(1.0);
    let e = 0.5 - (d * std::f64::consts::PI).cos() / 2.0;
    let a = (d * 2.0 + e) / 3.0 * std::f64::consts::TAU;
    [-a.sin(), a.cos(), 0.0]
}

/// What the land at `q` (off the vent) is multiplied by at strike second `t`, the sun at `sun`: volcano.wgsl's
/// `vc_set_state` (cov, Ru), `vc_sun_t`, `vc_sky_t` and `vc_dim` (for a colour that doesn't glow, browned as a grey is).
fn dim(t: f64, q: [f64; 3], sun: [f64; 3]) -> [f64; 3] {
    let u = (t - SPREAD).max(0.0);
    let thin = smooth(f64::from(VC_RED), LEN - 0.6, t).powf(1.3);
    let cov = smooth(2.0, 16.0, u) * (1.0 - thin);
    if cov <= 0.0 {
        return [1.0; 3];
    }
    let ru = 620.0 * smooth(0.0, 3.0, u) + 130.0 * u.powf(1.28);
    let sun_up = smooth(-0.12, 0.06, sun[1]);
    // (the light's way: the sun, or the moon opposite it)
    let l = {
        let s = if sun[1] > -0.04 { sun } else { [-sun[0], -sun[1], -sun[2]] };
        let v = [s[0], s[1] + 0.03, s[2]];
        let n = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt().max(1.0e-6);
        [v[0] / n, v[1] / n, v[2] / n]
    };
    let sun_t = {
        let up = HU - 120.0 - q[1];
        if l[1] < 0.01 || up < 0.0 {
            1.0
        } else {
            let r = (q[0] + l[0] * up / l[1]).hypot(q[2] + l[2] * up / l[1]);
            1.0 - cov * (1.0 - smooth(ru - 700.0, ru - 100.0, r)) * smooth(0.0, 160.0, up)
        }
    };
    let sky_t = {
        let d = (HU - q[1]).max(60.0);
        let lo = (ru - q[0].hypot(q[2])).max(0.0);
        1.0 - cov * (1.0 - d / (d * d + lo * lo).sqrt()) * 0.97
    };
    let st = 1.0 + (sun_t - 1.0) * sun_up;
    let lit = (0.72 * st + 0.28) * (0.05 + 0.95 * sky_t.powf(1.3));
    let b = 0.9 * cov;
    [lit * (1.0 + 0.12 * b), lit * (1.0 - 0.08 * b), lit * (1.0 - 0.26 * b)]
}

impl HandLight for VcHand {
    fn tick(&mut self, t: f32, at: [f64; 3]) {
        let q = [at[0] - self.vent[0], at[1] - self.vent[1], at[2] - self.vent[2]];
        let tt = f64::from(t);
        let day = crate::sdk::game::get_clock().map_or(6000, |c| c.day_time);
        let mut k = dim(tt, q, sun_dir(day));
        // (inside the wall of ash: near black, what light there is red from under it; `volcano`'s engulfing)
        if t > VC_COLLAPSE {
            let (rho, ang) = (q[0].hypot(q[2]), q[2].atan2(q[0]));
            let land = self.hf.borrow().at(q[0], q[2]);
            let rf = front_r(t);
            let e = rf - rho - (4.0 * (rf - VC_RING) + 30.0).min(520.0) * lobes(ang, rho) - 2.6 * land.max(0.0);
            let over = (q[1] - land).max(0.0);
            if e > 0.0 && over < 400.0 {
                let drf = 25.0 + 35.0 * (-(tt - f64::from(VC_COLLAPSE)) / 14.0).exp();
                let tau = e / drf;
                let thick = smooth(0.0, 0.9, tau) * (1.0 - smooth(4.0, 8.5, tau)) * (1.0 - smooth(180.0, 400.0, over)) * smooth(0.0, 30.0, e);
                let murk = 1.0 - 0.85 * thick;
                k = [k[0] * murk * (1.0 + 0.3 * thick), k[1] * murk * (1.0 - 0.2 * thick), k[2] * murk * (1.0 - 0.45 * thick)];
            }
        }
        self.steady = k.map(|c| c as f32);
        // (the flashes alive now or by the next tick, near enough to show on the hand)
        self.n = 0;
        let first = ((tt - 0.4) / FLASH_DT).ceil().max(0.0) as u32;
        let last = ((tt + 0.06) / FLASH_DT).floor() as u32;
        for slot in first..=last {
            let Some((t0, p, kb, _)) = flash(self.s, slot) else { continue };
            if self.n == FLASHES {
                break;
            }
            // (a bolt or not, as the pass picks: where the player stood as it fired, ahead of the column or behind it)
            let me = self.me;
            let wl = (me[0] * me[0] + me[1] * me[1]).sqrt().max(1.0e-3);
            let way = [-me[0] / wl, -me[1] / wl];
            let (px, pz) = (p[0] - me[0], p[2] - me[1]);
            let ahead = (px * way[0] + pz * way[1]) / px.hypot(pz).max(1.0e-3);
            let hidden = smooth(0.35, 0.8, (p[0] * way[0] + p[2] * way[1]) / p[0].hypot(p[2]).max(1.0)) * (1.0 - smooth(700.0, 1100.0, (p[0] * way[1] - p[2] * way[0]).abs()));
            let what = mh(slot, self.s, 0x921);
            let bolt = what < 0.13 + (0.5 - 0.13) * smooth(0.45, 0.75, ahead) * (1.0 - hidden);
            let (dx, dz) = (p[0] - q[0], p[2] - q[2]);
            let amp = if bolt {
                // (as `vc_flash_land` at a bolt's foot: the land times 1 + 1.6 * 2.4 * its stroke)
                3.84 / (1.0 + (dx * dx + dz * dz) / BOLT_R2)
            } else {
                let dy = p[1] - q[1];
                let faint = if mh(slot, self.s, 0x922) < 0.34 { 0.3 } else { 1.0 };
                1.2 * kb * faint / (1.0 + (dx * dx + dy * dy + dz * dz) / CLOUD_R2)
            };
            if amp < 0.08 {
                continue;
            }
            let n = (mh(slot, self.s, 0x907) * 65535.0) as u32;
            let mut f = Flash { t0, amp: amp as f32, bolt, ..Flash::default() };
            if bolt {
                f.r0 = 0.28 + 0.03 * (n & 7) as f32 / 7.0;
                f.r1 = 0.335 + 0.03 * ((n >> 3) & 7) as f32 / 7.0;
            } else {
                // (vc_strokes: one to four flickers after the first, each 0.04 to 0.13 s after the one before)
                let count = 1 + n % 4;
                let mut ts = 0.0;
                for k in 0..=count.min(3) {
                    let h = (super::pcg(n.wrapping_mul(13).wrapping_add(k)) & 1023) as f32 / 1023.0;
                    if k > 0 {
                        ts += 0.04 + 0.09 * h;
                    }
                    f.ts[k as usize] = ts;
                    f.w[k as usize] = if k == 0 { 1.0 } else { 0.5 + 0.4 * h };
                }
            }
            self.fl[self.n] = f;
            self.n += 1;
        }
    }

    fn frame(&self, t: f32) -> ([f32; 3], [f32; 3]) {
        let mut quick = [1.0f32; 3];
        // (the lightning)
        let mut e = 0.0;
        for f in &self.fl[..self.n] {
            let a = t - f.t0;
            if !(0.0..0.39).contains(&a) {
                continue;
            }
            let fade = 1.0 - smooth32(0.3, 0.39, a);
            let s = if f.bolt {
                // (vc_beam_k + 0.4 vc_lead_k: the leader flickering, the return stroke, a re-stroke or two)
                let beam = smooth32(0.05, 0.075, a) * (1.0 - smooth32(0.19, 0.27, a)) * 0.94;
                let lead = if a < 0.075 {
                    0.75
                } else if a >= f.r0 && a <= f.r0 + 0.034 {
                    0.8
                } else if a >= f.r1 && a <= f.r1 + 0.018 {
                    0.56
                } else {
                    0.0
                };
                beam + 0.4 * lead
            } else {
                // (each flicker's light dying away over some 40 ms: a cheap stand-in for vc_strokes' exp)
                let mut s = 0.0;
                for k in 0..4 {
                    let x = a - f.ts[k];
                    if f.w[k] > 0.0 && x >= 0.0 {
                        let y = x * 25.0;
                        s += f.w[k] / (1.0 + y * y);
                    }
                }
                s
            };
            e += f.amp * s * fade;
        }
        for c in &mut quick {
            *c += e;
        }
        // (the eruption's flash: a blaze along the ring, warm, gone in a second)
        let a = t - VC_ERUPT;
        if a > 0.0 && a < 7.0 {
            let fl = 5.0 * (-a / 0.12).exp() + 0.9 * (-a / 1.1).exp();
            let w = 0.025 * fl;
            quick = [quick[0] + 3.0 * w, quick[1] + 1.2 * w, quick[2] + 0.3 * w];
        }
        // (the white-out: vm_over's, one flash from 18.6 s, gone by 19.25)
        if t > VC_ERUPT + 0.5 && t < VC_ERUPT + 1.3 {
            let u = smooth32(VC_ERUPT + 0.6, VC_ERUPT + 0.97, t);
            let down = 1.0 - smooth32(VC_ERUPT + 1.05, VC_ERUPT + 1.24, t);
            let w = u * u * u * u * down;
            for c in &mut quick {
                *c *= 1.0 + 3.0 * w;
            }
        }
        (self.steady, quick)
    }
}

fn smooth32(a: f32, b: f32, x: f32) -> f32 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hand(me: [f64; 3]) -> VcHand {
        VcHand::new(37, [0.5, 65.0, 0.5], me, Default::default())
    }
    fn lum(c: [f32; 3]) -> f32 {
        0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }

    #[test]
    fn the_hand_darkens_under_the_sheet_and_browns() {
        let mut h = hand([0.5, 70.0, 1000.5]);
        h.tick(10.0, [0.5, 70.0, 1000.5]);
        assert_eq!(h.frame(10.0).0, [1.0; 3], "nothing before the sheet");
        h.tick(60.0, [600.5, 70.0, 1500.5]);
        let (k, _) = h.frame(60.0);
        assert!(lum(k) < 0.1, "dark under the sheet: {k:?}");
        assert!(k[0] > k[2], "browned: {k:?}");
        h.tick(87.9, [0.5, 70.0, 1000.5]);
        assert!(lum(h.frame(87.9).0) > 0.9, "the sheet gone: {:?}", h.frame(87.9).0);
    }

    #[test]
    fn the_hand_goes_near_black_in_the_wall_of_ash() {
        let mut h = hand([0.5, 70.0, 1000.5]);
        // (well out of the wall's reach, then in it a few seconds after it went over)
        h.tick(60.0, [0.5, 70.0, 5000.5]);
        let out = lum(h.frame(60.0).0);
        // (where it went over about three seconds ago: its depth past the front, `e`, some 3 s of its speed)
        let (rf, drf) = (front_r(60.0), 25.0 + 35.0 * (-10.0f64 / 14.0).exp());
        let ang = std::f64::consts::FRAC_PI_2;
        let mut r = rf - 3.0 * drf;
        for _ in 0..8 {
            r = rf - 3.0 * drf - (4.0 * (rf - VC_RING) + 30.0).min(520.0) * lobes(ang, r);
        }
        h.tick(60.0, [0.5, 70.0, r + 0.5]);
        let inside = lum(h.frame(60.0).0);
        assert!(inside < 0.3 * out && inside < 0.02, "in the wall {inside}, out of it {out}");
    }

    #[test]
    fn the_hand_lights_up_with_a_flash_and_the_white_out() {
        let mut h = hand([0.5, 70.0, 1000.5]);
        assert!(h.frame(17.0).1 == [1.0; 3], "nothing quick before the eruption");
        assert!(h.frame(18.97).1[1] > 3.0, "the white-out: {:?}", h.frame(18.97).1);
        assert!(h.frame(19.5).1[1] < 1.2, "gone after it");
        // (some flash lights it while the lightning plays, and none lasts)
        let (mut most, mut dark) = (1.0f32, 0);
        let mut t = 26.0;
        while t < 75.0 {
            h.tick(t, [0.5, 70.0, 900.5]);
            for f in 0..3 {
                let q = h.frame(t + 0.0167 * f as f32).1[1];
                most = most.max(q);
                dark += usize::from(q < 1.01);
            }
            t += 0.05;
        }
        assert!(most > 1.3, "no flash lit the hand: {most}");
        assert!(dark > 1000, "the lightning never let go: {dark}");
    }
}
