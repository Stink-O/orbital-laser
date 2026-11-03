# Design: how the Java port is built, and why

The Horizon version of Orbital Laser is a WebAssembly mod that calls Horizon's own capabilities (`world`, `render`,
`input`, `ui`). Minecraft Java has none of those, so the port is a rewrite in Java that keeps the original's logic and
swaps the capabilities for what Minecraft offers. The aim is parity: the same strike, from the same seed, looks, sounds
and plays the same.

## Decisions

1. **Reproduce the plans, don't reinvent them.** A strike's plan is a list of events on a timeline (seconds): a vanilla
   command, or a stage worked out when it is due. The Rust mod builds these in `strike.rs` and `strike/*.rs`. The Java
   classes (`Plan`, `StandardPlan`, `MeteorPlan`, `MothershipPlan`, `BigPlans`) follow them: the same numbers, timelines
   and random numbers (`Rng` is the original's generator; `ShaderTables` has its `pcg` hash). A fix in one should reach
   the other. Where the original did something Java can't (see 4), the plan is simplified and marked so in
   [PARITY-CHECKLIST.md](PARITY-CHECKLIST.md).
2. **Run plans as vanilla commands, on the server tick.** `Strike` plays every strike's due events each tick through
   `performPrefixedCommand`, as the player with owner permission, so `/fill`, `/summon`, `/playsound`, `/particle`,
   `/forceload` and `/title` do the work. This makes the port work in single player and on a server without a second
   mod channel for the world.
3. **Share the budgets.** The original lets at most 20,000 blocks and 400 commands through a tick. The port keeps those
   numbers, shared across every strike that is on (`Strike`), taking turns with the first one rotating, so a pile of big
   craters doesn't freeze the game and several strikes can run at once.
4. **Simplify the big world changes.** The original's Planet Killer, Crystal Bloom, Sinkhole, Nuke and Rod write blocks
   straight into chunks through `world.edit-blocks` (fast, outside the command budget) and read the land through
   `world.read-columns`. Minecraft has no such call reachable from a plain mod without a lot of extra work, so
   `BigPlans` uses commands and reduced sizes for these. Their sounds, messages and timings are the original's.
5. **Draw the original's shaders, translated.** The look is a full-screen pass the original writes in WGSL. Rather than
   redraw it, `tools/build_shader.py` assembles each WGSL pass, patches it for Minecraft, and `tools/wgsl2glsl` (naga)
   translates it to GLSL. The generated `.fsh` files are checked in and must not be hand-edited. The result matches the
   original's pictures closely; the Plasma, Godly, Black Hole, Meteor Storm, Mothership, Payload and Nuke work.
6. **One pass per strike, each with its own clock and table.** `StrikeShader` keeps a list of strikes that are on. Each
   has its start time, its sixteen parameters (`mod_params`) and, for the Payload and Nuke, its table (`mod_data`, a
   4096-wide `R32_UINT` texture). Each pass reads the picture the previous one left. Each strike also has its own
   parameter ring buffer, because Minecraft's `MappableRingBuffer` has only three slots.
7. **Stay compatible with shader packs.** With Iris, the pack composites its final picture at the very end of the
   level's rendering and wipes earlier draws. `GameRendererMixin` draws the pass later, at the head of `render3dHud`,
   after that composite and before the hand's depth clear, and captures the projection the level was drawn with (the
   view bob is inside it) so effects don't drift while walking. Iris is detected by reflection, so it stays an
   optional dependency. Without a shader pack the pass draws at the end of the main pass through Fabric's
   `LevelRenderEvents.END_MAIN`.
8. **A mod that can't hook must still run.** The mixin config is `required: false` with `defaultRequire: 0`; a failed
   hook costs the shader pack support, not the game.
9. **Reach far land.** Distance mods (Voxy) draw terrain the server doesn't have loaded. `FarTarget` casts the normal ray
   first, then marches along the view line over the terrain's height, loading a bounded number of chunks per pick (a
   small stall, not an endless one). `Strike` force-loads the land that strike's plan works on and lets it go when the
   strike ends or on `/orbital stop`.
10. **Make far strikes sound far.** The original's sounds play from the player. The port tells each plan where the
    player is and where the strike is: sounds that come from the strike are heard from its direction (so HRTF can place
    them), late by distance (about 343 blocks a second), and quieter past about 48 blocks (audible to 256 and then a
    floor that falls). The device's own sounds (charge, lock-on) stay with the player. Flashes dim with distance.
11. **`/orbital stop` clears everything.** It drops what each strike still had waiting, lets go the chunks it held,
    cuts every one of the mod's sounds and the vanilla ones the strikes lean on (`OrbitalSounds` lists them), and sends
    every client a packet (`Net.StopFx`) to drop the strikes' pictures, tables, shakes and tints.
12. **Terrain damage starts off.** Strikes are permanent. A first strike is only light and sound.
13. **Credit stays visible.** The port is MIT, as the original is. `LICENSE` keeps both copyright lines and `NOTICE` lists
    what comes from the original.

## Data flow

1. The player holds right-click with the Designator for 12 ticks (`DesignatorItem`). `FarTarget.pick` finds the target,
   up to 1000 blocks away.
2. `Strike.start` builds the plan for the player's loaded laser (`Settings`), counts the shaders' parameters, and tells
   clients: `Net.StrikeData` (the Payload's or Nuke's table, if any) then `Net.StrikeFx` (laser, time, position,
   parameters).
3. Each server tick `Strike.tick` runs due events within the shared budget. Shake and flash events become `Net.Shake` and
   `Net.Flash` packets, scaled by distance.
4. Each client frame `StrikeShader` draws every active strike's pass over the finished world.

## The shader pipeline in short

`build_shader.py` (its header lists every step) does five things: it assembles the pass the way the original's build does
(the fork's prelude, `strike.wgsl` up to its `fs_main`, then the laser's own file, at QUALITY FULL); moves every viewing
direction to a far point so the view bob can't swing it; replaces the Payload's half-float packing (`packHalf2x16` doesn't
compile on the OpenGL 3.3 path) with plain floats; replaces `mod_data` with an unsigned-integer texture and the depth
`textureLoad` with a `depth_at` lookup (depth is reversed: 1 near, 0 far); and, after naga converts it, puts it in
Minecraft's format (its header, the fragment input location, a plain depth read, and the vertical flip). Read the script's
header before changing a step.

## Known limits

- The world changes of the big lasers are simplified.
- No half-size smoke stage (QUALITY FAST), no follow camera, no knockback, no impact frames, no seed lock.
- Settings live in memory per player and reset with the server.
- The wheel is a plain button list, not the original's ring.
- Only single player was tried, on Windows with an NVIDIA GPU. Multiplayer, other systems and other GPUs are untested.

See [ROADMAP.md](ROADMAP.md) for what to do about them.
