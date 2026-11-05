// ---- the mount (strike/vc_mount.rs): the land swelling up, then bursting -------------------------------------------
// Appended to volcano.wgsl as the mod builds the pass; everything here is the mount's, from the tremor's end to the
// white-out. Its hooks in volcano(): vm_surface (the land's picture, the drawn mount over it), vm_air (the steam, the
// dust and the fire, soft, in with the cloud), vm_over (what is sharp, and the white-out), vm_join_len (fs_join).
// The drawn height is land(x) + H(t) * P(x) less a crack's cut, read from the columns vc_mount.rs bakes: the real land
// stays flat underneath, and where it lifts by less than a block or two the real picture is left showing.
const VM_BASE: u32 = 65536u;
const VM_HALF: f32 = 360.0;
const VM_STEP: f32 = 3.0;
const VM_GW: u32 = 241u;
const VM_COLS: u32 = 58081u;
const VM_TSIZE: f32 = 48.0;        // a tile's width, blocks
const VM_TN: i32 = 15;
const VM_TILE: u32 = 65552u;       // VM_BASE + 16: three words a tile
const VM_SPIRE: u32 = 66236u;      // VM_BASE + 700: four words a spire
const VM_W0: u32 = 69632u;         // VM_BASE + 4096
const VM_W1: u32 = 127713u;        // VM_W0 + VM_COLS
const VM_W2: u32 = 185794u;        // VM_W1 + VM_COLS
const VM_RAD: f32 = 300.0;         // the dome's radius, on average
const VM_SWELL: f32 = 7.0;         // BEATS.md
const VM_HUSH: f32 = 17.0;
const VM_ERUPT: f32 = 18.0;
const VM_GONE: f32 = 19.0;         // nothing of it is left under the white-out

struct VmS {
    on: bool,
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
    let a = TAU * (0.55 * s + 0.045 * s * s) + ph;
    let da = TAU * (0.55 + 0.09 * s);
    let st = s - 0.8 * sin(a) / da + 0.8 * sin(ph) / (TAU * 0.55);
    let u = saturate(st / 10.0);
    let u2 = u * u;
    return 150.0 * (0.035 * u + 0.225 * u2 + 0.74 * u2 * u2) * smoothstep(0.0, 0.8, s);
}
fn vm_set(time: f32) {
    var s: VmS;
    s.t = time;
    s.on = arrayLength(&mod_data) > VM_W2 + VM_COLS - 1u && mod_data[VM_BASE] != 0u && time > VC_CRACK - 0.1 && time < VM_GONE;
    if (s.on) {
        s.H = vm_hgt(time, 0.0);
        s.hk = vec4<f32>(s.H, vm_hgt(time, 1.7), vm_hgt(time, 3.3), vm_hgt(time, 4.9));
        s.sl = 0.075 * s.H / 150.0;
        s.open = smoothstep(9.5, 17.0, time);
        s.cw = 0.8 + 9.0 * s.open * s.open;
        s.cd = 3.0 + 42.0 * s.open;
        s.ylo = vm_w(VM_BASE + 1u) - 12.0;
        s.yhi = vm_w(VM_BASE + 2u) + 1.45 * s.H + 74.0;
        s.front = 165.0 * max(time - VC_CRACK, 0.0);
    }
    vm = s;
}
// Where the land at q (level, from the vent) has come from: its surface spreads out as the dome grows under it.
fn vm_rest(q: vec2<f32>) -> vec2<f32> {
    let w = max(1.0 - dot(q, q) / (340.0 * 340.0), 0.0);
    return q * (1.0 - vm.sl * w * w);
}
// A spire's height now, at its share `v`: it punches up, hard, and goes on rising slowly.
fn vm_spire(w2: u32) -> f32 {
    let id = (w2 >> 8u) & 255u;
    if (id == 0u) {
        return 0.0;
    }
    let i = VM_SPIRE + (id - 1u) * 4u;
    let t0 = vm_w(i);
    let e = saturate((vm.t - t0) / 1.1);
    let rise = 1.0 - (1.0 - e) * (1.0 - e) * (1.0 - e);
    return vm_w(i + 1u) * f32((w2 >> 16u) & 255u) / 255.0 * rise;
}
// The land at rest position g (in columns): x its top, y how much it has lifted, z how far from its plate's edge, w the
// spire on it.
fn vm_fetch(rest: vec2<f32>) -> vec4<f32> {
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
    var sp = vec4<f32>(0.0);
    if (((a0 | a1 | a2 | a3) >> 31u) != 0u) {
        let o = b - VM_W0 + VM_W2;
        if ((a0 >> 31u) != 0u) { sp.x = vm_spire(mod_data[o]); }
        if ((a1 >> 31u) != 0u) { sp.y = vm_spire(mod_data[o + 1u]); }
        if ((a2 >> 31u) != 0u) { sp.z = vm_spire(mod_data[o + VM_GW]); }
        if ((a3 >> 31u) != 0u) { sp.w = vm_spire(mod_data[o + VM_GW + 1u]); }
    }
    let m = vec4<f32>((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
    return vec4<f32>(dot(land, m), dot(lf, m), dot(dv, m), dot(sp, m));
}
fn vm_crack_w(r2: f32) -> f32 {
    return vm.cw * (1.0 - 0.72 * saturate(r2 / (330.0 * 330.0)));
}
// How much of the crack's cut at D, a crack `w` wide.
fn vm_cutv(d: f32, w: f32) -> f32 {
    return 1.0 - smoothstep(0.15 * w, w, d);
}
// The top of the drawn land at q (level, from the vent).
fn vm_height(q: vec2<f32>) -> f32 {
    let f = vm_fetch(vm_rest(q));
    let r2 = dot(q, q);
    let cut = min(0.6 * max(f.y, 0.0), vm.cd) * vm_cutv(f.z, vm_crack_w(r2));
    // (sunk just under the real land where it has hardly lifted, so the real picture shows there)
    let sink = 3.0 + 10.0 * (1.0 - smoothstep(0.4, 8.0, f.y + f.w));
    return f.x + f.y + f.w - cut - sink;
}
fn vm_tile_top(i: vec2<i32>) -> f32 {
    let b = VM_TILE + 3u * u32(i.y * VM_TN + i.x);
    return vm_w(b) + max(vm_w(b + 1u), 0.0) * vm.H * 1.12 + vm_w(b + 2u);
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
                s = s + max(ds0 + s * 0.0012, 0.4 * gap);
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
// How hot the mount's inside shows at rest radius r, now: from the top down, the top alight by 16 s.
fn vm_heat(r: f32) -> f32 {
    let u = r / VM_RAD;
    return smoothstep(10.0 + 6.2 * u * u, 13.0 + 6.0 * u * u, vm.t) * (0.25 + 0.75 * smoothstep(1.05, 0.25, u));
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
    // ---- the shape's slope, smooth and rough --------------------------------------------------------------------
    let e = max(2.2, pw * 1.5);
    let hc = f.x + f.y + f.w;
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
    rock = mix(rock, vec3<f32>(0.02, 0.019, 0.021), smoothstep(14.0, 44.0, depth));
    // (what stands on it comes away where it steepens: first the trees and the turf, then the dirt)
    let tear = slope + 0.7 * (nz - 0.5) + 0.35 * (nz2 - 0.5) + 0.5 * cutv;
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
    alb = mix(alb, vec3<f32>(0.17, 0.145, 0.12), 0.5 * smoothstep(40.0, 150.0, vm.H) * smoothstep(0.1, 0.6, f.y / max(vm.H, 1.0)) * (0.6 + 0.8 * nz2));
    // ---- its light ---------------------------------------------------------------------------------------------
    var shadow = 1.0;
    if (l.sun_up > 0.0) {
        var s = 7.0;
        for (var i = 0; i < 5; i = i + 1) {
            let q = p + l.L * s;
            if (q.y > vm.yhi) {
                break;
            }
            shadow = min(shadow, saturate(0.5 + (q.y - vm_height(q.xz)) / (0.22 * s + 1.0)));
            s = s * 1.75;
        }
    }
    // (a point in a crevice sees less of the sky)
    let e2 = 11.0;
    let cav = 0.25 * (vm_height(p.xz + vec2<f32>(e2, 0.0)) + vm_height(p.xz - vec2<f32>(e2, 0.0)) + vm_height(p.xz + vec2<f32>(0.0, e2)) + vm_height(p.xz - vec2<f32>(0.0, e2))) - p.y;
    let ao = 1.0 - 0.75 * smoothstep(0.0, 16.0, cav);
    let dl = 0.14 + 0.86 * l.day;
    // (a flat top is as bright as the real land round it, whatever the sun's height; slopes lighter or darker by it)
    let flat_lit = saturate(l.L.y);
    let nl = saturate(dot(n, l.L));
    let lit = (0.5 + (0.92 * (nl - flat_lit) + 0.5) * shadow * l.sun_up + 0.5 * (1.0 - l.sun_up)) * ao * mix(0.72, 1.0, n.y);
    var c = alb * lit * dl * mix(vec3<f32>(1.0), l.sunc * 0.75, 0.35 * l.sun_up);
    // ---- where it has hardly lifted it is the real land itself ---------------------------------------------------
    let same = 1.0 - smoothstep(5.0, 15.0, f.y + f.w);
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
        let dd = saturate(depth / (6.0 + 0.5 * vm.cd));
        let flick = 0.82 + 0.18 * sin(vm.t * 7.0 + plate * 2.0 + nz * 9.0);
        let cr = cutv * heat * flick;
        c = c + vm_ramp((0.2 + 0.85 * dd + 0.25 * (nz2 - 0.5)) * cr);
        c = c + alb * vec3<f32>(1.6, 0.26, 0.04) * heat * exp(-max(f.z - wc, 0.0) / 2.4) * (1.0 - cutv);
    }
    // ---- the cracks while still thin -----------------------------------------------------------------------------
    c = vm_hair(c, f.z, rr, pw);
    return c;
}
// A thin crack over what lies at rest radius r: `d` from its line, `pw` a pixel's size there.
fn vm_hair(c: vec3<f32>, d: f32, r: f32, pw: f32) -> vec3<f32> {
    let w = 0.3 + 0.6 * smoothstep(VC_CRACK, 10.0, vm.t);
    let ww = max(w, pw * 0.7);
    let reach = saturate((vm.front - r * (1.0 + 0.0)) / 30.0);
    let line = (1.0 - smoothstep(0.35 * ww, ww, d)) * reach * min(w / ww, 1.0);
    let hot = 0.6 + 0.4 * smoothstep(VC_CRACK, 12.0, vm.t);
    return mix(c, vec3<f32>(0.02, 0.016, 0.014), line * 0.9) + vec3<f32>(0.9, 0.14, 0.02) * line * line * hot * 0.3;
}

// What vm_surface gives: the picture there and how far off it (under 0: nothing of the mount here).
struct VmHit {
    c: vec3<f32>,
    t: f32,
}
var<private> vm_seed: f32 = -1.0;  // fs_join's start, from the half-size stage (under 0: from the eye)
var<private> vm_got: f32 = -2.0;   // the hit fs_join found (-2: not looked yet)
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
    if (t > 0.0 && t < scene_len + 1.5) {
        o.t = t;
        if (stage != 1u) {
            o.c = vm_shade(C, rd, t, l, uv);
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
