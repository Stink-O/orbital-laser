//! The laser wheel (capability `ui`): a ring of segments, one per laser, round
//! a centre button that switches terrain damage, and switches over the ring's
//! top right for the strikes' messages over the hotbar, the status panel and
//! the heavy smoke's quality. The lasers are laid out in
//! pages of five (arrows either side of the ring and numbered tabs over it
//! turn the page; so does a right-click). Under the ring, two rows of buttons
//! for which way a ship laser's ship comes in and how it arrives, and a row of
//! swatches for the colour it is lit in (shown while one is loaded, or its
//! segment is pointed at); for the Payload, a row picking which blast it
//! plays; for the Nuke, a row stepping through its earlier clouds. Over the title, the player's flying speed: a bar to click along and a
//! field to type one in. Drawn by the game from the
//! shapes built here; GUI pixels, from the centre of the screen.
use crate::lasers::{LASERS, Laser, is_ship};
use crate::strike::{APPROACHES, ARRIVALS, COLOUR_RGB, COLOURS, Choice};
use horizon_mod_sdk::ui::{Draw, Point, Rect};
use std::f32::consts::{PI, TAU};

// Everything fits a 320 x 240 GUI (the smallest the game's GUI scale leaves): 160 either side of the centre, 120 up
// and down.
const R_IN: f32 = 24.0;
const R_OUT: f32 = 64.0;
/// Radians left empty between two segments.
const GAP: f32 = 0.035;
/// Segments a page.
pub const PAGE: usize = 5;
/// The ship lasers' rows under the ring (approach, arrival, colour): the first's top, each button's size, and the space
/// between them.
const ROW_Y: f32 = R_OUT + 22.0;
const BTN_W: f32 = 44.0;
const BTN_H: f32 = 13.0;
const BTN_GAP: f32 = 3.0;
/// The page arrows either side of the ring (their middles' distance out, their size), and the page tabs over it.
const ARROW_X: f32 = R_OUT + 20.0;
const ARROW_W: f32 = 16.0;
const ARROW_H: f32 = 30.0;
const TAB_Y: f32 = -R_OUT - 17.0;
const TAB_W: f32 = 20.0;
const TAB_H: f32 = 10.0;
/// The title's top, over the tabs.
const TITLE_Y: f32 = -R_OUT - 31.0;
/// The line under the ring: what the cursor is on (a laser's name, or what a click does), and a laser's blurb under it.
const INFO_Y: f32 = R_OUT + 8.0;
/// Characters a line of a blurb holds (6 GUI pixels each), and the lines it may take.
const BLURB_CHARS: usize = 50;
const BLURB_LINES: usize = 2;
/// The strike messages' switch, over the ring's top right.
const MSG: Rect = Rect { x: R_OUT, y: -R_OUT - 33.0, w: 84.0, h: 12.0 };
/// The status panel's switch, under the messages'.
const HUD: Rect = Rect { x: MSG.x, y: MSG.y + MSG.h + 2.0, w: MSG.w, h: MSG.h };
/// The quality switch, under the panel's: the Payload's and the Nuke's smoke at full size or half (`/orbital quality`).
const QUALITY: Rect = Rect { x: MSG.x, y: HUD.y + HUD.h + 2.0, w: MSG.w, h: MSG.h };
/// Stopping the strike under way, top left, the switches' mirror; there only while one is.
const STOP: Rect = Rect { x: -MSG.x - MSG.w, y: MSG.y, w: MSG.w, h: MSG.h * 2.0 + 2.0 };
/// The flying speed's row over the title: the bar (a click along it sets the speed) and the field a speed is typed in.
const FLY_Y: f32 = -R_OUT - 52.0;
const BAR: Rect = Rect { x: -56.0, y: FLY_Y, w: 106.0, h: 12.0 };
const FIELD: Rect = Rect { x: 56.0, y: FLY_Y, w: 40.0, h: 12.0 };
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
    /// The quality switch.
    Quality,
    /// Stopping the strike under way.
    Stop,
    /// One of the ship's approaches (strike::APPROACHES), or ways of arriving (strike::ARRIVALS).
    Approach(usize),
    Arrival(usize),
    /// One of the ship's colours (strike::COLOURS).
    Colour(usize),
    /// The Payload's blast sound: 0 the main one, 1 the alternative.
    Sound(usize),
    /// The Nuke's cloud: 0 the version before, 1 the one after (`CLOUDS`).
    Cloud(usize),
    /// A page arrow or tab: the page it turns to.
    Page(usize),
    /// The flying speed's bar, and its field.
    FlyBar,
    FlyField,
}

/// Which rows under the ring are showing: none, a ship laser's three, the Payload's sound, or the Nuke's cloud.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Rows {
    None,
    Ship,
    Payload,
    Nuke,
}
impl Rows {
    /// The rows laser `i` has (if any).
    pub fn of(i: Option<usize>) -> Self {
        match i.map(|i| LASERS[i]) {
            Some(l) if is_ship(l) => Rows::Ship,
            Some(l) if l.key == "payload" => Rows::Payload,
            Some(l) if l.key == "nuke" => Rows::Nuke,
            _ => Rows::None,
        }
    }
}
impl From<bool> for Rows {
    fn from(ship: bool) -> Self {
        if ship { Rows::Ship } else { Rows::None }
    }
}
/// Whether a laser has rows of its own under the ring.
fn has_rows(i: usize) -> bool {
    Rows::of(Some(i)) != Rows::None
}

/// The Payload's sound row: its label, then its two buttons, centred under the ring where a ship's first row is.
pub const SOUNDS: [(&str, &str); 2] = [("MAIN", "Blast: the main one, deep and rolling"), ("ALT", "Blast: the alternative, a sharp crack, a wide roar")];
const SOUND_LABEL_W: f32 = 72.0;
fn sound_button(k: usize) -> Rect {
    let w = SOUND_LABEL_W + 2.0 * BTN_W + BTN_GAP;
    Rect { x: -w / 2.0 + SOUND_LABEL_W + k as f32 * (BTN_W + BTN_GAP), y: ROW_Y, w: BTN_W, h: BTN_H }
}

/// The Nuke's clouds, oldest first, the last today's (`/orbital nukecloud`; mod/build.rs builds their
/// sources, tools/nuke_cloud.py writes them): the wheel's name for each and the commit it came from.
pub const CLOUDS: [(&str, &str); 9] = [
    ("v1 FIRST CLOUD", "f7212de"),
    ("v2 ROUND CROWN", "59f7989"),
    ("v3 FOLDING", "12c9f80"),
    ("v4 CARRIED LUMPS", "3570696"),
    ("v5 BOIL-UP", "6cb04f9"),
    ("v6 FIZEAU", "c969abe"),
    ("v7 BILLOWS", "73fe7bf"),
    ("v8 BOIL ON BILLOWS", "1ba6527"),
    ("v9 CURRENT", "today's"),
];
/// The setting's and the command's name for cloud `c`: its number, or `current` for today's.
pub fn cloud_key(c: usize) -> String {
    if c + 1 >= CLOUDS.len() { "current".to_string() } else { (c + 1).to_string() }
}
/// A cloud from `1`..`9` or `current` (also `v5`).
pub fn parse_cloud(s: &str) -> Option<usize> {
    let s = s.trim().trim_start_matches(['v', 'V']);
    if s.eq_ignore_ascii_case("current") {
        return Some(CLOUDS.len() - 1);
    }
    s.parse::<usize>().ok().filter(|&n| (1..=CLOUDS.len()).contains(&n)).map(|n| n - 1)
}
/// The Nuke's cloud row: its label, the arrow back, the name, the arrow on, centred under the ring.
const CLOUD_LABEL_W: f32 = 36.0;
const CLOUD_ARROW_W: f32 = 16.0;
const CLOUD_NAME_W: f32 = 114.0;
fn cloud_row_x() -> f32 {
    -(CLOUD_LABEL_W + 2.0 * CLOUD_ARROW_W + CLOUD_NAME_W + 2.0 * BTN_GAP) / 2.0
}
/// Its arrows (0 back, 1 on), and between them the name's box.
fn cloud_button(k: usize) -> Rect {
    let x = cloud_row_x() + CLOUD_LABEL_W + k as f32 * (CLOUD_ARROW_W + CLOUD_NAME_W + 2.0 * BTN_GAP);
    Rect { x, y: ROW_Y, w: CLOUD_ARROW_W, h: BTN_H }
}
fn cloud_name() -> Rect {
    Rect { x: cloud_row_x() + CLOUD_LABEL_W + CLOUD_ARROW_W + BTN_GAP, y: ROW_Y, w: CLOUD_NAME_W, h: BTN_H }
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
    /// A strike is under way: the stop button shows.
    pub striking: bool,
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
const SWATCH: f32 = 12.0;
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

/// What is under the cursor on page `page` (`rows`: the rows showing under the ring; `true` for a ship's).
pub fn spot(x: f32, y: f32, rows: impl Into<Rows>, page: usize) -> Option<Spot> {
    let rows = rows.into();
    // (the bar takes a little either side of its ends, for its first and last speeds)
    if inside(&Rect { x: BAR.x - 4.0, y: BAR.y - 2.0, w: BAR.w + 8.0, h: BAR.h + 4.0 }, x, y) {
        return Some(Spot::FlyBar);
    }
    if inside(&FIELD, x, y) {
        return Some(Spot::FlyField);
    }
    if rows == Rows::Payload {
        for k in 0..SOUNDS.len() {
            if inside(&sound_button(k), x, y) {
                return Some(Spot::Sound(k));
            }
        }
    }
    if rows == Rows::Nuke {
        for k in 0..2 {
            if inside(&cloud_button(k), x, y) {
                return Some(Spot::Cloud(k));
            }
        }
        // (a click on the name steps on, as the arrow after it)
        if inside(&cloud_name(), x, y) {
            return Some(Spot::Cloud(1));
        }
    }
    if rows == Rows::Ship {
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
    if inside(&QUALITY, x, y) {
        return Some(Spot::Quality);
    }
    if inside(&STOP, x, y) {
        return Some(Spot::Stop);
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
    if d > R_OUT + 8.0 {
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
    /// The laser the rows are for (a ship laser, or the Payload), if they are showing: the one pointed at, or the one
    /// loaded.
    pub fn row_laser(&self, selected: usize) -> Option<usize> {
        self.row_for.or(has_rows(selected).then_some(selected))
    }
    /// Which rows are showing.
    pub fn rows(&self, selected: usize) -> Rows {
        Rows::of(self.row_laser(selected))
    }
    /// Turn to page `k` (the rows close unless the loaded laser is a ship).
    pub fn turn(&mut self, k: usize) {
        self.page = k % pages();
        self.row_for = None;
    }
    /// Takes a new cursor position; true when what is drawn changed.
    pub fn hover_at(&mut self, x: f32, y: f32, selected: usize) -> bool {
        let now = spot(x, y, self.rows(selected), self.page).filter(|&s| s != Spot::Stop || self.striking);
        let was = self.row_for;
        match now {
            Some(Spot::Laser(i)) => self.row_for = has_rows(i).then_some(i),
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
    pub fn draws(&self, selected: usize, terrain: bool, messages: bool, hud: bool, approach: usize, arrival: usize, colours: &[usize], blast_alt: bool, fast: bool, cloud: usize) -> Vec<Draw> {
        let mut out = Vec::new();
        // the world dims behind the wheel
        out.push(Draw::Fill((Rect { x: -4000.0, y: -4000.0, w: 8000.0, h: 8000.0 }, 0x8C05070A)));
        // a soft halo and the ring's dark body
        sector(&mut out, 0.0, TAU, R_OUT, R_OUT + 3.0, 0x22FFFFFF);
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
        text(&mut out, "MESSAGES", MSG.x + 30.0, MSG.y + 2.0, 0xB8BEC8);
        text(&mut out, if messages { "ON" } else { "OFF" }, MSG.x + 70.0, MSG.y + 2.0, if messages { 0x7CE884 } else { 0xF06A64 });
        // and the status panel, the same way
        let hovered = self.hover == Some(Spot::Hud);
        out.push(Draw::Fill((HUD, if hovered { 0xF0262A31 } else { 0xD0101318 })));
        out.push(Draw::Fill((Rect { x: HUD.x, y: HUD.y + HUD.h - 1.5, w: HUD.w, h: 1.5 }, if hud { 0xFF62D46A } else { 0xFFE0524E })));
        text(&mut out, "PANEL", HUD.x + 30.0, HUD.y + 2.0, 0xB8BEC8);
        text(&mut out, if hud { "ON" } else { "OFF" }, HUD.x + 70.0, HUD.y + 2.0, if hud { 0x7CE884 } else { 0xF06A64 });
        // and the quality: FAST (the heavy smoke at half size) or FULL (every pixel)
        let hovered = self.hover == Some(Spot::Quality);
        out.push(Draw::Fill((QUALITY, if hovered { 0xF0262A31 } else { 0xD0101318 })));
        out.push(Draw::Fill((Rect { x: QUALITY.x, y: QUALITY.y + QUALITY.h - 1.5, w: QUALITY.w, h: 1.5 }, if fast { 0xFF62D46A } else { 0xFFE8B04A })));
        text(&mut out, "QUALITY", QUALITY.x + 30.0, QUALITY.y + 2.0, 0xB8BEC8);
        text(&mut out, if fast { "FAST" } else { "FULL" }, QUALITY.x + 70.0, QUALITY.y + 2.0, if fast { 0x7CE884 } else { 0xF0C060 });
        // stopping the strike under way
        if self.striking {
            let hovered = self.hover == Some(Spot::Stop);
            out.push(Draw::Fill((STOP, if hovered { 0xF04A1A1A } else { 0xD0101318 })));
            out.push(Draw::Fill((Rect { x: STOP.x, y: STOP.y + STOP.h - 1.5, w: STOP.w, h: 1.5 }, 0xFFE0524E)));
            text(&mut out, "STOP STRIKE", STOP.x + STOP.w / 2.0, STOP.y + STOP.h / 2.0 - 4.0, if hovered { 0xFFFFFF } else { 0xF06A64 });
        }
        // title, the flying speed, the pages, hint, and what the highlighted laser does
        text(&mut out, "ORBITAL LASER", 0.0, TITLE_Y, 0xFFFFFF);
        self.fly_row(&mut out);
        if pages() > 1 {
            self.page_controls(&mut out, selected);
        }
        // the ship's approaches, ways of arriving and colours: the ones it will use lit in its laser's colour (each
        // colour's swatch in its own)
        // (pointing at a laser that isn't a ship hides the loaded ship's rows, to make room for its blurb)
        let row = match self.hover {
            Some(Spot::Laser(i)) if !has_rows(i) => None,
            _ => self.row_laser(selected),
        };
        // (the Payload's: which blast it plays, the one picked lit in its colour)
        if let Some(rl) = row.filter(|&i| Rows::of(Some(i)) == Rows::Payload) {
            let ms = LASERS[rl];
            let b0 = sound_button(0);
            text(&mut out, "BLAST SOUND", b0.x - SOUND_LABEL_W / 2.0 - 2.0, b0.y + 2.0, 0xB8BEC8);
            for (k, (name, _)) in SOUNDS.iter().enumerate() {
                let b = sound_button(k);
                let chosen = k == usize::from(blast_alt);
                let hovered = self.hover == Some(Spot::Sound(k));
                out.push(Draw::Fill((b, if hovered { argb(0xE6, shade(ms.rgb, 0.42)) } else { 0xE0101318 })));
                let rim = if chosen { 2.0 } else { 1.0 };
                let rim_c = if chosen { argb(0xFF, ms.rgb) } else { argb(0x90, shade(ms.rgb, 0.6)) };
                out.push(Draw::Fill((Rect { x: b.x, y: b.y + b.h - rim, w: b.w, h: rim }, rim_c)));
                text(&mut out, name, b.x + b.w / 2.0, b.y + 2.0, if chosen || hovered { ms.rgb } else { 0x9AA2AE });
            }
        }
        // (the Nuke's: which of its clouds it draws, stepped through with the arrows either side of its name)
        if let Some(rl) = row.filter(|&i| Rows::of(Some(i)) == Rows::Nuke) {
            let ms = LASERS[rl];
            let b0 = cloud_button(0);
            text(&mut out, "CLOUD", b0.x - CLOUD_LABEL_W / 2.0 - 1.0, b0.y + 2.0, 0xB8BEC8);
            for (k, arrow) in ["<", ">"].iter().enumerate() {
                let b = cloud_button(k);
                let hovered = self.hover == Some(Spot::Cloud(k));
                out.push(Draw::Fill((b, if hovered { argb(0xE6, shade(ms.rgb, 0.42)) } else { 0xE0101318 })));
                out.push(Draw::Fill((Rect { x: b.x, y: b.y + b.h - 1.0, w: b.w, h: 1.0 }, argb(0x90, shade(ms.rgb, 0.6)))));
                text(&mut out, arrow, b.x + b.w / 2.0, b.y + 2.0, if hovered { ms.rgb } else { 0x9AA2AE });
            }
            let n = cloud_name();
            out.push(Draw::Fill((n, 0xE0101318)));
            out.push(Draw::Fill((Rect { x: n.x, y: n.y + n.h - 2.0, w: n.w, h: 2.0 }, argb(0xFF, ms.rgb))));
            text(&mut out, CLOUDS[cloud.min(CLOUDS.len() - 1)].0, n.x + n.w / 2.0, n.y + 2.0, ms.rgb);
        }
        if let Some(rl) = row.filter(|&i| is_ship(LASERS[i])) {
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
                    text(&mut out, a.button, b.x + b.w / 2.0, b.y + 2.0, tc);
                }
            }
        }
        // under the ring: a laser's name in its colour (and what it does, while no ship's rows are showing), or in a
        // few words what a click does
        let (info, rgb) = match self.hover {
            Some(Spot::Laser(i)) => (LASERS[i].title.to_string(), LASERS[i].rgb),
            _ if self.typing.is_some() => ("Type a speed  ·  Enter to set it".to_string(), 0x8C93A0),
            Some(Spot::FlyBar) => (format!("Fly at {}", speed_label(self.bar_hover.unwrap_or(self.fly))), 0x8C93A0),
            Some(Spot::FlyField) => ("Click to type a speed, up to 1000x".to_string(), 0x8C93A0),
            Some(Spot::Centre) => ("Terrain damage on or off".to_string(), 0x8C93A0),
            Some(Spot::Messages) => ("Strike messages on or off".to_string(), 0x8C93A0),
            Some(Spot::Hud) => ("Status panel on or off".to_string(), 0x8C93A0),
            Some(Spot::Quality) => ("Payload and Nuke smoke: FAST half size, FULL all".to_string(), 0x8C93A0),
            Some(Spot::Stop) => ("End the strike now: its effects, sounds and world changes".to_string(), 0x8C93A0),
            Some(Spot::Approach(k)) => (format!("Comes in {}", APPROACHES[k].label), 0x8C93A0),
            Some(Spot::Arrival(k)) => (format!("It {}", ARRIVALS[k].label), 0x8C93A0),
            Some(Spot::Colour(k)) => (format!("Lit {}", COLOURS[k].label), 0x8C93A0),
            Some(Spot::Sound(k)) => (SOUNDS[k].1.to_string(), 0x8C93A0),
            Some(Spot::Cloud(k)) => {
                let c = CLOUDS[cloud.min(CLOUDS.len() - 1)];
                (format!("{} cloud  ·  now {} ({})", if k == 0 { "Older" } else { "Newer" }, c.0, c.1), 0x8C93A0)
            }
            Some(Spot::Page(k)) => (format!("Page {} of {}", k + 1, pages()), 0x8C93A0),
            None if pages() > 1 => ("Right-click: next page  ·  Esc to close".to_string(), 0x8C93A0),
            None => ("Esc to close".to_string(), 0x8C93A0),
        };
        text(&mut out, &info, 0.0, INFO_Y, rgb);
        if let (Some(Spot::Laser(i)), None) = (self.hover, row) {
            for (k, line) in wrap(LASERS[i].blurb, BLURB_CHARS).iter().take(BLURB_LINES).enumerate() {
                text(&mut out, line, 0.0, INFO_Y + 11.0 + k as f32 * 10.0, 0xC9CED8);
            }
        }
        out
    }

    /// The flying speed's row: its name, the bar lit up to the speed with a knob there (and a mark where a click
    /// would put it), and the field showing the speed, or what is being typed in it.
    fn fly_row(&self, out: &mut Vec<Draw>) {
        const ACCENT: u32 = 0x6FC8FF;
        out.push(Draw::Fill((Rect { x: -120.0, y: FLY_Y - 3.0, w: 220.0, h: BAR.h + 6.0 }, 0xB0101318)));
        text(out, "FLY SPEED", -88.0, FLY_Y + 2.0, 0xB8BEC8);
        let hovered = self.hover == Some(Spot::FlyBar);
        let track = Rect { x: BAR.x, y: BAR.y + 4.0, w: BAR.w, h: 4.0 };
        out.push(Draw::Fill((track, if hovered { 0xFF2A3038 } else { 0xFF1C2026 })));
        let at = BAR.x + BAR.w * bar_place(self.fly);
        out.push(Draw::Fill((Rect { w: at - BAR.x, ..track }, argb(0xFF, if hovered { shade(ACCENT, 1.15) } else { ACCENT }))));
        // marks at 1x, 2x, 5x, 10x, 20x and 40x
        for m in [1.0, 2.0, 5.0, 10.0, 20.0, 40.0] {
            let x = BAR.x + BAR.w * bar_place(m);
            out.push(Draw::Fill((Rect { x: x - 0.5, y: BAR.y + 9.0, w: 1.0, h: 2.0 }, 0x70FFFFFF)));
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
        text(out, &shown, FIELD.x + FIELD.w / 2.0, FIELD.y + 2.0, colour);
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
            text(out, &(k + 1).to_string(), b.x + b.w / 2.0, b.y + 1.0, if on { 0xFFFFFF } else { 0x8C93A0 });
        }
    }
}

/// A segment's icon, one and a half times the hotbar size, dimmed unless it is pointed at or loaded (its name shows under the ring
/// while it is pointed at).
fn segment_label(out: &mut Vec<Draw>, laser: &Laser, mid: f32, bright: bool) {
    let c = polar(mid, (R_IN + R_OUT) / 2.0 + 2.0);
    let scale = 1.5;
    out.push(Draw::Item((
        "minecraft:paper".to_string(),
        laser.icon_model.to_string(),
        Point { x: c.x - 8.0 * scale, y: c.y - 8.0 * scale },
        scale,
    )));
    if !bright {
        sector(out, mid - 0.5, mid + 0.5, R_IN + 4.0, R_OUT - 2.0, 0x50101318);
    }
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
            assert_eq!(spot(QUALITY.x + QUALITY.w / 2.0, QUALITY.y + QUALITY.h / 2.0, true, page), Some(Spot::Quality));
        }
        let corner = (MSG.x * MSG.x + (MSG.y + MSG.h) * (MSG.y + MSG.h)).sqrt();
        assert!(corner > R_OUT + 10.0 && MSG.x > tab(pages() - 1).x + TAB_W + 4.0 && MSG.y + MSG.h < arrow(1).y);
        let corner = (HUD.x * HUD.x + (HUD.y + HUD.h) * (HUD.y + HUD.h)).sqrt();
        assert!(corner > R_OUT + 10.0 && HUD.y + HUD.h < arrow(1).y);
        let corner = (QUALITY.x * QUALITY.x + (QUALITY.y + QUALITY.h) * (QUALITY.y + QUALITY.h)).sqrt();
        assert!(corner > R_OUT + 10.0 && QUALITY.y + QUALITY.h < arrow(1).y && QUALITY.y >= HUD.y + HUD.h);
        // the stop button: clickable only while a strike is under way, clear of the ring, the tabs and the arrows
        let (sx, sy) = (STOP.x + STOP.w / 2.0, STOP.y + STOP.h / 2.0);
        assert_eq!(spot(sx, sy, false, 0), Some(Spot::Stop));
        let mut w = Wheel::on_page(0, 1.0);
        w.hover_at(sx, sy, 0);
        assert_eq!(w.hover, None);
        w.striking = true;
        w.hover_at(sx, sy, 0);
        assert_eq!(w.hover, Some(Spot::Stop));
        let corner = ((STOP.x + STOP.w).powi(2) + (STOP.y + STOP.h).powi(2)).sqrt();
        assert!(corner > R_OUT + 10.0 && STOP.x + STOP.w < tab(0).x - 4.0 && STOP.y + STOP.h < arrow(0).y);
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
        // switch and the title, and on the smallest GUI (240 high)
        for page in 0..pages() {
            for row in [false, true] {
                assert_eq!(spot(BAR.x + 2.0, BAR.y + 7.0, row, page), Some(Spot::FlyBar));
                assert_eq!(spot(BAR.x + BAR.w - 2.0, BAR.y + 7.0, row, page), Some(Spot::FlyBar));
                assert_eq!(spot(FIELD.x + FIELD.w / 2.0, FIELD.y + 7.0, row, page), Some(Spot::FlyField));
            }
        }
        assert!(FIELD.y + FIELD.h < MSG.y - 2.0 && FLY_Y + BAR.h < TITLE_Y - 2.0 && FLY_Y - 3.0 >= -120.0);
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
            assert_eq!(w.rows(other), Rows::None);
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
            assert_eq!(w.rows(other), Rows::None);
            assert_eq!(w.row_laser(s), Some(s));
        }
        // a loaded ship keeps its rows on the other page too
        let w = Wheel::on_page(0, 1.0);
        assert_eq!(w.row_laser(ship("downfall")), Some(ship("downfall")));
    }
    #[test]
    fn payload_sound_row() {
        let pl = ship("payload");
        // its two buttons clickable while its row shows, nothing there otherwise, clear of the ring and of each other
        for k in 0..SOUNDS.len() {
            let b = sound_button(k);
            let (x, y) = (b.x + b.w / 2.0, b.y + b.h / 2.0);
            assert_eq!(spot(x, y, Rows::Payload, page_of(pl)), Some(Spot::Sound(k)));
            assert_ne!(spot(x, y, Rows::None, page_of(pl)), Some(Spot::Sound(k)));
            assert_ne!(spot(x, y, Rows::Ship, page_of(pl)), Some(Spot::Sound(k)));
            assert!(b.y > R_OUT + 10.0 && b.x >= -160.0 && b.x + b.w <= 160.0 && b.y + b.h <= 120.0);
            // (each hint fits the line under the ring)
            assert!(SOUNDS[k].1.len() * 6 <= 320, "{}", SOUNDS[k].1);
        }
        assert!(sound_button(1).x >= sound_button(0).x + BTN_W + 2.0);
        // the label's room left of the first button holds it
        assert!("BLAST SOUND".len() as f32 * 6.0 <= SOUND_LABEL_W && sound_button(0).x - SOUND_LABEL_W >= -160.0);
        // pointing at the Payload opens its row (not a ship's), and it stays open on the way down to it
        let mut w = Wheel::on_page(page_of(pl), 1.0);
        let other = 0;
        assert_eq!(w.rows(other), Rows::None);
        let c = polar(segment_angle(pl % PAGE), 60.0);
        w.hover_at(c.x, c.y, other);
        assert_eq!((w.row_laser(other), w.rows(other)), (Some(pl), Rows::Payload));
        let b = sound_button(1);
        w.hover_at(b.x + 4.0, b.y + 4.0, other);
        assert_eq!(w.hover, Some(Spot::Sound(1)));
        assert_eq!(w.rows(other), Rows::Payload);
        // (and where a ship's buttons would be, nothing of theirs)
        let b = button(1, 0);
        w.hover_at(b.x + 4.0, b.y + 4.0, other);
        assert!(!matches!(w.hover, Some(Spot::Arrival(_) | Spot::Colour(_))));
        // loaded, it shows on any page; drawn, its picked button is lit
        assert_eq!(Wheel::on_page(0, 1.0).rows(pl), Rows::Payload);
        let lit = |alt: bool| -> Vec<u32> {
            Wheel::on_page(0, 1.0)
                .draws(pl, true, true, true, 0, 0, &[0; 16], alt, true, 8)
                .into_iter()
                .filter_map(|d| if let Draw::Text((t, _, c, _)) = d { (t == "MAIN" || t == "ALT").then_some(c) } else { None })
                .collect()
        };
        assert_eq!(lit(false), vec![LASERS[pl].rgb, 0x9AA2AE]);
        assert_eq!(lit(true), vec![0x9AA2AE, LASERS[pl].rgb]);
    }
    #[test]
    fn nuke_cloud_row() {
        let nk = ship("nuke");
        // its arrows (and the name) clickable while its row shows, nothing there otherwise
        for (k, b) in [(0, cloud_button(0)), (1, cloud_button(1)), (1, cloud_name())] {
            let (x, y) = (b.x + b.w / 2.0, b.y + b.h / 2.0);
            assert_eq!(spot(x, y, Rows::Nuke, page_of(nk)), Some(Spot::Cloud(k)));
            assert_ne!(spot(x, y, Rows::Payload, page_of(nk)), Some(Spot::Cloud(k)));
            assert_ne!(spot(x, y, Rows::None, page_of(nk)), Some(Spot::Cloud(k)));
            assert!(b.y > R_OUT + 10.0 && b.x >= -160.0 && b.x + b.w <= 160.0 && b.y + b.h <= 120.0);
        }
        assert!(cloud_name().x >= cloud_button(0).x + CLOUD_ARROW_W + 2.0 && cloud_button(1).x >= cloud_name().x + CLOUD_NAME_W + 2.0);
        // every name fits its box, the label its room, every hint the line under the ring
        assert!("CLOUD".len() as f32 * 6.0 <= CLOUD_LABEL_W && cloud_row_x() >= -160.0);
        for c in 0..CLOUDS.len() {
            assert!(CLOUDS[c].0.len() as f32 * 6.0 + 4.0 <= CLOUD_NAME_W, "{}", CLOUDS[c].0);
            let w = Wheel { hover: Some(Spot::Cloud(0)), ..Wheel::on_page(page_of(nk), 1.0) };
            for d in w.draws(nk, true, true, true, 0, 0, &[0; 16], false, true, c) {
                if let Draw::Text((t, ..)) = d {
                    assert!(t.len() <= 320 / 6 + 4, "{t}");
                }
            }
        }
        // the keys
        assert_eq!(parse_cloud("current"), Some(CLOUDS.len() - 1));
        assert_eq!(parse_cloud("9"), Some(8));
        assert_eq!(parse_cloud("v1"), Some(0));
        assert_eq!(parse_cloud("0"), None);
        assert_eq!(parse_cloud("10"), None);
        assert_eq!(cloud_key(4), "5");
        assert_eq!(cloud_key(8), "current");
        // pointing at the Nuke opens its row; loaded, it shows on any page, its name drawn
        let mut w = Wheel::on_page(page_of(nk), 1.0);
        let c = polar(segment_angle(nk % PAGE), 60.0);
        w.hover_at(c.x, c.y, 0);
        assert_eq!(w.rows(0), Rows::Nuke);
        assert_eq!(Wheel::on_page(0, 1.0).rows(nk), Rows::Nuke);
        let names: Vec<String> = Wheel::on_page(0, 1.0)
            .draws(nk, true, true, true, 0, 0, &[0; 16], false, true, 4)
            .into_iter()
            .filter_map(|d| if let Draw::Text((t, ..)) = d { Some(t) } else { None })
            .collect();
        assert!(names.iter().any(|t| t == "v5 BOIL-UP"));
    }
    #[test]
    fn fits_the_smallest_gui() {
        // the game's GUI is at least 320 x 240 at any window size and GUI scale: everything stays inside it
        let (hw, hh) = (160.0, 120.0);
        let mut boxes = vec![BAR, FIELD, MSG, HUD, QUALITY, STOP, arrow(0), arrow(1), Rect { x: -120.0, y: FLY_Y - 3.0, w: 220.0, h: BAR.h + 6.0 }];
        boxes.extend((0..pages()).map(tab));
        for (r, items) in ROWS.iter().enumerate() {
            boxes.extend((0..items.len()).map(|k| button(r, k)));
        }
        let nuke_row = [cloud_button(0), cloud_name(), cloud_button(1)];
        for b in boxes.iter().chain(&nuke_row) {
            assert!(b.x >= -hw && b.x + b.w <= hw && b.y >= -hh && b.y + b.h <= hh, "{:?}", (b.x, b.y, b.w, b.h));
        }
        // and none on another (but the fly row's span, round its bar and field)
        let apart = |a: &Rect, b: &Rect| a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y;
        let clickable: Vec<&Rect> = boxes.iter().filter(|b| b.w != 220.0).collect();
        for (i, a) in clickable.iter().enumerate() {
            for b in &clickable[i + 1..] {
                assert!(apart(a, b), "{:?} on {:?}", (a.x, a.y, a.w, a.h), (b.x, b.y, b.w, b.h));
            }
        }
        assert!(R_OUT + 3.0 + 4.0 <= INFO_Y && INFO_Y + 9.0 + 4.0 <= ROW_Y);
        // every blurb in two lines that fit across, under the ring
        for l in LASERS {
            let lines = wrap(l.blurb, BLURB_CHARS);
            assert!(lines.len() <= BLURB_LINES, "{}", l.title);
            assert!(lines.iter().all(|s| s.len() * 6 <= 2 * hw as usize), "{}", l.title);
        }
        assert!(INFO_Y + 11.0 + (BLURB_LINES as f32 - 1.0) * 10.0 + 9.0 <= hh);
        // the rows clear of the ring, the blurb's room and each other; the title clear of the tabs and the fly row
        assert!(button(1, 0).y > button(0, 0).y + BTN_H);
        assert!(TITLE_Y + 9.0 + 4.0 <= TAB_Y && TAB_Y + TAB_H + 4.0 <= -R_OUT - 3.0 && FLY_Y + BAR.h + 3.0 + 4.0 <= TITLE_Y);
    }
}
