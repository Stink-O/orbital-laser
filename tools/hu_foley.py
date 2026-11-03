"""Field-recording building blocks for the Hurricane's accents (tools/sounds_hurricane.py): wood giving way, soil
tearing, leaves thrashing, things knocking and scraping across the ground, a body shoved through gusting air, and the
open space they are heard in.

Nothing here is a designed one-shot. Every event is noise through causal filters (a real thing's sound starts when it
is struck and only decays after: no pre-ring), no two alike (its band, its length, its strength drawn afresh), most of
them clusters of smaller events rather than one clean pulse, and nothing rings at a pitch: no sines, no resonant
bodies, no sweeps. What sounds alike in nature is a texture of many small irregular things, so that is how they are
made: heavy-tailed sizes, Poisson timing whose rate itself wanders, surges and gaps.
"""
import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

import soundlib
from soundlib import SR
import sounds_themes as T
import sounds_pk_blast as PB


def rng():
    return soundlib.rng


def n_of(d):
    return int(SR * d)


def cband(x, lo=None, hi=None, order=2):
    """`x` through a causal Butterworth band (lo/hi Hz, either may be None)."""
    if lo and hi:
        sos = butter(order, [lo, min(hi, SR * 0.45)], "bandpass", fs=SR, output="sos")
    elif lo:
        sos = butter(order, lo, "highpass", fs=SR, output="sos")
    elif hi:
        sos = butter(order, min(hi, SR * 0.45), "lowpass", fs=SR, output="sos")
    else:
        return x
    return sosfilt(sos, x)


def grains(d, rate, taus=(0.012, 0.025, 0.05)):
    """sounds_pk_blast's grains (many little surges at random, heavy-tailed, averaging 1), by FFT convolution: long
    surges cost nothing more than short ones."""
    n = n_of(d)
    out = np.zeros(n)
    for tau in taus:
        x = np.zeros(n)
        k = rng().poisson(rate * d / len(taus))
        np.add.at(x, rng().integers(0, n, k), np.minimum(rng().pareto(2.5, k) + 0.2, 6.0))
        s = np.arange(int(tau * SR * 6)) / SR
        kern = (1 - np.exp(-s / 0.002)) * np.exp(-s / tau)
        out += fftconvolve(x, kern)[:n] / (tau * SR)
    return np.maximum(out, 0) / (np.mean(out) + 1e-9)


def put(x, y, t0):
    k = int(t0 * SR)
    if k < 0:
        y, k = y[-k:], 0
    m = min(len(y), len(x) - k)
    if m > 0:
        x[k:k + m] += y[:m]


def wander(n, lo, hi, depth_db):
    """A gain curve wandering by about `depth_db` dB, its movement between `lo` and `hi` Hz."""
    return np.exp(depth_db * PB.slow_random(n, lo, hi) / 8.686)


# ---------------------------------------------------------------------------------------------------- small events
def fracture(size=1.0, bright=1.0, dull=0.0):
    """One fibre or splinter giving: a few micro-breaks within milliseconds of each other (never one clean pulse), each
    a short burst of noise in its own band, the bigger ones longer and lower; `dull` (0..1) takes the top off (inside
    the wood, under bark or soil). Unit peak, dry."""
    m = n_of(0.03 + 0.05 * size)
    x = np.zeros(m)
    k = 1 + int(rng().poisson(1.5 + 2.0 * size))
    t = 0.0
    for i in range(k):
        a = (1.0 if i == 0 else rng().uniform(0.15, 0.8)) * size ** 0.5
        mm = n_of(rng().uniform(0.002, 0.006 + 0.012 * size))
        s = np.arange(mm) / SR
        lo = rng().uniform(250, 1400) / (0.6 + 0.6 * size)
        hi = min(rng().uniform(2500, 9000) * bright * (1 - 0.75 * dull), 16000)
        b = cband(rng().standard_normal(mm), lo, max(hi, lo * 2.5), 2) * np.exp(-s / rng().uniform(0.0006, 0.0025 + 0.004 * size))
        put(x, b * a, t)
        t += rng().exponential(0.0035 * (0.5 + size))
    return x / (np.abs(x).max() + 1e-12)


def knock(size=1.0, hard=0.5):
    """Wood or a clod of earth hitting the ground or another thing: a dull low-mid burst (no ring), a short crunch of
    contact on its front, sometimes doubled as it lands unevenly. Unit peak, dry."""
    m = n_of(0.08 + 0.12 * size)
    s = np.arange(m) / SR
    dec = rng().uniform(0.010, 0.022) + 0.03 * size
    body = cband(rng().standard_normal(m), rng().uniform(70, 140), rng().uniform(450, 1100) / (0.7 + 0.4 * size), 2)
    body *= (1 - np.exp(-s / 0.0015)) * np.exp(-s / dec)
    con = cband(rng().standard_normal(m), 600, rng().uniform(2500, 6000), 2) * np.exp(-s / rng().uniform(0.002, 0.006))
    x = T.unit(body) + T.unit(con) * hard * 0.6
    if rng().random() < 0.45:
        y = np.zeros(m)
        put(y, x * rng().uniform(0.3, 0.7), rng().uniform(0.006, 0.03))
        x = x + y
    return x / (np.abs(x).max() + 1e-12)


def scrape(d, rough=1.0):
    """Something dragged or skidding over the ground: uneven grabs of mid noise (stick and slip with no steady rate),
    grit ticking in it. Unit RMS, dry."""
    n = n_of(d)
    g = np.clip(grains(d, 60.0 + 80.0 * rough, (0.004, 0.009, 0.02)), 0, 8) ** 1.3
    x = cband(rng().standard_normal(n), rng().uniform(250, 500), rng().uniform(1800, 3500), 2) * g
    x *= T.fade(n, 0.03, min(0.15, d * 0.4))
    return T.unit(x)


# ---------------------------------------------------------------------------------------------------- textures
def rustle(d, env, density=2500.0, lo=1400.0, hi=9000.0):
    """Leaves and twigs thrashing: a crackling granular texture, thousands of tiny leaf-on-leaf ticks a second at
    heavy-tailed sizes, coming in surges (`env`, one value a sample), its top pressed down where it thins. Not a
    filtered hiss: at these densities each tick is still heard as grain. Unit-ish level, dry."""
    n = n_of(d)
    env = np.asarray(env, float)
    x = np.zeros(n)
    peak = env.max() + 1e-9
    k = rng().poisson(density * d * float(env.mean() / peak))
    # (where they fall: as thick as the envelope is)
    cdf = np.cumsum(env) / np.sum(env)
    at = np.searchsorted(cdf, rng().random(k))
    np.add.at(x, np.clip(at, 0, n - 1), np.minimum(rng().pareto(2.4, k) * 0.35 + 0.05, 1.5) * rng().choice([-1.0, 1.0], k))
    # (each tick a little smeared: a leaf's flick, not a digital click)
    s = np.arange(n_of(0.004)) / SR
    x = np.convolve(x, np.exp(-s / 0.0006))[:n]
    x = cband(x, lo, hi, 2)
    # (and a soft rush of the whole crown under it, wandering)
    x += T.unit(cband(rng().standard_normal(n), lo * 0.6, hi * 0.6, 1)) * np.std(x) * 0.5 * wander(n, 1.0, 9.0, 4.0) * env / peak
    return x / (np.std(x) + 1e-12)


def soil_tear(d, env):
    """Roots ripping out of wet ground: earth crumbling and tearing in uneven grabs (low-mid grit), root fibres snapping
    muffled under it, a low heave. Unit-ish RMS, dry; `env` one value a sample."""
    n = n_of(d)
    g = np.clip(grains(d, 140.0, (0.006, 0.015, 0.04)), 0, 8) ** 1.4
    crumble = cband(rng().standard_normal(n), 90, 1300, 2) * g
    heave = T.unit(cband(rng().standard_normal(n), 25, 160, 2)) * wander(n, 1.5, 8.0, 5.0)
    x = T.unit(crumble) + heave * 0.7
    for t1 in PB_poisson(0.0, d - 0.05, lambda u: 30.0 * float(env[min(int(u * SR), n - 1)])):
        f = fracture(rng().uniform(0.4, 1.4), 0.7, dull=rng().uniform(0.5, 0.9))
        put(x, f * rng().uniform(0.6, 2.5), t1)
    return x * env


def buffet(d, env, deep=1.0):
    """Turbulent air shoving past: the low pressure buffeting of a gust or a body pushed through it (20-250 Hz,
    lurching in uneven surges), a broad low-mid rush boiling over it, a little of the top only at its strongest.
    No pitch and no sweep: its spectrum stays put, only its surges and its weight move. Dry, unit-ish."""
    n = n_of(d)
    env = np.asarray(env, float)
    surge = np.clip(grains(d, 22.0, (0.03, 0.07, 0.15)), 0, 6) ** 1.2
    low = T.unit(cband(rng().standard_normal(n), 18, 110 + 120 * deep, 2)) * surge * wander(n, 0.5, 4.0, 4.0)
    rush = T.unit(cband(rng().standard_normal(n), 120, 1400, 1)) * np.clip(grains(d, 45.0, (0.012, 0.03, 0.06)), 0, 6) * wander(n, 2.0, 12.0, 5.0)
    top = T.unit(cband(rng().standard_normal(n), 1200, 5000, 1)) * np.clip(grains(d, 70.0, (0.006, 0.015)), 0, 6)
    e = env / (env.max() + 1e-9)
    return low * 1.1 * e ** 0.8 * deep + rush * 0.5 * e ** 1.4 + top * 0.12 * e ** 3


def PB_poisson(t_lo, t_hi, rate_fn):
    """Event times at a rate (a second) that changes over time (sounds_payload's poisson_times, local)."""
    peak = max(rate_fn(t) for t in np.linspace(t_lo, t_hi, 128)) * 1.2 + 1e-9
    out, t = [], t_lo
    while True:
        t += rng().exponential(1.0 / peak)
        if t >= t_hi:
            return out
        if rng().random() < rate_fn(t) / peak:
            out.append(t)


# ---------------------------------------------------------------------------------------------------- the space
def space(x, wet=0.5, length=2.4, darken=(3200, 260), decay=0.9, ground=True, seed_shift=0):
    """`x` heard out in the open some way off: the ground's reflection a few ms behind it, the land's clumped echoes
    (sounds_themes' outdoor_ir), darker and later the further they come. Same length as `x`."""
    n = len(x)
    y = x.copy()
    if ground:
        dt = rng().uniform(0.003, 0.009)
        put(y, cband(x, None, 2500, 1) * rng().uniform(0.35, 0.6), dt)
    ir = T.outdoor_ir(length, seed_shift, density=45.0, darken=darken, decay=decay)
    m = n + len(ir)
    w = np.fft.irfft(np.fft.rfft(y, m) * np.fft.rfft(ir, m), m)[:n]
    return y + w * wet * np.std(y) / (np.std(w) + 1e-12)


def tame(x, over_db=9.0, ratio=4.0, att=0.0005, rel=0.1):
    """A recorder's gentle compression: what rises more than `over_db` over the sound's loud body (its loudest 400 ms)
    pulled down `ratio`:1, so the hits sit in the texture as they do on a field recording rather than spiking out of
    it."""
    from scipy.signal import lfilter
    a = np.exp(-1 / (0.001 * SR))
    det = np.sqrt(lfilter([1 - a], [1, -a], x ** 2)) + 1e-12
    thr = T.loudest(x) * 10 ** (over_db / 20)
    want = np.where(det > thr, (det / thr) ** (1 / ratio - 1), 1.0)
    g = np.empty(len(want))
    a_at, a_rel = np.exp(-1 / (att * SR)), np.exp(-1 / (rel * SR))
    st = 1.0
    for i, v in enumerate(want):
        st = v + (st - v) * (a_at if v < st else a_rel)
        g[i] = st
    return x * g
