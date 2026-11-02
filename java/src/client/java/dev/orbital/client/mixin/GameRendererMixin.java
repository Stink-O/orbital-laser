package dev.orbital.client.mixin;

import dev.orbital.client.StrikeShader;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.client.renderer.state.OptionsRenderState;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import net.minecraft.client.renderer.state.level.PlayerRenderState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.joml.Matrix4f;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.ModifyArg;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * With an Iris shader pack in use, the pack composites its own picture over the screen at the end of the level's rendering,
 * which erases anything drawn before it. `render3dHud` runs right after that and before it clears the depth for the hand,
 * so the strike's screen shader is drawn here instead (it still sees the finished world and its depth).
 */
@Mixin(GameRenderer.class)
public abstract class GameRendererMixin {
	/**
	 * The matrix the level is drawn with: the camera's projection times the walking bob, the hurt tilt and the portal wobble
	 * (renderLevel builds it in a local and never stores it). The strike's pass must use this one, not the camera's plain
	 * projection, or its effects slide against the world as the view bobs.
	 */
	@ModifyArg(method = "renderLevel", at = @At(value = "INVOKE",
			target = "Lnet/minecraft/client/renderer/ProjectionMatrixBuffer;getBuffer(Lorg/joml/Matrix4f;)Lcom/mojang/renderpearl/api/buffers/GpuBufferSlice;"),
			index = 0)
	private Matrix4f orbital$captureLevelProjection(Matrix4f projection) {
		StrikeShader.captureProjection(projection);
		return projection;
	}

	@Inject(method = "render3dHud", at = @At("HEAD"))
	private void orbital$afterLevel(CameraRenderState cameraState, PlayerRenderState playerState, OptionsRenderState optionsState,
			boolean consistentDepthRequired, CallbackInfo ci) {
		StrikeShader.renderLate((GameRenderer) (Object) this, cameraState);
	}
}
