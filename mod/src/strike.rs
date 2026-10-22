//! A strike's plan: every command and sound it makes, at the second it makes
//! it. The mod plays the plan out tick by tick (`world.run-commands`, run at
//! operator level and silently, so nothing reaches the chat).
use crate::lasers::Laser;
use std::f64::consts::PI;

/// Strike clock of the impact (the shader's T_FIRE).
pub const FIRE: f32 = 4.0;
/// How long a strike runs, light and aftermath.
pub const LENGTH: f32 = 26.0;
/// Mobs and dropped items this close to the impact die (players are spared).
const KILL_RADIUS: i32 = 40;
/// Godly: the six quartz pillars (and the shader's pillars of light) stand on
/// this circle, the first at this angle. Keep in step with strike.wgsl.
const PILLAR_R: f64 = 40.0;
const PILLAR_A0: f64 = PI / 6.0;

pub enum Act {
    Cmd(String),
    /// A sound that follows the player.
    Sound { event: String, volume: f32, pitch: f32 },
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

/// `then`, run on the ground at column (x, z): `~ ~ ~` is the first air block above the surface.
fn surf(x: i32, z: i32, then: &str) -> String {
    format!("execute positioned {x} 0 {z} positioned over motion_blocking_no_leaves run {then}")
}

struct Plan<'a> {
    laser: &'a Laser,
    ev: Vec<(f32, Act)>,
    rng: Rng,
    bx: i32,
    by: i32,
    bz: i32,
}

impl Plan<'_> {
    fn at(&mut self, t: f32, cmd: impl Into<String>) {
        self.ev.push((t, Act::Cmd(cmd.into())));
    }
    /// A vanilla sound, `vol` out of 10.
    fn sound(&mut self, t: f32, name: &str, vol: f32, pitch: f64) {
        self.ev.push((
            t,
            Act::Sound {
                event: format!("minecraft:{name}"),
                volume: (vol / 10.0).min(1.0),
                pitch: pitch as f32,
            },
        ));
    }
    /// One of the laser's own sounds.
    fn csound(&mut self, t: f32, role: &str, vol: f32, pitch: f32) {
        let event = self.laser.sound(role);
        self.ev.push((t, Act::Sound { event, volume: (vol / 10.0).min(1.0), pitch }));
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

/// Everything a strike of `laser` at `target` does. `me` is where the player
/// stands (godly's wings face them); `dimension` picks the bedrock floor.
pub fn plan(laser: &Laser, target: &Target, terrain: bool, dimension: &str) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let r2 = |v: f64| (v * 100.0).round() / 100.0;
    let (tx, ty, tz) = (r2(target.point[0]), r2(target.point[1]), r2(target.point[2]));
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let plasma = laser.key == "plasma";
    let godly = laser.key == "godly";
    let t = FIRE;

    // charge, lock-on, impact
    p.csound(0.0, "charge", 10.0, 1.0);
    p.csound(3.4, "lockon", 8.0, 1.0);
    p.at(3.5, format!(r#"title @s actionbar {{"text":"ORBITAL LASER: LOCKED  [{}]","color":"{}","bold":true}}"#, laser.title, laser.color));
    p.csound(t, "fire", 10.0, 1.0);
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
            p.sound(t + 0.05 + k as f32 * 0.07, name, 10.0, pitch);
        }
        for _ in 0..10 {
            let dt = p.rng.uniform(0.0, 2.5) as f32;
            let name = *p.rng.pick(&["block.stone.break", "block.gravel.break"]);
            let pitch = p.rng.uniform(0.6, 1.1);
            p.sound(t + 1.0 + dt, name, 6.0, pitch);
        }
    }

    // ---- particles in the world ----
    let shard = if plasma { "minecraft:blackstone" } else { "minecraft:calcite" };
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

    if terrain {
        let r_mouth = laser.shaft_r;
        let bedrock_top = match dimension {
            "minecraft:overworld" => -59,
            "minecraft:the_nether" => 5,
            _ => 1,
        };
        let floor_y = bedrock_top;
        // 1. the blast: everything standing above the ground in a wide disc is vaporised
        for c in p.disc(44, by + 1, by + 60, "minecraft:air", 0.12, None) {
            p.at(t + 0.15, c);
        }
        // 2. scorched earth: what the ground round the crater turns into
        for &(rad, block, rough, repl) in laser.scorch {
            for c in p.disc(rad, by - 3, by + 1, block, f64::from(rough), Some(repl)) {
                let dt = p.rng.next() as f32 * 2.2;
                p.at(t + 0.4 + dt, c);
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
                p.sound(tl + dt, name, 9.0, pitch);
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
            p.sound(ts, if y_hi < 0 { "block.deepslate.break" } else { "block.stone.break" }, 8.0, pitch);
            if i % 2 == 0 {
                let pitch = p.rng.uniform(0.6, 0.9);
                p.sound(ts + 0.1, "block.gravel.break", 6.0, pitch);
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

/// The godly wings' facing: from the impact towards the player, in the xz plane.
pub fn wing_angle(target: [f64; 3], me: [f64; 3]) -> f32 {
    (me[2] - target[2]).atan2(me[0] - target[0]) as f32
}
