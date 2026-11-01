package dev.orbital.client;

import com.mojang.blaze3d.platform.InputConstants;
import dev.orbital.Net;
import dev.orbital.OrbitalMod;
import dev.orbital.RemoteItem;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayConnectionEvents;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayNetworking;
import net.fabricmc.fabric.api.client.rendering.v1.hud.HudElementRegistry;
import net.fabricmc.fabric.api.client.rendering.v1.level.LevelRenderEvents;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;

public class OrbitalClient implements ClientModInitializer {
	private static KeyMapping wheelKey;

	@Override
	public void onInitializeClient() {
		ClientState.load();
		wheelKey = KeyMappingHelper.registerKeyMapping(new KeyMapping("key.orbital.wheel", InputConstants.KEY_R,
				KeyMapping.Category.register(OrbitalMod.id("orbital"))));
		ClientTickEvents.END_CLIENT_TICK.register(mc -> {
			while (wheelKey.consumeClick()) {
				if (mc.player != null && mc.gui.screen() == null) {
					openWheel();
				}
			}
		});
		ClientPlayNetworking.registerGlobalReceiver(Net.OpenWheel.TYPE, (payload, context) -> openWheel());
		ClientPlayNetworking.registerGlobalReceiver(Net.Shake.TYPE, (payload, context) -> ClientFx.shake(payload.strength(), payload.seconds()));
		ClientPlayNetworking.registerGlobalReceiver(Net.Flash.TYPE, (payload, context) ->
			ClientFx.flash(payload.rgb(), payload.alpha(), payload.fadeIn(), payload.hold(), payload.fadeOut()));
		ClientPlayNetworking.registerGlobalReceiver(Net.StrikeFx.TYPE, (payload, context) -> StrikeShader.begin(payload));
		ClientPlayNetworking.registerGlobalReceiver(Net.StrikeData.TYPE, (payload, context) -> StrikeShader.setData(payload.words()));
		ClientPlayNetworking.registerGlobalReceiver(Net.StopFx.TYPE, (payload, context) -> {
			StrikeShader.clearAll();
			ClientFx.clear();
		});
		LevelRenderEvents.END_MAIN.register(StrikeShader::render);
		ClientTickEvents.END_CLIENT_TICK.register(ClientFx::tick);
		HudElementRegistry.addFirst(OrbitalMod.id("fx"), ClientFx::render);
		// the remote opens the wheel too
		RemoteItem.openWheel = OrbitalClient::openWheel;
		// tell a freshly joined server what the wheel last chose
		ClientPlayConnectionEvents.JOIN.register((handler, sender, mc) -> {
			ClientPlayNetworking.send(new Net.SelectLaser(ClientState.laser));
			ClientPlayNetworking.send(new Net.SetTerrain(ClientState.terrain));
		});
	}

	public static void openWheel() {
		Minecraft mc = Minecraft.getInstance();
		mc.gui.setScreen(new WheelScreen());
	}
}
