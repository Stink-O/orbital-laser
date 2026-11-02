package dev.orbital;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.function.Consumer;
import java.util.function.Supplier;

/** A strike's plan: vanilla commands on a timeline (seconds), as the original mod's strike.rs Plan. */
public final class Plan {
	/** One event: a command at time t, or a stage (job) worked out when it is due. */
	public record Ev(float t, String cmd, Supplier<List<Ev>> job) {}

	public final Laser laser;
	public final List<Ev> ev = new ArrayList<>();
	public final Rng rng;
	public final int bx, by, bz;

	public Plan(Laser laser, Rng rng, int bx, int by, int bz) {
		this.laser = laser;
		this.rng = rng;
		this.bx = bx;
		this.by = by;
		this.bz = bz;
	}

	// ---- formatting (as Rust prints numbers: 12 not 12.0) ----

	public static String num(double v) {
		if (v == Math.rint(v) && Math.abs(v) < 1e15) {
			return Long.toString((long) v);
		}
		return Double.toString(v);
	}

	public static String f1(double v) {
		return String.format(Locale.ROOT, "%.1f", v);
	}

	public static String f2(double v) {
		return String.format(Locale.ROOT, "%.2f", v);
	}

	/** `then`, run on the ground at column (x, z): `~ ~ ~` is the first air block above the surface. */
	public static String surf(int x, int z, String then) {
		return "execute positioned " + x + " 0 " + z + " positioned over motion_blocking_no_leaves run " + then;
	}

	// ---- events ----

	/** Work out part of the plan only when it is due (at `at`, a little before its first event). */
	public void later(float at, Consumer<Plan> f) {
		long seed = (long) (rng.next() * 9.0e15);
		Laser l = laser;
		int x = bx, y = by, z = bz;
		ev.add(new Ev(at, null, () -> {
			Plan p = new Plan(l, new Rng(seed), x, y, z);
			f.accept(p);
			p.ev.sort((a, b) -> Float.compare(a.t, b.t));
			return p.ev;
		}));
	}

	public void at(float t, String cmd) {
		ev.add(new Ev(t, cmd, null));
	}

	// ---- distance: where the listener stands from the strike, so far strikes sound far ----

	private double[] tgt;
	private double dist;

	/**
	 * Tell the plan where the player stands and where the strike is. From then on its sounds that come from the strike are
	 * heard from the strike's direction (so an HRTF can place them) and, past about 48 blocks, quieter and a little deeper
	 * the further off it is. (The device's own sounds, charge and lock-on, stay with the player.)
	 */
	public void setListener(double[] me, double[] target) {
		tgt = target;
		dist = Math.sqrt(Math.pow(me[0] - target[0], 2) + Math.pow(me[1] - target[1], 2) + Math.pow(me[2] - target[2], 2));
	}

	private boolean far() {
		return tgt != null && dist > 48.0;
	}

	/** How long a sound takes to arrive from the strike (about 343 blocks a second), when it is far. */
	private float travel() {
		return far() ? (float) (dist / 343.0) : 0f;
	}

	/** A sound from the strike, heard from its direction: audible out to 256 blocks, then at a floor that falls with distance. */
	private String farPlay(String event, float vol, double pitch) {
		double min = Math.max(0.12, Math.min(0.9, 0.9 - dist / 1400.0)) * Math.min(vol / 10f, 1f);
		double p = pitch * (dist > 250 ? 0.94 : 1.0);
		return "playsound " + event + " master @s " + num(tgt[0]) + " " + num(tgt[1]) + " " + num(tgt[2]) + " 16 " + f2(p) + " " + f2(min);
	}

	/** As `sound`, but late by how far the strike is (for plans that have not already worked that out). */
	public void farSound(float t, String name, float vol, double pitch) {
		sound(t + travel(), name, vol, pitch);
	}

	/** As `csound`, but late by how far the strike is. */
	public void farCsound(float t, String role, float vol, float pitch) {
		csound(t + travel(), role, vol, pitch);
	}

	/** A vanilla sound heard by the player, `vol` out of 10. */
	public void sound(float t, String name, float vol, double pitch) {
		if (far()) {
			at(t, farPlay("minecraft:" + name, vol, pitch));
			return;
		}
		at(t, "playsound minecraft:" + name + " master @s ~ ~ ~ " + num(Math.min(vol / 10f, 1f)) + " " + f2(pitch));
	}

	/** A vanilla sound out of the impact, heard there and fading with distance. */
	public void groundSound(float t, String name, float vol, double pitch) {
		at(t, "playsound minecraft:" + name + " block @a " + (bx + 0.5) + " " + (by + 0.5) + " " + (bz + 0.5) + " "
				+ num(Math.min(vol / 10f, 1f) * 4f) + " " + f2(pitch));
	}

	/** One of the laser's own sounds. */
	public void csound(float t, String role, float vol, float pitch) {
		if (far() && !role.equals("charge") && !role.equals("lockon")) {
			at(t, farPlay(laser.sound(role), vol, pitch));
			return;
		}
		at(t, "playsound " + laser.sound(role) + " master @s ~ ~ ~ " + num(Math.min(vol / 10f, 1f)) + " " + f2(pitch));
	}

	/**
	 * A beam from the sky to the ground as a column of coloured dust, from t0 to t1 (a stand-in for the original's shader
	 * beam): `rgb` is 0xRRGGBB, `height` how far up, `radius` how wide, `count` particles a tenth of a second.
	 */
	public void beam(float t0, float t1, double x, double y, double z, int rgb, double height, double radius, int count) {
		String c = String.format(Locale.ROOT, "[%.2f,%.2f,%.2f]", ((rgb >> 16) & 255) / 255.0, ((rgb >> 8) & 255) / 255.0, (rgb & 255) / 255.0);
		for (float t = t0; t < t1; t += 0.1f) {
			at(t, "particle minecraft:dust{color:" + c + ",scale:3} " + num(x) + " " + num(y + height / 2) + " " + num(z) + " " + f1(radius) + " " + f1(height / 2) + " " + f1(radius) + " 0 " + count + " force");
			at(t, "particle minecraft:dust{color:[1.0,1.0,1.0],scale:2} " + num(x) + " " + num(y + height / 2) + " " + num(z) + " " + f1(radius * 0.3) + " " + f1(height / 2) + " " + f1(radius * 0.3) + " 0 " + (count / 3) + " force");
		}
	}

	/** How much of a blast's jolt reaches the player d blocks off: all of it close by, a third at 300 blocks (the original's falloff). */
	public static float falloff(double d) {
		return (float) Math.min(1.4 / (1.0 + d / 100.0), 1.0);
	}

	/** A jolt of the camera, played on the client (see Net.Shake). */
	public void shake(float t, float strength, float seconds) {
		at(t, "@shake " + f2(Math.max(0f, Math.min(1f, strength))) + " " + f2(Math.max(0.05f, Math.min(30f, seconds))));
	}

	/** A colour laid over the whole screen (see Net.Flash): rgb 0xRRGGBB, alpha 0 to 1. */
	public void flash(float t, int rgb, float alpha, float fadeIn, float hold, float fadeOut) {
		at(t, "@flash " + rgb + " " + f2(alpha) + " " + f2(fadeIn) + " " + f2(hold) + " " + f2(fadeOut));
	}

	// ---- shapes ----

	/** A rough circle as a few rectangles (x0, z0, x1, z1): consecutive rows share one /fill. */
	public List<int[]> rects(int r, double rough) {
		int n = 2 * r + 1;
		int groups = Math.min(n, 3 + (int) Math.round(r * 0.6));
		List<int[]> out = new ArrayList<>();
		for (int g = 0; g < groups; g++) {
			int lo = g * n / groups;
			int hi = (g + 1) * n / groups;
			if (hi <= lo) {
				continue;
			}
			double sum = 0;
			for (int k = lo; k < hi; k++) {
				int dz = -r + k;
				sum += Math.sqrt(Math.max(0.0, (double) (r * r - dz * dz)));
			}
			double hw = sum / (hi - lo);
			hw = hw * (1.0 + rng.uniform(-rough, rough)) + 0.5;
			int ihw = (int) hw;
			int zFirst = -r + lo;
			int zLast = -r + hi - 1;
			out.add(new int[] {bx - ihw, bz + zFirst, bx + ihw, bz + zLast});
		}
		return out;
	}

	public static List<String> fills(List<int[]> rs, int yLo, int yHi, String block, String replace, int grow) {
		String suffix = replace == null ? "" : " replace " + replace;
		List<String> out = new ArrayList<>();
		for (int[] r : rs) {
			out.add("fill " + (r[0] - grow) + " " + yLo + " " + (r[1] - grow) + " " + (r[2] + grow) + " " + yHi + " " + (r[3] + grow) + " " + block + suffix);
		}
		return out;
	}

	public static List<String> edgeFills(List<int[]> rs, int yLo, int yHi, String block, String replace, int grow) {
		List<String> out = new ArrayList<>();
		for (int i = 0; i < rs.size(); i++) {
			int[] r = rs.get(i);
			int za = r[1] - (i == 0 ? grow : 0);
			int zb = r[3] + (i + 1 == rs.size() ? grow : 0);
			if (i == 0 || i + 1 == rs.size() || r[2] - r[0] <= 4 * grow + 2) {
				out.add("fill " + (r[0] - grow) + " " + yLo + " " + za + " " + (r[2] + grow) + " " + yHi + " " + zb + " " + block + " replace " + replace);
			} else {
				out.add("fill " + (r[0] - grow) + " " + yLo + " " + za + " " + (r[0] + grow) + " " + yHi + " " + zb + " " + block + " replace " + replace);
				out.add("fill " + (r[2] - grow) + " " + yLo + " " + za + " " + (r[2] + grow) + " " + yHi + " " + zb + " " + block + " replace " + replace);
			}
		}
		return out;
	}

	public List<String> disc(int r, int yLo, int yHi, String block, double rough, String replace) {
		return fills(rects(r, rough), yLo, yHi, block, replace, 0);
	}

	/** Everything left standing over a blast of radius r, from y0 up to the sky, in bands (a fill's cap). */
	public void clearAbove(float t, int r, int y0, int sky, double rough) {
		int y = y0;
		while (y <= sky) {
			int top = Math.min(y + 19, sky);
			for (String c : disc(r, y, top, "minecraft:air", rough, null)) {
				at(t, c);
			}
			y = top + 1;
		}
	}

	/** Patches of the laser's other lining blocks over the fused wall at radius r. */
	public void mottle(int r, int yLo, int yHi, float t, int n) {
		String prim = laser.lining()[0].block();
		for (int i = 0; i < n; i++) {
			double a = rng.uniform(0.0, 2.0 * Math.PI);
			int x = bx + (int) Math.round(Math.cos(a) * (r + 1));
			int z = bz + (int) Math.round(Math.sin(a) * (r + 1));
			int s = rng.pick(1, 1, 2);
			String blk = rng.weighted(laser.lining(), 1);
			at(t + 0.05f, "fill " + (x - s) + " " + (yLo - 1) + " " + (z - s) + " " + (x + s) + " " + yHi + " " + (z + s) + " " + blk + " replace " + prim);
		}
	}

	private static final String[] NATURAL = {
		"#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand", "minecraft:gravel", "minecraft:clay",
		"#minecraft:terracotta", "minecraft:blackstone", "minecraft:smooth_basalt", "minecraft:smooth_quartz",
		"minecraft:calcite", "#minecraft:coal_ores", "#minecraft:iron_ores", "#minecraft:copper_ores"};

	/** Fuse the ground round a disc into the laser's lining (walls and the ledge under them), then dig the disc out. */
	public void dig(int r, int yLo, int yHi, float t, double rough, int grow) {
		String prim = laser.lining()[0].block();
		List<int[]> rs = rects(r, rough);
		for (String tag : NATURAL) {
			for (String c : fills(rs, yLo - 1, yHi, prim, tag, grow)) {
				at(t - 0.05f, c);
			}
		}
		for (String c : fills(rs, yLo, yHi, "minecraft:air", null, 0)) {
			at(t, c);
		}
	}
}
