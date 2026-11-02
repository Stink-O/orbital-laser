package dev.orbital;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;
import net.minecraft.sounds.SoundEvent;

/** One sound event for every key of the original mod's sounds.json, so "orbital:charge" etc. exist. */
public final class OrbitalSounds {
	private static final Map<String, SoundEvent> EVENTS = new HashMap<>();

	private OrbitalSounds() {}

	public static void register() {
		try (Reader r = new InputStreamReader(
				OrbitalSounds.class.getResourceAsStream("/assets/orbital/sounds.json"), StandardCharsets.UTF_8)) {
			JsonObject root = JsonParser.parseReader(r).getAsJsonObject();
			for (String key : root.keySet()) {
				Identifier id = OrbitalMod.id(key);
				SoundEvent event = SoundEvent.createVariableRangeEvent(id);
				Registry.register(BuiltInRegistries.SOUND_EVENT, id, event);
				EVENTS.put(key, event);
			}
		} catch (Exception e) {
			throw new IllegalStateException("could not read orbital sounds.json", e);
		}
	}

	/** The sounds /orbital stop cuts: every one of the mod's own, and the vanilla ones the strikes lean on. */
	public static java.util.List<String> cutOnStop() {
		java.util.List<String> out = new java.util.ArrayList<>();
		for (String key : EVENTS.keySet()) {
			out.add("orbital:" + key);
		}
		out.addAll(java.util.List.of("minecraft:entity.generic.explode", "minecraft:entity.lightning_bolt.thunder",
				"minecraft:block.portal.trigger", "minecraft:entity.warden.sonic_boom", "minecraft:block.end_portal.spawn",
				"minecraft:block.beacon.deactivate"));
		return out;
	}

	public static SoundEvent get(String key) {
		return EVENTS.get(key);
	}
}
