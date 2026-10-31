//! The real ground under a strike's pieces: column heights asked of the world (`world.surface-height`) and kept until
//! the stages that need them are worked out. The world answers a tick or two after it is asked (`poll` takes the
//! answers in each tick), so a stage asks well ahead and the one that uses the answer waits for it, or does without.
//!
//! A column's ground is the first air over it, solid ground only: the lower of its height without leaves (logs and
//! water count) and its ocean floor (leaves count, water does not), so a piece comes to rest on the land under a tree's
//! leaves and on the bed of a lake, not on its water.
use crate::sdk::world::{self, Heightmap, SurfaceHeights};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::hash::{BuildHasherDefault, Hasher};

/// A cheap hash for columns (FxHash's): the standard one costs far more fuel a lookup, and a stage looks up thousands.
#[derive(Default)]
pub(crate) struct Fx(u64);
impl Hasher for Fx {
    fn finish(&self) -> u64 {
        self.0
    }
    fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.write_u64(u64::from(*b));
        }
    }
    fn write_u32(&mut self, v: u32) {
        self.write_u64(u64::from(v));
    }
    fn write_i32(&mut self, v: i32) {
        self.write_u64(u64::from(v as u32));
    }
    fn write_u64(&mut self, v: u64) {
        self.0 = (self.0.rotate_left(5) ^ v).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
    }
}
pub(crate) type FxMap<K, V> = HashMap<K, V, BuildHasherDefault<Fx>>;
pub(crate) type FxSet<K> = HashSet<K, BuildHasherDefault<Fx>>;

/// How many columns one query asks about at most (the game takes 65,536).
pub const PER_QUERY: usize = 65_536;

#[derive(Default)]
struct Store {
    /// Each query waiting for its answers (both heightmaps): its columns, and how many of its two answers are in.
    asked: FxMap<u32, (Vec<(i32, i32)>, u8)>,
    /// The columns' first answer, until the other comes too (and whether it was the ocean floor's).
    half: FxMap<(i32, i32), (Option<i32>, bool)>,
    /// Each column's ground (none: not loaded), once both are in.
    ground: FxMap<(i32, i32), Option<i32>>,
    /// How deep the water over a column's ground is, where there is any (the two heights apart).
    wet: FxMap<(i32, i32), i32>,
    /// The queries answered.
    done: FxSet<u32>,
    /// Answers come in but not yet taken in (`poll` takes in so many columns a tick).
    inbox: std::collections::VecDeque<SurfaceHeights>,
    /// How many columns of the first of them are in.
    taken: usize,
    next: u32,
    /// In the tests: the ground, given at once.
    #[cfg(test)]
    test: Option<fn(i32, i32) -> Option<i32>>,
}

thread_local! {
    static STORE: RefCell<Store> = RefCell::new(Store::default());
}

/// A new query's tag, for `ask` and `ready` (made as the plan is, so the stage that asks and the one that reads the
/// answer both know it).
pub fn new_tag() -> u32 {
    STORE.with(|s| {
        let mut s = s.borrow_mut();
        // (the world's tags are twice it, and one more: kept under half the range)
        s.next = (s.next + 1) & 0x7fff_ffff;
        s.next
    })
}

/// Ask the world for `columns`' ground (at most `PER_QUERY`), as query `tag` (lib.rs, for `Act::Survey`).
pub fn ask(tag: u32, columns: Vec<(i32, i32)>) {
    if columns.is_empty() {
        STORE.with(|s| s.borrow_mut().done.insert(tag));
        return;
    }
    let mut columns = columns;
    columns.truncate(PER_QUERY);
    // (two queries: tag * 2 the heights without leaves, tag * 2 + 1 the ocean floor)
    world::surface_height(tag * 2, &columns, Heightmap::MotionBlockingNoLeaves);
    world::surface_height(tag * 2 + 1, &columns, Heightmap::OceanFloor);
    STORE.with(|s| s.borrow_mut().asked.insert(tag, (columns, 0)));
}

/// Columns `poll` takes in a tick at most (more wait for the next: answers that come in together, when the world is
/// slow, would otherwise all be taken in on one tick, beside that tick's stage).
const POLL_COLUMNS: usize = 3_000;

/// The world's answers since the last tick, kept (lib.rs, every tick): as many columns of them a tick as
/// POLL_COLUMNS and the tick's work (`meter`) allow, a big answer over several ticks.
pub fn poll() {
    let answers = world::poll_surface_heights();
    STORE.with(|s| {
        let mut s = s.borrow_mut();
        let s = &mut *s;
        s.inbox.extend(answers);
        let mut budget = POLL_COLUMNS;
        while budget > 0 && !crate::meter::full() {
            let Some(front) = s.inbox.front() else { break };
            let (tag, len) = (front.tag, front.heights.len());
            let q = tag / 2;
            let Some((cols, got)) = s.asked.get(&q) else {
                // (an answer to a query no longer asked about: an earlier strike's)
                s.inbox.pop_front();
                s.taken = 0;
                continue;
            };
            let got = *got;
            // (this tick's share of it, from where the last tick left it)
            let (i0, i1) = (s.taken, (s.taken + budget).min(cols.len()));
            budget -= i1 - i0;
            crate::meter::spend(3_600 * (i1 - i0) as u64 + 200);
            let floor = tag % 2 == 1;
            for i in i0..i1 {
                let c = cols[i];
                let h = if i < len { s.inbox[0].heights[i] } else { None };
                if got == 0 {
                    // (the first of its two answers: kept until the other comes)
                    s.half.insert(c, (h, floor));
                    continue;
                }
                let (other, other_floor) = s.half.remove(&c).unwrap_or((None, !floor));
                let g = match (other, h) {
                    (Some(a), Some(b)) => {
                        // (water: the height without leaves over the ocean floor's)
                        let (top, bed) = if other_floor { (b, a) } else { (a, b) };
                        if top > bed {
                            s.wet.insert(c, top - bed);
                        }
                        Some(a.min(b))
                    }
                    _ => None,
                };
                s.ground.insert(c, g);
            }
            if i1 < cols.len() {
                s.taken = i1;
                continue;
            }
            // (all of it in)
            s.inbox.pop_front();
            s.taken = 0;
            if got == 0 {
                if let Some(e) = s.asked.get_mut(&q) {
                    e.1 = 1;
                }
            } else {
                s.asked.remove(&q);
                s.done.insert(q);
            }
        }
    });
}

/// Whether query `tag` has been answered.
pub fn ready(tag: u32) -> bool {
    STORE.with(|s| s.borrow().done.contains(&tag))
}

/// Column (x, z)'s ground, the first air over it (none: not asked, not answered yet, or not loaded).
pub fn at(x: i32, z: i32) -> Option<i32> {
    STORE.with(|s| s.borrow().ground.get(&(x, z)).copied().flatten())
}

/// How deep the water standing over column (x, z)'s ground is (none: dry, or not answered).
pub fn water(x: i32, z: i32) -> Option<i32> {
    STORE.with(|s| s.borrow().wet.get(&(x, z)).copied())
}

/// In the tests: water this deep over the columns given.
#[cfg(test)]
pub fn set_test_water(cols: &[((i32, i32), i32)]) {
    STORE.with(|s| {
        let mut s = s.borrow_mut();
        for &(c, d) in cols {
            s.wet.insert(c, d);
        }
    });
}

/// Forget everything asked and answered (a new strike; answers to an earlier one's queries that come later are
/// dropped).
pub fn clear() {
    STORE.with(|s| {
        let mut s = s.borrow_mut();
        let next = s.next;
        #[cfg(test)]
        let test = s.test;
        *s = Store::default();
        s.next = next;
        #[cfg(test)]
        {
            s.test = test;
        }
    });
}

/// In the tests, where nothing plays the plan out against a world: query `tag` answered at once, as the plan makes it,
/// with the ground `set_test` gave (or none of it).
#[cfg(test)]
pub fn test_answer(tag: u32, columns: &[(i32, i32)]) {
    STORE.with(|s| {
        let mut s = s.borrow_mut();
        if let Some(f) = s.test {
            for c in columns {
                s.ground.insert(*c, f(c.0, c.1));
            }
        }
        s.done.insert(tag);
    });
}

/// In the tests: the ground every query is answered with at once (none: none of it, the way a world that did not say
/// would leave it).
#[cfg(test)]
pub fn set_test(f: Option<fn(i32, i32) -> Option<i32>>) {
    STORE.with(|s| {
        let mut s = s.borrow_mut();
        *s = Store::default();
        s.test = f;
    });
}
