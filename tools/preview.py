#!/usr/bin/env python3
"""Look at a strike without the game: render its post pass offscreen (tools/preview, over a synthetic scene of sky,
rolling ground and a cloud layer) at the moments and from the views asked for, and put them on one labelled contact
sheet. Seconds a sheet, against a rebuild, a restart and a whole strike in the game.

    tools/preview.py downfall 14.5 30 31 45            # those moments, from the default views
    tools/preview.py downfall 28 30 --views far,under  # from those views
    tools/preview.py mothership 12 --bench             # and how long the pass takes on the GPU (median of 9)
    tools/preview.py downfall 30 --set mode=2 colour=1 # any of the preview's keys (see tools/preview/src/main.rs)

The sheet is dist/preview/<laser>.jpg (each frame beside it as NN.png). The scene is not the game's: what the pass
reads from the world (its depth, the clouds, the time of day) is like it, not the same. The look and the timing are the
real pass's, built from the shaders exactly as the mod builds it.
"""
import argparse
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHADERS = ROOT / "mod" / "shaders"
LASERS = ["plasma", "godly", "blackhole", "meteor", "mothership", "downfall", "planetkiller", "crystalbloom"]
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
}
DEFAULT_VIEWS = {"downfall": "player,far,side", "mothership": "player,far", "planetkiller": "player,far,side",
                 "crystalbloom": "cbplayer,cbfar,spire"}


def build_pass(laser: str, out: pathlib.Path) -> pathlib.Path:
    """The pass as the mod builds it (mod/src/lib.rs): strike.wgsl, or for the downfall and the planet killer
    strike.wgsl up to its fs_main less the other lasers' own functions, then downfall.wgsl or planetkiller.wgsl."""
    path = out / "pass.wgsl"
    strike = (SHADERS / "strike.wgsl").read_text()
    if laser in ("downfall", "planetkiller", "crystalbloom"):
        pre = subprocess.run(["sed", "-e", r"/^\/\/ \[lasers pass only\]/,/^\/\/ \[end lasers pass only\]/d", "-e", "/^@fragment/,$d"],
                             input=strike, capture_output=True, text=True, check=True).stdout
        path.write_text(pre + (SHADERS / f"{laser}.wgsl").read_text())
    else:
        path.write_text(strike)
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("laser", choices=LASERS)
    ap.add_argument("times", nargs="+", type=float, help="seconds into the strike")
    ap.add_argument("--views", help=f"comma-separated, of {', '.join(VIEWS)}")
    ap.add_argument("--set", nargs="*", default=[], metavar="KEY=VALUE", help="more of the preview's keys, for every shot")
    ap.add_argument("--size", default="800x450")
    ap.add_argument("--bench", action="store_true", help="time the pass (median of 9 draws a shot)")
    ap.add_argument("--out", type=pathlib.Path, default=ROOT / "dist" / "preview")
    a = ap.parse_args()

    tool = ROOT / "tools" / "preview"
    exe = tool / "target" / "release" / "preview"
    subprocess.run(["cargo", "build", "--release", "--quiet"], cwd=tool, check=True)
    out = a.out / a.laser
    out.mkdir(parents=True, exist_ok=True)
    shader = build_pass(a.laser, out)
    views = (a.views or DEFAULT_VIEWS.get(a.laser, "player")).split(",")
    w, h = a.size.split("x")
    common = [f"laser={LASERS.index(a.laser)}", "clouds=0", f"w={w}", f"h={h}", f"frames={9 if a.bench else 1}", *a.set]
    shots, labels = [], []
    for t in a.times:
        for v in views:
            shots += ["--", f"t={t}", *VIEWS[v].split()]
            labels.append(f"{t:g} s  {v}")
    r = subprocess.run([str(exe), str(shader), str(out), *common, *shots], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr, file=sys.stderr)
        return 1
    if a.bench:
        for line, label in zip([l for l in r.stderr.splitlines() if ": pass " in l], labels):
            print(f"{label:>18}: {line.split(': pass ')[1]}")
    # the sheet: a row a moment, a column a view
    frames = [Image.open(out / f"{i:02}.png").convert("RGB") for i in range(len(labels))]
    fw, fh = frames[0].size
    sheet = Image.new("RGB", (fw * len(views), fh * len(a.times)))
    d = ImageDraw.Draw(sheet)
    for i, (f, label) in enumerate(zip(frames, labels)):
        x, y = fw * (i % len(views)), fh * (i // len(views))
        sheet.paste(f, (x, y))
        d.rectangle([x, y, x + 8 * len(label) + 10, y + 18], fill=(0, 0, 0))
        d.text((x + 5, y + 3), label, fill=(255, 255, 255))
    path = a.out / f"{a.laser}.jpg"
    sheet.save(path, quality=88)
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
