#!/usr/bin/env bash
# Start the Horizon build that runs Orbital Laser (Horizon with the input, ui, render and world mod interfaces:
# https://github.com/Stink-O/horizon/releases) on your own game folder, so it sees your worlds, settings and mods.
# Stock Horizon can't run the mod: start the game with this script, from a terminal.
#
#   ./play.sh [WORLD]          default world: OrbitalTest (made if it doesn't exist; creative, cheats on)
#
# Where things are (each can be set in the environment):
#   HORIZON_ORBITAL    the folder with that build's horizon-client and horizon-ctl
#                      default: ~/horizon-orbital, else a source build in ~/horizon-src/target/{release,fast}
#   HORIZON_RESOURCES  prepared resources (horizon-prepare makes them)
#                      default: $HORIZON_ORBITAL/.local/horizon-client/26.3, else the ones beside your installed Horizon
#   HORIZON_HOME       your game folder (options.txt, saves/, horizon-mods/); default ~/.local/share/horizon
#   ORBITAL_NO_CHECK=1 start the build even if it doesn't look like the Orbital Laser build
set -euo pipefail
RELEASES="https://github.com/Stink-O/horizon/releases"

# Say what went wrong and stop. Started without a terminal (double-clicked in a file manager), the message would go
# nowhere, so it is also shown in a dialog if there is a way to, and written to play-error.txt beside this script.
fail() {
  local msg
  msg="$(printf '%s\n' "$@")"
  printf '\nplay.sh: %s\n\n' "$msg" >&2
  if [ ! -t 2 ]; then
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s\n' "$msg" > "$here/play-error.txt" 2>/dev/null || true
    if command -v zenity >/dev/null 2>&1; then
      zenity --error --title "Orbital Laser" --no-markup --text "$msg" 2>/dev/null || true
    elif command -v kdialog >/dev/null 2>&1; then
      kdialog --title "Orbital Laser" --error "$msg" 2>/dev/null || true
    elif command -v osascript >/dev/null 2>&1; then
      osascript -e 'on run argv' -e 'display alert "Orbital Laser" message (item 1 of argv) as critical' \
        -e 'end run' "$msg" >/dev/null 2>&1 || true
    elif command -v notify-send >/dev/null 2>&1; then
      notify-send "Orbital Laser" "$msg" 2>/dev/null || true
    fi
  fi
  exit 1
}

first_dir_with() {   # first folder among the rest that holds file $1 (none: nothing, and no error, for set -e)
  local f="$1"; shift
  for d in "$@"; do [ -n "$d" ] && [ -x "$d/$f" ] && { echo "$d"; return 0; }; done
  return 0
}
if [ -n "${HORIZON_ORBITAL:-}" ]; then
  bin="$HORIZON_ORBITAL"
  searched="$bin (HORIZON_ORBITAL)"
else
  bin="$(first_dir_with horizon-client "$HOME/horizon-orbital" "$HOME/horizon-src/target/release" "$HOME/horizon-src/target/fast")"
  searched="~/horizon-orbital, ~/horizon-src/target/release and ~/horizon-src/target/fast"
fi
if [ -z "$bin" ] || [ ! -x "$bin/horizon-client" ]; then
  fail "Can't find the Orbital Laser build of Horizon (no horizon-client in $searched)." \
    "" \
    "Orbital Laser needs that build: stock Horizon can't run the mod (its Mods screen says" \
    "\"Can't be read: horizon-mod.toml: capability world is for server mods\")." \
    "" \
    "Download it from $RELEASES (release orbital-mod-api-8 or newer)," \
    "unpack it to ~/horizon-orbital (or set HORIZON_ORBITAL to its folder), then run ./play.sh again from a terminal."
fi
if [ ! -x "$bin/horizon-ctl" ]; then
  fail "$bin has horizon-client but no horizon-ctl, which play.sh starts the game with." \
    "Unpack the whole Orbital Laser build of Horizon there ($RELEASES), or set HORIZON_ORBITAL to the folder that has both."
fi
# A cheap look inside the program (skipped without grep): a build made without --features mods says it has no mod
# runtime, and the fork's build knows the mod interfaces Orbital Laser uses (world.push-player is the newest it needs),
# which stock Horizon doesn't.
if [ "${ORBITAL_NO_CHECK:-}" != 1 ] && command -v grep >/dev/null 2>&1; then
  if LC_ALL=C grep -q -a -F 'has no mod runtime' "$bin/horizon-client"; then
    fail "$bin/horizon-client was built without the mod runtime, so the mod can't start (/orbital is unknown)." \
      "Build it again with:  cargo build --release -p horizon-client --features mods" \
      "or download the ready-made build from $RELEASES."
  fi
  if ! LC_ALL=C grep -q -a -F 'push-player' "$bin/horizon-client"; then
    fail "$bin/horizon-client isn't the Orbital Laser build of Horizon (stock Horizon, or a fork build older than" \
      "release orbital-mod-api-8), so it can't run the mod." \
      "Download the build from $RELEASES and unpack it to ~/horizon-orbital (or set HORIZON_ORBITAL to its folder)." \
      "(ORBITAL_NO_CHECK=1 ./play.sh starts it anyway.)"
  fi
fi
res="${HORIZON_RESOURCES:-}"
if [ -z "$res" ]; then
  for d in "$bin/.local/horizon-client/26.3" "$HOME/Downloads/horizon-linux-x86_64/.local/horizon-client/26.3"; do
    [ -d "$d" ] && { res="$d"; break; }
  done
fi
if [ -z "$res" ]; then
  fail "No prepared resources found. Run once, in $bin:  ./horizon-prepare --prepare --server-jar PATH/TO/server.jar" \
    "(see Horizon's PLAY.txt), or set HORIZON_RESOURCES to an existing Horizon's .local/horizon-client/26.3."
fi
home="${HORIZON_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/horizon}"
mkdir -p "$home"
cd "$home"   # the game keeps saves, options and mods in the folder it starts in
exec "$bin/horizon-ctl" launch --world "${1:-OrbitalTest}" --creative --wait \
  --game "$bin/horizon-client" --resources "$res"
