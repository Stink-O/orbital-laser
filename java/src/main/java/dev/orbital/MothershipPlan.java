package dev.orbital;

import static dev.orbital.Plan.f1;
import static dev.orbital.Plan.f2;
import static dev.orbital.Plan.num;
import static dev.orbital.Plan.surf;

import java.util.List;

/** The Mothership (strike.rs: mothership_plan, mothership_crater, trench). */
public final class MothershipPlan {
	private static final float FIRE = StandardPlan.FIRE;
	private static final float MS_ARRIVE = 3.0f, MS_HIT = 8.2f, MS_SWEEP0 = 10.0f, MS_SWEEP1 = 19.0f, MS_CUT = 20.0f,
			MS_LEAVE = 23.0f, MS_END = 32.0f;
	private static final double TRENCH_L = 100.0;
	private static final int KILL_RADIUS = 40;
	public static final String[] APPROACH_LABELS = {"from ahead, towards you", "from behind you", "from your left", "from your right", "from overhead"};

	private MothershipPlan() {}

	private static double sweep(float t) {
		double s = Math.max(0, Math.min(1, (t - MS_SWEEP0) / (MS_SWEEP1 - MS_SWEEP0)));
		return s * s * (3.0 - 2.0 * s);
	}

	private static float when(double u) {
		double c = Math.max(0, Math.min(1, u));
		double s = 0.5 - Math.sin(Math.asin(1.0 - 2.0 * c) / 3.0);
		return MS_SWEEP0 + (MS_SWEEP1 - MS_SWEEP0) * (float) s;
	}

	private static String bar(String text, String color) {
		return "title @s actionbar {\"text\":\"" + text + "\",\"color\":\"" + color + "\",\"bold\":true}";
	}

	private static float late(double x, double y, double z, double[] me) {
		return (float) (Math.sqrt(Math.pow(x - me[0], 2) + Math.pow(y - me[1], 2) + Math.pow(z - me[2], 2)) / 343.0);
	}

	public static List<Plan.Ev> plan(Laser laser, int bx, int by, int bz, double px, double py, double pz, boolean terrain,
			String dimension, double[] me, int approach) {
		double txd = Math.round(px * 100.0) / 100.0, tyd = Math.round(py * 100.0) / 100.0, tzd = Math.round(pz * 100.0) / 100.0;
		String tx = num(txd), ty = num(tyd), tz = num(tzd);
		long seed = ((long) bx * 73_856_093L) ^ ((long) bz * 19_349_663L) ^ (long) by;
		Plan p = new Plan(laser, new Rng(seed), bx, by, bz);
		p.setListener(me, new double[] {px, py, pz});
		// the beam sweeps away from the player
		double wing = Math.atan2(me[2] - pz, me[0] - px);
		double[] axis = {-Math.cos(wing), -Math.sin(wing)};
		double[] point = {px, py, pz};
		java.util.function.Function<Float, double[]> spot = t -> {
			double u = sweep(t) * TRENCH_L;
			return new double[] {point[0] + axis[0] * u, point[2] + axis[1] * u};
		};
		float ship = late(txd, tyd + 420.0, tzd, me);

		p.at(MS_ARRIVE - 1.0f, bar("MOTHERSHIP INBOUND " + APPROACH_LABELS[Math.min(approach, 4)].toUpperCase(), laser.color()));
		p.csound(MS_ARRIVE - 0.02f, "arrival", 10f, 1f);
		p.csound(MS_ARRIVE + ship, "boom", 10f, 1f);
		p.at(MS_ARRIVE + 0.6f, bar("MOTHERSHIP OVERHEAD", laser.color()));
		p.csound(MS_ARRIVE + ship + 0.3f, "hum", 8f, 1f);
		p.csound(FIRE, "charge", 10f, 1f);
		p.at(MS_HIT - 0.9f, bar("BEAM LOCKED", laser.color()));
		float heard = MS_HIT + late(txd, tyd, tzd, me);
		p.csound(heard, "fire", 10f, 1f);
		p.csound(MS_HIT + 0.15f, "beam1", 10f, 1f);
		p.csound(MS_HIT + 5.9f, "beam2", 10f, 1f);
		p.csound(heard + 1.2f, "rumble", 9f, 1f);
		p.csound(heard + 7.4f, "rumble", 8f, 1f);
		p.at(MS_HIT + 0.1f, bar("DIRECT HIT", "white"));
		for (int k = 0; k < 7; k++) {
			float tk = MS_SWEEP0 - 0.6f + k * 1.35f;
			double[] g = spot.apply(tk);
			double dist = Math.sqrt(Math.pow(g[0] - me[0], 2) + Math.pow(g[1] - me[2], 2));
			double min = Math.max(0.5, Math.min(0.95, 1.2 - dist / 350.0));
			int take = 1 + k % 2;
			p.at(tk + late(g[0], tyd, g[1], me), surf((int) Math.floor(g[0]), (int) Math.floor(g[1]),
					"playsound orbital:mothership.sweep" + take + " block @a ~ ~ ~ 6 1 " + f2(min)));
		}
		double[] end = spot.apply(MS_CUT);
		p.csound(MS_CUT + late(end[0], tyd, end[1], me), "cutoff", 9f, 1f);
		p.csound(MS_LEAVE - 0.8f, "depart", 10f, 1f);
		p.csound(MS_LEAVE + ship, "boom", 8f, 1f);
		// the camera and the screen
		double hd = Math.sqrt(Math.pow(px - me[0], 2) + Math.pow(py - me[1], 2) + Math.pow(pz - me[2], 2));
		float fo = Math.max(Plan.falloff(hd), 0.5f);
		p.shake(MS_ARRIVE + 0.2f, 0.35f, 1.0f);
		p.shake(MS_ARRIVE + ship, 0.85f, 3.5f);
		p.flash(MS_ARRIVE, 0xFFFFFF, 0.45f, 0.03f, 0.1f, 1.0f);
		p.shake(FIRE + 2.0f, 0.15f, 1.5f);
		p.shake(FIRE + 3.0f, 0.22f, 1.5f);
		p.shake(heard, fo, 4.0f);
		for (float tj = MS_HIT + 1.0f; tj < MS_CUT; tj += 1.0f) {
			p.shake(tj + (heard - MS_HIT), 0.22f * Math.max(fo, 0.6f), 1.3f);
		}
		p.flash(heard, 0xFFFFFF, 0.8f, 0.03f, 0.2f, 1.6f);
		p.flash(heard + 0.3f, laser.rgb(), 0.14f, 0.5f, 11.0f, 2.0f);
		p.shake(MS_CUT + late(end[0], tyd, end[1], me), 0.45f, 2.0f);
		p.shake(MS_LEAVE, 0.55f, 2.0f);
		p.shake(MS_LEAVE + ship, 0.6f, 3.0f);

		// ---- particles in the world ----
		for (int i = 0; i < 8; i++) {
			float tk = FIRE + 0.3f + i * 0.45f;
			double s = 10.0 - i;
			p.at(tk, "particle minecraft:white_ash " + tx + " " + num(tyd + 1.0) + " " + tz + " " + f1(s) + " 1 " + f1(s) + " 0 90 force");
			p.at(tk, "particle minecraft:poof " + tx + " " + num(tyd + 0.5) + " " + tz + " " + f1(s) + " 0.3 " + f1(s) + " 0.04 30 force");
			p.at(tk, "particle minecraft:end_rod " + tx + " " + num(tyd + 1.0) + " " + tz + " 2 0.5 2 0.08 " + (6 + i * 3) + " force");
		}
		p.at(MS_HIT, "particle minecraft:explosion_emitter " + tx + " " + num(tyd + 1.0) + " " + tz + " 2 1 2 0 4 force");
		p.at(MS_HIT + 0.05f, "particle minecraft:block{block_state:\"minecraft:obsidian\"} " + tx + " " + num(tyd + 1.0) + " " + tz + " 3 1 3 2.0 500 force");
		p.at(MS_HIT + 0.1f, "particle minecraft:block{block_state:\"minecraft:stone\"} " + tx + " " + num(tyd + 1.0) + " " + tz + " 5 1 5 1.6 400 force");
		for (float tb = MS_HIT; tb < MS_CUT; tb += 0.1f) {
			// the beam from the ship follows the spot it is cutting
			double[] g = spot.apply(tb);
			p.beam(tb, tb + 0.1f, g[0], tyd, g[1], laser.rgb(), 240.0, 1.4, 450);
		}
		float tk = MS_HIT + 0.2f;
		int k = 0;
		while (tk < MS_CUT) {
			double[] g = spot.apply(tk);
			int x = (int) Math.floor(g[0]), z = (int) Math.floor(g[1]);
			p.at(tk, surf(x, z, "particle minecraft:lava ~ ~1 ~ 2 1 2 0 14 force"));
			p.at(tk, surf(x, z, "particle minecraft:flame ~ ~0.5 ~ 2.5 0.6 2.5 0.12 30 force"));
			if (k % 2 == 0) {
				p.at(tk, surf(x, z, "particle minecraft:explosion ~ ~1 ~ 2 1 2 0 3 force"));
				p.at(tk, surf(x, z, "particle minecraft:large_smoke ~ ~2 ~ 2.5 2 2.5 0.06 24 force"));
				p.at(tk, "execute positioned " + f1(g[0]) + " " + ty + " " + f1(g[1]) + " run kill @e[type=!minecraft:player,distance..16]");
			}
			tk += 0.25f;
			k++;
		}
		float tw = MS_SWEEP0 + 1.0f;
		while (tw < MS_END) {
			tw += 0.7f;
			double u = (p.rng.next() * sweep(tw - 0.8f)) * TRENCH_L;
			int x = (int) Math.floor(point[0] + axis[0] * u), z = (int) Math.floor(point[2] + axis[1] * u);
			p.at(tw, surf(x, z, "particle minecraft:campfire_cosy_smoke ~ ~0.5 ~ 3 0.5 3 0.03 14 force"));
			p.at(tw, surf(x, z, "particle minecraft:cloud ~ ~1 ~ 3 1 3 0.04 18 force"));
		}
		for (double kt : new double[] {0.1, 0.8, 1.6, 3.0}) {
			p.at(MS_HIT + (float) kt, "execute positioned " + tx + " " + ty + " " + tz + " run kill @e[type=!minecraft:player,distance.." + KILL_RADIUS + "]");
		}

		if (terrain) {
			double ex = point[0] + axis[0] * TRENCH_L, ez = point[2] + axis[1] * TRENCH_L;
			int x0 = (int) Math.floor(Math.min(point[0], ex) - 48.0), x1 = (int) Math.floor(Math.max(point[0], ex) + 48.0);
			int z0 = (int) Math.floor(Math.min(point[2], ez) - 48.0), z1 = (int) Math.floor(Math.max(point[2], ez) + 48.0);
			p.at(0.0f, "forceload add " + x0 + " " + z0 + " " + x1 + " " + z1);
			p.at(MS_END + 1.0f, "forceload remove " + x0 + " " + z0 + " " + x1 + " " + z1);
			int floorY = "minecraft:overworld".equals(dimension) ? -59 : "minecraft:the_nether".equals(dimension) ? 5 : 1;
			int sky = "minecraft:overworld".equals(dimension) ? 319 : "minecraft:the_nether".equals(dimension) ? 122 : 255;
			crater(p, floorY, sky);
			double d0 = 0.0;
			while (d0 < TRENCH_L) {
				double d1 = Math.min(d0 + 8.0, TRENCH_L);
				final double a = d0, b = d1;
				p.later(when(a / TRENCH_L) - 0.3f, q -> trench(q, point, axis, a, b, sky));
				d0 = d1;
			}
		}
		p.ev.sort((a, b) -> Float.compare(a.t(), b.t()));
		return p.ev;
	}

	private static void crater(Plan p0, int floorY, int sky) {
		float t = MS_HIT;
		p0.later(t - 0.1f, p -> {
			int by = p.by;
			for (int band = 0; band < 2; band++) {
				int y0 = by + 1 + band * 20;
				if (y0 > sky) {
					break;
				}
				for (String c : p.disc(34, y0, Math.min(y0 + 19, sky), "minecraft:air", 0.12, null)) {
					p.at(t + 0.1f + band * 0.1f, c);
				}
			}
			p.clearAbove(t + 0.3f, 34, by + 41, sky, 0.12);
			for (Laser.Scorch sc : p.laser.scorch()) {
				for (String c : p.disc(sc.radius(), by - 3, by + 1, sc.block(), sc.rough(), sc.replace())) {
					float dt = (float) p.rng.next() * 1.6f;
					p.at(t + 0.4f + dt, c);
				}
			}
		});
		p0.later(t + 0.1f, p -> {
			Laser l = p.laser;
			int by = p.by;
			int bowlR = l.bowlR(), bowlD = l.bowlD();
			for (int d = 0; d < bowlD; d += 2) {
				int r = Math.max((int) (bowlR * Math.sqrt(1.0 - (double) d / (bowlD + 0.5))), 3);
				float tl = t + 0.3f + d * 0.09f;
				p.dig(r, by - d - 1, by - d, tl, l.bowlRough(), 2);
				p.mottle(r, by - d - 1, by - d, tl, 12);
				double pitch = p.rng.uniform(0.55, 0.85);
				p.groundSound(tl, "block.stone.break", 8f, pitch);
			}
			Laser.Floor fl = l.bowlFloor();
			for (String c : p.disc(bowlR - 4, by - bowlD, by - bowlD + 1, fl.block(), fl.rough(), fl.replace())) {
				p.at(t + 1.8f, c);
			}
		});
		p0.later(t + 0.4f, p -> {
			Laser l = p.laser;
			int bx = p.bx, by = p.by, bz = p.bz;
			int yHi = by - l.bowlD();
			int i = 0;
			while (yHi >= floorY) {
				int r = Math.max((int) Math.round(l.shaftR() - i * 0.25), l.shaftMin());
				float ts = t + 0.5f + i * 0.05f;
				p.dig(r, Math.max(yHi - 3, floorY), yHi, ts, l.shaftRough(), 1);
				p.mottle(r, Math.max(yHi - 3, floorY), yHi, ts, 3);
				if (i % 3 == 0) {
					double pitch = p.rng.uniform(0.5, 0.8);
					p.groundSound(ts, yHi < 0 ? "block.deepslate.break" : "block.stone.break", 7f, pitch);
					p.at(ts, "particle minecraft:lava " + num(bx + 0.5) + " " + yHi + " " + num(bz + 0.5) + " 2 1 2 0 12 force");
				}
				yHi -= 4;
				i++;
			}
			Laser.Bottom[] bottom = l.bottom();
			for (int k = 0; k < bottom.length; k++) {
				Laser.Bottom bt = bottom[k];
				for (String c : p.disc(bt.radius(), floorY + bt.from(), floorY + bt.to(), bt.block(), 0.0, null)) {
					p.at(t + 0.6f + i * 0.05f + 0.1f * k, c);
				}
			}
		});
	}

	private static String fill(boolean alongX, int c, int n0, int n1, int y0, int y1, String what) {
		return alongX ? "fill " + c + " " + y0 + " " + n0 + " " + c + " " + y1 + " " + n1 + " " + what
				: "fill " + n0 + " " + y0 + " " + c + " " + n1 + " " + y1 + " " + c + " " + what;
	}

	private static void trench(Plan p, double[] point, double[] axis, double d0, double d1, int sky) {
		String[] natural = {"#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand", "minecraft:gravel", "#minecraft:terracotta"};
		double[][] steps = {{7.0, 0, -5}, {5.0, -6, -11}, {3.0, -12, -16}};
		Laser laser = p.laser;
		int by = p.by;
		String prim = laser.lining()[0].block();
		boolean alongX = Math.abs(axis[0]) >= Math.abs(axis[1]);
		double m = alongX ? axis[0] : axis[1];
		double n = alongX ? axis[1] : axis[0];
		double pm = alongX ? point[0] : point[2];
		double pn = alongX ? point[2] : point[0];
		double ma = pm + m * d0, mb = pm + m * d1;
		int cLo = (int) Math.floor(Math.min(ma, mb) - 0.5) - 1, cHi = (int) Math.ceil(Math.max(ma, mb) - 0.5) + 1;
		for (int c = cLo; c <= cHi; c++) {
			double d = (c + 0.5 - pm) / m;
			if (d < d0 || d >= d1) {
				continue;
			}
			float t = when(d / TRENCH_L);
			double nc = pn + n * d;
			java.util.function.DoubleFunction<int[]> span = hw -> {
				double e = hw / Math.abs(m);
				return new int[] {(int) Math.ceil(nc - e - 0.5), (int) Math.floor(nc + e - 0.5)};
			};
			int nsteps = d > 95.0 ? 1 : d > 89.0 ? 2 : 3;
			int deepest = by;
			for (int si = 0; si < nsteps; si++) {
				double hw = steps[si][0];
				int top = (int) steps[si][1], bottom = (int) steps[si][2];
				int[] sp = span.apply(hw);
				int y0 = by + bottom, y1 = by + top;
				for (String tag : natural) {
					String what = prim + " replace " + tag;
					p.at(t - 0.05f, fill(alongX, c, sp[0] - 2, sp[0] - 1, y0 - 1, y1, what));
					p.at(t - 0.05f, fill(alongX, c, sp[1] + 1, sp[1] + 2, y0 - 1, y1, what));
					p.at(t - 0.05f, fill(alongX, c, sp[0] - 1, sp[1] + 1, y0 - 1, y0 - 1, what));
				}
				p.at(t, fill(alongX, c, sp[0], sp[1], y0, y1, "minecraft:air"));
				deepest = y0;
			}
			int[] top9 = span.apply(9.0);
			p.at(t, fill(alongX, c, top9[0], top9[1], by + 1, sky, "minecraft:air"));
			for (int i = 0; i < 2; i++) {
				int pick = Math.min((int) (p.rng.next() * nsteps), nsteps - 1);
				double hw = steps[pick][0];
				int top = (int) steps[pick][1], bottom = (int) steps[pick][2];
				int[] w = span.apply(hw);
				int side = p.rng.next() < 0.5 ? w[0] - 1 : w[1] + 1;
				int y = p.rng.integer(by + bottom - 1, by + top);
				String blk = p.rng.weighted(laser.lining(), 1);
				p.at(t + 0.05f, fill(alongX, c, side, side, y - 1, y + 1, blk + " replace " + prim));
			}
			int[] s = span.apply(7.0);
			for (Laser.Scorch sc : laser.scorch()) {
				String what = sc.block() + " replace " + sc.replace();
				p.at(t + 0.3f, fill(alongX, c, s[0] - 12, s[0] - 3, by - 3, by + 1, what));
				p.at(t + 0.3f, fill(alongX, c, s[1] + 3, s[1] + 12, by - 3, by + 1, what));
			}
			if (Math.floorMod(c, 5) == 0) {
				int mid = (int) Math.floor(nc);
				p.at(t + 0.6f, fill(alongX, c, mid, mid, deepest, deepest, "minecraft:lava"));
			}
			if (Math.floorMod(c, 3) == 0) {
				int lip = p.rng.next() < 0.5 ? s[0] - p.rng.integer(2, 6) : s[1] + p.rng.integer(2, 6);
				float dt = (float) p.rng.uniform(0.2, 1.6);
				int x = alongX ? c : lip, z = alongX ? lip : c;
				p.at(t + dt, surf(x, z, "setblock ~ ~ ~ minecraft:fire keep"));
			}
			if (Math.floorMod(c, 4) == 0) {
				int mid = (int) Math.floor(nc);
				int x = alongX ? c : mid, z = alongX ? mid : c;
				double pitch = p.rng.uniform(0.5, 0.8);
				p.at(t, "playsound minecraft:block.stone.break block @a " + x + " " + by + " " + z + " 3 " + f2(pitch));
			}
		}
	}
}
