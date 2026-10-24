# Notes for AI agents

You've been asked to set up or work on **Orbital Laser**, a mod for [Horizon](https://github.com/ludovic111/horizon) (the
Rust rewrite of Minecraft Java). It runs on a Horizon fork that adds the mod capabilities it needs:
[Stink-O/horizon, branch `mod-api-input-ui-render-world`](https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world).
The README is the user-facing guide and the full copy-paste setup prompt is in
[README.md](README.md#set-it-up-with-an-ai-agent). This file is the short, factual version for you.

## Ground rules

- **A strike is destructive and permanent.** It flattens everything above ground within ~44 blocks (52 for the black hole), digs a ~60-block
  crater and a shaft to bedrock, and kills every mob and dropped item within 40 blocks (not players). Only fire it in a
  throwaway world, and ask the user before the first strike with terrain damage on. `/orbital terrain off` (or the
  wheel's centre) makes strikes light and sound only.
- **Minecraft is not part of this repo.** Horizon's prepared resources come from the user's own Minecraft Java 26.3
  (`horizon-prepare`). Don't download, bundle, fake or work around it.
- **Stock Horizon can't run the mod.** It needs the fork's build: a Linux x86-64 download on the fork's releases, or
  `cargo build --release -p horizon-client` in the fork elsewhere (ask first: it takes a while).
- **Tested on Linux only.** On Windows and macOS keep fixes small and tell the user what you changed.
- Run `install.py` with the game closed. Don't touch the user's saves or settings beyond what it does.

## Commands

```sh
python3 install.py                  # install the mod into Horizon's game folder and switch it on (game CLOSED)
./play.sh [WORLD]                   # start the fork's build on the game folder (default world OrbitalTest, creative)
python3 tools/build_mod.py          # build the mod from source into dist/orbital (needs cargo-horizon-mod from the fork)
```

In the game: `/orbital give` (the two items), `/orbital wheel`, `/orbital plasma`, `godly` or `blackhole`, `/orbital terrain on|off`.
R (or right-clicking the Orbital Remote) opens the laser wheel; holding right-click with the Orbital Laser Designator for
under a second fires. Rebind R in Options > Controls > Key Binds.

`play.sh` finds things through `HORIZON_ORBITAL` (the folder with the fork's `horizon-client` and `horizon-ctl`; default
`~/horizon-orbital`), `HORIZON_RESOURCES` (prepared resources; default `.local/horizon-client/26.3` beside the build)
and `HORIZON_HOME` (the game folder; default `~/.local/share/horizon`).

The game's control tool works on this build too: `horizon-ctl state`, `horizon-ctl command "orbital give"`,
`horizon-ctl key r tap` (opens the wheel), `horizon-ctl screenshot out.png`.

## Layout

- `mod/`: the mod (Rust for `wasm32-unknown-unknown`): `src/lib.rs` hooks, designator and strike playback,
  `src/lasers.rs` the lasers, `src/strike.rs` a strike's plan, `src/wheel.rs` the wheel, `shaders/strike.wgsl` the post
  pass, `horizon-mod.toml` the manifest (api 0.2 with `registries` for the content).
- `orbital-laser-mod/` (items, models, textures, names) and `orbital-sounds/` (the sounds): the mod's content.
- `orbital-laser-shader/`, `strike.py`, `themes.py`: 0.1's setup for stock Horizon (`install.py --legacy`).

## Things that will bite you

- **Nothing happens in the game:** it's stock Horizon. Start it with `./play.sh`. Options > Mods shows the mod's status
  and, if it stopped, why.
- **The game keeps its saves and options in the folder it starts in** when started with `--game`: `play.sh` starts it in
  the game folder for that reason. Starting it elsewhere makes a fresh, empty game folder there.
- **The mod's post pass is plain WGSL in Horizon's shader-pack stage format** with the prelude prepended. A compile error
  is logged ("a mod's post pass did not compile") and the pass is skipped. Validate with `tools/wgslcheck`.
- **`mod.wasm` imports must match the manifest's capabilities**; `cargo horizon-mod build` checks this.

## Verifying work

Shader: `tools/wgslcheck` prints `OK` on prelude + `mod/shaders/strike.wgsl`. Mod: build, install, `./play.sh`, one
strike with terrain off, then one with terrain on in a throwaway world; the chat stays empty and the shaft reaches
bedrock. See [CONTRIBUTING.md](CONTRIBUTING.md).
