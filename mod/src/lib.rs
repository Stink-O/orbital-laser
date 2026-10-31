//! Orbital Laser, a Horizon mod. Hold the Orbital Laser Designator on a target
//! and the strike lands there: a beam from orbit, a crater to bedrock, and what
//! each laser leaves behind. Right-click the Orbital Remote (or press R) for the
//! laser wheel (rebind R in Options > Controls). `/orbital give` hands you both items.
//!
//! It uses the game's mod capabilities: `input` (the two items' right-clicks,
//! the wheel's key and what is typed on it), `ui` (the wheel), `render` (the
//! strike's post pass, shaders/strike.wgsl, and the downfall's and the planet
//! killer's own), `world` (aiming, the crater's block
//! changes, the sounds and the flying speed), `hud` (the status panel), `storage`
//! (the chosen laser and the settings) and
//! `registries` (the items, their textures and the sounds, in assets/ and data/).
mod columns;
mod ground;
mod lasers;
mod meter;
mod pace;
mod sdk;
mod strike;
mod wheel;

use horizon_mod_sdk::{
    Mod, Registration,
    hud::{self, Corner, Line},
    input::{self, Event},
    storage, ui,
};
use sdk::{game, log, render, world};
use lasers::{LASERS, is_ship};
use strike::{APPROACHES, ARRIVALS, Act, COLOUR_RGB, COLOURS, FIRE, Target};

const DESIGNATOR: &str = "orbital:laser_designator";
const REMOTE: &str = "orbital:remote";
/// Ticks of holding the designator on a target before it fires.
const LOCK_TICKS: u32 = 14;
// Every post pass, built ahead of time from the shader files by build.rs (src/passbuild.rs): PASS_OWN (the other
// lasers', strike.wgsl itself, then the downfall's, the planet killer's, the crystal bloom's and the sinkhole's: strike.wgsl
// up to its fs_main less the other lasers' own functions, then shaders/downfall.wgsl ...), PASS_PAYLOAD and PASS_NUKE (at
// QUALITY FULL and FAST). A switch only picks one: building a pass of some 200 KB in the
// game took the mod past its fuel in one call.
include!(concat!(env!("OUT_DIR"), "/passes.rs"));
#[cfg(test)]
mod passbuild;
/// The Payload's pass at QUALITY FULL or FAST: FAST keeps its half-size stage (`[half stage]` in payload.wgsl: the
/// smoke drawn at half the width and height, on a game with mod passes' half-size stage; a game without it draws the
/// pass's `fs_main`, at full size), FULL leaves it out.
fn payload_pass(fast: bool) -> &'static str {
    PASS_PAYLOAD[usize::from(fast)]
}
/// The Nuke's, the same way (nuke.wgsl's `[half stage]`: its cloud, dust and trail at half size).
fn nuke_pass(fast: bool) -> &'static str {
    PASS_NUKE[usize::from(fast)]
}
/// Which of the post passes a laser's strike runs (`Orbital::passes`).
fn pass_of(l: &lasers::Laser) -> usize {
    match l.key {
        "downfall" => 1,
        "planetkiller" => 2,
        "crystalbloom" => 3,
        "sinkhole" => 4,
        "payload" => 5,
        "nuke" => 6,
        _ => 0,
    }
}
const SETTINGS: &str = "settings";
/// Vanilla's flying speed (creative flight), which the wheel's speeds multiply.
const VANILLA_FLY: f32 = 0.05;
/// Blocks a tick's world changes may touch (see `strike::block_cost`): more waits for the next tick, so a big strike
/// carves its crater over a few seconds instead of freezing the game for one.
const BLOCK_BUDGET: u64 = 20_000;
/// At most this many world-changing commands a tick, however few blocks each changes: each is parsed and run on its
/// own, and thousands of small ones in one tick (a planet killer's fissures, cut a column at a time, with its crater's
/// walls) hitch the game as surely as too many blocks. Every other laser stays under it.
pub(crate) const CARVE_CMDS: usize = 400;
/// What a world-changing command costs the mod to hand over (`meter`), roughly.
const CMD_COST: u64 = 3_000;
/// What a stage of a plan costs at the least (`meter`): what it counts of itself, if more, instead.
const STAGE_COST: u64 = 2_000_000;
/// What working out a strike's plan as it fires costs (`meter`), about.
const FIRE_COST: u64 = 8_000_000;
/// What an edit costs the mod to hand over (`meter`): its runs copied and written out for the game, roughly.
fn edit_cost(b: &strike::Blocks) -> u64 {
    3_000 + 600 * b.runs.len() as u64
}

/// A part of a strike's plan a stage gave (`Strike::more`): in order of time, then of when it was given.
struct Given {
    t: f32,
    seq: u64,
    act: Act,
}
impl PartialEq for Given {
    fn eq(&self, o: &Self) -> bool {
        self.cmp(o) == std::cmp::Ordering::Equal
    }
}
impl Eq for Given {}
impl PartialOrd for Given {
    fn partial_cmp(&self, o: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(o))
    }
}
impl Ord for Given {
    // (reversed: the heap gives the earliest first)
    fn cmp(&self, o: &Self) -> std::cmp::Ordering {
        o.t.total_cmp(&self.t).then(o.seq.cmp(&self.seq))
    }
}

struct Strike {
    /// The plan as it fired, in order, and how far through it the strike is.
    plan: Vec<(f32, Act)>,
    next: usize,
    /// What its stages gave since, earliest first (a heap: a stage's few acts go in without the rest of the plan being
    /// gone through again, which in a long plan cost more than the stage).
    more: std::collections::BinaryHeap<Given>,
    given: u64,
    ticks: u32,
    /// Seconds it runs (the laser's `length`).
    length: f32,
    /// What the post pass reads; [3] is the strike clock, set each frame.
    params: [f32; 16],
    /// Stages due that wait for a tick of their own (`tick_strike` works out one a tick).
    waiting: std::collections::VecDeque<strike::Stage>,
    /// Those that go before them (`Act::Soon`), in order.
    urgent: std::collections::VecDeque<strike::Stage>,
    /// What the pass reads as `mod_data` (`Act::Data`), and whether it changed since it was last sent.
    data: Vec<u32>,
    data_sent: bool,
    /// Started this far in (`/orbital skip`): commands, sounds and jolts due before then are left out.
    skipped: f32,
    /// The sounds it has played, to cut them short if it is stopped.
    sounds: std::collections::BTreeSet<String>,
}
impl Strike {
    /// Work out a stage of the plan, what it gives due after what was due before it at the same time.
    fn work_out(&mut self, job: strike::Stage) {
        let before = meter::spent();
        let out = job();
        let depth = u64::from(64 - (self.more.len() as u64 + out.len() as u64).leading_zeros());
        meter::spend(out.len() as u64 * (100 + 30 * depth));
        // (and what it made: the work of a stage that counts little of itself shows in the runs and commands it gives,
        // so the rest of the tick waits for it)
        let made: u64 = out.iter().map(|(_, a)| match a {
            Act::Blocks(b) => 1_000 * b.runs.len() as u64,
            Act::Cmd(_) | Act::Spare(_) => 1_000,
            _ => 0,
        }).sum();
        meter::spend(made);
        for (t, act) in out {
            self.given += 1;
            self.more.push(Given { t, seq: self.given, act });
        }
        // (a stage counts as some work however little of it it counts itself: `meter`)
        let own = meter::spent() - before;
        meter::spend(STAGE_COST.saturating_sub(own));
    }
    /// When what falls due next does: the plan's next act or a stage's.
    fn next_due(&self) -> Option<f32> {
        match (self.plan.get(self.next).map(|e| e.0), self.more.peek().map(|g| g.t)) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        }
    }
    /// What falls due next, taken: the plan's first when the two are due together.
    fn take_due(&mut self) -> Option<(f32, Act)> {
        let from_plan = match (self.plan.get(self.next).map(|e| e.0), self.more.peek().map(|g| g.t)) {
            (Some(a), Some(b)) => a <= b,
            (Some(_), None) => true,
            (None, Some(_)) => false,
            (None, None) => return None,
        };
        if from_plan {
            let e = std::mem::replace(&mut self.plan[self.next], (0.0, Act::Cmd(String::new())));
            self.next += 1;
            Some(e)
        } else {
            self.more.pop().map(|g| (g.t, g.act))
        }
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
    page: usize,
    colours: Vec<usize>,
    fly: f32,
    blast_alt: bool,
    fast: bool,
}

/// A ship laser's colour until one is picked (strike::COLOURS): the Mothership green, the Downfall red.
fn default_colour(i: usize) -> usize {
    usize::from(LASERS[i].key == "downfall")
}

struct Orbital {
    /// The post passes (0 the other lasers', 1 the downfall's, 2 the planet killer's, 3 the crystal bloom's, 4 the
    /// sinkhole's, 5 the payload's, 6 the nuke's), the one the
    /// game last compiled,
    /// and the ones waiting to be compiled ahead of a strike, and whether one is being now (see `frame`).
    passes: [&'static str; 7],
    compiled: Option<usize>,
    warm_queue: Vec<usize>,
    warming: bool,
    /// World changes waiting for room in a tick's block budget, in order; they outlive the strike that made them.
    carving: std::collections::VecDeque<(u64, String)>,
    /// World changes that wait for spare block budget (`Act::Spare`): what stands high over a blast.
    spare: std::collections::VecDeque<(u64, String)>,
    /// Block edits waiting for room in a tick's budget (`pace`), in order, each with its cost and the tick it was due
    /// (`edit_ticks`); they outlive the strike that made them too.
    edits: std::collections::VecDeque<(u32, u64, Box<strike::Blocks>)>,
    /// Whether edits went in on the tick before, how many a tick may go in, by the frame time, the ticks counted, and
    /// the most ticks an edit has waited since the queue was last empty.
    edited: bool,
    edit_ticks: u64,
    edits_late: u64,
    pace: pace::Pace,
    laser: usize,
    terrain: bool,
    /// Whether the strikes put their messages over the hotbar (the replies to the player's own clicks always show).
    messages: bool,
    /// Whether the status panel shows at the top right while the player holds one of the items.
    hud: bool,
    /// Which way the ship lasers' ship comes in (strike::APPROACHES), and how it arrives (strike::ARRIVALS).
    approach: usize,
    arrival: usize,
    /// The wheel's page last shown.
    page: usize,
    /// Each laser's ship colour (strike::COLOURS; only the ship lasers use theirs).
    colours: Vec<usize>,
    /// Whether the Payload's blast and its thump through the ground are the alternative ones (`/orbital payloadsound`).
    blast_alt: bool,
    /// The player's flying speed, in times vanilla's (the wheel's bar and field, `/orbital flyspeed`).
    fly: f32,
    /// QUALITY FAST: the Payload's smoke drawn at half size (`payload_pass`; the wheel's switch, `/orbital quality`).
    fast: bool,
    /// Ticks the designator has been held, while it is.
    aiming: Option<u32>,
    /// Seconds the next strike starts in at (`/orbital skip`, for looking at one moment of it; terrain off only).
    skip: f32,
    /// The Payload's and the Nuke's cloud shadows on the land left out (`/orbital shadow off`: for looking at them
    /// side by side; not kept).
    shadow_off: bool,
    strike: Option<Strike>,
    wheel: Option<wheel::Wheel>,
    /// Seconds since the last tick, for a smooth strike clock between ticks.
    since_tick: f32,
    /// The HUD panel last sent.
    panel: Vec<(String, u32)>,
    /// `/orbital meter N`: each tick whose work (`meter`) comes to N instructions or more is logged.
    meter_log: Option<u64>,
    ticks: u64,
}

thread_local! {
    /// `/orbital meter trace`: each part of a strike's tick logged with what the meter says by then (`fuel:`, which the
    /// fork's soak harness tells the fuel used by then of).
    static TRACE: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}
fn trace(what: &str) {
    if TRACE.with(std::cell::Cell::get) {
        log::write(log::Level::Info, &format!("fuel: {what} (meter {:.2}M)", meter::spent() as f64 / 1e6));
    }
}

impl Orbital {
    /// The mod's state with these settings, nothing under way.
    fn new(settings: Settings) -> Orbital {
        let Settings { laser, terrain, messages, hud, approach, arrival, page, colours, fly, blast_alt, fast } = settings;
        Orbital {
            passes: [PASS_OWN[0], PASS_OWN[1], PASS_OWN[2], PASS_OWN[3], PASS_OWN[4], payload_pass(fast), nuke_pass(fast)],
            compiled: None,
            // all compiled as the world loads (the driver keeps them), the loaded laser's last, so the game holds it
            warm_queue: {
                let mine = pass_of(LASERS[laser]);
                (0..7).filter(|&i| i != mine).chain([mine]).collect()
            },
            warming: false,
            carving: std::collections::VecDeque::new(),
            spare: std::collections::VecDeque::new(),
            edits: std::collections::VecDeque::new(),
            edited: false,
            edit_ticks: 0,
            edits_late: 0,
            pace: pace::Pace::default(),
            laser,
            terrain,
            messages,
            hud,
            approach,
            arrival,
            page,
            colours,
            fly,
            blast_alt,
            fast,
            aiming: None,
            skip: 0.0,
            shadow_off: false,
            strike: None,
            wheel: None,
            since_tick: 0.0,
            panel: Vec::new(),
            meter_log: None,
            ticks: 0,
        }
    }
    fn save(&self) {
        let text = format!(
            "laser={}\nterrain={}\nmessages={}\nhud={}\napproach={}\narrival={}\npage={}\nflyspeed={}\npayloadsound={}\nquality={}\n",
            LASERS[self.laser].key,
            u8::from(self.terrain),
            u8::from(self.messages),
            u8::from(self.hud),
            APPROACHES[self.approach].key,
            ARRIVALS[self.arrival].key,
            self.page,
            self.fly,
            if self.blast_alt { "alt" } else { "main" },
            if self.fast { "fast" } else { "full" }
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
        Self::parse(&text)
    }
    fn parse(text: &str) -> Settings {
        let mut laser = 0;
        let mut terrain = true;
        let mut messages = true;
        let mut hud = true;
        let mut approach = 0;
        let mut arrival = 0;
        let mut page = 0;
        let mut fly = 1.0;
        let mut blast_alt = false;
        let mut fast = true;
        let mut colours: Vec<usize> = (0..LASERS.len()).map(default_colour).collect();
        for line in text.lines() {
            match line.split_once('=') {
                Some(("laser", k)) => laser = LASERS.iter().position(|l| l.key == k).unwrap_or(0),
                Some(("terrain", v)) => terrain = v != "0",
                Some(("messages", v)) => messages = v != "0",
                Some(("hud", v)) => hud = v != "0",
                Some(("approach", k)) => approach = APPROACHES.iter().position(|a| a.key == k).unwrap_or(0),
                Some(("arrival", k)) => arrival = ARRIVALS.iter().position(|a| a.key == k).unwrap_or(0),
                Some(("page", v)) => page = v.parse::<usize>().unwrap_or(0).min(wheel::pages() - 1),
                Some(("flyspeed", v)) => fly = wheel::parse_speed(v).unwrap_or(1.0),
                Some(("payloadsound", v)) => blast_alt = v == "alt",
                Some(("quality", v)) => fast = v != "full",
                Some((k, v)) if k.starts_with("colour_") => {
                    if let (Some(i), Some(c)) = (LASERS.iter().position(|l| l.key == &k[7..]), COLOURS.iter().position(|c| c.key == v)) {
                        colours[i] = c;
                    }
                }
                _ => {}
            }
        }
        Settings { laser, terrain, messages, hud, approach, arrival, page, colours, fly, blast_alt, fast }
    }
    fn actionbar(text: &str, color: &str) {
        world::run_commands(&[format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#)]);
    }

    // ---- the flying speed ----
    /// Hands the game the flying speed (vanilla's at 1x). The game keeps it through respawns and worlds until it is
    /// changed, so this is needed only when it changes and as the mod starts.
    fn apply_fly(&self) {
        let speed = ((self.fly - 1.0).abs() > 1e-4).then_some(VANILLA_FLY * self.fly);
        world::set_flying_speed(speed);
    }
    fn set_fly(&mut self, m: f32) {
        self.fly = m.clamp(0.01, wheel::FLY_MAX);
        self.apply_fly();
        self.save();
        if let Some(w) = &mut self.wheel {
            w.fly = self.fly;
        }
    }
    /// What was typed on the wheel: into the flying speed's field while it has the keyboard; Enter sets the speed,
    /// Backspace takes a character off.
    fn typed(&mut self, t: input::Typed) {
        let Some(field) = self.wheel.as_mut().and_then(|w| w.typing.as_mut()) else {
            return;
        };
        match t {
            input::Typed::Text(s) => wheel::type_into(field, &s),
            input::Typed::Key(k) if k == "key.keyboard.backspace" => {
                field.pop();
            }
            input::Typed::Key(k) if k == "key.keyboard.enter" || k == "key.keyboard.keypad.enter" => {
                let typed = std::mem::take(field);
                if let Some(w) = &mut self.wheel {
                    w.typing = None;
                }
                match wheel::parse_speed(&typed) {
                    Some(m) => {
                        self.set_fly(m);
                        world::play_sound("minecraft:ui.button.click", None, 0.6, 1.6);
                    }
                    // (nothing typed leaves the speed as it was; a bad number says so)
                    None if !typed.is_empty() => world::play_sound("minecraft:ui.button.click", None, 0.6, 0.6),
                    None => {}
                }
            }
            input::Typed::Key(_) => return,
        }
        self.show_wheel();
    }

    // ---- the wheel ----
    fn show_wheel(&self) {
        if let Some(w) = &self.wheel {
            ui::show(&w.draws(self.laser, self.terrain, self.messages, self.hud, self.approach, self.arrival, &self.colours, self.blast_alt, self.fast));
        }
    }
    fn open_wheel(&mut self) {
        let mut w = wheel::Wheel::on_page(self.page, self.fly);
        w.striking = self.strike.is_some();
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
        let spot = wheel::spot(x, y, wheel::Rows::of(row), page);
        // a click anywhere but the field takes the keyboard from it, leaving the speed as it was
        if let Some(w) = &mut self.wheel
            && w.typing.is_some()
            && spot != Some(wheel::Spot::FlyField)
        {
            w.typing = None;
            self.show_wheel();
        }
        match spot {
            Some(wheel::Spot::FlyBar) => {
                self.set_fly(wheel::bar_speed_at(x));
                world::play_sound("minecraft:ui.button.click", None, 0.5, 1.2 + 0.4 * (self.fly.ln() / wheel::BAR_MAX.ln()).clamp(0.0, 1.0));
                self.show_wheel();
            }
            Some(wheel::Spot::FlyField) => {
                if let Some(w) = &mut self.wheel {
                    w.typing.get_or_insert_with(String::new);
                }
                world::play_sound("minecraft:ui.button.click", None, 0.5, 1.4);
                self.show_wheel();
            }
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
            Some(wheel::Spot::Sound(k)) => {
                // picking the Payload's blast loads it too
                self.blast_alt = k == 1;
                self.laser = row.unwrap_or(self.laser);
                self.save();
                ui::close();
                self.wheel = None;
                let l = LASERS[self.laser];
                Self::actionbar(&format!("{} LOADED: {} BLAST", l.title, wheel::SOUNDS[k].0), l.color);
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
            Some(wheel::Spot::Stop) if self.strike.is_some() => {
                world::play_sound("minecraft:ui.button.click", None, 0.6, 0.8);
                self.stop_strike();
            }
            Some(wheel::Spot::Stop) => {}
            Some(wheel::Spot::Quality) => {
                self.set_quality(!self.fast);
                world::play_sound("minecraft:ui.button.click", None, 0.6, if self.fast { 1.6 } else { 1.0 });
                self.show_wheel();
            }
            Some(wheel::Spot::Hud) => {
                self.hud = !self.hud;
                self.save();
                world::play_sound("minecraft:ui.button.click", None, 0.6, if self.hud { 1.6 } else { 1.0 });
                self.update_panel();
                self.show_wheel();
            }
            None => {}
        }
    }

    /// QUALITY FAST or FULL: the Payload's pass built again for it, and given to the game at once if a Payload strike
    /// is drawing it (else compiled ahead of the next, as the passes are).
    fn set_quality(&mut self, fast: bool) {
        if fast == self.fast {
            return;
        }
        self.fast = fast;
        self.save();
        self.rebuild("payload", payload_pass(fast));
        self.rebuild("nuke", nuke_pass(fast));
        self.update_panel();
    }
    /// Laser `key`'s pass is `pass` from now on: given to the game at once if its strike is drawing it (else compiled
    /// ahead of the next, as the passes are).
    fn rebuild(&mut self, key: &str, pass: &'static str) {
        let pl = pass_of(LASERS.iter().find(|l| l.key == key).expect("the laser"));
        self.passes[pl] = pass;
        if self.compiled == Some(pl) {
            self.compiled = None;
            if self.strike.is_some() {
                render::set_post(&self.passes[pl]);
                self.compiled = Some(pl);
            }
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
        ground::clear();
        columns::clear();
        // (the ship lasers take their approach; the Payload which blast it plays, 1 for the alternative)
        let option = if laser.key == "payload" { usize::from(self.blast_alt) } else { self.approach };
        let plan = strike::plan(laser, &target, self.terrain, &dimension, seed, me, option);
        meter::spend(FIRE_COST);
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
        if laser.key == "crystalbloom" {
            // (the latest landed piece's blocks in: none yet; with the terrain left alone there are none to wait for)
            params[14] = if self.terrain { 0.0 } else { 1.0e6 };
        }
        if laser.key == "downfall" {
            params[14] = strike::df_reach(target.point, me);
        }
        if laser.key == "payload" || laser.key == "nuke" {
            // (where the player stood as it fired: the shockwave's dust follows the land from the target's ground to theirs)
            params[12..15].copy_from_slice(&[me[0] as f32, me[1] as f32, me[2] as f32]);
            params[15] = if self.shadow_off { 1.0 } else { 0.0 };
        }
        let pass = pass_of(laser);
        render::set_post(&self.passes[pass]);
        self.compiled = Some(pass);
        render::set_params(&params);
        log::write(log::Level::Info, &format!("strike [{}] at {} {} {}", laser.key, hit.block_x, hit.block_y, hit.block_z));
        // (started part way in: what was due before then is left out, sounds and world changes alike; but the stages and
        // the pass's tables due before then are worked out on the first ticks, as the pass needs them, what they give
        // that was due before then left out too)
        let ticks = (self.skip.min(laser.length - 1.0) * 20.0) as u32;
        let skipped = ticks as f32 * 0.05;
        let mut plan = plan;
        plan.retain(|e| e.0 >= skipped || matches!(e.1, Act::Later(_) | Act::Soon(_) | Act::Table(_) | Act::Words { .. } | Act::Data { .. } | Act::Survey { .. }));
        let next = 0;
        self.skip = 0.0;
        // (the crystal bloom's spires and pieces, worked out once for the pass: strike::cb_table)
        // (the sinkhole's slabs, rings and rim come on the tick after: strike::sh_table, as Act::Table)
        let data = if laser.key == "crystalbloom" { strike::cb_table(seed) } else { Vec::new() };
        render::set_data(&data);
        self.strike = Some(Strike { plan, next, more: Default::default(), given: 0, ticks, length: laser.length, params, waiting: Default::default(), urgent: Default::default(), data, data_sent: true, skipped, sounds: Default::default() });
    }
    /// One tick of the strike: everything due by now, in one batch.
    fn tick_strike(&mut self) {
        // (the world's answers to the ground asked for, before the stages that read them)
        ground::poll();
        columns::poll();
        trace("polled");
        let carved = self.carve(CARVE_CMDS);
        trace("carved");
        let Some(s) = &mut self.strike else {
            self.edit();
            return;
        };
        s.ticks += 1;
        let now = s.ticks as f32 * 0.05;
        let mut cmds = Vec::new();
        let mut jolts: Vec<(f32, f32)> = Vec::new();
        // one stage worked out a tick at most (each is a tick's worth of work, and a tick has a fuel limit): when more
        // fall due together, the rest wait for the ticks after, while everything else goes on time (each is due a
        // little before its own events)
        // (the stages that must not wait, `Act::Soon`, go before the rest: a landed piece's blocks must be in on the tick
        // it lands however much else waits)
        // (and none once the tick's work is over the meter's mark: `meter`; the stages and edits it leaves wait)
        let mut worked_out = false;
        if !meter::full()
            && let Some(job) = s.urgent.pop_front().or_else(|| s.waiting.pop_front())
        {
            s.work_out(job);
            worked_out = true;
            trace("stage");
        }
        while let Some(t) = s.next_due() {
            // (what is due waits a tick once the tick has done all it should: `meter`)
            if t > now || meter::over() {
                break;
            }
            meter::spend(300);
            let Some((t, act)) = s.take_due() else { break };
            if t < s.skipped && matches!(act, Act::Cmd(_) | Act::Sound { .. } | Act::Shake { .. } | Act::Spare(_) | Act::Blocks(_) | Act::Read { .. }) {
                continue;
            }
            match act {
                // the strike's messages over the hotbar, unless they are switched off
                Act::Cmd(c) if !self.messages && c.starts_with("title @s actionbar") => {}
                Act::Cmd(c) => match strike::block_cost(&c) {
                    Some(cost) => self.carving.push_back((cost, c)),
                    None => cmds.push(c),
                },
                Act::Sound { event, at, volume, pitch } => {
                    world::play_sound(&event, at.map(|[x, y, z]| (x, y, z)), volume, pitch);
                    s.sounds.insert(event);
                }
                Act::Shake { strength, seconds } => jolts.push((strength, seconds)),
                Act::Spare(c) => self.spare.push_back((strike::block_cost(&c).unwrap_or(1), c)),
                // (a landed piece's blocks in on the tick it lands, whatever waits: the pass may then let it go)
                Act::Blocks(b) if b.landing.is_some() => {
                    meter::spend(edit_cost(&b));
                    world::edit_blocks(&b.edit());
                    if let Some(t) = b.landing {
                        s.params[14] = s.params[14].max(t);
                    }
                }
                // the rest in order, as many a tick as the frame time allows (`edit`)
                Act::Blocks(b) => {
                    meter::spend(60 * b.runs.len() as u64);
                    self.edits.push_back((pace::cost(&b.runs), self.edit_ticks, b))
                }
                Act::Survey { tag, columns } => ground::ask(tag, columns),
                Act::Read { tag, columns, below, above } => columns::ask(tag, columns, below, above),
                Act::Words { index, words } => {
                    let i = index as usize;
                    if s.data.len() < i + words.len() {
                        s.data.resize(i + words.len(), 0);
                    }
                    s.data[i..i + words.len()].copy_from_slice(&words);
                    s.data_sent = false;
                }
                Act::Table(words) => {
                    if s.data.len() < words.len() {
                        s.data.resize(words.len(), 0);
                    }
                    s.data[..words.len()].copy_from_slice(&words);
                    s.data_sent = false;
                }
                Act::Data { index, value } => {
                    let i = index as usize;
                    if s.data.len() <= i {
                        s.data.resize(i + 1, 0);
                    }
                    s.data[i] = value.to_bits();
                    s.data_sent = false;
                }
                Act::Soon(job) if worked_out || meter::full() => s.urgent.push_back(job),
                Act::Later(job) if worked_out || meter::full() => s.waiting.push_back(job),
                Act::Later(job) | Act::Soon(job) => {
                    // more of the plan, worked out now it is due
                    s.work_out(job);
                    worked_out = true;
                    trace("due stage");
                }
            }
        }
        trace("due");
        // (the edits due go in before the tick's commands, as they always have)
        self.edit();
        trace("edits");
        let Some(s) = &mut self.strike else {
            return;
        };
        if !cmds.is_empty() {
            world::run_commands(&cmds);
        }
        if !s.data_sent {
            render::set_data(&s.data);
            s.data_sent = true;
        }
        if !jolts.is_empty() {
            // the jolts due this tick as one (the game adds jolts up the same way, and takes only so many a call)
            let strength = jolts.iter().map(|j| j.0 * j.0).sum::<f32>().sqrt().min(1.0);
            let seconds = jolts.iter().map(|j| j.1).fold(0.0, f32::max);
            render::shake(strength, seconds);
        }
        if now >= s.length {
            self.end_strike();
        }
        self.carve(CARVE_CMDS.saturating_sub(carved));
        trace("end");
    }
    /// The strike is over: its pass off, what it asked of the world forgotten.
    fn end_strike(&mut self) {
        render::clear_post();
        self.strike = None;
        ground::clear();
        columns::clear();
        if let Some(w) = &mut self.wheel {
            w.striking = false;
            self.show_wheel();
        }
    }
    /// Stop the strike under way: the rest of its plan and the world changes still waiting are dropped and its sounds
    /// cut short, but the chunks it force-loaded are let go (what it has already done to the world stays).
    fn stop_strike(&mut self) {
        let Some(s) = &mut self.strike else { return };
        let mut cmds: Vec<String> = s.sounds.iter().map(|e| format!("stopsound @s * {e}")).collect();
        let more = std::mem::take(&mut s.more).into_vec().into_iter().map(|g| (g.t, g.act));
        let rest = s.plan.drain(s.next..).chain(more).filter_map(|(_, a)| match a {
            Act::Cmd(c) | Act::Spare(c) => Some(c),
            _ => None,
        });
        self.edits.clear();
        self.edits_late = 0;
        self.edited = false;
        let queued = self.carving.drain(..).chain(self.spare.drain(..)).map(|(_, c)| c);
        cmds.extend(rest.chain(queued).filter(|c| c.starts_with("forceload remove")));
        world::run_commands(&cmds);
        self.end_strike();
        Self::actionbar("STRIKE STOPPED", "gray");
        log::write(log::Level::Info, "strike stopped");
    }
    /// Make the waiting block edits, in order, as many as this tick's budget allows (`pace`: all of them while the
    /// frames are quick, at least one).
    fn edit(&mut self) {
        let budget = self.pace.tick(self.edited || !self.edits.is_empty());
        let n = pace::Pace::release(budget, self.edits.iter().map(|e| e.0)).min(self.edits.len());
        // (and no more than the tick's work allows, `meter`: however long the queue, a tick hands the game only so
        // many runs; the first goes in unless the tick has already done all it should)
        let mut m = 0;
        while m < n {
            if meter::over() || (m > 0 && meter::spent() >= meter::EDITS) {
                break;
            }
            let (_, due, b) = &self.edits[m];
            self.edits_late = self.edits_late.max(self.edit_ticks - due);
            meter::spend(edit_cost(b));
            world::edit_blocks(&b.edit());
            m += 1;
        }
        self.edits.drain(..m);
        self.edited = m > 0;
        self.edit_ticks += 1;
        if self.edits.is_empty() && self.edits_late > 0 {
            log::write(log::Level::Info, &format!("block edits paced: the last went in {:.2} s late", self.edits_late as f32 * 0.05));
            self.edits_late = 0;
        }
    }
    /// Run the waiting world changes, in order, as far as this tick's block budget goes (at least one), and no more
    /// than `room` commands; then, with what is left of it, the ones that wait for spare budget. How many it ran.
    fn carve(&mut self, room: usize) -> usize {
        if room == 0 {
            return 0;
        }
        let mut spent = 0;
        let mut cmds = Vec::new();
        while let Some((cost, _)) = self.carving.front() {
            if !cmds.is_empty() && (spent + cost > BLOCK_BUDGET || cmds.len() >= room || meter::full()) {
                break;
            }
            if meter::over() {
                break;
            }
            meter::spend(CMD_COST);
            spent += cost;
            if let Some((_, c)) = self.carving.pop_front() {
                cmds.push(c);
            }
        }
        // (nor while edits wait: the spare budget's forceloads must not let their chunks go under them)
        while self.carving.is_empty()
            && self.edits.is_empty()
            && let Some((cost, _)) = self.spare.front()
        {
            if (spent + cost > BLOCK_BUDGET || cmds.len() >= room || meter::full()) && (spent > 0 || !cmds.is_empty()) {
                break;
            }
            if meter::over() {
                break;
            }
            meter::spend(CMD_COST);
            spent += cost;
            if let Some((_, c)) = self.spare.pop_front() {
                cmds.push(c);
            }
        }
        if !cmds.is_empty() {
            world::run_commands(&cmds);
        }
        cmds.len()
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
            if l.key == "payload" || l.key == "nuke" {
                lines.push((format!("Quality: {}", if self.fast { "fast (smoke at half size)" } else { "full" }), 0xA8B0BC));
            }
            if (self.fly - 1.0).abs() > 1e-4 {
                lines.push((format!("Flying speed: {}", wheel::speed_label(self.fly)), 0x6FC8FF));
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
        let state = Orbital::new(Orbital::load());
        // the game keeps the flying speed from here on, in every world
        state.apply_fly();
        Ok((state, Registration::new().command("orbital").on_tick().on_frame()))
    }

    fn tick(&mut self, _tick: u64) {
        meter::reset();
        self.ticks += 1;
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
        for t in input::poll_typed() {
            self.typed(t);
        }
        if let Some(n) = self.aiming {
            let l = LASERS[self.laser];
            if n >= LOCK_TICKS {
                self.aiming = None;
                self.fire();
            } else {
                if n % 4 == 0 {
                    // (the sinkhole comes from nothing overhead: it reads the ground under the crosshair instead)
                    let what = match l.key {
                        "sinkhole" => "SEISMIC SCAN",
                        "payload" | "nuke" => "DESIGNATING",
                        _ => "ACQUIRING TARGET",
                    };
                    Self::actionbar(&format!("{what} {}  [{}]", ".".repeat(1 + n as usize / 4), l.title), l.color);
                }
                self.aiming = Some(n + 1);
            }
        }
        self.tick_strike();
        self.update_panel();
        meter::end(self.ticks);
        if let Some(n) = self.meter_log
            && meter::spent() >= n
        {
            let (q, c) = (self.edits.len(), self.carving.len() + self.spare.len());
            let w = self.strike.as_ref().map_or(0, |s| s.waiting.len() + s.urgent.len());
            log::write(log::Level::Info, &format!("meter: tick {} spent {:.2}M ({q} edits, {c} commands, {w} stages waiting)", self.ticks, meter::spent() as f64 / 1e6));
        }
    }

    fn frame(&mut self, seconds: f32) {
        meter::reset();
        self.since_tick += seconds;
        self.pace.frame(seconds);
        // Compile the post passes as the world loads, not when the first strike fires (that costs about a second): set
        // each for one frame, all but invisible (no strike clock, the lowest intensity), then clear it. The game keeps
        // the last one compiled for the strikes after; loading a laser that needs another one compiles that one the
        // same way (quickly, the driver has kept it), there and then rather than as it fires.
        let want = pass_of(LASERS[self.laser]);
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
        meter::reset();
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
            (Some("meter"), Some("trace")) => {
                TRACE.with(|t| t.set(!t.get()));
                Ok(Some(format!("Tracing the strike's ticks: {}", TRACE.with(std::cell::Cell::get))))
            }
            (Some("meter"), v) => {
                self.meter_log = v.and_then(|v| v.parse::<f64>().ok()).map(|m| (m * 1e6) as u64);
                let (peak, tick) = meter::take_peak();
                Ok(Some(format!("Busiest tick since the last look: {:.2}M (tick {tick}); logging ticks over {}", peak as f64 / 1e6, self.meter_log.map_or("none".into(), |m| format!("{:.2}M", m as f64 / 1e6)))))
            }
            (Some("stop"), _) => {
                if self.strike.is_none() {
                    return Err("No strike under way".into());
                }
                self.stop_strike();
                Ok(None)
            }
            (Some("skip"), Some(v)) => {
                let t: f32 = v.parse().map_err(|_| "/orbital skip SECONDS (0 to start at the beginning)".to_string())?;
                if self.terrain && t > 0.0 {
                    return Err("Skipping leaves out what the strike does to the land before then: /orbital terrain off first".into());
                }
                self.skip = t.max(0.0);
                Ok(Some(format!("The next strike starts {t} s in")))
            }
            (Some("flyspeed"), Some("reset")) => {
                self.set_fly(1.0);
                Ok(Some("Flying speed back to vanilla's (1x)".into()))
            }
            (Some("flyspeed"), Some(v)) => {
                let m = wheel::parse_speed(v).ok_or("/orbital flyspeed N (times vanilla's, over 0, up to 1000) or reset")?;
                self.set_fly(m);
                Ok(Some(format!("Flying speed {}", wheel::speed_label(self.fly))))
            }
            (Some("flyspeed"), None) => Ok(Some(format!("Flying speed {} (/orbital flyspeed N, or reset)", wheel::speed_label(self.fly)))),
            (Some("hud"), Some(v @ ("on" | "off"))) => {
                self.hud = v == "on";
                self.save();
                self.update_panel();
                Ok(Some(format!("Status panel {v}")))
            }
            (Some("shadow"), Some(v @ ("on" | "off"))) => {
                self.shadow_off = v == "off";
                if let Some(s) = &mut self.strike {
                    s.params[15] = if self.shadow_off { 1.0 } else { 0.0 };
                }
                Ok(Some(format!("Cloud shadows {v}")))
            }
            (Some("payloadsound"), Some(v @ ("main" | "alt"))) => {
                self.blast_alt = v == "alt";
                self.save();
                Ok(Some(format!("Payload blast: {}", if self.blast_alt { "alternative" } else { "main" })))
            }
            (Some("payloadsound"), None) => Ok(Some(format!(
                "Payload blast: {} (/orbital payloadsound main or alt)",
                if self.blast_alt { "alternative" } else { "main" }
            ))),
            (Some("quality"), Some(v @ ("full" | "fast"))) => {
                self.set_quality(v == "fast");
                Ok(Some(format!("Quality {}", if self.fast { "fast: the Payload's and the Nuke's smoke at half size" } else { "full: every pixel" })))
            }
            (Some("quality"), None) => Ok(Some(format!(
                "Quality: {} (/orbital quality full or fast)",
                if self.fast { "fast" } else { "full" }
            ))),
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
                "/orbital give | wheel | terrain on|off | messages on|off | hud on|off | quality full|fast | flyspeed N|reset | stop | skip SECONDS | approach {} | arrival {} | colour {} | {}",
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
    fn own_passes_are_whole_and_small() {
        // the downfall's and the planet killer's passes leave out the other lasers' own functions and fs_main, keep what
        // they use, and are under the game's 256 KiB
        for (p, kept) in [
            (super::PASS_OWN[1], &["fn bh_lens(", "fn ms_hull(", "fn ms_frame(", "fn downfall(", "fn ms_air("][..]),
            (super::PASS_OWN[2], &["fn ray_seg(", "fn bolt_line(", "fn mh(", "fn planet_killer(", "fn lava_ramp("][..]),
            (super::PASS_OWN[3], &["fn ray_seg(", "fn mh(", "fn gfbm3(", "fn crystal_bloom(", "fn rot_axis("][..]),
            (super::PASS_OWN[4], &["fn mh(", "fn vnoise3(", "fn sinkhole(", "fn rot_axis(", "fn ign("][..]),
            (super::payload_pass(false), &["fn mh(", "fn gnoise3(", "fn payload(", "fn ign("][..]),
            (super::nuke_pass(false), &["fn mh(", "fn gnoise3(", "fn nuke(", "fn ign("][..]),
        ] {
            for gone in ["fn singularity(", "fn meteor_storm(", "fn mothership(", "fn fs_main(in: StageIn) -> @location(0) vec4<f32> {\n    if (th_is"] {
                assert!(!p.contains(gone), "{gone}");
            }
            for kept in kept {
                assert!(p.contains(kept), "{kept}");
            }
            assert_eq!(p.matches("@fragment").count(), 1);
            assert!(p.len() <= 256 << 10);
        }
        // the payload's at QUALITY FULL is the one above; at FAST it keeps its half-size stage, still under 256 KiB
        let fast = super::payload_pass(true);
        assert_eq!(fast.matches("@fragment").count(), 3);
        assert!(fast.contains("fn fs_half(") && fast.contains("fn fs_join(") && fast.len() <= 256 << 10);
        assert!(!super::payload_pass(false).contains("half_picture"));
        for fast in [false, true] {
            let p = super::nuke_pass(fast);
            assert_eq!(p.matches("@fragment").count(), if fast { 3 } else { 1 });
            assert_eq!(p.contains("fn fs_half(") && p.contains("fn fs_join("), fast);
            assert!(p.len() <= 256 << 10);
            assert!(!p.contains("half_picture") || fast);
            assert_eq!(p.matches("    // ---- the mushroom cloud: raymarched").count(), 1);
            assert!(p.contains("fn nuke(") && p.contains("// ---- the bomb") && !p.contains("v10_"));
        }
        assert!(super::PASS_OWN[0].len() <= 256 << 10);
        assert!(!super::PASS_OWN[2].contains("fn downfall("));
        assert!(!super::PASS_OWN[3].contains("fn planet_killer("));
        assert!(!super::PASS_OWN[4].contains("fn crystal_bloom("));
        assert!(!super::payload_pass(false).contains("fn sinkhole("));
    }
    #[test]
    fn switching_quality_costs_nothing() {
        // a switch picks a ready-made pass (build.rs): no building, microseconds for every one of them back to back
        let t0 = std::time::Instant::now();
        let mut n = 0usize;
        for _ in 0..1000 {
            for fast in [false, true] {
                n += super::nuke_pass(fast).len() + super::payload_pass(fast).len();
            }
        }
        let each = t0.elapsed().as_secs_f64() * 1.0e6 / 2000.0;
        println!("a switch: {each:.3} us ({n})");
        assert!(each < 5.0, "{each} us");
    }
}

/// Strikes played through the mod's own playback (`tick_strike`, `edit`, `carve`, `stop_strike`, `fire`) against the
/// stand-in world of sdk.rs: fired again and again at one spot, stopped part way and fired again at once, the world's
/// answers to the reads coming at once, late, all together or never, the frames now quick and now slow (the edits
/// paced down and piling up). No tick may do more work (`meter`, which the fork's fuel harness ties to the game's
/// fuel) than a fair share of a tick's fuel, and a stop leaves nothing queued for the next strike to start on.
#[cfg(test)]
mod stress {
    use super::*;
    use horizon_mod_sdk::{
        game::Player,
        world::{ColumnBlocks, Hit, SurfaceHeights},
    };
    use sdk::fake;

    /// The most work a tick may do: well under the 50 million instructions of a tick's fuel.
    const CAP: u64 = 32_000_000;

    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            self.0
        }
        fn below(&mut self, n: u64) -> u64 {
            self.next() % n.max(1)
        }
    }

    /// The land round the target: hills, now and then deep craters of earlier strikes with water in their floor and
    /// lava under it, and trees.
    fn ground(x: i32, z: i32, cratered: bool) -> i32 {
        let (fx, fz) = (f64::from(x), f64::from(z));
        let mut h = 66.0 + 8.0 * (fx / 37.0).sin() * (fz / 53.0).cos();
        if cratered {
            let r = (fx - 1000.0).hypot(fz + 2000.0);
            if r < 110.0 {
                h -= 45.0 * (1.0 - (r / 110.0).powi(2));
            }
        }
        h as i32
    }
    fn column(x: i32, z: i32, below: u32, above: u32, cratered: bool) -> (i32, Vec<&'static str>) {
        let g = ground(x, z, cratered);
        let tree = (x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) % 40 == 0;
        let wet = cratered && g < 40;
        let top = if tree { g + 7 } else if wet { 41 } else { g + 1 };
        let blocks = (top - below as i32..top + above as i32)
            .map(|y| match y {
                _ if y < g - 30 && cratered && (x + z) % 5 == 0 => "minecraft:lava",
                _ if y < g - 3 => "minecraft:stone",
                _ if y < g => "minecraft:dirt",
                _ if y == g => "minecraft:grass_block",
                _ if wet && y <= 40 => "minecraft:water",
                _ if tree && y <= g + 5 => "minecraft:oak_log",
                _ if tree && y <= g + 7 => "minecraft:oak_leaves",
                _ => "minecraft:air",
            })
            .collect();
        (top, blocks)
    }
    fn answer(tag: u32, cols: &[(i32, i32)], below: u32, above: u32, cratered: bool) -> ColumnBlocks {
        let mut palette: Vec<String> = Vec::new();
        let (mut bases, mut blocks) = (Vec::new(), Vec::new());
        for &(x, z) in cols {
            let (top, names) = column(x, z, below, above, cratered);
            bases.push(Some(top));
            for n in names {
                let i = palette.iter().position(|p| p == n).unwrap_or_else(|| {
                    palette.push(n.to_string());
                    palette.len() - 1
                });
                blocks.push(i as u16);
            }
        }
        let tints = cols.iter().flat_map(|_| [0x91BD59, 0x77AB2F, 0x3F76E4]).collect();
        ColumnBlocks { tag, palette, bases, blocks, tints }
    }

    /// How the world answers a sequence's reads.
    #[derive(Clone, Copy, Debug)]
    enum Answers {
        Next,
        Late(u64),
        /// Held, then all at once every so many ticks.
        Bunched(u64),
        /// Not at all (the land not loaded, the reads lost).
        Never,
    }

    struct Soak {
        o: Orbital,
        rng: Rng,
        tick: u64,
        answers: Answers,
        cratered: bool,
        reads: Vec<(u64, u32, Vec<(i32, i32)>, u32, u32)>,
        surveys: Vec<(u64, u32, Vec<(i32, i32)>)>,
        frame: f32,
        worst: (u64, String),
    }
    impl Soak {
        fn new(seed: u64) -> Self {
            fake::with(|w| *w = fake::Fake::default());
            let mut o = Orbital::new(Orbital::parse(""));
            o.terrain = true;
            Soak { o, rng: Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1), tick: 0, answers: Answers::Next, cratered: false, reads: Vec::new(), surveys: Vec::new(), frame: 0.016, worst: (0, String::new()) }
        }
        fn due(&mut self) -> u64 {
            match self.answers {
                Answers::Next => self.tick + 1,
                Answers::Late(n) => self.tick + 1 + self.rng.below(n),
                Answers::Bunched(n) => (self.tick / n + 1) * n,
                Answers::Never => u64::MAX,
            }
        }
        /// One tick: the world's answers due handed over, the frames drawn, the strike's tick played.
        fn step(&mut self, what: &str) {
            self.tick += 1;
            let (reads, surveys) = fake::with(|w| (std::mem::take(&mut w.reads), std::mem::take(&mut w.surveys)));
            for (tag, cols, below, above) in reads {
                let due = self.due();
                self.reads.push((due, tag, cols, below, above));
            }
            for (tag, cols) in surveys {
                let due = self.due();
                self.surveys.push((due, tag, cols));
            }
            let now = self.tick;
            let cratered = self.cratered;
            let (ready, wait): (Vec<_>, Vec<_>) = std::mem::take(&mut self.reads).into_iter().partition(|r| r.0 <= now);
            self.reads = wait;
            let (sready, swait): (Vec<_>, Vec<_>) = std::mem::take(&mut self.surveys).into_iter().partition(|r| r.0 <= now);
            self.surveys = swait;
            fake::with(|w| {
                for (_, tag, cols, below, above) in ready {
                    w.columns.push(answer(tag, &cols, below, above, cratered));
                }
                // (the game keeps 16 answers for a mod between its polls, the latest)
                let n = w.columns.len();
                w.columns.drain(..n.saturating_sub(16));
                for (_, tag, cols) in sready {
                    let heights = cols.iter().map(|&(x, z)| Some(ground(x, z, cratered) + 1)).collect();
                    w.heights.push(SurfaceHeights { tag, heights });
                }
            });
            // (the frames: quick, or slow for a while)
            if self.rng.below(60) == 0 {
                self.frame = [0.007, 0.016, 0.016, 0.045, 0.09, 0.2][self.rng.below(6) as usize];
            }
            for _ in 0..3 {
                self.o.pace.frame(self.frame);
            }
            meter::reset();
            self.o.tick_strike();
            let spent = meter::spent();
            if spent > self.worst.0 {
                let t = self.o.strike.as_ref().map_or(-1.0, |s| s.ticks as f32 * 0.05);
                self.worst = (spent, format!("{what} at {t:.2} s ({} edits, {} commands waiting)", self.o.edits.len(), self.o.carving.len() + self.o.spare.len()));
            }
        }
        fn fire(&mut self, laser: usize, at: (i32, i32)) {
            let g = ground(at.0, at.1, self.cratered);
            fake::with(|w| {
                w.hit = Some(Hit { block_x: at.0, block_y: g, block_z: at.1, x: f64::from(at.0) + 0.5, y: f64::from(g + 1), z: f64::from(at.1) + 0.5, block: "minecraft:grass_block".into() });
                w.player = Some(Player { x: f64::from(at.0) + 0.5, y: f64::from(g) + 40.0, z: f64::from(at.1) + 150.5, yaw: 180.0, pitch: 15.0, health: 20.0, food: 20, dimension: "minecraft:overworld".into() });
                w.clock = 1000 + self.tick;
            });
            self.o.laser = laser;
            // (as the mod's tick fires it: in the tick, before the strike's playback)
            self.tick += 1;
            meter::reset();
            self.o.fire();
            self.o.tick_strike();
            let spent = meter::spent();
            if spent > self.worst.0 {
                self.worst = (spent, format!("{} firing", LASERS[laser].key));
            }
        }
        fn stop(&mut self) {
            meter::reset();
            self.o.stop_strike();
            // nothing left for the next strike to start on
            assert!(self.o.strike.is_none() && self.o.edits.is_empty() && self.o.carving.is_empty() && self.o.spare.is_empty());
            assert!(!self.o.edited);
        }
    }

    fn soak(sequences: u64, seed: u64) -> (u64, String) {
        let mut s = Soak::new(seed);
        let lasers: Vec<usize> = ["nuke", "nuke", "nuke", "nuke", "payload", "planetkiller", "crystalbloom", "sinkhole", "downfall", "blackhole"]
            .iter()
            .map(|k| LASERS.iter().position(|l| l.key == *k).expect("a laser"))
            .collect();
        for n in 0..sequences {
            let laser = lasers[s.rng.below(lasers.len() as u64) as usize];
            s.cratered = s.rng.below(2) == 0;
            s.answers = match s.rng.below(5) {
                0 => Answers::Next,
                1 => Answers::Late(10),
                2 => Answers::Late(60),
                3 => Answers::Bunched(10 + s.rng.below(60)),
                _ => Answers::Never,
            };
            let off = if s.rng.below(4) == 0 { 120 } else { 16 };
            let at = (1000 + s.rng.below(2 * off + 1) as i32 - off as i32, -2000 + s.rng.below(2 * off + 1) as i32 - off as i32);
            s.fire(laser, at);
            // stopped at once, soon, late or never; fired again at once or a little later
            let ticks = match s.rng.below(6) {
                0 => 1 + s.rng.below(5),
                1 => 5 + s.rng.below(60),
                2 => 60 + s.rng.below(300),
                3 => 300 + s.rng.below(500),
                _ => (LASERS[laser].length * 20.0) as u64 + 40,
            };
            let what = format!("#{n} {} {:?}", LASERS[laser].key, s.answers);
            for _ in 0..ticks {
                s.step(&what);
                if s.o.strike.is_none() {
                    break;
                }
            }
            if s.o.strike.is_some() {
                s.stop();
            }
            for _ in 0..[0, 0, 1, 3, 20][s.rng.below(5) as usize] {
                s.step(&what);
            }
        }
        s.worst
    }

    #[test]
    fn no_tick_overworks_through_fire_stop_and_refire() {
        let (worst, at) = soak(40, 1);
        eprintln!("worst tick: {:.2}M ({at})", worst as f64 / 1e6);
        assert!(worst <= CAP, "a tick of {:.2}M: {at}", worst as f64 / 1e6);
    }

    /// `ORBITAL_SOAK=N cargo test --release thousands_of_strikes -- --ignored --nocapture`: N sequences (default 2000).
    #[test]
    #[ignore]
    fn thousands_of_strikes() {
        let n = std::env::var("ORBITAL_SOAK").ok().and_then(|v| v.parse().ok()).unwrap_or(2000);
        let (worst, at) = soak(n, 7);
        eprintln!("{n} sequences, worst tick: {:.2}M ({at})", worst as f64 / 1e6);
        assert!(worst <= CAP, "a tick of {:.2}M: {at}", worst as f64 / 1e6);
    }

    #[test]
    fn an_artificially_heavy_stage_slows_the_strike_and_never_overworks_a_tick() {
        // a plan of stages each far more work than a tick should do (counted as such), with edits due beside them:
        // the stages wait a tick each, the edits and commands wait while the tick is full, and all of it goes in
        fake::with(|w| *w = fake::Fake::default());
        let mut o = Orbital::new(Orbital::parse(""));
        let heavy = |k: u32| -> strike::Stage {
            Box::new(move || {
                meter::spend(meter::SOFT - 1);
                (0..400).map(|i| (0.05 * f32::from(k as u16), Act::Cmd(format!("setblock {i} {k} 0 minecraft:stone")))).collect()
            })
        };
        let mut plan: Vec<(f32, Act)> = (0..60).map(|k| (0.05, Act::Later(heavy(k)))).collect();
        plan.extend((0..3000).map(|i| (0.05, Act::Cmd(format!("setblock {i} 1 1 minecraft:stone")))));
        o.strike = Some(Strike { plan, next: 0, more: Default::default(), given: 0, ticks: 0, length: 1000.0, params: [0.0; 16], waiting: Default::default(), urgent: Default::default(), data: Vec::new(), data_sent: true, skipped: 0.0, sounds: Default::default() });
        let mut worst = 0;
        let mut ticks = 0;
        while o.strike.as_ref().is_some_and(|s| s.next < s.plan.len() || !s.more.is_empty() || !s.waiting.is_empty()) || !o.carving.is_empty() {
            meter::reset();
            o.tick_strike();
            worst = worst.max(meter::spent());
            ticks += 1;
            assert!(ticks < 2000, "it never finished");
        }
        let ran = fake::with(|w| w.commands);
        assert_eq!(ran, 60 * 400 + 3000, "every command ran");
        assert!(ticks > 60, "a stage a tick at most: {ticks}");
        assert!(worst <= meter::HARD + 2 * meter::SOFT, "a tick of {:.2}M", worst as f64 / 1e6);
    }
}
