package dev.orbital.client;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import net.fabricmc.loader.api.FabricLoader;

/** What the wheel last chose, remembered between sessions in config/orbital.txt. */
public final class ClientState {
	public static String laser = "plasma";
	public static boolean terrain = false;
	/** Whether the Payload's and the Nuke's alternative blast sound is picked (see /orbital payloadsound, nukesound). */
	public static boolean payloadAlt = false;
	public static boolean nukeAlt = false;

	private ClientState() {}

	private static Path file() {
		return FabricLoader.getInstance().getConfigDir().resolve("orbital.txt");
	}

	public static void load() {
		try {
			for (String line : Files.readAllLines(file())) {
				if (line.startsWith("laser:")) {
					laser = line.substring(6).trim();
				}
			}
		} catch (IOException ignored) {
			// first run
		}
	}

	public static void save() {
		try {
			Files.write(file(), List.of("laser:" + laser));
		} catch (IOException ignored) {
			// not worth failing for
		}
	}
}
