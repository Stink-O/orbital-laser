#!/usr/bin/env bash
# Validate the mod's post pass the way Horizon will: put the game's mod pass prelude before it, then parse and
# validate the WGSL with naga (the version the game ships).
#
#   tools/check-shader.sh              # checks mod/shaders/strike.wgsl
#   tools/check-shader.sh other.wgsl   # another pass
#
# Why it exists: the game only logs that a mod's post pass did not compile. This prints the real error, with its line.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/wgslcheck/target/release/wgslcheck"
[ -x "$bin" ] || (cd "$here/wgslcheck" && cargo build --release --quiet)
shader="${1:-$here/../mod/shaders/strike.wgsl}"
tmp="$(mktemp -t orbital-check.XXXXXX)"
trap 'rm -f "$tmp"' EXIT
cat "$here/wgslcheck/prelude.wgsl" "$shader" > "$tmp"
"$bin" "$tmp"
