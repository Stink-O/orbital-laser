#!/usr/bin/env python3
"""Build the Orbital Laser mod: the code (mod/, Rust, built for WebAssembly with `cargo horizon-mod build`) plus its
content (the items, their textures and models, and the sounds) into one mod folder Horizon loads:

    dist/orbital/horizon-mod.toml   the manifest (mod/horizon-mod.toml)
    dist/orbital/mod.wasm           the component
    dist/orbital/assets/orbital/    items, models, textures, lang, sounds.json and sounds/
    dist/orbital/data/orbital/      the item declarations

    python3 tools/build_mod.py [--cargo-horizon-mod PATH] [--install HORIZON_HOME]

`cargo horizon-mod` comes from the Horizon fork with the input, ui, render and world mod interfaces
(cargo install --git https://github.com/Stink-O/horizon --branch mod-api-input-ui-render-world cargo-horizon-mod).
"""
import argparse, shutil, subprocess, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "mod"
OUT = ROOT / "dist" / "orbital"

ap = argparse.ArgumentParser()
ap.add_argument("--cargo-horizon-mod", default=shutil.which("cargo-horizon-mod") or str(Path.home() / "horizon-src/target/fast/cargo-horizon-mod"))
ap.add_argument("--install", help="Horizon's game folder: copies the mod into its horizon-mods/ and turns it on")
args = ap.parse_args()

tool = Path(args.cargo_horizon_mod)
if not tool.is_file():
    sys.exit(f"cargo-horizon-mod not found at {tool}: install it (see this file's docstring) or pass --cargo-horizon-mod")
subprocess.run([str(tool), "horizon-mod", "build"], cwd=MOD, check=True)
hmod = MOD / "target" / "horizon-mod" / "orbital.hmod"

if OUT.exists():
    shutil.rmtree(OUT)
(OUT / "assets").mkdir(parents=True)
with zipfile.ZipFile(hmod) as z:
    (OUT / "mod.wasm").write_bytes(z.read("mod.wasm"))
shutil.copy(MOD / "horizon-mod.toml", OUT / "horizon-mod.toml")
shutil.copytree(ROOT / "orbital-laser-mod" / "assets" / "orbital", OUT / "assets" / "orbital")
shutil.copytree(ROOT / "orbital-laser-mod" / "data", OUT / "data")
sounds = ROOT / "orbital-sounds" / "assets" / "orbital"
shutil.copy(sounds / "sounds.json", OUT / "assets" / "orbital" / "sounds.json")
shutil.copytree(sounds / "sounds", OUT / "assets" / "orbital" / "sounds")
size = sum(f.stat().st_size for f in OUT.rglob("*") if f.is_file())
print(f"built {OUT} ({size / 1e6:.1f} MB, mod.wasm {(OUT / 'mod.wasm').stat().st_size / 1e3:.0f} KB)")

if args.install:
    home = Path(args.install).expanduser()
    dest = home / "horizon-mods" / "orbital"
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(OUT, dest)
    old = home / "horizon-mods" / "orbital-laser"          # the content-only mod from 0.2
    if old.exists():
        shutil.rmtree(old)
    lst = home / "horizon-mods.txt"
    lines = [l for l in (lst.read_text().splitlines() if lst.exists() else []) if not l.startswith("mod.orbital:")]
    lst.write_text("\n".join(lines + ["mod.orbital:true"]) + "\n")
    print(f"installed to {dest} and turned on in {lst}")
