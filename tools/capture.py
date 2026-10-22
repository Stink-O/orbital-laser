#!/usr/bin/env python3
"""Grab a correct-colour screenshot of one moment of the strike (for docs and shader debugging).

    python3 tools/capture.py SECONDS out.png [--ctl PATH] [--home PATH]

Why this exists: `horizon-ctl screenshot` writes the 10-bit surface as 8-bit PNG and overwrites the top byte, which
destroys most of the blue channel. So the shader has two debug options: `freeze_time` pins the strike clock at
SECONDS, and `swz` makes it alternate frame by frame between the normal picture and a frame that carries the blue
channel in the red channel. This script grabs consecutive frames until it has one of each, and merges them.
Aim the camera first (spectator mode keeps it still), and stop strike.py --daemon so it doesn't fight over pack.toml.
"""
import argparse, os, re, shutil, subprocess, sys, tempfile, time
from pathlib import Path
import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("seconds", type=float)
ap.add_argument("out")
ap.add_argument("--ctl")
ap.add_argument("--home")
args = ap.parse_args()
ctl = args.ctl or os.environ.get("HORIZON_CTL") or shutil.which("horizon-ctl")
if not ctl:
    sys.exit("Can't find horizon-ctl (use --ctl or HORIZON_CTL).")
home = Path(args.home or os.environ.get("HORIZON_HOME") or
            {"win32": Path(os.environ.get("APPDATA", Path.home())) / "horizon",
             "darwin": Path.home() / "Library/Application Support/horizon"}.get(
                sys.platform, Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "horizon"))
pack = home / "shaderpacks" / "orbital-laser-shader" / "pack.toml"
tmp = Path(tempfile.mkdtemp()) / "grab.png"


def setopt(**kw):
    s = pack.read_text()
    for k, v in kw.items():
        s = re.sub(rf"(\[options\.{k}\][^\[]*?default = )[-0-9.eE+]+", rf"\g<1>{float(v):.2f}", s, flags=re.S)
    pack.write_text(s)


def grab():
    subprocess.run([ctl, "screenshot", str(tmp)], check=True, capture_output=True)
    a = np.asarray(Image.open(tmp).convert("RGBA"), dtype=np.uint32)
    w = a[..., 0] | (a[..., 1] << 8) | (a[..., 2] << 16)
    return (w & 1023) >> 2, ((w >> 10) & 1023) >> 2          # the surface's 10-bit red and green, as 8-bit


setopt(freeze_time=args.seconds, swz=1.0)
time.sleep(2.5)                                             # let the pack reload
frames = []
try:
    for _ in range(12):
        r, g = grab()
        blue_only = float(np.mean(np.abs(r.astype(int) - g.astype(int)))) < 1.0
        frames.append((blue_only, r, g))
        if len(frames) >= 2 and frames[-1][0] != frames[-2][0]:
            colour = frames[-1] if not frames[-1][0] else frames[-2]
            blue = frames[-1] if frames[-1][0] else frames[-2]
            Image.fromarray(np.dstack([colour[1], colour[2], blue[1]]).astype(np.uint8)).save(args.out)
            print("saved", args.out)
            break
    else:
        sys.exit("Couldn't catch both frame types; try again.")
finally:
    setopt(freeze_time=100.0, swz=0.0)
