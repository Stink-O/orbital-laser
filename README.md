<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/branding/orbital-laser-logo-dark.svg">
    <img alt="Orbital Laser" width="640" src="docs/branding/orbital-laser-logo-light.svg">
  </picture>
</p>

# Orbital Laser

**An orbital laser strike, as a mod for [Horizon](https://github.com/horizon-rust/horizon), the Rust rewrite of
Minecraft Java.** Pick a laser from a wheel, hold the Orbital Laser Designator on a target, and a strike comes down from
orbit. It digs a crater and a shaft to bedrock, flattens what stands round it and leaves the land changed for good.

<p align="center">
  <a href="https://github.com/Stink-O/orbital-laser/releases/latest"><b>Download</b></a>
  &nbsp;·&nbsp;
  <a href="#getting-started"><b>Get started</b></a>
  &nbsp;·&nbsp;
  <a href="docs/HOW-IT-WORKS.md"><b>How it works</b></a>
  &nbsp;·&nbsp;
  <a href="https://ko-fi.com/stinkoh"><b>Support it</b></a>
</p>

<p align="center">
  <a href="https://github.com/Stink-O/orbital-laser/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Stink-O/orbital-laser"></a>
  <a href="https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world"><img alt="Horizon mod API 0.1 + input, ui, render, world" src="https://img.shields.io/badge/Horizon%20mod-input%20%C2%B7%20ui%20%C2%B7%20render%20%C2%B7%20world-62b47a"></a>
  <img alt="Tested on Linux" src="https://img.shields.io/badge/tested%20on-Linux-informational">
  <img alt="Rust" src="https://img.shields.io/badge/Rust-WebAssembly-b7410e?logo=rust&logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <a href="https://ko-fi.com/stinkoh"><img alt="Support on Ko-fi" src="https://img.shields.io/badge/Ko--fi-support-ff5e5b?logo=ko-fi&logoColor=white"></a>
</p>

<p align="center">
  <img alt="The Sky Breaks: a huge eye flaring in a black hole punched through the cracked sky, broken panes round it, dust rising off the land below" width="720" src="docs/62-skybreak-eye-flare.jpg">
</p>

> [!WARNING]
> **Strikes wreck the land for good.** Use a throwaway world or back yours up. The Planet Killer leaves a crater
> 480 blocks across, the Fold one about 530 and the Supervolcano a caldera about 560, so stand well back. The wheel's centre (or `/orbital terrain off`) makes strikes
> light and sound only. [What each laser destroys](docs/HOW-IT-WORKS.md#what-each-strike-destroys).

> [!IMPORTANT]
> **How to play.** Orbital Laser runs on the Orbital Laser build of Horizon ([Getting started](#getting-started)), which
> has every laser. The native version for regular Horizon is off for now: Horizon's launcher moved to a new mod format
> on 18 November and no longer installs it ([Native version](#native-version-regular-horizon)). You need your own copy
> of Minecraft Java Edition 26.3: nothing from Minecraft is in this repository or the downloads. [Setup](docs/SETUP.md)
> has every step and option.

> [!WARNING]
> **Early and experimental.** Developed and tested on one Linux PC (Fedora, NVIDIA). Reported working on Windows 11 by
> a user (the fork built from source); on macOS the Downfall's effects may not draw. The ready-built Horizon is for
> Linux x86-64, with a Windows test build that has only been run under Wine so far.

**Contents:** [New in 0.5.18](#new-in-0518) · [Getting started](#getting-started) · [Native version](#native-version-regular-horizon) ·
[How to play](#how-to-play) · [The lasers](#the-lasers) · [If something goes wrong](#if-something-goes-wrong) ·
[Credits and licence](#credits-and-licence)

**More:** [Setup](docs/SETUP.md) · [Playing](docs/PLAYING.md) · [The lasers](docs/LASERS.md) ·
[Troubleshooting](docs/TROUBLESHOOTING.md) · [How it works](docs/HOW-IT-WORKS.md) · [Changes](docs/CHANGES.md)

## New in 0.5.18

A new laser, **the Colossi**. Five stone giants about 220 blocks tall heave themselves out of the earth in a ring 300
blocks round the target, tearing the land up round their feet. Each stamps a foot down, hauls its hammer up over its
shoulder and slams it into the ground in front of it, one after another, then all five together. Green cracks run from
the blows to the middle and meet, and the land bursts in a crown of earth round a column of dark smoke some 500 blocks
high while a wall of dust races out past the giants. Light runs back up each hammer into the arms holding it and they
burst into flying rock; the giants sink onto one knee and a glowing line sweeps down each, turning it into real blocks.
It leaves five kneeling statues round a terraced crater about 317 blocks across, split by glowing green fissures, the
hammers' wrecks lying in it and the trees felled round it. It's on the wheel's fifth page and `/orbital colossi`. It
isn't in the native version. The giants and their hammer were made in [Tripo](https://www.tripo3d.ai) and turned into
blocks with [model2mc](https://github.com/Stink-O/model2mc); this laser was sponsored by Tripo.
**Photosensitivity:** as the land bursts there are half a second of hard black-and-white impact frames and a white flash;
`/orbital impactframes off` or the wheel's FLASHES row (SOFT) leaves out the impact frames and holds the flash down.
See [The lasers](docs/LASERS.md#the-colossi).

Also a fix for the Earthquake. Where its fault ran through water, the slabs breaking off the low edge took the water and the
seabed with them, drawn as stretched blue and black sheets. Now only slabs standing dry break away. The fork version
needs `orbital-mod-api-13`, as 0.5.17 did. [All the changes](docs/CHANGES.md#0518).

The native version is off for now: see [Native version](#native-version-regular-horizon).

## New in 0.5.17

A new laser, **the Earthquake**. No beam: the ground splits open along a fault through the target, a trench of lava
opening down it, and over twenty seconds the land on your side is thrust up into a cliff in lurches while the far side
drops away, trees going over and slabs of the low edge breaking off into the lava. It comes to rest moved for real:
cliffs of banded rock up to about 90 blocks high along the fault, a lava canyon at their foot and scree heaped under
every step. If you stand on your side as it fires, you ride the land up. It's on the wheel's fifth page and
`/orbital earthquake`; on the fork it needs the new release `orbital-mod-api-13`. It isn't in the native version
(`orbital-laser-native-v0.5.17.hnmod`) yet. [More on the Earthquake](docs/LASERS.md#the-earthquake).

**Motion:** the camera jolts at each heave and hard at the climax, and the land you stand on moves under you for about
fifteen seconds.

A second new laser, **the Six Stars**. A wanted level climbs to six stars at the top of your screen, a far siren joining
with each one, while the whole sky turns to a hazy golden-hour sunset and the sun swells. When the sixth lights, the
last star tears out of the screen, turns into a burning star the size of a hill hanging over the target, and falls. It
strikes in a dirty fireball, its five points break off and plough out across the land, and it leaves a five-pointed
star about 340 blocks tip to tip burnt into the ground, lava in its cracks and the forest flattened round it. It's on
the wheel's fifth page and `/orbital sixstars`, and it plays in the native version too.
[More on the Six Stars](docs/LASERS.md#the-six-stars).

**Photosensitivity:** the sun flares on each star, the stars flash, and the impact is a bright flash
(`/orbital impactframes off`, or SOFT on the wheel's FLASHES row, softens them); the camera jolts at the impact.

The native version catches up with the fork. Every laser but the Fold and the Earthquake now plays on regular Horizon:
the Six Stars, the Sky Breaks, the Carpet Bomb, the World Eater and the Convergence included. It's built on a newer Horizon with three
fixes I sent upstream: the sound keeps going through a heavy strike, no frames hang on NVIDIA cards on Linux, and the
Supervolcano no longer drags the world. Big strikes no longer leave whole chunks standing in their craters, and the
strikes' sounds come from the strike and fade with distance as on the fork. The download is now
`orbital-laser-native-v0.5.17.hnmod`. [All the changes](docs/CHANGES.md#0517).

Earlier versions: [docs/CHANGES.md](docs/CHANGES.md).

## Getting started

The fork version, on the Orbital Laser build of Horizon. On Windows or macOS, see [Setup](docs/SETUP.md#fork-version).

1. **Get the Orbital Laser build of Horizon** (`orbital-mod-api-13` or newer). Download
   `horizon-orbital-linux-x86_64.tar.gz` from [Stink-O/horizon releases](https://github.com/Stink-O/horizon/releases),
   unpack it to `~/horizon-orbital` and make Horizon's prepared resources once from your own Minecraft 26.3:

   ```sh
   cd ~/horizon-orbital
   ./horizon-prepare --prepare --server-jar PATH/TO/server.jar
   ./horizon-prepare sounds
   ```

2. **Install the mod.** Download `orbital-laser-v0.5.18.zip` from the
   [latest release](https://github.com/Stink-O/orbital-laser/releases/latest), unzip it, and with the game closed run
   `python3 install.py`.
3. **Play.** From the same folder, run `./play.sh` (a creative test world called OrbitalTest) or `./play.sh MyWorld`
   (back it up first). Always start the game this way: Horizon's own launcher, or a stock `horizon-client`, can't run
   the mod.
4. **In the game,** type `/orbital give` for the Designator.

## Native version (regular Horizon)

Horizon's launcher moved to a new mod format on 18 November 2026 and no longer installs `.hnmod` mods, so Orbital
Laser isn't on its Mods page any more. The last native file, `orbital-laser-native-v0.5.17.hnmod` (every laser but the
Fold and the Earthquake), stays on the [0.5.17 release](https://github.com/Stink-O/orbital-laser/releases/tag/v0.5.17)
for Horizon builds from before the change. For now, play the [fork version](#getting-started).
[More in Setup](docs/SETUP.md#native-version-regular-horizon).

## Set it up with an AI agent

If you use a coding agent (Claude Code, Codex, Cursor and the like), paste it this and it can do the whole setup on
your computer. [AGENTS.md](AGENTS.md) has the same guidance for agents that read the repository themselves.

````text
Set up Orbital Laser on this computer and get one test strike working: https://github.com/Stink-O/orbital-laser

It is a mod for Horizon, the Rust rewrite of Minecraft Java, and it runs on a Horizon fork. Read README.md,
docs/SETUP.md and AGENTS.md in the repository first, and follow them over anything you remember: they name
the fork release, the Minecraft version and the commands for the current release.

Rules:
- Minecraft is not included. Use my own copy of the version the docs name; if I don't have it, stop and tell me.
- Use the fork's build: its download if there is one for my system, and ask before building from source.
- Ask before installing any tool or package. Install the mod with the game closed.
- Strikes wreck the land for good. Use only the throwaway world play.sh makes, test with terrain damage off
  first, and ask me before the first strike with it on.
- Keep any workaround small and tell me what you changed.

Then: install the fork's build and the mod, start the game, give me the Designator, fire one strike with
terrain damage off, check there are no errors in chat, and tell me how to open the wheel, fire and rebind
the keys. If a step fails, show me the command and its message before you try a fix.
````

## How to play

1. Type **`/orbital give`** for the **Orbital Laser Designator**.
2. **Pick a laser.** Press **R** with the designator in hand (or type `/orbital wheel`) and the laser wheel opens. Point
   at a laser to read what it does and click to load it. The arrows either side of the ring, the tabs over it or a
   right-click turn the page. The middle switches terrain damage on or off, and Escape closes the wheel.
3. **Fire.** Hold the designator, aim at a target and **hold right-click** for under a second. The action bar counts
   down, then the strike lands where your crosshair is.
4. **Stop.** Only one strike runs at a time. The wheel's STOP STRIKE button or `/orbital stop` ends it there and then
   (what it has already done to the world stays).

`/orbital terrain off` makes strikes light and sound only. Several lasers have bright flashes or hard cuts over the
whole picture; each laser's photosensitivity note is in [The lasers](docs/LASERS.md), and `/orbital impactframes off`
leaves out the Rod's and the Convergence's impact frames. The wheel's other switches, being caught in the Hurricane,
the Tsunami or the World Eater, and every command: [Playing](docs/PLAYING.md).

## The lasers

Twenty-three lasers, five to a page of the wheel. Each name links to its full description.

| | |
|---|---|
| <img alt="A plasma beam with forked lightning, a shockwave ring and a molten crater" width="240" src="docs/02-impact.jpg"> | **[Plasma](docs/LASERS.md#plasma)**: a raging beam with forked lightning that fuses the crater into glass, obsidian and magma. |
| <img alt="A Godly strike: a pillar of light, six pillars of light round a golden sigil, halo rings and wings in the sky" width="240" src="docs/06-godly.jpg"> | **[Godly](docs/LASERS.md#godly)**: the clouds part, a pillar of light comes down and the crater turns to quartz and gold. |
| | **[Black Hole](docs/LASERS.md#black-hole)**: a singularity opens over the target, tears the ground up into orbit and drags the land into spiral arms. |
| <img alt="The big impact: a fireball tearing open with burning ejecta thrown out every way" width="240" src="docs/09-meteor-impact.jpg"> | **[Meteor Storm](docs/LASERS.md#meteor-storm)**: 72 meteors pound the land round the target, then one the size of a hill hits it. |
| <img alt="A vast dark metal ship lit with green seams hanging over the land, its green beam striking the ground" width="240" src="docs/11-mothership.jpg"> | **[Mothership](docs/LASERS.md#mothership)**: a kilometre-long ship drills a shaft to bedrock and cuts a molten trench with its beam. |
| <img alt="The burning ship ploughing into a mountain, earth flung up along its sides, smoke trailing behind" width="240" src="docs/15-downfall-crash.jpg"> | **[Downfall](docs/LASERS.md#downfall)**: a meteor brings the Mothership down; it buries itself and its black hole engine swallows the wreck. |
| <img alt="The Planet Killer's towers on the horizon striking the ring of light in the sky with bolts of lightning" width="240" src="docs/17-planet-killer-lightning.jpg"> | **[Planet Killer](docs/LASERS.md#planet-killer)**: seven towers strike a ring in the sky, and its beam leaves a crater 480 blocks across. |
| <img alt="Prism beams and an aurora over the crystal spires as they resonate" width="240" src="docs/22-crystal-bloom-prism.jpg"> | **[Crystal Bloom](docs/LASERS.md#crystal-bloom)**: crystal spires burst out of the land and shatter, leaving a geode crater. |
| <img alt="The finished pit, waterfalls pouring over its rim into the dark" width="240" src="docs/28-sinkhole-aftermath.jpg"> | **[Sinkhole](docs/LASERS.md#sinkhole)**: the land caves in, slab by slab, into a pit about 225 blocks across and down to bedrock. |
| <img alt="The column of smoke rising out of the crater, the bomb's trail still hanging in the sky" width="240" src="docs/32-payload-column.jpg"> | **[Payload](docs/LASERS.md#payload)**: a fireball comes down from orbit on one long arc and leaves a bomb crater. |
| <img alt="The mushroom cloud towering over its crater" width="240" src="docs/35-nuke-cloud.jpg"> | **[Nuke](docs/LASERS.md#nuke)**: a bomb from orbit bursts into a mushroom cloud and flattens the land out to about 230 blocks. |
| <img alt="The radiant burst as it strikes, rays fanning out over the land" width="240" src="docs/39-rod-burst.jpg"> | **[Rod from God](docs/LASERS.md#rod-from-god)**: a colossal rod dropped from orbit, left standing in a crater lined in white and gold. |
| <img alt="The final strike hitting the target, the land round it lit up" width="240" src="docs/43-supercell-strike.jpg"> | **[Supercell](docs/LASERS.md#supercell)**: a storm called down, lightning all over the land, then one colossal strike. |
| <img alt="The hurricane's eyewall towering over the land, lightning in it and debris whirling round" width="240" src="docs/branding/hurricane-card.jpg"> | **[Hurricane](docs/LASERS.md#hurricane)**: a hurricane some 3,500 blocks across tears up the land round its eye and carries you round with it. |
| <img alt="The wall close to, nearly black, long streaks of foam drawn up its face and a boiling brown foot on the land" width="240" src="docs/46-tsunami-wall.jpg"> | **[Tsunami](docs/LASERS.md#tsunami)**: a wall of water 320 blocks high comes in over the land and rolls over you. |
| <img alt="The whole world on the walls of a tube, a hole of stars in its roof" width="240" src="docs/50-fold-tube.jpg"> | **[The Fold](docs/LASERS.md#the-fold)** (fork only): a drop of liquid metal goes into the land and folds the world up round you. |
| <img alt="The column at sunset, lightning down through it and plates of crust hanging in the air" width="240" src="docs/55-supervolcano-column.jpg"> | **[Supervolcano](docs/LASERS.md#supervolcano)**: the land erupts and falls into a caldera about 560 across. |
| <img alt="A huge eye looking through the black hole in the cracked sky, broken panes round it, one falling" width="240" src="docs/59-skybreak-eye.jpg"> | **[The Sky Breaks](docs/LASERS.md#the-sky-breaks)**: a fist punches through the sky, an eye looks through, and panes of sky fall into the land. |
| <img alt="The blasts walking in across the land" width="240" src="docs/64-carpetbomb-run.jpg"> | **[The Carpet Bomb](docs/LASERS.md#the-carpet-bomb)**: a bomber walks a line of thirteen blasts across the land towards you. |
| <img alt="The worm's body arched over the jungle, diving back into the land" width="240" src="docs/68-worldeater-arch.jpg"> | **[The World Eater](docs/LASERS.md#the-world-eater)**: a worm the size of a mountain bursts out of the land and comes after you. |
| <img alt="The column of fire and the column of light meeting in the air over the target" width="240" src="docs/73-convergence-clash.jpg"> | **[The Convergence](docs/LASERS.md#the-convergence)**: the Nether and the Aether fight over the target and tear the land in two. |
| <img alt="The land torn open along the fault, one side thrust up into a cliff over a trench of lava" width="240" src="docs/78-earthquake-cliff.jpg"> | **[The Earthquake](docs/LASERS.md#the-earthquake)** (fork only): the land splits along a fault and your side is thrust up into a cliff over a canyon of lava. |
| <img alt="A five-pointed star burnt into the land, lava in its cracks, the forest flattened round it" width="240" src="docs/80-sixstars-crater.jpg"> | **[The Six Stars](docs/LASERS.md#the-six-stars)**: a wanted level climbs to six stars, the last one tears out of the screen as a burning star the size of a hill and lands, leaving a star burnt into the land. |
| <img alt="A kneeling stone statue of a giant over a terraced crater, more statues behind it" width="240" src="docs/87-colossi-statues.jpg"> | **[The Colossi](docs/LASERS.md#the-colossi)**: five stone giants rise in a ring, hammer the land until it blows, and are left kneeling as stone statues round the crater. |

## If something goes wrong

- **No wheel, no `/orbital` command, or Options → Mods says *capability world is for server mods*.** That's stock
  Horizon or an older fork build: start the game with `./play.sh` on `orbital-mod-api-13` or newer. On
  **Options → Mods**, Orbital Laser's row says why if it stopped.
- **`NO TARGET IN RANGE`.** You're aiming at the sky, too far, or at unloaded chunks.
- **The designator only clicks.** A strike is already under way; wait for it, or end it with `/orbital stop`.

The rest, and the known gaps (performance, macOS, single player): [Troubleshooting](docs/TROUBLESHOOTING.md). To build
the mod from source or change it, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Support it

Orbital Laser is free and always will be. If you've enjoyed it and want more strikes, you can buy me a coffee on
[Ko-fi](https://ko-fi.com/stinkoh). It goes straight into the hours behind the next one.

## Credits and licence

Orbital Laser is under the MIT License (`LICENSE`). Third-party notes are in `NOTICE`. It is built on
[Horizon](https://github.com/horizon-rust/horizon) by Ludovic and contributors (MIT), and the Orbital Laser build of Horizon
is a fork of it.

**The Colossi's giants and hammer** were made in [Tripo](https://www.tripo3d.ai) and turned into blocks with
[model2mc](https://github.com/Stink-O/model2mc); that laser was sponsored by Tripo.

**Java Edition port:** [@Ramingen](https://github.com/Ramingen) is porting Orbital Laser to Minecraft Java Edition,
starting with Fabric ([#6](https://github.com/Stink-O/orbital-laser/pull/6)), with NeoForge and Forge to follow. The work
lives on the [`java` branch](https://github.com/Stink-O/orbital-laser/tree/java) until it's done.

Minecraft is a trademark and work of Mojang Studios and Microsoft. Orbital Laser is an independent fan project, not made
by or affiliated with Mojang, Microsoft or Horizon's author, and it contains none of their code, textures or sounds. You
need your own copy of Minecraft.
