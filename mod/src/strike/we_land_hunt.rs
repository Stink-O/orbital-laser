//! The World Eater's hunt: where the worm breaks out next and where it dives, from where the player
//! is. Pure: no world in here (strike/worldeater.rs asks the world which candidates are on loaded land).
//!
//! Path contract v2: every arch has its own two holes, a breach A_i and a dive D_i; between a dive and the next breach
//! the head runs underground, its mound crossing the land (WE_RUN_MIN..=WE_RUN_MAX level). So the hunt picks a PAIR: the
//! next breach A (on the ring round the last dive, turning believably from the way it dived) and the dive D beyond it.
//!
//! A hunt is two or three low hops (the seed picks how many), then the big arch with the bellow; one more small arch if
//! it swallowed the player on its last bite (to surface and spit them out). A hop breaks out close to the player
//! (`hop_gap`) and dives where the next can come back at them; the last hop leaves them some 250-650 off, ahead; the
//! big arch breaks out a span off and comes down on them (leading them a little). The run between varies: a quick dash
//! of a couple of hundred blocks, or a long stalk (`run_want`). Every hole keeps KNOT_GAP from every hole before; no
//! arch passes through one of its own still standing (`clear_of_itself`).
use super::we_path::{WE_ARCS_MAX, WE_BREACH, WE_LEN, WE_R, WE_RUN_DEPTH, WE_RUN_MAX, WE_RUN_MIN, WE_V_HOLD, WeKnot, WePath, we_arc_table};

/// The longest a hunting strike runs (lasers.rs's World Eater `length`), and the latest an arch may go in (its tail is
/// some 12 s behind it, then its tunnel caves in): a spit arch a little later.
pub(super) const WE_HUNT_LEN: f64 = 90.0;
pub(super) const LAST_T_IN: f64 = 52.0;
pub(super) const LAST_T_IN_SPIT: f64 = 58.0;
/// The most its run turns from the way it dived (degrees), and the most its arch turns from its run's way.
pub(super) const RUN_TURN: f64 = 120.0;
pub(super) const TURN_MAX: f64 = 80.0;
/// The first arch's from the wormsign's way (which runs across the player's view: 90 points it at them).
pub(super) const TURN_FIRST: f64 = 100.0;
/// A new hole keeps this far (level) from every hole before it.
pub(super) const KNOT_GAP: f64 = 110.0;
/// Two bodies this far apart (centre lines) pass clear of each other.
pub(super) const CLEAR: f64 = 2.0 * WE_R + 8.0;
/// A spit arch's hold round its top (seconds) and its speed there.
pub(super) const SPIT_HOLD: f64 = 4.4;
pub(super) const SPIT_HV: f64 = 8.0;
/// The head's mean speed along a run carrying a swallowed player (the carry closes on it).
pub(super) const RUN_V_CAUGHT: f64 = 85.0;
/// A run with a swallowed player in it is no longer than this (the carry follows the head at its own pace: 3 to 6 s).
pub(super) const RUN_CAUGHT: f64 = 320.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Kind {
    Hop,
    Big,
    Spit,
}
impl Kind {
    /// Its spans (least, most).
    pub fn span(self) -> (f64, f64) {
        match self {
            Kind::Hop => (130.0, 230.0),
            Kind::Big => (170.0, 320.0),
            // (wide: the player let go from its mouth at its top lands between its holes, clear of both)
            Kind::Spit => (200.0, 230.0),
        }
    }
    /// Its speeds out and in (blocks a second).
    pub fn speeds(self) -> (f64, f64) {
        match self {
            Kind::Hop => (125.0, 132.0),
            Kind::Big => (140.0, 153.0),
            // (out slowly: the swallowed player carried up its throat closes on the head as it rises)
            Kind::Spit => (70.0, 110.0),
        }
    }
    pub fn apex(self, span: f64, r: f64) -> f64 {
        match self {
            Kind::Hop => (span * (0.42 + 0.25 * r)).clamp(60.0, 150.0),
            Kind::Big => 230.0 + 40.0 * r,
            Kind::Spit => 60.0,
        }
    }
}

/// An arch's times from its `t_out`: (t_in, hold).
pub(super) fn arch_times(len: f64, kind: Kind, t_out: f64, v_out: f64) -> (f64, Option<(f64, f64, f64, f64)>) {
    let (_, v_in) = kind.speeds();
    if kind == Kind::Big {
        // (as the scripted show: fast out, held two seconds round its top, faster in)
        let half = 0.5 * len;
        let hv = WE_V_HOLD;
        let h0 = t_out + (half - hv) / (0.5 * (v_out + hv) * 1.13);
        let h1 = h0 + 2.0;
        return (h1 + (half - hv) / (0.5 * (hv + v_in) * 0.81), Some((h0, h1, half, hv)));
    }
    if kind == Kind::Spit {
        // (held SPIT_HOLD round its top, its jaws open, while the player is carried out of its mouth; then in)
        let half = 0.5 * len;
        let hv = SPIT_HV;
        let h0 = t_out + (half - hv) / (0.5 * (v_out + hv) * 1.05);
        let h1 = h0 + SPIT_HOLD;
        return (h1 + (half - hv) / (0.5 * (hv + v_in) * 0.81), Some((h0, h1, half, hv)));
    }
    // (slowing a little over its top)
    (t_out + len / (0.82 * 0.5 * (v_out + v_in)), None)
}

/// How far from the player a hop breaks out: close (130 to 170), but past KNOT_GAP, so the big arch can still come
/// down on them.
pub(super) fn hop_gap(r: f64) -> f64 {
    130.0 + 40.0 * r
}
/// The run before an arch: the length the seed would like (a quick dash or a long stalk) and the head's mean speed.
pub(super) fn run_want(r: f64) -> (f64, f64) {
    if r < 0.4 { (180.0 + 80.0 * r, 170.0 + 40.0 * r) } else { (300.0 + 280.0 * (r - 0.4), 80.0 + 50.0 * r) }
}

/// A candidate: the next breach A and the dive D beyond it (from the origin; heights not known yet), how it scores.
#[derive(Clone, Copy, Debug)]
pub(super) struct Pick {
    pub a: [f64; 3],
    pub d: [f64; 3],
    pub score: f64,
}

fn rot(d: [f64; 2], deg: f64) -> [f64; 2] {
    let (s, c) = deg.to_radians().sin_cos();
    [d[0] * c - d[1] * s, d[0] * s + d[1] * c]
}
fn dist2(a: [f64; 2], b: [f64; 2]) -> f64 {
    let (x, z) = (a[0] - b[0], a[1] - b[1]);
    (x * x + z * z).sqrt()
}

/// The candidates for the next arch, best first: `kind`, aimed at the player's place `aim` (from the origin, level,
/// leading them); `next` the kind of the arch after it, if any (where its dive must leave the player); `run_len` the
/// run the seed would like; `caught` a swallowed player rides the run (kept short). For the first arch A is the
/// origin and only D is picked (turning from the wormsign's way).
pub(super) fn picks(path: &WePath, aim: [f64; 2], kind: Kind, next: Option<Kind>, run_len: f64, caught: bool, r: f64) -> Vec<Pick> {
    let holes: Vec<[f64; 2]> = path.arches.iter().flat_map(|a| [[a.from[0], a.from[2]], [a.to[0], a.to[2]]]).collect();
    let clear = |p: [f64; 2]| holes.iter().all(|h| (h[0] - p[0]) * (h[0] - p[0]) + (h[1] - p[1]) * (h[1] - p[1]) >= KNOT_GAP * KNOT_GAP);
    // (the breaches: the first at the origin heading on the wormsign's way, else on the ring round the last dive)
    let (aa, first) = match path.arches.last() {
        None => (vec![([0.0, 0.0], path.sign_dir, 0.0)], true),
        Some(l) => {
            let (dx, dz) = (l.to[0] - l.from[0], l.to[2] - l.from[2]);
            let w = (dx * dx + dz * dz).sqrt().max(1e-6);
            let came = [dx / w, dz / w];
            let hi = if caught { RUN_CAUGHT } else { WE_RUN_MAX };
            let mut v = Vec::new();
            for k in -8..=8 {
                let off = f64::from(k) * 15.0;
                let d = rot(came, off);
                // (a block in from the run's shortest: a run of exactly WE_RUN_MIN comes out a hair short once rounded,
                // and `next_window` refuses it)
                let mut len = WE_RUN_MIN + 1.0;
                while len <= hi + 1e-9 {
                    let a = [l.to[0] + d[0] * len, l.to[2] + d[1] * len];
                    if clear(a) {
                        v.push((a, d, 0.1 * off.abs() + 0.25 * (len - run_len).abs()));
                    }
                    len += 40.0;
                }
            }
            // (the big arch: also breaches a span off them chosen so its dive comes straight down on them: on circles
            // round them, wherever the run from the last dive can reach and the lunge can turn to them)
            if kind == Kind::Big {
                let (lo, hi_span) = kind.span();
                let mut span = lo + 10.0;
                while span <= hi_span {
                    for k in 0..24 {
                        let (s, c) = (f64::from(k) * 15.0).to_radians().sin_cos();
                        let a = [aim[0] + c * span, aim[1] + s * span];
                        let (rx, rz) = (a[0] - l.to[0], a[1] - l.to[2]);
                        let len = (rx * rx + rz * rz).sqrt();
                        if !(WE_RUN_MIN + 1.0..=hi - 1.0).contains(&len) || !clear(a) {
                            continue;
                        }
                        let d = [rx / len, rz / len];
                        let off = (d[0] * came[0] + d[1] * came[1]).clamp(-1.0, 1.0).acos().to_degrees();
                        let lunge = [(aim[0] - a[0]) / span, (aim[1] - a[1]) / span];
                        if off > RUN_TURN || lunge[0] * d[0] + lunge[1] * d[1] < TURN_FIRST.to_radians().cos() {
                            continue;
                        }
                        v.push((a, d, 0.1 * off + 0.25 * (len - run_len).abs()));
                    }
                    span += 50.0;
                }
            }
            (v, false)
        }
    };
    let turn = if first { TURN_FIRST } else { TURN_MAX };
    let steps = (turn / 10.0).floor() as i32;
    let turns: Vec<(f64, f64, f64)> = (-steps..=steps)
        .map(|k| {
            let (s, c) = (f64::from(k) * 10.0).to_radians().sin_cos();
            (f64::from(k) * 10.0, c, s)
        })
        .collect();
    let (lo, hi) = kind.span();
    let gap = hop_gap(r);
    let mut out = Vec::new();
    // (and the best for each breach: if the best of all lie on land not loaded, others elsewhere)
    let mut each: Vec<Pick> = Vec::with_capacity(aa.len());
    for &(a, rd, run_score) in &aa {
        let first_of_a = out.len();
        let da = dist2(a, aim);
        let a_score = match kind {
            Kind::Hop if !first => (da - gap).abs(),
            // (the big arch breaks out a span off them: its dive comes down on them)
            Kind::Big => (da.clamp(lo, hi) - da).abs(),
            _ => 0.0,
        };
        // (the big arch: also straight at them from this breach, if that is within its spans and its turn)
        let mut ways: Vec<(f64, [f64; 2], Option<f64>)> = turns.iter().map(|&(off, c, s)| (off, [rd[0] * c - rd[1] * s, rd[0] * s + rd[1] * c], None)).collect();
        if kind == Kind::Big && (lo..=hi).contains(&da) {
            let d = [(aim[0] - a[0]) / da, (aim[1] - a[1]) / da];
            let c = d[0] * rd[0] + d[1] * rd[1];
            // (a lunge at them may turn a little further: up to TURN_FIRST)
            if c >= TURN_FIRST.to_radians().cos() {
                ways.push((c.clamp(-1.0, 1.0).acos().to_degrees(), d, Some(da)));
            }
        }
        for &(off, d, exact) in &ways {
            let mut span = exact.unwrap_or(lo);
            while span <= exact.unwrap_or(hi) + 1e-9 {
                let dd = [a[0] + d[0] * span, a[1] + d[1] * span];
                span += 20.0;
                if !clear(dd) {
                    continue;
                }
                let dp = dist2(dd, aim);
                // (the dive: never on them on a hop; on them for the big arch; where the next can come back at them)
                let d_score = match kind {
                    Kind::Big => 4.0 * dp,
                    Kind::Spit => (110.0 - dp).max(0.0) * 2.0,
                    Kind::Hop => {
                        let near = (110.0 - dp).max(0.0) * 3.0;
                        let c2 = if dp > 1.0 { ((aim[0] - dd[0]) * d[0] + (aim[1] - dd[1]) * d[1]) / dp } else { 1.0 };
                        // (the last before the big arch: them well ahead of the way it dives, so the run and the lunge can
                        // turn to them)
                        let behind = if next == Some(Kind::Big) { 300.0 * (0.5 - c2).max(0.0) } else { 60.0 * (-0.5 - c2).max(0.0) };
                        let far = match next {
                            Some(Kind::Big) => (250.0 - dp).max(0.0) + (dp - 650.0).max(0.0),
                            _ => (dp - 600.0).max(0.0),
                        };
                        near + behind + far
                    }
                };
                // (the first arch: towards them)
                let first_score = if first && kind == Kind::Hop { 0.5 * dp } else { 0.0 };
                out.push(Pick { a: [a[0], 0.0, a[1]], d: [dd[0], 0.0, dd[1]], score: run_score + a_score + d_score + first_score + 0.12 * off.abs() });
            }
        }
        if let Some(b) = out[first_of_a..].iter().min_by(|x, y| x.score.total_cmp(&y.score)) {
            each.push(*b);
        }
    }
    // (in the game's WebAssembly a candidate is some 400 instructions: counted as such; only the best 60 sorted)
    crate::meter::spend(450 * out.len() as u64 + 400 * aa.len() as u64);
    if out.len() > 60 {
        out.select_nth_unstable_by(60, |a, b| a.score.total_cmp(&b.score));
        out.truncate(60);
    }
    // (the last hop before the big arch: only a dive from which the big arch can come straight down on them, as far as
    // that can be told now; the others well behind)
    if kind == Kind::Hop && next == Some(Kind::Big) {
        for p in out.iter_mut().chain(each.iter_mut()) {
            if !big_can_reach(p, aim, &clear) {
                p.score += 400.0;
            }
        }
    }
    out.sort_by(|a, b| a.score.total_cmp(&b.score));
    each.sort_by(|a, b| a.score.total_cmp(&b.score));
    out.extend(each);
    out
}

/// Whether a big arch after a hop with pick `p` could breach somewhere it can lunge from straight onto `aim`: a breach a
/// span off them on a circle round them (as `picks` looks for them), its run from `p`'s dive long enough, turned no more
/// than RUN_TURN, and the lunge within TURN_FIRST of the run.
pub(super) fn big_can_reach(p: &Pick, aim: [f64; 2], clear: &dyn Fn([f64; 2]) -> bool) -> bool {
    let (dx, dz) = (p.d[0] - p.a[0], p.d[2] - p.a[2]);
    let w = (dx * dx + dz * dz).sqrt().max(1e-6);
    let came = [dx / w, dz / w];
    let (lo, hi) = Kind::Big.span();
    let (turn, lunge_turn) = (RUN_TURN.to_radians().cos(), TURN_FIRST.to_radians().cos());
    crate::meter::spend(24 * 4 * 60);
    let mut span = lo + 10.0;
    while span <= hi {
        for k in 0..24 {
            let (s, c) = (f64::from(k) * 15.0).to_radians().sin_cos();
            let a = [aim[0] + c * span, aim[1] + s * span];
            let (rx, rz) = (a[0] - p.d[0], a[1] - p.d[2]);
            let len = (rx * rx + rz * rz).sqrt();
            if !(WE_RUN_MIN + 1.0..=WE_RUN_MAX - 1.0).contains(&len) {
                continue;
            }
            let d = [rx / len, rz / len];
            let off_hop = |h: [f64; 2]| (h[0] - a[0]) * (h[0] - a[0]) + (h[1] - a[1]) * (h[1] - a[1]) >= KNOT_GAP * KNOT_GAP;
            if d[0] * came[0] + d[1] * came[1] >= turn
                && ((aim[0] - a[0]) * d[0] + (aim[1] - a[1]) * d[1]) / span >= lunge_turn
                && off_hop([p.a[0], p.a[2]])
                && off_hop([p.d[0], p.d[2]])
                && clear(a)
            {
                return true;
            }
        }
        span += 50.0;
    }
    false
}

/// The path with pick `p` appended as an arch of `kind` (heights as given), its breach as soon after `t_min` as the run
/// allows at about `v_run` (within `next_window`), or none if it cannot be made.
pub(super) fn with_pick(path: &WePath, p: &Pick, kind: Kind, v_out: f64, v_run: f64, t_min: f64, r: f64) -> Option<WePath> {
    if path.arches.len() >= WE_ARCS_MAX {
        return None;
    }
    let t_out = match path.arches.last() {
        None => WE_BREACH,
        Some(last) => {
            let w = path.next_window(p.a, v_out);
            #[cfg(test)]
            if std::env::var("WE_PICKS").is_ok() {
                eprintln!("  window {w:?} from {:?} t_in {}", last.to, last.t_in);
            }
            let (lo, hi) = w?;
            let hd = (p.a[0] - last.to[0]).hypot(p.a[2] - last.to[2]);
            let want = last.t_in + (hd + 2.0 * WE_RUN_DEPTH) / v_run.max(1.0);
            let t = want.max(t_min).clamp(lo, hi);
            if t < t_min - 1e-6 {
                return None;
            }
            t
        }
    };
    let span = (p.d[0] - p.a[0]).hypot(p.d[2] - p.a[2]);
    let apex = kind.apex(span, r);
    let (len, _) = we_arc_table(0.5 * span, apex);
    let (t_in, hold) = arch_times(len, kind, t_out, v_out);
    let (_, v_in) = kind.speeds();
    let mut np = path.clone();
    let r = np.try_push(p.a, p.d, apex, t_out, v_out, t_in, v_in, hold);
    #[cfg(test)]
    if std::env::var("WE_PICKS").is_ok() {
        eprintln!("  t_out {t_out:.2} t_in {t_in:.2} span {span:.0} apex {apex:.0}: {:?}", r.as_ref().err());
    }
    r.ok()?;
    crate::meter::spend(150_000);
    Some(np)
}

/// The head's `s` and speed at `t` from the schedule's knots (as `WePath::head`, without building them again).
pub(super) fn head_at(k: &[WeKnot], t: f64) -> (f64, f64) {
    let Some(first) = k.first() else { return (-1.0e4, 0.0) };
    if t <= first.t {
        return (first.s + first.v * (t - first.t), first.v);
    }
    let i = k.partition_point(|x| x.t < t);
    if i >= k.len() {
        let l = k[k.len() - 1];
        return (l.s + l.v * (t - l.t), l.v);
    }
    let (a, b) = (k[i - 1], k[i]);
    let dt = b.t - a.t;
    let u = ((t - a.t) / dt).clamp(0.0, 1.0);
    let (u2, u3) = (u * u, u * u * u);
    let p = (2.0 * u3 - 3.0 * u2 + 1.0) * a.s + (u3 - 2.0 * u2 + u) * dt * a.v + (-2.0 * u3 + 3.0 * u2) * b.s + (u3 - u2) * dt * b.v;
    let v = (6.0 * u2 - 6.0 * u) / dt * a.s + (3.0 * u2 - 4.0 * u + 1.0) * a.v + (-6.0 * u2 + 6.0 * u) / dt * b.s + (3.0 * u2 - 2.0 * u) * b.v;
    (p, v)
}
/// When the head is at `s` (the schedule's monotone).
pub(super) fn time_at(k: &[WeKnot], s: f64) -> f64 {
    let (mut lo, mut hi) = (-200.0, 400.0);
    for _ in 0..60 {
        let m = 0.5 * (lo + hi);
        if head_at(k, m).0 < s {
            lo = m;
        } else {
            hi = m;
        }
    }
    crate::meter::spend(60 * 400);
    0.5 * (lo + hi)
}

/// Whether the arch just pushed (the path's last) passes clear of every arch of the path still standing while it is up.
pub(super) fn clear_of_itself(p: &WePath) -> bool {
    let n = p.arches.len();
    if n < 2 {
        return true;
    }
    let kn = p.knots();
    let up = |a: &super::we_path::WeArch| (a.t_out, time_at(&kn, a.s1() + WE_LEN));
    let new = &p.arches[n - 1];
    let (new_out, new_in) = up(new);
    let sample = |a: &super::we_path::WeArch| -> Vec<[f64; 3]> { (1..24).map(|k| p.point(a.s0 + a.len * f64::from(k) / 24.0).0).collect() };
    let mine = sample(new);
    for a in &p.arches[..n - 1] {
        let (out, tail_in) = up(a);
        if tail_in < new_out || out > new_in {
            continue;
        }
        crate::meter::spend(23 * 23 * 40 + 46 * 2_000);
        let theirs = sample(a);
        for q in &mine {
            for r in &theirs {
                let d = ((q[0] - r[0]).powi(2) + (q[1] - r[1]).powi(2) + (q[2] - r[2]).powi(2)).sqrt();
                if d < CLEAR {
                    return false;
                }
            }
        }
    }
    true
}

/// The arch the hunt plans as arch `k` (`hops` low hops, then the big one); none past it.
pub(super) fn kind_of(k: usize, hops: usize) -> Option<Kind> {
    match k {
        k if k < hops => Some(Kind::Hop),
        k if k == hops => Some(Kind::Big),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::super::we_path::{we_geo, we_runs};
    use super::*;

    #[test]
    fn a_chain_of_picks_holds_together() {
        let g = we_geo([0.5, 65.0, 0.5], [0.0, 65.0, 300.0], 37);
        let aim = [0.0, 300.0];
        let mut p = WePath::new(g.dir);
        for (k, kind) in [Kind::Hop, Kind::Hop, Kind::Big, Kind::Spit].into_iter().enumerate() {
            let next = [Some(Kind::Hop), Some(Kind::Big), None, None][k];
            let r = 0.1 + 0.27 * k as f64;
            let (len, v) = run_want(r);
            let c = picks(&p, aim, kind, next, len, kind == Kind::Spit, r);
            let t_min = p.arches.last().map_or(0.0, |a| a.t_in);
            p = c.iter().take(30).find_map(|c| with_pick(&p, c, kind, kind.speeds().0, v, t_min, r).filter(clear_of_itself)).unwrap_or_else(|| panic!("arch {k}"));
        }
        p.check(WE_HUNT_LEN).unwrap();
        assert!((p.arches[0].t_out - WE_BREACH).abs() < 1e-9 && p.arches[0].from[0].abs() < 1e-9);
        assert!(p.arches[2].hold.is_some());
        // (the big arch comes down on them)
        assert!((p.arches[2].to[0] - aim[0]).hypot(p.arches[2].to[2] - aim[1]) < 70.0, "{:?}", p.arches[2].to);
        for w in p.arches.windows(2) {
            let run = (w[1].from[0] - w[0].to[0]).hypot(w[1].from[2] - w[0].to[2]);
            assert!((WE_RUN_MIN - 1e-6..=WE_RUN_MAX + 1e-6).contains(&run), "{run}");
        }
        assert!(we_runs(&p)[3].head_in < LAST_T_IN_SPIT);
    }
}
