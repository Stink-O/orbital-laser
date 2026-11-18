// The Earthquake's world warp (the fork's render.set-warp): every terrain and entity vertex comes through `world_warp`,
// every pixel of the terrain through `world_fragment` (what follows the fragments marker line). mod/build.rs puts
// shaders/earthquake_plates.wgsl before this file. The warp moves the game's own land, trees, water, buildings and mobs
// with the plate under them, lit and textured as the game draws them; lib.rs keeps it on only from EQ_WARP_START to
// rest (to EQ_BACK_END with the terrain left alone; with it on the game culls nothing).
//
// The warp can't read mod_data: the mod puts what it needs into the sixteen params (strike/earthquake.rs's `eq_params`;
// globals.warp[0..4] are params 0-15):
//   params[0]   the main fault's direction as two integers about 256 long, packed: (fx + 512) * 1024 + (fz + 512)
//   params[2]   the zone's reach, blocks (0: nothing moves, as while the warp is built ahead)
//   params[3]   the strike's clock (whole ticks; the partial tick is globals.warp[4].w)
//   params[4-5] the target block's middle, x and z; params[11] its y (the land is one over it)
//   params[6]   the knob `pace`
//   params[8]   the strike's seed
//   params[10]  the knobs `slip` and `heave` in hundredths, packed: slip * 1000 + heave
//   params[12]  the fault coordinates' origin (u0, v0), whole blocks, packed: (u0 + 512) * 1024 + (v0 + 512)
//   params[13]  the plate the player stands on + 1 (0: none), and in half its fraction how far it is kept from rocking
//   params[14]  the plate they stood on before, the same (its rock let back in while the view eases off it)
//   params[15]  the flags; a quarter in its fraction when the plates rest displaced (the real land is moved)
//
// The trees that fall (strike/eq_trees.rs) come in `globals.warp_data` (render.set-warp-data, `eq_tree_data`): [0] their
// count and a circle round all of them (x, z from the origin, radius), then two vec4 a tree: (the hinge block x, y, z
// from the origin, the second it starts to fall), (the crown box's reach toward -x and -z packed (x + 16 z), toward +x
// and +z the same, the way it falls + 4 x its plate, the crown's top block over the hinge). lib.rs has the game draw the
// sections near them again as copy 1 (render.warp-on's copies).
//
// A vertex outside the zone stays where it is; inside it, it moves rigidly with its plate (eq_disp).
// The faults are cut open for real before anything moves (terrain on: strike/eq_land.rs), so every plate has its own
// walls; the only faces with vertices on two plates are the cut's floor far down (and, with the terrain left alone, the
// boundaries themselves). `world_fragment` finds those by the stretch itself and paints them as darkness, a faint ember
// light deep in the main fault, so a gap between plates is never see-through and never a smeared texture.

fn eq_warp_cfg() -> EqCfg {
    let w = globals.warp;
    let fp = u32(max(w[0].x, 0.0) + 0.5);
    let fi = vec2<i32>(i32(fp / 1024u) - 512, i32(fp % 1024u) - 512);
    let fl = max(length(vec2<f32>(fi)), 1.0);
    let kn = u32(max(w[2].z, 0.0) + 0.5);
    let sh = u32(max(w[3].x, 0.0) + 0.5);
    var c: EqCfg;
    c.seed = u32(max(w[2].x, 0.0) + 0.5);
    c.reach = w[0].z;
    c.pace = w[1].z;
    c.fdir = vec2<f32>(fi) / fl;
    c.fi = fi;
    c.slip_q = i32(kn / 1000u);
    c.heave_q = i32(kn % 1000u);
    c.rest = fract(w[3].w) > 0.2;
    c.rider = i32(floor(w[3].y + 0.001)) - 1;
    c.rider_k = clamp(fract(w[3].y + 0.001) * 2.0, 0.0, 1.0);
    c.prev = i32(floor(w[3].z + 0.001)) - 1;
    c.prev_k = clamp(fract(w[3].z + 0.001) * 2.0, 0.0, 1.0);
    c.shift = vec2<f32>(f32(i32(sh / 1024u) - 512), f32(i32(sh % 1024u) - 512));
    return c;
}
// The target block's corner (the land one over it), from the camera.
fn eq_warp_origin() -> vec3<f32> {
    let w = globals.warp;
    return (vec3<f32>(w[1].x - 0.5, w[2].w + 1.0, w[1].y - 0.5) - w[4].xyz) - w[5].xyz;
}
// Whether world height y is the surface of the lake's lava (params[7]: its top block's y + 1024, 0 none; a fluid's
// surface is drawn a little under its block's top).
fn eq_lake_surface(y: f32) -> bool {
    let l = globals.warp[1].w;
    return l > 0.5 && abs(y - (l - 1024.0 + 0.89)) < 0.1;
}
// How crusted the lake's lava is over the block at p (level, from the origin): strike/earthquake.rs's `EqPlates::crust`.
const EQ_CRUST: f32 = 0.6;
const EQ_CRUST_RIM: f32 = 0.04;
fn eq_crust(seed: u32, p: vec2<f32>) -> f32 {
    let q = floor(p) + 0.5;
    return eq_vn(seed, q * (1.0 / 11.0), 61u) + 0.35 * (eq_vn(seed, q * 0.25, 62u) - 0.5);
}
fn eq_warp_t() -> f32 {
    let w = globals.warp;
    return w[0].w + w[4].w * 0.05;
}
// ---- the trees that fall --------------------------------------------------------------------------------------------
const EQ_TREE_FALL: f32 = 0.9;       // a fall's length, seconds
const EQ_TREE_A: f32 = 0.82;         // the share of it before the crown hits the land
const EQ_TREE_BOUNCE: f32 = 0.05;    // how far it bounces back, of the quarter turn
// How far through its quarter turn a tree is, u of the way through its fall: slow, then fast, a small bounce.
fn eq_tree_turn(u: f32) -> f32 {
    if (u <= 0.0) {
        return 0.0;
    }
    if (u >= 1.0) {
        return 1.0;
    }
    if (u < EQ_TREE_A) {
        let s = u / EQ_TREE_A;
        return s * s * (0.35 + 0.65 * s);
    }
    return 1.0 - EQ_TREE_BOUNCE * sin(EQ_PI * (u - EQ_TREE_A) / (1.0 - EQ_TREE_A));
}
// A tree, from the origin: its hinge block, when it starts to fall, its crown's box (lo to hi, corners), the way it falls.
struct EqTree {
    h: vec3<f32>,
    t0: f32,
    lo: vec3<f32>,
    hi: vec3<f32>,
    e: vec2<f32>,
    plate: i32,
}
fn eq_trees_n() -> i32 {
    return i32(clamp(globals.warp_data[0].x, 0.0, 4095.0) + 0.5) % 64;
}
// ---- the slabs of the lip that come away (strike/eq_trees.rs's EqSlab) ------------------------------------------------
// After the trees in the data, two vec4 each: (the box's first column x, z and its last, from the origin), (its lowest
// block's y, the second it starts to lean, the way it leans + 4 x its plate + 128 x the most it leans in degrees, how far
// it drops).
const EQ_SLAB_T: f32 = 2.4;          // how long it takes to lean over and go under, seconds
struct EqSlab {
    lo: vec3<f32>,
    hi: vec3<f32>,
    t0: f32,
    e: vec2<f32>,
    plate: i32,
    amax: f32,
    fall: f32,
}
fn eq_slabs_n() -> i32 {
    return i32(clamp(globals.warp_data[0].x, 0.0, 4095.0) + 0.5) / 64;
}
fn eq_slab(j: i32) -> EqSlab {
    let k = 1 + 2 * eq_trees_n() + 2 * j;
    let a = globals.warp_data[k];
    let b = globals.warp_data[k + 1];
    let dp = u32(max(b.z, 0.0) + 0.5);
    var s: EqSlab;
    s.lo = vec3<f32>(a.x, b.x, a.y);
    s.hi = vec3<f32>(a.z + 1.0, 1.0e6, a.w + 1.0);
    s.t0 = b.y;
    let d = dp % 4u;
    s.e = select(select(vec2<f32>(0.0, 1.0), vec2<f32>(0.0, -1.0), d == 3u), select(vec2<f32>(1.0, 0.0), vec2<f32>(-1.0, 0.0), d == 1u), d < 2u);
    s.plate = i32((dp / 4u) % 32u);
    s.amax = f32(dp / 128u) * (EQ_PI / 180.0);
    s.fall = b.w;
    return s;
}
// Whether the point p (from the origin) is clear of slab j's columns (told before it is unpacked).
fn eq_slab_far(j: i32, p: vec3<f32>) -> bool {
    let a = globals.warp_data[1 + 2 * eq_trees_n() + 2 * j];
    return p.x < a.x - 1.0 || p.x > a.z + 2.0 || p.z < a.y - 1.0 || p.z > a.w + 2.0;
}
// Whether the point p lies in slab s or on it; whether block b (its corner) is one of its blocks.
fn eq_slab_vertex_in(s: EqSlab, p: vec3<f32>) -> bool {
    return all(p >= s.lo - 0.001) && p.x <= s.hi.x + 0.001 && p.z <= s.hi.z + 0.001;
}
fn eq_slab_block_in(s: EqSlab, b: vec3<f32>) -> bool {
    return b.x >= s.lo.x && b.x < s.hi.x && b.z >= s.lo.z && b.z < s.hi.z && b.y >= s.lo.y;
}
// The point p of slab s at t: leant about its foot's edge on the side it goes to (slow, then fast), and dropped.
fn eq_slab_move(s: EqSlab, p: vec3<f32>, t: f32) -> vec3<f32> {
    let u = (t - s.t0) / EQ_SLAB_T;
    let k = clamp(u / 0.65, 0.0, 1.0);
    let ang = s.amax * k * k * (0.4 + 0.6 * k);
    let q = clamp((u - 0.2) / 0.8, 0.0, 1.0);
    let c = vec3<f32>(select(s.lo.x, s.hi.x, s.e.x > 0.0), s.lo.y, select(s.lo.z, s.hi.z, s.e.y > 0.0));
    let d = p - c;
    let along = d.x * s.e.x + d.z * s.e.y;
    let side = d.xz - along * s.e;
    let sn = sin(ang);
    let cs = cos(ang);
    let na = cs * along + sn * d.y;
    let ny = -sn * along + cs * d.y;
    return c + vec3<f32>(side.x + na * s.e.x, ny - s.fall * q * q, side.y + na * s.e.y);
}
// The slab whose block b (from the origin) is, once it has begun to go at t; none: -1.
fn eq_slab_falling(b: vec3<f32>, t: f32) -> i32 {
    let m = eq_slabs_n();
    for (var j = 0; j < m; j = j + 1) {
        if (eq_slab_far(j, b)) {
            continue;
        }
        let s = eq_slab(j);
        if (t >= s.t0 && eq_slab_block_in(s, b)) {
            return j;
        }
    }
    return -1;
}
// Whether the point p (from the origin) may lie near a tree: in the circle round all of them, standing and lying.
fn eq_trees_near(p: vec3<f32>) -> bool {
    let d = globals.warp_data[0];
    return length(p.xz - d.yz) <= d.w;
}
// Whether the point p (from the origin) may lie near a tree: in the circle round the trees alone (the last vec4).
fn eq_trees_close(p: vec3<f32>) -> bool {
    let d = globals.warp_data[63];
    return d.z > 0.0 && length(p.xz - d.xy) <= d.z;
}
fn eq_tree(j: i32) -> EqTree {
    let a = globals.warp_data[1 + 2 * j];
    let b = globals.warp_data[2 + 2 * j];
    let lo = u32(max(b.x, 0.0) + 0.5);
    let hi = u32(max(b.y, 0.0) + 0.5);
    let dp = u32(max(b.z, 0.0) + 0.5);
    var t: EqTree;
    t.h = a.xyz;
    t.t0 = a.w;
    t.lo = vec3<f32>(a.x - f32(lo % 16u), a.y + 2.0, a.z - f32(lo / 16u));
    t.hi = vec3<f32>(a.x + f32(hi % 16u) + 1.0, a.y + b.w + 1.0, a.z + f32(hi / 16u) + 1.0);
    let d = dp % 4u;
    t.e = select(select(vec2<f32>(0.0, 1.0), vec2<f32>(0.0, -1.0), d == 3u), select(vec2<f32>(1.0, 0.0), vec2<f32>(-1.0, 0.0), d == 1u), d < 2u);
    t.plate = i32(dp / 4u);
    return t;
}
// Whether the point p (from the origin) is too far from tree j's trunk to be of it, standing or lying, or in its shade
// (a crown reaches 7 from its trunk at most and lies 19 along the land at most): most trees, told before they are unpacked.
fn eq_tree_far(j: i32, p: vec3<f32>) -> bool {
    let d = abs(p.xz - globals.warp_data[1 + 2 * j].xz);
    return max(d.x, d.y) > 24.0;
}
// Whether the point p (from the origin) lies in tree t's box or on it: its trunk's two lowest cells, its crown's box.
fn eq_tree_vertex_in(t: EqTree, p: vec3<f32>) -> bool {
    let crown = all(p >= t.lo - 0.001) && all(p <= t.hi + 0.001);
    let trunk = all(p >= t.h - 0.001) && all(p <= t.h + vec3<f32>(1.0, 2.0, 1.0) + 0.001);
    return crown || trunk;
}
// Whether block b (its corner, from the origin) is in tree t's box.
fn eq_tree_block_in(t: EqTree, b: vec3<f32>) -> bool {
    let crown = all(b >= t.lo) && all(b < t.hi);
    let trunk = b.x == t.h.x && b.z == t.h.z && b.y >= t.h.y && b.y <= t.h.y + 1.0;
    return crown || trunk;
}
// The point p (from the origin) turned by a radians of tree t's fall about its hinge's middle.
fn eq_tree_rot(t: EqTree, p: vec3<f32>, a: f32) -> vec3<f32> {
    let c = t.h + 0.5;
    let d = p - c;
    let along = d.x * t.e.x + d.z * t.e.y;
    let side = d.xz - along * t.e;
    let s = sin(a);
    let k = cos(a);
    let na = k * along + s * d.y;
    let ny = -s * along + k * d.y;
    return c + vec3<f32>(side.x + na * t.e.x, ny, side.y + na * t.e.y);
}
// The tree whose box, begun to fall at t, block b (from the origin) lies in; none: -1.
fn eq_tree_falling(b: vec3<f32>, t: f32) -> i32 {
    let n = eq_trees_n();
    for (var j = 0; j < n; j = j + 1) {
        if (eq_tree_far(j, b)) {
            continue;
        }
        let tr = eq_tree(j);
        if (t >= tr.t0 && eq_tree_block_in(tr, b)) {
            return j;
        }
    }
    return -1;
}
// How far a tree has come down over block b (from the origin) at t, 0 to 1: b under its box where it stood, or a block
// beside that. What stood in its shade is lit as under the open sky by then (`eq_tree_lit`).
fn eq_tree_bared(b: vec3<f32>, t: f32) -> f32 {
    let n = eq_trees_n();
    var k = 0.0;
    for (var j = 0; j < n; j = j + 1) {
        if (eq_tree_far(j, b)) {
            continue;
        }
        let tr = eq_tree(j);
        if (t >= tr.t0 && all(b.xz >= tr.lo.xz - 1.0) && all(b.xz < tr.hi.xz + 1.0) && b.y < tr.hi.y + 1.0) {
            k = max(k, clamp((t - tr.t0) / (EQ_TREE_A * EQ_TREE_FALL), 0.0, 1.0));
        }
    }
    return k;
}
// Whether block b (from the origin) is under a tree's crown that has begun to fall at t, as far as EQ_TREE_HUNG under its
// hinge: the vines that hung from it there go with it (strike/eq_trees.rs's `eq_tree_edits`).
const EQ_TREE_HUNG: f32 = 6.0;
fn eq_tree_under(b: vec3<f32>, t: f32) -> bool {
    let n = eq_trees_n();
    for (var j = 0; j < n; j = j + 1) {
        if (eq_tree_far(j, b)) {
            continue;
        }
        let tr = eq_tree(j);
        if (t >= tr.t0 && all(b.xz >= tr.lo.xz) && all(b.xz < tr.hi.xz) && b.y < tr.lo.y && b.y >= tr.h.y - EQ_TREE_HUNG) {
            return true;
        }
    }
    return false;
}
// The game's shade of a face by the way it faces (up 1, down 0.5, across z 0.8, across x 0.6).
fn eq_face_shade(n: vec3<f32>) -> f32 {
    return 0.6 * n.x * n.x + 0.8 * n.z * n.z + select(0.5, 1.0, n.y > 0.0) * n.y * n.y;
}
// Whether block b (from the origin) is where a tree lies that has come down at t: a cell its box turns onto, or the one
// over one. The plants there are gone from the land at rest (strike/eq_trees.rs's `eq_tree_edits`), so their pixels are
// left out from EQ_TREE_DOWN of the fall on.
const EQ_TREE_DOWN: f32 = 0.7;
// The sky light a face bared by a fallen tree, or of one, has at least (0 to 15).
const EQ_TREE_SKY: f32 = 13.0;
fn eq_tree_lain(b: vec3<f32>, t: f32) -> bool {
    let n = eq_trees_n();
    let m = b + 0.5;
    for (var j = 0; j < n; j = j + 1) {
        if (eq_tree_far(j, b)) {
            continue;
        }
        let tr = eq_tree(j);
        if (t < tr.t0 + EQ_TREE_DOWN * EQ_TREE_FALL) {
            continue;
        }
        // (the block of the box that lies there: a quarter turn back, block middle to block middle)
        let u0 = floor(eq_tree_rot(tr, m, -0.5 * EQ_PI));
        let u1 = floor(eq_tree_rot(tr, m - vec3<f32>(0.0, 1.0, 0.0), -0.5 * EQ_PI));
        if (eq_tree_block_in(tr, u0) || eq_tree_block_in(tr, u1)) {
            return true;
        }
    }
    return false;
}
// The eye, from the camera (where the projection's x, y and w all vanish): a face with a vertex there is drawn as a line.
fn eq_eye() -> vec3<f32> {
    let m = globals.view_proj;
    let r0 = vec4<f32>(m[0].x, m[1].x, m[2].x, m[3].x);
    let r1 = vec4<f32>(m[0].y, m[1].y, m[2].y, m[3].y);
    let r3 = vec4<f32>(m[0].w, m[1].w, m[2].w, m[3].w);
    let c0 = cross(r1.xyz, r3.xyz);
    let c1 = cross(r3.xyz, r0.xyz);
    let c2 = cross(r0.xyz, r1.xyz);
    let det = dot(r0.xyz, c0);
    return -(r0.w * c0 + r1.w * c1 + r3.w * c2) / det;
}
// A vertex of the copy: turned with the falling tree whose box holds it, then moved with its plate; any other cut (red
// under 0) and sent to the eye, so the faces it is part of have no area.
fn eq_tree_vertex(pos: vec3<f32>, t: f32, on: bool) -> Warped {
    let cut = Warped(eq_eye(), vec3<f32>(-1.0, 1.0, 1.0));
    let n = eq_trees_n();
    let m = eq_slabs_n();
    if (!on || n + m == 0) {
        return cut;
    }
    let rel = pos - eq_warp_origin();
    let q = round(rel * 16.0) / 16.0;
    if (!eq_trees_near(q)) {
        return cut;
    }
    let close = eq_trees_close(q);
    for (var j = 0; close && j < n; j = j + 1) {
        if (eq_tree_far(j, q)) {
            continue;
        }
        let tr = eq_tree(j);
        if (t >= tr.t0 && eq_tree_vertex_in(tr, q)) {
            let p = eq_tree_rot(tr, q, 0.5 * EQ_PI * eq_tree_turn((t - tr.t0) / EQ_TREE_FALL));
            let c = eq_warp_cfg();
            let d = eq_disp(c, tr.plate, t, eq_uv(c, eq_bent(c, p.xz)));
            return Warped(pos + (p - q) + d, vec3<f32>(1.0));
        }
    }
    // (a slab of the lip: leant and dropped, then moved with its plate as it stood; gone once it is under)
    for (var j = 0; j < m; j = j + 1) {
        if (eq_slab_far(j, q)) {
            continue;
        }
        let sl = eq_slab(j);
        if (t >= sl.t0 && t < sl.t0 + EQ_SLAB_T && eq_slab_vertex_in(sl, q)) {
            let p = eq_slab_move(sl, q, t);
            let c = eq_warp_cfg();
            let d = eq_disp(c, sl.plate, t, eq_uv(c, eq_bent(c, q.xz)));
            return Warped(pos + (p - q) + d, vec3<f32>(1.0));
        }
    }
    return cut;
}

fn world_warp(pos: vec3<f32>, copy: u32) -> Warped {
    let w = globals.warp;
    let reach = w[0].z;
    let t = eq_warp_t();
    let on = !(reach < 1.0 || t < EQ_WARP_START || t >= EQ_BACK_END);
    if (copy > 0u) {
        return eq_tree_vertex(pos, t, on);
    }
    if (!on) {
        return Warped(pos, vec3<f32>(1.0));
    }
    let c = eq_warp_cfg();
    let rel = pos - eq_warp_origin();
    // (outside the stadium the bending can reach: nothing moves)
    let w0 = eq_uv(c, rel.xz);
    if (length(vec2<f32>(max(abs(w0.x) - EQ_CAP * reach, 0.0), w0.y)) > 1.07 * reach + 14.0) {
        return Warped(pos, vec3<f32>(1.0));
    }
    // (on the block grid's sixteenths: the same corner seen from two sections lands on the same plate)
    let q = round(rel.xz * 16.0) / 16.0;
    let qb = eq_bent(c, q);
    let wq = eq_uv(c, qb);
    let pl = eq_cell(c, wq, eq_rim(c, qb)).plate;
    var d = eq_disp(c, pl, t, wq);
    // (the lake in the main fault's trench: its lava's surface keeps its height, so the two halves part with the plates
    // and the faces between them bridge the gap level)
    if (eq_lake_surface(rel.y + w[2].w + 1.0) && abs(wq.y) < 30.0) {
        d.y = 0.0;
    }
    return Warped(pos + d, vec3<f32>(1.0));
}

// [fragments]
// (the game's light map is the terrain shader's alone: this side of the mark is not built into the entities')
// What a face's colour is times when its sky light is `to` at least (the game's light map: its vertices' colour holds
// the light they had).
fn eq_tree_lit(light: vec2<f32>, to: f32) -> vec3<f32> {
    let was = sample_lightmap(light.x, light.y).rgb;
    let now = sample_lightmap(max(light.x, to), light.y).rgb;
    return now / max(was, vec3<f32>(0.04));
}
// How stretched a face must be to be one between two plates (a plate's rock is about 0.03; a face between two plates a
// block apart or more is 1 and up).
const EQ_STRETCH: f32 = 0.8;
// A face stretched between two plates: rock in shade, lit by its own slope, darker the deeper it is drawn under the
// land; in the main fault a lava glow where it is drawn as deep as the real lava lies (by where it really is: within a
// few blocks of the fault).
fn eq_dark(f: Fragment, n: vec3<f32>) -> Painted {
    let w = globals.warp;
    let wp = (f.at + w[4].xyz) + w[5].xyz;
    let depth = (w[2].w + 1.0) - wp.y;
    let sun = normalize(globals.sun.xyz + vec3<f32>(0.0, 1.0e-4, 0.0));
    let sky = clamp(f.light.x / 15.0, 0.0, 1.0);
    let lit = (0.25 + 0.75 * max(dot(n, sun), 0.0)) * (0.3 + 0.7 * sky);
    // (rock in shade, about as the cut's real walls read from afar, so little changes where the real land takes its place)
    var col = vec3<f32>(0.33, 0.33, 0.35) * lit * mix(1.0, 0.4, smoothstep(0.0, 70.0, depth));
    // (the main fault: its home within a few blocks of v = 0, glowing where it is drawn deep)
    let c = eq_warp_cfg();
    let rel = f.home - eq_warp_origin();
    let v = abs(eq_uv(c, eq_bent(c, rel.xz)).y);
    let t = eq_warp_t();
    let flick = 0.85 + 0.15 * sin(t * 3.1 + wp.x * 0.13 + wp.z * 0.11);
    // (only as deep as the real lava lies once the land is in: within a few blocks over the main cut's floor)
    let ember = (1.0 - smoothstep(3.0, 9.0, v)) * (1.0 - smoothstep(-46.0, -38.0, wp.y)) * flick;
    col = col + vec3<f32>(1.0, 0.33, 0.07) * 0.55 * ember;
    return Painted(vec4<f32>(col, 1.0), 1.0 - 0.6 * ember);
}
// The lake's surface: its lava, crusted over in rafts that form as it cools (none as the plates first part, all of them
// by the climax: the rafts the land at rest has as blocks, where they will lie), a rim of magma round each.
fn eq_lake_paint(lava: vec4<f32>, p: vec2<f32>) -> Painted {
    let t = eq_warp_t();
    let grown = smoothstep(6.0, 17.0, t);
    let v = eq_crust(u32(max(globals.warp[2].x, 0.0) + 0.5), p) - (1.0 - grown) * 0.7;
    if (v >= EQ_CRUST) {
        let g = 0.9 + 0.2 * fract(sin(dot(floor(p), vec2<f32>(12.9898, 78.233))) * 43758.5453);
        return Painted(vec4<f32>(vec3<f32>(0.16, 0.145, 0.16) * g, 1.0), 1.0);
    }
    if (v >= EQ_CRUST - EQ_CRUST_RIM) {
        return Painted(vec4<f32>(mix(lava.rgb, vec3<f32>(0.5, 0.2, 0.07), 0.75), 1.0), 1.0);
    }
    return Painted(lava, 1.0);
}
fn world_fragment(f: Fragment) -> Painted {
    // (how much the face is stretched: the change of where it is drawn from where it is across the screen, against the
    // change of where it is; a rigid plate has none. Worked out first, while every pixel of the face still runs.)
    let moved = f.at - f.home;
    let dh = abs(dpdx(moved)) + abs(dpdy(moved));
    let dw = abs(dpdx(f.home)) + abs(dpdy(f.home));
    let stretch = (dh.x + dh.y + dh.z) / max(dw.x + dw.y + dw.z, 1.0e-5);
    let na = cross(dpdx(f.at), dpdy(f.at));
    let n = normalize(na + vec3<f32>(0.0, 1.0e-6, 0.0));
    // (the block this pixel is of: where it really is, stepped a hair into the face's block. The face's normal where it
    // really is turns as it is drawn (the plates move it, a falling tree turns it), so the side of it the face's front is
    // on is the side its drawn normal shows the camera, or the other for a back)
    let nh = cross(dpdx(f.home), dpdy(f.home));
    let out_home = normalize(nh + vec3<f32>(0.0, 1.0e-9, 0.0)) * select(-1.0, 1.0, (dot(na, f.at) < 0.0) == f.front);
    let rel = f.home - eq_warp_origin();
    let blk = floor(rel - 0.02 * out_home);
    let near = eq_trees_near(blk + 0.5);
    let trees = eq_trees_n() > 0 && near && eq_trees_close(blk + 0.5);
    var tree = -1;
    if (trees) {
        tree = eq_tree_falling(blk, eq_warp_t());
    }
    var slab = -1;
    if (tree < 0 && eq_slabs_n() > 0 && near) {
        slab = eq_slab_falling(blk, eq_warp_t());
    }
    let falling = tree >= 0 || slab >= 0;
    // (a plant: the only faces that stand across a block's corners)
    let plant = abs(out_home.x) > 0.3 && abs(out_home.z) > 0.3;
    // (a vine: an upright face that lies inside its block, off the grid's planes; a tree's own faces are all on them)
    let along = dot(rel, abs(out_home));
    let vine = !plant && abs(out_home.y) < 0.3 && abs(along - round(along)) > 0.02;
    if (f.cut > 0.0) {
        return Painted(vec4<f32>(0.0, 0.0, 0.0, -1.0), 1.0);
    }
    // (the copy: only what is in a falling tree's box, turned rigidly, so never a face between two plates, and no plant
    // caught in it; the land itself: what is in one left out, the copy draws it, and the plants where one has come down)
    if (f.copy > 0u) {
        if (!falling || (tree >= 0 && (plant || vine)) || !f.front || (f.light.x < 0.5 && f.light.y < 0.5)) {
            return Painted(vec4<f32>(0.0, 0.0, 0.0, -1.0), 1.0);
        }
        // (a slab of the lip: shaded by the way the face has leant to)
        if (slab >= 0) {
            let sl = eq_slab(slab);
            let o = sl.lo + 0.5;
            let ns = eq_slab_move(sl, o + out_home, eq_warp_t()) - eq_slab_move(sl, o, eq_warp_t());
            let sh = select(eq_face_shade(ns) / eq_face_shade(out_home), 1.0, plant);
            return Painted(sprite(f.uv, f.layer) * f.color * vec4<f32>(vec3<f32>(sh), 1.0), 1.0);
        }
        // (shaded by the way the face has turned to, and lit as in the open as it comes down: what the game makes of it
        // once it lies there as real blocks)
        let tr = eq_tree(tree);
        let u = (eq_warp_t() - tr.t0) / EQ_TREE_FALL;
        let c = tr.h + 0.5;
        let n1 = eq_tree_rot(tr, c + out_home, 0.5 * EQ_PI * eq_tree_turn(u)) - c;
        let shade = eq_face_shade(n1) / eq_face_shade(out_home);
        let lit = mix(vec3<f32>(1.0), eq_tree_lit(f.light, EQ_TREE_SKY), clamp(u / EQ_TREE_A, 0.0, 1.0));
        return Painted(sprite(f.uv, f.layer) * f.color * vec4<f32>(lit * shade, 1.0), 1.0);
    }
    if (falling || ((plant || vine) && trees && eq_tree_lain(blk, eq_warp_t())) || (vine && trees && eq_tree_under(blk, eq_warp_t()))) {
        return Painted(vec4<f32>(0.0, 0.0, 0.0, -1.0), 1.0);
    }
    if (stretch > EQ_STRETCH) {
        // (the lake's lava stretched between the plates: its own texture, tiled by where it is drawn)
        let gw = globals.warp;
        let hy = f.home.y + gw[4].y + gw[5].y;
        if (eq_lake_surface(hy)) {
            let at = (f.at + gw[4].xyz) + gw[5].xyz;
            return eq_lake_paint(sprite(at.xz, f.layer) * f.color, (f.at - eq_warp_origin()).xz);
        }
        // (the lava's sides, drawn where the lake's edge is sealed with a block that draws nothing: their tops keep the
        // lake's height and their feet go with the plate, so they are left out while they are stretched)
        let ll = gw[1].w - 1024.0;
        if (gw[1].w > 0.5 && hy > ll - 1.05 && hy < ll + 0.8) {
            return Painted(vec4<f32>(0.0, 0.0, 0.0, -1.0), 1.0);
        }
        return eq_dark(f, select(-n, n, dot(n, f.at) < 0.0));
    }
    // (the warp's pipelines cull no faces, and the back of a face lies in the plane of another's front: a plant's two
    // sides, two leaf blocks' shared faces, water's underside. Drawn both, they flicker through each other. The plates
    // only shift and rock, nothing is turned over, so a back here is one the game would have left out.)
    if (!f.front) {
        return Painted(vec4<f32>(0.0, 0.0, 0.0, -1.0), 1.0);
    }
    // (the faces no light reaches are kept, unlike the fork's default for a warp: the plates only shift and rock, so the
    // land still hides its caves, and the floor of water over 15 deep has no light either: left out, the caves under a
    // lake showed through it)
    // (what stood in a tree's shade, lit as under the open sky as it comes down)
    if (trees) {
        let bared = eq_tree_bared(blk, eq_warp_t());
        if (bared > 0.0) {
            let lit = mix(vec3<f32>(1.0), eq_tree_lit(f.light, EQ_TREE_SKY), bared);
            return Painted(sprite(f.uv, f.layer) * f.color * vec4<f32>(lit, 1.0), 1.0);
        }
    }
    // (the lake's own surface where it is not stretched: crusted as the stretched part is)
    if (eq_lake_surface(f.home.y + globals.warp[4].y + globals.warp[5].y)) {
        return eq_lake_paint(sprite(f.uv, f.layer) * f.color, (f.at - eq_warp_origin()).xz);
    }
    // (what lay under the lake had no light of the sky: the cliff's foot as it rises out of the lava is lit as in the
    // open, which is what the game makes of it once the land is at rest)
    let gl = globals.warp;
    if (gl[1].w > 0.5 && f.home.y + gl[4].y + gl[5].y < gl[1].w - 1024.0 - 1.5 && f.at.y > f.home.y + 0.5) {
        return Painted(sprite(f.uv, f.layer) * f.color * vec4<f32>(eq_tree_lit(f.light, 15.0), 1.0), 1.0);
    }
    return Painted(sprite(f.uv, f.layer) * f.color, 1.0);
}
