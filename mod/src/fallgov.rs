//! [World Eater, perf] A cap on the falling blocks a strike summons (the crest's, a breach's thrown blocks and trees): at
//! most so many a tick and so many alive at once at QUALITY PERFORMANCE (lib.rs uses it there only) (counted as alive for `LIFE` ticks after their summons), fewer at the
//! lighter QUALITY tiers and while the frames run long. Those over it are left out, never delayed (a block thrown late
//! flies from where the land no longer heaves). Every falling block is an entity the server moves and the game draws one
//! by one: thousands a hunt cost both.
use std::collections::VecDeque;

/// Ticks a summoned block is counted alive (most land within three or four seconds).
pub const LIFE: u64 = 80;

#[derive(Default)]
pub struct FallGov {
    alive: VecDeque<u64>,
    tick: u64,
    this_tick: u32,
    pub made: u64,
    pub dropped: u64,
}

/// (per tick, alive at once) for a tier (2 FULL, 1 FAST, 0 PERFORMANCE), halved while the frames are slow.
pub fn limits(tier: u8, slow: bool) -> (u32, usize) {
    let (n, alive): (u32, usize) = match tier {
        2 => (12, 260),
        1 => (6, 140),
        _ => (3, 60),
    };
    if slow { (n.div_ceil(2), alive / 2) } else { (n, alive) }
}

impl FallGov {
    /// Whether one more falling block may be summoned on `tick` under `limits`.
    pub fn allow(&mut self, tick: u64, (per_tick, alive): (u32, usize)) -> bool {
        if tick != self.tick {
            self.tick = tick;
            self.this_tick = 0;
        }
        while self.alive.front().is_some_and(|&t| t + LIFE <= tick) {
            self.alive.pop_front();
        }
        if self.this_tick >= per_tick || self.alive.len() >= alive {
            self.dropped += 1;
            return false;
        }
        self.this_tick += 1;
        self.alive.push_back(tick);
        self.made += 1;
        true
    }
}

/// Whether a command summons a falling block (through any `execute ... run`).
pub fn is_falling(cmd: &str) -> bool {
    cmd.contains("summon minecraft:falling_block")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn caps_a_tick_and_the_living() {
        let mut g = FallGov::default();
        let l = limits(1, false);
        let made = (0..20).filter(|_| g.allow(1, l)).count();
        assert_eq!(made, 6);
        // (a burst every tick fills the living cap, then only what has landed makes room)
        for t in 2..40 {
            for _ in 0..20 {
                g.allow(t, l);
            }
        }
        assert_eq!(g.made as usize, 140);
        let before = g.made;
        for _ in 0..20 {
            g.allow(1 + LIFE, l);
        }
        assert_eq!(g.made - before, 6);
        assert!(limits(0, true).0 >= 1 && limits(2, false).1 > limits(1, false).1);
    }
}
