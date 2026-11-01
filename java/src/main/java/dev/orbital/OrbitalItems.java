package dev.orbital;

import java.util.function.Function;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.Rarity;

public final class OrbitalItems {
	public static Item DESIGNATOR;
	public static Item REMOTE;

	private OrbitalItems() {}

	private static Item register(String name, Function<Item.Properties, Item> factory, Item.Properties props) {
		ResourceKey<Item> key = ResourceKey.create(Registries.ITEM, OrbitalMod.id(name));
		return Registry.register(BuiltInRegistries.ITEM, key, factory.apply(props.setId(key)));
	}

	public static void register() {
		DESIGNATOR = register("laser_designator", DesignatorItem::new, new Item.Properties().stacksTo(1).rarity(Rarity.EPIC));
		REMOTE = register("remote", RemoteItem::new, new Item.Properties().stacksTo(1).rarity(Rarity.RARE));
	}
}
