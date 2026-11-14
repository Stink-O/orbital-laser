// [lean pass] (mod/src/passbuild.rs: the game's pass goes in without its comment and blank lines)
// Orbital Laser's post pass for the World Eater (laser 19): the last of the pass's three files (after
// strike.wgsl up to its fs_main, worldeater_path.wgsl and worldeater_body.wgsl; mod/build.rs builds it, its
// `[half stage]` kept for QUALITY FAST only). Validate with tools/check-shader.sh.
//
// Everything in the picture that is not the worm's own body, composed with it against the scene's depth: the wormsign
// (a wall of earth and hundreds of thrown blocks over the passing head, wef_run_dust and wef_pieces), each breach's and
// bite's earth and dust (wef_hole_dust, wef_pieces), the tunnel failing, the camera's jolt and lens, and the caught
// view (wef_caught). The dust is marched at half size for QUALITY FAST (fs_half) and joined (fs_join) with the sharp
// things at full size.

// The mound's and the dome's stand-in, for the preview (no world warp there). The game's pass is built with it off
// (mod/build.rs), the warp lifting the real land instead.
const WE_STANDIN_MOUND: bool = true;
// (the preview's test of the Caught view: when it was caught and spat out, strike seconds; -1: from the table)
const WEF_TEST_CATCH: vec2<f32> = vec2<f32>(-1.0, -1.0);
// (the table's words that are the fx's: WE_FX_T + these)
// (the wind inside the throat: 1 as tuned, up or down from there)
const WEF_WIND: f32 = 1.0;
// (how much work the pass may do, 1 the full look: a menu tier or the game's frame time may lower it (a pass param, to
// come); the step counts, the dust's shadow and the pieces scale with it)
const WEF_DETAIL: f32 = 1.0;
// (the land's shut word is the bite; the jaws take this long more to close over the eye (the body's gape falls from
// t_in + 0.05 to t_in + 0.6): the day is faded out over it and the caught view, and the dark beat's black, begin then)
const WEF_SHUT_D: f32 = 0.3;
const WEF_W_CAUGHT: u32 = 0u;      // when the jaws close on the player (strike seconds; 0 or less: not caught)
const WEF_W_SPIT: u32 = 1u;        // when it spits them out
const WEF_W_END: u32 = 2u;         // the strike's last second (the land's; 0: worked out here, wef_end)
const WEF_HF: u32 = 16u;
// (the fx's blocks, real blocks of the game with its own textures: strike/we_fx.rs's table, from WE_FX_T + WEF_BK)
const WEF_BK: u32 = 1024u;
const WEF_B_DIRT: u32 = 0u;
const WEF_B_COARSE: u32 = 1u;
const WEF_B_GRASS: u32 = 2u;
const WEF_B_STONE: u32 = 3u;
const WEF_B_COBBLE: u32 = 4u;
const WEF_B_DEEP: u32 = 5u;
const WEF_B_GRAVEL: u32 = 6u;
const WEF_B_SAND: u32 = 7u;
const WEF_B_LOG: u32 = 8u;
const WEF_B_LEAVES: u32 = 12u;
const WEF_B_IRON: u32 = 16u;
const WEF_B_DIAMOND: u32 = 17u;
const WEF_B_SCULK: u32 = 18u;           // the land's heightfield, if given (wef_hf)
// The dust's and the pieces' gravity and the earth's colours
const WEF_G: f32 = 26.0;
// The dust's amount and its falloff (kept light, denser near its source): every source's density times WEF_AMOUNT, and times exp(-d / WEF_FALL) for d blocks out past its
// source (a hole's rim, a tunnel's line, a jet's foot): dense and readable at the hole, a faint haze a hundred out, almost
// nothing past that. A large WEF_FALL (say 400) gives the even cloud of round 3 back, for comparing.
const WEF_AMOUNT: f32 = 0.5;
const WEF_FALL: f32 = 32.0;
// How long a hole's dust lasts before it is gone altogether (seconds past its breach or bite): it caps the live sources
// in a hunt (an arch's dust is gone before two more are added).
const WEF_LIFE: f32 = 16.0;
const WEF_NB: u32 = 90u;           // pieces a breach throws (the first; the hops fewer)
const WEF_NI: u32 = 48u;           // pieces a bite draws in
const WEF_SRC: u32 = 20u;          // dust sources at most: holes (12), runs (6)

struct WeOut {
    c: vec4<f32>,
    e: vec4<f32>,
}


// The ray (from the camera, rd unit) against the ellipsoid at c with radii r: its near distance, or -1.
fn we_ellipsoid(rd: vec3<f32>, c: vec3<f32>, r: vec3<f32>) -> f32 {
    let oc = -c / r;
    let d = rd / r;
    let a = dot(d, d);
    let b = dot(oc, d);
    let cc = dot(oc, oc) - 1.0;
    let h = b * b - a * cc;
    if (h < 0.0) {
        return -1.0;
    }
    return (-b - sqrt(h)) / a;
}

// tools/preview.py's check of the path (`--set wedebug=1`: we_path.rs's samples at WE_DBG_T): Rust's points red,
// the WGSL's at the same s green, yellow where they are one (within half a block); and a box in the top left corner,
// green if every sample agrees within 0.05 of a block (the points) and of a block of s (we_head), red if not.
fn we_debug(uv: vec2<f32>, rd: vec3<f32>, scene_len: f32, col: vec3<f32>) -> vec3<f32> {
    let m = u32(we_w(WE_DBG_T));
    if (m == 0u) {
        return col;
    }
    var out = col;
    var tr = 1.0e9;
    var tg = 1.0e9;
    var err = 0.0;
    for (var k = 0u; k < min(m, 64u); k = k + 1u) {
        let o = WE_DBG_T + 1u + 4u * k;
        let s = we_w(o);
        let pr = vec3<f32>(we_w(o + 1u), we_w(o + 2u), we_w(o + 3u));
        let pg = we_point(s);
        err = max(err, length(pr - pg));
        let a = we_ellipsoid(rd, we_o + pr, vec3<f32>(3.0));
        if (a > 0.0) {
            tr = min(tr, a);
        }
        let b = we_ellipsoid(rd, we_o + pg, vec3<f32>(3.0));
        if (b > 0.0) {
            tg = min(tg, b);
        }
    }
    let hq = WE_DBG_T + 1u + 4u * 64u;
    let q = u32(we_w(hq));
    var herr = 0.0;
    for (var k = 0u; k < min(q, 64u); k = k + 1u) {
        herr = max(herr, abs(we_head(we_w(hq + 1u + 2u * k)) - we_w(hq + 2u + 2u * k)));
    }
    let near = min(tr, tg);
    if (near < scene_len + 2.0 && near < 1.0e8) {
        out = select(select(vec3<f32>(0.0, 0.9, 0.1), vec3<f32>(0.9, 0.05, 0.05), tr < tg), vec3<f32>(1.0, 0.85, 0.0), abs(tr - tg) < 0.5);
    }
    if (uv.x < 0.06 && uv.y < 0.06) {
        out = select(vec3<f32>(0.9, 0.0, 0.0), vec3<f32>(0.0, 0.8, 0.0), err < 0.05 && herr < 0.05);
    }
    return out;
}

fn wef_knot(h: u32) -> vec3<f32> {
    return select(we_arch_to(h / 2u), we_arch_from(h / 2u), (h & 1u) == 0u);
}
// When the head breaks out of hole h (none: -1e4) and when it goes into it.
fn wef_tb(h: u32) -> f32 {
    return select(-1.0e4, we_arch_t_out(h / 2u), (h & 1u) == 0u);
}
fn wef_ti(h: u32) -> f32 {
    return select(-1.0e4, we_arch_t_in(h / 2u), (h & 1u) == 1u);
}
// The land's word w of its record for tunnel i (the run into arch i: WE_LAND_T + 224 + 16 i; land.md): 6, 7 its rings'
// first and last time, 10 how many, 11 the tail into it, 12 the tail out of it (out of arch i's breach). -1 when not given.
fn wef_lw(i: u32, w: u32) -> f32 {
    if (we_w(WE_LAND_T) < 0.5 || i >= we_n()) {
        return -1.0;
    }
    let v = we_w(WE_LAND_T + 224u + 16u * i + w);
    return select(-1.0, v, v > 0.0);
}
// When the tail has gone into bite hole h: the land's word when given, else the body pouring on at about the speed the
// head went in.
fn wef_tail_in(h: u32) -> f32 {
    let i = h / 2u;
    // (into arch i's dive hole: into the tunnel that starts there, the next arch's)
    let lw = wef_lw(i + 1u, 11u);
    if (lw > 0.0) {
        return lw;
    }
    return we_arch_t_in(i) + WE_LEN / max(we_aw(i, WE_R_VIN), 60.0);
}
// When the tail comes out of breach hole h: the length of the body still behind the arch, at the pour's speed.
fn wef_tail_out(h: u32) -> f32 {
    let i = h / 2u;
    let lw = wef_lw(i, 12u);
    if (lw > 0.0) {
        return lw;
    }
    return wef_tail_in(h + 1u) - we_arch_len(i) / max(we_aw(i, WE_R_VIN), 60.0);
}
// How big a breach and a bite are: the first breach the biggest; the rest by their arch's size, each a little its own.
fn wef_sb(h: u32) -> f32 {
    let i = h / 2u;
    if (i == 0u) {
        return 1.0;
    }
    let ap = we_arch_apex(i);
    return clamp(0.45 + 0.4 * sqrt(max(ap, 1.0) / WE_APEX), 0.45, 0.85) * (0.9 + 0.2 * fh21(vec2<f32>(f32(i), 3.7)));
}
fn wef_bs(h: u32) -> f32 {
    let i = h / 2u;
    let ap = we_arch_apex(i);
    return clamp(0.4 + 0.6 * sqrt(max(ap, 1.0) / WE_APEX), 0.5, 1.0) * select(0.85, 1.0, i + 1u == we_n() || we_arch_hold(i).x >= 0.0);
}
// When everything has faded away: the strike's last second as the land gives it (WE_FX_T + 2), or else the last tail
// in and fifteen seconds.
// Whether the worm has gone into the ground for good (its tail two seconds into its last hole): nothing of it to draw.
fn wef_gone(t: f32) -> bool {
    let n = we_n();
    return n > 0u && t > wef_tail_in(2u * n - 1u) + 2.0;
}
fn wef_end() -> f32 {
    let e = we_w(WE_FX_T + WEF_W_END);
    if (e > 0.0) {
        return e;
    }
    let n = we_n();
    if (n == 0u) {
        return WE_LEN_S;
    }
    return max(WE_LEN_S, wef_tail_in(2u * n - 1u) + 15.0);
}
fn wef_fade(t: f32) -> f32 {
    let e = wef_end();
    return 1.0 - smoothstep(e - 7.0, e, t);
}

// Small value noise (as the warp's).
fn wef_vh(p: vec2<f32>) -> f32 {
    let q = fract(p * vec2<f32>(0.1031, 0.1030));
    let r = q + dot(q, q.yx + 33.33);
    return fract((r.x + r.y) * r.x);
}
fn wef_vn(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = p - i;
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(wef_vh(i), wef_vh(i + vec2<f32>(1.0, 0.0)), u.x), mix(wef_vh(i + vec2<f32>(0.0, 1.0)), wef_vh(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn wef_b(q2: f32) -> f32 {
    let u = max(1.0 - q2, 0.0);
    return u * u;
}
// The mound and the dome this frame (contract v2's we_mound), and the way the head goes under the land: wef_begin.
var<private> wef_m: WeMnd;
var<private> wef_hd: vec2<f32>;
fn wef_begin(t: f32) {
    wef_m = we_mound(t);
    wef_hd = we_sdir;
    if (wef_m.arch >= 0) {
        let i = u32(wef_m.arch);
        let d = we_arch_from(i).xz - we_run_from(i).xz;
        if (dot(d, d) > 1.0) {
            wef_hd = normalize(d);
        }
    }
}
// A dome dh high over the land at x (level, from its middle), uneven and shivering (the warp's wew_dome_lift).
fn wef_dome_lift(x: vec2<f32>, dh: f32, t: f32) -> f32 {
    if (dh <= 0.01) {
        return 0.0;
    }
    let q2 = dot(x, x) / (WE_DOME_R * WE_DOME_R) * (0.85 + 0.3 * wef_vn(x * 0.05 + vec2<f32>(3.0, 9.0)));
    let shiver = 1.0 + 0.05 * (dh / WE_DOME_H) * sin(t * 37.0 + x.x * 0.9 + x.y * 0.6);
    return dh * wef_b(q2) * shiver;
}
// The land's lift by the mound over the head and the dome before a breach (the warp's wew_lift: keep in step), x level
// from the origin: the mound at mc, mh high, going the way dir; the dome at dc, dh high.
fn wef_lift_at(x: vec2<f32>, mc: vec2<f32>, mh: f32, dir: vec2<f32>, dc: vec2<f32>, dh: f32, t: f32) -> f32 {
    var lift = 0.0;
    if (mh > 0.01) {
        let d = x - mc;
        let u = dot(d, dir);
        let v = d.x * dir.y - d.y * dir.x;
        let hb = mh * (0.8 + 0.4 * wef_vn(x * 0.04 + vec2<f32>(0.0, t * 0.35)));
        let ua = u / (WE_MOUND_R * select(1.4, 0.95, u > 0.0));
        let va = v / (WE_MOUND_R * (0.85 + 0.3 * wef_vn(x * 0.06 + vec2<f32>(7.0, 1.0))));
        var m = wef_b(ua * ua + va * va);
        let ub = (u - WE_MOUND_R * 1.3) / 13.0;
        let vb = v / (WE_MOUND_R * 1.35);
        m = m + 0.16 * wef_b(ub * ub + vb * vb);
        let us = (u + WE_MOUND_R * 1.75) / 24.0;
        let vs = v / (WE_MOUND_R * 0.6);
        m = m - 0.2 * wef_b(us * us + vs * vs);
        lift = hb * m * (1.0 + 0.07 * sin(t * 5.3 - u * 0.15));
    }
    return lift + wef_dome_lift(x - dc, dh, t);
}
// (round 4: no travelling mound any more; only the slight quick swell over a breach in its last half second, as the warp)
fn wef_lift(x: vec2<f32>, t: f32) -> f32 {
    return 0.0 * wef_lift_at(x, wef_m.at.xz, 0.0, wef_hd, wef_m.dome_at.xz, 0.0, t);
}
// The dome's cracks (the warp's wew_crack: keep in step): x their glowing core, y their lips.
fn wef_cracks(x: vec2<f32>, t: f32) -> vec2<f32> {
    return wef_crack(x - wef_m.dome_at.xz, wef_m.dome / WE_DOME_H);
}
fn wef_crack(x: vec2<f32>, g: f32) -> vec2<f32> {
    if (g <= 0.0) {
        return vec2<f32>(0.0);
    }
    let r = length(x);
    let open = g * smoothstep(WE_DOME_R * 1.15 * g + 4.0, WE_DOME_R * 0.25 * g, r);
    if (open <= 0.001) {
        return vec2<f32>(0.0);
    }
    let ang = atan2(x.y, x.x);
    let q = vec2<f32>(r / 7.5, ang * max(r, 6.0) / 10.0) + vec2<f32>(wef_vn(x * 0.11), wef_vn(x * 0.11 + 5.0)) * 0.8;
    let i = floor(q);
    let f = q - i;
    var d1 = 9.0;
    var d2 = 9.0;
    for (var a = -1; a <= 1; a = a + 1) {
        for (var b = -1; b <= 1; b = b + 1) {
            let o = vec2<f32>(f32(a), f32(b));
            let pt = o + vec2<f32>(wef_vh(i + o), wef_vh(i + o + 17.0)) * 0.8 + 0.1 - f;
            let dd = dot(pt, pt);
            if (dd < d1) {
                d2 = d1;
                d1 = dd;
            } else if (dd < d2) {
                d2 = dd;
            }
        }
    }
    let e = (sqrt(d2) - sqrt(d1)) * 4.0;
    let w = 0.06 + 0.3 * open * (0.6 + 0.8 * wef_vn(x * 0.2));
    let core = smoothstep(w, w * 0.25, e) * open;
    let lips = exp(-e / (0.3 + 0.5 * open)) * open;
    return vec2<f32>(core, lips);
}

// ---- the light, matched to the scene's ---------------------------------------------------------------------------
struct WefLight {
    fog: vec3<f32>,
    sunc: vec3<f32>,
    amb: vec3<f32>,
    haze: vec3<f32>,
    L: vec3<f32>,
    day: f32,
}
fn wef_light() -> WefLight {
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    let moon = smoothstep(-0.02, -0.2, sun.y);
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
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
    let amb = mix(vec3<f32>(0.03, 0.035, 0.05), skyl * 0.8 + vec3<f32>(0.04), day);
    let sunc = mix(vec3<f32>(1.3, 1.2, 1.04), mix(vec3<f32>(1.5, 0.68, 0.3), vec3<f32>(1.3, 0.38, 0.14), smoothstep(0.0, -0.1, sun.y)), warm) * sun_up + vec3<f32>(0.07, 0.09, 0.14) * moon;
    let haze = mix(vec3<f32>(0.02, 0.025, 0.04), skyl * 1.05, day);
    // (on the dust and the pieces the low sun's colour is less deep than on the sky)
    let sund = mix(vec3<f32>(dot(sunc, vec3<f32>(0.2126, 0.7152, 0.0722))), sunc, 0.35);
    return WefLight(srgb_to_linear(frame.fog_color.rgb), sund, amb, haze, L, day);
}

// How much of the game's fog is on something t blocks off (its fog starts round half the render distance).
fn wef_fog(t: f32) -> f32 {
    let R = max(frame.view_params.z, 64.0);
    let u = saturate((t - 0.4 * R) / (1.0 * R));
    return u * u * (3.0 - 2.0 * u) * 0.9;
}

// ---- the dust -------------------------------------------------------------------------------------------------
// Where this pixel's ray meets the land (from the origin): the dust right there sits on it, not on the guess of the
// land's height a source makes (its holes' heights). xz, its height, the reach of that squared.
var<private> wef_loc: vec4<f32>;
// The land's heightfield, if the land gave one (WEF_HF: nx, nz, x0, z0 (from the origin), its cell, then nx * nz
// heights from the origin's ground, row by row along x): the ground at xz, and whether it knows (0 to 1).
fn wef_hf(xz: vec2<f32>) -> vec2<f32> {
    let b = WE_FX_T + WEF_HF;
    let nx = we_w(b);
    let nz = we_w(b + 1u);
    if (nx < 2.0 || nz < 2.0) {
        return vec2<f32>(0.0, 0.0);
    }
    let cell = max(we_w(b + 4u), 1.0);
    let f = (xz - vec2<f32>(we_w(b + 2u), we_w(b + 3u))) / cell;
    let fc = clamp(f, vec2<f32>(0.0), vec2<f32>(nx - 1.001, nz - 1.001));
    let i0 = vec2<u32>(floor(fc));
    let u = fc - floor(fc);
    let w0 = b + 8u + i0.y * u32(nx) + i0.x;
    let h00 = we_w(w0);
    let h10 = we_w(w0 + 1u);
    let h01 = we_w(w0 + u32(nx));
    let h11 = we_w(w0 + u32(nx) + 1u);
    let g = mix(mix(h00, h10, u.x), mix(h01, h11, u.x), u.y);
    // (past its edge, fading to not knowing)
    let out = max(max(-f.x, f.x - (nx - 1.0)), max(-f.y, f.y - (nz - 1.0)));
    return vec2<f32>(g, 1.0 - smoothstep(0.0, 3.0, out));
}
// Else the land as the picture shows it: the point at xz looked for on the screen at a guess of its height. Where the
// land seen there is near it in xz, that is the ground; where the land seen lies beyond it the guess is in the air (lower
// it); where it lies before it, near in xz, the guess is under a slope (raise it); a bisection of five looks. Where the
// land at xz is hidden behind a hill it keeps the highest guess still possible.
fn wef_ssg(xz: vec2<f32>, base: f32) -> f32 {
    var lo = base - 70.0;
    var hi = base + 50.0;
    var g = base;
    for (var i = 0; i < 4; i = i + 1) {
        let q = we_o + vec3<f32>(xz.x, g, xz.y);
        let sp = project_rel(q);
        if (sp.z < 0.0 || any(sp.xy < vec2<f32>(0.002)) || any(sp.xy > vec2<f32>(0.998))) {
            return select(base, g, i > 0);
        }
        let d = depth_at(sp.xy);
        let lq = length(q);
        let tol = 2.0 + 0.008 * lq;
        if (is_sky(d)) {
            // (no land drawn there at all, past the render distance: no ground for the dust to lie on, so none)
            if (i == 0) {
                return -1.0e5;
            }
            hi = g;
        } else {
            let Q = world_offset(sp.xy, d) - we_o;
            let e = length(Q.xz - xz);
            if (e < tol) {
                return Q.y;
            }
            if (length(Q + we_o) > lq) {
                hi = g;
            } else if (e < 12.0 * tol) {
                lo = g;
            } else {
                return min(hi, max(g, base));
            }
        }
        g = 0.5 * (lo + hi);
    }
    return g;
}
// The ground at xz: the heightfield where given, else the picture's land looked up at the corners of a 10-block grid
// round it and taken between them (the same corners for every pixel, so the ground is one smooth field, not each
// pixel's own: no streaks where one sees a crown and the next the grass under it); and right where this pixel's ray
// meets the land, that point's own height, a little.
// How much of the ground the last wef_ground found is drawn land (0 to 1): where the picture has none the dust fades
// out smoothly, never in grid-shaped steps.
var<private> wef_landw: f32;
fn wef_ground(xz: vec2<f32>, base: f32) -> f32 {
    let hf = wef_hf(xz);
    var g = base;
    wef_landw = 1.0;
    if (hf.y > 0.99) {
        g = hf.x;
    } else {
        let c = xz / 10.0 - 0.5;
        let i = floor(c);
        let f = c - i;
        let u = f * f * (3.0 - 2.0 * f);
        var gs = 0.0;
        var ws = 0.0;
        for (var k = 0; k < 4; k = k + 1) {
            let o = vec2<f32>(f32(k & 1), f32(k >> 1u));
            let gk = wef_ssg((i + o + vec2<f32>(0.5)) * 10.0, base);
            let wk = mix(1.0 - u.x, u.x, o.x) * mix(1.0 - u.y, u.y, o.y);
            if (gk > -1.0e4) {
                gs = gs + gk * wk;
                ws = ws + wk;
            }
        }
        wef_landw = smoothstep(0.15, 0.85, ws);
        g = select(base, gs / max(ws, 1.0e-4), ws > 1.0e-3);
        g = mix(g, hf.x, hf.y);
    }
    return g;
}
// Cauliflower lumps (as the Payload's boil builds them): domes over a jittered lattice, each its own size, rounded on
// top and meeting in creases: about 1 on a big dome's crown, 0 in a crease. Used on turned domains (wef_turn), a
// different turn for each size, so no lattice lines up with another or with the world.
fn wef_dome(p: vec3<f32>) -> f32 {
    let b = floor(p - 0.5);
    var hmax = 0.0;
    for (var c = 0u; c < 8u; c = c + 1u) {
        let o = vec3<f32>(f32(c & 1u), f32((c >> 1u) & 1u), f32(c >> 2u));
        let cell = b + o;
        let q = bitcast<vec3<u32>>(vec3<i32>(cell));
        let hs = pcg(q.x ^ pcg(q.y ^ pcg(q.z + 0x77u)));
        let jit = vec3<f32>(f32(hs & 1023u), f32((hs >> 10u) & 1023u), f32((hs >> 20u) & 1023u)) * (0.7 / 1023.0) + 0.15;
        let sz = 0.7 + 0.55 * f32(pcg(hs) & 1023u) / 1023.0;
        let e = cell + jit - p;
        hmax = max(hmax, sz * sqrt(saturate(1.0 - dot(e, e) * 1.7 / (sz * sz))));
    }
    return hmax;
}
fn wef_turn(k: i32, p: vec3<f32>) -> vec3<f32> {
    if (k == 0) {
        return mat3x3<f32>(0.3360, 0.8941, -0.2961, -0.6542, 0.4410, 0.6146, 0.6801, -0.0779, 0.7290) * p;
    }
    if (k == 1) {
        return mat3x3<f32>(-0.5370, 0.2440, 0.8075, 0.7970, -0.1867, 0.5744, 0.2909, 0.9516, -0.0985) * p;
    }
    return mat3x3<f32>(0.8660, -0.3536, 0.3536, 0.0, 0.7071, 0.7071, -0.5, -0.6124, 0.6124) * p;
}

// A point rolled about (cr, ch) in the plane of r and h by ang, the more the nearer it: the front of a gravity current
// rolling over on itself.
fn wef_roll(r: f32, h: f32, cr: f32, ch: f32, ang: f32, rad: f32) -> vec2<f32> {
    let d = vec2<f32>(r - cr, h - ch);
    let a = ang * exp(-dot(d, d) / (rad * rad));
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(cr + d.x * c - d.y * s, ch + d.x * s + d.y * c);
}
// The breach's billows (wef_hk): middles (from the origin) and radii, the way each rolls (axis, angle), how much is
// left of each; and how far out and up any of them reaches.
const WEF_NP: u32 = 10u;
var<private> wef_puf: array<vec4<f32>, 12>;
var<private> wef_pax: array<vec4<f32>, 12>;
var<private> wef_plife: array<f32, 12>;
var<private> wef_pmax: vec2<f32>;
// The bite's thrown clumps (wef_hk): heads (from the origin) and radii, their trails' ends and radii, how much is left of
// each; how far out and up any reaches.
const WEF_NC: u32 = 14u;
var<private> wef_cl: array<vec4<f32>, 14>;
var<private> wef_ct: array<vec4<f32>, 14>;
var<private> wef_ctl: array<f32, 14>;
var<private> wef_cmax: vec2<f32>;
// (the billow the march last found itself in: the looks towards the sun use only it)
var<private> wef_pni: u32;
// (how deep in a crease between lumps the last dust looked up lies, 0 deep to 1 on a crown: the march darkens the creases
// so the lumps read as forms whatever side the light comes from)
var<private> wef_crease: f32;
// (the sculk-teal light coming up through a burst at its foot just after the head has passed: wef_run_dust sets it)
var<private> wef_glow: f32;
// (the colour of thrown earth here: the land this pixel sees, dark and browned; dark soil where it sees sky)
var<private> wef_earth: vec3<f32>;
// (just spat out, 1 to 0 over a couple of seconds: the dust the eye is in thinned, near it most, so the land shows)
var<private> wef_clear: f32;
// (the march's step here, blocks: no edge sharper than it, or the jittered steps print it as a screen of dots; and the
// sun's way, for the earth's own shading)
var<private> wef_dt: f32;
var<private> wef_L: vec3<f32>;
// (how far from the eye the march is: far off the earth stands taller and denser, to read from there)
var<private> wef_tt: f32;
// (0 with the head within 100 blocks of the eye, 1 past 160: the far read's boost, by the head's distance, so that
// nothing near costs more)
var<private> wef_fr: f32;
// What a hole's dust needs that is the same all along a ray: worked out once a source (wef_hk).
struct WefHk {
    H: vec3<f32>,
    k: u32,
    ab: f32,       // since the head broke out of it (or -1e4)
    ai: f32,       // since it went in
    sb: f32,
    bs: f32,
    tout: f32,     // the tail out of it, and into it
    tin: f32,
    climb: f32,    // how high the head has climbed out of it, to 90
    reach: vec2<f32>, // wef_hole_reach's: the dust is faded out before it
    dome: f32,     // how high the land over it is domed now (before a breach), 0 to 1
    fade: f32,
}
// Billow m and clump m of the hole hk, as the tick's table has them taken between its two slices (wef_tab), or as
// wef_hk worked them out (no table).
var<private> wef_tab: bool;
var<private> wef_hkf: f32;
fn wef_hk4(k: u32, q: u32) -> vec4<f32> {
    let a = WEP_T + WEP_HK + 2u * WEP_HKS * k + q;
    return mix(wep_v4(a), wep_v4(a + WEP_HKS), wef_hkf);
}
fn wef_hk1(k: u32, q: u32) -> f32 {
    let a = WEP_T + WEP_HK + 2u * WEP_HKS * k + q;
    return mix(wep_f(a), wep_f(a + WEP_HKS), wef_hkf);
}
fn wef_gpuf(k: u32, m: u32) -> vec4<f32> {
    if (wef_tab) {
        return wef_hk4(k, 9u * m);
    }
    return wef_puf[m];
}
fn wef_gpax(k: u32, m: u32) -> vec4<f32> {
    if (wef_tab) {
        return wef_hk4(k, 9u * m + 4u);
    }
    return wef_pax[m];
}
fn wef_gplife(k: u32, m: u32) -> f32 {
    if (wef_tab) {
        return wef_hk1(k, 9u * m + 8u);
    }
    return wef_plife[m];
}
fn wef_gcl(k: u32, m: u32) -> vec4<f32> {
    if (wef_tab) {
        return wef_hk4(k, 90u + 9u * m);
    }
    return wef_cl[m];
}
fn wef_gct(k: u32, m: u32) -> vec4<f32> {
    if (wef_tab) {
        return wef_hk4(k, 94u + 9u * m);
    }
    return wef_ct[m];
}
fn wef_gctl(k: u32, m: u32) -> f32 {
    if (wef_tab) {
        return wef_hk1(k, 98u + 9u * m);
    }
    return wef_ctl[m];
}
fn wef_hk(k: u32, t: f32) -> WefHk {
    var o: WefHk;
    o.H = wef_knot(k);
    o.k = k;
    o.ab = t - wef_tb(k);
    o.ai = t - wef_ti(k);
    let bh = (k & 1u) == 1u;
    o.dome = select(0.0, wef_m.dome / WE_DOME_H, !bh && length(wef_m.dome_at.xz - o.H.xz) < 4.0);
    o.fade = wef_fade(t);
    wef_tab = false;
    // (the hole's numbers, its billows and clumps as the tick worked them out (strike/we_fx.rs's hk_words), taken
    // between it and the next; the billows and clumps read where they are used (wef_gpuf and the rest), never copied
    // out for every source on every pixel)
    if (wep_nev_ok() && mod_data[WEP_T + 8u] == 1u && k < 12u) {
        wef_tab = true;
        wef_hkf = clamp((t - wep_f(WEP_T + 1u)) / wep_f(WEP_T + 6u), 0.0, 1.0);
        let a = WEP_T + WEP_HK + 2u * WEP_HKS * k;
        let b = a + WEP_HKS;
        wef_pmax = max(vec2<f32>(wep_f(a + 216u), wep_f(a + 217u)), vec2<f32>(wep_f(b + 216u), wep_f(b + 217u)));
        wef_cmax = max(vec2<f32>(wep_f(a + 218u), wep_f(a + 219u)), vec2<f32>(wep_f(b + 218u), wep_f(b + 219u)));
        o.reach = wef_hole_reach(k, t);
        o.climb = wef_hk1(k, 222u);
        o.tout = wep_f(a + 223u);
        o.tin = wep_f(a + 224u);
        o.sb = wep_f(a + 225u);
        o.bs = wep_f(a + 226u);
        return o;
    }
    o.sb = wef_sb(k);
    o.bs = select(1.0, wef_bs(k), bh);
    o.tout = select(wef_tail_out(k), -1.0e4, bh);
    o.tin = select(-1.0e4, wef_tail_in(k), bh);
    o.climb = 0.0;
    if (o.ab > 0.3 && t < o.tout + 1.0) {
        o.climb = min(max(we_head(t) - we_arch_s0(k / 2u), 0.0), 90.0);
    }
    o.reach = wef_hole_reach(k, t);
    // (the bite's clumps)
    wef_cmax = vec2<f32>(0.0, -1.0e9);
    for (var m = 0u; m < WEF_NC; m = m + 1u) {
        wef_cl[m] = vec4<f32>(0.0);
        let tau = o.ai - (0.1 + 0.35 * wef_ph(m, k, 61u));
        if ((k & 1u) == 0u || tau <= 0.0 || o.ai > 10.0) {
            continue;
        }
        let th = (f32(m) + 0.6 * wef_ph(m, k, 62u)) / f32(WEF_NC) * 6.2831853 + 0.7 * f32(k);
        let dir = vec3<f32>(cos(th), 0.0, sin(th));
        let p0 = dir * (WE_R + 3.0) + vec3<f32>(0.0, 2.0, 0.0);
        let v0 = dir * (18.0 + 26.0 * wef_ph(m, k, 63u)) + vec3<f32>(0.0, o.bs * (60.0 + 60.0 * wef_ph(m, k, 64u)), 0.0);
        let ph = wef_fly(p0, v0, tau, 0.08, 24.0);
        let pt = wef_fly(p0, v0, max(tau - 0.45, 0.0), 0.08, 24.0);
        let rad = o.bs * (5.0 + 5.0 * wef_ph(m, k, 65u)) * (0.5 + 0.5 * smoothstep(0.0, 0.3, tau)) + 0.8 * tau;
        wef_cl[m] = vec4<f32>(o.H + ph, rad);
        wef_ct[m] = vec4<f32>(o.H + pt, rad * 1.5 + 1.0);
        wef_ctl[m] = smoothstep(-8.0, 2.0, ph.y) * exp(-max(tau - 3.0, 0.0) / 2.0);
        let rr = max(length(ph.xz), length(pt.xz)) + rad * 2.0;
        wef_cmax = max(wef_cmax, vec2<f32>(rr, max(ph.y, pt.y) + rad * 2.0));
    }
    // (the billows)
    wef_pmax = vec2<f32>(0.0, -1.0e9);
    // (the breach's, or at a bite the rebound's, bigger, thrown up round the body as it drives in: whichever came last)
    let bite = o.ai > 0.0 && (o.ab <= 0.0 || o.ai < o.ab);
    let a0 = select(o.ab, o.ai - 0.15, bite);
    let S = select(o.sb, 1.1 * o.bs, bite);
    for (var m = 0u; m < WEF_NP; m = m + 1u) {
        wef_puf[m] = vec4<f32>(0.0);
        let a = a0 - (0.04 + select(1.3, 0.8, bite) * pow(wef_ph(m, k, 51u), 1.5));
        if (a <= 0.0 || a0 > 12.0) {
            continue;
        }
        let th = (f32(m) + 0.6 * wef_ph(m, k, 52u)) / f32(WEF_NP) * 6.2831853 + f32(k);
        let dir = vec3<f32>(cos(th), 0.0, sin(th));
        let top = S * (16.0 + 34.0 * wef_ph(m, k, 53u));
        let y = top * (1.0 - exp(-a / 1.3)) - 1.4 * max(a - 6.0, 0.0);
        let rr = WE_R + 6.0 + 16.0 * wef_ph(m, k, 54u) + select(12.0, 24.0, bite) * (1.0 - exp(-a / 2.0)) + 2.5 * a;
        let rad = min(S * (5.0 + 10.0 * (1.0 - exp(-a / 1.2))) + 0.6 * a, 16.0);
        wef_puf[m] = vec4<f32>(o.H + dir * rr + vec3<f32>(0.0, max(y, rad * 0.4), 0.0), rad);
        wef_pax[m] = vec4<f32>(vec3<f32>(-dir.z, 0.0, dir.x), -1.6 * (1.0 - exp(-a / 2.2)));
        wef_plife[m] = smoothstep(0.0, 0.25, a) * exp(-max(a - 2.0, 0.0) / 2.2);
        wef_pmax = max(wef_pmax, vec2<f32>(rr + rad * 1.4, max(y, rad * 0.4) + rad * 1.4));
    }
    return o;
}
// The breach's numbers at ab seconds, size S: x the skirt's front, y the boil's ring (its middle out), z its height,
// w its tube's radius.
fn wef_boil(ab: f32, S: f32) -> vec4<f32> {
    let rf = WE_R + 10.0 + S * 75.0 * (1.0 - exp(-ab / 2.5)) + 1.0 * ab;
    let rc = WE_R + 12.0 + 26.0 * S * (1.0 - exp(-ab / 1.6)) + 1.5 * ab;
    let hc = S * (8.0 + 66.0 * (1.0 - exp(-ab / 1.5))) * (1.0 - 0.35 * smoothstep(6.0, 18.0, ab));
    let tube = S * (10.0 + 24.0 * (1.0 - exp(-ab / 1.3))) + 1.1 * ab;
    return vec4<f32>(rf, rc, hc, tube);
}
// The bite's rebound at its age ai: x the splash crown's top, y the ground wave's front, z the rim cloud's middle, w its
// width.
fn wef_splash(ai: f32, S: f32) -> vec4<f32> {
    let tt = max(ai - 0.12, 0.0);
    let top = max(S * 230.0 * (1.0 - exp(-tt / 0.6)) - 9.0 * max(tt - 2.6, 0.0) * max(tt - 2.6, 0.0), 0.0);
    let rf = 45.0 + 310.0 * S * (1.0 - exp(-ai / 1.8));
    let rc = (WE_R + 17.0) - 8.0 * smoothstep(0.0, 5.0, ai);
    let wid = 10.0 + 2.2 * min(ai, 6.0) + 0.5 * max(ai - 6.0, 0.0);
    return vec4<f32>(top, rf, rc, wid);
}
// The dust of a hole at p (from the origin), over ground g0 (as wef_src_ground has it): x its density (extinction a
// block), y its height over the land, z how grey (stone dust) it is, w how much of it is clods of dark earth rather
// than dust. `lite`: its bulk only, for the looks towards the sun.
fn wef_hole_dust(p: vec3<f32>, hk: WefHk, t: f32, g0: f32, lite: bool) -> vec4<f32> {
    let H = hk.H;
    let k = hk.k;
    let q = p - H;
    let r = length(q.xz);
    // (the hole itself: dust may hang down in it; measured from its rim, not its floor)
    let inhole = smoothstep(WE_R + 14.0, WE_R + 4.0, r);
    let g = mix(g0, H.y, smoothstep(WE_R + 22.0, WE_R + 6.0, r));
    let h = p.y - g;
    if (h < -4.0 - 30.0 * inhole || h > 260.0) {
        return vec4<f32>(0.0, h, 0.0, 0.0);
    }
    let w = p + vec3<f32>(f32(k) * 71.0, 0.0, f32(k) * 37.0);
    let cs = q.xz / max(r, 1.0e-3);
    var den = 0.0;
    // (thrown earth: not thinned with distance as the dust is)
    var keep = 0.0;
    var grey = 0.0;
    var dark = 0.0;
    // ---- the breach --------------------------------------------------------------------------------------------
    let ab = hk.ab;
    if (ab > 0.0 && ab < WEF_LIFE) {
        let S = hk.sb;
        let bo = wef_boil(ab, S);
        // (the burst: a low sheet of earth and dust blasted out over the land the moment it breaks)
        if (ab < 2.0) {
            let rb = WE_R + 4.0 + 95.0 * S * (1.0 - exp(-ab / 0.3));
            let hb = S * (6.0 + 14.0 * (1.0 - exp(-ab / 0.2))) * (1.0 - 0.6 * saturate((r - WE_R) / 110.0));
            if (r < rb + 18.0 && h < hb * 1.6) {
                let m1 = wef_dome(wef_turn(0, w * (1.0 / 7.0) + vec3<f32>(0.0, -2.0 * ab, 0.0)));
                let top = hb * (0.25 + 0.95 * m1);
                let sheet = smoothstep(rb + 12.0, rb - 6.0, r + (m1 - 0.5) * 20.0) * saturate((top - h) / 2.5) * smoothstep(-4.0 - 20.0 * inhole, 0.0, h);
                let bd = 0.12 * S * exp(-ab / 0.45) * sheet;
                den = den + bd;
                dark = dark + 0.7 * bd;
            }
        }
        // (the skirt: the boil's dust spreading low and wide over the land, 200 blocks and more over fifteen seconds, a
        // body of dust with height: its front a rolling head, its top cauliflower lumps lit on one side, thinning slowly)
        let hw0 = S * (5.0 + 7.0 * exp(-max(bo.x - r, 0.0) / 30.0)) + 0.25 * ab;
        if (r < bo.x + 30.0 && h < hw0 * 2.2 + 4.0 && ab > 0.4) {
            let rl = wef_roll(r, h, bo.x - 0.45 * hw0, 0.35 * hw0, -1.3 * ab / (1.0 + 0.25 * ab), 0.6 * hw0 + 4.0);
            let wq = vec3<f32>(cs.x * rl.x, rl.y, cs.y * rl.x) + H + vec3<f32>(f32(k) * 71.0, 0.0, 0.0);
            let sc = 1.0 / (9.0 + 0.9 * ab);
            // (its lumps in the world's own frame, carried out a little with the front and rising slowly: rolled
            // coordinates would stretch them into bands)
            let wl = w - vec3<f32>(cs.x, 0.0, cs.y) * (0.5 * (bo.x - WE_R)) - vec3<f32>(0.0, 0.6 * ab, 0.0);
            let b1 = wef_dome(wef_turn(0, wl * sc));
            let lob = wef_vn(vec2<f32>(cs.x * r, cs.y * r) * (1.0 / 45.0) + vec2<f32>(f32(k) * 3.0, 0.03 * ab));
            var b2 = 0.45;
            let top0 = hw0 * (0.55 + 0.6 * lob) * (0.55 + 0.6 * b1);
            let s0 = bo.x - r + (b1 - 0.5) * 24.0 * S;
            if (!lite && (abs(top0 - h) < 0.35 * hw0 || abs(s0) < 12.0)) {
                b2 = wef_dome(wef_turn(1, wl * sc * 2.6 + vec3<f32>(3.0, 0.0, 1.0)));
            }
            // (its front lumped too, at both sizes, so it is never a smooth wall seen from the side)
            let s = s0 + (b2 - 0.45) * 16.0 + (lob - 0.5) * 20.0;
            let head = 1.0 + 0.35 * exp(-(s - 0.4 * hw0) * (s - 0.4 * hw0) / (hw0 * hw0 + 30.0));
            let top = hw0 * head * (0.55 + 0.6 * lob) * (0.55 + 0.6 * b1 + 0.3 * (b2 - 0.45));
            if (!lite) {
                wef_crease = saturate(0.4 + 0.55 * b1 + 0.25 * (b2 - 0.45));
            }
            let inside = saturate((top - h) / (1.0 + 0.12 * hw0)) * saturate(s / 5.0) * smoothstep(-4.0 - 20.0 * inhole, 0.0, h) * smoothstep(0.4, 2.0, ab);
            let life = 0.75 * exp(-ab / 3.0) + 0.15 * exp(-ab / 8.0);
            den = den + 0.3 * S * inside * life;
        }
        if (!lite) {
            // (the dust crown round the body as it punches out: a shell of earth-dust rising with it and falling back)
            if (ab < 6.0 && r < WE_R + 12.0 + 18.0 * ab) {
                let hc = S * 120.0 * (1.0 - exp(-ab / 0.45)) - 16.0 * max(ab - 1.3, 0.0) * max(ab - 1.3, 0.0);
                if (h < hc) {
                    let shell = exp(-max(r - WE_R - 1.0, 0.0) / (3.0 + 5.0 * ab)) * smoothstep(WE_R - 6.0, WE_R, r);
                    let st = wef_dome(wef_turn(1, vec3<f32>(cs.x * WE_R, h - 40.0 * ab, cs.y * WE_R) * (1.0 / 9.0) + vec3<f32>(f32(k) * 9.0, 0.0, 0.0)));
                    let dd = 0.22 * S * shell * smoothstep(max(hc, 0.0), max(hc, 0.0) * 0.4, h) * exp(-ab / 1.4) * smoothstep(0.35, 0.75, st);
                    keep = keep + dd;
                    dark = dark + dd;
                }
            }
            // (earth pouring off the plates as the body climbs: sheets and streams falling down its sides, for seconds)
            if (hk.climb > 0.0 && r < WE_R + 10.0 && r > WE_R - 2.0 && h < hk.climb) {
                let shell = smoothstep(WE_R - 2.0, WE_R + 1.0, r) * smoothstep(WE_R + 10.0, WE_R + 2.0, r);
                let fall = wef_dome(wef_turn(2, vec3<f32>(cs.x * WE_R, (h + 30.0 * ab) * 0.6, cs.y * WE_R) * (1.0 / 5.0) + vec3<f32>(f32(k) * 5.0, 0.0, 0.0)));
                let fine = 0.5;
                let pour = (exp(-(ab - 0.3) / 4.0) + 0.3) * smoothstep(hk.tout + 1.0, hk.tout - 1.0, t);
                let dd = 0.55 * S * shell * smoothstep(hk.climb, hk.climb * 0.55, h) * smoothstep(0.5, 0.72, fall * 0.75 + fine * 0.25) * pour;
                keep = keep + dd;
                dark = dark + dd;
            }
        }
        grey = grey + 0.2 * exp(-ab / 3.0);
    }
    // (the boil: a ring of billows round the body's foot, each born as it breaks through, climbing to 40 or 100
    // blocks and swelling as it slows, rolling over on itself; from five seconds or so they settle into the skirt.
    // Their middles and sizes worked out once a ray: wef_hk)
    if (h < wef_pmax.y && r < wef_pmax.x) {
        var f = 1.0e9;
        var near = wef_pni;
        if (lite) {
            // (a look towards the sun: only the billow the march last found itself in)
            let pf = wef_gpuf(k, near);
            var dv = p - pf.xyz;
            dv.y = dv.y / select(1.0, 1.6, dv.y < 0.0);
            f = select(1.0e9, length(dv) - pf.w, pf.w > 0.0);
        } else {
            var nd = 1.0e9;
            for (var m = 0u; m < WEF_NP; m = m + 1u) {
                let pf = wef_gpuf(k, m);
                if (pf.w <= 0.0) {
                    continue;
                }
                var dv = p - pf.xyz;
                dv.y = dv.y / select(1.0, 1.6, dv.y < 0.0);
                let d = length(dv) - pf.w;
                // (a soft union: the billows run into each other, one mass)
                let hh = saturate(0.5 + 0.5 * (f - d) / 10.0);
                f = mix(f, d, hh) - 10.0 * hh * (1.0 - hh);
                if (d < nd) {
                    nd = d;
                    near = m;
                }
            }
            wef_pni = near;
        }
        let pf = wef_gpuf(k, near);
        if (pf.w > 0.0 && f < pf.w * 0.6) {
            // (cauliflower lumps on it as the Payload's boil has them: big domes, middling ones on them, all carried
            // and rolled with the billow they are on, the domain a little warped so no dome shows round)
            let lp = wef_rot(p - pf.xyz, wef_gpax(k, near).xyz, wef_gpax(k, near).w) + vec3<f32>(f32(near) * 37.0, f32(k) * 11.0, 0.0);
            let sc = 1.0 / (0.42 * pf.w);
            // (the domain warped a little, cheaply, so no dome shows round)
            let lq = lp * sc;
            let wq3 = lq + 0.35 * sin(lq.yzx * 0.9 + vec3<f32>(1.3, 4.1, 2.7));
            let b1 = wef_dome(wef_turn(0, wq3));
            var b2 = 0.45;
            // (the middling lumps only near its surface, where they show)
            if (!lite && abs(f - 0.45 * pf.w * (b1 - 0.3)) < 0.3 * pf.w) {
                b2 = wef_dome(wef_turn(1, wq3 * 2.4 + vec3<f32>(1.7, 0.0, 3.1)));
            }
            let d = min(f - (0.65 * pf.w * (b1 - 0.3) + 0.2 * pf.w * (b2 - 0.4)), f + 0.3 * pf.w);
            // (crisp-edged and dense: a short ramp from its surface in, so it reads as a volume with an edge, not a fuzz)
            let bd = 0.5 * saturate(-d / (1.2 + 0.08 * pf.w)) * wef_gplife(k, near) * smoothstep(-4.0 - 20.0 * inhole, 1.0, h);
            if (!lite) {
                wef_crease = mix(wef_crease, saturate(0.35 + 0.6 * b1 + 0.25 * (b2 - 0.45)), saturate(bd * 8.0));
            }
            den = den + bd;
            dark = dark + bd * 0.3;
        }
    }
    // ---- the dome's cracks puffing before a breach ------------------------------------------------------------
    if (!lite && hk.dome > 0.01 && h < 8.0 && r < WE_DOME_R * 1.2) {
        let c = wef_crack(q.xz, hk.dome);
        den = den + 0.06 * (c.y + c.x) * smoothstep(3.0 + 4.0 * hk.dome, 0.0, h) * hk.dome;
    }
    // ---- the bite ----------------------------------------------------------------------------------------------
    let ai = hk.ai;
    if ((k & 1u) == 1u && ai > -1.8 && ai < WEF_LIFE) {
        let S = hk.bs;
        if (!lite && ai < 0.1 && r < 55.0 && h < 7.0) {
            // (before it: the land under the coming mouth shivers and shakes a little dust up)
            let sh = gnoise3(vec3<f32>(w.x / 4.0, w.z / 4.0, t * 6.0));
            den = den + 0.07 * S * smoothstep(-1.8, 0.0, ai) * smoothstep(55.0, 30.0, r) * smoothstep(2.0 + 4.0 * smoothstep(-1.8, 0.0, ai), 0.0, h) * saturate(sh * 2.0 - 0.6);
        }
        if (ai > 0.0) {
            let sp = wef_splash(ai, S);
            let n3 = gnoise3(w * (1.0 / 34.0) + vec3<f32>(0.0, -0.05 * ai, 11.0));
            // (the ground wave: a low ring racing out over the land to 300 blocks and more, hugging it, no dome)
            if (ai < 12.0) {
                let hw = (5.0 + 14.0 * exp(-ai / 2.0)) * (1.0 - 0.55 * saturate((r - 45.0) / 300.0)) * (0.45 + 1.1 * n3 * n3);
                if (r < sp.y + 10.0 && h < hw) {
                    let n1 = wef_dome(wef_turn(0, w * (1.0 / 6.0) + vec3<f32>(0.0, -0.9 * ai, 0.0)));
                    let s = sp.y - r + (n1 - 0.5) * 14.0;
                    let ring = exp(-max(s, 0.0) / (8.0 + 4.0 * ai)) * smoothstep(-2.5, 2.0, s);
                    den = den + 0.4 * S * ring * saturate((hw * (0.3 + 0.9 * n1) - h) / 1.5) * smoothstep(-3.0, 0.0, h) * exp(-ai / 4.0);
                }
            }
            // (the splash: as the body drives into the hole, heavy clumps of earth thrown up and out round it, each
            // trailing dust, higher than the breach's, falling back outward (wef_hk's wef_cl, wef_ct))
            if (h < wef_cmax.y && r < wef_cmax.x) {
                var f = 1.0e9;
                var near = 0u;
                var nu = 0.0;
                for (var m = 0u; m < WEF_NC; m = m + 1u) {
                    let hc = wef_gcl(k, m);
                    if (hc.w <= 0.0) {
                        continue;
                    }
                    let tc = wef_gct(k, m);
                    let ab2 = hc.xyz - tc.xyz;
                    let u = saturate(dot(p - tc.xyz, ab2) / max(dot(ab2, ab2), 1.0e-3));
                    let d = length(p - tc.xyz - ab2 * u) - mix(tc.w, hc.w, u);
                    if (d < f) {
                        f = d;
                        near = m;
                        nu = u;
                    }
                }
                let rad = wef_gcl(k, near).w;
                if (rad > 0.0 && f < rad * 0.7) {
                    let lp = p - wef_gcl(k, near).xyz + vec3<f32>(f32(near) * 19.0, f32(k) * 7.0, 0.0);
                    let b1 = wef_dome(wef_turn(0, lp * (1.0 / (0.45 * rad))));
                    let d = min(f - 0.5 * rad * (b1 - 0.3), f + 0.35 * rad);
                    let dd = 0.22 * saturate(-d / (2.0 + 0.2 * rad)) * wef_gctl(k, near) * (0.45 + 0.55 * nu);
                    keep = keep + dd;
                    // (the clump itself darker earth, its trail dust)
                    dark = dark + dd * mix(0.05, 0.45, nu * nu);
                }
            }
            // (the rim failing inward under a towering rolling cloud, creeping in over the hole)
            let Hc = 6.0 + 26.0 * smoothstep(0.2, 3.0, ai) + 0.2 * ai;
            if (abs(r - sp.z) < 2.6 * sp.w && h < Hc * 1.6) {
                let rl = wef_roll(r, h, sp.z, 0.45 * Hc, 0.9 * ai / (1.0 + 0.3 * ai), 0.6 * Hc + 4.0);
                let wq = vec3<f32>(cs.x * rl.x, rl.y, cs.y * rl.x) + H + vec3<f32>(f32(k) * 13.0, 0.0, 0.0);
                let m1 = wef_dome(wef_turn(0, wq / (9.0 + 0.8 * ai) + vec3<f32>(0.0, -0.2 * ai, 0.0)));
                var m2 = 0.45;
                let dt0 = length(vec2<f32>((r - sp.z) / sp.w, (h - 0.42 * Hc) / (0.55 * Hc))) - 1.0 - 0.5 * (m1 - 0.45);
                if (!lite && abs(dt0) < 0.3) {
                    m2 = wef_dome(wef_turn(1, wq / (3.6 + 0.3 * ai) + vec3<f32>(5.0, -0.4 * ai, 2.0)));
                }
                // (a rolling bank: its section round the rim a rounded mass, its surface lumped)
                let dt = length(vec2<f32>((r - sp.z) / sp.w, (h - 0.38 * Hc) / (0.5 * Hc))) - 1.0 - (0.6 * (m1 - 0.5) + 0.25 * (m2 - 0.45) + 0.25 * (n3 - 0.5));
                let tor = saturate(-dt / 0.12) * smoothstep(-30.0 * inhole - 3.0, 0.0, h);
                den = den + 0.2 * S * smoothstep(0.05, 0.6, ai) * (exp(-ai / 3.5) + 0.15 * exp(-ai / 9.0)) * tor;
            }
            // (the land drawn in: dust streaming in to the mouth and down, its streaks shrinking in)
            if (!lite && ai < 4.0 && r < 95.0 && h < 30.0) {
                let zin = 1.0 + 1.2 * ai;
                let st = gnoise3(vec3<f32>(cs.x * 5.0, cs.y * 5.0, r * zin / 16.0 + (h + 9.0 * ai) / 12.0 + f32(k)));
                den = den + 0.3 * S * exp(-ai / 1.2) * smoothstep(95.0, 40.0, r) * smoothstep(30.0, 2.0, h) * smoothstep(-20.0 * inhole - 2.0, 0.0, h) * saturate(st * 2.2 - 0.9);
            }
            grey = grey + 0.25;
        }
        // (the body pouring into the hole drags a thin curtain of dust down with it)
        if (!lite && ai > 0.2 && t < hk.tin + 3.0 && r > WE_R - 1.0 && r < WE_R + 9.0 && h < 45.0) {
            let shell = smoothstep(WE_R - 1.0, WE_R + 1.5, r) * smoothstep(WE_R + 9.0, WE_R + 2.5, r);
            let fall = wef_dome(wef_turn(2, vec3<f32>(cs.x * WE_R, h + 45.0 * ai, cs.y * WE_R) * (1.0 / 6.0) + vec3<f32>(f32(k) * 3.0, 0.0, 0.0)));
            let on = smoothstep(0.2, 1.0, ai) * smoothstep(hk.tin + 3.0, hk.tin, t);
            den = den + 0.07 * S * shell * smoothstep(45.0, 6.0, h) * smoothstep(-14.0, 0.0, h) * smoothstep(0.5, 0.85, fall) * on;
        }
    }
    // (dense at the hole, falling away with distance from it: a faint haze a hundred out)
    let fall = exp(-max(r - (WE_R + 12.0), 0.0) / WEF_FALL);
    // (each hole's dust faded out over its last seconds, never cut off)
    let age = select(ab, ai, (k & 1u) == 1u);
    var dsum = (den * fall + keep) * smoothstep(WEF_LIFE, WEF_LIFE - 5.0, age);
    // (and, so the end is not empty, a thin low haze over the hole that stays till the strike's end, fading with it)
    if (age > 2.0 && h < 12.0) {
        let hz = wef_dome(wef_turn(2, w * (1.0 / 14.0) + vec3<f32>(0.0, -0.1 * t, 0.0)));
        dsum = dsum + 0.1 * smoothstep(2.0, 9.0, age) * fall * saturate((4.0 + 6.0 * hz - h) / 2.5) * smoothstep(-3.0 - 20.0 * inhole, 0.0, h);
    }
    // (faded before the bounds it is marched in: no straight edge anywhere)
    dsum = dsum * smoothstep(hk.reach.x, hk.reach.x * 0.82, r) * smoothstep(hk.reach.y, hk.reach.y * 0.8, h);
    return vec4<f32>(dsum * hk.fade * WEF_AMOUNT, h, saturate(grey), dark / max(den + keep, 1.0e-5));
}
// The reach of hole k's dust at t: x how far out, y how high; 0 when it has none.
fn wef_hole_reach(k: u32, t: f32) -> vec2<f32> {
    let dm0 = select(0.0, wef_m.dome, (k & 1u) == 0u && length(wef_m.dome_at.xz - wef_knot(k).xz) < 4.0);
    if (wep_nev_ok() && mod_data[WEP_T + 8u] == 1u && k < 12u) {
        // (the tick's (strike/we_fx.rs's hole_reach), taken between it and the next; the dome's part and the cap here)
        let a = WEP_T + WEP_HK + 2u * WEP_HKS * k;
        let f = clamp((t - wep_f(WEP_T + 1u)) / wep_f(WEP_T + 6u), 0.0, 1.0);
        var rr = mix(vec2<f32>(wep_f(a + 220u), wep_f(a + 221u)), vec2<f32>(wep_f(a + WEP_HKS + 220u), wep_f(a + WEP_HKS + 221u)), f);
        if (dm0 > 0.01) {
            rr = max(rr, vec2<f32>(WE_DOME_R * 1.2, 18.0));
        }
        return vec2<f32>(min(rr.x, WE_R + 12.0 + 4.5 * WEF_FALL + 60.0), rr.y);
    }
    var R = 0.0;
    var top = 0.0;
    let ab = t - wef_tb(k);
    if (ab > 0.0 && ab < WEF_LIFE) {
        let S = wef_sb(k);
        let bo = wef_boil(ab, S);
        R = max(bo.x + 30.0, WE_R + 34.0 + 3.5 * ab + 40.0 * S);
        top = S * 80.0 + 30.0;
        if (ab < 6.0) {
            top = max(top, S * 125.0);
        }
    }
    let dm = select(0.0, wef_m.dome, (k & 1u) == 0u && length(wef_m.dome_at.xz - wef_knot(k).xz) < 4.0);
    if (dm > 0.01) {
        R = max(R, WE_DOME_R * 1.2);
        top = max(top, 18.0);
    }
    let ai = t - wef_ti(k);
    if ((k & 1u) == 1u && ai > -1.8 && ai < WEF_LIFE) {
        let S = wef_bs(k);
        let sp = wef_splash(max(ai, 0.0), S);
        R = max(R, max(95.0, sp.z + 2.6 * sp.w));
        top = max(top, 1.1 * S * 80.0 + 30.0);
        if (ai > 0.0 && ai < 12.0) {
            R = max(R, sp.y + 14.0);
        }
        if (ai > 0.0 && ai < 10.0) {
            // (the thrown clumps)
            top = max(top, 250.0);
            R = max(R, 200.0);
        }
    }
    // (the low haze over it, from two seconds on, gone with the rest of its dust: no march at all after that)
    let age = select(ab, ai, (k & 1u) == 1u);
    if (age > 2.0 && age < WEF_LIFE) {
        R = max(R, WE_R + 12.0 + 3.0 * WEF_FALL);
        top = max(top, 14.0);
    }
    // (past four falloffs nothing is left to see)
    return vec2<f32>(min(R, WE_R + 12.0 + 4.5 * WEF_FALL + 60.0), top);
}

// ---- the runs: the land over each underground run (contract v2: the first is the approach from W0 into the first
// breach, each later one from a bite's hole down, along and up into the next breach). The mound's dust as the head
// passes under it, settling in a trail; then, behind the tail, the tunnel failing ring by ring, jets venting up in step
// with the rings and a low pall. Everything about a run is read here, in one place.
fn wef_run_n() -> u32 {
    return we_n();
}
// Where run i starts (x, its land's y, z) and where it ends (the breach it comes up into), from the origin.
fn wef_run_a(i: u32) -> vec3<f32> {
    return we_run_from(i);
}
fn wef_run_b(i: u32) -> vec3<f32> {
    return we_arch_from(i);
}
// When its tunnel fails: x the first ring (at its start), y how long till the last (at its end). The land's words
// (its trench's t_sink0, t_sink1) when given; else the tail passing along it: from the tail leaving its start to the
// tail leaving its breach, and 0.3 s.
fn wef_run_sink(i: u32) -> vec2<f32> {
    let s0 = wef_lw(i, 6u);
    let s1 = wef_lw(i, 7u);
    if (s0 > 0.0 && s1 > s0) {
        return vec2<f32>(s0, s1 - s0);
    }
    let end = wef_tail_out(2u * i) + 0.3;
    let dur = clamp(we_run_len(i) / max(we_aw(i, WE_R_VIN), 60.0), 3.0, 9.0);
    return vec2<f32>(end - dur, dur);
}
// When the head passed under the point f of the way along run i (0 its start, 1 its breach): its schedule along the run
// (Hermite from its start's time and speed to the breach's), turned round by a few Newton steps. (What the run's
// down and up legs take is counted on the way.)
fn wef_run_pass(i: u32, f: f32) -> f32 {
    let t0 = we_aw(i, WE_R_RUN_T);
    let t1 = we_arch_t_out(i);
    let L = max(we_run_len(i), 1.0);
    let A = we_run_from(i);
    let B = we_arch_from(i);
    let ry = we_run_y(i);
    let down = select(0.0, max(A.y - ry, 0.0), we_run_dive(i));
    let up = max(B.y - ry, 0.0);
    let u = clamp((down + f * max(L - down - up, 1.0)) / L, 0.0, 1.0);
    let T = max(t1 - t0, 0.1);
    let m0 = we_aw(i, WE_R_RUN_V) * T / L;
    let m1 = we_aw(i, WE_R_VOUT) * T / L;
    var x = u;
    for (var k = 0; k < 4; k = k + 1) {
        let x2 = x * x;
        let x3 = x2 * x;
        let hv = (x3 - 2.0 * x2 + x) * m0 + (-2.0 * x3 + 3.0 * x2) + (x3 - x2) * m1;
        let dv = (3.0 * x2 - 4.0 * x + 1.0) * m0 + (-6.0 * x2 + 6.0 * x) + (3.0 * x2 - 2.0 * x) * m1;
        x = clamp(x - (hv - u) / max(dv, 0.05), 0.0, 1.0);
    }
    return t0 + x * T;
}
// The dust of run i at p (from the origin) over ground g; `tp` when the head passed under it (wef_march works it out a
// few times along the ray): x its density, y its height over the land, z grey.
fn wef_run_dust(p: vec3<f32>, i: u32, t: f32, g: f32, tp: f32) -> vec4<f32> {
    let F = wef_run_a(i);
    let T = wef_run_b(i);
    let dv = (T - F).xz;
    let len = max(length(dv), 1.0);
    let d = dv / len;
    let q = p.xz - F.xz;
    let x = dot(q, d);
    let v = q.x * d.y - q.y * d.x;
    let h = p.y - g;
    // (the trench is ~50 across: dust may lie down in it)
    let intr = smoothstep(30.0, 20.0, abs(v)) * step(0.0, x) * step(x, len);
    if (h < -3.0 - 24.0 * intr || h > 95.0 || x < -70.0 || x > len + 30.0) {
        return vec4<f32>(0.0, h, 0.0, 0.0);
    }
    let w = p + vec3<f32>(f32(i) * 53.0, 0.0, 0.0);
    let ap = t - tp;
    let sk = wef_run_sink(i);
    let ar = t - (sk.x + sk.y * clamp(x, 0.0, len) / len);
    // (the sign of the head passing under: short heavy bursts of dust kicked up along its track, from where it has
    // levelled out right into the breach's hole, irregular in size and spacing, closer and bigger as it nears the breach;
    // each rises a few blocks, leans back along the track and is gone in two or three seconds)
    let x0 = select(8.0, 45.0, we_run_dive(i));
    let trail_on = ap > -0.3 && ap < 6.0 && x > x0 - 60.0 && x < len && h < 85.0 && abs(v) < 72.0;
    if (!trail_on && ar <= 0.0) {
        return vec4<f32>(0.0, h, 0.0, 0.0);
    }
    var den = 0.0;
    var dark = 0.0;
    var wsh = 0.0;
    if (trail_on) {
        let f = saturate(x / len);
        // (one lumpy field for all of it, clods about seven blocks across, carried back and up with the throw)
        let n2 = wef_dome(wef_turn(1, (w + vec3<f32>(2.0 * ap, -7.0 * max(ap, 0.0), 0.0)) * (1.0 / 7.0)));
        // (the heave: a ragged wall of dark earth the width of the body, heaved up all along the front over the head,
        // 15 to 30 high, thrown out to the sides as it climbs, falling back behind as the head moves on: solid at its
        // core, torn into clods at its top and edges)
        if (ap > -0.05 && ap < 2.6 && x > -5.0) {
            // (near, a low tight band under the blocks; past 150 blocks from the eye as tall and dense as a wall of
            // earth 20 to 40 high, so it reads from there: eased between 100 and 160)
            let fr = wef_fr;
            let hw = mix(28.0, 34.0, fr);
            let nx = wef_vn(vec2<f32>(x * 0.09, f32(i) * 7.0 + 3.0));
            let Hw = mix(10.0 + 8.0 * nx, 20.0 + 16.0 * nx, fr) * (1.0 + 0.25 * f * f);
            let ap0 = max(ap, 0.0);
            let rise = 1.0 - exp(-ap0 / 0.12);
            let fall = 1.0 - smoothstep(0.3, 1.4, ap0);
            let hh = max(h, 0.0);
            let vv = abs(v) - 0.35 * hh * smoothstep(0.0, 0.8, ap0);
            let across = saturate(1.0 - (vv / hw) * (vv / hw));
            // (its top lumpy, in the earth's own lumps: no streaks)
            let top = Hw * rise * (0.15 + 0.85 * fall) * sqrt(across) * (0.55 + 0.7 * n2);
            let uh = hh / max(top, 1.0);
            // (edges as soft as the march's step and no softer than two blocks)
            let sw = max(1.0, 0.8 * wef_dt);
            // (its foot ends at the ground it stands on: nothing of it lies over the land in front or under it)
            let core = saturate((top - hh) / sw) * smoothstep(0.0, 1.5, h) * saturate((hw - vv) / sw);
            let torn = mix(1.0, saturate(1.5 * n2 - 0.1), smoothstep(0.45, 0.95, uh) + smoothstep(0.75, 1.0, abs(vv) / hw));
            // (as it falls back it lands and is gone: no low sheet of it left lying over the land behind)
            // (and no low band of it lying on the land: what is under five or so high is gone; seen from above it read as a
            // dark smear along the track)
            let wv = mix(1.4, 2.6, fr) * core * saturate(torn) * smoothstep(-0.05, 0.04, ap) * smoothstep(0.15, 0.6, fall) * smoothstep(3.0, 7.0, top) * mix(0.55, 1.0, smoothstep(0.0, x0 + 15.0, x)) * smoothstep(-5.0, 10.0, x);
            // (its body: lit on the sun's side and on its top, dark on the other and deep inside, darkest at its foot;
            // the lumps each shaded)
            let side = sign(v) * vec3<f32>(d.y, 0.0, -d.x);
            let nrm = normalize(side * smoothstep(0.3, 1.0, abs(vv) / hw) + vec3<f32>(0.0, 0.25 + uh * uh, 0.0) + (n2 - 0.5) * vec3<f32>(0.6, 0.0, -0.6));
            let lit = saturate(0.3 + 0.8 * dot(nrm, wef_L));
            let deep = saturate(min(top - hh, hw - vv) / 7.0);
            let shade = 0.8 * lit * mix(1.0, 0.4, deep) * (0.5 + 0.5 * n2) * mix(0.55, 1.0, saturate(hh / 6.0));
            wsh = wsh + wv * shade;
            den = den + wv;
            dark = dark + wv;
        }
        // (cells along the track, closer together near the breach: 24 blocks apart at the start, 11 at the end; each
        // burst looked for in its own cell and its two neighbours, so none is cut off at a cell's edge)
        let u = x / 24.0 + (f * f * f) * len * (1.0 / 11.0 - 1.0 / 24.0) / 3.0;
        let spc = mix(24.0, 11.0, f * f);
        for (var m = -1; m <= 1; m = m + 1) {
            let c = floor(u) + f32(m);
            let hc = wef_vh(vec2<f32>(c, f32(i) + 31.0));
            if (hc <= mix(0.6, 0.45, wef_fr)) {
                continue;
            }
            let dx = (u - c - 0.5 - (wef_vh(vec2<f32>(c, f32(i) + 37.0)) - 0.5) * 0.6) * spc;
            let a = ap - 0.12 * wef_vh(vec2<f32>(c, f32(i) + 41.0));
            if (a <= 0.0 || a > 5.5) {
                continue;
            }
            // (the ground erupting: a jet of soil and rock punched up and out of the line, narrow at its foot and
            // fanning as it climbs, leaning back along the track like a ploughed spray; sharp and fast at the start (to
            // 15 or 30 blocks in a few tenths of a second), ragged at the top, then falling back as earth; a thin pale veil
            // of dust trailing it. Bigger toward the breach.)
            let Hb = mix(18.0 + 17.0 * saturate((hc - 0.6) / 0.4), 30.0 + 30.0 * (hc - 0.45) / 0.55, wef_fr) * (1.0 + 0.2 * f * f);
            let vc = (wef_vh(vec2<f32>(c, f32(i) + 43.0)) - 0.5) * 44.0;
            let top = max(Hb * (1.0 - exp(-a / 0.16)) - 14.0 * max(a - 0.55, 0.0) * max(a - 0.55, 0.0), 0.0);
            // (three jets from one foot, each its own height and tilt back along the track: fingers of earth, not one
            // shape; dense low down, torn into clumps higher up where the clods fly apart)
            let hh = max(h, 0.0);
            let b1 = n2;
            var earth = 0.0;
            var wid = 0.0;
            for (var s = 0; s < 3; s = s + 1) {
                let hs = wef_vh(vec2<f32>(c * 3.0 + f32(s), f32(i) + 47.0));
                let Hs = top * (0.45 + 0.55 * hs);
                let tilt = 0.15 + 0.7 * wef_vh(vec2<f32>(c * 3.0 + f32(s), f32(i) + 53.0));
                let side = (f32(s) - 1.0) * (0.12 + 0.1 * hs);
                let ax = dx + tilt * hh + 3.0 * a + f32(s - 1) * 1.5;
                let av = v - vc - side * hh;
                let ws = (2.5 + 0.16 * hh) * (1.0 + 0.3 * f * f);
                wid = max(wid, ws);
                let r = length(vec2<f32>(ax, av * 1.3));
                let u = hh / max(Hs, 1.0);
                let tear = mix(1.0, saturate(1.7 * b1 - 0.15), smoothstep(0.35, 0.95, u));
                // (its top torn: clods thrown higher here, lower there)
                let ut = 0.6 + 0.55 * b1;
                earth = max(earth, saturate((ws - r) / max(1.0, 1.2 * wef_dt)) * smoothstep(ut, ut - 0.3, u) * tear);
            }
            earth = earth * smoothstep(0.0, 1.5, h);
            let rr = abs(dx + 0.4 * hh + 3.0 * a);
            let rag = top;
            let alive = smoothstep(0.0, 0.05, a) * smoothstep(2.4, 1.2, a);
            let bd = 3.0 * earth * alive * smoothstep(x0 - 20.0, x0 + 10.0, x - dx);
            // (the veil of dust it trails: wider, pale and thin, lasting a little longer)
            // (hugging the jets: no column of its own, its top as torn as theirs)
            let veil = saturate((wid * 1.4 + 1.5 - length(vec2<f32>(rr, v - vc))) / 2.5) * smoothstep(rag * (0.6 + 0.5 * b1), rag * 0.3, h) * smoothstep(0.0, 1.5, h);
            let vd = 0.04 * veil * smoothstep(0.1, 0.4, a) * smoothstep(2.2, 1.0, a) * smoothstep(x0 - 20.0, x0 + 10.0, x - dx);
            den = den + bd + vd;
            dark = dark + bd;
            wsh = wsh + bd * (0.45 + 0.55 * b1) * mix(0.6, 1.0, saturate(hh / 8.0)) + vd;
            // (lit from below by the teal for a moment, low in it, flickering)
            wef_glow = max(wef_glow, saturate(bd * 6.0) * exp(-a / 0.45) * smoothstep(max(top, 2.0) * 0.6, 0.0, h) * (0.6 + 0.4 * sin(t * 31.0 + c * 2.3)));
        }
        // (none over the breach's own hole, where the body comes up: faded out over the last stretch)
        let edge = smoothstep(len, len - 25.0, x) * smoothstep(72.0, 58.0, abs(v));
        den = den * edge;
        dark = dark * edge;
        wsh = wsh * edge;
    }
    // (the tunnel failing, behind the tail)
    if (ar > 0.0) {
        let n1 = gnoise3(w * vec3<f32>(1.0 / 6.0, 1.0 / 8.0, 1.0 / 6.0) + vec3<f32>(0.0, -0.8 * t, 0.0));
        let n3 = gnoise3(w * (1.0 / 26.0) + vec3<f32>(0.0, -0.04 * t, 2.0));
        // (the ends: the holes, where it starts and stops)
        let ends = smoothstep(-25.0, 15.0, x) * smoothstep(len + 25.0, len - 15.0, x);
        // (the jets: one every ~20 blocks along the line, each fired as its ring sinks, a little off the line to one
        // side or the other: a column bursting up to 35 or 70 blocks, leaning and drifting its own way, its top
        // spreading, lifting off the ground and thinning as the vent stops)
        var jet = 0.0;
        var pall = 0.0;
        let c0 = floor(x / 20.0);
        for (var m = -1; m <= 1; m = m + 1) {
            let c = c0 + f32(m);
            let hj = wef_vh(vec2<f32>(c, f32(i) + 3.0));
            let xc = (c + 0.5) * 20.0 + (hj - 0.5) * 8.0;
            if (xc < 0.0 || xc > len) {
                continue;
            }
            let vc = select(-1.0, 1.0, (i32(c) & 1) == 0) * (4.0 + 10.0 * wef_vh(vec2<f32>(c, f32(i) + 9.0)));
            let aj = t - (sk.x + sk.y * xc / len) - 0.3 * wef_vh(vec2<f32>(c, f32(i) + 5.0));
            if (aj <= 0.0) {
                continue;
            }
            let top = (14.0 + 18.0 * hj) * (1.0 - exp(-aj / 0.45)) + 1.0 * aj;
            let bot = 9.0 * max(aj - 1.2, 0.0);
            let la = 6.2831853 * wef_vh(vec2<f32>(c, f32(i) + 7.0));
            let lean = vec2<f32>(cos(la), sin(la)) * ((0.18 + 0.06 * aj) * max(h, 0.0) + 2.0 * aj);
            let dd = vec2<f32>(x - xc, v - vc) - lean;
            let u = saturate(h / max(top, 1.0));
            let rj = (3.0 + 1.3 * aj + 0.1 * max(h, 0.0)) * (1.0 + 1.0 * smoothstep(0.55, 1.0, u));
            let env = smoothstep(top * (0.8 + 0.4 * n1), top * 0.55, h) * smoothstep(bot - 2.0, bot + 4.0, h);
            jet = jet + exp(-dot(dd, dd) / (2.0 * rj * rj)) * env * exp(-aj / 1.8) * step(0.2, hj);
            // (where it fell, a patch of low dust settling and spreading)
            let pr = 9.0 + 3.5 * aj;
            let pd = vec2<f32>(x - xc, v - vc);
            pall = pall + exp(-dot(pd, pd) / (2.0 * pr * pr)) * smoothstep(0.3, 1.5, aj) * (0.75 * exp(-aj / 3.5) + 0.25) * smoothstep(9.0, 4.0, aj);
        }
        let ph = (2.5 + 0.6 * ar) * (0.5 + 1.0 * n3);
        pall = pall * smoothstep(ph, 0.0, h) * smoothstep(-3.0 - 22.0 * intr, 0.0, h);
        den = den + (0.3 * jet * saturate(1.7 * n1 - 0.3) + 0.06 * pall * saturate(1.6 * n1 + 0.6 * n3 - 0.6)) * ends * smoothstep(80.0, 55.0, abs(v));
    }
    // (the earth's shading, through the march's crease)
    wef_crease = (wsh + max(den - dark, 0.0) * 1.0) / max(den, 1.0e-5);
    // (grey-brown dust, and the dark earth thrown: its share in w)
    return vec4<f32>(den * wef_fade(t) * WEF_AMOUNT, h, 0.6, dark / max(den, 1.0e-5));
}

// (whether the dust is marched at full size: fs_main)
var<private> wef_full: bool;
// (the worm's shadow on the land this pixel sees, -1 not known; and that point, from the camera)
var<private> wef_land_sh: f32;
var<private> wef_rel: vec3<f32>;
// What one source's march gave: premultiplied colour and transmittance; and how far in it starts.
var<private> wef_sc: array<vec4<f32>, 20>;
var<private> wef_st: array<f32, 20>;
var<private> wef_ns: u32;
// The ray (from the camera) through the vertical cylinder round c of radius R, y from c.y + y0 to c.y + y1: the span.
fn wef_cyl(rd: vec3<f32>, c: vec3<f32>, R: f32, y0: f32, y1: f32) -> vec2<f32> {
    let a2 = max(dot(rd.xz, rd.xz), 1.0e-8);
    let b = -dot(rd.xz, c.xz);
    let cc = dot(c.xz, c.xz) - R * R;
    let hh = b * b - a2 * cc;
    if (hh < 0.0) {
        return vec2<f32>(1.0, -1.0);
    }
    var t0 = (-b - sqrt(hh)) / a2;
    var t1 = (-b + sqrt(hh)) / a2;
    if (abs(rd.y) > 1.0e-5) {
        let ya = (c.y + y0) / rd.y;
        let yb = (c.y + y1) / rd.y;
        t0 = max(t0, min(ya, yb));
        t1 = min(t1, max(ya, yb));
    } else if (c.y + y0 > 0.0 || c.y + y1 < 0.0) {
        return vec2<f32>(1.0, -1.0);
    }
    return vec2<f32>(max(t0, 0.0), t1);
}
// The ray through a box along `d` (level, unit) from a (from the camera), `len` long, `hw` either side, y0..y1 over a.y.
fn wef_obox(rd: vec3<f32>, a: vec3<f32>, d: vec2<f32>, len: f32, hw: f32, y0: f32, y1: f32) -> vec2<f32> {
    let e = vec3<f32>(d.x, 0.0, d.y);
    let s = vec3<f32>(-d.y, 0.0, d.x);
    let o = -a;
    let ro = vec3<f32>(dot(o, e), o.y, dot(o, s));
    let rv = vec3<f32>(dot(rd, e), rd.y, dot(rd, s));
    let inv = 1.0 / select(rv, vec3<f32>(1.0e-6), abs(rv) < vec3<f32>(1.0e-6));
    let ta = (vec3<f32>(0.0, y0, -hw) - ro) * inv;
    let tb = (vec3<f32>(len, y1, hw) - ro) * inv;
    let tn = min(ta, tb);
    let tf = max(ta, tb);
    return vec2<f32>(max(max(tn.x, tn.y), max(tn.z, 0.0)), min(min(tf.x, tf.y), tf.z));
}
// The ground under p (from the origin) as source `kind` k sees it: a hole's round its height, a run's along it, the
// wormsign's lifted by the stand-in's mound (the game's picture has the warp's lift in it already).
fn wef_src_ground(kind: u32, k: u32, p: vec3<f32>, t: f32) -> f32 {
    if (kind == 0u) {
        return wef_ground(p.xz, wef_knot(k).y);
    }
    let F = wef_run_a(k);
    let T = wef_run_b(k);
    let dv = (T - F).xz;
    let f = clamp(dot(p.xz - F.xz, dv) / max(dot(dv, dv), 1.0), 0.0, 1.0);
    return wef_ground(p.xz, mix(F.y, T.y, f)) + select(0.0, wef_lift(p.xz, t), WE_STANDIN_MOUND);
}
// When the head passed under the land at p (from the origin) of run k.
// How far along run i (from its start F, along d) the head is at time tau.
fn wef_run_headx(i: u32, tau: f32, F: vec3<f32>, d: vec2<f32>) -> f32 {
    let p = we_run_at(i, clamp(we_head(tau) - we_run_s(i), 0.0, we_run_len(i))).p;
    return dot(p.xz - F.xz, d);
}
fn wef_src_pass(k: u32, p: vec3<f32>) -> f32 {
    let F = wef_run_a(k);
    let T = wef_run_b(k);
    let dv = (T - F).xz;
    return wef_run_pass(k, clamp(dot(p.xz - F.xz, dv) / max(dot(dv, dv), 1.0), 0.0, 1.0));
}
// March source `kind` (0 hole, 1 run, 2 the wormsign) number k from ta to tb in n steps; the result pushed.
fn wef_march(kind: u32, k: u32, rd: vec3<f32>, ta: f32, tb: f32, n0: i32, j: f32, t: f32, lt: WefLight, sun: vec3<f32>) {
    if (tb <= ta || wef_ns >= WEF_SRC) {
        return;
    }
    // (at full size, fewer steps: the dither between neighbouring pixels makes up for them)
    // (and more where the ray's way through it is long)
    // (and fewer for a far source: it covers few pixels and its lumps are small there)
    let far = clamp(350.0 / max(ta, 1.0), 0.45, 1.0);
    // (and above 1080 lines fewer at half size, the join's tent filter making up for them: its pixels are more and
    // smaller)
    let n = clamp(i32(f32(n0) * select(wef_det(), 0.5, wef_full) * clamp(sqrt((tb - ta) / 120.0), 0.6, 1.3) * far), 5, 36);
    var tr = 1.0;
    var acs = vec3<f32>(0.0);
    var aca = vec3<f32>(0.0);
    var tw = 0.0;
    var ws = 0.0;
    var hk: WefHk;
    if (kind == 0u) {
        hk = wef_hk(k, t);
    }
    // (the ground under the ray, looked up at three points along it and taken between them: it changes slowly)
    var ts = 1.0;
    var gl_acc = 0.0;
    var gs = array<f32, 3>(0.0, 0.0, 0.0);
    var lws = array<f32, 3>(1.0, 1.0, 1.0);
    for (var m = 0; m < 3; m = m + 2) {
        let pm = rd * (ta + (tb - ta) * f32(m) * 0.5) - we_o;
        gs[m] = wef_src_ground(kind, k, pm, t);
        lws[m] = wef_landw;
    }
    gs[1] = 0.5 * (gs[0] + gs[2]);
    lws[1] = 0.5 * (lws[0] + lws[2]);
    // (at full size there is nothing to filter the jitter from pixel to pixel: more steps there, and the earth's edges
    // as soft as a step and a half, so that the jitter leaves no screen of dots; one offset for all slices the land)
    let jj = j;
    let rlive = kind == 1u && t < we_arch_t_out(k) + 6.0;
    for (var i = 0; i < n; i = i + 1) {
        let u0 = (f32(i) + jj) / f32(n);
        let u1 = (f32(i) + jj + 1.0) / f32(n);
        // (closer together near the eye)
        // (closer together near the eye; but evenly through a run's stretch, whose earth stands in its middle, not by
        // the eye: the steps there no longer than its clods)
        let lin = kind == 1u;
        let tt = ta + (tb - ta) * select(u0 * u0, u0, lin);
        let dt = (tb - ta) * select(u1 * u1 - u0 * u0, u1 - u0, lin);
        wef_dt = dt;
        wef_tt = tt;
        wef_L = lt.L;
        let p = rd * tt - we_o;
        let gu = select(u0 * u0, u0, lin) * 2.0;
        let gi = min(i32(gu), 1);
        let g = mix(gs[gi], gs[gi + 1], gu - f32(gi));
        var dh = vec4<f32>(0.0);
        wef_crease = 1.0;
        wef_glow = 0.0;
        if (kind == 0u) {
            dh = wef_hole_dust(p, hk, t, g, false);
        } else {
            // (the head's passing worked out only while the trail can still be up)
            var tp = -1.0e9;
            if (rlive) {
                tp = wef_src_pass(k, p);
            }
            dh = wef_run_dust(p, k, t, g, tp);
        }
        // (thin right round the eye: it shows on the lens and in the air at the eye instead; and gone into the game's fog
        // as the land is, never hanging past the land's drawn edge)
        let fg = 1.0 - 0.55 * wef_fog(tt);
        let den = dh.x * smoothstep(1.5, 18.0 + 110.0 * wef_clear, tt) * mix(1.0, 0.3, wef_clear) * fg * mix(lws[gi], lws[gi + 1], gu - f32(gi));
        if (den <= 1.0e-4) {
            continue;
        }
        let al = 1.0 - exp(-den * dt);
        // (lit on its tops, dark low down and deep in)
        let lo = (0.5 + 0.5 * saturate(dh.y / 20.0)) * wef_crease;
        // (its own shadow: how much of it lies between here and the sun, a look a few blocks that way, its bulk only;
        // where it is thin it is not worth the look)
        // (every other step: the look before is kept between)
        if (kind == 0u && den > 0.01 && (i & 3) == 0) {
            ts = exp(-wef_hole_dust(p + lt.L * 8.0, hk, t, g, true).x * 14.0);
        }
        // (the earth of the place: dark soil low down, paler dust as it climbs and ages, grey stone dust from deep, dark
        // clods of earth where it is thrown earth)
        let up = smoothstep(-2.0, 45.0, dh.y);
        var alb = mix(vec3<f32>(0.15, 0.12, 0.092), vec3<f32>(0.36, 0.33, 0.29), up);
        alb = mix(alb, vec3<f32>(0.3, 0.3, 0.3) * (0.6 + 0.4 * up), dh.z * 0.6);
        alb = mix(alb, wef_earth, saturate(dh.w));
        acs = acs + tr * al * alb * lo * ts;
        // (the teal glow in a burst's foot: its own light, added where the sun's goes, scaled to come out as itself)
        gl_acc = gl_acc + tr * al * wef_glow * smoothstep(8.0, 40.0, tt);
        aca = aca + tr * al * alb * (0.55 + 0.45 * lo) * (0.6 + 0.4 * ts);
        tw = tw + tr * al * tt;
        ws = ws + tr * al;
        tr = tr * (1.0 - al);
        if (tr < 0.04) {
            break;
        }
    }
    if (ws < 1.0e-4) {
        return;
    }
    // (the body's shadow on it, where the most of it is)
    let tm = tw / ws;
    // (near the land this pixel sees, its shadow there will do: one look less)
    var sh = wef_land_sh;
    if (wef_land_sh < 0.0 || length(rd * tm - wef_rel) > 40.0) {
        sh = we_body_shade(rd * tm, sun, t);
    }
    // (the light round about: the sky's, warmed by the land under it)
    let ambd = mix(lt.amb, vec3<f32>(dot(lt.amb, vec3<f32>(0.2126, 0.7152, 0.0722))) * vec3<f32>(1.0, 0.96, 0.9), 0.8);
    var c = acs * lt.sunc * 1.05 * (0.3 + 0.7 * smoothstep(0.03, 0.45, lt.L.y)) * mix(0.25, 1.0, sh) + aca * (ambd * 0.5 + vec3<f32>(0.04, 0.04, 0.03) * lt.day);
    // (capped well under saturation: a glow at its foot, never a flood)
    c = c + vec3<f32>(0.06, 0.55, 0.5) * min(1.2 * gl_acc, 0.3);
    // (farther, greyed by the air towards the sky's colour, gently: the game's own fog is lighter than the dust's)
    c = mix(c, lt.haze * ws, (1.0 - exp(-tm / 2600.0)) * 0.6);
    wef_sc[wef_ns] = vec4<f32>(c, tr);
    wef_st[wef_ns] = ta;
    wef_ns = wef_ns + 1u;
}
// All the dust on the ray to t_end, front to back: premultiplied colour and transmittance.
fn wef_dust(rd: vec3<f32>, t_end: f32, j: f32, t: f32, lt: WefLight, sun: vec3<f32>) -> vec4<f32> {
    wef_ns = 0u;
    let n = we_n();
    let tmax = min(t_end, 2400.0);
    if (n > 0u) {
        for (var k = 0u; k < 2u * n; k = k + 1u) {
            let rr = wef_hole_reach(k, t);
            if (rr.x > 0.0) {
                let c = we_o + wef_knot(k);
                let sp = wef_cyl(rd, c, rr.x, -30.0, rr.y);
                wef_march(0u, k, rd, sp.x, min(sp.y, tmax), 14, j, t, lt, sun);
            }
        }
        for (var i = 0u; i < wef_run_n(); i = i + 1u) {
            // (while its mound's dust is up, and from its first ring on)
            let trail = t > we_aw(i, WE_R_RUN_T) - 0.5 && t < we_arch_t_out(i) + 6.0;
            let sk = wef_run_sink(i);
            if ((trail || (t > sk.x && t < sk.x + sk.y + 9.5)) && t < wef_end()) {
                // (the trail's bursts reach out of the line's box only as far as it, faded before its sides)
                let F = wef_run_a(i);
                let T = wef_run_b(i);
                let dv = (T - F).xz;
                let len = max(length(dv), 1.0);
                let d = dv / len;
                var xa = -70.0;
                var xl = len + 100.0;
                var hwb = 85.0;
                wef_fr = 0.0;
                // (before its tunnel fails, only the stretch the head has passed in the last few seconds has anything
                // in it: the march spends its steps there, a few blocks apart, not over the whole run)
                if (t < wef_run_sink(i).x) {
                    let xh = wef_run_headx(i, t, F, d);
                    let xb = wef_run_headx(i, t - 2.8, F, d);
                    xa = max(min(xb, xh) - 30.0, -70.0);
                    xl = max(xh + 25.0 - xa, 1.0);
                    hwb = 66.0;
                    wef_fr = smoothstep(100.0, 160.0, length(we_o + F + vec3<f32>(d.x, 0.0, d.y) * xh));
                }
                let a = we_o + F + vec3<f32>(d.x, 0.0, d.y) * xa;
                let sp = wef_obox(rd, a, d, xl, hwb, min(T.y - F.y, 0.0) - 28.0, max(T.y - F.y, 0.0) + 95.0);
                wef_march(1u, i, rd, sp.x, min(sp.y, tmax), 20, j, t, lt, sun);
            }
        }
    }
    // (front to back: the nearest first)
    var out = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var used = 0u;
    for (var m = 0u; m < wef_ns; m = m + 1u) {
        var best = 0u;
        var bt = 1.0e9;
        for (var q = 0u; q < wef_ns; q = q + 1u) {
            if ((used & (1u << q)) == 0u && wef_st[q] < bt) {
                bt = wef_st[q];
                best = q;
            }
        }
        used = used | (1u << best);
        let s = wef_sc[best];
        out = vec4<f32>(out.rgb + s.rgb * out.a, out.a * s.a);
    }
    return out;
}
// How much of the sun reaches land point p (from the origin) through the holes' dust: four looks towards it.
fn wef_dust_shadow(p: vec3<f32>, L: vec3<f32>, t: f32) -> f32 {
    let n = we_n();
    var tau = 0.0;
    for (var k = 0u; k < 2u * n; k = k + 1u) {
        let rr = wef_hole_reach(k, t);
        if (rr.x <= 0.0 || length((p - wef_knot(k)).xz) > rr.x + 20.0) {
            continue;
        }
        let hk = wef_hk(k, t);
        // (the land point is the ground: two looks up towards the sun, the bulk only)
        tau = tau + wef_hole_dust(p + L * 10.0, hk, t, p.y, true).x * 26.0;
    }
    return exp(-tau);
}
// ---- the pieces: the land of the place, in pieces --------------------------------------------------------------
// The breach's crown of clods and its slabs (some with their trees), the earth pouring off the body, the bite's slabs
// and its splash, the clods thrown over a passing head, the spit's burst: boxes in their own frames, textured by the
// block (wef_face, wef_obj's lumps), lit as the game lights a block. Where each is is worked out ONCE A TICK by the mod
// (strike/we_fx.rs's we_pieces_words, a port of the formulas this file had) and read here from mod_data at WEP_T: the
// live ones only, each extrapolated by the frame's time past the tick, in groups of up to 16 in boxes, the groups in
// boxes of 8, so a ray tests a few boxes and only the pieces of those it passes through. What depends on the camera (a
// hole's small ones fewer far off and at lower detail, a slab shrunk near the eye, a run's clods thinned and grown with
// the distance) is worked out here.
fn wef_ph(i: u32, k: u32, s: u32) -> f32 {
    return f32(pcg(i * 747796405u + k * 2891336453u + s * 0x9e3779b9u)) * (1.0 / 4294967296.0);
}
fn wef_rot(v: vec3<f32>, ax: vec3<f32>, an: f32) -> vec3<f32> {
    let c = cos(an);
    let s = sin(an);
    return v * c + cross(ax, v) * s + ax * dot(ax, v) * (1.0 - c);
}
// Thrown from p0 at v0, tau seconds on, slowed by the air (k) and falling (g).
fn wef_fly(p0: vec3<f32>, v0: vec3<f32>, tau: f32, kd: f32, g: f32) -> vec3<f32> {
    let e = (1.0 - exp(-kd * tau)) / kd;
    return p0 + vec3<f32>(v0.x * e, v0.y * e - g * (tau - e) / kd, v0.z * e);
}
fn wef_pdet() -> f32 {
    return select(clamp(wef_det(), 0.35, 1.0), 1.0, wef_full);
}
// The ray (ro, rv: in a box's frame) against the box lo..hi: x where it enters (-1 none), yzw the face's normal.
fn wef_box(ro: vec3<f32>, rv: vec3<f32>, lo: vec3<f32>, hi: vec3<f32>) -> vec4<f32> {
    let inv = 1.0 / select(rv, vec3<f32>(1.0e-6), abs(rv) < vec3<f32>(1.0e-6));
    let t1 = (lo - ro) * inv;
    let t2 = (hi - ro) * inv;
    let tn = min(t1, t2);
    let tf = max(t1, t2);
    let tin = max(max(tn.x, tn.y), tn.z);
    let tout = min(min(tf.x, tf.y), tf.z);
    if (tin > tout || tout < 0.0 || tin < 0.0) {
        return vec4<f32>(-1.0, 0.0, 0.0, 0.0);
    }
    let n = select(select(vec3<f32>(0.0, 0.0, -sign(rv.z)), vec3<f32>(0.0, -sign(rv.y), 0.0), tin == tn.y), vec3<f32>(-sign(rv.x), 0.0, 0.0), tin == tn.x);
    return vec4<f32>(tin, n);
}
// A face's colour at lp (in its box's frame, the box's top at `top`), facing n: a block's texture, sixteen texels a
// block; a slab (kind 10) by its layers: turf on top, a block of dirt under it, stone below, deepslate deep.
fn wef_face(kind: i32, lp: vec3<f32>, n: vec3<f32>, top: f32, seed: f32, t: f32, e: vec3<f32>) -> vec3<f32> {
    // (the game's own block there, a block to a unit, sixteen texels: a slab by its layers, turf on dirt on stone on
    // deepslate, grass on top)
    let d = top - lp.y;
    var b = wef_bof(kind);
    if (kind >= 10) {
        b = select(select(select(select(select(WEF_B_DEEP, WEF_B_STONE, d < 6.0), WEF_B_DIRT, d < 3.0), WEF_B_GRASS, d < 1.0), WEF_B_STONE, n.y < -0.5), WEF_B_GRASS, n.y > 0.5);
    }
    // (a clod is one block, its texture across the whole of it; a slab is blocks, one a unit)
    let f = select(wef_fuv(fract(lp) - 0.5, n, vec3<f32>(1.0)), wef_fuv(lp - 64.0, n, 2.0 * e), kind < 10);
    let c = wef_btex(b, u32(f.x), f.yz, wef_lod(t, select(1.0, 2.0 * max(e.x, e.z), kind < 10)));
    if (c.x >= 0.0) {
        return c;
    }
    let fuv = select(select(lp.xy, lp.xz, abs(n.y) > 0.5), lp.zy, abs(n.x) > 0.5);
    let px = floor(fuv * 16.0);
    if (kind < 10) {
        return srgb_to_linear(debris_tex(kind, px, n.y > 0.5, 0.0, seed));
    }
    let fb = abs(fract(fuv) - 0.5);
    let seam = mix(0.72, 1.0, smoothstep(0.43, 0.47, 0.5 - max(fb.x, fb.y) + 0.43));
    if (n.y > 0.5) {
        return srgb_to_linear(debris_tex(0, px, true, 0.0, seed)) * seam;
    }
    if (n.y < -0.5) {
        return srgb_to_linear(debris_tex(2, px, false, 0.0, seed)) * seam;
    }
    let k2 = select(select(select(1, 2, d > 3.0), 3, d > 6.0), 0, d < 1.0);
    return srgb_to_linear(debris_tex(k2, px, false, 1.0 - d * 5.0, seed)) * seam;
}
// A piece of the land in the air lit as the game would light a block there (the Hurricane's hu_lit): its texture by
// the game's own face shade (top brightest, the sides darker by pair, the bottom darkest; `nl` its face's normal in
// its own frame), the sky's light round it, the sun on its sun side (none in the worm's shadow), and the scene's fog
// by distance like the land behind it. `nw` the face's normal in the world, `d` how far, `rd` the ray.
fn wef_plit(tex: vec3<f32>, nl: vec3<f32>, nw: vec3<f32>, d: f32, rd: vec3<f32>, lt: WefLight, t: f32) -> vec3<f32> {
    let an = abs(nl);
    let mcs = select(select(select(0.8, 0.6, an.x > an.z), 0.5, nl.y < -0.5), 1.0, nl.y > 0.5);
    var sh = 1.0;
    if (lt.L.y > 0.0 && dot(nw, lt.L) > 0.0) {
        sh = we_body_shade(rd * d, frame.sun.xyz, t);
    }
    let c = tex * mcs * (lt.amb * (1.5 + 0.6 * nw.y) + lt.sunc * max(dot(nw, lt.L), 0.0) * 0.9 * sh + vec3<f32>(0.012));
    return mix(c, lt.fog, wef_fog(d));
}
// The pieces' table (keep in step with strike/we_fx.rs's PCS_*; its test pcs_layout_in_step checks).
const WEP_T: u32 = 20480u;
const WEP_SRC: u32 = 16u;
const WEP_SUP: u32 = 272u;
const WEP_GRP: u32 = 1040u;
const WEP_PC: u32 = 5136u;
const WEP_W: u32 = 12u;
const WEP_EV: u32 = 54288u;
const WEP_HK: u32 = 54544u;
const WEP_HKS: u32 = 232u;
const WEP_LEN: u32 = 60112u;
// Whether the tick's table is there; how many jolt and lens events it lists.
fn wep_nev_ok() -> bool {
    return arrayLength(&mod_data) >= WEP_T + WEP_LEN && mod_data[WEP_T] == 1u;
}
fn wep_nev() -> u32 {
    if (!wep_nev_ok()) {
        return 0u;
    }
    return min(mod_data[WEP_T + 7u], 32u);
}
fn wep_v4(i: u32) -> vec4<f32> {
    return vec4<f32>(wep_f(i), wep_f(i + 1u), wep_f(i + 2u), wep_f(i + 3u));
}
fn wep_f(i: u32) -> f32 {
    return bitcast<f32>(mod_data[i]);
}
fn wep_v3(i: u32) -> vec3<f32> {
    return vec3<f32>(wep_f(i), wep_f(i + 1u), wep_f(i + 2u));
}
// Whether the ray (from the camera; inv its reciprocal) passes through box b (lo, hi from the origin) before tmax, the
// box grown by `pad` blocks for every block it is from the eye.
fn wep_in(b: u32, inv: vec3<f32>, tmax: f32, pad: f32) -> bool {
    let lo = we_o + wep_v3(b);
    let hi = we_o + wep_v3(b + 3u);
    let g = pad * (length(0.5 * (lo + hi)) + 0.5 * length(hi - lo));
    let t1 = (lo - g) * inv;
    let t2 = (hi + g) * inv;
    let tn = min(t1, t2);
    let tf = max(t1, t2);
    let tin = max(max(tn.x, tn.y), max(tn.z, 0.0));
    return tin <= min(min(tf.x, tf.y), tf.z) && tin <= tmax;
}
// An axis from its octahedral words.
fn wep_axis(w: u32) -> vec3<f32> {
    let e = unpack2x16snorm(w);
    var v = vec3<f32>(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
    let k = max(-v.z, 0.0);
    v.x = v.x + select(k, -k, v.x >= 0.0);
    v.y = v.y + select(k, -k, v.y >= 0.0);
    return normalize(v);
}
// A piece drawn: the ray against the box at c (from the camera) of half sizes e, turned by an about ax (a slab, kind
// 10 or 11 (with a tree, lv its size), in its frame: x out from the hole, z along the ring (ax), y up); a clod bigger
// than a block a lump of blocks hR round (wef_obj, seed id). x its distance (-1 none, or not before best), yzw its colour.
fn wep_draw(rd: vec3<f32>, c: vec3<f32>, e: vec3<f32>, ax: vec3<f32>, an: f32, kind: i32, lump: bool, hR: f32, id: u32, fseed: f32, lv: f32, best: f32, lt: WefLight, t: f32) -> vec4<f32> {
    var ro = -c;
    var rv = rd;
    let slab = kind >= 10;
    let out = vec3<f32>(ax.z, 0.0, -ax.x);
    if (slab) {
        let m = mat3x3<f32>(out, vec3<f32>(0.0, 1.0, 0.0), ax);
        ro = wef_rot(ro, ax, -an) * m;
        rv = wef_rot(rv, ax, -an) * m;
    } else {
        ro = wef_rot(ro, ax, -an);
        rv = wef_rot(rv, ax, -an);
    }
    let eb = select(e, vec3<f32>(hR + 0.6), lump);
    var bh = wef_box(ro, rv, -eb, eb);
    var k2 = kind;
    let hty = select(select(5u, 6u, kind == 3), 4u, kind == 2);
    if (lump && bh.x >= 0.0) {
        bh = wef_obj(ro + vec3<f32>(4.5), rv, hty, i32(hR * 10.0), id);
    }
    if (kind == 11) {
        // (a tree on it: a trunk and a crown, a little off its middle)
        let tc = vec3<f32>(e.x * 0.2, e.y, -e.z * 0.25);
        let tr = wef_box(ro, rv, tc + vec3<f32>(-0.5, 0.0, -0.5) * lv, tc + vec3<f32>(0.5, 5.0, 0.5) * lv);
        if (tr.x > 0.0 && (bh.x < 0.0 || tr.x < bh.x)) {
            bh = tr;
            k2 = 4;
        }
        let cr = wef_box(ro, rv, tc + vec3<f32>(-2.5, 3.0, -2.5) * lv, tc + vec3<f32>(2.5, 7.0, 2.5) * lv);
        if (cr.x > 0.0 && (bh.x < 0.0 || cr.x < bh.x)) {
            bh = cr;
            k2 = 5;
        }
    }
    if (bh.x < 0.0 || bh.x > best) {
        return vec4<f32>(-1.0, 0.0, 0.0, 0.0);
    }
    let lp = ro + rv * bh.x;
    var nw = wef_rot(bh.yzw, ax, an);
    if (slab) {
        nw = wef_rot(out * bh.y + vec3<f32>(0.0, bh.z, 0.0) + ax * bh.w, ax, an);
    }
    var tex = vec3<f32>(0.0);
    if (lump) {
        tex = wef_vox_col(wef_ok, hty, lp + vec3<f32>(4.5), bh.yzw, bh.x, id);
    } else {
        tex = wef_face(k2, lp + vec3<f32>(64.0), bh.yzw, e.y + 64.0, fseed, bh.x, e);
    }
    return vec4<f32>(bh.x, wef_plit(tex, bh.yzw, nw, bh.x, rd, lt, t));
}
// The nearest piece on the ray before tmax: x its distance (1e9 none), yzw its colour (linear, lit). `near`: only whether
// a live piece passes within a few pixels of the ray (x 1 if so), for the half-size stage to flag where the join must
// look.
fn wef_pieces(rd: vec3<f32>, tmax: f32, t: f32, lt: WefLight, near: bool) -> vec4<f32> {
    var best = tmax;
    var col = vec3<f32>(0.0);
    var hit = false;
    if (arrayLength(&mod_data) < WEP_T + WEP_LEN || mod_data[WEP_T] != 1u || mod_data[WEP_T + 5u] == 0u) {
        return vec4<f32>(select(1.0e9, 0.0, near), col);
    }
    let dt = clamp(t - wep_f(WEP_T + 1u), 0.0, wep_f(WEP_T + 6u));
    let px_a = 4.0 * frame.view_params.w / frame.resolution.y;
    let pad = select(0.0, px_a, near);
    let inv = 1.0 / select(rd, vec3<f32>(1.0e-6), abs(rd) < vec3<f32>(1.0e-6));
    let pdet = wef_pdet();
    let nsup = mod_data[WEP_T + 3u];
    for (var su = 0u; su < nsup; su = su + 1u) {
        let sp = WEP_T + WEP_SUP + 8u * su;
        if (!wep_in(sp, inv, best, pad)) {
            continue;
        }
        let gr = mod_data[sp + 6u];
        for (var g = gr & 0xffffu; g < (gr & 0xffffu) + (gr >> 16u); g = g + 1u) {
            let gb = WEP_T + WEP_GRP + 8u * g;
            if (!wep_in(gb, inv, best, pad)) {
                continue;
            }
            // (its source's: a hole's class, a run, the spit)
            let sb = WEP_T + WEP_SRC + 8u * mod_data[gb + 7u];
            let sty = mod_data[sb] & 3u;
            let S = wep_v3(sb + 1u);
            var cnt = 0xffffffffu;
            var grow = 1.0;
            var hd = 0.0;
            var e3 = vec3<f32>(0.0);
            if (sty == 0u) {
                // (fewer of a hole's small ones the farther off they are: past 300 blocks a clod is a pixel or two)
                let base = wep_f(sb + 4u);
                if (base > 0.0) {
                    cnt = u32(base * clamp(260.0 / max(length(we_o + S), 1.0), 0.3, 1.0) * pdet);
                }
            } else if (sty == 1u) {
                // (the head's distance from the eye: the far read's boost, none with the head near)
                e3 = vec3<f32>(wep_f(sb + 4u), 0.0, wep_f(sb + 5u));
                hd = length(we_o + S + e3 * (wep_f(sb + 6u) + wep_f(sb + 7u) * dt));
                grow = mix(1.0, 2.2, smoothstep(110.0, 260.0, hd));
            }
            let pr = mod_data[gb + 6u];
            for (var p = pr & 0xffffu; p < (pr & 0xffffu) + (pr >> 16u); p = p + 1u) {
                let b = WEP_T + WEP_PC + WEP_W * p;
                let m = mod_data[b + 10u];
                let cl = (m >> 2u) & 7u;
                let bk = (m >> 5u) & 7u;
                let idx = m >> 16u;
                let w3 = unpack2x16float(mod_data[b + 3u]);
                let w4 = unpack2x16float(mod_data[b + 4u]);
                let w5 = unpack2x16float(mod_data[b + 5u]);
                let c = we_o + wep_v3(b) + vec3<f32>(w3.x, w3.y, w4.x) * dt;
                var lv = clamp(w4.y + w5.x * dt, 0.0, 1.0);
                let tp = dot(c, rd);
                var e = vec3<f32>(0.0);
                var lump = false;
                var hR = 0.0;
                var id = idx;
                var fseed = f32(idx % 37u);
                var kind = i32(bk);
                if (sty == 0u) {
                    // (a hole's: the count its distance and the detail allow)
                    if (idx >= cnt) {
                        continue;
                    }
                    let w7 = unpack2x16float(mod_data[b + 7u]);
                    let e0 = vec3<f32>(w7.x, w7.y, unpack2x16float(mod_data[b + 8u]).x);
                    if (bk >= 6u) {
                        // (never a big flat thing drifting past the eye: shrunk away within 40 blocks of it; and within
                        // 120 blocks of the eye no bigger than four across)
                        let dc = length(c);
                        lv = lv * smoothstep(12.0, 40.0, dc) * mix(min(2.0 / max(e0.x, e0.z), 1.0), 1.0, smoothstep(120.0, 200.0, dc));
                        kind = select(10, 11, bk == 7u);
                    }
                    if (lv <= 0.02) {
                        continue;
                    }
                    let rb0 = unpack2x16float(mod_data[b + 6u]).x;
                    // (under a third of a pixel across: left out)
                    if (rb0 * lv < tp * px_a * 0.08) {
                        continue;
                    }
                    let rb = rb0 * lv + select(0.0, tp * px_a, near);
                    if (tp - rb > best || length(c - rd * tp) > rb) {
                        continue;
                    }
                    if (near) {
                        return vec4<f32>(1.0, 0.0, 0.0, 0.0);
                    }
                    e = e0 * lv;
                    lump = kind < 10 && max(max(e.x, e.y), e.z) > 0.75;
                    hR = min(max(max(e.x, e.y), e.z), 4.2);
                    id = idx + 7u * cl;
                } else if (sty == 1u) {
                    // (a run's clod: two a place at full size, three at half; far off the small ones thinned by the
                    // place, never by the pixel; with the head far, the big ones all kept and drawn larger than life)
                    if (cl == 2u && wef_full) {
                        continue;
                    }
                    let dk = length(we_o + S + e3 * (f32(idx) * 1.3));
                    let mm = u32(clamp(dk / select(140.0, 100.0, wef_full), 1.0, 4.0));
                    if ((idx % mm) != 0u && ((m & 512u) == 0u || hd < 150.0)) {
                        continue;
                    }
                    let w7 = unpack2x16float(mod_data[b + 7u]);
                    let es = w7.x * grow;
                    if (w7.y + unpack2x16float(mod_data[b + 8u]).x * dt < -es) {
                        continue;
                    }
                    lump = es > 0.75;
                    hR = min(es, 4.2) * lv;
                    e = select(vec3<f32>(0.5 * lv), vec3<f32>(hR + 0.6), lump);
                    if (es < tp * px_a * 0.06) {
                        continue;
                    }
                    let rb = length(e) + select(0.0, tp * px_a, near);
                    if (tp - rb > best || length(c - rd * tp) > rb) {
                        continue;
                    }
                    if (near) {
                        return vec4<f32>(1.0, 0.0, 0.0, 0.0);
                    }
                    id = idx * 3u + cl;
                    fseed = f32(id % 37u);
                } else {
                    // (the spit's)
                    let rb = 0.9 + select(0.0, tp * px_a, near);
                    if (tp < 0.5 || tp - rb > best || length(c - rd * tp) > rb) {
                        continue;
                    }
                    if (near) {
                        return vec4<f32>(1.0, 0.0, 0.0, 0.0);
                    }
                    e = vec3<f32>(0.5 * lv);
                }
                let an = wep_f(b + 11u) + w5.y * dt;
                let h = wep_draw(rd, c, e, wep_axis(mod_data[b + 9u]), an, kind, lump, hR, id, fseed, lv, best, lt, t);
                if (h.x >= 0.0) {
                    best = h.x;
                    hit = true;
                    col = h.yzw;
                }
            }
        }
    }
    if (near) {
        return vec4<f32>(0.0);
    }
    return vec4<f32>(select(1.0e9, best, hit), col);
}

// ---- the camera: the picture jolted on each breach and bite (on top of the game's shake) --------------------------
var<private> wef_px: vec2<f32>;
fn wef_jolt(in: StageIn) -> StageIn {
    wef_px = in.position.xy;
    var o = in;
    we_begin();
    wef_begin(now());
    let n = we_n();
    if (n == 0u || intensity_v() <= 0.0) {
        return o;
    }
    let t = now();
    let res = frame.resolution.xy;
    let asp = res.x / res.y;
    var off = vec2<f32>(0.0);
    var roll = 0.0;
    var zk = 0.0;
    // (each hole's breach or bite and each run's rumble, as the tick's events list them: strike/we_fx.rs, WEP_EV)
    let nev = wep_nev();
    var rum = 0.0;
    for (var e = 0u; e < nev; e = e + 1u) {
        let eb = WEP_T + WEP_EV + 8u * e;
        let ek = mod_data[eb];
        let te = wep_f(eb + 1u);
        let S = wep_f(eb + 2u);
        let dk = length(we_o + wep_v3(eb + 4u));
        if (ek == 2u) {
            rum = rum + 0.0012 * smoothstep(te, te + 0.5, t) * smoothstep(te + S + 1.5, te + S, t) * clamp(1.4 / (1.0 + dk / 200.0), 0.1, 1.0);
            continue;
        }
        let k = mod_data[eb + 3u];
        let bite = ek == 1u;
        // (through the ground: it comes quicker than the sound)
        let s = t - te - dk / 900.0;
        if (s <= 0.0 || s > 6.0) {
            continue;
        }
        let g = S * clamp(1.6 / (1.0 + dk / 260.0), 0.12, 1.0);
        let ph = f32(k) * 1.7 + select(0.0, 2.3, bite);
        let hit = 0.026 * g * exp(-s / 0.26) * smoothstep(0.0, 0.02, s);
        let ring = vec2<f32>(0.65 * sin(s * 47.0 + ph) + 0.35 * sin(s * 83.0 + 2.1 + ph), 0.7 * cos(s * 41.0 + 1.3 + ph) + 0.3 * sin(s * 71.0 + 0.4));
        let shud = 0.0045 * g * exp(-s / 1.6) * smoothstep(0.08, 0.4, s);
        let sh = vec2<f32>(0.6 * sin(s * 15.0 + 0.3 + ph) + 0.4 * sin(s * 27.0 + 1.9), 0.6 * cos(s * 13.0 + 2.2) + 0.4 * sin(s * 29.0 + 0.7 + ph));
        // (a heave: the land lifting under the player as the wave passes, the picture dropping and coming back)
        let heave = 0.012 * g * exp(-s / 0.5) * sin(min(s / 0.35, 1.0) * 3.14159);
        off = off + ring * hit + sh * shud + vec2<f32>(0.0, heave);
        roll = roll + 0.012 * g * exp(-s / 0.35) * sin(s * 37.0 + ph) + 0.002 * g * exp(-s / 1.6) * sin(s * 9.0);
        zk = zk + hit + shud + abs(heave);
    }
    // (the tremor under the wormsign, building to the breach, and the tunnel's rumble as it fails)
    // (the mound's: by its height and the dome's, near it)
    let dm = length(we_o + wef_m.at);
    let trem = 0.0018 * saturate(wef_m.h / WE_MOUND_H + wef_m.dome / WE_DOME_H) * clamp(1.4 / (1.0 + dm / 200.0), 0.1, 1.0);
    let tr = trem + rum;
    off = off + tr * vec2<f32>(sin(t * 31.0) + 0.5 * sin(t * 53.0 + 1.0), cos(t * 27.0 + 0.5) + 0.5 * sin(t * 47.0));
    zk = zk + tr;
    if (zk <= 1.0e-5) {
        return o;
    }
    let zoom = 1.0 + 2.2 * zk + 1.1 * abs(roll) * asp;
    var q = (o.uv - 0.5) * vec2<f32>(asp, 1.0) / zoom;
    q = vec2<f32>(q.x * cos(roll) - q.y * sin(roll), q.x * sin(roll) + q.y * cos(roll)) + off;
    o.uv = clamp(q / vec2<f32>(asp, 1.0) + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    o.position = vec4<f32>(o.uv * res, in.position.zw);
    return o;
}

// ---- earth on the lens after a near breach or bite: crumbs and smears far out of focus --------------------------
fn wef_lens(col: vec3<f32>, t: f32, lt: WefLight) -> vec3<f32> {
    let n = we_n();
    let res = frame.resolution.xy;
    let pxy = wef_px;
    var keep = 1.0;
    var shine = 0.0;
    let nev = wep_nev();
    for (var e = 0u; e < nev; e = e + 1u) {
        let eb = WEP_T + WEP_EV + 8u * e;
        let ek = mod_data[eb];
        let dk = length(we_o + wep_v3(eb + 4u));
        if (ek == 2u || dk > 150.0) {
            continue;
        }
        let k = mod_data[eb + 3u];
        let b = ek;
        let bite = ek == 1u;
        {
            let a0 = t - wep_f(eb + 1u);
            // (from when what it threw reaches the eye: its front's dust, or the earth falling near)
            let a = a0 - min(dk / 70.0, 2.5);
            if (a < 0.0 || a > 22.0) {
                continue;
            }
            let vis = smoothstep(150.0, 70.0, dk) * select(1.0, 0.7, bite);
            let sk = k * 2u + b + 7u;
            for (var i = 0u; i < 11u; i = i + 1u) {
                let t0 = 0.4 + 1.6 * wef_ph(i, sk, 20u);
                let age = a - t0;
                if (age <= 0.0) {
                    continue;
                }
                let c = vec2<f32>(0.04 + 0.92 * wef_ph(i, sk, 21u), 0.03 + 0.85 * pow(wef_ph(i, sk, 22u), 1.6)) * res;
                let r = (0.014 + 0.04 * pow(wef_ph(i, sk, 23u), 1.4)) * res.y;
                let d0 = pxy - c;
                if (dot(d0, d0) > 4.0 * r * r) {
                    continue;
                }
                let life = smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(5.0, 14.0, age + 5.0 * wef_ph(i, sk, 24u)));
                // (each its own: stretched a little, its edge uneven, feathered over its outer half with no outline)
                let rot = 6.2831853 * wef_ph(i, sk, 25u);
                let e = vec2<f32>((d0.x * cos(rot) + d0.y * sin(rot)) / (1.0 + 0.5 * wef_ph(i, sk, 26u)), -d0.x * sin(rot) + d0.y * cos(rot));
                let th = atan2(e.y, e.x);
                let q = length(e) / r * (1.0 + 0.06 * sin(3.0 * th + rot) + 0.04 * sin(5.0 * th - rot));
                let body = 1.0 - smoothstep(0.25, 1.35, q);
                let op = (0.12 + 0.3 * pow(wef_ph(i, sk, 27u), 0.8)) * life * vis;
                keep = keep * (1.0 - body * op);
                shine = shine + body * smoothstep(0.3, -0.9, d0.y / r) * op;
            }
        }
    }
    let dirt = vec3<f32>(0.33, 0.25, 0.18) * (lt.sunc * 0.35 + lt.amb * 0.8);
    return col * keep + dirt * (1.0 - keep) * 0.8 + dirt * 0.25 * min(shine, 1.0);
}

// ---- caught -----------------------------------------------------------------------------------------------------
// When the jaws closed on the player and when it spits them out (x <= 0: not caught).
fn wef_catch() -> vec2<f32> {
    if (WEF_TEST_CATCH.x > 0.0) {
        return WEF_TEST_CATCH;
    }
    return vec2<f32>(we_w(WE_FX_T + WEF_W_CAUGHT), we_w(WE_FX_T + WEF_W_SPIT));
}
// The eye's ray inside at pixel uv: the slow roll of the picture inside, never a spin.
fn wef_rdr(uv: vec2<f32>, t: f32, cw: vec2<f32>) -> vec3<f32> {
    let asp = frame.resolution.x / frame.resolution.y;
    let q = (uv - 0.5) * vec2<f32>(asp, 1.0);
    let roll = 0.32 * sin((t - cw.x) * 0.55) + 0.06 * (t - cw.x);
    let qr = vec2<f32>(q.x * cos(roll) - q.y * sin(roll), q.x * sin(roll) + q.y * cos(roll));
    return normalize(world_offset(qr / vec2<f32>(asp, 1.0) + 0.5, 0.5));
}
// ---- the game's block textures (the Hurricane's way: its hu_face, from the fx's own table) --------------------------
fn wef_u32(i: u32) -> u32 {
    let n = arrayLength(&mod_data);
    return select(0u, mod_data[min(i, n - 1u)], i < n);
}
fn wef_565(c: u32) -> vec3<f32> {
    return srgb_to_linear(vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0));
}
fn wef_tint(c: u32) -> vec3<f32> {
    if (c == 0xFFFFu) {
        return vec3<f32>(1.0);
    }
    return vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0);
}
fn wef_face_st(m: u32, uv: vec2<f32>) -> vec2<f32> {
    let q = vec3<f32>(vec3<u32>(m, m >> 2u, m >> 4u) & vec3<u32>(3u)) - 1.0;
    let r = vec3<f32>(vec3<u32>(m >> 6u, m >> 8u, m >> 10u) & vec3<u32>(3u)) - 1.0;
    return fract(vec2<f32>(q.x + uv.x * q.z + uv.y * r.y, q.y + uv.x * r.x + uv.y * r.z) * 0.99999 + 0.000005);
}
// The mip level a block's sixteen texels are seen at, `t` off, the block `sz` across.
fn wef_lod(t: f32, sz: f32) -> f32 {
    let px = 2.0 * tan(0.5 * frame.view_params.w) * frame.resolution.w;
    return log2(max(t * px * 16.0 / max(sz, 0.05), 1.0e-4));
}
// Block b's face (0 top, 1 bottom, 2 a side) at uv (0 to 1 across it, v down a side), linear, as the game draws it,
// its grass and leaves tinted; x < 0: no table (the pass's own look-alike then).
fn wef_btex(b: u32, face: u32, uv: vec2<f32>, lod: f32) -> vec3<f32> {
    let h = WE_FX_T + WEF_BK;
    if (wef_u32(h + 1u) != 0x3F800000u || b >= wef_u32(h)) {
        return vec3<f32>(-1.0);
    }
    let o = h + 4u + b * 12u;
    let wa = wef_u32(o);
    let wb2 = wef_u32(o + 1u);
    let avg = wef_565(select(select(wa >> 16u, wb2 & 0xFFFFu, face == 1u), wa & 0xFFFFu, face == 0u));
    let f0 = wef_u32(o + 2u + 3u * face);
    if ((f0 & 1u) == 0u || lod > 3.5) {
        return avg;
    }
    let st = wef_face_st(wef_u32(o + 4u + 3u * face), uv);
    let lv = clamp(lod, 0.0, f32(textureNumLevels(block_sprites) - 1));
    let c0 = textureSampleLevel(block_sprites, block_sampler, st, i32((f0 >> 2u) & 0x1FFFu), lv);
    var rgb = srgb_to_linear(c0.rgb * wef_tint(f0 >> 16u));
    if ((f0 & 2u) != 0u && c0.a < 0.5) {
        rgb = avg * 0.3;
    }
    let f1 = wef_u32(o + 3u + 3u * face);
    if ((f1 & 1u) != 0u) {
        let c1 = textureSampleLevel(block_sprites, block_sampler, st, i32((f1 >> 2u) & 0x1FFFu), lv);
        rgb = mix(rgb, srgb_to_linear(c1.rgb * wef_tint(f1 >> 16u)), c1.a);
    }
    return rgb;
}
// A block's face at local point lp (its own axes, the face's normal n, a block `sz` across): which face and where on
// it, a sprite's v running down a side. x: the face (0 top, 1 bottom, 2 side), yz the uv.
fn wef_fuv(lp: vec3<f32>, n: vec3<f32>, sz: vec3<f32>) -> vec3<f32> {
    let q = lp / sz + 0.5;
    if (abs(n.y) > 0.5) {
        return vec3<f32>(select(1.0, 0.0, n.y > 0.0), q.x, q.z);
    }
    let u = select(q.x, q.z, abs(n.x) > 0.5) * select(1.0, -1.0, (n.x + n.z) < 0.0);
    return vec3<f32>(2.0, fract(u), 1.0 - q.y);
}
// The fx's own look-alike kind (debris_tex's: 0 turf, 1 dirt, 2 stone, 3 deepslate, 4 log, 5 leaves) as a real block.
fn wef_bof(kind: i32) -> u32 {
    return select(select(select(select(select(WEF_B_LEAVES, WEF_B_LOG, kind == 4), WEF_B_DEEP, kind == 3), WEF_B_STONE, kind == 2), WEF_B_DIRT, kind == 1), WEF_B_GRASS, kind == 0);
}
// One whole block `sz` across, hit at local lp with local normal n, `t` off: the game's texture, or the look-alike.
fn wef_block_col(b: u32, lp: vec3<f32>, n: vec3<f32>, sz: vec3<f32>, t: f32, kind: i32, seed: f32) -> vec3<f32> {
    let f = wef_fuv(lp, n, sz);
    let c = wef_btex(b, u32(f.x), f.yz, wef_lod(t, max(sz.x, sz.z)));
    if (c.x >= 0.0) {
        return c;
    }
    return srgb_to_linear(debris_tex(kind, floor(f.yz * 16.0), n.y > 0.5, 0.0, seed));
}

// ---- whole things it ate, riding down the throat: trees (oak, birch, spruce, acacia) and lumps (a boulder with ore, a
// clump of turf), built of blocks on a 9 by 12 by 9 grid, walked block by block (wef_obj) --------------------------
// What block of thing `ty` (trunk `h` high) is at cell q: -1 none, else a debris_tex kind (6 a birch log, 7 an ore).
fn wef_occ(ty: u32, h: i32, q: vec3<i32>, sd: u32) -> i32 {
    let hq = wef_ph(u32(q.x + 9 * (q.y + 12 * q.z)), sd, 1u);
    let dx = f32(q.x) - 4.0;
    let dz = f32(q.z) - 4.0;
    let rxz = sqrt(dx * dx + dz * dz);
    if (ty >= 4u) {
        // (a lump `h` tenths of a block round: a rough ball of blocks, its corners knocked off block by block: stone
        // with ore, earth with turf on top, or deepslate and cobble)
        let R = f32(h) * 0.1;
        let dy = f32(q.y) - 4.0;
        let rr = length(vec3<f32>(dx, dy, dz));
        if (rr > R + 0.35 - 0.9 * hq) {
            return -1;
        }
        if (ty == 4u) {
            return select(2, 7, hq > 0.88);
        }
        if (ty == 5u) {
            return select(1, 0, dy > R * 0.35);
        }
        return select(3, 2, hq > 0.7);
    }
    // (roots of earth hanging under some)
    if (q.y == 0) {
        return select(-1, 1, rxz < 1.5 && hq < 0.35 && (sd & 1u) == 0u);
    }
    // (the trunk; an acacia's leaning over halfway up)
    let tx = select(0, 1, ty == 3u && q.y > h / 2 + 1);
    if (q.x == 4 + tx && q.z == 4 && q.y <= h) {
        return select(4, 6, ty == 1u);
    }
    let y = f32(q.y - h);
    var leaf = false;
    if (ty == 2u) {
        // (spruce: a cone)
        leaf = q.y >= 3 && y <= 2.0 && rxz <= (2.0 - y) * 0.75 + 0.5;
    } else if (ty == 3u) {
        // (acacia: a flat top, wide)
        leaf = (y >= 1.0 && y <= 1.0 && length(vec2<f32>(dx - 1.0, dz)) <= 3.6) || (y == 2.0 && length(vec2<f32>(dx - 1.0, dz)) <= 2.2);
    } else {
        // (oak, birch: a round head)
        let rc = select(2.6, 2.1, ty == 1u) - select(0.0, 1.0, y >= 2.0);
        leaf = y >= -1.0 && y <= 2.0 && rxz <= rc;
    }
    return select(-1, 5, leaf && hq > 0.12);
}
var<private> wef_ok: i32;
// A block of a thing (wef_occ's kind k; its tree's kind ty) at lp in the thing's grid, face normal n, t off: the game's
// own block there.
fn wef_vox_col(k: i32, ty: u32, lp: vec3<f32>, n: vec3<f32>, t: f32, id: u32) -> vec3<f32> {
    let tsp = min(ty, 3u);
    var bk = WEF_B_DIRT;
    if (k == 4 || k == 6) {
        bk = WEF_B_LOG + tsp;
    } else if (k == 5) {
        bk = WEF_B_LEAVES + tsp;
    } else if (k == 7) {
        bk = select(WEF_B_IRON, WEF_B_DIAMOND, wef_ph(id, 161u, 9u) > 0.6);
    } else if (k == 2) {
        bk = select(WEF_B_STONE, WEF_B_COBBLE, ty == 6u);
    } else if (k == 3) {
        bk = WEF_B_DEEP;
    } else if (k == 0) {
        bk = WEF_B_GRASS;
    }
    return wef_block_col(bk, fract(lp) - 0.5, n, vec3<f32>(1.0), t, select(k, 4, k == 6), f32(id % 37u));
}
// The ray ro + rv t (in the thing's frame, its grid from 0 to 9, 12, 9) to its first block: x the distance, yzw the
// face's normal; -1 none. The block's kind left in wef_ok.
fn wef_obj(ro: vec3<f32>, rv: vec3<f32>, ty: u32, h: i32, sd: u32) -> vec4<f32> {
    let hi = vec3<f32>(9.0, 12.0, 9.0);
    let inv = 1.0 / select(rv, vec3<f32>(1.0e-6), abs(rv) < vec3<f32>(1.0e-6));
    let t1 = -ro * inv;
    let t2 = (hi - ro) * inv;
    let tn = min(t1, t2);
    let tf = max(t1, t2);
    var t0 = max(max(max(tn.x, tn.y), tn.z), 0.0);
    let t9 = min(min(tf.x, tf.y), tf.z);
    if (t0 >= t9) {
        return vec4<f32>(-1.0, 0.0, 0.0, 0.0);
    }
    let p = ro + rv * (t0 + 1.0e-3);
    var q = vec3<i32>(clamp(floor(p), vec3<f32>(0.0), hi - 1.0));
    let st = vec3<i32>(sign(rv));
    let dl = abs(inv);
    var sm = (select(vec3<f32>(q), vec3<f32>(q) + 1.0, rv > vec3<f32>(0.0)) - ro) * inv;
    var nrm = select(select(vec3<f32>(0.0, 0.0, -sign(rv.z)), vec3<f32>(0.0, -sign(rv.y), 0.0), t0 == tn.y), vec3<f32>(-sign(rv.x), 0.0, 0.0), t0 == tn.x);
    for (var i = 0; i < 26; i = i + 1) {
        if (any(q < vec3<i32>(0)) || any(q > vec3<i32>(8, 11, 8))) {
            break;
        }
        let k = wef_occ(ty, h, q, sd);
        if (k >= 0) {
            wef_ok = k;
            return vec4<f32>(t0, nrm);
        }
        if (sm.x < sm.y && sm.x < sm.z) {
            t0 = sm.x;
            sm.x = sm.x + dl.x;
            q.x = q.x + st.x;
            nrm = vec3<f32>(-f32(st.x), 0.0, 0.0);
        } else if (sm.y < sm.z) {
            t0 = sm.y;
            sm.y = sm.y + dl.y;
            q.y = q.y + st.y;
            nrm = vec3<f32>(0.0, -f32(st.y), 0.0);
        } else {
            t0 = sm.z;
            sm.z = sm.z + dl.z;
            q.z = q.z + st.z;
            nrm = vec3<f32>(0.0, 0.0, -f32(st.z));
        }
    }
    return vec4<f32>(-1.0, 0.0, 0.0, 0.0);
}

// ---- the ride inside ---------------------------------------------------------------------------------------------
// The virtual eye while caught: xyz its place (camera-relative) on the throat's centreline, w its s along the path.
// A stand-in until the path gives we_eye(t): the camera's place found on the centreline (a coarse look along 500 behind
// the head, then three Newton steps), eased back onto the camera over the last 0.3 s before the let-go.
// The eye's s along the path and its speed at t: we_eye_s's curve, found by halving (its knots up to 64) and once for
// both, not by a walk along the knots each call.
// When the eye passes the tip and leaves the mouth (the land's word 8; without it, the let-go): the end of the ride inside.
fn wef_tip() -> f32 {
    let tp = we_w(WE_EYE_T + 8u);
    return select(we_w(WE_EYE_T + 1u), tp, tp > 0.0);
}
fn wef_eye_sv(t: f32) -> vec2<f32> {
    let n = u32(clamp(we_w(WE_EYE_T + 2u), 0.0, 64.0));
    if (n == 0u) {
        return vec2<f32>(0.0);
    }
    let b = WE_EYE_T + 24u;
    if (t <= we_w(b)) {
        return vec2<f32>(we_w(b + 1u), 0.0);
    }
    if (t >= we_w(b + 3u * (n - 1u))) {
        return vec2<f32>(we_w(b + 3u * n - 2u), 0.0);
    }
    var lo = 0u;
    var hi = n - 1u;
    for (var k = 0; k < 7 && hi - lo > 1u; k = k + 1) {
        let m = (lo + hi) / 2u;
        if (we_w(b + 3u * m) <= t) {
            lo = m;
        } else {
            hi = m;
        }
    }
    let t0 = we_w(b + 3u * lo);
    let dt = max(we_w(b + 3u * hi) - t0, 1.0e-6);
    let p0 = we_w(b + 3u * lo + 1u);
    let m0 = we_w(b + 3u * lo + 2u) * dt;
    let p1 = we_w(b + 3u * hi + 1u);
    let m1 = we_w(b + 3u * hi + 2u) * dt;
    let u = (t - t0) / dt;
    let u2 = u * u;
    let dh = (6.0 * u2 - 6.0 * u) * p0 + (3.0 * u2 - 4.0 * u + 1.0) * m0 + (-6.0 * u2 + 6.0 * u) * p1 + (3.0 * u2 - 2.0 * u) * m1;
    return vec2<f32>(we_herm(p0, m0, p1, m1, u), dh / dt);
}
// (the eye as last worked out in this pixel, and its speed: the caught view asks for it more than once)
var<private> wef_eye_t: f32 = -1.0e9;
var<private> wef_eye_c: vec4<f32>;
var<private> wef_eye_v: f32;
fn wef_eye(t: f32, cw: vec2<f32>) -> vec4<f32> {
    if (t == wef_eye_t) {
        return wef_eye_c;
    }
    let cam = -we_o;
    // (the path's eye when the land gives it: we_eye's place from where they stood onto the centreline; the camera's
    // place on the centreline only without it)
    if (we_w(WE_EYE_T) > 0.0) {
        // (eased back onto the camera as it passes the tip: from there it flies outside, drawn from the camera)
        let tf = wef_tip();
        let sv = wef_eye_sv(t);
        let t0 = we_w(WE_EYE_T);
        let st = vec3<f32>(we_w(WE_EYE_T + 5u), we_w(WE_EYE_T + 6u), we_w(WE_EYE_T + 7u));
        let uu = clamp((t - t0 - we_w(WE_EYE_T + 3u)) / max(we_w(WE_EYE_T + 4u), 1.0e-3), 0.0, 1.0);
        let m = uu * uu * uu * (uu * (6.0 * uu - 15.0) + 10.0);
        wef_eye_t = t;
        wef_eye_v = sv.y;
        wef_eye_c = vec4<f32>((mix(st, we_point(sv.x), m) - cam) * (1.0 - smoothstep(tf - 0.3, tf, t)), sv.x);
        return wef_eye_c;
    }
    let sh = we_head(t);
    var s = sh;
    var bd = 1.0e9;
    for (var k = 0; k < 26; k = k + 1) {
        let sk = sh - f32(k) * 20.0;
        let dd = length(we_point(sk) - cam);
        if (dd < bd) {
            bd = dd;
            s = sk;
        }
    }
    for (var k = 0; k < 3; k = k + 1) {
        s = s + dot(cam - we_point(s), we_tangent(s));
    }
    let ts = max(cw.y, cw.x + 1.5);
    return vec4<f32>((we_point(s) - cam) * (1.0 - smoothstep(ts - 0.3, ts, t)), s);
}
// The light on a face inside the throat: at P (from the camera), facing n, seen along rd; the eye at E (xyz, its s in
// w) going D; the let-go at tf. The nearest wall's teal glow on the faces turned to it, flaring as a band sweeps past,
// soft shade near the wall; the glow far ahead on the faces turned to it, and as a rim round what stands against it;
// the faces turned to the dark middle dark; daylight from ahead as the mouth opens at the spit.
fn wef_tlight(P: vec3<f32>, n: vec3<f32>, rd: vec3<f32>, E: vec4<f32>, D: vec3<f32>, t: f32, tf: f32) -> vec3<f32> {
    let y = P - E.xyz;
    let z = dot(y, D);
    let lat = y - D * z;
    let r = length(lat);
    let out = lat / max(r, 1.0e-3);
    let gap = max(WB_RT - r, 0.0);
    // (the walls' own light there, with its bands, and the deep glow ahead: the body's we_throat_glow, we_throat_far)
    let far = we_throat_far(t);
    let wall = we_throat_glow(E.w + z, t) * 4.0 * exp(-gap / 6.0) * saturate(0.85 * dot(n, out) + 0.15);
    let ahead = far * 3.0 * saturate(dot(n, D));
    let rim = far * 2.4 * pow(1.0 - saturate(dot(n, -rd)), 3.0) * saturate(dot(rd, D));
    let ao = mix(0.55, 1.0, smoothstep(0.5, 3.0, gap));
    // (as the jaws open on the push, the day's light in through the mouth: the sky's from ahead, the sun on its side)
    let Ls = normalize(frame.sun.xyz + vec3<f32>(0.0, 0.03, 0.0));
    let day = (vec3<f32>(0.6, 0.65, 0.75) * (0.75 + 0.25 * n.y) + vec3<f32>(1.1, 1.05, 0.95) * max(dot(n, Ls), 0.0) * smoothstep(-0.05, 0.1, Ls.y)) * smoothstep(tf - 2.9, tf - 1.9, t);
    return (wall + ahead + day) * ao + rim + vec3<f32>(0.012, 0.014, 0.018);
}
// The caught view over col0: the swallow's dark beat, the land it ate streaming past the eye along the throat, the
// wind. `th` the throat along wef_rdr's ray (the body's colour there and how far, or we_throat_miss).
fn wef_caught(col0: vec3<f32>, uv: vec2<f32>, rd: vec3<f32>, t: f32, cw: vec2<f32>, lt: WefLight, th: vec4<f32>) -> vec3<f32> {
    let rdr = wef_rdr(uv, t, cw);
    // (timed to the eye's words when the land gives them: the shut, the beat (the eye where they stood), the let-go)
    let eyed = we_w(WE_EYE_T) > 0.0;
    let tc = select(cw.x, we_w(WE_EYE_T), eyed);
    let ts = select(max(cw.y, cw.x + 1.5), wef_tip(), eyed);
    let bl = select(0.7, we_w(WE_EYE_T + 3u), eyed);
    let u = t - tc;
    // (the swallow: the daylight pinched out as the jaws shut, a dark beat with the throat's glow ahead, then the walls
    // come up and the ride gathers speed; nothing streams before it)
    let beat = smoothstep(0.1, 0.35, u) * (1.0 - smoothstep(bl, bl + 0.6, u));
    let go = smoothstep(bl, bl + 1.6, u);
    if (!wef_inside(t)) {
        // (the jaws coming down over the eye: the day faded out over the close, black by the time they have shut over
        // it (WEF_SHUT_D), whatever sky the petals still leave between them)
        let dk = select(0.9 * smoothstep(0.15, 0.55, u), smoothstep(0.06, WEF_SHUT_D, u), eyed);
        return col0 * (1.0 - dk * (1.0 - smoothstep(ts - 0.6, ts + 0.3, t)));
    }
    let E = wef_eye(t, cw);
    let D = normalize(we_tangent(E.w));
    let U0 = select(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), abs(D.y) > 0.9);
    let U = normalize(cross(D, U0));
    let V = cross(D, U);
    let wall = min(th.a, 400.0);
    var col = select(th.rgb, col0, th.a >= 1.0e8);
    // (the land it ate: blocks on a grid round the throat's axis, fixed along the path, so they pour past as the eye
    // is carried on; 4 along, 10 round, rings 3.6 out; a pixel looks only in the cells its ray passes through, at most
    // 22, each holding one block or none: denser just after the swallow)
    // (the land streams back down the throat on its own too, swallowed: 15 a second once the ride is going, on top of
    // the eye's own way along the path)
    // (and at the spit they surge out of the mouth with the player, overtaking the eye: the last 0.6 s)
    let sg = max(t - (ts - 2.4), 0.0);
    let sf = E.w + 15.0 * max(u - bl, 0.0) - 6.0 * sg * sg * sg;
    let dens = 0.26 + 0.3 * exp(-max(u - 1.0, 0.0) / 2.5);
    var best = wall;
    var bcol = vec3<f32>(0.0);
    var hsel = 0;
    var hbk = 0u;
    var hlp = vec3<f32>(0.0);
    var hnl = vec3<f32>(0.0);
    var hsz = vec3<f32>(1.0);
    var hkind = 0;
    var hid = 0u;
    var hnw = vec3<f32>(0.0);
    var hty = 0u;
    var hsh = 1.0;
    var motes = 0.0;
    let wspd = go * clamp(select(we_head_v(t), wef_eye_v, eyed) / 70.0, 0.25, 1.6) * (1.0 + 1.3 * smoothstep(ts - 2.4, ts - 0.1, t));
    var last = vec3<i32>(-99999);
    let tmax = min(wall, 70.0);
    let n = 12;
    for (var q = 0; q < n; q = q + 1) {
        if (go <= 0.0) {
            break;
        }
        let tq = 1.5 + (tmax - 1.5) * (f32(q) + 0.5) / f32(n);
        if (tq > best) {
            break;
        }
        let y = rdr * tq - E.xyz;
        let z = dot(y, D);
        let lat = y - D * z;
        let r = length(lat);
        let th0 = atan2(dot(lat, V), dot(lat, U));
        let cell = vec3<i32>(i32(floor((z + sf) / 4.0)), i32(floor((th0 / 6.2831853 + 0.5) * 10.0)), i32(floor(r / 3.6)));
        if (all(cell == last) || cell.z > 3) {
            continue;
        }
        last = cell;
        let id = u32(cell.x * 7919 + cell.y * 131 + cell.z * 17 + 100000);
        // (a mote of grit in every other cell, drawn out along the throat by its speed: a soft streak catching the
        // walls' glow, a few blocks long at full speed, a point at rest)
        if (wef_ph(id, 152u, 1u) < 0.3) {
            let am = (f32(cell.x) + wef_ph(id, 152u, 2u)) * 4.0 - sf;
            let gm = ((f32(cell.y) + wef_ph(id, 152u, 3u)) / 10.0 - 0.5) * 6.2831853;
            let rm = (f32(cell.z) + wef_ph(id, 152u, 4u)) * 3.6;
            let pm = E.xyz + D * am + (U * cos(gm) + V * sin(gm)) * rm;
            let ln = 0.15 + 1.2 * wspd;
            // (the nearest point of the streak pm..pm+D*ln to the ray)
            let w0 = pm;
            let b = dot(rdr, D);
            let dd0 = dot(rdr, w0);
            let ee = dot(D, w0);
            let den2 = max(1.0 - b * b, 1.0e-4);
            let sc = clamp((b * dd0 - ee) / den2, 0.0, ln);
            let tr = dd0 + b * sc;
            if (tr > 0.5 && tr < best) {
                let dm = length(w0 + D * sc - rdr * tr) / (0.012 + tr * 0.0012);
                motes = motes + exp(-dm * dm) * (1.0 - sc / max(ln, 1.0e-3) * 0.7) * smoothstep(3.0, 8.0, tr);
            }
        }
        if (wef_ph(id, 151u, 1u) > dens) {
            continue;
        }
        let a = (f32(cell.x) + 0.3 + 0.4 * wef_ph(id, 151u, 2u)) * 4.0;
        let ang = ((f32(cell.y) + 0.3 + 0.4 * wef_ph(id, 151u, 3u)) / 10.0 - 0.5) * 6.2831853;
        // (bouncing off the walls a little as they ride)
        // (none within three blocks of the axis, the eye's line, by its own size)
        let rr = clamp((f32(cell.z) + 0.3 + 0.4 * wef_ph(id, 151u, 4u)) * 3.6 + 0.8 * abs(sin(t * (1.5 + wef_ph(id, 151u, 5u) * 2.0) + f32(id))), 4.2, 13.5);
        let c = E.xyz + D * (a - sf) + (U * cos(ang) + V * sin(ang)) * rr;
        let big = wef_ph(id, 151u, 6u);
        let es = (0.3 + 0.2 * big) * smoothstep(3.0, 6.0, length(c));
        let ax = normalize(vec3<f32>(wef_ph(id, 151u, 7u), wef_ph(id, 151u, 8u), wef_ph(id, 151u, 9u)) - 0.5 + vec3<f32>(0.0, 0.0, 1.0e-3));
        let an = (0.8 + 3.0 * wef_ph(id, 151u, 10u)) * t;
        let ro = wef_rot(-c, ax, -an);
        let rv = wef_rot(rdr, ax, -an);
        let e = vec3<f32>(es, es * (0.75 + 0.4 * wef_ph(id, 151u, 11u)), es * (0.8 + 0.3 * wef_ph(id, 151u, 12u)));
        let bh = wef_box(ro, rv, -e, e);
        if (bh.x < 0.5 || bh.x > best) {
            continue;
        }
        best = bh.x;
        let m = wef_ph(id, 151u, 13u);
        // (dirt, stone, grass, logs, leaves, deepslate, and now and then an ore)
        let kind = select(select(select(select(select(1, 2, m > 0.3), 0, m > 0.55), 4, m > 0.72), 5, m > 0.82), 3, m > 0.92);
        let lp = ro + rv * bh.x;
        // (each one block of the game, its texture across the whole of it: an ore now and then among the stone, a
        // log of one of four trees, their leaves)
        let sp = u32(wef_ph(id, 151u, 15u) * 3.99);
        var bk = wef_bof(kind);
        bk = select(bk, select(WEF_B_IRON, WEF_B_DIAMOND, wef_ph(id, 151u, 15u) > 0.75), kind == 2 && wef_ph(id, 151u, 14u) > 0.7);
        bk = select(bk, bk + sp, kind == 4 || kind == 5);
        bk = select(bk, select(WEF_B_GRAVEL, WEF_B_COBBLE, wef_ph(id, 151u, 15u) > 0.5), kind == 1 && wef_ph(id, 151u, 14u) > 0.75);
        // (its texture and light worked out once, for the nearest, after the walk)
        hsel = 1;
        hbk = bk;
        hlp = lp;
        hnl = bh.yzw;
        hsz = 2.0 * e;
        hkind = kind;
        hid = id;
        hnw = wef_rot(bh.yzw, ax, an);
    }
    // (and whole things among them: one place every 40 along the throat, a thing in about half (nearly all just after
    // the swallow), off the axis by their own size, tumbling slowly end over end; a pixel looks at the places its ray
    // passes, three or four)
    if (go > 0.0) {
        let z0 = dot(-E.xyz, D);
        let z1 = dot(rdr * tmax - E.xyz, D);
        let c0 = i32(floor((min(z0, z1) + sf - 10.0) / 22.0));
        let c1 = i32(floor((max(z0, z1) + sf + 10.0) / 22.0));
        for (var cc = c0; cc <= min(c1, c0 + 5); cc = cc + 1) {
            let id = u32(cc + 100000);
            if (wef_ph(id, 161u, 1u) > mix(0.6, 0.97, exp(-max(u - bl, 0.0) / 2.5))) {
                continue;
            }
            let ty = select(u32(wef_ph(id, 161u, 2u) * 4.0), 4u + u32(wef_ph(id, 161u, 3u) * 2.0), wef_ph(id, 161u, 4u) > 0.82);
            let h = select(4 + i32(wef_ph(id, 161u, 5u) * 3.99), 26, ty >= 4u);
            let ga = (f32(cc) + 0.5) * 22.0 - sf;
            let gg = wef_ph(id, 161u, 6u) * 6.2831853;
            // (off the axis by its own size and three blocks more: a tree's middle 10.5 out, a lump's 7)
            let rad = select(10.5, 7.0, ty >= 4u);
            let cen = E.xyz + D * ga + (U * cos(gg) + V * sin(gg)) * rad;
            // (only a ray passing within its reach looks into it)
            let tc2 = dot(cen, rdr);
            if (length(cen) > best + 9.0 || tc2 < -8.0 || length(cen - rdr * tc2) > select(8.5, 4.5, ty >= 4u)) {
                continue;
            }
            // (its frame: tumbling end over end about an axis across the throat)
            let tax = normalize(cross(D, U * cos(gg + 1.3) + V * sin(gg + 1.3)));
            let tan = t * (0.35 + 0.4 * wef_ph(id, 161u, 7u)) + wef_ph(id, 161u, 8u) * 6.28;
            let mid = select(vec3<f32>(4.5, 0.5 + 0.5 * f32(h + 3), 4.5), vec3<f32>(4.5), ty >= 4u);
            let ro = wef_rot(-cen, tax, -tan) + mid;
            let rv = wef_rot(rdr, tax, -tan);
            let oh = wef_obj(ro, rv, ty, h, id);
            if (oh.x < 0.5 || oh.x > best) {
                continue;
            }
            best = oh.x;
            let lp = ro + rv * oh.x;
            let k = wef_ok;
            let nw = wef_rot(oh.yzw, tax, tan);
            // (its own blocks shade each other: a face whose next block towards the wall is there is in that block's
            // shade, the crown's underside and the trunk behind the leaves dark)
            let po = rdr * oh.x - E.xyz;
            let lo = wef_rot(normalize(po - D * dot(po, D) + vec3<f32>(1.0e-4)), tax, -tan);
            let la = abs(lo);
            let st = select(select(vec3<i32>(0, 0, i32(sign(lo.z))), vec3<i32>(0, i32(sign(lo.y)), 0), la.y > la.z), vec3<i32>(i32(sign(lo.x)), 0, 0), la.x > max(la.y, la.z));
            let qn = vec3<i32>(floor(lp - oh.yzw * 0.5)) + st;
            let sh = select(1.0, 0.4, all(qn >= vec3<i32>(0)) && all(qn <= vec3<i32>(8, 11, 8)) && wef_occ(ty, h, qn, id) >= 0);
            hsel = 2;
            hkind = k;
            hty = ty;
            hlp = lp;
            hnl = oh.yzw;
            hid = id;
            hnw = nw;
            hsh = sh * smoothstep(3.0, 6.0, oh.x);
        }
    }
    // (the nearest hit's texture and light)
    // (one light for either: each call is a whole copy for the compiler)
    if (hsel != 0) {
        let tl = wef_tlight(rdr * best, hnw, rdr, E, D, t, ts);
        if (hsel == 1) {
            bcol = wef_block_col(hbk, hlp, hnl, hsz, best, hkind, f32(hid % 37u)) * tl;
        } else {
            bcol = wef_vox_col(hkind, hty, hlp, hnl, best, hid) * tl * hsh;
        }
    }
    if (best < wall) {
        col = bcol;
    }
    col = col + WB_SOUL * 0.035 * WEF_WIND * min(motes, 1.5);
    // (the wind: fine streaks and grit rushing past along the throat, from the point ahead out past the eye, faster with
    // the ride's speed, gusting; drawn round the vanishing point of the throat's way)
    let spd = wspd;
    if (spd > 0.01) {
        let fw = dot(D, rdr);
        let pv = rdr - D * fw;
        let rad = length(pv) / max(fw, 0.05);
        let ang2 = atan2(dot(pv, V), dot(pv, U));
        let lr = log(max(rad, 0.02));
        let gust = 0.7 + 0.3 * sin(t * 2.3) * sin(t * 0.9 + 1.0);
        let lane = floor(ang2 * 38.0);
        let ph = lr * 3.0 - t * (5.0 + 9.0 * spd) * gust + wef_vh(vec2<f32>(lane, 7.0)) * 20.0;
        let streak = smoothstep(0.9, 0.98, wef_vh(vec2<f32>(lane, floor(ph)))) * smoothstep(0.0, 0.25, fract(ph)) * smoothstep(1.0, 0.45, fract(ph));
        let thin = smoothstep(0.25, 0.0, abs(fract(ang2 * 38.0) - 0.5) * 2.0 - 0.6);
        col = col + WB_SOUL * 0.006 * WEF_WIND * streak * thin * spd * smoothstep(0.08, 0.6, rad) * select(1.0, 0.0, fw < 0.0);
        // (and the view pulled toward where it goes: the edges a little darker at speed)
        let q2 = (uv - 0.5) * 2.0;
        col = col * (1.0 - 0.12 * spd * dot(q2, q2) * 0.5);
    }
    // (the swallow's dark beat: black, the throat's glow ahead the only light)
    let fw2 = dot(D, rdr);
    let ahead = WB_SOUL * 0.08 * exp(-(1.0 - fw2) * 14.0);
    col = mix(col, ahead, beat * 0.9);
    // (the walls come up out of the dark as the ride starts)
    col = col * mix(1.0, smoothstep(bl - 0.1, bl + 0.6, u), 1.0 - step(bl + 0.6, u));
    return col;
}

// (the body as fs_join found it, so the pass needn't look again)
var<private> wef_pre_hit: WeHit;
// (the player in the worm's shadow, as the half-size stage found it; -1: look here)
var<private> wef_cam_sh: f32;
// (whether a piece passes near this pixel, as the half-size stage found it; FULL: always looked for)
var<private> wef_pnear: bool;
// (the dust's shadow on the land, as the half-size stage found it)
var<private> wef_up_ds: f32;

// Caught, from just after the dark beat to just before the mouth opens at the spit: nothing of the outside can be seen,
// so none of it is worked out (no dust marched, no pieces, no land's shadows): only the throat and the caught view.
// The work the half stage may do: WEF_DETAIL, and above 1080 lines as much as at 1080 (its pixels more by the square of
// the height: fewer steps each).
fn wef_det() -> f32 {
    let r = clamp(1080.0 / frame.resolution.y, 0.5, 1.0);
    return WEF_DETAIL * r * r;
}
// The dark beat: from the jaws' shut to just before the throat's walls come up the picture is black (wef_caught), so
// nothing is worked out at all.
fn wef_black(t: f32) -> bool {
    // (from the eye's own word only, the shut as it happened: the catch's word is the shut planned, and the jaws can
    // still be open on the sky then: black from it cut the close short by a few frames)
    let t0 = we_w(WE_EYE_T);
    return t0 > 0.0 && t >= t0 + WEF_SHUT_D && t < t0 + we_w(WE_EYE_T + 3u) - 0.1;
}
fn wef_lean(t: f32) -> bool {
    let t0 = we_w(WE_EYE_T);
    // (from the dark beat gone black to the eye passing the tip; a pixel that sees out of the gaping mouth in the last
    // of it is drawn in full: wef_sees_out)
    return t0 > 0.0 && t > t0 + 0.35 && t < wef_tip();
}
// The half-size stage's part of that: to before the jaws gape (1.2 s before the tip), when nothing outside can be seen.
fn wef_lean_half(t: f32) -> bool {
    return wef_lean(t) && t < wef_tip() - 1.3;
}
// Whether the eye's ray (after we_eye_hit_at) leaves by the open mouth into the world.
fn wef_sees_out(hit: WeHit) -> bool {
    return hit.d >= 1.0e8 && we_throat_miss().a >= 1.0e8;
}
// The picture then: the throat along the eye's ray (`hit`) and the caught view over it; a ray that leaves by the mouth
// shows the scene as it is.
fn wef_lean_view(in: StageIn, hit: WeHit) -> vec4<f32> {
    return vec4<f32>(linear_to_srgb(max(wef_lean_col(in, hit), vec3<f32>(0.0))), 1.0);
}
fn wef_lean_col(in: StageIn, hit: WeHit) -> vec3<f32> {
    let t = now();
    let cw = wef_catch();
    var th = we_throat_miss();
    if (hit.d < 1.0e8) {
        th = vec4<f32>(wef_pre_bc, hit.d);
    }
    let col0 = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0).rgb);
    var lt: WefLight;
    return wef_caught(col0, in.uv, normalize(world_offset(in.uv, 0.5)), t, cw, lt, th);
}
// Caught and inside the body: then only the throat is drawn, not the body's outside, the dust or the pieces.
fn wef_inside(t: f32) -> bool {
    if (we_w(WE_EYE_T) > 0.0) {
        return t >= we_w(WE_EYE_T) + WEF_SHUT_D && t <= wef_tip();
    }
    let cw = wef_catch();
    if (cw.x <= 0.0 || t < cw.x || t > max(cw.y, cw.x + 1.5) + 0.5) {
        return false;
    }
    return (t > cw.x + 1.2 && t < max(cw.y, cw.x + 1.5) - 0.4) || we_body_sd(vec3<f32>(0.0), t) < 0.0;
}

// The wormsign's line of light on the land at lr (from the origin), scene_len off: the broken teal crack along each run
// as the head passes under it.
fn wef_line(lr: vec3<f32>, scene_len: f32, time: f32) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    for (var i = 0u; i < wef_run_n(); i = i + 1u) {
        let tout = we_arch_t_out(i);
        if (time < we_aw(i, WE_R_RUN_T) || time > tout + 2.0) {
            continue;
        }
        let F = wef_run_a(i);
        let T = wef_run_b(i);
        let dv = (T - F).xz;
        let len = max(length(dv), 1.0);
        let d = dv / len;
        let q = lr.xz - F.xz;
        let x = dot(q, d);
        let v = q.x * d.y - q.y * d.x;
        let x0 = select(8.0, 45.0, we_run_dive(i));
        let wander = (wef_vn(vec2<f32>(x * 0.12, f32(i) * 7.0)) - 0.5) * 5.0;
        // (at least a couple of pixels across wherever it is seen, though it lies flat and is seen edge on from
        // far off, so it reads at 250 blocks; its pieces longer there in step)
        let lw = clamp(scene_len * 3.0 * frame.resolution.w, 0.2, 6.0);
        if (abs(v - wander) > 4.0 * lw || x < x0 || x > len - WE_R * 0.4) {
            continue;
        }
        let ap = time - wef_run_pass(i, x / len);
        if (ap <= 0.0 || ap > 1.8) {
            continue;
        }
        // (broken: short pieces of a crack line, some missing; thin; flickering out)
        let piece = step(0.4, wef_vh(vec2<f32>(floor(x / (2.5 * sqrt(lw / 1.1))), f32(i) + 51.0)));
        let line = exp(-(v - wander) * (v - wander) / (2.0 * lw * lw));
        let fl = 0.55 + 0.45 * sin(time * 37.0 + x * 1.7);
        let g = piece * line * fl * smoothstep(1.5, 0.5, ap) * (0.75 + 0.25 * exp(-ap / 0.3)) * smoothstep(0.0, 0.06, ap) * (1.0 - wef_fog(scene_len));
        // (near the eye a thin crack only, faint: never a lit patch on the grass in front of the camera)
        acc = acc + vec3<f32>(0.08, 0.75, 0.68) * min(mix(0.5, 3.6, smoothstep(12.0, 200.0, scene_len)) * g, 0.9) * smoothstep(3.0, 14.0, scene_len);
    }
    return acc;
}
// ---- the pass ---------------------------------------------------------------------------------------------------
fn worldeater(in: StageIn, stage: u32, up: vec4<f32>, up_t: f32) -> WeOut {
    var uv = in.uv;
    let time = now();
    we_begin();
    wef_begin(time);
    let lt = wef_light();
    var d = 0.0;
    if (stage == 1u) {
        // (the half-size stage: alternately the nearest and the farthest depth of each two by two pixels)
        let full = vec2<i32>(frame.resolution.xy);
        let q = vec2<i32>(floor(in.position.xy)) * 2;
        let q1 = min(q + vec2<i32>(1), full - vec2<i32>(1));
        let d0 = depth_at((vec2<f32>(q) + 0.5) * frame.resolution.zw);
        let d1 = depth_at((vec2<f32>(f32(q1.x), f32(q.y)) + 0.5) * frame.resolution.zw);
        let d2 = depth_at((vec2<f32>(f32(q.x), f32(q1.y)) + 0.5) * frame.resolution.zw);
        let d3 = depth_at((vec2<f32>(q1) + 0.5) * frame.resolution.zw);
        let hq = vec2<i32>(floor(in.position.xy));
        d = select(min(min(d0, d1), min(d2, d3)), max(max(d0, d1), max(d2, d3)), ((hq.x + hq.y) & 1) == 0);
        uv = (vec2<f32>(q) + 1.0) * frame.resolution.zw;
    } else {
        d = depth_at(uv);
    }
    let sky = is_sky(d);
    var rel = world_offset(uv, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let sun = frame.sun.xyz;
    let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, fract(time * 3.0) * 11.0));
    // (where this pixel's ray meets the land, for the dust to sit on: from the origin)
    let lr = rel - we_o;
    wef_loc = vec4<f32>(lr.xz, select(lr.y, 0.0, sky), pow(0.06 * min(scene_len, 2000.0) + 8.0, 2.0));

    let cw = wef_catch();
    let inside = wef_inside(time);
    wef_clear = 0.0;
    if (cw.x > 0.0 && time > cw.y - 0.5) {
        wef_clear = 1.0 - smoothstep(cw.y + 1.0, cw.y + 3.5, time);
    }
    // (the earth thrown up here is the land's own: sand in a desert, dark soil on grass, browned and darkened)
    wef_earth = vec3<f32>(0.1, 0.082, 0.065);
    if (!sky) {
        let sl = dot(srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb), vec3<f32>(0.2126, 0.7152, 0.0722));
        wef_earth = vec3<f32>(1.0, 0.9, 0.76) * clamp(sl * 0.28, 0.045, 0.22);
    }

    if (stage == 1u) {
        // (the dust, at half size, to the land or the body: premultiplied colour and transmittance, and how far the ray
        // went beside it for the join)
        // (QUALITY FAST does all the heavy work here, a quarter of the pixels: the body traced and coloured along this
        // pixel's ray, laid behind the dust; the join only spreads it out)
        var hd = WE_MISS;
        var bc = vec3<f32>(0.0);
        let gone = wef_gone(time);
        if (!inside && !gone) {
            let bh = we_eye_hit_at(vec3<f32>(0.0), rd, scene_len, time, -1.0e9);
            if (bh.d < scene_len) {
                hd = bh.d;
                bc = we_body_colour(bh, rd, sun, time);
            }
        }
        let t_end = min(scene_len, hd);
        var dc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        wef_land_sh = -1.0;
        if (!inside) {
            dc = wef_dust(rd, t_end, j, time, lt, sun);
        }
        // (and in its first pixel only, whether the player is in the worm's shadow: the join reads it there)
        var cs = 1.0;
        if (all(floor(in.position.xy) == vec2<f32>(0.0)) && time > WE_BREACH && lt.L.y > 0.03) {
            cs = we_body_shade(vec3<f32>(0.0, 0.5, 0.0), sun, time);
        }
        // (and whether a piece passes near: only there does the join look for them)
        let pn = wef_pieces(rd, t_end, time, lt, true).x;
        // (and the dust's shadow on the land this pixel sees, for the join)
        var ds = 1.0;
        if (!sky && hd >= scene_len) {
            // (the land's light: the worm's shadow on it, and (at full detail) the dust's)
            if (time > WE_BREACH && lt.L.y > 0.03 && !gone) {
                ds = mix(0.42, 1.0, we_body_shade(rel, sun, time));
            }
            if (lt.L.y > 0.03 && wef_det() > 0.75) {
                ds = ds * mix(1.0, wef_dust_shadow(rel - we_o, lt.L, time), 0.75);
            }
        }
        // (the wormsign's line of light on the land, added in)
        var lay = dc;
        if (!sky) {
            lay = vec4<f32>(lay.rgb + wef_line(lr, scene_len, time) * lay.a, lay.a);
        }
        // (the body behind the dust: the layer opaque there, and marked (y over 1.5) for the join)
        var fl = 0.0;
        if (hd < scene_len) {
            lay = vec4<f32>(dc.rgb + dc.a * bc, 0.0);
            fl = 2.0;
        }
        return WeOut(lay, vec4<f32>(min(t_end, 6.0e4), cs + fl, pn, ds));
    }

    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    // (before a bite: the land under the coming mouth shivers, by a pixel or two)
    if (!sky) {
        let n = we_n();
        for (var k = 1u; k < 2u * n; k = k + 2u) {
            let ai = time - wef_ti(k);
            if (ai > -1.6 && ai < 0.15) {
                let rr = length((lr - wef_knot(k)).xz);
                let amt = smoothstep(-1.6, -0.1, ai) * smoothstep(0.15, 0.0, ai) * smoothstep(60.0, 30.0, rr);
                if (amt > 0.0) {
                    let fpx = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
                    let a = min(0.35 * fpx / max(scene_len, 1.0), 3.0) * amt;
                    let ph = dot(floor(lr.xz), vec2<f32>(0.37, 0.71));
                    let o = vec2<f32>(sin(time * 41.0 + ph * 5.0), cos(time * 37.0 + ph * 3.0)) * a;
                    col = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv + o * frame.resolution.zw, 0.0).rgb);
                }
            }
        }
    }

    // (the head travelling under the land: near it the land shivers by a pixel or two; just behind it a thin, broken
    // sculk-teal glow seeps through the ground along its track and flickers out within a second or two)
    if (!sky && wef_m.arch >= 0) {
        let rr = length((lr - wef_m.at).xz);
        let amt = smoothstep(40.0, 10.0, rr) * smoothstep(0.0, 1.0, time - we_aw(u32(wef_m.arch), WE_R_RUN_T));
        if (amt > 0.0) {
            let fpx = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
            let a = min(0.25 * fpx / max(scene_len, 1.0), 2.0) * amt;
            let ph = dot(floor(lr.xz), vec2<f32>(0.37, 0.71));
            let o = vec2<f32>(sin(time * 43.0 + ph * 5.0), cos(time * 39.0 + ph * 3.0)) * a;
            col = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv + o * frame.resolution.zw, 0.0).rgb);
        }
    }
    if (!sky) {
        col = col + wef_line(lr, scene_len, time);
    }

    // (the stand-in for the warp's cracks over a breach, as world_fragment paints them on the game's ground: the preview's
    // land is flat, at the hole's height)
    if (WE_STANDIN_MOUND && !sky && wef_m.dome > 0.01) {
        let xk = lr.xz - wef_m.dome_at.xz;
        let gr = smoothstep(5.0, 2.0, lr.y - wef_m.dome_at.y) * smoothstep(-8.0, -4.0, lr.y - wef_m.dome_at.y);
        if (gr > 0.0 && dot(xk, xk) < WE_DOME_R * WE_DOME_R * 1.3) {
            let k = wef_crack(xk, wef_m.dome / WE_DOME_H);
            let fd = gr * smoothstep(WE_DOME_R * 1.1, WE_DOME_R * 0.4, length(xk));
            let core = saturate(k.x) * fd;
            col = col * (1.0 - 0.35 * saturate(k.y) * fd);
            col = mix(col, vec3<f32>(0.05, 0.5, 0.46) * (0.8 + 0.2 * sin(time * 9.0)), 0.7 * core);
        }
    }

    // (the stand-in for the land the warp lifts: the wormsign's mound and the dome, as a heightfield over the land at
    // the origin's level, coloured from the picture where that land was before it was lifted)
    var t_land = scene_len;
    if (WE_STANDIN_MOUND) {
        let dh = 0.0;
        let by = wef_m.dome_at.y;
        if (wef_m.dome > 0.05) {
            let top = dh * 1.25 + 0.5;
            var ta = 0.0;
            var tb = min(scene_len + 4.0, 4000.0);
            if (abs(rd.y) > 1.0e-5) {
                let ya = (we_o.y + by - 2.5) / rd.y;
                let yb = (we_o.y + by + top) / rd.y;
                ta = max(ta, min(ya, yb));
                tb = min(tb, max(ya, yb));
            }
            if (tb > ta) {
                var prev = ta;
                var found = -1.0;
                let N = 64;
                for (var i = 0; i <= N; i = i + 1) {
                    let tt = ta + (tb - ta) * (f32(i) + 0.5 * j) / f32(N);
                    let p = rd * tt - we_o;
                    let lf = wef_lift(p.xz, time);
                    if (lf > 0.05 && p.y < by + lf) {
                        var lo = prev;
                        var hi = tt;
                        for (var b = 0; b < 6; b = b + 1) {
                            let m = 0.5 * (lo + hi);
                            let pm = rd * m - we_o;
                            if (pm.y < by + wef_lift(pm.xz, time)) {
                                hi = m;
                            } else {
                                lo = m;
                            }
                        }
                        found = hi;
                        break;
                    }
                    prev = tt;
                }
                if (found > 0.0 && found < scene_len + 3.0) {
                    let p = rd * found - we_o;
                    let lf = wef_lift(p.xz, time);
                    let src = project_rel(we_o + vec3<f32>(p.x, p.y - lf, p.z));
                    var c = col;
                    if (src.z > 0.0 && all(src.xy > vec2<f32>(0.0)) && all(src.xy < vec2<f32>(1.0))) {
                        c = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, src.xy, 0.0).rgb);
                    }
                    let e = 1.0;
                    let gx = wef_lift(p.xz + vec2<f32>(e, 0.0), time) - wef_lift(p.xz - vec2<f32>(e, 0.0), time);
                    let gz = wef_lift(p.xz + vec2<f32>(0.0, e), time) - wef_lift(p.xz - vec2<f32>(0.0, e), time);
                    let nn = normalize(vec3<f32>(-gx / (2.0 * e), 1.0, -gz / (2.0 * e)));
                    let L = lt.L;
                    let lit = (0.35 + max(dot(nn, L), 0.0)) / (0.35 + max(L.y, 0.05));
                    c = c * clamp(lit, 0.3, 1.6);
                    let k = wef_cracks(p.xz, time);
                    let teal = vec3<f32>(0.06, 0.62, 0.58) * (0.8 + 0.2 * sin(time * 9.0));
                    c = mix(c * (1.0 - 0.55 * min(k.y, 1.0)), teal * 1.6, min(k.x, 1.0)) + teal * 0.35 * k.y;
                    col = c;
                    t_land = found;
                    rel = rd * found;
                }
            }
        }
    }

    // (the stand-in for the holes the land digs (the preview has no land changes): a pit under each knot once it is
    // broken, its walls the layers of the place darkening downward, open to the deep)
    if (WE_STANDIN_MOUND && rd.y < -1.0e-4) {
        let n = we_n();
        for (var k = 0u; k < 2u * n; k = k + 1u) {
            var R = 0.0;
            if ((k & 1u) == 0u && time > wef_tb(k)) {
                R = 40.0 * smoothstep(0.0, 0.25, time - wef_tb(k));
            }
            if ((k & 1u) == 1u && time > wef_ti(k)) {
                R = max(R, 45.0 * smoothstep(0.0, 0.4, time - wef_ti(k)));
            }
            if (R < 0.5) {
                continue;
            }
            let H = we_o + wef_knot(k);
            let tp = H.y / rd.y;
            if (tp <= 0.0) {
                continue;
            }
            let pp = rd * tp;
            let o2 = (pp - H).xz;
            if (length(o2) > R) {
                continue;
            }
            // (something nearer, out of the hole, in front of it)
            if (!sky && t_land < tp - 1.0 && length((rel - H).xz) > R + 1.0) {
                continue;
            }
            let d2 = rd.xz;
            let a2 = max(dot(d2, d2), 1.0e-8);
            let b2 = dot(o2, d2);
            let c2 = dot(o2, o2) - R * R;
            let sw = (-b2 + sqrt(max(b2 * b2 - a2 * c2, 0.0))) / a2;
            let sf = -140.0 / rd.y;
            let sh = min(sw, sf);
            let P = pp + rd * sh;
            let dd = H.y - P.y;
            let wn = -normalize(vec3<f32>((P - H).x, 0.0, (P - H).z) + vec3<f32>(1.0e-4, 0.0, 0.0));
            let nrm = select(wn, vec3<f32>(0.0, 1.0, 0.0), sw > sf);
            let ang = atan2((P - H).z, (P - H).x);
            let fuv = vec2<f32>(ang * R, dd) + vec2<f32>(512.0);
            let kind = select(select(select(1, 2, dd > 4.0), 3, dd > 30.0), 0, dd < 1.0);
            let tex = srgb_to_linear(debris_tex(kind, floor(fuv * 16.0), false, 1.0 - dd * 5.0, f32(k)));
            let li = max(dot(nrm, lt.L), 0.0) * exp(-dd / 25.0);
            col = tex * (lt.sunc * li * 0.8 + lt.amb * (0.45 * exp(-dd / 35.0) + 0.02));
            t_land = tp + sh;
            rel = P;
        }
    }

    // (the worm's shadow on the land, and the dust's)
    wef_land_sh = -1.0;
    wef_rel = rel;
    if (!sky && t_land < 1.0e8) {
        wef_land_sh = we_body_shade(rel, sun, time);
        col = col * mix(0.42, 1.0, wef_land_sh);
        if (lt.L.y > 0.03) {
            // (the half-size stage's, where there is one)
            let ds = select(wef_dust_shadow(rel - we_o, lt.L, time), wef_up_ds, stage == 2u);
            col = col * mix(1.0, ds, 0.75);
        }
    }

    // (the join has looked for it already, against the land or, caught, along the throat's ray: a body behind land
    // nearer than it was found is hidden by the test below; only fs_main looks here, so the join's pipeline holds one
    // copy of the hit)
    var hit = wef_pre_hit;
    var t_end = t_land;
    var th = vec4<f32>(0.0, 0.0, 0.0, 1.0e9);
    if (hit.d < select(t_land, 1.0e8, inside)) {
        let bc = wef_pre_bc;
        th = vec4<f32>(bc, hit.d);
        if (!inside) {
            col = bc;
            t_end = hit.d;
        }
    } else if (inside) {
        th = we_throat_miss();
    }
    if (inside) {
        hit.d = WE_MISS;
    }

    // (the pieces of earth in the air, sharp)
    var pc = vec4<f32>(1.0e9, 0.0, 0.0, 0.0);
    if (stage == 0u || wef_pnear) {
        pc = wef_pieces(rd, t_end, time, lt, false);
    }

    // (the dust: marched here at full size, or the half-size stage's over the picture, the pieces kept in front of it
    // only as far as the dust lets them through)
    if (!inside) {
        if (stage == 0u) {
            let dc = wef_dust(rd, min(t_end, pc.x), j, time, lt, sun);
            if (pc.x < t_end) {
                col = pc.yzw;
            }
            col = col * dc.a + dc.rgb;
        } else {
            if (up_t < t_end) {
                col = col * up.a + up.rgb;
            }
            if (pc.x < t_end) {
                col = mix(col, pc.yzw, 0.35 + 0.65 * up.a);
            }
        }
    }

    // (the body between the player and the sun: the picture a little darker while it passes)
    if (time > WE_BREACH && lt.L.y > 0.03) {
        var cs = wef_cam_sh;
        if (cs < 0.0) {
            cs = we_body_shade(vec3<f32>(0.0, 0.5, 0.0), sun, time);
        }
        col = col * mix(0.8 + 0.2 * f32(sky), 1.0, cs);
    }

    col = wef_lens(col, time, lt);

    if (cw.x > 0.0 && time > cw.x && time < max(cw.y, cw.x + 1.5) + 1.5) {
        col = wef_caught(col, uv, rd, time, cw, lt, th);
    }

    col = we_debug(uv, rd, min(t_land, hit.d), col);
    return WeOut(vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0), vec4<f32>(0.0));
}

// The body for this pixel, once per pipeline (each call site is a whole copy for the compiler): outside, along the
// pixel's ray to the scene's depth, in the half-size join only where its coarse hit found it near; caught, along the
// throat's ray from the virtual eye. Its colour too (wef_pre_bc), for worldeater() and the lean view alike.
var<private> wef_pre_bc: vec3<f32>;
fn wef_body(in: StageIn, near: f32) -> WeHit {
    let t = now();
    let d = depth_at(in.uv);
    let len0 = select(1.0e9, length(world_offset(in.uv, d)), !is_sky(d));
    let inside = wef_inside(t);
    var ey = vec4<f32>(0.0, 0.0, 0.0, -1.0e9);
    if (inside) {
        ey = wef_eye(t, wef_catch());
    }
    // (near: the nearest the half-size stage's coarse hit came round this pixel; -1 in FULL, no half stage)
    let need = inside || near < min(len0, 6.0e4) - 0.5 || we_body_head_near(normalize(world_offset(in.uv, 0.5)), len0, t);
    let rdh = select(normalize(world_offset(in.uv, 0.5)), wef_rdr(in.uv, t, wef_catch()), inside);
    var hit = WeHit();
    hit.d = WE_MISS;
    wef_pre_bc = vec3<f32>(0.0);
    if (need) {
        hit = we_eye_hit_at(ey.xyz, rdh, select(len0, 1.0e9, inside), t, ey.w);
        if (hit.d < 1.0e8) {
            wef_pre_bc = we_body_colour(hit, rdh, frame.sun.xyz, t);
        }
    }
    wef_pre_hit = hit;
    return hit;
}

@fragment
fn fs_main(in0: StageIn) -> @location(0) vec4<f32> {
    we_begin();
    if (wef_black(now())) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    // (caught: the throat and the caught view only, unjolted, unless this pixel sees out of the mouth)
    let lean = wef_lean(now());
    var in = in0;
    if (!lean) {
        in = wef_jolt(in0);
    }
    let hit = wef_body(in, -1.0);
    if (lean && !wef_sees_out(hit)) {
        return wef_lean_view(in, hit);
    }
    wef_full = true;
    wef_cam_sh = -1.0;
    return worldeater(in, 0u, vec4<f32>(0.0, 0.0, 0.0, 1.0), 1.0e9).c;
}

// [half stage]
// QUALITY FAST (mod/src/lib.rs keeps this only then): the dust drawn at half the width and height by fs_half and laid
// over the full-size picture by fs_join; a game without the stage compiles these too and draws fs_main alone, at full
// size.
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

struct WeHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> WeHalf {
    // (caught, nothing outside can be seen: no dust to march)
    we_begin();
    // (caught: the throat and the caught view drawn here, at half size, opaque; the join only spreads it out. The dark
    // beat's black: nothing traced at all)
    let t = now();
    if (wef_black(t)) {
        return WeHalf(vec4<f32>(0.0, 0.0, 0.0, 0.0), vec4<f32>(1.0e4, 3.0, 0.0, 1.0));
    }
    if (wef_inside(t)) {
        var inh = in;
        inh.uv = (floor(in.position.xy) * 2.0 + 1.0) * frame.resolution.zw;
        // (a ray out of the open mouth shows the scene through it, and the eaten land surging out over it)
        let hit = wef_body(inh, -1.0);
        return WeHalf(vec4<f32>(max(wef_lean_col(inh, hit), vec3<f32>(0.0)), 0.0), vec4<f32>(1.0e4, 3.0, 0.0, 1.0));
    }
    let o = worldeater(in, 1u, vec4<f32>(0.0, 0.0, 0.0, 1.0), 1.0e9);
    return WeHalf(o.c, o.e);
}

// The half-size stage at this pixel (whose ray goes `len` blocks, to the land or the body): the four nearest of its
// pixels, each weighed by how near it is and by how near the length it was marched to is to this pixel's
// (carpetbomb.wgsl's cp_up). In .x of the second the length of the one that counts most.
fn we_up(pos: vec2<f32>, len: f32) -> WeOut {
    let hs = vec2<i32>(textureDimensions(half_picture));
    let h = floor(pos) * 0.5 - 0.25;
    let i0 = vec2<i32>(floor(h));
    let f = h - floor(h);
    let lp = min(len, 6.0e4);
    var acc = vec4<f32>(0.0);
    var sw = 0.0;
    var near_dz = 1.0e9;
    var near_c = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var pn = 0.0;
    var ds = 0.0;
    var dw = 0.0;
    // (where the four nearest have nothing (no dust, no piece near, no dust's shadow), nothing: most of the picture,
    // spared the sixteen loads)
    var empty = true;
    for (var k = 0; k < 4; k = k + 1) {
        let q = clamp(i0 + vec2<i32>(k & 1, k >> 1u), vec2<i32>(0), hs - vec2<i32>(1));
        let c = textureLoad(half_picture, q, 0);
        let e = textureLoad(half_extra, q, 0);
        empty = empty && c.a > 0.999 && e.z < 0.5 && e.w > 0.999 && e.y < 1.5;
    }
    if (empty) {
        return WeOut(vec4<f32>(0.0, 0.0, 0.0, 1.0), vec4<f32>(1.0e9, 0.0, 1.0, 0.0));
    }
    var bd = 1.0e9;
    var accb = vec4<f32>(0.0);
    var swb = 0.0;
    var cvb = 0.0;
    var cvt = 0.0;
    // (a tent two of its pixels wide each way, not one: the march's jitter from pixel to pixel is filtered out here, so
    // thin dust comes out as soft alpha, never as a screen of dots)
    for (var k = 0; k < 16; k = k + 1) {
        let o = vec2<i32>((k & 3) - 1, (k >> 2u) - 1);
        let q = clamp(i0 + o, vec2<i32>(0), hs - vec2<i32>(1));
        let c = textureLoad(half_picture, q, 0);
        let e = textureLoad(half_extra, q, 0);
        let dd = abs(vec2<f32>(o) - f);
        let bw = max(1.0 - dd.x * 0.5, 0.0) * max(1.0 - dd.y * 0.5, 0.0);
        let inner = dd.x < 1.0 && dd.y < 1.0;
        if (inner) {
            pn = max(pn, e.z);
        }
        ds = ds + e.w * bw;
        dw = dw + bw;
        let dz = abs(e.x - lp) / max(lp, 1.0);
        let w = bw * exp(-dz * 24.0);
        // (the body, or the throat caught: its colour (and the dust over it) spread by the same wide tent, so the dust's
        // jitter is filtered as it is over the land; how much of this pixel it covers from the nearest four alone, so
        // its edge stays sharp. The body in front of this pixel's land counts whatever its distance, behind it not)
        let bil = select(0.0, (1.0 - dd.x) * (1.0 - dd.y), inner);
        cvt = cvt + bil;
        if (e.y > 1.5) {
            if (!(e.y < 2.5 && e.x > lp * 1.02 + 0.5)) {
                accb = accb + c * bw;
                swb = swb + bw;
                cvb = cvb + bil;
            }
            if (inner && e.y < 2.5) {
                bd = min(bd, e.x);
            }
            continue;
        }
        acc = acc + c * w;
        sw = sw + w;
        if (dz < near_dz) {
            near_dz = dz;
            near_c = c;
        }
    }
    let cov = cvb / max(cvt, 1.0e-4);
    let land = select(near_c, acc / max(sw, 1.0e-6), sw >= 1.0e-3);
    let body = accb / max(swb, 1.0e-6);
    let ex = vec4<f32>(bd, pn, ds / max(dw, 1.0e-4), 0.0);
    if (swb < 1.0e-4) {
        return WeOut(land, ex);
    }
    if (sw < 1.0e-3 && cov > 0.0) {
        return WeOut(body, ex);
    }
    return WeOut(mix(land, body, cov), ex);
}

@fragment
fn fs_join(in0: StageIn) -> @location(0) vec4<f32> {
    // (QUALITY FAST: the half-size stage did the work (the body, the dust, the caught view); here it is spread over the
    // picture against the land's depth, the pieces drawn sharp where it found one near, the lens and the camera's shade.
    // Jolted as fs_main is, the half-size picture drawn steady and read where the jolted pixel looks)
    we_begin();
    let t = now();
    if (wef_black(t)) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    var in = in0;
    if (!wef_lean(t)) {
        in = wef_jolt(in0);
    }
    let d = depth_at(in.uv);
    let sky = is_sky(d);
    let len0 = select(1.0e9, length(world_offset(in.uv, d)), !sky);
    let u = we_up(in.position.xy, len0);
    var col = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0).rgb) * u.e.z;
    let tend = min(len0, u.e.x);
    var pc = vec4<f32>(1.0e9, 0.0, 0.0, 0.0);
    let lt = wef_light();
    if (u.e.y > 0.5 && !wef_inside(t)) {
        pc = wef_pieces(normalize(world_offset(in.uv, 0.5)), tend, t, lt, false);
    }
    col = col * u.c.a + u.c.rgb;
    if (pc.x < tend) {
        col = mix(col, pc.yzw, 0.35 + 0.65 * u.c.a);
    }
    // (the body between the player and the sun: the picture a little darker while it passes)
    if (t > WE_BREACH && lt.L.y > 0.03) {
        var cs = textureLoad(half_extra, vec2<i32>(0), 0).y;
        cs = cs - 2.0 * step(1.5, cs);
        col = col * mix(0.8 + 0.2 * f32(sky), 1.0, saturate(cs));
    }
    col = wef_lens(col, t, lt);
    // (the jaws coming down over the eye: the day faded out over the close, as wef_caught does at full size)
    let e0 = we_w(WE_EYE_T);
    if (e0 > 0.0 && t >= e0 && t < e0 + WEF_SHUT_D) {
        col = col * (1.0 - smoothstep(0.06, WEF_SHUT_D, t - e0));
    }
    return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
}
// [end half stage]
