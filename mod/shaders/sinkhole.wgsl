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
const SH_END: f32 = 34.0;
const SH_BIRDS: i32 = 28;

// ---- the table (strike/sinkhole.rs's sh_table): see SH_RG.. there ----------------------------------------------
const SH_RG: u32 = 8u;
const SH_RW: u32 = 5u;
const SH_WF: u32 = 64u;
const SH_SB: u32 = 96u;
const SH_SW: u32 = 20u;
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
        // straining: settling a little, rocking, shuddering
        let u = saturate((s + SH_LEAD) / SH_LEAD);
        p.phi = 0.03 * u * u + 0.006 * sin(s * 41.0 + fk) * u;
        p.psi = 0.0;
        p.drop = vec3<f32>(0.0, -0.45 * u * u - 0.07 * abs(sin(s * 33.0 + fk * 1.7)) * u, 0.0);
    } else {
        // let go: tipping in over its outer edge faster and faster as it drops, sliding in, turning a little
        p.phi = min(0.03 + 0.5 * sh_w(b + 12u) * s * s, 1.5);
        p.psi = sh_w(b + 13u) * s * s;
        p.drop = vec3<f32>(0.0, -0.45 - 0.5 * sh_w(b + 11u) * s * s, 0.0) - p.er * sh_w(b + 14u) * s * s;
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

    // ---- on the land: the cracks, and the pit's darkness where it has been dug -----------------------------------
    if (!sky && n_slabs > 0 && rq < SH_R * 1.4) {
        let pw = scene_len * px_a;
        let er = Q.xz / max(rq, 1.0e-3);
        // the network racing out from the middle from 1 s, its fingers running ahead here and lagging there
        let fing = 0.75 + 0.5 * fvnoise(vec2<f32>(aq * 6.0, 0.0) + vec2<f32>(f32(seed) * 0.37));
        let front = SH_R * 1.3 * smoothstep(0.8, 6.8, time) * fing;
        var crack = 0.0;
        if (time > 0.8 && rq < front + 4.0 && abs(Q.y) < 3.0 && time < sh_front(rq) + 0.2) {
            let nt = sh_net(Q.xz + vec2<f32>(f32(seed) * 3.1, 0.0), er);
            // (it reaches each edge at its own time, as it races out; then widens)
            let age = (front - rq) / 30.0 - nt.y * 0.5;
            // (not every edge: the network breaks off here and there, as real cracks do)
            let keep = step(0.3, fvnoise(Q.xz * 0.06 + vec2<f32>(f32(seed))));
            let w = clamp(0.03 + 0.07 * age, 0.0, 0.16) * step(0.0, age) * keep * smoothstep(SH_R * 1.4, SH_R * 0.9, rq);
            crack = max(crack, saturate((w - nt.x + pw * 0.5) / max(pw, 0.02)) * min(1.0, w / max(pw * 0.6, 0.01)));
        }
        // the slabs' own outlines opening up as each is about to go
        let sl = sh_slab_at(rq, aq, rimq, seed);
        if (sl.x >= 0.0 && abs(Q.y) < 3.0) {
            let o = smoothstep(sl.z - 1.8, sl.z - 0.15, time) * step(time, sl.z);
            let w = 0.05 + 0.7 * o * o;
            crack = max(crack, saturate((w - sl.y + pw * 0.5) / max(pw, 0.02)) * min(1.0, w / max(pw * 0.6, 0.01)) * step(0.01, o + step(0.0, time - SH_GIVE + 1.5)));
        }
        // and round the rim once it has gone: the land there torn along it
        if (sl.x < 0.0 && time > sh_front(rimq) && sl.y < 14.0 && abs(Q.y) < 4.0) {
            let along = aq * rimq;
            let wob = (fvnoise(vec2<f32>(along * 0.08, 3.0)) - 0.5) * 5.0;
            let dd = abs(fract((sl.y + wob) / 4.6 + 0.3) - 0.5) * 4.6;
            let w = 0.12 * fvnoise(vec2<f32>(along * 0.15, 9.0)) * smoothstep(14.0, 4.0, sl.y);
            crack = max(crack, saturate((w - dd + pw * 0.5) / max(pw, 0.02)) * min(1.0, w / max(pw * 0.6, 0.01)));
        }
        col = col * (1.0 - 0.88 * crack * k);
        // the pit, where it has been dug: dark, darker the deeper, a cold haze down in it; and, until it is dug on down,
        // its floor 25 down hidden in murk
        let into = rimq + 7.0 - rq;
        if (into > 0.0 && Q.y < -2.5 && time > sh_front(rq) - SH_LEAD) {
            let dep = -Q.y;
            var dark = pow(smoothstep(2.0, 108.0, dep), 0.7);
            dark = max(dark, smoothstep(13.0, 24.0, dep) * 0.93 * (1.0 - smoothstep(SH_DEEP0 + 2.0, SH_DEEP0 + 7.0, time)));
            let haze = mix(vec3<f32>(0.012, 0.012, 0.014), vec3<f32>(0.05, 0.05, 0.055), day);
            col = mix(col, haze, dark * 0.97 * k);
        }
    }

    // ---- the slabs: solid, the nearest drawn, hidden by anything nearer ------------------------------------------
    var hit_t = 1.0e9;
    var hit_c = vec3<f32>(0.0);
    if (n_slabs > 0 && time > SH_C0 - SH_LEAD - 0.1 && time < 16.6 + SH_FALL) {
        for (var i = 0; i < n_slabs; i = i + 1) {
            let b = SH_SB + u32(i) * SH_SW;
            let s = time - sh_w(b + 6u);
            if (s < -SH_LEAD || s > SH_FALL) {
                continue;
            }
            let ps = sh_pose(b, i, s, C);
            // (a sphere round it first)
            let cc = ps.o + ps.drop;
            let rad = 0.5 * length(vec2<f32>(sh_w(b + 5u) - sh_w(b + 2u), (sh_w(b + 1u) - sh_w(b)) * sh_w(b + 5u))) + sh_w(b + 10u) + 4.0;
            let tc = dot(cc, rd);
            if (dot(cc, cc) - tc * tc > rad * rad || tc + rad < 0.0 || tc - rad > min(hit_t, scene_len + 1.0)) {
                continue;
            }
            let o = sh_to(ps, vec3<f32>(0.0));
            let dl = sh_dir_to(ps, rd);
            let h = sh_hit(b, o, dl);
            if (h.y <= h.x || h.x <= 0.0 || h.x >= hit_t) {
                continue;
            }
            // (straining in place over the land as it still is: where they meet, the land's own colour)
            if (h.x > scene_len + 0.7) {
                continue;
            }
            hit_t = h.x;
            let q = o + dl * h.x;
            let sx = sh_w(b + 8u);
            let sz = sh_w(b + 9u);
            let dtop = sx * q.x + sz * q.z - q.y;
            var nl = vec3<f32>(-sx, 1.0, -sz);
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
            let nw = sh_dir_from(ps, normalize(nl));
            // (its block-sized look, in its own frame, from the world's grid where it lay)
            let qg = q + ps.o + cam;
            var base = sh_earth(dtop, h.z, qg, f32(i), day);
            if (h.z < 0.5 && s < 0.0 && abs(h.x - scene_len) < 1.2) {
                base = scene;
            }
            let lit = (amb * (0.6 + 0.4 * nw.y) + sunc * max(dot(nw, Ls), 0.0)) * 0.72;
            var c = base * select(lit, vec3<f32>(1.0), h.z < 0.5 && s < 0.0 && abs(h.x - scene_len) < 1.2);
            // (in the shadow of the pit as it drops, and into its dark)
            let wy = (cam + rd * h.x).y - gy;
            let shade = smoothstep(2.0, 60.0, -wy);
            c = mix(c, c * 0.25, smoothstep(0.0, 1.0, s) * 0.6);
            c = mix(c, vec3<f32>(0.012, 0.012, 0.014), pow(shade, 0.7) * 0.97);
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
                col = mix(col, mix(foam, vec3<f32>(0.02, 0.025, 0.03), deep * 0.9), alpha * k);
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
    let murk = smoothstep(SH_C0, SH_C0 + 3.0, time) * (1.0 - smoothstep(20.0, SH_END, time));
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
