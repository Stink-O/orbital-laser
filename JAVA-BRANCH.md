# The `java` branch: Orbital Laser for Minecraft Java Edition

This branch is where **Orbital Laser is being ported to Minecraft: Java Edition**. It's a work in progress and isn't
released yet. The Horizon version (the Rust mod, released from `main`) is unchanged and lives on `main`.

**The goal:** one Orbital Laser that runs on **every modern Java mod loader**, from one shared codebase:

| Loader | Status |
|---|---|
| **Fabric** | in progress: the starting point, by [@Ramingen](https://github.com/Ramingen) ([#6](https://github.com/Stink-O/orbital-laser/pull/6)) |
| **NeoForge** | planned |
| **Forge** | planned |
| **Quilt** | planned (Quilt loads most Fabric mods already) |

The game logic (the strike plans, timings, sounds, lasers and the wheel) is meant to live in one common module, with
only a thin layer per loader on top, so every loader gets the same mod. Fabric came first. It will be reorganised into
that common-plus-loaders layout (for example with Architectury, or a MultiLoader-style Gradle setup) before the other
loaders are added.

**Done means parity:** every laser looks, sounds and plays like the Horizon version, on every loader. What's ported and
what isn't is tracked in [`java/PARITY.md`](java/PARITY.md). When it's complete, this branch merges into `main` and the
Java version is released alongside the Horizon one.

## Where things are

- `java/`: the Java port. See [`java/README.md`](java/README.md) to build it and try it (Fabric, Minecraft 26.3).
- Everything else is the Horizon version, the same as `main`. `main` is merged into this branch after each release, so
  new lasers and fixes are here to port.

## Contributing

Open pull requests against **`java`**, not `main`. Keep Java work inside `java/`. Changes to the Horizon mod go to
`main`.

> [!WARNING]
> **Work in progress.** Strikes are permanent: try it only in a throwaway world. Tested so far on Windows (Fabric,
> NVIDIA, OpenGL).

> [!IMPORTANT]
> Nothing from Minecraft is included. This is an independent fan project, not affiliated with Mojang or Microsoft.
