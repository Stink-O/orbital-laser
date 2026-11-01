#!/usr/bin/env python3
"""Snapshot a world and put it back, to strike the same land again and again (a village to re-nuke, say).

    tools/world_snapshot.py save WORLD [NAME] [--replace]   # copy saves/WORLD to a snapshot (NAME default: default)
    tools/world_snapshot.py restore WORLD [NAME]   # put the snapshot back as saves/WORLD
    tools/world_snapshot.py reset WORLD [NAME]     # in the running game: save and quit to the title screen,
                                                   # restore, open the world again
    tools/world_snapshot.py list [WORLD]           # the snapshots kept

WORLD is the world's folder under the game folder's saves/ ($HORIZON_HOME, default ~/.local/share/horizon). The
snapshots are kept in orbital-snapshots/WORLD/NAME beside saves/ (so the game doesn't list them) and are never deleted
by this script (`save` refuses an existing NAME unless given --replace). `restore` replaces saves/WORLD only, and only
once the snapshot is copied in beside it.

`save` and `restore` refuse while the world is open in the game (horizon-ctl state names it; with the game running
and not answering they refuse too). Save the snapshot from the title screen, or with the game closed: the player's
place in it is where they stood when the world was last saved, so leave the world from the vantage point you want
to start each take from.

`reset` needs the game running with horizon-ctl's control socket (./play.sh starts it so). It opens the pause menu,
clicks Save and Quit to Title, waits for the title screen, restores and opens the world again.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

HOME = pathlib.Path(os.environ.get("HORIZON_HOME") or pathlib.Path(os.environ.get("XDG_DATA_HOME", pathlib.Path.home() / ".local/share")) / "horizon")
SAVES = HOME / "saves"
SNAPS = HOME / "orbital-snapshots"


def die(msg: str) -> None:
    print(f"world_snapshot: {msg}", file=sys.stderr)
    sys.exit(1)


def ctl_path() -> str | None:
    for d in [os.environ.get("HORIZON_ORBITAL"), pathlib.Path.home() / "horizon-orbital", pathlib.Path.home() / "horizon-port/target/release", pathlib.Path.home() / "horizon-src/target/release"]:
        if d and (pathlib.Path(d) / "horizon-ctl").is_file():
            return str(pathlib.Path(d) / "horizon-ctl")
    return shutil.which("horizon-ctl")


def ctl(*args: str, timeout: float = 30.0) -> dict | None:
    """One horizon-ctl command's reply, or None when there's no game to answer."""
    exe = ctl_path()
    if not exe:
        return None
    try:
        r = subprocess.run([exe, "--timeout", str(int(timeout)), *args], capture_output=True, text=True, timeout=timeout + 10)
    except subprocess.TimeoutExpired:
        return None
    line = (r.stdout.strip().splitlines() or [""])[-1]
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        return None


def game_running() -> bool:
    return subprocess.run(["pgrep", "-x", "horizon-client"], capture_output=True).returncode == 0


def world_name(world: str) -> str:
    """The name the game shows for a world (level.dat's LevelName), else its folder."""
    w = ctl("worlds")
    for e in (w or {}).get("worlds", []):
        if e.get("folder") == world:
            return e.get("name") or world
    return world


def open_world() -> str | None:
    """The world the game has open (its name), "" on the title screen; refuses when it can't tell."""
    if not game_running():
        return ""
    s = ctl("state")
    if s is None or "error" in s:
        die("the game is running but horizon-ctl can't say which world is open; leave the world (or close the game) and try again")
    return s.get("world") or ""


def refuse_if_open(world: str) -> None:
    w = open_world()
    if w and w in (world, world_name(world)):
        die(f"{world} is open in the game: leave it first (pause, Save and Quit to Title), or use `reset`")


def check_name(s: str, what: str) -> str:
    if not s or s in (".", "..") or "/" in s or "\\" in s or s.startswith("."):
        die(f"bad {what}: {s!r}")
    return s


def save(world: str, name: str, replace: bool = False) -> None:
    src = SAVES / world
    if not (src / "level.dat").is_file():
        die(f"no world {world} in {SAVES}")
    refuse_if_open(world)
    dst = SNAPS / world / name
    if dst.exists() and not replace:
        die(f"there's already a snapshot {name} of {world}: pick another name, or add --replace")
    tmp = SNAPS / world / f".{name}.part"
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, tmp, ignore=shutil.ignore_patterns("session.lock"))
    if dst.exists():
        shutil.rmtree(dst)  # (only an older snapshot of the same name)
    tmp.rename(dst)
    print(f"saved {src} -> {dst}")


def restore(world: str, name: str) -> None:
    snap = SNAPS / world / name
    if not (snap / "level.dat").is_file():
        die(f"no snapshot {name} of {world} in {SNAPS / world} (tools/world_snapshot.py save {world} {name} first)")
    refuse_if_open(world)
    dst = SAVES / world
    if dst.resolve().parent != SAVES.resolve() or dst.name != world:
        die(f"refusing to touch {dst}")
    tmp = SAVES / f".{world}.restoring"
    old = SAVES / f".{world}.replaced"
    for p in (tmp, old):
        if p.exists():
            shutil.rmtree(p)
    # (the snapshot copied in beside the world first; the world swapped for it only once it's whole)
    shutil.copytree(snap, tmp)
    if dst.exists():
        dst.rename(old)
    tmp.rename(dst)
    if old.exists():
        shutil.rmtree(old)  # (the world being restored, and only it)
    print(f"restored {snap} -> {dst}")


def reset(world: str, name: str) -> None:
    if not (SNAPS / world / name / "level.dat").is_file():
        die(f"no snapshot {name} of {world} (save one first)")
    if not game_running():
        die("the game isn't running: use `restore`, then start it (./play.sh WORLD)")
    w = open_world()
    if w:
        if ctl("pause") is None:
            die("horizon-ctl didn't answer")
        clicked = False
        for label in ("Save and Quit to Title", "menu.returnToMenu"):
            r = ctl("click-button", label)
            if r is not None and "error" not in r:
                clicked = True
                break
        if not clicked:
            die("couldn't click Save and Quit to Title on the pause menu; leave the world by hand and run restore")
        r = ctl("wait-for", "screen", "title", "--timeout", "120", timeout=130)
        if r is None or "error" in r:
            die(f"the game didn't reach the title screen: {r}")
        time.sleep(2.0)  # (the world's last chunks written)
    restore(world, name)
    r = ctl("open", world, timeout=120)
    if r is None or "error" in r:
        die(f"couldn't open {world} again: {r}")
    ctl("wait-ready", "--timeout", "120", timeout=130)
    print(f"{world} reset to snapshot {name} and open")


def list_snaps(world: str | None) -> None:
    worlds = [SNAPS / world] if world else sorted(p for p in SNAPS.glob("*") if p.is_dir())
    for w in worlds:
        for s in sorted(p for p in w.glob("*") if p.is_dir() and not p.name.startswith(".")):
            print(f"{w.name} {s.name}  ({time.strftime('%Y-%m-%d %H:%M', time.localtime((s / 'level.dat').stat().st_mtime))})")


def main() -> None:
    a = [x for x in sys.argv[1:] if x != "--replace"]
    replace = "--replace" in sys.argv[1:]
    if not a or a[0] in ("-h", "--help", "help"):
        print(__doc__)
        return
    cmd = a[0]
    if cmd == "list":
        list_snaps(check_name(a[1], "world") if len(a) > 1 else None)
        return
    if cmd not in ("save", "restore", "reset") or len(a) < 2:
        die("usage: world_snapshot.py save|restore|reset WORLD [NAME] | list [WORLD]")
    world = check_name(a[1], "world")
    name = check_name(a[2], "snapshot name") if len(a) > 2 else "default"
    if cmd == "save":
        save(world, name, replace)
    else:
        {"restore": restore, "reset": reset}[cmd](world, name)


if __name__ == "__main__":
    main()
