//! Adaptive pacing of a strike's block edits (`world.edit-blocks`) by the game's frame time.
//!
//! Every chunk an edit changes is sent to the client whole, and the client works each one out again (relit, remeshed,
//! uploaded): a wave's cost to the frame follows the chunks it changes a tick, which grows with its radius (a ring's
//! chunks grow with its circumference). The edits wait in order, and each tick lets through as many as a budget
//! allows: none held back while the frames are quick, fewer while they run long (a smoothed frame time well over
//! what it was before the edits began, and over `SLOW`), down to a floor so a strike never stalls. Throttling only
//! stretches the sweep: the edits keep their order, and each goes in whole.

/// A frame this long (smoothed) is slow whatever the frames were like before.
const SLOW: f32 = 0.025;
/// Under this (smoothed) the budget grows back.
const FAST: f32 = 0.018;
/// Slow also means this much over the frames before the edits began (on a machine whose frames are long anyway,
/// the strike's own look, not its edits, would be what makes them long).
const SLOW_OVER_CALM: f32 = 1.4;
const FAST_OVER_CALM: f32 = 1.15;
/// The fewest cost units (`cost`) a tick lets through: the slowest a sweep goes.
pub const FLOOR: u32 = 8;
/// The budget at or over which nothing is held back.
pub const MAX: u32 = 96;
/// How much of the budget a slow tick keeps, and how much a quick one adds back.
const CUT: f32 = 0.7;
const GROW: u32 = MAX / 16;
/// Frames longer than this count as this long (a pause, a window being dragged).
const LONGEST: f32 = 0.2;

/// What an edit costs in budget units: the chunks it changes (each is sent and worked out again whole by the client)
/// and a unit for every 2,048 blocks it touches (the server's share).
pub fn cost(runs: &[horizon_mod_sdk::world::BlockRun]) -> u32 {
    let mut chunks: Vec<(i32, i32)> = runs.iter().map(|r| (r.x >> 4, r.z >> 4)).collect();
    chunks.sort_unstable();
    chunks.dedup();
    let blocks: u64 = runs.iter().map(|r| u64::from(r.height)).sum();
    (chunks.len() as u64 + blocks / 2048).min(u64::from(u32::MAX)) as u32
}

pub struct Pace {
    /// The smoothed frame time, and the same while no edits wait or go in (what the frames are like without them).
    frame: f32,
    calm: f32,
    /// Cost units a tick may let through; `None` while nothing is held back.
    budget: Option<u32>,
    busy: bool,
}

impl Default for Pace {
    fn default() -> Self {
        Self { frame: 1.0 / 60.0, calm: 1.0 / 60.0, budget: None, busy: false }
    }
}

impl Pace {
    /// A frame drawn, `seconds` long.
    pub fn frame(&mut self, seconds: f32) {
        let s = seconds.clamp(0.0, LONGEST);
        self.frame += (s - self.frame) * 0.15;
        if !self.busy {
            self.calm += (s - self.calm) * 0.05;
        }
    }
    /// A tick's budget, `busy` when edits wait or went in on the tick before: `None` for no limit.
    pub fn tick(&mut self, busy: bool) -> Option<u32> {
        self.busy = busy;
        if !busy {
            self.budget = None;
            return None;
        }
        let slow = self.frame > SLOW.max(self.calm * SLOW_OVER_CALM);
        let fast = self.frame < FAST.max(self.calm * FAST_OVER_CALM);
        self.budget = match self.budget {
            _ if slow => Some(((self.budget.unwrap_or(MAX) as f32 * CUT) as u32).max(FLOOR)),
            Some(b) if fast => (b + GROW < MAX).then_some(b + GROW),
            b => b,
        };
        self.budget
    }
    /// How many of `costs` (the waiting edits, in order) go in this tick under `budget`: at least one.
    pub fn release(budget: Option<u32>, costs: impl IntoIterator<Item = u32>) -> usize {
        let Some(budget) = budget else {
            return usize::MAX;
        };
        let mut spent = 0u64;
        let mut n = 0;
        for c in costs {
            if n > 0 && spent + u64::from(c) > u64::from(budget) {
                break;
            }
            spent += u64::from(c);
            n += 1;
        }
        n
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_frames(p: &mut Pace, ms: f32, frames: usize) {
        for _ in 0..frames {
            p.frame(ms / 1000.0);
        }
    }

    #[test]
    fn quick_frames_hold_nothing_back() {
        let mut p = Pace::default();
        run_frames(&mut p, 14.0, 200);
        for _ in 0..100 {
            run_frames(&mut p, 15.0, 3);
            assert_eq!(p.tick(true), None);
        }
        assert_eq!(Pace::release(None, [500, 500, 500]), usize::MAX);
    }

    #[test]
    fn long_frames_cut_the_budget_to_the_floor_and_quick_ones_let_it_back() {
        let mut p = Pace::default();
        run_frames(&mut p, 14.0, 200);
        // (the smoothing takes a few frames to see them)
        run_frames(&mut p, 45.0, 10);
        let mut last = u32::MAX;
        for _ in 0..30 {
            run_frames(&mut p, 45.0, 2);
            let b = p.tick(true).expect("throttled");
            assert!(b <= last && b >= FLOOR);
            last = b;
        }
        assert_eq!(last, FLOOR);
        // as long frames go on, the floor still goes through: the strike never stalls
        assert_eq!(Pace::release(Some(FLOOR), [3, 3, 3, 3]), 2);
        assert_eq!(Pace::release(Some(FLOOR), [500, 1]), 1);
        // quick again: back up, then nothing held back
        let mut ticks = 0;
        while p.tick(true).is_some() {
            run_frames(&mut p, 14.0, 3);
            ticks += 1;
            assert!(ticks < 200);
        }
        assert!(ticks > 5, "{ticks}");
        // no edits: no budget
        run_frames(&mut p, 45.0, 50);
        assert_eq!(p.tick(false), None);
    }

    #[test]
    fn frames_long_before_the_edits_are_not_held_against_them() {
        // a slow machine: 30 ms frames before the strike's edits begin, and as they go in
        let mut p = Pace::default();
        run_frames(&mut p, 30.0, 400);
        for _ in 0..50 {
            run_frames(&mut p, 31.0, 2);
            assert_eq!(p.tick(true), None);
        }
        // but frames much longer than those are
        for _ in 0..20 {
            run_frames(&mut p, 60.0, 2);
            p.tick(true);
        }
        assert_eq!(p.tick(true), Some(FLOOR));
    }

    #[test]
    fn an_edit_costs_its_chunks_and_its_blocks() {
        use horizon_mod_sdk::world::BlockRun;
        let run = |x, z, height| BlockRun { x, z, y: 0, height, surface: None, block: 0, only: None };
        assert_eq!(cost(&[]), 0);
        assert_eq!(cost(&[run(0, 0, 10), run(15, 15, 10), run(16, 0, 10), run(-1, 0, 10)]), 3);
        assert_eq!(cost(&[run(0, 0, 4096)]), 3);
    }
}
