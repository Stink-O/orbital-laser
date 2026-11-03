# Minecraft 26.3 notes

What was learned while porting, so the next person doesn't relearn it. Minecraft 26.3 ships unobfuscated, with Mojang's
own names, and its renderer was rewritten around a new GPU API. Read the game's sources from your own copy of the game
(Loom can generate them); **never put them in this repository.** What follows was checked against 26.3 only.

## Rendering

- **The GPU API is new:** `RenderPipeline`, `BindGroupLayout`, `RenderPass`, `GpuBuffer`, `GpuTexture`. A post pass is
  a pipeline built from a vertex and a fragment shader (`strike.vsh`, `*.fsh`) and drawn as a full-screen triangle.
- **`MappableRingBuffer` has three slots.** One strike uses one slot a frame, so a fourth strike in a frame wraps onto a
  slot still in use and throws "Cannot wait on a fence for the current submit". Each strike keeps its own ring
  (`StrikeShader`).
- **Depth is reversed** (1 near, 0 far).
- **The scene's picture** is read by copying the main target's colour (`TextureTarget.copyColorFrom`) into one the pass
  samples, so each pass sees the world as the previous one left it.
- **Where to draw:** `LevelRenderEvents.END_MAIN` (Fabric API) at the end of the level's main rendering, without a shader
  pack. With Iris, draw later (see below).
- **The HUD:** `HudElementRegistry` and `GuiGraphicsExtractor` for the screen tints (`ClientFx`).
- **The menu:** an ordinary `Screen` with `Button.builder` widgets (`WheelScreen`).
- **Shaders compile through shaderc, then SPIRV-Cross** to the GL dialect in use. On the OpenGL 3.3 path this means no GLSL
  newer than 3.30: `packHalf2x16` and similar fail with "requires #version 420". The pipeline's "vertex shader not found"
  messages that sometimes follow are the fallback pipeline cache retrying, not a second problem.
- **Don't trust a shader that passes `tools/ShaderCheck.java`.** It uses the Vulkan target; the game's GL path is stricter.

## Iris

- Iris composites its own final picture at the end of the level's rendering (`finalizeLevelRendering`), which erases
  anything drawn at `END_MAIN`. `GameRendererMixin` injects at the head of `render3dHud`, which runs right after and before
  the hand's depth clear.
- `renderLevel` builds the matrix the world is drawn with (projection times the view bob, hurt tilt and portal wobble) in a
  local and never stores it. The mixin captures it with a `@ModifyArg` on the `getBuffer(Matrix4f)` call. Using the
  camera's plain projection instead makes the effects slide against the world as the view bobs.
- Iris is detected by reflection, so it isn't a compile-time dependency.

## Commands and the server

- Plans are vanilla commands run through `performPrefixedCommand` as the player, with owner permission.
- `/forceload` loads the chunks a strike works on; the port lets them go on `/orbital stop`.
- Far terrain drawn by Voxy is not loaded on the server. `FarTarget` marches the view line over the terrain's height and
  loads a bounded number of chunks per pick.

## Fabric

- Fabric Loader 0.20.1+ and Fabric API 0.165.0+26.3. Loom 1.19 with Mojang names (no mappings layer).
- The mod id is `orbital`. Entrypoints: `dev.orbital.OrbitalMod` (main) and `dev.orbital.client.OrbitalClient` (client).
- The client mixin config is optional (`required: false`, `defaultRequire: 0`).
- `fabric.mod.json` depends on `fabric-api`, Fabric Loader >= 0.20.1, Minecraft ~26.3 and Java >= 25.

## Not Minecraft's, but learned on the way

- A shader that fails to compile never will: leave it off. Any other failure skips the frame, and the strike is given
  up only if it keeps failing (a single bad frame must not turn the effect off for good).
- A mod's pass reads a lot of state per pixel; test on a mid-range GPU before calling a shader done. Only an NVIDIA GPU
  has been tried.
