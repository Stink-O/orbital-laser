#!/usr/bin/env python3
"""Install Orbital Laser into Horizon's game home.

  python3 install.py            copy the shader pack and the sound pack into place
  python3 install.py --enable   ...and select/switch them on (needs the game CLOSED: Horizon rewrites its settings on exit)
  python3 install.py --link     symlink the packs instead of copying (handy while developing)
  python3 install.py --uninstall
  --home PATH                   Horizon's game home (default: $HORIZON_HOME, then the usual place for your OS)

It installs three things: the shader pack, the sound pack and the item mod (the Orbital Laser Designator and the Orbital
Remote). Without --enable, pick them in the game: Options > Video Settings > Shader Packs > "orbital-laser-shader",
Options > Resource Packs > enable "orbital-sounds", and Options > Mods > switch on "Orbital Laser". Then run strike.py (strike.py --doctor checks everything).
"""
import argparse, os, shutil, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
# (source folder, folder in the game home, installed name)
PACKS = (("orbital-laser-shader", "shaderpacks", "orbital-laser-shader"), ("orbital-sounds", "resourcepacks", "orbital-sounds"),
         ("orbital-laser-mod", "horizon-mods", "orbital-laser"))

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--home")
ap.add_argument("--link", action="store_true")
ap.add_argument("--uninstall", action="store_true")
ap.add_argument("--enable", action="store_true")
args = ap.parse_args()


def find_home():
    h = Path.home()
    cands = [args.home, os.environ.get("HORIZON_HOME")]
    if sys.platform == "win32":
        cands += [Path(os.environ.get("APPDATA", h / "AppData/Roaming")) / "horizon",
                  Path(os.environ.get("LOCALAPPDATA", h / "AppData/Local")) / "horizon"]
    elif sys.platform == "darwin":
        cands += [h / "Library/Application Support/horizon", h / ".local/share/horizon"]
    else:
        cands += [Path(os.environ.get("XDG_DATA_HOME", h / ".local/share")) / "horizon"]
    for explicit in cands[:2]:                                      # a folder you named always wins
        if explicit and Path(explicit).is_dir():
            return Path(explicit)
    cands = [Path(c) for c in cands if c]
    for c in cands:
        if c.is_dir() and ((c / "options.txt").exists() or (c / "saves").is_dir() or (c / "shaderpacks").is_dir()):
            return c
    for c in cands:
        if c.is_dir():
            return c
    sys.exit("Can't find Horizon's game folder (the one with options.txt and saves/). Tried:\n  "
             + "\n  ".join(map(str, cands)) + "\nRun Horizon once, then pass --home PATH or set HORIZON_HOME.")


home = find_home()

for name, sub, installed in PACKS:
    dest = home / sub / installed
    if dest.is_symlink() or dest.exists():
        shutil.rmtree(dest) if dest.is_dir() and not dest.is_symlink() else dest.unlink()
        print(f"removed {dest}")
    if args.uninstall:
        continue
    dest.parent.mkdir(parents=True, exist_ok=True)
    if args.link:
        dest.symlink_to(HERE / name, target_is_directory=True)
    else:
        shutil.copytree(HERE / name, dest)
    print(f"{'linked' if args.link else 'copied'}  {name}  ->  {dest}")

def set_line(path, key, value):
    """Set `key:value` in one of Horizon's `key:value` settings files, adding the line if it isn't there."""
    lines = path.read_text().splitlines() if path.is_file() else []
    out, done = [], False
    for ln in lines:
        if ln.split(":", 1)[0] == key:
            out.append(f"{key}:{value}"); done = True
        else:
            out.append(ln)
    if not done:
        out.append(f"{key}:{value}")
    path.write_text("\n".join(out) + "\n")


if args.enable and not args.uninstall:
    import json
    set_line(home / "horizon-graphics.txt", "shaderPack", "orbital-laser-shader")
    opt = home / "options.txt"
    packs = ["vanilla"]
    if opt.is_file():
        for ln in opt.read_text().splitlines():
            if ln.startswith("resourcePacks:"):
                try:
                    packs = json.loads(ln.split(":", 1)[1])
                except ValueError:
                    pass
    if "file/orbital-sounds" not in packs:
        packs.append("file/orbital-sounds")
    set_line(opt, "resourcePacks", json.dumps(packs, separators=(",", ":")))
    set_line(home / "horizon-mods.txt", "mod.orbital", "true")
    print("enabled: shader pack selected, sound pack and the item mod switched on (start the game afterwards, not before)")

if not args.uninstall:
    print("\nNext:\n"
          + ("" if args.enable else
             "  1. In the game: Options > Video Settings > Shader Packs > orbital-laser-shader > Apply\n"
             "     and Options > Resource Packs > enable orbital-sounds   (or re-run with --enable while the game is closed)\n")
          + "  2. horizon-ctl launch --world NAME --creative --wait\n"
          "  3. python3 strike.py --doctor     (checks everything)\n"
          "  4. python3 strike.py --daemon     and scope in with the Orbital Laser Designator")
