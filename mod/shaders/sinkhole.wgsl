// Orbital Laser's post pass for the Sinkhole (laser 8). Like the Crystal Bloom's, the mod builds it from
// shaders/strike.wgsl up to its fs_main (the helpers: the noise, rot_axis, project_rel, mh, ign) less the other lasers'
// own functions, followed by this file, and sets it for a sinkhole strike only. Validate with tools/check-shader.sh.

// ---- laser 8: the sinkhole ----------------------------------------------------------------------------------------
// No beam, nothing from the sky. The land round the target trembles, birds go up off it, hairline cracks race out over
// it, radiating and branching; a patch in the middle gives (real blocks), the cracks round the slabs it will break into
// open; then it caves in from the middle out, ring by ring: each slab of land (grass over dirt over stone) strains,
// tilts and drops away into the pit, the dust boiling up out of it and rolling out low over the land, and the pit is
// left: dark, sheer, down to bedrock, water pouring over its edge where it cut a river or a lake.
// strike/sinkhole.rs cuts the same rings and slabs (ShGeo) and hands them over as the table below (sh_table); it digs
// each slab's land SH_DIG_AHEAD before it lets go, while this pass already draws the slab over it, so nothing is seen
// open before it falls: keep the SH_* and the table in step.
const SH_R: f32 = 112.0;           // the pit's mean radius at the top (the rim wanders, sh_rim)
const SH_GIVE: f32 = 6.0;          // the middle gives,
const SH_SAG: f32 = 7.3;           // sags,
const SH_C0: f32 = 8.6;            // and the collapse sets out from the middle (sh_front)
const SH_LEAD: f32 = 0.45;         // a slab drawn this long before it lets go, straining in place,
const SH_FALL: f32 = 3.2;          // and gone this long after, deep in the pit
const SH_DEEP0: f32 = 16.0;        // the pit dug on down to bedrock from here (until then it is 25 deep)
const SH_END: f32 = 34.0;          // the dust gone
const SH_LEN: f32 = 40.0;          // the strike's length (lasers.rs): the pit's dark fades out over its last SH_FADE
const SH_FADE: f32 = 9.0;
const SH_DIG: f32 = 0.1;           // a slab's land dug this long before it lets go (sinkhole.rs's SH_DIG_AHEAD)
const SH_SPURTS: i32 = 10;         // the cracks race out in spurts (sinkhole.rs's sh_spurts), each over SH_SPURT
const SH_SPURT: f32 = 0.2;
const SH_BIRDS: i32 = 28;

// ---- the table (strike/sinkhole.rs's sh_table): see SH_RG.. there ----------------------------------------------
const SH_RG: u32 = 8u;
const SH_RW: u32 = 5u;
const SH_WF: u32 = 64u;
const SH_SB: u32 = 96u;
const SH_SW: u32 = 24u;
const SH_MAT: u32 = 7936u;         // the materials (sh_land.rs's MATS), two words each
const SH_GRID: u32 = 8192u;        // the land's columns (sh_land.rs): SH_GW by SH_GW from the target's less SH_G
const SH_G: i32 = 134;
const SH_GW: i32 = 269;
fn sh_w(i: u32) -> f32 {
    if (i < arrayLength(&mod_data)) {
        return bitcast<f32>(mod_data[i]);
    }
    return 0.0;
}
fn sh_count() -> i32 {
    if (arrayLength(&mod_data) < SH_SB) {
        return 0;
    }
    return i32(sh_w(0u));
}
fn sh_rim(a: f32) -> f32 {
    return SH_R * (1.0 + 0.07 * sin(3.0 * a + sh_w(2u)) + 0.04 * sin(5.0 * a + sh_w(3u)) + 0.025 * sin(11.0 * a + sh_w(4u))
        + 0.012 * sin(23.0 * a + sh_w(5u)));
}
fn sh_ring_r(j: i32, a: f32, rim: f32) -> f32 {
    let nr = i32(sh_w(1u));
    if (j <= 0) {
        return 0.0;
    }
    if (j >= nr) {
        return rim;
    }
    let b = SH_RG + u32(j) * SH_RW;
    return sh_w(b) * rim / SH_R + 2.0 * sin(7.0 * a + sh_w(b + 1u));
}
// When the collapse reaches r out (sinkhole.rs's sh_front), and how far out it has reached at `t` (its inverse).
fn sh_front(r: f32) -> f32 {
    if (r < 30.0) {
        return SH_C0 + 0.9 * r / 30.0;
    }
    return SH_C0 + 2.0 + 4.4 * pow(clamp((r - 30.0) / (SH_R - 30.0), 0.0, 1.4), 0.75);
}
fn sh_reached(t: f32) -> f32 {
    if (t < SH_C0) {
        return 0.0;
    }
    if (t < SH_C0 + 0.9) {
        return 30.0 * (t - SH_C0) / 0.9;
    }
    if (t < SH_C0 + 2.0) {
        return 30.0;
    }
    return 30.0 + (SH_R - 30.0) * pow((t - SH_C0 - 2.0) / 4.4, 1.0 / 0.75);
}
// The slab the land at polar (r, a) from the middle is part of (-1 outside the rim), and the distances from it to its
// ring's edges and its sector's (in blocks): x the ring's slab index, y its edges' nearest, z when it lets go.
fn sh_slab_at(r: f32, a: f32, rim: f32, seed: u32) -> vec3<f32> {
    if (r >= rim) {
        return vec3<f32>(-1.0, r - rim, 0.0);
    }
    let nr = i32(sh_w(1u));
    var j = 0;
    loop {
        if (j + 1 >= nr || r < sh_ring_r(j + 1, a, rim)) {
            break;
        }
        j = j + 1;
    }
    let r0 = sh_ring_r(j, a, rim);
    let r1 = sh_ring_r(j + 1, a, rim);
    let b = SH_RG + u32(j) * SH_RW;
    let n = i32(sh_w(b + 2u));
    let th0 = sh_w(b + 3u);
    let off = i32(sh_w(b + 4u));
    let u = fract((a - th0) / TAU) * f32(n);
    let m0 = min(i32(floor(u)), n - 1);
    let jit0 = 0.35 * (mh(u32(m0 % n), seed, 0x710u + u32(j)) - 0.5);
    let jit1 = 0.35 * (mh(u32((m0 + 1) % n), seed, 0x710u + u32(j)) - 0.5);
    var m = m0;
    var e0 = f32(m0) + jit0;
    var e1 = f32(m0 + 1) + jit1;
    if (u < e0) {
        m = (m0 + n - 1) % n;
        e1 = e0;
        e0 = f32(m0 - 1) + 0.35 * (mh(u32((m0 + n - 1) % n), seed, 0x710u + u32(j)) - 0.5);
    } else if (u >= e1) {
        m = (m0 + 1) % n;
        e0 = e1;
        e1 = f32(m0 + 2) + 0.35 * (mh(u32((m0 + 2) % n), seed, 0x710u + u32(j)) - 0.5);
    }
    let side = min(u - e0, e1 - u) / f32(n) * TAU * r;
    let ring = select(min(r - r0, r1 - r), r1 - r, j == 0);
    let k = off + m;
    return vec3<f32>(f32(k), min(side, ring), sh_w(SH_SB + u32(k) * SH_SW + 6u));
}

// ---- a slab: a convex block of land (its corners' quad, grown to cover its curved edges; its ground's plane on top;
//      flat underneath), moving as it strains, tilts and falls -----------------------------------------------------------
struct ShPose {
    o: vec3<f32>,      // its ground's middle where it now is, relative to the camera
    pv: vec3<f32>,     // the edge it tips over, relative to the camera, before it moves
    er: vec3<f32>,     // out from the pit's middle, and along its ring
    et: vec3<f32>,
    phi: f32,          // how far it has tipped (its inner edge down), and turned about its own up
    psi: f32,
    drop: vec3<f32>,   // how far it has dropped and slid in
}
fn sh_corner(r: f32, th: f32) -> vec2<f32> {
    return vec2<f32>(cos(th), sin(th)) * max(r, 0.6);
}
// Slab k's pose `s` seconds after it lets go (s < 0: straining in place), C the pit's middle relative to the camera.
fn sh_pose(b: u32, k: i32, s: f32, C: vec3<f32>) -> ShPose {
    let c0 = sh_corner(sh_w(b + 2u), sh_w(b));
    let c1 = sh_corner(sh_w(b + 3u), sh_w(b + 1u));
    let c2 = sh_corner(sh_w(b + 5u), sh_w(b + 1u));
    let c3 = sh_corner(sh_w(b + 4u), sh_w(b));
    let m = (c0 + c1 + c2 + c3) * 0.25;
    let am = 0.5 * (sh_w(b) + sh_w(b + 1u));
    let er2 = vec2<f32>(cos(am), sin(am));
    var p: ShPose;
    p.er = vec3<f32>(er2.x, 0.0, er2.y);
    p.et = vec3<f32>(-er2.y, 0.0, er2.x);
    let ytop = sh_w(b + 7u);
    let thick = sh_w(b + 10u);
    let half_r = 0.5 * (0.5 * (sh_w(b + 4u) + sh_w(b + 5u)) - 0.5 * (sh_w(b + 2u) + sh_w(b + 3u)));
    let O = C + vec3<f32>(m.x, ytop, m.y);
    p.pv = O + p.er * half_r - vec3<f32>(0.0, thick, 0.0);
    let fk = f32(k);
    if (s < 0.0) {
        // dug out under it, still in place: exactly where the land it stands in for was (the hand-off unseen)
        p.phi = 0.0;
        p.psi = 0.0;
        p.drop = vec3<f32>(0.0);
    } else {
        // let go: a lurch, then tipping in over its outer edge faster and faster as it drops, sliding in, turning a
        // little
        let l = smoothstep(0.0, 0.3, s);
        p.phi = min(0.03 * l + 0.5 * sh_w(b + 12u) * s * s, 1.5);
        p.psi = sh_w(b + 13u) * s * s;
        p.drop = vec3<f32>(0.0, -0.45 * l - 0.5 * sh_w(b + 11u) * s * s, 0.0) - p.er * sh_w(b + 14u) * s * s;
    }
    p.o = O;
    return p;
}
// Into the slab's own frame (its ground's middle at the origin, along the world's axes as it lay): a point relative to
// the camera, and a direction.
fn sh_to(p: ShPose, x: vec3<f32>) -> vec3<f32> {
    let q = rot_axis(x - p.drop - p.pv, p.et, -p.phi) + p.pv - p.o;
    return rot_axis(q, vec3<f32>(0.0, 1.0, 0.0), -p.psi);
}
fn sh_from(p: ShPose, q: vec3<f32>) -> vec3<f32> {
    return rot_axis(rot_axis(q, vec3<f32>(0.0, 1.0, 0.0), p.psi) + p.o - p.pv, p.et, p.phi) + p.pv + p.drop;
}
fn sh_dir_to(p: ShPose, v: vec3<f32>) -> vec3<f32> {
    return rot_axis(rot_axis(v, p.et, -p.phi), vec3<f32>(0.0, 1.0, 0.0), -p.psi);
}
fn sh_dir_from(p: ShPose, v: vec3<f32>) -> vec3<f32> {
    return rot_axis(rot_axis(v, vec3<f32>(0.0, 1.0, 0.0), p.psi), p.et, p.phi);
}
// The view ray (o + t d, in the slab's frame) through slab b: x where it enters, y where it leaves, z which face it
// enters by (0 top, 1 bottom, 2.. the sides), w unused.
fn sh_hit(b: u32, o: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    let c = array<vec2<f32>, 4>(sh_corner(sh_w(b + 2u), sh_w(b)), sh_corner(sh_w(b + 3u), sh_w(b + 1u)),
        sh_corner(sh_w(b + 5u), sh_w(b + 1u)), sh_corner(sh_w(b + 4u), sh_w(b)));
    let m = (c[0] + c[1] + c[2] + c[3]) * 0.25;
    var t0 = -1.0e9;
    var t1 = 1.0e9;
    var face = -1.0;
    // the top: its ground's plane; the bottom: flat
    let sx = sh_w(b + 8u);
    let sz = sh_w(b + 9u);
    let nt = vec3<f32>(-sx, 1.0, -sz);
    let thick = sh_w(b + 10u);
    for (var i = 0; i < 6; i = i + 1) {
        var n = nt;
        var w = 0.0;
        if (i == 1) {
            n = vec3<f32>(0.0, -1.0, 0.0);
            w = thick;
        } else if (i >= 2) {
            let a = c[i - 2] - m;
            let e = c[(i - 1) % 4] - m - a;
            var n2 = normalize(vec2<f32>(e.y, -e.x) + vec2<f32>(1.0e-7));
            if (dot(n2, a) < 0.0) {
                n2 = -n2;
            }
            let grow = 1.0 + select(0.0, sh_w(b + 16u), i == 2) + select(0.0, sh_w(b + 17u), i == 4);
            n = vec3<f32>(n2.x, 0.0, n2.y);
            w = dot(n2, a) + grow;
        }
        let den = dot(n, d);
        let num = w - dot(n, o);
        if (abs(den) < 1.0e-7) {
            if (num < 0.0) {
                return vec3<f32>(1.0, 0.0, -1.0);
            }
            continue;
        }
        let tt = num / den;
        if (den < 0.0) {
            if (tt > t0) {
                t0 = tt;
                face = f32(i);
            }
        } else {
            t1 = min(t1, tt);
        }
    }
    return vec3<f32>(t0, t1, face);
}

// The view ray (o + t d, in slab b's frame) through the blocks of the land it carries (slab k's columns of the land's
// square, `off` taking its frame into the square's), from tn to tf: x the distance to the block it hits (1e9 none),
// yzw the face's normal in its frame; and the block's colour (sRGB) and the pixel's size there for `pw0` a pixel's
// angle.
struct ShVox {
    t: f32,
    n: vec3<f32>,
    c: vec3<f32>,
}
fn sh_vox(b: u32, k: i32, o: vec3<f32>, d: vec3<f32>, off: vec3<f32>, t_max: f32, px_a: f32) -> ShVox {
    var v: ShVox;
    v.t = 1.0e9;
    let lo = vec3<f32>(sh_w(b + 18u), sh_w(b + 22u), sh_w(b + 19u));
    let hi = vec3<f32>(sh_w(b + 20u) + 1.0, sh_w(b + 23u), sh_w(b + 21u) + 1.0);
    let P = o + off;
    let inv = 1.0 / select(d, vec3<f32>(1.0e-7), abs(d) < vec3<f32>(1.0e-7));
    let ta = (lo - P) * inv;
    let tb = (hi - P) * inv;
    let tn3 = min(ta, tb);
    let tf3 = max(ta, tb);
    let tn = max(max(tn3.x, tn3.y), max(tn3.z, 0.0));
    let tf = min(min(tf3.x, tf3.y), min(tf3.z, t_max));
    if (tf <= tn) {
        return v;
    }
    let ylo = sh_w(b + 22u);
    var t = tn + 1.0e-4;
    let p0 = P + d * t;
    var cell = floor(p0);
    let stp = sign(d);
    let tdel = abs(inv);
    var tnext = (cell + max(stp, vec3<f32>(0.0)) - P) * inv;
    // (which axis it last stepped along: the face it enters by; at the start, the box's face it came in by)
    var axis = 1;
    if (tn3.x >= tn3.y && tn3.x >= tn3.z) {
        axis = 0;
    } else if (tn3.z >= tn3.y) {
        axis = 2;
    }
    var lastc = vec2<i32>(-99999);
    var w = vec2<u32>(0u);
    for (var i = 0; i < 160; i = i + 1) {
        if (t > tf) {
            break;
        }
        let cc = vec2<i32>(i32(cell.x), i32(cell.z));
        if (any(cc != lastc)) {
            w = sh_colw(cc.x, cc.y);
            lastc = cc;
        }
        if (w.x != 0u) {
            let blk = sh_cell(w, k, cell, ylo);
            if (blk.x != 0u) {
                var n = vec3<f32>(0.0);
                if (axis == 0) {
                    n.x = -stp.x;
                } else if (axis == 1) {
                    n.y = -stp.y;
                } else {
                    n.z = -stp.z;
                }
                v.t = t;
                v.n = n;
                let f = P + d * t - cell;
                v.c = sh_block_col(blk, w, cell, n, clamp(f, vec3<f32>(0.0), vec3<f32>(0.9999)), t * px_a);
                return v;
            }
        }
        // (on to the next cell)
        if (tnext.x < tnext.y && tnext.x < tnext.z) {
            t = tnext.x;
            tnext.x = tnext.x + tdel.x;
            cell.x = cell.x + stp.x;
            axis = 0;
        } else if (tnext.y < tnext.z) {
            t = tnext.y;
            tnext.y = tnext.y + tdel.y;
            cell.y = cell.y + stp.y;
            axis = 1;
        } else {
            t = tnext.z;
            tnext.z = tnext.z + tdel.z;
            cell.z = cell.z + stp.z;
            axis = 2;
        }
    }
    return v;
}

// The land's colours, a block at a time: grass, its side, dirt, stone in strata, deepslate deep down, broken rock under.
fn sh_block_tint(q: vec3<f32>, k: f32) -> f32 {
    return 0.86 + 0.28 * fh31(floor(q) + vec3<f32>(k * 17.0, 0.0, 0.0));
}
fn sh_earth(dtop: f32, face: f32, q: vec3<f32>, k: f32, day: f32) -> vec3<f32> {
    let bt = sh_block_tint(q, k);
    if (face < 0.5) {
        let g = vec3<f32>(0.17, 0.31, 0.11) * (0.85 + 0.3 * fvnoise(q.xz * 0.25 + vec2<f32>(k)));
        return g * bt;
    }
    if (face > 0.5 && face < 1.5) {
        return vec3<f32>(0.11, 0.10, 0.095) * bt;
    }
    if (dtop < 0.9) {
        return select(vec3<f32>(0.25, 0.18, 0.12), vec3<f32>(0.19, 0.3, 0.1), dtop < 0.3 + 0.25 * fh21(floor(q.xz))) * bt;
    }
    if (dtop < 4.0 + 1.5 * fh21(floor(q.xz) + vec2<f32>(k))) {
        return vec3<f32>(0.27, 0.19, 0.13) * bt;
    }
    // stone, in bands (andesite, tuff, granite now and then), deepslate under it
    let band = floor((dtop + 0.7 * fvnoise(q.xz * 0.2)) / 3.0);
    let hb = fh21(vec2<f32>(band, k * 0.37));
    var st = vec3<f32>(0.40, 0.395, 0.385);
    if (hb > 0.82) {
        st = vec3<f32>(0.46, 0.33, 0.28);
    } else if (hb > 0.66) {
        st = vec3<f32>(0.33, 0.34, 0.31);
    } else if (hb < 0.15) {
        st = vec3<f32>(0.5, 0.5, 0.49);
    }
    let ore = step(0.985, fh31(floor(q) + vec3<f32>(3.0, k, 1.0)));
    st = mix(st, vec3<f32>(0.08, 0.08, 0.08), ore);
    return mix(st, vec3<f32>(0.2, 0.2, 0.22), smoothstep(10.0, 16.0, dtop)) * bt;
}

// ---- the cracks: a network racing out over the land from the middle, branching, and the slabs' outlines opening up
//      before they go (a Voronoi of cells stretched out along the radius, so most run out from the middle) ------------
fn sh_net(q: vec2<f32>, er: vec2<f32>) -> vec2<f32> {
    // in a frame along the radius and across it, cells longer along it
    let u = vec2<f32>(dot(q, er), dot(q, vec2<f32>(-er.y, er.x))) * vec2<f32>(0.075, 0.14);
    let w = u + 0.35 * vec2<f32>(fvnoise(u * 1.7 + vec2<f32>(3.1, 1.2)), fvnoise(u * 1.7 + vec2<f32>(7.4, 5.3)));
    let i = floor(w);
    let f = w - i;
    var d1 = 9.0;
    var d2 = 9.0;
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let g = vec2<f32>(f32(x), f32(y));
            let h = vec2<f32>(fh21(i + g), fh21(i + g + vec2<f32>(19.7, 4.1)));
            let d = length(g + h - f);
            if (d < d1) {
                d2 = d1;
                d1 = d;
            } else if (d < d2) {
                d2 = d;
            }
        }
    }
    // (the distance to the nearest edge, in blocks, roughly; and a value along it)
    return vec2<f32>((d2 - d1) * 6.0, fh21(i));
}

// ---- the land as it really is (sh_land.rs): each column's ground, the blocks on it, under it and deeper, the snow on
//      it, the trunk and leaves of a tree standing on it, and the slab it is part of ------------------------------------
// Column (ci, ck) of the land's square: its two words (0, 0: not read, or outside it).
fn sh_colw(ci: i32, ck: i32) -> vec2<u32> {
    if (ci < 0 || ck < 0 || ci >= SH_GW || ck >= SH_GW) {
        return vec2<u32>(0u);
    }
    let i = SH_GRID + 2u * u32(ck * SH_GW + ci);
    if (i + 1u >= arrayLength(&mod_data)) {
        return vec2<u32>(0u);
    }
    return vec2<u32>(mod_data[i], mod_data[i + 1u]);
}
// Its ground's top, from the target's ground (one above its highest ground block).
fn sh_col_h(w: vec2<u32>) -> i32 {
    return i32(w.x & 511u) - 256;
}
// A material's colours (sRGB): x its top's, y its sides'; and its kind (0 plain, 1 leaves, 2 log, 3 water, 4 grassy) and
// how much each block of it varies.
struct ShMat {
    top: vec3<f32>,
    side: vec3<f32>,
    kind: u32,
    var_: f32,
}
fn sh_mat(m: u32) -> ShMat {
    var o: ShMat;
    let i = SH_MAT + 2u * m;
    var a = 0x00646e7au;
    var b = 0x2e646e7au;
    if (i + 1u < arrayLength(&mod_data)) {
        a = mod_data[i];
        b = mod_data[i + 1u];
    }
    o.top = vec3<f32>(f32(a & 255u), f32((a >> 8u) & 255u), f32((a >> 16u) & 255u)) / 255.0;
    o.side = vec3<f32>(f32(b & 255u), f32((b >> 8u) & 255u), f32((b >> 16u) & 255u)) / 255.0;
    o.kind = a >> 24u;
    o.var_ = f32(b >> 24u) / 255.0;
    return o;
}
// What block of slab k is at cell c of the land's square (y from the target's ground), given its column's words and its
// underside `ylo`: 0 none; else 1 + the material, the second the cell's part (0 ground's top block, 1 deeper ground,
// 2 trunk, 3 leaves).
fn sh_cell(w: vec2<u32>, k: i32, c: vec3<f32>, ylo: f32) -> vec2<u32> {
    if (w.x >> 31u == 0u || i32((w.x >> 21u) & 511u) != k + 1) {
        return vec2<u32>(0u);
    }
    let y = i32(c.y);
    let g = sh_col_h(w) - 1;
    // (its underside broken, a block or two either way)
    let lo = i32(ylo) + i32(fh21(c.xz) * 2.5);
    if (y < lo) {
        return vec2<u32>(0u);
    }
    if (y <= g) {
        let dd = g - y;
        if (dd == 0) {
            return vec2<u32>(1u + ((w.x >> 9u) & 63u), 0u);
        }
        if (dd <= 3) {
            return vec2<u32>(1u + ((w.x >> 15u) & 63u), 1u);
        }
        if (dd <= 7) {
            return vec2<u32>(1u + (w.y & 63u), 1u);
        }
        // (deeper: stone, deepslate deeper still)
        return vec2<u32>(select(13u, 19u, dd > 16 + i32(fh21(c.xz + vec2<f32>(5.0)) * 4.0)), 1u);
    }
    let up = y - g;
    let log = (w.y >> 6u) & 63u;
    if (log > 0u && up <= i32((w.y >> 12u) & 15u)) {
        return vec2<u32>(1u + log, 2u);
    }
    let leaf = (w.y >> 16u) & 63u;
    if (leaf > 0u && up >= i32((w.y >> 22u) & 15u) && up <= i32((w.y >> 26u) & 15u)) {
        // (leaves, ragged: a few gaps in them)
        if (fh31(c + vec3<f32>(0.0, 31.0, 0.0)) < 0.16) {
            return vec2<u32>(0u);
        }
        return vec2<u32>(1u + leaf, 3u);
    }
    return vec2<u32>(0u);
}
// A block's colour on face `fn` (its normal, along an axis) at `f` within it (0..1 each way), at cell `c`, as the game's
// own blocks look: the material's colour varying a little block to block and texel to texel (the texels fading out
// once they are smaller than a pixel: `pw` a pixel's size, in blocks), the grass's fringe on the sides of its block,
// snow on it, bark streaks and log rings. sRGB.
fn sh_block_col(cell: vec2<u32>, w: vec2<u32>, c: vec3<f32>, fnrm: vec3<f32>, f: vec3<f32>, pw: f32) -> vec3<f32> {
    let m = sh_mat(cell.x - 1u);
    let topf = fnrm.y > 0.5;
    var col = select(m.side, m.top, topf || fnrm.y < -0.5);
    // (the texel it is in on that face)
    var uv = f.xz;
    if (abs(fnrm.x) > 0.5) {
        uv = f.zy;
    } else if (abs(fnrm.z) > 0.5) {
        uv = f.xy;
    }
    let tx = floor(uv * 16.0);
    let tex = fh31(vec3<f32>(tx, 7.0) + c * vec3<f32>(1.31, 2.17, 0.73)) - 0.5;
    let texk = 1.0 - smoothstep(0.03, 0.09, pw);
    if (m.kind == 4u && cell.y == 0u && !topf && fnrm.y > -0.5) {
        // (grassy: its sides the dirt, with the grass's fringe hanging over the top)
        let fringe = 0.82 - 0.12 * step(0.5, fh21(vec2<f32>(tx.x, c.x + c.z * 3.0)));
        if (uv.y > fringe) {
            col = m.top;
        }
    }
    if (m.kind == 2u && !(topf || fnrm.y < -0.5)) {
        // (bark: streaks up the log)
        col = col * (0.85 + 0.3 * fh21(vec2<f32>(tx.x, c.x * 7.0 + c.z)) * texk + 0.15 * (1.0 - texk));
    }
    if (cell.y == 0u && (w.x >> 30u & 1u) == 1u) {
        // (snow lying on it: its top white, a rim of white down its sides)
        if (topf || uv.y > 0.86) {
            col = vec3<f32>(0.95, 0.98, 0.99);
        }
    }
    let blockv = (fh31(c) - 0.5) * m.var_;
    let leafk = select(1.0, 1.8, m.kind == 1u);
    return col * (1.0 + blockv + tex * m.var_ * 0.9 * leafk * texk);
}

// ---- the cracks: they race out from the middle in spurts (sinkhole.rs's sh_spurts), along the lines the slabs will
//      break on, thin at first, widening into dark gaps as the slab each side is about to go ----------------------------
fn sh_spurt_t(i: i32, seed: u32) -> f32 {
    return 1.0 + 6.4 * (f32(i) + 0.15 + 0.7 * mh(u32(i), seed, 0x7c0u)) / f32(SH_SPURTS);
}
fn sh_spurt_r(i: i32) -> f32 {
    return SH_R * 1.3 * pow(f32(i + 1) / f32(SH_SPURTS), 0.85);
}
// When the cracks reach `rr` out (the radius over the lag at that angle): in the spurt that runs over it, slowing as it
// stops.
fn sh_crack_at(rr: f32, seed: u32) -> f32 {
    let u = pow(clamp(rr / (SH_R * 1.3), 0.0, 1.0), 1.0 / 0.85) * f32(SH_SPURTS);
    let i = clamp(i32(ceil(u)) - 1, 0, SH_SPURTS - 1);
    let r0 = select(0.0, sh_spurt_r(i - 1), i > 0);
    let f = saturate((rr - r0) / max(sh_spurt_r(i) - r0, 1.0e-3));
    return sh_spurt_t(i, seed) + SH_SPURT * (1.0 - sqrt(1.0 - f));
}
// The nearest edge of the slab at polar (r, a), as sh_slab_at finds it: x the slab (-1 outside the rim), y the distance
// to the edge, z which side of the edge its slab is (1: the side that drops first), w along the edge (in blocks); and
// the edge's normal (xz).
struct ShEdge {
    k: f32,
    d: f32,
    first: f32,
    along: f32,
    n: vec2<f32>,
    t: f32,
}
fn sh_edge(r: f32, a: f32, rim: f32, seed: u32) -> ShEdge {
    var e: ShEdge;
    e.k = -1.0;
    if (r >= rim) {
        return e;
    }
    let nr = i32(sh_w(1u));
    var j = 0;
    loop {
        if (j + 1 >= nr || r < sh_ring_r(j + 1, a, rim)) {
            break;
        }
        j = j + 1;
    }
    let r0 = sh_ring_r(j, a, rim);
    let r1 = sh_ring_r(j + 1, a, rim);
    let b = SH_RG + u32(j) * SH_RW;
    let n = i32(sh_w(b + 2u));
    let th0 = sh_w(b + 3u);
    let off = i32(sh_w(b + 4u));
    let u = fract((a - th0) / TAU) * f32(n);
    let m0 = min(i32(floor(u)), n - 1);
    let jit0 = 0.35 * (mh(u32(m0 % n), seed, 0x710u + u32(j)) - 0.5);
    let jit1 = 0.35 * (mh(u32((m0 + 1) % n), seed, 0x710u + u32(j)) - 0.5);
    var m = m0;
    var e0 = f32(m0) + jit0;
    var e1 = f32(m0 + 1) + jit1;
    if (u < e0) {
        m = (m0 + n - 1) % n;
        e1 = e0;
        e0 = f32(m0 - 1) + 0.35 * (mh(u32((m0 + n - 1) % n), seed, 0x710u + u32(j)) - 0.5);
    } else if (u >= e1) {
        m = (m0 + 1) % n;
        e0 = e1;
        e1 = f32(m0 + 2) + 0.35 * (mh(u32((m0 + 2) % n), seed, 0x710u + u32(j)) - 0.5);
    }
    let ds0 = (u - e0) / f32(n) * TAU * r;
    let ds1 = (e1 - u) / f32(n) * TAU * r;
    let din = select(1.0e4, r - r0, j > 0);
    let dout = r1 - r;
    let k = off + m;
    e.k = f32(k);
    e.t = sh_w(SH_SB + u32(k) * SH_SW + 6u);
    let er = vec2<f32>(cos(a), sin(a));
    let et = vec2<f32>(-er.y, er.x);
    e.d = min(min(ds0, ds1), min(din, dout));
    if (e.d == dout) {
        // (its outer edge: the slab inside goes first)
        e.n = er;
        e.first = 1.0;
        e.along = a * r1;
    } else if (e.d == din) {
        e.n = er;
        e.first = 0.0;
        e.along = a * r0;
    } else {
        // (a side: which side drops first, the edge's own)
        let edge = select(m + 1, m, ds0 < ds1);
        let lead = step(0.5, mh(u32(edge % n), seed, 0x7c5u + u32(j)));
        e.n = et;
        e.first = select(1.0 - lead, lead, ds0 < ds1);
        e.along = r + 37.0 * f32(edge);
    }
    return e;
}

// ---- dust: what the collapse throws up out of the pit and rolls out low over the land, and the puff of the give --
fn sh_dust(p: vec3<f32>, time: f32, rimm: f32) -> f32 {
    let r = length(p.xz);
    var d = 0.0;
    // the give's puff, then the sag's
    let tg = time - SH_GIVE;
    if (tg > 0.0 && tg < 6.0) {
        let rr = 14.0 + 10.0 * (1.0 - exp(-tg * 1.5));
        d = d + exp(-tg * 0.7) * smoothstep(rr, rr * 0.5, r) * smoothstep(10.0 + 6.0 * tg, 0.0, p.y + 4.0) * 0.9;
    }
    let tc = time - SH_C0;
    if (tc > 0.0) {
        let env = smoothstep(0.0, 1.5, tc) * (1.0 - smoothstep(12.0, SH_END - SH_C0, tc));
        // out of the pit: boiling up where the land has gone, higher and higher, thinning as it climbs
        let reach = min(sh_reached(time), SH_R * 1.12) + 6.0;
        let H = 18.0 + 75.0 * (1.0 - exp(-tc / 6.0));
        let plume = smoothstep(reach, reach - 25.0, r) * smoothstep(H, H * 0.3, p.y) * smoothstep(-70.0, -20.0, p.y);
        // rolling out over the land, low, from the rim
        let out = rimm + 90.0 * (1.0 - exp(-max(time - (SH_C0 + 3.0), 0.0) / 6.0));
        let hk = 5.0 + 7.0 * smoothstep(rimm, out, r);
        let skirt = smoothstep(rimm - 20.0, rimm, r) * smoothstep(out, out - 40.0, r) * smoothstep(hk, 0.0, p.y) * step(-2.0, p.y) * (1.0 - 0.6 * smoothstep(rimm, out, r));
        let late = 1.0 - smoothstep(4.0, 14.0, tc) * smoothstep(-10.0, 30.0, p.y) * 0.7;
        d = d + env * late * (plume * 1.0 + skirt * 0.6);
    }
    if (d < 0.003) {
        return 0.0;
    }
    let q = p * 0.045 + vec3<f32>(0.0, -time * 0.18, 0.0) + vec3<f32>(time * 0.05, 0.0, 0.0);
    let n = 0.62 * fvnoise3(q) + 0.38 * fvnoise3(q * 2.3 + vec3<f32>(5.1, 1.3 - time * 0.2, 7.7));
    return d * smoothstep(0.32, 0.8, n) * 2.0;
}

fn sinkhole(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let time = now();
    let cam = frame.camera_position.xyz;
    let k = intensity_v();
    let seed = u32(seed_v());
    let px_a = frame.view_params.w / frame.resolution.y;      // (the angle a pixel spans)
    let anc = anchor_xz();
    let gy = target_y();
    let C = vec3<f32>(anc.x, gy, anc.y) - cam;              // the pit's middle, on the target's ground
    let n_slabs = sh_count();
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);

    let d = depth_at(uv);
    let sky = is_sky(d);
    let rel = world_offset(uv, select(d, 0.5, sky));
    var scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    let Q = rel - C;                                          // the scene's point from the pit's middle
    let rq = length(Q.xz);
    let aq = atan2(Q.z, Q.x);
    let rimq = sh_rim(aq);
    let Ls = normalize(select(vec3<f32>(0.3, 1.0, 0.2), sun, sun.y > 0.05));
    let amb = mix(vec3<f32>(0.03, 0.035, 0.05), vec3<f32>(0.32, 0.36, 0.44), day);
    let sunc = vec3<f32>(1.25, 1.18, 1.05) * day;

    // (a pixel's footprint on the land, from the derivatives of where it is: here, in uniform control flow)
    let dQx = dpdx(Q);
    let dQy = dpdy(Q);
    let dy0 = gy - (block_y() + 1.0);                         // the target's ground over its block's top
    let fade = 1.0 - smoothstep(SH_LEN - SH_FADE, SH_LEN, time);
    let fade_e = fade * fade * (3.0 - 2.0 * fade);

    // ---- on the land: the cracks, and the pit's darkness where it has been dug -----------------------------------
    if (!sky && n_slabs > 0 && rq < SH_R * 1.4) {
        let pw = scene_len * px_a;
        // (the land's column here: is this its ground's top?)
        let cw = sh_colw(i32(floor(Q.x + 0.5)) + SH_G, i32(floor(Q.z + 0.5)) + SH_G);
        var on_ground = abs(Q.y) < 3.0;
        if (cw.x >> 31u == 1u) {
            let hy = f32(sh_col_h(cw)) - dy0;
            on_ground = Q.y > hy - 1.05 && Q.y < hy + 0.2;
        }
        // the cracks, along the slabs' edges, from 1 s, racing out in spurts, the fingers running ahead here and
        // lagging there; thin at first, widening, then gaping as the slabs each side are about to go
        if (time > 0.9 && on_ground && time < sh_front(rq) + 0.2) {
            let e = sh_edge(rq, aq, rimq, seed);
            let lag = 0.8 + 0.45 * fvnoise(vec2<f32>(cos(aq), sin(aq)) * 2.3 + vec2<f32>(f32(seed % 97u) * 0.37));
            let age = time - sh_crack_at(rq / lag, seed);
            if (e.k >= 0.0 && age > 0.0 && time < e.t - SH_DIG + 0.02) {
                let o = smoothstep(e.t - 1.9, e.t - 0.1, time);
                var w = 0.06 + 0.42 * pow(saturate(age / 2.2), 0.7) + 0.2 * smoothstep(SH_GIVE - 0.5, SH_GIVE + 1.5, time) + 0.8 * o * o;
                // (the footprint across the crack, from the derivatives; at a silhouette it is huge, and it fades out)
                let n3 = vec3<f32>(e.n.x, 0.0, e.n.y);
                let fp = max(length(vec2<f32>(dot(dQx, n3), dot(dQy, n3))), pw * 0.35);
                // (its edges broken and wandering, less so where a pixel is wider than the wander)
                let wq = Q.xz + vec2<f32>(f32(seed % 61u) * 7.3, 0.0);
                let jag = (fvnoise(wq * 0.42) - 0.5) * (0.5 + 0.9 * w) + (fvnoise(wq * 1.6 + vec2<f32>(4.1, 9.3)) - 0.5) * (0.25 + 0.5 * w) * saturate(1.5 - fp * 1.5);
                let d = e.d + jag;
                // (never thinner on screen than most of a pixel: drawn wider and fainter instead, so it neither
                // breaks up nor shimmers; and faded out far off)
                let wd = max(w, 0.7 * fp);
                let cov = saturate((wd - d) / fp + 0.5) * sqrt(w / wd) * (1.0 - smoothstep(1.5, 4.0, fp)) * (1.0 - smoothstep(380.0, 650.0, scene_len));
                // (the side that drops first stepped down a little, in shadow beside the gap)
                let drop = (0.25 + 0.7 * o) * e.first;
                let band = saturate((w + drop - d) / fp + 0.5) * (1.0 - cov) * step(0.01, drop) * (1.0 - smoothstep(1.5, 4.0, fp));
                // (dust puffing up out of it as it opens, a second or so)
                let puff = exp(-age * 1.6) * saturate((w * 2.5 + 1.5 - e.d) / 1.5);
                col = mix(col, vec3<f32>(0.22, 0.19, 0.16) * (amb + sunc * 0.5), 0.35 * puff * k);
                col = col * (1.0 - 0.45 * band * k);
                col = mix(col, vec3<f32>(0.006, 0.005, 0.005), 0.94 * cov * k);
            }
        }
        // and round the rim once it has gone: the land there torn along it
        let sl = sh_slab_at(rq, aq, rimq, seed);
        if (sl.x < 0.0 && time > sh_front(rimq) && sl.y < 14.0 && on_ground) {
            let wq = Q.xz * 0.08;
            let wob = (fvnoise(wq + vec2<f32>(3.0)) - 0.5) * 5.0;
            let dd = abs(fract((sl.y + wob) / 4.6 + 0.3) - 0.5) * 4.6;
            let w = 0.12 * fvnoise(Q.xz * 0.15 + vec2<f32>(9.0)) * smoothstep(14.0, 4.0, sl.y);
            let fp = max(length(vec2<f32>(length(dQx.xz), length(dQy.xz))) * 0.7, pw * 0.35);
            let wd = max(w, 0.7 * fp);
            let crack = saturate((wd - dd) / fp + 0.5) * (w / max(wd, 1.0e-4)) * (1.0 - smoothstep(1.5, 4.0, fp));
            col = col * (1.0 - 0.88 * crack * k * fade_e);
        }
        // the pit, where it has been dug: dark, darker the deeper, a cold haze down in it; and, until it is dug on down,
        // its floor 25 down hidden in murk; fading slowly away over the strike's last seconds (the real pit's walls
        // darken with depth on their own)
        let into = rimq + 7.0 - rq;
        if (into > 0.0 && Q.y < -2.5 && time > sh_front(rq) - SH_DIG) {
            let dep = -Q.y;
            var dark = pow(smoothstep(2.0, 108.0, dep), 0.7);
            dark = max(dark, smoothstep(13.0, 24.0, dep) * 0.93 * (1.0 - smoothstep(SH_DEEP0 + 2.0, SH_DEEP0 + 7.0, time)));
            let haze = mix(vec3<f32>(0.012, 0.012, 0.014), vec3<f32>(0.05, 0.05, 0.055), day);
            col = mix(col, haze, dark * 0.97 * k * fade_e);
        }
    }

    // ---- the slabs: solid, the nearest drawn, hidden by anything nearer; each from the moment its land is dug, in its
    //      place, as the land it stands in for was (the land's own blocks, when it was read), then letting go ---------
    var hit_t = 1.0e9;
    var hit_c = vec3<f32>(0.0);
    if (n_slabs > 0 && time > SH_C0 - SH_DIG - 0.1 && time < 16.6 + SH_FALL) {
        for (var i = 0; i < n_slabs; i = i + 1) {
            let b = SH_SB + u32(i) * SH_SW;
            let s = time - sh_w(b + 6u);
            if (s < -SH_DIG || s > SH_FALL) {
                continue;
            }
            let ps = sh_pose(b, i, s, C);
            let real = sh_w(b + 15u) > 0.5;
            // (a sphere round it first: round the land it carries, or round its block of ground)
            var cc = ps.o + ps.drop;
            var rad = 0.5 * length(vec2<f32>(sh_w(b + 5u) - sh_w(b + 2u), (sh_w(b + 1u) - sh_w(b)) * sh_w(b + 5u))) + sh_w(b + 10u) + 4.0;
            // (its frame into the land's square)
            let mq = (sh_corner(sh_w(b + 2u), sh_w(b)) + sh_corner(sh_w(b + 3u), sh_w(b + 1u)) + sh_corner(sh_w(b + 5u), sh_w(b + 1u))
                + sh_corner(sh_w(b + 4u), sh_w(b))) * 0.25;
            let off = vec3<f32>(mq.x + 0.5 + f32(SH_G), sh_w(b + 7u) + dy0, mq.y + 0.5 + f32(SH_G));
            if (real) {
                let lo = vec3<f32>(sh_w(b + 18u), sh_w(b + 22u), sh_w(b + 19u));
                let hi = vec3<f32>(sh_w(b + 20u) + 1.0, sh_w(b + 23u), sh_w(b + 21u) + 1.0);
                cc = sh_from(ps, 0.5 * (lo + hi) - off);
                rad = 0.5 * length(hi - lo) + 1.0;
            }
            let tc = dot(cc, rd);
            if (dot(cc, cc) - tc * tc > rad * rad || tc + rad < 0.0 || tc - rad > min(hit_t, scene_len + 1.0)) {
                continue;
            }
            let o = sh_to(ps, vec3<f32>(0.0));
            let dl = sh_dir_to(ps, rd);
            var t_hit = 1.0e9;
            var nl = vec3<f32>(0.0, 1.0, 0.0);
            var base = vec3<f32>(0.0);
            if (real) {
                let vx = sh_vox(b, i, o, dl, off, min(hit_t, scene_len + 0.3), px_a);
                if (vx.t >= 1.0e8) {
                    continue;
                }
                t_hit = vx.t;
                nl = vx.n;
                base = vx.c;
            } else {
                // (its land not read: a block of ground, grass over dirt over stone, its top its ground's plane)
                let h = sh_hit(b, o, dl);
                if (h.y <= h.x || h.x <= 0.0 || h.x >= hit_t || h.x > scene_len + 0.7) {
                    continue;
                }
                t_hit = h.x;
                let q = o + dl * h.x;
                let sx = sh_w(b + 8u);
                let sz = sh_w(b + 9u);
                let dtop = sx * q.x + sz * q.z - q.y;
                nl = normalize(vec3<f32>(-sx, 1.0, -sz));
                if (h.z > 0.5 && h.z < 1.5) {
                    nl = vec3<f32>(0.0, -1.0, 0.0);
                } else if (h.z > 1.5) {
                    let c = array<vec2<f32>, 4>(sh_corner(sh_w(b + 2u), sh_w(b)), sh_corner(sh_w(b + 3u), sh_w(b + 1u)),
                        sh_corner(sh_w(b + 5u), sh_w(b + 1u)), sh_corner(sh_w(b + 4u), sh_w(b)));
                    let fi = i32(h.z) - 2;
                    let e = c[(fi + 1) % 4] - c[fi];
                    var n2 = normalize(vec2<f32>(e.y, -e.x) + vec2<f32>(1.0e-7));
                    let m = (c[0] + c[1] + c[2] + c[3]) * 0.25;
                    if (dot(n2, c[fi] - m) < 0.0) {
                        n2 = -n2;
                    }
                    nl = vec3<f32>(n2.x, 0.0, n2.y);
                }
                base = linear_to_srgb(sh_earth(dtop, h.z, q + ps.o + cam, f32(i), day));
            }
            hit_t = t_hit;
            // (lit as the game lights its blocks: by the face, the top brightest, the sides less, the underside least,
            // turning with the slab; and by the time of day)
            let nw = sh_dir_from(ps, nl);
            let shade = 0.6 * nw.x * nw.x + 0.8 * nw.z * nw.z + select(0.5, 1.0, nw.y > 0.0) * nw.y * nw.y;
            let light = mix(0.16, 1.0, day);
            var c = srgb_to_linear(saturate(base * shade * light));
            // (in the shadow of the pit as it drops, and into its dark)
            let wy = (cam + rd * t_hit).y - gy;
            let pit = smoothstep(2.0, 60.0, -wy);
            c = mix(c, c * 0.25, smoothstep(0.0, 1.0, s) * 0.6);
            c = mix(c, vec3<f32>(0.012, 0.012, 0.014), pow(pit, 0.7) * 0.97);
            hit_c = c;
        }
    }
    if (hit_t < 1.0e8) {
        col = mix(col, hit_c, k);
        scene_len = hit_t;
    }

    // ---- water pouring over the rim where the pit cut a river or a lake ------------------------------------------
    let nwf = i32(sh_w(SH_WF));
    if (n_slabs > 0 && nwf > 0) {
        for (var w = 0; w < min(nwf, 6); w = w + 1) {
            let b = SH_WF + 4u + u32(w) * 4u;
            let ac = sh_w(b);
            let hw = sh_w(b + 1u);
            let ytop = sh_w(b + 2u) - 0.3;
            let s = time - sh_w(b + 3u);
            if (s < 0.0) {
                continue;
            }
            let fall = min(0.5 * 30.0 * s * s, 140.0);
            let Rw = sh_rim(ac) - 1.2;
            // (the sheet: a cylinder round the pit's middle just inside the rim, both its sides)
            let a2 = max(dot(rd.xz, rd.xz), 1.0e-8);
            let bb = -dot(rd.xz, C.xz);
            let cc2 = dot(C.xz, C.xz) - Rw * Rw;
            let disc = bb * bb - a2 * cc2;
            if (disc <= 0.0) {
                continue;
            }
            for (var side = 0; side < 2; side = side + 1) {
                let t = (-bb + select(-1.0, 1.0, side == 1) * sqrt(disc)) / a2;
                if (t <= 0.0 || t > scene_len) {
                    continue;
                }
                let X = rd * t - C;
                let a = atan2(X.z, X.x);
                let da = abs(atan2(sin(a - ac), cos(a - ac)));
                let y = X.y;
                let edge = hw * (0.85 + 0.3 * fvnoise(vec2<f32>(y * 0.1, f32(w) * 3.0)));
                if (da > edge || y > ytop || y < ytop - fall) {
                    continue;
                }
                let along = (a - ac) * Rw;
                let streak = fvnoise(vec2<f32>(along * 1.4, (y + time * 22.0) * 0.08)) * 0.6 + fvnoise(vec2<f32>(along * 3.1, (y + time * 30.0) * 0.21)) * 0.4;
                let alpha = saturate(0.45 + 0.7 * streak) * smoothstep(edge, edge * 0.7, da) * smoothstep(ytop - fall, ytop - fall + 6.0, y);
                let foam = mix(vec3<f32>(0.25, 0.33, 0.4), vec3<f32>(0.8, 0.85, 0.9), streak) * (amb + sunc * 0.6);
                let deep = pow(smoothstep(2.0, 100.0, -y), 0.7);
                col = mix(col, mix(foam, vec3<f32>(0.02, 0.025, 0.03), deep * 0.9), alpha * k * fade_e);
            }
        }
    }

    // ---- the birds going up off the land as it starts to shake, scattering away from it ------------------------------
    if (time > 0.8 && time < 10.0) {
        for (var i = 0; i < SH_BIRDS; i = i + 1) {
            let h = vec3<f32>(mh(u32(i), seed, 0x7b0u), mh(u32(i), seed, 0x7b1u), mh(u32(i), seed, 0x7b2u));
            let t0 = 1.0 + 1.6 * h.x + 0.6 * h.z;
            let s = time - t0;
            if (s < 0.0) {
                continue;
            }
            let a = h.y * TAU;
            let dir = vec3<f32>(cos(a), 0.0, sin(a));
            let start = C + dir * (25.0 + 110.0 * h.z) + vec3<f32>(0.0, 4.0 + 6.0 * h.x, 0.0);
            let pos = start + dir * (9.0 * s) + vec3<f32>(0.0, 6.0 * s - 0.25 * s * s + 1.5 * sin(s * 2.0 + h.x * 6.0), 0.0);
            let dist = length(pos);
            if (dist > scene_len) {
                continue;
            }
            let P = project_rel(pos);
            if (P.z < 0.0) {
                continue;
            }
            let span = max(0.45 / (dist * px_a), 1.2);
            let pxl = (uv - P.xy) * frame.resolution.xy;
            let flap = sin(time * (13.0 + 4.0 * h.x) + h.z * 20.0);
            let wx = abs(pxl.x) / span;
            let yv = pxl.y / span + (0.35 + 0.35 * flap) * (1.0 - wx) - 0.2;
            let m = step(wx, 1.0) * saturate(1.0 - abs(yv) * 1.8 / max(0.25, 1.0 / span));
            col = mix(col, vec3<f32>(0.03, 0.03, 0.035), m * 0.9 * k * (1.0 - smoothstep(7.0, 10.0, time)));
        }
    }

    // ---- the dust, marched along the view ray through where it can be -------------------------------------------
    if (time > SH_GIVE && time < SH_END) {
        let Rb = SH_R * 1.15 + 95.0;
        let a2 = max(dot(rd.xz, rd.xz), 1.0e-8);
        let bb = -dot(rd.xz, C.xz);
        let cc2 = dot(C.xz, C.xz) - Rb * Rb;
        let disc = bb * bb - a2 * cc2;
        if (disc > 0.0) {
            var t0 = (-bb - sqrt(disc)) / a2;
            var t1 = (-bb + sqrt(disc)) / a2;
            let y0 = -70.0;
            let y1 = 100.0;
            if (abs(rd.y) > 1.0e-5) {
                let ya = (C.y + y0) / rd.y;
                let yb = (C.y + y1) / rd.y;
                t0 = max(t0, min(ya, yb));
                t1 = min(t1, max(ya, yb));
            }
            t0 = max(t0, 0.0);
            t1 = min(t1, scene_len);
            if (t1 > t0) {
                let N = 22;
                let dt = (t1 - t0) / f32(N);
                var tr = 1.0;
                var acc = vec3<f32>(0.0);
                let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 61.0, 0.0));
                let rimm = SH_R;
                for (var i = 0; i < N; i = i + 1) {
                    let t = t0 + dt * (f32(i) + j);
                    let p = rd * t - C;
                    let den = sh_dust(p, time, rimm);
                    if (den <= 0.0) {
                        continue;
                    }
                    let a = 1.0 - exp(-den * dt * 0.025);
                    // (lit from above, darker low down and deep in the pit)
                    let up = smoothstep(-40.0, 40.0, p.y);
                    let dc = mix(vec3<f32>(0.05, 0.043, 0.036), vec3<f32>(0.5, 0.44, 0.36), up) * (amb * 1.3 + sunc * 0.55 * up);
                    acc = acc + tr * a * dc;
                    tr = tr * (1.0 - a);
                    if (tr < 0.02) {
                        break;
                    }
                }
                col = mix(col, col * tr + acc, k);
            }
        }
    }

    // ---- a faint dimming of the light while the dust is up -------------------------------------------------------
    let murk = smoothstep(SH_C0, SH_C0 + 3.0, time) * (1.0 - smoothstep(20.0, SH_END, time)) * fade_e;
    col = col * (1.0 - 0.12 * murk * k);
    let srgb = linear_to_srgb(max(col, vec3<f32>(0.0)));
    if (capture() > 2.5) {
        let sp = floor(in.position.xy);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0);
    }
    return vec4<f32>(srgb, 1.0);
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return sinkhole(in);
}
