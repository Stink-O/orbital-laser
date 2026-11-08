# Notes for AI agents

You've been asked to set up or work on **Orbital Laser**, a mod for [Horizon](https://github.com/ludovic111/horizon) (the
Rust rewrite of Minecraft Java). It runs on a Horizon fork that adds the mod capabilities it needs:
[Stink-O/horizon, branch `mod-api-input-ui-render-world`](https://github.com/Stink-O/horizon/tree/mod-api-input-ui-render-world).
The README is the user-facing guide and the full copy-paste setup prompt is in
[README.md](README.md#set-it-up-with-an-ai-agent); [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) has the detail (every
laser, command, capability and timing). This file is the short, factual version for you.

## Ground rules

- **A strike is destructive and permanent.** It flattens everything above ground within ~44 blocks (52 for the black hole), digs a ~60-block
  crater and a shaft to bedrock, and kills every mob and dropped item within 40 blocks (not players). The Meteor Storm is far bigger:
  craters across 120 blocks round the target, then everything above ground flattened out to 100, a ~125-block crater,
  the land charred to 135, rubble out to 250 and every mob within 130 killed. The Mothership vaporises out to 34 blocks, digs a
  22-block crater, a shaft and a 100-block trench, and force-loads those chunks while it works. The Downfall buries a
  kilometre-long wreck at least 360 blocks in front of the player, crushes the land under its whole length, heaps
  berms along it and leaves the black hole's crater (arms out to 150 blocks) and a shaft; its crushing carries on for
  up to a minute after the strike. The Planet Killer is the biggest: it flattens out to 340 blocks, digs a crater 480
  across (terraced walls 60 deep, the floor 80, an open shaft 80 across to bedrock in the middle), heaps a rim out to
  340, splits the land in chasms out to ~400, chars it and strews rubble to 380, kills every mob within 280 and
  force-loads ~1,900 chunks from the moment it fires; its crater, rim and charred land go straight into the chunks
  through the fork's `world.edit-blocks` (new in the fork release `orbital-mod-api-4`) and are done about 25 s into the strike, the fissures' few
  commands soon after. The Crystal Bloom clears everything above ground out to ~130 blocks (24 up, to the sky over its
  middle), digs a geode crater ~176 across and 28 deep round a well 20 across to bedrock, leaves about two dozen crystal stumps up
  to 34 tall out to ~150 with three broken spires lying by them, opens nine fissures out to ~205, strews crystal shards
  and frosts the land out to 235, kills every mob within 160 and force-loads the ~770 chunks within 240; its land goes
  in through `world.edit-blocks` from the detonation at 22 s and is done by about 28 s. The Sinkhole caves the land in
  under a pit ~225 across (its rim wandering from ~190 to ~260) and down to bedrock: everything over the pit is gone
  (up to each column's real top: a mountain, its trees and snow, read with `world.read-columns`), its walls are cut back
  under the rim by up to ~6 (2.5 just under the rim's own band) and darken downward (tuff, deepslate, blackstone), water and lava in them are sealed (water to barrier near the top, tuff deeper; lava to magma), the middle is
  `clone`d down 7 blocks first (at 6 and 7.3 s), mobs within 140 die and the ~285 chunks within ~152 are force-loaded;
  its land goes in slab by slab from 8.6 s and down to bedrock from 16 s, done by about 23 s. The Payload is a bomb,
  not a beam: it digs a crater ~42 across (its edge wandering ~10%) and 9 deep, scorched (blackstone, basalt, tuff,
  coarse dirt, gravel, cobbled deepslate), its rim heaped up to ~4 high out to ~35 from the middle; everything standing on the
  land is swept off out to ~85 (up to each column's real top, read with `world.read-columns`), the trees there felled
  and lying pointing away from it (a stump of 1-2 left, their crowns crushed by their ends past ~46), the grass charred
  out to ~100, past ~85 a band ~24 wide where crowns are stripped and some trees knocked flat, leaves and branches
  strewn, ~220 pieces of rubble strewn out to ~105, ~90 falling blocks thrown out of the crater (landing out to ~110 by
  ~19 s, about half as blocks), mobs and items within 90 killed and the ~240 chunks within
  ~124 force-loaded; water it cuts into is dug like any other block (what is left flows in, as round TNT); the lava in
  the ground it bares is sealed. Its land goes in from 13.65 s, from the middle out
  with the shockwave, and the rubble lands by about 17 s. The Nuke is the Payload's big brother (`strike/nuke.rs`,
  `shaders/nuke.wgsl`): a bomb bursts 12 over the land at 11 s, its fireball spread over the ground; it digs a terraced crater ~200 across and 40 deep
  (water dug like any block), flattens everything standing out to ~230 (trees felled pointing
  away), strips crowns and knocks trees flat out to ~300, chars the grass to ~290, strews rubble to ~280, throws ~160
  falling blocks, kills every mob and item within 300 and force-loads the ~1,150 chunks within ~304; past that, out to
  480, its flash scorches what faces the fireball (a line of sight over the land's heights; read with a second set of
  32 `world.read-columns` queries, two in flight at a time, not force-loaded). Its land goes in through
  `world.edit-blocks` as one wave from the middle out (`Wave`, `nk_work` in nuke.rs: one chain of stages, ring by ring,
  split by angle, never by rows), each ring as the shockwave reaches it or as soon after as 350,000 blocks a second
  allows (`NK_RATE`), each chunk's edits on one tick (`Wave::chunk`: the game redraws its sections once); every stage stays under ~1.3 ms natively wherever it lands (`nuke_no_stage_too_heavy_anywhere`,
  ignored: run it on its own; `nk_wave_profile` prints the wave tick by tick), since a stage over the tick's fuel stops the mod ("took too long"). `/orbital shadow
  off|on` (not kept) hides the Nuke's and the Payload's cloud shadows, for comparing. As the Nuke's front reaches the
  player it knocks them back and up (`Act::Shove`, lib.rs's `knockback`: a kick to their velocity through the fork's
  `world.push-player`, 0.8 blocks a tick out and 0.55 up within 200, fading to none at 600, `strike::knock_share`;
  they fly a jump's height or so and some six blocks back, then fall) and jolts the camera
  (`nk_jolt`) and the picture itself (nuke.wgsl's `pl_jolt`, on top of the game's shake, which tops out at a few
  degrees). The Rod from God is the Nuke made kinetic and holy (`strike/rod.rs`, `shaders/rod.wgsl`, the
  same reads, `Wave`, pacing and far-land waiting): plumb over the target, a hard last burst of speed eased in over
  its last half second to about 2,300 blocks a second (`RdGeo::left`: under 40 blocks a frame, so it reads), impact
  at 7 s (`RD_HIT`, which the sounds key off); a crater ~120 across and 50 deep with steep walls (`bowl`: a punch)
  lined in quartz, calcite and gold (`scorched`), a bleached rim (`ejecta`) out to ~90, the crater dug out first
  and lined after (`Wave`: the carve, air over every crater column's floor and the lava it bares sealed, out from the
  middle with the shock at `RD_CARVE_RATE` from 7.1 s, the whole pit open by ~7.7, ~60 chunks; then, `RD_LINE_GAP`
  after, the lining from the rod out at `RD_RATE`, the rod and the heave by ~8.05, the floor to its walls by ~8.6, on
  out over the rim and the land; a chunk's edits on one tick in each, `carve_chunk` and `chunk`), the floor round the rod's foot heaved up in broken, tilted slabs out to ~22
  from its axis (`rd_heave`; its ring of light kept clear), the rod left standing in
  its middle (`rd_rod_col`: 13 wide, 130 over the floor, its top 80 over the land, and 40 under it, driven in deeper on land so
  high its top would pass 318 (`rd_rod_base`; rod.wgsl's `rd_top_end`), polished blackstone banded in gold, a ring of
  light round its foot; keep rod.wgsl's `RD_R`, `RD_L`, `RD_TOP_END` in step), trees felled to ~200 (a band of
  stripped crowns to ~240), the grass blessed (white concrete, calcite, quartz, gold, lights, pale moss: `charred`) and
  rubble strewn in ~17 rays out to ~250, ~120 falling blocks thrown up in a cone, mobs killed within 200, the ~830
  chunks within ~260 force-loaded; its land goes in from 7.1 s, the pit dug by ~7.7, the rod by ~8.05 (rod.wgsl's `RD_LET_GO`, 1.8,
  draws it till then and a margin), the crater lined by ~8.6, all by ~13.5 s. Its
  knockback is 0.65 out and 0.5 up, none past 450 (`rd_jolt`, sharper).
  Its pass has impact frames (`rd_impact`, `rd_if_cut`, `rd_clock`): the pass's clock holds on the hit for 12–14
  frames at 60 while hard cuts of 2–3 frames each play (Kanada style, `RD_IF_STYLE` 1: black silhouettes and thick
  converging lines on white, a 3x close-up in negative with gold lines, gold and umber two-tone), the camera punching
  in and shaking per cut, then a zoom blur with a colour split and a glow as it lets go and catches up over 0.35 s
  (the look is the player's: `/orbital impactframes kanada|blackflash|cinematic|off`, the wheel's IMPACT FX row,
  sent as params[15] / 4 = 1 + `RD_IF_STYLE`'s number, read by `rd_if_style`; the preview's `--set rdif=N` sets the default); params[15] + 2 turns
  them off: `/orbital impactframes off`, the IMPACT FX row's OFF, kept). Only fire them in a
  throwaway world, and ask the user before the first strike with terrain damage on. `/orbital terrain off` (or the
  wheel's centre) makes strikes light and sound only.
- **The Supercell** (`strike/storm.rs`, its funnels `strike/vortex.rs`, `shaders/supercell.wgsl`; 42 s): ~120 bolts
  out to 120 blocks, building (`sc_bolts`: lone small ones from 4 s coming faster, from 15 s waves of more and more at
  once up to `SC_CAP` 5, from 24 s drawn in onto the target, the last wave right before the finale at 29 s, which the
  pass collapses them into; the table's per-second index `SC_I` keeps the pass to the bolts due) (terrain on only: each hurts what stands at its foot, `damage ... minecraft:lightning_bolt`, and sets a few
  fires there; never a vanilla `lightning_bolt`, whose own thunder can't be silenced in time), a pit a block or two
  deep at each, the funnels' tracks scoured (plants, leaves, a few falling blocks), and a finale crater ~70 across and
  24 deep with fulgurite glass veins out to ~85, an overturned rim, trees blasted and set alight out to 95, the land
  scorched to 112, 60 blocks thrown, mobs within 80 killed. It never touches the world's weather (the pass draws the
  rain). The fires its bolts light are left burning (they burn out or spread as fire does; a stop leaves them too).
  Force-loads the chunks within 154.
  Its thunder (`tools/sounds_storm.py`; `sc_thunder` schedules it) is late by the distance and picked by it: `crack`
  within 90 blocks, `crack_mid` to 260, `crack_far` (mostly rumble) past that, each take its own event
  (`supercell.crack3`) so none plays twice running; bolts heard within 0.15 s of each other are one louder clap, never
  a flam; the flurry's quieter (`size_db`). The finale's file starts `FIN_PRE` (1.2 s) before its crack, its run-in
  the last waves' cracks stacking up (keep FIN_PRE in step in both). Horizon plays every sound file summed to mono; `--listen` mixes as
  the game does.
- **The Hurricane** (`strike/hurricane.rs`, `carry.rs`, `shaders/hurricane.wgsl`; 64 s, reaches 1000 blocks) digs
  no crater but strips the land round its eyewall: from 15 s its wind's front, out from the eyewall (62 blocks) in to
  32 and out to 150 by 35 s, takes the trees, the light things people put up and everything built (all of it within
  ~100, further out roofs and high blocks first, nothing past 150), the land's own top one to three blocks from 34 to
  105, the plants out to 175 and the leaves to ~158 (in patches past it); the calm eye (26) is left alone, and so are
  water, unbreakable blocks, blocks the table doesn't know (a mod's) and blocks that hold items (chests and the like,
  with their contents). At 46 s it flings it all out: up to 128 trees and pieces of buildings land as real blocks
  where they fall, and 2,400 blocks of rubble come down out to ~170. Mobs and items out to ~176 are carried round and
  flung (terrain on; the fall does the damage, nothing is killed outright), the player too with KNOCKBACK on (within
  175, terrain on or off). Force-loads the chunks within 184 from the moment it fires. Its eyewall lightning flashes
  in bursts at 16-28 s and 43-46 s (bright full-screen flashes: a photosensitivity note goes with it in the README and
  the release notes). The storm itself: some 3,500 across
  and 450 high (the picture of Florence from the space station is the reference). A ragged mass of towering storms
  gathers (0-6 s) and is drawn into three trailing bands wound tighter round a dense core as it organises (`hu_org`,
  to 16 s; each place comes together at its own time, `hu_mature`: the core first, then out along the bands, by a broad
  noise, eased, so no step or ramp shows over the whole of it, the cells' tops, softness and the bands' spread all by
  it), the eye opening from a pinhole by 17 s into a stadium (`hu_flare`: its billowed face, `hu_eyeface`, flaring
  out as it rises, widest at the peak 36-46 s; its far wall sunlit from the rim, `hu_eyelit`), an open moat round the
  eyewall under the overcast's top (from above one shield runs unbroken from the eyewall's top out over the central
  dense overcast, the bands feathering out of it, merging into it close in; each band and the overcast's edge thin at
  its edge and domed to its middle, `HuCol.h`, never a sheer cliff; the plan's noise all gradient noise, `hu_gn2`: a
  value noise's lattice showed through its sharp thresholds as straight cuts and chevrons), anticyclonic cirrus streaks over it all (`hu_col` the cloud's plan, `hu_den` its density; lit from its top
  down with one self-shadow sample a lit point). The eyewall's base is a little over the land so the tear-up shows
  under it. Lightning (`hu_flashes`: a fifth-of-a-second slot each, bursts at 16-28 s and 43-46 s, about a third of
  them bolts out of the eyewall's flank across the moat; the brightest lights the cloud). The wind spins up to full
  by 26 s (`SPIN_K`); from 15 s its front (`front_t`) tears the land up from the eyewall (62) in to 32 and out to 150
  by 35 s (plants and leaves stripped to 175): every column out to 180 is read (`world.read-columns`, 24 ring parts,
  re-asked till loaded, given up at 40 s), and as the front reaches each chunk what stood on each column goes, block by
  block as read (an edit run over just that block, filtered by its name): trees, light things, plants, the top one to
  three blocks of the land's own ground (34-105), and **everything built** (class 7: by the wind's strength and
  exposure, `torn`: all of it within ~100, further out roofs and high blocks first, nothing past 150; a column's roof
  at its time, its walls, floor and the ground under them 1-4 s later). What stays (class 8, `stays`): unbreakable
  blocks (bedrock, barriers, portal frames, command and structure blocks, spawners), any block the table doesn't know
  (a mod's), and blocks that hold items (chests, barrels, shulker boxes, furnaces, hoppers, lecterns, shelves...),
  left in place with their contents; water is left alone. What each block is to the wind, and its colours, come from
  `strike/hu_blocks.rs`, generated by `tools/hu_blocks.py` from the player's prepared resources (every block's
  textures averaged, top, sides and bottom, and its tint; its class from the block tags); regenerate it for a new
  game version. The pass draws block types (`HU_BK`) and faces, coloured in one place (`hu_face`): with the game's own
  textures (the `atlas` capability, fork API 10: `atlas.block-sprites` packed a block type at a time by `bk_words`,
  repacked when `atlas.resources-version` changes; the pass samples bindings 8 and 9), the average colour as the
  fallback and the far LOD. Seen through as the game draws them (`hu_see`, from the atlas's flags: `face_words`' cutout
  bit and translucent bit 15, the layer in 13 bits): a cut-out face's clear pixels (leaves, glass, flowers, rails,
  bars) show what is behind, a lone block's faces towards the eye only, a tree's leaves cell after cell (up to six, then
  solid); a translucent block (stained glass, ice, slime) is blended over what is behind by its alpha, the nearest one
  only, found again for its colour once the search is done (`HuHit` kept small: the searches' loops hold it all the
  way; a translucent block in a tree or a building's piece is drawn solid). FAST hands on the nearest block or tree
  seen through for its 2x2 (`HuHit.cid`), and the join takes the cloud of the half-size pixel that marched shortest when
  that is the block it finds sharp (`HuJoin`), so no cloud from behind a leaf is laid over it. Offscreen, `HU_GLASS=1`
  in the environment of tools/preview.py puts glass, stained glass and ice in the land (`hu_write_table`). Offscreen, `tools/hu_atlas.py` makes a stand-in for the sprite arrays from the player's
  prepared resources (tools/preview binds it as `PREVIEW_ATLAS`; the tests' fake atlas reads `HU_ATLAS_JSON`, each
  texture cut out or translucent by its own alpha).
  **Trees meet a mix of fates** (by hash, the wind's strength and the tree's size): most are shredded where they stand
  (their logs and leaves go up as the field's blocks); of those given a record, a few uprooted whole (`HU_WHOLE`, 36,
  the bigger nearer the eyewall), some snapped at the trunk (the crown and upper trunk carried off whole from the top
  of a stump of 1-4 logs the edits spare), some lifted whole to break apart in the air (`t_break`, word 6: the pass
  breaks them into twelve pieces, `hu_piece_box`, each its own body from that instant: where it was and turned as the
  tree was, then flung off its own way, tumbling about its own axis, `hu_vox` walking its cells; each block gone where
  it hits the land; no real landing of their own). The field's blocks are never a lattice: each column of a ring's
  cells climbs at its own speed and sits at its own height (`hu_column`), each block anywhere in its cell and wobbling
  there, thinned and thickened in patches, now and then two to a cell. The cloud's edges are soft and wispy while it
  gathers and as it breaks up (`hu_soft`); the mature deck is solid. At the end each place thins away to nothing at its
  own time, the edges first, all of it gone by 63.4 s (`hu_gone`; lit from the top it has left, `HuDen.top`, so what is
  left is never darker than the cloud was), and the land's shade under it goes with it: nothing pops out at 64 s.
  **A block's whole life, each handover seamless:** up to `HU_NT` (128) rigid voxel groups, trees and (up to 48)
  pieces of buildings lifted whole where they stood (`TreeRec`: trunk, 7x7 spans; path `tree_at`, mirrored by the
  pass's `hu_tree_at`); the field of blocks round the eyewall in 13 rings of 3-block cells (`ring_*`, the pass's
  `hu_debris`) rises out of the land behind the front, never appearing in the air (the cells over the land as the
  front came stay empty, so the column fills from the ground up: `ring_fill`), climbing out along the stadium's slope,
  each ring coloured from a weighted sample of what was torn up under it (`Pal`, table `HU_PAL`, building rubble
  included). At the fling (46 s) everything is thrown out: the field's blocks fall and shatter to dust where they hit
  (a dust wave spreading out with them), and `HU_RUBBLE` (2,400) real blocks from the rings' samples land where they
  do (one a column, on the ground, never into water); each tree and piece is laid as real blocks (logs along x or z,
  leaves that don't decay, at most 160 a piece) exactly where and when the pass lays it down: `tree_landing` solves
  its fall onto the real ground as the strike leaves it (`left_top`) and writes `t_land`, `yl`, `yaw` into its words
  25-27; the pass slerps its tumble into that pose (`hu_slerp`) and hands over at `t_land`. Every landing edit goes
  only into air and never into the player's body (`Blocks::clear_of_player`, lib.rs's `edit_clear_of`). Mobs
  (terrain on) are carried round by `tp ^ ^ ^`, their `Motion` zeroed each tick; at the fling given their own
  motion (out, along the wind, up) and left to fall: fall damage does the rest (no kill at the end). The player, with
  KNOCKBACK on, is picked up when the front reaches them (none in the eye, none past 175; flying, standing, falling,
  gliding or swimming), eased into the spin (no snap), carried at 108 out and 50 up by the fork's
  `world.carry-player` (API 10: each tick their move in place of their own, through the game's collision move, no
  gravity, no drag, no fall distance, out of flight, drawn smoothly, and a turn of their view spread over the frames:
  `CARRY_TURN` of their turn round the storm plus a gentle gust sway, `/orbital carryview turn|still`, kept; at most
  3.5 blocks a tick here, never near `VMAX`), round the eyewall with the debris, buffeted, never drawn into the eye;
  at the fling swept out over 1.4 s into a throw (`THROW_V`: out, round with the wind, up) and let go with it: a
  `world.push-player` made while carried is the throw the game lets them go with; the game's physics from there (a
  player who may not fly gets 12 s of Resistance V so the landing does not kill them). Only sneak held half a second
  breaks free (the game decides: a tap of sneak, a jump, a double jump or an abilities packet does nothing while
  carried): the next carry answers false (heard two ticks after the carry it is about: `Carry::asked`), the carry
  lets go with a gust's whoosh, and the game keeps only a little of the carry's motion and puts a creative player
  back into flight. Ticks held still while chunks load keep the carry pending. Free, they are left alone while they
  fly (`game.player-flying`); out of flight a second running (landed, or stopped flying in mid-air) while the wind
  still blows where they are, they are picked up again, as often as they break free. Rain close by is drawn in the world (`hu_rain_lines`, the Supercell's `sc_rain_lines` the same): drops
  strung along lines in the way they fall (down, and blown by the wind where the camera is), the lines' feet on a grid
  across that way, four layers out from the camera on coarser grids, only the cells the ray crosses tried, so no
  direction is special (never shells round the camera: they converge on the points overhead and underfoot); none in
  the eye. The cloud is solid: its 3D noise displaces its surfaces (tops, bases, edges) rather than thinning its body,
  the high cloud's noise turning all of a piece (no brushed stripes), every stride of the march jittered per pixel
  (white noise: grain, never slices, contours or sheets). The storms it gathers from condense from their strongest
  cores; as it breaks up the eyewall collapses from the fling, the moat fills, and the cloud is eaten from its edges
  and top, shredding. The pass's FAST stage finds each 2x2's block or tree at
  half size (`hu_pack`, in `half_extra.zw`) and the join tries them again sharp; keep what the cloud's march holds in
  hand small (the GPU's occupancy): it takes the brightest flash alone. Preview views `huorbit`, `hutop`, `hueyeup`,
  `hueyemid` (and the older `hu*`); `hu_write_village` (ignored) writes a village's table and its standing blocks
  over time (`vox_<t>.txt` for the preview's `vox=1`). Sounds `tools/sounds_hurricane.py`: three continuous minute-long
  beds (wind, roar or roar_far, rain) played once from the start, the storm's life written into them, their levels by
  the distance; debris accents now and then, trees' cracks where they are torn up, whooshes while carried (none in
  the eye); thunder for the eyewall's lightning (`hu_flash_list` mirrors the pass's flashes: `thunder` within ~110,
  `thunder_mid` to 320, `thunder_far` past it, `rumble` for a flash in the cloud, late by the distance); `--listen DIR`
  mixes it as the game does at 60, 150 and 500 blocks and carried (`hu_write_sounds`). The designator's countdown
  for it is `TRACKING STORM …`.
- **The Supervolcano** (`strike/volcano.rs`, `strike/vc_land.rs`, `shaders/volcano.wgsl`; 80 s, reaches 1000, the vent moved
  to at least 500 blocks in front of the player by `vc_vent`, `fire` in lib.rs): an orbital laser satellite over the
  vent (`vc_opening`, `vc_sat0`: 7,000 up, 1,600 beyond the vent from the player, table words 2-3, drawn up to 5.5 times its
  size far off, scaled from where it parks so it shrinks as it leaves: `vc_sat_k`; built of blocks in `vc_sat_hit`: a
  gold-foiled bus and engine, white radiators, a gold collar, roll-out solar arrays on a truss turned to the sun
  (`vc_sat_wing`: rolled up as it comes, out from 0.95 s, back in from 5.0), an octagonal barrel
  ringed by four coils stepping in to the emitter, four prongs; from the ground, nearly down its barrel, a dark cross with
  a glowing eye) comes straight down from 3,000 higher, braking on four jets fired down, settled over the vent by ~1.1 s
  (`vc_sat_go`, `vc_sat_tip`), aims a solid red targeting beam (0.6 s, locked at 1.5; its coils lit red), its coils charge
  outside in and it fires at 2 s (`VC_HIT`), a white-hot beam melting a round glowing hole (`vc_open_land`, light only)
  cut at 4.6 s (`VC_OFF`); it rolls its arrays in, kicks its jets at 6.1 (`VC_BURN`) and lifts straight up and away,
  into the haze by 9.5 (never a fade on the spot). Steam surges off the hole as the beam is cut and is fed in
  pulses, puffs rising, slowing, swelling and bending with the wind, red from under (`vc_plume`, `vc_feed`), until the
  eruption; the mount rising round the hole; the
  tremor, the ring cracking at 8 s with wisps of steam, the eruption at 12 s (`VC_ERUPT`, a flash along the ring and a
  pressure ring at the speed of sound), a ring of vents 560 across feeding a column to about 1,800 (`vc_col`: the
  ring's foot follows the land, `vc_land`, a heightfield of 128 x 128 cells; lumps on lumps, `vc_lump_col`, drawn out and
  rushing low down by the height they are looked up at), 64 lava bombs from 13 s (`vc_bombs`, solved against the land,
  their smoke at half size, their heads sharp; each landing leaves a small real crater, counted from each column's
  ground so it needs no read), lightning from 20 s (`vc_flash`, a slot of 0.13 s, in the plume, then in rings through
  the sheet; `vc_bolts`), the umbrella spreading from 23 s (`vc_umb`, out past the horizon, Hunga Tonga's ripple
  `vc_ripple`), the sky dark by 40 s (`vc_dim`: land and sky darkened by what the sheet shuts out, `vc_sun_t`,
  `vc_sky_t`, what glows left glowing; the game's clock and weather never touched), the collapse at 44 s (the lumps slow,
  stop and fall back, `up`, the top of what stands falling, `Hb`), the wall of ash from the ring (`vc_flow`, `vc_front`:
  60 blocks a second slowing to 25, at 500 by about 48 s, looked up round the vent so its lumps travel with it without
  smearing, `vc_lump_flow`, the lattice wrapped round the circle; its base lifting off the land behind it into new
  clouds from 60 s), the player engulfed (near black, embers, `vc_specks`), then a dim world under falling ash, the sheet
  thinning from 69 s to a blood-red sun, all gone by 80 (`thin`). FAST's half stage holds the cloud and the bombs' smoke.
  **Its cloud's cost:** a GPU works on pixels in groups and a group lasts as long as its slowest, so `vc_march`'s time
  goes with the worst ray of a group and with what its lanes branch into at different steps. The look at the light is out
  of the loop for that (once a ray), and skipping pixels saves nothing (a chequerboard of pixels or of 2x2 blocks was
  tried). `vc_gn3` is gnoise3 with a hash a corner; `VC_HOLD` keeps the big lumps longer far from the surface; the air
  the wall has emptied is crossed without looking up lumps (`VC_ST_AIR`).
  **The blast** (`vc_col`) is lobed round a low base surge (the surge only till the collapse, bounded at its rim: past it a
  flat ellipsoid's distance is about the height over the land everywhere, and the lumps stand a dark sheet on all of it).
  The shock is a thin torn veil at the pressure ring's speed (`vc_shells`, worked out from the ray's closest approach so no
  line runs round it) and a low haze of dust behind it (`vc_dust`). **The pass is close to the game's 256 KiB**, comments
  included (`tools/check-shader.sh` says): new code here wants something taken out.
  **A chain of stages takes the strike's clock** (`now.max(clock())`, in `vc_work` and `vl_tick`): counting its own time it
  runs at half speed beside another chain, and what's due last never goes in.
  **Thin walls show the land through:** the ring's wall must stay thicker than the lumps cut (`vc_ww`, the gain in
  `vc_lump_col`). Its land (terrain on only, `vc_land.rs`): a caldera about 560 across and 90 deep, a lake of dark crust
  (`lake_edit`: big plates warped irregular, broken further in places, veins of lava towards the ring's vents `Hot`,
  dimming to magma and dark seams away from them, a few open pools, lava some 6-8% of it), seven huge blocks of the land
  dropped whole into it (`Drop`, their beds in them); its walls (`relief`) a scarp, slumped blocks each dropped and turned
  back on its own, rubble fans at the foot, faced in dark beds carried down with them (`beds_edit`, a bed's run at a
  time: per-block rock here was most of its runs); the rim (`Ctx::rim`) tilted slabs on the ring's apron of ash
  (`apron`, the land rising to the crater), a crown of wedges where it burst hardest; one deposit to about 440
  (`out_edit`: one tone with a fine grain, wet streaks along the flows, `ring_noise`, ponded in the low ground, a skin on
  the ridges so the land shows through, lobes down the valleys), water under it filled to a dark wet plain; past it dust
  thinning through patches (`dust_cover`), pumice on the water, on to the odd patch by `VC_FAR` (1050) wherever the world
  has chunks loaded (`vc_far_chunk`, no read, counted from each column's ground); the trees graded by `fate`, `stand_edit`
  and `vc_fell`: charred trunks lying pointing away and burnt stumps to `VC_FELLED`, bare black trunks to `VC_BARE`,
  scorched to `VC_SCORCH`, leaves browning (mangrove roots and the poplars' red and orange leaves) to `VC_GREEN`; mobs and
  items killed as the wall passes, never the player; water and lava the walls cut into sealed; the ~4,000 chunks within
  `VC_LOAD` (576) force-loaded: it has to be that wide or the fade stops at a straight chunk edge on the side away from
  the player. It goes a chunk at a time in order of when each is due (`vc_due`: past the ring with the wall, inside it
  from the edge in at `VC_RATE`, done by about 72 s), each chunk's edits on one tick; the caldera needs no read, the rest
  reads rings of columns from `VC_READ0` to `VC_READ`, packed a 32-bit word each. **Its limits:** a mod has 64 MB
  (below). `VC_FLIGHT` bounds the parts of the read out at once: one asked a tick and never more than that many unanswered, or
  the answers pile up in the mod and the reads fall behind the server thread. Chunks not loaded are listed as chunks
  (`Missing`), never as columns. `VC_QUEUE` caps the runs waiting and `VC_HOLD` stops new chunks while the mod holds
  that much (the edits behind slow frames); a column is as few runs as it can be. A chunk's real fuel is 2 to 3 times its
  count (runs are cheap going out, some 90 fuel; it's the noise and the runs' making): `VC_TICK` allows for it. Anything a
  stage does thousands of times that isn't a chunk wants counting too: `hypot` and `vc_due` are dear (`DueTable`, `far_chunks`),
  and the mount's tables go in stages (`PlateSums`). `mod_soak` with `SOAK_FULL=1 SOAK_LASERS=supervolcano SOAK_REPORT=8` plays
  it whole. `VC_VIEW_OUT=DIR [VC_VIEWS=map,air570,...]
  [VC_LAND_SEED=N] cargo test --release vc_land_picture -- --ignored --nocapture` (strike/vc_land_view.rs) makes the real
  edits on a synthetic land in a voxel grid and writes a top-down map and ray-traced views as PPMs, in seconds: look there
  before the game. **The far terrain doesn't see these edits:** see `docs/HOW-IT-WORKS.md`.
- **The Supervolcano's plates that stay** (`strike/vc_lodge.rs`; the pass's `VL_*`, `vl_*` and `vm_plates` in
  `shaders/volcano_mount.wgsl`): the ten biggest whole plates the mount throws come down as real land, terrain on only,
  and stay. Their sites are worked out as the strike fires (`vl_sites`: five on the player's side, 310-460 from them,
  the rest round the mount, all 570-860 from the vent), their chunks force-loaded from then (`vl_patch`, 160 round each);
  the plates are picked at the end of the mount's tables (`vl_pick`) and aimed, their flight's words rewritten (`vl_one`,
  `Slab::fly`). From 19.5 s the ground where each meets it is asked (a small `world.surface-height` query) and its pose
  settled (`Pose`, `set_pose`: lying low, `VL_LOW` to `VL_STEEP` degrees, turned up to 42 degrees off the way it came and
  rolled up to 15, on a plane fitted to the ground under the whole plate, `Slab::bed`, at most `VL_BANK` steep, so a bank or a
  shore by its foot doesn't leave it stood on a stack of earth; its low end in the ground, what it lifts packed under with crushed
  earth, `under`, and that earth heaped most of the way up its edges (`VL_UP`) and falling away from them, `make_fall`, `talus`, so nothing is held up by air or a sheer wall;
  `Lodge`'s words at `VL_BASE`) before its last 3.5 s, in which the pass slerps its tumble into that pose and slides it
  in (`vl_add`, `vl_slerp`). From the moment it hits its chunks are read (`Lot`, `vl_tick`) and made (`Slab::chunk`: the
  plate a world column at a time, `spans`, so it has no holes; soil, rock and a burnt underside as strata by depth; its
  ground's lip, cracks of tuff and rubble round its foot), each chunk one edit through the paced queue, none worked out
  before it's needed, so nothing is held. The pass holds the drawn plate where it lies until every edit is in
  (`Blocks::sent`, then the plate's word `gone`) and fades it out over `VL_FADE`; past `VL_SEEN` (470, about the render
  distance: the game doesn't show the land's changes further) it goes on drawing it until `VL_END`. Land not answered,
  or the player in the way: it stays drawn and goes on into the ground (`Step::Failed`). Terrain off: the same flight, no
  blocks. A stop finishes the plates under way, nothing else (`vl_finish`, a far-future `Act::Cleanup`), and the land's
  work leaves their columns alone (`Lodge::covers`). `vc_plate_picture` (ignored; `VC_VIEW_OUT=DIR
  VC_VIEWS=p0g,p0h,p0f,p0a,p0m`) makes their real edits on the synthetic land. Keep `vl_thk` in step with the pass. Stages
  wait their turn (one a tick): `strike::set_clock`'s clock is the true one, a stage's own count falls behind it.
- **Minecraft is not part of this repo.** Horizon's prepared resources come from the user's own Minecraft Java 26.3
  (`horizon-prepare`). Don't download, bundle, fake or work around it.
- **Stock Horizon can't run the mod.** It needs the fork's build, release `orbital-mod-api-10` or newer (it adds
  the `atlas` capability, the game's block textures in a post pass, which the Hurricane draws its flying blocks with;
  `world.carry-player`, the Hurricane's carry; and `game.player-flying`; `orbital-mod-api-9` skips a post pass the
  driver can't build instead of crashing; `orbital-mod-api-8` added `world.push-player`, the Nuke's knockback;
  `orbital-mod-api-7` added the half-size stage QUALITY FAST draws the
  Payload's, the Nuke's and the Rod's smoke with, `orbital-mod-api-6` `world.read-columns`, `orbital-mod-api-5`
  `world.surface-height` and `render.set-data`; older builds won't start the mod): a Linux x86-64 download on the
  fork's releases, or
  `cargo build --release -p horizon-client --features mods` in the fork elsewhere (ask first: it takes a while).
- **Tested on Linux only** (a user reports Windows 11 working, the fork built from source with `--features mods`; on
  macOS the Downfall's pass crashes Metal's compiler). On Windows and macOS keep fixes small and tell the user what you
  changed.
- Run `install.py` with the game closed. Don't touch the user's saves or settings beyond what it does.

## Commands

```sh
python3 install.py                  # install the mod into Horizon's game folder and switch it on (game CLOSED)
./play.sh [WORLD]                   # start the fork's build on the game folder (default world OrbitalTest, creative)
python3 tools/build_mod.py          # build the mod from source into dist/orbital (needs cargo-horizon-mod from the fork)
tools/check-shader.sh               # validate the post passes (a tenth of a second)
tools/preview.py downfall 14 30 45  # render those moments offscreen onto dist/preview/downfall.jpg (seconds; no game)
tools/preview.py payload 18 --quality both --bench   # the Payload at QUALITY FULL and FAST side by side, timed
tools/preview.py rod 7.05 9 25 --views rdnear,rdstand  # the Rod's impact frames, its jet, it standing (views rd*)
RD_VOX_OUT=/tmp/h.vox cargo test --release rod_heaves_the_floor_round_its_foot   # (in mod/) the heave as voxels: then
PREVIEW_VOXELS=/tmp/h.vox tools/preview.py rod 40 --views rdfoot,rdfootup --set vox=1
RD_CAVE_OUT=/tmp/c.txt cargo test --release rd_cave_order -- --ignored --nocapture  # the crater dug, then lined, by tick
python3 tools/sounds_rod.py --listen DIR             # the Rod's sounds (and listening mixdowns from 200 and 600 blocks)
tools/world_snapshot.py save|restore|reset WORLD [NAME]  # snapshot a world and put it back (refuses while it's open; reset leaves, restores, rejoins)
```

**Search with ripgrep (`rg`), not `grep`.** It's installed, much faster on this repo and the fork, and skips
`target/` and other ignored files by default: `rg -n 'pattern' mod/src`, `rg -l --type rust 'fn tick'`.

**Iterate on a strike's look offscreen first.** `tools/preview.py LASER TIMES... [--views player,far,side,up,under,aerial,tower,cbplayer,cbfar,spire,cbside,cbaerial]
[--set key=value...] [--bench]` (`--set sunel=3 sunaz=180`: the sun's height and bearing in degrees, for dusk and
night) builds the pass exactly as the mod does, renders every moment from every view in one run
over a synthetic scene, and writes a labelled contact sheet; `--bench` prints the pass's GPU time. Only then rebuild,
install and check it in the game, once. In the game, `/orbital skip SECONDS` (terrain off) starts the next strike that
far in, so one moment can be looked at without sitting through the rest; `horizon-ctl command "orbital skip 29"`
from a script.

In the game: `/orbital give` (the designator), `/orbital wheel`, `/orbital plasma`, `godly`, `blackhole`, `meteor`, `mothership`, `downfall`, `planetkiller`, `crystalbloom`, `sinkhole`, `payload`, `nuke`, `rod`, `supercell`, `hurricane` or `supervolcano`, `/orbital approach …`, `/orbital arrival …`, `/orbital colour …`, `/orbital terrain on|off`, `/orbital hud on|off`, `/orbital payloadsound main|alt`, `/orbital nukesound main|alt`, `/orbital quality full|fast`, `/orbital impactframes kanada|blackflash|cinematic|off` (`on` brings back the last look), `/orbital seed N|lock|random` (kept, the wheel's SEED field and LOCK SEED switch: N in 1-997 holds every strike's seed, `lock` holds the last strike's, `random` lets go), `/orbital knockback on|off` (the Nuke's, the Rod's and the Supervolcano's push, the Hurricane's carry; kept, the wheel's KNOCKBACK switch), `/orbital carryview turn|still` (kept: whether the Hurricane's carry turns the player's view a little with them round the storm and sways it with the gusts, `CARRY_TURN`; `still` leaves the view their own), `/orbital follow on|off` and `/orbital follow distance N` (kept, the wheel's FOLLOW switch: an orbit camera round a Nuke's or a Payload's bomb, `follow.rs`: the player's own look sets the angle, the camera `distance` (70) back from the bomb along it; moved only by `world.push-player` kicks each tick, never faster than 24 blocks a tick (`VMAX`: past that the game's collision sweep runs out of budget and crashes), worked out against the game's own drag so its movement and frame interpolation carry it, never a teleport or a turn of the view; it leaves the player once the bomb is within 440 blocks of them, so it stays on land already loaded; backs off to 380 (the Payload 170) as the burst nears, orbits the cloud, and a `tp ... ~ ~` puts them back), `/orbital flyspeed N|reset`, `/orbital stop` (ends the strike under way; also the wheel's STOP STRIKE button while one is), `/orbital skip SECONDS`.
The wheel has pages of five (its arrows, its tabs or a right-click turn them); the Downfall, the Planet Killer, the Crystal Bloom, the Sinkhole and the Payload are on the second, the Nuke, the Rod from God, the Supercell and the Hurricane on the third. Its FLY
SPEED row over the title sets the creative flying speed (a click along the bar for 1x–40x, or a number typed in its
box, up to 1000x, Enter to set), through `world.set-flying-speed` and `input.poll-typed`. A fork build without them, or
without `world.edit-blocks`, `world.surface-height`, `world.read-columns`, `world.push-player`, `world.carry-player`,
`game.player-flying`, `render.set-data` or the `atlas` capability, won't start the mod.
The wheel's left column has the strike options: SEED (a field: the last strike's seed, or one typed) and LOCK SEED
at the top, then KNOCKBACK (the Nuke, the Rod, the Hurricane) and FOLLOW (the Nuke, the Payload) only for the lasers they apply to
(`toggles` in wheel.rs); the right column PANEL and QUALITY, and a red STOP STRIKE under QUALITY while a strike is
under way, its rows lined up with the left's (PANEL with SEED, QUALITY with LOCK SEED, STOP STRIKE with the first
switch under them). Nothing goes over the hotbar but the designator's: its countdown while held (`ACQUIRING TARGET …`, `SEISMIC SCAN …`,
`DESIGNATING …`, the Hurricane's `TRACKING STORM …`, the Supervolcano's `BREACHING CRUST …`, with the laser's name) and `NO TARGET IN RANGE` (`actionbar` in lib.rs;
the strikes have no messages; firing during a strike only clicks). With the Rod loaded or pointed at, an IMPACT FX row under the ring (OFF, KANADA, BLACK FLASH,
CINEMATIC). With the Payload or the Nuke loaded or pointed at, a BLAST SOUND row under the ring picks its blast (MAIN or ALT, as
`/orbital payloadsound` or `/orbital nukesound`). Every post pass is built ahead of time by `mod/build.rs` (`src/passbuild.rs`): a switch
only picks a ready-made one. The QUALITY switch under PANEL (top right; `/orbital quality full|fast`, kept
between sessions, default FAST) picks whether the Payload's, the Nuke's and the Rod's smoke is drawn at full size or at half size: FAST gives the
game the pass with its half-size stage (`fs_half`, `fs_join`; see below), which the fork draws from release
`orbital-mod-api-7` (an older fork would compile the same source and draw its `fs_main` at full size; FAST needs no
import of its own).
R with the Orbital Laser Designator in hand opens the laser wheel (with anything else in hand R is left to the game;
`/orbital wheel` opens it from anywhere); holding right-click with the designator for under a second fires. Rebind R in
Options > Controls > Key Binds. There is no Orbital Remote any more (0.5.9): a Remote left in an old world's inventory
loads as an empty slot, does nothing and breaks nothing.

**Leaving the world mid-strike ends the strike** (`left_world` in lib.rs): the API has no leave hook, so the mod takes a
tick with no player, or a world clock more than `SAME_PLAY` ticks off from the last one, as having left. The strike,
every world change waiting and its cleanups are dropped there (nothing carries into the next world), and the strike's
forceload removes, kept in storage as it fires (`FORCELOADS`, `hold_forceloads`: each with its dimension, and the clock
span it ran in), are run the next time that world is played (`release_held`, ~2 s in, when the clock falls in that
span). `/orbital left-world` is the same for a host that knows when the player leaves (the native glue, on
`client_level_unload`). **Pausing** needs nothing of the mod: the game doesn't tick while paused, so the strike's clock,
its edits and its pass stand still, and the game pauses and resumes every sound. **The game's own sounds keep playing
after Save and Quit to Title** (the fork's and upstream's `leave_server`, which single player leaves through, doesn't
stop them; `finish_close_world`, which does, is skipped): an engine bug the mod can't reach.

`play.sh` finds things through `HORIZON_ORBITAL` (the folder with the fork's `horizon-client` and `horizon-ctl`; default
`~/horizon-orbital`), `HORIZON_RESOURCES` (prepared resources; default `.local/horizon-client/26.3` beside the build)
and `HORIZON_HOME` (the game folder; default `~/.local/share/horizon`).

The game's control tool works on this build too: `horizon-ctl state`, `horizon-ctl command "orbital give"`,
`horizon-ctl key r tap` (opens the wheel with the designator in hand), `horizon-ctl screenshot out.png` (without the mod's post pass), and
`horizon-ctl record out.mp4 60` / `horizon-ctl record stop` (the finished frames, effects included; F1 hides the HUD).

## Layout

- `mod/`: the mod (Rust for `wasm32-unknown-unknown`): `src/lib.rs` hooks, designator and strike playback,
  `src/lasers.rs` the lasers, `src/strike.rs` a strike's plan (`src/strike/crystal.rs` the Crystal Bloom's, `src/strike/sinkhole.rs` the Sinkhole's, `src/strike/payload.rs` the Payload's, `src/strike/nuke.rs` the Nuke's, `src/strike/rod.rs` the Rod's), `src/wheel.rs` the wheel, `shaders/strike.wgsl` the post
  pass, `shaders/downfall.wgsl`, `shaders/planetkiller.wgsl`, `shaders/crystalbloom.wgsl`, `shaders/sinkhole.wgsl`, `shaders/payload.wgsl`, `shaders/nuke.wgsl` and `shaders/rod.wgsl` the
  Downfall's, the Planet Killer's, the Crystal Bloom's, the Sinkhole's, the Payload's, the Nuke's and the Rod's own passes (the
  mod appends each to `strike.wgsl` up to its `fs_main`; `pass_of` in lib.rs picks a strike's),
  `horizon-mod.toml` the manifest (api 0.2 with `registries` for the content).
- The Supercell: `src/strike/storm.rs` its plan (bolts, pits, finale crater, fire sweeps, `sc_table`),
  `src/strike/vortex.rs` its funnels as reusable pieces for a tornado (`Funnel`, `wander`, `vx_words`, `scour`, `roar`),
  `shaders/supercell.wgsl` its pass (the vortex section `vx_*`; FAST's `[half stage]` as the Payload's).
- The Supervolcano: `src/strike/volcano.rs` its plan (the bombs, the land's height), `src/strike/vc_land.rs` its land,
  `shaders/volcano.wgsl` its pass (preview views `vc*`).
- The Hurricane: `src/strike/hurricane.rs` its plan (the land's read and edits, the trees, the rings' colours, the mobs,
  the landings: `tree_landing`, `hu_landings`), `src/carry.rs` the player's carry, `shaders/hurricane.wgsl` its pass (`hu_debris`, `hu_trees`,
  `hu_volume`; FAST's `[half stage]`). Preview views `hu*` (`hustrip=1` takes the preview's trees away as the front
  reaches them); `hu_write_table` (ignored) writes its table over the preview's wooded land.
- `orbital-laser-mod/` (items, models, textures, names) and `orbital-sounds/` (the sounds): the mod's content.
- `orbital-laser-shader/`, `strike.py`, `themes.py`: 0.1's setup for stock Horizon (`install.py --legacy`).

## Things that will bite you

- **Nothing happens in the game:** it's stock Horizon. Start it with `./play.sh`. Options > Mods shows the mod's status
  and, if it stopped, why.
- **The game keeps its saves and options in the folder it starts in** when started with `--game`: `play.sh` starts it in
  the game folder for that reason. Starting it elsewhere makes a fresh, empty game folder there.
- **The mod's post pass is plain WGSL after the fork's mod pass prelude** (`tools/wgslcheck/prelude.wgsl` is a copy). A compile error
  is logged ("a mod's post pass did not compile") and the pass is skipped. Validate with `tools/wgslcheck`. A laser's own
  pass is strike.wgsl up to its fs_main less `[lasers pass only]` and the Mothership's ship (`[mothership]`, ~36 KB),
  which only an own file saying `// [uses the mothership]` (the Downfall's) keeps: passbuild.rs, check-shader.sh and
  preview.py all build it so.
- **The mod's post pass reads `mod_data`** (`render.set-data`, binding 5 of the prelude): the Crystal Bloom's pieces'
  rest heights (word `i * 16 + k * 2 + half`) and from `CB_TAB` (1024) its spires and pieces, worked out once by
  `cb_table` in `strike/crystal.rs`; keep that layout in step with the pass's `CB_*` offsets. `tools/preview` binds it from `$PREVIEW_DATA` (`index value` lines) and
  draws hills with `hills=H`; `cb_dump_slope` (ignored test) writes a matching data file and voxel files.
- **`world.surface-height` answers a tick or two later** (`mod/src/ground.rs` keeps the answers; a stage asks, a later
  one reads). In the tests `ground::set_test` answers at once; with none set the pieces lie as on flat land.
- **`world.read-columns` answers the same way** (`mod/src/columns.rs`; `Act::Read`): the Sinkhole reads the 24 blocks
  under every pit column's world-surface top as it starts, and `strike/sh_land.rs` works them out ~3,000 columns a tick
  (material names to colours in `MATS`, the game's textures' averages, grass and leaves tinted by the biome tints the read answers with; packed three words a column at `SH_GRID` of `mod_data`; keep it in step with
  `sh_colw`/`sh_cell` in `shaders/sinkhole.wgsl`). In the tests `columns::test_answer` answers at once; the preview's
  land is `synth_column` in `strike/sinkhole.rs` (`SH_LAND=0` leaves it out). For a local mod build against an
  unreleased fork API, point the SDK at the fork with an uncommitted `mod/.cargo/config.toml` `[patch]`, and never
  commit `mod/Cargo.lock` while it holds that path.
- **The Payload's pass has a half-size stage** (QUALITY FAST): between `// [half stage]` and `// [end half stage]`
  at the end of `shaders/payload.wgsl`, `fs_half` (the column, the trail, the dust and the pieces' smoke, as
  premultiplied colour and transmittance, marched to alternately the nearest and the farthest depth of each two by two
  pixels; beside it the ray's length, the column's distance and whether debris is near) and `fs_join` (a joint
  bilateral upsample against the full-size depth, then the sharp parts: the flash, the object, the pieces' glow, the
  debris, the lens). Both call `payload(in, stage, ...)`, stage 0 the whole pass (fs_main), so FULL's look is the same
  code. The pass declares the fork's bindings 6 and 7 itself (the prelude doesn't), so the source compiles on every
  fork; `payload_pass` in lib.rs drops the section for FULL. `tools/preview.py payload T --quality both` shows FULL and
  FAST side by side (`--whole`: FAST as a fork without the stage draws it). The Planet Killer, the Crystal Bloom and
  the Sinkhole could take the same split.
- **A call into the mod has a fuel limit** (a tick 50 million WebAssembly instructions, a frame 10 million; past it the
  game stops the mod for good: "it took too long"). `mod/src/meter.rs` counts each call's work (the loops that do the
  heavy work `spend`), and what can wait (a stage, a job of the Nuke's, an edit, a command, an answer taken in) waits
  for the next tick once it reads `SOFT`; a stage counts at least `STAGE_COST`. Keep any one stage well under a tick:
  split it rather than let it grow. The fork's `mod_soak` example (`cargo run --release -p horizon-mods --features
  fuel-trace --example mod_soak -- COPY_OF_dist/orbital N SEED`, `SOAK_LASERS=nuke`, `SOAK_TRACE=1`) plays the real
  mod.wasm headless and prints every hook's worst fuel; `stress::thousands_of_strikes` (ignored) plays fire, stop and
  re-fire sequences through lib.rs's own playback natively. The game logs a call that uses half its fuel, and on a
  stop which hook and the mod's stack. Both play targets far off on land not loaded (the far terrain's LOD: only the
  player's surroundings loaded, the target's chunks coming slowly or never once forceloaded), the player up to 1000
  blocks away, and stops in the first seconds and round the burst; `mod_soak` fails any call over half its fuel
  (`SOAK_MAX`). The meter can't see work it isn't told of: the native soak (release) fails a tick that takes more
  than 3 ms past what its counted work explains (`thousands_of_strikes`). Never scan everything left (columns not
  loaded, jobs, rings) each time a stage asks what's ready: keep it O(what's due). The Nuke's land waits for columns
  not loaded, asking again a ring at a time, and goes in late as they come; it leaves out what never loads (logged
  `nuke: N columns of the land never loaded`).
- **A mod has 64 MB of linear memory, and it never shrinks**: past it an allocation fails and the game stops the mod
  ("it crashed (a panic)", in `cabi_realloc` as often as not). `mod/src/mem.rs` counts what's held; the log says
  `memory: strike's peak ...` as a strike ends and `memory: heap ...` as the heap grows, a warning past 48 MB (which
  `tools/game_check.py` fails). What the world answers lands in the mod's memory all at once, so bound what's asked
  before it's taken in; `a_supervolcano_stays_in_its_memory` holds the Supervolcano to it.
- **Single player's clock is the server thread's**: the client counts on by itself between the server's `SetTime`, so
  a server running behind puts the client's clock back when its word comes (and a client that hung sees it jump on).
  `in_world` allows for that (`SAME_WORLD`, a minute); it isn't a sign of having left. The log says the clock moved.
- **`mod.wasm` imports must match the manifest's capabilities**; `cargo horizon-mod build` checks this.
- **A strike's world changes go through a budget**: at most 20,000 blocks and 400 commands a tick (`BLOCK_BUDGET`,
  `CARVE_CMDS` in lib.rs); the rest wait. Thousands of small commands in one tick hitch the game as much as too many
  blocks. `carve_queue` prints a laser's busiest ticks and commonest commands. Those count commands only: the Crystal
  Bloom's (and much of the Planet Killer's) land goes through `world.edit-blocks`, outside that budget; its
  `cb_edit_profile` ignored test prints its edits' busiest ticks.
- **Block edits are paced by the frame time** (`mod/src/pace.rs`): every chunk an edit changes is resent whole to the
  client, so a wave costs the frame per chunk, which grows with its radius (`nk_wave_profile` prints the chunks per
  quarter second). Edits wait in order and go in as fast as they are due while the frames are quick; while the
  smoothed frame time runs long (over 25 ms and 1.4 times what it was before the edits) fewer go in a tick, down to a
  floor. A landed piece's edit never waits, and `Act::Spare` (the forceload removes) waits for the edits. The log
  says `block edits paced: the last went in N s late` when they were held back.

## Verifying work

Shader: `tools/check-shader.sh` prints `OK` (every pass: the prelude + `mod/shaders/strike.wgsl`, the Downfall's, the
Planet Killer's, the Crystal Bloom's, the Sinkhole's, the Payload's, the Nuke's, the Rod's, the Supercell's and the
Hurricane's, each also at QUALITY FULL where it has a half-size stage). Mod: build, install, `./play.sh`, one
strike with terrain off, then one with terrain on in a throwaway world; the chat stays empty and the shaft reaches
bedrock. See [CONTRIBUTING.md](CONTRIBUTING.md).
Around every in-game strike run `tools/game_check.py mark` before it and `tools/game_check.py watch` (or `check`)
during and after it: if it reports the mod stopped (out of fuel, a panic, a failed start), the run failed, whatever it
looked like.
