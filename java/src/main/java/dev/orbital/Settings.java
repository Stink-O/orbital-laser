package dev.orbital;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/** Per-player choices (the loaded laser, terrain damage). Terrain damage starts OFF: strikes are permanent. */
public final class Settings {
	public static final class Player {
		public String laser = "plasma";
		public boolean terrain = false;
		public int approach = 0;            // ahead, behind, left, right, overhead
		public int arrival = 0;             // snap, unfold, warp
		public int colour = 0;              // green, red, amber, blue, violet, white
		public boolean messages = true;
		public boolean hud = true;
		public boolean quality = false;     // false = fast, true = full
		public boolean payloadAlt = false;
		public boolean nukeAlt = false;
		public float skip = 0f;             // start the next strike this many seconds in (terrain off only)
	}

	private static final Map<UUID, Player> ALL = new ConcurrentHashMap<>();

	private Settings() {}

	public static Player of(UUID id) {
		return ALL.computeIfAbsent(id, k -> new Player());
	}
}
