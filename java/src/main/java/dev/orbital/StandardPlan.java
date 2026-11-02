package dev.orbital;

import static dev.orbital.Plan.f1;
import static dev.orbital.Plan.f2;
import static dev.orbital.Plan.num;
import static dev.orbital.Plan.surf;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Plasma, Godly and Black Hole: the original's strike.rs `plan` and their aftermaths, as vanilla commands. */
public final class StandardPlan {
	public static final float FIRE = 4.0f;
	private static final int KILL_RADIUS = 40;
	private static final double PILLAR_R = 40.0;
	private static final double PILLAR_A0 = Math.PI / 6.0;
	private static final double HOLE_H = 28.0;
	private static final float BH_END = 10.0f;
	private static final int DEBRIS = 160;

	private StandardPlan() {}

	private static String r2(double v) {
		return num(Math.round(v * 100.0) / 100.0);
	}

	private static double fract(double v) {
		return v - Math.floor(v);
	}

	private static int skyTop(String dim) {
		return switch (dim) {
			case "minecraft:overworld" -> 319;
			case "minecraft:the_nether" -> 122;
			default -> 255;
		};
	}

	private static int bedrockTop(String dim) {
		return switch (dim) {
			case "minecraft:overworld" -> -59;
			case "minecraft:the_nether" -> 5;
			default -> 1;
		};
	}

	public static List<Plan.Ev> plan(Laser laser, int bx, int by, int bz, double px, double py, double pz,
			boolean terrain, String dimension, float shaderSeed, double[] me) {
		String tx = r2(px), ty = r2(py), tz = r2(pz);
		double tyd = Math.round(py * 100.0) / 100.0;
		double txd = Math.round(px * 100.0) / 100.0;
		double tzd = Math.round(pz * 100.0) / 100.0;
		long seed = ((long) bx * 73_856_093L) ^ ((long) bz * 19_349_663L) ^ (long) by;
		Plan p = new Plan(laser, new Rng(seed), bx, by, bz);
		p.setListener(me, new double[] {px, py, pz});
		boolean plasma = laser.key().equals("plasma");
		boolean godly = laser.key().equals("godly");
		boolean blackhole = laser.key().equals("blackhole");
		float t = FIRE;

		// charge, lock-on, impact
		p.csound(0.0f, "charge", 10.0f, 1.0f);
		p.csound(3.4f, "lockon", 8.0f, 1.0f);
		p.at(3.5f, "title @s actionbar {\"text\":\"ORBITAL LASER: LOCKED  [" + laser.title() + "]\",\"color\":\"" + laser.color() + "\",\"bold\":true}");
		p.farCsound(t, "fire", 10.0f, 1.0f);
		// the camera and the screen: a hard jolt when the blast reaches the player, then the beam shaking the ground
		double dist = Math.sqrt(Math.pow(px - me[0], 2) + Math.pow(py - me[1], 2) + Math.pow(pz - me[2], 2));
		float lt = (float) (dist / 343.0), fo = Plan.falloff(dist);
		p.shake(t + lt, new float[] {0.95f, 0.8f, 0.9f}[(godly ? 1 : 0) + 2 * (blackhole ? 1 : 0)] * fo, 3.0f);
		if (plasma) {
			for (int i = 0; i < 9; i++) {
				p.shake(t + lt + 0.6f + i, 0.22f * fo, 1.3f);
			}
			p.flash(t, 0xFFFFFF, 0.85f, 0.04f, 0.12f, 1.4f);
			p.flash(t + 0.3f, laser.rgb(), 0.16f, 0.6f, 7.0f, 2.5f);
		}
		if (godly) {
			for (int i = 0; i < 6; i++) {
				p.shake(t + lt + 0.8f + i * 1.4f, 0.12f * fo, 1.6f);
			}
			p.flash(0.3f, laser.rgb(), 0.10f, 3.0f, 0.5f, 0.5f);
			p.flash(t, 0xFFFFFF, 0.9f, 0.04f, 0.2f, 1.8f);
			p.flash(t + 0.3f, laser.rgb(), 0.14f, 0.8f, 8.0f, 3.0f);
		}
		if (blackhole) {
			p.shake(t - 1.0f, 0.3f * fo, 1.2f);
			for (int i = 0; i < 9; i++) {
				p.shake(t + lt + 0.5f + i, 0.18f * fo, 1.2f);
			}
			p.flash(0.4f, 0x180830, 0.30f, 3.0f, 9.0f, 3.0f);
			p.flash(t, 0xB070FF, 0.35f, 0.05f, 0.3f, 2.0f);
			double dh = Math.sqrt(Math.pow(px - me[0], 2) + Math.pow(py + HOLE_H - me[1], 2) + Math.pow(pz - me[2], 2));
			p.shake(t + BH_END + (float) (dh / 343.0), 0.95f * Plan.falloff(dh), 3.0f);
			p.flash(t + BH_END, 0xFFFFFF, 1.0f, 0.03f, 0.25f, 2.2f);
		}
		float[][] booms = {{0.0f, 0.42f}, {0.06f, 0.55f}, {0.2f, 0.7f}, {0.5f, 0.5f}};
		for (float[] b : booms) {
			p.farSound(t + b[0], "entity.generic.explode", 10.0f, b[1]);
		}
		p.farSound(t + 0.05f, "entity.lightning_bolt.thunder", 9.0f, 0.55);
		p.farSound(t + 0.9f, "entity.lightning_bolt.thunder", 6.0f, 0.75);
		p.at(t, "particle minecraft:explosion_emitter " + tx + " " + num(tyd + 1.0) + " " + tz + " 0 0 0 0 1 force");
		p.at(t + 0.1f, "title @s actionbar {\"text\":\"DIRECT HIT\",\"color\":\"white\",\"bold\":true}");
		for (int i = 0; i < 3; i++) {
			p.farCsound(t + 0.2f + i * 3.4f, "beam", 9.0f, 1.0f);
		}
		p.farCsound(t + 0.6f, "rumble", 9.0f, 0.95f);
		p.farCsound(t + 4.2f, "rumble", 8.0f, 0.85f);
		float[] accents = plasma ? new float[] {1.1f, 2.4f, 3.9f, 5.3f, 6.8f} : new float[] {1.4f, 3.9f, 6.6f};
		for (int i = 0; i < accents.length; i++) {
			p.farCsound(t + accents[i], "accent", 7.0f + (i % 2), 0.85f + 0.12f * ((i * 3) % 4));
		}
		if (terrain) {
			for (int i = 0; i < 3; i++) {
				p.farCsound(t + 1.2f + i * 2.6f, "collapse", 8.0f, 0.92f + 0.08f * i);
			}
		}
		p.farCsound(t + 9.2f, "shutdown", 9.0f, 1.0f);

		if (terrain) {
			for (int k = 0; k < 14; k++) {
				String name = p.rng.pick("block.stone.break", "block.gravel.break", "block.grass.break", "block.wood.break");
				double pitch = p.rng.uniform(0.5, 0.9);
				p.groundSound(t + 0.05f + k * 0.07f, name, 10.0f, pitch);
			}
			for (int i = 0; i < 10; i++) {
				float dt = (float) p.rng.uniform(0.0, 2.5);
				String name = p.rng.pick("block.stone.break", "block.gravel.break");
				double pitch = p.rng.uniform(0.6, 1.1);
				p.groundSound(t + 1.0f + dt, name, 6.0f, pitch);
			}
		}

		// ---- particles in the world ----
		String shard = plasma ? "minecraft:blackstone" : godly ? "minecraft:calcite" : "minecraft:crying_obsidian";
		p.at(t + 0.05f, "particle minecraft:block{block_state:\"" + shard + "\"} " + tx + " " + num(tyd + 1.0) + " " + tz + " 3 1 3 2.2 700 force");
		p.at(t + 0.1f, "particle minecraft:block{block_state:\"minecraft:stone\"} " + tx + " " + num(tyd + 1.0) + " " + tz + " 5 1 5 1.6 500 force");
		if (plasma || godly) {
			// the beam / pillar of light from the sky (a particle stand-in for the original's shader)
			p.beam(t, t + 9.0f, txd, tyd, tzd, laser.rgb(), 160.0, godly ? 2.5 : 1.2, 500);
		}
		if (plasma) {
			for (int i = 0; i < 18; i++) {
				p.at(t + 0.3f + i * 0.5f, "particle minecraft:electric_spark " + tx + " " + num(tyd + 3.0) + " " + tz + " 5 6 5 0.8 70 force");
			}
		}
		if (godly) {
			for (int i = 0; i < 8; i++) {
				double s = 6.0 - i * 0.6;
				p.at(0.3f + i * 0.45f, "particle minecraft:end_rod " + tx + " " + num(tyd + 0.5) + " " + tz + " " + f1(s) + " 0.1 " + f1(s) + " 0.01 14 force");
			}
			for (int i = 0; i < 22; i++) {
				p.at(t + 0.4f + i * 0.6f, "particle minecraft:end_rod " + tx + " " + num(tyd + 2.0) + " " + tz + " 9 2 9 0.06 45 force");
				if (i % 2 == 0) {
					p.at(t + 0.6f + i * 0.6f, "particle minecraft:white_ash " + tx + " " + num(tyd + 30.0) + " " + tz + " 24 18 24 0 260 force");
				}
			}
		}

		if (blackhole) {
			double hy = tyd + HOLE_H;
			p.sound(0.2f, "block.portal.trigger", 8.0f, 0.5);
			for (int i = 0; i < 12; i++) {
				double s = 2.0 + i * 0.9;
				p.at(0.4f + i * 0.3f, "particle minecraft:portal " + tx + " " + num(hy) + " " + tz + " 0 0 0 " + f1(s) + " " + (40 + i * 12) + " force");
			}
			p.farSound(t, "entity.warden.sonic_boom", 10.0f, 0.5);
			p.farSound(t + 0.1f, "block.end_portal.spawn", 10.0f, 0.6);
			p.at(t, "particle minecraft:sonic_boom " + tx + " " + num(hy) + " " + tz + " 0 0 0 0 1 force");
			p.at(t + 0.05f, "particle minecraft:sonic_boom " + tx + " " + num(tyd + 2.0) + " " + tz + " 0 0 0 0 1 force");
			for (int i = 0; i < 24; i++) {
				float tk = t + 0.3f + i * 0.4f;
				p.at(tk, "particle minecraft:portal " + tx + " " + num(hy) + " " + tz + " 0 0 0 16 260 force");
				p.at(tk, "particle minecraft:portal " + tx + " " + num(hy - 6.0) + " " + tz + " 0 0 0 7 120 force");
				if (i % 2 == 0) {
					p.at(tk, "particle minecraft:reverse_portal " + tx + " " + num((tyd + hy) / 2.0) + " " + tz + " 0.6 12 0.6 0.04 140 force");
					p.at(tk, "particle minecraft:squid_ink " + tx + " " + num(tyd + 1.5) + " " + tz + " 14 1 14 0.05 60 force");
				}
			}
			float te = t + BH_END;
			p.at(te, "particle minecraft:flash " + tx + " " + num(hy) + " " + tz + " 0 0 0 0 1 force");
			p.at(te, "particle minecraft:explosion_emitter " + tx + " " + num(hy) + " " + tz + " 2 2 2 0 3 force");
			p.at(te, "particle minecraft:end_rod " + tx + " " + num(hy) + " " + tz + " 0 0 0 1.4 500 force");
			p.at(te + 0.05f, "particle minecraft:reverse_portal " + tx + " " + num(hy) + " " + tz + " 1 1 1 2.5 700 force");
			p.farSound(te, "entity.generic.explode", 10.0f, 0.45);
			p.farSound(te + 0.02f, "entity.lightning_bolt.thunder", 10.0f, 0.5);
			p.farSound(te + 0.1f, "block.beacon.deactivate", 10.0f, 0.5);
		}

		if (terrain) {
			int rMouth = laser.shaftR();
			int floorY = bedrockTop(dimension);
			double[] point = {txd, tyd, tzd};
			int bladeR = blackhole ? 52 : 44;
			int sky = skyTop(dimension);
			p.later(0.1f, q -> {
				for (String c : q.disc(bladeR, by + 1, Math.min(by + 60, sky), "minecraft:air", 0.12, null)) {
					q.at(t + 0.15f, c);
				}
				q.clearAbove(t + 0.15f, bladeR, by + 61, sky, 0.12);
			});
			p.later(0.15f, q -> {
				float tScorch = blackhole ? t + 7.6f : t + 0.4f;
				for (Laser.Scorch sc : q.laser.scorch()) {
					for (String c : q.disc(sc.radius(), by - 3, by + 1, sc.block(), sc.rough(), sc.replace())) {
						float dt = (float) q.rng.next() * 2.2f;
						q.at(tScorch + dt, c);
					}
				}
			});
			p.later(0.2f, q -> {
				Laser l = q.laser;
				int bowlR = l.bowlR(), bowlD = l.bowlD();
				for (int d = 0; d < bowlD; d += 2) {
					int r = Math.max((int) (bowlR * Math.sqrt(1.0 - (double) d / (bowlD + 0.5))), 3);
					float tl = t + 0.5f + d * 0.28f;
					q.dig(r, by - d - 1, by - d, tl, l.bowlRough(), 2);
					q.mottle(r, by - d - 1, by - d, tl, 16);
					for (int i = 0; i < 3; i++) {
						float dt = (float) q.rng.uniform(0.0, 0.25);
						String name = q.rng.pick("block.stone.break", "block.gravel.break", "block.grass.break");
						double pitch = q.rng.uniform(0.55, 0.9);
						q.groundSound(tl + dt, name, 9.0f, pitch);
					}
				}
				Laser.Floor fl = l.bowlFloor();
				for (String c : q.disc(bowlR - 4, by - bowlD, by - bowlD + 1, fl.block(), fl.rough(), fl.replace())) {
					q.at(t + 4.2f, c);
				}
			});
			p.later(0.25f, q -> {
				Laser l = q.laser;
				int bowlD = l.bowlD();
				int steps = Math.max((by - bowlD - floorY) / 4 + 1, 1);
				for (int i = 0; i < steps; i++) {
					int yHi = by - bowlD - 4 * i;
					if (yHi < floorY) {
						break;
					}
					int r = Math.max((int) Math.round(rMouth - i * (double) (rMouth - l.shaftMin()) / 14.0), l.shaftMin());
					float ts = t + 1.2f + i * (8.2f / steps);
					q.dig(r, Math.max(yHi - 3, floorY), yHi, ts, l.shaftRough(), 1);
					q.mottle(r, Math.max(yHi - 3, floorY), yHi, ts, 3);
					double pitch = q.rng.uniform(0.5, 0.8);
					q.groundSound(ts, yHi < 0 ? "block.deepslate.break" : "block.stone.break", 8.0f, pitch);
					if (i % 2 == 0) {
						double pitch2 = q.rng.uniform(0.6, 0.9);
						q.groundSound(ts + 0.1f, "block.gravel.break", 6.0f, pitch2);
					}
					q.at(ts, fmt(l.particleA(), bx, bz, by + 1, r * 0.6));
					q.at(ts, fmt(l.particleB(), bx, bz, yHi, r * 0.4));
				}
				float tb = t + 9.6f;
				Laser.Bottom[] bottom = l.bottom();
				for (int k = 0; k < bottom.length; k++) {
					Laser.Bottom bt = bottom[k];
					for (String c : q.disc(bt.radius(), floorY + bt.from(), floorY + bt.to(), bt.block(), 0.0, null)) {
						q.at(tb + 0.1f * k, c);
					}
				}
			});
			p.later(0.3f, q -> {
				if (plasma) {
					plasmaAftermath(q);
				}
				if (godly) {
					godlyAftermath(q);
				}
				if (blackhole) {
					blackholeAftermath(q, point, shaderSeed);
				}
			});
		}
		if (godly) {
			p.at(t + 1.0f, "execute positioned " + tx + " " + ty + " " + tz + " run effect give @a[distance=..60] minecraft:regeneration 15 1 true");
			p.at(t + 1.0f, "execute positioned " + tx + " " + ty + " " + tz + " run effect give @a[distance=..60] minecraft:absorption 30 1 true");
		}
		for (double tk : new double[] {0.15, 0.9, 2.5, 5.0, 8.0}) {
			p.at(t + (float) tk, "execute positioned " + tx + " " + ty + " " + tz + " run kill @e[type=!minecraft:player,distance=.." + KILL_RADIUS + "]");
		}
		p.ev.sort((a, b) -> Float.compare(a.t(), b.t()));
		return p.ev;
	}

	private static String fmt(String s, int bx, int bz, int y, double rr) {
		return s.replace("{x}", num(bx + 0.5)).replace("{y}", Integer.toString(y)).replace("{z}", num(bz + 0.5)).replace("{r}", f1(rr));
	}

	private static void plasmaAftermath(Plan p) {
		float t = FIRE;
		int bx = p.bx, by = p.by, bz = p.bz;
		int bowlR = p.laser.bowlR(), bowlD = p.laser.bowlD(), mouth = p.laser.shaftR();
		for (int k = 0; k < 8; k++) {
			double a = p.rng.uniform(0.0, 2.0 * Math.PI);
			double rr = p.rng.uniform(mouth + 3, bowlR - 6);
			int x = bx + (int) Math.round(Math.cos(a) * rr), z = bz + (int) Math.round(Math.sin(a) * rr);
			for (String blk : new String[] {"minecraft:obsidian", "minecraft:magma_block", "minecraft:black_stained_glass"}) {
				p.at(t + 4.6f + k * 0.2f, surf(x, z, "fill ~-1 ~-1 ~-1 ~1 ~-1 ~1 minecraft:lava replace " + blk));
			}
		}
		p.at(t + 5.0f, surf(bx, bz, "playsound minecraft:block.lava.ambient block @a ~ ~ ~ 3 0.6"));
		int span = bowlR + 3;
		int y0 = by - bowlD - 2;
		while (y0 < by + 2) {
			p.at(t + 19.0f, "fill " + (bx - span) + " " + y0 + " " + (bz - span) + " " + (bx + span) + " " + Math.min(y0 + 4, by + 1) + " " + (bz + span) + " minecraft:obsidian replace minecraft:lava");
			y0 += 5;
		}
		p.at(t + 19.0f, surf(bx, bz, "playsound minecraft:block.fire.extinguish block @a ~ ~ ~ 3 0.7"));
		for (int i = 0; i < 36; i++) {
			double a = p.rng.uniform(0.0, 2.0 * Math.PI);
			double rr = p.rng.uniform(bowlR + 1, 39.0);
			float dt = (float) p.rng.uniform(0.0, 3.0);
			p.at(t + 2.0f + dt, surf(bx + (int) Math.round(Math.cos(a) * rr), bz + (int) Math.round(Math.sin(a) * rr), "setblock ~ ~ ~ minecraft:fire keep"));
		}
		String[] rubble = {"minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:blackstone", "minecraft:gravel",
			"minecraft:magma_block", "minecraft:obsidian", "minecraft:basalt", "minecraft:cobblestone"};
		for (int k = 0; k < 80; k++) {
			double a = p.rng.uniform(0.0, 2.0 * Math.PI);
			double rr = 38.0 + 60.0 * Math.pow(p.rng.next(), 1.6);
			int x = bx + (int) Math.round(Math.cos(a) * rr), z = bz + (int) Math.round(Math.sin(a) * rr);
			float tl = t + 1.0f + (float) (rr / 95.0 * 4.5) + (float) p.rng.uniform(0.0, 1.0);
			String blk = p.rng.pick(rubble);
			p.at(tl, surf(x, z, "setblock ~ ~ ~ " + blk + " keep"));
			if (p.rng.next() < 0.45) {
				int dx = p.rng.pick(-1, 0, 1), dz = p.rng.pick(-1, 0, 1);
				String blk2 = p.rng.pick(rubble);
				p.at(tl + 0.05f, surf(x + dx, z + dz, "setblock ~ ~ ~ " + blk2 + " keep"));
			}
			p.at(tl, surf(x, z, "particle minecraft:block{block_state:\"" + blk + "\"} ~ ~0.5 ~ 0.5 0.4 0.5 0.2 18 force"));
			if (k % 3 == 0) {
				double pitch = p.rng.uniform(0.5, 0.8);
				p.at(tl, surf(x, z, "playsound minecraft:block.basalt.break block @a ~ ~ ~ 2.5 " + f2(pitch)));
			}
		}
	}

	private static void godlyAftermath(Plan p) {
		float t = FIRE;
		int bx = p.bx, by = p.by, bz = p.bz;
		int bowlR = p.laser.bowlR();
		double r1 = bowlR + 3, r2 = PILLAR_R;
		String gold = "setblock ~ ~-1 ~ minecraft:gold_block";
		double[][] verts = new double[6][2];
		for (int k = 0; k < 6; k++) {
			double a = PILLAR_A0 + k * Math.PI / 3.0;
			verts[k][0] = bx + 0.5 + Math.cos(a) * r2;
			verts[k][1] = bz + 0.5 + Math.sin(a) * r2;
		}
		Set<Long> done = new HashSet<>();
		for (double[] v : verts) {
			done.add(key((int) Math.floor(v[0]), (int) Math.floor(v[1])));
		}
		double[] rads = {r1, r2};
		float[] t0s = {1.6f, 2.4f};
		for (int ri = 0; ri < 2; ri++) {
			double rad = rads[ri];
			int n = (int) (2.0 * Math.PI * rad * 1.3);
			for (int i = 0; i < n; i++) {
				double a = (double) i / n * 2.0 * Math.PI;
				etch(p, done, bx + (int) Math.round(Math.cos(a) * rad), bz + (int) Math.round(Math.sin(a) * rad), t + t0s[ri] + 2.4f * i / n, gold);
			}
		}
		for (int k = 0; k < 6; k++) {
			double[] a = verts[k], b = verts[(k + 2) % 6];
			int n = (int) (Math.sqrt(Math.pow(b[0] - a[0], 2) + Math.pow(b[1] - a[1], 2)) * 1.2);
			for (int i = 0; i <= n; i++) {
				double u = (double) i / n;
				etch(p, done, (int) Math.floor(a[0] + (b[0] - a[0]) * u), (int) Math.floor(a[1] + (b[1] - a[1]) * u), t + 4.6f + 2.6f * (float) u, gold);
			}
		}
		for (int k = 0; k < 6; k++) {
			int x = (int) Math.floor(verts[k][0]), z = (int) Math.floor(verts[k][1]);
			float tl = t + 0.45f + 0.25f * k;
			p.at(tl, surf(x, z, "fill ~ ~ ~ ~ ~9 ~ minecraft:quartz_pillar"));
			p.at(tl + 0.1f, surf(x, z, "setblock ~ ~ ~ minecraft:sea_lantern"));
			p.at(tl + 0.15f, surf(x, z, "setblock ~ ~ ~ minecraft:end_rod"));
			p.at(tl, surf(x, z, "playsound minecraft:block.amethyst_block.resonate block @a ~ ~ ~ 3 0.6"));
		}
		String[] flowers = {"minecraft:oxeye_daisy", "minecraft:lily_of_the_valley", "minecraft:azure_bluet", "minecraft:white_tulip",
			"minecraft:dandelion", "minecraft:oxeye_daisy", "minecraft:short_grass"};
		for (int k = 0; k < 320; k++) {
			double a = p.rng.uniform(0.0, 2.0 * Math.PI);
			double rr = 45.0 + 55.0 * Math.sqrt(p.rng.next());
			int x = bx + (int) Math.round(Math.cos(a) * rr), z = bz + (int) Math.round(Math.sin(a) * rr);
			float tl = t + 2.5f + (float) ((rr - 45.0) / 55.0 * 8.0) + (float) p.rng.uniform(0.0, 0.4);
			String flower = p.rng.pick(flowers);
			p.at(tl, surf(x, z, "execute if block ~ ~-1 ~ minecraft:grass_block run setblock ~ ~ ~ " + flower + " keep"));
			if (k % 5 == 0) {
				p.at(tl, surf(x, z, "particle minecraft:wax_on ~ ~0.6 ~ 0.4 0.3 0.4 0 4 force"));
			}
		}
		for (int k = 0; k < 6; k++) {
			double a = k * 2.0 * Math.PI / 6.0 + p.rng.uniform(-0.4, 0.4);
			double rr = p.rng.uniform(11.0, bowlR - 2);
			int x = bx + (int) Math.round(Math.cos(a) * rr), z = bz + (int) Math.round(Math.sin(a) * rr);
			int y = by + p.rng.integer(15, 30);
			int s = p.rng.pick(2, 2, 3);
			float tl = t + 5.5f + k * 0.45f;
			p.at(tl, "fill " + (x - s) + " " + y + " " + (z - s) + " " + (x + s) + " " + y + " " + (z + s) + " minecraft:grass_block");
			int[][] corners = {{x - s, z - s}, {x - s, z + s}, {x + s, z - s}, {x + s, z + s}};
			for (int[] c : corners) {
				p.at(tl, "setblock " + c[0] + " " + y + " " + c[1] + " minecraft:air");
			}
			p.at(tl, "fill " + (x - s + 1) + " " + (y - 1) + " " + (z - s + 1) + " " + (x + s - 1) + " " + (y - 1) + " " + (z + s - 1) + " minecraft:dirt");
			int s2 = Math.max(s - 2, 0);
			p.at(tl, "fill " + (x - s2) + " " + (y - 2) + " " + (z - s2) + " " + (x + s2) + " " + (y - 2) + " " + (z + s2) + " minecraft:calcite");
			p.at(tl, "setblock " + x + " " + (y - 3) + " " + z + " minecraft:gold_block");
			int fx = x + p.rng.pick(-1, 1);
			String flower = p.rng.pick(flowers);
			p.at(tl, "setblock " + fx + " " + (y + 1) + " " + z + " " + flower);
			p.at(tl, "particle minecraft:end_rod " + x + " " + y + " " + z + " " + s + " 1 " + s + " 0.08 40 force");
			p.at(tl, "playsound minecraft:block.amethyst_block.chime block @a " + x + " " + y + " " + z + " 3 0.7");
		}
	}

	private static long key(int x, int z) {
		return ((long) x << 32) ^ (z & 0xFFFFFFFFL);
	}

	private static void etch(Plan p, Set<Long> done, int x, int z, float tt, String gold) {
		if (done.add(key(x, z))) {
			p.at(tt, surf(x, z, gold));
		}
	}

	private static double debrisAngle(int i, float seed) {
		return fract(i * 0.381966 + seed * 0.1137) * 2.0 * Math.PI;
	}

	private static double debrisR0(int i, float seed) {
		return 35.0 + 15.0 * fract(i * 0.618034 + seed * 0.1234);
	}

	private static float debrisT(int i) {
		return 0.4f + 6.0f * i / DEBRIS + 0.3f * (float) fract(i * 0.7548777f);
	}

	private static boolean debrisBig(int i, float seed) {
		return fract(i * 0.2763932 + seed * 0.0517) > 0.78;
	}

	private static void blackholeAftermath(Plan p, double[] point, float seed) {
		float t = FIRE;
		int by = p.by;
		for (int i = 0; i < DEBRIS; i++) {
			double a = debrisAngle(i, seed), r0 = debrisR0(i, seed);
			int x = (int) Math.floor(point[0] + Math.cos(a) * r0), z = (int) Math.floor(point[2] + Math.sin(a) * r0);
			float tl = t + debrisT(i);
			if (debrisBig(i, seed)) {
				p.at(tl, "fill " + (x - 1) + " " + (by - 1) + " " + (z - 1) + " " + x + " " + by + " " + z + " minecraft:air");
			} else {
				p.at(tl, "setblock " + x + " " + by + " " + z + " minecraft:air");
			}
			p.at(tl, "particle minecraft:block{block_state:\"minecraft:dirt\"} " + x + " " + (by + 1) + " " + z + " 0.8 0.3 0.8 0.3 24 force");
			if (i % 5 == 0) {
				double pitch = p.rng.uniform(0.5, 0.8);
				p.at(tl, "playsound minecraft:block.rooted_dirt.break block @a " + x + " " + by + " " + z + " 3 " + f2(pitch));
			}
		}
		String[] flung = {"minecraft:dirt", "minecraft:cobblestone", "minecraft:stone", "minecraft:grass_block",
			"minecraft:cobbled_deepslate", "minecraft:oak_log", "minecraft:gravel"};
		for (int i = 0; i < 70; i++) {
			double a = p.rng.uniform(0.0, 2.0 * Math.PI);
			double rr = p.rng.uniform(10.0, 22.0);
			double x = point[0] + Math.cos(a) * rr, z = point[2] + Math.sin(a) * rr;
			double y = by + HOLE_H + p.rng.uniform(-2.0, 2.0);
			double sp = p.rng.uniform(1.0, 1.9);
			double vx = (Math.sin(a) * 0.9 + Math.cos(a) * 0.45) * sp, vz = (-Math.cos(a) * 0.9 + Math.sin(a) * 0.45) * sp;
			double vy = p.rng.uniform(0.1, 0.7);
			String blk = p.rng.pick(flung);
			float tl = t + (float) p.rng.uniform(1.5, 9.8);
			p.at(tl, "summon minecraft:falling_block " + f2(x) + " " + f2(y) + " " + f2(z) + " {BlockState:{Name:\"" + blk
					+ "\"},Time:1,DropItem:0b,Motion:[" + String.format(java.util.Locale.ROOT, "%.3f", vx) + "d,"
					+ String.format(java.util.Locale.ROOT, "%.3f", vy) + "d," + String.format(java.util.Locale.ROOT, "%.3f", vz) + "d]}");
		}
		int bx = p.bx, bz = p.bz;
		double bowlR = p.laser.bowlR();
		double hy = by + HOLE_H;
		String[] arms = {"minecraft:sculk", "minecraft:black_concrete", "minecraft:sculk", "minecraft:crying_obsidian"};
		double a0 = p.rng.uniform(0.0, 2.0 * Math.PI);
		for (int arm = 0; arm < 4; arm++) {
			int lastX = Integer.MIN_VALUE, lastZ = Integer.MIN_VALUE;
			for (int i = 0; i < 150; i++) {
				double u = i / 149.0;
				double rr = 44.0 + 56.0 * u;
				double a = a0 + arm * Math.PI / 2.0 + Math.log(rr / 44.0) * 2.6 + p.rng.uniform(-0.03, 0.03);
				int x = bx + (int) Math.round(Math.cos(a) * rr), z = bz + (int) Math.round(Math.sin(a) * rr);
				if (x == lastX && z == lastZ) {
					continue;
				}
				lastX = x;
				lastZ = z;
				int w = u < 0.5 ? 1 : 0;
				String blk = p.rng.pick(arms);
				float tl = t + 0.6f + (float) (1.0 - u) * 5.0f;
				for (String tag : new String[] {"#minecraft:dirt", "#minecraft:sand", "#minecraft:base_stone_overworld"}) {
					p.at(tl, surf(x, z, "fill ~-" + w + " ~-1 ~-" + w + " ~" + w + " ~-1 ~" + w + " " + blk + " replace " + tag));
				}
				if (i % 6 == 0) {
					p.at(tl, surf(x, z, "particle minecraft:portal ~ ~0.5 ~ 0 0 0 1.5 12 force"));
				}
			}
		}
		String[] torn = {"minecraft:obsidian", "minecraft:crying_obsidian", "minecraft:cobbled_deepslate", "minecraft:blackstone",
			"minecraft:obsidian", "minecraft:amethyst_block"};
		for (int k = 0; k < 8; k++) {
			double a = k * Math.PI / 4.0 + p.rng.uniform(-0.25, 0.25);
			double r0 = bowlR + p.rng.uniform(2.0, 6.0);
			double x0 = bx + 0.5 + Math.cos(a) * r0, z0 = bz + 0.5 + Math.sin(a) * r0;
			double reach = p.rng.uniform(0.55, 0.8);
			float tk = t + 1.5f + k * 0.7f;
			for (int i = 0; i < 44; i++) {
				double u = i / 43.0 * reach;
				double rr = r0 + (7.0 - r0) * u;
				double aa = a + 0.9 * u * u;
				double x = bx + 0.5 + Math.cos(aa) * rr, z = bz + 0.5 + Math.sin(aa) * rr;
				double y = by + (hy - 4.0 - by) * Math.pow(u, 1.4);
				String blk = u > reach * 0.85 ? "minecraft:crying_obsidian" : p.rng.pick(torn);
				float tl = tk + (float) (u / reach) * 1.6f;
				p.at(tl, "setblock " + (int) Math.floor(x) + " " + (int) Math.floor(y) + " " + (int) Math.floor(z) + " " + blk);
				if (i == 0) {
					p.at(tl, surf((int) Math.floor(x0), (int) Math.floor(z0), "fill ~ ~-1 ~ ~ ~ ~ " + blk));
					p.at(tl, "playsound minecraft:block.sculk_shrieker.shriek block @a " + f1(x) + " " + f1(y) + " " + f1(z) + " 2 0.5");
				}
				if (i % 8 == 0) {
					p.at(tl, "particle minecraft:block{block_state:\"" + blk + "\"} " + f1(x) + " " + f1(y) + " " + f1(z) + " 0.4 0.4 0.4 0.1 10 force");
				}
			}
		}
		float te = t + BH_END;
		for (int i = 0; i < 120; i++) {
			double a = p.rng.uniform(0.0, 2.0 * Math.PI);
			double rr = 9.0 + 16.0 * Math.sqrt(p.rng.next());
			int x = bx + (int) Math.round(Math.cos(a) * rr), z = bz + (int) Math.round(Math.sin(a) * rr);
			int y = (int) Math.round(hy + p.rng.uniform(-1.5, 1.5) + Math.sin(a * 2.0) * 2.0);
			String blk = p.rng.pick(torn);
			float tl = te + (float) p.rng.uniform(0.0, 0.15);
			p.at(tl, "setblock " + x + " " + y + " " + z + " " + blk);
		}
		p.at(te + 0.2f, "playsound minecraft:block.amethyst_block.resonate block @a " + bx + " " + (int) hy + " " + bz + " 4 0.5");
	}
}
