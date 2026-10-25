//! A strike's plan: every command and sound it makes, at the second it makes
//! it. The mod plays the plan out tick by tick (`world.run-commands`, run at
//! operator level and silently, so nothing reaches the chat).
use crate::lasers::Laser;
use std::f64::consts::PI;

/// Strike clock of the impact (the shader's T_FIRE).
pub const FIRE: f32 = 4.0;
/// Mobs and dropped items this close to the impact die (players are spared).
const KILL_RADIUS: i32 = 40;
/// Godly: the six quartz pillars (and the shader's pillars of light) stand on
/// this circle, the first at this angle. Keep in step with strike.wgsl.
const PILLAR_R: f64 = 40.0;
const PILLAR_A0: f64 = PI / 6.0;
/// Black hole: the singularity hangs this high over the impact, and evaporates
/// this long after it. Keep in step with strike.wgsl (HOLE_H, BH_END).
const HOLE_H: f64 = 28.0;
const BH_END: f32 = 10.0;
/// Black hole: the blocks torn out of the ground that the shader flies round the hole. Where and when each one goes
/// comes from these formulas, the same as strike.wgsl's debris_* (keep them in step); `seed` is the shader's seed.
const DEBRIS: usize = 160;
fn debris_angle(i: usize, seed: f32) -> f64 {
    (f64::from(i as u32) * 0.381966 + f64::from(seed) * 0.1137).fract() * 2.0 * PI
}
fn debris_r0(i: usize, seed: f32) -> f64 {
    35.0 + 15.0 * (f64::from(i as u32) * 0.618034 + f64::from(seed) * 0.1234).fract()
}
fn debris_t(i: usize) -> f32 {
    0.4 + 6.0 * i as f32 / DEBRIS as f32 + 0.3 * (i as f32 * 0.754_877_7).fract()
}
fn debris_big(i: usize, seed: f32) -> bool {
    (f64::from(i as u32) * 0.276_393_2 + f64::from(seed) * 0.0517).fract() > 0.78
}

pub enum Act {
    Cmd(String),
    /// A sound that follows the player.
    /// A sound following the player (`at` none), or at a point, heard only nearby.
    Sound { event: String, at: Option<[f64; 3]>, volume: f32, pitch: f32 },
    /// A jolt of the real camera (`render.shake`): `strength` 0 to 1, fading out over `seconds`.
    Shake { strength: f32, seconds: f32 },
    /// Part of the plan worked out only when it is due: it returns more of the plan. A big strike's whole plan is too
    /// much work for the one tick it fires in (a mod's tick has a fuel limit).
    Later(Box<dyn FnOnce() -> Vec<(f32, Act)>>),
}

/// The blocks a command changes or visits, roughly, when it changes the world (`fill`, `setblock`, `summon`, through
/// any `execute ... run`); `None` for one that doesn't (sounds, particles, titles, kills), which runs on time.
pub fn block_cost(cmd: &str) -> Option<u64> {
    let run = cmd.rsplit(" run ").next().unwrap_or(cmd);
    let mut words = run.split_whitespace();
    match words.next()? {
        "fill" => {
            // x1 y1 z1 x2 y2 z2, absolute or ~-relative (both corners the same way)
            let n: Vec<i64> = words
                .take(6)
                .map(|w| w.trim_start_matches('~').parse::<i64>().unwrap_or(0))
                .collect();
            if n.len() < 6 {
                return Some(1);
            }
            Some((0..3).map(|i| (n[i + 3] - n[i]).unsigned_abs() + 1).product())
        }
        "setblock" => Some(1),
        "summon" => Some(20),
        _ => None,
    }
}

/// What was hit: the block, and the point on its face.
pub struct Target {
    pub block: [i32; 3],
    pub point: [f64; 3],
}

/// xorshift64*: the same rubble and craters for the same spot.
pub struct Rng(u64);
impl Rng {
    pub fn new(seed: u64) -> Self {
        Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1)
    }
    pub fn next(&mut self) -> f64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        (x.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 11) as f64 / (1u64 << 53) as f64
    }
    pub fn uniform(&mut self, a: f64, b: f64) -> f64 {
        a + (b - a) * self.next()
    }
    pub fn int(&mut self, a: i32, b: i32) -> i32 {
        a + (self.next() * f64::from(b - a + 1)).floor() as i32
    }
    pub fn pick<'a, T>(&mut self, items: &'a [T]) -> &'a T {
        &items[((self.next() * items.len() as f64) as usize).min(items.len() - 1)]
    }
    fn weighted<'a>(&mut self, items: &'a [(&'static str, f32)]) -> &'a str {
        let total: f32 = items.iter().map(|i| i.1).sum();
        let mut r = self.next() as f32 * total;
        for (name, w) in items {
            if r < *w {
                return name;
            }
            r -= w;
        }
        items[items.len() - 1].0
    }
}

/// Seconds a sound takes to reach the player at `me` from `p` (about 343 blocks a second), and how far it is.
fn sound_from(p: [f64; 3], me: [f64; 3]) -> (f32, f64) {
    let d = ((p[0] - me[0]).powi(2) + (p[1] - me[1]).powi(2) + (p[2] - me[2]).powi(2)).sqrt();
    ((d / 343.0) as f32, d)
}
/// How much of a blast's jolt reaches the player `d` blocks off: all of it close by, a third at 300 blocks. (The game
/// squares a jolt's strength, so a third of it is a faint tremor.)
fn falloff(d: f64) -> f32 {
    (1.4 / (1.0 + d / 100.0)).min(1.0) as f32
}

/// `then`, run on the ground at column (x, z): `~ ~ ~` is the first air block above the surface.
fn surf(x: i32, z: i32, then: &str) -> String {
    format!("execute positioned {x} 0 {z} positioned over motion_blocking_no_leaves run {then}")
}

struct Plan {
    laser: &'static Laser,
    ev: Vec<(f32, Act)>,
    rng: Rng,
    bx: i32,
    by: i32,
    bz: i32,
}

impl Plan {
    /// Work out part of the plan only when it is due (at `at`, a little before its first event).
    fn later(&mut self, at: f32, f: impl FnOnce(&mut Plan) + 'static) {
        let (laser, bx, by, bz) = (self.laser, self.bx, self.by, self.bz);
        let seed = (self.rng.next() * 9.0e15) as u64;
        let job = move || {
            let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed), bx, by, bz };
            f(&mut p);
            p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
            p.ev
        };
        self.ev.push((at, Act::Later(Box::new(job))));
    }
    fn at(&mut self, t: f32, cmd: impl Into<String>) {
        self.ev.push((t, Act::Cmd(cmd.into())));
    }
    /// A vanilla sound, `vol` out of 10.
    fn sound(&mut self, t: f32, name: &str, vol: f32, pitch: f64) {
        self.ev.push((
            t,
            Act::Sound {
                event: format!("minecraft:{name}"),
                at: None,
                volume: (vol / 10.0).min(1.0),
                pitch: pitch as f32,
            },
        ));
    }
    /// A vanilla sound out of the impact, `vol` out of 10: heard there (out to about 64 blocks at 10) and fading with
    /// distance, not in the player's ears wherever they are, like the ground breaking.
    fn ground_sound(&mut self, t: f32, name: &str, vol: f32, pitch: f64) {
        let at = [f64::from(self.bx) + 0.5, f64::from(self.by) + 0.5, f64::from(self.bz) + 0.5];
        self.ev.push((
            t,
            Act::Sound {
                event: format!("minecraft:{name}"),
                at: Some(at),
                volume: (vol / 10.0).min(1.0) * 4.0,
                pitch: pitch as f32,
            },
        ));
    }
    /// A jolt of the camera, timed to when the blast reaches the player (see `late` and `falloff`).
    fn shake(&mut self, t: f32, strength: f32, seconds: f32) {
        self.ev.push((t, Act::Shake { strength: strength.clamp(0.0, 1.0), seconds: seconds.clamp(0.05, 30.0) }));
    }
    /// One of the laser's own sounds.
    fn csound(&mut self, t: f32, role: &str, vol: f32, pitch: f32) {
        let event = self.laser.sound(role);
        self.ev.push((t, Act::Sound { event, at: None, volume: (vol / 10.0).min(1.0), pitch }));
    }
    /// A rough circle as a few rectangles (x0, z0, x1, z1): consecutive rows share one /fill.
    fn rects(&mut self, r: i32, rough: f64) -> Vec<[i32; 4]> {
        let rows: Vec<i32> = (-r..=r).collect();
        let n = rows.len();
        let groups = n.min(3 + (f64::from(r) * 0.6).round() as usize);
        let mut out = Vec::new();
        for g in 0..groups {
            let chunk = &rows[g * n / groups..(g + 1) * n / groups];
            if chunk.is_empty() {
                continue;
            }
            let hw: f64 = chunk
                .iter()
                .map(|dz| f64::from(r * r - dz * dz).max(0.0).sqrt())
                .sum::<f64>()
                / chunk.len() as f64;
            let hw = (hw * (1.0 + self.rng.uniform(-rough, rough)) + 0.5) as i32;
            out.push([self.bx - hw, self.bz + chunk[0], self.bx + hw, self.bz + chunk[chunk.len() - 1]]);
        }
        out
    }
    fn fills(rs: &[[i32; 4]], y_lo: i32, y_hi: i32, block: &str, replace: Option<&str>, grow: i32) -> Vec<String> {
        let suffix = replace.map(|r| format!(" replace {r}")).unwrap_or_default();
        rs.iter()
            .map(|[x0, z0, x1, z1]| {
                format!(
                    "fill {} {y_lo} {} {} {y_hi} {} {block}{suffix}",
                    x0 - grow,
                    z0 - grow,
                    x1 + grow,
                    z1 + grow
                )
            })
            .collect()
    }
    /// Like `fills`, but only the ends of each row (and the first and last rows whole): the wall of a dug disc,
    /// for lining it without visiting the inside, which is about to be air anyway.
    fn edge_fills(rs: &[[i32; 4]], y_lo: i32, y_hi: i32, block: &str, replace: &str, grow: i32) -> Vec<String> {
        let mut out = Vec::new();
        for (i, &[x0, z0, x1, z1]) in rs.iter().enumerate() {
            let (za, zb) = (z0 - if i == 0 { grow } else { 0 }, z1 + if i + 1 == rs.len() { grow } else { 0 });
            if i == 0 || i + 1 == rs.len() || x1 - x0 <= 4 * grow + 2 {
                out.push(format!("fill {} {y_lo} {za} {} {y_hi} {zb} {block} replace {replace}", x0 - grow, x1 + grow));
            } else {
                out.push(format!("fill {} {y_lo} {za} {} {y_hi} {zb} {block} replace {replace}", x0 - grow, x0 + grow));
                out.push(format!("fill {} {y_lo} {za} {} {y_hi} {zb} {block} replace {replace}", x1 - grow, x1 + grow));
            }
        }
        out
    }
    fn disc(&mut self, r: i32, y_lo: i32, y_hi: i32, block: &str, rough: f64, replace: Option<&str>) -> Vec<String> {
        let rs = self.rects(r, rough);
        Self::fills(&rs, y_lo, y_hi, block, replace, 0)
    }
    /// Patches of the laser's other lining blocks over the fused wall at radius r.
    fn mottle(&mut self, r: i32, y_lo: i32, y_hi: i32, t: f32, n: usize) {
        let prim = self.laser.lining[0].0;
        let others = &self.laser.lining[1..];
        for _ in 0..n {
            let a = self.rng.uniform(0.0, 2.0 * PI);
            let x = self.bx + (a.cos() * f64::from(r + 1)).round() as i32;
            let z = self.bz + (a.sin() * f64::from(r + 1)).round() as i32;
            let s = *self.rng.pick(&[1, 1, 2]);
            let blk = self.rng.weighted(others).to_string();
            self.at(t + 0.05, format!("fill {} {} {} {} {y_hi} {} {blk} replace {prim}", x - s, y_lo - 1, z - s, x + s, z + s));
        }
    }
    /// Fuse the ground round a disc into the laser's lining (walls and the ledge under them), then dig the disc out.
    fn dig(&mut self, r: i32, y_lo: i32, y_hi: i32, t: f32, rough: f64, grow: i32) {
        const NATURAL: [&str; 13] = [
            "#minecraft:base_stone_overworld",
            "#minecraft:dirt",
            "#minecraft:sand",
            "minecraft:gravel",
            "minecraft:clay",
            "#minecraft:terracotta",
            "minecraft:blackstone",
            "minecraft:smooth_basalt",
            "minecraft:smooth_quartz",
            "minecraft:calcite",
            "#minecraft:coal_ores",
            "#minecraft:iron_ores",
            "#minecraft:copper_ores",
        ];
        let prim = self.laser.lining[0].0;
        let rs = self.rects(r, rough);
        for tag in NATURAL {
            for c in Self::fills(&rs, y_lo - 1, y_hi, prim, Some(tag), grow) {
                self.at(t - 0.05, c);
            }
        }
        for c in Self::fills(&rs, y_lo, y_hi, "minecraft:air", None, 0) {
            self.at(t, c);
        }
    }
}

/// Everything a strike of `laser` at `target` does. `dimension` picks the
/// bedrock floor; `shader_seed` is the shader's, for what the two must agree on;
/// `me` is where the player stands (the meteor storm's sounds reach them late);
/// `approach` is the way the mothership comes in (APPROACHES).
pub fn plan(laser: &'static Laser, target: &Target, terrain: bool, dimension: &str, shader_seed: f32, me: [f64; 3], approach: usize) -> Vec<(f32, Act)> {
    if laser.key == "meteor" {
        return meteor_plan(laser, target, terrain, dimension, shader_seed, me);
    }
    if laser.key == "mothership" {
        return mothership_plan(laser, target, terrain, dimension, wing_angle(target.point, me), me, approach);
    }
    let [bx, by, bz] = target.block;
    let r2 = |v: f64| (v * 100.0).round() / 100.0;
    let (tx, ty, tz) = (r2(target.point[0]), r2(target.point[1]), r2(target.point[2]));
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let plasma = laser.key == "plasma";
    let godly = laser.key == "godly";
    let blackhole = laser.key == "blackhole";
    let t = FIRE;

    // charge, lock-on, impact
    p.csound(0.0, "charge", 10.0, 1.0);
    p.csound(3.4, "lockon", 8.0, 1.0);
    p.at(3.5, format!(r#"title @s actionbar {{"text":"ORBITAL LASER: LOCKED  [{}]","color":"{}","bold":true}}"#, laser.title, laser.color));
    p.csound(t, "fire", 10.0, 1.0);
    // the camera: a hard jolt when the blast reaches the player, then the beam (or the jet) shaking the ground while
    // it burns
    let (lt, dist) = sound_from(target.point, me);
    let fo = falloff(dist);
    p.shake(t + lt, [0.95, 0.8, 0.9][usize::from(godly) + 2 * usize::from(blackhole)] * fo, 3.0);
    if plasma {
        for i in 0..9 {
            p.shake(t + lt + 0.6 + i as f32, 0.22 * fo, 1.3);
        }
    }
    if godly {
        for i in 0..6 {
            p.shake(t + lt + 0.8 + i as f32 * 1.4, 0.12 * fo, 1.6);
        }
    }
    // the impact: stacked explosions and thunder under the laser's own blast, then rock raining back down
    for (dt, pitch) in [(0.0, 0.42), (0.06, 0.55), (0.2, 0.7), (0.5, 0.5)] {
        p.sound(t + dt, "entity.generic.explode", 10.0, pitch);
    }
    p.sound(t + 0.05, "entity.lightning_bolt.thunder", 9.0, 0.55);
    p.sound(t + 0.9, "entity.lightning_bolt.thunder", 6.0, 0.75);
    p.at(t, format!("particle minecraft:explosion_emitter {tx} {} {tz} 0 0 0 0 1 force", ty + 1.0));
    p.at(t + 0.1, r#"title @s actionbar {"text":"DIRECT HIT","color":"white","bold":true}"#);
    // while it burns
    for i in 0..3 {
        p.csound(t + 0.2 + i as f32 * 3.4, "beam", 9.0, 1.0);
    }
    p.csound(t + 0.6, "rumble", 9.0, 0.95);
    p.csound(t + 4.2, "rumble", 8.0, 0.85);
    let accents: &[f32] = if plasma { &[1.1, 2.4, 3.9, 5.3, 6.8] } else { &[1.4, 3.9, 6.6] };
    for (i, tc) in accents.iter().enumerate() {
        p.csound(t + tc, "accent", 7.0 + (i % 2) as f32, 0.85 + 0.12 * ((i * 3) % 4) as f32);
    }
    if terrain {
        for i in 0..3 {
            p.csound(t + 1.2 + i as f32 * 2.6, "collapse", 8.0, 0.92 + 0.08 * i as f32);
        }
    }
    p.csound(t + 9.2, "shutdown", 9.0, 1.0);

    if terrain {
        // everything round the impact shattering at once, then debris raining back down
        for k in 0..14 {
            let name = *p.rng.pick(&["block.stone.break", "block.gravel.break", "block.grass.break", "block.wood.break"]);
            let pitch = p.rng.uniform(0.5, 0.9);
            p.ground_sound(t + 0.05 + k as f32 * 0.07, name, 10.0, pitch);
        }
        for _ in 0..10 {
            let dt = p.rng.uniform(0.0, 2.5) as f32;
            let name = *p.rng.pick(&["block.stone.break", "block.gravel.break"]);
            let pitch = p.rng.uniform(0.6, 1.1);
            p.ground_sound(t + 1.0 + dt, name, 6.0, pitch);
        }
    }

    // ---- particles in the world ----
    let shard = match laser.key {
        "plasma" => "minecraft:blackstone",
        "godly" => "minecraft:calcite",
        _ => "minecraft:crying_obsidian",
    };
    p.at(t + 0.05, format!(r#"particle minecraft:block{{block_state:"{shard}"}} {tx} {} {tz} 3 1 3 2.2 700 force"#, ty + 1.0));
    p.at(t + 0.1, format!(r#"particle minecraft:block{{block_state:"minecraft:stone"}} {tx} {} {tz} 5 1 5 1.6 500 force"#, ty + 1.0));
    if plasma {
        for i in 0..18 {
            p.at(t + 0.3 + i as f32 * 0.5, format!("particle minecraft:electric_spark {tx} {} {tz} 5 6 5 0.8 70 force", ty + 3.0));
        }
    }
    if godly {
        for i in 0..8 {
            let s = 6.0 - f64::from(i) * 0.6;
            p.at(0.3 + i as f32 * 0.45, format!("particle minecraft:end_rod {tx} {} {tz} {s:.1} 0.1 {s:.1} 0.01 14 force", ty + 0.5));
        }
        for i in 0..22 {
            p.at(t + 0.4 + i as f32 * 0.6, format!("particle minecraft:end_rod {tx} {} {tz} 9 2 9 0.06 45 force", ty + 2.0));
            if i % 2 == 0 {
                p.at(t + 0.6 + i as f32 * 0.6, format!("particle minecraft:white_ash {tx} {} {tz} 24 18 24 0 260 force", ty + 30.0));
            }
        }
    }

    if blackhole {
        let hy = ty + HOLE_H;
        // matter spiralling in while it charges, faster and from further out as the singularity grows
        p.sound(0.2, "block.portal.trigger", 8.0, 0.5);
        for i in 0..12 {
            let s = 2.0 + f64::from(i) * 0.9;
            p.at(0.4 + i as f32 * 0.3, format!("particle minecraft:portal {tx} {hy} {tz} 0 0 0 {s:.1} {} force", 40 + i * 12));
        }
        // the air pulled in towards it as it forms, the jet shaking the ground, and its evaporation's blast
        p.shake(t - 1.0, 0.3 * fo, 1.2);
        for i in 0..9 {
            p.shake(t + lt + 0.5 + i as f32, 0.18 * fo, 1.2);
        }
        let (lh, dh) = sound_from([tx, hy, tz], me);
        p.shake(t + BH_END + lh, 0.95 * falloff(dh), 3.0);
        // it opens with a crack of the air, and the end portal's toll
        p.sound(t, "entity.warden.sonic_boom", 10.0, 0.5);
        p.sound(t + 0.1, "block.end_portal.spawn", 10.0, 0.6);
        p.at(t, format!("particle minecraft:sonic_boom {tx} {hy} {tz} 0 0 0 0 1 force"));
        p.at(t + 0.05, format!("particle minecraft:sonic_boom {tx} {} {tz} 0 0 0 0 1 force", ty + 2.0));
        for i in 0..24 {
            // the land streams up into it while the jet pours out underneath
            let tk = t + 0.3 + i as f32 * 0.4;
            p.at(tk, format!("particle minecraft:portal {tx} {hy} {tz} 0 0 0 16 260 force"));
            p.at(tk, format!("particle minecraft:portal {tx} {} {tz} 0 0 0 7 120 force", hy - 6.0));
            if i % 2 == 0 {
                p.at(tk, format!("particle minecraft:reverse_portal {tx} {} {tz} 0.6 12 0.6 0.04 140 force", (ty + hy) / 2.0));
                p.at(tk, format!("particle minecraft:squid_ink {tx} {} {tz} 14 1 14 0.05 60 force", ty + 1.5));
            }
        }
        // it evaporates: a burst of light from where it was, and a ring of sound running out
        let te = t + BH_END;
        p.at(te, format!("particle minecraft:flash {tx} {hy} {tz} 0 0 0 0 1 force"));
        p.at(te, format!("particle minecraft:explosion_emitter {tx} {hy} {tz} 2 2 2 0 3 force"));
        p.at(te, format!("particle minecraft:end_rod {tx} {hy} {tz} 0 0 0 1.4 500 force"));
        p.at(te + 0.05, format!("particle minecraft:reverse_portal {tx} {hy} {tz} 1 1 1 2.5 700 force"));
        p.sound(te, "entity.generic.explode", 10.0, 0.45);
        p.sound(te + 0.02, "entity.lightning_bolt.thunder", 10.0, 0.5);
        p.sound(te + 0.1, "block.beacon.deactivate", 10.0, 0.5);
    }

    if terrain {
        let r_mouth = laser.shaft_r;
        let floor_y = bedrock_top(dimension);
        // 1. the blast: everything standing above the ground in a wide disc is vaporised (the black hole clears
        //    further, so the ground it tears its debris from is level with the target)
        for c in p.disc(if blackhole { 52 } else { 44 }, by + 1, by + 60, "minecraft:air", 0.12, None) {
            p.at(t + 0.15, c);
        }
        // 2. scorched earth: what the ground round the crater turns into (the black hole drains it once it has
        //    torn its debris up)
        let t_scorch = if blackhole { t + 7.6 } else { t + 0.4 };
        for &(rad, block, rough, repl) in laser.scorch {
            for c in p.disc(rad, by - 3, by + 1, block, f64::from(rough), Some(repl)) {
                let dt = p.rng.next() as f32 * 2.2;
                p.at(t_scorch + dt, c);
            }
        }
        // 3. the bowl: a rough paraboloid crater, outer layers first, its walls fused as it goes
        let (bowl_r, bowl_d) = (laser.bowl_r, laser.bowl_d);
        for d in (0..bowl_d).step_by(2) {
            let r = ((f64::from(bowl_r) * (1.0 - f64::from(d) / (f64::from(bowl_d) + 0.5)).sqrt()) as i32).max(3);
            let tl = t + 0.5 + d as f32 * 0.28;
            p.dig(r, by - d - 1, by - d, tl, f64::from(laser.bowl_rough), 2);
            p.mottle(r, by - d - 1, by - d, tl, 16);
            for _ in 0..3 {
                let dt = p.rng.uniform(0.0, 0.25) as f32;
                let name = *p.rng.pick(&["block.stone.break", "block.gravel.break", "block.grass.break"]);
                let pitch = p.rng.uniform(0.55, 0.9);
                p.ground_sound(tl + dt, name, 9.0, pitch);
            }
        }
        let (fb, fr, fq) = laser.bowl_floor;
        for c in p.disc(bowl_r - 4, by - bowl_d, by - bowl_d + 1, fb, f64::from(fr), Some(fq)) {
            p.at(t + 4.2, c);
        }
        // 4. the shaft: drills on down through the bowl, funnelling in and then running straight to bedrock
        let steps = ((by - bowl_d - floor_y) / 4 + 1).max(1);
        for i in 0..steps {
            let y_hi = by - bowl_d - 4 * i;
            if y_hi < floor_y {
                break;
            }
            let r = ((f64::from(r_mouth) - f64::from(i) * f64::from(r_mouth - laser.shaft_min) / 14.0).round() as i32)
                .max(laser.shaft_min);
            let ts = t + 1.2 + i as f32 * (8.2 / steps as f32);
            p.dig(r, (y_hi - 3).max(floor_y), y_hi, ts, f64::from(laser.shaft_rough), 1);
            p.mottle(r, (y_hi - 3).max(floor_y), y_hi, ts, 3);
            let pitch = p.rng.uniform(0.5, 0.8);
            p.ground_sound(ts, if y_hi < 0 { "block.deepslate.break" } else { "block.stone.break" }, 8.0, pitch);
            if i % 2 == 0 {
                let pitch = p.rng.uniform(0.6, 0.9);
                p.ground_sound(ts + 0.1, "block.gravel.break", 6.0, pitch);
            }
            let fmt = |s: &str, y: i32, rr: f64| {
                s.replace("{x}", &format!("{}", f64::from(bx) + 0.5))
                    .replace("{y}", &y.to_string())
                    .replace("{z}", &format!("{}", f64::from(bz) + 0.5))
                    .replace("{r}", &format!("{rr:.1}"))
            };
            p.at(ts, fmt(laser.particle_a, by + 1, f64::from(r) * 0.6));
            p.at(ts, fmt(laser.particle_b, y_hi, f64::from(r) * 0.4));
        }
        // 5. the bottom of the shaft
        let tb = t + 9.6;
        for (k, &(rad, lo, hi, block)) in laser.bottom.iter().enumerate() {
            for c in p.disc(rad, floor_y + lo, floor_y + hi, block, 0.0, None) {
                p.at(tb + 0.1 * k as f32, c);
            }
        }
        if plasma {
            plasma_aftermath(&mut p);
        }
        if godly {
            godly_aftermath(&mut p);
        }
        if blackhole {
            blackhole_aftermath(&mut p, target.point, shader_seed);
        }
    }
    if godly {
        p.at(t + 1.0, format!("execute positioned {tx} {ty} {tz} run effect give @a[distance=..60] minecraft:regeneration 15 1 true"));
        p.at(t + 1.0, format!("execute positioned {tx} {ty} {tz} run effect give @a[distance=..60] minecraft:absorption 30 1 true"));
    }
    // wipe out every living thing near the impact (players are spared); a few passes catch anything wandering in
    for tk in [0.15, 0.9, 2.5, 5.0, 8.0] {
        p.at(t + tk, format!("execute positioned {tx} {ty} {tz} run kill @e[type=!minecraft:player,distance=..{KILL_RADIUS}]"));
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// The top of the bedrock floor in a dimension.
fn bedrock_top(dimension: &str) -> i32 {
    match dimension {
        "minecraft:overworld" => -59,
        "minecraft:the_nether" => 5,
        _ => 1,
    }
}

/// Molten pools on the crater floor that crust over to obsidian, fires round the rim, and rubble landing far and wide.
fn plasma_aftermath(p: &mut Plan) {
    let t = FIRE;
    let (bx, by, bz) = (p.bx, p.by, p.bz);
    let (bowl_r, bowl_d, mouth) = (p.laser.bowl_r, p.laser.bowl_d, p.laser.shaft_r);
    for k in 0..8 {
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = p.rng.uniform(f64::from(mouth + 3), f64::from(bowl_r - 6));
        let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
        for blk in ["minecraft:obsidian", "minecraft:magma_block", "minecraft:black_stained_glass"] {
            p.at(t + 4.6 + k as f32 * 0.2, surf(x, z, &format!("fill ~-1 ~-1 ~-1 ~1 ~-1 ~1 minecraft:lava replace {blk}")));
        }
    }
    p.at(t + 5.0, surf(bx, bz, "playsound minecraft:block.lava.ambient block @a ~ ~ ~ 3 0.6"));
    let span = bowl_r + 3;
    let mut y0 = by - bowl_d - 2;
    while y0 < by + 2 {
        // the pools crust over (a fill is capped at 32768 blocks)
        p.at(t + 19.0, format!("fill {} {y0} {} {} {} {} minecraft:obsidian replace minecraft:lava", bx - span, bz - span, bx + span, (y0 + 4).min(by + 1), bz + span));
        y0 += 5;
    }
    p.at(t + 19.0, surf(bx, bz, "playsound minecraft:block.fire.extinguish block @a ~ ~ ~ 3 0.7"));
    for _ in 0..36 {
        // fires catch on the scorched rim, well clear of anything that burns
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = p.rng.uniform(f64::from(bowl_r + 1), 39.0);
        let dt = p.rng.uniform(0.0, 3.0) as f32;
        p.at(t + 2.0 + dt, surf(bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32, "setblock ~ ~ ~ minecraft:fire keep"));
    }
    const RUBBLE: [&str; 8] = [
        "minecraft:cobblestone",
        "minecraft:cobbled_deepslate",
        "minecraft:blackstone",
        "minecraft:gravel",
        "minecraft:magma_block",
        "minecraft:obsidian",
        "minecraft:basalt",
        "minecraft:cobblestone",
    ];
    for k in 0..80 {
        // rock thrown out by the blast comes down across the land around
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = 38.0 + 60.0 * p.rng.next().powf(1.6);
        let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
        let tl = t + 1.0 + (rr / 95.0 * 4.5) as f32 + p.rng.uniform(0.0, 1.0) as f32;
        let blk = *p.rng.pick(&RUBBLE);
        p.at(tl, surf(x, z, &format!("setblock ~ ~ ~ {blk} keep")));
        if p.rng.next() < 0.45 {
            let (dx, dz) = (*p.rng.pick(&[-1, 0, 1]), *p.rng.pick(&[-1, 0, 1]));
            let blk2 = *p.rng.pick(&RUBBLE);
            p.at(tl + 0.05, surf(x + dx, z + dz, &format!("setblock ~ ~ ~ {blk2} keep")));
        }
        p.at(tl, surf(x, z, &format!(r#"particle minecraft:block{{block_state:"{blk}"}} ~ ~0.5 ~ 0.5 0.4 0.5 0.2 18 force"#)));
        if k % 3 == 0 {
            let pitch = p.rng.uniform(0.5, 0.8);
            p.at(tl, surf(x, z, &format!("playsound minecraft:block.basalt.break block @a ~ ~ ~ 2.5 {pitch:.2}")));
        }
    }
}

/// A golden sigil etched into the ground, six quartz pillars where the light came down, a wave of flowers blooming
/// outwards, and chunks of the ground left hanging in the air above the crater.
fn godly_aftermath(p: &mut Plan) {
    let t = FIRE;
    let (bx, by, bz) = (p.bx, p.by, p.bz);
    let bowl_r = p.laser.bowl_r;
    let (r1, r2) = (f64::from(bowl_r + 3), PILLAR_R);
    let gold = "setblock ~ ~-1 ~ minecraft:gold_block";
    let verts: Vec<(f64, f64)> = (0..6)
        .map(|k| {
            let a = PILLAR_A0 + f64::from(k) * PI / 3.0;
            (f64::from(bx) + 0.5 + a.cos() * r2, f64::from(bz) + 0.5 + a.sin() * r2)
        })
        .collect();
    // the pillars' own columns are left alone
    let mut done: std::collections::HashSet<(i32, i32)> = verts.iter().map(|(x, z)| (x.floor() as i32, z.floor() as i32)).collect();
    let mut etch = |p: &mut Plan, x: i32, z: i32, tt: f32| {
        if done.insert((x, z)) {
            p.at(tt, surf(x, z, gold));
        }
    };
    for (rad, t0) in [(r1, 1.6f32), (r2, 2.4)] {
        // two rings, burned in as a sweep round the crater
        let n = (2.0 * PI * rad * 1.3) as usize;
        for i in 0..n {
            let a = i as f64 / n as f64 * 2.0 * PI;
            etch(p, bx + (a.cos() * rad).round() as i32, bz + (a.sin() * rad).round() as i32, t + t0 + 2.4 * i as f32 / n as f32);
        }
    }
    for k in 0..6 {
        // a hexagram: two triangles joining alternate pillars
        let ((x0, z0), (x1, z1)) = (verts[k], verts[(k + 2) % 6]);
        let n = (((x1 - x0).powi(2) + (z1 - z0).powi(2)).sqrt() * 1.2) as usize;
        for i in 0..=n {
            let u = i as f64 / n as f64;
            etch(p, (x0 + (x1 - x0) * u).floor() as i32, (z0 + (z1 - z0) * u).floor() as i32, t + 4.6 + 2.6 * u as f32);
        }
    }
    for (k, (x, z)) in verts.iter().enumerate() {
        // the pillars stand where the shader's pillars of light come down
        let (x, z) = (x.floor() as i32, z.floor() as i32);
        let tl = t + 0.45 + 0.25 * k as f32;
        p.at(tl, surf(x, z, "fill ~ ~ ~ ~ ~9 ~ minecraft:quartz_pillar"));
        p.at(tl + 0.1, surf(x, z, "setblock ~ ~ ~ minecraft:sea_lantern"));
        p.at(tl + 0.15, surf(x, z, "setblock ~ ~ ~ minecraft:end_rod"));
        p.at(tl, surf(x, z, "playsound minecraft:block.amethyst_block.resonate block @a ~ ~ ~ 3 0.6"));
    }
    const FLOWERS: [&str; 7] = [
        "minecraft:oxeye_daisy",
        "minecraft:lily_of_the_valley",
        "minecraft:azure_bluet",
        "minecraft:white_tulip",
        "minecraft:dandelion",
        "minecraft:oxeye_daisy",
        "minecraft:short_grass",
    ];
    for k in 0..320 {
        // a wave of flowers running out across the grass
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = 45.0 + 55.0 * p.rng.next().sqrt();
        let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
        let tl = t + 2.5 + ((rr - 45.0) / 55.0 * 8.0) as f32 + p.rng.uniform(0.0, 0.4) as f32;
        let flower = *p.rng.pick(&FLOWERS);
        p.at(tl, surf(x, z, &format!("execute if block ~ ~-1 ~ minecraft:grass_block run setblock ~ ~ ~ {flower} keep")));
        if k % 5 == 0 {
            p.at(tl, surf(x, z, "particle minecraft:wax_on ~ ~0.6 ~ 0.4 0.3 0.4 0 4 force"));
        }
    }
    for k in 0..6 {
        // rock torn up by the light, left hanging above the crater
        let a = f64::from(k) * 2.0 * PI / 6.0 + p.rng.uniform(-0.4, 0.4);
        let rr = p.rng.uniform(11.0, f64::from(bowl_r - 2));
        let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
        let y = by + p.rng.int(15, 30);
        let s = *p.rng.pick(&[2, 2, 3]);
        let tl = t + 5.5 + k as f32 * 0.45;
        p.at(tl, format!("fill {} {y} {} {} {y} {} minecraft:grass_block", x - s, z - s, x + s, z + s));
        for (cx, cz) in [(x - s, z - s), (x - s, z + s), (x + s, z - s), (x + s, z + s)] {
            p.at(tl, format!("setblock {cx} {y} {cz} minecraft:air"));
        }
        p.at(tl, format!("fill {} {} {} {} {} {} minecraft:dirt", x - s + 1, y - 1, z - s + 1, x + s - 1, y - 1, z + s - 1));
        let s2 = (s - 2).max(0);
        p.at(tl, format!("fill {} {} {} {} {} {} minecraft:calcite", x - s2, y - 2, z - s2, x + s2, y - 2, z + s2));
        p.at(tl, format!("setblock {x} {} {z} minecraft:gold_block", y - 3));
        let fx = x + *p.rng.pick(&[-1, 1]);
        let flower = *p.rng.pick(&FLOWERS);
        p.at(tl, format!("setblock {fx} {} {z} {flower}", y + 1));
        p.at(tl, format!("particle minecraft:end_rod {x} {y} {z} {s} 1 {s} 0.08 40 force"));
        p.at(tl, format!("playsound minecraft:block.amethyst_block.chime block @a {x} {y} {z} 3 0.7"));
    }
}

/// The blocks torn out of the ground for the shader's debris, real ones spat out of the disk to land far away, the land
/// dragged into spiral arms round the crater, streams of rock pulled up towards the singularity, and what it had not yet
/// swallowed when it evaporated left hanging in a ring where the disk was.
fn blackhole_aftermath(p: &mut Plan, point: [f64; 3], seed: f32) {
    let t = FIRE;
    let by = p.by;
    for i in 0..DEBRIS {
        // the blocks the shader tears up and flies round the hole leave the ground at the moment it does
        let (a, r0) = (debris_angle(i, seed), debris_r0(i, seed));
        // (the blast has levelled the ground there to the target's block, which is where the shader starts them)
        let (x, z) = ((point[0] + a.cos() * r0).floor() as i32, (point[2] + a.sin() * r0).floor() as i32);
        let tl = t + debris_t(i);
        if debris_big(i, seed) {
            p.at(tl, format!("fill {} {} {} {x} {by} {z} minecraft:air", x - 1, by - 1, z - 1));
        } else {
            p.at(tl, format!("setblock {x} {by} {z} minecraft:air"));
        }
        p.at(tl, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {x} {} {z} 0.8 0.3 0.8 0.3 24 force"#, by + 1));
        if i % 5 == 0 {
            let pitch = p.rng.uniform(0.5, 0.8);
            p.at(tl, format!("playsound minecraft:block.rooted_dirt.break block @a {x} {by} {z} 3 {pitch:.2}"));
        }
    }
    const FLUNG: [&str; 7] = [
        "minecraft:dirt",
        "minecraft:cobblestone",
        "minecraft:stone",
        "minecraft:grass_block",
        "minecraft:cobbled_deepslate",
        "minecraft:oak_log",
        "minecraft:gravel",
    ];
    for _ in 0..70 {
        // real blocks spat out of the disk, thrown far across the land where they come down as rubble
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = p.rng.uniform(10.0, 22.0);
        let (x, z) = (point[0] + a.cos() * rr, point[2] + a.sin() * rr);
        let y = f64::from(by) + HOLE_H + p.rng.uniform(-2.0, 2.0);
        // along the disk's turn (clockwise seen from above, as the shader spins it), a little outwards and up
        let sp = p.rng.uniform(1.0, 1.9);
        let (vx, vz) = ((a.sin() * 0.9 + a.cos() * 0.45) * sp, (-a.cos() * 0.9 + a.sin() * 0.45) * sp);
        let vy = p.rng.uniform(0.1, 0.7);
        let blk = *p.rng.pick(&FLUNG);
        let tl = t + p.rng.uniform(1.5, 9.8) as f32;
        p.at(tl, format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b,Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"));
    }
    let (bx, by, bz) = (p.bx, p.by, p.bz);
    let bowl_r = f64::from(p.laser.bowl_r);
    let hy = f64::from(by) + HOLE_H;
    const ARMS: [&str; 4] = ["minecraft:sculk", "minecraft:black_concrete", "minecraft:sculk", "minecraft:crying_obsidian"];
    let a0 = p.rng.uniform(0.0, 2.0 * PI);
    for arm in 0..4 {
        // logarithmic spiral arms out across the land, drawn in from the outside as the ground is dragged towards the hole
        let mut last = (i32::MIN, i32::MIN);
        for i in 0..150 {
            let u = f64::from(i) / 149.0;
            let rr = 44.0 + 56.0 * u;
            let a = a0 + f64::from(arm) * PI / 2.0 + (rr / 44.0).ln() * 2.6 + p.rng.uniform(-0.03, 0.03);
            let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
            if (x, z) == last {
                continue;
            }
            last = (x, z);
            let w = if u < 0.5 { 1 } else { 0 };
            let blk = *p.rng.pick(&ARMS);
            let tl = t + 0.6 + (1.0 - u) as f32 * 5.0;
            for tag in ["#minecraft:dirt", "#minecraft:sand", "#minecraft:base_stone_overworld"] {
                p.at(tl, surf(x, z, &format!("fill ~-{w} ~-1 ~-{w} ~{w} ~-1 ~{w} {blk} replace {tag}")));
            }
            if i % 6 == 0 {
                p.at(tl, surf(x, z, "particle minecraft:portal ~ ~0.5 ~ 0 0 0 1.5 12 force"));
            }
        }
    }
    const TORN: [&str; 6] = [
        "minecraft:obsidian",
        "minecraft:crying_obsidian",
        "minecraft:cobbled_deepslate",
        "minecraft:blackstone",
        "minecraft:obsidian",
        "minecraft:amethyst_block",
    ];
    for k in 0..8 {
        // streams of rock torn up off the rim, reaching up and curving round towards the hole, left standing
        let a = f64::from(k) * PI / 4.0 + p.rng.uniform(-0.25, 0.25);
        let r0 = bowl_r + p.rng.uniform(2.0, 6.0);
        let (x0, z0) = (f64::from(bx) + 0.5 + a.cos() * r0, f64::from(bz) + 0.5 + a.sin() * r0);
        let reach = p.rng.uniform(0.55, 0.8);
        let tk = t + 1.5 + k as f32 * 0.7;
        for i in 0..44 {
            let u = f64::from(i) / 43.0 * reach;
            let rr = r0 + (7.0 - r0) * u;
            let aa = a + 0.9 * u * u;
            let (x, z) = (f64::from(bx) + 0.5 + aa.cos() * rr, f64::from(bz) + 0.5 + aa.sin() * rr);
            let y = f64::from(by) + (hy - 4.0 - f64::from(by)) * u.powf(1.4);
            let blk = if u > reach * 0.85 { "minecraft:crying_obsidian" } else { *p.rng.pick(&TORN) };
            let tl = tk + (u / reach) as f32 * 1.6;
            p.at(tl, format!("setblock {} {} {} {blk}", x.floor() as i32, y.floor() as i32, z.floor() as i32));
            if i == 0 {
                p.at(tl, surf(x0.floor() as i32, z0.floor() as i32, &format!("fill ~ ~-1 ~ ~ ~ ~ {blk}")));
                p.at(tl, format!("playsound minecraft:block.sculk_shrieker.shriek block @a {x:.1} {y:.1} {z:.1} 2 0.5"));
            }
            if i % 8 == 0 {
                p.at(tl, format!(r#"particle minecraft:block{{block_state:"{blk}"}} {x:.1} {y:.1} {z:.1} 0.4 0.4 0.4 0.1 10 force"#));
            }
        }
    }
    // the moment it evaporates, the matter still circling it is left hanging where the disk was
    let te = t + BH_END;
    for _ in 0..120 {
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = 9.0 + 16.0 * p.rng.next().sqrt();
        let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
        let y = (hy + p.rng.uniform(-1.5, 1.5) + (a * 2.0).sin() * 2.0).round() as i32;
        let blk = *p.rng.pick(&TORN);
        let tl = te + p.rng.uniform(0.0, 0.15) as f32;
        p.at(tl, format!("setblock {x} {y} {z} {blk}"));
    }
    p.at(te + 0.2, format!("playsound minecraft:block.amethyst_block.resonate block @a {bx} {} {bz} 4 0.5", hy as i32));
}

/// The godly wings' facing: from the impact towards the player, in the xz plane.
pub fn wing_angle(target: [f64; 3], me: [f64; 3]) -> f32 {
    (me[2] - target[2]).atan2(me[0] - target[0]) as f32
}

// ---- the meteor storm ------------------------------------------------------------------------------------------------

/// Meteor storm: how many meteors, how far out from the target they land, and when the big one lands (after FIRE).
/// Where, when and how big each meteor is comes from met_*, the same as strike.wgsl's: keep them in step.
const MET_N: usize = 72;
const MET_SPAN: f64 = 120.0;
const BIG_T: f32 = 13.5;
/// The integer hash strike.wgsl uses (PCG): the same bits there and here.
fn pcg(x: u32) -> u32 {
    let s = x.wrapping_mul(747_796_405).wrapping_add(2_891_336_453);
    let w = ((s >> ((s >> 28) + 4)) ^ s).wrapping_mul(277_803_737);
    (w >> 22) ^ w
}
/// A meteor's own random numbers (`k` picks which), as strike.wgsl's `mh`.
fn mh(i: u32, seed: u32, k: u32) -> f64 {
    f64::from(pcg(i ^ pcg(seed ^ pcg(k)))) / 4_294_967_296.0
}
/// Where a meteor lands (x, z off the target) and when (seconds after FIRE), as strike.wgsl's `met_where`: a third of
/// them come down together, the fragments of one that broke up, the rest anywhere, at any time.
fn met_where(i: usize, seed: f32) -> (f64, f64, f32) {
    let (i, s) = (i as u32, seed as u32);
    if mh(i, s, 5) < 0.33 {
        let c = 100 + ((mh(i, s, 6) * 6.0) as u32).min(5);
        let ca = mh(c, s, 1) * 2.0 * PI;
        let cr = 24.0 + (MET_SPAN - 30.0) * mh(c, s, 2).sqrt();
        let oa = mh(i, s, 7) * 2.0 * PI;
        let or = 3.0 + 11.0 * mh(i, s, 8);
        let t = 3.0 + 8.5 * mh(c, s, 3) + 1.4 * mh(i, s, 9);
        return (ca.cos() * cr + oa.cos() * or, ca.sin() * cr + oa.sin() * or, t as f32);
    }
    let a = mh(i, s, 1) * 2.0 * PI;
    let r = 14.0 + (MET_SPAN - 14.0) * mh(i, s, 2).sqrt();
    (a.cos() * r, a.sin() * r, (2.5 + 9.5 * mh(i, s, 3)) as f32)
}
fn met_t(i: usize, seed: f32) -> f32 {
    met_where(i, seed).2
}
fn met_off(i: usize, seed: f32) -> (f64, f64) {
    let (x, z, _) = met_where(i, seed);
    (x, z)
}
/// The horizontal direction the meteors come in from (strike.wgsl's met_dir); they head the other way, downrange.
fn met_from(seed: f32) -> f64 {
    (f64::from(seed) * 0.0911).fract() * 2.0 * PI
}
/// 0 tiny, 1 medium, 2 big.
fn met_class(i: usize, seed: f32) -> usize {
    let h = mh(i as u32, seed as u32, 4);
    if h < 0.6 {
        0
    } else if h < 0.87 {
        1
    } else {
        2
    }
}

/// A meteor storm: 72 meteors over the land round the target, then the extinction impact on it.
fn meteor_plan(laser: &'static Laser, target: &Target, terrain: bool, dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let r2 = |v: f64| (v * 100.0).round() / 100.0;
    let (tx, ty, tz) = (r2(target.point[0]), r2(target.point[1]), r2(target.point[2]));
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let t = FIRE;
    let tb = t + BIG_T;
    let bar = |text: &str, color: &str| format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#);
    // sound takes its time to reach the player: about 343 blocks a second
    let late = |x: f64, y: f64, z: f64| (((x - me[0]).powi(2) + (y - me[1]).powi(2) + (z - me[2]).powi(2)).sqrt() / 343.0) as f32;

    // the warning, then the sky starts falling
    p.csound(0.0, "charge", 10.0, 1.0);
    p.csound(3.4, "lockon", 8.0, 1.0);
    p.at(3.5, bar("METEOR STORM INBOUND", laser.color));
    p.csound(t, "fire", 10.0, 1.0);
    p.csound(t + 0.3, "storm", 8.0, 1.0);
    p.csound(t + 3.0, "rumble", 6.0, 1.0);
    p.csound(t + 8.0, "rumble", 6.0, 0.9);
    // the big one coming in, and its blast reaching the player after its flash
    let heard = tb + late(tx, ty, tz);
    p.csound(tb - 6.5, "approach", 10.0, 1.0);
    p.at(tb - 6.0, bar("IMPACT IMMINENT", "dark_red"));
    p.csound(heard, "impact", 10.0, 1.0);
    // the camera: the air shaking more and more as it comes in, then the hardest jolt of all, and the land shaking on
    for (k, s) in [0.25, 0.35, 0.45].iter().enumerate() {
        p.shake(tb - 3.0 + k as f32, *s, 1.6);
    }
    p.shake(heard, 1.0, 6.0);
    p.shake(heard + 2.5, 0.55, 4.0);
    p.shake(heard + 6.0, 0.35, 4.0);
    for i in 0..5 {
        p.shake(t + 1.0 + i as f32 * 2.0, 0.15, 2.0);
    }
    p.at(tb + 0.2, bar("EXTINCTION EVENT", "dark_red"));
    p.csound(heard + 6.0, "rumble", 9.0, 0.75);
    p.csound(heard + 12.0, "shutdown", 9.0, 1.0);

    for i in 0..MET_N {
        // each meteor: its whistle coming down, the blast, a crater where it lands
        let (ox, oz) = met_off(i, shader_seed);
        let (x, z) = ((target.point[0] + ox).floor() as i32, (target.point[2] + oz).floor() as i32);
        let cls = met_class(i, shader_seed);
        let tl = t + met_t(i, shader_seed);
        // its whoosh coming in (where it lands), then its hit, once the sound has had time to reach the player. A
        // player further than `playsound` reaches (16 blocks a unit of volume) still hears it, from its direction, at
        // `min`: quieter the further off, louder the bigger; far ones are muffled and echo.
        // sized by the take, not by pitch (pitching a sound up makes it toy-like); only a little variation
        let pitch = p.rng.uniform(0.97, 1.03);
        let dist = ((f64::from(x) - me[0]).powi(2) + (f64::from(z) - me[2]).powi(2)).sqrt();
        let min = ((1.25 - dist / 320.0).clamp(0.3, 1.0) * [0.6, 0.8, 1.0][cls]).max(0.2);
        // the hit recorded at its size (tiny, medium, big), near or far; a whoosh at random
        let hit = format!("{}{}", if dist > 90.0 { "hit_far" } else { "hit" }, cls + 1);
        let whoosh = format!("whoosh{}", p.rng.int(1, 2));
        p.at(tl - 1.3, surf(x, z, &format!("playsound orbital:meteor.{whoosh} block @a ~ ~ ~ 4 {pitch:.2} {:.2}", min * 0.8)));
        let tl_heard = tl + late(f64::from(x), ty, f64::from(z));
        p.at(tl_heard, surf(x, z, &format!("playsound orbital:meteor.{hit} block @a ~ ~ ~ 4 {pitch:.2} {min:.2}")));
        p.shake(tl_heard, [0.3, 0.5, 0.75][cls] * falloff(dist), [0.8, 1.4, 2.2][cls]);
        match cls {
            0 => p.at(tl, surf(x, z, "particle minecraft:explosion ~ ~1 ~ 1 1 1 0 4 force")),
            1 => {
                p.at(tl, surf(x, z, "particle minecraft:explosion_emitter ~ ~1 ~ 0 0 0 0 1 force"));
                p.at(tl, surf(x, z, "particle minecraft:campfire_signal_smoke ~ ~1 ~ 2 1 2 0.02 20 force"));
            }
            _ => {
                p.at(tl, surf(x, z, "particle minecraft:explosion_emitter ~ ~2 ~ 3 2 3 0 4 force"));
                p.at(tl, surf(x, z, "particle minecraft:lava ~ ~1 ~ 3 1 3 0 60 force"));
                p.at(tl, surf(x, z, "particle minecraft:campfire_signal_smoke ~ ~1 ~ 4 1 4 0.03 50 force"));
            }
        }
        let kill = [4, 8, 14][cls];
        p.at(tl + 0.05, surf(x, z, &format!("kill @e[type=!minecraft:player,distance=..{kill}]")));
        if terrain {
            p.later(tl - 0.4, move |q| meteor_crater(q, x, z, cls, tl));
        }
    }

    // the big one hits
    p.at(tb, format!("particle minecraft:explosion_emitter {tx} {} {tz} 14 6 14 0 10 force", ty + 4.0));
    p.at(tb + 0.05, format!("particle minecraft:flash {tx} {} {tz} 0 0 0 0 1 force", ty + 20.0));
    p.at(tb + 0.1, format!(r#"particle minecraft:block{{block_state:"minecraft:blackstone"}} {tx} {} {tz} 20 4 20 3 400 force"#, ty + 2.0));
    for i in 0..10 {
        p.at(tb + 0.5 + i as f32 * 0.6, format!("particle minecraft:lava {tx} {} {tz} 30 6 30 0 40 force", ty + 4.0));
        p.at(tb + 0.7 + i as f32 * 0.6, format!("particle minecraft:campfire_signal_smoke {tx} {} {tz} 30 4 30 0.05 40 force", ty + 2.0));
    }
    for i in 0..26 {
        // ash coming down over everything
        let tk = tb + 2.0 + i as f32 * 0.6;
        p.at(tk, format!("particle minecraft:ash {tx} {} {tz} 70 20 70 0 300 force", ty + 25.0));
        p.at(tk, format!("particle minecraft:white_ash {tx} {} {tz} 70 20 70 0 150 force", ty + 25.0));
    }
    for tk in [0.1, 0.8, 2.0, 4.0, 7.0] {
        p.at(tb + tk, format!("execute positioned {tx} {ty} {tz} run kill @e[type=!minecraft:player,distance=..130]"));
    }
    if terrain {
        let (floor_y, point) = (bedrock_top(dimension), target.point);
        p.later(tb - 0.3, move |q| extinction(q, tb, floor_y, point, shader_seed));
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// One meteor's crater (cls: 0 tiny, 1 medium, 2 big) at column (x, z), dug at `tl`: a round bowl, its walls fused,
/// a meteorite at the bottom, a lip of thrown-up rubble, scorch marks and fires round it. Every command measures from
/// the ground at (x, z), so the order matters: trees first (a tick earlier), then what is above the ground, the
/// lining, the layers from the deepest up, the meteorite, and the top layer last (which moves the ground).
fn meteor_crater(p: &mut Plan, x: i32, z: i32, cls: usize, tl: f32) {
    let (r, d) = [(3, 2), (6, 4), (11, 7)][cls];
    // a round disc of rows at depth y (relative to the ground), radius rr
    let rows = |rr: i32, y_lo: i32, y_hi: i32, block: &str, replace: &str| -> Vec<String> {
        (-rr..=rr)
            .map(|dz| {
                let hw = (f64::from(rr * rr - dz * dz).max(0.0).sqrt() + 0.35) as i32;
                format!("fill ~-{hw} ~{y_lo} ~{dz} ~{hw} ~{y_hi} ~{dz} {block}{replace}")
            })
            .collect()
    };
    let a = r + 2;
    for tag in ["#minecraft:logs", "#minecraft:leaves"] {
        p.at(tl - 0.05, surf(x, z, &format!("fill ~-{a} ~-14 ~-{a} ~{a} ~14 ~{a} minecraft:air replace {tag}")));
    }
    for c in rows(r + 1, 0, 6, "minecraft:air", "") {
        p.at(tl, surf(x, z, &c));
    }
    for tag in ["#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand"] {
        for c in rows(r + 1, -(d + 2), -1, "minecraft:blackstone", &format!(" replace {tag}")) {
            p.at(tl, surf(x, z, &c));
        }
    }
    for _ in 0..(1 + 3 * cls) {
        let (dx, dz) = (p.rng.int(-r, r), p.rng.int(-r, r));
        p.at(tl, surf(x, z, &format!("fill ~{} ~-{} ~{} ~{} ~-1 ~{} minecraft:magma_block replace minecraft:blackstone", dx - 1, d + 2, dz - 1, dx + 1, dz + 1)));
    }
    for k in (1..d).rev() {
        let rk = ((f64::from(r) * (1.0 - f64::from(k) / (f64::from(d) + 0.5)).sqrt()).round() as i32).max(1);
        for c in rows(rk, -(k + 1), -(k + 1), "minecraft:air", "") {
            p.at(tl, surf(x, z, &c));
        }
    }
    let core = ["minecraft:magma_block", "minecraft:raw_iron_block", "minecraft:ancient_debris"][cls];
    p.at(tl, surf(x, z, &format!("setblock ~ ~-{} ~ {core}", d + 1)));
    if cls == 2 {
        p.at(tl, surf(x, z, &format!("fill ~-1 ~-{} ~-1 ~1 ~-{} ~1 minecraft:magma_block replace minecraft:blackstone", d + 1, d + 1)));
    }
    for c in rows(r, -1, -1, "minecraft:air", "") {
        p.at(tl, surf(x, z, &c));
    }
    // the lip: rubble thrown up round the edge, and scorch marks splashed out past it
    const LIP: [&str; 5] = ["minecraft:cobblestone", "minecraft:blackstone", "minecraft:coarse_dirt", "minecraft:gravel", "minecraft:tuff"];
    for _ in 0..[8, 18, 36][cls] {
        let ang = p.rng.uniform(0.0, 2.0 * PI);
        let rr = f64::from(r) + p.rng.uniform(0.6, 2.2);
        let (lx, lz) = (x + (ang.cos() * rr).round() as i32, z + (ang.sin() * rr).round() as i32);
        let blk = *p.rng.pick(&LIP);
        p.at(tl + 0.1, surf(lx, lz, &format!("setblock ~ ~ ~ {blk} keep")));
    }
    for _ in 0..[3, 6, 10][cls] {
        let ang = p.rng.uniform(0.0, 2.0 * PI);
        let rr = f64::from(r) + p.rng.uniform(1.0, f64::from(r) * 1.4 + 2.0);
        let (sx, sz) = (x + (ang.cos() * rr).round() as i32, z + (ang.sin() * rr).round() as i32);
        let s = p.rng.int(1, 1 + cls as i32);
        let blk = *p.rng.pick(&["minecraft:coarse_dirt", "minecraft:blackstone", "minecraft:coarse_dirt"]);
        p.at(tl + 0.1, surf(sx, sz, &format!("fill ~-{s} ~-1 ~-{s} ~{s} ~-1 ~{s} {blk} replace #minecraft:dirt")));
    }
    // fires round it, and rocks thrown out
    for _ in 0..(3 + 4 * cls) {
        let ang = p.rng.uniform(0.0, 2.0 * PI);
        let rr = f64::from(r) + p.rng.uniform(1.0, 5.0);
        let (fx, fz) = (x + (ang.cos() * rr).round() as i32, z + (ang.sin() * rr).round() as i32);
        let dt = p.rng.uniform(0.1, 0.6) as f32;
        p.at(tl + dt, surf(fx, fz, "setblock ~ ~ ~ minecraft:fire keep"));
    }
    for _ in 0..[1, 4, 10][cls] {
        let ang = p.rng.uniform(0.0, 2.0 * PI);
        let sp = p.rng.uniform(0.3, 0.9);
        let (vx, vy, vz) = (ang.cos() * sp, p.rng.uniform(0.4, 1.0), ang.sin() * sp);
        let blk = *p.rng.pick(&["minecraft:cobblestone", "minecraft:blackstone", "minecraft:dirt", "minecraft:magma_block"]);
        p.at(tl + 0.05, surf(x, z, &format!("summon minecraft:falling_block ~ ~1 ~ {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b,Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}")));
    }
}

/// The extinction impact at the target: everything above the ground flattened out to 100 blocks, the land charred out
/// to 135, a crater 125 blocks across with a raised rim, a shaft to bedrock with lava at the bottom, a melt sheet on
/// its floor, and ejecta thrown far across the land.
fn extinction(p: &mut Plan, tb: f32, floor_y: i32, point: [f64; 3], seed: f32) {
    // each stage is worked out just before it starts
    // 1. the blast (in bands of height: a fill is capped at 32768 blocks)
    p.later(tb + 0.0 - 0.15, move |p| {
        let by = p.by;
        for band in 0..4 {
            let y0 = by + 1 + band * 20;
            for c in p.disc(100, y0, y0 + 19, "minecraft:air", 0.1, None) {
                p.at(tb + 0.1 + band as f32 * 0.1, c);
            }
        }
    });
    // 2. charred land
    p.later(tb + 0.5 - 0.15, move |p| {
        let laser = p.laser;
        let by = p.by;
        for &(rad, block, rough, repl) in laser.scorch {
            for c in p.disc(rad, by - 4, by + 1, block, f64::from(rough), Some(repl)) {
                let dt = p.rng.next() as f32 * 1.5;
                p.at(tb + 0.6 + dt, c);
            }
        }
    });
    // 3. the crater, blown out in under two seconds, its walls fused as it goes
    p.later(tb + 0.2 - 0.15, move |p| {
        let laser = p.laser;
        let (bx, by, bz) = (p.bx, p.by, p.bz);
        const NATURAL: [&str; 5] = ["#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand", "minecraft:gravel", "minecraft:coarse_dirt"];
        let prim = laser.lining[0].0;
        let (bowl_r, bowl_d) = (laser.bowl_r, laser.bowl_d);
        let mut d = 0;
        while d < bowl_d {
            let r = ((f64::from(bowl_r) * (1.0 - f64::from(d) / (f64::from(bowl_d) + 0.5)).sqrt()) as i32).max(4);
            let tl = tb + 0.3 + d as f32 * 0.045;
            let (y_lo, y_hi) = (by - d - 2, by - d);
            let rs = p.rects(r, f64::from(laser.bowl_rough));
            for tag in NATURAL {
                for c in Plan::edge_fills(&rs, y_lo - 1, y_hi, prim, tag, 2) {
                    p.at(tl - 0.05, c);
                }
            }
            for c in Plan::fills(&rs, y_lo, y_hi, "minecraft:air", None, 0) {
                p.at(tl, c);
            }
            p.mottle(r, y_lo, y_hi, tl, 24);
            d += 3;
        }
        let (fb, fr, fq) = laser.bowl_floor;
        for c in p.disc(bowl_r - 6, by - bowl_d - 1, by - bowl_d + 2, fb, f64::from(fr), Some(fq)) {
            p.at(tb + 2.2, c);
        }
        for _ in 0..14 {
            // pools of melt on the floor, still molten
            let a = p.rng.uniform(0.0, 2.0 * PI);
            let rr = p.rng.uniform(16.0, f64::from(bowl_r) * 0.6);
            let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
            let s = p.rng.int(1, 3);
            p.at(tb + 2.6, surf(x, z, &format!("fill ~-{s} ~-1 ~-{s} ~{s} ~-1 ~{s} minecraft:lava")));
        }
    });
    // 4. the shaft to bedrock, and a lava lake at the bottom
    p.later(tb + 0.9 - 0.15, move |p| {
        let laser = p.laser;
        let by = p.by;
        let bowl_d = laser.bowl_d;
        let mut y_hi = by - bowl_d;
        let mut i = 0;
        while y_hi >= floor_y {
            let r = ((f64::from(laser.shaft_r) - f64::from(i) * 0.3).round() as i32).max(laser.shaft_min);
            let ts = tb + 1.0 + i as f32 * 0.12;
            p.dig(r, (y_hi - 3).max(floor_y), y_hi, ts, f64::from(laser.shaft_rough), 1);
            p.mottle(r, (y_hi - 3).max(floor_y), y_hi, ts, 4);
            y_hi -= 4;
            i += 1;
        }
        for (k, &(rad, lo, hi, block)) in laser.bottom.iter().enumerate() {
            for c in p.disc(rad, floor_y + lo, floor_y + hi, block, 0.0, None) {
                p.at(tb + 4.0 + 0.1 * k as f32, c);
            }
        }
    });
    // 5. the rim: rock thrown up round the edge, piled highest nearest the crater
    p.later(tb + 0.7 - 0.15, move |p| {
        let laser = p.laser;
        let (bx, by, bz) = (p.bx, p.by, p.bz);
        let bowl_r = laser.bowl_r;
        const RIM: [&str; 6] = ["minecraft:cobblestone", "minecraft:blackstone", "minecraft:tuff", "minecraft:cobbled_deepslate", "minecraft:basalt", "minecraft:magma_block"];
        for _ in 0..280 {
            let a = p.rng.uniform(0.0, 2.0 * PI);
            let rr = f64::from(bowl_r) + 1.0 + 14.0 * p.rng.next().powf(1.5);
            let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
            let h = (6.0 * (1.0 - (rr - f64::from(bowl_r)) / 16.0)).round().max(1.0) as i32 + p.rng.int(-1, 1);
            let blk = *p.rng.pick(&RIM);
            let tl = tb + 0.8 + p.rng.uniform(0.0, 1.6) as f32;
            p.at(tl, format!("fill {} {} {} {} {} {} {blk} keep", x - 1, by + 1, z - 1, x + 1, by + h.max(1), z + 1));
        }
    });
    // 6. ejecta: real blocks thrown out over the land, landing as far as 250 blocks away, and rubble raining down
    p.later(tb + 0.0 - 0.15, move |p| {
        let (bx, by, bz) = (p.bx, p.by, p.bz);
        const EJECTA: [&str; 8] = [
            "minecraft:cobblestone",
            "minecraft:blackstone",
            "minecraft:magma_block",
            "minecraft:cobbled_deepslate",
            "minecraft:basalt",
            "minecraft:obsidian",
            "minecraft:tuff",
            "minecraft:dirt",
        ];
        // thrown every way at once: most along seven rays (the ones strike.wgsl's glowing ejecta follow) and downrange of
        // where it came in, some skimming low and far, some lobbed high, a few big chunks
        let from = met_from(seed);
        let (dx0, dz0) = (-from.cos(), -from.sin());
        let ray0 = f64::from(seed) * 0.3;
        for _ in 0..260 {
            let a = if p.rng.next() < 0.6 {
                ray0 + f64::from(p.rng.int(0, 6)) * 2.0 * PI / 7.0 + p.rng.uniform(-0.09, 0.09)
            } else {
                p.rng.uniform(0.0, 2.0 * PI)
            };
            let bias = 0.35 * p.rng.next();
            let (hx, hz) = (a.cos() * (1.0 - bias) + dx0 * bias, a.sin() * (1.0 - bias) + dz0 * bias);
            let hl = (hx * hx + hz * hz).sqrt().max(1e-6);
            let (hx, hz) = (hx / hl, hz / hl);
            let rr = p.rng.uniform(16.0, 40.0);
            let (x, z) = (point[0] + hx * rr, point[2] + hz * rr);
            let elev = 0.15 + 1.2 * p.rng.next().powf(0.7);
            let speed = (1.6 + 2.8 * p.rng.next().powi(2)) * p.rng.uniform(0.7, 1.3);
            let (vx, vy, vz) = (hx * elev.cos() * speed, elev.sin() * speed, hz * elev.cos() * speed);
            let blk = *p.rng.pick(&EJECTA);
            let tl = tb + (0.1 + 1.4 * p.rng.next().powi(2)) as f32;
            p.at(tl, format!("summon minecraft:falling_block {x:.1} {} {z:.1} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b,Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}", by + 3));
        }
        for k in 0..320 {
            // rubble coming down across the land, in rays reaching out furthest
            let on_ray = p.rng.next() < 0.5;
            let a = if on_ray { ray0 + f64::from(p.rng.int(0, 6)) * 2.0 * PI / 7.0 + p.rng.uniform(-0.06, 0.06) } else { p.rng.uniform(0.0, 2.0 * PI) };
            let rr = 80.0 + if on_ray { 170.0 } else { 110.0 } * p.rng.next().powf(1.4);
            let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
            let tl = tb + 1.5 + (rr / 210.0 * 6.0) as f32 + p.rng.uniform(0.0, 1.5) as f32;
            let blk = *p.rng.pick(&EJECTA);
            p.at(tl, surf(x, z, &format!("setblock ~ ~ ~ {blk} keep")));
            if k % 4 == 0 {
                p.at(tl, surf(x, z, &format!(r#"particle minecraft:block{{block_state:"{blk}"}} ~ ~0.5 ~ 0.6 0.4 0.6 0.2 16 force"#)));
            }
        }
    });
    // 7. the charred land burning
    p.later(tb + 0.9 - 0.15, move |p| {
        let laser = p.laser;
        let (bx, _, bz) = (p.bx, p.by, p.bz);
        let bowl_r = laser.bowl_r;
        for _ in 0..170 {
            let a = p.rng.uniform(0.0, 2.0 * PI);
            let rr = p.rng.uniform(f64::from(bowl_r) + 4.0, 130.0);
            let dt = p.rng.uniform(1.0, 5.0) as f32;
            p.at(tb + dt, surf(bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32, "setblock ~ ~ ~ minecraft:fire keep"));
        }
    });

}

// ---- the mothership --------------------------------------------------------------------------------------------------

/// Mothership: when it drops out of hyperspace (it has stopped a fifth of a second later), when its beam lands, sweeps,
/// cuts off and when it leaves (strike clock), how high its belly hangs over the target and how long a trench the beam
/// cuts. Where the beam is on the ground comes from ms_sweep, the same as strike.wgsl's: keep them in step (MS_*,
/// ms_sweep, ms_axis). The ship's own small coast after it stops has died away long before the beam fires, so it plays no
/// part here.
const MS_H: f64 = 420.0;
const MS_ARRIVE: f32 = 3.0;
const MS_HIT: f32 = 8.2;
const MS_SWEEP0: f32 = 10.0;
const MS_SWEEP1: f32 = 19.0;
const MS_CUT: f32 = 20.0;
const MS_LEAVE: f32 = 23.0;
const MS_END: f32 = 32.0;
const TRENCH_L: f64 = 100.0;
/// How far along the trench the beam is at `t`, 0 to 1: it eases away from the crater and eases to a stop.
fn ms_sweep(t: f32) -> f64 {
    let s = f64::from(((t - MS_SWEEP0) / (MS_SWEEP1 - MS_SWEEP0)).clamp(0.0, 1.0));
    s * s * (3.0 - 2.0 * s)
}
/// When the beam is `u` of the way along (ms_sweep turned round).
fn ms_when(u: f64) -> f32 {
    let s = 0.5 - ((1.0 - 2.0 * u.clamp(0.0, 1.0)).asin() / 3.0).sin();
    MS_SWEEP0 + (MS_SWEEP1 - MS_SWEEP0) * s as f32
}
/// The way the beam sweeps: from the target away from the player (the wings' angle turned round), whichever way the
/// ship came in, so the player is never in its path.
fn ms_axis(wing: f32) -> (f64, f64) {
    (-f64::from(wing.cos()), -f64::from(wing.sin()))
}

/// Which way the mothership comes in, picked in the wheel: its settings key, how the game says it, and its button.
/// The index is the shader's approach (`frame.mod_params[3].x`): it points the ship and flies it in that way.
pub struct Choice {
    pub key: &'static str,
    pub label: &'static str,
    pub button: &'static str,
}
pub const APPROACHES: [Choice; 5] = [
    Choice { key: "ahead", label: "from ahead, towards you", button: "AHEAD" },
    Choice { key: "behind", label: "from behind you", button: "BEHIND" },
    Choice { key: "left", label: "from your left", button: "LEFT" },
    Choice { key: "right", label: "from your right", button: "RIGHT" },
    Choice { key: "overhead", label: "from overhead", button: "ABOVE" },
];

/// How the mothership arrives, picked in the wheel: its settings key, how the game says it, and its button. The index
/// is the shader's arrival style (`frame.mod_params[3].y`).
pub const ARRIVALS: [Choice; 3] = [
    Choice { key: "snap", label: "snaps in, like film", button: "SNAP" },
    Choice { key: "unfold", label: "unfolds out of a point", button: "UNFOLD" },
    Choice { key: "warp", label: "pulls out of a warp streak", button: "WARP" },
];

/// The mothership: it drops in out of hyperspace (from `approach`, one of APPROACHES), its shadow over the land, charges, drills a shaft at the target, sweeps its beam away from
/// the player cutting a trench, and leaves. `wing` is the shader's facing angle (towards the player).
fn mothership_plan(laser: &'static Laser, target: &Target, terrain: bool, dimension: &str, wing: f32, me: [f64; 3], approach: usize) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let r2 = |v: f64| (v * 100.0).round() / 100.0;
    let (tx, ty, tz) = (r2(target.point[0]), r2(target.point[1]), r2(target.point[2]));
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let bar = |text: &str, color: &str| format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#);
    let late = |x: f64, y: f64, z: f64| (((x - me[0]).powi(2) + (y - me[1]).powi(2) + (z - me[2]).powi(2)).sqrt() / 343.0) as f32;
    let axis = ms_axis(wing);
    let point = target.point;
    // where the beam is on the ground at `t`
    let spot = move |t: f32| {
        let u = ms_sweep(t) * TRENCH_L;
        (point[0] + axis.0 * u, point[2] + axis.1 * u)
    };
    let ship = late(tx, ty + MS_H, tz);

    // it drops in: a deep shove of displaced air the instant it stops; its boom comes down after the light
    p.at(MS_ARRIVE - 1.0, bar(&format!("MOTHERSHIP INBOUND {}", APPROACHES[approach.min(4)].label.to_uppercase()), laser.color));
    p.csound(MS_ARRIVE - 0.02, "arrival", 10.0, 1.0);
    p.csound(MS_ARRIVE + ship, "boom", 10.0, 1.0);
    // the camera: the shove of air as it stops, then its boom coming down from overhead
    p.shake(MS_ARRIVE + 0.2, 0.35, 1.0);
    p.shake(MS_ARRIVE + ship, 0.85, 3.5);
    p.at(MS_ARRIVE + 0.6, bar("MOTHERSHIP OVERHEAD", laser.color));
    p.csound(MS_ARRIVE + ship + 0.3, "hum", 8.0, 1.0);
    // it charges, and fires: the blast reaches the player after the flash
    p.csound(FIRE, "charge", 10.0, 1.0);
    p.at(MS_HIT - 0.9, bar("BEAM LOCKED", laser.color));
    let heard = MS_HIT + late(tx, ty, tz);
    let heard_dist = sound_from(target.point, me).1;
    p.csound(heard, "fire", 10.0, 1.0);
    // the camera: the charge building, the beam landing (the hardest jolt of the strike), the ground shaking while
    // it burns
    let fo = falloff(heard_dist).max(0.5);
    p.shake(FIRE + 2.0, 0.15, 1.5);
    p.shake(FIRE + 3.0, 0.22, 1.5);
    p.shake(heard, fo, 4.0);
    let mut tk = MS_HIT + 1.0;
    while tk < MS_CUT {
        p.shake(tk + (heard - MS_HIT), 0.22 * fo.max(0.6), 1.3);
        tk += 1.0;
    }
    // the beam's roar, two takes end to end (6.2 s each, crossfading)
    p.csound(MS_HIT + 0.15, "beam1", 10.0, 1.0);
    p.csound(MS_HIT + 5.9, "beam2", 10.0, 1.0);
    p.csound(heard + 1.2, "rumble", 9.0, 1.0);
    p.csound(heard + 7.4, "rumble", 8.0, 1.0);
    p.at(MS_HIT + 0.1, bar("DIRECT HIT", "white"));
    for k in 0..7 {
        // the beam searing across the land, heard from where it is: in full within 96 blocks, and from further off (out
        // to the 1000 the mothership reaches) still clearly, at the volume floor, quieter the further
        let tk = MS_SWEEP0 - 0.6 + k as f32 * 1.35;
        let (gx, gz) = spot(tk);
        let dist = ((gx - me[0]).powi(2) + (gz - me[2]).powi(2)).sqrt();
        let min = (1.2 - dist / 350.0).clamp(0.5, 0.95);
        let take = 1 + k % 2;
        p.at(tk + late(gx, ty, gz), surf(gx.floor() as i32, gz.floor() as i32, &format!("playsound orbital:mothership.sweep{take} block @a ~ ~ ~ 6 1 {min:.2}")));
    }
    let (ex, ez) = spot(MS_CUT);
    p.csound(MS_CUT + late(ex, ty, ez), "cutoff", 9.0, 1.0);
    p.shake(MS_CUT + late(ex, ty, ez), 0.45, 2.0);
    // a still moment, then it is gone the way it points, and its boom follows it out (all of it quieter than the beam
    // landing)
    p.csound(MS_LEAVE - 0.8, "depart", 10.0, 1.0);
    p.csound(MS_LEAVE + ship, "boom", 8.0, 1.0);
    p.shake(MS_LEAVE, 0.55, 2.0);
    p.shake(MS_LEAVE + ship, 0.6, 3.0);

    // ---- particles in the world ----
    for i in 0..8 {
        // the ground under it stirring while it charges: dust lifting, a shimmer of energy coming up off it
        let tk = FIRE + 0.3 + i as f32 * 0.45;
        let s = 10.0 - f64::from(i);
        p.at(tk, format!("particle minecraft:white_ash {tx} {} {tz} {s:.1} 1 {s:.1} 0 90 force", ty + 1.0));
        p.at(tk, format!("particle minecraft:poof {tx} {} {tz} {s:.1} 0.3 {s:.1} 0.04 30 force", ty + 0.5));
        p.at(tk, format!("particle minecraft:end_rod {tx} {} {tz} 2 0.5 2 0.08 {} force", ty + 1.0, 6 + i * 3));
    }
    p.at(MS_HIT, format!("particle minecraft:explosion_emitter {tx} {} {tz} 2 1 2 0 4 force", ty + 1.0));
    p.at(MS_HIT + 0.05, format!(r#"particle minecraft:block{{block_state:"minecraft:obsidian"}} {tx} {} {tz} 3 1 3 2.0 500 force"#, ty + 1.0));
    p.at(MS_HIT + 0.1, format!(r#"particle minecraft:block{{block_state:"minecraft:stone"}} {tx} {} {tz} 5 1 5 1.6 400 force"#, ty + 1.0));
    let mut tk = MS_HIT + 0.2;
    let mut k = 0;
    while tk < MS_CUT {
        // where the beam is cutting: molten rock thrown up, fire, smoke boiling off; anything there dies
        let (gx, gz) = spot(tk);
        let (x, z) = (gx.floor() as i32, gz.floor() as i32);
        p.at(tk, surf(x, z, "particle minecraft:lava ~ ~1 ~ 2 1 2 0 14 force"));
        p.at(tk, surf(x, z, "particle minecraft:flame ~ ~0.5 ~ 2.5 0.6 2.5 0.12 30 force"));
        if k % 2 == 0 {
            p.at(tk, surf(x, z, "particle minecraft:explosion ~ ~1 ~ 2 1 2 0 3 force"));
            p.at(tk, surf(x, z, "particle minecraft:large_smoke ~ ~2 ~ 2.5 2 2.5 0.06 24 force"));
            p.at(tk, format!("execute positioned {gx:.1} {ty} {gz:.1} run kill @e[type=!minecraft:player,distance=..16]"));
        }
        tk += 0.25;
        k += 1;
    }
    let mut tk = MS_SWEEP0 + 1.0;
    while tk < MS_END {
        // steam and smoke off the trench as it cools
        tk += 0.7;
        let u = (p.rng.next() * ms_sweep(tk - 0.8)) * TRENCH_L;
        let (x, z) = (point[0] + axis.0 * u, point[2] + axis.1 * u);
        let (x, z) = (x.floor() as i32, z.floor() as i32);
        p.at(tk, surf(x, z, "particle minecraft:campfire_cosy_smoke ~ ~0.5 ~ 3 0.5 3 0.03 14 force"));
        p.at(tk, surf(x, z, "particle minecraft:cloud ~ ~1 ~ 3 1 3 0.04 18 force"));
    }
    for tk in [0.1, 0.8, 1.6, 3.0] {
        p.at(MS_HIT + tk, format!("execute positioned {tx} {ty} {tz} run kill @e[type=!minecraft:player,distance=..{KILL_RADIUS}]"));
    }

    if terrain {
        // a far target's trench runs out past what the game keeps loaded round the player: keep it loaded until the
        // trench has been cut (a forceload takes 256 chunks at most; this is 200 at most)
        let (ex, ez) = (point[0] + axis.0 * TRENCH_L, point[2] + axis.1 * TRENCH_L);
        let (x0, x1) = ((point[0].min(ex) - 48.0).floor() as i32, (point[0].max(ex) + 48.0).floor() as i32);
        let (z0, z1) = ((point[2].min(ez) - 48.0).floor() as i32, (point[2].max(ez) + 48.0).floor() as i32);
        p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        p.at(MS_END + 1.0, format!("forceload remove {x0} {z0} {x1} {z1}"));
        let floor_y = bedrock_top(dimension);
        mothership_crater(&mut p, floor_y);
        // the trench, a stretch at a time, each worked out just before the beam gets there
        let mut d0 = 0.0;
        while d0 < TRENCH_L {
            let d1 = (d0 + 8.0).min(TRENCH_L);
            p.later(ms_when(d0 / TRENCH_L) - 0.3, move |q| trench(q, point, axis, d0, d1));
            d0 = d1;
        }
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// The crater where the beam first comes down: the land above it vaporised, the ground round it charred, a bowl, and a
/// shaft drilled to bedrock in the two seconds before it starts to sweep.
fn mothership_crater(p: &mut Plan, floor_y: i32) {
    let t = MS_HIT;
    // 1. the blast, in two bands of height (a fill is capped at 32768 blocks)
    p.later(t - 0.1, move |p| {
        let by = p.by;
        for band in 0..2 {
            let y0 = by + 1 + band * 20;
            for c in p.disc(34, y0, y0 + 19, "minecraft:air", 0.12, None) {
                p.at(t + 0.1 + band as f32 * 0.1, c);
            }
        }
        for &(rad, block, rough, repl) in p.laser.scorch {
            for c in p.disc(rad, by - 3, by + 1, block, f64::from(rough), Some(repl)) {
                let dt = p.rng.next() as f32 * 1.6;
                p.at(t + 0.4 + dt, c);
            }
        }
    });
    // 2. the bowl, its walls fused as it goes
    p.later(t + 0.1, move |p| {
        let laser = p.laser;
        let by = p.by;
        let (bowl_r, bowl_d) = (laser.bowl_r, laser.bowl_d);
        for d in (0..bowl_d).step_by(2) {
            let r = ((f64::from(bowl_r) * (1.0 - f64::from(d) / (f64::from(bowl_d) + 0.5)).sqrt()) as i32).max(3);
            let tl = t + 0.3 + d as f32 * 0.09;
            p.dig(r, by - d - 1, by - d, tl, f64::from(laser.bowl_rough), 2);
            p.mottle(r, by - d - 1, by - d, tl, 12);
            let pitch = p.rng.uniform(0.55, 0.85);
            p.ground_sound(tl, "block.stone.break", 8.0, pitch);
        }
        let (fb, fr, fq) = laser.bowl_floor;
        for c in p.disc(bowl_r - 4, by - bowl_d, by - bowl_d + 1, fb, f64::from(fr), Some(fq)) {
            p.at(t + 1.8, c);
        }
    });
    // 3. the shaft, drilled to bedrock, and lava at the bottom
    p.later(t + 0.4, move |p| {
        let laser = p.laser;
        let (bx, by, bz) = (p.bx, p.by, p.bz);
        let mut y_hi = by - laser.bowl_d;
        let mut i = 0;
        while y_hi >= floor_y {
            let r = ((f64::from(laser.shaft_r) - f64::from(i) * 0.25).round() as i32).max(laser.shaft_min);
            let ts = t + 0.5 + i as f32 * 0.05;
            p.dig(r, (y_hi - 3).max(floor_y), y_hi, ts, f64::from(laser.shaft_rough), 1);
            p.mottle(r, (y_hi - 3).max(floor_y), y_hi, ts, 3);
            if i % 3 == 0 {
                let pitch = p.rng.uniform(0.5, 0.8);
                p.ground_sound(ts, if y_hi < 0 { "block.deepslate.break" } else { "block.stone.break" }, 7.0, pitch);
                p.at(ts, format!("particle minecraft:lava {} {y_hi} {} 2 1 2 0 12 force", f64::from(bx) + 0.5, f64::from(bz) + 0.5));
            }
            y_hi -= 4;
            i += 1;
        }
        for (k, &(rad, lo, hi, block)) in laser.bottom.iter().enumerate() {
            for c in p.disc(rad, floor_y + lo, floor_y + hi, block, 0.0, None) {
                p.at(t + 0.6 + i as f32 * 0.05 + 0.1 * k as f32, c);
            }
        }
    });
}

/// The stretch `d0..d1` blocks along the trench (from the target, along `axis`): each column of it cut the moment the
/// beam reaches it (`ms_when`). The land over it vaporised, a stepped cut 14 blocks wide and 17 deep fused into the
/// laser's lining, lava running along its floor, scorched ground and fires along its lips. The trench is laid out in
/// columns across whichever of x and z it runs along most, each column one /fill per step of its cut.
fn trench(p: &mut Plan, point: [f64; 3], axis: (f64, f64), d0: f64, d1: f64) {
    const NATURAL: [&str; 5] = ["#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand", "minecraft:gravel", "#minecraft:terracotta"];
    // (half-width, top, bottom) of each step of the cut, from the target's block down; the end shallows out
    const STEPS: [(f64, i32, i32); 3] = [(7.0, 0, -5), (5.0, -6, -11), (3.0, -12, -16)];
    let laser = p.laser;
    let by = p.by;
    let prim = laser.lining[0].0;
    let others = &laser.lining[1..];
    let along_x = axis.0.abs() >= axis.1.abs();
    // m: along the major axis, n: along the minor one
    let (m, n) = if along_x { axis } else { (axis.1, axis.0) };
    let (pm, pn) = if along_x { (point[0], point[2]) } else { (point[2], point[0]) };
    let fill = |c: i32, n0: i32, n1: i32, y0: i32, y1: i32, what: &str| {
        if along_x {
            format!("fill {c} {y0} {n0} {c} {y1} {n1} {what}")
        } else {
            format!("fill {n0} {y0} {c} {n1} {y1} {c} {what}")
        }
    };
    let (ma, mb) = (pm + m * d0, pm + m * d1);
    // the columns whose middles are in [d0, d1)
    let (c_lo, c_hi) = ((ma.min(mb) - 0.5).floor() as i32 - 1, (ma.max(mb) - 0.5).ceil() as i32 + 1);
    for c in c_lo..=c_hi {
        let d = (f64::from(c) + 0.5 - pm) / m;
        if d < d0 || d >= d1 {
            continue;
        }
        let t = ms_when(d / TRENCH_L);
        let nc = pn + n * d;
        // the cells across this column within `hw` of the trench's middle line
        let span = |hw: f64| {
            let e = hw / m.abs();
            ((nc - e - 0.5).ceil() as i32, (nc + e - 0.5).floor() as i32)
        };
        let steps = if d > 95.0 { 1 } else if d > 89.0 { 2 } else { 3 };
        let mut deepest = by;
        for &(hw, top, bottom) in &STEPS[..steps] {
            let (n0, n1) = span(hw);
            let (y0, y1) = (by + bottom, by + top);
            for tag in NATURAL {
                let what = format!("{prim} replace {tag}");
                p.at(t - 0.05, fill(c, n0 - 2, n0 - 1, y0 - 1, y1, &what));
                p.at(t - 0.05, fill(c, n1 + 1, n1 + 2, y0 - 1, y1, &what));
                p.at(t - 0.05, fill(c, n0 - 1, n1 + 1, y0 - 1, y0 - 1, &what));
            }
            p.at(t, fill(c, n0, n1, y0, y1, "minecraft:air"));
            deepest = y0;
        }
        // everything standing over it, trees and all
        let (n0, n1) = span(9.0);
        p.at(t, fill(c, n0, n1, by + 1, by + 30, "minecraft:air"));
        for _ in 0..2 {
            // patches of the other linings over the fused walls
            let &(hw, top, bottom) = p.rng.pick(&STEPS[..steps]);
            let (w0, w1) = span(hw);
            let side = if p.rng.next() < 0.5 { w0 - 1 } else { w1 + 1 };
            let y = p.rng.int(by + bottom - 1, by + top);
            let blk = p.rng.weighted(others).to_string();
            p.at(t + 0.05, fill(c, side, side, y - 1, y + 1, &format!("{blk} replace {prim}")));
        }
        let (s0, s1) = span(7.0);
        for &(_, block, _, repl) in laser.scorch {
            // the ground along its lips charred
            let what = format!("{block} replace {repl}");
            p.at(t + 0.3, fill(c, s0 - 12, s0 - 3, by - 3, by + 1, &what));
            p.at(t + 0.3, fill(c, s1 + 3, s1 + 12, by - 3, by + 1, &what));
        }
        if c.rem_euclid(5) == 0 {
            // molten rock pooling along the floor
            let mid = nc.floor() as i32;
            p.at(t + 0.6, fill(c, mid, mid, deepest, deepest, "minecraft:lava"));
        }
        if c.rem_euclid(3) == 0 {
            // fires catching along the lips
            let lip = if p.rng.next() < 0.5 { s0 - p.rng.int(2, 6) } else { s1 + p.rng.int(2, 6) };
            let dt = p.rng.uniform(0.2, 1.6) as f32;
            let (x, z) = if along_x { (c, lip) } else { (lip, c) };
            p.at(t + dt, surf(x, z, "setblock ~ ~ ~ minecraft:fire keep"));
        }
        if c.rem_euclid(4) == 0 {
            let mid = nc.floor() as i32;
            let (x, z) = if along_x { (c, mid) } else { (mid, c) };
            let pitch = p.rng.uniform(0.5, 0.8);
            p.at(t, format!("playsound minecraft:block.stone.break block @a {x} {by} {z} 3 {pitch:.2}"));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn block_costs() {
        assert_eq!(block_cost("fill 0 60 0 9 61 4 minecraft:air"), Some(100));
        assert_eq!(block_cost("fill 5 70 5 -4 69 0 minecraft:stone replace #minecraft:dirt"), Some(120));
        assert_eq!(block_cost(&surf(3, 4, "fill ~-2 ~-3 ~-2 ~2 ~-1 ~2 minecraft:blackstone replace #minecraft:dirt")), Some(75));
        assert_eq!(block_cost(&surf(3, 4, "setblock ~ ~ ~ minecraft:fire keep")), Some(1));
        assert_eq!(block_cost("playsound minecraft:entity.generic.explode block @a 0 64 0 3 1"), None);
        assert_eq!(block_cost(&surf(3, 4, "particle minecraft:explosion ~ ~1 ~ 1 1 1 0 4 force")), None);
        assert_eq!(block_cost("execute positioned 0 64 0 run kill @e[type=!minecraft:player,distance=..40]"), None);
    }
    #[test]
    fn sweep_turns_round() {
        for i in 0..=20 {
            let t = MS_SWEEP0 + (MS_SWEEP1 - MS_SWEEP0) * i as f32 / 20.0;
            assert!((ms_when(ms_sweep(t)) - t).abs() < 1e-3, "{t}");
        }
        assert_eq!(ms_sweep(MS_HIT), 0.0);
        assert_eq!(ms_sweep(MS_CUT), 1.0);
    }
    /// The whole plan, every stage worked out (as the mod does when each one is due).
    fn run_all(mut ev: Vec<(f32, Act)>) -> Vec<(f32, String)> {
        let mut out = Vec::new();
        while let Some((t, act)) = ev.pop() {
            match act {
                Act::Cmd(c) => out.push((t, c)),
                Act::Sound { .. } | Act::Shake { .. } => {}
                Act::Later(job) => ev.extend(job()),
            }
        }
        out
    }
    #[test]
    fn every_laser_shakes_the_camera() {
        // each laser jolts the real camera, within what render.shake takes; the mothership hardest as its beam lands
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        for laser in crate::lasers::LASERS {
            let mut ev = plan(laser, &target, false, "minecraft:overworld", 7.0, [10.5, 66.0, 60.0], 0);
            let mut jolts = Vec::new();
            while let Some((t, act)) = ev.pop() {
                match act {
                    Act::Shake { strength, seconds } => jolts.push((t, strength, seconds)),
                    Act::Later(job) => ev.extend(job()),
                    _ => {}
                }
            }
            assert!(!jolts.is_empty(), "{}", laser.key);
            for &(t, s, d) in &jolts {
                assert!(s > 0.0 && s <= 1.0 && (0.05..=30.0).contains(&d) && t < laser.length, "{}: {s} {d} at {t}", laser.key);
            }
            if laser.key == "mothership" {
                let hardest = jolts.iter().fold((0.0, 0.0), |a, j| if j.1 > a.1 { (j.0, j.1) } else { a });
                assert!(hardest.0 > MS_HIT && hardest.0 < MS_HIT + 0.5, "hardest at {}", hardest.0);
            }
        }
    }
    #[test]
    fn trench_away_from_player_every_approach() {
        // whichever way it comes in, from wherever the player stands, the trench runs away from them and never under
        // them, the beam's spot and the cut agree, and what is force-loaded fits in one forceload
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        for (i, ap) in APPROACHES.iter().enumerate() {
            for me in [[10.5, 66.0, 80.0], [-150.0, 70.0, -40.0], [200.0, 64.0, 190.0], [10.5, 66.0, -250.0]] {
                let cmds = run_all(plan(&crate::lasers::MOTHERSHIP, &target, true, "minecraft:overworld", 7.0, me, i));
                let axis = ms_axis(wing_angle(target.point, me));
                let mut columns = 0;
                for (t, c) in &cmds {
                    // the trench's clearing fills, one a column: `fill X 65 Z X 94 Z air` (or across)
                    let w: Vec<&str> = c.split_whitespace().collect();
                    if w.len() == 8 && w[0] == "fill" && w[2] == "65" && w[5] == "94" && w[7] == "minecraft:air" {
                        let n: Vec<f64> = [1, 3, 4, 6].iter().map(|&k| w[k].parse::<f64>().unwrap() + 0.5).collect();
                        let (cx, cz) = ((n[0] + n[2]) * 0.5, (n[1] + n[3]) * 0.5);
                        let along = (cx - target.point[0]) * axis.0 + (cz - target.point[2]) * axis.1;
                        assert!(along > -2.0 && along < TRENCH_L + 2.0, "{}: {c}", ap.key);
                        // the beam is there when the column is cut
                        let u = ms_sweep(*t) * TRENCH_L;
                        assert!((u - along).abs() < 2.5, "{}: beam at {u}, cut at {along}", ap.key);
                        let to_me = ((me[0] - cx).powi(2) + (me[2] - cz).powi(2)).sqrt();
                        assert!(to_me > 20.0, "{}: the trench runs under the player", ap.key);
                        columns += 1;
                    }
                }
                assert!(columns >= 70, "{}: {columns} columns", ap.key);
                let fl: Vec<&String> = cmds.iter().map(|(_, c)| c).filter(|c| c.starts_with("forceload add")).collect();
                assert_eq!(fl.len(), 1);
                let n: Vec<i32> = fl[0].split_whitespace().skip(2).map(|v| v.parse().unwrap()).collect();
                let chunks = ((n[2] >> 4) - (n[0] >> 4) + 1) * ((n[3] >> 4) - (n[1] >> 4) + 1);
                assert!(chunks <= 256, "{chunks} chunks");
                assert!(cmds.iter().any(|(t, c)| c.starts_with("forceload remove") && *t < crate::lasers::MOTHERSHIP.length));
            }
        }
    }
    #[test]
    fn trench_fills_fit() {
        // every column of the trench once, and no fill over the cap, whichever way it runs
        for wing in [0.0f32, 0.4, 1.2, 2.5, -2.0, -0.8] {
            let mut p = Plan { laser: &crate::lasers::MOTHERSHIP, ev: Vec::new(), rng: Rng::new(7), bx: 10, by: 64, bz: -3 };
            let axis = ms_axis(wing);
            let mut d0 = 0.0;
            while d0 < TRENCH_L {
                let d1 = (d0 + 8.0).min(TRENCH_L);
                trench(&mut p, [10.5, 64.0, -2.5], axis, d0, d1);
                d0 = d1;
            }
            let air: Vec<&String> = p
                .ev
                .iter()
                .filter_map(|(_, a)| match a {
                    Act::Cmd(c) if c.ends_with("minecraft:air") && c.contains(" 94 ") => Some(c),
                    _ => None,
                })
                .collect();
            // one column a block along whichever of x and z it runs along most, none twice
            let along = TRENCH_L * axis.0.abs().max(axis.1.abs());
            assert!((air.len() as f64 - along).abs() <= 2.0, "{wing}: {} columns", air.len());
            let mut seen: Vec<&String> = air.clone();
            seen.dedup();
            assert_eq!(seen.len(), air.len());
            for (_, a) in &p.ev {
                if let Act::Cmd(c) = a {
                    assert!(block_cost(c).unwrap_or(0) <= 32768, "{c}");
                }
            }
        }
    }
}
