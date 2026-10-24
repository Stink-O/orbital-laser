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
use lasers::LASERS;
use strike::{Act, FIRE, Target};

const DESIGNATOR: &str = "orbital:laser_designator";
const REMOTE: &str = "orbital:remote";
/// Ticks of holding the designator on a target before it fires.
const LOCK_TICKS: u32 = 14;
/// Blocks the designator reaches.
const RANGE: f32 = 200.0;
const SHADER: &str = include_str!("../shaders/strike.wgsl");
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
}

struct Orbital {
    /// Frames since the world loaded, until the post pass has been compiled once (see `frame`).
    warm: u8,
    /// World changes waiting for room in a tick's block budget, in order; they outlive the strike that made them.
    carving: std::collections::VecDeque<(u64, String)>,
    laser: usize,
    terrain: bool,
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
        let text = format!("laser={}\nterrain={}\n", LASERS[self.laser].key, u8::from(self.terrain));
        if let Err(e) = storage::set(SETTINGS, text.as_bytes()) {
            log::write(log::Level::Warn, &format!("settings not saved: {e}"));
        }
    }
    fn load() -> (usize, bool) {
        let text = storage::get(SETTINGS).map(|b| String::from_utf8_lossy(&b).into_owned()).unwrap_or_default();
        let mut laser = 0;
        let mut terrain = true;
        for line in text.lines() {
            match line.split_once('=') {
                Some(("laser", k)) => laser = LASERS.iter().position(|l| l.key == k).unwrap_or(0),
                Some(("terrain", v)) => terrain = v != "0",
                _ => {}
            }
        }
        (laser, terrain)
    }
    fn actionbar(text: &str, color: &str) {
        world::run_commands(&[format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#)]);
    }

    // ---- the wheel ----
    fn open_wheel(&mut self) {
        let mut w = wheel::Wheel::default();
        if let Some(c) = ui::cursor() {
            w.hover_at(c.x, c.y);
        }
        ui::show(&w.draws(self.laser, self.terrain));
        self.wheel = Some(w);
        world::play_sound("minecraft:ui.button.click", None, 0.5, 1.4);
    }
    fn wheel_click(&mut self, x: f32, y: f32) {
        match wheel::spot(x, y) {
            Some(wheel::Spot::Laser(i)) => {
                self.laser = i;
                self.save();
                ui::close();
                self.wheel = None;
                let l = LASERS[i];
                Self::actionbar(&format!("{} LOADED", l.title), l.color);
                world::play_sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
            }
            Some(wheel::Spot::Centre) => {
                self.terrain = !self.terrain;
                self.save();
                world::play_sound("minecraft:ui.button.click", None, 0.6, if self.terrain { 1.6 } else { 1.0 });
                if let Some(w) = &self.wheel {
                    ui::show(&w.draws(self.laser, self.terrain));
                }
            }
            None => {}
        }
    }

    // ---- the strike ----
    fn fire(&mut self) {
        let Some(hit) = world::raycast(RANGE) else {
            Self::actionbar("NO TARGET IN RANGE", "gray");
            return;
        };
        let laser = LASERS[self.laser];
        let player = game::get_player();
        let dimension = player.as_ref().map_or("minecraft:overworld".to_string(), |p| p.dimension.clone());
        let me = player.as_ref().map_or([hit.x, hit.y, hit.z + 1.0], |p| [p.x, p.y, p.z]);
        let target = Target { block: [hit.block_x, hit.block_y, hit.block_z], point: [hit.x, hit.y, hit.z] };
        let clock = game::get_clock().map_or(0, |c| c.game_time);
        let seed = (clock % 997 + 1) as f32; // a fresh look every strike
        let plan = strike::plan(laser, &target, self.terrain, &dimension, seed, me);
        let mut params = [0.0f32; 16];
        params[..3].copy_from_slice(&[hit.x as f32, hit.y as f32, hit.z as f32]);
        params[4] = hit.block_x as f32 + 0.5;
        params[5] = hit.block_z as f32 + 0.5;
        params[6] = strike::wing_angle(target.point, me);
        params[7] = laser.index as f32;
        params[8] = seed;
        params[9] = 1.0;
        params[11] = hit.block_y as f32;
        render::set_post(SHADER);
        render::set_params(&params);
        log::write(log::Level::Info, &format!("strike [{}] at {} {} {}", laser.key, hit.block_x, hit.block_y, hit.block_z));
        self.strike = Some(Strike { plan, next: 0, ticks: 0, length: laser.length, params });
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
        while let Some((t, _)) = s.plan.get(s.next) {
            if *t > now {
                break;
            }
            let (_, act) = std::mem::replace(&mut s.plan[s.next], (0.0, Act::Cmd(String::new())));
            s.next += 1;
            match act {
                Act::Cmd(c) => match strike::block_cost(&c) {
                    Some(cost) => self.carving.push_back((cost, c)),
                    None => cmds.push(c),
                },
                Act::Sound { event, volume, pitch } => world::play_sound(&event, None, volume, pitch),
                Act::Later(job) => {
                    // more of the plan, worked out now it is due: merged in after what has run (both are in order,
                    // so the sort only merges two runs)
                    let mut rest = s.plan.split_off(s.next);
                    rest.extend(job());
                    rest.sort_by(|a, b| a.0.total_cmp(&b.0));
                    s.plan.extend(rest);
                }
            }
        }
        if !cmds.is_empty() {
            world::run_commands(&cmds);
        }
        if now >= s.length {
            render::clear_post();
            self.strike = None;
        }
        self.carve();
    }
    /// Run the waiting world changes, in order, as far as this tick's block budget goes (at least one).
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
            ];
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
        let (laser, terrain) = Orbital::load();
        let state = Orbital {
            warm: 0,
            carving: std::collections::VecDeque::new(),
            laser,
            terrain,
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
        // Compile the post pass as the world loads, not when the first strike fires (that costs about a second): set
        // it for one frame, all but invisible (no strike clock, the lowest intensity), then clear it. The game keeps
        // the compiled pass for the strikes after.
        if self.warm < 2 && self.strike.is_none() {
            if self.warm == 0 {
                render::set_post(SHADER);
                render::set_params(&[0.0; 16]);
            } else {
                render::clear_post();
            }
            self.warm += 1;
        }
        if let Some(s) = &mut self.strike {
            s.params[3] = s.ticks as f32 * 0.05 + self.since_tick.min(0.05);
            render::set_params(&s.params);
        }
        if let (Some(w), Some(c)) = (&mut self.wheel, ui::cursor())
            && w.hover_at(c.x, c.y)
        {
            ui::show(&w.draws(self.laser, self.terrain));
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
            (Some("terrain"), Some(v @ ("on" | "off"))) => {
                self.terrain = v == "on";
                self.save();
                Ok(Some(format!("Terrain damage {v}")))
            }
            (Some(key), None) if LASERS.iter().any(|l| l.key == key) => {
                self.laser = LASERS.iter().position(|l| l.key == key).unwrap_or(0);
                self.save();
                Ok(Some(format!("{} loaded", LASERS[self.laser].title)))
            }
            _ => Err(format!(
                "/orbital give | wheel | terrain on|off | {}",
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
