package dev.orbital;

import static dev.orbital.Plan.f1;
import static dev.orbital.Plan.f2;
import static dev.orbital.Plan.num;
import static dev.orbital.Plan.surf;

import java.util.List;
import java.util.Locale;

/** The Meteor Storm: 72 meteors over the land round the target, then the extinction impact on it (strike.rs: meteor_plan). */
public final class MeteorPlan {
	private static final float FIRE = StandardPlan.FIRE;
	private static final int MET_N = 72;
	private static final double MET_SPAN = 120.0;
	private static final float BIG_T = 13.5f;

	private MeteorPlan() {}

	// ---- the shader's hash, so meteors fall where its hash puts them ----

	private static int pcg(int x) {
		int s = x * 747_796_405 + (int) 2_891_336_453L;
		int w = ((s >>> ((s >>> 28) + 4)) ^ s) * 277_803_737;
		return (w >>> 22) ^ w;
	}

	private static double mh(int i, int seed, int k) {
		return (pcg(i ^ pcg(seed ^ pcg(k))) & 0xFFFFFFFFL) / 4_294_967_296.0;
	}

	/** x, z off the target and seconds after FIRE. */
	private static double[] metWhere(int i, float shaderSeed) {
		int s = (int) shaderSeed;
		if (mh(i, s, 5) < 0.33) {
			int c = 100 + Math.min((int) (mh(i, s, 6) * 6.0), 5);
			double ca = mh(c, s, 1) * 2.0 * Math.PI;
			double cr = 24.0 + (MET_SPAN - 30.0) * Math.sqrt(mh(c, s, 2));
			double oa = mh(i, s, 7) * 2.0 * Math.PI;
			double or = 3.0 + 11.0 * mh(i, s, 8);
			double t = 3.0 + 8.5 * mh(c, s, 3) + 1.4 * mh(i, s, 9);
			return new double[] {Math.cos(ca) * cr + Math.cos(oa) * or, Math.sin(ca) * cr + Math.sin(oa) * or, (float) t};
		}
		double a = mh(i, s, 1) * 2.0 * Math.PI;
		double r = 14.0 + (MET_SPAN - 14.0) * Math.sqrt(mh(i, s, 2));
		return new double[] {Math.cos(a) * r, Math.sin(a) * r, (float) (2.5 + 9.5 * mh(i, s, 3))};
	}

	private static int metClass(int i, float shaderSeed) {
		double h = mh(i, (int) shaderSeed, 4);
		return h < 0.6 ? 0 : h < 0.87 ? 1 : 2;
	}

	private static double metFrom(float seed) {
		double v = seed * 0.0911;
		return (v - Math.floor(v)) * 2.0 * Math.PI;
	}

	private static float falloffDist(double ax, double ay, double az, double[] me) {
		return (float) (Math.sqrt(Math.pow(ax - me[0], 2) + Math.pow(ay - me[1], 2) + Math.pow(az - me[2], 2)) / 343.0);
	}

	private static String bar(String text, String color) {
		return "title @s actionbar {\"text\":\"" + text + "\",\"color\":\"" + color + "\",\"bold\":true}";
	}

	public static List<Plan.Ev> plan(Laser laser, int bx, int by, int bz, double px, double py, double pz, boolean terrain,
			String dimension, float shaderSeed, double[] me) {
		double tyd = Math.round(py * 100.0) / 100.0;
		String tx = num(Math.round(px * 100.0) / 100.0), ty = num(tyd), tz = num(Math.round(pz * 100.0) / 100.0);
		long seed = ((long) bx * 73_856_093L) ^ ((long) bz * 19_349_663L) ^ (long) by;
		Plan p = new Plan(laser, new Rng(seed), bx, by, bz);
		p.setListener(me, new double[] {px, py, pz});
		float t = FIRE;
		float tb = t + BIG_T;

		p.csound(0.0f, "charge", 10.0f, 1.0f);
		p.csound(3.4f, "lockon", 8.0f, 1.0f);
		p.at(3.5f, bar("METEOR STORM INBOUND", laser.color()));
		p.csound(t, "fire", 10.0f, 1.0f);
		p.csound(t + 0.3f, "storm", 8.0f, 1.0f);
		p.csound(t + 3.0f, "rumble", 6.0f, 1.0f);
		p.csound(t + 8.0f, "rumble", 6.0f, 0.9f);
		float heard = tb + falloffDist(Math.round(px * 100.0) / 100.0, tyd, Math.round(pz * 100.0) / 100.0, me);
		p.csound(tb - 6.5f, "approach", 10.0f, 1.0f);
		p.at(tb - 6.0f, bar("IMPACT IMMINENT", "dark_red"));
		p.csound(heard, "impact", 10.0f, 1.0f);
		p.at(tb + 0.2f, bar("EXTINCTION EVENT", "dark_red"));
		p.csound(heard + 6.0f, "rumble", 9.0f, 0.75f);
		p.csound(heard + 12.0f, "shutdown", 9.0f, 1.0f);
		// the camera and the screen: the air shaking more and more as the big one comes in, then the hardest jolt of all
		for (int k = 0; k < 3; k++) {
			p.shake(tb - 3.0f + k, new float[] {0.25f, 0.35f, 0.45f}[k], 1.6f);
		}
		p.shake(heard, 1.0f, 6.0f);
		p.shake(heard + 2.5f, 0.55f, 4.0f);
		p.shake(heard + 6.0f, 0.35f, 4.0f);
		for (int i = 0; i < 5; i++) {
			p.shake(t + 1.0f + i * 2.0f, 0.15f, 2.0f);
		}
		p.flash(tb - 1.0f, 0xFF5A1A, 0.18f, 1.0f, 0.5f, 0.5f);
		p.flash(heard, 0xFFFFFF, 1.0f, 0.03f, 0.3f, 3.0f);
		p.flash(heard + 0.3f, 0xFF5A1A, 0.30f, 1.0f, 5.0f, 4.0f);

		for (int i = 0; i < MET_N; i++) {
			double[] w = metWhere(i, shaderSeed);
			int x = (int) Math.floor(px + w[0]), z = (int) Math.floor(pz + w[1]);
			int cls = metClass(i, shaderSeed);
			float tl = t + (float) w[2];
			double pitch = p.rng.uniform(0.97, 1.03);
			double dist = Math.sqrt(Math.pow(x - me[0], 2) + Math.pow(z - me[2], 2));
			double min = Math.max(Math.min(Math.max(1.25 - dist / 320.0, 0.3), 1.0) * new double[] {0.6, 0.8, 1.0}[cls], 0.2);
			String hit = (dist > 90.0 ? "hit_far" : "hit") + (cls + 1);
			String whoosh = "whoosh" + p.rng.integer(1, 2);
			p.at(tl - 1.3f, surf(x, z, "playsound orbital:meteor." + whoosh + " block @a ~ ~ ~ 4 " + f2(pitch) + " " + f2(min * 0.8)));
			float tlHeard = tl + falloffDist(x, tyd, z, me);
			p.at(tlHeard, surf(x, z, "playsound orbital:meteor." + hit + " block @a ~ ~ ~ 4 " + f2(pitch) + " " + f2(min)));
			p.shake(tlHeard, new float[] {0.3f, 0.5f, 0.75f}[cls] * Plan.falloff(dist), new float[] {0.8f, 1.4f, 2.2f}[cls]);
			switch (cls) {
				case 0 -> p.at(tl, surf(x, z, "particle minecraft:explosion ~ ~1 ~ 1 1 1 0 4 force"));
				case 1 -> {
					p.at(tl, surf(x, z, "particle minecraft:explosion_emitter ~ ~1 ~ 0 0 0 0 1 force"));
					p.at(tl, surf(x, z, "particle minecraft:campfire_signal_smoke ~ ~1 ~ 2 1 2 0.02 20 force"));
				}
				default -> {
					p.at(tl, surf(x, z, "particle minecraft:explosion_emitter ~ ~2 ~ 3 2 3 0 4 force"));
					p.at(tl, surf(x, z, "particle minecraft:lava ~ ~1 ~ 3 1 3 0 60 force"));
					p.at(tl, surf(x, z, "particle minecraft:campfire_signal_smoke ~ ~1 ~ 4 1 4 0.03 50 force"));
				}
			}
			int kill = new int[] {4, 8, 14}[cls];
			p.at(tl + 0.05f, surf(x, z, "kill @e[type=!minecraft:player,distance.." + kill + "]"));
			if (terrain) {
				final int fx = x, fz = z, fc = cls;
				final float ftl = tl;
				p.later(tl - 0.4f, q -> meteorCrater(q, fx, fz, fc, ftl));
			}
		}

		// the big one hits
		p.at(tb, "particle minecraft:explosion_emitter " + tx + " " + num(tyd + 4.0) + " " + tz + " 14 6 14 0 10 force");
		p.at(tb + 0.05f, "particle minecraft:flash " + tx + " " + num(tyd + 20.0) + " " + tz + " 0 0 0 0 1 force");
		p.at(tb + 0.1f, "particle minecraft:block{block_state:\"minecraft:blackstone\"} " + tx + " " + num(tyd + 2.0) + " " + tz + " 20 4 20 3 400 force");
		for (int i = 0; i < 10; i++) {
			p.at(tb + 0.5f + i * 0.6f, "particle minecraft:lava " + tx + " " + num(tyd + 4.0) + " " + tz + " 30 6 30 0 40 force");
			p.at(tb + 0.7f + i * 0.6f, "particle minecraft:campfire_signal_smoke " + tx + " " + num(tyd + 2.0) + " " + tz + " 30 4 30 0.05 40 force");
		}
		for (int i = 0; i < 26; i++) {
			float tk = tb + 2.0f + i * 0.6f;
			p.at(tk, "particle minecraft:ash " + tx + " " + num(tyd + 25.0) + " " + tz + " 70 20 70 0 300 force");
			p.at(tk, "particle minecraft:white_ash " + tx + " " + num(tyd + 25.0) + " " + tz + " 70 20 70 0 150 force");
		}
		for (double tk : new double[] {0.1, 0.8, 2.0, 4.0, 7.0}) {
			p.at(tb + (float) tk, "execute positioned " + tx + " " + ty + " " + tz + " run kill @e[type=!minecraft:player,distance..130]");
		}
		if (terrain) {
			int floorY = "minecraft:overworld".equals(dimension) ? -59 : "minecraft:the_nether".equals(dimension) ? 5 : 1;
			int sky = "minecraft:overworld".equals(dimension) ? 319 : "minecraft:the_nether".equals(dimension) ? 122 : 255;
			double[] point = {px, py, pz};
			p.later(tb - 0.3f, q -> extinction(q, tb, floorY, sky, point, shaderSeed));
		}
		p.ev.sort((a, b) -> Float.compare(a.t(), b.t()));
		return p.ev;
	}

	private static List<String> rows(int rr, int yLo, int yHi, String block, String replace) {
		java.util.ArrayList<String> out = new java.util.ArrayList<>();
		for (int dz = -rr; dz <= rr; dz++) {
			int hw = (int) (Math.sqrt(Math.max(0.0, rr * rr - dz * dz)) + 0.35);
			out.add("fill ~-" + hw + " ~" + yLo + " ~" + dz + " ~" + hw + " ~" + yHi + " ~" + dz + " " + block + replace);
		}
		return out;
	}

	private static void meteorCrater(Plan p, int x, int z, int cls, float tl) {
		int[][] rd = {{3, 2}, {6, 4}, {11, 7}};
		int r = rd[cls][0], d = rd[cls][1];
		int a = r + 2;
		for (String tag : new String[] {"#minecraft:logs", "#minecraft:leaves"}) {
			p.at(tl - 0.05f, surf(x, z, "fill ~-" + a + " ~-14 ~-" + a + " ~" + a + " ~14 ~" + a + " minecraft:air replace " + tag));
		}
		for (String c : rows(r + 1, 0, 6, "minecraft:air", "")) {
			p.at(tl, surf(x, z, c));
		}
		for (String tag : new String[] {"#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand"}) {
			for (String c : rows(r + 1, -(d + 2), -1, "minecraft:blackstone", " replace " + tag)) {
				p.at(tl, surf(x, z, c));
			}
		}
		for (int i = 0; i < 1 + 3 * cls; i++) {
			int dx = p.rng.integer(-r, r), dz = p.rng.integer(-r, r);
			p.at(tl, surf(x, z, "fill ~" + (dx - 1) + " ~-" + (d + 2) + " ~" + (dz - 1) + " ~" + (dx + 1) + " ~-1 ~" + (dz + 1) + " minecraft:magma_block replace minecraft:blackstone"));
		}
		for (int k = d - 1; k >= 1; k--) {
			int rk = Math.max((int) Math.round(r * Math.sqrt(1.0 - (double) k / (d + 0.5))), 1);
			for (String c : rows(rk, -(k + 1), -(k + 1), "minecraft:air", "")) {
				p.at(tl, surf(x, z, c));
			}
		}
		String core = new String[] {"minecraft:magma_block", "minecraft:raw_iron_block", "minecraft:ancient_debris"}[cls];
		p.at(tl, surf(x, z, "setblock ~ ~-" + (d + 1) + " ~ " + core));
		if (cls == 2) {
			p.at(tl, surf(x, z, "fill ~-1 ~-" + (d + 1) + " ~-1 ~1 ~-" + (d + 1) + " ~1 minecraft:magma_block replace minecraft:blackstone"));
		}
		for (String c : rows(r, -1, -1, "minecraft:air", "")) {
			p.at(tl, surf(x, z, c));
		}
		String[] lip = {"minecraft:cobblestone", "minecraft:blackstone", "minecraft:coarse_dirt", "minecraft:gravel", "minecraft:tuff"};
		int lipN = new int[] {8, 18, 36}[cls];
		for (int i = 0; i < lipN; i++) {
			double ang = p.rng.uniform(0.0, 2.0 * Math.PI);
			double rr = r + p.rng.uniform(0.6, 2.2);
			int lx = x + (int) Math.round(Math.cos(ang) * rr), lz = z + (int) Math.round(Math.sin(ang) * rr);
			String blk = p.rng.pick(lip);
			p.at(tl + 0.1f, surf(lx, lz, "setblock ~ ~ ~ " + blk + " keep"));
		}
		int scorchN = new int[] {3, 6, 10}[cls];
		for (int i = 0; i < scorchN; i++) {
			double ang = p.rng.uniform(0.0, 2.0 * Math.PI);
			double rr = r + p.rng.uniform(1.0, r * 1.4 + 2.0);
			int sx = x + (int) Math.round(Math.cos(ang) * rr), sz = z + (int) Math.round(Math.sin(ang) * rr);
			int s = p.rng.integer(1, 1 + cls);
			String blk = p.rng.pick("minecraft:coarse_dirt", "minecraft:blackstone", "minecraft:coarse_dirt");
			p.at(tl + 0.1f, surf(sx, sz, "fill ~-" + s + " ~-1 ~-" + s + " ~" + s + " ~-1 ~" + s + " " + blk + " replace #minecraft:dirt"));
		}
		for (int i = 0; i < 3 + 4 * cls; i++) {
			double ang = p.rng.uniform(0.0, 2.0 * Math.PI);
			double rr = r + p.rng.uniform(1.0, 5.0);
			int fx = x + (int) Math.round(Math.cos(ang) * rr), fz = z + (int) Math.round(Math.sin(ang) * rr);
			float dt = (float) p.rng.uniform(0.1, 0.6);
			p.at(tl + dt, surf(fx, fz, "setblock ~ ~ ~ minecraft:fire keep"));
		}
		int rocks = new int[] {1, 4, 10}[cls];
		for (int i = 0; i < rocks; i++) {
			double ang = p.rng.uniform(0.0, 2.0 * Math.PI);
			double sp = p.rng.uniform(0.3, 0.9);
			double vx = Math.cos(ang) * sp, vy = p.rng.uniform(0.4, 1.0), vz = Math.sin(ang) * sp;
			String blk = p.rng.pick("minecraft:cobblestone", "minecraft:blackstone", "minecraft:dirt", "minecraft:magma_block");
			p.at(tl + 0.05f, surf(x, z, falling("~ ~1 ~", blk, vx, vy, vz)));
		}
	}

	private static String falling(String pos, String blk, double vx, double vy, double vz) {
		return "summon minecraft:falling_block " + pos + " {BlockState:{Name:\"" + blk + "\"},Time:1,DropItem:0b,Motion:["
				+ String.format(Locale.ROOT, "%.3f", vx) + "d," + String.format(Locale.ROOT, "%.3f", vy) + "d,"
				+ String.format(Locale.ROOT, "%.3f", vz) + "d]}";
	}

	private static void extinction(Plan p0, float tb, int floorY, int sky, double[] point, float seed) {
		p0.later(tb - 0.15f, p -> {
			int by = p.by;
			for (int band = 0; band < 4; band++) {
				int y0 = by + 1 + band * 20;
				if (y0 > sky) {
					break;
				}
				for (String c : p.disc(100, y0, Math.min(y0 + 19, sky), "minecraft:air", 0.1, null)) {
					p.at(tb + 0.1f + band * 0.1f, c);
				}
			}
			p.clearAbove(tb + 0.5f, 100, by + 81, sky, 0.1);
		});
		p0.later(tb + 0.35f, p -> {
			int by = p.by;
			for (Laser.Scorch sc : p.laser.scorch()) {
				for (String c : p.disc(sc.radius(), by - 4, by + 1, sc.block(), sc.rough(), sc.replace())) {
					float dt = (float) p.rng.next() * 1.5f;
					p.at(tb + 0.6f + dt, c);
				}
			}
		});
		p0.later(tb + 0.05f, p -> {
			Laser laser = p.laser;
			int bx = p.bx, by = p.by, bz = p.bz;
			String[] natural = {"#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand", "minecraft:gravel", "minecraft:coarse_dirt"};
			String prim = laser.lining()[0].block();
			int bowlR = laser.bowlR(), bowlD = laser.bowlD();
			for (int d = 0; d < bowlD; d += 3) {
				int r = Math.max((int) (bowlR * Math.sqrt(1.0 - (double) d / (bowlD + 0.5))), 4);
				float tl = tb + 0.3f + d * 0.045f;
				int yLo = by - d - 2, yHi = by - d;
				List<int[]> rs = p.rects(r, laser.bowlRough());
				for (String tag : natural) {
					for (String c : Plan.edgeFills(rs, yLo - 1, yHi, prim, tag, 2)) {
						p.at(tl - 0.05f, c);
					}
				}
				for (String c : Plan.fills(rs, yLo, yHi, "minecraft:air", null, 0)) {
					p.at(tl, c);
				}
				p.mottle(r, yLo, yHi, tl, 24);
			}
			Laser.Floor fl = laser.bowlFloor();
			for (String c : p.disc(bowlR - 6, by - bowlD - 1, by - bowlD + 2, fl.block(), fl.rough(), fl.replace())) {
				p.at(tb + 2.2f, c);
			}
			for (int i = 0; i < 14; i++) {
				double a = p.rng.uniform(0.0, 2.0 * Math.PI);
				double rr = p.rng.uniform(16.0, bowlR * 0.6);
				int x = bx + (int) Math.round(Math.cos(a) * rr), z = bz + (int) Math.round(Math.sin(a) * rr);
				int s = p.rng.integer(1, 3);
				p.at(tb + 2.6f, surf(x, z, "fill ~-" + s + " ~-1 ~-" + s + " ~" + s + " ~-1 ~" + s + " minecraft:lava"));
			}
		});
		p0.later(tb + 0.75f, p -> {
			Laser laser = p.laser;
			int by = p.by;
			int yHi = by - laser.bowlD();
			int i = 0;
			while (yHi >= floorY) {
				int r = Math.max((int) Math.round(laser.shaftR() - i * 0.3), laser.shaftMin());
				float ts = tb + 1.0f + i * 0.12f;
				p.dig(r, Math.max(yHi - 3, floorY), yHi, ts, laser.shaftRough(), 1);
				p.mottle(r, Math.max(yHi - 3, floorY), yHi, ts, 4);
				yHi -= 4;
				i++;
			}
			Laser.Bottom[] bottom = laser.bottom();
			for (int k = 0; k < bottom.length; k++) {
				Laser.Bottom bt = bottom[k];
				for (String c : p.disc(bt.radius(), floorY + bt.from(), floorY + bt.to(), bt.block(), 0.0, null)) {
					p.at(tb + 4.0f + 0.1f * k, c);
				}
			}
		});
		p0.later(tb + 0.55f, p -> {
			Laser laser = p.laser;
			int bx = p.bx, by = p.by, bz = p.bz;
			int bowlR = laser.bowlR();
			String[] rim = {"minecraft:cobblestone", "minecraft:blackstone", "minecraft:tuff", "minecraft:cobbled_deepslate", "minecraft:basalt", "minecraft:magma_block"};
			for (int i = 0; i < 280; i++) {
				double a = p.rng.uniform(0.0, 2.0 * Math.PI);
				double rr = bowlR + 1.0 + 14.0 * Math.pow(p.rng.next(), 1.5);
				int x = bx + (int) Math.round(Math.cos(a) * rr), z = bz + (int) Math.round(Math.sin(a) * rr);
				int h = (int) Math.max(Math.round(6.0 * (1.0 - (rr - bowlR) / 16.0)), 1) + p.rng.integer(-1, 1);
				String blk = p.rng.pick(rim);
				float tl = tb + 0.8f + (float) p.rng.uniform(0.0, 1.6);
				p.at(tl, "fill " + (x - 1) + " " + (by + 1) + " " + (z - 1) + " " + (x + 1) + " " + (by + Math.max(h, 1)) + " " + (z + 1) + " " + blk + " keep");
			}
		});
		p0.later(tb - 0.15f, p -> {
			int bx = p.bx, by = p.by, bz = p.bz;
			String[] ejecta = {"minecraft:cobblestone", "minecraft:blackstone", "minecraft:magma_block", "minecraft:cobbled_deepslate",
				"minecraft:basalt", "minecraft:obsidian", "minecraft:tuff", "minecraft:dirt"};
			double from = metFrom(seed);
			double dx0 = -Math.cos(from), dz0 = -Math.sin(from);
			double ray0 = seed * 0.3;
			for (int i = 0; i < 260; i++) {
				double a = p.rng.next() < 0.6
						? ray0 + p.rng.integer(0, 6) * 2.0 * Math.PI / 7.0 + p.rng.uniform(-0.09, 0.09)
						: p.rng.uniform(0.0, 2.0 * Math.PI);
				double bias = 0.35 * p.rng.next();
				double hx = Math.cos(a) * (1.0 - bias) + dx0 * bias, hz = Math.sin(a) * (1.0 - bias) + dz0 * bias;
				double hl = Math.max(Math.sqrt(hx * hx + hz * hz), 1e-6);
				hx /= hl;
				hz /= hl;
				double rr = p.rng.uniform(16.0, 40.0);
				double x = point[0] + hx * rr, z = point[2] + hz * rr;
				double elev = 0.15 + 1.2 * Math.pow(p.rng.next(), 0.7);
				double speed = (1.6 + 2.8 * Math.pow(p.rng.next(), 2)) * p.rng.uniform(0.7, 1.3);
				double vx = hx * Math.cos(elev) * speed, vy = Math.sin(elev) * speed, vz = hz * Math.cos(elev) * speed;
				String blk = p.rng.pick(ejecta);
				float tl = tb + (float) (0.1 + 1.4 * Math.pow(p.rng.next(), 2));
				p.at(tl, falling(f1(x) + " " + (by + 3) + " " + f1(z), blk, vx, vy, vz));
			}
			for (int k = 0; k < 320; k++) {
				boolean onRay = p.rng.next() < 0.5;
				double a = onRay ? ray0 + p.rng.integer(0, 6) * 2.0 * Math.PI / 7.0 + p.rng.uniform(-0.06, 0.06) : p.rng.uniform(0.0, 2.0 * Math.PI);
				double rr = 80.0 + (onRay ? 170.0 : 110.0) * Math.pow(p.rng.next(), 1.4);
				int x = bx + (int) Math.round(Math.cos(a) * rr), z = bz + (int) Math.round(Math.sin(a) * rr);
				float tl = tb + 1.5f + (float) (rr / 210.0 * 6.0) + (float) p.rng.uniform(0.0, 1.5);
				String blk = p.rng.pick(ejecta);
				p.at(tl, surf(x, z, "setblock ~ ~ ~ " + blk + " keep"));
				if (k % 4 == 0) {
					p.at(tl, surf(x, z, "particle minecraft:block{block_state:\"" + blk + "\"} ~ ~0.5 ~ 0.6 0.4 0.6 0.2 16 force"));
				}
			}
		});
		p0.later(tb + 0.75f, p -> {
			int bx = p.bx, bz = p.bz;
			int bowlR = p.laser.bowlR();
			for (int i = 0; i < 170; i++) {
				double a = p.rng.uniform(0.0, 2.0 * Math.PI);
				double rr = p.rng.uniform(bowlR + 4.0, 130.0);
				float dt = (float) p.rng.uniform(1.0, 5.0);
				p.at(tb + dt, surf(bx + (int) Math.round(Math.cos(a) * rr), bz + (int) Math.round(Math.sin(a) * rr), "setblock ~ ~ ~ minecraft:fire keep"));
			}
		});
	}
}
