//! Offscreen pictures of what the Supervolcano leaves: a synthetic land, the real plan's edits made on it in a voxel grid,
//! then a top-down map and views ray-traced with the blocks' own average colours (hu_blocks.rs). `VC_VIEW_OUT=DIR [VC_VIEWS=map,air]
//! cargo test --release vc_land_picture -- --ignored --nocapture` writes DIR/<view>.ppm (magick turns them into anything).
use super::*;
use crate::columns::Answer;
use crate::strike::hu_blocks::HU_BLOCKS;
use std::collections::HashMap;

const R: i32 = 1100;
const W: usize = (2 * R) as usize;
const Y0: i32 = -48;
const H: usize = 300;
const GY: i32 = 65;

/// The voxels and the blocks' names; id 0 air.
struct Vox {
    v: Vec<u8>,
    names: Vec<String>,
    ids: HashMap<String, u8>,
}
impl Vox {
    fn new() -> Self {
        let mut s = Vox { v: vec![0; W * W * H], names: Vec::new(), ids: HashMap::new() };
        s.id("minecraft:air");
        s
    }
    fn id(&mut self, name: &str) -> u8 {
        if let Some(&i) = self.ids.get(name) {
            return i;
        }
        let i = self.names.len() as u8;
        assert!(self.names.len() < 255, "too many blocks");
        self.names.push(name.to_string());
        self.ids.insert(name.to_string(), i);
        i
    }
    #[inline]
    fn at(x: i32, y: i32, z: i32) -> Option<usize> {
        let (i, k, j) = (x + R, z + R, y - Y0);
        if i < 0 || k < 0 || j < 0 || i >= 2 * R || k >= 2 * R || j >= H as i32 {
            return None;
        }
        Some((j as usize * W + k as usize) * W + i as usize)
    }
    fn get(&self, x: i32, y: i32, z: i32) -> u8 {
        Self::at(x, y, z).map_or(0, |i| self.v[i])
    }
    fn set(&mut self, x: i32, y: i32, z: i32, id: u8) {
        if let Some(i) = Self::at(x, y, z) {
            self.v[i] = id;
        }
    }
    /// One above the highest block that is not air.
    fn world_surface(&self, x: i32, z: i32) -> i32 {
        for y in (Y0..Y0 + H as i32).rev() {
            if self.get(x, y, z) != 0 {
                return y + 1;
            }
        }
        Y0
    }
    /// One above the highest block but leaves and what does not block.
    fn motion(&self, x: i32, z: i32) -> i32 {
        for y in (Y0..Y0 + H as i32).rev() {
            let n = &self.names[self.get(x, y, z) as usize];
            if !(n.ends_with("air") || n.ends_with("leaves") || n.ends_with("short_grass") || n.ends_with("dandelion") || n.ends_with("dead_bush") || n.ends_with("mangrove_roots")) {
                return y + 1;
            }
        }
        Y0
    }
}
fn is(name: &str, filter: &str) -> bool {
    match filter.strip_prefix('#') {
        None => name == filter,
        Some(tag) => {
            let n = name.strip_prefix("minecraft:").unwrap_or(name);
            match tag {
                "minecraft:leaves" => n.ends_with("_leaves"),
                "minecraft:logs" => n.ends_with("_log") || n.ends_with("_wood"),
                "minecraft:dirt" => matches!(n, "dirt" | "grass_block" | "coarse_dirt" | "podzol" | "mud" | "rooted_dirt"),
                "minecraft:sand" => n.ends_with("sand"),
                "minecraft:azalea_root_replaceable" => matches!(n, "stone" | "dirt" | "grass_block" | "coarse_dirt" | "sand" | "gravel" | "sandstone" | "terracotta" | "snow_block"),
                _ => panic!("the picture knows no tag {tag}"),
            }
        }
    }
}
fn apply(w: &mut Vox, b: &Blocks) {
    let e = b.edit();
    let pal: Vec<u8> = e.palette.iter().map(|n| w.id(n)).collect();
    // (the heights a surface run counts from, read before any change)
    let mut heights: HashMap<(i32, i32), i32> = HashMap::new();
    for r in &e.runs {
        let base = if r.surface.is_some() { *heights.entry((r.x, r.z)).or_insert_with(|| w.motion(r.x, r.z)) + r.y } else { r.y };
        for y in base..base + r.height as i32 {
            if let Some(f) = r.only {
                let n = &w.names[w.get(r.x, y, r.z) as usize];
                if !is(n, &e.filters[f as usize]) {
                    continue;
                }
            }
            w.set(r.x, y, r.z, pal[r.block as usize]);
        }
    }
}

fn fbm(x: f64, z: f64, s: f64, seed: u32, oct: u32) -> f64 {
    let (mut a, mut t, mut n, mut sc) = (1.0, 0.0, 0.0, s);
    for k in 0..oct {
        t += a * vnoise(x, z, sc, seed + k);
        n += a;
        a *= 0.5;
        sc *= 0.5;
    }
    t / n
}
/// A land something like the game's: rolling hills, a few ridges, rivers and lakes at the sea's level, forests.
fn land(w: &mut Vox) {
    let (grass, dirt, stone, sand, water, log, leaves, tuft, gravel) = (
        w.id("minecraft:grass_block"),
        w.id("minecraft:dirt"),
        w.id("minecraft:stone"),
        w.id("minecraft:sand"),
        w.id("minecraft:water"),
        w.id("minecraft:oak_log"),
        w.id("minecraft:oak_leaves"),
        w.id("minecraft:short_grass"),
        w.id("minecraft:gravel"),
    );
    let sea = GY - 3;
    let seed = std::env::var("VC_LAND_SEED").map_or(5, |v| v.parse().unwrap());
    let height = |x: i32, z: i32| -> (f64, f64) {
        let (fx, fz) = (f64::from(x), f64::from(z));
        let hills = fbm(fx, fz, 420.0, seed, 4) - 0.5;
        let ridge = 1.0 - (2.0 * vnoise(fx + 90.0, fz, 300.0, seed + 11) - 1.0).abs();
        let river = (fbm(fx, fz, 520.0, seed + 21, 3) - 0.5).abs();
        let mut h = 69.0 + 70.0 * hills + 34.0 * ridge.powi(4);
        let cut = (1.0 - river / 0.018).clamp(0.0, 1.0);
        h += (f64::from(sea) - 3.0 - h) * cut.powf(0.6) * 0.9;
        // (the vent's ground kept near GY)
        let near = (1.0 - (fx.hypot(fz) - 200.0) / 200.0).clamp(0.0, 1.0);
        (h + (f64::from(GY) - h) * near, river)
    };
    for z in -R..R {
        for x in -R..R {
            let (h, _) = height(x, z);
            let top = h.floor() as i32;
            let steep = (height(x + 3, z).0 - h).abs().max((height(x, z + 3).0 - h).abs());
            for y in Y0..top - 3 {
                w.set(x, y, z, stone);
            }
            let beach = top <= sea + 1;
            let rock = steep > 5.0;
            for y in top - 3..top {
                w.set(x, y, z, if rock { stone } else if beach { sand } else { dirt });
            }
            w.set(x, top, z, if rock { stone } else if beach { if pick(x * 3 + z * 7, 5) < 0.3 { gravel } else { sand } } else { grass });
            for y in top + 1..=sea {
                w.set(x, y, z, water);
            }
            if top > sea && !rock && !beach && pick(x * 11 + z * 5, 6) < 0.12 {
                w.set(x, top + 1, z, tuft);
            }
        }
    }
    // the trees
    let mut x = -R + 6;
    while x < R - 6 {
        let mut z = -R + 6;
        while z < R - 6 {
            let k = x * 73 + z * 19;
            let (tx, tz) = (x + (pick(k, 7) * 5.0) as i32, z + (pick(k, 8) * 5.0) as i32);
            let forest = fbm(f64::from(tx), f64::from(tz), 170.0, seed + 31, 2);
            let g = w.world_surface(tx, tz) - 1;
            let on = g > sea + 1 && w.names[w.get(tx, g, tz) as usize] == "minecraft:grass_block";
            if on && pick(k, 9) < (forest - 0.42) * 3.5 {
                let t = 4 + (pick(k, 10) * 4.0) as i32;
                for y in g + 1..=g + t {
                    w.set(tx, y, tz, log);
                }
                for dy in -2i32..=2 {
                    let rr = if dy >= 1 { 1 } else { 2 };
                    for dx in -rr..=rr {
                        for dz in -rr..=rr {
                            if (dx * dx + dz * dz + dy * dy) <= 7 && w.get(tx + dx, g + t + dy, tz + dz) == 0 {
                                w.set(tx + dx, g + t + dy, tz + dz, leaves);
                            }
                        }
                    }
                }
            }
            z += 7;
        }
        x += 7;
    }
}

/// The land's answers, as the game gives them.
fn answers(w: &Vox, cols: &mut [u32], bx: i32, bz: i32) {
    let palette: Vec<String> = w.names.clone();
    let mut parts = Vec::new();
    for part in 0..VC_PARTS {
        parts.extend(read_columns(bx, bz, part));
    }
    for lot in parts.chunks(40_000) {
        let per = (VC_BELOW + VC_ABOVE) as usize;
        let mut a = Answer { columns: lot.to_vec(), palette: palette.clone(), bases: Vec::new(), blocks: Vec::with_capacity(lot.len() * per), tints: Vec::new(), per, below: VC_BELOW as i32 };
        for &(x, z) in lot {
            let top = w.world_surface(x, z);
            a.bases.push(Some(top));
            for y in top - VC_BELOW as i32..top + VC_ABOVE as i32 {
                a.blocks.push(u16::from(w.get(x, y, z)));
            }
        }
        take_in(cols, &mut Missing::default(), &a, bx, bz);
    }
}

#[derive(Clone, Copy)]
struct Cam {
    eye: [f64; 3],
    at: [f64; 3],
    fov: f64,
}
fn views() -> Vec<(&'static str, Cam)> {
    let v = |eye: [f64; 3], at: [f64; 3], fov: f64| Cam { eye, at, fov };
    vec![
        ("air570", v([0.0, 300.0, 700.0], [0.0, 40.0, 0.0], 70.0)),
        ("air2", v([-620.0, 420.0, -520.0], [40.0, 30.0, 60.0], 58.0)),
        ("edge", v([120.0, 150.0, 640.0], [40.0, 62.0, 380.0], 70.0)),
        ("rim", v([40.0, 118.0, 296.0], [-40.0, 10.0, -60.0], 75.0)),
        ("lake", v([-60.0, 2.0, -40.0], [100.0, -24.0, 160.0], 70.0)),
        ("wall", v([90.0, -2.0, -120.0], [150.0, 30.0, -300.0], 75.0)),
        ("trees", v([-400.0, 135.0, 495.0], [-250.0, 78.0, 300.0], 62.0)),
        ("crown", v([330.0, 150.0, 330.0], [150.0, 70.0, 190.0], 70.0)),
    ]
}

struct Mat {
    top: [f32; 3],
    side: [f32; 3],
    glow: f32,
    alpha: f32,
}
fn mats(names: &[String]) -> Vec<Mat> {
    let lin = |c: [u8; 3]| c.map(|v| (f32::from(v) / 255.0).powf(2.2));
    names
        .iter()
        .map(|n| {
            let h = HU_BLOCKS.iter().find(|b| b.name == n.split('[').next().unwrap());
            let (mut top, mut side) = h.map_or(([0.5; 3], [0.5; 3]), |b| (lin(b.top), lin(b.side)));
            if n.ends_with("grass_block") {
                top = [0.2, 0.42, 0.1];
                side = [0.25, 0.2, 0.12];
            } else if n.ends_with("oak_leaves") {
                top = [0.12, 0.3, 0.07];
                side = top;
            } else if n.ends_with("short_grass") {
                top = [0.17, 0.38, 0.1];
                side = top;
            }
            let water = n.ends_with(":water");
            if water {
                top = [0.1, 0.22, 0.75];
                side = top;
            }
            let lava = n.ends_with(":lava");
            Mat { top, side, glow: if lava { 2.2 } else if n.ends_with("magma_block") { 0.5 } else { 0.0 }, alpha: if water { 0.75 } else { 1.0 } }
        })
        .collect()
}
const SUN: [f64; 3] = [0.46, 0.78, 0.42];
/// The first solid thing along the ray: the block, its id and the face's axis.
fn march(w: &Vox, o: [f64; 3], d: [f64; 3], tmax: f64) -> Option<(f64, [i32; 3], u8, usize)> {
    let b0 = [f64::from(-R), f64::from(Y0), f64::from(-R)];
    let b1 = [f64::from(R), f64::from(Y0) + H as f64, f64::from(R)];
    let (mut t0, mut t1) = (0.0f64, tmax);
    for i in 0..3 {
        if d[i].abs() < 1e-9 {
            if o[i] < b0[i] || o[i] > b1[i] {
                return None;
            }
            continue;
        }
        let (a, b) = ((b0[i] - o[i]) / d[i], (b1[i] - o[i]) / d[i]);
        t0 = t0.max(a.min(b));
        t1 = t1.min(a.max(b));
    }
    if t0 >= t1 {
        return None;
    }
    let t = t0 + 1e-6;
    let p = [o[0] + d[0] * t, o[1] + d[1] * t, o[2] + d[2] * t];
    let mut c = p.map(|v| v.floor() as i32);
    let step = d.map(|v| if v > 0.0 { 1 } else { -1 });
    let dt = d.map(|v| if v.abs() < 1e-9 { 1e30 } else { 1.0 / v.abs() });
    let mut next = [0.0; 3];
    for i in 0..3 {
        let b = f64::from(c[i]) + if step[i] > 0 { 1.0 } else { 0.0 };
        next[i] = if d[i].abs() < 1e-9 { 1e30 } else { t + (b - p[i]) / d[i] };
    }
    let mut axis = 1;
    let mut tn = t;
    loop {
        let Some(i) = Vox::at(c[0], c[1], c[2]) else { return None };
        let id = w.v[i];
        if id != 0 {
            return Some((tn, c, id, axis));
        }
        axis = if next[0] < next[1] { if next[0] < next[2] { 0 } else { 2 } } else if next[1] < next[2] { 1 } else { 2 };
        tn = next[axis];
        if tn > t1 {
            return None;
        }
        c[axis] += step[axis];
        next[axis] += dt[axis];
    }
}
fn shade(w: &Vox, m: &[Mat], o: [f64; 3], d: [f64; 3], tmax: f64, depth: u32) -> [f32; 3] {
    let sky = [0.42f32, 0.6, 0.95];
    let Some((t, c, id, axis)) = march(w, o, d, tmax) else { return sky };
    let mm = &m[id as usize];
    let up = axis == 1 && d[1] < 0.0;
    let base = if up { mm.top } else { mm.side };
    // (a block's texture, roughly: a grain of sixteen to the block)
    let p = [o[0] + d[0] * t, o[1] + d[1] * t, o[2] + d[2] * t];
    let g = |i: usize| ((p[i] * 16.0).floor() as i32).wrapping_mul([31, 57, 89][i]);
    let grain = 0.9 + 0.2 * pick(g(0) + g(1) + g(2), 3) as f32;
    let n = [if axis == 0 { -d[0].signum() } else { 0.0 }, if axis == 1 { -d[1].signum() } else { 0.0 }, if axis == 2 { -d[2].signum() } else { 0.0 }];
    let nl = (n[0] * SUN[0] + n[1] * SUN[1] + n[2] * SUN[2]).max(0.0);
    let start = [p[0] + n[0] * 0.01, p[1] + n[1] * 0.01, p[2] + n[2] * 0.01];
    let lit = if nl > 0.0 && march(w, start, SUN, 600.0).is_none() { nl as f32 } else { 0.0 };
    let amb = match axis {
        1 => 0.46,
        0 => 0.3,
        _ => 0.36,
    };
    let l = amb + 0.85 * lit;
    let mut col = [0.0; 3];
    for i in 0..3 {
        col[i] = base[i] * grain * l + base[i] * mm.glow;
    }
    if mm.alpha < 1.0 && depth < 1 {
        let r = [d[0], -d[1], d[2]];
        let under = shade(w, m, start, r, 400.0, depth + 1);
        for i in 0..3 {
            col[i] = col[i] * 0.85 + 0.15 * under[i];
        }
    }
    // the air's haze
    let hz = (1.0 - (-t / 3200.0).exp()) as f32;
    for i in 0..3 {
        col[i] = col[i] * (1.0 - hz) + sky[i] * hz;
    }
    col
}
fn write_ppm(path: &str, wide: usize, high: usize, px: &[[f32; 3]]) {
    let mut out = format!("P6\n{wide} {high}\n255\n").into_bytes();
    for p in px {
        for v in p {
            out.push((v.max(0.0).powf(1.0 / 2.2) * 255.0).min(255.0) as u8);
        }
    }
    std::fs::write(path, out).unwrap();
}
fn render(w: &Vox, m: &[Mat], c: Cam, wide: usize, high: usize) -> Vec<[f32; 3]> {
    let norm = |v: [f64; 3]| {
        let l = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
        v.map(|x| x / l)
    };
    let cross = |a: [f64; 3], b: [f64; 3]| [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    let f = norm([c.at[0] - c.eye[0], c.at[1] - c.eye[1], c.at[2] - c.eye[2]]);
    let r = norm(cross(f, [0.0, 1.0, 0.0]));
    let u = cross(r, f);
    let k = (c.fov.to_radians() * 0.5).tan();
    let mut px = vec![[0.0f32; 3]; wide * high];
    let rows: Vec<&mut [[f32; 3]]> = px.chunks_mut(wide).collect();
    let mut lots: Vec<Vec<(usize, &mut [[f32; 3]])>> = (0..16).map(|_| Vec::new()).collect();
    for (j, row) in rows.into_iter().enumerate() {
        lots[j % 16].push((j, row));
    }
    std::thread::scope(|s| {
        for lot in lots {
            s.spawn(move || {
                for (j, row) in lot {
                    for (i, p) in row.iter_mut().enumerate() {
                        let (sx, sy) = ((i as f64 + 0.5) / wide as f64 * 2.0 - 1.0, 1.0 - (j as f64 + 0.5) / high as f64 * 2.0);
                        let a = wide as f64 / high as f64;
                        let d = norm([0, 1, 2].map(|q| f[q] + r[q] * sx * k * a + u[q] * sy * k));
                        *p = shade(w, m, c.eye, d, 6000.0, 0);
                    }
                }
            });
        }
    });
    px
}
fn map(w: &Vox, m: &[Mat], half: i32) -> Vec<[f32; 3]> {
    let side = 2 * half as usize;
    let mut px = vec![[0.0f32; 3]; side * side];
    let rows: Vec<&mut [[f32; 3]]> = px.chunks_mut(side).collect();
    let mut lots: Vec<Vec<(usize, &mut [[f32; 3]])>> = (0..16).map(|_| Vec::new()).collect();
    for (j, row) in rows.into_iter().enumerate() {
        lots[j % 16].push((j, row));
    }
    std::thread::scope(|s| {
        for lot in lots {
            s.spawn(move || {
                for (j, row) in lot {
                    for (i, p) in row.iter_mut().enumerate() {
                        let (x, z) = (i as f64 - f64::from(half) + 0.5, j as f64 - f64::from(half) + 0.5);
                        *p = shade(w, m, [x, 280.0, z], [0.02, -1.0, 0.01], 900.0, 0);
                    }
                }
            });
        }
    });
    px
}

/// What share of the floor shows lava, what share of the sheet's columns each block is.
fn tally(w: &Vox) {
    let mut f: HashMap<u8, u32> = HashMap::new();
    let mut n = 0;
    for z in (-200..200).step_by(2) {
        for x in (-200..200).step_by(2) {
            if x * x + z * z > 200 * 200 {
                continue;
            }
            *f.entry(w.get(x, w.world_surface(x, z) - 1, z)).or_default() += 1;
            n += 1;
        }
    }
    let mut l: Vec<_> = f.into_iter().collect();
    l.sort_by_key(|e| std::cmp::Reverse(e.1));
    for (id, c) in l.iter().take(10) {
        eprintln!("  floor: {:5.1}% {}", 100.0 * f64::from(*c) / f64::from(n), w.names[*id as usize]);
    }
}

#[test]
#[ignore]
fn vc_land_picture() {
    let out = std::env::var("VC_VIEW_OUT").unwrap();
    let (bx, bz) = (0, 0);
    let t0 = std::time::Instant::now();
    let mut w = Vox::new();
    land(&mut w);
    eprintln!("land {:?}", t0.elapsed());
    let s = Shape::new(0.5, 0.5, 37, GY);
    let mut wk = Work::new(s, bx, bz);
    wk.cols = vec![0u32; (VC_GW * VC_GW) as usize];
    answers(&w, &mut wk.cols, bx, bz);
    // (the land's height as the Survey gives it: its 128 by 128 cells)
    let reach = 1500.0;
    let n = crate::strike::volcano::VC_HN as i32;
    let step = 2.0 * reach / f64::from(n - 1);
    let hs: Vec<Option<f64>> = (0..n * n)
        .map(|c| {
            let (i, k) = (c % n, c / n);
            let at = |q: i32| (-reach + step * f64::from(q)).round() as i32;
            let (x, z) = (at(i).clamp(-R + 1, R - 1), at(k).clamp(-R + 1, R - 1));
            Some(f64::from(w.world_surface(x, z) - GY))
        })
        .collect();
    wk.hf.borrow_mut().set(&hs, reach);
    eprintln!("read {:?}", t0.elapsed());
    let chunks = std::mem::take(&mut wk.chunks);
    let mut p = Plan { laser: &crate::lasers::SUPERVOLCANO, ev: Vec::new(), rng: Rng::new(7), bx, by: GY - 1, bz };
    let mut worst = (0u64, 0, 0);
    let mut total = 0u64;
    let mut runs = 0usize;
    let mut by = [(0u64, 0u32); 8];
    for &(t, x, z) in &chunks {
        crate::meter::reset();
        vc_chunk(&mut p, &wk, t, x, z);
        let m = crate::meter::spent();
        total += m;
        let z_ = ((f64::from(x) + 8.0).hypot(f64::from(z) + 8.0) / 100.0) as usize;
        by[z_.min(7)].0 += m;
        by[z_.min(7)].1 += 1;
        if m > worst.0 {
            worst = (m, x, z);
        }
    }
    // (the far dust, every chunk as if the world had them all loaded)
    let n = VC_FAR as i32 / 16 + 1;
    for dz in -n..=n {
        for dx in -n..=n {
            let (x, z) = (dx * 16, dz * 16);
            let r = (f64::from(x) + 8.0).hypot(f64::from(z) + 8.0);
            if r + 12.0 > f64::from(VC_READ) && r < VC_FAR && x.abs() < R - 16 && z.abs() < R - 16 {
                vc_far_chunk(&mut p, &s, 60.0, x, z);
            }
        }
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    for e in &p.ev {
        if let Act::Blocks(b) = &e.1 {
            runs += b.runs.len();
            apply(&mut w, b);
        }
    }
    eprintln!("edits {:?}: {} chunks, {runs} runs, {:.0}M counted, worst chunk {:.2}M at {} {}", t0.elapsed(), chunks.len(), total as f64 / 1e6, worst.0 as f64 / 1e6, worst.1, worst.2);
    for (i, b) in by.iter().enumerate() {
        eprintln!("  r {:4}: {:5} chunks, {:6.2}M a chunk", i * 100, b.1, b.0 as f64 / 1e6 / f64::from(b.1.max(1)));
    }
    tally(&w);
    let m = mats(&w.names);
    let want = std::env::var("VC_VIEWS").unwrap_or("map,air570,edge,rim,lake,wall,trees,crown".into());
    let want: Vec<&str> = want.split(',').collect();
    if want.contains(&"map") {
        let half = 720;
        write_ppm(&format!("{out}/map.ppm"), 2 * half as usize, 2 * half as usize, &map(&w, &m, half));
    }
    for (name, c) in views() {
        if want.contains(&name) {
            write_ppm(&format!("{out}/{name}.ppm"), 1280, 720, &render(&w, &m, c, 1280, 720));
        }
    }
    eprintln!("done {:?}", t0.elapsed());
}
