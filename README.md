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
  <a href="#getting-started"><b>Getting started</b></a>
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
> **It needs the Orbital Laser build of Horizon, release `orbital-mod-api-8` or newer.** Horizon's mod API doesn't
> yet let a mod catch an item's use, open its own screen, draw effects or change the world, so the mod runs on a
> fork that adds those:
> [Stink-O/horizon, branch `mod-api-input-ui-render-world`](https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world),
> with a ready-built Linux download on its [releases](https://github.com/Stink-O/horizon/releases). Older fork builds
> won't start the mod. You also need your own copy of Minecraft Java Edition 26.3: nothing from Minecraft is in this
> repository or the downloads.

> [!WARNING]
> **Early and experimental.** Developed and tested on one Linux PC (Fedora, NVIDIA). Windows and macOS are untested,
> and the ready-built Horizon is Linux x86-64 only (elsewhere, build the fork from source).

**Contents:** [New in 0.5.6](#new-in-056) · [The lasers](#the-lasers) · [Getting started](#getting-started) ·
[Set it up with an AI agent](#set-it-up-with-an-ai-agent) · [How to play](#how-to-play) ·
[If something goes wrong](#if-something-goes-wrong) · [Known gaps](#known-gaps) · [Credits and licence](#credits-and-licence)

## New in 0.5.6

<!-- Nuke still, once captured: <p align="center"><img alt="The Nuke: a mushroom cloud hundreds of blocks tall over the land, its shadow across the ground" width="720" src="docs/35-nuke-cloud.jpg"></p> -->

- **Nuke**, the eleventh laser, on the wheel's third page and `/orbital nuke`. A white-hot streak across the sky, a
  dive, then a blinding flash, a fireball boiling up into a mushroom cloud and a shockwave in a wall of dust that
  knocks you off your feet. It leaves a terraced crater about 200 blocks across, the land flattened out to about 230
  and scorched out to about 480. It lasts 90 seconds.
- **The Payload** casts its cloud's shadow on the land, and its craters cut into water naturally.
- **No more "took too long".** Big strikes are split into small steps, so no laser stops the mod, and terrain goes in
  paced by the frame rate, with much less stutter.
- **Needs the next Orbital Laser build of Horizon**, `orbital-mod-api-8` (it adds `world.push-player`, the Nuke's
  knockback). Older builds won't start the mod.

Earlier versions: [docs/CHANGES.md](docs/CHANGES.md).

## The lasers

Eleven lasers, five to a page of the wheel.

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

Plasma, Godly, the Black Hole and the Meteor Storm reach 200 blocks; the Mothership, the Downfall, the Planet Killer, the
Crystal Bloom, the Sinkhole, the Payload and the Nuke reach 1000. [How it works](docs/HOW-IT-WORKS.md#the-lasers-in-detail) describes each one from start to finish.

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

<!-- Nuke stills, once captured:
| Nuke | The flash | The cloud | The crater |
|---|---|---|---|
| ![The bomb coming in from orbit, a white-hot streak across the sky](docs/33-nuke-fall.jpg) | ![The blinding white flash as it bursts over the land](docs/34-nuke-flash.jpg) | ![The mushroom cloud rolling over on itself, its shadow across the land, the dust wall racing out](docs/35-nuke-cloud.jpg) | ![The terraced crater with its glassy floor and broken rim, the land flattened round it](docs/36-nuke-crater.jpg) |
-->

## Getting started

1. **Get the Orbital Laser build of Horizon** (`orbital-mod-api-8` or newer). Download
   `horizon-orbital-linux-x86_64.tar.gz` from [Stink-O/horizon releases](https://github.com/Stink-O/horizon/releases)
   and unpack it to `~/horizon-orbital`.

   It needs Horizon's prepared resources, made once from your own Minecraft 26.3 (Horizon's
   [PLAY.txt](https://github.com/ludovic111/horizon) explains the server jar and Java 25):

   ```sh
   cd ~/horizon-orbital
   ./horizon-prepare --prepare --server-jar PATH/TO/server.jar
   ./horizon-prepare sounds
   ```

   If you already have Horizon set up, skip that and point `HORIZON_RESOURCES` at its prepared resources (the folder
   `.local/horizon-client/26.3` inside it).

2. **Install the mod.** Download `orbital-laser-v0.5.6.zip` from the
   [latest release](https://github.com/Stink-O/orbital-laser/releases/latest), unzip it, and with the game closed run:

   ```sh
   python3 install.py
   ```

   It copies the mod into Horizon's game folder (`~/.local/share/horizon/horizon-mods/orbital`, or `$HORIZON_HOME`) and
   switches it on. If 0.1's shader pack and sound pack are installed, it takes them out.

3. **Play.** From the same folder:

   ```sh
   ./play.sh                 # a creative test world called OrbitalTest
   ./play.sh MyWorld         # or one of yours (back it up first)
   ```

   It starts the Orbital Laser build on your normal game folder, so your worlds, settings and mods are all there.

4. **In the game,** type `/orbital give` for the Designator and the Remote.

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

1. Type **`/orbital give`** for the **Orbital Laser Designator** and the **Orbital Remote**.
2. **Pick a laser.** Right-click with the remote, or press **R**, and the laser wheel opens. Point at a laser to read
   what it does and click to load it. The arrows either side of the ring, the tabs over it or a right-click turn the
   page. The middle switches terrain damage on or off, and Escape closes the wheel. Your choices are remembered.
3. **Fire.** Hold the designator, aim at a target and **hold right-click** for under a second. The action bar shows
   `ACQUIRING TARGET…` (`SEISMIC SCAN…` for the Sinkhole, `DESIGNATING…` for the Payload and the Nuke), then the strike lands where your crosshair is.

Only one strike runs at a time. Plasma, Godly and the Black Hole take about 26 seconds, the Planet Killer 30.5, the
Mothership 34, the Meteor Storm 38, the Sinkhole 40, the Crystal Bloom 60, the Downfall 64, the Payload 70 and the Nuke 90.

The wheel also has:

- **FLY SPEED** over the title, for getting round the craters: click along the bar for 1x to 40x vanilla's creative
  flight, or type any speed up to 1000x in the box beside it and press Enter.
- **MESSAGES** and **PANEL** switches, which turn off the strikes' messages over the hotbar and the status panel shown
  at the top right while you hold either item.
- A **QUALITY** switch under them: **FAST** (the default) draws the Payload's and the Nuke's smoke, dust and trail at half the
  width and height and lays them over the full-size picture, keeping their edges against blocks and the sky; **FULL**
  draws every pixel (about two to three times the GPU time).
- **STOP STRIKE** at the top left while a strike is under way: it ends the strike there and then (what it has already
  done to the world stays), the same as `/orbital stop`.
- For the Mothership and the Downfall, rows for where the ship comes in from, how it arrives, and its colour.
- For the Payload, a **BLAST SOUND** row: **MAIN** (deep and rolling) or **ALT** (a sharp crack and a wide roar), the
  same choice as `/orbital payloadsound`.

| Command | What it does |
|---|---|
| `/orbital give` | gives you the Designator and the Remote |
| `/orbital wheel` | opens the laser wheel |
| `/orbital plasma`, `godly`, `blackhole`, `meteor`, `mothership`, `downfall`, `planetkiller`, `crystalbloom`, `sinkhole`, `payload`, `nuke` | loads that laser |
| `/orbital terrain on\|off` | terrain damage on, or off (light and sound only) |
| `/orbital approach ahead\|behind\|left\|right\|overhead` | where the ship comes in from |
| `/orbital arrival snap\|unfold\|warp` | how the ship arrives |
| `/orbital colour green\|red\|amber\|blue\|violet\|white` | the loaded ship's colour |
| `/orbital flyspeed N\|reset` | creative flying speed, N times vanilla's (up to 1000) |
| `/orbital messages on\|off`, `/orbital hud on\|off` | the strikes' messages, the status panel |
| `/orbital payloadsound main\|alt` | the Payload's blast: the main one or the alternative; also the wheel's BLAST SOUND row |
| `/orbital quality full\|fast` | the Payload's and the Nuke's smoke at full size, or at half size (faster); also the wheel's QUALITY switch |
| `/orbital stop` | ends the strike under way (also the wheel's STOP STRIKE button) |
| `/orbital skip SECONDS` | starts the next strike that far in, to look at one moment (terrain damage off only) |

[How it works](docs/HOW-IT-WORKS.md#commands) has the full details of each command. To rebind **R**: **Options →
Controls → Key Binds**, the *Orbital Laser* section at the bottom.

## If something goes wrong

- **No wheel, no `/orbital` command, or the items do nothing.** You're running stock Horizon or an older fork build.
  Start the game with `./play.sh` on `orbital-mod-api-8` or newer. On **Options → Mods**, Orbital Laser's row says why
  if it stopped.
- **`play.sh` can't find the build or the resources.** Set `HORIZON_ORBITAL` to the folder with the build's
  `horizon-client` and `horizon-ctl`, and `HORIZON_RESOURCES` to the prepared resources.
- **R does nothing.** Something else may use R: check **Options → Controls → Key Binds** (a clash is shown in yellow)
  and rebind it. R only opens the wheel while you play, not over another screen.
- **`NO TARGET IN RANGE`.** You're aiming at the sky, too far, or at unloaded chunks. Past your render distance only
  the Mothership, the Downfall, the Planet Killer, the Crystal Bloom, the Sinkhole, the Payload and the Nuke can aim, and only with **LOD Distance** on in Video Settings.
- **`STRIKE IN PROGRESS`.** One strike runs at a time. Wait for it to finish.
- **No sound.** Check the in-game master volume (Music & Sounds) and your system volume for the game.
- **The shaft fills with water, or ends in obsidian.** It hit groundwater, and the lava at the bottom met it.

## Known gaps

- **It needs a Horizon fork** until Horizon adds these capabilities upstream. The ready-built fork is Linux x86-64 only.
- **Linux only so far.** Windows and macOS are untested.
- **Single player** (or hosting LAN). The world changes need a world the game itself runs, and the effects are drawn
  only for the player who fired.
- **Terrain damage can't be undone.** Back up the world, or switch terrain damage off.
- **Targets must be in loaded chunks.** The seven long-range lasers reach 1000 blocks across the distant terrain, where
  the aim follows the coarser distant heights, and a crater only shows there once those chunks load.
- **Stock Horizon** builds from before 24 October 2026 can run 0.1's setup (Plasma and Godly only, driven from outside
  the game): see [How it works](docs/HOW-IT-WORKS.md#stock-horizon).

To build the mod from source or change it, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits and licence

Orbital Laser is under the MIT License (`LICENSE`). Third-party notes are in `NOTICE`. It is built on
[Horizon](https://github.com/ludovic111/horizon) by Ludovic and contributors (MIT), and the Orbital Laser build of Horizon
is a fork of it.

Minecraft is a trademark and work of Mojang Studios and Microsoft. Orbital Laser is an independent fan project, not made
by or affiliated with Mojang, Microsoft or Horizon's author, and it contains none of their code, textures or sounds. You
need your own copy of Minecraft.
