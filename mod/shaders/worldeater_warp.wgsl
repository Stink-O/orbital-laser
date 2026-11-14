// The World Eater's world warp (the fork's render.set-warp): the land bending up over the head as
// it travels under it (the mound, on the first approach and on every run between arches), and doming up and cracking
// open over each breach in its last second and a half. Every terrain and entity vertex comes through `world_warp`, every
// pixel of the terrain through `world_fragment` (docs/mods.md, "A world warp"); mod/build.rs puts worldeater_path.wgsl's
// `[warp too]` part before this (the constants).
//
// The warp can't read mod_data: the mod packs the mound from `we_mound` into the params each frame
// (lib.rs) and keeps the warp on while the head is under the land:
//   params[0], params[2]  the mound's x and z from the origin (the dome's too: during the dome the head comes straight up
//                         under the breach, so they are one place)
//   params[1]             the mound's height (0: none)
//   params[10]            the dome's height (0: none)
//   params[6]             the way the head goes under the land, radians
//
//   the mound    gone (it read as a pipe stretched under the land); params[1] is no longer read
//   the dome     over a breach: only cracks opening from the middle out over its last second and a half, glowing
//                sculk-teal from below (world_fragment); round 5: no swell, no vertex is ever moved
//
// worldeater.wgsl draws the same land (`wef_lift_at`, `wef_crack`: keep them in step with wew_lift and wew_crack) as a
// stand-in for the preview, which has no warp (WE_STANDIN_MOUND; off in the game's pass).

struct WewClock { t: f32, o: vec3<f32>, live: bool, mc: vec2<f32>, mh: f32, dh: f32, dir: vec2<f32> }
fn wew_clock() -> WewClock {
    let w = globals.warp;
    // (from the camera: the target's ground point, the block's middle one up)
    let o = (vec3<f32>(w[1].x, w[2].w + 1.0, w[1].y) - w[4].xyz) - w[5].xyz;
    let t = w[0].w + w[4].w * 0.05;
    let mh = max(w[0].y, 0.0);
    let dh = max(w[2].z, 0.0);
    // (the laser's number 19, a strike clock, and a mound or a dome up)
    let live = abs(w[1].w - 19.0) < 0.5 && w[2].y > 0.5 && t > 0.0 && dh > 0.01;
    return WewClock(t, o, live, vec2<f32>(w[0].x, w[0].z), mh, dh, vec2<f32>(cos(w[1].z), sin(w[1].z)));
}
fn wew_h(p: vec2<f32>) -> f32 {
    let q = fract(p * vec2<f32>(0.1031, 0.1030));
    let r = q + dot(q, q.yx + 33.33);
    return fract((r.x + r.y) * r.x);
}
// Value noise, 0 to 1, smooth.
fn wew_vn(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = p - i;
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(wew_h(i), wew_h(i + vec2<f32>(1.0, 0.0)), u.x), mix(wew_h(i + vec2<f32>(0.0, 1.0)), wew_h(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
// A smooth bump, 1 in its middle, 0 (and flat) at q2 = 1 (q2: the squared distance in its own radii).
fn wew_b(q2: f32) -> f32 {
    let u = max(1.0 - q2, 0.0);
    return u * u;
}
// A dome dh high over the land at x (level, from its middle), uneven and shivering (the pass's wef_dome_lift).
fn wew_dome_lift(x: vec2<f32>, dh: f32, t: f32) -> f32 {
    if (dh <= 0.01) {
        return 0.0;
    }
    let q2 = dot(x, x) / (WE_DOME_R * WE_DOME_R) * (0.85 + 0.3 * wew_vn(x * 0.05 + vec2<f32>(3.0, 9.0)));
    let shiver = 1.0 + 0.05 * (dh / WE_DOME_H) * sin(t * 37.0 + x.x * 0.9 + x.y * 0.6);
    return dh * wew_b(q2) * shiver;
}
// How much the land at x (level, from the origin) is lifted: no travelling mound any more (it read as a pipe stretched
// under the land: the sign of the head travelling is the pass's bursts and glow and the land's real blocks); only
// a slight, quick swell over the breach in its last half second, at most three blocks (the pass's wef_lift_at).
fn wew_lift(x: vec2<f32>, c: WewClock) -> f32 {
    // (round 5: no displacement of the world at all, anywhere: a swell stretched the leaves near the camera)
    return 0.0;
}
fn world_warp(pos: vec3<f32>, copy: u32) -> Warped {
    // (the world is never moved: only its pixels painted, the cracks in world_fragment)
    return Warped(pos, vec3<f32>(1.0));
}

// [fragments]
// ---- the cracks in the dome: cells ~9 across opening from the middle out as it swells, their lips dark, their cores
// glowing sculk-teal from below ------------------------------------------------------------------------------------
// x: level, from the dome's middle; g how far it has swollen (0 to 1). x: the crack's glowing core (0 to 1), y: its lips.
fn wew_crack(x: vec2<f32>, g: f32) -> vec2<f32> {
    if (g <= 0.0) {
        return vec2<f32>(0.0);
    }
    let r = length(x);
    // (opening from the middle out: by the breach out to the dome's edge and a little past)
    let open = g * smoothstep(WE_DOME_R * 1.15 * g + 4.0, WE_DOME_R * 0.25 * g, r);
    if (open <= 0.001) {
        return vec2<f32>(0.0);
    }
    // (the cells drawn out along the way out from the middle, so they run as radial cracks and a few rings)
    let ang = atan2(x.y, x.x);
    let q = vec2<f32>(r / 7.5, ang * max(r, 6.0) / 10.0) + vec2<f32>(wew_vn(x * 0.11), wew_vn(x * 0.11 + 5.0)) * 0.8;
    let i = floor(q);
    let f = q - i;
    var d1 = 9.0;
    var d2 = 9.0;
    for (var a = -1; a <= 1; a = a + 1) {
        for (var b = -1; b <= 1; b = b + 1) {
            let o = vec2<f32>(f32(a), f32(b));
            let pt = o + vec2<f32>(wew_h(i + o), wew_h(i + o + 17.0)) * 0.8 + 0.1 - f;
            let dd = dot(pt, pt);
            if (dd < d1) {
                d2 = d1;
                d1 = dd;
            } else if (dd < d2) {
                d2 = dd;
            }
        }
    }
    // (blocks to the nearest edge, roughly)
    let e = (sqrt(d2) - sqrt(d1)) * 4.0;
    let w = 0.06 + 0.3 * open * (0.6 + 0.8 * wew_vn(x * 0.2));
    let core = smoothstep(w, w * 0.25, e) * open;
    let lips = exp(-e / (0.3 + 0.5 * open)) * open;
    return vec2<f32>(core, lips);
}
fn world_fragment(f: Fragment) -> Painted {
    // (the face's way up, from how its position changes across the screen: worked out first, while every pixel of the
    // face is still running)
    let up = abs(normalize(cross(dpdx(f.home), dpdy(f.home)) + vec3<f32>(0.0, 1.0e-6, 0.0)).y);
    // (as the game's own fragments: faces cut, and those no light reaches, left out)
    if (f.cut > 0.0 || (f.light.x < 0.5 && f.light.y < 0.5)) {
        return Painted(vec4<f32>(0.0, 0.0, 0.0, -1.0), 1.0);
    }
    let plain = sprite(f.uv, f.layer) * f.color;
    let c = wew_clock();
    if (!c.live || c.dh <= 0.01) {
        return Painted(plain, 1.0);
    }
    let x = f.home.xz - c.o.xz - c.mc;
    let r2 = dot(x, x);
    // (only the ground: faces looking up, at about the land's height over the breach, within the dome; never leaves,
    // trunks or anything standing over the land)
    let ground = smoothstep(0.75, 0.95, up) * smoothstep(5.0, 2.0, f.home.y - c.o.y) * smoothstep(-8.0, -4.0, f.home.y - c.o.y);
    if (r2 > WE_DOME_R * WE_DOME_R * 1.3 || ground <= 0.0) {
        return Painted(plain, 1.0);
    }
    let k = wew_crack(x, c.dh / WE_DOME_H);
    if (k.x + k.y <= 0.001) {
        return Painted(plain, 1.0);
    }
    // (thin lines of light with the dark ground between them, never a flood: the core capped well under saturation, a
    // faint darkening of the lips round it, fading out with distance from the breach)
    let fade = ground * smoothstep(WE_DOME_R * 1.1, WE_DOME_R * 0.4, sqrt(r2));
    let pulse = 0.8 + 0.2 * sin(c.t * 9.0 + wew_h(floor(x * 0.3)) * 6.28);
    let core = saturate(k.x) * fade;
    var col = plain.rgb * (1.0 - 0.35 * saturate(k.y) * fade);
    col = mix(col, vec3<f32>(0.05, 0.5, 0.46) * pulse, 0.7 * core);
    return Painted(vec4<f32>(col, plain.a), 1.0 - 0.4 * core);
}
