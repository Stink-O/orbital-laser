#!/usr/bin/env bash
# Validate the shader exactly the way Horizon will: prepend Horizon's stage prelude, parse and validate the WGSL
# with naga (the version the game ships), then substitute the option values (pipeline overrides).
#
#   tools/check-shader.sh                      # checks the shipped shader with sample options
#   tools/check-shader.sh other.wgsl a=1 b=2   # custom file / override values
#
# Why it exists: the game only tells you "Pipeline constant error ... Entry point is invalid" with no detail,
# and one naga bug bites this shader's style of code (see README, "Gotchas"). This tells you the real error.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/wgslcheck/target/release/wgslcheck"
[ -x "$bin" ] || (cd "$here/wgslcheck" && cargo build --release --quiet)
shader="${1:-$here/../orbital-laser-shader/shaders/strike.wgsl}"
[ $# -gt 0 ] && shift
tmp="$(mktemp -t orbital-check.XXXXXX)"
trap 'rm -f "$tmp"' EXIT
cat "$here/wgslcheck/prelude.wgsl" "$shader" > "$tmp"
if [ $# -eq 0 ]; then
  set -- target_x=10.5 target_y=63 target_z=12.5 intensity=1 freeze_time=7 swz=0 seed=3
fi
"$bin" "$tmp" "$@"
