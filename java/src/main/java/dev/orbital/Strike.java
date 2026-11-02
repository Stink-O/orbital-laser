package dev.orbital;

import java.util.ArrayList;
import java.util.List;
import java.util.PriorityQueue;
import net.fabricmc.fabric.api.networking.v1.ServerPlayNetworking;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.permissions.LevelBasedPermissionSet;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;

/**
 * Strikes: the plans' commands played out in time order by the server tick. As many strikes as you like can be on at
 * once; they share the original's per-tick budgets (20,000 blocks and 400 commands a tick), taking turns, so a pile of big
 * craters does not freeze the game.
 */
public final class Strike {
	private static final int BLOCK_BUDGET = 20_000;
	private static final int CMD_BUDGET = 400;
	private static final List<Strike> ACTIVE = new ArrayList<>();
	private static int turn;

	private record Node(long seq, Plan.Ev ev) {}

	/** What is left of this tick's allowance, shared by every strike that is on. */
	private static final class Budget {
		int blocks = BLOCK_BUDGET, cmds = CMD_BUDGET;
	}

	private final ServerPlayer player;
	private final Vec3 target;
	private final PriorityQueue<Node> queue = new PriorityQueue<>((a, b) -> {
		int c = Float.compare(a.ev.t(), b.ev.t());
		return c != 0 ? c : Long.compare(a.seq, b.seq);
	});
	private long seq;
	private int tick;
	private final int endTick;

	private Strike(ServerPlayer player, Vec3 target, List<Plan.Ev> events, float length) {
		this.player = player;
		this.target = target;
		this.endTick = (int) (length * 20);
		add(events);
	}

	private void add(List<Plan.Ev> events) {
		for (Plan.Ev e : events) {
			queue.add(new Node(seq++, e));
		}
	}

	/** The lasers whose plans are ported so far (the rest say so when loaded or fired). */
	public static boolean isPorted(String key) {
		return switch (key) {
			case "plasma", "godly", "blackhole", "meteor", "mothership", "planetkiller", "downfall", "payload", "nuke", "crystalbloom", "sinkhole" -> true;
			default -> false;
		};
	}

	/** How many strikes are on. */
	public static int count() {
		return ACTIVE.size();
	}

	/**
	 * /orbital stop: every strike ends now. What it still had waiting (blocks, sounds, particles, messages) is dropped, the chunks it
	 * had force-loaded are let go, its sounds are cut, and every player is told to clear its picture.
	 */
	public static void stopAll(MinecraftServer server) {
		for (Strike s : ACTIVE) {
			var src = s.player.createCommandSourceStack().withPermission(LevelBasedPermissionSet.OWNER).withSuppressedOutput();
			var commands = server.getCommands();
			for (Node n : s.queue) {
				if (n.ev.cmd() != null && n.ev.cmd().startsWith("forceload remove")) {
					try {
						commands.performPrefixedCommand(src, n.ev.cmd());
					} catch (RuntimeException ex) {
						OrbitalMod.LOGGER.warn("could not release chunks: {}", n.ev.cmd());
					}
				}
			}
			s.queue.clear();
		}
		ACTIVE.clear();
		for (ServerPlayer p : server.getPlayerList().getPlayers()) {
			ServerPlayNetworking.send(p, new Net.StopFx());
			var src = p.createCommandSourceStack().withPermission(LevelBasedPermissionSet.OWNER).withSuppressedOutput();
			for (String sound : OrbitalSounds.cutOnStop()) {
				try {
					server.getCommands().performPrefixedCommand(src, "stopsound @s * " + sound);
				} catch (RuntimeException ignored) {
					// (a sound that is not there)
				}
			}
		}
	}

	/** Plan a strike with the player's loaded laser at the hit, and start it. Returns false if it can't. */
	public static boolean start(ServerPlayer player, Vec3 point, int bx, int by, int bz, boolean terrain) {
		Laser laser = Laser.byKey(Settings.of(player.getUUID()).laser);
		ServerLevel level = (ServerLevel) player.level();
		String dim = level.dimension() == Level.OVERWORLD ? "minecraft:overworld"
				: level.dimension() == Level.NETHER ? "minecraft:the_nether" : "minecraft:the_end";
		float shaderSeed = (float) Math.abs(((long) bx * 31 + (long) bz * 17 + by + ACTIVE.size() * 7L) % 1000);
		Settings.Player opts = Settings.of(player.getUUID());
		double[] me = {player.getX(), player.getY(), player.getZ()};
		List<Plan.Ev> events;
		switch (laser.key()) {
			case "plasma", "godly", "blackhole" ->
				events = StandardPlan.plan(laser, bx, by, bz, point.x, point.y, point.z, terrain, dim, shaderSeed, me);
			case "planetkiller" -> events = BigPlans.planetKiller(laser, bx, by, bz, point.x, point.y, point.z, terrain, dim, shaderSeed, me);
			case "downfall" -> events = BigPlans.downfall(laser, bx, by, bz, point.x, point.y, point.z, terrain, dim, shaderSeed, me, opts.approach);
			case "payload" -> events = BigPlans.payload(laser, bx, by, bz, point.x, point.y, point.z, terrain, dim, shaderSeed, me, opts.payloadAlt);
			case "nuke" -> events = BigPlans.nuke(laser, bx, by, bz, point.x, point.y, point.z, terrain, dim, shaderSeed, me, opts.nukeAlt);
			case "crystalbloom" -> events = BigPlans.crystalBloom(laser, bx, by, bz, point.x, point.y, point.z, terrain, dim, shaderSeed, me);
			case "sinkhole" -> events = BigPlans.sinkhole(laser, bx, by, bz, point.x, point.y, point.z, terrain, dim, shaderSeed, me);
			case "mothership" -> events = MothershipPlan.plan(laser, bx, by, bz, point.x, point.y, point.z, terrain, dim, me, opts.approach);
			case "meteor" -> events = MeteorPlan.plan(laser, bx, by, bz, point.x, point.y, point.z, terrain, dim, shaderSeed, me);
			default -> {
				return false;
			}
		}
		events = new ArrayList<>(events);
		// A far target (out where only Voxy's distant terrain shows) is not loaded on the server: keep the land the strike works
		// on loaded while it works. (The big lasers already do this for themselves.)
		double dist = Math.sqrt(Math.pow(me[0] - point.x, 2) + Math.pow(me[2] - point.z, 2));
		int ownRadius = switch (laser.key()) {
			case "plasma", "godly", "blackhole" -> 70;
			case "meteor" -> 260;
			default -> 0;
		};
		if (ownRadius > 0 && terrain && dist > 80) {
			int tile = 192;
			for (int x = (int) Math.floor(point.x - ownRadius); x < point.x + ownRadius; x += tile) {
				for (int z = (int) Math.floor(point.z - ownRadius); z < point.z + ownRadius; z += tile) {
					int x1 = (int) Math.min(x + tile - 1, Math.floor(point.x + ownRadius));
					int z1 = (int) Math.min(z + tile - 1, Math.floor(point.z + ownRadius));
					events.add(new Plan.Ev(0.0f, "forceload add " + x + " " + z + " " + x1 + " " + z1, null));
					events.add(new Plan.Ev(laser.length() - 0.2f, "forceload remove " + x + " " + z + " " + x1 + " " + z1, null));
				}
			}
		}
		Strike s = new Strike(player, point, events, laser.length());
		if (laser.index() <= 4 || laser.index() == 9 || laser.index() == 10) {
			// the screen shaders (the original's, translated): strike.wgsl draws Plasma, Godly, Black Hole, Meteor Storm and
			// Mothership; the Payload and the Nuke have their own, which read a table worked out here from the world
			double wing = Math.atan2(player.getZ() - point.z, player.getX() - point.x);
			float offset = !terrain && opts.skip > 0f ? opts.skip : 0f;
			if (laser.index() >= 9) {
				boolean nuke = laser.index() == 10;
				double gy = by + 1.0;
				double[] rel = {player.getX() - (bx + 0.5), player.getY() - gy, player.getZ() - (bz + 0.5)};
				int[] words = ShaderTables.build(nuke, shaderSeed, rel, bx, bz, (x, z) ->
						level.hasChunk(x >> 4, z >> 4)
								? Double.valueOf(level.getHeight(net.minecraft.world.level.levelgen.Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z) - gy)
								: null);
				ServerPlayNetworking.send(player, new Net.StrikeData(words));
			}
			ServerPlayNetworking.send(player, new Net.StrikeFx(laser.index(), point.x, point.y, point.z, bx, by, bz, (float) wing,
					shaderSeed, opts.approach, opts.arrival, opts.colour, offset, laser.length(),
					(float) player.getX(), (float) player.getY(), (float) player.getZ()));
		}
		if (!terrain && opts.skip > 0f) {
			// look at one moment without sitting through the rest: start that far in, dropping what came before
			s.tick = (int) (opts.skip * 20);
			s.queue.removeIf(n -> n.ev.t() < opts.skip && n.ev.job() == null);
			opts.skip = 0f;
		}
		ACTIVE.add(s);
		return true;
	}

	/** Called every server tick: each strike takes its turn at the shared budget, the one that went first rotating. */
	public static void tickAll() {
		if (ACTIVE.isEmpty()) {
			return;
		}
		Budget budget = new Budget();
		int n = ACTIVE.size();
		for (int k = 0; k < n; k++) {
			Strike s = ACTIVE.get((turn + k) % n);
			s.step(budget);
			s.tick++;
		}
		turn++;
		ACTIVE.removeIf(s -> s.tick > s.endTick && s.queue.isEmpty());
	}

	private void step(Budget budget) {
		float now = tick / 20f;
		var src = player.createCommandSourceStack().withPermission(LevelBasedPermissionSet.OWNER).withSuppressedOutput();
		var commands = ((ServerLevel) player.level()).getServer().getCommands();
		while (!queue.isEmpty() && queue.peek().ev.t() <= now && budget.cmds > 0 && budget.blocks > 0) {
			Plan.Ev e = queue.poll().ev;
			if (e.job() != null) {
				add(e.job().get());
				continue;
			}
			if (e.cmd().startsWith("title @s actionbar") && !Settings.of(player.getUUID()).messages) {
				continue;
			}
			if (e.cmd().startsWith("@")) {
				clientEffect(e.cmd());
				continue;
			}
			budget.blocks -= volume(e.cmd());
			budget.cmds--;
			try {
				commands.performPrefixedCommand(src, e.cmd());
			} catch (RuntimeException ex) {
				OrbitalMod.LOGGER.warn("strike command failed: {}", e.cmd(), ex);
			}
		}
	}

	/** Effects on the player's own screen: @shake strength seconds / @flash rgb alpha in hold out. */
	private void clientEffect(String cmd) {
		String[] t = cmd.split(" ");
		try {
			if (t[0].equals("@shake")) {
				ServerPlayNetworking.send(player, new Net.Shake(Float.parseFloat(t[1]), Float.parseFloat(t[2])));
			} else if (t[0].equals("@flash")) {
				// a flash seen from far off is dimmer: the further the strike, the fainter (never quite nothing)
				double dist = player.position().distanceTo(target);
				float vis = (float) Math.max(0.04, Math.min(1.0, 1.6 / (1.0 + dist / 120.0)));
				ServerPlayNetworking.send(player, new Net.Flash(Integer.parseInt(t[1]), Float.parseFloat(t[2]) * vis,
						Float.parseFloat(t[3]), Float.parseFloat(t[4]), Float.parseFloat(t[5])));
			}
		} catch (RuntimeException ex) {
			OrbitalMod.LOGGER.warn("bad client effect: {}", cmd);
		}
	}

	/** Blocks a /fill command touches (others count as 1). */
	private static int volume(String cmd) {
		if (!cmd.startsWith("fill ")) {
			return 1;
		}
		String[] t = cmd.split(" ");
		if (t.length < 8) {
			return 1;
		}
		try {
			long v = 1;
			for (int i = 0; i < 3; i++) {
				v *= Math.abs(coord(t[4 + i]) - coord(t[1 + i])) + 1;
			}
			return (int) Math.min(v, Integer.MAX_VALUE);
		} catch (NumberFormatException ex) {
			return 1;
		}
	}

	private static long coord(String s) {
		if (s.startsWith("~")) {
			return s.length() == 1 ? 0 : Long.parseLong(s.substring(1));
		}
		return Long.parseLong(s);
	}
}
