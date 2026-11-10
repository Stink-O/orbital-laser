# Orbital Laser 0.5.14 on native Horizon: install

Orbital Laser 0.5.14 as a native mod of upstream Horizon: no fork and no WebAssembly. The launcher compiles it into
the game. Its code runs with full access to your computer, like any native mod, so only install it if you trust it.

## What you need

- The Horizon launcher, 0.2.37 or newer ([playhorizon.dev](https://playhorizon.dev)), and a Horizon instance of its
  own (not the Orbital Laser build's game folder). Any installed release or Nightly will do: the mod is pinned to
  upstream Horizon `89f236e3ef8e8b554bef507216b86ca90b552213`, and the launcher builds it on that commit.
- The first native build downloads the launcher's own Rust (1.99.1) and takes 20 to 30 minutes. Later builds are
  quicker. You don't need Rust installed yourself.

### Per system

| System | What to install first | Status |
| --- | --- | --- |
| **Linux** (x86-64) | A C compiler, `pkg-config`, and the ALSA and libudev development files. Debian, Ubuntu, Mint: `sudo apt install build-essential pkg-config libasound2-dev libudev-dev`. Fedora: `sudo dnf install gcc pkgconf-pkg-config alsa-lib-devel systemd-devel`. Arch: `sudo pacman -S --needed base-devel alsa-lib systemd-libs`. The launcher checks for these and gives the command for your distribution. SteamOS can't build native mods yet. | **Tested**: built and played. |
| **Windows** (x64) | Nothing: the launcher brings its own Rust and MinGW-w64 (no Visual Studio needed). | **Build-checked only**: the code type-checks for Windows and every post pass translates for DX12 and Vulkan; not yet run on Windows. |
| **macOS** (Apple Silicon) | Apple's Command Line Tools: `xcode-select --install` in Terminal (the launcher asks for them). | **Build-checked only**: the code type-checks for macOS and every post pass translates for Metal; not yet run on a Mac. The Downfall's effects don't draw on Macs (see Known issues). |
| **macOS** (Intel) | Not available: the launcher has no Rust toolchain for Intel Macs, so it can't build native mods there. | Not supported. |

## The file

`orbital.hnmod`: the native code and the content (items, models, textures, sounds) in one file. It goes in the
instance's `horizon-native-mods/`. The launcher builds its code into the game, and the game reads its content from the
same file.

**Coming from an earlier native test build?** Delete `orbital_laser.hnmod` from `horizon-native-mods/`, and
`orbital-*.hmod` and `orbital-laser-native-*.hmod` from `horizon-mods/`. The new `orbital.hnmod` replaces them all, and
the old ones build or load beside it.

## Steps

1. Close the game.
2. Copy `orbital.hnmod` into the instance's `horizon-native-mods/` folder (make it if it isn't there). Or install
   **Orbital Laser** from the launcher's Mods page, which puts it there for you. The Instances page's **Open folder** opens
   the instance's folder; `horizon-launcher instance list` prints it.
3. Turn it on in the Mods page (or check that `orbital` is on in the instance's `horizon-mods.txt`). On the
   **Native build** row pick **Release build** (`horizon-launcher settings native-profile release`): it builds more
   slowly, but the game runs noticeably faster than with the default Performance build.
4. **The trust step (yours to run).** In the Mods page, the **Native build of {instance}** row shows **Not built** or
   **Needs rebuild**. Press **Build**, read the red warning naming `orbital 0.5.14`, and choose
   **I trust these mods: build**. From a terminal, the same step is:

   ```bash
   horizon-launcher native-build --instance "<instance>" --trust-native-code
   ```

   With no folder given, it builds the native mods turned on in the instance. (**Build anyway** only comes up when
   other native mods pin a different Horizon than this one builds on.)
5. Wait for the build. The row shows each step, and a failed build shows its error and keeps a build log.
6. Play the instance. It now runs "native-…, built on Horizon …". In a world: `/orbital give`, then hold the
   Designator and press R for the laser wheel (or `/orbital wheel`).

## Checking it worked

- Options > Mods lists Orbital Laser 0.5.14.
- `/orbital` answers in chat, is white once typed and completes with Tab, and the wheel opens with R while you hold
  the Designator.
- Fire one strike with terrain off first (`/orbital terrain off`). Strikes with terrain on are permanent, so only
  fire those in a throwaway world.

## Known issues

- **On Macs the Downfall's effects don't draw.** Apple's Metal compiler fails on its pass (the same on the Orbital
  Laser build of Horizon, [#3](https://github.com/Stink-O/orbital-laser/issues/3)): you get its land and sound, not its
  visuals. The Crystal Bloom and the Planet Killer are the next biggest passes, so the likeliest to follow.
- **Multiplayer and LAN aren't tested** on the native build; it's made for single player. On a server, a strike's world
  changes need operator level 4, and the server needs the mod too.
- **Each new version rebuilds the game.** Installing an update means another native build: 20 to 30 minutes the first
  time, quicker after that.
- Tested on Linux; Windows and macOS on Apple Silicon are build-checked only (see the table above).

## Removing it

Remove `orbital.hnmod`, or turn the mod off, then rebuild (or switch the instance back to a plain Nightly).
