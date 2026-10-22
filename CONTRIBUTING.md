# Contributing to Orbital Laser

Thanks for looking. Orbital Laser is a small project made by one person. It works, and it is rough in places. Help of
any size is welcome: a bug report, a test on your PC, a fix, or taking over a whole idea.

## Where to talk

- **[Discussions](https://github.com/Stink-O/orbital-laser/discussions):** questions, ideas, and "I'd like to work on X".
- **[Issues](https://github.com/Stink-O/orbital-laser/issues):** bugs and concrete tasks. Say on the issue that you're
  taking one, so two people don't do the same work.
- **Pull requests:** welcome, including small ones and drafts.

## What needs doing most

- **A real item.** The designator is a renamed spyglass that a script watches for. Horizon's content-mod API
  (`registries`, API 0.2) is meant to add real items and blocks, but I couldn't get one to load. If you can, a proper
  Orbital Laser Designator item (and a trigger that doesn't need `strike.py`) is the best upgrade there is.
- **Windows and macOS.** Everything was built and tested on one Linux PC. `strike.py` needs path handling for the other
  systems, and the shader needs a look on other GPUs and drivers.
- **Survival and multiplayer.** It needs cheats and runs against one local game. Once Horizon has server mods, the
  strike could run where the world is simulated.
- **Undo.** Terrain damage is permanent. A snapshot-and-restore of the blasted region would make it much safer to use.
- **Sound design.** Every sound is synthesized (`tools/synth_sounds.py`). Better or more convincing sounds are welcome,
  as long as they are original or properly licensed.
- **Shader cost.** It's one full-screen pass with a lot of noise in it. Cheaper versions of the beam, smoke and lightning
  that look the same would help lower-end GPUs.

## How it fits together

- **`orbital-laser-shader/`** is a Horizon shader pack: one WGSL `composite` stage (`shaders/strike.wgsl`) and its
  `pack.toml`. It owns the whole picture: reticle, beam, lightning, shockwaves, crater glow, smoke, camera shake.
- **`orbital-sounds/`** is a resource pack with eight `.ogg` sounds and a `sounds.json`.
- **`strike.py`** is the driver. It finds where you're aiming, rewrites the installed `pack.toml` to aim and restart the
  shader, and in time with the shader's clock sends the `/fill`, `/kill`, `/particle` and `/playsound` commands through
  `horizon-ctl`.
- **`install.py`** copies (or symlinks) the two packs into Horizon's game folder.
- **`tools/`** has the offline shader validator (`check-shader.sh`), the sound generator, a screenshot helper that
  recovers the real colours, and the logo generator.

## Testing a change

- **Shader:** `tools/check-shader.sh` must print `OK`. It validates the file against Horizon's prelude and substitutes the
  option values, which reproduces errors the game only reports as "Pipeline constant error". For anything visual, take a
  screenshot with `tools/capture.py` at a few moments of the strike (about 2.9 s, 6.3 s and 17 s are good ones).
- **Driver:** run `python3 strike.py --no-terrain --no-sound` first, then a full strike in a throwaway world, and check
  that the chat stayed empty and that the shaft reaches bedrock.
- **Sounds:** regenerate with `python3 tools/synth_sounds.py`, reload resources in game (F3 + T), and listen to all
  eight at the volume you'd actually play at.

## Rules

- **No Minecraft assets and no decompiled code.** Nothing from the game goes in this repository.
- **Sounds and art must be original or properly licensed**, and any third-party material goes in `NOTICE`.
- **Keep it quiet and keep it safe.** Nothing a strike does may appear in chat, and nothing should destroy more than the
  strike is documented to.
