//! The lasers: one entry per look. Each says which shader laser to run, how it
//! is shown, which sounds it uses, and how it scars the world (what the ground
//! turns into, the crater, the shaft, what sits at the bottom). What each one
//! leaves behind beyond the crater lives in `strike.rs`.

pub struct Laser {
    /// Settings key and sound prefix (the plasma set has none).
    pub key: &'static str,
    /// The shader's laser number (`frame.mod_params[1].w`).
    pub index: u32,
    pub title: &'static str,
    /// Minecraft text colour for the action bar.
    pub color: &'static str,
    /// The wheel's accent, 0xRRGGBB.
    pub rgb: u32,
    pub blurb: &'static str,
    /// The item model its segment of the wheel shows.
    pub icon_model: &'static str,
    /// (radius, block, roughness, replace): what the ground round the crater turns into, in order.
    pub scorch: &'static [(i32, &'static str, f32, &'static str)],
    pub bowl_r: i32,
    pub bowl_d: i32,
    pub bowl_rough: f32,
    /// Shaft radius at the mouth, and the radius the funnel narrows to.
    pub shaft_r: i32,
    pub shaft_min: i32,
    pub shaft_rough: f32,
    /// (block, share): what the crater walls fuse into, mottled by share. The first is the base.
    pub lining: &'static [(&'static str, f32)],
    /// (block, roughness, replace) laid on the bowl floor.
    pub bowl_floor: (&'static str, f32, &'static str),
    /// (radius, y from, y to, block) at the bottom of the shaft.
    pub bottom: &'static [(i32, i32, i32, &'static str)],
    /// Thrown into the shaft as it deepens: {x} {y} {z} {r} are filled in.
    pub particle_a: &'static str,
    pub particle_b: &'static str,
}

impl Laser {
    /// The sound event for a role (charge, lockon, fire, beam, rumble, accent, collapse, shutdown).
    pub fn sound(&self, role: &str) -> String {
        match (self.key, role) {
            (_, "collapse") => "orbital:collapse".into(),
            ("plasma", "accent") => "orbital:crackle".into(),
            ("plasma", _) => format!("orbital:{role}"),
            (key, _) => format!("orbital:{key}.{role}"),
        }
    }
}

pub const PLASMA: Laser = Laser {
    key: "plasma",
    index: 0,
    title: "PLASMA",
    color: "aqua",
    rgb: 0x55D8FF,
    blurb: "A raging plasma beam and forked lightning. Fuses the crater into glass and obsidian, rings it with fire and throws rubble far and wide.",
    icon_model: "orbital:plasma_icon",
    scorch: &[
        (46, "minecraft:blackstone", 0.15, "minecraft:grass_block"),
        (42, "minecraft:smooth_basalt", 0.15, "minecraft:sand"),
        (39, "minecraft:coarse_dirt", 0.15, "minecraft:dirt"),
    ],
    bowl_r: 32,
    bowl_d: 16,
    bowl_rough: 0.14,
    shaft_r: 9,
    shaft_min: 3,
    shaft_rough: 0.06,
    lining: &[
        ("minecraft:obsidian", 0.35),
        ("minecraft:black_stained_glass", 0.25),
        ("minecraft:tinted_glass", 0.15),
        ("minecraft:magma_block", 0.15),
        ("minecraft:smooth_basalt", 0.10),
    ],
    bowl_floor: ("minecraft:magma_block", 0.2, "minecraft:obsidian"),
    bottom: &[(3, 0, 0, "minecraft:magma_block"), (2, 1, 3, "minecraft:lava")],
    particle_a: "particle minecraft:flame {x} {y} {z} {r} 3 {r} 0.25 60 force",
    particle_b: "particle minecraft:lava {x} {y} {z} {r} 1 {r} 0 25 force",
};

pub const GODLY: Laser = Laser {
    key: "godly",
    index: 1,
    title: "GODLY",
    color: "yellow",
    rgb: 0xFFD55A,
    blurb: "The clouds part and a pillar of light comes down. Leaves a crater of quartz and gold, a sigil in the ground, flowers blooming outwards and rock left hanging in the air.",
    icon_model: "orbital:godly_icon",
    scorch: &[
        (42, "minecraft:smooth_quartz", 0.0, "minecraft:grass_block"),
        (38, "minecraft:smooth_quartz", 0.0, "minecraft:sand"),
        (36, "minecraft:calcite", 0.0, "minecraft:dirt"),
    ],
    bowl_r: 28,
    bowl_d: 14,
    bowl_rough: 0.0,
    shaft_r: 6,
    shaft_min: 6,
    shaft_rough: 0.0,
    lining: &[
        ("minecraft:smooth_quartz", 0.45),
        ("minecraft:calcite", 0.3),
        ("minecraft:gold_block", 0.12),
        ("minecraft:quartz_bricks", 0.13),
    ],
    bowl_floor: ("minecraft:gold_block", 0.0, "minecraft:smooth_quartz"),
    bottom: &[
        (4, 0, 0, "minecraft:gold_block"),
        (3, 1, 1, "minecraft:sea_lantern"),
        (1, 2, 8, "minecraft:glowstone"),
    ],
    particle_a: "particle minecraft:end_rod {x} {y} {z} {r} 3 {r} 0.15 80 force",
    particle_b: "particle minecraft:wax_on {x} {y} {z} {r} 2 {r} 0.5 40 force",
};

pub const LASERS: [&Laser; 2] = [&PLASMA, &GODLY];
