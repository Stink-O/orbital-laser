# Notes for AI agents

You've been asked to set up or work on **Orbital Laser**, a shader pack, a sound pack and a Python driver for
[Horizon](https://github.com/ludovic111/horizon) (the Rust rewrite of Minecraft Java). The README is the user-facing
guide and the full copy-paste setup prompt is in [README.md](README.md#set-it-up-with-an-ai-agent). This file is the
short, factual version for you.

## Ground rules

- **A strike is destructive and permanent.** It carves a ~20-block crater and a shaft to bedrock and kills every mob and
  dropped item within 40 blocks (not players). Only ever fire it in a throwaway world, and ask the user before the first
  strike that changes terrain. `--no-terrain` is the safe mode (visuals and sound only).
- **Horizon and Minecraft are not part of this repo.** Don't download, bundle, fake or work around them. If Horizon isn't
  installed, tell the user where to get it and stop.
- **Tested on Linux only.** On Windows and macOS keep fixes small and tell the user what you changed.
- Don't touch Horizon's files, the user's saves or their settings beyond what `install.py` does.

## Commands

```sh
python3 strike.py --doctor          # checks the whole setup and says how to fix each [FAIL]; changes nothing
python3 install.py --enable         # copy both packs in, select the shader pack, enable the sound pack (game must be CLOSED)
python3 install.py                  # copy only; then pick the packs in the game's menus
horizon-ctl launch --world NAME --creative --wait     # start a throwaway creative world with the control socket
python3 strike.py --daemon          # the spyglass designator: hold 9, right-click and hold, aim, keep holding ~1 s
python3 strike.py --no-terrain --no-sound             # one safe test strike at the block under the crosshair
python3 strike.py --at X Y Z        # one strike at a surface block
tools/check-shader.sh               # validate the shader like Horizon does; prints the real error or OK
```

Finding things: `--ctl PATH` / `HORIZON_CTL` for `horizon-ctl` (it ships in Horizon's own folder), `--home PATH` /
`HORIZON_HOME` for Horizon's game folder (the one holding `options.txt` and `saves/`; `horizon-ctl launch` prints it as
`home`). Default game folders: Linux `~/.local/share/horizon`, macOS `~/Library/Application Support/horizon`,
Windows `%APPDATA%\horizon`. Only the Linux one has been seen to be right.

## Layout

- `orbital-laser-shader/`: the Horizon shader pack (`pack.toml` plus one WGSL `composite` stage in `shaders/strike.wgsl`).
- `orbital-sounds/`: the resource pack with eight `.ogg` sounds.
- `strike.py`: the driver (aims the shader by rewriting the installed `pack.toml`, sends vanilla commands through
  `horizon-ctl` in step with the shader's clock). `install.py`: the installer. `tools/`: validator, sound generator,
  screenshot helper, logo generator.

## Things that will bite you

- **Floats in `pack.toml`.** Option values must be written as floats (`13.0`, not `13`) or the pack fails to load.
- **A shader error shows only as "Pipeline constant error … Entry point fs_main is invalid".** Run `tools/check-shader.sh`
  for the real message. Don't build a vector from override constants inside the entry point
  (`vec3<f32>(target_x, target_y, target_z)`): use a helper function, as `target_pos()` does.
- **Spectator mode can't hold items**, so the designator won't work there. `horizon-ctl command "gamemode creative"`.
- **Command feedback.** The daemon turns `minecraft:send_command_feedback` off for its whole lifetime and restores it
  when it exits. If a run is killed hard it can stay off: `horizon-ctl command "gamerule minecraft:send_command_feedback true"`.
- **`horizon-ctl screenshot` loses colour** (it destroys most of the blue channel). Use `tools/capture.py` for real colours.
- **Both `strike.py --daemon` and `tools/capture.py` rewrite `pack.toml`**: don't run them at the same time.
- **Silent game?** Check the in-game master volume, the OS volume for the game's own stream, and that the `orbital-sounds`
  resource pack is enabled (reload resources with F3 + T after changing it).

## Verifying work

A change to the shader: `tools/check-shader.sh` must print `OK`, and look at a screenshot from `tools/capture.py`.
A change to the driver: run `--no-terrain --no-sound` first, then a full strike in a throwaway world, and check the chat
stayed empty and the shaft reaches bedrock. See [CONTRIBUTING.md](CONTRIBUTING.md).
