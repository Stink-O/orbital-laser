# Notes for AI agents: the Java port

You've been asked to work on the **Java Edition port** of Orbital Laser, in `java/` on the `java` branch. The Horizon
version (the Rust mod, on `main`) is the reference: the port's job is to look, sound and play the same. The repo's root
[AGENTS.md](../AGENTS.md) is about the Rust mod; this file is the short, factual version for the Java one. The detail is in
[docs/](docs/README.md). Read [PARITY.md](PARITY.md) first: it says what is done.

## Ground rules

- **A strike is destructive and permanent.** Test only in a throwaway Creative world with cheats on. Terrain damage starts
  **off** (`/orbital terrain on` turns it on); ask the user before the first strike with it on.
- **Minecraft is not part of this repo.** Don't commit, bundle, download or fake game files, decompiled game sources,
  textures or sounds. Gradle fetches the game for the build. Keep decompiled sources outside the repo.
- **Keep Java work inside `java/`.** Changes to the Horizon mod go to `main`. Open pull requests against `java`.
- **Don't hand-edit the generated shaders** (`src/client/resources/assets/orbital/shaders/post/*.fsh`). Change
  `tools/build_shader.py` and regenerate (see [tools/README.md](tools/README.md)).
- **Tested on Windows only** (Fabric, NVIDIA, OpenGL, with and without Iris and Voxy). Linux, macOS, AMD, Intel,
  Distant Horizons and multiplayer are untried: say so when you change something they would touch.

## Versions

Minecraft Java **26.3**, Fabric Loader **0.20.1+**, Fabric API **0.165.0+26.3**, Java **25**, Fabric Loom 1.19, Gradle
9.8.2 (the wrapper). Names are Mojang's (the game ships unobfuscated; no mappings layer).

## Commands

```sh
cd java
./gradlew build            # Windows: gradlew.bat build. The jar is build/libs/orbital-laser-0.1.0.jar
```

There is no automated test suite. Verify by playing: copy the jar and Fabric API into a Fabric 26.3 instance's `mods`
folder, make a throwaway world, `/orbital give`, one strike with terrain off, then one with it on. See
[docs/BUILD-AND-TEST.md](docs/BUILD-AND-TEST.md). `/orbital skip SECONDS` (terrain off only) starts the next strike that far
in. `/orbital stop` ends every strike.

## Layout

- `src/main/java/dev/orbital/`: the mod (runs on the server, and in single player). `OrbitalMod` registers items,
  sounds, commands and packets; `Strike` plays plans out on the server tick; `Plan`, `StandardPlan`, `MeteorPlan`,
  `MothershipPlan`, `BigPlans` are the strike plans; `ShaderTables` builds the tables the Payload's and Nuke's shaders
  read; `FarTarget` picks a target far past the loaded world; `Settings` is per-player choices; `Net` holds the packets;
  `Rng` is the original's random-number generator; `Laser` lists the lasers.
- `src/client/java/dev/orbital/client/`: the client. `StrikeShader` draws the screen shaders; `mixin/GameRendererMixin`
  hooks the draw for Iris; `WheelScreen` is the laser menu; `ClientFx` the camera shake and screen tints; `ClientState`.
- `src/main/resources/`: `fabric.mod.json`, and `assets/orbital` (items, models, textures, `sounds.json`, 122 sounds,
  names), copied from the repo's `orbital-laser-mod/` and `orbital-sounds/`.
- `tools/`: the WGSL to GLSL pipeline (`build_shader.py`, `wgsl2glsl/`, `ShaderCheck.java`).

## How it maps to the Rust mod

| Rust (`mod/`) | Java (`java/`) |
|---|---|
| `lasers.rs` | `Laser.java` |
| `strike.rs` (`Plan`) and its strike files | `Plan`, `StandardPlan`, `MeteorPlan`, `MothershipPlan`, `BigPlans` |
| `strike/payload.rs`, `strike/nuke.rs` tables | `ShaderTables.java` |
| `lib.rs` (designator, playback, commands) | `DesignatorItem`, `Strike`, `OrbitalMod` |
| `wheel.rs` | `client/WheelScreen.java` (a plain button list: far simpler) |
| `shaders/*.wgsl` | generated `.fsh` files, drawn by `client/StrikeShader.java` |
| `mod_data` (`render.set-data`) | a 4096-wide `R32_UINT` texture per strike |
| `world.*` capabilities | vanilla commands run as the player with owner rights |

The plans reproduce the Rust ones: the same numbers, timelines and random numbers (`Rng`, the `pcg` hash). A plan is a
list of events (a vanilla command, or a stage worked out when due) on a timeline in seconds.

## Things that will bite you

- **Strikes share a budget:** 20,000 blocks and 400 commands a tick across all strikes on (`Strike`). Many small
  commands in one tick hitch the game as much as too many blocks. The Rust mod's large strikes use `world.edit-blocks`
  outside this budget; the port has no equivalent, so its big lasers are simplified.
- **Minecraft 26.3 has a new GPU API** (`RenderPipeline`, `BindGroupLayout`, `RenderPass`, `GpuBuffer`). A
  `MappableRingBuffer` has only 3 slots, so every strike drawn in a frame needs its own (`StrikeShader`): a fourth
  strike on a shared one crashed with "Cannot wait on a fence for the current submit".
- **Depth is reversed** (1 near, 0 far). The shaders' far point is `RAY_DEPTH`.
- **The game runs OpenGL 3.3 on some machines**: shaders go through shaderc then SPIRV-Cross, so no GLSL newer than 3.30
  (`packHalf2x16` fails). `tools/build_shader.py` patches the translation for this; its header lists every patch.
- **Iris draws its own final picture at the end of the level's rendering**, erasing earlier draws. With a shader pack the
  pass is drawn later, from `GameRendererMixin` at the head of `render3dHud`, and uses the projection captured there
  (it includes the view bob; the plain camera projection makes effects drift while walking with bobbing on).
  The mixin config is `required: false`, so the mod still runs if the hook can't apply.
- **A shader that fails to compile is left off for good; any other failure skips that frame** and gives the strike up
  only if it keeps failing (`StrikeShader`).
- **Far targets** are not loaded on the server (Voxy and similar draw land the server doesn't have): `FarTarget` marches
  the view line over the terrain and loads what it needs, a few chunks a pick; `Strike` force-loads the land a far
  strike works on and lets go on `/orbital stop`.
- **The shaders only exist for 7 lasers** (Plasma, Godly, Black Hole, Meteor Storm, Mothership, Payload, Nuke). The wheel
  lists only those (`Laser.READY`); the other four commands still run with stand-in particles and tints.
- The log line at start-up still says "Plasma, Godly, Black Hole and Meteor Storm so far": it's stale, ignore it.
- Settings are per player and kept in memory only (`Settings`): they reset when the server restarts. The Rust mod keeps
  them between sessions.

## Verifying work

1. `./gradlew build` succeeds.
2. In a throwaway world: one strike of each laser you touched, terrain off, then on. The chat stays empty (the strike's
   messages are action-bar text, on by default; `/orbital messages off` hides them). The shaft reaches bedrock where
   the original's does.
3. With a shader pack (Iris) and without; walk with view bobbing on after the strike: the effect must stay put.
4. `/orbital stop` during a strike: picture, sounds and smoke end at once.
5. Read `logs/latest.log` for errors from `dev.orbital` or "shader". A strike that looked right but logged an error
   failed.
6. Update [PARITY.md](PARITY.md) and [docs/PARITY-CHECKLIST.md](docs/PARITY-CHECKLIST.md) with every change.
