//! The laser wheel (capability `ui`): a ring of segments, one per laser, round
//! a centre button that switches terrain damage. Drawn by the game from the
//! shapes built here; GUI pixels, from the centre of the screen.
use crate::lasers::{LASERS, Laser};
use horizon_mod_sdk::ui::{Draw, Point, Rect};
use std::f32::consts::{PI, TAU};

const R_IN: f32 = 30.0;
const R_OUT: f32 = 96.0;
/// Radians left empty between two segments.
const GAP: f32 = 0.035;

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Spot {
    Laser(usize),
    Centre,
}

#[derive(Default)]
pub struct Wheel {
    pub hover: Option<Spot>,
}

/// Where segment `i`'s middle points: the first laser on the left, then clockwise.
fn segment_angle(i: usize) -> f32 {
    PI + i as f32 * TAU / LASERS.len() as f32
}

/// What is under the cursor.
pub fn spot(x: f32, y: f32) -> Option<Spot> {
    let d = (x * x + y * y).sqrt();
    if d < R_IN {
        return Some(Spot::Centre);
    }
    if d > R_OUT + 14.0 {
        return None;
    }
    let span = TAU / LASERS.len() as f32;
    let from_first = (y.atan2(x) - (segment_angle(0) - span / 2.0)).rem_euclid(TAU);
    Some(Spot::Laser(((from_first / span) as usize).min(LASERS.len() - 1)))
}

fn argb(a: u8, rgb: u32) -> u32 {
    (u32::from(a) << 24) | (rgb & 0xFF_FFFF)
}
/// `rgb` darkened (k < 1) or lightened towards white (k > 1).
fn shade(rgb: u32, k: f32) -> u32 {
    let ch = |s: u32| {
        let c = ((rgb >> s) & 0xFF) as f32;
        let v = if k <= 1.0 { c * k } else { c + (255.0 - c) * (k - 1.0) };
        (v.clamp(0.0, 255.0) as u32) << s
    };
    ch(16) | ch(8) | ch(0)
}
fn polar(a: f32, r: f32) -> Point {
    Point { x: a.cos() * r, y: a.sin() * r }
}
/// A ring sector from `a0` to `a1`, radii `r0` to `r1`, as thin quads.
fn sector(out: &mut Vec<Draw>, a0: f32, a1: f32, r0: f32, r1: f32, color: u32) {
    let steps = ((a1 - a0).abs() / 0.07).ceil().max(1.0) as usize;
    for k in 0..steps {
        let (b0, b1) = (a0 + (a1 - a0) * k as f32 / steps as f32, a0 + (a1 - a0) * (k + 1) as f32 / steps as f32);
        out.push(Draw::Quad((vec![polar(b0, r0), polar(b0, r1), polar(b1, r1), polar(b1, r0)], color)));
    }
}
fn text(out: &mut Vec<Draw>, s: &str, x: f32, y: f32, rgb: u32) {
    out.push(Draw::Text((s.to_string(), Point { x, y }, rgb, true)));
}
fn wrap(s: &str, width: usize) -> Vec<String> {
    let mut lines = Vec::new();
    let mut line = String::new();
    for w in s.split_whitespace() {
        if !line.is_empty() && line.len() + 1 + w.len() > width {
            lines.push(std::mem::take(&mut line));
        }
        if !line.is_empty() {
            line.push(' ');
        }
        line.push_str(w);
    }
    if !line.is_empty() {
        lines.push(line);
    }
    lines
}

impl Wheel {
    /// Takes a new cursor position; true when what is highlighted changed.
    pub fn hover_at(&mut self, x: f32, y: f32) -> bool {
        let now = spot(x, y);
        let changed = now != self.hover;
        self.hover = now;
        changed
    }

    pub fn draws(&self, selected: usize, terrain: bool) -> Vec<Draw> {
        let mut out = Vec::new();
        // the world dims behind the wheel
        out.push(Draw::Fill((Rect { x: -4000.0, y: -4000.0, w: 8000.0, h: 8000.0 }, 0x8C05070A)));
        // a soft halo and the ring's dark body
        sector(&mut out, 0.0, TAU, R_OUT, R_OUT + 10.0, 0x22FFFFFF);
        let span = TAU / LASERS.len() as f32;
        for (i, laser) in LASERS.iter().enumerate() {
            let mid = segment_angle(i);
            let (a0, a1) = (mid - span / 2.0 + GAP, mid + span / 2.0 - GAP);
            let hovered = self.hover == Some(Spot::Laser(i));
            let body = if hovered { argb(0xE6, shade(laser.rgb, 0.42)) } else { 0xE0101318 };
            sector(&mut out, a0, a1, R_IN + 4.0, R_OUT, body);
            // the accent rim: full on the loaded laser, a hairline on the others
            let rim = if i == selected { 5.0 } else { 1.5 };
            sector(&mut out, a0, a1, R_OUT - rim, R_OUT, argb(0xFF, laser.rgb));
            if hovered {
                sector(&mut out, a0, a1, R_IN + 4.0, R_IN + 5.5, argb(0xC0, shade(laser.rgb, 1.3)));
            }
            segment_label(&mut out, laser, mid, hovered || i == selected);
        }
        // the centre: terrain damage on or off
        let hovered = self.hover == Some(Spot::Centre);
        sector(&mut out, 0.0, TAU, 0.0, R_IN, if hovered { 0xF0262A31 } else { 0xF0121418 });
        sector(&mut out, 0.0, TAU, R_IN - 1.5, R_IN, if terrain { 0xFF62D46A } else { 0xFFE0524E });
        text(&mut out, "TERRAIN", 0.0, -9.0, 0xB8BEC8);
        text(&mut out, if terrain { "ON" } else { "OFF" }, 0.0, 2.0, if terrain { 0x7CE884 } else { 0xF06A64 });
        // title, hint, and what the highlighted laser does
        text(&mut out, "ORBITAL LASER", 0.0, -R_OUT - 26.0, 0xFFFFFF);
        let hint = match self.hover {
            Some(Spot::Centre) => "Click: terrain damage on or off",
            Some(Spot::Laser(_)) => "Click to load this laser",
            None => "Pick a laser  ·  Esc to close",
        };
        text(&mut out, hint, 0.0, R_OUT + 16.0, 0x8C93A0);
        if let Some(Spot::Laser(i)) = self.hover {
            for (k, line) in wrap(LASERS[i].blurb, 52).iter().enumerate() {
                text(&mut out, line, 0.0, R_OUT + 32.0 + k as f32 * 10.0, 0xC9CED8);
            }
        }
        out
    }
}

/// A segment's icon (twice the hotbar size) and its name under it.
fn segment_label(out: &mut Vec<Draw>, laser: &Laser, mid: f32, bright: bool) {
    let c = polar(mid, (R_IN + R_OUT) / 2.0 + 2.0);
    let scale = 2.0;
    out.push(Draw::Item((
        "minecraft:paper".to_string(),
        laser.icon_model.to_string(),
        Point { x: c.x - 8.0 * scale, y: c.y - 8.0 * scale - 5.0 },
        scale,
    )));
    let rgb = if bright { laser.rgb } else { shade(laser.rgb, 0.75) };
    text(out, laser.title, c.x, c.y + 13.0, rgb);
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn spots() {
        assert_eq!(spot(0.0, 0.0), Some(Spot::Centre));
        assert_eq!(spot(-60.0, 0.0), Some(Spot::Laser(0)));
        for i in 0..LASERS.len() {
            let c = polar(segment_angle(i), 60.0);
            assert_eq!(spot(c.x, c.y), Some(Spot::Laser(i)));
        }
        assert_eq!(spot(0.0, 300.0), None);
    }
}
