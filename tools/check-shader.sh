#!/usr/bin/env bash
# Validate the mod's post passes the way Horizon will: put the game's mod pass prelude before each, then parse and
# validate the WGSL with naga (the version the game ships).
#
#   tools/check-shader.sh              # checks both passes: mod/shaders/strike.wgsl, and the downfall's (strike.wgsl up
#                                      # to its fs_main, then mod/shaders/downfall.wgsl, as the mod builds it)
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
{ cat "$here/wgslcheck/prelude.wgsl"; sed '/^@fragment/,$d' "$shaders/strike.wgsl"; cat "$shaders/downfall.wgsl"; } > "$tmp"
out=$("$bin" "$tmp" 2>&1) || { echo "the downfall's pass (strike.wgsl up to its fs_main, then downfall.wgsl):"; echo "$out"; exit 1; }
# the game takes a pass of 256 KiB at most
size=$(( $(sed '/^@fragment/,$d' "$shaders/strike.wgsl" | wc -c) + $(wc -c < "$shaders/downfall.wgsl") ))
[ "$size" -le 262144 ] || { echo "the downfall's pass is $size bytes, over the game's 256 KiB"; exit 1; }
echo OK
