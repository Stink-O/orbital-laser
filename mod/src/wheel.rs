//! The laser wheel (capability `ui`), as a screen of the game's own widgets: a
//! list of the lasers (picking one loads it and closes the screen), and a list
//! of the strikes' switches, where picking a row flips or cycles it. While a
//! ship laser is loaded, three more rows cycle which way its ship comes in,
//! how it arrives and the colour it is lit in. The same widgets fill the mod's
//! page in Options > Mods. Lists keep the screen small enough for a 720p
//! window at the default GUI scale.
use crate::lasers::{LASERS, is_ship};
use crate::strike::{APPROACHES, ARRIVALS, COLOURS};
use horizon_mod_sdk::ui::{ListWidget, Screen, Widget};

/// The widgets' ids, which `ui-events::select` echoes.
pub const LASER_LIST: u32 = 1;
pub const SWITCHES: u32 = 2;

/// A row of the switches' list.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Switch {
    Approach,
    Arrival,
    Colour,
    Terrain,
    Messages,
    Hud,
}

/// What the wheel shows.
pub struct State<'a> {
    pub laser: usize,
    pub terrain: bool,
    pub messages: bool,
    pub hud: bool,
    pub approach: usize,
    pub arrival: usize,
    pub colours: &'a [usize],
}

fn on_off(on: bool) -> &'static str {
    if on { "ON" } else { "OFF" }
}

/// The switches' rows, in order: the ship's three for a ship laser, then the three every laser has.
pub fn switches(laser: usize) -> Vec<Switch> {
    let mut rows = Vec::new();
    if is_ship(LASERS[laser]) {
        rows.extend([Switch::Approach, Switch::Arrival, Switch::Colour]);
    }
    rows.extend([Switch::Terrain, Switch::Messages, Switch::Hud]);
    rows
}

fn label(s: &State, row: Switch) -> String {
    match row {
        Switch::Approach => format!("Approach: {}", APPROACHES[s.approach].button),
        Switch::Arrival => format!("Arrival: {}", ARRIVALS[s.arrival].button),
        Switch::Colour => format!("Colour: {}", COLOURS[s.colours[s.laser]].button),
        Switch::Terrain => format!("Terrain damage: {}", on_off(s.terrain)),
        Switch::Messages => format!("Strike messages: {}", on_off(s.messages)),
        Switch::Hud => format!("Status panel: {}", on_off(s.hud)),
    }
}

/// The wheel's widgets, top to bottom.
pub fn widgets(s: &State) -> Vec<Widget> {
    vec![
        Widget::List(ListWidget {
            id: LASER_LIST,
            rows: LASERS.iter().map(|l| l.title.to_string()).collect(),
            selected: Some(s.laser as u32),
        }),
        Widget::List(ListWidget {
            id: SWITCHES,
            rows: switches(s.laser).into_iter().map(|row| label(s, row)).collect(),
            selected: None,
        }),
    ]
}

/// The screen: the widgets under the mod's title.
pub fn screen(s: &State) -> Screen {
    Screen {
        title: "Orbital Laser".into(),
        widgets: widgets(s),
    }
}
