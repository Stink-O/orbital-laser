#!/usr/bin/env bash
# Start Horizon's custom build (the fork with the input, ui, render and world mod interfaces) on your own game
# folder, so it sees your worlds, settings and horizon-mods/ (Orbital Laser included).
#
#   tools/play.sh [WORLD]            default world: modtest
#
# HORIZON_SRC (default ~/horizon-src) is the fork's checkout; HORIZON_HOME (default ~/.local/share/horizon) the game
# folder; HORIZON_RESOURCES the prepared resources (default: the ones beside your installed Horizon).
set -euo pipefail
src="${HORIZON_SRC:-$HOME/horizon-src}"
home="${HORIZON_HOME:-$HOME/.local/share/horizon}"
res="${HORIZON_RESOURCES:-$HOME/Downloads/horizon-linux-x86_64/.local/horizon-client/26.3}"
for p in "$src/target/fast/horizon-client" "$src/target/fast/horizon-ctl"; do
  [ -x "$p" ] || { echo "missing $p: cd $src && cargo build --profile fast -p horizon-client" >&2; exit 1; }
done
cd "$home"   # the game keeps saves, options and mods in the folder it starts in
exec "$src/target/fast/horizon-ctl" launch --world "${1:-modtest}" --creative --wait \
  --game "$src/target/fast/horizon-client" --resources "$res"
