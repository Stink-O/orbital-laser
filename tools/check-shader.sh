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
for own in downfall planetkiller crystalbloom sinkhole payload nuke; do
    { cat "$here/wgslcheck/prelude.wgsl"; pre; cat "$shaders/$own.wgsl"; } > "$tmp"
    out=$("$bin" "$tmp" 2>&1) || { echo "the $own pass (strike.wgsl up to its fs_main, then $own.wgsl):"; echo "$out"; exit 1; }
    # the game takes a pass of 256 KiB at most
    size=$(( $(pre | wc -c) + $(wc -c < "$shaders/$own.wgsl") ))
    [ "$size" -le 262144 ] || { echo "the $own pass is $size bytes, over the game's 256 KiB"; exit 1; }
done
# the payload's at QUALITY FULL: without its half-size stage (`[half stage]`), as mod/src/lib.rs's payload_pass builds it
for own in payload nuke; do
    { cat "$here/wgslcheck/prelude.wgsl"; pre; sed -e '/^\/\/ \[half stage\]/,/^\/\/ \[end half stage\]/d' "$shaders/$own.wgsl"; } > "$tmp"
    out=$("$bin" "$tmp" 2>&1) || { echo "the $own pass at QUALITY FULL (without its half-size stage):"; echo "$out"; exit 1; }
done
# the Nuke's earlier clouds (/orbital nukecloud: mod/shaders/nuke_cloud/vN.wgsl spliced into nuke.wgsl by
# tools/nuke_cloud.py, as mod/src/lib.rs's nuke_cloud_pass does), each at QUALITY FULL and FAST
for v in "$shaders"/nuke_cloud/v*.wgsl; do
    n=$(basename "$v" .wgsl); n=${n#v}
    for q in "" --fast; do
        { cat "$here/wgslcheck/prelude.wgsl"; pre; python3 "$here/nuke_cloud.py" splice "$n" $q; } > "$tmp"
        out=$("$bin" "$tmp" 2>&1) || { echo "the nuke pass with cloud v$n ${q:-(full)}:"; echo "$out"; exit 1; }
        size=$(( $(wc -c < "$tmp") - $(wc -c < "$here/wgslcheck/prelude.wgsl") ))
        [ "$size" -le 262144 ] || { echo "the nuke pass with cloud v$n is $size bytes, over the game's 256 KiB"; exit 1; }
    done
done
echo OK
