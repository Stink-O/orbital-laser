//! The real blocks of columns asked of the world (`world.read-columns`): what stands round each column's top, kept until
//! the stage that wants it takes it. As with ground.rs, the world answers a tick or two after it is asked (`poll` takes
//! the answers in each tick), so a stage asks well ahead and the ones that use the answer wait for it, or do without.
//!
//! The columns are read from their world-surface height (one above the highest block that is not air: the top of a tree,
//! the snow on a peak, the water of a lake), `below` under it and `above` from it up.
use horizon_mod_sdk::world::{self, ColumnBlocks, Heightmap};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

/// The most one query asks for (the game takes 65,536 columns and 1,048,576 blocks).
pub const MAX_COLUMNS: usize = 65_536;
pub const MAX_BLOCKS: usize = 1 << 20;

/// An answer: the columns asked about, the names of the blocks seen, each column's top (none: not loaded) and its
/// blocks, `per` a column, bottom first, from `below` under its top.
pub struct Answer {
    pub columns: Vec<(i32, i32)>,
    pub palette: Vec<String>,
    pub bases: Vec<Option<i32>>,
    pub blocks: Vec<u16>,
    /// Each column's grass, foliage and water tints (0xRRGGBB; 0 not loaded).
    pub tints: Vec<u32>,
    pub per: usize,
    pub below: i32,
}
impl Answer {
    /// Column i's grass and foliage tints (0 where not known).
    pub fn tints(&self, i: usize) -> (u32, u32) {
        (self.tints.get(3 * i).copied().unwrap_or(0), self.tints.get(3 * i + 1).copied().unwrap_or(0))
    }
    /// Column i's blocks, bottom first (from its top less `below`), and its top; none where it is not loaded.
    pub fn column(&self, i: usize) -> Option<(i32, &[u16])> {
        let base = self.bases.get(i).copied().flatten()?;
        let s = self.blocks.get(i * self.per..(i + 1) * self.per)?;
        Some((base, s))
    }
}

#[derive(Default)]
struct Store {
    next: u32,
    /// Each query waiting: its columns, and how deep and high it reads.
    asked: HashMap<u32, (Vec<(i32, i32)>, u32, u32)>,
    got: HashMap<u32, Rc<Answer>>,
}

thread_local! {
    static STORE: RefCell<Store> = RefCell::new(Store::default());
}

/// A new query's tag (made as the plan is, so the stage that asks and the ones that read the answer all know it).
pub fn new_tag() -> u32 {
    STORE.with(|s| {
        let mut s = s.borrow_mut();
        s.next = s.next.wrapping_add(1);
        s.next
    })
}

/// Ask the world for `columns`' blocks round their tops, as query `tag` (lib.rs, for `Act::Read`). A query over the
/// game's limits is cut down to them.
pub fn ask(tag: u32, columns: Vec<(i32, i32)>, below: u32, above: u32) {
    let per = (below + above).max(1) as usize;
    let mut columns = columns;
    columns.truncate(MAX_COLUMNS.min(MAX_BLOCKS / per));
    world::read_columns(tag, &columns, Heightmap::WorldSurface, below, above);
    STORE.with(|s| s.borrow_mut().asked.insert(tag, (columns, below, above)));
}

/// The world's answers since the last tick, kept (lib.rs, every tick).
pub fn poll() {
    let answers = world::poll_columns();
    if answers.is_empty() {
        return;
    }
    STORE.with(|s| {
        let mut s = s.borrow_mut();
        for ColumnBlocks { tag, palette, bases, blocks, tints } in answers {
            let Some((columns, below, above)) = s.asked.remove(&tag) else { continue };
            let per = (below + above) as usize;
            s.got.insert(tag, Rc::new(Answer { columns, palette, bases, blocks, tints, per, below: below as i32 }));
        }
    });
}

/// Query `tag`'s answer, once it is in.
pub fn get(tag: u32) -> Option<Rc<Answer>> {
    STORE.with(|s| s.borrow().got.get(&tag).cloned())
}

/// Forget everything asked and answered (a new strike).
pub fn clear() {
    STORE.with(|s| {
        let mut s = s.borrow_mut();
        let next = s.next;
        *s = Store::default();
        s.next = next;
    });
}

/// In the tests, where nothing plays the plan out against a world: query `tag` answered at once, each column's top and
/// its blocks (bottom first, `below` + `above` of them) from `f`, as names.
#[cfg(test)]
pub fn test_answer(tag: u32, columns: &[(i32, i32)], below: u32, above: u32, f: &dyn Fn(i32, i32) -> Option<(i32, Vec<&'static str>)>) {
    let per = (below + above) as usize;
    let mut palette: Vec<String> = vec!["minecraft:air".into()];
    let mut bases = Vec::new();
    let mut blocks = Vec::new();
    for &(x, z) in columns {
        match f(x, z) {
            Some((base, names)) => {
                assert_eq!(names.len(), per);
                bases.push(Some(base));
                for n in names {
                    let i = palette.iter().position(|p| p == n).unwrap_or_else(|| {
                        palette.push(n.to_string());
                        palette.len() - 1
                    });
                    blocks.push(i as u16);
                }
            }
            None => {
                bases.push(None);
                blocks.extend(std::iter::repeat_n(0u16, per));
            }
        }
    }
    // (the tints of a dappled forest east of x 40, the default's elsewhere)
    let tints = columns.iter().flat_map(|&(x, _)| if x > 40 { [0xDF6827, 0xE68E30, 0x375154] } else { [0x91BD59, 0x77AB2F, 0x3F76E4] }).collect();
    let a = Answer { columns: columns.to_vec(), palette, bases, blocks, tints, per, below: below as i32 };
    STORE.with(|s| s.borrow_mut().got.insert(tag, Rc::new(a)));
}
