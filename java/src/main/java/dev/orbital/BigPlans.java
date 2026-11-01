package dev.orbital;

import static dev.orbital.Plan.f1;
import static dev.orbital.Plan.f2;
import static dev.orbital.Plan.num;
import static dev.orbital.Plan.surf;

import java.util.List;
import java.util.Locale;

/**
 * Planet Killer, Downfall, Payload, Nuke, Crystal Bloom and Sinkhole.
 *
 * SIMPLIFIED PORT: the sounds, action-bar messages and their timings are the original's (read from its plans); the sizes
 * (crater, clear, kill and force-load radii) are the ones its notes give. What the original works out in step with its
 * screen shaders (the ship's fall, the towers, the clouds, the spires) is replaced by plainer world changes built from the
 * same crater tools as the other lasers, so the land is not an exact copy of the original's.
 */
public final class BigPlans {
	private BigPlans() {}

	private static final String[] NATURAL5 = {"#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand", "minecraft:gravel", "minecraft:coarse_dirt"};

	// ---- shared helpers ----

	private static String bar(String text, String color) {
		return "title @s actionbar {\"text\":\"" + text + "\",\"color\":\"" + color + "\",\"bold\":true}";
	}

	private static float late(double x, double y, double z, double[] me) {
		return (float) (Math.sqrt(Math.pow(x - me[0], 2) + Math.pow(y - me[1], 2) + Math.pow(z - me[2], 2)) / 343.0);
	}

	private static double smooth(double u) {
		double c = Math.max(0, Math.min(1, u));
		return c * c * (3.0 - 2.0 * c);
	}

	private static int floorY(String dim) {
		return "minecraft:overworld".equals(dim) ? -59 : "minecraft:the_nether".equals(dim) ? 5 : 1;
	}

	private static int skyTop(String dim) {
		return "minecraft:overworld".equals(dim) ? 319 : "minecraft:the_nether".equals(dim) ? 122 : 255;
	}

	/** Keep the chunks within r of (cx, cz) loaded for the strike (forceload takes 256 chunks at most a command). */
	private static void forceload(Plan p, double cx, double cz, int r, float end) {
		int tile = 192;
		for (int x = (int) Math.floor(cx - r); x < cx + r; x += tile) {
			for (int z = (int) Math.floor(cz - r); z < cz + r; z += tile) {
				int x1 = (int) Math.min(x + tile - 1, Math.floor(cx + r)), z1 = (int) Math.min(z + tile - 1, Math.floor(cz + r));
				p.at(0.0f, "forceload add " + x + " " + z + " " + x1 + " " + z1);
				p.at(end, "forceload remove " + x + " " + z + " " + x1 + " " + z1);
			}
		}
	}

	private static void killPasses(Plan p, float t, String tx, String ty, String tz, int r, double[] offsets, String extra) {
		for (double dt : offsets) {
			p.at(t + (float) dt, "execute positioned " + tx + " " + ty + " " + tz + " run kill @e[type=!minecraft:player," + extra + "distance.." + r + "]");
		}
	}

	/** Everything standing over a blast of radius r flattened: from the ground up `up` blocks, and (if skyR > 0) to the sky over the middle. */
	private static void blast(Plan p0, float t, int r, int up, int skyR, int sky) {
		p0.later(t - 0.2f, p -> {
			int by = p.by;
			for (int y0 = by + 1; y0 <= Math.min(by + up, sky); y0 += 20) {
				for (String c : p.disc(r, y0, Math.min(y0 + 19, Math.min(by + up, sky)), "minecraft:air", 0.1, null)) {
					p.at(t + (y0 - by) * 0.004f, c);
				}
			}
			if (skyR > 0) {
				p.clearAbove(t + 0.4f, skyR, by + up + 1, sky, 0.1);
			}
		});
	}

	/** Ground charred out to r (the laser's scorch blocks scaled to r). */
	private static void char_(Plan p0, float t, int r) {
		p0.later(t - 0.1f, p -> {
			int by = p.by;
			String[][] pairs = {{"minecraft:coarse_dirt", "minecraft:grass_block"}, {"minecraft:smooth_basalt", "minecraft:sand"}, {"minecraft:blackstone", "minecraft:dirt"}};
			for (int k = 0; k < pairs.length; k++) {
				int rad = r - k * Math.max(r / 12, 2);
				for (String c : p.disc(rad, by - 3, by + 1, pairs[k][0], 0.1, pairs[k][1])) {
					p.at(t + 0.3f + (float) p.rng.next() * 3.0f, c);
				}
			}
		});
	}

	/** A bowl dug out from the top down, its wall fused into the laser's lining (rim only, so a big one is not held up). */
	private static void bowl(Plan p0, float t, float perLayer, int radius, int depth, int layer, double rough) {
		p0.later(t - 0.2f, p -> {
			String prim = p.laser.lining()[0].block();
			int by = p.by;
			for (int d = 0; d < depth; d += layer) {
				int r = Math.max((int) (radius * Math.sqrt(1.0 - (double) d / (depth + 0.5))), 4);
				float tl = t + d / (float) layer * perLayer;
				int yLo = by - d - layer + 1, yHi = by - d;
				List<int[]> rs = p.rects(r, rough);
				for (String tag : NATURAL5) {
					for (String c : Plan.edgeFills(rs, yLo - 1, yHi, prim, tag, 2)) {
						p.at(tl - 0.05f, c);
					}
				}
				for (String c : Plan.fills(rs, yLo, yHi, "minecraft:air", null, 0)) {
					p.at(tl, c);
				}
				p.mottle(r, yLo, yHi, tl, 8);
				if (d % (layer * 3) == 0) {
					p.groundSound(tl, "block.stone.break", 9f, p.rng.uniform(0.55, 0.9));
				}
			}
			Laser.Floor fl = p.laser.bowlFloor();
			float tEnd = t + depth / (float) layer * perLayer;
			for (String c : p.disc(Math.max(radius - 6, 3), by - depth, by - depth + 1, fl.block(), fl.rough(), fl.replace())) {
				p.at(tEnd, c);
			}
		});
	}

	/** A shaft from y `fromY` down to bedrock, funnelling in, with the laser's bottom blocks. */
	private static void shaft(Plan p0, float t, float perStep, int rMouth, int rMin, int fromY, int floorY) {
		p0.later(t - 0.2f, p -> {
			int i = 0;
			for (int yHi = fromY; yHi >= floorY; yHi -= 4) {
				int r = Math.max((int) Math.round(rMouth - i * 0.3), rMin);
				float ts = t + i * perStep;
				p.dig(r, Math.max(yHi - 3, floorY), yHi, ts, p.laser.shaftRough(), 1);
				if (i % 3 == 0) {
					p.groundSound(ts, yHi < 0 ? "block.deepslate.break" : "block.stone.break", 8f, p.rng.uniform(0.5, 0.8));
				}
				i++;
			}
			Laser.Bottom[] bottom = p.laser.bottom();
			for (int k = 0; k < bottom.length; k++) {
				Laser.Bottom bt = bottom[k];
				for (String c : p.disc(bt.radius(), floorY + bt.from(), floorY + bt.to(), bt.block(), 0.0, null)) {
					p.at(t + i * perStep + 0.1f * k, c);
				}
			}
		});
	}

	/** Rubble thrown across the land and landing between rMin and rMax. */
	private static void rubble(Plan p0, float t, int count, double rMin, double rMax, double speed) {
		p0.later(t - 0.2f, p -> {
			String[] blocks = {"minecraft:cobblestone", "minecraft:blackstone", "minecraft:gravel", "minecraft:tuff", "minecraft:basalt", "minecraft:cobbled_deepslate", "minecraft:coarse_dirt"};
			for (int k = 0; k < count; k++) {
				double a = p.rng.uniform(0.0, 2.0 * Math.PI);
				double rr = rMin + (rMax - rMin) * Math.pow(p.rng.next(), 1.4);
				int x = p.bx + (int) Math.round(Math.cos(a) * rr), z = p.bz + (int) Math.round(Math.sin(a) * rr);
				float tl = t + 0.5f + (float) (rr / speed) + (float) p.rng.uniform(0.0, 1.5);
				String blk = p.rng.pick(blocks);
				p.at(tl, surf(x, z, "setblock ~ ~ ~ " + blk + " keep"));
				if (k % 4 == 0) {
					p.at(tl, surf(x, z, "particle minecraft:block{block_state:\"" + blk + "\"} ~ ~0.5 ~ 0.6 0.4 0.6 0.2 14 force"));
				}
			}
		});
	}

	private static void fires(Plan p0, float t, int count, double rMin, double rMax) {
		p0.later(t - 0.2f, p -> {
			for (int i = 0; i < count; i++) {
				double a = p.rng.uniform(0.0, 2.0 * Math.PI);
				double rr = p.rng.uniform(rMin, rMax);
				p.at(t + (float) p.rng.uniform(0.5, 6.0), surf(p.bx + (int) Math.round(Math.cos(a) * rr), p.bz + (int) Math.round(Math.sin(a) * rr), "setblock ~ ~ ~ minecraft:fire keep"));
			}
		});
	}

	private static void fling(Plan p0, float t, int count, double[] point, int by, double speedLo, double speedHi, String[] blocks) {
		p0.later(t - 0.2f, p -> {
			for (int i = 0; i < count; i++) {
				double a = p.rng.uniform(0.0, 2.0 * Math.PI);
				double rr = p.rng.uniform(4.0, 14.0);
				double sp = p.rng.uniform(speedLo, speedHi);
				double elev = 0.3 + 0.9 * p.rng.next();
				String blk = p.rng.pick(blocks);
				p.at(t + (float) p.rng.uniform(0.0, 1.0), "summon minecraft:falling_block " + f1(point[0] + Math.cos(a) * rr) + " " + (by + 3) + " "
						+ f1(point[2] + Math.sin(a) * rr) + " {BlockState:{Name:\"" + blk + "\"},Time:1,DropItem:0b,Motion:["
						+ String.format(Locale.ROOT, "%.3f", Math.cos(a) * Math.cos(elev) * sp) + "d," + String.format(Locale.ROOT, "%.3f", Math.sin(elev) * sp) + "d,"
						+ String.format(Locale.ROOT, "%.3f", Math.sin(a) * Math.cos(elev) * sp) + "d]}");
			}
		});
	}

	private static Plan start(Laser laser, int bx, int by, int bz) {
		long seed = ((long) bx * 73_856_093L) ^ ((long) bz * 19_349_663L) ^ (long) by;
		return new Plan(laser, new Rng(seed), bx, by, bz);
	}

	private static List<Plan.Ev> done(Plan p) {
		p.ev.sort((a, b) -> Float.compare(a.t(), b.t()));
		return p.ev;
	}

	private static void burstParticles(Plan p, float t, String tx, double ty, String tz, int spread, String block) {
		p.at(t, "particle minecraft:explosion_emitter " + tx + " " + num(ty + 2) + " " + tz + " " + spread + " 6 " + spread + " 0 20 force");
		p.at(t + 0.05f, "particle minecraft:flash " + tx + " " + num(ty + 6) + " " + tz + " 0 0 0 0 1 force");
		p.at(t + 0.05f, "particle minecraft:block{block_state:\"" + block + "\"} " + tx + " " + num(ty + 1) + " " + tz + " " + spread + " 4 " + spread + " 3.0 300 force");
		p.at(t + 0.1f, "particle minecraft:block{block_state:\"minecraft:stone\"} " + tx + " " + num(ty + 1) + " " + tz + " " + (spread * 2) + " 4 " + (spread * 2) + " 2.4 300 force");
	}

	// ======================================================================================================== Planet Killer

	public static List<Plan.Ev> planetKiller(Laser laser, int bx, int by, int bz, double px, double py, double pz, boolean terrain,
			String dim, float seed, double[] me) {
		final float IGN0 = 3.05f, SHOOT = 1.14f, MERGE = 7.6f, DROP = 8.4f, BURST = 9.0f, CUT = 17.65f, POP = 18.55f;
		double tyd = Math.round(py * 100.0) / 100.0;
		String tx = num(Math.round(px * 100.0) / 100.0), ty = num(tyd), tz = num(Math.round(pz * 100.0) / 100.0);
		Plan p = start(laser, bx, by, bz);
		p.setListener(me, new double[] {px, py, pz});
		double dist = Math.sqrt(Math.pow(px - me[0], 2) + Math.pow(py - me[1], 2) + Math.pow(pz - me[2], 2));
		float lt = (float) (dist / 343.0);
		float heard = BURST + lt;
		float nexus = late(px, tyd + 300.0, pz, me);
		double wing = Math.atan2(me[2] - pz, me[0] - px);

		p.at(0.2f, bar("PLANET KILLER: ARRAY RISING", laser.color()));
		p.csound(0.0f, "charge", 10f, 1f);
		// the seven towers round the horizon, each heard from where it stands, then its bolt to the ring
		for (int i = 0; i < 7; i++) {
			double a = wing + Math.PI + i * 2.0 * Math.PI / 7.0 + 0.3;
			double x = px + Math.cos(a) * 1100.0, z = pz + Math.sin(a) * 1100.0;
			float tTower = 2.6f + 0.55f * i; // (approximate: the original's come from its shader geometry)
			float lag = Math.min(late(x, tyd, z, me), 0.35f);
			int take = 1 + i % 3;
			p.at(tTower - 2.25f - 0.7f + lag, "playsound orbital:planetkiller.rise" + take + " block @a " + f1(x) + " " + ty + " " + f1(z) + " 4 " + f2(p.rng.uniform(0.92, 1.07)) + " 0.95");
			double bxx = px + (x - px) * 0.3, byy = tyd + 300.0 + 120.0 * 0.3, bzz = pz + (z - pz) * 0.3;
			float blag = Math.min(late(bxx, byy, bzz, me), 0.3f);
			p.at(tTower + blag, "playsound orbital:planetkiller.bolt" + (1 + i % 3) + " block @a " + f1(bxx) + " " + f1(byy) + " " + f1(bzz) + " 4 " + f2(p.rng.uniform(0.9, 1.1)) + " 1");
		}
		p.csound(IGN0 + SHOOT, "arcs", 10f, 1f);
		p.at(IGN0 + 0.2f, bar("ARRAY CHARGING", laser.color()));
		p.csound(MERGE, "merge", 10f, 1f);
		p.at(MERGE, bar("CONVERGENCE", "aqua"));
		p.csound(DROP + lt, "fire", 10f, 1f);
		p.at(BURST + 0.1f, bar("DIRECT HIT", "white"));
		p.csound(heard + 0.7f, "beam1", 10f, 1f);
		p.csound(heard + 5.4f, "beam2", 10f, 1f);
		p.csound(heard + 1.5f, "rumble", 9f, 1f);
		p.csound(heard + 6.0f, "rumble", 8f, 0.9f);
		p.csound(CUT + lt, "cutoff", 10f, 1f);
		p.csound(POP + 1.0f, "after", 9f, 1f);
		float fo = Math.max(Plan.falloff(dist), 0.45f);
		for (int i = 0; i < 3; i++) {
			p.shake(0.1f + i * 0.25f, new float[] {0.04f, 0.06f, 0.08f}[i], 0.7f);
		}
		for (int i = 0; i < 7; i++) {
			p.shake(2.6f + 0.55f * i, 0.3f, 0.6f);
		}
		for (int i = 0; i < 3; i++) {
			p.shake(MERGE - 1.2f + i * 0.4f, new float[] {0.12f, 0.18f, 0.3f}[i], 1.0f);
		}
		p.shake(MERGE + nexus, 0.55f, 2.0f);
		p.shake(DROP + lt, 0.4f * fo, 0.5f);
		p.shake(heard, fo, 5.0f);
		for (float tj = BURST + 1.2f; tj < CUT; tj += 1.0f) {
			p.shake(tj + lt, 0.24f * fo, 1.3f);
		}
		p.shake(POP + lt, 0.7f * fo, 3.0f);
		p.flash(MERGE - 2.0f, 0x4D7CFF, 0.20f, 2.0f, 1.5f, 0.5f);
		p.flash(MERGE, 0xFFFFFF, 0.7f, 0.05f, 0.2f, 1.2f);
		p.flash(BURST, 0xFFFFFF, 1.0f, 0.03f, 0.4f, 3.0f);
		p.flash(BURST + 0.4f, 0x4D7CFF, 0.22f, 0.5f, CUT - BURST - 1.0f, 2.0f);
		p.flash(POP, 0xFFFFFF, 0.9f, 0.03f, 0.2f, 2.5f);

		for (int i = 0; i < 10; i++) {
			float tk = MERGE - 2.6f + i * 0.3f;
			double s = 24.0 - 1.5 * i;
			p.at(tk, "particle minecraft:white_ash " + tx + " " + num(tyd + 1) + " " + tz + " " + f1(s) + " 1 " + f1(s) + " 0 160 force");
			p.at(tk, "particle minecraft:soul_fire_flame " + tx + " " + num(tyd + 0.5) + " " + tz + " " + f1(s) + " 0.3 " + f1(s) + " 0.02 40 force");
		}
		burstParticles(p, BURST, tx, tyd, tz, 30, "minecraft:obsidian");
		p.beam(DROP, CUT, Math.round(px * 100.0) / 100.0, tyd, Math.round(pz * 100.0) / 100.0, laser.rgb(), 300.0, 5.0, 900);
		float tk = BURST + 0.2f;
		int k = 0;
		while (tk < CUT) {
			p.at(tk, "particle minecraft:soul_fire_flame " + tx + " " + num(tyd + 1) + " " + tz + " 10 3 10 0.25 80 force");
			p.at(tk, "particle minecraft:lava " + tx + " " + num(tyd - 10) + " " + tz + " 20 3 20 0 30 force");
			if (k % 2 == 0) {
				p.at(tk, "particle minecraft:explosion " + tx + " " + num(tyd - 5) + " " + tz + " 20 4 20 0 6 force");
				p.at(tk, "particle minecraft:large_smoke " + tx + " " + num(tyd + 4) + " " + tz + " 30 6 30 0.1 60 force");
			}
			tk += 0.35f;
			k++;
		}
		p.at(POP, "particle minecraft:explosion_emitter " + tx + " " + num(tyd - 20) + " " + tz + " 20 10 20 0 20 force");
		p.at(POP + 0.05f, "particle minecraft:flash " + tx + " " + ty + " " + tz + " 0 0 0 0 1 force");
		for (int i = 0; i < 24; i++) {
			p.at(POP + i * 0.45f, "particle minecraft:ash " + tx + " " + num(tyd + 40) + " " + tz + " 220 30 220 0 180 force");
		}
		killPasses(p, BURST, tx, ty, tz, 280, new double[] {0.1, 0.8, 2.0, 4.0, 7.0, POP - BURST + 0.2}, "type=!minecraft:falling_block,");

		if (terrain) {
			int fl = floorY(dim), sky = skyTop(dim);
			forceload(p, px, pz, 304, laser.length() - 0.2f);
			blast(p, BURST, 340, 24, 120, sky);
			char_(p, BURST + 0.5f, 280);
			bowl(p, BURST + 0.3f, 0.16f, 240, 80, 4, 0.06);
			shaft(p, BURST + 3.0f, 0.1f, 40, 36, by - 80, fl);
			rubble(p, BURST + 0.5f, 400, 250, 380, 160.0);
			fires(p, BURST + 1.0f, 200, 245, 330);
		}
		return done(p);
	}

	// ============================================================================================================== Downfall

	public static List<Plan.Ev> downfall(Laser laser, int bx, int by, int bz, double px, double py, double pz, boolean terrain,
			String dim, float seed, double[] me, int approach) {
		final float DF_CUT = 6.8f, DF_SPLIT = 11.0f, DF_FALL0 = 17.0f, DF_FALL1 = 30.0f, DF_OPEN = 40.0f, ARRIVE = 3.0f;
		double tyd = Math.round(py * 100.0) / 100.0;
		String tx = num(Math.round(px * 100.0) / 100.0), ty = num(tyd), tz = num(Math.round(pz * 100.0) / 100.0);
		Plan p = start(laser, bx, by, bz);
		p.setListener(me, new double[] {px, py, pz});
		float ship = late(px, tyd + 420.0, pz, me);
		// the wreck lies downrange of the target, away from the player, at least 360 in front of them
		double[] dir = {-Math.cos(Math.atan2(me[2] - pz, me[0] - px)), -Math.sin(Math.atan2(me[2] - pz, me[0] - px))};
		double dPlayer = Math.sqrt(Math.pow(px - me[0], 2) + Math.pow(pz - me[2], 2));
		double reach = Math.max(40.0, 360.0 - dPlayer);
		double[] rest = {px + dir[0] * reach, pz + dir[1] * reach};
		float lh = late(rest[0], tyd + 40.0, rest[1], me);
		float lc = late(rest[0], tyd, rest[1], me);

		p.at(ARRIVE - 1.0f, bar("MOTHERSHIP INBOUND " + MothershipPlan.APPROACH_LABELS[Math.min(approach, 4)].toUpperCase(), laser.color()));
		p.csound(ARRIVE - 0.02f, "hum", 8f, 1f);
		p.at(ARRIVE + 0.6f, bar("MOTHERSHIP OVERHEAD", "green"));
		p.csound(ARRIVE + ship + 0.3f, "hum", 8f, 1f);
		p.csound(StandardPlan.FIRE, "divert", 10f, 1f);
		p.at(DF_CUT + 0.1f, bar("CHARGE ABORTED: POWER TO ROOF BATTERIES", "gold"));
		p.at(DF_CUT + 1.6f, bar("METEOR INBOUND", "red"));
		// the roof batteries volley
		for (int i = 0; i < 4; i++) {
			p.csound(8.4f + i * 0.75f, i % 2 == 0 ? "battery1" : "battery2", 8f, 1f);
		}
		p.csound(DF_SPLIT - 7.6f, "approach", 10f, 1f);
		float heard = DF_SPLIT + late(px, tyd + 300.0, pz, me);
		p.csound(heard, "split", 10f, 1f);
		p.at(DF_SPLIT + 0.2f, bar("METEOR BROKEN UP: FRAGMENTS INBOUND", "red"));
		for (int i = 0; i < 3; i++) {
			p.csound(12.5f + i * 1.1f, "hit" + (1 + i), 9f, 1f);
		}
		p.at(15.9f, bar("HULL BREACHED", "dark_red"));
		p.csound(15.6f, "groan1", 8f, 1f);
		p.at(DF_FALL0 + 0.4f, bar("LIFT FAILING", "dark_red"));
		p.csound(DF_FALL0 + late(px, tyd + 200.0, pz, me), "fall", 10f, 1f);
		p.csound(DF_FALL1 - 5.0f, "groan2", 8f, 1f);
		float crash = DF_FALL1 + lc;
		p.csound(crash, "crash", 10f, 1f);
		p.at(DF_FALL1 + 0.2f, bar("IMPACT", "white"));
		p.at(36.0f, bar("ENGINE CONTAINMENT FAILING", "light_purple"));
		p.csound(DF_OPEN + lh, "rupture", 10f, 1f);
		p.at(DF_OPEN + 0.2f, bar("SINGULARITY", "light_purple"));
		p.csound(DF_OPEN + 0.4f + lh, "vortex", 9f, 1f);
		p.csound(DF_OPEN + 6.0f + lh, "vortex", 8f, 0.9f);
		float te = DF_OPEN + 15.0f;
		p.csound(te, "evaporate", 10f, 1f);
		p.csound(te + 3.5f, "after", 8f, 1f);
		double dw = Math.sqrt(Math.pow(rest[0] - me[0], 2) + Math.pow(tyd - me[1], 2) + Math.pow(rest[1] - me[2], 2));
		float few = Plan.falloff(dw);
		for (int i = 0; i < 3; i++) {
			p.shake(12.5f + i * 1.1f, 0.4f + 0.1f * i, 1.2f);
		}
		p.shake(DF_SPLIT + late(px, tyd + 300.0, pz, me), 0.5f, 1.5f);
		p.flash(DF_SPLIT, 0xFFD2A0, 0.5f, 0.05f, 0.2f, 1.5f);
		p.shake(crash, 0.9f * few, 5.0f);
		p.shake(crash + 2.0f, 0.5f * few, 4.0f);
		p.flash(crash, 0xFFFFFF, 0.8f, 0.03f, 0.25f, 2.0f);
		p.flash(DF_OPEN - 4.0f, 0x2A0A40, 0.25f, 3.0f, 14.0f, 4.0f);
		p.shake(DF_OPEN + lh, 0.9f * few, 4.0f);
		p.flash(DF_OPEN, 0xB070FF, 0.4f, 0.05f, 0.4f, 2.5f);
		for (int i = 0; i < 12; i++) {
			p.shake(DF_OPEN + 1.0f + lh + i, 0.18f * few, 1.3f);
		}
		p.shake(te + lh, 0.9f * few, 3.0f);
		p.flash(te, 0xFFFFFF, 1.0f, 0.03f, 0.3f, 2.5f);

		String rx = num(Math.floor(rest[0])), rz = num(Math.floor(rest[1]));
		for (int i = 0; i < 12; i++) {
			float tk = DF_FALL1 + i * 0.25f;
			p.at(tk, "particle minecraft:explosion_emitter " + rx + " " + num(tyd + 3) + " " + rz + " 14 4 14 0 4 force");
			p.at(tk, "particle minecraft:large_smoke " + rx + " " + num(tyd + 4) + " " + rz + " 20 5 20 0.08 80 force");
		}
		for (int i = 0; i < 20; i++) {
			float tk = DF_OPEN + i * 0.7f;
			p.at(tk, "particle minecraft:portal " + rx + " " + num(tyd + 40) + " " + rz + " 0 0 0 16 260 force");
			p.at(tk, "particle minecraft:reverse_portal " + rx + " " + num(tyd + 20) + " " + rz + " 0.6 12 0.6 0.04 140 force");
		}
		p.at(te, "particle minecraft:flash " + rx + " " + num(tyd + 40) + " " + rz + " 0 0 0 0 1 force");
		p.at(te, "particle minecraft:explosion_emitter " + rx + " " + num(tyd + 40) + " " + rz + " 4 4 4 0 4 force");
		killPasses(p, DF_FALL1, rx, ty, rz, 120, new double[] {0.1, 1.0, 3.0, 8.0, 14.0, 20.0}, "type=!minecraft:falling_block,");

		if (terrain) {
			int fl = floorY(dim), sky = skyTop(dim);
			// the wreck crushes the land under its length, a 70-wide strip running downrange from the rest point
			forceload(p, rest[0], rest[1], 160, laser.length() - 0.2f);
			p.later(DF_FALL1 - 0.3f, q -> {
				boolean alongX = Math.abs(dir[0]) >= Math.abs(dir[1]);
				double m = alongX ? dir[0] : dir[1], n = alongX ? dir[1] : dir[0];
				double pm = alongX ? rest[0] : rest[1], pn = alongX ? rest[1] : rest[0];
				double length = 400.0;
				int steps = (int) (length / 2);
				for (int s = 0; s < steps; s++) {
					double d = s * 2.0;
					int c = (int) Math.floor(pm + m * d);
					int nc = (int) Math.floor(pn + n * d);
					int x = alongX ? c : nc, z = alongX ? nc : c;
					float t = DF_FALL1 + (float) smooth(d / length) * 2.6f;
					String span = alongX ? "~ ~-3 ~-35 ~1 ~40 ~35" : "~-35 ~-3 ~ ~35 ~40 ~1";
					q.at(t, surf(x, z, "fill " + span + " minecraft:air"));
					q.at(t + 0.1f, surf(x, z, "fill " + span.replace("~40", "~-1").replace("~-3", "~-4") + " minecraft:coarse_dirt replace #minecraft:dirt"));
				}
			});
			// its engine ruptures into a black hole that digs a crater and shaft where the stern rests
			Plan hole = new Plan(laser, new Rng(((long) (rest[0] * 31) ^ (long) (rest[1] * 17))), (int) Math.floor(rest[0]), by, (int) Math.floor(rest[1]));
			bowl(hole, DF_OPEN + 0.5f, 0.28f, 115, 56, 4, 0.06);
			shaft(hole, DF_OPEN + 4.0f, 0.12f, 8, 7, by - 56, fl);
			rubble(hole, DF_OPEN + 1.0f, 200, 90, 180, 60.0);
			p.ev.addAll(hole.ev);
			// the wreck's black hole arms and thrown rock (as the Black Hole's, around the rest point)
			Plan arms = new Plan(laser, new Rng((long) (rest[0] + rest[1])), (int) Math.floor(rest[0]), by, (int) Math.floor(rest[1]));
			blast(arms, DF_OPEN, 150, 30, 60, sky);
			p.ev.addAll(arms.ev);
		}
		return done(p);
	}

	// =============================================================================================================== Payload

	public static List<Plan.Ev> payload(Laser laser, int bx, int by, int bz, double px, double py, double pz, boolean terrain,
			String dim, float seed, double[] me, boolean alt) {
		final float SEEN = 3.0f, TURN = 10.6f, HIT = 13.6f, DIVE = 3.0f;
		double tyd = Math.round(py * 100.0) / 100.0;
		String tx = num(Math.round(px * 100.0) / 100.0), ty = num(tyd), tz = num(Math.round(pz * 100.0) / 100.0);
		Plan p = start(laser, bx, by, bz);
		double dist = Math.sqrt(Math.pow(px - me[0], 2) + Math.pow(py - me[1], 2) + Math.pow(pz - me[2], 2));
		float late = (float) (dist / 343.0);

		p.at(1.2f, bar("ORBITAL TRACKING: OBJECT DESCENDING", "gray"));
		p.csound(SEEN - 0.3f, "drift", 10f, 1f);
		p.at(7.5f, bar("ORBITAL TRACKING: OBJECT DESCENDING", "gray"));
		p.at(TURN + 0.2f, bar("PAYLOAD INBOUND", "red"));
		p.csound(HIT - DIVE, "dive", 10f, 1f);
		float tg = HIT + (float) (dist / (5.0 * 343.0));
		float gap = HIT + late - tg;
		float gv = (float) (Math.max(0.3, Math.min(1.0, 1.0 / (1.0 + dist / 900.0))) * Math.pow(Math.max(0.25, Math.min(1.0, (gap - 0.05) / 0.9)), 1.5));
		p.csound(tg - 0.02f, alt ? "ground_alt" : "ground", 10f * gv, 1f);
		float arrive = HIT + late;
		double u = Math.max(0.0, Math.min(1.0, (dist - 500.0) / 1000.0));
		float far = (float) (u * u * (3.0 - 2.0 * u));
		if (far < 1.0f) {
			p.csound(arrive - 0.02f, alt ? "blast_alt" : "blast", 10f * (1f - far), 1f);
		}
		if (far > 0.0f) {
			p.csound(arrive - 0.02f, alt ? "blast_alt_far" : "blast_far", 10f * far, 1f);
		}
		p.csound(arrive - 0.15f, "rush", 10f, 1f);
		p.csound(arrive + 2.4f, "tail", 10f, 1f);
		float near = (float) Math.max(0.0, 1.0 - dist / 300.0);
		p.csound(HIT + 3.2f + (float) (dist / 160.0), "debris", 10f * (0.45f + 0.55f * near), 1f);
		p.at(HIT + 1.5f, bar("PAYLOAD DETONATED", "gold"));
		// the screen and the camera: the ground's early thump, then the blast's hard hit and aftershocks
		float fo = Plan.falloff(dist);
		p.shake(tg, 0.45f * (float) Math.max(0.35, Math.min(1.0, 1.6 / (1.0 + dist / 400.0))), 0.35f);
		p.flash(HIT, 0xFFE8C0, (float) Math.max(0.15, Math.min(0.9, 1.4 - dist / 1200.0)), 0.04f, 0.2f, 2.0f);
		p.shake(arrive, Math.max(0.35f, fo), 2.5f);
		for (int i = 0; i < 6; i++) {
			p.shake(arrive + 0.2f + i * 0.1f, 0.3f * fo, 0.4f);
		}
		for (int i = 0; i < 5; i++) {
			p.shake(arrive + 0.8f + i * 0.5f, 0.12f * fo, 1.0f);
		}
		p.flash(arrive, 0xB8A890, 0.30f * Math.max(near, 0.2f), 0.2f, 1.5f, 5.0f);

		burstParticles(p, HIT, tx, tyd, tz, 8, "minecraft:dirt");
		for (int i = 0; i < 30; i++) {
			float tk = HIT + 0.3f + i * 0.5f;
			p.at(tk, "particle minecraft:campfire_signal_smoke " + tx + " " + num(tyd + 6 + i * 3) + " " + tz + " 6 4 6 0.03 30 force");
			p.at(tk, "particle minecraft:large_smoke " + tx + " " + num(tyd + 2 + i) + " " + tz + " 10 2 10 0.05 40 force");
		}
		for (int i = 0; i < 16; i++) {
			p.at(HIT + 0.3f + i * 0.3f, "particle minecraft:cloud " + tx + " " + num(tyd + 1) + " " + tz + " " + (10 + i * 5) + " 0.5 " + (10 + i * 5) + " 0.1 60 force");
		}
		killPasses(p, HIT, tx, ty, tz, 90, new double[] {0.1, 0.9, 2.5, 5.0}, "type=!minecraft:falling_block,");

		if (terrain) {
			int fl = floorY(dim), sky = skyTop(dim);
			forceload(p, px, pz, 124, laser.length() - 1.0f);
			blast(p, HIT + 0.05f, 85, 60, 0, sky);
			char_(p, HIT + 0.2f, 100);
			bowl(p, HIT + 0.2f, 0.12f, 21, 9, 3, 0.1);
			rubble(p, HIT, 220, 40, 105, 30.0);
			fling(p, HIT, 90, new double[] {px, py, pz}, by, 0.8, 2.0, new String[] {"minecraft:dirt", "minecraft:cobblestone", "minecraft:gravel", "minecraft:coarse_dirt"});
			fires(p, HIT + 0.5f, 60, 30, 100);
		}
		return done(p);
	}

	// ================================================================================================================ Nuke

	public static List<Plan.Ev> nuke(Laser laser, int bx, int by, int bz, double px, double py, double pz, boolean terrain,
			String dim, float seed, double[] me, boolean alt) {
		final float TURN = 8.0f, HIT = 11.0f, BURST = 12.0f;
		double tyd = Math.round(py * 100.0) / 100.0;
		String tx = num(Math.round(px * 100.0) / 100.0), ty = num(tyd), tz = num(Math.round(pz * 100.0) / 100.0);
		Plan p = start(laser, bx, by, bz);
		double dist = Math.sqrt(Math.pow(px - me[0], 2) + Math.pow(py - me[1], 2) + Math.pow(pz - me[2], 2));
		float late = (float) (dist / 343.0);

		p.at(0.6f, bar("WARNING: NUCLEAR DEVICE RELEASED", "red"));
		p.at(5.0f, bar("WARNING: NUCLEAR DEVICE INBOUND", "red"));
		p.at(TURN, bar("TAKE COVER", "yellow"));
		p.csound(1.5f, "fall", 10f, 1f);
		float tg = HIT + (float) (dist / (5.0 * 343.0));
		float gap = HIT + late - tg;
		float gv = (float) (Math.max(0.3, Math.min(1.0, 1.0 / (1.0 + dist / 900.0))) * Math.pow(Math.max(0.25, Math.min(1.0, (gap - 0.05) / 0.9)), 1.5));
		p.csound(tg - 0.02f, "ground", 10f * gv, 1f);
		float arrive = HIT + late;
		double u = Math.max(0.0, Math.min(1.0, (dist - 300.0) / 600.0));
		float far = (float) (u * u * (3.0 - 2.0 * u));
		if (far < 1.0f) {
			p.csound(arrive - 0.02f, alt ? "blast_alt" : "blast", 10f * (1f - far), 1f);
		}
		if (far > 0.0f) {
			p.csound(arrive - 0.02f, alt ? "blast_alt_far" : "blast_far", 10f * far * (float) Math.min(1.25 / (1.0 + dist / 2000.0), 1.0), 1f);
		}
		float shockVol = (float) (1.0 / (1.0 + dist / 900.0));
		p.csound(arrive - 0.2f, "shockwave", 10f * Math.max(0.33f, shockVol), 1f);
		p.csound(arrive + 1.5f, "rumble", 10f, 1f);
		float near = (float) Math.max(0.0, 1.0 - dist / 600.0);
		p.csound(arrive + 3.0f, "debris", 10f * (0.5f + 0.5f * near), 1f);
		if (near < 0.75f) {
			p.csound(arrive + 9.0f, "debris", 10f * (0.25f + 0.4f * near), 0.9f);
		}
		p.at(HIT + 2.0f, bar("NUCLEAR DETONATION", "gold"));
		// the screen and the camera: a blinding flash the moment it bursts, then the blast and its shockwave arriving late
		float fo = Plan.falloff(dist);
		float jolt = (float) Math.max(0.35, Math.min(1.0, 2.4 / (1.0 + dist / 500.0)));
		p.flash(BURST, 0xFFFFFF, 1.0f, 0.05f, (float) Math.max(0.6, 1.8 - dist / 1500.0), 5.0f);
		p.flash(BURST + 1.0f, 0xFF8A2E, 0.28f, 1.0f, 6.0f, 6.0f);
		p.shake(tg, 0.45f * (float) Math.max(0.35, Math.min(1.0, 1.6 / (1.0 + dist / 400.0))), 0.4f);
		p.shake(arrive, jolt, 4.0f);
		for (int i = 0; i < 8; i++) {
			p.shake(arrive + 0.2f + i * 0.1f, 0.35f * jolt, 0.4f);
		}
		for (int i = 0; i < 10; i++) {
			p.shake(arrive + 1.0f + i * 0.6f, 0.16f * jolt, 1.2f);
		}
		p.flash(arrive - 0.2f, 0xC8B8A0, 0.35f * Math.max(near, 0.2f), 0.3f, 2.5f, 6.0f);

		burstParticles(p, BURST, tx, tyd + 10, tz, 30, "minecraft:blackstone");
		for (int i = 0; i < 40; i++) {
			float tk = BURST + 0.4f + i * 0.5f;
			p.at(tk, "particle minecraft:campfire_signal_smoke " + tx + " " + num(tyd + 10 + i * 6) + " " + tz + " 14 8 14 0.03 60 force");
			p.at(tk, "particle minecraft:lava " + tx + " " + num(tyd + 6 + i * 4) + " " + tz + " 18 6 18 0 30 force");
			p.at(tk, "particle minecraft:large_smoke " + tx + " " + num(tyd + 4 + i * 5) + " " + tz + " 24 8 24 0.05 80 force");
		}
		for (int i = 0; i < 30; i++) {
			p.at(BURST + 0.2f + i * 0.35f, "particle minecraft:cloud " + tx + " " + num(tyd + 1) + " " + tz + " " + (12 + i * 9) + " 0.6 " + (12 + i * 9) + " 0.12 80 force");
		}
		killPasses(p, BURST, tx, ty, tz, 300, new double[] {0.1, 0.9, 2.5, 5.0, 8.0}, "type=!minecraft:falling_block,");

		if (terrain) {
			int fl = floorY(dim), sky = skyTop(dim);
			forceload(p, px, pz, 304, laser.length() - 1.0f);
			blast(p, BURST, 230, 60, 0, sky);
			char_(p, BURST + 0.5f, 290);
			bowl(p, BURST + 0.2f, 0.18f, 100, 40, 4, 0.1);
			rubble(p, BURST, 300, 100, 280, 140.0);
			fling(p, BURST, 160, new double[] {px, py, pz}, by, 1.2, 3.0, new String[] {"minecraft:dirt", "minecraft:blackstone", "minecraft:cobblestone", "minecraft:basalt"});
			fires(p, BURST + 1.0f, 150, 105, 290);
		}
		return done(p);
	}

	// ============================================================================================================ Crystal Bloom

	public static List<Plan.Ev> crystalBloom(Laser laser, int bx, int by, int bz, double px, double py, double pz, boolean terrain,
			String dim, float seed, double[] me) {
		final float BLOOM0 = 7.6f, RES = 14.0f, DET = 22.0f;
		double tyd = Math.round(py * 100.0) / 100.0;
		String tx = num(Math.round(px * 100.0) / 100.0), ty = num(tyd), tz = num(Math.round(pz * 100.0) / 100.0);
		Plan p = start(laser, bx, by, bz);
		p.setListener(me, new double[] {px, py, pz});
		float lt = late(px, tyd, pz, me);

		p.at(0.2f, bar("CRYSTAL BLOOM: THE LAND WAKES", laser.color()));
		p.csound(lt, "wake", 10f, 1f);
		for (int i = 0; i < 3; i++) {
			p.at(2.2f + i * 1.4f, "playsound orbital:crystalbloom.punch" + (1 + i) + " block @a " + tx + " " + ty + " " + tz + " 4 1 0.9");
		}
		p.at(BLOOM0, bar("BLOOM", laser.color()));
		p.csound(BLOOM0 - 0.3f + lt, "bloom", 10f, 1f);
		p.at(RES, bar("RESONANCE", "aqua"));
		p.csound(RES + lt, "resonance", 10f, 1f);
		p.at(DET, bar("DETONATION", "white"));
		p.csound(DET - 1.0f + lt, "shatter", 10f, 1f);
		p.csound(DET + 1.4f + lt, "tinkle", 10f, 1f);
		p.csound(DET + 5.0f + lt, "after", 9f, 1f);
		double cd = Math.sqrt(Math.pow(px - me[0], 2) + Math.pow(py - me[1], 2) + Math.pow(pz - me[2], 2));
		float fo = Math.max(Plan.falloff(cd), 0.3f);
		// the daylight dimming and glowing as the land wakes, the pulses of the resonance, the flash of the detonation
		p.flash(0.5f, 0x101030, 0.30f, 6.0f, DET - 7.0f, 2.0f);
		p.flash(BLOOM0, 0xE07BFF, 0.14f, 3.0f, DET - BLOOM0 - 3.0f, 1.5f);
		for (int i = 0; i < 3; i++) {
			p.shake(2.2f + i * 1.4f + lt, 0.3f * fo, 0.5f);
		}
		p.shake(BLOOM0 + lt, 0.5f * fo, 2.0f);
		for (int i = 0; i < 16; i++) {
			p.shake(RES + i * 0.5f, 0.05f + 0.01f * i, 0.6f);
			p.flash(RES + i * 0.5f, 0xE0B0FF, 0.07f + 0.005f * i, 0.05f, 0.1f, 0.3f);
		}
		p.flash(DET, 0xFFFFFF, 1.0f, 0.04f, 0.3f, 2.5f);
		p.shake(DET + lt, 0.8f * fo, 3.5f);

		for (int i = 0; i < 14; i++) {
			float tk = 0.5f + i * 0.5f;
			double s = 30.0 - i * 1.5;
			p.at(tk, "particle minecraft:glow " + tx + " " + num(tyd + 1) + " " + tz + " " + f1(s) + " 1 " + f1(s) + " 0.02 60 force");
			p.at(tk, "particle minecraft:end_rod " + tx + " " + num(tyd + 2) + " " + tz + " " + f1(s) + " 6 " + f1(s) + " 0.05 30 force");
		}
		for (int i = 0; i < 12; i++) {
			p.at(DET - 5.0f + i * 0.4f, "particle minecraft:end_rod " + tx + " " + num(tyd + 12) + " " + tz + " 60 14 60 0.08 120 force");
		}
		burstParticles(p, DET, tx, tyd, tz, 60, "minecraft:amethyst_block");
		killPasses(p, DET, tx, ty, tz, 160, new double[] {0.0, 1.0, 3.0, 6.0}, "type=!minecraft:falling_block,");

		if (terrain) {
			int fl = floorY(dim), sky = skyTop(dim);
			forceload(p, px, pz, 240, laser.length() - 1.0f);
			// crystal spires standing before the bloom shatters: columns of amethyst that become stumps
			p.later(BLOOM0 - 0.3f, q -> {
				for (int i = 0; i < 26; i++) {
					double a = q.rng.uniform(0.0, 2.0 * Math.PI);
					double rr = 16.0 + 130.0 * Math.sqrt(q.rng.next());
					int x = q.bx + (int) Math.round(Math.cos(a) * rr), z = q.bz + (int) Math.round(Math.sin(a) * rr);
					int h = q.rng.integer(14, 34);
					float tl = BLOOM0 + (float) (rr / 150.0 * 5.0);
					q.at(tl, surf(x, z, "fill ~ ~ ~ ~ ~" + h + " ~ minecraft:amethyst_block"));
					q.at(tl + 0.1f, surf(x, z, "setblock ~ ~" + (h + 1) + " ~ minecraft:budding_amethyst"));
				}
			});
			blast(p, DET, 130, 24, 0, sky);
			bowl(p, DET + 0.2f, 0.1f, 88, 28, 4, 0.05);
			shaft(p, DET + 3.0f, 0.1f, 10, 10, by - 28, fl);
			p.later(DET - 0.2f, q -> {
				for (int i = 0; i < 160; i++) {
					double a = q.rng.uniform(0.0, 2.0 * Math.PI);
					double rr = q.rng.uniform(20.0, 235.0);
					int x = q.bx + (int) Math.round(Math.cos(a) * rr), z = q.bz + (int) Math.round(Math.sin(a) * rr);
					q.at(DET + 1.0f + (float) (rr / 80.0), surf(x, z, "setblock ~ ~ ~ " + q.rng.pick("minecraft:amethyst_cluster", "minecraft:small_amethyst_bud", "minecraft:large_amethyst_bud") + " keep"));
				}
			});
		}
		return done(p);
	}

	// ================================================================================================================ Sinkhole

	public static List<Plan.Ev> sinkhole(Laser laser, int bx, int by, int bz, double px, double py, double pz, boolean terrain,
			String dim, float seed, double[] me) {
		final float C0 = 8.6f;
		double tyd = Math.round(py * 100.0) / 100.0;
		String tx = num(Math.round(px * 100.0) / 100.0), ty = num(tyd), tz = num(Math.round(pz * 100.0) / 100.0);
		Plan p = start(laser, bx, by, bz);
		p.setListener(me, new double[] {px, py, pz});
		float lt = late(px, tyd, pz, me);

		p.at(0.2f, bar("SEISMIC WARNING: TREMORS UNDER THE TARGET", laser.color()));
		p.csound(lt, "rumble", 10f, 1f);
		for (int i = 0; i < 3; i++) {
			p.at(1.5f + i * 0.9f, "playsound orbital:sinkhole.crack" + (1 + i) + " block @a " + tx + " " + ty + " " + tz + " 4 1 0.9");
			p.at(2.4f + i * 1.3f, "playsound orbital:sinkhole.groan" + (1 + i) + " block @a " + tx + " " + ty + " " + tz + " 4 1 0.9");
		}
		p.at(3.6f, bar("SEISMIC WARNING: THE GROUND IS GIVING WAY", "red"));
		p.at(6.0f, "playsound orbital:sinkhole.give block @a " + tx + " " + ty + " " + tz + " 4 1 0.9");
		p.csound(C0 - 0.6f + lt, "collapse", 10f, 1f);
		p.csound(C0 + 1.2f + lt, "rockfall", 10f, 1f);
		p.at(C0, bar("COLLAPSE", "white"));
		p.at(16.5f, bar("SINKHOLE", laser.color()));
		p.csound(17.5f + lt, "trickle", 10f, 1f);
		double sd = Math.sqrt(Math.pow(px - me[0], 2) + Math.pow(py - me[1], 2) + Math.pow(pz - me[2], 2));
		float fo = Math.max(Plan.falloff(sd), 0.35f);
		// the tremors building, the give, the collapse, and the dust hanging over the pit
		for (float tj = 0.2f; tj < C0; tj += 0.9f) {
			p.shake(tj + lt, (0.05f + 0.012f * tj) * fo, 1.0f);
		}
		p.shake(6.0f + lt, 0.35f * fo, 1.0f);
		p.shake(C0 + lt, 0.7f * fo, 3.0f);
		for (float tj = C0 + 1.0f; tj < 23.0f; tj += 0.8f) {
			p.shake(tj + lt, 0.18f * fo, 1.0f);
		}
		p.flash(C0, 0x8A7A66, 0.28f, 2.0f, 9.0f, 5.0f);

		for (int i = 0; i < 16; i++) {
			float tk = 0.6f + i * 0.5f;
			p.at(tk, "particle minecraft:block{block_state:\"minecraft:dirt\"} " + tx + " " + num(tyd + 1) + " " + tz + " " + (6 + i * 5) + " 0.5 " + (6 + i * 5) + " 0.1 40 force");
			p.at(tk, "particle minecraft:poof " + tx + " " + num(tyd + 1) + " " + tz + " " + (6 + i * 5) + " 0.5 " + (6 + i * 5) + " 0.05 30 force");
		}
		for (int i = 0; i < 40; i++) {
			float tk = C0 + i * 0.35f;
			p.at(tk, "particle minecraft:large_smoke " + tx + " " + num(tyd + 3) + " " + tz + " 70 4 70 0.08 120 force");
			p.at(tk, "particle minecraft:cloud " + tx + " " + num(tyd + 6) + " " + tz + " 60 6 60 0.05 60 force");
		}
		killPasses(p, C0, tx, ty, tz, 140, new double[] {0.0, 1.0, 3.0, 6.0, 10.0}, "type=!minecraft:falling_block,");

		if (terrain) {
			int fl = floorY(dim), sky = skyTop(dim);
			forceload(p, px, pz, 152, laser.length() - 1.0f);
			// the land caves in from the middle out, slab by slab, down to bedrock; the wall darkens with depth
			p.later(C0 - 0.4f, q -> {
				int by2 = q.by;
				int depth = by2 - fl;
				int layers = Math.max(depth / 4, 1);
				for (int i = 0; i < layers; i++) {
					int yHi = by2 - 4 * i;
					int r = (int) Math.round(112 * (1.0 - 0.18 * i / layers));
					float tl = C0 + (float) (i * (14.4 / layers));
					String lining = yHi > 20 ? "minecraft:tuff" : yHi > -20 ? "minecraft:deepslate" : "minecraft:blackstone";
					List<int[]> rs = q.rects(r, 0.1);
					for (String tag : NATURAL5) {
						for (String c : Plan.edgeFills(rs, yHi - 4, yHi, lining, tag, 2)) {
							q.at(tl - 0.05f, c);
						}
					}
					for (String c : Plan.fills(rs, yHi - 3, yHi, "minecraft:air", null, 0)) {
						q.at(tl, c);
					}
					if (i % 3 == 0) {
						q.groundSound(tl, "block.stone.break", 9f, q.rng.uniform(0.5, 0.8));
					}
				}
				// everything over the pit gone, up to the sky
				q.clearAbove(C0 + 0.3f, 112, by2 + 1, sky, 0.1);
				for (String c : q.disc(108, fl, fl + 1, "minecraft:cobblestone", 0.2, "minecraft:stone")) {
					q.at(C0 + 15.0f, c);
				}
			});
			rubble(p, C0 + 6.0f, 200, 20, 100, 25.0);
		}
		return done(p);
	}
}
