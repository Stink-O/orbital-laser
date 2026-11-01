//! The game's mod interfaces the strike's playback calls: the SDK's own in the mod, and in the tests (which run
//! natively, where the SDK's calls into the game don't exist) a stand-in world that records what is asked of it and
//! answers the reads when a test says (`fake`), so the tests can play strikes through lib.rs's own playback.
#[cfg(not(test))]
pub use horizon_mod_sdk::{game, log, render, world};
#[cfg(test)]
pub use fake::{game, log, render, world};

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
        pub logs: Vec<String>,
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
    pub mod render {
        #[allow(unused_imports)]
        pub use horizon_mod_sdk::render::*;
        pub fn set_post(_wgsl: &str) {}
        pub fn set_params(_params: &[f32]) {}
        pub fn clear_post() {}
        pub fn set_data(_words: &[u32]) {}
        pub fn shake(_strength: f32, _seconds: f32) {}
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
            });
        }
        pub fn play_sound(_event: &str, _at: Option<(f64, f64, f64)>, _volume: f32, _pitch: f32) {}
        pub fn push_player(_x: f32, _y: f32, _z: f32) {}
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
