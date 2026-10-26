//! Orbital Laser, a Horizon mod. Hold the Orbital Laser Designator on a target
//! and the strike lands there: a beam from orbit, a crater to bedrock, and what
//! each laser leaves behind. Right-click the Orbital Remote (or press R) for the
//! laser wheel. `/orbital give` hands you both items.
//!
//! It uses Horizon's stock mod interfaces: `input` (the two items'
//! right-clicks and the wheel's key), `ui` (the wheel, a screen of the game's
//! widgets), `game-read` (aiming: `game.raycast`), `command` (the crater's
//! block changes, the sounds and the messages, as vanilla commands run
//! quietly, one batch a tick: it needs cheats), `render` (the camera's
//! jolts), `hud` (the status panel), `storage` (the chosen laser and the
//! settings) and `registries` (the items, their textures and the sounds, in
//! assets/ and data/). The strike's light (the post
//! pass in shaders/) waits for Horizon's native shader API.
mod lasers;
mod strike;
mod wheel;

use horizon_mod_sdk::{
    Mod, Registration, command, game,
    hud::{self, Corner, Line},
    input::{self, Event},
    log, render, storage, ui,
};
use lasers::{LASERS, is_ship};
use std::collections::VecDeque;
use strike::{APPROACHES, ARRIVALS, Act, COLOUR_RGB, COLOURS, FIRE, Target};

pub(crate) const DESIGNATOR: &str = "orbital:laser_designator";
const REMOTE: &str = "orbital:remote";
/// Ticks of holding the designator on a target before it fires.
const LOCK_TICKS: u32 = 14;
/// The strike's light, for when Horizon has a native shader API: strike.wgsl, and the downfall's own pass
/// (strike.wgsl up to its fs_main, less the other lasers' own functions, marked `[lasers pass only]`, then
/// shaders/downfall.wgsl).
#[cfg(test)]
const SHADER: &str = include_str!("../shaders/strike.wgsl");
#[cfg(test)]
const DOWNFALL_PASS: &str = include_str!("../shaders/downfall.wgsl");
#[cfg(test)]
fn downfall_pass() -> String {
    let mut out = String::with_capacity(SHADER.len() + DOWNFALL_PASS.len());
    let mut skip = false;
    for line in SHADER.lines() {
        if line.starts_with("@fragment") {
            break;
        }
        if line.starts_with("// [lasers pass only]") {
            skip = true;
        }
        if !skip {
            out.push_str(line);
            out.push('\n');
        }
        if line.starts_with("// [end lasers pass only]") {
            skip = false;
        }
    }
    out.push_str(DOWNFALL_PASS);
    out
}
const SETTINGS: &str = "settings";
/// Blocks a tick's world changes may touch (see `strike::block_cost`): more waits for the next tick, so a big strike
/// carves its crater over a few seconds instead of freezing the game for one.
const BLOCK_BUDGET: u64 = 20_000;
/// Commands sent a tick at most, as one `command.run-quiet` batch: Horizon's servers run 64 a player a tick, so the
/// rest wait here rather than in the server's queue.
const COMMANDS_PER_TICK: usize = 64;

struct Strike {
    plan: Vec<(f32, Act)>,
    next: usize,
    ticks: u32,
    /// Seconds it runs (the laser's `length`).
    length: f32,
    /// Stages due that wait for a tick of their own (`tick_strike` works out one a tick).
    waiting: VecDeque<strike::Stage>,
}
impl Strike {
    /// Work out a stage of the plan and merge what it gives in after what has run (both are in order, so the sort only
    /// merges two runs).
    fn work_out(&mut self, job: strike::Stage) {
        let mut rest = self.plan.split_off(self.next);
        rest.extend(job());
        rest.sort_by(|a, b| a.0.total_cmp(&b.0));
        self.plan.extend(rest);
    }
}

/// What is kept between sessions.
struct Settings {
    laser: usize,
    terrain: bool,
    messages: bool,
    hud: bool,
    approach: usize,
    arrival: usize,
    colours: Vec<usize>,
}

/// A ship laser's colour until one is picked (strike::COLOURS): the Mothership green, the Downfall red.
fn default_colour(i: usize) -> usize {
    usize::from(LASERS[i].key == "downfall")
}

/// `playsound` for a sound following the player (`at` none) or at a point.
fn playsound(event: &str, at: Option<[f64; 3]>, volume: f32, pitch: f32) -> String {
    let at = at.map_or("~ ~ ~".to_string(), |[x, y, z]| format!("{x:.2} {y:.2} {z:.2}"));
    format!("playsound {event} master @s {at} {volume:.2} {pitch:.2}")
}

struct Orbital {
    /// Commands due now (sounds, messages, effects), in order: they go first.
    due: VecDeque<String>,
    /// World changes waiting for room in a tick's block budget, in order; they outlive the strike that made them.
    carving: VecDeque<(u64, String)>,
    /// World changes that wait for spare block budget (`Act::Spare`): what stands high over a blast.
    spare: VecDeque<(u64, String)>,
    laser: usize,
    terrain: bool,
    /// Whether the strikes put their messages over the hotbar (the replies to the player's own clicks always show).
    messages: bool,
    /// Whether the status panel shows at the top right while the player holds one of the items.
    hud: bool,
    /// Which way the ship lasers' ship comes in (strike::APPROACHES), and how it arrives (strike::ARRIVALS).
    approach: usize,
    arrival: usize,
    /// Each laser's ship colour (strike::COLOURS; only the ship lasers use theirs).
    colours: Vec<usize>,
    /// Ticks the designator has been held, while it is.
    aiming: Option<u32>,
    /// Seconds the next strike starts in at (`/orbital skip`, for looking at one moment of it; terrain off only).
    skip: f32,
    strike: Option<Strike>,
    /// The wheel is open (else its widgets may be on the mod's settings page).
    wheel: bool,
    /// The HUD panel last sent.
    panel: Vec<(String, u32)>,
}

impl Orbital {
    fn save(&self) {
        let mut text = format!(
            "laser={}\nterrain={}\nmessages={}\nhud={}\napproach={}\narrival={}\n",
            LASERS[self.laser].key,
            u8::from(self.terrain),
            u8::from(self.messages),
            u8::from(self.hud),
            APPROACHES[self.approach].key,
            ARRIVALS[self.arrival].key,
        );
        for (i, l) in LASERS.iter().enumerate() {
            if is_ship(l) {
                text += &format!("colour_{}={}\n", l.key, COLOURS[self.colours[i]].key);
            }
        }
        if let Err(e) = storage::set(SETTINGS, text.as_bytes()) {
            log::write(log::Level::Warn, &format!("settings not saved: {e}"));
        }
    }
    fn load() -> Settings {
        let text = storage::get(SETTINGS).map(|b| String::from_utf8_lossy(&b).into_owned()).unwrap_or_default();
        let mut laser = 0;
        let mut terrain = true;
        let mut messages = true;
        let mut hud = true;
        let mut approach = 0;
        let mut arrival = 0;
        let mut colours: Vec<usize> = (0..LASERS.len()).map(default_colour).collect();
        for line in text.lines() {
            match line.split_once('=') {
                Some(("laser", k)) => laser = LASERS.iter().position(|l| l.key == k).unwrap_or(0),
                Some(("terrain", v)) => terrain = v != "0",
                Some(("messages", v)) => messages = v != "0",
                Some(("hud", v)) => hud = v != "0",
                Some(("approach", k)) => approach = APPROACHES.iter().position(|a| a.key == k).unwrap_or(0),
                Some(("arrival", k)) => arrival = ARRIVALS.iter().position(|a| a.key == k).unwrap_or(0),
                Some((k, v)) if k.starts_with("colour_") => {
                    if let (Some(i), Some(c)) = (LASERS.iter().position(|l| l.key == &k[7..]), COLOURS.iter().position(|c| c.key == v)) {
                        colours[i] = c;
                    }
                }
                _ => {}
            }
        }
        Settings { laser, terrain, messages, hud, approach, arrival, colours }
    }

    // ---- commands ----
    fn run(&mut self, cmd: String) {
        self.due.push_back(cmd);
    }
    fn sound(&mut self, event: &str, at: Option<[f64; 3]>, volume: f32, pitch: f32) {
        self.run(playsound(event, at, volume, pitch));
    }
    fn actionbar(&mut self, text: &str, color: &str) {
        self.run(format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#));
    }
    /// Hands the game this tick's commands as one quiet batch (nothing of them in the chat): the ones due first, then
    /// the waiting world changes in order as far as the tick's block budget goes (at least one a tick), then with what
    /// is left of it the ones that wait for spare budget.
    fn flush(&mut self) {
        let mut lines = Vec::new();
        while lines.len() < COMMANDS_PER_TICK
            && let Some(c) = self.due.pop_front()
        {
            lines.push(c);
        }
        let mut spent = 0;
        while lines.len() < COMMANDS_PER_TICK
            && let Some((cost, _)) = self.carving.front()
        {
            if spent > 0 && spent + cost > BLOCK_BUDGET {
                break;
            }
            spent += cost;
            if let Some((_, c)) = self.carving.pop_front() {
                lines.push(c);
            }
        }
        while lines.len() < COMMANDS_PER_TICK
            && self.carving.is_empty()
            && let Some((cost, _)) = self.spare.front()
        {
            if spent > 0 && spent + cost > BLOCK_BUDGET {
                break;
            }
            spent += cost;
            if let Some((_, c)) = self.spare.pop_front() {
                lines.push(c);
            }
        }
        if !lines.is_empty() {
            command::run_quiet(&lines);
        }
    }

    // ---- the wheel ----
    fn state(&self) -> wheel::State<'_> {
        wheel::State {
            laser: self.laser,
            terrain: self.terrain,
            messages: self.messages,
            hud: self.hud,
            approach: self.approach,
            arrival: self.arrival,
            colours: &self.colours,
        }
    }
    /// The wheel, or the settings page, again after a change.
    fn show_wheel(&self) {
        if self.wheel {
            ui::open_screen(&wheel::screen(&self.state()));
        } else {
            ui::set_settings(&wheel::widgets(&self.state()));
        }
    }
    fn open_wheel(&mut self) {
        self.wheel = true;
        self.show_wheel();
        self.sound("minecraft:ui.button.click", None, 0.5, 1.4);
    }
    fn click(&mut self, on: bool) {
        self.save();
        self.sound("minecraft:ui.button.click", None, 0.6, if on { 1.6 } else { 1.0 });
        self.show_wheel();
    }
    /// A laser loaded from the wheel: it closes, and the action bar says so.
    fn loaded(&mut self, what: String) {
        self.save();
        if self.wheel {
            ui::close_screen();
            self.wheel = false;
        } else {
            self.show_wheel();
        }
        let l = LASERS[self.laser];
        self.actionbar(&what, l.color);
        self.sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
    }
    fn wheel_select(&mut self, id: u32, row: u32) {
        let row = row as usize;
        if id == wheel::LASER_LIST && row < LASERS.len() {
            self.laser = row;
            self.loaded(format!("{} LOADED", LASERS[self.laser].title));
            return;
        }
        if id != wheel::SWITCHES {
            return;
        }
        let ship = self.laser;
        match wheel::switches(ship).get(row) {
            Some(wheel::Switch::Approach) => {
                self.approach = (self.approach + 1) % APPROACHES.len();
                self.click(true);
            }
            Some(wheel::Switch::Arrival) => {
                self.arrival = (self.arrival + 1) % ARRIVALS.len();
                self.click(true);
            }
            Some(wheel::Switch::Colour) => {
                self.colours[ship] = (self.colours[ship] + 1) % COLOURS.len();
                self.click(true);
            }
            Some(wheel::Switch::Terrain) => {
                self.terrain = !self.terrain;
                self.click(self.terrain);
            }
            Some(wheel::Switch::Messages) => {
                self.messages = !self.messages;
                self.click(self.messages);
            }
            Some(wheel::Switch::Hud) => {
                self.hud = !self.hud;
                self.update_panel();
                self.click(self.hud);
            }
            None => {}
        }
    }

    // ---- the strike ----
    fn fire(&mut self) {
        let laser = LASERS[self.laser];
        let Some(hit) = game::raycast(laser.range) else {
            self.actionbar("NO TARGET IN RANGE", "gray");
            return;
        };
        let player = game::get_player();
        let dimension = player.as_ref().map_or("minecraft:overworld".to_string(), |p| p.dimension.clone());
        let me = player.as_ref().map_or([hit.x, hit.y, hit.z + 1.0], |p| [p.x, p.y, p.z]);
        let target = Target { block: [hit.block_x, hit.block_y, hit.block_z], point: [hit.x, hit.y, hit.z] };
        let clock = game::get_clock().map_or(0, |c| c.game_time);
        let seed = (clock % 997 + 1) as f32; // a fresh look every strike
        let plan = strike::plan(laser, &target, self.terrain, &dimension, seed, me, self.approach);
        log::write(log::Level::Info, &format!("strike [{}] at {} {} {}", laser.key, hit.block_x, hit.block_y, hit.block_z));
        // (started part way in: what was due before then is left out, sounds and world changes alike)
        let ticks = (self.skip.min(laser.length - 1.0) * 20.0) as u32;
        let next = plan.iter().take_while(|e| e.0 < ticks as f32 * 0.05).count();
        self.skip = 0.0;
        self.strike = Some(Strike { plan, next, ticks, length: laser.length, waiting: Default::default() });
    }
    /// One tick of the strike: everything due by now, in one batch.
    fn tick_strike(&mut self) {
        let Some(s) = &mut self.strike else {
            return;
        };
        s.ticks += 1;
        let now = s.ticks as f32 * 0.05;
        let mut jolts: Vec<(f32, f32)> = Vec::new();
        // one stage worked out a tick at most (each is a tick's worth of work, and a tick has a fuel limit): when more
        // fall due together, the rest wait for the ticks after, while everything else goes on time (each is due a
        // little before its own events)
        let mut worked_out = false;
        if let Some(job) = s.waiting.pop_front() {
            s.work_out(job);
            worked_out = true;
        }
        while let Some((t, _)) = s.plan.get(s.next) {
            if *t > now {
                break;
            }
            let (_, act) = std::mem::replace(&mut s.plan[s.next], (0.0, Act::Cmd(String::new())));
            s.next += 1;
            match act {
                // the strike's messages over the hotbar, unless they are switched off
                Act::Cmd(c) if !self.messages && c.starts_with("title @s actionbar") => {}
                Act::Cmd(c) => match strike::block_cost(&c) {
                    Some(cost) => self.carving.push_back((cost, c)),
                    None => self.due.push_back(c),
                },
                Act::Sound { event, at, volume, pitch } => self.due.push_back(playsound(&event, at, volume, pitch)),
                Act::Shake { strength, seconds } => jolts.push((strength, seconds)),
                Act::Spare(c) => self.spare.push_back((strike::block_cost(&c).unwrap_or(1), c)),
                Act::Later(job) if worked_out => s.waiting.push_back(job),
                Act::Later(job) => {
                    // more of the plan, worked out now it is due
                    s.work_out(job);
                    worked_out = true;
                }
            }
        }
        if !jolts.is_empty() {
            // the jolts due this tick as one (the game adds jolts up the same way)
            let strength = jolts.iter().map(|j| j.0 * j.0).sum::<f32>().sqrt().min(1.0);
            let seconds = jolts.iter().map(|j| j.1).fold(0.0, f32::max);
            render::shake(strength, seconds);
        }
        if now >= s.length {
            self.strike = None;
        }
    }

    /// While the player holds one of the items: which laser is loaded.
    fn update_panel(&mut self) {
        let holding = self.hud && input::held().is_some_and(|h| h.id == DESIGNATOR || h.id == REMOTE);
        let lines: Vec<(String, u32)> = if holding {
            let l = LASERS[self.laser];
            let mut lines = vec![
                ("Orbital Laser".to_string(), 0xFFFFFF),
                (format!("Laser: {}", l.title), l.rgb),
                (format!("Terrain damage: {}", if self.terrain { "on" } else { "off" }), 0xA8B0BC),
                (format!("Messages: {}", if self.messages { "on" } else { "off" }), 0xA8B0BC),
            ];
            if is_ship(l) {
                lines.push((format!("Approach: {}", APPROACHES[self.approach].label), 0xA8B0BC));
                lines.push((format!("Arrival: it {}", ARRIVALS[self.arrival].label), 0xA8B0BC));
                lines.push((format!("Colour: {}", COLOURS[self.colours[self.laser]].label), COLOUR_RGB[self.colours[self.laser]]));
            }
            if self.strike.is_some() {
                lines.push(("Strike in progress".to_string(), 0xFF8A65));
            } else {
                lines.push(("R or the remote: laser wheel".to_string(), 0x7C8594));
            }
            lines
        } else {
            Vec::new()
        };
        if lines != self.panel {
            if lines.is_empty() {
                hud::clear();
            } else {
                let panel: Vec<Line> = lines.iter().map(|(t, c)| Line { text: t.clone(), color: *c }).collect();
                hud::set_panel(Corner::TopRight, &panel);
            }
            self.panel = lines;
        }
    }
}

impl Mod for Orbital {
    fn init() -> Result<(Self, Registration), String> {
        input::claim_items(&[DESIGNATOR.to_string(), REMOTE.to_string()]);
        if let Err(e) = input::register_key("wheel", "Open the laser wheel", "key.keyboard.r") {
            log::write(log::Level::Warn, &format!("the wheel's key: {e}"));
        }
        let Settings { laser, terrain, messages, hud, approach, arrival, colours } = Orbital::load();
        let state = Orbital {
            due: VecDeque::new(),
            carving: VecDeque::new(),
            spare: VecDeque::new(),
            laser,
            terrain,
            messages,
            hud,
            approach,
            arrival,
            colours,
            aiming: None,
            skip: 0.0,
            strike: None,
            wheel: false,
            panel: Vec::new(),
        };
        Ok((state, Registration::new().command("orbital").on_tick()))
    }

    fn tick(&mut self, _tick: u64) {
        for event in input::poll() {
            match event {
                Event::UseStart(u) if u.item.id == DESIGNATOR => {
                    if self.strike.is_some() {
                        self.actionbar("STRIKE IN PROGRESS", "gray");
                    } else {
                        self.aiming = Some(0);
                    }
                }
                Event::UseStart(u) if u.item.id == REMOTE => self.open_wheel(),
                Event::UseStop(u) if u.item.id == DESIGNATOR => self.aiming = None,
                Event::KeyDown(k) if k == "wheel" => self.open_wheel(),
                _ => {}
            }
        }
        if let Some(n) = self.aiming {
            let l = LASERS[self.laser];
            if n >= LOCK_TICKS {
                self.aiming = None;
                self.fire();
            } else {
                if n % 4 == 0 {
                    self.actionbar(&format!("ACQUIRING TARGET {}  [{}]", ".".repeat(1 + n as usize / 4), l.title), l.color);
                }
                self.aiming = Some(n + 1);
            }
        }
        self.tick_strike();
        self.update_panel();
        self.flush();
    }

    fn ui_select(&mut self, id: u32, row: u32) {
        self.wheel_select(id, row);
    }
    fn ui_closed(&mut self) {
        self.wheel = false;
    }
    fn ui_settings_opened(&mut self) {
        ui::set_settings(&wheel::widgets(&self.state()));
    }

    fn command(&mut self, _name: &str, args: &str) -> Result<Option<String>, String> {
        self.orbital(args)
    }
}

impl Orbital {
    /// `/orbital ...`
    fn orbital(&mut self, args: &str) -> Result<Option<String>, String> {
        let mut words = args.split_whitespace();
        match (words.next(), words.next()) {
            (Some("give"), _) => {
                self.run(format!("give @s {DESIGNATOR}"));
                self.run(format!("give @s {REMOTE}"));
                Ok(Some("Orbital Laser Designator and Orbital Remote added to your inventory".into()))
            }
            (Some("wheel"), _) => {
                self.open_wheel();
                Ok(None)
            }
            (Some("approach"), Some(k)) if APPROACHES.iter().any(|a| a.key == k) => {
                self.approach = APPROACHES.iter().position(|a| a.key == k).unwrap_or(0);
                self.save();
                Ok(Some(format!("The ship comes in {}", APPROACHES[self.approach].label)))
            }
            (Some("arrival"), Some(k)) if ARRIVALS.iter().any(|a| a.key == k) => {
                self.arrival = ARRIVALS.iter().position(|a| a.key == k).unwrap_or(0);
                self.save();
                Ok(Some(format!("The ship {}", ARRIVALS[self.arrival].label)))
            }
            (Some("terrain"), Some(v @ ("on" | "off"))) => {
                self.terrain = v == "on";
                self.save();
                Ok(Some(format!("Terrain damage {v}")))
            }
            (Some("colour" | "color"), Some(k)) if COLOURS.iter().any(|c| c.key == k) => {
                let l = LASERS[self.laser];
                if !is_ship(l) {
                    return Err("The colour is the ship's: load the Mothership or the Downfall first".into());
                }
                self.colours[self.laser] = COLOURS.iter().position(|c| c.key == k).unwrap_or(0);
                self.save();
                Ok(Some(format!("The {} is lit {k}", l.title)))
            }
            (Some("skip"), Some(v)) => {
                let t: f32 = v.parse().map_err(|_| "/orbital skip SECONDS (0 to start at the beginning)".to_string())?;
                if self.terrain && t > 0.0 {
                    return Err("Skipping leaves out what the strike does to the land before then: /orbital terrain off first".into());
                }
                self.skip = t.max(0.0);
                Ok(Some(format!("The next strike starts {t} s in")))
            }
            (Some("hud"), Some(v @ ("on" | "off"))) => {
                self.hud = v == "on";
                self.save();
                self.update_panel();
                Ok(Some(format!("Status panel {v}")))
            }
            (Some("messages"), Some(v @ ("on" | "off"))) => {
                self.messages = v == "on";
                self.save();
                Ok(Some(format!("Strike messages {v}")))
            }
            (Some(key), None) if LASERS.iter().any(|l| l.key == key) => {
                self.laser = LASERS.iter().position(|l| l.key == key).unwrap_or(0);
                self.save();
                let l = LASERS[self.laser];
                Ok(Some(format!("{} loaded: {}", l.title, l.blurb)))
            }
            _ => Err(format!(
                "/orbital give | wheel | terrain on|off | messages on|off | hud on|off | skip SECONDS | approach {} | arrival {} | colour {} | {}",
                APPROACHES.iter().map(|a| a.key).collect::<Vec<_>>().join("|"),
                ARRIVALS.iter().map(|a| a.key).collect::<Vec<_>>().join("|"),
                COLOURS.iter().map(|a| a.key).collect::<Vec<_>>().join("|"),
                LASERS.iter().map(|l| l.key).collect::<Vec<_>>().join(" | ")
            )),
        }
    }
}

horizon_mod_sdk::export_mod!(Orbital);

// The shader runs the impact at FIRE seconds into the strike.
const _: () = {
    let mut i = 0;
    while i < LASERS.len() {
        assert!(FIRE < LASERS[i].length);
        i += 1;
    }
};

#[cfg(test)]
mod tests {
    #[test]
    fn downfall_pass_is_whole_and_small() {
        // the downfall's pass leaves out the other lasers' own functions and fs_main, keeps what it uses, and is under
        // the game's 256 KiB
        let p = super::downfall_pass();
        for gone in ["fn singularity(", "fn meteor_storm(", "fn mothership(", "fn fs_main(in: StageIn) -> @location(0) vec4<f32> {\n    if (th_is"] {
            assert!(!p.contains(gone), "{gone}");
        }
        for kept in ["fn bh_lens(", "fn ms_hull(", "fn ms_frame(", "fn downfall(", "fn ms_air("] {
            assert!(p.contains(kept), "{kept}");
        }
        assert_eq!(p.matches("@fragment").count(), 1);
        assert!(p.len() <= 256 << 10 && super::SHADER.len() <= 256 << 10);
    }
}
