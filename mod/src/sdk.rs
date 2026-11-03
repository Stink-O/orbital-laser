//! The game's mod interfaces the strike's playback calls: the SDK's own in the mod, and in the tests (which run
//! natively, where the SDK's calls into the game don't exist) a stand-in world that records what is asked of it and
//! answers the reads when a test says (`fake`), so the tests can play strikes through lib.rs's own playback.
#[cfg(not(test))]
pub use horizon_mod_sdk::{atlas, game, log, render, storage, world};
#[cfg(test)]
pub use fake::{atlas, game, log, render, storage, world};

#[cfg(test)]
pub mod fake {
    use std::cell::RefCell;

    /// What the playback asked of the world, and what it will be told.
    #[derive(Default)]
    pub struct Fake {
        pub hit: Option<horizon_mod_sdk::world::Hit>,
        pub player: Option<horizon_mod_sdk::game::Player>,
        pub clock: u64,
        /// The reads asked and not yet answered: (tag, columns, below, above), and the surveys: (tag, columns).
        pub reads: Vec<(u32, Vec<(i32, i32)>, u32, u32)>,
        pub surveys: Vec<(u32, Vec<(i32, i32)>)>,
        /// The answers the next polls hand over.
        pub columns: Vec<horizon_mod_sdk::world::ColumnBlocks>,
        pub heights: Vec<horizon_mod_sdk::world::SurfaceHeights>,
        /// Edits made (and their runs), commands run.
        pub edits: u64,
        pub runs: u64,
        pub commands: u64,
        /// The forceload commands run (the stress test loads the chunks they name a while later).
        pub forceloads: Vec<String>,
        /// Every command run, while a test asks for them (`keep_commands`).
        pub keep_commands: bool,
        pub ran: Vec<String>,
        /// The kicks given the player (`push-player`).
        pub pushes: u64,
        pub logs: Vec<String>,
        /// The mod's storage (`storage`), key to value.
        pub stored: std::collections::HashMap<String, Vec<u8>>,
    }
    thread_local! {
        pub static FAKE: RefCell<Fake> = RefCell::new(Fake::default());
    }
    pub fn with<R>(f: impl FnOnce(&mut Fake) -> R) -> R {
        FAKE.with(|w| f(&mut w.borrow_mut()))
    }

    pub mod game {
        pub use horizon_mod_sdk::game::*;
        pub fn get_player() -> Option<Player> {
            super::with(|w| w.player.clone())
        }
        pub fn get_clock() -> Option<Clock> {
            super::with(|w| Some(Clock { game_time: w.clock, day_time: 6000 }))
        }
    }
    pub mod log {
        pub use horizon_mod_sdk::log::*;
        pub fn write(_level: Level, message: &str) {
            super::with(|w| w.logs.push(message.to_string()));
        }
    }
    pub mod storage {
        pub fn get(key: &str) -> Option<Vec<u8>> {
            super::with(|w| w.stored.get(key).cloned())
        }
        pub fn set(key: &str, value: &[u8]) -> Result<(), String> {
            super::with(|w| w.stored.insert(key.to_string(), value.to_vec()));
            Ok(())
        }
        pub fn delete(key: &str) {
            super::with(|w| w.stored.remove(key));
        }
    }
    pub mod render {
        #[allow(unused_imports)]
        pub use horizon_mod_sdk::render::*;
        pub fn set_post(_wgsl: &str) {}
        pub fn set_params(_params: &[f32]) {}
        pub fn clear_post() {}
        pub fn set_data(_words: &[u32]) {}
        pub fn shake(_strength: f32, _seconds: f32) {}
    }
    /// The block sprites, as tools/hu_atlas.py describes them from the player's prepared resources (`HU_ATLAS_JSON`:
    /// for each block its sides' faces), so the tests and the preview's table use real layers; none without it.
    pub mod atlas {
        pub use horizon_mod_sdk::atlas::*;
        use std::collections::HashMap;
        thread_local! {
            static TABLE: std::cell::RefCell<Option<HashMap<String, BlockFaces>>> = const { std::cell::RefCell::new(None) };
        }
        fn load() -> HashMap<String, BlockFaces> {
            let Ok(path) = std::env::var("HU_ATLAS_JSON") else { return HashMap::new() };
            let text = std::fs::read_to_string(path).expect("HU_ATLAS_JSON");
            // (a line a block: name, then six sides each `|`-separated faces `layer,cutout,tint,u0,v0,duu,duv,dvu,dvv`
            // joined by `;`)
            let mut out = HashMap::new();
            for line in text.lines() {
                let mut parts = line.split('|');
                let Some(name) = parts.next() else { continue };
                let sides: Vec<Vec<Face>> = parts
                    .map(|side| {
                        side.split(';')
                            .filter(|f| !f.is_empty())
                            .map(|f| {
                                let v: Vec<&str> = f.split(',').collect();
                                let n = |i: usize| v[i].parse::<f32>().unwrap_or(0.0);
                                let tint = match v[2] {
                                    "grass" => Tint::Grass,
                                    "foliage" => Tint::Foliage,
                                    "water" => Tint::Water,
                                    t if t.starts_with('#') => Tint::Fixed(u32::from_str_radix(&t[1..], 16).unwrap_or(0xFFFFFF)),
                                    _ => Tint::None,
                                };
                                Face {
                                    // (`1` cut out, `2` translucent)
                                    sprite: Sprite { array: 0, layer: v[0].parse().unwrap_or(0), animated: false, cutout: v[1] == "1" },
                                    rect: (0.0, 0.0, 1.0, 1.0),
                                    inset: 0.0,
                                    uv: (n(3), n(4), n(5), n(6), n(7), n(8)),
                                    tint,
                                    translucent: v[1] == "2",
                                }
                            })
                            .collect()
                    })
                    .collect();
                out.insert(name.to_string(), BlockFaces { sides, particle: None, cube: true });
            }
            out
        }
        pub fn block_sprites(names: &[String]) -> Vec<Option<BlockFaces>> {
            TABLE.with(|t| {
                let mut t = t.borrow_mut();
                let t = t.get_or_insert_with(load);
                names.iter().map(|n| t.get(n).cloned()).collect()
            })
        }
        pub fn resources_version() -> u64 {
            1
        }
    }
    pub mod world {
        pub use horizon_mod_sdk::world::*;
        pub fn raycast(_distance: f32) -> Option<Hit> {
            super::with(|w| w.hit.clone())
        }
        pub fn run_commands(commands: &[String]) {
            super::with(|w| {
                w.commands += commands.len() as u64;
                w.forceloads.extend(commands.iter().filter(|c| c.starts_with("forceload")).cloned());
                if w.keep_commands {
                    w.ran.extend(commands.iter().cloned());
                }
            });
        }
        pub fn play_sound(_event: &str, _at: Option<(f64, f64, f64)>, _volume: f32, _pitch: f32) {}
        pub fn push_player(_x: f32, _y: f32, _z: f32) {
            super::with(|w| w.pushes += 1);
        }
        pub fn carry_player(_x: f32, _y: f32, _z: f32) -> bool {
            super::with(|w| w.pushes += 1);
            true
        }
        pub fn edit_blocks(edit: &BlockEdit) {
            super::with(|w| {
                w.edits += 1;
                w.runs += edit.runs.len() as u64;
            });
        }
        pub fn surface_height(tag: u32, columns: &[(i32, i32)], _heightmap: Heightmap) {
            super::with(|w| w.surveys.push((tag, columns.to_vec())));
        }
        pub fn poll_surface_heights() -> Vec<SurfaceHeights> {
            super::with(|w| std::mem::take(&mut w.heights))
        }
        pub fn read_columns(tag: u32, columns: &[(i32, i32)], _heightmap: Heightmap, below: u32, above: u32) {
            super::with(|w| w.reads.push((tag, columns.to_vec(), below, above)));
        }
        pub fn poll_columns() -> Vec<ColumnBlocks> {
            super::with(|w| std::mem::take(&mut w.columns))
        }
    }
}
