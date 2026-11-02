package dev.orbital;

import java.util.List;

/** The lasers: one entry per look, from the original mod's lasers.rs. */
public record Laser(
		String key, int index, String title, String color, int rgb, String blurb, float length, float range,
		Scorch[] scorch, int bowlR, int bowlD, double bowlRough, int shaftR, int shaftMin, double shaftRough,
		Lining[] lining, Floor bowlFloor, Bottom[] bottom, String particleA, String particleB) {

	public record Scorch(int radius, String block, double rough, String replace) {}
	public record Lining(String block, float share) {}
	public record Floor(String block, double rough, String replace) {}
	public record Bottom(int radius, int from, int to, String block) {}

	private static final String M = "minecraft:";

	/** The sound event for a role (charge, lockon, fire, beam, rumble, accent, collapse, shutdown). */
	public String sound(String role) {
		if (role.equals("collapse")) {
			return "orbital:collapse";
		}
		if (key.equals("plasma")) {
			return role.equals("accent") ? "orbital:crackle" : "orbital:" + role;
		}
		return "orbital:" + key + "." + role;
	}

	private static Scorch s(int r, String b, double rough, String repl) {
		return new Scorch(r, M + b, rough, M + repl);
	}

	private static Lining l(String b, float share) {
		return new Lining(M + b, share);
	}

	private static Bottom b(int r, int from, int to, String block) {
		return new Bottom(r, from, to, M + block);
	}

	public static final Laser PLASMA = new Laser("plasma", 0, "PLASMA", "aqua", 0x55D8FF,
			"A raging plasma beam and forked lightning. Leaves a crater of glass and obsidian ringed in fire.", 26f, 200f,
			new Scorch[] {s(46, "blackstone", 0.15, "grass_block"), s(42, "smooth_basalt", 0.15, "sand"), s(39, "coarse_dirt", 0.15, "dirt")},
			32, 16, 0.14, 9, 3, 0.06,
			new Lining[] {l("obsidian", 0.35f), l("black_stained_glass", 0.25f), l("tinted_glass", 0.15f), l("magma_block", 0.15f), l("smooth_basalt", 0.10f)},
			new Floor(M + "magma_block", 0.2, M + "obsidian"),
			new Bottom[] {b(3, 0, 0, "magma_block"), b(2, 1, 3, "lava")},
			"particle minecraft:flame {x} {y} {z} {r} 3 {r} 0.25 60 force", "particle minecraft:lava {x} {y} {z} {r} 1 {r} 0 25 force");

	public static final Laser GODLY = new Laser("godly", 1, "GODLY", "yellow", 0xFFD55A,
			"A pillar of light through parted clouds. Leaves a crater of quartz and gold, with flowers.", 26f, 200f,
			new Scorch[] {s(42, "smooth_quartz", 0.0, "grass_block"), s(38, "smooth_quartz", 0.0, "sand"), s(36, "calcite", 0.0, "dirt")},
			28, 14, 0.0, 6, 6, 0.0,
			new Lining[] {l("smooth_quartz", 0.45f), l("calcite", 0.3f), l("gold_block", 0.12f), l("quartz_bricks", 0.13f)},
			new Floor(M + "gold_block", 0.0, M + "smooth_quartz"),
			new Bottom[] {b(4, 0, 0, "gold_block"), b(3, 1, 1, "sea_lantern"), b(1, 2, 8, "glowstone")},
			"particle minecraft:end_rod {x} {y} {z} {r} 3 {r} 0.15 80 force", "particle minecraft:wax_on {x} {y} {z} {r} 2 {r} 0.5 40 force");

	public static final Laser BLACK_HOLE = new Laser("blackhole", 2, "BLACK HOLE", "light_purple", 0xB070FF,
			"A singularity tears open, bores to bedrock and drags the land into spiral arms.", 26f, 200f,
			new Scorch[] {s(48, "sculk", 0.12, "grass_block"), s(44, "tuff", 0.12, "sand"), s(41, "deepslate", 0.12, "dirt")},
			34, 20, 0.05, 8, 8, 0.0,
			new Lining[] {l("obsidian", 0.35f), l("crying_obsidian", 0.25f), l("black_concrete", 0.2f), l("sculk", 0.12f), l("amethyst_block", 0.08f)},
			new Floor(M + "crying_obsidian", 0.1, M + "obsidian"),
			new Bottom[] {b(4, 0, 0, "crying_obsidian"), b(2, 1, 1, "amethyst_block"), b(1, 2, 3, "obsidian")},
			"particle minecraft:portal {x} {y} {z} {r} 3 {r} 3 220 force", "particle minecraft:reverse_portal {x} {y} {z} {r} 2 {r} 0.2 60 force");

	public static final Laser METEOR = new Laser("meteor", 3, "METEOR STORM", "red", 0xFF7A3A,
			"A storm of meteors, then one the size of a hill: a crater 125 blocks across.", 38f, 200f,
			new Scorch[] {s(135, "coarse_dirt", 0.1, "grass_block"), s(130, "smooth_basalt", 0.1, "sand"), s(110, "blackstone", 0.12, "coarse_dirt"),
					s(110, "blackstone", 0.12, "dirt"), s(84, "magma_block", 0.15, "blackstone")},
			62, 34, 0.08, 11, 8, 0.05,
			new Lining[] {l("blackstone", 0.35f), l("magma_block", 0.25f), l("obsidian", 0.2f), l("basalt", 0.1f), l("tuff", 0.1f)},
			new Floor(M + "magma_block", 0.25, M + "blackstone"),
			new Bottom[] {b(6, 0, 0, "magma_block"), b(5, 1, 4, "lava")},
			"particle minecraft:lava {x} {y} {z} {r} 2 {r} 0 50 force", "particle minecraft:flame {x} {y} {z} {r} 2 {r} 0.1 60 force");

	public static final Laser MOTHERSHIP = new Laser("mothership", 4, "MOTHERSHIP", "green", 0x3FE05A,
			"A kilometre-long ship drops in over the target and cuts a molten trench with its beam.", 34f, 1000f,
			new Scorch[] {s(40, "blackstone", 0.12, "grass_block"), s(36, "smooth_basalt", 0.12, "sand"), s(34, "coarse_dirt", 0.12, "dirt")},
			22, 14, 0.08, 7, 5, 0.04,
			new Lining[] {l("obsidian", 0.35f), l("magma_block", 0.22f), l("tinted_glass", 0.18f), l("smooth_basalt", 0.15f), l("cyan_stained_glass", 0.1f)},
			new Floor(M + "magma_block", 0.25, M + "obsidian"),
			new Bottom[] {b(4, 0, 0, "magma_block"), b(3, 1, 3, "lava")},
			"particle minecraft:flame {x} {y} {z} {r} 3 {r} 0.2 50 force", "particle minecraft:lava {x} {y} {z} {r} 1 {r} 0 20 force");

	public static final Laser DOWNFALL = new Laser("downfall", 5, "DOWNFALL", "dark_red", 0xE8424F,
			"A meteor brings the mothership down into the land, and a black hole swallows the wreck.", 64f, 1000f,
			new Scorch[] {s(60, "sculk", 0.12, "grass_block"), s(56, "tuff", 0.12, "sand"), s(52, "deepslate", 0.12, "dirt")},
			30, 18, 0.06, 8, 7, 0.03,
			new Lining[] {l("blackstone", 0.3f), l("basalt", 0.2f), l("obsidian", 0.15f), l("tuff", 0.2f), l("magma_block", 0.05f), l("cobbled_deepslate", 0.1f)},
			new Floor(M + "crying_obsidian", 0.1, M + "obsidian"),
			new Bottom[] {b(4, 0, 0, "crying_obsidian"), b(2, 1, 2, "obsidian")},
			"particle minecraft:portal {x} {y} {z} {r} 3 {r} 3 120 force", "particle minecraft:reverse_portal {x} {y} {z} {r} 2 {r} 0.2 40 force");

	public static final Laser PLANET_KILLER = new Laser("planetkiller", 6, "PLANET KILLER", "blue", 0x4D7CFF,
			"Seven towers strike a ring in the sky with lightning. Its beam leaves a crater 480 across.", 30.5f, 1000f,
			new Scorch[] {s(280, "coarse_dirt", 0.08, "grass_block"), s(250, "smooth_basalt", 0.08, "sand"), s(220, "blackstone", 0.1, "dirt"),
					s(200, "blackstone", 0.1, "coarse_dirt")},
			240, 80, 0.06, 40, 36, 0.04,
			new Lining[] {l("obsidian", 0.3f), l("blackstone", 0.2f), l("tinted_glass", 0.15f), l("magma_block", 0.15f), l("blue_stained_glass", 0.1f), l("smooth_basalt", 0.1f)},
			new Floor(M + "magma_block", 0.2, M + "obsidian"),
			new Bottom[] {b(10, 0, 0, "magma_block"), b(9, 1, 5, "lava")},
			"particle minecraft:soul_fire_flame {x} {y} {z} {r} 3 {r} 0.2 60 force", "particle minecraft:lava {x} {y} {z} {r} 1 {r} 0 25 force");

	public static final Laser CRYSTAL_BLOOM = new Laser("crystalbloom", 7, "CRYSTAL BLOOM", "light_purple", 0xE07BFF,
			"A forest of crystal spires bursts from the land, hums as one and shatters in a flash of colour.", 60f, 1000f,
			new Scorch[] {}, 88, 28, 0.05, 10, 10, 0.0,
			new Lining[] {l("amethyst_block", 0.45f), l("calcite", 0.3f), l("smooth_basalt", 0.25f)},
			new Floor(M + "amethyst_block", 0.1, M + "calcite"),
			new Bottom[] {b(6, 0, 0, "amethyst_block")},
			"particle minecraft:end_rod {x} {y} {z} {r} 3 {r} 0.1 40 force", "particle minecraft:glow {x} {y} {z} {r} 2 {r} 0 20 force");

	public static final Laser SINKHOLE = new Laser("sinkhole", 8, "SINKHOLE", "gold", 0xD2A257,
			"The land trembles, cracks and caves in: a pit hundreds of blocks across, down to bedrock.", 40f, 1000f,
			new Scorch[] {}, 112, 124, 0.1, 0, 0, 0.0,
			new Lining[] {l("stone", 1.0f)}, new Floor(M + "cobblestone", 0.0, M + "stone"), new Bottom[] {},
			"particle minecraft:block{block_state:\"minecraft:dirt\"} {x} {y} {z} {r} 3 {r} 0.2 40 force",
			"particle minecraft:block{block_state:\"minecraft:stone\"} {x} {y} {z} {r} 2 {r} 0.2 20 force");

	public static final Laser PAYLOAD = new Laser("payload", 9, "PAYLOAD", "gold", 0xFF8A2E,
			"A light in the sky drifts, loops and dives. Then a column of smoke and a wall of dust.", 70f, 1000f,
			new Scorch[] {}, 21, 9, 0.1, 0, 0, 0.0,
			new Lining[] {l("coarse_dirt", 1.0f)}, new Floor(M + "coarse_dirt", 0.0, M + "dirt"), new Bottom[] {},
			"particle minecraft:block{block_state:\"minecraft:dirt\"} {x} {y} {z} {r} 3 {r} 0.2 40 force",
			"particle minecraft:campfire_signal_smoke {x} {y} {z} {r} 2 {r} 0.02 20 force");

	public static final Laser NUKE = new Laser("nuke", 10, "NUKE", "yellow", 0xFFE14D,
			"A bomb falls and bursts over the land: a blinding flash, a mushroom cloud and a shockwave.", 90f, 1000f,
			new Scorch[] {}, 50, 18, 0.1, 0, 0, 0.0,
			new Lining[] {l("blackstone", 1.0f)}, new Floor(M + "blackstone", 0.0, M + "coarse_dirt"), new Bottom[] {},
			"particle minecraft:block{block_state:\"minecraft:dirt\"} {x} {y} {z} {r} 3 {r} 0.2 40 force",
			"particle minecraft:campfire_signal_smoke {x} {y} {z} {r} 2 {r} 0.02 20 force");

	public static final List<Laser> ALL = List.of(PLASMA, GODLY, BLACK_HOLE, METEOR, MOTHERSHIP, DOWNFALL, PLANET_KILLER,
			CRYSTAL_BLOOM, SINKHOLE, PAYLOAD, NUKE);

	/**
	 * The lasers with their finished screen visuals (the original's shaders, translated): these are the ones the menu lists. The
	 * others (Downfall, Planet Killer, Crystal Bloom, Sinkhole) have no shader yet and still answer to their commands.
	 */
	public static final List<Laser> READY = List.of(PLASMA, GODLY, BLACK_HOLE, METEOR, MOTHERSHIP, PAYLOAD, NUKE);

	public static Laser byKey(String key) {
		return ALL.stream().filter(x -> x.key().equals(key)).findFirst().orElse(null);
	}

	public boolean isShip() {
		return key.equals("mothership") || key.equals("downfall");
	}
}
