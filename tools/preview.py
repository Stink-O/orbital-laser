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

The sheet is dist/preview/<laser>.jpg (each frame beside it as NN.png). The scene is not the game's: what the pass
reads from the world (its depth, the clouds, the time of day) is like it, not the same. The look and the timing are the
real pass's, built from the shaders exactly as the mod builds it.
"""
import argparse
import os
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHADERS = ROOT / "mod" / "shaders"
LASERS = ["plasma", "godly", "blackhole", "meteor", "mothership", "downfall", "planetkiller", "crystalbloom", "sinkhole", "payload", "nuke"]
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
}
DEFAULT_VIEWS = {"downfall": "player,far,side", "mothership": "player,far", "planetkiller": "player,far,side",
                 "crystalbloom": "cbplayer,cbfar,spire", "sinkhole": "shplayer,shedge,shdown",
                 "payload": "plplayer,plsky,pltop", "nuke": "nkplayer,nkfar,nkclose"}


def build_pass(laser: str, out: pathlib.Path, fast: bool = False, cloud: str = "current") -> pathlib.Path:
    """The pass as the mod builds it (mod/src/lib.rs): strike.wgsl, or for the downfall and the planet killer
    strike.wgsl up to its fs_main less the other lasers' own functions, then downfall.wgsl or planetkiller.wgsl. Its
    half-size stage (`[half stage]`) kept only for QUALITY FAST (`fast`)."""
    path = out / ("pass-fast.wgsl" if fast else "pass.wgsl")
    strike = (SHADERS / "strike.wgsl").read_text()
    if laser in ("downfall", "planetkiller", "crystalbloom", "sinkhole", "payload", "nuke"):
        pre = subprocess.run(["sed", "-e", r"/^\/\/ \[lasers pass only\]/,/^\/\/ \[end lasers pass only\]/d", "-e", "/^@fragment/,$d"],
                             input=strike, capture_output=True, text=True, check=True).stdout
        own = (SHADERS / f"{laser}.wgsl").read_text()
        if laser == "nuke" and cloud not in ("current", "0", "9"):
            # (an earlier cloud, spliced in as the mod does: tools/nuke_cloud.py)
            sys.path.insert(0, str(ROOT / "tools"))
            import nuke_cloud
            own = nuke_cloud.splice(own, (SHADERS / "nuke_cloud" / f"v{int(cloud.lstrip('v'))}.wgsl").read_text())
        if not fast:
            own = subprocess.run(["sed", "-e", r"/^\/\/ \[half stage\]/,/^\/\/ \[end half stage\]/d"],
                                 input=own, capture_output=True, text=True, check=True).stdout
        path.write_text(pre + own)
    else:
        path.write_text(strike)
    return path


def mod_data(laser: str, out: pathlib.Path, sets: list, pl_reach: str = "300") -> dict:
    """The Crystal Bloom's and the Sinkhole's passes read their tables from the mod's data (render.set-data): work it out
    for the strike's seed, as the mod does (the Sinkhole's waterfall, with SH_WATER=angle in the environment)."""
    if laser == "crystalbloom":
        return crystal_data(out, sets)
    if laser in ("payload", "nuke"):
        seed = next((kv.split("=", 1)[1] for kv in sets if kv.startswith("seed=")), "37")
        path = (out / "data.txt").resolve()
        hills = next((kv.split("=", 1)[1] for kv in sets if kv.startswith("hills=")), "0")
        env = dict(os.environ, CB_SEED=seed, CB_OUT=str(path), PL_ME=f"0,65,{pl_reach}", PL_HILLS=hills)
        test = "nk_write_table" if laser == "nuke" else "pl_write_table"
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
    ap.add_argument("--cloud", default="current", help="the Nuke's cloud: 1-8 (an earlier one, tools/nuke_cloud.py) or current")
    ap.add_argument("--out", type=pathlib.Path, default=ROOT / "dist" / "preview")
    a = ap.parse_args()
    # (`--set nkcloud=N` is the same as `--cloud N`)
    for kv in [kv for kv in a.set if kv.startswith("nkcloud=")]:
        a.cloud = kv.split("=", 1)[1]
        a.set.remove(kv)

    tool = ROOT / "tools" / "preview"
    exe = tool / "target" / "release" / "preview"
    subprocess.run(["cargo", "build", "--release", "--quiet"], cwd=tool, check=True)
    out = a.out / a.laser
    out.mkdir(parents=True, exist_ok=True)
    views = (a.views or DEFAULT_VIEWS.get(a.laser, "player")).split(",")
    qualities = ["full", "fast"] if a.quality == "both" else [a.quality]
    w, h = a.size.split("x")
    common = [f"laser={LASERS.index(a.laser)}", "clouds=0", f"w={w}", f"h={h}", f"frames={9 if a.bench else 1}", *a.set]
    if a.laser in ("payload", "nuke"):
        # (where the player stood as it fired, in the params the pass reads it from: payload.wgsl's `me`)
        common += ["mode=0", "style=65", "reach=300"]
    shots = []
    for t in a.times:
        for v in views:
            shots += ["--", f"t={t}", *VIEWS[v].split()]
    # (the payload's player: 300 blocks south, or as far as the first view puts them)
    pl_reach = next((kv.split("=", 1)[1] for kv in VIEWS[views[0]].split() + a.set if kv.startswith("reach=")), "300")
    # (and on the first view's land: its hills, if any, in the payload's heightfield)
    env = mod_data(a.laser, out, [kv for kv in VIEWS[views[0]].split() if kv.startswith("hills=")] + a.set, pl_reach) if a.laser in ("crystalbloom", "sinkhole", "payload", "nuke") else None
    env = dict(env or os.environ)
    if a.whole:
        env["PREVIEW_WHOLE"] = "1"
    # each quality's frames, in their own folder; on the sheet a row a moment, a column a view (and a quality)
    frames, labels = {}, {}
    for q in qualities:
        qout = out / q if len(qualities) > 1 else out
        qout.mkdir(parents=True, exist_ok=True)
        shader = build_pass(a.laser, out, q == "fast", a.cloud)
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
