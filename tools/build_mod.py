#!/usr/bin/env python3
"""Build the Orbital Laser mod into one file Horizon loads, dist/orbital.hmod: the manifest
(mod/horizon-mod.toml), the code (mod/, Rust, built for WebAssembly by `cargo horizon-mod build`) and
its content (the items, their textures and models, and the sounds), gathered into mod/assets/ and
mod/data/ first (both are build output).

    python3 tools/build_mod.py [--cargo-horizon-mod PATH] [--install HORIZON_HOME]

`cargo horizon-mod` comes with Horizon
(cargo install --git https://github.com/ludovic111/horizon cargo-horizon-mod).
"""
import argparse, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "mod"
OUT = ROOT / "dist" / "orbital.hmod"

ap = argparse.ArgumentParser()
ap.add_argument("--cargo-horizon-mod", default=shutil.which("cargo-horizon-mod") or str(Path.home() / "horizon-src/target/fast/cargo-horizon-mod"))
ap.add_argument("--install", help="Horizon's game folder: copies the mod into its horizon-mods/ and turns it on")
args = ap.parse_args()

tool = Path(args.cargo_horizon_mod)
if not tool.is_file():
    sys.exit(f"cargo-horizon-mod not found at {tool}: install it (see this file's docstring) or pass --cargo-horizon-mod")
for part in ("assets", "data"):
    if (MOD / part).exists():
        shutil.rmtree(MOD / part)
shutil.copytree(ROOT / "orbital-laser-mod" / "assets", MOD / "assets")
shutil.copytree(ROOT / "orbital-laser-mod" / "data", MOD / "data")
sounds = ROOT / "orbital-sounds" / "assets" / "orbital"
shutil.copy(sounds / "sounds.json", MOD / "assets" / "orbital" / "sounds.json")
shutil.copytree(sounds / "sounds", MOD / "assets" / "orbital" / "sounds")
subprocess.run([str(tool), "horizon-mod", "build"], cwd=MOD, check=True)
OUT.parent.mkdir(parents=True, exist_ok=True)
shutil.copy(MOD / "target" / "horizon-mod" / "orbital.hmod", OUT)
print(f"built {OUT} ({OUT.stat().st_size / 1e6:.1f} MB)")

if args.install:
    home = Path(args.install).expanduser()
    mods = home / "horizon-mods"
    mods.mkdir(parents=True, exist_ok=True)
    for old in (mods / "orbital", mods / "orbital-laser"):   # the folders 0.5 and 0.2 installed
        if old.exists():
            shutil.rmtree(old)
    shutil.copy(OUT, mods / "orbital.hmod")
    lst = home / "horizon-mods.txt"
    lines = [l for l in (lst.read_text().splitlines() if lst.exists() else []) if not l.startswith("mod.orbital:")]
    lst.write_text("\n".join(lines + ["mod.orbital:true"]) + "\n")
    print(f"installed to {mods / 'orbital.hmod'} and turned on in {lst}")
