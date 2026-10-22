#!/usr/bin/env python3
"""Orbital Laser: the driver for the strike.

  ./strike.py --daemon     hand yourself the Orbital Laser Designator and the Orbital Remote and wait. Look through the
                           designator for a moment and the strike lands wherever you point, up to 200 blocks away.
                           Tap the remote to cycle the theme: Plasma, Inferno, Void, Godly.
  ./strike.py              fire once at the block under the crosshair (within normal reach)
  ./strike.py --at X Y Z   fire once at a surface block
  ./strike.py --theme godly      pick the theme for a one-off strike (or the daemon's starting theme)

  --no-terrain   --no-sound   --radius N   --depth N   (depth defaults to all the way down to bedrock)
  --ctl PATH     path to horizon-ctl   (default: $HORIZON_CTL, then PATH, then next to this script)
  --home PATH    Horizon's game home   (default: $HORIZON_HOME, then the usual place for your OS)
  --doctor       check the whole setup and say what to fix
  --timeline F   also write the strike's sound timeline to F (JSON), for building soundtracks

Needs Horizon running with its control socket (horizon-ctl launch --world NAME --creative), cheats on, the
"Orbital Laser" shader pack selected and, for the custom sounds, the "orbital-sounds" resource pack enabled. The two
items come from the orbital-laser-mod content mod (install.py puts it in place); without it the daemon falls back to
renamed spyglasses. Run install.py once first. The strike edits the installed shader pack's pack.toml to aim and restart it.

WARNING: a strike permanently destroys terrain (a crater and a shaft to bedrock) and kills every mob and
dropped item within 40 blocks of the impact. Players are spared. Back up your world.
"""
import argparse, json, math, os, random, re, shlex, shutil, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from themes import THEMES, BY_KEY   # noqa: E402

RELOAD_LAG = 0.40   # the pack's clock starts ~0.4 s after pack.toml is written
FIRE = 4.0          # shader time of the impact (strike.wgsl: T_FIRE)
NAME = "Orbital Laser Designator"
REMOTE_NAME = "Orbital Remote"
ITEM_DESIGNATOR = "orbital:laser_designator"   # from the orbital-laser-mod content mod
ITEM_REMOTE = "orbital:remote"
TAP_TICKS = 11      # a use of the remote shorter than this is a tap: it changes the theme
RANGE = 200         # blocks the designator can reach
KILL_RADIUS = 40    # mobs and dropped items inside this many blocks of the impact die (players don't)
LOCK_TICKS = 14     # ticks of looking through the scope before it fires

ap = argparse.ArgumentParser()
ap.add_argument("--daemon", action="store_true")
ap.add_argument("--no-terrain", action="store_true")
ap.add_argument("--no-sound", action="store_true")
ap.add_argument("--at", type=int, nargs=3, metavar=("X", "Y", "Z"))
ap.add_argument("--radius", type=int, default=None, help="shaft radius at the top, in blocks (default: the theme's)")
ap.add_argument("--depth", type=int, default=0, help="how deep to drill (default 0: all the way down to bedrock)")
ap.add_argument("--ctl", help="path to horizon-ctl")
ap.add_argument("--home", help="Horizon's game home (where options.txt and shaderpacks/ live)")
ap.add_argument("--doctor", action="store_true", help="check the whole setup and say what to fix")
ap.add_argument("--theme", choices=[t.key for t in THEMES], default="plasma", help="plasma, inferno, void or godly")
ap.add_argument("--timeline", help="write the strike's sound timeline here (JSON)")
ap.add_argument("--capture", action="store_true", help="shader video-capture mode (luma + alternating chroma); see tools/make_video.py")
ap.add_argument("--list-themes", action="store_true")
args = ap.parse_args()
if args.list_themes:
    for t in THEMES:
        print(f"{t.key:8s} {t.blurb}")
    sys.exit(0)


def home_candidates():
    """Where Horizon keeps its game folder (options.txt, saves/, shaderpacks/, resourcepacks/), most likely first."""
    h = Path.home()
    out = [args.home, os.environ.get("HORIZON_HOME")]
    if sys.platform == "win32":
        out += [Path(os.environ.get("APPDATA", h / "AppData/Roaming")) / "horizon",
                Path(os.environ.get("LOCALAPPDATA", h / "AppData/Local")) / "horizon"]
    elif sys.platform == "darwin":
        out += [h / "Library/Application Support/horizon", h / ".local/share/horizon"]
    else:
        out += [Path(os.environ.get("XDG_DATA_HOME", h / ".local/share")) / "horizon"]
    return [Path(c) for c in out if c]


def find_home():
    for explicit in (args.home, os.environ.get("HORIZON_HOME")):   # a folder you named always wins
        if explicit and Path(explicit).is_dir():
            return Path(explicit)
    for c in home_candidates():
        if c.is_dir() and ((c / "options.txt").exists() or (c / "saves").is_dir() or (c / "shaderpacks").is_dir()):
            return c
    for c in home_candidates():
        if c.is_dir():
            return c
    return None


def find_ctl():
    for cand in (args.ctl, os.environ.get("HORIZON_CTL"), shutil.which("horizon-ctl"),
                 HERE / "horizon-ctl", HERE.parent / "horizon-ctl"):
        if cand and Path(cand).is_file():
            return str(cand)
    sys.exit("Can't find horizon-ctl. Pass --ctl PATH, set HORIZON_CTL, or put it on your PATH.")


def find_pack():
    home = find_home()
    if home is None:
        sys.exit("Can't find Horizon's game folder. Pass --home PATH or set HORIZON_HOME (it holds options.txt and "
                 "saves/; `horizon-ctl launch` prints it as \"home\").")
    pack = home / "shaderpacks" / "orbital-laser-shader" / "pack.toml"
    if not pack.is_file():
        sys.exit(f"The shader pack isn't installed ({pack} is missing). Run install.py first, or pass --home.")
    return pack


def doctor():
    """Check the whole setup and print what to fix. Never changes anything."""
    ok = True

    def line(good, what, fix=""):
        nonlocal ok
        ok = ok and good
        print(("  [ok]   " if good else "  [FAIL] ") + what + (("\n           -> " + fix) if fix and not good else ""))

    print(f"Orbital Laser doctor (python {sys.version.split()[0]}, {sys.platform})")
    line(sys.version_info >= (3, 8), "Python 3.8 or newer", "install a newer Python 3")
    ctl_path = None
    try:
        ctl_path = find_ctl()
    except SystemExit:
        pass
    line(bool(ctl_path), f"horizon-ctl found ({ctl_path})" if ctl_path else "horizon-ctl found",
         "it ships in Horizon's folder: pass --ctl PATH, set HORIZON_CTL, or add it to PATH")
    home = find_home()
    line(bool(home), f"Horizon game folder found ({home})" if home else "Horizon game folder found",
         "run Horizon once, then pass --home PATH or set HORIZON_HOME (it holds options.txt and saves/). "
         "Tried: " + ", ".join(str(c) for c in home_candidates()))
    if home:
        sp = home / "shaderpacks" / "orbital-laser-shader" / "pack.toml"
        rp = home / "resourcepacks" / "orbital-sounds" / "pack.mcmeta"
        line(sp.is_file(), "shader pack installed", "run: python3 install.py")
        line(rp.is_file(), "sound pack installed", "run: python3 install.py")
        mp = home / "horizon-mods" / "orbital-laser" / "horizon-mod.toml"
        mt = home / "horizon-mods.txt"
        line(mp.is_file() and mt.is_file() and "mod.orbital:true" in mt.read_text(),
             "item mod installed and switched on (the Designator and the Remote)",
             "run: python3 install.py --enable (without it the daemon falls back to renamed spyglasses, which still work)")
        gfx = (home / "horizon-graphics.txt")
        sel = gfx.is_file() and "shaderPack:orbital-laser-shader" in gfx.read_text()
        line(sel, "shader pack selected", "close the game, run: python3 install.py --enable (or pick it in Options > Video Settings > Shader Packs)")
        opt = home / "options.txt"
        snd = opt.is_file() and "orbital-sounds" in opt.read_text()
        line(snd, "sound pack enabled", "close the game, run: python3 install.py --enable (or enable it in Options > Resource Packs)")
    if ctl_path:
        st = {}
        try:
            st = json.loads(subprocess.run([ctl_path, "state"], capture_output=True, text=True, timeout=15).stdout or "{}")
        except Exception:
            pass
        running = "player" in st
        line(running, "Horizon is running with its control socket",
             "start it with: horizon-ctl launch --world NAME --creative --wait")
        if running:
            print(f"           player in {st.get('dimension')}, game mode {st.get('gamemode')}")
            line(st.get("gamemode") in ("creative", "survival"), "you can hold items (not spectator)",
                 "run: horizon-ctl command \"gamemode creative\"")
            try:
                logs = subprocess.run([ctl_path, "logs"], capture_output=True, text=True, timeout=15).stdout
            except Exception:
                logs = ""
            bad = [l for l in logs.splitlines() if "orbital-laser-shader" in l and "WARN" in l]
            line(not bad, "shader pack compiles without errors (recent log)",
                 "run tools/check-shader.sh and read the message; last log line: " + (bad[-1][:140] if bad else ""))
    print("\nAll good: run  python3 strike.py --daemon" if ok else "\nFix the [FAIL] items above, then run this again.")
    sys.exit(0 if ok else 1)


if args.doctor:
    doctor()

CTL = find_ctl()
PACK = find_pack()


def ctl(*a):
    return subprocess.run([CTL, *a], capture_output=True, text=True).stdout


_pipe = None
DAEMON_QUIET = False   # the daemon holds command feedback off for its whole lifetime


def drain(timeout=60):
    """Close the command pipe and wait for horizon-ctl to finish running everything already sent."""
    global _pipe
    if _pipe is not None:
        try:
            _pipe.stdin.close()
            _pipe.wait(timeout=timeout)
        except Exception:
            pass
        _pipe = None


def cmd(c):
    """Send a command through one long-lived `horizon-ctl script` so hundreds of /fill lines stay fast."""
    global _pipe
    if _pipe is None or _pipe.poll() is not None:
        _pipe = subprocess.Popen([CTL, "script", "--keep-going"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, text=True)
    _pipe.stdin.write("command " + shlex.quote(c) + "\n")
    _pipe.stdin.flush()


def jctl(*a):
    try:
        return json.loads(ctl(*a) or "{}")
    except json.JSONDecodeError:
        return {}


def setopt(**kw):
    s = PACK.read_text()
    for k, v in kw.items():
        s = re.sub(rf"(\[options\.{k}\][^\[]*?default = )[-0-9.eE+]+", rf"\g<1>{float(v):.2f}", s, flags=re.S)
    PACK.write_text(s)


def actionbar(text, color="red"):
    cmd(f'execute as @s at @s run title @a actionbar {{"text":"{text}","color":"{color}","bold":true}}')


# ---------------------------------------------------------------------------------------------
def aim_ray():
    """March the view ray out to RANGE blocks and return (hit block, entry point) or None."""
    st = jctl("state")
    p = st.get("player", {})
    if "eye" not in p:
        return None
    yaw, pitch = math.radians(p["yaw"]), math.radians(p["pitch"])
    d = (-math.sin(yaw) * math.cos(pitch), -math.sin(pitch), math.cos(yaw) * math.cos(pitch))
    ex, ey, ez = p["eye"]

    def block_at(t):
        x, y, z = ex + d[0] * t, ey + d[1] * t, ez + d[2] * t
        b = jctl("block", str(math.floor(x)), str(math.floor(y)), str(math.floor(z)))
        return b, (x, y, z)

    prev = 0.0
    t = 2.0
    while t <= RANGE:
        b, pt = block_at(t)
        if not b.get("loaded", True):
            return None
        name = b.get("block", "minecraft:air")
        if name not in ("minecraft:air", "minecraft:cave_air", "minecraft:void_air") and "water" not in name:
            for tt in [prev + i * 0.25 for i in range(1, int((t - prev) / 0.25) + 1)]:   # refine the entry point
                b2, pt2 = block_at(tt)
                n2 = b2.get("block", "minecraft:air")
                if n2 not in ("minecraft:air", "minecraft:cave_air", "minecraft:void_air") and "water" not in n2:
                    return b2["pos"], pt2
            return b["pos"], pt
        prev = t
        t += 3.0
    return None


# ---------------------------------------------------------------------------------------------
def run_strike(bx, by, bz, px, py, pz, theme=None):
    theme = theme or BY_KEY[args.theme]
    tx, ty, tz = round(px, 2), round(py, 2), round(pz, 2)
    print(f"strike [{theme.key}] -> {tx} {ty} {tz}  (block {bx} {by} {bz})", flush=True)
    events = []
    sound_log = []

    def at(t, c):
        events.append((t, c))

    def sound(t, name, vol=8, pitch=1.0):
        if not args.no_sound:
            v = min(vol / 10.0, 1.0)
            at(t, f"playsound minecraft:{name} master @a ~ ~ ~ {v:.2f} {pitch} {v:.2f}")

    def csound(t, role, vol=10, pitch=1.0):
        if not args.no_sound:
            v = min(vol / 10.0, 1.0)
            ev = theme.snd(role)
            at(t, f"playsound orbital:{ev} master @a ~ ~ ~ {v:.2f} {pitch} {v:.2f}")
            sound_log.append({"t": round(t, 3), "event": ev, "volume": round(v, 2), "pitch": pitch})

    T = FIRE
    # charge, lock-on, impact
    csound(0.0, "charge", 10, 1.0)
    csound(3.4, "lockon", 8, 1.0)
    at(3.5, f'title @a actionbar {{"text":"ORBITAL LASER: LOCKED  [{theme.title}]","color":"{theme.color}","bold":true}}')
    csound(T, "fire", 10, 1.0)
    if theme.key in ("plasma", "inferno"):                   # vanilla thunder and an explosion underneath, for texture
        sound(T + 0.05, "entity.lightning_bolt.thunder", 6, 0.6)
        sound(T + 0.1, "entity.generic.explode", 5 if theme.key == "plasma" else 7, 0.45)
    at(T, f"particle minecraft:explosion_emitter {tx} {ty + 1} {tz} 0 0 0 0 1 force")
    at(T + 0.1, 'title @a actionbar {"text":"DIRECT HIT","color":"white","bold":true}')
    # while it burns
    for i in range(3):
        csound(T + 0.2 + i * 3.4, "beam", 9, 1.0)
    csound(T + 0.6, "rumble", 9, 0.95)
    csound(T + 4.2, "rumble", 8, 0.85)
    accents = (1.1, 2.4, 3.9, 5.3, 6.8) if theme.key == "plasma" else (1.4, 3.9, 6.6)
    for i, tc in enumerate(accents):
        csound(T + tc, "accent", 7 + i % 2, 0.85 + 0.12 * ((i * 3) % 4))
    if not args.no_terrain:
        for i in range(3):
            csound(T + 1.2 + i * 2.6, "collapse", 8, 0.92 + 0.08 * i)
    csound(T + 9.2, "shutdown", 9, 1.0)

    rng = random.Random(bx * 73856093 ^ bz * 19349663 ^ by)

    def disc(r, y_lo, y_hi, block="minecraft:air", rough=0.0, replace=None):
        """A rough filled circle built from a few rectangles (consecutive rows share one /fill)."""
        out = []
        suffix = f" replace {replace}" if replace else ""
        rows = list(range(-r, r + 1))
        groups = min(len(rows), 3 + round(r * 0.6))
        for g in range(groups):
            chunk = rows[g * len(rows) // groups:(g + 1) * len(rows) // groups]
            if not chunk:
                continue
            hw = sum(math.sqrt(max(r * r - dz * dz, 0)) for dz in chunk) / len(chunk)
            hw = int(hw * (1.0 + rng.uniform(-rough, rough)) + 0.5)
            out.append(f"fill {bx - hw} {y_lo} {bz + chunk[0]} {bx + hw} {y_hi} {bz + chunk[-1]} {block}{suffix}")
        return out

    if not args.no_terrain:
        R = args.radius or theme.shaft_r                  # shaft radius at the mouth
        dim = jctl("state").get("dimension", "minecraft:overworld")
        bedrock_top = {"minecraft:overworld": -59, "minecraft:the_nether": 5}.get(dim, 1)   # one block above the bedrock layer
        floor_y = max(by - args.depth, bedrock_top) if args.depth > 0 else bedrock_top
        # 1. the blast: everything standing above the ground in a wide disc is vaporised
        for c in disc(24, by + 1, by + 40, rough=0.12):
            at(T + 0.15, c)
        # 2. scorched earth: what the ground around the crater turns into
        for (rad, block, rgh, repl) in theme.scorch:
            for c in disc(rad, by - 3, by + 1, block, rgh, repl):
                at(T + 0.4 + rng.random() * 2.2, c)
        for (rad, block, rgh, repl) in theme.scorch2:
            for c in disc(rad, by - 3, by + 1, block, rgh, repl):
                at(T + 3.2 + rng.random() * 0.8, c)
        # 3. the bowl: a rough paraboloid crater, outer layers first
        bowl_r, bowl_d = theme.bowl_r, theme.bowl_d
        for d in range(0, bowl_d, 2):
            r = max(3, int(bowl_r * math.sqrt(1 - d / (bowl_d + 0.5))))
            for c in disc(r, by - d - 1, by - d, rough=theme.bowl_rough):
                at(T + 0.5 + d * 0.28, c)
        fb, fr, fq = theme.bowl_floor
        for c in disc(bowl_r - 4, by - bowl_d, by - bowl_d + 1, fb, fr, fq):
            at(T + 4.2, c)
        # 4. the shaft: drills on down through the bowl, funnelling in and then running straight to bedrock
        steps = max((by - bowl_d - floor_y) // 4 + 1, 1)
        for i in range(steps):
            y_hi = by - bowl_d - 4 * i
            if y_hi < floor_y:
                break
            r = max(theme.shaft_min, round(R - i * (R - theme.shaft_min) / 14))
            t = T + 1.2 + i * (8.2 / steps)
            for c in disc(r, max(y_hi - 3, floor_y), y_hi, rough=theme.shaft_rough):
                at(t, c)
            at(t, theme.particle_a.format(x=bx + 0.5, y=by + 1, z=bz + 0.5, r=round(r * 0.6, 1)))
            at(t, theme.particle_b.format(x=bx + 0.5, y=y_hi, z=bz + 0.5, r=round(r * 0.4, 1)))
        # 5. the bottom of the shaft
        tb = T + 9.6
        for k, (rad, lo, hi, block) in enumerate(theme.bottom):
            for c in disc(rad, floor_y + lo, floor_y + hi, block):
                at(tb + 0.1 * k, c)
        if theme.key in ("plasma", "inferno"):
            sound(tb, "block.lava.pop", 8, 0.6)
        # 6. godly: eight quartz pillars crowned with glowstone stand round the crater
        if theme.pillars:
            for k in range(8):
                px_ = bx + round(math.cos(k * math.pi / 4) * (theme.bowl_r + 4))
                pz_ = bz + round(math.sin(k * math.pi / 4) * (theme.bowl_r + 4))
                at(T + 4.5 + 0.2 * k, f"fill {px_} {by - 4} {pz_} {px_} {by + 6} {pz_} minecraft:quartz_pillar")
                at(T + 4.6 + 0.2 * k, f"setblock {px_} {by + 7} {pz_} minecraft:glowstone")
    if theme.blessing:
        at(T + 1.0, f"execute positioned {tx} {ty} {tz} run effect give @a[distance=..60] minecraft:regeneration 15 1 true")
        at(T + 1.0, f"execute positioned {tx} {ty} {tz} run effect give @a[distance=..60] minecraft:absorption 30 1 true")
    # wipe out every living thing near the impact (players are spared); a few passes catch anything wandering in
    for tk in (0.15, 0.9, 2.5, 5.0, 8.0):
        at(T + tk, f"execute positioned {tx} {ty} {tz} run kill @e[type=!minecraft:player,distance=..{KILL_RADIUS}]")
    events.sort(key=lambda e: e[0])
    if args.timeline:
        Path(args.timeline).write_text(json.dumps({"theme": theme.key, "target": [tx, ty, tz], "fire": T, "length": 26.0,
                                                   "sounds": sorted(sound_log, key=lambda e: e["t"])}, indent=1))

    # keep the chat clean: no "Successfully filled..." / "Played sound..." lines while the strike runs
    if not DAEMON_QUIET:
        cmd("execute as @s run gamerule minecraft:send_command_feedback false")   # forked: no "already set" chatter
        time.sleep(0.15)
    try:
        # a fresh seed per strike: palette, surges, lightning and sway all differ every time
        setopt(target_x=tx, target_y=ty, target_z=tz, freeze_time=-1.0, swz=3.0 if args.capture else 0.0, seed=random.randint(1, 999), theme=theme.index)
        t0 = time.time() + RELOAD_LAG
        for t, c in events:
            delay = t0 + t - time.time()
            if delay > 0:
                time.sleep(delay)
            cmd("execute as @s at @s run " + c)   # forked execute: failures like "No blocks were filled" stay out of chat
        drain()                                  # block until the game has executed every queued command
        time.sleep(max(0.0, t0 + 25.0 - time.time()))
    finally:
        setopt(freeze_time=100.0, swz=0.0)  # idle again
        if not DAEMON_QUIET:
            cmd("gamerule minecraft:send_command_feedback true")                  # back to vanilla's default
            time.sleep(0.2)


# ---------------------------------------------------------------------------------------------
def item_kind(st):
    """'designator', 'remote' or None for the held item: the real mod items, or renamed spyglasses as a fallback."""
    held = st.get("held") or {}
    item, comp = held.get("item"), str(held.get("components", ""))
    if item == ITEM_DESIGNATOR:
        return "designator"
    if item == ITEM_REMOTE:
        return "remote"
    if item == "minecraft:spyglass":
        if NAME in comp:
            return "designator"
        if REMOTE_NAME in comp:
            return "remote"
    return None


def theme_bar(theme):
    actionbar(f"THEME: {theme.title}", theme.color)


def set_remote_name(slot, theme, real):
    """Rename the remote in its slot to show the current theme (the slot is 0 to 8, left to right)."""
    name = f"{REMOTE_NAME} - {theme.title}"
    base = ITEM_REMOTE if real else "minecraft:spyglass"
    extra = "" if real else ",enchantment_glint_override=true"
    cmd(f'execute as @s run item replace entity @s hotbar.{slot} with {base}[custom_name={{text:"{name}",color:"{theme.color}",bold:true}}{extra}]')


if args.daemon:
    import atexit, signal
    theme = BY_KEY[args.theme]
    # can we hand out the real mod items? (this has to be asked before command feedback is switched off)
    probe = ctl("command", f"item replace entity @s hotbar.8 with {ITEM_DESIGNATOR}")
    real = "Unknown item" not in probe
    DAEMON_QUIET = True
    cmd("execute as @s run gamerule minecraft:send_command_feedback false")   # nothing the designator does may show in chat
    time.sleep(0.2)
    atexit.register(lambda: ctl("command", "gamerule minecraft:send_command_feedback true"))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    if real:
        set_remote_name(7, theme, True)
    else:
        cmd(f'execute as @s run item replace entity @s hotbar.8 with minecraft:spyglass[custom_name={{text:"{NAME}",color:"red",bold:true}},'
            f'enchantment_glint_override=true]')
        set_remote_name(7, theme, False)
    ctl("select", "9")
    print(f"{NAME} is in your last hotbar slot and the {REMOTE_NAME} next to it ({'real items' if real else 'spyglass fallback: install the mod for real items'}).")
    print(f"Theme: {theme.key}. Hold the designator and look through it to fire; tap the remote to change theme (sneak + tap goes back).")
    print("Ctrl-C to stop.", flush=True)
    armed = True
    last_use = None                 # the remote's use in progress: {"ticks": ..., "slot": ...}
    idx = [t.key for t in THEMES].index(theme.key)
    while True:
        st = jctl("state")
        using = st.get("using")
        kind = item_kind(st)
        if not using:
            armed = True
            if last_use is not None:                       # a use of the remote just ended
                if last_use["ticks"] <= TAP_TICKS:         # ...and it was a tap: change theme
                    back = bool((st.get("player") or {}).get("sneaking"))
                    idx = (idx + (-1 if back else 1)) % len(THEMES)
                    theme = THEMES[idx]
                    set_remote_name(last_use["slot"], theme, real)
                    theme_bar(theme)
                    print(f"theme -> {theme.key}", flush=True)
                last_use = None
        elif kind == "remote":
            last_use = {"ticks": using.get("ticks", 0), "slot": using.get("slot", 7)}
        elif armed and kind == "designator":
            ticks = using.get("ticks", 0)
            if ticks < LOCK_TICKS:
                if ticks % 4 == 0:
                    actionbar(f"ACQUIRING TARGET {'.' * (1 + ticks // 4)}  [{theme.title}]", theme.color)
            else:
                armed = False
                print("locked, tracing...", flush=True)
                hit = aim_ray()
                if not hit:
                    print("no target in range", flush=True)
                    actionbar("NO TARGET IN RANGE", "gray")
                else:
                    (bx, by, bz), (px, py, pz) = hit
                    run_strike(bx, by, bz, px, py, pz, theme)
        time.sleep(0.04)
elif args.at:
    bx, by, bz = args.at
    run_strike(bx, by, bz, bx + 0.5, by + 1.0, bz + 0.5)
else:
    look = jctl("looking-at").get("block")
    if not look:
        sys.exit("Look at a block within reach, pass --at X Y Z, or use --daemon to fire at any distance.")
    px, py, pz = look["point"]
    run_strike(*(math.floor(v) for v in look["pos"]), px, py, pz)
