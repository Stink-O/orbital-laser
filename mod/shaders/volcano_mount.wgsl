// ---- the mount (strike/vc_mount.rs): the land swelling up, then bursting -------------------------------------------
// Appended to volcano.wgsl as the mod builds the pass; everything here is the mount's, from the tremor's end to the
// white-out. Its hooks in volcano(): vm_surface (the land's picture, the drawn mount over it), vm_air (the steam, the
// dust and the fire, soft, in with the cloud), vm_over (what is sharp, and the white-out), vm_join_len (fs_join).
// The drawn height is land(x) + H(t) * P(x) less a crack's cut, read from the columns vc_mount.rs bakes: the real land
// stays flat underneath, and where it lifts by less than a block or two the real picture is left showing.
const VM_BASE: u32 = 65536u;
const VM_HALF: f32 = 480.0;
const VM_STEP: f32 = 4.0;
const VM_GW: u32 = 241u;
const VM_COLS: u32 = 58081u;
const VM_TSIZE: f32 = 64.0;        // a tile's width, blocks
const VM_TN: i32 = 15;
const VM_TILE: u32 = 65552u;       // VM_BASE + 16: two words a tile
const VM_SHARD: u32 = 66048u;      // VM_BASE + 512: VM_SW words a shard
const VM_SHARDS: u32 = 56u;
const VM_SW: u32 = 22u;
const VM_FOUNT: u32 = 67736u;      // VM_BASE + 2200: eight words each
const VM_FOUNTS: u32 = 44u;
const VM_BOULD: u32 = 68336u;      // VM_BASE + 2800
const VM_BOULDS: u32 = 40u;
const VM_BW: u32 = 16u;
const VM_PLATE: u32 = 69036u;      // VM_BASE + 3500
const VM_PW: u32 = 16u;
const VM_FLY: u32 = 95u;           // the plates thrown
const VM_G: f32 = 34.0;            // what comes back down, blocks a second squared
const VM_GF: f32 = 20.0;           // the lava's: slow, it is that high
const VM_W0: u32 = 73728u;         // VM_BASE + 8192
const VM_W1: u32 = 131809u;        // VM_W0 + VM_COLS
const VM_W2: u32 = 189890u;        // VM_W1 + VM_COLS
const VM_RAD: f32 = 400.0;         // the dome's radius, on average
const VM_H: f32 = 380.0;           // and how high it gets
const VM_SWELL: f32 = 7.0;         // BEATS.md
const VM_HUSH: f32 = 17.0;
const VM_ERUPT: f32 = 18.0;
const VM_GONE: f32 = 19.0;         // nothing of it is left under the white-out
const VM_FIREOUT: f32 = 19.5;      // but the fire sheet's outer ring, burning out as the blast comes up through it

struct VmS {
    on: bool,
    fire: bool,    // the fire sheet still burns
    t: f32,
    H: f32,        // the dome's height
    hk: vec4<f32>, // and each of the plates' four phases' (they lurch up out of step)
    sl: f32,       // how far the land has slid down the dome's back
    cw: f32,       // the cracks' width
    cd: f32,       // how deep they are cut
    open: f32,     // 0 to 1: how far open
    ylo: f32,
    yhi: f32,
    front: f32,    // how far the cracks have raced out
}
var<private> vm: VmS;

fn vm_w(i: u32) -> f32 {
    return bitcast<f32>(mod_data[i]);
}
// The dome's height at time t, its plates' `ph` out of step: slow, then frightening, in lurches, each a little sooner
// than the last; it stops dead.
fn vm_hgt(t: f32, ph: f32) -> f32 {
    let s = clamp(t - VM_SWELL, 0.0, VM_HUSH - VM_SWELL);
    let a = TAU * (0.42 * s + 0.03 * s * s) + ph;
    let da = TAU * (0.42 + 0.06 * s);
    let st = s - 0.8 * sin(a) / da + 0.8 * sin(ph) / (TAU * 0.42);
    let u = saturate(st / 10.0);
    let u2 = u * u;
    // (it stops dead, settling back a little under its own weight; the last instant it heaves)
    let settle = 1.0 - 0.012 * smoothstep(VM_HUSH, VM_HUSH + 0.6, t);
    let heave = 1.0 + 0.09 * smoothstep(VM_ERUPT - 0.03, VM_ERUPT + 0.07, t);
    return VM_H * (0.62 * u + 0.08 * u2 + 0.3 * u2 * u2) * smoothstep(0.0, 0.8, s) * settle * heave;
}
fn vm_set(time: f32) {
    var s: VmS;
    s.t = time;
    let got = arrayLength(&mod_data) > VM_W2 + VM_COLS - 1u && mod_data[VM_BASE] != 0u;
    s.on = got && time > VC_CRACK - 0.1 && time < VM_GONE;
    s.fire = got && time > VM_ERUPT && time < VM_FIREOUT;
    if (s.on || s.fire) {
        s.ylo = vm_w(VM_BASE + 1u) - 12.0;
    }
    if (s.on) {
        s.H = vm_hgt(time, 0.0);
        s.hk = vec4<f32>(s.H, vm_hgt(time, 1.7), vm_hgt(time, 3.3), vm_hgt(time, 4.9));
        s.sl = 0.075 * s.H / VM_H;
        s.open = smoothstep(9.5, 17.0, time);
        s.cw = 1.0 + 12.0 * s.open * s.open;
        s.cd = 4.0 + 75.0 * s.open;
        s.yhi = vm_w(VM_BASE + 2u) + 1.45 * s.H;
        s.front = 200.0 * max(time - VC_CRACK, 0.0);
    }
    vm = s;
}
// Where the land at q (level, from the vent) has come from: its surface spreads out as the dome grows under it.
fn vm_rest(q: vec2<f32>) -> vec2<f32> {
    let w = max(1.0 - dot(q, q) / (453.0 * 453.0), 0.0);
    return q * (1.0 - vm.sl * w * w);
}
// The land at rest position g (in columns): x its top, y how much it has lifted, z how far from its plate's edge.
fn vm_fetch(rest: vec2<f32>) -> vec3<f32> {
    let g = clamp((rest + VM_HALF) / VM_STEP, vec2<f32>(0.0), vec2<f32>(239.999));
    let c = floor(g);
    let f = g - c;
    let b = VM_W0 + u32(c.y) * VM_GW + u32(c.x);
    let a0 = mod_data[b];
    let a1 = mod_data[b + 1u];
    let a2 = mod_data[b + VM_GW];
    let a3 = mod_data[b + VM_GW + 1u];
    let land = vec4<f32>(f32(a0 & 0x7ffu), f32(a1 & 0x7ffu), f32(a2 & 0x7ffu), f32(a3 & 0x7ffu)) * 0.5 - 512.0;
    let p = vec4<f32>(f32((a0 >> 11u) & 0x7ffu), f32((a1 >> 11u) & 0x7ffu), f32((a2 >> 11u) & 0x7ffu), f32((a3 >> 11u) & 0x7ffu)) * (1.6 / 2047.0) - 0.25;
    let lf = p * vec4<f32>(vm.hk[(a0 >> 29u) & 3u], vm.hk[(a1 >> 29u) & 3u], vm.hk[(a2 >> 29u) & 3u], vm.hk[(a3 >> 29u) & 3u]);
    let dv = vec4<f32>(f32((a0 >> 22u) & 127u), f32((a1 >> 22u) & 127u), f32((a2 >> 22u) & 127u), f32((a3 >> 22u) & 127u)) * 0.25;
    var hole = vec4<f32>(0.0);
    if (vm.t > VM_ERUPT) {
        // (the plates thrown leave a hole with the fire in it)
        let o = b - VM_W0 + VM_W2;
        hole = vec4<f32>(vm_gone(mod_data[o]), vm_gone(mod_data[o + 1u]), vm_gone(mod_data[o + VM_GW]), vm_gone(mod_data[o + VM_GW + 1u]));
    }
    let m = vec4<f32>((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
    return vec3<f32>(dot(land, m), dot(lf * (1.0 - hole) - 60.0 * hole, m), dot(dv, m));
}
fn vm_gone(w2: u32) -> f32 {
    return step(vm_w(VM_PLATE + (w2 & 255u) * VM_PW + 8u), vm.t);
}
fn vm_crack_w(r2: f32) -> f32 {
    return vm.cw * (1.0 - 0.72 * saturate(r2 / (440.0 * 440.0)));
}
// How much of the crack's cut at D, a crack `w` wide.
fn vm_cutv(d: f32, w: f32) -> f32 {
    return 1.0 - smoothstep(0.15 * w, w, d);
}
// The top of the drawn land at q (level, from the vent).
fn vm_height(q: vec2<f32>) -> f32 {
    let f = vm_fetch(vm_rest(q));
    let r2 = dot(q, q);
    if (f.y < -1.0) {
        return f.x + f.y;
    }
    let cut = min(0.6 * f.y, vm.cd) * vm_cutv(f.z, vm_crack_w(r2));
    // (sunk just under the real land where it has hardly lifted, so the real picture shows there)
    let sink = 3.0 + 10.0 * (1.0 - smoothstep(0.4, 8.0, f.y));
    return f.x + f.y - cut - sink;
}
fn vm_tile_top(i: vec2<i32>) -> f32 {
    let b = VM_TILE + 2u * u32(i.y * VM_TN + i.x);
    return vm_w(b) + max(vm_w(b + 1u), 0.0) * vm.H * 1.12;
}
// The ray (from the eye, `o` the eye from the vent) on to the drawn land, between t0 and t1: how far, or under 0.
// `seeded`: started from the half-size stage's answer, so a start already under the land is the hit.
fn vm_trace(o: vec3<f32>, rd: vec3<f32>, t0: f32, t1: f32, ds0: f32, seeded: bool) -> f32 {
    let rs = select(rd, rd + vec3<f32>(1.0e-5), abs(rd.x) < 1.0e-5 || abs(rd.z) < 1.0e-5);
    let inv = 1.0 / rs;
    let lo = (vec3<f32>(-VM_HALF, vm.ylo, -VM_HALF) - o) * inv;
    let hi = (vec3<f32>(VM_HALF - 0.1, vm.yhi, VM_HALF - 0.1) - o) * inv;
    let tn = min(lo, hi);
    let tf = max(lo, hi);
    var ta = max(max(tn.x, max(tn.y, tn.z)), t0);
    let tb = min(min(tf.x, min(tf.y, tf.z)), t1);
    if (ta >= tb) {
        return -1.0;
    }
    var t = ta;
    var above = true;
    var left = 220;
    var first = seeded;
    for (var it = 0; it < 40; it = it + 1) {
        let p = o + rd * t;
        let ic = clamp(vec2<i32>(floor((p.xz + VM_HALF) / VM_TSIZE)), vec2<i32>(0), vec2<i32>(VM_TN - 1));
        let b0 = vec2<f32>(ic) * VM_TSIZE - VM_HALF;
        let ex = (select(b0.x, b0.x + VM_TSIZE, rs.x > 0.0) - o.x) * inv.x;
        let ez = (select(b0.y, b0.y + VM_TSIZE, rs.z > 0.0) - o.z) * inv.z;
        let te = min(min(ex, ez) + 0.02, tb);
        let top = vm_tile_top(ic);
        let y1 = o.y + rd.y * te;
        if (min(p.y, y1) < top) {
            var s = t;
            var prev = t;
            loop {
                let q = o + rd * s;
                let gap = q.y - vm_height(q.xz);
                left = left - 1;
                if (gap < 0.0 && (above || first)) {
                    if (first) {
                        return s;
                    }
                    // (between the last two looks, closer)
                    var a = prev;
                    var b = s;
                    for (var j = 0; j < 4; j = j + 1) {
                        let m = 0.5 * (a + b);
                        let qm = o + rd * m;
                        if (qm.y - vm_height(qm.xz) < 0.0) {
                            b = m;
                        } else {
                            a = m;
                        }
                    }
                    return b;
                }
                above = gap >= 0.0;
                first = false;
                prev = s;
                s = s + max(ds0 + s * 0.0016, 0.4 * gap);
                if (s >= te || left <= 0) {
                    break;
                }
            }
            if (left <= 0) {
                return -1.0;
            }
        } else {
            above = true;
            first = false;
        }
        t = te;
        if (t >= tb) {
            break;
        }
    }
    return -1.0;
}
fn vm_565(c: u32) -> vec3<f32> {
    return vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0);
}
// The two colours at rest (sRGB, smooth between the columns), the word of its nearest column.
struct VmC {
    top: vec3<f32>,
    under: vec3<f32>,
    w2: u32,
}
fn vm_cols(rest: vec2<f32>) -> VmC {
    let g = clamp((rest + VM_HALF) / VM_STEP, vec2<f32>(0.0), vec2<f32>(239.999));
    let c = floor(g);
    let f = g - c;
    let b = u32(c.y) * VM_GW + u32(c.x);
    let w = array<u32, 4>(mod_data[VM_W1 + b], mod_data[VM_W1 + b + 1u], mod_data[VM_W1 + b + VM_GW], mod_data[VM_W1 + b + VM_GW + 1u]);
    var o: VmC;
    let tx0 = mix(vm_565(w[0]), vm_565(w[1]), f.x);
    let tx1 = mix(vm_565(w[2]), vm_565(w[3]), f.x);
    o.top = mix(tx0, tx1, f.y);
    o.under = mix(mix(vm_565(w[0] >> 16u), vm_565(w[1] >> 16u), f.x), mix(vm_565(w[2] >> 16u), vm_565(w[3] >> 16u), f.x), f.y);
    let n = vec2<u32>(floor(g + 0.5));
    o.w2 = mod_data[VM_W2 + n.y * VM_GW + n.x];
    return o;
}
fn vm_lin(c: vec3<f32>) -> vec3<f32> {
    return c * c * (0.2 + 0.8 * c);
}
// Lava by how hot (0 to 1 and past it): dull red through orange to yellow-white.
fn vm_ramp(h: f32) -> vec3<f32> {
    let u = max(h, 0.0);
    return vec3<f32>(3.2, 0.5, 0.05) * u * u + vec3<f32>(7.0, 3.6, 0.7) * pow(saturate(u - 0.6) / 0.4, 2.0) * u;
}
// Fire, by how deep in it (0 to 1 and past it): smoke-dark red at its edge to white in its heart.
fn vm_fire(h: f32) -> vec3<f32> {
    let u = saturate(h);
    return mix(vec3<f32>(0.9, 0.12, 0.012), mix(vec3<f32>(5.5, 1.5, 0.16), vec3<f32>(12.0, 8.0, 3.4), smoothstep(0.55, 1.0, u)), smoothstep(0.1, 0.6, u)) * (0.4 + 0.6 * smoothstep(0.0, 0.3, h));
}
// How hot the mount's inside shows at rest radius r, now: from the top down, the top alight by 16 s.
fn vm_heat(r: f32) -> f32 {
    let u = r / VM_RAD;
    let hush = 1.0 - 0.45 * smoothstep(VM_HUSH, VM_HUSH + 0.5, vm.t) + 2.0 * smoothstep(VM_ERUPT - 0.05, VM_ERUPT + 0.08, vm.t);
    return smoothstep(10.0 + 6.2 * u * u, 13.0 + 6.0 * u * u, vm.t) * (0.25 + 0.75 * smoothstep(1.05, 0.25, u)) * hush;
}
// The drawn land's colour at distance t along rd (linear).
fn vm_shade(C: vec3<f32>, rd: vec3<f32>, t: f32, l: VcLight, cam_uv: vec2<f32>) -> vec3<f32> {
    let p = rd * t - C;
    let r2 = dot(p.xz, p.xz);
    let r = sqrt(r2);
    let rest = vm_rest(p.xz);
    let rr = length(rest);
    let f = vm_fetch(rest);
    let cl = vm_cols(rest);
    let pw = t * vs.px;                                   // a pixel's size, blocks
    if (f.y < -1.0) {
        let hn = gnoise2(rest * 0.045 + vec2<f32>(0.0, vm.t * 3.0)) + 0.5 * gnoise2(rest * 0.17);
        return vm_fire(0.15 + 0.58 * hn);
    }
    // ---- the shape's slope, smooth and rough --------------------------------------------------------------------
    let e = max(3.0, pw * 1.5);
    let hc = f.x + f.y;
    let gx = (vm_height(p.xz + vec2<f32>(e, 0.0)) - vm_height(p.xz - vec2<f32>(e, 0.0))) / (2.0 * e);
    let gz = (vm_height(p.xz + vec2<f32>(0.0, e)) - vm_height(p.xz - vec2<f32>(0.0, e))) / (2.0 * e);
    let slope = length(vec2<f32>(gx, gz));
    let nz = gnoise2(rest * 0.11 + vec2<f32>(3.1, 1.7));
    let nz2 = gnoise2(rest * 0.37);
    // (the rock's grain shows on what is broken, and everything's up close)
    let grain = 1.0 - smoothstep(0.5, 3.0, pw);
    let rough = (0.16 + 0.5 * smoothstep(0.5, 1.4, slope)) * (0.5 + 0.5 * grain);
    let b1 = gnoise2(rest * 0.8 + vec2<f32>(p.y * 0.2, -p.y * 0.1)) - 0.5;
    let b2 = gnoise2(rest.yx * 0.8 + vec2<f32>(9.0, p.y * 0.2)) - 0.5;
    let n = normalize(vec3<f32>(-gx + rough * b1, 1.0, -gz + rough * b2));
    // ---- what it is made of ------------------------------------------------------------------------------------
    let wc = vm_crack_w(r2);
    let cutv = vm_cutv(f.z, wc);
    let lifted = smoothstep(1.0, 16.0, f.y);
    let depth = max(hc - p.y, 0.0);                       // how far down a crack or a scarp
    let top = vm_lin(cl.top);
    let under = vm_lin(cl.under);
    // (the layers of the rock, in what is laid open: tipped a little with the plate, bands of pale and dark)
    let plate = f32(cl.w2 & 255u);
    let dip = vec2<f32>(sin(plate * 1.7), cos(plate * 2.3)) * 0.22;
    let by = p.y + dot(rest, dip) + 6.0 * nz;
    let band = 0.5 + 0.2 * sin(by * 0.41 + 3.0 * sin(by * 0.09)) + 0.16 * sin(by * 1.31) + 0.14 * (b1 + b2);
    var rock = mix(vec3<f32>(0.05, 0.047, 0.046), vec3<f32>(0.135, 0.122, 0.108), band);
    rock = mix(rock, vec3<f32>(0.02, 0.019, 0.021), smoothstep(18.0, 70.0, depth));
    // (what stands on it comes away where it steepens: first the trees and the turf, then the dirt)
    let gone = 0.75 * smoothstep(0.1, 0.75, vm.H / VM_H) * smoothstep(0.1, 0.5, f.y / max(vm.H, 1.0));
    let tear = slope + gone + 0.8 * (gnoise2(rest * 0.03 + vec2<f32>(7.0, 2.0)) - 0.5) + 0.7 * (nz - 0.5) + 0.35 * (nz2 - 0.5) + 0.5 * cutv;
    let s1 = smoothstep(0.95, 1.25, tear) * lifted;
    let s2 = smoothstep(1.25, 1.75, tear) * lifted;
    var alb = mix(top, under * 0.8, s1);
    alb = mix(alb, rock, s2);
    // (the land's own: water runs off what tilts, leaving wet ground)
    let kind = (cl.w2 >> 24u) & 7u;
    if (kind == 2u) {
        alb = mix(alb, vec3<f32>(0.05, 0.045, 0.04) * (0.7 + 0.8 * nz2), smoothstep(0.1, 0.45, slope) * smoothstep(3.0, 16.0, f.y));
    }
    // (dust settling on it all, thicker up its back)
    alb = mix(alb, vec3<f32>(0.105, 0.09, 0.08), 0.55 * smoothstep(70.0, VM_H, vm.H) * smoothstep(0.1, 0.6, f.y / max(vm.H, 1.0)) * (0.6 + 0.8 * nz2));
    // ---- its light ---------------------------------------------------------------------------------------------
    var shadow = 1.0;
    if (l.sun_up > 0.0) {
        var s = 9.0;
        for (var i = 0; i < 6; i = i + 1) {
            let q = p + l.L * s;
            if (q.y > vm.yhi) {
                break;
            }
            shadow = min(shadow, saturate(0.5 + (q.y - vm_height(q.xz)) / (0.22 * s + 1.0)));
            s = s * 1.75;
        }
    }
    // (a point in a crevice sees less of the sky)
    let e2 = 15.0;
    let cav = 0.25 * (vm_height(p.xz + vec2<f32>(e2, 0.0)) + vm_height(p.xz - vec2<f32>(e2, 0.0)) + vm_height(p.xz + vec2<f32>(0.0, e2)) + vm_height(p.xz - vec2<f32>(0.0, e2))) - p.y;
    let ao = 1.0 - 0.75 * smoothstep(0.0, 22.0, cav);
    let dl = 0.14 + 0.86 * l.day;
    // (a flat top is as bright as the real land round it, whatever the sun's height; slopes lighter or darker by it)
    let flat_lit = saturate(l.L.y);
    let nl = saturate(dot(n, l.L));
    let lit = (0.5 + (0.92 * (nl - flat_lit) + 0.5) * shadow * l.sun_up + 0.5 * (1.0 - l.sun_up)) * ao * mix(0.72, 1.0, n.y);
    var c = alb * lit * dl * mix(vec3<f32>(1.0), l.sunc * 0.75, 0.35 * l.sun_up);
    // ---- where it has hardly lifted it is the real land itself ---------------------------------------------------
    let same = 1.0 - smoothstep(5.0, 15.0, f.y);
    if (same > 0.0) {
        let W = C + vec3<f32>(rest.x, f.x, rest.y);
        let P = project_rel(W);
        if (P.z > 0.0 && all(P.xy > vec2<f32>(0.001)) && all(P.xy < vec2<f32>(0.999))) {
            let dd = depth_at(P.xy);
            let lw = length(W);
            // (only if the picture does show that land there: nothing in front of it, no sky behind)
            if (!is_sky(dd) && abs(length(world_offset(P.xy, dd)) - lw) < 3.0 + 0.012 * lw) {
                let sc = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, P.xy, 0.0).rgb);
                c = mix(c, sc * saturate(0.45 + lit), same);
            }
        }
    }
    // ---- the fire inside: the cracks lit from under, the air over them glowing on what stands by -------------------
    let heat = vm_heat(rr);
    if (heat > 0.0) {
        // (down in the crack, hotter the deeper; the cracks' lips lit by it)
        let dd = saturate(depth / (8.0 + 0.5 * vm.cd));
        let flick = 0.82 + 0.18 * sin(vm.t * 7.0 + plate * 2.0 + nz * 9.0);
        let cr = cutv * heat * flick;
        c = c + vm_ramp((0.14 + 0.62 * dd + 0.2 * (nz2 - 0.5) + 0.5 * smoothstep(VM_ERUPT - 0.05, VM_ERUPT + 0.08, vm.t)) * cr);
        c = c + min(alb, vec3<f32>(0.2)) * vec3<f32>(1.6, 0.26, 0.04) * heat * exp(-max(f.z - wc, 0.0) / 2.4) * (1.0 - cutv);
    }
    // ---- the cracks while still thin; the smaller breaks over each plate, opening late -----------------------------
    c = vm_hair(c, f.z, rr, pw);
    let d2 = f32((cl.w2 >> 8u) & 255u) / 8.0;
    if (lifted > 0.0) {
        let ww = max(0.5 + 1.1 * vm.open, pw * 0.7);
        let brk = (1.0 - smoothstep(0.3 * ww, ww, d2)) * lifted * smoothstep(9.0, 14.0, vm.t) * min((0.5 + 1.1 * vm.open) / ww, 1.0);
        c = mix(c, vec3<f32>(0.012), brk * 0.85);
        c = c + vm_ramp(0.62 * heat * smoothstep(13.0, 16.5, vm.t)) * brk;
    }
    return c;
}
// A thin crack over what lies at rest radius r: `d` from its line, `pw` a pixel's size there.
fn vm_hair(c: vec3<f32>, d: f32, r: f32, pw: f32) -> vec3<f32> {
    let w = 0.5 + 1.2 * smoothstep(VC_CRACK, 10.0, vm.t);
    let ww = max(w, pw * 0.7);
    let reach = saturate((vm.front - r * (1.0 + 0.0)) / 30.0);
    let line = (1.0 - smoothstep(0.35 * ww, ww, d)) * reach * min(w / ww, 1.0);
    let hot = 0.6 + 0.4 * smoothstep(VC_CRACK, 12.0, vm.t);
    return mix(c, vec3<f32>(0.02, 0.016, 0.014), line * 0.9) + vec3<f32>(0.9, 0.14, 0.02) * line * line * hot * 0.3;
}

// ---- the shards: columns of rock thrust up through it ----------------------------------------------------------------
struct VmSh {
    t: f32,
    n: vec3<f32>,
    i: u32,
    face: u32,  // 5 its broken top
}
// The nearest shard the ray meets before `tmax` (`o` the eye from the vent).
fn vm_shards(o: vec3<f32>, rd: vec3<f32>, tmax: f32) -> VmSh {
    var r: VmSh;
    r.t = -1.0;
    var best = tmax;
    for (var i = 0u; i < VM_SHARDS; i = i + 1u) {
        let b = VM_SHARD + i * VM_SW;
        let t0 = vm_w(b + 4u);
        if (t0 >= vm.t) {
            break;
        }
        let e = saturate((vm.t - t0) / 2.2);
        let rise = 1.0 - (1.0 - e) * (1.0 - e) * (1.0 - e);
        let h = vm_w(b + 5u);
        let rad = vm_w(b + 6u);
        let y0 = vm_w(b + 2u) + vm_w(b + 3u) * vm.H - 30.0 + (h + 30.0) * rise - h;
        var c = vec3<f32>(vm_w(b), y0, vm_w(b + 1u));
        // (the burst takes them with the plates)
        let fly = max(vm.t - VM_ERUPT - 0.06, 0.0);
        if (fly > 0.0) {
            let up = 230.0 + 150.0 * fract(t0 * 7.3);
            c = c + vec3<f32>(c.x * 0.5 * fly, up * fly - 0.5 * VM_G * fly * fly, c.z * 0.5 * fly);
        }
        // (first its sphere: it stands h high, a good deal of that under the land yet)
        let mid = c + vec3<f32>(vm_w(b + 7u) * h, 0.5 * h, vm_w(b + 8u) * h) * 0.5;
        let oc = mid - o;
        let tc = dot(oc, rd);
        let rb = 0.62 * h + rad;
        let dd = dot(oc, oc) - tc * tc;
        if (dd > rb * rb || tc + rb < 0.0) {
            continue;
        }
        let lean = vec2<f32>(vm_w(b + 7u), vm_w(b + 8u));
        let oo = o - c;
        let ro = vec3<f32>(oo.x - lean.x * oo.y, oo.y, oo.z - lean.y * oo.y);
        let dv = vec3<f32>(rd.x - lean.x * rd.y, rd.y, rd.z - lean.y * rd.y);
        let taper = vm_w(b + 11u);
        var tn = -1.0e9;
        var tf = 1.0e9;
        var nb = vec3<f32>(0.0, 1.0, 0.0);
        var fb = 0u;
        for (var f = 0u; f < 5u; f = f + 1u) {
            let n = vec3<f32>(vm_w(b + 12u + 2u * f), taper, vm_w(b + 13u + 2u * f));
            let den = dot(n, dv);
            let tt = (rad - dot(n, ro)) / den;
            if (den < 0.0) {
                if (tt > tn) {
                    tn = tt;
                    nb = n;
                    fb = f;
                }
            } else {
                tf = min(tf, tt);
            }
        }
        // (its top, tilted)
        let tp = vec3<f32>(vm_w(b + 9u), 1.0, vm_w(b + 10u));
        let den = dot(tp, dv);
        let tt = (h - dot(tp, ro)) / den;
        if (den < 0.0) {
            if (tt > tn) {
                tn = tt;
                nb = tp;
                fb = 5u;
            }
        } else {
            tf = min(tf, tt);
        }
        if (tn < tf && tn > 0.0 && tn < best) {
            best = tn;
            r.t = tn;
            r.i = i;
            r.face = fb;
            r.n = normalize(vec3<f32>(nb.x, nb.y - lean.x * nb.x - lean.y * nb.z, nb.z));
        }
    }
    return r;
}
fn vm_shade_shard(C: vec3<f32>, rd: vec3<f32>, h: VmSh, l: VcLight) -> vec3<f32> {
    let p = rd * h.t - C;
    let b = VM_SHARD + h.i * VM_SW;
    // (how far over the land it is torn out of: a shard's foot runs down the slope)
    let up = p.y - vm_height(p.xz);
    // (dark basalt, streaked down its length, each face its own; a broken top with the land's turf on it)
    let f = f32(h.face);
    let st = gnoise2(vec2<f32>(dot(p.xz, vec2<f32>(0.7, -0.7)) * 0.9 + f * 7.0, p.y * 0.05));
    var alb = mix(vec3<f32>(0.018, 0.017, 0.019), vec3<f32>(0.095, 0.086, 0.08), st * st);
    if (h.face == 5u) {
        alb = mix(vm_lin(vm_cols(vec2<f32>(vm_w(b), vm_w(b + 1u))).top), vec3<f32>(0.07, 0.06, 0.05), 0.4);
    }
    let dl = 0.14 + 0.86 * l.day;
    let nl = saturate(dot(h.n, l.L));
    var c = alb * dl * (0.42 + 1.5 * nl * l.sun_up) * mix(vec3<f32>(1.0), l.sunc * 0.75, 0.35 * l.sun_up);
    // (lit red from where it tears out of the land)
    let heat = saturate(vm_heat(length(p.xz)) + 0.35);
    c = c + alb * vec3<f32>(9.0, 1.7, 0.2) * exp(-max(up, 0.0) / 18.0) * heat;
    c = c + vm_ramp(0.55 * exp(-max(up, 0.0) / 7.0) * heat);
    return c;
}

// ---- the plates, thrown: slabs of the land, on their own now, with the fire behind them --------------------------------
struct VmPl {
    t: f32,
    n: vec3<f32>,     // in the world
    rest: vec2<f32>,  // where on the land it was
    kind: u32,        // 0 its top, 1 its edge or underside
    dep: f32,         // how far down through it, 0 to 1
    y: f32,           // how high it was, at rest
}
// A vector turned about the unit axis by an angle (cos, sin).
fn vm_rot(v: vec3<f32>, ax: vec3<f32>, c: f32, s: f32) -> vec3<f32> {
    return v * c + cross(ax, v) * s + ax * dot(ax, v) * (1.0 - c);
}
// The land's top at rest position xz, as it stood when it broke (the holes not counted).
fn vm_top(xz: vec2<f32>) -> f32 {
    let g = clamp((xz + VM_HALF) / VM_STEP, vec2<f32>(0.0), vec2<f32>(239.999));
    let c = floor(g);
    let f = g - c;
    let b = VM_W0 + u32(c.y) * VM_GW + u32(c.x);
    let a0 = mod_data[b];
    let a1 = mod_data[b + 1u];
    let a2 = mod_data[b + VM_GW];
    let a3 = mod_data[b + VM_GW + 1u];
    let land = vec4<f32>(f32(a0 & 0x7ffu), f32(a1 & 0x7ffu), f32(a2 & 0x7ffu), f32(a3 & 0x7ffu)) * 0.5 - 512.0;
    let p = vec4<f32>(f32((a0 >> 11u) & 0x7ffu), f32((a1 >> 11u) & 0x7ffu), f32((a2 >> 11u) & 0x7ffu), f32((a3 >> 11u) & 0x7ffu)) * (1.6 / 2047.0) - 0.25;
    let v = land + p * vm.H;
    return mix(mix(v.x, v.y, f.x), mix(v.z, v.w, f.x), f.y);
}
// Whether the point lp of plate i's frame (cxz its middle, y0 its height) is in it.
fn vm_in_plate(lp: vec3<f32>, cxz: vec2<f32>, y0: f32, i: u32, th: f32) -> bool {
    let xz = lp.xz + cxz;
    if (any(abs(xz) > vec2<f32>(VM_HALF - 3.0))) {
        return false;
    }
    let gc = vec2<u32>((xz + VM_HALF) / VM_STEP + 0.5);
    if ((mod_data[VM_W2 + gc.y * VM_GW + gc.x] & 255u) != i) {
        return false;
    }
    let y = lp.y + y0;
    let top = vm_top(xz);
    return y <= top && y >= top - th;
}
fn vm_plates(o: vec3<f32>, rd: vec3<f32>, tmax: f32) -> VmPl {
    var r: VmPl;
    r.t = -1.0;
    if (vm.t <= VM_ERUPT) {
        return r;
    }
    var best = tmax;
    for (var i = 0u; i < VM_FLY; i = i + 1u) {
        let b = VM_PLATE + i * VM_PW;
        let a = vm.t - vm_w(b + 8u);
        if (a <= 0.0) {
            continue;
        }
        let rest = vec3<f32>(vm_w(b), vm_w(b + 2u) + vm_w(b + 3u) * vm.H, vm_w(b + 1u));
        let c = rest + vec3<f32>(vm_w(b + 9u), vm_w(b + 10u), vm_w(b + 11u)) * a - vec3<f32>(0.0, 0.5 * VM_G * a * a, 0.0);
        let rad = vm_w(b + 6u);
        let oc = c - o;
        let tc = dot(oc, rd);
        let dd = dot(oc, oc) - tc * tc;
        if (dd > rad * rad * 1.1 || tc + rad < 0.0) {
            continue;
        }
        // (the ray in the plate's own frame: there it lies where it lay)
        let ax = vec3<f32>(vm_w(b + 12u), 0.0, vm_w(b + 13u));
        let ang = -vm_w(b + 14u) * a;
        let cs = cos(ang);
        let sn = sin(ang);
        let lo = vm_rot(o - c, ax, cs, sn);
        let ld = vm_rot(rd, ax, cs, sn);
        // (between its top and its underside, planes tilted as the dome was there)
        let g = vec3<f32>(vm_w(b + 4u), 1.0 / vm.H, vm_w(b + 5u));
        let gn = g * vm.H;                   // (-gx, 1, -gz) up to the sign of x and z
        let n = vec3<f32>(-gn.x, 1.0, -gn.z);
        let dn = dot(n, ld);
        if (abs(dn) < 1.0e-5) {
            continue;
        }
        let th = vm_w(b + 7u);
        let mg = vm_w(b + 15u);
        let t0 = (mg - dot(n, lo)) / dn;
        let t1 = (-th - mg - dot(n, lo)) / dn;
        let ta = max(min(t0, t1), 0.0);
        let tb = min(max(t0, t1), best);
        if (ta >= tb) {
            continue;
        }
        let cxz = vec2<f32>(vm_w(b), vm_w(b + 1u));
        // (looks down the ray through the slab for this plate's own columns, between their land's top and its thickness
        // under that: it carries the land as it stood, crags and all; its edges are the cracks')
        let looks = 2 + i32(min((tb - ta) / 4.0, 26.0));
        let dtl = (tb - ta) / f32(looks);
        for (var k = 0; k < looks; k = k + 1) {
            let t = ta + dtl * (f32(k) + 0.1);
            if (!vm_in_plate(lo + ld * t, cxz, rest.y, i, th)) {
                continue;
            }
            var a0 = t - dtl;
            var b0 = t;
            for (var q = 0; q < 4; q = q + 1) {
                let m = 0.5 * (a0 + b0);
                if (vm_in_plate(lo + ld * m, cxz, rest.y, i, th)) {
                    b0 = m;
                } else {
                    a0 = m;
                }
            }
            let lp = lo + ld * b0;
            let xz = lp.xz + cxz;
            let top = vm_top(xz);
            let dep = top - (lp.y + rest.y);
            best = b0;
            r.t = b0;
            r.rest = xz;
            r.kind = select(1u, 0u, dep < 3.4);
            r.dep = saturate(dep / th);
            r.y = lp.y + rest.y;
            var nn = normalize(cross(ld, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4));
            if (r.kind == 0u) {
                let e = 4.0;
                nn = normalize(vec3<f32>((vm_top(xz - vec2<f32>(e, 0.0)) - vm_top(xz + vec2<f32>(e, 0.0))) / (2.0 * e), 1.0, (vm_top(xz - vec2<f32>(0.0, e)) - vm_top(xz + vec2<f32>(0.0, e))) / (2.0 * e)));
            }
            r.n = vm_rot(nn, ax, cs, -sn);
            break;
        }
    }
    return r;
}
fn vm_shade_plate(C: vec3<f32>, rd: vec3<f32>, h: VmPl, l: VcLight) -> vec3<f32> {
    let cl = vm_cols(h.rest);
    let nl = saturate(dot(h.n, l.L));
    let dl = 0.14 + 0.86 * l.day;
    let nz = gnoise2(h.rest * 0.2);
    if (h.kind == 0u) {
        // (its land as it stood, the steep of it bare rock: lit by the sun, the fire on what faces down)
        let slope = sqrt(max(1.0 - h.n.y * h.n.y, 0.0)) / max(h.n.y, 0.15);
        // (as vm_shade made it: what stands on it torn away where it steepens, the water run off, the dust on it)
        let nf = gnoise2(h.rest * 0.11 + vec2<f32>(3.1, 1.7));
        let nf2 = gnoise2(h.rest * 0.37);
        let tear = slope + 0.7 * (nf - 0.5) + 0.35 * (nf2 - 0.5);
        let by = h.y + 6.0 * nf;
        let rock = mix(vec3<f32>(0.05, 0.047, 0.046), vec3<f32>(0.135, 0.122, 0.108), 0.5 + 0.3 * sin(by * 0.41));
        var alb = mix(vm_lin(cl.top), vm_lin(cl.under) * 0.8, smoothstep(0.95, 1.25, tear));
        if (((cl.w2 >> 24u) & 7u) == 2u) {
            alb = vec3<f32>(0.05, 0.045, 0.04) * (0.7 + 0.8 * nf2);
        }
        alb = mix(alb, rock, smoothstep(1.25, 1.75, tear));
        alb = mix(alb, vec3<f32>(0.105, 0.09, 0.08), 0.5 * (0.6 + 0.8 * nf2));
        let d2 = f32((cl.w2 >> 8u) & 255u) / 8.0;
        return mix(alb * dl * (0.4 + 0.9 * nl) + min(alb, vec3<f32>(0.2)) * vec3<f32>(1.6, 0.5, 0.12) * saturate(-h.n.y + 0.1), vec3<f32>(0.012), 0.8 * (1.0 - smoothstep(0.3, 1.4, d2)));
    }
    // (its broken edge and underside: raw rock, burning)
    let st = gnoise2(vec2<f32>(dot(h.rest, vec2<f32>(0.6, 0.8)) * 0.09, h.dep * 2.2));
    let hot = smoothstep(0.62, 1.05, h.dep + 0.7 * (st - 0.5));
    return mix(vec3<f32>(0.02, 0.018, 0.018), vec3<f32>(0.08, 0.07, 0.062), st) * dl * (0.5 + nl) + vm_ramp(0.6 * hot);
}

// What vm_surface gives: the picture there and how far off it (under 0: nothing of the mount here).
struct VmHit {
    c: vec3<f32>,
    t: f32,
}
var<private> vm_seed: f32 = -1.0;  // fs_join's start, from the half-size stage (under 0: from the eye)
var<private> vm_got: f32 = -2.0;   // the hit fs_join found (-2: not looked yet)
var<private> vm_plc: vec3<f32>;    // a thrown plate at this pixel, shown through the fire: land and fire lift as one sheet
var<private> vm_plk: f32 = 0.0;
// The land's picture: the drawn mount where the ray meets it first; on the real land past it, the cracks.
fn vm_surface(C: vec3<f32>, rd: vec3<f32>, scene_len: f32, col: vec3<f32>, stage: u32, l: VcLight, uv: vec2<f32>, sky: bool) -> VmHit {
    var o: VmHit;
    o.c = col;
    o.t = -1.0;
    if (!vm.on) {
        return o;
    }
    var t = vm_got;
    if (t < -1.5) {
        t = vm_trace(-C, rd, 0.0, scene_len + 2.0, select(1.5, 3.0, stage == 1u), false);
    }
    let lim = select(scene_len + 1.5, min(t, scene_len + 1.5), t > 0.0);
    let sh = vm_shards(-C, rd, lim);
    let pl = vm_plates(-C, rd, select(lim, sh.t, sh.t > 0.0));
    // (the air between: it stands a long way off)
    let ap = 1.0 - exp(-select(lim, sh.t, sh.t > 0.0) / 14000.0);
    if (pl.t > 0.0) {
        o.t = pl.t;
        if (stage != 1u) {
            o.c = vm_shade_plate(C, rd, pl, l);
            vm_plc = o.c;
            vm_plk = 1.0;
        }
        return o;
    }
    if (sh.t > 0.0) {
        o.t = sh.t;
        if (stage != 1u) {
            o.c = mix(vm_shade_shard(C, rd, sh, l), vc_haze(rd, l), ap);
        }
        return o;
    }
    if (t > 0.0 && t < scene_len + 1.5) {
        o.t = t;
        if (stage != 1u) {
            o.c = mix(vm_shade(C, rd, t, l, uv), vc_haze(rd, l), ap);
        }
        return o;
    }
    if (stage != 1u && !sky) {
        let p = rd * scene_len - C;
        if (all(abs(p.xz) < vec2<f32>(VM_HALF - 3.0)) && abs(p.y - vm.ylo) < 400.0) {
            let f = vm_fetch(vm_rest(p.xz));
            o.c = vm_hair(col, f.z, length(p.xz), scene_len * vs.px);
        }
    }
    return o;
}

// ---- what hangs in the air over it: the steam off the cracks, the dust down the flanks and round the foot --------------
// Soft: a density from where the cracks and the land are, worn away by noise, marched at half size with the cloud.
// The ground under q, near enough for what hangs over it (one word, no smoothing): .x its height, .y how far from a crack.
fn vm_under(q: vec2<f32>) -> vec2<f32> {
    let g = clamp((vm_rest(q) + VM_HALF) / VM_STEP + 0.5, vec2<f32>(0.0), vec2<f32>(240.0));
    let c = vec2<u32>(g);
    let a = mod_data[VM_W0 + c.y * VM_GW + c.x];
    let land = f32(a & 0x7ffu) * 0.5 - 512.0;
    let p = f32((a >> 11u) & 0x7ffu) * (1.6 / 2047.0) - 0.25;
    return vec2<f32>(land + p * vm.H, f32((a >> 22u) & 127u) * 0.25);
}
struct VmAir {
    steam: f32,
    dust: f32,
    up: f32,     // how far over the land
    crack: f32,  // how far from a crack
}
fn vm_field(q: vec3<f32>, t: f32) -> VmAir {
    var a: VmAir;
    let r = length(q.xz);
    if (r > VM_HALF * 1.2) {
        return a;
    }
    // (wind and rise carry it, so it wanders off the cracks as it climbs)
    let w0 = gnoise3(q * 0.016 + vec3<f32>(0.0, -t * 0.5, 0.0));
    let w1 = gnoise3(q.zxy * 0.016 + vec3<f32>(3.7, -t * 0.5, 1.1));
    let u0 = vm_under(q.xz);
    let up = q.y - u0.x;
    a.up = up;
    if (up < -8.0) {
        return a;
    }
    let wob = vec2<f32>(w0 - 0.5, w1 - 0.5) * (7.0 + 0.9 * max(up, 0.0));
    let u = vm_under(q.xz + wob);
    a.crack = u.y;
    // ---- the steam: thin along the cracks at first, racing out with them, then thick columns off the live ones -------
    let reach = saturate((vm.front - r) / 50.0);
    let live = smoothstep(0.42, 0.68, gnoise2(q.xz * 0.011 + vec2<f32>(t * 0.05, 3.0)));
    // (the great plumes: blobs of a broad noise, wider as they climb, each its own height, standing up off the land)
    let pw = wob * 0.35;
    let pg = gnoise2((q.xz + pw) * 0.0078 + vec2<f32>(11.0, 4.0));
    let pth = 0.68 - 0.00045 * max(up, 0.0);
    let pl = smoothstep(pth, pth + 0.05, pg) * (1.0 - smoothstep(230.0, 420.0, r - 0.5 * max(up, 0.0)));
    let ph = (130.0 + 420.0 * gnoise2((q.xz + pw) * 0.0031)) * smoothstep(6.5, 12.5, t) + 20.0;
    // (a jet where the crack has just got to: a ring of them racing out over the land)
    let jetk = exp(-max(vm.front - r, 0.0) / 300.0);
    let tall = 12.0 + (12.0 + 46.0 * live) * smoothstep(7.0, 15.0, t) * (1.0 - 0.45 * smoothstep(11.0, 14.0, t)) + 120.0 * jetk;
    let wd = 3.0 + 0.22 * max(up, 0.0);
    a.steam = max((1.0 - smoothstep(0.2 * wd, wd, u.y)) * exp(-max(up, 0.0) / tall) * min(0.2 + 0.8 * live + 1.3 * jetk, 1.0) * saturate(1.0 - up / 220.0), pl * saturate(1.0 - up / ph) * saturate(1.0 + up / 8.0)) * reach;
    // ---- the dust: pouring down off what breaks, lying in a ring round its foot, spreading -------------------------
    let dt = smoothstep(9.5, 15.0, t);
    if (dt > 0.0) {
        let k = vm.H / VM_H;
        let fc = dot(q.xz, vec2<f32>(vm_w(VM_BASE + 3u), vm_w(VM_BASE + 4u))) / max(r, 1.0);
        let fr = VM_RAD * (1.16 - 0.32 * fc * fc) * (0.98 + 0.2 * smoothstep(12.0, 17.5, t));
        let ring = exp(-pow((r - fr) / (30.0 + 44.0 * k), 2.0));
        let ht = 16.0 + 46.0 * k;
        let band = ring * exp(-max(up, 0.0) / ht);
        let n = gnoise2(q.xz * 0.009 + vec2<f32>(-0.4 * t, 1.0));
        let n2 = gnoise2(q.xz * 0.023 + vec2<f32>(1.0, 0.3 * t));
        a.dust = band * dt * smoothstep(0.08, 0.5, 0.6 * n + 0.4 * n2);
    }
    // (blown clear by the burst, from the middle out)
    let gone = saturate((vm.t - VM_ERUPT) * 600.0 - r * 1.0) ;
    let clr = 1.0 - saturate(gone / 200.0);
    a.steam = a.steam * clr;
    a.dust = a.dust * clr;
    return a;
}
// How wide the fire sheet is, `a` seconds into the burst: well past the blast's 410 by 18.9, and never to the player's 1,000.
fn vm_fire_r(a: f32) -> f32 {
    return select(0.0, min(80.0 + 760.0 * (1.0 - exp(-a / 0.55)), 720.0), a > 0.0);
}
// Lumps: domes over a jittered lattice, as vc_dome.
fn vm_lump(p: vec3<f32>) -> f32 {
    let b = floor(p - 0.5);
    var hmax = 0.0;
    for (var c = 0u; c < 8u; c = c + 1u) {
        let o = vec3<f32>(f32(c & 1u), f32((c >> 1u) & 1u), f32(c >> 2u));
        let cell = b + o;
        let q = bitcast<vec3<u32>>(vec3<i32>(cell));
        let h = pcg(q.x ^ pcg(q.y ^ pcg(q.z + 0x77u)));
        let jit = vec3<f32>(f32(h & 1023u), f32((h >> 10u) & 1023u), f32((h >> 20u) & 1023u)) * (0.7 / 1023.0) + 0.15;
        let e = cell + jit - p;
        hmax = max(hmax, sqrt(saturate(1.0 - dot(e, e) * 1.7)));
    }
    return hmax;
}
// The fire: boiling up out of the holes and out over the land in a sheet far wider than it is tall; .rgb what it adds,
// .a what it leaves. Its heart white, then yellow and orange out to a torn red edge, the folds between its lumps hottest.
fn vm_fireball(o: vec3<f32>, rd: vec3<f32>, tend: f32, j: f32, a: f32) -> vec4<f32> {
    if (a <= 0.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    const FLAT = 0.56;
    let R = vm_fire_r(a);
    let burn = smoothstep(VM_GONE - 0.05, VM_FIREOUT - 0.05, vm.t);
    let ng = vm.ylo + 8.0;
    let oe = vec3<f32>(o.x, (o.y - ng) / FLAT, o.z);
    let de = vec3<f32>(rd.x, rd.y / FLAT, rd.z);
    let A = dot(de, de);
    let Bq = dot(oe, de);
    let Rb = R * 1.2;
    let disc = Bq * Bq - A * (dot(oe, oe) - Rb * Rb);
    if (disc <= 0.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let sq = sqrt(disc);
    let t0 = max((-Bq - sq) / A, 0.0);
    let t1 = min((-Bq + sq) / A, tend);
    if (t0 >= t1) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    const N = 30;
    let dt = (t1 - t0) / f32(N);
    var c = vec3<f32>(0.0);
    var tr = 1.0;
    var t = t0 + dt * j;
    // (the lumps ride out with it)
    let grow = 1.0 / (0.35 + 0.65 * R / 680.0);
    for (var i = 0; i < N; i = i + 1) {
        let q = o + rd * t;
        t = t + dt;
        let y = q.y - ng;
        if (y < -6.0) {
            continue;
        }
        let e = vec3<f32>(q.x, y / FLAT, q.z);
        let rho = length(e) / R;
        if (rho > 1.2) {
            continue;
        }
        let wq = q * grow + vec3<f32>(0.0, -a * 40.0, 0.0);
        let w = gnoise3(wq * 0.011);
        let l1 = vm_lump((wq + 60.0 * vec3<f32>(w - 0.5)) * (1.0 / 82.0));
        var l = 0.22 * (l1 - 0.55);
        if (abs(rho - 0.85) < 0.45) {
            let l2 = vm_lump((wq + vec3<f32>(9.0, 4.0, 1.0)) * (1.0 / 30.0));
            l = l + 0.1 * (l2 - 0.55);
        }
        // (from the white-out on it burns out from the inside, the blast coming up through it)
        let f = 1.0 - rho + l - 1.2 * burn * smoothstep(1.15, 0.6, rho + 0.35 * burn) - 1.3 * burn * (1.0 - l1);
        if (f <= 0.0) {
            continue;
        }
        let al = (1.0 - exp(-saturate(f * 7.0) * dt * 0.08)) * (1.0 - burn * burn);
        let crease = 1.0 - l1;
        let hot = saturate(f * 2.4) * (0.72 + 0.5 * crease) + 0.1 * smoothstep(0.5, 0.0, a);
        c = c + tr * al * vm_fire(hot * (1.0 - 0.75 * burn));
        tr = tr * (1.0 - al);
        if (tr < 0.02) {
            break;
        }
    }
    return vec4<f32>(c, tr);
}
// The steam and dust along the ray up to `tend`: .rgb what it adds, .a what it leaves.
fn vm_air(C: vec3<f32>, rd: vec3<f32>, tend: f32, j: f32, l: VcLight) -> vec4<f32> {
    if ((!vm.on && !vm.fire) || vm.t < VC_CRACK) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let o = -C;
    let time = vm.t;
    let fa = max(time - VM_ERUPT, 0.0);
    let fire = vm_fireball(o, rd, tend, j, fa);
    if (!vm.on || (fa > 0.3 && fire.a < 0.02)) {
        return fire;
    }
    let ytop = vm.yhi + 240.0;
    let rs = select(rd, rd + vec3<f32>(1.0e-5), abs(rd.x) < 1.0e-5 || abs(rd.z) < 1.0e-5);
    let inv = 1.0 / rs;
    let b = VM_HALF * 1.2;
    let lo = (vec3<f32>(-b, vm.ylo, -b) - o) * inv;
    let hi = (vec3<f32>(b, ytop, b) - o) * inv;
    let tn = min(lo, hi);
    let tf = max(lo, hi);
    let ta = max(max(tn.x, max(tn.y, tn.z)), 0.0);
    let tb = min(min(tf.x, min(tf.y, tf.z)), min(tend, 4000.0));
    if (ta >= tb) {
        return fire;
    }
    const N = 34;
    let dt = (tb - ta) / f32(N);
    var c = vec3<f32>(0.0);
    var tr = 1.0;
    var t = ta + dt * j;
    let dl = 0.14 + 0.86 * l.day;
    let sunk = l.sunc * l.sun_up;
    let ph = 0.8 + 0.5 * pow(saturate(dot(rd, l.L)), 4.0);
    for (var i = 0; i < N; i = i + 1) {
        let q = o + rd * t;
        t = t + dt;
        let a = vm_field(q, time);
        let e = a.steam + a.dust;
        if (e < 0.004) {
            continue;
        }
        // (worn away by noise that climbs and curls: dense in its middle, wisps at its edge)
        let fl = vec3<f32>(0.0, -time * 8.0, 0.0);
        let n1 = gnoise3(q * 0.02 + fl * 0.02);
        let n2 = gnoise3(q.zyx * 0.056 + fl * 0.056 + vec3<f32>(n1 * 1.4));
        var n = 0.62 * n1 + 0.38 * n2;
        if (e < 0.5) {
            n = n - 0.14 * (1.0 - gnoise3(q * 0.15 + fl * 0.15));
        }
        let ds = saturate(a.steam * 2.6 - (1.0 - n) * 1.25) * (1.0 - 0.5 * smoothstep(VM_HUSH, VM_HUSH + 0.8, time));
        let dd = saturate(a.dust * 2.4 - (1.0 - n) * 1.05);
        let den = ds + dd * 1.3;
        if (den < 0.003) {
            continue;
        }
        let al = 1.0 - exp(-(ds + 0.6 * dd * 1.3) * dt * 0.016);
        // ---- lit from above, shaded in its depth; the fire under it ---------------------------------------------------
        let shade = saturate(0.55 + 0.9 * (n - 0.52));
        let alb = mix(vec3<f32>(0.52, 0.43, 0.33), vec3<f32>(0.92, 0.91, 0.9), ds / max(den, 1.0e-3));
        var col = alb * (l.skyl * (0.62 + 0.3 * shade) * dl + sunk * 0.6 * shade * ph);
        let heat = vm_heat(length(q.xz));
        col = col + vec3<f32>(1.1, 0.24, 0.035) * min(heat, 1.0) * exp(-max(a.up, 0.0) / 24.0) * exp(-a.crack / 14.0);
        c = c + tr * al * col;
        tr = tr * (1.0 - al);
        if (tr < 0.02) {
            break;
        }
    }
    // (over what is behind it: the fire)
    return vec4<f32>(c + fire.rgb * tr, tr * fire.a);
}

// [half stage]
// The join's look at the mount: its march starts from the half-size stage's depth (`half_extra`'s x, the nearest of the
// four half-size pixels round this one), so the land's hit is found in a few steps at full size. The depth the upsample
// weighs the cloud against is the mount's where the ray meets it.
fn vm_join_len(pos: vec2<f32>, len: f32, C: vec3<f32>, rd: vec3<f32>) -> f32 {
    vm_set(now());
    if (!vm.on) {
        return len;
    }
    let hs = vec2<i32>(textureDimensions(half_extra));
    let h = vec2<i32>(floor(pos * 0.5 - 0.25));
    var near = 1.0e9;
    for (var k = 0; k < 4; k = k + 1) {
        let q = clamp(h + vec2<i32>(k & 1, k >> 1u), vec2<i32>(0), hs - vec2<i32>(1));
        near = min(near, textureLoad(half_extra, q, 0).x);
    }
    vm_got = -1.0;
    if (near < min(len, 6.0e4) - 0.5) {
        let t = vm_trace(-C, rd, max(near - 14.0, 0.0), len + 2.0, 1.2, true);
        if (t > 0.0) {
            vm_got = t;
            return min(t, len);
        }
    }
    return len;
}
// [end half stage]

// ---- what is sharp over it all: the fountains, the boulders, the rock flung out, the white-out ------------------------
// The lava bursting from cracks: arcs of bright drops off a white-hot jet, fired on and off for as long as it lasts.
fn vm_founts(C: vec3<f32>, rd: vec3<f32>, tmax: f32) -> vec4<f32> {
    var sum = vec4<f32>(0.0);
    if (vm.t < 10.0 || vm.t > VM_GONE + 0.2) {
        return sum;
    }
    for (var i = 0u; i < VM_FOUNTS; i = i + 1u) {
        let b = VM_FOUNT + i * 8u;
        let t0 = vm_w(b + 4u);
        if (t0 >= vm.t) {
            break;
        }
        let a = vm.t - t0;
        let dur = vm_w(b + 5u);
        let h = vm_w(b + 6u);
        let vy = sqrt(2.0 * VM_GF * h);
        let life = 2.0 * vy / VM_GF;
        if (a > dur + life) {
            continue;
        }
        let B = vec3<f32>(vm_w(b), vm_w(b + 2u) + vm_w(b + 3u) * vm.H, vm_w(b + 1u));
        let v = B + C;
        // (a sheet facing the eye, through its foot)
        let dist = length(v.xz);
        let n = v.xz / max(dist, 1.0);
        let den = dot(rd.xz, n);
        if (den < 0.02) {
            continue;
        }
        let tp = dist / den;
        if (tp > tmax + 6.0) {
            continue;
        }
        let P = rd * tp - v;
        let side = vec2<f32>(-n.y, n.x);
        let px = dot(P.xz, side);
        let py = P.y;
        if (abs(px) > 0.9 * h + 6.0 || py < -6.0 || py > h * 1.15) {
            continue;
        }
        let pw = tp * vs.px;
        let seed = u32(vm_w(b + 7u) * 100.0);
        // (the jet: from the crack, narrowing as it climbs, on while it fires)
        let on = smoothstep(0.0, 0.12, a) * (1.0 - smoothstep(dur - 0.3, dur, a));
        let top = h * (0.8 + 0.2 * sin(a * 2.6 + f32(seed))) * on;
        let hu = saturate(py / max(top, 1.0));
        let wj = max(1.2 + 0.022 * h * (1.0 - 0.6 * hu), pw * 0.6);
        let clot = gnoise2(vec2<f32>(px * 0.11 + f32(seed), py * 0.045 - vm.t * 2.4));
        let jet = exp(-px * px / (wj * wj)) * smoothstep(1.0, 0.55, hu) * step(-2.0, py) * on * smoothstep(0.34 + 0.3 * hu, 0.56 + 0.3 * hu, clot + 0.4 * (1.0 - hu));
        if (jet > 0.0) {
            let jc = mix(vec3<f32>(0.6, 0.07, 0.01), mix(vec3<f32>(1.5, 0.28, 0.03), vec3<f32>(2.0, 0.62, 0.06), smoothstep(0.4, 0.05, hu)), smoothstep(0.92, 0.5, hu));
            sum = sum + vec4<f32>(jc * jet, jet) * (1.0 - sum.a);
        }
        // (the drops, each thrown at its own moment on its own line, cooling as they go)
        for (var k = 0u; k < 26u; k = k + 1u) {
            let ta = dur * mh(k, seed, 0x771u);
            let s = a - ta;
            let lf = life * (0.55 + 0.45 * mh(k, seed, 0x772u));
            if (s <= 0.0 || s > lf) {
                continue;
            }
            let vk = vy * (0.5 + 0.5 * mh(k, seed, 0x773u));
            let vs_ = (mh(k, seed, 0x774u) - 0.5) * 0.5 * vy;
            let x = vs_ * s;
            let y = vk * s - 0.5 * VM_GF * s * s;
            // (a short streak along its way)
            let dt = 0.11;
            let ex = vs_ * dt;
            let ey = (vk - VM_GF * s) * dt;
            let qx = px - x;
            let qy = py - y;
            let u = saturate((qx * ex + qy * ey) / (ex * ex + ey * ey + 1.0e-4));
            let d = length(vec2<f32>(qx - ex * u, qy - ey * u));
            let w0 = 0.8 + 1.2 * mh(k, seed, 0x775u);
            let w = max(w0, pw * 0.7);
            if (d < 2.5 * w) {
                let cool = saturate(s / lf);
                let dr = exp(-d * d / (w * w)) * min(w0 / w * 1.5, 1.0);
                let dc = mix(mix(vec3<f32>(1.7, 0.4, 0.04), vec3<f32>(0.65, 0.08, 0.01), smoothstep(0.0, 0.6, cool)), vec3<f32>(0.05, 0.02, 0.015), smoothstep(0.55, 1.0, cool));
                sum = sum + vec4<f32>(dc * dr, dr) * (1.0 - sum.a);
            }
        }
    }
    return sum;
}
// The rock flung out with the plates: thousands of chunks, in shells flying out, from the eye's look only where a ray
// crosses a shell (so the count costs nothing). .rgb its colour, .a how much of the pixel it covers.
fn vm_chunks(C: vec3<f32>, rd: vec3<f32>, tmax: f32, l: VcLight) -> vec4<f32> {
    let a = vm.t - VM_ERUPT;
    var best = tmax;
    var out = vec4<f32>(0.0);
    let flat_y = 0.6;
    for (var k = 0u; k < 9u; k = k + 1u) {
        let fk = f32(k);
        let R = 300.0 + (90.0 + 50.0 * fk) * a * (1.0 + 0.4 * a);
        // (an ellipsoid, flattened: the sheet is wider than it is tall)
        let oe = vec3<f32>(-C.x, (-C.y - vm.ylo) / flat_y, -C.z);
        let de = vec3<f32>(rd.x, rd.y / flat_y, rd.z);
        let A = dot(de, de);
        let Bq = dot(oe, de);
        let cq = dot(oe, oe) - R * R;
        let disc = Bq * Bq - A * cq;
        if (disc <= 0.0) {
            continue;
        }
        let sq = sqrt(disc);
        for (var h = 0; h < 2; h = h + 1) {
            let t = (-Bq + (f32(h) * 2.0 - 1.0) * sq) / A;
            if (t <= 60.0 || t >= best) {
                continue;
            }
            let p = oe + de * t;
            let dir = p / R;
            if (dir.y < 0.02) {
                continue;
            }
            let u = (atan2(dir.z, dir.x) / TAU + 0.5) * 220.0;
            let w = asin(saturate(dir.y)) / 1.5708 * 52.0;
            let cell = floor(vec2<f32>(u, w));
            let id = u32(cell.x) + u32(cell.y) * 257u + k * 9973u;
            let hs = pcg(id);
            if (f32(hs & 0xffu) / 255.0 > 0.05 + 0.15 * smoothstep(0.15, 0.55, a)) {
                continue;
            }
            let cu = cell + vec2<f32>(0.2 + 0.6 * f32((hs >> 8u) & 0xffu) / 255.0, 0.2 + 0.6 * f32((hs >> 16u) & 0xffu) / 255.0);
            // (cells in angle: as big in blocks as the shell's radius makes them; its rock smaller than a cell)
            let scale = vec2<f32>(TAU * R / 220.0 * sqrt(max(1.0 - dir.y * dir.y, 0.02)), 1.5708 * R / 52.0);
            let dv = (vec2<f32>(u, w) - cu) * scale;
            let size = (1.0 + 9.0 * pow(f32(hs >> 24u) / 255.0, 5.0)) * min(t / 260.0, 1.0) * smoothstep(0.03, 0.2, a);
            let pw = t * vs.px;
            // (a broken rock, not a disc: straight sides, turned its own way)
            let ang = f32(hs & 0xfffu) * 0.0015 + a * (2.0 + f32((hs >> 12u) & 7u));
            let ca = cos(ang);
            let sa = sin(ang);
            let e = vec2<f32>(ca * dv.x - sa * dv.y, sa * dv.x + ca * dv.y) * vec2<f32>(1.0, 0.8);
            let dlen = max(max(abs(e.x) * 1.3, abs(e.y) * 0.8), (abs(e.x) + abs(e.y)) * 0.86);
            if (dlen < size + pw) {
                let cover = saturate((size + 0.5 * pw - dlen) / pw);
                best = t;
                let hot = exp(-a * 1.6) * saturate(-0.1 - e.y / size);
                out = vec4<f32>(vec3<f32>(0.016, 0.014, 0.013) * (0.3 + l.day) + vm_ramp(0.6 * hot), cover);
            }
        }
    }
    return out;
}
// Boulder b's line, r out (the land and the lift along it).
fn vm_rock_at(b: u32, r: f32, r0: f32, r1: f32) -> vec3<f32> {
    let u = 3.0 * saturate((r - r0) / (r1 - r0));
    let i0 = min(u32(u), 2u);
    let f = u - f32(i0);
    let s0 = vm_w(b + 8u + 2u * i0) + vm_w(b + 9u + 2u * i0) * vm.H;
    let s1 = vm_w(b + 10u + 2u * i0) + vm_w(b + 11u + 2u * i0) * vm.H;
    return vec3<f32>(vm_w(b) * r, mix(s0, s1, f), vm_w(b + 1u) * r);
}
// The ray from the eye (rd, a unit) against the segment a to b: .x the distance squared at their closest, .y how far along
// the segment, .z how far along the ray.
fn vm_seg(rd: vec3<f32>, a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    let u = b - a;
    let A = dot(u, u);
    let B = dot(u, rd);
    let D = dot(u, -a);
    let E = dot(rd, -a);
    let s = saturate((D - B * E) / max(A - B * B, 1.0e-3));
    let t = s * B - E;
    let e = rd * t - a - u * s;
    return vec3<f32>(dot(e, e), s, t);
}
// The boulders rolling down: lumps of rock, each dragging its dust down the slope, bounding as they go.
fn vm_rocks(C: vec3<f32>, rd: vec3<f32>, tmax: f32, l: VcLight, col: vec3<f32>) -> vec3<f32> {
    var c = col;
    var best = tmax;
    var dust = 0.0;
    for (var i = 0u; i < VM_BOULDS; i = i + 1u) {
        let b = VM_BOULD + i * VM_BW;
        let a = vm.t - vm_w(b + 4u);
        if (a <= 0.0) {
            continue;
        }
        let r0 = vm_w(b + 2u);
        let r1 = vm_w(b + 3u);
        let r = r0 + 0.5 * vm_w(b + 5u) * a * a;
        if (r > r1) {
            continue;
        }
        let size = vm_w(b + 6u);
        let hop = size * 0.9 * abs(sin(a * 1.7 + vm_w(b + 7u))) * smoothstep(0.0, 1.0, a);
        // (the dust it raises hangs on the slope behind it, spreading and thinning)
        let run = r - r0;
        let tl = min(run, 40.0 + 2.4 * sqrt(2.0 * vm_w(b + 5u) * run));
        let pa = vm_rock_at(b, r - tl, r0, r1) + vec3<f32>(0.0, size * 0.8, 0.0) + C;
        let pm = vm_rock_at(b, r - 0.5 * tl, r0, r1) + vec3<f32>(0.0, size * 0.7, 0.0) + C;
        let pb = vm_rock_at(b, r, r0, r1) + vec3<f32>(0.0, size * 0.6, 0.0) + C;
        for (var q = 0; q < 2; q = q + 1) {
            let a0 = select(pa, pm, q == 1);
            let a1 = select(pm, pb, q == 1);
            let g = vm_seg(rd, a0, a1);
            if (g.z > 0.0 && g.z < tmax + 20.0) {
                let v = (f32(q) + g.y) * 0.5;      // 0 its tail, 1 at the rock
                let wd = size * mix(3.2, 0.9, v) + 9.0 * (1.0 - v);
                let dn = exp(-g.x / (wd * wd)) * smoothstep(0.0, 0.3, v) * 0.72 * min(a * 1.2, 1.0);
                dust = dust + dn * (1.0 - dust);
            }
        }
        let P = vm_rock_at(b, r, r0, r1) + vec3<f32>(0.0, size + hop, 0.0) + C;
        let tc = dot(P, rd);
        let e = P - rd * tc;
        let d2 = dot(e, e);
        // (a lump, not a ball: turning as it goes)
        let sd = vec2<f32>(dot(e, normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)))), e.y);
        let ga = atan2(sd.y, sd.x) + a * 1.1 + vm_w(b + 7u);
        let rr = size * (1.0 + 0.13 * sin(ga * 2.0 + 0.7) + 0.08 * sin(ga * 3.0 + vm_w(b + 7u)));
        if (tc < 0.0 || tc > best || d2 > rr * rr) {
            continue;
        }
        let tq = tc - sqrt(rr * rr - d2);
        let q = (rd * tq - P) / rr;
        let n = normalize(q + 0.3 * vec3<f32>(sin(q.y * 3.0 + a * 1.4), sin(q.z * 4.0 + 1.0), sin(q.x * 3.0 + a * 1.1)));
        let dl = 0.14 + 0.86 * l.day;
        c = vec3<f32>(0.075, 0.066, 0.058) * dl * (0.45 + 1.3 * saturate(dot(n, l.L)));
        best = tc;
    }
    let dc = vec3<f32>(0.3, 0.255, 0.205) * (0.4 + 0.6 * l.day) * mix(vec3<f32>(1.0), l.sunc * 0.75, 0.3 * l.sun_up);
    return mix(c, dc, dust);
}
// `len` how far the picture's ray goes, the steam counted.
fn vm_over(col0: vec3<f32>, C: vec3<f32>, rd: vec3<f32>, len: f32, l: VcLight) -> vec3<f32> {
    let time = now();
    if (time < VC_CRACK || time > VM_ERUPT + 1.4 || !(arrayLength(&mod_data) > VM_W2 + VM_COLS - 1u) || mod_data[VM_BASE] == 0u) {
        return col0;
    }
    var col = mix(col0, vm_plc, 0.72 * vm_plk);
    if (vm.on) {
        col = vm_rocks(C, rd, len, l, col);
        let fo = vm_founts(C, rd, len);
        col = col * (1.0 - fo.a) + fo.rgb;
        if (time > VM_ERUPT) {
            let ch = vm_chunks(C, rd, len, l);
            col = mix(col, ch.rgb, ch.a);
        }
    }
    // ---- the white-out, one flash: from where the mount was out over the picture, at its height by VM_GONE, gone by a
    // quarter of a second after it (nothing longer: photosensitivity) -----------------------------------------------
    if (time > VM_ERUPT + 0.5) {
        let u = smoothstep(VM_ERUPT + 0.6, VM_GONE - 0.03, time);
        let down = 1.0 - smoothstep(VM_GONE + 0.05, VM_GONE + 0.24, time);
        let P = C + vec3<f32>(0.0, 170.0, 0.0);
        let cs = dot(normalize(P), rd);
        // (it blooms out from the burst, soft, no edge to it: the look away from it goes last)
        let ang = sqrt(max(2.0 * (1.0 - cs), 0.0));
        let glow = exp(-ang / (0.05 + 1.5 * u * u)) * smoothstep(0.0, 0.5, u);
        col = col + mix(vec3<f32>(2.6, 1.5, 0.6), vec3<f32>(2.6, 2.3, 1.9), u) * glow * 1.6 * down;
        let w = u * u * u * u;
        col = mix(col, vec3<f32>(1.7), saturate(w) * down);
    }
    return col;
}
