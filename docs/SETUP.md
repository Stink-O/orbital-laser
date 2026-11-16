# Setting up Orbital Laser

The [README](../README.md) has the short version. This page has every step and option for both versions.

**Contents:** [Two ways to play](#two-ways-to-play) · [Native version](#native-version-regular-horizon) ·
[Fork version](#fork-version) · [Set it up with an AI agent](#set-it-up-with-an-ai-agent)

## Two ways to play

The [native version](#native-version-regular-horizon) runs on regular Horizon: install it from
the launcher's Mods page and the launcher compiles it into the game. The [fork version](#fork-version) is a WebAssembly mod for the Orbital Laser build of
Horizon ([Stink-O/horizon](https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world), release
`orbital-mod-api-12` or newer), with a ready-built Linux download on its
[releases](https://github.com/Stink-O/horizon/releases). Either way you need your own copy of Minecraft Java
Edition 26.3: nothing from Minecraft is in this repository or the downloads.

**Not in the native version yet: the Fold, the Sky Breaks, the Carpet Bomb, the World Eater and the Convergence.**
They aren't playable in the native file, `orbital.hnmod` (what the launcher's Mods page installs): the first three show
greyed out in the wheel, saying "On the fork now, native soon", and the World Eater and the Convergence aren't in it
yet. To play them now, use the fork version, `orbital-laser-v0.5.16.zip`, on the Orbital Laser build of Horizon ([Fork version](#fork-version)).
Every other laser plays on both.

**A reliable native version is waiting on upstream Horizon.** I can't release a native build I'd call reliable until
Horizon merges the fixes I've sent it: the sound stopping during a heavy strike
([#15875](https://github.com/horizon-rust/horizon/pull/15875)) and frames hanging on NVIDIA cards on Linux
([#13885](https://github.com/horizon-rust/horizon/pull/13885)) are still open. Until they're in, new lasers come to
the fork first.

## Native version (regular Horizon)

**You need:** the [Horizon launcher](https://playhorizon.dev) (0.2.37 or newer) with an instance set up from your own
Minecraft Java Edition 26.3, and on Linux a C compiler, `pkg-config` and the ALSA and libudev development files (the
launcher tells you the command if any are missing). Windows needs nothing extra. On a Mac with Apple Silicon run
`xcode-select --install` first; Intel Macs can't build native mods.

1. **Close the game.**
2. In the launcher, open the **Mods** page, search **orbital** and press **Install** on Orbital Laser.
3. On the **Native build** row, pick **Release build**.
4. Press **Build** and choose **I trust these mods: build**. The first build takes 20 to 30 minutes; later ones are
   quicker.
5. Press **Play**, open a creative world and type **`/orbital give`**.
6. Hold the Designator and press **R** to pick a laser, then hold right-click on a target to fire. Type
   **`/orbital terrain off`** first if you don't want the land wrecked.

**Not in this version yet:** the Fold, the Sky Breaks and the Carpet Bomb show greyed out in the native wheel, and the
World Eater and the Convergence aren't in it yet. They're in the [fork version](#fork-version) for now.

**To update:** when the **Mods** page offers a newer Orbital Laser, install it, then **Build** again (step 4).

**To install the file by hand** (for a version that isn't on the Mods page yet):

1. Download **`orbital.hnmod`** from the [latest release](https://github.com/Stink-O/orbital-laser/releases/latest).
2. On the **Instances** page, press **Open folder** on your instance. (A new instance's folder is in
   `instances/<its name>` inside Horizon's data folder, not in the data folder itself.)
3. Put `orbital.hnmod` in its **`horizon-native-mods`** folder. Make the folder if it isn't there yet: it only
   appears once a native mod has been installed.
4. On the **Mods** page, check Orbital Laser is on, then carry on from step 3 above.

> [!CAUTION]
> A native mod isn't sandboxed: its code is built into the game and runs with full access to your computer, so only
> build it if you trust it. It's played and tested on Linux; on Windows and Apple Silicon it builds but hasn't been
> played yet. The [install guide](https://github.com/Stink-O/orbital-laser/releases/latest/download/INSTALL.md) has the
> known issues and how to remove it.

## Fork version

1. **Get the Orbital Laser build of Horizon** (`orbital-mod-api-12` or newer). Download
   `horizon-orbital-linux-x86_64.tar.gz` from [Stink-O/horizon releases](https://github.com/Stink-O/horizon/releases)
   and unpack it to `~/horizon-orbital`.

   **On Windows**, try the test build: download `orbital-laser-windows-test.zip` from the
   [latest release](https://github.com/Stink-O/orbital-laser/releases/latest) and follow its `README-WINDOWS.txt`. The game and the mod are both in it,
   so skip the steps below. It has only been run under Wine, never on real Windows, so please report how it goes.

   **On macOS**, or to build Windows yourself, build it from source instead: branch `mod-api-input-ui-render-world` of
   [Stink-O/horizon](https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world), with the mod runtime
   switched on:

   ```sh
   cargo build --release -p horizon-client --features mods
   ```

   Without `--features mods` the mod only half-loads: its items are there, but `/orbital` is an unknown command, and
   the game's log says `1 mod(s) not started: this build has no mod runtime (build with --features mods)`.

   It needs Horizon's prepared resources, made once from your own Minecraft 26.3 (Horizon's
   [PLAY.txt](https://github.com/horizon-rust/horizon) explains the server jar and Java 25):

   ```sh
   cd ~/horizon-orbital
   ./horizon-prepare --prepare --server-jar PATH/TO/server.jar
   ./horizon-prepare sounds
   ```

   If you already have Horizon set up, skip that and point `HORIZON_RESOURCES` at its prepared resources (the folder
   `.local/horizon-client/26.3` inside it).

2. **Install the mod.** Download `orbital-laser-v0.5.16.zip` from the
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

If you use a coding agent (Claude Code, Codex, Cursor and the like), it can do the whole setup on your computer: paste
it the message in the [README](../README.md#set-it-up-with-an-ai-agent).

