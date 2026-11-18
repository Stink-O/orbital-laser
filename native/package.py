#!/usr/bin/env python3
"""Package Orbital Laser's native release as one file, `orbital-laser-native-vX.Y.Z.hnmod`: the native code (horizon-native.json,
mixins/orbital/) and the content (horizon-mod.toml, assets/, data/) under the one mod id `orbital`
(docs/api/mod-files.md, "Both, in one .hmod").

The launcher installs it as `horizon-native-mods/orbital.hnmod` and builds its code into the game; the bundle's
`content_find` injection has the game read the content from that same file (until the game reads content from native
files itself: horizon-rust/horizon#5865).

package.py CONTENT_DIR OUT_DIR
CONTENT_DIR is the content mod (content.sh's output); the bundle is mixins/orbital as assemble.sh left it.
"""
import concurrent.futures
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import zipfile

B = pathlib.Path(__file__).resolve().parent
ID = "orbital"
BUNDLE = B / "mixins" / ID
# The horizon-mixins commit the launcher builds with (launcher/src/native_mods.rs MIXINS_REV).
MIXINS = "5a64af938ec86b00d53d16a408aabc0038fb3e57"
# The newest hook points the bundle calls, or None: it uses the block-sprite helpers (#7319), not stamped with an API
# number yet, so it names none and the launcher builds it on its pinned revision.
HOOKS = None
GAME = "26.3"
# docs/api/mod-files.md: the native entries at most 512 and 64 MiB unpacked; the whole file at most 64 MiB (the
# registry's limit).
NATIVE_LIMIT = (512, 64 << 20)
FILE_LIMIT = 64 << 20


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
            sys.exit(f"{rel}: a native file holds only .rs, .toml and data/ files under mixins/{ID}/")
        out.append((f"mixins/{ID}/{rel.as_posix()}", p))
    return out


def content_files(content):
    files = [("horizon-mod.toml", content / "horizon-mod.toml")]
    for top in ("assets", "data"):
        for p in sorted((content / top).rglob("*")):
            if p.is_file():
                rel = p.relative_to(content).as_posix()
                if not re.fullmatch(r"(assets|data)(/[a-z0-9_.-]+){2,}", rel):
                    sys.exit(f"{rel}: not a content path")
                files.append((rel, p))
    return files


def channels(p):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels",
                          "-of", "csv=p=0", str(p)], capture_output=True, text=True, check=True).stdout
    return int(out.strip() or 1)


def as_mono(files, tmp):
    """Stereo sounds as the mono the fork plays them as. The fork sums every sound file to mono and places it in the
    world; upstream Horizon plays a stereo file direct, as OpenAL does (no distance, no direction), so on the native
    build a stereo file would sound unlike the fork. The same sum here (the channels' mean) makes it sound as it does
    there, and keeps the file under the registry's limit. Needs ffmpeg and ffprobe."""
    def one(item):
        name, p = item
        if p.suffix != ".ogg" or channels(p) == 1:
            return name, p
        out = pathlib.Path(tmp) / name
        out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(p), "-af", "pan=mono|c0=0.5*c0+0.5*c1",
                        "-c:a", "libvorbis", "-q:a", "6", "-fflags", "+bitexact", "-map_metadata", "-1", str(out)],
                       check=True)
        return name, out
    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 4) as pool:
        return list(pool.map(one, files))


def main():
    content, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    toml = (BUNDLE / "horizon-mixin.toml").read_text()
    nid = re.search(r'(?m)^id = "([^"]+)"', toml).group(1)
    version = re.search(r'(?m)^version = "([^"]+)"', toml).group(1)
    horizon = re.search(r'(?m)^horizon_revision = "([0-9a-f]{40})"', toml).group(1)
    mod_toml = (content / "horizon-mod.toml").read_text()
    cid = re.search(r'(?m)^id = "([^"]+)"', mod_toml).group(1)
    cver = re.search(r'(?m)^version = "([^"]+)"', mod_toml).group(1)
    if (nid, cid, cver) != (ID, ID, version):
        sys.exit(f"the bundle is {nid} {version}, the content {cid} {cver}: want {ID} for both, one version")
    manifest = {"schema": 1, "id": ID, "version": version, "game": GAME, "horizon": horizon, "mixins": MIXINS}
    if HOOKS is not None:
        manifest["hooks"] = HOOKS
    native = bundle_files()
    size = sum(p.stat().st_size for _, p in native)
    if len(native) + 1 > NATIVE_LIMIT[0] or size > NATIVE_LIMIT[1]:
        sys.exit(f"native files over the limit: {len(native) + 1} entries, {size} bytes")
    tmp = tempfile.TemporaryDirectory()
    files = as_mono(content_files(content), tmp.name)
    out_dir.mkdir(parents=True, exist_ok=True)
    # (the download says what it is; the launcher installs it as `horizon-native-mods/orbital.hnmod` by its id, and
    # content_find.rs finds one installed by hand under this name too)
    out = out_dir / f"orbital-laser-native-v{version}.hnmod"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("horizon-native.json", json.dumps(manifest, indent=2) + "\n")
        for name, p in native + files:
            z.write(p, name)
    if out.stat().st_size > FILE_LIMIT:
        sys.exit(f"{out}: {out.stat().st_size} bytes, over the registry's 64 MiB")
    print(f"{out}: {len(native) + 1} native entries, {len(files)} content entries, {out.stat().st_size >> 20} MiB; "
          f"{json.dumps(manifest)}")


if __name__ == "__main__":
    main()
