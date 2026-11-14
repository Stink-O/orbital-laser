//! The World Eater's body table: the words shaders/worldeater_body.wgsl reads from mod_data, from
//! word WE_BODY_T (512) up to WE_FX_T (2048).
//!
//! Layout (word offsets from WE_BODY_T):
//!   0          how many block types follow
//!   1          1.0 once given (the pass falls back to its own average colours without it)
//!   2          the spit's time (f32 seconds; 0 none): the jaws gape round it. strike/worldeater.rs writes it with
//!              `Act::Words { index: WE_BODY_T + 2, .. }` when it plans a spit
//!   3          kept
//!   4 + 12 i   block type i's words, as the Hurricane packs them (`hurricane::bk_words`: its faces' average colours,
//!              then for its top, bottom and sides the game's sprite layers and how their UVs run, where the game's
//!              atlas has them), in the order of `WB_BLOCKS` (keep it in step with the pass's `WB_B_*` constants)
//!
//! The worm is built of these blocks: each one a real block of the game with its own texture, set on grids that
//! travel with the body (the pass's rings, jaw petals and rings of teeth).
use super::hurricane::{bk_words, hu_block, HU_BKW};
use super::we_path::{WePath, WE_BODY_T, WE_FX_T};

/// The blocks the worm is made of, in the pass's order (worldeater_body.wgsl's WB_B_*).
pub(super) const WB_BLOCKS: [&str; 22] = [
    "minecraft:deepslate_tiles",
    "minecraft:cobbled_deepslate",
    "minecraft:polished_blackstone",
    "minecraft:deepslate_bricks",
    "minecraft:polished_blackstone_bricks",
    "minecraft:cracked_deepslate_tiles",
    "minecraft:tuff",
    "minecraft:sculk",
    "minecraft:deepslate",
    "minecraft:bone_block",
    "minecraft:calcite",
    "minecraft:dripstone_block",
    "minecraft:terracotta",
    "minecraft:grass_block",
    "minecraft:dirt",
    "minecraft:oak_leaves",
    "minecraft:oak_log",
    "minecraft:blackstone",
    "minecraft:basalt",
    "minecraft:chiseled_deepslate",
    "minecraft:polished_deepslate",
    "minecraft:mud_bricks",
];
/// Where the block types start (from WE_BODY_T).
pub(super) const WB_BK0: usize = 4;

/// The body's words (given with the path's table on the tick after it fires: strike/worldeater.rs), the land on its
/// back in the plains' grass and leaf colours.
pub(super) fn we_body_words(_path: &WePath, _seed: u32) -> Vec<u32> {
    we_body_words_tinted(0, 0)
}

/// The same with the biome's grass and leaf colours (0xRRGGBB as the Hurricane reads them; 0 the plains'), for the
/// land the worm carries up on its back.
pub(super) fn we_body_words_tinted(grass: u32, foliage: u32) -> Vec<u32> {
    let mut w = vec![0u32; WB_BK0 + HU_BKW * WB_BLOCKS.len()];
    w[0] = WB_BLOCKS.len() as u32;
    w[1] = 1.0f32.to_bits();
    for (i, name) in WB_BLOCKS.iter().enumerate() {
        if let Some(b) = hu_block(name) {
            w[WB_BK0 + HU_BKW * i..WB_BK0 + HU_BKW * (i + 1)].copy_from_slice(&bk_words(b, grass, foliage));
        }
    }
    debug_assert!(WE_BODY_T + w.len() <= WE_FX_T);
    w
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn we_body_words_fit_and_name_real_blocks() {
        for n in WB_BLOCKS {
            assert!(hu_block(n).is_some(), "{n}");
        }
        let w = we_body_words_tinted(0, 0);
        assert!(WE_BODY_T + w.len() <= WE_FX_T);
        assert_eq!(w[0] as usize, WB_BLOCKS.len());
        // (every block's own average colour is there, so the pass draws it even without the game's textures)
        for i in 0..WB_BLOCKS.len() {
            assert_ne!(w[WB_BK0 + HU_BKW * i], 0, "{}", WB_BLOCKS[i]);
        }
    }
}
