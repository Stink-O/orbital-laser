"""Regenerate the Orbital Laser sound effects (orbital-sounds/assets/orbital/sounds/*.ogg).

Every sound is synthesized from scratch (band-limited noise, pitched sweeps, convolution reverb built from a
synthetic impulse response): no samples, nothing to license. Needs numpy and ffmpeg (with libvorbis).

    python3 tools/synth_sounds.py [OUT_DIR]      # default: ../orbital-sounds
"""
import json, os, subprocess, sys, wave
from pathlib import Path
import numpy as np

SR = 44100
rng = np.random.default_rng(20261021)
OUT = sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).resolve().parent.parent / "orbital-sounds")
os.makedirs(OUT + "/assets/orbital/sounds", exist_ok=True)


def tt(d):
    return np.arange(int(SR * d)) / SR


def white(d):
    return rng.standard_normal(int(SR * d))


def band(x, lo=None, hi=None, order=2):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if lo:
        g = g / (1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    if hi:
        g = g / (1 + (f / hi) ** (2 * order))
    return np.fft.irfft(X * g, len(x))


def smooth_noise(d, rate, n=None):
    """slowly varying random curve in [-1,1], `rate` new values per second"""
    n = n or int(SR * d)
    pts = rng.uniform(-1, 1, int(d * rate) + 3)
    xs = np.linspace(0, len(pts) - 1, n)
    i = np.floor(xs).astype(int)
    f = xs - i
    f = f * f * (3 - 2 * f)
    return pts[i] * (1 - f) + pts[np.minimum(i + 1, len(pts) - 1)] * f


def exp_env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay)


def make_ir(length=3.5, tau_lo=1.8, tau_mid=0.9, tau_hi=0.35):
    n = int(SR * length)
    t = np.arange(n) / SR
    base = rng.standard_normal(n)
    ir = (band(base, None, 400) * np.exp(-t / tau_lo) * 1.0
          + band(base, 400, 2500) * np.exp(-t / tau_mid) * 0.7
          + band(base, 2500, 9000) * np.exp(-t / tau_hi) * 0.4)
    ir[: int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(x, wet=0.4, **kw):
    ir = make_ir(**kw)
    n = len(x) + len(ir)
    y = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    y = y[: len(x) + int(len(ir) * 0.6)]
    out = np.zeros(len(y))
    out[: len(x)] += x
    return out * (1 - wet * 0.5) + y * wet * 3.0


def soft(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def thump(n, t0, f0=70, f1=24, decay=0.25, rate=9):
    t = np.arange(n) / SR - t0
    m = t >= 0
    f = f1 + (f0 - f1) * np.exp(-np.maximum(t, 0) * rate)
    ph = 2 * np.pi * np.cumsum(f * m) / SR
    return np.sin(ph) * np.exp(-np.maximum(t, 0) / decay) * m


def click(n, t0, amp=1.0, lo=1500, hi=9000, decay=0.006):
    t = np.arange(n) / SR - t0
    m = t >= 0
    seg = rng.standard_normal(n)
    seg = band(seg, lo, hi)
    return seg * np.exp(-np.maximum(t, 0) / decay) * m * amp


def ring(n, t0, freqs, decay=0.3, amp=0.2):
    t = np.arange(n) / SR - t0
    m = t >= 0
    out = np.zeros(n)
    for k, f in enumerate(freqs):
        out += np.sin(2 * np.pi * f * t * m + k) * np.exp(-np.maximum(t, 0) / (decay / (1 + 0.4 * k))) * m
    return out * amp


def finish(name, x, tail_fade=0.05):
    x = x - np.mean(x)
    x = soft(x / (np.percentile(np.abs(x), 99.5) + 1e-9) * 0.8, 1.15)
    nf = int(tail_fade * SR)
    x[-nf:] *= np.linspace(1, 0, nf)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.97
    path = f"{OUT}/assets/orbital/sounds/{name}"
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path + ".wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path + ".wav", "-c:a", "libvorbis", "-q:a", "7", path + ".ogg"], check=True)
    os.remove(path + ".wav")
    print(f"wrote {name:9s} {len(x) / SR:5.2f}s  rms {np.sqrt(np.mean(x ** 2)):.3f}")


# ------------------------------------------------------------------------------------------ charge
d = 4.0; n = int(SR * d); t = tt(d); p = t / d
f0 = 38 + 640 * p ** 2.2                                   # a turbine spooling up
phase = 2 * np.pi * np.cumsum(f0 * (1 + 0.012 * smooth_noise(d, 30))) / SR
saw = 2 * ((phase / (2 * np.pi)) % 1) - 1
saw = band(saw, 30, None) * 0.9
cut = 120 + 5200 * p ** 1.6
turb = np.zeros(n)
for lo_f in (150, 400, 1000, 2500):                        # cutoff follows the rpm: brighter as it climbs
    gate = np.clip((cut - lo_f) / lo_f, 0, 1)
    turb += band(saw, lo_f * 0.5, lo_f * 2.0) * gate
air = band(white(d), 350, 4500) * (0.1 + 1.6 * p ** 2.4) * (1 + 0.25 * smooth_noise(d, 14))
rise = band(white(d), 2500, 10000) * np.clip((p - 0.55) / 0.45, 0, 1) ** 2 * 1.2
sub = np.sin(2 * np.pi * np.cumsum(28 + 20 * p) / SR) * p ** 1.8 * 1.5
x = (turb * (0.2 + 1.2 * p) + air + rise + sub) * np.minimum(t / 0.25, 1.0)
x[-int(0.04 * SR):] *= np.linspace(1, 0.3, int(0.04 * SR))
finish("charge", reverb(x, 0.22, length=2.0, tau_lo=0.9, tau_mid=0.5, tau_hi=0.2))

# ------------------------------------------------------------------------------------------ lock-on: a heavy mechanical latch
d = 0.9; n = int(SR * d)
x = (thump(n, 0.0, 95, 40, 0.12, 14) * 1.4 + click(n, 0.0, 1.0, 1800, 9000, 0.005)
     + click(n, 0.115, 0.55, 1200, 7000, 0.004) + thump(n, 0.115, 160, 70, 0.05, 30) * 0.5
     + ring(n, 0.0, (880, 1930, 3170, 4980), 0.35, 0.16)
     + band(white(d), 3000, 11000) * exp_env(n, 0.001, 0.05) * 0.25)
finish("lockon", reverb(x, 0.3, length=1.2, tau_lo=0.5, tau_mid=0.3, tau_hi=0.15))

# ------------------------------------------------------------------------------------------ fire: the impact
d = 6.5; n = int(SR * d); t = tt(d)
crack = band(white(d), 600, 14000) * exp_env(n, 0.0004, 0.012) * 2.0 + band(white(d), 100, 1200) * exp_env(n, 0.0006, 0.06) * 1.3
boom = thump(n, 0.0, 85, 26, 1.0, 3.6) * 1.8 + thump(n, 0.012, 55, 22, 0.8, 2.4) * 1.1
blast = band(white(d), 60, 900) * exp_env(n, 0.003, 0.55) * 1.6
air = band(white(d), 400, 6000) * exp_env(n, 0.002, 0.16) * 1.0
roll = band(white(d), 18, 220, 3) * exp_env(n, 0.25, 1.9) * (1 + 0.8 * smooth_noise(d, 5)) * 2.6
x = crack + boom + blast + air + roll
for delay, g, hi in ((0.55, 0.45, 900), (1.25, 0.35, 600), (2.2, 0.25, 420), (3.4, 0.16, 300)):   # thunder echoing off the terrain
    dn = int(delay * SR)
    echo = np.zeros(n)
    echo[dn:] = band(x, 25, hi)[: n - dn] * g
    x = x + echo
for _ in range(110):                                       # debris raining back down
    ti = rng.uniform(0.35, 5.6)
    x += click(n, ti, rng.uniform(0.04, 0.22) * np.exp(-ti / 3.0), 300, rng.uniform(1500, 5500), rng.uniform(0.004, 0.02))
finish("fire", reverb(soft(x, 1.4), 0.5, length=3.8, tau_lo=2.2, tau_mid=1.1, tau_hi=0.4), 0.3)

# ------------------------------------------------------------------------------------------ beam: a plasma roar
d = 4.0; n = int(SR * d); t = tt(d)
def lane(lo, hi, rate, depth, amp):
    return band(white(d), lo, hi) * (1 + depth * smooth_noise(d, rate)) * amp
roar = (lane(35, 160, 2.2, 0.45, 1.7) + lane(160, 700, 3.5, 0.5, 1.5) + lane(700, 2800, 5.5, 0.55, 0.9)
        + lane(2800, 9500, 8.0, 0.7, 0.28))
jit = 1 + 0.014 * smooth_noise(d, 18)
buzz = sum(np.sin(2 * np.pi * np.cumsum(50 * h * jit) / SR + h) / h ** 1.3 for h in (1, 2, 3, 5, 7)) * 0.13
swirl = band(white(d), 300, 1500) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.37 * t + 1.2)) * 0.5
ticks = np.zeros(n)
for _ in range(70):
    ticks += click(n, rng.uniform(0, d - 0.1), rng.uniform(0.1, 0.5), 1800, rng.uniform(5000, 11000), rng.uniform(0.002, 0.01))
x = soft(roar + buzz + swirl + ticks, 1.3)
x *= np.minimum(np.minimum(t / 0.35, (d - t) / 0.35), 1.0)
finish("beam", reverb(x, 0.18, length=1.6, tau_lo=0.8, tau_mid=0.4, tau_hi=0.2), 0.01)

# ------------------------------------------------------------------------------------------ rumble: the ground shaking
d = 3.4; n = int(SR * d); t = tt(d)
g = band(white(d), 12, 85, 3) * (1 + 0.7 * smooth_noise(d, 3)) * 3.0 + band(white(d), 90, 520) * 0.5 * (1 + smooth_noise(d, 6))
for _ in range(16):
    g += thump(n, rng.uniform(0, d - 0.5), rng.uniform(45, 70), rng.uniform(20, 28), rng.uniform(0.15, 0.4), 6) * rng.uniform(0.2, 0.7)
x = g * np.minimum(np.minimum(t / 0.5, (d - t) / 1.0), 1.0)
finish("rumble", reverb(x, 0.25, length=2.2, tau_lo=1.2, tau_mid=0.6, tau_hi=0.2), 0.02)

# ------------------------------------------------------------------------------------------ crackle: electrical discharge
d = 1.8; n = int(SR * d)
x = click(n, 0.02, 2.2, 1200, 12000, 0.012) + click(n, 0.02, 1.0, 120, 900, 0.05)
for k in range(34):
    ti = 0.04 + abs(rng.normal(0, 0.28))
    x += click(n, ti, rng.uniform(0.15, 0.9) * np.exp(-ti * 1.6), rng.uniform(900, 3000), rng.uniform(4500, 12000), rng.uniform(0.0015, 0.014))
x += band(white(d), 40, 260, 3) * exp_env(n, 0.01, 0.6) * 0.9
finish("crackle", reverb(x, 0.35, length=2.2, tau_lo=1.0, tau_mid=0.5, tau_hi=0.25), 0.1)

# ------------------------------------------------------------------------------------------ collapse: rock giving way
d = 3.4; n = int(SR * d); t = tt(d)
x = band(white(d), 90, 1800) * exp_env(n, 0.05, 1.1) * (1 + 0.8 * smooth_noise(d, 9)) * 0.7
for tm in (0.0, 0.3, 0.75, 1.3, 2.0):
    x += thump(n, tm, rng.uniform(60, 90), 24, rng.uniform(0.18, 0.4), 6) * rng.uniform(0.7, 1.3)
for _ in range(140):
    ti = rng.uniform(0.05, 2.8)
    x += click(n, ti, rng.uniform(0.05, 0.4) * np.exp(-ti / 1.6), rng.uniform(150, 900), rng.uniform(1200, 4200), rng.uniform(0.01, 0.05))
finish("collapse", reverb(x, 0.4, length=2.8, tau_lo=1.4, tau_mid=0.7, tau_hi=0.3), 0.1)

# ------------------------------------------------------------------------------------------ shutdown: the machine spooling down, metal ticking as it cools
d = 3.2; n = int(SR * d); t = tt(d); p = t / d
f0 = 20 + 480 * np.exp(-t * 1.9)
phase = 2 * np.pi * np.cumsum(f0 * (1 + 0.01 * smooth_noise(d, 25))) / SR
saw = band(2 * ((phase / (2 * np.pi)) % 1) - 1, 25, 3000)
x = saw * np.exp(-t * 1.4) * 1.2 + band(white(d), 200, 3500) * np.exp(-t * 1.8) * 0.9 + thump(n, 0.0, 70, 24, 0.5, 4) * 0.9
tk = 0.35
while tk < d - 0.2:                                        # cooling metal: ticks slow down as it settles
    x += (click(n, tk, 0.4, 1400, 6000, 0.004) + ring(n, tk, (rng.uniform(1100, 2900), rng.uniform(3100, 5200)), 0.12, 0.35))
    tk += 0.12 + (tk ** 1.6) * 0.14 + rng.uniform(0, 0.08)
finish("shutdown", reverb(x, 0.3, length=2.0, tau_lo=1.0, tau_mid=0.5, tau_hi=0.2), 0.1)

names = ["charge", "lockon", "fire", "beam", "rumble", "crackle", "collapse", "shutdown"]
json.dump({n: {"sounds": [f"orbital:{n}"], "subtitle": f"subtitles.orbital.{n}"} for n in names}, open(OUT + "/assets/orbital/sounds.json", "w"), indent=2)
json.dump({"pack": {"description": "Orbital laser sound design", "min_format": 84, "max_format": 99, "pack_format": 84}}, open(OUT + "/pack.mcmeta", "w"), indent=2)
