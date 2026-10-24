# Contributing to Orbital Laser

Thanks for looking. Orbital Laser is a small project made by one person. It works, and it is rough in places. Help of
any size is welcome: a bug report, a test on your PC, a fix, or taking over a whole idea.

## Where to talk

- **[Discussions](https://github.com/Stink-O/orbital-laser/discussions):** questions, ideas, and "I'd like to work on X".
- **[Issues](https://github.com/Stink-O/orbital-laser/issues):** bugs and concrete tasks. Say on the issue that you're
  taking one, so two people don't do the same work.
- **Pull requests:** welcome, including small ones and drafts.

## What needs doing most

- **Getting the mod capabilities into Horizon.** The mod runs on a fork that adds `input`, `ui`, `render` and `world`
  ([Stink-O/horizon](https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world)). Help shaping them into
  something Horizon would take upstream is the most useful work there is.
- **Windows and macOS.** Everything was built and tested on one Linux PC. The fork needs building and testing on the
  other systems, and the shader needs a look on other GPUs and drivers.
- **Multiplayer.** The world changes run as server commands in a world the game itself runs, and the effects are drawn
  only for the player who fired. Server mods and a `net` channel in Horizon would let a strike be seen by everyone.
- **Undo.** Terrain damage is permanent. A snapshot-and-restore of the blasted region would make it much safer to use.
- **More lasers.** A laser is an entry in `mod/src/lasers.rs`, a branch in `mod/shaders/strike.wgsl`, what it leaves
  behind in `mod/src/strike.rs`, sounds in `tools/sounds_themes.py` and an icon in `tools/make_item_textures.py`.
- **Shader cost.** It's one full-screen pass with a lot of noise in it, Plasma traces a volume, and the Black Hole
  marches rays through its gravity and tests 160 pieces of debris per pixel. Cheaper versions that
  look the same would help lower-end GPUs.

## How it fits together

- **`mod/`** is the mod: Rust for WebAssembly (`src/lib.rs` the hooks, the designator and the strike's playback;
  `src/lasers.rs` the lasers; `src/strike.rs` a strike's plan of commands and sounds; `src/wheel.rs` the laser wheel),
  its post pass (`shaders/strike.wgsl`) and its manifest.
- **`orbital-laser-mod/`** holds the mod's content: the items, their models, textures and names. **`orbital-sounds/`**
  holds the sounds. `tools/build_mod.py` puts the code and both into one mod folder, `dist/orbital`.
- **`install.py`** installs that folder into Horizon's game folder; **`play.sh`** starts the Orbital Laser build of
  Horizon on it.
- **Stock Horizon:** `orbital-laser-shader/` (the same effects as a shader pack), `strike.py` and `themes.py` (the driver
  that runs a strike from outside the game) are 0.1's setup, kept for stock Horizon (`install.py --legacy`).
- **`tools/`** has the sound generator, the texture and logo generators, the shader validator and the video recorder.

## Testing a change

- **Shader:** validate it against Horizon's prelude: `cat tools/wgslcheck/prelude.wgsl mod/shaders/strike.wgsl > /tmp/s.wgsl`
  and run `tools/wgslcheck/target/release/wgslcheck /tmp/s.wgsl`; it must print `OK`. In the game a broken pass is
  skipped and the reason logged.
- **Mod:** `python3 tools/build_mod.py --install ~/.local/share/horizon`, then `./play.sh` in a throwaway world. Switch
  terrain damage off (`/orbital terrain off`) for the first strike, then check a full strike: the chat stays empty, the
  shaft reaches bedrock, and a second strike right after looks the same as the first.
- **Sounds:** regenerate with `python3 tools/synth_sounds.py`, rebuild the mod, and listen to all of them at the volume
  you'd actually play at.

## Rules

- **No Minecraft assets and no decompiled code.** Nothing from the game goes in this repository.
- **Sounds and art must be original or properly licensed**, and any third-party material goes in `NOTICE`.
- **Keep it quiet and keep it safe.** Nothing a strike does may appear in chat, and nothing should destroy more than the
  strike is documented to.
