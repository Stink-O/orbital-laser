// [lean pass] (mod/src/passbuild.rs: the game's pass goes in without its comment and blank lines)
// The Colossi's own post pass (appended to strike.wgsl up to its fs_main, as the other lasers' are): five stone giants
// standing in a ring round the target, each with its hammer, ray-traced as triangle meshes. The meshes are the Tripo
// models decimated by the converter's display-mesh export (`.m2md`, ~8,000 triangles a giant, ~3,000 the hammer), cut by
// tools/colossi_rig.py into 13 rigid bone pieces a giant (a BVH each, one colour a triangle, an emissive byte for the green
// cracks) and read from `mod_data` (render.set-data). Two giant designs and one hammer are instanced five times; the
// instances are the table below, written for each strike by strike/colossi.rs.
//
// A giant is a skeleton of rigid pieces (`cl_pose`, `cl_rig`): pelvis, torso, head, two arms (upper arm, forearm and fist),
// two legs (thigh, shin, foot), chained from the pelvis about the joints in the design's rig (15 joints, from one table: tools/
// colossi_rig.py or colossi.json's `rig`). The legs are solved by two-bone IK so the feet stay planted wherever the
// pelvis goes (`cl_leg`); the hammer is held in the closed right fist (the forearm's piece carries it). Where an arm turns a
// ball (a sphere in the pass, a bone's `ball`) closes the seam; at the others two pieces overlap a little.
//
// The strike (strike/colossi.rs keeps the same times): the giants stand 300 out, spread round the target as the Planet
// Killer's towers are. 0-7.5 s they heave themselves out of the earth (`cl_rise`: in heaves, never one glide), green cracks
// spreading through the land round each as it comes and dust boiling off it. Each then plants a foot (a stamp, a dust
// ring: `cl_stomps`), takes the hammer in both hands, heaves it up over its shoulder, hangs there, and brings it down in
// front of itself in a deep squat, the torso folded over it (first blows 11 s + 0.6 s a giant, word 10): a flash, a
// green cracked glow through the land from where the head lands (`cl_ground`), dust thrown up (`cl_earth`), the giant's own
// cracks flaring. They lift the hammers back and at 18 s bring them down again all five at once (word 23). 18-20 s a green
// beam comes straight down the middle; at 20 s it explodes: a wave runs out from the middle at 240 blocks a second and cuts
// the hammers away and each giant where its seeded damage says (the converter's own function, docs/damage.md, so the
// blocks left standing are what this cuts), the edges hot green and cooling, the giants rocked back by it. From 20.9 s the
// light climbs each hammer and the arms holding it (`cl_chain`), and at 22.4 s + 0.15 s a giant they burst (`cl_tb`; word 47
// says which arm pieces go with the hammer: the statues are made without them), fireballs, boulders (`cl_debris`) and dust
// off each; the giants settle to the pose the statues have (by 26.6 s). The earth each heaved up as it rose and dragged
// up its feet is a heap of blocks (`cl_mound`; with the terrain on strike/colossi.rs's `Heave` heaps the same on the real land as it rises, and only
// what lies in the crater is drawn here). From 27 s a glowing line sweeps down each giant and what is
// above it is blocks (the mod places them as the line passes: strike/colossi.rs) until the display mesh is gone at 36 s.
//
// `mod_data` layout (words; keep in step with tools/colossi_rig.py (layout), tools/colossi_assets.py and strike/colossi.rs):
//   0 magic 0xC0105510, 1 meshes (27), 2 giants (5), 3 flags (bit 0 damage cuts, bit 1 the giants' shadows on the land),
//   4 and 5 the ground's height at the target
//   16 + 16 m  mesh m's header (giant design d's bone b is mesh 13 d + b, the hammer 26): node_off, tri_off, triangles, vert_off,
//              the piece's box (corner xyz, size xyz), the piece's pivot xyz (the hammer: its grip) in the design's mesh space,
//              radius, ball radius, ball rgb
//   448 + 96 d design d's rig: 15 joints xyz (pelvis, spine, neck, r_shoulder, r_elbow, r_wrist, l_shoulder, l_elbow, l_wrist, r_hip,
//              r_knee, r_ankle, l_hip, l_knee, l_ankle: mesh units, 50 a giant's height), then word 45: the farthest vertex from the pelvis
//   640 + 64 g giant g: design, mirror (f32 +-1), scale (its height / 50), yaw (radians, the converter's), p0 xyz (where the
//              mesh's origin is over the world, x and z from the target block's middle), seed (u32), glow, t_rise, first impact,
//              t_sweep, grid X Y Z (f32), cuts (u32), size, rough, ymin, ymax, b xyz (the grid offset) [words 0-22], then
//              the second impact (all five at once), swing seconds, variation (0-1) [23-25], the pose's own words
//              [26-43; 36 the hammer's scale over the giant's], then where its hammer's head lands on the land, xyz in
//              the world [44-46], then the pieces that burst with its hammer (bit k piece k) [47]
//   1024 ..    the meshes, each its nodes, its triangles and its vertices: a node is 3 words (its box's min and max corners as
//              three 10-bit coordinates in the piece's box packed to a word each; then a leaf's triangle count in the top four
//              bits over its first triangle, or 0 over the left child: the right is the next node); a triangle 2 words (three
//              vertex numbers, 16 bits each); a vertex 3 words (its position packed as the corners are; its normal, octahedral,
//              12 bits each, under how open it is to the sky around it (baked ambient occlusion), 8 bits; its rgb under the
//              converter's glow byte: how much greener than stone the model's texture is there, the cracks).

const CL_MESH: u32 = 16u;
const CL_RIG: u32 = 448u;
const CL_RIGS: u32 = 96u;
const CL_INST: u32 = 640u;
const CL_REC: u32 = 64u;
const CL_SETTLE: f32 = 24.3;
const CL_FRONT: vec3<f32> = vec3<f32>(1.0, 0.0, 5.3);  // where the foot that does not kneel goes from its ankle at rest, the right (the left's x the other way, in under the body; colossi_pose.FRONT)     // by when every giant holds its statue's crouch (strike/colossi.rs's STATUE_AT goes after)
const CL_NG: u32 = 5u;
const CL_NB: u32 = 13u;           // bone pieces a giant
const CL_NP: u32 = 14u;           // pieces a giant and its hammer
const CL_BIG: f32 = 1.0e30;
const CL_HIT: f32 = 20.0;         // it reaches the ground; everything goes
const CL_K: f32 = 4.4;            // how much bigger than the first design's 50 blocks they stand (about 220: the most a statue can be)
const CL_WAVE: f32 = 240.0;       // blocks a second, the blast's front (CL_K times 55)
const CL_SWEEP: f32 = 4.5;        // seconds the converting line takes down a giant
const CL_RISE: f32 = 6.5;         // seconds a giant takes to come up out of the earth
const CL_CHARGE: f32 = 20.9;      // the blast's light, come back along the cracks, starts up each hammer (colossi.rs's CHARGE)
const CL_BURST: f32 = 22.4;       // the first giant's hammer and arms burst (BURST), each later giant 0.15 s after (BURST_STEP)
const CL_CRATER: f32 = 36.0 * CL_K; // the crater's radius (the plan's CRATER_R)
const CL_RELAX1: f32 = 24.9;      // they have drawn themselves up into the statues' pose
const CL_BURY: f32 = 9.0;         // blocks a giant's soles are under its ground (colossi.rs's BURY)
const CL_HL: f32 = 25.0;
const CL_HV_COL: u32 = 1008u;     // each giant's torn land's colours: its surface's, what is under it (0xAABBGGRR sRGB, A 255 once known; strike/colossi.rs's HV_COL)          // the hammer's mesh: from where the bottom hand holds it to the middle of its head

fn cl_f(i: u32) -> f32 { return bitcast<f32>(mod_data[i]); }
fn cl_v3(i: u32) -> vec3<f32> { return vec3<f32>(cl_f(i), cl_f(i + 1u), cl_f(i + 2u)); }

fn cl_ry(a: f32) -> mat3x3<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat3x3<f32>(vec3<f32>(c, 0.0, -s), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(s, 0.0, c));
}
fn cl_rx(a: f32) -> mat3x3<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat3x3<f32>(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, c, s), vec3<f32>(0.0, -s, c));
}
fn cl_rz(a: f32) -> mat3x3<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat3x3<f32>(vec3<f32>(c, s, 0.0), vec3<f32>(-s, c, 0.0), vec3<f32>(0.0, 0.0, 1.0));
}
// The rotation that carries unit vector a onto unit vector b by the shortest way.
fn cl_arc(a: vec3<f32>, b: vec3<f32>) -> mat3x3<f32> {
    let c = dot(a, b);
    let v = cross(a, b);
    let k = 1.0 / max(1.0 + c, 1.0e-3);
    let vx = mat3x3<f32>(vec3<f32>(0.0, v.z, -v.y), vec3<f32>(-v.z, 0.0, v.x), vec3<f32>(v.y, -v.x, 0.0));
    return mat3x3<f32>(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 0.0, 1.0)) + vx + (vx * vx) * k;
}

struct ClInst {
    r: mat3x3<f32>,   // local to world (orthonormal; a mirror has det -1)
    p: vec3<f32>,
    s: f32,
    mesh: u32,
    kind: u32,        // 0 a giant's piece, 1 the hammer
    g: u32,           // which giant (a hammer's too)
    c: vec3<f32>,     // bounding sphere
    rad: f32,
}

fn cl_a(g: u32) -> mat3x3<f32> {
    let b = CL_INST + CL_REC * g;
    return mat3x3<f32>(vec3<f32>(cl_f(b + 1u), 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 0.0, 1.0)) * cl_ry(cl_f(b + 3u));
}

fn cl_j(d: u32, n: u32) -> vec3<f32> { return cl_v3(CL_RIG + CL_RIGS * d + 3u * n); }

// When giant g's hammer and arms burst, and which of its pieces go with them (bit k piece k; the hammer always).
fn cl_tb(g: u32) -> f32 { return CL_BURST + 0.15 * f32(g); }
fn cl_mask(g: u32) -> u32 { return mod_data[CL_INST + CL_REC * g + 47u] | 0x2000u; }
fn cl_gone(g: u32, k: u32, t: f32) -> bool {
    return t > cl_tb(g) + 0.45 && ((cl_mask(g) >> k) & 1u) == 1u;
}
// a blow's kick: sharp, then let go over a couple of seconds
// A heavy body's answer to a shove at x = 0: it gives smoothly, furthest at 1 / w seconds, and comes back (a critically damped
// spring's impulse response, peak 1), never a snap in one frame.
fn cl_imp(x: f32, w: f32) -> f32 {
    return select(0.0, w * x * exp(1.0 - w * x), x > 0.0);
}

// ---- the pose: what a giant's joints and its hammer are doing at strike time t --------------------------------------------------
// (angles in radians; lengths in mesh units, a giant's height 50. Every angle is a turn of the joint from the mesh's own pose,
// the pose the statue has: all zero. The hammer is placed in the giant's mesh space and both hands go to it by IK.)
struct ClP {
    fu: f32,       // how far the front leg's knee is bent up (its pole forward and up)
    kn: f32,       // how far the kneeling leg kneels (its foot turned back along the ground)
    dy: f32,       // pelvis drop (knees bend: the feet stay put)
    dz: f32,       // pelvis shift forward
    pyaw: f32,     // pelvis turn (negative takes the right side back)
    ppitch: f32,   // pelvis bend forward
    proll: f32,
    syaw: f32,     // the torso's turn on the pelvis
    spitch: f32,   // the torso's bend forward on the pelvis
    sroll: f32,
    hyaw: f32,
    hpitch: f32,
    hb: vec3<f32>, // the hammer: where the bottom (left) hand holds its handle
    hu: vec3<f32>, // its handle's direction, from that hand to the head
    he: vec3<f32>, // its head's long axis (the striking faces)
    sl: f32,       // how far up the handle the right hand is
    hold: f32,     // 1 the hands are on the hammer, 0 the statue's arms
    px: f32,       // pelvis shift sideways (the weight over the foot that stays down)
    lf: vec3<f32>, // the left ankle, from where the statue's is (a step: out, up, forward)
    rf: vec3<f32>, // the right ankle
    act: f32,      // how hard the joints are working (their seams glow, dust falls)
    arc: f32,      // mid-swing: the hands are kept out at arm's length from the chest (the hammer comes round, not through)
}
struct ClH {
    b: vec3<f32>,
    th: f32,
    ps: f32,
    sl: f32,
}

fn cl_pt(a: f32, b: f32, x: f32) -> f32 { return smoothstep(a, b, x); }
// a heavy thing's spring after it is stopped: overshoot and settle (about a second's period, gone in 2.5 s)
fn cl_spring(dt: f32) -> f32 {
    return select(0.0, exp(-2.7 * dt) * sin(6.0 * dt), dt > 0.0);
}
// stone grinding on stone: a slow move goes in n catches, each sticking and then giving (0 and 1 stay put)
fn cl_grind(p: f32, n: f32) -> f32 {
    let x = p * n;
    return mix(p, (floor(x) + smoothstep(0.3, 1.0, fract(x))) / n, 0.55);
}

// The hammer with its head on the ground: gr 0 at rest in front of the feet (the handle steep), 1 driven in at the slam's
// place `sm` (the handle nearly level). `kick` lifts the handle a little (the rebound).
// A heavy foot's step, k 0..1: x how far along it is (eased), y how high (a slow lift, then dropped: it stamps).
fn cl_step(k: f32) -> vec2<f32> {
    return vec2<f32>(smoothstep(0.0, 0.85, k), sin(3.14159 * pow(k, 1.7)));
}
// When giant g's feet come down: x the left's stamp forward before its first heave, y the right's back before the second.
// (each giant's wind-up its own length: words 26 and 27, `leads` in strike/colossi.rs)
fn cl_stomps(g: u32) -> vec2<f32> {
    let b = CL_INST + CL_REC * g;
    return vec2<f32>(cl_f(b + 10u) - 3.2 * cl_f(b + 26u), cl_f(b + 23u) - 3.2 * cl_f(b + 27u));
}
// The earth lets a giant go in heaves: how far up it has come, 0 to 1.
fn cl_rise(g: u32, t: f32) -> f32 {
    return cl_grind(smoothstep(0.0, CL_RISE, t - cl_f(CL_INST + CL_REC * g + 9u)), 5.0);
}

fn cl_hground(gr: f32, kick: f32, jp: vec3<f32>, sm: vec3<f32>, gy0: f32, hsr: f32) -> ClH {
    var o: ClH;
    o.th = mix(-0.70, -0.12, gr) + kick;
    let hz = mix(jp.z + 26.5, sm.z, gr);
    let hx = mix(jp.x, sm.x, gr);
    let gy = mix(gy0, sm.y, clamp((hz - jp.z) / max(sm.z - jp.z, 1.0), 0.0, 1.0));
    let hy = gy + hsr * (9.25 * abs(cos(o.th)) + 6.0 * abs(sin(o.th))) - mix(1.2, 3.0, gr);
    o.b = vec3<f32>(hx, hy, hz) - CL_HL * hsr * vec3<f32>(0.0, sin(o.th), cos(o.th));
    o.ps = 0.0;
    o.sl = mix(8.0, 4.0, gr);
    return o;
}

// A slow drift that never repeats (three sines at odd rates), -1..1: the small life in a joint that keeps a pose from
// looking held.
fn cl_nz(t: f32, s: f32) -> f32 {
    return 0.5 * sin(t * 0.37 + s) + 0.3 * sin(t * 0.83 + s * 2.3) + 0.2 * sin(t * 1.71 + s * 4.1);
}
// Where a head looks while it waits: a new way every few seconds (its own rhythm), turned to heavily, held, -1..1.
fn cl_look(t: f32, s: f32, per: f32) -> f32 {
    let x = (t + s * 1.7) / per;
    let k = floor(x);
    let a = fract(sin(k * 12.9898 + s * 78.233) * 43758.547) * 2.0 - 1.0;
    let c = fract(sin((k + 1.0) * 12.9898 + s * 78.233) * 43758.547) * 2.0 - 1.0;
    return mix(a, c, smoothstep(0.62, 1.0, fract(x)));
}

fn cl_pose(g: u32, t: f32, jp: vec3<f32>, sm: vec3<f32>, gy0: f32, hsr: f32) -> ClP {
    let b = CL_INST + CL_REC * g;
    let t_rise = cl_f(b + 9u);
    let t1 = cl_f(b + 10u);
    let t2 = cl_f(b + 23u);
    let v = cl_f(b + 25u);
    // its character (`CHARACTER` in strike/colossi.rs): the wind-up's scale before each blow, crouch, arch, twist,
    // posture, head turned, restlessness, reaction
    let crouch = cl_f(b + 28u);
    let arch = cl_f(b + 29u);
    let twist = cl_f(b + 30u);
    let post = cl_f(b + 31u);
    let hbias = cl_f(b + 32u);
    let rest = cl_f(b + 33u);
    let react = cl_f(b + 34u);
    var o: ClP;
    // which slam this is: the first (from the hammer at rest) or the one all five make together (from where the first left it)
    let second = t > max(t2 - 3.75 * cl_f(b + 27u), t1);
    let ti = select(t1, t2, second);
    let ld = cl_f(b + select(26u, 27u, second));
    // (the swing as long as the wind-up leaves room for, its press up over the shoulder kept: never quicker than 1.15 s)
    let sw = min(cl_f(b + 24u), max(1.4 * ld, 1.15));
    let g0 = select(0.0, 1.0, second);
    let pre = t < ti;
    let dt = t - select(t1, t2, t >= t2);          // since the last blow landed (negative before the first)
    // the heave, the way a man does it: the weight gathered over the hammer and the top hand slid down to its head (prep), it is
    // hauled off the ground to the chest by the legs, the back leaning against it (a), caught there with a dip of the knees
    // (cat), pressed up over the right shoulder (bq), hung back there, the body arched under it (hang), and swung (s)
    let prep = cl_pt(ti - 3.75 * ld, ti - 3.15 * ld, t) * (1.0 - cl_pt(ti - 3.15 * ld, ti - 2.45 * ld, t));
    let ar = select(1.0, cl_pt(ti - 3.20 * ld, ti - 2.15 * ld, t), pre);
    let a = cl_grind(ar, 4.0);
    let cat = cl_pt(ti - 2.50 * ld, ti - 2.15 * ld, t) * (1.0 - cl_pt(ti - 2.10 * ld, ti - 1.70 * ld, t));
    let br = select(1.0, cl_pt(ti - 2.15 * ld, ti - max(1.40 * ld, sw + 0.1), t), pre);
    let bq = cl_grind(br, 3.0);
    let hang = select(1.0, cl_pt(ti - max(1.50 * ld, sw + 0.05), ti - sw + 0.25, t), pre);
    let s = clamp((t - (ti - sw)) / sw, 0.0, 1.0);
    let h0 = cl_hground(g0, 0.0, jp, sm, gy0, hsr);
    let kick = select(0.0, 0.07 * sin(min(9.0 * dt, 3.14159)) * exp(-3.0 * dt), dt > 0.0);
    let h1 = cl_hground(1.0, kick, jp, sm, gy0, hsr);
    let bc = vec3<f32>(jp.x - 1.5, jp.y + 8.5, jp.z + 9.5);
    let bt = vec3<f32>(jp.x - 4.0, 46.4 + 0.8 * hang + 3.0 * (arch - 1.0), jp.z + 5.0 - 2.4 * hang - 2.0 * (arch - 1.0));
    let tht = 2.16 + 0.26 * hang + 0.05 * v + 0.25 * (arch - 1.0);
    var hb = mix(mix(h0.b, bc, a), bt, bq);
    hb.z = hb.z + 2.0 * sin(3.14159 * bq);
    var th = mix(mix(h0.th, 0.8, pow(a, 0.85)), tht, bq);
    var ps = (0.35 * twist + 0.2 * (arch - 1.0)) * bq;
    // (the weight caught at the top: it sags, the body under it gives, and both come back)
    let t_top = ti - max(1.40 * ld, sw + 0.1);
    let sag = select(0.0, cl_spring(t - t_top), pre);
    hb.y = hb.y - 2.4 * sag;
    var sl = mix(h0.sl, mix(17.0, 13.0, bq), select(1.0, cl_pt(ti - 3.7 * ld, ti - 3.15 * ld, t), pre));
    // (heavy: it hangs at the top and falls, the most of its way in the last of it)
    let sp = pow(s, 1.9);
    hb = mix(hb, h1.b, pow(s, 2.4));
    th = mix(th, h1.th, pow(s, 2.8));
    ps = ps * (1.0 - sp);
    sl = mix(sl, h1.sl, sp);
    // the body: c how deep it is crouched over the hammer, e how far it is drawn up and arched under it, tw its turn to the
    // right, lb its lean back against the hammer's weight as that comes off the ground
    let cg = mix(0.12, 0.9, g0);
    var c = mix(mix(cg + 0.3 * prep, 0.04, a) + 0.17 * cat * (1.0 - bq), 1.0, pow(s, 2.0));
    let wind = cl_pt(ti - sw - 0.45, ti - sw - 0.05, t) * (1.0 - cl_pt(ti - sw, ti - sw + 0.25, t)) * select(0.0, 1.0, pre);
    var e = (bq + 0.35 * hang + 0.35 * wind) * (1.0 - cl_pt(0.0, 0.6, s));
    var tw = cl_pt(0.2, 1.0, bq) * (1.0 - cl_pt(0.0, 0.7, s));
    e = e * arch;
    tw = tw * twist;
    let lb = sin(3.14159 * ar) * select(0.0, 1.0, pre);
    // the cracks running in to the middle: they lift their heads from their crouch to watch them meet (the quick ones first);
    // the blast rocks them back
    let bmo = 0.9 * (1.0 - react);
    let bm = cl_pt(CL_HIT - 1.5 + bmo, CL_HIT - 0.3 + bmo, t);
    if (!pre) {
        // (after the blow each holds its crouch its own way: the quick ones come up to watch, the heavy stay down)
        c = 0.9 - (0.1 + 0.35 * (react - 0.6)) * bm - 0.18 * (rest - 1.0) * bm;
        e = 0.0;
        tw = 0.0;
    }
    // (the blow's weight goes on down into the knees and comes back)
    let hitk = select(0.0, 1.0, dt > 0.0);
    c = c + hitk * 0.1 * exp(-2.5 * max(dt, 0.0));
    let dip = hitk * (1.0 - exp(-14.0 * max(dt, 0.0))) * exp(-2.4 * max(dt, 0.0));
    let spr = cl_spring(dt);
    c = min(c * crouch, 1.12);
    // the rise: out of a deeper crouch, slouched, the head down, each part grinding up in its turn
    let u = (t - t_rise) / CL_RISE;
    // (each its own way up: the quick get their legs under them first, the hunched lift their heads last)
    let ru = 0.1 * (react - 1.0);
    let leg = cl_grind(cl_pt(0.28 - ru, 0.84 - ru, u), 4.0);
    let tor = cl_grind(cl_pt(0.42 + 0.05 * post, 0.93, u), 3.0 + round(2.0 * rest - 0.5));
    let hd = cl_grind(cl_pt(0.6 + 0.12 * post, 1.02 + 0.06 * post, u), 3.0);
    c = c + 0.4 * (1.0 - leg);
    // (breathing and the sway of the weight, slow: it is huge)
    let ph = t * 1.15 * (0.8 + 0.2 * rest) + f32(g) * 2.1;
    let ph2 = t * 0.57 * (0.75 + 0.25 * rest) + f32(g) * 1.3;
    let uc = clamp(u, 0.0, 1.0);
    o.act = saturate(max(max(4.0 * uc * (1.0 - uc), 4.0 * ar * (1.0 - ar)), max(4.0 * br * (1.0 - br), 4.0 * s * (1.0 - s))));
    let shud = 0.006 * sin(47.0 * t + f32(g)) * o.act * (1.0 - step(0.001, s));
    o.dy = max(0.5 + 8.3 * c - 0.5 * e, 0.0) + 0.16 * sin(ph2) + 1.2 * dip - 0.25 * bm;
    o.dz = -3.2 * c + 1.3 * e - 1.1 * lb + 0.25 * spr;
    // (its own sway: the restless shift their weight foot to foot and look about, the still hardly move)
    let sw1 = sin(ph2 * 0.7 + f32(g));
    o.pyaw = -0.10 * tw + 0.022 * rest * sin(ph2 + 1.0);
    o.ppitch = 0.36 * c - 0.1 * e - 0.05 * lb + 0.03 * spr + 0.04 * post;
    o.proll = 0.012 * rest * sin(ph2) + shud + 0.02 * rest * sw1;
    o.syaw = -0.26 * tw - 0.018 * rest * sin(ph2 + 1.0) + (0.05 + 0.6 * bm) * hbias;
    o.spitch = 0.72 * c - 0.27 * e - 0.15 * lb + 0.3 * (1.0 - tor) + 0.014 * rest * sin(ph) + 0.06 * spr + shud - 0.07 * bm
        + 0.12 * post;
    o.sroll = 0.03 * tw + 0.025 * rest * sin(ph2 * 1.3 + 2.0);
    o.hyaw = 0.8 * 0.36 * tw + 0.05 * rest * sin(ph2 * 0.8) + hbias * (1.0 - 0.6 * bm);
    o.hpitch = -0.45 * c - 0.04 * e + 0.1 * lb + 0.42 * (1.0 - hd) + 0.012 * sin(ph + 0.6) - 0.34 * bm - 0.08 * post;
    // overlap: each part moves after the one that drives it. The swing: the torso leads, the head is left behind looking up
    // and snaps after; the blow: the pelvis stops first, the torso and then the head carry on down and come back, the
    // shoulders rolling off it, each a spring a little later than the last
    let sarc = sin(3.14159 * s) * select(0.0, 1.0, pre);
    o.spitch = o.spitch + 0.1 * sarc;
    o.hpitch = o.hpitch - 0.22 * sarc;
    o.spitch = o.spitch + 0.16 * cl_spring(dt - 0.05) + 0.05 * sag;
    o.hpitch = o.hpitch + 0.3 * cl_spring(dt - 0.14) + 0.1 * sag;
    o.sroll = o.sroll + 0.07 * (v - 0.5) * cl_spring(dt - 0.1);
    o.dy = o.dy + 0.9 * sag;
    // (the hang: the body drawn back like a bow, the head tipped up after the hammer)
    o.hpitch = o.hpitch - 0.12 * wind;
    // the small life in every joint, its own rates for each giant: the restless more, the still hardly at all; and between
    // the moves, the head turning to look about, at the others, at the land, at the middle
    let gs = f32(g) * 7.31 + v * 13.0;
    let r2 = 0.35 + 0.65 * rest;
    let idle = (1.0 - o.act) * (1.0 - bm) * select(1.0, 0.0, s > 0.0 && pre) * cl_pt(0.85, 1.05, u);
    o.pyaw = o.pyaw + 0.03 * r2 * cl_nz(t, gs);
    o.proll = o.proll + 0.012 * r2 * cl_nz(t * 1.2, gs + 1.0);
    o.syaw = o.syaw + 0.05 * r2 * cl_nz(t * 0.9, gs + 2.0);
    o.sroll = o.sroll + 0.03 * r2 * cl_nz(t * 1.1, gs + 3.0);
    o.spitch = o.spitch + 0.025 * r2 * cl_nz(t * 0.8, gs + 4.0) + 0.018 * sin(ph * (0.7 + 0.25 * rest));
    o.hyaw = o.hyaw + (0.05 * cl_nz(t, gs + 5.0) + 0.38 * cl_look(t, gs, 2.2 + 2.6 / rest)) * r2 * idle;
    o.hpitch = o.hpitch + (0.03 * cl_nz(t * 1.3, gs + 6.0) + 0.1 * cl_look(t, gs + 3.0, 3.1 + 2.0 / rest)) * r2 * idle;
    o.syaw = o.syaw + 0.12 * r2 * cl_look(t, gs, 2.2 + 2.6 / rest) * idle;
    let wd = length(vec2<f32>(cl_f(b + 4u), cl_f(b + 6u)));
    let tb = CL_HIT + wd / CL_WAVE;
    // (the blast in the middle rocks them a little; their own hammer bursting in their hands throws them back)
    let tg = cl_tb(g);
    // (each part answers the shove in turn: the pelvis pushed back first, the torso rocked after it, the head last and
    // whipping forward against it, a heavy give and return each, the blast's wave a smaller shove than their own hammer)
    let bp = react * (0.4 * cl_imp(t - tb, 4.0) + cl_imp(t - tg, 5.0));
    let btr = react * (0.4 * cl_imp(t - tb - 0.07, 3.6) + cl_imp(t - tg - 0.07, 4.4));
    let bhd = react * (0.4 * cl_imp(t - tb - 0.15, 3.2) + cl_imp(t - tg - 0.15, 3.8));
    // (the light climbing the hammer: they look down at it, and a slow tremble goes through them as it comes up their arms)
    let chg = cl_pt(CL_CHARGE - 0.2, CL_CHARGE + 0.7, t) * (1.0 - cl_pt(tg, tg + 0.3, t));
    o.hpitch = o.hpitch + 0.5 * chg;
    o.spitch = o.spitch + 0.02 * cl_nz(t * 9.0, gs + 9.0) * chg * cl_pt(CL_CHARGE, tg, t);
    o.dz = o.dz - 1.5 * bp;
    o.dy = o.dy + 0.4 * bp;
    o.ppitch = o.ppitch - 0.08 * bp;
    o.spitch = o.spitch - 0.3 * btr;
    o.sroll = o.sroll + 0.05 * (v - 0.5) * btr;
    o.hpitch = o.hpitch + 0.2 * bhd + 0.3 * bm * cl_pt(tb, tb + 0.8, t);
    // (the head tips back only a little: past that the cut under its jaw opens at the front and its glowing core reads as an
    // open mouth; the chest does the rest of the looking up)
    let back = min(o.hpitch + 0.06, 0.0);
    o.hpitch = o.hpitch - back;
    o.spitch = o.spitch + 0.7 * back;
    // the feet: the left lifted and stamped down forward into the stance before the first heave, the right back and out
    // before the second, the weight over the other while one is up; they stay there, the giant ending crouched where it
    // struck
    let stp = cl_stomps(g);
    let k1 = clamp((t - (stp.x - 0.95)) / 0.95, 0.0, 1.0);
    let k2 = clamp((t - (stp.y - 0.95)) / 0.95, 0.0, 1.0);
    let s1 = cl_step(k1);
    let s2 = cl_step(k2);
    o.lf = vec3<f32>(2.0 + 0.5 * s1.x, 5.2 * s1.y, 3.4 * s1.x);
    o.rf = vec3<f32>(-(2.0 + 0.9 * s2.x), 4.6 * s2.y, -2.4 * s2.x);
    let up1 = sin(3.14159 * k1);
    let up2 = sin(3.14159 * k2);
    o.px = -1.5 * up1 + 1.5 * up2 + 0.25 * (s1.x - s2.x) + 0.55 * (rest - 0.4) * sw1;
    o.proll = o.proll + 0.035 * (up1 - up2);
    o.dz = o.dz + 1.0 * s1.x - 0.5 * s2.x;
    // (each stamp goes through the whole body)
    let j1 = max(t - stp.x, 0.0);
    let j2 = max(t - stp.y, 0.0);
    o.dy = o.dy + 0.7 * ((1.0 - exp(-16.0 * j1)) * exp(-3.2 * j1) + (1.0 - exp(-16.0 * j2)) * exp(-3.2 * j2));
    // and after their hammers burst they sink, the heavy way, into the crouch their statue is built in (words 48-58,
    // `STATUE_POSE` in tools/colossi_assets.py, which poses the blocks the same way: keep the two in step), and hold it
    // still: from CL_SETTLE on the giant drawn is exactly its statue
    let w = pow(cl_grind(cl_pt(tg + 0.2, CL_SETTLE, t), 3.0), 0.8);
    // (it goes down on one knee: that foot drawn back and its knee set down, the other foot stepped on forward under it;
    // words 59-62, tools/colossi_pose.py's `feet`. One foot at a time, the way a heavy thing moves: the front foot is lifted,
    // swung in and planted first, the weight over the other; then that one steps back and the knee goes down)
    let kf = vec3<f32>(cl_f(b + 59u), cl_f(b + 60u), cl_f(b + 61u));
    let kw = cl_pt(0.36, 0.95, w);
    o.kn = cl_pt(0.45, 0.95, w);
    let kl = 2.5 * sin(3.14159 * kw);
    let fw = cl_pt(0.0, 0.42, w);
    if (cl_f(b + 62u) < 0.5) {
        o.rf = mix(o.rf, kf, kw) + vec3<f32>(0.0, kl, 0.0);
        o.lf = mix(o.lf, CL_FRONT * vec3<f32>(-1.0, 1.0, 1.0), fw) + vec3<f32>(0.0, 3.0 * sin(3.14159 * fw), 0.0);
    } else {
        o.lf = mix(o.lf, kf, kw) + vec3<f32>(0.0, kl, 0.0);
        o.rf = mix(o.rf, CL_FRONT, fw) + vec3<f32>(0.0, 3.0 * sin(3.14159 * fw), 0.0);
    }
    // (the front knee bends up over its foot, not in: the leg's pole turns from forward to up as it steps out)
    o.fu = fw;
    // (the pelvis comes down from no higher than the kneel holds it: where the stance held it low, it rises onto the knee
    // as the feet come in under it and does not stand up past it first)
    o.dy = mix(mix(o.dy, max(o.dy, cl_f(b + 48u)), cl_pt(0.0, 0.12, w)), cl_f(b + 48u), w);
    o.dz = mix(o.dz, cl_f(b + 49u), w);
    o.px = mix(o.px, cl_f(b + 50u), w) + select(1.0, -1.0, cl_f(b + 62u) < 0.5) * 1.1 * sin(3.14159 * fw);
    o.ppitch = mix(o.ppitch, cl_f(b + 51u), w);
    o.pyaw = mix(o.pyaw, cl_f(b + 52u), w);
    o.proll = mix(o.proll, cl_f(b + 53u), w);
    o.spitch = mix(o.spitch, cl_f(b + 54u), w);
    o.syaw = mix(o.syaw, cl_f(b + 55u), w);
    o.sroll = mix(o.sroll, cl_f(b + 56u), w);
    o.hpitch = mix(o.hpitch, cl_f(b + 57u), w);
    o.hyaw = mix(o.hyaw, cl_f(b + 58u), w);
    // (and as the stone takes it, it shudders to a stop: a shake that grows as it settles and is gone the instant it is
    // still, so the giant drawn is its statue exactly from CL_SETTLE)
    let shk = smoothstep(0.45, 0.85, w) * (1.0 - w) * 4.0;
    let sf = t * 34.0 + f32(g) * 3.7;
    o.spitch = o.spitch + 0.035 * shk * sin(sf);
    o.sroll = o.sroll + 0.03 * shk * sin(sf * 1.31 + 1.0);
    o.pyaw = o.pyaw + 0.02 * shk * sin(sf * 0.87 + 2.0);
    o.hpitch = o.hpitch + 0.05 * shk * sin(sf * 1.17 + 0.5);
    o.hyaw = o.hyaw + 0.04 * shk * sin(sf * 0.93 + 3.0);
    o.dy = o.dy + 0.35 * shk * sin(sf * 1.53);
    let hh = vec3<f32>(sin(ps), 0.0, cos(ps));
    o.hb = hb;
    o.hu = hh * cos(th) + vec3<f32>(0.0, sin(th), 0.0);
    o.he = -hh * sin(th) + vec3<f32>(0.0, cos(th), 0.0);
    o.sl = sl;
    o.arc = smoothstep(0.0, 0.3, s) * (1.0 - smoothstep(0.72, 1.0, s));
    // (the hammer is gone from their hands as it bursts)
    o.hold = 1.0 - cl_pt(tg, tg + 1.2, t);
    return o;
}

// ---- the skeleton: rigid transforms chained about the joints ------------------------------------------------------------------
struct Xf {
    r: mat3x3<f32>,
    t: vec3<f32>,
}
fn cl_xf_id() -> Xf {
    return Xf(mat3x3<f32>(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 0.0, 1.0)), vec3<f32>(0.0));
}
// The parent's transform followed by a turn `rl` about the point `c` (of the rest pose).
fn cl_about(pr: Xf, c: vec3<f32>, rl: mat3x3<f32>) -> Xf {
    return Xf(pr.r * rl, pr.r * (c - rl * c) + pr.t);
}
fn cl_pos(x: Xf, p: vec3<f32>) -> vec3<f32> { return x.r * p + x.t; }

struct ClLeg {
    thigh: Xf,
    shin: Xf,
    foot: Xf,
}
// Two-bone IK: the hip is carried by the pelvis, the ankle stays where it stood (the foot planted; if the pelvis has gone
// further than the leg is long the foot is lifted as little as it must), the knee bends forward.
// (a0 the ankle at rest, goal where the foot is put: the shin keeps its own length and turns from its own rest direction)
// (kn: how far it kneels, 0..1: the foot then turns all the way with the shin and points its toes back along the ground)
// A frame from an axis and a direction across it (made square to the axis): the columns axis, across, their cross.
fn cl_frame(ax: vec3<f32>, n: vec3<f32>) -> mat3x3<f32> {
    let nn = normalize(n - ax * dot(n, ax));
    return mat3x3<f32>(ax, nn, cross(ax, nn));
}
fn cl_leg(pel: Xf, h0: vec3<f32>, k0: vec3<f32>, a0: vec3<f32>, goal: vec3<f32>, kn: f32, up: f32, sx: f32) -> ClLeg {
    let hw = cl_pos(pel, h0);
    let l1 = length(k0 - h0);
    let l2 = length(a0 - k0);
    let e0 = goal - hw;
    let d = clamp(length(e0), 0.35 * (l1 + l2), l1 + l2);
    let e = normalize(e0);
    let a = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d);
    let h = sqrt(max(l1 * l1 - a * a, 0.0));
    var fwd = pel.r * vec3<f32>(0.0, 0.0, 1.0) + vec3<f32>(0.0, up, 0.0);
    // (and never in across the body: with the foot out to the side and forward or back, forward made square to the leg
    // leans in; as much of the leg's outward side `so` (sx: 1 the left, -1 the right) is put back as cancels that)
    let so = pel.r * vec3<f32>(sx, 0.0, 0.0);
    let es = dot(e, so);
    let l0 = dot(fwd, so) - es * dot(fwd, e);
    fwd = fwd + so * (max(-l0, 0.0) / max(1.0 - es * es, 0.2));
    let pv = normalize(fwd - e * dot(fwd, e));
    let kw = hw + e * a + pv * h;
    let aw = hw + e * d;
    // (thigh, shin and foot turn as one hinge: each from its own rest axis to its new one about the same knee line, the
    // leg's bend plane's normal, so the knee never twists open between them)
    let n = cross(e, pv);
    let n0 = cross(normalize(a0 - h0), vec3<f32>(0.0, 0.0, 1.0));
    let rt = cl_frame(normalize(kw - hw), n) * transpose(cl_frame(normalize(k0 - h0), n0));
    let rs = cl_frame(normalize(aw - kw), n) * transpose(cl_frame(normalize(a0 - k0), n0));
    var o: ClLeg;
    o.thigh = Xf(rt, hw - rt * h0);
    o.shin = Xf(rs, kw - rs * k0);
    // (the foot takes a third of the shin's lean about the ankle, so the shin never stands out of it; kneeling, all of it,
    // its toes then pointed back along the ground)
    let s0 = normalize(a0 - k0);
    let rf = cl_frame(normalize(mix(s0, normalize(aw - kw), mix(0.35, 1.0, kn))), n) * transpose(cl_frame(s0, n0)) * cl_rx(1.2 * kn);
    o.foot = Xf(rf, aw - rf * a0);
    return o;
}

// A turn of `a` radians about the unit axis f.
fn cl_axis(f: vec3<f32>, a: f32) -> mat3x3<f32> {
    let c = cos(a);
    let s = sin(a);
    let k = 1.0 - c;
    return mat3x3<f32>(
        vec3<f32>(c + k * f.x * f.x, k * f.x * f.y + s * f.z, k * f.x * f.z - s * f.y),
        vec3<f32>(k * f.x * f.y - s * f.z, c + k * f.y * f.y, k * f.y * f.z + s * f.x),
        vec3<f32>(k * f.x * f.z + s * f.y, k * f.y * f.z - s * f.x, c + k * f.z * f.z));
}
// Two-bone IK for an arm: the shoulder is carried by the torso (`xt`), the fist goes to `goal` (the mesh's own space), the
// elbow bends towards `pole`, and the forearm is twisted about itself so the fist's grip axis (`ax0` in the rest pose) lies
// along the handle `gu` (by `w`). Returns the upper arm's and the forearm's transforms.
struct ClArm {
    upper: Xf,
    fore: Xf,
}
fn cl_arm(xt: Xf, s0: vec3<f32>, e0: vec3<f32>, w0: vec3<f32>, goal: vec3<f32>, pole: vec3<f32>, ax0: vec3<f32>, gu: vec3<f32>, w: f32) -> ClArm {
    let sw = cl_pos(xt, s0);
    let l1 = length(e0 - s0);
    let l2 = length(w0 - e0);
    let e = goal - sw;
    let d = clamp(length(e), 0.3 * (l1 + l2), 0.999 * (l1 + l2));
    let dir = normalize(e);
    let a = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d);
    let h = sqrt(max(l1 * l1 - a * a, 0.0));
    let pv = normalize(pole - dir * dot(pole, dir));
    let kw = sw + dir * a + pv * h;
    let ww = sw + dir * d;
    let f = normalize(ww - kw);
    let ru = cl_arc(normalize(e0 - s0), normalize(kw - sw));
    var rf = cl_arc(normalize(w0 - e0), f);
    let a1 = rf * ax0;
    let ap = a1 - f * dot(a1, f);
    let bp = gu - f * dot(gu, f);
    let wt = w * smoothstep(0.02, 0.2, dot(bp, bp));
    if (wt > 0.0 && dot(ap, ap) > 1.0e-4) {
        let an = normalize(ap);
        let bn = normalize(bp);
        rf = cl_axis(f, wt * atan2(dot(cross(an, bn), f), dot(an, bn))) * rf;
    }
    var o: ClArm;
    o.upper = Xf(ru, sw - ru * s0);
    o.fore = Xf(rf, kw - rf * e0);
    return o;
}
// the way an arm's elbow is bent in the rest pose (off the line from the shoulder to the fist)
fn cl_rest_pole(s0: vec3<f32>, e0: vec3<f32>, w0: vec3<f32>) -> vec3<f32> {
    let dir = normalize(w0 - s0);
    let v = e0 - s0;
    return normalize(v - dir * dot(v, dir) + vec3<f32>(0.0, 0.0, -1.0e-3));
}

// One piece as an instance: its mesh, the pose transform `x` (in the design's mesh space) over the giant at p0.
fn cl_piece(g: u32, d: u32, b: u32, x: Xf, p0: vec3<f32>, am: mat3x3<f32>, sc: f32) -> ClInst {
    var o: ClInst;
    o.g = g;
    o.kind = 0u;
    o.mesh = CL_NB * d + b;
    o.s = sc;
    o.r = am * x.r;
    o.p = p0 + am * (x.t * sc);
    let hb = CL_MESH + 16u * o.mesh;
    let ext = cl_v3(hb + 7u);
    o.c = o.p + o.r * ((cl_v3(hb + 4u) + ext * 0.5) * sc);
    o.rad = sc * (0.5 * length(ext) + cl_f(hb + 14u)) + 0.5;
    return o;
}

// All the pieces of giant g at time t: 0-12 the bones (pelvis, torso, head, right arm, right forearm, left arm, left forearm,
// right thigh, right shin, left thigh, left shin, right foot, left foot), 13 the hammer. (Keep colossi_rig.py's BONES.)
fn cl_rig(g: u32, t: f32, pi: ptr<function, array<ClInst, 14>>) {
    let b = CL_INST + CL_REC * g;
    let d = mod_data[b];
    let sc = cl_f(b + 2u);
    var p0 = cl_v3(b + 4u);
    let am = cl_a(g);
    let hsr = cl_f(b + 36u);
    let j_pel = cl_j(d, 0u);
    let j_sp = cl_j(d, 1u);
    let j_nk = cl_j(d, 2u);
    let j_rs = cl_j(d, 3u);
    let j_re = cl_j(d, 4u);
    let j_rw = cl_j(d, 5u);
    let j_ls = cl_j(d, 6u);
    let j_le = cl_j(d, 7u);
    let j_lw = cl_j(d, 8u);
    // (the slam's place and the giant's own ground, in its mesh's space)
    let sm = ((cl_v3(b + 44u) - p0) * am) / sc;
    let p = cl_pose(g, t, j_pel, sm, CL_BURY / sc, hsr);
    let rise = cl_rise(g, t);
    p0.y = p0.y - 56.0 * sc * (1.0 - rise);
    // the pelvis: turned about the hips and carried down and forward
    var xp = cl_about(cl_xf_id(), j_pel, cl_rz(p.proll) * cl_rx(p.ppitch) * cl_ry(p.pyaw));
    xp.t = xp.t + vec3<f32>(p.px, -p.dy, p.dz);
    var xt = cl_about(xp, j_sp, cl_rz(p.sroll) * cl_rx(p.spitch) * cl_ry(p.syaw));
    // the left hand is the anchor at the handle's end: if the arm can't reach it the whole body goes after it
    let fl0 = j_lw + normalize(j_lw - j_le) * 2.5;
    let lreach = 0.97 * (length(j_le - j_ls) + length(fl0 - j_le));
    let ms = cl_pos(xt, 0.5 * (j_rs + j_ls));
    let dv = p.hb - ms;
    let od = normalize(normalize(dv) + xt.r * vec3<f32>(0.0, 0.25, 0.8));
    let phb = p.hb + od * (max(0.86 * lreach - length(dv), 0.0) * p.arc);
    let dl = phb - cl_pos(xt, j_ls);
    let sh = dl * (max(1.0 - lreach / max(length(dl), 0.01), 0.0) * p.hold);
    xp.t = xp.t + sh;
    xt.t = xt.t + sh;
    // the right hand slides on the handle, never further up it than the arm can reach
    let rreach = 0.97 * (length(j_re - j_rs) + length(j_rw - j_re));
    let m = phb - cl_pos(xt, j_rs);
    let mu = dot(m, p.hu);
    let q2 = sqrt(max(mu * mu - dot(m, m) + rreach * rreach, 0.0));
    let lo = max(-mu - q2, 4.0);
    let slr = clamp(p.sl, lo, max(-mu + q2, lo));
    // (and where the right arm can't reach its grip anywhere along the handle, in a deep squat or a hard twist, the body leans
    // on in after it, and the left's reach is checked again: both fists stay on the handle, never hanging off it)
    let gpr = phb + p.hu * slr;
    for (var it = 0; it < 3; it = it + 1) {
        let er = gpr - cl_pos(xt, j_rs);
        let s1 = er * (max(1.0 - rreach / max(length(er), 0.01), 0.0) * p.hold);
        xp.t = xp.t + s1;
        xt.t = xt.t + s1;
        let el = phb - cl_pos(xt, j_ls);
        let s2 = el * (max(1.0 - lreach / max(length(el), 0.01), 0.0) * p.hold);
        xp.t = xp.t + s2;
        xt.t = xt.t + s2;
        // (nor may the pelvis rise further from the planted feet than the legs reach: it sinks back onto them)
        var drop = 0.0;
        for (var k = 0u; k < 2u; k = k + 1u) {
            let h0 = cl_j(d, select(12u, 9u, k == 0u));
            let k0 = cl_j(d, select(13u, 10u, k == 0u));
            let ar = cl_j(d, select(14u, 11u, k == 0u));
            let a0 = ar + select(p.lf, p.rf, k == 0u);
            drop = max(drop, length(a0 - cl_pos(xp, h0)) - 0.995 * (length(k0 - h0) + length(ar - k0)));
        }
        xp.t.y = xp.t.y - 1.1 * max(drop, 0.0);
        xt.t.y = xt.t.y - 1.1 * max(drop, 0.0);
    }
    let xh = cl_about(xt, j_nk, cl_rx(p.hpitch) * cl_ry(p.hyaw));
    let gr = mix(cl_pos(xt, j_rw), gpr, p.hold);
    let gl = mix(cl_pos(xt, fl0), phb, p.hold);
    let pr = normalize(mix(xt.r * cl_rest_pole(j_rs, j_re, j_rw), xt.r * normalize(vec3<f32>(-0.8, -0.5, -0.2)), p.hold));
    let pl = normalize(mix(xt.r * cl_rest_pole(j_ls, j_le, fl0), xt.r * normalize(vec3<f32>(0.8, -0.5, -0.2)), p.hold));
    let ra = cl_arm(xt, j_rs, j_re, j_rw, gr, pr, vec3<f32>(0.0, 1.0, 0.0), p.hu, p.hold);
    let la = cl_arm(xt, j_ls, j_le, fl0, gl, pl, vec3<f32>(0.0, 0.0, 1.0), p.hu, p.hold);
    // (a wide stance, stepped into and out of: cl_pose's feet)
    let kr = select(0.0, 1.0, cl_f(CL_INST + CL_REC * g + 62u) < 0.5);
    let rl = cl_leg(xp, cl_j(d, 9u), cl_j(d, 10u), cl_j(d, 11u), cl_j(d, 11u) + p.rf, p.kn * kr, p.fu * (1.0 - kr), -1.0);
    let ll = cl_leg(xp, cl_j(d, 12u), cl_j(d, 13u), cl_j(d, 14u), cl_j(d, 14u) + p.lf, p.kn * (1.0 - kr), p.fu * kr, 1.0);
    (*pi)[0] = cl_piece(g, d, 0u, xp, p0, am, sc);
    (*pi)[1] = cl_piece(g, d, 1u, xt, p0, am, sc);
    (*pi)[2] = cl_piece(g, d, 2u, xh, p0, am, sc);
    (*pi)[3] = cl_piece(g, d, 3u, ra.upper, p0, am, sc);
    (*pi)[4] = cl_piece(g, d, 4u, ra.fore, p0, am, sc);
    (*pi)[5] = cl_piece(g, d, 5u, la.upper, p0, am, sc);
    (*pi)[6] = cl_piece(g, d, 6u, la.fore, p0, am, sc);
    (*pi)[7] = cl_piece(g, d, 7u, rl.thigh, p0, am, sc);
    (*pi)[8] = cl_piece(g, d, 8u, rl.shin, p0, am, sc);
    (*pi)[9] = cl_piece(g, d, 9u, ll.thigh, p0, am, sc);
    (*pi)[10] = cl_piece(g, d, 10u, ll.shin, p0, am, sc);
    (*pi)[11] = cl_piece(g, d, 11u, rl.foot, p0, am, sc);
    (*pi)[12] = cl_piece(g, d, 12u, ll.foot, p0, am, sc);
    // the hammer, by the point of its handle the left hand holds (its mesh's), the handle's way and the head's
    let hm = 2u * CL_NB;
    let hb = CL_MESH + 16u * hm;
    let ext = cl_v3(hb + 7u);
    let q = mat3x3<f32>(p.he, p.hu, cross(p.he, p.hu));
    var o: ClInst;
    o.g = g;
    o.kind = 1u;
    o.mesh = hm;
    o.s = sc * hsr;
    o.r = am * q;
    o.p = p0 + am * (sc * (phb - hsr * (q * vec3<f32>(9.25, 7.0, 4.0))));
    o.c = o.p + o.r * ((cl_v3(hb + 4u) + ext * 0.5) * o.s);
    o.rad = o.s * 0.5 * length(ext) + 0.5;
    (*pi)[13] = o;
}

// ---- the converter's damage (docs/damage.md of model-to-minecraft), exactly: integer hashing and a few float operations ----
fn cl_h3(seed: u32, ix: i32, iy: i32, iz: i32) -> u32 {
    var x = seed ^ (u32(ix) * 0x8DA6B343u) ^ (u32(iy) * 0xD8163841u) ^ (u32(iz) * 0xCB1AB31Fu);
    x = x ^ (x >> 16u);
    x = x * 0x7FEB352Du;
    x = x ^ (x >> 15u);
    x = x * 0x846CA68Bu;
    x = x ^ (x >> 16u);
    return x;
}
fn cl_unit(seed: u32, ix: i32, iy: i32, iz: i32) -> f32 {
    return f32(cl_h3(seed, ix, iy, iz)) * (1.0 / 4294967296.0);
}
// Value noise in [-1, 1].
fn cl_vn(s: u32, p: vec3<f32>) -> f32 {
    let f = floor(p);
    let t0 = p - f;
    let t = t0 * t0 * (3.0 - 2.0 * t0);
    let i = vec3<i32>(f);
    var o = 0.0;
    for (var k = 0u; k < 8u; k = k + 1u) {
        let dx = i32(k & 1u);
        let dy = i32((k >> 1u) & 1u);
        let dz = i32(k >> 2u);
        let w = select(1.0 - t.x, t.x, dx == 1) * select(1.0 - t.y, t.y, dy == 1) * select(1.0 - t.z, t.z, dz == 1);
        o = o + w * cl_unit(s, i.x + dx, i.y + dy, i.z + dz);
    }
    return o * 2.0 - 1.0;
}
// How far inside the nearest chunk a block at grid position `g` is, negative inside: the least over the chunks of
// (distance from its middle) - (its radius with the ragged edge); the blocks with a negative value are the ones removed.
fn cl_damage(b: u32, gp: vec3<f32>) -> f32 {
    let seed = mod_data[b + 7u];
    let grid = cl_v3(b + 12u);
    let cuts = min(mod_data[b + 15u], 8u);
    let size = cl_f(b + 16u);
    let rough = cl_f(b + 17u);
    let ymin = cl_f(b + 18u);
    let ymax = cl_f(b + 19u);
    let grain = max(grid.y / 16.0, 1.0);
    var m = CL_BIG;
    for (var i = 0u; i < cuts; i = i + 1u) {
        let ii = i32(i);
        let r0 = cl_unit(seed, ii, 0, 7001);
        let r1 = cl_unit(seed, ii, 1, 7001);
        let r2 = cl_unit(seed, ii, 2, 7001);
        let r3 = cl_unit(seed, ii, 3, 7001);
        let c = vec3<f32>((0.1 + 0.8 * r0) * grid.x, (ymin + (ymax - ymin) * r1) * grid.y, (0.1 + 0.8 * r2) * grid.z);
        let radius = size * grid.y * (0.6 + 0.8 * r3);
        let dd = length(gp - c);
        let reach = radius * (1.0 + rough * 0.75);
        if (dd > reach + 1.0) {
            m = min(m, dd - reach);
            continue;
        }
        let p = gp / grain;
        let s = seed * 31u + i;
        let n = 0.65 * cl_vn(s, p + vec3<f32>(17.0)) + 0.35 * cl_vn(s + 1000u, p * 2.0 + vec3<f32>(53.0));
        m = min(m, dd - radius * (1.0 + rough * 0.75 * n));
    }
    return m;
}

// Where a point of a piece (mesh space) is on the way the light takes: x 0 at the hammer's head, 1 at the hands, 1.5 at the
// elbows, 2 at the shoulders (99 off it); y 1 where it bursts (the hammer, and the arm pieces of the giant's mask).
fn cl_chain(ins: ClInst, u: vec3<f32>) -> vec2<f32> {
    if (ins.kind == 1u) {
        return vec2<f32>(1.0 - (u.y - 7.0) / CL_HL, 1.0);
    }
    let d = mod_data[CL_INST + CL_REC * ins.g];
    let bone = ins.mesh - CL_NB * d;
    if (bone < 3u || bone > 6u) {
        return vec2<f32>(99.0, 0.0);
    }
    let fore = (bone - 3u) & 1u;
    let j0 = 3u + 3u * ((bone - 3u) >> 1u);
    let ja = cl_j(d, j0 + 1u + fore);
    let jb = cl_j(d, j0 + fore);
    let f = dot(u - ja, jb - ja) / dot(jb - ja, jb - ja);
    return vec2<f32>(1.5 - 0.5 * f32(fore) + 0.5 * f, f32((cl_mask(ins.g) >> bone) & 1u));
}

struct ClCut {
    d: f32,     // negative where the mesh is gone; the edge glows where it is just above 0
    hot: f32,   // how freshly cut it is (white-hot, cooling to green)
    sweep: f32, // the converting line's band
}

// Where the mesh is cut at the point of mesh space `u` of an instance, at time t.
fn cl_cut(ins: ClInst, u: vec3<f32>, t: f32, flags: u32, lit: bool) -> ClCut {
    var o: ClCut;
    o.d = CL_BIG;
    o.hot = 0.0;
    o.sweep = 0.0;
    if (t < CL_BURST) {
        return o;
    }
    let wp = ins.p + ins.r * (u * ins.s);
    let b = CL_INST + CL_REC * ins.g;
    let tg = t - cl_tb(ins.g);
    // the burst: it runs from the hammer's head up the handle and the arms in a third of a second, everything in its way gone
    let ca = cl_chain(ins, u);
    if (ca.y > 0.5 && tg > 0.0) {
        o.d = (ca.x + (vnoise3(wp * 0.08) - 0.5) * 0.35 + 0.4 - tg * 7.5) * 20.0 * ins.s;
        o.hot = 1.0;
        return o;
    }
    // (the stumps the burst leaves on what stays: the upper arm's end where its forearm went, the shoulder where its upper arm
    // went, glowing in a ragged, stepped band a few blocks deep that cools and draws back to nothing in about a second. Only
    // light: d never goes under 0 here, so nothing the statue has is cut away: the trace's test leaves it out, `lit` false)
    if (lit && tg > 0.1 && ins.kind == 0u && ca.y < 0.5) {
        let d = mod_data[b];
        let bone = ins.mesh - CL_NB * d;
        let msk = cl_mask(ins.g);
        let rag = 0.45 * vnoise3(floor(wp * 0.33) * 0.22 + vec3<f32>(f32(ins.g) * 5.0)) + 0.35 * vnoise3(wp * 0.05 + vec3<f32>(3.0)) + 0.2 * hash31(floor(wp * 0.5) + vec3<f32>(9.0));
        var ds = CL_BIG;
        if ((bone == 3u || bone == 5u) && ((msk >> (bone + 1u)) & 1u) == 1u) {
            ds = max((ca.x - 1.5 - (0.012 + 0.04 * rag)) * 30.0 * ins.s, 0.0);
        } else if (bone == 1u) {
            for (var k = 0u; k < 2u; k = k + 1u) {
                if (((msk >> (3u + 2u * k)) & 1u) == 1u) {
                    ds = min(ds, max((length(u - cl_j(d, 3u + 3u * k)) - (0.4 + 1.8 * rag)) * ins.s, 0.0));
                }
            }
        }
        if (ds < o.d) {
            o.d = ds + max(tg - 0.6, 0.0) * 3.0;
            o.hot = saturate(1.0 - (tg - 0.1) * 0.6);
        }
    }
    // (and the chunks it shakes out of the rest of the giant, from where the hammer lay outwards)
    let fr = tg - 0.1 - length(wp - cl_v3(b + 44u)) / 260.0;
    if (fr > 0.0 && ins.kind == 0u && (flags & 1u) != 0u) {
        let a_m = cl_a(ins.g);
        let gp = ins.s * (a_m * u) + cl_v3(b + 20u);
        let dm = cl_damage(b, gp);
        if (dm < o.d) {
            o.d = dm;
            o.hot = saturate(1.0 - fr * 0.7);
        }
    }
    // (the line sweeping down it, the blocks it leaves behind it)
    let ts = cl_f(b + 11u);
    if (t > ts) {
        let y = ins.s * u.y;
        // (from the grid's top, its Y: word 13; word 14 is its depth, Z, which started the line half way down and dropped
        // all the giant over it the moment the sweep began)
        let h = cl_f(b + 13u);
        // (once it has gone all the way down it carries on under the soles, so nothing is left of the mesh, its band fading out)
        let gone = smoothstep(ts + CL_SWEEP, ts + CL_SWEEP + 0.6, t);
        let yl = h * (1.0 - clamp((t - ts) / CL_SWEEP, 0.0, 1.0)) - 80.0 * gone;
        let ds = yl - y;
        if (ds < o.d) {
            o.d = ds;
            o.hot = 0.0;
        }
        o.sweep = (1.0 - smoothstep(0.0, 5.0, abs(ds))) * (1.0 - gone);
    }
    return o;
}

fn cl_q(w: u32) -> vec3<f32> {
    return vec3<f32>(f32(w & 1023u), f32((w >> 10u) & 1023u), f32((w >> 20u) & 1023u));
}

// How far along the ray the box of the node at word `nb` is entered (CL_BIG if it is missed or lies past `best`).
// (ylim: the sweep's line in the mesh's space: everything over it is gone, so a box wholly over it is missed)
fn cl_slab(nb: u32, bmin: vec3<f32>, qs: vec3<f32>, ro: vec3<f32>, inv: vec3<f32>, best: f32, ylim: f32) -> f32 {
    let lo = bmin + cl_q(mod_data[nb]) * qs;
    var hi = bmin + cl_q(mod_data[nb + 1u]) * qs;
    if (lo.y > ylim) {
        return CL_BIG;
    }
    hi.y = min(hi.y, ylim);
    let t0 = (lo - ro) * inv;
    let t1 = (hi - ro) * inv;
    let tn = min(t0, t1);
    let tf = max(t0, t1);
    let a = max(max(tn.x, tn.y), max(tn.z, 0.0));
    let b = min(min(tf.x, tf.y), min(tf.z, best));
    return select(CL_BIG, a, a <= b);
}

struct ClHit {
    t: f32,
    tri: u32,          // the triangle's first word, 0 for none, 1 for the joint's ball
    uv: vec2<f32>,     // where on the triangle (the weights of its second and third vertices)
}

// The nearest hit on the instance's mesh along the world ray (ro, rd) before `tmax`, with the cuts applied; with `any`, the
// first found.
fn cl_trace(ins: ClInst, ro: vec3<f32>, rd: vec3<f32>, tmax: f32, any: bool, t: f32, flags: u32) -> ClHit {
    let rl = ((ro - ins.p) * ins.r) / ins.s;
    let rdl = (rd * ins.r) / ins.s;
    let hb = CL_MESH + 16u * ins.mesh;
    let noff = mod_data[hb];
    let toff = mod_data[hb + 1u];
    let voff = mod_data[hb + 3u];
    let bmin = cl_v3(hb + 4u);
    let qs = cl_v3(hb + 7u) * (1.0 / 1023.0);
    let safe = select(rdl, vec3<f32>(1.0e-9), abs(rdl) < vec3<f32>(1.0e-9));
    let inv = 1.0 / safe;
    let cutting = t >= CL_BURST || ((flags & 4u) != 0u);
    // (where the sweep's line is, in the mesh's space, as cl_cut has it: nothing over it is drawn, so no box over it is opened)
    var ylim = CL_BIG;
    let tsw = cl_f(CL_INST + CL_REC * ins.g + 11u);
    if (cutting && t > tsw) {
        let gone = smoothstep(tsw + CL_SWEEP, tsw + CL_SWEEP + 0.6, t);
        ylim = (cl_f(CL_INST + CL_REC * ins.g + 13u) * (1.0 - clamp((t - tsw) / CL_SWEEP, 0.0, 1.0)) - 80.0 * gone) / ins.s + 1.0e-3;
    }
    var h: ClHit;
    h.t = tmax;
    h.tri = 0u;
    h.uv = vec2<f32>(0.0);
    // (a joint's ball: a sphere about the piece's pivot, closing the seam when the joint turns)
    let ballr = cl_f(hb + 14u);
    if (ballr > 0.0) {
        let oc = rl - cl_v3(hb + 10u);
        let aa = dot(rdl, rdl);
        let bb = dot(oc, rdl);
        let disc = bb * bb - aa * (dot(oc, oc) - ballr * ballr);
        if (disc > 0.0) {
            let tb = (-bb - sqrt(disc)) / aa;
            if (tb > 0.002 && tb < h.t && !(cutting && cl_cut(ins, rl + rdl * tb, t, flags, false).d < 0.0)) {
                h.t = tb;
                h.tri = 1u;
                if (any) {
                    return h;
                }
            }
        }
    }
    if (cl_slab(noff, bmin, qs, rl, inv, h.t, ylim) >= CL_BIG) {
        return h;
    }
    var stack: array<u32, 24>;
    var dist: array<f32, 24>;
    var sp = 0u;
    var cur = 0u;
    loop {
        let w2 = mod_data[noff + cur * 3u + 2u];
        let cnt = w2 >> 28u;
        let first = w2 & 0x0FFFFFFFu;
        var next = 0xFFFFFFFFu;
        if (cnt > 0u) {
            for (var i = 0u; i < cnt; i = i + 1u) {
                let tb = toff + (first + i) * 2u;
                let ia = mod_data[tb];
                let v0 = bmin + cl_q(mod_data[voff + (ia & 0xFFFFu) * 3u]) * qs;
                let e1 = bmin + cl_q(mod_data[voff + (ia >> 16u) * 3u]) * qs - v0;
                let e2 = bmin + cl_q(mod_data[voff + (mod_data[tb + 1u] & 0xFFFFu) * 3u]) * qs - v0;
                let pv = cross(rdl, e2);
                let det = dot(e1, pv);
                if (abs(det) < 1.0e-9) {
                    continue;
                }
                let id = 1.0 / det;
                let tv = rl - v0;
                let u = dot(tv, pv) * id;
                if (u < 0.0 || u > 1.0) {
                    continue;
                }
                let qv = cross(tv, e1);
                let v = dot(rdl, qv) * id;
                if (v < 0.0 || u + v > 1.0) {
                    continue;
                }
                let th = dot(e2, qv) * id;
                if (th > 0.002 && th < h.t) {
                    if (cutting && cl_cut(ins, rl + rdl * th, t, flags, false).d < 0.0) {
                        continue;
                    }
                    h.t = th;
                    h.tri = tb;
                    h.uv = vec2<f32>(u, v);
                    if (any) {
                        return h;
                    }
                }
            }
        } else {
            let l = first;
            let tl = cl_slab(noff + l * 3u, bmin, qs, rl, inv, h.t, ylim);
            let tr = cl_slab(noff + (l + 1u) * 3u, bmin, qs, rl, inv, h.t, ylim);
            if (tl < CL_BIG && tr < CL_BIG) {
                let near_l = tl <= tr;
                next = select(l + 1u, l, near_l);
                stack[sp] = select(l, l + 1u, near_l);
                dist[sp] = select(tl, tr, near_l);
                sp = sp + 1u;
            } else if (tl < CL_BIG) {
                next = l;
            } else if (tr < CL_BIG) {
                next = l + 1u;
            }
        }
        if (next == 0xFFFFFFFFu) {
            loop {
                if (sp == 0u) {
                    break;
                }
                sp = sp - 1u;
                if (dist[sp] < h.t) {
                    next = stack[sp];
                    break;
                }
            }
            if (next == 0xFFFFFFFFu) {
                break;
            }
        }
        cur = next;
    }
    return h;
}

// What the mesh is where a ray hit it: the vertices' normals, colours, glow and openness, weighed across the triangle.
struct ClSurf {
    n: vec3<f32>,     // the smooth normal (mesh space)
    ng: vec3<f32>,    // the triangle's own
    col: vec3<f32>,   // sRGB, 0-1
    glow: f32,        // 0-1: how green the model's texture is here (its cracks)
    ao: f32,          // 0-1: how open
}

fn cl_oct(w: u32) -> vec3<f32> {
    let f = vec2<f32>(f32(w & 4095u), f32((w >> 12u) & 4095u)) * (2.0 / 4095.0) - 1.0;
    var n = vec3<f32>(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
    let k = max(-n.z, 0.0);
    n.x = n.x + select(k, -k, n.x >= 0.0);
    n.y = n.y + select(k, -k, n.y >= 0.0);
    return normalize(n);
}

fn cl_rgba(w: u32) -> vec4<f32> {
    return vec4<f32>(f32(w & 255u), f32((w >> 8u) & 255u), f32((w >> 16u) & 255u), f32(w >> 24u)) * (1.0 / 255.0);
}

fn cl_surf(hb: u32, tri: u32, uv: vec2<f32>) -> ClSurf {
    let voff = mod_data[hb + 3u];
    let ia = mod_data[tri];
    let a = voff + (ia & 0xFFFFu) * 3u;
    let b = voff + (ia >> 16u) * 3u;
    let c = voff + (mod_data[tri + 1u] & 0xFFFFu) * 3u;
    let w = vec3<f32>(1.0 - uv.x - uv.y, uv.x, uv.y);
    let qs = cl_v3(hb + 7u);
    let p0 = cl_q(mod_data[a]) * qs;
    var o: ClSurf;
    o.ng = normalize(cross(cl_q(mod_data[b]) * qs - p0, cl_q(mod_data[c]) * qs - p0));
    let na = mod_data[a + 1u];
    let nb = mod_data[b + 1u];
    let nc = mod_data[c + 1u];
    o.n = normalize(cl_oct(na) * w.x + cl_oct(nb) * w.y + cl_oct(nc) * w.z);
    o.ao = (f32(na >> 24u) * w.x + f32(nb >> 24u) * w.y + f32(nc >> 24u) * w.z) * (1.0 / 255.0);
    let k = cl_rgba(mod_data[a + 2u]) * w.x + cl_rgba(mod_data[b + 2u]) * w.y + cl_rgba(mod_data[c + 2u]) * w.z;
    o.col = k.rgb;
    o.glow = k.a;
    return o;
}

// ---- what is not mesh: the beam, the fireball, the dust and the shockwave on the land -----------------------------------
// (all in the world relative to the target block's middle; added to the picture as light, `c.rgb` with no coverage)


// How far giant g's long crack has run to the middle (x, 0..1) and how fresh its last lunge is (y, 1 as it lunges): it runs in
// jolts, three after the giant's own blow (a1 seconds ago) to a third of the way, then five from the blow all strike together
// (t2), the last of them meeting in the middle at CL_HIT.
// (the cracks lunge on together from the last of the five blows, `slam2` in strike/colossi.rs)
const CL_T2: f32 = 18.0;
fn cl_run(a1: f32, t: f32, t2: f32) -> vec2<f32> {
    let s1 = clamp(a1 / 2.4, 0.0, 1.0) * 2.35;
    let s2 = clamp((t - t2) / (CL_HIT - t2), 0.0, 1.0) * 4.35;
    let p1 = (floor(s1) + smoothstep(0.0, 0.35, fract(s1))) / 3.0;
    let p2 = (floor(s2) + smoothstep(0.0, 0.35, fract(s2))) / 5.0;
    let fresh = select(exp(-fract(s1) * 5.0) * step(s1, 2.349), exp(-fract(s2) * 4.0), t >= t2 && t < CL_HIT);
    return vec2<f32>(0.32 * p1 + 0.68 * p2, select(fresh, 0.0, a1 <= 0.0));
}

// Dust rings and the shockwave on the land at world point `w` (relative to the target block's middle), as light.
fn cl_ground(w0: vec3<f32>, t: f32) -> vec3<f32> {
    // (worked out in units of CL_K blocks, as it was for the first design)
    let w = w0 / CL_K;
    var col = vec3<f32>(0.0);
    // (the dust rings are lit dust, as bright as the day lets them be: by night they were a pale wash over the dark land)
    let dust = vec3<f32>(0.62, 0.52, 0.4) * (0.06 + 0.94 * saturate(frame.sun.y * 2.5 + 0.35));
    // a ring where each giant's weight comes down at the end of its swing, and a puff as it rises out of the earth
    for (var g = 0u; g < CL_NG; g = g + 1u) {
        let b = CL_INST + CL_REC * g;
        let t1 = cl_f(b + 10u);
        let t2 = cl_f(b + 23u);
        let tr = cl_f(b + 9u);
        let uni = step(t2, t);
        let big = 1.0 + 0.6 * uni;
        let a1 = t - t1;                        // since its first blow: the cracks stay
        let a = t - select(t1, t2, t >= t2);    // since its latest: the ring and the heat
        let design = mod_data[b];
        let fm = 0.5 * (cl_j(design, 11u) + cl_j(design, 14u));
        let foot = ((cl_a(g) * (vec3<f32>(fm.x, 0.0, fm.z) * cl_f(b + 2u))) + cl_v3(b + 4u)) / CL_K;
        let d = length(w.xz - foot.xz);
        // (the slam: a ring out from where the hammer's head lands on the ground, and the cracks it opens, green, running
        // through the land towards the middle, forking, glowing hot at the blow and settling)
        let pt = cl_v3(b + 44u) / CL_K;
        let dp = length(w.xz - pt.xz);
        if (a > 0.0 && a < 3.0) {
            let r = 4.0 + 24.0 * big * a * (1.0 - 0.2 * a);
            let ring = exp(-pow((dp - r) / (1.8 + 1.2 * a), 2.0));
            col = col + dust * ring * (1.0 - a / 3.0) * 0.4 * big * (0.6 + 0.8 * vnoise(w.xz * 0.4 - f32(g)));
        }
        // (the burst: a wider ring, and the land round it lit green)
        let ab = t - cl_tb(g);
        if (ab > 0.0 && ab < 3.0) {
            let r = 4.0 + 46.0 * ab * (1.0 - 0.2 * ab);
            let ring = exp(-pow((dp - r) / (2.2 + 1.6 * ab), 2.0));
            col = col + dust * ring * (1.0 - ab / 3.0) * 0.8 * (0.6 + 0.8 * vnoise(w.xz * 0.4 - f32(g)))
                + vec3<f32>(0.1, 1.0, 0.4) * (1.0 * exp(-dp / 13.0) * exp(-ab * 1.4));
        }
        if (a1 > 0.0) {
            let tl = clamp(a1 / 1.1, 0.0, 1.0);
            let front = 34.0 * (1.0 - exp(-a1 * 1.8)) + 14.0 * uni * (1.0 - exp(-a * 1.8));
            // the fan of cracks round the blow
            let q = w.xz - pt.xz;
            let n1 = abs(vnoise(q * 0.22 + f32(g) * 7.0) * 2.0 - 1.0);
            let n2 = abs(vnoise(q * 0.5 - f32(g) * 3.0) * 2.0 - 1.0);
            let fan = exp(-n1 * n1 * 90.0) * 0.85 + exp(-n2 * n2 * 260.0) * 0.5;
            col = col + vec3<f32>(0.1, 1.0, 0.4) * fan * smoothstep(front, front * 0.5, dp) * exp(-dp / 22.0) * (0.55 + 2.2 * big * exp(-a * 1.6)) * tl;
            // the long crack to the middle (a jagged line, growing along it from the blow)
            let ax = -pt.xz;
            let len = max(length(ax), 1.0);
            let u = ax / len;
            let rel = w.xz - pt.xz;
            let sp = dot(rel, u);
            let off = dot(rel, vec2<f32>(-u.y, u.x)) - (vnoise(vec2<f32>(sp * 0.18, f32(g) * 5.0)) - 0.5) * 7.0;
            let run = cl_run(a1, t, CL_T2);
            let grow = run.x * len;
            if (sp > 0.0 && sp < grow) {
                let w0 = 0.85 + 0.45 * sin(sp * 0.7);
                let tip = exp(-(grow - sp) * 0.16);
                let hot = 0.9 + 2.4 * tip * (0.35 + run.y) + 1.5 * run.y + 1.6 * uni * exp(-a * 1.6) + 2.5 * step(CL_HIT, t) * exp(-(t - CL_HIT) * 1.1);
                // (a side crack forking off it every so often, behind the tip)
                let fk = floor(sp / 9.0);
                let fs = sp - fk * 9.0;
                let sgn = select(-1.0, 1.0, hash21(vec2<f32>(fk, f32(g) + 3.0)) > 0.5);
                let fo = off - sgn * fs * 0.75 - (vnoise(vec2<f32>(fs * 0.5, fk + f32(g) * 9.0)) - 0.5) * 2.0;
                let fork = exp(-fo * fo / 0.2) * (1.0 - smoothstep(3.0, 8.0, fs)) * step(fk * 9.0 + 8.0, grow) * 0.7;
                col = col + (mix(vec3<f32>(0.1, 1.0, 0.45), vec3<f32>(0.6, 1.0, 0.75), saturate(tip * run.y)) * exp(-off * off / (w0 * w0)) + vec3<f32>(0.1, 1.0, 0.45) * (fork + 0.12 * exp(-off * off / (w0 * w0 * 30.0))))
                    * hot * (0.75 + 0.25 * sin(t * 3.0 - sp * 0.3));
            }
        }
        // the earth splitting over it as it comes up: green cracks out from the place, opening wider with each heave
        let a2 = t - tr;
        if (a2 > -0.4 && a2 < 9.5) {
            let up = smoothstep(-0.4, 0.8, a2) * (1.0 - smoothstep(6.0, 9.5, a2));
            let q = w.xz - foot.xz;
            let reach = 7.0 + 17.0 * cl_rise(g, t);
            if (d < reach) {
                // (the cracks radiating from its feet, where the land really splits open: `frac` in strike/colossi.rs,
                // `cl_frac` here; hot along their middle, a glow either side)
                let fr = cl_frac(11u + g, q);
                let glow = 1.3 * saturate(fr.c * 3.0) + 0.3 * exp(-fr.x * 0.9);
                // (brightest as it first splits, before anything of it shows: the hook, seen from far off)
                let early = smoothstep(-0.4, 0.3, a2) * (1.0 - smoothstep(1.2, 4.0, a2));
                col = col + vec3<f32>(0.1, 1.0, 0.4) * (glow * (1.0 + 1.6 * early) + 1.1 * early * exp(-d / (0.6 * reach) - 0.4 * fr.x)) * smoothstep(reach, reach * 0.35, d) * up * (1.1 + 0.4 * sin(t * 4.0 + d * 0.5));
            }
        }
        // (a ring of dust along the ground from each stamp of a foot)
        let stp = cl_stomps(g);
        let js = t - select(stp.x, stp.y, t >= stp.y);
        if (js > 0.0 && js < 2.0) {
            let r = 4.0 + 13.0 * js * (1.0 - 0.2 * js);
            col = col + dust * exp(-pow((d - r) / (1.5 + js), 2.0)) * (1.0 - js / 2.0) * 0.3 * (0.6 + 0.8 * vnoise(w.xz * 0.5 + f32(g)));
        }
    }
    // the blast's glow on the land round the target, and the shockwave running out from it
    let tt = t - CL_HIT;
    let d = length(w.xz);
    if (tt > -1.4 && tt <= 0.0 && d < 40.0) {
        // (as the cracks close in, the ground between them lights up from under: a crazed web of light swelling out from the
        // middle, the middle itself white-hot at the last)
        let b = smoothstep(-1.4, 0.0, tt);
        let n1 = abs(vnoise(w.xz * 0.42 + vec2<f32>(3.0, 7.0)) * 2.0 - 1.0);
        let n2 = abs(vnoise(w.xz * 1.1 - vec2<f32>(5.0, 1.0)) * 2.0 - 1.0);
        let web = exp(-n1 * n1 * 70.0) + 0.6 * exp(-n2 * n2 * 160.0);
        let reach = 4.0 + 18.0 * b;
        let fl = 0.8 + 0.2 * sin(t * 31.0 + d * 0.9);
        col = col + vec3<f32>(0.2, 1.0, 0.5) * (web * smoothstep(reach, reach * 0.3, d) * (0.6 + 3.0 * b * b) * fl
            + exp(-d / (2.0 + 5.0 * b)) * 4.0 * b * b * b);
    }
    if (tt > 0.0) {
        // the crater lit from inside: the whole of it at first, then its pit and the veins of its floor, fading over ten seconds
        let cr = CL_CRATER / CL_K;
        // (and then, to the end, a low glow pulsing slowly along the veins and in the pit)
        let pulse = 0.7 + 0.3 * sin(t * 1.3 - d * 0.25);
        let pit = exp(-d / 6.0) * (1.6 * max(exp(-tt * 0.25), 0.35 * pulse)) + exp(-d / 12.0) * 3.0 * exp(-tt * 1.6);
        let vn = abs(vnoise(w.xz * 0.3 + vec2<f32>(11.0, 4.0)) * 2.0 - 1.0);
        let veins = exp(-vn * vn * 120.0) * smoothstep(cr, cr * 0.4, d) * 0.9 * max(exp(-tt * 0.22), 0.3 * pulse) * (0.75 + 0.25 * sin(t * 2.2 + d * 0.4));
        col = col + vec3<f32>(0.15, 1.0, 0.45) * (pit + veins) * smoothstep(0.0, 0.08, tt);
        // the shockwave over the land, at the front of the dust it drives out (`cl_surge_r`)
        if (tt < 8.0) {
            let r = cl_surge_r(tt) * cl_surge_k(w0.xz, tt) / CL_K;
            let ring = exp(-pow((d - r) / (3.0 + 2.2 * tt), 2.0));
            let n = 0.45 + 0.8 * fbm(w.xz * 0.06 + vec2<f32>(tt * 0.3, 0.0));
            col = col + mix(dust, vec3<f32>(1.0) * (0.06 + 0.94 * saturate(frame.sun.y * 2.5 + 0.35)), 0.12) * ring * n * (1.0 - smoothstep(3.0, 8.0, tt)) * smoothstep(0.05, 0.3, tt) * 0.5;
        }
    }
    // (all of it fading out by the strike's end, not cut off)
    return col * (1.0 - smoothstep(31.0, 33.9, t));
}

// One puff of dust: a squashed ball of it at c (radius R, `flat` as high as wide), how much of the view it hides before
// `tmax`. One noise sample at the middle of the ray's way through it eats its edge.
fn cl_puff(ro: vec3<f32>, rd: vec3<f32>, tmax: f32, c: vec3<f32>, R: f32, flat: f32, env: f32, seed: f32, tm: f32) -> f32 {
    let k = vec3<f32>(1.0, 1.0 / flat, 1.0);
    let o = (ro - c) * k;
    let dd = rd * k;
    let aa = dot(dd, dd);
    let b = dot(o, dd);
    let disc = b * b - aa * (dot(o, o) - R * R);
    if (env <= 0.002 || disc <= 0.0) {
        return 0.0;
    }
    let sq = sqrt(disc);
    let t0 = max((-b - sq) / aa, 0.0);
    let t1 = min((-b + sq) / aa, tmax);
    if (t1 <= t0) {
        return 0.0;
    }
    let ch = (t1 - t0) * sqrt(aa) / (2.0 * R);
    let pm = ro + rd * (0.5 * (t0 + t1));
    let nz = fbm3(pm * (0.16 / CL_K) + vec3<f32>(seed, -tm * 0.3, seed * 1.7));
    let e = saturate(ch * 1.7 - 0.2 + (nz - 0.5) * 1.7);
    return e * e * (3.0 - 2.0 * e) * (0.55 + 0.45 * nz) * env;
}


// ---- the earth they raise (0 s to the last blow): rolling ground clouds where each comes up, stamps and strikes, and the
// plumes of earth thrown up as each head breaks the ground. Marched through, lit (the light falls off with how deep under
// the cloud's own top a point is, and with the side away from the sun), billowing in advected noise; nothing in a ball.
// The ray's (t0, t1) through an upright cylinder at c (xz), radius R, from y0 to y1; t1 <= t0 when it misses.
fn cl_cyl(ro: vec3<f32>, rd: vec3<f32>, c: vec2<f32>, R: f32, y0: f32, y1: f32) -> vec2<f32> {
    let oc = ro.xz - c;
    let a = max(dot(rd.xz, rd.xz), 1.0e-8);
    let b = dot(oc, rd.xz);
    let disc = b * b - a * (dot(oc, oc) - R * R);
    if (disc <= 0.0) {
        return vec2<f32>(1.0, 0.0);
    }
    let sq = sqrt(disc);
    let ry = select(rd.y, 1.0e-6, abs(rd.y) < 1.0e-6);
    let ya = (y0 - ro.y) / ry;
    let yb = (y1 - ro.y) / ry;
    return vec2<f32>(max(max((-b - sq) / a, 0.0), min(ya, yb)), min((-b + sq) / a, max(ya, yb)));
}
// The land's height under p: c.y, pulled to where this pixel's ray meets the land (lp, w 1 when it does) close to it, so
// the cloud climbs the rise it is seen against and fills the hollow (the Payload's `loc`).
fn cl_hug(p: vec3<f32>, gy: f32, lp: vec4<f32>) -> f32 {
    let dl = p.xz - lp.xz;
    return gy + (lp.y - gy) * lp.w * exp(-dot(dl, dl) / 6400.0);
}
// One rolling ground cloud: out from c (its ground) to the front rf, a wall hw high at its front billowing over it, haze
// behind; `a` its age, `env` how much of it there is, `grn` how much green light from the cracks under it. Premultiplied
// colour and coverage, marched to tmax.
fn cl_gc(ro: vec3<f32>, rd: vec3<f32>, tmax: f32, c: vec3<f32>, rf: f32, hw: f32, a: f32, env: f32, grn: f32, seed: f32, lp: vec4<f32>, L: vec3<f32>, lt: vec3<f32>) -> vec4<f32> {
    if (env < 0.003) {
        return vec4<f32>(0.0);
    }
    // (down into the land too: what lies under the land is hidden by it, and in a hollow the cloud fills it, never a
    // floor hanging over it)
    let lo = min(c.y, select(c.y, lp.y, lp.w > 0.5)) - 32.0;
    // (its ceiling over the highest the billows can reach, 3.13 hw: a lower one cut their tops off flat)
    let hi = max(c.y, select(c.y, lp.y, lp.w > 0.5)) + hw * 3.2;
    // (as wide as the noise can push its front, 1.335 rf: a narrower one cut it off straight up the side)
    let sg = cl_cyl(ro, rd, c.xz, rf * 1.36 + 4.0, lo, hi);
    let t0 = sg.x;
    let t1 = min(sg.y, tmax);
    if (t1 <= t0) {
        return vec4<f32>(0.0);
    }
    let n = clamp(i32((t1 - t0) / 10.0), 6, 14);
    let dt = (t1 - t0) / f32(n);
    let jit = 0.5 + 0.7 * (cl_jit(fract(seed * 0.37)) - 0.5);
    let Lx = normalize(L.xz + vec2<f32>(1.0e-4));
    var acc = vec3<f32>(0.0);
    var tr = 1.0;
    let sk = vec3<f32>(seed * 17.0, 0.0, seed * 9.0);
    for (var i = 0; i < n; i = i + 1) {
        let p = ro + rd * (t0 + dt * (f32(i) + jit));
        let q = p - c;
        let r = length(q.xz);
        let h = p.y - cl_hug(p, c.y, lp);
        if (h < -32.0 || h > hw * 3.2) {
            continue;
        }
        // (past the most the noise can push the front out: nothing, no noise looked at)
        if (1.335 * rf - r - 0.3 * max(h, 0.0) < 0.0) {
            continue;
        }
        // (the billows roll out and over: the noise carried outwards with the front and up as it rises)
        let out = q.xz / max(r, 1.0) * rf * 0.18;
        let w = p - vec3<f32>(out.x, 0.0, out.y) + sk;
        let n1 = vnoise3(w * vec3<f32>(1.0 / 19.0, 1.0 / 12.0, 1.0 / 19.0) + vec3<f32>(0.0, -0.5 * a, 0.0));
        let n3 = vnoise3(w * (1.0 / 41.0) + vec3<f32>(3.0, -0.25 * a, 9.0));
        // (a finer octave: the billows' own lumps, rolling over faster)
        let n0 = vnoise3(w * (1.0 / 7.0) + vec3<f32>(7.0, -0.9 * a, 2.0));
        let s = rf - r + (n1 - 0.5) * 0.3 * rf + (n3 - 0.5) * 0.25 * rf + (n0 - 0.5) * 0.07 * rf - 0.3 * max(h, 0.0);
        if (s < -0.06 * rf) {
            continue;
        }
        let top = hw * (0.35 + 1.0 * n1) * (0.55 + 0.9 * n3) * (1.0 + 0.6 * smoothstep(0.0, 0.25 * rf, s)) * (0.88 + 0.24 * n0);
        // (a firm, lumpy top, not a long fade into haze)
        let up = smoothstep(top, top * 0.6, h);
        let wall = 1.3 * smoothstep(-0.04 * rf, 0.07 * rf, s) * exp(-s / (0.16 * rf + 3.0));
        // (behind the wall a haze on the ground, thinning away up: an even blanket under the billows' top read, seen from over
        // it, as one straight edge across the land)
        let haze = (0.16 + 0.12 * n3) * exp(-max(h, 0.0) / (0.16 * hw + 4.0));
        let d = env * (wall * saturate(1.6 * n1 - 0.2 + 0.6 * (n0 - 0.5)) * (0.5 + n3) * up + haze * n1) * smoothstep(-0.06 * rf, 0.05 * rf, s);
        if (d < 0.004) {
            continue;
        }
        let al = 1.0 - exp(-d * dt * 0.12);
        // (lit from over the top and the sun's side; dark low down and on the far side)
        let deep = max(top - h, 0.0);
        let side = dot(q.xz / max(r, 1.0), Lx);
        let li = exp(-deep * 0.045) * (0.7 + 0.3 * side);
        let col = lt * (0.42 + 0.9 * li) * mix(vec3<f32>(0.22, 0.19, 0.165), vec3<f32>(0.46, 0.38, 0.28), li)
            + vec3<f32>(0.1, 1.0, 0.4) * grn * exp(-max(h, 0.0) / 5.0) * smoothstep(rf, 0.2 * rf, r) * 0.6;
        acc = acc + col * al * tr;
        tr = tr * (1.0 - al);
        if (tr < 0.03) {
            break;
        }
    }
    return vec4<f32>(acc, 1.0 - tr);
}
// The plumes of earth thrown up as giant g's head and shoulders break the ground, each its own: seeded height, width, lean
// (downwind and away from the body), start and lobes, one side bursting further than the other; they rise fast and slow,
// and their tops sag and fall back in ragged curtains as they thin into the ground cloud.
const CL_PL_WIND: vec2<f32> = vec2<f32>(0.62, 0.31);
fn cl_plumes(g: u32, t: f32, ro: vec3<f32>, rd: vec3<f32>, tmax: f32, gy: f32, L: vec3<f32>, lt: vec3<f32>) -> vec4<f32> {
    let b = CL_INST + CL_REC * g;
    let a0 = t - cl_f(b + 9u);
    if (a0 < 0.2 || a0 > 11.0) {
        return vec4<f32>(0.0);
    }
    let d = mod_data[b];
    let sc = cl_f(b + 2u);
    let am = cl_a(g);
    let p0 = cl_v3(b + 4u);
    let seed = mod_data[b + 7u];
    var jp: array<vec3<f32>, 3>;
    var ja: array<f32, 3>;
    var jh: array<f32, 3>;
    var jr: array<f32, 3>;
    var jl: array<vec2<f32>, 3>;    // its lean: blocks sideways for each block up
    var jq: array<vec4<f32>, 3>;    // its lobes: how far its one side bursts out, where, a second lobe, its twist up it
    let ks = array<u32, 3>(2u, 3u, 6u);
    let body = (am * (cl_j(d, 1u) * sc) + p0).xz;
    var mid = vec2<f32>(0.0);
    for (var k = 0u; k < 3u; k = k + 1u) {
        let j = cl_j(d, ks[k]);
        jp[k] = am * (j * sc) + p0;
        mid = mid + jp[k].xz / 3.0;
        let u = vec4<f32>(cl_unit(seed, i32(g), 41, i32(k)), cl_unit(seed, i32(g), 42, i32(k)), cl_unit(seed, i32(g), 43, i32(k)), cl_unit(seed, i32(g), 44, i32(k)));
        // (when its height came up through the ground, cl_age's way; the head's a little before it shows, the shoulders
        // each later by their own amount)
        let hj = select(j.y - 1.0, 50.0, k == 0u);
        let x = clamp(1.0 - (hj * sc - CL_BURY) / (56.0 * sc), 0.0, 1.0);
        ja[k] = a0 - CL_RISE * (0.5 - sin(asin(1.0 - 2.0 * x) / 3.0)) + select(-0.6 * u.x, 0.6 + 0.6 * u.x, k == 0u);
        jh[k] = sc * select(9.0 + 13.0 * u.y, 27.0 + 15.0 * u.y, k == 0u);
        jr[k] = sc * select(1.6 + 1.3 * u.z, 2.6 + 1.4 * u.z, k == 0u);
        let away = jp[k].xz - body;
        let dir = normalize(CL_PL_WIND * (0.5 + u.w) + away / max(length(away), 1.0) * select(1.2, 0.5, k == 0u) + vec2<f32>(u.x - 0.5, u.z - 0.5));
        jl[k] = dir * (0.08 + 0.22 * u.w);
        jq[k] = vec4<f32>(0.35 + 0.4 * u.z, 6.2832 * u.w, 0.15 + 0.25 * u.x, (u.y - 0.5) * 0.06);
    }
    // (bounded tight round what is in the air of them now, leaning, so the steps are close)
    var lo = vec2<f32>(1.0e9);
    var hi = vec2<f32>(-1.0e9);
    var Hb = 0.0;
    for (var k = 0u; k < 3u; k = k + 1u) {
        if (ja[k] > 0.0 && ja[k] < 8.5) {
            let hf = jh[k] * (1.0 - exp(-ja[k] * 2.2));
            let r = jr[k] * (3.6 + 0.5 * ja[k]);
            let top = jp[k].xz + jl[k] * hf;
            lo = min(lo, min(jp[k].xz, top) - vec2<f32>(r));
            hi = max(hi, max(jp[k].xz, top) + vec2<f32>(r));
            Hb = max(Hb, hf + jr[k] * 6.0);
        }
    }
    if (Hb <= 0.0) {
        return vec4<f32>(0.0);
    }
    let cb = 0.5 * (lo + hi);
    let sg = cl_cyl(ro, rd, cb, 0.5 * length(hi - lo), gy - 2.0, gy + Hb);
    let t0 = sg.x;
    let t1 = min(sg.y, tmax);
    if (t1 <= t0) {
        return vec4<f32>(0.0);
    }
    var tr = 1.0;
    var acc = vec3<f32>(0.0);
    // (fine steps in a plume, leaping the air between by how far the nearest is: no noise looked at out of them)
    let jit = cl_jit(f32(g) * 0.29);
    let Lx = normalize(L.xz + vec2<f32>(1.0e-4));
    var st = t0;
    for (var i = 0; i < 48; i = i + 1) {
        if (st >= t1 || tr < 0.03) {
            break;
        }
        let dt = min(max(sc + 1.0, st * 0.006), t1 - st);
        let p = ro + rd * (st + dt * jit);
        let h = p.y - gy;
        var dmin = 1.0e9;
        var dsum = 0.0;
        var lit = 0.0;
        for (var k = 0u; k < 3u; k = k + 1u) {
            let a = ja[k];
            if (a <= 0.0 || a > 8.5) {
                continue;
            }
            // (its top: shot up, slowing, then sagging back as it falls)
            let H = jh[k];
            let hf = H * (1.0 - exp(-a * 2.2)) * (1.0 - 0.5 * smoothstep(1.2, 5.5, a));
            let peak = H * (1.0 - exp(-a * 2.2));
            // (over the most its ragged cap reaches, 5.5 radii: a lower bound cut it flat)
            if (h > peak + jr[k] * 6.0) {
                dmin = min(dmin, h - peak - jr[k] * 6.0);
                continue;
            }
            let u = saturate(h / max(hf, 1.0));
            let q = p.xz - jp[k].xz - jl[k] * max(h, 0.0);
            let lq = length(q);
            // (lopsided: one side of it thrown out further, a second smaller lobe, turning a little up it)
            let ang = atan2(q.y, q.x) + jq[k].w * h;
            let lobe = 1.0 + jq[k].x * cos(ang - jq[k].y) * smoothstep(0.1, 0.7, u) + jq[k].z * cos(2.0 * ang - 1.7 * jq[k].y);
            let rad = jr[k] * (0.85 + (1.3 + 0.9 * jq[k].x) * u * sqrt(u) + 0.45 * a) * lobe;
            // (falling back: curtains of earth hanging outside it, under its sagging top)
            let fall = smoothstep(1.0, 2.5, a);
            if (lq > rad * (1.55 + 0.5 * fall)) {
                // (the leap by its widest anywhere, every way round and at any height: never past any of it)
                dmin = min(dmin, lq - jr[k] * (2.15 + 0.9 * jq[k].x + 0.45 * a) * (1.0 + jq[k].x + jq[k].z) * (1.55 + 0.5 * fall));
                continue;
            }
            dmin = 0.0;
            let w = p + vec3<f32>(f32(k) * 31.0 + f32(g) * 13.0, -peak * 0.6, f32(g) * 17.0);
            let n1 = vnoise3(w / (2.2 * sc));
            let n2 = vnoise3(w * vec3<f32>(1.0 / (1.6 * sc), 1.0 / (3.6 * sc), 1.0 / (1.6 * sc)) + vec3<f32>(5.0, a * 1.8, 1.0));
            let n0 = vnoise3(w / (0.8 * sc) + vec3<f32>(2.0, a * 2.5, 4.0));
            let rr = lq / rad + (n1 - 0.5) * 0.85 + (n2 - 0.5) * 0.4 + (n0 - 0.5) * 0.35;
            let life = smoothstep(0.0, 0.12, a) * (1.0 - smoothstep(2.2, 7.0, a)) * (1.0 - 0.6 * smoothstep(1.2, 4.0, a) * u);
            // (its top ragged: torn by the noise, lower where it has started to fall)
            let cap = smoothstep(hf + jr[k] * 1.5, hf - jr[k] * 2.5, h + (n2 - 0.5) * jr[k] * 5.0 + (n1 - 0.5) * jr[k] * 3.0);
            var dk = smoothstep(1.0, 0.5, rr) * (0.6 + 0.8 * n1) * cap * life * (2.4 - 1.4 * u);
            // (the curtains: streaks of earth falling from the top's edge, a band round it, coming down as it sags)
            let band = smoothstep(1.55, 1.15, rr) * smoothstep(0.75, 1.05, rr);
            let drop = peak - 26.0 * max(a - 1.2, 0.0) * max(a - 1.2, 0.0);
            let curtain = fall * band * smoothstep(0.55, 0.8, n2) * smoothstep(drop - jr[k] * 2.0, drop + jr[k] * 2.0, h) * smoothstep(peak + jr[k], peak - jr[k] * 2.0, h) * (1.0 - smoothstep(4.0, 8.0, a));
            dk = dk + 1.2 * curtain;
            dsum = dsum + dk;
            lit = lit + dk * saturate(0.55 + 0.45 * dot(q / max(lq, 1.0), Lx) * min(rr, 1.0) - 0.25 * (1.0 - min(rr, 1.0)));
        }
        if (dsum < 0.004 || h < -2.0) {
            st = st + max(dt, dt * jit + 0.7 * dmin);
            continue;
        }
        st = st + dt;
        let li = lit / dsum;
        let al = 1.0 - exp(-dsum * dt * 0.09);
        let col = lt * (0.25 + 0.85 * li) * mix(vec3<f32>(0.13, 0.12, 0.115), vec3<f32>(0.38, 0.3, 0.22), li);
        acc = acc + col * al * tr;
        tr = tr * (1.0 - al);
        if (tr < 0.03) {
            break;
        }
    }
    return vec4<f32>(acc, 1.0 - tr);
}
// All of it for the five giants, front to back as well as it can (each over the last): the ground cloud each raises as it
// comes up (round its feet, and where its hammer breaks out), at each stamp of a foot and each blow of its hammer, and the
// plumes. lp: where this pixel's ray meets the land (w 1 if it does); lt the light on the land.
fn cl_earth(ro: vec3<f32>, rd: vec3<f32>, t: f32, tmax: f32, lp: vec4<f32>, L: vec3<f32>, lt: vec3<f32>) -> vec4<f32> {
    var o = vec4<f32>(0.0);
    var od = 1.0e9;
    if (t > CL_T2 + 6.5) {
        return o;
    }
    for (var g = 0u; g < CL_NG; g = g + 1u) {
        let b = CL_INST + CL_REC * g;
        let sc = cl_f(b + 2u);
        let m = cl_mound(g, t);
        let gy = m.gy;
        let fg = f32(g);
        let a2 = t - cl_f(b + 9u);
        var v = vec4<f32>(0.0);
        if (a2 > 0.0 && a2 < 13.0) {
            // (round its feet: the earth bulging and splitting first, lit green from under, then rolling out as it comes up)
            let env = smoothstep(0.0, 1.2, a2) * (1.0 - smoothstep(7.5, 13.0, a2));
            let rf = sc * (11.0 + 24.0 * (1.0 - exp(-a2 * 0.32)));
            let grn = exp(-a2 * 0.45) * 1.4;
            v = cl_over(v, cl_gc(ro, rd, tmax, vec3<f32>(m.o.x, gy, m.o.y), rf, sc * (4.0 + 6.0 * cl_rise(g, t)), a2, env, grn, fg * 3.1, lp, L, lt));
            // (where the hammer's head breaks out in front of it)
            let hcw = m.o + m.sc * m.sc * (m.ax * m.hc.x + m.az * m.hc.y);
            let ah = a2 - 1.5;
            let eh = smoothstep(0.0, 1.5, ah) * (1.0 - smoothstep(6.0, 11.0, ah)) * 0.85;
            if (ah > 0.0) {
                v = cl_over(v, cl_gc(ro, rd, tmax, vec3<f32>(hcw.x, mix(gy, cl_f(b + 45u), 0.66), hcw.y), sc * (7.0 + 13.0 * (1.0 - exp(-ah * 0.4))), sc * 3.2, ah, eh, 0.3 * exp(-ah * 0.5), fg * 5.7 + 1.0, lp, L, lt));
            }
            v = cl_over(v, cl_plumes(g, t, ro, rd, tmax, gy, L, lt));
        }
        // (a stamp of a foot)
        let stp = cl_stomps(g);
        let js = t - select(stp.x, stp.y, t >= stp.y);
        if (js > 0.0 && js < 4.0) {
            let env = smoothstep(0.0, 0.25, js) * (1.0 - smoothstep(1.5, 4.0, js)) * 0.75;
            v = cl_over(v, cl_gc(ro, rd, tmax, vec3<f32>(m.o.x, gy, m.o.y), sc * (5.0 + 12.0 * (1.0 - exp(-js * 1.4))), sc * 2.2, js, env, 0.0, fg * 5.3 + 2.0, lp, L, lt));
        }
        // (a blow of its hammer, up to the last at CL_T2: earth thrown out round the head, rolling out over the land)
        let t1 = cl_f(b + 10u);
        let t2 = cl_f(b + 23u);
        let ab = t - select(t1, t2, t >= t2);
        if (ab > 0.0 && ab < 6.5 && t < cl_tb(g)) {
            let big = select(1.0, 1.35, t >= t2);
            let env = smoothstep(0.0, 0.12, ab) * (1.0 - smoothstep(2.5, 6.5, ab));
            let pt = cl_v3(b + 44u);
            v = cl_over(v, cl_gc(ro, rd, tmax, pt, sc * big * (5.0 + 20.0 * (1.0 - exp(-ab * 1.1))), sc * big * (3.0 + 1.5 * (1.0 - exp(-ab * 2.0))), ab, env, 0.8 * exp(-ab * 1.5), fg * 7.7 + 4.0, lp, L, lt));
        }
        // (the nearer giant's over the farther)
        if (v.a > 0.0) {
            let dn = length(m.o - ro.xz);
            o = select(cl_over(o, v), cl_over(v, o), dn < od);
            od = min(od, dn);
        }
    }
    return o;
}

// ---- the blast in the middle (CL_HIT): where the five cracks meet, the land bursts ----------------------------------------
// How far out the dust it drives over the land has run, tt seconds after (blocks): past the giants (300) in about 1.4 s.
fn cl_surge_r(tt: f32) -> f32 {
    return 470.0 * (1.0 - exp(-tt * 0.8)) + 12.0 * tt;
}
// The same front at the land's point xz, as a factor on cl_surge_r: lobed (seeded), its edge torn into fingers by a noise
// over the land (of the bearing alone they were straight-sided wedges). Never a circle.
fn cl_surge_k(xz: vec2<f32>, tt: f32) -> f32 {
    let s = fract(seed_v() * 0.6180339) * 61.0;
    let dir = xz / max(length(xz), 1.0);
    let lobe = vnoise(dir * 1.15 + vec2<f32>(s, 3.0 + s)) * 0.65 + vnoise(dir * 3.3 + vec2<f32>(7.0 - s, s)) * 0.35;
    let fing = vnoise(xz * 0.03 + dir * 2.0 + vec2<f32>(s * 1.3, 9.0 - tt * 0.15));
    return 0.74 + 0.52 * lobe + 0.1 * (fing - 0.5) * smoothstep(0.2, 1.5, tt);
}
fn cl_over(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(a.rgb + (1.0 - a.a) * b.rgb, a.a + (1.0 - a.a) * b.a);
}
fn cl_smin(a: f32, b: f32, k: f32) -> f32 {
    let h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}
// Where a ray (its xz) is inside the upright cylinder of radius r round the middle: entry and exit (exit < entry: never).
fn cl_cyl2(o: vec2<f32>, d: vec2<f32>, r: f32) -> vec2<f32> {
    let a = dot(d, d);
    let c = dot(o, o) - r * r;
    if (a < 1.0e-8) {
        return select(vec2<f32>(1.0e9, -1.0e9), vec2<f32>(-1.0e9, 1.0e9), c < 0.0);
    }
    let b = dot(o, d);
    let disc = b * b - a * c;
    if (disc <= 0.0) {
        return vec2<f32>(1.0e9, -1.0e9);
    }
    let sq = sqrt(disc);
    return vec2<f32>((-b - sq) / a, (-b + sq) / a);
}
// ... and between the heights ylo and yhi.
fn cl_yband(oy: f32, dy: f32, ylo: f32, yhi: f32) -> vec2<f32> {
    if (abs(dy) < 1.0e-6) {
        return select(vec2<f32>(1.0e9, -1.0e9), vec2<f32>(-1.0e9, 1.0e9), oy > ylo && oy < yhi);
    }
    let a = (ylo - oy) / dy;
    let b = (yhi - oy) / dy;
    return vec2<f32>(min(a, b), max(a, b));
}

// The eruption out of the cracks' meeting place, tt seconds after: a heavy column of earth and smoke bursting up out of the
// land, wide at its foot (the crater's width), its billowing head climbing to some 500 over the land and on to near 700 at
// its top, slowing as it goes, then hanging, carried off by the wind with height, and eaten away from outside in.
struct ClCol {
    H: f32,         // the head's middle over the land
    Rh: f32,        // the head's radius
    rb: f32,        // the foot's
    rs: f32,        // the stem's
    sk: f32,        // the height of the skirt of dust over the crater
    top: f32,       // the most any of it reaches over the land
    R: f32,         // and out from the middle (its lumps and the wind's carry in)
    gone: f32,      // how far it has dissolved
    tt: f32,
}
// The wind's carry at height h over the land: none at the foot, most at the head, growing as it hangs.
fn cl_drift(h: f32, tt: f32) -> vec2<f32> {
    return vec2<f32>(0.92, 0.38) * (9.0 * max(tt - 1.5, 0.0) * pow(saturate(h / 520.0), 1.3) + 1.5 * max(tt - 3.0, 0.0) * saturate(h / 60.0));
}
fn cl_col(tt: f32) -> ClCol {
    var c: ClCol;
    c.tt = tt;
    c.H = 20.0 + 480.0 * (1.0 - exp(-tt / 2.4));
    c.Rh = 40.0 + 160.0 * (1.0 - exp(-tt / 2.8)) + 3.5 * tt;
    c.rb = 35.0 + 130.0 * (1.0 - exp(-tt * 1.6)) + 1.5 * tt;
    c.rs = 30.0 + 105.0 * (1.0 - exp(-tt / 1.8)) + 2.0 * tt;
    c.sk = 16.0 + 30.0 * (1.0 - exp(-tt / 2.0)) + 2.0 * tt;
    c.top = c.H + 0.8 * c.Rh + 95.0;
    c.R = max(c.Rh, c.rb * 1.3) + 95.0 + 0.6 * c.rs + length(cl_drift(c.top, tt));
    c.gone = smoothstep(4.5, 13.0, tt);
    return c;
}
// Its smooth body at q (from the middle of the land, the wind's carry taken off): .x the column (a flared foot, the stem,
// the head, flatter under than over), .y the low skirt of dust over the crater.
fn cl_col_d(c: ClCol, q0: vec3<f32>) -> vec2<f32> {
    let h = q0.y;
    let u = saturate(h / max(c.H, 1.0));
    // (no straight trunk: it leans off and back as it climbs (the head overhanging its foot), necks in irregularly and
    // bulges on one side, that side turning with height)
    let sd = fract(seed_v() * 0.6180339) * 61.0;
    let la = sd * 1.7;
    let lean = vec2<f32>(cos(la), sin(la)) * (c.rs * 0.4 * sin(u * 2.4) * smoothstep(0.0, 1.0, c.tt))
        + vec2<f32>(-sin(la), cos(la)) * (c.rs * 0.18 * sin(u * 5.1 + sd));
    let q = vec3<f32>(q0.x - lean.x, h, q0.z - lean.y);
    let rho = length(q.xz);
    let eh = vec3<f32>(q.x, h - c.H, q.z) / vec3<f32>(c.Rh, c.Rh * select(0.8, 0.55, h < c.H), c.Rh);
    let dh = (length(eh) - 1.0) * c.Rh * 0.6;
    let ph = h * 0.009 + sd;
    let side = dot(q.xz, vec2<f32>(cos(ph), sin(ph))) / max(rho, 1.0);
    let neck = 1.0 - 0.2 * smoothstep(0.35, 0.75, u) * (0.6 + 0.4 * sin(h * 0.021 + sd * 2.3)) + 0.09 * sin(h * 0.047 + sd);
    let r = mix(mix(c.rb, c.rs, smoothstep(0.0, 0.3, u)), 0.75 * c.Rh, smoothstep(0.7, 1.0, u)) * neck * (1.0 + 0.16 * side);
    let ds = max(rho - r, max(h - c.H, -h - 12.0));
    let dk = (length(vec2<f32>(rho / (c.rb * 1.3), h / c.sk)) - 1.0) * min(c.sk, c.rb);
    return vec2<f32>(cl_smin(dh, ds, 0.3 * c.Rh + 10.0), dk);
}
fn cl_col_q(c: ClCol, p: vec3<f32>) -> vec3<f32> {
    let w = cl_drift(p.y, c.tt);
    return vec3<f32>(p.x - w.x, p.y, p.z - w.y);
}
// Its smoke at p (from the middle of the land): .x how thick, .y how far out on a lump (its creases darker).
// The lumps are carried up the stem and swell with the head as it grows; a slow warp churns the big ones, so the head keeps
// rolling and changing shape. Dissolving, it is eaten from outside in, unevenly, into wisps; the skirt over the crater and
// thin smoke rising from it hang on to the end.
// (q: p with the wind's carry taken off, cl_col_q; b its smooth body there, cl_col_d)
fn cl_col_rho_at(c: ClCol, q: vec3<f32>, b: vec2<f32>, fine: bool) -> vec2<f32> {
    let tt = c.tt;
    let rho = length(q.xz);
    let late = smoothstep(2.5, 7.0, tt);
    let hd = smoothstep(c.H - 1.1 * c.Rh, c.H, q.y);
    let a1 = mix(0.38 * c.rs, 0.3 * c.Rh, hd);
    let er = c.gone * mix(0.8 * c.rs, 0.8 * c.Rh, hd);
    // (nothing here whatever the noises do: no noise looked at)
    if (b.x - 0.7 * a1 - 12.8 + 0.2 * er > 0.0 && b.y > 16.8 && (late <= 0.0 || rho > c.rb * 1.15 || q.y > 260.0)) {
        return vec2<f32>(0.0);
    }
    let s = fract(seed_v() * 0.6180339) * 61.0;
    let gro = mix(1.0, c.Rh / 130.0, hd);
    let rise = (1.0 - hd) * 34.0 * tt + hd * 9.0 * tt;
    let qn = vec3<f32>(q.x, q.y - rise, q.z) / max(gro, 0.4) + vec3<f32>(s, 0.0, s * 0.7);
    let w = vnoise3(qn * 0.008 + vec3<f32>(0.0, -tt * 0.12, tt * 0.05));
    let qw = qn + (w - 0.5) * 80.0;
    let b1 = abs(gnoise3(qw * 0.0165) * 2.0 - 1.0);
    let b2 = abs(gnoise3(qw * 0.043 + vec3<f32>(3.1, tt * 0.06, 1.7)) * 2.0 - 1.0);
    var dd = b.x - a1 * (b1 - 0.3) - 14.0 * (b2 - 0.3);
    if (fine && dd < 16.0) {
        dd = dd - 6.0 * (vnoise3(qw * 0.13 + vec3<f32>(0.0, -tt * 0.6, 0.0)) - 0.5);
    }
    if (er > 0.0) {
        let lo = vnoise3(q * 0.0065 + vec3<f32>(s, -tt * 0.05, 0.0));
        dd = dd + (0.2 + 1.1 * lo) * er;
    }
    var dens = saturate(-dd / 16.0) * (0.5 + 0.5 * b1) * (1.0 - 0.7 * c.gone);
    // (the skirt: a low ragged sheet over the crater, thinning but staying)
    let dk = b.y - 14.0 * (b2 - 0.3) - 10.0 * (b1 - 0.3);
    dens = max(dens, saturate(-dk / 10.0) * 0.55 * smoothstep(0.0, 0.6, tt) * (1.0 - 0.5 * smoothstep(3.0, 10.0, tt)));
    // (thin smoke still rising off the crater's floor, leaning off with the wind)
    if (late > 0.0 && rho < c.rb * 1.15 && q.y < 260.0) {
        let wn = vnoise3(vec3<f32>(q.x * 0.03, q.y * 0.007 - tt * 0.22, q.z * 0.03) + vec3<f32>(s));
        dens = max(dens, smoothstep(0.6, 0.85, wn) * exp(-max(q.y, 0.0) / 100.0) * smoothstep(c.rb * 1.15, c.rb * 0.55, rho) * 0.4 * late);
    }
    return vec2<f32>(dens * (1.0 - smoothstep(11.5, 13.9, tt)), b1);
}
// About how far p is from anywhere the smoke could be: the march leaps through clear air by it (as the Payload's).
fn cl_col_skip_at(c: ClCol, q: vec3<f32>, b: vec2<f32>) -> f32 {
    let a1 = max(0.38 * c.rs, 0.3 * c.Rh);
    let er = c.gone * 0.8 * min(c.rs, c.Rh);
    var d = min(b.x - 0.7 * a1 - 12.8 + 0.2 * er, b.y - 16.8);
    if (c.tt > 2.5) {
        d = min(d, max(length(q.xz) - c.rb * 1.15, q.y - 260.0));
    }
    return d;
}
// How much the smoke's smooth body holds at p (for its shadows).
fn cl_col_bulk(c: ClCol, p: vec3<f32>) -> f32 {
    let b = cl_col_d(c, cl_col_q(c, p));
    return saturate(0.4 - b.x / 45.0) + 0.5 * saturate(0.3 - b.y / 20.0);
}
// The blast's own light: x how strong, y how high over the land its middle is (rising with the column). A swelling under
// the land as the cracks close in; one hard flash, gone in a few tenths of a second; the core's green light for a few
// seconds; a low glow pulsing in the crater to the end.
fn cl_blast_glow(t: f32) -> vec2<f32> {
    let tt = t - CL_HIT;
    var i = 0.0;
    if (tt > -1.4 && tt <= 0.0) {
        let b = smoothstep(-1.4, 0.0, tt);
        i = 0.7 * b * b * b;
    } else if (tt > 0.0) {
        i = select(10.0, 2.0, cl_soft()) * exp(-tt / 0.08) + 2.6 * exp(-tt / 0.6) + 0.9 * exp(-tt / 2.6) + 0.14 * (0.75 + 0.25 * sin(t * 1.9));
        i = i * (1.0 - smoothstep(31.0, 33.9, t));
    }
    return vec2<f32>(i, 12.0 + 140.0 * (1.0 - exp(-max(tt, 0.0) / 1.3)));
}
// How much of that light falls on a surface at wp facing n (relative: a gain on what it shows by day). `wrap`: how far
// round onto the side away from it it still reaches (the light is a column, not a point).
fn cl_blast_lit(wp: vec3<f32>, n: vec3<f32>, t: f32, gy: f32, wrap: f32) -> f32 {
    let g = cl_blast_glow(t);
    if (g.x <= 0.0) {
        return 0.0;
    }
    let lp = vec3<f32>(0.0, gy + g.y, 0.0) - wp;
    let d2 = dot(lp, lp);
    let ndl = saturate((dot(n, lp * inverseSqrt(max(d2, 1.0))) + wrap) / (1.0 + wrap));
    return g.x * 28900.0 / (28900.0 + d2) * ndl;
}
// How much of the land at wp the column's smoke keeps the sun from (0..1): a few looks along the light at its body, each
// edge torn by noise and softer the further the light has come (a ragged penumbra, never a straight-sided band).
fn cl_blast_shade(wp: vec3<f32>, L: vec3<f32>, t: f32, gy: f32) -> f32 {
    let tt = t - CL_HIT;
    if (tt <= 0.3 || tt > 13.9 || L.y < 0.2) {
        return 0.0;
    }
    let c = cl_col(tt);
    // (the light's way up from wp, in xz: nowhere near the column, no shadow)
    let s_lo = max((gy - wp.y) / L.y, 0.0);
    let s_hi = max((gy + c.top - wp.y) / L.y, 0.0);
    let la = wp.xz + L.xz * s_lo;
    let lb = wp.xz + L.xz * s_hi;
    let ab = lb - la;
    let ce = cl_drift(0.6 * c.top, tt) * 0.5;
    let u = saturate(dot(ce - la, ab) / max(dot(ab, ab), 1.0e-3));
    if (length(la + ab * u - ce) > c.R + 40.0) {
        return 0.0;
    }
    let sd = fract(seed_v() * 0.6180339) * 61.0;
    var tau = 0.0;
    // (with the sun low the looks lie too far apart along the land to make one shadow: none then)
    for (var i = 0; i < 6; i = i + 1) {
        let h = c.top * (0.08 + 0.16 * f32(i));
        let s = (gy + h - wp.y) / L.y;
        if (s > 0.0) {
            let p = wp + L * s;
            let q = cl_col_q(c, vec3<f32>(p.x, h, p.z));
            let b = cl_col_d(c, q);
            if (min(b.x, b.y) < 90.0 + 0.12 * s) {
                let nz = vnoise(q.xz * 0.018 + vec2<f32>(sd + f32(i) * 3.7, tt * 0.12)) - 0.5;
                let soft = 55.0 + 0.12 * s;
                tau = tau + saturate(0.45 - (b.x + 70.0 * nz) / soft) + 0.5 * saturate(0.3 - (b.y + 30.0 * nz) / (0.5 * soft));
            }
        }
    }
    return (1.0 - exp(-tau * 0.9)) * smoothstep(0.2, 0.4, L.y) * (1.0 - 0.75 * c.gone) * smoothstep(0.3, 1.5, tt) * (1.0 - smoothstep(11.5, 13.9, tt));
}
// One side of the crown where the ray meets its cone at s: colour and coverage (premultiplied).
fn cl_crown_at(ro: vec3<f32>, rd: vec3<f32>, s: f32, tmax: f32, gy: f32, tt: f32, rb: f32, hc: f32, k: f32, L: vec3<f32>, lum: f32) -> vec4<f32> {
    if (s <= 0.0 || s >= tmax) {
        return vec4<f32>(0.0);
    }
    let p = ro + rd * s;
    let h = p.y - gy;
    if (h < 0.0 || h > hc * 1.4) {
        return vec4<f32>(0.0);
    }
    let u = h / max(hc, 1.0);
    // (thrown earth in streaks and sprays: noise in the world's space (no seam, no straight edge) stretched up the cone,
    // broad streaks torn into rags by a finer one; soft-edged, thinning as it rises, the tops ragged)
    let sd = fract(seed_v() * 0.6180339) * 61.0;
    let nb = vnoise3(vec3<f32>(p.x * 0.02 + sd, h * 0.0045 - tt * 0.35, p.z * 0.02));
    let nf = vnoise3(vec3<f32>(p.x * 0.06, h * 0.013 - tt * 0.8, p.z * 0.06 + sd) + vec3<f32>(7.3, 0.0, 2.1));
    let reach = 0.55 + 0.6 * vnoise3(vec3<f32>(p.x * 0.011, 4.0 + sd, p.z * 0.011));
    let m = 0.65 * nb + 0.35 * nf;
    let streak = nb;
    let dens = smoothstep(0.36 + 0.3 * u, 0.7 + 0.2 * u, m) * (1.0 - smoothstep(0.35 * reach, reach, u + (nf - 0.5) * 0.4)) * smoothstep(0.0, 6.0, h);
    let fade = 1.0 - smoothstep(1.8, 4.5, tt + 0.6 * (streak - 0.5));
    let nrm = normalize(vec3<f32>(p.x, -k * length(p.xz), p.z));
    // (thicker seen edge-on, at the cone's sides, than face-on: a shell of earth, not a pane)
    let al = dens * fade * 0.85 * mix(0.5, 1.0, 1.0 - abs(dot(nrm, rd)));
    let sl = 0.4 + 0.6 * max(dot(nrm, L), 0.0);
    let alb = mix(vec3<f32>(0.2, 0.16, 0.12), vec3<f32>(0.3, 0.29, 0.27), streak);
    let green = vec3<f32>(0.12, 1.0, 0.42);
    // (the core's light on its inside, low and early, and through the gaps between the streaks)
    let heat = exp(-tt * 1.3) * exp(-h / 90.0);
    let gap = (1.0 - dens) * exp(-tt * 1.5) * exp(-h / 40.0) * fade * 0.3 * saturate(1.0 - u);
    return vec4<f32>((alb * lum * sl + green * heat * 0.6) * al + green * gap, al);
}

// The dust the blast drives out over the land on one stretch [s0, s1] of the ray: a low wall rolling out at the front,
// lobed and torn (cl_surge_k), heaped up where it meets a giant, a thinner sheet behind it, lit green from under at first.
fn cl_surge_seg(ro: vec3<f32>, rd: vec3<f32>, s0: f32, s1: f32, gy: f32, tt: f32, jit: f32, lum: f32, gxz: ptr<function, array<vec2<f32>, 5>>) -> vec4<f32> {
    if (s1 <= s0) {
        return vec4<f32>(0.0);
    }
    let Rs = cl_surge_r(tt);
    let ws = 22.0 + 14.0 * tt;
    let hs = 26.0 + 44.0 * (1.0 - exp(-tt * 0.8));
    let fade = smoothstep(0.05, 0.35, tt) * (1.0 - smoothstep(5.0, 11.0, tt));
    let green = vec3<f32>(0.12, 1.0, 0.42);
    // (a step every ~90 blocks, 7 to 10; one over the dust's highest reach costs no noise)
    // (looking down, the steps closer towards the land, where it is thickest)
    let n = clamp(i32(ceil((s1 - s0) / 90.0)), 7, 10);
    let w = mix(1.0, 1.8, smoothstep(0.25, 0.7, -rd.y));
    let sl = s1 - s0;
    var acc = vec3<f32>(0.0);
    var tr = 1.0;
    for (var i = 0; i < n; i = i + 1) {
        let u = 1.0 - (f32(i) + jit) / f32(n);
        let ds = sl * w * pow(u, w - 1.0) / f32(n);
        let p = ro + rd * (s1 - sl * pow(u, w));
        let rr = max(length(p.xz), 1.0);
        var gb = 0.0;
        for (var g = 0u; g < CL_NG; g = g + 1u) {
            let e = p.xz - (*gxz)[g];
            gb = max(gb, exp(-dot(e, e) / 6400.0));
        }
        if (p.y - gy >= hs * 1.2 * (1.0 + 1.7 * gb)) {
            continue;
        }
        let Rf = Rs * cl_surge_k(p.xz, tt);
        gb = gb * smoothstep(Rf + ws, Rf - 0.5 * ws, rr);
        let x = (rr - Rf) / ws;
        let hl = hs * (1.0 + 1.7 * gb) * (0.6 + 0.6 * exp(-(x + 0.4) * (x + 0.4)));
        let v = (p.y - gy) / hl;
        let front = select(exp(-x * x * 0.55), exp(-x * x * 2.6), x > 0.0);
        let shape = (front + 0.22 * smoothstep(Rf, Rf * 0.5, rr) * smoothstep(Rf * 0.25, Rf * 0.45, rr) + 0.5 * gb) * pow(saturate(1.0 - v), 1.3);
        if (shape > 0.01) {
            let nz = 0.6 * vnoise3(p * 0.022 + vec3<f32>(0.0, -tt * 0.5, tt * 0.3)) + 0.4 * vnoise3(p * 0.061 + vec3<f32>(tt * 0.4, -tt * 0.9, 0.0));
            // (a soft knee, not a cut: a threshold's edge is what a few jittered steps show as grain)
            let e0 = max(shape * (0.15 + 1.7 * nz) - 0.2 - 0.3 * saturate(x), 0.0);
            let dens = min(e0 * e0 / (e0 + 0.12), 1.0) * fade;
            let a = 1.0 - exp(-dens * ds * 0.035);
            let c = vec3<f32>(0.4, 0.35, 0.29) * lum * (0.55 + 0.5 * saturate(v)) + green * (1.2 * exp(-tt * 1.1) * exp(-saturate(v) * 2.5) * exp(-rr / 170.0));
            acc = acc + c * a * tr;
            tr = tr * (1.0 - a);
        }
    }
    return vec4<f32>(acc, 1.0 - tr);
}

// The blast's earth and dust, premultiplied colour and coverage over what is at tmax: the crown of rock and earth it throws
// up round the crater, the eruption's column (cl_col) climbing out of it far over the giants and dissolving to the end, and
// the dust it drives out over the land past the giants (in front of the column on the near side, behind it on the far).
// (gy: the land's height in the middle; jit: this pixel's jitter of the marches)
fn cl_blast(ro: vec3<f32>, rd: vec3<f32>, t: f32, tmax: f32, gy: f32, jit: f32) -> vec4<f32> {
    let tt = t - CL_HIT;
    if (tt <= 0.0 || tt > 14.0) {
        return vec4<f32>(0.0);
    }
    let sun = frame.sun.xyz;
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    let day = saturate(sun.y * 2.5 + 0.35);
    let lum = 0.14 + 0.95 * day;
    let green = vec3<f32>(0.12, 1.0, 0.42);

    // the crown: the cone r = rb + k (y - gy) where the ray meets it (x² + z² = (rb + k (y - gy))², a quadratic along it)
    var near = vec4<f32>(0.0);
    var far = vec4<f32>(0.0);
    if (tt < 4.5) {
        let k = 0.62;
        let rb = 30.0 + 140.0 * (1.0 - exp(-tt * 3.0));
        let hc = 330.0 * (1.0 - exp(-tt * 2.4));
        let a0 = rb + k * (ro.y - gy);
        let qa = rd.x * rd.x + rd.z * rd.z - k * k * rd.y * rd.y;
        let qb = 2.0 * (ro.x * rd.x + ro.z * rd.z - a0 * k * rd.y);
        let qc = ro.x * ro.x + ro.z * ro.z - a0 * a0;
        let disc = qb * qb - 4.0 * qa * qc;
        if (disc > 0.0 && abs(qa) > 1.0e-5) {
            let sq = sqrt(disc);
            let sa = (-qb - sq) / (2.0 * qa);
            let sb = (-qb + sq) / (2.0 * qa);
            near = cl_crown_at(ro, rd, min(sa, sb), tmax, gy, tt, rb, hc, k, L, lum);
            far = cl_crown_at(ro, rd, max(sa, sb), tmax, gy, tt, rb, hc, k, L, lum);
        }
    }

    // the column, marched through the upright cylinder that holds all of it, from the land to over its highest lump (its
    // smoke thins to nothing well inside both, so no edge of the march ever shows)
    var colm = vec4<f32>(0.0);
    let c = cl_col(tt);
    let ro_l = vec3<f32>(ro.x, ro.y - gy, ro.z);
    var sc = cl_cyl2(ro.xz, rd.xz, c.R);
    let sy = cl_yband(ro_l.y, rd.y, -6.0, c.top);
    let s0 = max(max(sc.x, sy.x), 0.0);
    let s1 = min(min(sc.y, sy.y), tmax);
    if (s1 > s0) {
        // (leaping through clear air, then steps of ~9 blocks (wider far off and in thin smoke), jittered, till opaque)
        var acc = vec3<f32>(0.0);
        var tr = 1.0;
        // (the core: green-white and blinding at first, low in the crater; its light spreading up the column, cooling)
        let yc = 25.0 + 90.0 * (1.0 - exp(-tt / 1.2));
        let lr = 50.0 + 110.0 * (1.0 - exp(-tt / 1.5));
        let ic = 7.0 * exp(-tt / 0.5) + 1.1 * exp(-tt / 1.2) + 0.12 * exp(-tt / 3.5) * (0.8 + 0.2 * sin(t * 1.9));
        let hot = mix(green, vec3<f32>(0.8, 1.0, 0.86), exp(-tt / 0.45));
        var s = s0;
        var thin = 1.0;
        for (var i = 0; i < 44; i = i + 1) {
            if (s >= s1 || tr < 0.01) {
                break;
            }
            // (the step's look, and how far it is from any smoke, from one look at the body there)
            let ds = min(max(9.0, s * 0.006) * (1.0 + 1.6 * thin), s1 - s);
            let p = ro_l + rd * (s + ds * jit);
            let qp = cl_col_q(c, p);
            let bp = cl_col_d(c, qp);
            let d0 = cl_col_skip_at(c, qp, bp);
            if (d0 > 10.0) {
                s = s + ds * jit + max(d0 * 0.6, 6.0);
                thin = 1.0;
                continue;
            }
            s = s + ds;
            let r = cl_col_rho_at(c, qp, bp, true);
            thin = 1.0 - saturate(r.x * 6.0);
            if (r.x > 0.002) {
                let a = 1.0 - exp(-r.x * ds * 0.05);
                // (the sun through it: two looks along the light at its smooth body)
                let tau = cl_col_bulk(c, p + L * 30.0) * 30.0 + cl_col_bulk(c, p + L * 95.0) * 65.0;
                let sh = exp(-tau * 0.035 * (1.0 - 0.6 * c.gone));
                let alb = mix(vec3<f32>(0.16, 0.135, 0.11), vec3<f32>(0.29, 0.265, 0.235), saturate(p.y / 480.0)) * (0.7 + 0.4 * r.y);
                let amb = 0.32 + 0.12 * saturate(p.y / 400.0);
                let dc = length(p - vec3<f32>(0.0, yc, 0.0));
                let em = hot * ic * exp(-dc / lr) * exp(-max(p.y - yc, 0.0) / (90.0 + 40.0 * tt)) * (0.4 + 0.6 * (1.0 - saturate(r.x)));
                acc = acc + (alb * lum * (amb + 0.85 * sh) + em) * a * tr;
                tr = tr * (1.0 - a);
            }
        }
        colm = vec4<f32>(acc, 1.0 - tr);
    }

    // the dust driven out over the land
    var sn = vec4<f32>(0.0);
    var sf = vec4<f32>(0.0);
    if (tt < 11.0) {
        var gxz: array<vec2<f32>, 5>;
        for (var g = 0u; g < CL_NG; g = g + 1u) {
            gxz[g] = cl_v3(CL_INST + CL_REC * g + 4u).xz;
        }
        let Rs = cl_surge_r(tt);
        let ws = 22.0 + 14.0 * tt;
        let hs = 26.0 + 44.0 * (1.0 - exp(-tt * 0.8));
        let so = cl_cyl2(ro.xz, rd.xz, Rs * 1.31 + 1.6 * ws);
        let si = cl_cyl2(ro.xz, rd.xz, max(Rs * 0.2 - ws, 1.0));
        // (as high as it heaps against a giant only where the ray passes near one)
        let y3 = cl_yband(ro.y, rd.y, gy - 4.0, gy + hs * 3.4);
        let xa = ro.xz + rd.xz * max(max(so.x, y3.x), 0.0);
        let xb = ro.xz + rd.xz * max(min(min(so.y, y3.y), tmax), 0.0);
        var hg = 1.25;
        for (var g = 0u; g < CL_NG; g = g + 1u) {
            let e = gxz[g] - xa;
            let ab = xb - xa;
            if (length(e - ab * saturate(dot(e, ab) / max(dot(ab, ab), 1.0e-3))) < 240.0) {
                hg = 3.4;
            }
        }
        let yb = cl_yband(ro.y, rd.y, gy - 4.0, gy + hs * hg);
        let a0 = max(max(so.x, yb.x), 0.0);
        let a1 = min(min(so.y, yb.y), tmax);
        let qa = dot(rd.xz, rd.xz);
        let smid = select(-dot(ro.xz, rd.xz) / qa, 0.0, qa < 1.0e-8);
        let m0 = select(smid, min(si.x, smid), si.y > si.x);
        let m1 = select(smid, max(si.y, smid), si.y > si.x);
        sn = cl_surge_seg(ro, rd, a0, min(a1, m0), gy, tt, jit, lum, &gxz);
        sf = cl_surge_seg(ro, rd, max(a0, m1), a1, gy, tt, jit, lum, &gxz);
    }
    return cl_over(near, cl_over(sn, cl_over(colm, cl_over(sf, far))));
}

// ---- the earth they break: heaved up in a ring where each comes through, and dragged up against its feet. Blocks, in 2-block
// cells; `Heave::terms` in strike/colossi.rs is the same sum. With the terrain on (flags bit 3) the mod tears the real land up as
// they rise and heaps this on it as blocks, so only what lies in the crater (gone with it at the blast) is drawn here ----
struct ClM {
    o: vec2<f32>,               // the middle of its feet (world xz)
    ax: vec2<f32>,              // its own x and z in the world, over its scale
    az: vec2<f32>,
    f: array<vec3<f32>, 4>,     // its feet at rest and in the stance: xz in its own units, z how far the earth is up them
    gr: f32,
    sc: f32,
    gy: f32,
    seed: u32,
    hc: vec2<f32>,              // the hammer's head where it came up out of the ground, in its own units from `o`
    sq: vec2<f32>,              // and where it is driven in
    hs: vec2<f32>,              // the head's half width, and the hammer's scale over the giant's
    slam: f32,                  // 1 once the first blow has landed
    o2: vec2<f32>,              // the circle (world xz, blocks) that holds what the hammer heaved up past the giant's own
    r2: f32,
    cut: f32,                   // the crater so far (blocks from the middle): no heap inside it
    real: f32,                  // 1 with the terrain on: the heap outside the crater is the world's blocks, not drawn
    g: u32,                     // which giant (its cracks' seed, 11 + g)
    sy: f32,                    // the land's height where the hammer is driven in (word 45): the lip round it lies on it
}
fn cl_mound(g: u32, t: f32) -> ClM {
    let b = CL_INST + CL_REC * g;
    let d = mod_data[b];
    var m: ClM;
    m.g = g;
    m.sc = cl_f(b + 2u);
    let a = cl_a(g);
    let jr = cl_j(d, 11u);
    let jl = cl_j(d, 14u);
    let fm = 0.5 * (jr + jl);
    m.o = (a * (vec3<f32>(fm.x, 0.0, fm.z) * m.sc)).xz + vec2<f32>(cl_f(b + 4u), cl_f(b + 6u));
    m.ax = (a * vec3<f32>(1.0, 0.0, 0.0)).xz / m.sc;
    m.az = (a * vec3<f32>(0.0, 0.0, 1.0)).xz / m.sc;
    let rise = cl_rise(g, t);
    m.gr = smoothstep(0.0, 0.6, rise);
    let up = smoothstep(0.45, 1.0, rise);
    let stp = cl_stomps(g);
    let l = jl.xz - fm.xz + vec2<f32>(0.0, 1.6);
    let r = jr.xz - fm.xz + vec2<f32>(0.0, 1.6);
    m.f[0] = vec3<f32>(l + vec2<f32>(2.0, 0.0), up);
    m.f[1] = vec3<f32>(r - vec2<f32>(2.0, 0.0), up);
    m.f[2] = vec3<f32>(l + vec2<f32>(2.5, 3.4), smoothstep(0.0, 0.3, t - stp.x));
    m.f[3] = vec3<f32>(r - vec2<f32>(2.9, 2.4), smoothstep(0.0, 0.3, t - stp.y));
    m.gy = cl_f(b + 5u) + CL_BURY;
    m.seed = mod_data[b + 7u];
    // (the hammer: its head on the ground in front as they rise, `cl_hground`'s rest, then driven in at the slam's place)
    let hsr = cl_f(b + 36u);
    let jp = cl_j(d, 0u);
    let sm = ((cl_v3(b + 44u) - cl_v3(b + 4u)) * a) / m.sc;
    m.hc = vec2<f32>(jp.x, jp.z + 26.5) - fm.xz;
    m.sq = sm.xz - fm.xz;
    m.hs = vec2<f32>(0.5 * cl_f(CL_MESH + 32u * CL_NB + 9u) * hsr, hsr);
    m.slam = smoothstep(0.0, 0.25, t - cl_f(b + 10u));
    m.cut = min(max(t - CL_HIT - 0.15, 0.0) * 140.0, CL_CRATER + 2.0);
    m.real = select(0.0, 1.0, (cl_flags() & 8u) != 0u);
    m.sy = cl_f(b + 45u);
    let zhi = m.sq.y + 6.0 * hsr + 3.5;
    let qc = vec2<f32>(0.5 * (m.hc.x + m.sq.x), 0.5 * (16.0 + zhi));
    m.o2 = m.o + m.sc * m.sc * (m.ax * qc.x + m.az * qc.y);
    m.r2 = m.sc * length(vec2<f32>(m.hs.x + 3.5 + 0.5 * abs(m.hc.x - m.sq.x), 0.5 * (zhi - 16.0))) + 2.0;
    return m;
}
fn cl_n2(s: u32, p: vec2<f32>) -> f32 {
    let f = floor(p);
    let u = p - f;
    let i = vec2<i32>(f);
    return mix(mix(cl_unit(s, i.x, 5, i.y), cl_unit(s, i.x + 1, 5, i.y), u.x), mix(cl_unit(s, i.x, 5, i.y + 1), cl_unit(s, i.x + 1, 5, i.y + 1), u.x), u.y);
}
// Value noise on `cl_unit`'s lattice, eased between (strike/colossi.rs's `vs`).
fn cl_vs(s: u32, p: vec2<f32>) -> f32 {
    let f = floor(p);
    let u0 = p - f;
    let u = u0 * u0 * (3.0 - 2.0 * u0);
    let i = vec2<i32>(f);
    return mix(mix(cl_unit(s, i.x, 6, i.y), cl_unit(s, i.x + 1, 6, i.y), u.x), mix(cl_unit(s, i.x, 6, i.y + 1), cl_unit(s, i.x + 1, 6, i.y + 1), u.x), u.y);
}
// The ground a giant breaks as it rises (strike/colossi.rs's `Frac` and `frac`, step for step): q in CL_K units from the
// middle of its feet, world axes; s 11 + the giant. CL_FR_N cracks radiating from its feet, each with up to two branches
// veering off it; plates between them in staggered rings CL_FR_RING wide, each tipped its own way.
struct ClFr {
    c: f32,      // how far into a crack (0 none, 1 its middle)
    nr: f32,     // how near that crack's root
    x: f32,      // the nearest crack's distance over its half width
    ring: f32,   // blocks to the plate's fissure across its ring (99 none)
    p: f32,      // the plate's two hashes
    p2: f32,
    ramp: f32,   // how far up its tilt
    dj: f32,     // its ring's middle (units)
}
const CL_FR_N: f32 = 9.0;
const CL_FR_RING: f32 = 3.6;
fn cl_fr_id(k: f32) -> i32 {
    let n = i32(CL_FR_N);
    return ((i32(k) % n) + n) % n;
}
fn cl_frac(s: u32, q: vec2<f32>) -> ClFr {
    let d = max(length(q), 1.0e-3);
    let arc = 6.2831855 * d / CL_FR_N;
    let warp = (3.4 * (cl_vs(s, q * 0.11) - 0.5) + 0.7 * (cl_vs(s + 97u, q * 0.5) - 0.5)) * min(d / 7.0, 1.0);
    let u = atan2(q.y, q.x) / 6.2831855 * CL_FR_N + warp / arc;
    let k0 = floor(u);
    var o: ClFr;
    o.c = 0.0;
    o.nr = 0.0;
    o.x = 99.0;
    o.ring = 99.0;
    var sub = 0;
    for (var n = 0; n < 4; n = n + 1) {
        let kk = k0 + select(0.0, 1.0, n == 1 || n == 3);
        let side = select(select(-1.0, 1.0, n == 2), 0.0, n < 2);
        let i = cl_fr_id(kk);
        let jit = 0.56 * (cl_unit(s, i, 7, 9) - 0.5);
        var st: f32;
        var half: f32;
        var at: f32;
        var nr: f32;
        if (side == 0.0) {
            let d0 = 2.2 + cl_unit(s, i, 7, 2);
            let l = 12.0 + 9.0 * cl_unit(s, i, 7, 1);
            st = smoothstep(d0, d0 + 1.2, d) * (1.0 - smoothstep(0.6 * l, l, d));
            nr = 1.0 - smoothstep(d0, 13.0, d);
            half = 0.5 + 1.1 * nr;
            at = kk + jit;
        } else {
            let b = select(4, 3, side > 0.0);
            if (cl_unit(s, i, 7, b) < 0.3) {
                continue;
            }
            let ds = 4.0 + 7.0 * cl_unit(s, i, 7, b + 2);
            let l = ds + 4.0 + 7.0 * cl_unit(s, i, 7, b + 4);
            let veer = 0.4 * smoothstep(ds, ds + 5.0, d);
            at = kk + jit + side * veer;
            if (d > ds + 0.5 && d < l && select(at > u, u > at, side > 0.0)) {
                sub = sub | select(2, 1, side > 0.0);
            }
            st = smoothstep(ds, ds + 1.0, d) * (1.0 - smoothstep(0.5 * (ds + l), l, d));
            nr = 1.0 - smoothstep(ds, 16.0, d);
            half = 0.4 + 0.5 * nr;
        }
        if (st < 0.02) {
            continue;
        }
        let x = abs(u - at) * arc * CL_K / half;
        let c = st * (1.0 - x);
        if (c > o.c) {
            o.c = c;
            o.nr = nr;
        }
        if (st > 0.3) {
            o.x = min(o.x, x);
        }
    }
    let pid = cl_fr_id(k0) * 4 + sub;
    let ph = cl_unit(s, pid, 11, 0);
    let v = (d + 3.2 * (cl_vs(s + 5u, q * 0.14) - 0.5)) / CL_FR_RING + ph;
    let j = floor(v);
    let fr = v - j;
    if (d > 3.0 && cl_unit(s, pid, 8, i32(floor(v + 0.5))) > 0.45) {
        o.ring = min(fr, 1.0 - fr) * CL_FR_RING * CL_K;
    }
    o.p = cl_unit(s, pid, 9, i32(j));
    o.p2 = cl_unit(s, pid, 10, i32(j));
    o.ramp = select(select(u - k0, 1.0 - fr, o.p2 < 0.8), fr, o.p2 < 0.4);
    o.dj = (j + 0.5 - ph) * CL_FR_RING;
    return o;
}
// A point (world xz) in a giant's own frame: x how far from the middle of its feet, y from the hammer's ridge, z from where
// it is driven in (units; ragged, the ridge narrowing to its far end: `Heave::shape`).
fn cl_mshape(m: ClM, w: vec2<f32>) -> vec3<f32> {
    let q = vec2<f32>(dot(w, m.ax), dot(w, m.az));
    let pn = cl_n2(m.seed ^ 0x51u, q * 0.45) - 0.5;
    let pa = q - m.hc;
    let ba = abs(pa) - vec2<f32>(m.hs.x, 7.5 * m.hs.y);
    let boxa = length(max(ba, vec2<f32>(0.0))) + min(max(ba.x, ba.y), 0.0) + 0.6 * m.hs.x * smoothstep(-2.0 * m.hs.y, 7.5 * m.hs.y, pa.y);
    let da = min(boxa, length(vec2<f32>(pa.x, pa.y - clamp(pa.y, -24.0 * m.hs.y, 0.0))) - 1.6 * m.hs.y) + 1.4 * pn;
    let bb = abs(q - m.sq) - vec2<f32>(m.hs.x, 6.0 * m.hs.y);
    let db = length(max(bb, vec2<f32>(0.0))) + min(max(bb.x, bb.y), 0.0) + 1.2 * pn;
    return vec3<f32>(length(q), da, db);
}
// The colour of the torn earth's block k (0..2) of family `fam` (strike/colossi.rs's `HV_FAM`, the blocks' averages).
fn cl_heapcol(fam: u32, k: u32) -> vec3<f32> {
    var tab = array<vec3<f32>, 24>(
        vec3<f32>(0.30, 0.30, 0.31), vec3<f32>(0.33, 0.33, 0.35), vec3<f32>(0.42, 0.43, 0.38),
        vec3<f32>(0.49, 0.49, 0.49), vec3<f32>(0.45, 0.45, 0.45), vec3<f32>(0.53, 0.53, 0.52),
        vec3<f32>(0.42, 0.43, 0.38), vec3<f32>(0.49, 0.49, 0.49), vec3<f32>(0.30, 0.30, 0.31),
        vec3<f32>(0.47, 0.33, 0.23), vec3<f32>(0.53, 0.38, 0.26), vec3<f32>(0.51, 0.48, 0.47),
        vec3<f32>(0.56, 0.41, 0.31), vec3<f32>(0.47, 0.33, 0.23), vec3<f32>(0.53, 0.38, 0.26),
        vec3<f32>(0.56, 0.42, 0.31), vec3<f32>(0.47, 0.33, 0.23), vec3<f32>(0.56, 0.41, 0.31),
        vec3<f32>(0.51, 0.48, 0.47), vec3<f32>(0.47, 0.33, 0.23), vec3<f32>(0.45, 0.45, 0.45),
        vec3<f32>(0.53, 0.38, 0.26), vec3<f32>(0.47, 0.33, 0.23), vec3<f32>(0.56, 0.41, 0.31));
    return tab[min(fam, 7u) * 3u + min(k, 2u)];
}
// How many blocks high the heap's top is over the giant's ground (m.gy) at cell c (-1000: none there).
fn cl_mh(m: ClM, c: vec2<i32>) -> f32 {
    let w = vec2<f32>(c) * 2.0 + 1.0 - m.o;
    // (the hammer's: a ridge thrown up along its head and its handle where it came out, and a lip round where it is driven in)
    let sh = cl_mshape(m, w);
    let q = vec2<f32>(dot(w, m.ax), dot(w, m.az));
    let r = sh.x;
    let da = sh.y;
    let db = sh.z;
    let rc = length(vec2<f32>(c) * 2.0 + 1.0);
    if ((r > 19.5 && min(da, db) > 3.5) || rc < m.cut || (m.real > 0.5 && rc >= CL_CRATER + 2.0)) {
        return -1000.0;
    }
    let n = cl_n2(m.seed, vec2<f32>(c) * 0.21);
    // (in patches a few cells across, not cell by cell)
    let n0 = 0.75 * cl_vs(m.seed ^ 0x2Fu, vec2<f32>(c) * 0.4) + 0.25 * cl_unit(m.seed, c.x, 9, c.y);
    // (what rises with it, and what the stance feet and the hammer's lip push up later)
    var hr = 0.0;
    var hs = 0.0;
    if (r <= 19.5) {
        let rr = (r - 13.0 - 5.0 * (n - 0.5)) / 2.7;
        hr = m.gr * ((1.0 + 4.6 * n * n) * exp(-rr * rr) + 0.32 * n0 * step(0.45, n0) * (1.0 - smoothstep(8.0, 13.0, r)));
        for (var k = 0; k < 4; k = k + 1) {
            let e = length((q - m.f[k].xy) / vec2<f32>(3.3, 5.2));
            let v = m.f[k].z * (2.1 + 2.2 * n + 0.6 * n0) * (1.0 - smoothstep(0.7, 1.45, e));
            if (k < 2) {
                hr = max(hr, v);
            } else {
                hs = max(hs, v);
            }
        }
    }
    if (da <= 3.5) {
        let ra = (da - 1.2 - 1.6 * (n - 0.5)) / 1.5;
        hr = max(hr, m.gr * ((1.0 + 3.8 * n * n) * exp(-ra * ra) + 0.36 * n0 * step(0.4, n0) * step(da, 0.0)) * (1.0 - smoothstep(1.5, 3.5, da)));
    }
    if (db <= 3.5) {
        let rb = (db - 1.2 - 1.6 * (n - 0.5)) / 1.5;
        hs = max(hs, m.slam * (1.0 + 4.2 * n * n) * exp(-rb * rb) * (1.0 - smoothstep(1.5, 3.5, db)));
    }
    if (max(hr, hs) <= 0.0) {
        return -1000.0;
    }
    // (split by the cracks and the plates' fissures, each plate tipped up its own way: `frac`)
    let fr = cl_frac(11u + m.g, w / CL_K);
    if (fr.c > 0.0 || fr.ring < 0.8) {
        return -1000.0;
    }
    if (hr > 0.05) {
        hr = hr + (0.12 + 0.5 * fr.p) * fr.ramp * smoothstep(0.45, 1.6, hr);
    }
    var h = max(hr, hs);
    if (m.real > 0.5) {
        // (the blocks' heap fades in out from the crater's edge: this fades out to it)
        h = h * (1.0 - smoothstep(CL_CRATER - 10.0, CL_CRATER + 2.0, rc));
    }
    // (over the land under it: the lip round the blow on the blow's own ground, not the giant's; the top over m.gy)
    let hb = floor(h * m.sc + 0.6 * n0);
    return select(-1000.0, hb + floor(cl_mbase(m, r, da, db)), hb > 0.0);
}
// How far over the giant's ground (m.gy) the land under a heap's cell lies: the blow's ground (m.sy) where the lip
// round it is what heaps the cell, its own ground nearer the giant.
fn cl_mbase(m: ClM, r: f32, da: f32, db: f32) -> f32 {
    return (m.sy - m.gy) * saturate((min(r - 13.0, da) - db) / 6.0 + 0.5);
}
// Whether heap cell c would hang in the air: the land the depth buffer shows past its foot lies well beyond it (a heap
// from a giant on a rise reaching out over a valley). Its column is left out; the blocks (terrain on) sit on each
// column's own ground anyway.
fn cl_mair(m: ClM, c: vec2<i32>, ro: vec3<f32>) -> bool {
    let rc = vec2<f32>(c) * 2.0 + 1.0;
    let sh = cl_mshape(m, rc - m.o);
    let foot = vec3<f32>(rc.x, m.gy + floor(cl_mbase(m, sh.x, sh.y, sh.z)) - 3.0, rc.y) - ro;
    let s = project_rel(foot);
    if (s.z < 0.0 || any(s.xy < vec2<f32>(0.0)) || any(s.xy > vec2<f32>(1.0))) {
        return false;
    }
    let d = depth_at(s.xy);
    let lf = length(foot);
    return select(1.0e9, length(world_offset(s.xy, d)), !is_sky(d)) > lf * 1.03 + 4.0;
}
// The ray against a giant's heap: xyz the face's normal, w how far (CL_BIG: none).
fn cl_mtrace(m: ClM, o: vec2<f32>, R: f32, ro: vec3<f32>, rd: vec3<f32>, tmax: f32) -> vec4<f32> {
    let none = vec4<f32>(0.0, 1.0, 0.0, CL_BIG);
    let oc = ro.xz - o;
    let a = dot(rd.xz, rd.xz);
    let bq = dot(oc, rd.xz);
    let disc = bq * bq - a * (dot(oc, oc) - R * R);
    if (m.gr <= 0.0 || a < 1.0e-8 || disc <= 0.0) {
        return none;
    }
    let sq = sqrt(disc);
    let ry = select(rd.y, 1.0e-6, abs(rd.y) < 1.0e-6);
    let ylo = min(m.gy, m.sy) - 6.0;
    let ya = (ylo - ro.y) / ry;
    let yb = (max(m.gy, m.sy) + 24.0 - ro.y) / ry;
    let t0 = max(max((-bq - sq) / a, 0.0), min(ya, yb));
    let t1 = min(min((-bq + sq) / a, tmax), max(ya, yb));
    if (t1 <= t0) {
        return none;
    }
    let p = (ro.xz + rd.xz * t0) * 0.5;
    var c = vec2<i32>(floor(p));
    let pos = rd.xz > vec2<f32>(0.0);
    let st = select(vec2<i32>(-1), vec2<i32>(1), pos);
    let inv = 2.0 / max(abs(rd.xz), vec2<f32>(1.0e-6));
    var tn = vec2<f32>(t0) + select(p - floor(p), 1.0 - (p - floor(p)), pos) * inv;
    var tc = t0;
    var nrm = vec3<f32>(0.0, 1.0, 0.0);
    for (var i = 0; i < 110; i = i + 1) {
        let te = min(min(tn.x, tn.y), t1);
        let h = cl_mh(m, c);
        if (h > -999.0) {
            let top = m.gy + h;
            var at = -1.0;
            var n = nrm;
            if (ro.y + ry * tc <= top) {
                if (ro.y + ry * tc > ylo - 0.5) {
                    at = tc;
                }
            } else if (ro.y + ry * te <= top) {
                at = (top - ro.y) / ry;
                n = vec3<f32>(0.0, 1.0, 0.0);
            }
            if (at >= 0.0 && !cl_mair(m, c, ro)) {
                return vec4<f32>(n, at);
            }
        }
        if (te >= t1) {
            break;
        }
        if (tn.x < tn.y) {
            tc = tn.x;
            tn.x = tn.x + inv.x;
            c.x = c.x + st.x;
            nrm = vec3<f32>(-f32(st.x), 0.0, 0.0);
        } else {
            tc = tn.y;
            tn.y = tn.y + inv.y;
            c.y = c.y + st.y;
            nrm = vec3<f32>(0.0, 0.0, -f32(st.y));
        }
    }
    return none;
}

struct ClOut {
    c: vec4<f32>,   // light added over the picture, and the giants' colour premultiplied by their coverage (rgb, a)
    e: vec4<f32>,   // x how far the hit, y how much the land is in their shadow, z how far the land is
}

// Whether the ray (ro, rd) comes within the giant's reach (its whole skeleton and the hammer) before `tmax`.
fn cl_coarse(g: u32, t: f32, ro: vec3<f32>, rd: vec3<f32>, tmax: f32) -> bool {
    let b = CL_INST + CL_REC * g;
    let d = mod_data[b];
    let sc = cl_f(b + 2u);
    let rise = cl_rise(g, t);
    var c = cl_v3(b + 4u) + cl_a(g) * (cl_j(d, 0u) * sc);
    c.y = c.y - 56.0 * sc * (1.0 - rise);
    // (all of it within 64 of its pelvis with the hammer swung; within 48 while it rises, till it heaves the hammer up for
    // its first blow, and within 44 once the hammer is gone (cl_gone): the most measured over the strike, every giant, on
    // flat land and among hills 40 high, is 57.6 with the hammer swung, 41.2 as it rises with it and 39.6 without it)
    let rad = sc * select(select(64.0, 48.0, t < cl_f(b + 10u) - 3.2), 44.0, t > cl_tb(g) + 0.45);
    let oc = ro - c;
    let bb = dot(oc, rd);
    let disc = bb * bb - (dot(oc, oc) - rad * rad);
    return disc >= 0.0 && -bb + sqrt(disc) >= 0.0 && -bb - sqrt(disc) <= tmax;
}

// Whether the giants stand between the point `wp` and the sun (towards L): 1 in their shadow.
fn cl_shadow(wp: vec3<f32>, L: vec3<f32>, t: f32, flags: u32) -> f32 {
    var pieces: array<ClInst, 14>;
    for (var g = 0u; g < CL_NG; g = g + 1u) {
        if (!cl_coarse(g, t, wp, L, 400.0 * CL_K)) {
            continue;
        }
        cl_rig(g, t, &pieces);
        for (var k = 0u; k < CL_NP; k = k + 1u) {
            if (cl_gone(g, k, t)) {
                continue;
            }
            let ins = pieces[k];
            let oc = wp - ins.c;
            let b = dot(oc, L);
            let disc = b * b - (dot(oc, oc) - ins.rad * ins.rad);
            if (disc < 0.0 || -b + sqrt(disc) < 0.0) {
                continue;
            }
            if (cl_trace(ins, wp, L, 400.0 * CL_K, true, t, flags).tri != 0u) {
                return 1.0;
            }
        }
    }
    return 0.0;
}

// The flash and sparks where each hammer's head lands, as light along the view ray.
// The burst's rubble: each giant's hammer and arms break into CL_DBN chunks (`cl_pc`, cut by fracture planes, drawn in blocks by
// `cl_vox`), thrown out tumbling as the burst passes, landing with a puff and lying there to the end.
const CL_DBN: u32 = 40u;          // pieces a giant: 0-3 big and 4-15 mid (cut by fracture planes, in blocks), the rest small (whole blocks)
const CL_DBG: f32 = 28.0;         // what pulls them down, blocks a second a second
// Where giant g's hammer and arms are as they burst, worked out cheaply, never by cl_rig: the hammer as cl_rig places it (by
// then it lies driven in at the slam's place: cl_hground at rest), the shoulders where the crouch it holds leaves them (cl_pose's
// numbers for that moment) drawn out to reach the handle, the elbows bent between as cl_arm bends them.
struct ClBs {
    hr: mat3x3<f32>,              // the hammer's mesh to the world,
    hp: vec3<f32>,                // where its mesh's (9.25, 7, 4) is (where the bottom hand holds it),
    hs: f32,                      // and its scale
    w: array<vec3<f32>, 2>,       // the wrists, right and left (world)
    e: array<vec3<f32>, 2>,       // the elbows
    s: array<vec3<f32>, 2>,       // the shoulders
}
fn cl_bsrc(g: u32) -> ClBs {
    var o: ClBs;
    let b = CL_INST + CL_REC * g;
    let d = mod_data[b];
    let sc = cl_f(b + 2u);
    let p0 = cl_v3(b + 4u);
    let am = cl_a(g);
    let hsr = cl_f(b + 36u);
    let jp = cl_j(d, 0u);
    let sm = ((cl_v3(b + 44u) - p0) * am) / sc;
    let h = cl_hground(1.0, 0.0, jp, sm, CL_BURY / sc, hsr);
    let hu = vec3<f32>(0.0, sin(h.th), cos(h.th));
    let he = vec3<f32>(0.0, cos(h.th), -sin(h.th));
    o.hr = am * mat3x3<f32>(he, hu, cross(he, hu));
    o.hs = sc * hsr;
    o.hp = p0 + am * (sc * h.b);
    // (the crouch each holds after the blast: cl_pose's c, the pelvis and the spine pitched over it)
    let c = min((0.9 - (0.1 + 0.35 * (cl_f(b + 34u) - 0.6)) - 0.18 * (cl_f(b + 33u) - 1.0)) * cl_f(b + 28u), 1.12);
    let post = cl_f(b + 31u);
    var xp = cl_about(cl_xf_id(), jp, cl_rx(0.36 * c + 0.04 * post));
    xp.t = xp.t + vec3<f32>(0.0, -(0.25 + 8.3 * c), 0.5 - 3.2 * c);
    let xt = cl_about(xp, cl_j(d, 1u), cl_rx(0.72 * c - 0.07 + 0.12 * post));
    var sr = cl_pos(xt, cl_j(d, 3u));
    var sl = cl_pos(xt, cl_j(d, 6u));
    let gl = h.b;
    let gr = h.b + hu * 4.0;
    let l1r = length(cl_j(d, 4u) - cl_j(d, 3u));
    let l2r = length(cl_j(d, 5u) - cl_j(d, 4u));
    let l1l = length(cl_j(d, 7u) - cl_j(d, 6u));
    let l2l = length(cl_j(d, 8u) - cl_j(d, 7u)) + 2.5;
    // (drawn on to the handle where the arms can't reach it, as cl_rig draws the body)
    for (var it = 0; it < 2; it = it + 1) {
        let dl = gl - sl;
        let s1 = dl * max(1.0 - 0.97 * (l1l + l2l) / max(length(dl), 0.01), 0.0);
        sl = sl + s1;
        sr = sr + s1;
        let dr = gr - sr;
        let s2 = dr * max(1.0 - 0.97 * (l1r + l2r) / max(length(dr), 0.01), 0.0);
        sl = sl + s2;
        sr = sr + s2;
    }
    for (var k = 0; k < 2; k = k + 1) {
        let s0 = select(sl, sr, k == 0);
        let w0 = select(gl, gr, k == 0);
        let l1 = select(l1l, l1r, k == 0);
        let l2 = select(l2l, l2r, k == 0);
        let ev = w0 - s0;
        let dd = clamp(length(ev), 0.3 * (l1 + l2), 0.999 * (l1 + l2));
        let dir = normalize(ev);
        let a = (l1 * l1 - l2 * l2 + dd * dd) / (2.0 * dd);
        let pole = xt.r * normalize(vec3<f32>(select(0.8, -0.8, k == 0), -0.5, -0.2));
        let pv = normalize(pole - dir * dot(pole, dir) + vec3<f32>(0.0, -1.0e-3, 0.0));
        let el = s0 + dir * a + pv * sqrt(max(l1 * l1 - a * a, 0.0));
        o.s[k] = p0 + am * (sc * s0);
        o.e[k] = p0 + am * (sc * el);
        o.w[k] = p0 + am * (sc * w0);
    }
    return o;
}
struct ClPc {
    p: vec3<f32>,                 // its middle now (off the target)
    r0: mat3x3<f32>,              // its grid's frame as it broke off,
    sax: vec3<f32>,               // the axis it tumbles about
    an: f32,                      // and how far it has turned (cl_pc_r: its grid to the world)
    e: vec3<f32>,                 // its box's half size (blocks)
    v: f32,                       // how big its blocks are (1 but on the bigger pieces)
    age: f32,                     // seconds since it broke off (negative: not yet)
    tl: f32,                      // when it comes down (its age)
    vel: vec3<f32>,               // how fast it is going (none once down)
    L: f32,                       // how big it is
    mesh: u32,                    // the giant's piece it came from
}
// The land a piece comes down on: the giant's own ground, or with the terrain on the crater's bowl where it reaches
// (strike/colossi.rs's `Crater::at` without its terraces: a piece set into the land hides the difference).
fn cl_dbland(xz: vec2<f32>, gy: f32) -> f32 {
    if ((cl_flags() & 8u) == 0u) {
        return gy;
    }
    let u = length(xz) / CL_CRATER;
    let fl = cl_f(4u) - 14.0 * CL_K * pow(max(1.0 - u * u, 0.0), 0.8);
    return mix(fl, gy, smoothstep(0.92, 1.05, u));
}
fn cl_dbh(i: u32, g: u32, k: u32) -> vec3<f32> {
    return vec3<f32>(pcg3d(vec3<u32>(i, g + 17u, k))) * (1.0 / 4294967295.0);
}
// Piece i of giant g, tg seconds after its burst (bs: where the hammer and arms were; gy its ground): where it is, closed-form.
fn cl_pc(g: u32, i: u32, tg: f32, bs: ClBs, gy: f32) -> ClPc {
    var o: ClPc;
    let h1 = cl_dbh(i, g, 81u);
    let h2 = cl_dbh(i, g, 82u);
    let h3 = cl_dbh(i, g, 83u);
    let cls = select(select(2u, 1u, i < 16u), 0u, i < 4u);
    // where it comes from: 0 the hammer's head, 1 its handle, 2 an arm
    var part = 2u;
    if (cls == 0u) {
        part = select(0u, 1u, i == 3u);
    } else if (cls == 1u) {
        part = select(select(2u, 1u, i < 13u), 0u, i < 10u);
    } else {
        part = select(select(2u, 1u, h1.x < 0.55), 0u, h1.x < 0.35);
    }
    let d = mod_data[CL_INST + CL_REC * g];
    var p0 = vec3<f32>(0.0);
    var x = 0.0;                                  // where on the burst's way it was (cl_chain's x)
    if (part == 2u) {
        let k = select(1u, 0u, h1.y < 0.5);
        let upper = h1.z < 0.45 && ((cl_mask(g) >> (3u + 2u * k)) & 1u) == 1u;
        let s = 0.12 + 0.8 * h2.x;
        let a = select(bs.e[k], bs.s[k], upper);
        let bb = select(bs.w[k], bs.e[k], upper);
        p0 = mix(a, bb, s) + (h3 - 0.5) * 8.0;
        x = select(1.0, 1.5, upper) + 0.5 * (1.0 - s);
        o.r0 = cl_arc(vec3<f32>(0.0, 1.0, 0.0), normalize(bb - a));
        o.mesh = CL_NB * d + 3u + 2u * k + select(1u, 0u, upper);
    } else {
        let hb = CL_MESH + 16u * 2u * CL_NB;
        let bmin = cl_v3(hb + 4u);
        let ext = cl_v3(hb + 7u);
        let hh = max(bmin.y + ext.y - 32.0, 3.0);
        var u = vec3<f32>(9.25 + (h3.x - 0.5) * 1.2, mix(bmin.y + 1.0, 32.0 - 1.1 * hh, h2.y), 4.0 + (h3.z - 0.5) * 1.2);
        if (part == 0u) {
            u = vec3<f32>(bmin.x + ext.x * (0.15 + 0.7 * h2.x), 32.0 + hh * (1.4 * h2.y - 0.7), bmin.z + ext.z * (0.15 + 0.7 * h2.z));
        }
        p0 = bs.hp + bs.hr * ((u - vec3<f32>(9.25, 7.0, 4.0)) * bs.hs);
        x = 1.0 - (u.y - 7.0) / CL_HL;
        o.r0 = bs.hr;
        o.mesh = 2u * CL_NB;
    }
    // (it goes as the burst's front passes where it was: cl_cut's)
    o.age = tg - max((x + 0.4) / 7.5 + 0.04 * h3.y, 0.0);
    // its size and shape: slabs off the head, long splinters off the handle, chunks of arm
    o.L = select(select(2.0 + 4.0 * h2.z * h2.z, 8.0 + 8.0 * h1.z, cls == 1u), 22.0 + 14.0 * h1.z, cls == 0u);
    var shp = vec3<f32>(0.85, 1.0, 0.7);
    if (part == 0u) {
        shp = vec3<f32>(1.0, 0.5 + 0.35 * h3.x, 0.7 + 0.3 * h3.z);
    } else if (part == 1u) {
        shp = vec3<f32>(0.4 + 0.15 * h3.x, 1.0, 0.4 + 0.15 * h3.z);
    }
    o.e = 0.5 * o.L * shp;
    // (at most five of its blocks each way from its middle: the walk through them stays short)
    o.v = max(1.0, ceil(max(o.e.x, max(o.e.y, o.e.z)) / 5.0 - 0.01));
    if (cls == 2u) {
        o.e = max(floor(o.e + 0.5), vec3<f32>(0.5));
    }
    // thrown out from the line it was on: the heavy slow and low, the small fast and high
    let rnd = normalize(h3 * 2.0 - 1.0 + vec3<f32>(0.0, 0.35, 0.0));
    let axw = o.r0[1];
    let side = normalize(rnd - axw * (0.85 * dot(rnd, axw)) + vec3<f32>(0.0, 1.0e-3, 0.0));
    let spd = select(select(20.0 + 34.0 * h1.y, 10.0 + 15.0 * h1.y, cls == 1u), 3.5 + 5.0 * h1.y, cls == 0u);
    let vy = select(select(12.0 + 26.0 * h2.x, 8.0 + 14.0 * h2.x, cls == 1u), 4.0 + 6.0 * h2.x, cls == 0u) + 0.4 * abs(side.y) * spd;
    let vh = side.xz * spd;
    // (down where it lands, set into the land a little: never left floating over it)
    let me = min(o.e.x, min(o.e.y, o.e.z));
    let tl0 = (vy + sqrt(vy * vy + 2.0 * CL_DBG * max(p0.y - gy, 0.0))) / CL_DBG;
    let yc = cl_dbland(p0.xz + vh * tl0, gy) + 0.1 * me;
    o.tl = (vy + sqrt(vy * vy + 2.0 * CL_DBG * max(p0.y - yc, 0.0))) / CL_DBG;
    let corr = (yc - (p0.y + vy * o.tl - 0.5 * CL_DBG * o.tl * o.tl)) / o.tl;
    let a = clamp(o.age, 0.0, o.tl);
    o.p = p0 + vec3<f32>(vh.x * a, vy * a - 0.5 * CL_DBG * a * a + corr * a, vh.y * a);
    o.vel = select(vec3<f32>(0.0), vec3<f32>(vh.x, vy + corr - CL_DBG * a, vh.y), o.age < o.tl);
    if (o.age > o.tl) {
        // (it slides on a little and settles in, stopping smoothly)
        let s = 1.0 - exp(-(o.age - o.tl) * 5.0);
        let lv = length(vh);
        o.p = o.p + vec3<f32>(vh.x, 0.0, vh.y) * (min(lv * 0.12, 0.35 * o.L) / max(lv, 1.0e-3) * s) - vec3<f32>(0.0, 0.15 * me * s, 0.0);
    }
    // tumbling as its size lets it, stopped where it lands
    o.sax = normalize(h2 - 0.5 + vec3<f32>(0.0, 1.0e-3, 0.0));
    o.an = select(select(3.0 + 5.0 * h3.y, 1.2 + 2.0 * h3.y, cls == 1u), 0.45 + 0.6 * h3.y, cls == 0u) * select(-1.0, 1.0, h1.x > 0.3) * a;
    return o;
}
// Its grid to the world, as it has turned.
fn cl_pc_r(pc: ClPc) -> mat3x3<f32> {
    let rs = mat3x3<f32>(rot_axis(vec3<f32>(1.0, 0.0, 0.0), pc.sax, pc.an), rot_axis(vec3<f32>(0.0, 1.0, 0.0), pc.sax, pc.an),
        rot_axis(vec3<f32>(0.0, 0.0, 1.0), pc.sax, pc.an));
    return pc.r0 * rs;
}
// Its four fracture planes in its grid (inside where dot(xyz, q) <= w; none on the small ones, whole blocks), and which way
// its face that was the hammer's or the arm's own surface looks (w: none).
struct ClCuts {
    q: array<vec4<f32>, 4>,
    out: vec4<f32>,
}
fn cl_pc_cuts(g: u32, i: u32, e: vec3<f32>) -> ClCuts {
    var o: ClCuts;
    for (var c = 0u; c < 4u; c = c + 1u) {
        let hc = cl_dbh(i, g, 90u + c);
        let n = normalize(hc - 0.5 + vec3<f32>(1.0e-3, 0.0, 0.0));
        o.q[c] = vec4<f32>(n, select((0.4 + 0.42 * hc.x) * dot(abs(n), e), CL_BIG, i >= 16u));
    }
    let h = cl_dbh(i, g, 85u);
    let ox = select(0u, 1u, h.x > 0.5) + select(0u, 1u, h.x > 0.8);
    o.out = vec4<f32>(select(vec3<f32>(0.0), vec3<f32>(1.0), vec3<u32>(ox) == vec3<u32>(0u, 1u, 2u)) * select(-1.0, 1.0, h.y > 0.5), 0.0);
    return o;
}
// The view ray (o, d: in the piece's grid, from its middle) through its blocks (`v` across, at most five each way from its
// middle): the cells whose middles are inside its planes `cu`, walked one by one (a DDA, at most 30 steps) to the first that is.
// t how far (CL_BIG: none), n the face's normal (its grid's).
struct ClVx {
    t: f32,
    n: vec3<f32>,
}
fn cl_vox(o: vec3<f32>, d: vec3<f32>, e: vec3<f32>, v: f32, cu: ClCuts, tmax: f32) -> ClVx {
    var r: ClVx;
    r.t = CL_BIG;
    let nb = clamp(floor(e / v + 0.5), vec3<f32>(1.0), vec3<f32>(5.0));
    let B = nb * v;
    let sd = select(d, vec3<f32>(1.0e-6), abs(d) < vec3<f32>(1.0e-6));
    let inv = 1.0 / sd;
    let ta = (-B - o) * inv;
    let tb = (B - o) * inv;
    let tn = min(ta, tb);
    let tf = max(ta, tb);
    let t0 = max(max(tn.x, tn.y), max(tn.z, 0.0));
    let t1 = min(min(tf.x, tf.y), min(tf.z, tmax));
    if (t0 >= t1) {
        return r;
    }
    var ax = select(select(2u, 1u, tn.y >= tn.z), 0u, tn.x >= tn.y && tn.x >= tn.z);
    let st = sign(sd);
    var cell = clamp(floor((o + d * (t0 + 1.0e-3 * v)) / v), -nb, nb - 1.0);
    let tdel = abs(v * inv);
    var tnext = ((cell + max(st, vec3<f32>(0.0))) * v - o) * inv;
    var tc = t0;
    for (var s = 0; s < 30; s = s + 1) {
        let c = (cell + 0.5) * v;
        let m = min(min(cu.q[0].w - dot(cu.q[0].xyz, c), cu.q[1].w - dot(cu.q[1].xyz, c)),
                    min(cu.q[2].w - dot(cu.q[2].xyz, c), cu.q[3].w - dot(cu.q[3].xyz, c)));
        if (m >= 0.0) {
            r.t = tc;
            r.n = -st * select(vec3<f32>(0.0), vec3<f32>(1.0), vec3<u32>(ax) == vec3<u32>(0u, 1u, 2u));
            return r;
        }
        if (tnext.x <= tnext.y && tnext.x <= tnext.z) {
            ax = 0u;
            tc = tnext.x;
            tnext.x = tnext.x + tdel.x;
            cell.x = cell.x + st.x;
        } else if (tnext.y <= tnext.z) {
            ax = 1u;
            tc = tnext.y;
            tnext.y = tnext.y + tdel.y;
            cell.y = cell.y + st.y;
        } else {
            ax = 2u;
            tc = tnext.z;
            tnext.z = tnext.z + tdel.z;
            cell.z = cell.z + st.z;
        }
        if (tc > t1 || any(cell < -nb) || any(cell >= nb)) {
            break;
        }
    }
    return r;
}
// The rubble the ray meets before tmax (t, normal, place on the piece, colour, broken face, heat, what is left) and its dust; at
// most CL_DBV walks of a piece's blocks a pixel, nearest first.
const CL_DBV: i32 = 4;
struct ClDb {
    n: vec3<f32>,
    t: f32,
    heat: f32,
    lp: vec3<f32>,
    col: vec3<f32>,
    fr: f32,
    a: f32,
    dust: f32,
    v: f32,
}
fn cl_debris(ro: vec3<f32>, rd: vec3<f32>, t: f32, tmax: f32) -> ClDb {
    var o: ClDb;
    o.t = tmax;
    o.dust = 0.0;
    o.a = 1.0 - smoothstep(33.0, 33.95, t);
    if (o.a <= 0.0) {
        return o;
    }
    var tr = 1.0;
    var hp: ClPc;
    var hv: ClVx;
    var hr = mat3x3<f32>(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 0.0, 1.0));
    var ho = vec4<f32>(0.0);
    var hcu: ClCuts;
    var found = false;
    var walks = 0;
    for (var g = 0u; g < CL_NG; g = g + 1u) {
        let tg = t - cl_tb(g);
        if (tg <= 0.0) {
            continue;
        }
        let b = CL_INST + CL_REC * g;
        let pt = cl_v3(b + 44u);
        let p0 = cl_v3(b + 4u);
        // (all of them are inside this ball)
        let cc = ro - (mix(pt, vec3<f32>(p0.x, pt.y, p0.z), 0.4) + vec3<f32>(0.0, 40.0, 0.0));
        let cb = dot(cc, rd);
        let cr = 150.0 + 90.0 * min(tg, 2.5);
        let cq = cb * cb - dot(cc, cc) + cr * cr;
        if (cq < 0.0 || -cb + sqrt(cq) < 0.0 || -cb - sqrt(cq) > tmax) {
            continue;
        }
        // (and between the lowest land one can lie on and the highest any can be now: from ~200 up at ~60 a second,
        // falling; once down, a low layer and their puffs)
        let gy = cl_f(b + 5u) + CL_BURY;
        let ylo = min(gy, cl_f(4u) - 14.0 * CL_K) - 30.0;
        let ta = max(tg - 0.5, 0.0);
        let yhi = gy + max(215.0 + 60.0 * max(tg, 0.0) - 14.0 * tg * tg, max(215.0 + 60.0 * ta - 14.0 * ta * ta, select(40.0, 80.0, tg < 10.5)));
        let sy = cl_yband(ro.y, rd.y, ylo, yhi);
        if (sy.x > sy.y || sy.y < 0.0 || sy.x > tmax) {
            continue;
        }
        let bs = cl_bsrc(g);
        for (var i = 0u; i < CL_DBN; i = i + 1u) {
            let pc = cl_pc(g, i, tg, bs, gy);
            if (pc.age <= 0.0) {
                continue;
            }
            let oc = ro - pc.p;
            let bb = dot(oc, rd);
            // (its dust: a thin trail behind what is flying, a low puff where a big or mid one comes down)
            if (pc.age < pc.tl) {
                let back = min(pc.age, 0.45);
                let pa = pc.p - pc.vel * back - vec3<f32>(0.0, 0.5 * CL_DBG * back * back, 0.0);
                let rs = ray_seg(rd, pa - ro, pc.p - ro);
                let w = 0.3 * pc.L + 0.8 + 2.5 * (1.0 - rs.z);
                if (rs.x < 2.5 * w && rs.y < tmax) {
                    tr = tr * (1.0 - 0.3 * exp(-rs.x * rs.x / (w * w)) * rs.z * smoothstep(0.0, 0.3, pc.age));
                }
            } else if (i < 16u && pc.age - pc.tl < 4.0) {
                let la = pc.age - pc.tl;
                let env = smoothstep(0.0, 0.08, la) * exp(-la * 0.9) * select(0.45, 0.75, i < 4u);
                let R = pc.L * (0.7 + 1.3 * (1.0 - exp(-la * 2.2)));
                tr = tr * (1.0 - cl_puff(ro, rd, tmax, pc.p + vec3<f32>(0.0, 0.25 * R, 0.0), R, 0.42, env, f32(i) * 1.7 + f32(g) * 9.1, t));
            }
            let rad = length(pc.e) + pc.v;
            let q = bb * bb - dot(oc, oc) + rad * rad;
            if (q < 0.0 || -bb - sqrt(q) > o.t || -bb + sqrt(q) < 0.0 || walks >= CL_DBV) {
                continue;
            }
            walks = walks + 1;
            let r = cl_pc_r(pc);
            let cu = cl_pc_cuts(g, i, pc.e);
            let vx = cl_vox(oc * r, rd * r, pc.e, pc.v, cu, o.t);
            if (vx.t < o.t) {
                o.t = vx.t;
                hp = pc;
                hv = vx;
                hr = r;
                ho = cu.out;
                hcu = cu;
                found = true;
            }
        }
    }
    o.dust = 1.0 - tr;
    if (found) {
        o.n = normalize(hr * hv.n);
        o.lp = (ro - hp.p + rd * o.t) * hr;
        // (a broken face: one along a fracture plane, its block at the plane; on a small one the face opposite its own
        // surface. The rest stays stone)
        let cc = (floor(o.lp / hp.v - hv.n * 0.5) + 0.5) * hp.v;
        var brk = 0.0;
        for (var c = 0u; c < 4u; c = c + 1u) {
            let qn = hcu.q[c];
            if (qn.w < 1.0e29) {
                brk = max(brk, smoothstep(0.3, 0.6, dot(hv.n, qn.xyz)) * (1.0 - smoothstep(0.7 * hp.v, 1.6 * hp.v, qn.w - dot(qn.xyz, cc))));
            }
        }
        o.fr = select(brk, select(0.0, 1.0, dot(hv.n, ho.xyz) < -0.5), hcu.q[0].w >= 1.0e29);
        o.heat = exp(-hp.age * 0.85);
        o.v = hp.v;
        // (its stone: the colour of one of the mesh's own triangles, picked by the piece)
        let hb = CL_MESH + 16u * hp.mesh;
        let ntri = max(mod_data[hb + 2u], 1u);
        let tri = mod_data[hb + 1u] + (pcg(u32(hp.L * 977.0) + hp.mesh * 131u) % ntri) * 2u;
        let k = cl_rgba(mod_data[mod_data[hb + 3u] + (mod_data[tri] & 0xFFFFu) * 3u + 2u]);
        let gr = dot(k.rgb, vec3<f32>(0.3, 0.5, 0.2));
        // (the stone's grey, never the glow's green if the triangle picked was one of the cracks')
        let gx = saturate((k.g - max(k.r, k.b)) * 5.0);
        o.col = mix(k.rgb, vec3<f32>(gr), max(0.35 + 0.4 * k.a, gx)) * 0.9;
    }
    return o;
}

// The burst's smoke: a torn shell of dust out from the hammer's and arms' line, lit through itself, sheared by the wind, gone in
// ~7 s. Premultiplied colour and coverage; at most 14 steps a giant's ball the ray meets.
fn cl_bsden(q: vec3<f32>, A: vec3<f32>, B: vec3<f32>, C: vec3<f32>, tg: f32, sc: f32, fine: bool) -> vec3<f32> {
    let ab = B - A;
    let u1 = clamp(dot(q - A, ab) / max(dot(ab, ab), 1.0), 0.0, 1.0);
    let d1 = length(q - A - ab * u1);
    let bc = C - B;
    let u2 = clamp(dot(q - B, bc) / max(dot(bc, bc), 1.0), 0.0, 1.0);
    let d2 = length(q - B - bc * u2);
    // (where on the burst's way the nearest of it is, and so how long ago it burst there: cl_cut's front)
    let x = select(1.0 + u2, u1, d1 < d2);
    let a = tg - (x + 0.4) / 7.5;
    if (a <= 0.0) {
        return vec3<f32>(0.0, a, 1.0);
    }
    // (the head's end the thickest)
    let R = sc * (1.5 + 6.5 * (1.0 - exp(-a * 2.4)) + 1.2 * a) * (1.0 + 0.45 * (1.0 - min(x, 1.0)));
    let n = gfbm3(q * (0.2 / sc) + vec3<f32>(0.0, -0.35 * a, 0.0), select(1, 3, fine));
    let dd = (min(d1, d2) + (n - 0.5) * R * 1.25) / R;
    if (dd > 1.0) {
        return vec3<f32>(0.0, a, dd);
    }
    var den = smoothstep(1.0, 0.72, dd) * (0.2 + 0.8 * smoothstep(0.2, 0.8, dd));
    if (fine) {
        // (eaten through more as it thins: holes, then rags)
        let m = gnoise3(q * (0.32 / sc) + vec3<f32>(3.0, -0.8 * a, 7.0));
        den = den * saturate((m - 0.22 - 0.3 * (1.0 - exp(-a * 0.5))) * 3.0);
    }
    return vec3<f32>(den * exp(-a * 0.45) * (1.0 - smoothstep(4.5, 7.5, a)), a, dd);
}
fn cl_bsmoke(ro: vec3<f32>, rd: vec3<f32>, t: f32, tmax: f32, jit: f32, dist: ptr<function, f32>) -> vec4<f32> {
    var acc = vec4<f32>(0.0);
    var dw = 0.0;
    var dn0 = 0.0;
    let sun = frame.sun.xyz;
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    let day = saturate(sun.y * 2.5 + 0.35);
    let wind = vec3<f32>(0.85, 0.0, 0.5);
    for (var g = 0u; g < CL_NG; g = g + 1u) {
        let tg = t - cl_tb(g);
        if (tg <= 0.0 || tg > 7.8) {
            continue;
        }
        let b = CL_INST + CL_REC * g;
        let sc = cl_f(b + 2u);
        let gy = cl_f(b + 5u) + CL_BURY;
        let pt = cl_v3(b + 44u);
        let p0 = cl_v3(b + 4u);
        // (the ball it is all inside, drifting with it)
        let dr = wind * (4.0 * tg) + vec3<f32>(0.0, sc * 1.6 * tg, 0.0);
        let ce = mix(pt, vec3<f32>(p0.x, pt.y, p0.z), 0.4) + vec3<f32>(0.0, 35.0, 0.0) + dr;
        let cr = 110.0 + sc * 16.0 * min(tg, 4.0);
        let oc = ro - ce;
        let bb = dot(oc, rd);
        let q0 = bb * bb - dot(oc, oc) + cr * cr;
        if (q0 <= 0.0) {
            continue;
        }
        if (max(-bb - sqrt(q0), 0.0) >= min(-bb + sqrt(q0), tmax)) {
            continue;
        }
        let bs = cl_bsrc(g);
        let A = bs.hp + bs.hr[1] * (25.0 * bs.hs);
        let B = bs.hp;
        let C = 0.5 * (bs.s[0] + bs.s[1]);
        // (the march only over the stretch of the ray near the two lines, drifted as the smoke has, by their widest)
        let dm = wind * (tg * (3.0 + 0.05 * max(0.5 * (B.y + C.y) - gy, 0.0))) + vec3<f32>(0.0, sc * 1.6 * tg, 0.0);
        let Rm = sc * (8.0 + 1.2 * tg) * 1.45 * 1.4 + 6.0;
        let ra = ray_seg(rd, A + dm - ro, B + dm - ro);
        let rb = ray_seg(rd, B + dm - ro, C + dm - ro);
        let sa = sqrt(max(Rm * Rm - ra.x * ra.x, 0.0)) / max(length(cross(rd, normalize(B - A))), 0.35);
        let sb = sqrt(max(Rm * Rm - rb.x * rb.x, 0.0)) / max(length(cross(rd, normalize(C - B))), 0.35);
        var s0 = 1.0e9;
        var s1 = 0.0;
        if (ra.x < Rm) {
            s0 = ra.y - sa;
            s1 = ra.y + sa;
        }
        if (rb.x < Rm) {
            s0 = min(s0, rb.y - sb);
            s1 = max(s1, rb.y + sb);
        }
        s0 = max(s0, 0.0);
        s1 = min(s1, tmax);
        if (s1 <= s0) {
            continue;
        }
        let ds = (s1 - s0) / 14.0;
        var tr = 1.0;
        var col = vec3<f32>(0.0);
        for (var i = 0; i < 14; i = i + 1) {
            let p = ro + rd * (s0 + ds * (f32(i) + jit));
            // (carried off downwind, the higher the further: sheared; and rising a little)
            let hgt = max(p.y - gy, 0.0);
            let q = p - wind * (tg * (3.0 + 0.05 * hgt)) - vec3<f32>(0.0, sc * 1.6 * tg, 0.0);
            let dn = cl_bsden(q, A, B, C, tg, sc, true);
            if (dn.x <= 0.002) {
                continue;
            }
            // (its own shadow: the shape a little way towards the sun)
            let sh = cl_bsden(q + L * (sc * 5.0), A, B, C, tg, sc, false).x;
            let lit = exp(-sh * 2.6);
            let a = 1.0 - exp(-dn.x * ds * 0.09);
            let alb = vec3<f32>(0.25, 0.22, 0.185) * (0.75 + 0.25 * smoothstep(0.2, 0.9, dn.z));
            var c = alb * (0.1 + 0.16 * day + 0.85 * day * lit) + vec3<f32>(0.01, 0.012, 0.016) * (1.0 - day);
            // (green from inside, only as it opens)
            c = c + vec3<f32>(0.12, 1.0, 0.45) * (2.6 * exp(-dn.y * 6.0) * (1.0 - smoothstep(0.1, 0.9, dn.z)));
            col = col + c * a * tr;
            dw = dw + a * tr;
            dn0 = dn0 + a * tr * (s0 + ds * f32(i));
            tr = tr * (1.0 - a);
            if (tr < 0.02) {
                break;
            }
        }
        acc = vec4<f32>(acc.rgb + col * (1.0 - acc.a), acc.a + (1.0 - acc.a) * (1.0 - tr));
    }
    *dist = select(CL_BIG, dn0 / max(dw, 1.0e-4), dw > 0.0);
    return acc;
}

fn cl_flash(ro: vec3<f32>, rd: vec3<f32>, t: f32, scene_len: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    for (var g = 0u; g < CL_NG; g = g + 1u) {
        let b = CL_INST + CL_REC * g;
        let t2 = cl_f(b + 23u);
        let tt = t - select(cl_f(b + 10u), t2, t >= t2);
        let tg = t - cl_tb(g);
        if (tt < 0.0 || (tt > 1.2 && t < CL_CHARGE) || tg > 1.6) {
            continue;
        }
        var pt = cl_v3(b + 44u);
        // (the blow's flash; the hammer's head brightening as it charges; the burst, from its hands)
        var r = 14.0 + 90.0 * (1.0 - exp(-tt * 9.0));
        var amp = select(2.0, 1.25, t >= t2) * exp(-tt * 3.6) * smoothstep(0.0, 0.03, tt);
        if (t > CL_CHARGE) {
            // (the charge: its light climbs from the head up the handle and the arms with the front cl_render's surface
            // draws; then the burst: a hard green-white line all along them, gone in a fifth of a second, and a softer glow
            // round the hands a little longer)
            let x = saturate((t - CL_CHARGE) / (cl_tb(g) - CL_CHARGE));
            let sc = cl_f(b + 2u);
            // (charging, its light a ball sc (4 + 5 x) wide on the hammer or the arms, within 64 sc of the pelvis: a ray
            // passing that by three times its width has none of it worth a shade)
            if (tg <= 0.0) {
                let pv = cl_v3(b + 4u) + cl_a(g) * (cl_j(mod_data[b], 0u) * sc) - ro;
                let ds = pv - rd * clamp(dot(pv, rd), 0.0, scene_len);
                if (length(ds) > sc * (64.0 + 3.0 * (4.0 + 5.0 * x))) {
                    continue;
                }
            }
            let bs = cl_bsrc(g);
            let A = bs.hp + bs.hr[1] * (25.0 * bs.hs);
            let C = 0.5 * (bs.s[0] + bs.s[1]);
            let pr = -0.4 + 2.6 * x * x * (3.0 - 2.0 * x);
            pt = select(mix(bs.hp, C, saturate(pr - 1.0)), mix(A, bs.hp, saturate(pr)), pr < 1.0);
            r = sc * (4.0 + 5.0 * x);
            amp = 0.55 * x * x * (1.0 - step(0.0, tg));
            if (tg > 0.0) {
                let wl = sc * (2.5 + 9.0 * (1.0 - exp(-tg * 10.0)));
                let l1 = ray_seg(rd, A - ro, bs.hp - ro);
                let l2 = ray_seg(rd, bs.hp - ro, C - ro);
                let dl = min(select(1.0e9, l1.x, l1.y < scene_len), select(1.0e9, l2.x, l2.y < scene_len));
                col = col + vec3<f32>(0.75, 1.0, 0.8) * (1.5 * exp(-tg * 9.0) * smoothstep(0.0, 0.03, tg)) * exp(-dl * dl / (wl * wl));
                r = sc * (10.0 + 14.0 * (1.0 - exp(-tg * 6.0)));
                amp = 0.5 * exp(-tg * 4.0);
                pt = bs.hp;
            }
        }
        let oc = ro - pt;
        let bb = dot(oc, rd);
        let pc = oc + rd * clamp(-bb, 0.0, scene_len);
        col = col + vec3<f32>(0.8, 1.0, 0.75) * amp * exp(-dot(pc, pc) / (r * r));
    }
    // (the blast in the middle, where the cracks met)
    // a swelling of light low over the ground as the cracks close in; one hard flash, gone in about a fifth of a second
    // (never a long white-out: by night it is held down, so the picture keeps its shapes); then the core's green light,
    // low in the crater, under the crown and the column it lights
    let th = t - CL_HIT;
    if (th > -1.0 && th < 7.0) {
        let gy = cl_f(4u);
        let expo = 0.3 + 0.7 * saturate(frame.sun.y * 2.5 + 0.35);
        var amp = 0.0;
        var r = 1.0;
        var y = gy + 8.0;
        if (th <= 0.0) {
            let b = 1.0 + th;
            amp = 0.9 * b * b * b;
            r = 25.0 + 45.0 * b;
        } else {
            amp = 1.5 * exp(-th * 1.1) * (0.85 + 0.15 * sin(th * 23.0)) * smoothstep(0.0, 0.05, th);
            r = 60.0 + 70.0 * (1.0 - exp(-th * 2.0));
            y = gy + 20.0 + 25.0 * (1.0 - exp(-th));
            // (the flash: a blinding core over the crater and a glare round it, the glare only so wide)
            let ofl = ro - vec3<f32>(0.0, gy + 30.0, 0.0);
            let pf = ofl + rd * clamp(-dot(ofl, rd), 0.0, scene_len);
            let d2 = dot(pf, pf);
            let rc = 50.0 + 90.0 * (1.0 - exp(-th * 10.0));
            let rg = 220.0 + 360.0 * (1.0 - exp(-th * 12.0));
            col = col + vec3<f32>(0.85, 1.0, 0.9) * smoothstep(0.0, 0.02, th) * select(1.0, 0.2, cl_soft()) * (6.0 * exp(-th / 0.09) * exp(-d2 / (rc * rc))
                + 0.9 * expo * expo * exp(-th / 0.07) * exp(-d2 / (rg * rg)));
        }
        let oc = ro - vec3<f32>(0.0, y, 0.0);
        let pc = oc + rd * clamp(-dot(oc, rd), 0.0, scene_len);
        col = col + vec3<f32>(0.3, 1.0, 0.55) * amp * expo * exp(-dot(pc, pc) / (r * r));
    }
    return col;
}

// Embers over the crater after the blast: a few green sparks lifting off its floor on the heat, swaying, each living a few
// seconds and fading in and out, until the end. Light along the ray (soft points, dimmer and wider far off: no speckle).
fn cl_motes(ro: vec3<f32>, rd: vec3<f32>, t: f32, scene_len: f32) -> vec3<f32> {
    let tt = t - CL_HIT;
    if (tt < 0.8 || tt > 13.9) {
        return vec3<f32>(0.0);
    }
    let gy = cl_f(4u);
    // (all of them are in this cylinder over the crater, their glow too: a ray that misses it has none)
    let bc = cl_cyl(ro, rd, vec2<f32>(0.0), 175.0, gy - 10.0, gy + 100.0);
    if (bc.y <= bc.x || bc.x > scene_len) {
        return vec3<f32>(0.0);
    }
    var col = vec3<f32>(0.0);
    for (var i = 0; i < 24; i = i + 1) {
        let fi = f32(i);
        let per = 4.0 + 2.5 * fract(fi * 0.618034);
        let ph = (tt - 0.8) / per + fract(fi * 0.381966);
        let a = fract(ph);
        if (tt - 0.8 < a * per) {
            continue;
        }
        let cyc = floor(ph);
        let h1 = hash21(vec2<f32>(fi, cyc + 3.0));
        let h2 = hash21(vec2<f32>(cyc + 11.0, fi));
        let r0 = 135.0 * sqrt(h1);
        let an = h2 * TAU;
        let up = a * per * (5.0 + 7.0 * h2);
        let w = cl_drift(up, tt) * 0.5 + vec2<f32>(sin(a * 5.0 + fi), cos(a * 4.0 + fi * 1.7)) * 6.0;
        let pm = vec3<f32>(cos(an) * r0 + w.x, gy + 3.0 + up, sin(an) * r0 + w.y);
        let oc = ro - pm;
        let s = clamp(-dot(oc, rd), 0.0, scene_len);
        let e = oc + rd * s;
        let rad = max(0.9, s * 0.0022);
        col = col + vec3<f32>(0.35, 1.0, 0.55) * (1.3 * exp(-dot(e, e) / (rad * rad)) * (0.81 / (rad * rad)) * sin(a * 3.14159));
    }
    return col * (1.0 - smoothstep(31.5, 33.9, t));
}

// ---- the earth that comes up with them: soil on the stone, dirt pouring off whatever overhangs, dust where a part breaks ground ----
// How long ago the height y of giant g came up through its ground (it rises straight up; the heaves' catches left out).
fn cl_age(g: u32, t: f32, y: f32) -> f32 {
    let b = CL_INST + CL_REC * g;
    let span = 56.0 * cl_f(b + 2u);
    let x = clamp(1.0 - (y - cl_f(b + 5u) - CL_BURY) / span - (1.0 - cl_rise(g, t)), 0.0, 1.0);
    return t - cl_f(b + 9u) - CL_RISE * (0.5 - sin(asin(1.0 - 2.0 * x) / 3.0));
}
// One stream of dirt falling from `e` (a point inside the stone: what shows is what leaves its underside), begun `a` seconds
// ago and fed for `dur`, `h0` under `e` where it leaves the stone: x how much of the view it hides, y how far along the ray it is.
fn cl_strm(ro: vec3<f32>, rd: vec3<f32>, e: vec3<f32>, e0: vec2<f32>, gy: f32, a: f32, dur: f32, wd: f32, seed: f32, h0: f32) -> vec2<f32> {
    let G = 26.0;
    let late = max(a - dur, 0.0);
    let top = e.y - 0.5 * G * late * late;
    let bot = max(e.y - h0 - 0.5 * G * a * a, gy);
    let aa = dot(rd.xz, rd.xz);
    if (a <= 0.0 || top <= bot || aa < 1.0e-5) {
        return vec2<f32>(0.0, 1.0e9);
    }
    // (dirt that left the stone `tau` in falls from where the stone was then, between e0 as the stream began and e now: a
    // stream from a hammer heaved up again trails back to where it lifted from, not hung under it)
    let s1 = dot(e.xz - ro.xz, rd.xz) / aa;
    let tau1 = a - sqrt(2.0 * max(e.y - ro.y - rd.y * s1 - h0, 0.0) / G);
    let c = mix(e0, e.xz, saturate(tau1 / max(a, 1.0e-3)));
    let s = dot(c - ro.xz, rd.xz) / aa;
    let y = ro.y + rd.y * s;
    if (s <= 0.0 || y > top || y < bot) {
        return vec2<f32>(0.0, 1.0e9);
    }
    let d = e.y - y;
    // (wider the further it has fallen, and billowing out where it comes down on the ground)
    let land = select(0.0, exp(-(y - gy) / (7.0 * wd)), bot <= gy + 0.01);
    let w = wd * min(0.5 + 0.016 * d, 1.8) * (1.0 + 2.2 * land);
    // (it wavers as it falls, more the further down, and drifts a little downwind)
    let sway = vec2<f32>(vnoise3(vec3<f32>(d * 0.045, seed, a * 0.5)), vnoise3(vec3<f32>(seed, d * 0.045, a * 0.5 + 9.0))) - 0.5;
    let dx = length(ro.xz + rd.xz * s - c - sway * min(d * 0.09, 7.0) * wd - vec2<f32>(0.035, 0.02) * d);
    if (dx > 3.6 * w) {
        return vec2<f32>(0.0, 1.0e9);
    }
    // (what is here left the stone `tau` seconds after the stream began: it comes in clumps, and thins as it falls faster)
    let tau = a - sqrt(2.0 * max(d - h0, 0.0) / G);
    let clump = vnoise3(vec3<f32>(tau * 3.3, seed * 7.1, d * 0.07 + seed));
    let fed = smoothstep(0.0, 0.35, tau) * (1.0 - smoothstep(0.25 * dur, dur, tau));
    let thin = 1.0 / (1.0 + 0.014 * sqrt(2.0 * G * d));
    let ends = saturate((top - y) * 0.4) * saturate((y - bot) * 0.3 + select(0.0, 1.0, bot <= gy + 0.01));
    let q = dx * dx / (w * w);
    return vec2<f32>(min((exp(-q) * (0.35 + 0.65 * clump) + 0.4 * exp(-q * 0.16)) * fed * (thin + 0.5 * land) * ends * 1.4, 0.95), s);
}
// Which side of a stream from `e` the ray (ro, rd) passes at s: 1 the side the sun is on, -1 the far side.
fn cl_strm_side(ro: vec3<f32>, rd: vec3<f32>, e: vec3<f32>, s: f32) -> f32 {
    let off = ro.xz + rd.xz * s - e.xz;
    let sun = frame.sun.xyz;
    let L = select(-sun, sun, sun.y > -0.04);
    return dot(off / max(length(off), 0.3), normalize(L.xz + vec2<f32>(1.0e-4)));
}
// Giant g's falling dirt and the dust its parts raise as they break ground (its pieces as cl_rig left them): x the streams,
// y how far the nearest of them is, z the dust.
fn cl_falls(g: u32, t: f32, pi: ptr<function, array<ClInst, 14>>, ro: vec3<f32>, rd: vec3<f32>, tmax: f32) -> vec4<f32> {
    let b = CL_INST + CL_REC * g;
    let d = mod_data[b];
    let sc = cl_f(b + 2u);
    let gy = cl_f(b + 5u) + CL_BURY;
    let t1 = cl_f(b + 10u);
    let t2 = cl_f(b + 23u);
    let fg = f32(g);
    var tr_s = 1.0;
    var near = 1.0e9;
    // the streams: off the hammer's head and handle, the arms, the hands and the chin, from when each clears the ground, and
    // again, shorter, shaken loose by each blow
    let blow = select(t1, t2, t >= t2);
    // (no stream rides a part that moves: what pours off it as it rises is gone before it reaches for
    // its hammer for the first blow (cl_pose's prep, 3.75 leads before); what the first blow shakes loose before it reaches
    // for it again; what the second shakes off the arms and head before they come up to watch the cracks meet (cl_pose's
    // bm). The hammer itself lies still from the second blow till it bursts.)
    let quiet1 = 1.0 - smoothstep(t1 - 3.75 * cl_f(b + 26u) - 0.6, t1 - 3.75 * cl_f(b + 26u) + 0.1, t);
    let tm = max(t2 - 3.75 * cl_f(b + 27u), t1);
    let quiet2 = select(1.0 - smoothstep(tm - 0.2, tm + 0.4, t), 1.0, t >= t2);
    let tb = CL_HIT - 1.5 + 0.9 * (1.0 - cl_f(b + 34u));
    let quiet3 = 1.0 - smoothstep(tb - 0.3, tb + 0.4, t);
    let wd = 0.8 * sc;
    var lsum = 0.0;
    var lw = 0.0;
    // (how far the hammer's head has come since it was driven in: what poured off it after a blow fell from back there)
    var dl = vec2<f32>(0.0);
    if (t >= t1 && !cl_gone(g, 13u, t)) {
        let hm = (*pi)[13u];
        dl = (hm.p + hm.r * (vec3<f32>(9.25, 34.9, 4.0) * hm.s)).xz - cl_v3(b + 44u).xz;
    }
    for (var i = 0u; i < 23u; i = i + 1u) {
        var k = 13u;
        var v = vec3<f32>(9.25, 7.0 + 5.0 * f32(i), 4.0);
        // (15 on: the hammer's head, its eight corners: whichever way it lies, what pours off its overhangs)
        let j = i - 15u;
        if (i >= 15u) {
            v = vec3<f32>(select(1.2, 17.3, (j & 1u) == 1u), select(32.3, 37.5, (j & 2u) == 2u), select(1.0, 7.0, (j & 4u) == 4u));
        }
        switch i {
            case 4u { v = vec3<f32>(3.2, 32.0, 4.0); }
            case 5u { v = vec3<f32>(15.3, 32.0, 4.0); }
            case 6u { v = vec3<f32>(9.25, 32.0, 4.0); }
            case 7u { k = 3u; v = 0.5 * (cl_j(d, 3u) + cl_j(d, 4u)); }
            case 8u { k = 4u; v = cl_j(d, 4u); }
            case 9u { k = 4u; v = 0.5 * (cl_j(d, 4u) + cl_j(d, 5u)); }
            case 10u { k = 4u; v = cl_j(d, 5u); }
            case 11u { k = 5u; v = 0.5 * (cl_j(d, 6u) + cl_j(d, 7u)); }
            case 12u { k = 6u; v = cl_j(d, 7u); }
            case 13u { k = 6u; v = 0.5 * (cl_j(d, 7u) + cl_j(d, 8u)); }
            case 14u { k = 2u; }
            default {}
        }
        if (cl_gone(g, k, t)) {
            continue;
        }
        let ins = (*pi)[k];
        var e = ins.p + ins.r * (v * ins.s);
        if (i == 14u) {
            e = ins.c;
        }
        let up = smoothstep(gy + 1.0, gy + 7.0, e.y);
        if (up <= 0.0) {
            continue;
        }
        // (nothing of it near this ray: the cheap way out)
        // (the arms and the head move less with the hammer than its own head does)
        let wk = select(select(select(0.25, 0.5, k == 3u || k == 5u), 0.85, k == 4u || k == 6u), 1.0, k == 13u);
        let e0 = e.xz - dl * wk;
        let sx = dot(e.xz - ro.xz, rd.xz) / max(dot(rd.xz, rd.xz), 1.0e-5);
        if (sx <= 0.0 || ro.y + rd.y * sx > e.y || length(ro.xz + rd.xz * sx - e.xz) > 14.0 * wd + 8.0 + length(dl) * wk) {
            continue;
        }
        let sd = fg * 5.0 + f32(i);
        let h = hash31(vec3<f32>(sd, 1.37, 0.5));
        let head = (i >= 4u && i <= 6u) || i >= 15u;
        let h0 = sc * select(select(1.0, 3.2, head), 0.8, i >= 15u);
        // (off the head's overhangs in sheets, wider)
        let wdi = wd * select(1.0, 0.75, i >= 15u);
        var r1 = vec2<f32>(0.0, 1.0e9);
        if (quiet1 > 0.0) {
            r1 = cl_strm(ro, rd, e, e.xz, gy, cl_age(g, t, e.y) - 0.25 * h, 4.5 + 4.5 * h, wdi, sd, h0);
        }
        let a2 = t - blow;
        let dur2 = 0.9 + 0.7 * h;
        let k2 = 0.85 * select(quiet2, select(quiet3, 1.0, k == 13u), t >= t2);
        var r2 = vec2<f32>(0.0, 1.0e9);
        if (k2 > 0.0) {
            r2 = cl_strm(ro, rd, e, e0, gy, a2, dur2, wdi, sd + 31.0, h0);
        }
        let x1 = r1.x * quiet1 * up * select(1.0, 1.25, head) * select(1.0, 0.8, i >= 15u);
        let x2 = r2.x * up * k2;
        if (x1 > 0.0 && r1.y < tmax) {
            tr_s = tr_s * (1.0 - x1);
            near = min(near, r1.y);
            lsum = lsum + x1 * cl_strm_side(ro, rd, e, r1.y);
            lw = lw + x1;
        }
        if (x2 > 0.0 && r2.y < tmax) {
            tr_s = tr_s * (1.0 - x2);
            near = min(near, r2.y);
            lsum = lsum + x2 * cl_strm_side(ro, rd, e, r2.y);
            lw = lw + x2;
        }
    }
    return vec4<f32>(1.0 - tr_s, near, 0.0, lsum / max(lw, 1.0e-4));
}

// This stage's pixel (set by the entry points) and the marches' jitter: white noise on the pixel grid, new each frame (an
// IGN's diagonal structure showed as a hatching through the few steps, and off the pixel grid it beat into a moire).
var<private> cl_px: vec2<f32>;
fn cl_jit(salt: f32) -> f32 {
    return fract(fh31(vec3<f32>(cl_px, frame.time.y - 1024.0 * floor(frame.time.y / 1024.0))) + salt);
}
fn cl_render(uv: vec2<f32>, t: f32, flags: u32) -> ClOut {
    var out: ClOut;
    out.c = vec4<f32>(0.0);
    out.e = vec4<f32>(1.0e9, 0.0, 1.0e9, 0.0);
    if (arrayLength(&mod_data) < 512u || mod_data[0] != 0xC0105510u) {
        return out;
    }
    let d = depth_at(uv);
    let sky = is_sky(d);
    let anchor = vec3<f32>(frame.mod_params[1].x, 0.0, frame.mod_params[1].y);
    let ro = frame.camera_position.xyz - anchor;
    let rd = normalize(world_offset(uv, 0.5));
    let scene_len = select(1.0e9, length(world_offset(uv, d)), !sky);
    out.e.z = scene_len;
    let cy = cl_f(4u);
    var best = scene_len;
    var hit_k = 99u;
    var hit_tri = 0u;
    var hit_uv = vec2<f32>(0.0);
    var hit_ins: ClInst;
    var pieces: array<ClInst, 14>;
    var mn = vec3<f32>(0.0);
    var falls: array<vec4<f32>, 5>;
    for (var g = 0u; g < CL_NG; g = g + 1u) {
        let md = cl_mound(g, t);
        // (with the terrain on, only a circle that reaches into the crater has anything drawn in it)
        let r1 = 19.5 * md.sc + 2.0;
        var mh = vec4<f32>(0.0, 1.0, 0.0, CL_BIG);
        if (md.real < 0.5 || length(md.o) - r1 < CL_CRATER + 2.0) {
            mh = cl_mtrace(md, md.o, r1, ro, rd, best - 0.3);
        }
        if (mh.w < best) {
            best = mh.w;
            hit_k = 98u;
            mn = mh.xyz;
        }
        var mh2 = vec4<f32>(0.0, 1.0, 0.0, CL_BIG);
        if (md.real < 0.5 || length(md.o2) - md.r2 < CL_CRATER + 2.0) {
            mh2 = cl_mtrace(md, md.o2, md.r2, ro, rd, best - 0.3);
        }
        if (mh2.w < best) {
            best = mh2.w;
            hit_k = 98u;
            mn = mh2.xyz;
        }
    }
    for (var g = 0u; g < CL_NG; g = g + 1u) {
        if (!cl_coarse(g, t, ro, rd, best)) {
            continue;
        }
        cl_rig(g, t, &pieces);
        for (var k = 0u; k < CL_NP; k = k + 1u) {
            if (cl_gone(g, k, t)) {
                continue;
            }
            let ins = pieces[k];
            let oc = ro - ins.c;
            let b = dot(oc, rd);
            let disc = b * b - (dot(oc, oc) - ins.rad * ins.rad);
            if (disc < 0.0) {
                continue;
            }
            let sq = sqrt(disc);
            if (-b + sq < 0.0 || -b - sq > best) {
                continue;
            }
            let h = cl_trace(ins, ro, rd, best, false, t, flags);
            if (h.tri != 0u) {
                best = h.t;
                hit_k = k;
                hit_tri = h.tri;
                hit_uv = h.uv;
                hit_ins = ins;
            }
        }
        if (t < 24.0) {
            falls[g] = cl_falls(g, t, &pieces, ro, rd, best);
        }
    }
    let db = cl_debris(ro, rd, t, best);
    if (db.t < best) {
        best = db.t;
        hit_k = 97u;
    }
    let sun = frame.sun.xyz;
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    var glow = vec3<f32>(0.0);
    let day = saturate(sun.y * 2.5 + 0.35);
    let skyc = mix(vec3<f32>(0.02, 0.025, 0.035), srgb_to_linear(frame.sky_color.rgb) * 0.7 + vec3<f32>(0.03), day);
    let sunc = vec3<f32>(1.3, 1.22, 1.08) * smoothstep(-0.12, 0.06, sun.y);
    // (the night's own light, about what the game leaves on its land: without it the heaved earth is a black hole in it)
    let nightc = vec3<f32>(0.075, 0.09, 0.13) * (1.0 - smoothstep(-0.2, 0.1, sun.y));
    // (the day's light as the game's lightmap gives it: full by mid-morning, dimming through dusk)
    let dl = smoothstep(-0.2, 0.25, sun.y);
    if (hit_k == 98u) {
        // the heaved earth: torn soil and stone, a block at a time
        let wp = ro + rd * best;
        let bp = floor(wp - mn * 0.5);
        // (in its plate's family, as the blocks are: strike/colossi.rs's `hv_chunk`; the nearest giant's plates)
        var gn = 0u;
        var dn = CL_BIG;
        for (var g = 0u; g < CL_NG; g = g + 1u) {
            let dg = length(wp.xz - cl_v3(CL_INST + CL_REC * g + 4u).xz);
            if (dg < dn) {
                dn = dg;
                gn = g;
            }
        }
        let hm = cl_mound(gn, t);
        let hw = wp.xz - hm.o;
        let fr = cl_frac(11u + gn, hw / CL_K);
        let near = max(0.22 + 0.73 * (1.0 - smoothstep(4.0, 12.0, fr.dj)), 0.6 * (1.0 - smoothstep(0.0, 3.5, cl_mshape(hm, hw).y)));
        let p4 = fract(fr.p * 31.7 + fr.p2 * 17.3);
        var fam = 3u + min(u32(fract(p4 * 7.1) * 5.0), 4u);
        if (fr.x < 1.8) {
            fam = 0u;
        } else if (fr.ring < 0.9) {
            fam = select(2u, 0u, near > 0.5);
        } else if (p4 < near) {
            fam = min(u32(fr.p2 * 3.0), 2u);
        }
        let mi = 0.8 * cl_vs(hm.seed ^ 0x41u, bp.xz * 0.3) + 0.2 * hash31(bp + vec3<f32>(3.0));
        var alb = cl_heapcol(fam, select(select(2u, 1u, mi < 0.75), 0u, mi < 0.5)) * 0.85;
        // (made of what was there: its top the land's own surface, the earth under it tinted to the land's; the colours
        // the plan read, HV_COL in strike/colossi.rs, once it has)
        let lw = vec2<u32>(mod_data[CL_HV_COL + 2u * gn], mod_data[CL_HV_COL + 2u * gn + 1u]);
        if ((lw.x >> 24u) == 255u) {
            let su = vec3<f32>(f32(lw.x & 255u), f32((lw.x >> 8u) & 255u), f32((lw.x >> 16u) & 255u)) / 255.0;
            let un = vec3<f32>(f32(lw.y & 255u), f32((lw.y >> 8u) & 255u), f32((lw.y >> 16u) & 255u)) / 255.0;
            let ctop = hm.gy + cl_mh(hm, vec2<i32>(floor((wp.xz - mn.xz * 0.01) * 0.5)));
            let is_top = mn.y > 0.5 || wp.y > ctop - 1.0;
            alb = select(mix(alb, un * 0.85 * (0.8 + 0.4 * mi), select(0.6, 0.3, fam < 3u)), su * 0.9, is_top && mn.y > -0.5 && fam >= 3u);
        }
        let tex = hash31(floor((wp - mn * 0.01) * 4.0));
        alb = srgb_to_linear(alb * (0.86 + 0.24 * mix(0.5, tex, 1.0 - smoothstep(150.0, 500.0, best))));
        var lit = max(dot(mn, L), 0.0);
        if (lit > 0.0 && sun.y > -0.12 && (flags & 2u) != 0u) {
            lit = lit * (1.0 - cl_shadow(wp + mn * 0.3, L, t, flags));
        }
        let amb = skyc * mix(0.5, 1.0, mn.y) * (0.55 + 0.45 * abs(mn.z));
        // (the cracks' glow on it from low down: the walls of a crack lit near its foot, not up their whole height)
        let col = alb * (cl_mcface(mn) * dl * (0.85 + 0.2 * lit) + nightc * (0.55 + 0.45 * mn.y) * (0.8 + 0.2 * abs(mn.z))) + cl_ground(wp, t) * 0.35 * exp(-max(wp.y - hm.gy, 0.0) / 3.0)
            + alb * vec3<f32>(0.55, 1.0, 0.7) * cl_blast_lit(wp, mn, t, cy, 0.2);
        out.c = vec4<f32>(mix(col, srgb_to_linear(frame.fog_color.rgb), 1.0 - exp(-best * 0.0003)), 1.0);
        out.e.x = best;
    } else if (hit_k == 97u) {
        // a piece of the burst: the giant's own stone in blocks, a grain a block wide, the blocks' edges a little darker;
        // paler and green-hot on its broken faces, cooling, the heat lingering a while in the veins through it
        let lp = db.lp;
        // (a pixel's width there, in blocks: detail a block across fades as it nears a pixel: no crawling speckle)
        let px = best * frame.view_params.w / frame.resolution.y;
        let fb = fract(lp);
        let fq = min(fb, 1.0 - fb) + abs(db.n) * 9.0;
        let fc = fract(lp / db.v);
        let fe = min(fc, 1.0 - fc) + abs(db.n) * 9.0;
        let ke = 1.0 - smoothstep(0.04, 0.14, px / db.v);
        let kq = 1.0 - smoothstep(0.04, 0.14, px);
        let kg = 1.0 - smoothstep(0.3, 1.0, px);
        let edge = mix(1.0, mix(0.78, 1.0, smoothstep(0.0, 0.08, min(fe.x, min(fe.y, fe.z)))), ke) * mix(1.0, mix(0.92, 1.0, smoothstep(0.0, 0.06, min(fq.x, min(fq.y, fq.z)))), kq);
        let gq = floor(lp - db.n * 0.5);
        var alb = srgb_to_linear(db.col) * (0.72 + 0.4 * mix(0.5, hash31(gq + vec3<f32>(3.0)), kg)) * edge;
        alb = mix(alb, alb * 1.2 + vec3<f32>(0.008), db.fr * 0.5);
        let col0 = alb * (cl_mcface(db.n) * dl * (0.85 + 0.2 * max(dot(db.n, L), 0.0)) + nightc * 0.5);
        // (the heat: on broken faces only, a dull glow and veins at least a pixel wide, cooling in a couple of seconds)
        let vq = abs(gnoise3(lp * 0.3 + vec3<f32>(db.v * 7.0)) - 0.5);
        let vw = 0.06 + 0.5 * px * 0.3;
        let vein = (1.0 - smoothstep(0.0, vw, vq)) * (0.06 / vw);
        let hot = db.fr * (db.heat * (0.14 + 0.85 * vein) + 0.04 * vein * (1.0 - smoothstep(0.0, 6.0, t - CL_BURST)));
        let col = col0 * (1.0 - 0.35 * saturate(hot)) + mix(vec3<f32>(0.03, 0.6, 0.2), vec3<f32>(0.45, 1.0, 0.65), db.heat * db.heat * db.heat) * hot * 1.4;
        out.c = vec4<f32>(mix(col, srgb_to_linear(frame.fog_color.rgb), 1.0 - exp(-best * 0.0003)) * db.a, db.a);
        out.e.x = best;
    } else if (hit_k < 99u) {
        let ins = hit_ins;
        let hb = CL_MESH + 16u * ins.mesh;
        let wp = ro + rd * best;
        let pl = ((wp - ins.p) * ins.r) / ins.s;      // where on the piece, in its mesh's space
        let pb = pl * ins.s;                           // the same in blocks: the stone's grain is fixed to the piece
        let rdl = rd * ins.r;
        var nl = vec3<f32>(0.0, 1.0, 0.0);
        var ngl = nl;
        var albs = vec3<f32>(0.4);
        var gmask = 0.0;
        var ao = 1.0;
        var rough = 0.5;
        if (hit_tri == 1u) {
            // (a joint's ball: it shows only where a joint has opened)
            nl = normalize(pl - cl_v3(hb + 10u));
            ngl = nl;
            let cq = pl * 0.55 + vec3<f32>(f32(ins.mesh) * 7.3);
            let ck = min(abs(gnoise3(cq) - 0.5), abs(gnoise3(cq * 2.3 + vec3<f32>(19.0)) - 0.5) * 1.6);
            // (stone like the rest of it, a few thin veins: a bent knee reads as a knee, not a glowing wound)
            albs = vec3<f32>(0.33, 0.34, 0.33);
            gmask = mix(0.72, 0.0, smoothstep(0.0, 0.035, ck));
            ao = 0.75;
            rough = 1.3;
        } else {
            let sf = cl_surf(hb, hit_tri, hit_uv);
            nl = sf.n;
            ngl = sf.ng;
            albs = sf.col;
            gmask = sf.glow;
            ao = sf.ao;
        }
        if (dot(ngl, rdl) > 0.0) {
            ngl = -ngl;
        }
        if (dot(nl, ngl) < 0.0) {
            nl = -nl;
        }
        // the stone: chiselled faces a few blocks across, weathering in big stains, a grain a block wide
        let q1 = pb * 0.2;
        let bump = vec3<f32>(gnoise3(q1 + vec3<f32>(11.3, 0.0, 0.0)), gnoise3(q1 + vec3<f32>(0.0, 23.7, 0.0)), gnoise3(q1 + vec3<f32>(0.0, 0.0, 37.1))) - 0.5;
        let q2 = pb * 0.62;
        let fine = vec3<f32>(vnoise3(q2 + vec3<f32>(5.3, 0.0, 0.0)), vnoise3(q2 + vec3<f32>(0.0, 9.7, 0.0)), vnoise3(q2 + vec3<f32>(0.0, 0.0, 3.1))) - 0.5;
        let far_fade = 1.0 - smoothstep(500.0, 1400.0, best);     // (the fine grain only shimmers from far off)
        nl = normalize(nl + (bump * 1.1 + fine * 0.5 * far_fade) * rough);
        let stain = fbm3(pb * 0.04 + vec3<f32>(f32(ins.g) * 13.0));
        let grain = mix(0.5, hash31(floor(pb)), 0.6 * far_fade);
        var n = normalize(ins.r * nl);
        let hammer = ins.kind == 1u;
        let ngw = normalize(ins.r * ngl);
        var alb = srgb_to_linear(albs) * (0.66 + 0.62 * stain) * (0.9 + 0.2 * grain);
        // (the sky's light from above, the land's from below, both less in a crevice)
        let open = ao * ao * (3.0 - 2.0 * ao);
        let amb = mix(skyc * vec3<f32>(0.42, 0.4, 0.34), skyc, n.y * 0.5 + 0.5) * mix(0.18, 1.0, open);
        let ndl = max(dot(n, L), 0.0);
        var lit = ndl * mix(0.55, 1.0, open);
        if (lit > 0.0 && sun.y > -0.12 && (flags & 2u) != 0u) {
            lit = lit * (1.0 - cl_shadow(wp + ngw * 0.45 + L * 0.2, L, t, flags));
        }
        let gg = ins.g;
        let gb = CL_INST + CL_REC * gg;
        // the soil it came up through: lying on what faces up and packed into the crevices, sliding off within seconds, last
        // from the ledges; and on the sheer faces dirt still running down for a while
        var soil = 0.0;
        let sage = cl_age(gg, t, wp.y);
        if (sage < 11.0 && t < 24.0) {
            let upf = saturate(n.y * 0.6 + 0.4);
            let hold = max(upf * upf, 0.7 * (1.0 - open));
            let keep = 1.0 - smoothstep(0.4, 2.2 + 8.0 * hold, sage);
            let pat = 0.6 * hash31(floor(pb * 0.5) + vec3<f32>(7.0)) + 0.4 * stain;
            soil = smoothstep(0.0, 0.14, keep * (0.3 + 0.7 * hold) * 1.25 - pat) * mix(1.0, 0.75, 1.0 - far_fade);
            let run = vnoise3(vec3<f32>(wp.x * 0.7, wp.y * 0.05 + t * 1.6, wp.z * 0.7));
            soil = max(soil, smoothstep(0.62, 0.8, run) * (1.0 - upf) * (1.0 - smoothstep(0.5, 5.0, sage)) * 0.55);
            alb = mix(alb, srgb_to_linear(vec3<f32>(0.36, 0.27, 0.19) * (0.8 + 0.4 * grain)), soil * 0.9);
        }
        // (the hammer's head, heaved back out of the earth after its first blow, comes up caked)
        if (hammer && t > cl_f(gb + 10u) && t < cl_f(gb + 23u)) {
            let cx = cl_chain(ins, pl).x;
            let caked = (1.0 - smoothstep(0.0, 0.22, cx)) * (1.0 - smoothstep(2.0, 5.5, t - max(cl_f(gb + 23u) - 3.7, cl_f(gb + 10u) + 0.6)));
            let s2 = smoothstep(0.0, 0.14, caked * 0.72 - (0.6 * hash31(floor(pb * 0.5) + vec3<f32>(7.0)) + 0.4 * stain) * 0.9);
            alb = mix(alb, srgb_to_linear(vec3<f32>(0.36, 0.27, 0.19) * (0.8 + 0.4 * grain)), s2 * 0.9);
            soil = max(soil, s2);
        }
        // (the game's face shading, a little of the sun's direction and its shadow kept for their shape, and the
        // crevices darker as the game's smooth lighting darkens a corner; as bright as the game lights the statue's own
        // blocks, which take over at the sweep: measured in the game, the same giant's blocks read a quarter brighter (sRGB) than
        // the stone drawn here did. By night the moon's light the game leaves on its blocks, so the stone still reads)
        var col = alb * (cl_mcface(n) * dl * (1.0 + 0.3 * lit) * mix(0.62, 1.0, open) * 1.45
            + nightc * 1.6 * (0.6 + 0.4 * n.y) * mix(0.5, 1.0, open));
        // (the blast's light on the faces turned to it)
        col = col + alb * vec3<f32>(0.55, 1.0, 0.7) * cl_blast_lit(wp, n, t, cy, 0.1) * mix(0.6, 1.0, open);
        let glw = cl_f(gb + 8u);
        let rise = cl_rise(gg, t);
        // (the cracks burn brighter as it strains under the hammer, and flare at each blow)
        let gt1 = cl_f(gb + 10u);
        let gt2 = cl_f(gb + 23u);
        let gti = select(gt1, gt2, t > max(gt2 - 3.75 * cl_f(gb + 27u), gt1));
        let strain = smoothstep(gti - 3.3, gti - 1.2, t) * (1.0 - smoothstep(gti - 0.25, gti, t));
        let gdt = t - select(gt1, gt2, t >= gt2);
        let flare = select(0.0, exp(-2.0 * gdt), gdt > 0.0) * select(1.0, 1.5, t >= gt2);
        // the cracks: where the model's texture is green, thin bright veins with a soft light round them (they glow from the
        // first, swelling as it rises and pulsing)
        let em = saturate((gmask * 255.0 - select(96.0, 170.0, hammer)) * select(1.9, 4.0, hammer) / 255.0);
        let v1 = abs(gnoise3(pb * 0.085 + vec3<f32>(3.0, 17.0, 5.0)) - 0.5);
        let v2 = abs(gnoise3(pb * 0.21 + vec3<f32>(41.0, 7.0, 13.0)) - 0.5);
        let vein = max(1.0 - smoothstep(0.0, 0.035, v1), 0.7 * (1.0 - smoothstep(0.0, 0.05, v2)));
        let core = saturate(em * (0.25 + 1.5 * vein) + smoothstep(0.55, 1.0, em) * 0.6);
        // the charge: the light climbs from the hammer's head up the handle and the arms, a bright front and everything behind
        // it lit from inside, hotter and whiter until it bursts
        let ca = cl_chain(ins, pl);
        let tbg = cl_tb(gg);
        var bh = 0.0;
        if (ca.x < 50.0 && t > CL_CHARGE && t < tbg + 0.5) {
            let x = saturate((t - CL_CHARGE) / (tbg - CL_CHARGE));
            let pr = -0.4 + 2.6 * x * x * (3.0 - 2.0 * x);
            bh = saturate((pr - ca.x) * 6.0);
            let fl = (0.75 + 0.25 * sin(t * 37.0 + ca.x * 9.0));
            glow = glow + vec3<f32>(0.5, 1.0, 0.65) * (1.6 * exp(-pow((ca.x - pr) * 9.0, 2.0)) * (1.0 - step(tbg, t)))
                + mix(vec3<f32>(0.04, 0.6, 0.22), vec3<f32>(0.6, 1.0, 0.7), pow(x, 14.0)) * (bh * fl * (0.03 + 0.3 * pow(x, 4.0)));
        }
        let pulse = 0.45 + 0.8 * rise + 0.25 * sin(t * 2.6 + f32(gg) * 1.7) + 0.9 * strain + 2.4 * flare + 5.0 * bh;
        let emis = glw * pulse * (core * 1.5 + em * 0.22) * (1.0 - 0.7 * soil);
        col = col * (1.0 - 0.5 * core);
        let cc = cl_cut(ins, pl, t, flags, true);
        if (cc.d < 1.0e29) {
            let rim = 1.0 - smoothstep(0.0, 2.2, cc.d);
            glow = glow + rim * mix(vec3<f32>(0.1, 1.0, 0.4) * 2.2, vec3<f32>(0.5, 1.0, 0.62) * 4.0, cc.hot) * (1.0 - cc.sweep);
            glow = glow + cc.sweep * vec3<f32>(0.5, 1.0, 0.7) * 3.5;
        }
        // (the blast's heat on what it passed, a flash on all of it as it goes by)
        let tt = t - CL_HIT;
        if (tt > 0.0 && ins.kind == 0u) {
            let near = exp(-pow((length(wp.xz) / CL_WAVE - tt) * 9.0, 2.0))
                + exp(-pow((length(wp - cl_v3(gb + 44u)) / 260.0 - (t - tbg)) * 9.0, 2.0));
            glow = glow + vec3<f32>(0.5, 0.9, 0.6) * near * 0.22;
        }
        col = col + mix(vec3<f32>(0.05, 1.0, 0.3), vec3<f32>(0.55, 1.0, 0.7), saturate(core * core)) * emis;
        let fog = srgb_to_linear(frame.fog_color.rgb);
        col = mix(col, fog, 1.0 - exp(-best * 0.0003));
        out.c = vec4<f32>(col + glow, 1.0);
        // (negative: a giant's, for the impact frames' spikes)
        out.e.x = -best;
    } else if (!sky && (flags & 2u) != 0u && t < 38.0) {
        // the giants' shadows on the land: one ray towards the sun from where the land is, near the ring only
        let wp = ro + rd * scene_len;
        if (length(wp.xz) < 90.0 * CL_K) {
            let sh = cl_shadow(wp + L * 0.1, L, t, flags);
            out.e.y = sh;
        }
    }
    // the land's light (dust, the blast) and the beam over what they are in front of (not over a giant)
    if (hit_k >= 99u) {
        let wp = ro + rd * best;
        if (!sky && t < 34.0 && length(wp.xz) < 260.0 * CL_K) {
            out.c = vec4<f32>(out.c.rgb + cl_ground(wp, t), out.c.a);
        }
        // (the blast's light on the land, as a gain on its own colour (cl_compose), and a little more by night; the
        // column's shadow on it)
        if (!sky) {
            let bl = cl_blast_lit(wp, vec3<f32>(0.0, 1.0, 0.0), t, cy, 0.6);
            out.e.w = bl;
            out.c = vec4<f32>(out.c.rgb + vec3<f32>(0.55, 1.0, 0.7) * bl * 0.012 * (1.0 - day), out.c.a);
            if (sun.y > 0.02 && (flags & 2u) != 0u) {
                out.e.y = max(out.e.y, cl_blast_shade(wp, L, t, cy));
            }
        }
    }
    out.c = vec4<f32>(out.c.rgb + cl_flash(ro, rd, t, best) + cl_motes(ro, rd, t, best), out.c.a);
    // (the dirt off the giants: brown where it pours, paler where it is kicked up)
    var fs = 1.0;
    var fp = 1.0;
    var fl = 0.0;
    for (var g = 0u; g < CL_NG; g = g + 1u) {
        let x = select(0.0, falls[g].x, falls[g].y < best);
        fs = fs * (1.0 - x);
        fp = fp * (1.0 - falls[g].z);
        fl = fl + x * falls[g].w;
    }
    fp = fp * (1.0 - db.dust);
    if (fs * fp < 0.999) {
        let dday = saturate(frame.sun.y * 2.5 + 0.35);
        let lum = 0.22 + 0.95 * dday;
        let fa = 1.0 - fs;
        let pa = 1.0 - fp;
        // (dark earth, lit on the sun's side of the stream, in shadow on the other)
        let side = fl / max(fa, 1.0e-3);
        var c3 = out.c.rgb * fs + mix(vec3<f32>(0.14, 0.11, 0.08), vec3<f32>(0.29, 0.23, 0.165), saturate(0.45 + 0.55 * side)) * lum * fa;
        c3 = c3 * fp + vec3<f32>(0.215, 0.185, 0.145) * lum * pa;
        let al = 1.0 - fs * fp;
        out.c = vec4<f32>(c3, out.c.a + (1.0 - out.c.a) * al);
    }
    // (the earth they raise, 0 s to the last blow: `cl_earth`)
    if (t < CL_T2 + 6.5) {
        let lp = vec4<f32>(ro + rd * min(scene_len, 1.0e5), select(0.0, 1.0, !sky));
        let er = cl_earth(ro, rd, t, best, lp, L, vec3<f32>(0.1 + 0.95 * dl) + nightc * 2.0);
        if (er.a > 0.0) {
            out.c = vec4<f32>(out.c.rgb * (1.0 - er.a) + er.rgb, out.c.a + (1.0 - out.c.a) * er.a);
        }
    }
    // (the blast in the middle: its crown, its column and the dust it drives out, `cl_blast`)
    var ball = cl_blast(ro, rd, t, best, cy, cl_jit(0.0));
    // (each giant's burst: the shell of stone dust off its hammer and arms, `cl_bsmoke`, over what is behind it)
    // (in front of the blast's or behind it, as it lies nearer the eye than the middle or not)
    var bsd = CL_BIG;
    let bsm = cl_bsmoke(ro, rd, t, best, cl_jit(0.5), &bsd);
    if (bsd < -dot(ro, rd)) {
        ball = vec4<f32>(bsm.rgb + ball.rgb * (1.0 - bsm.a), ball.a + (1.0 - ball.a) * bsm.a);
    } else {
        ball = vec4<f32>(ball.rgb + bsm.rgb * (1.0 - ball.a), ball.a + (1.0 - ball.a) * bsm.a);
    }
    if (ball.a > 0.0) {
        out.c = vec4<f32>(out.c.rgb * (1.0 - ball.a) + ball.rgb, max(out.c.a, ball.a));
    }
    return out;
}

// The game's own light on a surface facing `n`: a block's face is its texture times a fixed shade by the way it faces (top
// 1, north and south 0.8, east and west 0.6, the bottom 0.5, gamma-encoded), blended here across a curved surface, in linear
// light. The giants, their earth and their boulders are lit with it so they sit in the world's light, not a render's.
fn cl_mcface(n: vec3<f32>) -> f32 {
    let q = n * n;
    let s = q.x * 0.6 + q.z * 0.8 + q.y * select(0.5, 1.0, n.y > 0.0);
    return pow(s, 2.2);
}

fn cl_compose(scene: vec3<f32>, o: ClOut) -> vec4<f32> {
    // (the giants and the fireball cover the picture by their coverage; the rest of o.c is light added to it)
    let land = scene * (1.0 - 0.55 * o.e.y) * (vec3<f32>(1.0) + vec3<f32>(0.55, 1.0, 0.7) * o.e.w);
    return vec4<f32>(linear_to_srgb(max(land * (1.0 - o.c.a) + o.c.rgb, vec3<f32>(0.0))), 1.0);
}

// Impact frames as it goes up (CL_HIT), drawn as an anime's are: ink on paper, the giants and what lies solid (`sol`) in
// silhouette with dry-brush streaks, spikes torn off each giant's back (`spk`: cl_spikes, from the half-size stage), sparse
// brushed strokes in from the frame's edge on the blast, splatter. Three cuts: black on white, a green negative of the
// picture with the ink pale, black on pale green; then a flash easing back. c is sRGB.
fn cl_hash(x: f32) -> f32 {
    return fract(sin(x * 12.9898) * 43758.547);
}
// Flashes softened (`/orbital impactframes off`, the wheel's FLASHES row SOFT: params[15] bit 2): no impact frames, and
// the blast's white flash held down, for anyone sensitive to flashing light.
fn cl_soft() -> bool {
    return (u32(frame.mod_params[3].w + 0.01) & 2u) != 0u;
}
fn cl_if(c: vec3<f32>, uv: vec2<f32>, sol: f32, spk: f32) -> vec3<f32> {
    let k = frame.mod_params[0].w - CL_HIT;
    if (k < 0.0 || k > 0.5 || cl_soft()) {
        return c;
    }
    let ro = frame.camera_position.xyz - vec3<f32>(frame.mod_params[1].x, 0.0, frame.mod_params[1].y);
    let asp = vec2<f32>(frame.resolution.x / frame.resolution.y, 1.0);
    let px = 1.5 / frame.resolution.y;
    let fk = floor(k * 25.0);
    let d = (uv - project_rel(vec3<f32>(0.0, cl_f(4u) + 60.0, 0.0) - ro).xy) * asp;
    let r = length(d);
    let ab = (atan2(d.y, d.x) / 6.2832 + 0.5) * 64.0;
    let hb = cl_hash(floor(ab) + fk * 91.0);
    let wb = (0.004 + 0.02 * hb * hb) * smoothstep(0.2 + 0.5 * cl_hash(hb * 7.7), 1.3, r) * step(0.72, hb);
    let ob = abs(fract(ab) - 0.5) * 6.2832 / 64.0 * r;
    var ink = max((1.0 - smoothstep(wb - px, wb + px, ob)) * (0.75 + 0.25 * vnoise(vec2<f32>(ab * 7.0, r * 9.0))), spk);
    let q = uv * asp * 80.0;
    let hq = cl_hash(dot(floor(q), vec2<f32>(1.0, 157.0)) + fk * 17.0);
    let rq = 0.12 + 0.3 * cl_hash(hq * 91.0);
    ink = max(ink, step(0.96, hq) * (1.0 - smoothstep(rq - 0.08, rq + 0.08, length(fract(q) - 0.5))) * step(0.1, r) * step(r, 0.55));
    let dry = smoothstep(0.72, 0.8, vnoise(vec2<f32>(ab * 12.0, r * 6.0)));
    let m = max(ink, sol * (1.0 - 0.15 * dry));
    if (k < 0.067) {
        return mix(vec3<f32>(0.97, 0.97, 0.95), vec3<f32>(0.02), m);
    }
    if (k < 0.133) {
        return mix((1.0 - c) * vec3<f32>(0.4, 1.0, 0.6), vec3<f32>(0.75, 1.0, 0.82), m);
    }
    if (k < 0.2) {
        return mix(vec3<f32>(0.74, 1.0, 0.8), vec3<f32>(0.02), m);
    }
    return mix(vec3<f32>(1.0, 1.0, 0.95), c, smoothstep(0.2, 0.5, k));
}

fn cl_flags() -> u32 {
    return select(3u, mod_data[3], arrayLength(&mod_data) > 3u);
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    cl_px = in.position.xy;
    let o = cl_render(in.uv, frame.mod_params[0].w, cl_flags());
    let c = cl_compose(srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0).rgb), o);
    return vec4<f32>(cl_if(c.rgb, in.uv, step(o.e.x, 6.0e4), 0.0), 1.0);
}

// [half stage]
// QUALITY FAST: cl_render at half size (fs_half), joined by a bilateral upsample against the land's depth (fs_join).
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

// The spikes torn off the giants' backs in the impact frames, as ink coverage at uv: each giant's run straight away from the
// blast in the world (so one facing the eye throws them away behind itself, out of sight), shown on the picture as that
// direction is; a spike is ink where the giant's own outline (the half-size stage's giants, a negative hit distance) lies
// within its length back along it, tapering to a point; each its own length, growing through the cuts, drawn afresh on each.
fn cl_spikes(uv: vec2<f32>) -> f32 {
    let t = frame.mod_params[0].w;
    let k = t - CL_HIT;
    if (k < 0.0 || k > 0.2 || cl_soft()) {
        return 0.0;
    }
    let hs = vec2<i32>(textureDimensions(half_extra));
    let ro = frame.camera_position.xyz - vec3<f32>(frame.mod_params[1].x, 0.0, frame.mod_params[1].y);
    let asp = vec2<f32>(frame.resolution.x / frame.resolution.y, 1.0);
    var pieces: array<ClInst, 14>;
    var best = 1.0e9;
    var next = 1.0e9;
    var dir = vec2<f32>(0.0);
    var org = vec2<f32>(0.0);
    var gs = 0.0;
    for (var g = 0u; g < CL_NG; g = g + 1u) {
        cl_rig(g, t, &pieces);
        let c = pieces[1].c;
        let e = project_rel(c - ro);
        let w = normalize(vec3<f32>(c.x, 0.0, c.z) + vec3<f32>(1.0e-3, 0.0, 0.0));
        let e2 = project_rel(c + w * 30.0 * cl_f(CL_INST + CL_REC * g + 2u) - ro);
        if (e.z < 0.0 || e2.z < 0.0) {
            continue;
        }
        let dg = length((uv - e.xy) * asp);
        if (dg < best) {
            next = best;
            best = dg;
            dir = (e2.xy - e.xy) * asp;
            org = e.xy * asp;
            gs = f32(g);
        } else {
            next = min(next, dg);
        }
    }
    let L0 = length(dir);
    if (L0 < 1.0e-4) {
        return 0.0;
    }
    let u = dir / L0;
    let fk = floor(k * 25.0);
    // (spikes, not a hatching: few, each apart, no longer than a share of the screen however near the giant (near
    // ones threw striped fans to the frame's edge), and gone where two giants' zones meet, never a seam)
    let bw = 0.02;
    let bin = dot(uv * asp - org, vec2<f32>(-u.y, u.x)) / bw;
    let h = cl_hash(floor(bin) + gs * 13.0 + fk * 7.0);
    let l = min(L0, 0.16) * (0.35 + 0.65 * h * h) * (0.6 + 3.5 * k);
    let seam = smoothstep(0.0, 0.06, next - best);
    if (h < 0.55 || l < 0.004 || seam <= 0.0) {
        return 0.0;
    }
    var at = -1.0;
    for (var i = 0; i < 14; i = i + 1) {
        let sd = l * (f32(i) + 0.5) / 14.0;
        let qp = clamp(vec2<i32>((uv - u * sd / asp) * vec2<f32>(hs)), vec2<i32>(0), hs - vec2<i32>(1));
        if (textureLoad(half_extra, qp, 0).x < 0.0) {
            at = sd;
            break;
        }
    }
    if (at < 0.0) {
        return 0.0;
    }
    let hw = bw * 0.46 * (1.0 - at / l);
    let px = 1.5 / frame.resolution.y;
    return seam * (1.0 - smoothstep(hw - px, hw + px, abs(fract(bin) - 0.5) * bw)) * (0.6 + 0.4 * smoothstep(0.3, 0.6, vnoise(vec2<f32>(bin * 6.0, at / l * 9.0))));
}

struct ClHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> ClHalf {
    cl_px = in.position.xy;
    let o = cl_render(in.uv, frame.mod_params[0].w, cl_flags());
    return ClHalf(o.c, o.e);
}

@fragment
fn fs_join(in: StageIn) -> @location(0) vec4<f32> {
    let hs = vec2<i32>(textureDimensions(half_picture));
    let h = floor(in.position.xy) * 0.5 - 0.25;
    let i0 = vec2<i32>(floor(h));
    let f = h - floor(h);
    let dz = depth_at(in.uv);
    let len = select(1.0e9, length(world_offset(in.uv, dz)), !is_sky(dz));
    var c = vec4<f32>(0.0);
    var sh = 0.0;
    var gl = 0.0;
    var sol = 0.0;
    var sw = 0.0;
    var near_d = 1.0e30;
    var near_c = vec4<f32>(0.0);
    var near_e = vec4<f32>(0.0);
    for (var k = 0; k < 4; k = k + 1) {
        let o = vec2<i32>(k & 1, k >> 1u);
        let q = clamp(i0 + o, vec2<i32>(0), hs - vec2<i32>(1));
        let pc = textureLoad(half_picture, q, 0);
        let pe = textureLoad(half_extra, q, 0);
        let bw = select(1.0 - f.x, f.x, o.x == 1) * select(1.0 - f.y, f.y, o.y == 1);
        // (how far this pixel's land is from the one this half-size pixel saw: 1 at a sky pixel against a sky one)
        let dl = abs(min(pe.z, 1.0e5) - min(len, 1.0e5)) / (0.04 * min(len, 1.0e5) + 0.6);
        let w = bw * exp(-dl * dl);
        c = c + pc * w;
        sh = sh + pe.y * w;
        gl = gl + pe.w * w;
        sol = sol + step(pe.x, 6.0e4) * w;
        sw = sw + w;
        if (dl < near_d) {
            near_d = dl;
            near_c = pc;
            near_e = pe;
        }
    }
    var oc = near_c;
    var os = near_e.y;
    var og = near_e.w;
    var osol = step(near_e.x, 6.0e4);
    if (sw > 1.0e-3) {
        oc = c / sw;
        os = sh / sw;
        og = gl / sw;
        osol = sol / sw;
    }
    var o: ClOut;
    o.c = oc;
    o.e = vec4<f32>(0.0, os, 0.0, og);
    let cc = cl_compose(srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0).rgb), o);
    return vec4<f32>(cl_if(cc.rgb, in.uv, osol, cl_spikes(in.uv)), 1.0);
}
// [end half stage]
