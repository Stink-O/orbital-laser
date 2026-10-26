//! The laser wheel (capability `ui`): a ring of segments, one per laser, round
//! a centre button that switches terrain damage, and a switch over the ring's
//! top right for the strikes' messages over the hotbar. The lasers are laid out in
//! pages of five (arrows either side of the ring and numbered tabs over it
//! turn the page; so does a right-click). Under the ring, two rows of buttons
//! for which way a ship laser's ship comes in and how it arrives, and a row of
//! swatches for the colour it is lit in (shown while one is loaded, or its
//! segment is pointed at). Over the title, the player's flying speed: a bar to
//! click along and a field to type one in. Drawn by the game from the
//! shapes built here; GUI pixels, from the centre of the screen.
use crate::lasers::{LASERS, Laser, is_ship};
use crate::strike::{APPROACHES, ARRIVALS, COLOUR_RGB, COLOURS, Choice};
use horizon_mod_sdk::ui::{Draw, Point, Rect};
use std::f32::consts::{PI, TAU};

const R_IN: f32 = 30.0;
const R_OUT: f32 = 96.0;
/// Radians left empty between two segments.
const GAP: f32 = 0.035;
/// Segments a page.
pub const PAGE: usize = 5;
/// The ship lasers' rows under the ring (approach, arrival, colour): the first's top, each button's size, and the space
/// between them.
const ROW_Y: f32 = R_OUT + 20.0;
const BTN_W: f32 = 46.0;
const BTN_H: f32 = 16.0;
const BTN_GAP: f32 = 4.0;
/// The page arrows either side of the ring (their middles' distance out, their size), and the page tabs over it.
const ARROW_X: f32 = R_OUT + 24.0;
const ARROW_W: f32 = 18.0;
const ARROW_H: f32 = 34.0;
const TAB_Y: f32 = -R_OUT - 16.0;
const TAB_W: f32 = 20.0;
const TAB_H: f32 = 11.0;
/// The strike messages' switch, over the ring's top right.
const MSG: Rect = Rect { x: R_OUT - 30.0, y: -R_OUT - 33.0, w: 80.0, h: 15.0 };
/// The status panel's switch, under the messages'.
const HUD: Rect = Rect { x: MSG.x, y: MSG.y + MSG.h + 3.0, w: MSG.w, h: MSG.h };
/// The flying speed's row over the title: the bar (a click along it sets the speed) and the field a speed is typed in.
const FLY_Y: f32 = -R_OUT - 56.0;
const BAR: Rect = Rect { x: -76.0, y: FLY_Y, w: 150.0, h: 14.0 };
const FIELD: Rect = Rect { x: 80.0, y: FLY_Y, w: 46.0, h: 14.0 };
/// The bar's top speed and the highest a typed one may be, in times vanilla's.
pub const BAR_MAX: f32 = 40.0;
pub const FLY_MAX: f32 = 1000.0;
/// Characters the field holds.
const FIELD_CHARS: usize = 6;

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Spot {
    Laser(usize),
    Centre,
    /// The strike messages' switch.
    Messages,
    /// The status panel's switch.
    Hud,
    /// One of the ship's approaches (strike::APPROACHES), or ways of arriving (strike::ARRIVALS).
    Approach(usize),
    Arrival(usize),
    /// One of the ship's colours (strike::COLOURS).
    Colour(usize),
    /// A page arrow or tab: the page it turns to.
    Page(usize),
    /// The flying speed's bar, and its field.
    FlyBar,
    FlyField,
}

#[derive(Default)]
pub struct Wheel {
    pub hover: Option<Spot>,
    /// The ship laser whose rows are open because its segment has been pointed at; they stay open until another laser
    /// or the centre is pointed at, or the page turned.
    row_for: Option<usize>,
    /// The page shown.
    pub page: usize,
    /// The flying speed shown, in times vanilla's, and what has been typed in its field while it has the keyboard.
    pub fly: f32,
    pub typing: Option<String>,
    /// The speed a click on the bar would give, while the cursor is on it.
    bar_hover: Option<f32>,
}

/// How many pages of lasers there are, and the page a laser is on.
pub fn pages() -> usize {
    LASERS.len().div_ceil(PAGE)
}
pub fn page_of(i: usize) -> usize {
    i / PAGE
}

/// Row `row`'s buttons (0 approach, 1 arrival, 2 colour), left to right: the approaches centred, the ways of arriving
/// under them with the colours' swatches beside them, the two together centred.
const SWATCH: f32 = 14.0;
fn button(row: usize, k: usize) -> Rect {
    let y = ROW_Y + row.min(1) as f32 * (BTN_H + BTN_GAP + 2.0);
    if row == 0 {
        let n = ROWS[0].len() as f32;
        let x0 = -(n * BTN_W + (n - 1.0) * BTN_GAP) / 2.0;
        return Rect { x: x0 + k as f32 * (BTN_W + BTN_GAP), y, w: BTN_W, h: BTN_H };
    }
    let na = ROWS[1].len() as f32;
    let nc = ROWS[2].len() as f32;
    let wa = na * BTN_W + (na - 1.0) * BTN_GAP;
    let x0 = -(wa + 12.0 + nc * SWATCH + (nc - 1.0) * 3.0) / 2.0;
    if row == 1 {
        Rect { x: x0 + k as f32 * (BTN_W + BTN_GAP), y, w: BTN_W, h: BTN_H }
    } else {
        Rect { x: x0 + wa + 12.0 + k as f32 * (SWATCH + 3.0), y: y + 1.0, w: SWATCH, h: SWATCH }
    }
}
const ROWS: [&[Choice]; 3] = [&APPROACHES, &ARRIVALS, &COLOURS];
fn row_spot(r: usize, k: usize) -> Spot {
    [Spot::Approach(k), Spot::Arrival(k), Spot::Colour(k)][r]
}
/// The page arrows: 0 back (left of the ring), 1 on (right of it).
fn arrow(k: usize) -> Rect {
    let x = if k == 0 { -ARROW_X } else { ARROW_X };
    Rect { x: x - ARROW_W / 2.0, y: -ARROW_H / 2.0, w: ARROW_W, h: ARROW_H }
}
fn tab(k: usize) -> Rect {
    let n = pages() as f32;
    let x0 = -(n * TAB_W + (n - 1.0) * 3.0) / 2.0;
    Rect { x: x0 + k as f32 * (TAB_W + 3.0), y: TAB_Y, w: TAB_W, h: TAB_H }
}
fn inside(b: &Rect, x: f32, y: f32) -> bool {
    x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h
}

/// The speed `t` of the way along the bar gives: 1x to 40x in even ratios, so the low end has room, rounded to a half
/// under 10x and to whole ones over it.
pub fn bar_speed(t: f32) -> f32 {
    let m = BAR_MAX.powf(t.clamp(0.0, 1.0));
    if m < 10.0 { (m * 2.0).round() / 2.0 } else { m.round() }
}
/// The speed a click at `x` on the bar gives.
pub fn bar_speed_at(x: f32) -> f32 {
    bar_speed((x - BAR.x) / BAR.w)
}
/// How far along the bar speed `m` sits (a typed speed past its end at the end).
fn bar_place(m: f32) -> f32 {
    (m.max(1.0).ln() / BAR_MAX.ln()).min(1.0)
}
/// A typed speed: any number over 0 (an `x` after it is fine), up to 1000x.
pub fn parse_speed(s: &str) -> Option<f32> {
    let v: f32 = s.trim().trim_end_matches(['x', 'X']).parse().ok()?;
    (v.is_finite() && v > 0.0).then(|| v.min(FLY_MAX))
}
/// A speed as the wheel and the panel show it: `12x`, `2.5x`, `0.25x`.
pub fn speed_label(m: f32) -> String {
    let s = format!("{m:.2}");
    format!("{}x", s.trim_end_matches('0').trim_end_matches('.'))
}
/// What typing adds to the field: digits and a point, up to its length.
pub fn type_into(field: &mut String, text: &str) {
    for c in text.chars() {
        if (c.is_ascii_digit() || c == '.') && field.len() < FIELD_CHARS {
            field.push(c);
        }
    }
}

/// Where slot `k`'s middle points: the first on the left, then clockwise.
fn segment_angle(k: usize) -> f32 {
    PI + k as f32 * TAU / PAGE as f32
}

/// What is under the cursor on page `page` (`row`: whether the ship's rows are showing).
pub fn spot(x: f32, y: f32, row: bool, page: usize) -> Option<Spot> {
    // (the bar takes a little either side of its ends, for its first and last speeds)
    if inside(&Rect { x: BAR.x - 4.0, y: BAR.y - 2.0, w: BAR.w + 8.0, h: BAR.h + 4.0 }, x, y) {
        return Some(Spot::FlyBar);
    }
    if inside(&FIELD, x, y) {
        return Some(Spot::FlyField);
    }
    if row {
        for (r, items) in ROWS.iter().enumerate() {
            for k in 0..items.len() {
                if inside(&button(r, k), x, y) {
                    return Some(row_spot(r, k));
                }
            }
        }
    }
    if inside(&MSG, x, y) {
        return Some(Spot::Messages);
    }
    if inside(&HUD, x, y) {
        return Some(Spot::Hud);
    }
    if pages() > 1 {
        for k in 0..2 {
            if inside(&arrow(k), x, y) {
                return Some(Spot::Page(if k == 0 { (page + pages() - 1) % pages() } else { (page + 1) % pages() }));
            }
        }
        for k in 0..pages() {
            if inside(&tab(k), x, y) {
                return Some(Spot::Page(k));
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
    let span = TAU / PAGE as f32;
    let from_first = (y.atan2(x) - (segment_angle(0) - span / 2.0)).rem_euclid(TAU);
    let i = page * PAGE + ((from_first / span) as usize).min(PAGE - 1);
    (i < LASERS.len()).then_some(Spot::Laser(i))
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
    pub fn on_page(page: usize, fly: f32) -> Self {
        Wheel { page: page.min(pages() - 1), fly, ..Default::default() }
    }
    /// The ship laser the rows are for, if they are showing: the one pointed at, or the one loaded.
    pub fn row_laser(&self, selected: usize) -> Option<usize> {
        self.row_for.or(is_ship(LASERS[selected]).then_some(selected))
    }
    /// Whether the rows are showing.
    pub fn row_shown(&self, selected: usize) -> bool {
        self.row_laser(selected).is_some()
    }
    /// Turn to page `k` (the rows close unless the loaded laser is a ship).
    pub fn turn(&mut self, k: usize) {
        self.page = k % pages();
        self.row_for = None;
    }
    /// Takes a new cursor position; true when what is drawn changed.
    pub fn hover_at(&mut self, x: f32, y: f32, selected: usize) -> bool {
        let now = spot(x, y, self.row_shown(selected), self.page);
        let was = self.row_for;
        match now {
            Some(Spot::Laser(i)) => self.row_for = is_ship(LASERS[i]).then_some(i),
            Some(Spot::Centre) => self.row_for = None,
            _ => {}
        }
        let bar = (now == Some(Spot::FlyBar)).then(|| bar_speed_at(x));
        let changed = now != self.hover || was != self.row_for || bar != self.bar_hover;
        self.hover = now;
        self.bar_hover = bar;
        changed
    }

    #[allow(clippy::too_many_arguments)]
    pub fn draws(&self, selected: usize, terrain: bool, messages: bool, hud: bool, approach: usize, arrival: usize, colours: &[usize]) -> Vec<Draw> {
        let mut out = Vec::new();
        // the world dims behind the wheel
        out.push(Draw::Fill((Rect { x: -4000.0, y: -4000.0, w: 8000.0, h: 8000.0 }, 0x8C05070A)));
        // a soft halo and the ring's dark body
        sector(&mut out, 0.0, TAU, R_OUT, R_OUT + 10.0, 0x22FFFFFF);
        let span = TAU / PAGE as f32;
        for k in 0..PAGE {
            let mid = segment_angle(k);
            let (a0, a1) = (mid - span / 2.0 + GAP, mid + span / 2.0 - GAP);
            let i = self.page * PAGE + k;
            let Some(laser) = LASERS.get(i) else {
                // a slot for a laser still to come
                sector(&mut out, a0, a1, R_IN + 4.0, R_OUT, 0xB00C0E12);
                sector(&mut out, a0, a1, R_OUT - 1.0, R_OUT, 0x40FFFFFF);
                continue;
            };
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
        // the strike messages: on or off, the way the centre shows terrain damage
        let hovered = self.hover == Some(Spot::Messages);
        out.push(Draw::Fill((MSG, if hovered { 0xF0262A31 } else { 0xD0101318 })));
        out.push(Draw::Fill((Rect { x: MSG.x, y: MSG.y + MSG.h - 1.5, w: MSG.w, h: 1.5 }, if messages { 0xFF62D46A } else { 0xFFE0524E })));
        text(&mut out, "MESSAGES", MSG.x + 27.0, MSG.y + 4.0, 0xB8BEC8);
        text(&mut out, if messages { "ON" } else { "OFF" }, MSG.x + 64.0, MSG.y + 4.0, if messages { 0x7CE884 } else { 0xF06A64 });
        // and the status panel, the same way
        let hovered = self.hover == Some(Spot::Hud);
        out.push(Draw::Fill((HUD, if hovered { 0xF0262A31 } else { 0xD0101318 })));
        out.push(Draw::Fill((Rect { x: HUD.x, y: HUD.y + HUD.h - 1.5, w: HUD.w, h: 1.5 }, if hud { 0xFF62D46A } else { 0xFFE0524E })));
        text(&mut out, "PANEL", HUD.x + 27.0, HUD.y + 4.0, 0xB8BEC8);
        text(&mut out, if hud { "ON" } else { "OFF" }, HUD.x + 64.0, HUD.y + 4.0, if hud { 0x7CE884 } else { 0xF06A64 });
        // title, the flying speed, the pages, hint, and what the highlighted laser does
        text(&mut out, "ORBITAL LASER", 0.0, -R_OUT - 30.0, 0xFFFFFF);
        self.fly_row(&mut out);
        if pages() > 1 {
            self.page_controls(&mut out, selected);
        }
        // the ship's approaches, ways of arriving and colours: the ones it will use lit in its laser's colour (each
        // colour's swatch in its own)
        let row = self.row_laser(selected);
        let below = if let Some(rl) = row {
            let ms = LASERS[rl];
            for (r, items) in ROWS.iter().enumerate() {
                let chosen = [approach, arrival, colours.get(rl).copied().unwrap_or(0)][r];
                for (k, a) in items.iter().enumerate() {
                    let b = button(r, k);
                    let hovered = self.hover == Some(row_spot(r, k));
                    if r == 2 {
                        // a swatch: the picked one ringed in white, the one pointed at brighter
                        if k == chosen {
                            out.push(Draw::Fill((Rect { x: b.x - 1.5, y: b.y - 1.5, w: b.w + 3.0, h: b.h + 3.0 }, 0xFFFFFFFF)));
                        }
                        let c = COLOUR_RGB[k];
                        out.push(Draw::Fill((Rect { x: b.x, y: b.y, w: b.w, h: b.h }, argb(0xFF, if hovered { shade(c, 1.25) } else { shade(c, 0.85) }))));
                        continue;
                    }
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
            _ if self.typing.is_some() => "Type a flying speed (times vanilla's)  ·  Enter: set it  ·  click elsewhere: leave it".to_string(),
            Some(Spot::FlyBar) => format!("Click: fly at {}  ·  or click the box and type any speed", speed_label(self.bar_hover.unwrap_or(self.fly))),
            Some(Spot::FlyField) => "Click to type a flying speed, up to 1000x".to_string(),
            Some(Spot::Centre) => "Click: terrain damage on or off".to_string(),
            Some(Spot::Messages) => "Click: strike messages over the hotbar on or off (replies to your clicks stay)".to_string(),
            Some(Spot::Hud) => "Click: the status panel at the top right on or off".to_string(),
            Some(Spot::Laser(_)) => "Click to load this laser".to_string(),
            Some(Spot::Approach(k)) => format!("Click: the ship comes in {}", APPROACHES[k].label),
            Some(Spot::Arrival(k)) => format!("Click: the ship {}", ARRIVALS[k].label),
            Some(Spot::Colour(k)) => format!("Click: the ship lit {}", COLOURS[k].label),
            Some(Spot::Page(k)) => format!("Click: page {} of {}", k + 1, pages()),
            None if row.is_some() => "Pick a laser, or how the ship comes in, arrives and is lit  ·  Esc to close".to_string(),
            None if pages() > 1 => "Pick a laser  ·  arrows or right-click: more lasers  ·  Esc to close".to_string(),
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

    /// The flying speed's row: its name, the bar lit up to the speed with a knob there (and a mark where a click
    /// would put it), and the field showing the speed, or what is being typed in it.
    fn fly_row(&self, out: &mut Vec<Draw>) {
        const ACCENT: u32 = 0x6FC8FF;
        out.push(Draw::Fill((Rect { x: -138.0, y: FLY_Y - 3.0, w: 270.0, h: BAR.h + 6.0 }, 0xB0101318)));
        text(out, "FLY SPEED", -107.0, FLY_Y + 3.0, 0xB8BEC8);
        let hovered = self.hover == Some(Spot::FlyBar);
        let track = Rect { x: BAR.x, y: BAR.y + 5.0, w: BAR.w, h: 4.0 };
        out.push(Draw::Fill((track, if hovered { 0xFF2A3038 } else { 0xFF1C2026 })));
        let at = BAR.x + BAR.w * bar_place(self.fly);
        out.push(Draw::Fill((Rect { w: at - BAR.x, ..track }, argb(0xFF, if hovered { shade(ACCENT, 1.15) } else { ACCENT }))));
        // marks at 1x, 2x, 5x, 10x, 20x and 40x
        for m in [1.0, 2.0, 5.0, 10.0, 20.0, 40.0] {
            let x = BAR.x + BAR.w * bar_place(m);
            out.push(Draw::Fill((Rect { x: x - 0.5, y: BAR.y + 10.0, w: 1.0, h: 3.0 }, 0x70FFFFFF)));
        }
        if let Some(m) = self.bar_hover {
            let to = BAR.x + BAR.w * bar_place(m);
            out.push(Draw::Fill((Rect { x: to - 1.0, y: BAR.y + 1.0, w: 2.0, h: BAR.h - 2.0 }, 0x90FFFFFF)));
        }
        out.push(Draw::Fill((Rect { x: at - 2.0, y: BAR.y, w: 4.0, h: BAR.h }, 0xFFFFFFFF)));
        // the field: lit while it has the keyboard
        let typing = self.typing.as_deref();
        let body = if typing.is_some() { 0xF0262A31 } else if self.hover == Some(Spot::FlyField) { 0xF0202429 } else { 0xE0101318 };
        out.push(Draw::Fill((FIELD, body)));
        let rim = if typing.is_some() { 0xFFFFFFFF } else { argb(0xC0, ACCENT) };
        out.push(Draw::Fill((Rect { x: FIELD.x, y: FIELD.y + FIELD.h - 1.5, w: FIELD.w, h: 1.5 }, rim)));
        let (shown, colour) = match typing {
            Some(t) => (format!("{t}_"), 0xFFFFFF),
            None => (speed_label(self.fly), ACCENT),
        };
        text(out, &shown, FIELD.x + FIELD.w / 2.0, FIELD.y + 3.0, colour);
    }

    /// The page arrows either side of the ring, and the numbered tabs over it, the page shown lit (in the loaded laser's
    /// colour when it is on that page).
    fn page_controls(&self, out: &mut Vec<Draw>, selected: usize) {
        let accent = LASERS[selected].rgb;
        for k in 0..2 {
            let b = arrow(k);
            let to = if k == 0 { (self.page + pages() - 1) % pages() } else { (self.page + 1) % pages() };
            let hovered = self.hover == Some(Spot::Page(to));
            out.push(Draw::Fill((Rect { x: b.x, y: b.y, w: b.w, h: b.h }, if hovered { 0xF0262A31 } else { 0xD0101318 })));
            // a triangle pointing out from the ring
            let (cx, cy, s) = (b.x + b.w / 2.0, 0.0, if k == 0 { -1.0 } else { 1.0 });
            let tip = Point { x: cx + 5.0 * s, y: cy };
            let c = if hovered { 0xFFFFFFFF } else { 0xFFB8BEC8 };
            out.push(Draw::Quad((vec![Point { x: cx - 4.0 * s, y: cy - 7.0 }, tip, tip, Point { x: cx - 4.0 * s, y: cy + 7.0 }], c)));
        }
        for k in 0..pages() {
            let b = tab(k);
            let on = k == self.page;
            let hovered = self.hover == Some(Spot::Page(k)) && !on;
            let body = if on { 0xF0262A31 } else if hovered { 0xE01C2026 } else { 0xC0101318 };
            out.push(Draw::Fill((Rect { x: b.x, y: b.y, w: b.w, h: b.h }, body)));
            let rim = if on { if page_of(selected) == k { argb(0xFF, accent) } else { 0xFFB8BEC8 } } else { 0x60FFFFFF };
            out.push(Draw::Fill((Rect { x: b.x, y: b.y + b.h - 1.5, w: b.w, h: 1.5 }, rim)));
            text(out, &(k + 1).to_string(), b.x + b.w / 2.0, b.y + 2.0, if on { 0xFFFFFF } else { 0x8C93A0 });
        }
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
    fn ship(key: &str) -> usize {
        LASERS.iter().position(|l| l.key == key).unwrap()
    }
    #[test]
    fn spots() {
        assert_eq!(spot(0.0, 0.0, false, 0), Some(Spot::Centre));
        assert_eq!(spot(-60.0, 0.0, false, 0), Some(Spot::Laser(0)));
        // every laser on its own page, under its segment, rows showing or not; the first five keep their places
        for i in 0..LASERS.len() {
            let c = polar(segment_angle(i % PAGE), 60.0);
            assert_eq!(spot(c.x, c.y, false, page_of(i)), Some(Spot::Laser(i)));
            assert_eq!(spot(c.x, c.y, true, page_of(i)), Some(Spot::Laser(i)));
            if i < PAGE {
                assert_eq!(page_of(i), 0);
            }
        }
        // the empty slots on the last page are nothing
        let last = pages() - 1;
        for k in (LASERS.len() - last * PAGE)..PAGE {
            let c = polar(segment_angle(k), 60.0);
            assert_eq!(spot(c.x, c.y, false, last), None);
        }
        assert_eq!(spot(0.0, 300.0, false, 0), None);
        // the messages' switch, on every page, clear of the ring, the title, the tabs and the arrows
        for page in 0..pages() {
            assert_eq!(spot(MSG.x + MSG.w / 2.0, MSG.y + MSG.h / 2.0, true, page), Some(Spot::Messages));
            assert_eq!(spot(HUD.x + HUD.w / 2.0, HUD.y + HUD.h / 2.0, true, page), Some(Spot::Hud));
        }
        let corner = (MSG.x * MSG.x + (MSG.y + MSG.h) * (MSG.y + MSG.h)).sqrt();
        assert!(corner > R_OUT + 14.0 && MSG.x > tab(pages() - 1).x + TAB_W + 4.0 && MSG.y + MSG.h < arrow(1).y);
        let corner = (HUD.x * HUD.x + (HUD.y + HUD.h) * (HUD.y + HUD.h)).sqrt();
        assert!(corner > R_OUT + 14.0 && HUD.y + HUD.h < arrow(1).y);
        assert_eq!(page_of(ship("downfall")), 1);
    }
    #[test]
    fn pages_turn() {
        assert!(pages() >= 2);
        // the arrows and tabs are clickable, clear of the ring and of each other, on every page
        for page in 0..pages() {
            let b = arrow(1);
            assert_eq!(spot(b.x + b.w / 2.0, b.y + b.h / 2.0, false, page), Some(Spot::Page((page + 1) % pages())));
            let b = arrow(0);
            assert_eq!(spot(b.x + b.w / 2.0, b.y + b.h / 2.0, true, page), Some(Spot::Page((page + pages() - 1) % pages())));
            assert!(b.x + b.w < -R_OUT - 2.0);
            for k in 0..pages() {
                let t = tab(k);
                assert_eq!(spot(t.x + t.w / 2.0, t.y + t.h / 2.0, false, page), Some(Spot::Page(k)));
                assert!(t.y + t.h < -R_OUT - 2.0);
            }
        }
        let mut w = Wheel::on_page(7, 1.0);
        assert_eq!(w.page, pages() - 1);
        w.turn(pages());
        assert_eq!(w.page, 0);
    }
    #[test]
    fn flying_speed_row() {
        // the bar and the field are clickable on every page, the ship's rows showing or not, clear of the messages'
        // switch and the title, and on a 1080p screen at GUI scale 3 (360 high)
        for page in 0..pages() {
            for row in [false, true] {
                assert_eq!(spot(BAR.x + 2.0, BAR.y + 7.0, row, page), Some(Spot::FlyBar));
                assert_eq!(spot(BAR.x + BAR.w - 2.0, BAR.y + 7.0, row, page), Some(Spot::FlyBar));
                assert_eq!(spot(FIELD.x + FIELD.w / 2.0, FIELD.y + 7.0, row, page), Some(Spot::FlyField));
            }
        }
        assert!(FIELD.y + FIELD.h < MSG.y - 2.0 && FLY_Y + BAR.h < -R_OUT - 30.0 - 2.0 && FLY_Y - 3.0 > -180.0);
        assert!(BAR.x + BAR.w + 4.0 < FIELD.x);
        // 1x at the left end, 40x at the right, rising all the way, with room at the low end
        assert_eq!(bar_speed_at(BAR.x - 3.0), 1.0);
        assert_eq!(bar_speed_at(BAR.x + BAR.w + 3.0), BAR_MAX);
        let speeds: Vec<f32> = (0..=100).map(|k| bar_speed(k as f32 / 100.0)).collect();
        assert!(speeds.windows(2).all(|w| w[1] >= w[0]));
        assert!(bar_speed(0.25) <= 3.0);
        for m in [1.0, 2.0, 5.0, 10.0, 20.0, 40.0] {
            assert_eq!(bar_speed(bar_place(m)), m);
        }
        assert_eq!(bar_place(500.0), 1.0);
        // typed speeds: any number over 0, up to 1000x
        assert_eq!(parse_speed("12"), Some(12.0));
        assert_eq!(parse_speed("2.5x"), Some(2.5));
        assert_eq!(parse_speed(" 0.25 "), Some(0.25));
        assert_eq!(parse_speed("5000"), Some(FLY_MAX));
        for bad in ["", ".", "0", "-3", "abc", "NaN", "inf"] {
            assert_eq!(parse_speed(bad), None, "{bad}");
        }
        assert_eq!(speed_label(12.0), "12x");
        assert_eq!(speed_label(2.5), "2.5x");
        assert_eq!(speed_label(0.25), "0.25x");
        assert_eq!(speed_label(1000.0), "1000x");
        let mut field = String::new();
        type_into(&mut field, "1a2.5x");
        assert_eq!(field, "12.5");
        type_into(&mut field, "123456");
        assert_eq!(field.len(), FIELD_CHARS);
        // the mark follows the cursor along the bar
        let mut w = Wheel::on_page(0, 1.0);
        assert!(w.hover_at(BAR.x + 10.0, BAR.y + 7.0, 0));
        assert!(!w.hover_at(BAR.x + 10.0, BAR.y + 7.0, 0));
        assert!(w.hover_at(BAR.x + BAR.w + 1.0, BAR.y + 7.0, 0));
        assert_eq!(w.bar_hover, Some(BAR_MAX));
    }
    #[test]
    fn approach_row() {
        // each button clickable while the row shows, nothing there while it doesn't, clear of the ring
        for k in 0..APPROACHES.len() {
            let b = button(0, k);
            let (x, y) = (b.x + b.w / 2.0, b.y + b.h / 2.0);
            assert_eq!(spot(x, y, true, 0), Some(Spot::Approach(k)));
            assert_ne!(spot(x, y, false, 0), Some(Spot::Approach(k)));
            assert!(b.y > R_OUT + 10.0);
        }
        for k in 0..ARRIVALS.len() {
            let b = button(1, k);
            assert!(b.y > button(0, 0).y + BTN_H);
            assert_eq!(spot(b.x + b.w / 2.0, b.y + b.h / 2.0, true, 1), Some(Spot::Arrival(k)));
        }
        for k in 0..COLOURS.len() {
            let b = button(2, k);
            // (beside the ways of arriving, clear of them)
            assert!(b.x > button(1, ARRIVALS.len() - 1).x + BTN_W + 4.0 && (b.y - button(1, 0).y).abs() < 2.0);
            assert_eq!(spot(b.x + b.w / 2.0, b.y + b.h / 2.0, true, 0), Some(Spot::Colour(k)));
            assert_ne!(spot(b.x + b.w / 2.0, b.y + b.h / 2.0, false, 0), Some(Spot::Colour(k)));
        }
        // pointing at either ship opens its rows, on its own page, and they stay open on the way down to them
        for key in ["mothership", "downfall"] {
            let s = ship(key);
            let mut w = Wheel::on_page(page_of(s), 1.0);
            let other = 0;
            assert!(!w.row_shown(other));
            let c = polar(segment_angle(s % PAGE), 60.0);
            w.hover_at(c.x, c.y, other);
            assert_eq!(w.row_laser(other), Some(s));
            let b = button(0, 2);
            w.hover_at(b.x + 4.0, b.y + 4.0, other);
            assert_eq!(w.hover, Some(Spot::Approach(2)));
            assert_eq!(w.row_laser(other), Some(s));
            let b = button(1, 1);
            w.hover_at(b.x + 4.0, b.y + 4.0, other);
            assert_eq!(w.hover, Some(Spot::Arrival(1)));
            w.hover_at(0.0, 0.0, other);
            assert!(!w.row_shown(other));
            assert_eq!(w.row_laser(s), Some(s));
        }
        // a loaded ship keeps its rows on the other page too
        let w = Wheel::on_page(0, 1.0);
        assert_eq!(w.row_laser(ship("downfall")), Some(ship("downfall")));
    }
}
