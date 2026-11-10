// Orbital Laser's post pass for the Sky Breaks (laser 18): as the Payload's, the mod builds it from strike.wgsl up to
// its fs_main (the helpers: noise, project_rel, mh, ign) less other lasers' own, then this file; for its strikes only.
// Validate with tools/check-shader.sh.

// ---- laser 18: the sky breaks
// No beam. A crack snaps across the sky from a point high over the target, more race out and fork, short slanted breaks
// join them (never whole rings), as annealed glass hit at one point; each piece out of true, catching the light its own
// way. The middle falls out in a glittering rain; through the hole a void, something vast in it looking down. Huge
// panes of sky break free one by one, tumble and smash into the land, lying as real blocks (drawn here till the mod
// lays them). Late on the sky heals from its holes' edges. strike/skybreak.rs puts the cracks and panes in the table
// (sb_table, render.set-data), strike/sb_lodge.rs lays the panes' blocks: keep the SB_* and sb_sky in step. Round 4:
// the crack is a hand behind the sky punching through; at the end it slams a fist into the land (`[hand]`, sb_hand.rs).
const SB_H: f32 = 560.0;           // the sky's pane, over the target's ground
const SB_K: i32 = 15;              // primary radial cracks
const SB_FAR: f32 = 7000.0;        // how far the cracks run
const SB_LEAD: f32 = 8.75;         // round 3's timeline starts this much later (the land lifted into the sky first)
const SB_CRACK: f32 = SB_LEAD + 0.25; // the hand punches through: the first crack, every radial across the sky in 0.1 s,
const SB_SPREAD: f32 = SB_CRACK + 0.25; // the rings joining them by here; then the pieces shift out of true
const SB_COLLAPSE: f32 = SB_CRACK + 0.03; // the middle round the fist blown down (its outer ring at the slam, HD_KNOCK)
const SB_SAG: f32 = 1.3;           // a pane sags this long before breaking free
const SB_HEAL: f32 = 40.0;         // the sky heals over from here
const SB_HEALED: f32 = 46.5;       // to here
const SB_LEN: f32 = 49.5;
const SB_NC: u32 = 14u;            // the table (skybreak.rs's SB_*): chords a sector before its fork, each side after
const SB_NS2: u32 = 10u;
const SB_SEC: u32 = 32u;           // each sector,
const SB_SECW: u32 = 76u;
const SB_RAD: u32 = 1172u;         // each radial's start and run, and its sector branch's,
const SB_CELL: u32 = 1232u;        // each cell's pane or fragment,
const SB_CPS: u32 = 64u;
const SB_SH: u32 = 2192u;          // the panes,
const SB_SW: u32 = 40u;
const SB_FR: u32 = 2472u;          // the fragments of the middle,
const SB_FW: u32 = 16u;
const SB_NS: i32 = 7;
const SB_NF: i32 = 40;

fn sb_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
fn sb_u(i: u32) -> u32 {
    if (i >= arrayLength(&mod_data)) {
        return 0u;
    }
    return mod_data[i];
}
// ---- the crack pattern (skybreak.rs's Mesh): primary radials, a fork in most sectors, short chords between
fn sb_sec(k: i32) -> u32 {
    return SB_SEC + u32(((k % SB_K) + SB_K) % SB_K) * SB_SECW;
}
// Radial k's bearing (k = SB_K: the first's, a turn on).
fn sb_bear(k0: i32) -> f32 {
    return sb_w(sb_sec(k0)) + select(0.0, TAU, k0 >= SB_K);
}
struct SbLine {
    o: vec2<f32>,
    d: vec2<f32>,
}
// Sector k's crack i: 0 its radial, 1 the next radial, 2 its branch.
fn sb_line(k: i32, i: i32) -> SbLine {
    let b = sb_sec(k);
    if (i == 0) {
        let a = sb_w(b);
        return SbLine(vec2<f32>(0.0), vec2<f32>(cos(a), sin(a)));
    }
    let a1 = sb_bear(k + 1);
    if (i == 1) {
        return SbLine(vec2<f32>(0.0), vec2<f32>(cos(a1), sin(a1)));
    }
    let ar = select(sb_w(b), a1, sb_w(b + 2u) > 1.5);
    let bb = sb_w(b + 3u);
    return SbLine(vec2<f32>(cos(ar), sin(ar)) * sb_w(b + 4u), vec2<f32>(cos(bb), sin(bb)));
}
// Chord n of part p (0 the whole sector, 1 the fork's near side, 2 its far): its ends' distances along its cracks.
fn sb_chord(k: i32, p: i32, n: i32) -> vec2<f32> {
    let off = select(select(8u + 2u * SB_NC + 2u * SB_NS2, 8u + 2u * SB_NC, p == 1), 8u, p == 0);
    let i = sb_sec(k) + off + 2u * u32(n);
    return vec2<f32>(sb_w(i), sb_w(i + 1u));
}
fn sb_count(k: i32, p: i32) -> i32 {
    return i32(sb_w(sb_sec(k) + select(select(6u, 5u, p == 1), 1u, p == 0)));
}
// The cracks either side of part p of sector k: (left, right).
fn sb_sides(k: i32, p: i32) -> vec2<i32> {
    if (p == 0) {
        return vec2<i32>(0, 1);
    }
    let near_left = sb_w(sb_sec(k) + 2u) < 1.5;
    if (p == 1) {
        return select(vec2<i32>(2, 1), vec2<i32>(0, 2), near_left);
    }
    return select(vec2<i32>(0, 2), vec2<i32>(2, 1), near_left);
}
// When crack i of sector k gets t out along itself, and how far it has run by `tt`.
fn sb_line_t0(k: i32, i: i32) -> vec2<f32> {
    if (i == 2) {
        let r = SB_RAD + 4u * u32(((k % SB_K) + SB_K) % SB_K);
        return vec2<f32>(sb_w(r + 2u), sb_w(r + 3u));
    }
    let kk = ((k + i) % SB_K + SB_K) % SB_K;
    let r = SB_RAD + 4u * u32(kk);
    return vec2<f32>(sb_w(r), sb_w(r + 1u));
}
fn sb_reach(k: i32, i: i32, t: f32) -> f32 {
    let td = sb_line_t0(k, i);
    return td.x + td.y * (1.0 - sqrt(max(1.0 - t / SB_FAR, 0.0)));
}
fn sb_run(k: i32, i: i32, tt: f32) -> f32 {
    let td = sb_line_t0(k, i);
    let u = saturate((tt - td.x) / max(td.y, 0.1));
    return SB_FAR * (1.0 - (1.0 - u) * (1.0 - u));
}
fn sb_cross2(a: vec2<f32>, b: vec2<f32>) -> f32 {
    return a.x * b.y - a.y * b.x;
}
fn sb_beyond(q: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> bool {
    return sb_cross2(b - a, q - a) < 0.0;
}
// The cell q is in: (sector, part 21 + n), or j = -9 for none.
fn sb_cell(q: vec2<f32>) -> vec2<i32> {
    if (length(q) > SB_FAR) {
        return vec2<i32>(0, -9);
    }
    let a = atan2(q.y, q.x);
    var k = 0;
    var best = 1.0e9;
    for (var kk = 0; kk < SB_K; kk = kk + 1) {
        let d = fract((a - sb_w(sb_sec(kk))) / TAU) * TAU;
        if (d < best) {
            best = d;
            k = kk;
        }
    }
    let l0 = sb_line(k, 0);
    let l1 = sb_line(k, 1);
    let nf = sb_count(k, 0);
    var n = 0;
    for (var m = 0; m < 14; m = m + 1) {
        if (m >= nf) {
            break;
        }
        let c = sb_chord(k, 0, m);
        if (!sb_beyond(q, l0.o + l0.d * c.x, l1.o + l1.d * c.y)) {
            break;
        }
        n = n + 1;
    }
    let fork = sb_w(sb_sec(k) + 2u);
    if (n < nf || fork < 0.5) {
        return vec2<i32>(k, n);
    }
    // (past the fork: which side of the branch, then its own chords)
    let br = sb_line(k, 2);
    let ccw = sb_cross2(br.d, q - br.o) > 0.0;
    let p = select(select(1, 2, ccw), select(2, 1, ccw), fork > 1.5);
    let sd = sb_sides(k, p);
    let ll = sb_line(k, sd.x);
    let lr = sb_line(k, sd.y);
    let nc = sb_count(k, p);
    var m2 = 0;
    for (var m = 0; m < 10; m = m + 1) {
        if (m >= nc) {
            break;
        }
        let c = sb_chord(k, p, m);
        if (!sb_beyond(q, ll.o + ll.d * c.x, lr.o + lr.d * c.y)) {
            break;
        }
        m2 = m2 + 1;
    }
    return vec2<i32>(k, p * 21 + m2);
}
fn sb_seg(q: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let e = b - a;
    let s = saturate(dot(q - a, e) / max(dot(e, e), 1e-6));
    return vec2<f32>(length(q - a - e * s), s);
}
fn sb_cell_hash(k: i32, j: i32, salt: u32) -> f32 {
    return mh(u32(k * 64 + j + 1), u32(seed_v()), salt);
}
struct SbCrack {
    d: f32,        // to the nearest crack formed by now, blocks of the pane
    age: f32,      // how long ago that bit of it formed
    tip: f32,      // how far the nearest running tip of a crack is
    w: f32,        // how heavy that crack is (the radials heaviest, then the branches, the chords)
    cp: vec2<f32>, // the nearest point of it
    chip: f32,     // a chip broken out of its edge there, on q's side (how much wider)
    nq: vec2<f32>, // a point just across the line between its ends, in the cell beyond it
    sw: f32,       // 1 where it wanders across that line past q (the cell beyond is q's own)
}
// Piecewise straight noise, -1 to 1: straight runs, a kink at each whole x.
fn sb_kink(x: f32, key: f32) -> f32 {
    let i = floor(x);
    return mix(fh21(vec2<f32>(i, key)), fh21(vec2<f32>(i + 1.0, key)), x - i) * 2.0 - 1.0;
}
struct SbSeg {
    d: f32,
    s: f32,
    cp: vec2<f32>,
    nq: vec2<f32>,
    sw: f32,
    sg: f32,       // which side of it q is on
}
// The distance from q to the crack a to b, wandering off the line in straight runs and kinks as glass breaks: a chord
// (its ends fixed on the cracks it joins) up to 5 blocks, a radial or branch more as it runs out.
fn sb_wseg(q: vec2<f32>, a: vec2<f32>, b: vec2<f32>, chord: bool, key: f32) -> SbSeg {
    let e = b - a;
    let len = max(length(e), 1e-3);
    let ds = sb_seg(q, a, b);
    let p = a + e * ds.y;
    if (ds.y <= 0.0 || ds.y >= 1.0) {
        return SbSeg(ds.x, ds.y, p, q, 0.0, 1.0);
    }
    let along = ds.y * len;
    let amp = select(min(0.008 * along, 5.0), min(0.035 * len, 4.0) * sin(3.14159 * ds.y), chord);
    let wv = amp * (sb_kink(along / 47.0, key) + 0.2 * sb_kink(along / 13.0, key + 17.0));
    let nrm = vec2<f32>(-e.y, e.x) / len;
    let sd = sb_cross2(e, q - a) / len;
    let sg = select(-1.0, 1.0, sd >= 0.0);
    return SbSeg(abs(sd - wv), ds.y, p + nrm * wv, p - nrm * sg * 1.5, select(0.0, 1.0, (sd - wv) * sd < 0.0), select(-1.0, 1.0, sd - wv >= 0.0));
}
// A crack's chips: little flakes broken out of one edge or the other, more near the impact; how much wider there
// (signed: which edge).
fn sb_chips(along: f32, key: f32, r: f32) -> f32 {
    let cell = floor(along / 3.0);
    let h = fh21(vec2<f32>(cell, key * 7.31 + seed_v()));
    let thr = mix(0.86, 0.97, smoothstep(30.0, 900.0, r));
    let f = fract(along / 3.0);
    let side = select(-1.0, 1.0, fract(h * 37.0) < 0.5);
    return select(0.0, (0.3 + 0.9 * (h - thr) / (1.0 - thr)) * (1.0 - abs(f * 2.0 - 1.0)), h > thr) * mix(1.6, 1.0, smoothstep(40.0, 600.0, r)) * side;
}
fn sb_take(c: ptr<function, SbCrack>, g: SbSeg, age: f32, w: f32, chip: f32) {
    let ch = max(chip * g.sg, 0.0);
    if (g.d - ch < (*c).d - (*c).chip) {
        (*c).d = g.d;
        (*c).age = age;
        (*c).w = w;
        (*c).cp = g.cp;
        (*c).chip = ch;
        (*c).nq = g.nq;
        (*c).sw = g.sw;
    }
}
// Crack i of sector k (a radial or the branch, straight out): its formed part.
fn sb_edge_line(q: vec2<f32>, k: i32, i: i32, t: f32, c: ptr<function, SbCrack>) {
    let l = sb_line(k, i);
    let run = sb_run(k, i, t);
    if (run <= 0.0) {
        return;
    }
    let key = select(f32(((k + i) % SB_K + SB_K) % SB_K) * 3.7, f32(k) * 5.3 + 40.0, i == 2);
    let g = sb_wseg(q, l.o, l.o + l.d * SB_FAR, false, key);
    let along = g.s * SB_FAR;
    if (along < run) {
        sb_take(c, g, t - sb_reach(k, i, along), select(1.0, 0.85, i == 2), sb_chips(along, key, length(g.cp)));
    }
    // (its tip, running out)
    if (run < SB_FAR) {
        (*c).tip = min((*c).tip, length(q - (l.o + l.d * run)));
    }
}
// Chord n of part p of sector k: when it forms (once both its cracks have passed), growing from one end.
fn sb_edge_chord(q: vec2<f32>, k: i32, p: i32, n: i32, t: f32, c: ptr<function, SbCrack>) {
    let sd = sb_sides(k, p);
    let ch = sb_chord(k, p, n);
    let key = f32(k * 64 + p * 21 + n);
    // (glass: the rings join the radials almost at once, the near ones first, all inside a quarter of a second)
    let t0 = max(sb_reach(k, sd.x, ch.x), sb_reach(k, sd.y, ch.y)) + 0.004 + (0.025 + 0.11 * smoothstep(30.0, 2500.0, max(ch.x, ch.y))) * sb_cell_hash(k, p * 21 + n, 0x91u);
    if (t < t0) {
        return;
    }
    let ll = sb_line(k, sd.x);
    let lr = sb_line(k, sd.y);
    let flip = sb_cell_hash(k, p * 21 + n, 0x93u) < 0.5;
    let a = select(ll.o + ll.d * ch.x, lr.o + lr.d * ch.y, flip);
    let b = select(lr.o + lr.d * ch.y, ll.o + ll.d * ch.x, flip);
    let len = length(b - a);
    let tg = 0.035 + 0.05 * sb_cell_hash(k, p * 21 + n, 0x94u);
    let grown = len * (t - t0) / tg;
    let g = sb_wseg(q, a, b, true, 50.0 + key * 0.37);
    if (g.s * len < grown) {
        sb_take(c, g, t - t0 - g.s * tg, 0.62, sb_chips(g.s * len, key + 0.5, length(g.cp)));
    }
    if (grown < len) {
        (*c).tip = min((*c).tip, length(q - (a + (b - a) * (grown / len))) * 1.4);
    }
}
// The cracks round q, in its cell (k, part 21 + n).
fn sb_cracks(q: vec2<f32>, cell: vec2<i32>, t: f32) -> SbCrack {
    var c = SbCrack(1.0e9, 0.0, 1.0e9, 1.0, vec2<f32>(0.0), 0.0, q, 0.0);
    let k = cell.x;
    let p = cell.y / 21;
    let n = cell.y % 21;
    let sd = sb_sides(k, p);
    sb_edge_line(q, k, sd.x, t, &c);
    sb_edge_line(q, k, sd.y, t, &c);
    if (n > 0) {
        sb_edge_chord(q, k, p, n - 1, t, &c);
    } else if (p == 2) {
        sb_edge_chord(q, k, 0, sb_count(k, 0) - 1, t, &c);
    }
    if (n < sb_count(k, p)) {
        sb_edge_chord(q, k, p, n, t, &c);
    }
    // (the crushed middle: a dense web of small cracks round the point it broke from, running out)
    let r = length(q);
    if (r < 70.0) {
        let tw = SB_CRACK + 0.004 + r / 1500.0;
        if (t > tw) {
            // (cells in log-polar: finer to the middle, drawn out along the line from it, as crushed glass)
            let g = vec2<f32>(log(max(r, 0.5)) * 3.0, atan2(q.y, q.x) * (44.0 / TAU));
            let gi = floor(g);
            var f1 = 9.0;
            var f2 = 9.0;
            for (var m = 0; m < 9; m = m + 1) {
                let o = vec2<f32>(f32(m % 3 - 1), f32(m / 3 - 1));
                let c = gi + o;
                let cw = vec2<f32>(c.x, c.y - 44.0 * floor(c.y / 44.0));
                let h = vec2<f32>(fh21(cw + vec2<f32>(seed_v(), 3.0)), fh21(cw + vec2<f32>(7.0, seed_v())));
                let dd = length((c + 0.15 + 0.7 * h - g) * vec2<f32>(0.55, 1.0));
                if (dd < f1) {
                    f2 = f1;
                    f1 = dd;
                } else if (dd < f2) {
                    f2 = dd;
                }
            }
            let fade = smoothstep(70.0, 25.0, r);
            let dv = ((f2 - f1) * r * (TAU / 44.0) * 0.5 + 0.2) / max(fade, 0.05);
            if (dv < c.d) {
                c.d = dv;
                c.age = t - tw;
                c.w = 0.4;
                c.cp = q;
                c.chip = 0.0;
                c.nq = q;
                c.sw = 0.0;
            }
        }
    }
    return c;
}

// ---- what the sky on a pane shows: keep in step with sb_lodge.rs's sb_hash, sb_vn, sb_sky
fn sb_hash(i: i32, k: i32, s: u32) -> f32 {
    return f32(pcg((bitcast<u32>(i) * 73856093u) ^ (bitcast<u32>(k) * 19349663u) ^ s)) * (1.0 / 4294967296.0);
}
fn sb_vn(x: f32, z: f32, s: u32) -> f32 {
    let ix = floor(x);
    let iz = floor(z);
    let tx = x - ix;
    let tz = z - iz;
    let sx = tx * tx * (3.0 - 2.0 * tx);
    let sz = tz * tz * (3.0 - 2.0 * tz);
    let i = i32(ix);
    let k = i32(iz);
    let a = sb_hash(i, k, s);
    let b = sb_hash(i + 1, k, s);
    let c = sb_hash(i, k + 1, s);
    let d = sb_hash(i + 1, k + 1, s);
    return a + (b - a) * sx + (c - a) * sz + (a - b - c + d) * sx * sz;
}
// 0 its blue, 1 a paler haze, 2 cloud, at (qx, qz) of the pane.
fn sb_sky(qx: f32, qz: f32) -> i32 {
    let s = u32(seed_v());
    let cx = floor(qx / 6.0);
    let cz = floor(qz / 6.0);
    let n = sb_vn((cx + 0.5) / 6.0, (cz + 0.5) / 6.0, s ^ 0x3c1u) + 0.16 * (sb_hash(i32(cx), i32(cz), s ^ 0x3c2u) - 0.5);
    if (n > 0.62) {
        return 2;
    }
    return select(0, 1, sb_vn(qx / 23.0, qz / 23.0, s ^ 0x3c3u) > 0.66);
}
// A pane's blocks, as the game's textures average (sRGB): its sky (blue ice, packed ice, snow), its ice (packed ice),
// its broken rim (light blue stained glass), its back (obsidian, crying obsidian).
fn sb_block_rgb(m: i32) -> vec3<f32> {
    switch (m) {
        case 0: { return vec3<f32>(116.0, 168.0, 253.0) / 255.0; }
        case 1: { return vec3<f32>(142.0, 180.0, 250.0) / 255.0; }
        case 2: { return vec3<f32>(249.0, 254.0, 254.0) / 255.0; }
        case 3: { return vec3<f32>(142.0, 180.0, 250.0) / 255.0; }
        case 4: { return vec3<f32>(102.0, 153.0, 216.0) / 255.0; }
        case 5: { return vec3<f32>(15.0, 11.0, 25.0) / 255.0; }
        default: { return vec3<f32>(33.0, 10.0, 60.0) / 255.0; }
    }
}

// ---- the panes
fn sb_qrot(q: vec4<f32>, v: vec3<f32>) -> vec3<f32> {
    let t = 2.0 * cross(q.xyz, v);
    return v + q.w * t + cross(q.xyz, t);
}
fn sb_qinv(q: vec4<f32>, v: vec3<f32>) -> vec3<f32> {
    return sb_qrot(vec4<f32>(-q.xyz, q.w), v);
}
fn sb_slerp(a: vec4<f32>, b0: vec4<f32>, u: f32) -> vec4<f32> {
    var b = b0;
    var d = dot(a, b);
    if (d < 0.0) {
        b = -b;
        d = -d;
    }
    if (d > 0.9995) {
        return normalize(mix(a, b, u));
    }
    let th = acos(clamp(d, -1.0, 1.0));
    return (a * sin((1.0 - u) * th) + b * sin(u * th)) / sin(th);
}
// Whether pane i is sagging in place (its last moment in the sky).
fn t_sag(t: f32, i: i32) -> bool {
    let tr = sb_w(SB_SH + u32(i) * SB_SW + 12u);
    return t > tr - SB_SAG && t < tr;
}
fn sb_axis_q(ax: vec3<f32>, ang: f32) -> vec4<f32> {
    return vec4<f32>(ax * sin(ang * 0.5), cos(ang * 0.5));
}
struct SbPose {
    q: vec4<f32>,
    c: vec3<f32>,     // its middle, from the target's ground point
    st: i32,          // 0 still in the sky, 1 sagging or falling, 2 down, 3 gone (its blocks in)
    u: f32,           // how far down
}
fn sb_qmul(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(a.w * b.xyz + b.w * a.xyz + cross(a.xyz, b.xyz), a.w * b.w - dot(a.xyz, b.xyz));
}
// A pane strikes low end first, its far end up (SB_SLAM_A, about its foot), slamming down SB_SLAM later, all of it
// driven in a little and springing back, still from SB_SETTLE (skybreak.rs's: its blocks go in after). `a` seconds
// after it struck: (its far end's lift, radians; how far it is pressed in, blocks).
const SB_SLAM: f32 = 0.34;
const SB_SLAM_A: f32 = 0.13;
const SB_SETTLE: f32 = 0.85;
fn sb_slam(a: f32) -> vec2<f32> {
    if (a < 0.0) {
        return vec2<f32>(SB_SLAM_A, 0.0);
    }
    if (a < SB_SLAM) {
        let x = a / SB_SLAM;
        return vec2<f32>(SB_SLAM_A * (1.0 - x * x), 0.8 * sin(3.14159 * x * 0.5));
    }
    let y = saturate((a - SB_SLAM) / (SB_SETTLE - SB_SLAM));
    return vec2<f32>(0.018 * sin(3.14159 * y) * (1.0 - y), 0.8 * (1.0 - y) * (1.0 - y) * (1.0 + 2.0 * y));
}
fn sb_pose(i: i32, t: f32) -> SbPose {
    let b = SB_SH + u32(i) * SB_SW;
    let tr = sb_w(b + 12u);
    let hit = sb_w(b + 13u);
    let th = sb_w(b + 9u);
    let c0 = vec3<f32>(sb_w(b + 10u), SB_H + 0.5 * th, sb_w(b + 11u));
    let q1 = vec4<f32>(sb_w(b + 16u), sb_w(b + 17u), sb_w(b + 18u), sb_w(b + 19u));
    let c1 = vec3<f32>(sb_w(b + 20u), sb_w(b + 21u), sb_w(b + 22u));
    let gone = sb_w(b + 14u);
    if (t < tr - SB_SAG) {
        return SbPose(vec4<f32>(0.0, 0.0, 0.0, 1.0), c0, 0, 0.0);
    }
    // (where it lies, turned up about its foot as far as its far end is still up)
    let foot = vec3<f32>(sb_w(b + 25u), sb_w(b + 26u), sb_w(b + 27u));
    let v1 = c1 - foot;
    let hg = normalize(vec3<f32>(-v1.z, 0.0, v1.x) + vec3<f32>(1e-4, 0.0, 0.0));
    let sl = sb_slam(t - hit);
    let rq = sb_axis_q(hg, sl.x);
    let qe = sb_qmul(rq, q1);
    let ce = foot + sb_qrot(rq, v1) - vec3<f32>(0.0, sl.y, 0.0);
    if (t >= hit) {
        return SbPose(qe, ce, select(2, 3, gone > 0.0 && t > gone + 0.1), 1.0);
    }
    // (it sags first: drops a little, its outer edge hanging on a moment)
    let lay = vec2<f32>(sb_w(b + 23u), sb_w(b + 24u));
    let hinge = normalize(vec3<f32>(-lay.y, 0.0, lay.x) + vec3<f32>(1e-4, 0.0, 0.0));
    let s = smoothstep(tr - SB_SAG, tr, t);
    let qs = sb_axis_q(hinge, -0.07 * s * s);
    let cs = c0 - vec3<f32>(0.0, 4.0 * s * s, 0.0);
    if (t < tr) {
        return SbPose(qs, cs, 1, 0.0);
    }
    // (then it falls, slow to turn for its weight, rocking a little on the air, gathering speed all the way)
    let u = saturate((t - tr) / max(hit - tr, 0.1));
    var q = sb_slerp(qs, qe, smoothstep(0.0, 1.0, u));
    let wob = 0.05 * sin(6.2832 * 0.4 * (t - tr) + f32(i) * 1.7) * sin(3.14159 * u) + 0.025 * sin(6.2832 * 0.23 * (t - tr) + f32(i)) * sin(3.14159 * u);
    q = sb_qmul(sb_axis_q(normalize(vec3<f32>(lay.x, 0.0, lay.y) + vec3<f32>(1e-4, 0.0, 0.0)), wob), q);
    let c = vec3<f32>(mix(cs.x, ce.x, pow(u, 1.5)), mix(cs.y, ce.y, pow(u, 2.3)), mix(cs.z, ce.z, pow(u, 1.5)));
    return SbPose(q, c, 1, u);
}
// A ray (in the pane's frame) through pane i's prism, grown by `grow`: (in, out, the face it enters by: 0 its sky, 1
// its back, 2 its rim), or in > out for a miss.
fn sb_prism(ro: vec3<f32>, rd: vec3<f32>, i: i32, grow: f32) -> vec3<f32> {
    let b = SB_SH + u32(i) * SB_SW;
    return sb_poly(ro, rd, b, sb_w(b + 9u), grow);
}
// The same for the prism cornered by the words from b (their count at b + 8), `th` thick.
fn sb_poly(ro: vec3<f32>, rd: vec3<f32>, b: u32, th: f32, grow: f32) -> vec3<f32> {
    let h = 0.5 * th + grow;
    var t0 = -1.0e9;
    var t1 = 1.0e9;
    var face = 0.0;
    if (abs(rd.y) < 1e-6) {
        if (abs(ro.y) > h) {
            return vec3<f32>(1.0, -1.0, 0.0);
        }
    } else {
        let a = (-h - ro.y) / rd.y;
        let c = (h - ro.y) / rd.y;
        t0 = min(a, c);
        t1 = max(a, c);
        face = select(1.0, 0.0, rd.y > 0.0);
    }
    let n = i32(sb_w(b + 8u));
    for (var k = 0; k < 4; k = k + 1) {
        if (k >= n) {
            break;
        }
        let k1 = (k + 1) % n;
        let p = vec2<f32>(sb_w(b + u32(2 * k)), sb_w(b + u32(2 * k + 1)));
        let q = vec2<f32>(sb_w(b + u32(2 * k1)), sb_w(b + u32(2 * k1 + 1)));
        let e = q - p;
        let el = max(length(e), 1e-4);
        let al = e.x * (ro.z - p.y) - e.y * (ro.x - p.x) + grow * el;
        let be = e.x * rd.z - e.y * rd.x;
        if (abs(be) < 1e-7) {
            if (al < 0.0) {
                return vec3<f32>(1.0, -1.0, 0.0);
            }
            continue;
        }
        let c = -al / be;
        if (be > 0.0) {
            if (c > t0) {
                t0 = c;
                face = 2.0;
            }
        } else {
            t1 = min(t1, c);
        }
    }
    return vec3<f32>(t0, t1, face);
}
// How far (its own x, z) is in from pane i's nearest edge.
fn sb_inset(l: vec2<f32>, i: i32) -> f32 {
    let b = SB_SH + u32(i) * SB_SW;
    let n = i32(sb_w(b + 8u));
    var d = 1.0e9;
    for (var k = 0; k < 4; k = k + 1) {
        if (k >= n) {
            break;
        }
        let k1 = (k + 1) % n;
        let p = vec2<f32>(sb_w(b + u32(2 * k)), sb_w(b + u32(2 * k + 1)));
        let q = vec2<f32>(sb_w(b + u32(2 * k1)), sb_w(b + u32(2 * k1 + 1)));
        let e = q - p;
        d = min(d, sb_cross2(e, l - p) / max(length(e), 1e-4));
    }
    return d;
}
// When block `cell` of pane i crumbles away, a share of the way through (a pane never laid: sb_open's).
fn sb_crumb(cell: vec3<f32>, i: i32) -> f32 {
    return saturate(0.45 * fh31(cell + vec3<f32>(f32(i) * 31.7, 0.0, 7.0)) + 0.55 * (0.5 + 1.6 * (gnoise3(cell * 0.085 + vec3<f32>(f32(i) * 5.0, 0.0, 0.0)) - 0.5)));
}
// What block pane i is at l in its frame (sb_lodge.rs's pane_block): 0-2 its sky, 3 ice, 4 rim, 5-6 back.
fn sb_block_of(l: vec3<f32>, i: i32, cellw: vec3<f32>) -> i32 {
    let b = SB_SH + u32(i) * SB_SW;
    let th = sb_w(b + 9u);
    let d = l.y + 0.5 * th;
    if (sb_inset(l.xz, i) < 1.0) {
        return 4;
    }
    if (d < 1.15) {
        return sb_sky(l.x + sb_w(b + 10u), l.z + sb_w(b + 11u));
    }
    if (d > th - 1.15) {
        let wc = vec3<i32>(floor(cellw));
        return select(5, 6, sb_hash(wc.x * 7 + wc.y, wc.z, u32(seed_v()) ^ 0x3c5u) < 0.07);
    }
    return 3;
}

// ---- the void behind the sky, and what looks through
// The eye: a vast eye in a head in the dark behind the sky, ray-traced (review/round4-eye/research.md): its ball (the
// white veined, a darker ring round the iris), its cornea a clear bulge over the sunk iris (seen through it, bent), its
// lids a shell of skin with real thickness over the ball (wet margins; draped over the cornea's bulge), smoothed into
// socket, brow, cheek and the nose's side; lit only, dimly, by what comes in through the hole; wet, mirroring the hole
// and the broken glass. Its head stays on the line from where they fired through the hole (filling it for them, as at
// a spyhole); from anywhere else it is seen as it is from there. Once the hand has gone back up it slides in from the
// side, temple first, lids barely parted; they part; its ball searches the land in quick jumps; rolls to the one
// looking, lids wide, pupil snapping tight (SB_LOCK: the strike's beat, its sound in skybreak.rs); follows them, its
// pupil tightening as each pane breaks free; blinks once, slowly; its pupil shrinks to a point and it flares
// (HD_FLARE); and turns away, sliding off the way it came, shutting, clear of the hole before the fist.
const SB_EYE_R: f32 = 78.0;          // its ball's radius (blocks); the rest of it in that radius, in its own frame:
const EY_LID: f32 = 1.1;             // the lids' outside (a shell over the ball, an eye's lid thick)
const EY_CR: f32 = 0.64;             // the cornea's curve (an eye's 7.8 mm on a ball of 12)
const EY_CD: f32 = 0.485;            // its middle, out from the ball's along where it looks (its apex 1.125 out)
const EY_LZ: f32 = 0.851;            // where it meets the white (the limbus), along where it looks: 0.526 across
const EY_IZ: f32 = 0.8;              // the iris's plane, along where it looks (the chamber in front of it ~3 mm deep)
const EY_IR: f32 = 0.53;             // the iris's radius
const EY_N: f32 = 1.336;             // the cornea's and the chamber's refractive index
const EY_FACE: f32 = 2.4;            // how far its face goes out round it before the dark has it
const EY_LIT: f32 = 1.4;             // how much of the light through the hole reaches it
const SB_ARRIVE: f32 = 12.0;       // it slides in from here,
const SB_THERE: f32 = 14.0;        // is there,
const SB_OPEN: f32 = SB_THERE + 1.2; // opens,
const SB_LOCK: f32 = SB_LEAD + 10.4; // finds them,
const SB_BLINK: f32 = SB_LEAD + 21.4; // blinks,
const SB_AWAY: f32 = 35.55;        // turns away (clear of the hole before the fist is thrown down through it: HD_DOWN),
const SB_SHUT: f32 = 35.75;        // and shuts
// How far apart its lids are: 0 shut, 1 open.
fn sb_lids(t: f32) -> f32 {
    let peer = 0.075 * smoothstep(SB_ARRIVE + 0.5, SB_ARRIVE + 1.6, t);
    let slit = 0.05 * smoothstep(SB_OPEN - 0.8, SB_OPEN - 0.1, t);
    let wide = smoothstep(SB_OPEN + 0.15, SB_OPEN + 2.1, t);
    let blink = 1.0 - smoothstep(SB_BLINK, SB_BLINK + 0.24, t) * (1.0 - smoothstep(SB_BLINK + 0.36, SB_BLINK + 0.95, t));
    let shut = 1.0 - smoothstep(SB_SHUT, SB_SHUT + 1.0, t);
    return max(max(peer, slit), wide) * blink * shut;
}
// How wide it stares (its upper lid drawn up off the iris): as it finds them, and as it flares.
fn sb_stare(t: f32) -> f32 {
    let lock = smoothstep(SB_LOCK + 0.3, SB_LOCK + 0.55, t) * (1.0 - smoothstep(SB_LOCK + 1.2, SB_LOCK + 4.5, t));
    let fl = smoothstep(HD_FLARE - 0.8, HD_FLARE - 0.1, t) * (1.0 - smoothstep(SB_AWAY, SB_SHUT, t));
    return max(lock, fl);
}
// How far behind the hole its ball's middle is (blocks, along the line from where they fired): further back as it slides
// in, and sinking away into the dark after it shuts.
fn sb_eye_d(t: f32) -> f32 {
    let rest = SB_EYE_R * 1.2 + 4.0;
    let d = mix(rest + 70.0, rest, smoothstep(SB_ARRIVE, SB_THERE + 0.6, t));
    return mix(d, 1600.0, smoothstep(SB_SHUT + 1.0, SB_SHUT + 5.0, t));
}
// How far off to the side of the hole it is, in 150s of blocks (it comes in from there, overshooting a little, and slides
// back off at the end).
fn sb_eye_off(t: f32) -> f32 {
    let x = saturate((t - SB_ARRIVE) / (SB_THERE - SB_ARRIVE));
    let c = x - 1.0;
    let come = 1.0 + 1.25 * c * c * c + 0.25 * c * c;
    let y = saturate((t - SB_AWAY) / 1.4);
    return 2.3 * (1.0 - come) + 2.5 * y * y * (3.0 - 2.0 * y);
}
struct EyF {
    e: vec3<f32>,      // its ball's middle (from the target's ground point)
    x: vec3<f32>,      // its head's frame: across (to its temple), up, out of its face
    y: vec3<f32>,
    z: vec3<f32>,
    g: vec3<f32>,      // where its ball looks, in that frame
}
// Where its head is (its gaze is sb_eye_gaze's).
fn sb_eye_head(t: f32) -> EyF {
    let s = seed_v();
    let H = vec3<f32>(0.0, SB_H, 0.0);
    // (on the line from where they fired through the hole; its face turned most of the way to them, level to them)
    let me = frame.mod_params[3].xz - anchor_xz();
    let m3 = select(vec3<f32>(0.0, 0.0, 300.0), vec3<f32>(me.x, 0.0, me.y), dot(me, me) > 1.0);
    let w = normalize(H - m3);
    let z0 = normalize(mix(vec3<f32>(0.0, -1.0, 0.0), -w, 0.7));
    let x0 = normalize(cross(normalize(vec3<f32>(m3.x, 0.0, m3.z)), z0));
    // (which of its eyes: its temple to one side or the other; it slides in from the side of its nose, its temple first,
    // turned a little the way it moves)
    let sg = select(-1.0, 1.0, fract(s * 0.137) > 0.5);
    let side = -x0 * sg;
    let off = sb_eye_off(t);
    let e = H + w * sb_eye_d(t) + side * off * 150.0;
    let z = normalize(z0 - side * 0.25 * min(off, 1.5));
    let x1 = normalize(x0 - z * dot(x0, z));
    let y = cross(z, x1);
    let x = x1 * sg;
    return EyF(e, x, y, z, vec3<f32>(0.0, 0.0, 1.0));
}
// Where its ball looks, in its head's frame, for someone looking from ro.
fn sb_eye_gaze(h: EyF, ro: vec3<f32>, t: f32) -> vec3<f32> {
    let s = seed_v();
    let e = h.e;
    // (where it looks: before it finds them, about the land under the hole in quick jumps, eased, a little past and back,
    // holding each a moment)
    let u = max(t - SB_ARRIVE, 0.0) * 1.3;
    let k = floor(u);
    let sm = saturate((fract(u) - 0.3 * fh21(vec2<f32>(k, s + 5.0))) / 0.14);
    let c = sm - 1.0;
    let jm = 1.0 + 1.6 * c * c * c + 0.6 * c * c;
    let p0 = vec2<f32>(fh21(vec2<f32>(k - 1.0, s)), fh21(vec2<f32>(k - 1.0, s + 3.0))) - 0.5;
    let p1 = vec2<f32>(fh21(vec2<f32>(k, s)), fh21(vec2<f32>(k, s + 3.0))) - 0.5;
    let pl = mix(p0, p1, jm) * 320.0;
    let srch = normalize(vec3<f32>(pl.x, 0.0, pl.y) - e);
    // (then rolling to them, a little past and back; then on them, flicking a little now and then)
    let xl = saturate((t - SB_LOCK) / 0.6);
    let cl = xl - 1.0;
    let f = select(1.0 + 1.8 * cl * cl * cl + 0.8 * cl * cl, 0.0, t < SB_LOCK);
    let tt = max(t - SB_LOCK - 0.6, 0.0) / 1.9;
    let kk = floor(tt);
    let jm2 = smoothstep(0.0, 0.05, fract(tt));
    let j0 = vec2<f32>(fh21(vec2<f32>(kk - 1.0, s)), fh21(vec2<f32>(kk - 1.0, s + 3.0)));
    let j1 = vec2<f32>(fh21(vec2<f32>(kk, s)), fh21(vec2<f32>(kk, s + 3.0)));
    let jit = (mix(j0, j1, jm2) - 0.5) * 0.05 * smoothstep(SB_LOCK + 0.6, SB_LOCK + 1.0, t);
    let gv = normalize(mix(srch, normalize(ro - e), f) + (h.x * jit.x + h.y * jit.y) * f);
    var g = vec3<f32>(dot(gv, h.x), dot(gv, h.y), dot(gv, h.z));
    // (as far as a ball turns in its socket, and no further: past that it strains, turned as far as it goes)
    let ang = acos(clamp(g.z, -1.0, 1.0));
    let a2 = 0.62 * tanh(ang / 0.62);
    return vec3<f32>(normalize(g.xy + vec2<f32>(1e-5, 0.0)) * sin(a2), cos(a2));
}
// Gradient noise about 0, periodic in x over n cells (n whole): round the iris and round the ball, with no seam.
fn ey_pn(p: vec2<f32>, n: f32) -> f32 {
    let i = floor(p);
    let f = p - i;
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let i0 = i.x - n * floor(i.x / n);
    let i1 = select(i0 + 1.0, 0.0, i0 + 1.0 >= n);
    let a = dot(grad2(vec2<f32>(i0, i.y)), f);
    let b = dot(grad2(vec2<f32>(i1, i.y)), f - vec2<f32>(1.0, 0.0));
    let c = dot(grad2(vec2<f32>(i0, i.y + 1.0)), f - vec2<f32>(0.0, 1.0));
    let d = dot(grad2(vec2<f32>(i1, i.y + 1.0)), f - vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.9;
}
fn ey_smax(a: f32, b: f32, k: f32) -> f32 {
    let h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(a, b, h) + k * h * (1.0 - h);
}
// Its face round the eye, as a height out of it over (x to its temple, y up), in its radii: low across the lids' width,
// the brow over them and the cheek under them as high as the lids (so the lids lie tucked between), the nose's side,
// the temple falling away.
fn ey_face(p: vec2<f32>) -> f32 {
    let q = vec2<f32>(p.x * 0.85, p.y * select(1.35, 1.55, p.y > 0.0));
    let rr = length(q);
    var z = 0.4 + 0.65 * smoothstep(0.85, 1.7, rr);
    z = z + 0.15 * smoothstep(0.8, 1.4, p.y) * (1.0 - smoothstep(0.7, 1.7, p.x));
    z = z + 0.45 * (1.0 - smoothstep(-1.9, -1.0, p.x)) * (1.0 - smoothstep(-0.3, 1.2, p.y));
    z = z - 0.4 * smoothstep(1.2, 2.4, p.x);
    return z;
}
// Its lids and face, as a height: the lids a shell over the ball (shut over all of it; their opening is ey_fiss's),
// raised a little over the cornea's bulge (`cb` its middle) so they always cover it, smoothed into the socket.
fn ey_h(p: vec2<f32>, cb: vec3<f32>, op: f32) -> f32 {
    let r2 = dot(p, p);
    var lid = sqrt(max(EY_LID * EY_LID - r2, 0.0));
    // (a soft rise moving under them as the ball turns: the cornea's own outline through a shut lid reads as its iris)
    let dc = p - cb.xy * (1.0 / EY_CD);
    lid = lid + 0.075 * exp(-dot(dc, dc) / 0.17);
    // (the fold of the upper lid, an arch over its opening, deep as it is open and smoothed out as it shuts; and a softer
    // one under the lower lid)
    let u = clamp(p.x / 1.05, -1.0, 1.0);
    let yc = 0.58 + 0.2 * (1.0 - u * u) - 0.05 * u;
    let fo = (p.y - yc) / 0.07;
    lid = lid - (0.035 + 0.05 * op) * exp(-fo * fo) * (1.0 - u * u);
    let yl = -0.62 - 0.1 * (1.0 - u * u);
    let fl = (p.y - yl) / 0.1;
    lid = lid - 0.025 * exp(-fl * fl) * (1.0 - u * u);
    return ey_smax(lid, ey_face(p), 0.22);
}
// How far inside the lids' opening a way out from the ball's middle is (its x, y; > 0 inside), and how far under the
// upper lid's margin: `op` how open (sb_lids), `wide` how wide it stares, `gy` how far up it looks (the lids follow it).
fn ey_fiss(p: vec2<f32>, op: f32, wide: f32, gy: f32) -> vec2<f32> {
    let u = clamp(p.x / 0.9, -1.0, 1.0);
    let b = max(1.0 - u * u, 1e-5);
    // (shut, they meet along a line a little under its middle, its outer corner a little higher than its inner; the
    // upper lid's arch highest a little towards the nose, the lower's lowest a little towards the temple)
    let mid = -0.1 + 0.05 * b + 0.05 * u;
    let fo = gy * sqrt(b) * op;
    let up = mid + (0.47 + 0.15 * wide) * pow(b, 0.62) * (1.0 - 0.1 * u) * op + 0.3 * fo;
    let lo = mid - 0.36 * pow(b, 0.85) * (1.0 + 0.08 * u) * sqrt(op) + 0.14 * fo;
    return vec2<f32>(min(p.y - lo, up - p.y), up - p.y);
}
// What its wet surface mirrors along r from pw: through the hole, the world beyond, bright; round it the broken glass,
// from behind, each piece lit its own way by the day through it; the dim of its own brow and lids past that.
fn ey_env(pw: vec3<f32>, r: vec3<f32>, t: f32, world: vec3<f32>) -> vec3<f32> {
    // (up and away from the hole: its own brow and lids, dimly lit)
    let up = world * 0.22;
    if (r.y > -0.01) {
        return up;
    }
    // (where the glass is along r; for a point already past it, where it is: a jump there drew a second pupil)
    let q = pw.xz + r.xz * (min(SB_H - pw.y, 0.0) / r.y);
    let cell = sb_cell(q);
    // (soft: a hard edge reads as a second pupil; round it each broken piece its own shade)
    let o = 0.85 * (1.0 - smoothstep(0.0, 260.0, length(q)));
    let glass = 0.2 + 0.25 * sb_cell_hash(cell.x, cell.y, 0x81u);
    // (and grazing, far out over the glass, it eases into the same dim as up and away: no edge between them)
    let k = (1.0 - smoothstep(-0.3, -0.02, r.y)) * (1.0 - smoothstep(1200.0, 3000.0, length(q)));
    return mix(up, world * mix(glass, 1.0, o), k);
}
// The eye along rd (from ro, the camera from the target's ground point): its colour, and how much of it there is (0
// where the ray passes it by).
fn sb_eye(ro: vec3<f32>, rd: vec3<f32>, t: f32, px: f32, nk: f32) -> vec4<f32> {
    var f = sb_eye_head(t);
    let ocw = (ro - f.e) / SB_EYE_R;
    let o = vec3<f32>(dot(ocw, f.x), dot(ocw, f.y), dot(ocw, f.z));
    let d = vec3<f32>(dot(rd, f.x), dot(rd, f.y), dot(rd, f.z));
    if (d.z > -0.06) {
        return vec4<f32>(0.0);
    }
    // (the slab its face lies in, from over its nose to under its lids' lowest (rays slipped through); none where the
    // ray passes by)
    let t0 = (1.7 - o.z) / d.z;
    let t1 = (0.3 - o.z) / d.z;
    if (length(o.xy + d.xy * (0.5 * (t0 + t1))) > EY_FACE + 0.5 * (t1 - t0) * length(d.xy)) {
        return vec4<f32>(0.0);
    }
    f.g = sb_eye_gaze(f, ro, t);
    let cb = f.g * EY_CD;
    let op = sb_lids(t);
    let wide = sb_stare(t);
    // (its lids and face: marched as a height, then narrowed down)
    var ta = t0;
    var tb = t1;
    var hit = false;
    for (var i = 1; i <= 24; i = i + 1) {
        let tt = mix(t0, t1, f32(i) / 24.0);
        let p = o + d * tt;
        if (p.z < ey_h(p.xy, cb, op)) {
            tb = tt;
            hit = true;
            break;
        }
        ta = tt;
    }
    if (!hit) {
        return vec4<f32>(0.0);
    }
    for (var i = 0; i < 6; i = i + 1) {
        let tm = 0.5 * (ta + tb);
        let p = o + d * tm;
        if (p.z < ey_h(p.xy, cb, op)) {
            tb = tm;
        } else {
            ta = tm;
        }
    }
    var th = tb;
    var p = o + d * th;
    var fs = ey_fiss(p.xy / length(p), op, wide, f.g.y);
    // (in the lids' opening: through to the ball, or, between, the lid's own thickness, its margin)
    var kind = 0;
    var corn = false;
    // (kk: across the margin, 1 at the lid's skin to 0 against the ball)
    var kk = 1.0;
    if (fs.x > 0.0 && dot(p.xy, p.xy) < 1.0) {
        var te = 1.0e9;
        let bq = dot(o, d);
        let disc = bq * bq - (dot(o, o) - 1.0);
        if (disc > 0.0) {
            te = -bq - sqrt(disc);
        }
        let oc2 = o - cb;
        let bq2 = dot(oc2, d);
        let disc2 = bq2 * bq2 - (dot(oc2, oc2) - EY_CR * EY_CR);
        if (disc2 > 0.0) {
            let tc = -bq2 - sqrt(disc2);
            if (tc < te && dot(o + d * tc, f.g) > EY_LZ) {
                te = tc;
                corn = true;
            }
        }
        let pe = o + d * te;
        if (te < 1.0e8 && ey_fiss(pe.xy / length(pe), op, wide, f.g.y).x > 0.0) {
            kind = 2;
            th = te;
        } else {
            var a = th;
            var b = min(te, th + 0.7);
            for (var i = 0; i < 6; i = i + 1) {
                let m = 0.5 * (a + b);
                let pm = o + d * m;
                if (ey_fiss(pm.xy / length(pm), op, wide, f.g.y).x > 0.0) {
                    a = m;
                } else {
                    b = m;
                }
            }
            kind = 1;
            kk = saturate((length(o + d * b) - 1.0) / max(length(p) - 1.0, 1e-3));
            th = b;
            corn = false;
        }
        p = o + d * th;
        fs = ey_fiss(p.xy / length(p), op, wide, f.g.y);
    }
    let aa = max(px * th, 0.0015);
    let s = seed_v();
    let pw = f.e + (f.x * p.x + f.y * p.y + f.z * p.z) * SB_EYE_R;
    // (the light: what comes in through the hole from the world beyond it, falling away from it; and the brightest of
    // that, the sunlit side of the hole, for its wet highlights)
    let hc = vec3<f32>(0.0, SB_H, 0.0);
    let lv = hc - pw;
    let l2 = dot(lv, lv);
    let ld = lv * inverseSqrt(l2);
    let night = mix(0.18, 1.0, nk);
    let world = (srgb_to_linear(frame.sky_color.rgb) * 0.55 + vec3<f32>(0.15, 0.17, 0.14)) * night;
    let lc = world * EY_LIT * 7200.0 / (7200.0 + l2) * saturate(-ld.y * 1.3 + 0.15);
    let sh = vec3<f32>(frame.sun.x, 0.0, frame.sun.z);
    let ls = normalize(hc + sh * (40.0 / max(length(sh), 0.05)) - pw);
    // (its surface's way out, in the world)
    var n = p;
    let e = 0.004;
    if (kind == 0) {
        let h0 = ey_h(p.xy, cb, op);
        n = normalize(vec3<f32>(-(ey_h(p.xy + vec2<f32>(e, 0.0), cb, op) - h0) / e, -(ey_h(p.xy + vec2<f32>(0.0, e), cb, op) - h0) / e, 1.0));
    } else if (kind == 1) {
        let dp = p.xy / length(p);
        let s0 = fs.x;
        let sx = ey_fiss(dp + vec2<f32>(e, 0.0), op, wide, f.g.y).x - s0;
        let sy = ey_fiss(dp + vec2<f32>(0.0, e), op, wide, f.g.y).x - s0;
        // (rounding over into the lid's skin at its outer edge: no crease between)
        n = normalize(mix(normalize(vec3<f32>(normalize(vec2<f32>(sx, sy) + vec2<f32>(1e-6, 0.0)), 0.0) + p * 0.55), p / length(p), smoothstep(0.4, 1.0, kk)));
    } else if (corn) {
        n = (p - cb) / EY_CR;
    }
    let nw = f.x * n.x + f.y * n.y + f.z * n.z;
    let rw = reflect(rd, nw);
    let hs = saturate(dot(rw, ls));
    // (shadowed close under its lids, most under the upper's lashes)
    let lid_ao = mix(0.12, 1.0, smoothstep(0.0, 0.16, fs.x)) * mix(0.4, 1.0, smoothstep(0.0, 0.36, fs.y));
    var col = vec3<f32>(0.0);
    var alb = vec3<f32>(0.0);
    var cover = 1.0;
    // (the ball's own frame, turning with it: its white's veins and its iris's fibres turn as it does)
    let gr = normalize(cross(f.g, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1e-4, 0.0, 0.0));
    let gu = cross(gr, f.g);
    let fl = hd_flare(t);
    // (its upper lashes: dark strands out from the upper lid's margin, of uneven lengths, hanging over the opening's top
    // a little; as they get too fine to see, their shade)
    let lm = max(-fs.x, max(fs.y, 0.0));
    let lx0 = p.x * 46.0 + 0.6 * sin(p.x * 9.0 + s);
    let lh = fh21(vec2<f32>(floor(lx0), s + 11.0));
    let lx = lx0 + (lh - 0.5) * 2.5 * lm / 0.08 + 0.8 * (gnoise2(vec2<f32>(p.x * 13.0, s)) - 0.5);
    let lh2 = fh21(vec2<f32>(floor(lx), s + 17.0));
    let llen = 0.03 + 0.07 * lh2 * lh2;
    let lw = saturate(1.5 - aa * 170.0);
    let ltip = 1.0 - smoothstep(0.3 * llen, llen, lm);
    let strand_x = mix(0.35, (1.0 - smoothstep(0.04, 0.05 + 0.13 * ltip, abs(fract(lx) - 0.5))) * step(0.2, lh2 + 0.25), lw);
    let lmid = 1.0 - smoothstep(0.55, 0.85, abs(p.x / max(length(p), 1e-3)));
    if (kind < 2) {
        // ---- its skin: lids, face, and the lids' margins (kind 1) as the same skin, wet and darker toward the ball
        let m = max(-fs.x, 0.0);
        let ul = 1.0 - smoothstep(0.0, 0.1, fs.y);
        alb = vec3<f32>(0.3, 0.215, 0.205) * (0.7 + 0.6 * gnoise2(p.xy * 6.0 + vec2<f32>(s, 0.0))) * (0.85 + 0.3 * gnoise2(p.xy * 23.0));
        let cw = saturate(1.0 - aa * 140.0);
        // (the finest of it only where it is big enough to see)
        if (cw > 0.0) {
            let crs = smoothstep(0.6, 1.0, sin(m * 95.0 + 6.0 * gnoise2(p.xy * vec2<f32>(4.0, 9.0) + vec2<f32>(s, 1.0)))) * smoothstep(0.035, 0.06, m) * (1.0 - smoothstep(0.08, 0.22, m)) * cw * (0.4 + 0.6 * gnoise2(p.xy * 11.0));
            alb = alb * (1.0 - 0.3 * crs);
        }
        // (across the lid, fine creases along its margin, most as it lies shut over the ball; and faint veins under its
        // thin skin)
        if (aa < 0.003 && m > 0.03 && m < 0.6) {
            let fine = smoothstep(0.55, 1.0, sin(m * 230.0 + 9.0 * gnoise2(p.xy * vec2<f32>(3.0, 12.0) + vec2<f32>(s, 4.0)))) * smoothstep(0.03, 0.08, m) * (1.0 - smoothstep(0.3, 0.6, m)) * saturate(1.0 - aa * 330.0) * (0.35 + 0.65 * (1.0 - op)) * (0.3 + 0.7 * gnoise2(p.xy * 17.0 + vec2<f32>(2.0, s)));
            alb = alb * (1.0 - 0.28 * fine);
        }
        if (aa < 0.016 && m > 0.04 && m < 0.7) {
            let lv = abs(gnoise2(p.xy * 5.5 + vec2<f32>(s, 9.0)) - 0.5 + 0.35 * (gnoise2(p.xy * 13.0 + vec2<f32>(1.0, s)) - 0.5));
            let lvk = (1.0 - smoothstep(0.0, 0.012 + aa * 1.5, lv)) * smoothstep(0.04, 0.12, m) * (1.0 - smoothstep(0.35, 0.7, m)) * saturate(1.0 - aa * 60.0);
            // (darker with the dark that is in its skin, as its hand's are)
            alb = mix(alb, mix(vec3<f32>(0.2, 0.09, 0.14), vec3<f32>(0.03, 0.028, 0.06), min(HD_DM * 1.2, 0.85)), (0.35 + 0.3 * HD_DM) * lvk);
        }
        let wet = 1.0 - smoothstep(0.3, 0.9, kk);
        alb = mix(alb, mix(vec3<f32>(0.22, 0.12, 0.12), vec3<f32>(0.1, 0.06, 0.06), ul), wet);
        let lash = (1.0 - smoothstep(0.0, mix(0.45 * llen, llen, ul), m)) * mix(0.55, 0.95, ul) * strand_x * smoothstep(0.6, 1.0, kk);
        alb = alb * (1.0 - lash);
        let u = clamp(p.x / 1.05, -1.0, 1.0);
        let fo = (p.y - (0.58 + 0.2 * (1.0 - u * u) - 0.05 * u)) / 0.09;
        let fold = 1.0 - (0.35 + 0.35 * op) * exp(-fo * fo) * (1.0 - u * u);
        let ao = (0.45 + 0.55 * smoothstep(0.35, 0.95, p.z)) * (0.5 + 0.5 * smoothstep(0.0, 0.12, m)) * fold * mix(0.3, 1.0, smoothstep(0.0, 0.5, kk));
        var bump = vec3<f32>(0.0);
        if (cw > 0.0) {
            bump = (gnoise2(p.xy * 14.0 + vec2<f32>(3.0, s)) - 0.5) * f.x + (gnoise2(p.xy * 14.0 + vec2<f32>(s, 7.0)) - 0.5) * f.y;
        }
        let bump2 = (gnoise2(p.xy * 4.0 + vec2<f32>(5.0, s)) - 0.5) * f.x + (gnoise2(p.xy * 4.0 + vec2<f32>(s, 2.0)) - 0.5) * f.y;
        let nb = normalize(nw + bump * 0.35 * cw + bump2 * 0.3);
        let hv = normalize(ls - rd);
        // (its margin's rounded edge catching the light here and there; the wet line where it lies on the ball)
        let rn = smoothstep(0.35, 0.75, gnoise2(vec2<f32>(p.x * 20.0, s)));
        let rim = exp(-m * m / max(0.008 * 0.008, aa * aa)) * (0.5 + 0.5 * smoothstep(0.0, 0.1, op)) * rn * smoothstep(0.5, 1.0, kk);
        let wl = exp(-(kk - 0.12) * (kk - 0.12) / 0.006) * (0.6 + 0.4 * rn);
        col = alb * lc * saturate(dot(nb, ld) * 0.75 + 0.25) * ao + lc * (pow(saturate(dot(nb, hv)), 14.0) * 0.012 * ao + rim * 0.3 * pow(hs, 4.0));
        // (and the dark its hand's skin has, HD_DM of it: where its lids turn from the light and in their folds they
        // swallow it; less than the hand's, the eye being in the dark already)
        let edk = saturate(HD_DM * (0.9 * (1.0 - saturate(dot(nb, ld) + 0.05)) + 0.6 * (1.0 - fold) + 0.25 * (1.0 - smoothstep(0.0, 0.12, m))));
        col = mix(col * (1.0 - 0.25 * HD_DM), vec3<f32>(0.008, 0.007, 0.018) * lc, 0.9 * edk) + lc * (pow(hs, 40.0) * 0.15 * wet + wl * (0.04 + 0.5 * pow(hs, 4.0)));
        // (and out past its brow and cheek, the dark has it: the stars show again)
        cover = 1.0 - smoothstep(EY_FACE - 0.8, EY_FACE, length(p.xy * vec2<f32>(0.8, 1.0)));
    } else if (!corn) {
        // ---- the white: veined, greyer into the corners, a darker ring round the iris; wet
        let q = vec3<f32>(dot(p, gr), dot(p, gu), dot(p, f.g));
        let tb2 = acos(clamp(q.z, -1.0, 1.0));
        let pb = atan2(q.y, q.x) / TAU + 0.5;
        let v1 = ey_pn(vec2<f32>(pb * 14.0, tb2 * 3.2 + s), 14.0);
        let v2 = ey_pn(vec2<f32>(pb * 37.0, tb2 * 7.0 + 3.0), 37.0);
        let vw = 0.022 + aa * 1.5;
        let vein = (1.0 - smoothstep(0.0, vw, abs(v1 + 0.3 * v2))) * 0.9 + (1.0 - smoothstep(0.0, vw * 0.7, abs(v2))) * 0.5;
        let vk = vein * smoothstep(0.6, 1.15, tb2) * (0.45 + 0.55 * abs(q.x)) * saturate(1.0 - aa * 25.0);
        alb = mix(vec3<f32>(0.85, 0.8, 0.8), vec3<f32>(0.62, 0.54, 0.48), smoothstep(0.85, 1.45, tb2)) * (0.88 + 0.24 * gnoise2(vec2<f32>(pb * 40.0, tb2 * 10.0)));
        alb = mix(alb, vec3<f32>(0.42, 0.05, 0.06), saturate(vk));
        alb = alb * (1.0 - 0.65 * (1.0 - smoothstep(0.555, 0.68, tb2)));
        let fr = 0.025 + 0.975 * pow(1.0 - saturate(dot(-rd, nw)), 5.0);
        col = alb * lc * saturate(dot(nw, ld) * 0.5 + 0.55) * lid_ao + (ey_env(pw, rw, t, world * 0.35) * fr + world * (pow(hs, 250.0) * 0.6 + pow(hs, 30.0) * 0.02)) * lid_ao;
        // (the tear along the lower lid: a thin wet bright line)
        let tear = exp(-(fs.x - 0.012) * (fs.x - 0.012) / max(0.006 * 0.006, aa * aa)) * step(0.0, fs.y - fs.x - 0.02);
        col = col + world * tear * pow(hs, 4.0) * 0.3;
        col = col * (1.0 - 0.85 * (1.0 - smoothstep(0.0, 0.6 * llen, fs.y)) * strand_x * lmid);
    } else {
        // ---- the cornea: clear, the iris sunk behind it seen through it, bent; the hole and the glass round it mirrored
        // in it, and its wet highlight ----
        let cosv = saturate(dot(-d, n));
        let fr = 0.025 + 0.975 * pow(1.0 - cosv, 5.0);
        let dr = refract(d, n, 1.0 / EY_N);
        let ti = (EY_IZ - dot(p, f.g)) / min(dot(dr, f.g), -1e-3);
        let v = p + dr * ti - f.g * EY_IZ;
        let ri0 = length(v);
        let ph = atan2(dot(v, gu), dot(v, gr)) / TAU + 0.5;
        // (its pupil: wide in the dark, snapping tight as it finds them, easing open; tightening as each pane breaks
        // free; wider as the last land; shrinking to a point before it flares; blown wide as it does)
        var tight = 0.0;
        let np = i32(sb_w(0u));
        for (var i = 0; i < SB_NS; i = i + 1) {
            if (i >= np) {
                break;
            }
            let ai = t - sb_w(SB_SH + u32(i) * SB_SW + 12u) + SB_SAG;
            tight = tight + smoothstep(0.0, 0.35, ai) * exp(-max(ai, 0.0) / 2.6);
        }
        let snap = smoothstep(SB_LOCK + 0.42, SB_LOCK + 0.5, t) * exp(-max(t - SB_LOCK - 0.5, 0.0) / 2.8);
        let pr0 = max(0.27 + 0.012 * sin(t * 0.31) - 0.05 * min(tight, 1.0) - 0.16 * snap + 0.04 * smoothstep(SB_LEAD + 17.0, SB_LEAD + 24.0, t), 0.035);
        let pr = mix(mix(pr0, 0.035, smoothstep(HD_FLARE - 0.7, HD_FLARE - 0.05, t)), 0.15, fl);
        // (the iris: fibres out from the pupil, crypts of dark between, pale ice by the pupil to deep blue at its edge, lit
        // from within; a dark ring at its rim; a thin cold corona round the pupil)
        let iaa = aa * 1.6;
        let lr = log(max(ri0, 1e-3));
        let f1 = ey_pn(vec2<f32>(ph * 100.0 + t * 0.015, lr * 2.4), 100.0);
        // (the finer fibres fading out as they get too fine for a pixel: no sparkle far off)
        let f2 = ey_pn(vec2<f32>(ph * 270.0 - t * 0.02, lr * 5.0 + 3.0), 270.0) * saturate(2.0 - iaa * 280.0);
        let f3 = ey_pn(vec2<f32>(ph * 636.0, lr * 9.0), 636.0) * saturate(2.0 - iaa * 650.0);
        let fib = saturate(0.32 + 0.7 * f1 + 0.45 * f2 + 0.25 * f3);
        let r = ri0 / EY_IR;
        let ri = saturate((ri0 - pr) / (EY_IR - pr));
        let pale = vec3<f32>(0.20, 0.34, 0.62);
        let collar = exp(-(ri - 0.3) * (ri - 0.3) / 0.004);
        let strand = smoothstep(0.2, 0.85, fib);
        var glow = vec3<f32>(0.004, 0.008, 0.024) * (0.5 + 1.5 * fib) + pale * (strand * strand * (0.55 * (1.0 - ri) + 0.1) + collar * 0.18 * strand + 0.22 * exp(-ri / 0.06));
        glow = glow * (1.0 - 0.92 * smoothstep(0.76, 0.97, r));
        let cq = (ri0 - pr * 1.04) / max(pr * 0.05, iaa);
        glow = glow + vec3<f32>(0.6, 0.75, 1.0) * exp(-cq * cq * 0.3) * 0.1;
        // (crypts: dark pits in it between its fibres, round its middle)
        let crypt = smoothstep(0.1, 0.28, ey_pn(vec2<f32>(ph * 34.0, lr * 3.5 + 7.0 + s), 34.0)) * smoothstep(0.25, 0.4, ri) * (1.0 - smoothstep(0.75, 0.9, ri));
        glow = glow * (1.0 - 0.75 * crypt);
        // (lit too, by the light through the hole, focused through the cornea into a crescent on its far side)
        let ll = vec3<f32>(dot(ld, f.x), dot(ld, f.y), dot(ld, f.z));
        let lt = vec2<f32>(dot(ll, gr), dot(ll, gu));
        let vd = vec2<f32>(dot(v, gr), dot(v, gu)) / max(ri0, 1e-4);
        let caus = pow(saturate(-dot(vd, normalize(lt + vec2<f32>(1e-5, 0.0)))), 3.0) * smoothstep(0.45, 0.95, r) * saturate(length(lt) * 1.6);
        let ialb = vec3<f32>(0.12, 0.19, 0.3) * (0.35 + 1.1 * strand) * (1.0 - 0.85 * smoothstep(0.78, 0.98, r));
        var iris = glow * 0.55 + ialb * (1.0 - 0.6 * crypt) * lc * saturate(dot(ll, f.g) * 0.5 + 0.5) * (1.0 + 2.0 * caus);
        if (fl > 0.0) {
            // (its flare: the fibres lit from the pupil out, a white-hot ring at the pupil, the light running out along each
            // strand)
            let blaze = (1.0 - smoothstep(EY_IR * 0.88, EY_IR * 1.02, ri0)) * (0.35 + 1.8 * strand) * (0.5 + 2.2 * exp(-ri / 0.25));
            let ring = exp(-(ri0 - pr) * (ri0 - pr) / max(pr * pr * 0.02, 1e-5));
            iris = iris + (vec3<f32>(0.45, 0.66, 1.0) * blaze * 1.5 + vec3<f32>(0.9, 0.95, 1.0) * ring * 2.5) * fl;
        }
        // (the pupil, a hole into the dark; past the iris's edge, the limbus, dark)
        var inner = mix(vec3<f32>(0.001, 0.0015, 0.003), iris, smoothstep(pr - iaa, pr + iaa, ri0));
        inner = mix(inner, vec3<f32>(0.006, 0.007, 0.01), smoothstep(EY_IR - iaa, EY_IR + iaa, ri0));
        // (and the darker ring round it, where the cornea meets the white)
        let lzr = dot(p, f.g);
        inner = inner * (1.0 - 0.5 * (1.0 - smoothstep(EY_LZ, EY_LZ + 0.06, lzr)));
        col = inner * (1.0 - fr) * lid_ao + (ey_env(pw, rw, t, world * 0.35) * fr + world * (pow(hs, 280.0) * 2.6 + pow(hs, 50.0) * 0.06)) * mix(0.3, 1.0, lid_ao);
        // (as it flares, the light scattered in the cornea itself, a cold haze over all of it)
        col = col + vec3<f32>(0.3, 0.45, 0.8) * fl * 0.12 * smoothstep(pr * 0.9, pr * 1.3, ri0) * (1.0 - smoothstep(EY_IR, EY_IR * 1.15, ri0));
        col = col * (1.0 - 0.85 * (1.0 - smoothstep(0.0, 0.6 * llen, fs.y)) * strand_x * lmid);
    }
    // (its flare's light on its lids and face round it, and a cold wash over all of it)
    if (fl > 0.0) {
        let dl = f.g * (EY_CD + EY_CR) - p;
        let gl = fl * vec3<f32>(0.45, 0.66, 1.0) * 2.5 / (1.0 + dot(dl, dl) * 4.0) * saturate(dot(n, normalize(dl + vec3<f32>(0.0, 0.0, 1e-4))) * 0.7 + 0.3);
        col = col + max(alb, vec3<f32>(0.15)) * gl * select(1.0, 0.0, corn);
        // (and its burst: a glare out from the iris over all of it, blinding for a moment, as it blazes through the hole)
        let ap = normalize(f.e + (f.x * f.g.x + f.y * f.g.y + f.z * f.g.z) * (EY_CD + EY_CR) * SB_EYE_R - ro);
        let ga = acos(clamp(dot(rd, ap), -1.0, 1.0)) * length(f.e - ro) / SB_EYE_R;
        col = col + vec3<f32>(0.5, 0.7, 1.1) * fl * fl * (1.1 * exp(-ga * ga / 0.09) + 0.55 * exp(-ga / 0.6));
    }
    return vec4<f32>(col, cover);
}
// Looking along rd (from ro, the camera from the target's ground point) through a hole: the dark, its stars, the eye.
fn sb_void(ro: vec3<f32>, rd: vec3<f32>, t: f32, px: f32, eye: bool, nk: f32) -> vec3<f32> {
    let seen = smoothstep(SB_ARRIVE, SB_ARRIVE + 0.4, t) * (1.0 - smoothstep(SB_SHUT + 2.0, SB_SHUT + 3.0, t));
    var ec = vec4<f32>(0.0);
    if (eye && seen > 0.0) {
        ec = sb_eye(ro, rd, t, px, nk);
        ec.a = ec.a * seen;
        // (the pane lays the flare's glow in the dark round the eye over all seen through the hole (sb_void's caller);
        // none over the eye, its flare lighting it)
        let fl = hd_flare(t);
        if (fl > 0.0 && rd.y > 0.0) {
            let dq = length(ro.xz + rd.xz * ((SB_H - ro.y) / rd.y));
            ec = vec4<f32>(ec.rgb - vec3<f32>(0.12, 0.17, 0.36) * fl * exp(-dq / 260.0), ec.a);
        }
        if (ec.a > 0.999) {
            return ec.rgb;
        }
    }
    let s = seed_v();
    // (a faint deep haze, violet and teal, barely there)
    let hz = gfbm3(rd * 3.1 + vec3<f32>(s * 0.17, 0.0, 0.0), 2);
    var c = vec3<f32>(0.004, 0.003, 0.009) + vec3<f32>(0.010, 0.006, 0.022) * saturate(hz * 1.4 + 0.4) + vec3<f32>(0.0, 0.010, 0.012) * saturate(-hz * 1.6);
    // (stars: sharp, sparse, a few bright)
    for (var l = 0; l < 2; l = l + 1) {
        let sc = select(260.0, 120.0, l == 1);
        let g = rd * sc;
        let gi = floor(g);
        let h = fh31(gi + vec3<f32>(s, f32(l) * 17.0, 3.0));
        if (h > 0.985 - 0.01 * f32(l)) {
            let o = vec3<f32>(fh31(gi + 1.3), fh31(gi + 2.7), fh31(gi + 5.1));
            let d = length(g - gi - 0.2 - 0.6 * o) / sc;
            let rad = max(px * 0.7, 0.0004);
            let hb = max(h - 0.97, 0.0) / 0.03;
            let b = exp(-d * d / (rad * rad)) * (0.4 + 2.5 * hb * hb * hb);
            c = c + vec3<f32>(0.85, 0.9, 1.0) * b;
        }
    }
    return mix(c, ec.rgb, ec.a);
}

// ---- dust, where each pane lands (and where the hand slams the land)
struct SbImpact {
    ok: bool,
    hit: f32,
    foot: vec3<f32>,
    size: f32,
    hand: bool,
}
// Impact i: pane i's (of `n`), or for i = SB_NS the hand's slam (its fist's face on the land; as a pane of 190).
fn sb_impact(i: i32, n: i32) -> SbImpact {
    if (i == SB_NS) {
        return SbImpact(sb_w(HD + 6u) > 1.0, HD_PRESS, vec3<f32>(sb_w(HD), sb_w(HD + 5u), sb_w(HD + 1u)), 190.0, true);
    }
    if (i >= n) {
        return SbImpact(false, 0.0, vec3<f32>(0.0), 0.0, false);
    }
    let b = SB_SH + u32(i) * SB_SW;
    return SbImpact(true, sb_w(b + 13u), vec3<f32>(sb_w(b + 25u), sb_w(b + 26u), sb_w(b + 27u)), sb_w(b + 28u), false);
}
// The dust where pane i landed (`foot`, `size` long), a seconds after: a wall rolling out over the land, a plume
// boiling up over where it struck, a low pall between; its height at p's place (`h`, the noise tearing its top),
// density at p.
struct SbDustK {
    rf: f32,      // the rolling wall's radius
    w: f32,       // its width
    hw: f32,      // its height
    hp: f32,      // the plume's height
    rp: f32,      // its radius
    fill: f32,    // the pall's height
    fade: f32,
}
fn sb_dust_k(size: f32, a: f32) -> SbDustK {
    let e1 = 1.0 - exp(-a / 1.5);
    let rf = 0.4 * size + (0.35 * size + 58.0) * e1;
    let w = 10.0 + 14.0 * (1.0 - exp(-a / 2.0));
    let hw = (16.0 + 16.0 * (1.0 - exp(-a / 2.5))) * exp(-a / 12.0);
    let hp = (42.0 + 0.6 * size) * (1.0 - exp(-a / 0.8)) + 4.0 * a;
    let rp = 0.42 * size + 18.0 + 5.0 * a;
    let fill = (5.0 + 5.0 * (1.0 - exp(-a / 3.0))) * exp(-a / 7.0);
    let fade = smoothstep(0.0, 0.12, a) * (1.0 - smoothstep(3.5, 12.0, a)) * (1.0 - 0.55 * smoothstep(1.5, 6.0, a));
    return SbDustK(rf, w, hw, hp, rp, fill, fade);
}
fn sb_dust_at(p: vec3<f32>, foot: vec3<f32>, k: SbDustK, a: f32, i: i32, oct: i32) -> f32 {
    let d = p - foot;
    if (d.y < -4.0) {
        return 0.0;
    }
    let o = vec3<f32>(f32(i) * 17.3, 0.0, f32(i) * 5.1);
    // (its front in lobes, never a circle, the dust heaped in clumps along it)
    let ang = atan2(d.z, d.x);
    let lobe = gnoise2(vec2<f32>(ang * 2.2 + f32(i) * 3.1, ang * 0.9 + a * 0.05));
    let r = length(d.xz) / (1.0 + 0.2 * lobe);
    if (r > k.rf + 2.5 * k.w) {
        return 0.0;
    }
    // (its noise: billows rolling slowly, torn at the edges; the light's look through it, `oct` 1, takes less)
    let n = gfbm3(vec3<f32>(d.x * 0.028, d.y * 0.04 - a * 0.14, d.z * 0.028) + o, oct);
    let clump = select(0.0, gnoise3(vec3<f32>(d.x * 0.055, d.y * 0.05, d.z * 0.055) + o * 0.7), oct > 1);
    let wq = (r - k.rf) / k.w;
    let wall = k.hw * exp(-wq * wq) * (0.65 + 0.7 * saturate(clump + 0.4));
    let pu = r / k.rp;
    let plume = k.hp * sqrt(max(1.0 - pu * pu, 0.0)) * (0.8 + 0.4 * clump);
    let fill = k.fill * smoothstep(k.rf + k.w, k.rf - 2.0 * k.w, r) * (0.5 + 0.8 * saturate(clump + 0.5));
    let h = max(max(wall, plume), fill) * (0.62 + 0.85 * n);
    // (the low pall between is thin: in it the land is hazed, not all the sky)
    let thin = select(1.0, 0.35, fill > max(wall, plume));
    let den = saturate((h - d.y) / 4.0) * (0.7 + 0.6 * n) * thin;
    return den * 0.1 * k.fade;
}
// The dust along the ray from ro (from the target's ground point) to `far`: premultiplied colour, transmittance.
fn sb_dust(ro: vec3<f32>, rd: vec3<f32>, far: f32, t: f32, px: vec2<f32>, sunc: vec3<f32>, amb: vec3<f32>, L: vec3<f32>) -> vec4<f32> {
    var acc = vec3<f32>(0.0);
    var tr = 1.0;
    let n = i32(sb_w(0u));
    let jit = ign(px);
    // (one budget of steps for all, however many panes' dust the ray crosses)
    var left = 88;
    for (var i = 0; i <= SB_NS; i = i + 1) {
        if (left <= 0 || tr < 0.02) {
            break;
        }
        let im = sb_impact(i, n);
        let a = t - im.hit;
        if (!im.ok || a < 0.0 || a > 12.0) {
            continue;
        }
        // (the hand's slam has its own: hd_dust)
        if (im.hand) {
            continue;
        }
        let foot = im.foot;
        let k = sb_dust_k(im.size, a);
        // (its bounds: a box round it)
        let R = k.rf + 3.0 * k.w;
        let top = max(max(k.hw, k.hp), k.fill) * 1.6 + 4.0;
        let lo = foot + vec3<f32>(-R, -4.0, -R);
        let hi = foot + vec3<f32>(R, top, R);
        let inv = 1.0 / select(rd, vec3<f32>(1e-6), abs(rd) < vec3<f32>(1e-6));
        let ta = (lo - ro) * inv;
        let tb = (hi - ro) * inv;
        let t0 = max(max(max(min(ta.x, tb.x), min(ta.y, tb.y)), min(ta.z, tb.z)), 0.0);
        let t1 = min(min(min(max(ta.x, tb.x), max(ta.y, tb.y)), max(ta.z, tb.z)), far);
        if (t1 <= t0) {
            continue;
        }
        // (thin, fading dust in longer strides)
        let dt0 = clamp((t1 - t0) / 34.0, 1.8, 8.0) * (1.0 + 0.8 * (1.0 - saturate(k.fade * 1.5)));
        var dt = dt0;
        var s = t0 + dt * jit;
        for (var m = 0; m < 64; m = m + 1) {
            if (s > t1 || left <= 0) {
                break;
            }
            left = left - 1;
            let p = ro + rd * s;
            let den = sb_dust_at(p, foot, k, a, i, select(3, 2, s > 240.0));
            // (clear air in long strides, back to the fine one in the dust)
            dt = select(min(dt * 1.5, dt0 * 2.5), dt0, den > 0.002);
            if (den > 0.002) {
                // (sunlit through the dust over it, darker in its folds and low; earth-brown, paler on top, the
                // pulverised sky in it pale and cold at first)
                let sh = exp(-sb_dust_at(p + L * 11.0, foot, k, a, i, 1) * 22.0);
                let hy = saturate((p.y - foot.y) / max(top * 0.6, 1.0));
                let ice = exp(-a / 1.5) * select(0.25, 0.0, im.hand);
                let base = mix(mix(vec3<f32>(0.19, 0.16, 0.13), vec3<f32>(0.36, 0.32, 0.28), hy), vec3<f32>(0.6, 0.68, 0.78), ice);
                let lit = base * (sunc * (0.1 + 0.9 * sh) * 0.8 + amb * (0.3 + 0.45 * hy));
                let ab = exp(-den * dt);
                acc = acc + tr * (1.0 - ab) * lit;
                tr = tr * ab;
                if (tr < 0.02) {
                    break;
                }
            }
            s = s + dt;
        }
    }
    return vec4<f32>(acc, tr);
}
// The glass sprayed up where each pane struck: glints flung out and up, falling back, gone in a few seconds.
fn sb_spray_light(ro: vec3<f32>, rd: vec3<f32>, far: f32, t: f32, px_a: f32, sunc: vec3<f32>, amb: vec3<f32>) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    let n = i32(sb_w(0u));
    for (var i = 0; i < SB_NS; i = i + 1) {
        if (i >= n) {
            break;
        }
        let b = SB_SH + u32(i) * SB_SW;
        let a = t - sb_w(b + 13u);
        if (a < 0.0 || a > 5.0) {
            continue;
        }
        let foot = vec3<f32>(sb_w(b + 25u), sb_w(b + 26u), sb_w(b + 27u));
        // (a dome of it: out fast, slowing, sinking back)
        let R = 8.0 + (0.5 * sb_w(b + 28u) + 50.0) * (1.0 - exp(-a / 0.5));
        let c = foot + vec3<f32>(0.0, 0.25 * R - 9.0 * a * a, 0.0);
        let k = exp(-a / 1.4) * smoothstep(0.0, 0.05, a);
        let oc = ro - c;
        let bq = dot(oc, rd);
        let cq = dot(oc, oc) - R * R;
        let disc = bq * bq - cq;
        if (disc <= 0.0) {
            continue;
        }
        let sq = sqrt(disc);
        let t0 = max(-bq - sq, 0.0);
        let t1 = min(-bq + sq, far);
        if (t1 <= t0) {
            continue;
        }
        let ns = 14;
        let dt = (t1 - t0) / f32(ns);
        for (var m = 0; m < ns; m = m + 1) {
            let pp = ro + rd * (t0 + dt * (f32(m) + 0.5));
            // (in the shell's scale, so each glint rides out with it)
            let u = (pp - c) / R;
            let cell = floor(u * 9.0);
            let h = fh31(cell + vec3<f32>(f32(i) * 7.0, 11.0, seed_v()));
            if (h > 0.9 && pp.y > foot.y - 1.0) {
                let o = vec3<f32>(fh31(cell + 1.7), fh31(cell + 3.1), fh31(cell + 4.9));
                let sp = c + (cell + o) / 9.0 * R;
                let w = sp - ro;
                let along = dot(w, rd);
                let dperp = length(w - rd * along);
                let ps = max(along * px_a * 0.9, 0.12);
                let tw = fh31(cell + vec3<f32>(floor(t * 11.0 + h * 30.0), 2.0, 9.0));
                acc = acc + vec3<f32>(0.85, 0.93, 1.0) * exp(-dperp * dperp / (ps * ps)) * (0.4 + 3.0 * tw * tw * tw) * k * (sunc * 0.6 + amb * 0.6);
            }
        }
    }
    return acc;
}

// How far the pieces have shifted out of true: none till the rings join the radials (SB_SPREAD), then at once, a jolt
// past where they settle and back.
fn sb_shift(t: f32) -> f32 {
    let u = t - SB_SPREAD + 0.07;
    if (u <= 0.0) {
        return 0.0;
    }
    return 1.0 - exp(-u * 9.0) * cos(u * 24.0);
}
// How open cell (k, j) is at t (its pane gone or fragment fallen), and how near to going (it tears first).
fn sb_open(cell: vec2<i32>, t: f32) -> vec2<f32> {
    if (cell.y < 0) {
        return vec2<f32>(0.0);
    }
    let who = sb_u(SB_CELL + u32(cell.x) * SB_CPS + u32(cell.y));
    if (who == 63u || who == 62u) {
        // (the crushed middle: gone as glitter as the fist blows it out (63: as it hits, so the arm comes through a
        // hole, never glass), or as the slam knocks it loose (62))
        let tc = select(HD_KNOCK + 0.1, SB_CRACK, who == 63u);
        let o = smoothstep(tc - 0.03, tc + 0.12, t);
        return vec2<f32>(o, smoothstep(tc - 0.5, tc, t) * (1.0 - o));
    }
    if (who >= 64u) {
        let fb = SB_FR + (who - 64u) * SB_FW;
        // (one the arm drags up goes with the fist)
        let tf = select(sb_w(fb + 11u), SB_CRACK, sb_w(fb + 15u) > 0.5);
        let o = smoothstep(tf - 0.03, tf + 0.12, t);
        return vec2<f32>(o, smoothstep(tf - 0.6, tf, t) * (1.0 - o));
    }
    if (who >= 1u) {
        let tr = sb_w(SB_SH + (who - 1u) * SB_SW + 12u);
        let o = smoothstep(tr - SB_SAG, tr - SB_SAG + 0.15, t);
        return vec2<f32>(o, smoothstep(tr - SB_SAG - 1.4, tr - SB_SAG, t) * (1.0 - o));
    }
    return vec2<f32>(0.0);
}

// ---- the shattered middle: its fragments falling, then bursting into glitter
const SB_FG: f32 = 48.0; // how fast they fall, blocks a second a second
const SB_FTH: f32 = 4.0; // how thick
fn sb_frag_a(f: i32, t: f32) -> f32 {
    return t - sb_w(SB_FR + u32(f) * SB_FW + 11u);
}
// Where a fragment the arm drags up (from c0) is at t: down with the fist, then up with it as it goes back, drawn in
// to the arm; never up past the glass (scraped off at the hole's edge).
fn hd_drag(t: f32, c0: vec3<f32>) -> vec3<f32> {
    let up = hd_py(t) - hd_py(SB_CRACK + 0.1);
    let pull = 0.4 * saturate(up / 120.0);
    let y = min(c0.y + up * 0.92, SB_H - 14.0) - c0.y;
    return vec3<f32>(-c0.x * pull, y, -c0.z * pull);
}
// Fragment f's pose a seconds after it fell, and how whole it is (1 whole, 0 burst). The fist's blown down hard, the
// nearest hardest, spinning; the slam's let go; one the arm dragged falls from where it let go (a < 0: riding it).
fn sb_frag_pose(f: i32, a: f32) -> SbPose {
    let b = SB_FR + u32(f) * SB_FW;
    var c0 = vec3<f32>(sb_w(b + 9u), SB_H + 0.5 * SB_FTH, sb_w(b + 10u));
    let tf = sb_w(b + 11u);
    let dragged = sb_w(b + 15u) > 0.5;
    let punch = tf < 25.0 && !dragged;
    let out = normalize(c0.xz + vec2<f32>(1e-3, 0.0));
    let rc = length(c0.xz);
    let ax = vec3<f32>(cos(sb_w(b + 12u)), 0.0, sin(sb_w(b + 12u)));
    if (dragged) {
        let ride = hd_drag(min(tf + a, tf), c0);
        c0 = c0 + ride;
        if (a < 0.0) {
            let sway = 0.25 * sin((tf + a) * 2.3 + f32(f)) * saturate((tf + a - SB_CRACK) / 0.6);
            return SbPose(sb_axis_q(ax, sway), c0, 1, 1.0);
        }
    }
    let v0 = select(2.0, 70.0 * exp(-rc / 50.0) + 16.0, punch);
    let vo = select(7.0, 26.0 * exp(-rc / 60.0) + 8.0, punch);
    let c = c0 + vec3<f32>(out.x * vo * a, -(0.5 * SB_FG * a * a + v0 * a), out.y * vo * a);
    let q = sb_axis_q(ax, sb_w(b + 13u) * (0.5 * a * a + 0.3 * a) + select(0.0, 2.2 * a, punch));
    let shat = sb_w(b + 14u);
    return SbPose(q, c, 1, 1.0 - smoothstep(shat, shat + 0.3, a));
}
// The glitter a burst fragment leaves: its middle, radius b seconds after it burst, and how bright.
fn sb_glitter(f: i32, bb: f32) -> vec4<f32> {
    let b = SB_FR + u32(f) * SB_FW;
    let shat = sb_w(b + 14u);
    let p = sb_frag_pose(f, shat);
    let v0 = SB_FG * shat;
    let tau = 1.1;
    let drop = 34.0 * bb + (v0 - 34.0) * tau * (1.0 - exp(-bb / tau));
    let r = 6.0 + 26.0 * (1.0 - exp(-bb / 0.7)) + 4.0 * bb;
    return vec4<f32>(p.c - vec3<f32>(0.0, drop, 0.0), r);
}
// The light of the glitter along the ray (ro, rd), out to `far`.
fn sb_glitter_light(ro: vec3<f32>, rd: vec3<f32>, far: f32, t: f32, px_a: f32, sunc: vec3<f32>, amb: vec3<f32>) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    let nf = i32(sb_w(1u));
    for (var f = 0; f < SB_NF; f = f + 1) {
        if (f >= nf) {
            break;
        }
        let b = SB_FR + u32(f) * SB_FW;
        let bb = sb_frag_a(f, t) - sb_w(b + 14u);
        if (bb < 0.0 || bb > 11.0) {
            continue;
        }
        let g = sb_glitter(f, bb);
        let k = (1.0 - smoothstep(4.0, 11.0, bb)) * smoothstep(0.0, 0.08, bb) * (0.6 + 0.8 * exp(-bb / 0.6));
        let oc = ro - g.xyz;
        let bq = dot(oc, rd);
        let cq = dot(oc, oc) - g.w * g.w;
        let disc = bq * bq - cq;
        if (disc <= 0.0) {
            continue;
        }
        let sq = sqrt(disc);
        let t0 = max(-bq - sq, 0.0);
        let t1 = min(-bq + sq, far);
        if (t1 <= t0) {
            continue;
        }
        // (glints: specks of glass catching the sun, twinkling as they turn, drawn out a little falling)
        let n = 14;
        let dt = (t1 - t0) / f32(n);
        for (var m = 0; m < n; m = m + 1) {
            let pp = ro + rd * (t0 + dt * (f32(m) + 0.5));
            let cell = floor((pp - g.xyz) / 2.6);
            let h = fh31(cell + vec3<f32>(f32(f) * 13.0, 5.0, seed_v()));
            if (h > 0.955) {
                let o = vec3<f32>(fh31(cell + 1.7), fh31(cell + 3.1), fh31(cell + 4.9));
                let sp = g.xyz + (cell + o) * 2.6;
                // (as a short streak down the way it falls)
                let w0 = sp - ro;
                let s1 = clamp(dot(w0, rd) - 0.0, 0.0, 1.0e9);
                let st = vec3<f32>(0.0, 0.7, 0.0);
                let wv = sp + st * clamp(dot(ro + rd * s1 - sp, st) / dot(st, st), -1.0, 1.0) - ro;
                let along = dot(wv, rd);
                let dperp = length(wv - rd * along);
                let ps = max(along * px_a * 0.8, 0.1);
                let tw = fh31(cell + vec3<f32>(floor(t * 9.0 + h * 40.0), 2.0, 9.0));
                let r2 = length(sp - g.xyz) / g.w;
                // (none by the eye: a speck of glass a few blocks off is no streak across the picture)
                let near_k = smoothstep(12.0, 40.0, along);
                acc = acc + near_k * vec3<f32>(0.9, 0.95, 1.0) * exp(-dperp * dperp / (ps * ps)) * (0.2 + 2.6 * tw * tw * tw * tw) * k * max(1.0 - r2 * r2, 0.0) * (sunc * 0.5 + amb * 0.4);
            }
        }
    }
    return acc;
}

// The ground shock round where each pane struck (the slam's: hd_shock): a low curtain of dust and grit racing out
// along the land at about the speed of sound, reaching whoever watches with the boom and the jolt; torn along its
// top, thinning as it goes. Its colour, transmittance along (ro, rd) to `far`.
fn sb_shock(ro: vec3<f32>, rd: vec3<f32>, far: f32, t: f32, sunc: vec3<f32>, amb: vec3<f32>) -> vec4<f32> {
    var acc = vec3<f32>(0.0);
    var tr = 1.0;
    let A = dot(rd.xz, rd.xz);
    if (A < 1e-6) {
        return vec4<f32>(acc, tr);
    }
    let n = i32(sb_w(0u));
    for (var i = 0; i < SB_NS; i = i + 1) {
        let im = sb_impact(i, n);
        let a = t - im.hit;
        if (!im.ok || a < 0.0 || a > 2.4) {
            continue;
        }
        let rs = 0.35 * im.size + 343.0 * (a + 0.35 * (1.0 - exp(-a / 0.3)));
        let hr = (8.0 + 0.09 * im.size) * exp(-a / 1.2) + 3.0;
        let k = smoothstep(0.0, 0.06, a) * exp(-a / 0.85);
        let o = ro.xz - im.foot.xz;
        let B = dot(o, rd.xz);
        let disc = B * B - A * (dot(o, o) - rs * rs);
        if (disc <= 0.0) {
            continue;
        }
        let sq = sqrt(disc);
        // (its far side, then near)
        for (var sd = 0; sd < 2; sd = sd + 1) {
            let ts = (-B + select(sq, -sq, sd == 1)) / A;
            if (ts <= 0.0 || ts > far) {
                continue;
            }
            let p = ro + rd * ts;
            let y = p.y - im.foot.y;
            let ang = atan2(p.z - im.foot.z, p.x - im.foot.x);
            let nz = gnoise2(vec2<f32>(ang * rs / 24.0, a * 1.4 + f32(i) * 3.0));
            let top = hr * (0.55 + 0.9 * saturate(nz));
            let prof = smoothstep(-3.0, 0.5, y) * (1.0 - smoothstep(top * 0.35, top, y));
            // (thick seen along it, thin across, fading where the ray grazes it: no hard edge)
            let cs = abs(dot(normalize(rd.xz), normalize(p.xz - im.foot.xz + vec2<f32>(1e-4, 0.0))));
            let slant = smoothstep(0.0, 0.3, cs) / max(cs, 0.4);
            let tear = 0.55 + 0.7 * saturate(gnoise2(vec2<f32>(ang * rs / 8.0, y * 0.35 - a * 3.0)));
            let den = min(prof * k * 0.3 * slant * tear, 0.7);
            let lit = mix(vec3<f32>(0.3, 0.26, 0.22), vec3<f32>(0.62, 0.7, 0.8), 0.4 * exp(-a / 0.5)) * (sunc * 0.6 + amb * 0.85);
            acc = acc + tr * den * lit;
            tr = tr * (1.0 - den);
        }
    }
    return vec4<f32>(acc, tr);
}

// [lift]
// ---- the opening, before the first crack (strike/sb_lift.rs: keep the LF_* in step)
// The land round the target cracks round a ragged rim and tears free: its real blocks taken out (a real hole left) and
// drawn here as an island, block for block. It lurches up, hangs, turning a little, bits falling off its underside, a
// ring of dust rolling out, bits of the rim circling it; climbs fast, brakes under the sky and sinks in, the sky
// closing over it with a point of light. The sky rings like a struck pane (gone by LF_PRESS), a small star crack left.
// Then something presses on it from behind: it bows over the target, whitening with strain, a hand's dark on it as
// through frosted glass, lifting off, curling into a fist, coming down: the first crack (SB_CRACK).
@group(0) @binding(8) var block_sprites: texture_2d_array<f32>;
@group(0) @binding(9) var block_sampler: sampler;
const LF_W: u32 = 12288u;            // its words (sb_lift.rs's SB_LF): header,
const LF_RIM: u32 = LF_W + 32u;      // the rim's radius round it,
const LF_PATH: u32 = LF_W + 64u;     // its way up,
const LF_NP: i32 = 200;
const LF_PW: u32 = 8u;
const LF_DT: f32 = 0.033333333;
const LF_BITS: u32 = LF_PATH + 1600u; // what falls off it,
const LF_NB: i32 = 48;
const LF_BW: u32 = 12u;
const LF_ORB: u32 = LF_BITS + 576u;  // what circles it,
const LF_NO: i32 = 16;
const LF_OW: u32 = 8u;
const LF_PAL: u32 = LF_ORB + 128u;   // its kinds of block,
const LF_KW: u32 = 12u;
const LF_GRID: u32 = LF_PAL + 576u;  // its blocks
const LF_N: i32 = 24;
const LF_NY: i32 = 48;
const LF_RING: f32 = 0.08;           // the ground cracks round its rim
const LF_CUT: f32 = 0.55;            // its blocks taken out of the land
const LF_TEAR: f32 = 0.6;            // it tears free
const LF_TOUCH: f32 = 4.2;           // its top meets the sky
const LF_IN: f32 = 5.15;             // the sky has closed over it
const LF_STAR: f32 = 5.3;            // the star crack where it went in
const LF_RIPPLE: f32 = 5.4;          // the sky rings
const LF_PRESS: f32 = 7.0;           // the hand, laid flat on it, leans on it
const LF_CURL: f32 = 8.35;           // the fist drawn back off it: its last heave
const LF_PUNCH: f32 = 8.75;          // the fist thrown: through at SB_CRACK
const LF_HS: f32 = 3.4;              // the hand's size: as vast as the eye behind it (palm ~100 across)

fn lf_h(i: u32) -> f32 {
    return sb_w(LF_W + i);
}
// The rim's radius at bearing a (sb_lift.rs's lf_rim).
fn lf_rim(a: f32) -> f32 {
    let u = fract(a / TAU) * 32.0;
    let i = u32(floor(u));
    let f = u - floor(u);
    let r0 = sb_w(LF_RIM + i % 32u);
    let r1 = sb_w(LF_RIM + (i + 1u) % 32u);
    return mix(r0, r1, f * f * (3.0 - 2.0 * f));
}
struct LfPose {
    c: vec3<f32>,
    q: vec4<f32>,
}
fn lf_pc(i: i32) -> vec3<f32> {
    let b = LF_PATH + u32(clamp(i, 0, LF_NP - 1)) * LF_PW;
    return vec3<f32>(sb_w(b), sb_w(b + 1u), sb_w(b + 2u));
}
fn lf_pq(i: i32) -> vec4<f32> {
    let b = LF_PATH + u32(clamp(i, 0, LF_NP - 1)) * LF_PW + 3u;
    return vec4<f32>(sb_w(b), sb_w(b + 1u), sb_w(b + 2u), sb_w(b + 3u));
}
// The island's pivot and turn at t (Catmull-Rom through its way's samples), trembling as it tears.
fn lf_pose(t: f32) -> LfPose {
    let x = clamp(t / LF_DT, 0.0, f32(LF_NP) - 1.001);
    let i = i32(floor(x));
    let f = x - floor(x);
    let p0 = lf_pc(i - 1);
    let p1 = lf_pc(i);
    let p2 = lf_pc(i + 1);
    let p3 = lf_pc(i + 2);
    let c = 0.5 * (2.0 * p1 + (p2 - p0) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (3.0 * p1 - p0 - 3.0 * p2 + p3) * f * f * f);
    let q1 = lf_pq(i);
    var q2 = lf_pq(i + 1);
    if (dot(q1, q2) < 0.0) {
        q2 = -q2;
    }
    let tr = 0.07 * smoothstep(LF_CUT, LF_TEAR, t) * (1.0 - smoothstep(LF_TEAR + 0.05, LF_TEAR + 0.4, t));
    let jit = vec3<f32>(sin(t * 91.0), 0.6 * sin(t * 77.0 + 1.3), sin(t * 83.0 + 2.1)) * tr;
    return LfPose(c + jit, normalize(mix(q1, q2, f) + vec4<f32>(0.0, 0.0, 0.0, 1e-6)));
}
fn lf_cell(c: vec3<i32>) -> u32 {
    if (c.x < 0 || c.y < 0 || c.z < 0 || c.x >= LF_N || c.y >= LF_NY || c.z >= LF_N) {
        return 0u;
    }
    let idx = u32((c.y * LF_N + c.z) * LF_N + c.x);
    return (sb_u(LF_GRID + (idx >> 2u)) >> ((idx & 3u) * 8u)) & 255u;
}
// A kind's faces (hurricane.rs's bk_words, as the Hurricane's pass reads them, hu_face).
fn lf_565(c: u32) -> vec3<f32> {
    return srgb_to_linear(vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0));
}
fn lf_tint(c: u32) -> vec3<f32> {
    if (c == 0xFFFFu) {
        return vec3<f32>(1.0);
    }
    return vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0);
}
fn lf_st(m: u32, uv: vec2<f32>) -> vec2<f32> {
    let q = vec3<f32>(vec3<u32>(m, m >> 2u, m >> 4u) & vec3<u32>(3u)) - 1.0;
    let r = vec3<f32>(vec3<u32>(m >> 6u, m >> 8u, m >> 10u) & vec3<u32>(3u)) - 1.0;
    return fract(vec2<f32>(q.x + uv.x * q.z + uv.y * r.y, q.y + uv.x * r.x + uv.y * r.z) * 0.99999 + 0.000005);
}
fn lf_lod(t: f32) -> f32 {
    let px = 2.0 * tan(0.5 * frame.view_params.w) * frame.resolution.w;
    return log2(max(t * px * 16.0, 1.0e-4));
}
// Kind k's face (0 top, 1 bottom, 2 a side; a crossed plant's planes its 0) at uv: its colour (linear), whether it is
// there (a cut-out's clear texel: 0). Far off (a block a few pixels), its texture's average, all there.
fn lf_face(k: u32, face: u32, uv: vec2<f32>, lod: f32) -> vec4<f32> {
    let o = LF_PAL + k * LF_KW;
    let a = sb_u(o);
    let b = sb_u(o + 1u);
    let cross = (b >> 31u) == 1u;
    let avg = lf_565(select(select(a >> 16u, b & 0xFFFFu, face == 1u), a & 0xFFFFu, face == 0u));
    let f0 = sb_u(o + 2u + 3u * face);
    if ((f0 & 1u) == 0u || lod > 3.5) {
        if (cross) {
            // (a plant with no known texture, or far off: a tuft of its colour)
            let w = 0.3 * (1.0 - uv.y) + 0.05;
            return vec4<f32>(avg, select(0.0, 1.0, abs(uv.x - 0.5) < w && uv.y < 0.75));
        }
        return vec4<f32>(avg, 1.0);
    }
    let st = lf_st(sb_u(o + 4u + 3u * face), uv);
    let lv = clamp(lod, 0.0, f32(textureNumLevels(block_sprites) - 1));
    let c0 = textureSampleLevel(block_sprites, block_sampler, st, i32((f0 >> 2u) & 0x1FFFu), lv);
    var rgb = srgb_to_linear(c0.rgb * lf_tint(f0 >> 16u));
    var al = 1.0;
    if ((f0 & 2u) != 0u && c0.a < 0.5) {
        al = 0.0;
    }
    let f1 = sb_u(o + 3u + 3u * face);
    if ((f1 & 1u) != 0u && !cross) {
        let c1 = textureSampleLevel(block_sprites, block_sampler, st, i32((f1 >> 2u) & 0x1FFFu), lv);
        rgb = mix(rgb, srgb_to_linear(c1.rgb * lf_tint(f1 >> 16u)), c1.a);
    }
    return vec4<f32>(rgb, al);
}
struct LfHit {
    t: f32,       // how far along the ray (1e9: none)
    c: vec3<f32>, // its colour, lit
    y: f32,       // its height (from the target's ground point)
}
// Lit as round 3's blocks, its face's world normal `n`: the sun, the sky's light, shaded as the game shades a block's
// faces (tops brightest, undersides darkest).
fn lf_lit(alb: vec3<f32>, n: vec3<f32>, L: vec3<f32>, sunc: vec3<f32>, amb: vec3<f32>) -> vec3<f32> {
    // (as the game lights a block in the open: its texture's colour by day, faces shaded by which way they face, a
    // little warmth on those to the sun; dimmer as the sky is)
    let shade = 0.76 + 0.24 * n.y - 0.06 * abs(n.x);
    let day = clamp(dot(amb, vec3<f32>(0.2126, 0.7152, 0.0722)) * 2.4, 0.06, 1.0);
    return alb * (day * shade + sunc * 0.12 * max(dot(n, L), 0.0));
}
// The island along (ro, rd: from the target's ground point) to `far`, at pose ps; `lo` how far along the ray its blocks
// stop showing (the sky's surface, for one under it), `gone` how much of it has dissolved.
fn lf_island(ro: vec3<f32>, rd: vec3<f32>, far: f32, ps: LfPose, t: f32, gone: f32, L: vec3<f32>, sunc: vec3<f32>, amb: vec3<f32>) -> LfHit {
    var out = LfHit(1.0e9, vec3<f32>(0.0), 0.0);
    let piv = vec3<f32>(lf_h(7u), lf_h(8u), lf_h(9u));
    let g0 = vec3<f32>(lf_h(4u), lf_h(5u), lf_h(6u));
    // (its bounding sphere first)
    let reach = lf_h(17u);
    let oc = ro - ps.c;
    let bq = dot(oc, rd);
    if (bq * bq - (dot(oc, oc) - reach * reach) <= 0.0) {
        return out;
    }
    let o = piv + sb_qinv(ps.q, oc) - g0;
    let d = sb_qinv(ps.q, rd);
    let b0 = vec3<f32>(lf_h(10u), lf_h(11u), lf_h(12u));
    let b1 = vec3<f32>(lf_h(13u), lf_h(14u), lf_h(15u));
    let ad = max(abs(d), vec3<f32>(1.0e-6));
    let inv = select(-1.0 / ad, 1.0 / ad, d >= vec3<f32>(0.0));
    let ta = (b0 - o) * inv;
    let tb = (b1 - o) * inv;
    let tn = min(ta, tb);
    let tf = max(ta, tb);
    let t0 = max(max(tn.x, tn.y), max(tn.z, 0.0));
    let t1 = min(min(tf.x, tf.y), min(tf.z, far));
    if (t0 >= t1) {
        return out;
    }
    var axis = 1;
    if (tn.x >= tn.y && tn.x >= tn.z) {
        axis = 0;
    } else if (tn.z >= tn.y) {
        axis = 2;
    }
    let p0 = o + d * (t0 + 1.0e-4);
    var cell = vec3<i32>(floor(p0));
    let stp = vec3<i32>(select(vec3<i32>(-1), vec3<i32>(1), d >= vec3<f32>(0.0)));
    let tdel = abs(inv);
    var tm = (vec3<f32>(cell) + select(vec3<f32>(0.0), vec3<f32>(1.0), d >= vec3<f32>(0.0)) - o) * inv;
    var tc = t0;
    let lod = lf_lod(t0);
    for (var m = 0; m < 110; m = m + 1) {
        if (tc > t1) {
            break;
        }
        let v = lf_cell(cell);
        let tx = min(min(tm.x, tm.y), tm.z);
        if (v != 0u && (gone <= 0.0 || fh31(vec3<f32>(cell) + vec3<f32>(seed_v(), 3.0, 1.0)) > gone)) {
            let k = v - 1u;
            let cross = (sb_u(LF_PAL + k * LF_KW + 1u) >> 31u) == 1u;
            let cf = vec3<f32>(cell);
            if (cross) {
                // (two planes across the cell, corner to corner: the nearest showing its texture there)
                var best = 1.0e9;
                var bc = vec3<f32>(0.0);
                for (var pl = 0; pl < 2; pl = pl + 1) {
                    let den = select(d.x + d.z, d.x - d.z, pl == 0);
                    if (abs(den) < 1.0e-5) {
                        continue;
                    }
                    let s = select((cf.x - o.x) + (cf.z - o.z) + 1.0, (cf.x - o.x) - (cf.z - o.z), pl == 0) / den;
                    if (s < tc - 1.0e-4 || s > tx + 1.0e-4 || s >= best) {
                        continue;
                    }
                    let lp = o + d * s - cf;
                    if (lp.x < 0.0 || lp.x > 1.0 || lp.y < 0.0 || lp.y > 1.0) {
                        continue;
                    }
                    let fc = lf_face(k, 0u, vec2<f32>(lp.x, lp.y), lod);
                    if (fc.a > 0.5) {
                        best = s;
                        bc = fc.rgb;
                    }
                }
                if (best < 1.0e8) {
                    let nw = normalize(sb_qrot(ps.q, vec3<f32>(0.0, 1.0, 0.0)) * 0.6 - rd * 0.4);
                    out = LfHit(best, lf_lit(bc, nw, L, sunc, amb) * 0.9, ro.y + rd.y * best);
                    return out;
                }
            } else {
                let lp = o + d * tc - cf;
                var nl = vec3<f32>(0.0);
                var uv = vec2<f32>(0.0);
                if (axis == 0) {
                    nl.x = -f32(stp.x);
                    uv = lp.zy;
                } else if (axis == 1) {
                    nl.y = -f32(stp.y);
                    uv = lp.xz;
                } else {
                    nl.z = -f32(stp.z);
                    uv = lp.xy;
                }
                let face = select(2u, select(1u, 0u, nl.y > 0.0), axis == 1);
                let fc = lf_face(k, face, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), lod);
                if (fc.a > 0.5) {
                    let nw = sb_qrot(ps.q, nl);
                    // (a block's edges a little darker: blocks read where their textures are too small to)
                    let e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
                    let edge = select(1.0, 0.8, e < 0.05 && lod > 2.0);
                    out = LfHit(tc, lf_lit(fc.rgb, nw, L, sunc, amb) * edge, ro.y + rd.y * tc);
                    return out;
                }
            }
        }
        if (tm.x < tm.y && tm.x < tm.z) {
            tc = tm.x;
            tm.x = tm.x + tdel.x;
            cell.x = cell.x + stp.x;
            axis = 0;
        } else if (tm.y < tm.z) {
            tc = tm.y;
            tm.y = tm.y + tdel.y;
            cell.y = cell.y + stp.y;
            axis = 1;
        } else {
            tc = tm.z;
            tm.z = tm.z + tdel.z;
            cell.z = cell.z + stp.z;
            axis = 2;
        }
    }
    return out;
}
// A small block of kind k at c (half-size hs, turned by q) along the ray: its hit, nearer than `best`.
fn lf_block(ro: vec3<f32>, rd: vec3<f32>, c: vec3<f32>, hs: f32, q: vec4<f32>, k: u32, best: f32, L: vec3<f32>, sunc: vec3<f32>, amb: vec3<f32>) -> LfHit {
    var out = LfHit(1.0e9, vec3<f32>(0.0), 0.0);
    let oc = ro - c;
    let bq = dot(oc, rd);
    if (bq * bq - (dot(oc, oc) - 3.0 * hs * hs) <= 0.0) {
        return out;
    }
    let o = sb_qinv(q, oc);
    let d = sb_qinv(q, rd);
    let ad = max(abs(d), vec3<f32>(1.0e-6));
    let inv = select(-1.0 / ad, 1.0 / ad, d >= vec3<f32>(0.0));
    let ta = (vec3<f32>(-hs) - o) * inv;
    let tb = (vec3<f32>(hs) - o) * inv;
    let tn = min(ta, tb);
    let tf = max(ta, tb);
    let tnear = max(max(tn.x, tn.y), tn.z);
    let tfar = min(min(tf.x, tf.y), tf.z);
    if (tnear > tfar || tfar < 0.0 || tnear >= best || tnear < 0.5) {
        return out;
    }
    var nl = vec3<f32>(0.0);
    let lp = (o + d * tnear) / (2.0 * hs) + 0.5;
    var uv = lp.xz;
    if (tnear == tn.x) {
        nl.x = -sign(d.x);
        uv = lp.zy;
    } else if (tnear == tn.y) {
        nl.y = -sign(d.y);
    } else {
        nl.z = -sign(d.z);
        uv = lp.xy;
    }
    let face = select(2u, select(1u, 0u, nl.y > 0.0), abs(nl.y) > 0.5);
    let fc = lf_face(k, face, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), lf_lod(tnear / (2.0 * hs)));
    out = LfHit(tnear, lf_lit(fc.rgb, sb_qrot(q, nl), L, sunc, amb), (ro + rd * tnear).y);
    return out;
}
// What falls off it (sb_lift.rs's Bit: the first `real` fall as real blocks, not drawn here) and the bits circling it,
// along the ray, nearer than `best`.
fn lf_bits(ro: vec3<f32>, rd: vec3<f32>, best0: f32, ps: LfPose, t: f32, L: vec3<f32>, sunc: vec3<f32>, amb: vec3<f32>, plane: f32) -> LfHit {
    var out = LfHit(best0, vec3<f32>(0.0), 0.0);
    let nb = i32(lf_h(18u));
    let real = select(0, i32(lf_h(20u)), lf_h(2u) > 0.5);
    for (var i = real; i < LF_NB; i = i + 1) {
        if (i >= nb) {
            break;
        }
        let b = LF_BITS + u32(i) * LF_BW;
        let a = t - sb_w(b);
        if (a < 0.0 || a > 6.0) {
            continue;
        }
        // (flung off lagging its climb, slowing on the air, falling)
        let v0 = vec3<f32>(sb_w(b + 4u), sb_w(b + 5u), sb_w(b + 6u));
        let tau = 0.5;
        let e = 1.0 - exp(-a / tau);
        let vt = -34.0;
        let c = vec3<f32>(sb_w(b + 1u), sb_w(b + 2u), sb_w(b + 3u)) + vec3<f32>(v0.x * tau * e, vt * a + (v0.y - vt) * tau * e, v0.z * tau * e);
        if (c.y < -40.0 || c.y > plane) {
            continue;
        }
        // (shrinking away as it falls far: crumbled to grit)
        let sz = sb_w(b + 8u) * 0.5 * (1.0 - smoothstep(3.5, 5.5, a));
        if (sz < 0.02) {
            continue;
        }
        let ax = sb_w(b + 9u);
        let q = sb_axis_q(normalize(vec3<f32>(cos(ax), 0.5, sin(ax))), a * sb_w(b + 10u));
        let h = lf_block(ro, rd, c, sz, q, u32(sb_w(b + 7u)) - 1u, out.t, L, sunc, amb);
        if (h.t < out.t) {
            out = h;
        }
    }
    // (the rim's bits: lifted after it from where it tore, round it climbing, drawn in with it into the sky)
    let no = i32(lf_h(19u));
    for (var i = 0; i < LF_NO; i = i + 1) {
        if (i >= no) {
            break;
        }
        let b = LF_ORB + u32(i) * LF_OW;
        let a = t - sb_w(b);
        if (a < 0.0) {
            continue;
        }
        let bear = sb_w(b + 1u);
        let r0 = lf_rim(bear) + 0.6;
        let start = vec3<f32>(cos(bear) * r0, sb_w(b + 2u) + 0.4, sin(bear) * r0);
        let w = sb_w(b + 5u);
        let ph = bear + w * a * smoothstep(0.0, 1.5, a);
        let pull = 1.0 - 0.9 * smoothstep(LF_TOUCH - 0.4, LF_IN, t);
        let rr = sb_w(b + 3u) * pull;
        let orbit = ps.c + vec3<f32>(cos(ph) * rr, sb_w(b + 4u) * pull + 0.8 * sin(1.7 * a + bear * 3.0), sin(ph) * rr);
        let u = smoothstep(0.0, 1.6, a);
        let c = mix(start, orbit, u * u * (3.0 - 2.0 * u));
        if (c.y > plane) {
            continue;
        }
        let sz = sb_w(b + 7u) * 0.5;
        let q = sb_axis_q(normalize(vec3<f32>(sin(bear * 5.0), 0.6, cos(bear * 3.0))), a * (1.5 + 2.0 * fract(bear * 7.3)));
        let h = lf_block(ro, rd, c, sz, q, u32(sb_w(b + 6u)) - 1u, out.t, L, sunc, amb);
        if (h.t < out.t) {
            out = h;
        }
    }
    return out;
}
// The island, what falls off and circles it, over what's drawn so far (`near`, `hit`, `pc`: round 3's).
fn lf_draw(ro: vec3<f32>, rd: vec3<f32>, t: f32, scene_len: f32, L: vec3<f32>, sunc: vec3<f32>, amb: vec3<f32>, skyl: vec3<f32>, near: ptr<function, f32>, hit: ptr<function, bool>, pc: ptr<function, vec3<f32>>) {
    if (sb_w(LF_W) < 0.5 || t > LF_IN + 2.0) {
        return;
    }
    let ps = lf_pose(t);
    // (for one under the sky, what has gone up through it is behind it: hidden)
    var far = *near;
    var plane = 1.0e9;
    if (ro.y < SB_H) {
        plane = SB_H;
        if (rd.y > 0.0) {
            far = min(far, (SB_H - ro.y) / rd.y);
        }
    }
    // (the real blocks win while still there, as it is read and till taken out: no fighting)
    let gone = smoothstep(LF_IN, LF_IN + 1.2, t);
    var h = lf_island(ro, rd, far, ps, t, gone, L, sunc, amb);
    let b = lf_bits(ro, rd, min(h.t, far), ps, t, L, sunc, amb, plane);
    if (b.t < h.t) {
        h = b;
    }
    if (h.t < far && h.t < scene_len - 0.05 - 0.004 * h.t) {
        *near = h.t;
        *hit = true;
        // (where it goes into the sky, the sky drawn up round it, a pale skin at the line)
        var c = h.c;
        if (ro.y < SB_H) {
            let m = exp(-max(SB_H - h.y, 0.0) / 1.2) * smoothstep(LF_TOUCH - 0.05, LF_TOUCH + 0.1, t);
            c = mix(c, skyl * 1.15 + vec3<f32>(0.08, 0.1, 0.14), m * 0.85);
        }
        *pc = mix(c, skyl * 0.95, (1.0 - exp(-h.t / 2600.0)) * 0.7);
    }
}

// The ground cracking round the rim before it tears (from LF_RING): a dark line racing round, short cracks out from it;
// gone as the real hole shows. On the scene's land at p (from the target's ground point), `pxw` a pixel there.
fn lf_ground(col: vec3<f32>, p: vec3<f32>, t: f32, pxw: f32) -> vec3<f32> {
    if (t < LF_RING || t > LF_TEAR + 1.0 || sb_w(LF_RIM) < 1.0) {
        return col;
    }
    let r = length(p.xz);
    if (r > 14.0 || abs(p.y) > 4.0) {
        return col;
    }
    let a = atan2(p.z, p.x);
    let R = lf_rim(a);
    // (round from where it starts, both ways, in a third of a second)
    let a0 = TAU * mh(5u, u32(seed_v()), 0x1f0u);
    let da = abs(fract((a - a0) / TAU + 0.5) - 0.5) * TAU;
    let run = (t - LF_RING) / 0.3 * 3.1416;
    let formed = smoothstep(run, run - 0.3, da);
    let jag = 0.22 * (gnoise2(vec2<f32>(a * R * 0.9, 3.0)) - 0.5) + 0.1 * sin(a * R * 2.3);
    let w = 0.12 + 0.3 * smoothstep(LF_RING, LF_CUT, t);
    let dr = abs(r - R - jag);
    var line = (1.0 - smoothstep(w, w + max(pxw, 0.05), dr)) * min(w / max(pxw, 1.0e-3), 1.0) * formed;
    // (short cracks out from the rim)
    let n = 13.0;
    let s = floor((a - a0) / TAU * n + 0.5);
    let ac = a0 + (s + 0.3 * (fh21(vec2<f32>(s, seed_v())) - 0.5)) * TAU / n;
    let ln = 1.0 + 2.5 * fh21(vec2<f32>(s, seed_v() + 7.0));
    let along = r - R;
    let off = abs(sin(a - ac)) * r;
    let grow = smoothstep(LF_RING + 0.15, LF_RING + 0.4, t);
    line = max(line, (1.0 - smoothstep(0.06, 0.06 + max(pxw, 0.05), off)) * step(0.0, along) * step(along, ln * grow) * min(0.06 / max(pxw, 1.0e-3), 1.0));
    let fade = 1.0 - smoothstep(LF_TEAR + 0.1, LF_TEAR + 1.0, t);
    return col * (1.0 - 0.8 * line * fade);
}

// The dust thrown out where it tore free: a low wall rolling out over the land from the rim, a thinning pall behind;
// along the ray from ro to `far`: premultiplied colour, transmittance.
fn lf_dust_at(p: vec3<f32>, a: f32, gh: f32) -> f32 {
    let y = p.y - gh;
    if (y > 7.5 || y < -2.0) {
        return 0.0;
    }
    let r = length(p.xz);
    let ang = atan2(p.z, p.x);
    let R = lf_rim(ang);
    let front = R + 1.0 + 20.0 * (1.0 - exp(-a / 0.8));
    let w = 1.6 + 3.0 * (1.0 - exp(-a / 1.3));
    let wq = (r - front) / w;
    // (where there can be none, no noise worked out)
    let env = max(exp(-wq * wq), 0.22 * smoothstep(front + 0.5 * w, R + 1.0, r) * step(R - 0.5, r));
    if (env < 0.02) {
        return 0.0;
    }
    // (in clumps along it, rolling over, torn at the top: no smooth ring)
    let n = gfbm3(vec3<f32>(p.x * 0.3, y * 0.38 - a * 0.7, p.z * 0.3) + vec3<f32>(seed_v() * 0.1, 0.0, 0.0), 3);
    let clump = saturate(gnoise3(vec3<f32>(p.x * 0.12, y * 0.15, p.z * 0.12) + vec3<f32>(3.0, seed_v() * 0.07, 1.0)) * 1.6 - 0.3);
    let ht = (1.8 + 3.4 * (1.0 - exp(-a / 0.5))) * (0.65 + 0.7 * clump) * (0.7 + 0.6 * n);
    let wall = exp(-wq * wq) * (0.55 + 0.7 * clump);
    let pall = 0.22 * smoothstep(front + 0.5 * w, R + 1.0, r) * step(R - 0.5, r) * (0.5 + clump);
    let den = max(wall, pall) * saturate((ht - y) / 1.0) * smoothstep(-2.0, 0.0, y) * saturate(n * 2.4 - 0.75);
    return den * 0.22 * smoothstep(0.0, 0.1, a) * (1.0 - smoothstep(1.0, 4.5, a));
}
fn lf_dust(ro: vec3<f32>, rd: vec3<f32>, far: f32, t: f32, px: vec2<f32>, sunc: vec3<f32>, amb: vec3<f32>, L: vec3<f32>) -> vec4<f32> {
    let a = t - LF_TEAR;
    if (a < 0.0 || a > 4.5 || sb_w(LF_RIM) < 1.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    // (its land's height round the target: the heights the pass has for the panes' dust)
    let gh = 0.0;
    let R = 9.0 + 1.0 + 20.0 * (1.0 - exp(-a / 0.8)) + 9.0;
    let lo = vec3<f32>(-R, gh - 3.0, -R);
    let hi = vec3<f32>(R, gh + 7.5, R);
    let ad = max(abs(rd), vec3<f32>(1.0e-6));
    let inv = select(-1.0 / ad, 1.0 / ad, rd >= vec3<f32>(0.0));
    let ta = (lo - ro) * inv;
    let tb = (hi - ro) * inv;
    let t0 = max(max(max(min(ta.x, tb.x), min(ta.y, tb.y)), min(ta.z, tb.z)), 0.0);
    let t1 = min(min(min(max(ta.x, tb.x), max(ta.y, tb.y)), max(ta.z, tb.z)), far);
    if (t1 <= t0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    var acc = vec3<f32>(0.0);
    var tr = 1.0;
    let n = 22;
    let dt = (t1 - t0) / f32(n);
    var s = t0 + dt * ign(px);
    for (var m = 0; m < n; m = m + 1) {
        let p = ro + rd * s;
        let den = lf_dust_at(p, a, gh);
        if (den > 0.002) {
            let hy = saturate((p.y - gh) / 7.0);
            let base = mix(vec3<f32>(0.22, 0.18, 0.14), vec3<f32>(0.42, 0.37, 0.31), hy);
            let lit = base * (sunc * (0.35 + 0.65 * hy) * 0.8 + amb * (0.45 + 0.4 * hy));
            let ab = exp(-den * dt);
            acc = acc + tr * (1.0 - ab) * lit;
            tr = tr * ab;
            if (tr < 0.02) {
                break;
            }
        }
        s = s + dt;
    }
    return vec4<f32>(acc, tr);
}

// The dust it trails as it climbs: a thin streak hung in the air from its hole to where it is, widening and thinning
// as it ages; along (ro, rd) to `far`: premultiplied colour, transmittance.
fn lf_trail(ro: vec3<f32>, rd: vec3<f32>, far: f32, t: f32, sunc: vec3<f32>, amb: vec3<f32>) -> vec4<f32> {
    let none = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    if (t < LF_TEAR + 0.4 || t > LF_IN + 3.5 || sb_w(LF_W) < 0.5) {
        return none;
    }
    let ps = lf_pose(min(t, LF_IN));
    let bot = lf_h(21u);
    let o = ro.xz - ps.c.xz;
    let dd = dot(rd.xz, rd.xz);
    if (dd < 1.0e-5) {
        return none;
    }
    let s = -dot(o, rd.xz) / dd;
    if (s < 0.0 || s > far) {
        return none;
    }
    let dh = length(o + rd.xz * s);
    let y = ro.y + rd.y * s;
    let top = min(ps.c.y - bot, SB_H);
    if (y < 0.0 || y > top || dh > 40.0) {
        return none;
    }
    // (when its bottom passed this height: the way's samples searched)
    var lo = i32(LF_TEAR / LF_DT);
    var hi = min(i32(t / LF_DT) + 1, LF_NP - 1);
    for (var k = 0; k < 8; k = k + 1) {
        let mid = (lo + hi) / 2;
        if (lf_pc(mid).y - bot < y) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    let age = max(t - f32(hi) * LF_DT, 0.0);
    let r = 1.8 + 2.2 * age + 0.004 * y;
    let lump = 0.55 + 0.9 * gnoise2(vec2<f32>(y * 0.07 - age * 0.4, seed_v() * 0.3));
    let sin_a = sqrt(dd);
    let tau = 0.045 * exp(-age / 1.3) * smoothstep(0.0, 0.2, age + 0.05) * exp(-dh * dh / (r * r)) * r * 1.77 / max(sin_a, 0.12) * lump * smoothstep(0.0, 6.0, y) * (1.0 - smoothstep(SB_H - 20.0, SB_H, y));
    let a = 1.0 - exp(-tau);
    let lit = vec3<f32>(0.4, 0.35, 0.3) * (sunc * 0.35 + amb * 0.9);
    return vec4<f32>(lit * a, 1.0 - a);
}

// ---- the sky before it breaks: drawn up round the island as it goes in, ringing, pressed on
struct LfPress {
    bow: f32,   // how far the sky is bowed down over the target, blocks
    dark: f32,  // how dark the hand behind it shows (its shape and softness: the hand's own, `hd_shade`)
    white: f32, // the strain whitening the sky
}
// (in step with the hand's motion, sb_hand.rs's `punch`: down out of the dark from 6.3 s, laid flat on the sky by 7.15
// and leaning on it, up on its knuckles by 7.9, drawn back from 7.95 and thrown at LF_PUNCH)
const LF_HAND: f32 = 6.3;
fn lf_press(t: f32) -> LfPress {
    let s = smoothstep(7.12, 7.95, t);
    // (pressing, with two creaks where it gives a little more)
    var bow = 22.0 * s * s * (3.0 - 2.0 * s) * 0.85 + 3.0 * smoothstep(7.5, 7.62, t) + 4.0 * smoothstep(7.9, 8.03, t);
    var dark = 0.66 * smoothstep(LF_CURL - 0.1, LF_CURL + 0.15, t); // (unseen until the fist is drawn back)
    var white = 0.55 * smoothstep(7.3, 8.05, t);
    // (it lifts off, the sky springing back a little; the fist comes down)
    let back = smoothstep(8.05, 8.5, t);
    bow = bow - 9.0 * back;
    let p = saturate((t - LF_PUNCH) / (SB_CRACK - LF_PUNCH));
    bow = bow + 40.0 * p * p * p;
    dark = dark + (0.9 - dark) * p * p;
    white = white + (1.0 - white) * p * p;
    let end = 1.0 - smoothstep(SB_CRACK, SB_CRACK + 0.15, t);
    return LfPress(bow * end, dark * end, white * end);
}
// The sky over the target before it breaks, along rd (ro: the camera from the target's ground point; uv its pixel;
// `col` the scene's colour there, sky).
fn lf_sky(col: vec3<f32>, uv: vec2<f32>, ro: vec3<f32>, rd: vec3<f32>, t: f32, C: vec3<f32>, px_a: f32, skyl: vec3<f32>, sunc: vec3<f32>, amb: vec3<f32>, nk: f32, day: f32, L: vec3<f32>) -> vec3<f32> {
    if (t < LF_TOUCH - 0.6 || t > SB_CRACK + 0.2 || ro.y > SB_H || rd.y <= 0.0 || sb_w(LF_W) < 0.5) {
        return col;
    }
    let tp = (SB_H - ro.y) / rd.y;
    let q = ro.xz + rd.xz * tp;
    let pxw = tp * px_a / sqrt(max(rd.y, 0.06));
    let far_c = exp(-tp / 4200.0);
    let dq = length(q);
    let bp = project_rel(C + vec3<f32>(0.0, SB_H, 0.0));
    let rdir = normalize(uv - bp.xy + vec2<f32>(1.0e-5, 0.0));
    var slope = 0.0;      // the sky's surface's slope out from the middle (its bending: the sky seen shifted)
    var add = vec3<f32>(0.0);
    var c = col;
    // (going in: the sky drawn up round it, a skin round its waist, closing on a point of light as its last goes in)
    let ps = lf_pose(min(t, LF_IN + 0.5));
    let top = lf_h(16u);
    let hh = lf_h(3u);
    let above = ps.c.y + top - SB_H;
    let into = saturate(above / max(hh, 1.0));
    let rs = 8.0 * (1.0 - pow(into, 1.4)) + 0.5;
    let cq = length(q - ps.c.xz);
    let near_in = smoothstep(-70.0, 0.0, above) * (1.0 - smoothstep(LF_IN, LF_IN + 0.18, t));
    let pull = (1.5 + 4.0 * into) * near_in;
    let dx = max(cq - rs, 0.0);
    slope = slope - pull * exp(-dx / 22.0) / 22.0 * 6.0;
    let skin = exp(-dx * dx / max(pxw * pxw * 1.5, 0.3)) * smoothstep(-0.5, 0.5, above) * (1.0 - smoothstep(LF_IN - 0.05, LF_IN + 0.05, t));
    add = add + (skyl * 0.5 + vec3<f32>(0.25, 0.28, 0.32) * day) * skin * nk + skyl * 0.18 * exp(-dx / 14.0) * near_in * smoothstep(-20.0, 0.0, above) * nk;
    let pinch = smoothstep(LF_IN - 0.06, LF_IN, t) * exp(-max(t - LF_IN, 0.0) / 0.12);
    add = add + vec3<f32>(1.0, 1.0, 1.05) * pinch * (exp(-dq / max(pxw * 1.2, 1.0)) * 1.6 + exp(-dq / 14.0) * 0.12) * mix(0.5, 1.0, nk);
    // (its dark behind the sky a moment, as through frosted glass, rising away)
    let behind = smoothstep(LF_TOUCH, LF_IN, t) * (1.0 - smoothstep(LF_IN, LF_IN + 1.3, t));
    let blob = exp(-pow(cq / (9.0 + 14.0 * smoothstep(LF_TOUCH, LF_IN + 1.0, t)), 2.0));
    // (ringing: tight stiff rings racing out from where it went in, a pane flexing, gone by LF_PRESS)
    var crest = 0.0;
    var trough = 0.0;
    for (var n = 0; n < 3; n = n + 1) {
        let a = t - (LF_RIPPLE - 0.1 + 0.09 * f32(n));
        if (a <= 0.0) {
            continue;
        }
        let rr = 300.0 * a * (1.0 - 0.17 * a);
        let w = 5.0 + 0.03 * rr;
        let x = (dq - rr) / w;
        let amp = pow(0.62, f32(n)) * exp(-a / 0.75) / sqrt(1.0 + rr / 120.0) * (1.0 - smoothstep(LF_PRESS - 0.6, LF_PRESS, t));
        slope = slope + amp * (1.0 - 2.0 * x * x) * exp(-x * x) * 1.6;
        crest = crest + amp * exp(-x * x * 3.0) * max(1.0 - 2.0 * x * x, 0.0);
        trough = trough + amp * exp(-(x + 1.1) * (x + 1.1) * 2.0);
    }
    add = add + (sunc * 0.22 + skyl * 0.55) * crest * far_c * mix(0.4, 1.0, nk);
    // (pressed on: bowed down over the target, whitening with strain, the hand's dark on it)
    let pr = lf_press(t);
    let W = 230.0;
    let g = exp(-dq * dq / (W * W));
    if (t > LF_PRESS) {
        slope = slope + pr.bow * 2.0 * dq / (W * W) * g * 4.0;
    }
    // (the hand behind it: its dark on the glass, softer and fainter the further off)
    var hs = vec3<f32>(0.0);
    if (t > LF_HAND) {
        hs = hd_shade(q, t, 1.0);
    }
    let cover = hs.x * pr.dark;
    // (the sky through the bent glass: shifted out from or in to the middle, under whatever is drawn over it; the
    // island's dark behind it)
    if (abs(slope) > 1.0e-4) {
        let uv2 = clamp(uv + rdir * slope * 0.004, vec2<f32>(0.0), vec2<f32>(1.0));
        if (is_sky(depth_at(uv2))) {
            let s0 = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
            c = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv2, 0.0).rgb) + (col - s0);
        }
    }
    c = c * (1.0 - 0.45 * behind * blob) * (1.0 - 0.14 * min(trough, 1.0) * far_c);
    // (the bowed glass catching the light along its slope)
    let sh = pr.bow / 30.0 * g * (dq / W) * dot(normalize(q + vec2<f32>(1.0e-4, 0.0)), normalize(L.xz + vec2<f32>(1.0e-4, 0.0)));
    c = c * (1.0 + 0.35 * sh) + sunc * max(sh, 0.0) * 0.08;
    if (t > LF_PRESS) {
        // (whitening where strained most, under the hand and round its middle: pale streaks across the strain (arcs
        // round the middle, crazed), a milky haze between; fine crazes in them near enough to see)
        let strain = saturate(g * 1.1 + 0.7 * hs.z * pr.dark) * pr.white;
        let frost = vec3<f32>(0.86, 0.9, 0.98) * (amb * 1.3 + sunc * 0.25);
        let ang = atan2(q.y, q.x);
        // (in clumps, as stressed glass goes milky, drawn out a little along arcs round the middle)
        let band = gfbm2(vec2<f32>(dq / 16.0, ang * max(dq, 30.0) / 22.0) + vec2<f32>(seed_v() * 0.13, 0.0)) * 0.75 + gnoise2(q / 4.0) * 0.25;
        let streak = smoothstep(0.6 - 0.2 * strain, 0.78 - 0.12 * strain, band) * strain;
        let cu = vec2<f32>(dq / 2.4, ang * max(dq, 1.0) / 7.0);
        let ci = floor(cu);
        let cf = cu - ci;
        let ch = fh21(ci + vec2<f32>(seed_v(), 31.0));
        let craze = step(ch, strain * 1.2) * (1.0 - smoothstep(0.06, 0.06 + max(pxw / 2.4, 0.02), abs(cf.x - 0.5 - 0.3 * (fh21(ci + vec2<f32>(4.0, seed_v())) - 0.5)))) * step(abs(cf.y - 0.5), 0.38) * min(0.15 / max(pxw, 1.0e-3), 1.0);
        c = mix(c, frost, saturate(0.12 * strain + 0.45 * streak + 0.5 * craze) * far_c);
    }
    // (the hand's dark, deep violet at heart, a faint cold glow round its edge)
    c = c * (1.0 - 0.8 * cover) + vec3<f32>(0.012, 0.008, 0.03) * cover;
    add = add + vec3<f32>(0.42, 0.48, 1.0) * 0.12 * pr.dark * hs.y * (1.0 - 0.6 * cover) * mix(0.6, 1.0, nk);
    // (the star crack where it went in: a few short cracks snapped out from the point, glinting, creeping on under the
    // pressure)
    let st = smoothstep(LF_STAR, LF_STAR + 0.05, t) * (1.0 - smoothstep(SB_CRACK, SB_CRACK + 0.2, t));
    if (st > 0.0 && dq < 60.0) {
        let s = u32(seed_v());
        var dmin = 1.0e9;
        var glint = 0.0;
        for (var i = 0; i < 7; i = i + 1) {
            let a = TAU * (f32(i) + 0.7 * mh(u32(i), s, 0x1e1u)) / 7.0;
            let len = (8.0 + 22.0 * mh(u32(i), s, 0x1e2u)) * (1.0 + 0.5 * smoothstep(LF_PRESS, SB_CRACK, t)) * st;
            let dir = vec2<f32>(cos(a), sin(a));
            let along = dot(q, dir);
            if (along < 0.0 || along > len) {
                continue;
            }
            let wob = 0.6 * (gnoise2(vec2<f32>(along * 0.25, f32(i) * 7.0)) - 0.5) * smoothstep(0.0, 6.0, along);
            let dd = abs(dot(q, vec2<f32>(-dir.y, dir.x)) - wob);
            if (dd < dmin) {
                dmin = dd;
                // (glints along it, twinkling)
                let gk = floor(along / 2.0);
                let gh = fh21(vec2<f32>(gk + f32(i) * 31.0, seed_v()));
                glint = step(0.72, gh) * (0.5 + 0.5 * sin(t * (7.0 + 9.0 * gh) + gh * 40.0));
            }
        }
        let ew = max(0.3, pxw * 0.7);
        let line = exp(-dmin * dmin / (ew * ew)) * min(0.3 / max(pxw * 0.7, 1.0e-3), 1.0);
        let crush = exp(-dq / 2.5) * 0.6;
        add = add + vec3<f32>(0.85, 0.92, 1.0) * (line * (0.6 + 1.6 * glint) + crush) * st * (0.4 + 0.4 * day) * mix(0.3, 1.0, nk) * far_c;
        add = add + sunc * glint * exp(-dmin / max(pxw * 1.5, 0.6)) * 0.5 * st;
    }
    return c + add;
}
// The hand's shadow on the land as the sun throws it through the sky (p: the scene's point, from the target's ground
// point).
fn lf_land(col: vec3<f32>, p: vec3<f32>, t: f32, L: vec3<f32>) -> vec3<f32> {
    if (t < LF_HAND || t > SB_CRACK + 0.2 || L.y < 0.15 || sb_w(LF_W) < 0.5) {
        return col;
    }
    let s = (SB_H - p.y) / L.y;
    let cover = hd_shade(p.xz + L.xz * s, t, 1.8).x * lf_press(t).dark;
    return col * (1.0 - 0.3 * cover);
}
// [end lift]

struct SbOut {
    c: vec4<f32>,
    e: vec4<f32>,
}

// The pane's flat sky colour where it shows its painted sky (falling): the sky's blue, its clouds lit white.
fn sb_painted(qx: f32, qz: f32, skyl: vec3<f32>, sunc: vec3<f32>, amb: vec3<f32>) -> vec3<f32> {
    let m = sb_sky(qx, qz);
    let blue = skyl * 1.05;
    if (m == 2) {
        return vec3<f32>(0.92, 0.94, 0.97) * (sunc * 0.55 + amb * 0.9) + skyl * 0.15;
    }
    return select(blue, mix(blue, vec3<f32>(0.8, 0.86, 0.95) * (sunc * 0.3 + amb), 0.3), m == 1);
}

// [hand]
// ---- the hand: the one behind the sky
// It punches through the sky as it cracks (SB_CRACK), knuckles first, a little past and back, held a moment; then goes
// back up through the hole, wrist leading, fingers loosening (HD_LET_GO). At the end (HD_DOWN) it comes back, a fist
// thrown straight down through the hole on to the target in one blow (HD_PRESS): the crater (sb_hand.rs lays it), a
// shockwave over the land (hd_shock) and up through the glass (HD_KNOCK); it grinds in and is lifted out through the
// hole before the sky heals, never through the glass (sb_hand.rs plans it, a pose each 30th of a second at HD_HP, and
// tests that). Two builds on the one pose (hd_set): the hand of rounded shapes and the sculpted one (`the hand as
// sculpted`). Its frame: x across (to the thumb), y its back, z to its fingers, in its bones' units (a palm about 30
// across; HD_SC blocks each).
const HD_LET_GO: f32 = 10.0; // the first shard it drags falls off it
const HD_FLARE: f32 = 35.1;  // the eye flares
const HD_DOWN: f32 = 36.0;   // its fist is thrown down through the hole,
const HD_PRESS: f32 = 37.5;  // slams the land (sb_hand.rs's SB_PRESS),
const HD_KNOCK: f32 = 37.72; // its shudder knocks the last of the middle loose (skybreak.rs's SB_KNOCK)
const HD: u32 = 24576u;      // its words (sb_hand.rs's SB_HD): where the fist's face comes down (x, z), the way its
                             // back faces (x, z), its thumb's side, the land's height there, when it slams, if its
                             // crater is laid
const HD_HP: u32 = HD + 16u; // its poses (sb_hand.rs's SB_HP): the punch's 199 from 6.3 s, the slam's 277 from 33.8 s,
const HD_HP_W: u32 = 26u;    // a 30th of a second apart, 26 words each: its wrist, elbow, shoulder, the way to its
                             // fingers and its back's, each finger's curl, the thumb's, how spread, how much of it
                             // there is, how far each finger's joints lead its knuckle
const HD_SC: f32 = 2.8;      // its size: blocks to its bones' unit (its fist 84 across: the lift's pressing hand,
                             // LF_HS; sb_hand.rs's SB_SC)
// (`--set hdlab=1`: the hand alone over the land, to see its shape: `hd_lab`)
const HD_LAB: bool = false;
// (how much dark there is in its skin, 0 the eye's skin alone: `--set hddm=N`)
const HD_DM: f32 = 0.6;
// (the lab's plain grey clay under one hard light, to judge its shape: the preview's `--set hdclay=1`)
const HD_CLAY: bool = false;
// (the hand as sculpted, from `tools/bake_hand.py`'s grids; false, or no grids: the one of rounded shapes. The
// preview's `--set hdbake=0|1`)
const HD_BAKE: bool = true;
const HB: u32 = 65536u;       // (where its grids are in the mod's data: sb_hand.rs's SB_HB)
const HD_SB: f32 = 18.0;     // (how soft its dark on the sky is, pressed on it)
const HD_SK: f32 = 6.0;      // (how far its parts melt into one another there)
const HD_SHADOW: i32 = 8;     // (the steps of its own shadow on itself)
const HD_LP: bool = false;
const HD_LP_FL: vec4<f32> = vec4<f32>(0.0, 0.0, 0.0, 0.0);
const HD_LP_TS: vec4<f32> = vec4<f32>(0.0, 0.0, 0.0, 0.0);
// The eye's flare (and its light through the hole), 0 to 1.
fn hd_flare(t: f32) -> f32 {
    let a = t - HD_FLARE;
    return smoothstep(-0.05, 0.03, a) * exp(-max(a - 0.03, 0.0) / 0.75);
}
struct HdPose {
    p: vec3<f32>,      // its palm's middle, from the target's ground
    ax: vec3<f32>,     // its frame: across (to the thumb, times side), its back, to its fingers
    ay: vec3<f32>,
    az: vec3<f32>,
    fl: vec4<f32>,     // each finger's curl (index, middle, ring, little): 0 straight, 1 a fist
    th: f32,           // the thumb: 0 out, 1 over the closed fingers
    spread: f32,       // the fingers spread: 0 easy, 1 wide
    side: f32,         // which hand: the thumb's side of ax, 1 or -1
    w: vec3<f32>,      // its wrist,
    el: vec3<f32>,     // its elbow,
    sh: vec3<f32>,     // its shoulder, up in the dark past the hole
    k: f32,            // how much of it there is
    sc: f32,           // blocks to its bones' unit
}
fn hd_none() -> HdPose {
    return HdPose(vec3<f32>(0.0), vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 0.0, 1.0), vec4<f32>(0.0), 0.0, 0.0, 1.0, vec3<f32>(0.0), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 2.0, 0.0), 0.0, HD_SC);
}
// (the lab (HD_LAB): the hand hung over the land, closing each second (open at .0, shut by .8), turned 45 degrees more
// each second, from its back)
fn hd_lab(t: f32) -> HdPose {
    if (HD_LP) {
        // (a set pose: fingers up, back to the camera; tipped to it, then turned)
        let pi = HD_LP_TS.w * 0.017453;
        let ya = HD_LP_TS.z * 0.017453;
        let z0 = vec3<f32>(0.0, cos(pi), sin(pi));
        let b0 = vec3<f32>(0.0, -sin(pi), cos(pi));
        let az = vec3<f32>(z0.x * cos(ya) + z0.z * sin(ya), z0.y, z0.z * cos(ya) - z0.x * sin(ya));
        let bk = vec3<f32>(b0.x * cos(ya) + b0.z * sin(ya), b0.y, b0.z * cos(ya) - b0.x * sin(ya));
        let w = vec3<f32>(0.0, 235.0, 0.0) - az * 90.0;
        let el = w - az * 96.0 * HD_SC;
        return HdPose(w + az * 24.0 * HD_SC, cross(bk, az), bk, az, HD_LP_FL, HD_LP_TS.x, HD_LP_TS.y, 1.0, w, el, el - az * 138.0 * HD_SC, 1.0, HD_SC);
    }
    let c = saturate(fract(t) * 1.25);
    let a = floor(t) * 0.7854;
    let bk = vec3<f32>(sin(a), 0.0, cos(a));
    let w = vec3<f32>(0.0, 300.0, 0.0);
    let az = vec3<f32>(0.0, -1.0, 0.0);
    let fl = vec4<f32>(saturate(c * 1.3 - 0.3), saturate(c * 1.3 - 0.2), saturate(c * 1.3 - 0.1), saturate(c * 1.3)) + vec4<f32>(0.08, 0.1, 0.14, 0.2) * (1.0 - c);
    let el = w + vec3<f32>(0.0, 96.0 * HD_SC, 0.0);
    return HdPose(w + az * 24.0 * HD_SC, cross(bk, az), bk, az, fl, saturate(c * 1.4 - 0.4), 0.4 * (1.0 - c), 1.0, w, el, el + vec3<f32>(0.0, 138.0 * HD_SC, 0.0), 1.0, HD_SC);
}
fn hd_hpv(i: u32, k: u32) -> vec3<f32> {
    let b = HD_HP + i * HD_HP_W + k;
    return vec3<f32>(sb_w(b), sb_w(b + 1u), sb_w(b + 2u));
}
fn hd_hpf(i: u32, k: u32) -> vec4<f32> {
    let b = HD_HP + i * HD_HP_W + k;
    return vec4<f32>(sb_w(b), sb_w(b + 1u), sb_w(b + 2u), sb_w(b + 3u));
}
// Its palm's middle's height at t in the punch, cheaply (what drags the shards up with it).
fn hd_py(t: f32) -> f32 {
    let x = clamp((t - 6.3) * 30.0, 0.0, 198.0);
    let i = u32(floor(x));
    let b = min(i + 1u, 198u);
    let ya = sb_w(HD_HP + i * HD_HP_W + 1u) + sb_w(HD_HP + i * HD_HP_W + 10u) * 24.0 * HD_SC;
    let yb = sb_w(HD_HP + b * HD_HP_W + 1u) + sb_w(HD_HP + b * HD_HP_W + 10u) * 24.0 * HD_SC;
    return mix(ya, yb, x - floor(x));
}
// Where it is at t: between its poses either side of t (sb_hand.rs's `Arm`).
fn hd_pose(t: f32) -> HdPose {
    if (HD_LAB) {
        return hd_lab(t);
    }
    var base = 0u;
    var n = 199u;
    var t0 = 6.3;
    var side = 1.0;
    if (t > 25.0) {
        base = 199u;
        n = 277u;
        t0 = 33.8;
        side = select(-1.0, 1.0, sb_w(HD + 4u) >= 0.0);
    }
    let x = (t - t0) * 30.0;
    if (x < 0.0 || x > f32(n - 1u) || arrayLength(&mod_data) < HD_HP + (base + n) * HD_HP_W) {
        return hd_none();
    }
    let i = u32(floor(x));
    let u = x - floor(x);
    let a = base + i;
    let b = base + min(i + 1u, n - 1u);
    let w = mix(hd_hpv(a, 0u), hd_hpv(b, 0u), u);
    let az = normalize(mix(hd_hpv(a, 9u), hd_hpv(b, 9u), u));
    var ay = mix(hd_hpv(a, 12u), hd_hpv(b, 12u), u);
    ay = normalize(ay - az * dot(ay, az) + vec3<f32>(1e-5, 0.0, 0.0));
    let rest = mix(hd_hpf(a, 18u), hd_hpf(b, 18u), u);
    hd_hk = mix(hd_hpf(a, 22u), hd_hpf(b, 22u), u);
    return HdPose(w + az * 24.0 * HD_SC, cross(ay, az), ay, az, mix(hd_hpf(a, 15u), hd_hpf(b, 15u), u), rest.y, rest.z, side, w, mix(hd_hpv(a, 3u), hd_hpv(b, 3u), u), mix(hd_hpv(a, 6u), hd_hpv(b, 6u), u), rest.w, HD_SC);
}
// A bone of a finger or the thumb, in the hand's frame: its start, way, back, length, half-width at each end.
struct HdBone {
    a: vec3<f32>,
    f: vec3<f32>,
    u: vec3<f32>,
    r: vec3<f32>,
    len: f32,
    w0: f32,
    w1: f32,
}
// The pose drawn and its bones, once a pixel (`hd_set`): the fingers' bones (3 a finger, index to little), the thumb's
// (12 to 14); each finger's ball (middle, radius), its tendon's radius; the forearm's line and frame (way from the
// wrist, length; across and back at wrist and elbow), the ridge of muscle down it, the way from shoulder to elbow.
var<private> hd_h: HdPose;
var<private> hd_hk: vec4<f32>;     // how far each finger's joints' curl leads its knuckle (hd_pose sets, hd_set reads)
var<private> hd_fb: array<HdBone, 15>;
var<private> hd_kn: array<vec4<f32>, 4>;  // (the lean model's knuckles as posed)
var<private> hd_uh: vec3<f32>;     // (the lean model's: the bony knob on its wrist's back, the little finger's side)
var<private> hd_fc: array<vec4<f32>, 4>;
var<private> hd_tc: vec4<f32>;     // (and round the sculpted thumb)
var<private> hd_tr: vec4<f32>;
var<private> hd_ad: vec3<f32>;
var<private> hd_lf: f32;
var<private> hd_x0: vec3<f32>;
var<private> hd_x1: vec3<f32>;
var<private> hd_r0: vec3<f32>;
var<private> hd_r1: vec3<f32>;
var<private> hd_ue: vec3<f32>;
var<private> hd_cv: f32;          // how closed the fingers are in all
var<private> hd_bc: vec3<f32>;     // a box round the hand in its frame: its middle and half its size
var<private> hd_bh: vec3<f32>;
// Each finger's knuckle (its joint's middle) and its head's radius: on an arc, the middle one highest and furthest out,
// the little one back and low (sb_hand.rs's HD_KNUCKLES).
fn hd_knuckle(i: i32) -> vec4<f32> {
    // (a man's hand, 0.36 of a unit to the mm: 86 mm across, the knuckles 85 mm from the wrist's middle on their arc, 7
    // units apart)
    var k = array<vec4<f32>, 4>(vec4<f32>(10.9, 0.9, 7.0, 4.0), vec4<f32>(3.5, 1.6, 7.7, 4.2), vec4<f32>(-3.9, 1.1, 4.8, 3.8), vec4<f32>(-11.0, -0.3, 1.6, 3.3));
    return k[i];
}
// Each finger's length, half-width at its root, way out from the palm (radians, to the thumb), and how its curl leans
// in to the palm's middle.
fn hd_digit_dims(i: i32) -> vec4<f32> {
    // (82, 92, 88 and 70 mm from their knuckles' middles, about 20 across; the little one's tip at the ring finger's
    // last joint; curling, they turn in to the thumb's root)
    var d = array<vec4<f32>, 4>(vec4<f32>(29.5, 3.8, 0.07, 0.05), vec4<f32>(33.1, 3.9, 0.012, -0.03), vec4<f32>(31.7, 3.65, -0.05, -0.15), vec4<f32>(25.2, 3.25, -0.14, -0.28));
    return d[i];
}
fn hd_fore_ab(c: f32, sc: f32) -> vec2<f32> {
    // (a narrow flat wrist, cords and bone its first third, its muscles' bellies swelling to their widest two thirds
    // up, in again to the elbow)
    return sc * vec2<f32>(10.2 + 1.0 * c + 7.7 * smoothstep(0.03, 0.72, c) - 3.4 * smoothstep(0.82, 1.0, c), 6.3 + 1.6 * c + 7.7 * smoothstep(0.03, 0.68, c) - 2.0 * smoothstep(0.84, 1.0, c));
}
// Pose h's bones and its arm's frame, into hd_h, hd_fb ... for hd_map.
fn hd_set(h: HdPose) {
    hd_h = h;
    // (the sculpted one, if its grids are there)
    hb_on = HD_BAKE && arrayLength(&mod_data) >= HB + HB_WORDS && mod_data[HB] == 0x53424844u && mod_data[HB + 3u] == HB_WORDS;
    for (var i = 0; i < 4; i = i + 1) {
        var kn = hd_knuckle(i);
        let dm = hd_digit_dims(i);
        let c = h.fl[i];
        // (closing, the back arches: the ring and little fingers' knuckles sink to the palm)
        kn.y = kn.y - saturate(dot(h.fl, vec4<f32>(0.25))) * select(0.0, select(0.7, 1.7, i == 3), i > 1);
        hd_kn[i] = kn;
        let spl = dm.z * (1.0 + 1.6 * h.spread) * (1.0 - 0.6 * saturate(c));
        let f = vec3<f32>(sin(spl), 0.0, cos(spl));
        var u = vec3<f32>(dm.w * saturate(c * 1.4), 1.0, 0.0);
        u = normalize(u - f * dot(u, f));
        // (its three joints bend together, the root as much as the rest: at rest a gentle curl all along, not a hook;
        // shut, as far as a hand's go, 86, 110 and 74 degrees: the last two thirds of the middle one)
        let t1 = 1.5 * (c - 0.5 * hd_hk[i]);
        let t2 = 1.92 * saturate(c + 0.5 * hd_hk[i]);
        let t3 = 0.67 * t2;
        var ang = array<f32, 3>(t1, t1 + t2, t1 + t2 + t3);
        var lens = array<f32, 3>(0.48, 0.29, 0.23);
        var wd = array<vec2<f32>, 3>(vec2<f32>(1.0, 0.94), vec2<f32>(0.94, 0.86), vec2<f32>(0.85, 0.74));
        var p = kn.xyz;
        for (var s = 0; s < 3; s = s + 1) {
            let fs = f * cos(ang[s]) - u * sin(ang[s]);
            let us = u * cos(ang[s]) + f * sin(ang[s]);
            hd_fb[i * 3 + s] = HdBone(p, fs, us, cross(us, fs), lens[s] * dm.x, wd[s].x * dm.y, wd[s].y * dm.y);
            p = p + fs * lens[s] * dm.x;
        }
        hd_fc[i] = vec4<f32>((kn.xyz + p) * 0.5, 0.5 * length(p - kn.xyz) + 0.3 * dm.x + dm.y);
        hd_tr[i] = 0.5 * (1.0 - 0.7 * saturate(c));
    }
    // (the thumb: from low by the wrist, out to the side and forward, turned from the palm; closed, across the index
    // and middle fingers' middle bones, tip down)
    let c = saturate(h.th);
    let s = h.spread;
    // (open, it carries on its first bone's way, its end bent back a little, not in by the fingers)
    let o1 = vec3<f32>(0.54 + 0.2 * s, -0.28, 0.78);
    let o2 = vec3<f32>(0.5 + 0.22 * s, -0.24, 0.83);
    // (closed, across the fist: slanting over the index finger's middle bone, its end across the middle finger's)
    let c1 = vec3<f32>(-0.52, -0.59, 0.62);
    let c2 = vec3<f32>(-0.95, 0.0, 0.3);
    // (its first bone swings in front of the palm; in the fist no further than lets the thumb lie on the fingers)
    let m1 = vec3<f32>(0.3, -0.5, 0.81);
    var tf = array<vec3<f32>, 3>(normalize(mix(vec3<f32>(0.7 + 0.2 * s, -0.33, 0.63 - 0.15 * s), m1, c)), normalize(mix(o1, c1, c)), normalize(mix(o2, c2, c)));
    let up = normalize(mix(vec3<f32>(0.8, 0.55, -0.2), vec3<f32>(0.25, -0.95, 0.15), c));
    var tl = array<vec3<f32>, 3>(vec3<f32>(15.6, 4.7, 4.3), vec3<f32>(10.8, 4.3, 4.1), vec3<f32>(8.6, 4.15, 3.4));
    var tp = vec3<f32>(8.6, -3.4, -16.5);
    // (the sculpted thumb's ball stays with the palm, its bones not round: its first turns with the pose less than
    // its last, which has the nail)
    var roll = array<f32, 3>(0.4, 0.8, 1.0);
    for (var k = 0; k < 3; k = k + 1) {
        var uk = up;
        if (hb_on) {
            uk = normalize(mix(vec3<f32>(0.8, 0.55, -0.2), vec3<f32>(0.25, -0.95, 0.15), c * roll[k]));
        }
        let tu = normalize(uk - tf[k] * dot(uk, tf[k]));
        hd_fb[12 + k] = HdBone(tp, tf[k], tu, cross(tu, tf[k]), tl[k].x, tl[k].y, tl[k].z);
        tp = tp + tf[k] * tl[k].x;
    }
    // (the forearm: its way from the wrist, length, frame turning along it; the ridge on its thumb's side)
    let A = h.el - h.w;
    hd_lf = length(A);
    hd_ad = A / max(hd_lf, 1e-3);
    hd_x0 = normalize(h.ax - hd_ad * dot(h.ax, hd_ad) + vec3<f32>(1e-4, 0.0, 0.0));
    let y0 = cross(hd_x0, hd_ad);
    let tw = 0.95 * h.side;
    hd_x1 = hd_x0 * cos(tw) + y0 * sin(tw);
    let r0 = 0.28;
    let x_r0 = normalize(mix(hd_x0, hd_x1, r0));
    let ab0 = hd_fore_ab(r0, h.sc);
    let ab1 = hd_fore_ab(1.0, h.sc);
    hd_r0 = h.w + hd_ad * r0 * hd_lf + x_r0 * h.side * ab0.x * 0.72 + cross(x_r0, hd_ad) * ab0.y * 0.25;
    hd_r1 = h.w + hd_ad * 1.04 * hd_lf + hd_x1 * h.side * ab1.x * 0.6 + cross(hd_x1, hd_ad) * ab1.y * 0.3;
    hd_ue = normalize(h.el - h.sh);
    hd_uh = h.w + hd_ad * 2.4 * h.sc - hd_x0 * h.side * 6.9 * h.sc + y0 * 1.7 * h.sc;
    hd_cv = saturate(dot(h.fl, vec4<f32>(0.25)));
    // (the box round it: the palm, each bone's ends with its width)
    var lo = vec3<f32>(-17.0, -10.0, -31.0);
    var hi = vec3<f32>(17.0, 8.0, 13.0);
    for (var k = 0; k < 15; k = k + 1) {
        let bn = hd_fb[k];
        let e = bn.a + bn.f * bn.len;
        lo = min(lo, min(bn.a, e) - vec3<f32>(bn.w0 + 1.0));
        hi = max(hi, max(bn.a, e) + vec3<f32>(bn.w0 + 1.0));
    }
    lo = min(lo, hd_fb[12].a - vec3<f32>(9.0));
    // (the sculpted one: its own box and balls round the fingers and the thumb)
    if (hb_on) {
        // (the palm's own from where it takes over from the forearm: `hd_hand_b`)
        lo = vec3<f32>(HB_PLO.xy, -33.0);
        hi = HB_PHI;
        for (var k = 0; k < 15; k = k + 1) {
            let bn = hd_fb[k];
            let e = bn.a + bn.f * bn.len;
            lo = min(lo, min(bn.a, e) - vec3<f32>(HB_RAD[k]));
            hi = max(hi, max(bn.a, e) + vec3<f32>(HB_RAD[k]));
        }
        for (var i = 0; i < 4; i = i + 1) {
            let c = hd_fc[i].xyz;
            var r = 0.0;
            for (var s = 0; s < 3; s = s + 1) {
                let bn = hd_fb[i * 3 + s];
                r = max(r, max(length(bn.a - c), length(bn.a + bn.f * bn.len - c)) + HB_RAD[i * 3 + s]);
            }
            hd_fc[i] = vec4<f32>(c, r);
        }
        let tc = 0.5 * (hd_fb[12].a + hd_fb[14].a + hd_fb[14].f * hd_fb[14].len);
        var tr = 0.0;
        for (var k = 12; k < 15; k = k + 1) {
            let bn = hd_fb[k];
            tr = max(tr, max(length(bn.a - tc), length(bn.a + bn.f * bn.len - tc)) + HB_RAD[k]);
        }
        hd_tc = vec4<f32>(tc, tr);
        // (and the forearm's end, the palm running into it: bent at the wrist, it leaves the palm's box)
        let fw = h.w + hd_ad * 13.0 * h.sc - h.p;
        let fl = vec2<f32>(dot(fw, h.ax) * h.side, dot(fw, h.ay)) / h.sc;
        lo = vec3<f32>(min(lo.xy, fl - vec2<f32>(11.0)), lo.z);
        hi = vec3<f32>(max(hi.xy, fl + vec2<f32>(11.0)), hi.z);
    }
    hd_bc = 0.5 * (lo + hi);
    hd_bh = 0.5 * (hi - lo);
}
// One of its parts behind the unbroken sky at q on it: a bone from a to b (ra, rb its radius at each end), melted into
// the parts before it (o0) as one shape (HD_SK), the lower winning: x its weight at q, y its height over the glass and
// z how much of it shows, by that weight. `fade`: lost in the dark towards b; `feet` 2: its lower end too.
fn hd_shade_cap(o0: vec4<f32>, q: vec2<f32>, a: vec3<f32>, b: vec3<f32>, ra: f32, rb: f32, fade: f32, feet: i32) -> vec4<f32> {
    let ba = b.xz - a.xz;
    let qa = q - a.xz;
    let u = saturate(dot(qa, ba) / max(dot(ba, ba), 1.0e-3));
    let lo = select(0.0, 1.0, b.y - rb < a.y - ra);
    var o = o0;
    for (var k = 0; k < feet; k = k + 1) {
        let v = select(u, lo, k == 1);
        let r = mix(ra, rb, v);
        let hgt = max(mix(a.y, b.y, v) - r - SB_H, 0.0);
        let w = exp((r - length(qa - ba * v)) / HD_SK - 0.05 * hgt) * select(1.0, abs(lo - u), k == 1);
        o = o + w * vec4<f32>(1.0, hgt, 1.0 - fade * smoothstep(0.1, 0.8, v), 0.0);
    }
    return o;
}
fn hd_off(q: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let ba = b - a;
    return length(q - a - ba * saturate(dot(q - a, ba) / max(dot(ba, ba), 1.0e-3)));
}
// The hand behind the unbroken sky, seen through it at q (blocks, from the target): its pose at t (sb_hand.rs's
// `punch`'s press), every bone as it is. x how dark, y a glow round its edge, z how hard it bears on the glass there.
// `soft`: how much softer than on the glass (its shadow thrown on the land).
fn hd_shade(q: vec2<f32>, t: f32, soft: f32) -> vec3<f32> {
    if (HD_LAB) {
        return vec3<f32>(0.0);
    }
    let h = hd_pose(t);
    // (no pose yet, or nowhere near it across the sky)
    if (h.w.y < SB_H * 0.5 || min(hd_off(q, h.p.xz + h.az.xz * 40.0 * h.sc, h.w.xz), min(hd_off(q, h.w.xz, h.el.xz), hd_off(q, h.el.xz, h.sh.xz))) > 330.0 * soft) {
        return vec3<f32>(0.0);
    }
    hd_set(h);
    let X = h.ax * h.side * h.sc;
    let Y = h.ay * h.sc;
    let Z = h.az * h.sc;
    var o = vec4<f32>(0.0);
    // (its fingers' and thumb's bones)
    for (var k = 0; k < 15; k = k + 1) {
        let bn = hd_fb[k];
        let e = bn.a + bn.f * bn.len;
        o = hd_shade_cap(o, q, h.p + X * bn.a.x + Y * bn.a.y + Z * bn.a.z, h.p + X * e.x + Y * e.y + Z * e.z, bn.w0 * h.sc, bn.w1 * h.sc, 0.0, 2);
    }
    // (the webs between its fingers, a third along their first bones)
    for (var i = 0; i < 3; i = i + 1) {
        let b0 = hd_fb[i * 3];
        let b1 = hd_fb[i * 3 + 3];
        let e0 = b0.a + b0.f * b0.len * 0.34;
        let e1 = b1.a + b1.f * b1.len * 0.34;
        o = hd_shade_cap(o, q, h.p + X * e0.x + Y * e0.y + Z * e0.z, h.p + X * e1.x + Y * e1.y + Z * e1.z, 3.3 * h.sc, 3.3 * h.sc, 0.0, 2);
    }
    // (its palm: a bone to each knuckle from the wrist, its heel, its thumb's ball)
    for (var i = 0; i < 4; i = i + 1) {
        let kn = hd_kn[i];
        o = hd_shade_cap(o, q, h.p + X * kn.x * 0.8 - Y * 1.0 - Z * 21.0, h.p + X * kn.x + Y * (kn.y - 1.0) + Z * kn.z, 6.2 * h.sc, 5.4 * h.sc, 0.0, 2);
    }
    o = hd_shade_cap(o, q, h.p - X * 7.0 - Y * 3.0 - Z * 21.0, h.p + X * 7.0 - Y * 3.0 - Z * 20.0, 7.0 * h.sc, 7.2 * h.sc, 0.0, 2);
    o = hd_shade_cap(o, q, h.p + X * 9.0 - Y * 4.0 - Z * 18.0, h.p + X * 11.0 - Y * 2.5 - Z * 4.0, 6.4 * h.sc, 5.2 * h.sc, 0.0, 2);
    // (its forearm, swelling up from the wrist, and its upper arm, lost in the dark before its shoulder)
    let fm = mix(h.w, h.el, 0.62);
    o = hd_shade_cap(o, q, h.w, fm, 11.0 * h.sc, 17.0 * h.sc, 0.0, 1);
    o = hd_shade_cap(o, q, fm, h.el, 17.0 * h.sc, 14.5 * h.sc, 0.0, 1);
    o = hd_shade_cap(o, q, h.el, h.sh, 16.5 * h.sc, 19.0 * h.sc, 1.0, 1);
    // (the one shape's edge, its height and how much shows there; blurred by its height, a glow round what is close)
    let s = max(o.x, 1.0e-36);
    let hgt = o.y / s;
    let d = -HD_SK * log(s) - 0.05 * HD_SK * hgt;
    let bl = (HD_SB + 0.3 * hgt) * soft;
    let kp = o.z / s;
    let c = 1.0 - smoothstep(-bl, bl, d * (1.0 + 1.4 * smoothstep(0.0, 0.5 * bl, -d)));
    let dd = max(d, 0.0);
    return vec3<f32>(c * exp(-hgt / 260.0), 4.0 * (1.0 - c) * c * exp(-hgt / 45.0), exp(-dd * dd / 3000.0 - hgt / 40.0)) * kp;
}
fn hd_cap(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, ra: f32, rb: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-4));
    return length(pa - ba * h) - mix(ra, rb, h);
}
fn hd_smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}
// ---- the hand: a real one's measures and structure. No round tubes: fingers squarish, flat-backed, padded under,
// knotted at the joints; the back a broad plane with a firm edge, the knuckles hard on it; the palm padded; its parts
// joined with hardly any blend
fn hd_bone_a(l: vec3<f32>, b: HdBone, dk: f32, tip: f32) -> f32 {
    // (a squarish tapering length of finger, `dk` as deep as wide: back flat with firm corners, pad round, a little
    // waisted so the joints are knots; each end a hinge, round from the side, square from above, the next carrying on
    // out of it with no step however it bends; a finger's end round every way)
    let d = l - b.a;
    let rc = 0.92 * dk * b.w1;
    let len = b.len - tip * rc;
    let z = dot(d, b.f);
    let zc = clamp(z / len, 0.0, 1.0);
    // (narrowest at its middle, swelling softly to its joints; past its ends narrowing again as the next bone does:
    // a joint a swell, not a band standing out of both)
    let sb = sin(3.1416 * clamp(z / len, -0.4, 1.4));
    let bump = sb * sb;
    let w = mix(b.w0, b.w1, zc) * (1.0 - 0.1 * bump * (1.0 - 0.5 * tip));
    let ht = dk * w * (1.0 - 0.07 * bump);
    let hb = dk * w * (1.0 + 0.2 * bump);
    let x = dot(d, b.r);
    let yr = dot(d, b.u);
    let y = yr - 0.5 * (ht - hb);
    let hy = 0.5 * (ht + hb);
    // (its section a rounded box, flatter on its back than under; past its ends that section turned about the joint's
    // axis, so a bent joint is as round at its sides as the bone, not a spool standing out of it)
    let r2 = mix(0.97, 0.78, smoothstep(-0.5, 0.5, y / hy)) * dk * w;
    let dz = z - zc * len;
    let q = vec2<f32>(abs(x) - w + r2, abs(y) - hy + r2);
    let d2 = length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r2;
    let qh = vec2<f32>(q.x, length(vec2<f32>(y, dz)) - hy + r2);
    let hinge = length(max(qh, vec2<f32>(0.0))) + min(max(qh.x, qh.y), 0.0) - r2;
    var dist = hinge;
    if (tip > 0.5) {
        let round = length(vec2<f32>(max(d2 + rc, 0.0), dz)) - rc;
        dist = mix(hinge, round, smoothstep(0.3, 0.6, z / len));
        // (its nail: a plate set in its back, a little rounded across, its root round, a fold down each side)
        let xn = x / (0.62 * w);
        let cut = max(max(abs(x) - 0.62 * w, (0.34 + 0.1 * xn * xn) * b.len - z), ht - (0.025 + 0.06 * xn * xn) * w - yr);
        dist = max(dist, -cut);
    }
    return dist;
}
// One finger, one skin along it.
fn hd_finger_a(l: vec3<f32>, i: i32) -> f32 {
    let w = hd_fb[i * 3].w0;
    var d = hd_bone_a(l, hd_fb[i * 3], 0.84, 0.0);
    // (a joint's two bones end in the same round about its axis: joined so, no blend to swell it)
    d = hd_smin(d, hd_bone_a(l, hd_fb[i * 3 + 1], 0.84, 0.0), 0.02 * w);
    return hd_smin(d, hd_bone_a(l, hd_fb[i * 3 + 2], 0.82, 1.0), 0.02 * w);
}
// How far p is from the palm's outline seen from its back (negative inside): the wrist's two corners, the knuckles'
// line on its arc, straight down the little finger's edge.
fn hd_outline(p: vec2<f32>) -> f32 {
    let e = 2.6 * (1.0 - hd_cv);
    // (its corners drawn in 2.4 and the whole let out as much: round corners)
    var v = array<vec2<f32>, 6>(vec2<f32>(6.06, -24.6), vec2<f32>(10.76, 4.48 + e), vec2<f32>(3.68, 5.82 + e), vec2<f32>(-3.63, 3.26 + e), vec2<f32>(-11.01, 0.13 + e), vec2<f32>(-6.68, -24.6));
    var d = dot(p - v[0], p - v[0]);
    var sg = 1.0;
    var j = 5;
    for (var i = 0; i < 6; i = i + 1) {
        let e = v[j] - v[i];
        let w = p - v[i];
        let b = w - e * saturate(dot(w, e) / dot(e, e));
        d = min(d, dot(b, b));
        let c1 = p.y >= v[i].y;
        let c2 = p.y < v[j].y;
        let c3 = e.x * w.y > e.y * w.x;
        if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) {
            sg = -sg;
        }
        j = i;
    }
    return sg * sqrt(d) - 2.4;
}
// How high the back of the hand stands across it: its arch, highest over the middle finger's bone, falling to the
// little finger's (more as the fist closes).
fn hd_arch(x: f32) -> f32 {
    let u = saturate((-x - 1.0) / 11.0);
    let v = saturate((x - 5.0) / 8.0);
    let m = (x - 3.0) / 11.0;
    return 0.5 + 0.7 * (1.0 - min(m * m, 1.5)) - (2.2 + 1.7 * hd_cv) * u * u - 0.6 * v * v;
}
fn hd_hand_a(l: vec3<f32>) -> f32 {
    // (the palm's body: a slab its outline's shape, its back nearly flat, firm-edged, rounder under)
    let ar = hd_arch(l.x);
    // (to the wrist its back sinks, its edges rounding into the arm's: one skin over both, no step)
    let wz = smoothstep(-7.0, -25.0, l.z);
    let ys = l.y - ar + 0.5 + 0.25 * wz;
    let rb = select(4.1, mix(2.9, 4.2, wz), ys > 0.0);
    let qo = vec2<f32>(hd_outline(l.xz) + rb, abs(ys) - 4.3 + rb);
    var d = (length(max(qo, vec2<f32>(0.0))) + min(max(qo.x, qo.y), 0.0) - rb) * 0.94;
    for (var i = 0; i < 4; i = i + 1) {
        let kn = hd_kn[i];
        let kc = saturate(hd_h.fl[i]);
        // (the cord over its back to each knuckle, standing out a little)
        let x0 = kn.x * 0.36 + 0.5;
        let tr = 1.0 - 0.65 * kc;
        d = hd_smin(d, hd_cap(l, vec3<f32>(x0, 0.4 + hd_arch(x0), -24.0), vec3<f32>(kn.x, 3.25 + hd_arch(kn.x), kn.z - 2.4), 0.4 * tr, 1.0 * tr), 1.0);
        // (the knuckle's head: hard, standing out of the back, higher and further out as the finger bends over it;
        // four sizes: the middle finger's biggest, the little one's half; low domes, not balls)
        let ke = (l - kn.xyz - vec3<f32>(0.0, 0.8 + 1.4 * kc, 0.5 * kc)) * vec3<f32>(0.9, 1.25, 1.0);
        var kr = array<f32, 4>(3.05, 3.35, 2.7, 2.05);
        d = hd_smin(d, (length(ke) - kr[i]) * 0.8, 1.3);
    }
    // (the wrist's bones, the heel of the hand)
    let qc = vec3<f32>(abs(l.x) - 9.2 + 4.2, abs(l.y + 2.7) - 5.6 + 4.2, abs(l.z + 21.5) - 4.8 + 4.2);
    d = hd_smin(d, length(max(qc, vec3<f32>(0.0))) + min(max(qc.x, max(qc.y, qc.z)), 0.0) - 4.2, 3.2);
    // (the pad under the fingers' roots)
    let pd = hd_smin(hd_cap(l, vec3<f32>(-10.2, -2.0, 2.6), vec3<f32>(0.5, -2.4, 8.0), 2.8, 3.1), hd_cap(l, vec3<f32>(0.5, -2.4, 8.0), vec3<f32>(9.4, -2.2, 7.6), 3.1, 3.0), 2.0);
    d = hd_smin(d, pd, 3.8);
    if (hd_cv > 0.6) {
        let r = 4.0 * smoothstep(0.6, 0.95, hd_cv);
        d = hd_smin(d, hd_cap(l, vec3<f32>(-10.0, -8.0, -1.0), vec3<f32>(11.2, -9.0, 1.5), r, r), 2.0);
    }
    // (the thumb's mass, big, from the wrist to its first joint; the little finger's down the other edge)
    let tj0 = hd_fb[12].a;
    let tj1 = hd_fb[13].a;
    var th = hd_cap(l, tj0 + vec3<f32>(-2.2, -1.0, -1.5), mix(tj0, tj1, 0.82) + vec3<f32>(-1.6, -0.8, 0.0), 5.6, 4.4);
    let te = (l - mix(tj0, tj1, 0.36) - vec3<f32>(-4.6, -0.2, 1.8)) * vec3<f32>(1.0, 1.35, 0.78);
    th = hd_smin(th, (length(te) - 5.9) * 0.74, 3.0);
    d = hd_smin(d, th, 3.2);
    d = hd_smin(d, hd_cap(l, vec3<f32>(-7.7, -3.3 - 1.2 * hd_cv, -19.0), vec3<f32>(-10.6, -2.7 - 2.6 * hd_cv, -3.0), 4.9, 3.3 + 0.8 * hd_cv), 3.8);
    // (the web from the thumb's first joint to the palm's edge under the index finger: a thin taut sheet)
    d = hd_smin(d, hd_cap(l, mix(tj0, tj1, 0.8) + vec3<f32>(-0.6, 0.2, 0.0), vec3<f32>(11.2, -1.2, -2.5), 1.5, 1.9), 2.6);
    d = hd_smin(d, hd_cap(l, mix(tj0, tj1, 0.5) + vec3<f32>(-1.0, 1.2, 0.0), vec3<f32>(10.2, 1.3, -3.5), 3.4, 2.6), 3.2);
    // (the webs between the fingers' roots, thin, a third up their first bones)
    for (var i = 0; i < 3; i = i + 1) {
        let b0 = hd_fb[i * 3];
        let b1 = hd_fb[i * 3 + 3];
        let wa = b0.a + b0.f * b0.len * 0.3 - b0.u * 1.1;
        let wb = b1.a + b1.f * b1.len * 0.34 - b1.u * 1.1;
        d = hd_smin(d, hd_cap(l, wa, wb, 1.25, 1.25), 0.6);
    }
    var f = 1.0e9;
    for (var i = 0; i < 4; i = i + 1) {
        let fc = hd_fc[i];
        if (length(l - fc.xyz) - fc.w > min(f, d) + 3.0) {
            continue;
        }
        // (each grows out of the palm round its own knuckle only: past that it lies against the palm, the next finger
        // and the thumb with a crease between, never run into them)
        let kr = length(l - hd_kn[i].xyz);
        f = min(f, hd_smin(d, hd_finger_a(l, i), 0.3 + 1.5 * (1.0 - smoothstep(4.5, 9.5, kr))));
    }
    // (the thumb the same: out of its own mass at its root, then its own thing lying across the fingers)
    var t = hd_bone_a(l, hd_fb[12], 0.94, 0.0);
    t = hd_smin(t, hd_bone_a(l, hd_fb[13], 0.92, 0.0), 0.15);
    t = hd_smin(t, hd_bone_a(l, hd_fb[14], 0.82, 1.0), 0.15);
    let tr = hd_cap(l, tj0, tj1, 0.0, 0.0);
    return min(f, hd_smin(d, t, 0.3 + 1.6 * (1.0 - smoothstep(6.0, 11.0, tr))));
}
fn hd_arm_a(q: vec3<f32>) -> f32 {
    let sc = hd_h.sc;
    let v = q - hd_h.w;
    let s = dot(v, hd_ad);
    let c = clamp(s / hd_lf, 0.0, 1.0);
    let X = normalize(mix(hd_x0, hd_x1, c));
    let Y = cross(X, hd_ad);
    let ab = hd_fore_ab(c, sc);
    let bulge = smoothstep(0.2, 0.62, c) * (1.0 - smoothstep(0.8, 1.0, c));
    // (its flexors' belly under it to the little finger's side; all a little bowed, its back the bow's outside)
    let e = vec2<f32>(dot(v, X), dot(v, Y)) - vec2<f32>(-1.6 * hd_h.side, -2.6) * sc * bulge - vec2<f32>(0.0, 1.8 * sc * sin(3.1416 * c) - 1.5 * sc * (1.0 - smoothstep(0.0, 0.4, c)));
    // (an oval, flatter on its inner side, the palm's)
    let fl = select(1.0, 1.2, e.y < 0.0);
    let ef = vec2<f32>(e.x, e.y * fl);
    // (squarer at the wrist, its back as broad and flat as the hand's it runs into; round from a third up)
    let pe = mix(3.0, 2.0, smoothstep(0.0, 0.3, c));
    let en = abs(ef) / ab + vec2<f32>(1e-4);
    let en1 = pow(en, vec2<f32>(pe - 1.0));
    let k0 = max(pow(dot(en1, en), 1.0 / pe), 1e-3);
    var d = (k0 - 1.0) / max(pow(k0, 1.0 - pe) * length(en1 / ab), 1e-5) / fl;
    d = -hd_smin(-d, -max(-s - 4.0 * sc, s - hd_lf - 2.0 * sc), 5.0 * sc);
    // (the ridge of muscle down the thumb's side; the bone's edge from the wrist's knob to the elbow's point)
    d = hd_smin(d, hd_cap(q, hd_r0, hd_r1, 1.6 * sc, 6.8 * sc), 4.0 * sc);
    let ep = hd_h.el + hd_ue * 4.0 * sc;
    // (the ulna's end a hard knob on the back of the wrist, its edge on down to the elbow's point; the radius's end on
    // the thumb's side)
    d = hd_smin(d, length(q - hd_uh) - 2.5 * sc, 2.5 * sc);
    d = hd_smin(d, hd_cap(q, hd_uh, ep + Y * 6.0 * sc - X * hd_h.side * 3.0 * sc, 1.3 * sc, 4.5 * sc), 2.6 * sc);
    d = hd_smin(d, length(q - hd_h.w - hd_ad * 1.2 * sc - hd_x0 * hd_h.side * 7.6 * sc) - 2.1 * sc, 2.6 * sc);
    d = hd_smin(d, length(q - ep) - 9.6 * sc, 4.5 * sc);
    return hd_smin(d, hd_cap(q, hd_h.el, hd_h.sh, 13.0 * sc, 15.5 * sc), 6.0 * sc);
}
// ---- the hand as sculpted
// A sculpted arm (MakeHuman's base mesh, CC0) cut at its joints into rigid pieces, each baked into a small grid of
// distances in its bone's frame (`tools/bake_hand.py`; in the mod's data from HB, ten bits a sample, three a word along
// x), read where its bone is now (`hd_set`: one pose drives both hands). Pieces 0 to 11 the fingers' bones (index to
// little, three each), 12 to 14 the thumb's, 15 the palm (the hand's frame), 16 the forearm (from the wrist, z back
// along it, a grid 96 long whatever the pose's forearm), 17 the upper arm (from the elbow).
// [bake table] (written by tools/bake_hand.py from the sculpted mesh: rerun it, don't edit this)
const HB_WORDS: u32 = 95133u;
const HB_LO: f32 = -5.0;
const HB_STEP: f32 = 0.01173021;
const HB_UZ: f32 = -57.000; // (the upper arm's grid ends here: past it the arm runs on as there)
const HB_FZ: f32 = 7.600; // (and the forearm's, past the wrist)
const HB_RAD: array<f32, 15> = array<f32, 15>(4.84, 3.91, 3.32, 5.00, 4.05, 3.58, 4.72, 4.05, 3.17, 4.34, 3.60, 2.88, 8.85, 6.44, 3.91); // (how far each bone's piece reaches from its line)
const HB_PLO: vec3<f32> = vec3<f32>(-14.00, -13.00, -37.50); // (the box round the palm)
const HB_PHI: vec3<f32> = vec3<f32>(17.20, 6.50, 12.60);
const HB_RF: f32 = 23.33; // (how far the forearm, and the upper arm, reach from their line)
const HB_RU: f32 = 20.00;
fn hb_piece(id: i32, p: vec3<f32>) -> f32 {
    switch id {
        case 0 { return hb_grid(p, 4u, vec3<i32>(17, 18, 40), vec3<f32>(-5.1, -5.4, -4.8), vec3<f32>(1.666667, 1.666667, 1.666667), 1.231); }
        case 1 { return hb_grid(p, 4324u, vec3<i32>(18, 17, 31), vec3<f32>(-4.9, -4.85, -4.3), vec3<f32>(1.818182, 1.818182, 1.818182), 1.072); }
        case 2 { return hb_grid(p, 7486u, vec3<i32>(18, 18, 27), vec3<f32>(-3.75, -3.8, -3.8), vec3<f32>(2.222222, 2.222222, 2.222222), 1.055); }
        case 3 { return hb_grid(p, 10402u, vec3<i32>(18, 19, 45), vec3<f32>(-5.1, -5.4, -5.4), vec3<f32>(1.666667, 1.666667, 1.666667), 1.087); }
        case 4 { return hb_grid(p, 15532u, vec3<i32>(18, 17, 35), vec3<f32>(-4.35, -4.3, -4.85), vec3<f32>(1.818182, 1.818182, 1.818182), 1.242); }
        case 5 { return hb_grid(p, 19102u, vec3<i32>(19, 18, 29), vec3<f32>(-3.75, -3.8, -3.8), vec3<f32>(2.222222, 2.222222, 2.222222), 1.051); }
        case 6 { return hb_grid(p, 22756u, vec3<i32>(18, 18, 42), vec3<f32>(-5.1, -5.4, -4.8), vec3<f32>(1.666667, 1.666667, 1.666667), 1.262); }
        case 7 { return hb_grid(p, 27292u, vec3<i32>(17, 15, 32), vec3<f32>(-4.35, -3.75, -4.3), vec3<f32>(1.818182, 1.818182, 1.818182), 1.100); }
        case 8 { return hb_grid(p, 30172u, vec3<i32>(18, 18, 29), vec3<f32>(-3.75, -3.8, -3.8), vec3<f32>(2.222222, 2.222222, 2.222222), 1.203); }
        case 9 { return hb_grid(p, 33304u, vec3<i32>(16, 16, 34), vec3<f32>(-3.9, -4.8, -3.6), vec3<f32>(1.666667, 1.666667, 1.666667), 1.278); }
        case 10 { return hb_grid(p, 36568u, vec3<i32>(17, 15, 28), vec3<f32>(-3.8, -3.75, -4.3), vec3<f32>(1.818182, 1.818182, 1.818182), 1.074); }
        case 11 { return hb_grid(p, 39088u, vec3<i32>(17, 16, 24), vec3<f32>(-3.75, -3.35, -3.35), vec3<f32>(2.222222, 2.222222, 2.222222), 1.166); }
        case 12 { return hb_grid(p, 41392u, vec3<i32>(25, 24, 46), vec3<f32>(-10.5, -9.0, -9.75), vec3<f32>(1.333333, 1.333333, 1.333333), 1.978); }
        case 13 { return hb_grid(p, 51328u, vec3<i32>(21, 19, 37), vec3<f32>(-7.1, -5.9, -6.0), vec3<f32>(1.666667, 1.666667, 1.666667), 1.288); }
        case 14 { return hb_grid(p, 56249u, vec3<i32>(18, 18, 30), vec3<f32>(-4.5, -4.5, -4.5), vec3<f32>(2.000000, 2.000000, 2.000000), 1.128); }
        case 15 { return hb_grid(p, 59489u, vec3<i32>(40, 28, 59), vec3<f32>(-16.4, -15.4, -37.2), vec3<f32>(1.111111, 1.111111, 1.111111), 2.080); }
        case 16 { return hb_grid(p, 82617u, vec3<i32>(23, 21, 52), vec3<f32>(-13.2, -16.4, -112.4), vec3<f32>(0.625000, 0.625000, 0.416667), 2.266); }
        case 17 { return hb_grid(p, 91353u, vec3<i32>(20, 20, 27), vec3<f32>(-20.0, -20.0, -60.0), vec3<f32>(0.500000, 0.500000, 0.333333), 2.510); }
        default { return 1.0e9; }
    }
}
// [end bake table]
var<private> hb_on: bool = false;  // (this pixel draws the sculpted one: hd_set)
var<private> hb_df: f32;               // (the forearm's distance, how far past the wrist: hd_arm_b)
var<private> hb_zw: f32;
// Two samples of a row of a grid, between them.
fn hb_row(r: u32, ix: i32, fx: f32) -> f32 {
    let w0 = mod_data[r + u32(ix / 3)];
    let w1 = mod_data[r + u32((ix + 1) / 3)];
    let a = f32((w0 >> u32(10 * (ix % 3))) & 1023u);
    let b = f32((w1 >> u32(10 * ((ix + 1) % 3))) & 1023u);
    return mix(a, b, fx);
}
// A grid's distance at p (its frame): `off` its words, `n` its samples, `bmin` its first, `inv` samples to a unit,
// `mrg` the least between its surface and its sides. Outside it, never more than true: its side's distance left and the
// way out to p at right angles (its surface is all inside); far out, the way alone.
fn hb_grid(p: vec3<f32>, off: u32, n: vec3<i32>, bmin: vec3<f32>, inv: vec3<f32>, mrg: f32) -> f32 {
    let g = (p - bmin) * inv;
    let gc = clamp(g, vec3<f32>(0.0), vec3<f32>(n - vec3<i32>(1)) - vec3<f32>(0.001));
    let out = length((g - gc) / inv);
    if (out > 2.0) {
        return out + mrg;
    }
    let i = vec3<i32>(gc);
    let f = gc - vec3<f32>(i);
    let nxw = (n.x + 2) / 3;
    let r = HB + off + u32((i.z * n.y + i.y) * nxw);
    let ry = u32(nxw);
    let rz = u32(n.y * nxw);
    let v = mix(mix(hb_row(r, i.x, f.x), hb_row(r + ry, i.x, f.x), f.y), mix(hb_row(r + rz, i.x, f.x), hb_row(r + rz + ry, i.x, f.x), f.y), f.z);
    let d = HB_LO + HB_STEP * v;
    if (out <= 0.0) {
        return d;
    }
    let dd = mix(d, min(d, mrg), out * 0.5);
    return sqrt(max(dd, 0.0) * max(dd, 0.0) + out * out + 2.0 * out * mrg) + min(dd, 0.0);
}
// The piece on bone k at l (the hand's own frame).
fn hb_bone(l: vec3<f32>, k: i32) -> f32 {
    let b = hd_fb[k];
    let v = l - b.a;
    let q = vec3<f32>(dot(v, b.r), dot(v, b.u), dot(v, b.f));
    let d = hb_piece(k, q);
    return d;
}
// The sculpted hand at l (its frame, its bones' units), with the forearm (`hb_df`, from hd_arm_b).
fn hd_hand_b(l: vec3<f32>) -> f32 {
    // (palm and forearm one surface, both holding the wrist as sculpted, the palm's grid a hand's width down the arm, the
    // forearm's a little into the hand; one to the other across the wrist: nothing shows there straight, and bent the
    // skin goes over smoothly)
    var d = hb_df / hd_h.sc;
    let wz = smoothstep(-33.0, -21.0, l.z);
    if (wz > 0.0) {
        // (closing, the palm's back arches with the knuckles `hd_set` sinks: the ring and little fingers' side)
        var pl = l;
        pl.y = pl.y + hd_cv * (0.7 * saturate(-l.x / 3.9) + saturate((-l.x - 3.9) / 7.1)) * smoothstep(-22.0, -4.0, l.z);
        let dp = hb_piece(15, pl);
        d = mix(d, dp, wz);
    }
    var f = d;
    for (var i = 0; i < 4; i = i + 1) {
        // (only near a finger its pieces: the ball round it)
        let c = hd_fc[i];
        if (length(l - c.xyz) - c.w > f + 0.7) {
            continue;
        }
        let p0 = hb_bone(l, i * 3);
        let p1 = hb_bone(l, i * 3 + 1);
        let p2 = hb_bone(l, i * 3 + 2);
        // (a finger's joints run into each other, its root into the palm; never a finger into its neighbour or the
        // thumb)
        let bend = saturate(hd_h.fl[i]);
        var g = min(hd_smin(p0, p1, 0.12 + 0.2 * bend), hd_smin(p1, p2, 0.12 + 0.15 * bend));
        // (shut, its end pressed on its own root and the palm: the flesh between closes up, no hollow through the fist)
        let pr = 4.5 * smoothstep(0.55, 1.0, bend) + 0.01;
        g = min(g, hd_smin(p0, p2, pr));
        f = min(f, min(hd_smin(d, p0, 0.2 + 0.4 * bend), min(g, hd_smin(d, min(p1, p2), 0.55 * pr))));
    }
    if (length(l - hd_tc.xyz) - hd_tc.w > f + 1.3) {
        return f;
    }
    let t0 = hb_bone(l, 12);
    let t1 = hb_bone(l, 13);
    let t2 = hb_bone(l, 14);
    let t = min(hd_smin(t0, t1, 0.25), hd_smin(t1, t2, 0.2));
    return min(f, min(hd_smin(d, t0, 0.4 + 1.8 * saturate(hd_h.th)), t));
}
// The sculpted upper arm at q (the world); the forearm's distance into `hb_df` (past the wrist running on as there:
// `hd_hand_b` takes it over), how far past the wrist into `hb_zw`.
fn hd_arm_b(q: vec3<f32>) -> f32 {
    let sc = hd_h.sc;
    // (the forearm: its frame the wrist's, its grid's length drawn out to the pose's)
    let v = (q - hd_h.w) / sc;
    let y0 = cross(hd_x0, hd_ad);
    let zs = 96.0 * sc / hd_lf;
    let pf = vec3<f32>(dot(v, hd_x0) * hd_h.side, dot(v, y0), min(-dot(v, hd_ad) * zs, HB_FZ));
    let df = hb_piece(16, pf) * min(1.0, 1.0 / zs);
    hb_df = df * sc;
    hb_zw = -dot(v, hd_ad) * sc;
    // (the upper arm: the forearm's frame turned the short way to the shoulder's; past its grid's end running on as
    // there, to a little past the shoulder)
    let a = hd_ad;
    let b = -hd_ue;
    let k = 1.0 / max(1.0 + dot(a, b), 0.05);
    let x1 = hd_x0 - (a + b) * (dot(a + b, hd_x0) * k) + 2.0 * b * dot(a, hd_x0);
    let y1 = y0 - (a + b) * (dot(a + b, y0) * k) + 2.0 * b * dot(a, y0);
    let w = (q - hd_h.el) / sc;
    let zu = dot(w, hd_ue);
    let pu = vec3<f32>(dot(w, x1) * hd_h.side, dot(w, y1), max(zu, HB_UZ));
    let du = max(hb_piece(17, pu), -zu - length(hd_h.sh - hd_h.el) / sc - 4.0);
    return du * sc;
}
fn hd_map_b(q: vec3<f32>) -> f32 {
    let sc = hd_h.sc;
    let du = hd_arm_b(q);
    // (away from the hand, the arm alone: its forearm ending a little past the wrist, in the hand)
    let m = hd_smin(max(hb_df, hb_zw - 10.0 * sc), du, 1.2 * sc);
    let dq = q - hd_h.p;
    // (its pieces only near the hand: a ball round it, then the box round it in its frame)
    let hb = length(dq - hd_h.az * 12.0 * sc) - 52.0 * sc;
    if (hb > m) {
        return m;
    }
    if (hb > 4.0 * sc) {
        return min(m, hb);
    }
    let l = vec3<f32>(dot(dq, hd_h.ax) * hd_h.side, dot(dq, hd_h.ay), dot(dq, hd_h.az)) / sc;
    let qb = abs(l - hd_bc) - hd_bh;
    let db = length(max(qb, vec3<f32>(0.0))) + min(max(qb.x, max(qb.y, qb.z)), 0.0);
    // (outside the box, the distance to the box is enough; not just under it, down the arm, where the hand is the
    // forearm: the box's face is no skin there, and its light and self-shadow, asking the distance well off its skin,
    // would take the air by the arm for near the hand and draw a dark line round the wrist)
    if (db > 1.5 && (l.z > hd_bc.z - hd_bh.z || db > 8.0)) {
        return min(db * sc, m);
    }
    return hd_smin(hd_hand_b(l) * sc, du, 1.2 * sc);
}
// How far q is from the hand and its arm (the pose hd_set last set).
fn hd_map(q: vec3<f32>) -> f32 {
    if (hb_on) {
        return hd_map_b(q);
    }
    let m = hd_arm_a(q);
    let dq = q - hd_h.p;
    // (only near the hand its bones: a ball round it)
    let hb = length(dq - hd_h.az * 12.0 * hd_h.sc) - 52.0 * hd_h.sc;
    if (hb > m) {
        return m;
    }
    if (hb > 4.0 * hd_h.sc) {
        return min(m, hb);
    }
    let l = vec3<f32>(dot(dq, hd_h.ax) * hd_h.side, dot(dq, hd_h.ay), dot(dq, hd_h.az)) / hd_h.sc;
    // (outside the box round the hand, the distance to it is enough, less what blending it into the arm takes off)
    let qb = abs(l - hd_bc) - hd_bh;
    let db = length(max(qb, vec3<f32>(0.0))) + min(max(qb.x, max(qb.y, qb.z)), 0.0);
    // (so the arm is itself right up to where the hand's blend with it begins: no cuff round it)
    if (db > 2.6) {
        return min(db * hd_h.sc, m);
    }
    return hd_smin(hd_hand_a(l) * hd_h.sc, m, 0.9 * hd_h.sc);
}
// Where a ray (ro, rd) comes nearest a segment: (its t, how near).
fn hd_near_seg(ro: vec3<f32>, rd: vec3<f32>, pa: vec3<f32>, pb: vec3<f32>) -> vec2<f32> {
    let ba = pb - pa;
    let oa = ro - pa;
    let baba = dot(ba, ba);
    let bard = dot(ba, rd);
    let den = baba - bard * bard;
    var s = 0.5;
    if (den > 1e-6) {
        s = saturate((dot(ba, oa) - bard * dot(rd, oa)) / den);
    }
    let t = max(bard * s - dot(rd, oa), 0.0);
    return vec2<f32>(t, length(ro + rd * t - pa - ba * s));
}
// The part of a ray within `ra` of a segment: (t0, t1), or t1 < t0.
fn hd_seg_span(ro: vec3<f32>, rd: vec3<f32>, pa: vec3<f32>, pb: vec3<f32>, ra: f32) -> vec2<f32> {
    let na = hd_near_seg(ro, rd, pa, pb);
    if (na.y >= ra) {
        return vec2<f32>(1.0e9, -1.0);
    }
    let ax = normalize(pb - pa);
    let sn = sqrt(max(1.0 - dot(ax, rd) * dot(ax, rd), 1e-6));
    let half = min(sqrt(ra * ra - na.y * na.y) / sn, length(pb - pa)) + ra;
    return vec2<f32>(max(na.x - half, 0.0), na.x + half);
}
struct HdHit {
    t: f32,       // how far along the ray (or where it came nearest)
    op: f32,      // how much of what is behind it it hides
    c: vec3<f32>, // its light (added)
}
// How far l (its frame) is from the nearest crease across a joint: the fingers' and thumb's joints, the knuckles, the
// wrist (its bones' units).
fn hd_crease(l: vec3<f32>) -> vec3<f32> {
    var best = vec3<f32>(1.0e3, 0.0, 1.0);
    for (var k = 0; k < 10; k = k + 1) {
        // (the fingers' middle and end joints, the thumb's two)
        let j = select(k + k / 2 + 1, 13 + k - 8, k > 7);
        let bn = hd_fb[j];
        let pv = hd_fb[j - 1];
        let dl = l - bn.a;
        if (dot(dl, dl) < 4.0 * bn.w0 * bn.w0) {
            let dd = abs(dot(dl, normalize(pv.f + bn.f)));
            if (dd < best.x) {
                best = vec3<f32>(dd, dot(dl, normalize(pv.u + bn.u)) / bn.w0, dot(pv.f, bn.f));
            }
        }
    }
    return best;
}
// How much of a nail is at l (the plates let into the backs of the fingers' and thumb's ends by hd_bone_a).
fn hd_nail(l: vec3<f32>) -> f32 {
    var m = 0.0;
    for (var k = 0; k < 5; k = k + 1) {
        let b = hd_fb[k * 3 + 2];
        let dl = l - b.a;
        let z = dot(dl, b.f);
        let w = mix(b.w0, b.w1, saturate(z / b.len));
        let xn = dot(dl, b.r) / (0.62 * w);
        m = max(m, saturate((1.0 - abs(xn)) * 6.0) * saturate((z - (0.34 + 0.1 * xn * xn) * b.len) * 3.0) * step(0.4 * w, dot(dl, b.u)) * step(z, b.len * 1.1));
    }
    return m;
}
fn hd_seg2(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let e = b - a;
    let w = p - a;
    return length(w - e * saturate(dot(w, e) / dot(e, e)));
}
// A mote in the dark inside it: one to a cell of q, most empty; r its size (of a cell).
fn hd_mote(q: vec3<f32>, r: f32) -> f32 {
    let i = floor(q);
    let hh = hd_h3(hash31(i) * 7.31 + 0.137);
    if (hh.x < 0.1) {
        return 0.0;
    }
    let d = length(q - i - 0.5 - hh * (0.9 - 2.0 * r));
    return (1.0 - smoothstep(0.0, r, d)) * (0.4 + 1.5 * (hh.x - 0.1));
}
fn hd_h3(x: f32) -> vec3<f32> {
    return vec3<f32>(fract(x * 127.1), fract(x * 311.7), fract(x * 74.7)) - 0.5;
}
// The hand along the ray (ro, rd) out to `far`.
// How far apart its normal's four taps are at p (blocks): the sculpted hand's as its grids' samples, so its faces are
// smooth, not flat to a sample (the forearm's and upper arm's coarser).
fn hd_ne(p: vec3<f32>) -> f32 {
    if (!hb_on) {
        return 0.25;
    }
    let z = dot(p - hd_h.p, hd_h.az) / hd_h.sc;
    return hd_h.sc * mix(0.45, 1.0, smoothstep(-26.0, -36.0, z));
}
fn hd_trace(ro: vec3<f32>, rd: vec3<f32>, t: f32, px_a: f32, far: f32, sunc: vec3<f32>, L: vec3<f32>, skyl: vec3<f32>, amb: vec3<f32>) -> HdHit {
    var out = HdHit(1.0e9, 0.0, vec3<f32>(0.0));
    let h = hd_pose(t);
    if (h.k <= 0.001) {
        return out;
    }
    // (only rays coming near it: a ball round the hand, its forearm and upper arm; then, for the hand, the box round it
    // in its frame)
    let hc = h.p + h.az * 12.0 * h.sc;
    let oc = ro - hc;
    let bq = dot(oc, rd);
    let rr = 56.0 * h.sc;
    let disc = bq * bq - (dot(oc, oc) - rr * rr);
    // (the sculpted arm's reach is its own: wider at the elbow)
    let bk = HD_BAKE && arrayLength(&mod_data) >= HB + HB_WORDS;
    let sf = hd_seg_span(ro, rd, h.w, h.el, select(23.5, HB_RF + 1.0, bk) * h.sc);
    let su = hd_seg_span(ro, rd, h.el, h.sh, select(18.0, HB_RU + 1.0, bk) * h.sc);
    if (disc <= 0.0 && sf.y < sf.x && su.y < su.x) {
        return out;
    }
    hd_set(h);
    var t0 = 1.0e9;
    var t1 = -1.0;
    if (disc > 0.0) {
        let lo3 = vec3<f32>(dot(ro - h.p, h.ax) * h.side, dot(ro - h.p, h.ay), dot(ro - h.p, h.az)) / h.sc;
        let ld3 = vec3<f32>(dot(rd, h.ax) * h.side, dot(rd, h.ay), dot(rd, h.az));
        let inv = 1.0 / select(ld3, vec3<f32>(1e-6), abs(ld3) < vec3<f32>(1e-6));
        let ta = (hd_bc - hd_bh - 3.0 - lo3) * inv;
        let tb = (hd_bc + hd_bh + 3.0 - lo3) * inv;
        let b0 = max(max(max(min(ta.x, tb.x), min(ta.y, tb.y)), min(ta.z, tb.z)), 0.0) * h.sc;
        let b1 = min(min(max(ta.x, tb.x), max(ta.y, tb.y)), max(ta.z, tb.z)) * h.sc;
        if (b1 >= b0) {
            t0 = b0;
            t1 = b1;
        }
    }
    t0 = min(t0, min(sf.x, su.x));
    t1 = max(t1, max(sf.y, su.y));
    t1 = min(t1, far);
    if (t1 <= t0) {
        return out;
    }
    // (one loop, one place it is measured, so the pass holds its long distance function once: marching to it, closing
    // in on where the ray entered, its normal, how thick it is along the ray)
    var s = t0;
    var hit = false;
    var dmin = 1.0e9;
    var smin_t = t0;
    var dh = 0.0;
    var sp = s;
    var phase = 0;
    var j = 0;
    var lo = 0.0;
    var hi = 0.0;
    var eh = 0.0;
    var p = ro;
    var e = 0.0;
    var nacc = vec3<f32>(0.0);
    var dk = vec3<f32>(0.0);
    var din = 0.0;
    var tr = 0.3;
    var t_in = -1.0;
    var out_of_it = false;
    let pxw0 = px_a;
    for (var i = 0; i < 150; i = i + 1) {
        if (phase == 0 && (s > t1 || i >= 80)) {
            // (out of steps, or past it: a ray grazing it is on it)
            let pxw = max(smin_t * pxw0, 0.05);
            if (dmin < max(pxw, 0.6) && s <= t1) {
                hit = true;
                s = smin_t;
                dh = max(dmin, 0.0);
                p = ro + rd * s;
                e = max(hd_ne(p), s * px_a);
                phase = 2;
                j = 0;
            } else {
                break;
            }
        }
        var q = ro + rd * s;
        if (phase == 1) {
            q = ro + rd * (0.5 * (lo + hi));
        } else if (phase == 2) {
            dk = select(select(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(-1.0, 1.0, -1.0), j == 2), select(vec3<f32>(-1.0, -1.0, 1.0), vec3<f32>(1.0, -1.0, -1.0), j == 0), j < 2);
            q = p + dk * e;
        } else if (phase == 3) {
            q = p + rd * (din + tr);
        }
        let d = hd_map(q);
        if (phase == 0) {
            if (d < dmin) {
                dmin = d;
                smin_t = s;
            }
            let eps = max(0.04, s * px_a * 0.8);
            if (d < eps) {
                hit = true;
                dh = d;
                if (d < 0.0) {
                    // (a long stride may have gone past its face: back to it, halving)
                    lo = sp;
                    hi = s;
                    eh = eps;
                    phase = 1;
                    j = 0;
                } else {
                    p = ro + rd * s;
                    e = max(hd_ne(p), s * px_a);
                    phase = 2;
                    j = 0;
                }
                continue;
            }
            sp = s;
            s = s + max(d * 0.9, max(eps * 0.6, s * 0.005));
        } else if (phase == 1) {
            let m = 0.5 * (lo + hi);
            if (d > eh) {
                lo = m;
            } else {
                hi = m;
            }
            j = j + 1;
            if (j == 5) {
                s = hi;
                dh = 0.0;
                p = ro + rd * s;
                e = max(hd_ne(p), s * px_a);
                phase = 2;
                j = 0;
            }
        } else if (phase == 2) {
            nacc = nacc + dk * d;
            j = j + 1;
            if (j == 4) {
                din = max(dh, 0.0);
                phase = 3;
                j = 0;
            }
        } else {
            if (d > 0.0) {
                if (t_in >= 0.0) {
                    tr = max(tr - d, t_in + 0.3);
                    out_of_it = true;
                    break;
                }
                tr = tr + max(d * 1.5, 0.4);
            } else {
                if (t_in < 0.0) {
                    t_in = tr;
                }
                tr = tr + max(-d * 1.2, 1.5 * h.sc + (tr - t_in) * 0.5);
            }
            j = j + 1;
            if (j == 4) {
                break;
            }
        }
    }
    if (!hit) {
        // (its very edge, a pixel across: smooth)
        let pxw = max(smin_t * px_a, 0.05);
        let cov = saturate(1.0 - dmin / pxw) * h.k;
        if (dmin > 30.0 || cov <= 0.0) {
            return out;
        }
        out.t = smin_t;
        let pe = ro + rd * smin_t;
        out.op = cov * 0.6;
        out.c = vec3<f32>(0.3, 0.215, 0.205) * (sunc * 0.35 + amb * 0.7 + skyl * 0.5) * (1.0 - 0.5 * HD_DM) * out.op;
        return out;
    }
    let n = normalize(nacc + vec3<f32>(0.0, 1e-6, 0.0));
    var th = 0.3;
    if (t_in >= 0.0) {
        th = tr - t_in + select(40.0 * h.sc, 0.0, out_of_it);
    }
    // (where on it: its frame, and how far up its arm into the dark: past the glass, and up the upper arm)
    let d0 = p - h.p;
    let lp = vec3<f32>(dot(d0, h.ax) * h.side, dot(d0, h.ay), dot(d0, h.az)) / h.sc;
    let ua = h.sh - h.el;
    let up_arm = saturate(dot(p - h.el, ua) / max(dot(ua, ua), 1.0));
    let in_arm = lp.z < -24.0;
    let fade = max(smoothstep(0.0, 0.85, up_arm) * select(0.0, 1.0, in_arm), smoothstep(SB_H + 10.0, SB_H + 260.0, p.y));
    var c = vec3<f32>(0.0);
    var op = 1.0;
    // ---- the eye's own skin (sb_eye's lids: the same flesh, mottled, veined, creased across its joints); past
    // the sky lit only by what comes in through the hole, falling away into the dark
    let sd = seed_v();
    let q2 = lp.xz / 30.0 + lp.y * vec2<f32>(0.011, 0.017);
    let pxl = s * px_a / h.sc;
    let fine = saturate(1.0 - pxl * 2.5);
    // (mottled as the eye's lids, its grain fine)
    var alb = vec3<f32>(0.3, 0.215, 0.205) * (0.76 + 0.48 * gnoise2(q2 * 7.0 + vec2<f32>(sd, 0.0))) * (0.88 + 0.24 * gnoise2(q2 * 26.0)) * (1.0 + 0.1 * fine * (gnoise2(q2 * 90.0) - 0.5));
    var nail = 0.0;
    // (the creases across its joints, the skin round them redder)
    if (!in_arm) {
        // (the fold under each joint; three fine wrinkles across its back while straight; the palm's three lines)
        let cr = hd_crease(lp);
        let fold = (1.0 - smoothstep(0.03, 0.3 + pxl, cr.x)) * saturate(-cr.y * 2.0) * saturate(1.0 - pxl * 0.5);
        let wk = pow(0.5 + 0.5 * cos(cr.x * 14.0), 5.0) * (1.0 - smoothstep(0.7, 1.4, cr.x)) * saturate(cr.y * 2.0) * smoothstep(0.7, 0.97, cr.z) * saturate(1.0 - pxl * 4.0);
        let pq = lp.xz;
        let pl = min(min(hd_seg2(pq, vec2<f32>(-12.5, -0.5), vec2<f32>(3.0, 4.2)), hd_seg2(pq, vec2<f32>(11.5, -1.5), vec2<f32>(-7.5, -8.5))), min(hd_seg2(pq, vec2<f32>(10.5, -2.0), vec2<f32>(3.8, -9.5)), hd_seg2(pq, vec2<f32>(3.8, -9.5), vec2<f32>(2.0, -21.0))));
        let palm = (1.0 - smoothstep(0.05, 0.35 + pxl, pl)) * saturate(-dot(n, h.ay) * 2.0 - 0.6) * step(-11.0, lp.y) * (1.0 - smoothstep(0.5, 0.9, hd_cv)) * saturate(1.0 - pxl * 0.7);
        alb = alb * (1.0 - 0.3 * fold - 0.2 * wk - 0.22 * palm);
        nail = hd_nail(lp) * saturate(1.0 - pxl);
        alb = mix(alb, alb * 1.2 + vec3<f32>(0.05, 0.035, 0.035), 0.75 * nail);
    }
    // (dark where its parts lie against each other: the creases between fingers, under the thumb)
    let ao = mix(0.16, 1.0, pow(saturate(hd_map(p + n * 2.4 * h.sc) / (2.4 * h.sc)), 1.4));
    // (and wider: its palm's hollow, its fist's inside; then its shadow on itself, firm-edged)
    let ao2 = mix(0.35, 1.0, saturate(hd_map(p + n * 6.0 * h.sc) / (6.0 * h.sc)));
    var Ls = L;
    if (HD_CLAY) {
        let cs = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)));
        Ls = normalize(-rd * 0.55 - cs * 0.62 + cross(cs, rd) * 0.56);
    }
    var shd = 1.0;
    var st = 2.5 * h.sc;
    for (var k = 0; k < HD_SHADOW; k = k + 1) {
        let dd = hd_map(p + n * 1.2 * h.sc + Ls * st);
        shd = min(shd, saturate(dd / (0.07 * st) + 0.35));
        st = st + max(dd, 0.8 * h.sc);
    }
    var dmi = 0.0;
    // (the dark in it, HD_DM of it: dark veins under the skin along it, soft, thinning to nothing)
    if (HD_DM > 0.0) {
        let vq = vec2<f32>((lp.x + 0.5 * lp.y) / 7.0, lp.z / 30.0);
        let vn = abs(gnoise2(vq + vec2<f32>(sd, 3.0)) - 0.5 + 0.3 * (gnoise2(vq * 2.3 + vec2<f32>(7.0, sd)) - 0.5));
        // (up its arm, its wrist and its hand's back to the knuckles; a soft dark round each under the skin)
        let vm = (1.0 - smoothstep(10.0, 22.0, lp.z)) * smoothstep(0.22, 0.55, gnoise2(vq * 0.7 + vec2<f32>(11.0, sd))) * saturate(0.9 + dot(n, h.ay));
        let vein = (1.0 - smoothstep(0.0, 0.006 + 0.05 * vm + pxl * 0.02, vn)) * saturate(1.0 - pxl * 0.3) * vm;
        // (slow patches where the skin thins and the dark shows through, larger up the arm)
        let pt = smoothstep(0.48 - 0.14 * saturate(-lp.z / 60.0), 0.8, gnoise2(vec2<f32>(lp.x / 9.0 + lp.y / 14.0, lp.z / 16.0) + vec2<f32>(sd * 1.7, 5.0)));
        dmi = saturate(0.6 * vein + 0.55 * (1.0 - smoothstep(0.0, 0.2 + pxl * 0.03, vn)) * vm + 0.6 * pt);
        alb = mix(alb, vec3<f32>(0.035, 0.03, 0.075), min(HD_DM * 1.3, 0.85) * vein);
    }
    let bmp = (gnoise2(q2 * 60.0 + vec2<f32>(3.0, sd)) - 0.5) * h.ax + (gnoise2(q2 * 60.0 + vec2<f32>(sd, 7.0)) - 0.5) * h.az;
    let nb = normalize(n + bmp * 0.1 * fine * (1.0 - nail));
    let hv = normalize(L - rd);
    let wrap = saturate(dot(nb, L) * 0.92 + 0.08) * shd;
    c = alb * (sunc * wrap * (0.4 + 0.6 * ao) + (amb * 0.7 + skyl * 0.5) * (0.55 + 0.45 * nb.y) * ao * ao2);
    // (the light through its thin edges, red; a dull shine on it)
    c = c + alb * vec3<f32>(1.0, 0.3, 0.2) * sunc * exp(-th / (1.4 * h.sc)) * saturate(0.3 - dot(n, L)) * 0.3;
    c = c + sunc * pow(saturate(dot(nb, hv)), 34.0) * 0.2 * (1.0 + 2.0 * nail) * ao * shd + skyl * pow(1.0 - saturate(-dot(nb, rd)), 4.0) * 0.12 * ao * ao2;
    var dkm = 0.0;
    if (HD_DM > 0.0) {
        // (it swallows light turned from the sun, folded, thick, or through the skin (dmi), in sun too)
        let ndv = saturate(-dot(n, rd));
        let shade = 1.0 - smoothstep(-0.3, 0.45, dot(n, L));
        let thick = 1.0 - exp(-th / (14.0 * h.sc));
        let dark = saturate(HD_DM * (1.15 * shade + 1.3 * (1.0 - ao) + 0.6 * (1.0 - ao2) + 0.3 * thick + 1.1 * dmi));
        let glow = 0.25 + 0.75 * saturate(length(skyl + sunc * 0.3));
        dkm = dark;
        c = mix(c * (1.0 - 0.15 * HD_DM), vec3<f32>(0.008, 0.007, 0.018) * glow, 0.95 * dark);
        // (in that dark, deep under the skin: a dim cloud, and motes drifting slowly, deeper the further from square
        // on they are seen)
        let vl = vec3<f32>(dot(rd, h.ax) * h.side, dot(rd, h.ay), dot(rd, h.az));
        let q0 = lp + vl * 4.0;
        let neb = gnoise2(q0.xz / 14.0 + vec2<f32>(q0.y * 0.07 + t * 0.012, sd)) * gnoise2(q0.zy / 9.0 + vec2<f32>(sd, q0.x * 0.08 - t * 0.009));
        var deep = vec3<f32>(0.05, 0.032, 0.14) * smoothstep(0.15, 0.6, neb) * 0.12;
        let mr = clamp(0.1 + pxl * 0.45, 0.1, 0.4);
        let mk = 0.01 / (mr * mr);
        let drift = vec3<f32>(0.013, 0.021, -0.017) * t;
        deep = deep + vec3<f32>(0.5, 0.65, 1.0) * hd_mote((lp + vl * 2.2) / 2.3 + drift + sd, mr) * mk * 0.7;
        deep = deep + vec3<f32>(0.7, 0.55, 1.0) * hd_mote((lp + vl * 6.0) / 3.4 - drift.zxy + sd * 3.0, mr) * mk * 0.4;
        c = c + deep * dark * dark * (0.3 + 0.7 * ndv) * glow;
        // (a thin cold light along its edge, as off nothing there: its outline holds against sky and night)
        c = c + vec3<f32>(0.45, 0.62, 1.0) * pow(1.0 - ndv, 3.0) * (0.15 * HD_DM + 0.5 * dark) * glow;
    }
    if (HD_CLAY) {
        // (grey clay, one hard light from over the camera's shoulder, its shadow, dark in its creases)
        c = vec3<f32>(0.62) * (saturate(dot(n, Ls)) * shd * 1.05 + 0.16 * ao * ao2 * (0.6 + 0.4 * n.y)) + vec3<f32>(0.25) * pow(saturate(dot(n, normalize(Ls - rd))), 40.0) * shd;
        out.t = s;
        out.op = h.k;
        out.c = c * out.op;
        return out;
    }
    op = 1.0 - smoothstep(0.6, 1.0, fade);
    c = c * mix(1.0, 0.04, smoothstep(0.0, 0.8, fade));
    out.t = s;
    out.op = op * h.k;
    let hz = 1.0 - exp(-s / 2600.0);
    out.c = mix(c, skyl * 0.9, hz * 0.55 * (1.0 - 0.75 * dkm)) * out.op;
    return out;
}
// ---- the slam's dust: the crown of earth round its crater, and the surge it drove out over the land
// The land's height at xz (from the target), from skybreak.rs's SB_HF (48 by 48, 16 apart).
fn hd_land(xz: vec2<f32>) -> f32 {
    let f = clamp(xz / 16.0 + 23.5, vec2<f32>(0.0), vec2<f32>(46.999));
    let i = vec2<u32>(floor(f));
    let u = f - floor(f);
    let b = SB_FR + u32(SB_NF) * SB_FW + i.y * 48u + i.x;
    return mix(mix(sb_w(b), sb_w(b + 1u), u.x), mix(sb_w(b + 48u), sb_w(b + 49u), u.x), u.y);
}
// Cauliflower lumps (payload.wgsl's pl_dome): ~1 on a dome's crown, 0 in a crease.
fn hd_dome(p: vec3<f32>) -> f32 {
    let b = floor(p - 0.5);
    var hmax = 0.0;
    for (var c = 0u; c < 8u; c = c + 1u) {
        let cell = b + vec3<f32>(f32(c & 1u), f32((c >> 1u) & 1u), f32(c >> 2u));
        let q = bitcast<vec3<u32>>(vec3<i32>(cell));
        let h = pcg(q.x ^ pcg(q.y ^ pcg(q.z + 0x77u)));
        let jit = vec3<f32>(f32(h & 1023u), f32((h >> 10u) & 1023u), f32((h >> 20u) & 1023u)) * (0.7 / 1023.0) + 0.15;
        let sz = 0.7 + 0.55 * f32(pcg(h) & 1023u) / 1023.0;
        let e = cell + jit - p;
        hmax = max(hmax, sz * sqrt(saturate(1.0 - dot(e, e) * 1.7 / (sz * sz))));
    }
    return hmax;
}
struct HdDustK {
    s: vec2<f32>,      // where it came down (from the target), the land's height there, seconds since
    g: f32,
    a: f32,
    rc: f32,           // the crown: its ring's radius, its middle's height, its thickness
    hc: f32,
    th: f32,
    rf: f32,           // the surge: its front, its head's height
    hf: f32,
    fade: f32,
}
fn hd_dust_k(t: f32) -> HdDustK {
    let a = t - HD_PRESS - 0.02;
    let rc = 56.0 + 48.0 * (1.0 - exp(-a / 1.5)) + 3.0 * a;
    let hc = 18.0 + 32.0 * (1.0 - exp(-a / 0.8)) + 3.5 * a;
    let th = 18.0 + 14.0 * (1.0 - exp(-a / 1.6)) + 1.5 * a;
    // (sb_hand.rs's buffet keeps to this front)
    let rf = 70.0 + 450.0 * (1.0 - exp(-a / 2.6));
    let hf = (12.0 + 60.0 * exp(-a / 2.6)) * smoothstep(0.0, 0.35, a);
    let fade = smoothstep(0.0, 0.12, a) * (1.0 - smoothstep(4.5, 12.5, a));
    return HdDustK(vec2<f32>(sb_w(HD), sb_w(HD + 1u)), sb_w(HD + 5u), a, rc, hc, th, rf, hf, fade);
}
// The dust's density at p (from the target's ground point) over land `gl` high; `fine`: the lumps too. In .y how deep
// in it p is (0 at its skin), for the light.
fn hd_dust_at(p: vec3<f32>, k: HdDustK, gl: f32, fine: bool) -> vec2<f32> {
    let q = p.xz - k.s;
    let r = length(q);
    let h = p.y - gl;
    if (h < -3.0) {
        return vec2<f32>(0.0);
    }
    var den = 0.0;
    var dp = 0.0;
    let ang = atan2(q.y, q.x);
    // (the crown: earth thrown up over the rim, turning outward, lumps on lumps; eaten away, never mist)
    let roll = k.a * 0.8;
    let tc = vec2<f32>(r - k.rc, (p.y - k.g - k.hc) * 0.8);
    let dt = length(tc);
    if (dt < k.th + 34.0) {
        let tr = vec2<f32>(tc.x * cos(roll) + tc.y * sin(roll), tc.y * cos(roll) - tc.x * sin(roll));
        let dq = vec3<f32>(ang * k.rc, tr.x, tr.y) / (19.0 + 3.0 * min(k.a, 3.0)) + vec3<f32>(0.0, 0.0, -0.3 * k.a);
        let jet = gnoise2(vec2<f32>(ang * 2.4, 3.1)) - 0.5;
        var sd = dt - k.th * (1.0 + 0.5 * jet * smoothstep(-10.0, 30.0, tc.y)) - 24.0 * (hd_dome(dq) - 0.45) + 5.0 * max(k.a - 2.0, 0.0);
        if (fine && sd < 8.0) {
            sd = sd - 7.0 * (hd_dome(dq * 2.6 + vec3<f32>(5.1, 2.3, 7.7)) - 0.45);
        }
        den = smoothstep(2.0, -3.0, sd) * 0.16 * (1.0 - 0.5 * smoothstep(20.0, 140.0, h)) * exp(-k.a / 5.5) * smoothstep(0.3, 0.75, r / k.rc);
        dp = max(-sd, 0.0);
    }
    // (the surge: a wall of earth driven out over the land, its head a billowing roll tens of blocks high, lobed,
    // lower behind, thinning to a pall)
    let lobe = gnoise2(vec2<f32>(ang * 2.6 + 1.7, 0.3 * k.a)) - 0.5;
    let n3 = gnoise3(p * (1.0 / 40.0) + vec3<f32>(0.0, -0.25 * k.a, 9.0));
    let H = k.hf * (0.55 + 0.9 * n3) * (1.0 + 0.7 * lobe);
    let sb = k.rf * (1.0 + 0.13 * lobe) - r + 0.15 * min(h, H);
    if (sb > -40.0 && r > 40.0) {
        var b = 0.45;
        if (fine) {
            // (its billows ride its front, rolling up its face and back over its top)
            let ro2 = k.a * 0.55;
            let c = vec2<f32>(sb - 0.55 * H, h - 0.45 * H);
            let tq = vec2<f32>(c.x * cos(ro2) - c.y * sin(ro2), c.x * sin(ro2) + c.y * cos(ro2));
            b = hd_dome(vec3<f32>(ang * r, tq) / (10.0 + 0.25 * k.hf));
        }
        // (a rounded head rolling at its front, the body lower behind, lumps over both)
        let eh = 0.55 * H - length(vec2<f32>(sb - 0.55 * H, h - 0.45 * H));
        let eb = min(0.7 * H * mix(1.0, 0.55, smoothstep(H, 3.5 * H, sb)) - h, sb - 0.55 * H);
        let e = max(eh, eb) + 0.4 * H * (b - 0.45);
        let body = 0.18 * exp(-k.a / 5.0) * (1.0 - 0.8 * smoothstep(100.0, 420.0, r)) * exp(-max(sb - 1.3 * H, 0.0) / (0.5 * H + 8.0)) + 0.0035 * smoothstep(0.3, 0.7, n3);
        let w = smoothstep(-4.0, 5.0, e) * body;
        den = den + w;
        dp = select(dp, max(e, 0.0), w > den - w);
    }
    return vec2<f32>(den * k.fade, dp);
}
// The slam's dust along the ray from ro (from the target's ground point) to `far`: premultiplied colour, transmittance.
fn hd_dust(ro: vec3<f32>, rd: vec3<f32>, far: f32, t: f32, px: vec2<f32>, sunc: vec3<f32>, amb: vec3<f32>, L: vec3<f32>) -> vec4<f32> {
    if (sb_w(HD + 6u) < 1.0 || t < HD_PRESS || t > HD_PRESS + 14.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let k = hd_dust_k(t);
    // (its bounds: a box round crown and surge)
    let R = max(k.rf * 1.15 + 40.0, k.rc + k.th + 60.0);
    let lo = vec3<f32>(k.s.x - R, k.g - 50.0, k.s.y - R);
    let hi = vec3<f32>(k.s.x + R, k.g + k.hc + k.th + 70.0, k.s.y + R);
    let inv = 1.0 / select(rd, vec3<f32>(1e-6), abs(rd) < vec3<f32>(1e-6));
    let ta = (lo - ro) * inv;
    let tb = (hi - ro) * inv;
    let t0 = max(max(max(min(ta.x, tb.x), min(ta.y, tb.y)), min(ta.z, tb.z)), 0.0);
    let t1 = min(min(min(max(ta.x, tb.x), max(ta.y, tb.y)), max(ta.z, tb.z)), far);
    if (t1 <= t0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    var acc = vec3<f32>(0.0);
    var tr = 1.0;
    let dt0 = clamp((t1 - t0) / 44.0, 1.8, 6.5);
    var dt = dt0;
    var s = t0 + dt * ign(px);
    for (var m = 0; m < 56; m = m + 1) {
        if (s > t1 || tr < 0.02) {
            break;
        }
        let p = ro + rd * s;
        let gl = hd_land(p.xz);
        let dd = hd_dust_at(p, k, gl, s < 700.0);
        let den = dd.x * (0.3 + 0.7 * smoothstep(0.0, 30.0, s));
        dt = select(min(dt * 1.4, dt0 * 2.0), dt0, den > 0.002);
        if (den > 0.002) {
            // (sunlit through the dust over it, dark in its folds; browns, greys in patches, darker low)
            let sh = exp(-hd_dust_at(p + L * 16.0, k, gl, false).x * 18.0);
            let hy = saturate((p.y - gl) / 70.0);
            let cv = gnoise2(p.xz * 0.02);
            let base = mix(mix(vec3<f32>(0.12, 0.1, 0.085), vec3<f32>(0.36, 0.31, 0.25), hy), mix(vec3<f32>(0.1, 0.095, 0.09), vec3<f32>(0.37, 0.35, 0.33), hy), cv);
            let fold = exp(-dd.y / 14.0);
            let lit = base * (sunc * (0.16 + 0.84 * sh) * (0.45 + 0.55 * fold) + amb * (0.4 + 0.3 * hy) * (0.7 + 0.3 * fold));
            let ab = exp(-den * dt);
            acc = acc + tr * (1.0 - ab) * lit;
            tr = tr * ab;
        }
        s = s + dt;
    }
    return vec4<f32>(acc, tr);
}
// The slam's shockwave, ahead of its dust: the air's front from under the fist, at the speed of sound once clear of it
// (`rs`: sb_hand.rs's jolt and hd_lens keep to it): grit swept off the land, torn along its top, thinning behind
// (no dome); passing the eye, the air thick with it a breath. Its colour, transmittance
// (behind the slam's dust: `hide` of it).
fn hd_shock(ro: vec3<f32>, rd: vec3<f32>, far: f32, t: f32, px: vec2<f32>, hide: f32, sunc: vec3<f32>, amb: vec3<f32>) -> vec4<f32> {
    let a = t - HD_PRESS;
    var acc = vec3<f32>(0.0);
    var tr = 1.0;
    if (sb_w(HD + 6u) < 1.0 || a < 0.0 || a > 6.0) {
        return vec4<f32>(acc, tr);
    }
    let f = vec3<f32>(sb_w(HD), sb_w(HD + 5u), sb_w(HD + 1u));
    let o = ro - f;
    let rs = 343.0 * a + 30.0 * (1.0 - exp(-a / 0.08));
    let k = smoothstep(0.0, 0.04, a) * exp(-a / 1.7);
    let rc = length(o.xz);
    // (the skirt: across the ring from the front back 45, over the land; near crossing, then far)
    let A2 = max(dot(rd.xz, rd.xz), 1e-6);
    let B2 = dot(o.xz, rd.xz);
    let Ro = rs * 1.05 + 8.0;
    let dout = B2 * B2 - A2 * (rc * rc - Ro * Ro);
    let ri = max(rs - 45.0, 0.0);
    let si = sqrt(max(B2 * B2 - A2 * (rc * rc - ri * ri), 0.0));
    let ry = select(rd.y, 1e-6, abs(rd.y) < 1e-6);
    let ya = (-40.0 - o.y) / ry;
    let yb = (70.0 - o.y) / ry;
    let j = ign(px);
    for (var sg = 0; sg < 2 && dout > 0.0; sg = sg + 1) {
        let sq = sqrt(dout) * select(-1.0, 1.0, sg == 1);
        let sa = max(max(select(-B2 + si, -B2 + sq, sg == 0) / A2, min(ya, yb)), 0.0);
        let sb = min(min(select(-B2 - si, -B2 + sq, sg == 1) / A2, max(ya, yb)), far);
        let dt = (sb - sa) / 6.0;
        for (var m = 0; m < 6 && sb > sa && tr > 0.03; m = m + 1) {
            let p = o + rd * (sa + dt * (f32(m) + j));
            let r = length(p.xz);
            let h = p.y + f.y - hd_land(p.xz + f.xz);
            let lob = gnoise2(p.xz * (3.5 / r) + 1.3);
            let x0 = rs * (1.0 + 0.1 * (lob - 0.5)) - r;
            if (h > 50.0 || x0 < -9.0 || x0 > 60.0) {
                continue;
            }
            let n1 = gnoise3(p * vec3<f32>(0.07, 0.14, 0.07) + vec3<f32>(0.0, -1.5 * a, 3.0));
            let x = x0 + 12.0 * (n1 - 0.5);
            let g = gnoise2(p.xz / 25.0 + 0.8 * a);
            let top = (9.0 + 30.0 * exp(-a / 1.3)) * (0.3 + 1.4 * g);
            let den = 0.9 * k * smoothstep(-3.0, 1.0, x) * exp(-max(x, 0.0) / (12.0 + 0.05 * r)) * smoothstep(top, 0.3 * top, h) * smoothstep(-3.0, 0.0, h) * saturate(1.6 * n1 + 0.5 * g - 0.2) * smoothstep(0.1, 0.5, lob + 0.3 * g) * smoothstep(40.0, 90.0, r);
            let al = (1.0 - exp(-den * dt)) * select(hide, 1.0, sg == 0);
            let hy = saturate(0.7 * h / top + 0.3 * n1);
            acc = acc + tr * al * mix(vec3<f32>(0.16, 0.14, 0.12), vec3<f32>(0.56, 0.5, 0.42), hy) * (sunc * (0.5 + 0.4 * hy) + amb * 0.75);
            tr = tr * (1.0 - al);
        }
    }
    // (at the eye)
    let tau = a - max(rc - 30.0, 0.0) / 343.0;
    let E = 0.6 * smoothstep(-0.05, 0.05, tau) * exp(-max(tau, 0.0) / 0.8) * k * smoothstep(40.0, 8.0, o.y + f.y - hd_land(ro.xz)) * smoothstep(60.0, 120.0, rc);
    acc = acc + tr * E * vec3<f32>(0.5, 0.46, 0.4) * (sunc * 0.6 + amb * 0.8);
    tr = tr * (1.0 - E);
    return vec4<f32>(acc, tr);
}
// What is behind it (`behind`) with the hand over it.
fn hd_over(behind: vec3<f32>, h: HdHit) -> vec3<f32> {
    return behind * (1.0 - h.op) + h.c;
}
// [end hand]

// (muck on the lens as the smash's front passes the eye, as the Payload's: soft drops far out of focus, `lit` on them)
fn hd_lens(col: vec3<f32>, ro: vec3<f32>, t: f32, pxy: vec2<f32>, lit: vec3<f32>) -> vec3<f32> {
    let a = t - HD_PRESS;
    let rc = length(ro.xz - vec2<f32>(sb_w(HD), sb_w(HD + 1u)));
    let tau = a - max(rc - 30.0, 0.0) / 343.0;
    let vis = smoothstep(40.0, 8.0, ro.y - hd_land(ro.xz)) * smoothstep(1400.0, 500.0, rc) * smoothstep(60.0, 140.0, rc);
    if (sb_w(HD + 6u) < 1.0 || vis <= 0.0 || tau < 0.2) {
        return col;
    }
    let res = frame.resolution.xy;
    let s = u32(seed_v());
    var keep = 1.0;
    var shine = 0.0;
    for (var i = 0u; i < 14u; i = i + 1u) {
        let age = tau - 0.25 - 1.4 * mh(i, s, 0x3d0u);
        let c = vec2<f32>(0.03 + 0.94 * mh(i, s, 0x3d1u), 0.02 + 0.4 * pow(mh(i, s, 0x3d2u), 1.3)) * res;
        let r = (0.011 + 0.026 * pow(mh(i, s, 0x3d3u), 0.8)) * res.y;
        let d0 = pxy - c;
        if (age <= 0.0 || dot(d0, d0) > 16.0 * r * r) {
            continue;
        }
        let life = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(5.0, 10.0, age + 3.0 * mh(i, s, 0x3d4u)));
        for (var j = 0u; j < 4u; j = j + 1u) {
            let k2 = i * 7u + j;
            if (j > 0u && mh(k2, s, 0x3e0u) > 0.3) {
                continue;
            }
            let rj = select(r * (0.22 + 0.3 * mh(k2, s, 0x3e1u)), r, j == 0u);
            let ang = TAU * mh(k2, s, 0x3e2u);
            let dj = pxy - select(c + vec2<f32>(cos(ang), sin(ang)) * r * (1.4 + 0.9 * mh(k2, s, 0x3e3u)), c, j == 0u);
            let rot = TAU * mh(k2, s, 0x3e4u);
            let stretch = 1.0 + mix(0.4, 0.06, smoothstep(0.012, 0.03, rj / res.y)) * 2.0 * mh(k2, s, 0x3e5u);
            let e = vec2<f32>((dj.x * cos(rot) + dj.y * sin(rot)) / stretch, dj.y * cos(rot) - dj.x * sin(rot));
            let th = atan2(e.y, e.x);
            let ph = TAU * mh(k2, s, 0x3e6u);
            let q = length(e) / rj * (1.0 + 0.05 * sin(3.0 * th + ph) + 0.035 * sin(5.0 * th - 2.0 * ph));
            if (q >= 1.4) {
                continue;
            }
            let body = 1.0 - smoothstep(0.3, 1.38, q);
            let op = (0.14 + 0.34 * pow(mh(k2, s, 0x3e7u), 0.7)) * select(0.85, 1.0, j == 0u) * life;
            keep = keep * (1.0 - body * mix(0.9, 1.15, smoothstep(0.1, 0.8, q)) * (0.94 + 0.12 * gnoise3(vec3<f32>(e / (0.8 * rj), f32(k2 % 97u)))) * op);
            shine = shine + body * smoothstep(0.3, -0.9, dj.y / rj) * op;
        }
    }
    return col * mix(1.0, keep, vis) + vec3<f32>(0.42, 0.38, 0.33) * lit * 0.4 * min(shine, 1.0) * vis;
}

fn skybreak(in: StageIn, stage: u32, up: vec4<f32>, up_e: vec2<f32>) -> SbOut {
    var uv = in.uv;
    let time = now();
    let cam = frame.camera_position.xyz;
    let px_a = frame.view_params.w / frame.resolution.y;
    let anc = anchor_xz();
    let gy = block_y() + 1.0;
    let C = vec3<f32>(anc.x, gy, anc.y) - cam; // the target's ground point, from the camera
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    let moon = smoothstep(-0.02, -0.2, sun.y);
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    let have = arrayLength(&mod_data) > SB_FR + 32u;

    var d = 0.0;
    if (stage == 1u) {
        let full = vec2<i32>(frame.resolution.xy);
        let q = vec2<i32>(floor(in.position.xy)) * 2;
        let q1 = min(q + vec2<i32>(1), full - vec2<i32>(1));
        let d0 = textureLoad(scene_depth, q, 0);
        let d1 = textureLoad(scene_depth, vec2<i32>(q1.x, q.y), 0);
        let d2 = textureLoad(scene_depth, vec2<i32>(q.x, q1.y), 0);
        let d3 = textureLoad(scene_depth, q1, 0);
        let hq = vec2<i32>(floor(in.position.xy));
        d = select(min(min(d0, d1), min(d2, d3)), max(max(d0, d1), max(d2, d3)), ((hq.x + hq.y) & 1) == 0);
        uv = (vec2<f32>(q) + 1.0) * frame.resolution.zw;
    } else {
        d = depth_at(uv);
    }
    let sky = is_sky(d);
    let rel = world_offset(uv, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    let ro = -C; // the camera, from the target's ground point

    // (the light, matched to the scene's: its sky from the picture's top where it is sky, and the sun's)
    var skyl = srgb_to_linear(frame.sky_color.rgb);
    var nsk = 1.0;
    for (var s = 0; s < 3; s = s + 1) {
        let su = vec2<f32>(0.2 + 0.3 * f32(s), 0.04);
        if (is_sky(depth_at(su))) {
            skyl = skyl + srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, su, 0.0).rgb);
            nsk = nsk + 1.0;
        }
    }
    skyl = skyl / nsk;
    // (how light the sky is: cracks and glows as bright against it as it is light, dim at night)
    let nk = clamp(0.06 + 2.2 * dot(skyl, vec3<f32>(0.2126, 0.7152, 0.0722)), 0.1, 1.0);
    let amb = mix(vec3<f32>(0.03, 0.035, 0.05), skyl * 0.85 + vec3<f32>(0.04), day);
    let sunc = mix(vec3<f32>(1.35, 1.24, 1.06), mix(vec3<f32>(1.5, 0.68, 0.3), vec3<f32>(1.3, 0.38, 0.14), smoothstep(0.0, -0.1, sun.y)), warm) * sun_up + vec3<f32>(0.07, 0.09, 0.14) * moon;
    let fade_all = 1.0 - smoothstep(SB_LEN - 2.5, SB_LEN, time);
    let heal = smoothstep(SB_HEAL, SB_HEALED, time);
    let look = C + vec3<f32>(0.0, SB_H, 0.0); // the point the sky broke from, from the camera

    // ---- the panes coming down (and lying where they landed, block for block, until their blocks are in)
    var near_t = scene_len;
    // ---- the hand (and its arm), traced first: what it hides need not be worked out
    var hd = HdHit(1.0e9, 0.0, vec3<f32>(0.0));
    if (have && stage != 1u) {
        hd = hd_trace(ro, rd, time, px_a, scene_len, sunc, L, skyl, amb);
        if (hd.op > 0.985) {
            near_t = min(near_t, hd.t);
        }
    }
    var pane_c = vec3<f32>(0.0);
    var pane_hit = false;
    var dust_far = scene_len;
    if (have && stage != 1u) {
        let n = i32(sb_w(0u));
        for (var i = 0; i < SB_NS; i = i + 1) {
            if (i >= n) {
                break;
            }
            let ps = sb_pose(i, time);
            if (ps.st == 0 || ps.st == 3) {
                continue;
            }
            let b = SB_SH + u32(i) * SB_SW;
            let th = sb_w(b + 9u);
            let lro = sb_qinv(ps.q, ro - ps.c);
            let lrd = sb_qinv(ps.q, rd);
            if (ps.st == 1) {
                let h = sb_prism(lro, lrd, i, 0.0);
                if (h.x < h.y && h.y > 0.0 && h.x < near_t) {
                    let tt = max(h.x, 0.0);
                    near_t = tt;
                    pane_hit = true;
                    let lp = lro + lrd * tt;
                    let sky_side = h.z < 0.5;
                    // (its normal in the world, for the light)
                    var ln = vec3<f32>(0.0, select(1.0, -1.0, sky_side), 0.0);
                    if (h.z > 1.5) {
                        // (its broken rim: the edge it came in by)
                        let nn = i32(sb_w(b + 8u));
                        var best = 1.0e9;
                        for (var k = 0; k < 4; k = k + 1) {
                            if (k >= nn) {
                                break;
                            }
                            let k1 = (k + 1) % nn;
                            let p0 = vec2<f32>(sb_w(b + u32(2 * k)), sb_w(b + u32(2 * k + 1)));
                            let p1 = vec2<f32>(sb_w(b + u32(2 * k1)), sb_w(b + u32(2 * k1 + 1)));
                            let e = p1 - p0;
                            let dd = abs(sb_cross2(e, lp.xz - p0)) / max(length(e), 1e-4);
                            if (dd < best) {
                                best = dd;
                                ln = normalize(vec3<f32>(e.y, 0.0, -e.x));
                            }
                        }
                    }
                    let wn = sb_qrot(ps.q, ln);
                    let ndl = max(dot(wn, L), 0.0);
                    let fres = pow(saturate(1.0 - abs(dot(wn, rd))), 4.0);
                    let spec = pow(max(dot(reflect(rd, wn), L), 0.0), 220.0);
                    var c = vec3<f32>(0.0);
                    if (h.z > 1.5) {
                        // (thick glass, pale and cold, bright where it catches light)
                        c = vec3<f32>(0.66, 0.82, 0.98) * (sunc * (0.45 + 0.7 * ndl) + amb * 1.2) + vec3<f32>(0.5, 0.6, 0.7) * fres * amb * 2.0;
                    } else if (sky_side) {
                        // (its sky: as where it hung, then its painted sky as it falls)
                        let qx = lp.x + sb_w(b + 10u);
                        let qz = lp.z + sb_w(b + 11u);
                        // (deeper blue than the sky round it once fallen out of it: the sky as it was up there)
                        let painted = sb_painted(qx, qz, skyl, sunc, amb) * vec3<f32>(0.84, 0.92, 1.1);
                        c = mix(scene, painted, smoothstep(0.0, 0.25, ps.u) * select(1.0, 0.0, sky && ps.u < 0.001));
                        c = mix(c, painted, select(0.0, 1.0, !sky));
                        // (and glass: the light glancing off it, its broken edges catching it)
                        let bev = exp(-max(sb_inset(lp.xz, i), 0.0) / 1.6) * smoothstep(0.0, 0.1, ps.u + select(0.0, 0.2, t_sag(time, i)));
                        c = c * (0.92 + 0.12 * ndl) + vec3<f32>(1.2, 1.15, 1.05) * spec * sunc * 1.5 + skyl * fres * 0.6 + vec3<f32>(0.8, 0.88, 1.0) * bev * (sunc * 0.4 + amb * 0.9);
                    } else {
                        // (its back: the dark from behind the sky, a few sparks in it)
                        let g = floor(lp.xz * 0.5);
                        let sp = step(0.985, fh21(g + vec2<f32>(seed_v(), f32(i))));
                        c = vec3<f32>(0.012, 0.008, 0.022) + vec3<f32>(0.7, 0.75, 0.95) * sp * 0.6 + vec3<f32>(0.2, 0.22, 0.3) * spec * sunc + vec3<f32>(0.05, 0.04, 0.09) * fres;
                    }
                    // (the air between: far panes fade in the haze)
                    let haze = 1.0 - exp(-tt / 2600.0);
                    pane_c = mix(c, skyl * 0.95, haze * 0.7);
                }
            } else {
                // (down: block for block as the mod lays it, till its blocks are in. One never laid (terrain off, or
                // its land never loaded) crumbles away block by block as the sky heals, each flaring pale as it goes)
                let gone = sb_w(b + 14u);
                let du = select(-1.0, smoothstep(SB_HEAL + 0.5, SB_HEALED + 0.3, time) * 1.12, gone < 0.0 || sb_w(2u) < 0.5);
                if (du >= 1.1) {
                    continue;
                }
                let lro2 = sb_qinv(ps.q, ro - ps.c);
                let h = sb_prism(lro2, lrd, i, 0.9);
                if (h.x < h.y && h.y > 0.0 && h.x < near_t) {
                    // (through the world's blocks in the mod's grid: a block is the pane's if its middle is inside it)
                    let g0 = ro + vec3<f32>(0.5, 0.0, 0.5);
                    var tt = max(h.x, 0.0) + 1e-3;
                    let pp = g0 + rd * tt;
                    var cell = floor(pp);
                    let stp = sign(rd);
                    let tdel = abs(1.0 / max(abs(rd), vec3<f32>(1e-6)));
                    var tmax = (select(cell, cell + 1.0, rd > vec3<f32>(0.0)) - pp) / select(-max(abs(rd), vec3<f32>(1e-6)), max(abs(rd), vec3<f32>(1e-6)), rd > vec3<f32>(0.0)) + tt;
                    var face = 1;
                    var found = false;
                    for (var m = 0; m < 110; m = m + 1) {
                        if (tt > h.y + 1.8 || tt > near_t) {
                            break;
                        }
                        let ctr = cell + vec3<f32>(0.0, 0.5, 0.0);
                        let lc = sb_qinv(ps.q, ctr - ps.c);
                        if (abs(lc.y) <= 0.5 * th && sb_inset(lc.xz, i) >= 0.0 && (du < 0.0 || sb_crumb(cell, i) > du)) {
                            found = true;
                            break;
                        }
                        if (tmax.x < tmax.y && tmax.x < tmax.z) {
                            tt = tmax.x;
                            tmax.x = tmax.x + tdel.x;
                            cell.x = cell.x + stp.x;
                            face = 0;
                        } else if (tmax.y < tmax.z) {
                            tt = tmax.y;
                            tmax.y = tmax.y + tdel.y;
                            cell.y = cell.y + stp.y;
                            face = 1;
                        } else {
                            tt = tmax.z;
                            tmax.z = tmax.z + tdel.z;
                            cell.z = cell.z + stp.z;
                            face = 2;
                        }
                    }
                    // (where the real blocks already are, going in, they win: no fighting over a face)
                    if (found && tt < near_t - 0.3) {
                        near_t = tt;
                        pane_hit = true;
                        let ctr = cell + vec3<f32>(0.0, 0.5, 0.0);
                        let lc = sb_qinv(ps.q, ctr - ps.c);
                        let wc = ctr + cam + C;
                        let m = sb_block_of(lc, i, wc);
                        var nrm = vec3<f32>(0.0);
                        if (face == 0) {
                            nrm.x = -stp.x;
                        } else if (face == 1) {
                            nrm.y = -stp.y;
                        } else {
                            nrm.z = -stp.z;
                        }
                        let hp = g0 + rd * tt;
                        let fp = fract(hp);
                        let ed = min(min(select(min(fp.x, 1.0 - fp.x), 1.0, face == 0), select(min(fp.y, 1.0 - fp.y), 1.0, face == 1)), select(min(fp.z, 1.0 - fp.z), 1.0, face == 2));
                        let shade = select(select(0.8, 1.0, face == 1 && nrm.y > 0.0), 0.5, face == 1 && nrm.y < 0.0) * select(1.0, 0.75, ed < 0.05);
                        let alb = srgb_to_linear(sb_block_rgb(m));
                        // (a little texture in each block's face)
                        let tex = 0.9 + 0.2 * fh21(floor(fp.xz * 8.0 + fp.y * 13.0) + cell.xz * 3.1);
                        var c = alb * tex * shade * (sunc * 0.75 * max(dot(nrm, L), 0.0) + amb * 1.1);
                        if (m == 4) {
                            c = c + vec3<f32>(0.25, 0.3, 0.4) * pow(saturate(1.0 - abs(dot(nrm, rd))), 3.0) * amb;
                        }
                        if (m == 6) {
                            c = c + vec3<f32>(0.08, 0.02, 0.18);
                        }
                        if (du > 0.0) {
                            let e = 1.0 - saturate((sb_crumb(cell, i) - du) / 0.07);
                            c = c + vec3<f32>(0.7, 0.82, 1.0) * e * e * (0.25 + 0.9 * nk);
                        }
                        let haze = 1.0 - exp(-tt / 2600.0);
                        pane_c = mix(c, skyl * 0.95, haze * 0.7);
                    }
                }
            }
        }
    }
    // ---- the shattered middle's fragments, tumbling down until they burst
    if (have && stage != 1u && time > SB_COLLAPSE - 0.5) {
        let nf = i32(sb_w(1u));
        for (var f = 0; f < SB_NF; f = f + 1) {
            if (f >= nf) {
                break;
            }
            let a = sb_frag_a(f, time);
            let fb = SB_FR + u32(f) * SB_FW;
            // (one the arm drags is there from the punch, riding it)
            let riding = sb_w(fb + 15u) > 0.5 && time > SB_COLLAPSE;
            if ((a < 0.0 && !riding) || a > sb_w(fb + 14u) + 0.3) {
                continue;
            }
            let ps = sb_frag_pose(f, a);
            if (dot(ps.c - ro, rd) - 70.0 > near_t) {
                continue;
            }
            let sc = max(ps.u, 0.02);
            let lro = sb_qinv(ps.q, ro - ps.c) / sc;
            let lrd = sb_qinv(ps.q, rd);
            let h = sb_poly(lro, lrd, fb, SB_FTH, 0.0);
            let tt = max(h.x, 0.0) * sc;
            if (h.x < h.y && h.y > 0.0 && tt < near_t) {
                near_t = tt;
                pane_hit = true;
                let lp = lro + lrd * max(h.x, 0.0);
                let ln = select(select(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, -1.0, 0.0), h.z < 0.5), normalize(vec3<f32>(lp.x, 0.0, lp.z)), h.z > 1.5);
                let wn = sb_qrot(ps.q, ln);
                let ndl = max(dot(wn, L), 0.0);
                let spec = pow(max(dot(reflect(rd, wn), L), 0.0), 120.0);
                var c = vec3<f32>(0.0);
                if (h.z > 1.5) {
                    c = vec3<f32>(0.66, 0.8, 0.96) * (sunc * (0.35 + 0.6 * ndl) + amb);
                } else if (h.z < 0.5) {
                    c = sb_painted(lp.x + sb_w(fb + 9u), lp.z + sb_w(fb + 10u), skyl, sunc, amb) * vec3<f32>(0.86, 0.93, 1.08);
                } else {
                    c = vec3<f32>(0.012, 0.008, 0.022);
                }
                c = c + vec3<f32>(1.2, 1.15, 1.05) * spec * sunc * 1.2;
                // (bright as it bursts)
                c = c + vec3<f32>(0.8, 0.9, 1.0) * (1.0 - ps.u) * 2.0;
                pane_c = mix(c, skyl * 0.95, (1.0 - exp(-tt / 2600.0)) * 0.7);
            }
        }
    }
    // ---- what each impact throws: chunks of earth and pane flung out in arcs, falling back into the dust
    if (have && stage != 1u) {
        let n = i32(sb_w(0u));
        for (var i = 0; i <= SB_NS; i = i + 1) {
            let im = sb_impact(i, n);
            let a = time - im.hit;
            if (!im.ok || a < 0.0 || a > 5.0) {
                continue;
            }
            let foot = im.foot;
            let sc = foot + vec3<f32>(0.0, 45.0, 0.0);
            let oc = ro - sc;
            let bq = dot(oc, rd);
            let cq = dot(oc, oc) - 190.0 * 190.0;
            if (bq * bq - cq <= 0.0 || -bq + sqrt(max(bq * bq - cq, 0.0)) < 0.0) {
                continue;
            }
            for (var j = 0; j < 30; j = j + 1) {
                let hj = u32(i * 64 + j);
                let ph = TAU * mh(hj, u32(seed_v()), 0xa1u);
                let vh = 16.0 + 42.0 * mh(hj, u32(seed_v()), 0xa2u);
                let vy = 22.0 + 50.0 * mh(hj, u32(seed_v()), 0xa3u);
                let sz = 0.8 + 2.2 * pow(mh(hj, u32(seed_v()), 0xa4u), 2.0);
                let c = foot + vec3<f32>(cos(ph) * vh * a, 3.0 + vy * a - 16.0 * a * a, sin(ph) * vh * a);
                if (c.y < foot.y - 2.0) {
                    continue;
                }
                let ax = normalize(vec3<f32>(mh(hj, 7u, 0xa5u) - 0.5, mh(hj, 7u, 0xa6u) - 0.5, mh(hj, 7u, 0xa7u) - 0.5) + vec3<f32>(1e-3));
                let q = sb_axis_q(ax, a * (3.0 + 6.0 * mh(hj, 7u, 0xa8u)));
                let lro = sb_qinv(q, ro - c);
                let lrd = sb_qinv(q, rd);
                let inv = 1.0 / select(lrd, vec3<f32>(1e-6), abs(lrd) < vec3<f32>(1e-6));
                let t0v = (vec3<f32>(-sz) - lro) * inv;
                let t1v = (vec3<f32>(sz) - lro) * inv;
                let tn = max(max(min(t0v.x, t1v.x), min(t0v.y, t1v.y)), min(t0v.z, t1v.z));
                let tf = min(min(max(t0v.x, t1v.x), max(t0v.y, t1v.y)), max(t0v.z, t1v.z));
                if (tn < tf && tf > 0.0 && tn < near_t) {
                    near_t = max(tn, 0.0);
                    pane_hit = true;
                    // (its face: the one the ray came in by)
                    let hp = lro + lrd * tn;
                    let ah = abs(hp) / sz;
                    var ln = vec3<f32>(0.0, sign(hp.y), 0.0);
                    if (ah.x > ah.y && ah.x > ah.z) {
                        ln = vec3<f32>(sign(hp.x), 0.0, 0.0);
                    } else if (ah.z > ah.y) {
                        ln = vec3<f32>(0.0, 0.0, sign(hp.z));
                    }
                    let wn = sb_qrot(q, ln);
                    let ice = mh(hj, 7u, 0xa9u) < 0.3 && !im.hand;
                    let alb = select(vec3<f32>(0.2, 0.14, 0.09), vec3<f32>(0.5, 0.68, 0.95), ice);
                    pane_c = alb * (sunc * (0.25 + 0.75 * max(dot(wn, L), 0.0)) + amb * 0.8);
                }
            }
        }
    }
    // (the opening's island, what falls off and circles it: `[lift]`)
    if (have && stage != 1u) {
        lf_draw(ro, rd, time, scene_len, L, sunc, amb, skyl, &near_t, &pane_hit, &pane_c);
    }
    // (the hand: over what it is in front of, or through the holes behind the glass; not over a pane, a piece or the
    // island in front of it)
    if (hd.t > near_t + 0.01) {
        hd = HdHit(1.0e9, 0.0, vec3<f32>(0.0));
    }
    dust_far = near_t;
    if (hd.op > 0.4) {
        dust_far = min(dust_far, hd.t);
    }

    // (the opening: the ground cracking round the island's rim, the hand's shadow on the land: `[lift]`)
    if (have && stage != 1u && time < SB_CRACK + 0.25) {
        if (!sky) {
            col = lf_land(lf_ground(col, rel - C, time, scene_len * px_a), rel - C, time, L);
        }
    }
    // ---- the sky's pane: its cracks, its panes out of true, its holes (from under it; from over it, its back)
    var sky_c = col;
    let above = ro.y > SB_H;
    // (where the hand hides it all in front of the glass, no glass is worked out)
    let hand_hides = hd.op > 0.985;
    if (have && stage != 1u && select(rd.y > 0.0, rd.y < 0.0, above) && time > SB_CRACK - 0.3 && !(hand_hides && hd.t < (SB_H - ro.y) / rd.y)) {
        let tp = (SB_H - ro.y) / rd.y;
        if (tp < scene_len && tp < near_t) {
            let q = ro.xz + rd.xz * tp;
            let pxw = tp * px_a / sqrt(max(abs(rd.y), 0.06)); // a pixel's width on the pane, in blocks, roughly
            let far_k = exp(-tp / 9000.0);
            let far_c = exp(-tp / 4200.0); // (the cracks far off fade into the haze)
            let dq = length(q);
            let dc = time - SB_CRACK;
            // (the first crack's shudder: a ring racing out through the glass from where it broke, bending sky)
            let rr = 3400.0 * (1.0 - exp(-max(dc, 0.0) / 0.16));
            let rw = 24.0 + 0.1 * rr;
            var ring = exp(-(dq - rr) * (dq - rr) / (rw * rw)) * exp(-max(dc, 0.0) * 4.0) * step(0.0, dc);
            // (and the slam's, up the arm and out through the glass from the hole, knocking its last pieces loose)
            let dk = time - HD_KNOCK + 0.12;
            if (dk > 0.0 && dk < 2.0) {
                let rk = 60.0 + 2600.0 * (1.0 - exp(-dk / 0.3));
                let wk = 20.0 + 0.08 * rk;
                ring = ring + exp(-(dq - rk) * (dq - rk) / (wk * wk)) * exp(-dk * 2.6) * 0.8;
            }
            let cell0 = sb_cell(q);
            if (cell0.y > -9 && time > SB_CRACK - 0.05) {
                let cr = sb_cracks(q, cell0, time);
                let rq = dq;
                // (the piece across the nearest crack; where it wanders over the line between its ends, the side q
                // is really on, so a hole's edge follows the crack drawn)
                var cell = cell0;
                var nb = cell0;
                if (cr.w > 0.45 && cr.d < max(pxw * 5.0, 18.0)) {
                    nb = sb_cell(cr.nq);
                    if (cr.sw > 0.5 && nb.y > -9) {
                        cell = nb;
                        nb = cell0;
                    }
                }
                // (which piece is open: a pane broken free, or a piece of the middle once fallen)
                let ot = sb_open(cell, time);
                var open = ot.x;
                let tear = ot.y;
                var onb = open;
                if (nb.x != cell.x || nb.y != cell.y) {
                    onb = sb_open(nb, time).x;
                }
                let both = min(open, onb);
                // (healing from its edges: the hole closing in from the cracks round it)
                let heal_d = heal * 120.0;
                let inner = min(cr.d, 1.0e5);
                let open0 = open;
                if (heal > 0.0) {
                    open = open * smoothstep(heal_d - 6.0, heal_d, inner);
                }
                // (each piece tilted its own way, the sky behind shifted through it by its tilt: more as the middle
                // sags before it gives, most round a piece about to go)
                let shift_t = sb_shift(time) * (1.0 - heal);
                // (round the hole the glass left hangs out of true, sagging till the slam knocks it loose)
                let sag = smoothstep(260.0, 40.0, rq) * smoothstep(SB_CRACK, SB_CRACK + 0.5, time) * (1.0 - heal);
                let h1 = sb_cell_hash(cell.x, cell.y, 0x81u);
                let h2 = sb_cell_hash(cell.x, cell.y, 0x82u);
                let h3 = sb_cell_hash(cell.x, cell.y, 0x83u);
                let tv = vec2<f32>(h1 - 0.5, h2 - 0.5) * 2.0;
                var glass = col;
                if (sky && !above) {
                    var duv = tv * 0.009 * shift_t * (1.0 + 1.6 * sag + 2.5 * tear);
                    // (the shudder's ring bending it outward as it passes)
                    let bp = project_rel(look);
                    if (bp.z > 0.0 && ring > 0.01) {
                        duv = duv + normalize(uv - bp.xy + vec2<f32>(1e-5, 0.0)) * ring * 0.014;
                    }
                    let uv2 = clamp(uv + duv, vec2<f32>(0.0), vec2<f32>(1.0));
                    if (is_sky(depth_at(uv2))) {
                        glass = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv2, 0.0).rgb);
                    }
                }
                glass = glass * (1.0 + (h3 - 0.5) * 0.16 * shift_t * (1.0 + sag)) + vec3<f32>(0.02, 0.03, 0.05) * (h1 - 0.3) * shift_t * day;
                // (now and then a piece's tilt catches the sun)
                let tl = 0.06 * shift_t * (1.0 + 2.0 * sag + 3.0 * tear);
                let nrm = normalize(vec3<f32>(tv.x * tl, select(1.0, -1.0, above), tv.y * tl));
                let gl = pow(max(dot(refract(rd, -nrm, 0.92), L), 0.0), 900.0) * shift_t;
                glass = glass + sunc * gl * 1.4 * far_k * select(1.0, 0.0, above);
                // (near the impact the glass crushed white: a frosted mist, its breaks hackled; further out, clean)
                let hk = 1.0 - smoothstep(30.0, 900.0, rq);
                let crk_t = smoothstep(SB_CRACK, SB_CRACK + 0.6, time);
                let frost = vec3<f32>(0.85, 0.9, 1.0) * (amb * 1.4 + sunc * 0.22);
                glass = mix(glass, frost, (0.5 * (1.0 - smoothstep(14.0, 52.0, rq)) * crk_t + 0.12 * exp(-cr.d / (2.0 + 5.0 * hk)) * shift_t * hk) * far_k * (1.0 - heal));
                // (from over it: its back, dark glass, the land under dimmed through it)
                if (above) {
                    glass = glass * vec3<f32>(0.42, 0.40, 0.52) * mix(1.0, 0.75, far_k) + vec3<f32>(0.012, 0.010, 0.022);
                }
                // (the void through the holes, and the eye; through a hole's edge, the broken pane's thickness, its
                // inner wall. From over it, through a hole, the land as it is)
                var vo = col;
                if (!above) {
                    // (the hand behind the glass, seen through the hole over the void and the eye, the eye's flare
                    // lighting the dark round it; no void worked out where the hand hides it)
                    if (hand_hides && hd.t > tp) {
                        vo = hd.c;
                    } else {
                        vo = sb_void(ro, rd, time, px_a, open > 0.003, nk);
                        vo = vo + vec3<f32>(0.12, 0.17, 0.36) * hd_flare(time) * exp(-dq / 260.0);
                        if (hd.t > tp) {
                            vo = hd_over(vo, hd);
                        }
                    }
                    if (open > 0.02) {
                        let tq = (SB_H + 7.0 - ro.y) / rd.y;
                        let q2 = ro.xz + rd.xz * tq;
                        let c2 = sb_cell(q2);
                        if (c2.y > -9 && sb_open(c2, time).x < 0.5) {
                            let wall = vec3<f32>(0.6, 0.76, 0.95) * (amb * 1.3 + sunc * 0.25) + vec3<f32>(0.15, 0.2, 0.3) * pow(saturate(1.0 - rd.y), 3.0);
                            vo = mix(vo, wall, 1.0 - heal);
                        }
                    }
                }
                sky_c = mix(glass, vo, open);
                // ---- the cracks: a dark gap opening in each, its edges bright or dim by their piece's tilt, chipped,
                // a glow round it; as bright against the sky as it is light (dim at night)
                if (cr.d < 1.0e8) {
                    let age = cr.age;
                    let fade_c = 1.0 - smoothstep(SB_HEAL + 2.0, SB_HEALED + 1.0, time);
                    let wsc = mix(0.6, 1.6, hk * hk * hk);
                    // (the gap, opening as the pieces part, wider where it all began and where a chip broke out)
                    let gap = (0.1 + 0.45 * smoothstep(0.0, 4.0, age) + 2.2 * tear) * (1.0 + 0.8 * smoothstep(250.0, 30.0, rq)) * cr.w;
                    let wv = max(gap, pxw * 0.6);
                    let core = smoothstep(wv, wv * 0.4, cr.d) * min(gap / max(pxw * 0.6, 1e-3), 1.0);
                    sky_c = mix(sky_c, select(vo * 0.6, col * 0.9, above), core * fade_c * far_c * (1.0 - open) * (1.0 - both));
                    // (its edges: thin bright cold lines, white and wide near the impact, thin and clean far out; one
                    // side lit, the other dim, by the piece's tilt; brightest as it forms)
                    let side = normalize(q - cr.cp + vec2<f32>(1e-4, 0.0));
                    let lit = 0.35 + 1.1 * saturate(0.5 + 0.9 * dot(side, tv)) * (0.55 + 0.9 * fh21(floor(cr.cp / 9.0) + vec2<f32>(seed_v(), 1.7)));
                    let ew0 = (0.6 * cr.w + 0.2) * wsc;
                    let ew = max(ew0, pxw * 0.7);
                    let cover = min(ew0 / max(pxw * 0.7, 1e-3), 1.0);
                    let eq = max(cr.d - gap * 0.5, 0.0) / ew;
                    let edge = exp(-eq * eq) * (1.0 - core * 0.7) * (0.35 + 0.65 * cover) * (1.0 - max(open, both));
                    let fresh = 1.0 + 1.6 * exp(-age * 7.0) + 2.5 * hd_flare(time) * exp(-rq / 1400.0);
                    let lineb = (0.45 + 0.35 * day) * fresh * (0.45 + 0.55 * cr.w) * lit * (1.0 + 0.4 * hk) * nk;
                    sky_c = sky_c + vec3<f32>(0.85, 0.92, 1.0) * edge * lineb * 0.8 * fade_c * far_c;
                    // (glints: as the pieces jolt out of true, light runs along their broken edges here and there as
                    // they move)
                    let glk = floor(cr.cp / 11.0);
                    let glh = fh21(glk + vec2<f32>(seed_v() * 0.71, 9.3));
                    let glt = time - SB_SPREAD - 0.02 - 0.5 * fh21(glk + vec2<f32>(3.7, seed_v()));
                    let glint = step(0.55, glh) * exp(-glt * glt / 0.0036) * (1.0 + 2.0 * (glh - 0.55));
                    sky_c = sky_c + sunc * edge * glint * 2.2 * far_c * (1.0 - open) * mix(0.4, 1.0, nk);
                    // (a chip: a flake gone from the edge, its broken face catching light)
                    let chipb = smoothstep(gap * 0.5 + cr.chip + pxw * 0.5, gap * 0.5 + cr.chip * 0.3, cr.d) * step(0.05, cr.chip) * (1.0 - core);
                    sky_c = sky_c + vec3<f32>(0.9, 0.95, 1.0) * chipb * (0.2 + 0.25 * day) * lit * fade_c * far_c * (1.0 - open) * nk;
                    // (glass dust along the breaks: sparks of light where they can be told apart)
                    let gq = floor(q / 1.4);
                    let gh = fh21(gq + vec2<f32>(seed_v() * 0.37, 5.1));
                    let gd = length(q / 1.4 - gq - 0.5);
                    let spark = step(0.985 - 0.02 * hk, gh) * smoothstep(0.3, 0.1, gd) * exp(-cr.d / (2.0 + 3.0 * hk)) * smoothstep(1.2, 0.4, pxw);
                    let tw = 0.5 + 0.5 * sin(time * (9.0 + 14.0 * gh) + gh * 60.0);
                    sky_c = sky_c + sunc * spark * tw * tw * 0.6 * shift_t * fade_c * (1.0 - open);
                    // (a faint glow round it, reading from far off)
                    let glow = exp(-cr.d / max(pxw * 3.0, 4.0)) * 0.05 * fresh * cr.w * nk;
                    sky_c = sky_c + vec3<f32>(0.6, 0.75, 1.0) * glow * fade_c * far_c * (1.0 - open);
                    // (round a hole its broken edge: a thin cold rim of light where the glass was, fading as it heals)
                    if (cr.w > 0.45) {
                        let rim = exp(-cr.d / max(pxw * 0.9, 1.4)) * open0 * (1.0 - onb) * (1.0 - heal);
                        sky_c = sky_c + vec3<f32>(0.75, 0.86, 1.0) * rim * (0.35 + 0.45 * day) * far_c * nk;
                    }
                    // (healing: the sky knitting closed, a pale seam at the edge drawing in)
                    if (heal > 0.0 && heal < 1.0 && open0 > 0.5) {
                        let seam = exp(-abs(min(cr.d, 1.0e4) - heal_d) / max(pxw * 1.5, 2.5)) * (1.0 - onb);
                        sky_c = sky_c + vec3<f32>(0.8, 0.9, 1.0) * seam * 0.55 * (1.0 - heal) * far_c * nk;
                    }
                }
                // (the running tips: white-hot points racing out)
                sky_c = sky_c + vec3<f32>(0.9, 0.95, 1.0) * (exp(-cr.tip / max(pxw * 1.2, 1.5)) * 0.9 + exp(-cr.tip / 30.0) * 0.04) * far_c * mix(0.4, 1.0, nk);
            }
            // (the first crack: a point of light swelling where it will break, a blinding flash there, a halo over the
            // sky round it, the shudder's ring racing out, bright)
            let fk = mix(0.5, 1.0, nk);
            let pre = smoothstep(SB_CRACK - 0.28, SB_CRACK, time) * step(time, SB_CRACK);
            let fl = exp(-max(dc, 0.0) * 3.2) * step(0.0, dc);
            let pt = exp(-dq / max(pxw * 2.5, 5.0));
            sky_c = sky_c + vec3<f32>(1.0, 1.0, 1.05) * fk * (pre * pre * pre * pt * 4.0 + fl * (pt * 9.0 + exp(-dq / 70.0) * 0.8 * exp(-max(dc, 0.0) * 2.0) + exp(-dq / 500.0) * 0.35 * exp(-max(dc, 0.0) * 7.0)));
            sky_c = sky_c + vec3<f32>(0.8, 0.88, 1.0) * ring * 0.2 * fk * far_c;
            col = sky_c;
        }
    }
    // (the opening: the sky drawn up round the island going in, ringing, pressed on, over the first crack's glow:
    // `[lift]`)
    if (have && stage != 1u && sky && time < SB_CRACK + 0.25) {
        col = lf_sky(col, uv, ro, rd, time, C, px_a, skyl, sunc, amb, nk, day, L);
    }
    if (pane_hit) {
        col = pane_c;
    }
    // (the hand in front of the glass (or no glass in the way), over the sky, the land, the panes)
    if (hd.t < 1.0e8) {
        let tq = select(1.0e9, (SB_H - ro.y) / rd.y, rd.y > 0.0 && ro.y < SB_H);
        if (hd.t < tq) {
            col = hd_over(col, hd);
        }
    }
    // ---- the sun glancing off the panes on the land, drawn or laid: their sky's ice, each block's face a little out
    // of true, glittering as the eye moves over them, as broken glass does
    if (have && stage != 1u && (pane_hit || !sky)) {
        let pw = ro + rd * (select(scene_len, near_t, pane_hit) + 0.04);
        let n = i32(sb_w(0u));
        for (var i = 0; i < SB_NS; i = i + 1) {
            if (i >= n) {
                break;
            }
            let b = SB_SH + u32(i) * SB_SW;
            if (time < sb_w(b + 13u)) {
                continue;
            }
            let ps = sb_pose(i, time);
            let th = sb_w(b + 9u);
            let l = sb_qinv(ps.q, pw - ps.c);
            if (abs(l.y + 0.5 * th) > 1.7 || sb_inset(l.xz, i) < 0.5) {
                continue;
            }
            let m = sb_sky(l.x + sb_w(b + 10u), l.z + sb_w(b + 11u));
            // (in quarters of a block: a face's few pixels catching the light, as the game draws textures)
            let cellb = floor((pw + vec3<f32>(0.5, 0.0, 0.5)) * 4.0);
            let hj = vec2<f32>(fh31(cellb + vec3<f32>(3.1, 0.0, f32(i))), fh31(cellb + vec3<f32>(7.7, 1.0, f32(i)))) - 0.5;
            let ns = sb_qrot(ps.q, vec3<f32>(0.0, -1.0, 0.0));
            let t1 = normalize(cross(ns, vec3<f32>(0.0, 0.0, 1.0)) + vec3<f32>(1e-4, 0.0, 0.0));
            let t2 = cross(ns, t1);
            let nj = normalize(ns + (t1 * hj.x + t2 * hj.y) * 0.17);
            let rf = max(dot(reflect(rd, nj), L), 0.0);
            let rs = max(dot(reflect(rd, ns), L), 0.0);
            let fres = 0.04 + 0.96 * pow(1.0 - abs(dot(ns, rd)), 5.0);
            col = col + sunc * (pow(rf, 1400.0) * 5.0 + pow(rs, 60.0) * 0.14 * fres) * select(1.0, 0.3, m == 2);
            break;
        }
    }

    // ---- the dust where each pane landed, and its flash
    var dust = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    if (have) {
        if (stage == 2u) {
            dust = up;
        } else {
            dust = sb_dust(ro, rd, select(dust_far, scene_len, stage == 1u), time, in.position.xy, sunc, amb, L);
            let hdd = hd_dust(ro, rd, select(dust_far, scene_len, stage == 1u), time, in.position.xy, sunc, amb, L);
            dust = vec4<f32>(dust.rgb + dust.a * hdd.rgb, dust.a * hdd.a);
        }
    }
    if (stage == 1u) {
        return SbOut(dust, vec4<f32>(min(scene_len, 6.0e4), 0.0, 0.0, 0.0));
    }
    col = col * dust.a + dust.rgb;
    if (have && time < LF_IN + 3.5) {
        let ld = lf_dust(ro, rd, dust_far, time, in.position.xy, sunc, amb, L);
        col = col * ld.a + ld.rgb;
        let lt = lf_trail(ro, rd, dust_far, time, sunc, amb);
        col = col * lt.a + lt.rgb;
    }
    if (have) {
        // (the panes' ground shock, hidden as much as the dust on the ray hides what is behind)
        let sk = sb_shock(ro, rd, near_t, time, sunc, amb);
        let hide = sqrt(dust.a);
        col = col * mix(1.0, sk.a, hide) + sk.rgb * hide;
        let hs = hd_shock(ro, rd, near_t, time, in.position.xy, hide, sunc, amb);
        col = col * hs.a + hs.rgb;
    }
    if (have && time > SB_COLLAPSE) {
        col = col + sb_glitter_light(ro, rd, near_t, time, px_a, sunc, amb) + sb_spray_light(ro, rd, near_t, time, px_a, sunc, amb);
    }
    if (have) {
        // (each impact's flash: the land lit a moment, cold white)
        let n = i32(sb_w(0u));
        var flash = 0.0;
        for (var i = 0; i <= SB_NS; i = i + 1) {
            let im = sb_impact(i, n);
            let a = time - im.hit;
            if (im.ok && a > 0.0 && a < 1.5) {
                let foot = im.foot;
                let dist = length(foot - ro);
                flash = flash + exp(-a * 5.0) * 0.5 / (1.0 + dist / 400.0);
                // (and the point it struck, glaring)
                let fp = foot + vec3<f32>(0.0, 6.0, 0.0) - ro;
                let ang = acos(clamp(dot(normalize(fp), rd), -1.0, 1.0));
                col = col + vec3<f32>(1.0, 0.98, 0.95) * exp(-a * 14.0) * (exp(-ang / (px_a * 5.0 + 0.0015)) * 2.5 + exp(-ang / 0.03) * 0.25);
            }
        }
        col = col * (1.0 + flash * 0.6) + vec3<f32>(0.8, 0.85, 0.95) * flash * 0.25;
        // (the first crack: all the light jumps, cold, for a breath, and falls back)
        let snap = exp(-max(time - SB_CRACK, 0.0) * 11.0) * step(SB_CRACK, time) * mix(0.3, 0.55, nk);
        col = col * (1.0 + snap) + vec3<f32>(0.85, 0.9, 1.0) * snap * 0.35 * mix(0.2, 1.0, nk);
        // (the sky broken open, the light goes a little cold and dim; as the eye finds them, darker a while)
        let dim = smoothstep(SB_COLLAPSE, SB_COLLAPSE + 6.0, time) * (1.0 - smoothstep(SB_HEAL, SB_HEALED, time));
        let seen_by = smoothstep(SB_LOCK + 0.3, SB_LOCK + 0.7, time) * (1.0 - smoothstep(SB_LOCK + 2.0, SB_LOCK + 7.0, time));
        col = mix(col, col * vec3<f32>(0.86, 0.88, 0.95), dim * 0.55);
        col = col * (1.0 - 0.16 * seen_by);
    }
    col = hd_lens(col, ro, time, in.position.xy, sunc * 0.45 + amb * 0.9);
    col = mix(scene, col, fade_all);
    let srgb = linear_to_srgb(max(col, vec3<f32>(0.0)));
    return SbOut(vec4<f32>(srgb, 1.0), vec4<f32>(0.0));
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return skybreak(in, 0u, vec4<f32>(0.0, 0.0, 0.0, 1.0), vec2<f32>(1.0e9, 1.0)).c;
}

// [half stage]
// QUALITY FAST (lib.rs keeps this only then): the dust at half width and height (fs_half), laid over the full-size
// picture by fs_join; a game without the stage compiles these too and draws fs_main alone, at full size.
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

struct SbHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> SbHalf {
    let o = skybreak(in, 1u, vec4<f32>(0.0, 0.0, 0.0, 1.0), vec2<f32>(1.0e9, 1.0));
    return SbHalf(o.c, o.e);
}
// The half-size stage's dust at this pixel (its ray `len` blocks): its four nearest pixels, each weighed by how near it
// is and how near the depth it was marched to is to this pixel's (a joint bilateral upsample).
fn sb_up(pos: vec2<f32>, len: f32) -> vec4<f32> {
    let hs = vec2<i32>(textureDimensions(half_picture));
    let h = floor(pos) * 0.5 - 0.25;
    let i0 = vec2<i32>(floor(h));
    let f = h - floor(h);
    let lp = min(len, 6.0e4);
    var acc = vec4<f32>(0.0);
    var sw = 0.0;
    var near_dz = 1.0e9;
    var near_c = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    for (var k = 0; k < 4; k = k + 1) {
        let o = vec2<i32>(k & 1, k >> 1u);
        let q = clamp(i0 + o, vec2<i32>(0), hs - vec2<i32>(1));
        let c = textureLoad(half_picture, q, 0);
        let e = textureLoad(half_extra, q, 0);
        let bw = select(1.0 - f.x, f.x, o.x == 1) * select(1.0 - f.y, f.y, o.y == 1);
        let dz = abs(e.x - lp) / max(lp, 1.0);
        let w = bw * exp(-dz * 24.0);
        acc = acc + c * w;
        sw = sw + w;
        if (dz < near_dz) {
            near_dz = dz;
            near_c = c;
        }
    }
    if (sw < 1.0e-3) {
        return near_c;
    }
    return acc / sw;
}
@fragment
fn fs_join(in: StageIn) -> @location(0) vec4<f32> {
    let d = depth_at(in.uv);
    let len = select(1.0e9, length(world_offset(in.uv, d)), !is_sky(d));
    return skybreak(in, 2u, sb_up(in.position.xy, len), vec2<f32>(1.0e9, 1.0)).c;
}
// [end half stage]
