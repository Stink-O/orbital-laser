//! The Horizon mod SDK (Stink-O/horizon `horizon-mod-sdk`, wit/horizon.wit) for a native build: the same modules,
//! types and functions the WebAssembly SDK's bindings give, so the mod's code builds unchanged. Each call does what
//! the fork's runtime (`horizon-mods/src/runtime.rs`) did on the host side of the WebAssembly boundary: it reads the
//! snapshot the game gave before the call, or keeps state, or queues an `Output`. The game's glue drives it through
//! `__host`. The WebAssembly sandbox's per-call caps are left out; value clamps stay.
#![allow(dead_code, clippy::all)]


pub mod log {
    #[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
    pub enum Level {
        Debug,
        Info,
        Warn,
        Error,
    }
    pub fn write(level: Level, message: &str) {
        let level = match level {
            Level::Debug => ::log::Level::Debug,
            Level::Info => ::log::Level::Info,
            Level::Warn => ::log::Level::Warn,
            Level::Error => ::log::Level::Error,
        };
        let id = super::__host::with(|s| s.id.clone());
        ::log::log!(target: "horizon_mods", level, "[mod {}] {}", id, message);
    }
}

pub mod game {
    #[derive(Clone, Debug, PartialEq, Default)]
    pub struct Player {
        pub x: f64,
        pub y: f64,
        pub z: f64,
        pub yaw: f32,
        pub pitch: f32,
        pub health: f32,
        pub food: u32,
        pub dimension: String,
    }
    #[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
    pub struct Clock {
        pub game_time: u64,
        pub day_time: u64,
    }
    pub fn get_player() -> Option<Player> {
        super::__host::with(|s| s.snapshot.player.clone())
    }
    pub fn get_clock() -> Option<Clock> {
        super::__host::with(|s| s.snapshot.clock)
    }
    /// Whether the local player flies (creative flight, or a spectator).
    pub fn player_flying() -> bool {
        super::__host::with(|s| s.snapshot.flying)
    }
}

pub mod chat {
    pub fn show(text: &str) {
        let text = text.to_owned();
        super::__host::with(|s| {
            let name = s.name.clone();
            s.out.push(super::__host::Output::Chat { name, text })
        });
    }
}

pub mod hud {
    #[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
    pub enum Corner {
        TopLeft,
        TopRight,
        BottomLeft,
        BottomRight,
    }
    #[derive(Clone, Debug, PartialEq)]
    pub struct Line {
        pub text: String,
        pub color: u32,
    }
    pub fn set_panel(corner: Corner, lines: &[Line]) {
        let lines = lines
            .iter()
            .take(super::__host::HUD_LINES)
            .map(|l| Line {
                text: l.text.clone(),
                color: l.color & 0xFF_FFFF,
            })
            .collect();
        super::__host::with(|s| s.panel = Some((corner, lines)));
    }
    pub fn clear() {
        super::__host::with(|s| s.panel = None);
    }
}

pub mod storage {
    fn key_ok(key: &str) -> bool {
        let chars_ok = (1..=64).contains(&key.len())
            && key
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"_.-".contains(&b));
        chars_ok && key != "." && key != ".."
    }
    pub fn get(key: &str) -> Option<Vec<u8>> {
        let dir = super::__host::with(|s| s.data_dir.clone());
        key_ok(key).then(|| std::fs::read(dir.join(key)).ok()).flatten()
    }
    pub fn set(key: &str, value: &[u8]) -> Result<(), String> {
        if !key_ok(key) {
            return Err(format!("{key:?} is not [a-z0-9_.-]{{1,64}}"));
        }
        let dir = super::__host::with(|s| s.data_dir.clone());
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        std::fs::write(dir.join(key), value).map_err(|e| e.to_string())
    }
    pub fn delete(key: &str) {
        if key_ok(key) {
            let dir = super::__host::with(|s| s.data_dir.clone());
            let _ = std::fs::remove_file(dir.join(key));
        }
    }
}

pub mod input {
    #[derive(Clone, Debug, PartialEq)]
    pub struct HeldItem {
        pub id: String,
        pub count: u32,
        pub slot: u32,
        pub custom_name: Option<String>,
        pub custom_data: Option<String>,
    }
    #[derive(Clone, Debug, PartialEq)]
    pub struct ItemUse {
        pub item: HeldItem,
        pub ticks: u32,
    }
    #[derive(Clone, Copy, Debug, PartialEq)]
    pub struct Click {
        pub x: f32,
        pub y: f32,
        pub button: u32,
    }
    #[derive(Clone, Debug, PartialEq)]
    pub enum Event {
        UseStart(ItemUse),
        UseStop(ItemUse),
        KeyDown(String),
        KeyUp(String),
        ScreenClick(Click),
        ScreenClosed,
    }
    #[derive(Clone, Debug, PartialEq)]
    pub enum Typed {
        Text(String),
        Key(String),
    }
    pub fn claim_items(ids: &[String]) {
        let ids = ids.iter().take(64).cloned().collect();
        super::__host::with(|s| s.claims = ids);
    }
    pub fn register_key(name: &str, label: &str, key: &str) {
        let k = super::__host::ModKey {
            name: name.to_owned(),
            label: label.to_owned(),
            key: key.to_owned(),
        };
        super::__host::with(|s| {
            if s.keys.contains(&k) {
                return;
            }
            s.keys.retain(|o| o.name != k.name);
            s.keys.push(k);
            s.out.push(super::__host::Output::Keys);
        });
    }
    pub fn held() -> Option<HeldItem> {
        super::__host::with(|s| s.snapshot.held.clone())
    }
    pub fn poll() -> Vec<Event> {
        super::__host::with(|s| std::mem::take(&mut s.events))
    }
    pub fn poll_typed() -> Vec<Typed> {
        super::__host::with(|s| std::mem::take(&mut s.typed))
    }
}

pub mod ui {
    #[derive(Clone, Copy, Debug, PartialEq, Default)]
    pub struct Rect {
        pub x: f32,
        pub y: f32,
        pub w: f32,
        pub h: f32,
    }
    #[derive(Clone, Copy, Debug, PartialEq, Default)]
    pub struct Point {
        pub x: f32,
        pub y: f32,
    }
    #[derive(Clone, Debug, PartialEq)]
    pub enum Draw {
        Fill((Rect, u32)),
        Quad((Vec<Point>, u32)),
        Sprite((String, Rect, u32)),
        Item((String, String, Point, f32)),
        Text((String, Point, u32, bool)),
    }
    pub fn show(draws: &[Draw]) {
        let draws: Vec<Draw> = draws.iter().take(4096).cloned().collect();
        super::__host::with(|s| {
            if s.screen.replace(draws).is_none() {
                s.out.push(super::__host::Output::Screen { open: true });
            }
        });
    }
    pub fn close() {
        super::__host::with(|s| {
            if s.screen.take().is_some() {
                s.typed.clear();
                s.out.push(super::__host::Output::Screen { open: false });
            }
        });
    }
    pub fn cursor() -> Option<Point> {
        super::__host::with(|s| s.cursor)
    }
}

pub mod render {
    use std::sync::Arc;
    pub fn set_post(wgsl: &str) {
        if wgsl.len() > super::__host::POST_SOURCE {
            ::log::warn!("post pass over {} KiB, ignored", super::__host::POST_SOURCE >> 10);
            return;
        }
        super::__host::with(|s| {
            if s.post_source.as_ref().is_some_and(|(src, _)| **src == *wgsl) {
                return;
            }
            use std::hash::{Hash, Hasher};
            let mut h = std::collections::hash_map::DefaultHasher::new();
            s.id.hash(&mut h);
            wgsl.hash(&mut h);
            s.post_source = Some((Arc::from(wgsl), h.finish()));
        });
    }
    pub fn set_params(params: &[f32]) {
        let mut p = [0.0; super::__host::POST_PARAMS];
        for (to, from) in p.iter_mut().zip(params) {
            *to = if from.is_finite() { *from } else { 0.0 };
        }
        super::__host::with(|s| s.post_params = Some(p));
    }
    pub fn clear_post() {
        super::__host::with(|s| {
            s.post_source = None;
            s.post_params = None;
            s.post_data = None;
            // (clearing the pass ends a hold, as the fork's clear-post does)
            s.hold = false;
            s.hold_areas.clear();
        });
    }
    pub fn set_data(words: &[u32]) {
        if words.len() > super::__host::POST_DATA_WORDS {
            ::log::warn!("post pass data over {} KiB, ignored", (super::__host::POST_DATA_WORDS * 4) >> 10);
            return;
        }
        super::__host::with(|s| {
            if s.post_data.as_ref().is_some_and(|(d, _)| **d == *words) {
                return;
            }
            let version = s.post_data.as_ref().map_or(1, |(_, v)| v + 1);
            s.post_data = Some((Arc::from(words), version));
        });
    }
    /// `render.set-warp`: the world warp's WGSL (empty: none); built by the game the first time it is turned on.
    pub fn set_warp(wgsl: &str) {
        if wgsl.len() > super::__host::POST_SOURCE {
            ::log::warn!("world warp over {} KiB, ignored", super::__host::POST_SOURCE >> 10);
            return;
        }
        super::__host::with(|s| {
            if wgsl.is_empty() {
                s.warp_source = None;
            } else if s.warp_source.as_deref() != Some(wgsl) {
                s.warp_source = Some(Arc::from(wgsl));
            }
        });
    }
    /// `render.warp-on`: the warp on or off. `copies` and `radius` (the solid sections near a point drawn again) are
    /// kept for the mod's sake; the native build draws no copies.
    pub fn warp_on(on: bool, x: f64, y: f64, z: f64, copies: u32, radius: f32) {
        super::__host::with(|s| {
            s.warp = on.then_some(super::__host::Warp { at: [x, y, z], copies: copies.min(8), radius });
        });
    }
    /// `render.hold-world`: the terrain kept on screen as it is drawn while the world changes under it.
    pub fn hold_world(on: bool) {
        super::__host::with(|s| {
            if !on {
                s.hold_areas.clear();
            }
            s.hold = on;
        });
    }
    /// `render.hold-world-within`: while held, only the sections whose middles lie in these circles (x, z, radius)
    /// go on waiting; empty: all of them.
    pub fn hold_world_within(areas: &[(f64, f64, f64)]) {
        super::__host::with(|s| {
            s.hold_areas = areas.iter().copied().filter(|(x, z, r)| x.is_finite() && z.is_finite() && r.is_finite()).collect();
        });
    }
    /// `render.set-hand-tint` (the fork's API 12): the first-person hand and held item multiplied by (r, g, b), kept
    /// until changed, 1, 1, 1 changing nothing. Kept here as the fork keeps it (each clamped to 0..8, not a number: 1),
    /// but nothing draws it yet: upstream's renderer has no hand tint, so the hand stays as the game draws it. It is
    /// only the light on the hand (the Supervolcano's), so it isn't in `native_build::UNSUPPORTED` and no laser waits
    /// for it. To draw it later: upstream's `hand_drawn` hook (API 364) hands over the hand's quads once drawn.
    pub fn set_hand_tint(r: f32, g: f32, b: f32) {
        let c = |v: f32| if v.is_finite() { v.clamp(0.0, 8.0) } else { 1.0 };
        super::__host::with(|s| s.hand_tint = Some([c(r), c(g), c(b)]));
    }
    pub fn shake(strength: f32, seconds: f32) {
        if strength.is_finite() && seconds.is_finite() && strength > 0.0 && seconds > 0.0 {
            super::__host::with(|s| {
                s.out.push(super::__host::Output::Shake {
                    strength: strength.min(1.0),
                    seconds: seconds.min(60.0),
                })
            });
        }
    }
}

pub mod world {
    #[derive(Clone, Debug, PartialEq)]
    pub struct Hit {
        pub block_x: i32,
        pub block_y: i32,
        pub block_z: i32,
        pub x: f64,
        pub y: f64,
        pub z: f64,
        pub block: String,
    }
    #[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
    pub enum Heightmap {
        WorldSurface,
        MotionBlocking,
        MotionBlockingNoLeaves,
        OceanFloor,
    }
    #[derive(Clone, Copy, Debug, PartialEq)]
    pub struct BlockRun {
        pub x: i32,
        pub z: i32,
        pub y: i32,
        pub height: u32,
        pub surface: Option<Heightmap>,
        pub block: u32,
        pub only: Option<u32>,
    }
    #[derive(Clone, Debug, PartialEq, Default)]
    pub struct BlockEdit {
        pub palette: Vec<String>,
        pub filters: Vec<String>,
        pub runs: Vec<BlockRun>,
    }
    #[derive(Clone, Debug, PartialEq)]
    pub struct SurfaceHeights {
        pub tag: u32,
        pub heights: Vec<Option<i32>>,
    }
    #[derive(Clone, Debug, PartialEq)]
    pub struct ColumnBlocks {
        pub tag: u32,
        pub palette: Vec<String>,
        pub bases: Vec<Option<i32>>,
        pub blocks: Vec<u16>,
        pub tints: Vec<u32>,
    }
    use super::__host::{Output, with};
    pub fn raycast(distance: f32) -> Option<Hit> {
        let max = distance.clamp(0.0, super::__host::RAYCAST_MAX);
        with(|s| {
            s.snapshot
                .view_hit
                .as_ref()
                .filter(|(d, _)| *d <= max)
                .map(|(_, hit)| hit.clone())
        })
    }
    pub fn run_commands(commands: &[String]) {
        if !commands.is_empty() {
            let commands = commands.to_vec();
            with(|s| s.out.push(Output::Commands { commands }));
        }
    }
    pub fn play_sound(event: &str, at: Option<(f64, f64, f64)>, volume: f32, pitch: f32) {
        let event = event.to_owned();
        with(|s| {
            s.out.push(Output::Sound {
                event,
                at: at.map(|(x, y, z)| [x, y, z]),
                volume: if volume.is_finite() { volume.clamp(0.0, 16.0) } else { 1.0 },
                pitch: if pitch.is_finite() { pitch.clamp(0.0, 4.0) } else { 1.0 },
            })
        });
    }
    pub fn push_player(x: f32, y: f32, z: f32) {
        if x.is_finite() && y.is_finite() && z.is_finite() {
            with(|s| {
                s.out.push(super::__host::Output::Push {
                    velocity: [x.clamp(-4.0, 4.0), y.clamp(-4.0, 4.0), z.clamp(-4.0, 4.0)],
                })
            });
        }
    }
    /// The fork's `world.carry-player`: the local player moved by `x`, `y`, `z` this tick in place of their own
    /// motion, their view turned by `turn` degrees; whether the carry held them (the glue's `carry_step`).
    pub fn carry_player(x: f32, y: f32, z: f32, turn: f32) -> bool {
        if !(x.is_finite() && y.is_finite() && z.is_finite()) {
            return false;
        }
        with(|s| {
            s.out.retain(|o| !matches!(o, super::__host::Output::Carry { .. }));
            s.out.push(super::__host::Output::Carry {
                delta: [x.clamp(-4.0, 4.0), y.clamp(-4.0, 4.0), z.clamp(-4.0, 4.0)],
                turn: if turn.is_finite() { turn.clamp(-6.0, 6.0) } else { 0.0 },
            });
            s.snapshot.carried
        })
    }
    pub fn set_flying_speed(speed: Option<f32>) {
        let speed = speed
            .filter(|s| s.is_finite())
            .map(|s| s.clamp(0.0, super::__host::FLYING_SPEED_MAX));
        with(|s| s.flying_speed = speed);
    }
    pub fn edit_blocks(edit: &BlockEdit) {
        let palette = edit.palette.len();
        let filters = edit.filters.len();
        if let Some(bad) = edit
            .runs
            .iter()
            .find(|r| r.block as usize >= palette || r.only.is_some_and(|f| f as usize >= filters))
        {
            ::log::warn!(
                "edit-blocks: a run at {} {} {} names palette entry {} or filter {:?}, past the end; left out",
                bad.x, bad.y, bad.z, bad.block, bad.only
            );
            return;
        }
        if !edit.runs.is_empty() {
            let edit = edit.clone();
            with(|s| s.out.push(Output::Edit { edit }));
        }
    }
    pub fn surface_height(tag: u32, columns: &[(i32, i32)], heightmap: Heightmap) {
        let columns = columns.to_vec();
        with(|s| s.out.push(Output::Surface { tag, columns, heightmap }));
    }
    pub fn poll_surface_heights() -> Vec<SurfaceHeights> {
        with(|s| std::mem::take(&mut s.surface))
    }
    pub fn read_columns(tag: u32, columns: &[(i32, i32)], heightmap: Heightmap, below: u32, above: u32) {
        let columns = columns.to_vec();
        with(|s| s.out.push(Output::Columns { tag, columns, heightmap, below, above }));
    }
    pub fn poll_columns() -> Vec<ColumnBlocks> {
        with(|s| std::mem::take(&mut s.columns))
    }
}

/// Capability `atlas` (the fork's API 10): where blocks' textures are in the block sprite arrays, answered at once by
/// the game (`native_block_sprites`, through `__host::Atlas`); the arrays themselves are the post pass's bindings 8
/// to 16 (`WorldDrawn::block_sprites`).
pub mod atlas {
    #[derive(Clone, Copy, Debug, PartialEq)]
    pub enum Tint {
        None,
        Grass,
        Foliage,
        DryFoliage,
        Water,
        Fixed(u32),
    }
    #[derive(Clone, Copy, Debug, PartialEq)]
    pub struct Sprite {
        pub array: u32,
        pub layer: u32,
        pub animated: bool,
        pub cutout: bool,
    }
    #[derive(Clone, Copy, Debug, PartialEq)]
    pub struct Face {
        pub sprite: Sprite,
        pub rect: (f32, f32, f32, f32),
        pub inset: f32,
        pub uv: (f32, f32, f32, f32, f32, f32),
        pub tint: Tint,
        pub translucent: bool,
    }
    #[derive(Clone, Debug, PartialEq)]
    pub struct BlockFaces {
        pub sides: Vec<Vec<Face>>,
        pub particle: Option<Sprite>,
        pub cube: bool,
    }
    /// At most this many names a call, as the fork's runtime; the rest are none.
    const MAX_NAMES: usize = 4096;
    pub fn block_sprites(names: &[String]) -> Vec<Option<BlockFaces>> {
        let atlas = super::__host::with(|s| s.atlas.clone());
        let mut out = match atlas {
            Some(a) => (a.blocks)(&names[..names.len().min(MAX_NAMES)]),
            None => Vec::new(),
        };
        out.resize(names.len(), None);
        out
    }
    pub fn texture_sprites(names: &[String]) -> Vec<Option<Sprite>> {
        let atlas = super::__host::with(|s| s.atlas.clone());
        let mut out = match atlas {
            Some(a) => (a.textures)(&names[..names.len().min(MAX_NAMES)]),
            None => Vec::new(),
        };
        out.resize(names.len(), None);
        out
    }
    pub fn resources_version() -> u64 {
        super::__host::with(|s| s.atlas.as_ref().map_or(0, |a| a.version))
    }
}

/// What this build can't do of the fork's SDK yet, and so which lasers it can't play. The mod asks `unavailable`
/// (native/assemble.sh puts it in place of lib.rs's `native_unavailable`): the wheel shows those lasers greyed out with
/// `NOT_YET`, they can't be loaded or fired, and `/orbital <laser>` answers `NOT_YET`. On the fork every laser plays.
pub mod native_build {
    /// The fork's calls this build has, so the mod builds, but doesn't carry out yet. Take one out when the glue does.
    pub const UNSUPPORTED: &[&str] = &[
        // (none: the Fold's world warp and held world are drawn since upstream's #11955 and #11956)
    ];
    /// The fork's calls a laser's strike can't do without (by its key in lasers.rs), for the lasers that need one this
    /// build may lack: a laser with a call in UNSUPPORTED is unavailable. A new laser that needs a call this build
    /// doesn't make: add it here with that call (and a new call to UNSUPPORTED too, with a stand-in for it above so the
    /// mod builds).
    pub const NEEDS: &[(&str, &[&str])] = &[
        // the Fold: the land bent through the world warp, the crater made behind the held world
        ("fold", &["render.set-warp", "render.warp-on", "render.hold-world", "render.hold-world-within"]),
    ];
    /// What the wheel, the Designator and `/orbital <laser>` say of an unavailable laser.
    pub const NOT_YET: &str = "Not on the native build yet";
    /// Whether this build carries out the fork's call `call` (as the fork names it: `render.set-warp`).
    pub fn supports(call: &str) -> bool {
        !UNSUPPORTED.contains(&call)
    }
    /// Why the laser `key` can't be played on this build (`NOT_YET`), or none.
    pub fn unavailable(key: &str) -> Option<&'static str> {
        unavailable_without(key, UNSUPPORTED)
    }
    /// Why the laser `key` can't be played on a build lacking the calls `unsupported`, or none.
    fn unavailable_without(key: &str, unsupported: &[&str]) -> Option<&'static str> {
        NEEDS
            .iter()
            .any(|(k, calls)| *k == key && calls.iter().any(|c| unsupported.contains(c)))
            .then_some(NOT_YET)
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        #[test]
        fn every_laser_plays_on_this_build() {
            for key in ["plasma", "nuke", "rod", "supercell", "hurricane", "tsunami", "fold", "supervolcano", "moonfall", "skybreak"] {
                assert_eq!(unavailable(key), None, "{key}");
            }
            assert!(supports("render.set-warp") && supports("render.hold-world-within") && supports("render.set-post"));
        }
        #[test]
        fn a_laser_waits_for_a_call_the_build_lacks() {
            assert_eq!(unavailable_without("fold", &["render.set-warp"]), Some(NOT_YET));
            assert_eq!(unavailable_without("fold", &["render.set-post"]), None);
            assert_eq!(unavailable_without("nuke", &["render.set-warp"]), None);
        }
        #[test]
        fn every_call_is_named_as_the_fork_names_it() {
            for (key, calls) in NEEDS {
                for c in *calls {
                    assert!(c.split_once('.').is_some_and(|(i, f)| !i.is_empty() && !f.is_empty() && !f.contains('_')), "{key}: {c}");
                }
            }
        }
    }
}

/// `events.registration`.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Registration {
    pub commands: Vec<String>,
    pub tick: bool,
    pub frame: bool,
    pub chat: bool,
}

/// The game's calls into a mod. Only the hooks [`Registration`] asks for
/// are called; the others may stay as their defaults.
pub trait Mod: Sized + 'static {
    fn init() -> Result<(Self, Registration), String>;
    fn tick(&mut self, _tick: u64) {}
    fn frame(&mut self, _seconds: f32) {}
    fn command(&mut self, _name: &str, _args: &str) -> Result<Option<String>, String> {
        Err("This command does nothing".into())
    }
    fn chat(&mut self, _text: &str) {}
}

impl Registration {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn command(mut self, name: &str) -> Self {
        self.commands.push(name.into());
        self
    }
    pub fn on_tick(mut self) -> Self {
        self.tick = true;
        self
    }
    pub fn on_frame(mut self) -> Self {
        self.frame = true;
        self
    }
    pub fn on_chat(mut self) -> Self {
        self.chat = true;
        self
    }
}

pub fn info(message: &str) {
    log::write(log::Level::Info, message);
}
pub fn warn(message: &str) {
    log::write(log::Level::Warn, message);
}

/// Exports a [`Mod`]: its calls, for the game's glue (`__host::Exports`).
#[macro_export]
macro_rules! export_mod {
    ($t:ty) => {
        ::std::thread_local! {
            static __MOD_STATE: ::std::cell::RefCell<Option<$t>> = const { ::std::cell::RefCell::new(None) };
        }
        fn __mod_with(f: impl FnOnce(&mut $t)) {
            __MOD_STATE.with(|s| {
                if let Some(m) = s.borrow_mut().as_mut() {
                    f(m)
                }
            })
        }
        /// The mod's calls, for the game's glue.
        pub static __EXPORTS: $crate::__host::Exports = $crate::__host::Exports {
            init: || {
                let (m, registration) = <$t as $crate::Mod>::init()?;
                __MOD_STATE.with(|s| *s.borrow_mut() = Some(m));
                Ok(registration)
            },
            tick: |tick| __mod_with(|m| $crate::Mod::tick(m, tick)),
            frame: |seconds| __mod_with(|m| $crate::Mod::frame(m, seconds)),
            command: |name, args| {
                let mut out = Err("The mod is not running".to_string());
                __mod_with(|m| out = $crate::Mod::command(m, name, args));
                out
            },
            chat: |text| __mod_with(|m| $crate::Mod::chat(m, text)),
        };
    };
}

/// The host side: what the game's glue sets before a call and takes after it (the fork's runtime `State`).
pub mod __host {
    use super::{game, hud, input, ui, world};
    use std::{cell::RefCell, path::PathBuf, sync::Arc};

    pub const HUD_LINES: usize = 16;
    pub const POST_SOURCE: usize = 256 << 10;
    pub const POST_PARAMS: usize = 16;
    pub const POST_DATA_WORDS: usize = 1 << 18;
    pub const RAYCAST_MAX: f32 = 1024.0;
    pub const FLYING_SPEED_MAX: f32 = 50.0;

    /// The mod's calls.
    pub struct Exports {
        pub init: fn() -> Result<super::Registration, String>,
        pub tick: fn(u64),
        pub frame: fn(f32),
        pub command: fn(&str, &str) -> Result<Option<String>, String>,
        pub chat: fn(&str),
    }

    /// The game's answers to `atlas`, given by the glue (and again when the resources load anew): lookups over the
    /// pack's resources, answered at once, and the resources' version.
    #[derive(Clone)]
    pub struct Atlas {
        pub blocks: Arc<dyn Fn(&[String]) -> Vec<Option<super::atlas::BlockFaces>>>,
        pub textures: Arc<dyn Fn(&[String]) -> Vec<Option<super::atlas::Sprite>>>,
        pub version: u64,
    }

    /// What mods may read of the game, copied once per tick by the game.
    #[derive(Clone, Debug, Default)]
    pub struct Snapshot {
        pub player: Option<game::Player>,
        pub clock: Option<game::Clock>,
        pub held: Option<input::HeldItem>,
        /// The first block along the view within `RAYCAST_MAX`, and its distance.
        pub view_hit: Option<(f32, world::Hit)>,
        /// Whether the last `carry_player` held the player (true when none was asked: the next holds).
        pub carried: bool,
        /// Whether the local player flies (creative flight, or a spectator).
        pub flying: bool,
    }

    /// A keybind the mod registered.
    #[derive(Clone, Debug, PartialEq)]
    pub struct ModKey {
        pub name: String,
        pub label: String,
        pub key: String,
    }

    /// What the mod asked the game to do since the last `drain`.
    #[derive(Clone, Debug, PartialEq)]
    pub enum Output {
        Chat { name: String, text: String },
        Screen { open: bool },
        Commands { commands: Vec<String> },
        Edit { edit: world::BlockEdit },
        Surface { tag: u32, columns: Vec<(i32, i32)>, heightmap: world::Heightmap },
        Columns { tag: u32, columns: Vec<(i32, i32)>, heightmap: world::Heightmap, below: u32, above: u32 },
        Keys,
        Sound { event: String, at: Option<[f64; 3]>, volume: f32, pitch: f32 },
        Shake { strength: f32, seconds: f32 },
        /// `world.push-player`: added to the local player's velocity, blocks a tick.
        Push { velocity: [f32; 3] },
        /// `world.carry-player`: the local player moved by `delta` this tick, their view turned by `turn` degrees.
        Carry { delta: [f32; 3], turn: f32 },
    }

    /// `render.warp-on`'s arguments while the warp is on.
    #[derive(Clone, Copy, Debug, PartialEq)]
    pub struct Warp {
        pub at: [f64; 3],
        pub copies: u32,
        pub radius: f32,
    }

    #[derive(Default)]
    pub struct State {
        pub name: String,
        pub id: String,
        pub snapshot: Snapshot,
        pub out: Vec<Output>,
        pub panel: Option<(hud::Corner, Vec<hud::Line>)>,
        pub data_dir: PathBuf,
        pub claims: Vec<String>,
        pub keys: Vec<ModKey>,
        pub events: Vec<input::Event>,
        pub typed: Vec<input::Typed>,
        pub screen: Option<Vec<ui::Draw>>,
        pub cursor: Option<ui::Point>,
        pub post_source: Option<(Arc<str>, u64)>,
        pub post_params: Option<[f32; POST_PARAMS]>,
        pub post_data: Option<(Arc<[u32]>, u64)>,
        pub surface: Vec<world::SurfaceHeights>,
        pub columns: Vec<world::ColumnBlocks>,
        pub flying_speed: Option<f32>,
        pub atlas: Option<Atlas>,
        pub warp_source: Option<Arc<str>>,
        pub warp: Option<Warp>,
        pub hold: bool,
        pub hold_areas: Vec<(f64, f64, f64)>,
        /// `render.set-hand-tint`'s last colour (none: never set). Kept, not drawn (see `render::set_hand_tint`).
        pub hand_tint: Option<[f32; 3]>,
    }

    thread_local! {
        static STATE: RefCell<State> = RefCell::new(State::default());
    }

    /// The mod's state, for a call or for the glue.
    pub fn with<T>(f: impl FnOnce(&mut State) -> T) -> T {
        STATE.with(|s| f(&mut s.borrow_mut()))
    }
}
