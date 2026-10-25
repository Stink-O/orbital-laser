//! The laser wheel (capability `ui`): a ring of segments, one per laser, round
//! a centre button that switches terrain damage, and under the ring two rows of
//! buttons for which way the mothership comes in and how it arrives (shown while
//! it is loaded, or its segment is pointed at). Drawn by the game from the shapes built here;
//! GUI pixels, from the centre of the screen.
use crate::lasers::{LASERS, Laser};
use crate::strike::{APPROACHES, ARRIVALS, Choice};
use horizon_mod_sdk::ui::{Draw, Point, Rect};
use std::f32::consts::{PI, TAU};

const R_IN: f32 = 30.0;
const R_OUT: f32 = 96.0;
/// Radians left empty between two segments.
const GAP: f32 = 0.035;
/// The mothership's rows under the ring (approach, then arrival): the first's top, each button's size, and the space
/// between them.
const ROW_Y: f32 = R_OUT + 20.0;
const BTN_W: f32 = 46.0;
const BTN_H: f32 = 16.0;
const BTN_GAP: f32 = 4.0;

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Spot {
    Laser(usize),
    Centre,
    /// One of the mothership's approaches (strike::APPROACHES), or ways of arriving (strike::ARRIVALS).
    Approach(usize),
    Arrival(usize),
}

#[derive(Default)]
pub struct Wheel {
    pub hover: Option<Spot>,
    /// The mothership's rows stay open once its segment has been pointed at, until another laser or the centre is.
    row_open: bool,
}

/// The mothership's place in LASERS.
pub fn mothership() -> usize {
    LASERS.iter().position(|l| l.key == "mothership").unwrap_or(0)
}

/// Row `row`'s buttons (0 approach, 1 arrival), left to right, each row centred.
fn button(row: usize, k: usize) -> Rect {
    let n = [APPROACHES.len(), ARRIVALS.len()][row] as f32;
    let x0 = -(n * BTN_W + (n - 1.0) * BTN_GAP) / 2.0;
    Rect { x: x0 + k as f32 * (BTN_W + BTN_GAP), y: ROW_Y + row as f32 * (BTN_H + BTN_GAP + 2.0), w: BTN_W, h: BTN_H }
}
const ROWS: [&[Choice]; 2] = [&APPROACHES, &ARRIVALS];

/// Where segment `i`'s middle points: the first laser on the left, then clockwise.
fn segment_angle(i: usize) -> f32 {
    PI + i as f32 * TAU / LASERS.len() as f32
}

/// What is under the cursor (`row`: whether the approach row is showing).
pub fn spot(x: f32, y: f32, row: bool) -> Option<Spot> {
    if row {
        for (r, items) in ROWS.iter().enumerate() {
            for k in 0..items.len() {
                let b = button(r, k);
                if x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h {
                    return Some(if r == 0 { Spot::Approach(k) } else { Spot::Arrival(k) });
                }
            }
        }
    }
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
    /// Whether the approach row is showing.
    pub fn row_shown(&self, selected: usize) -> bool {
        self.row_open || selected == mothership()
    }
    /// Takes a new cursor position; true when what is drawn changed.
    pub fn hover_at(&mut self, x: f32, y: f32, selected: usize) -> bool {
        let now = spot(x, y, self.row_shown(selected));
        let was_open = self.row_open;
        match now {
            Some(Spot::Laser(i)) => self.row_open = i == mothership(),
            Some(Spot::Centre) => self.row_open = false,
            _ => {}
        }
        let changed = now != self.hover || was_open != self.row_open;
        self.hover = now;
        changed
    }

    pub fn draws(&self, selected: usize, terrain: bool, approach: usize, arrival: usize) -> Vec<Draw> {
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
        // the mothership's approaches and ways of arriving: the ones it will use lit in its colour
        let row = self.row_shown(selected);
        let below = if row {
            let ms = LASERS[mothership()];
            for (r, items) in ROWS.iter().enumerate() {
                let chosen = [approach, arrival][r];
                for (k, a) in items.iter().enumerate() {
                    let b = button(r, k);
                    let hovered = self.hover == Some(if r == 0 { Spot::Approach(k) } else { Spot::Arrival(k) });
                    let body = if hovered { argb(0xE6, shade(ms.rgb, 0.42)) } else { 0xE0101318 };
                    out.push(Draw::Fill((Rect { x: b.x, y: b.y, w: b.w, h: b.h }, body)));
                    let rim = if k == chosen { 2.0 } else { 1.0 };
                    let rim_c = if k == chosen { argb(0xFF, ms.rgb) } else { argb(0x90, shade(ms.rgb, 0.6)) };
                    out.push(Draw::Fill((Rect { x: b.x, y: b.y + b.h - rim, w: b.w, h: rim }, rim_c)));
                    let tc = if k == chosen || hovered { ms.rgb } else { 0x9AA2AE };
                    text(&mut out, a.button, b.x + b.w / 2.0, b.y + 4.0, tc);
                }
            }
            2.0 * BTN_H + BTN_GAP + 14.0
        } else {
            0.0
        };
        let hint = match self.hover {
            Some(Spot::Centre) => "Click: terrain damage on or off".to_string(),
            Some(Spot::Laser(_)) => "Click to load this laser".to_string(),
            Some(Spot::Approach(k)) => format!("Click: the mothership comes in {}", APPROACHES[k].label),
            Some(Spot::Arrival(k)) => format!("Click: the mothership {}", ARRIVALS[k].label),
            None if row => "Pick a laser, or how the mothership comes in and arrives  ·  Esc to close".to_string(),
            None => "Pick a laser  ·  Esc to close".to_string(),
        };
        text(&mut out, &hint, 0.0, R_OUT + 16.0 + below, 0x8C93A0);
        if let Some(Spot::Laser(i)) = self.hover {
            for (k, line) in wrap(LASERS[i].blurb, 52).iter().enumerate() {
                text(&mut out, line, 0.0, R_OUT + 32.0 + below + k as f32 * 10.0, 0xC9CED8);
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
        assert_eq!(spot(0.0, 0.0, false), Some(Spot::Centre));
        assert_eq!(spot(-60.0, 0.0, false), Some(Spot::Laser(0)));
        for i in 0..LASERS.len() {
            let c = polar(segment_angle(i), 60.0);
            assert_eq!(spot(c.x, c.y, false), Some(Spot::Laser(i)));
            assert_eq!(spot(c.x, c.y, true), Some(Spot::Laser(i)));
        }
        assert_eq!(spot(0.0, 300.0, false), None);
    }
    #[test]
    fn approach_row() {
        // each button clickable while the row shows, nothing there while it doesn't, clear of the ring
        for k in 0..APPROACHES.len() {
            let b = button(0, k);
            let (x, y) = (b.x + b.w / 2.0, b.y + b.h / 2.0);
            assert_eq!(spot(x, y, true), Some(Spot::Approach(k)));
            assert_ne!(spot(x, y, false), Some(Spot::Approach(k)));
            assert!(b.y > R_OUT + 10.0);
        }
        for k in 0..ARRIVALS.len() {
            let b = button(1, k);
            assert!(b.y > button(0, 0).y + BTN_H);
            assert_eq!(spot(b.x + b.w / 2.0, b.y + b.h / 2.0, true), Some(Spot::Arrival(k)));
        }
        // pointing at the mothership opens it, and it stays open on the way down to it
        let mut w = Wheel::default();
        let other = (mothership() + 1) % LASERS.len();
        assert!(!w.row_shown(other));
        let c = polar(segment_angle(mothership()), 60.0);
        w.hover_at(c.x, c.y, other);
        assert!(w.row_shown(other));
        let b = button(0, 2);
        w.hover_at(b.x + 4.0, b.y + 4.0, other);
        assert_eq!(w.hover, Some(Spot::Approach(2)));
        let b = button(1, 1);
        w.hover_at(b.x + 4.0, b.y + 4.0, other);
        assert_eq!(w.hover, Some(Spot::Arrival(1)));
        w.hover_at(0.0, 0.0, other);
        assert!(!w.row_shown(other));
        assert!(w.row_shown(mothership()));
    }
}
