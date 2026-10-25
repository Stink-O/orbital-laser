// Orbital Laser's post pass for the Downfall (laser 5). The mod builds it from shaders/strike.wgsl up to its fs_main
// (the helpers, the Mothership's hull and the Black Hole's lens, which this reuses) followed by this file, and sets it
// for a downfall strike only: one pass with every laser in it would be much bigger for the GPU's compiler to fit, and
// slower for all of them. Validate with tools/check-shader.sh.

// ---- laser 5: the downfall ----------------------------------------------------------------------------------------
// The mothership's last stand. It drops in exactly as the Mothership does and charges, but the charge is cut and the
// power thrown to the batteries along its roof as a meteor the size of a hill comes down on it. They break it up, and the
// pieces, coming on as fast, strike it anyway: it burns, sheds chunks, loses lift and falls stern first, drifting
// downrange, smoke streaming up from it, and its stern strikes the ground, it ploughs on and its bow slams down, a wall
// of dust rolling out. Then the black hole engine in its stern groans, cracks of light spreading over it, and ruptures:
// the black hole draws the wreck in after it, tears up the land round it, and collapses in a flash. The hull is the
// Mothership's (ms_tier, ms_hull), met analytically in its own frame as it tilts (df_trace); the black hole is the
// Black Hole's lens (bh_lens). strike.rs works out the same fall, crash, gouge, chunks and torn blocks (DfGeo): keep
// the DF_* and df_* in step.

const DF_XP: f32 = -480.0;         // keep in step with strike.rs: DF_*, DfGeo
const DF_CUT: f32 = 6.8;
const DF_TURN0: f32 = 7.2;
const DF_TURN1: f32 = 13.2;
const DF_FIRE0: f32 = 8.4;
const DF_FIRE1: f32 = 13.8;
const DF_PERIOD: f32 = 0.75;
const DF_BOLT: f32 = 1.4;          // a bolt's flight up to the meteor
const DF_SPLIT: f32 = 14.0;
const DF_MV: f32 = 260.0;
const DF_LS: f32 = 360.0;
const DF_ELEV: f32 = 0.45;
const DF_MR: f32 = 34.0;           // the meteor's radius, and its pieces'
const DF_FR: f32 = 11.0;
const DF_ROCK: f32 = 15.4;
const DF_FALL0: f32 = 17.0;
const DF_FALL1: f32 = 30.0;
const DF_SLIDE: f32 = 2.6;
const DF_GROAN: f32 = 34.0;        // its engine starts to give
const DF_OPEN: f32 = 40.0;
const DF_LIFE: f32 = 11.0;
const DF_SINK0: f32 = 28.0;        // it ploughs in this deep, then settles over DF_SETTLE, buried DF_EMBED deep at the stern
const DF_SETTLE: f32 = 5.5;
const DF_EMBED: f32 = 72.0;
const DF_THC: f32 = 0.19;
const DF_THS: f32 = 0.05;
const DF_THR: f32 = 0.03;
const DF_REAL_A: f32 = 170.0;      // the slot under its keel is cut for real along its stern's this many blocks, this deep
const DF_SLOT: f32 = 32.0;
const DF_SHED: i32 = 48;           // the pieces it sheds as it falls, DF_SHED_PER every DF_SHED_DT from DF_SHED_T0
const DF_SHED_PER: i32 = 6;
const DF_SHED_T0: f32 = 15.9;
const DF_SHED_DT: f32 = 1.6;
const DF_SEC: i32 = 8;             // the black hole tears the wreck apart in this many sections, the last going in
const DF_SWALLOW: f32 = 9.6;       // this long after it opens
const DF_PHC: f32 = 0.12;
const DF_PHR: f32 = 0.035;
const DF_HOLE_H: f32 = 40.0;
const DF_BETA: f32 = 0.111;
const DF_RS: f32 = 13.0;           // the black hole's horizon, in blocks
const DFD_N: i32 = 96;
const DF_CHUNKS: i32 = 10;
const DF_G: f32 = 16.0;
const DF_KEEL_W: f32 = 70.0;
const DF_SKID_W: f32 = 60.0;
const DF_END: f32 = 60.0;          // the strike's length

// Where everything is, from the strike (strike.rs's DfGeo): the way away from the player, the ship's heading as it
// arrives and once it has come about, its middle, its belly's height, the target's block level, where its stern comes to
// rest (the hole) and strikes, its pivot hanging there, the way the meteor goes, its roll and the hits' mirror.
struct DfGeo {
    ax: vec2<f32>,
    h0: vec2<f32>,
    hf: vec2<f32>,
    c: vec2<f32>,
    ps: vec2<f32>,
    c0: vec2<f32>,
    s1: vec2<f32>,
    side: vec2<f32>,
    y0: f32,
    by: f32,
    roll: f32,
    mz: f32,
    mode: i32,
}
fn df_geo() -> DfGeo {
    var g: DfGeo;
    let tgt = target_pos();
    g.ax = ms_axis();
    let right = vec2<f32>(-g.ax.y, g.ax.x);
    g.mode = approach();
    g.h0 = select(select(select(-g.ax, right, g.mode == 2), -right, g.mode == 3), g.ax, g.mode == 1);
    g.hf = select(g.h0, right, g.mode == 0 || g.mode >= 4);
    g.c = tgt.xz - g.h0 * MS_EM_X;
    g.s1 = g.c + g.hf * DF_XP;
    g.ps = tgt.xz + g.ax * frame.mod_params[3].z;
    g.c0 = g.ps - (g.ps - g.s1) * DF_BETA;
    g.y0 = tgt.y + MS_H;
    g.by = block_y();
    let s = u32(seed_v());
    g.side = select(-g.hf, right * select(-1.0, 1.0, mh(7u, s, 1u) < 0.5), g.mode == 1);
    let far = -g.hf.y * g.ax.x + g.hf.x * g.ax.y;
    g.roll = select(select(-1.0, 1.0, mh(7u, s, 2u) < 0.5), sign(far), abs(far) > 0.3);
    g.mz = select(-1.0, 1.0, mh(7u, s, 3u) < 0.5);
    return g;
}
fn df_heading(g: DfGeo, t: f32) -> vec2<f32> {
    if (g.mode == 0 || g.mode >= 4) {
        let a = -1.5707963 * smoothstep(DF_TURN0, DF_TURN1, t);
        return vec2<f32>(g.h0.x * cos(a) - g.h0.y * sin(a), g.h0.x * sin(a) + g.h0.y * cos(a));
    }
    return g.h0;
}
// A point of the hull (x along, y up, z across) while it hangs there level, in the world.
fn df_hover(g: DfGeo, t: f32, l: vec3<f32>) -> vec3<f32> {
    let h = df_heading(g, t);
    let xz = g.c + h * l.x + vec2<f32>(-h.y, h.x) * l.z;
    return vec3<f32>(xz.x, g.y0 + l.y, xz.y);
}

// The ship in its own frame: its plan's origin (camera-relative) and axes, its scale (the arrival's, along about `px`),
// and the black hole's hold on it: how far it has drawn the hull in, how far round it the hull is gone, and where it is
// in the hull's frame.
struct DfPose {
    o: vec3<f32>,
    a: vec3<f32>,
    u: vec3<f32>,
    d: vec3<f32>,
    s: vec3<f32>,
    px: f32,
    pull: f32,
    eat: f32,
    hl: vec3<f32>,
    // what is left of it between two torn planes across it (plan x), its torn edges jagged; and its stern crumpling in
    // towards the hole before it opens
    x0: f32,
    x1: f32,
    crush: f32,
}
fn df_bare(o: vec3<f32>, a: vec3<f32>, u: vec3<f32>, d: vec3<f32>) -> DfPose {
    var P: DfPose;
    P.o = o;
    P.a = a;
    P.u = u;
    P.d = d;
    P.s = vec3<f32>(1.0);
    P.px = 0.0;
    P.pull = 0.0;
    P.eat = 0.0;
    P.hl = vec3<f32>(0.0);
    P.x0 = -1.0e4;
    P.x1 = 1.0e4;
    P.crush = 0.0;
    return P;
}
// The Mothership's arrival, as a pose.
fn df_from_ms(f: MsFrame, cam: vec3<f32>) -> DfPose {
    let c = f.c + f.ax * f.shift;
    var P = df_bare(vec3<f32>(c.x, f.y0, c.y) - cam, vec3<f32>(f.ax.x, 0.0, f.ax.y), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(f.sd.x, 0.0, f.sd.y));
    P.s = vec3<f32>(f.sx, f.sy, f.sz);
    P.px = f.px;
    return P;
}
// The ship at `t` once it has stopped (strike.rs's DfGeo::pose): hanging there, coming about, rocked by the hits, falling
// stern first and drifting downrange, ploughing on along the ground as its bow slams down, at rest.
fn df_pose(g: DfGeo, t: f32, cam: vec3<f32>) -> DfPose {
    let h = df_heading(g, t);
    var s = g.c + h * DF_XP;
    var y = g.y0;
    var th = 0.0;
    var ph = 0.0;
    if (t > DF_ROCK) {
        let r = t - DF_ROCK;
        ph = 0.03 * exp(-r * 0.7) * sin(r * 2.4);
    }
    let yc = g.by + 6.0;
    let yr = g.by - DF_EMBED;
    if (t >= DF_FALL0 && t < DF_FALL1) {
        let u = (t - DF_FALL0) / (DF_FALL1 - DF_FALL0);
        let e = u * u * (3.0 - 2.0 * u);
        s = g.s1 + (g.c0 - g.s1) * pow(max(u, 1.0e-6), 1.25);
        y = g.y0 - (g.y0 - yc) * u * u * sqrt(u);
        th = DF_THC * e;
        ph = ph + DF_PHC * e * g.roll;
    } else if (t >= DF_FALL1) {
        // it ploughs on through the ground as its bow slams down, then sinks on in, slowing, until it is buried
        let tau = min((t - DF_FALL1) / DF_SLIDE, 1.0);
        let e = 1.0 - (1.0 - tau) * (1.0 - tau);
        let f = 1.0 - pow(1.0 - saturate((t - DF_FALL1 - DF_SLIDE) / DF_SETTLE), 3.0);
        let ys = g.by - DF_SINK0;
        s = g.c0 + (g.ps - g.c0) * e;
        y = yc + (ys - yc) * e + (yr - ys) * f;
        th = DF_THS + (DF_THC - DF_THS) * (1.0 - tau * tau) + (DF_THR - DF_THS) * f;
        ph = ph + (DF_PHR + (DF_PHC - DF_PHR) * (1.0 - tau) * (1.0 - tau)) * g.roll;
        let b = t - DF_FALL1 - DF_SLIDE;
        if (b > 0.0) {
            th = th + 0.012 * exp(-b * 2.5) * sin(b * 7.0);
        }
    }
    let a3 = vec3<f32>(h.x, 0.0, h.y);
    let s3 = vec3<f32>(-h.y, 0.0, h.x);
    let a = vec3<f32>(a3.x * cos(th), sin(th), a3.z * cos(th));
    let u1 = vec3<f32>(-a3.x * sin(th), cos(th), -a3.z * sin(th));
    return df_bare(vec3<f32>(s.x, y, s.y) - cam - a * DF_XP, a, u1 * cos(ph) + s3 * sin(ph), s3 * cos(ph) - u1 * sin(ph));
}
fn df_local(P: DfPose, p: vec3<f32>) -> vec3<f32> {
    let r = p - P.o;
    return vec3<f32>(dot(r, P.a), dot(r, P.u), dot(r, P.d));
}
fn df_world(P: DfPose, l: vec3<f32>) -> vec3<f32> {
    return P.o + P.a * l.x + P.u * l.y + P.d * l.z;
}

// How far a tear across the hull wanders, `y` across it and `h` up it: torn further in some decks than others, ragged.
fn df_jag(y: f32, h: f32) -> f32 {
    return 26.0 * (fvnoise(vec2<f32>(y * 0.045, floor(h / 9.0) * 1.7)) - 0.5) + 10.0 * (fvnoise(vec2<f32>(y * 0.21, h * 0.13)) - 0.5);
}
// Where in the hull's plan a point of its frame is (xy), and z 1e4 once the black hole has had it: the hull is drawn in
// after the hole along its length, narrowing as it goes, and gone round the hole and behind it.
fn df_plan(P: DfPose, l: vec3<f32>) -> vec3<f32> {
    var q = vec2<f32>((l.x - P.px) / P.s.x + P.px, l.z / P.s.z);
    var gone = 0.0;
    if (P.crush > 0.0) {
        // crumpling inwards: the plating round the hole drawn in towards it, in dents and folds
        let dq = q - P.hl.xz;
        let dent = 0.6 + 0.4 * sin(dq.x * 0.07 + l.y * 0.05) * sin(dq.y * 0.09 - l.y * 0.04);
        q = q + dq * P.crush * dent * exp(-dot(dq, dq) / 26000.0);
    }
    if (P.eat > 0.0) {
        gone = select(0.0, 1.0e4, length(l - P.hl) < P.eat);
    }
    if (P.x0 > -1.0e3 || P.x1 < 1.0e3) {
        // torn off along a rib: jagged, deeper in some decks than others
        let jag = df_jag(q.y, l.y);
        gone = max(gone, select(0.0, 1.0e4, q.x < P.x0 + jag || q.x > P.x1 + jag));
    }
    return vec3<f32>(q, gone);
}
// The batteries along both edges of the roof, overhanging them a little: below 0 inside one.
fn df_turret(q: vec2<f32>) -> f32 {
    let x = -450.0 + 150.0 * clamp(floor((q.x + 450.0) / 150.0 + 0.5), 0.0, 5.0);
    let t = length(q - vec2<f32>(x, sign(q.y) * (ms_half_w(x) - 3.0))) - 9.0;
    // and a raised spine down the middle of the roof, stepped in sections, from the engines to the bow's sensors
    let sec = floor(q.x / 90.0);
    let w = 34.0 + 14.0 * fh21(vec2<f32>(sec, 71.0));
    let spine = max(max(abs(q.y) - w, q.x - 300.0), -390.0 - q.x);
    return min(t, max(spine, abs(q.x - (sec + 0.5) * 90.0) - 42.0));
}
// Band `k`'s footprint at a point of the hull's frame (below 0 inside): the keel, the middle deck, the outer hull, each
// up to the next one's floor, and the batteries over the roof.
fn df_foot(P: DfPose, l: vec3<f32>, k: i32) -> f32 {
    let m = df_plan(P, l);
    if (k == 3) {
        return df_turret(m.xy) + m.z;
    }
    return ms_tier(m.xy, k) + m.z;
}
// Up the eye or the hangar from its mouth at `t_lo`: its ceiling, or its wall on the way (as ms_recess).
fn df_recess(P: DfPose, o: vec3<f32>, v: vec3<f32>, t_lo: f32, up: f32, which: i32) -> MsHit {
    var hit: MsHit;
    let t_c = (up * P.s.y - o.y) / v.y;
    let q_c = df_plan(P, o + v * t_c).xy;
    if (select(ms_hangar(q_c), ms_eye(q_c), which == 0) < 0.0) {
        hit.t = t_c;
        hit.q = q_c;
        hit.h = up;
        hit.kind = select(6, 4, which == 0);
        return hit;
    }
    var a = t_lo;
    var b = t_c;
    for (var i = 0; i < 5; i = i + 1) {
        let m = 0.5 * (a + b);
        let qm = df_plan(P, o + v * m).xy;
        if (select(ms_hangar(qm), ms_eye(qm), which == 0) < 0.0) {
            a = m;
        } else {
            b = m;
        }
    }
    hit.t = b;
    hit.q = df_plan(P, o + v * b).xy;
    hit.h = (o.y + v.y * b) / P.s.y;
    hit.kind = select(7, 5, which == 0);
    return hit;
}
// Where a ray (from `ro`, camera-relative, along `rd`) meets the hull, from any side: the hull is the keel, the middle
// deck and the outer hull, each a prism from its floor to the next one's (each inside the next), and the batteries over
// the roof. Each prism is met at its floor or its top (found by where the ray crosses those heights) or else through
// its wall (stepping across it, then closing in by halves). The kinds are ms_trace's, and 9 a battery; the roof is a
// floor at MS_TOP.
fn df_trace(P: DfPose, ro: vec3<f32>, rd: vec3<f32>) -> MsHit {
    var hit: MsHit;
    hit.t = 1.0e9;
    hit.q = vec2<f32>(0.0);
    hit.h = 0.0;
    hit.kind = -1;
    let o = df_local(P, ro);
    let v = vec3<f32>(dot(rd, P.a), dot(rd, P.u), dot(rd, P.d));
    let iv = 1.0 / select(v, vec3<f32>(1.0e-6), abs(v) < vec3<f32>(1.0e-6));
    // the box round it, in its frame
    let lo = vec3<f32>((max(-560.0, P.x0 - 30.0) - P.px) * P.s.x + P.px, 0.0, -302.0 * P.s.z);
    let hi = vec3<f32>((min(560.0, P.x1 + 30.0) - P.px) * P.s.x + P.px, (MS_TOP + 12.0) * P.s.y, 302.0 * P.s.z);
    let t1 = (lo - o) * iv;
    let t2 = (hi - o) * iv;
    let tmin = min(t1, t2);
    let tmax = max(t1, t2);
    let bx0 = max(max(tmin.x, tmin.z), 0.0);
    let bx1 = min(tmax.x, tmax.z);
    if (bx1 < max(bx0, max(tmin.y, 0.0)) || tmax.y < bx0) {
        return hit;
    }
    var hangar = false;
    let below = o.y < 0.0 && v.y > 0.0;
    for (var k = 0; k < 4; k = k + 1) {
        if (below && hit.kind >= 0) {
            // (from below the bands come in order of height: the first met is the nearest)
            break;
        }
        let y0 = select(ms_tier_h(k), MS_TOP, k == 3) * P.s.y;
        let y1 = select(select(MS_TOP, ms_tier_h(k + 1), k < 2), MS_TOP + 12.0, k == 3) * P.s.y;
        var ta = bx0;
        var tb = min(bx1, hit.t);
        var floor_in = false;
        var roof_in = false;
        if (abs(v.y) > 1.0e-6) {
            let sa = (y0 - o.y) * iv.y;
            let sb = (y1 - o.y) * iv.y;
            if (min(sa, sb) > ta) {
                ta = min(sa, sb);
                floor_in = v.y > 0.0;
                roof_in = v.y < 0.0;
            }
            tb = min(tb, max(sa, sb));
        } else if (o.y < y0 || o.y > y1) {
            continue;
        }
        if (tb <= ta || (k == 2 && hangar)) {
            continue;
        }
        let la = o + v * ta;
        if (k == 1 && floor_in) {
            // from below into the hangar's mouth: up it to its ceiling, or its wall
            let qa = df_plan(P, la);
            if (ms_hangar(qa.xy) < 0.0 && ms_outline(qa.xy, 40.0) < 0.0 && qa.z < 1.0) {
                hangar = true;
                let rh = df_recess(P, o, v, ta, MS_HANGAR_UP, 1);
                if (rh.t < hit.t) {
                    hit = rh;
                }
                continue;
            }
        }
        if (df_foot(P, la, k) < 0.0) {
            let qa = df_plan(P, la).xy;
            if (k == 0 && floor_in && ms_eye(qa) < 0.0) {
                let re = df_recess(P, o, v, ta, MS_EYE_UP, 0);
                if (re.t < hit.t) {
                    hit = re;
                }
                continue;
            }
            hit.t = ta;
            hit.q = qa;
            hit.h = select(select((o.y + v.y * ta) / P.s.y, MS_TOP, roof_in), ms_tier_h(k), floor_in);
            hit.kind = select(select(3, 2, roof_in && k == 2), k, floor_in && k < 3);
            hit.kind = select(hit.kind, 9, k == 3);
            continue;
        }
        // step across the band to where the ray first comes inside, then close in on the wall
        let n = clamp(i32(length((v * (tb - ta)).xz) / 40.0), 1, 14);
        var a = ta;
        for (var i = 1; i <= n; i = i + 1) {
            let b = ta + (tb - ta) * f32(i) / f32(n);
            if (df_foot(P, o + v * b, k) < 0.0) {
                var lo_ = a;
                var hi_ = b;
                for (var j = 0; j < 5; j = j + 1) {
                    let m = 0.5 * (lo_ + hi_);
                    if (df_foot(P, o + v * m, k) < 0.0) {
                        hi_ = m;
                    } else {
                        lo_ = m;
                    }
                }
                hit.t = hi_;
                hit.q = df_plan(P, o + v * hi_).xy;
                hit.h = (o.y + v.y * hi_) / P.s.y;
                hit.kind = select(3, 9, k == 3);
                break;
            }
            a = b;
        }
    }
    return hit;
}

// How fast its pivot is moving at `t` as it falls (strike.rs's DfGeo::vel; its spin left out).
fn df_vel(g: DfGeo, t: f32) -> vec3<f32> {
    if (t < DF_FALL0 || t >= DF_FALL1) {
        return vec3<f32>(0.0);
    }
    let tf = DF_FALL1 - DF_FALL0;
    let u = max((t - DF_FALL0) / tf, 1.0e-6);
    let kk = 1.25 * pow(u, 0.25) / tf;
    return vec3<f32>((g.c0.x - g.s1.x) * kk, -(g.y0 - g.by - 6.0) * 2.5 * pow(u, 1.5) / tf, (g.c0.y - g.s1.y) * kk);
}
// The displaced ground heaped up beside the hull, `e` blocks out from its edge, `x` along it (strike.rs's df_berm_h).
fn df_berm_h(x: f32, e: f32) -> f32 {
    if (e < 0.0) {
        return 0.0;
    }
    return (14.0 * exp(-pow((e - 14.0) / 13.0, 2.0)) + 5.0 * exp(-pow((e - 52.0) / 6.0, 2.0))) * (1.0 - 0.35 * (x + 560.0) / 1120.0);
}

// Whether the hull stands between the eye and `p` (camera-relative): where the line to it crosses the belly's and the
// roof's planes, is it inside the hull's outline? For fading the glare of what the hull hides.
fn df_blocks(P: DfPose, p: vec3<f32>) -> bool {
    let o = df_local(P, vec3<f32>(0.0));
    let e = df_local(P, p) - o;
    for (var i = 0; i < 2; i = i + 1) {
        let y = select(0.0, MS_TOP, i == 1) * P.s.y;
        let f = (y - o.y) / select(e.y, 1.0e-6, abs(e.y) < 1.0e-6);
        if (f > 0.0 && f < 1.0) {
            let m = df_plan(P, o + e * f);
            if (ms_outline(m.xy, 0.0) + m.z < 0.0) {
                return true;
            }
        }
    }
    return false;
}

// Where the meteor's piece `j` strikes the roof, in the hull's frame (strike.rs's DF_HITS, mirrored across by `mz`).
fn df_hit_l(j: i32, mz: f32) -> vec3<f32> {
    var l = vec3<f32>(-440.0, 150.0, 40.0);
    switch j {
        case 1: { l = vec3<f32>(-300.0, 150.0, -110.0); }
        case 2: { l = vec3<f32>(-520.0, 150.0, -150.0); }
        case 3: { l = vec3<f32>(-200.0, 150.0, 120.0); }
        case 4: { l = vec3<f32>(-545.0, 150.0, 60.0); }
        case 5: { l = vec3<f32>(-360.0, 150.0, 190.0); }
        default: {}
    }
    return vec3<f32>(l.x, l.y, l.z * mz);
}
// The way the meteor goes (strike.rs's DfGeo::meteor), and where it comes down on the roof.
fn df_met_dir(g: DfGeo) -> vec3<f32> {
    let h = normalize(g.side - g.ax * 0.2);
    return vec3<f32>(h.x * cos(DF_ELEV), -sin(DF_ELEV), h.y * cos(DF_ELEV));
}
// The meteor's middle at `t` (until it breaks up, DF_LS short of `aim`), in the world.
fn df_met_head(aim: vec3<f32>, mv: vec3<f32>, t: f32) -> vec3<f32> {
    return aim - mv * (DF_LS + DF_MV * (DF_SPLIT - t));
}

// The top block of the ground at column `xz` near the hole once the gouges are cut (strike.rs's DfGeo::ground).
fn df_ground(g: DfGeo, xz: vec2<f32>) -> f32 {
    let p = floor(xz) + 0.5;
    var top = g.by;
    let r = p - g.ps;
    let a = dot(r, g.hf);
    if (a >= -80.0 && a < DF_REAL_A && abs(r.y * g.hf.x - r.x * g.hf.y) <= select(DF_KEEL_W, 170.0, a < 50.0)) {
        top = min(top, g.by - DF_SLOT - 1.0);
    }
    let sk = length(g.ps - g.c0);
    if (sk > 2.0) {
        let dir = (g.ps - g.c0) / sk;
        let r2 = p - g.c0;
        let a2 = dot(r2, dir);
        if (a2 >= 0.0 && a2 < sk && abs(r2.y * dir.x - r2.x * dir.y) <= DF_SKID_W) {
            top = min(top, g.by - floor(12.0 + 8.0 * a2 / sk) - 1.0);
        }
    }
    return top;
}
// How hot the gouges are at a point of the ground (0 to 1): fresh from the friction where the hull ploughed, cooling.
fn df_gouge_heat(g: DfGeo, p: vec3<f32>, time: f32) -> f32 {
    let r = p.xz - g.ps;
    let a = dot(r, g.hf);
    let b = abs(r.y * g.hf.x - r.x * g.hf.y);
    var heat = 0.0;
    let kw = select(DF_KEEL_W, 170.0, a < 50.0);
    if (a > -80.0 && a < DF_REAL_A && b < kw + 4.0) {
        let age = time - DF_FALL1 - DF_SLIDE;
        heat = select(0.0, exp(-age / 12.0) * (1.0 - smoothstep(kw - 8.0, kw + 4.0, b)), age > 0.0);
    }
    let sk = length(g.ps - g.c0);
    if (sk > 2.0) {
        let dir = (g.ps - g.c0) / sk;
        let r2 = p.xz - g.c0;
        let a2 = dot(r2, dir);
        let b2 = abs(r2.y * dir.x - r2.x * dir.y);
        if (a2 > 0.0 && a2 < sk && b2 < DF_SKID_W + 4.0) {
            let age = time - (DF_FALL1 + DF_SLIDE * (1.0 - sqrt(1.0 - a2 / sk)));
            heat = max(heat, select(0.0, exp(-age / 9.0) * (1.0 - smoothstep(DF_SKID_W - 8.0, DF_SKID_W + 4.0, b2)), age > 0.0));
        }
    }
    return heat * saturate((g.by + 1.0 - p.y) / 3.0);
}
// Block `i` the black hole tears up (strike.rs's DfGeo::torn): x, z (the block), when (after DF_OPEN), and 1 for a piece
// of the wreck (or 0, the ground) + 2 for a big one.
// (`ks` holds pcg(seed ^ pcg(n)) for n = 21..25, worked out once: mh(i, seed, n) is then pcg(i ^ ks[n]))
fn df_torn(g: DfGeo, i: i32, ks: array<u32, 5>) -> vec4<f32> {
    let k = u32(i);
    let a = f32(pcg(k ^ ks[0])) * (TAU / 4294967296.0);
    let r = 46.0 + 36.0 * f32(pcg(k ^ ks[1])) * (1.0 / 4294967296.0);
    let t = 0.5 + 7.0 * f32(i) / f32(DFD_N) + 0.3 * f32(pcg(k ^ ks[2])) * (1.0 / 4294967296.0);
    let xz = floor(g.ps + vec2<f32>(cos(a), sin(a)) * r);
    return vec4<f32>(xz, t, select(0.0, 1.0, pcg(k ^ ks[3]) <= 1717986918u) + select(0.0, 2.0, pcg(k ^ ks[4]) > 3006477107u));
}

// A burning rock of radius `rr` (0: only its trail) at `head` (camera-relative), coming down along -`u` (`u` points back
// up its path), its trail `len` blocks back up it, `age0` seconds older than its head; `heat` how fiercely it burns. The
// Meteor Storm's big one: the smoke left in a widening wall, the fire streaming off it, its face white-hot.
fn df_rock(col: ptr<function, vec3<f32>>, add: ptr<function, vec3<f32>>, rd: vec3<f32>, head: vec3<f32>, u: vec3<f32>, rr: f32, len: f32,
           age0: f32, heat: f32, scene_len: f32, sky: bool, ship_t: f32, dim: f32, seed: f32, k: f32) {
    let w0 = abs(rr);
    let q = ray_seg(rd, head, head + u * len);
    let l = q.z * len;
    let age = l / DF_MV + age0;
    let vis = select(1.0, 1.0 - smoothstep(scene_len - 2.0, scene_len + 2.0, q.y), !sky) * select(1.0, 0.0, q.y > ship_t);
    let sw = w0 * 1.3 + age * (3.0 + w0 * 0.25);
    let swp = max(sw, q.y * 0.004);
    if (vis > 0.0 && q.x < swp * 3.0) {
        let sn = gfbm2(vec2<f32>(l * 0.02 - age * 0.3, q.x / swp * 2.0 + seed));
        let sa = exp(-pow(q.x / swp, 2.0)) * (sw / swp) * smoothstep(0.05, 0.6, age) * exp(-age / 14.0) * (0.35 + 0.65 * sn) * saturate(heat * 2.0);
        *col = mix(*col, vec3<f32>(0.3, 0.26, 0.23) * dim * (0.5 + 0.8 * sn), saturate(sa * 0.9) * vis);
        let fw0 = w0 * (1.0 + age * 2.5);
        let fw = max(fw0, q.y * 0.003);
        let core = exp(-pow(q.x / (fw * 0.7), 2.0)) * sqrt(fw0 / fw) * exp(-age * 1.6);
        *add = *add + mix(vec3<f32>(4.0, 3.4, 2.2), vec3<f32>(3.0, 0.9, 0.15), smoothstep(0.0, 0.8, age)) * core * vis * heat * k;
    }
    let th = dot(head, rd);
    if (rr > 0.0 && th > 0.0) {
        let dh = length(head - rd * th);
        let hq = rr * rr - dh * dh;
        if (hq > 0.0) {
            let t0 = th - sqrt(hq);
            if (t0 > 0.0 && t0 < min(scene_len, ship_t)) {
                let nrm = normalize(rd * t0 - head);
                let front = saturate(dot(nrm, -u));
                let cracks = smoothstep(0.55, 0.75, gfbm3(nrm * 5.0 + vec3<f32>(seed), 3));
                let rock = vec3<f32>(0.06, 0.05, 0.045) * (0.5 + gfbm3(nrm * 9.0, 2)) * dim;
                *col = rock + lava_ramp(0.4 + 0.6 * front + 0.3 * cracks) * (pow(front, 2.0) * 3.0 + cracks * 1.2) * heat;
            }
        }
        let glare = 1.0 / (1.0 + pow(dh / (rr * 2.5 + th * 0.004), 2.0));
        *add = *add + vec3<f32>(2.2, 1.4, 0.7) * glare * heat * 0.3 * select(1.0, 0.05, (!sky && scene_len < th) || ship_t < th) * k;
    }
}

// A ray (camera at the origin) against a box of half-size `hs` at `c` (camera-relative), turned `ang` about `ax`: how
// far (or -1), and the face's normal in the world.
fn df_box(c: vec3<f32>, rd: vec3<f32>, hs: vec3<f32>, ax: vec3<f32>, ang: f32) -> vec4<f32> {
    let ro = rot_axis(-c, ax, -ang) / hs;
    let rv = rot_axis(rd, ax, -ang) / hs;
    let inv = 1.0 / select(rv, vec3<f32>(1.0e-6), abs(rv) < vec3<f32>(1.0e-6));
    let ta = (vec3<f32>(-1.0) - ro) * inv;
    let tb = (vec3<f32>(1.0) - ro) * inv;
    let tlo = min(ta, tb);
    let tn = max(max(tlo.x, tlo.y), tlo.z);
    let tf = min(min(max(ta.x, tb.x), max(ta.y, tb.y)), max(ta.z, tb.z));
    if (tf < tn || tn < 0.0) {
        return vec4<f32>(-1.0);
    }
    let lp = abs(ro + rv * tn);
    var nl = vec3<f32>(0.0, sign((ro + rv * tn).y), 0.0);
    if (lp.x >= lp.y && lp.x >= lp.z) {
        nl = vec3<f32>(sign((ro + rv * tn).x), 0.0, 0.0);
    } else if (lp.z >= lp.y) {
        nl = vec3<f32>(0.0, 0.0, sign((ro + rv * tn).z));
    }
    return vec4<f32>(tn, normalize(rot_axis(nl, ax, ang)));
}

// The dust the crash raises, round `c` (xz) out to `R`: thick at the ground (`yg`) and thinning with height over `hs`,
// its front heaped up. Integrated along the view ray in closed form for its height, its spread and billows taken where
// the ray passes through it (three stretches), so it is soft, never blocky. How much of the view through it is left.
fn df_dust(cam: vec3<f32>, rd: vec3<f32>, scene_len: f32, c: vec2<f32>, R: f32, yg: f32, hs: f32, dens: f32, time: f32, seed: f32) -> vec2<f32> {
    let oc = cam.xz - c;
    let b = dot(oc, rd.xz);
    let a = max(dot(rd.xz, rd.xz), 1.0e-6);
    let cq = dot(oc, oc) - R * R;
    let disc = b * b - a * cq;
    if (disc <= 0.0) {
        return vec2<f32>(1.0, 0.0);
    }
    let sq = sqrt(disc);
    let t0 = max((-b - sq) / a, 0.0);
    let t1 = min((-b + sq) / a, min(scene_len, 6000.0));
    if (t1 <= t0) {
        return vec2<f32>(1.0, 0.0);
    }
    var tau = 0.0;
    var lit = 0.0;
    for (var i = 0; i < 3; i = i + 1) {
        let ta = mix(t0, t1, f32(i) / 3.0);
        let tb = mix(t0, t1, f32(i + 1) / 3.0);
        let pm = cam + rd * (0.5 * (ta + tb));
        let r = length(pm.xz - c);
        let nz = gfbm2(pm.xz * 0.012 + vec2<f32>(seed, time * 0.05));
        let front = exp(-pow((r - R * 0.85) / (R * 0.09), 2.0));
        let h = hs * (0.4 + 1.2 * nz) * (1.0 + 1.8 * front);
        // the height part in closed form: the density falls off as exp(-(y - yg) / h)
        let ea = exp(-max(cam.y + rd.y * ta - yg, -h) / h);
        let eb = exp(-max(cam.y + rd.y * tb - yg, -h) / h);
        let hint = select((tb - ta) * 0.5 * (ea + eb), h * (ea - eb) / rd.y, abs(rd.y) > 1.0e-3);
        let d = max(hint, 0.0) * (1.0 - smoothstep(R * 0.85, R, r)) * (0.12 + 0.35 * nz + 1.4 * front) * (1.0 - 0.5 * smoothstep(300.0, 700.0, r));
        tau = tau + d;
        // lit from above: brighter where it is heaped high and thin, darker low down in it
        lit = lit + d * saturate((pm.y - yg) / (h * 2.0) + 0.3 + 0.5 * nz);
    }
    return vec2<f32>(exp(-tau * dens), lit / max(tau, 1.0e-4));
}

// The hull's colour where a ray (`rd`, world) met it in pose `P` at `ts`: the Mothership's plating and lights in its own
// frame, its batteries, and what the downfall does to it: the meteor's hits burning through it, its engine's cracks of
// light as it fails, the black hole's light on it and its torn edges glowing as it is drawn in.
// What is left of the wreck in the hole's grip, `sw` of the way through swallowing it: swung up on its far end so its
// torn end lifts towards the hole, and drawn in after it.
fn df_grip(P0: DfPose, sw: f32, H: vec3<f32>) -> DfPose {
    var P = P0;
    let be = 0.11 * sw * sw;
    let a = P0.a * cos(be) - P0.u * sin(be);
    let u = P0.u * cos(be) + P0.a * sin(be);
    let far = P0.o + P0.a * 560.0;
    P.a = a;
    P.u = u;
    P.o = far - a * (560.0 + 70.0 * sw * sw);
    P.hl = df_local(P, H);
    return P;
}
// Section `k` torn off the wreck (`R` what is left of it), `age` seconds since: it falls in over `dur` seconds along a
// closed-form path, faster and faster, some swinging round the hole first, tumbling, and stretched out along its length
// as it nears the horizon, where it goes in. `pull` holds how far through its fall it is.
fn df_section(R: DfPose, k: i32, age: f32, dur: f32, H: vec3<f32>, nd: vec3<f32>, rs: f32) -> DfPose {
    var P = R;
    let fk = f32(k);
    let x0 = -370.0 + 930.0 / f32(DF_SEC) * fk;
    let x1 = x0 + 930.0 / f32(DF_SEC);
    let s = saturate(age / dur);
    let C0 = df_world(R, vec3<f32>(0.5 * (x0 + x1), 75.0, 0.0));
    let swing = select(0.5, 2.2, k % 3 == 1) * s * s;
    let rel = rot_axis(C0 - H, nd, swing) * (1.0 - s * s);
    let C = H + rel;
    let ax = normalize(vec3<f32>(fh21(vec2<f32>(fk, 3.0)) - 0.5, 0.6, fh21(vec2<f32>(fk, 7.0)) - 0.5));
    let om = (1.2 + 1.5 * fh21(vec2<f32>(fk, 9.0))) * s * s * select(1.0, 2.0, k == DF_SEC - 1);
    P.a = rot_axis(R.a, ax, om);
    P.u = rot_axis(R.u, ax, om);
    P.d = rot_axis(R.d, ax, om);
    P.s = vec3<f32>(1.0 + 4.0 * s * s * s, 1.0, 1.0 - 0.5 * s * s);
    P.px = 0.5 * (x0 + x1);
    P.o = C - P.a * P.px - P.u * 75.0;
    P.x0 = x0;
    P.x1 = x1;
    P.hl = df_local(P, H);
    P.eat = rs * 1.3 + 10.0;
    P.pull = s;
    return P;
}

fn df_shade(h: MsHit, P: DfPose, g: DfGeo, rd: vec3<f32>, X: vec3<f32>, ts: f32, lit: f32, chase_on: f32, core: f32, focus: vec3<f32>, haze: vec3<f32>,
            day: f32, sun: vec3<f32>, boost: f32, wake: f32, eng: f32, groan: f32, ht0: vec3<f32>, ht1: vec3<f32>) -> vec3<f32> {
    let v = vec3<f32>(dot(rd, P.a), dot(rd, P.u), dot(rd, P.d));
    let sl = vec3<f32>(dot(sun, P.a), dot(sun, P.u), dot(sun, P.d));
    let fl = vec3<f32>(dot(focus, P.a), dot(focus, P.u), dot(focus, P.d));
    var f0: MsFrame;
    f0.ax = vec2<f32>(1.0, 0.0);
    f0.sd = vec2<f32>(0.0, 1.0);
    var c = vec3<f32>(0.0);
    let q = h.q;
    if (h.kind == 9) {
        // a battery: a squat dark turret, its emitter on top glowing green as it fires
        let x = -450.0 + 150.0 * clamp(floor((q.x + 450.0) / 150.0 + 0.5), 0.0, 5.0);
        let tc = vec2<f32>(x, sign(q.y) * (ms_half_w(x) - 3.0));
        let dq = q - tc;
        let top = h.h > MS_TOP + 11.5;
        let n = select(normalize(vec3<f32>(dq.x, 0.0, dq.y)), vec3<f32>(0.0, 1.0, 0.0), top);
        let lam = 0.25 + 0.75 * max(dot(n, sl), 0.0) * day;
        let ring = smoothstep(0.6, 0.9, abs(fract(h.h / 4.0) - 0.5) * 2.0);
        c = vec3<f32>(0.07, 0.075, 0.08) * lam * (0.7 + 0.3 * ring) + haze * 0.05;
        let em = (1.0 - smoothstep(3.0, 4.5, length(dq))) * f32(top);
        c = c + vec3<f32>(0.6, 3.5, 1.0) * (em * 3.0 + exp(-length(dq) / 4.0) * 0.4) * lit;
    } else {
        // its lights after the crash: on here and there, then failing section by section from the stern, each with a
        // last flare, until none is left
        var bl = boost;
        if (ts > DF_FALL1) {
            let sec = floor((q.x + 560.0) / 70.0);
            let tf = DF_GROAN + 5.8 * (0.25 * fh21(vec2<f32>(sec, sign(q.y) + 5.0)) + 0.75 * (q.x + 560.0) / 1120.0);
            bl = 0.35 * f32(ts < tf) * (0.55 + 0.45 * step(0.3, fh21(vec2<f32>(sec, floor(ts * 7.0))))) + 2.0 * exp(-pow((ts - tf) / 0.08, 2.0));
        }
        c = ms_hull(h, f0, v, ts, lit, chase_on, core, 0.0, fl, haze, day, sl, bl, wake, eng);
    }
    // the hits: craters burning through the plating, scorched round, and fire breaking out through its belly under them
    for (var j = 0; j < 6; j = j + 1) {
        let e = df_hit_l(j, g.mz);
        let age = ts - select(ht1[max(j - 3, 0)], ht0[min(j, 2)], j < 3);
        if (age <= 0.0 || q.x > -60.0) {
            continue;
        }
        let dp = length(q - e.xz);
        let up = select(0.5, 1.0, h.h > 100.0);
        let R = (24.0 + 26.0 * (1.0 - exp(-age * 0.6))) * up;
        if (dp < R * 2.5) {
            // scorched round, glowing in the middle: the fire breathing in slow surges
            let n = gnoise2(q * 0.05 + vec2<f32>(f32(j) * 7.0, ts * 0.4));
            let core = exp(-pow(dp / (R * (0.55 + 0.3 * n)), 2.0));
            c = c * (1.0 - 0.7 * exp(-pow(dp / (R * 1.6), 2.0)));
            let heat = core * (0.6 + 0.4 * exp(-age * 0.3)) * (0.8 + 0.25 * sin(ts * 3.0 + f32(j) * 3.0) + 0.15 * n);
            c = c + lava_ramp(0.3 + 0.65 * heat) * heat * 2.6;
        }
    }
    let lx = df_local(P, X);
    let dh = length(lx - P.hl);
    let wall = h.kind == 3 || h.kind == 5 || h.kind == 7 || h.kind == 9;
    let cq = select(q, vec2<f32>(q.x + q.y, h.h * 1.5), wall);
    if ((groan > 0.0 || P.eat > 0.0) && dh < 420.0) {
        // the stern crumpling in towards the engine as it fails: its plating folded and creased, and gaps torn open in
        // it showing the engine's glow deep inside, pulsing slowly, growing
        let w = exp(-dh * dh / 45000.0);
        let gr = max(groan, f32(P.eat > 0.0));
        let fold = abs(gnoise2(cq * 0.06 + vec2<f32>(3.0, 1.0)) - 0.5) * 2.0;
        c = c * mix(1.0, 0.3 + 0.9 * smoothstep(0.0, 0.3, fold), w * gr);
        // tears opening in it: dark holes into the hull, a deep heat glowing far down in them
        let gn = gnoise2(cq * 0.045 + vec2<f32>(11.0, 4.0));
        let th = 0.74 - 0.1 * gr * w;
        let gap = smoothstep(th, th + 0.02, gn) * w;
        let down = smoothstep(th + 0.02, th + 0.12, gn);
        let deep = vec3<f32>(1.6, 0.42, 0.08);
        let inner = deep * down * (0.25 + 0.9 * gr * gr) * (0.7 + 0.3 * sin(ts * 1.7 + dh * 0.02));
        c = mix(c, vec3<f32>(0.006) + inner, gap * min(gr * 1.5, 1.0));
    }
    if (P.x0 > -1.0e3 || P.x1 < 1.0e3) {
        // where it was torn apart: its decks, girders and rooms open, some still lit, its edges hot nearer the hole
        let jag = df_jag(q.y, lx.y);
        let edge = min(abs(q.x - P.x0 - jag), abs(q.x - P.x1 - jag));
        if (edge < 7.0) {
            let deck = abs(fract(h.h / 7.0) - 0.5) * 7.0;
            let gird = abs(fract(q.y / 9.0) - 0.5) * 9.0;
            let room = fh21(vec2<f32>(floor(q.y / 9.0), floor(h.h / 7.0)) + vec2<f32>(3.0, 1.0));
            let lit_in = vec3<f32>(0.25, 0.75, 0.3) * step(0.7, room) * 0.35 + vec3<f32>(0.9, 0.4, 0.1) * step(0.9, room) * 0.6;
            let frame_ = saturate(step(deck, 0.9) + step(gird, 0.8));
            let inside = mix(vec3<f32>(0.008) + lit_in * (0.6 + 0.4 * fh21(vec2<f32>(room, floor(ts * 3.0)))), vec3<f32>(0.035, 0.035, 0.04) * (0.4 + 0.6 * day), frame_);
            c = mix(c, inside, 1.0 - smoothstep(4.0, 7.0, edge));
            // only its rim, where the torn section meets the skin, glowing hot (hotter nearer the hole)
            let rim = 1.0 - smoothstep(0.0, 5.0, -ms_outline(q, 0.0));
            c = c + lava_ramp(0.6) * rim * (1.0 - smoothstep(3.0, 7.0, edge)) * 1.6 * exp(-dh / 260.0);
        }
    }
    if (P.eat > 0.0 || P.x0 > -1.0e3) {
        // in the black hole's grip: lit by its disk, heating, reddening and brightening as it nears the horizon
        c = c + c * vec3<f32>(1.6, 0.8, 0.5) * 30000.0 / (dh * dh + 6000.0) + vec3<f32>(0.5, 0.22, 0.12) * 4000.0 / (dh * dh + 4000.0) * 0.3;
        c = c + vec3<f32>(3.0, 0.9, 0.3) * exp(-max(dh - max(P.eat, 20.0), 0.0) / 12.0) * 1.4;
    }
    return c;
}

fn downfall(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let aspect = frame.resolution.x / frame.resolution.y;
    let time = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let crel = tgt - cam;
    let k = intensity_v();
    let seed = seed_v();
    let su = u32(seed);
    let g = df_geo();
    let mode = g.mode;
    let style = arrival_style();

    // ---- timeline ---------------------------------------------------------------
    let ta = time - MS_ARRIVE;
    let present = time >= MS_ARRIVE;
    let stir = smoothstep(0.0, MS_ARRIVE, time) * f32(ta < 0.0);
    let stop = ms_stop(style);
    let wake = ta - stop;
    let arriving = ta >= 0.0 && ta < stop + MS_SHUTTER;
    let cut_t = time - DF_CUT;
    let charge = saturate((time - T_FIRE) / (DF_CUT - T_FIRE)) * f32(cut_t < 0.0);
    let conv_env = smoothstep(T_FIRE + 1.0, DF_CUT - 0.3, time) * (1.0 - smoothstep(DF_CUT, DF_CUT + 0.2, time));
    let core_env = smoothstep(T_FIRE + 1.5, DF_CUT, time) * (1.0 - smoothstep(DF_CUT, DF_CUT + 0.45, time)) * (1.0 + 0.8 * step(0.5, fract(time * 23.0)) * f32(cut_t > 0.0));
    // the batteries charged and firing
    let firing = smoothstep(DF_CUT, DF_FIRE0, time) * (1.0 - smoothstep(DF_FIRE1 + 0.4, DF_SPLIT + 1.5, time));
    let fall_u = saturate((time - DF_FALL0) / (DF_FALL1 - DF_FALL0));
    let crash_t = time - DF_FALL1;
    let crashed = crash_t > 0.0;
    let groan = smoothstep(DF_GROAN, DF_OPEN, time) * f32(time < DF_OPEN);
    let bt = time - DF_OPEN;                                    // the black hole's own clock
    let opened = bt > 0.0;
    let left = saturate((DF_LIFE - bt) / 1.6);
    let life = select(0.0, smoothstep(0.0, 0.6, bt) * pow(left, 0.4), opened);
    let ef = bt - DF_LIFE;                                      // its collapse's
    let evap = select(0.0, exp(-ef * 2.6), ef > 0.0);
    let open_ = select(0.0, exp(-bt * 9.0), opened);
    // its lights: the charge pulled out of them to the roof, browning out with each volley, failing under the hits and
    // as it falls; its engines sputtering as it goes down, its stern's bells strobing as the engine gives way
    let flick = step(0.35, fvnoise(vec2<f32>(time * 9.0, 3.0)));
    var boost = 1.0;
    if (cut_t > 0.0) {
        boost = mix(0.2, 0.8, smoothstep(0.0, 0.9, cut_t)) * (1.0 - 0.35 * firing * step(0.7, fract((time - DF_FIRE0) / DF_PERIOD)));
    }
    if (time > 15.2) {
        boost = 0.45 * (0.3 + 0.7 * flick);
    }
    if (time > DF_FALL0) {
        boost = (0.3 - 0.25 * fall_u) * flick;
    }
    if (crashed) {
        boost = 1.0;      // (df_shade fails its lights section by section)
    }
    var eng = 0.35;
    if (time > DF_FALL0) {
        eng = 0.3 + 2.2 * step(0.72, fvnoise(vec2<f32>(time * 5.0, 9.0))) * (1.0 - 0.6 * fall_u);
    }
    if (crashed) {
        // its engine's bells guttering as it fails, in uneven surges, dark at last
        eng = 0.06 + groan * (1.0 - groan) * 3.0 * step(0.55, fvnoise(vec2<f32>(time * 4.0, 2.0)));
    }
    let lit = select(charge, 0.25 + 0.5 * firing, cut_t > 0.0) * f32(time < DF_FALL0);
    let chase_on = select(charge, firing * 0.8, cut_t > 0.0);

    // ---- where things are -------------------------------------------------------
    var base: MsFrame;
    base.ax = g.h0;
    base.c = g.c;
    base.sd = vec2<f32>(-g.h0.y, g.h0.x);
    base.y0 = g.y0;
    base.shift = 0.0;
    base.sx = 1.0;
    base.sz = 1.0;
    base.sy = 1.0;
    base.px = 0.0;
    let f = ms_frame(base, time, mode, style);
    var P = df_from_ms(f, cam);
    if (time >= DF_TURN0) {
        P = df_pose(g, time, cam);
    }
    let Hw = vec3<f32>(g.ps.x, g.by + DF_HOLE_H, g.ps.y);
    let H = Hw - cam;
    // the wreck in the black hole's grip: its stern crumpling in towards the engine as it fails; once it opens, the
    // stern round it blown away at once, then the rest torn off section by section from the stern forward (`xc`, slowly
    // then faster), what is left swung round on its far end towards the hole and drawn in after it
    let sw = saturate(bt / DF_SWALLOW) * f32(opened);
    let sec_l = 930.0 / f32(DF_SEC);
    let kc = select(0, i32(floor(930.0 * pow(sw, 1.8) / sec_l)), opened);
    if (crashed) {
        P.hl = df_local(P, H);
        P.crush = 0.32 * groan * groan + 0.32 * f32(opened);
    }
    if (opened) {
        P = df_grip(P, sw, H);
        P.eat = 120.0 * smoothstep(0.0, 1.0, bt);
        P.x0 = -370.0 + sec_l * f32(kc);
    }
    let wreck_on = present && (!opened || kc < DF_SEC);
    let focus = vec3<f32>(tgt.x, base.y0 - MS_FOCUS, tgt.z) - cam;
    let mv = df_met_dir(g);
    let aim = df_hover(g, DF_SPLIT, vec3<f32>(-380.0, 150.0, 0.0));
    let Bw = aim - mv * DF_LS;
    // the hits: where each piece strikes the roof (plan xz, y height) and when
    var hits: array<vec4<f32>, 6>;
    for (var j = 0; j < 6; j = j + 1) {
        let l = df_hit_l(j, g.mz);
        hits[j] = vec4<f32>(l.x, l.y, l.z, DF_SPLIT + length(df_hover(g, DF_SPLIT, l) - Bw) / DF_MV);
    }
    let c0w = vec3<f32>(g.c0.x, g.by, g.c0.y);
    let rsw = 150.0 * max(crash_t, 0.0) / (1.0 + max(crash_t, 0.0) * 0.1);   // the crash's shock running out

    // ---- the light and the sky ---------------------------------------------------
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let haze = srgb_to_linear(saturate(frame.sky_color.rgb)) * 0.95 + vec3<f32>(0.01, 0.015, 0.03);

    // ---- the air bending: as it comes, the crash's shock along the ground, space round the hole -----------------
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    var off = vec2<f32>(0.0);
    if (time < 10.0) {
        off = ms_air(uv, cam, p0, sky0, stir, ta - stop, wake, base, f, time, seed, k);
    }
    if (crashed && crash_t < 7.0 && !sky0) {
        let pc = project_rel(c0w - cam);
        let m = exp(-pow((length(p0.xz - g.c0) - rsw) / 7.0, 2.0)) * exp(-crash_t * 0.35) * (1.0 - smoothstep(30.0, 70.0, abs(p0.y - g.by)));
        let dir = uv - pc.xy;
        off = off + dir / max(length(dir), 1.0e-4) * m * 0.035 * k * pc.z;
    }
    let pH = project_rel(H);
    let rs_now = DF_RS * life;
    let sdist = length((uv - pH.xy) * vec2<f32>(aspect, 1.0));
    var gw = 0.0;
    if (pH.z > 0.0) {
        if (opened && bt < 3.0) {
            gw = exp(-pow((sdist - bt * 2.0) / 0.07, 2.0)) * exp(-bt * 1.6);
            off = off + (uv - pH.xy) / max(sdist, 1.0e-4) * gw * 0.04 * k;
        }
        if (groan > 0.0 || opened) {
            // space bending round the engine: before it opens a faint warp of what lies past it, growing; once open, the
            // weak bending out past the lens's reach (what is near the hole, bh_lens bends). Light passing it at `b`
            // is turned towards it by 2 rs / b, so each pixel looks a little further in
            let rw = select(3.5 * groan * groan, rs_now, opened);
            let p11 = frame.projection[1][1];
            let b = max(length(H) * sdist * 2.0 / p11, 1.0);
            let fade_in = select(1.0, smoothstep(LENS_R * rw * 0.8, LENS_R * rw * 1.4, b) * 0.6, opened);
            let mag = min(rw * p11 / b, 0.5 * sdist) * fade_in;
            let dv = (pH.xy - uv) * vec2<f32>(aspect, 1.0) / max(sdist, 1.0e-4);
            off = off + dv * mag / vec2<f32>(aspect, 1.0) * k;
            // and only a faint shimmer of the air right round it
            let m = exp(-sdist / 0.08) * groan * groan;
            let hw = vec2<f32>(gnoise2(uv * 90.0 + vec2<f32>(0.0, time * 3.0)), gnoise2(uv * 90.0 + vec2<f32>(13.0, time * 2.6))) - 0.5;
            off = off + hw * 0.003 * m * k;
        }
    }
    let uv2 = clamp(uv + off, vec2<f32>(0.002), vec2<f32>(0.998));

    // ---- the scene --------------------------------------------------------------
    let d = depth_at(uv2);
    let sky = is_sky(d);
    let rel = world_offset(uv2, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv2, 0.5));
    let rdb = normalize(world_offset(uv, 0.5));
    let Pg = cam + rel;
    let cloud = !sky && abs(Pg.y - CLOUD_Y - 2.0) < 6.0;
    let ca = (open_ * 0.02 + evap * 0.015 + gw * 0.03) * k;
    let ca_dir = (uv2 - pH.xy) * ca;
    var col = srgb_to_linear(vec3<f32>(
        textureSampleLevel(scene_color, linear_sampler, uv2 + ca_dir, 0.0).r,
        textureSampleLevel(scene_color, linear_sampler, uv2, 0.0).g,
        textureSampleLevel(scene_color, linear_sampler, uv2 - ca_dir, 0.0).b));
    // the light: grey under the ship, the meteor lighting everything as it comes, brown under the dust after the crash,
    // drunk by the black hole
    let land = smoothstep(stop, stop + 0.3, ta) * (1.0 - smoothstep(DF_FALL1 - 2.0, DF_FALL1, time));
    let dust_env = smoothstep(DF_FALL1, DF_FALL1 + 5.0, time) * (1.0 - smoothstep(DF_END - 14.0, DF_END, time));
    let sky_env = smoothstep(DF_OPEN - 0.5, DF_OPEN + 2.5, time) * (1.0 - smoothstep(DF_OPEN + DF_LIFE + 1.0, DF_OPEN + DF_LIFE + 7.0, time));
    let met_env = smoothstep(6.0, DF_SPLIT, time) * f32(time < DF_SPLIT);
    let dim = clamp(1.0 - (0.12 * stir + 0.14 * land + 0.18 * charge * charge + 0.3 * dust_env + 0.45 * sky_env) * k, 0.25, 1.0);
    col = col * dim * mix(vec3<f32>(1.0), vec3<f32>(1.1, 0.9, 0.75), dust_env * 0.7 * k);
    col = col * (1.0 + vec3<f32>(1.4, 0.75, 0.3) * met_env * met_env * 0.4 * k);
    // the flashes lighting the land and the sky: the meteor breaking up, the pieces striking, the crash, the rupture
    let st = time - DF_SPLIT;
    var flash = vec3<f32>(0.5, 0.4, 0.28) * select(0.0, exp(-st * 2.5), st > 0.0);
    for (var j = 0; j < 6; j = j + 1) {
        let dt = time - hits[j].w;
        flash = flash + vec3<f32>(1.4, 0.7, 0.3) * select(0.0, exp(-dt * 3.0) * 0.5, dt > 0.0);
    }
    flash = flash + vec3<f32>(1.5, 1.0, 0.6) * select(0.0, exp(-crash_t * 1.5), crashed) + vec3<f32>(1.2, 1.0, 1.8) * (open_ + evap);
    col = col * (1.0 + flash * 0.6 * k);
    if (sky) {
        let grad = pow(1.0 - uv2.y, 1.5);
        let dusty = vec3<f32>(0.2, 0.13, 0.08) + vec3<f32>(0.25, 0.14, 0.07) * grad * (0.6 + 0.6 * gfbm2(rd.xz / max(rd.y, 0.05) * 1.5 + vec2<f32>(time * 0.04, 0.0)));
        col = mix(col, dusty * (0.35 + 0.65 * day), dust_env * 0.55 * k);
        col = mix(col, bh_sky(rd, seed), sky_env * 0.65);
        let tow = max(dot(rd, normalize(df_met_head(aim, mv, min(time, DF_SPLIT)) - cam)), 0.0);
        col = col + vec3<f32>(1.6, 0.75, 0.25) * pow(tow, 14.0) * met_env * 1.4 * k;
    }

    // ---- its shadow on the land, while it is up there ---------------------------------
    if (!sky && present && time < DF_FALL1 + 1.0) {
        let ls = select(vec3<f32>(0.0, 1.0, 0.0), normalize(vec3<f32>(sun.x, max(sun.y, 0.6), sun.z)), sun.y > 0.0);
        let lo = df_local(P, rel);
        let lv = vec3<f32>(dot(ls, P.a), dot(ls, P.u), dot(ls, P.d));
        if (lo.y < 0.0) {
            let qm = df_plan(P, lo + lv * ((MS_TIER_C * 0.5 * P.s.y - lo.y) / max(lv.y, 0.2)));
            let pen = 4.0 + max(-lo.y, 0.0) * 0.012;
            col = col * (1.0 - (1.0 - smoothstep(-pen, pen, ms_tier(qm.xy, 2) + qm.z)) * (0.6 * day + 0.15) * land * k);
        }
    }
    var add = vec3<f32>(0.0);

    // ---- on the ground ------------------------------------------------------------
    if (!sky) {
        let dy = Pg.y - g.by;
        let on_ground = 1.0 - smoothstep(25.0, 40.0, dy);
        let r = length(Pg.xz - tgt.xz);
        if (charge > 0.0 || (cut_t > 0.0 && cut_t < 0.8)) {
            // the charge's glow under the eye and a ring closing in on the target, gone the moment it is cut
            let ch = select(charge, 1.0, cut_t > 0.0);
            let conv = mix(60.0, 5.0, pow(ch, 1.5));
            let gl = exp(-r / 14.0) * ch * ch * 1.4 + exp(-pow((r - conv) / 1.2, 2.0)) * ch * 1.6;
            add = add + vec3<f32>(0.3, 1.8, 0.45) * gl * on_ground * select(1.0, exp(-cut_t * 7.0), cut_t > 0.0) * k;
        }
        let dustc = vec3<f32>(0.34, 0.28, 0.21) * (0.3 + 0.7 * day) * dim;
        let pw = time - (DF_FALL1 - 2.4);
        if (pw > 0.0 && pw < 9.0) {
            // the air under it blasted out along the ground as it comes down: a surge of dust racing out from under it
            let qd = df_plan(P, df_local(P, rel));
            let e = ms_outline(qd.xy, 0.0);
            let front = pw * 75.0 - 30.0;
            let dn = gfbm2(Pg.xz * 0.025 + vec2<f32>(time * 0.5, seed));
            let surge = (1.0 - smoothstep(front - 50.0, front + 15.0, e)) * (0.45 + 0.9 * dn) * (1.0 - smoothstep(4.0, 9.0, pw)) * on_ground;
            col = mix(col, dustc * (0.7 + 0.5 * dn), saturate(surge) * 0.75 * k);
        }
        if (crashed) {
            // the shock racing out from where the stern struck, the land behind it veiled in dust; the gouges glowing
            let rc = length(Pg.xz - g.c0);
            let dn = gfbm2(Pg.xz * 0.018 + vec2<f32>(time * 0.15, seed + 3.0));
            add = add + vec3<f32>(1.3, 1.0, 0.7) * exp(-pow((rc - rsw) / 6.0, 2.0)) * exp(-crash_t * 0.4) * on_ground * 2.0 * k;
            let behind = smoothstep(rsw + 6.0, rsw - 70.0, rc) * exp(-crash_t * 0.04) * on_ground;
            col = mix(col, dustc * (0.5 + 0.9 * dn), behind * (0.35 + 0.35 * dn) * k);
            let heat = df_gouge_heat(g, Pg, time);
            if (heat > 0.01) {
                let n = gfbm2(Pg.xz * 0.14 + vec2<f32>(Pg.y * 0.3, seed));
                let veins = exp(-pow((n - 0.5) / 0.07, 2.0));
                let molten = mix(veins * 0.9, 1.0, heat * heat);
                add = add + lava_ramp(heat * molten * (0.8 + 0.4 * n)) * smoothstep(0.03, 0.25, heat * molten) * 2.2 * k;
                col = col * (1.0 - 0.5 * smoothstep(0.0, 0.3, heat) * (1.0 - molten));
            }
        }
        if (opened && ef < 5.0) {
            // the land round the hole drawn in in streaks, the shockwave as it opens, lit by the disk
            let dxg = Pg.xz - g.ps;
            let rh = length(dxg);
            let ang = atan2(dxg.y, dxg.x);
            let lr = log(max(rh, 0.5));
            let near_y = on_ground / (1.0 + dy * dy / 200.0);
            let rw = bt * 65.0;
            add = add + vec3<f32>(1.1, 0.7, 1.8) * exp(-pow((rh - rw) / 3.5, 2.0)) * exp(-bt * 0.5) * near_y * 4.0 * k;
            col = col * (1.0 - exp(-pow((rh - rw + 7.0) / 5.0, 2.0)) * exp(-bt * 0.5) * near_y * 0.6);
            let arms = pow(0.5 + 0.5 * cos(4.0 * (ang - lr * 2.6) + time * 3.0), 6.0) * smoothstep(80.0, 95.0, rh) * (1.0 - smoothstep(140.0, 160.0, rh));
            add = add + vec3<f32>(0.6, 0.2, 1.1) * arms * life * near_y * 0.5 * k;
            let sa = ang - lr * 1.2;
            let flow = gfbm2(vec2<f32>(cos(sa), sin(sa)) * 9.0 + vec2<f32>(lr * 2.0 + time * 0.9, seed));
            add = add + vec3<f32>(0.5, 0.15, 0.9) * smoothstep(0.55, 0.8, flow) * smoothstep(20.0, 40.0, rh) * (1.0 - smoothstep(110.0, 170.0, rh)) * life * near_y * 0.6 * k;
            let lh = H - rel;
            col = col + col * vec3<f32>(1.8, 0.85, 0.4) * life * 9000.0 / (dot(lh, lh) + 4000.0) * k / max(dim, 0.25);
        }
    }

    // ---- the ship ----------------------------------------------------------------------
    var ship_t = 1.0e9;
    if (wreck_on) {
        // averaged over the shutter while it moves fast as it arrives (as the Mothership)
        let n = select(1, 12, arriving);
        let jit = select(0.0, ign(in.position.xy), arriving);
        let film = arriving && style == 0;
        let t_film = MS_ARRIVE + floor(ta / MS_SHUTTER) * MS_SHUTTER;
        var acc = vec3<f32>(0.0);
        var cover = 0.0;
        for (var i = 0; i < n; i = i + 1) {
            let fr = (f32(i) + jit) / f32(n);
            let ts = select(time - select(0.0, MS_SHUTTER * fr, arriving), t_film + MS_SHUTTER * 0.5 * fr, film);
            if (ts < MS_ARRIVE) {
                continue;
            }
            var Pi = P;
            if (arriving) {
                Pi = df_from_ms(ms_frame(base, ts, mode, style), cam);
            }
            let hit = df_trace(Pi, vec3<f32>(0.0), rd);
            if (hit.kind < 0) {
                continue;
            }
            // behind a cloud: faint through it from under the clouds; solid under its tint from over them
            let over = cloud && cam.y > CLOUD_Y + 8.0;
            let vis = select(select(0.0, 0.3, cloud), 1.0, sky || hit.t < scene_len || over) * (1.0 - smoothstep(4000.0, 20000.0, hit.t));
            if (vis > 0.0) {
                var hc = vec3<f32>(0.0);
                if (arriving) {
                    // (as it arrives, unhurt: the Mothership's own shading, lighter for the shutter's twelve looks)
                    var f0: MsFrame;
                    f0.ax = vec2<f32>(1.0, 0.0);
                    f0.sd = vec2<f32>(0.0, 1.0);
                    let vl = vec3<f32>(dot(rd, Pi.a), dot(rd, Pi.u), dot(rd, Pi.d));
                    let fl = vec3<f32>(dot(focus, Pi.a), dot(focus, Pi.u), dot(focus, Pi.d));
                    let sl = vec3<f32>(dot(sun, Pi.a), dot(sun, Pi.u), dot(sun, Pi.d));
                    hc = ms_hull(hit, f0, vl, ts, lit, chase_on, core_env, 0.0, fl, haze, day, sl, 3.0, ts - MS_ARRIVE - stop, eng);
                } else {
                    hc = df_shade(hit, Pi, g, rd, rd * hit.t, ts, lit, chase_on, core_env, focus, haze, day, sun, boost, ts - MS_ARRIVE - stop, eng, groan, vec3<f32>(hits[0].w, hits[1].w, hits[2].w), vec3<f32>(hits[3].w, hits[4].w, hits[5].w));
                }
                if (over && hit.t > scene_len) {
                    hc = mix(hc, vec3<f32>(luminance(col)), 0.3);
                }
                var a = vis;
                if (style == 2 && arriving) {
                    let w = saturate((max(Pi.s.x, Pi.s.y) - 1.0) / 8.0);
                    let az = abs(hit.q.y) / max(ms_half_w(hit.q.x), 1.0);
                    let smear = (exp(-pow(az / 0.05, 2.0)) * 2.0 + pow(0.5 + 0.5 * cos(az * 40.0), 12.0) * 0.6 + 0.15)
                        * (0.4 + 0.6 * saturate((hit.q.x + MS_HL) / (2.0 * MS_HL)));
                    a = vis * (1.0 - 0.9 * w);
                    hc = hc * (1.0 - 0.9 * w) + vec3<f32>(1.2, 2.6, 1.5) * smear * w;
                }
                // far off, the air between veils it
                acc = acc + hc * vis;
                cover = cover + a;
                ship_t = min(ship_t, hit.t);
            }
        }
        let a = cover / f32(n);
        col = col * (1.0 - a) + acc / f32(n);
        add = add * (1.0 - a);
        // (a smear of it, while it moves fast, hides what is behind it only where it covers most of the shutter)
        ship_t = select(1.0e9, ship_t, a > 0.5);
    }
    // ---- the black hole: how big, its disk filling from the wreck as it goes in ----------
    let wd = wing_dirs();
    let nd = normalize(vec3<f32>(0.0, 1.0, 0.0) + 0.32 * vec3<f32>(wd.x, 0.0, wd.y));
    let e1 = vec3<f32>(wd.z, 0.0, wd.w);
    let e2 = cross(nd, e1);
    let rs = DF_RS * life * (1.0 + 0.15 * exp(-bt * 5.0) + 0.03 * sin(time * 5.0));
    let disk_env = smoothstep(0.0, 0.4, bt) * pow(left, 0.5) * f32(opened) * (0.2 + 0.8 * smoothstep(0.05, 0.85, sw));
    let hot = 1.0 + 1.6 * (1.0 - left) + 2.2 * exp(-max(bt, 0.0) * 2.0) + 0.8 * sw;

    // ---- the sections torn off it, falling in: the nearest of them drawn, a stream of grit and dust off each --------
    if (opened && bt < DF_LIFE) {
        var best: MsHit;
        best.kind = -1;
        best.t = min(ship_t, scene_len);
        var bestP = P;
        for (var kk = 1; kk <= 3; kk = kk + 1) {
            let kx = kc - kk;
            if (kx < 0) {
                continue;
            }
            let t_k = DF_SWALLOW * pow(f32(kx + 1) / f32(DF_SEC), 1.0 / 1.8);
            let dur = 2.6 - 1.2 * f32(kx) / f32(DF_SEC - 1);
            let Pk = df_section(P, kx, bt - t_k, dur, H, nd, rs);
            if (Pk.pull >= 1.0) {
                continue;
            }
            let C = df_world(Pk, vec3<f32>(Pk.px, 75.0, 0.0));
            let tc = dot(C, rd);
            if (tc > 0.0 && length(C - rd * tc) < 300.0 + 280.0 * Pk.s.x) {
                let hk = df_trace(Pk, vec3<f32>(0.0), rd);
                if (hk.kind >= 0 && hk.t < best.t) {
                    best = hk;
                    bestP = Pk;
                }
            }
            // grit and dust streaming off it, back along its path, hot nearer the hole
            let sp = saturate((bt - t_k - 0.35) / dur);
            let Cp = H + rot_axis(df_world(P, vec3<f32>(Pk.px, 75.0, 0.0)) - H, nd, select(0.5, 2.2, kx % 3 == 1) * sp * sp) * (1.0 - sp * sp);
            let q = ray_seg(rd, C, Cp);
            let w = max(50.0 + 60.0 * q.z, q.y * 0.002);
            if (q.x < w * 2.0 && q.y < min(scene_len, best.t)) {
                let sn = gfbm2(vec2<f32>(q.z * 5.0 - bt * 2.0, q.x / w * 2.0 + f32(kx)));
                let dens = exp(-pow(q.x / w, 2.0)) * (0.25 + 0.7 * sn) * (1.0 - q.z) * 0.7;
                col = mix(col, vec3<f32>(0.13, 0.1, 0.09) * dim + lava_ramp(0.6) * exp(-length(C - H) / 120.0) * 0.8, saturate(dens));
            }
        }
        if (best.kind >= 0) {
            col = df_shade(best, bestP, g, rd, rd * best.t, time, 0.0, 0.0, 0.0, focus, haze, day, sun, 0.0, 9.0, 0.0, 0.0, vec3<f32>(hits[0].w, hits[1].w, hits[2].w), vec3<f32>(hits[3].w, hits[4].w, hits[5].w));
            add = vec3<f32>(0.0);
            ship_t = best.t;
        }
    }

    // ---- the lens: the land and the wreck bent round it, its disk ------------------
    var swallowed = false;
    if (rs > 0.02 && ship_t > dot(H, rd) - LENS_R * rs * 0.5) {
        let L = bh_lens(H, rs, rd, uv2, scene_len, sky, nd, e1, e2, disk_env, hot, seed, time, sky_env, dim);
        if (L.on) {
            var bent = mix(col, L.bent, smoothstep(0.0, 0.25, L.w));
            if (!L.captured && !L.hit && L.w > 0.01 && wreck_on) {
                // what is left of the wreck, seen round it
                let hb = df_trace(P, L.p, L.v);
                if (hb.kind >= 0) {
                    bent = mix(col, df_shade(hb, P, g, L.v, L.p + L.v * hb.t, time, 0.0, 0.0, 0.0, focus, haze, day, sun, 0.0, 9.0, 0.0, 0.0, vec3<f32>(hits[0].w, hits[1].w, hits[2].w), vec3<f32>(hits[3].w, hits[4].w, hits[5].w)) * dim, smoothstep(0.0, 0.25, L.w));
                }
            }
            col = bent * L.trans + L.acc * k;
            swallowed = L.captured;
            add = add * L.trans + vec3<f32>(2.6, 1.7, 1.0) * exp(-pow((L.rmin - 1.52) / 0.05, 2.0)) * disk_env * select(1.0, 0.0, L.captured) * 1.4 * k;
        }
    }

    // everything drawn after the wreck is hidden where it is in front: its distance is the scene's depth
    let scene_lh = min(scene_len, ship_t);
    let sky_h = sky && ship_t > 1.0e8;
    if (time < MS_ARRIVE + 1.0) {
        add = add + ms_arrival_fx(f, base, cam, rd, sky_h, scene_lh, ta, mode, style, arriving, present, k);
    }
    if (time > T_FIRE && time < DF_CUT + 0.6) {
        add = add + ms_charge_fx(f, cam, rdb, focus, sky, scene_len, ship_t, conv_env, core_env, present, time, k);
    }

    // ---- the batteries firing: green bolts racing up from the roof's edges at the meteor, flaring where they strike ----
    if (time > DF_FIRE0 && time < DF_FIRE1 + DF_BOLT + 0.4) {
        for (var i = 0; i < 12; i = i + 1) {
            let side = select(-1.0, 1.0, i < 6);
            let x = -450.0 + 150.0 * f32(i % 6);
            let ml = vec3<f32>(x, MS_TOP + 14.0, side * (ms_half_w(x) - 3.0));
            // (its bolts all fly near the line from it to where the meteor is now)
            let qc = ray_seg(rd, df_hover(g, time, ml) - cam, df_met_head(aim, mv, time) - cam);
            if (qc.x > 300.0 + qc.y * 0.02) {
                continue;
            }
            let ph = fract(f32(i) * 0.618034) * DF_PERIOD;
            let n0 = floor((time - DF_FIRE0 - ph) / DF_PERIOD);
            for (var j = 0; j < 2; j = j + 1) {
                let tf = DF_FIRE0 + ph + (n0 - f32(j)) * DF_PERIOD;
                let a = time - tf;
                if (tf < DF_FIRE0 || tf > DF_FIRE1 || a < 0.0 || a > DF_BOLT + 0.35) {
                    continue;
                }
                let M = df_hover(g, tf, ml) - cam;
                let Tg = df_met_head(aim, mv, tf + DF_BOLT) - cam + vec3<f32>(fh21(vec2<f32>(f32(i), tf)) - 0.5, fh21(vec2<f32>(tf, f32(i))) - 0.5, 0.0) * DF_MR * 1.2;
                let u = a / DF_BOLT;
                if (u < 1.0) {
                    let q = ray_seg(rd, mix(M, Tg, u), mix(M, Tg, max(u - 0.05, 0.0)));
                    let w = max(1.4, q.y * 0.0012);
                    let vis = select(1.0, 0.0, (!sky_h && q.y > scene_lh) || q.y > ship_t + 2.0);
                    add = add + (vec3<f32>(2.4, 6.0, 2.8) * exp(-pow(q.x / (w * 0.6), 2.0)) + vec3<f32>(0.15, 1.5, 0.35) * exp(-pow(q.x / (w * 3.0), 2.0)))
                        * (1.4 / w) * vis * k;
                }
                // the muzzle's flash, glaring past the roof's edge even where the hull hides it, and the hit on the rock
                let fl_m = exp(-a * 14.0);
                let fl_h = select(0.0, exp(-(a - DF_BOLT) * 9.0), a > DF_BOLT);
                for (var e = 0; e < 2; e = e + 1) {
                    let pnt = select(Tg, M, e == 0);
                    let s = select(fl_h, fl_m, e == 0);
                    let tp = dot(pnt, rd);
                    if (s > 0.01 && tp > 0.0) {
                        let dp = length(pnt - rd * tp) / tp;
                        let hid = select(1.0, 0.08, tp > ship_t || (!sky_h && tp > scene_lh) || df_blocks(P, pnt));
                        add = add + vec3<f32>(1.6, 4.0, 1.8) * s * (exp(-pow(dp / 0.0025, 2.0)) * 3.0 + exp(-dp / 0.01) * 0.4) * hid * k;
                    }
                }
            }
        }
    }

    // ---- the meteor coming in, and its pieces ------------------------------------------------------------------------
    if (time > 5.0 && time < DF_SPLIT + 25.0) {
        // the meteor (-1): its head, then its trail left hanging across the sky_h; and its pieces coming on as fast, each
        // its own trail, into the hull
        let split = time >= DF_SPLIT;
        for (var j = -1; j < select(0, 6, split); j = j + 1) {
            var head = df_met_head(aim, mv, time) - cam;
            var u = -mv;
            var rr = DF_MR;
            var ln = DF_MV * (min(time, DF_SPLIT) - 5.0);
            var age0 = 0.0;
            var heat = smoothstep(5.0, 9.5, time);
            if (j == -1 && split) {
                head = Bw - cam;
                rr = -DF_MR;
                age0 = st;
                heat = 1.0;
            }
            if (j >= 0) {
                let T = df_hover(g, DF_SPLIT, hits[j].xyz);
                let fl = hits[j].w - DF_SPLIT;
                let uu = min(st / fl, 1.0);
                age0 = max(st - fl, 0.0);
                head = mix(Bw, T, uu) - cam;
                u = normalize(Bw - T);
                rr = select(-DF_FR, DF_FR, uu < 1.0);
                ln = length(T - Bw) * uu;
                heat = 1.0 - smoothstep(0.0, 12.0, age0);
            }
            if (heat > 0.0) {
                df_rock(&col, &add, rd, head, u, rr, ln, age0, heat, scene_lh, sky_h, ship_t, dim, seed + f32(j), k);
            }
        }
    }
    if (st > 0.0 && st < 24.0) {
        // it breaks up: a ball of fire bursting out of it, then a cloud of smoke and grit left hanging there, drifting
        let Bc = Bw - cam + vec3<f32>(6.0, 2.0, 2.0) * st;
        let tcb = dot(Bc, rd);
        if (tcb > 0.0) {
            let db = length(Bc - rd * tcb);
            let visb = select(1.0, select(0.0, 0.08, !df_blocks(P, Bc)), tcb > ship_t || (!sky_h && tcb > scene_lh));
            let Rf = 85.0 * (1.0 - exp(-st * 3.0)) + 8.0;
            let fire = exp(-pow(db / Rf, 2.0)) * exp(-st * 1.7);
            add = add + (lava_ramp(0.45 + fire * 0.6) * fire * 4.0 + vec3<f32>(2.0, 1.6, 1.2) / (1.0 + pow(db / (Rf * 2.5), 2.0)) * exp(-st * 3.0)) * visb * k;
            let Rs = 70.0 + st * 7.0;
            if (db < Rs * 2.0 && visb > 0.5) {
                let pq = (rd * tcb - Bc) / Rs;
                let sn = gfbm2(vec2<f32>(pq.x + pq.y * 0.7, pq.z - pq.y * 0.6) * 2.0 + vec2<f32>(st * 0.08, seed));
                let sd = exp(-pow(db / Rs, 2.0)) * (0.3 + 0.9 * sn) * smoothstep(0.2, 1.2, st) * (1.0 - smoothstep(8.0, 24.0, st));
                col = mix(col, vec3<f32>(0.22, 0.2, 0.19) * dim * (0.6 + 0.6 * sn) + lava_ramp(0.5) * exp(-st * 1.2) * 0.4, saturate(sd * 0.85));
            }
        }
    }
    // the pieces striking: fireballs bursting up off the roof (seen past its edges), fire left burning on it
    for (var j = 0; j < 6; j = j + 1) {
        let dt = time - hits[j].w;
        if (dt > 0.0 && dt < 5.0 && time < DF_FALL0 + 1.0) {
            let T = df_hover(g, DF_SPLIT, hits[j].xyz) - cam;
            let Rf = 60.0 * (1.0 - exp(-dt * 3.5)) + 4.0;
            let C = T + vec3<f32>(0.0, Rf * 0.5 + dt * 10.0, 0.0);
            let tc = dot(C, rd);
            if (tc > 0.0) {
                let dc = length(C - rd * tc);
                let visf = select(1.0, select(0.0, 0.1, !df_blocks(P, C)), (!sky_h && tc > scene_lh) || tc - Rf * 0.5 > ship_t);
                let fire = exp(-pow(dc / (Rf * (0.75 + 0.4 * gfbm2(vec2<f32>(dc * 0.05, dt * 2.0 + f32(j))))), 2.0)) * exp(-dt * 0.9);
                add = add + (lava_ramp(0.5 + 0.5 * fire) * fire * 4.0 + vec3<f32>(1.5, 0.8, 0.35) / (1.0 + pow(dc / (Rf * 3.0), 2.0)) * exp(-dt * 2.5)) * visf * k;
            }
        }
    }

    // ---- the chunks blown off the roof's edges, tumbling down, burning, trailing smoke; their dust where they land ----
    if (time > DF_SPLIT + 1.5 && time < DF_FALL1 + 2.0) {
        for (var i = 0; i < DF_CHUNKS; i = i + 1) {
            let tb = DF_SPLIT + 1.6 + 1.4 * mh(u32(i), su, 31u);
            let a = time - tb;
            if (a <= 0.0) {
                continue;
            }
            let side = select(-1.0, 1.0, i < DF_CHUNKS / 2);
            let x = -500.0 + 80.0 * f32(i % (DF_CHUNKS / 2));
            let hb = df_heading(g, tb);
            let nn = vec2<f32>(-hb.y, hb.x) * side;
            if (dot(nn, g.ax) < -0.25) {
                continue;
            }
            let vh = 22.0 + 14.0 * mh(u32(i), su, 32u);
            let vy = 8.0 + 10.0 * mh(u32(i), su, 33u);
            let p0 = df_hover(g, tb, vec3<f32>(x, 150.0, side * (ms_half_w(x) - 2.0))) - cam;
            let tl = (vy + sqrt(vy * vy + 2.0 * DF_G * (p0.y + cam.y - g.by))) / DF_G;
            let pos = p0 + vec3<f32>(nn.x * vh * a, vy * a - 0.5 * DF_G * a * a, nn.y * vh * a);
            if (a < tl) {
                let a1 = max(a - 1.6, 0.0);
                let tail = p0 + vec3<f32>(nn.x * vh * a1, vy * a1 - 0.5 * DF_G * a1 * a1, nn.y * vh * a1);
                let q = ray_seg(rd, pos, tail);
                let vis = select(1.0, 0.0, (!sky_h && q.y > scene_lh) || q.y > ship_t);
                let w = max(8.0 + 14.0 * q.z, q.y * 0.003);
                if (q.x > w * 3.0 + 10.0) {
                    continue;
                }
                if (vis > 0.0) {
                    let sn = gfbm2(vec2<f32>(q.z * 6.0 - a, q.x / w + f32(i)));
                    col = mix(col, vec3<f32>(0.09, 0.085, 0.08) * dim * (0.6 + 0.7 * sn), saturate(exp(-pow(q.x / w, 2.0)) * (0.3 + 0.7 * sn) * (8.0 / w)) * vis);
                    add = add + lava_ramp(0.7 - q.z * 0.5) * exp(-pow(q.x / (w * 0.3), 2.0)) * (1.0 - q.z) * (1.0 - q.z) * (8.0 / w) * vis * k;
                }
                let bx = df_box(pos, rd, vec3<f32>(14.0, 6.0, 10.0), normalize(vec3<f32>(fh21(vec2<f32>(f32(i), 1.0)), 0.5, fh21(vec2<f32>(f32(i), 2.0))) - 0.3), a * (1.0 + fh21(vec2<f32>(f32(i), 3.0))));
                if (bx.x > 0.0 && bx.x < min(scene_lh, ship_t)) {
                    let lam = 0.2 + 0.8 * max(dot(bx.yzw, sun), 0.0) * day;
                    col = vec3<f32>(0.06, 0.065, 0.07) * lam * dim + lava_ramp(0.6) * max(dot(bx.yzw, -normalize(vec3<f32>(nn.x, 0.0, nn.y))), 0.0) * 1.2;
                }
            } else if (a - tl < 3.0) {
                let ga = a - tl;
                let C = p0 + vec3<f32>(nn.x * vh * tl, 0.0, nn.y * vh * tl);
                let Cg = vec3<f32>(C.x, g.by - cam.y + 4.0 + ga * 4.0, C.z);
                let tc = dot(Cg, rd);
                if (tc > 0.0) {
                    let dc = length(Cg - rd * tc);
                    let Rf = 7.0 + 6.0 * (1.0 - exp(-ga * 4.0));
                    let visf = select(1.0, smoothstep(tc - Rf, tc, scene_lh), !sky_h);
                    add = add + lava_ramp(0.6) * exp(-pow(dc / Rf, 2.0)) * exp(-ga * 2.2) * 3.0 * visf * k;
                    col = mix(col, vec3<f32>(0.28, 0.23, 0.18) * dim, exp(-pow(dc / (Rf * 1.6), 2.0)) * smoothstep(0.1, 0.6, ga) * (1.0 - ga / 3.0) * 0.7 * visf);
                }
            }
        }
    }

    // ---- the smoke streaming up off the fires on its roof, then left behind along its fall --------------------------
    if (time > hits[0].w - 0.5 && time < DF_END - 4.0) {
        let tm = 0.5 * (DF_FALL0 + min(time, DF_FALL1 + DF_SLIDE));
        let Pm = df_pose(g, select(DF_FALL0, tm, time > DF_FALL0), cam);
        let fade = 1.0 - smoothstep(DF_OPEN, DF_END - 4.0, time);
        let burning = 1.0 - smoothstep(DF_OPEN, DF_OPEN + 1.5, time);
        let wind = vec3<f32>(4.0, 0.0, 1.5);
        for (var j = 0; j < 6; j = j + 1) {
            let tj = hits[j].w;
            if (time < tj) {
                continue;
            }
            let l = hits[j].xyz + vec3<f32>(0.0, 6.0, 0.0);
            let Wh = df_hover(g, DF_SPLIT, l) - cam;
            let Wn = select(Wh, df_world(P, l), time > DF_FALL0);
            let Wm = select(Wh, df_world(Pm, l), time > DF_FALL0);
            let up = 20.0 * (min(time, DF_FALL0 + 4.0) - tj);
            var bq = vec3<f32>(1.0e9, 0.0, 0.0);
            var bage = 0.0;
            var bw = 1.0;
            var blen = 1.0;
            for (var sgm = 0; sgm < 3; sgm = sgm + 1) {
                // the column rising off the fire while it hung there; then the trail from where it is back up to it
                var a = Wh + wind * (time - tj) * 0.5;
                var b = Wh + vec3<f32>(0.0, up, 0.0) + wind * (time - tj);
                var age_a = max(time - DF_FALL0, 0.0);
                var age_b = time - tj;
                if (sgm == 1) {
                    a = Wn;
                    b = Wm + wind * (time - tm);
                    age_a = 0.0;
                    age_b = time - tm;
                } else if (sgm == 2) {
                    a = Wm + wind * (time - tm);
                    b = Wh + wind * (time - DF_FALL0);
                    age_a = time - tm;
                    age_b = time - DF_FALL0;
                }
                if (sgm > 0 && time <= DF_FALL0) {
                    continue;
                }
                let q = ray_seg(rd, a, b);
                let age = mix(age_a, age_b, q.z);
                let w = 14.0 + 5.0 * age + 6.0 * f32(j % 2);
                if (q.x / max(w, q.y * 0.0015) < bq.x / max(bw, bq.y * 0.0015)) {
                    bq = q;
                    bage = age;
                    bw = w;
                    blen = length(b - a) * q.z + f32(sgm) * 400.0;
                }
            }
            let wp = max(bw, bq.y * 0.0015);
            let vis = select(1.0, 1.0 - smoothstep(scene_lh - 2.0, scene_lh + 2.0, bq.y), !sky_h) * select(1.0, 0.0, bq.y > ship_t + 4.0);
            if (bq.x < wp * 2.5 && vis > 0.0) {
                let sn = gfbm2(vec2<f32>(blen * 0.03 - time * 0.15, bq.x / wp * 1.5 + f32(j) * 5.0));
                let dens = exp(-pow(bq.x / wp, 2.0)) * (bw / wp) * (0.35 + 0.9 * sn) * exp(-bage / 40.0) * fade * 1.1;
                let fire = exp(-bage * 1.5) * exp(-pow(bq.x / (wp * 0.5), 2.0)) * burning;
                col = mix(col, vec3<f32>(0.1, 0.095, 0.09) * dim * (0.55 + 0.6 * sn) + lava_ramp(0.55) * fire * 0.8, saturate(dens) * vis);
                add = add * (1.0 - saturate(dens) * vis * 0.7) + lava_ramp(0.6 + 0.3 * sn) * fire * 1.5 * vis * k;
            }
        }
    }

    // ---- the crash: a fireball where the stern strikes, and the dust rolling out over everything -----------------
    if (crashed && crash_t < 6.0) {
        let C = c0w - cam + vec3<f32>(0.0, 20.0 + crash_t * 12.0, 0.0);
        let tc = dot(C, rd);
        if (tc > 0.0) {
            let dc = length(C - rd * tc);
            let Rf = 110.0 * (1.0 - exp(-crash_t * 2.5)) + 10.0;
            let nz = gfbm2(vec2<f32>(atan2(dot(rd * tc - C, vec3<f32>(0.0, 1.0, 0.0)), dot(rd * tc - C, vec3<f32>(rd.z, 0.0, -rd.x))) * 1.5, dc / Rf * 2.0 - crash_t * 2.0));
            let fire = exp(-pow(dc / (Rf * (0.7 + 0.5 * nz)), 2.0)) * exp(-crash_t * 0.7);
            let visf = select(1.0, smoothstep(tc - Rf * 1.2, tc - Rf * 0.2, scene_lh), !sky_h) * select(1.0, 0.12, ship_t < tc - Rf);
            add = add + (lava_ramp(0.45 + 0.55 * fire) * fire * 4.0 + vec3<f32>(1.6, 0.9, 0.4) / (1.0 + pow(dc / (Rf * 2.5), 2.0)) * exp(-crash_t * 1.8)) * visf * k;
        }
    }
    if (time > DF_FALL1 - 1.0) {
        let mid = 0.5 * (g.c0 + g.ps + g.hf * 480.0);
        let R = min(260.0 + max(crash_t, 0.0) * 120.0, 1000.0);
        let hs = 4.0 + 12.0 * sqrt(max(crash_t, 0.0));
        // (settling, and drawn into the black hole the moment it opens)
        let dd = 0.009 * smoothstep(DF_FALL1 - 1.0, DF_FALL1 + 1.5, time) * exp(-max(crash_t - 4.0, 0.0) / 14.0) * (1.0 - smoothstep(DF_OPEN, DF_OPEN + 3.0, time));
        if (dd > 0.0) {
            let tr = df_dust(cam, rd, scene_lh, mid, R, g.by, hs, dd, time, seed);
            let lightd = mix(vec3<f32>(0.16, 0.13, 0.1), vec3<f32>(0.5, 0.43, 0.34), tr.y) * (0.3 + 0.7 * day) * (1.0 + flash * 0.4)
                + lava_ramp(0.5) * 0.25 * exp(-max(crash_t, 0.0) / 3.0) * (1.0 - tr.y);
            col = col * tr.x + lightd * (1.0 - tr.x) * dim;
            add = add * tr.x;
        }
    }

    // ---- the black hole's debris: wreck and ground torn up round it, tumbling in, eaten or flung --------------------
    if (opened && ef < 2.5) {
        let tch = dot(H, rd);
        var best = min(scene_lh, ship_t);
        let rsn = max(rs, 0.8);
        let E1 = normalize(vec3<f32>(1.0, 0.0, 0.0) - nd * nd.x);
        let E2 = normalize(vec3<f32>(0.0, 0.0, 1.0) - nd * nd.z - E1 * dot(vec3<f32>(0.0, 0.0, 1.0), E1));
        let ks = array<u32, 5>(pcg(su ^ pcg(21u)), pcg(su ^ pcg(22u)), pcg(su ^ pcg(23u)), pcg(su ^ pcg(24u)), pcg(su ^ pcg(25u)));
        // (until they are flung, all of them are within 100 blocks of the hole)
        let near_h = tch > -100.0 && length(H - rd * max(tch, 0.0)) < 100.0;
        for (var i = 0; i < DFD_N; i = i + 1) {
            let fi = f32(i);
            let h1 = fh21(vec2<f32>(fi, seed + 5.0));
            let flung = h1 < 0.22;
            if (!near_h && !flung) {
                continue;
            }
            let tr = df_torn(g, i, ks);
            let s = min(bt, DF_LIFE) - tr.z;
            if (s <= 0.0) {
                continue;
            }
            let big = tr.w >= 2.0;
            let wreck = fract(tr.w * 0.5) > 0.25;
            let hs = select(0.5, 1.0, big);
            let gy = df_ground(g, tr.xy + 0.5);
            let y_c = select(gy - select(0.0, 1.0, big), gy + 1.0, wreck) + select(0.5, 1.0, big);
            let src = vec3<f32>(tr.x + select(0.5, 0.0, big), y_c, tr.y + select(0.5, 0.0, big)) - cam;
            let h2 = fh21(vec2<f32>(fi, seed + 9.0));
            let T_in = 3.2 + 1.8 * h2;
            let u_f = 0.5 + 0.2 * h2;
            let ub = s / T_in;
            let u = min(ub, select(1.0, u_f, flung));
            let a0 = atan2(src.z + cam.z - g.ps.y, src.x + cam.x - g.ps.x);
            let R0 = length(src.xz + cam.xz - g.ps);
            let r = mix(rsn * 0.95, R0, pow(1.0 - u, 0.75));
            let thd = a0 - (3.0 + 3.0 * h1) * u * u;
            let lift = smoothstep(0.0, 0.45, u);
            let ground_r = vec3<f32>(g.ps.x, y_c, g.ps.y) - cam + vec3<f32>(cos(thd), 0.0, sin(thd)) * r;
            let gp = mix(src, ground_r, smoothstep(0.0, 0.15, u));
            var c = mix(gp, H + (E1 * cos(thd) + E2 * sin(thd)) * r, lift) + vec3<f32>(0.0, sin(lift * 3.14159) * 12.0, 0.0);
            var alive = smoothstep(0.0, 0.05, s);
            if (flung && ub > u_f) {
                let dt = (ub - u_f) * T_in;
                c = c + ((E1 * sin(thd) - E2 * cos(thd)) * 70.0 + nd * 18.0) * dt;
                alive = alive * (1.0 - smoothstep(2.5, 4.0, dt));
            } else if (!flung) {
                alive = alive * (1.0 - step(1.0, ub));
            }
            if (ef > 0.0) {
                c = c + normalize(c - H) * ef * 70.0;
                alive = alive * (1.0 - smoothstep(1.0, 2.5, ef));
            }
            if (alive < 0.01) {
                continue;
            }
            let tq = dot(c, rd);
            if (tq < 0.0 || length(c - rd * tq) > hs * 1.8 || tq - hs * 1.8 > best) {
                continue;
            }
            let ax = normalize(vec3<f32>(fh21(vec2<f32>(fi, 1.0)), fh21(vec2<f32>(fi, 2.0)), fh21(vec2<f32>(fi, 3.0))) - 0.5 + 1.0e-3);
            let bx = df_box(c, rd, vec3<f32>(hs), ax, s * (1.5 + 3.0 * fh21(vec2<f32>(fi, 4.0))));
            if (bx.x < 0.0 || bx.x > best || (swallowed && bx.x > tch)) {
                continue;
            }
            best = bx.x;
            let nw = bx.yzw;
            let lp = rd * bx.x - c;
            let px = floor((lp.xz + lp.y) * 8.0);
            let kind = min(i32(fh21(vec2<f32>(fi, seed + 13.0)) * 4.0), 3);
            var albedo = srgb_to_linear(debris_tex(kind, px, nw.y > 0.5, 0.0, seed + fi));
            if (wreck) {
                albedo = vec3<f32>(0.05, 0.055, 0.06) * (0.7 + 0.6 * fh21(px + vec2<f32>(fi)));
            }
            let rl = length(c - H) / rsn;
            let diskl = vec3<f32>(2.2, 1.0, 0.45) * max(dot(nw, -normalize(c - H)), 0.0) * disk_env * 6.0 / (1.0 + rl * 0.5);
            let glow = smoothstep(rsn * 4.0, rsn * 1.2, r) * f32(!(flung && ub > u_f));
            var cc = albedo * ((0.3 + 0.7 * max(dot(nw, sun), 0.0) * day) * dim + diskl);
            cc = cc + vec3<f32>(2.6, 0.7, 0.15) * glow * glow * 1.5 + vec3<f32>(0.3, 2.0, 0.6) * f32(wreck) * step(0.85, fh21(px)) * 0.8;
            col = cc * smoothstep(1.0, 1.9, rl) * alive;
            add = add * 0.15;
        }
    }

    // ---- the ground it displaced as it dug in: surging out and up along its sides and in a wave before its bow, settling
    // into heaps (the real ones near its stern take over as they are built; strike.rs's df_berms) ----------------------
    if (time > DF_FALL1 && time < DF_END) {
        let rise = smoothstep(DF_FALL1 + 0.4, DF_FALL1 + DF_SLIDE + DF_SETTLE, time);
        let surge = 0.35 * exp(-pow((time - DF_FALL1 - 3.4) / 1.5, 2.0));
        let hf = g.hf;
        let sd = vec2<f32>(-hf.y, hf.x);
        let mw = g.ps + hf * (-DF_XP);
        let o2 = cam.xz - mw;
        let xa0 = dot(o2, hf);
        let xa1 = dot(rd.xz, hf);
        let zb0 = dot(o2, sd);
        let zb1 = dot(rd.xz, sd);
        var bt_hit = min(scene_lh, 6000.0);
        var bn = vec3<f32>(0.0, 1.0, 0.0);
        var bxa = 0.0;
        var found = false;
        for (var band = 0; band < 3; band = band + 1) {
            // the band's stretch of the view ray: beside either side (out from its edge), or before its bow
            var t0 = 0.0;
            var t1 = bt_hit;
            let side = select(1.0, -1.0, band == 1);
            if (band < 2) {
                let za = side * zb1;
                let lo = (150.0 - side * zb0) / select(za, 1.0e-6, abs(za) < 1.0e-6);
                let hi = (360.0 - side * zb0) / select(za, 1.0e-6, abs(za) < 1.0e-6);
                t0 = max(t0, min(lo, hi));
                t1 = min(t1, max(lo, hi));
            } else {
                let lo = (550.0 - xa0) / select(xa1, 1.0e-6, abs(xa1) < 1.0e-6);
                let hi = (680.0 - xa0) / select(xa1, 1.0e-6, abs(xa1) < 1.0e-6);
                t0 = max(t0, min(lo, hi));
                t1 = min(t1, max(lo, hi));
            }
            // and under the heaps' top
            let ylo = (g.by - 2.0 - cam.y) / select(rd.y, 1.0e-6, abs(rd.y) < 1.0e-6);
            let yhi = (g.by + 30.0 - cam.y) / select(rd.y, 1.0e-6, abs(rd.y) < 1.0e-6);
            t0 = max(t0, min(ylo, yhi));
            t1 = min(t1, max(ylo, yhi));
            if (t1 <= t0) {
                continue;
            }
            var prev = 1.0;
            var tp = t0;
            for (var i = 0; i <= 11; i = i + 1) {
                let tt = mix(t0, t1, f32(i) / 11.0);
                let xa = xa0 + xa1 * tt;
                let zb = zb0 + zb1 * tt;
                var hb = 0.0;
                if (band < 2) {
                    let e = side * zb - ms_half_w(xa) - 18.0 * (1.0 - rise);
                    hb = df_berm_h(xa, e) * step(abs(xa), 560.0);
                } else {
                    hb = 22.0 * exp(-pow((xa - 576.0 - 14.0 * (1.0 - rise)) / 14.0, 2.0)) * (1.0 - smoothstep(180.0, 270.0, abs(zb)));
                }
                hb = hb * (rise + surge) * (0.85 + 0.3 * fvnoise(vec2<f32>(xa, zb) * 0.06));
                let dh = cam.y + rd.y * tt - g.by - hb;
                if (dh < 0.0 && hb > 0.3) {
                    let th = mix(tp, tt, prev / max(prev - dh, 1.0e-4));
                    if (th < bt_hit) {
                        bt_hit = th;
                        bxa = xa;
                        let e2 = select(xa - 576.0, side * zb - ms_half_w(xa), band < 2);
                        let slope = select(-(e2 - 14.0) / 13.0, -(e2 - 14.0) / 14.0, band == 2) * hb * 0.15;
                        let out = select(vec2<f32>(sd * side), hf, band == 2);
                        bn = normalize(vec3<f32>(-out.x * slope, 1.0, -out.y * slope));
                        found = true;
                    }
                    break;
                }
                prev = dh;
                tp = tt;
            }
        }
        // where its real heaps stand they take over once built; further along it the drawn ones last the strike
        let real = select(1.0 - smoothstep(DF_FALL1 + 9.0, DF_FALL1 + 13.0, time), 1.0 - smoothstep(DF_END - 3.0, DF_END, time), bxa > DF_XP + DF_REAL_A + 8.0);
        if (found && real > 0.0) {
            let pb = cam + rd * bt_hit;
            let n1 = fvnoise(pb.xz * 0.4);
            let n2 = fvnoise(pb.xz * 0.07 + vec2<f32>(3.0, 1.0));
            let alb = mix(vec3<f32>(0.2, 0.14, 0.09), vec3<f32>(0.22, 0.21, 0.2), smoothstep(0.65, 0.8, n2)) * (0.75 + 0.4 * n1);
            let lam = 0.3 + 0.7 * max(dot(bn, sun), 0.0) * day;
            col = mix(col, alb * lam * dim, real);
            add = add * (1.0 - real);
        }
        // clods of earth and rock flung out over the land as it digs in
        if (time < DF_FALL1 + 7.0) {
            for (var i = 0; i < 28; i = i + 1) {
                let fi = f32(i);
                let t0 = DF_FALL1 + 0.2 + 4.0 * fh21(vec2<f32>(fi, 61.0));
                let a_ = time - t0;
                if (a_ <= 0.0 || a_ > 4.0) {
                    continue;
                }
                let side = select(-1.0, 1.0, fh21(vec2<f32>(fi, 63.0)) < 0.5);
                let xl = -560.0 + 1120.0 * fh21(vec2<f32>(fi, 65.0));
                let src = mw + hf * xl + sd * side * (ms_half_w(xl) + 6.0);
                let vh = 10.0 + 18.0 * fh21(vec2<f32>(fi, 67.0));
                let vy = 16.0 + 16.0 * fh21(vec2<f32>(fi, 69.0));
                let dir = sd * side;
                let pc = vec3<f32>(src.x + dir.x * vh * a_, g.by + 4.0 + vy * a_ - 8.0 * a_ * a_, src.y + dir.y * vh * a_) - cam;
                if (pc.y + cam.y < g.by - 2.0) {
                    continue;
                }
                let sz = 1.5 + 2.0 * fh21(vec2<f32>(fi, 71.0));
                let tq = dot(pc, rd);
                if (tq > 0.0 && length(pc - rd * tq) < sz * 2.0) {
                    let bx = df_box(pc, rd, vec3<f32>(sz, sz * 0.8, sz), normalize(vec3<f32>(fi, 1.0, 2.0)), a_ * 3.0);
                    if (bx.x > 0.0 && bx.x < scene_lh) {
                        col = vec3<f32>(0.2, 0.14, 0.09) * (0.3 + 0.7 * max(dot(bx.yzw, sun), 0.0) * day) * dim;
                    }
                }
            }
        }
    }

    // ---- the pieces it sheds as it falls: plates, girders, chunks and burning fragments, tumbling down the whole way,
    // catching the light, the bigger trailing smoke; dust where they come down (strike.rs's DfGeo::shed) ------------
    if (time > DF_SHED_T0 && time < DF_FALL1 + 8.0) {
        let sk41 = pcg(su ^ pcg(41u));
        let sk42 = pcg(su ^ pcg(42u));
        let sk43 = pcg(su ^ pcg(43u));
        let sk44 = pcg(su ^ pcg(44u));
        let sk45 = pcg(su ^ pcg(45u));
        let sk46 = pcg(su ^ pcg(46u));
        let sk47 = pcg(su ^ pcg(47u));
        for (var e = 0; e < DF_SHED / DF_SHED_PER; e = e + 1) {
            let te = DF_SHED_T0 + DF_SHED_DT * f32(e);
            if (time < te) {
                break;
            }
            if (time > te + 13.0) {
                continue;
            }
            let Pe = df_pose(g, te, cam);
            let ve = df_vel(g, te);
            let a_ = time - te;
            // (all its pieces are still near where the ship was, falling with it)
            let cen = df_world(Pe, vec3<f32>(0.0, 75.0, 0.0)) + ve * a_ + vec3<f32>(0.0, -0.5 * DF_G * a_ * a_, 0.0);
            let tcen = dot(cen, rd);
            if (length(cen - rd * max(tcen, 0.0)) > 650.0 + 30.0 * a_) {
                continue;
            }
            for (var j = 0; j < DF_SHED_PER; j = j + 1) {
                let ku = u32(e * DF_SHED_PER + j);
                let x = -560.0 + 1120.0 * pow(f32(pcg(ku ^ sk41)) * (1.0 / 4294967296.0), 1.7);
                let hw = ms_half_w(x);
                let h42 = f32(pcg(ku ^ sk42)) * (1.0 / 4294967296.0);
                let h43 = f32(pcg(ku ^ sk43)) * (1.0 / 4294967296.0);
                let h44 = f32(pcg(ku ^ sk44)) * (1.0 / 4294967296.0);
                let sgn = select(1.0, -1.0, h43 < 0.5);
                var l = vec3<f32>(x, 150.0, sgn * (hw - 5.0));
                var nl = vec3<f32>(0.0, 0.6, sgn * 0.8);
                if (h42 < 0.5) {
                    l = vec3<f32>(x, 0.0, (h43 - 0.5) * 2.0 * (hw - 10.0));
                    nl = vec3<f32>(0.0, -1.0, 0.0);
                } else if (h42 < 0.8) {
                    l = vec3<f32>(x, 20.0 + 120.0 * h44, sgn * (hw - 1.0));
                    nl = vec3<f32>(0.0, 0.0, sgn);
                }
                let p0 = df_world(Pe, l);
                let nw = Pe.a * nl.x + Pe.u * nl.y + Pe.d * nl.z;
                let v = ve + nw * (6.0 + 14.0 * f32(pcg(ku ^ sk45)) * (1.0 / 4294967296.0)) + vec3<f32>(0.0, 4.0 * h44, 0.0);
                let cls = min(i32(f32(pcg(ku ^ sk46)) * (1.0 / 4294967296.0) * 4.0), 3);
                let size = 0.6 + f32(pcg(ku ^ sk47)) * (1.0 / 4294967296.0);
                let tl = (v.y + sqrt(v.y * v.y + 2.0 * DF_G * max(p0.y + cam.y - g.by, 0.0))) / DF_G;
                let fi = f32(ku);
                if (a_ < tl) {
                    let pos = p0 + v * a_ + vec3<f32>(0.0, -0.5 * DF_G * a_ * a_, 0.0);
                    var hs = vec3<f32>(10.0, 1.0, 7.0);
                    if (cls == 1) {
                        hs = vec3<f32>(16.0, 1.2, 1.2);
                    } else if (cls == 2) {
                        hs = vec3<f32>(6.0, 5.0, 6.0);
                    } else if (cls == 3) {
                        hs = vec3<f32>(2.0, 2.0, 2.0);
                    }
                    hs = hs * size;
                    // the smoke and fire it trails (chunks and burning fragments)
                    if (cls >= 2) {
                        let a1 = max(a_ - 1.4, 0.0);
                        let tail = p0 + v * a1 + vec3<f32>(0.0, -0.5 * DF_G * a1 * a1, 0.0);
                        let q = ray_seg(rd, pos, tail);
                        let w = max(hs.y * (1.2 + 3.0 * q.z), q.y * 0.002);
                        if (q.x < w * 2.5 && q.y < scene_lh) {
                            let sn = gfbm2(vec2<f32>(q.z * 6.0 - a_, q.x / w + fi));
                            col = mix(col, vec3<f32>(0.08, 0.075, 0.07) * dim * (0.6 + 0.7 * sn), saturate(exp(-pow(q.x / w, 2.0)) * (0.3 + 0.6 * sn) * (1.0 - q.z)));
                            add = add + lava_ramp(0.75 - 0.5 * q.z) * exp(-pow(q.x / (w * 0.35), 2.0)) * (1.0 - q.z) * (1.0 - q.z) * select(0.6, 1.6, cls == 3) * k;
                        }
                    }
                    let tq = dot(pos, rd);
                    let reach = length(hs);
                    if (tq > 0.0 && length(pos - rd * tq) < reach && tq - reach < scene_lh) {
                        let ax = normalize(vec3<f32>(fh21(vec2<f32>(fi, 1.0)), fh21(vec2<f32>(fi, 2.0)), fh21(vec2<f32>(fi, 3.0))) - 0.5 + 1.0e-3);
                        let bx = df_box(pos, rd, hs, ax, a_ * (0.8 + 2.0 * fh21(vec2<f32>(fi, 4.0))));
                        if (bx.x > 0.0 && bx.x < scene_lh) {
                            let n = bx.yzw;
                            let lam = 0.2 + 0.8 * max(dot(n, sun), 0.0) * day;
                            let glint = pow(max(dot(reflect(rd, n), sun), 0.0), 40.0) * 3.0 * day;
                            col = vec3<f32>(0.07, 0.075, 0.08) * lam * dim + vec3<f32>(1.0, 0.95, 0.85) * glint * select(1.0, 0.2, cls >= 2);
                            if (cls == 3) {
                                col = col + lava_ramp(0.7 + 0.2 * sin(time * 17.0 + fi)) * 2.5;
                            }
                        }
                    }
                } else if (a_ - tl < 2.5 && cls != 1) {
                    // where it comes down: a puff of dust and grit (a crater, for the big ones: strike.rs)
                    let ga = a_ - tl;
                    let C = p0 + vec3<f32>(v.x * tl, 0.0, v.z * tl);
                    let Cg = vec3<f32>(C.x, g.by - cam.y + 3.0 + ga * 5.0, C.z);
                    let tc = dot(Cg, rd);
                    if (tc > 0.0 && tc < scene_lh + 8.0) {
                        let dc = length(Cg - rd * tc);
                        let Rf = (3.0 + 5.0 * (1.0 - exp(-ga * 3.0))) * size;
                        col = mix(col, vec3<f32>(0.27, 0.22, 0.17) * dim, exp(-pow(dc / Rf, 2.0)) * (1.0 - ga / 2.5) * 0.75);
                        add = add + lava_ramp(0.6) * exp(-pow(dc / Rf, 2.0)) * exp(-ga * 3.0) * 1.5 * k;
                    }
                }
            }
        }
    }

    // ---- drawn in towards the engine as it fails, and into the hole: dust and grit streaming in, plating peeling off --
    if (time > DF_GROAN && ef < 0.5) {
        let rsn = max(rs, 3.0);
        let near_hole = length(H - rd * max(dot(H, rd), 0.0)) < 290.0;
        for (var i = 0; i < select(0, 40, near_hole); i = i + 1) {
            let fi = f32(i);
            let t0 = DF_GROAN + 1.0 + 14.0 * fh21(vec2<f32>(fi, 17.0));
            let dur = 2.2 + 1.5 * fh21(vec2<f32>(fi, 19.0));
            let a_ = time - t0;
            if (a_ < 0.0 || a_ > dur) {
                continue;
            }
            let ang0 = fh21(vec2<f32>(fi, 23.0)) * TAU;
            let r0 = 70.0 + 190.0 * fh21(vec2<f32>(fi, 29.0));
            let y0 = g.by + 2.0 + 60.0 * fh21(vec2<f32>(fi, 31.0));
            var pos = vec3<f32>(0.0);
            var pp = vec3<f32>(0.0);
            for (var m = 0; m < 2; m = m + 1) {
                let s_ = saturate((a_ - 0.12 * f32(m)) / dur);
                let r = r0 * (1.0 - s_ * s_) + rsn;
                let ang = ang0 + 2.5 * s_ * s_;
                let p = vec3<f32>(g.ps.x + cos(ang) * r, mix(y0, Hw.y, s_ * s_), g.ps.y + sin(ang) * r) - cam;
                if (m == 0) {
                    pos = p;
                } else {
                    pp = p;
                }
            }
            let q = ray_seg(rd, pos, pp);
            let w = max(0.8 + 2.5 * a_ / dur, q.y * 0.0012);
            if (q.x < w * 2.0 && q.y < scene_lh) {
                col = mix(col, vec3<f32>(0.14, 0.12, 0.1) * dim, exp(-pow(q.x / w, 2.0)) * 0.55);
                add = add + vec3<f32>(1.4, 0.6, 1.1) * exp(-pow(q.x / w, 2.0)) * smoothstep(0.6, 1.0, a_ / dur) * f32(opened) * 0.5 * k;
            }
        }
        // plating peeling off: before it opens from round the engine, then from just ahead of where it is breaking up;
        // pulled in, tumbling, stretched out as they near the hole, gone into the wreck, or into the hole
        for (var i = 0; i < 36; i = i + 1) {
            let fi = f32(i);
            let pre = i < 14;
            let t0 = select(DF_OPEN + 0.5 + 9.0 * fh21(vec2<f32>(fi, 41.0)), DF_GROAN + 1.5 + 4.5 * fh21(vec2<f32>(fi, 41.0)), pre);
            let dur = select(1.4 + fh21(vec2<f32>(fi, 43.0)), 2.4, pre);
            let a_ = time - t0;
            if (a_ < 0.0 || a_ > dur) {
                continue;
            }
            let s_ = a_ / dur;
            let xs = select(-370.0 + 930.0 * pow(saturate((t0 - DF_OPEN) / DF_SWALLOW), 1.8) + 15.0 + 80.0 * fh21(vec2<f32>(fi, 45.0)), -560.0 + 200.0 * fh21(vec2<f32>(fi, 45.0)), pre);
            let zs = (fh21(vec2<f32>(fi, 47.0)) - 0.5) * 2.0 * (ms_half_w(xs) - 10.0);
            let src = df_world(P, vec3<f32>(xs, MS_TOP, zs));
            let pos = H + rot_axis(mix(src, H, select(1.0, 0.8, pre) * s_ * s_) - H, nd, select(1.6, 0.4, pre) * s_ * s_);
            if (pre && length(pos - H) < 70.0) {
                continue;
            }
            let tq = dot(pos, rd);
            let hs = vec3<f32>(5.0 * (1.0 + 2.0 * s_ * s_ * s_), 0.6, 3.5) * (0.7 + 0.8 * fh21(vec2<f32>(fi, 49.0)));
            if (tq > 0.0 && length(pos - rd * tq) < length(hs) && tq - length(hs) < scene_lh) {
                let ax = normalize(vec3<f32>(fh21(vec2<f32>(fi, 51.0)) - 0.5, 0.7, fh21(vec2<f32>(fi, 53.0)) - 0.5));
                let bx = df_box(pos, rd, hs, ax, a_ * 2.5);
                if (bx.x > 0.0 && bx.x < scene_lh) {
                    let n = bx.yzw;
                    let near = exp(-length(pos - H) / 90.0);
                    col = vec3<f32>(0.06, 0.065, 0.07) * (0.25 + 0.75 * max(dot(n, sun), 0.0) * day) * dim
                        + vec3<f32>(1.0, 0.95, 0.85) * pow(max(dot(reflect(rd, n), sun), 0.0), 50.0) * 2.5 * day
                        + lava_ramp(0.5 + 0.5 * near) * near * 2.5 * f32(!pre);
                }
            }
        }
    }

    // ---- it collapses: a blinding flash, a shell of light running out, the light boring down into the ground --------
    if (ef > 0.0 && ef < 8.0) {
        let tcs = dot(H, rd);
        let bs = length(H - rd * max(tcs, 0.0));
        let re = ef * 90.0;
        let shell = exp(-pow((bs - re) / (2.0 + re * 0.06), 2.0)) * exp(-ef * 0.7) * select(0.0, 1.0, tcs > 0.0 || length(H) < re);
        add = add + vec3<f32>(1.6, 1.2, 2.4) * shell * 2.5 * k + vec3<f32>(2.2, 2.0, 2.6) * evap * evap * 1.4 * k;
        add = add + vec3<f32>(1.2, 0.9, 1.8) * exp(-bs * 0.05) * evap * 3.0 * k;
        let ah = axis_hit(H.xz, rd.xz, dot(rd.xz, rd.xz), cam.y, rd.y);
        if (ah.x > 0.0 && ah.z < Hw.y && ef < 1.2) {
            let visb = select(1.0, 1.0 - smoothstep(scene_lh - 0.6, scene_lh + 0.6, ah.x), !sky_h);
            add = add + vec3<f32>(3.0, 2.4, 5.0) * exp(-pow(ah.y / 3.0, 2.0)) * (1.0 - smoothstep(0.3, 1.2, ef)) * mix(0.3, 1.0, visb) * 4.0 * k;
        }
    }

    // ---- the lens: the meteor's glare as it comes, the disk's bloom, a streak through it -----------------------------
    if (time < DF_SPLIT) {
        let pm = project_rel(df_met_head(aim, mv, max(time, 5.0)) - cam);
        if (pm.z > 0.0 && !df_blocks(P, df_met_head(aim, mv, max(time, 5.0)) - cam)) {
            let dd = (uv - pm.xy) * vec2<f32>(aspect, 1.0);
            add = add + vec3<f32>(1.6, 0.9, 0.4) * met_env * met_env / (1.0 + dot(dd, dd) * 60.0) * 0.35 * k;
        }
    }
    if (pH.z > 0.0 && (opened || groan > 0.0)) {
        let dd = (uv - pH.xy) * vec2<f32>(aspect, 1.0);
        add = add + vec3<f32>(1.6, 1.2, 2.4) * exp(-pow((sdist - bt * 2.0) / 0.02, 2.0)) * exp(-max(bt, 0.0) * 2.2) * f32(opened) * 0.8 * k;
        add = add + vec3<f32>(1.2, 0.6, 0.35) * disk_env * hot * 0.25 / (1.0 + dot(dd, dd) * 40.0) * k;
        add = add + vec3<f32>(1.2, 0.5, 2.6) * exp(-abs(dd.y) * 240.0) * exp(-abs(dd.x) * 2.6) * (disk_env * 0.6 + evap * 2.0) * k;
    }
    let ps_c = project_rel(c0w - cam);
    if (ps_c.z > 0.0 && crashed && crash_t < 3.0) {
        let dd = (uv - ps_c.xy) * vec2<f32>(aspect, 1.0);
        add = add + vec3<f32>(2.0, 1.3, 0.7) * exp(-crash_t * 1.8) / (1.0 + dot(dd, dd) * 25.0) * 0.6 * k;
    }
    add = add + vec3<f32>(1.0, 0.9, 0.75) * select(0.0, exp(-st * 5.0), st > 0.0) * 0.12 * k;

    // ---- combine --------------------------------------------------------------
    var outc = col + add;
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    outc = outc * (1.0 - smoothstep(0.3, 1.0, vg) * (0.2 + 0.25 * f32(present) + 0.3 * sky_env + 0.15 * dust_env) * k);
    outc = aces(outc * 0.9);
    var srgb = linear_to_srgb(outc);
    // the instant the engine ruptures the picture goes negative
    srgb = mix(srgb, vec3<f32>(1.0) - srgb, saturate(open_ * 1.2 * k));
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
    return downfall(in);
}
