<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/branding/orbital-laser-logo-dark.svg">
    <img alt="Orbital Laser" width="640" src="docs/branding/orbital-laser-logo-light.svg">
  </picture>
</p>

# Orbital Laser

**An orbital laser strike, as a mod for [Horizon](https://github.com/ludovic111/horizon), the Rust rewrite of
Minecraft Java.** Pick a laser from a wheel, hold the Orbital Laser Designator on a target, and a strike comes down from
orbit. It digs a crater and a shaft to bedrock, flattens what stands round it and leaves the land changed for good.

<p align="center">
  <a href="https://github.com/Stink-O/orbital-laser/releases/latest"><b>Download</b></a>
  &nbsp;·&nbsp;
  <a href="#quick-install-regular-horizon"><b>Quick install</b></a>
  &nbsp;·&nbsp;
  <a href="#getting-started"><b>Fork version</b></a>
  &nbsp;·&nbsp;
  <a href="docs/HOW-IT-WORKS.md"><b>How it works</b></a>
</p>

<p align="center">
  <a href="https://github.com/Stink-O/orbital-laser/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Stink-O/orbital-laser"></a>
  <a href="https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world"><img alt="Horizon mod API 0.1 + input, ui, render, world" src="https://img.shields.io/badge/Horizon%20mod-input%20%C2%B7%20ui%20%C2%B7%20render%20%C2%B7%20world-62b47a"></a>
  <img alt="Tested on Linux" src="https://img.shields.io/badge/tested%20on-Linux-informational">
  <img alt="Rust" src="https://img.shields.io/badge/Rust-WebAssembly-b7410e?logo=rust&logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

<p align="center">
  <img alt="The Mothership: a vast dark metal ship lit with green seams over the land, its green beam striking the ground" width="720" src="docs/11-mothership.jpg">
</p>

> [!WARNING]
> **Strikes wreck the land for good.** Use a throwaway world or back yours up. The Planet Killer alone leaves a crater
> 480 blocks across, so stand at least 450 blocks back. The wheel's centre (or `/orbital terrain off`) makes strikes
> light and sound only. [What each laser destroys](docs/HOW-IT-WORKS.md#what-each-strike-destroys).

> [!IMPORTANT]
> **Two ways to play.** The [native version](#quick-install-regular-horizon) runs on regular Horizon: the launcher
> compiles it into the game. The [fork version](#getting-started) is a WebAssembly mod for the Orbital Laser build of
> Horizon ([Stink-O/horizon](https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world), release
> `orbital-mod-api-10` or newer), with a ready-built Linux download on its
> [releases](https://github.com/Stink-O/horizon/releases). Either way you need your own copy of Minecraft Java
> Edition 26.3: nothing from Minecraft is in this repository or the downloads.

> [!WARNING]
> **Early and experimental.** Developed and tested on one Linux PC (Fedora, NVIDIA). Reported working on Windows 11 by
> a user (the fork built from source); on macOS the Downfall's effects may not draw (see [Known gaps](#known-gaps)). The
> ready-built Horizon is Linux x86-64 only (elsewhere, build the fork from source).

**Contents:** [Quick install](#quick-install-regular-horizon) · [New in 0.5.9](#new-in-059) · [The lasers](#the-lasers) · [Fork version](#getting-started) ·
[Set it up with an AI agent](#set-it-up-with-an-ai-agent) · [How to play](#how-to-play) ·
[If something goes wrong](#if-something-goes-wrong) · [Known gaps](#known-gaps) · [Credits and licence](#credits-and-licence)

## Quick install (regular Horizon)

1. Install the [Horizon launcher](https://playhorizon.dev) (0.2.37 or newer) and set up an instance from your own
   Minecraft Java Edition 26.3.
2. Download **`orbital.hnmod`** from the [latest release](https://github.com/Stink-O/orbital-laser/releases/latest).
3. Close the game. On the launcher's Instances page press **Open folder**, and put `orbital.hnmod` in the
   **`horizon-native-mods`** folder (make it if it isn't there).
4. On the launcher's **Mods** page, check Orbital Laser is on.
5. On the **Native build** row pick **Release build**, press **Build**, and choose **I trust these mods: build**. The
   first build takes 20 to 30 minutes.
6. Press Play, open a creative world and type **`/orbital give`**. Hold the Designator and press **R** to pick a
   laser, then hold right-click on a target to fire.

**What each system needs first.** Linux: a C compiler, `pkg-config` and the ALSA and libudev development files (the
launcher gives you the command). Windows: nothing. macOS on Apple Silicon: `xcode-select --install`. Intel Macs can't
build native mods. It's played and tested on Linux; on Windows and Apple Silicon it builds but hasn't been played yet.

A native mod isn't sandboxed: its code runs with full access to your computer, so only build it if you trust it. A
listing in the launcher's Mods browser is in review. The
[install guide](https://github.com/Stink-O/orbital-laser/releases/latest/download/INSTALL.md) has the known issues
and how to remove it.

## New in 0.5.9

- **It runs on regular Horizon.** The new native version needs no fork build and no `play.sh`: see
  [Quick install](#quick-install-regular-horizon).
- **The Orbital Remote is gone.** The Designator is the one item: `/orbital give` gives you it, and **R** with it in
  hand opens the laser wheel. A Remote already in a world's inventory turns into an empty slot.
- **R opens the wheel only while you hold the Designator.** With anything else in hand R is left alone for whatever
  else you use it for. `/orbital wheel` still opens the wheel from anywhere.
- **Leaving the world ends the strike.** Before, a strike carried on into the next world you opened. Now it ends
  as you leave, and the chunks it forceloaded are let go the next time you play that world. The pause menu holds the
  strike where it is, sounds included, until you go back to the game.
- **A known gap on the fork version:** the game doesn't stop the sounds playing when you Save and Quit to Title, so a
  strike's sounds can run on over the title screen until they end. It needs a fix in Horizon itself.

Earlier versions: [docs/CHANGES.md](docs/CHANGES.md).

## The lasers

Fourteen lasers, five to a page of the wheel.

- **Plasma.** A raging beam with forked lightning. The crater fuses into glass, obsidian and magma, ringed in fire.
- **Godly.** The clouds part and a pillar of light comes down. The crater turns to quartz and gold, with flowers.
- **Black Hole.** A singularity opens over the target and bends the light round it. It tears the ground up into orbit,
  swallows it and drags the land into spiral arms.
- **Meteor Storm.** 72 meteors pound the land round the target, then one the size of a hill hits it: a crater about 125
  blocks across.
- **Mothership.** A kilometre-long ship drops in over the target, drills a shaft to bedrock and cuts a molten trench
  with its beam. You pick where it comes in from, how it arrives and its colour.
- **Downfall** (page two). The Mothership again, but a meteor brings it down. It crashes into the land and buries itself,
  and then its black hole engine ruptures and swallows the wreck.
- **Planet Killer** (page two). Seven towers out on the horizon strike a ring in the sky with lightning, and its beam
  leaves a crater 480 blocks across.
- **Crystal Bloom** (page two). A forest of crystal spires bursts out of the land, hums as one and shatters into pieces
  that land as real blocks, leaving a geode crater with a well to bedrock, broken crystal pillars and shards.
- **Sinkhole** (page two). Nothing from the sky: the land cracks and caves in, slab by slab, each slab carrying its
  real ground and trees as it falls, into a sheer pit about 225 blocks across and down to bedrock.
- **Payload** (page two). A bright point high in the sky comes down on one long arc from orbit, slow at first, then fast as a fireball,
  crackling and shedding burning chunks, its lumpy smoke trail hanging in the sky: a column of smoke boils up, a wall of dust
  races out over the land and debris rains down, and the column slowly melts into a drifting haze. It leaves a bomb crater.
- **Nuke** (page three). A bomb comes in from orbit, a white-hot streak across the sky, cools and
  dives onto the target, faster and faster, then bursts over the land: a blinding white flash, a fireball
  boiling up into a mushroom cloud hundreds of blocks tall that rolls over on itself, its shadow across the land, and a
  shockwave racing out in a wall of dust. The boom arrives late with the distance. It leaves a terraced crater about
  200 blocks across and 40 deep with a glassy floor (flooded where it cuts into water), the land flattened out to about
  230 with the trees felled pointing away, the ground charred in streaks, what faces the flash scorched out to about
  480, and every mob within 300 killed.
- **Rod from God** (page three). A colossal rod of dark forged metal dropped from orbit, kinetic, no explosive, and
  holy: it comes straight down onto the target, a golden-white star high overhead that grows fast, god rays streaming
  from it and a column of light down its path, and in its last fraction of a second it slams in. It strikes: the
  picture freezes on the hit for a fifth of a second of hard-cut impact frames (by default black-and-white
  silhouettes with thick lines rushing into the point, a close-up in negative with gold lines, gold and umber; BLACK
  FLASH and CINEMATIC are the other looks), then lets go with a blur, a blinding radiant burst with rays fanning out, the land rippling out in rings like
  water, a jet of molten rock up its path, a short plume of dust spreading into a haze and a ring of dust racing out
  over the land, then one colossal crack-boom, late with the distance. The crater is blasted out round it in a moment, then lined in white and gold from the rod out, and it leaves
  itself standing in a hallowed crater about 120 blocks across and 50 deep, the floor round its foot heaved up in
  broken slabs: the rod, 13 blocks thick and 130 tall over the crater's floor, its top 80 over
  the land, polished blackstone banded in gold and capped with light; the crater lined in quartz, calcite and gold with
  veins of glowstone, rays of white and gold over pale grass round it, rubble out to about 250, the trees felled out to
  about 200, and every mob within 200 killed.
  **Photosensitivity:** its impact frames are a fifth of a second of hard cuts over the whole picture;
  `/orbital impactframes off` (or OFF on the wheel's IMPACT FX row) leaves them out.
- **Supercell** (page three). A storm called down: the sky darkens and a turning wall cloud and an anvil-topped storm
  cloud boil up over the target, rain pouring out of them; lightning strikes all over the land under it, faster
  and faster, thin funnels come down and wander over the land, the bolts draw in on the target, a rapid run of them
  lands on it, a moment's hush, then one colossal strike at 29 seconds. It leaves small
  scorched pits, the funnels' scoured tracks and a crater about 70 across with veins of fused glass branching out
  through the ground round it; the fires it lights are left burning, and can spread.
- **Hurricane** (page three). A hurricane spun up over the target, some 3,500 blocks across: towering storms gather
  and wind into spiral rain bands round a dense core, the eye opens into a stadium of cloud with clear sky overhead,
  rain sweeps past you and lightning bursts in the eyewall. The wind tears the land up from the eyewall out to about
  150 blocks: the plants and leaves first, then the trees, everything built (roofs first) and the ground's top blocks,
  all of it rising out of the land and whirling round the eye in the game's own textures, trees uprooted, snapped or
  breaking apart in the air. Mobs are carried round with it, and the wind picks you up too and carries you round the
  eyewall (hold **sneak** for half a second to break free; `/orbital knockback off` leaves you standing). At 46 seconds
  the winds drop and it flings everything out: the trees and pieces of buildings land as real blocks where they fall,
  rubble rains down out to about 170, and you are thrown clear. Chests and the like stay where they are, with what's
  in them. **Photosensitivity:** its lightning is bright flashes over much of the picture, in bursts at about 16-28 and
  43-46 seconds.

Plasma, Godly, the Black Hole and the Meteor Storm reach 200 blocks; the Mothership, the Downfall, the Planet Killer, the
Crystal Bloom, the Sinkhole, the Payload, the Nuke, the Rod from God, the Supercell and the Hurricane reach 1000. [How it works](docs/HOW-IT-WORKS.md#the-lasers-in-detail) describes each one from start to finish.

| The laser wheel | Plasma | What Godly leaves behind |
|---|---|---|
| ![The laser wheel: Plasma and Godly segments round a terrain-damage switch](docs/05-wheel.jpg) | ![A plasma beam with forked lightning, a shockwave ring and a molten crater](docs/02-impact.jpg) | ![A quartz and gold crater with a golden sigil, quartz pillars and floating islands of rock](docs/07-godly-aftermath.jpg) |

| Meteor Storm | The extinction impact | What it leaves |
|---|---|---|
| ![Meteors streaking down through the sky and landing across the land in flashes of light](docs/08-meteor-storm.jpg) | ![The big impact: a fireball tearing open with burning ejecta thrown out every way](docs/09-meteor-impact.jpg) | ![A huge glowing crater rimmed with fire in charred land](docs/10-meteor-crater.jpg) |

| Mothership | Its underside | For scale, from 900 blocks |
|---|---|---|
| ![A vast dark metal ship lit with green seams hanging over the land, its green beam striking the ground](docs/11-mothership.jpg) | ![Looking up at the ship's underside: plated decks, green-lit seams, window lights and the beam's emitter](docs/12-mothership-underside.jpg) | ![The whole ship hanging over the horizon, small against the sky, its beam on the land below](docs/13-mothership-scale.jpg) |

| Downfall | The crash | The black hole |
|---|---|---|
| ![The Downfall falling, fires burning on its roof and smoke streaming off it](docs/14-downfall-fall.jpg) | ![The burning ship ploughing into a mountain, earth flung up along its sides, smoke trailing behind](docs/15-downfall-crash.jpg) | ![The black hole tearing up what is left of the wreck](docs/16-downfall-black-hole.jpg) |

| Planet Killer | The beam | The burst | The crater |
|---|---|---|---|
| ![The Planet Killer's towers on the horizon striking the ring of light in the sky with bolts of lightning](docs/17-planet-killer-lightning.jpg) | ![The Planet Killer's beam hitting the land, cracks glowing across the ground round it](docs/18-planet-killer-beam.jpg) | ![The Planet Killer's burst: a fireball rising out of the crater](docs/19-planet-killer-burst.jpg) | ![The Planet Killer's crater afterwards, seen from high above at a distance](docs/20-planet-killer-crater.jpg) |

| Crystal Bloom | The resonance | The shatter | What it leaves |
|---|---|---|---|
| ![Crystal spires blooming out of the cracked ground](docs/21-crystal-bloom-bloom.jpg) | ![Prism beams and an aurora over the crystal spires as they resonate](docs/22-crystal-bloom-prism.jpg) | ![The spires shattering into fractured pieces](docs/23-crystal-bloom-detonation.jpg) | ![The geode crater with broken crystal pillars and shards, seen from the ground](docs/24-crystal-bloom-aftermath.jpg) |

| Sinkhole | The collapse | The pit | What it leaves |
|---|---|---|---|
| ![Cracks racing out over the land from the target](docs/25-sinkhole-cracks.jpg) | ![The land caving in, dust boiling up out of the collapse](docs/26-sinkhole-collapse.jpg) | ![The dark pit opening as the dust settles](docs/27-sinkhole-pit.jpg) | ![The finished pit, waterfalls pouring over its rim into the dark](docs/28-sinkhole-aftermath.jpg) |

| Payload | The dive | The impact | The column |
|---|---|---|---|
| ![A bright point high in the sky trailing a lumpy smoke trail](docs/29-payload-sky.jpg) | ![The fireball diving at the land, shedding burning chunks](docs/30-payload-dive.jpg) | ![The flash and the burst of fire as it hits](docs/31-payload-impact.jpg) | ![The column of smoke rising out of the crater, the bomb's trail still hanging in the sky](docs/32-payload-column.jpg) |

| Nuke | The flash | The cloud | The crater |
|---|---|---|---|
| ![The bomb's smoke trail arcing over into its dive](docs/33-nuke-fall.jpg) | ![The fireball bursting on the ground, the shockwave's dome racing out over a wall of dust](docs/34-nuke-flash.jpg) | ![The mushroom cloud towering over its crater](docs/35-nuke-cloud.jpg) | ![The terraced crater with its glassy floor and broken rim, the land flattened round it](docs/36-nuke-crater.jpg) |

| Rod from God | The impact frames | The burst | What it leaves |
|---|---|---|---|
| ![The rod coming straight down onto the land, glowing white, god rays round it](docs/37-rod-fall.jpg) | ![An impact frame: the rod and the land as gold and umber silhouettes, thick lines converging on the point](docs/38-rod-impact-frames.jpg) | ![The radiant burst as it strikes, rays fanning out over the land](docs/39-rod-burst.jpg) | ![The rod standing in its crater, the land round it bleached white and gold](docs/40-rod-crater.jpg) |

<!-- HURRICANE STILLS GO HERE (optional): a gallery row like the ones above, for example
| Hurricane | The eye | The tear-up | What it leaves |
|---|---|---|---|
| ![...](docs/45-hurricane-....jpg) | ![...](docs/46-....jpg) | ![...](docs/47-....jpg) | ![...](docs/48-....jpg) |
-->

## Getting started

1. **Get the Orbital Laser build of Horizon** (`orbital-mod-api-10` or newer). Download
   `horizon-orbital-linux-x86_64.tar.gz` from [Stink-O/horizon releases](https://github.com/Stink-O/horizon/releases)
   and unpack it to `~/horizon-orbital`.

   **On Windows and macOS**, build it from source instead: branch `mod-api-input-ui-render-world` of
   [Stink-O/horizon](https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world), with the mod runtime
   switched on:

   ```sh
   cargo build --release -p horizon-client --features mods
   ```

   Without `--features mods` the mod only half-loads: its items are there, but `/orbital` is an unknown command, and
   the game's log says `1 mod(s) not started: this build has no mod runtime (build with --features mods)`.

   It needs Horizon's prepared resources, made once from your own Minecraft 26.3 (Horizon's
   [PLAY.txt](https://github.com/ludovic111/horizon) explains the server jar and Java 25):

   ```sh
   cd ~/horizon-orbital
   ./horizon-prepare --prepare --server-jar PATH/TO/server.jar
   ./horizon-prepare sounds
   ```

   If you already have Horizon set up, skip that and point `HORIZON_RESOURCES` at its prepared resources (the folder
   `.local/horizon-client/26.3` inside it).

   If `horizon-prepare --prepare` says your `26.3.json` is *a 26.3 version file Horizon does not know yet*, your copy
   is fine: Mojang republished it. The fork's builds from `orbital-mod-api-9` on know the republished files; if Mojang
   republishes again, copy [upstream Horizon's `research-lock.json`](https://github.com/ludovic111/horizon/blob/main/research-lock.json)
   over the one at the top of the fork's folder (it's read as `horizon-prepare` runs: nothing to rebuild) and run it
   again.

2. **Install the mod.** Download `orbital-laser-v0.5.8.zip` from the
   [latest release](https://github.com/Stink-O/orbital-laser/releases/latest), unzip it, and with the game closed run:

   ```sh
   python3 install.py
   ```

   It copies the mod into Horizon's game folder (`~/.local/share/horizon/horizon-mods/orbital`, or `$HORIZON_HOME`) and
   switches it on. If 0.1's shader pack and sound pack are installed, it takes them out.

3. **Play.** From the same folder, in a terminal:

   ```sh
   ./play.sh                 # a creative test world called OrbitalTest
   ./play.sh MyWorld         # or one of yours (back it up first)
   ```

   It starts the Orbital Laser build on your normal game folder, so your worlds, settings and mods are all there.
   Always start the game this way: Horizon's own launcher, or a stock `horizon-client`, can't run the mod. If
   `play.sh` can't find the build it says what's missing (started without a terminal, it also writes that to
   `play-error.txt` beside it).

4. **In the game,** type `/orbital give` for the Designator.

## Set it up with an AI agent

If you use a coding agent (Claude Code, Codex, Cursor and the like), paste the message below into it and it can do the
whole setup on your computer. [AGENTS.md](AGENTS.md) has the same guidance for agents that read the repository
themselves.

````text
Set up Orbital Laser on this computer and get a test strike working, end to end:
https://github.com/Stink-O/orbital-laser

Orbital Laser is a mod for Horizon, the Rust rewrite of Minecraft Java. It runs on a Horizon fork that
adds the mod capabilities it needs. Before doing anything, read README.md (especially "Getting started",
"If something goes wrong" and "Known gaps") and AGENTS.md from the repository: they say which fork release,
which Minecraft version and which commands the current release needs. Trust them over anything you
remember, since they change with each release.

Ground rules:
- Minecraft is not included. Horizon's resources come from my own copy of Minecraft Java, the version the
  README names. Don't download, fake or work around it; if I don't have it, stop and tell me.
- Stock Horizon can't run this mod: use the fork's build the README names. Use its ready-built download
  if there is one for my system; otherwise build it from source, and tell me before you start, since that
  takes a while.
- Check what my system has before installing anything, and ask me before installing tools or packages.
- Strikes are destructive and permanent: they dig craters and kill mobs, and the biggest lasers reshape
  hundreds of blocks of land. Only use a throwaway creative world (play.sh makes one), never one of my
  real worlds, and ask me before the first strike with terrain damage on. Terrain damage can be turned
  off (the README says how); test with it off first.
- Install with the game closed. Don't change my saves or settings beyond what the installer does.
- If you have to work around something on my system, keep the fix small and tell me exactly what you
  changed and why.

Steps:
1. Get the fork's build of Horizon and its prepared resources, as the README describes.
2. Get the latest Orbital Laser release (or clone the repository) and run its installer.
3. Start the game in a throwaway world and give me the mod's items.
4. Test safely: open the laser wheel, then fire one strike with terrain damage off, and check it plays
   with sound and no errors in chat. Ask me before a strike with terrain damage on.
5. Tell me how to use it: how to open the wheel, fire, and rebind the keys.

Report each step's result as you go. If a step fails, show me the exact command and message, say what you
think is wrong, and fix it. Don't guess past a failure. If the game shows the mod as stopped (Options >
Mods), read the reason it gives first.
````

## How to play

1. Type **`/orbital give`** for the **Orbital Laser Designator**.
2. **Pick a laser.** Press **R** with the designator in hand (or type `/orbital wheel`) and the laser wheel opens. Point
   at a laser to read what it does and click to load it. The arrows either side of the ring, the tabs over it or a
   right-click turn the page. The middle switches terrain damage on or off, and Escape closes the wheel. Your choices
   are remembered.
3. **Fire.** Hold the designator, aim at a target and **hold right-click** for under a second. The action bar counts
   down (`ACQUIRING TARGET…`, `SEISMIC SCAN…` for the Sinkhole, `DESIGNATING…` for the Payload, the Nuke and the Rod,
   `TRACKING STORM…` for the Hurricane), then the strike lands where your crosshair is. Nothing else pops up over the
   hotbar but `NO TARGET IN RANGE`.
4. **Caught in the Hurricane?** Its wind picks you up and carries you round the eye. Hold **sneak** for half a second
   to break free; while you fly it leaves you alone, but stop flying for a second while it still blows where you are
   and it grabs you again. If it still has you at 46 seconds it throws you clear (a survival player gets a few seconds
   of Resistance V so the landing doesn't kill them).

Only one strike runs at a time. Plasma, Godly and the Black Hole take about 26 seconds, the Planet Killer 30.5, the
Mothership 34, the Meteor Storm 38, the Sinkhole 40, the Supercell 42, the Crystal Bloom and the Rod from God 60, the Downfall and the Hurricane 64, the Payload 70 and the Nuke 90.

The wheel also has:

- **FLY SPEED** over the title, for getting round the craters: click along the bar for 1x to 40x vanilla's creative
  flight, or type any speed up to 1000x in the box beside it and press Enter.
- Down the right, a **PANEL** switch, which hides the status panel shown at the top right while you hold either item,
  and a **QUALITY** switch under it: **FAST** (the default) draws the Payload's, the Nuke's and the Rod's smoke, dust and trail and the Supercell's storm at half the
  width and height and lays them over the full-size picture, keeping their edges against blocks and the sky; **FULL**
  draws every pixel (about two to three times the GPU time).
- **STOP STRIKE**, a red button under QUALITY while a strike is under way: it ends the strike there and then (what it
  has already done to the world stays), the same as `/orbital stop`.
- Down the left, the strike options. **SEED** shows the last strike's seed, or takes one you type (1 to 997), and
  **LOCK SEED** keeps it, so a strike plays out the same way take after take (`/orbital seed`). Under them, for the
  lasers they apply to: **KNOCKBACK** (the Nuke, the Rod and the Hurricane), whether the blast pushes you or the wind
  carries you, and **FOLLOW** (the Nuke and the Payload), the follow camera.
- An **IMPACT FX** row under the ring while the Rod from God is pointed at or loaded: **OFF**, **KANADA** (the
  default), **BLACK FLASH** or **CINEMATIC**, as `/orbital impactframes`.
- For the Mothership and the Downfall, rows for where the ship comes in from, how it arrives, and its colour.
- For the Payload, a **BLAST SOUND** row: **MAIN** (deep and rolling) or **ALT** (a sharp crack and a wide roar), the
  same choice as `/orbital payloadsound`. The Nuke has one too: **MAIN** (a hard crack, an overdriven boom) or **ALT**
  (a rounder, bassier boom and a longer thunder roll), as `/orbital nukesound`.

| Command | What it does |
|---|---|
| `/orbital give` | gives you the Designator |
| `/orbital wheel` | opens the laser wheel |
| `/orbital plasma`, `godly`, `blackhole`, `meteor`, `mothership`, `downfall`, `planetkiller`, `crystalbloom`, `sinkhole`, `payload`, `nuke`, `rod`, `supercell`, `hurricane` | loads that laser |
| `/orbital terrain on\|off` | terrain damage on, or off (light and sound only) |
| `/orbital approach ahead\|behind\|left\|right\|overhead` | where the ship comes in from |
| `/orbital arrival snap\|unfold\|warp` | how the ship arrives |
| `/orbital colour green\|red\|amber\|blue\|violet\|white` | the loaded ship's colour |
| `/orbital flyspeed N\|reset` | creative flying speed, N times vanilla's (up to 1000) |
| `/orbital hud on\|off` | the status panel |
| `/orbital payloadsound main\|alt`, `/orbital nukesound main\|alt` | the Payload's or the Nuke's blast: the main one or the alternative; also the wheel's BLAST SOUND row |
| `/orbital quality full\|fast` | the Payload's, the Nuke's and the Rod's smoke and the Supercell's storm at full size, or at half size (faster); also the wheel's QUALITY switch |
| `/orbital impactframes kanada\|blackflash\|cinematic\|off` | the Rod from God's impact frames (a fifth of a second of hard cuts as it strikes) in one of three looks (Kanada is the default), or off; kept; also the wheel's IMPACT FX row |
| `/orbital foldpattern a\|b\|c` | the Fold's crease pattern for its next strike: umbrella (the default), waterbomb or diagonal; kept, also the wheel's FOLD row |
| `/orbital knockback on\|off` | the Nuke's and the Rod's push on you as the blast reaches you (the camera's jolt stays), and whether the Hurricane carries you off; also the wheel's KNOCKBACK switch |
| `/orbital carryview turn\|still` | while the Hurricane carries you, your view turns a little with you round the storm and sways with the gusts (`turn`, the default), or stays your own (`still`); kept |
| `/orbital follow on\|off` | the follow camera: an orbit round the Nuke's or the Payload's bomb as it comes in. Your mouse sets the angle (the camera sits 70 blocks back along your view), it backs off as the burst nears and orbits the fireball and the cloud, then puts you back where you stood; also the wheel's FOLLOW switch. Pairs well with the Cinematic Camera key (Options > Controls > Key Binds > Miscellaneous) |
| `/orbital follow distance N` | the follow camera's distance from the bomb, 10 to 400 blocks (70 by default) |
| `/orbital seed N\|lock\|random` | hold every strike's look at seed N (1 to 997), lock it at the last strike's, or go back to a fresh one each time; also the wheel's SEED field and LOCK SEED switch |
| `/orbital stop` | ends the strike under way (also the wheel's STOP STRIKE button) |
| `/orbital skip SECONDS` | starts the next strike that far in, to look at one moment (terrain damage off only) |

[How it works](docs/HOW-IT-WORKS.md#commands) has the full details of each command. To rebind **R**: **Options →
Controls → Key Binds**, the *Orbital Laser* section at the bottom.

## If something goes wrong

- **Options → Mods says `orbital — Can't be read: horizon-mod.toml: capability world is for server mods`.** That's
  stock Horizon, not the Orbital Laser build: the mod is installed fine, but stock Horizon can't run it. Quit, and
  start the game with `./play.sh` from a terminal (it finds the build in `~/horizon-orbital`, or tells you how to get
  it).
- **No wheel, no `/orbital` command, or the items do nothing.** You're running stock Horizon, an older fork build, or
  one built without `--features mods` (the log says *this build has no mod runtime*). Start the game with `./play.sh`
  on `orbital-mod-api-10` or newer. On **Options → Mods**, Orbital Laser's row says why if it stopped.
- **`play.sh` can't find the build or the resources, or says the build isn't the Orbital Laser one.** Set
  `HORIZON_ORBITAL` to the folder with the build's `horizon-client` and `horizon-ctl`, and `HORIZON_RESOURCES` to the
  prepared resources. Double-clicking `play.sh` in a file manager may show nothing: run it from a terminal to see its
  messages (or read `play-error.txt` beside it).
- **R does nothing.** Something else may use R: check **Options → Controls → Key Binds** (a clash is shown in yellow)
  and rebind it. R only opens the wheel while you play with the designator in hand, not over another screen. With
  anything else in hand it does nothing (`/orbital wheel` opens the wheel either way).
- **`NO TARGET IN RANGE`.** You're aiming at the sky, too far, or at unloaded chunks. Past your render distance only
  the Mothership, the Downfall, the Planet Killer, the Crystal Bloom, the Sinkhole, the Payload, the Nuke, the Rod, the Supercell and the Hurricane can aim, and only with **LOD Distance** on in Video Settings.
- **The designator only clicks.** A strike is already under way, and one runs at a time. Wait for it to finish, or end
  it with the wheel's STOP STRIKE or `/orbital stop`.
- **No sound.** Check the in-game master volume (Music & Sounds) and your system volume for the game.
- **The shaft fills with water, or ends in obsidian.** It hit groundwater, and the lava at the bottom met it.

## Known gaps

- **It needs a Horizon fork** until Horizon adds these capabilities upstream. The ready-built fork is Linux x86-64 only.
  A native version is in the works: Orbital Laser is being ported to Horizon's own native mods, with the hooks it needs
  going into Horizon itself ([horizon-rust/horizon#5727](https://github.com/horizon-rust/horizon/issues/5727)), so it
  will run on regular Horizon without the fork.
- **Tested on Linux.** Reported working on Windows 11 by a user (the fork built from source, `--features mods`).
- **macOS (Apple Silicon): the Downfall's effects may not draw.** Apple's Metal shader compiler fails on its effects
  (`XPC_ERROR_CONNECTION_INTERRUPTED` in `Device::create_render_pipeline`), and the Nuke's can when it's the laser
  loaded as the game starts. The other lasers work. The fork's builds from `orbital-mod-api-9` on (so the
  `orbital-mod-api-10` this release needs) stop the crash: a pass the driver can't build is skipped and tried again
  later, so on those Macs the Downfall's strike may run without its visuals. Since 0.5.7 the mod builds a laser's effects only once
  you're playing, and if the game closed while it built them, the next start loads the Plasma instead and says so in
  chat. On 0.5.6 or older, if the game crashes every time it starts, set `laser=plasma` in
  `horizon-mods/.horizon-mod-data/orbital/settings` in the game folder (or delete that file).
- **Single player** (or hosting LAN). The world changes need a world the game itself runs, and the effects are drawn
  only for the player who fired.
- **Terrain damage can't be undone.** Back up the world, or switch terrain damage off.
- **Targets must be in loaded chunks.** The ten long-range lasers reach 1000 blocks across the distant terrain, where
  the aim follows the coarser distant heights, and a crater only shows there once those chunks load.
- **Stock Horizon** builds from before 24 October 2026 can run 0.1's setup (Plasma and Godly only, driven from outside
  the game): see [How it works](docs/HOW-IT-WORKS.md#stock-horizon).

To build the mod from source or change it, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits and licence

Orbital Laser is under the MIT License (`LICENSE`). Third-party notes are in `NOTICE`. It is built on
[Horizon](https://github.com/ludovic111/horizon) by Ludovic and contributors (MIT), and the Orbital Laser build of Horizon
is a fork of it.

**Java Edition port:** [@Ramingen](https://github.com/Ramingen) is porting Orbital Laser to Minecraft Java Edition,
starting with Fabric ([#6](https://github.com/Stink-O/orbital-laser/pull/6)), with NeoForge and Forge to follow. The work
lives on the [`java` branch](https://github.com/Stink-O/orbital-laser/tree/java) until it's done.

Minecraft is a trademark and work of Mojang Studios and Microsoft. Orbital Laser is an independent fan project, not made
by or affiliated with Mojang, Microsoft or Horizon's author, and it contains none of their code, textures or sounds. You
need your own copy of Minecraft.
