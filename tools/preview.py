#!/usr/bin/env python3
"""Look at a strike without the game: render its post pass offscreen (tools/preview, over a synthetic scene of sky,
rolling ground and a cloud layer) at the moments and from the views asked for, and put them on one labelled contact
sheet. Seconds a sheet, against a rebuild, a restart and a whole strike in the game.

    tools/preview.py downfall 14.5 30 31 45            # those moments, from the default views
    tools/preview.py downfall 28 30 --views far,under  # from those views
    tools/preview.py mothership 12 --bench             # and how long the pass takes on the GPU (median of 9)
    tools/preview.py downfall 30 --set mode=2 colour=1 # any of the preview's keys (see tools/preview/src/main.rs)
    tools/preview.py payload 18 --quality both --bench # QUALITY FULL and FAST side by side (the payload's half-size
                                                       # stage; --whole: FAST as a game without the stages draws it)
    tools/preview.py rod 7.05 --set rdif=0             # the Rod's other impact frames (rod.wgsl's RD_IF_STYLE: 0 the
                                                       # black flash, 1 Kanada, 2 cinematic)

The sheet is dist/preview/<laser>.jpg (each frame beside it as NN.png). The scene is not the game's: what the pass
reads from the world (its depth, the clouds, the time of day) is like it, not the same. The look and the timing are the
real pass's, built from the shaders exactly as the mod builds it.
"""
import argparse
import os
import re
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHADERS = ROOT / "mod" / "shaders"
LASERS = ["plasma", "godly", "blackhole", "meteor", "mothership", "downfall", "planetkiller", "crystalbloom", "sinkhole", "payload", "nuke", "rod", "supercell", "hurricane", "tsunami"]
# the shader's laser number where it is not the list's place (lasers.rs's index)
INDEX = {"supercell": 12, "hurricane": 13, "tsunami": 16}
# Where the eye is (the target is at 0.5 65 0.5, the player 60 blocks south of it, so the ships lie away north)
VIEWS = {
    "player": "cx=0 cy=70 cz=60 yaw=-90 pitch=28",
    "mid": "cx=0 cy=95 cz=420 yaw=-90 pitch=16 mx=0 mz=420",
    "nexus": "cx=0 cy=290 cz=170 lx=0.5 ly=365 lz=0.5 mx=0 mz=420",
    "up": "cx=0 cy=70 cz=60 yaw=-90 pitch=70",
    "far": "cx=0 cy=110 cz=900 yaw=-90 pitch=6 mx=0 mz=60",
    "side": "cx=1700 cy=200 cz=-250 yaw=180 pitch=6 mx=0 mz=60",
    "under": "cx=0 cy=72 cz=-250 yaw=-90 pitch=80 mx=0 mz=60",
    "aerial": "cx=0 cy=900 cz=1100 yaw=-90 pitch=-32 mx=0 mz=60",
    # the planet killer's first tower, a few hundred blocks off it (it stands beyond the target from the player)
    "tower": "cx=180 cy=80 cz=-420 lx=0 ly=170 lz=-1150 mx=0 mz=60",
    # and close under it, its crown and its seams
    "towerclose": "cx=160 cy=110 cz=-560 lx=0 ly=230 lz=-1130 mx=0 mz=60",
    # the crystal bloom: from where the player would watch it (330 blocks off), from far off, close under its spires,
    # from the side, and from above the aftermath
    "cbplayer": "cx=0 cy=80 cz=330 lx=0.5 ly=125 lz=0.5",
    "cbfar": "cx=0 cy=130 cz=950 lx=0.5 ly=150 lz=0.5",
    "spire": "cx=70 cy=74 cz=150 lx=0 ly=150 lz=0 mx=0 mz=330",
    "cbside": "cx=620 cy=110 cz=-120 lx=0.5 ly=140 lz=0.5 mx=0 mz=330",
    "cbaerial": "cx=0 cy=360 cz=380 lx=0.5 ly=60 lz=0.5 mx=0 mz=330",
    # flying over it at a distance, as the clip is filmed, at night
    "cbover": "cx=320 cy=430 cz=560 lx=0.5 ly=90 lz=0.5 mx=0 mz=330 night=1",
    # close on the ground heaving over the fifth of the first shards (4.9 to 6.2 s) and from a little further off
    "cbheave": "cx=30 cy=76 cz=86 lx=17 ly=66 lz=56 mx=0 mz=330",
    # close on one of the pieces as it comes down and lies there (piece 52 of seed 37, down at 27.48 s)
    "cbland": "cx=-31.4 cy=77 cz=192.1 lx=-53.4 ly=63 lz=170.1 mx=0 mz=330",
    "cbheavefar": "cx=60 cy=110 cz=170 lx=17 ly=66 lz=56 mx=0 mz=330",
    # the sinkhole (over flat land, its pit dug into the scene as the collapse reaches it: pit=1): from 300 blocks off,
    # close at the edge, looking down into it from over the rim, from high above, and low over the cracking land
    "shplayer": "cx=0 cy=100 cz=300 lx=0.5 ly=45 lz=0.5 flat=1 pit=1",
    "shedge": "cx=25 cy=72 cz=150 lx=0 ly=45 lz=30 flat=1 pit=1",
    "shdown": "cx=10 cy=150 cz=150 lx=0 ly=-20 lz=0 flat=1 pit=1",
    "shaerial": "cx=0 cy=430 cz=330 lx=0.5 ly=40 lz=0.5 flat=1 pit=1",
    "shground": "cx=50 cy=69 cz=110 lx=0 ly=64 lz=20 flat=1 pit=1",
    "shclose": "cx=-20 cy=95 cz=105 lx=10 ly=55 lz=40 flat=1 pit=1",
    # close on the slabs of the second and third rings as they let go, and over the cracks before
    "shslab": "cx=-28 cy=80 cz=78 lx=0 ly=60 lz=30 flat=1 pit=1",
    # across the pit at a waterfall on its far side (SH_WATER=-1.57 in the environment)
    "shfall": "cx=10 cy=80 cz=60 lx=0 ly=35 lz=-110 flat=1 pit=1",
    "shfallclose": "cx=3 cy=62 cz=-70 lx=0 ly=50 lz=-112 fov=50",
    # the payload (the player 300 blocks south of the target, on flat land): looking at it over the land, up at the
    # sky where the object drifts, from far off, from overhead, and close by the player as the dust arrives
    "plplayer": "cx=0 cy=67 cz=300 lx=0.5 ly=110 lz=0.5 flat=1",
    "plsky": "cx=0 cy=67 cz=300 lx=0 ly=330 lz=40 flat=1",
    "plfar": "cx=150 cy=90 cz=1000 lx=0.5 ly=150 lz=0.5 flat=1",
    "pltop": "cx=0 cy=700 cz=420 lx=0.5 ly=65 lz=0.5 flat=1",
    "plnear": "cx=0 cy=67 cz=300 lx=-30 ly=70 lz=240 flat=1",
    # set up like the reference clip's camera: third person at head height 450 blocks off in a wood, the target a
    # little left of the middle, the horizon a little under it, a 59 degree (vertical) field of view
    "plref": "cx=0 cy=68.5 cz=450 lx=12 ly=94 lz=0.5 flat=1 trees=1 fov=59 reach=450",
    # the same, looking up at the object as it drifts (the clip's 6-9 s)
    # the same on hilly land (hills 28 high round the target, the eye in a hollow 450 off), over the land, low along
    # the ground near the eye as the dust comes over the rise, and from high off to one side over the hills
    "plhill": "cx=0 cy=51.5 cz=450 lx=12 ly=80 lz=0.5 hills=28 trees=1 fov=59 reach=450",
    "plhilllow": "cx=0 cy=51.5 cz=450 lx=-40 ly=50 lz=300 hills=28 trees=1 fov=70 reach=450",
    "plhillside": "cx=520 cy=150 cz=330 lx=0 ly=60 lz=200 hills=28 trees=1 fov=60 reach=450",
    "plrefsky": "cx=0 cy=68.5 cz=450 lx=-60 ly=330 lz=40 flat=1 trees=1 fov=59 reach=450",
    # the same, close on the old high trail as it ages and breaks up (where it showed a ladder of stripes)
    # from high up and off to one side, looking down at the target (the middle of the frame): the column's foot over it
    "plover": "cx=-220 cy=420 cz=260 lx=0.5 ly=65 lz=0.5 flat=1 fov=60",
    # level from the south and from the east, 400 off, the target in the middle: where the column's foot stands
    "plfoot": "cx=0.5 cy=70 cz=400.5 lx=0.5 ly=70 lz=0.5 fov=40 flat=1",
    "plfoote": "cx=400.5 cy=70 cz=0.5 lx=0.5 ly=70 lz=0.5 fov=40 flat=1",
    "pltrail": "cx=0 cy=68.5 cz=450 lx=-150 ly=430 lz=40 flat=1 trees=1 fov=22 reach=450",
    # as the third clip is filmed: across a canyon some 1,600 blocks off, looking up at the trail and the column; close
    # by (230 off) looking up at the object coming in; and the same from 230 looking at the column as it settles
    "pl3far": "cx=0 cy=120 cz=1600 lx=0.5 ly=420 lz=0.5 flat=1 fov=50 reach=1600",
    "pl3close": "cx=0 cy=67 cz=230 lx=60 ly=300 lz=0.5 flat=1 trees=1 fov=70 reach=230",
    "pl3col": "cx=0 cy=67 cz=230 lx=0.5 ly=150 lz=0.5 flat=1 trees=1 fov=70 reach=230",
    # close by the crater (45 off), looking up at the column's foot and over it (with sunel=1 sunaz=200: as the user
    # saw it at dusk)
    "plclose": "cx=0 cy=69 cz=45 lx=0.5 ly=120 lz=0.5 flat=1 fov=75 reach=45",
    # high up, some 250 blocks off, the column large in the frame (as the user saw its lumps lined up in a grid)
    "plhigh": "cx=60 cy=190 cz=240 lx=0.5 ly=150 lz=0.5 flat=1 fov=60 reach=250",
    # the nuke: from 700 blocks off on the ground (the player's), from 1,800 off, 350 off as the shockwave arrives,
    # looking up at the bomb as it falls, from high above, and at dusk from the player's spot (add sunel=2 sunaz=200)
    "nkplayer": "cx=0 cy=67 cz=700 lx=0.5 ly=220 lz=0.5 flat=1 trees=1 fov=70 reach=700",
    "nkfar": "cx=150 cy=100 cz=1800 lx=0.5 ly=280 lz=0.5 flat=1 fov=60 reach=1800",
    "nkclose": "cx=0 cy=67 cz=350 lx=0.5 ly=260 lz=0.5 flat=1 trees=1 fov=80 reach=350",
    "nksky": "cx=0 cy=67 cz=700 lx=-150 ly=700 lz=0 flat=1 trees=1 fov=70 reach=700",
    "nkaerial": "cx=0 cy=1100 cz=1300 lx=0.5 ly=65 lz=0.5 flat=1 fov=60 reach=700",
    # the fireball's foot: low by the ground 260 off; on hills with the target on a slope (from the player's spot and
    # low, 260 off); and on hills with the target 13 over the land round it (a hit on a treetop or a ledge)
    "nklow": "cx=0 cy=67 cz=260 lx=0.5 ly=50 lz=0.5 flat=1 trees=1 fov=75 reach=260",
    "nkhill": "cx=0 cy=110 cz=700 lx=0.5 ly=150 lz=0.5 hills=40 flush=1 trees=1 fov=70 reach=700",
    "nkhilllow": "cx=0 cy=63 cz=260 lx=0.5 ly=50 lz=0.5 hills=40 flush=1 trees=1 fov=75 reach=260",
    "nkdip": "cx=0 cy=140 cz=420 lx=0.5 ly=70 lz=0.5 hills=-40 trees=1 fov=70 reach=700",
    # the rod from god: from 300 blocks off on the ground (the player's), looking up at it tearing down, 600 off, 1,500
    # off, close by (150) as the front arrives, from high above, and on hills
    "rdplayer": "cx=0 cy=67 cz=300 lx=0.5 ly=120 lz=0.5 flat=1 trees=1 fov=70 reach=300",
    "rdsky": "cx=0 cy=67 cz=300 lx=-60 ly=1400 lz=-500 flat=1 trees=1 fov=70 reach=300",
    "rdmid": "cx=0 cy=70 cz=600 lx=0.5 ly=160 lz=0.5 flat=1 trees=1 fov=60 reach=600",
    "rdfar": "cx=120 cy=100 cz=1500 lx=0.5 ly=260 lz=0.5 flat=1 fov=50 reach=1500",
    "rdclose": "cx=0 cy=67 cz=150 lx=0.5 ly=110 lz=0.5 flat=1 trees=1 fov=80 reach=150",
    "rdaerial": "cx=0 cy=700 cz=700 lx=0.5 ly=65 lz=0.5 flat=1 fov=60 reach=300",
    "rdhill": "cx=0 cy=100 cz=500 lx=0.5 ly=110 lz=0.5 hills=30 flush=1 trees=1 fov=70 reach=500",
    # close (150 off) and 400 off at the target, and from 150 off looking straight up the rod's path as it comes down
    "rdnear": "cx=0 cy=67 cz=150 lx=0.5 ly=95 lz=0.5 flat=1 trees=1 fov=75 reach=150 rdpit=1",
    "rd400": "cx=0 cy=67 cz=400 lx=0.5 ly=140 lz=0.5 flat=1 trees=1 fov=70 reach=400 rdpit=1",
    "rdup": "cx=0 cy=67 cz=150 lx=0.5 ly=1200 lz=-60 flat=1 trees=1 fov=80 reach=150 rdpit=1",
    # looking down into the crater from its rim (the hot hole at its bottom)
    "rdfall": "cx=0 cy=67 cz=150 lx=0.5 ly=190 lz=0.5 flat=1 trees=1 fov=75 reach=150 rdpit=1",
    # the rod standing in its crater, from 90 off and over the rim
    "rdstand": "cx=0 cy=105 cz=100 lx=0.5 ly=55 lz=0.5 flat=1 fov=70 reach=95 rdpit=1",
    "rdhole": "cx=0 cy=118 cz=78 lx=0.5 ly=30 lz=0.5 flat=1 fov=70 reach=95 rdpit=1",
    # down in the crater by the rod's foot, the floor heaved round it (with vox=1 and PREVIEW_VOXELS the heave's real
    # blocks: `RD_VOX_OUT=path cargo test --release rod_heaves_the_floor_round_its_foot`), from the floor and over it
    "rdfoot": "cx=8 cy=24 cz=42 lx=0.5 ly=22 lz=0.5 flat=1 fov=70 reach=95 rdpit=1",
    "rdfootup": "cx=0 cy=62 cz=40 lx=0.5 ly=15 lz=0.5 flat=1 fov=70 reach=95 rdpit=1",
    # looking up the plume's column from 300 and 900 off, and from under it close by
    "rddown": "cx=0.5 cy=60 cz=30 lx=0.5 ly=15 lz=0.4 flat=1 fov=70 reach=95 rdpit=1",
    "rdplume": "cx=0 cy=67 cz=300 lx=0.5 ly=230 lz=0.5 flat=1 trees=1 fov=70 reach=300",
    "rdplumefar": "cx=0 cy=90 cz=900 lx=0.5 ly=200 lz=0.5 flat=1 fov=50 reach=900",
    "rdplumeup": "cx=0 cy=67 cz=150 lx=0.5 ly=330 lz=0.5 flat=1 trees=1 fov=80 reach=150 rdpit=1",
    # the supercell (the player 300 blocks south): from the player's spot, from under the cloud by the wall cloud
    # looking up at it, from 900 off, from high above, close by a funnel (the first of seed 37's), and at night
    "scplayer": "cx=0 cy=67 cz=300 lx=0.5 ly=110 lz=0.5 flat=1 trees=1 fov=70 reach=300",
    "scunder": "cx=0 cy=67 cz=90 lx=0.5 ly=120 lz=0.5 flat=1 trees=1 fov=75 reach=90",
    "scfar": "cx=150 cy=90 cz=900 lx=0.5 ly=160 lz=0.5 flat=1 fov=60 reach=900",
    "scaerial": "cx=0 cy=700 cz=600 lx=0.5 ly=65 lz=0.5 flat=1 fov=60 reach=300",
    "scfunnel": "cx=0 cy=68 cz=160 lx=0.5 ly=85 lz=0.5 flat=1 trees=1 fov=60 reach=160",
    "scnight": "cx=0 cy=67 cz=300 lx=0.5 ly=110 lz=0.5 flat=1 trees=1 fov=70 reach=300 night=1",
    # the first funnel of seed 37 (13.9 to 29.4 s, wandering about x 25..48, z -12..41) close (~150 off) and far (~400),
    # over a wood
    "vxclose": "cx=35 cy=72 cz=165 lx=35 ly=75 lz=15 flat=1 trees=1 fov=60 reach=300",
    "vxfar": "cx=35 cy=85 cz=415 lx=35 ly=85 lz=15 flat=1 trees=1 fov=45 reach=300",
    # the hurricane (over a wood, its trees torn up as the front reaches them: hustrip=1): from 300 blocks off on the
    # ground (the player's), from 800, close under the eyewall, in the eye looking up at it, carried round it (where
    # the carry takes the player: 108 out, 50 up), from high above, and on wooded hills
    "huplayer": "cx=0 cy=67 cz=300 lx=0.5 ly=95 lz=0.5 flat=1 trees=1 hustrip=1 fov=75 reach=300",
    "hufar": "cx=0 cy=80 cz=800 lx=0.5 ly=130 lz=0.5 flat=1 trees=1 hustrip=1 fov=65 reach=800",
    "huunder": "cx=10 cy=68 cz=100 lx=-30 ly=105 lz=20 flat=1 trees=1 hustrip=1 fov=80 reach=100",
    "hueye": "cx=0 cy=67 cz=6 lx=0 ly=150 lz=-70 flat=1 trees=1 hustrip=1 fov=85 reach=6",
    "hucarried": "cx=108 cy=115 cz=0 lx=0 ly=95 lz=-70 flat=1 trees=1 hustrip=1 fov=80 reach=108",
    "hutrees": "cx=70 cy=70 cz=60 lx=-60 ly=85 lz=-10 flat=1 trees=1 hustrip=1 fov=80 reach=92",
    # the same, looking up at the eyewall's top from the ground (300 off) and from 800, and from the side, 1,500 off
    "huplayerup": "cx=0 cy=67 cz=300 lx=0.5 ly=190 lz=0.5 flat=1 trees=1 hustrip=1 fov=80 reach=300",
    "hufarup": "cx=0 cy=80 cz=800 lx=0.5 ly=200 lz=0.5 flat=1 trees=1 hustrip=1 fov=65 reach=800",
    "huside": "cx=-1300 cy=260 cz=700 lx=0.5 ly=150 lz=0.5 flat=1 fov=55 reach=300",
    # close on the blocks and trees flying round the eyewall (textured, with the atlas), from 25 and 60 off
    "hutex": "cx=96 cy=76 cz=-6 lx=70 ly=74 lz=-30 flat=1 trees=1 hustrip=1 fov=60 reach=96",
    "hutex2": "cx=118 cy=78 cz=10 lx=60 ly=68 lz=-35 flat=1 trees=1 hustrip=1 fov=55 reach=118",
    "huaerial": "cx=0 cy=900 cz=1100 lx=0.5 ly=65 lz=0.5 flat=1 fov=60 reach=300",
    "huhill": "cx=0 cy=110 cz=320 lx=0.5 ly=100 lz=0.5 hills=30 flush=1 trees=1 hustrip=1 fov=75 reach=320",
    # as the space station saw Florence: from 2,400 up and 1,700 off, looking down across it; and straight down on it
    "huorbit": "cx=0 cy=2400 cz=1700 lx=0.5 ly=65 lz=-150 flat=1 fov=60 reach=300",
    "hutop": "cx=0 cy=1900 cz=1 lx=0.5 ly=65 lz=0.5 flat=1 fov=75 reach=300",
    # in the eye on the ground looking straight up the stadium, and in it 90 up (where the carry takes the player at
    # its height) looking across at the far wall
    "hueyeup": "cx=0 cy=67 cz=4 lx=0 ly=300 lz=-45 flat=1 trees=1 hustrip=1 fov=100 reach=4",
    "hueyemid": "cx=8 cy=155 cz=6 lx=-60 ly=185 lz=-30 flat=1 trees=1 hustrip=1 fov=95 reach=10",
    # close on the cloud: its gathering storms from 250 off on the ground, the deck from 700 up over its bands
    "hucells": "cx=0 cy=67 cz=250 lx=0.5 ly=200 lz=-150 flat=1 trees=1 fov=70 reach=250",
    "hudeck": "cx=600 cy=700 cz=600 lx=300 ly=200 lz=200 flat=1 fov=60 reach=300",
    # looking along the debris field at the eyewall's foot from 180 out and from 110, as a player sees it
    "hufield": "cx=0 cy=68 cz=180 lx=0.5 ly=130 lz=0.5 flat=1 trees=1 hustrip=1 fov=55 reach=180",
    "hufieldnear": "cx=60 cy=70 cz=95 lx=-20 ly=110 lz=0 flat=1 trees=1 hustrip=1 fov=60 reach=110",
    # the tsunami (the player 300 blocks south of the target, the wave coming from the north over a wood): from the
    # player's spot looking at the horizon it rises on, at the target as it hits, up at the face towering overhead,
    # from the side, from high above, and 120 off as it arrives
    "tsplayer": "cx=0 cy=67 cz=300 lx=0.5 ly=95 lz=-300 flat=1 trees=1 fov=70 reach=300",
    "tshorizon": "cx=0 cy=67 cz=300 lx=0.5 ly=110 lz=-900 flat=1 trees=1 fov=70 reach=300",
    "tsup": "cx=0 cy=67 cz=300 lx=0.5 ly=190 lz=100 flat=1 trees=1 fov=80 reach=300",
    "tsside": "cx=1400 cy=140 cz=-200 lx=0.5 ly=90 lz=-200 flat=1 trees=1 fov=60 reach=300",
    "tsaerial": "cx=0 cy=500 cz=900 lx=0.5 ly=65 lz=-100 flat=1 trees=1 fov=60 reach=300",
    "tsnear": "cx=0 cy=67 cz=300 lx=0.5 ly=95 lz=120 flat=1 trees=1 fov=80 reach=300",
    "tsunder": "cx=0 cy=67 cz=300 lx=0.5 ly=62 lz=-300 flat=1 trees=1 fov=75 reach=300",
    "tsunderup": "cx=0 cy=67 cz=300 lx=40 ly=200 lz=100 flat=1 trees=1 fov=80 reach=300",
    "tsfar": "cx=0 cy=75 cz=1100 lx=0.5 ly=110 lz=-300 flat=1 trees=1 fov=60 reach=1100",
    # on hills, as the clip is filmed; riding the falling water (from 40 over the land, and a few over it), looking back
    # the way it goes
    "tshill": "cx=0 cy=74 cz=300 lx=0.5 ly=100 lz=-300 hills=30 trees=1 fov=70 reach=300",
    "tsride": "cx=0 cy=104 cz=250 lx=0.5 ly=88 lz=-300 flat=1 trees=1 fov=70 reach=300",
    "tsdeb": "cx=0 cy=67 cz=300 lx=0.5 ly=80 lz=-300 flat=1 fov=70 reach=300",
    "tsridelow": "cx=0 cy=72 cz=220 lx=0.5 ly=66 lz=-300 hills=20 trees=1 fov=70 reach=300",
}
DEFAULT_VIEWS = {"downfall": "player,far,side", "mothership": "player,far", "planetkiller": "player,far,side",
                 "crystalbloom": "cbplayer,cbfar,spire", "sinkhole": "shplayer,shedge,shdown",
                 "payload": "plplayer,plsky,pltop", "nuke": "nkplayer,nkfar,nkclose",
                 "rod": "rdplayer,rdmid,rdfar",
                 "supercell": "scplayer,scunder,scfar",
                 "hurricane": "huplayer,hufar,huunder,huaerial",
                 "tsunami": "tsplayer,tsside,tsaerial"}


def build_pass(laser: str, out: pathlib.Path, fast: bool = False, sets: tuple = ()) -> pathlib.Path:
    """The pass as the mod builds it (mod/src/lib.rs): strike.wgsl, or for the downfall and the planet killer
    strike.wgsl up to its fs_main less the other lasers' own functions, then downfall.wgsl or planetkiller.wgsl. Its
    half-size stage (`[half stage]`) kept only for QUALITY FAST (`fast`)."""
    path = out / ("pass-fast.wgsl" if fast else "pass.wgsl")
    strike = (SHADERS / "strike.wgsl").read_text()
    if laser in ("downfall", "planetkiller", "crystalbloom", "sinkhole", "payload", "nuke", "rod", "supercell", "hurricane", "tsunami"):
        pre = subprocess.run(["sed", "-e", r"/^\/\/ \[lasers pass only\]/,/^\/\/ \[end lasers pass only\]/d", "-e", "/^@fragment/,$d"],
                             input=strike, capture_output=True, text=True, check=True).stdout
        own = (SHADERS / f"{laser}.wgsl").read_text()
        if not fast:
            own = subprocess.run(["sed", "-e", r"/^\/\/ \[half stage\]/,/^\/\/ \[end half stage\]/d"],
                                 input=own, capture_output=True, text=True, check=True).stdout
        # (the Rod's impact frames in another of their looks: `--set rdif=N`)
        rdif = next((kv.split("=", 1)[1] for kv in sets if kv.startswith("rdif=")), None)
        if rdif is not None:
            own = re.sub(r"const RD_IF_STYLE: i32 = \d+;", f"const RD_IF_STYLE: i32 = {int(rdif)};", own)
        path.write_text(pre + own)
    else:
        path.write_text(strike)
    return path


def mod_data(laser: str, out: pathlib.Path, sets: list, pl_reach: str = "300") -> dict:
    """The Crystal Bloom's and the Sinkhole's passes read their tables from the mod's data (render.set-data): work it out
    for the strike's seed, as the mod does (the Sinkhole's waterfall, with SH_WATER=angle in the environment)."""
    if laser == "crystalbloom":
        return crystal_data(out, sets)
    if laser in ("payload", "nuke", "rod", "supercell", "hurricane", "tsunami"):
        seed = next((kv.split("=", 1)[1] for kv in sets if kv.startswith("seed=")), "37")
        path = (out / "data.txt").resolve()
        hills = next((kv.split("=", 1)[1] for kv in sets if kv.startswith("hills=")), "0")
        env = dict(os.environ, CB_SEED=seed, CB_OUT=str(path), PL_ME=f"0,65,{pl_reach}", PL_HILLS=hills,
                   PL_FLUSH="1" if "flush=1" in sets else "0")
        if laser in ("hurricane", "tsunami") and ATLAS:
            # (the blocks' sprites as the fake atlas has them, matching the stand-in arrays the preview binds)
            env["HU_ATLAS_JSON"] = str(ATLAS / "atlas.txt")
        test = {"nuke": "nk_write_table", "rod": "rd_write_table", "supercell": "sc_write_table", "hurricane": "hu_write_table", "tsunami": "ts_write_table"}.get(laser, "pl_write_table")
        subprocess.run(["cargo", "test", "--release", "--quiet", "--lib", test, "--", "--ignored"],
                       cwd=ROOT / "mod", env=env, check=True, capture_output=True)
        return dict(os.environ, PREVIEW_DATA=str(path))
    seed = next((kv.split("=", 1)[1] for kv in sets if kv.startswith("seed=")), "37")
    path = (out / "data.txt").resolve()
    env = dict(os.environ, CB_SEED=seed, CB_OUT=str(path))
    subprocess.run(["cargo", "test", "--release", "--quiet", "--lib", "sh_write_table", "--", "--ignored"],
                   cwd=ROOT / "mod", env=env, check=True, capture_output=True)
    return dict(os.environ, PREVIEW_DATA=str(path))


def crystal_data(out: pathlib.Path, sets: list) -> dict:
    """The Crystal Bloom's pass reads its spires and pieces from the mod's data (render.set-data, mod/src/strike/
    crystal.rs's cb_table): work it out for the strike's seed, as the mod does, and hand it to the preview."""
    seed = next((kv.split("=", 1)[1] for kv in sets if kv.startswith("seed=")), "37")
    path = (out / "data.txt").resolve()
    env = dict(os.environ, CB_SEED=seed, CB_OUT=str(path))
    subprocess.run(["cargo", "test", "--release", "--quiet", "--lib", "cb_write_table", "--", "--ignored"],
                   cwd=ROOT / "mod", env=env, check=True, capture_output=True)
    if "PREVIEW_DATA" in os.environ:
        # (the landings, cb_drop's words under the table, from a file of the caller's)
        path.write_text(pathlib.Path(os.environ["PREVIEW_DATA"]).read_text() + path.read_text())
    return dict(os.environ, PREVIEW_DATA=str(path))


ATLAS = None


def atlas(out: pathlib.Path):
    """The Hurricane's textured blocks: a stand-in for the game's block sprite arrays from the player's own prepared
    resources (tools/hu_atlas.py; made once into dist/preview/atlas), or none if there are none to make it from."""
    global ATLAS
    d = out.parent / "atlas"
    if not (d / "atlas.raw").exists():
        r = subprocess.run([sys.executable, str(ROOT / "tools" / "hu_atlas.py"), str(d)], capture_output=True, text=True)
        if r.returncode != 0:
            print("no textures (tools/hu_atlas.py: " + r.stderr.strip().splitlines()[-1] + ")", file=sys.stderr)
            return
    ATLAS = d.resolve()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("laser", choices=LASERS)
    ap.add_argument("times", nargs="+", type=float, help="seconds into the strike")
    ap.add_argument("--views", help=f"comma-separated, of {', '.join(VIEWS)}")
    ap.add_argument("--set", nargs="*", default=[], metavar="KEY=VALUE", help="more of the preview's keys, for every shot")
    ap.add_argument("--size", default="800x450")
    ap.add_argument("--bench", action="store_true", help="time the pass (median of 9 draws a shot)")
    ap.add_argument("--quality", choices=["full", "fast", "both"], default="full",
                    help="QUALITY FULL, FAST (the half-size stage), or both side by side (a column each a view)")
    ap.add_argument("--whole", action="store_true", help="FAST drawn as a game without half-size stages draws it: fs_main alone")
    ap.add_argument("--out", type=pathlib.Path, default=ROOT / "dist" / "preview")
    ap.add_argument("--notex", action="store_true", help="the Hurricane's blocks in their average colours, not textured")
    a = ap.parse_args()

    tool = ROOT / "tools" / "preview"
    exe = tool / "target" / "release" / "preview"
    subprocess.run(["cargo", "build", "--release", "--quiet"], cwd=tool, check=True)
    out = a.out / a.laser
    out.mkdir(parents=True, exist_ok=True)
    views = (a.views or DEFAULT_VIEWS.get(a.laser, "player")).split(",")
    if a.laser in ("hurricane", "tsunami") and not a.notex:
        atlas(out)
    qualities = ["full", "fast"] if a.quality == "both" else [a.quality]
    w, h = a.size.split("x")
    common = [f"laser={INDEX.get(a.laser, LASERS.index(a.laser))}", "clouds=0", f"w={w}", f"h={h}", f"frames={9 if a.bench else 1}", *a.set]
    if a.laser in ("payload", "nuke", "rod", "supercell", "hurricane", "tsunami"):
        # (where the player stood as it fired, in the params the pass reads it from: payload.wgsl's `me`)
        common += ["mode=0", "style=65", "reach=300"]
    shots = []
    for t in a.times:
        for v in views:
            shots += ["--", f"t={t}", *VIEWS[v].split()]
    # (the payload's player: 300 blocks south, or as far as the first view puts them)
    pl_reach = next((kv.split("=", 1)[1] for kv in VIEWS[views[0]].split() + a.set if kv.startswith("reach=")), "300")
    # (and on the first view's land: its hills, if any, in the payload's heightfield)
    env = mod_data(a.laser, out, [kv for kv in VIEWS[views[0]].split() if kv.startswith("hills=")] + a.set, pl_reach) if a.laser in ("crystalbloom", "sinkhole", "payload", "nuke", "rod", "supercell", "hurricane", "tsunami") else None
    env = dict(env or os.environ)
    if ATLAS:
        env["PREVIEW_ATLAS"] = str(ATLAS / "atlas.raw")
    if a.whole:
        env["PREVIEW_WHOLE"] = "1"
    # each quality's frames, in their own folder; on the sheet a row a moment, a column a view (and a quality)
    frames, labels = {}, {}
    for q in qualities:
        qout = out / q if len(qualities) > 1 else out
        qout.mkdir(parents=True, exist_ok=True)
        shader = build_pass(a.laser, out, q == "fast", a.set)
        r = subprocess.run([str(exe), str(shader), str(qout), *common, *shots], capture_output=True, text=True, env=env)
        if r.returncode != 0:
            print(r.stderr, file=sys.stderr)
            return 1
        tag = f"  {q.upper()}" if len(qualities) > 1 or q != "full" else ""
        n = 0
        times = [l.split(": pass ")[1] for l in r.stderr.splitlines() if ": pass " in l]
        for t in a.times:
            for v in views:
                label = f"{t:g} s  {v}{tag}"
                frames[(t, v, q)] = Image.open(qout / f"{n:02}.png").convert("RGB")
                labels[(t, v, q)] = label
                if a.bench:
                    print(f"{label:>24}: {times[n]}")
                n += 1
    keys = [(t, v, q) for t in a.times for v in views for q in qualities]
    cols = len(views) * len(qualities)
    # the sheet: a row a moment, a column a view
    fw, fh = frames[keys[0]].size
    sheet = Image.new("RGB", (fw * cols, fh * len(a.times)))
    d = ImageDraw.Draw(sheet)
    for i, key in enumerate(keys):
        f, label = frames[key], labels[key]
        x, y = fw * (i % cols), fh * (i // cols)
        sheet.paste(f, (x, y))
        d.rectangle([x, y, x + 8 * len(label) + 10, y + 18], fill=(0, 0, 0))
        d.text((x + 5, y + 3), label, fill=(255, 255, 255))
    path = a.out / f"{a.laser}.jpg"
    sheet.save(path, quality=88)
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
