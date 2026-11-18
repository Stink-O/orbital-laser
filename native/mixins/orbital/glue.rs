// Orbital Laser's host: the fork's game/mods.rs (tick_mods, mods_frame, mod_command, show_mod_output,
// draw_mod_panels) for one native mod, driving its SDK (`orbital_laser::horizon_sdk::__host`) through Horizon's
// hooks and helpers, as upstream's mods are made: a client half on the window, which runs the mod, and a server half,
// which does the mod's world work (commands, block edits, height and column reads, the flying speed) in the level
// being ticked, the two talking over mod messages (`orbital:work`, `orbital:answer`).
use super::Game;
use super::native_hooks::{NativeScreenView, NativeShake};
use super::native_claimed_items::{NativeHeldItem, NativeHit, NativeModEvent};
use super::native_world_columns::NativeColumnBlocks;
use super::native_world_edit::{NativeBlockEdit, NativeBlockRun, NativeHeightmap};
use horizon_client::text::{self, Text};
use horizon_client::block_sprites::{BlockSprites, FaceSprite, Lookup, SpriteRef};
use horizon_client::mesher::TintSource;
use orbital_laser::horizon_sdk::{__host as host, atlas, game as g, hud, input, ui, world};
use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, VecDeque};
use std::sync::Mutex;

pub(super) const ID: &str = "orbital";
const NAME: &str = "Orbital Laser";
const VERSION: &str = "0.5.17";
/// The operator level of the console, which the server half runs a client's world work at (`native_run_command`).
const CONSOLE_LEVEL: u8 = 4;
const WORK: &str = "orbital:work";
const ANSWER: &str = "orbital:answer";
/// A message's bytes at most (the channel's 30 000, less room for its header).
const MESSAGE: usize = 28_000;
/// Columns a read or a height query asks in one message (8 bytes each); the answers are split by their own size.
const READ_COLUMNS: usize = 3000;
/// Batches of world work out at once, not yet acknowledged by the server half. Upstream takes at most 32 mod messages
/// from a player a *server* tick and drops the rest in silence (`guest_native_net`), while the window may send 32 a
/// *client* tick: with the server behind (a big strike's chunks generating, ticks of half a second) most of a strike's
/// edits, reads and forceloads were thrown away, whole chunks left uncarved. So no more than this many are ever on
/// their way, whatever the two ticks do (the fork's mod calls the world directly and never lost any).
const WINDOW: usize = 30;
/// No acknowledgement for this long with batches out: the ones not acknowledged go again (the server half takes each
/// once, by its number).
const RESEND_AFTER: std::time::Duration = std::time::Duration::from_secs(4);

thread_local! {
    /// Started (its `init` ran) on this thread: the window's.
    static STARTED: Cell<Option<bool>> = const { Cell::new(None) };
    static TICKS: Cell<u64> = const { Cell::new(0) };
    static CLIENT: RefCell<Client> = RefCell::new(Client::default());
    static SERVER: RefCell<Server> = RefCell::new(Server::default());
}
/// `/orbital …` heard on the server thread (`horizon-ctl command`): the mod runs on the window's.
static SERVER_COMMANDS: Mutex<Vec<String>> = Mutex::new(Vec::new());

// ---- the client half's state ------------------------------------------------------------------------------------

#[derive(Default)]
struct Client {
    /// Work for the server half, in order, as messages.
    out: VecDeque<Vec<u8>>,
    /// Batches sent and not yet acknowledged (number, bytes), oldest first; `resend` of them, from the front, still to
    /// go again; the next batch's number; this session's number (a new one each world, so the server half starts over);
    /// when the last acknowledgement moved on.
    unacked: VecDeque<(u32, Vec<u8>)>,
    resend: usize,
    next_seq: u32,
    epoch: u32,
    progress: Option<std::time::Instant>,
    /// The most requests waiting since the work last caught up, and since when.
    backlog: (usize, Option<std::time::Instant>),
    /// The mod's own screen: open as far as the mod knows, and its clicks and typing not yet polled.
    screen_open: bool,
    screen_events: Vec<input::Event>,
    typed: Vec<input::Typed>,
    /// The keys the mod registered (name, label, default), and the key events not yet polled.
    keys: Vec<[String; 3]>,
    key_events: Vec<input::Event>,
    /// Answers coming back in pieces: surface heights and column reads by tag.
    surface: BTreeMap<u32, (u32, Vec<Option<i32>>, Vec<bool>)>,
    columns: BTreeMap<u32, Columns>,
    /// The flying speed last asked of the server half, and when (ticks).
    fly_sent: Option<(Option<f32>, u64)>,
    /// The camera shake's jolts (the fork's `CameraShake`).
    shake: Shake,
    /// The client level last loaded (`client_level_load`), and whether the world is being left
    /// (`client_level_unload`): the mod's outputs then stay on the window.
    level: Option<String>,
    leaving: bool,
    /// The mod's world warp as it gave it, and on this game's contract (`orbital_post::native_warp_source`).
    warp: Option<(std::sync::Arc<str>, std::sync::Arc<str>)>,
}

/// A column read coming back in pieces.
#[derive(Default)]
struct Columns {
    total: usize,
    got: usize,
    span: usize,
    palette: Vec<String>,
    index: BTreeMap<String, u16>,
    bases: Vec<Option<i32>>,
    blocks: Vec<u16>,
    tints: Vec<u32>,
}

// ---- block textures (the fork's `atlas`) -------------------------------------------------------------------------

fn sprite(s: SpriteRef) -> atlas::Sprite {
    atlas::Sprite { array: s.array, layer: s.layer, animated: s.animated, cutout: s.cutout }
}

fn face(f: &FaceSprite) -> atlas::Face {
    let [a0, b0, a1, b1] = f.rect;
    let [u0, v0, du_u, du_v, dv_u, dv_v] = f.uv;
    atlas::Face {
        sprite: sprite(f.sprite),
        rect: (a0, b0, a1, b1),
        inset: f.inset,
        uv: (u0, v0, du_u, du_v, dv_u, dv_v),
        tint: match f.tint {
            None => atlas::Tint::None,
            Some(TintSource::Grass) => atlas::Tint::Grass,
            Some(TintSource::Foliage) => atlas::Tint::Foliage,
            Some(TintSource::DryFoliage) => atlas::Tint::DryFoliage,
            Some(TintSource::Water) => atlas::Tint::Water,
            Some(TintSource::Fixed(c)) => atlas::Tint::Fixed(c),
        },
        translucent: f.translucent,
    }
}

fn block_faces(b: BlockSprites) -> atlas::BlockFaces {
    atlas::BlockFaces {
        sides: b.sides.iter().map(|side| side.iter().map(face).collect()).collect(),
        particle: b.particle.map(sprite),
        cube: b.cube,
    }
}

/// Gives the mod's SDK its `atlas` lookups over the game's resources as they are now: again when they load anew
/// (`native_block_sprites_version`) or the renderer's split is known, so its answers are what `native_block_sprites`
/// gives. (The mod calls `atlas` synchronously, while the glue holds the game mutably: the lookups own what they read.)
fn sync_atlas(game: &Game<'_>) {
    let split = game.renderer.as_ref().map_or(u32::MAX, |r| r.sprite_split());
    let version = game.native_block_sprites_version();
    thread_local! {
        static GIVEN: Cell<Option<(u64, u32)>> = const { Cell::new(None) };
    }
    if GIVEN.with(Cell::get) == Some((version, split)) {
        return;
    }
    GIVEN.with(|g| g.set(Some((version, split))));
    let context = game.pack.context.clone();
    let textures = context.clone();
    host::with(|s| {
        s.atlas = Some(host::Atlas {
            blocks: std::sync::Arc::new(move |names: &[String]| {
                let lookup = Lookup::new(&context, split);
                names.iter().map(|n| lookup.block(n).map(block_faces)).collect()
            }),
            textures: std::sync::Arc::new(move |names: &[String]| {
                let lookup = Lookup::new(&textures, split);
                names.iter().map(|n| lookup.texture(n).map(sprite)).collect()
            }),
            version,
        })
    });
}

// ---- starting -----------------------------------------------------------------------------------------------------

fn running(game: &mut Game<'_>) -> bool {
    if !game.native_window() || !game.native_on(ID) {
        return false;
    }
    if let Some(on) = STARTED.with(Cell::get) {
        return on;
    }
    let dir = game.native_data_dir(ID);
    host::with(|s| {
        s.id = ID.to_owned();
        s.name = NAME.to_owned();
        s.data_dir = dir;
    });
    sync_atlas(game);
    let on = match (orbital_laser::__EXPORTS.init)() {
        Ok(_) => true,
        Err(e) => {
            log::warn!("mod {ID} did not start: {e}");
            false
        }
    };
    STARTED.with(|s| s.set(Some(on)));
    show_output(game);
    on
}

fn held(h: NativeHeldItem) -> input::HeldItem {
    input::HeldItem {
        id: h.id,
        count: h.count,
        slot: h.slot,
        custom_name: h.custom_name,
        custom_data: h.custom_data,
    }
}
fn hit(h: NativeHit) -> world::Hit {
    world::Hit {
        block_x: h.block_x,
        block_y: h.block_y,
        block_z: h.block_z,
        x: h.x,
        y: h.y,
        z: h.z,
        block: h.block,
    }
}

/// `mod_snapshot` and the events since the last call.
fn snapshot(game: &mut Game<'_>) {
    sync_atlas(game);
    let snapshot = host::Snapshot {
        // (the mod reads where the player is and looks; health and food it doesn't)
        player: game.native_player().map(|p| g::Player {
            x: p.x,
            y: p.y,
            z: p.z,
            yaw: p.yaw,
            pitch: p.pitch,
            health: 20.0,
            food: 20,
            dimension: p.dimension.to_owned(),
        }),
        // The SDK keeps the fork's unsigned clock.
        clock: game.native_clock().map(|c| g::Clock {
            game_time: c.game_time.max(0) as u64,
            day_time: c.day_time.max(0) as u64,
        }),
        // API 9's native_held: the mod only asks the held item's id.
        held: game.native_held().map(|(id, count, _)| input::HeldItem {
            id,
            count,
            slot: game.selected as u32,
            custom_name: None,
            custom_data: None,
        }),
        view_hit: game.native_view_hit().map(|(d, h)| (d, hit(h))),
        // (the fork's `world.carry-player` answer and `game.player-flying`)
        carried: horizon_client::orbital_carry::carried(),
        flying: game.player.as_ref().is_some_and(|p| p.flying || p.spectator),
    };
    let mut events: Vec<input::Event> = game
        .native_poll(ID)
        .into_iter()
        .map(|e| match e {
            NativeModEvent::UseStart(item, ticks) => input::Event::UseStart(input::ItemUse { item: held(item), ticks }),
            NativeModEvent::UseStop(item, ticks) => input::Event::UseStop(input::ItemUse { item: held(item), ticks }),
        })
        .collect();
    // the mod's screen closed by the game (Escape, another screen): `screen-closed`, as the fork's
    let shown = game.native_mod_screen() == Some(ID);
    let typed = CLIENT.with(|c| {
        let mut c = c.borrow_mut();
        if c.screen_open && !shown {
            c.screen_open = false;
            c.screen_events.push(input::Event::ScreenClosed);
        }
        events.extend(std::mem::take(&mut c.key_events));
        events.append(&mut c.screen_events);
        std::mem::take(&mut c.typed)
    });
    let cursor = shown.then(|| {
        let [cx, cy] = gui_centre(game);
        let [x, y] = game.native_cursor();
        ui::Point { x: x - cx, y: y - cy }
    });
    host::with(|s| {
        s.snapshot = snapshot;
        // (`screen_closed`: the game closed the mod's screen)
        if events.iter().any(|e| *e == input::Event::ScreenClosed) {
            s.screen = None;
            s.typed.clear();
        }
        s.events.extend(events);
        s.typed.extend(typed);
        s.cursor = cursor;
    });
}

fn heightmap(h: world::Heightmap) -> u8 {
    match h {
        world::Heightmap::WorldSurface => 1,
        world::Heightmap::MotionBlocking => 2,
        world::Heightmap::MotionBlockingNoLeaves => 3,
        world::Heightmap::OceanFloor => 4,
    }
}
fn heightmap_of(h: u8) -> Option<NativeHeightmap> {
    Some(match h {
        1 => NativeHeightmap::WorldSurface,
        2 => NativeHeightmap::MotionBlocking,
        3 => NativeHeightmap::MotionBlockingNoLeaves,
        4 => NativeHeightmap::OceanFloor,
        _ => return None,
    })
}
/// The middle of the GUI, in GUI pixels: the origin of the fork's `ui.draw` and `ui.cursor`.
fn gui_centre(game: &Game<'_>) -> [f32; 2] {
    let size = game.renderer.as_ref().map_or([1, 1], |r| [r.config.width, r.config.height]);
    let b = horizon_client::hud::HudBatch::new(size);
    [b.width / 2.0, b.height / 2.0]
}

/// `show_mod_output`, and the state the mod keeps (claims, keys, post pass, flying speed).
fn show_output(game: &mut Game<'_>) {
    let (out, claims, keys, post, params, data, screen, fly) = host::with(|s| {
        (
            std::mem::take(&mut s.out),
            s.claims.clone(),
            s.keys.clone(),
            s.post_source.clone(),
            s.post_params,
            s.post_data.clone(),
            s.screen.is_some(),
            s.flying_speed,
        )
    });
    let out_opened = out.iter().any(|o| *o == host::Output::Screen { open: true });
    let leaving = CLIENT.with(|c| c.borrow().leaving);
    for output in out {
        match output {
            host::Output::Sound { event, at, volume, pitch } => {
                // (as the fork's `show_mod_output`: at a point, or with none, relative to the listener without
                // attenuation, so a strike's own sounds stay with the player as they move)
                if game.native_window() {
                    game.audio.play(&event, at, volume, pitch);
                }
            }
            // (leaving the world: the strike's sounds stopped here, nothing sent to the closing server)
            host::Output::Commands { commands } if leaving => {
                for event in commands.iter().filter_map(|c| c.strip_prefix("stopsound @s * ")) {
                    game.audio.stop_sounds(Some(event.trim()), None);
                }
            }
            host::Output::Edit { .. } | host::Output::Surface { .. } | host::Output::Columns { .. } if leaving => {}
            host::Output::Commands { commands } => send_commands(&commands),
            // (without the content the join hint (`/orbital give`) has nothing to give: the notice takes its place)
            host::Output::Chat { text: t, .. } if t.starts_with("Type /orbital give") && no_content(game) => {}
            host::Output::Chat { name, text: t } => {
                let mut line = Text::literal(format!("[{name}] ")).with_color(text::GRAY);
                line.push(Text::literal(t));
                chat(game, line);
            }
            host::Output::Keys => {}
            host::Output::Edit { edit } => send_edit(&edit),
            host::Output::Surface { tag, columns, heightmap: h } => send_surface(tag, &columns, heightmap(h)),
            host::Output::Columns { tag, columns, heightmap: h, below, above } => {
                send_columns(tag, &columns, heightmap(h), below, above)
            }
            host::Output::Shake { strength, seconds } => {
                let now = (game.ticks as f64) / 20.0;
                CLIENT.with(|c| c.borrow_mut().shake.add(now, strength, seconds));
            }
            // (a push while a carry holds them is its throw: what they are let go with)
            host::Output::Push { velocity } => {
                if !horizon_client::orbital_carry::push(velocity) {
                    game.native_push_player(velocity);
                }
            }
            // (made in the player's own tick: `carry.rs`)
            host::Output::Carry { delta, turn } => horizon_client::orbital_carry::ask(delta, turn),
            host::Output::Screen { open: false } => {
                game.native_mod_screen_close(ID);
                CLIENT.with(|c| c.borrow_mut().screen_open = false);
            }
            host::Output::Screen { open: true } => {}
        }
    }
    if screen {
        // (`ui.show` opens it, or keeps it open; the hooks draw it from the mod's draws each frame)
        let open = if out_opened { game.native_mod_screen_open(ID) } else { game.native_mod_screen() == Some(ID) };
        if open {
            CLIENT.with(|c| c.borrow_mut().screen_open = true);
        } else if out_opened {
            // another screen is up: the mod's doesn't open, and the mod hears it closed
            CLIENT.with(|c| c.borrow_mut().screen_events.push(input::Event::ScreenClosed));
            host::with(|s| {
                s.screen = None;
                s.typed.clear();
            });
        } else {
            // The game closed it (`screen_closed`): the mod hears ScreenClosed on its next poll.
            host::with(|s| {
                s.screen = None;
                s.typed.clear();
            });
        }
    }
    sync_flying_speed(game, fly);
    game.native_claim_items(ID, &claims);
    CLIENT.with(|c| {
        c.borrow_mut().keys = keys.iter().map(|k| [k.name.clone(), k.label.clone(), k.key.clone()]).collect();
    });
    let day_time = game.native_clock().map_or(0, |c| c.day_time.max(0) as u64);
    let pass = match (post, params) {
        (Some((source, version)), Some(params)) => Some(horizon_client_render::orbital_post::Pass {
            source,
            version,
            params,
            data,
            day_time,
        }),
        _ => None,
    };
    horizon_client_render::orbital_post::set(pass);
    // (the Fold's world warp: its source put on this game's contract once a source, `post.rs`)
    let (warp_source, warp_on) = host::with(|s| (s.warp_source.clone(), s.warp.is_some()));
    let warp = warp_source.map(|fork| {
        CLIENT.with(|c| {
            let mut c = c.borrow_mut();
            match &c.warp {
                Some((from, native)) if std::sync::Arc::ptr_eq(from, &fork) => native.clone(),
                _ => {
                    let native: std::sync::Arc<str> = std::sync::Arc::from(horizon_client_render::orbital_post::native_warp_source(&fork));
                    c.warp = Some((fork, native.clone()));
                    native
                }
            }
        })
    });
    horizon_client_render::orbital_post::set_warp(warp.map(|w| (w, warp_on)));
}

/// The fork's `world.set-flying-speed`: asked of the server half when it changed, or again while the window's
/// player hasn't got it (a new world comes with vanilla's), at most once a second.
fn sync_flying_speed(game: &mut Game<'_>, want: Option<f32>) {
    let ticks = game.ticks;
    let have = game.player.as_ref().map(|p| p.flying_speed);
    let spectator = game.player.as_ref().is_some_and(|p| p.spectator);
    CLIENT.with(|c| {
        let mut c = c.borrow_mut();
        let differs = match want {
            Some(s) => !spectator && have.is_some_and(|h| h != s),
            None => c.fly_sent.is_some_and(|(w, _)| w.is_some()) && have.is_some_and(|h| h != 0.05),
        };
        let changed = c.fly_sent.is_none_or(|(w, _)| w != want);
        let waiting = c.fly_sent.is_some_and(|(_, t)| ticks < t + 20);
        if (changed && (want.is_some() || c.fly_sent.is_some())) || (differs && !waiting) {
            let mut w = Writer::new(4);
            w.f32(want.unwrap_or(f32::NAN));
            c.out.push_back(w.0);
            c.fly_sent = Some((want, ticks));
        }
    });
}

/// A line in chat, not through system_message (a mod must not hear its own lines).
fn chat(game: &mut Game<'_>, line: Text) {
    let focused = game.screen == super::Screen::Chat;
    game.ui.chat.add(
        &game.gui.atlas,
        line,
        None,
        horizon_client::chat::ChatSource::Client,
        game.ticks,
        focused,
    );
}

// ---- the wire: requests (kind 0-4) and answers (10, 11) ----------------------------------------------------------

struct Writer(Vec<u8>);
impl Writer {
    fn new(kind: u8) -> Self {
        Self(vec![kind])
    }
    fn u32(&mut self, v: u32) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    fn i32(&mut self, v: i32) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    fn f32(&mut self, v: f32) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    fn str(&mut self, s: &str) {
        self.u32(s.len() as u32);
        self.0.extend_from_slice(s.as_bytes());
    }
    fn strs(&mut self, v: &[String]) {
        self.u32(v.len() as u32);
        for s in v {
            self.str(s);
        }
    }
}
struct Reader<'a>(&'a [u8]);
impl Reader<'_> {
    fn take(&mut self, n: usize) -> Option<&[u8]> {
        if self.0.len() < n {
            return None;
        }
        let (a, b) = self.0.split_at(n);
        self.0 = b;
        Some(a)
    }
    fn u8(&mut self) -> Option<u8> {
        self.take(1).map(|b| b[0])
    }
    fn u32(&mut self) -> Option<u32> {
        self.take(4).map(|b| u32::from_le_bytes(b.try_into().unwrap()))
    }
    fn u16(&mut self) -> Option<u16> {
        self.take(2).map(|b| u16::from_le_bytes(b.try_into().unwrap()))
    }
    fn i16(&mut self) -> Option<i16> {
        self.take(2).map(|b| i16::from_le_bytes(b.try_into().unwrap()))
    }
    fn i32(&mut self) -> Option<i32> {
        self.take(4).map(|b| i32::from_le_bytes(b.try_into().unwrap()))
    }
    fn f32(&mut self) -> Option<f32> {
        self.take(4).map(|b| f32::from_le_bytes(b.try_into().unwrap()))
    }
    fn str(&mut self) -> Option<String> {
        let n = self.u32()? as usize;
        self.take(n).and_then(|b| String::from_utf8(b.to_vec()).ok())
    }
    fn strs(&mut self) -> Option<Vec<String>> {
        let n = self.u32()? as usize;
        (0..n).map(|_| self.str()).collect()
    }
    fn columns(&mut self) -> Option<Vec<(i32, i32)>> {
        let n = self.u32()? as usize;
        (0..n).map(|_| Some((self.i32()?, self.i32()?))).collect()
    }
}

fn send(message: Vec<u8>) {
    CLIENT.with(|c| c.borrow_mut().out.push_back(message));
}
/// Commands, as many to a message as fit.
fn send_commands(commands: &[String]) {
    let mut lines: Vec<&String> = Vec::new();
    let flush = |lines: &mut Vec<&String>| {
        let mut w = Writer::new(0);
        w.u32(lines.len() as u32);
        for l in lines.drain(..) {
            w.str(l);
        }
        send(w.0);
    };
    let mut size = 0;
    for line in commands {
        if !lines.is_empty() && size + line.len() + 4 > MESSAGE {
            flush(&mut lines);
            size = 0;
        }
        size += line.len() + 4;
        lines.push(line);
    }
    if !lines.is_empty() {
        flush(&mut lines);
    }
}
/// A block edit, its runs split over as many messages as they need, each with the palette and filters. A message's
/// runs go packed (kind 5: 13 bytes a run, x and z from the message's first run's) when they fit, else whole (kind 1:
/// 25 bytes): the world work is what the channel's 32 messages a server tick carry, so the fewer bytes the better.
fn send_edit(edit: &world::BlockEdit) {
    let head = 9 + 8 + edit.palette.iter().chain(&edit.filters).map(|s| s.len() + 4).sum::<usize>();
    let mut start = 0;
    while start < edit.runs.len() {
        let room = MESSAGE.saturating_sub(head);
        // as many runs as fit packed, while they pack
        let (x0, z0) = (edit.runs[start].x, edit.runs[start].z);
        let packs = |r: &world::BlockRun| {
            i16::try_from(i64::from(r.x) - i64::from(x0)).is_ok()
                && i16::try_from(i64::from(r.z) - i64::from(z0)).is_ok()
                && i16::try_from(r.y).is_ok()
                && u16::try_from(r.height).is_ok()
                && u16::try_from(r.block).is_ok()
                && r.only.is_none_or(|o| o < i16::MAX as u32)
        };
        let mut n = 0;
        while start + n < edit.runs.len() && (n + 1) * 13 <= room && packs(&edit.runs[start + n]) {
            n += 1;
        }
        let packed = n > 0;
        if !packed {
            n = (room / 25).max(1).min(edit.runs.len() - start);
        }
        let runs = &edit.runs[start..start + n];
        let mut w = Writer::new(if packed { 5 } else { 1 });
        w.strs(&edit.palette);
        w.strs(&edit.filters);
        w.u32(runs.len() as u32);
        if packed {
            w.i32(x0);
            w.i32(z0);
        }
        for r in runs {
            if packed {
                w.0.extend_from_slice(&((r.x - x0) as i16).to_le_bytes());
                w.0.extend_from_slice(&((r.z - z0) as i16).to_le_bytes());
                w.0.extend_from_slice(&(r.y as i16).to_le_bytes());
                w.0.extend_from_slice(&(r.height as u16).to_le_bytes());
                w.0.push(r.surface.map_or(0, heightmap));
                w.0.extend_from_slice(&(r.block as u16).to_le_bytes());
                w.0.extend_from_slice(&r.only.map_or(-1i16, |o| o as i16).to_le_bytes());
            } else {
                w.i32(r.x);
                w.i32(r.z);
                w.i32(r.y);
                w.u32(r.height);
                w.0.push(r.surface.map_or(0, heightmap));
                w.u32(r.block);
                w.i32(r.only.map_or(-1, |o| o as i32));
            }
        }
        send(w.0);
        start += n;
    }
}
fn send_surface(tag: u32, columns: &[(i32, i32)], h: u8) {
    for (i, part) in columns.chunks(READ_COLUMNS).enumerate() {
        let mut w = Writer::new(2);
        w.u32(tag);
        w.0.push(h);
        w.u32((i * READ_COLUMNS) as u32);
        w.u32(columns.len() as u32);
        w.u32(part.len() as u32);
        for &(x, z) in part {
            w.i32(x);
            w.i32(z);
        }
        send(w.0);
    }
    if columns.is_empty() {
        let mut w = Writer::new(2);
        w.u32(tag);
        w.0.push(h);
        w.u32(0);
        w.u32(0);
        w.u32(0);
        send(w.0);
    }
}
fn send_columns(tag: u32, columns: &[(i32, i32)], h: u8, below: u32, above: u32) {
    let parts: Vec<&[(i32, i32)]> = if columns.is_empty() { vec![&[]] } else { columns.chunks(READ_COLUMNS).collect() };
    for (i, part) in parts.into_iter().enumerate() {
        let mut w = Writer::new(3);
        w.u32(tag);
        w.0.push(h);
        w.u32(below);
        w.u32(above);
        w.u32((i * READ_COLUMNS) as u32);
        w.u32(columns.len() as u32);
        w.u32(part.len() as u32);
        for &(x, z) in part {
            w.i32(x);
            w.i32(z);
        }
        send(w.0);
    }
}

/// A new session's number for the batches (not 0).
fn new_epoch() -> u32 {
    let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(1, |d| d.subsec_nanos() ^ d.as_secs() as u32);
    t.max(1)
}

/// The client half: the work waiting goes to the server half, as much as the channel takes this tick and no more than
/// `WINDOW` batches unacknowledged, the requests packed into as few messages as they fit (a message, kind 9: the
/// session, the batch's number, then requests, each its length then its bytes). Batches not acknowledged within
/// `RESEND_AFTER` go again first.
fn flush_work(game: &mut Game<'_>) {
    CLIENT.with(|c| {
        let mut c = c.borrow_mut();
        let c = &mut *c;
        if c.epoch == 0 {
            c.epoch = new_epoch();
        }
        let now = std::time::Instant::now();
        if c.unacked.is_empty() {
            c.progress = Some(now);
        } else if c.resend == 0 && c.progress.is_some_and(|t| now.duration_since(t) > RESEND_AFTER) {
            log::info!(
                "[mod {ID}] world work: no answer from the server half for {} s, {} batches sent again",
                RESEND_AFTER.as_secs(),
                c.unacked.len()
            );
            c.resend = c.unacked.len();
            c.progress = Some(now);
        }
        // the ones to go again
        while c.resend > 0 {
            let i = c.unacked.len() - c.resend;
            if game.native_net_send_to_server(WORK, &c.unacked[i].1).is_err() {
                return;
            }
            c.resend -= 1;
        }
        // (how far the world work fell behind the server half, said once it has caught up)
        if c.out.len() > c.backlog.0 {
            c.backlog = (c.out.len(), c.backlog.1.or(Some(now)));
        }
        if c.out.is_empty() && c.unacked.is_empty() {
            if let (n, Some(since)) = c.backlog
                && n >= 64
            {
                log::info!(
                    "[mod {ID}] world work: up to {n} requests waited for the server half, caught up after {:.1} s",
                    now.duration_since(since).as_secs_f32()
                );
            }
            c.backlog = (0, None);
        }
        while !c.out.is_empty() && c.unacked.len() < WINDOW {
            let mut batch = vec![9u8];
            batch.extend_from_slice(&c.epoch.to_le_bytes());
            batch.extend_from_slice(&c.next_seq.to_le_bytes());
            let mut taken = 0;
            for m in c.out.iter() {
                if taken > 0 && batch.len() + 4 + m.len() > MESSAGE {
                    break;
                }
                batch.extend_from_slice(&(m.len() as u32).to_le_bytes());
                batch.extend_from_slice(m);
                taken += 1;
            }
            if let Err(e) = game.native_net_send_to_server(WORK, &batch) {
                if c.out.len() > 512 {
                    static SAID: std::sync::Once = std::sync::Once::new();
                    SAID.call_once(|| log::warn!("[mod {ID}] world work waiting: {e}"));
                }
                break;
            }
            c.out.drain(..taken);
            c.unacked.push_back((c.next_seq, batch));
            c.next_seq = c.next_seq.wrapping_add(1);
        }
    });
}

/// The `net_from_server` hook: answers from the server half.
pub(super) fn from_server(game: &mut Game<'_>, channel: &str, data: &[u8]) {
    if channel != ANSWER || !game.native_window() {
        return;
    }
    let mut r = Reader(data);
    let Some(kind) = r.u8() else { return };
    let done = CLIENT.with(|c| -> Option<()> {
        let mut c = c.borrow_mut();
        match kind {
            10 => {
                let (tag, offset, total) = (r.u32()?, r.u32()? as usize, r.u32()? as usize);
                let n = r.u32()? as usize;
                let entry = c.surface.entry(tag).or_insert_with(|| (tag, vec![None; total], vec![false; total]));
                for i in 0..n {
                    let has = r.u8()?;
                    let h = r.i32()?;
                    if let Some(slot) = entry.1.get_mut(offset + i) {
                        *slot = (has == 1).then_some(h);
                        entry.2[offset + i] = true;
                    }
                }
                if entry.2.iter().all(|&b| b) {
                    let (_, heights, _) = c.surface.remove(&tag)?;
                    host::with(|s| s.surface.push(world::SurfaceHeights { tag, heights }));
                }
            }
            11 => {
                let (tag, offset, total, span) = (r.u32()?, r.u32()? as usize, r.u32()? as usize, r.u32()? as usize);
                let palette = r.strs()?;
                let n = r.u32()? as usize;
                let entry = c.columns.entry(tag).or_insert_with(|| Columns {
                    total,
                    span,
                    bases: vec![None; total],
                    blocks: vec![0; total * span],
                    tints: vec![0; total * 3],
                    ..Columns::default()
                });
                // this piece's palette, as indexes into the whole answer's
                let map: Vec<u16> = palette
                    .into_iter()
                    .map(|name| {
                        if let Some(&i) = entry.index.get(&name) {
                            return i;
                        }
                        let i = entry.palette.len() as u16;
                        entry.palette.push(name.clone());
                        entry.index.insert(name, i);
                        i
                    })
                    .collect();
                for i in 0..n {
                    let k = offset + i;
                    let has = r.u8()?;
                    let base = r.i32()?;
                    if k < entry.total {
                        entry.bases[k] = (has == 1).then_some(base);
                    }
                    for j in 0..entry.span {
                        let b = r.u16()? as usize;
                        if k < entry.total {
                            entry.blocks[k * entry.span + j] = map.get(b).copied().unwrap_or(0);
                        }
                    }
                    for t in 0..3 {
                        let v = r.u32()?;
                        if k < entry.total {
                            entry.tints[k * 3 + t] = v;
                        }
                    }
                }
                entry.got += n;
                if entry.got >= entry.total {
                    let e = c.columns.remove(&tag)?;
                    host::with(|s| {
                        s.columns.push(world::ColumnBlocks {
                            tag,
                            palette: e.palette,
                            bases: e.bases,
                            blocks: e.blocks,
                            tints: e.tints,
                        })
                    });
                }
            }
            12 => {
                // the server half has served every batch before `next` of session `epoch`
                let (epoch, next) = (r.u32()?, r.u32()?);
                if epoch == c.epoch {
                    let before = c.unacked.len();
                    while c.unacked.front().is_some_and(|&(seq, _)| next.wrapping_sub(seq) as i32 > 0) {
                        c.unacked.pop_front();
                    }
                    let gone = before - c.unacked.len();
                    if gone > 0 {
                        c.resend = c.resend.min(c.unacked.len());
                        c.progress = Some(std::time::Instant::now());
                    }
                }
            }
            _ => {}
        }
        Some(())
    });
    if done.is_none() {
        log::warn!("[mod {ID}] a bad answer from the server half");
    }
}

// ---- the server half ----------------------------------------------------------------------------------------------

#[derive(Default)]
struct Server {
    /// Each player's requests, in the order they came.
    work: BTreeMap<u128, VecDeque<Vec<u8>>>,
    /// Answers waiting for the channel, by player.
    answers: BTreeMap<u128, VecDeque<Vec<u8>>>,
    /// Each player's session and the number of the next batch to serve: a batch is served once, in order (one out of
    /// order, past one that was lost, waits to come again).
    next: BTreeMap<u128, (u32, u32)>,
    /// The acknowledgements still to go (the channel was full), by player.
    acks: BTreeMap<u128, (u32, u32)>,
    /// Edits for chunks not loaded yet, by (dimension, chunk), oldest first: upstream's edit-blocks leaves out runs in
    /// chunks not loaded, and a strike holding thousands of chunks (the Supervolcano, past upstream's 4,096) has the
    /// server so far behind that its edits came before their land. They go in as each chunk comes.
    waiting: BTreeMap<(String, i32, i32), Waiting>,
    /// Chunks that waited since the last time none did, and the longest wait (s).
    waited: (usize, f32),
}

/// A chunk's edits waiting for it, since when, and whether its ticket goes once they are in.
struct Waiting {
    since: std::time::Instant,
    edits: Vec<NativeBlockEdit>,
    release: bool,
}
/// How long a chunk's edits wait for it before they are given up; and how long one loaded waits for its neighbours
/// (whose loading lights it).
const WAIT_MOST: std::time::Duration = std::time::Duration::from_secs(120);
const WAIT_NEIGHBOURS: std::time::Duration = std::time::Duration::from_secs(10);
/// Waiting chunks put in a tick at most.
const WAIT_PER_TICK: usize = 96;

/// Whether chunk `(cx, cz)` of `dimension` takes edits now: loaded, its neighbours too (or it has waited long enough).
fn chunk_ready(game: &Game<'_>, dimension: &str, cx: i32, cz: i32, since: Option<std::time::Instant>) -> bool {
    if !game.native_chunk_is_loaded(dimension, [cx, cz]) {
        return false;
    }
    if since.is_some_and(|t| t.elapsed() > WAIT_NEIGHBOURS) {
        return true;
    }
    (-1..=1).all(|dz| (-1..=1).all(|dx| (dx == 0 && dz == 0) || game.native_chunk_is_loaded(dimension, [cx + dx, cz + dz])))
}

/// An edit: its runs in chunks ready go in now, the rest wait for their chunks (behind any edits already waiting there).
fn edit_or_wait(game: &mut Game<'_>, dimension: &str, edit: NativeBlockEdit) {
    let mut by_chunk: BTreeMap<(i32, i32), Vec<NativeBlockRun>> = BTreeMap::new();
    for r in edit.runs {
        by_chunk.entry((r.x >> 4, r.z >> 4)).or_default().push(r);
    }
    let mut now = Vec::new();
    for ((cx, cz), runs) in by_chunk {
        let key = (dimension.to_owned(), cx, cz);
        let queued = SERVER.with(|s| s.borrow().waiting.contains_key(&key));
        if !queued && chunk_ready(game, dimension, cx, cz, None) {
            now.extend(runs);
            continue;
        }
        let part = NativeBlockEdit { palette: edit.palette.clone(), filters: edit.filters.clone(), runs, ..Default::default() };
        SERVER.with(|s| {
            s.borrow_mut()
                .waiting
                .entry(key)
                .or_insert_with(|| Waiting { since: std::time::Instant::now(), edits: Vec::new(), release: false })
                .edits
                .push(part)
        });
    }
    if !now.is_empty() {
        let edit = NativeBlockEdit { palette: edit.palette, filters: edit.filters, runs: now, ..Default::default() };
        if let Err(e) = game.native_edit_blocks(dimension, &edit) {
            log::warn!("[mod {ID}] edit-blocks left out: {e}");
        }
    }
}

/// The edits waiting in `dimension` whose chunks have come go in (the oldest first, `WAIT_PER_TICK` chunks at most), and
/// those waiting past `WAIT_MOST` are given up; a chunk's ticket a strike let go of goes once its edits are done.
fn edits_waiting(game: &mut Game<'_>, dimension: &str) {
    let keys: Vec<((String, i32, i32), std::time::Instant)> = SERVER.with(|s| {
        let s = s.borrow();
        let mut k: Vec<_> = s.waiting.iter().filter(|(k, _)| k.0 == dimension).map(|(k, w)| (k.clone(), w.since)).collect();
        k.sort_by_key(|(_, t)| *t);
        k
    });
    if keys.is_empty() {
        return;
    }
    let (mut put, mut lost) = (0, 0);
    for (key, since) in keys {
        let expired = since.elapsed() > WAIT_MOST;
        if !expired && (put >= WAIT_PER_TICK || !chunk_ready(game, dimension, key.1, key.2, Some(since))) {
            continue;
        }
        let Some(w) = SERVER.with(|s| s.borrow_mut().waiting.remove(&key)) else { continue };
        if expired {
            lost += 1;
        } else {
            put += 1;
            for e in &w.edits {
                if let Err(err) = game.native_edit_blocks(dimension, e) {
                    log::warn!("[mod {ID}] edit-blocks left out: {err}");
                }
            }
            SERVER.with(|s| {
                let mut s = s.borrow_mut();
                s.waited.0 += 1;
                s.waited.1 = s.waited.1.max(since.elapsed().as_secs_f32());
            });
        }
        if w.release {
            game.native_force_chunk_in(TICKET, dimension, [key.1, key.2], false);
        }
    }
    if lost > 0 {
        log::warn!("[mod {ID}] world work: the edits of {lost} chunks given up, their land not loaded in {} s", WAIT_MOST.as_secs());
    }
    let done = SERVER.with(|s| {
        let mut s = s.borrow_mut();
        if s.waiting.is_empty() && s.waited.0 > 0 {
            Some(std::mem::take(&mut s.waited))
        } else {
            None
        }
    });
    if let Some((n, most)) = done {
        log::info!("[mod {ID}] world work: the edits of {n} chunks waited for their land, up to {most:.1} s");
    }
}

/// The `net_from_client` hook: a player's request, kept for the tick of their level.
pub(super) fn from_client(game: &mut Game<'_>, player: u128, channel: &str, data: &[u8]) {
    if channel != WORK || game.native_window() || !game.native_on(ID) {
        return;
    }
    SERVER.with(|s| s.borrow_mut().work.entry(player).or_default().push_back(data.to_vec()));
}

fn uuid(u: u128) -> String {
    let h = format!("{u:032x}");
    format!("{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32])
}

/// The `level_tick_post` hook: the requests of the players in this level, in order, and the answers that fit.
pub(super) fn level_tick(game: &mut Game<'_>, dimension: &str) {
    if game.native_window() || !game.native_on(ID) {
        return;
    }
    edits_waiting(game, dimension);
    let players = game.native_server_players();
    let mine: Vec<(u128, u8)> =
        players.iter().filter(|p| p.dimension == dimension).map(|p| (p.uuid, p.permission)).collect();
    for (player, permission) in mine {
        let work = SERVER.with(|s| s.borrow_mut().work.remove(&player)).unwrap_or_default();
        // (what a client sends is its own input, and it runs as the console: only a player at the console's level, who
        // can already run anything, as the fork ran them for the owner)
        if permission < CONSOLE_LEVEL {
            if !work.is_empty() {
                static SAID: std::sync::Once = std::sync::Once::new();
                SAID.call_once(|| {
                    log::warn!("[mod {ID}] world work from {} left out: not a level {CONSOLE_LEVEL} operator", uuid(player))
                });
            }
            continue;
        }
        let had = !work.is_empty();
        for batch in work {
            let mut r = Reader(&batch);
            let (Some(9), Some(epoch), Some(seq)) = (r.u8(), r.u32(), r.u32()) else {
                log::warn!("[mod {ID}] a bad message from {}", uuid(player));
                continue;
            };
            let take = SERVER.with(|s| {
                let mut s = s.borrow_mut();
                let next = s.next.entry(player).or_insert((epoch, 0));
                if next.0 != epoch {
                    *next = (epoch, 0);
                }
                if next.1 == seq {
                    next.1 = seq.wrapping_add(1);
                    true
                } else {
                    // (past the one expected: one before it was lost on the way; it comes again)
                    if (seq.wrapping_sub(next.1) as i32) > 0 {
                        static SAID: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
                        if SAID.fetch_add(1, std::sync::atomic::Ordering::Relaxed) < 8 {
                            log::warn!("[mod {ID}] world work: batch {seq} came before {}, which was lost on the way", next.1);
                        }
                    }
                    false
                }
            });
            if !take {
                continue;
            }
            while let Some(n) = r.u32() {
                let Some(request) = r.take(n as usize) else { break };
                if serve(game, player, dimension, request).is_none() {
                    log::warn!("[mod {ID}] a bad request from {}", uuid(player));
                }
            }
        }
        if had {
            SERVER.with(|s| {
                let mut s = s.borrow_mut();
                if let Some(&n) = s.next.get(&player) {
                    s.acks.insert(player, n);
                }
            });
        }
    }
    // acknowledgements first (kind 12: the session, the next batch to serve), so the window's work keeps coming
    let acks: Vec<(u128, (u32, u32))> = SERVER.with(|s| s.borrow().acks.iter().map(|(&p, &n)| (p, n)).collect());
    for (player, (epoch, next)) in acks {
        let mut w = Writer::new(12);
        w.u32(epoch);
        w.u32(next);
        if game.native_net_send_to_player(player, ANSWER, &w.0).is_ok() {
            SERVER.with(|s| s.borrow_mut().acks.remove(&player));
        }
    }
    // answers leave as the channel allows, the rest next tick
    let ids: Vec<u128> = SERVER.with(|s| s.borrow().answers.keys().copied().collect());
    for player in ids {
        loop {
            let Some(m) = SERVER.with(|s| s.borrow_mut().answers.get_mut(&player).and_then(|q| q.pop_front())) else {
                break;
            };
            if m.len() > 30_000 {
                log::warn!("[mod {ID}] an answer of {} bytes left out", m.len());
                continue;
            }
            if let Err(e) = game.native_net_send_to_player(player, ANSWER, &m) {
                log::debug!("[mod {ID}] answers waiting: {e}");
                SERVER.with(|s| s.borrow_mut().answers.entry(player).or_default().push_front(m));
                break;
            }
        }
    }
    SERVER.with(|s| s.borrow_mut().answers.retain(|_, q| !q.is_empty()));
}

fn answer(player: u128, message: Vec<u8>) {
    SERVER.with(|s| s.borrow_mut().answers.entry(player).or_default().push_back(message));
}

/// What holds the chunks a strike keeps loaded (`native_force_chunk_in`'s owner).
const TICKET: &str = "orbital:strike";

/// A strike's `forceload add|remove X0 Z0 X1 Z1` (or `execute in DIMENSION run` it), made as chunk tickets: upstream's
/// `/forceload add` waits on the server thread until its chunks are loaded (a9c7b82, as vanilla), and a strike's few
/// hundred of them over land not yet generated held one tick for half a minute, the game frozen behind it. Tickets
/// load the same chunks over the ticks that follow, as the fork's forceload did. Whether the line was one.
fn force_load(game: &mut Game<'_>, dimension: &str, line: &str) -> bool {
    let (dim, rest) = match line.strip_prefix("execute in ") {
        Some(r) => match r.split_once(" run ") {
            Some((d, rest)) => (d, rest),
            None => return false,
        },
        None => (dimension, line),
    };
    let w: Vec<&str> = rest.split_whitespace().collect();
    let hold = match w.as_slice() {
        ["forceload", "add", ..] => true,
        ["forceload", "remove", ..] => false,
        _ => return false,
    };
    let n: Vec<i32> = w[2..].iter().filter_map(|v| v.parse().ok()).collect();
    let (x0, z0, x1, z1) = match n.as_slice() {
        [x, z] if w.len() == 4 => (*x, *z, *x, *z),
        [a, b, c, d] if w.len() == 6 => (*a, *b, *c, *d),
        _ => return false,
    };
    let (cx0, cx1, cz0, cz1) = (x0.min(x1) >> 4, x0.max(x1) >> 4, z0.min(z1) >> 4, z0.max(z1) >> 4);
    // (as /forceload refuses more than 256 chunks a line)
    if i64::from(cx1 - cx0 + 1) * i64::from(cz1 - cz0 + 1) > 256 {
        return false;
    }
    for cx in cx0..=cx1 {
        for cz in cz0..=cz1 {
            // (a chunk whose edits still wait for it keeps its ticket until they are in)
            let waits = SERVER.with(|s| {
                let mut s = s.borrow_mut();
                match s.waiting.get_mut(&(dim.to_owned(), cx, cz)) {
                    Some(w) => {
                        w.release = !hold;
                        !hold
                    }
                    None => false,
                }
            });
            if !waits {
                game.native_force_chunk_in(TICKET, dim, [cx, cz], hold);
            }
        }
    }
    true
}

fn serve(game: &mut Game<'_>, player: u128, dimension: &str, request: &[u8]) -> Option<()> {
    let mut r = Reader(request);
    match r.u8()? {
        0 => {
            // as the player, where they are, silently: the fork ran them from the player's source
            let who = uuid(player);
            for line in r.strs()? {
                let line = line.trim_start_matches('/');
                if force_load(game, dimension, line) {
                    continue;
                }
                game.native_run_command(&format!("execute as {who} at @s run {line}"));
            }
        }
        kind @ (1 | 5) => {
            let palette = r.strs()?;
            let filters = r.strs()?;
            let n = r.u32()? as usize;
            let mut runs = Vec::with_capacity(n);
            if kind == 5 {
                let (x0, z0) = (r.i32()?, r.i32()?);
                for _ in 0..n {
                    let (dx, dz, y, height) = (r.i16()?, r.i16()?, r.i16()?, r.u16()?);
                    let surface = heightmap_of(r.u8()?);
                    let block = r.u16()?;
                    let only = r.i16()?;
                    runs.push(NativeBlockRun {
                        x: x0.wrapping_add(i32::from(dx)),
                        z: z0.wrapping_add(i32::from(dz)),
                        y: i32::from(y),
                        height: u32::from(height),
                        surface,
                        block: u32::from(block),
                        only: u32::try_from(only).ok(),
                    });
                }
            }
            for _ in 0..if kind == 1 { n } else { 0 } {
                let (x, z, y, height) = (r.i32()?, r.i32()?, r.i32()?, r.u32()?);
                let surface = heightmap_of(r.u8()?);
                let block = r.u32()?;
                let only = r.i32()?;
                runs.push(NativeBlockRun { x, z, y, height, surface, block, only: u32::try_from(only).ok() });
            }
            edit_or_wait(game, dimension, NativeBlockEdit { palette, filters, runs, ..Default::default() });
        }
        2 => {
            let (tag, h, offset, total) = (r.u32()?, r.u8()?, r.u32()?, r.u32()?);
            let columns = r.columns()?;
            let heights = game
                .native_surface_heights(dimension, &columns, heightmap_of(h)?)
                .unwrap_or_else(|_| vec![None; columns.len()]);
            for (k, part) in heights.chunks(MESSAGE / 5).enumerate() {
                let mut w = Writer::new(10);
                w.u32(tag);
                w.u32(offset + (k * (MESSAGE / 5)) as u32);
                w.u32(total);
                w.u32(part.len() as u32);
                for h in part {
                    w.0.push(u8::from(h.is_some()));
                    w.i32(h.unwrap_or(0));
                }
                answer(player, w.0);
            }
        }
        3 => {
            let (tag, h, below, above, offset, total) = (r.u32()?, r.u8()?, r.u32()?, r.u32()?, r.u32()?, r.u32()?);
            let columns = r.columns()?;
            let span = (below + above) as usize;
            let read = game
                .native_read_columns(dimension, &columns, heightmap_of(h)?, (below, above))
                .unwrap_or_else(|_| NativeColumnBlocks {
                    bases: vec![None; columns.len()],
                    blocks: vec![0; columns.len() * span],
                    tints: vec![0; columns.len() * 3],
                    ..NativeColumnBlocks::default()
                });
            let palette_bytes: usize = read.palette.iter().map(|p| p.len() + 4).sum();
            let per = ((MESSAGE.saturating_sub(palette_bytes + 32)) / (5 + 2 * span + 12)).max(1);
            for start in (0..columns.len()).step_by(per) {
                let end = (start + per).min(columns.len());
                let mut w = Writer::new(11);
                w.u32(tag);
                w.u32(offset + start as u32);
                w.u32(total);
                w.u32(span as u32);
                w.strs(&read.palette);
                w.u32((end - start) as u32);
                for i in start..end {
                    let base = read.bases.get(i).copied().flatten();
                    w.0.push(u8::from(base.is_some()));
                    w.i32(base.unwrap_or(0));
                    for j in 0..span {
                        w.0.extend_from_slice(&read.blocks.get(i * span + j).copied().unwrap_or(0).to_le_bytes());
                    }
                    for t in 0..3 {
                        w.u32(read.tints.get(i * 3 + t).copied().unwrap_or(0));
                    }
                }
                answer(player, w.0);
            }
        }
        4 => {
            let speed = r.f32()?;
            game.native_set_flying_speed(player, speed.is_finite().then_some(speed));
        }
        _ => return None,
    }
    Some(())
}

// ---- the camera shake: the fork's `CameraShake` (render.shake), handed to `native_camera_shake` -------------------

#[derive(Default)]
struct Shake {
    /// (start, seconds, strength), in seconds of game ticks.
    jolts: Vec<(f64, f32, f32)>,
}
/// The most the view turns at full strength: pitch, yaw and roll, in degrees.
const SHAKE_DEGREES: [f32; 3] = [3.2, 3.6, 2.4];
impl Shake {
    fn add(&mut self, now: f64, strength: f32, seconds: f32) {
        self.jolts.retain(|&(start, secs, _)| now - start < f64::from(secs));
        if self.jolts.len() < 64 {
            self.jolts.push((now, seconds, strength.clamp(0.0, 1.0)));
        }
    }
    fn trauma(&self, now: f64) -> f32 {
        let sum: f32 = self
            .jolts
            .iter()
            .map(|&(start, secs, strength)| {
                let u = ((now - start) as f32 / secs).clamp(0.0, 1.0);
                let left = strength * (1.0 - u) * (1.0 - u);
                if now >= start { left * left } else { 0.0 }
            })
            .sum();
        sum.sqrt().min(1.0)
    }
    /// The turn in degrees (pitch, yaw, roll) at `now`, before Distortion Effects (Horizon scales the shake).
    fn turn(&self, now: f64) -> Option<[f32; 3]> {
        let amount = self.trauma(now).powi(2);
        if amount <= 0.0 {
            return None;
        }
        let t = now as f32;
        let slow = 1.0 - 0.35 * amount;
        let axis = |k: f32| {
            (shake_noise(t * 2.1 * slow + k * 17.3) * 0.55
                + shake_noise(t * 6.3 * slow + k * 31.7) * 0.35
                + shake_noise(t * 13.0 + k * 53.1) * 0.1)
                * 1.6
        };
        let [p, y, r] = SHAKE_DEGREES;
        Some([axis(0.0) * p * amount, axis(1.0) * y * amount, axis(2.0) * r * amount])
    }
}
fn shake_noise(x: f32) -> f32 {
    let grad = |i: f32| {
        let h = (i * 127.1).sin() * 43_758.547;
        (h - h.floor()) * 2.0 - 1.0
    };
    let i = x.floor();
    let f = x - i;
    let u = f * f * (3.0 - 2.0 * f);
    let a = grad(i) * f;
    let b = grad(i + 1.0) * (f - 1.0);
    a + (b - a) * u
}

/// The `camera_shake` hook.
pub(super) fn camera_shake(game: &Game<'_>, partial: f32, shake: &mut NativeShake) {
    if !game.native_window() {
        return;
    }
    let now = (game.ticks as f64 + f64::from(partial)) / 20.0;
    if let Some([p, y, r]) = CLIENT.with(|c| c.borrow().shake.turn(now)) {
        shake.pitch += p;
        shake.yaw += y;
        shake.roll += r;
    }
}

// ---- the hooks ----------------------------------------------------------------------------------------------------

/// The `mods` hook: the mod's row on Options > Mods, with its keys (the wheel's), which the player rebinds there.
pub(super) fn mods(game: &mut Game<'_>, mods: &mut Vec<super::native_hooks::NativeMod>) {
    // (started here, so its keys are known when the page is first drawn)
    running(game);
    mods.push(super::native_hooks::NativeMod {
        id: ID.to_owned(),
        title: format!("{NAME} {VERSION}"),
        description: if no_content(game) {
            NO_CONTENT.to_owned()
        } else {
            "Call down an orbital strike that drills a crater to bedrock.".to_owned()
        },
        keys: CLIENT.with(|c| c.borrow().keys.clone()),
    });
}
/// The `key` hook: a key the player pressed or released, while playing, for the mod's keys bound to it.
pub(super) fn key(game: &mut Game<'_>, key: &str, pressed: bool) {
    if !running(game) || game.screen != super::Screen::Playing || game.title.is_some() {
        return;
    }
    let keys = CLIENT.with(|c| c.borrow().keys.clone());
    for [name, _, default] in keys {
        if game.native_mod_key(ID, &name, &default) == key {
            let event = if pressed { input::Event::KeyDown(name) } else { input::Event::KeyUp(name) };
            CLIENT.with(|c| c.borrow_mut().key_events.push(event));
        }
    }
}
pub(super) fn tick(game: &mut Game<'_>) {
    if !running(game) {
        return;
    }
    warn_no_content(game);
    let heard: Vec<String> = SERVER_COMMANDS.lock().map(|mut c| std::mem::take(&mut *c)).unwrap_or_default();
    for c in heard {
        run_command(game, &c);
    }
    horizon_client::orbital_carry::untaken();
    snapshot(game);
    let ticks = TICKS.with(|t| {
        t.set(t.get() + 1);
        t.get()
    });
    (orbital_laser::__EXPORTS.tick)(ticks);
    show_output(game);
    flush_work(game);
}

pub(super) fn frame(game: &mut Game<'_>, elapsed: std::time::Duration) {
    if STARTED.with(Cell::get) != Some(true) || !game.native_window() {
        return;
    }
    carry_look(game, elapsed.as_secs_f32());
    (orbital_laser::__EXPORTS.frame)(elapsed.as_secs_f32());
    show_output(game);
}

/// A carry turns the view (degrees a tick), spread over the frames so it turns smoothly; a long frame (a hitch) turns
/// it no more than a tenth of a second's worth.
fn carry_look(game: &mut Game<'_>, seconds: f32) {
    let turn = horizon_client::orbital_carry::turn();
    if turn != 0.0 && game.screen == super::Screen::Playing && game.player.is_some() {
        game.yaw += turn * seconds.min(0.1) * 20.0;
    }
}

/// `/orbital …`: true when it is the mod's.
pub(super) fn command(game: &mut Game<'_>, command: &str) -> bool {
    let line = command.trim_start_matches('/');
    if line != ID && !line.starts_with("orbital ") {
        return false;
    }
    if !game.native_window() {
        return from_owner(game, line);
    }
    if !running(game) {
        return false;
    }
    // (without the content there is no Designator to give: say why, rather than a give that fails)
    if line.strip_prefix(ID).unwrap_or("").trim_start().starts_with("give") && no_content(game) {
        chat(game, Text::literal(NO_CONTENT).with_color(text::RED));
        return true;
    }
    run_command(game, line);
    true
}

fn run_command(game: &mut Game<'_>, line: &str) {
    // The command may follow a teleport in the same tick.
    snapshot(game);
    let args = line.strip_prefix(ID).unwrap_or("").trim_start();
    match (orbital_laser::__EXPORTS.command)(ID, args) {
        Ok(Some(t)) => chat(game, Text::literal(t)),
        Ok(None) => {}
        Err(t) => chat(game, Text::literal(t).with_color(text::RED)),
    }
    show_output(game);
}

/// `draw_mod_panels`.
pub(super) fn hud(
    game: &mut Game<'_>,
    batch: &mut horizon_client::hud::HudBatch,
    corners: &mut horizon_client::extras_hud::Corners,
) {
    if STARTED.with(Cell::get) != Some(true) || !game.native_window() {
        return;
    }
    let Some((corner, lines)) = host::with(|s| s.panel.clone()) else {
        return;
    };
    use horizon_client::extras::Corner;
    let corner = match corner {
        hud::Corner::TopLeft => Corner::TopLeft,
        hud::Corner::TopRight => Corner::TopRight,
        hud::Corner::BottomLeft => Corner::BottomLeft,
        hud::Corner::BottomRight => Corner::BottomRight,
    };
    // F3 takes the top left, as it does from the extras.
    if game.debug && corner == Corner::TopLeft {
        return;
    }
    let lines: Vec<(&str, u32)> = lines.iter().map(|l| (l.text.as_str(), l.color)).collect();
    horizon_client::extras_hud::draw_lines(batch, &game.gui.atlas, corners, corner, &lines);
}

// ---- the mod's screen on the screen hooks (#5543) ----------------------------------------------------------------

/// Whether `screen` is this mod's own.
fn mine(game: &Game<'_>, screen: &NativeScreenView<'_>) -> bool {
    screen.id == "mod" && game.native_mod_screen() == Some(ID)
}

/// The `screen_render_post` hook: the mod's draws (`ui.show`), from the screen's centre.
pub(super) fn screen_render_post(
    game: &Game<'_>,
    batch: &mut horizon_client::hud::HudBatch,
    screen: &NativeScreenView<'_>,
) {
    if screen.id == "title" && game.native_window() && game.native_on(ID) && no_content(game) {
        // (on the title screen, before a world: the two lines of the notice at the top, centred)
        for (i, line) in NO_CONTENT_LINES.iter().enumerate() {
            let x = ((batch.width - game.native_text_width(line)) / 2.0).floor();
            game.native_text(batch, line, [x, 4.0 + 11.0 * i as f32], 0xFF5555, true);
        }
    }
    if !mine(game, screen) {
        return;
    }
    let Some(draws) = host::with(|s| s.screen.clone()) else {
        return;
    };
    let (cx, cy) = (batch.width / 2.0, batch.height / 2.0);
    for d in &draws {
        match d {
            ui::Draw::Fill((r, c)) => game.native_fill(batch, [cx + r.x, cy + r.y, r.w, r.h], *c),
            ui::Draw::Quad((p, c)) if p.len() >= 4 => {
                game.native_quad(batch, std::array::from_fn(|i| [cx + p[i].x, cy + p[i].y]), *c)
            }
            ui::Draw::Quad(_) => {}
            ui::Draw::Sprite((name, r, _)) => {
                let [w, h] = game.native_sprite_size(name).unwrap_or([r.w, r.h]);
                game.native_sprite(batch, name, [0.0, 0.0, w, h], [cx + r.x, cy + r.y, r.w, r.h]);
            }
            ui::Draw::Item((item, model, at, scale)) => {
                let at = [cx + at.x, cy + at.y];
                if model.is_empty() {
                    game.native_item(batch, item, at, 16.0 * scale);
                } else {
                    game.native_item_model(batch, item, model, at, 16.0 * scale);
                }
            }
            ui::Draw::Text((text, at, c, centred)) => {
                let x = if *centred { cx + at.x - (game.native_text_width(text) / 2.0).floor() } else { cx + at.x };
                game.native_text(batch, text, [x, cy + at.y], *c, true);
            }
        }
    }
}

/// The `screen_mouse_button_pressed_pre` hook: a click on the mod's screen, from its centre (`screen-click`).
pub(super) fn screen_click(game: &Game<'_>, screen: &NativeScreenView<'_>, button: i32, canceled: &mut bool) {
    if !mine(game, screen) || !(0..=2).contains(&button) {
        return;
    }
    let [cx, cy] = gui_centre(game);
    let [x, y] = screen.mouse;
    let click = input::Click { x: x - cx, y: y - cy, button: button as u32 };
    CLIENT.with(|c| c.borrow_mut().screen_events.push(input::Event::ScreenClick(click)));
    *canceled = true;
}

/// The `screen_key_pressed_pre` hook: a key on the mod's screen is its name for `input.poll-typed` when it types no
/// text (Backspace, Enter, the arrows: the character hook gives the rest); Escape stays the game's and closes it.
pub(super) fn screen_key(game: &Game<'_>, screen: &NativeScreenView<'_>, key: &str, canceled: &mut bool) {
    if !mine(game, screen) || key == "key.keyboard.escape" {
        return;
    }
    let name = key.strip_prefix("key.keyboard.").unwrap_or(key);
    let types_text = name.chars().count() == 1 || name == "space" || name.starts_with("keypad.") && name.len() == 8;
    if !types_text {
        CLIENT.with(|c| c.borrow_mut().typed.push(input::Typed::Key(key.to_owned())));
    }
    *canceled = true;
}

/// The `screen_char_typed_pre` hook: a character typed on the mod's screen.
pub(super) fn screen_char(game: &Game<'_>, screen: &NativeScreenView<'_>, c: char, canceled: &mut bool) {
    if !mine(game, screen) {
        return;
    }
    CLIENT.with(|cl| cl.borrow_mut().typed.push(input::Typed::Text(c.to_string())));
    *canceled = true;
}

// ---- the command tree --------------------------------------------------------------------------------------------

/// `/orbital`'s usages, as the mod's own help gives them (`Orbital::command`): in the server's command tree, so the
/// chat box colours and completes them as the game's own (the window's `command` hook still runs them).
const USAGES: &[&str] = &[
    "orbital",
    "orbital give",
    "orbital wheel",
    "orbital stop",
    "orbital skip <seconds:number>",
    "orbital terrain on",
    "orbital terrain off",
    "orbital hud on",
    "orbital hud off",
    "orbital quality full",
    "orbital quality fast",
    "orbital impactframes kanada",
    "orbital impactframes blackflash",
    "orbital impactframes cinematic",
    "orbital impactframes on",
    "orbital impactframes off",
    "orbital knockback on",
    "orbital knockback off",
    "orbital carryview turn",
    "orbital carryview still",
    "orbital follow on",
    "orbital follow off",
    "orbital follow distance <blocks:number>",
    "orbital seed <seed:integer>",
    "orbital seed lock",
    "orbital seed random",
    "orbital payloadsound main",
    "orbital payloadsound alt",
    "orbital nukesound main",
    "orbital nukesound alt",
    "orbital flyspeed <speed:number>",
    "orbital flyspeed reset",
    "orbital approach ahead",
    "orbital approach behind",
    "orbital approach left",
    "orbital approach right",
    "orbital approach overhead",
    "orbital arrival snap",
    "orbital arrival unfold",
    "orbital arrival warp",
    "orbital colour green",
    "orbital colour red",
    "orbital colour amber",
    "orbital colour blue",
    "orbital colour violet",
    "orbital colour white",
    "orbital plasma",
    "orbital godly",
    "orbital blackhole",
    "orbital meteor",
    "orbital mothership",
    "orbital downfall",
    "orbital planetkiller",
    "orbital crystalbloom",
    "orbital sinkhole",
    "orbital payload",
    "orbital nuke",
    "orbital rod",
    "orbital supercell",
    "orbital hurricane",
    "orbital tsunami",
    "orbital fold",
    "orbital foldpattern a",
    "orbital foldpattern b",
    "orbital foldpattern c",
    "orbital supervolcano",
];

/// The `register_commands` hook: `/orbital` and its usages in the server's command tree.
pub(super) fn register_commands(game: &mut Game<'_>, commands: &mut Vec<crate::mod_api::NativeCommand>) {
    if game.native_on(ID) {
        commands.extend(USAGES.iter().map(|u| crate::mod_api::NativeCommand::op(u, CONSOLE_LEVEL)));
    }
}

// ---- leaving the world ---------------------------------------------------------------------------------------------

/// The `client_level_load` hook: the level the window loaded last (another dimension's is loaded before the old one
/// is let go).
pub(super) fn client_level_load(_game: &mut Game<'_>, dimension: &str) {
    CLIENT.with(|c| c.borrow_mut().level = Some(dimension.to_owned()));
}

/// The `client_level_unload` hook: the window let go of the level it loaded last, so the world is being left (not
/// another dimension's level taking its place). The strike ends as `/orbital left-world` ends it (its sounds stopped
/// here, the server closing), the world work still waiting is dropped, and every sound stops, as vanilla's disconnect
/// stops them.
pub(super) fn client_level_unload(game: &mut Game<'_>, dimension: &str) {
    let left = CLIENT.with(|c| {
        let mut c = c.borrow_mut();
        let left = c.level.as_deref() == Some(dimension);
        if left {
            c.level = None;
        }
        left
    });
    if !left || !game.native_window() {
        return;
    }
    if STARTED.with(Cell::get) == Some(true) {
        CLIENT.with(|c| c.borrow_mut().leaving = true);
        if let Err(e) = (orbital_laser::__EXPORTS.command)(ID, "left-world") {
            log::warn!("[mod {ID}] left-world: {e}");
        }
        show_output(game);
        CLIENT.with(|c| {
            let mut c = c.borrow_mut();
            c.leaving = false;
            c.out.clear();
            c.unacked.clear();
            c.resend = 0;
            c.next_seq = 0;
            c.epoch = new_epoch();
            c.surface.clear();
            c.columns.clear();
        });
        horizon_client::orbital_carry::reset();
    }
    game.audio.stop_all();
}

/// The `perform_command` hook: `/orbital` reaching the server through its command tree (the owner's console,
/// `horizon-ctl command`), handed to the window as the `command` hook hands it.
pub(super) fn perform_command(game: &mut Game<'_>, command: &str, ran: &mut bool) {
    let line = command.trim_start_matches('/');
    if *ran || game.native_window() || (line != ID && !line.starts_with("orbital ")) {
        return;
    }
    *ran = from_owner(game, line);
}

/// `/orbital …` heard on the server: for the window, which runs the mod, when the owner sent it (a guest's own window
/// runs theirs, and one without the mod has none: it must not change the host's game). The owner's console runs inside
/// the owner's own player swap, so `lan_acting` alone doesn't tell them from a guest. True when it was the owner's.
fn from_owner(game: &Game<'_>, line: &str) -> bool {
    if let Some(conn) = game.lan_acting {
        let sender = game.lan.as_ref().and_then(|l| l.hub.guest(conn)).map(|g| g.uuid);
        if sender.is_none() || sender != game.serving.as_ref().map(|s| s.owner) {
            return false;
        }
    }
    if let Ok(mut c) = SERVER_COMMANDS.lock() {
        c.push(line.to_owned());
    }
    true
}

// ---- the content ---------------------------------------------------------------------------------------------------

/// On the native build the content (`orbital`: the Designator, its models, textures and sounds) is a mod of its own,
/// which a player may leave out.
const NO_CONTENT: &str =
    "Orbital Laser: its content isn't installed. Install \"Orbital Laser (content)\" from the launcher's Mods page.";
const NO_CONTENT_LINES: [&str; 2] =
    ["Orbital Laser: its content isn't installed.", "Install \"Orbital Laser (content)\" from the launcher's Mods page."];

/// The content isn't loaded: no content mod `orbital` among the ones the game loaded (a world that had the Designator
/// before still knows its id, so the item's id says nothing).
fn no_content(_game: &Game<'_>) -> bool {
    !horizon_protocol::mod_list::local().iter().any(|m| m.id == ID)
}

/// In a world without the content: the notice in chat, once a session.
fn warn_no_content(game: &mut Game<'_>) {
    thread_local! {
        static WARNED: Cell<bool> = const { Cell::new(false) };
    }
    if WARNED.with(Cell::get) || game.native_player().is_none() || !no_content(game) {
        return;
    }
    WARNED.with(|w| w.set(true));
    chat(game, Text::literal(NO_CONTENT).with_color(text::RED));
}

/// `native_world_hold`: the mod's `render.hold-world` and `hold-world-within`. The fork's circles narrow the hold
/// (only the sections in them go on waiting; none given: all of them), so the game is asked for exactly those.
pub(super) fn world_hold(game: &Game<'_>, hold: &mut horizon_client::mod_api::WorldHold) {
    if !game.native_window() {
        return;
    }
    let (on, areas) = host::with(|s| (s.hold, s.hold_areas.clone()));
    if !on {
        return;
    }
    if areas.is_empty() {
        hold.hold();
    } else {
        for (x, z, r) in areas {
            hold.hold_within(x, z, r);
        }
    }
}
