#!/usr/bin/env python3
"""Orbital Laser: the driver for the strike.

  ./strike.py --daemon     hand yourself the Orbital Laser Designator and the Orbital Remote and wait. Look through the
                           designator for a moment and the strike lands wherever you point, up to 200 blocks away.
                           Right-click the remote for its menu: pick the laser (Plasma or Godly), switch terrain damage.
  ./strike.py              fire once at the block under the crosshair (within normal reach)
  ./strike.py --at X Y Z   fire once at a surface block
  ./strike.py --theme godly      pick the theme for a one-off strike (or the daemon's starting theme)

  --no-terrain   --no-sound   --radius N   --depth N   (depth defaults to all the way down to bedrock)
  --ctl PATH     path to horizon-ctl   (default: $HORIZON_CTL, then PATH, then next to this script)
  --home PATH    Horizon's game home   (default: $HORIZON_HOME, then the usual place for your OS)
  --doctor       check the whole setup and say what to fix
  --timeline F   also write the strike's sound timeline to F (JSON), for building soundtracks

Needs Horizon running with its control socket (horizon-ctl launch --world NAME --creative), cheats on, the
"Orbital Laser" shader pack selected and, for the custom sounds, the "orbital-sounds" resource pack enabled. The items'
looks come from the orbital-laser-mod content mod (install.py puts it in place); without it they are plain spyglasses.
Run install.py --legacy once first. The strike edits the installed shader pack's pack.toml to aim and restart it, and writes its
block changes as functions into a small datapack in the world's folder (datapacks/orbital-laser) so they land in bulk.

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
RANGE = 200         # blocks the designator can reach
KILL_RADIUS = 40    # mobs and dropped items inside this many blocks of the impact die (players don't)
LOCK_TICKS = 14     # ticks of looking through the scope before it fires
GODLY_PILLAR_R = 40            # godly: the six quartz pillars (and the shader's pillars of light) stand on this circle,
GODLY_PILLAR_A0 = math.pi / 6  # the first at this angle; keep in step with strike.wgsl
MENU_SLOTS = {"plasma": 12, "godly": 14}   # where each laser's icon sits in the remote's menu (a 27-slot barrel)
MENU_TERRAIN_SLOT = 22
MENU_FALLBACK_ICON = {"plasma": "minecraft:heart_of_the_sea", "godly": "minecraft:nether_star"}   # without the mod
MENU_STASH_Y = {"minecraft:overworld": 318, "minecraft:the_nether": 126, "minecraft:the_end": 254}   # where the ground under the menu waits

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
ap.add_argument("--theme", choices=[t.key for t in THEMES], default="plasma", help="plasma or godly")
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
        sys.exit(f"The shader pack isn't installed ({pack} is missing). Run install.py --legacy first, or pass --home.")
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
        line(sp.is_file(), "shader pack installed", "run: python3 install.py --legacy")
        line(rp.is_file(), "sound pack installed", "run: python3 install.py --legacy")
        mp = home / "horizon-mods" / "orbital-laser" / "horizon-mod.toml"
        mt = home / "horizon-mods.txt"
        line(mp.is_file() and mt.is_file() and "mod.orbital:true" in mt.read_text(),
             "item mod installed and switched on (the Designator and the Remote)",
             "run: python3 install.py --legacy --enable (without it the daemon falls back to renamed spyglasses, which still work)")
        gfx = (home / "horizon-graphics.txt")
        sel = gfx.is_file() and "shaderPack:orbital-laser-shader" in gfx.read_text()
        line(sel, "shader pack selected", "close the game, run: python3 install.py --legacy --enable (or pick it in Options > Video Settings > Shader Packs)")
        opt = home / "options.txt"
        snd = opt.is_file() and "orbital-sounds" in opt.read_text()
        line(snd, "sound pack enabled", "close the game, run: python3 install.py --legacy --enable (or enable it in Options > Resource Packs)")
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
def surf(x, z, then):
    """`then`, run on the ground at column (x, z): ~ ~ ~ is the first air block above the surface."""
    return f"execute positioned {x} 0 {z} positioned over motion_blocking_no_leaves run {then}"


def run_strike(bx, by, bz, px, py, pz, theme=None, terrain=None):
    theme = theme or BY_KEY[args.theme]
    terrain = (not args.no_terrain) if terrain is None else terrain
    tx, ty, tz = round(px, 2), round(py, 2), round(pz, 2)
    print(f"strike [{theme.key}] -> {tx} {ty} {tz}  (block {bx} {by} {bz}){'' if terrain else '  terrain off'}", flush=True)
    events = []
    sound_log = []

    def at(t, c):
        events.append((t, c))

    def sound(t, name, vol=8, pitch=1.0):
        if not args.no_sound:
            v = min(vol / 10.0, 1.0)
            pitch = round(pitch, 2)
            at(t, f"playsound minecraft:{name} master @a ~ ~ ~ {v:.2f} {pitch} {v:.2f}")
            sound_log.append({"t": round(t, 3), "event": f"minecraft:{name}", "volume": round(v, 2), "pitch": pitch})

    def csound(t, role, vol=10, pitch=1.0):
        if not args.no_sound:
            v = min(vol / 10.0, 1.0)
            ev = theme.snd(role)
            at(t, f"playsound orbital:{ev} master @a ~ ~ ~ {v:.2f} {pitch} {v:.2f}")
            sound_log.append({"t": round(t, 3), "event": ev, "volume": round(v, 2), "pitch": pitch})

    T = FIRE
    plasma, godly = theme.key == "plasma", theme.key == "godly"
    # charge, lock-on, impact
    csound(0.0, "charge", 10, 1.0)
    csound(3.4, "lockon", 8, 1.0)
    at(3.5, f'title @a actionbar {{"text":"ORBITAL LASER: LOCKED  [{theme.title}]","color":"{theme.color}","bold":true}}')
    csound(T, "fire", 10, 1.0)
    # the impact: stacked explosions and thunder under the theme's own blast, then rock raining back down
    for dt, p in ((0.0, 0.42), (0.06, 0.55), (0.2, 0.7), (0.5, 0.5)):
        sound(T + dt, "entity.generic.explode", 10, p)
    sound(T + 0.05, "entity.lightning_bolt.thunder", 9, 0.55)
    sound(T + 0.9, "entity.lightning_bolt.thunder", 6, 0.75)
    at(T, f"particle minecraft:explosion_emitter {tx} {ty + 1} {tz} 0 0 0 0 1 force")
    at(T + 0.1, 'title @a actionbar {"text":"DIRECT HIT","color":"white","bold":true}')
    # while it burns
    for i in range(3):
        csound(T + 0.2 + i * 3.4, "beam", 9, 1.0)
    csound(T + 0.6, "rumble", 9, 0.95)
    csound(T + 4.2, "rumble", 8, 0.85)
    accents = (1.1, 2.4, 3.9, 5.3, 6.8) if plasma else (1.4, 3.9, 6.6)
    for i, tc in enumerate(accents):
        csound(T + tc, "accent", 7 + i % 2, 0.85 + 0.12 * ((i * 3) % 4))
    if terrain:
        for i in range(3):
            csound(T + 1.2 + i * 2.6, "collapse", 8, 0.92 + 0.08 * i)
    csound(T + 9.2, "shutdown", 9, 1.0)

    rng = random.Random(bx * 73856093 ^ bz * 19349663 ^ by)
    if terrain:                                                # everything around the impact shattering at once
        for k in range(14):
            sound(T + 0.05 + k * 0.07, rng.choice(("block.stone.break", "block.gravel.break", "block.grass.break", "block.wood.break")), 10, rng.uniform(0.5, 0.9))
        for k in range(10):                                    # debris raining back down
            sound(T + 1.0 + rng.uniform(0, 2.5), rng.choice(("block.stone.break", "block.gravel.break")), 6, rng.uniform(0.6, 1.1))

    # ---- particles in the world (nothing is painted flat on the screen) ----
    shard = "minecraft:blackstone" if plasma else "minecraft:calcite"
    at(T + 0.05, f'particle minecraft:block{{block_state:"{shard}"}} {tx} {ty + 1} {tz} 3 1 3 2.2 700 force')
    at(T + 0.1, f'particle minecraft:block{{block_state:"minecraft:stone"}} {tx} {ty + 1} {tz} 5 1 5 1.6 500 force')
    if plasma:
        for i in range(18):
            at(T + 0.3 + i * 0.5, f"particle minecraft:electric_spark {tx} {ty + 3} {tz} 5 6 5 0.8 70 force")
    if godly:
        for i in range(8):                                     # light gathering on the ground while it charges
            at(0.3 + i * 0.45, f"particle minecraft:end_rod {tx} {ty + 0.5} {tz} {6 - i * 0.6:.1f} 0.1 {6 - i * 0.6:.1f} 0.01 14 force")
        for i in range(22):                                    # motes rising out of the crater, ash-white flecks drifting down
            at(T + 0.4 + i * 0.6, f"particle minecraft:end_rod {tx} {ty + 2} {tz} 9 2 9 0.06 45 force")
            if i % 2 == 0:
                at(T + 0.6 + i * 0.6, f"particle minecraft:white_ash {tx} {ty + 30} {tz} 24 18 24 0 260 force")

    def rects(r, rough=0.0):
        """A rough circle as a few rectangles (x0, z0, x1, z1): consecutive rows share one /fill."""
        out = []
        rows = list(range(-r, r + 1))
        groups = min(len(rows), 3 + round(r * 0.6))
        for g in range(groups):
            chunk = rows[g * len(rows) // groups:(g + 1) * len(rows) // groups]
            if not chunk:
                continue
            hw = sum(math.sqrt(max(r * r - dz * dz, 0)) for dz in chunk) / len(chunk)
            hw = int(hw * (1.0 + rng.uniform(-rough, rough)) + 0.5)
            out.append((bx - hw, bz + chunk[0], bx + hw, bz + chunk[-1]))
        return out

    def fills(rs, y_lo, y_hi, block="minecraft:air", replace=None, grow=0):
        suffix = f" replace {replace}" if replace else ""
        return [f"fill {x0 - grow} {y_lo} {z0 - grow} {x1 + grow} {y_hi} {z1 + grow} {block}{suffix}" for x0, z0, x1, z1 in rs]

    def disc(r, y_lo, y_hi, block="minecraft:air", rough=0.0, replace=None):
        return fills(rects(r, rough), y_lo, y_hi, block, replace)

    prim = theme.lining[0][0]
    natural = ("#minecraft:base_stone_overworld", "#minecraft:dirt", "#minecraft:sand", "minecraft:gravel", "minecraft:clay",
               "#minecraft:terracotta", "minecraft:blackstone", "minecraft:smooth_basalt", "minecraft:smooth_quartz", "minecraft:calcite",
               "#minecraft:coal_ores", "#minecraft:iron_ores", "#minecraft:copper_ores")

    def mottle(r, y_lo, y_hi, t, n):
        """Patches of the theme's other lining blocks over the fused wall at radius r."""
        blocks, weights = zip(*theme.lining[1:])
        for _ in range(n):
            a = rng.uniform(0, math.tau)
            x, z = bx + round(math.cos(a) * (r + 1)), bz + round(math.sin(a) * (r + 1))
            s = rng.choice((1, 1, 2))
            blk = rng.choices(blocks, weights)[0]
            at(t + 0.05, f"fill {x - s} {y_lo - 1} {z - s} {x + s} {y_hi} {z + s} {blk} replace {prim}")

    def dig(r, y_lo, y_hi, t, rough, grow):
        """Fuse the ground round a disc into the theme's lining (walls and the ledge under them), then dig the disc out."""
        rs = rects(r, rough)
        for tag in natural:
            for c in fills(rs, y_lo - 1, y_hi, prim, tag, grow):
                at(t - 0.05, c)
        for c in fills(rs, y_lo, y_hi):
            at(t, c)

    if terrain:
        R = args.radius or theme.shaft_r                  # shaft radius at the mouth
        dim = jctl("state").get("dimension", "minecraft:overworld")
        bedrock_top = {"minecraft:overworld": -59, "minecraft:the_nether": 5}.get(dim, 1)   # one block above the bedrock layer
        floor_y = max(by - args.depth, bedrock_top) if args.depth > 0 else bedrock_top
        # 1. the blast: everything standing above the ground in a wide disc is vaporised
        for c in disc(44, by + 1, by + 60, rough=0.12):
            at(T + 0.15, c)
        # 2. scorched earth: what the ground around the crater turns into
        for (rad, block, rgh, repl) in theme.scorch:
            for c in disc(rad, by - 3, by + 1, block, rgh, repl):
                at(T + 0.4 + rng.random() * 2.2, c)
        # 3. the bowl: a rough paraboloid crater, outer layers first, its walls fused as it goes
        bowl_r, bowl_d = theme.bowl_r, theme.bowl_d
        for d in range(0, bowl_d, 2):
            r = max(3, int(bowl_r * math.sqrt(1 - d / (bowl_d + 0.5))))
            t = T + 0.5 + d * 0.28
            dig(r, by - d - 1, by - d, t, theme.bowl_rough, 2)
            mottle(r, by - d - 1, by - d, t, 16)
            for _ in range(3):
                sound(t + rng.uniform(0, 0.25), rng.choice(("block.stone.break", "block.gravel.break", "block.grass.break")), 9, rng.uniform(0.55, 0.9))
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
            dig(r, max(y_hi - 3, floor_y), y_hi, t, theme.shaft_rough, 1)
            mottle(r, max(y_hi - 3, floor_y), y_hi, t, 3)
            sound(t, "block.deepslate.break" if y_hi < 0 else "block.stone.break", 8, rng.uniform(0.5, 0.8))
            if i % 2 == 0:
                sound(t + 0.1, "block.gravel.break", 6, rng.uniform(0.6, 0.9))
            at(t, theme.particle_a.format(x=bx + 0.5, y=by + 1, z=bz + 0.5, r=round(r * 0.6, 1)))
            at(t, theme.particle_b.format(x=bx + 0.5, y=y_hi, z=bz + 0.5, r=round(r * 0.4, 1)))
        # 5. the bottom of the shaft
        tb = T + 9.6
        for k, (rad, lo, hi, block) in enumerate(theme.bottom):
            for c in disc(rad, floor_y + lo, floor_y + hi, block):
                at(tb + 0.1 * k, c)
        if plasma:
            plasma_aftermath(at, sound, rng, bx, by, bz, theme, R)
        if godly:
            godly_aftermath(at, rng, bx, by, bz, theme)
    if godly:
        at(T + 1.0, f"execute positioned {tx} {ty} {tz} run effect give @a[distance=..60] minecraft:regeneration 15 1 true")
        at(T + 1.0, f"execute positioned {tx} {ty} {tz} run effect give @a[distance=..60] minecraft:absorption 30 1 true")
    # wipe out every living thing near the impact (players are spared); a few passes catch anything wandering in
    for tk in (0.15, 0.9, 2.5, 5.0, 8.0):
        at(T + tk, f"execute positioned {tx} {ty} {tz} run kill @e[type=!minecraft:player,distance=..{KILL_RADIUS}]")
    events.sort(key=lambda e: e[0])
    events = batch_events(events)
    if args.timeline:
        Path(args.timeline).write_text(json.dumps({"theme": theme.key, "target": [tx, ty, tz], "fire": T, "length": 26.0,
                                                   "sounds": sorted(sound_log, key=lambda e: e["t"])}, indent=1))

    # keep the chat clean: no "Successfully filled..." / "Played sound..." lines while the strike runs
    if not DAEMON_QUIET:
        cmd("execute as @s run gamerule minecraft:send_command_feedback false")   # forked: no "already set" chatter
        time.sleep(0.15)
    try:
        # a fresh seed per strike: palette, surges, lightning and sway all differ every time. The wings face whoever fired.
        me = (jctl("state").get("player") or {}).get("position") or [tx + 1, ty, tz]
        setopt(target_x=tx, target_y=ty, target_z=tz, anchor_x=bx + 0.5, anchor_z=bz + 0.5,
               wing_a=math.atan2(me[2] - tz, me[0] - tx), freeze_time=-1.0, swz=3.0 if args.capture else 0.0,
               seed=random.randint(1, 999), theme=theme.index)
        t0 = time.time() + RELOAD_LAG
        for t, c in events:
            delay = t0 + t - time.time()
            if delay > 0:
                time.sleep(delay)
            cmd("execute as @s at @s run " + c)   # forked execute: failures like "No blocks were filled" stay out of chat
        drain()                                  # block until the game has executed every queued command
        time.sleep(max(0.0, t0 + 25.0 - time.time()))
    finally:
        setopt(freeze_time=100.0, swz=3.0 if args.capture else 0.0)  # idle again (a recording keeps capture mode on)
        if not DAEMON_QUIET:
            cmd("gamerule minecraft:send_command_feedback true")                  # back to vanilla's default
            time.sleep(0.2)
        drain()


def batch_events(events):
    """Fold the commands that fall in the same tenth of a second into one datapack function, so a few hundred block
    changes land in one tick instead of trickling in at the ~45 a second horizon-ctl can push one by one. The functions
    go in a small datapack in the world's own folder; without one (a server, say) the commands go one by one."""
    world = jctl("state").get("world")
    home = find_home()
    if not world or not home or not (home / "saves" / world / "level.dat").is_file():
        return events
    pack = home / "saves" / world / "datapacks" / "orbital-laser"
    fdir = pack / "data" / "orbital" / "function" / "strike"
    shutil.rmtree(fdir, ignore_errors=True)
    fdir.mkdir(parents=True)
    (pack / "pack.mcmeta").write_text('{"pack": {"description": "Orbital Laser: the current strike, in tenths of a second '
                                      '(strike.py rewrites this)", "min_format": 121, "max_format": 999}}\n')
    buckets = {}
    for t, c in events:
        buckets.setdefault(round(t * 10), []).append(c)
    out = []
    for b, cs in sorted(buckets.items()):
        if len(cs) == 1:
            out.append((b / 10, cs[0]))
        else:
            (fdir / f"b{b}.mcfunction").write_text("\n".join(cs) + "\n")
            out.append((b / 10, f"function orbital:strike/b{b}"))
    ctl("command", "reload")
    time.sleep(0.3)
    return out


def plasma_aftermath(at, sound, rng, bx, by, bz, theme, R):
    """Molten pools on the crater floor that cool to obsidian, fires round the rim, and rubble landing far and wide."""
    T, bowl_r, bowl_d = FIRE, theme.bowl_r, theme.bowl_d
    for k in range(8):
        a, rr = rng.uniform(0, math.tau), rng.uniform(R + 3, bowl_r - 6)
        x, z = bx + round(math.cos(a) * rr), bz + round(math.sin(a) * rr)
        for blk in ("minecraft:obsidian", "minecraft:magma_block", "minecraft:black_stained_glass"):
            at(T + 4.6 + k * 0.2, surf(x, z, f"fill ~-1 ~-1 ~-1 ~1 ~-1 ~1 minecraft:lava replace {blk}"))
    at(T + 5.0, surf(bx, bz, "playsound minecraft:block.lava.ambient block @a ~ ~ ~ 3 0.6"))
    span = bowl_r + 3
    for y0 in range(by - bowl_d - 2, by + 2, 5):              # the pools crust over (a fill is capped at 32768 blocks)
        at(T + 19.0, f"fill {bx - span} {y0} {bz - span} {bx + span} {min(y0 + 4, by + 1)} {bz + span} minecraft:obsidian replace minecraft:lava")
    at(T + 19.0, surf(bx, bz, "playsound minecraft:block.fire.extinguish block @a ~ ~ ~ 3 0.7"))
    for k in range(36):                                       # fires catch on the scorched rim, well clear of anything that burns
        a, rr = rng.uniform(0, math.tau), rng.uniform(bowl_r + 1, 39)
        at(T + 2.0 + rng.uniform(0, 3.0), surf(bx + round(math.cos(a) * rr), bz + round(math.sin(a) * rr), "setblock ~ ~ ~ minecraft:fire keep"))
    rubble = ("minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:blackstone", "minecraft:gravel",
              "minecraft:magma_block", "minecraft:obsidian", "minecraft:basalt", "minecraft:cobblestone")
    for k in range(80):                                       # rock thrown out by the blast comes down across the land around
        a, rr = rng.uniform(0, math.tau), 38 + 60 * rng.random() ** 1.6
        x, z = bx + round(math.cos(a) * rr), bz + round(math.sin(a) * rr)
        t = FIRE + 1.0 + rr / 95.0 * 4.5 + rng.uniform(0, 1.0)
        blk = rng.choice(rubble)
        at(t, surf(x, z, f"setblock ~ ~ ~ {blk} keep"))
        if rng.random() < 0.45:
            at(t + 0.05, surf(x + rng.choice((-1, 0, 1)), z + rng.choice((-1, 0, 1)), f"setblock ~ ~ ~ {rng.choice(rubble)} keep"))
        at(t, surf(x, z, f'particle minecraft:block{{block_state:"{blk}"}} ~ ~0.5 ~ 0.5 0.4 0.5 0.2 18 force'))
        if k % 3 == 0:
            at(t, surf(x, z, f"playsound minecraft:block.basalt.break block @a ~ ~ ~ 2.5 {rng.uniform(0.5, 0.8):.2f}"))


def godly_aftermath(at, rng, bx, by, bz, theme):
    """A golden sigil etched into the ground, six quartz pillars where the light came down, a wave of flowers blooming
    outwards, and chunks of the ground left hanging in the air above the crater."""
    T, bowl_r = FIRE, theme.bowl_r
    R1, R2 = bowl_r + 3, GODLY_PILLAR_R
    gold = "setblock ~ ~-1 ~ minecraft:gold_block"
    verts = [(bx + 0.5 + math.cos(GODLY_PILLAR_A0 + k * math.pi / 3) * R2, bz + 0.5 + math.sin(GODLY_PILLAR_A0 + k * math.pi / 3) * R2)
             for k in range(6)]
    done = {(math.floor(x), math.floor(z)) for x, z in verts}   # the pillars' own columns are left alone

    def etch(x, z, t):
        if (x, z) not in done:
            done.add((x, z))
            at(t, surf(x, z, gold))

    for R_, t0 in ((R1, 1.6), (R2, 2.4)):                     # two rings, burned in as a sweep round the crater
        n = int(math.tau * R_ * 1.3)
        for i in range(n):
            a = i / n * math.tau
            etch(bx + round(math.cos(a) * R_), bz + round(math.sin(a) * R_), T + t0 + 2.4 * i / n)
    for k in range(6):                                        # a hexagram: two triangles joining alternate pillars
        (x0, z0), (x1, z1) = verts[k], verts[(k + 2) % 6]
        n = int(math.dist((x0, z0), (x1, z1)) * 1.2)
        for i in range(n + 1):
            u = i / n
            etch(math.floor(x0 + (x1 - x0) * u), math.floor(z0 + (z1 - z0) * u), T + 4.6 + 2.6 * u)
    for k, (x, z) in enumerate(verts):                        # the pillars stand where the shader's pillars of light come down
        x, z = math.floor(x), math.floor(z)
        t = T + 0.45 + 0.25 * k
        at(t, surf(x, z, "fill ~ ~ ~ ~ ~9 ~ minecraft:quartz_pillar"))
        at(t + 0.1, surf(x, z, "setblock ~ ~ ~ minecraft:sea_lantern"))
        at(t + 0.15, surf(x, z, "setblock ~ ~ ~ minecraft:end_rod"))
        at(t, surf(x, z, "playsound minecraft:block.amethyst_block.resonate block @a ~ ~ ~ 3 0.6"))
    flowers = ("minecraft:oxeye_daisy", "minecraft:lily_of_the_valley", "minecraft:azure_bluet", "minecraft:white_tulip",
               "minecraft:dandelion", "minecraft:oxeye_daisy", "minecraft:short_grass")
    for k in range(320):                                      # a wave of flowers running out across the grass
        a, rr = rng.uniform(0, math.tau), 45 + 55 * math.sqrt(rng.random())
        x, z = bx + round(math.cos(a) * rr), bz + round(math.sin(a) * rr)
        t = T + 2.5 + (rr - 45) / 55 * 8.0 + rng.uniform(0, 0.4)
        at(t, surf(x, z, f"execute if block ~ ~-1 ~ minecraft:grass_block run setblock ~ ~ ~ {rng.choice(flowers)} keep"))
        if k % 5 == 0:
            at(t, surf(x, z, "particle minecraft:wax_on ~ ~0.6 ~ 0.4 0.3 0.4 0 4 force"))
    for k in range(6):                                        # rock torn up by the light, left hanging above the crater
        a, rr = k * math.tau / 6 + rng.uniform(-0.4, 0.4), rng.uniform(11, bowl_r - 2)
        x, z = bx + round(math.cos(a) * rr), bz + round(math.sin(a) * rr)
        y = by + rng.randint(15, 30)
        s = rng.choice((2, 2, 3))
        t = T + 5.5 + k * 0.45
        at(t, f"fill {x - s} {y} {z - s} {x + s} {y} {z + s} minecraft:grass_block")
        for cx, cz in ((x - s, z - s), (x - s, z + s), (x + s, z - s), (x + s, z + s)):
            at(t, f"setblock {cx} {y} {cz} minecraft:air")
        at(t, f"fill {x - s + 1} {y - 1} {z - s + 1} {x + s - 1} {y - 1} {z + s - 1} minecraft:dirt")
        at(t, f"fill {x - max(s - 2, 0)} {y - 2} {z - max(s - 2, 0)} {x + max(s - 2, 0)} {y - 2} {z + max(s - 2, 0)} minecraft:calcite")
        at(t, f"setblock {x} {y - 3} {z} minecraft:gold_block")
        at(t, f"setblock {x + rng.choice((-1, 1))} {y + 1} {z} {rng.choice(flowers)}")
        at(t, f"particle minecraft:end_rod {x} {y} {z} {s} 1 {s} 0.08 40 force")
        at(t, f"playsound minecraft:block.amethyst_block.chime block @a {x} {y} {z} 3 0.7")


# ---------------------------------------------------------------------------------------------
def item_kind(st):
    """'designator', 'remote' or None for the held item."""
    held = st.get("held") or {}
    item, comp = held.get("item"), str(held.get("components", ""))
    if item == "minecraft:spyglass":
        if NAME in comp:
            return "designator"
        if REMOTE_NAME in comp:
            return "remote"
    return None


def tool_item(model, real):
    """The item the designator and remote are made of. Horizon's mod items can't be used (right-click does nothing:
    an item file only sets template, stack size and rarity), so both are spyglasses; with the mod installed they wear
    its model, so they look like the real thing and still report a use the daemon can see."""
    return f'minecraft:spyglass[item_model="{model}",' if real else "minecraft:spyglass[enchantment_glint_override=true,"


def set_remote_name(slot, theme, real):
    """Rename the remote in its slot to show the current laser (the slot is 0 to 8, left to right)."""
    name = f"{REMOTE_NAME} - {theme.title}"
    cmd(f'execute as @s run item replace entity @s hotbar.{slot} with {tool_item(ITEM_REMOTE, real)}'
        f'custom_name={{text:"{name}",color:"{theme.color}",bold:true}}]')


def lore_lines(text, width=38):
    out, line = [], ""
    for w in text.split():
        if line and len(line) + 1 + len(w) > width:
            out.append(line)
            line = w
        else:
            line = f"{line} {w}".strip()
    return out + [line] if line else out


def menu_item(item, name, color, lore=(), model=None, glint=False, hide=False):
    """An item for the remote's menu as (id, components), tagged so every copy can be cleared off the player afterwards."""
    esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"')
    c = {"custom_name": f'{{text:"{esc(name)}",color:"{color}",bold:true,italic:false}}', "custom_data": "{orbital_menu:1b}"}
    if lore:
        c["lore"] = "[" + ",".join(f'{{text:"{esc(l)}",color:"{lc}",italic:false}}' for l, lc in lore) + "]"
    if model:
        c["item_model"] = f'"{model}"'
    if glint:
        c["enchantment_glint_override"] = "true"
    if hide:
        c["tooltip_display"] = "{hide_tooltip:true}"
    return item, c


def stack_arg(it):
    """minecraft:paper[custom_name=...,...], as /item and /give take it."""
    return f"{it[0]}[{','.join(f'{k}={v}' for k, v in it[1].items())}]"


def stack_nbt(it, slot):
    """{Slot:3b,id:...,count:1,components:{...}}, as a container's Items list holds it."""
    comps = ",".join(f'"minecraft:{k}":{v}' for k, v in it[1].items())
    return f'{{Slot:{slot}b,id:"{it[0]}",count:1,components:{{{comps}}}}}'


def open_menu(st, theme, terrain, real):
    """The remote's menu: a barrel slipped in under the player's feet and opened for them, holding one icon per laser and
    the terrain switch. Click an icon to pick that laser. Returns (theme, terrain); the barrel and the ground it
    replaced are put back, and so is the view."""
    p = st.get("player") or {}
    if "block_pos" not in p or "eye" not in p:
        return theme, terrain
    x, y, z = p["block_pos"]
    sy = y - 1
    hy = MENU_STASH_Y.get(st.get("dimension"), 254)
    yaw, pitch = math.radians(p["yaw"]), math.radians(p["pitch"])
    ex, ey, ez = p["eye"]
    look = (ex - math.sin(yaw) * math.cos(pitch) * 10, ey - math.sin(pitch) * 10, ez + math.cos(yaw) * math.cos(pitch) * 10)
    pane = menu_item("minecraft:black_stained_glass_pane", " ", "black", hide=True)

    def put(slot, item):
        cmd(f"item replace block {x} {sy} {z} container.{slot} with {stack_arg(item)}")

    def contents():
        items = {n: pane for n in range(27)}
        items.update({MENU_SLOTS[t.key]: icon(t) for t in THEMES})
        items[MENU_TERRAIN_SLOT] = switch()
        return "[" + ",".join(stack_nbt(it, n) for n, it in sorted(items.items())) + "]"

    def icon(t):
        lore = ([("Selected", "green")] if t is theme else [("Click to select", "dark_gray")]) + [(l, "gray") for l in lore_lines(t.blurb)]
        if real:
            return menu_item("minecraft:paper", t.title, t.color, lore, model=t.icon_model, glint=t is theme)
        return menu_item(MENU_FALLBACK_ICON[t.key], t.title, t.color, lore, glint=t is theme)

    def switch():
        if terrain:
            return menu_item("minecraft:grass_block", "Terrain damage: ON", "green",
                             [("The crater, shaft and aftermath are real", "gray"), ("and permanent. Click to turn off.", "gray")])
        return menu_item("minecraft:barrier", "Terrain damage: OFF", "red",
                         [("Light and sound only: the ground is", "gray"), ("left alone. Click to turn on.", "gray")])

    def paint():
        for t in THEMES:
            put(MENU_SLOTS[t.key], icon(t))
        put(MENU_TERRAIN_SLOT, switch())
        drain()

    q = lambda c: ctl("command", c)
    q(f"clone {x} {sy} {z} {x} {sy} {z} {x} {hy} {z}")          # keep the ground the barrel stands in for
    q(f"setblock {x} {sy} {z} minecraft:barrel[facing=up]{{Items:{contents()}}}")
    chosen = None
    try:
        r = jctl("interact", str(x), str(sy), str(z))
        if "busy" in str(r.get("error", "")):                          # horizon-ctl was mid-action (a scripted click)
            ctl("stop")
            r = jctl("interact", str(x), str(sy), str(z))
        if "error" in r:
            actionbar("MOVE A LITTLE: NOWHERE TO OPEN THE REMOTE HERE", "gray")
            return theme, terrain
        cmd("playsound minecraft:ui.button.click master @s ~ ~ ~ 0.6 1.4")
        seen = False                                                    # the screen takes a moment to open
        start = time.time()
        while time.time() < start + 120:
            m = jctl("menu")
            box = {s["slot"] - 300: s["stack"] for s in m.get("slots", []) if s.get("slot", 0) >= 300}
            if not box:
                if seen or time.time() > start + 2.0:
                    break                                               # closed without choosing
                time.sleep(0.05)
                continue
            seen = True
            full = lambda n: (box.get(n) or {}).get("item") not in (None, "minecraft:air")
            chosen = next((t for t in THEMES if not full(MENU_SLOTS[t.key])), None)
            if chosen:
                break
            if not full(MENU_TERRAIN_SLOT):
                terrain = not terrain
                cmd("clear @s *[minecraft:custom_data={orbital_menu:1b}]")
                cmd(f"playsound minecraft:ui.button.click master @s ~ ~ ~ 0.6 {1.6 if terrain else 1.0}")
                paint()
                continue
            empty = [n for n in range(27) if not full(n)]
            if empty:                                                   # a pane was picked up: put it back
                cmd("clear @s *[minecraft:custom_data={orbital_menu:1b}]")
                for n in empty:
                    put(n, pane)
                drain()
            time.sleep(0.05)
    finally:
        ctl("close")
        q("clear @s *[minecraft:custom_data={orbital_menu:1b}]")
        q(f"setblock {x} {sy} {z} minecraft:air")
        q(f"clone {x} {hy} {z} {x} {hy} {z} {x} {sy} {z}")
        q(f"setblock {x} {hy} {z} minecraft:air")
        for _ in range(15):                                             # refused until the screen has finished closing
            if jctl("look-at", *(f"{v:.2f}" for v in look)).get("ok"):
                break
            time.sleep(0.08)
    if chosen:
        theme = chosen
        actionbar(f"{theme.title} LOADED", theme.color)
        cmd("playsound minecraft:block.beacon.activate master @s ~ ~ ~ 0.5 1.6")
    return theme, terrain


if args.daemon:
    import atexit, signal
    theme = BY_KEY[args.theme]
    terrain = not args.no_terrain
    # is the content mod there to dress the items in? (this has to be asked before command feedback is switched off)
    probe = ctl("command", f"item replace entity @s hotbar.8 with {ITEM_DESIGNATOR}")
    real = "Unknown item" not in probe
    DAEMON_QUIET = True
    cmd("execute as @s run gamerule minecraft:send_command_feedback false")   # nothing the designator does may show in chat
    time.sleep(0.2)
    atexit.register(lambda: ctl("command", "gamerule minecraft:send_command_feedback true"))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    cmd(f'execute as @s run item replace entity @s hotbar.8 with {tool_item(ITEM_DESIGNATOR, real)}'
        f'custom_name={{text:"{NAME}",color:"red",bold:true}}]')
    set_remote_name(7, theme, real)
    ctl("select", "9")
    print(f"{NAME} is in your last hotbar slot and the {REMOTE_NAME} next to it "
          f"({'with the mod textures' if real else 'plain spyglasses: install the mod for the real textures'}).")
    print(f"Laser: {theme.key}. Hold the designator and look through it to fire; right-click the remote to pick the laser.")
    print("Ctrl-C to stop.", flush=True)
    armed = True
    while True:
        st = jctl("state")
        using = st.get("using")
        kind = item_kind(st)
        if not using:
            armed = True
        elif armed and kind == "remote":
            armed = False                                   # one menu per click: wait for the button to come up again
            before = theme
            theme, terrain = open_menu(st, theme, terrain, real)
            set_remote_name(using.get("slot", 7), theme, real)
            print(f"laser: {theme.key}{'' if theme is before else ' (changed)'}, terrain {'on' if terrain else 'off'}", flush=True)
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
                    run_strike(bx, by, bz, px, py, pz, theme, terrain)
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
