//! Orbital Laser, a Horizon mod. Hold the Orbital Laser Designator on a target
//! and the strike lands there: a beam from orbit, a crater to bedrock, and what
//! each laser leaves behind. Press R with the designator in hand for the laser
//! wheel (rebind R in Options > Controls). `/orbital give` hands you the designator.
//!
//! It uses the game's mod capabilities: `input` (the designator's right-click,
//! the wheel's key and what is typed on it), `ui` (the wheel), `render` (the
//! strike's post pass, shaders/strike.wgsl, and the downfall's and the planet
//! killer's own), `world` (aiming, the crater's block
//! changes, the sounds and the flying speed), `hud` (the status panel), `storage`
//! (the chosen laser and the settings) and
//! `registries` (the items, their textures and the sounds, in assets/ and data/).
mod carry;
mod columns;
mod follow;
mod ground;
mod lasers;
mod meter;
mod pace;
mod sdk;
pub mod smp;
mod strike;
mod surge;
mod wheel;

use horizon_mod_sdk::{
    Mod, Registration,
    hud::{self, Corner, Line},
    input::{self, Event},
    ui,
};
use sdk::{chat, game, log, render, storage, world};
use lasers::{LASERS, is_ship};
use strike::{APPROACHES, ARRIVALS, Act, COLOUR_RGB, COLOURS, FIRE, Target};

const DESIGNATOR: &str = "orbital:laser_designator";
/// Ticks of holding the designator on a target before it fires.
const LOCK_TICKS: u32 = 14;
// Every post pass, built ahead of time from the shader files by build.rs (src/passbuild.rs): PASS_OWN (the other
// lasers', strike.wgsl itself, then the downfall's, the planet killer's, the crystal bloom's and the sinkhole's: strike.wgsl
// up to its fs_main less the other lasers' own functions, then shaders/downfall.wgsl ...), PASS_PAYLOAD, PASS_NUKE and PASS_ROD (at
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
/// The Rod from God's, the same way (rod.wgsl's `[half stage]`: its dust column, dust ring and trail at half size).
fn rod_pass(fast: bool) -> &'static str {
    PASS_ROD[usize::from(fast)]
}
/// The Supercell's, the same way (supercell.wgsl's `[half stage]`: its storm cloud, rain and funnels at half size).
fn supercell_pass(fast: bool) -> &'static str {
    PASS_SUPERCELL[usize::from(fast)]
}
/// The Hurricane's, the same way (hurricane.wgsl's `[half stage]`: its cloud, rain and dust at half size, the blocks and
/// trees it carries found there and drawn sharp at full size).
fn hurricane_pass(fast: bool) -> &'static str {
    PASS_HURRICANE[usize::from(fast)]
}
/// The Tsunami's, the same way (tsunami.wgsl's `[half stage]`, if it has one).
fn tsunami_pass(fast: bool) -> &'static str {
    PASS_TSUNAMI[usize::from(fast)]
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
        "rod" => 7,
        "supercell" => 8,
        "hurricane" => 9,
        // (10 and 11 are spare)
        "tsunami" => 12,
        _ => 0,
    }
}
const SETTINGS: &str = "settings";
/// The storage key that says which pass the game is building while it builds one (`Orbital::hand_post`).
const BUILDING: &str = "building";
/// The storage key holding the forceload removes the strike under way owes the world, with its dimension and the
/// world clock it fired at (`hold_forceloads`): if the game closes or the player leaves the world mid-strike, they are
/// run the next time that world is played (`release_held`), so a save is never left with the strike's chunks
/// forceloaded.
const FORCELOADS: &str = "forceloads";
/// The storage key that says the player knows how to get the Designator (they ran `/orbital give`, or held one): the
/// join hint (`HINT`) is no longer shown.
const KNOWS: &str = "knows-give";
/// The first line on joining a world, until the player knows how to get the Designator (`KNOWS`): shown in chat as
/// `[Orbital Laser] Type /orbital give ...` (`chat::show`, only the player sees it).
const HINT: &str = "Type /orbital give for the Designator. Hold it and press R to pick a laser.";
/// Ticks after joining before the hint goes out, so it comes after the world's own lines.
const HINT_AFTER: u32 = 20;
/// Whether the player holds the Designator (in the tests, as the stand-in world says: `sdk::fake`).
fn holding_designator() -> bool {
    #[cfg(not(test))]
    return input::held().is_some_and(|h| h.id == DESIGNATOR);
    #[cfg(test)]
    return sdk::fake::with(|w| w.holding);
}
/// Game ticks (of the world's clock) a reopened world may be off from where it was left and still be taken for the
/// same play (`tick`): a pause, or a save and quit, keeps the clock where it was; another world's is elsewhere.
const SAME_PLAY: u64 = 40;
/// A jump of the world's clock is another world only if the game was somewhere else meanwhile (`in_world`): more than
/// AWAY seconds of frames since the last tick, each frame counting at most AWAY_FRAME (one stalled frame is no time
/// away), or the player over AWAY_ROOM blocks from where they were a tick ago.
const AWAY: f32 = 0.75;
const AWAY_FRAME: f32 = 0.25;
const AWAY_ROOM: f64 = 16.0;
/// Ticks of play (in a world, not paused) before the loaded laser's pass is given to the game to build ahead of its
/// first strike (`warm`): not as the game starts, so a pass the game can't build stops nothing but that laser.
const WARM_AFTER: u64 = 60;
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
    /// Its laser, and the game's textures as they were when its table packed them (`atlas.resources-version`: the
    /// Hurricane's blocks drawn with them are packed again when it changes).
    key: &'static str,
    sprites: u64,
}

/// The Rod's impact frames' looks, by rod.wgsl's RD_IF_STYLE number, and the order the wheel shows them in.
const IMPACT_STYLES: [&str; 3] = ["blackflash", "kanada", "cinematic"];
const IMPACT_ORDER: [u8; 3] = [1, 0, 2];

/// How many looks a strike's seed picks from (1 to SEEDS).
const SEEDS: u32 = 997;

/// A blast front's knockback for a player standing at `at` (`Act::Shove`): their velocity's kick, blocks a tick, away
/// from `from` along the ground at `out` and up at `up`, as much of it as `strike::knock_share` gives (the lift a third
/// of it at the least); none past its reach. The game adds it to the player's motion (`world.push-player`): they are
/// thrown, collide as they go and fall back under gravity, as from an explosion.
fn knockback(from: [f64; 3], at: [f64; 3], out: f32, up: f32, reach: f32) -> Option<[f32; 3]> {
    let (dx, dz) = (at[0] - from[0], at[2] - from[2]);
    let d = dx.hypot(dz);
    let k = strike::knock_share(d, reach);
    if k < 0.03 {
        return None;
    }
    // (straight out from under the middle; right under it, any way)
    let (ux, uz) = if d > 0.5 { ((dx / d) as f32, (dz / d) as f32) } else { (0.0, 1.0) };
    Some([ux * out * k, up * (0.35 + 0.65 * k.min(1.0)), uz * out * k])
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
        let own = meter::spent().saturating_sub(before);
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
    hud: bool,
    approach: usize,
    arrival: usize,
    page: usize,
    colours: Vec<usize>,
    fly: f32,
    blast_alt: [bool; 2],
    fast: bool,
    impact: bool,
    knock: bool,
    follow: bool,
    follow_distance: f64,
    seed_lock: Option<u32>,
    impact_style: u8,
    carry_turn: bool,
}

/// A ship laser's colour until one is picked (strike::COLOURS): the Mothership green, the Downfall red.
fn default_colour(i: usize) -> usize {
    usize::from(LASERS[i].key == "downfall")
}

struct Orbital {
    /// The post passes (0 the other lasers', 1 the downfall's, 2 the planet killer's, 3 the crystal bloom's, 4 the
    /// sinkhole's, 5 the payload's, 6 the nuke's, 7 the rod's, 8 the supercell's, 9 the hurricane's, 12 the tsunami's), the one the
    /// game last compiled, and whether it is being now, ahead of a strike (see `frame`).
    passes: [&'static str; 13],
    compiled: Option<usize>,
    warming: bool,
    /// A pick has left the wheel up while its pass is built (`close_picked`).
    closing: bool,
    /// Frames since a pass new to the game was handed to it, while the storage says it is being built (`hand_post`).
    building: Option<u8>,
    /// The laser whose pass the game stopped building last time, to tell the player of once they are in a world
    /// (`recover`).
    broke: Option<usize>,
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
    /// Whether the status panel shows at the top right while the player holds one of the items.
    hud: bool,
    /// Which way the ship lasers' ship comes in (strike::APPROACHES), and how it arrives (strike::ARRIVALS).
    approach: usize,
    arrival: usize,
    /// The wheel's page last shown.
    page: usize,
    /// Each laser's ship colour (strike::COLOURS; only the ship lasers use theirs).
    colours: Vec<usize>,
    /// Whether each of wheel::SOUND_LASERS plays its alternative blast (`/orbital payloadsound`, `/orbital nukesound`;
    /// the Payload's thump through the ground swaps with it).
    blast_alt: [bool; 2],
    /// The player's flying speed, in times vanilla's (the wheel's bar and field, `/orbital flyspeed`).
    fly: f32,
    /// QUALITY FAST: the Payload's smoke drawn at half size (`payload_pass`; the wheel's switch, `/orbital quality`).
    fast: bool,
    /// The Rod from God's impact frames (`/orbital impactframes`, the wheel's IMPACT FX switch): its stark full-screen
    /// flash frames as it strikes, on (the default) or off.
    impact: bool,
    /// Which look the Rod's impact frames take (rod.wgsl's RD_IF_STYLE numbering: 0 Black Flash, 1 Kanada, 2
    /// cinematic), `/orbital impactframes kanada|blackflash|cinematic`, the wheel's IMPACT FX row.
    impact_style: u8,
    /// The Nuke's and the Rod's knockback on the player (`/orbital knockback`, the wheel's KNOCKBACK switch): off leaves
    /// out their `Act::Shove` (the camera's jolt stays).
    knock: bool,
    /// The follow camera (`/orbital follow`, the wheel's FOLLOW switch): the Nuke's and the Payload's bomb chased down
    /// (`follow.rs`), and the one under way.
    follow: bool,
    following: Option<follow::Follow>,
    /// The Hurricane's carry of the player (`carry.rs`), while its strike is under way and the knockback is on.
    carrying: Option<carry::Carry>,
    /// The game's last answer to a carry (`world.carry-player`): whether the one before held the player.
    carry_held: bool,
    /// The Tsunami's surge carrying the player (`surge.rs`), while its strike is under way and the knockback is on.
    surging: Option<surge::Surge>,
    /// Whether the carry turns the player's view a little with them round the storm and sways it with the gusts
    /// (`/orbital carryview turn|still`; turn, the default).
    carry_turn: bool,
    /// The follow camera's orbit distance (`/orbital follow distance N`).
    follow_distance: f64,
    /// A strike's look held fixed (`/orbital seed N|lock|random`, the wheel's SEED switch): the same trail, cloud and
    /// crater every time from the same spot, for repeat takes. None, a fresh seed every strike (the default).
    seed_lock: Option<u32>,
    /// The last strike's seed (`/orbital seed lock` keeps it), once one has been fired this session.
    last_seed: u32,
    fired: bool,
    /// Ticks the designator has been held, while it is.
    aiming: Option<u32>,
    /// Seconds the next strike starts in at (`/orbital skip`, for looking at one moment of it; terrain off only).
    skip: f32,
    /// The Payload's and the Nuke's cloud shadows on the land left out (`/orbital shadow off`: for looking at them
    /// side by side; not kept).
    shadow_off: bool,
    /// What a stopped strike still has to do (`Act::Cleanup`), a stage a tick, its edits queued with the rest.
    cleanup: std::collections::VecDeque<strike::Stage>,
    strike: Option<Strike>,
    wheel: Option<wheel::Wheel>,
    /// The HUD panel last sent.
    panel: Vec<(String, u32)>,
    /// Whether the panel shows in the top left (the seed alone, the status panel being off) rather than the top right.
    panel_left: bool,
    /// `/orbital meter N`: each tick whose work (`meter`) comes to N instructions or more is logged.
    meter_log: Option<u64>,
    ticks: u64,
    /// The world's clock (game time) at the last tick in a world, none while out of one (`tick`).
    clock: Option<u64>,
    /// Where the player was last tick, and the seconds of frames since it (`AWAY_FRAME`): `in_world`.
    place: Option<[f64; 3]>,
    away: f32,
    /// The forceload removes in storage are the strike under way's (`FORCELOADS`): deleted once it and the world
    /// changes it left waiting are done.
    owes: bool,
    /// Ticks since joining a world while the join hint is still to go out (`HINT`), and whether the player knows how to
    /// get the Designator (`KNOWS`; read from storage the first time it's asked).
    hint: Option<u32>,
    knows: Option<bool>,
    /// Ticks in a world since the mod started or the player came back to one: the stored forceload removes of a
    /// strike broken off are looked at once they have settled (`release_held`).
    settled: Option<u32>,
}

thread_local! {
    /// `/orbital meter trace`: each part of a strike's tick logged with what the meter says by then (`fuel:`, which the
    /// fork's soak harness tells the fuel used by then of).
    static TRACE: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}
pub(crate) fn trace(what: &str) {
    if TRACE.with(std::cell::Cell::get) {
        log::write(log::Level::Info, &format!("fuel: {what} (meter {:.2}M)", meter::spent() as f64 / 1e6));
    }
}

impl Orbital {
    /// The mod's state with these settings, nothing under way.
    fn new(settings: Settings) -> Orbital {
        let Settings { laser, terrain, hud, approach, arrival, page, colours, fly, blast_alt, fast, impact, knock, follow, follow_distance, seed_lock, impact_style, carry_turn } = settings;
        Orbital {
            passes: [PASS_OWN[0], PASS_OWN[1], PASS_OWN[2], PASS_OWN[3], PASS_OWN[4], payload_pass(fast), nuke_pass(fast), rod_pass(fast), supercell_pass(fast), hurricane_pass(fast), PASS_OWN[0], PASS_OWN[0], tsunami_pass(fast)],
            compiled: None,
            warming: false,
            closing: false,
            building: None,
            broke: None,
            carving: std::collections::VecDeque::new(),
            spare: std::collections::VecDeque::new(),
            edits: std::collections::VecDeque::new(),
            edited: false,
            edit_ticks: 0,
            edits_late: 0,
            pace: pace::Pace::default(),
            laser,
            terrain,
            hud,
            approach,
            arrival,
            page,
            colours,
            fly,
            blast_alt,
            fast,
            impact,
            impact_style,
            knock,
            follow,
            following: None,
            carrying: None,
            carry_held: true,
            surging: None,
            carry_turn,
            follow_distance,
            seed_lock,
            last_seed: 1,
            fired: false,
            aiming: None,
            skip: 0.0,
            shadow_off: false,
            cleanup: Default::default(),
            strike: None,
            wheel: None,
            panel: Vec::new(),
            panel_left: false,
            meter_log: None,
            ticks: 0,
            clock: None,
            place: None,
            away: 0.0,
            owes: false,
            hint: None,
            knows: None,
            settled: Some(0),
        }
    }
    fn save(&self) {
        let text = format!(
            "laser={}\nterrain={}\nhud={}\napproach={}\narrival={}\npage={}\nflyspeed={}\npayloadsound={}\nnukesound={}\nquality={}\nimpactframes={}\nknockback={}\ncarryview={}\nfollow={}\nfollowdistance={}\nseed={}\n",
            LASERS[self.laser].key,
            u8::from(self.terrain),
            u8::from(self.hud),
            APPROACHES[self.approach].key,
            ARRIVALS[self.arrival].key,
            self.page,
            self.fly,
            if self.blast_alt[0] { "alt" } else { "main" },
            if self.blast_alt[1] { "alt" } else { "main" },
            if self.fast { "fast" } else { "full" },
            if self.impact { IMPACT_STYLES[usize::from(self.impact_style.min(2))] } else { "off" },
            if self.knock { "on" } else { "off" },
            if self.carry_turn { "turn" } else { "still" },
            if self.follow { "on" } else { "off" },
            self.follow_distance,
            self.seed_lock.map_or("random".to_string(), |s| s.to_string())
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
    /// The game stopped last time while it built a pass (the storage still says which: `hand_post`): Apple's Metal
    /// shader compiler has brought it down on the Downfall's and the Nuke's. If that is the loaded laser's, the Plasma
    /// is loaded instead (and kept), so the game doesn't stop again on every start; which laser it was, to tell the
    /// player of.
    fn recover(settings: &mut Settings) -> Option<usize> {
        let pass = storage::get(BUILDING).and_then(|b| String::from_utf8_lossy(&b).trim().parse::<usize>().ok());
        storage::delete(BUILDING);
        let pass = pass?;
        log::write(log::Level::Warn, &format!("the game stopped last time while it built post pass {pass}"));
        let broke = settings.laser;
        (pass != 0 && pass_of(LASERS[broke]) == pass).then(|| {
            settings.laser = 0;
            broke
        })
    }
    fn parse(text: &str) -> Settings {
        let mut laser = 0;
        let mut terrain = true;
        let mut hud = true;
        let mut approach = 0;
        let mut arrival = 0;
        let mut page = 0;
        let mut fly = 1.0;
        let mut blast_alt = [false; 2];
        let mut fast = true;
        let mut impact = true;
        let mut impact_style = 1u8;
        let mut knock = true;
        let mut carry_turn = true;
        let mut follow = false;
        let mut follow_distance = follow::DISTANCE;
        let mut seed_lock = None;
        let mut colours: Vec<usize> = (0..LASERS.len()).map(default_colour).collect();
        for line in text.lines() {
            match line.split_once('=') {
                Some(("laser", k)) => laser = LASERS.iter().position(|l| l.key == k).unwrap_or(0),
                Some(("terrain", v)) => terrain = v != "0",
                Some(("hud", v)) => hud = v != "0",
                Some(("approach", k)) => approach = APPROACHES.iter().position(|a| a.key == k).unwrap_or(0),
                Some(("arrival", k)) => arrival = ARRIVALS.iter().position(|a| a.key == k).unwrap_or(0),
                Some(("page", v)) => page = v.parse::<usize>().unwrap_or(0).min(wheel::pages() - 1),
                Some(("flyspeed", v)) => fly = wheel::parse_speed(v).unwrap_or(1.0),
                Some((k, v)) if wheel::SOUND_LASERS.iter().any(|s| s.1 == k) => {
                    blast_alt[wheel::SOUND_LASERS.iter().position(|s| s.1 == k).unwrap_or(0)] = v == "alt";
                }
                Some(("quality", v)) => fast = v != "full",
                Some(("impactframes", v)) => {
                    impact = v != "off";
                    if let Some(i) = IMPACT_STYLES.iter().position(|&s| s == v) {
                        impact_style = i as u8;
                    }
                }
                Some(("knockback", v)) => knock = v != "off",
                Some(("carryview", v)) => carry_turn = v != "still",
                Some(("follow", v)) => follow = v == "on",
                Some(("followdistance", v)) => {
                    follow_distance = v.parse::<f64>().ok().filter(|d| d.is_finite()).map_or(follow::DISTANCE, |d| d.clamp(follow::DISTANCE_MIN, follow::DISTANCE_MAX));
                }
                Some(("seed", v)) => seed_lock = v.parse::<u32>().ok().filter(|s| (1..=SEEDS).contains(s)),
                Some((k, v)) if k.starts_with("colour_") => {
                    if let (Some(i), Some(c)) = (LASERS.iter().position(|l| l.key == &k[7..]), COLOURS.iter().position(|c| c.key == v)) {
                        colours[i] = c;
                    }
                }
                _ => {}
            }
        }
        Settings { laser, terrain, hud, approach, arrival, page, colours, fly, blast_alt, fast, impact, knock, follow, follow_distance, seed_lock, impact_style, carry_turn }
    }

    /// The one message over the hotbar: the designator has nothing in range to aim at (`fire`).
    fn actionbar(text: &str, color: &str) {
        world::run_commands(&[format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#)]);
    }
    /// The designator can't fire while a strike is under way: a dull click at the player.
    fn refuse() {
        world::play_sound("minecraft:block.dispenser.fail", None, 0.5, 1.2);
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
        let seed = self.wheel.as_ref().is_some_and(|w| w.seed_typing);
        let Some(field) = self.wheel.as_mut().and_then(|w| w.typing.as_mut()) else {
            return;
        };
        match t {
            input::Typed::Text(s) if seed => wheel::type_seed(field, &s),
            input::Typed::Text(s) => wheel::type_into(field, &s),
            input::Typed::Key(k) if k == "key.keyboard.backspace" => {
                field.pop();
            }
            input::Typed::Key(k) if k == "key.keyboard.enter" || k == "key.keyboard.keypad.enter" => {
                let typed = std::mem::take(field);
                if let Some(w) = &mut self.wheel {
                    w.typing = None;
                    w.seed_typing = false;
                }
                if seed {
                    // the field's seed: the one held, if the lock is on; otherwise the one the lock would hold
                    match typed.parse::<u32>().ok().filter(|n| (1..=SEEDS).contains(n)) {
                        Some(n) => {
                            self.last_seed = n;
                            self.fired = true;
                            if self.seed_lock.is_some() {
                                self.seed_lock = Some(n);
                                self.save();
                            }
                            world::play_sound("minecraft:ui.button.click", None, 0.6, 1.6);
                        }
                        None if !typed.is_empty() => world::play_sound("minecraft:ui.button.click", None, 0.6, 0.6),
                        None => {}
                    }
                    self.show_wheel();
                    return;
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
            ui::show(&w.draws(self.laser, self.terrain, self.hud, self.approach, self.arrival, &self.colours, &self.blast_alt, self.fast, if self.impact { 1 + usize::from(IMPACT_ORDER.iter().position(|&s| s == self.impact_style).unwrap_or(0) as u8) } else { 0 }, self.knock, self.follow, self.seed_lock.is_some(), self.seed_lock.or(self.fired.then_some(self.last_seed))));
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
    /// A pick closes the wheel. If the picked laser's pass isn't the one the game holds, the wheel stays up for the two
    /// frames it takes to build it (`warm`), saying so: the build stops the game's frames for up to seconds the first
    /// time and some 60 ms after, and over the wheel that reads as the pick being taken, not as the world hitching.
    fn close_picked(&mut self) {
        if self.compiled == Some(pass_of(LASERS[self.laser])) || self.strike.is_some() || self.ticks < WARM_AFTER {
            ui::close();
            self.wheel = None;
            return;
        }
        self.closing = true;
        if let Some(w) = &mut self.wheel {
            w.loading = Some(self.laser);
        }
        self.show_wheel();
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
        if self.closing {
            return;
        }
        let (row, page) = self.wheel.as_ref().map_or((None, self.page), |w| (w.row_laser(self.laser), w.page));
        let spot = wheel::spot(x, y, wheel::Rows::of(row), page).or_else(|| wheel::toggle_spot(x, y, row.unwrap_or(self.laser)));
        // a click anywhere but the field takes the keyboard from it, leaving the speed as it was
        if let Some(w) = &mut self.wheel
            && w.typing.is_some()
            && spot != Some(if w.seed_typing { wheel::Spot::SeedField } else { wheel::Spot::FlyField })
        {
            w.typing = None;
            w.seed_typing = false;
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
                    if w.seed_typing {
                        w.typing = None;
                    }
                    w.seed_typing = false;
                    w.typing.get_or_insert_with(String::new);
                }
                world::play_sound("minecraft:ui.button.click", None, 0.5, 1.4);
                self.show_wheel();
            }
            Some(wheel::Spot::Laser(i)) => {
                self.laser = i;
                self.save();
                self.close_picked();
                world::play_sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
            }
            Some(wheel::Spot::Page(k)) => self.turn_page(k),
            Some(wheel::Spot::Approach(a)) => {
                // picking how it comes in loads the ship laser the row is for too
                self.approach = a;
                self.laser = row.unwrap_or(self.laser);
                self.save();
                self.close_picked();
                world::play_sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
            }
            Some(wheel::Spot::Arrival(a)) => {
                self.arrival = a;
                self.laser = row.unwrap_or(self.laser);
                self.save();
                self.close_picked();
                world::play_sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
            }
            Some(wheel::Spot::Colour(c)) => {
                let i = row.unwrap_or(self.laser);
                self.colours[i] = c;
                self.laser = i;
                self.save();
                self.close_picked();
                world::play_sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
            }
            Some(wheel::Spot::Sound(k)) => {
                // picking the Payload's or the Nuke's blast loads it too
                self.laser = row.unwrap_or(self.laser);
                if let Some(s) = wheel::sound_of(LASERS[self.laser].key) {
                    self.blast_alt[s] = k == 1;
                }
                self.save();
                self.close_picked();
                world::play_sound("minecraft:block.beacon.activate", None, 0.5, 1.6);
            }
            Some(wheel::Spot::Centre) => {
                self.terrain = !self.terrain;
                self.save();
                world::play_sound("minecraft:ui.button.click", None, 0.6, if self.terrain { 1.6 } else { 1.0 });
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
            Some(wheel::Spot::Impact(k)) => {
                if k > 0 {
                    self.impact_style = IMPACT_ORDER[(k - 1).min(2)];
                }
                self.set_impact(k > 0);
                world::play_sound("minecraft:ui.button.click", None, 0.6, if self.impact { 1.6 } else { 1.0 });
                self.show_wheel();
            }
            Some(wheel::Spot::Knock) => {
                self.knock = !self.knock;
                self.save();
                world::play_sound("minecraft:ui.button.click", None, 0.6, if self.knock { 1.6 } else { 1.0 });
                self.show_wheel();
            }
            Some(wheel::Spot::Follow) => {
                self.set_follow(!self.follow);
                world::play_sound("minecraft:ui.button.click", None, 0.6, if self.follow { 1.6 } else { 1.0 });
                self.show_wheel();
            }
            Some(wheel::Spot::SeedField) => {
                if let Some(w) = &mut self.wheel {
                    w.typing = Some(String::new());
                    w.seed_typing = true;
                }
                world::play_sound("minecraft:ui.button.click", None, 0.5, 1.4);
                self.show_wheel();
            }
            Some(wheel::Spot::SeedLock) => {
                self.seed_lock = if self.seed_lock.is_some() { None } else { Some(self.last_seed) };
                self.save();
                world::play_sound("minecraft:ui.button.click", None, 0.6, if self.seed_lock.is_some() { 1.6 } else { 1.0 });
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
        self.rebuild("rod", rod_pass(fast));
        self.rebuild("supercell", supercell_pass(fast));
        self.rebuild("hurricane", hurricane_pass(fast));
        self.rebuild("tsunami", tsunami_pass(fast));
        self.update_panel();
    }
    /// The Rod's impact frames on or off, kept, and at once for a strike under way.
    fn set_impact(&mut self, on: bool) {
        self.impact = on;
        self.save();
        let flags = self.flags_of(11);
        if let Some(s) = &mut self.strike
            && s.params[7] == 11.0
        {
            s.params[15] = flags;
        }
    }
    /// The follow camera on or off, kept; off ends the one under way at once (the player put back).
    fn set_follow(&mut self, on: bool) {
        self.follow = on;
        self.save();
        if !on {
            self.unfollow();
        }
    }
    /// The follow camera under way ended: the player back where they stood (their view as it is).
    fn unfollow(&mut self) {
        if let Some(f) = self.following.take() {
            world::run_commands(&f.finish());
        }
    }
    /// The follow camera's kicks this tick (`follow.rs`): the player moved by the game itself onto the orbit round the
    /// bomb, the way they look setting the angle; never turned.
    fn follow_tick(&mut self) {
        let Some(t) = self.strike.as_ref().map(|s| f64::from(s.ticks) * 0.05) else { return };
        let Some(f) = &mut self.following else { return };
        if f.over(t) {
            self.unfollow();
            return;
        }
        let Some(p) = game::get_player() else { return };
        for [x, y, z] in f.tick(t, [p.x, p.y, p.z], follow::look(p.yaw, p.pitch)) {
            world::push_player(x, y, z);
        }
    }
    /// The Hurricane's carry this tick (`carry.rs`): the player carried along their path round the storm once its wind
    /// has them, their view turning a little with them unless `/orbital carryview still`.
    fn carry_tick(&mut self) {
        let Some(t) = self.strike.as_ref().map(|s| f64::from(s.ticks) * 0.05) else { return };
        let Some(c) = &mut self.carrying else { return };
        if c.over(t) {
            self.carrying = None;
            return;
        }
        let Some(p) = game::get_player() else { return };
        let o = c.tick(t, [p.x, p.y, p.z], self.carry_held, game::player_flying(), self.carry_turn);
        // (thrown: a push while carried is the throw the game lets them go with as the carry stops)
        if let Some([x, y, z]) = o.throw {
            world::push_player(x, y, z);
        }
        if !o.cmds.is_empty() {
            world::run_commands(&o.cmds);
        }
        // (the game's answer: whether the carry it was asked for before held them)
        let held = match o.carry {
            Some([x, y, z]) => world::carry_player(x, y, z, o.turn),
            None => true,
        };
        self.carry_held = held;
        for (event, volume, pitch) in o.sounds {
            world::play_sound(&event, None, volume, pitch);
        }
    }
    /// The Tsunami's surge this tick (`surge.rs`): the player carried along with the water once it has them.
    fn surge_tick(&mut self) {
        let Some(t) = self.strike.as_ref().map(|s| f64::from(s.ticks) * 0.05) else { return };
        let Some(c) = &mut self.surging else { return };
        if c.over(t) {
            // (still held as the strike ends: set down, as the water does, not left flying)
            if let Some([x, y, z]) = c.set_down().filter(|_| c.lifted()) {
                world::push_player(x, y, z);
            }
            self.surging = None;
            return;
        }
        let Some(p) = game::get_player() else { return };
        let o = c.tick(t, [p.x, p.y, p.z], f64::from(p.yaw), self.carry_held, game::player_flying(), self.carry_turn);
        // (set down: a push while carried is what the game lets them go with, out of flight)
        if let Some([x, y, z]) = o.throw {
            world::push_player(x, y, z);
        }
        if !o.cmds.is_empty() {
            world::run_commands(&o.cmds);
        }
        // (the game's answer: whether the carry it was asked for before held them)
        let held = match o.carry {
            Some([x, y, z]) => world::carry_player(x, y, z, o.turn),
            None => true,
        };
        self.carry_held = held;
        for (event, volume, pitch) in o.sounds {
            world::play_sound(&event, None, volume, pitch);
        }
    }
    /// What the smoke lasers' pass reads in params[15] (laser `index`'s): 1 if the cloud shadows are off (`/orbital
    /// shadow off`), and for the Rod from God 2 more if its impact frames are.
    fn flags_of(&self, index: u32) -> f32 {
        f32::from(u8::from(self.shadow_off)) + if index == 11 { if self.impact { 4.0 * f32::from(1 + self.impact_style) } else { 2.0 } } else { 0.0 }
    }
    /// Laser `key`'s pass is `pass` from now on: given to the game at once if its strike is drawing it (else compiled
    /// ahead of the next, as the passes are).
    fn rebuild(&mut self, key: &str, pass: &'static str) {
        let pl = pass_of(LASERS.iter().find(|l| l.key == key).expect("the laser"));
        self.passes[pl] = pass;
        if self.compiled == Some(pl) {
            self.compiled = None;
            if self.strike.is_some() {
                self.hand_post(pl);
            }
        }
    }
    /// A frame's part in building the passes (`hand_post`).
    fn warm(&mut self) {
        // (a pass handed to the game is built as that frame is drawn: a few frames on, it was, and the game is still up)
        if let Some(n) = &mut self.building {
            *n += 1;
            if *n >= 3 {
                storage::delete(BUILDING);
                self.building = None;
            }
        }
        // Compile the loaded laser's pass ahead of its first strike (that costs about a second): set for one frame, all
        // but invisible (no strike clock, the lowest intensity), then cleared; the game keeps the last one compiled for
        // the strikes after. Only a few seconds into play, never as the game starts, and only the one that is needed:
        // loading a laser that needs another compiles that one the same way, there and then rather than as it fires.
        let want = pass_of(LASERS[self.laser]);
        if self.strike.is_none() {
            if self.warming {
                render::clear_post();
                self.warming = false;
            } else if self.compiled != Some(want) && self.ticks >= WARM_AFTER {
                self.hand_post(want);
                render::set_params(&[0.0; 16]);
                self.warming = true;
            }
        } else {
            self.warming = false;
        }
        // (the wheel a pick left up: its pass built by now, `close_picked`)
        if self.closing && !self.warming {
            self.closing = false;
            ui::close();
            self.wheel = None;
        }
    }
    /// Pass `pass` given to the game. One it doesn't hold yet is built as the frame is drawn (about a second the first
    /// time; the driver keeps it after), and should that bring the game down, as Apple's Metal compiler has on the
    /// biggest passes, the storage says which it was (`BUILDING`, until a few frames later: `warm`), so the next start
    /// doesn't load that laser again (`recover`).
    fn hand_post(&mut self, pass: usize) {
        if self.compiled != Some(pass) && storage::set(BUILDING, pass.to_string().as_bytes()).is_ok() {
            self.building = Some(0);
        }
        render::set_post(self.passes[pass]);
        self.compiled = Some(pass);
    }

    // ---- the strike ----
    fn network_start(&mut self, start: smp::Launch) {
        smp::set_observer(true);
        self.stop_strike();
        let saved=(self.laser,self.seed_lock,self.approach,self.arrival,self.colours.clone(),self.skip,self.follow,self.terrain,self.blast_alt);
        self.laser=start.laser;
        self.seed_lock=Some(start.seed);
        self.approach=start.approach;
        self.arrival=start.arrival;
        self.colours[self.laser]=start.colour;
        self.skip=start.elapsed;
        self.follow=false;
        self.terrain=false;
        if let Some(i)=wheel::sound_of(LASERS[self.laser].key) { self.blast_alt[i]=start.option != 0; }
        smp::set_remote(start);
        self.fire();
        (self.laser,self.seed_lock,self.approach,self.arrival,self.colours,self.skip,self.follow,self.terrain,self.blast_alt)=saved;
    }
    fn fire(&mut self) {
        let remote=smp::take_remote();
        if remote.is_none() { smp::set_observer(false); }
        let laser = LASERS[self.laser];
        let Some(hit) = remote.as_ref().map(|s| world::Hit { block_x:s.block[0],block_y:s.block[1],block_z:s.block[2],x:s.point[0],y:s.point[1],z:s.point[2],block:String::new() }).or_else(|| world::raycast(laser.range)) else {
            Self::actionbar("NO TARGET IN RANGE", "gray");
            return;
        };
        let player = game::get_player();
        let dimension = player.as_ref().map_or("minecraft:overworld".to_string(), |p| p.dimension.clone());
        let me = remote.as_ref().map(|s| s.origin).unwrap_or_else(|| player.as_ref().map_or([hit.x, hit.y, hit.z + 1.0], |p| [p.x, p.y, p.z]));
        let target = Target { block: [hit.block_x, hit.block_y, hit.block_z], point: [hit.x, hit.y, hit.z] };
        let clock = game::get_clock().map_or(0, |c| c.game_time);
        // a fresh look every strike, unless one is held (`/orbital seed`)
        let seed = self.seed_lock.unwrap_or((clock % u64::from(SEEDS)) as u32 + 1);
        self.last_seed = seed;
        self.fired = true;
        let seed = seed as f32;
        ground::clear();
        columns::clear();
        // (the ship lasers take their approach; the Payload and the Nuke which blast they play, 1 for the alternative)
        let option = wheel::sound_of(laser.key).map_or(self.approach, |s| usize::from(self.blast_alt[s]));
        if remote.is_none() {
            smp::emit(smp::Packet::Start(smp::Launch { laser:self.laser,block:target.block,point:target.point,origin:me,
                seed:seed as u32,approach:self.approach,arrival:self.arrival,colour:self.colours[self.laser],option,
                elapsed:self.skip,dimension:dimension.clone() }));
        }
        let plan = strike::plan(laser, &target, self.terrain && remote.is_none(), &dimension, seed, me, option);
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
        if laser.key == "payload" || laser.key == "nuke" || laser.key == "rod" || laser.key == "supercell" || laser.key == "hurricane" || laser.key == "tsunami" {
            // (where the player stood as it fired: the shockwave's dust follows the land from the target's ground to theirs)
            params[12..15].copy_from_slice(&[me[0] as f32, me[1] as f32, me[2] as f32]);
            params[15] = self.flags_of(laser.index);
        }
        self.hand_post(pass_of(laser));
        render::set_params(&params);
        log::write(log::Level::Info, &format!("strike [{}] at {} {} {}", laser.key, hit.block_x, hit.block_y, hit.block_z));
        // (started part way in: what was due before then is left out, sounds and world changes alike; but the stages and
        // the pass's tables due before then are worked out on the first ticks, as the pass needs them, what they give
        // that was due before then left out too)
        let ticks = (self.skip.min(laser.length - 1.0) * 20.0) as u32;
        let skipped = ticks as f32 * 0.05;
        let mut plan = plan;
        plan.retain(|e| e.0 >= skipped || matches!(e.1, Act::Later(_) | Act::Soon(_) | Act::Cleanup(_) | Act::Table(_) | Act::Words { .. } | Act::Data { .. } | Act::Survey { .. }));
        let next = 0;
        self.skip = 0.0;
        // (the crystal bloom's spires and pieces, worked out once for the pass: strike::cb_table)
        // (the sinkhole's slabs, rings and rim come on the tick after: strike::sh_table, as Act::Table)
        let data = if laser.key == "crystalbloom" { strike::cb_table(seed) } else { Vec::new() };
        render::set_data(&data);
        self.strike = Some(Strike { plan, next, more: Default::default(), given: 0, ticks, length: laser.length, params, waiting: Default::default(), urgent: Default::default(), data, data_sent: true, skipped, sounds: Default::default(), key: laser.key, sprites: if laser.key == "hurricane" { sdk::atlas::resources_version() } else { 0 } });
        if remote.is_none() { self.hold_forceloads(&dimension, clock, laser.length); }
        // (the Hurricane's wind carrying the player off once it reaches them, with the knockback on)
        self.carrying = (laser.key == "hurricane" && self.knock && player.is_some()).then(|| carry::Carry::new([hit.block_x as f64 + 0.5, hit.block_y as f64 + 1.0, hit.block_z as f64 + 0.5]));
        // (the Tsunami's surge carrying the player along once the water has them, with the knockback on)
        self.surging = (laser.key == "tsunami" && self.knock && player.is_some()).then(|| surge::Surge::new(strike::TsGeo::new(&target, me, seed)));
        // (the follow camera: an orbit round the bomb on the path the pass draws it on)
        self.unfollow();
        if self.follow
            && player.is_some()
            && let Some(path) = strike::bomb_path(laser.key, &target, seed, me)
        {
            self.following = Some(follow::Follow::new(path, me, self.follow_distance));
        }
    }
    /// One tick of the strike: everything due by now, in one batch.
    fn tick_strike(&mut self) {
        // (the world's answers to the ground asked for, before the stages that read them)
        ground::poll();
        columns::poll();
        trace("polled");
        let carved = self.carve(CARVE_CMDS);
        trace("carved");
        // (what a stopped strike still has to do: a stage a tick, its edits queued)
        if !meter::full()
            && let Some(job) = self.cleanup.pop_front()
        {
            let before = meter::spent();
            for (_, a) in job() {
                if let Act::Blocks(b) = a {
                    meter::spend(60 * b.runs.len() as u64);
                    self.edits.push_back((pace::cost(&b.runs), self.edit_ticks, b));
                }
            }
            meter::spend(STAGE_COST.saturating_sub(meter::spent().saturating_sub(before)));
        }
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
            if t < s.skipped && matches!(act, Act::Cmd(_) | Act::Sound { .. } | Act::Shake { .. } | Act::Shove { .. } | Act::Spare(_) | Act::Blocks(_) | Act::Read { .. }) {
                continue;
            }
            match act {
                Act::Cmd(c) => match strike::block_cost(&c) {
                    Some(cost) => self.carving.push_back((cost, c)),
                    None => cmds.push(c),
                },
                Act::Sound { event, at, volume, pitch } => {
                    world::play_sound(&event, at.map(|[x, y, z]| (x, y, z)), volume, pitch);
                    s.sounds.insert(event);
                }
                Act::Shake { strength, seconds } => jolts.push((strength, seconds)),
                Act::Shove { from, out, up, reach } => {
                    // (none while the follow camera moves them)
                    if self.knock
                        && self.following.is_none()
                        && let Some(p) = game::get_player()
                        && let Some([x, y, z]) = knockback(from, [p.x, p.y, p.z], out, up, reach)
                    {
                        world::push_player(x, y, z);
                    }
                }
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
                Act::Later(job) | Act::Cleanup(job) if worked_out || meter::full() => s.waiting.push_back(job),
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
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
        // (the game's textures loaded anew under a Hurricane: a resource pack turned on or off moves their layers)
        if s.key == "hurricane" {
            let v = sdk::atlas::resources_version();
            if v != s.sprites {
                s.sprites = v;
                strike::hu_repack(&mut s.data);
                s.data_sent = false;
            }
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
        self.unfollow();
        self.carrying = None;
        self.surging = None;
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
        if self.strike.is_some() && !smp::observer() { smp::emit(smp::Packet::Stop); }
        let Some(s) = &mut self.strike else { return };
        let mut cmds: Vec<String> = s.sounds.iter().map(|e| format!("stopsound @s * {e}")).collect();
        let more = std::mem::take(&mut s.more).into_vec().into_iter().map(|g| (g.t, g.act));
        // (what must still be done goes on after it: the edits and stages marked so, `Act::Cleanup`)
        let mut keep = Vec::new();
        let rest: Vec<String> = s
            .plan
            .drain(s.next..)
            .chain(more)
            .filter_map(|(_, a)| match a {
                Act::Cmd(c) | Act::Spare(c) => Some(c),
                Act::Cleanup(job) => {
                    self.cleanup.push_back(job);
                    None
                }
                Act::Blocks(b) if b.cleanup => {
                    keep.push(b);
                    None
                }
                _ => None,
            })
            .collect();
        self.edits.retain(|e| e.2.cleanup);
        for b in keep {
            self.edits.push_back((pace::cost(&b.runs), self.edit_ticks, b));
        }
        self.edits_late = 0;
        self.edited = false;
        let queued = self.carving.drain(..).chain(self.spare.drain(..)).map(|(_, c)| c);
        cmds.extend(rest.into_iter().chain(queued).filter(|c| c.starts_with("forceload remove")));
        world::run_commands(&cmds);
        self.end_strike();
        self.owes = false;
        storage::delete(FORCELOADS);
        log::write(log::Level::Info, "strike stopped");
    }
    /// Keep the strike's forceload removes in storage as it fires (`FORCELOADS`): each run in its dimension, with the
    /// world clock it fired at and its length, so the next play of this world can tell it is the same one.
    fn hold_forceloads(&mut self, dimension: &str, clock: u64, length: f32) {
        let Some(s) = &self.strike else { return };
        let removes: Vec<String> = s
            .plan
            .iter()
            .filter_map(|(_, a)| match a {
                Act::Cmd(c) | Act::Spare(c) if c.starts_with("forceload remove") => Some(format!("execute in {dimension} run {c}")),
                _ => None,
            })
            .collect();
        self.owes = !removes.is_empty();
        if !self.owes {
            storage::delete(FORCELOADS);
            return;
        }
        let end = clock + (length * 20.0) as u64;
        let text = format!("{clock}\n{end}\n{}\n", removes.join("\n"));
        if let Err(e) = storage::set(FORCELOADS, text.as_bytes()) {
            log::write(log::Level::Warn, &format!("the strike's forceloads not kept: {e}"));
        }
    }
    /// The player has left the world the strike is in (back to the title screen, or into another world): end it there
    /// and then, nothing of it carried into the next world. Its sounds are cut (the game stops every sound as a world
    /// closes; `stopsound` too, in case), its plan and every world change still waiting are dropped (what must be done
    /// whatever happens, `Act::Cleanup`, too: that world is gone), the wheel is closed and the pass cleared. The chunks it
    /// forceloaded are let go the next time that world is played (`release_held`).
    fn left_world(&mut self) {
        let sounds: Vec<String> = self.strike.as_ref().map_or(Vec::new(), |s| s.sounds.iter().map(|e| format!("stopsound @s * {e}")).collect());
        let live = self.strike.is_some() || !self.edits.is_empty() || !self.carving.is_empty() || !self.spare.is_empty() || !self.cleanup.is_empty();
        if self.strike.is_some() {
            log::write(log::Level::Info, "left the world mid-strike: strike ended");
        }
        self.end_strike();
        self.edits.clear();
        self.carving.clear();
        self.spare.clear();
        self.cleanup.clear();
        self.edits_late = 0;
        self.edited = false;
        self.aiming = None;
        if self.wheel.take().is_some() {
            ui::close();
        }
        if live && !sounds.is_empty() {
            world::run_commands(&sounds);
        }
        self.owes = false;
        self.settled = Some(0);
    }
    /// Once the strike and the world changes it left waiting are done (its forceload removes among them), the kept
    /// removes are dropped.
    fn paid(&mut self) {
        if self.owes && self.strike.is_none() && self.spare.is_empty() && self.carving.is_empty() {
            self.owes = false;
            storage::delete(FORCELOADS);
        }
    }
    /// Whether this tick is in a world, and the same one as the last. The API has no hook for leaving a world, so: a
    /// tick with no player (and so no world clock) is the game between worlds, and a world clock somewhere else than it
    /// was is another world (a pause, or this world saved and opened again, keeps it where it was). Either way a strike
    /// under way ends there (`left_world`).
    fn in_world(&mut self) -> bool {
        let player = game::get_player();
        let clock = player.as_ref().and(game::get_clock()).map(|c| c.game_time);
        let place = player.map(|p| [p.x, p.y, p.z]);
        let jumped = matches!((self.clock, clock), (Some(was), Some(now)) if now + SAME_PLAY < was || now > was + SAME_PLAY);
        // (a stall jumps the clock too, either way: the game's frames stop while the world runs on, and it catches up.
        // Nothing but a stalled frame has passed since the last tick and the player is where they were, so it is this
        // world. Between worlds the frames run on with no ticks, and the fork has no tick with no player to say so.)
        let moved = matches!((self.place, place), (Some(a), Some(b)) if (a[0] - b[0]).hypot(a[2] - b[2]).hypot(a[1] - b[1]) > AWAY_ROOM);
        let elsewhere = jumped && (self.away > AWAY || moved);
        if jumped && self.strike.is_some() {
            let said = if elsewhere { "another world" } else { "a stall: the strike goes on" };
            log::write(log::Level::Info, &format!("the world's clock went from {:?} to {clock:?} ({:.2} s of frames, moved: {moved}): {said}", self.clock, self.away));
        }
        self.place = place;
        self.away = 0.0;
        if clock.is_none() || elsewhere {
            self.left_world();
        }
        // (joined: this world's first tick, or another's after a tick out of one)
        if clock.is_some() && (self.clock.is_none() || elsewhere) {
            self.hint = Some(0);
        }
        self.clock = clock;
        clock.is_some()
    }
    /// A frame's part in telling time away from a stall (`in_world`).
    fn count_frame(&mut self, seconds: f32) {
        self.away += seconds.min(AWAY_FRAME);
    }
    /// The first line on joining a world (`HINT`), a second in, until the player knows how to get the Designator: they
    /// ran `/orbital give` or hold one (`KNOWS`).
    fn join_hint(&mut self) {
        if holding_designator() {
            self.learned();
        }
        let Some(n) = self.hint else { return };
        if n < HINT_AFTER {
            self.hint = Some(n + 1);
            return;
        }
        self.hint = None;
        if !self.knows() {
            chat::show(HINT);
        }
    }
    /// Whether the player knows how to get the Designator (`KNOWS`).
    fn knows(&mut self) -> bool {
        *self.knows.get_or_insert_with(|| storage::get(KNOWS).is_some())
    }
    /// The player knows how to get the Designator: the join hint stops (`KNOWS`).
    fn learned(&mut self) {
        if !self.knows() {
            self.knows = Some(true);
            if let Err(e) = storage::set(KNOWS, b"1") {
                log::write(log::Level::Warn, &format!("could not keep that the hint was learned: {e}"));
            }
        }
    }
    /// A strike broken off by the game closing or the player leaving left its forceload removes in storage
    /// (`hold_forceloads`): once settled in a world, run them if this is that world, played on from where it was left
    /// (its clock within the strike's span, a little either side); another world's leaves them for when it comes back.
    fn release_held(&mut self) {
        let Some(n) = self.settled else { return };
        if n < 40 {
            self.settled = Some(n + 1);
            return;
        }
        self.settled = None;
        if self.owes || self.strike.is_some() {
            return;
        }
        let Some(text) = storage::get(FORCELOADS).map(|b| String::from_utf8_lossy(&b).into_owned()) else { return };
        let mut lines = text.lines();
        let (Some(from), Some(to)) = (lines.next().and_then(|l| l.parse::<u64>().ok()), lines.next().and_then(|l| l.parse::<u64>().ok())) else {
            storage::delete(FORCELOADS);
            return;
        };
        let Some(now) = self.clock else { return };
        if now + SAME_PLAY < from || now > to + SAME_PLAY {
            return;
        }
        let cmds: Vec<String> = lines.filter(|l| l.starts_with("execute in ") && l.contains(" run forceload remove ")).map(str::to_string).collect();
        log::write(log::Level::Info, &format!("let go of the {} forceloads a strike broken off left", cmds.len()));
        world::run_commands(&cmds);
        storage::delete(FORCELOADS);
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
            // (what is laid down never where the player is)
            match game::get_player().filter(|_| b.clear_of_player) {
                Some(p) => world::edit_blocks(&b.edit_clear_of([p.x, p.y, p.z])),
                None => world::edit_blocks(&b.edit()),
            }
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
        let held = input::held().is_some_and(|h| h.id == DESIGNATOR);
        let holding = self.hud && held;
        let lines: Vec<(String, u32)> = if holding {
            let l = LASERS[self.laser];
            let mut lines = vec![
                ("Orbital Laser".to_string(), 0xFFFFFF),
                (format!("Laser: {}", l.title), l.rgb),
                (format!("Terrain damage: {}", if self.terrain { "on" } else { "off" }), 0xA8B0BC),
            ];
            if is_ship(l) {
                lines.push((format!("Approach: {}", APPROACHES[self.approach].label), 0xA8B0BC));
                lines.push((format!("Arrival: it {}", ARRIVALS[self.arrival].label), 0xA8B0BC));
                lines.push((format!("Colour: {}", COLOURS[self.colours[self.laser]].label), COLOUR_RGB[self.colours[self.laser]]));
            }
            if l.key == "payload" || l.key == "nuke" || l.key == "rod" || l.key == "supercell" || l.key == "hurricane" {
                lines.push((format!("Quality: {}", if self.fast { "fast (smoke at half size)" } else { "full" }), 0xA8B0BC));
            }
            if l.key == "nuke" || l.key == "rod" || l.key == "hurricane" || l.key == "tsunami" {
                lines.push((format!("Knockback: {}", if self.knock { "on" } else { "off" }), 0xA8B0BC));
            }
            if (l.key == "nuke" || l.key == "payload") && self.follow {
                lines.push(("Follow camera: on".to_string(), 0x6FC8FF));
            }
            if (self.fly - 1.0).abs() > 1e-4 {
                lines.push((format!("Flying speed: {}", wheel::speed_label(self.fly)), 0x6FC8FF));
            }
            if self.strike.is_some() {
                lines.push(("Strike in progress".to_string(), 0xFF8A65));
            } else {
                lines.push(("R: laser wheel".to_string(), 0x7C8594));
            }
            lines
        } else {
            Vec::new()
        };
        let left = false;
        if lines != self.panel || left != self.panel_left {
            if lines.is_empty() {
                hud::clear();
            } else {
                let panel: Vec<Line> = lines.iter().map(|(t, c)| Line { text: t.clone(), color: *c }).collect();
                hud::set_panel(if left { Corner::TopLeft } else { Corner::TopRight }, &panel);
            }
            self.panel = lines;
            self.panel_left = left;
        }
    }
}

impl Mod for Orbital {
    fn init() -> Result<(Self, Registration), String> {
        input::claim_items(&[DESIGNATOR.to_string()]);
        input::register_key("wheel", "Open the laser wheel", "key.keyboard.r");
        let mut settings = Orbital::load();
        let broke = Orbital::recover(&mut settings);
        let mut state = Orbital::new(settings);
        if broke.is_some() {
            state.broke = broke;
            state.save();
        }
        // the game keeps the flying speed from here on, in every world
        state.apply_fly();
        Ok((state, Registration::new().command("orbital").on_tick().on_frame()))
    }

    fn tick(&mut self, _tick: u64) {
        meter::reset();
        self.ticks += 1;
        if !self.in_world() {
            return;
        }
        self.join_hint();
        // (once the player is in the world and settled: a batch sent before the server has placed them is dropped)
        if self.ticks >= 100
            && game::get_player().is_some()
            && let Some(i) = self.broke.take()
        {
            let text = format!(
                "Orbital Laser: the game closed last time while it was building the {0}'s effects, so the Plasma laser is loaded instead. Pick the {0} on the wheel to try it again.",
                LASERS[i].title
            );
            world::run_commands(&[format!(r#"tellraw @s {{"text":"{text}","color":"yellow"}}"#)]);
        }
        for event in input::poll() {
            match event {
                Event::UseStart(u) if u.item.id == DESIGNATOR => {
                    if self.strike.is_some() {
                        // one strike at a time: a dull click
                        Self::refuse();
                    } else {
                        self.aiming = Some(0);
                    }
                }
                Event::UseStop(u) if u.item.id == DESIGNATOR => self.aiming = None,
                // (the wheel's key only with the designator in hand: with anything else it is left to the game)
                Event::KeyDown(k) if k == "wheel" && input::held().is_some_and(|h| h.id == DESIGNATOR) => self.open_wheel(),
                Event::ScreenClick(c) if c.button == 0 => self.wheel_click(c.x, c.y),
                Event::ScreenClick(c) if c.button == 1 => self.turn_page(self.page + 1),
                Event::ScreenClosed => {
                    self.wheel = None;
                    self.closing = false;
                }
                _ => {}
            }
        }
        for t in input::poll_typed() {
            self.typed(t);
        }
        if let Some(n) = self.aiming {
            if n >= LOCK_TICKS {
                self.aiming = None;
                self.fire();
            } else {
                // the designator's countdown over the hotbar while it is held: what it is doing, a dot more every
                // fifth of a second, and the laser loaded
                if n % 4 == 0 {
                    let l = LASERS[self.laser];
                    // (the sinkhole comes from nothing overhead: it reads the ground under the crosshair instead)
                    let what = match l.key {
                        "sinkhole" => "SEISMIC SCAN",
                        "payload" | "nuke" | "rod" => "DESIGNATING",
                        "hurricane" => "TRACKING STORM",
                        "tsunami" => "READING THE SEA",
                        _ => "ACQUIRING TARGET",
                    };
                    Self::actionbar(&format!("{what} {}  [{}]", ".".repeat(1 + n as usize / 4), l.title), &format!("#{:06X}", l.rgb & 0xFF_FFFF));
                }
                self.aiming = Some(n + 1);
            }
        }
        self.tick_strike();
        self.follow_tick();
        self.carry_tick();
        self.surge_tick();
        self.update_panel();
        self.paid();
        self.release_held();
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
        self.count_frame(seconds);
        self.pace.frame(seconds);
        self.warm();
        if let Some(s) = &mut self.strike {
            // (whole ticks: the pass adds the frame's partial tick, the camera's own, `now` in strike.wgsl)
            s.params[3] = s.ticks as f32 * 0.05;
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
                self.learned();
                world::run_commands(&[format!("give @s {DESIGNATOR}")]);
                Ok(Some("Orbital Laser Designator added to your inventory (R with it in hand: the laser wheel)".into()))
            }
            (Some("wheel"), _) => {
                self.open_wheel();
                Ok(None)
            }
            // (for a host that knows when the player leaves the world: the native build's glue, on the client level
            // unloading; the fork has no such hook, and the mod finds out on the next tick in a world, `in_world`)
            (Some("left-world"), _) => {
                self.left_world();
                self.clock = None;
                self.place = None;
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
                Ok(Some("Strike stopped".into()))
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
            (Some("impactframes"), Some(v @ ("on" | "off"))) => {
                self.set_impact(v == "on");
                Ok(Some(format!("Impact frames {v} (the Rod from God's stark flash frames as it strikes)")))
            }
            (Some("impactframes"), Some(v)) if IMPACT_STYLES.contains(&v) => {
                self.impact_style = IMPACT_STYLES.iter().position(|&s| s == v).unwrap_or(1) as u8;
                self.set_impact(true);
                Ok(Some(format!("Impact frames: {v}")))
            }
            (Some("seed"), Some("random")) => {
                self.seed_lock = None;
                self.save();
                Ok(Some("Seed: random (a fresh look every strike)".to_string()))
            }
            (Some("seed"), Some("lock")) => {
                self.seed_lock = Some(self.last_seed);
                self.save();
                Ok(Some(format!("Seed: held at {} (the last strike's look, every strike; /orbital seed random to free it)", self.last_seed)))
            }
            (Some("seed"), Some(v)) => match v.parse::<u32>() {
                Ok(n) if (1..=SEEDS).contains(&n) => {
                    self.seed_lock = Some(n);
                    self.save();
                    Ok(Some(format!("Seed: held at {n} (the same look every strike; /orbital seed random to free it)")))
                }
                _ => Err(format!("/orbital seed 1-{SEEDS} | lock | random")),
            },
            (Some("seed"), None) => Ok(Some(match self.seed_lock {
                Some(n) => format!("Seed: held at {n} (/orbital seed random | lock | N)"),
                None => format!("Seed: random, the last strike's was {} (/orbital seed lock to keep it)", self.last_seed),
            })),
            (Some("knockback"), Some(v @ ("on" | "off"))) => {
                self.knock = v == "on";
                self.save();
                Ok(Some(format!("Knockback {v} (the Nuke's and the Rod's push on you)")))
            }
            (Some("knockback"), None) => Ok(Some(format!("Knockback: {} (/orbital knockback on or off)", if self.knock { "on" } else { "off" }))),
            (Some("carryview"), Some(v @ ("turn" | "still"))) => {
                self.carry_turn = v == "turn";
                self.save();
                Ok(Some(format!("Carry view: {v} (the Hurricane's carry {} your view)", if self.carry_turn { "turns and sways" } else { "leaves alone" })))
            }
            (Some("carryview"), None) => Ok(Some(format!("Carry view: {} (/orbital carryview turn or still)", if self.carry_turn { "turn" } else { "still" }))),
            (Some("follow"), Some(v @ ("on" | "off"))) => {
                self.set_follow(v == "on");
                Ok(Some(format!("Follow camera {v} (an orbit round the Nuke's or the Payload's bomb as it comes in, the mouse turning it; then the fireball and the cloud)")))
            }
            (Some("follow"), Some("distance")) => match words.next().map(str::parse::<f64>) {
                Some(Ok(d)) if d.is_finite() => {
                    self.follow_distance = d.clamp(follow::DISTANCE_MIN, follow::DISTANCE_MAX);
                    self.save();
                    Ok(Some(format!("Follow camera orbits {} blocks from the bomb", self.follow_distance)))
                }
                None => Ok(Some(format!("Follow camera distance: {} blocks (/orbital follow distance N, {} to {})", self.follow_distance, follow::DISTANCE_MIN, follow::DISTANCE_MAX))),
                _ => Err(format!("/orbital follow distance N ({} to {} blocks)", follow::DISTANCE_MIN, follow::DISTANCE_MAX)),
            },
            (Some("follow"), None) => Ok(Some(format!("Follow camera: {}, {} blocks out (/orbital follow on|off, /orbital follow distance N)", if self.follow { "on" } else { "off" }, self.follow_distance))),
            (Some("impactframes"), None) => Ok(Some(format!("Impact frames: {} (/orbital impactframes kanada, blackflash, cinematic or off)", if self.impact { IMPACT_STYLES[usize::from(self.impact_style.min(2))] } else { "off" }))),
            (Some("shadow"), Some(v @ ("on" | "off"))) => {
                self.shadow_off = v == "off";
                let flags = |o: &Self, i: f32| o.flags_of(i as u32);
                if let Some(i) = self.strike.as_ref().map(|s| s.params[7]) {
                    let f = flags(self, i);
                    if let Some(s) = &mut self.strike {
                        s.params[15] = f;
                    }
                }
                Ok(Some(format!("Cloud shadows {v}")))
            }
            (Some(c), v) if wheel::SOUND_LASERS.iter().any(|s| s.1 == c) => {
                let s = wheel::SOUND_LASERS.iter().position(|s| s.1 == c).unwrap_or(0);
                let name = wheel::SOUND_LASERS[s].2;
                let said = |alt: bool| if alt { "alternative" } else { "main" };
                match v {
                    Some(v @ ("main" | "alt")) => {
                        self.blast_alt[s] = v == "alt";
                        self.save();
                        Ok(Some(format!("{name} blast: {}", said(self.blast_alt[s]))))
                    }
                    None => Ok(Some(format!("{name} blast: {} (/orbital {c} main or alt)", said(self.blast_alt[s])))),
                    Some(_) => Err(format!("/orbital {c} main or alt")),
                }
            }
            (Some("quality"), Some(v @ ("full" | "fast"))) => {
                self.set_quality(v == "fast");
                Ok(Some(format!("Quality {}", if self.fast { "fast: the Payload's, the Nuke's and the Rod's smoke at half size" } else { "full: every pixel" })))
            }
            (Some("quality"), None) => Ok(Some(format!(
                "Quality: {} (/orbital quality full or fast)",
                if self.fast { "fast" } else { "full" }
            ))),
            (Some(key), None) if LASERS.iter().any(|l| l.key == key) => {
                self.laser = LASERS.iter().position(|l| l.key == key).unwrap_or(0);
                self.save();
                Ok(Some(format!("{} loaded", LASERS[self.laser].title)))
            }
            _ => Err(format!(
                "/orbital give | wheel | terrain on|off | hud on|off | quality full|fast | impactframes kanada|blackflash|cinematic|off | knockback on|off | carryview turn|still | follow on|off|distance N | seed N|lock|random | payloadsound|nukesound main|alt | flyspeed N|reset | stop | skip SECONDS | approach {} | arrival {} | colour {} | {}",
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
            (super::rod_pass(false), &["fn mh(", "fn gnoise3(", "fn rod(", "fn ign("][..]),
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
            let r = super::rod_pass(fast);
            assert_eq!(r.matches("@fragment").count(), if fast { 3 } else { 1 });
            assert!(r.len() <= 256 << 10 && r.contains("fn rod(") && !r.contains("fn nuke("));
            let h = super::hurricane_pass(fast);
            assert_eq!(h.matches("@fragment").count(), if fast { 3 } else { 1 });
            assert!(h.len() <= 256 << 10 && h.contains("fn hurricane(") && h.contains("fn hu_debris(") && !h.contains("fn rod("));
            assert_eq!(h.contains("half_picture"), fast);
            // (the Tsunami's has no half-size stage: both qualities are the same pass)
            let t = super::tsunami_pass(fast);
            assert_eq!(t.matches("@fragment").count(), 1);
            assert!(t.len() <= 256 << 10 && t.contains("fn tsunami(") && t.contains("fn ts_under(") && !t.contains("fn hurricane("));
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

#[cfg(test)]
mod shove_tests {
    use super::knockback;

    #[test]
    fn the_knockback_throws_the_player_back_and_up_fading_with_distance() {
        let from = [0.0, 76.0, 0.0];
        let mut last = f32::MAX;
        for d in [0.0, 50.0, 200.0, 300.0, 400.0, 500.0, 540.0] {
            let [x, y, z] = knockback(from, [d * 0.6, 64.0, d * 0.8], 0.8, 0.55, 600.0).unwrap();
            let h = x.hypot(z);
            assert!(h <= last + 1e-6 && h <= 0.95 && y > 0.18 && y <= 0.6, "{d}: {x} {y} {z}");
            if d > 0.0 {
                assert!(x > 0.0 && z > 0.0 && (x / z - 0.75).abs() < 1e-4);
            }
            last = h;
        }
        assert!((knockback(from, [120.0, 64.0, 160.0], 0.8, 0.55, 600.0).unwrap()[1] - 0.55).abs() < 1e-6);
        assert!(knockback(from, [600.0, 64.0, 0.0], 0.8, 0.55, 600.0).is_none());
    }
    #[test]
    fn the_nuke_shoves_once_as_its_front_arrives() {
        use crate::strike::{Act, Target};
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let nuke = crate::lasers::LASERS.iter().find(|l| l.key == "nuke").unwrap();
        let mut ev = crate::strike::plan(nuke, &target, false, "minecraft:overworld", 7.0, [10.5, 66.0, 297.0], 0);
        let (mut shoves, mut jolt) = (Vec::new(), f32::MAX);
        while let Some((t, act)) = ev.pop() {
            match act {
                Act::Shove { out, reach, .. } => shoves.push((t, out, reach)),
                Act::Shake { strength, .. } if strength > 0.9 => jolt = jolt.min(t),
                Act::Later(job) | Act::Soon(job) => ev.extend(job()),
                _ => {}
            }
        }
        assert_eq!(shoves.len(), 1);
        assert!((shoves[0].0 - jolt).abs() < 0.01, "{shoves:?} {jolt}");
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
    /// Which of the world's chunks are loaded: those round the player, and those forceloaded once they have been
    /// generated (a while after: far off, in the far terrain's LOD, the land under a target is not loaded until then).
    struct Loaded {
        me: (i32, i32),
        view: i32,
        forced: std::collections::HashMap<(i32, i32), u64>,
        /// How slowly the forceloaded chunks come (times the usual; 0: not while the strike lasts).
        slow: u64,
        now: u64,
    }
    impl Loaded {
        fn has(&self, x: i32, z: i32) -> bool {
            let (cx, cz) = (x >> 4, z >> 4);
            (cx - (self.me.0 >> 4)).abs() <= self.view && (cz - (self.me.1 >> 4)).abs() <= self.view || self.forced.get(&(cx, cz)).is_some_and(|&t| t <= self.now)
        }
        fn command(&mut self, c: &str) {
            let w: Vec<&str> = c.split_whitespace().collect();
            let n: Vec<i32> = w.iter().skip(2).filter_map(|v| v.parse().ok()).collect();
            if n.len() < 2 {
                return;
            }
            let (x1, z1) = if n.len() >= 4 { (n[2], n[3]) } else { (n[0], n[1]) };
            for cx in (n[0].min(x1) >> 4)..=(n[0].max(x1) >> 4) {
                for cz in (n[1].min(z1) >> 4)..=(n[1].max(z1) >> 4) {
                    if w[1] == "add" {
                        let h = (cx.wrapping_mul(73_856_093) ^ cz.wrapping_mul(19_349_663)).unsigned_abs() as u64 % 140;
                        let at = if self.slow == 0 { u64::MAX } else { self.now + (10 + h) * self.slow };
                        self.forced.entry((cx, cz)).or_insert(at);
                    } else {
                        self.forced.remove(&(cx, cz));
                    }
                }
            }
        }
    }
    fn answer(tag: u32, cols: &[(i32, i32)], below: u32, above: u32, cratered: bool, loaded: &Loaded) -> ColumnBlocks {
        let mut palette: Vec<String> = Vec::new();
        let (mut bases, mut blocks) = (Vec::new(), Vec::new());
        for &(x, z) in cols {
            if !loaded.has(x, z) {
                bases.push(None);
                blocks.extend(std::iter::repeat_n(0u16, (below + above) as usize));
                continue;
            }
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
        loaded: Loaded,
        /// The spot the strikes are round (moved far off for a fresh one).
        home: (i32, i32),
        /// The most a tick took past what its counted work explains (release builds: work the meter does not count
        /// shows here), and where.
        slowest: (std::time::Duration, String),
    }
    impl Soak {
        fn new(seed: u64) -> Self {
            fake::with(|w| *w = fake::Fake::default());
            let mut o = Orbital::new(Orbital::parse(""));
            o.terrain = true;
            let loaded = Loaded { me: (1000, -1850), view: 12, forced: Default::default(), slow: 1, now: 0 };
            Soak { o, rng: Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1), tick: 0, answers: Answers::Next, cratered: false, reads: Vec::new(), surveys: Vec::new(), frame: 0.016, worst: (0, String::new()), loaded, home: (1000, -2000), slowest: Default::default() }
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
            self.loaded.now = now;
            for c in fake::with(|w| std::mem::take(&mut w.forceloads)) {
                self.loaded.command(&c);
            }
            let cratered = self.cratered;
            let (ready, wait): (Vec<_>, Vec<_>) = std::mem::take(&mut self.reads).into_iter().partition(|r| r.0 <= now);
            self.reads = wait;
            let (sready, swait): (Vec<_>, Vec<_>) = std::mem::take(&mut self.surveys).into_iter().partition(|r| r.0 <= now);
            self.surveys = swait;
            fake::with(|w| {
                for (_, tag, cols, below, above) in ready {
                    w.columns.push(answer(tag, &cols, below, above, cratered, &self.loaded));
                }
                // (the game keeps 16 answers for a mod between its polls, the latest)
                let n = w.columns.len();
                w.columns.drain(..n.saturating_sub(16));
                for (_, tag, cols) in sready {
                    let heights = cols.iter().map(|&(x, z)| self.loaded.has(x, z).then(|| ground(x, z, cratered) + 1)).collect();
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
            let began = thread_time();
            self.o.tick_strike();
            let took = thread_time().saturating_sub(began);
            let spent = meter::spent();
            // (how much longer it took than the work the meter counted would: a natively built instruction is well
            // under half a nanosecond)
            let over = took.saturating_sub(std::time::Duration::from_nanos(spent / 2));
            if over > self.slowest.0 {
                let t = self.o.strike.as_ref().map_or(-1.0, |s| s.ticks as f32 * 0.05);
                self.slowest = (over, format!("{what} at {t:.2} s, {:.1} ms for {:.2}M counted", took.as_secs_f64() * 1e3, spent as f64 / 1e6));
            }
            if spent > self.worst.0 {
                let t = self.o.strike.as_ref().map_or(-1.0, |s| s.ticks as f32 * 0.05);
                self.worst = (spent, format!("{what} at {t:.2} s ({} edits, {} commands waiting)", self.o.edits.len(), self.o.carving.len() + self.o.spare.len()));
            }
        }
        fn fire(&mut self, laser: usize, at: (i32, i32)) {
            let g = ground(at.0, at.1, self.cratered);
            fake::with(|w| {
                w.hit = Some(Hit { block_x: at.0, block_y: g, block_z: at.1, x: f64::from(at.0) + 0.5, y: f64::from(g + 1), z: f64::from(at.1) + 0.5, block: "minecraft:grass_block".into() });
                w.player = Some(Player { x: f64::from(self.loaded.me.0) + 0.5, y: f64::from(g) + 40.0, z: f64::from(self.loaded.me.1) + 0.5, yaw: 180.0, pitch: 15.0, health: 20.0, food: 20, dimension: "minecraft:overworld".into() });
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
            // (but what must still be done, the Supercell's fires put out: `Act::Cleanup`)
            assert!(self.o.strike.is_none() && self.o.edits.iter().all(|e| e.2.cleanup) && self.o.carving.is_empty() && self.o.spare.is_empty());
            assert!(!self.o.edited);
        }
    }

    /// The CPU time this thread has used: what a tick's own work took, whatever else the machine is busy with. A tick
    /// timed by the clock on the wall is failed by a game, a build or the other tests taking its core away.
    #[cfg(target_os = "linux")]
    fn thread_time() -> std::time::Duration {
        #[repr(C)]
        struct Timespec {
            sec: i64,
            nsec: i64,
        }
        unsafe extern "C" {
            fn clock_gettime(clock: i32, t: *mut Timespec) -> i32;
        }
        const CLOCK_THREAD_CPUTIME_ID: i32 = 3;
        let mut t = Timespec { sec: 0, nsec: 0 };
        // SAFETY: `t` is a timespec of the 64-bit layout, alive for the call, and the call only writes it.
        assert_eq!(unsafe { clock_gettime(CLOCK_THREAD_CPUTIME_ID, &mut t) }, 0);
        std::time::Duration::new(t.sec as u64, t.nsec as u32)
    }
    /// (elsewhere the clock on the wall, from the first call: such a run wants the test alone, or `ORBITAL_NO_TIMING`)
    #[cfg(not(target_os = "linux"))]
    fn thread_time() -> std::time::Duration {
        static START: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
        START.get_or_init(std::time::Instant::now).elapsed()
    }

    /// `bound`: the most CPU time a tick may take past what its counted work explains (release builds only).
    fn soak(sequences: u64, seed: u64, bound: f64) -> (u64, String) {
        let (worst, at, slow, slow_at) = soak_timed(sequences, seed);
        eprintln!("most uncounted in a tick: {:.2} ms ({slow_at})", slow.as_secs_f64() * 1e3);
        // (in a release build, where a tick's time says something of its work: work the meter does not count, as a
        // scan over every column not yet loaded asked for each job, shows here even though the meter cannot see it)
        if !cfg!(debug_assertions) && std::env::var_os("ORBITAL_NO_TIMING").is_none() {
            assert!(slow.as_secs_f64() < bound, "a tick took {:.2} ms more than its counted work: {slow_at}", slow.as_secs_f64() * 1e3);
        }
        (worst, at)
    }
    fn soak_timed(sequences: u64, seed: u64) -> (u64, String, std::time::Duration, String) {
        let mut s = Soak::new(seed);
        let lasers: Vec<usize> = ["nuke", "nuke", "nuke", "rod", "rod", "payload", "planetkiller", "crystalbloom", "sinkhole", "downfall", "blackhole", "supercell", "hurricane", "tsunami"]
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
            // at and round the same spot, or (a third of the time) at a fresh one far off, never loaded: its land in the
            // far terrain's LOD, only the player's surroundings loaded and the target's chunks coming as they are
            // forceloaded, slowly or not at all; the player by it, some hundreds of blocks off, or near the
            // designator's reach
            if s.rng.below(3) == 0 {
                s.home = (s.home.0 + 3000 + s.rng.below(5000) as i32, s.home.1 - 2000 + s.rng.below(4000) as i32);
                s.loaded.view = [6, 8, 12][s.rng.below(3) as usize];
            }
            s.loaded.slow = [1, 1, 4, 20, 0][s.rng.below(5) as usize];
            let off = if s.rng.below(4) == 0 { 120 } else { 16 };
            let at = (s.home.0 + s.rng.below(2 * off + 1) as i32 - off as i32, s.home.1 + s.rng.below(2 * off + 1) as i32 - off as i32);
            let d = [150, 400 + s.rng.below(200) as i32, 500 + s.rng.below(500) as i32][s.rng.below(3) as usize];
            let a = s.rng.below(360) as f64 * std::f64::consts::PI / 180.0;
            s.loaded.me = (at.0 + (a.cos() * f64::from(d)) as i32, at.1 + (a.sin() * f64::from(d)) as i32);
            s.fire(laser, at);
            // stopped at once, soon, in the land read's first seconds, round the burst, late or never; fired again at
            // once or a little later
            let ticks = match s.rng.below(8) {
                0 => 1 + s.rng.below(5),
                1 => 5 + s.rng.below(60),
                2 => 60 + s.rng.below(300),
                3 => 300 + s.rng.below(500),
                4 => 20 + s.rng.below(40),
                5 => 210 + s.rng.below(100),
                _ => (LASERS[laser].length * 20.0) as u64 + 40,
            };
            let what = format!("#{n} {} {:?} from {d} off, chunks x{}", LASERS[laser].key, s.answers, s.loaded.slow);
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
        (s.worst.0, s.worst.1, s.slowest.0, s.slowest.1)
    }

    /// A Nuke called in on land far off, in the far terrain's LOD (none of it loaded as it fires, the player 800 blocks
    /// away): its land's work waits for the chunks it forceloads, a few steps a tick, and its terrain goes in once they
    /// have loaded, late; if they never do, it is left out (and said so) and nothing stalls.
    #[test]
    fn a_nuke_on_far_unloaded_land_waits_for_it_cheaply() {
        let nuke = LASERS.iter().position(|l| l.key == "nuke").expect("the nuke");
        for slow in [4, 20, 0] {
            let mut s = Soak::new(3);
            s.loaded = Loaded { me: (1800, -2000), view: 8, forced: Default::default(), slow, now: 0 };
            s.fire(nuke, (1000, -2000));
            let mut ticks = 0;
            while s.o.strike.is_some() {
                s.step("far");
                ticks += 1;
                assert!(ticks < 2200, "it never ended");
            }
            let (edits, logs) = fake::with(|w| (w.edits, w.logs.clone()));
            let left = logs.iter().any(|l| l.contains("never loaded"));
            eprintln!("chunks x{slow}: worst tick {:.2}M ({}), {edits} edits, {}", s.worst.0 as f64 / 1e6, s.worst.1, if left { "land left out" } else { "all of it in" });
            assert!(s.worst.0 <= CAP, "a tick of {:.2}M: {}", s.worst.0 as f64 / 1e6, s.worst.1);
            if slow == 0 {
                assert!(left, "the land never loaded and nothing said so");
            } else {
                // (the crater dug once the land came: thousands of edits; all of it when it came within the time, the
                // slowest some of it given up on and said so)
                assert!(edits > 1000, "the crater never went in ({edits} edits)");
                assert!(slow > 4 || !left, "the land came but was left out");
            }
        }
    }

    /// The Rod from God called in on land far off, as the Nuke is (`a_nuke_on_far_unloaded_land_waits_for_it_cheaply`):
    /// its land waits for the chunks, cheaply, and what never loads is left out and said so.
    #[test]
    fn a_rod_on_far_unloaded_land_waits_for_it_cheaply() {
        let rod = LASERS.iter().position(|l| l.key == "rod").expect("the rod");
        for slow in [4, 20, 0] {
            let mut s = Soak::new(3);
            s.loaded = Loaded { me: (1800, -2000), view: 8, forced: Default::default(), slow, now: 0 };
            s.fire(rod, (1000, -2000));
            let mut ticks = 0;
            while s.o.strike.is_some() {
                s.step("far");
                ticks += 1;
                assert!(ticks < 2200, "it never ended");
            }
            let (edits, logs) = fake::with(|w| (w.edits, w.logs.clone()));
            let left = logs.iter().any(|l| l.contains("never loaded"));
            eprintln!("chunks x{slow}: worst tick {:.2}M ({}), {edits} edits, {}", s.worst.0 as f64 / 1e6, s.worst.1, if left { "land left out" } else { "all of it in" });
            assert!(s.worst.0 <= CAP, "a tick of {:.2}M: {}", s.worst.0 as f64 / 1e6, s.worst.1);
            if slow == 0 {
                assert!(left, "the land never loaded and nothing said so");
            } else {
                // (the crater dug once the land came: thousands of edits; all of it when it came within the time, the
                // slowest some of it given up on and said so)
                assert!(edits > 1000, "the crater never went in ({edits} edits)");
                assert!(slow > 4 || !left, "the land came but was left out");
            }
        }
    }

    /// The follow camera: a Nuke fired with it on moves the player by kicks to their velocity once the bomb comes
    /// near (never a teleport, never a turn of their view, never their game mode), and puts them back where they stood
    /// once it is over (their view kept); the knockback left out meanwhile. Off, nothing of it.
    /// Nothing goes over the hotbar but the designator's NO TARGET IN RANGE: no strike plans a message, an old
    /// settings file's `messages` line is let be (the rest of it kept), and NO TARGET IN RANGE shows whatever it said.
    #[test]
    fn only_no_target_goes_over_the_hotbar() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        for l in LASERS {
            for approach in 0..2 {
                let plan = strike::plan(l, &target, false, "minecraft:overworld", 7.0, [10.5, 66.0, 97.0], approach);
                assert!(!plan.iter().any(|(_, a)| matches!(a, Act::Cmd(c) if c.starts_with("title "))), "{}", l.key);
            }
        }
        let old = Orbital::parse("terrain=0\nmessages=0\nhud=0\nquality=full\n");
        assert!(!old.terrain && !old.hud && !old.fast);
        let mut o = Orbital::new(old);
        fake::with(|w| {
            *w = fake::Fake::default();
            w.keep_commands = true;
        });
        o.fire();
        let ran = fake::with(|w| std::mem::take(&mut w.ran));
        assert_eq!(ran, vec![r#"title @s actionbar {"text":"NO TARGET IN RANGE","color":"gray","bold":true}"#.to_string()]);
        assert!(o.strike.is_none());
    }
    /// The join hint is the first line in each world joined, once a join, until the player runs `/orbital give` (or
    /// holds a Designator): then never again, the game restarted or not (`KNOWS` in storage).
    #[test]
    fn the_join_hint_shows_each_join_until_the_player_knows() {
        let mut o = Orbital::new(Orbital::parse(""));
        let player = Player { x: 0.5, y: 100.0, z: 0.5, yaw: 0.0, pitch: 0.0, health: 20.0, food: 20, dimension: "minecraft:overworld".into() };
        fake::with(|w| {
            *w = fake::Fake::default();
            w.keep_commands = true;
        });
        let hints = |o: &mut Orbital, clock: Option<u64>, ticks: u32| {
            for t in 0..ticks {
                fake::with(|w| {
                    w.player = clock.map(|_| player.clone());
                    w.clock = clock.map_or(0, |c| c + u64::from(t));
                });
                o.ticks += 1;
                if o.in_world() {
                    o.join_hint();
                }
            }
            fake::with(|w| std::mem::take(&mut w.ran)).iter().filter(|c| c.contains(HINT)).count()
        };
        assert_eq!(hints(&mut o, Some(1000), 10), 0, "not at once");
        assert_eq!(hints(&mut o, Some(1010), 50), 1, "a second into the world");
        assert_eq!(hints(&mut o, Some(1060), 60), 0, "once a join");
        assert_eq!(hints(&mut o, None, 5), 0);
        assert_eq!(hints(&mut o, Some(5000), 60), 1, "the next world joined");
        o.command("orbital", "give").unwrap();
        assert_eq!(hints(&mut o, None, 5) + hints(&mut o, Some(9000), 60), 0, "known: never again");
        // (a new start of the game reads it back from storage)
        let mut again = Orbital::new(Orbital::parse(""));
        assert_eq!(hints(&mut again, None, 5) + hints(&mut again, Some(20000), 60), 0);
        // (holding a Designator says they know as well)
        fake::with(|w| {
            w.stored.clear();
            w.holding = true;
        });
        let mut held = Orbital::new(Orbital::parse(""));
        assert_eq!(hints(&mut held, Some(30000), 120), 0, "holding one");
        fake::with(|w| w.holding = false);
        assert_eq!(hints(&mut held, None, 5) + hints(&mut held, Some(40000), 60), 0, "and after");
    }
    /// A stall is not another world: the frames stop, the world runs on and the clock jumps (forwards, or back by what the
    /// client had run ahead), the player where they were, and the strike goes on. Another world's jump has seconds of
    /// frames before it, or the player somewhere else, and ends it.
    #[test]
    fn a_stall_is_not_another_world() {
        let player = Player { x: 0.5, y: 100.0, z: 400.5, yaw: 180.0, pitch: 15.0, health: 20.0, food: 20, dimension: "minecraft:overworld".into() };
        let start = |o: &mut Orbital| {
            fake::with(|w| {
                *w = fake::Fake::default();
                w.hit = Some(Hit { block_x: 0, block_y: 64, block_z: 0, x: 0.5, y: 65.0, z: 0.5, block: "minecraft:grass_block".into() });
                w.player = Some(player.clone());
                w.clock = 5000;
            });
            assert!(o.in_world());
            o.fire();
            assert!(o.strike.is_some(), "no strike");
        };
        let tick = |o: &mut Orbital, clock: u64, z: f64| {
            fake::with(|w| {
                w.clock = clock;
                if let Some(p) = w.player.as_mut() {
                    p.z = z;
                }
            });
            o.in_world()
        };
        for jump in [5000 + 25 * 20, 5000 + 75 * 20, 5000 + 3600 * 20, 4929] {
            let mut o = Orbital::new(Orbital::parse("terrain=0\nlaser=nuke\n"));
            start(&mut o);
            o.count_frame(0.016);
            o.count_frame(70.0);
            assert!(tick(&mut o, jump, 400.5) && o.strike.is_some(), "a jump to {jump} ended it");
            assert!(tick(&mut o, jump + 1, 400.5) && o.strike.is_some());
        }
        // (the title screen's frames, then a world with a clock of its own, forwards or back)
        for jump in [9000, 1000] {
            let mut o = Orbital::new(Orbital::parse("terrain=0\nlaser=nuke\n"));
            start(&mut o);
            for _ in 0..120 {
                o.count_frame(0.016);
            }
            assert!(tick(&mut o, jump, 400.5));
            assert!(o.strike.is_none(), "a world at {jump} left it going");
        }
        // (no frames seen, but the player somewhere else)
        let mut o = Orbital::new(Orbital::parse("terrain=0\nlaser=nuke\n"));
        start(&mut o);
        assert!(tick(&mut o, 9000, 2400.5));
        assert!(o.strike.is_none());
        // (a jump within the same play is nothing; a tick with no player still ends it)
        let mut o = Orbital::new(Orbital::parse("terrain=0\nlaser=nuke\n"));
        start(&mut o);
        for _ in 0..120 {
            o.count_frame(0.016);
        }
        assert!(tick(&mut o, 5030, 400.5) && o.strike.is_some());
        fake::with(|w| w.player = None);
        assert!(!o.in_world());
        assert!(o.strike.is_none());
    }

    /// Leaving the world mid-strike ends it there (nothing of it goes on into the next world), and its forceloads are
    /// let go the next time that world is played, not in another one; a strike that runs its course leaves none kept.
    #[test]
    fn leaving_mid_strike_ends_it_and_lets_its_forceloads_go_later() {
        let mut o = Orbital::new(Orbital::parse("terrain=1\nlaser=nuke\n"));
        let player = Player { x: 0.5, y: 100.0, z: 400.5, yaw: 180.0, pitch: 15.0, health: 20.0, food: 20, dimension: "minecraft:overworld".into() };
        let into = |o: &mut Orbital, clock: Option<u64>| {
            fake::with(|w| {
                w.player = clock.map(|_| player.clone());
                w.clock = clock.unwrap_or(0);
            });
            o.in_world()
        };
        fake::with(|w| {
            *w = fake::Fake::default();
            w.hit = Some(Hit { block_x: 0, block_y: 64, block_z: 0, x: 0.5, y: 65.0, z: 0.5, block: "minecraft:grass_block".into() });
            w.keep_commands = true;
        });
        assert!(into(&mut o, Some(5000)));
        o.fire();
        assert!(o.strike.is_some() && o.owes);
        for t in 1..100 {
            assert!(into(&mut o, Some(5000 + t)));
            o.tick_strike();
        }
        assert!(o.strike.is_some() && fake::with(|w| w.stored.contains_key(FORCELOADS)));
        // (out to the title screen: the strike and all it had waiting are gone, its forceloads kept to let go)
        assert!(!into(&mut o, None));
        assert!(o.strike.is_none() && o.edits.is_empty() && o.carving.is_empty() && o.spare.is_empty() && o.cleanup.is_empty());
        assert!(fake::with(|w| w.stored.contains_key(FORCELOADS)));
        // (another world: they stay kept)
        fake::with(|w| w.ran.clear());
        for t in 0..60 {
            assert!(into(&mut o, Some(90_000 + t)));
            o.release_held();
        }
        assert!(fake::with(|w| w.stored.contains_key(FORCELOADS) && !w.ran.iter().any(|c| c.contains("forceload"))));
        // (that world again, where it was left: let go, in its dimension)
        assert!(!into(&mut o, None));
        for t in 0..60 {
            assert!(into(&mut o, Some(5099 + t)));
            o.release_held();
        }
        let ran = fake::with(|w| std::mem::take(&mut w.ran));
        assert!(!ran.is_empty() && ran.iter().all(|c| c.starts_with("execute in minecraft:overworld run forceload remove ")), "{ran:?}");
        assert!(!fake::with(|w| w.stored.contains_key(FORCELOADS)));
        // (a strike played through: nothing kept once it is done)
        o.laser = LASERS.iter().position(|l| l.key == "plasma").unwrap_or(0);
        o.terrain = false;
        o.fire();
        let mut t = 6000;
        while o.strike.is_some() || !o.spare.is_empty() || !o.carving.is_empty() {
            t += 1;
            assert!(into(&mut o, Some(t)) && t < 20_000);
            o.tick_strike();
            o.paid();
        }
        assert!(!o.owes && !fake::with(|w| w.stored.contains_key(FORCELOADS)));
    }
    #[test]
    fn the_follow_camera_orbits_and_puts_the_player_back() {
        let kept = Orbital::parse("knockback=off\nfollow=on\nfollowdistance=90\n");
        assert!(!kept.knock && kept.follow && kept.follow_distance == 90.0);
        let plain = Orbital::parse("followdistance=nonsense");
        assert_eq!(Orbital::parse("seed=412").seed_lock, Some(412));
        let o = Orbital::new(Orbital::parse("impactframes=cinematic"));
        assert!(o.impact && o.impact_style == 2 && o.flags_of(11) == 12.0);
        let o = Orbital::new(Orbital::parse("impactframes=off"));
        assert!(!o.impact && o.impact_style == 1 && o.flags_of(11) == 2.0);
        assert_eq!(Orbital::parse("impactframes=on").impact_style, 1);
        assert_eq!(Orbital::parse("seed=random").seed_lock, None);
        assert_eq!(Orbital::parse("seed=5000").seed_lock, None);
        assert!(plain.knock && !plain.follow && plain.follow_distance == follow::DISTANCE);
        let nuke = LASERS.iter().position(|l| l.key == "nuke").expect("the nuke");
        for on in [true, false] {
            let mut s = Soak::new(3);
            s.o.follow = on;
            s.o.knock = true;
            fake::with(|w| w.keep_commands = true);
            s.fire(nuke, (1000, -2000));
            let mut ticks = 0;
            while s.o.strike.is_some() && ticks < 1000 {
                s.step("follow");
                s.o.follow_tick();
                ticks += 1;
            }
            let (ran, pushes) = fake::with(|w| (std::mem::take(&mut w.ran), w.pushes));
            assert!(!ran.iter().any(|c| c.contains("gamemode")));
            let tps: Vec<&String> = ran.iter().filter(|c| c.starts_with("tp @s")).collect();
            if on {
                assert!(pushes > 20 * 20, "{pushes} kicks");
                assert_eq!(tps.len(), 1, "{tps:?}");
                assert!(tps[0].ends_with(" ~ ~"));
                assert!(s.o.following.is_none());
            } else {
                assert!(tps.is_empty());
            }
        }
    }

    /// A Supercell called in on land far off, none of it loaded as it fires (the player 800 blocks away): its bolts'
    /// pits, its funnels' tracks and its fire sweeps go in as edits whatever has loaded (the game leaves out what has
    /// not), no tick overworks, and it ends on time; stopped part way, its fires are still put out.
    #[test]
    fn a_supercell_on_far_unloaded_land_stays_light() {
        let sc = LASERS.iter().position(|l| l.key == "supercell").expect("the supercell");
        for slow in [4, 0] {
            let mut s = Soak::new(5);
            s.loaded = Loaded { me: (1800, -2000), view: 8, forced: Default::default(), slow, now: 0 };
            s.fire(sc, (1000, -2000));
            let mut ticks = 0;
            while s.o.strike.is_some() {
                s.step("far");
                ticks += 1;
                assert!(ticks < 1400, "it never ended");
            }
            let edits = fake::with(|w| w.edits);
            eprintln!("chunks x{slow}: worst tick {:.2}M ({}), {edits} edits, {ticks} ticks", s.worst.0 as f64 / 1e6, s.worst.1);
            assert!(s.worst.0 <= CAP, "a tick of {:.2}M: {}", s.worst.0 as f64 / 1e6, s.worst.1);
            assert!(edits > 50, "the pits went in ({edits} edits)");
        }
        // (stopped in the storm: nothing of it left waiting, its fires left burning)
        let mut s = Soak::new(6);
        s.fire(sc, (0, 0));
        for _ in 0..400 {
            s.step("stop");
        }
        s.stop();
        for _ in 0..200 {
            s.step("after");
        }
        assert!(s.o.cleanup.is_empty() && s.o.edits.is_empty());
        assert!(s.worst.0 <= CAP, "a tick of {:.2}M: {}", s.worst.0 as f64 / 1e6, s.worst.1);
    }

    /// A Tsunami called in on land far off, none of it loaded as it fires (the player 800 blocks away): it waits for the
    /// land cheaply, its edits go in as it loads (or are left out where it never does), no tick overworks, it ends on time;
    /// and one close by carries the player along (carry-player and pushes of the surge) with the knockback on, never with
    /// it off.
    #[test]
    fn a_tsunami_on_far_unloaded_land_stays_light() {
        let ts = LASERS.iter().position(|l| l.key == "tsunami").expect("the tsunami");
        for slow in [4, 0] {
            let mut s = Soak::new(5);
            s.loaded = Loaded { me: (1800, -2000), view: 8, forced: Default::default(), slow, now: 0 };
            s.fire(ts, (1000, -2000));
            let mut ticks = 0;
            while s.o.strike.is_some() {
                s.step("far");
                ticks += 1;
                assert!(ticks < 1400, "it never ended");
            }
            let edits = fake::with(|w| w.edits);
            eprintln!("chunks x{slow}: worst tick {:.2}M ({}), {edits} edits, {ticks} ticks", s.worst.0 as f64 / 1e6, s.worst.1);
            assert!(s.worst.0 <= CAP, "a tick of {:.2}M: {}", s.worst.0 as f64 / 1e6, s.worst.1);
            if slow > 0 {
                assert!(edits > 50, "the land swept as it loaded ({edits} edits)");
            }
        }
        for knock in [true, false] {
            let mut s = Soak::new(7);
            s.o.knock = knock;
            fake::with(|w| w.pushes = 0);
            s.fire(ts, (0, 0));
            // (the player 100 blocks off the target, where the water reaches them by 12 s)
            fake::with(|w| {
                if let Some(p) = w.player.as_mut() {
                    p.x = 0.5;
                    p.z = 100.5;
                }
            });
            for _ in 0..(40 * 20) {
                s.step("surge");
                s.o.surge_tick();
            }
            let carries = fake::with(|w| w.pushes);
            assert_eq!(carries > 100, knock, "{carries} carries with the knockback {knock}");
        }
    }

    /// A Hurricane called in on land far off, none of it loaded as it fires (the player 800 blocks away): it waits for
    /// the land cheaply, its edits go in as it loads (or are left out where it never does), no tick overworks, and it
    /// ends on time; and one close by carries the player off (pushes) with the knockback on, never with it off.
    #[test]
    fn a_hurricane_on_far_unloaded_land_stays_light() {
        let hu = LASERS.iter().position(|l| l.key == "hurricane").expect("the hurricane");
        for slow in [4, 0] {
            let mut s = Soak::new(5);
            s.loaded = Loaded { me: (1800, -2000), view: 8, forced: Default::default(), slow, now: 0 };
            s.fire(hu, (1000, -2000));
            let mut ticks = 0;
            while s.o.strike.is_some() {
                s.step("far");
                ticks += 1;
                assert!(ticks < 1400, "it never ended");
            }
            let edits = fake::with(|w| w.edits);
            eprintln!("chunks x{slow}: worst tick {:.2}M ({}), {edits} edits, {ticks} ticks", s.worst.0 as f64 / 1e6, s.worst.1);
            assert!(s.worst.0 <= CAP, "a tick of {:.2}M: {}", s.worst.0 as f64 / 1e6, s.worst.1);
            if slow > 0 {
                assert!(edits > 50, "the land torn up as it loaded ({edits} edits)");
            }
        }
        for knock in [true, false] {
            let mut s = Soak::new(7);
            s.o.knock = knock;
            fake::with(|w| w.pushes = 0);
            s.fire(hu, (0, 0));
            // (the player 110 blocks off the eye, where the wind reaches by 27 s)
            fake::with(|w| {
                if let Some(p) = w.player.as_mut() {
                    p.x = 110.5;
                    p.z = 0.5;
                }
            });
            for _ in 0..(40 * 20) {
                s.step("carry");
                s.o.carry_tick();
            }
            let pushes = fake::with(|w| w.pushes);
            assert_eq!(pushes > 100, knock, "{pushes} pushes with the knockback {knock}");
        }
    }

    #[test]
    fn no_tick_overworks_through_fire_stop_and_refire() {
        let (worst, at) = soak(40, 1, 0.02);
        eprintln!("worst tick: {:.2}M ({at})", worst as f64 / 1e6);
        assert!(worst <= CAP, "a tick of {:.2}M: {at}", worst as f64 / 1e6);
    }

    /// `ORBITAL_SOAK=N cargo test --release thousands_of_strikes -- --ignored --nocapture`: N sequences (default 2000),
    /// and no tick more than 3 ms past what its counted work explains (the Nuke's old scan over every column not loaded
    /// for each job, uncounted, took 5 ms over: in the game 50M fuel, the mod stopped).
    #[test]
    #[ignore]
    fn thousands_of_strikes() {
        let n = std::env::var("ORBITAL_SOAK").ok().and_then(|v| v.parse().ok()).unwrap_or(2000);
        let (worst, at) = soak(n, 7, 0.003);
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
        o.strike = Some(Strike { plan, next: 0, more: Default::default(), given: 0, ticks: 0, length: 1000.0, params: [0.0; 16], waiting: Default::default(), urgent: Default::default(), data: Vec::new(), data_sent: true, skipped: 0.0, sounds: Default::default(), key: "", sprites: 0 });
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

    /// No pass is given to the game as it starts: the loaded laser's only a few seconds into play, and while the game
    /// builds one the storage says which. Should the game stop there (Apple's Metal compiler has, on the Downfall's and
    /// the Nuke's), the next start loads the Plasma instead of crashing again, and says so once in a world.
    #[test]
    fn a_pass_the_game_cannot_build_never_stops_every_start() {
        fake::with(|w| *w = fake::Fake::default());
        let nuke = LASERS.iter().position(|l| l.key == "nuke").expect("the nuke");
        let mut o = Orbital::new(Orbital::parse("laser=nuke"));
        for _ in 0..30 {
            o.warm();
        }
        assert_eq!(o.compiled, None, "a pass handed over before any play");
        o.ticks = WARM_AFTER;
        o.warm();
        assert_eq!(o.compiled, Some(pass_of(LASERS[nuke])));
        let noted = fake::with(|w| w.stored.get(BUILDING).cloned());
        assert_eq!(noted.as_deref(), Some(b"6".as_slice()), "the pass being built not noted");
        for _ in 0..4 {
            o.warm();
        }
        assert!(fake::with(|w| !w.stored.contains_key(BUILDING)), "the note outlived the build");
        // (the next frames: nothing handed over again; a strike of the same laser needs nothing new built)
        assert!(o.building.is_none() && !o.warming);
        // the game stopped while it built the Nuke's: the next start loads the Plasma, and says why once
        fake::with(|w| w.stored.insert(BUILDING.into(), b"6".to_vec()));
        let mut settings = Orbital::parse("laser=nuke");
        assert_eq!(Orbital::recover(&mut settings), Some(nuke));
        assert_eq!(settings.laser, 0);
        assert!(fake::with(|w| !w.stored.contains_key(BUILDING)));
        // another laser's pass (one loaded and dropped): the loaded laser stays
        fake::with(|w| w.stored.insert(BUILDING.into(), b"1".to_vec()));
        let mut settings = Orbital::parse("laser=payload");
        assert_eq!(Orbital::recover(&mut settings), None);
        assert_eq!(LASERS[settings.laser].key, "payload");
        let mut settings = Orbital::parse("laser=nuke");
        assert_eq!(Orbital::recover(&mut settings), None, "nothing noted, nothing changed");
        assert_eq!(settings.laser, nuke);
    }
}
