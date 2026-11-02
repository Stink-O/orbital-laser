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
  ~124 force-loaded; water it cuts into is dug like any other block (what is left flows in, as round TNT); the lava in
  the ground it bares is sealed. Its land goes in from 13.65 s, from the middle out
  with the shockwave, and the rubble lands by about 17 s. The Nuke is the Payload's big brother (`strike/nuke.rs`,
  `shaders/nuke.wgsl`): a bomb bursts 12 over the land at 11 s, its fireball spread over the ground; it digs a terraced crater ~200 across and 40 deep
  (water dug like any block), flattens everything standing out to ~230 (trees felled pointing
  away), strips crowns and knocks trees flat out to ~300, chars the grass to ~290, strews rubble to ~280, throws ~160
  falling blocks, kills every mob and item within 300 and force-loads the ~1,150 chunks within ~304; past that, out to
  480, its flash scorches what faces the fireball (a line of sight over the land's heights; read with a second set of
  32 `world.read-columns` queries, two in flight at a time, not force-loaded). Its land goes in through
  `world.edit-blocks` as one wave from the middle out (`Wave`, `nk_work` in nuke.rs: one chain of stages, ring by ring,
  split by angle, never by rows), each ring as the shockwave reaches it or as soon after as 350,000 blocks a second
  allows (`NK_RATE`), each chunk's edits on one tick (`Wave::chunk`: the game redraws its sections once); every stage stays under ~1.3 ms natively wherever it lands (`nuke_no_stage_too_heavy_anywhere`,
  ignored: run it on its own; `nk_wave_profile` prints the wave tick by tick), since a stage over the tick's fuel stops the mod ("took too long"). `/orbital shadow
  off|on` (not kept) hides the Nuke's and the Payload's cloud shadows, for comparing. As the Nuke's front reaches the
  player it knocks them back and up (`Act::Shove`, lib.rs's `knockback`: a kick to their velocity through the fork's
  `world.push-player`, 0.8 blocks a tick out and 0.55 up within 200, fading to none at 600, `strike::knock_share`;
  they fly a jump's height or so and some six blocks back, then fall) and jolts the camera
  (`nk_jolt`) and the picture itself (nuke.wgsl's `pl_jolt`, on top of the game's shake, which tops out at a few
  degrees). The Rod from God is the Nuke made kinetic and holy (`strike/rod.rs`, `shaders/rod.wgsl`, the
  same reads, `Wave`, pacing and far-land waiting): plumb over the target, a hard last burst of speed eased in over
  its last half second to about 2,300 blocks a second (`RdGeo::left`: under 40 blocks a frame, so it reads), impact
  at 7 s (`RD_HIT`, which the sounds key off); a crater ~120 across and 50 deep with steep walls (`bowl`: a punch)
  lined in quartz, calcite and gold (`scorched`), a bleached rim (`ejecta`) out to ~90, the crater dug out first
  and lined after (`Wave`: the carve, air over every crater column's floor and the lava it bares sealed, out from the
  middle with the shock at `RD_CARVE_RATE` from 7.1 s, the whole pit open by ~7.7, ~60 chunks; then, `RD_LINE_GAP`
  after, the lining from the rod out at `RD_RATE`, the rod and the heave by ~8.05, the floor to its walls by ~8.6, on
  out over the rim and the land; a chunk's edits on one tick in each, `carve_chunk` and `chunk`), the floor round the rod's foot heaved up in broken, tilted slabs out to ~22
  from its axis (`rd_heave`; its ring of light kept clear), the rod left standing in
  its middle (`rd_rod_col`: 13 wide, 130 over the floor, its top 80 over the land, and 40 under it, driven in deeper on land so
  high its top would pass 318 (`rd_rod_base`; rod.wgsl's `rd_top_end`), polished blackstone banded in gold, a ring of
  light round its foot; keep rod.wgsl's `RD_R`, `RD_L`, `RD_TOP_END` in step), trees felled to ~200 (a band of
  stripped crowns to ~240), the grass blessed (white concrete, calcite, quartz, gold, lights, pale moss: `charred`) and
  rubble strewn in ~17 rays out to ~250, ~120 falling blocks thrown up in a cone, mobs killed within 200, the ~830
  chunks within ~260 force-loaded; its land goes in from 7.1 s, the pit dug by ~7.7, the rod by ~8.05 (rod.wgsl's `RD_LET_GO`, 1.8,
  draws it till then and a margin), the crater lined by ~8.6, all by ~13.5 s. Its
  knockback is 0.65 out and 0.5 up, none past 450 (`rd_jolt`, sharper).
  Its pass has impact frames (`rd_impact`, `rd_if_cut`, `rd_clock`): the pass's clock holds on the hit for 12–14
  frames at 60 while hard cuts of 2–3 frames each play (Kanada style, `RD_IF_STYLE` 1: black silhouettes and thick
  converging lines on white, a 3x close-up in negative with gold lines, gold and umber two-tone), the camera punching
  in and shaking per cut, then a zoom blur with a colour split and a glow as it lets go and catches up over 0.35 s
  (the look is the player's: `/orbital impactframes kanada|blackflash|cinematic|off`, the wheel's IMPACT FX row,
  sent as params[15] / 4 = 1 + `RD_IF_STYLE`'s number, read by `rd_if_style`; the preview's `--set rdif=N` sets the default); params[15] + 2 turns
  them off: `/orbital impactframes off`, the IMPACT FX row's OFF, kept). Only fire them in a
  throwaway world, and ask the user before the first strike with terrain damage on. `/orbital terrain off` (or the
  wheel's centre) makes strikes light and sound only.
- **The Supercell** (`strike/storm.rs`, its funnels `strike/vortex.rs`, `shaders/supercell.wgsl`; 42 s): ~120 bolts
  out to 120 blocks, building (`sc_bolts`: lone small ones from 4 s coming faster, from 15 s waves of more and more at
  once up to `SC_CAP` 5, from 24 s drawn in onto the target, the last wave right before the finale at 29 s, which the
  pass collapses them into; the table's per-second index `SC_I` keeps the pass to the bolts due) (terrain on only: each hurts what stands at its foot, `damage ... minecraft:lightning_bolt`, and sets a few
  fires there; never a vanilla `lightning_bolt`, whose own thunder can't be silenced in time), a pit a block or two
  deep at each, the funnels' tracks scoured (plants, leaves, a few falling blocks), and a finale crater ~70 across and
  24 deep with fulgurite glass veins out to ~85, an overturned rim, trees blasted and set alight out to 95, the land
  scorched to 112, 60 blocks thrown, mobs within 80 killed. It never touches the world's weather (the pass draws the
  rain). The fires its bolts light are left burning (they burn out or spread as fire does; a stop leaves them too).
  Force-loads the chunks within 154.
  Its thunder (`tools/sounds_storm.py`; `sc_thunder` schedules it) is late by the distance and picked by it: `crack`
  within 90 blocks, `crack_mid` to 260, `crack_far` (mostly rumble) past that, each take its own event
  (`supercell.crack3`) so none plays twice running; bolts heard within 0.15 s of each other are one louder clap, never
  a flam; the flurry's quieter (`size_db`). The finale's file starts `FIN_PRE` (1.2 s) before its crack, its run-in
  the last waves' cracks stacking up (keep FIN_PRE in step in both). Horizon plays every sound file summed to mono; `--listen` mixes as
  the game does.
- **The Hurricane** (`strike/hurricane.rs`, `carry.rs`, `shaders/hurricane.wgsl`; 64 s): a spiral cloud deck gathers
  and turns (0-10 s), the eye clears by 14 s, the wind spins up to full by 26 s (`SPIN_K`); from 15 s its front
  (`front_t`) tears the land up from the eyewall (62) in to 32 and out to 150 by 35 s (plants and leaves stripped to 175):
  every column out to 180 is read (`world.read-columns`, 24 ring parts, re-asked till loaded, given up at 40 s), and as
  the front reaches each chunk its trees (logs, leaves), plants and the top one to three blocks of ground (34-105) go
  (`world.edit-blocks`, a chunk's on one tick). The pass draws them in their own colours: up to `HU_NT` (128) trees whole
  as rigid voxel groups (`TreeRec`: trunk, 7x7 canopy spans; path `tree_at`, mirrored by the pass's `hu_tree_at`), and a
  field of blocks round the eyewall in 13 rings of 3-block cells (`ring_*`, the pass's `hu_debris`: some 23,000 in the
  air at its height, about 13,600 under the cloud), each ring coloured from a weighted sample of what was torn up under it
  (`Pal`, table `HU_PAL`). Mobs (terrain on) are carried round by `tp ^ ^ ^` along the way they face the middle, their
  `Motion` zeroed each tick, flung out at 46 s and killed at the end. The player, with KNOCKBACK on, is picked up when the
  front reaches them (none in the eye, none past 175), carried at 108 out and 50 up by `world.push-player` kicks
  (follow.rs's `Drive`, now shared; a block or two a tick, never near `VMAX`) and let down over 7 s from 46 s, with slow
  falling. At 46 s everything is flung out; some 220 blocks and each tree's log and leaves land as falling blocks. The
  pass's FAST stage finds each 2x2's block or tree at half size (`hu_pack`, in `half_extra.zw`) and the join tries them
  again sharp. Sounds `tools/sounds_hurricane.py` (a first pass on sounds_storm.py's wind and rain). Force-loads the
  chunks within 184.
- **Minecraft is not part of this repo.** Horizon's prepared resources come from the user's own Minecraft Java 26.3
  (`horizon-prepare`). Don't download, bundle, fake or work around it.
- **Stock Horizon can't run the mod.** It needs the fork's build, release `orbital-mod-api-8` or newer (it adds
  `world.push-player`, the Nuke's knockback; `orbital-mod-api-7` added the half-size stage QUALITY FAST draws the
  Payload's, the Nuke's and the Rod's smoke with, `orbital-mod-api-6` `world.read-columns`, `orbital-mod-api-5`
  `world.surface-height` and `render.set-data`; older builds won't start the mod): a Linux x86-64 download on the
  fork's releases, or
  `cargo build --release -p horizon-client --features mods` in the fork elsewhere (ask first: it takes a while).
- **Tested on Linux only** (a user reports Windows 11 working, the fork built from source with `--features mods`; on
  macOS the Downfall's pass crashes Metal's compiler). On Windows and macOS keep fixes small and tell the user what you
  changed.
- Run `install.py` with the game closed. Don't touch the user's saves or settings beyond what it does.

## Commands

```sh
python3 install.py                  # install the mod into Horizon's game folder and switch it on (game CLOSED)
./play.sh [WORLD]                   # start the fork's build on the game folder (default world OrbitalTest, creative)
python3 tools/build_mod.py          # build the mod from source into dist/orbital (needs cargo-horizon-mod from the fork)
tools/check-shader.sh               # validate the post passes (a tenth of a second)
tools/preview.py downfall 14 30 45  # render those moments offscreen onto dist/preview/downfall.jpg (seconds; no game)
tools/preview.py payload 18 --quality both --bench   # the Payload at QUALITY FULL and FAST side by side, timed
tools/preview.py rod 7.05 9 25 --views rdnear,rdstand  # the Rod's impact frames, its jet, it standing (views rd*)
RD_VOX_OUT=/tmp/h.vox cargo test --release rod_heaves_the_floor_round_its_foot   # (in mod/) the heave as voxels: then
PREVIEW_VOXELS=/tmp/h.vox tools/preview.py rod 40 --views rdfoot,rdfootup --set vox=1
RD_CAVE_OUT=/tmp/c.txt cargo test --release rd_cave_order -- --ignored --nocapture  # the crater dug, then lined, by tick
python3 tools/sounds_rod.py --listen DIR             # the Rod's sounds (and listening mixdowns from 200 and 600 blocks)
tools/world_snapshot.py save|restore|reset WORLD [NAME]  # snapshot a world and put it back (refuses while it's open; reset leaves, restores, rejoins)
```

**Search with ripgrep (`rg`), not `grep`.** It's installed, much faster on this repo and the fork, and skips
`target/` and other ignored files by default: `rg -n 'pattern' mod/src`, `rg -l --type rust 'fn tick'`.

**Iterate on a strike's look offscreen first.** `tools/preview.py LASER TIMES... [--views player,far,side,up,under,aerial,tower,cbplayer,cbfar,spire,cbside,cbaerial]
[--set key=value...] [--bench]` (`--set sunel=3 sunaz=180`: the sun's height and bearing in degrees, for dusk and
night) builds the pass exactly as the mod does, renders every moment from every view in one run
over a synthetic scene, and writes a labelled contact sheet; `--bench` prints the pass's GPU time. Only then rebuild,
install and check it in the game, once. In the game, `/orbital skip SECONDS` (terrain off) starts the next strike that
far in, so one moment can be looked at without sitting through the rest; `horizon-ctl command "orbital skip 29"`
from a script.

In the game: `/orbital give` (the two items), `/orbital wheel`, `/orbital plasma`, `godly`, `blackhole`, `meteor`, `mothership`, `downfall`, `planetkiller`, `crystalbloom`, `sinkhole`, `payload`, `nuke`, `rod`, `supercell` or `hurricane`, `/orbital approach …`, `/orbital arrival …`, `/orbital colour …`, `/orbital terrain on|off`, `/orbital hud on|off`, `/orbital payloadsound main|alt`, `/orbital nukesound main|alt`, `/orbital quality full|fast`, `/orbital impactframes kanada|blackflash|cinematic|off` (`on` brings back the last look), `/orbital seed N|lock|random` (kept, the wheel's SEED field and LOCK SEED switch: N in 1-997 holds every strike's seed, `lock` holds the last strike's, `random` lets go), `/orbital knockback on|off` (the Nuke's and the Rod's push, the Hurricane's carry; kept, the wheel's KNOCKBACK switch), `/orbital follow on|off` and `/orbital follow distance N` (kept, the wheel's FOLLOW switch: an orbit camera round a Nuke's or a Payload's bomb, `follow.rs`: the player's own look sets the angle, the camera `distance` (70) back from the bomb along it; moved only by `world.push-player` kicks each tick, never faster than 24 blocks a tick (`VMAX`: past that the game's collision sweep runs out of budget and crashes), worked out against the game's own drag so its movement and frame interpolation carry it, never a teleport or a turn of the view; it leaves the player once the bomb is within 440 blocks of them, so it stays on land already loaded; backs off to 380 (the Payload 170) as the burst nears, orbits the cloud, and a `tp ... ~ ~` puts them back), `/orbital flyspeed N|reset`, `/orbital stop` (ends the strike under way; also the wheel's STOP STRIKE button while one is), `/orbital skip SECONDS`.
The wheel has pages of five (its arrows, its tabs or a right-click turn them); the Downfall, the Planet Killer, the Crystal Bloom, the Sinkhole and the Payload are on the second, the Nuke, the Rod from God, the Supercell and the Hurricane on the third. Its FLY
SPEED row over the title sets the creative flying speed (a click along the bar for 1x–40x, or a number typed in its
box, up to 1000x, Enter to set), through `world.set-flying-speed` and `input.poll-typed`. A fork build without them, or
without `world.edit-blocks`, `world.surface-height`, `world.read-columns`, `world.push-player` or `render.set-data`,
won't start the mod.
The wheel's left column has the strike options: SEED (a field: the last strike's seed, or one typed) and LOCK SEED
at the top, then KNOCKBACK (the Nuke, the Rod, the Hurricane) and FOLLOW (the Nuke, the Payload) only for the lasers they apply to
(`toggles` in wheel.rs); the right column PANEL and QUALITY, and a red STOP STRIKE under QUALITY while a strike is
under way, its rows lined up with the left's (PANEL with SEED, QUALITY with LOCK SEED, STOP STRIKE with the first
switch under them). Nothing goes over the hotbar but the designator's `NO TARGET IN RANGE` (`actionbar` in lib.rs;
the strikes have no messages; firing during a strike only clicks). With the Rod loaded or pointed at, an IMPACT FX row under the ring (OFF, KANADA, BLACK FLASH,
CINEMATIC). With the Payload or the Nuke loaded or pointed at, a BLAST SOUND row under the ring picks its blast (MAIN or ALT, as
`/orbital payloadsound` or `/orbital nukesound`). Every post pass is built ahead of time by `mod/build.rs` (`src/passbuild.rs`): a switch
only picks a ready-made one. The QUALITY switch under PANEL (top right; `/orbital quality full|fast`, kept
between sessions, default FAST) picks whether the Payload's, the Nuke's and the Rod's smoke is drawn at full size or at half size: FAST gives the
game the pass with its half-size stage (`fs_half`, `fs_join`; see below), which the fork draws from release
`orbital-mod-api-7` (an older fork would compile the same source and draw its `fs_main` at full size; FAST needs no
import of its own).
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
  `src/lasers.rs` the lasers, `src/strike.rs` a strike's plan (`src/strike/crystal.rs` the Crystal Bloom's, `src/strike/sinkhole.rs` the Sinkhole's, `src/strike/payload.rs` the Payload's, `src/strike/nuke.rs` the Nuke's, `src/strike/rod.rs` the Rod's), `src/wheel.rs` the wheel, `shaders/strike.wgsl` the post
  pass, `shaders/downfall.wgsl`, `shaders/planetkiller.wgsl`, `shaders/crystalbloom.wgsl`, `shaders/sinkhole.wgsl`, `shaders/payload.wgsl`, `shaders/nuke.wgsl` and `shaders/rod.wgsl` the
  Downfall's, the Planet Killer's, the Crystal Bloom's, the Sinkhole's, the Payload's, the Nuke's and the Rod's own passes (the
  mod appends each to `strike.wgsl` up to its `fs_main`; `pass_of` in lib.rs picks a strike's),
  `horizon-mod.toml` the manifest (api 0.2 with `registries` for the content).
- The Supercell: `src/strike/storm.rs` its plan (bolts, pits, finale crater, fire sweeps, `sc_table`),
  `src/strike/vortex.rs` its funnels as reusable pieces for a tornado (`Funnel`, `wander`, `vx_words`, `scour`, `roar`),
  `shaders/supercell.wgsl` its pass (the vortex section `vx_*`; FAST's `[half stage]` as the Payload's).
- The Hurricane: `src/strike/hurricane.rs` its plan (the land's read and edits, the trees, the rings' colours, the mobs,
  `hu_thrown`), `src/carry.rs` the player's carry, `shaders/hurricane.wgsl` its pass (`hu_debris`, `hu_trees`,
  `hu_volume`; FAST's `[half stage]`). Preview views `hu*` (`hustrip=1` takes the preview's trees away as the front
  reaches them); `hu_write_table` (ignored) writes its table over the preview's wooded land.
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
- **A call into the mod has a fuel limit** (a tick 50 million WebAssembly instructions, a frame 10 million; past it the
  game stops the mod for good: "it took too long"). `mod/src/meter.rs` counts each call's work (the loops that do the
  heavy work `spend`), and what can wait (a stage, a job of the Nuke's, an edit, a command, an answer taken in) waits
  for the next tick once it reads `SOFT`; a stage counts at least `STAGE_COST`. Keep any one stage well under a tick:
  split it rather than let it grow. The fork's `mod_soak` example (`cargo run --release -p horizon-mods --features
  fuel-trace --example mod_soak -- COPY_OF_dist/orbital N SEED`, `SOAK_LASERS=nuke`, `SOAK_TRACE=1`) plays the real
  mod.wasm headless and prints every hook's worst fuel; `stress::thousands_of_strikes` (ignored) plays fire, stop and
  re-fire sequences through lib.rs's own playback natively. The game logs a call that uses half its fuel, and on a
  stop which hook and the mod's stack. Both play targets far off on land not loaded (the far terrain's LOD: only the
  player's surroundings loaded, the target's chunks coming slowly or never once forceloaded), the player up to 1000
  blocks away, and stops in the first seconds and round the burst; `mod_soak` fails any call over half its fuel
  (`SOAK_MAX`). The meter can't see work it isn't told of: the native soak (release) fails a tick that takes more
  than 3 ms past what its counted work explains (`thousands_of_strikes`). Never scan everything left (columns not
  loaded, jobs, rings) each time a stage asks what's ready: keep it O(what's due). The Nuke's land waits for columns
  not loaded, asking again a ring at a time, and goes in late as they come; it leaves out what never loads (logged
  `nuke: N columns of the land never loaded`).
- **`mod.wasm` imports must match the manifest's capabilities**; `cargo horizon-mod build` checks this.
- **A strike's world changes go through a budget**: at most 20,000 blocks and 400 commands a tick (`BLOCK_BUDGET`,
  `CARVE_CMDS` in lib.rs); the rest wait. Thousands of small commands in one tick hitch the game as much as too many
  blocks. `carve_queue` prints a laser's busiest ticks and commonest commands. Those count commands only: the Crystal
  Bloom's (and much of the Planet Killer's) land goes through `world.edit-blocks`, outside that budget; its
  `cb_edit_profile` ignored test prints its edits' busiest ticks.
- **Block edits are paced by the frame time** (`mod/src/pace.rs`): every chunk an edit changes is resent whole to the
  client, so a wave costs the frame per chunk, which grows with its radius (`nk_wave_profile` prints the chunks per
  quarter second). Edits wait in order and go in as fast as they are due while the frames are quick; while the
  smoothed frame time runs long (over 25 ms and 1.4 times what it was before the edits) fewer go in a tick, down to a
  floor. A landed piece's edit never waits, and `Act::Spare` (the forceload removes) waits for the edits. The log
  says `block edits paced: the last went in N s late` when they were held back.

## Verifying work

Shader: `tools/check-shader.sh` prints `OK` (every pass: the prelude + `mod/shaders/strike.wgsl`, the Downfall's, the
Planet Killer's, the Crystal Bloom's, the Sinkhole's, the Payload's and the Nuke's). Mod: build, install, `./play.sh`, one
strike with terrain off, then one with terrain on in a throwaway world; the chat stays empty and the shaft reaches
bedrock. See [CONTRIBUTING.md](CONTRIBUTING.md).
Around every in-game strike run `tools/game_check.py mark` before it and `tools/game_check.py watch` (or `check`)
during and after it: if it reports the mod stopped (out of fuel, a panic, a failed start), the run failed, whatever it
looked like.
