# Native sweep: each laser on regular Horizon

Played on the native build (upstream Horizon `2093fb4d0` with this branch's bundle; 0.5.17's runs on `4626921`), off-screen under gamescope on an
RTX 4070 SUPER, Linux, render distance 19, creative, terrain damage on, each over fresh land. A laser counts as played
when it fires, runs to its end and the log shows no stop of the mod, no pass that failed to compile and no lost world
work.

## Fixed on this branch

- **All the game's sound stopping until a restart** (ALSA `POLLERR`): upstream's own fix (cd069f2, a run of stream
  errors reopens the output) is in the new pin. The error still happens during big strikes; the output is open again
  within a second each time, and what was playing that moment may be cut.
- **The Supervolcano's 35 s freeze**: upstream's `/forceload add` now waits on the server thread until its chunks are
  loaded (a9c7b82), and a strike sends a few hundred. The glue makes them chunk tickets instead.
- **The Supervolcano's uncarved chunks** (part): a re-read not answered within 3 s forgot its chunks; they go back on the
  list now.
- **Whole chunks left standing in big strikes' craters** (a test of the native test file then numbered 0.5.15, now 0.5.17, 2026-11-13: the Supervolcano and the
  Planet Killer): upstream drops a player's mod messages past 32 a server tick in silence, and the glue sent up to 32 a
  client tick, so with the server behind most of a strike's edits, reads and forceloads were lost. The glue now numbers
  its batches, the server half acknowledges them and at most 30 are out; edit runs go packed. Played after it, on the same
  land and seed as before: the Planet Killer, the Nuke, the
  Supervolcano and the Fold (un-greyed test build), each crater whole, no batch lost or sent again; the Fold's land, where
  runs without the fix lost 132,000-219,000 columns, all went in.
- **The Sky Breaks' island "made up (the land never answered)"**: it waits for its land until 0.8 s now, not 0.45 s.

## 0.5.17 on `4626921` (2026-11-16)

Upstream `4626921895` (main on 2026-11-15, the last before the new mod API, #17145) has horizon-rust/horizon#15875
(the sound output reopened without stopping the sounds), #13885 (NVIDIA frames) and #15878 (forced chunks past 4,096).
The game's sound went to a null sink and was recorded; each run its own fresh land, terrain on, KNOCKBACK on.

| Laser | Native | Notes |
| --- | --- | --- |
| Convergence | plays | twice; the crater lined by halves; sound from the omen through the blast; once the output stalled 5 s in and was reopened the same second, the sound going on |
| World Eater | plays | scripted twice, hunt once (caught on the third arch, carried on its track, spat out at 40.9 s); every hole in on time; the first run froze 36 s as it fired (its pass, a cold driver cache), none after |
| Nuke | plays | sound to the end, and three test sounds after it heard |
| Supervolcano | plays | 88 s with sound throughout; 9 chunks of its land never loaded (2,300-3,300 on `2093fb4d0`); no server lag logged |

## Each laser (terrain on)

Final run on the then-release file (`orbital-laser-native-v0.5.15.hnmod`, renumbered 0.5.17, sha256 `ee8bb087...`), 2026-11-12 23:06-23:24,
each over fresh land some 3,000 blocks from the last. Every laser fired and ran to its end; the mod never stopped and no
pass failed to compile.

| Laser | Native | Notes |
| --- | --- | --- |
| Plasma | plays | |
| Godly | plays | |
| Black Hole | plays | |
| Meteor Storm | plays | |
| Mothership | plays | |
| Downfall | plays | first strike in a session waits ~8 s for its pass to compile |
| Planet Killer | plays | server 2-5 s behind while its chunks load |
| Crystal Bloom | plays | |
| Sinkhole | plays | |
| Payload | plays | |
| Nuke | plays | once 27,726 columns of its land not loaded in time on fresh land (none the run before) |
| Rod from God | plays | once 22,885 columns not loaded in time on fresh land (none the run before) |
| Supercell | plays | |
| Hurricane | plays | carries the player (KNOCKBACK) |
| Tsunami | plays | carries the player; once 1,191 chunks not loaded in time on fresh land |
| Fold | held back | plays to its end natively; its water through the warp not seen right yet; on fresh land up to 92,000 columns of its land not loaded in time |
| Earthquake | held back | not built natively: it needs `render.set-view-offset`, `world.shift-player` and `render.set-warp-data`, which upstream lacks (stand-ins only) |
| Six Stars | plays | new in 0.5.17; one strike natively (terrain on, knockback on, over the sea): the climb, the star torn out of the screen, the fall, the blast, rubble; its pass compiled (one 2 s frame as it fired, the first build of the pass); sound throughout; no land left out; the crater not looked at from above |
| Supervolcano | plays, heavy | no freeze now; holds 5,836 chunks, past upstream's 4,096 its streaming scans them all: server ticks 400-800 ms, ~2,300-3,300 chunks of its land never load (fixed upstream by #15878: see 0.5.17 above). |
| Sky Breaks | plays | first strike waits ~12 s for its pass; island from the real land; a pane on land not loaded stays drawn |
| Carpet Bomb | plays | |

**Land not loaded in time:** on brand-new land the server generates the player's surroundings and a strike's chunks at
once, and natively some strikes' outer land isn't in before their deadline (left untouched there, logged). The fork
gives the same deadlines; how often it happens in ordinary play, firing over land already explored, isn't measured.

## Known, not fixed

- A strike's first frame waits for its post pass to compile if it fires before the pass has built in the background
  (most ~1-2 s, the Downfall ~8 s, the Sky Breaks ~12 s), once a session.
- The server falls a few seconds behind during the biggest strikes while their chunks generate.
