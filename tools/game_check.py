#!/usr/bin/env python3
"""Catch the mod being stopped in the game (out of fuel, a panic, a failed start) around an in-game test.

    tools/game_check.py mark                 # before a strike: remember how far the game's log goes
    tools/game_check.py watch [SECONDS]      # during it: poll the new lines (default 100 s, the longest strike)
    tools/game_check.py check                # after it: one look at the new lines

`watch` and `check` exit 1 with the line found when the new lines say `mod orbital stopped`, `did not start`,
`panicked`, or name `orbital` at WARN or ERROR level; 0 when they are clean. A run they fail is a failed run: its
results are not good, whatever it looked like. The log is the control socket's (/run/user/$UID/horizon-control.log),
else the game folder's logs/latest.log ($HORIZON_HOME, default ~/.local/share/horizon).
"""
import os
import pathlib
import re
import sys
import time

MARK = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "orbital-game-check.mark"
BAD = re.compile(r"mod orbital stopped|did not start|panicked|(WARN|ERROR)\].*orbital", re.IGNORECASE)


def log_path() -> pathlib.Path:
    ctl = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "horizon-control.log"
    if ctl.exists():
        return ctl
    home = pathlib.Path(os.environ.get("HORIZON_HOME", pathlib.Path.home() / ".local/share/horizon"))
    return home / "logs" / "latest.log"


def size(p: pathlib.Path) -> int:
    try:
        return p.stat().st_size
    except FileNotFoundError:
        return 0


def mark() -> None:
    p = log_path()
    MARK.write_text(f"{p}\n{size(p)}\n")
    print(f"marked {p} at {size(p)} bytes")


def new_lines() -> list[str]:
    try:
        path, start = MARK.read_text().split("\n")[:2]
        p, start = pathlib.Path(path), int(start)
    except (FileNotFoundError, ValueError):
        sys.exit("no mark: run `tools/game_check.py mark` before the test")
    if size(p) < start:
        start = 0  # (the log was started afresh: a new game)
    with open(p, "rb") as f:
        f.seek(start)
        return f.read().decode("utf-8", "replace").splitlines()


def bad() -> str | None:
    return next((line for line in new_lines() if BAD.search(line)), None)


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "mark":
        mark()
        return
    if cmd == "watch":
        end = time.time() + (float(sys.argv[2]) if len(sys.argv) > 2 else 100.0)
        while time.time() < end:
            if line := bad():
                print(f"FAILED: {line}")
                sys.exit(1)
            time.sleep(0.5)
    if line := bad():
        print(f"FAILED: {line}")
        sys.exit(1)
    print("clean: the mod ran throughout")


if __name__ == "__main__":
    main()
