# Notes for AI agents

You've been asked to set up or work on **Orbital Laser**, a mod for [Horizon](https://github.com/ludovic111/horizon) (the
Rust rewrite of Minecraft Java). It runs on a Horizon fork that adds the mod capabilities it needs:
[Stink-O/horizon, branch `mod-api-input-ui-render-world`](https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world).
The README is the user-facing guide and the full copy-paste setup prompt is in
[README.md](README.md#set-it-up-with-an-ai-agent). This file is the short, factual version for you.

## Ground rules

- **A strike is destructive and permanent.** It flattens everything above ground within ~44 blocks (52 for the black hole), digs a ~60-block
  crater and a shaft to bedrock, and kills every mob and dropped item within 40 blocks (not players). The Meteor Storm is far bigger:
  craters across 120 blocks round the target, then everything above ground flattened out to 100, a ~125-block crater,
  the land charred to 135, rubble out to 250 and every mob within 130 killed. The Mothership vaporises out to 34 blocks, digs a
  22-block crater, a shaft and a 100-block trench, and force-loads those chunks while it works. The Downfall buries a
  kilometre-long wreck at least 360 blocks in front of the player, crushes the land under its whole length, heaps
  berms along it and leaves the black hole's crater (arms out to 150 blocks) and a shaft; its crushing carries on for
  up to a minute after the strike. Only fire them in a
  throwaway world, and ask the user before the first strike with terrain damage on. `/orbital terrain off` (or the
  wheel's centre) makes strikes light and sound only.
- **Minecraft is not part of this repo.** Horizon's prepared resources come from the user's own Minecraft Java 26.3
  (`horizon-prepare`). Don't download, bundle, fake or work around it.
- **`mod/` builds against stock Horizon's mod API** (level 3: `game.raycast`, `command.run-quiet`). The stock build has
  no strike light (the post pass waits for a native shader API) and no fly speed, and it needs cheats: the world changes
  are vanilla commands, run quietly. The fork's build (a Linux x86-64 download on the fork's releases) has the full look.
- **Tested on Linux only.** On Windows and macOS keep fixes small and tell the user what you changed.
- Run `install.py` with the game closed. Don't touch the user's saves or settings beyond what it does.

## Commands

```sh
python3 install.py                  # install the mod into Horizon's game folder and switch it on (game CLOSED)
./play.sh [WORLD]                   # start the fork's build on the game folder (default world OrbitalTest, creative)
python3 tools/build_mod.py          # build the mod from source into dist/orbital.hmod (needs stock cargo-horizon-mod)
tools/check-shader.sh               # validate both post passes (a tenth of a second)
tools/preview.py downfall 14 30 45  # render those moments offscreen onto dist/preview/downfall.jpg (seconds; no game)
```

**Iterate on a strike's look offscreen first.** `tools/preview.py LASER TIMES... [--views player,far,side,up,under,aerial]
[--set key=value...] [--bench]` builds the pass exactly as the mod does, renders every moment from every view in one run
over a synthetic scene, and writes a labelled contact sheet; `--bench` prints the pass's GPU time. Only then rebuild,
install and check it in the game, once. In the game, `/orbital skip SECONDS` (terrain off) starts the next strike that
far in, so one moment can be looked at without sitting through the rest; `horizon-ctl command "orbital skip 29"`
from a script.

In the game: `/orbital give` (the two items), `/orbital wheel`, `/orbital plasma`, `godly`, `blackhole`, `meteor`, `mothership` or `downfall`, `/orbital approach …`, `/orbital arrival …`, `/orbital colour …`, `/orbital terrain on|off`, `/orbital messages on|off`, `/orbital hud on|off`, `/orbital skip SECONDS` (`/orbital flyspeed N|reset` on the fork's build only).
On the stock build the wheel is two lists: the lasers (a click loads one and closes it) and the switches (a click flips
or cycles one in place; a ship laser adds its approach, arrival and colour rows first). On the fork's build it has pages of
five and a FLY SPEED row (`world.set-flying-speed`, `input.poll-typed`).
R (or right-clicking the Orbital Remote) opens the laser wheel; holding right-click with the Orbital Laser Designator for
under a second fires. Rebind R in Options > Controls > Key Binds.

`play.sh` finds things through `HORIZON_ORBITAL` (the folder with the fork's `horizon-client` and `horizon-ctl`; default
`~/horizon-orbital`), `HORIZON_RESOURCES` (prepared resources; default `.local/horizon-client/26.3` beside the build)
and `HORIZON_HOME` (the game folder; default `~/.local/share/horizon`).

The game's control tool works on this build too: `horizon-ctl state`, `horizon-ctl command "orbital give"`,
`horizon-ctl key r tap` (opens the wheel), `horizon-ctl screenshot out.png` (without the mod's post pass), and
`horizon-ctl record out.mp4 60` / `horizon-ctl record stop` (the finished frames, effects included; F1 hides the HUD).

## Layout

- `mod/`: the mod (Rust for `wasm32-unknown-unknown`): `src/lib.rs` hooks, designator and strike playback,
  `src/lasers.rs` the lasers, `src/strike.rs` a strike's plan, `src/wheel.rs` the wheel, `shaders/strike.wgsl` the post
  pass, `shaders/downfall.wgsl` the Downfall's own pass (the mod appends it to `strike.wgsl` up to its `fs_main`),
  `horizon-mod.toml` the manifest (api 0.2 with `registries` for the content).
- `orbital-laser-mod/` (items, models, textures, names) and `orbital-sounds/` (the sounds): the mod's content.
- `orbital-laser-shader/`, `strike.py`, `themes.py`: 0.1's setup for stock Horizon (`install.py --legacy`).

## Things that will bite you

- **Nothing happens in the game:** it's stock Horizon. Start it with `./play.sh`. Options > Mods shows the mod's status
  and, if it stopped, why.
- **The game keeps its saves and options in the folder it starts in** when started with `--game`: `play.sh` starts it in
  the game folder for that reason. Starting it elsewhere makes a fresh, empty game folder there.
- **The mod's post pass is plain WGSL after the fork's mod pass prelude** (`tools/wgslcheck/prelude.wgsl` is a copy). A compile error
  is logged ("a mod's post pass did not compile") and the pass is skipped. Validate with `tools/wgslcheck`.
- **`mod.wasm` imports must match the manifest's capabilities**; `cargo horizon-mod build` checks this.

## Verifying work

Shader: `tools/check-shader.sh` prints `OK` (both passes: the prelude + `mod/shaders/strike.wgsl`, and the Downfall's). Mod: build, install, `./play.sh`, one
strike with terrain off, then one with terrain on in a throwaway world; the chat stays empty and the shaft reaches
bedrock. See [CONTRIBUTING.md](CONTRIBUTING.md).
