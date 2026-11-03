# Build and test

## You need

- **Java 25** (a JDK). The Minecraft launcher's own Java is not enough to build.
- Nothing else installed: the Gradle wrapper downloads Gradle 9.8.2, Fabric Loom, Minecraft 26.3, Fabric Loader 0.20.1 and
  Fabric API 0.165.0+26.3 on the first build. None of them is in this repository.

## Build

```sh
cd java
./gradlew build            # Windows: gradlew.bat build
```

The mod is `java/build/libs/orbital-laser-0.1.0.jar`. Ignore the `-sources` jar. The first build takes a few minutes.
`build/`, `.gradle/` and `run/` are git-ignored.

## Install it to play

1. Install Minecraft Java 26.3, then Fabric Loader 0.20.1 or newer for 26.3 (the installer at fabricmc.net).
2. Put **Fabric API 0.165.0+26.3** and `orbital-laser-0.1.0.jar` in the instance's `mods` folder (`.minecraft/mods`, or
   a launcher instance's own `mods` folder).
3. Optional, and what the port was tested with: Sodium, Iris with a shader pack (Complementary Reimagined), Voxy, and a
   terrain mod such as Tectonic.

Most testing so far was done this way, with the built jar in a launcher instance. Loom's `runClient` task is available in
the Gradle project but has not been used for testing.

## First test (throwaway world only)

1. New **Creative** world, **Allow Cheats: ON**. Strikes are permanent: never a world you care about.
2. `/orbital give` gives the Designator and the Remote. `R` (or right-click the Remote) opens the wheel.
3. Pick a laser. Hold right-click with the Designator on the ground for about half a second.
4. Terrain damage is off: you should see and hear the strike with nothing changed. `/orbital stop` ends it at once.
5. `/orbital terrain on`, then a strike. A crater should dig, the mobs and drops nearby should die, and the shaft should
   reach bedrock where the original's does.

## What to check for each change

| Check | How |
|---|---|
| It builds | `./gradlew build` |
| The game starts | the mod list shows Orbital Laser; `logs/latest.log` has no `dev.orbital` errors |
| The look | fire the laser; compare with the Horizon version at the same moments (below) |
| Shader packs | repeat with Iris and a pack on, and with shaders off |
| View bobbing | walk after the strike with bobbing on: effects must stay put in the world |
| Several strikes | fire four or five in a row without stopping; none should vanish or crash |
| `/orbital stop` | during a strike: the picture, sounds and smoke end at once |
| Far targets | aim at distant terrain drawn by Voxy; the strike should land there and its sound arrive late |
| Chat | stays empty; strike messages are action-bar text (`/orbital messages off` hides them) |

A strike that looked right but logged an error counts as failed. If a shader fails, the log line names the shader;
a shader that doesn't compile stays off for the session.

## Compare with the Horizon version

Fire the same laser from the same distance in both versions, at the same seed where the version has one, and compare the
picture at the same moments and the sounds. The Horizon version's `tools/preview.py` (on `main`) renders any moment
offscreen. `/orbital skip SECONDS` (terrain off only) starts a strike that far in on the Java side, so one moment can be
looked at without sitting through the rest. Note any difference in [PARITY-CHECKLIST.md](PARITY-CHECKLIST.md).

## Regenerating the shaders

Not needed to build. When you change `tools/build_shader.py` or the original's WGSL, see [../tools/README.md](../tools/README.md):

```sh
cargo build --release --manifest-path tools/wgsl2glsl/Cargo.toml
python tools/build_shader.py strike  --orbital-laser ../orbital-laser
```

(`../orbital-laser` is a checkout of the original mod; the path is yours to choose.) `tools/ShaderCheck.java` compiles a
shader with the options Minecraft 26.3 uses, so errors show without starting the game. The game's OpenGL 3.3 path adds
limits it doesn't know about, so a shader that passes can still fail in the game: read `latest.log`.

## Before you push

- Nothing from Minecraft is in the diff: no jars, decompiled sources, textures or sounds from the game.
- No personal data: names, emails, absolute paths from your machine, tokens.
- Work is under `java/`; pull requests go against the `java` branch.
- [PARITY.md](../PARITY.md) and [PARITY-CHECKLIST.md](PARITY-CHECKLIST.md) updated.
