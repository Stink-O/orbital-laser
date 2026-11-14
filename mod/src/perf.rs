//! `/orbital perf on|off` (not kept): one log line a second of a strike with what the mod asked of the game in it, for
//! the in-game benchmark (`game_bench.sh`): block edits (batches, runs, blocks, chunks touched), commands by kind
//! (summons of falling blocks, fills, forceloads, the rest), column reads and surveys, the meter's busiest tick, and
//! the queues left waiting. Counting is a few additions a call; the chunks an edit touches are only worked out while
//! it is on.
use std::cell::{Cell, RefCell};

#[derive(Default, Clone, Copy)]
pub struct Counts {
    pub edits: u64,
    pub runs: u64,
    pub blocks: u64,
    pub chunks: u64,
    pub cmds: u64,
    pub summon: u64,
    pub fill: u64,
    pub forceload: u64,
    pub clone: u64,
    pub tp: u64,
    pub reads: u64,
    pub read_cols: u64,
    pub surveys: u64,
    pub meter_max: u64,
    pub busiest_edit_chunks: u64,
}

thread_local! {
    static ON: Cell<bool> = const { Cell::new(false) };
    static C: RefCell<Counts> = RefCell::new(Counts::default());
}

pub fn set(on: bool) {
    ON.with(|o| o.set(on));
    take();
}
pub fn on() -> bool {
    ON.with(Cell::get)
}
fn with(f: impl FnOnce(&mut Counts)) {
    if on() {
        C.with(|c| f(&mut c.borrow_mut()));
    }
}
pub fn take() -> Counts {
    C.with(|c| std::mem::take(&mut *c.borrow_mut()))
}

pub fn commands(cmds: &[String]) {
    with(|c| {
        c.cmds += cmds.len() as u64;
        for s in cmds {
            // (through any `execute ... run`)
            let k = s.rsplit(" run ").next().unwrap_or(s).trim_start_matches('/');
            if k.starts_with("summon") {
                c.summon += 1;
            } else if k.starts_with("fill") {
                c.fill += 1;
            } else if k.starts_with("forceload") {
                c.forceload += 1;
            } else if k.starts_with("clone") {
                c.clone += 1;
            } else if k.starts_with("tp") || k.starts_with("teleport") {
                c.tp += 1;
            }
        }
    });
}
pub fn edit(runs: &[horizon_mod_sdk::world::BlockRun]) {
    with(|c| {
        c.edits += 1;
        c.runs += runs.len() as u64;
        c.blocks += runs.iter().map(|r| u64::from(r.height)).sum::<u64>();
        let mut ch: Vec<(i32, i32)> = runs.iter().map(|r| (r.x >> 4, r.z >> 4)).collect();
        ch.sort_unstable();
        ch.dedup();
        c.chunks += ch.len() as u64;
        c.busiest_edit_chunks = c.busiest_edit_chunks.max(ch.len() as u64);
    });
}
pub fn read(columns: usize) {
    with(|c| {
        c.reads += 1;
        c.read_cols += columns as u64;
    });
}
pub fn survey() {
    with(|c| c.surveys += 1);
}
pub fn tick_spent(spent: u64) {
    with(|c| c.meter_max = c.meter_max.max(spent));
}

thread_local! {
    static WARP: Cell<bool> = const { Cell::new(false) };
}
/// Whether the World Eater's world warp is now `on` when it was not (or the other way).
pub fn warp_changed(on: bool) -> bool {
    WARP.with(|w| w.replace(on) != on)
}
