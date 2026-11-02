package dev.orbital.client;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.player.LocalPlayer;

/**
 * The strike's effects on the player's own screen: a camera shake (the view nudged a little each tick, undone the
 * next) and colour laid over the whole screen (flashes, glows, dimming). A stand-in for the original's shader effects.
 */
public final class ClientFx {
	private record ShakeE(float strength, long start, long durMs) {}

	private record FlashE(int rgb, float alpha, long start, float in, float hold, float out) {}

	private static final List<ShakeE> SHAKES = new ArrayList<>();
	private static final List<FlashE> FLASHES = new ArrayList<>();
	private static final Random RNG = new Random();
	private static float lastYaw, lastPitch;

	private ClientFx() {}

	public static synchronized void shake(float strength, float seconds) {
		SHAKES.add(new ShakeE(strength, System.currentTimeMillis(), (long) (seconds * 1000)));
	}

	public static synchronized void flash(int rgb, float alpha, float in, float hold, float out) {
		FLASHES.add(new FlashE(rgb, alpha, System.currentTimeMillis(), in, hold, out));
	}

	/** /orbital stop: the shakes and tints end at once. */
	public static synchronized void clear() {
		SHAKES.clear();
		FLASHES.clear();
	}

	/** Once a client tick: take off last tick's nudge and put on this tick's. */
	public static synchronized void tick(Minecraft mc) {
		LocalPlayer p = mc.player;
		if (p == null) {
			SHAKES.clear();
			FLASHES.clear();
			lastYaw = 0;
			lastPitch = 0;
			return;
		}
		long now = System.currentTimeMillis();
		float total = 0f;
		for (var it = SHAKES.iterator(); it.hasNext();) {
			ShakeE s = it.next();
			float u = (now - s.start) / (float) Math.max(s.durMs, 1);
			if (u >= 1f) {
				it.remove();
				continue;
			}
			total += s.strength * (1f - u) * (1f - u); // (the original squares a jolt's strength)
		}
		total = Math.min(total, 1f);
		float dy = (RNG.nextFloat() * 2f - 1f) * total * 3.0f;
		float dx = (RNG.nextFloat() * 2f - 1f) * total * 2.4f;
		p.setYRot(p.getYRot() + dy - lastYaw);
		p.setXRot(Math.max(-90f, Math.min(90f, p.getXRot() + dx - lastPitch)));
		lastYaw = dy;
		lastPitch = dx;
	}

	/** The HUD layer under everything else: the colours over the world. */
	public static synchronized void render(GuiGraphicsExtractor g, DeltaTracker dt) {
		if (FLASHES.isEmpty()) {
			return;
		}
		Minecraft mc = Minecraft.getInstance();
		int w = mc.getWindow().getGuiScaledWidth(), h = mc.getWindow().getGuiScaledHeight();
		long now = System.currentTimeMillis();
		for (var it = FLASHES.iterator(); it.hasNext();) {
			FlashE f = it.next();
			float e = (now - f.start) / 1000f;
			float a;
			if (e < f.in) {
				a = e / Math.max(f.in, 1e-3f);
			} else if (e < f.in + f.hold) {
				a = 1f;
			} else if (e < f.in + f.hold + f.out) {
				a = 1f - (e - f.in - f.hold) / Math.max(f.out, 1e-3f);
			} else {
				it.remove();
				continue;
			}
			int alpha = Math.max(0, Math.min(255, (int) (a * f.alpha * 255f)));
			g.fill(0, 0, w, h, (alpha << 24) | (f.rgb & 0xFFFFFF));
		}
	}
}
