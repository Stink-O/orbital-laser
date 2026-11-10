#!/bin/bash
# Assemble the native bundle's engine crate: Orbital Laser's mod source (from the repo's REF, default main) built
# unchanged against horizon_sdk.rs, the SDK for a native build.
set -euo pipefail
B=$(dirname "$(readlink -f "$0")")
REPO=${REPO:-$HOME/Downloads/orbital-laser}
REF=${REF:-HEAD}
E=$B/mixins/orbital/engine
rm -rf "$E"; mkdir -p "$E/src"
tmp=$(mktemp -d)
if [ -n "${MODDIR:-}" ]; then
    # (a mod tree as it is on disk, uncommitted work included: for trying the bundle on work in progress)
    mkdir -p "$tmp/mod"; cp -r "$MODDIR/mod/src" "$MODDIR/mod/shaders" "$MODDIR/mod/build.rs" "$tmp/mod/"
else
    git -C "$REPO" archive "$REF" mod/src mod/shaders mod/build.rs | tar -x -C "$tmp"
fi
cp -r "$tmp/mod/src/." "$E/src/"; cp -r "$tmp/mod/shaders" "$E/shaders"
# The mod's build.rs builds the post passes into OUT_DIR; a bundle crate has no build script, so it runs here, into
# engine/gen, and lib.rs and passes.rs name the files relative to themselves.
mkdir -p "$E/gen"
rustc --edition 2024 -O -o "$tmp/build-script" "$tmp/mod/build.rs"
CARGO_MANIFEST_DIR="$tmp/mod" OUT_DIR="$E/gen" "$tmp/build-script" > /dev/null
sed -i -E -e "s|include_str!\(\"$E/gen/|include_str!(\"|g" -e "s|include_str!\(\"$tmp/mod/shaders/|include_str!(\"../shaders/|g" "$E/gen/passes.rs"
sed -i 's|include!(concat!(env!("OUT_DIR"), "/passes.rs"));|include!("../gen/passes.rs");|' "$E/src/lib.rs"
rm -rf "$tmp"
# A .hmod holds only .rs and .toml files under mixins/<id>/, besides a folder's data/ (docs/api/mod-files.md): the
# shaders and the built passes move under engine/data/, and what includes them follows.
mkdir -p "$E/data/gen"; mv "$E/shaders" "$E/data/shaders"; mv "$E"/gen/*.wgsl "$E/data/gen/"
sed -i -E -e 's|include_str!\("\.\./shaders/|include_str!("../data/shaders/|g' -e 's|include_str!\("(pass_[a-z_]+\.wgsl)"|include_str!("../data/gen/\1"|g' "$E/gen/passes.rs"
# (the mod's own shader includes: strike/*.rs two folders up, lib.rs one)
find "$E/src" -name '*.rs' -exec sed -i -E -e 's|include_str!\("\.\./\.\./shaders/|include_str!("../../data/shaders/|g' -e 's|include_str!\("\.\./shaders/|include_str!("../data/shaders/|g' {} +
if grep -rnE 'include_str!\("[^"]*\.wgsl"' "$E/src" "$E/gen" | grep -v '/data/'; then echo "a shader include left outside data/" >&2; exit 1; fi
cp "$B/engine-shim/horizon_sdk.rs" "$E/src/horizon_sdk.rs"
# After lib.rs's leading //! doc comment: the SDK at the crate root, named as the WebAssembly SDK was.
python3 - "$E/src/lib.rs" <<'PY'
import sys
p = sys.argv[1]; lines = open(p).read().split('\n')
i = 0
while i < len(lines) and (lines[i].startswith('//!') or lines[i].strip() == ''):
    i += 1
shim = ['#![allow(unused_mut, dead_code, hidden_glob_reexports)]', 'extern crate self as horizon_mod_sdk;', 'pub mod horizon_sdk;', 'pub use horizon_sdk::*;', '']
src = '\n'.join(lines[:i] + shim + lines[i:])
# Which lasers this build can't play: the SDK's answer (horizon_sdk.rs's `native_build`) in place of the fork's (none).
old = "fn native_unavailable(_key: &str) -> Option<&'static str> {\n    None\n}"
assert src.count(old) == 1, "lib.rs's native_unavailable not found"
src = src.replace(old, "use horizon_sdk::native_build::unavailable as native_unavailable;")
open(p, 'w').write(src)
PY
cat > "$E/Cargo.toml" <<'TOML'
[package]
name = "orbital-laser"
version = "0.5.14"
edition = "2024"
description = "Orbital Laser's engine for the native build: the mod's code, unchanged, on a native Horizon mod SDK."
license = "MIT"

[dependencies]
log = "0.4"
TOML
echo "engine assembled from ${MODDIR:-$REF}"

# The post pass's module (post.rs): the fork's gfx/mod_post.rs with its prelude inline (a support module is one file),
# its last stage drawn into the frame's own target, without its tests; then post_hooks.rs, the renderer's hook points.
python3 - "$B" <<'PY'
import re, sys
b = sys.argv[1]
src = open(f"{b}/engine-shim/mod_post.rs").read()
wgsl = open(f"{b}/engine-shim/mod_post.wgsl").read()
assert '"###' not in wgsl
src = src.replace('include_str!("mod_post.wgsl")', 'r###"' + wgsl + '"###', 1)
src = src[: src.index("#[cfg(test)]\nmod tests {")].rstrip() + "\n"
# run() reads the copy of the world's picture it is given and draws its last stage into `target`
old = "        mut frame: FrameUniform,\n    ) -> &wgpu::TextureView {"
assert old in src
src = src.replace(old, "        mut frame: FrameUniform,\n        target: &wgpu::TextureView,\n    ) -> &wgpu::TextureView {", 1)
for old in ("draw(encoder, &[Some(&output.view)], pipeline, &group);", "draw(encoder, &[Some(&output.view)], join, &join_group);"):
    assert old in src, old
    src = src.replace(old, old.replace("&[Some(&output.view)]", "&[Some(target)]"))
src = src.replace("#[allow(clippy::too_many_arguments)]\n    pub fn run(", "#[allow(clippy::too_many_arguments)]\n    pub fn run(", 1)
hooks = open(f"{b}/engine-shim/post_hooks.rs").read()
# (inner doc comments of the module become plain comments: it is wrapped as a module's items)
src = re.sub(r"(?m)^//!", "//", src)
open(f"{b}/mixins/orbital/post.rs", "w").write(src + "\n" + hooks)
PY
