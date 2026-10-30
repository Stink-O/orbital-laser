# Notes for AI agents

You've been asked to set up or work on **Orbital Laser**, a mod for [Horizon](https://github.com/ludovic111/horizon) (the
Rust rewrite of Minecraft Java). It runs on a Horizon fork that adds the mod capabilities it needs:
[Stink-O/horizon, branch `mod-api-input-ui-render-world`](https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world).
The README is the user-facing guide and the full copy-paste setup prompt is in
[README.md](README.md#set-it-up-with-an-ai-agent); [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) has the detail (every
laser, command, capability and timing). This file is the short, factual version for you.

## Ground rules

- **A strike is destructive and permanent.** It flattens everything above ground within ~44 blocks (52 for the black hole), digs a ~60-block
  crater and a shaft to bedrock, and kills every mob and dropped item within 40 blocks (not players). The Meteor Storm is far bigger:
  craters across 120 blocks round the target, then everything above ground flattened out to 100, a ~125-block crater,
  the land charred to 135, rubble out to 250 and every mob within 130 killed. The Mothership vaporises out to 34 blocks, digs a
  22-block crater, a shaft and a 100-block trench, and force-loads those chunks while it works. The Downfall buries a
  kilometre-long wreck at least 360 blocks in front of the player, crushes the land under its whole length, heaps
  berms along it and leaves the black hole's crater (arms out to 150 blocks) and a shaft; its crushing carries on for
  up to a minute after the strike. The Planet Killer is the biggest: it flattens out to 340 blocks, digs a crater 480
  across (terraced walls 60 deep, the floor 80, an open shaft 80 across to bedrock in the middle), heaps a rim out to
  340, splits the land in chasms out to ~400, chars it and strews rubble to 380, kills every mob within 280 and
  force-loads ~1,900 chunks from the moment it fires; its crater, rim and charred land go straight into the chunks
  through the fork's `world.edit-blocks` (new in the fork release `orbital-mod-api-4`) and are done about 25 s into the strike, the fissures' few
  commands soon after. The Crystal Bloom clears everything above ground out to ~130 blocks (24 up, to the sky over its
  middle), digs a geode crater ~176 across and 28 deep round a well 20 across to bedrock, leaves about two dozen crystal stumps up
  to 34 tall out to ~150 with three broken spires lying by them, opens nine fissures out to ~205, strews crystal shards
  and frosts the land out to 235, kills every mob within 160 and force-loads the ~770 chunks within 240; its land goes
  in through `world.edit-blocks` from the detonation at 22 s and is done by about 28 s. The Sinkhole caves the land in
  under a pit ~225 across (its rim wandering from ~190 to ~260) and down to bedrock: everything over the pit is gone
  (up to each column's real top: a mountain, its trees and snow, read with `world.read-columns`), its walls are cut back
  under the rim by up to ~6 (2.5 just under the rim's own band) and darken downward (tuff, deepslate, blackstone), water and lava in them are sealed (water to barrier near the top, tuff deeper; lava to magma), the middle is
  `clone`d down 7 blocks first (at 6 and 7.3 s), mobs within 140 die and the ~285 chunks within ~152 are force-loaded;
  its land goes in slab by slab from 8.6 s and down to bedrock from 16 s, done by about 23 s. The Payload is a bomb,
  not a beam: it digs a crater ~42 across (its edge wandering ~10%) and 9 deep, scorched (blackstone, basalt, tuff,
  coarse dirt, gravel, cobbled deepslate), its rim heaped up to ~4 high out to ~35 from the middle; everything standing on the
  land is swept off out to ~85 (up to each column's real top, read with `world.read-columns`), the trees there felled
  and lying pointing away from it (a stump of 1-2 left, their crowns crushed by their ends past ~46), the grass charred
  out to ~100, past ~85 a band ~24 wide where crowns are stripped and some trees knocked flat, leaves and branches
  strewn, ~220 pieces of rubble strewn out to ~105, ~90 falling blocks thrown out of the crater (landing out to ~110 by
  ~19 s, about half as blocks), mobs and items within 90 killed and the ~240 chunks within
  ~124 force-loaded; nothing is dug next to water or lava and what the crater opens is sealed. Its land goes in at
  13.65 s and the rubble lands by about 17 s. Only fire them in a
  throwaway world, and ask the user before the first strike with terrain damage on. `/orbital terrain off` (or the
  wheel's centre) makes strikes light and sound only.
- **Minecraft is not part of this repo.** Horizon's prepared resources come from the user's own Minecraft Java 26.3
  (`horizon-prepare`). Don't download, bundle, fake or work around it.
- **Stock Horizon can't run the mod.** It needs the fork's build, release `orbital-mod-api-6` or newer (it adds
  `world.read-columns`, which the Sinkhole reads the real land of its slabs with; `orbital-mod-api-5` added
  `world.surface-height` and `render.set-data`, which the Crystal Bloom rests its pieces on the real ground with; older
  builds won't start the mod): a Linux x86-64 download on the fork's releases, or
  `cargo build --release -p horizon-client --features mods` in the fork elsewhere (ask first: it takes a while).
- **Tested on Linux only.** On Windows and macOS keep fixes small and tell the user what you changed.
- Run `install.py` with the game closed. Don't touch the user's saves or settings beyond what it does.

## Commands

```sh
python3 install.py                  # install the mod into Horizon's game folder and switch it on (game CLOSED)
./play.sh [WORLD]                   # start the fork's build on the game folder (default world OrbitalTest, creative)
python3 tools/build_mod.py          # build the mod from source into dist/orbital (needs cargo-horizon-mod from the fork)
tools/check-shader.sh               # validate the post passes (a tenth of a second)
tools/preview.py downfall 14 30 45  # render those moments offscreen onto dist/preview/downfall.jpg (seconds; no game)
tools/preview.py payload 18 --quality both --bench   # the Payload at QUALITY FULL and FAST side by side, timed
```

**Iterate on a strike's look offscreen first.** `tools/preview.py LASER TIMES... [--views player,far,side,up,under,aerial,tower,cbplayer,cbfar,spire,cbside,cbaerial]
[--set key=value...] [--bench]` (`--set sunel=3 sunaz=180`: the sun's height and bearing in degrees, for dusk and
night) builds the pass exactly as the mod does, renders every moment from every view in one run
over a synthetic scene, and writes a labelled contact sheet; `--bench` prints the pass's GPU time. Only then rebuild,
install and check it in the game, once. In the game, `/orbital skip SECONDS` (terrain off) starts the next strike that
far in, so one moment can be looked at without sitting through the rest; `horizon-ctl command "orbital skip 29"`
from a script.

In the game: `/orbital give` (the two items), `/orbital wheel`, `/orbital plasma`, `godly`, `blackhole`, `meteor`, `mothership`, `downfall`, `planetkiller`, `crystalbloom`, `sinkhole` or `payload`, `/orbital approach …`, `/orbital arrival …`, `/orbital colour …`, `/orbital terrain on|off`, `/orbital messages on|off`, `/orbital hud on|off`, `/orbital payloadsound main|alt`, `/orbital quality full|fast`, `/orbital flyspeed N|reset`, `/orbital stop` (ends the strike under way; also the wheel's STOP STRIKE button while one is), `/orbital skip SECONDS`.
The wheel has pages of five (its arrows, its tabs or a right-click turn them); the Downfall, the Planet Killer, the Crystal Bloom, the Sinkhole and the Payload are on the second. Its FLY
SPEED row over the title sets the creative flying speed (a click along the bar for 1x–40x, or a number typed in its
box, up to 1000x, Enter to set), through `world.set-flying-speed` and `input.poll-typed`. A fork build without them, or
without `world.edit-blocks`, `world.surface-height`, `world.read-columns` or `render.set-data`, won't start the mod.
With the Payload loaded or pointed at, a BLAST SOUND row under the ring picks its blast (MAIN or ALT, as
`/orbital payloadsound`). The QUALITY switch under MESSAGES and PANEL (top right; `/orbital quality full|fast`, kept
between sessions, default FAST) picks whether the Payload's smoke is drawn at full size or at half size: FAST gives the
game the pass with its half-size stage (`fs_half`, `fs_join`; see below), which the fork draws from release
`orbital-mod-api-7`; an older fork compiles the same source and draws its `fs_main` at full size, so FAST needs no new
import and the mod still starts on `orbital-mod-api-6`.
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
  `src/lasers.rs` the lasers, `src/strike.rs` a strike's plan (`src/strike/crystal.rs` the Crystal Bloom's, `src/strike/sinkhole.rs` the Sinkhole's, `src/strike/payload.rs` the Payload's), `src/wheel.rs` the wheel, `shaders/strike.wgsl` the post
  pass, `shaders/downfall.wgsl`, `shaders/planetkiller.wgsl`, `shaders/crystalbloom.wgsl`, `shaders/sinkhole.wgsl` and `shaders/payload.wgsl` the
  Downfall's, the Planet Killer's, the Crystal Bloom's, the Sinkhole's and the Payload's own passes (the
  mod appends each to `strike.wgsl` up to its `fs_main`; `pass_of` in lib.rs picks a strike's),
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
- **The mod's post pass reads `mod_data`** (`render.set-data`, binding 5 of the prelude): the Crystal Bloom's pieces'
  rest heights (word `i * 16 + k * 2 + half`) and from `CB_TAB` (1024) its spires and pieces, worked out once by
  `cb_table` in `strike/crystal.rs`; keep that layout in step with the pass's `CB_*` offsets. `tools/preview` binds it from `$PREVIEW_DATA` (`index value` lines) and
  draws hills with `hills=H`; `cb_dump_slope` (ignored test) writes a matching data file and voxel files.
- **`world.surface-height` answers a tick or two later** (`mod/src/ground.rs` keeps the answers; a stage asks, a later
  one reads). In the tests `ground::set_test` answers at once; with none set the pieces lie as on flat land.
- **`world.read-columns` answers the same way** (`mod/src/columns.rs`; `Act::Read`): the Sinkhole reads the 24 blocks
  under every pit column's world-surface top as it starts, and `strike/sh_land.rs` works them out ~3,000 columns a tick
  (material names to colours in `MATS`, the game's textures' averages, grass and leaves tinted by the biome tints the read answers with; packed three words a column at `SH_GRID` of `mod_data`; keep it in step with
  `sh_colw`/`sh_cell` in `shaders/sinkhole.wgsl`). In the tests `columns::test_answer` answers at once; the preview's
  land is `synth_column` in `strike/sinkhole.rs` (`SH_LAND=0` leaves it out). For a local mod build against an
  unreleased fork API, point the SDK at the fork with an uncommitted `mod/.cargo/config.toml` `[patch]`, and never
  commit `mod/Cargo.lock` while it holds that path.
- **The Payload's pass has a half-size stage** (QUALITY FAST): between `// [half stage]` and `// [end half stage]`
  at the end of `shaders/payload.wgsl`, `fs_half` (the column, the trail, the dust and the pieces' smoke, as
  premultiplied colour and transmittance, marched to alternately the nearest and the farthest depth of each two by two
  pixels; beside it the ray's length, the column's distance and whether debris is near) and `fs_join` (a joint
  bilateral upsample against the full-size depth, then the sharp parts: the flash, the object, the pieces' glow, the
  debris, the lens). Both call `payload(in, stage, ...)`, stage 0 the whole pass (fs_main), so FULL's look is the same
  code. The pass declares the fork's bindings 6 and 7 itself (the prelude doesn't), so the source compiles on every
  fork; `payload_pass` in lib.rs drops the section for FULL. `tools/preview.py payload T --quality both` shows FULL and
  FAST side by side (`--whole`: FAST as a fork without the stage draws it). The Planet Killer, the Crystal Bloom and
  the Sinkhole could take the same split.
- **`mod.wasm` imports must match the manifest's capabilities**; `cargo horizon-mod build` checks this.
- **A strike's world changes go through a budget**: at most 20,000 blocks and 400 commands a tick (`BLOCK_BUDGET`,
  `CARVE_CMDS` in lib.rs); the rest wait. Thousands of small commands in one tick hitch the game as much as too many
  blocks. `carve_queue` prints a laser's busiest ticks and commonest commands. Those count commands only: the Crystal
  Bloom's (and much of the Planet Killer's) land goes through `world.edit-blocks`, outside that budget; its
  `cb_edit_profile` ignored test prints its edits' busiest ticks.

## Verifying work

Shader: `tools/check-shader.sh` prints `OK` (every pass: the prelude + `mod/shaders/strike.wgsl`, the Downfall's and the
Planet Killer's, the Crystal Bloom's, the Sinkhole's). Mod: build, install, `./play.sh`, one
strike with terrain off, then one with terrain on in a throwaway world; the chat stays empty and the shaft reaches
bedrock. See [CONTRIBUTING.md](CONTRIBUTING.md).
