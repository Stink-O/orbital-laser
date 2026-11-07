#!/usr/bin/env bash
# Validate the mod's post passes the way Horizon will: put the game's mod pass prelude before each, then parse and
# validate the WGSL with naga (the version the game ships).
#
#   tools/check-shader.sh              # checks every pass: mod/shaders/strike.wgsl, and the downfall's, the planet
#                                      # killer's and the crystal bloom's (strike.wgsl up to its fs_main less the other
#                                      # lasers' own functions, then mod/shaders/downfall.wgsl, planetkiller.wgsl or
#                                      # crystalbloom.wgsl, as the mod builds them; the payload's with its
#                                      # half-size stage and without, QUALITY FAST and FULL)
#   tools/check-shader.sh other.wgsl   # another pass
#
# Why it exists: the game only logs that a mod's post pass did not compile. This prints the real error, with its line.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/wgslcheck/target/release/wgslcheck"
[ -x "$bin" ] || (cd "$here/wgslcheck" && cargo build --release --quiet)
tmp="$(mktemp -t orbital-check.XXXXXX)"
trap 'rm -f "$tmp"' EXIT
if [ $# -gt 0 ]; then
    cat "$here/wgslcheck/prelude.wgsl" "$1" > "$tmp"
    "$bin" "$tmp"
    exit
fi
shaders="$here/../mod/shaders"
cat "$here/wgslcheck/prelude.wgsl" "$shaders/strike.wgsl" > "$tmp"
out=$("$bin" "$tmp" 2>&1) || { echo "strike.wgsl:"; echo "$out"; exit 1; }
pre() { sed -e '/^\/\/ \[lasers pass only\]/,/^\/\/ \[end lasers pass only\]/d' -e '/^@fragment/,$d' "$shaders/strike.wgsl"; }
for own in downfall planetkiller crystalbloom sinkhole payload nuke rod supercell hurricane tsunami fold; do
    { cat "$here/wgslcheck/prelude.wgsl"; pre; [ "$own" = fold ] && sed -n '/^\/\/ \[post pass too\]/,/^\/\/ \[end post pass too\]/p' "$shaders/fold_warp.wgsl"; cat "$shaders/$own.wgsl"; } > "$tmp"
    out=$("$bin" "$tmp" 2>&1) || { echo "the $own pass (strike.wgsl up to its fs_main, then $own.wgsl):"; echo "$out"; exit 1; }
    # the game takes a pass of 256 KiB at most
    size=$(( $(pre | wc -c) + $(wc -c < "$shaders/$own.wgsl") ))
    [ "$size" -le 262144 ] || { echo "the $own pass is $size bytes, over the game's 256 KiB"; exit 1; }
done
# the payload's and the nuke's at QUALITY FULL: without its half-size stage (`[half stage]`), as mod/src/lib.rs's payload_pass builds it
for own in payload nuke rod supercell hurricane; do
    { cat "$here/wgslcheck/prelude.wgsl"; pre; sed -e '/^\/\/ \[half stage\]/,/^\/\/ \[end half stage\]/d' "$shaders/$own.wgsl"; } > "$tmp"
    out=$("$bin" "$tmp" 2>&1) || { echo "the $own pass at QUALITY FULL (without its half-size stage):"; echo "$out"; exit 1; }
done
# the Fold's world warp, as it goes into the game's terrain and entity shaders (their Globals' warp, and Warped)
{ printf 'var<private> warp_section: vec3<f32>;\nstruct G { fog_color: vec4<f32>, sky_color: vec4<f32>, sun: vec4<f32>, fog: vec4<f32>, warp: array<vec4<f32>, 6> }\n@group(0) @binding(0) var<uniform> globals: G;\nstruct Warped { pos: vec3<f32>, tint: vec3<f32> }\nstruct Fragment { home: vec3<f32>, at: vec3<f32>, uv: vec2<f32>, layer: u32, color: vec4<f32>, light: vec2<f32>, cut: f32, copy: u32, front: bool }\nstruct Painted { color: vec4<f32>, fog: f32 }\nfn sprite(uv: vec2<f32>, layer: u32) -> vec4<f32> { return vec4<f32>(uv, f32(layer), 1.0); }\n'; cat "$shaders/fold_warp.wgsl"; } > "$tmp"
out=$("$bin" "$tmp" 2>&1) || { echo "the Fold's world warp:"; echo "$out"; exit 1; }
echo OK
