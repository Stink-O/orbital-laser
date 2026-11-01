# Orbital Laser: Fabric port

A port of [Orbital Laser](https://github.com/Stink-O/orbital-laser) by Stink-O to Minecraft Java Edition on the
[Fabric](https://fabricmc.net) loader. Pick a laser from a menu, hold the Orbital Laser Designator on a target, and a strike
comes down from orbit: it digs a crater and a shaft to bedrock, flattens what stands round it and leaves the land changed
for good. **Use a throwaway world: strikes are permanent.**

This is an independent fan project, not affiliated with Mojang, Microsoft or the original's author. See [NOTICE](NOTICE).

## Requirements

- Minecraft Java Edition **26.3**
- [Fabric Loader](https://fabricmc.net/use/installer/) 0.20.1 or newer
- [Fabric API](https://modrinth.com/mod/fabric-api) 0.165.0+26.3 or newer
- Java 25

It works with Iris shader packs (the strike's screen effects are drawn after the pack), and the strike can be aimed at far
terrain, including land that only a distance mod such as Voxy draws.

## Build

```sh
./gradlew build            # Windows: gradlew.bat build
```

The mod is `build/libs/orbital-laser-<version>.jar` (the other jar is the sources). Put it in your `mods` folder.
Gradle downloads Minecraft's build files, Fabric Loader and Fabric API itself; none of them is in this repository.

## Playing

- `/orbital give` gives the **Orbital Laser Designator** and the **Orbital Remote** (cheats must be on).
- **R**, or right-clicking with the Remote, opens the laser menu. Click a laser to load it. Payload and Nuke have a
  `Blast: MAIN / ALT` button for their alternative blast sound. Rebind R under Options, Controls, Key Binds.
- **Fire:** hold the Designator on a target and hold right-click for under a second. Fire as many as you like at once.
- `/orbital terrain on|off` turns terrain damage on or off. **It starts off.** `/orbital stop` ends every strike and clears
  its picture and sounds.
- Others: `/orbital plasma|godly|blackhole|meteor|mothership|payload|nuke` (also `downfall`, `planetkiller`, `crystalbloom`,
  `sinkhole`), `approach`, `arrival`, `colour`, `messages`, `hud`, `quality`, `payloadsound`, `nukesound`, `flyspeed`,
  `skip`, `wheel`.

## What is and isn't finished

| | World changes and sounds | Screen visuals (the original's shaders) |
|---|---|---|
| Plasma, Godly, Black Hole, Meteor Storm, Mothership | closely follow the original | translated and working |
| Payload, Nuke | simplified | translated and working (full quality only) |
| Downfall, Planet Killer, Crystal Bloom, Sinkhole | simplified | **not ported** (particles and screen tints stand in) |

The menu lists only the lasers whose visuals are done. Also not ported: the Nuke's knockback and the original's
`/orbital shadow`. The strike plans are in `src/main/java/dev/orbital`, the client in `src/client/java/dev/orbital/client`.

## The shaders

`src/client/resources/assets/orbital/shaders/post/*.fsh` are **generated** from the original's WGSL shaders. To regenerate
them (you need Python 3, Rust, and a checkout of the original mod) see [tools/README.md](tools/README.md).

## Licence

Copyright (c) 2026 Ramingen, MIT License. This is a port of Orbital Laser by Stink-O (also MIT, Copyright (c) 2026 Stink-O),
and the licence requires the original's copyright notice to stay: see [LICENSE](LICENSE) and [NOTICE](NOTICE).
