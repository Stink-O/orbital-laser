//! The Earthquake's dust in the air: the words its pass (shaders/earthquake_dust.wgsl) reads besides the table's head
//! and jolts, so it never hashes a plate's lurches per pixel. From word `EQ_FX` (past the jolts' room, whatever their
//! count): for each plate a block of `EQ_FX_STRIDE` words, its whole-block offset (x, y, z), how many lurches it has, then
//! each lurch's start and length (strike seconds). Keep `EQ_FX`, `EQ_FX_STRIDE` and the layout in step with the pass's
//! `EQD_FX`, `EQD_STRIDE` (`eq_fx_in_step`).
use super::earthquake::{EqPlates, EQ_PLATES};

/// Where the dust's words start: past the table's head and the most jolts it can hold (17 + 2 x 16).
pub(crate) const EQ_FX: usize = 64;
/// Words a plate.
pub(crate) const EQ_FX_STRIDE: usize = 20;
/// Room for a plate's lurches (the terrain left alone: seven).
const EQ_FX_LURCHES: usize = 8;

/// The table's words (floats) padded out to `EQ_FX`, then the plates' blocks.
pub(crate) fn eq_fx_extend(w: &mut Vec<f32>, pl: &EqPlates) {
    debug_assert!(w.len() <= EQ_FX);
    w.resize(EQ_FX, 0.0);
    let n = pl.lurch_n();
    for i in 0..EQ_PLATES {
        let o = pl.offset(i);
        let mut b = [0.0f32; EQ_FX_STRIDE];
        b[0] = o[0] as f32;
        b[1] = o[1] as f32;
        b[2] = o[2] as f32;
        b[3] = n as f32;
        for k in 0..n.min(EQ_FX_LURCHES) {
            let l = pl.lurch(i, k);
            b[4 + 2 * k] = l.t;
            b[5 + 2 * k] = l.d;
        }
        w.extend_from_slice(&b);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eq_fx_in_step() {
        let pass = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/shaders/earthquake_dust.wgsl")).unwrap();
        assert!(pass.contains(&format!("const EQD_FX: u32 = {EQ_FX}u;")), "EQD_FX");
        assert!(pass.contains(&format!("const EQD_STRIDE: u32 = {EQ_FX_STRIDE}u;")), "EQD_STRIDE");
        assert!(4 + 2 * EQ_FX_LURCHES <= EQ_FX_STRIDE);
        // (the head and the most jolts fit under EQ_FX)
        assert!(17 + 2 * 16 <= EQ_FX);
    }
}
