//! The World Eater's fx table: the blocks shaders/worldeater.wgsl draws (the clods and slabs thrown
//! on the approach and at the holes, the land streaming down the throat, the trees and lumps it ate), as real blocks
//! of the game with its own textures, from word WE_FX_T + WEF_BK.
//!
//! Layout (word offsets from WE_FX_T + WEF_BK):
//!   0          how many block types follow
//!   1          1.0 once given (the pass falls back to its own look-alike colours without it)
//!   2, 3       kept
//!   4 + 12 i   block type i's words, as the Hurricane packs them (`hurricane::bk_words`), in the order of WEF_BLOCKS
//!              (keep it in step with the pass's WEF_B_* constants)
use super::hurricane::{bk_words, hu_block, HU_BKW};
use super::we_path::WE_FX_T;

/// Where the fx's block table starts, from WE_FX_T (after the caught words and the heightfield's room).
pub(super) const WEF_BK: usize = 1024;
/// Where its block types start, from WE_FX_T + WEF_BK.
const WEF_BK0: usize = 4;
/// The blocks, in the pass's order (worldeater.wgsl's WEF_B_*).
pub(super) const WEF_BLOCKS: [&str; 19] = [
    "minecraft:dirt",
    "minecraft:coarse_dirt",
    "minecraft:grass_block",
    "minecraft:stone",
    "minecraft:cobblestone",
    "minecraft:deepslate",
    "minecraft:gravel",
    "minecraft:sand",
    "minecraft:oak_log",
    "minecraft:birch_log",
    "minecraft:spruce_log",
    "minecraft:acacia_log",
    "minecraft:oak_leaves",
    "minecraft:birch_leaves",
    "minecraft:spruce_leaves",
    "minecraft:acacia_leaves",
    "minecraft:iron_ore",
    "minecraft:diamond_ore",
    "minecraft:sculk",
];

/// The fx's words, to go at WE_FX_T + WEF_BK, its grass and leaves in the biome's colours (0xRRGGBB as the Hurricane
/// reads them; 0 the plains').
pub(super) fn we_fx_words(grass: u32, foliage: u32) -> Vec<u32> {
    let mut w = vec![0u32; WEF_BK0 + HU_BKW * WEF_BLOCKS.len()];
    w[0] = WEF_BLOCKS.len() as u32;
    w[1] = 1.0f32.to_bits();
    for (i, name) in WEF_BLOCKS.iter().enumerate() {
        if let Some(b) = hu_block(name) {
            w[WEF_BK0 + HU_BKW * i..WEF_BK0 + HU_BKW * (i + 1)].copy_from_slice(&bk_words(b, grass, foliage));
        }
    }
    debug_assert!(WE_FX_T + WEF_BK + w.len() <= super::we_path::WE_LAND_T);
    w
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn we_fx_words_fit_and_name_real_blocks() {
        for n in WEF_BLOCKS {
            assert!(hu_block(n).is_some(), "{n}");
        }
        assert!(WE_FX_T + WEF_BK + we_fx_words(0, 0).len() <= super::super::we_path::WE_LAND_T);
    }

    /// The pass's WEP_* are these.
    #[test]
    fn pcs_layout_in_step() {
        let src = include_str!("../../shaders/worldeater.wgsl");
        for (name, v) in [("WEP_T", WE_PCS_T), ("WEP_SRC", PCS_SRC), ("WEP_SUP", PCS_SUP), ("WEP_GRP", PCS_GRP), ("WEP_PC", PCS_PC), ("WEP_W", PCS_W), ("WEP_LEN", PCS_LEN), ("WEP_EV", PCS_EV), ("WEP_HK", PCS_HK), ("WEP_HKS", PCS_HKS)] {
            assert!(src.contains(&format!("const {name}: u32 = {v}u;")), "{name} = {v}");
        }
        assert!(WE_PCS_T >= super::super::we_path::WE_DBG_T + 1024);
    }

    /// f16 and the axis' words as the pass reads them back.
    #[test]
    fn pcs_packing() {
        for x in [0.0f32, 1.0, -2.5, 0.333, 1234.5, 6.0e-5, -7.0e-6, 60000.0] {
            let h = f16_bits(x);
            let back = half_to_f32(h);
            assert!((back - x).abs() <= x.abs() * 1.0e-3 + 6.0e-8, "{x} {back}");
        }
        let mut r = Rng(5);
        for _ in 0..1000 {
            let a = v3(r.u() - 0.5, r.u() - 0.5, r.u() - 0.5).norm();
            let w = oct(a);
            let e = |b: u32| (b as u16 as i16) as f32 / 32767.0;
            let (ex, ey) = (e(w), e(w >> 16));
            let mut v = v3(ex, ey, 1.0 - ex.abs() - ey.abs());
            let k = (-v.z).max(0.0);
            v.x += if v.x >= 0.0 { -k } else { k };
            v.y += if v.y >= 0.0 { -k } else { k };
            let b = v.norm();
            assert!((b - a).len() < 2.0e-4, "{a:?} {b:?}");
        }
    }
    fn half_to_f32(h: u16) -> f32 {
        let s = if h & 0x8000 != 0 { -1.0 } else { 1.0 };
        let e = ((h >> 10) & 0x1f) as i32;
        let m = (h & 0x3ff) as f32;
        if e == 0 { s * m * 2f32.powi(-24) } else { s * (1.0 + m / 1024.0) * 2f32.powi(e - 15) }
    }

    /// `PCS_REF=dir PCS_IN=hunt4.txt cargo test --release we_pieces_match_the_pass -- --ignored`: this port against the
    /// pass's own formulas (the old per-pixel wef_piece, its run loop and the spit, as worldeater.wgsl had them at
    /// d562c5b), which perf/pieces/ref/mkref.py's dump pass writes out on the card, one number a pixel, at the times in
    /// dir/times.txt (dir/<t>.dump: `row x bits`). Every piece the pass would draw must be where this puts it.
    #[test]
    #[ignore]
    fn we_pieces_match_the_pass() {
        let dir = std::env::var("PCS_REF").unwrap();
        let data = read_table(&std::env::var("PCS_IN").unwrap());
        let w = Wd(&data);
        let seed = 37u32;
        let times = std::fs::read_to_string(format!("{dir}/times.txt")).unwrap();
        let (mut nh, mut nr, mut ns, mut nk, mut worst) = (0, 0, 0, 0, 0.0f32);
        for ts in times.split_whitespace() {
            let t: f32 = ts.parse().unwrap();
            let mut g = std::collections::HashMap::new();
            for l in std::fs::read_to_string(format!("{dir}/{ts}.dump")).unwrap().lines() {
                let v: Vec<u32> = l.split_whitespace().map(|x| x.parse().unwrap()).collect();
                g.insert((v[0], v[1]), v[2]);
            }
            let gu = |y: u32, x: u32| g.get(&(y, x)).copied().unwrap_or(0);
            let gf = |y: u32, x: u32| f32::from_bits(gu(y, x));
            let mut close = |what: &str, a: f32, b: f32, tol: f32| {
                let d = (a - b).abs() / (1.0 + b.abs().min(100.0) * 0.0);
                worst = worst.max(d / tol);
                assert!(d <= tol, "t {t} {what}: rust {a} pass {b}");
            };
            for k in 0..2 * w.n() {
                let h = hk(&w, k, t);
                for cls in 0..5u32 {
                    let row = (k * 5 + cls) * 16;
                    let cnt = (0..2560).filter(|&x| gu(row + 12, x) == 1).count() as u32;
                    assert_eq!(cnt, pn(cls, &h).0, "t {t} hole {k} class {cls}: count");
                    for i in 0..cnt {
                        let p = piece(cls, i, &h, if cls < 3 { h.ab } else { h.ai }, seed);
                        let live = gf(row + 11, i);
                        close(&format!("hole {k} cls {cls} #{i} live"), p.live, live, 2.0e-3);
                        if live <= 0.02 {
                            continue;
                        }
                        nh += 1;
                        let c = w.hole(k) + p.c;
                        for (j, (a, b)) in [(c.x, gf(row, i)), (c.y, gf(row + 1, i)), (c.z, gf(row + 2, i))].into_iter().enumerate() {
                            close(&format!("hole {k} cls {cls} #{i} c{j}"), a, b, 0.02);
                        }
                        for (j, (a, b)) in [(p.e.x, gf(row + 3, i)), (p.e.y, gf(row + 4, i)), (p.e.z, gf(row + 5, i)), (p.ax.x, gf(row + 6, i)), (p.ax.y, gf(row + 7, i)), (p.ax.z, gf(row + 8, i)), (p.an, gf(row + 9, i))].into_iter().enumerate() {
                            close(&format!("hole {k} cls {cls} #{i} f{j}"), a, b, 2.0e-3);
                        }
                        assert_eq!(p.kind, gu(row + 10, i), "t {t} hole {k} cls {cls} #{i} kind");
                    }
                }
            }
            for r in 0..w.n() {
                let rt = run_t(&w, r, t);
                for q in 0..3u32 {
                    let row = 960 + (r * 3 + q) * 16;
                    for kk in 0..2560u32 {
                        let (p, pwy, es0, keep) = run_clod(&rt, r, kk as i32, q, t);
                        let ok = gu(row + 9, kk) == 1;
                        assert_eq!(p.live > 0.0, ok, "t {t} run {r} q {q} kk {kk}: in its window");
                        if !ok {
                            continue;
                        }
                        nr += 1;
                        for (j, (a, b)) in [(p.c.x, gf(row, kk)), (p.c.y, gf(row + 1, kk)), (p.c.z, gf(row + 2, kk)), (pwy, gf(row + 5, kk))].into_iter().enumerate() {
                            close(&format!("run {r} q {q} kk {kk} c{j}"), a, b, 0.02);
                        }
                        for (j, (a, b)) in [(p.an, gf(row + 3, kk)), (p.live, gf(row + 4, kk)), (es0, gf(row + 6, kk))].into_iter().enumerate() {
                            close(&format!("run {r} q {q} kk {kk} f{j}"), a, b, 2.0e-3);
                        }
                        assert_eq!(keep, gf(row + 7, kk) >= 0.6);
                        assert_eq!(p.kind, gu(row + 8, kk), "t {t} run {r} q {q} kk {kk} kind");
                    }
                }
            }
            for i in 0..36u32 {
                let p = spit(&w, i, t);
                let ok = gu(1254, i) == 1;
                assert_eq!(p.live > 0.0 || (ok && gf(1252, i) == 0.0), ok, "t {t} spit #{i}");
                if !ok {
                    continue;
                }
                ns += 1;
                for (j, (a, b)) in [(p.c.x, gf(1248, i)), (p.c.y, gf(1249, i)), (p.c.z, gf(1250, i))].into_iter().enumerate() {
                    close(&format!("spit #{i} c{j}"), a, b, 0.02);
                }
                close(&format!("spit #{i} an"), p.an, gf(1251, i), 2.0e-3);
                close(&format!("spit #{i} live"), p.live, gf(1252, i), 2.0e-3);
                assert_eq!(p.kind, gu(1253, i));
            }
            // (wef_hk's billows and clumps, where the dump has them)
            for k in 0..2 * w.n() {
                let row = 1280 + k;
                if (0..220).all(|x| gu(row, x) == 0) {
                    continue;
                }
                let mut o = vec![0u32; PCS_HKS];
                hk_words(&w, k, t, &mut o);
                // (and its reach (capped as the pass caps it), climb, tails and sizes, at 220..227 of the dump)
                if (220..227).any(|x| gu(row, x) != 0) {
                    let h = hk(&w, k, t);
                    let (rx, ry) = hole_reach(&w, k, t);
                    let tin = if k & 1 == 1 { w.tail_in(k) } else { -1.0e4 };
                    for (j, a) in [rx.min(R + 12.0 + 4.5 * 32.0 + 60.0), ry, h.climb, h.tout, tin, h.sb, h.bs].into_iter().enumerate() {
                        let b = gf(row, 220 + j as u32);
                        nk += 1;
                        close(&format!("hole {k} hk scalar {j}"), a, b, if b.abs() > 50.0 { 0.02 } else { 2.0e-3 });
                    }
                }
                for x in 0..220u32 {
                    let a = f32::from_bits(o[x as usize]);
                    let b = gf(row, x);
                    // (a slot not alive is all 0 in the dump; the port keeps its place for the tick's taking between)
                    let alive = x >= 216 || if x < 90 { f32::from_bits(o[(x / 9 * 9 + 3) as usize]) > 0.0 } else { f32::from_bits(o[(90 + (x - 90) / 9 * 9 + 3) as usize]) > 0.0 };
                    if alive {
                        nk += 1;
                        let tol = if b.abs() > 50.0 { 0.02 } else { 2.0e-3 };
                        close(&format!("hole {k} hk word {x}"), a, b, tol);
                    } else {
                        assert_eq!(b, 0.0, "t {t} hole {k} hk word {x}: alive in the pass only");
                    }
                }
            }
        }
        eprintln!("matched: {nh} holes' pieces, {nr} run clods, {ns} spit blocks, {nk} words of the holes' billows and clumps; worst error {worst:.2} of the tolerance");
        assert!(nh > 500 && nr > 500, "too few pieces compared");
    }

    /// `PCS_IN=table.txt cargo test --release we_pieces_worst_tick -- --ignored --nocapture`: every tick of a strike's
    /// pieces worked out natively: the most pieces, the meter's count and the native time of the worst tick.
    #[test]
    #[ignore]
    fn we_pieces_worst_tick() {
        let data = read_table(&std::env::var("PCS_IN").unwrap());
        let (mut worst, mut wt, mut most, mut mt, mut slow, mut st) = (0u64, 0.0, 0u32, 0.0, 0.0f64, 0.0);
        for n in 0..1800 {
            let t = n as f32 * 0.05;
            let a = std::time::Instant::now();
            let (w, cost) = we_pieces_words(&data, t, 37.0);
            let us = a.elapsed().as_secs_f64() * 1.0e6;
            if cost > worst {
                (worst, wt) = (cost, t);
            }
            if w[5] > most {
                (most, mt) = (w[5], t);
            }
            if us > slow {
                (slow, st) = (us, t);
            }
        }
        eprintln!("most pieces {most} at {mt:.2} s; the meter's worst {:.1} M at {wt:.2} s; slowest natively {slow:.0} us at {st:.2} s", worst as f64 / 1.0e6);
    }

    /// A preview table (tools/preview's `index value` lines) read in.
    pub(crate) fn read_table(path: &str) -> Vec<u32> {
        let mut w = vec![0u32];
        for l in std::fs::read_to_string(path).unwrap().lines() {
            let mut it = l.split_whitespace();
            let (Some(i), Some(v)) = (it.next(), it.next()) else { continue };
            let i: usize = i.parse().unwrap();
            if w.len() <= i {
                w.resize(i + 1, 0);
            }
            w[i] = match v.strip_suffix('u') {
                Some(u) => u.parse().unwrap(),
                None => v.parse::<f32>().unwrap().to_bits(),
            };
        }
        w
    }

    /// `PCS_IN=table.txt PCS_T='14 17.5' PCS_OUT=dir [PCS_SEED=37] cargo test --release we_pieces_stage -- --ignored`:
    /// the pieces' words at each time (as the game's tick gives them, at the tick's own time), written as
    /// PCS_OUT/<t>.txt, the words from WE_PCS_T only (the preview lays them over the table: $PREVIEW_DATA_SHOTS).
    #[test]
    #[ignore]
    fn we_pieces_stage() {
        let data = read_table(&std::env::var("PCS_IN").unwrap());
        let seed: f32 = std::env::var("PCS_SEED").map_or(37.0, |v| v.parse().unwrap());
        let out = std::env::var("PCS_OUT").unwrap();
        std::fs::create_dir_all(&out).unwrap();
        for ts in std::env::var("PCS_T").unwrap().split_whitespace() {
            let t: f32 = ts.parse().unwrap();
            let (w, cost) = we_pieces_words(&data, t, seed);
            let txt: String = w.iter().enumerate().map(|(i, v)| format!("{} {v}u\n", WE_PCS_T + i)).collect();
            std::fs::write(format!("{out}/{ts}.txt"), txt).unwrap();
            eprintln!("t {t}: {} sources, {} supers, {} groups, {} pieces; ~{:.1} M instructions", w[2], w[3], w[4], w[5], cost as f64 / 1.0e6);
        }
    }
}

// ---- the pieces: worked out here each tick, drawn by the pass ------------------------------------------------------
// Every piece of the land the pass throws (the breach's crown, its slabs, the pour, the bite's slabs and its splash, the
// clods over a passing head, the spit's burst) is a deterministic function of the path's words and the time. The pass
// used to work all of them out for every pixel (worldeater.wgsl's old `wef_piece` and its loops); now this does it once a
// tick, a port of the same formulas on the same words, and writes the LIVE ones only, with coarse bounds, from
// WE_PCS_T: the pass extrapolates each by the frame's time past the tick and tests a ray against a few boxes before any
// piece. What depends on the camera (how many of a hole's small ones are drawn at its distance, a slab shrunk near the
// eye, a run's clods thinned and grown with the distance) stays in the pass.
//
// Layout (words from WE_PCS_T; keep worldeater.wgsl's WEP_* in step):
//   0 1 (u32) once written; 1 the tick's strike time t_d; 2..6 how many sources, supers, groups, pieces (u32); 6 PCS_DT
//   PCS_SRC + 8 s   source s: [0] kind (0 a hole's class, 1 a run's clods, 2 the spit; u32), [1..4] the hole's middle
//                   (or the run's start F), from the origin, [4] a hole's class's count before its distance and detail
//                   cut it (0: never cut), or a run's way d.x, [5] d.y, [6] the run's head along it at t_d, [7] its rate
//   PCS_SUP + 8 g   a box of up to PCS_SUPN groups: [0..3] lo, [3..6] hi (from the origin), [6] first | count << 16
//   PCS_GRP + 8 g   a box of up to PCS_GRPN pieces of one source: [0..6] lo, hi, [6] first | count << 16, [7] its source
//   PCS_PC + 12 p   piece p: [0..3] its middle at t_d (from the origin), [3] v.xy, [4] v.z and its life at t_d, [5] its
//                   life's rate and its spin's (f16 pairs), [6] its reach (a hole's: the radius of its bound at life 1)
//                   and -, [7] a hole's half sizes x y (a run's: its size before the distance grows it, and how high it
//                   has flown), [8] a hole's half size z (a run's: how fast it flies up), [9] its axis (octahedral,
//                   snorm16), [10] meta: bits 0-1 kind, 2-4 class (a run's: q), 5-7 block (0-5 as debris_tex, 6 a slab, 7
//                   a slab with a tree), 9 a run's clod kept far off, 16-31 its number (a run's: its place kk), [11] its
//                   angle at t_d
use super::we_path::{
    WE_A0, WE_AW, WE_EYE_T, WE_LAND_T, WE_R_APEX, WE_R_FROM, WE_R_H0, WE_R_LEN, WE_R_RUN, WE_R_S, WE_R_TIN, WE_R_TO, WE_R_TOUT, WE_R_VIN, WE_R_VOUT, WE_T_COUNT,
};
use super::we_path::{WE_R_RUN_DIVE, WE_R_RUN_LAND, WE_R_RUN_LEN, WE_R_RUN_T, WE_R_RUN_V, WE_R_RUN_Y};

/// Where the pieces' table starts in mod_data (past the preview's debug words at WE_DBG_T).
pub(crate) const WE_PCS_T: usize = 20480;
pub(crate) const PCS_SRC: usize = 16;
pub(crate) const PCS_NSRC: usize = 32;
pub(crate) const PCS_SUP: usize = PCS_SRC + 8 * PCS_NSRC;
pub(crate) const PCS_NSUP: usize = 96;
pub(crate) const PCS_GRP: usize = PCS_SUP + 8 * PCS_NSUP;
pub(crate) const PCS_NGRP: usize = 512;
pub(crate) const PCS_PC: usize = PCS_GRP + 8 * PCS_NGRP;
pub(crate) const PCS_W: usize = 12;
pub(crate) const PCS_NPC: usize = 4096;
/// The table's whole length (written whole every tick, so mod_data keeps its size).
/// The camera's jolts' and the lens' events (each hole's breach or bite from just before it to 25 s after, each run's
/// rumble while its tunnel fails), 8 words each: [0] 0 a breach, 1 a bite, 2 a run's rumble (u32), [1] its time (a
/// run's: its first ring), [2] its size (a run's: how long to its last ring), [3] the hole (u32), [4..7] where (a run's
/// middle), from the origin. Their count at header word 7.
pub(crate) const PCS_EV: usize = PCS_PC + PCS_W * PCS_NPC;
pub(crate) const PCS_NEV: usize = 32;
/// Each hole's billows and clumps (wef_hk's) at t_d and at t_d + PCS_DT, for the pass to take between: PCS_HKW words a
/// hole, two slices of PCS_HKS: [0..90] the billows (10 x: middle xyz, radius (0 none), roll axis xyz, roll angle, life),
/// [90..216] the clumps (14 x: head xyz, radius (0 none), tail xyz, its radius, life), [216..218] how far out and how
/// high the billows reach from the hole (wef_pmax), [218..220] the clumps' (wef_cmax), [220..222] how far out and how
/// high its dust reaches (wef_hole_reach's, less the dome's and before its cap), [222] how high the head has climbed out
/// of it, [223] its tail out, [224] its tail in, [225] the breach's size, [226] the bite's. Given once header word 8 is 1.
pub(crate) const PCS_HK: usize = PCS_EV + 8 * PCS_NEV;
pub(crate) const PCS_HKS: usize = 232;
pub(crate) const PCS_HKW: usize = 2 * PCS_HKS;
pub(crate) const PCS_NHK: usize = 12;
pub(crate) const PCS_LEN: usize = PCS_HK + PCS_HKW * PCS_NHK;
const WEF_NP: u32 = 10;
const WEF_NC: u32 = 14;
/// Pieces a group, groups a super.
const PCS_GRPN: usize = 16;
const PCS_SUPN: usize = 8;
/// The tick: the pass extrapolates a piece at most this far past t_d (the boxes hold it over that).
pub(crate) const PCS_DT: f32 = 0.05;
/// The step its velocity and spin are taken over.
const PCS_EPS: f32 = 1.0 / 128.0;

const R: f32 = super::we_path::WE_R as f32;
const LEN: f32 = super::we_path::WE_LEN as f32;
const APEX: f32 = super::we_path::WE_APEX as f32;
const RUN_TURN: f32 = super::we_path::WE_RUN_TURN as f32;
const TN: usize = super::we_path::WE_TN;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct V3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}
const fn v3(x: f32, y: f32, z: f32) -> V3 {
    V3 { x, y, z }
}
impl std::ops::Add for V3 {
    type Output = V3;
    fn add(self, o: V3) -> V3 {
        v3(self.x + o.x, self.y + o.y, self.z + o.z)
    }
}
impl std::ops::Sub for V3 {
    type Output = V3;
    fn sub(self, o: V3) -> V3 {
        v3(self.x - o.x, self.y - o.y, self.z - o.z)
    }
}
impl std::ops::Mul<f32> for V3 {
    type Output = V3;
    fn mul(self, s: f32) -> V3 {
        v3(self.x * s, self.y * s, self.z * s)
    }
}
impl V3 {
    fn mulv(self, o: V3) -> V3 {
        v3(self.x * o.x, self.y * o.y, self.z * o.z)
    }
    fn len(self) -> f32 {
        (self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
    }
    fn len_xz(self) -> f32 {
        (self.x * self.x + self.z * self.z).sqrt()
    }
    fn norm(self) -> V3 {
        self * (1.0 / self.len())
    }
    fn min(self, o: V3) -> V3 {
        v3(self.x.min(o.x), self.y.min(o.y), self.z.min(o.z))
    }
    fn max(self, o: V3) -> V3 {
        v3(self.x.max(o.x), self.y.max(o.y), self.z.max(o.z))
    }
}

// (WGSL's own, as the pass has them)
fn smoothstep(a: f32, b: f32, x: f32) -> f32 {
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}
fn mix(a: f32, b: f32, t: f32) -> f32 {
    a * (1.0 - t) + b * t
}
fn fract(x: f32) -> f32 {
    x - x.floor()
}
fn pcg(x: u32) -> u32 {
    let s = x.wrapping_mul(747796405).wrapping_add(2891336453);
    let w = ((s >> ((s >> 28) + 4)) ^ s).wrapping_mul(277803737);
    (w >> 22) ^ w
}
fn fh21(x: f32, y: f32) -> f32 {
    let qx = (x.floor() as i32) as u32;
    let qy = (y.floor() as i32) as u32;
    pcg(qx ^ pcg(qy)) as f32 * (1.0 / 4294967295.0)
}
fn wef_ph(i: u32, k: u32, s: u32) -> f32 {
    pcg(i.wrapping_mul(747796405).wrapping_add(k.wrapping_mul(2891336453)).wrapping_add(s.wrapping_mul(0x9e3779b9))) as f32 * (1.0 / 4294967296.0)
}
/// wef_u's stream.
struct Rng(u32);
impl Rng {
    fn u(&mut self) -> f32 {
        self.0 = self.0.wrapping_mul(747796405).wrapping_add(2891336453);
        let s = self.0;
        let w = ((s >> ((s >> 28) + 4)) ^ s).wrapping_mul(277803737);
        ((w >> 22) ^ w) as f32 * (1.0 / 4294967296.0)
    }
}
fn wef_fly(p0: V3, v0: V3, tau: f32, kd: f32, g: f32) -> V3 {
    let e = (1.0 - (-kd * tau).exp()) / kd;
    p0 + v3(v0.x * e, v0.y * e - g * (tau - e) / kd, v0.z * e)
}
fn wef_kind(m: f32) -> u32 {
    if m > 0.94 {
        if m > 0.97 { 5 } else { 4 }
    } else if m > 0.86 {
        0
    } else if m > 0.7 {
        3
    } else if m > 0.38 {
        2
    } else {
        1
    }
}

/// The pass's reads of the path's words (worldeater_path.wgsl and worldeater.wgsl), in f32 as it has them.
struct Wd<'a>(&'a [u32]);
impl Wd<'_> {
    fn w(&self, i: usize) -> f32 {
        self.0.get(i).map_or(0.0, |&v| f32::from_bits(v))
    }
    fn n(&self) -> u32 {
        ((self.w(WE_T_COUNT).max(0.0) + 0.5) as u32).min(super::we_path::WE_ARCS_MAX as u32)
    }
    fn aw(&self, i: u32, k: usize) -> f32 {
        self.w(WE_A0 + i as usize * WE_AW + k)
    }
    fn a3(&self, i: u32, k: usize) -> V3 {
        v3(self.aw(i, k), self.aw(i, k + 1), self.aw(i, k + 2))
    }
    fn arch_from(&self, i: u32) -> V3 {
        self.a3(i, WE_R_FROM)
    }
    fn arch_to(&self, i: u32) -> V3 {
        self.a3(i, WE_R_TO)
    }
    fn s0(&self, i: u32) -> f32 {
        self.aw(i, WE_R_S)
    }
    fn alen(&self, i: u32) -> f32 {
        self.aw(i, WE_R_LEN)
    }
    fn t_out(&self, i: u32) -> f32 {
        self.aw(i, WE_R_TOUT)
    }
    fn t_in(&self, i: u32) -> f32 {
        self.aw(i, WE_R_TIN)
    }
    fn run_from(&self, i: u32) -> V3 {
        v3(self.aw(i, WE_R_RUN), self.aw(i, WE_R_RUN_LAND), self.aw(i, WE_R_RUN + 1))
    }
    fn run_len(&self, i: u32) -> f32 {
        self.aw(i, WE_R_RUN_LEN)
    }
    fn run_s(&self, i: u32) -> f32 {
        self.s0(i) - self.run_len(i)
    }
    // (we_run_at's place)
    fn run_at(&self, i: u32, u0: f32) -> V3 {
        let rt = RUN_TURN;
        let q = 1.5707963 * rt;
        let st = self.run_from(i);
        let a = self.arch_from(i);
        let (ddx, ddz) = (a.x - st.x, a.z - st.z);
        let hd = (ddx * ddx + ddz * ddz).sqrt().max(1.0e-4);
        let (ex, ez) = (ddx / hd, ddz / hd);
        let y = self.aw(i, WE_R_RUN_Y);
        let mut u = u0;
        let mut x0 = 0.0;
        if self.aw(i, WE_R_RUN_DIVE) > 0.5 {
            let v1 = st.y - (y + rt);
            if u < v1 {
                return v3(st.x, st.y - u, st.z);
            }
            u -= v1;
            if u < q {
                let (s, c) = ((u / rt).sin(), (u / rt).cos());
                let x = rt - rt * c;
                return v3(st.x + ex * x, y + rt - rt * s, st.z + ez * x);
            }
            u -= q;
            x0 = rt;
        }
        let lv = hd - rt - x0;
        if u < lv {
            let x = x0 + u;
            return v3(st.x + ex * x, y, st.z + ez * x);
        }
        u -= lv;
        if u < q {
            let (s, c) = ((u / rt).sin(), (u / rt).cos());
            let x = hd - rt + rt * s;
            return v3(st.x + ex * x, y + rt - rt * c, st.z + ez * x);
        }
        u -= q;
        v3(a.x, y + rt + u, a.z)
    }
    // (we_knot)
    fn knot(&self, i: u32, j: u32) -> [f32; 3] {
        let s0 = self.s0(i);
        if j == 0 {
            return [self.t_out(i), s0, self.aw(i, WE_R_VOUT)];
        }
        if j == 3 {
            return [self.t_in(i), s0 + self.alen(i), self.aw(i, WE_R_VIN)];
        }
        let h = [self.aw(i, WE_R_H0), self.aw(i, WE_R_H0 + 1), self.aw(i, WE_R_H0 + 2), self.aw(i, WE_R_H0 + 3)];
        if h[0] < 0.0 {
            return [-1.0, 0.0, 0.0];
        }
        let half = 0.5 * h[3] * (h[1] - h[0]);
        if j == 1 { [h[0], s0 + h[2] - half, h[3]] } else { [h[1], s0 + h[2] + half, h[3]] }
    }
    // (we_head)
    fn head(&self, t: f32) -> f32 {
        let n = self.n();
        if n == 0 {
            return -1.0e4;
        }
        let mut a = [self.aw(0, WE_R_RUN_T), self.run_s(0), self.aw(0, WE_R_RUN_V)];
        if t <= a[0] {
            return a[1] + a[2] * (t - a[0]);
        }
        for i in 0..n {
            for j in 0..4 {
                let b = self.knot(i, j);
                if b[0] < 0.0 {
                    continue;
                }
                if t <= b[0] {
                    let dt = b[0] - a[0];
                    let u = ((t - a[0]) / dt).clamp(0.0, 1.0);
                    let (u2, u3) = (u * u, u * u * u);
                    return (2.0 * u3 - 3.0 * u2 + 1.0) * a[1] + (u3 - 2.0 * u2 + u) * (a[2] * dt) + (-2.0 * u3 + 3.0 * u2) * b[1] + (u3 - u2) * (b[2] * dt);
                }
                a = b;
            }
        }
        a[1] + a[2] * (t - a[0])
    }
    // (wef_knot, wef_tb, wef_ti)
    fn hole(&self, h: u32) -> V3 {
        if h & 1 == 0 { self.arch_from(h / 2) } else { self.arch_to(h / 2) }
    }
    fn tb(&self, h: u32) -> f32 {
        if h & 1 == 0 { self.t_out(h / 2) } else { -1.0e4 }
    }
    fn ti(&self, h: u32) -> f32 {
        if h & 1 == 1 { self.t_in(h / 2) } else { -1.0e4 }
    }
    fn lw(&self, i: u32, w: usize) -> f32 {
        if self.w(WE_LAND_T) < 0.5 || i >= self.n() {
            return -1.0;
        }
        let v = self.w(WE_LAND_T + 224 + 16 * i as usize + w);
        if v > 0.0 { v } else { -1.0 }
    }
    fn tail_in(&self, h: u32) -> f32 {
        let i = h / 2;
        let lw = self.lw(i + 1, 11);
        if lw > 0.0 {
            return lw;
        }
        self.t_in(i) + LEN / self.aw(i, WE_R_VIN).max(60.0)
    }
    fn tail_out(&self, h: u32) -> f32 {
        let i = h / 2;
        let lw = self.lw(i, 12);
        if lw > 0.0 {
            return lw;
        }
        self.tail_in(h + 1) - self.alen(i) / self.aw(i, WE_R_VIN).max(60.0)
    }
    fn sb(&self, h: u32) -> f32 {
        let i = h / 2;
        if i == 0 {
            return 1.0;
        }
        let ap = self.aw(i, WE_R_APEX);
        (0.45 + 0.4 * (ap.max(1.0) / APEX).sqrt()).clamp(0.45, 0.85) * (0.9 + 0.2 * fh21(i as f32, 3.7))
    }
    fn bs(&self, h: u32) -> f32 {
        let i = h / 2;
        let ap = self.aw(i, WE_R_APEX);
        let last = i + 1 == self.n() || self.aw(i, WE_R_H0) >= 0.0;
        (0.4 + 0.6 * (ap.max(1.0) / APEX).sqrt()).clamp(0.5, 1.0) * if last { 1.0 } else { 0.85 }
    }
    fn run_sink_dur(&self, i: u32) -> f32 {
        let (s0, s1) = (self.lw(i, 6), self.lw(i, 7));
        if s0 > 0.0 && s1 > s0 {
            return s1 - s0;
        }
        (self.run_len(i) / self.aw(i, WE_R_VIN).max(60.0)).clamp(3.0, 9.0)
    }
    fn run_sink(&self, i: u32) -> f32 {
        let (s0, s1) = (self.lw(i, 6), self.lw(i, 7));
        if s0 > 0.0 && s1 > s0 {
            return s0;
        }
        let end = self.tail_out(2 * i) + 0.3;
        let dur = (self.run_len(i) / self.aw(i, WE_R_VIN).max(60.0)).clamp(3.0, 9.0);
        end - dur
    }
    fn eye3(&self, i: usize) -> V3 {
        v3(self.w(WE_EYE_T + i), self.w(WE_EYE_T + i + 1), self.w(WE_EYE_T + i + 2))
    }
    // (wef_tip)
    fn tip(&self) -> f32 {
        let tp = self.w(WE_EYE_T + 8);
        if tp > 0.0 { tp } else { self.w(WE_EYE_T + 1) }
    }
    // (wef_run_headx)
    fn headx(&self, i: u32, tau: f32, f: V3, d: (f32, f32)) -> f32 {
        let p = self.run_at(i, (self.head(tau) - self.run_s(i)).clamp(0.0, self.run_len(i)));
        (p.x - f.x) * d.0 + (p.z - f.z) * d.1
    }
}

/// What the pieces of a hole need of it at a time (the pieces' part of wef_hk).
#[derive(Clone, Copy)]
struct Hk {
    k: u32,
    tb: f32,
    ab: f32,
    ai: f32,
    sb: f32,
    bs: f32,
    tout: f32,
    climb: f32,
    vout: f32,
}
fn hk(w: &Wd, k: u32, t: f32) -> Hk {
    let ab = t - w.tb(k);
    let ai = t - w.ti(k);
    let bite = k & 1 == 1;
    let tout = if bite { -1.0e4 } else { w.tail_out(k) };
    let climb = if ab > 0.3 && t < tout + 1.0 { (w.head(t) - w.s0(k / 2)).max(0.0).min(90.0) } else { 0.0 };
    Hk { k, tb: w.tb(k), ab, ai, sb: w.sb(k), bs: if bite { w.bs(k) } else { 1.0 }, tout, climb, vout: w.aw(k / 2, WE_R_VOUT) }
}
/// How many of class cls a hole throws before its distance and the detail cut them (wef_pn at full count), and the
/// count they are cut from (0: never cut).
fn pn(cls: u32, h: &Hk) -> (u32, f32) {
    match cls {
        0 => ((80.0 * h.sb) as u32, 80.0 * h.sb),
        1 => ((13.0 * h.sb + 0.5) as u32, 0.0),
        2 => ((28.0 * h.sb) as u32, 28.0 * h.sb),
        3 => (26, 0.0),
        _ => ((100.0 * h.bs) as u32, 100.0 * h.bs),
    }
}

/// One piece at one time: from its hole (pc), its half sizes, its bound's half sizes, axis, angle, block, life.
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct Pc {
    pub c: V3,
    pub e: V3,
    pub eb: V3,
    pub ax: V3,
    pub an: f32,
    pub kind: u32,
    pub live: f32,
}
/// wef_piece (with `full`): piece i of class cls of the hole hk at the class's age a. Its life is 0 out of its window
/// (where wef_piece returned early) but its place is worked out all the same, for the tick's extrapolation.
fn piece(cls: u32, i: u32, h: &Hk, a: f32, seed: u32) -> Pc {
    let mut r = Rng(pcg(i.wrapping_mul(9781).wrapping_add(h.k.wrapping_mul(6271)).wrapping_add(cls.wrapping_mul(3343)).wrapping_add(seed.wrapping_mul(101))));
    let mut o = Pc::default();
    let tw = std::f32::consts::TAU;
    match cls {
        0 | 4 => {
            // (0 the breach's crown, 4 the bite's splash)
            let (td, tau, dir, p0, v0, floor_r) = if cls == 0 {
                let td = 0.02 + 0.3 * r.u() * r.u();
                let tau = a - td;
                let th = tw * r.u();
                let dir = v3(th.cos(), 0.0, th.sin());
                let r0 = R * (0.35 + 0.95 * r.u());
                let vup = h.sb * (42.0 + 78.0 * r.u().powf(0.65)) * (1.15 - 0.4 * r0 / R);
                let vout = 8.0 + 36.0 * r.u();
                (td, tau, dir, dir * r0 + v3(0.0, 2.0, 0.0), dir * vout + v3(0.0, vup, 0.0), R + 4.0)
            } else {
                let td = 0.1 + 0.45 * r.u();
                let tau = a - td;
                let th = tw * r.u();
                let dir = v3(th.cos(), 0.0, th.sin());
                let r0 = R + 2.0 + 16.0 * r.u();
                let vup = h.bs * (55.0 + 80.0 * r.u().powf(0.6));
                let vout = 14.0 + 42.0 * r.u();
                (td, tau, dir, dir * r0, dir * vout + v3(0.0, vup, 0.0), R + 10.0)
            };
            let _ = (td, dir);
            let pc = wef_fly(p0, v0, tau, 0.06, 24.0);
            o.c = pc;
            let floor_y = if pc.len_xz() < floor_r { -40.0 } else { -1.5 };
            o.live = if tau <= 0.0 { 0.0 } else { smoothstep(floor_y - 1.0, floor_y + 0.8, pc.y) * smoothstep(0.0, 0.05, tau) };
            let s = 0.5 * (0.9 + 2.4 * r.u().powf(1.6));
            o.eb = v3(s, s, s);
            o.e = o.eb.mulv(v3(1.0, 0.75 + 0.5 * r.u(), 0.8 + 0.4 * r.u()));
            o.kind = wef_kind(if cls == 0 { r.u() } else { r.u() * 0.94 });
            let (x, y, z) = (r.u(), r.u(), r.u());
            o.ax = (v3(x, y, z) - v3(0.5, 0.5, 0.5) + v3(0.0, 0.0, 1.0e-3)).norm();
            o.an = (1.0 + 3.5 * r.u()) * tau;
        }
        1 => {
            // (the breach's slabs)
            let n = pn(1, h).0 as f32;
            let th = (i as f32 + 0.8 * r.u()) / n * tw + 1.7 * h.k as f32;
            let dir = v3(th.cos(), 0.0, th.sin());
            let tg = v3(-dir.z, 0.0, dir.x);
            let r0 = 4.0 + 30.0 * r.u();
            let tip = 0.1 + 0.4 * r.u() * (1.0 - r0 / 40.0);
            let vb = h.vout.max(40.0);
            let ew = 4.0 + 5.0 * r.u().powf(1.3);
            let ed = 3.5 + 4.0 * r.u();
            let eh = (1.5 + 2.5 * r.u()).max(0.4 * ew.min(ed));
            let rr = r0.min(R - 1.0);
            let sag = R - (R * R - rr * rr).max(0.0).sqrt();
            let tilt = -((r0 / R).min(0.95)).asin();
            let vout = 10.0 + 24.0 * r.u();
            let spin = -(0.35 + 1.1 * r.u());
            let tree = r.u() < 0.4;
            let ar = a.min(tip);
            let mut pc = dir * (r0 * (1.0 + 0.35 * ar / tip)) + v3(0.0, vb * ar - sag + eh, 0.0);
            let mut an = tilt * smoothstep(0.0, tip, a);
            if a > tip {
                pc = wef_fly(pc, dir * vout + v3(0.0, vb * 0.7, 0.0), a - tip, 0.08, 24.0);
                an = tilt + spin * (a - tip);
            }
            o.c = pc;
            let floor_y = if pc.len_xz() < R + 6.0 { -45.0 } else { -2.0 };
            o.live = smoothstep(floor_y - 3.0, floor_y + 1.0, pc.y + eh);
            o.eb = v3(ed, eh + if tree { 8.0 } else { 0.0 }, ew);
            o.e = v3(ed, eh, ew);
            o.kind = if tree { 11 } else { 10 };
            o.ax = tg;
            o.an = an;
        }
        2 => {
            // (the pour; none while the head has not climbed)
            let p = 1.7;
            let ph = r.u();
            let lt = fract(a / p + ph) * p;
            let th = tw * r.u();
            let dir = v3(th.cos(), 0.0, th.sin());
            let y0 = (0.15 + 0.85 * r.u()) * h.climb;
            let pc = dir * (R + 1.0 + 3.0 * lt) + v3(0.0, y0 - 12.0 * lt * lt, 0.0);
            let pour = ((-(a - 0.3) / 4.0).exp() + 0.3) * smoothstep(h.tout + 1.0, h.tout - 1.0, a + h.tb);
            o.c = pc;
            o.live = if h.climb <= 0.0 { 0.0 } else { smoothstep(0.0, 0.12, lt) * smoothstep(-2.0, 1.0, pc.y) * smoothstep(0.1, 0.4, pour) * smoothstep(0.3, 0.6, a) };
            let s = 0.5 * (0.8 + 1.8 * r.u());
            o.eb = v3(s, s, s);
            o.e = o.eb;
            o.kind = wef_kind(r.u());
            let (x, y, z) = (r.u(), r.u(), r.u());
            o.ax = (v3(x, y, z) - v3(0.5, 0.5, 0.5) + v3(0.0, 0.0, 1.0e-3)).norm();
            o.an = (1.0 + 3.0 * r.u()) * lt;
        }
        _ => {
            // (the bite's slabs: ten in the mouth's circle, the rest its rim)
            let inner = i < 10;
            let mut th = i as f32 * 2.39996 + 0.9 * h.k as f32;
            let mut r0 = 40.0 * ((i as f32 + 0.5) / 10.0).sqrt();
            let mut t0 = 0.02 + 0.18 * r.u();
            if !inner {
                th = ((i - 10) as f32 + 0.7 * r.u()) / 16.0 * tw;
                r0 = R + 12.0 + 12.0 * r.u();
                t0 = 0.3 + 2.0 * r.u();
            }
            let tau = a - t0;
            let dir = v3(th.cos(), 0.0, th.sin());
            let tg = v3(-dir.z, 0.0, dir.x);
            let mut ew = 5.0 + 3.0 * r.u();
            let mut ed = 4.5 + 2.5 * r.u();
            let eh = (1.6 + 1.6 * r.u()).max(0.4 * ew.min(ed));
            let tree = !inner && r.u() < 0.4;
            let (pc, an);
            if inner {
                pc = dir * r0 * (1.0 - 0.45 * smoothstep(0.0, 1.2, tau)) + v3(0.0, -eh - 15.0 * tau * tau, 0.0);
                an = 0.9 * smoothstep(0.0, 1.0, tau);
            } else {
                ew = 6.0 + 3.0 * r.u();
                ed = 5.0 + 2.5 * r.u();
                pc = dir * (r0 - 16.0 * smoothstep(0.3, 2.2, tau)) + v3(0.0, -eh - 3.0 * tau - 12.0 * tau * tau, 0.0);
                an = 1.15 * smoothstep(0.0, 1.6, tau);
            }
            o.c = pc;
            o.live = if tau <= 0.0 { 0.0 } else { smoothstep(-80.0, -55.0, pc.y) };
            o.eb = v3(ed, eh + if tree { 8.0 } else { 0.0 }, ew);
            o.e = v3(ed, eh, ew);
            o.kind = if tree { 11 } else { 10 };
            o.ax = tg;
            o.an = an;
        }
    }
    o
}

/// A run's clods' numbers at a time (wef_pieces' run loop's, before its places).
#[derive(Clone, Copy)]
struct RunT {
    active: bool,
    f: V3,
    tt: V3,
    len: f32,
    d: (f32, f32),
    lo: f32,
    hi: f32,
    xh: f32,
    th0: f32,
    tv: f32,
}
const RUN_LIFE: f32 = 2.8;
const RUN_SP: f32 = 1.3;
fn run_t(w: &Wd, r: u32, t: f32) -> RunT {
    let rt0 = w.aw(r, WE_R_RUN_T);
    let rt1 = w.t_out(r);
    let active = !(t < rt0 || t > rt1 + 3.0 || t > w.run_sink(r));
    let f = w.run_from(r);
    let tt = w.arch_from(r);
    let (dx, dz) = (tt.x - f.x, tt.z - f.z);
    let len = (dx * dx + dz * dz).sqrt().max(1.0);
    let d = (dx / len, dz / len);
    let tb0 = (t - RUN_LIFE).max(rt0);
    let th0 = t.min(rt1);
    let xh = w.headx(r, th0, f, d);
    let xb = w.headx(r, tb0, f, d);
    let lo = xb.min(xh).max(10.0);
    let hi = xb.max(xh).min(len - 30.0);
    let tv = (th0 - tb0) / (xh - xb).abs().max(1.0);
    RunT { active: active && hi > lo, f, tt, len, d, lo, hi, xh, th0, tv }
}
fn sign(x: f32) -> f32 {
    if x > 0.0 {
        1.0
    } else if x < 0.0 {
        -1.0
    } else {
        0.0
    }
}
/// A run's clod (place kk, q of three) at time t, as the run loop has it: its middle from the origin, how high it has
/// flown (pw.y), its life, angle, axis, block, its size before the distance grows it and whether it is kept far off.
fn run_clod(rt: &RunT, r: u32, kk: i32, q: u32, t: f32) -> (Pc, f32, f32, bool) {
    let xk = kk as f32 * RUN_SP;
    let tl = rt.th0 - (rt.xh - xk).abs() * rt.tv;
    let a = t - tl;
    let inwin = rt.active && kk >= (rt.lo / RUN_SP).floor() as i32 && kk <= (rt.hi / RUN_SP).ceil() as i32 && a > 0.0 && a <= RUN_LIFE;
    let id = (kk as u32).wrapping_mul(3).wrapping_add(q);
    let sd = 131 + r;
    let big = wef_ph(id, sd, 1);
    let es0 = mix(0.4, 3.0, big * big);
    let vl = (wef_ph(id, sd, 2) - 0.5) * 68.0;
    let up = mix(50.0, 8.0, big) * (0.6 + 0.4 * wef_ph(id, sd, 3));
    let e3 = v3(rt.d.0, 0.0, rt.d.1);
    let side = v3(rt.d.1, 0.0, -rt.d.0);
    let v0 = side * (sign(vl) * (2.0 + 8.0 * wef_ph(id, sd, 4))) - e3 * (1.0 + 6.0 * wef_ph(id, sd, 5)) + v3(0.0, up, 0.0);
    let a2 = a - 0.15 * wef_ph(id, sd, 6);
    let pw = wef_fly(V3::default(), v0, a2, 0.05, 26.0);
    let gy = mix(rt.f.y, rt.tt.y, (xk / rt.len).clamp(0.0, 1.0));
    let c = rt.f + e3 * xk + side * vl + v3(0.0, gy - rt.f.y, 0.0) + pw;
    let mut o = Pc { c, ..Default::default() };
    o.live = if inwin && a2 > 0.0 { smoothstep(0.0, 0.06, a2) } else { 0.0 };
    o.ax = (v3(wef_ph(id, sd, 9), wef_ph(id, sd, 10), wef_ph(id, sd, 11)) - v3(0.5, 0.5, 0.5) + v3(0.0, 0.0, 1.0e-3)).norm();
    o.an = (1.0 + 4.0 * wef_ph(id, sd, 12)) * a2;
    o.kind = wef_kind(wef_ph(id, sd, 13) * 0.93);
    (o, pw.y, es0, big >= 0.6)
}
/// The spit's block i at t (none out of its two seconds).
fn spit(w: &Wd, i: u32, t: f32) -> Pc {
    let tf = w.tip();
    let tau = t - tf + 0.05;
    let p0 = w.eye3(9);
    let vv = w.eye3(12);
    let dl = (vv + v3(1.0e-4, 1.0e-4, 1.0e-4)).norm();
    let ve = vv.len();
    let h3 = v3(wef_ph(i, 171, 1), wef_ph(i, 171, 2), wef_ph(i, 171, 3)) - v3(0.5, 0.5, 0.5);
    let v = dl * (ve * (0.9 + 0.5 * wef_ph(i, 171, 4))) + h3 * 18.0 + v3(0.0, 5.0, 0.0);
    let c = p0 + h3 * 6.0 + wef_fly(V3::default(), v, tau, 0.08, 24.0);
    let on = w.w(WE_EYE_T + 8) > 0.0 && t > tf && t < tf + 2.2;
    Pc {
        c,
        e: v3(0.5, 0.5, 0.5),
        eb: v3(0.5, 0.5, 0.5),
        ax: (h3 + v3(0.0, 0.0, 1.0e-3)).norm(),
        an: (2.0 + 4.0 * wef_ph(i, 171, 5)) * tau,
        kind: wef_kind(wef_ph(i, 171, 6) * 0.97),
        live: if on { smoothstep(2.2, 1.6, t - tf) } else { 0.0 },
    }
}

/// wef_hk's billows and clumps of hole k at t (from the origin), into `o` (PCS_HKS words). A billow or clump not yet
/// born, or gone, has radius and life 0 but its place worked out all the same, so the pass can take it between ticks.
fn hk_words(w: &Wd, k: u32, t: f32, o: &mut [u32]) {
    let hh = w.hole(k);
    let ab = t - w.tb(k);
    let ai = t - w.ti(k);
    let bite_hole = k & 1 == 1;
    let bs = if bite_hole { w.bs(k) } else { 1.0 };
    let tw = std::f32::consts::TAU;
    let put = |o: &mut [u32], at: usize, v: &[f32]| {
        for (i, x) in v.iter().enumerate() {
            o[at + i] = x.to_bits();
        }
    };
    let mut cmax = (0.0f32, -1.0e9f32);
    for m in 0..WEF_NC {
        let tau = ai - (0.1 + 0.35 * wef_ph(m, k, 61));
        let on = bite_hole && tau > 0.0 && ai <= 10.0;
        let th = (m as f32 + 0.6 * wef_ph(m, k, 62)) / WEF_NC as f32 * tw + 0.7 * k as f32;
        let dir = v3(th.cos(), 0.0, th.sin());
        let p0 = dir * (R + 3.0) + v3(0.0, 2.0, 0.0);
        let v0 = dir * (18.0 + 26.0 * wef_ph(m, k, 63)) + v3(0.0, bs * (60.0 + 60.0 * wef_ph(m, k, 64)), 0.0);
        let ph = wef_fly(p0, v0, tau, 0.08, 24.0);
        let pt = wef_fly(p0, v0, (tau - 0.45).max(0.0), 0.08, 24.0);
        let rad = bs * (5.0 + 5.0 * wef_ph(m, k, 65)) * (0.5 + 0.5 * smoothstep(0.0, 0.3, tau)) + 0.8 * tau;
        let (hp, tp) = (hh + ph, hh + pt);
        let life = smoothstep(-8.0, 2.0, ph.y) * (-(tau - 3.0).max(0.0) / 2.0).exp();
        let r = if on { rad } else { 0.0 };
        put(o, 90 + 9 * m as usize, &[hp.x, hp.y, hp.z, r, tp.x, tp.y, tp.z, if on { rad * 1.5 + 1.0 } else { 0.0 }, if on { life } else { 0.0 }]);
        if on {
            let rr = ph.len_xz().max(pt.len_xz()) + rad * 2.0;
            cmax = (cmax.0.max(rr), cmax.1.max(ph.y.max(pt.y) + rad * 2.0));
        }
    }
    let mut pmax = (0.0f32, -1.0e9f32);
    let bite = ai > 0.0 && (ab <= 0.0 || ai < ab);
    let a0 = if bite { ai - 0.15 } else { ab };
    let sz = if bite { 1.1 * bs } else { w.sb(k) };
    for m in 0..WEF_NP {
        let a = a0 - (0.04 + if bite { 0.8 } else { 1.3 } * wef_ph(m, k, 51).powf(1.5));
        let on = a > 0.0 && a0 <= 12.0;
        let th = (m as f32 + 0.6 * wef_ph(m, k, 52)) / WEF_NP as f32 * tw + k as f32;
        let dir = v3(th.cos(), 0.0, th.sin());
        let top = sz * (16.0 + 34.0 * wef_ph(m, k, 53));
        let y = top * (1.0 - (-a / 1.3).exp()) - 1.4 * (a - 6.0).max(0.0);
        let rr = R + 6.0 + 16.0 * wef_ph(m, k, 54) + if bite { 24.0 } else { 12.0 } * (1.0 - (-a / 2.0).exp()) + 2.5 * a;
        let rad = (sz * (5.0 + 10.0 * (1.0 - (-a / 1.2).exp())) + 0.6 * a).min(16.0);
        let c = hh + dir * rr + v3(0.0, y.max(rad * 0.4), 0.0);
        let life = smoothstep(0.0, 0.25, a) * (-(a - 2.0).max(0.0) / 2.2).exp();
        put(o, 9 * m as usize, &[c.x, c.y, c.z, if on { rad } else { 0.0 }, -dir.z, 0.0, dir.x, -1.6 * (1.0 - (-a / 2.2).exp()), if on { life } else { 0.0 }]);
        if on {
            pmax = (pmax.0.max(rr + rad * 1.4), pmax.1.max(y.max(rad * 0.4) + rad * 1.4));
        }
    }
    put(o, 216, &[pmax.0, pmax.1, cmax.0, cmax.1]);
    // (the rest of wef_hk's: the reach, the climb, the tails, the sizes)
    let h = hk(w, k, t);
    let (rx, ry) = hole_reach(w, k, t);
    let tin = if bite_hole { w.tail_in(k) } else { -1.0e4 };
    put(o, 220, &[rx, ry, h.climb, h.tout, tin, h.sb, h.bs]);
}
/// wef_hole_reach less the dome's part and its cap (the pass adds those).
fn hole_reach(w: &Wd, k: u32, t: f32) -> (f32, f32) {
    let (mut r, mut top) = (0.0f32, 0.0f32);
    const LIFE: f32 = 16.0;
    const FALL: f32 = 32.0;
    let ab = t - w.tb(k);
    if ab > 0.0 && ab < LIFE {
        let s = w.sb(k);
        let rf = R + 10.0 + s * 75.0 * (1.0 - (-ab / 2.5).exp()) + 1.0 * ab;
        r = (rf + 30.0).max(R + 34.0 + 3.5 * ab + 40.0 * s);
        top = s * 80.0 + 30.0;
        if ab < 6.0 {
            top = top.max(s * 125.0);
        }
    }
    let ai = t - w.ti(k);
    if k & 1 == 1 && ai > -1.8 && ai < LIFE {
        let s = w.bs(k);
        let a = ai.max(0.0);
        let rf = 45.0 + 310.0 * s * (1.0 - (-a / 1.8).exp());
        let rc = (R + 17.0) - 8.0 * smoothstep(0.0, 5.0, a);
        let wid = 10.0 + 2.2 * a.min(6.0) + 0.5 * (a - 6.0).max(0.0);
        r = r.max(95.0f32.max(rc + 2.6 * wid));
        top = top.max(1.1 * s * 80.0 + 30.0);
        if ai > 0.0 && ai < 12.0 {
            r = r.max(rf + 14.0);
        }
        if ai > 0.0 && ai < 10.0 {
            top = top.max(250.0);
            r = r.max(200.0);
        }
    }
    let age = if k & 1 == 1 { ai } else { ab };
    if age > 2.0 && age < LIFE {
        r = r.max(R + 12.0 + 3.0 * FALL);
        top = top.max(14.0);
    }
    (r, top)
}

/// f32 to IEEE half (round to nearest even), as WGSL's unpack2x16float reads it.
pub(crate) fn f16_bits(x: f32) -> u16 {
    let b = x.to_bits();
    let sign = ((b >> 16) & 0x8000) as u16;
    let e = ((b >> 23) & 0xff) as i32;
    let m = b & 0x7f_ffff;
    if e == 0xff {
        return sign | 0x7c00 | if m != 0 { 0x200 } else { 0 };
    }
    let e2 = e - 127 + 15;
    if e2 >= 0x1f {
        return sign | 0x7bff;
    }
    if e2 <= 0 {
        if e2 < -10 {
            return sign;
        }
        let m = m | 0x80_0000;
        let shift = (14 - e2) as u32;
        let half = 1u32 << (shift - 1);
        let r = m & ((1 << shift) - 1);
        let mut v = m >> shift;
        if r > half || (r == half && v & 1 == 1) {
            v += 1;
        }
        return sign | v as u16;
    }
    let r = m & 0x1fff;
    let mut v = ((e2 as u32) << 10) | (m >> 13);
    if r > 0x1000 || (r == 0x1000 && v & 1 == 1) {
        v += 1;
    }
    if v >= 0x7c00 {
        return sign | 0x7bff;
    }
    sign | v as u16
}
fn pk16(a: f32, b: f32) -> u32 {
    f16_bits(a) as u32 | (f16_bits(b) as u32) << 16
}
fn snorm16(x: f32) -> u32 {
    ((x.clamp(-1.0, 1.0) * 32767.0).round() as i32 as i16) as u16 as u32
}
/// A unit axis as two snorm16 (octahedral: the pass's wep_axis).
fn oct(a: V3) -> u32 {
    let s = a.x.abs() + a.y.abs() + a.z.abs();
    let (mut x, mut y) = (a.x / s, a.y / s);
    if a.z < 0.0 {
        let sg = |v: f32| if v >= 0.0 { 1.0 } else { -1.0 };
        (x, y) = ((1.0 - y.abs()) * sg(x), (1.0 - x.abs()) * sg(y));
    }
    snorm16(x) | snorm16(y) << 16
}

/// A piece as written: its words and its bound's radius at its most alive over the tick.
struct Rec {
    w: [u32; PCS_W],
    c0: V3,
    v: V3,
    rmax: f32,
}
/// How fast `at(t)` moves at t, taken over PCS_EPS (backwards where a place jumps, as the pour's clods do as they start
/// again from the top).
fn rates(at: &dyn Fn(f32) -> Pc, t: f32, p: &Pc) -> (V3, f32) {
    let q = at(t + PCS_EPS);
    if (q.c - p.c).len() < 8.0 {
        return ((q.c - p.c) * (1.0 / PCS_EPS), (q.an - p.an) / PCS_EPS);
    }
    let m = at(t - PCS_EPS);
    ((p.c - m.c) * (1.0 / PCS_EPS), (p.an - m.an) / PCS_EPS)
}
#[allow(clippy::too_many_arguments)]
fn rec(base: V3, p: &Pc, v: V3, dan: f32, lb: f32, kind: u32, cls: u32, idx: u32, e_w: [u32; 2], rb: f32, rmax: f32, extra: u32) -> Rec {
    let c0 = base + p.c;
    let block = if p.kind == 11 { 7 } else if p.kind == 10 { 6 } else { p.kind };
    let meta = kind | cls << 2 | block << 5 | extra | idx << 16;
    let w = [
        c0.x.to_bits(),
        c0.y.to_bits(),
        c0.z.to_bits(),
        pk16(v.x, v.y),
        pk16(v.z, p.live),
        pk16((lb - p.live) / PCS_DT, dan),
        pk16(rb, 0.0),
        e_w[0],
        e_w[1],
        oct(p.ax),
        meta,
        p.an.rem_euclid(std::f32::consts::TAU).to_bits(),
    ];
    Rec { w, c0, v, rmax }
}
/// A source's pieces and its own words.
struct Src {
    words: [u32; 8],
    recs: Vec<Rec>,
    sort: bool,
}

/// The live pieces at strike time t (seed: the strike's, params[8]), by source.
fn we_pieces_srcs(data: &[u32], t: f32, seed: f32) -> (Vec<Src>, u64) {
    let w = Wd(data);
    let seed = seed as u32;
    let n = w.n();
    let mut out = Vec::new();
    let mut evals = 0u64;
    let t1 = t + PCS_DT;
    for k in 0..2 * n {
        let (h0, h1) = (hk(&w, k, t), hk(&w, k, t1));
        let breach = |h: &Hk| h.ab > 0.0 && h.ab < 9.0;
        let bite = |h: &Hk| h.ai > 0.0 && h.ai < 8.0;
        for cls in 0..5u32 {
            let open = |h: &Hk| if cls < 3 { breach(h) && (cls != 2 || h.climb > 0.0) } else { bite(h) };
            if !open(&h0) && !open(&h1) {
                continue;
            }
            let (cnt, base) = pn(cls, &h0);
            let (cnt, base) = (cnt.max(pn(cls, &h1).0), base.max(pn(cls, &h1).1));
            let hc = w.hole(k);
            let mut recs = Vec::new();
            // (the hole's numbers at the four times a piece is looked at, worked out once)
            let hs = [t, t1, t + PCS_EPS, t - PCS_EPS].map(|tt| (tt, hk(&w, k, tt)));
            for i in 0..cnt {
                let at = |tt: f32| {
                    let h = hs.iter().find(|x| x.0 == tt).map_or_else(|| hk(&w, k, tt), |x| x.1);
                    let mut p = piece(cls, i, &h, if cls < 3 { h.ab } else { h.ai }, seed);
                    if !open(&h) {
                        p.live = 0.0;
                    }
                    p
                };
                let p = at(t);
                let lb = at(t1).live;
                evals += 2;
                if p.live.max(lb) <= 0.02 {
                    continue;
                }
                let (v, dan) = rates(&at, t, &p);
                evals += 1;
                let rb = p.eb.len();
                recs.push(rec(hc, &p, v, dan, lb, 0, cls, i, [pk16(p.e.x, p.e.y), pk16(p.e.z, 0.0)], rb, rb * p.live.max(lb), 0));
            }
            if !recs.is_empty() {
                let mut sw = [0u32; 8];
                sw[0] = cls << 4;
                sw[1..4].copy_from_slice(&[hc.x.to_bits(), hc.y.to_bits(), hc.z.to_bits()]);
                sw[4] = base.to_bits();
                out.push(Src { words: sw, recs, sort: true });
            }
        }
    }
    for r in 0..n {
        let (ra, rb_) = (run_t(&w, r, t), run_t(&w, r, t1));
        if !ra.active && !rb_.active {
            continue;
        }
        let mut lo = i32::MAX;
        let mut hi = i32::MIN;
        for x in [&ra, &rb_] {
            if x.active {
                lo = lo.min((x.lo / RUN_SP).floor() as i32);
                hi = hi.max((x.hi / RUN_SP).ceil() as i32);
            }
        }
        let re = run_t(&w, r, t + PCS_EPS);
        let rm = run_t(&w, r, t - PCS_EPS);
        let mut recs = Vec::new();
        for kk in lo..=hi {
            for q in 0..3u32 {
                let (p, pwy, es0, keep) = run_clod(&ra, r, kk, q, t);
                let (pbb, pwyb, _, _) = run_clod(&rb_, r, kk, q, t1);
                let lb = pbb.live;
                evals += 2;
                if p.live.max(lb) <= 0.0 {
                    continue;
                }
                // (a clod sunk under the land by its size is gone; its size grows with the distance at most 2.2 times)
                if pwy.max(pwyb) < -es0 * 2.2 {
                    continue;
                }
                let fwd = run_clod(&re, r, kk, q, t + PCS_EPS);
                let (pe, dtt) = if (fwd.0.c - p.c).len() < 8.0 { (fwd, PCS_EPS) } else { (run_clod(&rm, r, kk, q, t - PCS_EPS), -PCS_EPS) };
                evals += 2;
                let v = (pe.0.c - p.c) * (1.0 / dtt);
                let dan = (pe.0.an - p.an) / dtt;
                let dpw = (pe.1 - pwy) / dtt;
                let rmax = 1.7321 * ((es0 * 2.2).min(4.2) * p.live.max(lb) + 0.6);
                recs.push(rec(V3::default(), &p, v, dan, lb, 1, q, kk as u32, [pk16(es0, pwy), pk16(dpw, 0.0)], 0.0, rmax, u32::from(keep) << 9));
            }
        }
        if !recs.is_empty() {
            let mut sw = [0u32; 8];
            sw[0] = 1;
            sw[1..4].copy_from_slice(&[ra.f.x.to_bits(), ra.f.y.to_bits(), ra.f.z.to_bits()]);
            sw[4] = ra.d.0.to_bits();
            sw[5] = ra.d.1.to_bits();
            sw[6] = ra.xh.to_bits();
            sw[7] = ((re.xh - ra.xh) / PCS_EPS).to_bits();
            out.push(Src { words: sw, recs, sort: false });
        }
    }
    {
        let mut recs = Vec::new();
        for i in 0..36u32 {
            let at = |tt: f32| spit(&w, i, tt);
            let p = at(t);
            let lb = at(t1).live;
            evals += 2;
            if p.live.max(lb) <= 0.0 {
                continue;
            }
            let (v, dan) = rates(&at, t, &p);
            recs.push(rec(V3::default(), &p, v, dan, lb, 2, 0, i, [pk16(0.5, 0.5), pk16(0.5, 0.0)], 0.9, 0.9, 0));
        }
        if !recs.is_empty() {
            let mut sw = [0u32; 8];
            sw[0] = 2;
            out.push(Src { words: sw, recs, sort: false });
        }
    }
    (out, evals)
}

/// The pieces' table at strike time t (PCS_LEN words, to go at WE_PCS_T), and roughly what working it out cost
/// (instructions, for the meter).
pub(crate) fn we_pieces_words(data: &[u32], t: f32, seed: f32) -> (Vec<u32>, u64) {
    let (mut srcs, evals) = we_pieces_srcs(data, t, seed);
    let mut o = vec![0u32; PCS_LEN];
    let (mut ns, mut nsup, mut ng, mut np) = (0usize, 0usize, 0usize, 0usize);
    let pad = 0.05;
    for s in srcs.iter_mut() {
        if ns >= PCS_NSRC || np >= PCS_NPC {
            break;
        }
        // (a hole's pieces sorted along a curve through their places, so a group's box is small)
        if s.sort && s.recs.len() > PCS_GRPN {
            let (mut lo, mut hi) = (s.recs[0].c0, s.recs[0].c0);
            for r in &s.recs {
                lo = lo.min(r.c0);
                hi = hi.max(r.c0);
            }
            let ext = hi - lo;
            let q = |x: f32, l: f32, e: f32| ((x - l) / e.max(1.0e-3) * 1023.0).clamp(0.0, 1023.0) as u32;
            let spread = |mut x: u32| {
                let mut y = 0u32;
                for b in 0..10 {
                    y |= ((x & 1) << (3 * b)) as u32;
                    x >>= 1;
                }
                y
            };
            s.recs.sort_by_key(|r| spread(q(r.c0.x, lo.x, ext.x)) | spread(q(r.c0.y, lo.y, ext.y)) << 1 | spread(q(r.c0.z, lo.z, ext.z)) << 2);
        }
        o[PCS_SRC + 8 * ns..PCS_SRC + 8 * ns + 8].copy_from_slice(&s.words);
        let g0 = ng;
        for chunk in s.recs.chunks(PCS_GRPN) {
            if ng >= PCS_NGRP || np + chunk.len() > PCS_NPC {
                break;
            }
            let mut lo = v3(f32::MAX, f32::MAX, f32::MAX);
            let mut hi = v3(f32::MIN, f32::MIN, f32::MIN);
            for r in chunk {
                let e = r.c0 + r.v * PCS_DT;
                let rr = r.rmax + pad;
                lo = lo.min(r.c0.min(e) - v3(rr, rr, rr));
                hi = hi.max(r.c0.max(e) + v3(rr, rr, rr));
                o[PCS_PC + PCS_W * np..PCS_PC + PCS_W * (np + 1)].copy_from_slice(&r.w);
                np += 1;
            }
            let b = PCS_GRP + 8 * ng;
            for (j, x) in [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z].iter().enumerate() {
                o[b + j] = x.to_bits();
            }
            o[b + 6] = (np - chunk.len()) as u32 | (chunk.len() as u32) << 16;
            o[b + 7] = ns as u32;
            ng += 1;
        }
        // (the source's groups in boxes of PCS_SUPN)
        let mut g = g0;
        while g < ng && nsup < PCS_NSUP {
            let e = (g + PCS_SUPN).min(ng);
            let mut lo = [f32::MAX; 3];
            let mut hi = [f32::MIN; 3];
            for gg in g..e {
                let b = PCS_GRP + 8 * gg;
                for j in 0..3 {
                    lo[j] = lo[j].min(f32::from_bits(o[b + j]));
                    hi[j] = hi[j].max(f32::from_bits(o[b + 3 + j]));
                }
            }
            let b = PCS_SUP + 8 * nsup;
            for j in 0..3 {
                o[b + j] = lo[j].to_bits();
                o[b + 3 + j] = hi[j].to_bits();
            }
            o[b + 6] = g as u32 | ((e - g) as u32) << 16;
            nsup += 1;
            g = e;
        }
        ns += 1;
    }
    o[0] = 1;
    o[1] = t.to_bits();
    o[2] = ns as u32;
    o[3] = nsup as u32;
    o[4] = ng as u32;
    o[5] = np as u32;
    o[6] = PCS_DT.to_bits();
    // (the jolts' and the lens' events)
    let w = Wd(data);
    let mut ne = 0;
    let mut ev = |o: &mut Vec<u32>, kind: u32, te: f32, s: f32, k: u32, p: V3| {
        if ne < PCS_NEV {
            let b = PCS_EV + 8 * ne;
            o[b..b + 7].copy_from_slice(&[kind, te.to_bits(), s.to_bits(), k, p.x.to_bits(), p.y.to_bits(), p.z.to_bits()]);
            ne += 1;
        }
    };
    for k in 0..2 * w.n() {
        let bite = k & 1 == 1;
        let te = if bite { w.ti(k) } else { w.tb(k) };
        if t - te > -PCS_DT && t - te < 25.0 + PCS_DT {
            ev(&mut o, u32::from(bite), te, if bite { 1.2 * w.bs(k) } else { w.sb(k) }, k, w.hole(k));
        }
    }
    for i in 0..w.n() {
        let (s0, d) = { let a = w.run_sink(i); (a, w.run_sink_dur(i)) };
        if t > s0 - PCS_DT && t < s0 + d + 1.5 + PCS_DT {
            ev(&mut o, 2, s0, d, i, (w.run_from(i) + w.arch_from(i)) * 0.5);
        }
    }
    o[7] = ne as u32;
    // (each hole's billows and clumps, at the tick and the next)
    for k in 0..(2 * w.n()).min(PCS_NHK as u32) {
        for (j, tt) in [t, t + PCS_DT].into_iter().enumerate() {
            let b = PCS_HK + PCS_HKW * k as usize + PCS_HKS * j;
            hk_words(&w, k, tt, &mut o[b..b + PCS_HKS]);
        }
    }
    o[8] = 1;
    // (an evaluation of a piece is a few dozen hashes and an exp or two: ~1,500 instructions as wasm; the boxes and
    // the words about as much again a piece)
    (o, evals * 1_500 + np as u64 * 1_500 + PCS_LEN as u64)
}

/// The tick's pieces into the strike's mod_data, at WE_PCS_T (lib.rs's tick, for the World Eater): what it cost.
pub(crate) fn we_pieces_tick(data: &mut Vec<u32>, t: f32, seed: f32) -> u64 {
    let (w, cost) = we_pieces_words(data, t, seed);
    if data.len() < WE_PCS_T + PCS_LEN {
        data.resize(WE_PCS_T + PCS_LEN, 0);
    }
    data[WE_PCS_T..WE_PCS_T + PCS_LEN].copy_from_slice(&w);
    cost
}
