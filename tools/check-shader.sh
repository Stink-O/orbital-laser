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
# (the fork's prelude; then the whole check again on the native build's, whose depth is a plain texture: a pass that
# loads depth with textureLoad compiles on the fork and not natively)
prelude="${PRELUDE:-$here/wgslcheck/prelude.wgsl}"
tmp="$(mktemp -t orbital-check.XXXXXX)"
trap 'rm -f "$tmp"' EXIT
if [ $# -gt 0 ]; then
    cat "$prelude" "$1" > "$tmp"
    "$bin" "$tmp"
    exit
fi
shaders="$here/../mod/shaders"
cat "$prelude" "$shaders/strike.wgsl" > "$tmp"
out=$("$bin" "$tmp" 2>&1) || { echo "strike.wgsl:"; echo "$out"; exit 1; }
# (strike.wgsl up to its fs_main less the lasers' pass's own, and the Mothership's ship unless the laser's says it uses it)
pre() {
    local ship='/^\/\/ \[mothership\]/,/^\/\/ \[end mothership\]/d'
    grep -q '^// \[uses the mothership\]' "$shaders/$1.wgsl" && ship='/^\/\/ \[never\]/d'
    sed -e '/^\/\/ \[lasers pass only\]/,/^\/\/ \[end lasers pass only\]/d' -e "$ship" -e '/^@fragment/,$d' "$shaders/strike.wgsl"
}
# (a laser's own file, with the Supervolcano's mount after its, and the Fold's with its warp's shared part before)
body() {
    [ "$1" != fold ] || sed -n '/^\/\/ \[post pass too\]/,/^\/\/ \[end post pass too\]/p' "$shaders/fold_warp.wgsl"
    # (the World Eater's pass is its path, its body and its own, in that order: mod/build.rs)
    [ "$1" != worldeater ] || cat "$shaders/worldeater_path.wgsl" "$shaders/worldeater_body.wgsl"
    # (the Earthquake's is its plates, shared with its world warp, then its own: mod/build.rs)
    [ "$1" != earthquake ] || cat "$shaders/earthquake_plates.wgsl"
    if [ "$1" = earthquake ]; then
        # (the Earthquake's own file up to [eq stages], its dust, then its stages: mod/build.rs)
        sed -e '/^\/\/ ==== \[eq stages\]/,$d' "$shaders/earthquake.wgsl"
        cat "$shaders/earthquake_dust.wgsl"
        sed -n -e '/^\/\/ ==== \[eq stages\]/,$p' "$shaders/earthquake.wgsl"
    elif [ "$1" = convergence ]; then
        # (the Convergence's: its own file up to [cv stages], its sky side, its ground side, its cracks, then its stages: mod/build.rs)
        sed -e '/^\/\/ ==== \[cv stages\]/,$d' "$shaders/convergence.wgsl"
        cat "$shaders/convergence_sky.wgsl" "$shaders/convergence_ground.wgsl" "$shaders/convergence_cracks.wgsl"
        sed -n -e '/^\/\/ ==== \[cv stages\]/,$p' "$shaders/convergence.wgsl"
    else
        cat "$shaders/$1.wgsl"
    fi
    [ "$1" != volcano ] || cat "$shaders/volcano_mount.wgsl"
}
for own in downfall planetkiller crystalbloom sinkhole payload nuke rod supercell hurricane tsunami fold volcano skybreak carpetbomb worldeater convergence earthquake sixstars colossi; do
    { cat "$prelude"; pre "$own"; body "$own"; } > "$tmp"
    out=$("$bin" "$tmp" 2>&1) || { echo "the $own pass (strike.wgsl up to its fs_main, then $own.wgsl):"; echo "$out"; exit 1; }
    # the game takes a pass of 256 KiB at most
    # (a pass whose own source says `// [lean pass]` goes in without its comment and blank lines: mod/src/passbuild.rs)
    if body "$own" | grep -q '^// \[lean pass\]'; then
        size=$( { pre "$own"; body "$own"; } | grep -v -e '^[[:space:]]*//' -e '^[[:space:]]*$' | wc -c)
    else
        size=$(( $(pre "$own" | wc -c) + $(body "$own" | wc -c) ))
    fi
    [ "$size" -le 262144 ] || { echo "the $own pass is $size bytes, over the game's 256 KiB"; exit 1; }
done
# the payload's and the nuke's at QUALITY FULL: without its half-size stage (`[half stage]`), as mod/src/lib.rs's payload_pass builds it
for own in payload nuke rod supercell hurricane volcano skybreak carpetbomb worldeater convergence earthquake sixstars colossi; do
    { cat "$prelude"; pre "$own"; body "$own" | sed -e '/^\/\/ \[half stage\]/,/^\/\/ \[end half stage\]/d'; } > "$tmp"
    out=$("$bin" "$tmp" 2>&1) || { echo "the $own pass at QUALITY FULL (without its half-size stage):"; echo "$out"; exit 1; }
done
# the Fold's world warp, as it goes into the game's terrain and entity shaders (their Globals' warp, and Warped)
{ printf 'var<private> warp_section: vec3<f32>;\nstruct G { fog_color: vec4<f32>, sky_color: vec4<f32>, sun: vec4<f32>, fog: vec4<f32>, warp: array<vec4<f32>, 6> }\n@group(0) @binding(0) var<uniform> globals: G;\nstruct Warped { pos: vec3<f32>, tint: vec3<f32> }\nstruct Fragment { home: vec3<f32>, at: vec3<f32>, uv: vec2<f32>, layer: u32, color: vec4<f32>, light: vec2<f32>, cut: f32, copy: u32, front: bool }\nstruct Painted { color: vec4<f32>, fog: f32 }\nfn sprite(uv: vec2<f32>, layer: u32) -> vec4<f32> { return vec4<f32>(uv, f32(layer), 1.0); }\n'; cat "$shaders/fold_warp.wgsl"; } > "$tmp"
out=$("$bin" "$tmp" 2>&1) || { echo "the Fold's world warp:"; echo "$out"; exit 1; }
# the World Eater's world warp: what of its path is marked [warp too], then worldeater_warp.wgsl
{ printf 'var<private> warp_section: vec3<f32>;\nstruct G { fog_color: vec4<f32>, sky_color: vec4<f32>, sun: vec4<f32>, fog: vec4<f32>, warp: array<vec4<f32>, 6> }\n@group(0) @binding(0) var<uniform> globals: G;\nstruct Warped { pos: vec3<f32>, tint: vec3<f32> }\nstruct Fragment { home: vec3<f32>, at: vec3<f32>, uv: vec2<f32>, layer: u32, color: vec4<f32>, light: vec2<f32>, cut: f32, copy: u32, front: bool }\nstruct Painted { color: vec4<f32>, fog: f32 }\nfn sprite(uv: vec2<f32>, layer: u32) -> vec4<f32> { return vec4<f32>(uv, f32(layer), 1.0); }\n'; sed -n '/^\/\/ \[warp too\]/,/^\/\/ \[end warp too\]/p' "$shaders/worldeater_path.wgsl"; cat "$shaders/worldeater_warp.wgsl"; } > "$tmp"
out=$("$bin" "$tmp" 2>&1) || { echo "the World Eater's world warp:"; echo "$out"; exit 1; }
# the Earthquake's world warp: its plates, then earthquake_warp.wgsl (it reads the projection and the warp's data too)
{ printf 'var<private> warp_section: vec3<f32>;\nstruct G { view_proj: mat4x4<f32>, fog_color: vec4<f32>, sky_color: vec4<f32>, sun: vec4<f32>, fog: vec4<f32>, warp: array<vec4<f32>, 6>, warp_data: array<vec4<f32>, 64> }\n@group(0) @binding(0) var<uniform> globals: G;\nstruct Warped { pos: vec3<f32>, tint: vec3<f32> }\nstruct Fragment { home: vec3<f32>, at: vec3<f32>, uv: vec2<f32>, layer: u32, color: vec4<f32>, light: vec2<f32>, cut: f32, copy: u32, front: bool }\nstruct Painted { color: vec4<f32>, fog: f32 }\nfn sprite(uv: vec2<f32>, layer: u32) -> vec4<f32> { return vec4<f32>(uv, f32(layer), 1.0); }\nfn sample_lightmap(sky: f32, block: f32) -> vec4<f32> { return vec4<f32>(sky, block, 1.0, 1.0); }\n'; cat "$shaders/earthquake_plates.wgsl" "$shaders/earthquake_warp.wgsl"; } > "$tmp"
out=$("$bin" "$tmp" 2>&1) || { echo "the Earthquake's world warp:"; echo "$out"; exit 1; }
# (what is before its `// [fragments]` goes into the entities' shader too, which has no light map)
sed -e '/^fn sample_lightmap/d' -e '/^\/\/ \[fragments\]/,$d' "$tmp" > "$tmp.v" && mv "$tmp.v" "$tmp"
out=$("$bin" "$tmp" 2>&1) || { echo "the Earthquake's world warp, the part the entities' shader takes:"; echo "$out"; exit 1; }
# (and, given the fork's source in HORIZON_FORK_SRC (its crates/horizon-client/src), every warp put into the game's own
# terrain shader as gfx/warp.rs puts it: its world_warp in place of the default, the pixels' inputs, warp_fragment.wgsl)
if [ -n "${HORIZON_FORK_SRC:-}" ] && [ -f "$HORIZON_FORK_SRC/terrain.wgsl" ]; then
    for w in fold earthquake worldeater; do
        case $w in
            fold) src=$(cat "$shaders/fold_warp.wgsl") ;;
            earthquake) src=$(cat "$shaders/earthquake_plates.wgsl" "$shaders/earthquake_warp.wgsl") ;;
            worldeater) src=$(sed -n '/^\/\/ \[warp too\]/,/^\/\/ \[end warp too\]/p' "$shaders/worldeater_path.wgsl"; cat "$shaders/worldeater_warp.wgsl") ;;
        esac
        WARP_SRC="$src" python3 - "$HORIZON_FORK_SRC" > "$tmp" <<'PY' || { echo "the $w warp: could not put it into terrain.wgsl"; exit 1; }
import os, sys
root = sys.argv[1]
shader = open(os.path.join(root, "terrain.wgsl")).read()
src = os.environ["WARP_SRC"]
a = shader.index("fn world_warp(pos: vec3<f32>, copy: u32)")
b = shader.index("// [end world warp]", a)
shader = shader[:a] + src + "\n" + shader[b:]
def fill(s, name, w):
    a = s.index(f"// [{name}]"); e = f"// [end {name}]"; b = s.index(e, a)
    return s[:a] + w + s[b + len(e):]
shader = fill(shader, "warp varyings", "@location(5) home: vec3<f32>,\n    @location(6) at: vec3<f32>,\n    @location(7) warp_light: vec2<f32>,\n    @location(8) cut: f32,\n    @location(9) @interpolate(flat) copy: u32,\n")
shader = fill(shader, "warp vertex", "out.home = position + origin;\n    out.at = pos;\n    out.warp_light = vec2(f32(light.x), f32(light.y)) / 16.0;\n    out.cut = select(0.0, 1.0, warped.tint.r < 0.0);\n    out.copy = copy;\n")
default = ("fn world_fragment(f: Fragment) -> Painted {\n    if f.cut > 0.0 || (f.light.x < 0.5 && f.light.y < 0.5) { return Painted(vec4(0.0, 0.0, 0.0, -1.0), 1.0); }\n"
           "    return Painted(sprite(f.uv, f.layer) * f.color, 1.0);\n}\n")
frag = "" if "fn world_fragment" in src else default
print(shader + "\n" + open(os.path.join(root, "gfx", "warp_fragment.wgsl")).read() + "\n" + frag)
PY
        out=$("$bin" "$tmp" 2>&1) || { echo "the $w warp in the game's terrain shader:"; echo "$out"; exit 1; }
    done
fi
if [ -z "${PRELUDE:-}" ] && [ -f "$here/../native/engine-shim/mod_post.wgsl" ]; then
    PRELUDE="$here/../native/engine-shim/mod_post.wgsl" "$0" > /dev/null || { echo "on the native build's prelude:"; PRELUDE="$here/../native/engine-shim/mod_post.wgsl" "$0"; exit 1; }
fi
echo OK
