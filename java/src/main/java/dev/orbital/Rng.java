package dev.orbital;

import java.util.List;

/** The original mod's random numbers (xorshift64*), bit for bit, so the same target gives the same roughness. */
public final class Rng {
	private long s;

	public Rng(long seed) {
		this.s = (seed * 0x9E3779B97F4A7C15L) | 1L;
	}

	public double next() {
		long x = s;
		x ^= x >>> 12;
		x ^= x << 25;
		x ^= x >>> 27;
		s = x;
		return (double) ((x * 0x2545F4914F6CDD1DL) >>> 11) / (double) (1L << 53);
	}

	public double uniform(double a, double b) {
		return a + (b - a) * next();
	}

	public int integer(int a, int b) {
		return a + (int) Math.floor(next() * (double) (b - a + 1));
	}

	public <T> T pick(List<T> items) {
		return items.get(Math.min((int) (next() * items.size()), items.size() - 1));
	}

	@SafeVarargs
	public final <T> T pick(T... items) {
		return pick(List.of(items));
	}

	public String weighted(Laser.Lining[] items, int from) {
		float total = 0;
		for (int i = from; i < items.length; i++) {
			total += items[i].share();
		}
		float r = (float) next() * total;
		for (int i = from; i < items.length; i++) {
			if (r < items[i].share()) {
				return items[i].block();
			}
			r -= items[i].share();
		}
		return items[items.length - 1].block();
	}
}
