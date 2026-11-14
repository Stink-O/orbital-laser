#!/usr/bin/env python3
"""The World Eater's sounds: a stone worm 68 blocks across and some 1,800 long, out of the deep dark.

All synthesized here, new for this laser (no other laser's files or sound models; soundlib's .ogg plumbing is not even
needed). One creature, one family of models:

  * the earth's own resonances: low modes of the ground (a few damped sines, 20-90 Hz) struck by a shaped push of force,
    never a swept "boom" sine;
  * moving mass: noise through a bank of slowly drifting low resonances (the rock and the earth round it groaning as it
    goes), its gain surging slowly ring by ring (peristalsis), never chopped fast;
  * air shoved by something 68 blocks wide: noise whose spectrum is shaped frame by frame (its centre sliding as it
    passes), no flutter, no crack;
  * its voice: four different models of a vast stone tube sounding (see `bellow_*`).

Every file is mono: the game sums a stereo file to mono as it loads it (horizon-client audio.rs), so width would only
cost level and comb. Files are written at fixed levels relative to each other (the bite the loudest), so the plan's
volumes are distance only.

    python3 tools/sounds_worldeater.py                 # every file under orbital-sounds/assets/orbital/sounds/worldeater/
    python3 tools/sounds_worldeater.py --measure       # the measurements (bands, onsets, flutter, ringing, dips)
    python3 tools/sounds_worldeater.py --review DIR    # the review: each piece and take, and the 250 / 800 block mixdowns
"""
import json
import os
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "orbital-sounds" / "assets" / "orbital" / "sounds" / "worldeater"

# ---- the strike's beats (mod/src/strike/we_path.rs; keep in step) ----------------------------------------------------
WE_BREACH = 9.0
WE_BELLOW = (12.5, 14.5)
WE_BITE = 19.0
WE_TAIL_OUT = 27.0
WE_TAIL_IN = 31.0
WE_SINK = (31.0, 40.0)
WE_LEN_S = 46.0
WE_SPAN = 260.0
WE_SIGN = 420.0
WE_APEX = 250.0

# ---- where each file's beat is in it (the plan cues a file this much before its beat): keep we_sounds.rs in step ------
SIGN_PEAK = 9.0        # sign: the breach, this far into it
SIGN_SHORT_PEAK = 4.5  # sign_short: the next surfacing
DIVE_HIT = 5.5         # dive: the bite
HIT_AT = 0.10          # breach*, bite*, sink*, quake*, tail_in: their blow
BELLOW_LEAD = 0.45     # bellow_*: the jaws open this long after the file starts
TAIL_AT = 0.35         # tail_out: the whip's apex
GULP_SHUT = 0.85       # gulp: shut
SPIT_AT = 0.25         # spit: thrown out

V_AIR = 343.0
V_GROUND = 5.0 * 343.0


# ======================================================================================================================
# plumbing
# ======================================================================================================================
def R(seed):
    return np.random.default_rng(seed)


def N(d):
    return int(round(d * SR))


def tt(n):
    return np.arange(n) / SR


def unit(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


def bp(x, lo=None, hi=None, order=4):
    """Zero-phase band-pass (Butterworth, forward and back)."""
    if lo and hi:
        sos = signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos")
    elif lo:
        sos = signal.butter(order, lo, "highpass", fs=SR, output="sos")
    else:
        sos = signal.butter(order, hi, "lowpass", fs=SR, output="sos")
    return signal.sosfiltfilt(sos, x)


def lowcut(x, f=19.0):
    """Causal: what no speaker plays (and DC) out, the onsets left as they are."""
    return signal.sosfilt(signal.butter(2, f, "highpass", fs=SR, output="sos"), x)


def slow(rng, n, rate, smooth=True):
    """A slowly wandering curve in about [-1, 1], `rate` new points a second (smoothstep between them)."""
    k = int(n / SR * rate) + 4
    pts = rng.uniform(-1, 1, k)
    xs = np.linspace(0, k - 3, n)
    i = np.floor(xs).astype(int)
    f = xs - i
    if smooth:
        f = f * f * (3 - 2 * f)
    return pts[i] * (1 - f) + pts[i + 1] * f


def ss(u):
    u = np.clip(u, 0, 1)
    return u * u * (3 - 2 * u)


def shaped(n, rng, mag, frame=8192, hop=2048, loop=False):
    """Noise shaped frame by frame: `mag(tc, f)` the magnitude over the frequencies `f` at the frame's middle `tc`
    (seconds). Random phase each frame, Hann overlap-add (so it stays smooth: no frame rate in it). `loop` wraps it
    round so the file loops seamlessly."""
    f = np.fft.rfftfreq(frame, 1 / SR)
    win = np.hanning(frame)
    if loop:
        # (frames laid round a circle of n samples: n a whole number of hops)
        out = np.zeros(n)
        k = max(1, round(n / hop))
        for start in (np.arange(k) * n // k):
            tc = ((start + frame / 2) % n) / SR
            z = (rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))) * mag(tc, f)
            seg = np.fft.irfft(z, frame) * win
            idx = (start + np.arange(frame)) % n
            np.add.at(out, idx, seg)
        return out
    out = np.zeros(n + 2 * frame)
    for start in range(-frame, n, hop):
        tc = (start + frame / 2) / SR
        m = mag(min(max(tc, 0.0), n / SR), f)
        z = (rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))) * m
        seg = np.fft.irfft(z, frame) * win
        a = start + frame
        out[a:a + frame] += seg
    return out[frame:frame + n]


def peaks(f, centres, widths, gains):
    """A spectrum of Lorentzian peaks (resonances) over the frequencies `f`."""
    g = np.zeros_like(f)
    for c, w, a in zip(centres, widths, gains):
        g += a / (1 + ((f - c) / (w / 2)) ** 2)
    return g


def tilt(f, ref, db_oct):
    return (np.maximum(f, 1.0) / ref) ** (db_oct / 6.02)


def floor_cut(f, lo, hi=None, order=2):
    g = 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    if hi:
        g = g / np.sqrt(1 + (f / hi) ** (2 * order))
    return g


def modes(n, t0, freqs, taus, amps, force_len, rng=None, phase_rand=True):
    """The ground (or a body) struck at t0: damped modes each rung by a smooth push of force `force_len` s long (a
    raised cosine): a thud with a rounded front, its weight in the modes, never a click or a falling sine."""
    t = tt(n)
    out = np.zeros(n)
    fl = max(N(force_len), 8)
    force = np.hanning(2 * fl)[:2 * fl]
    force = force / force.sum()
    for f0, tau, a in zip(freqs, taus, amps):
        ph = rng.uniform(0, 2 * np.pi) if (rng is not None and phase_rand) else 0.0
        u = t - t0
        ir = np.where(u >= 0, np.sin(2 * np.pi * f0 * u + ph) * np.exp(-np.maximum(u, 0) / tau), 0.0)
        out += a * signal.fftconvolve(ir, force)[:n]
    return out


def weight(x, lo=28, hi=110, amount=0.6):
    """Harmonics of the lows (2nd to 5th, 80-450 Hz) bent out of them, so their weight lands in the 100-800 Hz body
    too and carries on small speakers: an asymmetric soft bend of the low band only."""
    low = bp(x, lo, hi, 2)
    s = np.sqrt(np.mean(low ** 2)) * 3 + 1e-12
    v = low / s
    bent = np.tanh(1.6 * v) - 0.9 * v + 0.35 * (v * v) / (1 + 0.5 * v * v)
    bent = bp(bent, 75, 480, 2)
    return x + amount * bent * s


def space(x, rng, length=3.0, lo_tau=1.1, mid_tau=0.55, hi_tau=0.18, early=(), wet=0.35, pre=0.02):
    """A space round it: a decaying noise tail (the lows ringing longest) plus a few distinct early returns
    (`early`: (delay s, gain, low-pass Hz) the land, cliffs or the tube's far wall). Mono."""
    n = N(length)
    t = tt(n)
    z = rng.standard_normal(n)
    ir = (bp(z, None, 300, 2) * np.exp(-t / lo_tau) + bp(z, 300, 2000, 2) * np.exp(-t / mid_tau) * 0.6
          + bp(z, 2000, None, 2) * np.exp(-t / hi_tau) * 0.3)
    ir *= ss(t / 0.06)
    ir = np.concatenate([np.zeros(N(pre)), ir])
    ir /= np.sqrt(np.sum(ir ** 2))
    y = signal.fftconvolve(x, ir)
    for dly, g, lp in early:
        e = bp(x, None, lp, 2) * g
        k = N(dly)
        y[k:k + len(e)] += e[: len(y) - k]
    out = np.zeros(len(y))
    out[: len(x)] += x
    return out + wet * y


def distant(x, d, rng, echoes=True):
    """The same heard `d` blocks off: the air takes the top (roughly ISO 9613 at 20 C, 70 %: ~5 dB/km at 1 kHz, ~30 at
    4 kHz, ~100 at 8 kHz), fronts soften (the ground and air smear them), the land answers late."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    km = d / 1000.0
    a_db = km * (0.6 * (f / 1000) + 4.4 * (f / 1000) ** 2) * 1.0
    a_db = np.minimum(a_db, 80)
    # (a little dip where the ground's reflection cancels the direct sound over soft land)
    a_db += 4.0 * np.exp(-0.5 * (np.log2(np.maximum(f, 1) / 450) / 0.6) ** 2)
    y = np.fft.irfft(X * 10 ** (-a_db / 20), n)
    # (fronts smeared over ~15-40 ms: the turbulence and the many paths)
    sm = np.hanning(N(0.012 + 0.03 * min(km, 1.2)))
    sm /= sm.sum()
    y = 0.5 * y + 0.5 * signal.fftconvolve(y, sm)[: n]
    if echoes:
        ear = [(0.35 + 0.5 * km, 0.38, 900), (0.8 + 0.9 * km, 0.3, 600), (1.5 + 1.2 * km, 0.22, 450),
               (2.4 + 1.4 * km, 0.14, 350)]
        y = space(y, rng, length=4.5, lo_tau=1.6, mid_tau=0.8, hi_tau=0.2,
                  early=[(a * rng.uniform(0.85, 1.15), g, lp) for a, g, lp in ear], wet=0.45, pre=0.05)
    return y


def no_dip(x, until, w=0.3, most_db=6.0):
    """A build that must never dip: wherever its level (a `w` s window) sags under what it has already reached before
    `until` s, it is lifted back (at most `most_db`), smoothly. Noise this low wanders by a few dB on its own; this
    takes those sags out without touching the climb."""
    e = 20 * np.log10(env_rms(x, w) + 1e-12)
    k = N(until)
    want = e.copy()
    want[:k] = np.maximum.accumulate(e[:k])
    g = np.clip(want - e, 0, most_db)
    g[k:] = g[k - 1] * np.exp(-np.arange(len(g) - k) / N(0.15)) if k < len(g) else g[k:]
    sm = np.hanning(N(0.12))
    g = signal.fftconvolve(g, sm / sm.sum(), "same")
    return x * 10 ** (g / 20)


def pk(x):
    """Scaled so its loudest 50 ms is 1: so a mix's gains are its parts' peak levels."""
    return x / (env_rms(x, 0.05).max() + 1e-12)


def drive(x, over_db=9.0):
    """The loudest instants (over `over_db` above the loudest 400 ms) driven softly round, as a close mic overloaded
    by a blow: denser, never squashed flat."""
    c = st_rms(x).max() * 10 ** (over_db / 20)
    return np.tanh(x / c) * c


def st_rms(x, w=0.4):
    k = N(w)
    c = np.cumsum(np.r_[0.0, x ** 2])
    return np.sqrt(np.maximum((c[k:] - c[:-k]) / k, 1e-20))


def level(x, max_st_db, ceiling=-0.8):
    """Scaled so its loudest 400 ms is at `max_st_db` dBFS, its loudest instants bent softly under `ceiling`."""
    x = x - np.mean(x)
    x = x * 10 ** (max_st_db / 20) / (st_rms(x).max() + 1e-12)
    c = 10 ** (ceiling / 20)
    knee = 0.7 * c
    a = np.abs(x)
    y = np.where(a > knee, np.sign(x) * (knee + (c - knee) * np.tanh((a - knee) / (c - knee))), x)
    return y


def fade(x, a=0.0, b=0.3):
    x = x.copy()
    if a:
        k = N(a)
        x[:k] *= np.linspace(0, 1, k) ** 2
    if b:
        k = N(b)
        x[-k:] *= np.linspace(1, 0, k) ** 2
    return x


def write_ogg(path, x, q=6):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    tmp = str(path) + ".wav"
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q), "-fflags", "+bitexact", "-flags:a", "+bitexact", "-serial_offset", "1", str(path)], check=True)
    os.remove(tmp)


def load(path, channels=1):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", str(path), "-f", "f32le", "-ac", str(channels), "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


# ======================================================================================================================
# the creature's building blocks
# ======================================================================================================================
def mass(n, rng, lo=35, hi=420, count=14, drift=0.12, rise=0.0, q=6.0, loop=False, surge=None):
    """Moving mass: noise through a bank of low resonances (the rock and the earth round it), each drifting slowly (by
    `drift` of itself, `rise` octaves over the length gliding them all up), so it groans and moves without a single
    grain or click. `surge(t)` scales it over time (smooth)."""
    cs = np.exp(rng.uniform(np.log(lo), np.log(hi), count))
    gs = rng.uniform(0.4, 1.0, count) * (cs / lo) ** -0.35
    ph = rng.uniform(0, 100, count)
    rates = rng.uniform(0.08, 0.35, count)
    dur = n / SR

    def mag(tc, f):
        u = tc / dur
        c = cs * 2 ** (rise * u) * (1 + drift * np.sin(2 * np.pi * rates * tc + ph))
        w = c / q
        m = peaks(f, c, w, gs) + 0.08 * floor_cut(f, lo * 0.7, hi * 1.3, 2)
        return m * (1.0 if surge is None else surge(tc))

    return unit(shaped(n, rng, mag, loop=loop))


def air(n, rng, centre, width_oct=2.2, lo=25, loop=False, gain=None):
    """Air shoved aside: noise in a broad smooth hump round `centre(t)` Hz (log-Gaussian, `width_oct` wide), its low
    side kept (the push), no flutter: the hump's level and centre glide only as fast as the frames."""
    dur = n / SR

    def mag(tc, f):
        c = centre(tc)
        lf = np.log2(np.maximum(f, 1.0) / c)
        m = np.exp(-0.5 * (lf / (width_oct / 2.355)) ** 2) + 0.25 * np.exp(-0.5 * (lf / (width_oct * 1.2)) ** 2) * (f < c)
        m *= floor_cut(f, lo, None, 2)
        return m * (1.0 if gain is None else gain(tc))

    return unit(shaped(n, rng, mag, loop=loop))


def earth_pour(n, rng, t0, length, lo=40, hi=650):
    """Earth sliding and pouring off something huge: a smooth, dark sliding rush, its colour sinking as the heaviest
    goes last; no patter (no grains: shaped noise only, its gain wandering at under 2 Hz)."""
    dur = n / SR

    def mag(tc, f):
        u = (tc - t0) / length
        if u < 0:
            return np.zeros_like(f)
        top = hi * 2 ** (-1.2 * min(u, 1.0))
        return floor_cut(f, lo, top, 2) * tilt(f, 100, -2.0) * np.exp(-max(u, 0) * 1.6) * min(u / 0.08, 1.0)

    x = unit(shaped(n, rng, mag)) if dur > 0 else np.zeros(n)
    return x * (1 + 0.35 * slow(rng, n, 1.6))


def pressure(n, t0, rise, fall, f=22.0, rng=None):
    """A slow swell of pressure (the infrasonic push the body feels): a 15-35 Hz band of noise under a smooth
    envelope (not a sine: no pitch, just the room moving)."""
    t = tt(n)
    u = t - t0
    env = np.where(u < 0, np.exp(-0.5 * (u / rise) ** 2), np.exp(-u / fall))
    z = bp(rng.standard_normal(n), f * 0.65, f * 1.6, 2)
    return unit(z) * env


# ======================================================================================================================
# the wormsign and the movement under the land
# ======================================================================================================================
def sign(seed, length, peak, crack=True):
    """Something enormous coming under the land: felt before heard. Pressure and the earth's deepest groan first, the
    rock grinding (drifting low resonances) rising into the body band as it nears, the rings' surges heaving it, and
    (`crack`) the last 1.5 s the land over it doming and splitting: its groans gliding up, the body thickening into the
    breach at `peak` s. Its level only ever climbs (a 400 ms window never drops more than a fraction of a dB)."""
    rng = R(seed)
    n = N(length)
    t = tt(n)
    u = np.clip(t / peak, 0, 1)
    # (the climb: ~30 dB over its length, steepest at the end; after the peak it carries on under the breach)
    climb_db = -21 + 21 * u ** 1.5
    after = np.clip((t - peak) / (length - peak + 1e-9), 0, 1)
    climb = 10 ** (climb_db / 20) * (1 - 0.6 * after)
    # the surges of its rings shoving the earth (0.45 -> 1.0 a second as it closes, always adding, never cutting)
    rate = 0.45 + 0.55 * u
    ph = 2 * np.pi * np.cumsum(rate) / SR
    surge = 1 + 0.14 * (0.5 + 0.5 * np.sin(ph + rng.uniform(0, 6))) ** 2 * (1 - 0.5 * u)
    sub = unit(bp(rng.standard_normal(n), 18, 48, 2)) * (1 + 0.25 * slow(rng, n, 0.7))
    groan = mass(n, rng, 28, 140, count=10, drift=0.08, rise=0.25 if crack else 0.1, q=5)
    grind = mass(n, rng, 90, 600, count=16, drift=0.06, rise=0.2, q=4)
    # (the body band coming in as it nears: far off only the deepest reaches you through the ground)
    nearer = u ** 1.4
    x = 1.0 * sub + 0.85 * groan + grind * (0.15 + 0.85 * nearer)
    if crack:
        # the land over it doming up and splitting: groans gliding up a fifth in the last 1.5 s, a deep tearing (the
        # earth's own modes, slow) thickening into the burst
        c0 = peak - 1.6
        dome = mass(n, rng, 45, 300, count=8, drift=0.03, rise=0.6, q=9)
        tear = air(n, rng, lambda tc: 90 + 160 * ss((tc - c0) / 1.6), 2.6, 30)
        dm = ss((t - c0) / 1.6) * (1 - after)
        x = x + dome * 1.3 * dm + tear * 0.9 * dm ** 2
    x = x * surge * climb
    x = weight(x, 25, 100, 0.5)
    x = lowcut(space(x, rng, 2.5, 1.4, 0.6, 0.2, wet=0.25)[:n])
    # (its tail after the peak let go under the breach)
    x = x * np.where(t > peak, np.exp(-(t - peak) / 0.45), 1.0)
    x = no_dip(no_dip(x, peak), peak, 0.4)
    return fade(x, 0.0, 0.08)


def move(seed, length=4.0):
    """The mound steering after the player between surfacings: the sign's steady part, as overlapping pieces the plan
    lays end to end (each fades in and out over 1 s), its loudness set by the plan from how near it is."""
    rng = R(seed)
    n = N(length)
    t = tt(n)
    surge = 1 + 0.3 * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(0.55, 0.8) * t + rng.uniform(0, 6))) ** 2
    x = (unit(bp(rng.standard_normal(n), 18, 48, 2)) + 0.85 * mass(n, rng, 28, 140, 10, 0.08, 0.0, 5)
         + 0.5 * mass(n, rng, 90, 600, 14, 0.06, rng.uniform(-0.1, 0.1), 4)) * surge
    x = weight(x, 25, 100, 0.5)
    x = lowcut(space(x, rng, 2.0, 1.2, 0.5, 0.2, wet=0.2)[:n])
    env = ss(t / 1.0) * ss((length - t) / 1.0)
    return x * env


# ======================================================================================================================
# the breach and the quake ahead of it
# ======================================================================================================================
def quake(seed, var=1.0):
    """What comes through the ground first, ahead of the air's blow (five times as fast): a deep shove you feel, the
    land's lowest modes rung softly (front ~40 ms), 18-90 Hz, with just enough 100-250 Hz to be heard on a small
    speaker."""
    rng = R(seed)
    n = N(4.5)
    t = tt(n)
    t0 = HIT_AT
    f = np.array([24.0, 32.0, 43.0, 58.0]) * var
    x = pk(modes(n, t0 - 0.03, f, [0.8, 0.6, 0.45, 0.3], [1.0, 0.9, 0.6, 0.35], 0.07, rng))
    x += 0.4 * pk(pressure(n, t0 + 0.05, 0.05, 0.6, 26, rng))
    # (and the land rumbling on after it, until the air's blow lands on top of it)
    x += 0.4 * pk(mass(n, rng, 20, 110, 8, 0.05, -0.2, 6) * np.where(t > t0, ss((t - t0) / 0.3) * np.exp(-(t - t0) / 1.8), 0))
    x = weight(x, 20, 80, 0.6)
    return fade(lowcut(x), 0, 0.8)


# ======================================================================================================================
# rising, the body pouring, the dive
# ======================================================================================================================
def rise(seed):
    """The worm climbing out, 250 blocks up (9.3-14 s): the stone mass rising (its groans gliding up), the air it
    shoves, earth pouring off it; slowing as it tops out (its movement easing, the pour thinning) but never dropping
    out: it leans into the bellow."""
    rng = R(seed)
    d = 6.0
    n = N(d)
    t = tt(n)
    speed = np.exp(-t / 2.2) * 0.8 + 0.2
    m = mass(n, rng, 30, 380, 14, 0.07, 0.5, 5, surge=lambda tc: 0.7 + 0.3 * np.exp(-tc / 2.2))
    a = air(n, rng, lambda tc: 70 + 60 * np.exp(-tc / 1.8), 2.4, 22)
    pour = earth_pour(n, rng, 0.0, 5.0, 40, 500)
    x = m * 1.0 + a * 0.8 * speed + pour * 0.45
    x = x * (0.75 + 0.25 * ss(t / 0.5))
    x = weight(x, 25, 100, 0.5)
    x = lowcut(space(x, rng, 3.0, 1.4, 0.6, 0.2, wet=0.3)[:n])
    return fade(x, 0.0, 1.0)


def body(seed, length=7.0):
    """The body pouring over through the arch (19-31 s): a deep moving presence 68 blocks wide passing overhead: the
    air it moves in long slow passes (each section's push brightening a little as it nears and darkening as it goes:
    Doppler on a hump of air, ~0.5 a second), the stone mass groaning low under it, the rings' slow surges. Laid
    end to end, overlapping (the plan alternates body1 and body2)."""
    rng = R(seed)
    n = N(length)
    t = tt(n)
    rate = rng.uniform(0.42, 0.55)
    ph0 = rng.uniform(0, 6)
    pass_u = (np.sin(2 * np.pi * rate * t + ph0) + 1) / 2
    cen = lambda tc: 85 * 2 ** (0.9 * ((np.sin(2 * np.pi * rate * tc + ph0) + 1) / 2) - 0.2)
    a = air(n, rng, cen, 2.6, 22, gain=lambda tc: 0.75 + 0.25 * np.sin(2 * np.pi * rate * tc + ph0))
    m = mass(n, rng, 32, 300, 12, 0.1, rng.uniform(-0.15, 0.15), 5)
    hi = air(n, rng, lambda tc: 420 + 120 * np.sin(2 * np.pi * rate * tc + ph0 + 0.6), 1.6, 120)
    x = a * 1.0 + m * 0.8 + hi * 0.18 * (0.6 + 0.4 * pass_u)
    x = weight(x, 25, 100, 0.45)
    x = lowcut(space(x, rng, 3.0, 1.5, 0.6, 0.2, wet=0.3)[:n])
    # (round 9: a long let-go, 3 s: the last piece ending under nothing was a hard edge in the game's recording; laid
    # every ~4.2 s the pieces still cross-fade flat)
    env = ss(t / 1.2) * ss((length - t) / 3.0)
    return x * env


def dive(seed):
    """The arc over and down onto the bite (from the bellow's end, 13.5-19 s), ending on the bite at DIVE_HIT: the air
    in front of the falling head building into a roar (low, rising and opening as it nears), the body's mass rushing,
    the land under it shivering (sub tremor building); ~6 dB of climb (and its colour opening), steepest at the end, never a dip. It starts
    under the bellow's let-go so nothing sags between them."""
    rng = R(seed)
    d = DIVE_HIT + 0.25
    n = N(d)
    t = tt(n)
    u = np.clip(t / DIVE_HIT, 0, 1)
    lv = 10 ** ((-6 + 6 * u ** 1.6) / 20) * ss(t / 0.8)
    a = air(n, rng, lambda tc: 60 * 2 ** (1.6 * (tc / DIVE_HIT) ** 1.5), 2.6, 22)
    m = mass(n, rng, 30, 260, 10, 0.06, 0.4, 5)
    shiver = mass(n, rng, 18, 70, 6, 0.04, 0.2, 8) * u ** 2
    x = (a * 1.0 + m * 0.6 + shiver * 0.8) * lv
    x = weight(x, 25, 100, 0.5)
    x = lowcut(space(x, rng, 2.0, 1.2, 0.5, 0.2, wet=0.2)[:n])
    # (it stops on the bite: the bite's own front takes over)
    x *= np.where(t > DIVE_HIT, np.exp(-(t - DIVE_HIT) / 0.06), 1.0)
    x = np.r_[x[: N(0.8)], no_dip(no_dip(x[N(0.8):], DIVE_HIT - 0.8), DIVE_HIT - 0.8, 0.4)]
    return fade(x, 0, 0.02)


# ======================================================================================================================
# the bite: three takes
# ======================================================================================================================
def bite(take, far=False):
    """The mouth coming down and taking a 90-block bite out of the world: the biggest thing in the strike.

    A, "Hammer": one colossal blow of the ground's lowest modes (60 ms of force), the land going in (a falling rush,
        its colour sinking down the throat), the jaws' closing thud 0.8 s on, a ground wave after.
    B, "Swallow": a smaller first blow, then the land sucked in: a huge inhaling rush building for a second (air and
        earth pulled into the mouth), and the closing thud the peak, the deepest blow in the strike.
    C, "Quake": the blow, then the ground wave as three rolling surges travelling away (each lower and longer),
        the whole land heaving under it; the closing thud lower and buried in it."""
    rng = R({"A": 4101, "B": 4202, "C": 4303}[take] + (50 if far else 0))
    d = 9.0
    n = N(d)
    t = tt(n)
    t0 = HIT_AT
    u = np.maximum(t - t0, 0)
    on = t >= t0
    fg = np.array([24.0, 32.0, 42.0, 55.0, 72.0, 95.0, 125.0])
    tg = np.array([0.8, 0.6, 0.42, 0.3, 0.2, 0.14, 0.1])
    ag = np.array([1.0, 1.0, 0.9, 0.75, 0.6, 0.45, 0.3])

    def blow(at, scale, flen, fmul=1.0, tmul=1.0):
        """A blow of the ground's modes plus its punch (a short 70-300 Hz push in the chest), peak-scaled."""
        m = modes(n, at, fg * fmul * rng.uniform(0.97, 1.03, 7), tg * tmul, ag, flen, rng)
        pz = bp(rng.standard_normal(n), 70 * fmul, 300 * fmul, 2) * np.exp(-0.5 * ((t - at - flen) / (0.6 * flen + 0.012)) ** 2)
        return scale * pk(pk(m) + 0.45 * pk(pz))

    def land_in(at, length, start_hz=900, end_hz=90):
        def mag(tc, ff):
            v = (tc - at) / length
            if v < -0.02:
                return np.zeros_like(ff)
            c = start_hz * (end_hz / start_hz) ** min(max(v, 0) ** 0.7, 1.0)
            return floor_cut(ff, 35, c, 2) * tilt(ff, 100, -1.0) * np.exp(-max(v, 0) * 1.2)
        x = shaped(n, rng, mag, frame=4096, hop=1024)
        return pk(x * np.where(t >= at, 1 - np.exp(-(t - at) / 0.03), 0.0))

    def after(at, tau, rise=0.5):
        return np.where(t > at, np.exp(-(t - at) / tau) * ss((t - at) / rise), 0)

    body = mass(n, rng, 80, 650, 14, 0.04, -0.6, 5)
    if take == "A":
        x = blow(t0 - 0.02, 1.0, 0.03)
        x += 0.5 * pk(body * np.where(on, (1 - np.exp(-u / 0.02)) * np.exp(-u / 0.6), 0))
        x += 0.42 * land_in(t0 + 0.1, 1.6)
        x += blow(t0 + 0.8, 0.8, 0.07, 0.85, 1.2)
        x += 0.35 * pk(mass(n, rng, 22, 120, 8, 0.05, -0.3, 6) * after(t0 + 1.0, 2.0, 0.6))
        x += 0.45 * pk(pressure(n, t0 + 0.05, 0.03, 0.7, 26, rng))
        x += 0.22 * pk(earth_pour(n, rng, t0 + 1.1, 4.5, 35, 500))
    elif take == "B":
        x = blow(t0 - 0.02, 0.55, 0.04, 1.1, 0.8)
        x += 0.3 * pk(body * np.where(on, (1 - np.exp(-u / 0.02)) * np.exp(-u / 0.5), 0))
        # (sucked in: an inhale the size of a hill, rising for a second, its colour falling as the land goes down)
        def suck(tc, ff):
            v = (tc - t0) / 1.15
            if v < 0:
                return np.zeros_like(ff)
            c = 700 * (70 / 700) ** min(v, 1.0)
            g = (min(v, 1.0) ** 1.5) * (np.exp(-(v - 1.0) * 6) if v > 1 else 1.0)
            return floor_cut(ff, 30, c * 1.6, 2) * tilt(ff, 100, -0.5) * g
        x += 0.55 * pk(shaped(n, rng, suck, frame=4096, hop=1024))
        tc = t0 + 1.15
        x += blow(tc - 0.03, 1.0, 0.06, 0.82, 1.4)
        x += 0.5 * pk(pressure(n, tc, 0.1, 0.9, 24, rng))
        x += 0.35 * pk(mass(n, rng, 22, 120, 8, 0.05, -0.3, 6) * after(tc, 2.2, 0.5))
        x += 0.22 * pk(earth_pour(n, rng, tc + 0.3, 4.0, 35, 450))
    else:
        x = blow(t0 - 0.02, 1.0, 0.035, 0.95, 1.0)
        x += 0.45 * pk(body * np.where(on, (1 - np.exp(-u / 0.02)) * np.exp(-u / 0.6), 0))
        x += 0.35 * land_in(t0 + 0.1, 1.2, 700, 80)
        x += blow(t0 + 0.65, 0.55, 0.09, 0.8, 1.3)
        for k, (dt, g, lo, hi) in enumerate([(1.0, 0.55, 22, 160), (2.0, 0.47, 20, 130), (3.2, 0.4, 18, 110)]):
            sg = mass(n, rng, lo, hi, 8, 0.04, -0.2, 6)
            w = 0.7 + 0.35 * k
            x += g * pk(sg * np.exp(-0.5 * ((t - t0 - dt) / (w / 2.2)) ** 2))
        x += 0.45 * pk(pressure(n, t0 + 0.05, 0.04, 1.2, 24, rng))
        x += 0.2 * pk(earth_pour(n, rng, t0 + 1.2, 5.0, 35, 450))
    x = weight(x, 22, 110, 0.85)
    x = drive(x)
    if far:
        x = distant(x, 800, rng)
    else:
        x = space(x, rng, 4.0, 1.6, 0.7, 0.2, early=[(0.5, 0.22, 1000), (1.1, 0.14, 600), (1.9, 0.08, 400)], wet=0.28)
    return fade(lowcut(x[:n]), 0, 1.5)


# ======================================================================================================================
# the bellow: four different models
# ======================================================================================================================
def bellow_env(t, lead=BELLOW_LEAD, hold_end=2.45, rel=1.8):
    """The held beat's shape: a slow swell from the start (the jaws opening at `lead`), the peak through the hold,
    then let go."""
    up = ss(t / (lead + 0.9)) ** 1.3
    down = np.where(t > lead + hold_end, np.exp(-(t - lead - hold_end) / rel), 1.0)
    return (0.15 + 0.85 * up) * down * (0.82 + 0.18 * ss((t - lead) / 1.6))


def contour(t, base, lead=BELLOW_LEAD, up=1.12, droop=0.9):
    """The pitch's arc: rising into the opening, held, sagging as it lets go (slow only: no vibrato)."""
    a = 1 + (up - 1) * ss((t - lead + 0.3) / 1.0)
    b = 1 + (droop - 1) * ss((t - lead - 2.3) / 1.2)
    return base * a * b


def bellow_A(seed=5101):
    """Take A, "Throat": a voice. Source and filter as a throat makes sound: a choir of seven smooth pulse sources
    (its folds) a hair apart in pitch round 31 Hz (so they never buzz as one), each harmonic's level set by the
    throat's formants at that instant (exact source-filter, done additively); the formants rise as the jaws open
    (an "oo" to an "aa" a mountain wide: 120/330/680 Hz to 180/430/820), breath through the same throat under it."""
    rng = R(seed)
    d = 7.5
    n = N(d)
    t = tt(n)
    env = bellow_env(t)
    open_ = ss((t - BELLOW_LEAD + 0.1) / 1.1) * (1 - 0.6 * ss((t - BELLOW_LEAD - 2.4) / 1.0))
    F = [(120, 180, 70, 1.0), (330, 430, 120, 0.7), (680, 820, 200, 0.42), (1150, 1250, 300, 0.12)]
    x = np.zeros(n)
    voices = 7
    for v in range(voices):
        det = 1 + rng.uniform(-0.028, 0.028)
        drift = 1 + 0.008 * slow(rng, n, 0.6)
        f0 = contour(t, 31.0 * det) * drift
        ph = 2 * np.pi * np.cumsum(f0) / SR + rng.uniform(0, 6.28)
        for k in range(1, 40):
            fk = f0 * k
            if fk.mean() > 2500:
                break
            spec = 1.0 / k ** 0.75
            form = np.zeros(n)
            for lo_f, hi_f, bw, g in F:
                c = lo_f + (hi_f - lo_f) * open_
                form += g / (1 + ((fk - c) / (bw / 2)) ** 2)
            form += 0.6 * np.exp(-fk / 70)
            x += np.sin(k * ph + rng.uniform(0, 6.28)) * spec * form * (0.8 + 0.2 * slow(rng, n, 0.8))
    breath = shaped(n, rng, lambda tc, f: sum(g / (1 + ((f - c) / (bw / 2)) ** 2) for c, _, bw, g in F) * floor_cut(f, 60, 1800, 2))
    x = unit(x) + 0.12 * unit(breath)
    x = x * env
    x = weight(x, 25, 100, 0.35)
    x = space(x, rng, 3.5, 1.8, 0.8, 0.25, early=[(0.11, 0.25, 900), (0.23, 0.15, 700)], wet=0.35)
    return fade(lowcut(x[:n]), 0.02, 0.6)


def bellow_B(seed=5202):
    """Take B, "Mountain horn": low brass, the cinematic way: a section of eight horns on one low C (32.7 Hz) and its
    octave, their brightness growing with how hard they blow (brass's own law: each higher harmonic swells faster
    than the one under it, so the swell opens the sound up), a scoop up into the note as it starts, all of it into a
    vast hall of sympathetic resonance (high-Q ringing at the note's harmonics, as brass played into a piano's open
    strings in a church) and a long dark space."""
    rng = R(seed)
    d = 7.8
    n = N(d)
    t = tt(n)
    env = bellow_env(t, rel=2.0)
    x = np.zeros(n)
    for v in range(8):
        base = 32.7 * (2 if v >= 6 else 1) * (1 + rng.uniform(-0.03, 0.03))
        scoop = 1 - 0.06 * np.exp(-np.maximum(t - rng.uniform(0.0, 0.15), 0) / 0.18)
        f0 = base * scoop * (1 + 0.004 * slow(rng, n, 0.5)) * (1 - 0.05 * ss((t - BELLOW_LEAD - 2.4) / 1.4))
        ph = 2 * np.pi * np.cumsum(f0) / SR + rng.uniform(0, 6.28)
        blow_ = np.clip(env * (0.9 + 0.1 * slow(rng, n, 0.7)), 0, 1)
        for k in range(1, 48):
            if base * k > 3000:
                break
            # (brass: the k-th harmonic grows as blow^(1 + 0.45 (k-1)): soft is dark and round, loud opens out)
            a = blow_ ** (1 + 0.45 * (k - 1)) / k ** 0.35 * np.exp(-base * k / 800)
            x += np.sin(k * ph + rng.uniform(0, 6.28)) * a * (1.0 if v < 6 else 0.55)
    x = unit(x) * (0.2 + 0.8 * env)
    # the hall's sympathy: the note's harmonics ringing on long after
    sym = np.zeros(n)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = np.zeros_like(f)
    for k in range(1, 30):
        g += 1 / (1 + ((f - 32.7 * k * 1.003) / 0.8) ** 2) / k ** 0.5
    sym = np.fft.irfft(X * g, n)
    x = unit(x) + 0.35 * unit(sym)
    x = bp(x, None, 1100, 3)
    x = weight(x, 25, 100, 0.3)
    x = space(x, rng, 5.0, 2.6, 1.4, 0.35, early=[(0.19, 0.2, 800), (0.41, 0.15, 600)], wet=0.5)
    return fade(lowcut(x[:n]), 0.02, 0.6)


def bellow_C(seed=5303):
    """Take C, "Cavern": no oscillator at all. The worm breathes out through itself and the tube sounds as wind sounds
    a cave or a bottle: breath noise driven through the resonances of a stone cylinder (lengthwise and across: an
    inharmonic set worked out from a pipe's modes, scaled so its lowest sits at 34 Hz), each ringing with a Q of
    20-50, so the tone is born out of the air and breathes; a deep pressure swell under it."""
    rng = R(seed)
    d = 7.6
    n = N(d)
    t = tt(n)
    env = bellow_env(t, rel=1.9)
    # (a cylinder's modes: sqrt((p/L)^2 + (j/(pi a))^2), p along it, j the Bessel zeros across; scaled)
    jz = [0.0, 1.841, 3.054, 3.832, 4.201, 5.318]
    L, a = 1.0, 0.33
    fm = sorted({np.sqrt((p / L) ** 2 + (j / (np.pi * a)) ** 2) for p in range(1, 9) for j in jz})
    fm = np.array(fm) / fm[0] * 34.0
    fm = fm[fm < 1600]
    gm = (fm / 34.0) ** -0.9 * rng.uniform(0.6, 1.0, len(fm))
    qs = rng.uniform(20, 50, len(fm))
    dur = n / SR

    def mag(tc, f):
        e = float(np.interp(tc, t, env))
        sweep = 1 + 0.05 * ss((tc - BELLOW_LEAD) / 1.5) - 0.07 * ss((tc - BELLOW_LEAD - 2.5) / 1.2)
        c = fm * sweep
        tone = peaks(f, c, np.maximum(c / qs, 3.5), gm * (0.3 + 0.7 * e) ** (1 + 0.6 * np.log2(c / 34.0)))
        wind = 0.05 * floor_cut(f, 40, 900, 2) * e
        return (tone + wind) * e
    x = unit(shaped(n, rng, mag, frame=16384, hop=2048))
    x = x + 0.8 * pressure(n, BELLOW_LEAD + 0.8, 0.5, 1.6, 28, rng) * env
    x = weight(x, 25, 100, 0.45)
    x = space(x, rng, 4.0, 2.0, 1.0, 0.3, early=[(0.15, 0.25, 700), (0.33, 0.15, 500)], wet=0.4)
    return fade(lowcut(x[:n]), 0.02, 0.6)


def bore(f0, length, press, seed, cutoff=0.35):
    """A blown stone tube, as a physical model (a reed-driven bore, the clarinet's model in Perry Cook's and Gary
    Scavone's STK): a delay line the length of the tube (closed at the throat, open at the mouth: its odd harmonics
    strongest), a lossy reflection at the mouth, a pressure-driven valve (the throat) whose stiffness bends the tone
    brighter as it is blown harder. `press` the blowing pressure over time."""
    rng = R(seed)
    n = len(press)
    dl = SR / f0 * 0.5 - 1.5
    size = int(dl) + 4
    buf = [0.0] * size
    w = 0
    lp = 0.0
    out = [0.0] * n
    noise = (rng.standard_normal(n) * 0.04).tolist()
    press = press.tolist()
    for i in range(n):
        rp = w - dl
        j = int(rp // 1)
        fr = rp - j
        last = buf[j % size] * (1 - fr) + buf[(j + 1) % size] * fr
        lp = lp + cutoff * (last - lp)
        p = press[i] * (1 + noise[i])
        diff = -0.95 * lp - p
        refl = 0.7 - 0.3 * diff
        refl = -1.0 if refl < -1.0 else (1.0 if refl > 1.0 else refl)
        v = p + diff * refl
        buf[w % size] = v
        w += 1
        out[i] = v
    return np.array(out)


def bellow_D(seed=5404):
    """Take D, "Bore": a physical model of the tube itself (see `bore`): three bores a little apart (31, 31.6, 46 Hz:
    the throat and two chambers), blown with a slow swell so the valve's bloom opens the tone as it grows; the
    hollow odd-harmonic colour of a closed pipe; through the mouth's broad resonance and the long space of its own
    body."""
    rng = R(seed)
    d = 7.5
    n = N(d)
    t = tt(n)
    env = bellow_env(t)
    x = np.zeros(n)
    for f0, g, sd in ((31.0, 1.0, 1), (31.9, 0.85, 2), (30.2, 0.85, 4), (32.6, 0.6, 5), (46.5, 0.45, 3)):
        p = 0.32 + 0.5 * env * (1 + 0.03 * slow(rng, n, 0.6))
        y = bore(f0, d, p, seed + sd, 0.30)
        y = y - np.mean(y)
        x += g * unit(bp(y, 20, None, 2))
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    mouth = 0.5 + peaks(f, [210, 520], [260, 500], [1.0, 0.45])
    x = np.fft.irfft(X * mouth * floor_cut(f, 22, 800, 4), n)
    x = unit(x) * env
    x = weight(x, 25, 100, 0.3)
    x = space(x, rng, 4.0, 2.0, 0.9, 0.3, early=[(0.13, 0.22, 800), (0.29, 0.16, 600)], wet=0.4)
    return fade(lowcut(x[:n]), 0.02, 0.6)


BELLOWS = {"A": bellow_A, "B": bellow_B, "C": bellow_C, "D": bellow_D}
BITES = ("A", "B", "C")
# the takes the plan plays (the others are written too, so the wheel or a review can switch)
BELLOW_PICK = "A"
BITE_PICK = "C"


# ======================================================================================================================
# the tail, the tunnel failing, settling
# ======================================================================================================================
def tail_in(seed):
    """The tail gone into the far hole (31 s): a deep plunge: air drawn down after it, a muffled closing thud deep
    under the land, the hole's lip slumping after."""
    rng = R(seed)
    n = N(3.5)
    t = tt(n)
    pull = air(n, rng, lambda tc: 260 * 2 ** (-2.0 * ss((tc + 0.3) / 0.6)), 2.0, 25)
    x = pull * np.exp(-0.5 * ((t - HIT_AT + 0.05) / np.where(t < HIT_AT, 0.18, 0.3)) ** 2)
    x += 1.0 * unit(bp(modes(n, HIT_AT, [24, 33, 45, 60], [0.6, 0.45, 0.3, 0.2], [1, 0.8, 0.5, 0.3], 0.07, rng), None, 300, 2))
    x += 0.3 * earth_pour(n, rng, HIT_AT + 0.3, 2.5, 35, 400)
    x = weight(x, 22, 100, 0.6)
    x = space(x, rng, 3.0, 1.4, 0.6, 0.2, wet=0.25)
    return fade(lowcut(x[:n]), 0, 1.4)


def sink(k):
    """A ring of the tunnel giving way: a deep thud of the land dropping (the ground's modes, each ring's own: their
    pitches, decays, the push's length, a second slump for some), the earth sliding in over a second, and air venting
    up out of the cracks (a low rush, dark, swelling and fading). Six, each built differently enough to tell apart."""
    rng = R(6100 + 37 * k)
    n = N(4.0)
    t = tt(n)
    t0 = HIT_AT
    var = [1.0, 0.9, 1.12, 0.95, 1.06, 0.86][k]
    f = np.array([30.0, 42.0, 57.0, 78.0]) * var * rng.uniform(0.95, 1.05, 4)
    x = pk(modes(n, t0 - 0.02, f, [0.6, 0.45, 0.3, 0.18], [1, 0.85, 0.55, 0.3], rng.uniform(0.035, 0.07), rng))
    if k in (1, 4):
        x += 0.6 * pk(modes(n, t0 + rng.uniform(0.18, 0.3), f * 0.9, [0.5, 0.35, 0.25, 0.15], [1, 0.7, 0.4, 0.2], 0.05, rng))
    if k in (2, 5):
        x += 0.45 * pk(modes(n, t0 - 0.18, f * 1.1, [0.3, 0.25, 0.2, 0.1], [1, 0.6, 0.3, 0.2], 0.15, rng))
    body = mass(n, rng, 90, 600, 10, 0.05, -0.5, 5)
    x += 0.33 * pk(body * np.where(t > t0, (1 - np.exp(-(t - t0) / 0.02)) * np.exp(-(t - t0) / 0.45), 0))
    x += 0.2 * pk(earth_pour(n, rng, t0 + 0.15, 1.8, 40, 550))
    vt = t0 + rng.uniform(0.15, 0.45)
    vent = air(n, rng, lambda tc: 140 + 160 * ss((tc - vt) / 0.5) * np.exp(-max(tc - vt - 0.5, 0) / 1.0), 2.4, 40)
    x += rng.uniform(0.2, 0.3) * pk(vent * np.where(t > vt, ss((t - vt) / 0.35) * np.exp(-(t - vt) / rng.uniform(0.8, 1.4)), 0))
    x = drive(weight(x, 25, 100, 0.55))
    x = space(x, rng, 2.5, 1.2, 0.5, 0.2, early=[(0.3 * var, 0.15, 900)], wet=0.25)
    return fade(lowcut(x[:n]), 0, 0.6)


def settle(seed):
    """After the last ring (from ~38 s to the end): the land settling: a low smooth rumble letting go over seven
    seconds, the earth still sliding a little, the air going still. Fades out; never stops dead."""
    rng = R(seed)
    n = N(8.0)
    t = tt(n)
    x = mass(n, rng, 25, 220, 10, 0.05, -0.3, 5) + 0.6 * earth_pour(n, rng, 0.0, 7.5, 35, 450)
    x += 0.4 * air(n, rng, lambda tc: 110 - 40 * tc / 8, 2.4, 25)
    x = x * np.exp(-t / 2.6) * ss(t / 0.6)
    x = weight(x, 25, 100, 0.4)
    x = space(x, rng, 3.0, 1.5, 0.6, 0.2, wet=0.25)
    return fade(lowcut(x[:n]), 0, 1.5)


# ======================================================================================================================
# caught
# ======================================================================================================================
def gulp(seed):
    """The mouth closing over the player: the open world shut out over about a second. The outside's air (a broad band
    of the land's sound) narrowing and darkening as the jaws close (its top sliding down from 2.5 kHz to 120 Hz), the
    pressure changing (a slow sub push you feel in the ears), and the jaws meeting: a huge soft closing (padded: 80 ms
    of force into low modes), at GULP_SHUT."""
    rng = R(seed)
    n = N(2.6)
    t = tt(n)
    def mag(tc, f):
        v = ss(tc / GULP_SHUT)
        top = 2500 * (120 / 2500) ** v
        return floor_cut(f, 35, top, 2) * tilt(f, 150, -2.2) * (1 - 0.6 * v) * (1 if tc < GULP_SHUT + 0.1 else np.exp(-(tc - GULP_SHUT - 0.1) / 0.25))
    outside = unit(shaped(n, rng, mag, frame=4096, hop=1024))
    x = outside * (0.4 + 0.6 * ss(t / 0.25))
    x += 0.9 * pressure(n, GULP_SHUT - 0.1, 0.25, 0.8, 18, rng)
    x += 1.1 * unit(modes(n, GULP_SHUT - 0.05, [26, 37, 52, 74], [0.5, 0.4, 0.28, 0.18], [1, 0.75, 0.45, 0.25], 0.08, rng))
    x += 0.35 * mass(n, rng, 60, 400, 8, 0.04, -0.5, 6) * np.where(t > GULP_SHUT, np.exp(-(t - GULP_SHUT) / 0.6), 0)
    x = weight(x, 22, 100, 0.5)
    # (inside now: the closing heard in the throat's own space)
    x = space(x, rng, 3.0, 2.2, 0.6, 0.12, early=[(0.09, 0.3, 500), (0.2, 0.2, 400)], wet=0.35)
    return fade(lowcut(x[:n]), 0.03, 0.4)


def spit(seed):
    """Thrown out at the next surfacing: a burst of air out of the mouth (dark to bright, the outside's sound opening
    back up from 150 Hz to 3 kHz), the pressure let go, a deep huff of the throat throwing (a round push, no crack),
    the open world's air around again."""
    rng = R(seed)
    n = N(3.0)
    t = tt(n)
    def mag(tc, f):
        v = ss((tc - SPIT_AT + 0.1) / 0.6)
        top = 120 * (1600 / 120) ** v
        g = 0.3 + 0.7 * np.exp(-max(tc - SPIT_AT - 0.2, 0) / 0.9)
        return floor_cut(f, 30, top, 2) * tilt(f, 150, -2.5) * g
    x = 0.8 * unit(shaped(n, rng, mag, frame=4096, hop=1024)) * ss((t - SPIT_AT + 0.15) / 0.12)
    x += 1.2 * unit(modes(n, SPIT_AT - 0.04, [28, 40, 56], [0.35, 0.25, 0.18], [1, 0.7, 0.35], 0.07, rng))
    x += 0.7 * pressure(n, SPIT_AT, 0.05, 0.4, 20, rng)
    x = weight(x, 22, 100, 0.5)
    x = space(x, rng, 2.5, 1.2, 0.5, 0.2, wet=0.25)
    return fade(lowcut(x[:n]), 0.0, 0.6)


# ======================================================================================================================
# round 2 (the first set's kept sounds are all deep, continuous, ground-borne mass or a long seismic roll;
# the dropped ones all carried an air or texture layer, 10 dB more 800 Hz-3 kHz than the kept and a fast event
# envelope). Everything here keeps its 800 Hz-3 kHz 25 dB or more under the whole and its top 50 dB under, and rises
# over a tenth of a second or more.
# ======================================================================================================================
def dark(x, hi=700.0, order=2):
    """The top taken off: what the approved files have in common (their 800 Hz-3 kHz 25-40 dB down)."""
    return bp(x, None, hi, order)


def modal_bank(n, t0, freqs, taus, amps, force_len, rng):
    """Many damped modes rung by one smooth push (`modes`, but summed first and convolved once: hundreds of modes
    cheaply). Deterministic but for the phases."""
    t = tt(n)
    u = np.maximum(t - t0, 0.0)
    ir = np.zeros(n)
    ph = rng.uniform(0, 2 * np.pi, len(freqs))
    for f0, tau, a, p in zip(freqs, taus, amps, ph):
        ir += a * np.sin(2 * np.pi * f0 * u + p) * np.exp(-u / tau)
    ir *= t >= t0
    fl = max(N(force_len), 8)
    force = np.hanning(2 * fl)
    return signal.fftconvolve(ir, force / force.sum())[:n]


def surges(n, rng, t0, plan):
    """The ground rolling away in surges (bite C's): each a low band of drifting resonances
    swelling and dying round its time. `plan`: (delay, gain, lo, hi, width s)."""
    t = tt(n)
    x = np.zeros(n)
    for dt, g, lo, hi, w in plan:
        s = mass(n, rng, lo, 2.2 * hi, 10, 0.04, -0.2, 5)
        x += g * pk(s * np.exp(-0.5 * ((t - t0 - dt) / (w / 2.2)) ** 2))
    return x


def breach_A(seed=2201, far=False):
    """Take A, "Heave" (bite C's family): the land straining for half a second before it goes, then the ground struck
    from below by a long push (90 ms: no edge), its lowest modes ringing down, and the ground rolling away in three
    surges, each lower and longer, the pressure of it under them. No debris, no air."""
    rng = R(seed + (50 if far else 0))
    n = N(8.5)
    t = tt(n)
    t0 = HIT_AT + 0.5
    strain = mass(n, rng, 18, 90, 6, 0.03, 0.3, 7) * ss((t - t0 + 0.6) / 0.6) * np.where(t < t0, 1, np.exp(-(t - t0) / 0.3))
    blow = modes(n, t0 - 0.06, np.array([26.0, 35.0, 46.0, 60.0, 79.0, 104.0]) * rng.uniform(0.97, 1.03, 6), [0.8, 0.6, 0.45, 0.32, 0.22, 0.15], [1, 1, 0.85, 0.65, 0.45, 0.3], 0.09, rng)
    x = 0.3 * pk(strain) + 1.0 * pk(blow)
    x += surges(n, rng, t0, [(0.75, 0.62, 22, 170, 0.8), (1.7, 0.5, 20, 140, 1.15), (2.9, 0.42, 18, 110, 1.5)])
    x += 0.45 * pk(pressure(n, t0, 0.05, 1.0, 24, rng))
    x = drive(weight(x, 22, 110, 0.7))
    x = distant(x, 800, rng) if far else space(x, rng, 4.0, 1.6, 0.6, 0.2, early=[(0.55, 0.2, 600), (1.2, 0.12, 400)], wet=0.28)
    return fade(lowcut(dark(x[:n], 1600)), 0, 1.5), t0


def breach_B(seed=2202, far=False):
    """Take B, "Ringdown": no noise at all. The land as one vast body struck from below: 1,600 of its own modes
    (18-520 Hz, so dense they overlap and never ring as a note), the lowest ringing longest, rung by the heave (an
    8 ms push: short enough to ring them all up to ~250 Hz, nothing above), then rung again softer as it settles back 0.45 s on; under it the displaced air's single deep push.
    Its far take answered by the land as plain delayed copies (no noise reverb)."""
    rng = R(seed)
    n = N(8.5)
    t = tt(n)
    t0 = HIT_AT + 0.15
    k = 1600
    fr = np.exp(rng.uniform(np.log(18), np.log(520), k))
    taus = 0.3 + 1.3 * (fr / 18) ** -0.6 * rng.uniform(0.6, 1.2, k)
    am = (fr / 18) ** -0.12 * rng.uniform(0.3, 1.0, k)
    x = pk(modal_bank(n, t0 - 0.004, fr, taus, am, 0.004, rng))
    x += 0.5 * pk(modal_bank(n, t0 + 0.45, fr * 0.97, taus * 0.8, am, 0.009, rng))
    # (the displaced air: one swing and a half of 24 Hz, smoothly windowed)
    u = t - t0
    win = np.where((u > -0.03) & (u < 0.09), 0.5 - 0.5 * np.cos(2 * np.pi * (u + 0.03) / 0.12), 0.0)
    push = np.sin(2 * np.pi * 24 * (u + 0.03)) * win
    x += 0.5 * pk(push)
    x = drive(weight(x, 22, 110, 0.8), 7.0)
    if far:
        x = distant(x, 800, rng, echoes=False)
        y = x.copy()
        for dly, g, lp in ((0.55, 0.42, 500), (1.15, 0.33, 380), (1.9, 0.25, 300), (2.8, 0.17, 250), (3.7, 0.1, 200)):
            e = bp(x, None, lp, 2) * g
            k0 = N(dly * rng.uniform(0.9, 1.1))
            y[k0:] += e[: n - k0]
        x = y
    return fade(lowcut(dark(x[:n], 1600)), 0, 1.5), t0


def breach_C(seed=2203, far=False):
    """Take C, "Air front": the boom of the air a mountain shoves aside, and the land rolling it back. One deep
    pressure front (the second difference of a smooth swell: a single low push and pull, a little steepened as a
    big blast front is, its top taken off), then the land answering it as a long roll of returns off hills and
    valleys, thirty-odd, each later one lower, softer and smeared, crowding in and thinning out as thunder rolls. The
    air's slow low flow after it. No ground layer, no debris."""
    rng = R(seed + (50 if far else 0))
    n = N(8.5)
    t = tt(n)
    t0 = HIT_AT + 0.1
    w = 0.005
    g = np.exp(-0.5 * ((t - t0) / w) ** 2)
    front = -np.gradient(np.gradient(g))
    front = front / np.abs(front).max()
    front = front + 0.25 * front ** 2 * np.sign(front)
    front = bp(front, None, 1000, 2)
    roll = np.zeros(n)
    for j in range(34):
        dly = 0.12 + 4.2 * rng.beta(1.6, 3.0)
        lp = 900 * np.exp(-dly / 2.2) + 120
        sm = np.hanning(N(0.02 + 0.05 * dly))
        e = signal.fftconvolve(front, sm / sm.sum())[:n]
        e = bp(e, None, lp, 2) * np.exp(-dly / 1.8) * rng.uniform(0.5, 1.0) * (1 if rng.uniform() < 0.8 else -1)
        k0 = N(dly)
        roll[k0:] += e[: n - k0]
    flow = mass(n, rng, 18, 80, 5, 0.03, -0.2, 3) * np.where(t > t0, ss((t - t0) / 0.3) * np.exp(-(t - t0) / 1.6), 0)
    x = 1.0 * pk(front) + 0.9 * pk(roll) + 0.3 * pk(flow)
    x = drive(weight(x, 22, 110, 0.9))
    x = distant(x, 800, rng) if far else space(x, rng, 3.0, 1.4, 0.5, 0.2, wet=0.15)
    return fade(lowcut(dark(x[:n], 1600)), 0, 1.5), t0


def breach_D(seed=2204, far=False):
    """Take D, "Upheaval": no blow at all. The ground rising and failing as one long roar: a sub swell from below for
    0.8 s, then the land's resonances (wide, drifting) opening upward as it bursts (their top climbing 120 -> 420 Hz)
    and closing back down as it rolls on and dies over six seconds, its level wandering slowly."""
    rng = R(seed + (50 if far else 0))
    n = N(8.5)
    t = tt(n)
    t0 = HIT_AT + 0.8
    dur = n / SR
    cs = np.exp(rng.uniform(np.log(20), np.log(400), 22))
    gs = rng.uniform(0.5, 1.0, 22) * (cs / 20) ** -0.5
    rates = rng.uniform(0.05, 0.25, 22)
    ph = rng.uniform(0, 6, 22)

    def mag(tc, f):
        v = tc - t0
        top = 120 + 300 * np.exp(-0.5 * ((v - 0.6) / 0.9) ** 2) if v > -1 else 120
        c = cs * (1 + 0.1 * np.sin(2 * np.pi * rates * tc + ph))
        m = peaks(f, c, c / 2.5, gs) * floor_cut(f, 18, top, 2)
        return m
    roar = shaped(n, rng, mag)
    env = np.where(t < t0, 0.25 * ss((t - t0 + 0.8) / 0.8), 0.25 + 0.75 * ss((t - t0) / 0.3)) * np.where(t > t0 + 1.2, np.exp(-(t - t0 - 1.2) / 2.0), 1)
    env *= np.exp(2.5 * slow(rng, n, 0.8) / 8.686)
    sub = pressure(n, t0 - 0.3, 0.5, 1.2, 22, rng)
    x = pk(roar * env) + 0.5 * pk(sub)
    x = drive(weight(x, 22, 110, 0.35), 12.0)
    x = distant(x, 800, rng) if far else space(x, rng, 3.5, 1.6, 0.6, 0.2, wet=0.2)
    return fade(lowcut(dark(x[:n], 1600)), 0, 1.5), t0


BREACHES = {"A": breach_A, "B": breach_B, "C": breach_C, "D": breach_D}
BREACH_PICK = "X"


def land_small(k):
    """A smaller landing, in bite C's family (the bite played): one blow and two short surges, higher and lighter, each
    its own."""
    rng = R(4400 + 31 * k)
    n = N(6.0)
    t = tt(n)
    t0 = HIT_AT
    fm = [1.18, 1.3][k]
    x = pk(modes(n, t0 - 0.02, np.array([24.0, 32, 42, 55, 72, 95]) * fm * rng.uniform(0.97, 1.03, 6), [0.6, 0.45, 0.33, 0.24, 0.17, 0.12], [1, 1, 0.9, 0.75, 0.6, 0.45], 0.05, rng))
    x += surges(n, rng, t0, [(0.7, 0.5, 26, 170, 0.7), (1.5, 0.38, 22, 130, 1.0)])
    x += 0.35 * pk(pressure(n, t0 + 0.03, 0.04, 0.8, 26, rng))
    x = drive(weight(x, 22, 110, 0.75))
    x = space(x, rng, 3.0, 1.4, 0.6, 0.2, early=[(0.45, 0.18, 700)], wet=0.25)
    return fade(lowcut(dark(x[:n], 1600)), 0, 1.0)


# ---- the tail leaving its hole ---------------------------------------------------------------------------------------
TAIL_PICK = "D"


def tail_A(seed=7201):
    """Take A, "Release": the hole letting go of the last of it: the body's own groan dropping away (its drifting
    resonances sliding down an octave and fading as the end passes, TAIL_AT), and the emptied hole's pressure
    released as one deep, soft boom (a 160 ms push into the land's lowest modes), the ground relaxing after."""
    rng = R(seed)
    n = N(4.5)
    t = tt(n)
    goes = mass(n, rng, 30, 260, 12, 0.05, -1.0, 5) * np.where(t < TAIL_AT, 1, np.exp(-(t - TAIL_AT) / 0.7))
    boom = modes(n, TAIL_AT - 0.1, [24.0, 33, 45, 61], [0.7, 0.5, 0.36, 0.25], [1, 0.8, 0.5, 0.3], 0.16, rng)
    relax = surges(n, rng, TAIL_AT, [(0.9, 0.35, 20, 110, 1.4)])
    x = 0.55 * pk(goes) + 1.0 * pk(boom) + relax + 0.35 * pk(pressure(n, TAIL_AT, 0.08, 0.8, 22, rng))
    x = drive(weight(x, 22, 100, 0.6))
    x = space(x, rng, 3.0, 1.4, 0.5, 0.2, wet=0.25)
    return fade(lowcut(dark(x[:n], 1300)), 0, 0.8)


def tail_B(seed=7202):
    """Take B, "Suck": the air drawn down into the emptied shaft: a low pull swelling and darkening (its centre
    falling from 160 to 40 Hz, no hiss), and the shaft itself sounding as the air fills it, a column 100 blocks deep:
    its low resonance (35 Hz and its odd partials, rung by the air, never a struck note) swelling and dying."""
    rng = R(seed)
    n = N(4.5)
    t = tt(n)
    pull = air(n, rng, lambda tc: 160 * (40 / 160) ** ss((tc - 0.0) / (TAIL_AT + 0.6)), 1.6, 20)
    pull *= ss(t / 0.5) * np.where(t > TAIL_AT + 0.4, np.exp(-(t - TAIL_AT - 0.4) / 0.6), 1)

    def colmag(tc, f):
        return peaks(f, [35, 105, 175], [5, 9, 14], [1, 0.4, 0.15]) * float(ss((tc - TAIL_AT) / 0.4) * np.exp(-max(tc - TAIL_AT - 0.4, 0) / 1.1))
    col = shaped(n, rng, colmag, frame=16384, hop=2048)
    x = 0.8 * pk(pull) + 1.0 * pk(col) + 0.4 * pk(pressure(n, TAIL_AT + 0.2, 0.2, 0.8, 22, rng))
    x = drive(weight(x, 22, 100, 0.5))
    x = space(x, rng, 3.0, 1.6, 0.5, 0.15, wet=0.3)
    return fade(lowcut(dark(x[:n], 1100)), 0, 0.8)


def tail_C(seed=7203):
    """Take C, "Last pass": the approved body's sound, its last stretch: the moving mass and the air it moves passing
    over and away (the hump sliding down as it goes, Doppler), thinning to nothing; the ground under the hole giving
    a single slow low shrug as the weight leaves it."""
    rng = R(seed)
    n = N(5.0)
    t = tt(n)
    a = air(n, rng, lambda tc: 110 * 2 ** (-1.3 * ss((tc - 0.2) / 2.0)), 2.4, 22)
    m = mass(n, rng, 30, 280, 12, 0.08, -0.6, 5)
    away = ss(t / 0.4) * np.exp(-np.maximum(t - TAIL_AT, 0) / 1.2)
    shrug = surges(n, rng, TAIL_AT, [(0.4, 1.0, 18, 90, 1.6)])
    x = (pk(a) * 0.9 + pk(m) * 0.8) * away + 0.55 * shrug
    x = weight(x, 22, 100, 0.45)
    x = space(x, rng, 3.0, 1.5, 0.6, 0.2, wet=0.3)
    return fade(lowcut(dark(x[:n], 1300)), 0, 0.8)


TAILS = {"A": tail_A, "B": tail_B, "C": tail_C}


# ---- inside the throat: no beat, no pulse --------------------------------------------------------------------------
THROAT_S = 8.0
THROAT_PICK = "D"


def loop_slow(rng, n, kmax, decay=1.0):
    """A slow wandering curve that loops: a few sine cycles that fit the length exactly (1..kmax a loop), random
    phases, irregular (never one rate)."""
    t = np.arange(n) / n
    x = np.zeros(n)
    for k in range(1, kmax + 1):
        x += rng.uniform(0.3, 1.0) / k ** decay * np.sin(2 * np.pi * k * t + rng.uniform(0, 6.28))
    return x / (np.abs(x).max() + 1e-9)


def circ_space(x, rng, lo_tau=1.8, mid_tau=0.6, length=3.0):
    """A space convolved round the loop (so the loop stays seamless)."""
    n = len(x)
    m = N(length)
    ti = tt(m)
    z = rng.standard_normal(m)
    ir = bp(z, None, 250, 2) * np.exp(-ti / lo_tau) + 0.4 * bp(z, 250, 1200, 2) * np.exp(-ti / mid_tau)
    ir *= ss(ti / 0.05)
    ir /= np.sqrt(np.sum(ir ** 2))
    irc = np.zeros(n)
    for i0 in range(0, m, n):
        seg = ir[i0:i0 + n]
        irc[: len(seg)] += seg
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(irc), n)


def circ_band(x, lo, hi, order=2):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * floor_cut(f, lo, hi, order), len(x))


def throat_A(seed=8101):
    """Take A, "Gullet": the approved body heard from inside its own walls: its drifting stone resonances, muffled to
    under 250 Hz, carried through the walls, swelling and easing in slow irregular surges (loop-fitted, never a
    beat), pressure under it, the outside a faint low rumble."""
    rng = R(seed)
    n = N(THROAT_S)
    sw = 1 + 0.35 * loop_slow(rng, n, 5)
    m = mass(n, rng, 25, 240, 14, 0.06, 0.0, 5, loop=True)
    p = shaped(n, rng, lambda tc, f: floor_cut(f, 16, 40, 3), loop=True)
    out = shaped(n, rng, lambda tc, f: floor_cut(f, 25, 120, 3), loop=True)
    x = pk(m) * sw + 0.5 * pk(p) * (1 + 0.3 * loop_slow(rng, n, 3)) + 0.15 * pk(out)
    x = x + 0.35 * circ_space(x, rng)
    return drive(circ_band(x, 19, 260, 2), 6.0)


def throat_B(seed=8102):
    """Take B, "Tunnel": air pushed along a stone tube 60 blocks across: a dark rush (60-350 Hz) whose colour drifts
    slowly as the gullet bends, the tube's own crowded low resonances standing in it (a long pipe's modes, every
    ~6 Hz, wide), the body's mass under it, the vast enclosed space round all of it."""
    rng = R(seed)
    n = N(THROAT_S)
    wob = loop_slow(rng, n, 4)
    cs = 24 + 5.9 * np.arange(60)
    gs = (cs / 24) ** -0.6

    def mag(tc, f):
        i = int(min(tc * SR, n - 1))
        c = 140 * 2 ** (0.5 * wob[i])
        lf = np.log2(np.maximum(f, 1) / c)
        rush = np.exp(-0.5 * (lf / 0.9) ** 2) * floor_cut(f, 50, None, 2)
        return rush * (0.6 + peaks(f, cs, np.full(60, 3.5), gs))
    x = pk(shaped(n, rng, mag, frame=16384, hop=2048, loop=True))
    x += 0.6 * pk(mass(n, rng, 25, 160, 10, 0.05, 0.0, 5, loop=True))
    x = x * (1 + 0.25 * loop_slow(rng, n, 4))
    x = x + 0.45 * circ_space(x, rng, 2.2, 0.7)
    return drive(circ_band(x, 19, 400, 2), 6.0)


def throat_C(seed=8103):
    """Take C, "Pressure": almost nothing but weight: the enclosed air's slow pressure breathing (16-60 Hz), the walls'
    grinding passing far down the body (low, muffled under 150 Hz), and the outside world all but gone (a trace of
    rumble under 80 Hz). The emptiest of the three: the world gone away."""
    rng = R(seed)
    n = N(THROAT_S)
    p = shaped(n, rng, lambda tc, f: floor_cut(f, 16, 60, 3), loop=True) * (1 + 0.4 * loop_slow(rng, n, 3))
    g = mass(n, rng, 30, 150, 8, 0.05, 0.0, 6, loop=True) * (1 + 0.45 * loop_slow(rng, n, 6))
    o = shaped(n, rng, lambda tc, f: floor_cut(f, 22, 80, 3), loop=True)
    x = pk(p) + 0.55 * pk(g) + 0.12 * pk(o)
    x = x + 0.3 * circ_space(x, rng, 2.5, 0.6)
    return drive(circ_band(x, 18, 160, 2), 6.0)


THROATS = {"A": throat_A, "B": throat_B, "C": throat_C}


# ---- the unsure ones: alternatives -------------------------------------------------------------------------------------
def slump(k):
    """A tunnel ring dropping, round 2: a slump with weight (a 100-170 ms push into the land's lowest modes) and a
    long low tail rolling away in one or two surges (bite C's family), no venting air, no sliding earth. Three, each
    its own pitch, push and roll."""
    rng = R(6400 + 41 * k)
    n = N(6.0)
    t0 = HIT_AT
    var = [1.0, 0.88, 1.12][k]
    f = np.array([24.0, 32, 43, 57, 76]) * var * rng.uniform(0.96, 1.04, 5)
    x = pk(modes(n, t0 - 0.06, f, [0.75, 0.55, 0.4, 0.28, 0.2], [1, 0.9, 0.65, 0.45, 0.3], [0.11, 0.15, 0.17][k], rng))
    plan = [[(0.6, 0.5, 20, 140, 1.0)], [(0.5, 0.45, 20, 130, 0.9), (1.4, 0.35, 18, 100, 1.3)], [(0.8, 0.55, 22, 150, 1.2)]][k]
    x += surges(n, rng, t0, plan)
    x += 0.35 * pk(pressure(n, t0, 0.06, 0.8, 22 * var, rng))
    x = drive(weight(x, 22, 110, 0.65))
    x = space(x, rng, 3.0, 1.5, 0.5, 0.2, early=[(0.35 * var, 0.15, 500)], wet=0.25)
    return fade(lowcut(dark(x[:n], 1500)), 0, 1.2)


def settle_b(seed=7111):
    """Settling, round 2: the land's last rolls: five surges spaced ever wider, each lower and quieter (bite C's family),
    over the lowest groan of the ground going still. No sliding earth, no air."""
    rng = R(seed)
    n = N(9.0)
    t = tt(n)
    x = surges(n, rng, 0.0, [(0.6, 1.0, 22, 150, 1.2), (1.9, 0.75, 20, 130, 1.5), (3.5, 0.55, 19, 110, 1.9), (5.4, 0.38, 18, 95, 2.2), (7.4, 0.24, 18, 80, 2.4)])
    x += 0.5 * pk(mass(n, rng, 18, 70, 6, 0.03, -0.2, 6) * np.exp(-t / 3.5) * ss(t / 0.5))
    x = weight(x, 22, 100, 0.5)
    x = space(x, rng, 3.0, 1.6, 0.5, 0.2, wet=0.25)
    return fade(lowcut(dark(x[:n], 1200)), 0.05, 1.5)


def gulp_b(seed=8201):
    """Gulp, round 2 B, "Eclipse": the world going away. The open land's broad sound narrowing smoothly as the mouth
    comes over (its top falling from 1.2 kHz to 60 Hz over 1.2 s, as light going out), while the mountain's weight
    comes down on the air (a sub pressure building and holding), shut with no impact at all: the pressure simply
    stays and the outside is gone."""
    rng = R(seed)
    n = N(3.2)
    t = tt(n)
    sh = GULP_SHUT

    def mag(tc, f):
        v = ss((tc - sh + 1.2) / 1.2)
        top = 1200 * (60 / 1200) ** v
        return floor_cut(f, 25, top, 3) * tilt(f, 100, -2.5)
    world = pk(shaped(n, rng, mag, frame=4096, hop=1024)) * np.where(t < sh, 1, np.exp(-(t - sh) / 0.5))
    weight_ = pk(pressure(n, sh, 0.5, 2.5, 18, rng))
    body_ = pk(mass(n, rng, 20, 120, 8, 0.04, -0.3, 5)) * ss((t - sh + 0.8) / 0.9) * np.exp(-np.maximum(t - sh, 0) / 1.5)
    x = 0.8 * world + 1.0 * weight_ + 0.5 * body_
    x = weight(x, 20, 90, 0.4)
    x = space(x, rng, 3.0, 2.2, 0.5, 0.12, wet=0.3)
    return fade(lowcut(dark(x[:n], 1200, 2)), 0.05, 0.5)


def gulp_c(seed=8202):
    """Gulp, round 2 C, "Weight": the approved body bearing down: its moving mass growing closer and darker over a
    second (the mountain coming over you), then the jaws settling shut as one very soft, very heavy closure (a 250 ms
    push into the lowest modes, under 150 Hz) rolling on and muffled, the outside cut under it."""
    rng = R(seed)
    n = N(3.5)
    t = tt(n)
    sh = GULP_SHUT
    m = mass(n, rng, 25, 300, 12, 0.06, -0.8, 5) * ss((t - sh + 1.0) / 1.0) * np.where(t < sh, 1, np.exp(-(t - sh) / 0.35))
    m = dark(m, 600)
    close = bp(modes(n, sh - 0.15, [22.0, 30, 41, 55], [0.8, 0.6, 0.42, 0.3], [1, 0.85, 0.55, 0.3], 0.25, rng), None, 150, 2)
    roll = surges(n, rng, sh, [(0.7, 0.45, 18, 90, 1.3)])
    x = 0.7 * pk(m) + 1.0 * pk(close) + roll + 0.6 * pk(pressure(n, sh, 0.15, 1.5, 18, rng))
    x = weight(x, 20, 90, 0.5)
    x = space(x, rng, 3.0, 2.2, 0.5, 0.12, wet=0.3)
    return fade(lowcut(dark(x[:n], 1000)), 0.05, 0.6)


# ======================================================================================================================
# the files and their levels
# ======================================================================================================================
# (loudest 400 ms in dBFS: the bite the loudest thing, the breach next, the voice under them; the Payload's approved
# blast_alt sits at about -4.5. The close tier's are lower: their impacts' peaks stand 12-15 dB over their loudest
# 400 ms, as close rock does, and are kept rather than squashed to a level)
LEVELS = {
    "bite": -3.5, "bite_far": -5.0, "breach": -6.0, "breach_far": -7.0, "quake": -8.0, "bellow": -7.0,
    "bellow_far": -8.5, "sign": -8.0, "sign_short": -9.0, "move": -13.0, "rise": -10.0, "body": -11.0,
    "dive": -6.5, "land": -5.5, "ride": -9.0, "breach7": -6.0, "bite7": -4.0, "breach_close": -8.5, "bite_close": -7.0, "sink_close": -9.5, "grind": -11.0,
    "rim": -10.5, "tail_out": -8.0, "tail_in": -9.0, "sink": -8.0, "settle": -12.0, "gulp": -6.5, "throat": -11.0,
    "spit": -7.0,
}


def recipes():
    """Every file: {name: (how to make it, level key)}."""
    r = {}
    r["sign"] = (lambda: sign(1001, SIGN_PEAK + 1.2, SIGN_PEAK), "sign")
    r["sign_short"] = (lambda: sign(1002, SIGN_SHORT_PEAK + 1.0, SIGN_SHORT_PEAK), "sign_short")
    for k in range(3):
        r[f"move{k + 1}"] = (lambda k=k: move(1100 + k), "move")
    for tk, fn in BREACHES.items():
        r[f"breach_{tk.lower()}"] = (lambda fn=fn: fn()[0], "breach")
        r[f"breach_{tk.lower()}_far"] = (lambda fn=fn: fn(far=True)[0], "breach_far")
    for tk, fn in RIDES.items():
        for part in ("loop", "start", "end"):
            r[f"ride_{tk.lower()}_{part}"] = (lambda fn=fn, part=part: fn(part), "ride")
    # (round 7: the tiers, the burrowing and the rims made to the reference; round 5's synthesized breaking is gone)
    for tier in ("close", "mid", "far"):
        r[f"breach_{tier}"] = (lambda tier=tier: breach7_tier(tier), "breach7")
    r["bite_close"] = (lambda: bite7_close()[0], "bite7")
    r["bite_mid"] = (lambda: bite7_mid(), "bite")
    for k in range(3):
        r[f"slump_close{k + 1}"] = (lambda k=k: slump7_close(k), "sink")
        r[f"grind{k + 1}"] = (lambda k=k: grind7(k), "grind")
        r[f"rim{k + 1}"] = (lambda k=k: rim7(k), "rim")
    r["tail_d"] = (lambda: tail7(), "tail_out")
    r["settle_d"] = (lambda: settle7(), "settle")
    r["gulp_d"] = (lambda: gulp7(), "gulp")
    r["throat_d"] = (lambda: throat7(), "throat")
    for tk in SMASH_KIND:
        r[f"breach_{tk.lower()}"] = (lambda tk=tk: smash_take(tk)[0], "breach")
        r[f"breach_{tk.lower()}_far"] = (lambda tk=tk: smash_take(tk, far=True)[0], "breach_far")
    r["quake1"] = (lambda: quake(2101, 1.0), "quake")
    r["quake2"] = (lambda: quake(2102, 0.88), "quake")
    r["rise"] = (lambda: rise(3001), "rise")
    r["body1"] = (lambda: body(3101), "body")
    r["body2"] = (lambda: body(3102), "body")
    r["dive"] = (lambda: dive(3201), "dive")
    for tk, fn in BELLOWS.items():
        r[f"bellow_{tk.lower()}"] = (fn, "bellow")
        r[f"bellow_{tk.lower()}_far"] = (lambda fn=fn, tk=tk: distant(fn(), 800, R(5900 + ord(tk))), "bellow_far")
    for tk in BITES:
        r[f"bite_{tk.lower()}"] = (lambda tk=tk: bite(tk), "bite")
        r[f"bite_{tk.lower()}_far"] = (lambda tk=tk: bite(tk, True), "bite_far")
    for k in range(2):
        r[f"land{k + 1}"] = (lambda k=k: land_small(k), "land")
    for tk, fn in TAILS.items():
        r[f"tail_{tk.lower()}"] = (fn, "tail_out")
    r["tail_in"] = (lambda: tail_in(7002), "tail_in")
    for k in range(6):
        r[f"sink{k + 1}"] = (lambda k=k: sink(k), "sink")
    for k in range(3):
        r[f"slump{k + 1}"] = (lambda k=k: slump(k), "sink")
    r["settle"] = (lambda: settle(7101), "settle")
    r["settle_b"] = (lambda: settle_b(), "settle")
    r["gulp"] = (lambda: gulp(8001), "gulp")
    r["gulp_b"] = (lambda: gulp_b(), "gulp")
    r["gulp_c"] = (lambda: gulp_c(), "gulp")
    for tk, fn in THROATS.items():
        r[f"throat_{tk.lower()}"] = (fn, "throat")
    r["spit"] = (lambda: spit(8003), "spit")
    return r


def build_only(names):
    r = recipes()
    return {k: (r[k][0](), r[k][1]) for k in r if any(k == n or (n.endswith("*") and k.startswith(n[:-1])) for n in names)}


def build():
    r = recipes()
    return {k: (fn(), key) for k, (fn, key) in r.items()}


def write_all(files):
    out = {}
    for name, (x, key) in files.items():
        if name.startswith("throat") or name.endswith("_loop"):
            # (a loop: scaled only, never bent or faded, so its ends still meet)
            y = x * 10 ** (LEVELS[key] / 20) / (st_rms(x).max() + 1e-12)
            y = y * min(1.0, 0.89 / (np.abs(y).max() + 1e-9))
        elif name.startswith("ride_") and name.rsplit("_", 1)[0] + "_loop" in out:
            # (the ride's start and end meet its middle at the middle's level: the start's last half second and the
            # end's first are scaled to the middle's)
            lp = out[name.rsplit("_", 1)[0] + "_loop"]
            ref = np.sqrt(np.mean(lp ** 2))
            seg = x[-N(0.5):] if name.endswith("_start") else x[:N(0.5)]
            y = x * ref / (np.sqrt(np.mean(seg ** 2)) + 1e-12)
            a = np.abs(y)
            y = np.where(a > 0.5, np.sign(y) * (0.5 + 0.25 * np.tanh((a - 0.5) / 0.25)), y)
        else:
            y = level(x, LEVELS[key])
        write_ogg(OUT / f"{name}.ogg", y)
        out[name] = y
        print(f"wrote worldeater/{name:14s} {len(y) / SR:5.2f}s  peak {20 * np.log10(np.abs(y).max() + 1e-9):5.1f}  "
              f"loudest 400ms {20 * np.log10(st_rms(y).max()):5.1f} dBFS")
    return out


# ======================================================================================================================
# measuring (listening with numbers)
# ======================================================================================================================
OCTS = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000]


def bands(x):
    """Octave band levels (dB, the loudest band 0) and the 100-800 Hz body against everything under 100 Hz."""
    f, p = signal.welch(x, SR, nperseg=16384)
    lv = []
    for c in OCTS:
        m = (f >= c / np.sqrt(2)) & (f < c * np.sqrt(2))
        lv.append(10 * np.log10(p[m].sum() + 1e-30))
    lv = np.array(lv)
    body = p[(f >= 100) & (f < 800)].sum()
    sub = p[(f >= 18) & (f < 100)].sum()
    top = p[f >= 2000].sum()
    tot = p.sum()
    return lv - lv.max(), 10 * np.log10(body / sub), 10 * np.log10(top / tot)


def env_rms(x, w):
    k = max(N(w), 1)
    c = np.cumsum(np.r_[0.0, x ** 2])
    e = np.sqrt(np.maximum((c[k:] - c[:-k]) / k, 1e-24))
    return np.r_[np.full(k // 2, e[0]), e, np.full(len(x) - len(e) - k // 2, e[-1])]


def attack(x):
    """The first blow's front: from 10 % of the loudest 5 ms level to 80 % of the most it reaches in the next 150 ms
    (ms), and when."""
    e5 = env_rms(x, 0.005)
    top = e5.max()
    i10 = int(np.argmax(e5 >= 0.1 * top))
    seg = e5[i10:i10 + N(0.15)]
    i80 = int(np.argmax(seg >= 0.8 * seg.max()))
    return i80 / SR * 1000, (i10 + i80) / SR


def clicks(x):
    """Sharp broadband fronts (what snare cracks, clicks and patter are made of): moments where the >1.5 kHz band's
    1 ms level jumps 12 dB over its 60 ms median within 5 ms, loud enough to matter (within 35 dB of the file's
    loudest 1 ms)."""
    hb = bp(x, 1500, None, 4)
    e1 = env_rms(hb, 0.001)
    full = env_rms(x, 0.001).max()
    med = signal.medfilt(e1[::44], 61)
    med = np.repeat(med, 44)[: len(e1)]
    hot = (e1 > 4 * med) & (e1 > full * 10 ** (-35 / 20))
    # (count separate events)
    idx = np.where(hot)[0]
    if len(idx) == 0:
        return 0
    return int(1 + np.sum(np.diff(idx) > N(0.02)))


THIRD_FC = [160, 250, 400, 630, 1000, 1600]


def flutter(x):
    """Fast shaking of loudness (grainy, flickery roars are made of it: 20-80 Hz is where roughness lives). In each
    third octave from 160 Hz to 1.6 kHz that matters (within 30 dB of the strongest third octave, lows included), the envelope's 20-80 Hz depth
    against plain noise in the same band given the same slow (under 6 Hz) envelope: 1.0 = as smooth as plain noise
    can be, so any excess is shaking the sound adds. Returns the worst band's ratio and the strongest single rate's
    prominence in that range (dB; a buzz or a beat stands out as a peak)."""
    q = R(99)
    lv = []
    for fc in THIRD_FC:
        lv.append(np.sqrt(np.mean(bp(x, fc / 2 ** (1 / 6), fc * 2 ** (1 / 6), 3) ** 2)))
    lv = np.array(lv)
    # (a band counts if it is within 30 dB of the strongest third octave anywhere from 25 Hz up, the lows included: a
    # band further down than that under a sub-heavy sound is masked. Round 1 compared only 160 Hz-1.6 kHz with each
    # other, which counted the faint harmonics a few dark round-2 files leave 50-60 dB under their lows.)
    ref = max(np.sqrt(np.mean(bp(x, fc / 2 ** (1 / 6), fc * 2 ** (1 / 6), 3) ** 2)) for fc in (25, 31.5, 40, 50, 63, 80, 100, 125))
    ref = max(ref, lv.max())
    worst, prom = 0.0, 0.0
    dec = 21
    sr2 = SR / dec
    for fc, l in zip(THIRD_FC, lv):
        if l < ref * 10 ** (-30 / 20):
            continue
        b = bp(x, fc / 2 ** (1 / 6), fc * 2 ** (1 / 6), 3)
        e = signal.decimate(np.abs(signal.hilbert(b)), dec, zero_phase=True)
        slow_e = np.maximum(bp_rate(e, sr2, None, 6), 1e-12)
        on = slow_e > 0.1 * np.percentile(slow_e, 99)
        z = bp(q.standard_normal(len(x)), fc / 2 ** (1 / 6), fc * 2 ** (1 / 6), 3)
        ez = signal.decimate(np.abs(signal.hilbert(z)), dec, zero_phase=True)
        ez = ez / np.mean(ez) * slow_e[: len(ez)]
        dx = np.sqrt(np.mean((bp_rate(e, sr2, 20, 80) / slow_e)[on] ** 2))
        dz = np.sqrt(np.mean((bp_rate(ez, sr2, 20, 80) / slow_e)[on] ** 2))
        worst = max(worst, dx / dz)
        ff, pp = signal.welch(((e - slow_e) / slow_e) * on, sr2, nperseg=2048)
        bnd = (ff >= 20) & (ff <= 80)
        prom = max(prom, 10 * np.log10(pp[bnd].max() / (np.median(pp[bnd]) + 1e-30)))
    return worst, prom


def bp_rate(e, sr, lo, hi):
    if lo:
        sos = signal.butter(2, [lo, hi], "bandpass", fs=sr, output="sos")
    else:
        sos = signal.butter(2, hi, "lowpass", fs=sr, output="sos")
    return signal.sosfiltfilt(sos, e)


def ringing(x):
    """Narrow high partials (clinks, dings, chimes): over 1-8 kHz, the most any narrow peak stands over its own third
    octave's median (dB), counting only peaks within 45 dB of the loudest point of the spectrum."""
    f, p = signal.welch(x, SR, nperseg=16384)
    m = (f >= 1000) & (f <= 8000)
    lp = 10 * np.log10(p + 1e-30)
    worst = 0.0
    top = lp.max()
    for i in np.where(m)[0][::2]:
        w = (f > f[i] / 2 ** (1 / 6)) & (f < f[i] * 2 ** (1 / 6))
        if lp[i] > top - 45:
            worst = max(worst, lp[i] - np.median(lp[w]))
    return worst


def shares(x):
    """The 800 Hz-3 kHz and the over-3 kHz shares of the whole (dB): round 1's rejected files had 10 dB more of both
    than the approved ones."""
    f, p = signal.welch(x, SR, nperseg=16384)
    tot = p.sum()
    return 10 * np.log10(p[(f >= 800) & (f < 3000)].sum() / tot), 10 * np.log10(p[f >= 3000].sum() / tot + 1e-30)


def low_tone(x):
    """A low note standing out (a bong or a hum): over 25-400 Hz, the most any narrow peak (0.7 Hz bins) stands over its
    third octave's median, within 30 dB of the spectrum's top (dB)."""
    f, p = signal.welch(x, SR, nperseg=65536)
    lp = 10 * np.log10(p + 1e-30)
    m = np.where((f >= 25) & (f <= 400))[0]
    top = lp[m].max()
    worst = 0.0
    for i in m[::3]:
        if lp[i] < top - 30:
            continue
        w = (f > f[i] / 2 ** (1 / 6)) & (f < f[i] * 2 ** (1 / 6))
        worst = max(worst, lp[i] - np.median(lp[w]))
    return worst


def dip(x, until):
    """The most the 400 ms level falls below what it already reached, before `until` s (a build must never dip)."""
    e = st_rms(x)[:: N(0.05)]
    ts = np.arange(len(e)) * 0.05 + 0.2
    e = 20 * np.log10(e[ts < until] + 1e-12)
    run = np.maximum.accumulate(e)
    ok = run > run.max() - 40
    return float((run - e)[ok].max())


def limiter(x, block=1024):
    """The game's output limiter (horizon-client audio.rs): a peak over 1 held for the block, released over 0.2 s."""
    y = x.copy()
    peak_hold = 1.0
    rel = np.exp(-1 / (0.2 * SR))
    gains = np.empty(len(x))
    for a in range(0, len(x), block):
        seg = y[a:a + block]
        pk = max(1.0, np.abs(seg).max())
        peak_hold = max(peak_hold, pk)
        g = np.empty(len(seg))
        for i in range(len(seg)):
            g[i] = 1 / peak_hold
            peak_hold = max(peak_hold * rel, pk)
        y[a:a + block] = seg * g
        gains[a:a + block] = g
    return y, gains


def measure(name, x):
    lv, body_db, top_db = bands(x)
    att, at = attack(x)
    fl, prom = flutter(x)
    out = {
        "file": name, "s": round(len(x) / SR, 2), "peak_dbfs": round(20 * np.log10(np.abs(x).max()), 1),
        "loudest_400ms_dbfs": round(20 * np.log10(st_rms(x).max()), 1),
        "octaves_db": {str(c): round(v, 1) for c, v in zip(OCTS, lv)},
        "body_100_800_vs_sub_db": round(body_db, 1), "over_2k_share_db": round(top_db, 1),
        "front_ms": round(att, 1), "front_at_s": round(at, 2), "sharp_fronts": clicks(x),
        "mid_800_3k_db": round(shares(x)[0], 1), "top_3k_db": round(shares(x)[1], 1), "low_tone_db": round(low_tone(x), 1),
        "flutter_vs_noise": round(fl, 2), "flutter_peak_db": round(prom, 1), "ringing_db": round(ringing(x), 1),
    }
    if name in ("sign", "sign_short", "dive"):
        out["dip_before_peak_db"] = round(dip(x, {"sign": SIGN_PEAK, "sign_short": SIGN_SHORT_PEAK, "dive": DIVE_HIT}[name]), 2)
    return out


def measure_dir(folder, names=None):
    rows = []
    for p in sorted(Path(folder).glob("*.ogg")):
        if names and p.stem not in names:
            continue
        x = load(p)
        rows.append(measure(p.stem, x))
        r = rows[-1]
        o = " ".join(f"{v:5.0f}" for v in r["octaves_db"].values())
        extra = f" dip {r['dip_before_peak_db']:.2f}" if "dip_before_peak_db" in r else ""
        print(f"{r['file']:15s} {r['s']:5.1f}s pk {r['peak_dbfs']:5.1f} L {r['loudest_400ms_dbfs']:5.1f} | {o} | body {r['body_100_800_vs_sub_db']:5.1f}"
              f" >2k {r['over_2k_share_db']:5.1f} | front {r['front_ms']:5.1f}ms sharp {r['sharp_fronts']} | flut {r['flutter_vs_noise']:4.2f}"
              f" ({r['flutter_peak_db']:4.1f}) ring {r['ringing_db']:4.1f} | mid {r['mid_800_3k_db']:5.1f} top {r['top_3k_db']:5.1f} tone {r['low_tone_db']:4.1f}{extra}")
    print("octaves:", OCTS)
    return rows


# ======================================================================================================================
# the strike as the game plays it, and the review
# ======================================================================================================================
def vol_big(d):
    return min(1.0, 1.5 / (1 + d / 500))


def vol_small(d):
    return min(1.0, 1.3 / (1 + d / 350))


def vol_bite(d):
    """The bite carries furthest: the biggest thing in the strike."""
    return min(1.0, 1.9 / (1 + d / 500))


def far_share(d, near=250.0, all_=700.0):
    return float(ss((d - near) / (all_ - near)))


BREACH_AT = {"A": 0.6, "B": 0.25, "C": 0.2, "D": 0.9, "E": 0.6, "F": 0.6, "G": 0.6, "X": 0.6}
BREACH_CLOSE = "close"   # round 5: "close" or "close_b"
CLOSE_TIERS = True


def tiers3(d):
    """we_sounds.rs's tiers3: the close, mid and far shares at d blocks."""
    c = 1 - float(ss((d - 90) / 110))
    f = float(ss((d - 450) / 250))
    return c, max(1 - c - f, 0.0), f


def nearness(d):
    return 1 - float(ss((d - 40) / 130))   # each breach take's beat in its file (we_sounds.rs's breach_at)
SINK_SET = "slump"
SETTLE_PICK = "settle_d"
GULP_PICK = "gulp_d"


def script_cues(dist, bellow=None, bite=None, seed=1, breach=None, tail=None, sinks=None, settle_=None):
    """The scripted strike's cues for a player `dist` blocks from the breach, square to the line (`t file volume
    pitch`): the cue sheet, as code. Sound comes late by its distance through the air (343 b/s)
    and the ground's quake five times sooner; the sky's (the bellow) late at most 0.6 s so it stays on its jaws."""
    bellow = (bellow or BELLOW_PICK).lower()
    bite = (bite or BITE_PICK).lower()
    breach = (breach or BREACH_PICK).upper()
    tail = (tail or TAIL_PICK).lower()
    sinks = sinks or SINK_SET
    settle_ = settle_ or SETTLE_PICK
    rng = R(seed)
    dB = dist
    dD = float(np.hypot(dist, WE_SPAN))
    cues = []

    def add(t, f, v, p=1.0):
        if v > 0.003:
            cues.append((max(t, 0.0), f, min(v, 1.0), p))

    vb, fsB = vol_big(dB), far_share(dB)
    # (the sign peaks as the breach's blow is heard: it carries the land's rumble right up to it, at any distance)
    add(WE_BREACH + dB / V_AIR - HIT_AT - SIGN_PEAK, "sign", vb)
    add(WE_BREACH + dB / V_GROUND - HIT_AT, "quake1", 0.75 / (1 + dB / 700))
    if breach == "X":
        cw, mw, fw = tiers3(dB)
        tb = WE_BREACH + dB / V_AIR - BREACH_AT["X"]
        add(tb, f"breach_{BREACH_CLOSE}", vb * cw)
        add(tb, "breach_mid", vb * mw)
        add(tb, "breach_far", vb * fw)
    else:
        add(WE_BREACH + dB / V_AIR - BREACH_AT[breach], f"breach_{breach.lower()}", vb * (1 - fsB))
        add(WE_BREACH + dB / V_AIR - BREACH_AT[breach], f"breach_{breach.lower()}_far", vb * fsB)
    # (round 5: the burrowing close by, along the first approach: W0 to B, the head charging in, 30 to 140 b/s)
    for j, t in enumerate(np.arange(0.0, WE_BREACH - 2.0, 3.0)):
        u = min((t + 2.0) / WE_BREACH, 1.0)
        along = WE_SIGN * (1 - (1 - u) ** 1.0) ** 1.6
        dm = float(np.hypot(dB, WE_SIGN - along))
        add(t + dm / V_GROUND, f"grind{1 + (j + seed) % 3}", 0.95 * nearness(dm), 1.0)
    # (round 5: the breach hole's rim breaking while the body pours out, until the tail is out)
    for j, t in enumerate(np.arange(WE_BREACH + 0.8, WE_TAIL_OUT - 1.5, 4.0)):
        add(t + dB / V_AIR, f"rim{1 + j % 3}", 0.7 * nearness(dB) * (0.45 + 0.55 * np.exp(-(t - WE_BREACH - 0.8) / 8)))
    add(WE_BREACH + 0.3 + dB / V_AIR, "rise", vb * 0.9)
    dS = float(np.hypot(dB, WE_APEX))
    lag = min(dS / V_AIR, 0.6)
    fsS = far_share(dS, 300, 800)
    add(WE_BELLOW[0] - BELLOW_LEAD + lag, f"bellow_{bellow}", vol_big(dS) * (1 - fsS))
    add(WE_BELLOW[0] - BELLOW_LEAD + lag, f"bellow_{bellow}_far", vol_big(dS) * fsS)
    vD, fsD = vol_bite(dD), far_share(dD)
    add(WE_BITE + dD / V_AIR - DIVE_HIT, "dive", vol_bite(dD) * 0.9)
    add(WE_BITE + dD / V_GROUND - HIT_AT, "quake2", 0.75 / (1 + dD / 700))
    if CLOSE_TIERS and bite == "c":
        cw, mw, fw = tiers3(dD)
        add(WE_BITE + dD / V_AIR - HIT_AT, "bite_close", vD * cw)
        add(WE_BITE + dD / V_AIR - HIT_AT, "bite_mid", vD * mw)
        add(WE_BITE + dD / V_AIR - HIT_AT, "bite_c_far", vD * fw)
    else:
        add(WE_BITE + dD / V_AIR - HIT_AT, f"bite_{bite}", vD * (1 - fsD))
        add(WE_BITE + dD / V_AIR - HIT_AT, f"bite_{bite}_far", vD * fsD)
    for j, t in enumerate(np.arange(WE_BITE + 0.8, WE_TAIL_IN - 1.5, 4.0)):
        add(t + dD / V_AIR, f"rim{1 + (j + 1) % 3}", 0.7 * nearness(dD) * (0.45 + 0.55 * np.exp(-(t - WE_BITE - 0.8) / 8)))
    dM = float(np.hypot(np.hypot(dB, WE_SPAN / 2), 180))
    for k, t in enumerate([19.4, 23.6, 27.8]):
        add(t + dM / V_AIR, f"body{1 + k % 2}", vol_big(dM) * 0.85, 1.0 - 0.03 * k)
    add(WE_TAIL_OUT - TAIL_AT + dB / V_AIR, f"tail_{tail}", vol_small(dB) * 1.2)
    add(WE_TAIL_IN - HIT_AT + dD / V_AIR, "tail_in", vol_small(dD) * 1.2)
    rings = 12
    count = 6 if sinks == "sink" else 3
    for k in range(rings):
        s = WE_SPAN * k / (rings - 1)
        tk = WE_SINK[0] + 0.3 + 7.6 * (k / (rings - 1)) ** 0.9 + rng.uniform(-0.12, 0.12)
        dk = float(np.hypot(dB, s))
        v = (seed % count + (count - 1) * (k % count)) % count
        vv, pp = vol_small(dk) * rng.uniform(0.85, 1.05), float(rng.uniform(0.9, 1.08))
        if CLOSE_TIERS and sinks == "slump":
            cw = tiers3(dk)[0]
            add(tk + dk / V_AIR - HIT_AT, f"slump_close{v + 1}", vv * cw, pp)
            add(tk + dk / V_AIR - HIT_AT, f"{sinks}{v + 1}", vv * (1 - cw), pp)
        else:
            add(tk + dk / V_AIR - HIT_AT, f"{sinks}{v + 1}", vv, pp)
    add(38.6 + dM / V_AIR, settle_, vol_big(dM) * 0.9)
    return sorted(cues)


def caught_cues(at=19.0):
    """The Caught sequence (the bite closing over the player at `at`): the gulp, two passes of the throat, the spit
    at the next surfacing (on picture: they are inside it)."""
    th = f"throat_{THROAT_PICK.lower()}"
    return [(at - GULP_SHUT, GULP_PICK, 1.0, 1.0), (at + 0.5, th, 0.9, 1.0), (at + 0.5 + THROAT_S, th, 0.9, 1.0),
            (at + 0.5 + 9.0 - SPIT_AT, "spit", 1.0, 1.0), (at + 0.5 + 9.0 - SPIT_AT + 0.12, th, None, 1.0)]


def mix(cues, files, length=None, limit=True):
    """The cues as the game mixes them: mono files, each started on a 20 Hz tick, at its volume, pitch as speed, all
    summed and through the game's limiter."""
    length = length or (max(t for t, *_ in cues) + 12.0)
    cues = sorted(cues, key=lambda c: c[0])
    acc = np.zeros(N(length))
    # (a stop, volume None: that file's sounds already started are cut off there, as `stopsound`)
    stops = {}
    for t, f, v, p in cues:
        if v is None:
            stops.setdefault(f, []).append(t)
    for t, f, v, p in cues:
        if v is None:
            continue
        x = files[f]
        if abs(p - 1) > 1e-4:
            pos = np.arange(0, len(x) - 1, p)
            i = pos.astype(int)
            fr = pos - i
            x = x[i] * (1 - fr) + x[i + 1] * fr
        i0 = N(round(t * 20) / 20)
        m = min(len(x), len(acc) - i0)
        for ts in stops.get(f, []):
            if ts >= t:
                m = min(m, N(round(ts * 20) / 20) - i0)
        if m > 0:
            acc[i0:i0 + m] += x[:m] * v
    if not limit:
        return acc, None
    return limiter(acc)


def lufs(path):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    return float([l for l in r.splitlines() if l.strip().startswith("I:")][-1].split()[1])


def write_mp3(path, x, gain_db=None, target=-16.0):
    """For the review: at `target` LUFS (or `gain_db`), the loudest instants bent under -1 dBFS, as an MP3 (V0)."""
    tmp = str(path) + ".wav"

    def wav(y):
        with wave.open(tmp, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())

    def bend(y):
        c, k = 0.89, 0.75
        a = np.abs(y)
        return np.where(a > k, np.sign(y) * (k + (c - k) * np.tanh((a - k) / (c - k))), y)

    if gain_db is None:
        y = x / (np.abs(x).max() + 1e-9) * 0.5
        g = 0.0
        for _ in range(3):
            wav(bend(y * 10 ** (g / 20)))
            g += target - lufs(tmp)
        gain_db = g + 20 * np.log10(0.5 / (np.abs(x).max() + 1e-9))
    y = bend(x * 10 ** (gain_db / 20))
    wav(y)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libmp3lame", "-q:a", "0", str(path)], check=True)
    loud = lufs(tmp)
    os.remove(tmp)
    return gain_db, loud


REVIEW = [
    # (file, title, what it is)
    ("sign", "Wormsign (into the breach)", "0-9 s: something enormous moving under the land toward you; only grows, ends on the breach."),
    ("sign_short", "Wormsign, short (hunt)", "The 4.5 s build before each later surfacing in HUNT."),
    ("move1", "Under the land (hunt)", "The mound steering after you between surfacings; laid end to end by the plan."),
    ("breach1", "Breach 1, near", "The head punching out: one deep blow, earth bursting, then the pour of earth off it."),
    ("breach2", "Breach 2, near", "A later surfacing: a double heave."),
    ("breach3", "Breach 3, near", "A later surfacing: a slow bulge, then a harder burst."),
    ("breach1_far", "Breach 1, far (800 blocks)", "The same through 800 blocks of air: top taken, fronts softened, the land's echoes."),
    ("quake1", "Ground quake", "What arrives through the ground first, five times sooner than the air's blow."),
    ("rise", "Rise", "9-14 s: the stone mass climbing 250 blocks, air shoved, earth pouring off; leans into the bellow."),
    ("dive", "Dive", "14.5-19 s: the arc over and down; air in front of the head builds into the bite."),
    ("body1", "Body passing", "19-31 s: the body pouring through the arch overhead; laid end to end with body2."),
    ("tail_out", "Tail out", "27 s: one deep whip of air and mass out of the breach hole. No crack."),
    ("tail_in", "Tail in", "31 s: the tail plunging into the bite hole; a muffled deep thud under the land."),
    ("sink1", "Tunnel ring 1", "31-40 s: one ring of the tunnel dropping; six variants, rotated and re-pitched."),
    ("sink2", "Tunnel ring 2", "A second slump after the first."),
    ("sink3", "Tunnel ring 3", "A slower lead-in push, then the drop."),
    ("settle", "Settling", "40-46 s: the land settling; lets go over seven seconds."),
    ("gulp", "Caught: gulp", "The mouth closing over you: the outside shut out over a second, pressure, a huge soft close."),
    ("throat", "Caught: throat (loop)", "Inside: a heartbeat the size of a hill, the outside low-passed, air rushing past. Loops."),
    ("spit", "Caught: spit", "Thrown out: a burst of air, the world's sound opening back up, a deep huff."),
]
TAKES = {
    "bellow_a": ("Bellow take A: Throat", "A voice: seven detuned smooth pulse sources round 31 Hz filtered by the throat's formants, which rise as the jaws open (oo to aa, a mountain wide), breath under it.",
                 "Source-filter voice model (additive, exact formants); the only take whose colour is a vowel that moves."),
    "bellow_b": ("Bellow take B: Mountain horn", "Low brass: eight horns on low C and its octave, brightness growing with how hard they blow, a scoop into the note, into sympathetic resonance and a vast dark hall (the Inception idea).",
                 "Brass dynamics model: brightness tied to loudness, a fixed musical pitch, a long ringing hall."),
    "bellow_c": ("Bellow take C: Cavern", "No oscillator: breath driven through the resonances of a stone cylinder (its lengthwise and cross modes, inharmonic), so the tone is born from moving air; a deep pressure swell under it.",
                 "Noise-excited modal model: inharmonic, breathing, no fixed pitch; the most 'vast tube / cave' and least musical."),
    "bellow_d": ("Bellow take D: Bore", "A physical model of a blown tube (STK-style reed bore): three bores (31, 31.6, 46.5 Hz), the valve's bloom opening the tone as it swells; hollow odd harmonics of a closed pipe.",
                 "Waveguide physical model: odd harmonics only (hollow), its brightness from the model's own nonlinearity."),
    "bite_a": ("Bite take A: Hammer", "One colossal blow of the ground's lowest modes, the land going in (a falling rush), the jaws' closing thud 0.8 s on, a ground wave.",
               "The first blow is the peak; the most direct and punchy."),
    "bite_b": ("Bite take B: Swallow", "A smaller first blow, then the land sucked in for a second (an inhale the size of a hill), the closing thud the peak and the deepest blow.",
               "The close is the peak, after a one-second suck in: an event, less a hit."),
    "bite_c": ("Bite take C: Quake", "The blow, then the ground wave rolling away as three surges, each lower and longer; the closing thud buried in it.",
               "Seismic: the longest low tail, the land heaving after."),
}


def review(outdir):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    files = {p.stem: load(p) for p in sorted(OUT.glob("*.ogg"))}
    items = []
    for name, title, what in REVIEW:
        g, l = write_mp3(outdir / f"{name}.mp3", files[name])
        items.append({"file": f"{name}.mp3", "title": title, "what": what, "lufs": round(l, 1)})
    for name, (title, what, diff) in TAKES.items():
        for far in (False, True):
            key = name + ("_far" if far else "")
            fn = f"{name.replace('_', '_take_')}{'_far' if far else ''}.mp3".replace("_take_a", "_take_A").replace("_take_b", "_take_B").replace("_take_c", "_take_C").replace("_take_d", "_take_D")
            g, l = write_mp3(outdir / fn, files[key])
            items.append({"file": fn, "title": title + (" (800 blocks)" if far else ""), "what": what if not far else "The same take through 800 blocks of air.",
                          "different": diff, "take": True, "lufs": round(l, 1)})
    mixes = {}
    for d in (250, 800):
        y, gains = mix(script_cues(d), files, 48.0)
        mixes[d] = (y, gains)
    g, l = write_mp3(outdir / "strike_250_blocks.mp3", mixes[250][0])
    g2, l2 = write_mp3(outdir / "strike_800_blocks.mp3", mixes[800][0], gain_db=g)
    for d, gl, ll in ((250, g, l), (800, g2, l2)):
        gains = mixes[d][1]
        items.append({"file": f"strike_{d}_blocks.mp3", "title": f"The whole scripted strike from {d} blocks",
                      "what": f"Every cue as the game plays it (mono, 20 Hz ticks, its limiter), the player {d} blocks from the breach; bellow take {BELLOW_PICK}, bite take {BITE_PICK}. Both mixes at the same gain, so the 800 one is quieter as it should be.",
                      "lufs": round(ll, 1), "game_limiter_max_db": round(-20 * np.log10(gains.min()), 1)})
    y, gains = mix(caught_cues(DIVE_HIT) + [(0.0, "dive", 0.9, 1.0)], files, 20.0)
    g3, l3 = write_mp3(outdir / "caught_sequence.mp3", y)
    items.append({"file": "caught_sequence.mp3", "title": "Caught: the whole sequence", "what": "The dive, the gulp as the mouth closes over you, ~9 s down the throat, the spit.", "lufs": round(l3, 1)})
    (outdir / "review.json").write_text(json.dumps({"laser": "worldeater", "round": 1, "picks": {"bellow": BELLOW_PICK, "bite": BITE_PICK}, "items": items}, indent=1))
    print("wrote", len(items), "review files to", outdir)
    for d in (250, 800):
        print(f"mix {d}: game limiter at most {-20 * np.log10(mixes[d][1].min()):.1f} dB")


# ---- round 3: one synthesized attempt at the smash, over breach A (review only, not in the mod) -------------------------
def smash_layer(n, t0, rng):
    """SYNTHETIC. A mountain of stone breaking up through rock and earth, as structure rather than a wash of noise:
      a fracture boom (the rock failing at once: low modes struck by an 8 ms push, its top at 600 Hz);
      a tearing roar whose centre moves (180 -> 600 -> 220 Hz over 2 s) made of a train of fracture bursts (each 40-150
        ms with a soft 15 ms front, 4-14 a second, their sizes power-law: a few big, many small) rather than steady noise;
      masses falling back (a dozen blocks thrown up by the head, landing 0.7-3.6 s on: each a heavy low thud of its own
        pitch and size with a short low-mid crunch, the big ones heard one by one);
      the avalanche tail (rubble sliding off the body and down the heap: many soft overlapping slides, their rate falling
        from ~40 to ~5 a second over five seconds, its colour sinking)."""
    t = tt(n)
    # fracture boom
    boom = modes(n, t0 - 0.004, np.array([28.0, 39, 53, 72, 98, 132]) * rng.uniform(0.95, 1.05, 6), [0.5, 0.38, 0.28, 0.2, 0.14, 0.1], [1, 1, 0.9, 0.75, 0.6, 0.45], 0.004, rng)
    boom = bp(boom, None, 600, 2)
    # the tearing roar: a moving hump, gated by a train of fracture bursts

    def tear_mag(tc, f):
        v = tc - t0
        c = 180 * (600 / 180) ** ss(v / 0.5) * (220 / 600) ** ss((v - 0.5) / 1.5)
        lf = np.log2(np.maximum(f, 1) / c)
        return np.exp(-0.5 * (lf / 0.75) ** 2) * floor_cut(f, 60, 2200, 2)
    tear = shaped(n, rng, tear_mag, frame=4096, hop=1024)
    gate = np.zeros(n)
    tb = t0
    while tb < t0 + 2.6:
        rate = 14 * np.exp(-(tb - t0) / 1.2) + 4
        ln = rng.uniform(0.04, 0.15)
        g = rng.pareto(1.6) + 0.3
        gate += min(g, 4.0) * ss((t - tb) / 0.015) * np.exp(-np.maximum(t - tb, 0) / ln)
        tb += rng.exponential(1 / rate)
    tear = tear * gate * np.exp(-np.maximum(t - t0, 0) / 1.6)
    # masses falling back
    masses = np.zeros(n)
    for j in range(12):
        tl = t0 + 0.7 + 2.9 * rng.beta(1.4, 2.0)
        size = min(rng.pareto(1.3) + 0.4, 3.0)
        f0 = 120 / (1 + size) * rng.uniform(0.8, 1.2)
        thud = modes(n, tl, np.array([1.0, 1.45, 2.1]) * max(f0, 28), [0.25 * size, 0.18 * size, 0.12 * size], [1, 0.6, 0.3], 0.012 + 0.008 * size, rng)
        crunch = bp(rng.standard_normal(n), 150, 700, 2) * ss((t - tl) / 0.008) * np.exp(-np.maximum(t - tl, 0) / 0.05) * (t >= tl)
        masses += size * (pk(thud) + 0.25 * pk(crunch))
    # the avalanche tail
    slide = np.zeros(n)
    tb = t0 + 0.4
    while tb < t0 + 6.5:
        rate = 40 * np.exp(-(tb - t0 - 0.4) / 1.8) + 5
        ln = rng.uniform(0.08, 0.3)
        slide += rng.uniform(0.2, 1.0) * ss((t - tb) / 0.03) * np.exp(-np.maximum(t - tb, 0) / ln)
        tb += rng.exponential(1 / rate)

    def slide_mag(tc, f):
        v = max(tc - t0, 0)
        top = 900 * np.exp(-v / 3.0) + 200
        return floor_cut(f, 50, top, 2) * tilt(f, 150, -1.5)
    aval = shaped(n, rng, slide_mag, frame=4096, hop=1024) * slide * np.exp(-np.maximum(t - t0, 0) / 2.2)
    return 1.0 * pk(boom) + 0.55 * pk(tear) + 0.6 * pk(masses) + 0.35 * pk(aval)


def breach_a_smash(far=False):
    """SYNTHETIC: breach A (Heave) with the smash layer over it, its beat where breach A's is."""
    base, t0 = breach_A(far=False)
    rng = R(2301)
    n = len(base)
    sm = smash_layer(n, t0, rng)
    sm = space(sm, rng, 3.0, 1.3, 0.6, 0.2, early=[(0.5, 0.18, 900), (1.1, 0.1, 600)], wet=0.25)[:n]
    x = pk(base) + 0.8 * pk(sm)
    x = drive(weight(x, 22, 110, 0.4))
    if far:
        x = distant(x, 800, rng)[:n]
    return fade(lowcut(x), 0, 1.2)


def review3(outdir):
    """Round 3: the synthetic smash over breach A, beside breach A as it is, near and far, at -16 LUFS."""
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    items = []
    for far in (False, True):
        x = level(breach_a_smash(far), LEVELS["breach_far" if far else "breach"])
        fn = f"breach_A_smash_SYNTHETIC{'_far' if far else ''}.mp3"
        g, l = write_mp3(outdir / fn, x)
        print(fn, measure(fn, x))
        items.append({"file": fn, "title": "Breach A + smash (SYNTHETIC)" + (" (800 blocks)" if far else ""),
                      "what": "Breach A (Heave) with a synthesized smash over it: a fracture boom, a tearing roar built of fracture bursts with a moving centre, a dozen masses falling back one by one, an avalanche tail. All synthesized: to compare against a version made from real recordings.",
                      "changed": "Round 2's breach A had the ground's movement and nothing of rock breaking; this adds the breaking.", "lufs": round(l, 1)})
        base = load(OUT / f"breach_a{'_far' if far else ''}.ogg")
        fn = f"breach_A_as_round2{'_far' if far else ''}.mp3"
        g, l = write_mp3(outdir / fn, base)
        items.append({"file": fn, "title": "Breach A as in round 2" + (" (800 blocks)" if far else ""), "what": "For comparison, unchanged.", "lufs": round(l, 1)})
    (outdir / "review.json").write_text(json.dumps({"laser": "worldeater", "round": 3, "items": items}, indent=1))


# The references' measurements (round 4; the recordings themselves are never read here, never in the repo: measured
# only, as a reference for the synthesis). Third octaves 25 Hz-8 kHz in dB under the loudest band of the first 10 s, in
# the windows SMASH_WINS (s from the event's onset); impacts a second in SMASH_DENS_WINS; impact sizes (median, 90th
# percentile dB under the biggest, how many within 6 dB, count); T10/T20/T30 from the loudest 400 ms; the share of
# the first 8 s under 100 Hz, 100-800, 800 Hz-3 kHz, over 3 kHz; the 300 Hz-3 kHz band's log-envelope modulation
# (dB) at 0.5-2, 2-8, 8-20, 20-80 Hz; how far the 300 Hz-3 kHz band's onset trails the <120 Hz band's, and its peak
# the <120 Hz band's (ms).
REF = {'blast': {'banned': {'flutter': 2.16, 'low_tone': 6.7, 'ringing': 4.3, 'sharp_fronts': 32},
           'decay': [1.12, 5.9, 10.97],
           'dens': [18.0, 10.7, 5.0, 11.8],
           'lead': [-238, -2223],
           'mod': [-14.9, -24.6, -25.8, -27.1],
           'onset': 0.2,
           'shares': [-0.6, -9.3, -26.1, -46.8],
           'sizes': [-20.3, -4.5, 20, 132],
           'source': 'Freesound 475780, felix.blume, "Big dynamite explosion in an open mine (Chile)", CC0',
           'thirds': [[-24.5, -21.2, -24.2, -22.6, -25.9, -17.4, -12.8, -13.4, -18.3, -20.2, -18.4, -20.8, -22.3,
                       -28.0, -28.9, -33.8, -33.4, -36.3, -39.1, -42.8, -49.3, -52.5, -55.4, -57.1, -60.9, -63.1],
                      [-8.3, 0.5, -0.3, -1.6, -1.9, -1.2, -1.7, -4.3, -9.1, -5.1, -7.0, -7.5, -9.6, -11.0, -10.2,
                       -12.1, -15.1, -19.9, -22.7, -28.6, -33.8, -35.6, -38.2, -43.4, -44.8, -48.6],
                      [-2.4, -0.5, -0.9, -1.9, -1.8, -2.1, -2.7, -3.7, -5.4, -7.2, -6.6, -8.6, -10.0, -10.6, -11.6,
                       -14.5, -16.3, -20.3, -25.5, -28.4, -31.3, -35.8, -39.7, -42.6, -45.4, -48.9],
                      [2.6, 4.2, 2.4, 0.7, 1.7, -1.3, -3.8, -6.6, -10.7, -14.8, -17.2, -23.1, -27.0, -30.4, -32.9,
                       -33.3, -34.4, -37.3, -41.5, -45.4, -51.7, -60.4, -68.7, -71.4, -72.7, -74.4],
                      [-12.3, -12.5, -14.6, -14.3, -13.6, -14.9, -14.3, -14.1, -14.1, -14.6, -16.1, -19.0, -21.8,
                       -26.1, -31.6, -34.5, -37.2, -38.7, -38.8, -45.6, -50.4, -56.7, -63.4, -67.7, -69.1, -71.0]]},
 'collapse': {'banned': {'flutter': 1.17, 'low_tone': 9.4, 'ringing': 5.9, 'sharp_fronts': 5},
              'decay': [0.73, 1.64, 2.58],
              'dens': [6.0, 0.7, 1.0, 0.0],
              'lead': [-1, -22],
              'mod': [-13.5, -30.3, -31.3, -32.3],
              'onset': 10.05,
              'shares': [-2.2, -4.4, -14.2, -30.7],
              'sizes': [-12.7, -2.5, 2, 9],
              'source': 'Freesound 125937, alienistcog, "merrimack-st-demolition.aif", CC0',
              'thirds': [[-35.0, -33.5, -33.0, -31.4, -25.4, -35.0, -37.6, -36.6, -43.8, -44.6, -44.1, -44.3, -39.2,
                          -42.0, -39.3, -40.9, -44.2, -44.7, -46.5, -48.5, -53.2, -52.0, -56.2, -61.1, -63.2, -64.8],
                         [0.0, -1.4, 3.7, 12.7, 12.5, 6.1, 7.6, 8.3, 7.3, 1.9, 2.0, 0.3, 1.3, -1.6, 0.9, -0.2, -1.8,
                          -3.3, -6.5, -8.8, -11.3, -14.0, -18.5, -19.5, -24.2, -28.0],
                         [-13.6, -6.2, -5.8, -2.8, -0.5, 0.5, 0.6, -0.0, -2.8, -2.7, -4.4, -4.5, -5.1, -7.5, -6.6,
                          -7.7, -9.2, -10.4, -13.3, -16.4, -19.4, -23.6, -30.1, -36.2, -43.1, -48.0],
                         [-32.1, -27.7, -24.9, -19.7, -18.9, -21.7, -20.4, -21.6, -21.7, -21.4, -23.4, -23.2, -24.1,
                          -24.0, -24.1, -23.8, -23.0, -26.9, -29.2, -30.8, -34.8, -38.9, -44.0, -45.6, -46.3, -51.0],
                         [-37.6, -34.5, -36.7, -33.3, -24.0, -29.0, -28.4, -28.2, -29.9, -29.9, -29.1, -29.3, -28.2,
                          -27.6, -26.3, -25.7, -25.7, -27.7, -30.0, -32.1, -34.2, -37.1, -43.1, -48.1, -54.5,
                          -57.8]]},
 'far': {'banned': {'flutter': 2.23, 'low_tone': 2.6, 'ringing': 3.6, 'sharp_fronts': 102},
         'decay': [0.15, 8.78, None],
         'dens': [6.0, 14.7, 13.7, 13.8],
         'lead': [3604, 4565],
         'mod': [-16.5, -17.6, -20.3, -25.6],
         'onset': 2.5,
         'shares': [-8.2, -4.9, -3.1, -14.4],
         'sizes': [-24.3, -16.2, 1, 157],
         'source': 'Freesound 500638, betchkal, "Cathedral Mountain rock slide, slow blocky chunks", CC0',
         'thirds': [[-20.9, -16.9, -15.4, -13.2, -9.7, -11.8, -20.7, -25.2, -20.1, -18.3, -14.7, -8.2, -9.0, -6.8,
                     -10.3, -11.7, -10.5, -13.6, -11.4, -14.0, -13.5, -17.5, -20.5, -21.8, -28.1, -32.0],
                    [-20.7, -12.4, -15.1, -9.9, -0.6, -0.4, -7.4, -17.8, -13.4, -13.6, -9.8, -3.2, 3.7, 3.1, -3.6,
                     -1.0, -1.5, -1.5, 3.0, -2.2, -1.3, -8.9, -11.2, -12.8, -23.5, -34.9],
                    [-18.0, -10.4, -9.0, -6.7, -1.6, -0.3, -6.2, -14.0, -11.6, -8.2, -8.1, -3.1, -2.3, -2.0, -2.4,
                     -6.0, -1.6, -2.1, 0.7, -4.8, -7.5, -11.4, -13.6, -15.2, -21.4, -32.3],
                    [-15.3, -7.4, -9.7, -7.5, -5.9, -4.7, -9.0, -15.3, -17.9, -14.2, -11.0, -6.7, -4.7, -2.0, 0.3,
                     -1.8, -3.8, -5.7, -3.4, -3.4, -6.5, -8.8, -10.3, -12.1, -19.2, -30.7],
                    [-17.8, -13.0, -12.4, -12.0, -11.5, -11.6, -13.6, -18.4, -21.1, -19.6, -14.8, -10.4, -7.6, -5.5,
                     -2.9, -0.3, 1.4, 0.5, 0.7, -3.1, -5.6, -7.8, -8.8, -10.4, -17.7, -28.8]]},
 'rockfall': {'banned': {'flutter': 2.65, 'low_tone': 5.4, 'ringing': 8.2, 'sharp_fronts': 107},
              'decay': [0.23, 3.32, 13.29],
              'dens': [14.0, 9.3, 9.0, 8.2],
              'lead': [4447, 6382],
              'mod': [-8.0, -15.2, -18.9, -24.4],
              'onset': 0.25,
              'shares': [-9.7, -2.4, -5.2, -17.3],
              'sizes': [-23.3, -10.1, 5, 112],
              'source': 'Freesound 389303, AlanCat, "rockfall2a.wav", CC0',
              'thirds': [[-6.1, -11.4, -13.9, -7.7, -18.5, -15.9, -16.7, -18.1, -23.4, -22.5, -23.0, -26.4, -25.2,
                          -29.3, -28.8, -25.0, -21.5, -22.6, -21.8, -22.5, -24.9, -22.9, -25.9, -27.9, -29.7, -31.2],
                         [-9.9, -2.0, -5.6, -4.4, -4.7, -10.7, -14.9, -11.5, -6.5, -9.7, -11.6, -5.6, -6.4, -8.6,
                          -7.0, -3.7, -5.1, -4.4, -3.5, -3.6, -6.1, -9.3, -12.4, -12.3, -14.9, -17.9],
                         [-13.6, 0.1, -6.3, -8.0, -6.0, -4.3, -1.4, 0.3, 0.3, 3.5, 4.3, 0.9, -5.0, -4.1, -6.7, -4.3,
                          -1.0, -0.8, -0.0, -2.9, -4.8, -7.0, -9.4, -12.2, -16.2, -20.5],
                         [-19.5, -10.2, -14.1, -9.3, -8.9, -6.5, -7.5, -5.1, -8.0, -11.3, -11.7, -9.7, -6.1, -4.6,
                          -7.4, -3.3, -3.5, -1.2, -3.7, -5.8, -8.8, -11.9, -16.6, -18.3, -15.5, -25.5],
                         [-21.3, -11.6, -15.4, -14.0, -12.6, -13.6, -13.5, -10.2, -8.7, -3.6, -5.2, -7.8, -5.1, -2.6,
                          -1.1, -3.6, -5.2, -4.0, -4.6, -6.0, -8.9, -12.3, -16.8, -18.7, -17.6, -23.7]]}}
# (and per window of SMASH_DENS_WINS, impacts a second within 12 dB of the biggest, 12-20 dB under, 20-30 dB under)
REF_TIERS = {"blast": [[18.0, 0.0, 0.0], [10.0, 0.7, 0.0], [0.0, 0.0, 5.0], [0.2, 5.4, 6.2]], "rockfall": [[6.0, 2.0, 6.0], [2.0, 2.7, 4.7], [1.7, 1.0, 6.3], [1.0, 2.0, 5.2]], "collapse": [[6.0, 0.0, 0.0], [0.0, 0.7, 0.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0]], "far": [[2.0, 0.0, 4.0], [0.7, 2.0, 12.0], [0.7, 2.7, 10.3], [0.4, 2.8, 10.6]]}
TIERS = [(-12.0, 0.0), (-20.0, -12.0), (-30.0, -20.0)]
for _k, _v in REF_TIERS.items():
    REF[_k]["tiers"] = _v
SMASH_WINS = [(-1.0, 0.0), (0.0, 0.5), (0.5, 2.0), (2.0, 5.0), (5.0, 10.0)]
SMASH_DENS_WINS = [(0.0, 0.5), (0.5, 2.0), (2.0, 5.0), (5.0, 10.0)]
THIRDS_8K = [25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500,
             3150, 4000, 5000, 6300, 8000]


def thirds_of(x):
    f, p = signal.welch(x, SR, nperseg=min(16384, len(x)))
    return np.array([10 * np.log10(p[(f >= c / 2 ** (1 / 6)) & (f < c * 2 ** (1 / 6))].sum() + 1e-30) for c in THIRDS_8K])


def sm_onset(x):
    """The first time the 10 ms level reaches a tenth of what it reaches in the 3 s before the loudest 400 ms."""
    e = st_rms(x, 0.4)
    pk = int(np.argmax(e)) + N(0.2)
    e5 = env_rms(x, 0.01)
    top = e5[max(pk - N(2), 0):pk + N(0.3)].max()
    i = np.where(e5[:pk + N(0.3)] >= 0.1 * top)[0]
    i = i[i > pk - N(3)]
    return (i[0] if len(i) else pk) / SR


def sm_impacts(x, t0, t1, lo=300, hi=3000):
    """Individual impacts: peaks of the 300 Hz-3 kHz band's 5 ms level standing 6 dB over its 80 ms median, 30 ms
    apart at least: (time, dB under the biggest)."""
    b = bp(x, lo, hi, 4)
    e = env_rms(b, 0.005)[::44]
    sr2 = SR / 44
    med = signal.medfilt(e, 2 * int(0.04 * sr2) + 1)
    a, z = int(max(t0, 0) * sr2), int(min(t1, len(x) / SR) * sr2)
    out, last = [], -1e9
    for i in range(a + 2, z - 2):
        if e[i] > 2.0 * med[i] and e[i] >= e[i - 1] and e[i] >= e[i + 1] and (i - last) > 0.03 * sr2 and e[i] > 1e-5:
            out.append((i / sr2, e[i]))
            last = i
    if not out:
        return []
    m = max(v for _, v in out)
    return [(t, 20 * np.log10(v / m)) for t, v in out]


def sm_measure(x, t0=None, tscale=1.0, fscale=1.0):
    """The same measurements as the references' (see REF); `tscale` stretches the windows (a take made slower than its
    reference is measured over windows stretched as much, and its rates read back at the reference's pace)."""
    on = sm_onset(x) if t0 is None else t0
    lo_on, mid_on = sm_onset(bp(x, None, 120, 4)), sm_onset(bp(x, 300, 3000, 4))
    lpk = np.argmax(env_rms(bp(x, None, 120), 0.05)) / SR
    mpk = np.argmax(env_rms(bp(x, 300, 3000), 0.05)) / SR
    full = thirds_of(x[N(max(on - tscale, 0)):N(on + 10 * tscale)])
    th = []
    for a, b in SMASH_WINS:
        seg = x[N(max(on + a * tscale, 0)):N(min(on + b * tscale, len(x) / SR))]
        th.append(list(np.round(thirds_of(seg) - full.max(), 1)) if len(seg) > 4096 else [None] * len(THIRDS_8K))
    imp = sm_impacts(x, on - 0.2, on + 12 * tscale, 300 * fscale, 3000 * fscale)
    dens = [round(len([i for i in imp if on + a * tscale <= i[0] < on + b * tscale and i[1] > -30]) / ((b - a) * tscale), 1) for a, b in SMASH_DENS_WINS]
    lv = np.array([i[1] for i in imp if i[1] > -30])
    sizes = [round(float(np.median(lv)), 1), round(float(np.percentile(lv, 90)), 1), int((lv > -6).sum()), int(len(lv))] if len(lv) else [None] * 4
    e = 20 * np.log10(st_rms(x, 0.4) + 1e-12)
    pk = int(np.argmax(e))
    dec = []
    for d in (10, 20, 30):
        i = np.where(e[pk:] < e[pk] - d)[0]
        dec.append(round(i[0] / SR, 2) if len(i) else None)
    f, p = signal.welch(x[N(on):N(on + 8)], SR, nperseg=16384)
    tot = p.sum()
    sh = [round(10 * np.log10(p[m].sum() / tot + 1e-30), 1) for m in (f < 100, (f >= 100) & (f < 800), (f >= 800) & (f < 3000), f >= 3000)]
    b = bp(x, 300 * fscale, 3000 * fscale, 4)[N(on):N(on + 6 * tscale)]
    en = np.maximum(signal.decimate(np.abs(signal.hilbert(b)), 21, zero_phase=True), 1e-6)
    le = np.log(en) - np.mean(np.log(en))
    ff, pp = signal.welch(le, SR / 21, nperseg=min(4096, len(le)))
    mod = [round(10 * np.log10(pp[(ff >= a) & (ff < c)].mean() + 1e-30), 1) for a, c in ((0.5, 2), (2, 8), (8, 20), (20, 80))]
    tiers = [[round(len([i for i in imp if on + a * tscale <= i[0] < on + b * tscale and lo < i[1] <= hi + 0.1]) / ((b - a) * tscale), 1) for lo, hi in TIERS]
             for a, b in SMASH_DENS_WINS]
    return dict(onset=round(on, 2), thirds=th, dens=dens, tiers=tiers, sizes=sizes, decay=dec, shares=sh, mod=mod,
                lead=[round((mid_on - lo_on) * 1000), round((mpk - lpk) * 1000)])


def inv_cdf_db(u, p50, p90):
    """An impact's level (dB under the biggest) from u in [0, 1): the measured median and 90th percentile, -30 at the
    small end, 0 at the top."""
    return np.interp(u, [0.0, 0.5, 0.9, 1.0], [-30.0, p50, p90, 0.0])


def rock_hit(n, tl, size, fscale, rng, crunch_hz, crunch_len, top=1600.0):
    """One mass breaking or landing: a heavy low thud (its own pitch, lower for a bigger mass) and the rock's crunch
    (a band of noise round `crunch_hz`, rising over 5 ms, its top steeply cut at `top`: the references' impacts are
    5 ms fronts, which over 1.5 kHz are a patter kept out; under it they are the rock breaking), `crunch_len` s
    long."""
    t = tt(n)
    f0 = 55.0 * fscale / (0.6 + size) ** 0.5 * rng.uniform(0.85, 1.15)
    thud = modes(n, tl - 0.004, np.array([1.0, 1.5, 2.2, 3.1]) * f0, [0.22, 0.15, 0.1, 0.07], [1, 0.7, 0.45, 0.3], 0.006, rng)
    on = t >= tl
    u = np.maximum(t - tl, 0)
    c = crunch_hz * fscale * rng.uniform(0.7, 1.4)
    # (only the stretch round the impact is made: a whole-length filter per impact would cost minutes)
    a, z_end = max(N(tl) - N(0.05), 0), min(N(tl + 8 * crunch_len + 0.1), n)
    z = np.zeros(n)
    seg = bp(rng.standard_normal(z_end - a + N(0.2)), c / 2.2, min(c * 2.2, 9000), 2)
    z[a:z_end] = bp(seg, None, top, 4)[N(0.1):N(0.1) + z_end - a]
    cr = z * ss(u / 0.005) * np.exp(-u / crunch_len) * on
    return pk(thud) * 0.9 + pk(cr) * 0.7


# (impacts closer than 30 ms, or within 6 dB of a neighbour, read back as one: the big tier is made this much denser
# than the reference measures so that the same measurement reads it back; calibrated on take E)
BIG_CAL = 1.7


def smash_events(n, t0, ref, rng, tscale=1.0, fscale=1.0, crunch_hz=700, crunch_len=(0.03, 0.12), top=1600.0):
    """The reference's impacts, re-made: in each window its measured rates of big (within 12 dB of the biggest),
    middling (12-20 dB under) and small (20-30 dB under) impacts (time-scaled by `tscale`), each one's level drawn in
    its tier."""
    x = np.zeros(n)
    for (a, b), rates in zip(SMASH_DENS_WINS, ref["tiers"]):
        a, b = a * tscale, b * tscale
        for (lo, hi), rate, cal in zip(TIERS, rates, (BIG_CAL, 1.2, 1.0)):
            for _ in range(rng.poisson(cal * rate / tscale * (b - a))):
                tl = t0 + rng.uniform(a, b)
                if tl >= n / SR - 0.2:
                    continue
                size = 10 ** (rng.uniform(lo, hi) / 20)
                x += size * rock_hit(n, tl, size, fscale, rng, crunch_hz, rng.uniform(*crunch_len) * tscale ** 0.5, top)
    return x


def smash_roar(n, t0, ref, rng, tscale=1.0, shift=0):
    """The continuous part between the impacts: noise whose third-octave balance follows the reference's window by
    window (time-scaled; its bands moved down `shift` third octaves for a scaled-up event), interpolated in time."""
    th = np.array([[v if v is not None else -60 for v in w] for w in ref["thirds"]])
    if shift:
        th = np.concatenate([th[:, shift:], np.repeat(th[:, -1:], shift, axis=1) - 6 * np.arange(1, shift + 1)], axis=1)
    cent = np.array([(a + b) / 2 * tscale for a, b in SMASH_WINS])
    lf = np.log2(np.array(THIRDS_8K))

    def mag(tc, f):
        v = tc - t0
        row = np.array([np.interp(v, cent, th[:, j]) for j in range(th.shape[1])])
        g = np.interp(np.log2(np.maximum(f, 1)), lf, row, left=row[0] - 12, right=-80)
        dens = 10 ** (g / 20) / np.sqrt(np.maximum(f, 20) / 100)
        return dens * float(ss((v + 1.0 * tscale) / (0.4 * tscale)))
    return shaped(n, rng, mag, frame=4096, hop=1024)


def match_thirds(x, t0, ref, tscale=1.0, shift=0, iters=2, most=12.0):
    """A time-varying correction toward the reference's third-octave balance, window by window (in third-octave bands,
    each scaled by a gain smoothly interpolated between the windows' middles). It corrects the colour only: the
    timing of the impacts stays the synthesis's own."""
    th = np.array([[v if v is not None else -60 for v in w] for w in ref["thirds"]])
    if shift:
        th = np.concatenate([th[:, shift:], np.repeat(th[:, -1:], shift, axis=1) - 6 * np.arange(1, shift + 1)], axis=1)
    n = len(x)
    t = tt(n)
    cent = np.array([(a + b) / 2 * tscale for a, b in SMASH_WINS])
    for _ in range(iters):
        full = thirds_of(x[N(max(t0 - tscale, 0)):N(t0 + 10 * tscale)])
        now = []
        for a, b in SMASH_WINS:
            seg = x[N(max(t0 + a * tscale, 0)):N(min(t0 + b * tscale, n / SR))]
            now.append(thirds_of(seg) - full.max() if len(seg) > 4096 else th[len(now)])
        diff = np.clip(th - np.array(now), -most, most)
        y = np.zeros(n)
        for j, fc in enumerate(THIRDS_8K):
            lo, hi = fc / 2 ** (1 / 6), min(fc * 2 ** (1 / 6), SR * 0.45)
            # (zero-phase: a causal bank would smear each impact's front across the bands' delays)
            band = signal.sosfiltfilt(signal.butter(2, [lo, hi], "bandpass", fs=SR, output="sos"), x)
            g = 10 ** (np.interp(t - t0, cent, diff[:, j]) / 20)
            y += band * g
        # (what lies outside 22 Hz-9 kHz dropped; the bands' sum re-levelled)
        x = y * (np.sqrt(np.mean(x ** 2)) / (np.sqrt(np.mean(y ** 2)) + 1e-12))
    return x


def distant_air(x, d, rng):
    """The far take for the smash, guided by the distant rock slide (#4): air absorption as ISO 9613-1 gives it at 20 C,
    70 % (about 5 dB/km at 1 kHz, 10 at 2, 30 at 4, 100 at 8: gentler than `distant`, so the mids of rock still carry
    as they do in #4), fronts smeared 20-50 ms, the land's late returns."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    a_km = np.interp(f, [0, 125, 250, 500, 1000, 2000, 4000, 8000, 16000], [0, 0.4, 1.0, 1.9, 4.5, 10.0, 30.0, 100.0, 300.0])
    y = np.fft.irfft(X * 10 ** (-a_km * d / 1000 / 20), n)
    sm = np.hanning(N(0.02 + 0.03 * min(d / 1000, 1.2)))
    y = 0.5 * y + 0.5 * signal.fftconvolve(y, sm / sm.sum())[:n]
    km = d / 1000
    ear = [(0.35 + 0.5 * km, 0.35, 1200), (0.8 + 0.9 * km, 0.28, 800), (1.5 + 1.2 * km, 0.2, 600), (2.4 + 1.4 * km, 0.13, 450)]
    return space(y, rng, 4.5, 1.6, 0.8, 0.25, early=[(a * rng.uniform(0.85, 1.15), g, lp) for a, g, lp in ear], wet=0.4, pre=0.05)[:n]


SMASH_KIND = {
    # take: (reference, time scale, third octaves down, crunch centre Hz, crunch length s, smash level re the heave,
    # the crunch's top Hz)
    "E": ("blast", 1.0, 0, 700, (0.01, 0.035), 1.0, 900.0),
    "F": ("rockfall", 1.3, 4, 900, (0.01, 0.03), 0.9, 900.0),
    "G": ("collapse", 1.0, 0, 600, (0.012, 0.045), 1.0, 1300.0),
}


def smash_take(take, far=False, layer_only=False):
    """Round 4's breach takes: breach A's heave under a smash re-made from one real event's measurements (see REF).
    E, "Blast" (the open-mine blast, #1): the rock breaking first, a dense burst of breaking for over a second, the
      low roll swelling to its peak some 3 s on, then the fall-back for seconds.
    F, "Rockfall" (the cliff rockfall, #2, made the worm's size: 4 third octaves lower, so its pebbles become masses,
      and 1.3 times slower, so it doesn't drag): blocks breaking and tumbling, a few big, many smaller, thinning over ten seconds.
    G, "Collapse" (the building brought down, #3): one great crash, low and rock together at once, a dense half second
      of breaking, then quickly down to a short roll.
    The far take of each through 800 blocks of air (`distant_air`, after the distant rock slide, #4)."""
    name, tscale, shift, crunch_hz, crunch_len, mixlvl, top = SMASH_KIND[take]
    ref = REF[name]
    base, t0 = breach_A()
    base = np.concatenate([base, np.zeros(N(13.0) - len(base))])
    n = len(base)
    rng = R(4800 + ord(take))
    ev = smash_events(n, t0, ref, rng, tscale, 2 ** (-shift / 3), crunch_hz, crunch_len, top)
    roar = smash_roar(n, t0, ref, rng, tscale, shift)
    lay = pk(ev) + 0.08 * pk(roar)
    lay = match_thirds(lay, t0, ref, tscale, shift, iters=3)
    lay = lowcut(lay)
    if layer_only:
        return lay, t0
    x = pk(base) * 0.85 + mixlvl * pk(lay)
    # (driven gently: harder, its tops reach over 1.5 kHz as fronts)
    x = drive(x, 14.0)
    if far:
        x = distant_air(x, 800, rng)
    return fade(lowcut(x), 0, 1.2), t0


def smash_compare(take):
    """Take `take`'s smash layer measured as its reference was, and how close each measure is."""
    name, tscale, shift, *_ = SMASH_KIND[take]
    ref = REF[name]
    lay, t0 = smash_take(take, layer_only=True)
    m = sm_measure(lay, t0, tscale, 2 ** (-shift / 3))
    th = np.array([[v if v is not None else -60 for v in w] for w in ref["thirds"]])
    if shift:
        th = np.concatenate([th[:, shift:], np.repeat(th[:, -1:], shift, axis=1) - 6 * np.arange(1, shift + 1)], axis=1)
    mt = np.array([[v if v is not None else -60 for v in w] for w in m["thirds"]])
    thd = []
    for k, (a, b) in enumerate(SMASH_WINS):
        sel = th[k] > -40
        d = mt[k] - th[k]
        thd.append({"window_s": f"{a:+.1f}..{b:+.1f}", "mean_abs_db": round(float(np.mean(np.abs(d[sel]))), 1), "worst_db": round(float(d[sel][np.argmax(np.abs(d[sel]))]), 1)})
    return {"reference": ref["source"], "time_scale": tscale, "third_octaves_down": shift, "thirds_vs_reference": thd,
            **{k: {"reference": ref[k], "synth": m[k]} for k in ("tiers", "dens", "sizes", "decay", "shares", "mod", "lead")}}


def review4(outdir):
    """Round 4: the breach takes matched to real events (E, F, G), near and far, the whole strike from 250 blocks with
    the pick, and review.json with each take's reference and the numbers comparing them."""
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    files = {p.stem: load(p) for p in sorted(OUT.glob("*.ogg"))}
    titles = {"E": ("Breach take E: Blast", "The heave with the smash re-made from a real open-mine blast's measurements: the rock breaking first, a dense burst of breaking for over a second, the low roll swelling to its peak some 3 s on, the fall-back after."),
              "F": ("Breach take F: Rockfall", "The heave with the smash re-made from a real cliff rockfall's measurements, made the worm's size (4 third octaves lower, 1.3 times slower): blocks breaking and tumbling, a few big, many smaller, thinning over ten seconds."),
              "G": ("Breach take G: Collapse", "The heave with the smash re-made from a real building demolition's measurements: one great crash, low and rock together, a dense half second of breaking, then quickly down to a short roll.")}
    items = []
    for tk, (title, what) in titles.items():
        cmpd = smash_compare(tk)
        for far in (False, True):
            key = f"breach_{tk.lower()}" + ("_far" if far else "")
            fn = f"breach_take_{tk}{'_far' if far else ''}.mp3"
            g, l = write_mp3(outdir / fn, files[key])
            mb = measure(key, files[key])
            item = {"file": fn, "title": title + (" (800 blocks)" if far else ""), "what": what if not far else "The same take through 800 blocks of air (ISO 9613 absorption, the land's returns), guided by a real distant rock slide.",
                    "take": True, "lufs": round(l, 1), "matched_to": cmpd["reference"],
                    "banned_textures": {"sharp_fronts": mb["sharp_fronts"], "flutter_vs_noise": mb["flutter_vs_noise"], "ringing_db": mb["ringing_db"], "mid_800_3k_db": mb["mid_800_3k_db"], "top_3k_db": mb["top_3k_db"]}}
            if far:
                item["far_vs_distant_rockslide"] = {k: {"reference": REF["far"][k], "synth": v} for k, v in sm_measure(files[key], BREACH_AT[tk] + 0.0).items() if k in ("tiers", "sizes", "shares", "mod")}
            else:
                item["comparison"] = cmpd
            items.append(item)
    y, gains = mix(script_cues(250), files, 48.0)
    g, l = write_mp3(outdir / "strike_250_blocks.mp3", y)
    items.append({"file": "strike_250_blocks.mp3", "title": "The whole scripted strike from 250 blocks", "what": f"Every cue as the game plays it, breach take {BREACH_PICK}; the bite still the biggest.",
                  "lufs": round(l, 1), "game_limiter_max_db": round(-20 * np.log10(gains.min()), 1)})
    (outdir / "review.json").write_text(json.dumps({"laser": "worldeater", "round": 4, "picks": {"breach": BREACH_PICK}, "items": items}, indent=1, default=float))
    print("wrote", len(items), "files to", outdir)


# ======================================================================================================================
# round 5: destruction up close (the close sounds told little of the destruction and sounded far off). The close tier keeps what distance takes away: full band, dry,
# fronts of 1-3 ms, the references' impact rates, grit up to 10 kHz. Mid and far are the close sound carried through
# 300 and 800 blocks of air (`distant_air`), so walking in from 800 blocks to 50 is one continuous change.
# ======================================================================================================================
# The close references' own measures (round 5, from #2 the cliff rockfall, close; #1's blast for the burst's timing):
# their loudest impacts' fronts over 1.5 kHz rise in 1-5 ms; #2 has 10.6 sharp fronts a second, its 3-6 kHz share
# -17.5 dB and 6-10 kHz -25.2 dB; #1's burst has 18 impacts a second within 12 dB of the biggest in its first 0.5 s.
CLOSE_REF = {"fronts_per_s": 10.6, "rise_ms": (1.1, 5.0), "share_3_6k": -17.5, "share_6_10k": -25.2}


def crack_ev(rng, size, body_hz, bright, tear=1.0, slam=False):
    """One piece of rock failing, as heard close: a thump with real body (low modes struck in 2 ms) and a tear (a
    burst of 2-7 micro-fractures in the first 5-40 ms, each front 0.5-2 ms, then a ragged tail), its band 120 Hz to
    `bright` Hz. A `slam` is a mass landing: a heavier, lower thump and a shorter, darker tear. Returns a short array
    starting at the crack."""
    L = N(1.0)
    t = tt(L)
    f0 = body_hz * rng.uniform(0.8, 1.25) / (0.6 + size) ** 0.4 * (0.7 if slam else 1.0)
    th = np.zeros(L)
    for m, tau, a in ((1.0, 0.2, 1.0), (1.5, 0.13, 0.7), (2.2, 0.09, 0.45), (3.1, 0.06, 0.3)):
        th += a * np.sin(2 * np.pi * f0 * m * t + rng.uniform(0, 6)) * np.exp(-t / (tau * (0.5 + size) * (1.4 if slam else 1.0)))
    th *= ss(t / 0.002)
    tr = np.zeros(L)
    z = rng.standard_normal(L)
    u = 0.0
    for _ in range(rng.integers(2, 8)):
        u += rng.exponential(0.005)
        k = N(u)
        rise = rng.uniform(0.0005, 0.002)
        d = rng.uniform(0.002, 0.012)
        tt_ = t - u
        tr += rng.uniform(0.4, 1.0) * np.where(tt_ >= 0, ss(tt_ / rise) * np.exp(-np.maximum(tt_, 0) / d), 0.0)
    tr += 0.18 * ss(t / 0.004) * np.exp(-t / rng.uniform(0.015, 0.05 if not slam else 0.04))
    hi = bright * (0.6 if slam else 1.0) * rng.uniform(0.7, 1.2)
    tear_s = bp(z * tr, 120, min(hi, 15000), 2)
    return pk(th) * (1.2 if slam else 1.0) + tear * (0.6 if slam else 1.0) * pk(tear_s)


def close_layer(n, t0, plan, rng, body_hz=70.0, bright=9000.0, density=1.0, tear=1.0, slams=(), grit=1.0):
    """Destruction up close: per window (a, b) s from t0, cracks a second in three size tiers (within 12 dB of the
    biggest, 12-20 under, 20-30 under: the last the grit and rubble), times `density`; `slams` (t, size) masses landing."""
    x = np.zeros(n + N(1.0))
    for (a, b), rates in plan:
        # (the big tier made 1.5 times denser than measured: cracks closer than 30 ms or within 6 dB read back as one)
        for (lo, hi), rate, g, cal in zip(TIERS, rates, (1.0, 1.0, grit), (1.5, 1.2, 1.0)):
            for _ in range(rng.poisson(cal * rate * density * (b - a))):
                tc = t0 + rng.uniform(a, b)
                if tc < 0 or tc >= n / SR:
                    continue
                size = 10 ** (rng.uniform(lo, hi) / 20)
                ev = crack_ev(rng, size, body_hz, bright * (0.8 + 0.4 * size), tear)
                i = N(tc)
                x[i:i + len(ev)] += g * size * ev
    for ts, size in slams:
        ev = crack_ev(rng, size, body_hz, bright, tear, slam=True)
        i = N(t0 + ts)
        if 0 <= i < n:
            x[i:i + len(ev)] += size * ev
    return x[:n]


def tear_roar(n, t0, rng, lo=80.0, hi=3000.0, length=6.0, rate=1.2):
    """The roar of ground tearing: a broad band whose centre wanders (120-900 Hz) and whose level is ragged at 0.5-4 Hz,
    from t0, dying over `length` s."""
    t = tt(n)
    cen = 300 * 2 ** (1.5 * slow(rng, n, rate))

    def mag(tc, f):
        c = cen[min(N(tc), n - 1)]
        lf = np.log2(np.maximum(f, 1) / c)
        return np.exp(-0.5 * (lf / 1.3) ** 2) * floor_cut(f, lo, hi, 2)
    r = shaped(n, rng, mag, frame=2048, hop=512)
    env = ss((t - t0 + 0.05) / 0.08) * np.exp(-np.maximum(t - t0, 0) / (length / 2.5)) * (1 + 0.5 * slow(rng, n, 3.0))
    return r * np.maximum(env, 0)


# the windows' impact rates (big, middling, grit) a second: the burst as #1's (18 then 10 big a second), then the cascade
# as #2's (masses one after another, the grit under them)
BREACH_CLOSE_PLAN = [((0.0, 0.5), (18.0, 4.0, 6.0)), ((0.5, 2.0), (10.0, 2.7, 4.7)), ((2.0, 5.0), (1.7, 1.0, 6.3)), ((5.0, 10.0), (1.0, 2.0, 5.2))]
BITE_CLOSE_PLAN = [((0.0, 0.6), (22.0, 5.0, 7.0)), ((0.6, 2.0), (12.0, 3.0, 5.0)), ((2.0, 5.0), (2.5, 1.5, 6.0)), ((5.0, 9.0), (1.2, 2.0, 5.0))]
SLUMP_CLOSE_PLAN = [((0.0, 0.4), (10.0, 2.0, 4.0)), ((0.4, 1.5), (3.0, 2.0, 4.0)), ((1.5, 4.0), (0.6, 1.0, 3.0))]
CLOSE_THIRDS = REF["rockfall"]["thirds"]


def close_smash(n, t0, plan, rng, density=1.0, bright=9000.0, slams=None, match=True):
    """The close tier's breaking: cracks to `plan`, masses slamming down one after another, the tearing roar, then its
    third-octave balance matched window by window to the close rockfall (#2: full band, unscaled)."""
    if slams is None:
        slams = [(0.02, 1.0)] + [(rng.uniform(0.4, 6.5), rng.uniform(0.4, 0.9)) for _ in range(9)]
    cr = close_layer(n, t0, plan, rng, 70.0, bright, density, 1.0, slams)
    lay = pk(cr) + 0.3 * pk(tear_roar(n, t0, rng))
    if match:
        lay = match_thirds(lay, t0, {"thirds": CLOSE_THIRDS}, 1.0, 0, iters=2, most=9.0)
    return lay


def breach_close(alt=False):
    """The breach from about 60 blocks: the heave and its sub (breach A) under the close breaking at the references'
    full impact density and brightness (`alt`: at two-thirds of the density, the top 4 dB down)."""
    base, t0 = breach_A()
    base = np.concatenate([base, np.zeros(N(13.0) - len(base))])
    n = len(base)
    rng = R(5500 + (7 if alt else 0))
    lay = close_smash(n, t0, BREACH_CLOSE_PLAN, rng, 0.67 if alt else 1.0)
    if alt:
        lay = lay - (1 - 10 ** (-4 / 20)) * bp(lay, 2500, None, 2)
    sub = pressure(n, t0, 0.04, 1.2, 26, rng)
    x = 0.7 * pk(base) + 1.3 * pk(lay) + 0.35 * pk(sub)
    x = drive(x, 14.0)
    # (close: dry, the land's first return late and low)
    x = space(x, rng, 2.0, 0.9, 0.35, 0.12, early=[(0.35, 0.12, 2500)], wet=0.12)[:n]
    return fade(lowcut(x), 0, 1.2), t0


def bite_close():
    """The bite from about 60 blocks: bite C under the jaws driving into the ground and the land breaking,
    denser and heavier than the breach's, its first masses the jaws' own."""
    base = bite("C")
    n = len(base) + N(1.0)
    base = np.concatenate([base, np.zeros(n - len(base))])
    rng = R(5600)
    t0 = HIT_AT
    slams = [(0.0, 1.0), (0.08, 0.9), (0.85, 1.0)] + [(rng.uniform(0.3, 6.0), rng.uniform(0.4, 0.9)) for _ in range(10)]
    lay = close_smash(n, t0, BITE_CLOSE_PLAN, rng, 1.0, 9000.0, slams)
    x = 0.8 * pk(base) + 1.3 * pk(lay)
    x = drive(x, 14.0)
    x = space(x, rng, 2.0, 0.9, 0.35, 0.12, early=[(0.35, 0.12, 2500)], wet=0.12)[:n]
    return fade(lowcut(x), 0, 1.2), lay, t0


def bite_mid():
    """The bite from about 300 blocks: bite C as it was, with the close breaking carried through 300 blocks of air
    under it, so the breaking is there but the roll is the character."""
    _, lay, t0 = bite_close()
    base = bite("C")
    n = len(lay)
    base = np.concatenate([base, np.zeros(n - len(base))])
    far = distant_air(lay, 300, R(5601))
    x = pk(base) + 0.55 * pk(far)
    return fade(lowcut(drive(x, 14.0)), 0, 1.2)


def slump_close(k):
    """A tunnel ring giving way from about 60 blocks: the slump with the land breaking as it drops."""
    base = slump(k)
    n = len(base)
    rng = R(5700 + k)
    lay = close_smash(n, HIT_AT, SLUMP_CLOSE_PLAN, rng, 1.0, 8000.0, [(0.0, 0.9)] + [(rng.uniform(0.2, 2.5), rng.uniform(0.3, 0.7)) for _ in range(4)])
    x = pk(base) + 0.8 * pk(lay)
    x = space(drive(x, 14.0), rng, 1.6, 0.8, 0.3, 0.1, wet=0.1)[:n]
    return fade(lowcut(x), 0, 1.0)


def grind_piece(k):
    """The burrowing heard close (HUNT and the first approach, while the mound passes within ~150 blocks): rock being
    ground and broken under the land: steady cracks (4 big, 4 middling, 6 grit a second) muffled by the earth over
    them (their top at ~2.5 kHz), the grinding roar, the sub of the mass; 4 s, 1 s fades, laid every 3 s."""
    rng = R(5800 + k)
    n = N(4.0)
    t = tt(n)
    plan = [((-0.2, 4.2), (4.0, 4.0, 6.0))]
    cr = close_layer(n, 0.0, plan, rng, 55.0, 3500.0, 1.0, 0.8, [(rng.uniform(0.2, 3.8), rng.uniform(0.5, 0.9)) for _ in range(3)])
    roar = tear_roar(n, -0.1, rng, 50, 1500, 60.0, 0.8)
    g = mass(n, rng, 40, 600, 14, 0.06, 0.0, 4)
    sub = bp(rng.standard_normal(n), 18, 60, 2)
    x = pk(cr) + 0.5 * pk(roar) + 0.5 * pk(g) + 0.4 * pk(sub)
    x = bp(x, None, 2600, 2)
    x = drive(x, 14.0)
    return lowcut(x * ss(t / 1.0) * ss((4.0 - t) / 1.0))


def rim_piece(k):
    """A hole's rim while the body pours through it (60 blocks off): continuous violent grinding and breaking of the
    rim as 68 blocks of stone scrape past at 150 a second: dense cracks (5 big, 4 middling, 8 grit a second), slabs of the
    rim falling in (one a second), the grinding roar; 5 s, 1 s fades, laid every 4 s."""
    rng = R(5900 + k)
    n = N(5.0)
    t = tt(n)
    plan = [((-0.2, 5.2), (5.0, 4.0, 8.0))]
    slabs = [(rng.uniform(0.2, 4.8), rng.uniform(0.6, 1.0)) for _ in range(5)]
    cr = close_layer(n, 0.0, plan, rng, 65.0, 6000.0, 1.0, 1.0, slabs)
    roar = tear_roar(n, -0.1, rng, 60, 4000, 60.0, 1.5)
    g = mass(n, rng, 35, 500, 12, 0.08, 0.0, 4)
    x = pk(cr) + 0.45 * pk(roar) + 0.45 * pk(g)
    x = drive(x, 14.0)
    x = space(x, R(5950 + k), 1.5, 0.8, 0.3, 0.1, wet=0.1)[:n]
    return lowcut(x * ss(t / 1.0) * ss((5.0 - t) / 1.0))


_BC = {}


def breach_tier(tier):
    """The breach at its three distances, all from the one close sound: 'close' (~60 blocks), 'close_b' (the
    two-thirds alternative), 'mid' (~300: carried through 300 blocks of air) and 'far' (~800)."""
    if tier == "close_b":
        return breach_close(alt=True)[0]
    if "x" not in _BC:
        _BC["x"] = breach_close()[0]
    x = _BC["x"]
    if tier == "close":
        return x
    d = 300 if tier == "mid" else 800
    return fade(lowcut(distant_air(x, d, R(5501 + d))), 0, 1.0)


def review5(outdir):
    """Round 5: the breach and the bite at three distances, the close alternative, the burrowing passing close, the body
    pouring through a hole from 60 blocks, and the whole strike from 80 and 300 blocks; review.json with the close tier's
    measures against the close references."""
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    files = {p.stem: load(p) for p in sorted(OUT.glob("*.ogg"))}
    items = []

    def put(fn, x, title, what, extra=None):
        g, l = write_mp3(outdir / fn, x)
        it = {"file": fn, "title": title, "what": what, "lufs": round(l, 1)}
        mb = measure(fn, x)
        it["banned_textures"] = {k: mb[k] for k in ("sharp_fronts", "flutter_vs_noise", "ringing_db", "mid_800_3k_db", "top_3k_db")}
        it.update(extra or {})
        items.append(it)
        return it

    def close_numbers(x, t0):
        m = sm_measure(x, t0)
        seg = x[N(t0):N(t0 + 10)]
        f, p = signal.welch(seg, SR, nperseg=8192)
        tot = p.sum()
        return {"fronts_per_s": round(clicks(seg) / (len(seg) / SR), 1), "flutter": round(flutter(seg)[0], 2),
                "share_3_6k": round(10 * np.log10(p[(f >= 3000) & (f < 6000)].sum() / tot), 1), "share_6_10k": round(10 * np.log10(p[(f >= 6000) & (f < 10000)].sum() / tot), 1),
                "shares": m["shares"], "tiers": m["tiers"], "sizes": m["sizes"], "decay": m["decay"], "mod": m["mod"]}
    ref2 = {"fronts_per_s": 10.6, "flutter": 2.65, "share_3_6k": -17.5, "share_6_10k": -25.2, "shares": REF["rockfall"]["shares"],
            "tiers": REF["rockfall"]["tiers"], "sizes": REF["rockfall"]["sizes"], "decay": REF["rockfall"]["decay"], "mod": REF["rockfall"]["mod"]}
    put("breach_from_60_blocks.mp3", files["breach_close"], "Breach, from 60 blocks (pick)", "Standing near it: the heave and its sub under the rock failing at the close references' full density and brightness: deep cracks with body, the tearing roar, masses slamming down one after another, grit to 10 kHz; dry.",
        {"vs_close_reference": {"synth": close_numbers(files["breach_close"], 0.6), "reference_#2_cliff_rockfall": ref2}})
    put("breach_from_60_blocks_alt.mp3", files["breach_close_b"], "Breach, from 60 blocks (alternative: two-thirds)", "The same at two-thirds of the density, its top 4 dB down.",
        {"vs_close_reference": {"synth": close_numbers(files["breach_close_b"], 0.6), "reference_#2_cliff_rockfall": ref2}})
    put("breach_from_300_blocks.mp3", files["breach_mid"], "Breach, from 300 blocks", "The close sound carried through 300 blocks of air: the breaking still in it, the top softened, the land answering.")
    put("breach_from_800_blocks.mp3", files["breach_far"], "Breach, from 800 blocks", "The close sound through 800 blocks: the deep roll, the breaking dulled.")
    put("bite_from_60_blocks.mp3", files["bite_close"], "Bite, from 60 blocks", "Bite C under the jaws driving into the ground and the land breaking: denser and heavier than the breach's.",
        {"vs_close_reference": {"synth": close_numbers(files["bite_close"], HIT_AT), "reference_#2_cliff_rockfall": ref2}})
    put("bite_from_300_blocks.mp3", files["bite_mid"], "Bite, from 300 blocks", "Bite C with the close breaking carried through 300 blocks of air under it.")
    put("bite_from_800_blocks.mp3", files["bite_c_far"], "Bite, from 800 blocks", "Bite C's far take, as approved.")
    # the burrowing passing close: the mound 200 blocks off, passing 30 blocks from the listener, gone 200 the other side
    seq = []
    for j, t in enumerate(np.arange(0.0, 15.0, 3.0)):
        x_ = -200 + 400 * (t + 2) / 17.0
        dm = float(np.hypot(x_, 30))
        seq.append((t + dm / V_GROUND, f"move{1 + j % 3}", 0.9 * vol_big(dm), 1.0))
        seq.append((t + dm / V_GROUND, f"grind{1 + j % 3}", 0.95 * nearness(dm), 1.0))
    y, _ = mix(seq, files, 20.0)
    put("burrowing_passing_close.mp3", y, "The burrowing passing close", "The mound passing 30 blocks from you under the land, from 200 off to 200 the other side: the approved movement bed with the rock being ground and broken under it as it nears.")
    seq = [(0.0, "breach_close", 1.0, 1.0)] + [(0.8 + 4 * j, f"rim{1 + j % 3}", 0.45 + 0.55 * np.exp(-(4 * j) / 8), 1.0) for j in range(5)]
    y, _ = mix(seq, files, 24.0)
    put("body_pouring_through_hole_from_60.mp3", y, "The body pouring out of its hole, from 60 blocks", "The breach, then the hole's rim grinding and breaking as 1,836 blocks of stone pour out past it for some 18 s, easing as it goes.")
    for d in (80, 300):
        y, gains = mix(script_cues(d), files, 48.0)
        put(f"strike_from_{d}_blocks.mp3", y, f"The whole scripted strike from {d} blocks", f"Every cue as the game plays it, {d} blocks from the breach (the bite {round(float(np.hypot(d, WE_SPAN)))} off): breach tiers, burrowing, rims, the bite tiers, the rings' close tier.",
            {"game_limiter_max_db": round(-20 * np.log10(gains.min()), 1)})
    (outdir / "review.json").write_text(json.dumps({"laser": "worldeater", "round": 5, "picks": {"breach": "three tiers", "breach_close": BREACH_CLOSE}, "items": items}, indent=1, default=float))
    print("wrote", len(items), "files to", outdir)


# ======================================================================================================================
# round 6: the ride's air (wind passing by the player as they are carried through). The jaws shut, ~0.7 s dark, the player drawn down the throat gathering speed, 8-9 s at 60-110 blocks a
# second through a ribbed tube 60 across, a swell at the head, thrown out into daylight. Each take is a start (from the
# shut: the dark beat, then the draw and the gathering speed, RIDE_START s), a seamless middle (RIDE_LOOP s at the
# cruising speed; played faster for more speed), and an end (the swell at the head and the air tearing open into the
# outside, its open-air release on RIDE_END_OPEN, where the spit lands). Air only: no stone, no breaking.
# ======================================================================================================================
RIDE_START = 3.0      # ride_*_start: the shut at 0, dark to 0.7, speed gathered by its end
RIDE_LOOP = 6.0       # ride_*_loop: loops end to start
RIDE_END = 2.6        # ride_*_end
RIDE_END_OPEN = 1.1   # ride_*_end: the mouth open here (the spit's moment)
RIDE_V = 85.0         # the middle's speed, blocks a second


def ride_speed(part, n):
    """The speed (blocks a second) through each part: start 0 until 0.7, gathering to RIDE_V; middle RIDE_V; end
    RIDE_V rising to 110 at the head, then out."""
    t = tt(n)
    if part == "start":
        return RIDE_V * ss((t - 0.7) / (RIDE_START - 0.7)) ** 0.8
    if part == "loop":
        return np.full(n, RIDE_V)
    return RIDE_V + 25.0 * ss(t / RIDE_END_OPEN)


def ride_level(v):
    """Wind at the ear rises steeply with speed (as a dipole source, about the fifth power): dB re RIDE_V."""
    return 10 ** (50 * np.log10(np.maximum(v, 1.0) / RIDE_V) / 20)


def periodic_gusts(n, rng, rate, loop):
    """Rib sections passing: soft swells about `rate` a second, irregular in spacing and size; with `loop`, a whole
    number of them fitted to the length so it wraps."""
    t = tt(n)
    dur = n / SR
    k = max(1, int(round(rate * dur)))
    times = (np.arange(k) + rng.uniform(-0.25, 0.25, k)) * dur / k
    g = np.zeros(n)
    for tc in times:
        w = rng.uniform(0.18, 0.32)
        a = rng.uniform(0.5, 1.0)
        for sh in ((-dur, 0, dur) if loop else (0,)):
            g += a * np.exp(-0.5 * ((t - tc - sh) / w) ** 2)
    return g / (g.max() + 1e-9)


def ride_A(part, seed=9100):
    """Take A, "At the ear": the wind as it sounds at your own head at speed. Turbulence round the head: a broad hump
    of rush whose centre rises with speed (Strouhal: 120 Hz at a walk of the body to 260 Hz at 85, 340 at 110) with a
    steep top (no hiss), the low buffeting of it (20-150 Hz, gusting), the level climbing with the fifth power of the
    speed; the tube round it as a low hollow roar (drifting resonances 22-110 Hz); each rib section passing a slow
    swell that brightens the rush."""
    rng = R(seed + {"start": 0, "loop": 1, "end": 2}[part])
    loop = part == "loop"
    n = N({"start": RIDE_START, "loop": RIDE_LOOP, "end": RIDE_END}[part])
    t = tt(n)
    v = ride_speed(part, n)
    gust = periodic_gusts(n, rng, 1.9, loop)

    def mag(tc, f):
        i = min(N(tc), n - 1)
        c = max(260 * (v[i] / RIDE_V) * (1 + 0.25 * gust[i]), 30.0)
        lf = np.log2(np.maximum(f, 1) / c)
        rush = np.exp(-0.5 * (lf / 1.1) ** 2) / (1 + (f / (5 * c)) ** 3)
        return rush * floor_cut(f, 40, None, 2)
    rush = shaped(n, rng, mag, frame=2048, hop=512, loop=loop)
    buff = shaped(n, rng, lambda tc, f: floor_cut(f, 20, 150, 2), frame=8192, hop=2048, loop=loop)
    buff = buff * (1 + 0.6 * (gust - 0.5) + (0.3 * loop_slow(rng, n, 9) if loop else 0.3 * slow(rng, n, 1.5)))
    roar = mass(n, rng, 22, 110, 10, 0.05, 0.0, 4, loop=loop)
    lv = ride_level(v)
    x = (pk(rush) * (0.8 + 0.4 * gust) + 0.55 * pk(buff)) * lv + 0.5 * pk(roar) * np.minimum(lv, 1.6) ** 0.5
    return ride_part_finish(x, part, rng, loop)


def ride_B(part, seed=9200):
    """Take B, "Organ of the throat": the tube itself sounding as the air is driven through it: rush driven through a
    crowd of the tube's own resonances (a comb about 19 Hz apart from 38 Hz, as a pipe's, scaled up out of the
    infrasonic), the comb sliding slowly as the gullet bends, its drive (and how many of its partials speak) climbing
    with the speed; a hollow low drone under it; the ribs a slow swell. More tone and hollowness than A, less rush."""
    rng = R(seed + {"start": 0, "loop": 1, "end": 2}[part])
    loop = part == "loop"
    n = N({"start": RIDE_START, "loop": RIDE_LOOP, "end": RIDE_END}[part])
    v = ride_speed(part, n)
    bend = loop_slow(rng, n, 3) if loop else slow(rng, n, 0.4)
    gust = periodic_gusts(n, rng, 1.6, loop)
    cs = 38 + 19.0 * np.arange(40)

    def mag(tc, f):
        i = min(N(tc), n - 1)
        sc = 1 + 0.07 * bend[i]
        top = 180 + 900 * (v[i] / 110)
        comb = peaks(f, cs * sc, np.full(40, 4.0), (cs / 38) ** -0.4)
        return (0.25 + comb) * floor_cut(f, 30, top, 3)
    x = shaped(n, rng, mag, frame=8192, hop=1024, loop=loop)
    drone = shaped(n, rng, lambda tc, f: peaks(f, [27, 41, 55], [5, 6, 8], [1, 0.6, 0.35]), frame=16384, hop=2048, loop=loop)
    lv = ride_level(v)
    x = pk(x) * lv * (0.8 + 0.35 * gust) + 0.45 * pk(drone) * np.minimum(lv, 1.6) ** 0.5
    return ride_part_finish(x, part, rng, loop)


def ride_C(part, seed=9300):
    """Take C, "Draughts": the air in pieces: gusts thrown off each rib you pass, every one a swelling and falling
    breath of air whose colour slides down as it goes by (Doppler), 2-4 a second as the speed climbs, overlapping into
    a gusting wind; a deep steady roar of the tube under them. More movement and passing-by than A or B."""
    rng = R(seed + {"start": 0, "loop": 1, "end": 2}[part])
    loop = part == "loop"
    n = N({"start": RIDE_START, "loop": RIDE_LOOP, "end": RIDE_END}[part])
    t = tt(n)
    dur = n / SR
    v = ride_speed(part, n)
    # (each draught: 0.35-0.8 s, its centre sliding from 1.5x to 0.6x of a speed-led centre)
    x = np.zeros(n)
    tb = 0.0 if loop else 0.6
    while tb < dur:
        i = min(N(tb), n - 1)
        if v[i] > 5:
            ln = rng.uniform(0.35, 0.8)
            m = N(ln)
            c0 = 300 * (v[i] / RIDE_V)
            # (its colour sliding down: three bands of the same breath, cross-faded smoothly from high to low)
            z = rng.standard_normal(m)
            u = np.arange(m) / m
            seg = np.zeros(m)
            for c_mul, centre_u in ((1.5, 0.0), (1.0, 0.5), (0.6, 1.0)):
                w = np.exp(-0.5 * ((u - centre_u) / 0.3) ** 2)
                seg += bp(z, c0 * c_mul / 2, c0 * c_mul * 2, 2) * w
            seg *= np.sin(np.pi * np.arange(m) / m) ** 1.5 * rng.uniform(0.5, 1.0) * ride_level(np.array([v[i]]))[0]
            idx = (i + np.arange(m)) % n if loop else np.arange(i, min(i + m, n))
            np.add.at(x, idx, seg[:len(idx)])
        tb += 1.0 / max(1.8 + 2.2 * (v[i] / 110), 0.5) * rng.uniform(0.6, 1.4) if v[i] > 5 else 0.1
    roar = mass(n, rng, 22, 140, 10, 0.05, 0.0, 4, loop=loop)
    bed = shaped(n, rng, lambda tc, f: floor_cut(f, 40, 600, 2), frame=4096, hop=1024, loop=loop) * ride_level(v)
    x = pk(x) + 0.35 * pk(bed) + 0.5 * pk(roar) * np.minimum(ride_level(v), 1.6) ** 0.5
    return ride_part_finish(x, part, rng, loop)


def ride_part_finish(x, part, rng, loop):
    """The parts' shared ends: the start silent through the dark beat and the draw beginning low; the end's swell at the
    head and the air tearing open into the outside on RIDE_END_OPEN (the tube's sound let go, a wide release of open
    air), its last second fading into the spit. The middle stays seamless (a circular high-pass only)."""
    n = len(x)
    t = tt(n)
    if loop:
        X = np.fft.rfft(x)
        f = np.fft.rfftfreq(n, 1 / SR)
        # (its gusts' peaks bent softly, sample by sample, so the seam stays seamless)
        return drive(np.fft.irfft(X * floor_cut(f, 18, 7000, 2), n), 5.0)
    if part == "start":
        # (the dark beat: only a low draw of air, the mouth's pressure, from 0.25 s)
        draw = pressure(n, 0.75, 0.3, 0.8, 22, rng)
        x = x * ss((t - 0.6) / 0.6) + 0.4 * pk(draw) * np.std(x) * 3
    else:
        swell = 1 + 0.5 * np.exp(-0.5 * ((t - RIDE_END_OPEN + 0.25) / 0.3) ** 2)
        inside = x * swell * np.where(t < RIDE_END_OPEN, 1.0, np.exp(-(t - RIDE_END_OPEN) / 0.15))

        def mag(tc, f):
            v = tc - RIDE_END_OPEN
            if v < -0.15:
                return np.zeros_like(f)
            return floor_cut(f, 50, 1600, 2) * tilt(f, 200, -3.5) * float(ss((v + 0.15) / 0.25) * np.exp(-max(v, 0) / 0.6))
        out = shaped(n, rng, mag, frame=2048, hop=512)
        out = out / (np.sqrt(np.mean(out[N(RIDE_END_OPEN):N(RIDE_END_OPEN + 0.5)] ** 2)) + 1e-12)
        x = inside + 1.2 * out * np.sqrt(np.mean(inside[: N(RIDE_END_OPEN)] ** 2))
        x = fade(x, 0, 0.6)
    return lowcut(x)


RIDES = {"A": ride_A, "B": ride_B, "C": ride_C}
RIDE_PICK = "A"


def ride_mix(take, files, ride_s=9.6):
    """The ride as the catch would play it (the shut at 1.0 s): the gulp, the start, the middle back to back (each copy
    a little faster as the speed gathers: pitch 0.95 then 1.06), the end with the spit on its opening, the throat low
    under it."""
    shut = 1.0
    spit_at = shut + ride_s
    cues = [(shut - GULP_SHUT, GULP_PICK, 1.0, 1.0), (shut, f"ride_{take.lower()}_start", 1.0, 1.0),
            (shut + 0.5, f"throat_{THROAT_PICK.lower()}", 0.45, 1.0)]
    t, k = shut + RIDE_START, 0
    end_at = spit_at - RIDE_END_OPEN
    while t < end_at:
        p = [0.95, 1.06, 1.12][min(k, 2)]
        cues.append((t, f"ride_{take.lower()}_loop", 1.0, p))
        t += RIDE_LOOP / p
        k += 1
    cues += [(end_at, f"ride_{take.lower()}_loop", None, 1.0), (end_at, f"ride_{take.lower()}_end", 1.0, 1.0),
             (spit_at - SPIT_AT, "spit", 1.0, 1.0), (spit_at - SPIT_AT + 0.12, f"throat_{THROAT_PICK.lower()}", None, 1.0)]
    return mix(cues, files, spit_at + 4.0)


def review6(outdir):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    files = {p.stem: load(p) for p in sorted(OUT.glob("*.ogg"))}
    desc = {"A": ("Ride take A: At the ear", "Wind at your own head at speed: a rush whose centre rises with speed, low buffeting, the tube's hollow roar under it, a slow swell as each rib section passes."),
            "B": ("Ride take B: Organ of the throat", "The tube itself sounding as the air is driven through: rush through a crowd of the tube's own low resonances that slide as it bends, a hollow drone; more hollow and tonal than A."),
            "C": ("Ride take C: Draughts", "The air in pieces: gusts thrown off each rib, each swelling and sliding down as it passes, 2-4 a second, over the tube's deep roar; the most passing-by.")}
    items = []
    for tk, (title, what) in desc.items():
        y, gains = ride_mix(tk, files)
        g, l = write_mp3(outdir / f"ride_take_{tk}_in_the_catch.mp3", y)
        parts = {pt: measure(f"ride_{tk.lower()}_{pt}", files[f"ride_{tk.lower()}_{pt}"]) for pt in ("start", "loop", "end")}
        lp = files[f"ride_{tk.lower()}_loop"]
        items.append({"file": f"ride_take_{tk}_in_the_catch.mp3", "title": title + ", in the catch", "what": what + " Heard as the catch plays it: the gulp, the dark beat, the draw gathering speed, the ride, the swell at the head, out with the spit.",
                      "take": True, "lufs": round(l, 1),
                      "measures": {pt: {k: m[k] for k in ("loudest_400ms_dbfs", "octaves_db", "mid_800_3k_db", "top_3k_db", "flutter_vs_noise", "sharp_fronts", "ringing_db")} for pt, m in parts.items()},
                      "loop_seam": {"wrap_step": round(float(abs(lp[0] - lp[-1])), 4), "p99_step": round(float(np.percentile(np.abs(np.diff(lp)), 99)), 4)}})
        for pt in ("loop",):
            g, l = write_mp3(outdir / f"ride_take_{tk}_middle_loop.mp3", np.tile(files[f"ride_{tk.lower()}_loop"], 2))
            items.append({"file": f"ride_take_{tk}_middle_loop.mp3", "title": title + ", the middle looped twice", "what": "The loopable middle at cruising speed, played twice end to start.", "lufs": round(l, 1)})
    (outdir / "review.json").write_text(json.dumps({"laser": "worldeater", "round": 6, "picks": {"ride": RIDE_PICK}, "items": items}, indent=1, default=float))
    print("wrote", len(items), "files to", outdir)


# ======================================================================================================================
# round 7: to a measured reference (two recordings, measured only: nothing of their audio is here or anywhere
# delivered). What the measures say a worm needs: one
# broad, continuous roar of moving earth, its spectrum sloping about 1 dB a third octave from ~50 Hz to 1 kHz and
# steeper above (1-3 kHz 15-20 dB under, over 6 kHz 30-45 under), noise through and through (no tone, no ringing, few
# fronts: 1-4 a second), each band swelling slowly on its own (13-20 dB more 0.1-1 Hz movement than plain noise, a
# little more at 1-4 Hz, none faster), the bands sharing a quarter to half of it, the sub steadier; the big moments a
# 0.2-0.6 Hz heave; mono-ish when big (L/R correlation ~0.9), wide when far. Absent: cracks, clicks, tones.
# ======================================================================================================================
TEXREF_FC = [31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150,
             4000, 5000, 6300]
TEXREF_RATES = [(0.1, 0.3), (0.3, 1), (1, 2), (2, 4), (4, 8), (8, 16), (16, 32), (32, 64)]
# (per state: band levels dB under the loudest; each band's log-envelope modulation, dB over plain noise in the same band,
# at TEXREF_RATES; how much of the slow movement the bands share. "roar" the reference worm at full cry, "eaten" being
# eaten, "approach" its coming under the sand, "attack" the burst out of it)
TEXREF = {"roar": {"levels": [-4.7, -1.4, 0.0, -2.3, -3.1, -4.6, -2.7, -6.3, -8.1, -8.3, -10.0, -10.4, -10.4, -11.5, -12.6, -13.2, -15.6, -17.7, -20.0, -21.3, -23.9, -27.3, -31.5, -35.2], "mod_excess": [[0.5, 0.7, 1.1, -0.9, 1.2, 1.9, 0.3, -2.9], [-1.4, 0.0, 4.0, -2.0, -1.6, 1.4, 0.5, 0.3], [6.7, 2.4, 0.1, -1.9, -0.7, 1.7, 1.2, 1.2], [4.8, 3.8, 3.0, -2.6, -1.2, 0.7, -0.4, -0.6], [10.7, 6.6, 5.5, 0.3, -0.6, -0.4, -0.6, -0.2], [0.3, 2.1, 0.6, -1.2, 0.3, -1.4, -0.6, -1.4], [9.9, 5.7, 3.4, -0.6, -1.8, 0.5, -0.8, -0.8], [9.7, 7.4, 6.2, -1.2, -1.5, 0.4, -0.3, -0.6], [5.9, 3.7, 1.7, 0.3, -1.9, -3.0, 0.0, 0.4], [10.8, 6.6, 6.3, -0.7, 0.4, -0.2, -0.2, -0.4], [10.6, 10.8, 5.5, 3.2, 0.3, 0.3, -0.4, -0.5], [14.7, 9.8, 2.6, 1.3, -0.4, 0.6, 0.1, -0.7], [12.8, 8.2, 3.0, 1.8, -0.7, 1.6, 0.1, -0.4], [17.6, 7.5, 3.8, 3.2, 1.2, 1.2, 0.1, -0.3], [19.9, 9.8, 6.5, 1.9, 1.5, 2.3, 1.1, 0.2], [19.6, 12.9, 6.8, 1.4, -1.5, 3.3, 1.5, 0.6], [16.3, 11.4, 8.7, 4.8, 2.4, 2.4, 2.1, 0.7], [20.4, 14.1, 8.5, 5.7, 1.6, 4.1, 2.7, 1.0], [19.9, 15.2, 10.6, 5.0, 2.5, 3.7, 2.8, 0.9], [20.9, 14.4, 11.9, 6.7, 3.4, 4.2, 3.3, 1.2], [19.6, 14.5, 13.0, 8.0, 1.8, 5.4, 2.6, 2.0], [25.7, 16.2, 10.7, 6.9, 3.0, 5.4, 3.4, 1.7], [21.0, 14.1, 11.9, 5.8, 4.2, 5.3, 3.1, 2.3], [24.7, 15.1, 8.3, 7.7, 5.7, 4.1, 1.9, 0.2]], "slow_shared": 0.26, "slow_sd_db": 3.2}, "eaten": {"levels": [0.0, -0.9, -2.0, -1.9, -3.8, -3.5, -4.8, -8.1, -8.4, -9.0, -9.3, -8.8, -8.7, -9.9, -12.9, -14.1, -14.6, -16.3, -17.7, -19.0, -20.4, -21.4, -23.3, -25.4], "mod_excess": [[5.1, -1.3, -1.2, 1.3, 0.7, 0.9, -0.8, -3.0], [0.4, 2.6, 2.4, -0.6, -1.1, -1.5, -3.2, -4.4], [0.7, 3.6, 0.9, -2.9, -1.2, -0.9, -1.8, -3.2], [0.0, 1.0, 0.9, -2.6, -0.9, -0.7, -1.2, -1.4], [10.0, 6.7, 4.3, 2.7, 2.5, -0.6, -0.9, -1.9], [3.5, 4.4, -1.5, 0.5, -0.0, 0.1, -0.5, -1.1], [6.7, 3.7, -5.1, 1.0, 0.6, 0.6, 0.2, 0.6], [7.2, 5.5, 2.1, 2.4, -0.4, 0.1, 0.1, 0.2], [5.5, 3.7, 3.0, 2.5, 2.8, -1.6, 0.4, -0.8], [8.5, 6.7, -0.8, 0.6, 0.9, -0.2, 0.3, -0.3], [3.6, 6.0, 1.6, 2.0, 1.5, 0.2, -0.3, -0.3], [11.2, 5.9, 1.9, 2.7, 1.4, 0.7, 0.3, -1.1], [12.4, 8.0, 6.8, 3.6, 1.6, 3.2, 1.2, 0.7], [17.6, 11.7, 5.4, 4.9, 1.9, 1.6, 1.0, -0.0], [18.0, 10.6, 6.6, 4.5, 4.0, 1.4, 0.9, 0.5], [17.8, 13.2, 7.9, 5.9, 1.1, 3.1, 1.3, 0.6], [14.3, 11.9, 11.2, 6.8, 2.7, 0.7, 1.5, 1.0], [20.4, 17.7, 6.7, 6.0, 3.1, 3.2, 1.2, 1.4], [20.7, 17.2, 10.4, 7.2, 4.9, 3.9, 2.3, 1.8], [24.4, 18.5, 12.8, 6.0, 5.1, 4.3, 3.2, 0.8], [23.4, 19.7, 13.9, 7.8, 5.0, 6.5, 3.0, 2.2], [29.4, 21.3, 11.0, 7.1, 5.6, 4.9, 3.2, 1.2], [22.6, 19.1, 11.8, 7.6, 5.0, 2.8, 1.7, 1.9], [26.9, 20.5, 8.3, 5.9, 4.8, 2.7, 1.5, -0.0]], "slow_shared": 0.33, "slow_sd_db": 2.9}, "approach": {"levels": [-4.4, -2.6, -0.2, 0.0, -1.9, -2.5, -5.3, -5.2, -6.0, -5.7, -6.3, -5.9, -7.2, -5.6, -10.9, -12.8, -12.6, -15.0, -16.8, -17.8, -18.6, -18.8, -21.6, -23.1], "mod_excess": [[7.7, 4.5, 2.5, 2.3, 0.6, 0.9, 0.2, -1.0], [3.8, 2.4, -0.8, -0.5, 0.3, -0.1, 0.4, -0.5], [6.4, 5.5, 0.4, -1.2, -2.4, -1.3, -2.9, -2.3], [4.9, 3.3, 3.0, -1.6, -0.6, -0.3, -0.4, -0.3], [8.9, 3.8, 2.9, -1.0, 0.1, -1.6, -0.8, -1.7], [4.7, 4.9, 0.3, -1.2, -1.0, -0.2, -0.5, -0.5], [6.3, 4.5, -0.2, -1.6, -1.4, -0.6, 1.3, 1.6], [6.2, 4.9, 4.0, 1.2, 0.2, 0.0, 0.2, -0.6], [7.7, 8.2, 3.8, 0.2, 0.3, -2.3, 0.6, 0.2], [12.0, 10.4, 2.8, -0.5, 2.4, 0.7, 0.6, 0.4], [12.3, 8.0, 3.8, -0.1, 1.2, 0.5, 0.1, -0.6], [19.1, 15.1, 0.5, 0.2, 1.5, 1.2, 0.6, 0.1], [16.7, 10.1, 2.2, 3.2, 3.3, 2.7, 0.5, 0.4], [23.6, 10.9, 4.6, 3.9, 2.7, 2.2, 1.5, -0.1], [18.0, 12.5, 5.0, 3.2, 3.0, 1.7, 1.7, 0.1], [18.3, 13.4, 7.8, 4.0, 1.9, 1.6, 0.6, 0.9], [17.2, 14.2, 7.6, 5.4, 2.9, 1.7, 2.3, 0.6], [22.0, 14.0, 9.3, 5.8, 4.5, 3.6, 1.1, 0.9], [19.7, 15.6, 11.4, 6.3, 4.8, 4.9, 2.4, 1.3], [23.3, 18.0, 13.1, 7.5, 5.4, 5.4, 3.3, 1.4], [25.0, 17.2, 16.1, 10.7, 7.4, 5.9, 3.1, 1.6], [30.8, 20.0, 18.5, 12.3, 8.0, 5.5, 3.8, 2.0], [25.3, 19.8, 15.8, 11.4, 7.4, 5.1, 3.5, 1.7], [28.4, 21.0, 13.3, 12.1, 7.8, 5.3, 2.4, 0.1]], "slow_shared": 0.45, "slow_sd_db": 3.7}, "attack": {"levels": [-3.4, -1.9, 0.0, -4.8, -7.6, -12.8, -12.9, -14.7, -18.0, -19.6, -21.3, -22.5, -24.1, -24.8, -27.6, -31.0, -34.5, -34.1, -37.2, -38.9, -39.0, -40.0, -39.2, -37.4], "mod_excess": [[20.3, 13.6, 8.2, -0.1, 1.2, 0.8, -0.3, -4.0], [6.3, 0.4, 5.6, -6.7, -2.1, -1.6, -4.1, -5.3], [9.4, 2.9, 2.1, -3.2, -4.3, -6.5, -8.7, -12.1], [14.4, 13.1, 6.8, -5.1, 5.1, 2.4, 2.5, 5.5], [23.8, 11.5, -2.1, -1.4, -1.5, 0.9, 3.2, 5.3], [9.9, 1.2, 2.0, -2.8, 0.9, 2.7, 0.9, 0.7], [10.9, 5.0, -0.5, 4.2, 0.4, -0.3, 0.9, 1.2], [18.1, 9.2, 6.0, 0.2, -6.3, -1.9, 0.2, -0.3], [9.1, 10.6, 0.5, 1.6, 4.1, -3.4, -0.5, -0.7], [12.3, 14.0, 1.4, 1.4, 2.2, 1.3, 0.6, -1.2], [11.3, 12.5, 3.4, 3.8, -1.9, 0.8, 0.6, -2.5], [20.0, 19.9, 1.3, 3.2, -3.2, 0.6, 0.4, -0.9], [24.8, 14.6, 10.1, 0.2, -1.9, 2.3, 0.9, 0.5], [24.5, 8.3, -2.8, 7.0, 1.9, -0.0, 0.2, -1.0], [23.6, 10.2, 8.8, 7.7, 0.4, 0.4, 0.4, -1.0], [18.2, 16.2, 6.6, -2.0, 1.2, 1.3, 2.2, 1.1], [19.0, 11.2, 11.0, 8.3, -0.3, 0.5, 0.8, 1.4], [28.4, 16.3, 8.8, 11.8, 8.0, 4.5, 2.3, 2.2], [27.6, 23.5, 16.1, 17.1, 12.8, 7.4, 5.2, 1.6], [29.5, 23.8, 16.1, 9.8, 11.6, 10.1, 3.8, 1.2], [30.2, 22.8, 25.6, 12.5, 15.7, 11.3, 4.9, 3.1], [35.7, 36.0, 21.6, 12.5, 16.6, 12.9, 7.2, 5.7], [36.2, 25.3, 20.3, 20.9, 18.8, 12.9, 6.2, 1.7], [46.4, 29.3, 24.2, 25.1, 19.5, 14.6, 9.5, 5.2]], "slow_shared": 0.53, "slow_sd_db": 4.8}}
_MODBASE = {}


def _modbase(fc):
    """Plain Gaussian noise's own log-envelope modulation in band `fc` at TEXREF_RATES (power per Hz, natural log units)."""
    if fc not in _MODBASE:
        z = R(77).standard_normal(N(20))
        b = bp(z, fc / 2 ** (1 / 6), fc * 2 ** (1 / 6), 3)
        e = np.maximum(signal.decimate(np.abs(signal.hilbert(b)), 21, zero_phase=True), 1e-9)
        le = np.log(e)
        f, p = signal.welch(le - le.mean(), SR / 21, nperseg=8192)
        _MODBASE[fc] = [float(p[(f >= a) & (f < c)].mean()) for a, c in TEXREF_RATES]
    return _MODBASE[fc]


MOD_SR = 441.0


def _mod_noise(n, rng, power, loop):
    """A log-envelope movement whose spectrum (power per Hz, Welch's one-sided density) is `power` at TEXREF_RATES: built
    at 441 samples a second, each rate band scaled to its target as measured, then brought up to the audio rate."""
    m = int(n / SR * MOD_SR) + 2
    f = np.fft.rfftfreq(m, 1 / MOD_SR)
    x = np.zeros(m)
    for (a, c), pw in zip(TEXREF_RATES, power):
        if pw <= 0:
            continue
        sel = (f >= a) & (f < c)
        if not sel.any():
            continue
        z = (rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))) * sel
        comp = np.fft.irfft(z, m)
        d = np.mean(2 * np.abs(z[sel]) ** 2 / (MOD_SR * m)) + 1e-30
        x += comp * np.sqrt(pw / d)
    ts = np.arange(n) / SR * MOD_SR
    return np.interp(ts, np.arange(m), x)


def texref_stats(x):
    """The reference's measures on `x`: per band its level (dB under the loudest) and its log-envelope modulation over
    plain noise at TEXREF_RATES (as the references were measured), and how much slow movement the bands share."""
    lv, mod, slow_ = [], [], []
    for fc in TEXREF_FC:
        b = bp(x, fc / 2 ** (1 / 6), fc * 2 ** (1 / 6), 3)
        e = np.maximum(signal.decimate(np.abs(signal.hilbert(b)), 21, zero_phase=True), 1e-9)
        le = np.log(e)
        f, p = signal.welch(le - le.mean(), SR / 21, nperseg=min(8192, len(le)))
        lv.append(10 * np.log10(np.mean(b ** 2) + 1e-30))
        mod.append([10 * np.log10(p[(f >= a) & (f < c)].mean() + 1e-30) - 10 * np.log10(bb) for (a, c), bb in zip(TEXREF_RATES, _modbase(fc))])
        slow_.append(signal.sosfiltfilt(signal.butter(2, 1.0, "lowpass", fs=SR / 21, output="sos"), le - le.mean()))
    lv = np.array(lv)
    c = np.corrcoef(np.array(slow_))
    return {"levels": list(lv - lv.max()), "mod_excess": mod, "slow_shared": float(np.mean(c[np.triu_indices(len(TEXREF_FC), 1)]))}


_CAL = {}


def _texref_cal(state):
    """Corrections (levels, modulation dB) so that what `texref_texture` makes measures as the reference: two rounds of
    making 15 s, measuring, and taking the difference."""
    if state not in _CAL:
        lc = np.zeros(len(TEXREF_FC))
        mc = np.zeros((len(TEXREF_FC), len(TEXREF_RATES)))
        _CAL[state] = (lc, mc)
        for it in range(2):
            m = texref_stats(texref_texture(N(15), state, R(4242 + it)))
            ref = TEXREF[state]
            lc += 0.8 * (np.array(ref["levels"]) - np.array(m["levels"]))
            d = np.array(ref["mod_excess"]) - np.array(m["mod_excess"])
            mc += 0.8 * np.clip(d, -10, 10)
        _CAL[state] = (lc, mc)
    return _CAL[state]


def texref_texture(n, state, rng, loop=False, level_tilt=0.0):
    """The worm's earth: in each third octave, noise at the state's level, its envelope moved by a slow random
    swelling with the state's measured modulation excess over plain noise (a part shared by all bands as measured),
    log-normal (so its swells peak and its lows are long, as the reference's); calibrated (`_texref_cal`) so the result
    measures as the reference. `loop`: circular, so it wraps."""
    st = TEXREF[state]
    lc, mc = _CAL.get(state, (np.zeros(len(TEXREF_FC)), np.zeros((len(TEXREF_FC), len(TEXREF_RATES)))))
    share = max(min(st["slow_shared"], 0.9), 0.0)
    common = None
    out = np.zeros(n)
    f = np.fft.rfftfreq(n, 1 / SR)
    for j, fc in enumerate(TEXREF_FC):
        base = _modbase(fc)
        add = [b * max(10 ** ((ex + c) / 10) - 1, 0.0) for b, ex, c in zip(base, st["mod_excess"][j], mc[j])]
        own = _mod_noise(n, rng, add, loop)
        if common is None:
            common = _mod_noise(n, rng, add, loop)
        cm = common / (np.std(common) + 1e-12) * np.std(own)
        le = np.sqrt(share) * cm + np.sqrt(1 - share) * own
        env = np.exp(le - np.var(le) / 2)
        z = rng.standard_normal(n)
        carrier = unit(np.fft.irfft(np.fft.rfft(z) * floor_cut(f, fc / 2 ** (1 / 6), fc * 2 ** (1 / 6), 3), n))
        out += carrier * env * 10 ** ((st["levels"][j] + lc[j] + level_tilt * (j - 12)) / 20)
    return out


def texref(n, state, rng, loop=False, level_tilt=0.0):
    """`texref_texture`, calibrated."""
    _texref_cal(state)
    return texref_texture(n, state, rng, loop, level_tilt)


# ---- round 7's sounds: the worm's earth as the reference's ----------------------------------------------------------
def env_shape(n, on, rise, hold, fall, start=0.0):
    """0 before `on`, rising over `rise` (smooth), held for `hold`, falling exponentially with time constant `fall`."""
    t = tt(n)
    u = t - on
    return np.where(u < 0, start, start + (1 - start) * ss(u / rise)) * np.where(u > rise + hold, np.exp(-(u - rise - hold) / fall), 1.0)


def texref_blend(n, a, b, t_x, width, rng, loop=False):
    """State `a` turning into state `b` round t_x over `width` s."""
    t = tt(n)
    w = ss((t - t_x + width / 2) / width)
    return texref(n, a, rng, loop) * (1 - w) + texref(n, b, rng, loop) * w


def breach7_close():
    """The breach from close, round 7: the heave (breach A's, the approved family) under the worm's earth as the
    reference has it: the attack (dark, a huge low surge, its 0.2 Hz heave) for the first two seconds, turning into the
    full roar of moving earth (broad, sloping, swelling band by band) that rolls on for six and dies over three."""
    base, t0 = breach_A()
    n = N(13.0)
    base = np.concatenate([base, np.zeros(n - len(base))])
    rng = R(7100)
    earth = texref_blend(n, "attack", "roar", t0 + 2.0, 1.5, rng)
    earth *= env_shape(n, t0 - 0.05, 0.3, 5.5, 2.4)
    x = 0.6 * pk(base) + 1.0 * pk(earth)
    x = drive(x, 12.0)
    return fade(lowcut(x), 0, 1.5), t0


_B7 = {}


def breach7_tier(tier):
    if "x" not in _B7:
        _B7["x"] = breach7_close()[0]
    x = _B7["x"]
    if tier == "close":
        return x
    d = 300 if tier == "mid" else 800
    return fade(lowcut(distant_air(x, d, R(7101 + d))), 0, 1.0)


def bite7_close():
    """The bite from close, round 7: bite C under the earth going in: the attack and then the roar, bigger
    and longer than the breach's."""
    base = bite("C")
    n = len(base) + N(2.0)
    base = np.concatenate([base, np.zeros(n - len(base))])
    rng = R(7200)
    earth = texref_blend(n, "attack", "roar", HIT_AT + 1.5, 1.5, rng)
    earth *= env_shape(n, HIT_AT - 0.05, 0.25, 4.5, 2.6)
    x = 0.8 * pk(base) + 1.0 * pk(earth)
    return fade(lowcut(drive(x, 12.0)), 0, 1.5), earth


def bite7_mid():
    _, earth = bite7_close()
    base = bite("C")
    n = len(earth)
    base = np.concatenate([base, np.zeros(n - len(base))])
    x = pk(base) + 0.7 * pk(distant_air(earth, 300, R(7201)))
    return fade(lowcut(drive(x, 12.0)), 0, 1.5)


def slump7_close(k):
    """A tunnel ring dropping, close, round 7: the slump with the earth giving way (the attack, short)."""
    base = slump(k)
    n = len(base)
    rng = R(7300 + k)
    earth = texref_blend(n, "attack", "roar", HIT_AT + 0.8, 1.0, rng) * env_shape(n, HIT_AT - 0.03, 0.2, 1.0 + 0.4 * k, 1.2)
    return fade(lowcut(drive(pk(base) + 0.9 * pk(earth), 12.0)), 0, 1.0)


def grind7(k):
    """The burrowing heard close, round 7: the reference's approach (the earth moving over and round the worm under the
    land), 4 s, 1 s fades."""
    n = N(4.0)
    t = tt(n)
    x = texref(n, "approach", R(7400 + k))
    return lowcut(x * ss(t / 1.0) * ss((4.0 - t) / 1.0))


def rim7(k):
    """A hole's rim while the body pours through it, round 7: the full roar of the earth, 5 s, 1 s fades."""
    n = N(5.0)
    t = tt(n)
    x = texref(n, "roar", R(7500 + k))
    return lowcut(x * ss(t / 1.0) * ss((5.0 - t) / 1.0))


def tail7():
    """The tail out of its hole, round 7: the roar swelling as the last of the body goes by and dropping away as it
    leaves (TAIL_AT), the hole's air letting go low under it."""
    n = N(4.5)
    rng = R(7600)
    earth = texref(n, "roar", rng) * env_shape(n, 0.0, TAIL_AT + 0.1, 0.0, 0.9, start=0.35)
    low = pressure(n, TAIL_AT, 0.1, 0.9, 24, rng)
    return fade(lowcut(pk(earth) + 0.4 * pk(low)), 0, 0.8)


def settle7():
    """The land settling, round 7: the roar easing into the approach's quieter earth and dying over eight seconds."""
    n = N(9.0)
    x = texref_blend(n, "roar", "approach", 2.5, 3.0, R(7700)) * env_shape(n, 0.0, 0.5, 0.5, 2.8)
    return fade(lowcut(x), 0.05, 1.5)


def gulp7():
    """The jaws shutting over you, round 7: the roar rising over the last second (the earth and the mouth coming
    down), shut at GULP_SHUT, carrying straight on as the reference's being-eaten roar (no muffling: it carries on into
    the throat)."""
    n = N(3.0)
    rng = R(7800)
    x = texref_blend(n, "roar", "eaten", GULP_SHUT, 0.6, rng) * env_shape(n, 0.0, GULP_SHUT, 5.0, 3.0, start=0.3)
    x += 0.5 * pk(pressure(n, GULP_SHUT, 0.25, 1.0, 20, rng)) * np.std(x) * 3
    return fade(lowcut(x), 0.03, 0.4)


def throat7():
    """Inside, round 7: the reference's being-eaten roar, 8 s, seamless (no pulse)."""
    return drive(texref(N(THROAT_S), "eaten", R(7900), loop=True), 6.0)


def review7(outdir, ref1a=None, ref1b=None, ref2=None):
    """Round 7: each sound beside its reference moment, both at -18 LUFS, back to back with a second's gap
    (the reference first, marked REFERENCE: kept local, never published: third-party audio), and one mix of a
    strike with the catch on its timeline. The reference files are read only from the paths given."""
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    files = {p.stem: load(p) for p in sorted(OUT.glob("*.ogg"))}
    refs = {"1a": load(ref1a) if ref1a else None, "1b": load(ref1b) if ref1b else None, "2": load(ref2) if ref2 else None}
    items = []

    def lufs_gain(x, target=-18.0):
        tmp = str(outdir / "_t.wav")
        with wave.open(tmp, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((np.clip(x / (np.abs(x).max() + 1e-9) * 0.5, -1, 1) * 32767).astype("<i2").tobytes())
        l = lufs(tmp)
        os.remove(tmp)
        return x / (np.abs(x).max() + 1e-9) * 0.5 * 10 ** ((target - l) / 20)

    def pair(fn, title, ref_seg, ours, what, ref_what):
        a = lufs_gain(ref_seg)
        b = lufs_gain(ours)
        y = np.concatenate([a, np.zeros(N(1.0)), b])
        g, l = write_mp3(outdir / fn, y, gain_db=0.0)
        items.append({"file": fn, "title": title, "what": f"REFERENCE first ({ref_what}; local only, never published), then ours: {what}", "lufs_each": -18.0})

    def cut(r, a, b):
        return r[N(a):N(b)]

    def seq(cues, length):
        y, _ = mix(cues, files, length)
        return y
    if refs["1a"] is not None:
        pair("AB_breach_from_close.mp3", "Breach from close: the reference's attack, then ours", cut(refs["1a"], 19.5, 27.0),
             files["breach_close"][:N(9.0)], "the breach from ~60 blocks (the heave under the attack turning into the roar)", "the reference worm's attack, video 0:34.5-0:42")
        pair("AB_breach_from_300.mp3", "Breach from 300 blocks: the reference's attack, then ours", cut(refs["1a"], 19.5, 27.0),
             files["breach_mid"][:N(9.0)], "the same breach through 300 blocks of air", "the same moment")
    if refs["1b"] is not None:
        pair("AB_bite_close.mp3", "The bite from close: the reference worm's roar, then ours", cut(refs["1b"], 0.0, 9.0),
             files["bite_close"][:N(9.0)], "the bite from ~60 blocks (bite C under the earth going in)", "the reference worm, video 0:55-1:04")
        pair("AB_rim.mp3", "The body pouring through a hole: the reference worm's roar, then ours", cut(refs["1b"], 4.0, 13.0),
             seq([(0.0, "rim1", 1.0, 1.0), (4.0, "rim2", 0.95, 1.0), (8.0, "rim3", 0.9, 1.0)], 13.0)[:N(10.0)], "the hole's rim from 60 blocks while the body pours", "video 0:59-1:08")
        pair("AB_tail_settle.mp3", "Tail out and the land settling: the roar dying in the reference, then ours", cut(refs["1b"], 14.0, 20.0),
             seq([(0.0, "tail_d", 1.0, 1.0), (3.0, "settle_d", 0.9, 1.0)], 12.0), "the tail leaving its hole, then the land settling", "the reference worm's roar dying, video 1:09-1:15")
    if refs["2"] is not None:
        pair("AB_approach.mp3", "Something huge under the land: the reference's approach, then ours", cut(refs["2"], 0.0, 12.0),
             seq([(0.0, "sign", 1.0, 1.0)] + [(1.0 + 3 * j, f"grind{1 + j % 3}", 0.9 * nearness(abs(150 - 30 * j)), 1.0) for j in range(4)], 11.0),
             "the wormsign with the burrowing as it passes close", "the second video's approach, 0:00-0:12")
        pair("AB_eaten.mp3", "Being eaten: the reference, then ours", cut(refs["2"], 15.5, 27.0),
             seq([(0.0, GULP_PICK, 1.0, 1.0), (GULP_SHUT, "ride_a_start", 1.0, 1.0), (GULP_SHUT + 0.5, f"throat_{THROAT_PICK.lower()}", 0.6, 1.0),
                  (GULP_SHUT + RIDE_START, "ride_a_loop", 1.0, 0.95)], 11.5), "the gulp, the throat and the ride's air (take A)", "the second video, 0:15.5-0:27")
    # the strike with the catch: the scripted approach, breach, bellow and dive from 150 blocks, caught on the bite, the
    # ride (take A), the spit, then the land settling (a hunt's own timeline needs the land's playback to carry volume
    # and pitch: see the report)
    base = [c for c in script_cues(150) if c[0] < 18.9 and not c[1].startswith(("bite", "quake2", "body", "tail", "rim"))]
    shut = 19.0
    spit_at = shut + 9.6
    cat = [(shut - GULP_SHUT, GULP_PICK, 1.0, 1.0), (shut, "ride_a_start", 1.0, 1.0), (shut + 0.5, f"throat_{THROAT_PICK.lower()}", 0.45, 1.0)]
    t, k = shut + RIDE_START, 0
    while t < spit_at - RIDE_END_OPEN:
        p = [0.95, 1.06, 1.12][min(k, 2)]
        cat.append((t, "ride_a_loop", 1.0, p))
        t += RIDE_LOOP / p
        k += 1
    cat += [(spit_at - RIDE_END_OPEN, "ride_a_loop", None, 1.0), (spit_at - RIDE_END_OPEN, "ride_a_end", 1.0, 1.0), (spit_at - SPIT_AT, "spit", 1.0, 1.0),
            (spit_at - SPIT_AT + 0.12, f"throat_{THROAT_PICK.lower()}", None, 1.0), (spit_at + 0.2, "breach_mid", 0.6, 1.08),
            (spit_at + 1.0, "rim1", 0.4, 1.0), (spit_at + 6.0, "tail_d", 0.6, 1.0), (spit_at + 9.0, "settle_d", 0.8, 1.0)]
    y, gains = mix(base + cat, files, spit_at + 19.0)
    g, l = write_mp3(outdir / "strike_with_the_catch_from_150.mp3", y)
    items.append({"file": "strike_with_the_catch_from_150.mp3", "title": "A strike with the catch, from 150 blocks", "what": "The approach under the land, the breach, the rise and bellow, the dive; caught on the bite: the gulp, the ride down the throat (wind take A), the spit, the worm surfacing again and the land settling.", "lufs": round(l, 1), "game_limiter_max_db": round(-20 * np.log10(gains.min()), 1)})
    (outdir / "review.json").write_text(json.dumps({"laser": "worldeater", "round": 7, "local_only": "the AB_ files hold third-party reference audio: never publish", "items": items}, indent=1))
    print("wrote", len(items), "files to", outdir)


# ---- round 8: the re-voice across the sound design -----------------------------------------------------------------
# The approved sounds keep every sample's timing and envelope: only their tone changes, a fixed zero-phase EQ worked
# out per file so that from 300 Hz up they reach the new voice's bed (the reference's bed under the croak, as measured),
# never cut, lifted at most 15 dB, smooth across bands; under 300 Hz
# left as it is. Then the same integrated loudness as the original. The originals stay; these are NAME_rv.
RV_BED = {   # target band shares (dB of the whole) from 300 Hz up, per group
    "event": {(330, 750): -9.5, (750, 1500): -15.8, (1500, 3000): -21.0, (3000, 6000): -27.0, (6000, 12000): -34.0},
    "travel": {(330, 750): -12.0, (750, 1500): -18.0, (1500, 3000): -25.0, (3000, 6000): -32.0, (6000, 12000): -40.0},
    # (the bellow's voice: only its body lifted; over 1.5 kHz it has almost nothing but the encoder's own noise, which a
    # lift would bring up as crinkle)
    "voice": {(330, 750): -9.0, (750, 1500): -15.0, (1500, 3000): -99.0, (3000, 6000): -99.0, (6000, 12000): -99.0},
    "ground": {(330, 750): -16.0, (750, 1500): -24.0, (1500, 3000): -32.0, (3000, 6000): -40.0, (6000, 12000): -48.0},
}
RV_GROUP = {"sign": "travel", "sign_short": "travel", "move1": "travel", "quake1": "ground", "rise": "event",
            "dive": "event", "body1": "event", "tail_in": "event", "spit": "event", "bellow_a": "voice", "bite_c": "event"}


def rv_gain_curve(x, group, most=15.0):
    """The EQ (gain per FFT bin) that lifts `x`'s bands from 300 Hz up to the group's bed shares, interpolated smoothly
    on a log-frequency axis between band centres; 0 dB at and under 250 Hz."""
    tgt = RV_BED[group]
    f, p = signal.welch(x, SR, nperseg=16384)
    tot = p.sum()
    cents, gains = [250.0], [0.0]
    for (lo, hi), share in tgt.items():
        have = 10 * np.log10(p[(f >= lo) & (f < hi)].sum() / tot + 1e-30)
        cents.append(np.sqrt(lo * hi))
        gains.append(float(np.clip(share - have, 0.0, most)))
    # (a lifted band raises the whole a little: one more pass on the shares is not needed for a curve this gentle)
    lc, g = np.log2(np.array(cents)), np.array(gains)
    if group == "voice":
        # (and nothing lifted past 1.5 kHz)
        lc, g = np.append(lc, np.log2(1800.0)), np.append(g[:3], 0.0)
        lc = lc[:len(g)]
    return lc, g


def revoice(name):
    """`name`'s approved file re-voiced (see above): same samples in time, a new tone, the same loudness."""
    x = load(OUT / f"{name}.ogg")
    lc, g = rv_gain_curve(x, RV_GROUP[name])
    n = len(x)
    fr = np.fft.rfftfreq(n, 1 / SR)
    gdb = np.interp(np.log2(np.maximum(fr, 1.0)), lc, g, left=0.0, right=g[-1])
    y = np.fft.irfft(np.fft.rfft(x) * 10 ** (gdb / 20), n)
    return x, y


def write_revoiced(names=None):
    """Writes NAME_rv.ogg beside each approved NAME.ogg, at the original's integrated loudness (EBU R128), the loudest
    instants bent softly between -1.5 and -0.3 dBFS only if the lift pushed them over (a lower knee bent the lifted
    peaks into faint 2-3 kHz streaks)."""
    out = {}
    for name in names or RV_GROUP:
        x, y = revoice(name)
        tmp = str(OUT / f"_{name}.wav")

        def lufs_of(z):
            with wave.open(tmp, "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
                w.writeframes((np.clip(z, -1, 1) * 32767).astype("<i2").tobytes())
            return lufs(tmp)
        lx = lufs_of(x)
        for _ in range(3):
            y = y * 10 ** ((lx - lufs_of(y)) / 20)
            a = np.abs(y)
            c, k = 10 ** (-0.3 / 20), 10 ** (-1.5 / 20)
            y = np.where(a > k, np.sign(y) * (k + (c - k) * np.tanh((a - k) / (c - k))), y)
        ly = lufs_of(y)
        os.remove(tmp)
        write_ogg(OUT / f"{name}_rv.ogg", y)
        out[name] = (lx, ly)
        print(f"revoiced {name:11s} {lx:6.1f} -> {ly:6.1f} LUFS")
    return out


# ---- round 8c: the beds ducked under the voice ------------------------------------------------------------------------
# A cue's volume can't change once it plays, so the duck is baked in: NAME_dk is the bed with a smooth dip of `db` while
# the voice phrase over it sounds (from `start` s into the file for `length` s; 0.15 s down, 1.0 s back up).
DUCKS = {
    # name: (start s, length s, dB): the bite beds under a bite call (from the blow, ~3 s). (The breach's beds under the
    # croak are the burst's own `_dk` takes now, made by the burst's generator.)
    "bite_close": (0.1, 3.2, -9.0), "bite_mid": (0.1, 3.2, -11.0), "bite_c_far": (0.1, 3.2, -6.0),
}
# (round 9: the K1 burst's tiers under the croak, from 0.3 s after its step (the croak 0.45 after it) for the longest
# take's phrase: the burst's own `_dk` dipped 2-4 dB and left the croak level with it (0 dB in the game's terms); 10 and
# 12 dB give the croak +5-9 dB over it, the blast itself before the dip untouched)
BURST_STEP = {"k1a": 1.5, "k1b": 1.2, "k1c": 1.4, "k1d": 1.0}
# (round 12, so the explosion is heard: the whump's first second after its step is the plain file's, the dip
# only from 1.0 s, as its tail thins and the croak's pulses begin)
for _tk, _st in BURST_STEP.items():
    DUCKS[f"breach_burst_{_tk}_close"] = (_st + 1.0, 4.8, -10.0)
    DUCKS[f"breach_burst_{_tk}_mid"] = (_st + 1.0, 4.8, -12.0)


def ducked(name):
    start, length, db = DUCKS[name]
    x = load(OUT / f"{name}.ogg")
    t = tt(len(x))
    down = ss((t - start + 0.15) / 0.15) * (1 - ss((t - start - length) / 1.0))
    return x * 10 ** (db * down / 20)


def write_ducked(names=None):
    for name in names or DUCKS:
        y = ducked(name)
        (write_ogg_float if np.abs(y).max() > 1.0 else write_ogg)(OUT / f"{name}_dk.ogg", y)
        print("ducked", name)


def write_ogg_float(path, x, q=6):
    """As write_ogg, but floating point: peaks over 0 dBFS kept (as the Payload's and the Nuke's blasts have; the game
    mixes in floating point and its limiter takes the sum)."""
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis",
                    "-q:a", str(q), "-fflags", "+bitexact", "-flags:a", "+bitexact", "-serial_offset", "1", str(path)],
                   input=x.astype("<f4").tobytes(), check=True)


# ---- round 12: the ground under the land (the travel set's `_real` takes) ---------------------------------------------
GROUND_SRC = Path(os.environ.get("WE_SOUND_SRC", "worldeater-sound-src")) / "voice/ship_travel/ogg"   # the source takes: not in the repository
GROUND = {"ground_travel_close": "travel_ground_real_close", "ground_travel_mid": "travel_ground_real_mid",
          "ground_travel_far": "travel_ground_real_far", "ground_hole_close": "hole_grind_real_close",
          "ground_hole_mid": "hole_grind_real_mid", "ground_thrash_big_a": "thrash_big_a_real",
          "ground_thrash_big_b": "thrash_big_b_real", "ground_thrash_mid_a": "thrash_mid_a_real",
          "ground_thrash_mid_b": "thrash_mid_b_real"}


def write_ground():
    """The travel set's files as they are (mono), and for each loop an `_out` copy letting go over its last
    3 s (a quarter-cosine), for the last copy of a run, as voice_travel_out."""
    for name, src in GROUND.items():
        x = load(GROUND_SRC / f"{src}.ogg")
        write_ogg(OUT / f"{name}.ogg", x)
        if "_travel_" in name or "_hole_" in name:
            k = N(3.0)
            y = x.copy()
            y[-k:] *= np.cos(0.5 * np.pi * np.linspace(0, 1, k))
            write_ogg(OUT / f"{name}_out.ogg", y)
        print("ground", name, "from", src)


# ---- round 14: the worm passing under the land (three PASS takes) -----------------------------------------------------
PASS_SRC = Path(os.environ.get("WE_SOUND_SRC", "worldeater-sound-src")) / "voice/travel_r3"
PASS_TAKES = {"a": "pass_a_rockslide", "b": "pass_b_segments", "c": "pass_c_grind"}
PASS_CROAK_FAR_DB = -12.0   # the travelling croak at the pass's far end, against its nearest


def write_pass():
    """The pass set as it is (mono ogg): `ground_pass_X_TIER` for TIER close_near / close_far (the
    breach near the player or far off), mid, far: 12 s of ground (closest at the mark in passes.json, the burst's step
    at 12.0 s) and its reverb tail; `ground_lead_X` (its 8 s seamless far loop). And `voice_pass_X_TIER`: the
    travelling croak over the same 12 s, its level riding the pass's nearness `k` (PASS_CROAK_FAR_DB far, 0 at its
    closest), its last second let go."""
    import shutil
    marks = json.loads((PASS_SRC / "wav" / "passes.json").read_text())
    for tk, src in PASS_TAKES.items():
        for ours, theirs in (("close_near", "close_breach_near"), ("close_far", "close_breach_far"), ("mid", "mid"), ("far", "far")):
            shutil.copyfile(PASS_SRC / "ship" / "ogg" / f"{src}_{theirs}.ogg", OUT / f"ground_pass_{tk}_{ours}.ogg")
            # (round 14: for a run too short for the whole pass, or known too late (a hunt's next arch is known a few
            # seconds ahead): `_c1` from 2.5 s before its closest (the step up still in it), `_c2` from its closest;
            # each faded in over 0.3 s; we_sounds.rs PASS_CUTS)
            x = load(PASS_SRC / "ship" / "ogg" / f"{src}_{theirs}.ogg")
            for cut, cn in ((marks[src]["t_close"] - 2.5, "c1"), (marks[src]["t_close"], "c2")):
                y = x[N(cut):].copy()
                k = N(0.3)
                y[:k] *= np.sin(0.5 * np.pi * np.linspace(0, 1, k))
                write_ogg(OUT / f"ground_pass_{tk}_{ours}_{cn}.ogg", y)
        shutil.copyfile(PASS_SRC / "ship" / "ogg" / f"{src}_leadin_far_loop.ogg", OUT / f"ground_lead_{tk}.ogg")
        m = marks[src]
        kk = np.interp(np.arange(N(12.0)) / SR, np.arange(len(m["k"])) / 100.0, m["k"])
        g = 10 ** (PASS_CROAK_FAR_DB * (1 - kk) / 20)
        for tier in ("close", "mid", "far"):
            lp = load(OUT / f"voice_travel_loop_{tier}.ogg")
            y = np.tile(lp, 2)[: N(12.0)] * g
            k = N(1.0)
            y[-k:] *= np.cos(0.5 * np.pi * np.linspace(0, 1, k))
            write_ogg(OUT / f"voice_pass_{tk}_{tier}.ogg", y)
            for cut, cn in ((m["t_close"] - 2.5, "c1"), (m["t_close"], "c2")):
                z = y[N(cut):].copy()
                kz = N(0.3)
                z[:kz] *= np.sin(0.5 * np.pi * np.linspace(0, 1, kz))
                write_ogg(OUT / f"voice_pass_{tk}_{tier}_{cn}.ogg", z)
        print("pass", tk, "set and croak; closest at", m["t_close"])


# ---- round 12: the burst as loud as the mod's other blasts --------------------------------------------------------------
# The burst's set as made was 4-5 dB under the Payload's and the Nuke's blast files at its
# loudest half second (-8..-10 against -5.4 and -3.6), its peaks held at -1 dBFS. Made +BURST_LIFT dB, its peaks bent
# softly over +1 dBFS and held under +2.5 (the Payload's blast peaks at +2.1).
BURST_SRC = "7dd4281"
BURST_LIFT = 4.0


def write_burst_loud():
    import tempfile
    for tk in list(BURST_STEP) + ["hop"]:
        for tier in ("close", "mid", "far"):
            name = f"breach_burst_{tk}_{tier}"
            blob = subprocess.run(["git", "-C", str(ROOT), "show", f"{BURST_SRC}:orbital-sounds/assets/orbital/sounds/worldeater/{name}.ogg"],
                                  capture_output=True, check=True).stdout
            with tempfile.NamedTemporaryFile(suffix=".ogg", dir=OUT.parent) as f:
                f.write(blob)
                f.flush()
                x = load(f.name)
            # (round 13: the hop's whump, now the landings' and the jaws' thud, 4 dB more: its peaks were at -4)
            y = x * 10 ** ((BURST_LIFT + (4.0 if tk == "hop" else 0.0)) / 20)
            a = np.abs(y)
            k, c = 10 ** (1.0 / 20), 10 ** (2.5 / 20)
            y = np.where(a > k, np.sign(y) * (k + (c - k) * np.tanh((a - k) / (c - k))), y)
            write_ogg_float(OUT / f"{name}.ogg", y)
            print(f"loud {name}: peak {20 * np.log10(np.abs(y).max()):.1f} dBFS")
            if tk in BURST_STEP:
                # (round 13: `_short`, its roll let go from 1.6 to 2.8 s after the step, for a hop whose landing
                # follows within 6 s: the long roll filled the half second before the landing's thud)
                t = tt(len(y))
                u = np.clip((t - BURST_STEP[tk] - 1.6) / 1.2, 0, 1)
                z = y * np.cos(0.5 * np.pi * u)
                z = z[: N(BURST_STEP[tk] + 2.9)]
                write_ogg_float(OUT / f"{name}_short.ogg", z)


# ---- round 10: the travel loop's last copy letting go ----------------------------------------------------------------
def write_travel_out():
    """voice_travel_out_TIER: the travel loop with its last 3 s let go (a quarter-cosine, equal power
    against the rise that starts under it), for the last copy before each emergence (we_sounds.rs `travel`): the loop
    ended at its loudest, 9 dB over the rise's start, a hard edge in the game's recording."""
    for tier in ("close", "mid", "far"):
        x = load(OUT / f"voice_travel_loop_{tier}.ogg")
        k = N(3.0)
        x = x.copy()
        x[-k:] *= np.cos(0.5 * np.pi * np.linspace(0, 1, k))
        write_ogg(OUT / f"voice_travel_out_{tier}.ogg", x)
        print("wrote", f"voice_travel_out_{tier}")


# ---- round 2's review: only what is new ------------------------------------------------------------------------------
TAKES2 = {
    "breach_a": ("Breach take A: Heave", "Bite C's family: the land straining for half a second, struck from below by a long soft push, its lowest modes ringing down, then rolling away in three surges.",
                 "The approved bite's own model, sized for the breach: no debris, no air; a heave you feel coming."),
    "breach_b": ("Breach take B: Ringdown", "No noise at all: the land as one vast body, 1,600 of its own modes (18-520 Hz, too dense to ring as a note) struck from below and struck again as it settles, the displaced air's single deep push under it.",
                 "Deterministic modal model, no noise layer anywhere: the land ringing down like a struck mountain."),
    "breach_c": ("Breach take C: Air front", "The boom of the air shoved aside: one deep pressure front, then the land rolling it back as thirty-odd returns off hills, each lower and later, as thunder rolls.",
                 "The air's boom and its echoes only: a pressure front and a rolling train of returns, no ground layer."),
    "breach_d": ("Breach take D: Upheaval", "No blow at all: a sub swell from below, then the ground's resonances opening upward as it bursts and closing as it rolls on and dies over six seconds.",
                 "One long continuous roar with no impact: the land failing, not struck."),
    "tail_a": ("Tail out take A: Release", "The body's groan dropping away as the end passes, and the emptied hole's pressure let go as one deep soft boom, the ground relaxing after.",
               "A boom and a dropping groan: closest to tail_in, which passed."),
    "tail_b": ("Tail out take B: Suck", "Air drawn down into the emptied shaft (a low pull darkening, no hiss), and the shaft's own column resonance swelling and dying as it fills.",
               "An air column sounding: hollow and tonal-ish, no impact."),
    "tail_c": ("Tail out take C: Last pass", "The approved body sound's last stretch passing over and away, sliding down as it goes, and one slow low shrug of the ground as the weight leaves.",
               "The body sound ending: a continuation of body1, the least of an event."),
    "throat_a": ("Throat take A: Gullet", "The approved body heard from inside its walls: stone resonances muffled under 250 Hz swelling in slow irregular surges, pressure under it, the outside a faint rumble. 8 s, loops.",
                 "The body family from inside: the most motion."),
    "throat_b": ("Throat take B: Tunnel", "Air pushed along a stone tube 60 blocks across: a dark rush with the tube's crowded low resonances in it, its colour drifting as the gullet bends. 8 s, loops.",
                 "Moving air in a vast pipe: the most 'space'."),
    "throat_c": ("Throat take C: Pressure", "Almost nothing but weight: slow pressure breathing 16-60 Hz, the walls' grinding far down the body, the outside all but gone. 8 s, loops.",
                 "The emptiest: the world gone away."),
}
ALTS2 = [
    ("slump1", "Tunnel ring, round 2: slump 1", "A ring dropping as a slump with weight: a long push into the land's lowest modes, then a long low tail rolling away (bite C's family).", "Was: a short thud with venting air and sliding earth. Now: no air, no earth, a heavier push and a rolling tail twice as long."),
    ("slump2", "Tunnel ring, round 2: slump 2", "As slump 1, lower, with two rolls.", "Same change as slump 1; each slump has its own pitch, push and roll."),
    ("slump3", "Tunnel ring, round 2: slump 3", "As slump 1, higher, one long roll.", "Same change as slump 1."),
    ("settle_b", "Settling, round 2", "The land's last rolls: five surges spaced ever wider, each lower and quieter, over the ground going still.", "Was: a rumble with sliding earth and air. Now: only the ground rolling and stilling, bite C's family."),
    ("gulp_b", "Gulp, round 2 B: Eclipse", "The world going away: the land's sound narrowing to nothing as the mouth comes over, the mountain's weight on the air, shut with no impact at all.", "Was: a sweep and a padded thud (a swallow). Now: no thud, the outside fades out under pressure."),
    ("gulp_c", "Gulp, round 2 C: Weight", "The approved body bearing down over you, then one very soft, very heavy closure under 150 Hz rolling on, the outside cut under it.", "Was: a sweep and a padded thud. Now: the body's mass arriving and a far softer, heavier close."),
    ("land1", "Smaller landing 1 (hops)", "A hop's landing in bite C's family: one blow and two short surges, higher and lighter.", "Was: bite takes A and B played higher. Now: lighter versions of C, the bite played."),
    ("land2", "Smaller landing 2 (hops)", "As landing 1, higher still, its own blow and rolls.", "As landing 1."),
]


def review2(outdir):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    files = {p.stem: load(p) for p in sorted(OUT.glob("*.ogg"))}
    items = []
    for name, (title, what, diff) in TAKES2.items():
        fars = (False, True) if name.startswith("breach") else (False,)
        for far in fars:
            key = name + ("_far" if far else "")
            fn = name.replace("_", "_take_", 1)[:-1] + name[-1].upper() + ("_far" if far else "") + ".mp3"
            g, l = write_mp3(outdir / fn, files[key])
            items.append({"file": fn, "title": title + (" (800 blocks)" if far else ""), "what": what if not far else "The same take through 800 blocks of air.",
                          "different": diff, "take": True, "lufs": round(l, 1)})
    for name, title, what, changed in ALTS2:
        g, l = write_mp3(outdir / f"{name}.mp3", files[name])
        items.append({"file": f"{name}.mp3", "title": title, "what": what, "changed": changed, "lufs": round(l, 1)})
    mixes = {}
    for d in (250, 800):
        mixes[d] = mix(script_cues(d), files, 48.0)
    g, l = write_mp3(outdir / "strike_250_blocks.mp3", mixes[250][0])
    g2, l2 = write_mp3(outdir / "strike_800_blocks.mp3", mixes[800][0], gain_db=g)
    picks = f"bellow A, bite C, breach {BREACH_PICK}, tail out {TAIL_PICK}, rings {SINK_SET}, {SETTLE_PICK}"
    for d, ll in ((250, l), (800, l2)):
        items.append({"file": f"strike_{d}_blocks.mp3", "title": f"The whole scripted strike from {d} blocks",
                      "what": f"Every cue as the game plays it (mono, 20 Hz ticks, its limiter), {d} blocks from the breach: {picks}. Same gain for both.",
                      "changed": "Round 2's picks in place of the rejected and doubted sounds.",
                      "lufs": round(ll, 1), "game_limiter_max_db": round(-20 * np.log10(mixes[d][1].min()), 1)})
    y, gains = mix(caught_cues(DIVE_HIT) + [(0.0, "dive", 0.9, 1.0)], files, 22.0)
    g3, l3 = write_mp3(outdir / "caught_sequence.mp3", y)
    items.append({"file": "caught_sequence.mp3", "title": "Caught: the whole sequence", "what": f"The dive, {GULP_PICK} as the mouth closes over you, ~9 s inside (throat {THROAT_PICK}), the spit.",
                  "changed": "New gulp and throat; the throat no longer has a heartbeat.", "lufs": round(l3, 1)})
    (outdir / "review.json").write_text(json.dumps({"laser": "worldeater", "round": 2, "picks": {"breach": BREACH_PICK, "tail_out": TAIL_PICK, "throat": THROAT_PICK, "rings": SINK_SET, "settle": SETTLE_PICK, "gulp": GULP_PICK, "bellow": "A", "bite": "C"}, "items": items}, indent=1))
    print("wrote", len(items), "review files to", outdir)
    for d in (250, 800):
        e = st_rms(mixes[d][0], 0.5)
        print(f"mix {d}: limiter at most {-20 * np.log10(mixes[d][1].min()):.1f} dB;", " ".join(f"{20 * np.log10(e[N(t)] + 1e-9):.0f}" for t in np.arange(6, 24, 0.5)))


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--measure":
        measure_dir(OUT, sys.argv[2:] or None)
    elif len(sys.argv) == 3 and sys.argv[1] == "--review":
        review2(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "--review3":
        review3(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "--review4":
        review4(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "--review5":
        review5(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "--review6":
        review6(sys.argv[2])
    elif len(sys.argv) == 2 and sys.argv[1] == "--ship-pass":
        write_pass()
    elif len(sys.argv) == 2 and sys.argv[1] == "--burst-loud":
        write_burst_loud()
        write_ducked([n for n in DUCKS if n.startswith("breach_burst_")])
    elif len(sys.argv) == 2 and sys.argv[1] == "--ship-ground":
        write_ground()
    elif len(sys.argv) == 2 and sys.argv[1] == "--travel-out":
        write_travel_out()
    elif len(sys.argv) >= 2 and sys.argv[1] == "--duck":
        write_ducked(sys.argv[2:] or None)
    elif len(sys.argv) >= 2 and sys.argv[1] == "--revoice":
        write_revoiced(sys.argv[2:] or None)
    elif len(sys.argv) >= 3 and sys.argv[1] == "--review7":
        review7(sys.argv[2], *sys.argv[3:6])
    elif len(sys.argv) >= 3 and sys.argv[1] == "--only":
        fs = build_only(sys.argv[2:])
        write_all(fs)
    else:
        # (only the files the mod has: the older rounds' takes are made for their reviews, never written into it)
        have = set(json.loads((OUT.parent.parent / "sounds.json").read_text()))
        r = recipes()
        write_all({k: (fn(), key) for k, (fn, key) in r.items() if f"worldeater.{k}" in have})
