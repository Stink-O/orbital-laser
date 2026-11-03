#!/usr/bin/env python3
"""Package Orbital Laser's native release as two files, as Horizon's registry lists them and launchers install them:

- `orbital_laser.hnmod`: the native code (horizon-native.json, mixins/orbital_laser/), mod id `orbital_laser`, which
  the launcher builds into the game from `horizon-native-mods/`;
- `orbital-VERSION.hmod`: the content (horizon-mod.toml, assets/, data/), mod id `orbital`, which the game loads from
  `horizon-mods/`.

They have different ids because the registry lists one project per id, and the content's items are declared under its
own id (`data/orbital/horizon/item/`: `orbital:laser_designator`). The code still runs as `orbital` in the game (the
glue's `ID`: its switch, its storage, its channels).

package.py CONTENT_DIR OUT_DIR
CONTENT_DIR is the content mod (content.sh's output); the bundle is mixins/orbital_laser as assemble.sh left it.
"""
import json
import pathlib
import re
import sys
import zipfile

B = pathlib.Path(__file__).resolve().parent
NATIVE_ID = "orbital_laser"
CONTENT_ID = "orbital"
BUNDLE = B / "mixins" / NATIVE_ID
# The horizon-mixins commit the launcher builds with (launcher/src/native_mods.rs MIXINS_REV).
MIXINS = "a2af5c0dd4117d51ecd70066ba7a00b4a2c10dab"
# The newest hook points the bundle calls, or None: it uses the block-sprite helpers (#7319), not stamped with an API
# number yet, so it names none and the launcher builds it on its pinned revision.
HOOKS = None
GAME = "26.3"
NATIVE_LIMIT = (512, 64 << 20)


def bundle_files():
    """The bundle's files a native file may hold: .rs and .toml anywhere, and what is under a folder's data/."""
    out = []
    for p in sorted(BUNDLE.rglob("*")):
        if not p.is_file() or p.is_symlink():
            continue
        rel = p.relative_to(BUNDLE)
        parts = rel.parts
        ok = p.suffix in (".rs", ".toml") or parts[0] == "data" or (len(parts) > 2 and parts[1] == "data")
        if not ok:
            sys.exit(f"{rel}: a native file holds only .rs, .toml and data/ files under mixins/{NATIVE_ID}/")
        out.append((f"mixins/{NATIVE_ID}/{rel.as_posix()}", p))
    return out


def main():
    content, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    toml = (BUNDLE / "horizon-mixin.toml").read_text()
    nid = re.search(r'(?m)^id = "([^"]+)"', toml).group(1)
    version = re.search(r'(?m)^version = "([^"]+)"', toml).group(1)
    horizon = re.search(r'(?m)^horizon_revision = "([0-9a-f]{40})"', toml).group(1)
    mod_toml = (content / "horizon-mod.toml").read_text()
    cid = re.search(r'(?m)^id = "([^"]+)"', mod_toml).group(1)
    cver = re.search(r'(?m)^version = "([^"]+)"', mod_toml).group(1)
    if (nid, cid, cver) != (NATIVE_ID, CONTENT_ID, version):
        sys.exit(f"the bundle is {nid} {version}, the content {cid} {cver}: want {NATIVE_ID} and {CONTENT_ID}, one version")
    manifest = {"schema": 1, "id": NATIVE_ID, "version": version, "game": GAME, "horizon": horizon, "mixins": MIXINS}
    if HOOKS is not None:
        manifest["hooks"] = HOOKS
    native = bundle_files()
    size = sum(p.stat().st_size for _, p in native)
    if len(native) + 1 > NATIVE_LIMIT[0] or size > NATIVE_LIMIT[1]:
        sys.exit(f"native files over the limit: {len(native) + 1} entries, {size} bytes")
    out_dir.mkdir(parents=True, exist_ok=True)
    hn = out_dir / f"{NATIVE_ID}.hnmod"
    with zipfile.ZipFile(hn, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("horizon-native.json", json.dumps(manifest, indent=2) + "\n")
        for name, p in native:
            z.write(p, name)
    print(f"{hn}: the native code, {len(native) + 1} entries, {hn.stat().st_size >> 10} KiB; {json.dumps(manifest)}")
    hm = out_dir / f"{CONTENT_ID}-{version}.hmod"
    files = [("horizon-mod.toml", content / "horizon-mod.toml")]
    for top in ("assets", "data"):
        for p in sorted((content / top).rglob("*")):
            if p.is_file():
                rel = p.relative_to(content).as_posix()
                if not re.fullmatch(r"(assets|data)(/[a-z0-9_.-]+){2,}", rel):
                    sys.exit(f"{rel}: not a content path")
                files.append((rel, p))
    with zipfile.ZipFile(hm, "w", zipfile.ZIP_DEFLATED) as z:
        for name, p in files:
            z.write(p, name)
    print(f"{hm}: the content, {len(files)} entries, {hm.stat().st_size >> 20} MiB")


if __name__ == "__main__":
    main()
