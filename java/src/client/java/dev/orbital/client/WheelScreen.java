package dev.orbital.client;

import dev.orbital.Laser;
import java.util.List;
import net.minecraft.ChatFormatting;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;

/**
 * The laser menu: a plain list of buttons. Each runs the same /orbital command you could type, so it behaves exactly like
 * the command does. The Payload and the Nuke have a second button beside them for their alternative blast sound
 * (/orbital payloadsound alt|main, /orbital nukesound alt|main).
 */
public class WheelScreen extends Screen {
	private static final int COL_W = 160, GAP = 10, ROW_H = 20, STEP = 22, ALT_W = 70;

	public WheelScreen() {
		super(Component.literal("Orbital Laser"));
	}

	@Override
	public boolean isPauseScreen() {
		return false;
	}

	/** Runs a command as the player would type it. */
	private static void run(String command) {
		Minecraft mc = Minecraft.getInstance();
		if (mc.player != null) {
			mc.player.connection.sendCommand(command);
		}
	}

	private boolean hasAlt(Laser l) {
		return l.key().equals("payload") || l.key().equals("nuke");
	}

	private boolean altOn(Laser l) {
		return l.key().equals("payload") ? ClientState.payloadAlt : ClientState.nukeAlt;
	}

	@Override
	protected void init() {
		List<Laser> all = Laser.READY;
		int perCol = (all.size() + 1) / 2;
		int x0 = this.width / 2 - (COL_W * 2 + GAP) / 2;
		int y0 = 34;
		for (int i = 0; i < all.size(); i++) {
			Laser l = all.get(i);
			int col = i / perCol, row = i % perCol;
			int x = x0 + col * (COL_W + GAP), y = y0 + row * STEP;
			boolean selected = l.key().equals(ClientState.laser);
			Component label = selected
					? Component.literal("> " + titleCase(l.title())).withStyle(ChatFormatting.GREEN, ChatFormatting.BOLD)
					: Component.literal(titleCase(l.title()));
			int w = hasAlt(l) ? COL_W - ALT_W - 2 : COL_W;
			this.addRenderableWidget(Button.builder(label, b -> {
				ClientState.laser = l.key();
				ClientState.save();
				run("orbital " + l.key());
				this.rebuildWidgets();
			}).bounds(x, y, w, ROW_H).build());
			if (hasAlt(l)) {
				boolean alt = altOn(l);
				Component altLabel = Component.literal(alt ? "Blast: ALT" : "Blast: MAIN")
						.withStyle(alt ? ChatFormatting.AQUA : ChatFormatting.WHITE);
				this.addRenderableWidget(Button.builder(altLabel, b -> {
					boolean now = !altOn(l);
					if (l.key().equals("payload")) {
						ClientState.payloadAlt = now;
						run("orbital payloadsound " + (now ? "alt" : "main"));
					} else {
						ClientState.nukeAlt = now;
						run("orbital nukesound " + (now ? "alt" : "main"));
					}
					this.rebuildWidgets();
				}).bounds(x + w + 2, y, ALT_W, ROW_H).build());
			}
		}
		int yb = y0 + perCol * STEP + 8;
		Component terrain = Component.literal(ClientState.terrain ? "Terrain damage: ON" : "Terrain damage: OFF")
				.withStyle(ClientState.terrain ? ChatFormatting.RED : ChatFormatting.GREEN);
		this.addRenderableWidget(Button.builder(terrain, b -> {
			ClientState.terrain = !ClientState.terrain;
			run("orbital terrain " + (ClientState.terrain ? "on" : "off"));
			this.rebuildWidgets();
		}).bounds(x0, yb, COL_W, ROW_H).build());
		this.addRenderableWidget(Button.builder(Component.literal("Close"), b -> this.onClose())
				.bounds(x0 + COL_W + GAP, yb, COL_W, ROW_H).build());
	}

	private static String titleCase(String s) {
		StringBuilder out = new StringBuilder();
		for (String w : s.toLowerCase().split(" ")) {
			if (out.length() > 0) {
				out.append(' ');
			}
			out.append(Character.toUpperCase(w.charAt(0))).append(w.substring(1));
		}
		return out.toString();
	}

	@Override
	public void extractRenderState(GuiGraphicsExtractor g, int mx, int my, float a) {
		super.extractRenderState(g, mx, my, a);
		g.centeredText(this.font, "ORBITAL LASER", this.width / 2, 12, 0xFFFFFFFF);
		g.centeredText(this.font, "Click a laser to load it, then hold right-click with the Designator", this.width / 2, 23, 0xFFAAAAAA);
		Laser loaded = Laser.byKey(ClientState.laser);
		if (loaded != null) {
			g.centeredText(this.font, loaded.blurb(), this.width / 2, this.height - 22, 0xFF000000 | loaded.rgb());
		}
	}
}
