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
  in bursts at 16-28 s and 43-46 s (bright full-screen flashes: a photosensitivity note goes with it in docs/LASERS.md and
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
- **The Supervolcano** (`strike/volcano.rs`, `strike/vc_land.rs`, `shaders/volcano.wgsl`; 88 s, reaches 1000, the vent moved
  to at least 1,000 blocks in front of the player by `vc_vent` (`VC_NEAR`), `fire` in lib.rs; its beats `VC_*` in
  volcano.rs, which vc_sound.rs and vc_mount.rs take theirs from: keep volcano.wgsl's, volcano_mount.wgsl's `VM_SWELL`,
  `VM_HUSH`, `VM_ERUPT` and tools/sounds_volcano.py's in step): an orbital laser satellite over the
  vent (`vc_opening`, `vc_sat0`: 7,000 up, 1,600 beyond the vent from the player, table words 2-3, drawn up to 3.4 times its
  size far off, scaled from where it parks so it shrinks as it leaves: `vc_sat_k`; built of blocks in `vc_sat_hit`: a
  gold-foiled bus and engine, white radiators, a gold collar, roll-out solar arrays on a truss turned to the sun
  (`vc_sat_wing`: rolled up as it comes, out from 3.2 s, back in from 7.5), an octagonal barrel
  ringed by four coils stepping in to the emitter, four prongs; from the ground, nearly down its barrel, a dark cross with
  a glowing eye) falls in down a slant from 1,900 higher, 1,000 along its orbit and 1,500 nearer the player (so it is seen
  coming down their sky), steadily to 1.3 s (`VC_IGN`), then brakes on its four jets (fired down its barrel), hardest
  late, to a soft stop at 3.4 s (`VC_ARRIVE`), sagging past its station and back (`vc_sat_go`, `vc_sat_thr`). Its tilt
  is flown by a control loop, never a sine (`vc_sat_att`: `VC_SAT_TAB`, written by `tools/vc_sat_motion.py`, a rigid body
  pushed only by its actuators, through lag, with the ignition's kick, a thrust misalignment and slosh pushing back): it
  comes in 26 degrees off and turning further, its top-corner thrusters stop that and swing it round as it falls; the
  jets, gimballed by what the loop turns it with (they swing a tenth of a second before the body follows), heave it over
  unevenly as they brake it; as the burn dies its thrusters trim it onto the vent in discrete pulses (a tenth of a second
  each, sized to the push) while its arrays unroll; its wheels hold it still from 3.8, settled by the lock. It aims a solid
  red targeting beam (3.3 s, locked at 4.0; its coils lit red), its coils charge
  outside in and it fires at 4.5 s (`VC_HIT`), a white-hot beam melting a round glowing hole (`vc_open_land`, light only)
  cut at 7.1 s (`VC_OFF`); it rolls its arrays in, kicks its jets at 8.6 (`VC_BURN`) and lifts straight up and away,
  into the haze by 12 (never a fade on the spot). Steam surges off the hole as the beam is cut and is fed in
  uneven surges (noise, never a beat), red from under (`vc_plume`, `vc_feed`), until the eruption: as steam off a real
  vent, never a cone or a funnel. A tube round a path (`vc_path`: rising, slowing, taken up by a 34-a-second wind, so
  straight up off the hole and then leant over and carried off), a point taking the age of the nearest point on it; clear
  just over the hole, a puff a surge and necked in the lulls (merging as it spreads, or they draw stacked slabs), each puff
  a rounded cap (what was let go together lies on a dome), wandering, mixing away by age to ragged lumps and then nothing.
  Its lumps are domes on domes (`vc_dome`) riding it: across it from its middle, along it by how far along it was a moment
  ago on a fixed slant (a turning axis swings the lattice into streaks; world position over a growing scale smears it),
  the moment let go of now and then (two such half a cycle apart). Lit through a ball round it as thick as what lies the
  sun's way along it (the cap of a surge under thin vapour lit), creases darker. Preview views `vcsteam`, `vcmid`,
  `vcopen`, `vcsky` and `vcplume` (the whole of it level from 1,000 off); the mount rising round the hole; the
  tremor, the ring cracking at 6 s (`VC_CRACK`) with wisps of steam, the mount swelling from 7 s (`VC_SWELL`,
  vc_mount.rs, volcano_mount.wgsl) and stopping dead at 17 (`VC_HUSH`), the eruption at 18 s (`VC_ERUPT`, the mount's
  white-out for under a second, a flash along the ring and a
  pressure ring at the speed of sound), a ring of vents 560 across feeding a column to about 1,800 (`vc_col`: the
  ring's foot follows the land, `vc_land`, a heightfield of 128 x 128 cells; lumps on lumps, `vc_lump_col`, drawn out and
  rushing low down by the height they are looked up at), 64 lava bombs from 19 s to 36 (`vc_bombs`, solved against the land,
  their smoke at half size, their heads sharp; each landing leaves a small real crater, counted from each column's
  ground so it needs no read), lightning from 26 s (`VC_LIGHT`, `vc_flash`, a slot of 0.13 s, in the plume, then in rings
  through the sheet from about 36, thinning out from 60 and gone by 80; `vc_bolts`), the umbrella spreading from 28 s
  (`VC_SPREAD`, `vc_umb`, out past the horizon, Hunga Tonga's ripple `vc_ripple`), the sky dark by about 44 s (`vc_dim`:
  land and sky darkened by what the sheet shuts out, `vc_sun_t`, `vc_sky_t`, what glows left glowing; the game's clock
  and weather never touched; the player's hand and held item, which the game draws after the post pass, darkened and
  browned with the land where they stand, near black in the wall of ash, lit by the white-out, the eruption's flash and
  the lightning near them: `strike/vc_hand.rs`, a `HandLight` its plan gives as `Act::Hand`, mirroring `vc_dim`,
  `vc_flow`'s depth past the front and `vc_sound::flash`, worked out a tick at a time and eased each frame by lib.rs's
  `hand_frame` through the fork's `render.set-hand-tint`, given back as 1, 1, 1 when the strike ends, is stopped or the
  player leaves; keep it in step with the pass; OFF for now, `HAND_TINT = false` in lib.rs, as it went far too dark in
  the game, its test ignored), the collapse at 50 s (`VC_COLLAPSE`; the lumps slow,
  stop and fall back, `up`, the top of what stands falling, `Hb`), the wall of ash from the ring (`vc_flow`, `vc_front`:
  60 blocks a second slowing to 25, at 500 from the vent by about 54 s and 1,000 by about 66, looked up round the vent
  so its lumps travel with it without smearing, `vc_lump_flow`, the lattice wrapped round the circle; its base lifting
  off the land behind it into new clouds from 66 s, `VC_LIFT`), the player engulfed (near black, embers, `vc_specks`),
  then a dim world under falling ash, the sheet thinning from 80 s (`VC_RED`) to a blood-red sun, all gone by 88
  (`thin`). FAST's half stage holds the cloud and the bombs' smoke.
  **The shaking** (volcano.rs, the game's `render.shake`; the pass's `vc_jolt` adds the tremor and the eruption's front on
  the picture): a tremor from the shot building to the hush, nothing in the held breath; through the ground at
  18 + d/1715 s a hard jolt and a bigger heave 0.4 s on; the report's arrival; small jolts under the column to the
  collapse; the collapse; then the ash flow, building over its last 8 s as it comes, the blow as its lobes reach the
  player (`vc_sound::front_at`, so the picture, the sound and the shake agree), and 14 s of ragged shaking inside it with
  heavier gusts, easing as it thins; with KNOCKBACK on, the wall's shove (`Act::Shove`, 0.7 out and 0.4 up, none past
  1,500 from the vent).
  **Its sounds** (`strike/vc_sound.rs`, `tools/sounds_volcano.py`, whose docstring is the timeline; everything from the
  vent late by the distance, through the ground five times sooner; where the player is asked again as each part comes
  due): the satellite on the strike's clock from 0 (`sat_sky`, "the sky sings": a vast low horn, a second voice beating
  beside it from the aim pulled into one at the lock, the shot a driven braam with a sub blow, sagging a tone at the cut)
  and the shot's blow off the land late by the distance (`sat_land`); the mount from 4.5 s (the tremor, cracks through the
  ground, rock grinding underfoot within ~900, rockfalls, the fountains, the steam), all of it on the strike's clock and
  stopped dead at 17 s with the picture; then `hush` (a deep pressure swelling, never silent) and `seism` (the burst
  through the ground) until the report cuts them, the blast's front (`front1-4`, the longest that starts no sooner than
  the seism) swelling into the report (`report`/`report_far` cross-faded by distance), `boom` under it (the Nuke's ALT
  blast slowed with the Payload's ALT front: its weight), `report_sub`, the column's roar; the bombs (a whistle, a real
  impact and the stones it throws only near the player, `NEAR`; a dull thump further off); the lightning's thunder
  (`lt_crack` within 500, `lt_clap` to 1,800, `lt_roll` past it, `lt_rumble` for a flash in the cloud: the Hurricane's
  thunder files made louder, falling 2.5 dB a doubling of the distance, claps within 0.2 s one, none heard for 8 s after
  the flow hits); the collapse and the land's drop 3 s on; the flow rising to its hit (`flow_rise1-3`, trees and rock in
  its front within ~140), `flow_hit`, then inside it (`flow_in1-3`), or `flow_far` if it stops short; `after` and
  `patter` to the end. Every file ends by 88 s; `vc_sound_*` tests hold it to that and to sounds.json.
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
- **The Fold** (`strike/fold.rs`, `strike/fold_land.rs`, `shaders/fold_warp.wgsl`, `shaders/fold.wgsl`; about 64 s, its clock starting at -4, `Strike::wait`; reaches 1000 blocks; needs the
  fork's `render.set-warp`, `render.hold-world` and `render.hold-world-within`, release `orbital-mod-api-11`): a crater about 530 across on the crease pattern (corners out to ~353), a shaft to bedrock, the land charred
  to ~400 and rubble to ~404, every mob and item within 360 killed and the ~2,000 chunks within 410 force-loaded; its land goes in from 27 s, behind the hold, and is done by the first bang at 44.1 s.
- **The Tsunami** (`strike/tsunami.rs`, `strike/ts_sounds.rs`, `surge.rs`, `shaders/tsunami.wgsl`; 42 s, reaches 1000
  blocks) digs no crater: it sweeps a swath. A wave (320 high out at sea, ~145 over the target's ground at the land, a
  closed-form model, `TsGeo`, kept in step with the pass) crosses the land, and under its water a swath about 700 blocks
  across (345 each side, thinning from 255 out), from 300 upstream of the target to 160 past the player and at most 720
  past the target, loses every tree, plant and building: trunks are left as stumps of 1-3 logs, buildings as footings
  of up to 3 blocks, the soil is scoured to mud, packed mud, coarse dirt, gravel, sand and clay in streaks along the
  flow, channels are gouged up to 5 deep, and wreckage, a wrack line and timber in the trees at its limit are laid down.
  Up to 36 boats are summoned, every mob and item in each chunk is killed as the water gets there (not players), and
  real ponds are left in the hollows, up to 3 deep (`ponds`, a priority flood a 64 by 64 tile at a time; the
  `no_pond_leaks` test holds any land to it). Chests and the like, and what `stays` names, stay where they are. The
  ~2,200 chunks of a strike from 300 blocks (~1,600 to ~2,900, by how far off the player stands) are force-loaded from
  the start, and each is read and edited once, as the crest has passed it (`ts_chunk`, through `world.read-columns` and
  `world.edit-blocks`). With the knockback on the player is carried in the water (`world.carry-player`, as the
  Hurricane's), surfaces at `SURF` (6.5 s after it took them) and is set down 2 over where it took them, facing the
  wreck, with a small throw (`Surge::set_down`, `world.push-player` while carried) that keeps the game from putting a
  creative player back into flight, unless they were flying when it took them; sneak held half a second breaks free. **Photosensitivity:** the blow as the water takes the player is one white
  flash over the whole picture, about a fifth of a second.
- **The Sky Breaks** (`strike/skybreak.rs` the plan, the crack pattern, the panes and the table, `strike/sb_lift.rs` the
  opening, `strike/sb_hand.rs` the hand, `strike/sb_lodge.rs` the panes as blocks, `strike/sb_sounds.rs` the sounds'
  schedule, `shaders/skybreak.wgsl`; 49.5 s, reaches 1000 blocks; laser index 17, pass 13, the wheel's fourth page;
  plays natively since 0.5.17). No beam and no knockback. A disc of the land round the target
  (`LF_R`, 7, its edge ragged) cracks round its rim and tears free: its real blocks are read (`world.read-columns`) and
  taken out of the world at 0.55 s (`LF_CUT`, `world.edit-blocks`: a hole up to 14 deep in its middle, 3 at its edge;
  terrain off, they stay) and the pass draws them as an island in the game's textures, rising into the sky (its pane 560
  over the target's ground, `SB_H`) and sinking into it by 5.15 s (`LF_IN`); the sky rings, a hand presses on it from
  behind (`LF_PRESS`, 7 s) and its fist punches through at 9 s (`SB_CRACK` = `SB_LEAD` + 0.25): `SB_K` (15) radial
  cracks across the whole sky in a tenth of a second, forks and short chords between them (`Mesh`), the shattered
  middle blown down. An eye (`SB_EYE_R`, 78) slides into the hole (12-14 s), opens, finds the player (`SB_LOCK` + 0.45),
  blinks at 30.15, flares at 35.1 (`SB_FLARE`, `HD_FLARE`), turns away and shuts. From 16.75 s (`SB_FIRST`) up to
  `SB_NS` (7) panes break free 1.45 s apart, each falling ~5.3 s (`SB_FALL`) and lodging as real blocks (`sb_lodge.rs`,
  terrain on: lying low, `SB_LOW` to `SB_STEEP` degrees, `SB_BURY` of its length in the ground, its sky on top in blue
  ice, packed ice and snow, obsidian under; everything standing within 30 of it plus half its length gone and the trees
  felled for `SB_FELL` (32) more; 26 falling blocks thrown and mobs and items within 70 killed at each), their sites at
  least 118 apart and 120 plus their reach from the player; one on land that never loads, or that would come down on
  the player, stays drawn. The fist is thrown down through the hole at 36 s (`SB_DOWN`) and slams the land on the target
  at 37.5 (`SB_PRESS`): a bowl about 135-145 across (`SB_BOWL` 24 by 25.5 times `SB_SC` 2.8, ragged by a tenth) and 20
  deep (`SB_BOWL_DEEP`), falling in broken steps to the fist's print (the knuckles' dents, the middle one about 34 under
  the land: keep `HD_KNUCKLES` in step with the pass's `hd_knuckle`), the print obsidian, blackstone and crying obsidian,
  the earth heaped round it out to 1.4 radii (`SB_RIM`), everything standing swept off and the trees laid flat for
  `SB_BAND` (24) more; water dug like any block, the lava it bares sealed to magma; 44 falling blocks thrown, mobs and
  items within 125 killed. Its chunks are read and made from 32.8 s and let in from the slam, the middle first, paced
  (pace.rs). The slam's shockwave and dust wall run out over the land; as the front reaches the player the camera jolts
  as the Payload's does (`payload::pl_jolt`) and muck lands on the lens (`hd_lens`). The middle's last ring is knocked
  loose at 37.72 (`SB_KNOCK`), the arm lifts at 38.9 and is gone by 42.6, the sky heals over 40-46.5 (`SB_HEAL`,
  `SB_HEALED`). Force-loads the chunks within 152 of each pane's site (`SB_PATCH`) and 145 of the target from the
  moment it fires (`sb_load_rows`), let go a second before the end. **Photosensitivity:** the punch at 9 s is a
  blinding flash where the sky breaks and the whole picture's light jumping for a fraction of a second; each pane's
  impact brightens the picture a moment; the eye's flare at 35.1 s is a glare through the hole fading over about a
  second; and as the slam's front passes the player the picture greys over with dust for under a second.
- **The Carpet Bomb** (`strike/carpet.rs` the plan, the land, the table and the sounds' schedule (`cp_sounds`),
  `shaders/carpetbomb.wgsl`, `tools/sounds_carpetbomb.py` the sounds; 37.5 s, reaches 1000 blocks; laser index 18, pass
  14, the wheel's fourth page; plays natively since 0.5.17). No beam. A bomber (a silhouette
  in the pass, flying the line's way at 170 blocks a second, `CP_PLANE_V`, 632 up, `CP_HB`) comes out of the haze from
  0.3 s (`CP_APPEAR`), lets the stick go over 1.8 s from 4.4 s (`CP_RELEASE`, `CP_RIPPLE`) and flies on past the player.
  The stick (`CpGeo`) is `CP_N` (13) bombs on a line coming in 32-40 degrees off the way the player looks, 22 blocks
  apart (`CP_SPACING`), striking from 7.0 s (`CP_T0`) 0.52-0.68 s apart (`CP_GAP`), the last 1.0 s after the twelfth
  (`CP_LAST_GAP`): on the target, but at least 100 (`CP_MIN_ME`) from where the player stood, its size 1.55 (`CP_BIG`),
  the others about 1. Each bomb's land is worked out on the land as the bombs before left it (`Land`'s state: a
  crater never filled by the next one's rim, a log laid by one not swept off by the next), in a window of its own from 2 s
  before it strikes (the last's 2.6 s, `CP_LEAD`), its rows in `CP_PARTS` (6) stages (the last's 40), and goes in as
  its front reaches each column (`Blast::wave_at`). A small bomb digs a crater about 25 across and 8 deep (`crater_r`
  12.5, `crater_d` 8 a size: the next ones' overlap it into a ragged trench), its rim heaped, sweeps everything standing
  off to 35 (`flat_r`), fells the trees lying pointing away out to about 50 (`band_w` 15 more), chars the grass to 55
  (`char_r`), strews 60 pieces of rubble and throws 24 falling blocks, and kills every mob and item within 40 (`kill_r`).
  The last: a crater about 65 across and 16 deep (21 and 10.6 a size) with terraced walls (`bowl`: three-block steps), a
  heavy rim with 8 fires left on it (on netherrack, nothing that burns within two blocks), flattened to 110, felled to
  150, charred to 170, 320 rubble, 120 falling blocks, every mob and item within 124 killed, the Nuke's jolt
  (`nuke::nk_jolt`) and a shove (`Act::Shove`, 0.75 out and 0.5 up to 320, KNOCKBACK). The small ones' jolt is the
  Payload's (`payload::pl_jolt`). The land is read (`world.read-columns`, `PL_BELOW` under each top) in 16 parts
  (`CP_READS`, asked four a stage) within each blast's reach; the chunks within each blast's reach plus 4 (about 61 round
  the small ones, about 176 round the last; some 500 chunks for a straight line) are force-loaded from the moment it
  fires (`cp_load_boxes`), let go a second before the end. **Photosensitivity:** each blast is a quick flash with an
  orange glow through the smoke and dust for about a second (`cp_lights`), thirteen of them half a second apart; the
  last one's flash is brighter and lights the land round it, and a pale condensation flash races across the land with
  its shockwave.
- **The World Eater** (`strike/worldeater.rs` the plan and the per-tick hand, `strike/we_path.rs` the path, `we_land.rs`
  the land, `we_land_hunt.rs` the hunt, `we_land_catch.rs` the catch, `we_fx.rs` and `we_body.rs` the pass's tables,
  `we_sounds.rs` the sounds' schedule; `shaders/worldeater_path.wgsl`, `worldeater_body.wgsl`, `worldeater.wgsl` and the
  world warp `worldeater_warp.wgsl`; `tools/sounds_worldeater.py`; laser index 19, pass 15, the wheel's fourth page; plays
  natively since 0.5.17). No beam: a
  worm 68 across (`WE_R` 34) and 1836 long (`WE_LEN`) on a path that is data (a chain of arches, each with its own
  breach hole A_i and dive hole D_i, joined by underground runs: `we_holes`, `we_runs`, `we_tunnels`). **It acts on the
  player.** HUNT (the default, `/orbital worldeater hunt|scripted`, the wheel's TAKE row; up to 90 s, `WE_HUNT_LEN`):
  the wormsign's run from 420 off (`WE_SIGN`) to the target, out of it at 9.0 s (`WE_BREACH`), then two or three hops
  (the seed: `hops`; spans 130-230, `Kind::Hop`) and the big arch (spans 170-320, 230-270 high, held 2 s round its top),
  each appended to the path 1.6 s before the arch before it comes down (`decide`), aimed at where the player is then,
  on land that is loaded (`scout`), its run 160-600 long (`WE_RUN_MIN`, `WE_RUN_MAX`) at depth 80, every hole 110 from
  every other (`KNOT_GAP`), at most 6 arches, the last in by 52 s. It swallows the player (`Catch`) if the jaws come down
  within 47 of them on the last planned dive (HUNT only), or the head comes up within 42 of them on a breach (either
  take), but only with KNOCKBACK and terrain damage both on (`decide`, `breach_catch`): they are drawn in over 1.4 s
  (`SWALLOW`), carried along the run behind the head through the fork's `world.carry-player` (at most 64 a second,
  `CARRY_V`; a run carrying them at most 320, `RUN_CAUGHT`), out through the mouth at the next breach and thrown
  (`THROW`), landing clear of the hole (a breach's catch: held 26 under it for 2 s, then up and spat along an arc 64
  out, 30 up); one more small arch (`Kind::Spit`) if the catch was on the last bite; Resistance V for a survival player
  from the swallow; a stopped strike puts them on the land beside the hole (`WeHand`'s `drop`). SCRIPTED (46 s,
  `WE_LEN_S`): one arch across the player's view, out of the target at 9.0, held 12.5-14.5 (`WE_BELLOW`), into the land
  260 off (`WE_SPAN`) at 19.0 (`WE_BITE`), the tail in at 31. Knockback (`Shove`, KNOCKBACK): the first breach 0.7 out
  and 0.5 up to 300, the others 0.5/0.4 to 220; the big bite 0.9/0.6 to 420, the others 0.55/0.4 to 230; jolts with
  each. What it does to the world (terrain on; `we_land.rs`): each breach hole 40 in radius (`R_BREACH`) and each dive
  hole 45 (`R_BITE`, caving to a funnel of 60, `RF_BITE`) open to bedrock, dug from the middle out over 2.6 s (`DIG_T`),
  walls darkening downward, water and lava in them sealed; a breach heaps a rim (6 high at the first, 4.5 after) out to
  112, fells the trees to 120 lying pointing away and throws 110 falling blocks and 5 trees (80 and 3 after); a dive
  fells to 80; sculk creeps out round each; the land over every run (the first from the wormsign's start) bucks as the
  head passes (`buck_run`) and, once its tail has gone in, sinks ring by ring into a trench 50 wide and 25 deep
  (`TR_W`, `TR_D`; `watch`, `sink`), lakes and rivers left with a dam of ground beside them. Mobs and items within 110
  (`KILL`) of each hole and along each line are killed; the chunks within 130 of each hole and 64 of each line are
  force-loaded as each arch is planned (`LOAD_KNOT`, `LOAD_LINE`), let go at the end. The land is read
  (`world.read-columns`) round each hole (124, `SITE_R`) and along each run, and goes in through `world.edit-blocks`
  split by the tick it is due. At QUALITY PERFORMANCE the land's dressing (sculk, what hangs, felled logs, thrown blocks)
  is left out and the falling blocks capped (`fallgov.rs`). **Photosensitivity:** hard jolts at each breach and bite;
  being swallowed turns the picture black for about 0.7 s (the dark beat), then carries the view fast down a glowing
  tunnel for several seconds and throws it out.
- **The Convergence** (`strike/convergence.rs` the plan, the land, the table and the sounds' schedule (`cv_sounds`);
  `shaders/convergence.wgsl`, `convergence_sky.wgsl`, `convergence_ground.wgsl` and `convergence_cracks.wgsl`;
  `tools/sounds_convergence.py`, its explosions `tools/sounds_cv_blasts.py`; 60 s, reaches 1000 blocks; laser index 20,
  pass 16, the wheel's fifth page; plays natively since 0.5.17). No beam. Everything is split along a seam through the target, laid along the line from the
  player to it (`cv_face_seam`, `cv_seam`, `cv_side`): one half Nether, the other pale (the Aether). The omen (0-5 s):
  seven cracks (`CV_CRACKS`, out to 33-50, `CV_CRACK_R`) drawn by the pass only, a seam of light high over the target.
  At 5 s (`CV_BREAK`) the cracks open into real fissures (2-6 deep, magma at their foot, 5.3 to ~9.3 s), netherrack
  creeps along veins to 62 (`CV_VEIN_R`), sixteen basalt clusters rise on the Nether half 14-56 out (`CV_PILLARS`), and
  a rift opens in the plane 260 over the target's ground (`CV_RIFT_Y`, radius 80, `CV_RIFT_R`), the sky going dark and
  split red and blue along the seam (`cv_dusk`, `cv_grade`). A fountain of fire 30 high from 6 s (`CV_RED0`,
  `CV_RED_STUB`), a stub of light 36 long under the rift from 7.5 (`CV_GOLD0`, `CV_GOLD_STUB`); both fire at 12.45
  (`CV_FIRE`) and strike each other at 13 (`CV_MEET`), 130 over the ground (`CV_MEET_Y`), a shell out at 240 a second
  (`CV_IMPACT_V`) and a jolt as it reaches the player. Six surges (`CV_SURGES`, 14.4-22.2 s), each a ring (160 a second,
  `CV_RING_V`) and a jolt; the Nether's drive the meeting point up to ~180 (`cv_meet_y`); the land takes sides out to
  100 (`CV_SIDE_R`, 13.3 to ~22.5 s); 36 falling blocks lift toward the rift (terrain on). Drawn down from 23 s
  (`CV_DRAW`) to 14 over the ground (`CV_BURST`); the blast at 26 s (`CV_HIT`): impact frames (`cvg_impact`, three
  frames, a fifth of a second, off with `/orbital impactframes off`: params[15]'s bit 2, as the Rod's), the front at
  343 a second, the Rod's jolt (`cv_jolt`) and a shove (`Act::Shove`, 0.7 out and 0.5 up, none past 450,
  `CV_KNOCK_OUT`, `CV_KNOCK_UP`, `CV_KNOCK_REACH`; KNOCKBACK). What it does to the world (terrain on): a crater 84 in
  radius (`CV_CRATER_R`, edge wandering ~12%) and 42 deep (`CV_CRATER_D`), lined by half (`scorched`: netherrack,
  blackstone, basalt, soul soil, nether wart, magma, fire on its floor; diorite, calcite, andesite, pale moss, raw gold,
  glowstone; obsidian and crying obsidian on the seam, `CV_SEAM_W` 1.6), its rim heaped to 1.5 radii (`CV_RIM`, `heap`:
  up to ~17 high), everything standing swept off to ~190 (`CV_FLAT`) with the trees felled pointing away, a band 40
  wide past it of stripped crowns and trees knocked flat (`CV_BAND`), the grass turned by half in 17 rays to ~220
  (`CV_CHAR`, `CV_RAYS`), rubble to 250 (`CV_RUBBLE`), 240 falling blocks thrown (`CV_THROWN`), 11 basalt clusters round
  the Nether half from ~31 s (`CV_AFTER_PILLARS`), 7 islands grown in the sky from 28.5 s (`CV_ISLANDS`,
  `CV_ISLAND_AT`, at least `CV_ISLAND_CLEAR` 24 over the ground under them); no shaft. Water it cuts into is dug like
  any block; lava in the crater and its rim is dug or cooled (`lava_worked`), past the rim held back; the lava it bares
  sealed. Mobs and items within 200 killed (`CV_KILL`; the kill commands are outside `if terrain`, as the Rod's). The
  ~890 chunks within 260 (`CV_READ` + 4) are force-loaded from the moment it fires, let go a second before the end.
  Its land is read (`world.read-columns`, 36 under each top, `CV_BELOW`) out to 256 in 48 rings (`CV_PARTS`) and goes
  in through `world.edit-blocks` as two waves (`Wave`: the carve with the front, `CV_CARVE_RATE`; the lining from the
  middle once the pit is open, `CV_RATE`), the crater open by ~27.1 s and the land out to 256 by ~32.
  **Photosensitivity:** the impact frames at 26 s are a fifth of a second of hard full-screen cuts in black, white and
  the two sides' colours, then a white-out; the columns' meeting at 13 s is a short bright flash; jolts at the impact,
  each surge and the blast.
- **The Earthquake** (`strike/earthquake.rs` the plan and `EqPlates`, `strike/eq_land.rs` the land, `strike/eq_trees.rs`
  the falling trees and slabs, `strike/eq_ground.rs` the land's heights for the dust and the flier, `strike/eq_fx.rs`,
  `strike/eq_sounds.rs` the sounds' schedule, `src/eq_ride.rs` the player on a moving plate; `shaders/earthquake.wgsl`,
  `earthquake_dust.wgsl`, `earthquake_plates.wgsl` and the world warp `earthquake_warp.wgsl`; `tools/sounds_earthquake.py`;
  50 s, reaches 1000 blocks; laser index 21, pass 17, the wheel's fifth page; in `native_build::HELD_BACK`). No beam:
  the land moves. 0.8 s the crack, the faults cut open for real as it reaches them (`fault_at`, all by 5.5 s); 5.6 s the
  warp on; 6 s the heave; lurches at 8.5, 11, 13.5; the climax at 18.5; still at 21; at 31 s (`EQ_REST`) the moved land,
  written behind `render.hold-world` from 9.6 s, swapped in on one frame. 21 plates in seven bands of three, the four on
  the player's side rising up to 54, 38, 22, 8, the three on the far side dropping up to 38, 14, 5 (`EQ_RISE`); the main
  fault's trench up to 20 wide (`EQ_WIDE`) with a lava lake some 30 under the lowest land (`EqPlates::lake`), up to 10
  slabs of its low lip toppling into it (`find_slabs`, `EqSlab`), up to 21 trees near the player falling
  (`render.set-warp-data`: the warp draws them; the land lays them as logs). Every column within the zone is read
  (`world.read-columns`) and written where its plate rests, a chunk's edits on one tick, the player's chunks last
  (`EQ_RIDER_FROM`); the chunks within about 290 of the zone's middle force-loaded from the fire. A player on a moving
  plate walks it (`eq_ride.rs`: the camera drawn from their plate through `render.set-view-offset`, put where they are
  seen with `world.shift-player` and held with `world.carry-player` until the swap; in flight the view keeps its offset,
  held to the plate only by their height over the land). Knockback (KNOCKBACK) at the heave, two lurches and the climax,
  0.32 out and 0.5 up, none for one riding their plate; Resistance V for a survival player on a plate; nothing killed.
  Terrain off: the plates move the same and go home by 43 s (`EQ_BACK_END`). Land that sinks 8 or more has its own
  biome put under it (`fillbiome`, `biome_stage`), or a cave's biome below would recolour its grass at the swap.
  **Motion:** camera jolts at each heave and hard at the climax.
- **The Six Stars** (`strike/sixstars.rs` the plan, the land, the table and the sounds' schedule (`ss_sounds`);
  `shaders/sixstars.wgsl`; `tools/sounds_sixstars.py`; 58 s, reaches 1000 blocks; laser index 22, pass 18, the wheel's
  fifth page; plays natively too). No beam: a wanted level on the screen. The pass draws six stars
  at the top right (`ss_hud`, lit from the right at `SS_STARS` 1.2-6.95 s, the leftmost last), repaints the whole sky
  as a golden-hour sunset and grades the land (`ss_sunset`, `ss_grade`, the sun swelling a step a star, heat shimmer;
  the game's clock and weather untouched). At 8.2 (`SS_PEEL`) the leftmost star tears out of its slot (`ss_gather`'s
  wind-up from 7.72, a jolt of 0.1 s, a hit-stop to `SS_GO` 8.36, smear frames, a refraction ring `ss_bend`, the row
  recoiling; its sound a quiet glass pop on 8.2, the glass ringing on after, `SS_POP_LEAD`, `SS_POP_VOL`, then the air rushing after it from `SS_FLIGHT` 8.25), flies as a flat icon tracking where it will hang (`ss_fly`) and turns into the 3D star there at
  `SS_CONV` 10.35 (`ss_frame`, `ss_draw`: a voxel star, 12 cells from its middle to a tip, `SS_R` 75, `SS_THICK` 22),
  hanging 520 over the target's ground and 140 beyond it (`SS_H`, `SS_BACK`) from 11.2, falling 11.8-17.0 (`SsGeo::pos`,
  in the table) and landing flat, its first point away from the player (`SsGeo::yaw`). At 17.0 (`SS_HIT`) the
  Payload's column, larger and dark (the billows `ss_puffs`, the column `SS_HC` 340), its dust and debris; the five
  points plough out to `SS_TIP` 170 over `SS_PLOUGH` 2.4 s (`ss_tip`, `ss_piece`), smoke rising along each trench
  (part of the column's smoke in `pl_column`, on the land's heights); the HUD blinks from 19.5 and is gone by 23.6. What it does to the world (terrain on): a five-pointed
  crater (`Shape`, `star_edge`: tips at 170, inner corners at `SS_IN` 60, 40 deep in the middle), lined black with lava
  only where it cannot run and no water lies within six columns (`floor_of`), fires on netherrack in the trenches, the
  white wreck of each point at its trench's end (`wreck`), a black band out to `SS_BURN` 1.42 of the edge, the rim heaped
  to `SS_RIM` 1.22, the land flattened and the trees felled to `SS_FLAT` 225, crowns stripped 40 past it, the grass
  charred in rays to about `SS_CHAR` 255, rubble to `SS_RUBBLE` 268, 200 falling blocks thrown, mobs and items within
  `SS_KILL` 260 killed. The middle is dug as it strikes and each trench as its point reaches it (`Wave`: `plough_t`),
  then lined from the middle out; the ~1,000 chunks within 276 (`SS_READ` + 4) are force-loaded from the moment it
  fires. Knockback 0.75 out and 0.55 up, none past 500 (`Act::Shove`, KNOCKBACK). The wheel's FLASHES row (FULL or
  SOFT, `Rows::Flash`) is the same setting as `/orbital impactframes on|off`; the pass reads it as `ss_soft`.
  **Photosensitivity:** the sun's flare on each star's beat and on the release, each star's flash, the release's flash
  and ring, the impact's flash lighting the land, and the HUD's stars blinking 2.3-2.9 times a second for about 3 s from
  19.5 s; SOFT makes them slow pulses.
- **The Colossi** (`strike/colossi.rs`, `shaders/colossi.wgsl`, assets `mod/colossi/`; 34 s, `CL_LEN`; laser index 23,
  pass 19, the wheel's fifth page; held back natively, `HELD_BACK`) is the one laser
  built from models you hand it: five stone giants 206-230 blocks tall (`GIANTS` in tools/colossi_assets.py; `CL_K` 4.4
  times the first design's 50; the most a block statue can be under the build limit) in a ring 300 out (`RING_R`,
  `RING_DEG`). Each rises in heaves from 0.2 s + 0.2 s a giant over 6.5 s (`T_RISE0`, `T_RISE_STEP`, `CL_RISE_S`; the
  pass's `cl_rise`), stamps a foot 3.2 s times its own lead before each blow, heaves its hammer over its shoulder and
  slams it into the ground in front of it (`slam_point`, 40 of its mesh units ahead of its pelvis): first blows at
  11 s + 0.6 s a giant (`slam1`), then a ragged combined blow rolling over about half a second in an order dealt
  each strike, the last landing at 18 s (`slam2`, `SLAM2`, the pass's `CL_T2`). Each giant moves its own way
  (`CHARACTER`: eager, stiff, showy, brute, wary, dealt round the ring by the target block, `character`; its lead into
  each blow `leads`, its crouch, arch, twist, posture, head, restlessness and reaction: record words 26-34). The cracks
  from the five blows lunge on to the middle in five jolts (`cl_run`, 18-20 s) and meet in a blast at 20 s (`CL_HIT`;
  no beam from the sky, though the sound and the shakes still call that moment `T_BEAM0`); from 20.9 s its light climbs
  each hammer and the arms holding it, which burst at 22.4 s + 0.15 s a giant (`CHARGE`, `BURST`, `BURST_STEP`; the
  pass's `CL_CHARGE`, `CL_BURST`, `cl_tb`; which arm pieces go is `BURST_MASK`, the same masks as `GIANTS`, whose
  `burst` leaves them out of the statues and drops whatever no longer joins the ground). From 0.2 s after its burst
  each goes down on one knee, in three catches, and shudders to a stop at 24.3 s (`CL_SETTLE`): from then the giant
  drawn is exactly its statue. A line sweeps down each from 25 s, 0.3 s apart, 4.5 s each (`T_SWEEP0`, `T_SWEEP_STEP`,
  `CL_SWEEP`; the last done at 30.7 s), only showing the blocks already there. Terrain on: force-loads the chunks in
  the square within 400 of the target (`LOAD_R`, `load_rows`: about 2,600) from the start, let go at 33.5 s; kills
  every mob and item (not players, not falling blocks) within 470 at 20 s (`KILL_R`). **The torn land** round each giant
  (`hv_setup`, `hv_drive`, `hv_chunk`): every column out to ~115 from its feet and round its hammer's strip is read
  (`world.read-columns`, 36 under its top, `HV_READ` 24 chunks a read asked about 1.2 s before its first is due) and
  torn up a chunk an edit from its feet out, 0.4-4.8 s after the giant starts up: everything standing cleared whatever
  its height (leaves a little further, so no crown hangs), the ground broken into plates (`frac`, the pass's `cl_frac`,
  step for step: 9 cracks radiating from its feet, branching, dug 2-7 down and running on past the torn edge; plates
  in staggered rings, each tipped its own way, a fissure 1-2 deep along most of their edges), each plate one family of
  blocks (`HV_FAM`: deepslate, stone and tuff near its feet and at the cracks' lips, coarse, rooted and plain dirt,
  packed mud and gravel further out; sand or red sand under a desert's), the heap (`Heave::terms`, the pass's `cl_mh`)
  on each column's own ground, through any water, in up to 3 lifts 0.6 s apart (`HV_STEPS`, `HV_GAP`), its top the
  land's own surface (`hv_surface`: grass, snow, sand...), the earth at each stance foot as it stamps and the lip round
  the hammer (and what stands there) as it lands (`HV_AT_BLOW`); a ragged edge (`Heave::edge`), nothing inside the
  crater, columns holding a chest, barrel, furnace and the like left as they are (`hv_kind` 5); a chunk not loaded is
  asked again, a column first, till 19 s (`HV_LAST`). The colours of what it tears up go to the pass at `HV_COL`
  (`cl_heapcol`); with the terrain on the pass draws no heap outside the crater (flags bit 3). `hv_drive` runs by the
  real clock (`strike::clock()`, see below). **The crater** (`Crater`, `cr_column`): ~317 across (`CRATER_R` 158, 36
  CL_K), its edge wandering 9% and pulled out in lobes up to 16% along the five crack lines (`CR_LOBE`), ~62 deep under
  the target's ground (`CRATER_D`) and 8 more in a pit in its middle, in terraces about 6 deep (`CR_STEP`) broken into
  slabs ~22 across (`CR_SLAB`), lined by depth (`cr_stone`: the land's own stone, then tuff and stone, deepslate,
  blackstone and basalt deep), its risers blackened in patches, a few glowing pools of verdant froglight in the pit;
  land over the target's ground cut back from the edge in a stepped slope (`CR_SLOPE`); a broken rim of overturned
  earth and rock up to ~11 high (`CR_RIM_H`) within ~26 of the edge (`CR_RIM`); fissures (five towards the giants'
  blows from 8 out to ~258, and between each two giants one from inside the crater out to ~283 (most strikes) and one
  from near its edge out to 253-293), 6-15 wide and deep in the crater, narrower and shallower out past it, bedded in verdant froglight, dark prismarine, sculk and
  blackstone with dark lips. **The blast field** past it out to 384 (`BD_R`, `Crater::zone`, `bd_fell`, `bd_rock`): trees
  felled lying pointing away from the middle out to about 82 past the crater's edge (`BD_FELL`; some knocked flat
  further), snapped and stripped to about 150 past it (`BD_SNAP`), crowns thinned from the top in patches and snow
  shaken off out to `BD_R`, the ground scorched in tongues (blackstone, basalt, coal block; coarse dirt, podzol,
  gravel; singed), boulders and rubble in 21 rays (`BD_RAYS`); a column never loaded is done by the heightmap out to
  `TREE_R` (308) only; nothing within a statue's box or a giant's torn land (`Crater::clear`). Its stages
  (`cr_setup` at 7.85 s, `cr_list`, `cr_run`): the field and the crater's edge chunks clear of the torn land read from
  8 s (`BD_SETUP`, a stage every `BD_GAP` 0.1 s, `BD_AHEAD` 4 reads in hand), the crater's middle from 12 s
  (`CR_SETUP`, every `CR_GAP` 0.1 s, `CR_AHEAD` 3), the edge near the torn land from 18.2 s (`CR_ASK`, a stage a tick);
  `world.read-columns` 34 under each column's top (`CR_BELOW`), six chunks a read (`CR_PART`). A chunk's blocks are one
  edit, due as the front reaches its nearest column (`cr_when`: 20.15 s + 140 blocks a second out to ~228, `CR_READ`,
  then 110 a second, `BD_WAVE`: the bowl in by ~21.3 s, the rim by ~21.8, the field by ~23.2).
  `the_crater_goes_in_as_the_blast_hides_it` (hills, a river, trees) and `the_field_and_the_wrecks_over_a_snowy_forest`
  play it; `CR_MAP=file.ppm` draws it from above. **The hammer wrecks** (`hm_wreck`, `hm_pieces`, on the floor the
  crater's stages leave within `HM_R` 64 of each blow, `Crater::floors`): the head's stump buried across the blow, its
  top 6-14 over the floor, broken off at one end, the shaft's stub (18-44 long) leaning back towards the giant, in
  polished deepslate, deepslate tiles and bricks and tuff bricks with dark prismarine and froglight in the breaks, and
  11-15 fragments out to 46 (`HM_FAR`); the stump at 24.95 s + 0.25 s a giant + 0.05 (`HM_AT`, `HM_STEP`), the
  fragments in two edits as they land after it; all seeded from `Crater::seed` and the giant only. **The statues**: five
  kneeling statues (`STATUE_POSE` in tools/colossi_assets.py, posed by tools/colossi_pose.py; about 38,000-74,000 blocks
  each, some 300,000 in all, their grids 137-177 high and set 9 into the ground, `BURY`), read out of `statues.bin` from
  21.6 s + 0.3 s a giant (`statue_read_at`: `Statue::cells` a stage, `Cells::by_chunk` the next), handed to the world a
  few chunks a stage (`place_statue`, `STATUE_STAGE`), every edit of giant g's at 24.45 s + 0.1 s g (`STATUE_AT`,
  `STATUE_STEP`: after `CL_SETTLE`, before its line), one per chunk column, the chunk with the highest block first,
  each chunk once, hidden inside the giant the pass still draws over them till its line reveals them;
  `cl_edit_profile` (ignored) prints the edits a quarter second at a time and each statue's margin before its reveal.
  The meshes in the repo (`mod/colossi/*.bin`) are built from the owner's Tripo models (GiantA, GiantB, Hammer: not in
  the repo) with `tools/colossi_assets.py --models DIR`; **never run it without `--models`**: it would build from
  stand-ins (`tools/colossi_standin.py`) and replace them. `--reuse` packs the converter's output already in its work
  folder (only the packing and the statues' pose run); a fresh build needs the converter
  ([model2mc](https://github.com/Stink-O/model2mc)) and its `.venv`.
  Its impact frames (`cl_if`, half a second of hard cuts as the land bursts at 20 s, `cl_spikes` in the half-size
  stage) and the blast's white flash obey `/orbital impactframes on|off` and the wheel's FLASHES row (FULL or SOFT,
  `Rows::Flash`, the same setting as the Six Stars'): off sets params[15] bit 2 (`flags_of`) and `cl_soft` leaves the
  frames out and holds the flash down. **Photosensitivity:** a note goes with it in the README and the release notes.
- **Minecraft is not part of this repo.** Horizon's prepared resources come from the user's own Minecraft Java 26.3
  (`horizon-prepare`). Don't download, bundle, fake or work around it.
- **Stock Horizon can't run the mod.** It needs the fork's build, release `orbital-mod-api-13` or newer (it adds
  `render.set-view-offset` and `world.shift-player`, the Earthquake's walk on its moving plates, and
  `render.set-warp-data`, floats its world warp reads for the falling trees and slabs; `orbital-mod-api-12` added
  `render.set-hand-tint`, the hand and held item tinted each frame, which the Supervolcano dims with the land when
  `HAND_TINT` is on (off for now); any laser's plan can feed it a `HandLight`; and the chat's tree of mod commands, a
  registered name with spaces a path of words: `command_paths` in lib.rs registers `/orbital`'s; `orbital-mod-api-11` added `render.set-warp`, `render.hold-world` and
  `render.hold-world-within`, the Fold's; `orbital-mod-api-10` the `atlas` capability, the game's block textures in a
  post pass, which the Hurricane draws its flying blocks with;
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
tools/preview.py skybreak 3 9.05 20 37.6 --views sbplayer,sbeye,hdslam  # the Sky Breaks offscreen (views sb*, the opening lf*, the hand hd*)
tools/preview.py skybreak 49 --views sbruin,hdcrater  # the blocks its panes and its fist leave (those views' vox=2)
python3 tools/sounds_skybreak.py --only --listen DIR  # the Sky Breaks' sounds mixed as the game does from 30, 300 and 800 blocks
tools/preview.py carpetbomb 6 11 15 22 --views cpplayer,cpside,fside  # the Carpet Bomb offscreen (views cp*, its last blast fside, the fires cpfire, the bomber cpskyf, cpskyb)
python3 tools/sounds_carpetbomb.py                   # the Carpet Bomb's sounds (`--mix CUES OUT` a strike's cues, from cp_write_cues, into one file)
tools/preview.py worldeater 9.5 14 22 --views weplayer,weside,wefar  # the World Eater offscreen (the scripted show; `--set weplan=3` a three-arch chain; views we*, web* the body, wef* the fx)
python3 tools/sounds_worldeater.py                   # the World Eater's sounds (`--review DIR` the review mixdowns; the burst's and the ground's sources: NOTICE)
python3 -I tools/bake_hand.py MESH_DIR               # the hand's sculpted shape baked into mod/assets/sb_hand.bin and the pass's [bake table]
tools/world_snapshot.py save|restore|reset WORLD [NAME]  # snapshot a world and put it back (refuses while it's open; reset leaves, restores, rejoins)
tools/preview.py convergence 6 13.05 20 26.1 38 --views cvplayer,cvaerial  # the Convergence offscreen (views cv*, the sky cvs*, the ground cvg*, the cracks cvk*; `--set seam=face`)
python3 tools/sounds_convergence.py                  # the Convergence's sounds (its explosions from tools/sounds_cv_blasts.py; the recordings: NOTICE)
tools/preview.py sixstars 3.5 8.5 14 19 30 --views ssplayer,ssover  # the Six Stars offscreen (views ss*: ssplayer, sssun, ssup, ssfar, ssover, ssaerial)
python3 tools/sounds_sixstars.py                     # the Six Stars' sounds (`--src DIR` or SS_SOUND_SRC: the CC0 recordings, by their Freesound numbers in NOTICE)
tools/preview.py colossi 10.5 20.3 23.2 --views clplayer,clburst  # the Colossi (views cl*; the meshes from mod/colossi/view.bin)
python3 tools/sounds_colossi.py --listen DIR         # the Colossi's sounds (and the strike heard from 300 and 700 blocks)
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

In the game: `/orbital give` (the designator), `/orbital wheel`, `/orbital plasma`, `godly`, `blackhole`, `meteor`, `mothership`, `downfall`, `planetkiller`, `crystalbloom`, `sinkhole`, `payload`, `nuke`, `rod`, `supercell`, `hurricane`, `tsunami`, `fold`, `supervolcano`, `skybreak`, `carpetbomb`, `worldeater`, `convergence`, `earthquake`, `sixstars` or `colossi`, `/orbital approach …`, `/orbital arrival …`, `/orbital colour …`, `/orbital terrain on|off`, `/orbital hud on|off`, `/orbital payloadsound main|alt`, `/orbital nukesound main|alt`, `/orbital quality full|fast|performance` (PERFORMANCE: FAST with the World Eater's pass at its lightest, `we_tier`), `/orbital impactframes kanada|blackflash|cinematic|off` (`on` brings back the last look; the Convergence's frames read only on or off), `/orbital seed N|lock|random` (kept, the wheel's SEED field and LOCK SEED switch: N in 1-997 holds every strike's seed, `lock` holds the last strike's, `random` lets go), `/orbital knockback on|off` (the Nuke's, the Rod's, the Fold's, the Supervolcano's, the Carpet Bomb's, the World Eater's, the Convergence's and the Six Stars' push, the Hurricane's and the Tsunami's carry, the World Eater's swallow; kept, the wheel's KNOCKBACK switch), `/orbital worldeater hunt|scripted` (kept, the wheel's TAKE row), `/orbital wormground a|b|c|old|off` (the World Eater's sound under the land, `WORMGROUND`; this session only; default a), `/orbital carryview turn|still` (kept: whether the Hurricane's carry turns the player's view a little with them round the storm and sways it with the gusts, `CARRY_TURN`; `still` leaves the view their own), `/orbital follow on|off` and `/orbital follow distance N` (kept, the wheel's FOLLOW switch: an orbit camera round a Nuke's or a Payload's bomb, `follow.rs`: the player's own look sets the angle, the camera `distance` (70) back from the bomb along it; moved only by `world.push-player` kicks each tick, never faster than 24 blocks a tick (`VMAX`: past that the game's collision sweep runs out of budget and crashes), worked out against the game's own drag so its movement and frame interpolation carry it, never a teleport or a turn of the view; it leaves the player once the bomb is within 440 blocks of them, so it stays on land already loaded; backs off to 380 (the Payload 170) as the burst nears, orbits the cloud, and a `tp ... ~ ~` puts them back), `/orbital flyspeed N|reset`, `/orbital stop` (ends the strike under way; also the wheel's STOP STRIKE button while one is), `/orbital skip SECONDS`. `/orbital tune` lists the loaded laser's live knobs, `/orbital tune KEY VALUE` sets one (clamped; kept), `/orbital tune reset [KEY]` puts them back (`mod/src/tune.rs`; only the Convergence has any: `crater`, `depth`, `turn`, `knock`, `jolt`, `islands` from its next strike, `glow`, `burst`, `flash`, `haze`, `dusk` at once).
The wheel has pages of five (its arrows, its tabs or a right-click turn them); the Downfall, the Planet Killer, the Crystal Bloom, the Sinkhole and the Payload are on the second, the Nuke, the Rod from God, the Supercell, the Hurricane and the Tsunami on the third, the Fold, the Supervolcano, the Sky Breaks, the Carpet Bomb and the World Eater on the fourth, the Convergence, the Earthquake, the Six Stars and the Colossi on the fifth. Its FLY
SPEED row over the title sets the creative flying speed (a click along the bar for 1x–40x, or a number typed in its
box, up to 1000x, Enter to set), through `world.set-flying-speed` and `input.poll-typed`. A fork build without them, or
without `world.edit-blocks`, `world.surface-height`, `world.read-columns`, `world.push-player`, `world.carry-player`,
`game.player-flying`, `render.set-data`, `render.set-hand-tint` or the `atlas` capability, won't start the mod.
The wheel's left column has the strike options: SEED (a field: the last strike's seed, or one typed) and LOCK SEED
at the top, then KNOCKBACK (the Nuke, the Rod, the Hurricane, the Tsunami, the Fold, the Supervolcano, the Carpet Bomb, the World Eater, the Convergence, the Earthquake, the Six Stars) and FOLLOW (the Nuke, the Payload) only for the lasers they apply to
(`toggles` in wheel.rs); the right column PANEL and QUALITY, and a red STOP STRIKE under QUALITY while a strike is
under way, its rows lined up with the left's (PANEL with SEED, QUALITY with LOCK SEED, STOP STRIKE with the first
switch under them). Nothing goes over the hotbar but the designator's: its countdown while held (`ACQUIRING TARGET …`, `SEISMIC SCAN …`,
`DESIGNATING …`, the Hurricane's `TRACKING STORM …`, the Tsunami's `READING THE SEA …`, the Fold's `ATTUNING …`, the Supervolcano's
`BREACHING CRUST …`, the Convergence's `WORLDS STIRRING …`, the Earthquake's `READING FAULTS …`, the Six Stars' `HEAT RISING …`, the Colossi's `WAKING THE GIANTS …`, with the laser's name) and `NO TARGET IN RANGE` (`actionbar` in lib.rs;
the strikes have no messages; firing during a strike only clicks). With the Rod or the Convergence loaded or pointed at, an IMPACT FX row under the ring (OFF, KANADA, BLACK FLASH,
CINEMATIC; `Rows::Impact`; the Convergence's frames have one look, so any look but OFF turns them on). With the Six Stars or the Colossi, a FLASHES row (FULL or SOFT; `Rows::Flash`, the same setting). With the Payload or the Nuke loaded or pointed at, a BLAST SOUND row under the ring picks its blast (MAIN or ALT, as
`/orbital payloadsound` or `/orbital nukesound`). Every post pass is built ahead of time by `mod/build.rs` (`src/passbuild.rs`): a switch
only picks a ready-made one, but the game holds one pipeline at a time and builds a new one on the render thread as `warm` hands it
over: some 60 ms each time, and up to 2 s (the Downfall's 7) the first time the driver sees a pass. So a wheel pick stays up for the two
frames that takes, saying LOADING (`close_picked`). On native a pass is built on a thread of its own and kept
(`native/engine-shim/mod_post.rs`; a strike's frame waits for its pass, and on macOS every frame, where `BUILDING` needs the build in
the frame). The fork would need the engine to do the same. The QUALITY switch under PANEL (top right; `/orbital quality full|fast|performance`, kept
between sessions, default FAST; a click moves it FULL, FAST, PERF) picks whether the Payload's, the Nuke's and the Rod's smoke is drawn at full size or at half size: FAST gives the
game the pass with its half-size stage (`fs_half`, `fs_join`; see below), which the fork draws from release
`orbital-mod-api-7` (an older fork would compile the same source and draw its `fs_main` at full size; FAST needs no
import of its own).
R with the Orbital Laser Designator in hand opens the laser wheel (with anything else in hand R is left to the game;
`/orbital wheel` opens it from anywhere); holding right-click with the designator for under a second fires. Rebind R in
Options > Controls > Key Binds (on a native build: Options > Mods > Orbital Laser > Settings). There is no Orbital Remote any more (0.5.9): a Remote left in an old world's inventory
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
  `src/lasers.rs` the lasers, `src/strike.rs` a strike's plan (`src/strike/crystal.rs` the Crystal Bloom's, `src/strike/sinkhole.rs` the Sinkhole's, `src/strike/payload.rs` the Payload's, `src/strike/nuke.rs` the Nuke's, `src/strike/rod.rs` the Rod's, `src/strike/tsunami.rs` the Tsunami's, `src/surge.rs` its carry of the player), `src/wheel.rs` the wheel, `shaders/strike.wgsl` the post
  pass, `shaders/downfall.wgsl`, `shaders/planetkiller.wgsl`, `shaders/crystalbloom.wgsl`, `shaders/sinkhole.wgsl`, `shaders/payload.wgsl`, `shaders/nuke.wgsl` and `shaders/rod.wgsl` the
  Downfall's, the Planet Killer's, the Crystal Bloom's, the Sinkhole's, the Payload's, the Nuke's and the Rod's own passes (the
  mod appends each to `strike.wgsl` up to its `fs_main`; `pass_of` in lib.rs picks a strike's),
  `horizon-mod.toml` the manifest (api 0.2 with `registries` for the content).
- The Supercell: `src/strike/storm.rs` its plan (bolts, pits, finale crater, fire sweeps, `sc_table`),
  `src/strike/vortex.rs` its funnels as reusable pieces for a tornado (`Funnel`, `wander`, `vx_words`, `scour`, `roar`),
  `shaders/supercell.wgsl` its pass (the vortex section `vx_*`; FAST's `[half stage]` as the Payload's).
- The Supervolcano: `src/strike/volcano.rs` its plan (the beats, the bombs, the land's height, the shaking),
  `src/strike/vc_mount.rs` the mount, `src/strike/vc_lodge.rs` the plates that stay, `src/strike/vc_land.rs` its land
  (`vc_land_view.rs` its offscreen pictures), `src/strike/vc_sound.rs` its sounds (`tools/sounds_volcano.py` builds
  them), `shaders/volcano.wgsl` its pass and `shaders/volcano_mount.wgsl` the mount's (preview views `vc*`, `vm*`;
  `tools/vc_sat_motion.py` writes the satellite's `VC_SAT_TAB`).
- The Hurricane: `src/strike/hurricane.rs` its plan (the land's read and edits, the trees, the rings' colours, the mobs,
  the landings: `tree_landing`, `hu_landings`), `src/carry.rs` the player's carry, `shaders/hurricane.wgsl` its pass (`hu_debris`, `hu_trees`,
  `hu_volume`; FAST's `[half stage]`). Preview views `hu*` (`hustrip=1` takes the preview's trees away as the front
  reaches them); `hu_write_table` (ignored) writes its table over the preview's wooded land.
- The Colossi: `src/strike/colossi.rs` its plan (the table and the records, `CHARACTER`, the sounds' cues `CS_*`, the
  torn land `hv_*`, the crater and the blast field `cr_*`/`bd_*`, the hammer wrecks `hm_*`, the statues `place_statue`),
  `shaders/colossi.wgsl` its pass (appended to `strike.wgsl` up to its `fs_main`: the skeleton and its pose, BVH ray
  tracing of the packed meshes cut by the converter's damage function `cl_damage` (`cl_cut`), the land's cracks and
  heap, the ground clouds and plumes, the blast's crown, column and dust wall, the burst's debris and smoke, all put
  together in `cl_render`; FAST's `[half stage]`: the whole of `cl_render` at half size, `fs_join` a joint bilateral
  upsample against the land's depth), `tools/colossi_rig.py` (the meshes cut into bone pieces, the layout),
  `tools/colossi_assets.py` (converter output to `mod/colossi/view.bin` and `statues.bin`), `tools/colossi_pose.py` (the
  statues posed as the pass poses the giants), `tools/colossi_standin.py` (stand-in GLBs: never over the real ones),
  `tools/sounds_colossi.py` its sounds (`colossi.*`, all synthesised; its `schedule` plays the plan's cue arithmetic:
  keep the `CS_*` leads and the files in step). Preview views `cl*`; `cl_write_table` (ignored) writes the table.
- The Tsunami: `src/strike/tsunami.rs` its plan (`TsGeo`, the land's read and edits, `ts_chunk`, `ponds`, `table_words`),
  `src/strike/ts_sounds.rs` its sounds' schedule, `src/surge.rs` the player carried in the water,
  `shaders/tsunami.wgsl` its pass (no half-size stage), `tools/sounds_tsunami.py` its sounds. Preview views `ts*`;
  `ts_write_table` (ignored) writes its table.
- The Sky Breaks: `src/strike/skybreak.rs` its plan (`Mesh` the cracks, `sb_shards` the panes, `sb_table` the pass's
  table, `sb_pane_events`), `src/strike/sb_lift.rs` the opening (the island, its words from `SB_LF`),
  `src/strike/sb_hand.rs` the hand (`Print` its crater, `Arm` its poses, its words from `SB_HD`), `src/strike/sb_lodge.rs`
  the panes as real blocks, `src/strike/sb_sounds.rs` its sounds' schedule (`tools/sounds_skybreak.py` builds them; the
  shudder's glass from `tools/sound_sources/skybreak/`), `shaders/skybreak.wgsl` its pass (`[lift]`, `[hand]`, the
  `[bake table]` that `tools/bake_hand.py` writes with `mod/assets/sb_hand.bin`; FAST's `[half stage]` the dust).
  Preview views `sb*`, `lf*` and `hd*` (`vox=2` the blocks it leaves); `sb_write_table` (ignored) writes its table.
- The Carpet Bomb: `src/strike/carpet.rs` its plan (`CpGeo` the stick and the bomber, `Land` and `Blast` the land as the
  blasts leave it, `cp_blast_rows`, `cp_tidy`, `cp_felled`, `cp_rubble_and_thrown`, `cp_bomb_words` and
  `cp_debris_words` the pass's table, `cp_sounds` its sounds' schedule), `shaders/carpetbomb.wgsl` its pass (the bomber
  and its contrails, the bombs, the three latest blasts' smoke raymarched together and the last's formed as the
  Payload's column (`cp_final_prep`), the line's dust, the shockwave fronts as the Payload's (`cp_front`), the fires, the
  debris; FAST's `[half stage]` the smoke, the dust and the fronts), `tools/sounds_carpetbomb.py` its sounds (synthesised;
  the last blast plays the Payload's ALT set and the Nuke's ALT). Preview views `cp*` and `fside`; `cp_write_table` and
  `cp_write_cues` (ignored) write its table and its cues. Tests `carpet_*`.
- The World Eater: `src/strike/worldeater.rs` its plan (`worldeater_plan`; `arch_events` each arch's sounds, jolts,
  knockback, kills, forceloads and land as it is planned; `decide` the next arch; `watch` and `sink` the trenches;
  `WeHand` the per-tick part: the player sampled, the knockback, the carry; `land_words` its words for the pass),
  `src/strike/we_path.rs` the path (the arches, runs and knots; `we_head`, `we_point`, `we_mound`, `we_eye`; the table
  both the mod and the pass read from word 0), `we_land.rs` the land (`dig`, `funnel`, `heap`, `felled`, `thrown`,
  `sculk`, `trench_rings`, `buck_*`), `we_land_hunt.rs` the hunt (`Kind`, `hop_gap`, `run_want`, the picks),
  `we_land_catch.rs` the catch (`Catch`, its track, the spit), `we_fx.rs` the fx's block table and the per-tick tables
  (`we_pieces_words`: the pieces, the jolt and lens events, each hole's billows and clumps), `we_body.rs` the body's block
  table, `we_sounds.rs` the sounds' schedule (`we_arch_cues`; the takes picked by its `WE_*_TAKE` constants, the other
  takes' files kept; `WE_REVOICE` off: the re-voiced `_rv` files are unjudged and unused), `fallgov.rs` the falling-block
  cap, `perf.rs` the `/orbital perf …` measuring switches (all off by default). The pass is
  `shaders/worldeater_path.wgsl` (the path, `we_tier`, `we_detail`) + `worldeater_body.wgsl` (the worm: rings of block
  cells under 12 plates, the head with six petals and three rings of teeth, the neck turning to look, the throat from
  inside) + `worldeater.wgsl` (`fs_main`, the half stage, the dust, the pieces, the caught view, the lens), assembled by
  `mod/build.rs`; `worldeater_warp.wgsl` the world warp (the dome's teal cracks only). Preview views `we*`, `web*` (the
  body), `wef*` (the fx); `--set weplan=3` a three-arch chain. Tests `we_*` and the catch's and the path's
  (`a_breach_catch_holds_them_inside_then_spits_them_clear_of_the_hole`, `three_arches_with_holes_of_their_own`, ...);
  `we_land_profile`, `we_pieces_worst_tick` and `we_write_table` (ignored) print its busiest ticks and write its table.
- The Convergence: `src/strike/convergence.rs` its plan (`convergence_plan`; the shared clock and geometry `CV_*`,
  `cv_meet_y`, `cv_red_top`, `cv_gold_foot`; `cv_table` the pass's table; `Work` and `cv_work` the land's chain of
  stages: the read, `cv_pre_part` the land before the blast, `cv_islands_part`, `cv_thrown`, `cv_blast_part` and
  `cv_blast_col` the blast, `cv_fell`, `cv_rubble`, `cv_after_pillars`; `Wave` when the carve and the lining reach each
  radius; `cv_sounds` the sounds' schedule; `cv_jolt` the blast's jolt), `src/tune.rs` its live knobs. The pass is
  `shaders/convergence.wgsl` up to `[cv stages]` (`[cv shared]`: the clock and the geometry) + `convergence_sky.wgsl`
  (`cv_sky_soft`, `cv_sky_sharp`) + `convergence_ground.wgsl` (`cv_ground_soft`, `cv_ground_sharp`) +
  `convergence_cracks.wgsl` (`cv_cracks_soft`, `cv_cracks_sharp`, called by the ground side's) + the rest of
  `convergence.wgsl` (`fs_main`, FAST's `fs_half` and `fs_join`, `cv_jolt`), assembled by `mod/build.rs`.
  `tools/sounds_convergence.py` its sounds (`tools/sounds_cv_blasts.py` its explosions). Preview views `cv*`, `cvs*`,
  `cvg*`, `cvk*`; tests `cv_*`; `cv_write_table`, `cv_wave_times` and `cv_no_stage_too_heavy_anywhere` (ignored).
- The Six Stars: `src/strike/sixstars.rs` its plan (`sixstars_plan`; the clock `SS_*`; `SsGeo` the fall; `ss_table`
  the pass's table (header words 0-15, the path from `SS_P` 24, the billows from `SS_PF` 416, the burning blocks it
  sheds from `SS_FR` 560, the land's heightfield from `SS_HF` 2048, the debris from `SS_DB` 12288); `Shape` and
  `ss_blast_col` the crater; `Work` and `ss_work` the land's chain of stages; `ss_sounds` the sounds' schedule),
  `shaders/sixstars.wgsl` its pass (the Payload's pass and its half-size stage, with the HUD, the sky, the star, the
  points and the trenches' smoke; keep its `SS_*` and `PL_*` in step: `ss_pass_keeps_the_clock_and_the_star_in_step`).
  Preview views `ss*`; tests `ss_*`; `ss_write_table` (ignored) writes its table.
- `native/`: the native build for upstream Horizon (`assemble.sh` builds the mod's source unchanged against
  `engine-shim/horizon_sdk.rs`, the SDK on native helpers; `package.py` makes the one-file `orbital-laser-native-vX.Y.Z.hnmod` (the launcher installs it as `orbital.hnmod`; `content_find.rs` finds the content by the mod id);
  `mixins/orbital/horizon-mixin.toml` its hook points and the upstream commit it is pinned to). A fork call the native
  build lacks gets a stand-in in the shim so the mod builds: `native_build::UNSUPPORTED` lists the ones a laser can't do
  without and `NEEDS` which laser needs them, and such a laser is greyed out in the wheel; `HELD_BACK` greys out a laser the build can make but that hasn't been played
  natively yet or doesn't play right there (the Fold, its water through the warp; the Earthquake, which needs calls upstream lacks; the Colossi, not yet tried natively), saying `NOT_YET` ("On the fork now, native soon"). `render.set-hand-tint` is a stand-in that only keeps the colour (upstream has
  no hand tint). The glue ignores the mod's `Registration` (its command paths included): it runs every line starting
  with `/orbital` and puts only its own `USAGES` in the server's command tree. Check a bundle with
  `horizon-mixins apply` and `cargo check -p horizon-client` on its pin and on the newest Nightly (the registry's check).
  The client half sends its world work (commands, edits, reads) to the server half over mod messages, and upstream takes
  at most 32 a player a *server* tick, dropping the rest in silence (`guest_native_net`): the glue numbers its batches,
  the server half serves each once in order and acknowledges it (kind 12), and no more than `WINDOW` (30) are ever out
  (glue.rs's `flush_work`); edit runs go packed (kind 5). Without that, big strikes lost whole chunks of their land
  whenever the server fell behind. `custom_payload_from_client` (uncounted) would lift the cap but isn't stamped in
  native-hooks.json yet (horizon-mixins: E_HOOK_UNKNOWN).
  A strike's `forceload add|remove` boxes become chunk tickets in the glue (`force_load` in glue.rs): upstream's
  `/forceload add` waits on the server thread for its chunks. Upstream's streaming scanned every forced chunk past 4,096
  (`ForcedCover::MOST`) until horizon-rust/horizon#15878, which the pin has: only the Supervolcano holds more (5,836;
  the ignored test `forceload_chunks_per_laser` counts them). `native/SWEEP.md` is each laser's native state; test natively off-screen under gamescope, both GPU locks.
  The native prelude (`engine-shim/mod_post.wgsl`) binds the depth as a float texture: read it through `depth_at`, never
  `textureLoad`, and never name a WGSL local `gl` twice (naga's GLSL makes the second `gl_1`, a name OpenGL reserves).
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
- **Live knobs** (`mod/src/tune.rs`): a laser declares its numbers in `tune::KNOBS` (key, default, range, meaning, and
  for a shader knob a slot 0-15) and reads them with `tune::get(laser, key)` when its plan is made (the next strike) or,
  in its pass, `tune_knob(slot, default)` (strike.wgsl), at once. For a laser with shader knobs `tune::send` adds 17
  words after the laser's own `mod_data`: the 16 slots and `0x54554E45`; such a pass must not size its tables by
  `arrayLength(&mod_data)`. A laser with no knobs gets its words unchanged. Ship numbers as constants again once settled.
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
- **The Colossi are skeletons** (`tools/colossi_rig.py`, `cl_pose`/`cl_rig`/`cl_leg`/`cl_arm` in `colossi.wgsl`,
  `pose_words` in `strike/colossi.rs`): 13 rigid pieces a giant (pelvis, torso, head, two arms and forearms, two thighs,
  shins and feet) plus the hammer, chained about 15 joints per design (`JOINTS_A`/`JOINTS_B`, in the 50-unit mesh's
  coordinates, or `rig.joints` in colossi.json as box fractions: Tripo's rig can replace them with no code change), cut
  by nearest capsule, planes at the neck, hips, knees and ankles and a 0.7 overlap band, balls at shoulders and elbows to
  close the seam; legs by two-bone IK (`cl_leg`, its frame `cl_frame`: thigh, shin and foot turn as one hinge about the
  knee line) so the feet stay planted, arms by IK to the handle (`cl_arm`). The pose is `cl_pose(g, t)`: a rise in
  heaves, a foot stamped before each blow (`cl_stomps`), the hammer heaved over the shoulder and slammed, each giant by
  its record's character words; after its burst one knee goes down (record words 59-62: where the kneeling foot goes and
  which; the other foot steps in to `CL_FRONT`) and it sinks into its statue's crouch (words 48-58) by `CL_SETTLE`
  (24.3). **That pose is in two places**: the pass's `cl_pose`/`cl_rig`/`cl_leg`/`cl_arm`/`cl_about`/`cl_arc`/
  `cl_rest_pole` and `tools/colossi_pose.py` (`rig`, `leg`, `arm`, `feet`, `FRONT` = `CL_FRONT`), which moves the
  statue's blocks bone by bone into the same crouch (`pose_blocks`) for `tools/colossi_assets.py` (`STATUE_POSE`, packed
  into `statues.bin` and handed to the pass as words 48-62): change one, change the other, and rebuild the statues
  (`tools/colossi_assets.py --models DIR --reuse`; never without `--models`), or the blocks will not lie under the giant
  drawn over them. Round the giants: `cl_ground` (the green cracks where each rises, `cl_frac`; where each hammer lands
  and on to the middle, `cl_run`; the stamps' rings; the crazed glow as the cracks meet; the crater's light; the dust
  wall's ring on the land), `cl_mound`/`cl_mh`/`cl_mtrace` (the heap, drawn only inside the crater with the terrain on),
  `cl_earth` (to 24.5 s: `cl_gc`, rolling ground clouds where each rises, stamps and strikes; `cl_plumes`, each giant's
  own plumes of earth as its head and shoulders break the ground), `cl_falls`/`cl_strm` (dirt pouring off the hammer,
  the arms, the hands and the chin as each clears the ground and at each blow: 15 points a giant, a ray-to-line test
  each, no march), `cl_blast` (the crown of thrown earth, a cone, `cl_crown_at`; the eruption's column, `cl_col`,
  `cl_col_d`, `cl_col_rho`, marched with leaps through clear air, its head some 500 up, hanging and drifting with the
  wind to the end; the dust wall, `cl_surge_r`, `cl_surge_k`, `cl_surge_seg`, lobed and torn, past the giants in
  ~1.4 s), `cl_blast_glow`/`cl_blast_lit`/`cl_blast_shade` (its light: one flash of about a fifth of a second, the core's
  green, a low glow in the crater; and the column's ragged shadow on the land), `cl_debris` (each giant's hammer and arms
  in 40 pieces, `CL_DBN`: `cl_pc` places each closed-form, `cl_vox` walks its blocks, at most `CL_DBV` 4 walks a pixel;
  thrown, landed, lying to the end), `cl_bsmoke` (the burst's shell of stone dust, ~7 s), `cl_flash`, `cl_motes` (green
  embers over the crater), `cl_cut` (the damage, the burst and the sweep line on a hit). `cl_px` and `cl_jit`: every
  march's jitter is white noise on the pixel grid, new each frame (a pattern showed as hatching or moire). Preview views
  `cl*` (`clplayer`, `clfar`, `clclose`, `clswing`, `clheave`, `clrisehill`, `clriseslam`, `clburst`, `clburstup`,
  `clkneel`, `cllegs`, `cllegsb`, `clface`, `clhero`, `clbust`, `clhead`, `clgrip`, `clfeet`, `clside`, `clfront`,
  `clmid`, `claerial`; `--set hills=H` puts the giants on the preview's hills).
- **The Colossi's pass and the size limit**: the fork takes a post pass of at most 256 KiB (262,144 bytes,
  `POST_SOURCE` in the fork's `horizon-mods` runtime.rs: over it the game logs "post pass over 256 KiB, ignored" and draws
  nothing of it). colossi.wgsl says `// [lean pass]`, so the mod sends it without its comment and blank lines
  (`passbuild::lean_pass`): 172,931 bytes as sent, against 231,630 with them. `tools/check-shader.sh` fails any pass over
  the limit, counting it the same way.
- **The Colossi's data is three places**: the layout at the head of `colossi.wgsl` (`mod_data`: 27 meshes' headers at 16,
  rigs at 448 (96 words a design), five records of 64 words at 640 (`REC0 + REC * g`), the heap's colours at 1008
  (`HV_COL`), the meshes from 1024; view.bin is 256,808 words of the 262,144 `render.set-data` takes),
  `tools/colossi_rig.py` + `tools/colossi_assets.py` (the meshes, the statues file) and `strike/colossi.rs`
  (`table_words`, `pose_words`, the `Statue` reader). A record's words: 0 design, 1 mirror, 2 scale, 3 yaw, 4-6 where its
  mesh stands (5 its ground less `BURY`, rewritten by the `survey`), 7 its damage seed, 8 glow, 9 its rise, 10 its first
  blow, 11 its sweep, 12-14 its grid, 15 its cuts, 16-19 the damage spec, 20-22 the grid's offset; 23 its second blow, 24 its swing's
  seconds, 25 its variation, 26-27 its leads, 28-34 its character, 36 the hammer's scale; 44-46 where its hammer lands
  (45 rewritten by the survey), 47 the pieces that burst with it (`BURST_MASK`), 48-58 its statue's crouch and 59-62 its
  kneel. Word 3 is the flags (bit 0 the cuts, bit 1 the shadows, bit 3 the terrain's heap is real); 1008 + 2 g giant g's
  torn land's colours (its surface, what is under it; 0xAABBGGRR, A 255 once known). CL_K (4.4), the CL_* times, the
  ring and the blast's speed are in the shader and the plan: change both. The shader's damage (`cl_h3`, `cl_vn`,
  `cl_damage`) must stay the converter's `docs/damage.md` exactly, or the display and the blocks will not agree.
  `statues.bin` is 1.6 MB of runs and is read a stage at a time on purpose: reading it all when the strike fires took
  the mod's whole tick fuel ("it took too long"); keep the heavy decoding (`Statue::cells`) in a stage of its own, one
  giant at a time.
- **The mod has 64 MB of memory** (`MEMORY` in the fork's `horizon-mods` runtime.rs), besides the fuel limit: past it
  the mod stops for good (a `rust_oom` in the soak). Edits, reads' answers and work waiting are all held in it. The
  Colossi hit it: the giants' torn land shared the stages with the crater and the field, one stage a tick, and ran 13 to
  28 s late, till the strike's end at 34 s dropped them; their reads' answers waited in memory meanwhile (some 27 MB)
  and took the mod past 64 MB. Now `hv_drive` runs by the real clock (`strike::clock()`, set each tick by lib.rs's
  `set_clock` and by `sim::play`: a stage that runs late catches up with all that is due instead of falling a stage
  behind each time), the reads in hand are capped (`BD_AHEAD`, `CR_AHEAD`), a land never loaded is done only near the
  middle (`TREE_R`), and the statues go in over five ticks (`STATUE_STEP`). One soak seed hid it: run `mod_soak`
  (`SOAK_LASERS=colossi SOAK_FULL=1`) on several (7, 9 and 11), six strikes each, and keep every one under half the fuel.
- **The Tsunami's land work is metered by its columns** (`strike/tsunami.rs`): a first version counted a column at a
  sixth of what it cost (a block-name lookup for every column's ground, the noise per column) and the game stopped the mod
  mid-strike ("it took too long", 50M fuel in one tick). Now the ground's kind is looked up once per palette name, the
  strength of the wave, its height and the scour streak are worked out per 4 by 4 cells, and the honest costs are
  charged; `mod_soak` over the tsunami (`SOAK_LASERS=tsunami`) shows the worst tick at about 13M of 50M. Keep any cost you
  add in `ts_chunk` honest, and the stage under `TS_STAGE`. A real village is the case to try: `wreck_ok`'s string
  searches per building block ran the mod out of fuel there, on nothing the synthetic land had (now once a palette name).
- **The Tsunami's model is in three places**: `TsGeo` (`strike/tsunami.rs`), `tsunami.wgsl`'s `ts_*` and `surge.rs`'s
  flow (and `ts_drift`). Change the arrival, the envelope, the profile, the drain (`ts_x`, `ts_fall`) or the speed in all of them; the tests
  (`it_reaches_the_player_when_the_sounds_say`, `the_front_comes_in_order_...`) catch only the plan's side. The
  pass's debris table (`TS_KINDS`, `TSB`, `TSM`) is mirrored in tsunami.wgsl too (`ts_kind` picks among the 24 by index). Its map's words also carry the land's height over the target's ground (`ts_ground`: the foot follows it). A log's long axis in `ts_piece_hit` is its block up: bark along it, end grain on its ends.
  The preview reads the table from `cargo test ts_write_table -- --ignored` (tools/preview.py does it).
- **A jump of the world's clock isn't always another world** (`in_world`): when the frames stall and the world runs on,
  the clock jumps forward, or back by what the client had run ahead (a Fold run under load saw -71). It counts as another
  world only with over `AWAY` seconds of frames since the last tick (each frame at most `AWAY_FRAME`; the fork ticks no mod
  at the title screen, but its frames run) or the player over `AWAY_ROOM` from where they were. On native a stall needs the
  window not drawn or the frames held up with the integrated server going on; `a_stall_is_not_another_world` holds both ways.
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
- **The Fold has three crease patterns on one set of tables** (`tools/foldview/pattern.py` writes them into fold_warp.wgsl and strike/fold.rs: change them there): twelve creases, five rings, and across a panel nothing, an X or a diagonal (`cp_mode`, the wheel's FOLD row, `/orbital foldpattern a|b|c`, kept, read at the fire). params[10] carries it: under the level, 1024ths, 100 pattern + the player's panel + 1 (`fd_lie`, `cp_code`). The crater breaks along it (`facet`), and `fw_sag`, `fw_hurt` and `fw_sunk` go by the same nodes and lines, so the crater lands on what the bangs have already done.
- **The Fold's look is not in its pass.** The land's vertices and pixels go through the fork's `render.set-warp`
  (`shaders/fold_warp.wgsl`, API 11, built into terrain.wgsl and entity.wgsl by the fork's `gfx/warp.rs`; what follows its
  `// [fragments]` line is `world_fragment`, terrain pixels only), so `tools/preview.py` shows only `fold.wgsl`'s droplet, void and
  flash, and voxels of the crater (`fl_dump_land`; views fdtop, fdhigh, fdrim, fdfloor): judge the bending in the game. The warp
  is on only from FD_WARP_START to FD_WARP_END, and nothing is culled while it is (about 20 ms a frame in VillageNuke on an
  RTX 4070 Super, against 10 without). The land is a thin sheet: never let what is under it move on a lever
  (the old rings threw caves and the far tiles' columns into the sky). `fw_chain` must stay continuous in r and in the bearing: the
  far tiles' merged faces can't be cut by a tear. Only the player's island is a real break, its faces cut at the pixel.
  The beats and rings are kept in step by `the_warp_keeps_the_beats`. Falling blocks aren't entities to `@e`: `kill` misses them,
  and a no-gravity one is timed out through its `Time`, as `fd_peel`'s are.
- **The Fold's crater is made behind `render.hold-world`** (the fork's `gfx/hold.rs`, API 11): from `FD_HIDDEN.start` the terrain on
  screen stays as it was and the world changes under it. From the first bang the hold shrinks a tick at a time (`render.hold-world-within`, `fd_hold_areas`), the old land crumbling inward;
  fold_warp.wgsl's `fw_front` and `fw_freed_at` must keep to the same `FD_CRUMBLE`, and the warp goes by each vertex's own section (`warp_section`): by position alone, a vertex on a chunk's edge stretches a block up the height of the lift. The land has to be in by a second before its bang (`fold_land_goes_in_on_time_anywhere`). The rest goes on the frame at `FD_REVEAL`. The hold ends by itself after 30 s, past 1 GiB and on clear-post, a stop, another
  dimension. Every chunk is edited once, on its one tick (`fd_tick`): a second edit of a chunk is a second resend, nine light jobs
  and its meshes again, and that was the 12-30 fps after the last slam. The rubble and fires gathered in `late` are handed over behind
  the parts of the chunks they lie on (`flush`), and only once the crater's cuts are cached: an uncached heap went to 91% of a tick's fuel.
- **The Fold's crater is the crease pattern** (`fold_land.rs`): its outline the fourth ring's chords (`Shape::edge`, 228-353 out), a kite of the
  pattern a panel (`kite_drop`), the mandala laid on the kites. It swaps in held up by the warp at the land's level (`fw_sunk`, `FD_BOWL` =
  `FW_BOWL`) and falls in over ~3 s; the hold lets go 0.03 s before the warp lifts, or the old land shows a one-frame dome. **The mod has 64 MiB**
  (`runtime.rs`'s MEMORY): the land's square is ~19 MiB and worked-out edits wait in memory, so `FD_HELD` caps them and `FD_IN_FLIGHT` the reads
  (answers pile up otherwise: `rust_oom` on real land). The log gives the peak: `the mod's memory N MiB of 64`.
- **Scripted input doesn't reset the game's AFK limit** (60 s without real input: 30 fps; 10 minutes: 10 fps): a strike fired by
  script is capped part way through, in `horizon-ctl bench` and in recordings. `horizon-ctl options-set inactivityFpsLimit minimized`
  before a measurement, `afk` after it. Real play fires with a click, and the longest strikes end before 60 s.
- **A plan must be in time order**: playback stops at the first entry not due. `strike::plan` sorts nothing for the lasers with
  plans of their own, so each sorts its `ev` (the Fold's didn't, and its crater waited for its 49 s forceload remove).
- **`mod.wasm` imports must match the manifest's capabilities**; `cargo horizon-mod build` checks this.
- **The World Eater's pass is the biggest** (prelude + strike.wgsl up to its `fs_main` + `worldeater_path.wgsl` +
  `worldeater_body.wgsl` + `worldeater.wgsl`): `worldeater.wgsl` starts with `// [lean pass]`, so `passbuild.rs`'s
  `split_pass` drops every comment and blank line of the assembled pass (the FAST pass is about 225 KB of the game's 256
  KiB; `tools/check-shader.sh` measures it lean). Comments cost nothing; code does, and every call site of a big
  function is a whole copy for the compiler: keep one call per pipeline of `we_eye_hit_at`, `we_body_colour`,
  `wef_tlight`. QUALITY FAST runs its half-size stage (`fs_half`: the body, the dust, the caught view, at half width and
  height; `fs_join`: the upsample, the pieces, the lens), FULL `fs_main`; the tier (2 FULL, 1 FAST, 0 PERFORMANCE) is
  params[15] (`we_tier`), and `we_detail` scales the steps and counts with it and the picture's height (FAST 0.75 at
  1440 lines, PERFORMANCE half that). The first pick of it builds the pass on the render thread: the game freezes for
  about half a minute to a minute and a half the first time on `orbital-mod-api-12`.
- **The World Eater's `mod_data`** (`render.set-data`): the path from 0 (`we_path.rs`: header 0..16, an arch every 48
  words from 16; arches are appended during a strike and none of the earlier words change), the body's block table from
  512 (`WE_BODY_T`), the catch's words at 2048-2050 and the fx's block table from 3072 (`WE_FX_T` + 1024), the land's
  words from 8192 (`WE_LAND_T`: holes, tunnels, the furrow), the eye's (the swallowed player's view: shut, let-go, the
  track's knots) from 8704 (`WE_EYE_T`), and the per-tick tables from 20480 (`WE_PCS_T`: the live pieces, the jolt and
  lens events, each hole's billows and clumps at this tick and the next), written whole every tick by `we_fx.rs` and
  read by the pass between ticks. Keep the pass's `WEP_*`, `WEF_*` and `WE_*` offsets in step (`pcs_layout_in_step`,
  `we_wgsl_in_step`). Those tables cost the tick some 6 M of real fuel every tick on top of the land's stages.
- **The World Eater's world warp is on only while a dome is seen**: the game culls nothing while a warp is on (every
  resident section drawn, ~8 ms at 1440p), and the warp only paints the dome's teal cracks, so lib.rs switches it on
  only while a dome is up, within 420 of the player and in front of the camera (`we_dome_seen`); `/orbital perf
  nowarp` keeps it off for measuring.
- **The Convergence's clock and geometry are in two places**: `[cv shared]` at the top of `shaders/convergence.wgsl`
  and the `CV_*` constants and `cv_meet_y`, `cv_reach`, `cv_red_top`, `cv_gold_foot` in `strike/convergence.rs` (the
  beats, the surges, the heights, the stubs, the shells' speeds). Change one, change the other:
  `cv_pass_keeps_the_shared_clock_and_geometry_in_step` reads the pass's numbers. The three side files never keep a
  copy: they read `[cv shared]`, and each is reached only through its soft and sharp functions. The pass's crater
  radius (`CVG_CRATER_R` in `convergence_ground.wgsl`) is the built `CV_CRATER_R`, not the `crater` knob.
- **The Convergence's pass goes in without its comments**: `convergence.wgsl` starts with `// [lean pass]`, so
  `passbuild.rs` drops every comment and blank line of the assembled pass (about 190 KB of the game's 256 KiB; with its
  comments it would be about 290 KB, over the limit). The built `mod.wasm` carries it so.
- **The Convergence's `mod_data`** (`cv_table`, `Act::Table` the tick after it fires): word 0 `CV_MAGIC` (7171: the
  pass draws hashed stand-ins until it is in), 1 the seam's bearing, 2 the seed, from `CV_CRK` (16) the cracks'
  bearings, reaches and count, from `CV_SPR` (48) the atlas layers of `CV_SPRITES` (the islands through the rift;
  `cv_sprites`, look-alikes without them), from `CV_ISL` (64) the islands the land grows, from `CV_CRH` the land's
  heights along the cracks once `world.surface-height` has answered (`cv_crack_step`); `tune::send` puts its 17 words
  after them. Keep the pass's offsets (`CVG_CRACK_W`, `CVS_TEX`, `CVS_ISL`, ...) in step. params[15] carries the impact
  frames' bit (as the Rod's) and +0.25 with terrain on (the pass then leaves the fissures' trenches to the real blocks).
- **The Convergence's land is one chain of stages** (`cv_work`): the read (two rings asked a stage, up to four answers
  taken in), then the first job that can go, in order (a blast part never passes one that can't go yet), each stage
  about `CV_BUDGET` columns' worth (`Work::cost`, charged at `CV_UNIT` a unit on top of what the loops count). The
  land waits for unloaded columns, asking again a ring at a time, and leaves out what hasn't come by `CV_LAND_BY` (20 s
  after the blast) or `CV_PATIENCE` (4 s) after the last came once the crater's land is in (logged `convergence: N
  columns of the land never loaded`). `cv_no_stage_too_heavy_anywhere` (ignored, on its own) times every stage over
  the test lands; run `mod_soak` with `SOAK_LASERS=convergence` too.
- **The Earthquake's land is metered at its real cost** (`strike/eq_land.rs`): the cut keeps pace with the crack under
  `CUT_STAGE`, the rest's stages under `REST_STAGE` and `PASS_STAGE`; its costs were measured with `mod_soak`'s trace
  (`SOAK_TRACE=1`, the `eq cut:` points). Counted dearer, the cut falls behind the crack (`eq_land_cuts_the_faults_as_the_crack_passes`);
  counted cheaper, a stage runs past half a tick's fuel on high land. Anything done for every column of the cut wants
  working out once (`Work::lake`). `SOAK_LASERS=earthquake SOAK_FULL=1` plays it whole.
- **The Earthquake's warp, pass and mod agree on the plates**: `EqPlates` in Rust and `earthquake_plates.wgsl` (and the
  warp's copy of the trees and slabs, `eq_tree_data`, `EQ_TREES`, `EQ_SLABS`) are kept in step by `eq_wgsl_in_step` and
  `eq_tree_wgsl_in_step`. The warp is on from 5.6 to 31 s and culls nothing while it is (the game draws every resident
  section): most of its frame time.
- **The Earthquake's land can't carry block states**: `world.read-columns` answers names only, so stairs, slabs,
  fences, panes and doors on land that moves are written in their plain shape (only two-high halves, leaves'
  persistence and logs' axes are worked out), and blocks that hold items lose what they hold.
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
Planet Killer's, the Crystal Bloom's, the Sinkhole's, the Payload's, the Nuke's, the Rod's, the Supercell's, the
Hurricane's, the Tsunami's, the Supervolcano's, the Sky Breaks', the Carpet Bomb's, the World Eater's, the Convergence's, the Earthquake's, the Six Stars' and the Colossi's, each also at QUALITY FULL where it has a half-size stage). Mod: build, install, `./play.sh`, one
strike with terrain off, then one with terrain on in a throwaway world; the chat stays empty and the shaft reaches
bedrock. A change to the Colossi's plan: `mod_soak` with `SOAK_LASERS=colossi SOAK_FULL=1` on seeds 7, 9 and 11 (its
memory, besides its fuel). See [CONTRIBUTING.md](CONTRIBUTING.md).
Around every in-game strike run `tools/game_check.py mark` before it and `tools/game_check.py watch` (or `check`)
during and after it: if it reports the mod stopped (out of fuel, a panic, a failed start), the run failed, whatever it
looked like.
