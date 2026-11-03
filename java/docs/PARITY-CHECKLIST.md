# Parity checklist

Every feature of the Horizon version (the Rust mod on `main`, v0.5.8), and where the Java port stands. This is the
detailed version of [../PARITY.md](../PARITY.md). Update both with every change.

**Status:** **done** (looks, sounds and plays the same) · **partial** (there, but simplified or incomplete) · **not
started**. "Check" means nobody has compared it with the original yet.

Everything was tested on Windows (Fabric, NVIDIA, OpenGL, with and without Iris and Voxy). Nothing was tested on other
systems, other GPUs, Distant Horizons or multiplayer.

## Lasers

"Look" is the screen shader. "World" is what the strike does to the land and mobs. "Sound" is the sounds and their
timings. The port reproduces the original's plans in Java (same numbers and timelines); "simplified" means the world
changes were reduced (the original does them through `world.edit-blocks` and other capabilities Minecraft has no
equivalent of here; the port uses commands only).

| Laser | Look | Sound | World | Notes |
|---|---|---|---|---|
| Plasma | done | done | done | |
| Godly | done | done | done | |
| Black Hole | done | done | done | |
| Meteor Storm | done | done | done | |
| Mothership | done | done | done | approach, arrival and colour options work |
| Downfall | **not started** (stand-in particles and tints) | partial | partial (simplified) | its own pass is not ported |
| Planet Killer | **not started** (stand-in) | partial | partial (simplified) | its own pass is not ported |
| Crystal Bloom | **not started** (stand-in) | partial | partial (simplified) | its own pass is not ported |
| Sinkhole | **not started** (stand-in) | partial | partial (simplified) | its own pass is not ported; needs `world.read-columns`-style reads |
| Payload | done | done | partial (simplified) | main and alt blast sounds work |
| Nuke | done | done | partial (simplified) | knockback not started; main and alt blast sounds work |
| Rod from God | not started | not started | not started | new in 0.5.7; no plan, pass or command |
| Supercell | not started | not started | not started | new in 0.5.7; no plan, pass or command |
| Hurricane | not started | not started | not started | new in 0.5.8; no plan, pass or command; it carries the player round its eye (the fork's `world.carry-player`), which needs a Java equivalent |

Shader status: the pass for `strike.wgsl` (Plasma, Godly, Black Hole, Meteor Storm, Mothership), `payload.wgsl` and
`nuke.wgsl` is translated and works. Not translated: `downfall.wgsl`, `planetkiller.wgsl`, `crystalbloom.wgsl`,
`sinkhole.wgsl`, `rod.wgsl`, `supercell.wgsl`, `hurricane.wgsl`. The translator (`tools/build_shader.py`) is generic, but each new pass
needs its own patches and an in-game check on OpenGL 3.3 (see [MINECRAFT-26.3-NOTES.md](MINECRAFT-26.3-NOTES.md)).

## Items and input

| Feature | Status | Notes |
|---|---|---|
| Orbital Laser Designator item (hold right-click to fire) | done | held 12 ticks (0.6 s), range 1000 blocks |
| Orbital Remote item (right-click opens the wheel) | done | |
| `R` opens the wheel, rebindable under Controls | done | |
| Item models, textures, names | done | copied from `orbital-laser-mod/` |
| Sounds: one event per key of the original's `sounds.json`, 122 files | done | copied from `orbital-sounds/` |
| Registry content for each laser (laser-coloured item names, etc.) | check | |

## The wheel

The Rust wheel is a ring with pages of five lasers, a fly-speed bar, option rows and switches. The Java one is a plain
list of buttons.

| Feature | Status | Notes |
|---|---|---|
| Pick a laser | partial | a list; only the 7 lasers with finished shaders are listed |
| Pages, arrows and tabs for more lasers | not started | the list has one page |
| Terrain damage switch | done | centre of the Rust wheel; a button here |
| BLAST SOUND row (Payload, Nuke: MAIN or ALT) | done | a "Blast: MAIN/ALT" button beside each |
| FLY SPEED row (bar, typed number, 1x to 1000x) | not started | `/orbital flyspeed` works |
| SEED field and LOCK SEED | not started | |
| KNOCKBACK switch (Nuke, Rod) | not started | |
| FOLLOW switch (Nuke, Payload) | not started | |
| MESSAGES switch | not started | `/orbital messages on\|off` works |
| PANEL switch | not started | the `hud` setting is stored but nothing reads it |
| QUALITY switch (FULL or FAST) | not started | `/orbital quality` stores it; the shaders have no half-size stage |
| STOP STRIKE button | not started | `/orbital stop` works |
| IMPACT FX row (Rod) | not started | no Rod |
| Approach, arrival and colour rows for the ships | not started | `/orbital approach`, `arrival`, `colour` work |

## Commands

| Command | Rust | Java |
|---|---|---|
| `/orbital give` | yes | done |
| `/orbital wheel` | yes | done |
| `/orbital plasma`, `godly`, `blackhole`, `meteor`, `mothership` | yes | done |
| `/orbital downfall`, `planetkiller`, `crystalbloom`, `sinkhole`, `payload`, `nuke` | yes | done (their looks vary as above) |
| `/orbital rod`, `/orbital supercell`, `/orbital hurricane` | yes | not started |
| `/orbital terrain on\|off` | yes | done |
| `/orbital stop` | yes | done: clears every strike's blocks, sounds, particles, picture, force-loaded chunks |
| `/orbital skip SECONDS` | yes | done (terrain off only, up to 120 s) |
| `/orbital approach ahead\|behind\|left\|right\|overhead` | yes | done |
| `/orbital arrival snap\|unfold\|warp` | yes | done |
| `/orbital colour green\|red\|amber\|blue\|violet\|white` | yes | done: Rust keeps one per ship laser, Java one for all |
| `/orbital flyspeed N\|reset` | yes (also with no argument: prints it) | partial: no query form; Java caps at 1000 |
| `/orbital messages on\|off` | yes | done |
| `/orbital quality full\|fast` | yes | partial: stored, no effect |
| `/orbital payloadsound main\|alt`, `/orbital nukesound main\|alt` | yes | done |
| `/orbital hud on\|off` (the wheel's PANEL) | yes | partial: stored, no effect |
| `/orbital seed N\|random\|lock` | yes | not started |
| `/orbital knockback on\|off` | yes | not started |
| `/orbital follow on\|off`, `follow distance N` | yes | not started |
| `/orbital impactframes kanada\|blackflash\|cinematic\|off` | yes | not started |
| `/orbital shadow on\|off` | yes | not started |
| `/orbital meter`, `trace` (developer commands) | yes | not applicable |

## Settings and behaviour

| Feature | Status | Notes |
|---|---|---|
| Terrain damage off at start | done | |
| No pop-up messages; "NO TARGET IN RANGE" and the designator's countdown (0.5.8) | not started | the port still shows its action-bar messages (on by default) |
| Settings kept between sessions | **not started** | Java keeps them per player in memory; the Rust mod saves them to a file |
| Several strikes at once | done | each has its own clock, parameters and table; they share the per-tick budgets |
| Per-tick budgets (20,000 blocks, 400 commands) | done | shared across strikes |
| Paced block edits (wait while frames are slow) | not started | `pace.rs`; the Java budget is fixed |
| Fuel metering (the Rust mod's sandbox limit) | not applicable | Java has no fuel limit; big stages can still hitch a tick |
| Force-load the chunks a big strike works on | done | released on `/orbital stop` |
| Kill mobs and items within the strike's radius | done | per plan; the original spares players |
| Far targets (land drawn by Voxy and similar, not loaded) | done | `FarTarget`; a pick may load a few chunks |
| Distance-aware sound (late, quieter, from the strike's direction) | done | about 343 blocks a second; flashes dim with distance |
| Camera shake and flashes | done | `Net.Shake`, `Net.Flash`, `ClientFx`; a stand-in for the original's picture jolt |
| Picture jolt inside the shader (`pl_jolt`, `nk_jolt`) | check | the shader has it; the Java side hands it the same parameters |
| Follow camera | not started | |
| Nuke and Rod knockback | not started | |
| Impact frames (Kanada, Black Flash, Cinematic) | not started | Rod only |
| QUALITY FAST (half-size smoke) | not started | needs the `fs_half` and `fs_join` stages and a second pass |
| Cloud shadows (`/orbital shadow`) | not started | |
| Iris shader packs | done | drawn after the pack's final picture, bob-inclusive projection |
| Sodium | done | |
| Voxy | done | |
| Distant Horizons | check | untried |
| Multiplayer (others see the strike) | not started | the effects draw only for the player who fired, as in the Rust mod; the server-side world changes work on a server, untested |
| Linux, macOS | check | untried; macOS is known to be a problem for the Rust mod's Downfall pass |
| AMD, Intel GPUs | check | untried |

## Loaders

| Loader | Status |
|---|---|
| Fabric | partial: this port |
| Quilt | not started (try the Fabric build first) |
| NeoForge | not started |
| Forge | not started |

## Keeping this honest

- When a row's status changes, change it here and in [../PARITY.md](../PARITY.md) in the same commit.
- "Done" needs a side-by-side check with the Horizon version at the same seed and distance (see
  [BUILD-AND-TEST.md](BUILD-AND-TEST.md)), not just "it runs".
- The "check" rows are unknowns: resolve them before relying on them.
