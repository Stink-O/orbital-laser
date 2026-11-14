//! The World Eater's path (contract v2): the one source of the numbers every part of it shares (the `WE_*` constants)
//! and of where the worm is. Kept free of the rest of the crate: mod/build.rs compiles it too, to write the WGSL's
//! constants (`we_wgsl_consts`, spliced into shaders/worldeater_path.wgsl's `[generated constants]` block).
//!
//! The path is DATA, a chain of surfacings (`WePath`), which Rust and the pass (worldeater_path.wgsl) both read from the
//! same words of `mod_data` (`WePath::words`, render.set-data):
//!
//! - arches, at most `WE_ARCS_MAX`, each with TWO holes of its own: it breaches at `from` (A_i) and dives at `to` (D_i);
//!   the next arch breaches at a different point A_i+1. Every position is from the strike's origin (the target's ground
//!   point: the block hit, its middle, one up; x, y, z in blocks, y from the target's ground). A_0 is the origin.
//! - the centreline, `s` blocks along it (`s = 0` where it comes out at A_0):
//!   - the first approach (the run into arch 0): from the wormsign's start W0 (`A_0 - sign_dir * WE_SIGN`) level at
//!     depth, a quarter turn up under A_0 (radius `WE_RUN_TURN`), straight up to A_0; before W0 it lies level, straight
//!     back the way it came.
//!   - each arch: a half ellipse from A_i to D_i, vertical tangents at both feet, its top `apex` over the mean of the two
//!     feet's land (sheared to their heights; `s` is the level ellipse's arc length: a sheared arch runs within ~2% of
//!     a block per block).
//!   - between arches, the run from D_i to A_i+1: straight down under D_i, a quarter turn to level, level at depth (its
//!     centre `WE_RUN_DEPTH` under the lower of the run's two ends), a quarter turn up, straight up under A_i+1. Its
//!     horizontal span D_i to A_i+1 is `WE_RUN_MIN..=WE_RUN_MAX`.
//!   - after the last arch, straight down under its D.
//!   Position and tangent are continuous everywhere; every land crossing is vertical.
//! - the head's schedule, `we_head(t)`: the head is at W0 at `WE_SIGN_T0` (0) moving at `WE_V_SIGN`; per arch it comes
//!   out of A_i at `t_out` (`v_out`), an optional hold (from `h0` to `h1` it creeps at its speed round its middle, blocks
//!   into the arch), goes in at D_i at `t_in` (`v_in`); a cubic Hermite between those knots, so each run is travelled at
//!   whatever eased speed joins one arch's `v_in` to the next's `v_out` (position and speed continuous; `try_push`
//!   refuses a `t_out` the head can't make without going over `WE_V_RUN_MAX` or under `WE_V_RUN_MIN`: `next_window`
//!   says which it can). Before W0 it goes at `WE_V_SIGN`, after the last `t_in` at the last `v_in`. A body point `b`
//!   blocks behind the head is at `we_point(we_head(t) - b)`; the tail is `b = WE_LEN`.
//! - where the head is while underground: `we_mound(path, t)` (the wormsign's mound on the first approach and on every
//!   run after, and the dome over each A_i in the last `WE_DOME_LEAD` seconds before it breaches).
//!
//! The table can grow during a strike: a count word, then fixed-size records (`WE_AW` words an arch, from `WE_A0`).
//! Appending an arch changes no word of the arches before it: only the centreline past the last D (its shaft becomes the
//! run to the new arch) and the schedule after the last `t_in` change. Append before the head goes in at the last D. A
//! hole's land height (`set_hole_height`) sets the runs' depths, so every later arch's `s`: set them before the head
//! reaches them (the survey at the start).
//!
//! Cost (the game's WebAssembly fuel, where a sin, cos or hypot is hundreds of instructions and a sqrt one): no libm in
//! any loop. An arch's table (`we_arc_table`) is 512 Simpson steps turned on by a rotation, a sqrt each: ~0.1 M; a
//! `try_push` with its run's window (`next_window`: two 60-step bisections of a quadratic) ~0.15 M in all; `point` a
//! sin and a cos on an arch or a turn, none elsewhere (~1-2 k); `head` and `mound` walk at most 25 knots, no trig (~1 k).
#![allow(dead_code)]
#![allow(clippy::too_many_arguments)]

use std::f64::consts::PI;

// ---- the shared numbers ------------------------------------------------------------------------------------------
/// The body's radius (the head is 68 across).
pub const WE_R: f64 = 34.0;
/// The body's length, head to tail: the tail out at 27 and in at 31 over the default 612-block arch makes the pour 153
/// blocks a second, and at that speed from the bite at 19 the tail is 1836 behind the head.
pub const WE_LEN: f64 = 1836.0;
/// The default arch: A to D, its top over the land.
pub const WE_SPAN: f64 = 260.0;
pub const WE_APEX: f64 = 250.0;
/// The wormsign: the head starts this far from A_0 (at W0) at WE_SIGN_T0, moving at WE_V_SIGN; its mound this wide
/// (radius) and high; the dome over a breach this wide and high over its last WE_DOME_LEAD seconds.
pub const WE_SIGN: f64 = 420.0;
pub const WE_SIGN_T0: f64 = 0.0;
pub const WE_V_SIGN: f64 = 30.0;
pub const WE_MOUND_R: f64 = 25.0;
pub const WE_MOUND_H: f64 = 9.0;
pub const WE_DOME_LEAD: f64 = 1.5;
pub const WE_DOME_R: f64 = 45.0;
pub const WE_DOME_H: f64 = 10.0;
/// v1's wormsign (`we_sign`, `we_dome`: the default plan's, from constants alone, for the world warp, which can't read
/// the table): the mound arrives at A_0 by WE_SIGN_T, the dome from WE_DOME_T0.
pub const WE_SIGN_T: f64 = 8.5;
pub const WE_DOME_T0: f64 = 7.5;
/// The beats of the default plan (strike seconds).
pub const WE_BREACH: f64 = 9.0;
pub const WE_BELLOW: (f64, f64) = (12.5, 14.5);
pub const WE_BITE: f64 = 19.0;
pub const WE_TAIL_OUT: f64 = 27.0;
pub const WE_TAIL_IN: f64 = 31.0;
pub const WE_SINK: (f64, f64) = (31.0, 40.0);
/// The strike's length (lasers.rs's `length`).
pub const WE_LEN_S: f64 = 46.0;
/// The head comes out of the land this fast (blocks a second), creeps this fast through a hold.
pub const WE_V_BREACH: f64 = 140.0;
pub const WE_V_HOLD: f64 = 10.0;
/// The runs underground: the turns' radius (the default arch's bend at its top, a^2 / b), the level centre this far
/// under the lower of the run's two ends (the body's top more than WE_R + 12 under the land, and the turn fits), the
/// horizontal span allowed from D to the next A, and how fast and how slowly the head may go along a run.
pub const WE_RUN_TURN: f64 = 67.6;
pub const WE_RUN_DEPTH: f64 = 80.0;
pub const WE_RUN_MIN: f64 = 160.0;
pub const WE_RUN_MAX: f64 = 600.0;
pub const WE_V_RUN_MAX: f64 = 260.0;
pub const WE_V_RUN_MIN: f64 = 5.0;
/// v1's loop under a shared knot: no longer part of the path (kept so code written against v1 still compiles).
pub const WE_LOOP_D: f64 = 40.0;
pub const WE_LOOP_R: f64 = 50.0;
pub const WE_LOOP_LEN: f64 = 2.0 * WE_LOOP_D + 7.0 * PI * WE_LOOP_R / 3.0;
const LOOP_ALPHA: f64 = PI / 3.0;

// ---- the table's layout (words of mod_data, f32 bits unless said) --------------------------------------------------
/// At most this many arches.
pub const WE_ARCS_MAX: usize = 6;
/// The header: [0] the arch count, [1] 1.0 once a path is given, [2], [3] the wormsign's way (`dir`, x and z, unit,
/// from W0 to A_0), [4] WE_LEN, [5] the head's time at W0, [6] its speed there; [7..16] kept for the path.
pub const WE_T_COUNT: usize = 0;
pub const WE_T_MAGIC: usize = 1;
pub const WE_T_SIGN: usize = 2;
pub const WE_T_LEN: usize = 4;
pub const WE_T_T0: usize = 5;
pub const WE_T_V0: usize = 6;
/// The arches, from word WE_A0, WE_AW words each.
pub const WE_A0: usize = 16;
pub const WE_AW: usize = 48;
/// An arch's record: [0..3] from (A), [3..6] to (D), [6] its top over the land, [7] its length, [8] `s` where it leaves
/// A, [9..11] where the run INTO it starts (x, z: W0 for arch 0, the last arch's D after), [11] t_out, [12] v_out,
/// [13] t_in, [14] v_in, [15..19] the hold (h0, h1, its middle in blocks into the arch, its speed; h0 = h1 = -1 for
/// none), [19..36] the arc table (the level ellipse's angle at WE_TN + 1 even steps of its length), [36] the run's
/// length, [37] 1 if it starts with a dive (0: arch 0's, already level at W0), [38] the land's height where it starts,
/// [39] its level centre's y, [40] the head's time where it starts, [41] its speed there; [42..48] kept.
pub const WE_R_FROM: usize = 0;
pub const WE_R_TO: usize = 3;
pub const WE_R_APEX: usize = 6;
pub const WE_R_LEN: usize = 7;
pub const WE_R_S: usize = 8;
pub const WE_R_RUN: usize = 9;
pub const WE_R_TOUT: usize = 11;
pub const WE_R_VOUT: usize = 12;
pub const WE_R_TIN: usize = 13;
pub const WE_R_VIN: usize = 14;
pub const WE_R_H0: usize = 15;
pub const WE_R_H1: usize = 16;
pub const WE_R_HC: usize = 17;
pub const WE_R_HV: usize = 18;
pub const WE_R_TH: usize = 19;
pub const WE_TN: usize = 16;
pub const WE_R_RUN_LEN: usize = 36;
pub const WE_R_RUN_DIVE: usize = 37;
pub const WE_R_RUN_LAND: usize = 38;
pub const WE_R_RUN_Y: usize = 39;
pub const WE_R_RUN_T: usize = 40;
pub const WE_R_RUN_V: usize = 41;
/// v1's name for words 9 and 10 (they were the loop's way; now where the run into the arch starts).
pub const WE_R_LOOP: usize = WE_R_RUN;
/// The path's words end here; each part's own words in mod_data after it: the body's (strike/we_body.rs), the fx's,
/// the land's (strike/worldeater.rs, we_land.rs), and the preview's debug markers (only tools/preview.py writes them).
pub const WE_PATH_END: usize = 512;
pub const WE_BODY_T: usize = 512;
pub const WE_FX_T: usize = 2048;
pub const WE_LAND_T: usize = 8192;
pub const WE_DBG_T: usize = 16384;
/// The caught eye (the land's words, `WeEye`): where the throat is drawn from while a player is carried. At WE_EYE_T:
/// [0] when the jaws shut (0: none), [1] the let-go, [2] its knots' count (at most WE_EYE_MAX), [3] how long after the shut
/// the eye leaves where they stood, [4] over how long, [5..8] where they stood (from the origin), [8] when it leaves the
/// mouth's tip (0: never), [9..12] where, [12..15] its velocity then (blocks a second), [15..18] where it is let go,
/// [18..21] its velocity there; from [24] its knots: time, s along the centreline, ds/dt (three words each). Till it
/// leaves the mouth it is on the centreline at s(t); from then to the let-go on the cubic between those two places and
/// velocities (its flight, clear of the body). `we_eye` / `we_eye_dir` (worldeater_path.wgsl the same).
pub const WE_EYE_T: usize = 8704;
pub const WE_EYE_MAX: usize = 64;

// ---- the geometry of a strike --------------------------------------------------------------------------------------
/// Where a strike is: its origin (the target's ground point, in the world), the player from it, the seed, the line's
/// way `dir` (level, across the way the player looks at the target, its side picked by the seed), and from the origin:
/// B (= A_0 = 0, 0, 0), D (`dir * WE_SPAN`, its y the land's there once known: `with_land`), W0 (`-dir * WE_SIGN`).
#[derive(Clone, Copy, Debug)]
pub struct WeGeo {
    pub origin: [f64; 3],
    pub me: [f64; 3],
    pub seed: u32,
    pub dir: [f64; 2],
    pub b: [f64; 3],
    pub d: [f64; 3],
    pub w0: [f64; 3],
}

/// The line's way, from where the player is from the origin (`me`) and the seed: across the way they look at the
/// target, to their right for an odd seed, their left for an even one. (worldeater_path.wgsl's `we_dir_rule`.)
pub fn we_dir_rule(me: [f64; 3], seed: u32) -> [f64; 2] {
    let (vx, vz) = (-me[0], -me[2]);
    let l = (vx * vx + vz * vz).sqrt();
    let v = if l > 1.0 { [vx / l, vz / l] } else { [0.0, -1.0] };
    let side = if seed % 2 == 1 { 1.0 } else { -1.0 };
    [-v[1] * side, v[0] * side]
}

/// A strike's geometry: `target` the target's ground point in the world (the block's middle, one up), `player` where
/// the player is in the world.
pub fn we_geo(target: [f64; 3], player: [f64; 3], seed: u32) -> WeGeo {
    let me = [player[0] - target[0], player[1] - target[1], player[2] - target[2]];
    let dir = we_dir_rule(me, seed);
    WeGeo { origin: target, me, seed, dir, b: [0.0; 3], d: [dir[0] * WE_SPAN, 0.0, dir[1] * WE_SPAN], w0: [-dir[0] * WE_SIGN, 0.0, -dir[1] * WE_SIGN] }
}
impl WeGeo {
    /// D's land height (from the target's ground), once the world has answered.
    pub fn with_land(mut self, hd: f64) -> Self {
        self.d[1] = hd;
        self
    }
}

// ---- the path ----------------------------------------------------------------------------------------------------
/// One arch of the chain and the run into it (see the module's notes).
#[derive(Clone, Debug, PartialEq)]
pub struct WeArch {
    pub from: [f64; 3],
    pub to: [f64; 3],
    pub apex: f64,
    pub len: f64,
    pub s0: f64,
    /// The run into it: where it starts (x, the land's height there, z), its level centre's y, its length, whether it
    /// starts with a dive (all but arch 0's), the head's time and speed where it starts.
    pub run_from: [f64; 3],
    pub run_y: f64,
    pub run_len: f64,
    pub run_dive: bool,
    pub run_t: f64,
    pub run_v: f64,
    pub t_out: f64,
    pub v_out: f64,
    pub t_in: f64,
    pub v_in: f64,
    /// (h0, h1, its middle in blocks into the arch, its speed)
    pub hold: Option<(f64, f64, f64, f64)>,
    pub theta: [f64; WE_TN + 1],
}
impl WeArch {
    fn span(&self) -> (f64, [f64; 2]) {
        let (dx, dz) = (self.to[0] - self.from[0], self.to[2] - self.from[2]);
        let w = (dx * dx + dz * dz).sqrt().max(1e-6);
        (w, [dx / w, dz / w])
    }
    /// `s` where it goes in at `to`.
    pub fn s1(&self) -> f64 {
        self.s0 + self.len
    }
    /// `s` where the run into it starts.
    pub fn run_s(&self) -> f64 {
        self.s0 - self.run_len
    }
}

/// The length of the run from `start` (x, land y, z) to `to` (A, x y z), level at `y`, with or without its dive.
fn run_length(start: [f64; 3], to: [f64; 3], y: f64, dive: bool) -> f64 {
    let rt = WE_RUN_TURN;
    let (dx, dz) = (to[0] - start[0], to[2] - start[2]);
    let hd = (dx * dx + dz * dz).sqrt();
    let q = 0.5 * PI * rt;
    let v2 = to[1] - (y + rt);
    if dive { (start[1] - (y + rt)) + q + (hd - 2.0 * rt) + q + v2 } else { (hd - rt) + q + v2 }
}

/// A chain of arches: the centreline and the head's schedule.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct WePath {
    pub arches: Vec<WeArch>,
    /// The wormsign's way (`WeGeo::dir`).
    pub sign_dir: [f64; 2],
}

/// The level half-ellipse's arc length (half-axes `a` across, `b` up) and its angle at WE_TN + 1 even steps of it:
/// 512 Simpson steps, the angle turned on by a rotation (no sine or cosine in the loop), a sqrt each.
pub fn we_arc_table(a: f64, b: f64) -> (f64, [f64; WE_TN + 1]) {
    const N: usize = 512;
    let h = PI / N as f64;
    let (sh, ch) = (0.5 * h).sin_cos();
    let speed = |s: f64, c: f64| ((a * s) * (a * s) + (b * c) * (b * c)).sqrt();
    let mut cum = [0.0f64; N + 1];
    let (mut s, mut c) = (0.0f64, 1.0f64);
    let mut f0 = speed(s, c);
    for i in 0..N {
        let (sm, cm) = (s * ch + c * sh, c * ch - s * sh);
        let (s1, c1) = (sm * ch + cm * sh, cm * ch - sm * sh);
        let f1 = speed(s1, c1);
        cum[i + 1] = cum[i] + h / 6.0 * (f0 + 4.0 * speed(sm, cm) + f1);
        (s, c, f0) = (s1, c1, f1);
    }
    let len = cum[N];
    let mut th = [0.0; WE_TN + 1];
    let mut j = 0;
    for (k, out) in th.iter_mut().enumerate() {
        let want = len * k as f64 / WE_TN as f64;
        while j < N - 1 && cum[j + 1] < want {
            j += 1;
        }
        let f = ((want - cum[j]) / (cum[j + 1] - cum[j])).clamp(0.0, 1.0);
        *out = (j as f64 + f) * h;
    }
    th[WE_TN] = PI;
    (len, th)
}

fn hermite(t0: f64, p0: f64, v0: f64, t1: f64, p1: f64, v1: f64, t: f64) -> (f64, f64) {
    let dt = t1 - t0;
    let u = ((t - t0) / dt).clamp(0.0, 1.0);
    let (u2, u3) = (u * u, u * u * u);
    let p = (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (u3 - 2.0 * u2 + u) * dt * v0 + (-2.0 * u3 + 3.0 * u2) * p1 + (u3 - u2) * dt * v1;
    let v = (6.0 * u2 - 6.0 * u) / dt * p0 + (3.0 * u2 - 4.0 * u + 1.0) * v0 + (-6.0 * u2 + 6.0 * u) / dt * p1 + (3.0 * u2 - 2.0 * u) * v1;
    (p, v)
}
/// The slowest and the fastest a Hermite from speed `va` to `vb` over `ds` blocks in `dt` seconds goes.
fn herm_vrange(dt: f64, ds: f64, va: f64, vb: f64) -> (f64, f64) {
    let d = ds / dt;
    let (a2, a1, a0) = (-6.0 * d + 3.0 * va + 3.0 * vb, 6.0 * d - 4.0 * va - 2.0 * vb, va);
    let (mut lo, mut hi) = (va.min(vb), va.max(vb));
    if a2.abs() > 1e-12 {
        let u = -a1 / (2.0 * a2);
        if u > 0.0 && u < 1.0 {
            let v = a2 * u * u + a1 * u + a0;
            lo = lo.min(v);
            hi = hi.max(v);
        }
    }
    (lo, hi)
}
/// Which times `dt` after it starts a segment of `ds` blocks from speed `va` can end at `vb`, going no faster than
/// `vmax` and no slower than `vmin`: the earliest and the latest (none if none can).
fn seg_window(ds: f64, va: f64, vb: f64, vmin: f64, vmax: f64) -> Option<(f64, f64)> {
    if va > vmax || vb > vmax || va < vmin || vb < vmin || ds <= 0.0 {
        return None;
    }
    // (faster the shorter it is; slower, and at last stopping, the longer)
    let (mut lo, mut hi) = (1e-3, 600.0);
    if herm_vrange(hi, ds, va, vb).1 > vmax {
        return None;
    }
    for _ in 0..60 {
        let m = 0.5 * (lo + hi);
        if herm_vrange(m, ds, va, vb).1 > vmax { lo = m } else { hi = m }
    }
    let early = hi;
    let (mut lo, mut hi) = (early, 600.0);
    if herm_vrange(lo, ds, va, vb).0 < vmin {
        return None;
    }
    for _ in 0..60 {
        let m = 0.5 * (lo + hi);
        if herm_vrange(m, ds, va, vb).0 >= vmin { lo = m } else { hi = m }
    }
    Some((early, lo))
}

fn norm(a: [f64; 3]) -> [f64; 3] {
    let l = (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt().max(1e-12);
    [a[0] / l, a[1] / l, a[2] / l]
}
fn ss(a: f64, b: f64, x: f64) -> f64 {
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// A schedule knot: strike time, the head's `s`, its speed.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WeKnot {
    pub t: f64,
    pub s: f64,
    pub v: f64,
}

/// A hole: a breach (where an arch comes out) or a bite (where it goes in).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WeHoleKind {
    Breach,
    Bite,
}
/// A hole as the land sees it: which kind, of which arch, where (from the origin), when the head first breaks it, when
/// the body has finished passing through it (the tail out of a breach, into a bite).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WeHole {
    pub kind: WeHoleKind,
    pub arch: usize,
    pub at: [f64; 3],
    pub first: f64,
    pub last: f64,
}
/// An arch as the land sees it: from, to, when the head comes out of `from` and goes in at `to`, when the tail comes
/// out of `from` and goes in at `to` (the body is over the land between head_out and tail_in).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WeRun {
    pub from: [f64; 3],
    pub to: [f64; 3],
    pub head_out: f64,
    pub head_in: f64,
    pub tail_out: f64,
    pub tail_in: f64,
}
/// A run underground, into arch `arch`, as the land sees it: from (W0 for arch 0, the last arch's D after: its land
/// point), to (the arch's A), its level centre's y, when the head enters it (dives at `from`, or is at W0) and leaves it
/// (breaches at `to`), when the tail enters it and when the tail has passed out of it (the land over it can cave in
/// behind the tail: the aftermath's trenches follow the tunnels, nothing is tunnelled under an arch).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WeTunnel {
    pub arch: usize,
    pub from: [f64; 3],
    pub to: [f64; 3],
    pub y: f64,
    pub head_in: f64,
    pub head_out: f64,
    pub tail_in: f64,
    pub tail_out: f64,
}
/// Where the head is while it is underground (`we_mound`): the land over it (from the origin), the mound's height there,
/// the dome's height over the breach to come and where it is, and which arch's run it is in (none: it is over the land
/// or gone down for good).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WeMound {
    pub at: [f64; 3],
    pub h: f64,
    pub dome: f64,
    pub dome_at: [f64; 3],
    pub arch: Option<usize>,
}

impl WePath {
    pub fn new(sign_dir: [f64; 2]) -> Self {
        WePath { arches: Vec::new(), sign_dir }
    }
    /// The last arch's D (the origin, with none).
    pub fn end_knot(&self) -> [f64; 3] {
        self.arches.last().map_or([0.0; 3], |a| a.to)
    }
    /// `s` where the last arch goes in.
    pub fn s_end(&self) -> f64 {
        self.arches.last().map_or(0.0, WeArch::s1)
    }
    /// The run into an arch breaching at `from`, after the arches there are: where it starts, its level, its length,
    /// whether it dives, the head's time and speed where it starts.
    fn run_into(&self, from: [f64; 3], w0_y: f64) -> ([f64; 3], f64, f64, bool, f64, f64) {
        match self.arches.last() {
            None => {
                let st = [from[0] - self.sign_dir[0] * WE_SIGN, w0_y, from[2] - self.sign_dir[1] * WE_SIGN];
                let y = st[1].min(from[1]) - WE_RUN_DEPTH;
                (st, y, run_length(st, from, y, false), false, WE_SIGN_T0, WE_V_SIGN)
            }
            Some(p) => {
                let y = p.to[1].min(from[1]) - WE_RUN_DEPTH;
                (p.to, y, run_length(p.to, from, y, true), true, p.t_in, p.v_in)
            }
        }
    }
    /// Which `t_out`s an arch breaching at `from` (from the origin) next can have, coming out at `v_out`: the earliest
    /// and the latest the head can make along the run to it (none if it can't: too near or too far from the last D, or
    /// its speeds out of range). With no arch yet, the first approach from W0 (its land at the origin's height).
    pub fn next_window(&self, from: [f64; 3], v_out: f64) -> Option<(f64, f64)> {
        if let Some(p) = self.arches.last() {
            let (dx, dz) = (from[0] - p.to[0], from[2] - p.to[2]);
            let hd = (dx * dx + dz * dz).sqrt();
            if !(WE_RUN_MIN..=WE_RUN_MAX).contains(&hd) {
                return None;
            }
        }
        let (_, _, len, _, t, v) = self.run_into(from, 0.0);
        seg_window(len, v, v_out, WE_V_RUN_MIN, WE_V_RUN_MAX).map(|(a, b)| (t + a, t + b))
    }
    /// An arch from `from` (A) to `to` (D) (from the origin), its top `apex` over the land, out at `t_out` (`v_out`
    /// blocks a second), in at `t_in` (`v_in`), with a hold (h0, h1, its middle in blocks into the arch, its speed).
    /// Refused (and nothing changed) if the arch is too short, there are WE_ARCS_MAX already, `from` is not
    /// WE_RUN_MIN..=WE_RUN_MAX from the last D (the first must breach at the origin), the times aren't in order, the run
    /// can't be made by `t_out` (the error says which `t_out`s it can: `next_window`), or the head would stop or go back
    /// on the arch. Its land heights as given (`set_hole_height` later).
    pub fn try_push(&mut self, from: [f64; 3], to: [f64; 3], apex: f64, t_out: f64, v_out: f64, t_in: f64, v_in: f64, hold: Option<(f64, f64, f64, f64)>) -> Result<&mut Self, String> {
        if self.arches.len() >= WE_ARCS_MAX {
            return Err(format!("at most {WE_ARCS_MAX} arches"));
        }
        if self.arches.is_empty() && (from[0].abs() > 1e-6 || from[2].abs() > 1e-6) {
            return Err("the first arch breaches at the origin".into());
        }
        let (dx, dz) = (to[0] - from[0], to[2] - from[2]);
        let w = (dx * dx + dz * dz).sqrt();
        if w <= 2.0 * WE_R || apex <= WE_R {
            return Err(format!("an arch spans more than the body is wide and stands higher: span {w:.1}, apex {apex:.1}"));
        }
        if let Some(p) = self.arches.last() {
            let (ex, ez) = (from[0] - p.to[0], from[2] - p.to[2]);
            let hd = (ex * ex + ez * ez).sqrt();
            if !(WE_RUN_MIN..=WE_RUN_MAX).contains(&hd) {
                return Err(format!("the next breach is {hd:.1} from the last bite: it must be {WE_RUN_MIN} to {WE_RUN_MAX}"));
            }
        }
        if !(t_in > t_out) {
            return Err(format!("t_in {t_in} is not after t_out {t_out}"));
        }
        if let Some((h0, h1, c, v)) = hold
            && !(t_out < h0 && h0 < h1 && h1 < t_in && v > 0.0 && c > 0.0)
        {
            return Err(format!("the hold {h0}..{h1} is not within {t_out}..{t_in}"));
        }
        let (run_from, run_y, run_len, run_dive, run_t, run_v) = self.run_into(from, self.arches.first().map_or(0.0, |a| a.run_from[1]));
        match seg_window(run_len, run_v, v_out, WE_V_RUN_MIN, WE_V_RUN_MAX) {
            Some((a, b)) if (run_t + a..=run_t + b).contains(&t_out) => {}
            Some((a, b)) => return Err(format!("the run of {run_len:.1} blocks from t {run_t:.2} can come out at {:.2} to {:.2}, not {t_out:.2}", run_t + a, run_t + b)),
            None => return Err(format!("the run of {run_len:.1} blocks from t {run_t:.2} at {run_v:.1} can't come out at {v_out:.1}")),
        }
        let (len, theta) = we_arc_table(0.5 * w, apex);
        let s0 = if self.arches.is_empty() { 0.0 } else { self.s_end() + run_len };
        let arch = WeArch { from, to, apex, len, s0, run_from, run_y, run_len, run_dive, run_t, run_v, t_out, v_out, t_in, v_in, hold, theta };
        // (the head on the arch: never stopping nor going back)
        let mut ks = vec![(t_out, 0.0, v_out)];
        if let Some((h0, h1, c, v)) = hold {
            let half = 0.5 * v * (h1 - h0);
            ks.push((h0, c - half, v));
            ks.push((h1, c + half, v));
        }
        ks.push((t_in, len, v_in));
        for k in ks.windows(2) {
            let (lo, _) = herm_vrange(k[1].0 - k[0].0, k[1].1 - k[0].1, k[0].2, k[1].2);
            if lo <= 0.0 || k[1].1 <= k[0].1 {
                return Err(format!("the head would stop on the arch between {:.2} and {:.2}", k[0].0, k[1].0));
            }
        }
        self.arches.push(arch);
        Ok(self)
    }
    /// `try_push`, its refusal a panic (for plans made up front, whose numbers are known to hold: never mid-strike).
    pub fn push(&mut self, from: [f64; 3], to: [f64; 3], apex: f64, t_out: f64, v_out: f64, t_in: f64, v_in: f64, hold: Option<(f64, f64, f64, f64)>) -> &mut Self {
        if let Err(e) = self.try_push(from, to, apex, t_out, v_out, t_in, v_in, hold) {
            panic!("World Eater path: {e}");
        }
        self
    }
    /// Every run's depth and length, and every arch's `s`, worked out again from the holes' heights.
    fn relayout(&mut self) {
        for i in 0..self.arches.len() {
            let (st, y, len, dive) = if i == 0 {
                let a = &self.arches[0];
                let st = a.run_from;
                let y = st[1].min(a.from[1]) - WE_RUN_DEPTH;
                (st, y, run_length(st, a.from, y, false), false)
            } else {
                let p = self.arches[i - 1].to;
                let a = &self.arches[i];
                let y = p[1].min(a.from[1]) - WE_RUN_DEPTH;
                (p, y, run_length(p, a.from, y, true), true)
            };
            let s0 = if i == 0 { 0.0 } else { self.arches[i - 1].s1() + len };
            let a = &mut self.arches[i];
            (a.run_from, a.run_y, a.run_len, a.run_dive, a.s0) = (st, y, len, dive, s0);
        }
    }
    /// Hole `h`'s land height (from the target's ground): holes as `holes` numbers them (2 i arch i's breach, 2 i + 1 its
    /// bite). The runs' depths and the later arches' `s` follow; the schedule's times and speeds don't change.
    pub fn set_hole_height(&mut self, h: usize, y: f64) {
        let i = h / 2;
        if let Some(a) = self.arches.get_mut(i) {
            if h % 2 == 0 { a.from[1] = y } else { a.to[1] = y }
        }
        self.relayout();
    }
    /// The land's height at W0, where the first approach starts.
    pub fn set_sign_height(&mut self, y: f64) {
        if let Some(a) = self.arches.first_mut() {
            a.run_from[1] = y;
        }
        self.relayout();
    }
    /// v1's: knot `k` of a chain whose knots were A_0, then each arch's D: 0 arch 0's breach, k arch k-1's bite.
    pub fn set_height(&mut self, k: usize, y: f64) {
        self.set_hole_height(if k == 0 { 0 } else { 2 * k - 1 }, y);
    }
    /// Every knot of the head's schedule into `out`, in time order; how many.
    fn knots_into(&self, out: &mut [WeKnot; 1 + 4 * WE_ARCS_MAX]) -> usize {
        let mut n = 0;
        if let Some(a) = self.arches.first() {
            out[n] = WeKnot { t: a.run_t, s: a.run_s(), v: a.run_v };
            n += 1;
        }
        for a in &self.arches {
            out[n] = WeKnot { t: a.t_out, s: a.s0, v: a.v_out };
            n += 1;
            if let Some((h0, h1, c, v)) = a.hold {
                let half = 0.5 * v * (h1 - h0);
                out[n] = WeKnot { t: h0, s: a.s0 + c - half, v };
                out[n + 1] = WeKnot { t: h1, s: a.s0 + c + half, v };
                n += 2;
            }
            out[n] = WeKnot { t: a.t_in, s: a.s1(), v: a.v_in };
            n += 1;
        }
        n
    }
    /// Every knot of the head's schedule, in time order.
    pub fn knots(&self) -> Vec<WeKnot> {
        let mut k = [WeKnot { t: 0.0, s: 0.0, v: 0.0 }; 1 + 4 * WE_ARCS_MAX];
        let n = self.knots_into(&mut k);
        k[..n].to_vec()
    }
    /// The head's `s` and speed at strike time `t`.
    pub fn head(&self, t: f64) -> (f64, f64) {
        let mut k = [WeKnot { t: 0.0, s: 0.0, v: 0.0 }; 1 + 4 * WE_ARCS_MAX];
        let n = self.knots_into(&mut k);
        if n == 0 {
            return (-1.0e4, 0.0);
        }
        if t <= k[0].t {
            return (k[0].s + k[0].v * (t - k[0].t), k[0].v);
        }
        for i in 1..n {
            if t <= k[i].t {
                return hermite(k[i - 1].t, k[i - 1].s, k[i - 1].v, k[i].t, k[i].s, k[i].v, t);
            }
        }
        let l = k[n - 1];
        (l.s + l.v * (t - l.t), l.v)
    }
    /// When the head is at `s` (the schedule is monotone: `check`).
    pub fn time_at(&self, s: f64) -> f64 {
        let (mut lo, mut hi) = (-200.0, 400.0);
        for _ in 0..50 {
            let m = 0.5 * (lo + hi);
            if self.head(m).0 < s { lo = m } else { hi = m }
        }
        0.5 * (lo + hi)
    }
    /// Whether the head never stops nor goes back, from 0 to `until` (its slowest speed, if not).
    pub fn check(&self, until: f64) -> Result<(), f64> {
        let mut slowest = f64::MAX;
        let mut t = 0.0;
        while t <= until {
            slowest = slowest.min(self.head(t).1);
            t += 0.01;
        }
        if slowest > 0.0 { Ok(()) } else { Err(slowest) }
    }
    /// The point at `s` along the centreline (from the origin) and its unit tangent (the way the head goes).
    pub fn point(&self, s: f64) -> ([f64; 3], [f64; 3]) {
        if self.arches.is_empty() {
            return ([0.0, s, 0.0], [0.0, 1.0, 0.0]);
        }
        for a in &self.arches {
            if s < a.s0 {
                return run_at(a, s - a.run_s());
            }
            if s <= a.s1() {
                return arch_at(a, s - a.s0);
            }
        }
        let k = self.end_knot();
        ([k[0], k[1] - (s - self.s_end()), k[2]], [0.0, -1.0, 0.0])
    }
    /// The holes, two an arch (see `WeHole`): arch i's breach is hole 2 i, its bite 2 i + 1.
    pub fn holes(&self) -> Vec<WeHole> {
        let mut out = Vec::with_capacity(2 * self.arches.len());
        for (i, a) in self.arches.iter().enumerate() {
            out.push(WeHole { kind: WeHoleKind::Breach, arch: i, at: a.from, first: a.t_out, last: self.time_at(a.s0 + WE_LEN) });
            out.push(WeHole { kind: WeHoleKind::Bite, arch: i, at: a.to, first: a.t_in, last: self.time_at(a.s1() + WE_LEN) });
        }
        out
    }
    /// The arches as the land sees them (see `WeRun`).
    pub fn runs(&self) -> Vec<WeRun> {
        self.arches
            .iter()
            .map(|a| WeRun { from: a.from, to: a.to, head_out: a.t_out, head_in: a.t_in, tail_out: self.time_at(a.s0 + WE_LEN), tail_in: self.time_at(a.s1() + WE_LEN) })
            .collect()
    }
    /// The runs underground, one into each arch, the first approach first (see `WeTunnel`).
    pub fn tunnels(&self) -> Vec<WeTunnel> {
        self.arches
            .iter()
            .enumerate()
            .map(|(i, a)| WeTunnel {
                arch: i,
                from: a.run_from,
                to: a.from,
                y: a.run_y,
                head_in: a.run_t,
                head_out: a.t_out,
                tail_in: self.time_at(a.run_s() + WE_LEN),
                tail_out: self.time_at(a.s0 + WE_LEN),
            })
            .collect()
    }
    /// Where the head is at `t` while it is underground (see `WeMound`): the land over it, the mound rising as it
    /// levels out (from rest at W0 for the first approach) and sinking as it turns up; the dome over its breach in the
    /// last WE_DOME_LEAD seconds.
    pub fn mound(&self, t: f64) -> WeMound {
        let none = WeMound { at: [0.0; 3], h: 0.0, dome: 0.0, dome_at: [0.0; 3], arch: None };
        let s = self.head(t).0;
        for (i, a) in self.arches.iter().enumerate() {
            if s > a.s1() {
                continue;
            }
            if s >= a.s0 {
                return none;
            }
            if i > 0 && s < a.run_s() {
                return none;
            }
            let p = run_at(a, s - a.run_s()).0;
            let (ex, ez) = (a.from[0] - a.run_from[0], a.from[2] - a.run_from[2]);
            let hd2 = (ex * ex + ez * ez).max(1e-9);
            let f = (((p[0] - a.run_from[0]) * ex + (p[2] - a.run_from[2]) * ez) / hd2).clamp(0.0, 1.0);
            let land = a.run_from[1] + (a.from[1] - a.run_from[1]) * f;
            let rise = if a.run_dive { ss(a.run_t + 0.5, a.run_t + 2.1, t) } else { ss(a.run_t, a.run_t + 1.6, t) };
            let h = WE_MOUND_H * rise * (1.0 - ss(a.t_out - 1.4, a.t_out - 0.4, t));
            let dome = WE_DOME_H * ss(a.t_out - WE_DOME_LEAD, a.t_out, t);
            return WeMound { at: [p[0], land, p[2]], h, dome, dome_at: a.from, arch: Some(i) };
        }
        none
    }
    /// The table's words (see the layout above), from word 0: the header and every arch, WE_A0 + n * WE_AW words.
    pub fn words(&self) -> Vec<u32> {
        let mut w = vec![0.0f32; WE_A0 + self.arches.len() * WE_AW];
        w[WE_T_COUNT] = self.arches.len() as f32;
        w[WE_T_MAGIC] = 1.0;
        w[WE_T_SIGN] = self.sign_dir[0] as f32;
        w[WE_T_SIGN + 1] = self.sign_dir[1] as f32;
        w[WE_T_LEN] = WE_LEN as f32;
        w[WE_T_T0] = self.arches.first().map_or(WE_SIGN_T0, |a| a.run_t) as f32;
        w[WE_T_V0] = self.arches.first().map_or(WE_V_SIGN, |a| a.run_v) as f32;
        for (i, a) in self.arches.iter().enumerate() {
            let r = &mut w[WE_A0 + i * WE_AW..WE_A0 + (i + 1) * WE_AW];
            for j in 0..3 {
                r[WE_R_FROM + j] = a.from[j] as f32;
                r[WE_R_TO + j] = a.to[j] as f32;
            }
            r[WE_R_APEX] = a.apex as f32;
            r[WE_R_LEN] = a.len as f32;
            r[WE_R_S] = a.s0 as f32;
            r[WE_R_RUN] = a.run_from[0] as f32;
            r[WE_R_RUN + 1] = a.run_from[2] as f32;
            r[WE_R_TOUT] = a.t_out as f32;
            r[WE_R_VOUT] = a.v_out as f32;
            r[WE_R_TIN] = a.t_in as f32;
            r[WE_R_VIN] = a.v_in as f32;
            let (h0, h1, hc, hv) = a.hold.unwrap_or((-1.0, -1.0, 0.0, 0.0));
            r[WE_R_H0] = h0 as f32;
            r[WE_R_H1] = h1 as f32;
            r[WE_R_HC] = hc as f32;
            r[WE_R_HV] = hv as f32;
            for k in 0..=WE_TN {
                r[WE_R_TH + k] = a.theta[k] as f32;
            }
            r[WE_R_RUN_LEN] = a.run_len as f32;
            r[WE_R_RUN_DIVE] = if a.run_dive { 1.0 } else { 0.0 };
            r[WE_R_RUN_LAND] = a.run_from[1] as f32;
            r[WE_R_RUN_Y] = a.run_y as f32;
            r[WE_R_RUN_T] = a.run_t as f32;
            r[WE_R_RUN_V] = a.run_v as f32;
        }
        w.into_iter().map(f32::to_bits).collect()
    }
    /// The path back from its words (as the pass reads them: f32).
    pub fn from_words(words: &[u32]) -> Self {
        let f = |i: usize| f64::from(f32::from_bits(words.get(i).copied().unwrap_or(0)));
        let n = (f(WE_T_COUNT).round() as usize).min(WE_ARCS_MAX);
        let mut p = WePath::new([f(WE_T_SIGN), f(WE_T_SIGN + 1)]);
        for i in 0..n {
            let o = WE_A0 + i * WE_AW;
            let g = |k: usize| f(o + k);
            let h0 = g(WE_R_H0);
            let mut theta = [0.0; WE_TN + 1];
            for (k, t) in theta.iter_mut().enumerate() {
                *t = g(WE_R_TH + k);
            }
            p.arches.push(WeArch {
                from: [g(WE_R_FROM), g(WE_R_FROM + 1), g(WE_R_FROM + 2)],
                to: [g(WE_R_TO), g(WE_R_TO + 1), g(WE_R_TO + 2)],
                apex: g(WE_R_APEX),
                len: g(WE_R_LEN),
                s0: g(WE_R_S),
                run_from: [g(WE_R_RUN), g(WE_R_RUN_LAND), g(WE_R_RUN + 1)],
                run_y: g(WE_R_RUN_Y),
                run_len: g(WE_R_RUN_LEN),
                run_dive: g(WE_R_RUN_DIVE) > 0.5,
                run_t: g(WE_R_RUN_T),
                run_v: g(WE_R_RUN_V),
                t_out: g(WE_R_TOUT),
                v_out: g(WE_R_VOUT),
                t_in: g(WE_R_TIN),
                v_in: g(WE_R_VIN),
                hold: (h0 >= 0.0).then(|| (h0, g(WE_R_H1), g(WE_R_HC), g(WE_R_HV))),
                theta,
            });
        }
        p
    }
}

/// A point `sp` blocks into arch `a` and its tangent.
fn arch_at(a: &WeArch, sp: f64) -> ([f64; 3], [f64; 3]) {
    let (w, d) = a.span();
    let (ax, by) = (0.5 * w, a.apex);
    let h = a.len / WE_TN as f64;
    let x = (sp / h).clamp(0.0, WE_TN as f64);
    let k = (x.floor() as usize).min(WE_TN - 1);
    let (t0, t1) = (a.theta[k], a.theta[k + 1]);
    // (the speeds at the table's own angles: a sin and a cos each, but only for these two)
    let m = |th: f64| {
        let (s, c) = th.sin_cos();
        h / ((ax * s) * (ax * s) + (by * c) * (by * c)).sqrt().max(1e-6)
    };
    let th = hermite(0.0, t0, m(t0), 1.0, t1, m(t1), x - k as f64).0;
    let (s, c) = th.sin_cos();
    let along = ax * (1.0 - c);
    let p = [a.from[0] + d[0] * along, a.from[1] + (a.to[1] - a.from[1]) * 0.5 * (1.0 - c) + by * s, a.from[2] + d[1] * along];
    let tan = norm([d[0] * ax * s, (a.to[1] - a.from[1]) * 0.5 * s + by * c, d[1] * ax * s]);
    (p, tan)
}

/// A point `u` blocks into the run into arch `a` (from where it starts; before it, for the first approach, level
/// straight back) and its tangent: down, a quarter turn to level, level, a quarter turn up, up.
fn run_at(a: &WeArch, u: f64) -> ([f64; 3], [f64; 3]) {
    let rt = WE_RUN_TURN;
    let q = 0.5 * PI * rt;
    let st = a.run_from;
    let (dx, dz) = (a.from[0] - st[0], a.from[2] - st[2]);
    let hd = (dx * dx + dz * dz).sqrt().max(1e-6);
    let e = [dx / hd, dz / hd];
    let y = a.run_y;
    let at = |x: f64, py: f64| [st[0] + e[0] * x, py, st[2] + e[1] * x];
    let mut u = u;
    let mut x0 = 0.0;
    if a.run_dive {
        let v1 = st[1] - (y + rt);
        if u < v1 {
            return ([st[0], st[1] - u, st[2]], [0.0, -1.0, 0.0]);
        }
        u -= v1;
        if u < q {
            let (s, c) = (u / rt).sin_cos();
            return (at(rt - rt * c, y + rt - rt * s), [e[0] * s, -c, e[1] * s]);
        }
        u -= q;
        x0 = rt;
    }
    let lv = hd - rt - x0;
    if u < lv {
        return (at(x0 + u, y), [e[0], 0.0, e[1]]);
    }
    u -= lv;
    if u < q {
        let (s, c) = (u / rt).sin_cos();
        return (at(hd - rt + rt * s, y + rt - rt * c), [e[0] * c, s, e[1] * c]);
    }
    u -= q;
    ([a.from[0], y + rt + u, a.from[2]], [0.0, 1.0, 0.0])
}

/// The centreline's point at `s` (from the origin).
pub fn we_point(path: &WePath, s: f64) -> [f64; 3] {
    path.point(s).0
}
/// Its unit tangent there (the way the head goes).
pub fn we_tangent(path: &WePath, s: f64) -> [f64; 3] {
    path.point(s).1
}
/// The head's `s` at strike time `t`.
pub fn we_head(path: &WePath, t: f64) -> f64 {
    path.head(t).0
}
/// The holes as the land sees them, two an arch.
pub fn we_holes(path: &WePath) -> Vec<WeHole> {
    path.holes()
}
/// The arches as the land sees them.
pub fn we_runs(path: &WePath) -> Vec<WeRun> {
    path.runs()
}
/// The runs underground as the land sees them.
pub fn we_tunnels(path: &WePath) -> Vec<WeTunnel> {
    path.tunnels()
}
/// Where the head is while underground: the mound, the dome.
pub fn we_mound(path: &WePath, t: f64) -> WeMound {
    path.mound(t)
}

/// v1's wormsign, from the constants alone (the default plan's, roughly: the world warp can't read the table): how far
/// its mound has come from W0 (0 to WE_SIGN, arriving at WE_SIGN_T) and how high it is. `we_mound` is the path's own.
pub fn we_sign(t: f64) -> (f64, f64) {
    let u = (t / WE_SIGN_T).clamp(0.0, 1.0);
    let g = 1.0 - (1.0 - u).powf(1.7);
    let along = WE_SIGN * g * g * (3.0 - 2.0 * g);
    (along, WE_MOUND_H * ss(0.0, 1.6, t) * (1.0 - ss(7.6, 8.6, t)))
}
/// v1's dome over A_0 at `t` (none from the breach on).
pub fn we_dome(t: f64) -> f64 {
    if t >= WE_BREACH { 0.0 } else { WE_DOME_H * ss(WE_DOME_T0, WE_BREACH, t) }
}
/// v1's: where its mound is at `t` (from the origin, on the level of A_0's land).
pub fn we_sign_point(geo: &WeGeo, t: f64) -> [f64; 3] {
    let a = we_sign(t).0;
    [geo.w0[0] + geo.dir[0] * a, 0.0, geo.w0[2] + geo.dir[1] * a]
}

// ---- the plans --------------------------------------------------------------------------------------------------
/// PLAN.md's show: one arch, B to D, its top WE_APEX up; out at the breach, held through the bellow round its top,
/// in at the bite, then on at the pour's speed, so that the tail comes out of B at WE_TAIL_OUT and goes into D at
/// WE_TAIL_IN.
pub fn we_default_plan(geo: &WeGeo) -> WePath {
    let (len, _) = we_arc_table(0.5 * WE_SPAN, WE_APEX);
    let pour = len / (WE_TAIL_IN - WE_TAIL_OUT);
    let mut p = WePath::new(geo.dir);
    p.push([0.0; 3], geo.d, WE_APEX, WE_BREACH, WE_V_BREACH, WE_BITE, pour, Some((WE_BELLOW.0, WE_BELLOW.1, 0.5 * len, WE_V_HOLD)));
    p
}
/// The chain's test: three arches with holes of their own, each breaching a run on from where the last dived, turning:
/// a low hop along `dir`; 220 on, turned 50 degrees left, the big arch held round its top; 200 on, turned 70 degrees
/// back to the right, a middling one.
pub fn we_plan3(geo: &WeGeo) -> WePath {
    let rot = |d: [f64; 2], deg: f64| {
        let (s, c) = deg.to_radians().sin_cos();
        [d[0] * c - d[1] * s, d[0] * s + d[1] * c]
    };
    let d0 = geo.dir;
    let d1 = rot(d0, 50.0);
    let d2 = rot(d1, -70.0);
    let on = |p: [f64; 3], d: [f64; 2], k: f64| [p[0] + d[0] * k, 0.0, p[2] + d[1] * k];
    let a0 = [0.0; 3];
    let b0 = on(a0, d0, 150.0);
    let a1 = on(b0, d1, 220.0);
    let b1 = on(a1, d1, 260.0);
    let a2 = on(b1, d2, 200.0);
    let b2 = on(a2, d2, 180.0);
    let (big, _) = we_arc_table(130.0, 250.0);
    let mut p = WePath::new(geo.dir);
    p.push(a0, b0, 90.0, WE_BREACH, 120.0, 12.0, 120.0, None);
    p.push(a1, b1, 250.0, 14.8, 120.0, 23.6, 130.0, Some((17.6, 19.1, 0.5 * big, WE_V_HOLD)));
    p.push(a2, b2, 140.0, 25.9, 130.0, 28.8, 130.0, None);
    p
}
/// The plan by number: 3 the three-arch test, else the default.
pub fn we_plan(geo: &WeGeo, which: u32) -> WePath {
    if which == 3 { we_plan3(geo) } else { we_default_plan(geo) }
}

/// The preview's check of the pass's path against this one (words from WE_DBG_T on; worldeater.wgsl's we_debug): 64
/// samples (s, x, y, z) from before W0 to past the last D, then 64 of the head (t, s) over the strike.
pub fn we_debug_words(path: &WePath) -> Vec<u32> {
    let f = |x: f64| (x as f32).to_bits();
    let mut w = vec![f(64.0)];
    let s0 = path.arches.first().map_or(-60.0, |a| a.run_s() - 60.0);
    let s1 = path.s_end() + 120.0;
    for k in 0..64 {
        let s = s0 + (s1 - s0) * k as f64 / 63.0;
        let q = path.point(s).0;
        w.extend([f(s), f(q[0]), f(q[1]), f(q[2])]);
    }
    w.push(f(64.0));
    for k in 0..64 {
        let t = WE_LEN_S * k as f64 / 63.0;
        w.extend([f(t), f(path.head(t).0)]);
    }
    w
}

// ---- the WGSL's constants (mod/build.rs) ---------------------------------------------------------------------------
/// The `[generated constants]` block of shaders/worldeater_path.wgsl: every constant the shaders share with this file.
pub fn we_wgsl_consts() -> String {
    let f: &[(&str, f64)] = &[
        ("WE_R", WE_R),
        ("WE_LEN", WE_LEN),
        ("WE_SPAN", WE_SPAN),
        ("WE_APEX", WE_APEX),
        ("WE_SIGN", WE_SIGN),
        ("WE_SIGN_T0", WE_SIGN_T0),
        ("WE_V_SIGN", WE_V_SIGN),
        ("WE_SIGN_T", WE_SIGN_T),
        ("WE_MOUND_R", WE_MOUND_R),
        ("WE_MOUND_H", WE_MOUND_H),
        ("WE_DOME_T0", WE_DOME_T0),
        ("WE_DOME_LEAD", WE_DOME_LEAD),
        ("WE_DOME_R", WE_DOME_R),
        ("WE_DOME_H", WE_DOME_H),
        ("WE_BREACH", WE_BREACH),
        ("WE_BELLOW0", WE_BELLOW.0),
        ("WE_BELLOW1", WE_BELLOW.1),
        ("WE_BITE", WE_BITE),
        ("WE_TAIL_OUT", WE_TAIL_OUT),
        ("WE_TAIL_IN", WE_TAIL_IN),
        ("WE_SINK0", WE_SINK.0),
        ("WE_SINK1", WE_SINK.1),
        ("WE_LEN_S", WE_LEN_S),
        ("WE_RUN_TURN", WE_RUN_TURN),
        ("WE_RUN_DEPTH", WE_RUN_DEPTH),
        ("WE_RUN_MIN", WE_RUN_MIN),
        ("WE_RUN_MAX", WE_RUN_MAX),
        ("WE_LOOP_D", WE_LOOP_D),
        ("WE_LOOP_R", WE_LOOP_R),
        ("WE_LOOP_ALPHA", LOOP_ALPHA),
        ("WE_LOOP_LEN", WE_LOOP_LEN),
    ];
    let u: &[(&str, usize)] = &[
        ("WE_ARCS_MAX", WE_ARCS_MAX),
        ("WE_T_COUNT", WE_T_COUNT),
        ("WE_T_MAGIC", WE_T_MAGIC),
        ("WE_T_SIGN", WE_T_SIGN),
        ("WE_T_LEN", WE_T_LEN),
        ("WE_T_T0", WE_T_T0),
        ("WE_T_V0", WE_T_V0),
        ("WE_A0", WE_A0),
        ("WE_AW", WE_AW),
        ("WE_R_FROM", WE_R_FROM),
        ("WE_R_TO", WE_R_TO),
        ("WE_R_APEX", WE_R_APEX),
        ("WE_R_LEN", WE_R_LEN),
        ("WE_R_S", WE_R_S),
        ("WE_R_RUN", WE_R_RUN),
        ("WE_R_LOOP", WE_R_LOOP),
        ("WE_R_TOUT", WE_R_TOUT),
        ("WE_R_VOUT", WE_R_VOUT),
        ("WE_R_TIN", WE_R_TIN),
        ("WE_R_VIN", WE_R_VIN),
        ("WE_R_H0", WE_R_H0),
        ("WE_R_H1", WE_R_H1),
        ("WE_R_HC", WE_R_HC),
        ("WE_R_HV", WE_R_HV),
        ("WE_R_TH", WE_R_TH),
        ("WE_TN", WE_TN),
        ("WE_R_RUN_LEN", WE_R_RUN_LEN),
        ("WE_R_RUN_DIVE", WE_R_RUN_DIVE),
        ("WE_R_RUN_LAND", WE_R_RUN_LAND),
        ("WE_R_RUN_Y", WE_R_RUN_Y),
        ("WE_R_RUN_T", WE_R_RUN_T),
        ("WE_R_RUN_V", WE_R_RUN_V),
        ("WE_PATH_END", WE_PATH_END),
        ("WE_BODY_T", WE_BODY_T),
        ("WE_FX_T", WE_FX_T),
        ("WE_LAND_T", WE_LAND_T),
        ("WE_DBG_T", WE_DBG_T),
        ("WE_EYE_T", WE_EYE_T),
    ];
    let mut s = String::from("// [generated constants] (mod/build.rs from mod/src/strike/we_path.rs's we_wgsl_consts: change them there; `cargo test we_wgsl_in_step` checks this copy, WE_REGEN=1 rewrites it)\n");
    for (name, v) in f {
        s.push_str(&format!("const {name}: f32 = {v:?};\n"));
    }
    for (name, v) in u {
        s.push_str(&format!("const {name}: u32 = {v}u;\n"));
    }
    s.push_str("// [end generated constants]\n");
    s
}
/// A caught player's eye: on the path's centreline at s(t), a C1 cubic through its knots (time, s, ds/dt), blended from
/// where they stood (rest, then a quintic ease from `beat` over `blend` seconds after the shut). The pass draws the throat
/// from it (worldeater_path.wgsl's `we_eye`, `we_eye_dir`); the carry puts the player on it every tick.
#[derive(Clone, Debug, Default)]
pub struct WeEye {
    pub t_close: f64,
    pub t_free: f64,
    pub beat: f64,
    pub blend: f64,
    pub stand: [f64; 3],
    /// Out of the mouth at time [0], at [1..4] (from the origin) moving [4..7] (blocks a second), to the let-go at
    /// [7..10] moving [10..13] (none: let go on the centreline).
    pub flight: Option<[f64; 13]>,
    pub knots: Vec<[f64; 3]>,
}
/// The eye's knots' first word (WE_EYE_T + this).
const WE_EYE_K: usize = 24;
impl WeEye {
    pub fn words(&self) -> Vec<u32> {
        let n = self.knots.len().min(WE_EYE_MAX);
        let mut w = vec![self.t_close, self.t_free, n as f64, self.beat, self.blend, self.stand[0], self.stand[1], self.stand[2]];
        w.extend_from_slice(&self.flight.unwrap_or([0.0; 13]));
        w.resize(WE_EYE_K, 0.0);
        for k in &self.knots[..n] {
            w.extend_from_slice(k);
        }
        w.into_iter().map(|v| (v as f32).to_bits()).collect()
    }
    /// From the table's words (none if no eye is written there, or it is off: [0] <= 0).
    pub fn from_words(data: &[u32]) -> Option<WeEye> {
        let w = |i: usize| f64::from(f32::from_bits(data.get(WE_EYE_T + i).copied().unwrap_or(0)));
        if w(0) <= 0.0 {
            return None;
        }
        let n = (w(2).max(0.0) as usize).min(WE_EYE_MAX);
        let flight = (w(8) > 0.0).then(|| std::array::from_fn(|i| w(8 + i)));
        Some(WeEye {
            t_close: w(0),
            t_free: w(1),
            beat: w(3),
            blend: w(4),
            stand: [w(5), w(6), w(7)],
            flight,
            knots: (0..n).map(|k| [w(WE_EYE_K + 3 * k), w(WE_EYE_K + 1 + 3 * k), w(WE_EYE_K + 2 + 3 * k)]).collect(),
        })
    }
    /// s at t: the cubic through the knots (C1), held at the ends.
    pub fn s(&self, t: f64) -> f64 {
        let k = &self.knots;
        if k.is_empty() {
            return 0.0;
        }
        if t <= k[0][0] {
            return k[0][1];
        }
        let i = k.partition_point(|x| x[0] <= t);
        if i >= k.len() {
            return k[k.len() - 1][1];
        }
        let (a, b) = (k[i - 1], k[i]);
        let dt = (b[0] - a[0]).max(1e-6);
        let u = (t - a[0]) / dt;
        let (u2, u3) = (u * u, u * u * u);
        (2.0 * u3 - 3.0 * u2 + 1.0) * a[1] + (u3 - 2.0 * u2 + u) * a[2] * dt + (-2.0 * u3 + 3.0 * u2) * b[1] + (u3 - u2) * b[2] * dt
    }
    /// How far from where they stood towards the centreline at t (0 to 1, a quintic ease: at rest at both ends).
    pub fn mix(&self, t: f64) -> f64 {
        let u = ((t - self.t_close - self.beat) / self.blend.max(1e-3)).clamp(0.0, 1.0);
        u * u * u * (u * (6.0 * u - 15.0) + 10.0)
    }
    /// The eye's place (from the origin) on `path` at t, and 1 from the shut to the let-go (else 0).
    /// Its flight's place and velocity at t (t from its start to the let-go: the cubic between them).
    pub fn flying(&self, t: f64) -> Option<([f64; 3], [f64; 3])> {
        let f = self.flight?;
        if t < f[0] {
            return None;
        }
        let d = (self.t_free - f[0]).max(1e-3);
        let u = ((t - f[0]) / d).clamp(0.0, 1.0);
        let (u2, u3) = (u * u, u * u * u);
        let (h00, h10, h01, h11) = (2.0 * u3 - 3.0 * u2 + 1.0, u3 - 2.0 * u2 + u, -2.0 * u3 + 3.0 * u2, u3 - u2);
        let (d00, d10, d01, d11) = (6.0 * u2 - 6.0 * u, 3.0 * u2 - 4.0 * u + 1.0, -6.0 * u2 + 6.0 * u, 3.0 * u2 - 2.0 * u);
        let p = std::array::from_fn(|i| h00 * f[1 + i] + h10 * f[4 + i] * d + h01 * f[7 + i] + h11 * f[10 + i] * d);
        let v = std::array::from_fn(|i| (d00 * f[1 + i] + d01 * f[7 + i]) / d + d10 * f[4 + i] + d11 * f[10 + i]);
        Some((p, v))
    }
    pub fn at(&self, path: &WePath, t: f64) -> [f64; 4] {
        if let Some((p, _)) = self.flying(t) {
            return [p[0], p[1], p[2], if t <= self.t_free { 1.0 } else { 0.0 }];
        }
        let p = path.point(self.s(t)).0;
        let m = self.mix(t);
        let w = if t >= self.t_close && t <= self.t_free { 1.0 } else { 0.0 };
        [self.stand[0] + (p[0] - self.stand[0]) * m, self.stand[1] + (p[1] - self.stand[1]) * m, self.stand[2] + (p[2] - self.stand[2]) * m, w]
    }
    /// The way it travels at t: the centreline's, towards the head.
    pub fn dir(&self, path: &WePath, t: f64) -> [f64; 3] {
        if let Some((_, v)) = self.flying(t) {
            let l = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt().max(1e-9);
            return [v[0] / l, v[1] / l, v[2] / l];
        }
        path.point(self.s(t)).1
    }
}
/// `we_eye` as the pass has it, from the table's words (none written: all 0).
pub fn we_eye(data: &[u32], t: f64) -> [f64; 4] {
    WeEye::from_words(data).map_or([0.0; 4], |e| e.at(&WePath::from_words(data), t))
}
pub fn we_eye_dir(data: &[u32], t: f64) -> [f64; 3] {
    WeEye::from_words(data).map_or([0.0, 1.0, 0.0], |e| e.dir(&WePath::from_words(data), t))
}

/// `src` with its `[generated constants]` block put right (build.rs: the pass always has Rust's numbers).
pub fn we_splice_consts(src: &str) -> String {
    let (Some(a), Some(b)) = (src.find("// [generated constants]"), src.find("// [end generated constants]\n")) else {
        panic!("worldeater_path.wgsl has no [generated constants] block");
    };
    format!("{}{}{}", &src[..a], we_wgsl_consts(), &src[b + "// [end generated constants]\n".len()..])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn geo() -> WeGeo {
        we_geo([10.5, 65.0, -2.5], [10.5, 70.0, 297.5], 37)
    }
    fn dist(a: [f64; 3], b: [f64; 3]) -> f64 {
        ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
    }
    fn hdist(a: [f64; 3], b: [f64; 3]) -> f64 {
        (a[0] - b[0]).hypot(a[2] - b[2])
    }

    #[test]
    fn the_line_runs_across_the_players_view() {
        for (me, seed) in [([10.5, 70.0, 297.5], 37), ([300.0, 64.0, 0.0], 8), ([10.5, 65.0, -2.5], 3), ([-500.0, 90.0, -800.0], 12)] {
            let g = we_geo([10.5, 65.0, -2.5], me, seed);
            assert!((g.dir[0].hypot(g.dir[1]) - 1.0).abs() < 1e-9);
            let l = g.me[0].hypot(g.me[2]);
            if l > 1.0 {
                assert!((g.dir[0] * g.me[0] + g.dir[1] * g.me[2]).abs() / l < 1e-9, "across the way they look");
            }
            assert!((dist(g.d, g.b) - WE_SPAN).abs() < 1e-9 && (dist(g.w0, g.b) - WE_SIGN).abs() < 1e-9);
            assert!(g.d[0] * g.w0[0] + g.d[2] * g.w0[2] < 0.0, "the wormsign comes from the other side");
        }
        let a = we_geo([0.0; 3], [0.0, 0.0, 300.0], 1).dir;
        let b = we_geo([0.0; 3], [0.0, 0.0, 300.0], 2).dir;
        assert!((a[0] + b[0]).abs() < 1e-9 && (a[1] + b[1]).abs() < 1e-9, "the seed picks the side");
    }

    #[test]
    fn the_arc_table_is_exact() {
        // (against a fine sum by sines and cosines)
        for (a, b) in [(130.0, 250.0), (75.0, 90.0), (300.0, 60.0)] {
            let (len, th) = we_arc_table(a, b);
            let n = 200_000;
            let h = PI / n as f64;
            let mut cum = 0.0;
            let mut k = 1;
            for i in 0..n {
                let t = (i as f64 + 0.5) * h;
                cum += h * (a * t.sin()).hypot(b * t.cos());
                while k < WE_TN && cum >= len * k as f64 / WE_TN as f64 {
                    assert!((t - th[k]).abs() < 1e-4, "{a} {b} {k}: {t} {}", th[k]);
                    k += 1;
                }
            }
            assert!((cum - len).abs() < 1e-6 * len, "{cum} {len}");
        }
    }

    #[test]
    fn the_default_plan_keeps_the_beats() {
        let p = we_default_plan(&geo());
        let a = &p.arches[0];
        assert!((a.len - 611.879).abs() < 0.01, "{}", a.len);
        assert!(we_head(&p, WE_BREACH).abs() < 1e-9);
        assert!((we_head(&p, WE_BITE) - a.len).abs() < 1e-9);
        assert!((we_head(&p, 0.0) + a.run_len).abs() < 1e-9, "at W0 as it starts");
        assert!(we_head(&p, 8.9) < -10.0, "underground before the breach");
        for t in [12.5, 13.0, 13.5, 14.0, 14.5] {
            let (s, v) = p.head(t);
            assert!(v <= WE_V_HOLD + 1e-6 && (s - 0.5 * a.len).abs() <= 10.0 + 1e-6, "{t}: {s} {v}");
        }
        let r = we_runs(&p)[0];
        assert!((r.head_out - WE_BREACH).abs() < 1e-6 && (r.head_in - WE_BITE).abs() < 1e-6);
        assert!((r.tail_out - WE_TAIL_OUT).abs() < 0.01, "{}", r.tail_out);
        assert!((r.tail_in - WE_TAIL_IN).abs() < 0.01, "{}", r.tail_in);
        let h = we_holes(&p);
        assert_eq!(h.len(), 2);
        assert!(h[0].kind == WeHoleKind::Breach && (h[0].first - WE_BREACH).abs() < 1e-9 && (h[0].last - WE_TAIL_OUT).abs() < 0.01);
        assert!(h[1].kind == WeHoleKind::Bite && (h[1].first - WE_BITE).abs() < 1e-9 && (h[1].last - WE_TAIL_IN).abs() < 0.01);
        let tu = we_tunnels(&p);
        assert_eq!(tu.len(), 1);
        assert!(hdist(tu[0].from, geo().w0) < 1e-9 && dist(tu[0].to, [0.0; 3]) < 1e-9);
        assert!(tu[0].head_in == WE_SIGN_T0 && tu[0].head_out == WE_BREACH && (tu[0].tail_out - WE_TAIL_OUT).abs() < 0.01);
        assert!(tu[0].y <= -(WE_R + 12.0));
        p.check(WE_LEN_S).unwrap();
    }

    /// Position and speed continuous at every knot of the schedule, the speed the derivative, never stopping.
    fn schedule_is_smooth(p: &WePath) {
        let e = 1e-5;
        let mut ks: Vec<f64> = p.knots().iter().map(|k| k.t).collect();
        ks.push(0.0);
        for t in ks {
            let (a, va) = p.head(t - e);
            let (b, vb) = p.head(t + e);
            assert!((a - b).abs() < 1e-2, "position at {t}: {a} {b}");
            assert!((va - vb).abs() < 1e-2, "speed at {t}: {va} {vb}");
        }
        let mut t = -5.0;
        while t < WE_LEN_S {
            let num = (p.head(t + 1e-4).0 - p.head(t - 1e-4).0) / 2e-4;
            assert!((num - p.head(t).1).abs() < 1e-2 * (1.0 + num.abs()), "{t}");
            assert!(p.head(t).1 <= WE_V_RUN_MAX + 1e-6);
            t += 0.137;
        }
        p.check(WE_LEN_S).unwrap();
    }

    /// The centreline continuous, its tangent too, at every joint (land crossings, the runs' pieces, the table's
    /// steps), each crossing vertical, its tops where they belong, the runs under the land, and `s` its length.
    fn centreline_is_smooth(p: &WePath, stretch: f64) {
        let mut joints = vec![];
        let rt = WE_RUN_TURN;
        let q = 0.5 * PI * rt;
        for a in &p.arches {
            joints.extend([a.run_s(), a.s0, a.s1()]);
            let up = a.from[1] - (a.run_y + rt);
            joints.extend([a.s0 - up, a.s0 - up - q]);
            if a.run_dive {
                let down = a.run_from[1] - (a.run_y + rt);
                joints.extend([a.run_s() + down, a.run_s() + down + q]);
            }
            for k in 0..=WE_TN {
                joints.push(a.s0 + a.len * k as f64 / WE_TN as f64);
            }
        }
        for s in joints {
            let e = 1e-6;
            let (pa, ta) = p.point(s - e);
            let (pb, tb) = p.point(s + e);
            assert!(dist(pa, pb) < 1e-3, "position at {s}: {pa:?} {pb:?}");
            assert!(dist(ta, tb) < 1e-3, "tangent at {s}: {ta:?} {tb:?}");
        }
        for (i, a) in p.arches.iter().enumerate() {
            assert!(dist(p.point(a.s0).0, a.from) < 1e-6 && dist(p.point(a.s1()).0, a.to) < 1e-6);
            assert!(p.point(a.s0).1[1] > 0.999999 && p.point(a.s1()).1[1] < -0.999999, "vertical at both feet");
            let top = p.point(a.s0 + 0.5 * a.len).0[1];
            assert!((top - (0.5 * (a.from[1] + a.to[1]) + a.apex)).abs() < 0.05, "its top {top}");
            // (the run: where it starts, under the land all the way, the body's top WE_R + 12 under its ends' lower)
            if i > 0 {
                assert!(dist(p.point(a.run_s()).0, p.arches[i - 1].to) < 1e-6);
                assert!(p.point(a.run_s()).1[1] < -0.999999);
            } else {
                assert!(hdist(p.point(a.run_s()).0, a.run_from) < 1e-6);
            }
            assert!(a.run_y + WE_R + 12.0 <= a.run_from[1].min(a.from[1]) + 1e-9);
            let mut s = a.run_s();
            while s < a.s0 {
                assert!(p.point(s).0[1] <= a.run_from[1].max(a.from[1]) + 1e-6, "{s}");
                s += 1.0;
            }
        }
        // (one block of s, about one block of centreline; the runs' exactly)
        let mut s = p.arches[0].run_s() - 300.0;
        while s < p.s_end() + 300.0 {
            let l = dist(p.point(s).0, p.point(s + 0.01).0) / 0.01;
            assert!((l - 1.0).abs() < stretch, "at {s}: {l}");
            s += 0.731;
        }
    }

    #[test]
    fn the_default_plan_is_smooth() {
        let p = we_default_plan(&geo());
        schedule_is_smooth(&p);
        centreline_is_smooth(&p, 0.012);
    }

    #[test]
    fn three_arches_with_holes_of_their_own() {
        let g = geo();
        let p = we_plan3(&g);
        assert_eq!(p.arches.len(), 3);
        schedule_is_smooth(&p);
        centreline_is_smooth(&p, 0.012);
        for (i, a) in p.arches.iter().enumerate() {
            assert!((we_head(&p, a.t_out) - a.s0).abs() < 1e-9 && (we_head(&p, a.t_in) - a.s1()).abs() < 1e-9, "arch {i}");
            if i > 0 {
                let b = &p.arches[i - 1];
                let hd = hdist(a.from, b.to);
                assert!((WE_RUN_MIN..=WE_RUN_MAX).contains(&hd), "{hd}");
                assert!((a.s0 - b.s1() - a.run_len).abs() < 1e-9);
                let (d0, d1) = (b.span().1, a.span().1);
                assert!(d0[0] * d1[0] + d0[1] * d1[1] < 0.9, "it turns");
            }
        }
        let holes = we_holes(&p);
        assert_eq!(holes.len(), 6);
        for (k, h) in holes.iter().enumerate() {
            assert!(h.first < h.last);
            for o in &holes[k + 1..] {
                assert!(hdist(h.at, o.at) > 2.0 * WE_R, "six separate holes");
            }
        }
        let runs = we_runs(&p);
        for (i, r) in runs.iter().enumerate() {
            assert!(r.head_out < r.head_in && r.head_in < r.tail_in && r.tail_out < r.tail_in && r.head_out < r.tail_out);
            assert!((we_head(&p, r.tail_in) - (p.arches[i].s1() + WE_LEN)).abs() < 1e-3);
        }
        assert!(runs[2].tail_in < WE_LEN_S, "{}", runs[2].tail_in);
        let tu = we_tunnels(&p);
        assert_eq!(tu.len(), 3);
        for (i, t) in tu.iter().enumerate() {
            assert!(t.head_in < t.head_out && t.tail_in < t.tail_out && t.head_out < t.tail_out);
            if i > 0 {
                assert!(dist(t.from, p.arches[i - 1].to) < 1e-9 && (t.head_in - p.arches[i - 1].t_in).abs() < 1e-9);
            }
        }
    }

    #[test]
    fn push_refuses_what_cant_be() {
        let g = geo();
        let mut p = we_default_plan(&g);
        let d = p.arches[0].to;
        let dir = g.dir;
        let at = |k: f64| [d[0] + dir[0] * k, 0.0, d[2] + dir[1] * k];
        let far = |k: f64| [at(k)[0] + dir[0] * 200.0, 0.0, at(k)[2] + dir[1] * 200.0];
        assert!(p.clone().try_push(at(100.0), far(100.0), 150.0, 25.0, 120.0, 30.0, 120.0, None).is_err(), "too near");
        assert!(p.clone().try_push(at(700.0), far(700.0), 150.0, 25.0, 120.0, 30.0, 120.0, None).is_err(), "too far");
        let (early, late) = p.next_window(at(300.0), 120.0).expect("a window");
        assert!(early > WE_BITE && early < late);
        let e = p.clone().try_push(at(300.0), far(300.0), 150.0, early - 0.3, 120.0, early + 4.0, 120.0, None).unwrap_err();
        assert!(e.contains("can come out at"), "{e}");
        let before = p.words();
        p.try_push(at(300.0), far(300.0), 150.0, 0.5 * (early + late), 120.0, 0.5 * (early + late) + 4.0, 120.0, None).unwrap();
        assert_eq!(p.words()[WE_A0..before.len()], before[WE_A0..]);
        schedule_is_smooth(&p);
        centreline_is_smooth(&p, 0.012);
    }

    #[test]
    fn the_land_moves_the_feet_and_the_runs() {
        let mut p = we_plan3(&geo());
        let before = p.clone();
        p.set_hole_height(1, -14.0);
        p.set_hole_height(2, 9.0);
        p.set_sign_height(6.0);
        assert_eq!((p.arches[0].to[1], p.arches[1].from[1], p.arches[0].run_from[1]), (-14.0, 9.0, 6.0));
        let (k0, k1) = (p.knots(), before.knots());
        assert!(k0.iter().zip(&k1).all(|(a, b)| a.t == b.t && a.v == b.v), "the times and speeds stay");
        schedule_is_smooth(&p);
        // (the low hop sheared 14 down over 150: its s runs within 5% of a block a block)
        centreline_is_smooth(&p, 0.05);
        for a in &p.arches {
            assert!(dist(p.point(a.s0).0, a.from) < 1e-6 && dist(p.point(a.s1()).0, a.to) < 1e-6);
        }
        // (v1's set_height: knot k is arch k-1's bite)
        let mut q = we_default_plan(&geo());
        q.set_height(1, -7.0);
        assert_eq!(q.arches[0].to[1], -7.0);
    }

    #[test]
    fn the_table_reads_back() {
        for p in [we_default_plan(&geo()), we_plan3(&geo())] {
            let w = p.words();
            assert_eq!(w.len(), WE_A0 + p.arches.len() * WE_AW);
            assert!(w.len() <= WE_PATH_END);
            assert!(WE_R_TH + WE_TN < WE_R_RUN_LEN && WE_R_RUN_V < WE_AW);
            let q = WePath::from_words(&w);
            assert_eq!(q.arches.len(), p.arches.len());
            let mut s = p.arches[0].run_s() - 100.0;
            while s < p.s_end() + 100.0 {
                assert!(dist(p.point(s).0, q.point(s).0) < 0.02, "{s}");
                s += 3.7;
            }
            // (off the knots' own times: the dome goes as the head breaks out, and f32 has it a hair either side)
            let mut t = -1.993;
            while t < WE_LEN_S {
                assert!((p.head(t).0 - q.head(t).0).abs() < 0.02, "{t}");
                let (m, n) = (p.mound(t), q.mound(t));
                assert!(dist(m.at, n.at) < 0.02 && (m.h - n.h).abs() < 1e-3 && (m.dome - n.dome).abs() < 1e-3, "{t}");
                t += 0.21;
            }
        }
    }

    #[test]
    fn an_arch_appended_changes_nothing_under_way() {
        let full = we_plan3(&geo());
        let mut part = full.clone();
        part.arches.truncate(2);
        let (wf, wp) = (full.words(), part.words());
        assert_eq!(wf[WE_A0..wp.len()], wp[WE_A0..], "the arches before it, word for word");
        let end = part.s_end();
        let mut s = part.arches[0].run_s() - 100.0;
        while s <= end + full.arches[2].run_from[1] - (full.arches[2].run_y + WE_RUN_TURN) {
            assert!(dist(full.point(s).0, part.point(s).0) < 1e-9, "{s}");
            s += 1.3;
        }
        let mut t = -2.0;
        while t <= part.arches[1].t_in {
            assert!((full.head(t).0 - part.head(t).0).abs() < 1e-9, "{t}");
            t += 0.05;
        }
    }

    #[test]
    fn the_mound_follows_the_head_underground() {
        let g = geo();
        for p in [we_default_plan(&g), we_plan3(&g)] {
            let m = p.mound(0.0);
            assert!(m.arch == Some(0) && hdist(m.at, g.w0) < 1e-6 && m.h < 1e-9, "at W0, flat, as it starts");
            assert!(p.mound(4.0).h > WE_MOUND_H * 0.99);
            let a0 = &p.arches[0];
            assert!((p.mound(a0.t_out - 1e-3).dome - WE_DOME_H).abs() < 0.01 && p.mound(a0.t_out - 1e-3).h < 1e-9);
            assert_eq!(p.mound(a0.t_out - WE_DOME_LEAD - 0.01).dome, 0.0);
            assert!(p.mound(a0.t_out + 0.01).arch.is_none() && p.mound(a0.t_out + 0.01).dome == 0.0);
            // (it comes on along the run, every step towards the breach)
            let mut last = f64::MAX;
            let mut t = 0.0;
            while t < a0.t_out - 0.5 {
                let d = hdist(p.mound(t).at, a0.from);
                assert!(d <= last + 1e-9, "{t}");
                last = d;
                t += 0.05;
            }
            for (i, a) in p.arches.iter().enumerate().skip(1) {
                let tm = 0.5 * (a.run_t + a.t_out);
                let m = p.mound(tm);
                assert_eq!(m.arch, Some(i));
                assert!(hdist(m.dome_at, a.from) < 1e-9);
                assert!(p.mound(a.t_out - 0.2).dome > 0.5 * WE_DOME_H);
            }
            assert!(p.mound(45.0).arch.is_none());
        }
    }

    #[test]
    fn v1s_wormsign_still_comes_in() {
        assert_eq!(we_sign(0.0), (0.0, 0.0));
        assert!((we_sign(WE_SIGN_T).0 - WE_SIGN).abs() < 1e-9 && we_sign(8.6).1 < 1e-9);
        assert!((we_dome(8.999) - WE_DOME_H).abs() < 0.01 && we_dome(WE_BREACH) == 0.0);
        let g = geo();
        assert!(dist(we_sign_point(&g, WE_SIGN_T), g.b) < 1e-9 && dist(we_sign_point(&g, 0.0), g.w0) < 1e-9);
    }

    /// Cheap enough for the game: no stage of building a path near a tick's share, the hot calls a few thousand
    /// instructions (as native time, ~1 ns an instruction at most here: a wasm fuel unit is about one).
    #[test]
    fn it_is_cheap() {
        let g = geo();
        let n = 200;
        let t0 = std::time::Instant::now();
        for _ in 0..n {
            std::hint::black_box(we_plan3(std::hint::black_box(&g)));
        }
        let plan = t0.elapsed().as_secs_f64() / n as f64;
        let p = we_plan3(&g);
        let t0 = std::time::Instant::now();
        let mut acc = 0.0;
        for k in 0..20_000 {
            let s = (k as f64 * 0.137) % 2500.0 - 500.0;
            acc += p.point(s).0[1] + p.head(k as f64 * 0.002).0 + p.mound(k as f64 * 0.002).h;
        }
        std::hint::black_box(acc);
        let call = t0.elapsed().as_secs_f64() / 20_000.0;
        eprintln!("we_plan3 {:.1} us (three arch tables and runs), point+head+mound {:.0} ns", plan * 1e6, call * 1e9);
        assert!(plan < 300e-6 && call < 3e-6, "{plan} {call}");
    }

    #[test]
    fn we_wgsl_in_step() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/shaders/worldeater_path.wgsl");
        let src = std::fs::read_to_string(path).unwrap();
        let want = we_splice_consts(&src);
        if want != src {
            if std::env::var("WE_REGEN").is_ok() {
                std::fs::write(path, want).unwrap();
            } else {
                panic!("shaders/worldeater_path.wgsl's [generated constants] are not we_path.rs's: run WE_REGEN=1 cargo test --release --lib we_wgsl_in_step");
            }
        }
    }

    /// `WE_PLAN=1|3 cargo test --release --lib we_print_samples -- --ignored --nocapture`: we_point, we_head, the
    /// mound, the holes, the arches and the tunnels as Rust has them.
    #[test]
    #[ignore]
    fn we_print_samples() {
        let which: u32 = std::env::var("WE_PLAN").map_or(1, |v| v.parse().unwrap());
        let g = we_geo([0.5, 65.0, 0.5], [0.0, 65.0, 300.0], 37);
        let p = we_plan(&g, which);
        let s0 = p.arches[0].run_s() - 50.0;
        for k in 0..=30 {
            let s = s0 + (p.s_end() + 150.0 - s0) * k as f64 / 30.0;
            let (q, t) = p.point(s);
            println!("s {s:9.3}  point {:9.3} {:9.3} {:9.3}  tangent {:6.3} {:6.3} {:6.3}", q[0], q[1], q[2], t[0], t[1], t[2]);
        }
        for k in 0..=46 {
            let (s, v) = p.head(k as f64);
            let m = p.mound(k as f64);
            println!("t {k:2}  head {s:9.3}  speed {v:7.3}  mound {:?} h {:.2} dome {:.2}", m.arch, m.h, m.dome);
        }
        for r in p.runs() {
            println!("{r:?}");
        }
        for h in p.holes() {
            println!("{h:?}");
        }
        for t in p.tunnels() {
            println!("{t:?}");
        }
    }
}
