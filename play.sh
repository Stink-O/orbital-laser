#!/usr/bin/env bash
# Start the Horizon build that runs Orbital Laser (Horizon with the input, ui, render and world mod interfaces:
# https://github.com/Stink-O/horizon/releases) on your own game folder, so it sees your worlds, settings and mods.
#
#   ./play.sh [WORLD]          default world: OrbitalTest (made if it doesn't exist; creative, cheats on)
#
# Where things are (each can be set in the environment):
#   HORIZON_ORBITAL    the folder with that build's horizon-client and horizon-ctl
#                      default: ~/horizon-orbital, else a source build in ~/horizon-src/target/{release,fast}
#   HORIZON_RESOURCES  prepared resources (horizon-prepare makes them)
#                      default: $HORIZON_ORBITAL/.local/horizon-client/26.3, else the ones beside your installed Horizon
#   HORIZON_HOME       your game folder (options.txt, saves/, horizon-mods/); default ~/.local/share/horizon
set -euo pipefail
first_dir_with() {   # first folder among the rest that holds file $1
  local f="$1"; shift
  for d in "$@"; do [ -n "$d" ] && [ -x "$d/$f" ] && { echo "$d"; return; }; done
}
bin="${HORIZON_ORBITAL:-$(first_dir_with horizon-client "$HOME/horizon-orbital" "$HOME/horizon-src/target/release" "$HOME/horizon-src/target/fast")}"
if [ -z "$bin" ] || [ ! -x "$bin/horizon-client" ] || [ ! -x "$bin/horizon-ctl" ]; then
  echo "Can't find the Orbital Laser build of Horizon. Download it from https://github.com/Stink-O/horizon/releases" >&2
  echo "and unpack it to ~/horizon-orbital (or set HORIZON_ORBITAL to its folder)." >&2
  exit 1
fi
res="${HORIZON_RESOURCES:-}"
if [ -z "$res" ]; then
  for d in "$bin/.local/horizon-client/26.3" "$HOME/Downloads/horizon-linux-x86_64/.local/horizon-client/26.3"; do
    [ -d "$d" ] && { res="$d"; break; }
  done
fi
if [ -z "$res" ]; then
  echo "No prepared resources found. Run once, in $bin:  ./horizon-prepare --prepare --server-jar PATH/TO/server.jar" >&2
  echo "(see Horizon's PLAY.txt), or set HORIZON_RESOURCES to an existing Horizon's .local/horizon-client/26.3." >&2
  exit 1
fi
home="${HORIZON_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/horizon}"
mkdir -p "$home"
cd "$home"   # the game keeps saves, options and mods in the folder it starts in
exec "$bin/horizon-ctl" launch --world "${1:-OrbitalTest}" --creative --wait \
  --game "$bin/horizon-client" --resources "$res"
