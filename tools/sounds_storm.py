"""The Supercell's sounds, all synthesised here from noise, pulses, resonators and filters (nothing sampled).

  buildup     the storm forming (0 is the strike's start): the wind rising out of a hush in gusts, a thin whistle in
              it, a sub rumble swelling under it, two rolls of thunder far off
  gusts       the storm's wind (14 s, faded in and out over 1.8 s, so the plan's beds overlap into one): gusting,
              buffeting from side to side
  rain        the rain bed (12 s, faded in and out over 1.5 s): a dense hiss, a patter of drops near, a low drumming
  rumble      thunder from a flicker in the cloud, far off (3 variants): a soft, long, dark roll
  crack       a bolt's thunder close by (3 variants; 0 is when it reaches the player): a sharp ripping crack, a tearing
              burst of snaps, then a heavy boom (real low end: a falling sine body with its harmonics) rolling on in
              swells; noise only as texture over it
  crack_far   a bolt's thunder from further off (3 variants): no rip, a dull crack, a deeper, longer roll
  finale      the colossal strike: a long rip, a huge snap, three blows of sub, a sizzle, a roll dying over ten seconds
  roar        a funnel's roar (4 variants, mono, played where the funnel is every second, 2.6 s each faded in and out,
              so they overlap into one that moves with it): a deep turbulent roar, a whooshing middle

Vanilla's own thunder is stopped as each bolt plays it (strike/storm.rs): it is a full-scale boom (0 dBFS, nothing
over 6 kHz) that would bury these or clip with them. The files' levels are set against each other so the whole
strike's mix (as the plan plays them, tools' listening mix: `--listen`) peaks at or under -1 dBFS.

    python3 tools/sounds_storm.py                # writes orbital-sounds/assets/orbital/sounds/supercell/*.ogg and adds
                                                 # the events to sounds.json, leaving every other sound as it is
    python3 tools/sounds_storm.py --listen DIR   # and the WAV and MP3 of each, and the strike's mix as heard 60 and 300
                                                 # blocks off, in DIR (and its peak)
"""
import argparse, json, os, shutil, subprocess, sys, wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundlib
from soundlib import SR, white, band, smooth_noise

TH = "supercell"
ROOT = Path(__file__).resolve().parent.parent
VARIANTS = {"rumble": 3, "crack": 3, "crack_far": 3, "roar": 4}
NAMES = ["buildup", "gusts", "rain", "rumble", "crack", "crack_far", "finale", "roar"]
# Each file's peak (of full scale): set so the strike's mix stays under -1 dBFS (`--listen` checks it).
LEVEL = {"buildup": 0.42, "gusts": 0.18, "rain": 0.13, "rumble": 0.2, "crack": 0.5, "crack_far": 0.36, "finale": 0.72, "roar": 0.22}
LISTEN = None
rng = np.random.default_rng(20261101)


def n_of(d):
    return int(SR * d)


def fades(x, a, b):
    """Raised-cosine fade in over `a` s and out over `b` s."""
    n = len(x)
    e = np.ones(n)
    na, nb = n_of(a), n_of(b)
    if na:
        e[:na] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, na))
    if nb:
        e[-nb:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, nb))
    return x * e


def boom(n, t0, f0, f1, decay, rate, attack=0.004):
    """A falling sine body (the low end you feel) with its own harmonics (so small speakers carry it)."""
    t = np.arange(n) / SR - t0
    m = t >= 0
    tp = np.maximum(t, 0)
    f = f1 + (f0 - f1) * np.exp(-tp * rate)
    ph = 2 * np.pi * np.cumsum(f * m) / SR
    env = np.minimum(tp / attack, 1.0) * np.exp(-tp / decay) * m
    return (np.sin(ph) + 0.3 * np.sin(2 * ph + 0.4) + 0.12 * np.sin(3 * ph + 1.1)) * env


def rip(n, t0, length, count, lo=1800, hi=12000, big=1.0):
    """The ripping crack: a burst of snaps, denser and harder towards its end, then one big snap."""
    out = np.zeros(n)
    seg = n_of(0.03)
    for k in range(count):
        u = (k / max(count - 1, 1)) ** 0.7
        tk = t0 + length * u + rng.uniform(-0.004, 0.004)
        i = n_of(max(tk, 0))
        if i + seg >= n:
            continue
        s = band(rng.standard_normal(seg), lo * rng.uniform(0.7, 1.2), hi)
        s *= np.exp(-np.arange(seg) / SR / rng.uniform(0.0015, 0.004))
        out[i:i + seg] += s * rng.uniform(0.25, 0.7) * (0.4 + 0.6 * u)
    i = n_of(t0 + length)
    seg = n_of(0.08)
    s = band(rng.standard_normal(seg), 600, 14000) * np.exp(-np.arange(seg) / SR / 0.012)
    out[i:i + seg] += s * 1.6 * big
    return out


def roll(d, swells, lo, hi, t0=0.2, spread=3.5, width=(0.35, 0.9)):
    """Thunder's roll: low noise in swells, each further off and smaller."""
    n = n_of(d)
    t = np.arange(n) / SR
    env = np.zeros(n)
    for k in range(swells):
        tk = t0 + spread * (k / max(swells - 1, 1)) ** 1.3 + rng.uniform(-0.15, 0.15)
        w = rng.uniform(*width) * (1 + 0.4 * k)
        a = (0.85 ** k) * rng.uniform(0.6, 1.0)
        env += a * np.exp(-0.5 * ((t - tk) / w) ** 2) * (t > tk - 2 * w)
    env *= 0.7 + 0.3 * (smooth_noise(d, 9, n) * 0.5 + 0.5)
    return band(white(d), lo, hi, 2) * env


def write(name, x, level):
    """Normalised to `level` of full scale at its peak; stereo when x is a pair. The .ogg into the mod's sounds, and a
    WAV and MP3 for listening."""
    if isinstance(x, tuple):
        nmax = max(len(x[0]), len(x[1]))
        y = np.zeros((nmax, 2))
        y[: len(x[0]), 0] = x[0]
        y[: len(x[1]), 1] = x[1]
    else:
        y = x[:, None].copy()
    y -= y.mean(axis=0)
    nf = n_of(0.03)
    y[-nf:] *= np.linspace(1, 0, nf)[:, None]
    y = y / (np.max(np.abs(y)) + 1e-9) * level
    path = f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{name}"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = (np.clip(y, -1, 1) * 32767).astype("<i2")
    with wave.open(path + ".wav", "wb") as w:
        w.setnchannels(y.shape[1]); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path + ".wav", "-c:a", "libvorbis", "-q:a", "5", path + ".ogg"], check=True)
    if LISTEN:
        os.makedirs(LISTEN, exist_ok=True)
        shutil.move(path + ".wav", f"{LISTEN}/{name}.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f"{LISTEN}/{name}.wav", "-b:a", "192k", f"{LISTEN}/{name}.mp3"], check=True)
    else:
        os.remove(path + ".wav")
    print(f"wrote {TH}/{name:12s} {len(y) / SR:5.2f}s  {'stereo' if y.shape[1] == 2 else 'mono  '}  peak {20 * np.log10(level):5.1f} dBFS")


def stereo(f):
    """The same sound built twice (its noise different in each ear), a little wide."""
    a, b = f(), f()
    m = 0.5 * (a + b)
    return m + 0.6 * (a - m), m + 0.6 * (b - m)


def wind(d, rise=False):
    n = n_of(d)
    t = np.arange(n) / SR
    gust = np.clip(0.55 + 0.45 * smooth_noise(d, 0.7, n) + 0.25 * smooth_noise(d, 2.3, n), 0.08, 1.3)
    body = band(white(d), 140, 1400, 2) * gust
    hi = band(white(d), 1200, 5000, 2) * gust ** 2 * 0.25
    # (a thin whistle in it, wandering)
    whis = band(white(d), 620, 700, 4) * np.clip(smooth_noise(d, 0.4, n), 0, 1) * gust * 1.4
    low = band(white(d), 30, 140, 2) * (0.6 + 0.4 * smooth_noise(d, 0.5, n)) * 0.8
    x = body + hi + whis + low
    if rise:
        x *= np.clip(t / d, 0, 1) ** 1.3
    return x


def build_buildup():
    d = 12.0
    def one():
        n = n_of(d)
        t = np.arange(n) / SR
        x = wind(d, rise=True)
        x += band(white(d), 22, 85, 2) * (t / d) ** 1.6 * 2.2
        for t0, a in [(5.4, 0.6), (9.6, 1.0)]:
            r = roll(d - t0, 4, 25, 320, t0=0.3, spread=2.2) * a * 1.2
            x[n_of(t0):] += r[: n - n_of(t0)]
        return fades(x, 0.4, 0.8)
    write("buildup", stereo(one), LEVEL["buildup"])


def build_gusts():
    d = 14.0
    write("gusts", stereo(lambda: fades(wind(d), 1.8, 1.8)), LEVEL["gusts"])


def build_rain():
    d = 12.0
    def one():
        n = n_of(d)
        hiss = band(white(d), 900, 9000, 2) * 0.55
        drops = np.zeros(n)
        idx = rng.integers(0, n - 200, int(d * 900))
        drops[idx] = rng.uniform(-1, 1, len(idx)) * rng.uniform(0.2, 1.0, len(idx)) ** 2
        ker = np.exp(-np.arange(n_of(0.004)) / SR / 0.0009)
        drops = band(np.convolve(drops, ker)[:n], 1800, 8000, 2) * 2.5
        drum = band(white(d), 140, 700, 2) * (0.75 + 0.25 * smooth_noise(d, 1.5, n)) * 0.35
        return fades(hiss + drops + drum, 1.5, 1.5)
    write("rain", stereo(one), LEVEL["rain"])


def build_rumble(v):
    d = 6.0
    def one():
        n = n_of(d)
        x = roll(d, 5, 22, 280, t0=0.5, spread=3.2, width=(0.5, 1.1)) * 1.4
        x += boom(n, 0.4, 52, 30, 1.6, 2.5, attack=0.25) * 0.6
        x += roll(d, 3, 250, 700, t0=0.6, spread=2.5) * 0.12
        return fades(x, 0.3, 0.8)
    write(f"rumble{v}", stereo(one), LEVEL["rumble"])


def build_crack(v):
    d = 5.5
    def one():
        n = n_of(d)
        x = rip(n, 0.0, 0.1 + 0.05 * v, 26 + 6 * v) * 1.0
        x += boom(n, 0.05, 92 - 8 * v, 33, 0.85, 5.0) * 1.0
        x += boom(n, 0.13, 64, 29, 1.3, 3.0, attack=0.02) * 0.55
        x += roll(d, 6, 28, 240, t0=0.35, spread=3.0) * 0.75
        x += roll(d, 4, 250, 1600, t0=0.25, spread=1.5, width=(0.15, 0.4)) * 0.18
        return fades(x, 0.0, 0.6)
    l, r = stereo(one)
    write(f"crack{v}", soundlib.reverb_st(0.5 * (l + r), wet=0.3, length=2.5, tau_lo=1.3, tau_mid=0.6, tau_hi=0.2), LEVEL["crack"])


def build_crack_far(v):
    d = 6.5
    def one():
        n = n_of(d)
        x = rip(n, 0.02, 0.06, 8, lo=400, hi=2200, big=0.35) * 0.35
        x += boom(n, 0.05, 62, 28, 1.6, 3.0, attack=0.04) * 0.9
        x += roll(d, 7, 22, 300, t0=0.4, spread=4.0, width=(0.4, 1.0)) * 1.0
        return fades(x, 0.0, 0.8)
    l, r = stereo(one)
    write(f"crack_far{v}", soundlib.reverb_st(0.5 * (l + r), wet=0.35, length=3.0, tau_lo=1.6, tau_mid=0.7, tau_hi=0.2), LEVEL["crack_far"])


def build_finale():
    d = 12.0
    def one():
        n = n_of(d)
        t = np.arange(n) / SR
        x = rip(n, 0.0, 0.28, 70, big=1.6) * 1.0
        x += boom(n, 0.02, 105, 30, 1.8, 4.0) * 1.0
        x += boom(n, 0.12, 72, 27, 2.2, 3.0, attack=0.01) * 0.7
        x += boom(n, 0.5, 55, 24, 2.6, 2.0, attack=0.05) * 0.5
        x += band(white(d), 400, 3500, 2) * np.exp(-t / 0.45) * (t > 0.05) * 0.35
        x += roll(d, 8, 22, 260, t0=0.5, spread=6.5, width=(0.5, 1.2)) * 1.0
        x += roll(d, 5, 260, 1500, t0=0.4, spread=3.0, width=(0.2, 0.5)) * 0.15
        return fades(x, 0.0, 1.5)
    l, r = stereo(one)
    write("finale", soundlib.reverb_st(0.5 * (l + r), wet=0.42, length=4.0, tau_lo=2.2, tau_mid=1.0, tau_hi=0.3), LEVEL["finale"])


def build_roar(v):
    d = 2.6
    n = n_of(d)
    t = np.arange(n) / SR
    turb = 1 + 0.35 * smooth_noise(d, 11, n) + 0.2 * smooth_noise(d, 3, n)
    x = band(white(d), 35, 330, 2) * turb * 1.3
    x += band(white(d), 300, 1300, 2) * (0.6 + 0.4 * smooth_noise(d, 1.6, n)) * 0.4
    f = 48 + 6 * smooth_noise(d, 2, n)
    x += np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.25 * turb
    # (a hann window: the plan's overlapping copies, a second apart, sum to a near-steady roar)
    x *= np.sin(np.pi * t / d) ** 2
    write(f"roar{v}", x, LEVEL["roar"])


def listen_mix(z, out):
    """The strike's sounds as a player `z` blocks off hears them (their times and volumes from the plan), mixed."""
    tl = Path(out) / f"timeline_{z}.txt"
    subprocess.run(["cargo", "test", "--release", "--quiet", "--lib", "sc_write_sounds", "--", "--ignored"], cwd=ROOT / "mod",
                   env=dict(os.environ, SC_OUT=str(tl.resolve()), SC_ME=str(z)), check=True, capture_output=True)
    d = 70.0
    mix = np.zeros((n_of(d), 2))
    count = {}
    for line in tl.read_text().splitlines():
        t, ev, vol = line.split()
        name = ev.split(".", 1)[1]
        k = count.get(name, 0)
        count[name] = k + 1
        f = f"{out}/{name}{k % VARIANTS[name] + 1}.wav" if name in VARIANTS else f"{out}/{name}.wav"
        with wave.open(f) as w:
            y = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float).reshape(-1, w.getnchannels()) / 32768
        if y.shape[1] == 1:
            y = np.repeat(y, 2, axis=1) * 0.75
        i = n_of(float(t))
        m = min(len(y), len(mix) - i)
        if m > 0:
            mix[i:i + m] += y[:m] * min(float(vol), 1.0)
    peak = np.max(np.abs(mix))
    pcm = (np.clip(mix, -1, 1) * 32767).astype("<i2")
    path = f"{out}/storm_mix_{z}"
    with wave.open(path + ".wav", "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path + ".wav", "-b:a", "192k", path + ".mp3"], check=True)
    print(f"mix {z} blocks off: peak {20 * np.log10(peak):.2f} dBFS -> {path}.wav")
    return peak


BUILD = {
    "buildup": build_buildup, "gusts": build_gusts, "rain": build_rain,
    "rumble": lambda: [build_rumble(v) for v in (1, 2, 3)],
    "crack": lambda: [build_crack(v) for v in (1, 2, 3)],
    "crack_far": lambda: [build_crack_far(v) for v in (1, 2, 3)],
    "finale": build_finale,
    "roar": lambda: [build_roar(v) for v in (1, 2, 3, 4)],
}


def main():
    global LISTEN
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also the WAV and MP3 of each, and the strike's mix, in this folder")
    a = ap.parse_args()
    soundlib.init(a.out)
    LISTEN = a.listen
    for name in a.only or NAMES:
        BUILD[name]()
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    if path.exists():
        sounds = json.loads(path.read_text())
        for name in NAMES:
            ev = f"{TH}.{name}"
            files = [f"orbital:{TH}/{name}{v + 1}" for v in range(VARIANTS[name])] if name in VARIANTS else [f"orbital:{TH}/{name}"]
            # (the roar is heard where the funnel is, out to 320 blocks; the rest follow the player)
            dist = 320 if name == "roar" else 256
            sounds[ev] = {"sounds": [{"name": f, "attenuation_distance": dist} for f in files], "subtitle": f"subtitles.orbital.{ev}"}
        path.write_text(json.dumps(sounds, indent=2))
    if LISTEN and not a.only:
        for z in (60, 300):
            listen_mix(z, LISTEN)


if __name__ == "__main__":
    main()
