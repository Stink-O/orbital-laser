# Troubleshooting

What to do if the mod doesn't start or a strike doesn't fire, and the known gaps. Setup is in [SETUP.md](SETUP.md).

## If something goes wrong

- **Options → Mods says `orbital — Can't be read: horizon-mod.toml: capability world is for server mods`.** That's
  stock Horizon, not the Orbital Laser build: the mod is installed fine, but stock Horizon can't run it. Quit, and
  start the game with `./play.sh` from a terminal (it finds the build in `~/horizon-orbital`, or tells you how to get
  it).
- **No wheel, no `/orbital` command, or the items do nothing.** You're running stock Horizon, an older fork build, or
  one built without `--features mods` (the log says *this build has no mod runtime*). Start the game with `./play.sh`
  on `orbital-mod-api-13` or newer. On **Options → Mods**, Orbital Laser's row says why if it stopped.
- **`play.sh` can't find the build or the resources, or says the build isn't the Orbital Laser one.** Set
  `HORIZON_ORBITAL` to the folder with the build's `horizon-client` and `horizon-ctl`, and `HORIZON_RESOURCES` to the
  prepared resources. Double-clicking `play.sh` in a file manager may show nothing: run it from a terminal to see its
  messages (or read `play-error.txt` beside it).
- **R does nothing.** Something else may use R: check **Options → Controls → Key Binds** (a clash is shown in yellow)
  and rebind it (on a native build, on **Options → Mods → Orbital Laser → Settings**). R only opens the wheel while you play with the designator in hand, not over another screen. With
  anything else in hand it does nothing (`/orbital wheel` opens the wheel either way).
- **`NO TARGET IN RANGE`.** You're aiming at the sky, too far, or at unloaded chunks. Past your render distance only
  the Mothership, the Downfall, the Planet Killer, the Crystal Bloom, the Sinkhole, the Payload, the Nuke, the Rod, the Supercell, the Hurricane, the Tsunami, the Fold, the Supervolcano, the Sky Breaks, the Carpet Bomb, the World Eater and the Convergence can aim, and only with
  **LOD Distance** on in Video Settings.
- **The designator only clicks.** A strike is already under way, and one runs at a time. Wait for it to finish, or end
  it with the wheel's STOP STRIKE or `/orbital stop`.
- **`horizon-prepare --prepare` says your `26.3.json` is *a 26.3 version file Horizon does not know yet*.** Your copy is fine:
  Mojang republished it. The fork's builds from `orbital-mod-api-9` on know the republished files; if Mojang republishes
  again, copy [upstream Horizon's `research-lock.json`](https://github.com/horizon-rust/horizon/blob/main/research-lock.json)
  over the one at the top of the fork's folder (it's read as `horizon-prepare` runs: nothing to rebuild) and run it again.
- **No sound.** Check the in-game master volume (Music & Sounds) and your system volume for the game.
- **The shaft fills with water, or ends in obsidian.** It hit groundwater, and the lava at the bottom met it.

## Known gaps

- **The fork version needs a Horizon fork**. Its ready-built download is for Linux x86-64, with a Windows test build that hasn't been run on real Windows yet. The native version runs on regular Horizon.
- **QUALITY FULL is heavy during the Supervolcano**: about 50 ms a frame at 1080p, against about 17 ms on FAST (the default).
- **The World Eater is the heaviest laser.** At 2560x1440 on QUALITY FAST (an RTX 4070 SUPER) the game's frame takes
  about 5 ms of GPU time for most of a hunt, 17 to 26 ms through the breach and the hops and 9 to 19 ms while you ride inside, with whole frames spiking to 20 to 60 ms round the breach, the swallow and the spit (the slowest half second about 41 fps); the scripted show seen from 250 blocks off tops out at about 13 ms of GPU time. QUALITY PERFORMANCE (`/orbital quality performance`) draws it at its lightest.
- **The first time the World Eater is picked, the game freezes while its effects are built**: about half a minute to a minute and a half on the fork
  build `orbital-mod-api-12`, behind the wheel's LOADING. After that it's instant, until a driver update or a new
  version of the mod.
- **The World Eater's neck shows stacked discs** as its head turns to look at you: the rings behind the head fan out
  into a stack instead of bending smoothly.
- **On the fork version, picking a laser can stop the game for a moment** while its effects are built (up to a few seconds
  the first time, behind the wheel's LOADING). The native version builds them in the background.
- **On the fork version, a strike's sounds can run on over the title screen** after Save and Quit to Title, until they end: the game doesn't stop them. It needs a fix in Horizon itself.
- **Tested on Linux.** Reported working on Windows 11 by a user (the fork built from source, `--features mods`).
- **macOS (Apple Silicon): the Downfall's effects may not draw.** Apple's Metal shader compiler fails on its effects
  (`XPC_ERROR_CONNECTION_INTERRUPTED` in `Device::create_render_pipeline`), and the Nuke's can when it's the laser
  loaded as the game starts. The other lasers work. The fork's builds from `orbital-mod-api-9` on (so the
  `orbital-mod-api-13` this release needs) stop the crash: a pass the driver can't build is skipped and tried again
  later, so on those Macs the Downfall's strike may run without its visuals. The mod builds a laser's effects only once
  you're playing, and if the game closed while it built them, the next start loads the Plasma instead and says so in chat.
- **Single player** (or hosting LAN). The world changes need a world the game itself runs, and the effects are drawn
  only for the player who fired.
- **Terrain damage can't be undone.** Back up the world, or switch terrain damage off.
- **Targets must be in loaded chunks.** The seventeen long-range lasers reach 1000 blocks across the distant terrain, where
  the aim follows the coarser distant heights, and a crater only shows there once those chunks load.

To build the mod from source or change it, see [CONTRIBUTING.md](../CONTRIBUTING.md).
