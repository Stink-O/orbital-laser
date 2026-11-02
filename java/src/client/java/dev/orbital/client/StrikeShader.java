package dev.orbital.client;

import com.mojang.blaze3d.buffers.Std140Builder;
import com.mojang.blaze3d.pipeline.RenderTarget;
import com.mojang.blaze3d.pipeline.TextureTarget;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.renderpearl.api.GpuFormat;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import com.mojang.renderpearl.api.commands.CommandEncoder;
import com.mojang.renderpearl.api.commands.RenderPass;
import com.mojang.renderpearl.api.pipeline.BindGroupLayout;
import com.mojang.renderpearl.api.pipeline.ColorTargetState;
import com.mojang.renderpearl.api.pipeline.RenderPipeline;
import com.mojang.renderpearl.api.pipeline.UniformType;
import com.mojang.renderpearl.api.textures.FilterMode;
import com.mojang.renderpearl.api.textures.GpuTexture;
import com.mojang.renderpearl.api.textures.GpuTextureView;
import dev.orbital.Net;
import dev.orbital.OrbitalMod;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.OptionalDouble;
import net.fabricmc.fabric.api.client.rendering.v1.level.LevelRenderContext;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.MappableRingBuffer;
import net.minecraft.client.renderer.RenderPipelines;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import org.joml.Matrix4f;

/**
 * The original mod's screen shaders, translated to GLSL by tools in the repository and run here as one full-screen pass
 * over the finished world, every frame, for each strike that is on: strike.wgsl (Plasma, Godly, Black Hole, Meteor Storm,
 * Mothership), payload.wgsl and nuke.wgsl. Several strikes can be on at once: each has its own clock and its own table, and
 * each is drawn over what the one before it left. The pass is handed what the original's was: the scene's picture and depth,
 * the camera, sixteen numbers and (the Payload and the Nuke) a table of words.
 */
public final class StrikeShader {
	// the names naga gave the original's bindings (kept in step with shaders/post/*.fsh)
	private static final String SCENE = "_group_0_binding_0_fs";
	private static final String DEPTH = "_group_0_binding_1_fs";
	private static final String FRAME = "Frame_block_0Fragment";
	private static final String DATA = "_group_0_binding_5_fs";
	private static final int FRAME_SIZE = 4 * 64 + 7 * 16 + 4 * 16;
	private static final int DATA_WIDTH = 4096;

	private static final long T0 = System.nanoTime();

	/** One shader: its pipeline, and whether it reads the table. */
	private static final class Pass {
		final String name;
		final boolean data;
		RenderPipeline pipeline;
		boolean failed;

		Pass(String name, boolean data) {
			this.name = name;
			this.data = data;
		}
	}

	/** One strike that is on: what the server announced, when it started, and its table on the GPU. */
	private static final class Active {
		final Net.StrikeFx fx;
		final long startNs;
		int[] words;           // the table, until it is uploaded
		GpuTexture texture;
		GpuTextureView view;
		boolean logged;
		int errors;            // frames in a row that failed to draw

		Active(Net.StrikeFx fx, int[] words) {
			this.fx = fx;
			this.words = words;
			this.startNs = System.nanoTime() - (long) (fx.offset() * 1e9);
		}

		float clock() {
			return (System.nanoTime() - startNs) / 1e9f;
		}

		void release() {
			if (view != null) {
				view.close();
				texture.close();
				view = null;
				texture = null;
			}
		}
	}

	private static final Map<String, Pass> PASSES = new HashMap<>();
	private static final List<Active> ACTIVE = new ArrayList<>();
	/**
	 * The buffers that hand each strike's parameters to the shader. A MappableRingBuffer has only three slots, and each strike
	 * uses one a frame, so a fourth strike in the same frame would wrap round onto a slot still in use: every strike that is
	 * drawn in a frame gets a ring of its own.
	 */
	private static final List<MappableRingBuffer> RINGS = new ArrayList<>();
	private static TextureTarget scratch;

	private static MappableRingBuffer ring(int slot) {
		while (RINGS.size() <= slot) {
			RINGS.add(new MappableRingBuffer(() -> "orbital strike frame", 130, FRAME_SIZE));
		}
		return RINGS.get(slot);
	}
	private static int[] pendingData;

	private StrikeShader() {}

	private static void say(String text) {
		OrbitalMod.LOGGER.info("[shader] {}", text); // (the log only: nothing is written to the player's chat)
	}

	/** The table for the coming strike (the Payload's and the Nuke's): it arrives just before the strike's announcement. */
	public static void setData(int[] words) {
		pendingData = words;
	}

	/** A strike has started on the server. */
	public static void begin(Net.StrikeFx payload) {
		ACTIVE.add(new Active(payload, pendingData));
		pendingData = null;
		say("strike announced: " + passName(payload.laser()) + " shader (laser " + payload.laser() + "), " + ACTIVE.size() + " on");
	}

	/** /orbital stop: every strike's picture goes at once, and its table with it. */
	public static void clearAll() {
		for (Active a : ACTIVE) {
			a.release();
		}
		ACTIVE.clear();
		pendingData = null;
		say("all strikes cleared");
	}

	private static String passName(int laser) {
		return laser == 9 ? "payload" : laser == 10 ? "nuke" : "strike";
	}

	/** The projection the level was drawn with this frame (with the walking bob and tilt in it): see GameRendererMixin. */
	private static final Matrix4f levelProjection = new Matrix4f();
	private static boolean haveLevelProjection;

	public static void captureProjection(Matrix4f projection) {
		levelProjection.set(projection);
		haveLevelProjection = true;
	}

	private static java.lang.reflect.Method irisInUse;
	private static Object irisApi;
	private static boolean irisChecked;

	/**
	 * Whether an Iris shader pack is drawing the world. Iris then composites its own final picture over the screen at the
	 * very end of the level's rendering, which wipes out anything drawn before that: so the strike's pass has to draw after
	 * it (see GameRendererMixin) and not at the end of the main pass.
	 */
	static boolean shaderPackActive() {
		if (!irisChecked) {
			irisChecked = true;
			try {
				Class<?> api = Class.forName("net.irisshaders.iris.api.v0.IrisApi");
				irisApi = api.getMethod("getInstance").invoke(null);
				irisInUse = api.getMethod("isShaderPackInUse");
				OrbitalMod.LOGGER.info("Iris found: the strike shader will draw after the shader pack when one is in use");
			} catch (Throwable ignored) {
				irisInUse = null;
			}
		}
		if (irisInUse == null) {
			return false;
		}
		try {
			return (boolean) irisInUse.invoke(irisApi);
		} catch (Throwable e) {
			return false;
		}
	}

	/** Runs at the end of the level's main rendering (with no shader pack). */
	public static void render(LevelRenderContext ctx) {
		if (shaderPackActive()) {
			return; // GameRendererMixin draws it after the shader pack instead
		}
		run(ctx.gameRenderer().mainRenderTarget(), ctx.levelState().cameraRenderState);
	}

	/** Runs right after the level has been drawn, before the hand and the depth clear: with a shader pack. */
	public static void renderLate(net.minecraft.client.renderer.GameRenderer gameRenderer, CameraRenderState cam) {
		if (!shaderPackActive()) {
			return;
		}
		run(gameRenderer.mainRenderTarget(), cam);
	}

	private static void run(RenderTarget main, CameraRenderState cam) {
		if (ACTIVE.isEmpty()) {
			return;
		}
		for (int i = ACTIVE.size() - 1; i >= 0; i--) {
			Active a = ACTIVE.get(i);
			if (a.clock() > a.fx.length() + 6f) {
				a.release();
				ACTIVE.remove(i);
			}
		}
		int slot = 0;
		for (Active a : new ArrayList<>(ACTIVE)) {
			Pass failedPass = PASSES.get(passName(a.fx.laser()));
			if (failedPass != null && failedPass.failed) {
				continue;
			}
			try {
				draw(main, cam, a, slot++);
				a.errors = 0;
			} catch (Throwable e) {
				Pass p = PASSES.computeIfAbsent(passName(a.fx.laser()), n -> new Pass(n, !n.equals("strike")));
				if (String.valueOf(e.getMessage()).contains("did not compile")) {
					// (a shader that does not compile never will: leave it off)
					p.failed = true;
					OrbitalMod.LOGGER.error("The {} shader did not compile and is switched off until the game restarts", p.name, e);
				} else {
					// (anything else is this strike's trouble for a moment, not the shader's for good: skip the frame, and give this
					// strike up only if it keeps failing)
					if (a.errors == 0) {
						OrbitalMod.LOGGER.error("The {} shader failed to draw a frame", p.name, e);
					}
					if (++a.errors >= 20) {
						OrbitalMod.LOGGER.error("Giving up on a {} strike that keeps failing to draw", p.name);
						a.release();
						ACTIVE.remove(a);
					}
				}
			}
		}
	}

	private static Pass pass(int laser) {
		String name = passName(laser);
		Pass p = PASSES.computeIfAbsent(name, n -> new Pass(n, !n.equals("strike")));
		if (p.pipeline != null) {
			return p;
		}
		BindGroupLayout.Builder layout = BindGroupLayout.builder()
				.withUniform(SCENE, UniformType.COMBINED_IMAGE_SAMPLER)
				.withUniform(DEPTH, UniformType.COMBINED_IMAGE_SAMPLER)
				.withUniform(FRAME, UniformType.UNIFORM_BUFFER);
		if (p.data) {
			layout.withUniform(DATA, UniformType.COMBINED_IMAGE_SAMPLER);
		}
		RenderPipeline pipe = RenderPipeline.builder(RenderPipelines.POST_PROCESSING_SNIPPET)
				.withVertexShader(OrbitalMod.id("post/strike"))
				.withFragmentShader(OrbitalMod.id("post/" + name))
				.withLocation(OrbitalMod.id("pipeline/" + name + "_post"))
				.withBindGroupLayout(layout.build())
				.withColorTargetState(ColorTargetState.DEFAULT)
				.build();
		if (RenderSystem.getCompiledPipelineNullable(pipe) == null) {
			throw new IllegalStateException("the " + name + " shader did not compile (see the log above for the shader's errors)");
		}
		p.pipeline = pipe;
		OrbitalMod.LOGGER.info("The {} shader compiled", name);
		return p;
	}

	/** A strike's table as an unsigned-integer texture, DATA_WIDTH words a row. */
	private static void uploadData(Active a) {
		int[] words = a.words;
		a.words = null;
		int rows = Math.max(1, (words.length + DATA_WIDTH - 1) / DATA_WIDTH);
		a.texture = RenderSystem.getDevice().createTexture("orbital strike data", 1 | 4, GpuFormat.R32_UINT, DATA_WIDTH, rows, 1, 1);
		a.view = RenderSystem.getDevice().createTextureView(a.texture);
		ByteBuffer buf = ByteBuffer.allocateDirect(DATA_WIDTH * rows * 4).order(ByteOrder.nativeOrder());
		for (int w : words) {
			buf.putInt(w);
		}
		buf.clear();
		RenderSystem.getDevice().createCommandEncoder().writeToTexture(a.texture, buf, 0, 0, 0, 0, DATA_WIDTH, rows);
	}

	private static void draw(RenderTarget main, CameraRenderState cam, Active a, int slot) {
		Minecraft mc = Minecraft.getInstance();
		MappableRingBuffer frameUbo = ring(slot);
		Net.StrikeFx s = a.fx;
		float t = a.clock();
		Pass pass = pass(s.laser());
		if (pass.data) {
			if (a.words != null) {
				uploadData(a);
			}
			if (a.view == null) {
				return; // no table for this strike
			}
		}

		if (scratch == null || scratch.width != main.width || scratch.height != main.height) {
			if (scratch != null) {
				scratch.destroyBuffers();
			}
			scratch = new TextureTarget("orbital scene copy", main.width, main.height, GpuFormat.RGBA8_UNORM, null);
		}
		// (each strike reads the picture as the one before it left it)
		scratch.copyColorFrom(main);

		// (the matrix the world was drawn with, bob and tilt included, so the effects stay put in the world as the view bobs)
		Matrix4f proj = new Matrix4f(haveLevelProjection ? levelProjection : cam.projectionMatrix);
		Matrix4f view = new Matrix4f(cam.viewRotationMatrix);
		Matrix4f invView = new Matrix4f(view).invert();
		Matrix4f invProj = new Matrix4f(proj).invert();
		float fov = (float) (2.0 * Math.atan(1.0 / cam.projectionMatrix.m11()));
		float day = 0.25f;
		if (mc.level != null) {
			day = (mc.level.getDefaultClockTime() % 24000L) / 24000f;
		}
		float sunA = (float) (day * Math.PI * 2.0);
		float w = main.width, h = main.height;
		boolean ship = s.laser() == 4 || s.laser() == 5;

		try (GpuBufferSlice.MappedView view2 = frameUbo.currentBuffer().map(false, true)) {
			Std140Builder b = Std140Builder.intoBuffer(view2.data());
			b.putMat4f(view).putMat4f(proj).putMat4f(invView).putMat4f(invProj);
			b.putVec4((float) cam.pos.x, (float) cam.pos.y, (float) cam.pos.z, 0f);            // camera_position
			b.putVec4(w, h, 1f / w, 1f / h);                                                    // resolution
			b.putVec4((System.nanoTime() - T0) / 1e9f, day, 0f, 0f);                           // time
			b.putVec4((float) Math.cos(sunA), (float) Math.sin(sunA), 0f, sunA);               // sun
			b.putVec4(0.47f, 0.65f, 1.0f, 1f);                                                  // sky_color
			b.putVec4(0.75f, 0.82f, 0.95f, 1f);                                                 // fog_color
			b.putVec4(0.05f, cam.depthFar, mc.options.getEffectiveRenderDistance() * 16f, fov); // view_params
			// mod_params, as the original's mod hands them over
			b.putVec4((float) s.tx(), (float) s.ty(), (float) s.tz(), t);                      // [0] target, strike clock
			b.putVec4(s.bx() + 0.5f, s.bz() + 0.5f, s.wing(), s.laser());                      // [1] hit block, facing, laser
			b.putVec4(s.seed(), 1.0f, 0f, s.by());                                              // [2] seed, intensity, capture, block y
			if (pass.data) {
				b.putVec4(s.meX(), s.meY(), s.meZ(), 0f);                                       // [3] where the player stood (the dust follows the land to them)
			} else {
				b.putVec4(s.approach(), s.arrival(), 0f, ship ? s.colour() : 0f);              // [3] ship choices
			}
		}

		CommandEncoder enc = RenderSystem.getDevice().createCommandEncoder();
		try (RenderPass rp = enc.createRenderPass(() -> "Orbital strike", main.getColorTextureView(), Optional.empty(), null,
				OptionalDouble.empty())) {
			rp.setPipeline(RenderSystem.getCompiledPipeline(pass.pipeline));
			RenderSystem.bindDefaultUniforms(rp);
			rp.setUniform(FRAME, frameUbo.currentBuffer());
			rp.setUniform(SCENE, scratch.getColorTextureView(), RenderSystem.getSamplerCache().getClampToEdge(FilterMode.LINEAR));
			rp.setUniform(DEPTH, main.getDepthTextureView(), RenderSystem.getSamplerCache().getClampToEdge(FilterMode.NEAREST));
			if (pass.data) {
				rp.setUniform(DATA, a.view, RenderSystem.getSamplerCache().getClampToEdge(FilterMode.NEAREST));
			}
			rp.draw(3, 1, 0, 0);
		}
		frameUbo.rotate();

		if (!a.logged) {
			a.logged = true;
			say("the " + pass.name + " shader drew its first frame (clock " + String.format("%.1f", t) + " s; "
					+ (haveLevelProjection ? "using the world's own projection, bob included" : "WARNING: the world's projection was not caught, so view bobbing will show")
					+ "; " + (shaderPackActive() ? "after the shader pack" : "no shader pack") + ")");
		}
	}
}
