//! The Sky Breaks (shaders/skybreak.wgsl draws it; strike/sb_lodge.rs lodges its shards as real blocks). No beam: a crack
//! snaps across the sky from a point high over the target, more race out after it and rings join them like a windscreen
//! hit by a stone, the panes of sky between them shift out of true; the shattered middle falls out first, a glittering
//! rain over the target, and through the hole something vast and dark looks down. Then, one after another, huge panes of
//! sky break free, still showing the sky and its clouds, tumble down with weight and smash into the land round the
//! target, where they stay as real blocks: lying low, a third buried, the earth they ploughed up heaped against them.
//! Late on the sky heals over from the edges of its holes and the cracks fade.
//!
//! Round 4: the land lifted into the sky goes first (strike/sb_lift.rs), so round 3's timeline from the first crack starts
//! SB_LEAD later; the crack is the hand behind the sky punching through it, and at the end the hand comes back down
//! through the hole and slams a fist into the land on the target (strike/sb_hand.rs, skybreak.wgsl's `[hand]`).
//!
//! The crack pattern (`Mesh`: radial cracks, rings joining them) and the falling panes (`Shard`) are worked out here
//! once, as it fires, and handed to the pass as its table (`sb_table`): keep the SB_* offsets in step with
//! skybreak.wgsl's.
use super::sb_lodge::{Lodge, Shared, Shard};
use super::*;
use std::cell::RefCell;
use std::rc::Rc;

pub(super) const TAU: f64 = 2.0 * PI;
/// The sky's pane, this far over the target's ground: its cracks, its holes, where its panes fall from.
pub(super) const SB_H: f64 = 560.0;
/// The crack pattern, as real glass breaks under a point impact (review/glass-research.md): SB_K primary radial cracks,
/// straight out from the point over the target, the sectors between them uneven; in most sectors a fork, a branch splitting
/// off one of its radials and running out at a small angle, so the legs double outwards and long dagger wedges open
/// between parent and branch; and between the cracks, concentric breaks as short chords, each sector's and each side of a
/// fork's on its own (they end on the cracks either side, slanted, never lining up into rings), close together near the
/// impact and further and further apart (and more often missing) out from it.
pub(super) const SB_K: usize = 15;
/// At most this many chords across a whole sector (before its fork), and across each side after it.
pub(super) const SB_NC: usize = 14;
pub(super) const SB_NS2: usize = 10;
/// How far out the cracks run (towards the horizon).
pub(super) const SB_FAR: f64 = 7000.0;
/// The middle (every piece no further out than this) falls out first, the smallest of it as glitter.
pub(super) const SB_MIDDLE: f64 = 105.0;
/// How far out the middle falls in sector k: uneven, so the hole it leaves is ragged, not round.
fn middle(seed: u32, k: usize) -> f64 {
    SB_MIDDLE * (0.65 + 0.7 * mh(k as u32, seed, 0x5f))
}
/// The share of the middle the fist blows out (the rest of it hangs round the hole until the hand slams the land); and
/// every cell reaching within SB_OPEN of the middle, whatever its size, goes with the fist as it hits, so the hole is
/// always wide enough for the fist and the arm to come and go through (strike/sb_hand.rs's arm keeps inside it).
const SB_INNER: f64 = 0.8;
pub(super) const SB_OPEN: f64 = 75.0;
/// How near the middle a cell comes (0 if it holds it).
pub(super) fn near(p: &[[f64; 2]]) -> f64 {
    let inside = (0..p.len()).all(|i| {
        let (a, b) = (p[i], p[(i + 1) % p.len()]);
        a[0] * b[1] - b[0] * a[1] >= 0.0
    });
    if inside {
        return 0.0;
    }
    (0..p.len())
        .map(|i| {
            let (a, b) = (p[i], p[(i + 1) % p.len()]);
            let (ex, ez) = (b[0] - a[0], b[1] - a[1]);
            let h = ((-a[0] * ex - a[1] * ez) / (ex * ex + ez * ez).max(1e-9)).clamp(0.0, 1.0);
            (a[0] + ex * h).hypot(a[1] + ez * h)
        })
        .fold(f64::MAX, f64::min)
}
/// When the hand's slam knocks the middle's outer ring loose (skybreak.wgsl's HD_KNOCK: strike/sb_hand.rs's SB_PRESS on).
pub(super) const SB_KNOCK: f32 = super::sb_hand::SB_PRESS + 0.22;
/// The strike's length (lasers.rs).
pub(super) const SB_LEN: f32 = 49.5;
/// Round 3's whole timeline, from the first crack on, starts this much later: before it, the land lifted into the sky
/// (strike/sb_lift.rs); the times below are round 3's plus this, but for the crack's, the hand's and the end's.
pub(super) const SB_LEAD: f32 = 8.75;
/// The hand punches through: the first crack (the hook). The radials race across the whole sky in a tenth of a second and
/// the rings join them by SB_SPREAD (glass breaks almost at once).
pub(super) const SB_CRACK: f32 = SB_LEAD + 0.25;
#[allow(dead_code)] // (skybreak.wgsl's: nothing here is timed by it now, the crack's sound has the rip)
pub(super) const SB_SPREAD: f32 = SB_CRACK + 0.25;
/// The shattered middle round the fist is blown down from here, its inner pieces first (its outer ring hangs on until the
/// hand slams the land: strike/sb_hand.rs).
pub(super) const SB_COLLAPSE: f32 = SB_CRACK + 0.03;
/// The first pane breaks free, and the spacing of the rest.
const SB_FIRST: f32 = SB_LEAD + 8.0;
const SB_EVERY: f32 = 1.45;
/// Seconds a pane takes to come down.
const SB_FALL: f32 = 5.3;
/// At most this many panes come down, and how far apart where they land must be.
pub(super) const SB_NS: usize = 7;
const SB_APART: f64 = 118.0;
/// The most a pane reaches from its middle to a corner.
const SB_BIG: f64 = 92.0;
/// How near the player a pane may land (its middle), and how far towards the point under the cracks' middle it drifts
/// as it falls (the share of the way from under where it was).
const SB_ME: f64 = 120.0;
const SB_IN: f64 = 0.12;
/// The eye behind the sky (skybreak.wgsl's SB_ARRIVE, SB_OPEN, SB_LOCK): it slides in from the side of the hole (12 to 14
/// s), opens 1.2 s after it is there, and finds the player: its gaze lands on them about SB_LOCK + 0.45, as its pupil
/// snaps tight (strike/sb_sounds.rs's gaze lands on it).
pub(super) const SB_LOCK: f32 = SB_LEAD + 10.4;
/// A pane strikes low end first; its far end slams down SB_SLAM later, and it is still from SB_SETTLE, when its blocks
/// may go in (skybreak.wgsl's SB_SLAM, SB_SETTLE).
pub(super) const SB_SLAM: f32 = 0.34;
pub(super) const SB_SETTLE: f32 = 0.85;
/// The sky heals over from here to SB_HEALED (the holes close from their edges, the cracks fade).
pub(super) const SB_HEAL: f32 = 40.0;
/// Mobs and dropped items this near where a pane lands die.
const SB_KILL: i32 = 70;
/// Thrown out of where each pane lands, as falling blocks.
const SB_THROWN: usize = 26;

// ---- the table (render.set-data): keep in step with skybreak.wgsl ---------------------------------------------------
/// Header: [panes, fragments, terrain, ...].
/// Then each sector's words (SB_SEC + k SB_SECW): its radial's bearing, how many whole chords, the fork (0 none, 1 off its
/// own radial k, 2 off radial k + 1), the branch's bearing, where on its radial the fork is, how many chords on its
/// near side (A, between the forked radial and the branch) and its far side (B); then the chords (each its two ends'
/// distances along the cracks either side): SB_NC whole, SB_NS2 for A, SB_NS2 for B.
pub(super) const SB_SEC: usize = 32;
pub(super) const SB_SECW: usize = 8 + 2 * (SB_NC + 2 * SB_NS2);
/// Each radial's start and run (SB_RAD + 4 k), then its sector's branch's.
pub(super) const SB_RAD: usize = SB_SEC + SB_K * SB_SECW;
/// Each cell (SB_CELL + k SB_CPS + part 21 + n): 0, or 1 + the pane it is, 64 + the fragment, or 63 for the crushed middle.
pub(super) const SB_CELL: usize = SB_RAD + 4 * SB_K;
pub(super) const SB_CPS: usize = 64;
pub(super) const SB_SH: usize = SB_CELL + SB_K * SB_CPS;
pub(super) const SB_SW: usize = 40;
pub(super) const SB_FR: usize = SB_SH + SB_NS * SB_SW;
pub(super) const SB_FW: usize = 16;
pub(super) const SB_NF: usize = 40;
/// The land's heights round the target (the dust hugs it): SB_HF_N by SB_HF_N, SB_HF_STEP apart, from SB_HF.
pub(super) const SB_HF: usize = SB_FR + SB_NF * SB_FW;
pub(super) const SB_HF_N: usize = 48;
pub(super) const SB_HF_STEP: f64 = 16.0;
pub(super) const SB_WORDS: usize = SB_HF + SB_HF_N * SB_HF_N;

/// One sector: its radial's bearing, its whole chords, its fork and the chords either side of it.
#[derive(Clone, Debug, Default)]
pub(super) struct Sector {
    pub a: f64,
    pub full: Vec<(f64, f64)>,
    pub fork: u8,
    pub b: f64,
    pub tf: f64,
    pub ca: Vec<(f64, f64)>,
    pub cb: Vec<(f64, f64)>,
}
/// A crack running straight out: where it starts, its bearing.
#[derive(Clone, Copy, Debug)]
pub(super) struct Line {
    pub o: [f64; 2],
    pub d: [f64; 2],
}
impl Line {
    pub fn at(&self, t: f64) -> [f64; 2] {
        [self.o[0] + self.d[0] * t, self.o[1] + self.d[1] * t]
    }
}
fn unit(a: f64) -> [f64; 2] {
    [a.cos(), a.sin()]
}

/// The crack pattern.
pub(super) struct Mesh {
    pub sec: Vec<Sector>,
    pub t0: [f64; SB_K],
    pub dur: [f64; SB_K],
    pub bt0: [f64; SB_K],
    pub bdur: [f64; SB_K],
}
/// Chords out from radius `r0` to `r1` (their nominal radius; each slanted, its two ends apart), as glass breaks: a
/// tight bullseye round the impact, then few and far between, more and more slanted (cross breaks, not rings), now and
/// then one missing; each stretch (`key`) denser or sparser than the next, so neighbouring ones never line up.
fn chords(seed: u32, key: u32, r0: f64, r1: f64, most: usize) -> Vec<(f64, f64)> {
    let mut out = Vec::new();
    let m = |n: u32, q: u32| mh(key * 64 + n, seed, q);
    let dens = 0.7 + 0.8 * m(63, 0x75);
    let mut r = r0;
    let mut n = 0u32;
    let (mut lo, mut ro) = (0.0f64, 0.0f64);
    while out.len() < most && n < 60 {
        let g = 0.2 + 0.6 * smooth01((r - 40.0) / 300.0) + 0.5 * smooth01((r - 400.0) / 1500.0);
        let step = r.max(6.0) * g * dens * (0.6 + 0.8 * m(n, 0x70));
        r += step.max(4.0);
        if r >= r1 {
            break;
        }
        // (slanted: one end further out than the other; out past the bullseye by up to the whole spacing)
        let sl = step * (0.55 + 0.45 * smooth01((r - 80.0) / 300.0)) * (m(n, 0x71) - 0.5);
        let (tl, tr) = (r + sl, r - sl);
        n += 1;
        if out.len() > 1 && m(n, 0x72) < 0.22 + 0.35 * smooth01((r - 150.0) / 1200.0) {
            continue;
        }
        if tl > lo + 3.0 && tr > ro + 3.0 {
            out.push((tl, tr));
            lo = tl;
            ro = tr;
        }
    }
    out
}
fn smooth01(x: f64) -> f64 {
    let u = x.clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}
impl Mesh {
    /// The mesh for a player at `me` (from the target's ground point): its first crack runs away from them behind the target
    /// and back over their head, so it crosses whatever way they look.
    pub fn new(seed: u32, me: [f64; 3]) -> Mesh {
        let step = TAU / SB_K as f64;
        let a0 = TAU * mh(0, seed, 0x50);
        // (uneven sectors, never a regular star)
        let base: Vec<f64> = (0..SB_K).map(|k| a0 + step * (k as f64 + 0.62 * (mh(k as u32, seed, 0x51) - 0.5))).collect();
        let mut sec = Vec::with_capacity(SB_K);
        for k in 0..SB_K {
            let (a, a1) = (base[k], if k + 1 < SB_K { base[k + 1] } else { base[0] + TAU });
            let width = a1 - a;
            let ku = k as u32;
            let forked = mh(ku, seed, 0x57) < 0.82;
            let rf = 60.0 + 200.0 * mh(ku, seed, 0x58).powf(1.3);
            let full = chords(seed, ku * 3, 6.0 + 6.0 * mh(ku, seed, 0x59), if forked { rf } else { 0.6 * SB_FAR }, SB_NC);
            let mut s = Sector { a, full, ..Default::default() };
            if forked && !s.full.is_empty() {
                s.fork = if mh(ku, seed, 0x5a) < 0.5 { 1 } else { 2 };
                let alpha = width * (0.25 + 0.2 * mh(ku, seed, 0x5b));
                s.b = if s.fork == 1 { a + alpha } else { a1 - alpha };
                let last = *s.full.last().unwrap();
                s.tf = if s.fork == 1 { last.0 } else { last.1 };
                let f = Line { o: [0.0; 2], d: unit(if s.fork == 1 { a } else { a1 }) }.at(s.tf);
                let br = Line { o: f, d: unit(s.b) };
                // (a nominal radius r's place along the branch: |f + d t| = r)
                let along = |r: f64| {
                    let fd = f[0] * br.d[0] + f[1] * br.d[1];
                    (fd * fd - (f[0] * f[0] + f[1] * f[1]) + r * r).max(0.0).sqrt() - fd
                };
                let r0 = last.0.max(last.1);
                // (each side's chords on its two cracks: the branch's ends as distances along it)
                let conv = |c: Vec<(f64, f64)>, branch_right: bool| -> Vec<(f64, f64)> {
                    c.into_iter().map(|(l, r)| if branch_right { (l, along(r)) } else { (along(l), r) }).collect()
                };
                let ca = chords(seed, ku * 3 + 1, r0 + 6.0, 0.6 * SB_FAR, SB_NS2);
                let cb = chords(seed, ku * 3 + 2, r0, 0.6 * SB_FAR, SB_NS2);
                // (A lies between the forked radial and the branch, B between the branch and the other radial)
                if s.fork == 1 {
                    s.ca = conv(ca, true);
                    s.cb = conv(cb, false);
                } else {
                    s.ca = conv(ca, false);
                    s.cb = conv(cb, true);
                }
            }
            sec.push(s);
        }
        // (the first crack: a V of two either side of straight away from them, opening down to the horizon behind the target,
        // and the one back over their head; the rest a hair after: glass breaks all at once, every radial across the whole
        // sky in about a tenth of a second)
        let away = if me[0].hypot(me[2]) > 1.0 { (-me[2]).atan2(-me[0]) } else { TAU * mh(1, seed, 0x54) };
        let near = |a: f64| (0..SB_K).min_by(|&x, &y| ang_off(base[x], a).total_cmp(&ang_off(base[y], a))).unwrap_or(0);
        let ka = near(away - 0.3);
        let kc = Some(near(away + 0.3)).filter(|&k| k != ka);
        let kb = near(away + PI);
        let mut t0 = [0.0; SB_K];
        let mut dur = [0.0; SB_K];
        for k in 0..SB_K {
            let off = ang_off(base[k], base[ka]).min(ang_off(base[k], base[kb]));
            if k == ka || k == kb || Some(k) == kc {
                t0[k] = f64::from(SB_CRACK) + if k == kb { 0.006 } else if Some(k) == kc { 0.012 } else { 0.0 };
                dur[k] = 0.26;
            } else {
                t0[k] = f64::from(SB_CRACK) + 0.008 + 0.018 * off / PI * 2.0 + 0.014 * mh(k as u32, seed, 0x55);
                dur[k] = 0.28 + 0.08 * mh(k as u32, seed, 0x56);
            }
        }
        let mut m = Mesh { sec, t0, dur, bt0: [1.0e9; SB_K], bdur: [1.0; SB_K] };
        // (each branch splits off when its radial's crack reaches the fork)
        for k in 0..SB_K {
            if m.sec[k].fork != 0 {
                let kr = if m.sec[k].fork == 1 { k } else { (k + 1) % SB_K };
                m.bt0[k] = m.reach_radial(kr, m.sec[k].tf) + 0.004 + 0.012 * mh(k as u32, seed, 0x5c);
                m.bdur[k] = 0.3 + 0.08 * mh(k as u32, seed, 0x5d);
            }
        }
        m
    }
    /// When radial k's crack reaches `t` out.
    pub fn reach_radial(&self, k: usize, t: f64) -> f64 {
        self.t0[k] + self.dur[k] * (1.0 - (1.0 - t / SB_FAR).max(0.0).sqrt())
    }
    /// Sector k's cracks: its two radials and its branch.
    pub fn lines(&self, k: usize) -> [Line; 3] {
        let s = &self.sec[k];
        let a1 = if k + 1 < SB_K { self.sec[k + 1].a } else { self.sec[0].a + TAU };
        let l0 = Line { o: [0.0; 2], d: unit(s.a) };
        let l1 = Line { o: [0.0; 2], d: unit(a1) };
        let f = if s.fork == 2 { l1.at(s.tf) } else { l0.at(s.tf) };
        [l0, l1, Line { o: f, d: unit(s.b) }]
    }
    /// The cells of sector k: (part 0 whole, 1 the fork's near side, 2 its far side; n; corners, counter-clockwise), the
    /// open ones out to the horizon left out.
    pub fn cells(&self, k: usize) -> Vec<(u8, usize, Vec<[f64; 2]>)> {
        let s = &self.sec[k];
        let [l0, l1, lb] = self.lines(k);
        let mut out = Vec::new();
        let mut push = |part: u8, n: usize, mut c: Vec<[f64; 2]>| {
            if area(&c) < 0.0 {
                c.reverse();
            }
            out.push((part, n, c));
        };
        for (n, &(tl, tr)) in s.full.iter().enumerate() {
            if n == 0 {
                push(0, 0, vec![[0.0, 0.0], l1.at(tr), l0.at(tl)]);
            } else {
                let (pl, pr) = s.full[n - 1];
                push(0, n, vec![l0.at(pl), l1.at(pr), l1.at(tr), l0.at(tl)]);
            }
        }
        if s.fork != 0 {
            let (al, ar) = if s.fork == 1 { (l0, lb) } else { (lb, l1) };
            let (bl, brl) = if s.fork == 1 { (lb, l1) } else { (l0, lb) };
            let f = lb.o;
            for (n, &(tl, tr)) in s.ca.iter().enumerate() {
                if n == 0 {
                    push(1, 0, vec![f, ar.at(tr), al.at(tl)]);
                } else {
                    let (pl, pr) = s.ca[n - 1];
                    push(1, n, vec![al.at(pl), ar.at(pr), ar.at(tr), al.at(tl)]);
                }
            }
            let last = *s.full.last().unwrap();
            for (n, &(tl, tr)) in s.cb.iter().enumerate() {
                if n == 0 {
                    // (its inside the whole sector's last chord, from the fork to the other radial)
                    let inner = if s.fork == 1 { [f, l1.at(last.1)] } else { [l0.at(last.0), f] };
                    push(2, 0, vec![inner[0], inner[1], brl.at(tr), bl.at(tl)]);
                } else {
                    let (pl, pr) = s.cb[n - 1];
                    push(2, n, vec![bl.at(pl), brl.at(pr), brl.at(tr), bl.at(tl)]);
                }
            }
        }
        out
    }
}
/// How far apart two bearings are, 0 to PI.
fn ang_off(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(TAU);
    d.min(TAU - d)
}
/// A polygon's signed area (positive counter-clockwise, x right and z up).
pub(super) fn area(p: &[[f64; 2]]) -> f64 {
    (0..p.len()).map(|i| {
        let (a, b) = (p[i], p[(i + 1) % p.len()]);
        a[0] * b[1] - b[0] * a[1]
    }).sum::<f64>() * 0.5
}
fn centroid(p: &[[f64; 2]]) -> [f64; 2] {
    let (mut cx, mut cz, mut a) = (0.0, 0.0, 0.0);
    for i in 0..p.len() {
        let (u, v) = (p[i], p[(i + 1) % p.len()]);
        let c = u[0] * v[1] - v[0] * u[1];
        a += c;
        cx += (u[0] + v[0]) * c;
        cz += (u[1] + v[1]) * c;
    }
    [cx / (3.0 * a), cz / (3.0 * a)]
}
fn convex(p: &[[f64; 2]]) -> bool {
    (0..p.len()).all(|i| {
        let (a, b, c) = (p[i], p[(i + 1) % p.len()], p[(i + 2) % p.len()]);
        (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) > 1.0
    })
}
/// A cell's place in the table.
pub(super) fn cell_id(k: usize, part: u8, n: usize) -> usize {
    k * SB_CPS + usize::from(part) * 21 + n.min(20)
}

/// The panes that come down: cells of the pattern 110 to 380 out, the long ones first, where they land, when; in the
/// order they break free.
pub(super) fn sb_shards(mesh: &Mesh, seed: u32, me: [f64; 3]) -> Vec<Shard> {
    // (every closed cell in reach, the long ones (daggers) ahead of the rest, mixed; each kept if it lands clear of the
    // player and of those already kept)
    let mut cand: Vec<(f64, usize, Vec<[f64; 2]>, [f64; 2], f64)> = Vec::new();
    for k in 0..SB_K {
        for (part, n, poly) in mesh.cells(k) {
            if poly.len() > 4 || !convex(&poly) || poly.iter().all(|v| v[0].hypot(v[1]) <= middle(seed, k)) {
                continue;
            }
            let c = centroid(&poly);
            let rc = c[0].hypot(c[1]);
            if !(95.0..=440.0).contains(&rc) {
                continue;
            }
            let reach = poly.iter().map(|v| (v[0] - c[0]).hypot(v[1] - c[1])).fold(0.0, f64::max);
            if !(26.0..=SB_BIG + 8.0).contains(&reach) {
                continue;
            }
            // (how long against how wide: along the line out from the middle, and across it)
            let (ux, uz) = (c[0] / rc, c[1] / rc);
            let (mut a0, mut a1, mut w0, mut w1) = (f64::MAX, f64::MIN, f64::MAX, f64::MIN);
            for v in &poly {
                let (s, w) = ((v[0] - c[0]) * ux + (v[1] - c[1]) * uz, (v[1] - c[1]) * ux - (v[0] - c[0]) * uz);
                (a0, a1, w0, w1) = (a0.min(s), a1.max(s), w0.min(w), w1.max(w));
            }
            // (a dagger, not a sliver: a pane has to be big enough to read lying on the land; those a little out of
            // the usual run only if there are too few of the rest)
            if w1 - w0 < 18.0 || area(&poly) < 1500.0 {
                continue;
            }
            let usual = (105.0..=400.0).contains(&rc) && (30.0..=SB_BIG).contains(&reach) && w1 - w0 >= 24.0 && area(&poly) >= 1700.0;
            let aspect = ((a1 - a0) / (w1 - w0).max(1.0)).min(4.0);
            let id = cell_id(k, part, n);
            cand.push((mh(id as u32, seed, 0x60) - 0.22 * aspect + if usual { 0.0 } else { 10.0 }, id, poly, c, reach));
        }
    }
    cand.sort_by(|a, b| a.0.total_cmp(&b.0));
    let mut kept: Vec<(usize, Vec<[f64; 2]>, [f64; 2], [f64; 2])> = Vec::new();
    for (_, id, poly, c, reach) in cand {
        if kept.len() >= SB_NS {
            break;
        }
        let site = [c[0] * (1.0 - SB_IN), c[1] * (1.0 - SB_IN)];
        if (site[0] - me[0]).hypot(site[1] - me[2]) < SB_ME + reach {
            continue;
        }
        if kept.iter().any(|s| (s.3[0] - site[0]).hypot(s.3[1] - site[1]) < SB_APART) {
            continue;
        }
        kept.push((id, poly, c, site));
    }
    // (the farthest from the player first: the last, the nearest, the loudest)
    kept.sort_by(|a, b| {
        let d = |s: &[f64; 2]| (s[0] - me[0]).hypot(s[1] - me[2]);
        d(&b.3).total_cmp(&d(&a.3))
    });
    kept.into_iter()
        .enumerate()
        .map(|(i, (id, poly, c, site))| {
            let local: Vec<[f64; 2]> = poly.iter().map(|v| [v[0] - c[0], v[1] - c[1]]).collect();
            let tr = SB_FIRST + SB_EVERY * i as f32 + 0.4 * (mh(i as u32, seed, 0x61) as f32 - 0.5);
            let hit = tr + SB_FALL + 0.5 * mh(i as u32, seed, 0x62) as f32;
            let th = 6.0 + 2.0 * mh(i as u32, seed, 0x63);
            // (it lies the way it came down: in towards the middle, its low end first)
            let n = site[0].hypot(site[1]).max(1.0);
            let lay = (-site[0] / n, -site[1] / n);
            Shard::new(i, id, local, th, c, site, tr, hit, lay, seed, me)
        })
        .collect()
}

/// The pieces of the shattered middle (every cell no further out than SB_MIDDLE): (its cell, corners from its middle,
/// middle, when it falls, whether the hand drags it); the smallest are not here (crushed: they go as glitter,
/// `sb_crushed`). The inner part (SB_INNER of the way out) is blown down by the fist, the middle first, a few of its pieces
/// caught on the arm and dragged up as it withdraws (falling off it from `when`); the outer ring falls as the hand's slam
/// knocks it loose.
pub(super) fn sb_fragments(mesh: &Mesh, seed: u32) -> Vec<Frag> {
    let (mut inner, mut outer) = (Vec::new(), Vec::new());
    for k in 0..SB_K {
        let (rm, ri) = (middle(seed, k), SB_INNER * middle(seed, k));
        for (part, n, poly) in mesh.cells(k) {
            let far = poly.iter().map(|v| v[0].hypot(v[1])).fold(0.0, f64::max);
            let nr = near(&poly);
            if (far > rm && nr >= SB_OPEN) || poly.len() > 4 {
                continue;
            }
            let c = centroid(&poly);
            let reach = poly.iter().map(|v| (v[0] - c[0]).hypot(v[1] - c[1])).fold(0.0, f64::max);
            if reach < 7.0 {
                continue;
            }
            let id = cell_id(k, part, n);
            let rc = c[0].hypot(c[1]);
            let local: Vec<[f64; 2]> = poly.iter().map(|v| [v[0] - c[0], v[1] - c[1]]).collect();
            if nr < SB_OPEN {
                // (where the fist goes through: gone as it hits)
                inner.push((id, local, c, SB_CRACK + 0.015 * (nr / SB_OPEN) as f32, false));
            } else if far <= ri {
                // (the fist's: the middle at once, then out from it, a third of a second across)
                let t = SB_COLLAPSE + 0.3 * (rc / ri).min(1.0).powf(1.2) as f32 + 0.08 * mh(id as u32, seed, 0x64) as f32;
                inner.push((id, local, c, t, false));
            } else {
                // (the slam's: knocked loose as its shudder comes through the glass, the inner edge of the ring first)
                let u = ((rc - ri) / (rm - ri).max(1.0)).clamp(0.0, 1.0);
                let t = SB_KNOCK + 0.55 * u as f32 + 0.3 * mh(id as u32, seed, 0x64) as f32;
                outer.push((id, local, c, t, false));
            }
        }
    }
    // (the biggest of each, if there are more than the pass takes)
    let big = |a: &Frag, b: &Frag| {
        let r = |p: &Vec<[f64; 2]>| p.iter().map(|v| v[0].hypot(v[1])).fold(0.0, f64::max);
        r(&b.1).total_cmp(&r(&a.1))
    };
    inner.sort_by(big);
    outer.sort_by(big);
    outer.truncate(SB_NF_OUTER);
    inner.truncate(SB_NF - outer.len());
    // (a few caught on the arm: from round the fist, not its very middle, the biggest of them; dragged up as it withdraws
    // and falling off it one after another)
    let mut drag = 0;
    for f in inner.iter_mut() {
        let rc = f.2[0].hypot(f.2[1]);
        if drag < SB_DRAGGED && (16.0..60.0).contains(&rc) {
            f.3 = super::sb_hand::SB_LET_GO + 0.3 * drag as f32 + 0.2 * mh(f.0 as u32, seed, 0x68) as f32;
            f.4 = true;
            drag += 1;
        }
    }
    let mut out = inner;
    out.extend(outer);
    out.sort_by(|a, b| a.3.total_cmp(&b.3));
    out
}
/// A fragment of the middle: its cell, corners from its middle, middle, when it falls, whether the hand drags it first.
pub(super) type Frag = (usize, Vec<[f64; 2]>, [f64; 2], f32, bool);
/// At most this many of the fragments are the outer ring's (the rest the fist's), and this many are dragged up.
const SB_NF_OUTER: usize = 14;
const SB_DRAGGED: usize = 3;
/// The cells of the middle too small to fall as pieces: they go as glitter as the fist blows it out (63) or as the slam
/// knocks the outer ring loose (62).
pub(super) fn sb_crushed(mesh: &Mesh, seed: u32) -> Vec<(usize, u32)> {
    let mut out = Vec::new();
    for k in 0..SB_K {
        for (part, n, poly) in mesh.cells(k) {
            let far = poly.iter().map(|v| v[0].hypot(v[1])).fold(0.0, f64::max);
            let nr = near(&poly);
            if far <= middle(seed, k) || nr < SB_OPEN {
                out.push((cell_id(k, part, n), if far <= SB_INNER * middle(seed, k) || nr < SB_OPEN { 63 } else { 62 }));
            }
        }
    }
    out
}

/// The pass's table: the sectors, the cracks' runs, the cells, the panes and the fragments (the land's heights later).
pub(super) fn sb_table(mesh: &Mesh, shards: &[Shard], frags: &[Frag], seed: u32, terrain: bool) -> Vec<u32> {
    let mut w = vec![0u32; SB_HF];
    let f = |v: f64| (v as f32).to_bits();
    w[0] = f(shards.len() as f64);
    w[1] = f(frags.len() as f64);
    w[2] = f(if terrain { 1.0 } else { 0.0 });
    for (k, s) in mesh.sec.iter().enumerate() {
        let b = SB_SEC + k * SB_SECW;
        w[b] = f(s.a);
        w[b + 1] = f(s.full.len() as f64);
        w[b + 2] = f(f64::from(s.fork));
        w[b + 3] = f(s.b);
        w[b + 4] = f(s.tf);
        w[b + 5] = f(s.ca.len() as f64);
        w[b + 6] = f(s.cb.len() as f64);
        for (n, c) in s.full.iter().enumerate() {
            w[b + 8 + 2 * n] = f(c.0);
            w[b + 9 + 2 * n] = f(c.1);
        }
        for (n, c) in s.ca.iter().enumerate() {
            w[b + 8 + 2 * SB_NC + 2 * n] = f(c.0);
            w[b + 9 + 2 * SB_NC + 2 * n] = f(c.1);
        }
        for (n, c) in s.cb.iter().enumerate() {
            w[b + 8 + 2 * (SB_NC + SB_NS2) + 2 * n] = f(c.0);
            w[b + 9 + 2 * (SB_NC + SB_NS2) + 2 * n] = f(c.1);
        }
        w[SB_RAD + 4 * k] = f(mesh.t0[k]);
        w[SB_RAD + 4 * k + 1] = f(mesh.dur[k]);
        w[SB_RAD + 4 * k + 2] = f(mesh.bt0[k]);
        w[SB_RAD + 4 * k + 3] = f(mesh.bdur[k]);
    }
    for (id, code) in sb_crushed(mesh, seed) {
        w[SB_CELL + id] = code;
    }
    for (i, s) in shards.iter().enumerate() {
        w[SB_CELL + s.cell] = 1 + i as u32;
        w[SB_SH + i * SB_SW..SB_SH + (i + 1) * SB_SW].copy_from_slice(&s.words(0.0));
    }
    for (i, (id, poly, c, t, dragged)) in frags.iter().enumerate() {
        w[SB_CELL + id] = 64 + i as u32;
        let b = SB_FR + i * SB_FW;
        for (n, v) in poly.iter().enumerate().take(4) {
            w[b + 2 * n] = f(v[0]);
            w[b + 2 * n + 1] = f(v[1]);
        }
        if poly.len() == 3 {
            w[b + 6] = f(poly[2][0]);
            w[b + 7] = f(poly[2][1]);
        }
        w[b + 8] = f(poly.len() as f64);
        w[b + 9] = f(c[0]);
        w[b + 10] = f(c[1]);
        w[b + 11] = f(f64::from(*t));
        // (how it tumbles: about which way, how fast; and when, after it falls, it shatters into glitter)
        w[b + 12] = f(TAU * mh(i as u32, seed, 0x65));
        w[b + 13] = f(1.4 + 2.2 * mh(i as u32, seed, 0x66));
        w[b + 14] = f(2.4 + 1.3 * mh(i as u32, seed, 0x67));
        // (dragged up on the arm until it falls off at `t`)
        w[b + 15] = f(if *dragged { 1.0 } else { 0.0 });
    }
    w
}

/// The land's heights round the target for the pass (its dust follows them): SB_HF_N by SB_HF_N columns, SB_HF_STEP
/// apart, centred on the target's column.
pub(super) fn sb_hf_columns(bx: i32, bz: i32) -> Vec<(i32, i32)> {
    let h = (SB_HF_N as f64 - 1.0) * 0.5;
    let mut out = Vec::with_capacity(SB_HF_N * SB_HF_N);
    for k in 0..SB_HF_N {
        for i in 0..SB_HF_N {
            out.push((bx + ((i as f64 - h) * SB_HF_STEP).round() as i32, bz + ((k as f64 - h) * SB_HF_STEP).round() as i32));
        }
    }
    out
}
fn sb_hf_words(cols: &[(i32, i32)], gy: i32) -> Vec<u32> {
    crate::meter::spend(120 * cols.len() as u64);
    cols.iter().map(|&(x, z)| (crate::ground::at(x, z).map_or(0.0, |g| (g + crate::ground::water(x, z).unwrap_or(0) - gy) as f32)).to_bits()).collect()
}

/// The chunk rows (x0, z0, x1, z1) that hold every chunk within its `r` of any of `sites` (from the target's column `c`):
/// each chunk once, so its forceload is added and removed once.
fn sb_load_rows(c: [f64; 2], sites: &[([f64; 2], f64)]) -> Vec<[i32; 4]> {
    let mut set: std::collections::BTreeSet<(i32, i32)> = Default::default();
    for &(s, r) in sites {
        let (x, z) = (c[0] + s[0], c[1] + s[1]);
        let (c0x, c1x) = (((x - r).floor() as i32) >> 4, ((x + r).floor() as i32) >> 4);
        let (c0z, c1z) = (((z - r).floor() as i32) >> 4, ((z + r).floor() as i32) >> 4);
        for cz in c0z..=c1z {
            for cx in c0x..=c1x {
                let (x0, z0) = (f64::from(cx * 16), f64::from(cz * 16));
                let nx = (x - x0).clamp(0.0, 16.0) + x0 - x;
                let nz = (z - z0).clamp(0.0, 16.0) + z0 - z;
                if nx * nx + nz * nz <= r * r {
                    set.insert((cz, cx));
                }
            }
        }
    }
    let mut out = Vec::new();
    let mut run: Option<(i32, i32, i32)> = None;
    for (cz, cx) in set {
        run = match run {
            Some((z, a, b)) if z == cz && b + 1 == cx => Some((z, a, cx)),
            Some((z, a, b)) => {
                out.push([a * 16, z * 16, b * 16 + 15, z * 16 + 15]);
                Some((cz, cx, cx))
            }
            None => Some((cz, cx, cx)),
        };
    }
    if let Some((z, a, b)) = run {
        out.push([a * 16, z * 16, b * 16 + 15, z * 16 + 15]);
    }
    out
}

/// How much of an impact is heard through a long stretch of air (`impact_far`), `dist` blocks off.
fn sb_far(dist: f64) -> f32 {
    let u = ((dist - 350.0) / 650.0).clamp(0.0, 1.0);
    (u * u * (3.0 - 2.0 * u)) as f32
}

/// A pane's impact reaching the player `fo` as hard at `t`: a hard hit, a few quick jolts, a rumble fading.
fn sb_jolt(p: &mut Plan, t: f32, fo: f32) {
    p.shake(t, fo, 0.7);
    for n in 0..5 {
        p.shake(t + 0.1 * (n + 1) as f32, (0.8 - 0.1 * n as f32) * fo, 0.14);
    }
    for n in 0..10 {
        let u = n as f32 / 10.0;
        p.shake(t + 0.6 + 0.12 * n as f32, (0.4 * (1.0 - u) + 0.05) * fo, 0.12);
    }
}

/// The Sky Breaks.
pub(super) fn skybreak_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed_i = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed_i as u64), bx, by, bz };
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let seed = shader_seed as u32;
    let rel = [me[0] - cx, me[1] - gy, me[2] - cz];
    let mesh = Mesh::new(seed, rel);
    let shards = sb_shards(&mesh, seed, rel);
    let frags = sb_fragments(&mesh, seed);
    let table = sb_table(&mesh, &shards, &frags, seed, terrain);
    let mut sites: Vec<([f64; 2], f64)> = shards.iter().map(|s| (s.site, super::sb_lodge::SB_PATCH)).collect();
    // (the hand: where its fist slams the land, on the target (strike/sb_hand.rs); its crater's chunks force-loaded with
    // theirs)
    let print = super::sb_hand::Print::new(rel, &shards, seed);
    sites.push((print.site, 145.0));
    // (the opening's island: the chunks it is read from and cut out of (strike/sb_lift.rs's lf_columns, all within 14 of
    // the target's column), held with the rest so none of theirs is let go early)
    sites.push(([0.0, 0.0], f64::from(super::sb_lift::LF_H) + 2.0));
    let hand = Rc::new(RefCell::new(super::sb_hand::Hand::new(print, terrain, rel)));
    let hits: Vec<(f32, [f64; 3], f64)> = shards.iter().map(|s| (s.hit, [s.site[0], 0.0, s.site[1]], s.size())).collect();
    let lodge: Shared = Rc::new(RefCell::new(Lodge::new(shards, seed, terrain, rel, [cx, gy, cz])));
    let _ = sb_far;

    // the pass's table, on the tick after it fires; the land's heights round the target asked as it starts
    p.later(0.05, move |q| q.ev.push((0.05, Act::Table(table))));
    {
        let tag = crate::ground::new_tag();
        let cols = sb_hf_columns(bx, bz);
        let c2 = cols.clone();
        p.later(0.1, move |q| q.ev.push((0.1, Act::Survey { tag, columns: c2 })));
        fn hf_step(q: &mut Plan, tag: u32, cols: Vec<(i32, i32)>, at: f32) {
            if crate::ground::ready(tag) || at > 6.0 {
                let w = sb_hf_words(&cols, q.by + 1);
                q.ev.push((at, Act::Words { index: SB_HF as u32, words: w }));
            } else {
                let t = at + 0.25;
                q.later(t, move |q| hf_step(q, tag, cols, t));
            }
        }
        p.later(0.4, move |q| hf_step(q, tag, cols, 0.4));
    }

    // the opening, before the first crack: the island torn out and into the sky (strike/sb_lift.rs)
    super::sb_lift::sb_lift_plan(&mut p, seed, terrain, rel);

    // ---- the sounds: the sky breaking over them, the panes coming down, each impact late by how far it is ---------------
    // (all but the panes' own: strike/sb_sounds.rs)
    p.ev.extend(super::sb_sounds::sb_cues([cx, gy, cz], me, &hits));
    // (the jolt of the first crack)
    p.shake(SB_CRACK, 0.5, 0.18);
    for n in 0..6 {
        p.shake(SB_CRACK + 0.12 + 0.11 * n as f32, 0.28 * (1.0 - n as f32 / 6.0) + 0.05, 0.12);
    }
    p.shake(SB_LOCK + 0.45, 0.32, 0.5);

    // ---- the land: the panes' sites force-loaded from the start; each pane's ground asked, its pose settled, its blocks
    // laid as it lands (strike/sb_lodge.rs) ----------------------------------------------------------------------------
    let load = sb_load_rows([cx, cz], &sites);
    for [x0, z0, x1, z1] in &load {
        p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
    }
    for [x0, z0, x1, z1] in &load {
        p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
    }
    super::sb_lodge::sb_lodge_plan(&mut p, lodge.clone());
    super::sb_hand::sb_hand_plan(&mut p, hand, rel);
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}
/// Pane `i`'s own events, from when it breaks free (`tr`) to its impact (`hit`) and after: its sounds (late by how far
/// it is from the player at `me`, from the target's ground point `at`), the jolt, the dust and grit for anyone close,
/// the mobs killed, what it throws. Worked out once its pose is settled (strike/sb_lodge.rs), so a pane held back for
/// its land is heard when it falls.
#[allow(clippy::too_many_arguments)]
pub(super) fn sb_pane_events(p: &mut Plan, i: usize, tr: f32, hit: f32, foot: [f64; 3], size: f64, me: [f64; 3], at: [f64; 3], seed: u32, terrain: bool) {
    let (cx, gy, cz) = (at[0], at[1], at[2]);
    let me = [me[0] + cx, me[1] + gy, me[2] + cz];
    let (dl0, _) = sound_from([cx, gy + SB_H, cz], me);
    let sky_late = dl0.min(1.2);
    let (x, y, z) = (cx + foot[0], gy + foot[1], cz + foot[2]);
    let (late, dist) = sound_from([x, y, z], me);
    // (breaking free: a deep cleave up there; its fall a roar coming down on them, cut off as it hits)
    let pitch = 0.92 + 0.16 * mh(i as u32, seed, 0x70) as f32;
    p.csound(tr - SB_SAG - 0.2 + sky_late * 0.4, if i % 2 == 0 { "release" } else { "release2" }, 10.0, pitch);
    p.csound(hit - SB_FALL_SND, "fall", 10.0 * (0.55 + 0.45 * (1.0 / (1.0 + dist as f32 / 500.0)).min(1.0)), 0.95 + 0.1 * mh(i as u32, seed, 0x71) as f32);
    // (the ground's thump first, then the impact through the air, from far off its top let down)
    let tg = hit + (dist / 1715.0) as f32;
    let gap = hit + late - tg;
    let gv = ((1.0 / (1.0 + dist / 900.0)).clamp(0.3, 1.0) * (f64::from(gap - 0.05) / 0.9).clamp(0.25, 1.0).powf(1.5)) as f32;
    p.csound(tg - 0.02, "ground", 10.0 * gv, 1.0);
    let far = sb_far(dist);
    let size_k = (size / 100.0).clamp(0.8, 1.15) as f32;
    let take = ["impact", "impact2", "impact3"][i % 3];
    if far < 1.0 {
        p.csound(hit + late - 0.02, take, 10.0 * (1.0 - far), (1.04 - 0.08 * size_k) * pitch);
    }
    if far > 0.0 {
        p.csound(hit + late - 0.02, "impact_far", 10.0 * far, pitch);
    }
    let fo = (1.5 / (1.0 + dist / 260.0)).clamp(0.2, 1.0) as f32;
    sb_jolt(p, hit + late, fo);
    // (its far end slamming down after: a second blow, heavy and short)
    p.csound(hit + SB_SLAM + late - 0.01, "slam", 6.0 * (1.0 - 0.6 * far), pitch);
    p.shake(hit + SB_SLAM + late, 0.85 * fo, 0.35);
    // (real dust and grit where it lands, for anyone close)
    p.at(hit + 0.1, format!("particle minecraft:explosion_emitter {x:.1} {:.1} {z:.1} 8 3 8 0 5 force", y + 3.0));
    p.at(hit + 0.15, format!(r#"particle minecraft:block{{block_state:"minecraft:packed_ice"}} {x:.1} {:.1} {z:.1} 16 6 16 0.8 300 force"#, y + 6.0));
    p.at(hit + 0.2, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {x:.1} {:.1} {z:.1} 18 5 18 0.8 300 force"#, y + 4.0));
    if terrain {
        for t in [hit + 0.1, hit + 1.5] {
            p.at(t, format!("execute positioned {x:.1} {y:.1} {z:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{SB_KILL}]"));
        }
        sb_thrown(p, i, hit, foot, size, seed);
    }
}
/// A pane sags this long before it breaks free (skybreak.wgsl's SB_SAG).
pub(super) const SB_SAG: f32 = 1.3;

/// The fall's roar starts this long before its pane lands (cut dead on the impact, `tools/sounds_skybreak.py`'s FALL_CUT).
pub(super) const SB_FALL_SND: f32 = 4.6;

/// Falling blocks thrown out of where pane `i` lands (`foot`, from the target's ground point): its ground and its
/// broken edge, outward and up.
fn sb_thrown(q: &mut Plan, i: usize, hit: f32, foot: [f64; 3], size: f64, seed: u32) {
    let (cx, cz) = (f64::from(q.bx) + 0.5, f64::from(q.bz) + 0.5);
    let gy = f64::from(q.by) + 1.0;
    let mut rng = Rng::new(u64::from(seed) ^ 0x51ab ^ (i as u64 * 977));
    for n in 0..SB_THROWN {
        let a = rng.uniform(0.0, TAU);
        let r = rng.uniform(0.0, 0.25 * size);
        let (x, z) = (cx + foot[0] + a.cos() * r, cz + foot[2] + a.sin() * r);
        let blk = match rng.next() {
            d if d < 0.3 => "minecraft:packed_ice",
            d if d < 0.4 => "minecraft:blue_ice",
            d if d < 0.65 => "minecraft:dirt",
            d if d < 0.8 => "minecraft:coarse_dirt",
            d if d < 0.9 => "minecraft:cobblestone",
            _ => "minecraft:stone",
        };
        let h = 0.3 + 1.6 * rng.next().powf(1.4);
        let vy = 0.6 + 1.2 * rng.next();
        let (vx, vz) = (a.cos() * h, a.sin() * h);
        let y = gy + foot[1] + 2.0 + 3.0 * rng.next();
        let t = hit + 0.05 + 1.2 * rng.next().powf(1.3) as f32;
        let keep = if n % 2 == 0 { "" } else { ",CancelDrop:1b" };
        q.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
    }
}

#[cfg(test)]
mod table {
    use super::*;
    /// `CB_SEED=37 CB_OUT=path PL_ME=x,y,z cargo test --release sb_write_table -- --ignored`: the table the pass reads,
    /// for tools/preview.py (a line `index value` a word), the target's ground at the preview's (0.5 65 0.5), the player
    /// at PL_ME; the panes settled on the preview's land (PL_HILLS=H its hills, flat otherwise). With SB_VOX=path also
    /// the blocks the panes leave, as the preview's voxels (`x y z r g b`).
    #[test]
    #[ignore]
    fn sb_write_table() {
        let seed: u32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse::<f32>().unwrap()) as u32;
        let me: Vec<f64> = std::env::var("PL_ME").map_or(vec![0.0, 70.0, 300.0], |v| v.split(',').map(|x| x.parse().unwrap()).collect());
        let rel = [me[0] - 0.5, me[1] - 65.0, me[2] - 0.5];
        let hills: f64 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap());
        let mesh = Mesh::new(seed, rel);
        let mut shards = sb_shards(&mesh, seed, rel);
        let h = move |x: f64, z: f64| hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin());
        for s in &mut shards {
            s.settle_test(&|x, z| h(f64::from(x) + 0.5, f64::from(z) + 0.5), 0, 0, seed);
        }
        let frags = sb_fragments(&mesh, seed);
        let terrain = std::env::var("SB_TERRAIN").map_or(true, |v| v != "0");
        let mut w = sb_table(&mesh, &shards, &frags, seed, terrain);
        let gone: f32 = std::env::var("SB_GONE").map_or(1.0e6, |v| v.parse().unwrap());
        for i in 0..shards.len() {
            w[SB_SH + i * SB_SW + 14] = gone.to_bits();
        }
        let cols = sb_hf_columns(0, 0);
        w.resize(SB_WORDS, 0);
        for (n, &(x, z)) in cols.iter().enumerate() {
            w[SB_HF + n] = (h(f64::from(x) + 0.5, f64::from(z) + 0.5) as f32).to_bits();
        }
        // (the opening's words, on the preview's land: strike/sb_lift.rs)
        super::super::sb_lift::lf_preview(&mut w, seed, terrain);
        // (the hand's words, on the preview's land)
        let mut print = super::super::sb_hand::Print::new(rel, &shards, seed);
        print.g0 = h(print.site[0] + 0.5, print.site[1] + 0.5).round();
        w.resize(super::super::sb_hand::SB_HD, 0);
        w.extend(print.words(terrain));
        let arm = super::super::sb_hand::Arm::new(&print, rel);
        w.extend(arm.table(0));
        w.extend(arm.table(1));
        // (the sculpted hand's grids)
        w.resize(super::super::sb_hand::SB_HB, 0);
        w.extend(super::super::sb_hand::sb_hand_grids());
        eprintln!("the hand at {:.0} {:.0} (pointing {:.2} {:.2}, side {})", print.site[0], print.site[1], print.dir[0], print.dir[1], print.side);
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
        for s in &shards {
            eprintln!("pane {} cell {} at {:.0} {:.1} {:.0}, falls {:.2} hits {:.2}, {:.0} long", s.i, s.cell, s.foot[0], s.foot[1], s.foot[2], s.tr, s.hit, s.size());
        }
        if let Ok(path) = std::env::var("SB_VOX") {
            // (the hand's crater goes in after the panes' blocks: its columns as it leaves them)
            let lake = std::env::var("SB_LAND").is_ok_and(|v| v == "1");
            let land = super::super::sb_hand::land_of(&print, 65, hills, lake);
            let hand = super::super::sb_hand::voxels(&print, 65, &land);
            let col = |l: &str| {
                let mut w = l.split(' ');
                let x = w.next().unwrap_or("").to_string();
                let _ = w.next();
                (x, w.next().unwrap_or("").to_string())
            };
            let mine: std::collections::HashSet<(String, String)> = hand.lines().map(col).collect();
            let mut text = String::new();
            for s in &shards {
                for l in super::super::sb_lodge::voxels(s, 65, seed).lines() {
                    if !mine.contains(&col(l)) {
                        text.push_str(l);
                        text.push('\n');
                    }
                }
            }
            text.push_str(&hand);
            std::fs::write(path, text).unwrap();
        }
    }
}
#[cfg(test)]
mod survey {
    use super::*;
    /// `cargo test --release sb_mesh_survey -- --ignored --nocapture`: what the pattern makes for a few seeds.
    #[test]
    #[ignore]
    fn sb_mesh_survey() {
        for seed in [37u32, 5, 1234, 77, 9] {
            let me = [0.0, 5.0, 300.0];
            let m = Mesh::new(seed, me);
            let cells: usize = (0..SB_K).map(|k| m.cells(k).len()).sum();
            let forks = m.sec.iter().filter(|s| s.fork != 0).count();
            let sh = sb_shards(&m, seed, me);
            let fr = sb_fragments(&m, seed);
            let desc: Vec<String> = sh.iter().map(|s| {
                let c = s.sky;
                format!("{}c r{:.0} len{:.0}", s.poly.len(), c[0].hypot(c[1]), s.size())
            }).collect();
            eprintln!("seed {seed}: {cells} cells, {forks} forks, {} fragments, panes: {}", fr.len(), desc.join(", "));
            for s in &sh {
                eprintln!("  sky {:.0} {:.0}  foot {:.0} {:.0} {:.0}  tr {:.2}", s.sky[0], s.sky[1], s.foot[0], s.foot[1], s.foot[2], s.tr);
            }
        }
    }
}
