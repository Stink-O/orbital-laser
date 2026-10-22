#!/usr/bin/env python3
"""Orbital Laser: the driver for the strike.

  ./strike.py --daemon     hand yourself the Orbital Laser Designator (a spyglass) and wait: look through
                           it for a moment and the strike lands wherever you point, up to 200 blocks away.
  ./strike.py              fire once at the block under the crosshair (within normal reach)
  ./strike.py --at X Y Z   fire once at a surface block

  --no-terrain   --no-sound   --radius N   --depth N   (depth defaults to all the way down to bedrock)
  --ctl PATH     path to horizon-ctl   (default: $HORIZON_CTL, then PATH, then next to this script)
  --home PATH    Horizon's game home   (default: $HORIZON_HOME, then the usual place for your OS)
  --doctor       check the whole setup and say what to fix

Needs Horizon running with its control socket (horizon-ctl launch --world NAME --creative), cheats on, the
"Orbital Laser" shader pack selected and, for the custom sounds, the "orbital-sounds" resource pack enabled.
Run install.py once first. The strike edits the installed shader pack's pack.toml to aim and restart it.

WARNING: a strike permanently destroys terrain (a crater and a shaft to bedrock) and kills every mob and
dropped item within 40 blocks of the impact. Players are spared. Back up your world.
"""
import argparse, json, math, os, random, re, shlex, shutil, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELOAD_LAG = 0.40   # the pack's clock starts ~0.4 s after pack.toml is written
FIRE = 4.0          # shader time of the impact (strike.wgsl: T_FIRE)
NAME = "Orbital Laser Designator"
RANGE = 200         # blocks the designator can reach
KILL_RADIUS = 40    # mobs and dropped items inside this many blocks of the impact die (players don't)
LOCK_TICKS = 14     # ticks of looking through the scope before it fires

ap = argparse.ArgumentParser()
ap.add_argument("--daemon", action="store_true")
ap.add_argument("--no-terrain", action="store_true")
ap.add_argument("--no-sound", action="store_true")
ap.add_argument("--at", type=int, nargs=3, metavar=("X", "Y", "Z"))
ap.add_argument("--radius", type=int, default=9, help="shaft radius at the top, in blocks")
ap.add_argument("--depth", type=int, default=0, help="how deep to drill (default 0: all the way down to bedrock)")
ap.add_argument("--ctl", help="path to horizon-ctl")
ap.add_argument("--home", help="Horizon's game home (where options.txt and shaderpacks/ live)")
ap.add_argument("--doctor", action="store_true", help="check the whole setup and say what to fix")
args = ap.parse_args()


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
def run_strike(bx, by, bz, px, py, pz):
    tx, ty, tz = round(px, 2), round(py, 2), round(pz, 2)
    print(f"strike -> {tx} {ty} {tz}  (block {bx} {by} {bz})", flush=True)
    events = []

    def at(t, c):
        events.append((t, c))

    def sound(t, name, vol=8, pitch=1.0):
        if not args.no_sound:
            v = min(vol / 10.0, 1.0)
            at(t, f"playsound minecraft:{name} master @a ~ ~ ~ {v:.2f} {pitch} {v:.2f}")

    def csound(t, name, vol=10, pitch=1.0):
        if not args.no_sound:
            v = min(vol / 10.0, 1.0)
            at(t, f"playsound orbital:{name} master @a ~ ~ ~ {v:.2f} {pitch} {v:.2f}")

    # charge: the turbine spools up and peaks exactly at impact
    csound(0.0, "charge", 10, 1.0)
    csound(3.4, "lockon", 8, 1.0)
    at(3.5, 'title @a actionbar {"text":"ORBITAL LASER: LOCKED","color":"red","bold":true}')
    # impact: the custom blast with a vanilla thunder sample underneath as natural texture
    csound(FIRE, "fire", 10, 1.0)
    sound(FIRE + 0.05, "entity.lightning_bolt.thunder", 6, 0.6)
    sound(FIRE + 0.1, "entity.generic.explode", 5, 0.45)
    at(FIRE, f"particle minecraft:explosion_emitter {tx} {ty + 1} {tz} 0 0 0 0 1 force")
    at(FIRE + 0.1, 'title @a actionbar {"text":"DIRECT HIT","color":"white","bold":true}')
    # while it burns
    for i in range(3):
        csound(FIRE + 0.2 + i * 3.4, "beam", 9, 1.0)
    csound(FIRE + 0.6, "rumble", 9, 0.95)
    csound(FIRE + 4.2, "rumble", 8, 0.85)
    for i, tc in enumerate((1.1, 2.4, 3.9, 5.3, 6.8)):
        csound(FIRE + tc, "crackle", 7 + i % 2, 0.85 + 0.12 * ((i * 3) % 4))
    if not args.no_terrain:
        for i in range(3):
            csound(FIRE + 1.2 + i * 2.6, "collapse", 8, 0.92 + 0.08 * i)
    csound(FIRE + 9.2, "shutdown", 9, 1.0)

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
        R = args.radius                      # shaft radius at the mouth
        dim = jctl("state").get("dimension", "minecraft:overworld")
        bedrock_top = {"minecraft:overworld": -59, "minecraft:the_nether": 5}.get(dim, 1)   # one block above the bedrock layer
        floor_y = max(by - args.depth, bedrock_top) if args.depth > 0 else bedrock_top
        T = FIRE
        # 1. the blast: everything standing above the ground in a wide disc is vaporised
        for c in disc(24, by + 1, by + 40, rough=0.12):
            at(T + 0.15, c)
        # 2. scorched earth: grass and sand around the crater turn to blackstone, patches of magma
        for c in disc(34, by - 3, by + 1, "minecraft:blackstone", 0.15, "minecraft:grass_block"):
            at(T + 0.4 + rng.random() * 2.2, c)
        for c in disc(30, by - 3, by + 1, "minecraft:smooth_basalt", 0.15, "minecraft:sand"):
            at(T + 0.6 + rng.random() * 2.0, c)
        for c in disc(27, by - 2, by, "minecraft:coarse_dirt", 0.15, "minecraft:dirt"):
            at(T + 0.8 + rng.random() * 1.5, c)
        # 3. the bowl: a rough paraboloid crater, outer layers first
        bowl_r, bowl_d = 20, 12
        for d in range(0, bowl_d, 2):
            r = max(3, int(bowl_r * math.sqrt(1 - d / (bowl_d + 0.5))))
            for c in disc(r, by - d - 1, by - d, rough=0.14):
                at(T + 0.5 + d * 0.28, c)
        for c in disc(bowl_r - 4, by - bowl_d, by - bowl_d + 1, "minecraft:magma_block", 0.2, "minecraft:stone"):
            at(T + 4.2, c)
        # 4. the shaft: drills on down through the bowl in 3-block bites, narrowing like a funnel
        steps = max((by - bowl_d - floor_y) // 4 + 1, 1)
        for i in range(steps):
            y_hi = by - bowl_d - 4 * i
            if y_hi < floor_y:
                break
            r = max(3, round(R - i * (R - 3) / 14))          # funnels in over the first ~56 blocks, then a straight narrow column
            t = T + 1.2 + i * (8.2 / steps)
            for c in disc(r, max(y_hi - 3, floor_y), y_hi, rough=0.06):
                at(t, c)
            at(t, f"particle minecraft:flame {bx + 0.5} {by + 1} {bz + 0.5} {r * 0.6} 3 {r * 0.6} 0.25 60 force")
            at(t, f"particle minecraft:lava {bx + 0.5} {y_hi} {bz + 0.5} {r * 0.4} 1 {r * 0.4} 0 25 force")
        # molten bottom
        tb = T + 9.6
        for c in disc(3, floor_y, floor_y, "minecraft:magma_block"):
            at(tb, c)
        for c in disc(2, floor_y + 1, floor_y + 3, "minecraft:lava"):
            at(tb + 0.1, c)
        sound(tb, "block.lava.pop", 8, 0.6)
    # wipe out every living thing near the impact (players are spared); a few passes catch anything wandering in
    for tk in (0.15, 0.9, 2.5, 5.0, 8.0):
        at(FIRE + tk, f"execute positioned {tx} {ty} {tz} run kill @e[type=!minecraft:player,distance=..{KILL_RADIUS}]")
    events.sort(key=lambda e: e[0])

    # keep the chat clean: no "Successfully filled..." / "Played sound..." lines while the strike runs
    if not DAEMON_QUIET:
        cmd("execute as @s run gamerule minecraft:send_command_feedback false")   # forked: no "already set" chatter
        time.sleep(0.15)
    try:
        # a fresh seed per strike: palette, surges, lightning and sway all differ every time
        setopt(target_x=tx, target_y=ty, target_z=tz, freeze_time=-1.0, swz=0.0, seed=random.randint(1, 999))
        t0 = time.time() + RELOAD_LAG
        for t, c in events:
            delay = t0 + t - time.time()
            if delay > 0:
                time.sleep(delay)
            cmd("execute as @s at @s run " + c)   # forked execute: failures like "No blocks were filled" stay out of chat
        drain()                                  # block until the game has executed every queued command
        time.sleep(max(0.0, t0 + 25.0 - time.time()))
    finally:
        setopt(freeze_time=100.0)  # idle again
        if not DAEMON_QUIET:
            cmd("gamerule minecraft:send_command_feedback true")                  # back to vanilla's default
            time.sleep(0.2)


# ---------------------------------------------------------------------------------------------
def holding_designator(st):
    held = st.get("held") or {}
    return held.get("item") == "minecraft:spyglass" and NAME in str(held.get("components", ""))


if args.daemon:
    import atexit, signal
    DAEMON_QUIET = True
    cmd("execute as @s run gamerule minecraft:send_command_feedback false")   # nothing the designator does may show in chat
    time.sleep(0.2)
    atexit.register(lambda: ctl("command", "gamerule minecraft:send_command_feedback true"))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    cmd(f'item replace entity @s hotbar.8 with minecraft:spyglass[custom_name={{text:"{NAME}",color:"red",bold:true}},'
        f'enchantment_glint_override=true]')
    ctl("select", "9")
    print(f"{NAME} is in your last hotbar slot. Hold it, look through the scope at a target and wait: it locks and fires.")
    print("Ctrl-C to stop.", flush=True)
    armed = True
    while True:
        st = jctl("state")
        using = st.get("using")
        if not using:
            armed = True
        elif armed and holding_designator(st):
            ticks = using.get("ticks", 0)
            if ticks < LOCK_TICKS:
                if ticks % 4 == 0:
                    actionbar(f"ACQUIRING TARGET {'.' * (1 + ticks // 4)}", "gold")
            else:
                armed = False
                print("locked, tracing...", flush=True)
                hit = aim_ray()
                if not hit:
                    print("no target in range", flush=True)
                    actionbar("NO TARGET IN RANGE", "gray")
                else:
                    (bx, by, bz), (px, py, pz) = hit
                    run_strike(bx, by, bz, px, py, pz)
        time.sleep(0.1)
elif args.at:
    bx, by, bz = args.at
    run_strike(bx, by, bz, bx + 0.5, by + 1.0, bz + 0.5)
else:
    look = jctl("looking-at").get("block")
    if not look:
        sys.exit("Look at a block within reach, pass --at X Y Z, or use --daemon to fire at any distance.")
    px, py, pz = look["point"]
    run_strike(*(math.floor(v) for v in look["pos"]), px, py, pz)
