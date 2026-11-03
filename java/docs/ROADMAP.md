# Roadmap

What is missing, in a sensible order. "Done" means parity with the Horizon version (see
[PARITY-CHECKLIST.md](PARITY-CHECKLIST.md)). The goal is one Orbital Laser on every modern Java loader from one
shared codebase; see [../../JAVA-BRANCH.md](../../JAVA-BRANCH.md).

## 1. Finish the Fabric port

In rough order of value for effort:

1. **Check what is marked "check"** in the checklist (Distant Horizons, the registry content, the shader jolt).
2. **Wheel parity.** Add what the Rust wheel has: fly speed, seed and lock seed, knockback, follow, messages, panel,
   quality, a STOP STRIKE button, an impact-FX row, and pages for the extra lasers. The commands already exist for several.
   Keep it a simple Minecraft screen unless the ring is wanted.
3. **Settings kept between sessions** (the Rust mod saves them to a file): save `Settings` per player.
4. **The Nuke's and the Rod's knockback** and the **follow camera.**
5. **Shaders for Downfall, Planet Killer, Crystal Bloom and Sinkhole.** Run `tools/build_shader.py` on each pass, fix
   what the OpenGL 3.3 path rejects, and check in the game. Expect more patches than the first three took; the
   Sinkhole also needs the land's columns (its pass reads a table of them).
6. **Rod from God and Supercell** (new in 0.5.7): plans, passes, sounds, items' registry content, commands.
   The Rod also has impact frames.
7. **QUALITY FAST** (half-size smoke): the original's `fs_half` and `fs_join` stages are a second pass at half size
   and a join; this needs a second pipeline and an intermediate target.
8. **Bigger world changes done properly.** The simplified plans (Payload, Nuke, Planet Killer, Crystal Bloom, Sinkhole)
   use commands. A direct chunk write (a server-side block-edit helper) would bring back the original's sizes without
   hitching the tick. Measure first (the Rust mod's `nk_wave_profile` shows how much a wave costs per tick).
9. **Paced edits:** the Rust mod waits while frames are slow (`pace.rs`). The Java budget is fixed.
10. **Multiplayer:** the effects draw only for the player who fired. Sending a strike's announcement to everyone near
    it would show it to all; the world changes already run on the server.
11. **Test on other systems:** Linux, macOS, AMD and Intel GPUs, Distant Horizons.

## 2. Reorganise for several loaders

When Fabric reaches parity, move the shared game logic (plans, timings, settings, strike playback, sounds, the shader
tables) to a common module with a thin layer per loader. Fabric, Quilt (it loads most Fabric mods already), NeoForge and
Forge each need their own entrypoints, registration, networking and a way to draw the post pass. Architectury or a
MultiLoader-style Gradle setup are the options named in [../../JAVA-BRANCH.md](../../JAVA-BRANCH.md). Not started; don't
begin before the Fabric port is close to done, or each loader inherits the gaps.

Things that differ per loader and need care: how a screen pass is hooked in (the Iris-compatible draw is a Fabric mixin
today), how packets are registered, and how the game's items and sounds are registered.

## 3. Keeping up with the Horizon version

New lasers and fixes land on `main`, which is merged into `java` after each release. After a merge, read what changed
in `mod/src` and `mod/shaders`, add a row for each new feature to the checklist, and port from there.
