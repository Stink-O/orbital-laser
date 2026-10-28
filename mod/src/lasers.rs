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
    blurb: "A raging plasma beam and forked lightning. Leaves a crater of glass and obsidian ringed in fire.",
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
    blurb: "A pillar of light through parted clouds. Leaves a crater of quartz and gold, with flowers.",
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
    blurb: "A singularity tears open, bores to bedrock and drags the land into spiral arms.",
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
    blurb: "A storm of meteors, then one the size of a hill: a crater 125 blocks across.",
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
    blurb: "A kilometre-long ship drops in over the target and cuts a molten trench with its beam.",
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
    blurb: "A meteor brings the mothership down into the land, and a black hole swallows the wreck.",
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

/// The planet killer, planned in `strike::planetkiller_plan`: seven towers round the horizon, their beams feeding a ring
/// of light high over the target, and the one beam it fires coming down on it. The crater, the shaft and their lining below are its
/// own, by far the biggest of any laser; the blast, the terraces, the rim, the fissures and the ejecta are planned there.
pub const PLANET_KILLER: Laser = Laser {
    key: "planetkiller",
    index: 6,
    title: "PLANET KILLER",
    color: "blue",
    rgb: 0x4D7CFF,
    blurb: "Seven towers strike a ring in the sky with lightning. Its beam leaves a crater 480 across.",
    icon_model: "orbital:planetkiller_icon",
    length: 30.5,
    // a long way off, like the ship lasers: it is best watched from a distance
    range: 1000.0,
    scorch: &[
        (280, "minecraft:coarse_dirt", 0.08, "minecraft:grass_block"),
        (250, "minecraft:smooth_basalt", 0.08, "minecraft:sand"),
        (220, "minecraft:blackstone", 0.1, "minecraft:dirt"),
        (200, "minecraft:blackstone", 0.1, "minecraft:coarse_dirt"),
    ],
    bowl_r: 240,
    bowl_d: 80,
    bowl_rough: 0.06,
    shaft_r: 40,
    shaft_min: 36,
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

/// The crystal bloom, planned in `strike::crystalbloom_plan`: the land wakes, crystals punch up out of it and a forest of
/// spires blooms out over it, hums as one and shatters. The crater below is its geode: a bowl lined with amethyst over
/// calcite and basalt round a crystal-lined well to bedrock where its heart stood; the stumps of its spires, the broken
/// pieces lying by them, the fissures and the shards strewn over the land are planned there.
pub const CRYSTAL_BLOOM: Laser = Laser {
    key: "crystalbloom",
    index: 7,
    title: "CRYSTAL BLOOM",
    color: "light_purple",
    rgb: 0xE07BFF,
    blurb: "A forest of crystal spires bursts from the land, hums as one and shatters in a flash of colour.",
    icon_model: "orbital:crystalbloom_icon",
    length: 60.0,
    range: 1000.0,
    scorch: &[],
    bowl_r: 88,
    bowl_d: 28,
    bowl_rough: 0.05,
    shaft_r: 10,
    shaft_min: 10,
    shaft_rough: 0.0,
    lining: &[
        ("minecraft:amethyst_block", 0.45),
        ("minecraft:calcite", 0.3),
        ("minecraft:smooth_basalt", 0.25),
    ],
    bowl_floor: ("minecraft:amethyst_block", 0.1, "minecraft:calcite"),
    bottom: &[(6, 0, 0, "minecraft:amethyst_block")],
    particle_a: "particle minecraft:end_rod {x} {y} {z} {r} 3 {r} 0.1 40 force",
    particle_b: "particle minecraft:glow {x} {y} {z} {r} 2 {r} 0 20 force",
};

/// The sinkhole, planned in `strike::sinkhole_plan` (strike/sinkhole.rs): no beam and nothing from the sky. The land round
/// the target trembles and cracks, a patch of it gives, then it caves in from the middle out, slab by slab, into a pit
/// down to bedrock, dust billowing up out of it. The crater fields below are only what the shared tests read: the pit,
/// its jagged walls, the ledges and the rubble at its foot are planned there.
pub const SINKHOLE: Laser = Laser {
    key: "sinkhole",
    index: 8,
    title: "SINKHOLE",
    color: "gold",
    rgb: 0xD2A257,
    blurb: "The land trembles, cracks and caves in: a pit hundreds of blocks across, down to bedrock.",
    icon_model: "orbital:sinkhole_icon",
    length: 34.0,
    range: 1000.0,
    scorch: &[],
    bowl_r: 112,
    bowl_d: 124,
    bowl_rough: 0.1,
    shaft_r: 0,
    shaft_min: 0,
    shaft_rough: 0.0,
    lining: &[("minecraft:stone", 1.0)],
    bowl_floor: ("minecraft:cobblestone", 0.0, "minecraft:stone"),
    bottom: &[],
    particle_a: "particle minecraft:block{block_state:\"minecraft:dirt\"} {x} {y} {z} {r} 3 {r} 0.2 40 force",
    particle_b: "particle minecraft:block{block_state:\"minecraft:stone\"} {x} {y} {z} {r} 2 {r} 0.2 20 force",
};

pub const LASERS: [&Laser; 9] = [&PLASMA, &GODLY, &BLACK_HOLE, &METEOR, &MOTHERSHIP, &DOWNFALL, &PLANET_KILLER, &CRYSTAL_BLOOM, &SINKHOLE];

/// The ship lasers: they share the mothership's arrival and its approach and arrival choices.
pub fn is_ship(l: &Laser) -> bool {
    l.key == "mothership" || l.key == "downfall"
}
