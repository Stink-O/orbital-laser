//! A cheap meter of the work one call into the mod does, so no call comes near the game's fuel limit (a tick may run
//! some 50 million WebAssembly instructions, a frame 10 million; past that the game stops the mod for good: "it took too
//! long"). The mod can't read its fuel, so the loops that do the heavy work count what they do (`spend`, in
//! instructions, roughly: the columns a stage visits, the runs it makes, the blocks of an answer it takes in, the runs
//! an edit hands the game), and everything that can wait asks `full` before it starts: a stage not worked out, the
//! next job of one not begun, an edit or a command left for the next tick. The meter is reset as each call begins.
//! However heavy a path turns out to be, the strike then goes more slowly instead of the mod being stopped.
//!
//! The figures are set from the game's own count (`mod_soak` in the fork measures every call's fuel; `/orbital meter`
//! logs the meter's): they read high rather than low.
use std::cell::Cell;

/// Instructions a call may spend before what can wait waits: under a third of a tick's fuel, so a meter that reads
/// low on some land, or one job that runs over, still leaves the call well under the limit.
pub const SOFT: u64 = 16_000_000;
/// The edits due go in up to this (`lib.rs`'s `edit`): past what the stages may spend, so the edits already worked out
/// keep going in on time while a stage takes its share.
pub const EDITS: u64 = 22_000_000;
/// The most a tick spends at all on what can wait (the first of each kind of work goes in even past `SOFT`, so a strike
/// never stalls, but not past this).
pub const HARD: u64 = 28_000_000;

thread_local! {
    static SPENT: Cell<u64> = const { Cell::new(0) };
    static PEAK: Cell<(u64, u64)> = const { Cell::new((0, 0)) };
}

/// A call into the mod begins.
pub fn reset() {
    SPENT.with(|s| s.set(0));
}
/// `n` instructions' worth of work done.
#[inline]
pub fn spend(n: u64) {
    SPENT.with(|s| s.set(s.get().saturating_add(n)));
}
/// What this call has spent.
pub fn spent() -> u64 {
    SPENT.with(Cell::get)
}
/// Whether what can wait should wait for the next call.
pub fn full() -> bool {
    spent() >= SOFT
}
/// Whether even the first of a kind of work should wait.
pub fn over() -> bool {
    spent() >= HARD
}
/// The call is over: the most a call has spent (since the last `take_peak`), and on which tick.
pub fn end(tick: u64) {
    let s = spent();
    PEAK.with(|p| {
        if s > p.get().0 {
            p.set((s, tick));
        }
    });
}
pub fn take_peak() -> (u64, u64) {
    PEAK.with(|p| p.replace((0, 0)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_and_resets() {
        reset();
        assert!(!full());
        spend(SOFT - 1);
        assert!(!full());
        spend(1);
        assert!(full() && !over());
        spend(HARD);
        assert!(over());
        end(7);
        reset();
        assert_eq!(spent(), 0);
        assert_eq!(take_peak().1, 7);
    }
}
