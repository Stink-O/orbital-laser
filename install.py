#!/usr/bin/env python3
"""Install Orbital Laser into Horizon's game folder.

  python3 install.py              install the mod (horizon-mods/orbital) and switch it on
  python3 install.py --uninstall  remove it (and anything the 0.1 setup installed)
  python3 install.py --legacy     the 0.1 setup instead, for stock Horizon: a shader pack, a sound pack and an item
                                  mod, run by strike.py from outside the game (see "Stock Horizon" in the README)
  --home PATH                     Horizon's game folder (default: $HORIZON_HOME, then the usual place for your OS)

Run it with the game CLOSED: Horizon rewrites its settings when it exits.

The mod is one folder: its code (mod.wasm), the items, their textures and the sounds. It needs the Orbital Laser build
of Horizon (https://github.com/Stink-O/horizon/releases), which ./play.sh starts. In a release download the folder is
`orbital/` beside this script; in a clone of the repository, tools/build_mod.py builds it into dist/orbital first.
"""
import argparse, json, os, shutil, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
# The 0.1 setup: (source folder, folder in the game home, installed name).
LEGACY = (("orbital-laser-shader", "shaderpacks", "orbital-laser-shader"), ("orbital-sounds", "resourcepacks", "orbital-sounds"),
          ("orbital-laser-mod", "horizon-mods", "orbital-laser"))

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--home")
ap.add_argument("--uninstall", action="store_true")
ap.add_argument("--legacy", action="store_true")
ap.add_argument("--link", action="store_true", help="--legacy only: symlink the packs instead of copying (development)")
ap.add_argument("--enable", action="store_true", help="--legacy only: select the shader pack and enable the sound pack")
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


def set_line(path, key, value):
    """Set `key:value` in one of Horizon's `key:value` settings files, adding the line if it isn't there."""
    lines = path.read_text().splitlines() if path.is_file() else []
    out, done = [], False
    for ln in lines:
        if ln.split(":", 1)[0] == key:
            out.append(f"{key}:{value}")
            done = True
        else:
            out.append(ln)
    if not done:
        out.append(f"{key}:{value}")
    path.write_text("\n".join(out) + "\n")


def remove(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)
    else:
        return
    print(f"removed {path}")


def resource_packs(home):
    opt = home / "options.txt"
    if opt.is_file():
        for ln in opt.read_text().splitlines():
            if ln.startswith("resourcePacks:"):
                try:
                    return json.loads(ln.split(":", 1)[1])
                except ValueError:
                    pass
    return ["vanilla"]


def undo_legacy(home):
    """Take out what the 0.1 setup put in: the packs (and their selection) and the content-only item mod."""
    for _, sub, installed in LEGACY:
        remove(home / sub / installed)
    gfx = home / "horizon-graphics.txt"
    if gfx.is_file() and "shaderPack:orbital-laser-shader" in gfx.read_text():
        set_line(gfx, "shaderPack", "")
    packs = resource_packs(home)
    if "file/orbital-sounds" in packs:
        set_line(home / "options.txt", "resourcePacks", json.dumps([p for p in packs if p != "file/orbital-sounds"], separators=(",", ":")))


def mod_folder():
    for cand in (HERE / "orbital", HERE / "dist" / "orbital"):
        if (cand / "mod.wasm").is_file():
            return cand
    if (HERE / "tools" / "build_mod.py").is_file():
        print("building the mod (tools/build_mod.py)...")
        subprocess.run([sys.executable, str(HERE / "tools" / "build_mod.py")], check=True)
        return HERE / "dist" / "orbital"
    sys.exit("No built mod here: download the release zip, or build it with tools/build_mod.py.")


home = find_home()
print(f"Horizon game folder: {home}")

if args.uninstall:
    remove(home / "horizon-mods" / "orbital")
    undo_legacy(home)
    mods = home / "horizon-mods.txt"
    if mods.is_file():
        mods.write_text("".join(l + "\n" for l in mods.read_text().splitlines() if not l.startswith("mod.orbital:")))
    sys.exit(0)

if args.legacy:
    for name, sub, installed in LEGACY:
        dest = home / sub / installed
        remove(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        if args.link:
            dest.symlink_to(HERE / name, target_is_directory=True)
        else:
            shutil.copytree(HERE / name, dest)
        print(f"{'linked' if args.link else 'copied'}  {name}  ->  {dest}")
    if args.enable:
        set_line(home / "horizon-graphics.txt", "shaderPack", "orbital-laser-shader")
        packs = resource_packs(home)
        if "file/orbital-sounds" not in packs:
            packs.append("file/orbital-sounds")
        set_line(home / "options.txt", "resourcePacks", json.dumps(packs, separators=(",", ":")))
        set_line(home / "horizon-mods.txt", "mod.orbital", "true")
        print("enabled: shader pack selected, sound pack and the item mod switched on")
    print("\nNext: horizon-ctl launch --world NAME --creative --wait, then python3 strike.py --doctor and --daemon")
    sys.exit(0)

src = mod_folder()
dest = home / "horizon-mods" / "orbital"
remove(dest)
dest.parent.mkdir(parents=True, exist_ok=True)
shutil.copytree(src, dest)
print(f"copied  {src}  ->  {dest}")
undo_legacy(home)              # the mod draws and sounds by itself: the 0.1 packs would only get in the way
set_line(home / "horizon-mods.txt", "mod.orbital", "true")
print("switched on in horizon-mods.txt")
print("\nNext: ./play.sh            (starts the Orbital Laser build of Horizon on a creative test world)\n"
      "      /orbital give       in the game: the Orbital Laser Designator and the Orbital Remote")
