//! Orbital Laser, a Horizon mod. Hold the Orbital Laser Designator on a target
//! and the strike lands there: a beam from orbit, a crater to bedrock, and what
//! each laser leaves behind. Right-click the Orbital Remote (or press R) for the
//! laser wheel (rebind R in Options > Controls). `/orbital give` hands you both items.
//!
//! It uses the game's mod capabilities: `input` (the two items' right-clicks
//! and the wheel's key), `ui` (the wheel), `render` (the strike's post pass,
//! shaders/strike.wgsl), `world` (aiming, the crater's block changes and the
//! sounds), `hud` (the status panel), `storage` (the chosen laser) and
//! `registries` (the items, their textures and the sounds, in assets/ and data/).
mod lasers;
mod strike;
mod wheel;

use horizon_mod_sdk::{
    Mod, Registration, game,
    hud::{self, Corner, Line},
    input::{self, Event},
    log, render, storage, ui, world,
};
use lasers::{LASERS, is_ship};
use strike::{APPROACHES, ARRIVALS, Act, COLOUR_RGB, COLOURS, FIRE, Target};

const DESIGNATOR: &str = "orbital:laser_designator";
const REMOTE: &str = "orbital:remote";
/// Ticks of holding the designator on a target before it fires.
const LOCK_TICKS: u32 = 14;
const SHADER: &str = include_str!("../shaders/strike.wgsl");
/// The downfall's own pass: strike.wgsl up to its fs_main, less the other lasers' own functions (marked `[lasers pass
/// only]`), then this (see shaders/downfall.wgsl).
const DOWNFALL_PASS: &str = include_str!("../shaders/downfall.wgsl");
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

struct Strike {
    plan: Vec<(f32, Act)>,
    next: usize,
    ticks: u32,
    /// Seconds it runs (the laser's `length`).
    length: f32,
    /// What the post pass reads; [3] is the strike clock, set each frame.
    params: [f32; 16],
    /// Stages due that wait for a tick of their own (`tick_strike` works out one a tick).
    waiting: std::collections::VecDeque<strike::Stage>,
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
    approach: usize,
    arrival: usize,
    page: usize,
    colours: Vec<usize>,
}

/// A ship laser's colour until one is picked (strike::COLOURS): the Mothership green, the Downfall red.
fn default_colour(i: usize) -> usize {
    usize::from(LASERS[i].key == "downfall")
}

struct Orbital {
    /// The two post passes (0 every laser's, 1 the downfall's), the one the game last compiled, and the ones waiting to
    /// be compiled ahead of a strike, and whether one is being now (see `frame`).
    passes: [String; 2],
    compiled: Option<usize>,
    warm_queue: Vec<usize>,
    warming: bool,
    /// World changes waiting for room in a tick's block budget, in order; they outlive the strike that made them.
    carving: std::collections::VecDeque<(u64, String)>,
    /// World changes that wait for spare block budget (`Act::Spare`): what stands high over a blast.
    spare: std::collections::VecDeque<(u64, String)>,
    laser: usize,
    terrain: bool,
    /// Whether the strikes put their messages over the hotbar (the replies to the player's own clicks always show).
    messages: bool,
    /// Which way the ship lasers' ship comes in (strike::APPROACHES), and how it arrives (strike::ARRIVALS).
    approach: usize,
    arrival: usize,
    /// The wheel's page last shown.
    page: usize,
    /// Each laser's ship colour (strike::COLOURS; only the ship lasers use theirs).
    colours: Vec<usize>,
    /// Ticks the designator has been held, while it is.
    aiming: Option<u32>,
    strike: Option<Strike>,
    wheel: Option<wheel::Wheel>,
    /// Seconds since the last tick, for a smooth strike clock between ticks.
    since_tick: f32,
    /// The HUD panel last sent.
    panel: Vec<(String, u32)>,
}

impl Orbital {
    fn save(&self) {
        let text = format!(
            "laser={}\nterrain={}\nmessages={}\napproach={}\narrival={}\npage={}\n",
            LASERS[self.laser].key,
            u8::from(self.terrain),
            u8::from(self.messages),
            APPROACHES[self.approach].key,
            ARRIVALS[self.arrival].key,
            self.page
        );
        let mut text = text;
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
        let mut approach = 0;
        let mut arrival = 0;
        let mut page = 0;
        let mut colours: Vec<usize> = (0..LASERS.len()).map(default_colour).collect();
        for line in text.lines() {
            match line.split_once('=') {
                Some(("laser", k)) => laser = LASERS.iter().position(|l| l.key == k).unwrap_or(0),
                Some(("terrain", v)) => terrain = v != "0",
                Some(("messages", v)) => messages = v != "0",
                Some(("approach", k)) => approach = APPROACHES.iter().position(|a| a.key == k).unwrap_or(0),
                Some(("arrival", k)) => arrival = ARRIVALS.iter().position(|a| a.key == k).unwrap_or(0),
                Some(("page", v)) => page = v.parse::<usize>().unwrap_or(0).min(wheel::pages() - 1),
                Some((k, v)) if k.starts_with("colour_") => {
                    if let (Some(i), Some(c)) = (LASERS.iter().position(|l| l.key == &k[7..]), COLOURS.iter().position(|c| c.key == v)) {
                        colours[i] = c;
                    }
                }
                _ => {}
            }
        }
        Settings { laser, terrain, messages, approach, arrival, page, colours }
    }
    fn actionbar(text: &str, color: &str) {
        world::run_commands(&[format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#)]);
    }

    // ---- the wheel ----
    fn show_wheel(&self) {
        if let Some(w) = &self.wheel {
            ui::show(&w.draws(self.laser, self.terrain, self.messages, self.approach, self.arrival, &self.colours));
        }
    }
    fn open_wheel(&mut self) {
        let mut w = wheel::Wheel::on_page(self.page);
        if let Some(c) = ui::cursor() {
            w.hover_at(c.x, c.y, self.laser);
        }
        self.wheel = Some(w);
        self.show_wheel();
        world::play_sound("minecraft:ui.button.click", None, 0.5, 1.4);
    }
    fn turn_page(&mut self, k: usize) {
        let Some(w) = &mut self.wheel else { return };
        w.turn(k);
        self.page = w.page;
        self.show_wheel();
        world::play_sound("minecraft:ui.button.click", None, 0.5, 1.2);
        self.save();
    }
    fn wheel_click(&mut self, x: f32, y: f32) {
        let (row, page) = self.wheel.as_ref().map_or((None, self.page), |w| (w.row_laser(self.laser), w.page));
        match wheel::spot(x, y, row.is_some(), page) {
            Some(wheel::Spot::Laser(i)) => {
                self.laser = i;
                self.save();
                ui::close();
                self.wheel = None;
                let l = LASERS[i];
                Self::actionbar(&format!("{} LOADED", l.title), l.color);
                world::play_sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
            }
            Some(wheel::Spot::Page(k)) => self.turn_page(k),
            Some(wheel::Spot::Approach(a)) => {
                // picking how it comes in loads the ship laser the row is for too
                self.approach = a;
                self.laser = row.unwrap_or(self.laser);
                self.save();
                ui::close();
                self.wheel = None;
                let l = LASERS[self.laser];
                Self::actionbar(&format!("{} LOADED: {}", l.title, APPROACHES[a].label.to_uppercase()), l.color);
                world::play_sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
            }
            Some(wheel::Spot::Arrival(a)) => {
                self.arrival = a;
                self.laser = row.unwrap_or(self.laser);
                self.save();
                ui::close();
                self.wheel = None;
                let l = LASERS[self.laser];
                Self::actionbar(&format!("{} LOADED: IT {}", l.title, ARRIVALS[a].label.to_uppercase()), l.color);
                world::play_sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
            }
            Some(wheel::Spot::Colour(c)) => {
                let i = row.unwrap_or(self.laser);
                self.colours[i] = c;
                self.laser = i;
                self.save();
                ui::close();
                self.wheel = None;
                let l = LASERS[i];
                Self::actionbar(&format!("{} LOADED: LIT {}", l.title, COLOURS[c].button), l.color);
                world::play_sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
            }
            Some(wheel::Spot::Centre) => {
                self.terrain = !self.terrain;
                self.save();
                world::play_sound("minecraft:ui.button.click", None, 0.6, if self.terrain { 1.6 } else { 1.0 });
                self.show_wheel();
            }
            Some(wheel::Spot::Messages) => {
                self.messages = !self.messages;
                self.save();
                world::play_sound("minecraft:ui.button.click", None, 0.6, if self.messages { 1.6 } else { 1.0 });
                self.show_wheel();
            }
            None => {}
        }
    }

    // ---- the strike ----
    fn fire(&mut self) {
        let laser = LASERS[self.laser];
        let Some(hit) = world::raycast(laser.range) else {
            Self::actionbar("NO TARGET IN RANGE", "gray");
            return;
        };
        let player = game::get_player();
        let dimension = player.as_ref().map_or("minecraft:overworld".to_string(), |p| p.dimension.clone());
        let me = player.as_ref().map_or([hit.x, hit.y, hit.z + 1.0], |p| [p.x, p.y, p.z]);
        let target = Target { block: [hit.block_x, hit.block_y, hit.block_z], point: [hit.x, hit.y, hit.z] };
        let clock = game::get_clock().map_or(0, |c| c.game_time);
        let seed = (clock % 997 + 1) as f32; // a fresh look every strike
        let plan = strike::plan(laser, &target, self.terrain, &dimension, seed, me, self.approach);
        let mut params = [0.0f32; 16];
        params[..3].copy_from_slice(&[hit.x as f32, hit.y as f32, hit.z as f32]);
        params[4] = hit.block_x as f32 + 0.5;
        params[5] = hit.block_z as f32 + 0.5;
        params[6] = strike::wing_angle(target.point, me);
        params[7] = laser.index as f32;
        params[8] = seed;
        params[9] = 1.0;
        params[11] = hit.block_y as f32;
        if is_ship(laser) {
            params[12] = self.approach as f32;
            params[13] = self.arrival as f32;
            params[15] = self.colours[self.laser] as f32;
        }
        if laser.key == "downfall" {
            params[14] = strike::df_reach(target.point, me);
        }
        let pass = usize::from(laser.key == "downfall");
        render::set_post(&self.passes[pass]);
        self.compiled = Some(pass);
        render::set_params(&params);
        log::write(log::Level::Info, &format!("strike [{}] at {} {} {}", laser.key, hit.block_x, hit.block_y, hit.block_z));
        self.strike = Some(Strike { plan, next: 0, ticks: 0, length: laser.length, params, waiting: Default::default() });
    }
    /// One tick of the strike: everything due by now, in one batch.
    fn tick_strike(&mut self) {
        self.carve();
        let Some(s) = &mut self.strike else {
            return;
        };
        s.ticks += 1;
        let now = s.ticks as f32 * 0.05;
        let mut cmds = Vec::new();
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
                    None => cmds.push(c),
                },
                Act::Sound { event, at, volume, pitch } => world::play_sound(&event, at.map(|[x, y, z]| (x, y, z)), volume, pitch),
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
        if !cmds.is_empty() {
            world::run_commands(&cmds);
        }
        if !jolts.is_empty() {
            // the jolts due this tick as one (the game adds jolts up the same way, and takes only so many a call)
            let strength = jolts.iter().map(|j| j.0 * j.0).sum::<f32>().sqrt().min(1.0);
            let seconds = jolts.iter().map(|j| j.1).fold(0.0, f32::max);
            render::shake(strength, seconds);
        }
        if now >= s.length {
            render::clear_post();
            self.strike = None;
        }
        self.carve();
    }
    /// Run the waiting world changes, in order, as far as this tick's block budget goes (at least one); then, with
    /// what is left of it, the ones that wait for spare budget.
    fn carve(&mut self) {
        let mut spent = 0;
        let mut cmds = Vec::new();
        while let Some((cost, _)) = self.carving.front() {
            if !cmds.is_empty() && spent + cost > BLOCK_BUDGET {
                break;
            }
            spent += cost;
            if let Some((_, c)) = self.carving.pop_front() {
                cmds.push(c);
            }
        }
        while self.carving.is_empty()
            && let Some((cost, _)) = self.spare.front()
        {
            if spent + cost > BLOCK_BUDGET && (spent > 0 || !cmds.is_empty()) {
                break;
            }
            spent += cost;
            if let Some((_, c)) = self.spare.pop_front() {
                cmds.push(c);
            }
        }
        if !cmds.is_empty() {
            world::run_commands(&cmds);
        }
    }

    /// While the player holds one of the items: which laser is loaded.
    fn update_panel(&mut self) {
        let holding = input::held().is_some_and(|h| h.id == DESIGNATOR || h.id == REMOTE);
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
        input::register_key("wheel", "Open the laser wheel", "key.keyboard.r");
        let Settings { laser, terrain, messages, approach, arrival, page, colours } = Orbital::load();
        let state = Orbital {
            passes: [SHADER.to_string(), downfall_pass()],
            compiled: None,
            // both compiled as the world loads (the driver keeps them), the loaded laser's last, so the game holds it
            warm_queue: vec![usize::from(LASERS[laser].key == "downfall"), usize::from(LASERS[laser].key != "downfall")],
            warming: false,
            carving: std::collections::VecDeque::new(),
            spare: std::collections::VecDeque::new(),
            laser,
            terrain,
            messages,
            approach,
            arrival,
            page,
            colours,
            aiming: None,
            strike: None,
            wheel: None,
            since_tick: 0.0,
            panel: Vec::new(),
        };
        Ok((state, Registration::new().command("orbital").on_tick().on_frame()))
    }

    fn tick(&mut self, _tick: u64) {
        self.since_tick = 0.0;
        for event in input::poll() {
            match event {
                Event::UseStart(u) if u.item.id == DESIGNATOR => {
                    if self.strike.is_some() {
                        Self::actionbar("STRIKE IN PROGRESS", "gray");
                    } else {
                        self.aiming = Some(0);
                    }
                }
                Event::UseStart(u) if u.item.id == REMOTE => self.open_wheel(),
                Event::UseStop(u) if u.item.id == DESIGNATOR => self.aiming = None,
                Event::KeyDown(k) if k == "wheel" => self.open_wheel(),
                Event::ScreenClick(c) if c.button == 0 => self.wheel_click(c.x, c.y),
                Event::ScreenClick(c) if c.button == 1 => self.turn_page(self.page + 1),
                Event::ScreenClosed => self.wheel = None,
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
                    Self::actionbar(&format!("ACQUIRING TARGET {}  [{}]", ".".repeat(1 + n as usize / 4), l.title), l.color);
                }
                self.aiming = Some(n + 1);
            }
        }
        self.tick_strike();
        self.update_panel();
    }

    fn frame(&mut self, seconds: f32) {
        self.since_tick += seconds;
        // Compile the post passes as the world loads, not when the first strike fires (that costs about a second): set
        // each for one frame, all but invisible (no strike clock, the lowest intensity), then clear it. The game keeps
        // the last one compiled for the strikes after; loading a laser that needs the other one compiles that one the
        // same way (quickly, the driver has kept it), there and then rather than as it fires.
        let want = usize::from(LASERS[self.laser].key == "downfall");
        if self.warm_queue.is_empty() && !self.warming && self.compiled != Some(want) && self.strike.is_none() {
            self.warm_queue.push(want);
        }
        if self.strike.is_none() {
            if self.warming {
                render::clear_post();
                self.warming = false;
            } else if !self.warm_queue.is_empty() {
                let pass = self.warm_queue.remove(0);
                render::set_post(&self.passes[pass]);
                render::set_params(&[0.0; 16]);
                self.compiled = Some(pass);
                self.warming = true;
            }
        } else {
            self.warm_queue.clear();
            self.warming = false;
        }
        if let Some(s) = &mut self.strike {
            s.params[3] = s.ticks as f32 * 0.05 + self.since_tick.min(0.05);
            render::set_params(&s.params);
        }
        if let (Some(w), Some(c)) = (&mut self.wheel, ui::cursor())
            && w.hover_at(c.x, c.y, self.laser)
        {
            self.show_wheel();
        }
    }

    fn command(&mut self, _name: &str, args: &str) -> Result<Option<String>, String> {
        let mut words = args.split_whitespace();
        match (words.next(), words.next()) {
            (Some("give"), _) => {
                world::run_commands(&[format!("give @s {DESIGNATOR}"), format!("give @s {REMOTE}")]);
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
            (Some("messages"), Some(v @ ("on" | "off"))) => {
                self.messages = v == "on";
                self.save();
                Ok(Some(format!("Strike messages {v}")))
            }
            (Some(key), None) if LASERS.iter().any(|l| l.key == key) => {
                self.laser = LASERS.iter().position(|l| l.key == key).unwrap_or(0);
                self.save();
                Ok(Some(format!("{} loaded", LASERS[self.laser].title)))
            }
            _ => Err(format!(
                "/orbital give | wheel | terrain on|off | messages on|off | approach {} | arrival {} | colour {} | {}",
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
