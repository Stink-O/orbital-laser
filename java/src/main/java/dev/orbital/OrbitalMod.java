package dev.orbital;

import com.mojang.brigadier.arguments.BoolArgumentType;
import net.fabricmc.api.ModInitializer;
import net.fabricmc.fabric.api.command.v2.CommandRegistrationCallback;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.fabricmc.fabric.api.networking.v1.PayloadTypeRegistry;
import net.fabricmc.fabric.api.networking.v1.ServerPlayNetworking;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.Identifier;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class OrbitalMod implements ModInitializer {
	public static final String MOD_ID = "orbital";
	public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);

	@Override
	public void onInitialize() {
		OrbitalSounds.register();
		OrbitalItems.register();
		ServerTickEvents.END_SERVER_TICK.register(server -> Strike.tickAll());

		PayloadTypeRegistry.serverboundPlay().register(Net.SelectLaser.TYPE, Net.SelectLaser.CODEC);
		PayloadTypeRegistry.serverboundPlay().register(Net.SetTerrain.TYPE, Net.SetTerrain.CODEC);
		PayloadTypeRegistry.clientboundPlay().register(Net.OpenWheel.TYPE, Net.OpenWheel.CODEC);
		PayloadTypeRegistry.clientboundPlay().register(Net.Shake.TYPE, Net.Shake.CODEC);
		PayloadTypeRegistry.clientboundPlay().register(Net.StrikeFx.TYPE, Net.StrikeFx.CODEC);
		PayloadTypeRegistry.clientboundPlay().register(Net.StrikeData.TYPE, Net.StrikeData.CODEC);
		PayloadTypeRegistry.clientboundPlay().register(Net.StopFx.TYPE, Net.StopFx.CODEC);
		PayloadTypeRegistry.clientboundPlay().register(Net.Flash.TYPE, Net.Flash.CODEC);
		ServerPlayNetworking.registerGlobalReceiver(Net.SelectLaser.TYPE, (payload, context) -> {
			if (Laser.byKey(payload.key()) != null) {
				Settings.of(context.player().getUUID()).laser = payload.key();
			}
		});
		ServerPlayNetworking.registerGlobalReceiver(Net.SetTerrain.TYPE, (payload, context) ->
			Settings.of(context.player().getUUID()).terrain = payload.on());

		CommandRegistrationCallback.EVENT.register((dispatcher, registryAccess, environment) -> {
			var root = Commands.literal("orbital")
				.requires(Commands.hasPermission(Commands.LEVEL_GAMEMASTERS))
				.then(Commands.literal("give").executes(ctx -> {
					ServerPlayer p = ctx.getSource().getPlayerOrException();
					p.getInventory().add(new ItemStack(OrbitalItems.DESIGNATOR));
					p.getInventory().add(new ItemStack(OrbitalItems.REMOTE));
					say(p, "Orbital Laser Designator and Orbital Remote added to your inventory");
					return 1;
				}))
				.then(Commands.literal("terrain")
					.then(Commands.literal("on").executes(ctx -> terrain(ctx.getSource().getPlayerOrException(), true)))
					.then(Commands.literal("off").executes(ctx -> terrain(ctx.getSource().getPlayerOrException(), false))))
				.then(Commands.literal("stop").executes(ctx -> {
					int n = Strike.count();
					Strike.stopAll(ctx.getSource().getServer());
					say(ctx.getSource().getPlayerOrException(), n == 0 ? "No strikes on" : "Stopped " + n + (n == 1 ? " strike" : " strikes"));
					return 1;
				}));
			for (Laser laser : Laser.ALL) {
				root = root.then(Commands.literal(laser.key()).executes(ctx -> {
					ServerPlayer p = ctx.getSource().getPlayerOrException();
					Settings.of(p.getUUID()).laser = laser.key();
					boolean ported = Strike.isPorted(laser.key());
					say(p, "Loaded " + laser.title() + (ported ? "" : " (not ported to this Fabric version yet: it will not fire)"));
					return 1;
				}));
			}
			root = root
				.then(Commands.literal("wheel").executes(ctx -> {
					ServerPlayNetworking.send(ctx.getSource().getPlayerOrException(), new Net.OpenWheel());
					return 1;
				}))
				.then(choice("approach", new String[] {"ahead", "behind", "left", "right", "overhead"}, (s, i) -> s.approach = i))
				.then(choice("arrival", new String[] {"snap", "unfold", "warp"}, (s, i) -> s.arrival = i))
				.then(choice("colour", new String[] {"green", "red", "amber", "blue", "violet", "white"}, (s, i) -> s.colour = i))
				.then(choice("quality", new String[] {"fast", "full"}, (s, i) -> s.quality = i == 1))
				.then(choice("payloadsound", new String[] {"main", "alt"}, (s, i) -> s.payloadAlt = i == 1))
				.then(choice("nukesound", new String[] {"main", "alt"}, (s, i) -> s.nukeAlt = i == 1))
				.then(choice("messages", new String[] {"on", "off"}, (s, i) -> s.messages = i == 0))
				.then(choice("hud", new String[] {"on", "off"}, (s, i) -> s.hud = i == 0))
				.then(Commands.literal("flyspeed")
					.then(Commands.literal("reset").executes(ctx -> flySpeed(ctx.getSource().getPlayerOrException(), 1.0f)))
					.then(Commands.argument("times", com.mojang.brigadier.arguments.FloatArgumentType.floatArg(0.1f, 1000f))
						.executes(ctx -> flySpeed(ctx.getSource().getPlayerOrException(),
								com.mojang.brigadier.arguments.FloatArgumentType.getFloat(ctx, "times")))))
				.then(Commands.literal("skip")
					.then(Commands.argument("seconds", com.mojang.brigadier.arguments.FloatArgumentType.floatArg(0f, 120f))
						.executes(ctx -> {
							ServerPlayer p = ctx.getSource().getPlayerOrException();
							if (Settings.of(p.getUUID()).terrain) {
								say(p, "skip works with terrain damage off only");
								return 0;
							}
							Settings.of(p.getUUID()).skip = com.mojang.brigadier.arguments.FloatArgumentType.getFloat(ctx, "seconds");
							say(p, "The next strike starts " + Settings.of(p.getUUID()).skip + " s in");
							return 1;
						})));
			dispatcher.register(root);
		});
		LOGGER.info("Orbital Laser (Fabric port) loaded: Plasma, Godly, Black Hole and Meteor Storm so far");
	}

	/** `/orbital NAME option`: one literal per option, each storing its index in the player's settings. */
	private static com.mojang.brigadier.builder.LiteralArgumentBuilder<net.minecraft.commands.CommandSourceStack> choice(
			String name, String[] options, java.util.function.BiConsumer<Settings.Player, Integer> set) {
		var node = Commands.literal(name);
		for (int i = 0; i < options.length; i++) {
			final int idx = i;
			node = node.then(Commands.literal(options[i]).executes(ctx -> {
				ServerPlayer p = ctx.getSource().getPlayerOrException();
				set.accept(Settings.of(p.getUUID()), idx);
				say(p, name + ": " + options[idx]);
				return 1;
			}));
		}
		return node;
	}

	private static int flySpeed(ServerPlayer p, float times) {
		p.getAbilities().setFlyingSpeed(0.05f * times);
		p.onUpdateAbilities();
		say(p, "Fly speed " + times + "x");
		return 1;
	}

	private static int terrain(ServerPlayer p, boolean on) {
		Settings.of(p.getUUID()).terrain = on;
		say(p, on ? "Terrain damage ON" : "Terrain damage off");
		return 1;
	}

	private static void say(ServerPlayer p, String text) {
		p.sendSystemMessage(Component.literal(text).withStyle(ChatFormatting.AQUA), false);
	}

	public static Identifier id(String path) {
		return Identifier.fromNamespaceAndPath(MOD_ID, path);
	}
}
