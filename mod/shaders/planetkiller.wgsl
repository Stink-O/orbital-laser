// Orbital Laser's post pass for the Planet Killer (laser 6). Like the Downfall's, the mod builds it from
// shaders/strike.wgsl up to its fs_main (the helpers: the noise, ray_seg, lava_ramp, project_rel, mh) less the other
// lasers' own functions, followed by this file, and sets it for a planet killer strike only, so its size costs the other
// lasers nothing. Validate with tools/check-shader.sh.

// ---- laser 6: the planet killer -----------------------------------------------------------------------------------
// Seven emitters far out round the horizon fire one after another, the first beyond the target, the rest rippling round
// both ways towards the player, and the daylight drains out of the sky as they do. Their beams race up to a point high
// over the target and meet there: a star swells where they meet, arcs of plasma crawling over it, until they fuse in a
// flash and a ring of light tears out across the sky. Then one beam, far thicker than theirs, comes down on the target
// while they go on feeding it: a fireball, a shock ring and a wall of dust racing out over the land, the ground splitting
// in molten cracks. Then the emitters cut out, their beams draining up into the star, which collapses and bursts, and a
// column of smoke stands over the crater as the daylight comes back. strike.rs times the same strike and opens the same
// cracks (pk_crack): keep the PK_* and pk_* in step.

const PK_N: i32 = 7;               // the emitters
const PK_H: f32 = 300.0;           // the nexus, where their beams meet, this high over the target
const PK_SRC_R: f32 = 1500.0;      // how far out the emitters stand
const PK_IGN0: f32 = 0.3;          // the first fires, the last by PK_IGN1
const PK_IGN1: f32 = 1.5;
const PK_RISE: f32 = 0.7;          // a beam's head reaches the nexus this long after its emitter fires
const PK_MERGE: f32 = 4.0;         // keep in step with strike.rs: PK_MERGE, PK_HIT, PK_CUT, PK_POP, PK_END
const PK_DROP: f32 = 4.1;          // the one beam leaves the nexus
const PK_HIT: f32 = 4.35;          // and lands
const PK_CUT: f32 = 13.5;          // the emitters cut out
const PK_DRAIN: f32 = 0.6;         // their beams drain up into the nexus over this long
const PK_POP: f32 = 14.4;          // it collapses and bursts
const PK_END: f32 = 24.0;          // the daylight is back (the strike runs 26 s)
const PK_BOWL: f32 = 40.0;         // the crater's radius (the laser's bowl_r)
const PK_CRACKS: i32 = 9;          // the cracks: from PK_RIM out, PK_SEG-block segments, opening at PK_CRACK_V blocks a
const PK_RIM: f32 = 38.0;          // second from PK_CRACK_T after the hit
const PK_SEG: f32 = 8.0;
const PK_CRACK_V: f32 = 70.0;
const PK_CRACK_T: f32 = 1.2;
// The beams' light: a searing white core in an electric blue, a deep cobalt glow round it.
const PK_WHITE: vec3<f32> = vec3<f32>(7.0, 8.0, 10.0);
const PK_HOT: vec3<f32> = vec3<f32>(0.9, 2.2, 6.0);
const PK_DEEP: vec3<f32> = vec3<f32>(0.08, 0.22, 1.8);

// Emitter i: where it stands (xyz) and when it fires (w). The first fires beyond the target as the player faces it, the
// rest alternately to its right and left, round towards the player; each a little off its place and its time.
fn pk_emitter(i: i32, seed: f32) -> vec4<f32> {
    let s = u32(seed);
    let side = select(-1.0, 1.0, i % 2 == 1);
    let a = wing_a() + 3.14159265 + side * f32((i + 1) / 2) * TAU / f32(PK_N) + (mh(u32(i), s, 31u) - 0.5) * 0.5;
    let r = PK_SRC_R * (0.8 + 0.4 * mh(u32(i), s, 32u));
    let t = PK_IGN0 + (PK_IGN1 - PK_IGN0) * f32(i) / f32(PK_N - 1) + (mh(u32(i), s, 33u) - 0.5) * 0.12;
    let tgt = target_pos();
    return vec4<f32>(tgt.x + cos(a) * r, tgt.y - 2.0, tgt.z + sin(a) * r, t);
}

// Crack i: x its heading out from the target, y how long it runs past PK_RIM. Its line wanders off that heading by
// pk_crack_off at each PK_SEG.
fn pk_crack(i: i32, seed: f32) -> vec2<f32> {
    let s = u32(seed);
    let a = (f32(i) + 0.7 * mh(u32(i), s, 21u)) * TAU / f32(PK_CRACKS) + mh(99u, s, 22u) * TAU;
    return vec2<f32>(a, 50.0 + 25.0 * mh(u32(i), s, 23u));
}
fn pk_crack_off(i: i32, j: i32, seed: f32) -> f32 {
    return select((mh(u32(i * 32 + j), u32(seed), 24u) - 0.5) * 0.16, 0.0, j == 0);
}

// How much of a light `t` along the view ray shows: all of it in front of the scene or against the sky, some through a
// cloud, none behind the land.
fn pk_occ(t: f32, scene_len: f32, sky: bool, cloud: bool) -> f32 {
    return select(select(0.0, 0.5, cloud), 1.0, sky || t < scene_len);
}

fn planet_killer(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let aspect = frame.resolution.x / frame.resolution.y;
    let time = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let crel = tgt - cam;
    let k = intensity_v();
    let seed = seed_v();
    let NX = crel + vec3<f32>(0.0, PK_H, 0.0);                  // the nexus

    // ---- timeline -------------------------------------------------------------
    // the daylight draining away as the emitters fire, back once it is over
    let dark = smoothstep(0.0, 2.2, time) * (1.0 - smoothstep(PK_POP + 1.5, PK_END, time));
    let charge = smoothstep(PK_IGN0 + PK_RISE, PK_MERGE, time) * f32(time < PK_POP);
    let merge_t = time - PK_MERGE;
    let merged = merge_t > 0.0;
    let burn = smoothstep(PK_DROP, PK_DROP + 0.05, time) * (1.0 - smoothstep(PK_CUT + PK_DRAIN, PK_CUT + PK_DRAIN + 0.4, time));
    let hit_t = time - PK_HIT;
    let landed = hit_t > 0.0;
    let pop_t = time - PK_POP;
    let popped = pop_t > 0.0;
    // (the screen flashes as it lands, a little as they fuse and as it bursts: the rest of their light is the nexus's)
    let flash = select(0.0, exp(-hit_t * 6.0) * 0.85, landed) + select(0.0, exp(-merge_t * 9.0) * 0.3, merged)
        + select(0.0, exp(-pop_t * 7.0) * 0.45, popped);
    let after = 1.0 - smoothstep(PK_END - 6.0, PK_END + 1.5, time);

    // the emitters, and how many beams are feeding the nexus
    var em: array<vec4<f32>, 7>;
    var fed = 0.0;
    for (var i = 0; i < PK_N; i = i + 1) {
        em[i] = pk_emitter(i, seed);
        fed = fed + saturate((time - em[i].w - PK_RISE) / 0.3);
    }
    // the nexus: a point when the first beam reaches it, swelling with each one after and with the charge, blazing
    // as they fuse, steady while it feeds the beam, collapsing to nothing as they drain, then gone in a burst
    let collapse = 1.0 - smoothstep(PK_CUT + 0.2, PK_POP, time);
    let Rn = (1.5 + 1.1 * fed + 8.0 * charge * charge + 12.0 * select(0.0, exp(-merge_t * 2.5), merged))
        * (0.93 + 0.07 * sin(time * 31.0) + 0.04 * sin(time * 53.0)) * collapse * f32(fed > 0.0);
    let glow_n = saturate(fed / 3.0) * (0.4 + 0.6 * charge + 0.6 * burn) * collapse;

    // ---- the light and the sky ------------------------------------------------
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);

    // ---- the shock rings bending the light: in the sky as they fuse, on the land as it lands -------------------
    let pT = project_rel(crel);
    let pN = project_rel(NX);
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    var off = vec2<f32>(0.0);
    if (landed && !sky0 && pT.z > 0.0) {
        let r0 = length(p0.xz - tgt.xz);
        let rs = 30.0 + 160.0 * pow(hit_t, 0.8);
        let m = exp(-pow((r0 - rs) / 5.0, 2.0)) * exp(-hit_t * 0.45);
        off = off + normalize(uv - pT.xy + vec2<f32>(1.0e-5)) * m * 0.02 * k;
    }
    if (burn > 0.001 && pT.z > 0.0) {
        // the air boiling round the beam's foot
        let m = exp(-length((uv - pT.xy) * vec2<f32>(aspect, 1.0)) / 0.08);
        let hw = vec2<f32>(gnoise2(uv * vec2<f32>(120.0, 45.0) + vec2<f32>(0.0, -time * 8.0)), gnoise2(uv * vec2<f32>(120.0, 45.0) + vec2<f32>(31.0, -time * 7.0))) - 0.5;
        off = off + hw * 0.006 * m * burn * k;
    }
    let uv2 = clamp(uv + off, vec2<f32>(0.002), vec2<f32>(0.998));

    // ---- the scene ------------------------------------------------------------
    let d = depth_at(uv2);
    let sky = is_sky(d);
    let rel = world_offset(uv2, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv2, 0.5));
    let rdb = normalize(world_offset(uv, 0.5));                // not bent
    let P = cam + rel;
    let cloud = !sky && abs(P.y - CLOUD_Y - 2.0) < 6.0;
    let ca = flash * 0.015 * k;
    let ca_dir = (uv2 - vec2<f32>(0.5)) * ca;
    var col = srgb_to_linear(vec3<f32>(
        textureSampleLevel(scene_color, linear_sampler, uv2 + ca_dir, 0.0).r,
        textureSampleLevel(scene_color, linear_sampler, uv2, 0.0).g,
        textureSampleLevel(scene_color, linear_sampler, uv2 - ca_dir, 0.0).b));
    // the sky goes to a deep night blue, the land dark under it; the clouds take the light of the nexus
    if (sky) {
        col = mix(col, vec3<f32>(0.004, 0.007, 0.022), 0.88 * dark * k);
    } else {
        col = col * (1.0 - 0.62 * dark * k);
    }
    var add = vec3<f32>(0.0);

    // ---- the emitters firing: each lights its stretch of the horizon, a column of light thrown up where it stands ----
    for (var i = 0; i < PK_N; i = i + 1) {
        let e = em[i];
        let et = time - e.w;
        if (et <= 0.0) {
            continue;
        }
        let S = e.xyz - cam;
        let ds = length(S);
        let sdir = S / ds;
        let c = 1.0 - dot(rd, sdir);
        let live = 1.0 - smoothstep(PK_CUT, PK_CUT + PK_DRAIN, time);
        let burst = exp(-et * 2.2);
        // (the horizon round it lit up, along the horizon more than above it: in the sky and on the far land, a little
        // on the near land)
        let low = exp(-abs(rd.y - sdir.y) / 0.05);
        let horizon = exp(-c / 0.02) * low * (1.6 * burst + 0.25 * live) + exp(-c / 0.0015) * (2.0 * burst + 0.5 * live);
        add = add + PK_DEEP * horizon * select(0.15, 1.0, sky || scene_len > ds * 0.6) * k;
        // the point of it, white
        let vis = select(0.0, 1.0, sky || scene_len > ds - 30.0);
        add = add + (PK_WHITE * exp(-c / 2.0e-6) * 0.6 + PK_HOT * exp(-c / 4.0e-5) * 0.4) * (live + 2.0 * burst) * vis * k;
        // the column thrown up as it fires, falling back
        let q = ray_seg(rdb, S, S + vec3<f32>(0.0, 260.0 * (1.0 - exp(-et * 6.0)), 0.0));
        let w = max(9.0, q.y * 0.0013);
        add = add + (PK_HOT * exp(-pow(q.x / w, 2.0)) + PK_DEEP * exp(-q.x / (w * 4.0)) * 0.3) * (9.0 / w) * exp(-et * 1.6)
            * (1.0 - 0.7 * q.z) * pk_occ(q.y, scene_len, sky, cloud) * k;
    }

    // ---- on the land: lit by the nexus and the beam, the shock ring, the crater and the cracks molten ----
    let rel2 = P.xz - tgt.xz;
    let r = length(rel2);
    let dy = P.y - tgt.y;
    if (!sky) {
        let on_ground = 1.0 - smoothstep(25.0, 40.0, dy);
        // the nexus lights everything under it, like a second sun
        let ln = NX + cam - P;
        col = col + col * vec3<f32>(1.0, 1.7, 3.2) * glow_n * 90000.0 / (dot(ln, ln) + 60000.0) * k;
        // the beam hard on the land round its foot
        col = col + col * vec3<f32>(1.6, 2.2, 3.6) * burn * 5000.0 / (r * r + dy * dy + 1500.0) * k;
        if (charge > 0.0 && hit_t < 0.5) {
            // charging: a ring of light closing in on the target, the dust lifting off it
            let fade = 1.0 - smoothstep(0.0, 0.5, hit_t);
            let conv = mix(90.0, 3.0, pow(charge, 1.4));
            add = add + PK_HOT * (exp(-pow((r - conv) / 1.5, 2.0)) * 0.9 + exp(-r / 10.0) * charge * charge * 0.6) * charge * on_ground * fade * k;
        }
        if (landed) {
            // the shock ring racing out over the land, kicking up dust as it goes
            let rs = 30.0 + 160.0 * pow(hit_t, 0.8);
            let ring = exp(-pow((r - rs) / 3.0, 2.0)) * exp(-hit_t * 0.6);
            add = add + (PK_HOT * 0.6 + vec3<f32>(1.2, 1.0, 0.8)) * ring * on_ground * k;
            let behind = smoothstep(rs, rs - 25.0, r) * smoothstep(rs - 120.0, rs - 40.0, r) * exp(-hit_t * 0.35);
            col = mix(col, vec3<f32>(0.16, 0.13, 0.11) * (0.3 + 0.7 * day) * (1.0 - 0.6 * dark), behind * 0.55 * on_ground * k);
            // the crater molten, hottest deepest, a crust closing over it as it cools so only its veins glow
            if (r < PK_BOWL + 8.0) {
                let deep = saturate(-dy / 20.0);
                let heat = ((exp(-hit_t / 9.0) * 0.9 * (1.0 - 0.5 * r / PK_BOWL) + deep * 0.5 * exp(-hit_t / 25.0)) * (1.0 - smoothstep(PK_BOWL - 6.0, PK_BOWL + 8.0, r))
                    + burn * exp(-r / 14.0));
                let n = gfbm2(rel2 * 0.12 + vec2<f32>(P.y * 0.3, seed));
                let veins = exp(-pow((n - 0.5) / 0.07, 2.0));
                let molten = mix(veins * 0.9, 1.0, saturate(heat * heat));
                let hh = heat * molten * (0.8 + 0.4 * gnoise2(rel2 * 0.7 + vec2<f32>(time * 0.2, P.y)));
                add = add + lava_ramp(hh) * smoothstep(0.03, 0.25, heat * molten) * on_ground * after * 2.6 * k;
            }
            // the cracks running out from the rim, opening as the shock reaches them, molten down in them
            if (r > PK_RIM - 2.0 && r < PK_RIM + 80.0) {
                let ang = atan2(rel2.y, rel2.x);
                var crack = 0.0;
                for (var i = 0; i < PK_CRACKS; i = i + 1) {
                    let cr = pk_crack(i, seed);
                    let u = r - PK_RIM;
                    if (u > cr.y) {
                        continue;
                    }
                    let j = i32(floor(max(u, 0.0) / PK_SEG));
                    let f = fract(max(u, 0.0) / PK_SEG);
                    let a = cr.x + mix(pk_crack_off(i, j, seed), pk_crack_off(i, j + 1, seed), f);
                    var da = ang - a;
                    da = da - TAU * floor(da / TAU + 0.5);
                    let lat = abs(da) * r;
                    let hw = 0.5 + 2.5 * (1.0 - u / cr.y);
                    let open = saturate((hit_t - PK_CRACK_T - u / PK_CRACK_V) * 3.0);
                    crack = max(crack, (1.0 - smoothstep(hw - 0.4, hw + 0.8, lat)) * open + exp(-lat / (hw * 2.5)) * open * 0.3);
                }
                if (crack > 0.01) {
                    let cool = exp(-hit_t / 14.0);
                    let hh = (0.55 + 0.4 * cool) * (0.85 + 0.3 * gnoise2(rel2 * 0.5 + vec2<f32>(time * 0.3, 0.0)));
                    add = add + lava_ramp(hh) * crack * on_ground * after * 2.2 * k;
                }
            }
        }
    }
    // the clouds lit from above by the nexus, from below by the beam
    if (cloud) {
        let dn = length((P - cam - NX).xz);
        add = add + PK_HOT * (glow_n * 0.5 * exp(-dn / 160.0) + burn * 0.4 * exp(-length(rel2) / 60.0)) * k;
    }

    // ---- the shock dome: the air's blast front, a shell bending the light, lit at its edge, riding the shock ring ----
    if (landed && hit_t < 3.0) {
        let Rs = 30.0 + 160.0 * pow(hit_t, 0.8);
        let tcs = dot(crel, rd);
        let ps = rd * max(tcs, 0.0) - crel;
        let dcs = length(ps);
        let th = 3.0 + 8.0 * hit_t;
        let wpx = max(th, max(tcs, 1.0) * 0.002);
        let limb = exp(-pow((dcs - Rs) / wpx, 2.0)) * (th / wpx) * smoothstep(-5.0, 10.0, ps.y);
        add = add + (PK_HOT * 0.25 + vec3<f32>(0.5, 0.55, 0.6)) * limb * exp(-hit_t * 1.3) * pk_occ(tcs, scene_len, sky, cloud) * k;
    }

    // ---- the wall of dust thrown out round it, racing over the land and climbing ------------------------------------
    if (landed && hit_t < 14.0) {
        let Rw = 25.0 + 130.0 * (1.0 - exp(-hit_t * 0.35));
        let Hw = 10.0 + 75.0 * (1.0 - exp(-hit_t * 0.5));
        let c2 = cam.xz - tgt.xz;
        let v2 = rd.xz;
        let a2 = dot(v2, v2);
        let b2 = dot(c2, v2);
        let disc = b2 * b2 - a2 * (dot(c2, c2) - Rw * Rw);
        if (a2 > 1.0e-6 && disc > 0.0) {
            let sq = sqrt(disc);
            var dust = 0.0;
            for (var s = 0; s < 2; s = s + 1) {
                let tw = (-b2 + select(-sq, sq, s == 1)) / a2;
                if (tw <= 0.0 || (!sky && tw > scene_len)) {
                    continue;
                }
                let pw = cam + rd * tw;
                let hy = pw.y - tgt.y;
                let aw = atan2(pw.z - tgt.z, pw.x - tgt.x);
                let n = gfbm2(vec2<f32>(aw * 5.0 + seed, hy * 0.04 - hit_t * 0.4));
                let top = Hw * (0.55 + 0.8 * n);
                dust = max(dust, smoothstep(top, top * 0.3, hy) * smoothstep(-6.0, 2.0, hy) * (0.5 + 0.6 * n));
            }
            let fade = exp(-hit_t / 7.0) * smoothstep(0.0, 0.3, hit_t);
            // (lit by the day, and by the beam inside it)
            let lit = vec3<f32>(0.2, 0.18, 0.16) * (0.25 + 0.75 * day) * (1.0 - 0.6 * dark) + vec3<f32>(0.2, 0.28, 0.5) * burn * 0.6 * exp(-Rw / 160.0);
            col = mix(col, lit, saturate(dust * fade) * 0.85 * k);
            add = add * (1.0 - saturate(dust * fade) * 0.6);
        }
    }

    // ---- the smoke standing over the crater, lit from under by the melt ----------------------------------------
    if (landed) {
        let ht = 40.0 + 300.0 * (1.0 - exp(-hit_t * 0.15));
        let q = ray_seg(rd, crel, crel + vec3<f32>(0.0, ht, 0.0));
        let X = rd * q.y - crel;                                 // where the ray passes it, from the target
        let hq = X.y;
        let W = (18.0 + 2.5 * hit_t) * (0.7 + 0.6 * saturate(hq / ht)) * (1.0 + 1.0 * smoothstep(ht * 0.6, ht, hq));
        if (q.x < W * 1.8) {
            let vis = select(1.0, 1.0 - smoothstep(scene_len - 1.0, scene_len + 1.0, q.y), !sky);
            let side = dot(X, normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0)));
            let n = gfbm2(vec2<f32>(side / W * 1.3 + seed, hq / W * 0.8 - time * 0.25)) * 0.7 + gfbm2(vec2<f32>(side * 0.08, hq * 0.06 - time * 0.5)) * 0.3;
            let dens = exp(-pow(q.x / W, 2.0)) * (0.45 + 0.9 * n) * smoothstep(0.6, 3.0, hit_t) * (1.0 - smoothstep(ht * 0.8, ht * 1.05, hq)) * after;
            let under = exp(-max(hq, 0.0) / 30.0);
            let smoke = vec3<f32>(0.06, 0.055, 0.06) * (0.3 + 0.7 * day) * (1.0 - 0.6 * dark) * (0.7 + 0.5 * n)
                + lava_ramp(0.5) * under * 0.6 * exp(-hit_t / 10.0) + PK_HOT * burn * 0.05;
            col = mix(col, smoke, saturate(dens * 0.9) * vis * k);
            add = add * (1.0 - saturate(dens * 0.9) * vis * 0.7);
        }
    }

    // ---- the emitters' beams racing up to the nexus, surges running up them, then draining into it ----------------
    for (var i = 0; i < PK_N; i = i + 1) {
        let e = em[i];
        let et = time - e.w;
        if (et <= 0.0) {
            continue;
        }
        let S = e.xyz - cam;
        let u_head = saturate(et / PK_RISE);
        let u_tail = saturate((time - PK_CUT - 0.25 * mh(u32(i), u32(seed), 34u)) / PK_DRAIN);
        if (u_tail >= 1.0) {
            continue;
        }
        let A = S + (NX - S) * u_tail;
        let B = S + (NX - S) * u_head;
        let q = ray_seg(rdb, A, B);
        let len = length(NX - S);
        let along = mix(u_tail, u_head, q.z) * len;             // blocks from the emitter
        let rc = (1.6 + 1.0 * charge + 0.5 * burn + 2.5 * select(0.0, exp(-merge_t * 3.0), merged)) * (1.0 + 0.6 * smoothstep(len - 120.0, len, along)) * k;
        let w = max(rc, q.y * 0.0013);
        if (q.x > w * 40.0) {
            continue;
        }
        let en = rc / w;
        let occ = pk_occ(q.y, scene_len, sky, cloud);
        let fi = f32(i);
        let pulse = pow(0.5 + 0.5 * sin(along * 0.01 - time * 26.0 + fi * 1.7), 10.0) * charge + pow(0.5 + 0.5 * sin(along * 0.013 - time * 41.0 + fi), 14.0) * burn;
        let flick = 0.85 + 0.15 * sin(time * 47.0 + fi * 2.3);
        let core = exp(-pow(q.x / (w * 0.55), 2.0));
        let sheath = exp(-pow(q.x / (w * 1.8), 2.0));
        let glow = exp(-q.x / (w * 7.0));
        // its head blazing as it climbs
        let head = exp(-pow((1.0 - q.z) * (u_head - u_tail) * len / 10.0, 2.0)) * (1.0 - step(1.0, u_head));
        let b = PK_WHITE * core * (1.0 + 1.5 * pulse + 3.0 * head) * flick + PK_HOT * sheath * (0.7 + 1.6 * pulse + 2.0 * head)
            + PK_DEEP * glow * 0.4 * (1.0 - smoothstep(w * 25.0, w * 40.0, q.x));
        add = add + b * en * occ * k;
    }

    // ---- the nexus: a star where they meet, arcs crawling over it ----------------------------------------------
    let tcn = dot(NX, rd);
    let lum_n = Rn / 14.0;
    if (Rn > 0.01 && tcn > 0.0) {
        let dcn = length(NX - rd * tcn);
        let occ = pk_occ(tcn - Rn, scene_len, sky, cloud);
        let wpx = max(Rn, tcn * 0.0016);
        let en = Rn / wpx;
        let hx = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
        let hy = cross(hx, rd);
        let o = rd * tcn - NX;
        let p2 = vec2<f32>(dot(o, hx), dot(o, hy));
        let ang = atan2(p2.y, p2.x);
        let surf = gfbm2(vec2<f32>(ang * 2.5 + seed, dcn / wpx * 1.5 - time * 3.0));
        var star = PK_WHITE * 1.2 * (1.0 - smoothstep(wpx * 0.85, wpx * 1.05, dcn * (0.9 + 0.2 * surf)))
            + PK_HOT * exp(-max(dcn - wpx, 0.0) / (wpx * 0.6)) * (0.8 + 0.8 * surf) * en
            + PK_DEEP * exp(-dcn / (wpx * 4.0)) * 0.8 * en;
        if (dcn < wpx * 4.0 && time < PK_POP) {
            // arcs of plasma: down each beam into it, and leaping off it
            let tq = floor(time * 16.0);
            var arcs = 0.0;
            for (var i = 0; i < PK_N; i = i + 1) {
                let to = em[i].xyz - cam - NX;
                let d2 = normalize(vec2<f32>(dot(to, hx), dot(to, hy)) + vec2<f32>(1.0e-4, 0.0));
                let bl = bolt_line(p2, d2 * wpx * 0.6, d2 * wpx * (2.0 + 1.2 * fh21(vec2<f32>(f32(i), tq))), seed + f32(i) * 7.0, tq, wpx * 0.08);
                arcs = arcs + (bl.x + bl.y * 0.3) * step(em[i].w + PK_RISE, time);
            }
            for (var j = 0; j < 4; j = j + 1) {
                let aj = fh21(vec2<f32>(f32(j) * 3.1, tq)) * TAU;
                let dj = vec2<f32>(cos(aj), sin(aj));
                let bl = bolt_line(p2, dj * wpx * 0.7, dj * wpx * (2.4 + 1.5 * fh21(vec2<f32>(f32(j), tq + 5.0))), seed + 50.0 + f32(j) * 3.0, tq, wpx * 0.06);
                arcs = arcs + (bl.x + bl.y * 0.3) * step(0.35, fh21(vec2<f32>(f32(j) + 9.0, tq)));
            }
            star = star + (PK_WHITE * 0.5 + PK_HOT) * arcs * saturate(fed / 2.0) * (0.6 + charge + burn) * en;
        }
        add = add + star * occ * k;
    }
    // ...and its burst: a sphere of light thrown out, gone in a second
    if (popped && pop_t < 2.0) {
        let dcn = length(NX - rd * max(tcn, 0.0));
        let Rb = 10.0 + 200.0 * (1.0 - exp(-pop_t * 3.0));
        let ball = exp(-dcn / (Rb * 0.3)) * 1.2 + exp(-pow(dcn / Rb, 2.0)) * 0.3;
        add = add + (PK_WHITE * 0.25 * exp(-pop_t * 8.0) + PK_HOT) * ball * exp(-pop_t * 2.6) * select(0.0, 1.0, tcn > 0.0) * pk_occ(tcn, scene_len, sky, cloud) * k;
    }

    // ---- the ring of light thrown out across the sky as they fuse ------------------------------------------------
    if (merged && merge_t < 6.0) {
        let tp = NX.y / select(rd.y, 1.0e-5, abs(rd.y) < 1.0e-5);
        if (tp > 0.0) {
            let pp = rd * tp;
            let rr = length(pp.xz - NX.xz);
            let R = 1400.0 * (1.0 - exp(-merge_t * 0.9));
            let th = 6.0 + 50.0 * merge_t;
            let ring = (exp(-pow((rr - R) / th, 2.0)) + exp(-pow((rr - R * 0.82) / (th * 0.5), 2.0)) * 0.4) * exp(-merge_t * 0.9)
                * (0.7 + 0.6 * gnoise2(vec2<f32>(atan2(pp.z - NX.z, pp.x - NX.x) * 12.0, merge_t)));
            let wfar = max(1.0, tp * 0.002);
            add = add + (PK_HOT + PK_WHITE * 0.15) * ring * min(1.0, 30.0 / wfar) * pk_occ(tp, scene_len, sky, cloud) * k;
        }
    }

    // the guide: a pencil-thin thread from the nexus to the target in the moments before it fires
    if (time > 2.6 && time < PK_DROP) {
        let q = ray_seg(rdb, NX, crel);
        let w = max(0.15, q.y * 0.001);
        add = add + PK_HOT * exp(-pow(q.x / w, 2.0)) * (0.2 / w) * smoothstep(2.6, 3.4, time) * (0.7 + 0.3 * sin(time * 60.0))
            * pk_occ(q.y, scene_len, sky, cloud) * k;
    }

    // ---- the beam: down from the nexus onto the target, white-hot inside its sheaths ---------------------------
    if (burn > 0.001) {
        let G = crel - vec3<f32>(0.0, 14.0, 0.0);
        let u_head = saturate((time - PK_DROP) / (PK_HIT - PK_DROP));
        let u_top = saturate((time - PK_CUT - PK_DRAIN * 0.5) / 0.4);
        let A = NX + (G - NX) * u_top;
        let B = NX + (G - NX) * u_head;
        let q = ray_seg(rdb, A, B);
        let lenb = length(G - NX);
        let qz = mix(u_top, u_head, q.z);
        let along = qz * lenb;
        let hgt = NX.y + (G.y - NX.y) * qz - crel.y;
        var rc = (11.0 + 1.2 * sin(time * 23.0) + 0.9 * sin(time * 37.0 + 1.0)) * (1.0 + 0.6 * exp(-max(hit_t, 0.0) * 2.0));
        rc = rc * (1.0 + 0.5 * exp(-max(hgt, 0.0) / 12.0)) * k;
        let w = max(rc, q.y * 0.0013);
        let e = rc / w;
        let dd = q.x;
        if (dd < w * 40.0) {
            let vis = select(1.0, 1.0 - smoothstep(scene_len - 0.8, scene_len + 0.8, q.y), !sky);
            let vis_mix = mix(0.15, 1.0, vis);
            let bdir = (G - NX) / max(lenb, 1.0e-3);
            let e1 = normalize(cross(bdir, vec3<f32>(1.0, 0.0, 0.0)));
            let e2 = cross(bdir, e1);
            let ofs = rdb * q.y - (A + (B - A) * q.z);
            let ang = atan2(dot(ofs, e2), dot(ofs, e1));
            let n1 = gnoise2(vec2<f32>(ang * 1.6, along * 0.04 - time * 18.0));
            let n2 = gnoise2(vec2<f32>(ang * 2.3 + 7.0, along * 0.09 - time * 25.0));
            // surges racing down it, and strands of plasma winding round it
            let pulse = pow(0.5 + 0.5 * sin(along * 0.03 - time * 60.0), 6.0);
            let strand = pow(0.5 + 0.5 * sin(ang * 3.0 + along * 0.02 - time * 22.0), 4.0) * exp(-pow((dd - w * 1.8) / (w * 0.7), 2.0)) * (0.3 + 0.7 * n2);
            let core = exp(-pow(dd / (w * 0.75), 2.0));
            let inner = exp(-pow(dd / (w * 1.3), 2.0)) * (0.6 + 0.8 * n1);
            let outer = exp(-pow(dd / (w * 2.8), 2.0)) * (0.4 + 0.9 * n2);
            let halo = (exp(-dd / (rc * 4.0)) + exp(-dd / (rc * 14.0)) * 0.15) * (1.0 - smoothstep(w * 25.0, w * 40.0, dd));
            var b = (PK_WHITE * core * (1.0 + 0.6 * pulse) + PK_HOT * inner * (0.28 + 0.6 * pulse) + PK_DEEP * outer * 0.4 + PK_HOT * strand * 0.4) * e;
            // the head of it, blazing, on its way down
            b = b + PK_WHITE * exp(-pow((q.z - 1.0) * (u_head - u_top) * lenb / 10.0, 2.0)) * core * 1.5 * (1.0 - step(1.0, u_head));
            add = add + (b * vis + halo * PK_DEEP * 0.12 * e * vis_mix) * burn * k;
        }
        // the fireball where it lands, boiling
        if (landed) {
            // blown out to 90 across as it lands, settling round the foot of the beam
            let Rf = (20.0 + 28.0 * exp(-hit_t * 0.7) * (1.0 - exp(-hit_t * 7.0))) * (0.92 + 0.08 * sin(time * 13.0));
            let cf = crel + vec3<f32>(0.0, Rf * 0.25, 0.0);
            let tcp = dot(cf, rd);
            // (a dome, flattened against the land)
            let dc = length((rd * max(tcp, 0.0) - cf) * vec3<f32>(1.0, 1.7, 1.0));
            if (dc < Rf * 4.0) {
                {
                    let hx = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
                    let hy = cross(hx, rd);
                    let on = rd * tcp - cf;
                    let ang = atan2(dot(on, hy), dot(on, hx));
                    let nz = gfbm2(vec2<f32>(ang * 1.3 + seed, dc / Rf * 2.0 - time * 2.5));
                    let fire = exp(-pow(dc / (Rf * (0.75 + 0.5 * nz)), 2.0));
                    // plasma, white-hot at its heart, the land burning orange under it, a crust of smoke round its edge
                    let heat = fire * (0.4 + 0.6 * exp(-dc / (Rf * 0.3)));
                    let low = exp(-max((rd * max(tcp, 0.0) - crel).y, 0.0) / 8.0);
                    let visf = select(1.0, smoothstep(tcp - Rf * 1.3, tcp - Rf * 0.2, scene_len), !sky);
                    col = mix(col, vec3<f32>(0.04, 0.04, 0.05), smoothstep(0.05, 0.5, fire) * (1.0 - heat) * 0.6 * visf * burn * k);
                    add = add + (PK_WHITE * 0.25 * heat * heat + PK_HOT * 0.45 * heat * (1.0 + 0.6 * nz) + PK_DEEP * fire * 0.3
                        + lava_ramp(0.45 + 0.5 * heat) * fire * low * 1.4) * visf * burn * k;
                    add = add + vec3<f32>(1.2, 1.2, 1.6) * exp(-dc / Rf) * 0.12 * (1.0 - smoothstep(Rf * 2.5, Rf * 4.0, dc)) * burn * visf * k;
                }
            }
        }
    }

    // ---- molten rock thrown out of the crater, and chunks of the land (dark) -------------------------------------
    let sp_q = ray_seg(rd, crel, crel + vec3<f32>(0.0, 60.0, 0.0));
    if (landed && time < PK_CUT + 3.0 && sp_q.x < 140.0) {
        for (var j = 0; j < 28; j = j + 1) {
            // each one thrown again and again, a new way each time
            let fj = f32(j);
            let life = 1.6 + 1.2 * fract(fj * 0.618034);
            let ph = fract(fj * 0.754878) * life;
            let gen = floor((time + ph) / life);
            let tb = gen * life - ph;                               // when this one was thrown
            let a = time - tb;
            if (tb < PK_HIT || tb > PK_CUT) {
                continue;
            }
            let hv = vec3<f32>(pcg3d(vec3<u32>(u32(j), u32(gen), u32(seed)))) * (1.0 / 4294967295.0);
            let az = hv.x * TAU;
            let vh = 12.0 + 30.0 * hv.y;
            let vy = 20.0 + 30.0 * hv.z;
            let s3 = crel + vec3<f32>(cos(az) * 8.0, 2.0, sin(az) * 8.0);
            let pa = s3 + vec3<f32>(cos(az) * vh * a, vy * a - 16.0 * a * a, sin(az) * vh * a);
            let a1 = max(a - 0.07, 0.0);
            let pb = s3 + vec3<f32>(cos(az) * vh * a1, vy * a1 - 16.0 * a1 * a1, sin(az) * vh * a1);
            if (pa.y + cam.y < tgt.y - 10.0) {
                continue;
            }
            let qj = ray_seg(rd, pa, pb);
            let vis = select(1.0, 1.0 - smoothstep(scene_len - 0.4, scene_len + 0.4, qj.y), !sky);
            if (j % 3 == 0) {
                let w = 0.5 + 0.6 * hv.y;
                col = mix(col, vec3<f32>(0.04, 0.035, 0.03), exp(-pow(qj.x / max(w, qj.y * 0.0012), 4.0)) * (w / max(w, qj.y * 0.0012)) * vis);
            } else {
                let w = max(0.35, qj.y * 0.0012);
                add = add + mix(vec3<f32>(4.0, 3.4, 2.6), vec3<f32>(2.6, 0.7, 0.12), saturate(a / life)) * exp(-pow(qj.x / w, 2.0)) * (0.35 / w) * (1.0 - a / life) * vis * k;
            }
        }
    }

    // ---- the lens: bloom round the nexus and the beam's foot, a long streak through the nexus --------------------
    if (pN.z > 0.0 && Rn > 0.01) {
        let dd = (uv - pN.xy) * vec2<f32>(aspect, 1.0);
        let l = lum_n * (0.6 + 0.5 * charge + 0.6 * burn) + select(0.0, exp(-merge_t * 3.0) * 3.0, merged) + select(0.0, exp(-pop_t * 3.0) * 3.0, popped);
        add = add + PK_HOT * l / (1.0 + dot(dd, dd) * 300.0) * 0.35 * k;
        add = add + PK_HOT * exp(-abs(dd.y) * 300.0) * exp(-abs(dd.x) * 1.6) * l * 0.5 * k;
    }
    if (pT.z > 0.0 && burn > 0.001) {
        let dd = (uv - pT.xy) * vec2<f32>(aspect, 1.0);
        add = add + vec3<f32>(1.2, 1.6, 2.6) * burn / (1.0 + dot(dd, dd) * 400.0) * 0.25 * k;
        add = add + PK_HOT * exp(-abs(dd.y) * 260.0) * exp(-abs(dd.x) * 3.0) * burn * 0.35 * k;
    }
    add = add + vec3<f32>(2.2, 2.5, 3.2) * flash * flash * k;

    // ---- combine --------------------------------------------------------------
    var outc = col + add;
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    outc = outc * (1.0 - smoothstep(0.3, 1.0, vg) * (0.2 + 0.3 * dark) * k);
    outc = aces(outc * 0.9);
    let srgb = linear_to_srgb(outc);
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
    return planet_killer(in);
}
