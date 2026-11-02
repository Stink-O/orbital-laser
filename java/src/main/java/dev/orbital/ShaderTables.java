package dev.orbital;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.BiFunction;

/**
 * The tables the Payload's and the Nuke's screen shaders read (the original's `mod_data`): the path of the object, the
 * column's billows, the pieces it sheds, the debris, and a coarse height map of the land round the target. Ported from
 * strike/payload.rs and strike/nuke.rs (pl_table / nk_table, pl_debris_words / nk_debris_words, pl_hf_* / nk_hf_*).
 *
 * Layout (words): 0..848 the table, 1024.. the height map (8 header words, then 96 x 96 cells), 10496.. the debris.
 */
public final class ShaderTables {
	private static final double TAU = 2.0 * Math.PI;
	private static final int N = 128, PUFFS = 18, P = 16, PF = P + 3 * N, PW = 8, FR = 560, FW = 12, HF = 1024, HN = 96, DB = 10496, DW = 10;

	private ShaderTables() {}

	// ---- hashing (the original's pcg / mh) ----
	private static int pcg(int x) {
		int s = x * 747_796_405 + (int) 2_891_336_453L;
		int w = ((s >>> ((s >>> 28) + 4)) ^ s) * 277_803_737;
		return (w >>> 22) ^ w;
	}

	private static double mh(int i, int seed, int k) {
		return (pcg(i ^ pcg(seed ^ pcg(k))) & 0xFFFFFFFFL) / 4_294_967_296.0;
	}

	private static double[] add(double[] a, double[] b, double k) {
		return new double[] {a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k};
	}

	private static double len(double[] a) {
		return Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
	}

	private static double sstep(double a, double b, double x) {
		double t = Math.max(0, Math.min(1, (x - a) / (b - a)));
		return t * t * (3.0 - 2.0 * t);
	}

	private static double clamp(double v, double lo, double hi) {
		return Math.max(lo, Math.min(hi, v));
	}

	/** The object's path and wind: what the original calls PlGeo / NkGeo. */
	private interface Geo {
		double[] pos(double t);

		double[] wind();

		int seed();
	}

	// ---- the Payload's flight: one ballistic arc ----
	private static Geo payloadGeo(float seedF, double[] me) {
		int seed = (int) seedF;
		java.util.function.IntToDoubleFunction r = k -> mh(k, seed, 0x9a1);
		double d = Math.hypot(me[0], me[2]);
		double[] u = d > 1.0 ? new double[] {me[0] / d, 0.0, me[2] / d} : new double[] {0.0, 0.0, 1.0};
		double side = r.applyAsDouble(1) < 0.5 ? -1.0 : 1.0;
		double phi = Math.toRadians(50.0 + 15.0 * r.applyAsDouble(2)) * side;
		double c = Math.cos(phi), s = Math.sin(phi);
		double[] dir = {-u[0] * c + u[2] * s, 0.0, -u[2] * c - u[0] * s};
		double wa = TAU * r.applyAsDouble(9), ws = 2.0 + 2.5 * r.applyAsDouble(10);
		double dh = 1150.0 + 300.0 * r.applyAsDouble(3), y0 = 1100.0 + 200.0 * r.applyAsDouble(4);
		double[] wind = {Math.cos(wa) * ws, Math.sin(wa) * ws};
		final double SEEN = 3.0, HIT = 13.6, GLIDE = 0.25, CRAWL = 0.42, RUSH = 3.5;
		return new Geo() {
			public double[] pos(double t) {
				double w = clamp((t - SEEN) / (HIT - SEEN), 0, 1);
				double u2 = CRAWL * w + (1.0 - CRAWL) * Math.pow(w, RUSH);
				double y = y0 * (1.0 - (GLIDE * u2 + (1.0 - GLIDE) * u2 * u2));
				return add(new double[] {0.0, y, 0.0}, dir, dh * (1.0 - u2));
			}

			public double[] wind() {
				return wind;
			}

			public int seed() {
				return seed;
			}
		};
	}

	// ---- the Nuke's flight: re-entry, then a steep dive, simulated every 5 ms ----
	private static Geo nukeGeo(float seedF, double[] me) {
		int seed = (int) seedF;
		java.util.function.IntToDoubleFunction r = k -> mh(k, seed, 0x9b1);
		double d = Math.hypot(me[0], me[2]);
		double[] u = d > 1.0 ? new double[] {me[0] / d, 0.0, me[2] / d} : new double[] {0.0, 0.0, 1.0};
		double side = r.applyAsDouble(1) < 0.5 ? -1.0 : 1.0;
		double phi = Math.toRadians(50.0 + 15.0 * r.applyAsDouble(2)) * side;
		double c = Math.cos(phi), s = Math.sin(phi);
		double[] from = {-u[0] * c + u[2] * s, 0.0, -u[2] * c - u[0] * s};
		double wa = TAU * r.applyAsDouble(9), ws = 2.0 + 2.0 * r.applyAsDouble(10);
		double v0 = 410.0 + 60.0 * r.applyAsDouble(3);
		double g0 = Math.toRadians(6.0 + 4.0 * r.applyAsDouble(4));
		final double SEEN = 0.8, COOL = 6.0, HIT = 11.0, BURST = 12.0, DT = 0.005;
		java.util.function.DoubleUnaryOperator speed = t -> {
			double w = clamp((t - SEEN) / (COOL - SEEN), 0, 1);
			double hyper = v0 - (v0 - 140.0) * Math.pow(w, 1.5);
			double dive = 140.0 + 195.0 * Math.pow(clamp((t - COOL) / (HIT - COOL), 0, 1), 1.7);
			return t < COOL ? hyper : dive;
		};
		java.util.function.DoubleUnaryOperator slope = t -> {
			double w = clamp((t - SEEN) / (COOL - SEEN), 0, 1);
			double a = g0 + (Math.toRadians(18.0) - g0) * w * w;
			return a + (Math.toRadians(75.0) - Math.toRadians(18.0)) * sstep(COOL + 1.2, COOL + 3.4, t);
		};
		int n = (int) Math.round((HIT - SEEN) / DT);
		double[][] path = new double[n + 1][];
		double[] p = {0, 0, 0};
		path[0] = p;
		for (int i = 0; i < n; i++) {
			double t = SEEN + DT * (i + 0.5);
			double v = speed.applyAsDouble(t), a = slope.applyAsDouble(t);
			p = add(p, new double[] {-from[0] * Math.cos(a), -Math.sin(a), -from[2] * Math.cos(a)}, v * DT);
			path[i + 1] = p;
		}
		double[] shift = add(new double[] {0.0, BURST, 0.0}, p, -1.0);
		for (int i = 0; i < path.length; i++) {
			path[i] = add(path[i], shift, 1.0);
		}
		double[] wind = {Math.cos(wa) * ws, Math.sin(wa) * ws};
		return new Geo() {
			public double[] pos(double t) {
				if (t >= HIT) {
					return path[path.length - 1];
				}
				double uu = clamp((t - SEEN) / DT, 0, path.length - 1);
				int i = Math.min((int) Math.floor(uu), path.length - 2);
				double f = uu - i;
				return add(path[i], add(path[i + 1], path[i], -1.0), f);
			}

			public double[] wind() {
				return wind;
			}

			public int seed() {
				return seed;
			}
		};
	}

	// ---- the column's billows (the same for both) ----
	private static double[][] puffs(int seed) {
		double[][] out = new double[PUFFS][];
		for (int i = 0; i < PUFFS; i++) {
			final int ii = i;
			java.util.function.IntToDoubleFunction h = k -> mh(ii, seed, 0x5f0 + k);
			double t0, hf, rad;
			if (i < 5) {
				t0 = 0.1 + 0.35 * h.applyAsDouble(0);
				hf = 0.06 + 0.3 * (i / 5.0) + 0.06 * h.applyAsDouble(1);
				rad = 22.0 + 10.0 * h.applyAsDouble(2);
			} else if (i < 11) {
				t0 = 0.05 + 0.25 * h.applyAsDouble(0);
				hf = 0.4 + 0.34 * ((i - 5) / 6.0) + 0.06 * h.applyAsDouble(1);
				rad = 32.0 + 14.0 * h.applyAsDouble(2);
			} else {
				t0 = 0.0 + 0.12 * h.applyAsDouble(0);
				hf = 0.74 + 0.28 * ((i - 11) / 7.0) + 0.05 * h.applyAsDouble(1);
				rad = 50.0 + 18.0 * h.applyAsDouble(2);
			}
			double tau = 0.5 + 0.35 * h.applyAsDouble(3);
			double a = TAU * h.applyAsDouble(4);
			double off = rad * (0.2 + 0.55 * h.applyAsDouble(5)) * (i < 2 ? 1.1 : i < 5 ? 0.5 : 1.0);
			out[i] = new double[] {t0, tau, hf, rad, Math.cos(a) * off, Math.sin(a) * off};
		}
		return out;
	}

	/** The pieces shed on the way in (a few glowing chunks, a spray of sparks). */
	private static double[][] fragments(Geo g, boolean nuke) {
		int chunks = 8, sparks = nuke ? 24 : 16;
		double[][] out = new double[chunks + sparks][];
		java.util.function.DoubleFunction<double[]> vel = t -> {
			double[] a = g.pos(t - 0.02), b = g.pos(t + 0.02);
			return new double[] {(b[0] - a[0]) / 0.04, (b[1] - a[1]) / 0.04, (b[2] - a[2]) / 0.04};
		};
		for (int i = 0; i < chunks + sparks; i++) {
			final int ii = i;
			java.util.function.IntToDoubleFunction h = k -> mh(ii, g.seed(), 0x7a0 + k);
			boolean spark = i >= chunks;
			double t0;
			if (nuke) {
				double seen = 0.8, cool = 6.0;
				t0 = spark ? seen + 0.6 + (cool - seen - 0.4) * Math.pow(h.applyAsDouble(0), 0.8)
						: seen + 1.0 + (cool - seen - 1.4) * Math.pow(h.applyAsDouble(0), 0.7);
			} else {
				double hit = 13.6;
				t0 = spark ? hit - 3.5 + 3.3 * Math.sqrt(h.applyAsDouble(0)) : hit - 6.5 + 5.8 * Math.pow(h.applyAsDouble(0), 0.7);
			}
			double[] p0 = g.pos(t0);
			double[] v = vel.apply(t0);
			double sp = Math.max(len(v), 1.0);
			double[] dir = {v[0] / sp, v[1] / sp, v[2] / sp};
			double a = TAU * h.applyAsDouble(1);
			double[] up = Math.abs(dir[1]) > 0.95 ? new double[] {1, 0, 0} : new double[] {0, 1, 0};
			double[] s1 = {dir[1] * up[2] - dir[2] * up[1], dir[2] * up[0] - dir[0] * up[2], dir[0] * up[1] - dir[1] * up[0]};
			double l1 = Math.max(len(s1), 1e-9);
			s1 = new double[] {s1[0] / l1, s1[1] / l1, s1[2] / l1};
			double[] s2 = {dir[1] * s1[2] - dir[2] * s1[1], dir[2] * s1[0] - dir[0] * s1[2], dir[0] * s1[1] - dir[1] * s1[0]};
			double[] side = add(add(new double[3], s1, Math.cos(a)), s2, Math.sin(a));
			double kick, keep, life, size, drag;
			if (nuke) {
				kick = spark ? 25.0 + 70.0 * h.applyAsDouble(2) : 15.0 + 45.0 * h.applyAsDouble(2);
				keep = spark ? 0.7 + 0.2 * h.applyAsDouble(3) : 0.8 + 0.15 * h.applyAsDouble(3);
				life = spark ? 0.4 + 0.6 * h.applyAsDouble(5) : 1.2 + 1.2 * h.applyAsDouble(5);
				size = spark ? 1.0 + 1.2 * h.applyAsDouble(6) : 1.3 + 1.0 * h.applyAsDouble(6);
				drag = spark ? 1.6 + 1.2 * h.applyAsDouble(7) : 0.8 + 0.6 * h.applyAsDouble(7);
			} else {
				kick = spark ? 40.0 + 110.0 * h.applyAsDouble(2) : 70.0 + 110.0 * h.applyAsDouble(2);
				keep = spark ? 0.55 + 0.3 * h.applyAsDouble(3) : 0.35 + 0.35 * h.applyAsDouble(3);
				life = spark ? 0.35 + 0.6 * h.applyAsDouble(5) : 1.5 + 2.2 * h.applyAsDouble(5);
				size = spark ? 0.25 + 0.35 * h.applyAsDouble(6) : 0.9 + 1.4 * h.applyAsDouble(6);
				drag = spark ? 1.8 + 1.5 * h.applyAsDouble(7) : 0.35 + 0.5 * h.applyAsDouble(7);
			}
			double[] v0 = add(add(new double[3], v, keep), side, kick);
			if (!nuke) {
				v0 = add(v0, new double[] {0.0, 1.0, 0.0}, spark ? 0.0 : 15.0 * h.applyAsDouble(4));
			}
			out[i] = new double[] {t0, life, size, spark ? 1.0 : 0.0, drag, p0[0], p0[1], p0[2], v0[0], v0[1], v0[2]};
		}
		return out;
	}

	private static float[] table(Geo g, boolean nuke) {
		int chunks = 8, sparks = nuke ? 24 : 16;
		float[] w = new float[FR + (chunks + sparks) * FW];
		double seen = nuke ? 0.8 : 3.0, hit = nuke ? 11.0 : 13.6, hc = nuke ? 430.0 : 235.0;
		double dt = (hit - seen) / (N - 1);
		w[0] = N;
		w[1] = (float) seen;
		w[2] = (float) dt;
		w[3] = (float) g.wind()[0];
		w[4] = (float) g.wind()[1];
		w[5] = (float) hc;
		w[6] = PUFFS;
		for (int i = 0; i < N; i++) {
			double[] p = g.pos(seen + dt * i);
			for (int k = 0; k < 3; k++) {
				w[P + 3 * i + k] = (float) p[k];
			}
		}
		double[][] pf = puffs(g.seed());
		for (int i = 0; i < pf.length; i++) {
			for (int k = 0; k < 6; k++) {
				w[PF + PW * i + k] = (float) pf[i][k];
			}
		}
		w[7] = chunks + sparks;
		w[8] = nuke ? 160 : 120;
		double[][] fr = fragments(g, nuke);
		for (int i = 0; i < fr.length; i++) {
			for (int k = 0; k < 11; k++) {
				w[FR + FW * i + k] = (float) fr[i][k];
			}
		}
		return w;
	}

	private static float[] debris(int seed, boolean nuke) {
		int count = nuke ? 160 : 120;
		float[] w = new float[count * DW];
		double v = 343.0;
		for (int i = 0; i < count; i++) {
			final int ii = i;
			java.util.function.IntToDoubleFunction h = k -> mh(ii, seed, k);
			double ang = h.applyAsDouble(0x301) * TAU, big = h.applyAsDouble(0x303);
			double r0, el, sp, size;
			boolean far;
			if (nuke) {
				r0 = 10.0 + 110.0 * Math.sqrt(h.applyAsDouble(0x306));
				far = h.applyAsDouble(0x307) < 0.4;
				el = far ? 0.4 + 0.45 * h.applyAsDouble(0x302) : 0.3 + 0.9 * h.applyAsDouble(0x302);
				sp = (far ? 140.0 + 80.0 * h.applyAsDouble(0x304) : 50.0 + 80.0 * Math.pow(h.applyAsDouble(0x304), 0.7)) * (1.0 - 0.25 * big);
				size = 0.2 + 1.6 * big * big * big;
			} else {
				r0 = 6.0 + 40.0 * Math.sqrt(h.applyAsDouble(0x306));
				far = h.applyAsDouble(0x307) < 0.35;
				el = far ? 0.45 + 0.4 * h.applyAsDouble(0x302) : 0.35 + 0.85 * h.applyAsDouble(0x302);
				sp = (far ? 90.0 + 45.0 * h.applyAsDouble(0x304) : 30.0 + 50.0 * Math.pow(h.applyAsDouble(0x304), 0.7)) * (1.0 - 0.25 * big);
				size = 0.12 + 0.98 * big * big * big;
			}
			double t0 = r0 / v + 0.12 * h.applyAsDouble(0x305);
			double[] row = {Math.cos(ang), Math.sin(ang), r0, Math.cos(el) * sp, Math.sin(el) * sp, t0, size, Math.exp(0.06 * t0),
				3.0 + 6.0 * h.applyAsDouble(0x308), 0.0};
			for (int k = 0; k < row.length; k++) {
				w[DW * i + k] = (float) row[k];
			}
		}
		return w;
	}

	// ---- the land's shape round the target ----
	public static double reach(double dme, boolean nuke) {
		return nuke ? clamp(dme * 1.25 + 250.0, 450.0, 1600.0) : clamp(dme * 1.25 + 150.0, 260.0, 1150.0);
	}

	private static int[] heightMap(double[] heights /* null entries as NaN */, double reach) {
		int n = HN;
		double sum = 0, cnt = 0;
		for (double h : heights) {
			if (!Double.isNaN(h)) {
				sum += h;
				cnt++;
			}
		}
		double guess = cnt > 0 ? sum / cnt : 0.0;
		double[] raw = new double[heights.length];
		for (int i = 0; i < raw.length; i++) {
			raw[i] = Double.isNaN(heights[i]) ? guess : heights[i];
		}
		double[] h = raw.clone();
		for (int k = 1; k < n - 1; k++) {
			for (int i = 1; i < n - 1; i++) {
				int c = k * n + i;
				double[] v = {raw[c - 1], raw[c + 1], raw[c - n], raw[c + n]};
				Arrays.sort(v);
				double med = 0.5 * (v[1] + v[2]);
				if (raw[c] > med + 4.0) {
					h[c] = med;
				}
			}
		}
		// shelter: how far the land between each cell and the blast stands over the line from the blast
		double step = 2.0 * reach / (n - 1);
		double[] shelter = new double[n * n];
		for (int c = 0; c < n * n; c++) {
			double x = -reach + step * (c % n), z = -reach + step * (c / n);
			double r = Math.hypot(x, z);
			if (r < 30.0) {
				shelter[c] = 0.0;
				continue;
			}
			double src = 8.0, dst = h[c] + 3.0;
			int steps = (int) clamp((int) (r / step), 2, 10);
			double over = 0.0;
			for (int j = 1; j < steps; j++) {
				double f = (double) j / steps;
				double px = x * f, pz = z * f;
				double fi = clamp((px + reach) / step, 0.0, n - 1), fk = clamp((pz + reach) / step, 0.0, n - 1);
				int ii = Math.min((int) fi, n - 2), kk = Math.min((int) fk, n - 2);
				double u = fi - ii, vv = fk - kk;
				int cc = kk * n + ii;
				double hh = (h[cc] * (1.0 - u) + h[cc + 1] * u) * (1.0 - vv) + (h[cc + n] * (1.0 - u) + h[cc + n + 1] * u) * vv;
				over = Math.max(over, hh - (src + (dst - src) * f));
			}
			double s = clamp(over / 14.0, 0.0, 1.0);
			shelter[c] = s * s * (3.0 - 2.0 * s);
		}
		double lo = Double.MAX_VALUE, hi = -Double.MAX_VALUE;
		for (double x : h) {
			lo = Math.min(lo, x);
			hi = Math.max(hi, x);
		}
		int[] w = new int[8 + n * n];
		w[0] = Float.floatToRawIntBits((float) n);
		w[1] = Float.floatToRawIntBits((float) reach);
		w[2] = Float.floatToRawIntBits((float) lo);
		w[3] = Float.floatToRawIntBits((float) hi);
		for (int c = 0; c < n * n; c++) {
			int q = (int) clamp(Math.round((h[c] + 512.0) * 8.0), 0, 65535);
			int b = (int) clamp(Math.round(shelter[c] * 255.0), 0, 255);
			w[8 + c] = q | (b << 16);
		}
		return w;
	}

	/**
	 * Everything the Payload's (nuke = false) or the Nuke's (nuke = true) shader reads, as one array of words.
	 *
	 * @param rel    where the player stands from the target's ground point (x, y, z)
	 * @param ground the ground height at a block column, from the target's ground, or null where the chunk is not loaded
	 */
	public static int[] build(boolean nuke, float seed, double[] rel, int bx, int bz, BiFunction<Integer, Integer, Double> ground) {
		Geo g = nuke ? nukeGeo(seed, rel) : payloadGeo(seed, rel);
		float[] t = table(g, nuke);
		float[] d = debris((int) seed, nuke);
		double reach = reach(Math.hypot(rel[0], rel[2]), nuke);
		double step = 2.0 * reach / (HN - 1);
		double[] heights = new double[HN * HN];
		for (int k = 0; k < HN; k++) {
			for (int i = 0; i < HN; i++) {
				int x = bx + (int) Math.round(-reach + step * i), z = bz + (int) Math.round(-reach + step * k);
				Double hh = ground.apply(x, z);
				heights[k * HN + i] = hh == null ? Double.NaN : hh;
			}
		}
		int[] hf = heightMap(heights, reach);
		int[] w = new int[DB + d.length];
		for (int i = 0; i < t.length; i++) {
			w[i] = Float.floatToRawIntBits(t[i]);
		}
		System.arraycopy(hf, 0, w, HF, hf.length);
		for (int i = 0; i < d.length; i++) {
			w[DB + i] = Float.floatToRawIntBits(d[i]);
		}
		return w;
	}

	public static List<String> describe(int[] w) {
		List<String> out = new ArrayList<>();
		out.add("words=" + w.length);
		return out;
	}
}
