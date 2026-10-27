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

/// Part of a plan, worked out when it is due (`Act::Later`).
pub type Stage = Box<dyn FnOnce() -> Vec<(f32, Act)>>;

pub enum Act {
    Cmd(String),
    /// A sound following the player (`at` none), or at a point, heard only nearby.
    Sound { event: String, at: Option<[f64; 3]>, volume: f32, pitch: f32 },
    /// A jolt of the real camera (`render.shake`): `strength` 0 to 1, fading out over `seconds`.
    Shake { strength: f32, seconds: f32 },
    /// Part of the plan worked out only when it is due: it returns more of the plan. A big strike's whole plan is too
    /// much work for the one tick it fires in (a mod's tick has a fuel limit).
    Later(Stage),
    /// A world change for when the block budget is to spare (after everything `Cmd` queued): what is still standing
    /// high over a blast, which takes long to clear and nothing waits on.
    Spare(String),
}

/// The blocks a command changes or visits, roughly, when it changes the world (`fill`, `setblock`, `summon`, through
/// any `execute ... run`); `None` for one that doesn't (sounds, particles, titles, kills), which runs on time.
pub fn block_cost(cmd: &str) -> Option<u64> {
    let run = cmd.rsplit(" run ").next().unwrap_or(cmd);
    let mut words = run.split_whitespace();
    match words.next()? {
        "fill" => {
            // x1 y1 z1 x2 y2 z2, absolute or ~-relative (both corners the same way)
            let w: Vec<&str> = words.take(6).collect();
            let n: Vec<i64> = w.iter().map(|w| w.trim_start_matches('~').parse::<i64>().unwrap_or(0)).collect();
            if n.len() < 6 {
                return Some(1);
            }
            // a span from the ground's own height (~) to a fixed one can't be known here: taken as the few blocks it is
            // over flat ground
            let span = |i: usize| if w[i].starts_with('~') != w[i + 3].starts_with('~') { 8 } else { (n[i + 3] - n[i]).unsigned_abs() + 1 };
            Some((0..3).map(span).product())
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
    /// Everything left standing over a blast of radius `r`, from `y0` up to the sky: a laser comes down from orbit,
    /// so no mountain is left hanging over its crater. On the spare block budget, in bands (a fill's cap).
    fn clear_above(&mut self, t: f32, r: i32, y0: i32, sky: i32, rough: f64) {
        let mut y = y0;
        while y <= sky {
            let top = (y + 19).min(sky);
            for c in self.disc(r, y, top, "minecraft:air", rough, None) {
                self.ev.push((t, Act::Spare(c)));
            }
            y = top + 1;
        }
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
    /// Like `dig`, but lining only the disc's wall (`edge_fills`) and in the commonest ground: for big craters, where
    /// the full lining would hold up everything queued behind it.
    fn dig_rim(&mut self, r: i32, y_lo: i32, y_hi: i32, t: f32, rough: f64) {
        let prim = self.laser.lining[0].0;
        let rs = self.rects(r, rough);
        for tag in ["#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand"] {
            for c in Self::edge_fills(&rs, y_lo - 1, y_hi, prim, tag, 2) {
                self.at(t - 0.05, c);
            }
        }
        for c in Self::fills(&rs, y_lo, y_hi, "minecraft:air", None, 0) {
            self.at(t, c);
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
    if laser.key == "downfall" {
        return downfall_plan(laser, target, terrain, dimension, shader_seed, me, approach);
    }
    if laser.key == "planetkiller" {
        return planetkiller_plan(laser, target, terrain, dimension, shader_seed, me);
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
        let (blast_r, sky) = (if blackhole { 52 } else { 44 }, sky_top(dimension));
        for c in p.disc(blast_r, by + 1, (by + 60).min(sky), "minecraft:air", 0.12, None) {
            p.at(t + 0.15, c);
        }
        p.clear_above(t + 0.15, blast_r, by + 61, sky, 0.12);
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
/// The highest block a strike clears up to: the build limit, under the Nether's bedrock roof.
fn sky_top(dimension: &str) -> i32 {
    match dimension {
        "minecraft:overworld" => 319,
        "minecraft:the_nether" => 122,
        _ => 255,
    }
}

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
        let (floor_y, sky, point) = (bedrock_top(dimension), sky_top(dimension), target.point);
        p.later(tb - 0.3, move |q| extinction(q, tb, floor_y, sky, point, shader_seed));
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
fn extinction(p: &mut Plan, tb: f32, floor_y: i32, sky: i32, point: [f64; 3], seed: f32) {
    // each stage is worked out just before it starts
    // 1. the blast (in bands of height: a fill is capped at 32768 blocks)
    p.later(tb + 0.0 - 0.15, move |p| {
        let by = p.by;
        for band in 0..4 {
            let y0 = by + 1 + band * 20;
            if y0 > sky {
                break;
            }
            for c in p.disc(100, y0, (y0 + 19).min(sky), "minecraft:air", 0.1, None) {
                p.at(tb + 0.1 + band as f32 * 0.1, c);
            }
        }
        p.clear_above(tb + 0.5, 100, by + 81, sky, 0.1);
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
/// The colours a ship laser's ship can be lit in (the shader's frame.mod_params[3].w, its SHIP_M), and each one's swatch.
pub const COLOURS: [Choice; 6] = [
    Choice { key: "green", label: "green", button: "GREEN" },
    Choice { key: "red", label: "red", button: "RED" },
    Choice { key: "amber", label: "amber", button: "AMBER" },
    Choice { key: "blue", label: "blue", button: "BLUE" },
    Choice { key: "violet", label: "violet", button: "VIOLET" },
    Choice { key: "white", label: "white", button: "WHITE" },
];
pub const COLOUR_RGB: [u32; 6] = [0x4CE06A, 0xE0402C, 0xF2A42A, 0x48A0F5, 0xB060F0, 0xE6EAF0];

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
        let (floor_y, sky) = (bedrock_top(dimension), sky_top(dimension));
        mothership_crater(&mut p, floor_y, sky);
        // the trench, a stretch at a time, each worked out just before the beam gets there
        let mut d0 = 0.0;
        while d0 < TRENCH_L {
            let d1 = (d0 + 8.0).min(TRENCH_L);
            p.later(ms_when(d0 / TRENCH_L) - 0.3, move |q| trench(q, point, axis, d0, d1, sky));
            d0 = d1;
        }
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// The crater where the beam first comes down: the land above it vaporised, the ground round it charred, a bowl, and a
/// shaft drilled to bedrock in the two seconds before it starts to sweep.
fn mothership_crater(p: &mut Plan, floor_y: i32, sky: i32) {
    let t = MS_HIT;
    // 1. the blast, in two bands of height (a fill is capped at 32768 blocks)
    p.later(t - 0.1, move |p| {
        let by = p.by;
        for band in 0..2 {
            let y0 = by + 1 + band * 20;
            if y0 > sky {
                break;
            }
            for c in p.disc(34, y0, (y0 + 19).min(sky), "minecraft:air", 0.12, None) {
                p.at(t + 0.1 + band as f32 * 0.1, c);
            }
        }
        p.clear_above(t + 0.3, 34, by + 41, sky, 0.12);
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
fn trench(p: &mut Plan, point: [f64; 3], axis: (f64, f64), d0: f64, d1: f64, sky: i32) {
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
        // everything standing over it up to the sky, trees, hills and all: the beam comes down through a mountain
        // in its way, so it cuts a slot through it, not a tunnel under it
        let (n0, n1) = span(9.0);
        p.at(t, fill(c, n0, n1, by + 1, sky, "minecraft:air"));
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

// ---- the downfall ----------------------------------------------------------------------------------------------------

/// Downfall: the mothership's last stand. Its times (strike clock) and the shape of its fall are strike.wgsl's DF_* and
/// df_* (keep them in step): where the ship is at every moment (`DfGeo::pose`), where its stern comes to rest (`reach`
/// downrange of the target, where its engine becomes the black hole), where the meteor's pieces strike it, the chunks
/// blown off it and where they land, and the blocks the black hole tears up.
const MS_EM_X: f64 = 70.0;
const DF_XP: f64 = -480.0; // the pivot: the stern's engine core, on its belly, along the hull from its middle
const DF_CUT: f32 = 6.8; // the charge is cut and its power diverted
const DF_TURN0: f32 = 7.2; // coming from ahead or overhead it comes about, broadside on
const DF_TURN1: f32 = 13.2;
const DF_FIRE0: f32 = 8.4; // the roof batteries fire, a volley every DF_PERIOD
const DF_FIRE1: f32 = 10.8;
const DF_PERIOD: f32 = 0.75;
const DF_SPLIT: f32 = 11.0; // the meteor breaks up DF_LS short of the ship, in sight; its pieces come on as fast
const DF_MV: f64 = 260.0;
const DF_LS: f64 = 1150.0;
const DF_ELEV: f64 = 0.3;
const DF_ROCK: f32 = 15.4; // the hits rock it
const DF_FALL0: f32 = 17.0; // it loses lift
const DF_FALL1: f32 = 30.0; // its stern strikes the ground
const DF_SLIDE: f32 = 2.6; // it ploughs on and its bow slams down
const DF_BOW: f64 = 0.65; // its bow strikes the ground this long after its stern
const DF_OPEN: f32 = 40.0; // its engine ruptures into a black hole
const DF_LIFE: f32 = 15.0; // which collapses this long after (once the last of the wreck is in)
const DF_SINK0: f64 = 28.0; // it ploughs in this deep (its stern's belly under the ground), then settles
const DF_SETTLE: f32 = 5.5; // over this long, slowly for its weight,
const DF_EMBED: f64 = 72.0; // to rest buried this deep: about half its height at the stern
const DF_THC: f64 = 0.19; // its pitch (stern down) as it strikes and at rest, and its roll
const DF_THS: f64 = 0.05;
const DF_THR: f64 = 0.03;
const DF_PHC: f64 = 0.12;
const DF_PHR: f64 = 0.035;
const DF_HOLE_H: f64 = 40.0; // the black hole hangs this high over where the stern rests
const DF_NEAR: f64 = 360.0; // the stern rests at least this far in front of the player
const DF_MIN: f64 = 40.0; // and at least this far downrange of the target
const DF_BETA: f64 = 0.111; // the share of its way it ploughs along the ground (so its speed carries on unbroken)
const DFD_N: usize = 96; // the blocks the black hole tears up
const DF_CHUNKS: usize = 10; // the chunks blown off the hull
const DF_G: f64 = 16.0;
/// The pieces it sheds as it falls (plates, girders, chunks, burning fragments): DF_SHED_PER at a time, every
/// DF_SHED_DT from DF_SHED_T0 (strike.wgsl's DF_SHED*).
const DF_SHED: usize = 48;
const DF_SHED_PER: usize = 6;
const DF_SHED_T0: f32 = 15.9;
const DF_SHED_DT: f32 = 1.6;
/// Where the meteor's pieces strike the hull (x along, y up, z across; z mirrored by the seed), all on its roof.
const DF_HITS: [[f64; 3]; 6] =
    [[-440.0, 150.0, 40.0], [-300.0, 150.0, -110.0], [-520.0, 150.0, -150.0], [-200.0, 150.0, 120.0], [-545.0, 150.0, 60.0], [-360.0, 150.0, 190.0]];

/// How far downrange of the target the stern comes to rest: far enough in front of the player that nothing of the
/// ship comes down on them (strike.wgsl's `frame.mod_params[3].z`).
pub fn df_reach(point: [f64; 3], me: [f64; 3]) -> f32 {
    let d = ((me[0] - point[0]).powi(2) + (me[2] - point[2]).powi(2)).sqrt();
    (DF_NEAR - d).max(DF_MIN) as f32
}

/// How far it has dropped `r` seconds after it loses lift, as a share of the way down, and how fast (a share a
/// second; strike.wgsl's df_drop): a lurch as the lift first gives, its engines fighting back a little, a second lurch,
/// then falling free, faster and faster, into the ground.
fn df_drop(r: f64) -> (f64, f64) {
    let j = |x: f64| { let x = x.clamp(0.0, 1.0); (x * x * (3.0 - 2.0 * x), 6.0 * x * (1.0 - x)) };
    let (a, da) = j(r / 0.7);
    let (b, db) = j((r - 3.2) / 0.6);
    let c = ((r - 0.7) / 2.5).clamp(0.0, 1.0);
    let dc = if c > 0.0 && c < 1.0 { 1.0 } else { 0.0 };
    let f = (r - 4.0).max(0.0) / 9.0;
    (0.07 * a + 0.05 * b - 0.012 * (PI * c).sin() + 0.88 * f * f,
     0.07 * da / 0.7 + 0.05 * db / 0.6 - 0.012 * PI / 2.5 * (PI * c).cos() * dc + 0.88 * 2.0 * f / 9.0)
}
/// Its pitch and roll `r` seconds after it loses lift, as shares of those it strikes the ground with (strike.wgsl's
/// df_lurch): jerked over at each lurch, wallowing, then tipping on over as it falls.
fn df_lurch(r: f64) -> (f64, f64) {
    let j = |x: f64| { let x = x.clamp(0.0, 1.0); x * x * (3.0 - 2.0 * x) };
    let free = j((r - 4.0) / 9.0);
    let wal = (1.0 - j((r - 9.0) / 4.0)) * j(r);
    (0.35 * j(r / 0.8) + 0.25 * j((r - 3.2) / 0.7) + 0.4 * free + 0.16 * (r * 1.9).sin() * wal,
     0.3 * j((r - 0.2) / 0.8) + 0.3 * j((r - 3.3) / 0.7) + 0.4 * free + 0.17 * (r * 2.3 + 1.0).sin() * wal)
}
fn smooth(a: f32, b: f32, t: f32) -> f64 {
    let s = f64::from(((t - a) / (b - a)).clamp(0.0, 1.0));
    s * s * (3.0 - 2.0 * s)
}

/// The hull's half-width at `x` along it (strike.wgsl's ms_half_w).
fn ms_half_w(x: f64) -> f64 {
    let sponson = 32.0 * (f64::from(u8::from((x + 150.0).abs() <= 70.0)) + f64::from(u8::from((x - 130.0).abs() <= 70.0)));
    (250.0 + sponson).min(250.0 - 180.0 * (x - 340.0) / 220.0)
}

/// The ship at a moment: its pivot and its axes in the world (along towards the bow, up out of its roof, across).
#[derive(Clone, Copy)]
struct DfPose {
    s: [f64; 3],
    a: [f64; 3],
    u: [f64; 3],
    d: [f64; 3],
}
impl DfPose {
    /// A point of the hull (x along from its middle, y up from its belly, z across) in the world.
    fn world(&self, l: [f64; 3]) -> [f64; 3] {
        let x = l[0] - DF_XP;
        [0, 1, 2].map(|k| self.s[k] + self.a[k] * x + self.u[k] * l[1] + self.d[k] * l[2])
    }
}

fn rot2(v: (f64, f64), a: f64) -> (f64, f64) {
    (v.0 * a.cos() - v.1 * a.sin(), v.0 * a.sin() + v.1 * a.cos())
}

/// Where everything of a downfall is, worked out from the strike: the target, the player's side (`wing`), which way
/// the ship came in (`mode`, APPROACHES), `reach` and the shader's seed.
#[derive(Clone, Copy)]
struct DfGeo {
    ax: (f64, f64),
    mode: usize,
    h0: (f64, f64),
    hf: (f64, f64),
    c: (f64, f64),
    y0: f64,
    by: f64,
    ps: (f64, f64),
    c0: (f64, f64),
    s1: (f64, f64),
    side: (f64, f64),
    roll: f64,
    mz: f64,
    seed: u32,
    /// Its belly's line (the height of its middle, and its rise along it) at each step of `sunk_by`, and at rest: worked
    /// out once, as `sunk_by` is asked of every column the stages build (each pose costs a mod's tick a lot of maths).
    sink: [(f64, f64); DF_SINK_N],
    rest: (f64, f64),
}
/// The steps of `sunk_by`: every 0.05 s from a second before the stern strikes until it is at rest.
const DF_SINK_N: usize = 184;
impl DfGeo {
    fn new(point: [f64; 3], by: i32, wing: f32, mode: usize, reach: f32, seed: f32) -> Self {
        let ax = ms_axis(wing);
        let right = (-ax.1, ax.0);
        let neg = |v: (f64, f64)| (-v.0, -v.1);
        // its heading as it arrives (strike.wgsl's mothership `base.ax`), and once it has come about
        let h0 = match mode {
            1 => ax,
            2 => right,
            3 => neg(right),
            _ => neg(ax),
        };
        let hf = if mode == 0 || mode >= 4 { right } else { h0 };
        let c = (point[0] - h0.0 * MS_EM_X, point[2] - h0.1 * MS_EM_X);
        let s1 = (c.0 + hf.0 * DF_XP, c.1 + hf.1 * DF_XP);
        let r = f64::from(reach);
        let ps = (point[0] + ax.0 * r, point[2] + ax.1 * r);
        let c0 = (ps.0 - (ps.0 - s1.0) * DF_BETA, ps.1 - (ps.1 - s1.1) * DF_BETA);
        let s = seed as u32;
        let sg = |k: u32| if mh(7, s, k) < 0.5 { 1.0 } else { -1.0 };
        let side = if mode == 1 { (right.0 * sg(1), right.1 * sg(1)) } else { neg(hf) };
        // it rolls its far side down (lifting the side over the player), or either way when it lies along their view
        let far = -hf.1 * ax.0 + hf.0 * ax.1;
        let roll = if far.abs() > 0.3 { far.signum() } else { sg(2) };
        let mut g = DfGeo {
            ax, mode, h0, hf, c, y0: point[1] + MS_H, by: f64::from(by), ps, c0, s1, side, roll, mz: sg(3), seed: s,
            sink: [(0.0, 0.0); DF_SINK_N], rest: (0.0, 0.0),
        };
        let line = |p: DfPose| (p.s[1] - p.a[1] * DF_XP, p.a[1]);
        g.rest = line(g.pose(DF_REST));
        let mut t = DF_FALL1 - 1.0;
        let mut k = 0;
        while t < DF_REST && k < DF_SINK_N {
            g.sink[k] = line(g.pose(t.min(DF_REST)));
            t += 0.05;
            k += 1;
        }
        g
    }
    fn heading(&self, t: f32) -> (f64, f64) {
        if self.mode == 0 || self.mode >= 4 { rot2(self.h0, -0.5 * PI * smooth(DF_TURN0, DF_TURN1, t)) } else { self.h0 }
    }
    /// The ship at `t` (from when it has stopped): hanging there, rocked by the hits, falling stern first and drifting
    /// downrange, ploughing on along the ground as its bow slams down, and at rest.
    fn pose(&self, t: f32) -> DfPose {
        let h = self.heading(t);
        let mut s = (self.c.0 + h.0 * DF_XP, self.c.1 + h.1 * DF_XP);
        let mut y = self.y0;
        let (mut th, mut ph) = (0.0, 0.0);
        if t > DF_ROCK {
            let r = f64::from(t - DF_ROCK);
            // (kicked over by the hits, rocking back)
            ph = 0.07 * (-r * 1.1).exp() * (r * 4.5).sin();
            th = 0.025 * (-r * 1.3).exp() * (r * 5.2).sin();
        }
        let yc = self.by + 6.0;
        let yr = self.by - DF_EMBED;
        if (DF_FALL0..DF_FALL1).contains(&t) {
            let u = f64::from((t - DF_FALL0) / (DF_FALL1 - DF_FALL0));
            let r = f64::from(t - DF_FALL0);
            let k = u.powf(1.25);
            s = (self.s1.0 + (self.c0.0 - self.s1.0) * k, self.s1.1 + (self.c0.1 - self.s1.1) * k);
            y = self.y0 - (self.y0 - yc) * df_drop(r).0;
            let (pt, rl) = df_lurch(r);
            th = DF_THC * pt;
            ph += DF_PHC * rl * self.roll;
        } else if t >= DF_FALL1 {
            // it ploughs on through the ground, its bow slamming down, then sinks on in, slowing, until it is buried
            let tau = f64::from(((t - DF_FALL1) / DF_SLIDE).min(1.0));
            let e = 1.0 - (1.0 - tau) * (1.0 - tau);
            let sig = f64::from(((t - DF_FALL1 - DF_SLIDE) / DF_SETTLE).clamp(0.0, 1.0));
            let f = 1.0 - (1.0 - sig).powi(3);
            let ys = self.by - DF_SINK0;
            s = (self.c0.0 + (self.ps.0 - self.c0.0) * e, self.c0.1 + (self.ps.1 - self.c0.1) * e);
            y = yc + (ys - yc) * e + (yr - ys) * f;
            // (its bow slams down well before it stops, rebounds, and the whole hull shudders with the blow)
            let b0 = f64::from(t - DF_FALL1);
            let tp = (b0 / DF_BOW).min(1.0);
            th = DF_THS + (DF_THC - DF_THS) * (1.0 - tp * tp) + (DF_THR - DF_THS) * f;
            ph += (DF_PHR + (DF_PHC - DF_PHR) * (1.0 - tp) * (1.0 - tp)) * self.roll;
            let bs = b0 - DF_BOW;
            if bs > 0.0 {
                th += 0.03 * (-bs * 2.8).exp() * (bs * 7.5).sin();
                ph += 0.02 * (-bs * 3.0).exp() * (bs * 8.0).sin() * self.roll;
            }
            y += 1.5 * (-b0 * 1.8).exp() * (b0 * 29.0).sin();
            th += 0.004 * (-b0 * 1.8).exp() * (b0 * 23.0).sin();
            let b = f64::from(t - DF_FALL1 - DF_SLIDE);
            if b > 0.0 {
                th += 0.012 * (-b * 2.5).exp() * (b * 7.0).sin();
            }
        }
        let (a3, s3) = ([h.0, 0.0, h.1], [-h.1, 0.0, h.0]);
        let (ct, st, cp, sp) = (th.cos(), th.sin(), ph.cos(), ph.sin());
        let a = [a3[0] * ct, st, a3[2] * ct];
        let u1 = [-a3[0] * st, ct, -a3[2] * st];
        let u = [0, 1, 2].map(|k| u1[k] * cp + s3[k] * sp);
        let d = [0, 1, 2].map(|k| s3[k] * cp - u1[k] * sp);
        DfPose { s: [s.0, y, s.1], a, u, d }
    }
    /// How fast its pivot is moving at `t` (falling; strike.wgsl's df_vel): its spin left out.
    fn vel(&self, t: f32) -> [f64; 3] {
        if !(DF_FALL0..DF_FALL1).contains(&t) {
            return [0.0; 3];
        }
        let tf = f64::from(DF_FALL1 - DF_FALL0);
        let u = f64::from((t - DF_FALL0) / (DF_FALL1 - DF_FALL0)).max(1e-6);
        let k = 1.25 * u.powf(0.25) / tf;
        [(self.c0.0 - self.s1.0) * k, -(self.y0 - self.by - 6.0) * df_drop(f64::from(t - DF_FALL0)).1, (self.c0.1 - self.s1.1) * k]
    }
    /// Piece `i` it sheds: where it comes away (its belly, a side, or the roof's edge, more of them towards the stern
    /// where it was hit), its speed (the ship's, and a kick away from it), when, what it is (0 a plate, 1 a girder, 2 a
    /// chunk, 3 a burning fragment) and how big.
    fn shed(&self, i: usize) -> ([f64; 3], [f64; 3], f32, usize, f64) {
        let (s, k) = (self.seed, i as u32);
        let h = |n: u32| mh(k, s, n);
        let te = DF_SHED_T0 + DF_SHED_DT * (i / DF_SHED_PER) as f32;
        let x = -560.0 + 1120.0 * h(41).powf(1.7);
        let hw = ms_half_w(x);
        let side = if h(43) < 0.5 { -1.0 } else { 1.0 };
        let (l, n) = if h(42) < 0.5 {
            ([x, 0.0, (h(43) - 0.5) * 2.0 * (hw - 10.0)], [0.0, -1.0, 0.0])
        } else if h(42) < 0.8 {
            ([x, 20.0 + 120.0 * h(44), side * (hw - 1.0)], [0.0, 0.0, side])
        } else {
            ([x, 150.0, side * (hw - 5.0)], [0.0, 0.6, side * 0.8])
        };
        let p = self.pose(te);
        let nw = [0, 1, 2].map(|c| p.a[c] * n[0] + p.u[c] * n[1] + p.d[c] * n[2]);
        let vh = self.vel(te);
        let kick = 6.0 + 14.0 * h(45);
        let v = [vh[0] + nw[0] * kick, vh[1] + nw[1] * kick + 4.0 * h(44), vh[2] + nw[2] * kick];
        (p.world(l), v, te, ((h(46) * 4.0) as usize).min(3), 0.6 + h(47))
    }
    /// Where a shed piece comes down on the ground (the target's level), when, and whether it is big enough to leave a
    /// crater (a chunk, or a big plate).
    fn shed_land(&self, i: usize) -> Option<(f64, f64, f32, bool)> {
        let (p, v, te, cls, size) = self.shed(i);
        let tau = (v[1] + (v[1] * v[1] + 2.0 * DF_G * (p[1] - self.by).max(0.0)).sqrt()) / DF_G;
        Some((p[0] + v[0] * tau, p[2] + v[2] * tau, te + tau as f32, cls == 2 || (cls == 0 && size > 1.1)))
    }
    /// The meteor: the point on the roof it comes down on, where it breaks up, and the way it is going.
    fn meteor(&self) -> ([f64; 3], [f64; 3], [f64; 3]) {
        // across the sky from one side, from ahead of the player (it comes towards them, so they see it coming); low and
        // from far enough off that it breaks up past the ship's end, in the open, not over the hull where it hides it
        let (a, b) = (self.side.0 - self.ax.0 * 0.2, self.side.1 - self.ax.1 * 0.2);
        let l = (a * a + b * b).sqrt();
        let v = [a / l * DF_ELEV.cos(), -DF_ELEV.sin(), b / l * DF_ELEV.cos()];
        // (aimed at where it hangs once it has come about)
        let aim = self.pose(DF_TURN1).world([-380.0, 150.0, 0.0]);
        (aim, [0, 1, 2].map(|k| aim[k] - v[k] * DF_LS), v)
    }
    /// Where piece `j` of it strikes the hull, and when.
    fn hit(&self, j: usize) -> ([f64; 3], f32) {
        let h = DF_HITS[j];
        let pt = self.pose(DF_TURN1).world([h[0], h[1], h[2] * self.mz]);
        let b = self.meteor().1;
        let d = ((pt[0] - b[0]).powi(2) + (pt[1] - b[1]).powi(2) + (pt[2] - b[2]).powi(2)).sqrt();
        (pt, DF_SPLIT + (d / DF_MV) as f32)
    }
    /// Chunk `i` blown off the edge of the roof: where it comes off, its speed, and when; none if it would be thrown
    /// back towards the player.
    fn chunk(&self, i: usize) -> Option<([f64; 3], [f64; 3], f32)> {
        let side = if i < DF_CHUNKS / 2 { 1.0 } else { -1.0 };
        let x = -500.0 + 80.0 * (i % (DF_CHUNKS / 2)) as f64;
        let tb = DF_ROCK + 0.2 + 1.8 * mh(i as u32, self.seed, 31) as f32;
        let p = self.pose(tb);
        let (nx, nz) = (p.d[0] * side, p.d[2] * side);
        let nl = (nx * nx + nz * nz).sqrt().max(1e-6);
        let (nx, nz) = (nx / nl, nz / nl);
        if nx * self.ax.0 + nz * self.ax.1 < -0.25 {
            return None;
        }
        let vh = 22.0 + 14.0 * mh(i as u32, self.seed, 32);
        let vy = 8.0 + 10.0 * mh(i as u32, self.seed, 33);
        Some((p.world([x, 150.0, side * (ms_half_w(x) - 2.0)]), [nx * vh, vy, nz * vh], tb))
    }
    /// Where a chunk comes down on the ground (the target's level), and when.
    fn chunk_land(&self, i: usize) -> Option<(f64, f64, f32)> {
        let (p, v, tb) = self.chunk(i)?;
        let tau = (v[1] + (v[1] * v[1] + 2.0 * DF_G * (p[1] - self.by)).sqrt()) / DF_G;
        Some((p[0] + v[0] * tau, p[2] + v[2] * tau, tb + tau as f32))
    }
    /// How far the belly at `x` along the hull has sunk into the ground at `t` (blocks under the top of the land; below
    /// 0 while it is still over it), and how far it will have once it is at rest (strike.wgsl's df_sunk).
    fn sunk(&self, x: f64, t: f32) -> (f64, f64) {
        let now = self.pose(t.min(DF_REST)).world([x, 0.0, 0.0])[1];
        let rest = self.pose(DF_REST).world([x, 0.0, 0.0])[1];
        (self.by - now, self.by - rest)
    }
    /// When the belly at `x` along the hull has gone `share` of the way down to where it comes to rest, into the ground:
    /// the ground it shoves aside heaps up beside it as it does, and nothing of that shows before the hull is there.
    fn sunk_by(&self, x: f64, share: f64) -> f32 {
        let rest = self.by - (self.rest.0 + self.rest.1 * x);
        let mut t = DF_FALL1 - 1.0;
        let mut k = 0;
        while t < DF_REST {
            let now = match self.sink.get(k) {
                Some(&(y, a)) => self.by - (y + a * x),
                None => self.sunk(x, t).0,
            };
            if now >= 0.0 && now >= share * rest {
                return t;
            }
            t += 0.05;
            k += 1;
        }
        DF_REST
    }
    /// Block `i` the black hole tears up: where (x, z), when (after DF_OPEN), whether it is a piece of the wreck lying
    /// there (or the ground), and whether it is a big one (2 x 2 x 2).
    fn torn(&self, i: usize) -> (i32, i32, f32, bool, bool) {
        let (s, k) = (self.seed, i as u32);
        let a = mh(k, s, 21) * 2.0 * PI;
        let r = 46.0 + 36.0 * mh(k, s, 22);
        let t = 0.5 + 7.0 * i as f32 / DFD_N as f32 + 0.3 * mh(k, s, 23) as f32;
        ((self.ps.0 + a.cos() * r).floor() as i32, (self.ps.1 + a.sin() * r).floor() as i32, t, mh(k, s, 24) < 0.4, mh(k, s, 25) > 0.7)
    }
    /// The top block of the ground at column (x, z) near where the stern rests, once it has been levelled and the
    /// gouges cut: the target's level, or a gouge's floor (its lining).
    fn ground(&self, x: i32, z: i32) -> i32 {
        let (px, pz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
        let by = self.by as i32;
        let mut top = by;
        let (a, b) = ((px - self.ps.0) * self.hf.0 + (pz - self.ps.1) * self.hf.1, (pz - self.ps.1) * self.hf.0 - (px - self.ps.0) * self.hf.1);
        if (-80.0..DF_REAL_A).contains(&a) {
            let (hw, depth) = df_slot(a);
            let j = df_step_depth(hw, depth, b);
            if j >= 0 {
                top = top.min(by - j - 1);
            }
        }
        let skid = (self.ps.0 - self.c0.0).hypot(self.ps.1 - self.c0.1);
        if skid > 2.0 {
            let dir = ((self.ps.0 - self.c0.0) / skid, (self.ps.1 - self.c0.1) / skid);
            let (a, b) = ((px - self.c0.0) * dir.0 + (pz - self.c0.1) * dir.1, (pz - self.c0.1) * dir.0 - (px - self.c0.0) * dir.1);
            if (0.0..skid).contains(&a) {
                let j = df_step_depth(DF_SKID_W, df_skid_depth(a / skid), b);
                if j >= 0 {
                    top = top.min(by - j - 1);
                }
            }
        }
        top
    }
}

/// The downfall: the mothership drops in and charges, diverts the power to its roof batteries as a meteor comes down on
/// it, breaks the meteor up, is hit by the pieces anyway, falls out of the sky and ploughs into the land; then its
/// black hole engine ruptures and swallows the wreck and the land round it, and collapses.
fn downfall_plan(laser: &'static Laser, target: &Target, terrain: bool, dimension: &str, shader_seed: f32, me: [f64; 3], approach: usize) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let point = target.point;
    let mode = approach.min(4);
    let g = DfGeo::new(point, by, wing_angle(point, me), mode, df_reach(point, me), shader_seed);
    let bar = |text: &str, color: &str| format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#);
    let dist = |q: [f64; 3]| ((q[0] - me[0]).powi(2) + (q[1] - me[1]).powi(2) + (q[2] - me[2]).powi(2)).sqrt();
    let late = |q: [f64; 3]| (dist(q) / 343.0) as f32;
    let fby = f64::from(by);
    // the mothership's own sounds for its arrival; and this laser's, heard from where they happen (in full within 16
    // blocks a unit of volume, from further off at the volume floor `min`)
    let ms = |p: &mut Plan, t: f32, name: &str, vol: f32| {
        p.ev.push((t, Act::Sound { event: format!("orbital:mothership.{name}"), at: None, volume: vol / 10.0, pitch: 1.0 }));
    };
    let here = |p: &mut Plan, t: f32, name: &str, q: [f64; 3], vol: f32, min: f64| {
        p.at(t, format!("playsound orbital:downfall.{name} block @a {:.1} {:.1} {:.1} {vol} 1 {min:.2}", q[0], q[1], q[2]));
    };

    // 1. it drops in exactly as the mothership does, and charges
    let mid = g.pose(5.0).world([0.0, 0.0, 0.0]);
    let ship = late(mid);
    p.at(MS_ARRIVE - 1.0, bar(&format!("MOTHERSHIP INBOUND {}", APPROACHES[mode].label.to_uppercase()), laser.color));
    ms(&mut p, MS_ARRIVE - 0.02, "arrival", 10.0);
    ms(&mut p, MS_ARRIVE + ship, "boom", 10.0);
    p.shake(MS_ARRIVE + 0.2, 0.35, 1.0);
    p.shake(MS_ARRIVE + ship, 0.85, 3.5);
    p.at(MS_ARRIVE + 0.6, bar("MOTHERSHIP OVERHEAD", "green"));
    p.csound(MS_ARRIVE + ship + 0.3, "hum", 8.0, 1.0);
    // 2. the charge, cut short: its power slammed over to the roof batteries as the meteor is seen
    p.csound(FIRE, "divert", 10.0, 1.0);
    p.shake(FIRE + 2.0, 0.15, 1.5);
    p.shake(DF_CUT + 0.05, 0.3, 1.4);
    p.at(DF_CUT + 0.1, bar("CHARGE ABORTED: POWER TO ROOF BATTERIES", "gold"));
    p.at(DF_CUT + 1.6, bar("METEOR INBOUND", "red"));
    // 3. the meteor coming in (its roar ends as it breaks up), the batteries firing on it, heard from up on the roof
    let (_, split_at, _) = g.meteor();
    p.csound(DF_SPLIT - 7.6, "approach", 10.0, 1.0);
    let mut tf = DF_FIRE0;
    let mut n = 0;
    while tf < DF_FIRE1 {
        for side in [-1.0, 1.0] {
            let q = g.pose(tf).world([-75.0 + 60.0 * side, 160.0, side * (ms_half_w(-75.0) - 3.0)]);
            here(&mut p, tf + late(q), &format!("battery{}", 1 + (n + usize::from(side > 0.0)) % 2), q, 8.0, 0.55);
        }
        p.shake(tf + ship, 0.08, 0.6);
        tf += DF_PERIOD;
        n += 1;
    }
    // it breaks up high over the ship, and the pieces strike it
    let heard = DF_SPLIT + late(split_at);
    p.csound(heard, "split", 10.0, 1.0);
    p.shake(heard, 0.45 * falloff(dist(split_at)).max(0.5), 3.0);
    p.at(DF_SPLIT + 0.2, bar("METEOR BROKEN UP: FRAGMENTS INBOUND", "red"));
    for j in 0..DF_HITS.len() {
        let (q, th) = g.hit(j);
        let tl = th + late(q);
        here(&mut p, tl, &format!("hit{}", 1 + j % 3), q, 10.0, 0.75);
        p.shake(tl, 0.55 * falloff(dist(q)).max(0.55), 2.2);
    }
    p.at(15.9, bar("HULL BREACHED", "dark_red"));
    // 4. it falls: the roar of it coming down all round, the ground shaking more and more as it nears
    p.at(DF_FALL0 + 0.4, bar("LIFT FAILING", "dark_red"));
    // (timed so its roar is cut just as the crash reaches the player)
    let c0 = [g.c0.0, fby, g.c0.1];
    p.csound(DF_FALL0 + late(c0), "fall", 10.0, 1.0);
    for k in 0..13 {
        let u = k as f32 / 12.0;
        p.shake(DF_FALL0 + 0.6 + k as f32, 0.1 + 0.32 * u * u, 1.6);
    }
    // (each lurch as its lift gives way)
    p.shake(DF_FALL0 + late(c0) * 0.5, 0.55, 1.4);
    p.shake(DF_FALL0 + 3.2 + late(c0) * 0.5, 0.5, 1.4);
    // the crash: its stern strikes, it ploughs on, its bow slams down (the hardest jolt of all, the loudest moment)
    let crash = DF_FALL1 + late(c0);
    // (a ship a kilometre long hitting the ground: felt hard however far off it is)
    let fo = (1.25 - dist(c0) / 2000.0).clamp(0.9, 1.0) as f32;
    p.csound(crash, "crash", 10.0, 1.0);
    p.shake(crash, fo, 7.0);
    p.shake(crash + 0.05, 0.95 * fo, 1.2);
    let bow = g.pose(DF_FALL1 + DF_BOW as f32).world([560.0, 0.0, 0.0]);
    let slam = DF_FALL1 + DF_BOW as f32 + late(bow);
    p.shake(slam, 0.9 * fo, 4.5);
    p.shake(crash + 4.0, 0.45 * fo, 4.0);
    p.shake(crash + 8.0, 0.25 * fo, 4.0);
    for k in 0..5 {
        // the ground rolling as it sinks on in, burying itself
        p.shake(crash + DF_SLIDE + 0.6 + k as f32 * 0.9, (0.32 - 0.04 * k as f32) * fo, 1.4);
    }
    p.at(DF_FALL1 + 0.2, bar("IMPACT", "white"));
    // 5. the engine groaning, rupturing into a black hole, the land pulled into it, and its collapse
    let hole = [g.ps.0, fby + DF_HOLE_H, g.ps.1];
    let lh = late(hole);
    let fh = falloff(dist(hole)).max(0.4);
    here(&mut p, 34.2 + lh, "groan1", hole, 8.0, 0.8);
    here(&mut p, 37.3 + lh, "groan2", hole, 8.0, 0.85);
    p.shake(34.6 + lh, 0.15 * fh, 2.5);
    p.shake(37.8 + lh, 0.22 * fh, 2.5);
    p.at(36.0, bar("ENGINE CONTAINMENT FAILING", "light_purple"));
    p.csound(DF_OPEN + lh, "rupture", 10.0, 1.0);
    p.shake(DF_OPEN + lh, 0.75 * fh, 4.0);
    p.at(DF_OPEN + 0.2, bar("SINGULARITY", "light_purple"));
    // (it is drawn to nothing the instant it collapses)
    p.csound(DF_OPEN + 0.4 + lh, "vortex", 9.0, 1.0);
    p.csound(DF_OPEN + 6.0 + lh, "vortex", 8.0, 0.9);
    for k in 1..14 {
        p.shake(DF_OPEN + lh + k as f32, 0.17 * fh, 1.3);
    }
    let te = DF_OPEN + DF_LIFE + lh;
    p.csound(te, "evaporate", 10.0, 1.0);
    p.shake(te, 0.65 * fh, 4.0);
    p.csound(te + 3.5, "after", 8.0, 1.0);

    // ---- particles in the world ----
    let (tx, ty, tz) = (point[0], point[1], point[2]);
    for i in 0..6 {
        // the ground under it stirring while it charges
        let tk = FIRE + 0.3 + i as f32 * 0.45;
        p.at(tk, format!("particle minecraft:white_ash {tx:.1} {:.1} {tz:.1} 9 1 9 0 70 force", ty + 1.0));
    }
    for j in 0..DF_HITS.len() {
        let (q, th) = g.hit(j);
        p.at(th, format!("particle minecraft:explosion_emitter {:.1} {:.1} {:.1} 6 4 6 0 3 force", q[0], q[1] + 4.0, q[2]));
    }
    for i in 0..DF_CHUNKS {
        if let Some((x, z, tl)) = g.chunk_land(i) {
            let (x, z) = (x.floor() as i32, z.floor() as i32);
            p.at(tl, surf(x, z, "particle minecraft:explosion_emitter ~ ~1 ~ 0 0 0 0 1 force"));
            p.at(tl, surf(x, z, "particle minecraft:campfire_signal_smoke ~ ~1 ~ 3 1 3 0.03 30 force"));
            p.at(tl + 0.05, surf(x, z, "kill @e[type=!minecraft:player,distance=..12]"));
            let d = ((f64::from(x) - me[0]).powi(2) + (f64::from(z) - me[2]).powi(2)).sqrt();
            let min = ((1.25 - d / 320.0).clamp(0.3, 1.0) * 0.8).max(0.2);
            let hit = if d > 90.0 { "hit_far2" } else { "hit2" };
            p.at(tl + (d / 343.0) as f32, surf(x, z, &format!("playsound orbital:meteor.{hit} block @a ~ ~ ~ 4 1 {min:.2}")));
        }
    }
    let rest = g.pose(DF_FALL1 + DF_SLIDE);
    for k in 0..8 {
        // the wreck burning, along it
        let q = rest.world([-480.0 + 140.0 * f64::from(k), 60.0, 0.0]);
        let tk = DF_FALL1 + DF_SLIDE * 0.3 * (1.0 + f64::from(k) / 7.0) as f32;
        p.at(tk, format!("particle minecraft:explosion_emitter {:.1} {:.1} {:.1} 30 6 30 0 6 force", q[0], fby + 4.0, q[2]));
        for i in 0..6 {
            p.at(tk + 1.0 + i as f32 * 1.2, format!("particle minecraft:campfire_signal_smoke {:.1} {:.1} {:.1} 40 4 40 0.04 40 force", q[0], fby + 6.0, q[2]));
        }
    }
    for i in 0..20 {
        // matter streaming into the hole
        let tk = DF_OPEN + 0.3 + i as f32 * 0.5;
        p.at(tk, format!("particle minecraft:portal {:.1} {:.1} {:.1} 0 0 0 18 220 force", hole[0], hole[1], hole[2]));
        p.at(tk, format!("particle minecraft:squid_ink {:.1} {:.1} {:.1} 30 1 30 0.06 60 force", hole[0], fby + 1.5, hole[2]));
    }
    let tc = DF_OPEN + DF_LIFE;
    p.at(tc, format!("particle minecraft:flash {:.1} {:.1} {:.1} 0 0 0 0 1 force", hole[0], hole[1], hole[2]));
    p.at(tc, format!("particle minecraft:explosion_emitter {:.1} {:.1} {:.1} 4 4 4 0 4 force", hole[0], hole[1], hole[2]));
    p.at(tc + 0.05, format!("particle minecraft:reverse_portal {:.1} {:.1} {:.1} 2 2 2 3 800 force", hole[0], hole[1], hole[2]));

    // ---- what dies: everything under it, and round where it comes down ----
    p.at(DF_FALL1 + 0.1, format!("execute positioned {:.1} {by} {:.1} run kill @e[type=!minecraft:player,distance=..130]", c0[0], c0[2]));
    for k in 0..8 {
        let q = rest.world([-480.0 + 140.0 * f64::from(k), 0.0, 0.0]);
        let tk = DF_FALL1 + DF_SLIDE * (0.5 + 0.07 * k as f32);
        p.at(tk, format!("execute positioned {:.1} {by} {:.1} run kill @e[type=!minecraft:player,distance=..270]", q[0], q[2]));
    }
    for tk in [0.2, 2.0, 5.0, 8.0, 11.2] {
        p.at(DF_OPEN + tk, format!("execute positioned {:.1} {by} {:.1} run kill @e[type=!minecraft:player,distance=..140]", hole[0], hole[2]));
    }

    if terrain {
        let (floor_y, sky) = (bedrock_top(dimension), sky_top(dimension));
        // a crash site out past what the game keeps loaded round the player stays loaded until it is done
        for [x0, z0, x1, z1] in df_forceload(&g, me) {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
            p.ev.push((laser.length - 0.2, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        // the chunks: each a crater where it lands, the chunk lying in it, burning
        for i in 0..DF_CHUNKS {
            if let Some((x, z, tl)) = g.chunk_land(i) {
                let (x, z) = (x.floor() as i32, z.floor() as i32);
                p.later(tl - 0.4, move |q| {
                    meteor_crater(q, x, z, 1, tl);
                    df_pile(q, x, z, tl + 0.25, 1);
                });
            }
        }
        // the crash: the stern's crater, the land round where it comes to rest levelled, and the gouge it ploughs
        p.later(DF_FALL1 - 0.3, move |q| df_impact(q, &g, sky));
        p.later(DF_FALL1 + 0.6, move |q| df_level(q, &g, sky));
        let skid = ((g.ps.0 - g.c0.0).powi(2) + (g.ps.1 - g.c0.1).powi(2)).sqrt();
        if skid > 2.0 {
            let dir = ((g.ps.0 - g.c0.0) / skid, (g.ps.1 - g.c0.1) / skid);
            let mut d0 = 0.0;
            while d0 < skid {
                let d1 = (d0 + 15.0).min(skid);
                let t0 = df_skid_t(d0 / skid);
                p.later(t0 - 0.3, move |q| df_cut(q, g.c0, dir, d0, d1, None, move |d| Some((DF_SKID_W, df_skid_depth(d / skid), df_skid_t(d / skid)))));
                d0 = d1;
            }
        }
        // it buries itself: the ground it displaced heaped up along its sides, spilling back against it, and (on the
        // spare budget, first the heaps you see, then the slot under its keel, then the hills it swallowed) the ground
        // it sank into carved out from under it
        // the heaps a stretch at a time, a tick apart: worked out all at once they are more than one tick's budget
        let mut a0 = -80.0;
        let mut i = 0;
        while a0 < DF_BERM_END {
            let a1 = (a0 + DF_BERM_STRETCH).min(DF_BERM_END);
            p.later(DF_FALL1 - 0.4 + i as f32 * 0.1, move |q| df_berms(q, &g, a0, a1));
            a0 = a1;
            i += 1;
        }
        p.later(DF_FALL1 + DF_SLIDE, move |q| df_spills(q, &g, 70));
        p.later(DF_FALL1 + DF_SLIDE + 0.1, move |q| df_spills(q, &g, 70));
        let mut x0 = -80.0;
        while x0 < DF_REAL_A {
            let x1 = (x0 + 16.0f64).min(DF_REAL_A);
            // (carved once the keel over it is down past it: under the hull, out of sight)
            let ts = g.sunk_by(x0 + DF_XP, 0.55).max(g.sunk_by(x1 + DF_XP, 0.55));
            p.later(DF_FALL1 - 0.35, move |q| df_cut(q, g.ps, g.hf, x0, x1, Some(ts), df_keel));
            x0 = x1;
        }
        // (in stretches along it, a stage each: each is a few thousand commands)
        let mut a0 = -80.0;
        while a0 < 1040.0 {
            let a1 = a0 + DF_CRUSH_STRETCH;
            p.later(DF_FALL1 - 0.3 + (a0 as f32 + 80.0) / 1000.0, move |q| df_swallowed(q, &g, a0, a1));
            a0 = a1;
        }
        // the pieces it shed as it fell, where they came down near the crash
        for i in 0..DF_SHED {
            if let Some((x, z, tl, big)) = g.shed_land(i)
                && big
                && (x - me[0]).hypot(z - me[2]) > 80.0
                && (x - g.ps.0).hypot(z - g.ps.1) < 700.0
            {
                let (x, z) = (x.floor() as i32, z.floor() as i32);
                p.later(tl - 0.4, move |q| {
                    meteor_crater(q, x, z, 0, tl);
                    df_pile(q, x, z, tl + 0.2, 1);
                });
            }
        }
        // the wreckage lying round it, some of it where the black hole will tear it up
        p.later(DF_FALL1 + DF_SLIDE + 0.2, move |q| df_wreck(q, &g));
        // the black hole: its crater and the land dragged into spiral arms round it, the blocks it tears up, the shaft
        // its collapse bores to bedrock
        p.later(DF_OPEN - 0.3, move |q| df_hole(q, &g, floor_y, 0));
        p.later(DF_OPEN + 0.2, move |q| df_hole(q, &g, floor_y, 1));
        p.later(DF_OPEN + 5.0, move |q| df_hole(q, &g, floor_y, 2));
        p.later(DF_OPEN + DF_LIFE - 0.3, move |q| df_hole(q, &g, floor_y, 3));
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// When the stern, ploughing along the ground, is `u` of the way from where it struck to where it rests.
fn df_skid_t(u: f64) -> f32 {
    DF_FALL1 + DF_SLIDE * (1.0 - (1.0 - u.clamp(0.0, 1.0)).sqrt()) as f32
}
/// The slot under the buried keel, `a` along from the stern's pivot: its half-width and depth (and its time, unused:
/// it is carved on the spare budget once the crash's own work is done, under the hull, and is only seen once the black
/// hole has taken the hull).
fn df_keel(a: f64) -> Option<(f64, i32, f32)> {
    let (hw, depth) = df_slot(a);
    Some((hw, depth, DF_FALL1))
}
/// The gouges' half-widths and depths (strike.wgsl's df_ground). The slot the buried keel sits in is carved for real
/// along the stern's DF_REAL_A blocks (the part of the wreck near the player; its bow is a kilometre off, past what can
/// be kept loaded), DF_SLOT deep: the keel itself sits deeper still, and the wide decks over it are buried in the ground
/// that closes round it.
const DF_KEEL_W: f64 = 70.0;
/// When it has come to rest, buried.
const DF_REST: f32 = DF_FALL1 + DF_SLIDE + DF_SETTLE;
const DF_SKID_W: f64 = 60.0;
const DF_REAL_A: f64 = 170.0;
/// The berms are worked out this many blocks along the hull a stage (`df_berms`), to stay within a tick's budget.
const DF_BERM_STRETCH: f64 = 30.0;
/// The heaps run along the whole hull, up to where its bow narrows to its point (along from the stern's pivot).
const DF_BERM_END: f64 = 990.0;
/// What the heaps shoved up beside the hull are made of.
const DF_BERM_BODY: [&str; 5] = ["minecraft:dirt", "minecraft:coarse_dirt", "minecraft:stone", "minecraft:gravel", "minecraft:dirt"];
const DF_SLOT: i32 = 32;
/// The buried keel's half-width `a` along from the stern's pivot: the engine block at the stern, then the keel ridge
/// (ms_tier's tier 0).
fn df_keel_hw(a: f64) -> f64 {
    if a < 50.0 { 170.0 } else { DF_KEEL_W }
}
/// The displaced ground heaped up beside the hull: its height `e` blocks out from the hull's edge, `x` along it from its
/// middle (strike.wgsl's df_berm_h): a big berm against it, a pressure ridge further out, both higher at the stern,
/// which went in deepest.
fn df_berm_h(x: f64, e: f64) -> f64 {
    if e < 0.0 {
        return 0.0;
    }
    (14.0 * (-((e - 14.0) / 13.0).powi(2)).exp() + 5.0 * (-((e - 52.0) / 6.0).powi(2)).exp()) * (1.0 - 0.35 * (x + 560.0) / 1120.0)
}
fn df_skid_depth(u: f64) -> i32 {
    // deeper as it ploughs on, its floor rising and falling
    (12.5 + 8.0 * u + 2.5 * (u * 19.0 + 1.0).sin() + 1.5 * (u * 41.0).sin()).floor() as i32
}
/// How far in its walls lean: they slope in this many blocks across for each one down (in steps of three layers).
const DF_SLOPE: f64 = 1.1;
/// The deepest layer a gouge `hw` wide and `depth` deep has dug `b` across from its middle, its walls sloping in (df_cut's
/// steps of three layers, each as wide as its lowest allows): -1 for none (strike.wgsl's df_step_depth).
fn df_step_depth(hw: f64, depth: i32, b: f64) -> i32 {
    let m = (hw - b.abs()) / DF_SLOPE;
    if f64::from(depth) <= m {
        return depth;
    }
    if m < 2.0 {
        return -1;
    }
    3 * ((m - 2.0) / 3.0).floor() as i32 + 2
}
/// The slot the buried keel lies in, `a` along from the stern's pivot: its half-width at the top and its depth (strike.wgsl's
/// df_slot). Wide round the engine block, narrowing to the keel's ridge, its edges wandering, and shallowing out and
/// closing at its far end rather than stopping square where the real ground stops being carved.
fn df_slot(a: f64) -> (f64, i32) {
    let s = |x: f64| {
        let x = x.clamp(0.0, 1.0);
        x * x * (3.0 - 2.0 * x)
    };
    let wide = s((62.0 - a) / 32.0);
    let wander = 0.94 + 0.04 * (a * 0.11 + 1.3).sin() + 0.02 * (a * 0.29).sin();
    let end = ((DF_REAL_A - a) / 55.0).clamp(0.0, 1.0).powf(0.8) * s((a + 80.0) / 55.0);
    let hw = ((70.0 + 60.0 * wide) * wander * (0.5 + 0.5 * end)).min(df_keel_hw(a));
    (hw, (f64::from(DF_SLOT) * end + 0.5).floor() as i32)
}

/// The ground it displaced, heaped up along both its sides (df_berm_h), on the spare budget ahead of anything else there
/// (it is seen: the slot under the hull is not, yet), each heap a stack of earth and stone on the ground, some capped
/// with rubble; and earth spilling back off their crests against the hull as it settles.
/// The earth the hull shoves aside, heaped along both its sides for the stretch `a0..a1` along it (the heaps are done
/// a stretch at a time, a stage each).
fn df_berms(p: &mut Plan, g: &DfGeo, a0: f64, a1: f64) {
    const CAP: [&str; 3] = ["minecraft:gravel", "minecraft:cobblestone", "minecraft:coarse_dirt"];
    let rest = g.pose(DF_REST);
    let mut a = a0;
    while a < a1 {
        for side in [-1.0, 1.0] {
            let mut e = 4.0;
            while e < 64.0 {
                // (each heap a little off the grid, its own size, as high as df_berm_h gives, give or take)
                let (ja, je) = (a + p.rng.uniform(-2.5, 2.5), e + p.rng.uniform(-2.5, 2.5));
                let x = ja + DF_XP;
                // (out from the hull's widest just round it: clear of a sponson's end)
                let hw = ms_half_w(x - 7.0).max(ms_half_w(x)).max(ms_half_w(x + 7.0));
                let q = rest.world([x, 0.0, side * (hw + je)]);
                let (cx, cz) = (q[0].floor() as i32, q[2].floor() as i32);
                let lump = 0.75 + 0.5 * vnoise(q[0], q[2], 18.0, g.seed ^ 0x77);
                // (dying away at either end of the hull, and reaching out further in places)
                let ends = ((ja + 80.0) / 40.0).clamp(0.0, 1.0).min(((DF_BERM_END - ja) / 40.0).clamp(0.0, 1.0));
                let reach = je < 40.0 + 24.0 * vnoise(q[0], q[2], 30.0, g.seed ^ 0x99);
                let h = (df_berm_h(x, je) * lump * ends * f64::from(u8::from(reach))).round() as i32;
                // built once the hull beside it has sunk most of the way in (the drawn ones rise with it until then)
                let ts = g.sunk_by(x, 0.6);
                if h >= 1 {
                    let blk = *p.rng.pick(&DF_BERM_BODY);
                    let r = p.rng.int(3, 5);
                    // (ahead of the crushing under the hull, which is out of sight: these are what is seen; and where it
                    // is water, heaped up from a few blocks down in it, not floating on it)
                    p.ev.push((ts, Act::Cmd(surf(cx, cz, &format!("fill ~-{r} ~-4 ~-{r} ~{} ~{} ~{} {blk} replace minecraft:water", r - 1, h - 1, r - 1)))));
                    p.ev.push((ts, Act::Cmd(surf(cx, cz, &format!("fill ~-{r} ~ ~-{r} ~{} ~{} ~{} {blk} keep", r - 1, h - 1, r - 1)))));
                    if h >= 3 && p.rng.next() < 0.45 {
                        let cap = *p.rng.pick(&CAP);
                        let c = p.rng.int(1, 2);
                        p.ev.push((ts, Act::Cmd(surf(cx, cz, &format!("fill ~-{c} ~ ~-{c} ~{c} ~{} ~{c} {cap} keep", p.rng.int(0, 1))))));
                    }
                }
                e += 6.0;
            }
        }
        a += 6.0;
    }
}

/// Earth spilling back off the heaps against the hull as it settles: `n` falling blocks (in two stages, for the budget).
fn df_spills(p: &mut Plan, g: &DfGeo, n: usize) {
    let rest = g.pose(DF_REST);
    let t0 = DF_FALL1 + DF_SLIDE;
    for _ in 0..n {
        let x = p.rng.uniform(-80.0, DF_BERM_END) + DF_XP;
        let side = if p.rng.next() < 0.5 { -1.0 } else { 1.0 };
        let e = 14.0 + p.rng.uniform(-4.0, 6.0);
        let q = rest.world([x, 0.0, side * (ms_half_w(x) + e)]);
        let (ix, iz) = (-rest.d[0] * side, -rest.d[2] * side);
        let sp = p.rng.uniform(0.15, 0.45);
        let blk = *p.rng.pick(&DF_BERM_BODY);
        let tl = (t0 + p.rng.uniform(0.6, DF_SETTLE as f64 + 1.5) as f32).max(g.sunk_by(x, 0.6) + 0.3);
        let y = g.by + df_berm_h(x, e) + 1.0;
        p.at(tl, format!("summon minecraft:falling_block {:.1} {y:.1} {:.1} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b,Motion:[{:.3}d,0.15d,{:.3}d]}}", q[0], q[2], ix * sp, iz * sp));
    }
}

/// How much of the hull's length (blocks) each stage of `df_swallowed` crushes.
const DF_CRUSH_STRETCH: f64 = 60.0;
/// Whatever stood on the land under the hull, from `a0` to `a1` along from the stern's pivot, crushed by it as it came
/// down there (on the spare budget, after the slot). In 8 by 8 cells, each cleared from 16 over its middle column's top
/// (trees, and the slope across it, so nothing is left standing in pillars) down into the ground: along the stern's slot
/// to the land's own level, rising gently towards the hull's edges and its far end, so what is left once the wreck has
/// gone is a shallow valley round the slot; further on scraped a few blocks down, here and there a crater, its edges
/// ragged. What is left is scorched and broken: coarse dirt, gravel and rubble, lumps of stone thrown about.
fn df_swallowed(p: &mut Plan, g: &DfGeo, a0: f64, a1: f64) {
    let rest = g.pose(DF_REST);
    let by = p.by;
    const GROUND: [&str; 6] = ["coarse_dirt", "gravel", "coarse_dirt", "rooted_dirt", "cobblestone", "tuff"];
    const RUBBLE: [&str; 5] = ["cobblestone", "blackstone", "basalt", "cobbled_deepslate", "gravel"];
    let mut a = a0;
    while a < a1.min(1040.0) {
        let x = a + DF_XP;
        let hw = ms_half_w(x) - 4.0;
        let ts = g.sunk_by(x - 4.0, 0.0).max(g.sunk_by(x + 4.0, 0.0)) + 0.1;
        let inner = df_slot(a).0 + 16.0;
        let mut z = -hw;
        while z <= hw {
            let q = rest.world([x, 0.0, z]);
            // (each cell a little off the grid and its own size, overlapping its neighbours: no square pattern)
            let (cx, cz) = ((q[0] + p.rng.uniform(-2.0, 2.0)).floor() as i32, (q[2] + p.rng.uniform(-2.0, 2.0)).floor() as i32);
            let r = p.rng.int(4, 5);
            // (its edges ragged: torn and shoved, not cut along a line)
            if z.abs() > hw - 14.0 * vnoise(q[0], q[2], 20.0, g.seed ^ 0x5d) {
                z += 8.0;
                continue;
            }
            let cell = |then: &str| Act::Spare(surf(cx, cz, then));
            let s1 = r - 1;
            p.ev.push((ts, cell(&format!("fill ~-{r} ~16 ~-{r} ~{s1} ~1 ~{s1} minecraft:air"))));
            let k = if a < DF_REAL_A {
                let lv = by + 1 + ((z.abs() - inner).max(0.0) * 0.28 + (a - 110.0).max(0.0) * 0.3 + 3.0 * vnoise(q[0], q[2], 24.0, g.seed ^ 0x31)).min(24.0) as i32;
                p.ev.push((ts, cell(&format!("fill ~-{r} ~ ~-{r} ~{s1} {lv} ~{s1} minecraft:air"))));
                0
            } else {
                // (scraped down by a depth that wanders smoothly across it, so neighbours lie at much the same depth and
                // the ground undulates; now and then a crater)
                let crater = p.rng.next() < 0.12;
                let k = 1 + (5.0 * vnoise(q[0], q[2], 40.0, g.seed ^ 0x6b)).round() as i32 + if crater { 3 + (4.0 * p.rng.next()) as i32 } else { 0 };
                p.ev.push((ts, cell(&format!("fill ~-{r} ~ ~-{r} ~{s1} ~-{k} ~{s1} minecraft:air"))));
                k
            };
            // scorched and broken where it lay: all of the cell's ground, whatever its height across it
            let ground = GROUND[(p.rng.next() * GROUND.len() as f64) as usize % GROUND.len()];
            let tl = ts + 0.5;
            p.ev.push((tl, cell(&format!("fill ~-{r} ~-{} ~-{r} ~{s1} ~-{} ~{s1} minecraft:{ground} replace #minecraft:dirt", k + 4, k.max(1)))));
            if p.rng.next() < 0.35 {
                let rb = RUBBLE[(p.rng.next() * RUBBLE.len() as f64) as usize % RUBBLE.len()];
                let (dx, dz) = ((p.rng.next() * 6.0) as i32 - 3, (p.rng.next() * 6.0) as i32 - 3);
                let hgt = (p.rng.next() * 2.0) as i32;
                p.ev.push((tl, cell(&format!("fill ~{dx} ~ ~{dz} ~{} ~{hgt} ~{} minecraft:{rb}", dx + 1, dz + (p.rng.next() * 2.0) as i32))));
            }
            z += 8.0;
        }
        a += 8.0;
    }
}

/// The chunks of the world a downfall changes that may be out past what the game keeps loaded round the player: where
/// the stern strikes and ploughs, the gouge, the black hole's reach, and where the chunks come down. As rectangles of
/// chunks, one per row (`forceload add` takes 256 chunks at most).
fn df_forceload(g: &DfGeo, me: [f64; 3]) -> Vec<[i32; 4]> {
    let mut set = std::collections::BTreeSet::new();
    // the stern's section of the hull, with its heaps either side: a strip along it
    let hw = 282.0 + 64.0;
    let (ca, cb) = ((DF_REAL_A - 80.0) / 2.0, (DF_REAL_A + 80.0) / 2.0);
    let mid = (g.ps.0 + g.hf.0 * ca, g.ps.1 + g.hf.1 * ca);
    let reach = cb.hypot(hw);
    for cz in ((mid.1 - reach) / 16.0).floor() as i32..=((mid.1 + reach) / 16.0).floor() as i32 {
        for cx in ((mid.0 - reach) / 16.0).floor() as i32..=((mid.0 + reach) / 16.0).floor() as i32 {
            let (mx, mz) = (f64::from(cx) * 16.0 + 8.0 - mid.0, f64::from(cz) * 16.0 + 8.0 - mid.1);
            let (a, b) = (mx * g.hf.0 + mz * g.hf.1, mz * g.hf.0 - mx * g.hf.1);
            if a.abs() <= cb + 12.0 && b.abs() <= hw + 12.0 && (mx + mid.0 - me[0]).hypot(mz + mid.1 - me[2]) > 150.0 {
                set.insert((cz, cx));
            }
        }
    }
    let mut add = |x: f64, z: f64, r: f64| {
        for cz in ((z - r) / 16.0).floor() as i32..=((z + r) / 16.0).floor() as i32 {
            for cx in ((x - r) / 16.0).floor() as i32..=((x + r) / 16.0).floor() as i32 {
                let (mx, mz) = (f64::from(cx) * 16.0 + 8.0, f64::from(cz) * 16.0 + 8.0);
                if (mx - x).hypot(mz - z) <= r + 12.0 && (mx - me[0]).hypot(mz - me[2]) > 150.0 {
                    set.insert((cz, cx));
                }
            }
        }
    };
    add(g.ps.0, g.ps.1, 150.0);
    add(g.c0.0, g.c0.1, 55.0);
    for i in 0..DF_SHED {
        if let Some((x, z, _, true)) = g.shed_land(i)
            && (x - me[0]).hypot(z - me[2]) > 80.0
            && (x - g.ps.0).hypot(z - g.ps.1) < 700.0
        {
            add(x, z, 6.0);
        }
    }
    for i in 0..DF_CHUNKS {
        if let Some((x, z, _)) = g.chunk_land(i) {
            add(x, z, 12.0);
        }
    }
    let mut out: Vec<[i32; 4]> = Vec::new();
    for (cz, cx) in set {
        match out.last_mut() {
            Some(r) if r[1] == cz * 16 && r[2] == cx * 16 - 1 => r[2] = cx * 16 + 15,
            _ => out.push([cx * 16, cz * 16, cx * 16 + 15, cz * 16 + 15]),
        }
    }
    out
}

/// A heap of the wreck lying on the ground at column (x, z): dark metal, a few of its green lights still glowing in it.
fn df_pile(p: &mut Plan, x: i32, z: i32, t: f32, s: i32) {
    const WRECK: [&str; 5] = ["minecraft:polished_blackstone", "minecraft:blackstone", "minecraft:polished_deepslate", "minecraft:deepslate_tiles", "minecraft:obsidian"];
    let a = *p.rng.pick(&WRECK);
    let b = *p.rng.pick(&WRECK);
    p.at(t, surf(x, z, &format!("fill ~-{s} ~ ~-{s} ~{s} ~{} ~{s} {a} keep", s.max(1))));
    p.at(t, surf(x, z, &format!("fill ~-{s} ~ ~ ~{s} ~ ~ {b}")));
    if p.rng.next() < 0.6 {
        let lit = *p.rng.pick(&["minecraft:verdant_froglight", "minecraft:green_stained_glass", "minecraft:tinted_glass"]);
        p.at(t + 0.05, surf(x, z, &format!("setblock ~ ~ ~ {lit}")));
    }
    if p.rng.next() < 0.5 {
        p.at(t + 0.4, surf(x + s + 1, z, "setblock ~ ~ ~ minecraft:fire keep"));
    }
}

/// Where the stern strikes: everything over the ground round it blasted away, a crater, its walls fused.
fn df_impact(p: &mut Plan, g: &DfGeo, sky: i32) {
    let t = DF_FALL1;
    (p.bx, p.bz) = (g.c0.0.floor() as i32, g.c0.1.floor() as i32);
    let by = p.by;
    for c in p.disc(48, by + 1, by + 20, "minecraft:air", 0.12, None) {
        p.at(t + 0.1, c);
    }
    p.clear_above(t + 0.2, 48, by + 21, sky, 0.12);
    for d in (0..12).step_by(2) {
        let r = ((36.0 * (1.0 - f64::from(d) / 12.5).sqrt()) as i32).max(4);
        let tl = t + 0.15 + d as f32 * 0.05;
        p.dig_rim(r, by - d - 1, by - d, tl, 0.1);
        p.mottle(r, by - d - 1, by - d, tl, 10);
    }
    for _ in 0..30 {
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = p.rng.uniform(38.0, 70.0);
        let dt = p.rng.uniform(0.5, 3.0) as f32;
        p.at(t + dt, surf(p.bx + (a.cos() * rr) as i32, p.bz + (a.sin() * rr) as i32, "setblock ~ ~ ~ minecraft:fire keep"));
    }
}

/// Round where the stern comes to rest the land is flattened to the target's level (the ground the black hole later
/// tears its blocks from), and charred.
fn df_level(p: &mut Plan, g: &DfGeo, sky: i32) {
    let t = DF_FALL1 + DF_SLIDE * 0.6;
    (p.bx, p.bz) = (g.ps.0.floor() as i32, g.ps.1.floor() as i32);
    let by = p.by;
    for c in p.disc(88, by + 1, by + 15, "minecraft:air", 0.1, None) {
        p.at(t, c);
    }
    p.clear_above(t + 0.5, 88, by + 16, sky, 0.1);
    for (rad, block, repl) in [(96, "minecraft:coarse_dirt", "minecraft:grass_block"), (92, "minecraft:blackstone", "minecraft:dirt"), (90, "minecraft:smooth_basalt", "minecraft:sand")] {
        for c in p.disc(rad, by - 2, by, block, 0.12, Some(repl)) {
            let dt = p.rng.next() as f32 * 1.5;
            p.at(t + 0.6 + dt, c);
        }
    }
}

/// The stretch `d0..d1` blocks of a gouge from `from` along `dir` (unit, xz), each column cut when `prof(d)` says, as
/// wide and as deep as it says: its walls and floor fused into the lining, a little molten rock and fire, whatever
/// stood over it cleared to the sky (down from its own top, on the spare budget). Laid out in columns across whichever
/// of x and z it runs along most.
fn df_cut(p: &mut Plan, from: (f64, f64), dir: (f64, f64), d0: f64, d1: f64, spare: Option<f32>, prof: impl Fn(f64) -> Option<(f64, i32, f32)>) {
    let by = p.by;
    let along_x = dir.0.abs() >= dir.1.abs();
    let (m, n) = if along_x { dir } else { (dir.1, dir.0) };
    let (pm, pn) = if along_x { from } else { (from.1, from.0) };
    let fill = |c: i32, n0: i32, n1: i32, y0: i32, y1: i32, what: &str| {
        if along_x { format!("fill {c} {y0} {n0} {c} {y1} {n1} {what}") } else { format!("fill {n0} {y0} {c} {n1} {y1} {c} {what}") }
    };
    let (ma, mb) = (pm + m * d0, pm + m * d1);
    let (c_lo, c_hi) = ((ma.min(mb) - 0.5).floor() as i32 - 1, (ma.max(mb) - 0.5).ceil() as i32 + 1);
    // on the spare budget: everything queued at `spare`, in order, and only the cut itself (no fires or sounds)
    let at = |p: &mut Plan, t: f32, c: String| match spare {
        Some(ts) => p.ev.push((ts, Act::Spare(c))),
        None => p.at(t, c),
    };
    for c in c_lo..=c_hi {
        let d = (f64::from(c) + 0.5 - pm) / m;
        if d < d0 || d >= d1 {
            continue;
        }
        let Some((hw, depth, t)) = prof(d) else { continue };
        let nc = pn + n * d;
        // its walls sloping in, in steps of three layers (df_step_depth)
        let mut k0 = 0;
        while k0 <= depth {
            let j1 = (k0 + 2).min(depth);
            let w = hw - f64::from(j1) * DF_SLOPE;
            if w < 0.5 {
                break;
            }
            let e = w / m.abs();
            let (n0, n1) = ((nc - e - 0.5).ceil() as i32, (nc + e - 0.5).floor() as i32);
            at(p, t, fill(c, n0, n1, by - j1, by - k0, "minecraft:air"));
            k0 += 3;
        }
        let e = hw / m.abs();
        let (n0, n1) = ((nc - e - 0.5).ceil() as i32, (nc + e - 0.5).floor() as i32);
        let y0 = by - depth;
        if spare.is_some() {
            continue;
        }
        // whatever stands over it, down from its own top, in pieces (a fill's cap), on the spare budget
        let mut a = n0;
        while a <= n1 {
            let b = (a + 31).min(n1);
            let mid = (a + b) / 2;
            let (x, z) = if along_x { (c, mid) } else { (mid, c) };
            let rel = if along_x {
                format!("fill ~ ~30 ~{} ~ {} ~{} minecraft:air", a - mid, by + 1, b - mid)
            } else {
                format!("fill ~{} ~30 ~ ~{} {} ~ minecraft:air", a - mid, b - mid, by + 1)
            };
            p.ev.push((t + 0.1, Act::Spare(surf(x, z, &rel))));
            a = b + 1;
        }
        // its lips charred, molten rock left along its floor, fires catching
        for (block, repl) in [("minecraft:coarse_dirt", "minecraft:grass_block"), ("minecraft:blackstone", "minecraft:dirt")] {
            let what = format!("{block} replace {repl}");
            p.at(t + 0.4, fill(c, n0 - 10, n0 - 3, by - 3, by + 1, &what));
            p.at(t + 0.4, fill(c, n1 + 3, n1 + 10, by - 3, by + 1, &what));
        }
        let mid = nc.floor() as i32;
        if c.rem_euclid(7) == 0 {
            let w = p.rng.int(-((hw * 0.6) as i32), (hw * 0.6) as i32);
            p.at(t + 0.5, fill(c, mid + w - 1, mid + w + 1, y0, y0, "minecraft:magma_block"));
        }
        if c.rem_euclid(11) == 0 {
            p.at(t + 0.6, fill(c, mid, mid, y0, y0, "minecraft:lava"));
        }
        if c.rem_euclid(4) == 0 {
            let lip = if p.rng.next() < 0.5 { n0 - p.rng.int(2, 8) } else { n1 + p.rng.int(2, 8) };
            let (x, z) = if along_x { (c, lip) } else { (lip, c) };
            let dt = p.rng.uniform(0.3, 2.0) as f32;
            p.at(t + dt, surf(x, z, "setblock ~ ~ ~ minecraft:fire keep"));
        }
        if c.rem_euclid(9) == 0 {
            let (x, z) = if along_x { (c, mid) } else { (mid, c) };
            let pitch = p.rng.uniform(0.5, 0.75);
            p.at(t, format!("playsound minecraft:block.stone.break block @a {x} {by} {z} 4 {pitch:.2}"));
        }
    }
}

/// The wreck strewn round it: heaps along the gouge's lips, and the pieces lying where the black hole will tear them
/// up (DfGeo::torn).
fn df_wreck(p: &mut Plan, g: &DfGeo) {
    let t = DF_FALL1 + DF_SLIDE + 0.3;
    const WRECK: [&str; 4] = ["minecraft:polished_blackstone", "minecraft:polished_deepslate", "minecraft:obsidian", "minecraft:deepslate_tiles"];
    for i in 0..DFD_N {
        let (x, z, _, wreck, big) = g.torn(i);
        if wreck {
            let blk = *p.rng.pick(&WRECK);
            let y = g.ground(x, z) + 1;
            if big {
                p.at(t + 0.2, format!("fill {} {y} {} {x} {} {z} {blk}", x - 1, z - 1, y + 1));
            } else {
                p.at(t + 0.2, format!("setblock {x} {y} {z} {blk}"));
            }
        }
    }
    let rest = g.pose(DF_FALL1 + DF_SLIDE);
    for k in 0..28 {
        let x = p.rng.uniform(-560.0, -100.0);
        let z = p.rng.uniform(78.0, 115.0) * if k % 2 == 0 { 1.0 } else { -1.0 };
        let q = rest.world([x, 0.0, z]);
        if (q[0] - g.ps.0).hypot(q[2] - g.ps.1) < 100.0 {
            continue;
        }
        let s = *p.rng.pick(&[1, 1, 2]);
        let dt = p.rng.uniform(0.0, 0.8) as f32;
        df_pile(p, q[0].floor() as i32, q[2].floor() as i32, t + dt, s);
    }
}

/// The black hole: the blocks it tears up (as strike.wgsl flies them in), its crater, the land dragged into spiral arms
/// round it, the ground charred, and the shaft its collapse bores to bedrock, lined; what it had not swallowed thrown
/// out over the land.
/// In four stages, each worked out just before it starts: 0 the torn blocks and the crater, 1 the spiral arms, 2 the
/// charring, 3 the collapse.
fn df_hole(p: &mut Plan, g: &DfGeo, floor_y: i32, stage: u8) {
    let t = DF_OPEN;
    (p.bx, p.bz) = (g.ps.0.floor() as i32, g.ps.1.floor() as i32);
    let (bx, bz) = (p.bx, p.bz);
    if stage == 0 {
        df_hole_tear(p, g);
    }
    if stage == 1 {
        df_hole_arms(p, bx, bz);
    }
    if stage == 2 {
        // once everything it tears up round it has gone: its crater opened out to its full size, swallowing the end of
        // the slot the wreck lay in, then rubble thrown back into it, and the whole site scarred
        df_crater(p, f64::INFINITY, t + 8.3, 2.4);
        df_rubble(p, g, t + 10.7);
        df_scar(p, g, t + 10.9);
    }
    if stage == 3 {
        df_hole_collapse(p, g, floor_y, DF_CRATER_D);
    }
}
/// The black hole's crater: a bowl DF_CRATER_R across and DF_CRATER_D deep at its middle, falling away steeper towards
/// it (depth D (1 - (r/R)^1.6)), dug in layers of three, each a ragged disc, so its sides come down in uneven terraces.
/// Only out to `r_cap` (what of it can be dug before the blocks the hole tears up round it have gone), from `t0` over `dt`.
const DF_CRATER_R: f64 = 115.0;
const DF_CRATER_D: i32 = 56;
fn df_crater(p: &mut Plan, r_cap: f64, t0: f32, dt: f32) {
    let by = p.by;
    let mut d = 0;
    while d < DF_CRATER_D {
        let r = (DF_CRATER_R * (1.0 - f64::from(d) / f64::from(DF_CRATER_D)).powf(1.0 / 1.6)).min(r_cap);
        if r >= 3.0 {
            let tl = t0 + dt * d as f32 / DF_CRATER_D as f32;
            let rs = p.rects(r as i32, 0.14);
            for c in Plan::fills(&rs, by - d - 2, by - d, "minecraft:air", None, 0) {
                p.at(tl, c);
            }
        }
        d += 3;
    }
}
fn df_hole_tear(p: &mut Plan, g: &DfGeo) {
    let t = DF_OPEN;
    let by = p.by;
    for i in 0..DFD_N {
        let (x, z, tr, wreck, big) = g.torn(i);
        let tl = t + tr;
        // a piece of the wreck lying on the ground, or the ground itself
        let gy = g.ground(x, z);
        let y = if wreck { gy + 1 } else { gy - i32::from(big) };
        if big {
            p.at(tl, format!("fill {} {y} {} {x} {} {z} minecraft:air", x - 1, z - 1, y + 1));
        } else {
            p.at(tl, format!("setblock {x} {y} {z} minecraft:air"));
        }
        if i % 6 == 0 {
            p.at(tl, format!(r#"particle minecraft:block{{block_state:"minecraft:blackstone"}} {x} {} {z} 0.8 0.3 0.8 0.3 20 force"#, by + 1));
        }
    }
    // the heart of its crater, inside the ring of what it tears up
    df_crater(p, 44.0, t + 0.4, 2.0);
}
/// The land dragged round into spiral arms, from the outside in.
fn df_hole_arms(p: &mut Plan, bx: i32, bz: i32) {
    let t = DF_OPEN;
    const ARMS: [&str; 5] = ["minecraft:blackstone", "minecraft:basalt", "minecraft:sculk", "minecraft:smooth_basalt", "minecraft:crying_obsidian"];
    const LIP: [&str; 4] = ["minecraft:gravel", "minecraft:coarse_dirt", "minecraft:cobblestone", "minecraft:blackstone"];
    let a0 = p.rng.uniform(0.0, 2.0 * PI);
    for arm in 0..4 {
        let mut last = (i32::MIN, i32::MIN);
        for i in 0..150 {
            let u = f64::from(i) / 149.0;
            let rr = 86.0 + 64.0 * u;
            let a = a0 + f64::from(arm) * PI / 2.0 + (rr / 86.0).ln() * 2.6 + p.rng.uniform(-0.03, 0.03);
            let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
            if (x, z) == last {
                continue;
            }
            last = (x, z);
            let blk = *p.rng.pick(&ARMS);
            let tl = t + 0.6 + (1.0 - u) as f32 * 5.0;
            // the land dragged round into the hole: a furrow ploughed along the arm, deeper further in, its floor
            // scorched, the ground it shoved out heaped along its outer side
            let deep = if u < 0.7 { 3 } else { 2 };
            p.at(tl, surf(x, z, &format!("fill ~-1 ~-{deep} ~-1 ~1 ~-1 ~1 minecraft:air")));
            for tag in ["#minecraft:dirt", "#minecraft:base_stone_overworld"] {
                p.at(tl + 0.05, surf(x, z, &format!("fill ~-1 ~-1 ~-1 ~1 ~-1 ~1 {blk} replace {tag}")));
            }
            if i % 2 == 0 {
                let (ox, oz) = (bx + (a.cos() * (rr + 3.0)).round() as i32, bz + (a.sin() * (rr + 3.0)).round() as i32);
                let lip = *p.rng.pick(&LIP);
                p.at(tl + 0.1, surf(ox, oz, &format!("fill ~-1 ~ ~-1 ~1 ~{} ~1 {lip} keep", i32::from(u < 0.5))));
            }
        }
    }
}
/// Rubble: the ground and the wreck the hole threw back as it collapsed, in heaps on the crater's terraces and floor and
/// along the slot's floor and the foot of its walls; and a lip of earth and rock heaped round the crater's rim.
fn df_rubble(p: &mut Plan, g: &DfGeo, t: f32) {
    const RUBBLE: [&str; 6] = ["minecraft:gravel", "minecraft:cobblestone", "minecraft:coarse_dirt", "minecraft:blackstone", "minecraft:cobbled_deepslate", "minecraft:tuff"];
    const WRECK: [&str; 3] = ["minecraft:polished_blackstone", "minecraft:deepslate_tiles", "minecraft:obsidian"];
    let heap = |p: &mut Plan, x: f64, z: f64, s: i32, h: i32, dt: f32| {
        let (x, z) = (x.floor() as i32, z.floor() as i32);
        let a = *p.rng.pick(&RUBBLE);
        let b = if p.rng.next() < 0.25 { *p.rng.pick(&WRECK) } else { *p.rng.pick(&RUBBLE) };
        p.at(t + dt, surf(x, z, &format!("fill ~-{s} ~ ~-{s} ~{s} ~{h} ~{s} {a} keep")));
        if s > 1 {
            let (s2, h2) = (s / 2, h + 1);
            p.at(t + dt + 0.05, surf(x, z, &format!("fill ~-{s2} ~ ~-{s2} ~{s2} ~{h2} ~{s2} {b} keep")));
        }
    };
    // in the crater
    for _ in 0..70 {
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let r = DF_CRATER_R * p.rng.next().sqrt() * 0.9;
        let s = p.rng.int(1, 4);
        let h = p.rng.int(0, 2);
        let dt = p.rng.next() as f32;
        heap(p, g.ps.0 + a.cos() * r, g.ps.1 + a.sin() * r, s, h, dt);
    }
    // along the slot: its floor, and slumped against the foot of its walls
    for _ in 0..90 {
        let a = p.rng.uniform(40.0, DF_REAL_A - 10.0);
        let (hw, depth) = df_slot(a);
        let foot = (hw - f64::from(depth) * DF_SLOPE).max(4.0);
        let side = if p.rng.next() < 0.5 { -1.0 } else { 1.0 };
        let b = if p.rng.next() < 0.6 { side * (foot - p.rng.uniform(0.0, 5.0)) } else { p.rng.uniform(-foot, foot) };
        let (x, z) = (g.ps.0 + g.hf.0 * a - g.hf.1 * b, g.ps.1 + g.hf.1 * a + g.hf.0 * b);
        let s = p.rng.int(1, 3);
        let h = p.rng.int(0, 3);
        let dt = p.rng.next() as f32;
        heap(p, x, z, s, h, dt);
    }
    // the rim's lip
    for k in 0..64 {
        let a = f64::from(k) / 64.0 * 2.0 * PI + p.rng.uniform(-0.04, 0.04);
        let r = DF_CRATER_R + p.rng.uniform(2.0, 9.0);
        let s = p.rng.int(2, 4);
        let dt = p.rng.next() as f32 * 0.5;
        heap(p, g.ps.0 + a.cos() * r, g.ps.1 + a.sin() * r, s, 1, dt);
    }
}
/// A smooth noise over the land (0 to 1), `scale` blocks across.
fn vnoise(x: f64, z: f64, scale: f64, seed: u32) -> f64 {
    let (fx, fz) = (x / scale, z / scale);
    let (ix, iz) = (fx.floor(), fz.floor());
    let (tx, tz) = (fx - ix, fz - iz);
    let (sx, sz) = (tx * tx * (3.0 - 2.0 * tx), tz * tz * (3.0 - 2.0 * tz));
    let h = |dx: f64, dz: f64| mh(((ix + dx) as i32 as u32).wrapping_mul(73_856_093) ^ ((iz + dz) as i32 as u32).wrapping_mul(19_349_663), seed, 77);
    let (a, b, c, d) = (h(0.0, 0.0), h(1.0, 0.0), h(0.0, 1.0), h(1.0, 1.0));
    a + (b - a) * sx + (c - a) * sz + (a - b - c + d) * sx * sz
}
/// The site's ground, scarred: patches over the crater, the slot and the gouge, each a few blocks of scorched stone,
/// blackstone, basalt, tuff, coarse dirt or gravel, in broad stretches of one or another (a smooth noise picks), glassy
/// obsidian and the odd seam of magma nearer the hole. Only the top layers of the ground are changed, on the spare budget.
fn df_scar(p: &mut Plan, g: &DfGeo, t: f32) {
    let seed = g.seed;
    let skid = (g.ps.0 - g.c0.0).hypot(g.ps.1 - g.c0.1);
    let back = ((g.c0.0 - g.ps.0) * g.hf.0 + (g.c0.1 - g.ps.1) * g.hf.1).min(0.0) - 60.0;
    let mut a = (-DF_CRATER_R - 30.0).min(back);
    while a < DF_REAL_A + 10.0 {
        let mut b = -190.0;
        while b < 190.0 {
            let ja = a + p.rng.uniform(-2.5, 2.5);
            let jb = b + p.rng.uniform(-2.5, 2.5);
            let (x, z) = (g.ps.0 + g.hf.0 * ja - g.hf.1 * jb, g.ps.1 + g.hf.1 * ja + g.hf.0 * jb);
            let r = ja.hypot(jb);
            let in_slot = (-80.0..DF_REAL_A).contains(&ja) && df_step_depth(df_slot(ja).0 + 4.0, 0, jb) >= 0;
            let dir = ((g.ps.0 - g.c0.0) / skid.max(1.0), (g.ps.1 - g.c0.1) / skid.max(1.0));
            let ra = (x - g.c0.0) * dir.0 + (z - g.c0.1) * dir.1;
            let rb = ((z - g.c0.1) * dir.0 - (x - g.c0.0) * dir.1).abs();
            let in_skid = skid > 2.0 && (-10.0..skid + 10.0).contains(&ra) && rb < DF_SKID_W + 6.0;
            let at_strike = (x - g.c0.0).hypot(z - g.c0.1) < 58.0;
            if r < DF_CRATER_R + 26.0 || in_slot || in_skid || at_strike {
                let v = vnoise(x, z, 26.0, seed);
                let w = vnoise(x, z, 9.0, seed ^ 0x5bd1);
                let hot = (1.0 - r / 70.0).max(0.0);
                let blk = if hot > 0.2 && w > 0.62 {
                    "minecraft:obsidian"
                } else if hot > 0.1 && w < 0.08 {
                    "minecraft:magma_block"
                } else if v < 0.16 {
                    "minecraft:coarse_dirt"
                } else if v < 0.3 {
                    "minecraft:gravel"
                } else if v < 0.46 {
                    "minecraft:tuff"
                } else if v < 0.6 {
                    "minecraft:blackstone"
                } else if v < 0.72 {
                    "minecraft:basalt"
                } else if v < 0.84 {
                    "minecraft:deepslate"
                } else if w > 0.5 {
                    "minecraft:smooth_basalt"
                } else {
                    "minecraft:cobbled_deepslate"
                };
                let s = 3;
                for tag in ["#minecraft:base_stone_overworld", "#minecraft:dirt", "minecraft:blackstone"] {
                    p.ev.push((t, Act::Spare(surf(x.floor() as i32, z.floor() as i32, &format!("fill ~-{s} ~-3 ~-{s} ~{s} ~-1 ~{s} {blk} replace {tag}")))));
                }
            }
            b += 7.0;
        }
        a += 7.0;
    }
}
/// It collapses: the shaft bored to bedrock, lined, and what it was still holding thrown out over the land.
fn df_hole_collapse(p: &mut Plan, g: &DfGeo, floor_y: i32, bowl_d: i32) {
    let laser = p.laser;
    let by = p.by;
    let tc = DF_OPEN + DF_LIFE;
    let mut y_hi = by - bowl_d;
    let mut i = 0;
    while y_hi >= floor_y {
        let r = ((f64::from(laser.shaft_r) - f64::from(i) * 0.2).round() as i32).max(laser.shaft_min);
        let ts = tc + 0.1 + i as f32 * 0.06;
        p.dig(r, (y_hi - 3).max(floor_y), y_hi, ts, f64::from(laser.shaft_rough), 1);
        p.mottle(r, (y_hi - 3).max(floor_y), y_hi, ts, 3);
        y_hi -= 4;
        i += 1;
    }
    for (k, &(rad, lo, hi, block)) in laser.bottom.iter().enumerate() {
        for c in p.disc(rad, floor_y + lo, floor_y + hi, block, 0.0, None) {
            p.at(tc + 0.2 + i as f32 * 0.06 + 0.1 * k as f32, c);
        }
    }
    const FLUNG: [&str; 5] = ["minecraft:blackstone", "minecraft:polished_deepslate", "minecraft:obsidian", "minecraft:crying_obsidian", "minecraft:cobbled_deepslate"];
    let hy = f64::from(by) + DF_HOLE_H;
    for _ in 0..50 {
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = p.rng.uniform(8.0, 20.0);
        let (x, z) = (g.ps.0 + a.cos() * rr, g.ps.1 + a.sin() * rr);
        let sp = p.rng.uniform(1.2, 2.4);
        let (vx, vz) = (a.cos() * sp, a.sin() * sp);
        let vy = p.rng.uniform(0.3, 1.0);
        let blk = *p.rng.pick(&FLUNG);
        p.at(tc + 0.05, format!("summon minecraft:falling_block {x:.2} {hy:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b,Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"));
    }
}

// ---- the planet killer -----------------------------------------------------------------------------------------------

/// Planet killer: its times (strike clock) are strike.wgsl's PK_* (keep them in step), and where its towers stand, when
/// each fires and where its fissures run come from pk_*, the same as strike.wgsl's. Each tower's ground heaves for
/// PK_BULGE; then it breaks the surface and struggles there for PK_STRUGGLE (catching at PK_CATCH), bursts up out of it
/// over PK_THRUST, settles, and fires PK_RAISE after it broke the surface, from PK_IGN0 to PK_IGN1; its bolt feels its way
/// out and strikes the ring PK_SHOOT after it fires. The ring fuses at PK_MERGE; a bolt feels its way down to the target
/// and the beam pours down it at PK_DROP, lands at PK_HIT, and the land under it bursts at PK_BURST; it burns until the
/// towers cut out at PK_CUT, and the ring, crushed to a point, bursts in the crater at PK_POP.
const PK_N: usize = 7;
const PK_H: f64 = 300.0;
const PK_SRC_R: f64 = 1100.0;
const PK_TOWER_H: f64 = 420.0;
const PK_BULGE: f32 = 0.7;
const PK_STRUGGLE: f32 = 1.1;
const PK_THRUST: f32 = 0.8;
const PK_RAISE: f32 = 2.25;
/// When, after it breaks the surface, a tower gives a little and catches again as it struggles (strike.wgsl's pk_rise).
const PK_CATCH: [f32; 2] = [0.45, 0.82];
const PK_IGN0: f32 = 3.05;
const PK_IGN1: f32 = 5.45;
const PK_SHOOT: f32 = 1.14;
const PK_MERGE: f32 = 7.6;
const PK_DROP: f32 = 8.4;
const PK_HIT: f32 = 8.5;
const PK_BURST: f32 = 9.0;
const PK_CUT: f32 = 17.65;
const PK_POP: f32 = 18.55;
/// The blast: everything above the ground blown away out to this far (the first PK_BLAST_LOW blocks of it at once).
const PK_BLAST: i32 = 170;
const PK_BLAST_LOW: i32 = 8;
/// The crater (the laser's bowl_r and bowl_d) is dug 3 blocks at a time from PK_DIG0 after the burst, as fast as a
/// tick's block budget digs its layers (PK_DIG_K seconds a block down at the top, less as it narrows), in terraces
/// PK_TERRACE deep; its raised rim reaches out to PK_RIM_OUT.
const PK_DIG0: f32 = 2.9;
const PK_DIG_K: f64 = 0.21;
const PK_TERRACE: i32 = 12;
const PK_RIM_OUT: i32 = 175;
/// The fissures: PK_CRACKS of them from PK_RIM out, wandering off their heading every PK_SEG blocks, splitting open at
/// PK_CRACK_V blocks a second (in jerks: pk_crack_time) from PK_CRACK_T after the burst.
const PK_CRACKS: usize = 12;
const PK_RIM: f64 = 126.0;
const PK_SEG: f64 = 12.0;
const PK_CRACK_V: f64 = 90.0;
const PK_CRACK_T: f32 = 0.9;
/// The chunks kept loaded: a square this far either side of the target, and the fissures out past it.
const PK_LOAD: i32 = 184;

/// Tower i: where its foot stands (x, z) and when it fires, as strike.wgsl's pk_emitter. The first beyond the target as
/// the player faces it (`wing` points from the target to them), the rest alternately to its right and left, round
/// towards the player.
fn pk_emitter(i: usize, seed: f32, point: [f64; 3], wing: f32) -> (f64, f64, f32) {
    let s = seed as u32;
    let side = if i % 2 == 1 { 1.0 } else { -1.0 };
    let a = f64::from(wing) + PI + side * i.div_ceil(2) as f64 * 2.0 * PI / PK_N as f64 + (mh(i as u32, s, 31) - 0.5) * 0.5;
    let r = PK_SRC_R * (0.8 + 0.4 * mh(i as u32, s, 32));
    let t = PK_IGN0 + (PK_IGN1 - PK_IGN0) * i as f32 / (PK_N - 1) as f32 + ((mh(i as u32, s, 33) - 0.5) * 0.12) as f32;
    (point[0] + a.cos() * r, point[2] + a.sin() * r, t)
}
/// Fissure i: its heading out from the target, and how far it runs past PK_RIM (strike.wgsl's pk_crack).
fn pk_crack(i: usize, seed: f32) -> (f64, f64) {
    let s = seed as u32;
    let a = (i as f64 + 0.7 * mh(i as u32, s, 21)) * 2.0 * PI / PK_CRACKS as f64 + mh(99, s, 22) * 2.0 * PI;
    (a, 120.0 + 70.0 * mh(i as u32, s, 23))
}
/// The heading of fissure i `u` blocks past PK_RIM, as it wanders (strike.wgsl's pk_crack_off, between points).
fn pk_crack_at(i: usize, u: f64, seed: f32) -> f64 {
    let off = |j: usize| if j == 0 { 0.0 } else { (mh((i * 32 + j) as u32, seed as u32, 24) - 0.5) * 0.12 };
    let j = (u.max(0.0) / PK_SEG).floor() as usize;
    let f = (u.max(0.0) / PK_SEG).fract();
    pk_crack(i, seed).0 + off(j) + (off(j + 1) - off(j)) * f
}
/// When fissure splits have run `u` blocks past PK_RIM (after the burst): they run out in jerks, four a second, each a
/// lurch forward easing to a stop, PK_CRACK_V on the whole (strike.wgsl's pk_crack_front, turned round).
fn pk_crack_time(u: f64) -> f32 {
    let q = u.max(0.0) / PK_CRACK_V * 4.0;
    let (n, f) = (q.floor(), q.fract());
    // (where smoothstep(0, 0.35, x) is f)
    let x = 0.35 * (0.5 - ((1.0 - 2.0 * f).asin() / 3.0).sin());
    PK_CRACK_T + ((n + x) / 4.0) as f32
}
/// The crater's radius `d` blocks down: a bowl in terraces PK_TERRACE deep, each wall dropping steeply to a ledge.
fn pk_bowl_r(d: i32, bowl_r: i32, bowl_d: i32) -> i32 {
    let at = |d: i32| f64::from(bowl_r) * (1.0 - f64::from(d.min(bowl_d)) / (f64::from(bowl_d) + 0.5)).max(0.0).sqrt();
    let k = d / PK_TERRACE;
    let wall = at(k * PK_TERRACE) - f64::from(d - k * PK_TERRACE) * 0.55;
    (wall.max(at((k + 1) * PK_TERRACE)).round() as i32).max(18)
}
/// When the 3 blocks of the crater from `d` down are dug: the time to dig all of the bowl over them (its area falling
/// off with depth as a paraboloid's does), as strike.wgsl's pk_dig_t.
fn pk_dig_t(d: i32) -> f32 {
    let (d, dd) = (f64::from(d / 3 * 3), f64::from(crate::lasers::PLANET_KILLER.bowl_d) + 0.5);
    PK_BURST + PK_DIG0 + (PK_DIG_K * (d - d * d / (2.0 * dd))) as f32
}

/// The planet killer: seven towers grind up out of the land far out round the horizon (each heard from where it stands)
/// and strike a ring of light high over the target with bolts of lightning, one after another; the ring fuses, a bolt
/// feels its way down to the target and the beam comes down it: the land bursts, and the beam burns for eight and a half
/// seconds while they feed it; then they cut out and the nexus drops into the crater and bursts there. The land is blown flat for 170 blocks, a crater 260 across and 70 deep
/// is blown out in terraces with a molten floor and a shaft to bedrock, a rim is thrown up round it, twelve fissures
/// split the land out to about 300 blocks, and rock is thrown far across the land.
fn planetkiller_plan(laser: &'static Laser, target: &Target, terrain: bool, dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let r2 = |v: f64| (v * 100.0).round() / 100.0;
    let (tx, ty, tz) = (r2(target.point[0]), r2(target.point[1]), r2(target.point[2]));
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let bar = |text: &str, color: &str| format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#);
    let late = |x: f64, y: f64, z: f64| (((x - me[0]).powi(2) + (y - me[1]).powi(2) + (z - me[2]).powi(2)).sqrt() / 343.0) as f32;
    let wing = wing_angle(target.point, me);
    let (lt, dist) = sound_from(target.point, me);
    let fo = falloff(dist).max(0.45);
    let heard = PK_BURST + lt;
    let nexus = late(tx, ty + PK_H, tz);

    // the ground groaning under it all from the start, the array's power gathering, swelling to the moment they fuse
    // and cut dead just before it (the charge)
    p.at(0.2, bar("PLANET KILLER: ARRAY RISING", laser.color));
    p.csound(0.0, "charge", 10.0, 1.0);
    for (k, s) in [0.04, 0.06, 0.08].iter().enumerate() {
        p.shake(0.1 + k as f32 * 0.25, *s, 0.7);
    }
    // each tower heard from where it stands (far past where `playsound` reaches: from its direction, at the volume
    // floor), its sound kept to a third of a second behind it, though it stands further off than that, so the grinding
    // and the bursts stay on the picture: its ground heaving, the tower breaking the surface and grinding, giving and
    // catching, bursting up out of it and settling, rock raining back down; then its bolt crackling out to the ring and
    // striking it with a crack and a long roll of thunder. Three takes of each, at their own pitch, so no two are alike.
    // The land shakes with each, weaker the further off it stands (but not lost).
    let mut takes = [1, 2, 3];
    for i in 0..PK_N {
        let (x, z, t) = pk_emitter(i, shader_seed, target.point, wing);
        let (lag, d) = (late(x, ty, z).min(0.35), (x - me[0]).hypot(z - me[2]));
        let w = (1.0 / (1.0 + d / 600.0)) as f32;
        let r0 = t - PK_RAISE;
        if i % 3 == 0 {
            let k = p.rng.int(0, 2) as usize;
            takes.swap(0, k);
        }
        let take = takes[i % 3];
        let pitch = p.rng.uniform(0.92, 1.07);
        p.at(r0 - PK_BULGE + lag, format!("playsound orbital:planetkiller.rise{take} block @a {x:.1} {ty} {z:.1} 4 {pitch:.2} 0.95"));
        p.shake(r0 - PK_BULGE + lag, 0.07 * w + 0.02, PK_BULGE + 0.3);
        p.shake(r0 + lag, 0.3 * w + 0.06, 0.45);
        for c in PK_CATCH {
            p.shake(r0 + c + lag, 0.22 * w + 0.04, 0.35);
        }
        p.shake(r0 + 0.9 + lag, 0.1 * w + 0.03, 0.3);
        p.shake(r0 + PK_STRUGGLE + lag, 0.65 * w + 0.12, 1.6);
        p.shake(r0 + PK_STRUGGLE + PK_THRUST + lag, 0.22 * w + 0.05, 0.5);
        // its bolt: heard from the stretch of it nearest the ring, overhead and out towards the tower
        let (bx_, by_, bz_) = (tx + (x - tx) * 0.3, ty + PK_H + (PK_TOWER_H - PK_H) * 0.3, tz + (z - tz) * 0.3);
        let blag = late(bx_, by_, bz_).min(0.3);
        let btake = 1 + (i + take) % 3;
        let pitch = p.rng.uniform(0.9, 1.1);
        p.at(t + blag, format!("playsound orbital:planetkiller.bolt{btake} block @a {bx_:.1} {by_:.1} {bz_:.1} 4 {pitch:.2} 1"));
        p.shake(t + PK_SHOOT + blag, 0.2, 0.4);
    }
    // the bolts' crackle, held while they stay connected, swelling as each strikes the ring
    p.csound(PK_IGN0 + PK_SHOOT, "arcs", 10.0, 1.0);
    p.at(PK_IGN0 + 0.2, bar("ARRAY CHARGING", laser.color));
    for (k, s) in [0.12, 0.18, 0.3].iter().enumerate() {
        p.shake(PK_MERGE - 1.2 + k as f32 * 0.4, *s, 1.0);
    }
    // they fuse: a blow of light and pressure from overhead, the sky torn, a bolt crackling down out of it
    p.csound(PK_MERGE, "merge", 10.0, 1.0);
    p.shake(PK_MERGE + nexus, 0.55, 2.0);
    p.at(PK_MERGE, bar("CONVERGENCE", "aqua"));
    // the beam pours down onto the target: a thunderclap, the land heaving up under it, a breath of near silence, and it
    // bursts: the hardest blow of the strike (all one sound, heard from the target), then the beam's roar and the ground
    // shaking under it while it burns
    p.csound(PK_DROP + lt, "fire", 10.0, 1.0);
    p.shake(PK_DROP + lt, 0.4 * fo, 0.5);
    p.shake(PK_HIT + lt, 0.2 * fo, 0.5);
    p.shake(heard, fo, 5.0);
    p.at(PK_BURST + 0.1, bar("DIRECT HIT", "white"));
    p.csound(heard + 0.7, "beam1", 10.0, 1.0);
    p.csound(heard + 5.4, "beam2", 10.0, 1.0);
    p.csound(heard + 1.5, "rumble", 9.0, 1.0);
    p.csound(heard + 6.0, "rumble", 8.0, 0.9);
    let mut tk = PK_BURST + 1.2;
    while tk < PK_CUT {
        p.shake(tk + lt, 0.24 * fo, 1.3);
        tk += 1.0;
    }
    // they cut out, the nexus drops into the crater and bursts there, and the land settles
    p.csound(PK_CUT, "cutoff", 10.0, 1.0);
    p.shake(PK_POP + lt, 0.7 * fo, 3.0);
    p.csound(PK_POP + 1.0, "after", 9.0, 1.0);

    // ---- particles in the world ----
    for i in 0..10 {
        // the ground under the nexus stirring as it charges, dust lifting, a shimmer of energy coming up off it
        let tk = PK_MERGE - 2.6 + i as f32 * 0.3;
        let s = 24.0 - 1.5 * f64::from(i);
        p.at(tk, format!("particle minecraft:white_ash {tx} {} {tz} {s:.1} 1 {s:.1} 0 160 force", ty + 1.0));
        p.at(tk, format!("particle minecraft:soul_fire_flame {tx} {} {tz} {s:.1} 0.3 {s:.1} 0.02 40 force", ty + 0.5));
    }
    p.at(PK_BURST, format!("particle minecraft:explosion_emitter {tx} {} {tz} 30 6 30 0 30 force", ty + 2.0));
    p.at(PK_BURST + 0.05, format!("particle minecraft:flash {tx} {} {tz} 0 0 0 0 1 force", ty + 6.0));
    p.at(PK_BURST + 0.05, format!(r#"particle minecraft:block{{block_state:"minecraft:obsidian"}} {tx} {} {tz} 20 4 20 3.0 900 force"#, ty + 1.0));
    p.at(PK_BURST + 0.1, format!(r#"particle minecraft:block{{block_state:"minecraft:stone"}} {tx} {} {tz} 40 4 40 2.4 900 force"#, ty + 1.0));
    let mut tk = PK_BURST + 0.2;
    let mut k = 0;
    while tk < PK_CUT {
        // the foot of the beam: blue fire, molten rock thrown up, smoke boiling off
        p.at(tk, format!("particle minecraft:soul_fire_flame {tx} {} {tz} 10 3 10 0.25 80 force", ty + 1.0));
        p.at(tk, format!("particle minecraft:lava {tx} {} {tz} 20 3 20 0 30 force", ty - 10.0));
        if k % 2 == 0 {
            p.at(tk, format!("particle minecraft:explosion {tx} {} {tz} 20 4 20 0 6 force", ty - 5.0));
            p.at(tk, format!("particle minecraft:large_smoke {tx} {} {tz} 30 6 30 0.1 60 force", ty + 4.0));
        }
        tk += 0.35;
        k += 1;
    }
    // the nexus bursting in the crater
    p.at(PK_POP, format!("particle minecraft:explosion_emitter {tx} {} {tz} 20 10 20 0 20 force", ty - 20.0));
    p.at(PK_POP + 0.05, format!("particle minecraft:flash {tx} {} {tz} 0 0 0 0 1 force", ty));
    for i in 0..24 {
        // ash coming down over everything once it is over, the crater still smoking
        let tk = PK_POP + i as f32 * 0.45;
        p.at(tk, format!("particle minecraft:ash {tx} {} {tz} 150 30 150 0 400 force", ty + 40.0));
        p.at(tk, format!("particle minecraft:campfire_signal_smoke {tx} {} {tz} 60 4 60 0.05 40 force", ty - 30.0));
    }
    for tk in [0.1, 0.8, 2.0, 4.0, 7.0, PK_POP - PK_BURST + 0.2] {
        p.at(PK_BURST + tk, format!("execute positioned {tx} {ty} {tz} run kill @e[type=!minecraft:player,distance=..200]"));
    }

    if terrain {
        let (floor_y, sky, point) = (bedrock_top(dimension), sky_top(dimension), target.point);
        // a far target is past what the game keeps loaded round the player: keep the crater, the rim, the blast and the
        // fissures loaded until every change has been made (a forceload takes 256 chunks at most: strips of 128 blocks
        // across, and the stretch of each fissure past them); they are let go on the spare budget, after everything else
        // (the fissures' stretches let go as soon as everything queued before them is done, not held for the minute it
        // takes to clear the sky over the blast: then the square, which shares chunks with them at its edges, taken
        // again, and let go at the end)
        let rects = pk_forceload(point, shader_seed);
        for &(x0, z0, x1, z1, _) in &rects {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for &(x0, z0, x1, z1, fissure) in rects.iter().filter(|r| r.4).chain(rects.iter().filter(|r| !r.4)) {
            let verb = if fissure { "remove" } else { "add" };
            p.ev.push((PK_BURST + 5.0, Act::Spare(format!("forceload {verb} {x0} {z0} {x1} {z1}"))));
            if !fissure {
                p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
            }
        }
        pk_crater(&mut p, floor_y, sky);
        for i in 0..PK_CRACKS {
            // each fissure in two stretches, each worked out on its own tick just before it opens
            let len = pk_crack(i, shader_seed).1;
            for half in 0..2 {
                let (u0, u1) = (len * f64::from(half) / 2.0, len * f64::from(half + 1) / 2.0);
                let at = PK_BURST + PK_CRACK_T + (u0 / PK_CRACK_V) as f32 - 0.4 + (i % 4) as f32 * 0.05;
                p.later(at, move |q| pk_fissure(q, point, i, shader_seed, u0, u1));
            }
        }
        p.later(PK_BURST + 0.2, move |q| pk_ejecta(q, point));
        p.later(PK_BURST + 1.3, pk_rubble);
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// The rectangles kept loaded: strips across the square round the target, and the far stretch of each fissure (marked).
fn pk_forceload(point: [f64; 3], seed: f32) -> Vec<(i32, i32, i32, i32, bool)> {
    let (cx, cz) = (point[0].floor() as i32, point[2].floor() as i32);
    let mut out = Vec::new();
    let mut z = cz - PK_LOAD;
    while z <= cz + PK_LOAD {
        let z1 = (z + 127).min(cz + PK_LOAD);
        out.push((cx - PK_LOAD, z, cx + PK_LOAD, z1, false));
        z = z1 + 1;
    }
    for i in 0..PK_CRACKS {
        let len = pk_crack(i, seed).1;
        let (mut x0, mut z0, mut x1, mut z1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        let mut u = f64::from(PK_LOAD) - PK_RIM - 8.0;
        while u <= len + 4.0 {
            let a = pk_crack_at(i, u.min(len), seed);
            let (x, z) = ((point[0] + a.cos() * (PK_RIM + u)).floor() as i32, (point[2] + a.sin() * (PK_RIM + u)).floor() as i32);
            (x0, z0, x1, z1) = (x0.min(x - 6), z0.min(z - 6), x1.max(x + 6), z1.max(z + 6));
            u += 4.0;
        }
        if x0 <= x1 {
            out.push((x0, z0, x1, z1, true));
        }
    }
    out
}

/// The blast, the crater dug top down in terraces, its molten floor and lava lake, the shaft, the rim and the charred land:
/// each stage worked out just before it starts, each a small piece of work. They go in the order the eye takes them in:
/// the land blown flat round it, the crater opening, its depths, then the land further out; what stands high over the
/// blast, out of the way, goes on the spare budget.
fn pk_crater(p: &mut Plan, floor_y: i32, sky: i32) {
    let t = PK_BURST;
    // 1. the blast: everything standing above the ground blown away, the lowest PK_BLAST_LOW blocks at once, the next 30
    //    once the crater and its shaft are dug, the rest up to the sky on the spare budget (in bands: a fill is capped at
    //    32768 blocks)
    p.later(t - 0.1, move |p| {
        let by = p.by;
        for c in p.disc(PK_BLAST, by + 1, (by + PK_BLAST_LOW).min(sky), "minecraft:air", 0.08, None) {
            p.at(t + 0.05, c);
        }
    });
    p.later(t + 13.0, move |p| {
        let by = p.by;
        let mut y = by + PK_BLAST_LOW + 1;
        while y <= (by + PK_BLAST_LOW + 30).min(sky) {
            let top = (y + 14).min(sky);
            for c in p.disc(PK_BLAST, y, top, "minecraft:air", 0.08, None) {
                p.at(t + 13.2, c);
            }
            y = top + 1;
        }
        p.clear_above(t + 13.3, PK_BLAST, by + PK_BLAST_LOW + 31, sky, 0.08);
    });
    // 2. the crater, 3 blocks at a time from the top down, a stage for each: its walls fused as it goes, and the rock
    //    breaking away onto the ledges of its terraces
    let (bowl_r, bowl_d) = (p.laser.bowl_r, p.laser.bowl_d.min(p.by - floor_y - 8));
    let mut d = 0;
    while d < bowl_d {
        let dd = d;
        p.later(pk_dig_t(dd) - 0.15, move |p| {
            // (the walls fused where they are natural ground: near the top every kind of it; deeper down only the rock,
            // the odd pocket of dirt or gravel left in the glass. Each kind is a pass of its own over the wall, and the
            // passes are most of the crater's commands)
            const NATURAL: [&str; 4] = ["#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand", "minecraft:gravel"];
            let natural = if dd < 12 { &NATURAL[..] } else { &NATURAL[..1] };
            let laser = p.laser;
            let by = p.by;
            let prim = laser.lining[0].0;
            let tl = pk_dig_t(dd);
            let (y_lo, y_hi) = (by - dd - 2, by - dd);
            let r = pk_bowl_r(dd, bowl_r, bowl_d);
            let rs = p.rects(r, f64::from(laser.bowl_rough));
            for tag in natural {
                for c in Plan::edge_fills(&rs, y_lo - 1, y_hi, prim, tag, 2) {
                    p.at(tl - 0.05, c);
                }
            }
            for c in Plan::fills(&rs, y_lo, y_hi, "minecraft:air", None, 0) {
                p.at(tl, c);
            }
            p.mottle(r, y_lo, y_hi, tl, 24);
            if dd % PK_TERRACE == PK_TERRACE - 3 && dd + 3 < bowl_d {
                // the ledge under this terrace's wall: rock fallen from it heaped along it
                let next = pk_bowl_r(dd + 3, bowl_r, bowl_d);
                const FALLEN: [&str; 4] = ["minecraft:cobblestone", "minecraft:blackstone", "minecraft:cobbled_deepslate", "minecraft:basalt"];
                for _ in 0..18 {
                    let a = p.rng.uniform(0.0, 2.0 * PI);
                    let rr = p.rng.uniform(f64::from(next) + 1.0, f64::from(r) - 1.0);
                    let (x, z) = (p.bx + (a.cos() * rr).round() as i32, p.bz + (a.sin() * rr).round() as i32);
                    let h = p.rng.int(1, 3);
                    let blk = *p.rng.pick(&FALLEN);
                    p.at(tl + 0.1, format!("fill {} {} {} {} {} {} {blk} keep", x - 1, y_lo, z - 1, x + 1, y_lo + h - 1, z + 1));
                }
            }
            for _ in 0..2 {
                let (pitch, dt) = (p.rng.uniform(0.5, 0.8), p.rng.uniform(0.0, 0.2) as f32);
                p.ground_sound(tl + dt, if dd > 60 { "block.deepslate.break" } else { "block.stone.break" }, 10.0, pitch);
            }
        });
        d += 3;
    }
    // 3. its floor: magma, and a lake of lava over it
    let floor = p.by - bowl_d;
    p.later(pk_dig_t(bowl_d) + 0.1, move |p| {
        let laser = p.laser;
        let (fb, fr, fq) = laser.bowl_floor;
        let r = pk_bowl_r(bowl_d - 1, laser.bowl_r, bowl_d) + 6;
        let tf = pk_dig_t(bowl_d) + 0.3;
        for c in p.disc(r, floor - 2, floor, fb, f64::from(fr), Some(fq)) {
            p.at(tf, c);
        }
        for c in p.disc(r + 12, floor + 1, floor + 2, "minecraft:lava", 0.1, Some("minecraft:air")) {
            p.at(tf + 0.2, c);
        }
        p.at(tf + 0.2, format!("playsound minecraft:block.lava.ambient block @a {} {floor} {} 4 0.6", p.bx, p.bz));
    });
    // 4. the shaft, drilled on down from the floor to bedrock (in three stages), and the bottom of it
    let steps = ((floor - floor_y) / 4 + 1).max(1);
    for part in 0..3 {
        let (i0, i1) = (steps * part / 3, steps * (part + 1) / 3);
        p.later(pk_dig_t(bowl_d) + 0.3 + i0 as f32 * 0.15, move |p| {
            let laser = p.laser;
            let (bx, bz) = (p.bx, p.bz);
            for i in i0..i1 {
                let y_hi = floor - 4 * i;
                if y_hi < floor_y {
                    break;
                }
                let r = ((f64::from(laser.shaft_r) - f64::from(i) * 0.4).round() as i32).max(laser.shaft_min);
                let ts = pk_dig_t(bowl_d) + 0.5 + i as f32 * 0.15;
                p.dig(r, (y_hi - 3).max(floor_y), y_hi, ts, f64::from(laser.shaft_rough), 1);
                p.mottle(r, (y_hi - 3).max(floor_y), y_hi, ts, 4);
                if i % 2 == 0 {
                    let pitch = p.rng.uniform(0.5, 0.8);
                    p.ground_sound(ts, "block.deepslate.break", 9.0, pitch);
                    p.at(ts, format!("particle minecraft:soul_fire_flame {} {y_hi} {} 4 1 4 0.05 30 force", f64::from(bx) + 0.5, f64::from(bz) + 0.5));
                }
            }
            if part == 2 {
                for (k, &(rad, lo, hi, block)) in laser.bottom.iter().enumerate() {
                    for c in p.disc(rad, floor_y + lo, floor_y + hi, block, 0.0, None) {
                        p.at(pk_dig_t(bowl_d) + 0.6 + steps as f32 * 0.15 + 0.1 * k as f32, c);
                    }
                }
            }
        });
    }
    // 5. the rim, once the crater is dug: the land round it thrown up and piled outward, highest at the crater's lip, in
    //    three rings
    let tr = pk_dig_t(bowl_d) + 0.2;
    p.later(tr - 0.2, move |p| {
        let by = p.by;
        let mid = (bowl_r + 3 + PK_RIM_OUT) / 2;
        for (r, g, y0, y1, block) in [
            (mid, (PK_RIM_OUT - bowl_r - 3) / 2, by - 6, by + 3, "minecraft:cobbled_deepslate"),
            (bowl_r + 16, 12, by + 4, by + 8, "minecraft:blackstone"),
            (bowl_r + 9, 5, by + 9, by + 12, "minecraft:basalt"),
        ] {
            let rs = p.rects(r, 0.05);
            for c in Plan::edge_fills(&rs, y0, y1, block, "minecraft:air", g) {
                p.at(tr, c.replace(" replace minecraft:air", " keep"));
            }
        }
        const RIM: [&str; 5] = ["minecraft:cobblestone", "minecraft:tuff", "minecraft:blackstone", "minecraft:obsidian", "minecraft:magma_block"];
        for _ in 0..240 {
            // boulders strewn over it
            let a = p.rng.uniform(0.0, 2.0 * PI);
            let rr = p.rng.uniform(f64::from(bowl_r) + 4.0, f64::from(PK_RIM_OUT) + 10.0);
            let (x, z) = (p.bx + (a.cos() * rr).round() as i32, p.bz + (a.sin() * rr).round() as i32);
            let s = p.rng.int(1, 2);
            let blk = *p.rng.pick(&RIM);
            let dt = p.rng.uniform(0.0, 0.8) as f32;
            p.at(tr + 0.1 + dt, surf(x, z, &format!("fill ~-{s} ~ ~-{s} ~{s} ~{} ~{s} {blk} keep", s * 2 - 1)));
        }
    });
    // 6. the charred land, last (it is the most ground to change after the crater and the blast)
    p.later(t + 13.5, move |p| {
        let laser = p.laser;
        let by = p.by;
        for &(rad, block, rough, repl) in laser.scorch {
            for c in p.disc(rad, by - 1, by + 1, block, f64::from(rough), Some(repl)) {
                let dt = p.rng.next() as f32 * 2.0;
                p.at(t + 13.7 + dt, c);
            }
        }
    });
}

/// The stretch `u0..u1` blocks past PK_RIM of fissure `i` split open, a column at a time as the split runs out to it: a
/// chasm deepest and widest by the crater (34 blocks down), its floor magma, every third one running with lava, its
/// walls basalt. Each column is cut on its own from the ground there (so no cut moves the ground another measures from).
fn pk_fissure(p: &mut Plan, point: [f64; 3], i: usize, seed: f32, u0: f64, u1: f64) {
    let len = pk_crack(i, seed).1;
    let lava = i.is_multiple_of(3);
    let mut seen = std::collections::HashSet::new();
    let mut u = u0;
    while u < u1 {
        let a = pk_crack_at(i, u, seed);
        let r = PK_RIM + u;
        let (dx, dz) = (a.cos(), a.sin());
        let share = 1.0 - u / len;
        let hw = 0.8 + 3.5 * share;
        let depth = (4.0 + 30.0 * share).round() as i32;
        let t = PK_BURST + pk_crack_time(u);
        let mut o = -hw - 0.7;
        while o <= hw + 0.7 + 1e-6 {
            let (x, z) = ((point[0] + dx * r - dz * o).floor() as i32, (point[2] + dz * r + dx * o).floor() as i32);
            if seen.insert((x, z)) {
                if o.abs() > hw {
                    // the wall, fused
                    p.at(t, surf(x, z, &format!("fill ~ ~-{depth} ~ ~ ~-2 ~ minecraft:basalt replace #minecraft:base_stone_overworld")));
                } else {
                    p.at(t, surf(x, z, &format!("fill ~ ~-{} ~ ~ ~-1 ~ minecraft:magma_block", depth + 1)));
                    p.at(t, surf(x, z, &format!("fill ~ ~-{depth} ~ ~ ~-1 ~ minecraft:air")));
                    if lava && o.abs() < hw * 0.6 {
                        p.at(t + 0.05, surf(x, z, "setblock ~ ~-1 ~ minecraft:lava"));
                    }
                }
            }
            o += 0.7;
        }
        if (u / 8.0).fract() < 0.06 {
            let (x, z) = ((point[0] + dx * r).floor() as i32, (point[2] + dz * r).floor() as i32);
            let pitch = p.rng.uniform(0.5, 0.75);
            p.at(t, surf(x, z, &format!("playsound minecraft:block.basalt.break block @a ~ ~ ~ 4 {pitch:.2}")));
            p.at(t, surf(x, z, "particle minecraft:lava ~ ~ ~ 2 1 2 0 10 force"));
        }
        u += 0.5;
    }
}

/// Rock thrown out of the crater as the land bursts: real blocks flying out over the land.
fn pk_ejecta(p: &mut Plan, point: [f64; 3]) {
    let by = p.by;
    for _ in 0..260 {
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = p.rng.uniform(20.0, 110.0);
        let (x, z) = (point[0] + a.cos() * rr, point[2] + a.sin() * rr);
        let elev = 0.4 + 0.9 * p.rng.next().powf(0.7);
        let speed = (1.8 + 3.0 * p.rng.next().powi(2)) * p.rng.uniform(0.7, 1.3);
        let (vx, vy, vz) = (a.cos() * elev.cos() * speed, elev.sin() * speed, a.sin() * elev.cos() * speed);
        let blk = *p.rng.pick(&PK_EJECTA);
        let tl = PK_BURST + (0.05 + 1.0 * p.rng.next().powi(2)) as f32;
        p.at(tl, format!("summon minecraft:falling_block {x:.1} {} {z:.1} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b,Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}", by + 3));
    }
}
const PK_EJECTA: [&str; 7] = [
    "minecraft:cobblestone",
    "minecraft:blackstone",
    "minecraft:obsidian",
    "minecraft:cobbled_deepslate",
    "minecraft:basalt",
    "minecraft:magma_block",
    "minecraft:dirt",
];

/// Out past the rim: boulders and rubble coming down across the land out to 400 blocks, and the charred land burning.
fn pk_rubble(p: &mut Plan) {
    let t = PK_BURST;
    let (bx, bz) = (p.bx, p.bz);
    for _ in 0..220 {
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = f64::from(PK_RIM_OUT) + 150.0 * p.rng.next().powf(1.3);
        let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
        let tl = t + 1.5 + (rr / 330.0 * 4.0) as f32 + p.rng.uniform(0.0, 1.0) as f32;
        let blk = *p.rng.pick(&PK_EJECTA);
        let s = if p.rng.next() < 0.3 { 1 } else { 0 };
        p.at(tl, surf(x, z, &format!("fill ~-{s} ~ ~-{s} ~{s} ~{s} ~{s} {blk} keep")));
    }
    for k in 0..360 {
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = f64::from(PK_RIM_OUT) + 225.0 * p.rng.next().powf(1.4);
        let (x, z) = (bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32);
        let tl = t + 2.0 + (rr / 400.0 * 5.0) as f32 + p.rng.uniform(0.0, 1.2) as f32;
        let blk = *p.rng.pick(&PK_EJECTA);
        p.at(tl, surf(x, z, &format!("setblock ~ ~ ~ {blk} keep")));
        if k % 5 == 0 {
            p.at(tl, surf(x, z, &format!(r#"particle minecraft:block{{block_state:"{blk}"}} ~ ~0.5 ~ 0.6 0.4 0.6 0.2 16 force"#)));
        }
    }
    for _ in 0..200 {
        let a = p.rng.uniform(0.0, 2.0 * PI);
        let rr = p.rng.uniform(f64::from(PK_RIM_OUT) + 4.0, 290.0);
        let dt = p.rng.uniform(1.5, 7.0) as f32;
        p.at(t + dt, surf(bx + (a.cos() * rr).round() as i32, bz + (a.sin() * rr).round() as i32, "setblock ~ ~ ~ minecraft:fire keep"));
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
                Act::Cmd(c) | Act::Spare(c) => out.push((t, c)),
                Act::Sound { .. } | Act::Shake { .. } => {}
                Act::Later(job) => ev.extend(job()),
            }
        }
        out
    }
    #[test]
    fn blasts_clear_to_the_sky() {
        // nothing is left hanging over a crater: every laser clears the air over its target up to the build limit
        // (under the Nether's roof there), and no fill is over the cap
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        for laser in crate::lasers::LASERS {
            for (dimension, sky) in [("minecraft:overworld", 319), ("minecraft:the_nether", 122)] {
                let me = [10.5, 66.0, 60.0];
                let cmds = run_all(plan(laser, &target, true, dimension, 7.0, me, 0));
                // (the downfall's blast is where its stern comes down)
                let (cx, cz) = if laser.key == "downfall" {
                    let g = DfGeo::new(target.point, 64, wing_angle(target.point, me), 0, df_reach(target.point, me), 7.0);
                    (g.ps.0.floor() as i32, g.ps.1.floor() as i32)
                } else {
                    (10, -3)
                };
                let over = |y: i32| {
                    cmds.iter().any(|(_, c)| {
                        let w: Vec<&str> = c.split_whitespace().collect();
                        w.len() >= 8 && w[0] == "fill" && w[7] == "minecraft:air" && {
                            let n: Vec<i32> = w[1..7].iter().filter_map(|v| v.parse().ok()).collect();
                            n.len() == 6 && n[0].min(n[3]) <= cx && n[0].max(n[3]) >= cx && n[2].min(n[5]) <= cz && n[2].max(n[5]) >= cz
                                && n[1].min(n[4]) <= y && n[1].max(n[4]) >= y
                        }
                    })
                };
                for y in [65, (65 + sky) / 2, sky] {
                    assert!(over(y), "{} in {dimension}: nothing clears y {y} over the target", laser.key);
                }
                assert!(!over(sky + 1), "{} in {dimension}: clears above y {sky}", laser.key);
                for (_, c) in &cmds {
                    assert!(block_cost(c).unwrap_or(0) <= 32768, "{c}");
                }
            }
        }
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
                    // the trench's clearing fills, one a column: `fill X 65 Z X 319 Z air` (or across)
                    let w: Vec<&str> = c.split_whitespace().collect();
                    if w.len() == 8 && w[0] == "fill" && w[2] == "65" && w[5] == "319" && w[7] == "minecraft:air" {
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
                trench(&mut p, [10.5, 64.0, -2.5], axis, d0, d1, 319);
                d0 = d1;
            }
            let air: Vec<&String> = p
                .ev
                .iter()
                .filter_map(|(_, a)| match a {
                    Act::Cmd(c) if c.ends_with("minecraft:air") && c.contains(" 319 ") => Some(c),
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

    const DF_PLAYERS: [[f64; 3]; 7] =
        [[10.5, 66.0, 60.0], [10.5, 66.0, 4.0], [-150.0, 70.0, -40.0], [200.0, 64.0, 190.0], [10.5, 66.0, -600.0], [700.0, 64.0, -3.0], [-40.0, 90.0, 300.0]];
    fn df_cmds(mode: usize, me: [f64; 3], dimension: &str) -> Vec<(f32, String)> {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        run_all(plan(&crate::lasers::DOWNFALL, &target, true, dimension, 37.0, me, mode))
    }
    fn df_g(mode: usize, me: [f64; 3]) -> DfGeo {
        let point = [10.5, 65.0, -2.5];
        DfGeo::new(point, 64, wing_angle(point, me), mode, df_reach(point, me), 37.0)
    }
    #[test]
    fn downfall_never_comes_down_on_the_player() {
        // whichever way it came in, from wherever the player stands: no part of the hull comes within 40 blocks of
        // them lower than 80 blocks over them, at any moment of its fall or after; its stern (the black hole) comes to
        // rest well in front of them; and the chunks blown off it land well clear of them
        for mode in 0..5 {
            for me in DF_PLAYERS {
                let g = df_g(mode, me);
                assert!((g.ps.0 - me[0]).hypot(g.ps.1 - me[2]) >= 250.0, "mode {mode} {me:?}: the hole is too close");
                let mut t = DF_FALL0;
                while t <= 60.0 {
                    let p = g.pose(t);
                    for x in (-560..=560).step_by(20) {
                        for z in (-280..=280).step_by(20) {
                            let (x, z) = (f64::from(x), f64::from(z));
                            if ms_half_w(x) < z.abs() {
                                continue;
                            }
                            let w = p.world([x, 0.0, z]);
                            if (w[0] - me[0]).hypot(w[2] - me[2]) < 40.0 {
                                assert!(w[1] > me[1] + 80.0, "mode {mode} {me:?}: the hull {} over the player at {t}", w[1] - me[1]);
                            }
                        }
                    }
                    t += 0.25;
                }
                for i in 0..DF_CHUNKS {
                    if let Some((x, z, _)) = g.chunk_land(i) {
                        assert!((x - me[0]).hypot(z - me[2]) > 60.0, "mode {mode} {me:?}: chunk {i} lands by the player");
                    }
                }
            }
        }
    }
    #[test]
    fn downfall_pose_agrees() {
        for mode in 0..5 {
            for me in DF_PLAYERS {
                let g = df_g(mode, me);
                // hanging there it is the mothership as it stops: its eye over the target, 420 up
                let eye = g.pose(5.0).world([MS_EM_X, 0.0, 0.0]);
                assert!((eye[0] - 10.5).abs() < 1e-6 && (eye[2] + 2.5).abs() < 1e-6 && (eye[1] - 485.0).abs() < 1e-6);
                // its fall is unbroken, and its stern comes to rest at the hole, buried
                let mut last = g.pose(DF_FALL0 - 0.05).s;
                let mut t = DF_FALL0;
                while t < 40.0 {
                    let s = g.pose(t).s;
                    let step = ((s[0] - last[0]).powi(2) + (s[1] - last[1]).powi(2) + (s[2] - last[2]).powi(2)).sqrt();
                    assert!(step < 10.0, "mode {mode}: a jump of {step} at {t}");
                    last = s;
                    t += 0.05;
                }
                let s = g.pose(45.0).s;
                assert!((s[0] - g.ps.0).abs() < 1e-6 && (s[2] - g.ps.1).abs() < 1e-6 && (s[1] - (64.0 - DF_EMBED)).abs() < 1e-6);
                // the meteor's pieces strike its roof while it hangs there, before it falls
                for j in 0..DF_HITS.len() {
                    let (_, th) = g.hit(j);
                    assert!(th > DF_SPLIT + 0.5 && th < DF_FALL0 - 0.5, "{th}");
                }
            }
        }
    }
    #[test]
    fn downfall_real_blocks_agree() {
        // what the shader draws and what is really done: the blocks the black hole tears up go when it does, from where
        // its debris starts; each chunk's crater is dug where and when it comes down; the hole's crater is under it
        for mode in [0, 1, 2] {
            let me = DF_PLAYERS[mode + 1];
            let g = df_g(mode, me);
            let cmds = df_cmds(mode, me, "minecraft:overworld");
            for i in 0..DFD_N {
                let (x, z, tr, wreck, big) = g.torn(i);
                let gy = g.ground(x, z);
                let y = if wreck { gy + 1 } else { gy - i32::from(big) };
                let want = if big { format!("fill {} {y} {} {x} {} {z} minecraft:air", x - 1, z - 1, y + 1) } else { format!("setblock {x} {y} {z} minecraft:air") };
                assert!(cmds.iter().any(|(t, c)| *c == want && (*t - (DF_OPEN + tr)).abs() < 1e-4), "torn {i}: {want}");
                if wreck {
                    // and the piece of wreck was lying there
                    let put = if big { format!("fill {} {} {} {x} {} {z} ", x - 1, gy + 1, z - 1, gy + 2) } else { format!("setblock {x} {} {z} ", gy + 1) };
                    assert!(cmds.iter().any(|(t, c)| c.starts_with(&put) && *t < DF_OPEN), "wreck {i}");
                }
            }
            for i in 0..DF_CHUNKS {
                if let Some((x, z, tl)) = g.chunk_land(i) {
                    let at = surf(x.floor() as i32, z.floor() as i32, "fill");
                    assert!(cmds.iter().any(|(t, c)| c.starts_with(&at) && (*t - tl).abs() < 0.2), "chunk {i}");
                }
            }
            let (px, pz) = (g.ps.0.floor() as i32, g.ps.1.floor() as i32);
            assert!(cmds.iter().any(|(t, c)| {
                let w: Vec<&str> = c.split_whitespace().collect();
                *t > DF_OPEN && w.len() >= 8 && w[0] == "fill" && w[7] == "minecraft:air" && {
                    let n: Vec<i32> = w[1..7].iter().filter_map(|v| v.parse().ok()).collect();
                    n.len() == 6 && n[0] <= px && n[3] >= px && n[2] <= pz && n[5] >= pz && n[1] <= 50
                }
            }));
        }
    }
    #[test]
    fn downfall_fills_fit_and_stay_under_the_sky() {
        // every fill under the cap, nothing cleared over the build limit, a shaft to bedrock under the hole, and what is
        // force-loaded is let go again
        for mode in 0..5 {
            for me in [DF_PLAYERS[0], DF_PLAYERS[4]] {
                for (dimension, sky, floor) in [("minecraft:overworld", 319, -59), ("minecraft:the_nether", 122, 5)] {
                    let cmds = df_cmds(mode, me, dimension);
                    let mut deepest = i32::MAX;
                    for (_, c) in &cmds {
                        assert!(block_cost(c).unwrap_or(0) <= 32768, "{c}");
                        let run = c.rsplit(" run ").next().unwrap_or(c);
                        let w: Vec<&str> = run.split_whitespace().collect();
                        if w.first() == Some(&"fill") {
                            for k in [2, 5] {
                                if let Ok(y) = w[k].parse::<i32>() {
                                    assert!(y <= sky, "{c}");
                                    deepest = deepest.min(y);
                                }
                            }
                        }
                    }
                    // (the lining's patches reach one block into the bedrock floor, as every laser's do)
                    assert!(deepest == floor || deepest == floor - 1, "mode {mode}: the shaft reaches {deepest}");
                    let adds = cmds.iter().filter(|(_, c)| c.starts_with("forceload add")).count();
                    let removes = cmds.iter().filter(|(t, c)| c.starts_with("forceload remove") && *t < crate::lasers::DOWNFALL.length).count();
                    assert_eq!(adds, removes);
                    let chunks: i32 = cmds
                        .iter()
                        .filter(|(_, c)| c.starts_with("forceload add"))
                        .map(|(_, c)| {
                            let n: Vec<i32> = c.split_whitespace().skip(2).map(|v| v.parse().unwrap()).collect();
                            ((n[2] >> 4) - (n[0] >> 4) + 1) * ((n[3] >> 4) - (n[1] >> 4) + 1)
                        })
                        .sum();
                    // (the black hole's reach and the stern's section of the hull with its heaps, past what the game keeps loaded)
                    assert!(chunks <= 950, "{chunks} chunks");
                }
            }
        }
    }
    #[test]
    fn downfall_shakes_hardest_at_the_crash() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        for mode in 0..5 {
            for me in DF_PLAYERS {
                let mut ev = plan(&crate::lasers::DOWNFALL, &target, false, "minecraft:overworld", 37.0, me, mode);
                let mut jolts = Vec::new();
                while let Some((t, act)) = ev.pop() {
                    match act {
                        Act::Shake { strength, seconds } => jolts.push((t, strength, seconds)),
                        Act::Later(job) => ev.extend(job()),
                        _ => {}
                    }
                }
                for &(t, s, d) in &jolts {
                    assert!(s > 0.0 && s <= 1.0 && (0.05..=30.0).contains(&d) && t < crate::lasers::DOWNFALL.length, "{s} {d} at {t}");
                }
                let g = df_g(mode, me);
                let crash = DF_FALL1 + (((g.c0.0 - me[0]).powi(2) + (64.0 - me[1]).powi(2) + (g.c0.1 - me[2]).powi(2)).sqrt() / 343.0) as f32;
                let hardest = jolts.iter().fold((0.0, 0.0), |a, j| if j.1 > a.1 { (j.0, j.1) } else { a });
                assert!((hardest.0 - crash).abs() < 1e-3, "mode {mode} {me:?}: hardest at {} not {crash}", hardest.0);
            }
        }
    }

    #[test]
    fn downfall_leaves_the_land_alone_until_it_is_there() {
        // nothing of the crash is built or dug on the land along where it comes to rest (its heaps, the slot under its
        // keel, the hills it sinks into) before the hull has come down there: each part waits for the belly beside it
        for mode in [0, 1, 2] {
            let me = DF_PLAYERS[mode];
            let g = df_g(mode, me);
            let cmds = df_cmds(mode, me, "minecraft:overworld");
            let local = |x: f64, z: f64| ((x - g.ps.0) * g.hf.0 + (z - g.ps.1) * g.hf.1, (z - g.ps.1) * g.hf.0 - (x - g.ps.0) * g.hf.1);
            // (the pieces that fell off it, and the stern's own crater where it first strikes, come before)
            let mut falls: Vec<(f64, f64)> = (0..DF_SHED).filter_map(|i| g.shed_land(i).map(|(x, z, _, _)| (x, z))).collect();
            falls.extend((0..DF_CHUNKS).filter_map(|i| g.chunk_land(i).map(|(x, z, _)| (x, z))));
            let mut checked = 0;
            for (t, c) in &cmds {
                let w: Vec<&str> = c.split_whitespace().collect();
                let (x, z) = match w.as_slice() {
                    ["fill" | "setblock", x, _, z, ..] => (x.parse::<f64>().unwrap_or(f64::NAN), z.parse::<f64>().unwrap_or(f64::NAN)),
                    ["execute", "positioned", x, "0", z, ..] if c.contains(" fill ") || c.contains(" setblock ") => {
                        (x.parse::<f64>().unwrap(), z.parse::<f64>().unwrap())
                    }
                    _ => continue,
                };
                if !x.is_finite() || !z.is_finite() || *t < DF_FALL0 || *t > DF_REST + 3.0 {
                    continue;
                }
                if (x - g.c0.0).hypot(z - g.c0.1) < 75.0 || falls.iter().any(|f| (x - f.0).hypot(z - f.1) < 14.0) {
                    continue;
                }
                let (a, b) = local(x + 0.5, z + 0.5);
                let xl = a + DF_XP;
                if !(-560.0..=560.0).contains(&xl) || b.abs() > ms_half_w(xl) + 70.0 {
                    continue;
                }
                let touch = g.sunk_by(xl.clamp(-560.0, 560.0), 0.0);
                assert!(*t >= touch - 0.15, "mode {mode}: at {t:.2}, before the hull is down there at {touch:.2}: {c}");
                checked += 1;
            }
            assert!(checked > 300, "mode {mode}: {checked}");
        }
    }
    #[test]
    fn downfall_buries_itself_and_agrees() {
        // at rest its stern's belly is DF_EMBED under the ground; the slot carved for its keel (its walls sloping in, its
        // ends closing) lies inside the keel's own outline at that pose, no more than DF_SLOT deep; the heaps of displaced ground stand outside the hull,
        // as high as df_berm_h says; the pieces it shed leave craters where they come down
        for mode in [0, 1, 2] {
            let me = DF_PLAYERS[mode];
            let g = df_g(mode, me);
            let rest = g.pose(50.0);
            let pv = rest.world([DF_XP, 0.0, 0.0]);
            assert!((pv[1] - (64.0 - DF_EMBED)).abs() < 1e-6);
            // buried: its roof stands well under its full height over the land, its belly well under it, all along
            for x in [-560.0, 0.0, 560.0] {
                let b = rest.world([x, 0.0, 0.0])[1] - 64.0;
                assert!(b < -35.0 && b > -80.0, "mode {mode}: belly at {b} at {x}");
            }
            let cmds = df_cmds(mode, me, "minecraft:overworld");
            let local = |x: f64, z: f64| ((x - g.ps.0) * g.hf.0 + (z - g.ps.1) * g.hf.1, (z - g.ps.1) * g.hf.0 - (x - g.ps.0) * g.hf.1);
            let mut slot = 0;
            for (_, c) in &cmds {
                let w: Vec<&str> = c.split_whitespace().collect();
                let ys = (w.get(2).and_then(|v| v.parse::<i32>().ok()), w.get(5).and_then(|v| v.parse::<i32>().ok()));
                if w.len() == 8 && w[0] == "fill" && w[7] == "minecraft:air" && (w[1] == w[4] || w[3] == w[6]) && matches!(ys, (Some(y0), Some(y1)) if y0 >= 64 - DF_SLOT && y1 <= 64 && y0 <= y1) {
                    let n: Vec<f64> = [1, 3, 4, 6].iter().map(|&k| w[k].parse::<f64>().unwrap()).collect();
                    let (am, _) = local((n[0] + n[2]) * 0.5 + 0.5, (n[1] + n[3]) * 0.5 + 0.5);
                    if (-80.0..DF_REAL_A).contains(&am) {
                        for (x, z) in [(n[0], n[1]), (n[2], n[3])] {
                            let (_, b) = local(x + 0.5, z + 0.5);
                            assert!(b.abs() <= df_keel_hw(am) + 1.5, "mode {mode}: the slot strays outside the keel: {c}");
                            slot += 1;
                        }
                    }
                }
            }
            assert!(slot as f64 > 2.0 * (DF_REAL_A + 80.0) * 0.9, "mode {mode}: {slot} slot ends");
            let mut berms = 0;
            for (_, c) in &cmds {
                let run: Vec<&str> = c.rsplit(" run ").next().unwrap_or("").split_whitespace().collect();
                // (a heap: fill ~-r ~ ~-r ~(r-1) ~(h-1) ~(r-1) ... keep, round a point beside the hull)
                let num = |s: &str| s.trim_start_matches('~').parse::<i32>().ok();
                if let Some(rest_) = c.strip_prefix("execute positioned ")
                    && run.len() == 9
                    && run[0] == "fill"
                    && run[8] == "keep"
                    && run[2] == "~"
                    && matches!((num(run[1]), num(run[4])), (Some(r0), Some(r1)) if r0 <= -3 && r1 == -r0 - 1)
                {
                    let w: Vec<&str> = rest_.split_whitespace().collect();
                    let (x, z) = (w[0].parse::<f64>().unwrap() + 0.5, w[2].parse::<f64>().unwrap() + 0.5);
                    let (a, b) = local(x, z);
                    let xl = a + DF_XP;
                    berms += 1;
                    // (out from the hull's widest just round it, as df_berms lays them; not judged by a sponson's end,
                    // where the hull's width steps within the few blocks this finds the heap's place to)
                    if (ms_half_w(xl - 12.0) - ms_half_w(xl + 12.0)).abs() > 1.0 {
                        continue;
                    }
                    let e = b.abs() - ms_half_w(xl - 7.0).max(ms_half_w(xl)).max(ms_half_w(xl + 7.0));
                    assert!(b.abs() > ms_half_w(xl), "mode {mode}: a heap under the hull at {a:.1} {b:.1}: {c}");
                    let h = num(run[5]).unwrap();
                    let bh = df_berm_h(xl, e.max(0.0));
                    assert!(f64::from(h + 1) <= bh * 1.3 + 2.5, "mode {mode}: heap {h} at e {e:.1}: {bh:.1}");
                }
            }
            assert!(berms > 200, "mode {mode}: {berms} heaps");
            for i in 0..DF_SHED {
                if let Some((x, z, tl, true)) = g.shed_land(i)
                    && (x - me[0]).hypot(z - me[2]) > 80.0
                    && (x - g.ps.0).hypot(z - g.ps.1) < 700.0
                {
                    let at = surf(x.floor() as i32, z.floor() as i32, "fill");
                    assert!(cmds.iter().any(|(t, c)| c.starts_with(&at) && (*t - tl).abs() < 0.2), "mode {mode}: shed {i}");
                }
            }
        }
    }

    fn pk_cmds(me: [f64; 3], dimension: &str) -> Vec<(f32, String)> {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        run_all(plan(&crate::lasers::PLANET_KILLER, &target, true, dimension, 37.0, me, 0))
    }
    #[test]
    fn planetkiller_fills_fit_and_reach_bedrock() {
        // every fill under the cap, nothing cleared over the build limit, the shaft down to bedrock, and every forceload
        // under 256 chunks and let go again
        for me in [[10.5, 66.0, 400.0], [900.0, 70.0, -400.0]] {
            for (dimension, sky, floor) in [("minecraft:overworld", 319, -59), ("minecraft:the_nether", 122, 5)] {
                let cmds = pk_cmds(me, dimension);
                let mut deepest = i32::MAX;
                for (t, c) in &cmds {
                    assert!(block_cost(c).unwrap_or(0) <= 32768, "{c}");
                    assert!(*t < crate::lasers::PLANET_KILLER.length, "{t}: {c}");
                    let w: Vec<&str> = c.split_whitespace().collect();
                    if w.first() == Some(&"fill") {
                        for k in [2, 5] {
                            let y = w[k].parse::<i32>().unwrap();
                            assert!(y <= sky, "{c}");
                            deepest = deepest.min(y);
                        }
                    }
                }
                assert!(deepest == floor || deepest == floor - 1, "the shaft reaches {deepest}");
                // (the square is taken again once the fissures' stretches are let go: the same rectangles, counted once;
                // each let go after it was last taken)
                let adds: std::collections::BTreeSet<&String> = cmds.iter().map(|(_, c)| c).filter(|c| c.starts_with("forceload add")).collect();
                for a in &adds {
                    let last_add = cmds.iter().filter(|(_, c)| c == *a).map(|(t, _)| *t).fold(0.0, f32::max);
                    let last_remove = cmds.iter().filter(|(_, c)| *c == a.replace("add", "remove")).map(|(t, _)| *t).fold(-1.0, f32::max);
                    assert!(last_remove >= last_add, "{a} taken again after it was let go");
                }
                let mut chunks = 0;
                for a in &adds {
                    let n: Vec<i32> = a.split_whitespace().skip(2).map(|v| v.parse().unwrap()).collect();
                    let c = ((n[2] >> 4) - (n[0] >> 4) + 1) * ((n[3] >> 4) - (n[1] >> 4) + 1);
                    assert!(c <= 256, "{a}: {c} chunks");
                    chunks += c;
                    assert!(cmds.iter().any(|(_, c)| *c == a.replace("add", "remove")), "{a} never let go");
                }
                assert!(chunks <= 1100, "{chunks} chunks");
            }
        }
    }
    #[test]
    fn planetkiller_crater_follows_the_shader() {
        // the crater is dug 3 blocks at a time when strike.wgsl starts each glowing (pk_dig_t, PK_DIG0, PK_DIG_DT), never
        // wider than its bowl, its terraces stepping in, down to bowl_d, with a lake of lava on its floor
        let laser = &crate::lasers::PLANET_KILLER;
        let cmds = pk_cmds([10.5, 66.0, 400.0], "minecraft:overworld");
        let mut layers = 0;
        for d in (0..laser.bowl_d).step_by(3) {
            let r = pk_bowl_r(d, laser.bowl_r, laser.bowl_d);
            assert!(r <= laser.bowl_r && r >= 18 && (d == 0 || r <= pk_bowl_r(d - 3, laser.bowl_r, laser.bowl_d)), "{d}: {r}");
            let (y_lo, y_hi) = (64 - d - 2, 64 - d);
            let dug: Vec<&(f32, String)> = cmds
                .iter()
                .filter(|(_, c)| {
                    let w: Vec<&str> = c.split_whitespace().collect();
                    w.len() == 8 && w[0] == "fill" && w[7] == "minecraft:air" && w[2] == y_lo.to_string() && w[5] == y_hi.to_string()
                })
                .collect();
            assert!(!dug.is_empty(), "nothing dug at {d}");
            for (t, c) in dug {
                assert!((t - pk_dig_t(d)).abs() < 1e-4, "{d}: dug at {t}, not {}", pk_dig_t(d));
                let w: Vec<i32> = c.split_whitespace().skip(1).take(6).map(|v| v.parse().unwrap()).collect();
                for x in [w[0], w[3]] {
                    assert!((x - 10).abs() <= (f64::from(r) * 1.07) as i32 + 1, "{d}: {c} wider than {r}");
                }
            }
            layers += 1;
        }
        assert_eq!(layers, (laser.bowl_d + 2) / 3);
        let floor = 64 - laser.bowl_d;
        assert!(cmds.iter().any(|(_, c)| c.ends_with("minecraft:lava replace minecraft:air") && c.contains(&format!(" {} ", floor + 1))));
    }
    #[test]
    fn planetkiller_cracks_follow_the_shader() {
        // each fissure's columns lie along the line strike.wgsl draws it on (pk_crack, pk_crack_at), are cut as its split
        // runs out to them, deepest by the crater, and every third runs with lava
        let point = [10.5, 65.0, -2.5];
        for i in 0..PK_CRACKS {
            let mut p = Plan { laser: &crate::lasers::PLANET_KILLER, ev: Vec::new(), rng: Rng::new(7), bx: 10, by: 64, bz: -3 };
            let len = pk_crack(i, 37.0).1;
            pk_fissure(&mut p, point, i, 37.0, 0.0, len / 2.0);
            pk_fissure(&mut p, point, i, 37.0, len / 2.0, len);
            let mut cols = 0;
            for (t, a) in &p.ev {
                let Act::Cmd(c) = a else { continue };
                if !c.ends_with("minecraft:air") {
                    continue;
                }
                let w: Vec<&str> = c.split_whitespace().collect();
                let (x, z) = (w[2].parse::<f64>().unwrap() + 0.5 - point[0], w[4].parse::<f64>().unwrap() + 0.5 - point[2]);
                let r = x.hypot(z);
                let u = r - PK_RIM;
                assert!(u > -5.0 && u < len + 5.0, "fissure {i}: a column {r:.1} out");
                let a = pk_crack_at(i, u.clamp(0.0, len), 37.0);
                let lat = (x * a.sin() - z * a.cos()).abs();
                assert!(lat < 5.5, "fissure {i}: a column {lat:.1} off its line");
                // (the split runs out in lurches and waits between them: a column's centre may sit either side of a wait)
                let (t0, t1) = (PK_BURST + pk_crack_time((u - 1.5).max(0.0)), PK_BURST + pk_crack_time((u + 1.5).max(0.0)));
                assert!(*t >= t0 - 0.05 && *t <= t1 + 0.05, "fissure {i}: cut at {t} at {u:.1}, not {t0}..{t1}");
                let deep: i32 = w[w.len() - 6].trim_start_matches("~-").parse().unwrap();
                assert!(deep <= 34 && (u > len * 0.2 || deep >= 25), "fissure {i}: {deep} deep at {u:.1}");
                cols += 1;
            }
            assert!(cols as f64 > len * 2.0, "fissure {i}: {cols} columns");
            let lava = p.ev.iter().any(|(_, a)| matches!(a, Act::Cmd(c) if c.ends_with("setblock ~ ~-1 ~ minecraft:lava")));
            assert_eq!(lava, i % 3 == 0, "fissure {i}");
        }
    }
    #[test]
    fn planetkiller_emitters_ring_the_target() {
        // the towers stand round the target, the first beyond it from the player, all fired by PK_IGN1, and each is heard
        // grinding up from where it stands, and each bolt striking the ring
        let point = [10.5, 65.0, -2.5];
        for me in [[10.5, 66.0, 400.0], [-300.0, 70.0, 40.0]] {
            let wing = wing_angle(point, me);
            let cmds = pk_cmds(me, "minecraft:overworld");
            for i in 0..PK_N {
                let (x, z, t) = pk_emitter(i, 37.0, point, wing);
                let r = (x - point[0]).hypot(z - point[2]);
                assert!((850.0..=1350.0).contains(&r) && (PK_RAISE..=PK_IGN1 + 0.07).contains(&t), "{i}: {r} {t}");
                let heard = cmds.iter().any(|(_, c)| c.starts_with("playsound orbital:planetkiller.rise") && c.contains(&format!("{x:.1} 65 {z:.1}")));
                assert!(heard, "{i}: its rise not heard");
            }
            let bolts = cmds.iter().filter(|(_, c)| c.starts_with("playsound orbital:planetkiller.bolt")).count();
            assert_eq!(bolts, PK_N, "every bolt heard");
            let (x, z, _) = pk_emitter(0, 37.0, point, wing);
            let (to_me, to_it) = ((me[0] - point[0], me[2] - point[2]), (x - point[0], z - point[2]));
            assert!(to_me.0 * to_it.0 + to_me.1 * to_it.1 < 0.0, "the first is not beyond the target");
        }
    }
}


#[cfg(test)]
mod tick_budget {
    use super::*;
    /// The most plan work any one tick of `laser`'s strike does: its firing, or one stage (the mod works out one a tick;
    /// the best of three runs, in milliseconds).
    fn heaviest_tick(laser: &'static Laser) -> f64 {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let mut best = f64::MAX;
        for _ in 0..3 {
            let t0 = std::time::Instant::now();
            let mut ev = plan(laser, &target, true, "minecraft:overworld", 7.0, [10.5, 66.0, 400.0], 0);
            // the firing tick, then each stage on its own (the mod works out one a tick)
            let mut worst = t0.elapsed().as_secs_f64() * 1000.0;
            while let Some((_, act)) = ev.pop() {
                if let Act::Later(job) = act {
                    let s = std::time::Instant::now();
                    let more = job();
                    worst = worst.max(s.elapsed().as_secs_f64() * 1000.0);
                    ev.extend(more);
                }
            }
            best = best.min(worst);
        }
        best
    }
    #[test]
    fn no_tick_outworks_the_proven_lasers() {
        // a mod's tick has a fuel limit, and a stage that overran it stopped the whole mod. The plasma's, godly's and
        // black hole's firing ticks (each its whole plan at once) have always fitted: no tick of any strike may do much
        // more than the heaviest of them
        let proven = [&crate::lasers::PLASMA, &crate::lasers::GODLY, &crate::lasers::BLACK_HOLE]
            .map(heaviest_tick)
            .into_iter()
            .fold(0.0, f64::max);
        for laser in crate::lasers::LASERS {
            let ms = heaviest_tick(laser);
            assert!(ms <= proven * 1.25 + 0.5, "{}: a tick of {ms:.2} ms against the proven {proven:.2} ms", laser.key);
        }
    }
}
#[cfg(test)]
mod replay {
    use super::*;
    /// A strike played out tick by tick as the mod does (lib.rs's tick_strike: one stage a tick, every due command's
    /// cost worked out), timing each tick. `cargo test --release replay -- --ignored --nocapture`, with ORBITAL_REPLAY
    /// "laser bx by bz px py pz [approach]".
    #[test]
    #[ignore]
    fn replay_ticks() {
        let a: Vec<f64> = std::env::var("ORBITAL_REPLAY").unwrap_or("5 12092 96 12416 12021.5 199.9 11811.3 0".into())
            .split_whitespace().skip(1).map(|s| s.parse().unwrap()).collect();
        let key = std::env::var("ORBITAL_REPLAY").unwrap_or("5".into()).split_whitespace().next().unwrap().parse::<usize>().unwrap();
        let laser = crate::lasers::LASERS[key];
        let target = Target { block: [a[0] as i32, a[1] as i32, a[2] as i32], point: [a[0] + 0.5, a[1] + 1.0, a[2] + 0.5] };
        let t0 = std::time::Instant::now();
        let mut plan = plan(laser, &target, true, "minecraft:overworld", 7.0, [a[3], a[4], a[5]], a.get(6).copied().unwrap_or(0.0) as usize);
        let mut worst = vec![(t0.elapsed().as_secs_f64() * 1000.0, 0.0f32, 0usize)];
        let mut next = 0;
        let mut waiting: std::collections::VecDeque<Stage> = Default::default();
        let mut ticks = 0u32;
        let mut spare = 0u64;
        while (ticks as f32) * 0.05 < laser.length {
            ticks += 1;
            let now = ticks as f32 * 0.05;
            let s = std::time::Instant::now();
            let mut n = 0;
            let out = |job: Stage, plan: &mut Vec<(f32, Act)>, next: usize| {
                let mut rest = plan.split_off(next);
                let j = std::time::Instant::now();
                let made = job();
                let first = made.iter().map(|e| e.0).fold(f32::MAX, f32::min);
                println!("stage at {now:5.2} s: {:6.2} ms, {} acts, the first due {first:5.2}, {} waiting in the plan", j.elapsed().as_secs_f64() * 1000.0, made.len(), plan.len() - next + rest.len());
                rest.extend(made);
                rest.sort_by(|a, b| a.0.total_cmp(&b.0));
                plan.extend(rest);
            };
            let mut worked = false;
            if let Some(job) = waiting.pop_front() {
                out(job, &mut plan, next);
                worked = true;
            }
            while next < plan.len() && plan[next].0 <= now {
                let (_, act) = std::mem::replace(&mut plan[next], (0.0, Act::Cmd(String::new())));
                next += 1;
                n += 1;
                match act {
                    Act::Cmd(c) => { std::hint::black_box(block_cost(&c)); }
                    Act::Spare(c) => spare += block_cost(&c).unwrap_or(1),
                    Act::Later(job) if worked => waiting.push_back(job),
                    Act::Later(job) => { out(job, &mut plan, next); worked = true; }
                    _ => {}
                }
            }
            worst.push((s.elapsed().as_secs_f64() * 1000.0, now, n));
        }
        println!("spare budget asked for: {spare} blocks");
        worst.sort_by(|a, b| b.0.total_cmp(&a.0));
        for w in worst.iter().take(8) {
            println!("{:7.2} ms at {:5.2} s, {} events", w.0, w.1, w.2);
        }
    }
    /// A strike's world changes drained through the block budget as the mod does (lib.rs's carve: BLOCK_BUDGET a tick,
    /// in order, then the spare ones), to see how many blocks it changes, how far behind their time they are made, and
    /// when it is all done. `cargo test --release carve_queue -- --ignored --nocapture`, with ORBITAL_CARVE the laser.
    #[test]
    #[ignore]
    fn carve_queue() {
        let key = std::env::var("ORBITAL_CARVE").unwrap_or("6".into()).parse::<usize>().unwrap();
        let laser = crate::lasers::LASERS[key];
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let mut ev = plan(laser, &target, true, "minecraft:overworld", 7.0, [10.5, 66.0, 400.0], 0);
        let mut all: Vec<(f32, String, bool)> = Vec::new();
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Cmd(c) => all.push((t, c, false)),
                Act::Spare(c) => all.push((t, c, true)),
                Act::Later(job) => ev.extend(job()),
                _ => {}
            }
        }
        all.sort_by(|a, b| a.0.total_cmp(&b.0));
        let blocks: u64 = all.iter().filter(|a| !a.2).filter_map(|a| block_cost(&a.1)).sum();
        let spare: u64 = all.iter().filter(|a| a.2).map(|a| block_cost(&a.1).unwrap_or(1)).sum();
        println!("{} commands; world changes {blocks} blocks, spare {spare} blocks", all.len());
        // (the kinds of command most numerous: each runs on its own, however few blocks it changes)
        let mut kinds: std::collections::BTreeMap<String, usize> = Default::default();
        for (_, c, _) in &all {
            let run = c.rsplit(" run ").next().unwrap_or(c);
            let w: Vec<&str> = run.split_whitespace().collect();
            let k = format!("{} {}", w.first().unwrap_or(&""), w.iter().find(|x| x.starts_with("minecraft:")).unwrap_or(&""));
            *kinds.entry(k).or_default() += 1;
        }
        let mut kinds: Vec<_> = kinds.into_iter().collect();
        kinds.sort_by_key(|a| std::cmp::Reverse(a.1));
        for (k, n) in kinds.iter().take(8) {
            println!("{n:6} {k}");
        }
        let budget = 20_000u64;
        let (mut queue, mut spares) = (std::collections::VecDeque::new(), std::collections::VecDeque::new());
        let (mut next, mut tick, mut done_at, mut spare_at) = (0, 0u32, 0.0f32, 0.0f32);
        let mut late: Vec<(f32, f32, String)> = Vec::new();
        let mut busy: Vec<(usize, u64, f32)> = Vec::new();
        while next < all.len() || !queue.is_empty() || !spares.is_empty() {
            tick += 1;
            let now = tick as f32 * 0.05;
            while next < all.len() && all[next].0 <= now {
                let (t, c, sp) = &all[next];
                match (sp, block_cost(c)) {
                    (true, cost) => spares.push_back((cost.unwrap_or(1), c.clone())),
                    (false, Some(cost)) => queue.push_back((*t, cost, c.clone())),
                    _ => {}
                }
                next += 1;
            }
            let mut spent = 0;
            let mut cmds = 0;
            while let Some((t, cost, _)) = queue.front() {
                if spent > 0 && (spent + cost > budget || cmds >= crate::CARVE_CMDS) {
                    break;
                }
                spent += cost;
                cmds += 1;
                late.push((*t, now - t, queue.pop_front().unwrap().2));
                done_at = now;
            }
            while queue.is_empty() && let Some((cost, _)) = spares.front() {
                if spent > 0 && (spent + cost > budget || cmds >= crate::CARVE_CMDS) {
                    break;
                }
                spent += cost;
                cmds += 1;
                spares.pop_front();
                spare_at = now;
            }
            busy.push((cmds, spent, now));
        }
        busy.sort_by_key(|a| std::cmp::Reverse(a.0));
        for (c, b, t) in busy.iter().take(5) {
            println!("{c:5} commands, {b:6} blocks in the tick at {t:5.2} s");
        }
        late.sort_by(|a, b| b.1.total_cmp(&a.1));
        // (what is seen happen: the changes due while the strike plays, not the charred land after it)
        if let Some((t, l, c)) = late.iter().find(|a| a.0 < laser.length * 0.5) {
            println!("of those due in its first half, the latest: due {t:5.2} s, made {l:5.2} s late: {}", &c[..c.len().min(100)]);
        }
        for (t, l, c) in late.iter().take(5) {
            println!("due {t:5.2} s, made {l:5.2} s late: {}", &c[..c.len().min(100)]);
        }
        println!("world changes all made by {done_at:.1} s, the spare ones by {spare_at:.1} s");
    }
}
