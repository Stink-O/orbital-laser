//! What the mod holds in memory. A mod has 64 MB of linear memory and it never shrinks: past that an allocation fails and
//! the game stops the mod for good ("it crashed (a panic)"), so a strike's peak has to stay well under it, and a strike's
//! memory has to come back when it ends. The allocator is the system's with a count round it, per thread (`thread_local`:
//! the tests run side by side, each sees its own): `live` what's held now, `peak` the most held since `reset_peak`;
//! `heap` how far the linear memory has grown, which only ever rises (what's freed goes back to the allocator's bins, so
//! a heap well over the peak is fragmentation). lib.rs logs the three as a strike ends and as the heap grows.
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;

struct Counted;
thread_local! {
    static LIVE: Cell<usize> = const { Cell::new(0) };
    static PEAK: Cell<usize> = const { Cell::new(0) };
}
#[inline]
fn add(n: usize) {
    let _ = LIVE.try_with(|l| {
        let v = l.get().saturating_add(n);
        l.set(v);
        let _ = PEAK.try_with(|p| p.set(p.get().max(v)));
    });
}
#[inline]
fn sub(n: usize) {
    let _ = LIVE.try_with(|l| l.set(l.get().saturating_sub(n)));
}
// SAFETY: every call is passed straight to the system's allocator; the count round it allocates nothing.
unsafe impl GlobalAlloc for Counted {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let p = unsafe { System.alloc(layout) };
        if !p.is_null() {
            add(layout.size());
        }
        p
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let p = unsafe { System.alloc_zeroed(layout) };
        if !p.is_null() {
            add(layout.size());
        }
        p
    }
    unsafe fn dealloc(&self, p: *mut u8, layout: Layout) {
        unsafe { System.dealloc(p, layout) };
        sub(layout.size());
    }
    unsafe fn realloc(&self, p: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        let q = unsafe { System.realloc(p, layout, size) };
        if !q.is_null() {
            add(size);
            sub(layout.size());
        }
        q
    }
}
// (the fork's WebAssembly mod and the tests only: the native build is compiled into the game, which has its own global
// allocator, so there it counts nothing and `live` and `peak` stay 0)
#[cfg_attr(any(target_arch = "wasm32", test), global_allocator)]
static COUNTED: Counted = Counted;

/// Bytes held now.
pub fn live() -> usize {
    LIVE.with(Cell::get)
}
/// The most bytes held since `reset_peak`.
pub fn peak() -> usize {
    PEAK.with(Cell::get)
}
/// The peak starts again from what's held now.
pub fn reset_peak() {
    PEAK.with(|p| p.set(live()));
}
/// How far the linear memory has grown, in bytes (0 natively).
pub fn heap() -> usize {
    #[cfg(target_arch = "wasm32")]
    return core::arch::wasm32::memory_size(0) * 65_536;
    #[cfg(not(target_arch = "wasm32"))]
    0
}
/// A size in megabytes, for the log.
pub fn mb(n: usize) -> f64 {
    n as f64 / 1_048_576.0
}
