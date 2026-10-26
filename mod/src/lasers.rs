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
    /// Seconds a strike runs, light and aftermath.
    pub length: f32,
    /// Blocks the designator reaches with it (the raycast stops at 1024; past the render distance it needs LOD Distance).
    pub range: f32,
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
    length: 26.0,
    range: 200.0,
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
    length: 26.0,
    range: 200.0,
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

pub const BLACK_HOLE: Laser = Laser {
    key: "blackhole",
    index: 2,
    title: "BLACK HOLE",
    color: "light_purple",
    rgb: 0xB070FF,
    blurb: "A singularity tears open over the target. Light bends round it, an accretion disk spins up and its jet bores to bedrock. Drags the land into spiral arms and pulls rock up after it, then evaporates in a blinding flash.",
    icon_model: "orbital:blackhole_icon",
    length: 26.0,
    range: 200.0,
    scorch: &[
        (48, "minecraft:sculk", 0.12, "minecraft:grass_block"),
        (44, "minecraft:tuff", 0.12, "minecraft:sand"),
        (41, "minecraft:deepslate", 0.12, "minecraft:dirt"),
    ],
    bowl_r: 34,
    bowl_d: 20,
    bowl_rough: 0.05,
    shaft_r: 8,
    shaft_min: 8,
    shaft_rough: 0.0,
    lining: &[
        ("minecraft:obsidian", 0.35),
        ("minecraft:crying_obsidian", 0.25),
        ("minecraft:black_concrete", 0.2),
        ("minecraft:sculk", 0.12),
        ("minecraft:amethyst_block", 0.08),
    ],
    bowl_floor: ("minecraft:crying_obsidian", 0.1, "minecraft:obsidian"),
    bottom: &[
        (4, 0, 0, "minecraft:crying_obsidian"),
        (2, 1, 1, "minecraft:amethyst_block"),
        (1, 2, 3, "minecraft:obsidian"),
    ],
    particle_a: "particle minecraft:portal {x} {y} {z} {r} 3 {r} 3 220 force",
    particle_b: "particle minecraft:reverse_portal {x} {y} {z} {r} 2 {r} 0.2 60 force",
};

/// The storm and the extinction impact are planned in `strike::meteor_plan`; the crater, the shaft and their lining
/// below are the big one's.
pub const METEOR: Laser = Laser {
    key: "meteor",
    index: 3,
    title: "METEOR STORM",
    color: "red",
    rgb: 0xFF7A3A,
    blurb: "A storm of meteors pounds the land for 120 blocks round the target, each leaving its own crater. Then one the size of a hill comes down on it: a fireball, a crater 125 blocks across and a shaft to bedrock, the land charred out to 135 blocks.",
    icon_model: "orbital:meteor_icon",
    length: 38.0,
    range: 200.0,
    scorch: &[
        (135, "minecraft:coarse_dirt", 0.1, "minecraft:grass_block"),
        (130, "minecraft:smooth_basalt", 0.1, "minecraft:sand"),
        (110, "minecraft:blackstone", 0.12, "minecraft:coarse_dirt"),
        (110, "minecraft:blackstone", 0.12, "minecraft:dirt"),
        (84, "minecraft:magma_block", 0.15, "minecraft:blackstone"),
    ],
    bowl_r: 62,
    bowl_d: 34,
    bowl_rough: 0.08,
    shaft_r: 11,
    shaft_min: 8,
    shaft_rough: 0.05,
    lining: &[
        ("minecraft:blackstone", 0.35),
        ("minecraft:magma_block", 0.25),
        ("minecraft:obsidian", 0.2),
        ("minecraft:basalt", 0.1),
        ("minecraft:tuff", 0.1),
    ],
    bowl_floor: ("minecraft:magma_block", 0.25, "minecraft:blackstone"),
    bottom: &[(6, 0, 0, "minecraft:magma_block"), (5, 1, 4, "minecraft:lava")],
    particle_a: "particle minecraft:lava {x} {y} {z} {r} 2 {r} 0 50 force",
    particle_b: "particle minecraft:flame {x} {y} {z} {r} 2 {r} 0.1 60 force",
};

/// The ship, its beam and the trench it cuts are planned in `strike::mothership_plan`; the crater, the shaft and their
/// lining below are where the beam first comes down, and the trench is lined the same way.
pub const MOTHERSHIP: Laser = Laser {
    key: "mothership",
    index: 4,
    title: "MOTHERSHIP",
    color: "green",
    rgb: 0x3FE05A,
    blurb: "A slab of dark metal a kilometre long drops out of hyperspace and stops dead over the target, its shadow across the land. Its green beam drills a shaft to bedrock, then sweeps away from you, cutting a molten trench 100 blocks long, and the ship is gone.",
    icon_model: "orbital:mothership_icon",
    length: 34.0,
    // a long way off: past the render distance it aims across the distant terrain (LOD Distance on)
    range: 1000.0,
    scorch: &[
        (40, "minecraft:blackstone", 0.12, "minecraft:grass_block"),
        (36, "minecraft:smooth_basalt", 0.12, "minecraft:sand"),
        (34, "minecraft:coarse_dirt", 0.12, "minecraft:dirt"),
    ],
    bowl_r: 22,
    bowl_d: 14,
    bowl_rough: 0.08,
    shaft_r: 7,
    shaft_min: 5,
    shaft_rough: 0.04,
    lining: &[
        ("minecraft:obsidian", 0.35),
        ("minecraft:magma_block", 0.22),
        ("minecraft:tinted_glass", 0.18),
        ("minecraft:smooth_basalt", 0.15),
        ("minecraft:cyan_stained_glass", 0.1),
    ],
    bowl_floor: ("minecraft:magma_block", 0.25, "minecraft:obsidian"),
    bottom: &[(4, 0, 0, "minecraft:magma_block"), (3, 1, 3, "minecraft:lava")],
    particle_a: "particle minecraft:flame {x} {y} {z} {r} 3 {r} 0.2 50 force",
    particle_b: "particle minecraft:lava {x} {y} {z} {r} 1 {r} 0 20 force",
};

/// The mothership's last stand, planned in `strike::downfall_plan`: the crater, shaft and lining below are the black
/// hole's, where the ship's stern comes down and its engine ruptures; the meteor's hits, the crash and its gouge are
/// planned there too.
pub const DOWNFALL: Laser = Laser {
    key: "downfall",
    index: 5,
    title: "DOWNFALL",
    color: "dark_red",
    rgb: 0xE8424F,
    blurb: "The mothership drops in and charges, then turns its roof batteries on a meteor coming down on it. It breaks the rock up, the pieces hit it anyway, and the ship falls out of the sky and ploughs into the land. Then the black hole engine in its stern ruptures and swallows the wreck.",
    icon_model: "orbital:downfall_icon",
    length: 64.0,
    range: 1000.0,
    scorch: &[
        (60, "minecraft:sculk", 0.12, "minecraft:grass_block"),
        (56, "minecraft:tuff", 0.12, "minecraft:sand"),
        (52, "minecraft:deepslate", 0.12, "minecraft:dirt"),
    ],
    bowl_r: 30,
    bowl_d: 18,
    bowl_rough: 0.06,
    shaft_r: 8,
    shaft_min: 7,
    shaft_rough: 0.03,
    lining: &[
        ("minecraft:blackstone", 0.3),
        ("minecraft:basalt", 0.2),
        ("minecraft:obsidian", 0.15),
        ("minecraft:tuff", 0.2),
        ("minecraft:magma_block", 0.05),
        ("minecraft:cobbled_deepslate", 0.1),
    ],
    bowl_floor: ("minecraft:crying_obsidian", 0.1, "minecraft:obsidian"),
    bottom: &[(4, 0, 0, "minecraft:crying_obsidian"), (2, 1, 2, "minecraft:obsidian")],
    particle_a: "particle minecraft:portal {x} {y} {z} {r} 3 {r} 3 120 force",
    particle_b: "particle minecraft:reverse_portal {x} {y} {z} {r} 2 {r} 0.2 40 force",
};

/// The planet killer, planned in `strike::planetkiller_plan`: seven towers round the horizon, their beams meeting high
/// over the target, and the one beam they make coming down on it. The crater, the shaft and their lining below are its
/// own, by far the biggest of any laser; the blast, the terraces, the rim, the fissures and the ejecta are planned there.
pub const PLANET_KILLER: Laser = Laser {
    key: "planetkiller",
    index: 6,
    title: "PLANET KILLER",
    color: "blue",
    rgb: 0x4D7CFF,
    blurb: "Seven towers tear up out of the land on the horizon and fire columns of light that bend over and meet high above the target. They fuse and one beam comes down: the land domes up and bursts, and it leaves a crater 260 blocks across and 70 deep, fissures splitting the land for 300 blocks and a mushroom cloud.",
    icon_model: "orbital:planetkiller_icon",
    length: 26.0,
    // a long way off, like the ship lasers: it is best watched from a distance
    range: 1000.0,
    scorch: &[
        (280, "minecraft:coarse_dirt", 0.08, "minecraft:grass_block"),
        (250, "minecraft:smooth_basalt", 0.08, "minecraft:sand"),
        (220, "minecraft:blackstone", 0.1, "minecraft:dirt"),
        (200, "minecraft:blackstone", 0.1, "minecraft:coarse_dirt"),
    ],
    bowl_r: 130,
    bowl_d: 70,
    bowl_rough: 0.06,
    shaft_r: 16,
    shaft_min: 11,
    shaft_rough: 0.04,
    lining: &[
        ("minecraft:obsidian", 0.3),
        ("minecraft:blackstone", 0.2),
        ("minecraft:tinted_glass", 0.15),
        ("minecraft:magma_block", 0.15),
        ("minecraft:blue_stained_glass", 0.1),
        ("minecraft:smooth_basalt", 0.1),
    ],
    bowl_floor: ("minecraft:magma_block", 0.2, "minecraft:obsidian"),
    bottom: &[(10, 0, 0, "minecraft:magma_block"), (9, 1, 5, "minecraft:lava")],
    particle_a: "particle minecraft:soul_fire_flame {x} {y} {z} {r} 3 {r} 0.2 60 force",
    particle_b: "particle minecraft:lava {x} {y} {z} {r} 1 {r} 0 25 force",
};

pub const LASERS: [&Laser; 7] = [&PLASMA, &GODLY, &BLACK_HOLE, &METEOR, &MOTHERSHIP, &DOWNFALL, &PLANET_KILLER];

/// The ship lasers: they share the mothership's arrival and its approach and arrival choices.
pub fn is_ship(l: &Laser) -> bool {
    l.key == "mothership" || l.key == "downfall"
}
